/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * os_log (freemac 1.223, Ferry 0.47.0), written from Apple's public
 * os_log(3) documentation. A Mac keeps these messages in its unified log;
 * here they go to syslog, as "subsystem:category" and the message, and also
 * to standard error when OS_ACTIVITY_DT_MODE is set, as Xcode sets it on a
 * Mac to mirror the log into a program's output. Debug messages are dropped
 * unless OS_LOG_DEBUG is set, as a Mac drops them unless asked to keep
 * them. Ferry's SDK makes the os_log macros call ferry_os_log with the
 * format and the arguments as they are; the format's privacy annotations
 * ("%{public}s", "%{private}@") are dropped, since nothing is redacted in a
 * local log, and "%@" is an object's description.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include "../ferry.h"
#include "objc-private.h"

/* A log is an object of the class OS_os_log, as on a Mac, where Swift
 * sees it as that class (OSLog, freemac 1.260). Logs live as long as the
 * program, so retain and release do nothing to them. */
static struct fobjc_class oslog_class, oslog_meta; /* the table below lists them */

struct os_log_s {
    Class isa;
    char *subsystem, *category;
};

struct os_log_s _os_log_default = {&oslog_class, NULL, NULL};
struct os_log_s _os_log_disabled = {&oslog_class, NULL, NULL};

void ferry_oslog_init(void)
{
    ferry_objc_make_class(&oslog_class, &oslog_meta, &ferry_class_NSObject, "OS_os_log", sizeof(struct os_log_s),
                          ferry_static_rr_methods, ferry_static_rr_count, NULL, 0, RT_STATIC_INSTANCES);
}

static struct os_log_s *mac_os_log_create(const char *subsystem, const char *category)
{
    struct os_log_s *l = calloc(1, sizeof *l);
    if (!l)
        return &_os_log_default;
    l->isa = &oslog_class;
    l->subsystem = strdup(subsystem ? subsystem : "");
    l->category = strdup(category ? category : "");
    return l;
}

enum { TYPE_DEFAULT = 0x00, TYPE_INFO = 0x01, TYPE_DEBUG = 0x02, TYPE_ERROR = 0x10, TYPE_FAULT = 0x11 };

static bool mac_os_log_type_enabled(struct os_log_s *log, uint8_t type)
{
    if (!log || log == &_os_log_disabled)
        return false;
    if (type == TYPE_DEBUG)
        return getenv("OS_LOG_DEBUG") != NULL;
    return true;
}

/* An object's description as UTF-8, or "(null)". */
static const char *describe(id obj)
{
    if (!obj)
        return "(null)";
    static SEL description, utf8;
    if (!description) {
        description = sel_registerName("description");
        utf8 = sel_registerName("UTF8String");
    }
    id text = SEND0(id, obj, description);
    const char *s = text ? SEND0(const char *, text, utf8) : NULL;
    return s ? s : "(null)";
}

/* Where a message's values come from: a va_list (ferry_os_log, Swift's
 * os_log), or the buffer a Mac compiler packs them into for os_log's macro,
 * which calls _os_log_impl. That buffer is laid out as clang's
 * __builtin_os_log_format makes it (clang/lib/AST/OSLog.cpp, open source):
 * a summary byte, the number of items, then each item as a descriptor byte
 * (its kind in the high four bits), its size in bytes, and its bytes. */
struct values {
    va_list *ap;
    const uint8_t *item, *end;
    int left;
};

/* The next item of the buffer: its bytes and size, or NULL. */
static const uint8_t *next_item(struct values *v, unsigned *size)
{
    if (v->left <= 0 || v->item + 2 > v->end)
        return NULL;
    unsigned n = v->item[1];
    const uint8_t *data = v->item + 2;
    if (data + n > v->end)
        return NULL;
    v->item = data + n;
    v->left--;
    *size = n;
    return data;
}

