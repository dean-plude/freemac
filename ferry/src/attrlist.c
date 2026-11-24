/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * getattrlist and fgetattrlist: a file's attributes in one call, packed into
 * the caller's buffer as the getattrlist(2) man page describes. Written
 * from that documentation, not from Apple's code.
 *
 * The buffer starts with its length; then, if asked for, the set of
 * attributes returned; then each attribute in the order of its bit, every
 * one at a 4-byte boundary. A name or path is an attrreference (an offset
 * from the reference itself and a length counting the zero byte) to text
 * placed after the fixed part.
 *
 * Served: the common attributes most programs ask for (name, device,
 * object type and ids, the four dates, Finder info (empty), owner, group,
 * permissions, flags, the caller's access, file and parent ids, full
 * path), a directory's link and entry counts and whether it is a mount
 * point, and a file's link count, sizes and block size. Volume and fork
 * attributes, and any other bit, are EINVAL.
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
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#include "ferry.h"

struct mac_attrlist {
    uint16_t bitmapcount, reserved;
    uint32_t commonattr, volattr, dirattr, fileattr, forkattr;
};

#define ATTR_BIT_MAP_COUNT 5
#define FSOPT_NOFOLLOW 0x1
#define FSOPT_REPORT_FULLSIZE 0x4
#define FSOPT_PACK_INVAL_ATTRS 0x8

#define ATTR_CMN_NAME 0x00000001u
#define ATTR_CMN_DEVID 0x00000002u
#define ATTR_CMN_FSID 0x00000004u
#define ATTR_CMN_OBJTYPE 0x00000008u
#define ATTR_CMN_OBJID 0x00000020u
#define ATTR_CMN_OBJPERMANENTID 0x00000040u
#define ATTR_CMN_PAROBJID 0x00000080u
#define ATTR_CMN_CRTIME 0x00000200u
#define ATTR_CMN_MODTIME 0x00000400u
#define ATTR_CMN_CHGTIME 0x00000800u
#define ATTR_CMN_ACCTIME 0x00001000u
#define ATTR_CMN_BKUPTIME 0x00002000u
#define ATTR_CMN_FNDRINFO 0x00004000u
#define ATTR_CMN_OWNERID 0x00008000u
#define ATTR_CMN_GRPID 0x00010000u
#define ATTR_CMN_ACCESSMASK 0x00020000u
#define ATTR_CMN_FLAGS 0x00040000u
#define ATTR_CMN_USERACCESS 0x00200000u
#define ATTR_CMN_FILEID 0x02000000u
#define ATTR_CMN_PARENTID 0x04000000u
#define ATTR_CMN_FULLPATH 0x08000000u
#define ATTR_CMN_RETURNED_ATTRS 0x80000000u

#define ATTR_DIR_LINKCOUNT 0x1u
#define ATTR_DIR_ENTRYCOUNT 0x2u
#define ATTR_DIR_MOUNTSTATUS 0x4u

#define ATTR_FILE_LINKCOUNT 0x1u
#define ATTR_FILE_TOTALSIZE 0x2u
#define ATTR_FILE_ALLOCSIZE 0x4u
#define ATTR_FILE_IOBLOCKSIZE 0x8u
#define ATTR_FILE_DEVTYPE 0x20u
#define ATTR_FILE_DATALENGTH 0x200u
#define ATTR_FILE_DATAALLOCSIZE 0x400u
#define ATTR_FILE_RSRCLENGTH 0x1000u
#define ATTR_FILE_RSRCALLOCSIZE 0x2000u

static const uint32_t common_served =
    ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_FSID | ATTR_CMN_OBJTYPE | ATTR_CMN_OBJID | ATTR_CMN_OBJPERMANENTID |
    ATTR_CMN_PAROBJID | ATTR_CMN_CRTIME | ATTR_CMN_MODTIME | ATTR_CMN_CHGTIME | ATTR_CMN_ACCTIME | ATTR_CMN_BKUPTIME |
    ATTR_CMN_FNDRINFO | ATTR_CMN_OWNERID | ATTR_CMN_GRPID | ATTR_CMN_ACCESSMASK | ATTR_CMN_FLAGS |
    ATTR_CMN_USERACCESS | ATTR_CMN_FILEID | ATTR_CMN_PARENTID | ATTR_CMN_FULLPATH | ATTR_CMN_RETURNED_ATTRS;
