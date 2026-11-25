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
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
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

/* bzip2's two calls that take a FILE, given this system's FILE behind the
 * program's (freemac 1.226, Ferry 0.50.0; Sequel Pro's .bz2 imports and
 * exports). The rest of the FILE calls above still stop the program. */
static void *bz2_call(const char *name)
{
    for (int i = 0; twins[i].mac; i++)
        if (!strcmp(twins[i].linux_name, "libbz2.so.1.0") && twin_handles[i])
            return dlsym(twin_handles[i], name);
    return NULL;
}
static void *twin_bzReadOpen(int *err, void *file, int verbosity, int small, void *unused, int n_unused)
{
    void *(*f)(int *, void *, int, int, void *, int) = bz2_call("BZ2_bzReadOpen");
    if (!f) {
        if (err) *err = -6; /* BZ_IO_ERROR */
        return NULL;
    }
    return f(err, ferry_host_file(file), verbosity, small, unused, n_unused);
}
static void *twin_bzWriteOpen(int *err, void *file, int block_size, int verbosity, int work_factor)
{
    void *(*f)(int *, void *, int, int, int) = bz2_call("BZ2_bzWriteOpen");
    if (!f) {
        if (err) *err = -6;
        return NULL;
    }
    return f(err, ferry_host_file(file), block_size, verbosity, work_factor);
}

void *ferry_twin_lookup(const char *name)
{
    if (!strcmp(name, "BZ2_bzReadOpen"))
        return bz2_call(name) ? (void *)twin_bzReadOpen : NULL;
    if (!strcmp(name, "BZ2_bzWriteOpen"))
        return bz2_call(name) ? (void *)twin_bzWriteOpen : NULL;
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

/* For Ferry's own Foundation: one call of a twin library, looked up only when
 * Foundation first needs it, so that a program which never makes a regular
 * expression or parses XML doesn't load ICU or libxml2 (and doesn't stop if
 * they aren't installed). Only the twins above are reachable this way, under
 * their Mac install names, and not the calls that take a FILE; NULL when the
 * library or the call isn't there. */
void *ferry_twin_symbol(const char *install_name, const char *name)
{
    if (!install_name || !name || !ferry_twin_library(install_name))
        return NULL;
    for (int i = 0; takes_a_file[i]; i++)
        if (!strcmp(name, takes_a_file[i]))
            return NULL;
    for (int i = 0; twins[i].mac; i++)
        if (!strcmp(install_name, twins[i].mac)) {
            if (!twin_handles[i])
                return NULL;
            if (!strcmp(twins[i].linux_name, "icu")) {
                char versioned[256];
                snprintf(versioned, sizeof versioned, "%s%s", name, icu_suffix);
                return dlsym(twin_handles[i], versioned);
            }
            return dlsym(twin_handles[i], name);
        }
    return NULL;
}

/* ---- networking ------------------------------------------------------------------
 * Foundation's URL loading (NSURLSession, NSURLConnection, and reading http
 * and https URLs into NSData and NSString) is done by this system's libcurl.
 * Foundation asks for libcurl's calls by name the first time a program
 * loads a URL from the network, so programs that never do don't open
 * libcurl (or the TLS library it brings). Only libcurl's own calls are
 * served. */
static const char *const network_libraries[] = {"libcurl.so.4", "libcurl-gnutls.so.4"};

/* Each library is opened once, whichever of the program's threads asks first. */
static void *network_handle;
static void open_network(void)
{
    for (size_t i = 0; i < sizeof network_libraries / sizeof network_libraries[0] && !network_handle; i++)
        network_handle = dlopen(network_libraries[i], RTLD_NOW | RTLD_LOCAL);
}

void *ferry_network_symbol(const char *name)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    if (!name || strncmp(name, "curl_", 5))
        return NULL;
    pthread_once(&once, open_network);
    return network_handle ? dlsym(network_handle, name) : NULL;
}

/* ---- cryptography ----------------------------------------------------------------
 * CommonCrypto's encryption (src/commoncrypto.c) and the Security
 * framework's certificates and trust are done by this system's OpenSSL:
 * libcrypto, and libssl to fetch a server's certificates. Each is opened
 * the first time one of its calls is looked up, so programs that never
 * encrypt or look at a certificate don't load them, and Ferry still starts
 * on a system without them. Only OpenSSL's own calls are served. */
static const char *const crypto_libraries[] = {"libcrypto.so.3", "libcrypto.so.1.1"};
static const char *const ssl_libraries[] = {"libssl.so.3", "libssl.so.1.1"};
static const char *const crypto_prefixes[] = {"EVP_", "X509", "d2i_", "i2d_", "PEM_", "BIO_", "OPENSSL_",
                                              "ERR_", "ASN1_", "OBJ_", "CRYPTO_", NULL};
static const char *const ssl_prefixes[] = {"SSL_", "TLS_", NULL};

static int has_prefix(const char *name, const char *const *prefixes)
{
    for (; *prefixes; prefixes++)
        if (!strncmp(name, *prefixes, strlen(*prefixes)))
            return 1;
    return 0;
}

