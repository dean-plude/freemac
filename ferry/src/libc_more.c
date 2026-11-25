/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * C library calls the nine apps make that need converting (freemac 1.221,
 * Ferry 0.45.0), each written from its Mac man page:
 *
 * - malloc_good_size(3) and the malloc zones of malloc_zone_malloc(3).
 *   There is one heap, this system's, so every block can be given back
 *   with free() as on a Mac, and malloc_zone_from_ptr answers the default
 *   zone. A zone the program makes is a name only; destroying it leaves
 *   its blocks allocated, since they may since have been freed one by one.
 * - basename(3) and dirname(3), which on a Mac leave the path alone and
 *   answer in storage of their own (here one buffer per thread), and their
 *   _r forms.
 * - The extended-attribute calls of getxattr(2), with the Mac's position
 *   and options arguments. A Mac name is kept in this system's user.
 *   namespace (user.com.apple.FinderInfo), the one an ordinary program may
 *   write, and only those are listed, without the prefix. A missing
 *   attribute is ENOATTR, as on a Mac.
 *
 * And, in freemac 1.223 (Ferry 0.47.0), for Sparkle, the updater most of
 * the apps carry:
 *
 * - fts(3), walking a file tree, on this system's fts: each entry is copied
 *   into a Mac FTSENT (with a Mac struct stat), kept until fts_close; the
 *   program's comparison function and fts_set are passed through.
 * - statfs(2) and fstatfs(2), in the Mac's 64-bit-inode layout, with the
 *   mount point, the source and the kind of file system from
 *   /proc/self/mountinfo, and the read-only and other flags.
 * - The Apple System Log calls of asl(3): a message goes to syslog, and to
 *   standard error too for a client opened with ASL_OPT_STDERR (or to any
 *   file given with asl_add_log_file). The log can't be searched.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fts.h>
#include <limits.h>
#include <malloc.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/sysmacros.h>
#include <sys/xattr.h>
#include <syslog.h>
#include <unistd.h>

#include "ferry.h"

/* ---- malloc ------------------------------------------------------------------------- */

/* A size malloc would round the block up to anyway: 16-byte steps for small
 * blocks, whole pages for large ones. */
static size_t mac_malloc_good_size(size_t size)
{
    if (size == 0)
        return 16;
    if (size <= 1024)
        return (size + 15) & ~(size_t)15;
    if (size <= 128 * 1024)
        return (size + 511) & ~(size_t)511;
    return (size + 4095) & ~(size_t)4095;
}

struct mac_zone {
    char name[64];
};

static struct mac_zone default_zone = {"DefaultMallocZone"};
static struct mac_zone purgeable_zone = {"DefaultPurgeableMallocZone"};

static struct mac_zone *mac_malloc_default_zone(void) { return &default_zone; }
static struct mac_zone *mac_malloc_default_purgeable_zone(void) { return &purgeable_zone; }

static struct mac_zone *mac_malloc_create_zone(size_t start, unsigned flags)
{
    struct mac_zone *z = calloc(1, sizeof *z);
    if (z)
        strcpy(z->name, "Zone");
    return z;
}

static void mac_malloc_destroy_zone(struct mac_zone *z)
{
    if (z && z != &default_zone && z != &purgeable_zone)
        free(z);
}

static struct mac_zone *mac_malloc_zone_from_ptr(const void *p) { return p ? &default_zone : NULL; }
static void *mac_malloc_zone_malloc(struct mac_zone *z, size_t size) { return malloc(size); }
static void *mac_malloc_zone_calloc(struct mac_zone *z, size_t n, size_t size) { return calloc(n, size); }
static void *mac_malloc_zone_valloc(struct mac_zone *z, size_t size) { return valloc(size); }
static void *mac_malloc_zone_realloc(struct mac_zone *z, void *p, size_t size) { return realloc(p, size); }
static void mac_malloc_zone_free(struct mac_zone *z, void *p) { free(p); }
static size_t mac_malloc_zone_pressure_relief(struct mac_zone *z, size_t goal) { return 0; }

