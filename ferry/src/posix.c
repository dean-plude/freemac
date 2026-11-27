/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * POSIX calls whose numbers or structures differ between macOS and Linux:
 * file flags, stat and directory entries, memory maps, clocks, signals,
 * system limits and a few others. Each converts the Mac form to this
 * system's, calls the real function, and converts the answer back.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <ucontext.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <locale.h>
#include <pthread.h>
#include <pwd.h>
#include <signal.h>
#include <sched.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/ipc.h>
#include <sys/resource.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <spawn.h>
#include <dirent.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"

/* ---- open flags ------------------------------------------------------------------ */

static const struct { int mac, lnx; } open_bits[] = {
    {0x0004, O_NONBLOCK}, {0x0008, O_APPEND}, {0x0080, O_SYNC}, {0x0100, O_NOFOLLOW},
    {0x0200, O_CREAT}, {0x0400, O_TRUNC}, {0x0800, O_EXCL}, {0x20000, O_NOCTTY},
    {0x100000, O_DIRECTORY}, {0x400000, O_DSYNC}, {0x1000000, O_CLOEXEC},
};
#define NBITS (sizeof open_bits / sizeof open_bits[0])

static int open_to_linux(int mac)
{
    int out = mac & O_ACCMODE;
    for (size_t i = 0; i < NBITS; i++)
        if (mac & open_bits[i].mac)
            out |= open_bits[i].lnx;
    return out;
}

/* for dispatch I/O's paths (src/objc/dispatch_io.c) */
int ferry_open_flags_from_mac(int mac) { return open_to_linux(mac); }

static int open_to_mac(int lnx)
{
    int out = lnx & O_ACCMODE;
    for (size_t i = 0; i < NBITS; i++)
        if ((lnx & open_bits[i].lnx) == open_bits[i].lnx)
            out |= open_bits[i].mac;
    return out;
}

#define MAC_AT_FDCWD -2
#define MAC_AT_SYMLINK_NOFOLLOW 0x20
#define MAC_AT_REMOVEDIR 0x80

static int at_fd(int fd) { return fd == MAC_AT_FDCWD ? AT_FDCWD : fd; }

/* O_EVTONLY opens a file only to watch it (with kqueue's EVFILT_VNODE):
 * read-only, or, where the file can't be read, as a path (O_PATH), which
 * fstat and inotify still take. */
#define MAC_O_EVTONLY 0x8000
static int evtonly_open(int fd, const char *path, int flags)
{
    int lf = open_to_linux(flags & ~(MAC_O_EVTONLY | O_ACCMODE));
    int r = openat(fd, path, lf | O_RDONLY);
    if (r < 0 && (errno == EACCES || errno == EPERM))
        r = openat(fd, path, (lf & (O_NOFOLLOW | O_CLOEXEC | O_DIRECTORY)) | O_PATH);
    return r;
}

/* O_SYMLINK opens a symbolic link itself rather than what it points to
 * (freemac 1.223, Ferry 0.47.0): anything else is opened as asked, and a
 * link, which Linux can't open for reading or writing, as a path
 * (O_PATH), which fstat and fchown take. */
#define MAC_O_SYMLINK 0x200000
static int symlink_open(int fd, const char *path, int flags, mode_t mode)
{
    int lf = open_to_linux(flags & ~MAC_O_SYMLINK);
    int r = openat(fd, path, lf | O_NOFOLLOW, mode);
    if (r < 0 && errno == ELOOP)
        r = openat(fd, path, (lf & O_CLOEXEC) | O_PATH | O_NOFOLLOW);
    return r;
}

/* fchown takes a descriptor opened as a path (above) too, as a Mac's takes a link's. */
static int mac_fchown(int fd, uid_t owner, gid_t group)
{
    int r = fchown(fd, owner, group);
    if (r < 0 && errno == EBADF)
        r = fchownat(fd, "", owner, group, AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW);
    return r;
}

/* O_NOFOLLOW_ANY (freemac 1.224, Ferry 0.48.0) follows no symbolic link
 * anywhere in the path, as Linux's openat2 does with RESOLVE_NO_SYMLINKS. */
#define MAC_O_NOFOLLOW_ANY 0x20000000
struct linux_open_how { uint64_t flags, mode, resolve; };
#define LINUX_RESOLVE_NO_SYMLINKS 0x04
static int nofollow_any_open(int fd, const char *path, int flags, mode_t mode)
{
    struct linux_open_how how = {(uint64_t)open_to_linux(flags & ~MAC_O_NOFOLLOW_ANY),
                                 (flags & 0x200) ? (uint64_t)mode : 0, LINUX_RESOLVE_NO_SYMLINKS};
    return (int)syscall(SYS_openat2, fd, path, &how, sizeof how);
}

/* qsort_r(3) on a Mac takes its context before the comparison, and passes
 * it first; the C library here takes them the other way round (1.267). */
struct mac_qsort_ctx { void *thunk; int (*cmp)(void *, const void *, const void *); };
static int mac_qsort_cmp(const void *a, const void *b, void *arg)
{
    struct mac_qsort_ctx *c = arg;
    return c->cmp(c->thunk, a, b);
}
static void mac_qsort_r(void *base, size_t n, size_t size, void *thunk, int (*cmp)(void *, const void *, const void *))
{
    struct mac_qsort_ctx c = {thunk, cmp};
    qsort_r(base, n, size, mac_qsort_cmp, &c);
}

/* POSIX shared memory (shm_open(2)): a Mac's open flags, and the mode only
 * when it creates (freemac 1.267; FreeCAD's Qt shares a memory segment). */
static int mac_shm_open(const char *name, int flags, ...)
{
    mode_t mode = 0;
    if (flags & 0x200) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    return shm_open(name, open_to_linux(flags), mode);
}

static int mac_open(const char *path, int flags, ...)
{
    char font[PATH_MAX];
    path = ferry_font_path(path, font, sizeof font);
    mode_t mode = 0;
    if (flags & 0x200) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    if (ferry_is_virtual(path))
        return ferry_virtual_open(path, open_to_linux(flags));
    if (flags & MAC_O_EVTONLY)
        return evtonly_open(AT_FDCWD, path, flags);
    if (flags & MAC_O_SYMLINK)
        return symlink_open(AT_FDCWD, path, flags, mode);
    if (flags & MAC_O_NOFOLLOW_ANY)
        return nofollow_any_open(AT_FDCWD, path, flags, mode);
    return open(path, open_to_linux(flags), mode);
}

static int mac_openat(int fd, const char *path, int flags, ...)
{
    char font[PATH_MAX];
    path = ferry_font_path(path, font, sizeof font);
    mode_t mode = 0;
    if (flags & 0x200) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    if (ferry_is_virtual(path))
        return ferry_virtual_open(path, open_to_linux(flags));
    if (flags & MAC_O_EVTONLY)
        return evtonly_open(at_fd(fd), path, flags);
    if (flags & MAC_O_SYMLINK)
        return symlink_open(at_fd(fd), path, flags, mode);
    if (flags & MAC_O_NOFOLLOW_ANY)
        return nofollow_any_open(at_fd(fd), path, flags, mode);
    return openat(at_fd(fd), path, open_to_linux(flags), mode);
}

/* renamex_np and renameatx_np (freemac 1.224, Ferry 0.48.0): RENAME_SWAP
 * exchanges the two items and RENAME_EXCL keeps an existing destination, as
 * Linux's renameat2 does with RENAME_EXCHANGE and RENAME_NOREPLACE;
 * RENAME_NOFOLLOW_ANY refuses (ELOOP) a path whose folders hold a symbolic
 * link, which is checked by opening each item's folder that way. */
