/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * C library calls the nine apps make that need converting (freemac 1.221,
 * Ferry 0.45.0), each written from its Mac man page:
 *
 * - malloc_good_size(3) and the malloc zones of malloc_zone_malloc(3).
 *   There is one heap, this system's, so every block can be given back
 *   with free() as on a Mac, and malloc_zone_from_ptr answers the default
 *   zone. Zones are laid out as the Mac's malloc_zone_t, with function
 *   pointers a program can call (1.263); destroying one leaves its blocks
 *   allocated, since they may since have been freed one by one.
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
#include <math.h>
#include <pthread.h>
#include <regex.h>
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

/* A zone is laid out as malloc_zone_t in the Mac's <malloc/malloc.h>
 * (freemac 1.263): programs such as SQLite call through its function
 * pointers rather than the malloc_zone_ calls. Every one of them uses this
 * system's one heap. */
struct mac_zone;
struct mac_zone {
    void *reserved1, *reserved2;
    size_t (*size)(struct mac_zone *, const void *);
    void *(*malloc)(struct mac_zone *, size_t);
    void *(*calloc)(struct mac_zone *, size_t, size_t);
    void *(*valloc)(struct mac_zone *, size_t);
    void (*free)(struct mac_zone *, void *);
    void *(*realloc)(struct mac_zone *, void *, size_t);
    void (*destroy)(struct mac_zone *);
    const char *zone_name;
    unsigned (*batch_malloc)(struct mac_zone *, size_t, void **, unsigned);
    void (*batch_free)(struct mac_zone *, void **, unsigned);
    void *introspect;
    unsigned version;
    void *(*memalign)(struct mac_zone *, size_t, size_t);
    void (*free_definite_size)(struct mac_zone *, void *, size_t);
    size_t (*pressure_relief)(struct mac_zone *, size_t);
    int (*claimed_address)(struct mac_zone *, void *);
    void (*try_free_default)(struct mac_zone *, void *);
    char name[64]; /* Ferry's own, after the Mac's fields */
};

static size_t zone_size(struct mac_zone *z, const void *p) { (void)z; return p ? malloc_usable_size((void *)p) : 0; }
static void *mac_malloc_zone_malloc(struct mac_zone *z, size_t size) { (void)z; return malloc(size); }
static void *mac_malloc_zone_calloc(struct mac_zone *z, size_t n, size_t size) { (void)z; return calloc(n, size); }
static void *mac_malloc_zone_valloc(struct mac_zone *z, size_t size) { (void)z; return valloc(size); }
static void *mac_malloc_zone_realloc(struct mac_zone *z, void *p, size_t size) { (void)z; return realloc(p, size); }
static void mac_malloc_zone_free(struct mac_zone *z, void *p) { (void)z; free(p); }
static size_t mac_malloc_zone_pressure_relief(struct mac_zone *z, size_t goal) { (void)z; (void)goal; return 0; }
static void zone_free_definite(struct mac_zone *z, void *p, size_t size) { (void)z; (void)size; free(p); }
static int zone_claimed(struct mac_zone *z, void *p) { (void)z; (void)p; return 1; }

static void *mac_malloc_zone_memalign(struct mac_zone *z, size_t align, size_t size)
{
    (void)z;
    void *p = NULL;
    return posix_memalign(&p, align < sizeof(void *) ? sizeof(void *) : align, size) ? NULL : p;
}

static unsigned zone_batch_malloc(struct mac_zone *z, size_t size, void **out, unsigned n)
{
    (void)z;
    unsigned i = 0;
    for (; i < n && (out[i] = malloc(size)); i++)
        ;
    return i;
}

static void zone_batch_free(struct mac_zone *z, void **p, unsigned n)
{
    (void)z;
    for (unsigned i = 0; i < n; i++)
        free(p[i]);
}

static void mac_malloc_destroy_zone(struct mac_zone *z);

/* the introspection table's calls (enumerator, good_size, check, print,
 * log, force_lock, force_unlock, statistics, zone_locked and the rest):
 * nothing to report about one shared heap */
static uintptr_t zone_nothing(void) { return 0; }
static size_t zone_good_size(struct mac_zone *z, size_t size) { (void)z; return mac_malloc_good_size(size); }
static void *zone_introspect[] = {
    (void *)zone_nothing, (void *)zone_good_size, (void *)zone_nothing, (void *)zone_nothing,
    (void *)zone_nothing, (void *)zone_nothing,   (void *)zone_nothing, (void *)zone_nothing,
    (void *)zone_nothing, (void *)zone_nothing,   (void *)zone_nothing, (void *)zone_nothing,
    (void *)zone_nothing, (void *)zone_nothing,   (void *)zone_nothing, (void *)zone_nothing,
};

