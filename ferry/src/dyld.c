/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loading code while a Mac program runs: dlopen, dlsym, dlclose, dlerror and
 * dladdr, and the _dyld_ calls that list the loaded images. Written from
 * Apple's public documentation (the dlopen(3), dlsym(3), dladdr(3) and
 * dyld(3) man pages), not from Apple's code.
 *
 * A handle names one of the Mach-O images the loader keeps (src/loader.c)
 * or one of the libraries built into Ferry: libSystem and libobjc, whose
 * calls are Ferry's own tables, and the Linux twins (zlib, SQLite...). The
 * special handles search in the documented orders:
 *
 *   RTLD_DEFAULT    every image loaded globally: the program, then Ferry's
 *                   libSystem and libobjc, then the libraries in load order
 *   RTLD_NEXT       the images loaded after the caller's, then libSystem, then
 *                   the libraries the caller links (and theirs)
 *   RTLD_SELF       the caller's image, then as RTLD_NEXT
 *   RTLD_MAIN_ONLY  the program alone
 *
 * Symbols are named as C spells them; Mach-O's leading underscore is added
 * here. A name Ferry doesn't have is NULL, never one of the stubs that
 * stop the program. dlerror's message is kept per thread.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ferry.h"

/* The Mac's values (dlfcn.h on a Mac). */
#define MAC_RTLD_LAZY 0x1
#define MAC_RTLD_NOW 0x2
#define MAC_RTLD_LOCAL 0x4
#define MAC_RTLD_GLOBAL 0x8
#define MAC_RTLD_NOLOAD 0x10
#define MAC_RTLD_NODELETE 0x80
#define MAC_RTLD_FIRST 0x100
#define MAC_RTLD_NEXT ((void *)-1)
#define MAC_RTLD_DEFAULT ((void *)-2)
#define MAC_RTLD_SELF ((void *)-3)
#define MAC_RTLD_MAIN_ONLY ((void *)-5)

/* ---- dlerror ------------------------------------------------------------------ */

static __thread char error_text[1280];
static __thread int error_set;

__attribute__((format(printf, 1, 2))) static void set_error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(error_text, sizeof error_text, fmt, ap);
    va_end(ap);
    error_set = 1;
    /* With -v, say why a dlopen or dlsym failed: a program often only
     * reports that "it couldn't load" a library (freemac 1.266). */
    if (ferry_verbose)
        fprintf(stderr, "ferry: %s\n", error_text);
}

static char *mac_dlerror(void)
{
    if (!error_set)
        return NULL;
    error_set = 0;
    return error_text;
}

/* ---- handles ------------------------------------------------------------------- */

enum { H_IMAGE, H_LIBSYSTEM, H_TWIN };

struct handle {
    int kind;
    struct image *im;        /* H_IMAGE */
    const char *twin;        /* H_TWIN: the Mac library's install name */
    int first;               /* RTLD_FIRST: the image alone */
    int refs;
    struct handle *next;
};

static pthread_mutex_t lock;
static struct handle *handles;
static struct handle libsystem_handle = {H_LIBSYSTEM, NULL, NULL, 0, 1, NULL};

/* Images opened with RTLD_LOCAL (and never with RTLD_GLOBAL), which
 * RTLD_DEFAULT doesn't search. */
static struct image *local_images[512];
static int nlocal;

__attribute__((constructor)) static void make_lock(void)
{
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&lock, &a);
    pthread_mutexattr_destroy(&a);
}

static int is_local(struct image *im)
{
    for (int i = 0; i < nlocal; i++)
        if (local_images[i] == im)
            return 1;
    return 0;
}

static void set_global(struct image *im)
{
    for (int i = 0; i < nlocal; i++)
        if (local_images[i] == im) {
            local_images[i] = local_images[--nlocal];
            return;
        }
}

static struct handle *valid_handle(void *h)
{
    if (h == &libsystem_handle)
        return &libsystem_handle;
    for (struct handle *p = handles; p; p = p->next)
        if (p == h)
            return p;
    return NULL;
}

static struct handle *image_handle(struct image *im, int first)
{
    for (struct handle *p = handles; p; p = p->next)
        if (p->kind == H_IMAGE && p->im == im && p->first == first) {
            p->refs++;
            return p;
        }
    struct handle *p = calloc(1, sizeof *p);
    p->kind = H_IMAGE;
    p->im = im;
    p->first = first;
    p->refs = 1;
    p->next = handles;
    handles = p;
    return p;
}

