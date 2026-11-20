/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's own Mac frameworks for drawing and windows (Core Graphics, Core
 * Text and AppKit, in frameworks/) are Mac code that does its work with
 * this system's Cairo, Pango, HarfBuzz and GTK. They import those calls from
 * a library name that only exists inside Ferry, /usr/lib/ferry/libFerryHost.dylib; this file serves
 * it. The calls allowed are exactly the ones declared in graphics/host.h
 * and appkit/gtk.h (the list is generated from them at build time), and the
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

/* Two groups: the drawing libraries Core Graphics and Core Text use, and
 * GTK, which AppKit uses for windows. Each is opened the first time one of
 * its calls is looked up. */
struct group {
    const char *what;
    const char *const *libraries;
    size_t count;
    void *handles[8];
    int opened;
};
static const char *const drawing_libraries[] = {
    "libcairo.so.2",     "libpangocairo-1.0.so.0", "libpango-1.0.so.0",
    "libgobject-2.0.so.0", "libglib-2.0.so.0",     "libharfbuzz.so.0",
};
static const char *const window_libraries[] = {"libgtk-3.so.0", "libgdk-3.so.0"};
static struct group drawing = {"drawing", drawing_libraries, 6, {0}, 0};
static struct group windows = {"windows", window_libraries, 2, {0}, 0};

static void open_group(struct group *g)
{
    g->opened = 1;
    for (size_t i = 0; i < g->count; i++) {
        g->handles[i] = dlopen(g->libraries[i], RTLD_NOW | RTLD_GLOBAL);
        if (!g->handles[i])
            fprintf(stderr, "ferry: %s needs %s, which isn't installed (%s)\n", g->what, g->libraries[i],
                    dlerror());
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
    struct group *g = !strncmp(name, "gtk_", 4) || !strncmp(name, "gdk_", 4) ? &windows : &drawing;
    if (!g->opened)
        open_group(g);
    for (size_t i = 0; i < g->count; i++) {
        void *addr = g->handles[i] ? dlsym(g->handles[i], name) : NULL;
        if (addr)
            return addr;
    }
    return NULL;
}