#define ZONE_INIT(n)                                                                                       \
    {                                                                                                      \
        NULL, NULL, zone_size, mac_malloc_zone_malloc, mac_malloc_zone_calloc, mac_malloc_zone_valloc,     \
            mac_malloc_zone_free, mac_malloc_zone_realloc, mac_malloc_destroy_zone, NULL, zone_batch_malloc, \
            zone_batch_free, zone_introspect, 13, mac_malloc_zone_memalign, zone_free_definite,              \
            mac_malloc_zone_pressure_relief, zone_claimed, mac_malloc_zone_free, n                         \
    }

static struct mac_zone default_zone = ZONE_INIT("DefaultMallocZone");
static struct mac_zone purgeable_zone = ZONE_INIT("DefaultPurgeableMallocZone");

static struct mac_zone *zone_named(struct mac_zone *z)
{
    if (!z->zone_name)
        z->zone_name = z->name;
    return z;
}

static struct mac_zone *mac_malloc_default_zone(void) { return zone_named(&default_zone); }
static struct mac_zone *mac_malloc_default_purgeable_zone(void) { return zone_named(&purgeable_zone); }

static void mac_malloc_zone_register(void *zone);
static void mac_malloc_zone_unregister(void *zone);

static struct mac_zone *mac_malloc_create_zone(size_t start, unsigned flags)
{
    (void)start; (void)flags;
    struct mac_zone *z = malloc(sizeof *z);
    if (z) {
        *z = (struct mac_zone)ZONE_INIT("Zone");
        z->zone_name = z->name;
        mac_malloc_zone_register(z); /* a new zone is listed, as on a Mac */
    }
    return z;
}

/* malloc_get_all_zones lists the registered zones, the default first.
 * malloc_zone_register adds a zone at the end, and malloc_zone_unregister
 * takes one out by moving the last zone into its place, as on a Mac: a
 * program that wants its own zone to come first (Chromium's PartitionAlloc
 * does, in every Electron app) registers it, then unregisters and
 * registers the default zone again, and checks that its zone is now the
 * first one listed. The zones are only listed: this system's malloc still
 * serves every block, whichever zone a program puts first.
 * malloc_zone_statistics reports this system's figures (freemac Blender
 * work). */
#define MAX_ZONES 64
static uintptr_t registered_zones[MAX_ZONES];
static unsigned registered_count;
static pthread_mutex_t zones_lock = PTHREAD_MUTEX_INITIALIZER;

static void zones_start(void)
{
    if (!registered_count) {
        registered_zones[0] = (uintptr_t)zone_named(&default_zone);
        registered_count = 1;
    }
}

static int mac_malloc_get_all_zones(unsigned task, void *reader, uintptr_t **addresses, unsigned *count)
{
    (void)task; (void)reader;
    pthread_mutex_lock(&zones_lock);
    zones_start();
    if (addresses)
        *addresses = registered_zones;
    if (count)
        *count = registered_count;
    pthread_mutex_unlock(&zones_lock);
    return 0;
}
static void mac_malloc_zone_register(void *zone)
{
    if (!zone)
        return;
    pthread_mutex_lock(&zones_lock);
    zones_start();
    if (registered_count < MAX_ZONES)
        registered_zones[registered_count++] = (uintptr_t)zone;
    pthread_mutex_unlock(&zones_lock);
}
static void mac_malloc_zone_unregister(void *zone)
{
    pthread_mutex_lock(&zones_lock);
    zones_start();
    for (unsigned i = 0; i < registered_count; i++)
        if (registered_zones[i] == (uintptr_t)zone) {
            registered_zones[i] = registered_zones[--registered_count];
            registered_zones[registered_count] = 0;
            break;
        }
    pthread_mutex_unlock(&zones_lock);
}

struct mac_malloc_statistics {
    unsigned blocks_in_use;
    size_t size_in_use, max_size_in_use, size_allocated;
};