static struct handle *twin_handle(const char *install_name)
{
    for (struct handle *p = handles; p; p = p->next)
        if (p->kind == H_TWIN && !strcmp(p->twin, install_name)) {
            p->refs++;
            return p;
        }
    struct handle *p = calloc(1, sizeof *p);
    p->kind = H_TWIN;
    p->twin = strdup(install_name);
    p->refs = 1;
    p->next = handles;
    handles = p;
    return p;
}

/* ---- finding the file ------------------------------------------------------------ */

static int is_file(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* Names a Mac answers with libSystem (its parts and the older names that
 * point at it) or libobjc. */
static int is_libsystem(const char *path)
{
    static const char *const names[] = {
        "/usr/lib/libSystem.B.dylib", "/usr/lib/libSystem.dylib", "/usr/lib/libc.dylib", "/usr/lib/libm.dylib",
        "/usr/lib/libdl.dylib", "/usr/lib/libpthread.dylib", "/usr/lib/libinfo.dylib", "/usr/lib/libdyld.dylib",
        "/usr/lib/libobjc.A.dylib", "/usr/lib/libobjc.dylib", "/usr/lib/libdispatch.dylib",
        /* GNU libiconv, served from Ferry's own calls (libc_vlc.c) */
        "/usr/lib/libiconv.2.dylib", "/usr/lib/libiconv.dylib", NULL,
    };
    if (!strncmp(path, "/usr/lib/system/", 16))
        return 1;
    for (int i = 0; names[i]; i++)
        if (!strcmp(path, names[i]) || (!strchr(path, '/') && !strcmp(path, strrchr(names[i], '/') + 1)))
            return 1;
    return 0;
}

/* A bare file name: $DYLD_LIBRARY_PATH, the current folder, then
 * $DYLD_FALLBACK_LIBRARY_PATH or its default, ~/lib and /usr/local/lib. */
static int search_leaf(const char *name, char *out, size_t size)
{
    const char *lists[2] = {getenv("DYLD_LIBRARY_PATH"), getenv("DYLD_FALLBACK_LIBRARY_PATH")};
    char fallback[PATH_MAX];
    if (!lists[1]) {
        const char *home = getenv("HOME");
        snprintf(fallback, sizeof fallback, "%s/lib:/usr/local/lib", home ? home : "");
        lists[1] = fallback;
    }
    for (int k = 0; k < 2; k++) {
        if (k == 1 && is_file(name)) {
            snprintf(out, size, "%s", name);
            return 1;
        }
        if (!lists[k])
            continue;
        char copy[4096];
        snprintf(copy, sizeof copy, "%s", lists[k]);
        for (char *save, *dir = strtok_r(copy, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) {
            snprintf(out, size, "%s/%s", dir, name);
            if (is_file(out))
                return 1;
        }
    }
    snprintf(out, size, "%s", name);
    return 0;
}

static struct image *already_loaded(const char *path)
{
    char want[PATH_MAX], have[PATH_MAX];
    if (!realpath(path, want))
        return NULL;
    for (int i = 0; i < ferry_image_count(); i++) {
        struct image *im = ferry_image_at(i);
        if (realpath(ferry_image_path(im), have) && !strcmp(want, have))
            return im;
    }
    return NULL;
}

static struct image *caller_image(const void *ret) { return ferry_image_containing(ret); }

typedef void (*add_image_fn)(const void *header, intptr_t slide);
static add_image_fn add_callbacks[32];
static int nadd_callbacks;
/* How many images, in load order, each callback has been told of. A
 * library's initializer can register one while its own dlopen is still
 * under way (USD does, freemac Blender work): the callback is told of that
 * library then, so it isn't told again when the dlopen ends, since a Mac
 * calls each callback once for each image. */
static int add_told[32];

static void tell_add_callbacks(void)
{
    int n = ferry_image_count();
    for (int c = 0; c < nadd_callbacks; c++)
        while (add_told[c] < n) {
            struct image *im = ferry_image_at(add_told[c]++);
            add_callbacks[c](ferry_image_header(im), ferry_image_slide(im));
        }
}

static void *open_path(const char *path, int mode, struct image *caller)
{
    char full[PATH_MAX];
    int noload = mode & MAC_RTLD_NOLOAD, first = (mode & MAC_RTLD_FIRST) != 0;
    if (is_libsystem(path))
        return &libsystem_handle;
    if (ferry_twin_library(path))
        return twin_handle(path);
    if (!strcmp(path, FERRY_HOST_LIBRARY)) {
        set_error("dlopen(%s, 0x%04X): tried: '%s' (no such file)", path, mode, path);
        return NULL;
    }
    int found;
    if (path[0] == '@')
        found = ferry_image_resolve(caller, path, full, sizeof full) && is_file(full);
    else if (ferry_find_system_framework(path, full, sizeof full))
        found = 1;
    else if (!strchr(path, '/')) {
        found = search_leaf(path, full, sizeof full);
        /* As dyld does, a bare name also goes through the caller's and the
         * app's run paths, as @rpath/name (OBS loads libobs-opengl.dylib so). */
        char rp[PATH_MAX], at[PATH_MAX];
        snprintf(at, sizeof at, "@rpath/%s", path);
        if (!found && caller && ferry_image_resolve(caller, at, rp, sizeof rp) && is_file(rp)) {
            snprintf(full, sizeof full, "%s", rp);
            found = 1;
        }
    }
    else {
        snprintf(full, sizeof full, "%s", path);
        found = is_file(full);
    }
    if (!found) {
        if ((!strncmp(path, "/System/Library/", 16) || !strncmp(path, "/usr/lib/", 9)) && strstr(path, ".framework/"))
            set_error("dlopen(%s, 0x%04X): tried: '%s' (no such file; Ferry doesn't provide this framework yet)",
                      path, mode, path);
        else
            set_error("dlopen(%s, 0x%04X): tried: '%s' (no such file)", path, mode, full);
        return NULL;
    }
    struct image *im = already_loaded(full);
    if (!im && noload) {
        set_error("dlopen(%s, 0x%04X): image not already loaded", path, mode);
        return NULL;
    }
    if (!im) {
        char why[1024];
        im = ferry_image_load(full, why, sizeof why);
        if (!im) {
            set_error("dlopen(%s, 0x%04X): %s", path, mode, why);
            return NULL;
        }
        if (mode & MAC_RTLD_LOCAL && !(mode & MAC_RTLD_GLOBAL) && nlocal < (int)(sizeof local_images / sizeof *local_images))
            local_images[nlocal++] = im;
        tell_add_callbacks();
    } else if (mode & MAC_RTLD_GLOBAL)
        set_global(im);
    return image_handle(im, first);
}

static void *mac_dlopen(const char *path, int mode)
{
    if (!path) {
        pthread_mutex_lock(&lock);
        void *h = image_handle(ferry_main_image(), 0);
        pthread_mutex_unlock(&lock);
        return h;
    }
    struct image *caller = caller_image(__builtin_return_address(0));
    pthread_mutex_lock(&lock);
    void *h = open_path(path, mode, caller);
    pthread_mutex_unlock(&lock);
    return h;
}

/* dlopen_preflight: whether dlopen would load it, without loading it. */
static int mac_dlopen_preflight(const char *path)
{
    if (!path)
        return 0;
    char full[PATH_MAX];
    struct image *caller = caller_image(__builtin_return_address(0));
    if (is_libsystem(path) || ferry_twin_library(path))
        return 1;
    if (path[0] == '@')
        return ferry_image_resolve(caller, path, full, sizeof full) && is_file(full);
    if (ferry_find_system_framework(path, full, sizeof full))
        return 1;
    if (!strchr(path, '/'))
        return search_leaf(path, full, sizeof full);
    return is_file(path);
}

/* _dyld_shared_cache_contains_path (macOS 11): whether a system library is
 * in the shared cache, which on a Mac is where system libraries live instead
 * of on disk. Ferry has no shared cache; the system libraries and
 * frameworks it serves stand in for it (freemac 1.NEXT), so that a program
 * that looks for, say, Foundation by path finds it: Python's ctypes does,
 * through this call, which it calls without checking for NULL. */
static bool mac_dyld_shared_cache_contains_path(const char *path)
{
    if (!path || (strncmp(path, "/System/Library/", 16) && strncmp(path, "/usr/lib/", 9)))
        return false;
    char full[PATH_MAX];
    return is_libsystem(path) || ferry_twin_library(path) || ferry_find_system_framework(path, full, sizeof full);
}

/* _dyld_get_shared_cache_range: no shared cache. */
static const void *mac_dyld_get_shared_cache_range(size_t *length)
{
    if (length)
        *length = 0;
    return NULL;
}

static int mac_dlclose(void *h)
{
    pthread_mutex_lock(&lock);
    struct handle *p = valid_handle(h);
    int rc = 0;
    if (!p || (p->kind != H_LIBSYSTEM && p->refs <= 0)) {
        set_error("dlclose(%p): invalid handle", h);
        rc = -1;
    } else if (p->kind != H_LIBSYSTEM)
        p->refs--; /* the image itself stays, as Objective-C code always does on a Mac */
    pthread_mutex_unlock(&lock);
    return rc;
}

/* ---- dlsym ----------------------------------------------------------------------- */

static void *in_image(struct image *im, const char *name)
{
    char raw[512];
    snprintf(raw, sizeof raw, "_%s", name);
    return ferry_image_symbol(im, raw);
}

/* An image and the libraries it links, breadth first, each once. */
static void *in_image_tree(struct image *top, const char *name, int first)
{
    struct image *queue[512];
    int n = 0, builtin = 0;
    queue[n++] = top;
    for (int i = 0; i < n; i++) {
        void *addr = in_image(queue[i], name);
        if (addr)
            return addr;
        if (first)
            break;
        struct image *deps[64];
        int b, nd = ferry_image_dependencies(queue[i], deps, 64, &b);
        builtin |= b;
        for (int d = 0; d < nd; d++) {
            int seen = 0;
            for (int k = 0; k < n && !seen; k++)
                seen = queue[k] == deps[d];
            if (!seen && n < (int)(sizeof queue / sizeof *queue))
                queue[n++] = deps[d];
        }
    }
    return builtin ? ferry_lookup_libsystem(name) : NULL;
}

/* The images from the one at "from" on, then libSystem. */
static void *from_image_on(int from, const char *name)
{
    for (int i = from; i < ferry_image_count(); i++) {
        void *addr = in_image(ferry_image_at(i), name);
        if (addr)
            return addr;
    }
    return ferry_lookup_libsystem(name);
}

static int image_index(struct image *im)
{
    for (int i = 0; i < ferry_image_count(); i++)
        if (ferry_image_at(i) == im)
            return i;
    return -1;
}

static void *mac_dlsym(void *h, const char *name)
{
    if (!name) {
        set_error("dlsym(%p, NULL): symbol name is NULL", h);
        return NULL;
    }
    void *addr = NULL;
    const char *which = NULL;
    if (h == MAC_RTLD_DEFAULT) {
        which = "RTLD_DEFAULT";
        struct image *main = ferry_main_image();
        if (main)
            addr = in_image(main, name);
        if (!addr)
            addr = ferry_lookup_libsystem(name);
        for (int i = 0; !addr && i < ferry_image_count(); i++) {
            struct image *im = ferry_image_at(i);
            if (im != main && !is_local(im))
                addr = in_image(im, name);
        }
    } else if (h == MAC_RTLD_MAIN_ONLY) {
        which = "RTLD_MAIN_ONLY";
        addr = ferry_main_image() ? in_image(ferry_main_image(), name) : NULL;
    } else if (h == MAC_RTLD_NEXT || h == MAC_RTLD_SELF) {
        which = h == MAC_RTLD_NEXT ? "RTLD_NEXT" : "RTLD_SELF";
        struct image *self = caller_image(__builtin_return_address(0));
        int at = image_index(self);
        addr = from_image_on(at < 0 ? 0 : h == MAC_RTLD_NEXT ? at + 1 : at, name);
        /* dyld also looks in the libraries the caller links, and theirs,
         * whenever they were loaded: Qt's Mac plugin, loaded last, finds
         * OpenGL's calls with RTLD_NEXT through QtGui although OpenGL came
         * in before it (freemac 1.267). */
        if (!addr && self) {
            struct image *deps[64];
            int b, nd = ferry_image_dependencies(self, deps, 64, &b);
            for (int d = 0; !addr && d < nd; d++)
                addr = in_image_tree(deps[d], name, 0);
        }
    } else {
        struct handle *p = valid_handle(h);
        if (!p) {
            set_error("dlsym(%p, %s): invalid handle", h, name);
            return NULL;
        }
        if (p->kind == H_LIBSYSTEM)
            addr = ferry_lookup_libsystem(name);
        else if (p->kind == H_TWIN)
            addr = ferry_twin_symbol(p->twin, name);
        else
            addr = in_image_tree(p->im, name, p->first);
    }
    if (!addr) {
        if (which)
            set_error("dlsym(%s, %s): symbol not found", which, name);
        else
            set_error("dlsym(%p, %s): symbol not found", h, name);
    }
    return addr;
}

/* ---- dladdr ---------------------------------------------------------------------- */

struct mac_dl_info {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
};

/* The image holding an address and the nearest symbol at or below it. An
 * address of Ferry's own libSystem (or a call it passes to this system's
 * C library) reports /usr/lib/libSystem.B.dylib, with the name the program
 * imports it by when the address is one Ferry serves. */
static int mac_dladdr(const void *addr, struct mac_dl_info *info)
{
    memset(info, 0, sizeof *info);
    struct image *im = ferry_image_containing(addr);
    if (im) {
        void *saddr;
        info->dli_fname = ferry_image_path(im);
        info->dli_fbase = ferry_image_header(im);
        info->dli_sname = ferry_image_nearest(im, addr, &saddr);
        info->dli_saddr = info->dli_sname ? saddr : NULL;
        return 1;
    }
    Dl_info host;
    if (!dladdr(addr, &host))
        return 0;
    info->dli_fname = "/usr/lib/libSystem.B.dylib";
    info->dli_fbase = host.dli_fbase;
    const char *own = ferry_symbol_name(addr);
    if (own) {
        info->dli_sname = own;
        info->dli_saddr = (void *)addr;
    } else if (host.dli_sname && ferry_lookup_libsystem(host.dli_sname) == host.dli_saddr) {
        info->dli_sname = host.dli_sname;
        info->dli_saddr = host.dli_saddr;
    }
    return 1;
}

/* ---- the _dyld_ calls (mach-o/dyld.h) -------------------------------------------- */

static uint32_t mac_dyld_image_count(void) { return (uint32_t)ferry_image_count(); }
static const void *mac_dyld_get_image_header(uint32_t i) { return ferry_image_header(ferry_image_at((int)i)); }
static intptr_t mac_dyld_get_image_vmaddr_slide(uint32_t i) { return ferry_image_slide(ferry_image_at((int)i)); }
static const char *mac_dyld_get_image_name(uint32_t i) { return ferry_image_path(ferry_image_at((int)i)); }

/* Called at once for every image already loaded, then for each one dlopen
 * adds. Images are never removed, so the removal callbacks never run. */
/* Whether an address is one of dyld's shared-cache Objective-C constants
 * (freemac 1.227): Ferry has no shared cache, so never. */
static int mac_dyld_is_objc_constant(int kind, const void *addr) { return 0; }

static void mac_dyld_register_func_for_add_image(add_image_fn fn)
{
    if (!fn)
        return;
    pthread_mutex_lock(&lock);
    if (nadd_callbacks < (int)(sizeof add_callbacks / sizeof *add_callbacks)) {
        add_told[nadd_callbacks] = 0;
        add_callbacks[nadd_callbacks++] = fn;
        tell_add_callbacks();
    } else
        fprintf(stderr, "ferry: the program registered too many image callbacks; one is left out\n");
    pthread_mutex_unlock(&lock);
}

static void mac_dyld_register_func_for_remove_image(add_image_fn fn) { (void)fn; }

/* ---- sections of a loaded image (mach-o/getsect.h) ------------------------------
 * From the getsectiondata(3) man page: a section's or segment's address in
 * memory, found by walking the image's load commands, which the loader
 * maps with the image (freemac 1.227: Swift's runtime finds its metadata
 * sections this way). */

struct mac_seg64 { uint32_t cmd, cmdsize; char segname[16]; uint64_t vmaddr, vmsize, fileoff, filesize;
                   int32_t maxprot, initprot; uint32_t nsects, flags; };
struct mac_sect64 { char sectname[16], segname[16]; uint64_t addr, size;
                    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3; };
#define MAC_LC_SEGMENT_64 0x19

/* The image's 64-bit segments in order, and its slide (where __TEXT was
 * mapped, less the address it asks for). */
static int mac_segments(const void *mh, const struct mac_seg64 **segs, int max, intptr_t *slide)
{
    const uint32_t *h = mh;
    *slide = 0;
    if (!h || h[0] != 0xfeedfacfu)
        return 0;
    const char *p = (const char *)mh + 32;
    int n = 0;
    for (uint32_t i = 0; i < h[4]; i++) {
        const struct mac_seg64 *seg = (const void *)p;
        if (seg->cmd == MAC_LC_SEGMENT_64) {
            if (!strncmp(seg->segname, "__TEXT", 16))
                *slide = (intptr_t)mh - (intptr_t)seg->vmaddr;
            if (n < max)
                segs[n++] = seg;
        }
        p += seg->cmdsize;
    }
    return n;
}

static uint8_t *mac_getsegmentdata(const void *mh, const char *segname, unsigned long *size)
{
    const struct mac_seg64 *segs[64];
    intptr_t slide;
    int n = mac_segments(mh, segs, 64, &slide);
    for (int i = 0; i < n; i++)
        if (!strncmp(segs[i]->segname, segname, 16)) {
            if (size)
                *size = (unsigned long)segs[i]->vmsize;
            return (uint8_t *)(uintptr_t)(segs[i]->vmaddr + (uint64_t)slide);
        }
    return NULL;
}

static const struct mac_sect64 *mac_find_section(const void *mh, const char *segname, const char *sectname,
                                                 intptr_t *slide)
{
    const struct mac_seg64 *segs[64];
    int n = mac_segments(mh, segs, 64, slide);
    for (int i = 0; i < n; i++) {
        if (strncmp(segs[i]->segname, segname, 16))
            continue;
        const struct mac_sect64 *sect = (const void *)(segs[i] + 1);
        for (uint32_t k = 0; k < segs[i]->nsects; k++)
            if (!strncmp(sect[k].sectname, sectname, 16))
                return &sect[k];
    }
    return NULL;
}

static uint8_t *mac_getsectiondata(const void *mh, const char *segname, const char *sectname, unsigned long *size)
{
    intptr_t slide;
    const struct mac_sect64 *sect = mac_find_section(mh, segname, sectname, &slide);
    if (!sect)
        return NULL;
    if (size)
        *size = (unsigned long)sect->size;
    return (uint8_t *)(uintptr_t)(sect->addr + (uint64_t)slide);
}

/* The main program's section, at its address in the file (unslid), as
 * getsectdata's man page says. */
static char *mac_getsectdata(const char *segname, const char *sectname, unsigned long *size)
{
    intptr_t slide;
    const struct mac_sect64 *sect = mac_find_section(mac_dyld_get_image_header(0), segname, sectname, &slide);
    if (!sect)
        return NULL;
    if (size)
        *size = (unsigned long)sect->size;
    return (char *)(uintptr_t)sect->addr;
}

/* The section's own record, with its unslid address, as the man page says. */
static const void *mac_getsectbynamefromheader_64(const void *mh, const char *segname, const char *sectname)
{
    intptr_t slide;
    return mac_find_section(mh, segname, sectname, &slide);
}

/* The main program's segment of that name, as its unslid load command
 * (freemac Godot work). */
static const void *mac_getsegbyname(const char *segname)
{
    const struct mac_seg64 *segs[64];
    intptr_t slide;
    int n = mac_segments(mac_dyld_get_image_header(0), segs, 64, &slide);
    for (int i = 0; i < n; i++)
        if (!strncmp(segs[i]->segname, segname, 16))
            return segs[i];
    return NULL;
}

/* The main program's section of that name, as its unslid record. */
static const void *mac_getsectbyname(const char *segname, const char *sectname)
{
    return mac_getsectbynamefromheader_64(mac_dyld_get_image_header(0), segname, sectname);
}

/* Ferry's own, for Foundation's NSBundle: the first class a loaded bundle
 * defines (its principal class when Info.plist names none). */
static void *ferry_dl_first_class(void *h)
{
    struct handle *p = valid_handle(h);
    return p && p->kind == H_IMAGE ? ferry_image_first_class(p->im) : NULL;
}

/* The old NSModule calls (dyld(3), deprecated but still in macOS): a
 * symbol by its linker name, with C's leading underscore, looked up as
 * dlsym(RTLD_DEFAULT) would. An NSSymbol is here the symbol's address
 * (kitty's GLFW finds its OpenGL calls so). */
static const char *c_name(const char *linker_name)
{
    return linker_name && linker_name[0] == '_' ? linker_name + 1 : linker_name;
}
static int mac_NSIsSymbolNameDefined(const char *name)
{
    return mac_dlsym(MAC_RTLD_DEFAULT, c_name(name)) != NULL;
}
static int mac_NSIsSymbolNameDefinedWithHint(const char *name, const char *hint)
{
    (void)hint;
    return mac_NSIsSymbolNameDefined(name);
}
static void *mac_NSLookupAndBindSymbol(const char *name)
{
    return mac_dlsym(MAC_RTLD_DEFAULT, c_name(name));
}
static void *mac_NSLookupAndBindSymbolWithHint(const char *name, const char *hint)
{
    (void)hint;
    return mac_NSLookupAndBindSymbol(name);
}
static void *mac_NSLookupSymbolInImage(const void *image, const char *name, unsigned options)
{
    (void)image;
    (void)options;
    return mac_NSLookupAndBindSymbol(name);
}
static void *mac_NSAddressOfSymbol(void *symbol)
{
    return symbol;
}
/* An NSModule is the address of one of its symbols: its names are dladdr's */
static void *mac_NSModuleForSymbol(void *symbol)
{
    return symbol;
}
static const char *mac_NSNameOfModule(void *module)
{
    struct mac_dl_info info;
    return module && mac_dladdr(module, &info) ? info.dli_fname : NULL;
}
static const char *mac_NSLibraryNameForModule(void *module)
{
    return mac_NSNameOfModule(module);
}
static const char *mac_NSNameOfSymbol(void *symbol)
{
    static __thread char name[512];
    struct mac_dl_info info;
    if (!symbol || !mac_dladdr(symbol, &info) || !info.dli_sname)
        return NULL;
    snprintf(name, sizeof name, "_%s", info.dli_sname);
    return name;
}

const struct ferry_symbol ferry_dyld_symbols[] = {
    {"NSIsSymbolNameDefined", mac_NSIsSymbolNameDefined},
    {"NSIsSymbolNameDefinedWithHint", mac_NSIsSymbolNameDefinedWithHint},
    {"NSLookupAndBindSymbol", mac_NSLookupAndBindSymbol},
    {"NSLookupAndBindSymbolWithHint", mac_NSLookupAndBindSymbolWithHint},
    {"NSLookupSymbolInImage", mac_NSLookupSymbolInImage},
    {"NSAddressOfSymbol", mac_NSAddressOfSymbol},
    {"NSModuleForSymbol", mac_NSModuleForSymbol},
    {"NSNameOfModule", mac_NSNameOfModule},
    {"NSLibraryNameForModule", mac_NSLibraryNameForModule},
    {"NSNameOfSymbol", mac_NSNameOfSymbol},
    {"dlopen", mac_dlopen},
    {"dlopen_preflight", mac_dlopen_preflight},
    {"dlsym", mac_dlsym},
    {"dlclose", mac_dlclose},
    {"dlerror", mac_dlerror},
    {"dladdr", mac_dladdr},
    {"_dyld_image_count", mac_dyld_image_count},
    {"_dyld_get_image_header", mac_dyld_get_image_header},
    {"_dyld_get_image_vmaddr_slide", mac_dyld_get_image_vmaddr_slide},
    {"_dyld_get_image_name", mac_dyld_get_image_name},
    {"_dyld_register_func_for_add_image", mac_dyld_register_func_for_add_image},
    {"_dyld_is_objc_constant", mac_dyld_is_objc_constant},
    {"_dyld_shared_cache_contains_path", mac_dyld_shared_cache_contains_path},
    {"_dyld_get_shared_cache_range", mac_dyld_get_shared_cache_range},
    {"_dyld_register_func_for_remove_image", mac_dyld_register_func_for_remove_image},
    {"getsectiondata", mac_getsectiondata},
    {"getsectdata", mac_getsectdata},
    {"getsegmentdata", mac_getsegmentdata},
    {"getsectbynamefromheader_64", mac_getsectbynamefromheader_64},
    {"getsegbyname", mac_getsegbyname},
    {"getsectbyname", mac_getsectbyname},
    {"ferry_dl_first_class", ferry_dl_first_class},
    {NULL, NULL},
};