static void *mac_malloc_zone_memalign(struct mac_zone *z, size_t align, size_t size)
{
    void *p = NULL;
    return posix_memalign(&p, align < sizeof(void *) ? sizeof(void *) : align, size) ? NULL : p;
}

static void mac_malloc_set_zone_name(struct mac_zone *z, const char *name)
{
    if (z && name) {
        strncpy(z->name, name, sizeof z->name - 1);
        z->name[sizeof z->name - 1] = 0;
    }
}

static const char *mac_malloc_get_zone_name(struct mac_zone *z) { return z ? z->name : NULL; }

/* ---- basename and dirname ----------------------------------------------------------- */

#define MAC_MAXPATHLEN 1024

static char *mac_basename_r(const char *path, char *out)
{
    if (!path || !*path) {
        strcpy(out, ".");
        return out;
    }
    const char *end = path + strlen(path);
    while (end > path + 1 && end[-1] == '/')
        end--;
    const char *start = end;
    while (start > path && start[-1] != '/')
        start--;
    if (start == end) { /* only slashes */
        strcpy(out, "/");
        return out;
    }
    size_t len = (size_t)(end - start);
    if (len >= MAC_MAXPATHLEN) {
        errno = ENAMETOOLONG;
        return NULL;
    }
    memcpy(out, start, len);
    out[len] = 0;
    return out;
}

static char *mac_dirname_r(const char *path, char *out)
{
    if (!path || !*path) {
        strcpy(out, ".");
        return out;
    }
    const char *end = path + strlen(path);
    while (end > path + 1 && end[-1] == '/')
        end--;
    while (end > path && end[-1] != '/')
        end--;
    if (end == path) {
        strcpy(out, *path == '/' ? "/" : ".");
        return out;
    }
    while (end > path + 1 && end[-1] == '/')
        end--;
    size_t len = (size_t)(end - path);
    if (len >= MAC_MAXPATHLEN) {
        errno = ENAMETOOLONG;
        return NULL;
    }
    memcpy(out, path, len);
    out[len] = 0;
    return out;
}

static __thread char base_buf[MAC_MAXPATHLEN], dir_buf[MAC_MAXPATHLEN];
static char *mac_basename(char *path) { return mac_basename_r(path, base_buf); }
static char *mac_dirname(char *path) { return mac_dirname_r(path, dir_buf); }

/* ---- extended attributes ------------------------------------------------------------ */

#define MAC_XATTR_NOFOLLOW 0x0001
#define MAC_XATTR_CREATE 0x0002
#define MAC_XATTR_REPLACE 0x0004
#define MAC_ENOATTR 93

/* The Mac name under this system's user. prefix; 0 and errno if it can't be. */
static int linux_name(const char *name, char *out, size_t size)
{
    if (!name || !*name) {
        errno = EINVAL;
        return 0;
    }
    if ((size_t)snprintf(out, size, "user.%s", name) >= size) {
        errno = ENAMETOOLONG;
        return 0;
    }
    return 1;
}

/* A missing attribute reads ENOATTR on a Mac, which has no Linux twin. */
static void missing_attribute(void)
{
    if (errno == ENODATA) {
        errno = 0;
        ferry_set_mac_errno(MAC_ENOATTR);
    }
}

static int position_ok(uint32_t position)
{
    if (position) {
        errno = EINVAL;
        return 0;
    }
    return 1;
}

static ssize_t mac_getxattr(const char *path, const char *name, void *value, size_t size, uint32_t position,
                            int options)
{
    char n[XATTR_NAME_MAX + 1];
    if (!linux_name(name, n, sizeof n) || !position_ok(position))
        return -1;
    ssize_t r = (options & MAC_XATTR_NOFOLLOW) ? lgetxattr(path, n, value, size) : getxattr(path, n, value, size);
    if (r < 0)
        missing_attribute();
    return r;
}

static ssize_t mac_fgetxattr(int fd, const char *name, void *value, size_t size, uint32_t position, int options)
{
    char n[XATTR_NAME_MAX + 1];
    if (!linux_name(name, n, sizeof n) || !position_ok(position))
        return -1;
    ssize_t r = fgetxattr(fd, n, value, size);
    if (r < 0)
        missing_attribute();
    return r;
}

