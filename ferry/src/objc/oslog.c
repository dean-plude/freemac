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
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include "../ferry.h"
#include "objc-private.h"

struct os_log_s {
    char *subsystem, *category;
};

struct os_log_s _os_log_default = {NULL, NULL};
struct os_log_s _os_log_disabled = {NULL, NULL};

static struct os_log_s *mac_os_log_create(const char *subsystem, const char *category)
{
    struct os_log_s *l = calloc(1, sizeof *l);
    if (!l)
        return &_os_log_default;
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

/* The message: each conversion is formatted on its own, so that "%@" can be
 * an object and the annotations can be dropped. */
static char *format_message(const char *format, va_list ap)
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
        int lng = 0, hh = 0, h = 0, big = 0, size_mod = 0;
        while (*q && strchr("hlLqjzt", *q) && n < sizeof spec - 4) {
            if (*q == 'l')
                lng++;
            else if (*q == 'h')
                h ? (hh = 1) : (h = 1);
            else if (*q == 'L')
                big = 1;
            else if (*q == 'q')
                lng = 2;
            else
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
        int w1 = stars > 0 ? va_arg(ap, int) : 0, w2 = stars > 1 ? va_arg(ap, int) : 0;
#define OUT(v)                                                                                                     \
    do {                                                                                                           \
        if (stars == 2)                                                                                            \
            fprintf(f, spec, w1, w2, v);                                                                           \
        else if (stars == 1)                                                                                       \
            fprintf(f, spec, w1, v);                                                                               \
        else                                                                                                       \
            fprintf(f, spec, v);                                                                                   \
    } while (0)
        switch (conv) {
        case '@':
            fputs(describe(va_arg(ap, id)), f);
            break;
        case 'd': case 'i': case 'u': case 'x': case 'X': case 'o': case 'c':
            if (lng >= 2)
                OUT(va_arg(ap, long long));
            else if (lng == 1 || size_mod)
                OUT(va_arg(ap, long));
            else
                OUT(va_arg(ap, int));
            (void)hh;
            break;
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A':
            if (big)
                OUT(va_arg(ap, long double));
            else
                OUT(va_arg(ap, double));
            break;
        case 's': {
            const char *s = va_arg(ap, const char *);
            OUT(s ? s : "(null)");
            break;
        }
        case 'p':
            OUT(va_arg(ap, void *));
            break;
        case 'P': /* a buffer, with its length before it */
        case 'S':
        case 'C':
            (void)va_arg(ap, void *);
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
    char *text = format_message(format, ap);
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
    {"_os_log_default", &_os_log_default},
    {"_os_log_disabled", &_os_log_disabled},
    {NULL, NULL},
};