static void mac_malloc_zone_statistics(void *zone, struct mac_malloc_statistics *st)
{
    if (!st)
        return;
    struct mallinfo2 mi = mallinfo2();
    st->blocks_in_use = (unsigned)(mi.ordblks + mi.hblks);
    st->size_in_use = mi.uordblks + mi.hblkhd;
    st->max_size_in_use = st->size_in_use;
    st->size_allocated = mi.arena + mi.hblkhd;
}

static void mac_malloc_destroy_zone(struct mac_zone *z)
{
    if (z && z != &default_zone && z != &purgeable_zone) {
        mac_malloc_zone_unregister(z);
        free(z);
    }
}

static struct mac_zone *mac_malloc_zone_from_ptr(const void *p) { return p ? zone_named(&default_zone) : NULL; }

static void mac_malloc_set_zone_name(struct mac_zone *z, const char *name)
{
    if (z && name) {
        strncpy(z->name, name, sizeof z->name - 1);
        z->name[sizeof z->name - 1] = 0;
        z->zone_name = z->name;
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

/* getfsstat: the mounted disks, as Mac programs list volumes (a disk
 * picker, a free-space check). Linux's own kinds of mount (proc, sysfs,
 * cgroups and the like) are left out, as a Mac lists only its volumes and
 * devfs; a mount point seen twice is listed once. With no buffer, the
 * count. MNT_WAIT and MNT_NOWAIT read the same here. */
static int listed_mount(const char *type, const char *source)
{
    static const char *const kinds[] = {"ext2", "ext3", "ext4", "btrfs", "xfs", "vfat", "exfat", "ntfs", "ntfs3",
                                        "fuseblk", "f2fs", "hfsplus", "apfs", "iso9660", "udf", "overlay", NULL};
    if (strncmp(source, "/dev/", 5) == 0)
        return 1;
    for (int i = 0; kinds[i]; i++)
        if (strcmp(type, kinds[i]) == 0)
            return 1;
    return 0;
}

static int mac_getfsstat64(struct mac_statfs *buf, int bufsize, int mode)
{
    (void)mode;
    FILE *f = fopen("/proc/self/mountinfo", "re");
    if (!f)
        return -1;
    int room = buf && bufsize > 0 ? bufsize / (int)sizeof(struct mac_statfs) : 0;
    int count = 0;
    char line[4096];
    char (*seen)[1024] = NULL;
    while (fgets(line, sizeof line, f)) {
        char point[1024];
        if (sscanf(line, "%*d %*d %*u:%*u %*s %1023s", point) != 1)
            continue;
        char *dash = strstr(line, " - ");
        char type[64] = "", source[1024] = "";
        if (dash)
            sscanf(dash + 3, "%63s %1023s", type, source);
        if (!listed_mount(type, source))
            continue;
        int dup = 0;
        for (int i = 0; i < count && !dup; i++)
            dup = strcmp(seen[i], point) == 0;
        if (dup)
            continue;
        struct mac_statfs m;
        if (mac_statfs64(point, &m))
            continue;
        void *more = realloc(seen, (size_t)(count + 1) * sizeof *seen);
        if (!more)
            break;
        seen = more;
        snprintf(seen[count], sizeof seen[count], "%s", point);
        if (buf) {
            if (count >= room) {
                count++;
                break;
            }
            buf[count] = m;
        }
        count++;
    }
    fclose(f);
    free(seen);
    return buf && count > room ? room : count;
}

/* ---- classifying numbers -------------------------------------------------------------- */

/* What <math.h>'s fpclassify, isfinite, isinf, isnan, isnormal and signbit
 * call on a Mac when the compiler doesn't work them out itself. A Mac
 * numbers the kinds its own way: NaN 1, infinite 2, zero 3, normal 4,
 * subnormal 5. */
static int mac_fp_kind(int k)
{
    switch (k) {
    case FP_NAN: return 1;
    case FP_INFINITE: return 2;
    case FP_ZERO: return 3;
    case FP_SUBNORMAL: return 5;
    default: return 4;
    }
}

#define CLASSIFIERS(suffix, type)                                                                                    \
    static int mac_fpclassify##suffix(type x) { return mac_fp_kind(fpclassify(x)); }                                  \
    static int mac_isfinite##suffix(type x) { return isfinite(x) != 0; }                                              \
    static int mac_isinf##suffix(type x) { return isinf(x) != 0; }                                                    \
    static int mac_isnan##suffix(type x) { return isnan(x) != 0; }                                                    \
    static int mac_isnormal##suffix(type x) { return isnormal(x) != 0; }                                              \
    static int mac_signbit##suffix(type x) { return signbit(x) != 0; }
CLASSIFIERS(f, float)
CLASSIFIERS(d, double)
CLASSIFIERS(l, long double)

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

/* memset_s (freemac 1.230), C11's bounds-checked memset, which Swift's
 * concurrency runtime calls: the store is made through a volatile pointer,
 * so it isn't optimised away. It answers 0, or EINVAL when the destination
 * is missing, or ERANGE (filling what fits) when n is more than smax. */
static int mac_memset_s(void *s, size_t smax, int c, size_t n)
{
    if (!s)
        return EINVAL;
    int err = 0;
    if (n > smax) {
        n = smax;
        err = ERANGE;
    }
    volatile unsigned char *p = s;
    while (n--)
        *p++ = (unsigned char)c;
    return err;
}

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

/* ---- POSIX regular expressions (freemac 1.264, HandBrake's filter checks)
 * A Mac's regex_t is 32 bytes (re_magic, re_nsub, re_endp, re_g) and its
 * regmatch_t holds two 64-bit offsets; this system's regex_t is 64 bytes
 * and its offsets are 32-bit, so the host's regcomp wrote past the end of
 * a Mac program's regex_t. Ferry keeps the host's pattern on the heap,
 * pointed to by re_g, and translates the flags and the matches. */
struct mac_regex {
    int re_magic;
    size_t re_nsub;
    const char *re_endp;
    regex_t *re_g;
};
struct mac_regmatch {
    int64_t rm_so, rm_eo;
};
#define MAC_RE_MAGIC 0xf1e7c0de
enum { MAC_REG_EXTENDED = 1, MAC_REG_ICASE = 2, MAC_REG_NOSUB = 4, MAC_REG_NEWLINE = 8, MAC_REG_NOSPEC = 0x10,
       MAC_REG_PEND = 0x20 };
enum { MAC_REG_ESPACE = 12, MAC_REG_INVARG = 16 };

static int mac_regcomp(struct mac_regex *preg, const char *pattern, int cflags)
{
    if (!preg || !pattern)
        return MAC_REG_INVARG;
    int host = 0;
    if (cflags & MAC_REG_EXTENDED)
        host |= REG_EXTENDED;
    if (cflags & MAC_REG_ICASE)
        host |= REG_ICASE;
    if (cflags & MAC_REG_NOSUB)
        host |= REG_NOSUB;
    if (cflags & MAC_REG_NEWLINE)
        host |= REG_NEWLINE;
    /* REG_NOSPEC (the pattern is plain text) and REG_PEND (it ends at
     * re_endp) need a copy of the pattern: plain text gets its specials
     * escaped */
    char *copy = NULL;
    if (cflags & (MAC_REG_NOSPEC | MAC_REG_PEND)) {
        size_t n = (cflags & MAC_REG_PEND) && preg->re_endp >= pattern ? (size_t)(preg->re_endp - pattern)
                                                                       : strlen(pattern);
        copy = malloc(2 * n + 1);
        if (!copy)
            return MAC_REG_ESPACE;
        size_t o = 0;
        for (size_t i = 0; i < n; i++) {
            if ((cflags & MAC_REG_NOSPEC) && strchr("\\^$.[]|()?*+{}", pattern[i]))
                copy[o++] = '\\';
            copy[o++] = pattern[i];
        }
        copy[o] = 0;
        pattern = copy;
        if (cflags & MAC_REG_NOSPEC)
            host |= REG_EXTENDED;
    }
    regex_t *re = calloc(1, sizeof *re);
    if (!re) {
        free(copy);
        return MAC_REG_ESPACE;
    }
    int r = regcomp(re, pattern, host);
    free(copy);
    if (r) {
        free(re);
        return r; /* the same numbers as a Mac's, REG_NOMATCH to REG_BADRPT */
    }
    preg->re_magic = (int)MAC_RE_MAGIC;
    preg->re_nsub = re->re_nsub;
    preg->re_g = re;
    return 0;
}

static int mac_regexec(const struct mac_regex *preg, const char *string, size_t nmatch,
                       struct mac_regmatch *pmatch, int eflags)
{
    if (!preg || preg->re_magic != (int)MAC_RE_MAGIC || !preg->re_g)
        return MAC_REG_INVARG;
    regmatch_t local[16], *m = nmatch <= 16 ? local : malloc(nmatch * sizeof *m);
    if (!m)
        return MAC_REG_ESPACE;
    if ((eflags & REG_STARTEND) && pmatch) { /* the same flag values as a Mac's */
        m[0].rm_so = (regoff_t)pmatch[0].rm_so;
        m[0].rm_eo = (regoff_t)pmatch[0].rm_eo;
    }
    int r = regexec(preg->re_g, string, pmatch ? nmatch : 0, m, eflags & (REG_NOTBOL | REG_NOTEOL | REG_STARTEND));
    if (!r && pmatch)
        for (size_t i = 0; i < nmatch; i++) {
            pmatch[i].rm_so = m[i].rm_so;
            pmatch[i].rm_eo = m[i].rm_eo;
        }
    if (m != local)
        free(m);
    return r;
}

static void mac_regfree(struct mac_regex *preg)
{
    if (!preg || preg->re_magic != (int)MAC_RE_MAGIC || !preg->re_g)
        return;
    regfree(preg->re_g);
    free(preg->re_g);
    preg->re_g = NULL;
    preg->re_magic = 0;
}

static size_t mac_regerror(int code, const struct mac_regex *preg, char *buf, size_t size)
{
    const regex_t *re = preg && preg->re_magic == (int)MAC_RE_MAGIC ? preg->re_g : NULL;
    if (code == MAC_REG_INVARG) {
        const char *t = "invalid argument to regex routine";
        if (size) {
            snprintf(buf, size, "%s", t);
        }
        return strlen(t) + 1;
    }
    return regerror(code, re, buf, size);
}

/* The resolver state (libresolv's res_ninit and the name servers in it).
 * A Mac's struct __res_state is laid out unlike this system's, so Ferry
 * doesn't fill one in: res_ninit reports failure and a program falls back
 * to getaddrinfo, which reads this system's own resolver setup. */
static int mac_res_ninit(void *state) { (void)state; errno = ENOSYS; return -1; }
static void mac_res_ndestroy(void *state) { (void)state; }
static int mac_res_getservers(void *state, void *servers, int count) { (void)state; (void)servers; (void)count; return 0; }

/* the process that answers for another in privacy prompts: itself here */
static int mac_responsibility_get_pid_responsible_for_pid(int pid) { return pid; }

const struct ferry_symbol ferry_libc_more_symbols[] = {
    {"res_9_ninit", mac_res_ninit},
    {"res_9_ndestroy", mac_res_ndestroy},
    {"res_9_nclose", mac_res_ndestroy},
    {"res_9_getservers", mac_res_getservers},
    {"responsibility_get_pid_responsible_for_pid", mac_responsibility_get_pid_responsible_for_pid},
    {"malloc_good_size", mac_malloc_good_size},
    {"memset_pattern4", mac_memset_pattern4},
    {"memset_pattern8", mac_memset_pattern8},
    {"memset_pattern16", mac_memset_pattern16},
    {"memset_s", mac_memset_s},
    {"malloc_default_zone", mac_malloc_default_zone},
    {"malloc_get_all_zones", mac_malloc_get_all_zones},
    {"malloc_zone_register", mac_malloc_zone_register},
    {"malloc_zone_unregister", mac_malloc_zone_unregister},
    {"malloc_zone_statistics", mac_malloc_zone_statistics},
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
    {"getfsstat$INODE64", mac_getfsstat64},
    {"getfsstat64", mac_getfsstat64},
    {"regcomp", mac_regcomp},
    {"regexec", mac_regexec},
    {"regfree", mac_regfree},
    {"regerror", mac_regerror},
    {"__fpclassifyf", mac_fpclassifyf}, {"__fpclassifyd", mac_fpclassifyd}, {"__fpclassifyl", mac_fpclassifyl},
    {"__fpclassify", mac_fpclassifyd},   {"__isfinitef", mac_isfinitef},     {"__isfinited", mac_isfinited},
    {"__isfinitel", mac_isfinitel},     {"__isinff", mac_isinff},           {"__isinfd", mac_isinfd},
    {"__isinfl", mac_isinfl},           {"__isnanf", mac_isnanf},           {"__isnand", mac_isnand},
    {"__isnanl", mac_isnanl},           {"__isnormalf", mac_isnormalf},     {"__isnormald", mac_isnormald},
    {"__isnormall", mac_isnormall},     {"__signbitf", mac_signbitf},       {"__signbitd", mac_signbitd},
    {"__signbitl", mac_signbitl},
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