static int set_flags(int options)
{
    return (options & MAC_XATTR_CREATE ? XATTR_CREATE : 0) | (options & MAC_XATTR_REPLACE ? XATTR_REPLACE : 0);
}

static int mac_setxattr(const char *path, const char *name, const void *value, size_t size, uint32_t position,
                        int options)
{
    char n[XATTR_NAME_MAX + 1];
    if (!linux_name(name, n, sizeof n) || !position_ok(position))
        return -1;
    int r = (options & MAC_XATTR_NOFOLLOW) ? lsetxattr(path, n, value, size, set_flags(options))
                                           : setxattr(path, n, value, size, set_flags(options));
    if (r < 0)
        missing_attribute();
    return r;
}

static int mac_fsetxattr(int fd, const char *name, const void *value, size_t size, uint32_t position, int options)
{
    char n[XATTR_NAME_MAX + 1];
    if (!linux_name(name, n, sizeof n) || !position_ok(position))
        return -1;
    int r = fsetxattr(fd, n, value, size, set_flags(options));
    if (r < 0)
        missing_attribute();
    return r;
}

static int mac_removexattr(const char *path, const char *name, int options)
{
    char n[XATTR_NAME_MAX + 1];
    if (!linux_name(name, n, sizeof n))
        return -1;
    int r = (options & MAC_XATTR_NOFOLLOW) ? lremovexattr(path, n) : removexattr(path, n);
    if (r < 0)
        missing_attribute();
    return r;
}

static int mac_fremovexattr(int fd, const char *name, int options)
{
    char n[XATTR_NAME_MAX + 1];
    if (!linux_name(name, n, sizeof n))
        return -1;
    int r = fremovexattr(fd, n);
    if (r < 0)
        missing_attribute();
    return r;
}

/* This system's list, with only the user. names, the prefix taken off. */
static ssize_t mac_names(ssize_t got, char *all, char *out, size_t size)
{
    if (got < 0)
        return -1;
    size_t need = 0;
    for (char *p = all; p < all + got; p += strlen(p) + 1) {
        if (strncmp(p, "user.", 5))
            continue;
        size_t len = strlen(p + 5) + 1;
        if (out && size) {
            if (need + len > size) {
                errno = ERANGE;
                return -1;
            }
            memcpy(out + need, p + 5, len);
        }
        need += len;
    }
    return (ssize_t)need;
}

static ssize_t list_names(const char *path, int fd, int options, char *out, size_t size)
{
    for (int tries = 0; tries < 4; tries++) {
        ssize_t len = path ? ((options & MAC_XATTR_NOFOLLOW) ? llistxattr(path, NULL, 0) : listxattr(path, NULL, 0))
                           : flistxattr(fd, NULL, 0);
        if (len <= 0)
            return len;
        char *all = malloc((size_t)len);
        if (!all) {
            errno = ENOMEM;
            return -1;
        }
        ssize_t got = path ? ((options & MAC_XATTR_NOFOLLOW) ? llistxattr(path, all, (size_t)len)
                                                             : listxattr(path, all, (size_t)len))
                           : flistxattr(fd, all, (size_t)len);
        if (got < 0 && errno == ERANGE) { /* the list grew between the two calls */
            free(all);
            continue;
        }
        ssize_t r = mac_names(got, all, out, size);
        free(all);
        return r;
    }
    errno = ERANGE;
    return -1;
}

static ssize_t mac_listxattr(const char *path, char *out, size_t size, int options)
{
    return list_names(path, -1, options, out, size);
}

static ssize_t mac_flistxattr(int fd, char *out, size_t size, int options)
{
    return list_names(NULL, fd, options, out, size);
}

/* ---- fts ---------------------------------------------------------------------------- */

struct mac_ftsent {
    struct mac_ftsent *cycle, *parent, *link;
    long number;
    void *pointer;
    char *accpath, *path;
    int err, symfd;
    unsigned short pathlen, namelen;
    uint64_t ino;
    int32_t dev;
    uint16_t nlink;
    short level;
    unsigned short info, flags, instr;
    void *statp;
    char name[1];
};
_Static_assert(__builtin_offsetof(struct mac_ftsent, ino) == 72, "fts_ino offset");
_Static_assert(__builtin_offsetof(struct mac_ftsent, statp) == 96, "fts_statp offset");
_Static_assert(__builtin_offsetof(struct mac_ftsent, name) == 104, "fts_name offset");