static const uint32_t dir_served = ATTR_DIR_LINKCOUNT | ATTR_DIR_ENTRYCOUNT | ATTR_DIR_MOUNTSTATUS;
static const uint32_t file_served = ATTR_FILE_LINKCOUNT | ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE |
                                    ATTR_FILE_IOBLOCKSIZE | ATTR_FILE_DEVTYPE | ATTR_FILE_DATALENGTH |
                                    ATTR_FILE_DATAALLOCSIZE | ATTR_FILE_RSRCLENGTH | ATTR_FILE_RSRCALLOCSIZE;

/* What is known about the object. */
struct object {
    struct stat st;
    struct timespec birth;
    char name[NAME_MAX + 1];
    char path[PATH_MAX];       /* full path, if known */
    int have_path, have_parent, mount_point, access;
    struct stat parent;
    uint32_t entries;
};

struct packer {
    uint8_t *fixed, *var;      /* where the next fixed and variable parts go */
    uint8_t *start;
};

static void put(struct packer *p, const void *data, size_t size)
{
    memcpy(p->fixed, data, size);
    p->fixed += (size + 3) & ~(size_t)3;
}

static void put32(struct packer *p, uint32_t v) { put(p, &v, 4); }
static void put64(struct packer *p, uint64_t v) { put(p, &v, 8); }

static void put_time(struct packer *p, struct timespec t)
{
    int64_t v[2] = {t.tv_sec, t.tv_nsec};
    put(p, v, 16);
}

static void put_text(struct packer *p, const char *text)
{
    size_t len = strlen(text) + 1;
    int32_t ref[2] = {(int32_t)(p->var - p->fixed), (int32_t)len};
    memcpy(p->var, text, len);
    p->var += (len + 3) & ~(size_t)3;
    put(p, ref, 8);
}

static uint32_t object_type(mode_t m)
{
    switch (m & S_IFMT) {
    case S_IFREG: return 1;  /* VREG */
    case S_IFDIR: return 2;  /* VDIR */
    case S_IFBLK: return 3;  /* VBLK */
    case S_IFCHR: return 4;  /* VCHR */
    case S_IFLNK: return 5;  /* VLNK */
    case S_IFSOCK: return 6; /* VSOCK */
    case S_IFIFO: return 7;  /* VFIFO */
    }
    return 0;
}

static int32_t mac_dev(dev_t d) { return (int32_t)(major(d) << 24 | (minor(d) & 0xffffff)); }

/* The attributes packed in order, or only measured (fixed and variable
 * sizes) when p is NULL. */