static long long take_int(struct values *v, int wide)
{
    if (v->ap)
        return wide == 2 ? va_arg(*v->ap, long long) : wide == 1 ? va_arg(*v->ap, long) : va_arg(*v->ap, int);
    unsigned n;
    const uint8_t *d = next_item(v, &n);
    if (!d)
        return 0;
    if (n == 1)
        return (int8_t)d[0];
    if (n == 2) {
        int16_t x;
        memcpy(&x, d, 2);
        return x;
    }
    if (n == 4) {
        int32_t x;
        memcpy(&x, d, 4);
        return x;
    }
    long long x = 0;
    memcpy(&x, d, n < 8 ? n : 8);
    return x;
}

static long double take_double(struct values *v, int big)
{
    if (v->ap)
        return big ? va_arg(*v->ap, long double) : va_arg(*v->ap, double);
    unsigned n;
    const uint8_t *d = next_item(v, &n);
    if (!d)
        return 0;
    if (n == 4) {
        float x;
        memcpy(&x, d, 4);
        return x;
    }
    if (n == 8) {
        double x;
        memcpy(&x, d, 8);
        return x;
    }
    long double x = 0;
    memcpy(&x, d, n < sizeof x ? n : sizeof x);
    return x;
}

static void *take_pointer(struct values *v)
{
    if (v->ap)
        return va_arg(*v->ap, void *);
    unsigned n;
    const uint8_t *d = next_item(v, &n);
    void *x = NULL;
    if (d)
        memcpy(&x, d, n < sizeof x ? n : sizeof x);
    return x;
}

/* The message: each conversion is formatted on its own, so that "%@" can be
 * an object and the annotations can be dropped. */
static char *format_message(const char *format, struct values *v)
{
    char *out = NULL;
    size_t size = 0;
    FILE *f = open_memstream(&out, &size);
    if (!f)
        return NULL;
    for (const char *p = format; *p; p++) {
        if (*p != '%') {
            fputc(*p, f);
            continue;
        }
        if (p[1] == '%') {
            fputc('%', f);
            p++;
            continue;
        }
        /* the spec: flags, width, precision, length and conversion */
        char spec[64] = "%";
        size_t n = 1;
        const char *q = p + 1;
        if (*q == '{') { /* a privacy or type annotation */
            while (*q && *q != '}')
                q++;
            if (*q)
                q++;
        }
        while (*q && strchr("-+ #0'", *q) && n < sizeof spec - 8)
            spec[n++] = *q++;
        while (*q && (strchr("0123456789.", *q) || *q == '*') && n < sizeof spec - 8)
            spec[n++] = *q++;
        int lng = 0, big = 0, size_mod = 0;
        while (*q && strchr("hlLqjzt", *q) && n < sizeof spec - 4) {
            if (*q == 'l')
                lng++;
            else if (*q == 'L')
                big = 1;
            else if (*q == 'q')
                lng = 2;
            else if (*q != 'h')
                size_mod = 1;
            spec[n++] = *q++;
        }
        char conv = *q;
        if (!conv)
            break;
        spec[n++] = conv;
        spec[n] = 0;
        int stars = 0;
        for (size_t i = 0; i < n; i++)
            stars += spec[i] == '*';
        int w1 = stars > 0 ? (int)take_int(v, 0) : 0, w2 = stars > 1 ? (int)take_int(v, 0) : 0;
#define OUT(x)                                                                                                     \
    do {                                                                                                           \
        if (stars == 2)                                                                                            \
            fprintf(f, spec, w1, w2, x);                                                                           \
        else if (stars == 1)                                                                                       \
            fprintf(f, spec, w1, x);                                                                               \
        else                                                                                                       \
            fprintf(f, spec, x);                                                                                   \
    } while (0)
        switch (conv) {
        case '@':
            fputs(describe((id)take_pointer(v)), f);
            break;
        case 'd': case 'i': case 'u': case 'x': case 'X': case 'o': case 'c':
            if (lng >= 2)
                OUT(take_int(v, 2));
            else if (lng == 1 || size_mod)
                OUT((long)take_int(v, 1));
            else
                OUT((int)take_int(v, 0));
            break;
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A':
            if (big)
                OUT(take_double(v, 1));
            else
                OUT((double)take_double(v, 0));
            break;
        case 's': {
            const char *str = take_pointer(v);
            OUT(str ? str : "(null)");
            break;
        }
        case 'p':
            OUT(take_pointer(v));
            break;
        case 'm': /* errno's message; the buffer carries the number */
            fputs(strerror(v->ap ? errno : (int)take_int(v, 0)), f);
            break;
        case 'P': /* a buffer, with its length before it */
        case 'S':
        case 'C':
            (void)take_pointer(v);
            fputs("<data>", f);
            break;
        default:
            fputc('%', f);
            fputc(conv, f);
            break;
        }
#undef OUT
        p = q;
    }
    fclose(f);
    return out;
}

