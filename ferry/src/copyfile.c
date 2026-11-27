/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * copyfile(3) and fcopyfile(3) for Mac programs (freemac 1.232, Ferry
 * 0.56.0), written from the manual page. A file's data is copied with
 * copy_file_range (which clones it on a file system that can), its mode,
 * owner and times with COPYFILE_STAT, and its extended attributes with
 * COPYFILE_XATTR (Ferry keeps a Mac's in the user. namespace, so they are
 * copied as they are). Access control lists aren't kept. With
 * COPYFILE_RECURSIVE a folder is copied with all it holds; COPYFILE_MOVE
 * renames where it can and COPYFILE_UNLINK removes the original after.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <unistd.h>

#include "ferry.h"

#define MAC_AT_FDCWD (-2) /* a Mac's AT_FDCWD */

#define CF_ACL (1u << 0)
#define CF_STAT (1u << 1)
#define CF_XATTR (1u << 2)
#define CF_DATA (1u << 3)
#define CF_RECURSIVE (1u << 15)
#define CF_CHECK (1u << 16)
#define CF_EXCL (1u << 17)
#define CF_NOFOLLOW_SRC (1u << 18)
#define CF_NOFOLLOW_DST (1u << 19)
#define CF_MOVE (1u << 20)
#define CF_UNLINK (1u << 21)

/* What a copy records for copyfile_state_get: the two ends, the status
 * callback the program set (Ferry doesn't call it: a copy runs to the end
 * in one go) and how many bytes of data were copied. */
struct copyfile_state {
    int src_fd, dst_fd;
    char *src_name, *dst_name;
    void *status_cb, *status_ctx;
    int64_t copied;
};

#define STATE_SRC_FD 1
#define STATE_SRC_FILENAME 2
#define STATE_DST_FD 3
#define STATE_DST_FILENAME 4
#define STATE_QUARANTINE 5
#define STATE_STATUS_CB 6
#define STATE_STATUS_CTX 7
#define STATE_COPIED 8
#define STATE_XATTRNAME 9
#define STATE_WAS_CLONED 10

static void *mac_copyfile_state_alloc(void)
{
    struct copyfile_state *s = calloc(1, sizeof *s);
    if (s)
        s->src_fd = s->dst_fd = -1;
    return s;
}

static int mac_copyfile_state_free(void *p)
{
    struct copyfile_state *s = p;
    if (s) {
        free(s->src_name);
        free(s->dst_name);
    }
    free(s);
    return 0;
}

static void set_name(char **slot, const char *name)
{
    free(*slot);
    *slot = name ? strdup(name) : NULL;
}

static int mac_copyfile_state_get(void *p, uint32_t flag, void *dst)
{
    struct copyfile_state *s = p;
    if (!s || !dst) {
        errno = EINVAL;
        return -1;
    }
    switch (flag) {
    case STATE_SRC_FD: *(int *)dst = s->src_fd; return 0;
    case STATE_DST_FD: *(int *)dst = s->dst_fd; return 0;
    case STATE_SRC_FILENAME: *(const char **)dst = s->src_name; return 0;
    case STATE_DST_FILENAME: *(const char **)dst = s->dst_name; return 0;
    case STATE_STATUS_CB: *(void **)dst = s->status_cb; return 0;
    case STATE_STATUS_CTX: *(void **)dst = s->status_ctx; return 0;
    case STATE_COPIED: *(int64_t *)dst = s->copied; return 0;
    case STATE_XATTRNAME: *(const char **)dst = NULL; return 0;
    case STATE_WAS_CLONED: *(_Bool *)dst = 0; return 0;
    case STATE_QUARANTINE: *(void **)dst = NULL; return 0;
    }
    errno = EINVAL;
    return -1;
}

static int mac_copyfile_state_set(void *p, uint32_t flag, const void *src)
{
    struct copyfile_state *s = p;
    if (!s || (!src && flag != STATE_STATUS_CB && flag != STATE_STATUS_CTX && flag != STATE_QUARANTINE)) {
        errno = EINVAL;
        return -1;
    }
    switch (flag) {
    case STATE_SRC_FD: s->src_fd = *(const int *)src; return 0;
    case STATE_DST_FD: s->dst_fd = *(const int *)src; return 0;
    case STATE_SRC_FILENAME: set_name(&s->src_name, src); return 0;
    case STATE_DST_FILENAME: set_name(&s->dst_name, src); return 0;
    case STATE_STATUS_CB: s->status_cb = (void *)src; return 0;
    case STATE_STATUS_CTX: s->status_ctx = (void *)src; return 0;
    case STATE_QUARANTINE: return 0;
    }
    errno = EINVAL;
    return -1;
}

/* After a copy: how much data the destination now holds. */
static void note_copied(struct copyfile_state *s, int to)
{
    struct stat st;
    if (s && to >= 0 && fstat(to, &st) == 0 && S_ISREG(st.st_mode))
        s->copied = st.st_size;
}

