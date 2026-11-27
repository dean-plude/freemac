/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libSystem calls that Blender's official Mac build makes (freemac Blender
 * work), each written from its Mac man page, the Mac SDK's documented
 * numbers or Apple's public Mach documentation:
 *
 * - NXGetLocalArchInfo(3), NXGetArchInfoFromName and _FromCpuType: this
 *   machine is x86_64, the only kind of Mac program Ferry runs.
 * - The classification calls Mac math.h falls back to (__fpclassifyd and
 *   the __isnan, __isinf, __isfinite, __isnormal and __signbit families).
 *   A Mac numbers its FP_ classes FP_NAN 1, FP_INFINITE 2, FP_ZERO 3,
 *   FP_NORMAL 4, FP_SUBNORMAL 5.
 * - Mach clocks: host_get_clock_service and clock_get_time, the system
 *   clock (0) counting from boot and the calendar clock (1) from 1970.
 * - openlog(3), syslog and closelog, whose priority, facility and option
 *   numbers are the same on both systems.
 * - futimens(2) and utimensat, where a Mac writes UTIME_NOW as -1 and
 *   UTIME_OMIT as -2, and AT_SYMLINK_NOFOLLOW as 0x20.
 * - mknod(2), a Mac dev_t holding the major number in its top 8 bits.
 * - proc_pid_rusage(3) for this process, flavours 0 to 4 (rusage_info_v0
 *   to _v4), with times in mach_absolute_time units (nanoseconds here) and
 *   the resident size as the footprint.
 * - regcomp(3), regexec, regerror and regfree in the Mac's (BSD) layout:
 *   a 32-byte regex_t, 64-bit match offsets and BSD flag numbers. The
 *   matching is this system's.
 * - strcasecmp_l and strncasecmp_l, compared as in the C locale.
 * (confstr, gethostuuid, Mach exception ports, thread policies and the
 * ___chkstk_darwin stack probe, which Blender calls too, are Audacity's, in
 * libc_audacity.c.)
 * - _Unwind_Backtrace and _Unwind_GetIP, on this system's unwinder, which
 *   walks a Mac program's frames like any other.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <fenv.h>
#include <math.h>
#include <pthread.h>
#include <regex.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

#include "ferry.h"

/* ---- NXArchInfo -------------------------------------------------------- */

struct mac_arch_info {
    const char *name;
    int cputype, cpusubtype;
    int byteorder; /* NX_LittleEndian is 1 */
    const char *description;
};

static const struct mac_arch_info arch_x86_64 = {"x86_64", 0x01000007, 3, 1, "Intel x86-64"};
static const struct mac_arch_info arch_i386 = {"i386", 7, 3, 1, "Intel 80x86"};

static const struct mac_arch_info *mac_NXGetLocalArchInfo(void) { return &arch_x86_64; }

static const struct mac_arch_info *mac_NXGetArchInfoFromName(const char *name)
{
    if (name && !strcmp(name, arch_x86_64.name))
        return &arch_x86_64;
    if (name && !strcmp(name, arch_i386.name))
        return &arch_i386;
    return NULL;
}

static const struct mac_arch_info *mac_NXGetArchInfoFromCpuType(int cputype, int cpusubtype)
{
    if (cputype == arch_x86_64.cputype)
        return &arch_x86_64;
    if (cputype == arch_i386.cputype)
        return &arch_i386;
    return NULL;
}

/* ---- floating-point classes -------------------------------------------- */

enum { MAC_FP_NAN = 1, MAC_FP_INFINITE, MAC_FP_ZERO, MAC_FP_NORMAL, MAC_FP_SUBNORMAL };

static int mac_class(int c)
{
    switch (c) {
    case FP_NAN: return MAC_FP_NAN;
    case FP_INFINITE: return MAC_FP_INFINITE;
    case FP_ZERO: return MAC_FP_ZERO;
    case FP_SUBNORMAL: return MAC_FP_SUBNORMAL;
    default: return MAC_FP_NORMAL;
    }
}