/* A Mac entry and the entry it copies; the Mac entry is last so that its
 * name can run on. */
struct shadow {
    struct shadow *next; /* every copy, freed at fts_close */
    FTSENT *host;
    size_t room;           /* bytes for the name */
    unsigned char st[144]; /* the Mac struct stat */
    struct mac_ftsent mac;
};

typedef int (*mac_compar)(const struct mac_ftsent **, const struct mac_ftsent **);

struct mac_fts {
    FTS *host;
    mac_compar compar;
    struct shadow *all;
};

static __thread struct mac_fts *current_fts; /* for the comparison function */

/* The Mac copy of an entry: made the first time, brought up to date after.
 * This system's fts clears fts_pointer in each entry it makes, so the
 * pointer finds the copy. */
static struct mac_ftsent *shadow_of(struct mac_fts *f, FTSENT *e)
{
    if (!e)
        return NULL;
    struct shadow *sh = e->fts_pointer;
    if (!sh || sh->host != e || sh->room <= e->fts_namelen) {
        sh = calloc(1, sizeof *sh + e->fts_namelen + 1);
        if (!sh)
            return NULL;
        sh->host = e;
        sh->room = e->fts_namelen + 1;
        sh->next = f->all;
        f->all = sh;
        e->fts_pointer = sh;
    }
    struct mac_ftsent *m = &sh->mac;
    m->accpath = e->fts_accpath;
    m->path = e->fts_path;
    m->err = e->fts_errno;
    m->symfd = e->fts_symfd;
    m->pathlen = e->fts_pathlen;
    m->namelen = e->fts_namelen;
    m->ino = e->fts_ino;
    m->dev = (int32_t)((major(e->fts_dev) << 24) | (minor(e->fts_dev) & 0xffffff));
    m->nlink = e->fts_nlink > 0xffff ? 0xffff : (uint16_t)e->fts_nlink;
    m->level = e->fts_level;
    m->info = e->fts_info;
    m->flags = e->fts_flags;
    m->instr = e->fts_instr;
    memcpy(m->name, e->fts_name, e->fts_namelen);
    m->name[e->fts_namelen] = 0;
    if (e->fts_statp && e->fts_info != FTS_NS && e->fts_info != FTS_NSOK)
        ferry_to_mac_stat(e->fts_statp, sh->st);
    else
        memset(sh->st, 0, sizeof sh->st);
    m->statp = sh->st;
    /* the directories above, up to the starting point's parent */
    m->parent = e->fts_level > FTS_ROOTPARENTLEVEL ? shadow_of(f, e->fts_parent) : NULL;
    m->cycle = e->fts_info == FTS_DC ? shadow_of(f, e->fts_cycle) : NULL;
    m->link = NULL;
    return m;
}

static int compar_trampoline(const FTSENT **a, const FTSENT **b)
{
    struct mac_fts *f = current_fts;
    const struct mac_ftsent *ma = shadow_of(f, (FTSENT *)*a), *mb = shadow_of(f, (FTSENT *)*b);
    return f->compar(&ma, &mb);
}

static struct mac_fts *mac_fts_open(char *const *paths, int options, mac_compar compar)
{
    struct mac_fts *f = calloc(1, sizeof *f);
    if (!f)
        return NULL;
    f->compar = compar;
    struct mac_fts *saved = current_fts;
    current_fts = f;
    /* the options below 0x100 are the same here; the Mac's own ones
     * (FTS_NAMEONLY, FTS_STOP, FTS_COMFOLLOWDIR) have no counterpart */
    f->host = fts_open(paths, options & 0xff, compar ? compar_trampoline : NULL);
    current_fts = saved;
    if (!f->host) {
        free(f);
        return NULL;
    }
    return f;
}