static void pack(const struct mac_attrlist *a, const struct object *o, int is_dir, int pack_inval, struct packer *p,
                 size_t *fixed, size_t *var, uint32_t returned[5])
{
    uint32_t c = a->commonattr, d = a->dirattr, f = a->fileattr;
    int dir_ok = is_dir, file_ok = !is_dir;
    uint32_t dir_bits = dir_ok || pack_inval ? d : 0, file_bits = file_ok || pack_inval ? f : 0;
    returned[0] = c & ~(o->have_path ? 0 : ATTR_CMN_FULLPATH);
    returned[1] = 0;
    returned[2] = dir_ok ? d : 0;
    returned[3] = file_ok ? f : 0;
    returned[4] = 0;
    size_t fx = 0, vr = 0;
#define FIX(bit, n) if (c & (bit)) fx += (n)
    FIX(ATTR_CMN_RETURNED_ATTRS, 20);
    if (c & ATTR_CMN_NAME) {
        fx += 8;
        vr += (strlen(o->name) + 1 + 3) & ~(size_t)3;
    }
    FIX(ATTR_CMN_DEVID, 4);
    FIX(ATTR_CMN_FSID, 8);
    FIX(ATTR_CMN_OBJTYPE, 4);
    FIX(ATTR_CMN_OBJID, 8);
    FIX(ATTR_CMN_OBJPERMANENTID, 8);
    FIX(ATTR_CMN_PAROBJID, 8);
    FIX(ATTR_CMN_CRTIME, 16);
    FIX(ATTR_CMN_MODTIME, 16);
    FIX(ATTR_CMN_CHGTIME, 16);
    FIX(ATTR_CMN_ACCTIME, 16);
    FIX(ATTR_CMN_BKUPTIME, 16);
    FIX(ATTR_CMN_FNDRINFO, 32);
    FIX(ATTR_CMN_OWNERID, 4);
    FIX(ATTR_CMN_GRPID, 4);
    FIX(ATTR_CMN_ACCESSMASK, 4);
    FIX(ATTR_CMN_FLAGS, 4);
    FIX(ATTR_CMN_USERACCESS, 4);
    FIX(ATTR_CMN_FILEID, 8);
    FIX(ATTR_CMN_PARENTID, 8);
    if (c & ATTR_CMN_FULLPATH) {
        fx += 8;
        vr += (strlen(o->have_path ? o->path : "") + 1 + 3) & ~(size_t)3;
    }
#undef FIX
    for (uint32_t bit = 1; bit; bit <<= 1)
        if (dir_bits & bit)
            fx += 4;
    for (uint32_t bit = 1; bit; bit <<= 1)
        if (file_bits & bit)
            fx += (bit == ATTR_FILE_LINKCOUNT || bit == ATTR_FILE_IOBLOCKSIZE || bit == ATTR_FILE_DEVTYPE) ? 4 : 8;
    *fixed = fx;
    *var = vr;
    if (!p)
        return;

    if (c & ATTR_CMN_RETURNED_ATTRS)
        put(p, returned, 20);
    if (c & ATTR_CMN_NAME)
        put_text(p, o->name);
    if (c & ATTR_CMN_DEVID)
        put32(p, (uint32_t)mac_dev(o->st.st_dev));
    if (c & ATTR_CMN_FSID) {
        int32_t fsid[2] = {mac_dev(o->st.st_dev), 0};
        put(p, fsid, 8);
    }
    if (c & ATTR_CMN_OBJTYPE)
        put32(p, object_type(o->st.st_mode));
    uint32_t objid[2] = {(uint32_t)o->st.st_ino, 0}, parid[2] = {(uint32_t)o->parent.st_ino, 0};
    if (c & ATTR_CMN_OBJID)
        put(p, objid, 8);
    if (c & ATTR_CMN_OBJPERMANENTID)
        put(p, objid, 8);
    if (c & ATTR_CMN_PAROBJID)
        put(p, parid, 8);
    if (c & ATTR_CMN_CRTIME)
        put_time(p, o->birth);
    if (c & ATTR_CMN_MODTIME)
        put_time(p, o->st.st_mtim);
    if (c & ATTR_CMN_CHGTIME)
        put_time(p, o->st.st_ctim);
    if (c & ATTR_CMN_ACCTIME)
        put_time(p, o->st.st_atim);
    if (c & ATTR_CMN_BKUPTIME)
        put_time(p, (struct timespec){0, 0});
    if (c & ATTR_CMN_FNDRINFO) {
        static const uint8_t none[32];
        put(p, none, 32);
    }
    if (c & ATTR_CMN_OWNERID)
        put32(p, o->st.st_uid);
    if (c & ATTR_CMN_GRPID)
        put32(p, o->st.st_gid);
    if (c & ATTR_CMN_ACCESSMASK)
        put32(p, o->st.st_mode & 07777);
    if (c & ATTR_CMN_FLAGS)
        put32(p, 0);
    if (c & ATTR_CMN_USERACCESS)
        put32(p, (uint32_t)o->access);
    if (c & ATTR_CMN_FILEID)
        put64(p, o->st.st_ino);
    if (c & ATTR_CMN_PARENTID)
        put64(p, o->parent.st_ino);
    if (c & ATTR_CMN_FULLPATH)
        put_text(p, o->have_path ? o->path : "");
    if (dir_bits & ATTR_DIR_LINKCOUNT)
        put32(p, dir_ok ? (uint32_t)o->st.st_nlink : 0);
    if (dir_bits & ATTR_DIR_ENTRYCOUNT)
        put32(p, dir_ok ? o->entries : 0);
    if (dir_bits & ATTR_DIR_MOUNTSTATUS)
        put32(p, dir_ok && o->mount_point ? 1 : 0); /* DIR_MNTSTATUS_MNTPOINT */
    int64_t size = file_ok ? o->st.st_size : 0, alloc = file_ok ? (int64_t)o->st.st_blocks * 512 : 0;
    if (file_bits & ATTR_FILE_LINKCOUNT)
        put32(p, file_ok ? (uint32_t)o->st.st_nlink : 0);
    if (file_bits & ATTR_FILE_TOTALSIZE)
        put64(p, (uint64_t)size);
    if (file_bits & ATTR_FILE_ALLOCSIZE)
        put64(p, (uint64_t)alloc);
    if (file_bits & ATTR_FILE_IOBLOCKSIZE)
        put32(p, file_ok ? (uint32_t)o->st.st_blksize : 0);
    if (file_bits & ATTR_FILE_DEVTYPE)
        put32(p, file_ok && (S_ISCHR(o->st.st_mode) || S_ISBLK(o->st.st_mode)) ? (uint32_t)mac_dev(o->st.st_rdev) : 0);
    if (file_bits & ATTR_FILE_DATALENGTH)
        put64(p, (uint64_t)size);
    if (file_bits & ATTR_FILE_DATAALLOCSIZE)
        put64(p, (uint64_t)alloc);
    if (file_bits & ATTR_FILE_RSRCLENGTH)
        put64(p, 0);
    if (file_bits & ATTR_FILE_RSRCALLOCSIZE)
        put64(p, 0);
}