/* One message, already formatted, to the log. */
static void write_message(struct os_log_s *log, uint8_t type, const char *text)
{
    int priority = type == TYPE_FAULT ? LOG_CRIT : type == TYPE_ERROR ? LOG_ERR
                 : type == TYPE_INFO  ? LOG_INFO : type == TYPE_DEBUG ? LOG_DEBUG : LOG_NOTICE;
    if (log->subsystem && *log->subsystem)
        syslog(priority, "[%s:%s] %s", log->subsystem, log->category, text);
    else
        syslog(priority, "%s", text);
    if (getenv("OS_ACTIVITY_DT_MODE"))
        fprintf(stderr, "%s\n", text);
}

static void mac_ferry_os_logv(struct os_log_s *log, uint8_t type, const char *format, va_list ap)
{
    if (!mac_os_log_type_enabled(log, type) || !format)
        return;
    va_list copy;
    va_copy(copy, ap);
    struct values v = {&copy, NULL, NULL, 0};
    char *text = format_message(format, &v);
    va_end(copy);
    if (!text)
        return;
    write_message(log, type, text);
    free(text);
}

/* What os_log's macro calls when built on a Mac (freemac 1.260): the
 * format and the buffer the compiler packed the values into. */
static void mac_os_log_impl(void *dso, struct os_log_s *log, uint8_t type, const char *format, const uint8_t *buf,
                            uint32_t size)
{
    (void)dso;
    if (!mac_os_log_type_enabled(log, type) || !format)
        return;
    struct values v = {NULL, buf ? buf + 2 : NULL, buf ? buf + size : NULL, buf && size >= 2 ? buf[1] : 0};
    char *text = format_message(format, &v);
    if (!text)
        return;
    write_message(log, type, text);
    free(text);
}

static void mac_ferry_os_log(struct os_log_s *log, uint8_t type, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    mac_ferry_os_logv(log, type, format, ap);
    va_end(ap);
}

/* Swift's Logger, which formats its message itself (freemac 1.230). */
static void mac_ferry_os_log_message(struct os_log_s *log, uint8_t type, const char *message)
{
    if (mac_os_log_type_enabled(log, type) && message)
        write_message(log, type, message);
}

const struct ferry_symbol ferry_oslog_symbols[] = {
    {"os_log_create", mac_os_log_create},
    {"os_log_type_enabled", mac_os_log_type_enabled},
    {"ferry_os_log", mac_ferry_os_log},
    {"ferry_os_logv", mac_ferry_os_logv},
    {"ferry_os_log_message", mac_ferry_os_log_message},
    {"_os_log_impl", mac_os_log_impl},
    {"_os_log_error_impl", mac_os_log_impl},
    {"_os_log_fault_impl", mac_os_log_impl},
    {"_os_log_debug_impl", mac_os_log_impl},
    {"_os_log_default", &_os_log_default},
    {"_os_log_disabled", &_os_log_disabled},
    {"OBJC_CLASS_$_OS_os_log", &oslog_class},
    {"OBJC_METACLASS_$_OS_os_log", &oslog_meta},
    {NULL, NULL},
};