static struct mac_ftsent *mac_fts_read(struct mac_fts *f)
{
    struct mac_fts *saved = current_fts;
    current_fts = f;
    struct mac_ftsent *m = shadow_of(f, fts_read(f->host));
    current_fts = saved;
    return m;
}

static struct mac_ftsent *mac_fts_children(struct mac_fts *f, int options)
{
    struct mac_fts *saved = current_fts;
    current_fts = f;
    struct mac_ftsent *first = NULL, *prev = NULL;
    for (FTSENT *e = fts_children(f->host, options & 0xff); e; e = e->fts_link) {
        struct mac_ftsent *m = shadow_of(f, e);
        if (!m)
            break;
        if (prev)
            prev->link = m;
        else
            first = m;
        prev = m;
    }
    current_fts = saved;
    return first;
}

static int mac_fts_set(struct mac_fts *f, struct mac_ftsent *m, int instr)
{
    struct shadow *sh = (struct shadow *)((char *)m - __builtin_offsetof(struct shadow, mac));
    return fts_set(f->host, sh->host, instr);
}

static int mac_fts_close(struct mac_fts *f)
{
    if (!f)
        return 0;
    int rc = fts_close(f->host);
    while (f->all) {
        struct shadow *next = f->all->next;
        free(f->all);
        f->all = next;
    }
    free(f);
    return rc;
}

/* ---- statfs --------------------------------------------------------------------------- */

struct mac_statfs {
    uint32_t bsize;
    int32_t iosize;
    uint64_t blocks, bfree, bavail, files, ffree;
    int32_t fsid[2];
    uint32_t owner, type, flags, fssubtype;
    char fstypename[16];
    char mntonname[1024];
    char mntfromname[1024];
    uint32_t flags_ext;
    uint32_t reserved[7];
};
_Static_assert(sizeof(struct mac_statfs) == 2168, "Mac struct statfs is 2168 bytes");

#define MAC_MNT_RDONLY 0x1
#define MAC_MNT_SYNCHRONOUS 0x2
#define MAC_MNT_NOEXEC 0x4
#define MAC_MNT_NOSUID 0x8
#define MAC_MNT_NODEV 0x10
#define MAC_MNT_LOCAL 0x1000
#define MAC_MNT_ROOTFS 0x4000
#define MAC_MNT_NOATIME 0x10000000

/* The mount the device is on, from /proc/self/mountinfo: its mount point,
 * kind and source. Of several mounts of one device, the one whose mount
 * point is the longest start of the path, when there is a path. */
static void fill_mount(struct mac_statfs *m, dev_t dev, const char *path)
{
    FILE *f = fopen("/proc/self/mountinfo", "re");
    if (!f)
        return;
    char line[4096];
    size_t best = 0;
    int found = 0;
    while (fgets(line, sizeof line, f)) {
        unsigned maj, min;
        char root[1024], point[1024];
        if (sscanf(line, "%*d %*d %u:%u %1023s %1023s", &maj, &min, root, point) != 4)
            continue;
        if (makedev(maj, min) != dev)
            continue;
        size_t len = strlen(point);
        int prefix = path && strncmp(path, point, len) == 0 && (len == 1 || path[len] == '/' || path[len] == 0);
        if (found && !(prefix && len > best))
            continue;
        char *dash = strstr(line, " - ");
        char type[64] = "", source[1024] = "";
        if (dash)
            sscanf(dash + 3, "%63s %1023s", type, source);
        snprintf(m->mntonname, sizeof m->mntonname, "%s", point);
        snprintf(m->mntfromname, sizeof m->mntfromname, "%s", source);
        snprintf(m->fstypename, sizeof m->fstypename, "%s", type);
        if (strcmp(point, "/") == 0)
            m->flags |= MAC_MNT_ROOTFS;
        else
            m->flags &= ~MAC_MNT_ROOTFS;
        best = prefix ? len : 0;
        found = 1;
    }
    fclose(f);
}

