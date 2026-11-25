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
 */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <malloc.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/xattr.h>

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

const struct ferry_symbol ferry_libc_more_symbols[] = {
    {"malloc_good_size", mac_malloc_good_size},
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
    {NULL, NULL},
};