static int count_entries(const char *path, int fd, uint32_t *out)
{
    int dfd = path ? open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC) : openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dfd < 0)
        return -1;
    DIR *d = fdopendir(dfd);
    if (!d) {
        close(dfd);
        return -1;
    }
    uint32_t n = 0;
    for (struct dirent *e; (e = readdir(d));)
        if (strcmp(e->d_name, ".") && strcmp(e->d_name, ".."))
            n++;
    closedir(d);
    *out = n;
    return 0;
}

static int attributes(const char *path, int fd, const struct mac_attrlist *a, void *buf, size_t bufsize,
                      unsigned options)
{
    if (!a || a->bitmapcount != ATTR_BIT_MAP_COUNT || !buf) {
        errno = EINVAL;
        return -1;
    }
    if ((a->commonattr & ~common_served) || (a->dirattr & ~dir_served) || (a->fileattr & ~file_served) ||
        a->volattr || a->forkattr) {
        errno = EINVAL;
        return -1;
    }
    if (bufsize < 4) {
        errno = ERANGE;
        return -1;
    }
    struct object o;
    memset(&o, 0, sizeof o);
    int nofollow = options & FSOPT_NOFOLLOW;
    if (path && ferry_is_virtual(path)) {
        ferry_virtual_stat(path, &o.st);
    } else if (path ? (nofollow ? lstat(path, &o.st) : stat(path, &o.st)) : fstat(fd, &o.st)) {
        return -1;
    }
    o.birth = o.st.st_mtim;
    struct statx sx;
    if (!(path && ferry_is_virtual(path)) &&
        statx(path ? AT_FDCWD : fd, path ? path : "", (path ? 0 : AT_EMPTY_PATH) | (nofollow ? AT_SYMLINK_NOFOLLOW : 0),
              STATX_BTIME, &sx) == 0 &&
        (sx.stx_mask & STATX_BTIME)) {
        o.birth.tv_sec = sx.stx_btime.tv_sec;
        o.birth.tv_nsec = sx.stx_btime.tv_nsec;
    }
    /* the full path, the name and the parent */
    char full[PATH_MAX];
    if (path) {
        if (path[0] == '/' || !getcwd(full, sizeof full))
            snprintf(o.path, sizeof o.path, "%s", path);
        else
            snprintf(o.path, sizeof o.path, "%s/%s", full, path);
        char real[PATH_MAX];
        if (!nofollow && realpath(path, real))
            snprintf(o.path, sizeof o.path, "%s", real);
        o.have_path = 1;
    } else {
        char link[64];
        snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link, o.path, sizeof o.path - 1);
        if (n > 0 && o.path[0] == '/') {
            o.path[n] = 0;
            o.have_path = 1;
        }
    }
    if (o.have_path) {
        size_t len = strlen(o.path);
        while (len > 1 && o.path[len - 1] == '/')
            o.path[--len] = 0;
        const char *slash = strrchr(o.path, '/');
        snprintf(o.name, sizeof o.name, "%s", slash && slash[1] ? slash + 1 : "/");
        char parent[PATH_MAX];
        snprintf(parent, sizeof parent, "%s", o.path);
        char *cut = strrchr(parent, '/');
        if (cut && cut != parent)
            *cut = 0;
        else
            snprintf(parent, sizeof parent, "/");
        o.have_parent = stat(parent, &o.parent) == 0;
        if (o.have_parent && S_ISDIR(o.st.st_mode))
            o.mount_point = o.parent.st_dev != o.st.st_dev || !strcmp(o.path, "/");
    }
    if (!o.have_parent)
        o.parent = o.st;
    o.access = path ? ((access(path, R_OK) == 0) << 2 | (access(path, W_OK) == 0) << 1 | (access(path, X_OK) == 0))
                    : 0;
    if (!path) {
        int fl = fcntl(fd, F_GETFL);
        if (fl >= 0)
            o.access = ((fl & O_ACCMODE) != O_WRONLY) << 2 | ((fl & O_ACCMODE) != O_RDONLY) << 1;
    }
    int is_dir = S_ISDIR(o.st.st_mode);
    if (is_dir && (a->dirattr & ATTR_DIR_ENTRYCOUNT))
        count_entries(path, fd, &o.entries);

    size_t fixed, var;
    uint32_t returned[5];
    int pack_inval = options & FSOPT_PACK_INVAL_ATTRS;
    pack(a, &o, is_dir, pack_inval, NULL, &fixed, &var, returned);
    size_t total = 4 + fixed + var;
    uint8_t *tmp = calloc(1, total);
    if (!tmp) {
        errno = ENOMEM;
        return -1;
    }
    struct packer p = {tmp + 4, tmp + 4 + fixed, tmp};
    pack(a, &o, is_dir, pack_inval, &p, &fixed, &var, returned);
    size_t given = total < bufsize ? total : bufsize;
    uint32_t length = (uint32_t)((options & FSOPT_REPORT_FULLSIZE) ? total : given);
    memcpy(tmp, &length, 4);
    memcpy(buf, tmp, given);
    free(tmp);
    return 0;
}

static int mac_getattrlist(const char *path, struct mac_attrlist *a, void *buf, size_t size, unsigned options)
{
    if (!path) {
        errno = EFAULT;
        return -1;
    }
    return attributes(path, -1, a, buf, size, options);
}

static int mac_fgetattrlist(int fd, struct mac_attrlist *a, void *buf, size_t size, unsigned options)
{
    return attributes(NULL, fd, a, buf, size, options);
}

const struct ferry_symbol ferry_attrlist_symbols[] = {
    {"getattrlist", mac_getattrlist},
    {"fgetattrlist", mac_fgetattrlist},
    {NULL, NULL},
};