static void to_mac_statfs(const struct statfs *s, const struct statvfs *v, struct mac_statfs *m)
{
    memset(m, 0, sizeof *m);
    m->bsize = (uint32_t)s->f_bsize;
    m->iosize = (int32_t)s->f_bsize;
    m->blocks = s->f_blocks;
    m->bfree = s->f_bfree;
    m->bavail = s->f_bavail;
    m->files = s->f_files;
    m->ffree = s->f_ffree;
    memcpy(m->fsid, &s->f_fsid, sizeof m->fsid);
    m->type = (uint32_t)s->f_type;
    static const struct { unsigned long host; uint32_t mac; } flags[] = {
        {ST_RDONLY, MAC_MNT_RDONLY}, {ST_NOSUID, MAC_MNT_NOSUID},           {ST_NODEV, MAC_MNT_NODEV},
        {ST_NOEXEC, MAC_MNT_NOEXEC}, {ST_SYNCHRONOUS, MAC_MNT_SYNCHRONOUS}, {ST_NOATIME, MAC_MNT_NOATIME},
    };
    for (size_t i = 0; i < sizeof flags / sizeof flags[0]; i++)
        if (v->f_flag & flags[i].host)
            m->flags |= flags[i].mac;
    m->flags |= MAC_MNT_LOCAL;
}

static int mac_statfs64(const char *path, struct mac_statfs *out)
{
    struct statfs s;
    struct statvfs v;
    struct stat st;
    if (statfs(path, &s) || statvfs(path, &v) || stat(path, &st))
        return -1;
    to_mac_statfs(&s, &v, out);
    char real[PATH_MAX];
    fill_mount(out, st.st_dev, realpath(path, real) ? real : NULL);
    return 0;
}

static int mac_fstatfs64(int fd, struct mac_statfs *out)
{
    struct statfs s;
    struct statvfs v;
    struct stat st;
    if (fstatfs(fd, &s) || fstatvfs(fd, &v) || fstat(fd, &st))
        return -1;
    to_mac_statfs(&s, &v, out);
    char link[64], real[PATH_MAX];
    snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
    ssize_t n = readlink(link, real, sizeof real - 1);
    if (n > 0)
        real[n] = 0;
    fill_mount(out, st.st_dev, n > 0 ? real : NULL);
    return 0;
}

/* ---- asl ------------------------------------------------------------------------------ */

#define ASL_KEYS 16
#define ASL_FILES 8
struct asl_object {
    int is_client;
    /* a client */
    char *ident;
    int filter;
    int files[ASL_FILES];
    int nfiles;
    /* a message */
    char *keys[ASL_KEYS], *values[ASL_KEYS];
};

static pthread_mutex_t asl_lock = PTHREAD_MUTEX_INITIALIZER;
static struct asl_object *asl_default;

static const char *const level_names[] = {"Emergency", "Alert", "Critical", "Error",
                                          "Warning",   "Notice", "Info",   "Debug"};

static struct asl_object *mac_asl_open(const char *ident, const char *facility, uint32_t opts)
{
    (void)facility;
    struct asl_object *c = calloc(1, sizeof *c);
    if (!c)
        return NULL;
    c->is_client = 1;
    c->ident = strdup(ident ? ident : program_invocation_short_name);
    c->filter = (1 << 6) - 1; /* up to Notice, as on a Mac */
    if (opts & 0x1)           /* ASL_OPT_STDERR */
        c->files[c->nfiles++] = 2;
    return c;
}

static void mac_asl_free(struct asl_object *o)
{
    if (!o)
        return;
    if (o->is_client)
        free(o->ident);
    for (int i = 0; i < ASL_KEYS; i++) {
        free(o->keys[i]);
        free(o->values[i]);
    }
    free(o);
}

static struct asl_object *mac_asl_new(uint32_t type)
{
    (void)type;
    return calloc(1, sizeof(struct asl_object));
}

static int mac_asl_set(struct asl_object *m, const char *key, const char *value)
{
    if (!m || m->is_client || !key)
        return -1;
    int free_slot = -1;
    for (int i = 0; i < ASL_KEYS; i++) {
        if (m->keys[i] && strcmp(m->keys[i], key) == 0) {
            free(m->values[i]);
            m->values[i] = value ? strdup(value) : NULL;
            return 0;
        }
        if (!m->keys[i] && free_slot < 0)
            free_slot = i;
    }
    if (free_slot < 0)
        return -1;
    m->keys[free_slot] = strdup(key);
    m->values[free_slot] = value ? strdup(value) : NULL;
    return 0;
}