static int mac_fpclassifyf(float x) { return mac_class(fpclassify(x)); }
static int mac_fpclassifyd(double x) { return mac_class(fpclassify(x)); }
static int mac_fpclassifyl(long double x) { return mac_class(fpclassify(x)); }
static int mac_isnanf(float x) { return isnan(x); }
static int mac_isnand(double x) { return isnan(x); }
static int mac_isnanl(long double x) { return isnan(x); }
static int mac_isinff(float x) { return isinf(x) != 0; }
static int mac_isinfd(double x) { return isinf(x) != 0; }
static int mac_isinfl(long double x) { return isinf(x) != 0; }
static int mac_isfinitef(float x) { return isfinite(x); }
static int mac_isfinited(double x) { return isfinite(x); }
static int mac_isfinitel(long double x) { return isfinite(x); }
static int mac_isnormalf(float x) { return isnormal(x); }
static int mac_isnormald(double x) { return isnormal(x); }
static int mac_isnormall(long double x) { return isnormal(x); }
static int mac_signbitf(float x) { return signbit(x) != 0; }
static int mac_signbitd(double x) { return signbit(x) != 0; }
static int mac_signbitl(long double x) { return signbit(x) != 0; }

/* ---- Mach clocks ------------------------------------------------------- */

#define MAC_CLOCK_PORT 0x5c000 /* a port name for each clock, + its id */

struct mac_mach_timespec {
    unsigned int tv_sec;
    int tv_nsec;
};

static int mac_host_get_clock_service(unsigned host, int clock_id, unsigned *clock)
{
    if (clock_id != 0 && clock_id != 1)
        return 4; /* KERN_INVALID_ARGUMENT */
    *clock = MAC_CLOCK_PORT + (unsigned)clock_id;
    return 0;
}

static int mac_clock_get_time(unsigned clock, struct mac_mach_timespec *t)
{
    struct timespec now;
    if (clock == MAC_CLOCK_PORT)
        clock_gettime(CLOCK_MONOTONIC, &now);
    else if (clock == MAC_CLOCK_PORT + 1)
        clock_gettime(CLOCK_REALTIME, &now);
    else
        return 4;
    t->tv_sec = (unsigned)now.tv_sec;
    t->tv_nsec = (int)now.tv_nsec;
    return 0;
}

/* ---- syslog ------------------------------------------------------------ */

static void mac_openlog(const char *ident, int options, int facility) { openlog(ident, options, facility); }
static void mac_closelog(void) { closelog(); }

static void mac_syslog(int priority, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vsyslog(priority, format, ap);
    va_end(ap);
}

static void mac_vsyslog(int priority, const char *format, va_list ap) { vsyslog(priority, format, ap); }

/* ---- file times and nodes ---------------------------------------------- */

#define MAC_UTIME_NOW -1L
#define MAC_UTIME_OMIT -2L
#define MAC_AT_FDCWD -2
#define MAC_AT_SYMLINK_NOFOLLOW 0x20

static const struct timespec *host_times(const struct timespec *mac, struct timespec out[2])
{
    if (!mac)
        return NULL;
    for (int i = 0; i < 2; i++) {
        out[i] = mac[i];
        if (mac[i].tv_nsec == MAC_UTIME_NOW)
            out[i].tv_nsec = UTIME_NOW;
        else if (mac[i].tv_nsec == MAC_UTIME_OMIT)
            out[i].tv_nsec = UTIME_OMIT;
    }
    return out;
}

static int mac_futimens(int fd, const struct timespec times[2])
{
    struct timespec t[2];
    return futimens(fd, host_times(times, t));
}

static int mac_utimensat(int dirfd, const char *path, const struct timespec times[2], int flags)
{
    struct timespec t[2];
    return utimensat(dirfd == MAC_AT_FDCWD ? AT_FDCWD : dirfd, path, host_times(times, t),
                     flags & MAC_AT_SYMLINK_NOFOLLOW ? AT_SYMLINK_NOFOLLOW : 0);
}

static int mac_mknod(const char *path, unsigned mode, int32_t dev)
{
    uint32_t d = (uint32_t)dev;
    return mknod(path, mode, makedev(d >> 24, d & 0xffffff));
}

/* ---- proc_pid_rusage --------------------------------------------------- */