static int copy_data(int from, int to)
{
    if (lseek(from, 0, SEEK_SET) < 0 || lseek(to, 0, SEEK_SET) < 0 || ftruncate(to, 0) < 0)
        return -1;
    for (;;) {
        ssize_t n = copy_file_range(from, NULL, to, NULL, 1 << 30, 0);
        if (n == 0)
            return 0;
        if (n > 0)
            continue;
        if (errno == EINTR)
            continue;
        if (errno != EXDEV && errno != EINVAL && errno != ENOSYS && errno != EOPNOTSUPP)
            return -1;
        break; /* not between these two: copy by hand from where it stopped */
    }
    char buf[1 << 16];
    for (;;) {
        ssize_t n = read(from, buf, sizeof buf);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return (int)n;
        for (ssize_t done = 0; done < n;) {
            ssize_t w = write(to, buf + done, (size_t)(n - done));
            if (w < 0 && errno == EINTR)
                continue;
            if (w < 0)
                return -1;
            done += w;
        }
    }
}

static int copy_xattrs(int from, int to)
{
    ssize_t len = flistxattr(from, NULL, 0);
    if (len <= 0)
        return 0;
    char *names = malloc((size_t)len);
    if (!names || (len = flistxattr(from, names, (size_t)len)) < 0) {
        free(names);
        return 0;
    }
    for (char *n = names; n < names + len; n += strlen(n) + 1) {
        if (strncmp(n, "user.", 5))
            continue;
        ssize_t vlen = fgetxattr(from, n, NULL, 0);
        if (vlen < 0)
            continue;
        void *v = malloc((size_t)vlen + 1);
        if (v && (vlen = fgetxattr(from, n, v, (size_t)vlen)) >= 0)
            fsetxattr(to, n, v, (size_t)vlen, 0);
        free(v);
    }
    free(names);
    return 0;
}

static int copy_stat(int from, int to)
{
    struct stat st;
    if (fstat(from, &st) < 0)
        return -1;
    /* the owner only for root; anyone may try to keep the group */
    if (fchown(to, st.st_uid, st.st_gid) < 0)
        (void)!fchown(to, (uid_t)-1, st.st_gid);
    if (fchmod(to, st.st_mode & 07777) < 0)
        return -1;
    struct timespec t[2] = {st.st_atim, st.st_mtim};
    return futimens(to, t);
}

static int fd_copy(int from, int to, uint32_t flags)
{
    struct stat st;
    if (fstat(from, &st) < 0)
        return -1;
    if ((flags & CF_DATA) && S_ISREG(st.st_mode) && copy_data(from, to) < 0)
        return -1;
    if ((flags & CF_XATTR) && copy_xattrs(from, to) < 0)
        return -1;
    if ((flags & CF_STAT) && copy_stat(from, to) < 0)
        return -1;
    return 0;
}

static int mac_fcopyfile(int from, int to, void *state, uint32_t flags)
{
    struct copyfile_state *s = state;
    if (flags & CF_CHECK)
        return (int)(flags & (CF_STAT | CF_XATTR | CF_DATA));
    if (s) {
        s->src_fd = from;
        s->dst_fd = to;
    }
    if (fd_copy(from, to, flags) < 0)
        return -1;
    note_copied(s, to);
    return 0;
}

static int path_copy(const char *from, const char *to, uint32_t flags);

static int copy_folder(const char *from, const char *to, uint32_t flags, const struct stat *st)
{
    if (mkdir(to, (st->st_mode & 07777) | 0700) < 0 && (errno != EEXIST || (flags & CF_EXCL)))
        return -1;
    if (flags & CF_RECURSIVE) {
        DIR *d = opendir(from);
        if (!d)
            return -1;
        struct dirent *e;
        int r = 0;
        while (!r && (e = readdir(d))) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
                continue;
            char a[PATH_MAX], b[PATH_MAX];
            if (snprintf(a, sizeof a, "%s/%s", from, e->d_name) >= (int)sizeof a ||
                snprintf(b, sizeof b, "%s/%s", to, e->d_name) >= (int)sizeof b) {
                errno = ENAMETOOLONG;
                r = -1;
                break;
            }
            /* what a folder holds is copied as it is, links as links */
            r = path_copy(a, b, (flags & ~(CF_MOVE | CF_UNLINK)) | CF_NOFOLLOW_SRC);
        }
        closedir(d);
        if (r)
            return -1;
    }
    int f = open(from, O_RDONLY | O_DIRECTORY), t = open(to, O_RDONLY | O_DIRECTORY);
    int r = f >= 0 && t >= 0 ? fd_copy(f, t, flags & ~CF_DATA) : -1;
    if (f >= 0)
        close(f);
    if (t >= 0)
        close(t);
    return r;
}