static const char *mac_asl_get(struct asl_object *m, const char *key)
{
    if (!m || m->is_client || !key)
        return NULL;
    for (int i = 0; i < ASL_KEYS; i++)
        if (m->keys[i] && strcmp(m->keys[i], key) == 0)
            return m->values[i];
    return NULL;
}

static int mac_asl_unset(struct asl_object *m, const char *key)
{
    if (!m || m->is_client || !key)
        return -1;
    for (int i = 0; i < ASL_KEYS; i++)
        if (m->keys[i] && strcmp(m->keys[i], key) == 0) {
            free(m->keys[i]);
            free(m->values[i]);
            m->keys[i] = m->values[i] = NULL;
        }
    return 0;
}

/* One message, to syslog and to the client's files as
 * "ident[pid] <Level>: text". With no client, the program's own. */
static int emit(struct asl_object *c, int level, const char *text)
{
    if (level < 0)
        level = 0;
    if (level > 7)
        level = 7;
    if (!c) {
        pthread_mutex_lock(&asl_lock);
        if (!asl_default)
            asl_default = mac_asl_open(NULL, NULL, 0);
        c = asl_default;
        pthread_mutex_unlock(&asl_lock);
        if (!c)
            return -1;
    }
    if (!(c->filter & (1 << level)))
        return 0;
    syslog(level, "%s", text);
    for (int i = 0; i < c->nfiles; i++)
        dprintf(c->files[i], "%s[%d] <%s>: %s\n", c->ident, (int)getpid(), level_names[level], text);
    return 0;
}

static int mac_asl_send(struct asl_object *c, struct asl_object *m)
{
    if (!m || m->is_client)
        return -1;
    const char *text = mac_asl_get(m, "Message"), *level = mac_asl_get(m, "Level");
    return emit(c, level ? atoi(level) : 5, text ? text : "");
}

static int mac_asl_vlog(struct asl_object *c, struct asl_object *m, int level, const char *format, va_list ap)
{
    (void)m;
    char *text = NULL;
    if (vasprintf(&text, format, ap) < 0)
        return -1;
    int rc = emit(c, level, text);
    free(text);
    return rc;
}

static int mac_asl_log(struct asl_object *c, struct asl_object *m, int level, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    int rc = mac_asl_vlog(c, m, level, format, ap);
    va_end(ap);
    return rc;
}

static int mac_asl_set_filter(struct asl_object *c, int filter)
{
    if (!c)
        return 0;
    int old = c->filter;
    c->filter = filter;
    return old;
}

static int mac_asl_add_log_file(struct asl_object *c, int fd)
{
    if (!c || !c->is_client || c->nfiles >= ASL_FILES)
        return -1;
    for (int i = 0; i < c->nfiles; i++)
        if (c->files[i] == fd)
            return 0;
    c->files[c->nfiles++] = fd;
    return 0;
}

static int mac_asl_remove_log_file(struct asl_object *c, int fd)
{
    if (!c || !c->is_client)
        return -1;
    for (int i = 0; i < c->nfiles; i++)
        if (c->files[i] == fd) {
            c->files[i] = c->files[--c->nfiles];
            return 0;
        }
    return -1;
}

/* memset_pattern4, 8 and 16 (freemac 1.226, Ferry 0.50.0): fill len
 * bytes with a 4-, 8- or 16-byte pattern repeated, the last copy cut
 * short. Clang calls memset_pattern16 by itself when it compiles a loop
 * that stores the same 16 bytes over and over for a Mac. */
static void fill_pattern(void *b, const void *pattern, size_t n, size_t len)
{
    unsigned char *p = b;
    while (len >= n) {
        memcpy(p, pattern, n);
        p += n;
        len -= n;
    }
    memcpy(p, pattern, len);
}
static void mac_memset_pattern4(void *b, const void *pattern, size_t len) { fill_pattern(b, pattern, 4, len); }
static void mac_memset_pattern8(void *b, const void *pattern, size_t len) { fill_pattern(b, pattern, 8, len); }
static void mac_memset_pattern16(void *b, const void *pattern, size_t len) { fill_pattern(b, pattern, 16, len); }