#define MAC_RENAME_SWAP 0x2
#define MAC_RENAME_EXCL 0x4
#define MAC_RENAME_NOFOLLOW_ANY 0x10
#define LINUX_RENAME_NOREPLACE 1
#define LINUX_RENAME_EXCHANGE 2
static int no_link_in_folders(int fd, const char *path)
{
    char folder[PATH_MAX];
    const char *slash = strrchr(path, '/');
    if (!slash)
        return 0;
    size_t n = slash == path ? 1 : (size_t)(slash - path);
    if (n >= sizeof folder) {
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(folder, path, n);
    folder[n] = 0;
    struct linux_open_how how = {O_PATH | O_DIRECTORY, 0, LINUX_RESOLVE_NO_SYMLINKS};
    int d = (int)syscall(SYS_openat2, fd, folder, &how, sizeof how);
    if (d < 0)
        return -1;
    close(d);
    return 0;
}
static int mac_renameatx_np(int fromfd, const char *from, int tofd, const char *to, unsigned flags)
{
    if (flags & ~(unsigned)(MAC_RENAME_SWAP | MAC_RENAME_EXCL | MAC_RENAME_NOFOLLOW_ANY)) {
        errno = EINVAL;
        return -1;
    }
    if ((flags & MAC_RENAME_NOFOLLOW_ANY) &&
        (no_link_in_folders(at_fd(fromfd), from) < 0 || no_link_in_folders(at_fd(tofd), to) < 0))
        return -1;
    unsigned lf = ((flags & MAC_RENAME_SWAP) ? LINUX_RENAME_EXCHANGE : 0) |
                  ((flags & MAC_RENAME_EXCL) ? LINUX_RENAME_NOREPLACE : 0);
    return (int)syscall(SYS_renameat2, at_fd(fromfd), from, at_fd(tofd), to, lf);
}
/* utimes, futimes and lutimes (freemac 1.224, Ferry 0.48.0): a Mac's
 * struct timeval keeps its microseconds in 32 bits, followed by padding,
 * where Linux's keeps them in a long. */
struct mac_timeval { int64_t tv_sec; int32_t tv_usec; int32_t pad; };
static const struct timeval *linux_times(const struct mac_timeval *m, struct timeval out[2])
{
    if (!m)
        return NULL;
    for (int i = 0; i < 2; i++) {
        out[i].tv_sec = (time_t)m[i].tv_sec;
        out[i].tv_usec = m[i].tv_usec;
    }
    return out;
}
static int mac_utimes(const char *path, const struct mac_timeval *m)
{
    struct timeval t[2];
    return utimes(path, linux_times(m, t));
}
static int mac_futimes(int fd, const struct mac_timeval *m)
{
    struct timeval t[2];
    return futimes(fd, linux_times(m, t));
}
static int mac_lutimes(const char *path, const struct mac_timeval *m)
{
    struct timeval t[2];
    return lutimes(path, linux_times(m, t));
}
static int mac_renameat(int fromfd, const char *from, int tofd, const char *to)
{
    return renameat(at_fd(fromfd), from, at_fd(tofd), to);
}
static int mac_renamex_np(const char *from, const char *to, unsigned flags)
{
    return mac_renameatx_np(MAC_AT_FDCWD, from, MAC_AT_FDCWD, to, flags);
}

static int mac_creat(const char *path, mode_t mode) { return creat(path, mode); }

static int mac_unlinkat(int fd, const char *path, int flags)
{
    return unlinkat(at_fd(fd), path, (flags & MAC_AT_REMOVEDIR) ? AT_REMOVEDIR : 0);
}

static int mac_mkdirat(int fd, const char *path, mode_t mode) { return mkdirat(at_fd(fd), path, mode); }

/* Record locks: different command numbers, lock types and field order. */
struct mac_flock { int64_t start, len; int32_t pid; int16_t type, whence; };
#define MAC_F_GETLK 7
#define MAC_F_SETLK 8
#define MAC_F_SETLKW 9
#define MAC_F_FULLFSYNC 51
#define MAC_F_DUPFD_CLOEXEC 67

static int lock_type_to_linux(int t) { return t == 1 ? F_RDLCK : t == 3 ? F_WRLCK : F_UNLCK; }
static int lock_type_to_mac(int t) { return t == F_RDLCK ? 1 : t == F_WRLCK ? 3 : 2; }

static int mac_fcntl(int fd, int cmd, ...)
{
    va_list ap;
    va_start(ap, cmd);
    long arg = va_arg(ap, long);
    va_end(ap);
    switch (cmd) {
    case 0: /* F_DUPFD */
    case 1: /* F_GETFD */
    case 2: /* F_SETFD: FD_CLOEXEC is 1 on both */
        return fcntl(fd, cmd, arg);
    case 3: { /* F_GETFL */
        int rc = fcntl(fd, F_GETFL);
        return rc < 0 ? rc : open_to_mac(rc);
    }
    case 4: /* F_SETFL */
        return fcntl(fd, F_SETFL, open_to_linux((int)arg));
    case MAC_F_DUPFD_CLOEXEC:
        return fcntl(fd, F_DUPFD_CLOEXEC, arg);
    case MAC_F_FULLFSYNC:
        return fsync(fd);
    case MAC_F_GETLK:
    case MAC_F_SETLK:
    case MAC_F_SETLKW: {
        struct mac_flock *m = (void *)arg;
        struct flock l = {.l_type = lock_type_to_linux(m->type), .l_whence = m->whence,
                          .l_start = m->start, .l_len = m->len, .l_pid = m->pid};
        int rc = fcntl(fd, cmd == MAC_F_GETLK ? F_GETLK : cmd == MAC_F_SETLK ? F_SETLK : F_SETLKW, &l);
        if (rc == 0 && cmd == MAC_F_GETLK) {
            m->type = lock_type_to_mac(l.l_type);
            m->whence = l.l_whence;
            m->start = l.l_start;
            m->len = l.l_len;
            m->pid = l.l_pid;
        }
        return rc;
    }
    default:
        errno = EINVAL;
        return -1;
    }
}

/* ---- stat --------------------------------------------------------------------------
 * The 64-bit-inode struct stat that Mac programs for Intel use (the "$INODE64"
 * variants of the calls). */

struct mac_timespec { int64_t sec, nsec; };
struct mac_stat {
    int32_t dev;
    uint16_t mode, nlink;
    uint64_t ino;
    uint32_t uid, gid;
    int32_t rdev;
    struct mac_timespec atime, mtime, ctime, birthtime;
    int64_t size, blocks;
    int32_t blksize;
    uint32_t flags, gen;
    int32_t lspare;
    int64_t qspare[2];
};
_Static_assert(sizeof(struct mac_stat) == 144, "Mac struct stat is 144 bytes");
_Static_assert(__builtin_offsetof(struct mac_stat, size) == 96, "st_size offset");

static int32_t mac_dev(dev_t d) { return (int32_t)((major(d) << 24) | (minor(d) & 0xffffff)); }

static void to_mac_stat(const struct stat *s, struct mac_stat *m)
{
    memset(m, 0, sizeof *m);
    m->dev = mac_dev(s->st_dev);
    m->mode = s->st_mode;
    m->nlink = s->st_nlink > 0xffff ? 0xffff : s->st_nlink;
    m->ino = s->st_ino;
    m->uid = s->st_uid;
    m->gid = s->st_gid;
    m->rdev = mac_dev(s->st_rdev);
    m->atime = (struct mac_timespec){s->st_atim.tv_sec, s->st_atim.tv_nsec};
    m->mtime = (struct mac_timespec){s->st_mtim.tv_sec, s->st_mtim.tv_nsec};
    m->ctime = (struct mac_timespec){s->st_ctim.tv_sec, s->st_ctim.tv_nsec};
    m->birthtime = m->ctime; /* Linux's stat has no creation time */
    m->size = s->st_size;
    m->blocks = s->st_blocks;
    m->blksize = s->st_blksize;
}

/* For the calls elsewhere that answer a Mac struct stat (fts in libc_more.c). */
void ferry_to_mac_stat(const struct stat *s, void *out) { to_mac_stat(s, out); }

#define STAT_WRAPPER(name, call)                                   \
    static int name                                                \
    {                                                              \
        struct stat s;                                             \
        int rc = call;                                             \
        if (rc == 0)                                               \
            to_mac_stat(&s, out);                                  \
        return rc;                                                 \
    }

/* The Mac's version file is one Ferry makes (sysversion.c). */
#define VIRTUAL_OR(path, call) (ferry_virtual_stat(path, &s) ? 0 : (call))
/* A font in a Mac Fonts folder is a link in Ferry's (fonts.c), and a file to
 * the program, as on a Mac: lstat follows it. */
static int font_stat(const char *path, struct stat *s, int follow)
{
    char font[PATH_MAX];
    const char *p = ferry_font_path(path, font, sizeof font);
    return p != path ? stat(p, s) : follow ? stat(path, s) : lstat(path, s);
}
STAT_WRAPPER(mac_stat64(const char *path, struct mac_stat *out), VIRTUAL_OR(path, font_stat(path, &s, 1)))
STAT_WRAPPER(mac_lstat64(const char *path, struct mac_stat *out), VIRTUAL_OR(path, font_stat(path, &s, 0)))
STAT_WRAPPER(mac_fstat64(int fd, struct mac_stat *out), fstat(fd, &s))
STAT_WRAPPER(mac_fstatat64(int fd, const char *path, struct mac_stat *out, int flags),
             VIRTUAL_OR(path, path && path[0] == '/' ? font_stat(path, &s, !(flags & MAC_AT_SYMLINK_NOFOLLOW))
                                  : fstatat(at_fd(fd), path, &s, (flags & MAC_AT_SYMLINK_NOFOLLOW) ? AT_SYMLINK_NOFOLLOW : 0)))

/* access's mode bits are the same on both systems (R_OK 4, W_OK 2, X_OK 1). */
static int mac_access(const char *path, int mode)
{
    if (ferry_is_virtual(path)) {
        if (mode & (W_OK | X_OK)) {
            errno = EACCES;
            return -1;
        }
        return 0;
    }
    char font[PATH_MAX];
    return access(ferry_font_path(path, font, sizeof font), mode);
}

/* ---- directories ------------------------------------------------------------------- */

struct mac_dirent {
    uint64_t ino, seekoff;
    uint16_t reclen, namlen;
    uint8_t type;
    char name[1024];
};

struct mac_DIR {
    int fd; /* Mac headers may read the descriptor from the start of DIR */
    DIR *dir;
    struct mac_dirent entry;
};

static struct mac_DIR *wrap_dir(DIR *d)
{
    if (!d)
        return NULL;
    struct mac_DIR *m = calloc(1, sizeof *m);
    if (!m) {
        closedir(d);
        errno = ENOMEM;
        return NULL;
    }
    m->dir = d;
    m->fd = dirfd(d);
    return m;
}

static struct mac_DIR *mac_opendir(const char *path)
{
    char font[PATH_MAX];
    return wrap_dir(opendir(ferry_font_path(path, font, sizeof font)));
}
static struct mac_DIR *mac_fdopendir(int fd) { return wrap_dir(fdopendir(fd)); }

static struct mac_dirent *mac_readdir(struct mac_DIR *m)
{
    struct dirent *e = readdir(m->dir);
    if (!e)
        return NULL;
    size_t len = strlen(e->d_name); /* at most 255 on Linux */
    m->entry.ino = e->d_ino;
    m->entry.seekoff = e->d_off;
    m->entry.namlen = len;
    m->entry.type = e->d_type;
    m->entry.reclen = (uint16_t)((__builtin_offsetof(struct mac_dirent, name) + len + 1 + 3) & ~3u);
    memcpy(m->entry.name, e->d_name, len);
    m->entry.name[len] = 0;
    return &m->entry;
}

/* readdir_r(3): the next entry copied into the caller's Mac dirent, or
 * *result NULL at the end. */
static int mac_readdir_r(struct mac_DIR *m, struct mac_dirent *entry, struct mac_dirent **result)
{
    int saved = errno;
    errno = 0;
    struct mac_dirent *e = mac_readdir(m);
    if (!e) {
        *result = NULL;
        int err = errno;
        errno = saved;
        return err;
    }
    memcpy(entry, e, __builtin_offsetof(struct mac_dirent, name) + e->namlen + 1);
    *result = entry;
    errno = saved;
    return 0;
}

static int mac_closedir(struct mac_DIR *m)
{
    int rc = closedir(m->dir);
    free(m);
    return rc;
}

static void mac_rewinddir(struct mac_DIR *m) { rewinddir(m->dir); }

/* scandir(3) (freemac 1.221, Ferry 0.45.0): each entry is copied out in
 * the Mac's layout, as long as its own record says, and sorted with the
 * program's comparison, which is handed the Mac entries. */
static int mac_alphasort(const struct mac_dirent **a, const struct mac_dirent **b)
{
    return strcoll((*a)->name, (*b)->name);
}

static int (*scandir_compare)(const struct mac_dirent **, const struct mac_dirent **);
static int scandir_trampoline(const void *a, const void *b)
{
    return scandir_compare((const struct mac_dirent **)a, (const struct mac_dirent **)b);
}

static int mac_scandir(const char *path, struct mac_dirent ***out, int (*select)(const struct mac_dirent *),
                       int (*compare)(const struct mac_dirent **, const struct mac_dirent **))
{
    static pthread_mutex_t sort_lock = PTHREAD_MUTEX_INITIALIZER;
    struct mac_DIR *d = mac_opendir(path);
    if (!d)
        return -1;
    struct mac_dirent **list = NULL;
    size_t n = 0, cap = 0;
    struct mac_dirent *e;
    while ((e = mac_readdir(d))) {
        if (select && !select(e))
            continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 32;
            struct mac_dirent **bigger = realloc(list, cap * sizeof *list);
            if (!bigger)
                goto nomem;
            list = bigger;
        }
        struct mac_dirent *copy = malloc(e->reclen);
        if (!copy)
            goto nomem;
        memcpy(copy, e, e->reclen);
        list[n++] = copy;
    }
    mac_closedir(d);
    if (compare && n > 1) {
        pthread_mutex_lock(&sort_lock);
        scandir_compare = compare;
        qsort(list, n, sizeof *list, scandir_trampoline);
        pthread_mutex_unlock(&sort_lock);
    }
    *out = list;
    return (int)n;
nomem:
    while (n)
        free(list[--n]);
    free(list);
    mac_closedir(d);
    errno = ENOMEM;
    return -1;
}
static int mac_dirfd(struct mac_DIR *m) { return m->fd; }
static long mac_telldir(struct mac_DIR *m) { return telldir(m->dir); }
static void mac_seekdir(struct mac_DIR *m, long pos) { seekdir(m->dir, pos); }