static int mac_proc_pid_rusage(int pid, int flavor, void *buffer)
{
    /* rusage_info_v0 to _v4: 16 bytes of UUID, then 10, 16, 18, 27 and 35
     * 64-bit fields */
    static const int fields[] = {10, 16, 18, 27, 35};
    if (flavor < 0 || flavor > 4 || !buffer) {
        errno = EINVAL;
        return -1;
    }
    if (pid != getpid()) {
        errno = EPERM;
        return -1;
    }
    memset(buffer, 0, 16 + 8 * fields[flavor]);
    uint64_t *f = (uint64_t *)((char *)buffer + 16);
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    f[0] = (uint64_t)ru.ru_utime.tv_sec * 1000000000u + (uint64_t)ru.ru_utime.tv_usec * 1000u;
    f[1] = (uint64_t)ru.ru_stime.tv_sec * 1000000000u + (uint64_t)ru.ru_stime.tv_usec * 1000u;
    f[4] = (uint64_t)ru.ru_majflt;
    long pages = 0, resident = 0;
    FILE *statm = fopen("/proc/self/statm", "r");
    if (statm) {
        if (fscanf(statm, "%ld %ld", &pages, &resident) != 2)
            resident = 0;
        fclose(statm);
    }
    f[6] = (uint64_t)resident * (uint64_t)sysconf(_SC_PAGESIZE); /* ri_resident_size */
    f[7] = f[6];                                                 /* ri_phys_footprint */
    if (flavor >= 4)
        f[28] = (uint64_t)ru.ru_maxrss * 1024u; /* ri_lifetime_max_phys_footprint */
    return 0;
}

/* ---- regex ------------------------------------------------------------- */

struct mac_regex {
    int re_magic;
    size_t re_nsub;
    const char *re_endp;
    regex_t *re_g; /* this system's compiled expression */
};

struct mac_regmatch {
    int64_t rm_so, rm_eo;
};

#define MAC_REG_MAGIC 0xf265
#define MAC_REG_EXTENDED 0x1
#define MAC_REG_ICASE 0x2
#define MAC_REG_NOSUB 0x4
#define MAC_REG_NEWLINE 0x8
#define MAC_REG_NOTBOL 0x1
#define MAC_REG_NOTEOL 0x2
#define MAC_REG_STARTEND 0x4
#define MAC_REG_ESPACE 12
#define MAC_REG_INVARG 16

static int mac_regcomp(struct mac_regex *re, const char *pattern, int cflags)
{
    int flags = (cflags & MAC_REG_EXTENDED ? REG_EXTENDED : 0) | (cflags & MAC_REG_ICASE ? REG_ICASE : 0) |
                (cflags & MAC_REG_NOSUB ? REG_NOSUB : 0) | (cflags & MAC_REG_NEWLINE ? REG_NEWLINE : 0);
    regex_t *g = malloc(sizeof *g);
    if (!g)
        return MAC_REG_ESPACE;
    int rc = regcomp(g, pattern, flags);
    if (rc) {
        free(g);
        re->re_g = NULL;
        return rc; /* the error numbers are the same, REG_NOMATCH 1 to REG_BADRPT 13 */
    }
    re->re_magic = MAC_REG_MAGIC;
    re->re_nsub = g->re_nsub;
    re->re_endp = NULL;
    re->re_g = g;
    return 0;
}

static int mac_regexec(const struct mac_regex *re, const char *string, size_t nmatch, struct mac_regmatch *m,
                       int eflags)
{
    if (!re || re->re_magic != MAC_REG_MAGIC || !re->re_g)
        return MAC_REG_INVARG;
    int flags = (eflags & MAC_REG_NOTBOL ? REG_NOTBOL : 0) | (eflags & MAC_REG_NOTEOL ? REG_NOTEOL : 0);
    regmatch_t local[16], *hm = local;
    if (nmatch > 16 && !(hm = malloc(nmatch * sizeof *hm)))
        return MAC_REG_ESPACE;
    if (eflags & MAC_REG_STARTEND && m) {
        flags |= REG_STARTEND;
        hm[0].rm_so = (regoff_t)m[0].rm_so;
        hm[0].rm_eo = (regoff_t)m[0].rm_eo;
    }
    int rc = regexec(re->re_g, string, m ? nmatch : 0, m ? hm : NULL, flags);
    if (!rc && m)
        for (size_t i = 0; i < nmatch; i++) {
            m[i].rm_so = hm[i].rm_so;
            m[i].rm_eo = hm[i].rm_eo;
        }
    if (hm != local)
        free(hm);
    return rc;
}