/* the log can't be searched: no results */
static void *mac_asl_search(void *c, void *q)
{
    (void)c;
    (void)q;
    return NULL;
}
static void *mac_aslresponse_next(void *r)
{
    (void)r;
    return NULL;
}
static void mac_aslresponse_free(void *r) { (void)r; }
/* A query's conditions are kept as its keys and values (the operation is
 * not needed, since nothing is searched). */
static int mac_asl_set_query(struct asl_object *q, const char *key, const char *value, uint32_t op)
{
    (void)op;
    return mac_asl_set(q, key, value ? value : "");
}

const struct ferry_symbol ferry_libc_more_symbols[] = {
    {"malloc_good_size", mac_malloc_good_size},
    {"memset_pattern4", mac_memset_pattern4},
    {"memset_pattern8", mac_memset_pattern8},
    {"memset_pattern16", mac_memset_pattern16},
    {"malloc_default_zone", mac_malloc_default_zone},
    {"malloc_default_purgeable_zone", mac_malloc_default_purgeable_zone},
    {"malloc_create_zone", mac_malloc_create_zone},
    {"malloc_destroy_zone", mac_malloc_destroy_zone},
    {"malloc_zone_from_ptr", mac_malloc_zone_from_ptr},
    {"malloc_zone_malloc", mac_malloc_zone_malloc},
    {"malloc_zone_calloc", mac_malloc_zone_calloc},
    {"malloc_zone_valloc", mac_malloc_zone_valloc},
    {"malloc_zone_realloc", mac_malloc_zone_realloc},
    {"malloc_zone_memalign", mac_malloc_zone_memalign},
    {"malloc_zone_free", mac_malloc_zone_free},
    {"malloc_zone_pressure_relief", mac_malloc_zone_pressure_relief},
    {"malloc_set_zone_name", mac_malloc_set_zone_name},
    {"malloc_get_zone_name", mac_malloc_get_zone_name},
    {"basename", mac_basename},
    {"basename_r", mac_basename_r},
    {"dirname", mac_dirname},
    {"dirname_r", mac_dirname_r},
    {"getxattr", mac_getxattr},
    {"fgetxattr", mac_fgetxattr},
    {"setxattr", mac_setxattr},
    {"fsetxattr", mac_fsetxattr},
    {"removexattr", mac_removexattr},
    {"fremovexattr", mac_fremovexattr},
    {"listxattr", mac_listxattr},
    {"flistxattr", mac_flistxattr},
    {"fts_open$INODE64", mac_fts_open},
    {"fts_read$INODE64", mac_fts_read},
    {"fts_children$INODE64", mac_fts_children},
    {"fts_set$INODE64", mac_fts_set},
    {"fts_close$INODE64", mac_fts_close},
    {"statfs$INODE64", mac_statfs64},
    {"fstatfs$INODE64", mac_fstatfs64},
    {"statfs64", mac_statfs64},
    {"fstatfs64", mac_fstatfs64},
    {"asl_open", mac_asl_open},
    {"asl_close", mac_asl_free},
    {"asl_new", mac_asl_new},
    {"asl_free", mac_asl_free},
    {"asl_release", mac_asl_free},
    {"asl_set", mac_asl_set},
    {"asl_get", mac_asl_get},
    {"asl_unset", mac_asl_unset},
    {"asl_send", mac_asl_send},
    {"asl_log", mac_asl_log},
    {"asl_vlog", mac_asl_vlog},
    {"asl_set_filter", mac_asl_set_filter},
    {"asl_add_log_file", mac_asl_add_log_file},
    {"asl_remove_log_file", mac_asl_remove_log_file},
    {"asl_search", mac_asl_search},
    {"aslresponse_next", mac_aslresponse_next},
    {"aslresponse_free", mac_aslresponse_free},
    {"asl_set_query", mac_asl_set_query},
    {"asl_next", mac_aslresponse_next},
    {NULL, NULL},
};