static void *open_first(const char *const *names, size_t count)
{
    void *h = NULL;
    for (size_t i = 0; i < count && !h; i++)
        h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    return h;
}

static void *crypto_handle, *ssl_handle;
static void open_crypto(void)
{
    crypto_handle = open_first(crypto_libraries, sizeof crypto_libraries / sizeof crypto_libraries[0]);
}
static void open_ssl(void) { ssl_handle = open_first(ssl_libraries, sizeof ssl_libraries / sizeof ssl_libraries[0]); }

void *ferry_crypto_symbol(const char *name)
{
    static pthread_once_t crypto_once = PTHREAD_ONCE_INIT, ssl_once = PTHREAD_ONCE_INIT;
    if (!name)
        return NULL;
    if (has_prefix(name, crypto_prefixes)) {
        pthread_once(&crypto_once, open_crypto);
        return crypto_handle ? dlsym(crypto_handle, name) : NULL;
    }
    if (has_prefix(name, ssl_prefixes)) {
        pthread_once(&ssl_once, open_ssl);
        return ssl_handle ? dlsym(ssl_handle, name) : NULL;
    }
    return NULL;
}

/* ---- the session bus ---------------------------------------------------------------
 * Foundation's distributed notifications
 * (foundation/NSDistributedNotificationCenter.m) travel on the D-Bus
 * session bus through this system's GIO, opened the first time one of its
 * calls is looked up, so a program that never uses them doesn't load it.
 * Only GIO's and GLib's bus, variant, main-context and error calls are
 * served. */
static const char *const bus_libraries[] = {"libgio-2.0.so.0"};
static const char *const bus_prefixes[] = {"g_bus_", "g_dbus_", "g_variant_", "g_main_context_", "g_error_free",
                                           NULL};

static void *bus_handle;
static void open_bus(void) { bus_handle = open_first(bus_libraries, sizeof bus_libraries / sizeof bus_libraries[0]); }

void *ferry_bus_symbol(const char *name)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    if (!name || !has_prefix(name, bus_prefixes))
        return NULL;
    pthread_once(&once, open_bus);
    return bus_handle ? dlsym(bus_handle, name) : NULL;
}

/* ---- web views -------------------------------------------------------------------
 * Ferry's WebKit framework (webkit/) shows web content with this system's
 * WebKitGTK (webkit2gtk-4.1) and reads what a page hands back with
 * JavaScriptCore's GLib API. It asks for each call by name the first time
 * it makes one, so a program that links WebKit but never makes a web view
 * doesn't open WebKitGTK, and Ferry runs on a system without it. Only the
 * calls declared in webkit/WKHost.h are served. FERRY_WEBKITGTK names
 * another library to open in WebKitGTK's place (the tests use it to stand
 * for a system without WebKitGTK). */
static const char *const webkit_names[] = {
#include "webkit_names.h"
    NULL,
};
static void *webkit_handle, *jsc_handle;
static void open_webkit(void)
{
    const char *other = getenv("FERRY_WEBKITGTK");
    webkit_handle = dlopen(other && *other ? other : "libwebkit2gtk-4.1.so.0", RTLD_NOW | RTLD_LOCAL);
    if (webkit_handle)
        jsc_handle = dlopen("libjavascriptcoregtk-4.1.so.0", RTLD_NOW | RTLD_LOCAL);
}

void *ferry_webkit_symbol(const char *name)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    const char *const *p;
    if (!name)
        return NULL;
    for (p = webkit_names; *p; p++)
        if (!strcmp(*p, name))
            break;
    if (!*p)
        return NULL;
    pthread_once(&once, open_webkit);
    void *handle = !strncmp(name, "jsc_", 4) ? jsc_handle : webkit_handle;
    return handle ? dlsym(handle, name) : NULL;
}

/* ---- JavaScriptCore --------------------------------------------------------------
 * Ferry's JavaScriptCore framework (javascriptcore/) passes each call of
 * JavaScriptCore's C API to this system's JavaScriptCore
 * (libjavascriptcoregtk-4.1, the library WebKitGTK uses), which has the same
 * C API. It asks for each call by name the first time it is made, so a
 * program that links JavaScriptCore but never runs a script doesn't open
 * the library. Only the calls javascriptcore/JSCNames.h lists are served.
 * FERRY_JAVASCRIPTCORE names another library to open in its place (the
 * tests use it to stand for a system without JavaScriptCore). */
static const char *const jsc_names[] = {
#include "jsc_names.h"
    NULL,
};
static void *jsc_c_handle;
static void open_jsc(void)
{
    const char *other = getenv("FERRY_JAVASCRIPTCORE");
    jsc_c_handle = dlopen(other && *other ? other : "libjavascriptcoregtk-4.1.so.0", RTLD_NOW | RTLD_LOCAL);
}

void *ferry_jsc_symbol(const char *name)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    const char *const *p;
    if (!name)
        return NULL;
    for (p = jsc_names; *p; p++)
        if (!strcmp(*p, name))
            break;
    if (!*p)
        return NULL;
    pthread_once(&once, open_jsc);
    return jsc_c_handle ? dlsym(jsc_c_handle, name) : NULL;
}
