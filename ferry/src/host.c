/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's own Mac frameworks for drawing (Core Graphics and Core Text, in
 * frameworks/) are Mac code that does its work with this system's Cairo,
 * Pango and HarfBuzz. They import those calls from a library name that only
 * exists inside Ferry, /usr/lib/ferry/libFerryHost.dylib; this file serves
 * it. The calls allowed are exactly the ones declared in
 * graphics/host.h (the list is generated from it at build time), and the
 * Linux libraries are opened only when a program first needs one, so
 * programs that don't draw never load them and Ferry itself doesn't link
 * against them.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#include "ferry.h"

const char *const ferry_host_names[] = {
#include "host_names.h"
    NULL,
};

static const char *const host_libraries[] = {
    "libcairo.so.2",     "libpangocairo-1.0.so.0", "libpango-1.0.so.0",
    "libgobject-2.0.so.0", "libglib-2.0.so.0",     "libharfbuzz.so.0",
};
#define NLIBS (sizeof host_libraries / sizeof host_libraries[0])

static void *handles[NLIBS];
static int opened;

static void open_libraries(void)
{
    opened = 1;
    for (size_t i = 0; i < NLIBS; i++) {
        handles[i] = dlopen(host_libraries[i], RTLD_NOW | RTLD_GLOBAL);
        if (!handles[i])
            fprintf(stderr, "ferry: drawing needs %s, which isn't installed (%s)\n", host_libraries[i], dlerror());
    }
}

void *ferry_host_lookup(const char *name)
{
    const char *const *p;
    for (p = ferry_host_names; *p; p++)
        if (!strcmp(*p, name))
            break;
    if (!*p)
        return NULL;
    if (!opened)
        open_libraries();
    for (size_t i = 0; i < NLIBS; i++) {
        void *addr = handles[i] ? dlsym(handles[i], name) : NULL;
        if (addr)
            return addr;
    }
    return NULL;
}