static size_t mac_regerror(int code, const struct mac_regex *re, char *buf, size_t size)
{
    return regerror(code, re ? re->re_g : NULL, buf, size);
}

static void mac_regfree(struct mac_regex *re)
{
    if (!re || !re->re_g)
        return;
    regfree(re->re_g);
    free(re->re_g);
    re->re_g = NULL;
    re->re_magic = 0;
}

/* ---- strings ----------------------------------------------------------- */

static int mac_strcasecmp_l(const char *a, const char *b, void *locale) { return strcasecmp(a, b); }
static int mac_strncasecmp_l(const char *a, const char *b, size_t n, void *locale) { return strncasecmp(a, b, n); }

/* ---- the unwinder ------------------------------------------------------ */

static void *unwinder(const char *name)
{
    static void *lib;
    if (!lib && !(lib = dlopen("libgcc_s.so.1", RTLD_NOW | RTLD_GLOBAL)))
        return NULL;
    return dlsym(lib, name);
}

static int mac_Unwind_Backtrace(int (*trace)(void *, void *), void *arg)
{
    int (*fn)(int (*)(void *, void *), void *) = (int (*)(int (*)(void *, void *), void *))unwinder("_Unwind_Backtrace");
    return fn ? fn(trace, arg) : 5; /* _URC_END_OF_STACK */
}

static uintptr_t mac_Unwind_GetIP(void *context)
{
    uintptr_t (*fn)(void *) = (uintptr_t (*)(void *))unwinder("_Unwind_GetIP");
    return fn ? fn(context) : 0;
}

static uintptr_t mac_Unwind_GetCFA(void *context)
{
    uintptr_t (*fn)(void *) = (uintptr_t (*)(void *))unwinder("_Unwind_GetCFA");
    return fn ? fn(context) : 0;
}

const struct ferry_symbol ferry_libc_blender_symbols[] = {
    {"NXGetLocalArchInfo", mac_NXGetLocalArchInfo},
    {"NXGetArchInfoFromName", mac_NXGetArchInfoFromName},
    {"NXGetArchInfoFromCpuType", mac_NXGetArchInfoFromCpuType},
    {"__fpclassifyf", mac_fpclassifyf},
    {"__fpclassifyd", mac_fpclassifyd},
    {"__fpclassify", mac_fpclassifyd},
    {"__fpclassifyl", mac_fpclassifyl},
    {"__isnanf", mac_isnanf},
    {"__isnand", mac_isnand},
    {"__isnanl", mac_isnanl},
    {"__isinff", mac_isinff},
    {"__isinfd", mac_isinfd},
    {"__isinfl", mac_isinfl},
    {"__isfinitef", mac_isfinitef},
    {"__isfinited", mac_isfinited},
    {"__isfinitel", mac_isfinitel},
    {"__isnormalf", mac_isnormalf},
    {"__isnormald", mac_isnormald},
    {"__isnormall", mac_isnormall},
    {"__signbitf", mac_signbitf},
    {"__signbitd", mac_signbitd},
    {"__signbitl", mac_signbitl},
    {"host_get_clock_service", mac_host_get_clock_service},
    {"clock_get_time", mac_clock_get_time},
    {"openlog", mac_openlog},
    {"closelog", mac_closelog},
    {"syslog", mac_syslog},
    {"vsyslog", mac_vsyslog},
    {"futimens", mac_futimens},
    {"utimensat", mac_utimensat},
    {"mknod", mac_mknod},
    {"proc_pid_rusage", mac_proc_pid_rusage},
    {"regcomp", mac_regcomp},
    {"regexec", mac_regexec},
    {"regerror", mac_regerror},
    {"regfree", mac_regfree},
    {"strcasecmp_l", mac_strcasecmp_l},
    {"strncasecmp_l", mac_strncasecmp_l},
    {"_Unwind_Backtrace", mac_Unwind_Backtrace},
    {"_Unwind_GetIP", mac_Unwind_GetIP},
    {"_Unwind_GetCFA", mac_Unwind_GetCFA},
    /* the same on both systems */
    {"feclearexcept", feclearexcept},
    {"fetestexcept", fetestexcept},
    {"feraiseexcept", feraiseexcept},
    {"mincore", mincore},
    {NULL, NULL},
};