static int path_copy(const char *from, const char *to, uint32_t flags)
{
    struct stat st;
    if (((flags & CF_NOFOLLOW_SRC) ? lstat(from, &st) : stat(from, &st)) < 0)
        return -1;
    if (S_ISDIR(st.st_mode))
        return copy_folder(from, to, flags, &st);
    if (S_ISLNK(st.st_mode)) {
        char target[PATH_MAX];
        ssize_t n = readlink(from, target, sizeof target - 1);
        if (n < 0)
            return -1;
        target[n] = 0;
        if (!(flags & CF_EXCL))
            unlink(to);
        return symlink(target, to);
    }
    int f = open(from, O_RDONLY | O_CLOEXEC);
    if (f < 0)
        return -1;
    int oflags = O_WRONLY | O_CREAT | O_CLOEXEC | ((flags & CF_EXCL) ? O_EXCL : 0) |
                 ((flags & CF_NOFOLLOW_DST) ? O_NOFOLLOW : 0);
    int t = open(to, oflags, st.st_mode & 07777);
    if (t < 0) {
        int e = errno;
        close(f);
        errno = e;
        return -1;
    }
    int r = fd_copy(f, t, flags);
    int e = errno;
    close(f);
    close(t);
    errno = e;
    return r;
}

static int mac_copyfile(const char *from, const char *to, void *state, uint32_t flags)
{
    struct copyfile_state *s = state;
    if (!from || !to) {
        errno = EINVAL;
        return -1;
    }
    if (s) {
        set_name(&s->src_name, from);
        set_name(&s->dst_name, to);
    }
    if (flags & CF_CHECK)
        return (int)(flags & (CF_STAT | CF_XATTR | CF_DATA));
    if (flags & CF_MOVE) {
        if (!(flags & CF_EXCL) || access(to, F_OK) < 0) {
            if (rename(from, to) == 0)
                return 0;
            if (errno != EXDEV)
                return -1;
        }
        flags |= CF_UNLINK;
    }
    if (path_copy(from, to, flags) < 0)
        return -1;
    struct stat done;
    if (s && stat(to, &done) == 0 && S_ISREG(done.st_mode))
        s->copied = done.st_size;
    if (flags & CF_UNLINK) {
        struct stat st;
        if (lstat(from, &st) == 0 && S_ISDIR(st.st_mode))
            return rmdir(from) < 0 && errno != ENOTEMPTY ? -1 : 0;
        return unlink(from);
    }
    return 0;
}

/* clonefile(2): a copy that shares the original's blocks until either is
 * changed. Where the disk can (btrfs, XFS) the file is cloned with FICLONE;
 * elsewhere, and for folders, it fails with ENOTSUP, which tells Mac
 * programs to copy the usual way. The new file mustn't exist yet. */
#define CLONE_NOFOLLOW 0x1
#define CLONE_NOOWNERCOPY 0x2

static int clone_fd(int src, int dirfd, const char *to, uint32_t flags)
{
    struct stat st;
    if (fstat(src, &st) < 0)
        return -1;
    if (!S_ISREG(st.st_mode)) {
        errno = EOPNOTSUPP;
        return -1;
    }
    int t = openat(dirfd, to, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, st.st_mode & 07777);
    if (t < 0)
        return -1;
    if (ioctl(t, FICLONE, src) < 0) {
        close(t);
        unlinkat(dirfd, to, 0);
        errno = EOPNOTSUPP;
        return -1;
    }
    if (!(flags & CLONE_NOOWNERCOPY) && fchown(t, st.st_uid, st.st_gid) < 0) {
        /* not the owner: the clone stays the caller's, as on a Mac */
    }
    struct timespec times[2] = {st.st_atim, st.st_mtim};
    futimens(t, times);
    close(t);
    return 0;
}

static int mac_fclonefileat(int src, int dirfd, const char *to, uint32_t flags)
{
    return clone_fd(src, dirfd == MAC_AT_FDCWD ? AT_FDCWD : dirfd, to, flags);
}

static int mac_clonefileat(int srcdir, const char *from, int dstdir, const char *to, uint32_t flags)
{
    int f = openat(srcdir == MAC_AT_FDCWD ? AT_FDCWD : srcdir, from,
                   O_RDONLY | O_CLOEXEC | ((flags & CLONE_NOFOLLOW) ? O_NOFOLLOW : 0));
    if (f < 0)
        return -1;
    int r = clone_fd(f, dstdir == MAC_AT_FDCWD ? AT_FDCWD : dstdir, to, flags);
    int e = errno;
    close(f);
    errno = e;
    return r;
}

static int mac_clonefile(const char *from, const char *to, uint32_t flags)
{
    return mac_clonefileat(MAC_AT_FDCWD, from, MAC_AT_FDCWD, to, flags);
}

const struct ferry_symbol ferry_copyfile_symbols[] = {
    {"copyfile", mac_copyfile},
    {"fcopyfile", mac_fcopyfile},
    {"copyfile_state_alloc", mac_copyfile_state_alloc},
    {"copyfile_state_free", mac_copyfile_state_free},
    {"copyfile_state_get", mac_copyfile_state_get},
    {"copyfile_state_set", mac_copyfile_state_set},
    {"clonefile", mac_clonefile},
    {"clonefileat", mac_clonefileat},
    {"fclonefileat", mac_fclonefileat},
    {NULL, NULL},
};