/* ---- memory maps and clocks --------------------------------------------------------- */

static void *mac_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
    int lf = flags & 0x3;                 /* MAP_SHARED / MAP_PRIVATE */
    if (flags & 0x0010) lf |= MAP_FIXED;
    if (flags & 0x0040) lf |= MAP_NORESERVE;
    if (flags & 0x1000) lf |= MAP_ANONYMOUS;
    return mmap(addr, len, prot, lf, (flags & 0x1000) ? -1 : fd, off);
}

static clockid_t clock_to_linux(int c)
{
    switch (c) {
    case 0: return CLOCK_REALTIME;
    case 4: case 5: return CLOCK_MONOTONIC_RAW;
    case 6: case 8: case 9: return CLOCK_MONOTONIC;
    case 12: return CLOCK_PROCESS_CPUTIME_ID;
    case 16: return CLOCK_THREAD_CPUTIME_ID;
    default: return (clockid_t)-1;
    }
}

static int mac_clock_gettime(int c, struct timespec *ts)
{
    clockid_t id = clock_to_linux(c);
    if (id == (clockid_t)-1) {
        errno = EINVAL;
        return -1;
    }
    return clock_gettime(id, ts);
}

static int mac_clock_getres(int c, struct timespec *ts)
{
    clockid_t id = clock_to_linux(c);
    if (id == (clockid_t)-1) {
        errno = EINVAL;
        return -1;
    }
    return clock_getres(id, ts);
}

