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

/* Five groups: the drawing libraries Core Graphics and Core Text use, GTK,
 * which AppKit uses for windows, GdkPixbuf and Poppler, which read image
 * and PDF files, and GIO, whose D-Bus calls put menu bar items in the
 * desktop's menu bar and whose content types name the icon for a kind of
 * file. Each is opened the first time one of its calls is looked up. */
struct group {
    const char *what;
    const char *const *libraries;
    size_t count;
    void *handles[8];
    int opened;
    int optional; /* quiet if missing: only a call into it stops the program */
};
static const char *const drawing_libraries[] = {
    "libcairo.so.2",     "libpangocairo-1.0.so.0", "libpango-1.0.so.0",
    "libgobject-2.0.so.0", "libglib-2.0.so.0",     "libharfbuzz.so.0",
};
static const char *const window_libraries[] = {"libgtk-3.so.0", "libgdk-3.so.0"};
static const char *const image_libraries[] = {"libgdk_pixbuf-2.0.so.0"};
static const char *const pdf_libraries[] = {"libpoppler-glib.so.8"};
static const char *const gio_libraries[] = {"libgio-2.0.so.0"};
static struct group drawing = {"drawing", drawing_libraries, 6, {0}, 0, 0};
static struct group windows = {"windows", window_libraries, 2, {0}, 0, 0};
static struct group images = {"reading image files", image_libraries, 1, {0}, 0, 1};
static struct group pdf = {"reading PDF files", pdf_libraries, 1, {0}, 0, 1};
static struct group gio = {"menu bar items and file icons", gio_libraries, 1, {0}, 0, 1};

static void open_group(struct group *g)
{
    g->opened = 1;
    for (size_t i = 0; i < g->count; i++) {
        g->handles[i] = dlopen(g->libraries[i], RTLD_NOW | RTLD_GLOBAL);
        if (!g->handles[i] && !g->optional)
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
    struct group *g = !strncmp(name, "gdk_pixbuf_", 11)                  ? &images
                      : !strncmp(name, "poppler_", 8)                   ? &pdf
                      : !strncmp(name, "g_bus_", 6) || !strncmp(name, "g_dbus_", 7) ||
                              !strncmp(name, "g_content_type_", 15) || !strncmp(name, "g_themed_icon_", 14)
                          ? &gio
                      : !strncmp(name, "gtk_", 4) || !strncmp(name, "gdk_", 4) ? &windows
                                                                         : &drawing;
    if (!g->opened)
        open_group(g);
    for (size_t i = 0; i < g->count; i++) {
        void *addr = g->handles[i] ? dlsym(g->handles[i], name) : NULL;
        if (addr)
            return addr;
    }
    return NULL;
}

/* ---- libraries with Linux twins ------------------------------------------------
 * A few of the libraries in a Mac's /usr/lib are the same open-source
 * libraries Linux has, with the same calls and the same data layouts on
 * 64-bit Intel: zlib, bzip2, xz (liblzma), libxml2, SQLite and ICU. A program
 * that links one gets this system's copy. Calls that take a C library FILE
 * (whose layout differs between the two systems) are left out, so they stop
 * the program with their name instead. Each twin is opened only when a
 * program links it. */
static const struct twin {
    const char *mac, *linux_name;
} twins[] = {
    {"/usr/lib/libz.1.dylib", "libz.so.1"},
    {"/usr/lib/libz.dylib", "libz.so.1"},
    {"/usr/lib/libbz2.1.0.dylib", "libbz2.so.1.0"},
    {"/usr/lib/libbz2.dylib", "libbz2.so.1.0"},
    {"/usr/lib/liblzma.5.dylib", "liblzma.so.5"},
    {"/usr/lib/libxml2.2.dylib", "libxml2.so.2"},
    {"/usr/lib/libxml2.dylib", "libxml2.so.2"},
    {"/usr/lib/libsqlite3.dylib", "libsqlite3.so.0"},
    {"/usr/lib/libsqlite3.0.dylib", "libsqlite3.so.0"},
    /* ICU's C calls (regular expressions, collation, breaking), which
     * Linux builds name with the version, as uregex_open_74 */
    {"/usr/lib/libicucore.A.dylib", "icu"},
    {NULL, NULL},
};
static char icu_suffix[8];

/* This system's ICU, whichever version it has. */
static void *open_icu(void)
{
    for (int v = 99; v >= 50; v--) {
        char name[32];
        snprintf(name, sizeof name, "libicui18n.so.%d", v);
        void *h = dlopen(name, RTLD_NOW | RTLD_LOCAL);
        if (h) {
            snprintf(icu_suffix, sizeof icu_suffix, "_%d", v);
            return h;
        }
    }
    return NULL;
}
static void *twin_handles[16];
static int twin_linked[16];

static const char *const takes_a_file[] = {
    "BZ2_bzReadOpen", "BZ2_bzWriteOpen", "xmlDocDump", "xmlDocFormatDump", "xmlElemDump", "xmlBufferDump",
    "htmlDocDump", "xmlParserInputBufferCreateFile", "xmlOutputBufferCreateFile", "xmlCatalogDump",
    "xmlACatalogDump", "xmlLsOneNode", "xmlShell", "xmlPrintURI", "xmlMemDisplay", "xmlMemShow",
    "xmlDebugDumpString", "xmlDebugDumpAttr", "xmlDebugDumpAttrList", "xmlDebugDumpOneNode", "xmlDebugDumpNode",
    "xmlDebugDumpNodeList", "xmlDebugDumpDocumentHead", "xmlDebugDumpDocument", "xmlDebugDumpDTD",
    "xmlDebugDumpEntities", "xmlDebugCheckDocument", "xmlRegexpPrint", "xmlNanoHTTPSave", NULL,
};

int ferry_twin_library(const char *install_name)
{
    for (int i = 0; twins[i].mac; i++)
        if (!strcmp(install_name, twins[i].mac)) {
            if (!twin_linked[i]) {
                twin_linked[i] = 1;
                int icu = !strcmp(twins[i].linux_name, "icu");
                twin_handles[i] = icu ? open_icu() : dlopen(twins[i].linux_name, RTLD_NOW | RTLD_LOCAL);
                if (!twin_handles[i])
                    fprintf(stderr, "ferry: this program uses %s, but %s isn't installed\n",
                            strrchr(twins[i].mac, '/') + 1, icu ? "ICU (libicu)" : twins[i].linux_name);
            }
            return 1;
        }
    return 0;
}

void *ferry_twin_lookup(const char *name)
{
    for (int i = 0; takes_a_file[i]; i++)
        if (!strcmp(name, takes_a_file[i]))
            return NULL;
    for (int i = 0; twins[i].mac; i++) {
        if (!twin_handles[i])
            continue;
        void *addr;
        if (!strcmp(twins[i].linux_name, "icu")) {
            char versioned[256];
            snprintf(versioned, sizeof versioned, "%s%s", name, icu_suffix);
            addr = dlsym(twin_handles[i], versioned);
        } else
            addr = dlsym(twin_handles[i], name);
        if (addr)
            return addr;
    }
    return NULL;
}