static uint64_t mac_clock_gettime_nsec_np(int c)
{
    struct timespec ts;
    if (mac_clock_gettime(c, &ts) < 0)
        return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

/* ---- signals ----------------------------------------------------------------------- */

static const int mac_to_linux_sig[32] = {
    0, SIGHUP, SIGINT, SIGQUIT, SIGILL, SIGTRAP, SIGABRT, 0 /* EMT */, SIGFPE, SIGKILL,
    SIGBUS, SIGSEGV, SIGSYS, SIGPIPE, SIGALRM, SIGTERM, SIGURG, SIGSTOP, SIGTSTP, SIGCONT,
    SIGCHLD, SIGTTIN, SIGTTOU, SIGIO, SIGXCPU, SIGXFSZ, SIGVTALRM, SIGPROF, SIGWINCH,
    0 /* INFO */, SIGUSR1, SIGUSR2,
};

/* for posix_spawn's open actions (libc_apps.c; freemac 1.233) */
int ferry_open_flags_to_linux(int mac) { return open_to_linux(mac); }

int ferry_signal_to_linux(int s) { return s > 0 && s < 32 ? mac_to_linux_sig[s] : 0; }

int ferry_signal_to_mac(int s)
{
    for (int i = 1; i < 32; i++)
        if (mac_to_linux_sig[i] == s)
            return i;
    return 0;
}

static int sig_or_fail(int mac)
{
    if (mac == 0)
        return 0;
    int s = ferry_signal_to_linux(mac);
    if (!s)
        errno = EINVAL;
    return s ? s : -1;
}

static uint32_t set_to_mac(const sigset_t *set)
{
    uint32_t out = 0;
    for (int i = 1; i < 32; i++)
        if (mac_to_linux_sig[i] && sigismember(set, mac_to_linux_sig[i]) == 1)
            out |= 1u << (i - 1);
    return out;
}

static void set_to_linux(uint32_t mac, sigset_t *set)
{
    sigemptyset(set);
    for (int i = 1; i < 32; i++)
        if ((mac & (1u << (i - 1))) && mac_to_linux_sig[i])
            sigaddset(set, mac_to_linux_sig[i]);
}

static int mac_sigemptyset(uint32_t *set) { *set = 0; return 0; }
static int mac_sigfillset(uint32_t *set) { *set = 0xffffffffu; return 0; }
static int mac_sigaddset(uint32_t *set, int s)
{
    if (s <= 0 || s >= 32) { errno = EINVAL; return -1; }
    *set |= 1u << (s - 1);
    return 0;
}
static int mac_sigdelset(uint32_t *set, int s)
{
    if (s <= 0 || s >= 32) { errno = EINVAL; return -1; }
    *set &= ~(1u << (s - 1));
    return 0;
}
static int mac_sigismember(const uint32_t *set, int s)
{
    if (s <= 0 || s >= 32) { errno = EINVAL; return -1; }
    return (*set >> (s - 1)) & 1;
}

static int mac_sigprocmask(int how, const uint32_t *set, uint32_t *old)
{
    sigset_t in, out;
    int lhow = how == 1 ? SIG_BLOCK : how == 2 ? SIG_UNBLOCK : how == 3 ? SIG_SETMASK : -1;
    if (lhow < 0 && set) {
        errno = EINVAL;
        return -1;
    }
    if (set)
        set_to_linux(*set, &in);
    int rc = sigprocmask(lhow < 0 ? SIG_BLOCK : lhow, set ? &in : NULL, &out);
    if (rc == 0 && old)
        *old = set_to_mac(&out);
    return rc;
}

/* The same for the calling thread only, returning an error number instead of setting errno. */
static int mac_pthread_sigmask(int how, const uint32_t *set, uint32_t *old)
{
    sigset_t in, out;
    int lhow = how == 1 ? SIG_BLOCK : how == 2 ? SIG_UNBLOCK : how == 3 ? SIG_SETMASK : -1;
    if (lhow < 0 && set)
        return ferry_errno_to_mac(EINVAL);
    if (set)
        set_to_linux(*set, &in);
    int rc = pthread_sigmask(lhow < 0 ? SIG_BLOCK : lhow, set ? &in : NULL, &out);
    if (rc == 0 && old)
        *old = set_to_mac(&out);
    return ferry_errno_to_mac(rc);
}

static int mac_pthread_kill(pthread_t t, int sig)
{
    int lsig = sig ? ferry_signal_to_linux(sig) : 0;
    if (sig && !lsig)
        return ferry_errno_to_mac(EINVAL);
    return ferry_errno_to_mac(pthread_kill(t, lsig));
}

/* The Mac program's handlers get Mac signal numbers, so they run behind a trampoline. */
struct mac_siginfo {
    int32_t signo, err, code, pid;
    uint32_t uid;
    int32_t status;
    void *addr;
    uint64_t value;
    long band;
    unsigned long pad[7];
};

struct mac_sigaction {
    void *handler;
    uint32_t mask;
    int32_t flags;
};

#define MAC_SA_ONSTACK   0x0001
#define MAC_SA_RESTART   0x0002
#define MAC_SA_RESETHAND 0x0004
#define MAC_SA_NOCLDSTOP 0x0008
#define MAC_SA_NODEFER   0x0010
#define MAC_SA_NOCLDWAIT 0x0020
#define MAC_SA_SIGINFO   0x0040

static void *mac_handler[65];

static void trampoline(int s)
{
    ((void (*)(int))mac_handler[s])(ferry_signal_to_mac(s));
}

static void trampoline_info(int s, siginfo_t *info, void *ctx)
{
    (void)ctx;
    struct mac_siginfo mi = {.signo = ferry_signal_to_mac(s)};
    if (info) {
        mi.code = info->si_code;
        mi.pid = info->si_pid;
        mi.uid = info->si_uid;
        mi.addr = info->si_addr;
        mi.err = ferry_errno_to_mac(info->si_errno);
    }
    /* The machine context is laid out differently, so the program gets none. */
    ((void (*)(int, struct mac_siginfo *, void *))mac_handler[s])(mi.signo, &mi, NULL);
}

/* SIGEMT and SIGINFO have no Linux signal, so nothing ever raises them; a
 * program may still set and read their handlers (Node.js resets every
 * signal at start), so those are kept here. */
static struct mac_sigaction unraised[32];

/* FERRY_CRASH_REPORT=1: a program that crashes says where, in which image
 * and near which symbol, with the frames its frame pointers lead to, and
 * the program's own handlers for crashes aren't installed, so that the
 * report comes first (freemac 1.266, for finding why an app's helper
 * process ends). */
static int crash_report;

static int crash_read(uintptr_t a, void *out, size_t n)
{
    struct iovec l = {out, n}, r = {(void *)a, n};
    return syscall(SYS_process_vm_readv, getpid(), &l, 1, &r, 1, 0) == (long)n ? 0 : -1;
}

static void crash_where(uintptr_t a)
{
    struct image *im = ferry_image_containing((void *)a);
    if (im) {
        void *sa = NULL;
        const char *sn = ferry_image_nearest(im, (void *)a, &sa);
        const char *path = ferry_image_path(im), *base = strrchr(path, '/');
        fprintf(stderr, "  %#lx %s+%#lx %s+%#lx\n", (unsigned long)a, base ? base + 1 : path,
                (unsigned long)(a - (uintptr_t)ferry_image_header(im)), sn ? sn : "?",
                (unsigned long)(sn ? a - (uintptr_t)sa : 0));
        return;
    }
    Dl_info d;
    if (dladdr((void *)a, &d) && d.dli_fname)
        fprintf(stderr, "  %#lx ferry %s+%#lx\n", (unsigned long)a, d.dli_sname ? d.dli_sname : "?",
                (unsigned long)(a - (uintptr_t)(d.dli_saddr ? d.dli_saddr : d.dli_fbase)));
    else
        fprintf(stderr, "  %#lx\n", (unsigned long)a);
}

static void crash_handler(int sig, siginfo_t *si, void *ctx)
{
    ucontext_t *uc = ctx;
    uintptr_t ip = (uintptr_t)uc->uc_mcontext.gregs[REG_RIP], bp = (uintptr_t)uc->uc_mcontext.gregs[REG_RBP];
    fprintf(stderr, "ferry: process %d thread %ld crashed: signal %d (code %d), address %p\n", getpid(),
            (long)syscall(SYS_gettid), sig, si->si_code, si->si_addr);
    char sel[64] = {0};
    crash_read((uintptr_t)uc->uc_mcontext.gregs[REG_RSI], sel, sizeof sel - 1);
    for (unsigned i = 0; i < sizeof sel; i++)
        if (sel[i] && (sel[i] < 0x20 || sel[i] > 0x7e)) {
            sel[i] = 0;
            break;
        }
    fprintf(stderr, "  rdi %#llx rsi %#llx (\"%s\") rdx %#llx rsp %#llx\n",
            (unsigned long long)uc->uc_mcontext.gregs[REG_RDI], (unsigned long long)uc->uc_mcontext.gregs[REG_RSI], sel,
            (unsigned long long)uc->uc_mcontext.gregs[REG_RDX], (unsigned long long)uc->uc_mcontext.gregs[REG_RSP]);
    crash_where(ip);
    for (int i = 0; i < 24 && bp; i++) {
        uintptr_t frame[2];
        if (crash_read(bp, frame, sizeof frame) < 0 || !frame[1])
            break;
        crash_where(frame[1]);
        if (frame[0] <= bp)
            break;
        bp = frame[0];
    }
    /* Code built without frame pointers breaks that chain, so with
     * FERRY_CRASH_REPORT=2 the stack's words that point into a program's
     * code follow: likely return addresses, the callers (freemac 1.267). */
    const char *e = getenv("FERRY_CRASH_REPORT");
    if (e && *e == '2') {
        fprintf(stderr, "  stack words into code:\n");
        uintptr_t sp = (uintptr_t)uc->uc_mcontext.gregs[REG_RSP];
        int shown = 0;
        for (int i = 0; i < 4096 && shown < 40; i++) {
            uintptr_t w;
            if (crash_read(sp + 8 * (uintptr_t)i, &w, sizeof w) < 0)
                break;
            if (w > 4096 && ferry_image_containing((void *)w)) {
                crash_where(w);
                shown++;
            }
        }
    }
    _exit(128 + sig);
}

void ferry_crash_report_init(void)
{
    const char *e = getenv("FERRY_CRASH_REPORT");
    if (!e || !*e || *e == '0')
        return;
    crash_report = 1;
    struct sigaction sa = {0};
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    int sigs[] = {SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE};
    for (unsigned i = 0; i < sizeof sigs / sizeof sigs[0]; i++)
        sigaction(sigs[i], &sa, NULL);
}

static int mac_sigaction(int mac, const struct mac_sigaction *act, struct mac_sigaction *old)
{
    if (mac > 0 && mac < 32 && !mac_to_linux_sig[mac]) {
        if (old)
            *old = unraised[mac];
        if (act)
            unraised[mac] = *act;
        return 0;
    }
    int s = sig_or_fail(mac);
    if (s <= 0)
        return s == 0 ? (errno = EINVAL, -1) : -1;
    if (crash_report && act && (s == SIGSEGV || s == SIGBUS || s == SIGILL || s == SIGTRAP || s == SIGFPE))
        return 0; /* the crash report stays */
    struct sigaction in = {0}, out;
    if (act) {
        int f = act->flags;
        in.sa_flags = (f & MAC_SA_ONSTACK ? SA_ONSTACK : 0) | (f & MAC_SA_RESTART ? SA_RESTART : 0)
            | (f & MAC_SA_RESETHAND ? SA_RESETHAND : 0) | (f & MAC_SA_NOCLDSTOP ? SA_NOCLDSTOP : 0)
            | (f & MAC_SA_NODEFER ? SA_NODEFER : 0) | (f & MAC_SA_NOCLDWAIT ? SA_NOCLDWAIT : 0)
            | (f & MAC_SA_SIGINFO ? SA_SIGINFO : 0);
        set_to_linux(act->mask, &in.sa_mask);
        if (act->handler == SIG_DFL || act->handler == SIG_IGN) {
            in.sa_handler = act->handler;
        } else {
            mac_handler[s] = act->handler;
            if (f & MAC_SA_SIGINFO)
                in.sa_sigaction = trampoline_info;
            else
                in.sa_handler = trampoline;
        }
    }
    void *previous = mac_handler[s];
    int rc = ferry_sigaction(s, act ? &in : NULL, &out);
    if (rc == 0 && old) {
        int f = out.sa_flags;
        old->handler = (out.sa_handler == trampoline || (void *)out.sa_sigaction == (void *)trampoline_info)
            ? previous : (void *)out.sa_handler;
        old->mask = set_to_mac(&out.sa_mask);
        old->flags = (f & SA_ONSTACK ? MAC_SA_ONSTACK : 0) | (f & SA_RESTART ? MAC_SA_RESTART : 0)
            | (f & SA_RESETHAND ? MAC_SA_RESETHAND : 0) | (f & SA_NOCLDSTOP ? MAC_SA_NOCLDSTOP : 0)
            | (f & SA_NODEFER ? MAC_SA_NODEFER : 0) | (f & SA_NOCLDWAIT ? MAC_SA_NOCLDWAIT : 0)
            | (f & SA_SIGINFO ? MAC_SA_SIGINFO : 0);
    }
    return rc;
}

static void *mac_signal(int mac, void *handler)
{
    struct mac_sigaction act = {.handler = handler, .flags = MAC_SA_RESTART}, old;
    if (mac_sigaction(mac, &act, &old) < 0)
        return SIG_ERR;
    return old.handler;
}

static int mac_kill(pid_t pid, int mac)
{
    int s = sig_or_fail(mac);
    return s < 0 ? -1 : kill(pid, s);
}

static int mac_killpg(pid_t pg, int mac)
{
    int s = sig_or_fail(mac);
    return s < 0 ? -1 : killpg(pg, s);
}

static int mac_raise(int mac)
{
    int s = sig_or_fail(mac);
    return s < 0 ? -1 : raise(s);
}

static char *mac_strsignal(int mac) { return strsignal(ferry_signal_to_linux(mac)); }

/* A child killed by a signal reports that signal's number inside the status. */
static int status_to_mac(int st)
{
    if (WIFSIGNALED(st))
        return (st & ~0x7f) | ferry_signal_to_mac(WTERMSIG(st));
    if (WIFSTOPPED(st))
        return (ferry_signal_to_mac(WSTOPSIG(st)) << 8) | 0x7f;
    return st;
}

static pid_t mac_waitpid(pid_t pid, int *status, int options)
{
    /* WNOHANG 1 and WUNTRACED 2 are the same on both systems. */
    int st = 0;
    pid_t rc = waitpid(pid, &st, options & 3);
    if (rc > 0 && status)
        *status = status_to_mac(st);
    return rc;
}

static pid_t mac_wait(int *status) { return mac_waitpid(-1, status, 0); }

/* freemac 1.232, Ferry 0.56.0: what Qt's process launcher waits with. The
 * use figures (struct rusage) are laid out the same on both systems. */
static pid_t mac_wait4(pid_t pid, int *status, int options, struct rusage *ru)
{
    int st = 0;
    pid_t rc = wait4(pid, &st, options & 3, ru);
    if (rc > 0 && status)
        *status = status_to_mac(st);
    return rc;
}

static pid_t mac_wait3(int *status, int options, struct rusage *ru) { return mac_wait4(-1, status, options, ru); }

#define MAC_WEXITED    0x04
#define MAC_WSTOPPED   0x08
#define MAC_WCONTINUED 0x10
#define MAC_WNOWAIT    0x20

/* P_ALL, P_PID and P_PGID are 0, 1 and 2 on both, and so are the CLD_
 * codes; the wait flags and the record differ. */
static int mac_waitid(int idtype, id_t id, struct mac_siginfo *info, int options)
{
    int o = (options & 1 ? WNOHANG : 0) | (options & MAC_WEXITED ? WEXITED : 0)
          | (options & MAC_WSTOPPED ? WSTOPPED : 0) | (options & MAC_WCONTINUED ? WCONTINUED : 0)
          | (options & MAC_WNOWAIT ? WNOWAIT : 0);
    siginfo_t li;
    memset(&li, 0, sizeof li);
    int rc = waitid((idtype_t)idtype, id, &li, o);
    if (rc == 0 && info) {
        memset(info, 0, sizeof *info);
        if (li.si_pid) {
            info->signo = ferry_signal_to_mac(li.si_signo);
            info->code = li.si_code;
            info->pid = li.si_pid;
            info->uid = li.si_uid;
            /* an exit code, or the number of the signal that ended or stopped the child */
            info->status = li.si_code == CLD_EXITED ? li.si_status : ferry_signal_to_mac(li.si_status);
        }
    }
    return rc;
}

/* ---- system information --------------------------------------------------------------- */

static long mac_sysconf(int name)
{
    switch (name) {
    case 1: return sysconf(_SC_ARG_MAX);
    case 2: return sysconf(_SC_CHILD_MAX);
    case 3: return sysconf(_SC_CLK_TCK);
    case 4: return sysconf(_SC_NGROUPS_MAX);
    case 5: return sysconf(_SC_OPEN_MAX);
    case 29: return sysconf(_SC_PAGESIZE);
    case 57: return sysconf(_SC_NPROCESSORS_CONF);
    case 58: return sysconf(_SC_NPROCESSORS_ONLN);
    case 71: return sysconf(_SC_GETPW_R_SIZE_MAX);
    case 72: return sysconf(_SC_HOST_NAME_MAX);
    case 200: return sysconf(_SC_PHYS_PAGES);
    default:
        errno = EINVAL;
        return -1;
    }
}

struct mac_utsname { char sysname[256], nodename[256], release[256], version[256], machine[256]; };

static int mac_uname(struct mac_utsname *u)
{
    struct utsname l;
    if (uname(&l) < 0)
        return -1;
    memset(u, 0, sizeof *u);
    /* Programs check these names to pick Mac behaviour. Report the macOS
     * family Ferry imitates, and say in the version where it really runs
     * (sysversion.c; sysctl's kern.version is the same text). */
    snprintf(u->sysname, sizeof u->sysname, "Darwin");
    snprintf(u->nodename, sizeof u->nodename, "%s", l.nodename);
    snprintf(u->release, sizeof u->release, "%s", FERRY_DARWIN_RELEASE);
    snprintf(u->version, sizeof u->version, "%s", ferry_kernel_version());
    snprintf(u->machine, sizeof u->machine, "x86_64");
    return 0;
}

struct mac_passwd {
    char *name, *passwd;
    uint32_t uid, gid;
    long change;
    char *class_, *gecos, *dir, *shell;
    long expire;
};

static struct mac_passwd *to_mac_passwd(struct passwd *p)
{
    static __thread struct mac_passwd m;
    if (!p)
        return NULL;
    m = (struct mac_passwd){.name = p->pw_name, .passwd = p->pw_passwd, .uid = p->pw_uid,
                            .gid = p->pw_gid, .class_ = "", .gecos = p->pw_gecos,
                            .dir = p->pw_dir, .shell = p->pw_shell};
    return &m;
}

static struct mac_passwd *mac_getpwuid(uid_t uid) { return to_mac_passwd(getpwuid(uid)); }
static struct mac_passwd *mac_getpwnam(const char *name) { return to_mac_passwd(getpwnam(name)); }

#define MAC_TIOCGWINSZ 0x40087468ul
#define MAC_FIONREAD   0x4004667ful
#define MAC_FIONBIO    0x8004667eul
#define MAC_SIOCGIFMTU 0xc0206933ul /* a Mac's struct ifreq is 32 bytes, Linux's 40 */

/* Requests whose argument is the same on both, by their Mac numbers
 * (<sys/filio.h>, <sys/ttycom.h>). Rust's standard library marks its
 * descriptors close-on-exec with FIOCLEX; terminals size and own their
 * pseudo-terminals with the tty ones (freemac 1.268). */
static const struct { unsigned long mac, linux_; } same_ioctls[] = {
    {0x20006601ul, FIOCLEX},   {0x20006602ul, FIONCLEX},  {0x8004667dul, FIOASYNC},
    {0x80087467ul, TIOCSWINSZ}, {0x40047477ul, TIOCGPGRP}, {0x80047476ul, TIOCSPGRP},
    {0x20007461ul, TIOCSCTTY}, {0x20007471ul, TIOCNOTTY}, {0x40047473ul, TIOCOUTQ},
    {0x2000740dul, TIOCEXCL},  {0x2000740eul, TIOCNXCL},  {0x80017472ul, TIOCSTI},
};

static int mac_ioctl(int fd, unsigned long req, ...)
{
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    if (req == MAC_TIOCGWINSZ) /* struct winsize is the same on both */
        return ioctl(fd, TIOCGWINSZ, arg);
    if (req == MAC_FIONREAD)
        return ioctl(fd, FIONREAD, arg);
    if (req == MAC_FIONBIO) /* an int, nonzero for non-blocking */
        return ioctl(fd, FIONBIO, arg);
    for (size_t i = 0; i < sizeof same_ioctls / sizeof *same_ioctls; i++)
        if (req == same_ioctls[i].mac)
            return ioctl(fd, same_ioctls[i].linux_, req == 0x20007461ul ? 0 : arg);
    if (req == MAC_SIOCGIFMTU && arg) { /* both put the name first and the MTU after it */
        struct ifreq lr;
        memset(&lr, 0, sizeof lr);
        memcpy(lr.ifr_name, arg, IFNAMSIZ);
        lr.ifr_name[IFNAMSIZ - 1] = 0;
        if (ioctl(fd, SIOCGIFMTU, &lr) < 0)
            return -1;
        memcpy((char *)arg + IFNAMSIZ, &lr.ifr_mtu, sizeof(int));
        return 0;
    }
    if (ferry_verbose)
        fprintf(stderr, "ferry: ioctl %#lx on %d isn't translated yet\n", req, fd);
    errno = ENOTTY;
    return -1;
}

/* Resource numbers differ, and so does the "no limit" value. */
#define MAC_RLIM_INFINITY 0x7fffffffffffffffull

static int rlimit_to_linux(int r)
{
    static const int map[] = {RLIMIT_CPU, RLIMIT_FSIZE, RLIMIT_DATA, RLIMIT_STACK, RLIMIT_CORE,
                              RLIMIT_AS, RLIMIT_MEMLOCK, RLIMIT_NPROC, RLIMIT_NOFILE};
    return r >= 0 && r < 9 ? map[r] : -1;
}

static int mac_getrlimit(int r, uint64_t lim[2])
{
    int lr = rlimit_to_linux(r);
    struct rlimit l;
    if (lr < 0) {
        errno = EINVAL;
        return -1;
    }
    if (getrlimit(lr, &l) < 0)
        return -1;
    lim[0] = l.rlim_cur == RLIM_INFINITY ? MAC_RLIM_INFINITY : l.rlim_cur;
    lim[1] = l.rlim_max == RLIM_INFINITY ? MAC_RLIM_INFINITY : l.rlim_max;
    return 0;
}

/* The same layout as Linux's, but a Mac counts ru_maxrss in bytes and
 * Linux in kilobytes (FFmpeg's -benchmark prints it; freemac 1.233,
 * Ferry 0.57.0). RUSAGE_SELF and RUSAGE_CHILDREN are the same numbers. */
static int mac_getrusage(int who, struct rusage *r)
{
    if (getrusage(who, r) < 0)
        return -1;
    r->ru_maxrss *= 1024;
    return 0;
}

static int mac_setrlimit(int r, const uint64_t lim[2])
{
    int lr = rlimit_to_linux(r);
    if (lr < 0) {
        errno = EINVAL;
        return -1;
    }
    struct rlimit l = {lim[0] >= MAC_RLIM_INFINITY ? RLIM_INFINITY : lim[0],
                       lim[1] >= MAC_RLIM_INFINITY ? RLIM_INFINITY : lim[1]};
    return setrlimit(lr, &l);
}

/* Locale categories are numbered differently. */
static int category_to_linux(int c)
{
    static const int map[] = {LC_ALL, LC_COLLATE, LC_CTYPE, LC_MONETARY, LC_NUMERIC, LC_TIME, LC_MESSAGES};
    return c >= 0 && c < 7 ? map[c] : -1;
}

static char *mac_setlocale(int c, const char *name)
{
    int lc = category_to_linux(c);
    if (lc < 0)
        return NULL;
    return setlocale(lc, name);
}

/* Mac paths are at most 1024 bytes, and callers size their buffers to that. */
static char *mac_realpath(const char *path, char *out)
{
    char *full = realpath(path, NULL);
    if (!full || !out)
        return full;
    if (strlen(full) >= 1024) {
        free(full);
        errno = ENAMETOOLONG;
        return NULL;
    }
    strcpy(out, full);
    free(full);
    return out;
}

/* ---- getopt ---------------------------------------------------------------------------
 * BSD getopt stops at the first non-option; this C library's moves options
 * forward unless the option string starts with '+'. Mac programs also reset
 * scanning through a variable called optreset. */

static int mac_optreset;

static const char *bsd_optstring(const char *opts)
{
    static const char *last_in;
    static char *last_out;
    if (opts == last_in && last_out)
        return last_out;
    char *s = malloc(strlen(opts) + 2);
    if (!s)
        return opts;
    s[0] = '+';
    strcpy(s + 1, opts[0] == '+' ? opts + 1 : opts);
    free(last_out);
    last_in = opts;
    last_out = s;
    return s;
}

static void check_reset(void)
{
    if (mac_optreset) {
        mac_optreset = 0;
        optind = 0;
    }
}

static int mac_getopt(int argc, char *const argv[], const char *opts)
{
    check_reset();
    return getopt(argc, argv, bsd_optstring(opts));
}

static int mac_getopt_long(int argc, char *const argv[], const char *opts, const struct option *lo, int *idx)
{
    check_reset();
    return getopt_long(argc, argv, bsd_optstring(opts), lo, idx);
}

static int mac_getopt_long_only(int argc, char *const argv[], const char *opts, const struct option *lo, int *idx)
{
    check_reset();
    return getopt_long_only(argc, argv, bsd_optstring(opts), lo, idx);
}

/* ---- libkern's atomics (OSAtomic.h), on the compiler's atomic builtins.
 * (Its spin locks and os_unfair_lock are in pthread.c, with the other locks.) */
static void mac_OSMemoryBarrier(void) { __atomic_thread_fence(__ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicAdd32(int32_t v, volatile int32_t *p) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
static int64_t mac_OSAtomicAdd64(int64_t v, volatile int64_t *p) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicIncrement32(volatile int32_t *p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicDecrement32(volatile int32_t *p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int64_t mac_OSAtomicIncrement64(volatile int64_t *p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int64_t mac_OSAtomicDecrement64(volatile int64_t *p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicOr32(uint32_t v, volatile uint32_t *p) { return (int32_t)__atomic_or_fetch(p, v, __ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicAnd32(uint32_t v, volatile uint32_t *p) { return (int32_t)__atomic_and_fetch(p, v, __ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicOr32Orig(uint32_t v, volatile uint32_t *p) { return (int32_t)__atomic_fetch_or(p, v, __ATOMIC_SEQ_CST); }
static int32_t mac_OSAtomicAnd32Orig(uint32_t v, volatile uint32_t *p) { return (int32_t)__atomic_fetch_and(p, v, __ATOMIC_SEQ_CST); }
static bool mac_OSAtomicCompareAndSwap32(int32_t o, int32_t n, volatile int32_t *p)
{
    return __atomic_compare_exchange_n(p, &o, n, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
static bool mac_OSAtomicCompareAndSwap64(int64_t o, int64_t n, volatile int64_t *p)
{
    return __atomic_compare_exchange_n(p, &o, n, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
static bool mac_OSAtomicCompareAndSwapPtr(void *o, void *n, void *volatile *p)
{
    return __atomic_compare_exchange_n(p, &o, n, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
static bool mac_OSAtomicTestAndSet(uint32_t n, volatile void *addr)
{
    volatile uint8_t *b = (volatile uint8_t *)addr + (n >> 3);
    uint8_t mask = (uint8_t)(0x80 >> (n & 7));
    return (__atomic_fetch_or(b, mask, __ATOMIC_SEQ_CST) & mask) != 0;
}
static bool mac_OSAtomicTestAndClear(uint32_t n, volatile void *addr)
{
    volatile uint8_t *b = (volatile uint8_t *)addr + (n >> 3);
    uint8_t mask = (uint8_t)(0x80 >> (n & 7));
    return (__atomic_fetch_and(b, (uint8_t)~mask, __ATOMIC_SEQ_CST) & mask) != 0;
}

/* ---- System V shared memory and semaphores (freemac 1.232) ---------------------------
 * shmget, shmat, shmdt, semget, semop and ftok take the same arguments on
 * both systems and pass through. A segment's or set's description has a
 * Mac's layout, and semctl's commands a Mac's numbers, so those two are
 * translated. */
struct mac_ipc_perm {
    uint32_t uid, gid, cuid, cgid;
    uint16_t mode, seq;
    int32_t key;
};
#pragma pack(push, 4)
struct mac_shmid_ds {
    struct mac_ipc_perm perm;
    uint64_t segsz;
    int32_t lpid, cpid;
    uint16_t nattch;
    int64_t atime, dtime, ctime;
    void *internal;
};
struct mac_semid_ds {
    struct mac_ipc_perm perm;
    int32_t base;
    uint16_t nsems;
    int64_t otime;
    int32_t pad1;
    int64_t ctime;
    int32_t pad2, pad3[4];
};
#pragma pack(pop)
_Static_assert(sizeof(struct mac_ipc_perm) == 24, "Mac struct ipc_perm is 24 bytes");
_Static_assert(sizeof(struct mac_shmid_ds) == 76, "Mac struct shmid_ds is 76 bytes");

static void perm_to_mac(const struct ipc_perm *l, struct mac_ipc_perm *m)
{
    m->uid = l->uid;
    m->gid = l->gid;
    m->cuid = l->cuid;
    m->cgid = l->cgid;
    m->mode = (uint16_t)(l->mode & 07777);
    m->seq = (uint16_t)l->__seq;
    m->key = l->__key;
}

static int mac_shmctl(int id, int cmd, struct mac_shmid_ds *buf)
{
    struct shmid_ds l;
    memset(&l, 0, sizeof l);
    switch (cmd) {
    case 0: /* IPC_RMID */
        return shmctl(id, IPC_RMID, NULL);
    case 1: /* IPC_SET */
        if (!buf || shmctl(id, IPC_STAT, &l))
            return buf ? -1 : (errno = EFAULT, -1);
        l.shm_perm.uid = buf->perm.uid;
        l.shm_perm.gid = buf->perm.gid;
        l.shm_perm.mode = buf->perm.mode & 0777;
        return shmctl(id, IPC_SET, &l);
    case 2: /* IPC_STAT */
        if (!buf)
            return errno = EFAULT, -1;
        if (shmctl(id, IPC_STAT, &l))
            return -1;
        memset(buf, 0, sizeof *buf);
        perm_to_mac(&l.shm_perm, &buf->perm);
        buf->segsz = l.shm_segsz;
        buf->lpid = l.shm_lpid;
        buf->cpid = l.shm_cpid;
        buf->nattch = (uint16_t)l.shm_nattch;
        buf->atime = l.shm_atime;
        buf->dtime = l.shm_dtime;
        buf->ctime = l.shm_ctime;
        return 0;
    }
    errno = EINVAL;
    return -1;
}

union linux_semun {
    int val;
    struct semid_ds *buf;
    unsigned short *array;
};

/* The fourth argument is a union semun, passed as one 8-byte word. */
static int mac_semctl(int id, int num, int cmd, ...)
{
    va_list ap;
    va_start(ap, cmd);
    union {
        int val;
        void *ptr;
    } arg;
    arg.ptr = va_arg(ap, void *);
    va_end(ap);
    union linux_semun u;
    struct semid_ds l;
    switch (cmd) {
    case 0: return semctl(id, num, IPC_RMID);
    case 1: { /* IPC_SET */
        struct mac_semid_ds *m = arg.ptr;
        memset(&l, 0, sizeof l);
        u.buf = &l;
        if (!m || semctl(id, 0, IPC_STAT, u))
            return m ? -1 : (errno = EFAULT, -1);
        l.sem_perm.uid = m->perm.uid;
        l.sem_perm.gid = m->perm.gid;
        l.sem_perm.mode = m->perm.mode & 0777;
        return semctl(id, 0, IPC_SET, u);
    }
    case 2: { /* IPC_STAT */
        struct mac_semid_ds *m = arg.ptr;
        if (!m)
            return errno = EFAULT, -1;
        memset(&l, 0, sizeof l);
        u.buf = &l;
        if (semctl(id, 0, IPC_STAT, u))
            return -1;
        memset(m, 0, sizeof *m);
        perm_to_mac(&l.sem_perm, &m->perm);
        m->nsems = (uint16_t)l.sem_nsems;
        m->otime = l.sem_otime;
        m->ctime = l.sem_ctime;
        return 0;
    }
    case 3: return semctl(id, num, GETNCNT);
    case 4: return semctl(id, num, GETPID);
    case 5: return semctl(id, num, GETVAL);
    case 7: return semctl(id, num, GETZCNT);
    case 6: /* GETALL */
        u.array = arg.ptr;
        return semctl(id, num, GETALL, u);
    case 8: /* SETVAL */
        u.val = arg.val;
        return semctl(id, num, SETVAL, u);
    case 9: /* SETALL */
        u.array = arg.ptr;
        return semctl(id, num, SETALL, u);
    }
    errno = EINVAL;
    return -1;
}


/* vfork as fork: a vfork child may only exec or _exit, and fork serves that too
 * without the parent's stack being shared through a call of Ferry's. */
static pid_t mac_vfork(void) { return fork(); }

const struct ferry_symbol ferry_posix_symbols[] = {
    {"vfork", mac_vfork},
    {"OSMemoryBarrier", mac_OSMemoryBarrier},
    {"OSAtomicAdd32", mac_OSAtomicAdd32},
    {"OSAtomicAdd32Barrier", mac_OSAtomicAdd32},
    {"OSAtomicAdd64", mac_OSAtomicAdd64},
    {"OSAtomicAdd64Barrier", mac_OSAtomicAdd64},
    {"OSAtomicIncrement32", mac_OSAtomicIncrement32},
    {"OSAtomicIncrement32Barrier", mac_OSAtomicIncrement32},
    {"OSAtomicDecrement32", mac_OSAtomicDecrement32},
    {"OSAtomicDecrement32Barrier", mac_OSAtomicDecrement32},
    {"OSAtomicIncrement64", mac_OSAtomicIncrement64},
    {"OSAtomicIncrement64Barrier", mac_OSAtomicIncrement64},
    {"OSAtomicDecrement64", mac_OSAtomicDecrement64},
    {"OSAtomicDecrement64Barrier", mac_OSAtomicDecrement64},
    {"OSAtomicOr32", mac_OSAtomicOr32},
    {"OSAtomicOr32Barrier", mac_OSAtomicOr32},
    {"OSAtomicAnd32", mac_OSAtomicAnd32},
    {"OSAtomicAnd32Barrier", mac_OSAtomicAnd32},
    {"OSAtomicOr32Orig", mac_OSAtomicOr32Orig},
    {"OSAtomicOr32OrigBarrier", mac_OSAtomicOr32Orig},
    {"OSAtomicAnd32Orig", mac_OSAtomicAnd32Orig},
    {"OSAtomicAnd32OrigBarrier", mac_OSAtomicAnd32Orig},
    {"OSAtomicCompareAndSwap32", mac_OSAtomicCompareAndSwap32},
    {"OSAtomicCompareAndSwap32Barrier", mac_OSAtomicCompareAndSwap32},
    {"OSAtomicCompareAndSwap64", mac_OSAtomicCompareAndSwap64},
    {"OSAtomicCompareAndSwap64Barrier", mac_OSAtomicCompareAndSwap64},
    {"OSAtomicCompareAndSwapPtr", mac_OSAtomicCompareAndSwapPtr},
    {"OSAtomicCompareAndSwapPtrBarrier", mac_OSAtomicCompareAndSwapPtr},
    {"OSAtomicTestAndSet", mac_OSAtomicTestAndSet},
    {"OSAtomicTestAndSetBarrier", mac_OSAtomicTestAndSet},
    {"OSAtomicTestAndClear", mac_OSAtomicTestAndClear},
    {"OSAtomicTestAndClearBarrier", mac_OSAtomicTestAndClear},
    {"OSAtomicCompareAndSwapInt", mac_OSAtomicCompareAndSwap32},
    {"OSAtomicCompareAndSwapIntBarrier", mac_OSAtomicCompareAndSwap32},
    {"OSAtomicCompareAndSwapLong", mac_OSAtomicCompareAndSwap64},
    {"OSAtomicCompareAndSwapLongBarrier", mac_OSAtomicCompareAndSwap64},
    {"open", mac_open},
    {"shm_open", mac_shm_open},
    {"qsort_r", mac_qsort_r},
    {"shm_unlink", shm_unlink},
    {"openat", mac_openat},
    {"renamex_np", mac_renamex_np},
    {"renameat", mac_renameat},
    {"utimes", mac_utimes},
    {"futimes", mac_futimes},
    {"lutimes", mac_lutimes},
    {"renameatx_np", mac_renameatx_np},
    {"creat", mac_creat},
    {"fchown", mac_fchown},
    {"access", mac_access},
    {"unlinkat", mac_unlinkat},
    {"mkdirat", mac_mkdirat},
    {"fcntl", mac_fcntl},
    {"stat$INODE64", mac_stat64},
    {"lstat$INODE64", mac_lstat64},
    {"fstat$INODE64", mac_fstat64},
    {"fstatat$INODE64", mac_fstatat64},
    {"stat64", mac_stat64},
    {"lstat64", mac_lstat64},
    {"fstat64", mac_fstat64},
    {"opendir$INODE64", mac_opendir},
    {"fdopendir$INODE64", mac_fdopendir},
    {"readdir$INODE64", mac_readdir},
    {"readdir_r$INODE64", mac_readdir_r},
    {"rewinddir$INODE64", mac_rewinddir},
    {"telldir$INODE64", mac_telldir},
    {"seekdir$INODE64", mac_seekdir},
    {"closedir", mac_closedir},
    {"scandir$INODE64", mac_scandir},
    {"alphasort$INODE64", mac_alphasort},
    {"dirfd", mac_dirfd},
    {"mmap", mac_mmap},
    {"clock_gettime", mac_clock_gettime},
    {"clock_getres", mac_clock_getres},
    {"clock_gettime_nsec_np", mac_clock_gettime_nsec_np},
    {"sigemptyset", mac_sigemptyset},
    {"sigfillset", mac_sigfillset},
    {"sigaddset", mac_sigaddset},
    {"sigdelset", mac_sigdelset},
    {"sigismember", mac_sigismember},
    {"sigprocmask", mac_sigprocmask},
    {"pthread_sigmask", mac_pthread_sigmask},
    {"pthread_kill", mac_pthread_kill},
    {"sigaction", mac_sigaction},
    {"signal", mac_signal},
    {"kill", mac_kill},
    {"killpg", mac_killpg},
    {"raise", mac_raise},
    {"strsignal", mac_strsignal},
    {"waitpid", mac_waitpid},
    {"wait", mac_wait},
    {"wait3", mac_wait3},
    {"wait4", mac_wait4},
    {"shmctl", mac_shmctl},
    {"semctl", mac_semctl},
    {"waitid", mac_waitid},
    {"sysconf", mac_sysconf},
    {"uname", mac_uname},
    {"getpwuid", mac_getpwuid},
    {"getpwnam", mac_getpwnam},
    {"ioctl", mac_ioctl},
    {"tzname", tzname},
    {"timezone", &timezone},
    {"daylight", &daylight},
    {"getrlimit", mac_getrlimit},
    {"setrlimit", mac_setrlimit},
    {"getrusage", mac_getrusage},
    {"setlocale", mac_setlocale},
    {"realpath", mac_realpath},
    {"getopt", mac_getopt},
    {"getopt_long", mac_getopt_long},
    {"getopt_long_only", mac_getopt_long_only},
    {"optreset", &mac_optreset},
    {NULL, NULL},
};
