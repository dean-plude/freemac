/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Swift programs (freemac 1.227). A Mac program written in Swift links
 * Swift's runtime and standard library, /usr/lib/swift/libswiftCore.dylib,
 * and the libraries beside it. Ferry serves them from its own build of the
 * open-source Swift project's runtime for an Intel Mac
 * (swift/build-runtime.sh), kept in a "swift" folder beside Ferry's
 * frameworks; an app may also carry its own copies under @rpath, which are
 * used first. Here too are the few libSystem calls that runtime makes and
 * Ferry didn't have, written from their man pages.
 */
#define _GNU_SOURCE
#include <limits.h>
#include <fcntl.h>
#include <math.h>
#include <semaphore.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ferry.h"

/* "/usr/lib/swift/libswiftCore.dylib" (or "@rpath/libswiftCore.dylib", when
 * the app's own copy isn't there) to Ferry's copy, in the "swift" folder of
 * Ferry's frameworks: $FERRY_FRAMEWORKS/swift, frameworks/swift beside the
 * ferry program, then /usr/lib/ferry/frameworks/swift. */
int ferry_find_swift_library(const char *install_name, char *out, size_t size)
{
    const char *base = strrchr(install_name, '/');
    base = base ? base + 1 : install_name;
    if (strncmp(base, "libswift", 8) || !strstr(base, ".dylib"))
        return 0;
    char self[PATH_MAX], fw[PATH_MAX];
    const char *dirs[3] = {NULL, NULL, "/usr/lib/ferry/frameworks/swift"};
    const char *env_fw = getenv("FERRY_FRAMEWORKS");
    if (env_fw && *env_fw) {
        snprintf(fw, sizeof fw, "%s/swift", env_fw);
        dirs[0] = fw;
    }
    ssize_t n = readlink("/proc/self/exe", self, sizeof self - 32);
    if (n > 0) {
        self[n] = 0;
        char *slash = strrchr(self, '/');
        if (slash) {
            strcpy(slash + 1, "frameworks/swift");
            dirs[1] = self;
        }
    }
    for (int i = 0; i < 3; i++) {
        struct stat st;
        if (!dirs[i] || !*dirs[i])
            continue;
        snprintf(out, size, "%s/%s", dirs[i], base);
        if (stat(out, &st) == 0 && S_ISREG(st.st_mode))
            return 1;
    }
    return 0;
}

/* memset_pattern4, 8 and 16 (memset_pattern(3)): fill with a repeated
 * pattern of that many bytes; the last copy may be cut short. */
static void fill_pattern(void *b, const void *pattern, size_t plen, size_t len)
{
    uint8_t *p = b;
    while (len >= plen) {
        memcpy(p, pattern, plen);
        p += plen;
        len -= plen;
    }
    memcpy(p, pattern, len);
}
static void mac_memset_pattern4(void *b, const void *pattern, size_t len) { fill_pattern(b, pattern, 4, len); }
static void mac_memset_pattern8(void *b, const void *pattern, size_t len) { fill_pattern(b, pattern, 8, len); }
static void mac_memset_pattern16(void *b, const void *pattern, size_t len) { fill_pattern(b, pattern, 16, len); }

/* The compiler's own helpers that Swift's code calls (128-bit division,
 * float to half), from this system's compiler library, and the maths
 * calls Swift's numbers use that Ferry hadn't passed through: the same
 * functions, with the same calling convention, on both systems. */
extern __int128 __divti3(__int128, __int128);
extern __int128 __modti3(__int128, __int128);
extern unsigned __int128 __udivti3(unsigned __int128, unsigned __int128);
extern unsigned __int128 __umodti3(unsigned __int128, unsigned __int128);
extern _Float16 __truncsfhf2(float);
extern _Float16 __truncdfhf2(double);
extern float __extendhfsf2(_Float16);

/* Half-precision conversions as a Mac program calls them. On the Mac
 * (x86_64), the compiler passes a half to these helpers and takes one back
 * as a 16-bit integer, in %edi and %ax; this system's helpers use %xmm0
 * for it. So the Mac names get these, which take and give the bits. */
static float mac_extendhfsf2(uint16_t bits)
{
    _Float16 h;
    memcpy(&h, &bits, sizeof h);
    return __extendhfsf2(h);
}
static uint16_t mac_truncsfhf2(float f)
{
    _Float16 h = __truncsfhf2(f);
    uint16_t bits;
    memcpy(&bits, &h, sizeof bits);
    return bits;
}
static uint16_t mac_truncdfhf2(double d)
{
    _Float16 h = __truncdfhf2(d);
    uint16_t bits;
    memcpy(&bits, &h, sizeof bits);
    return bits;
}

/* Named semaphores (sem_open(2)), which Swift's Darwin overlay wraps: this
 * system's, with the Mac's O_CREAT and O_EXCL turned into this system's.
 * A Mac program only ever holds the pointer. */
static sem_t *mac_sem_open(const char *name, int mac_flags, ...)
{
    int flags = 0;
    if (mac_flags & 0x0200)
        flags |= O_CREAT;
    if (mac_flags & 0x0800)
        flags |= O_EXCL;
    if (!(flags & O_CREAT))
        return sem_open(name, flags);
    va_list ap;
    va_start(ap, mac_flags);
    unsigned mode = va_arg(ap, unsigned);
    unsigned value = va_arg(ap, unsigned);
    va_end(ap);
    sem_t *s = sem_open(name, flags, (mode_t)mode, value);
    return s == SEM_FAILED ? (sem_t *)-1 : s;
}

/* The program's name, which Swift's runtime reads to decide whether to
 * use a system library of prespecialised generics; Ferry has none. */
static const char *mac_progname;

/* Two of the standard library's questions about the macOS version, which
 * Swift 6.2 and later compile @available checks and the like into, and
 * which Ferry's build of Swift's runtime doesn't have (freemac 1.260,
 * Rectangle). They answer from the version Ferry presents (sysversion.c).
 * The first is Swift's own function, taking the version wanted and the
 * Mac Catalyst one (which doesn't apply here) as six machine words; Swift
 * passes and returns those as C does. */
struct swift_os_version { intptr_t major, minor, patch; };

static struct swift_os_version mac_swift_stdlib_operatingSystemVersion(void)
{
    uint32_t v = ferry_macos_version_packed();
    struct swift_os_version r = {v >> 16, v >> 8 & 0xff, v & 0xff};
    return r;
}

static bool mac_swift_isOSVersionAtLeastOrVariant(intptr_t major, intptr_t minor, intptr_t patch, intptr_t vmajor,
                                                  intptr_t vminor, intptr_t vpatch)
{
    (void)vmajor, (void)vminor, (void)vpatch;
    struct swift_os_version os = mac_swift_stdlib_operatingSystemVersion();
    if (os.major != major)
        return os.major > major;
    if (os.minor != minor)
        return os.minor > minor;
    return os.patch >= patch;
}

/* The older question without the Catalyst version, which Swift 5 compiled
 * #available into (Hex Fiend's byte themes ask for macOS 12, freemac 1.270). */
static bool mac_swift_isOSVersionAtLeast(intptr_t major, intptr_t minor, intptr_t patch)
{
    return mac_swift_isOSVersionAtLeastOrVariant(major, minor, patch, 0, 0, 0);
}

const struct ferry_symbol ferry_swift_symbols[] = {
    {"__divti3", __divti3},
    {"__modti3", __modti3},
    {"__udivti3", __udivti3},
    {"__umodti3", __umodti3},
    {"__truncsfhf2", mac_truncsfhf2},
    {"__truncdfhf2", mac_truncdfhf2},
    {"__extendhfsf2", mac_extendhfsf2},
    {"__gnu_h2f_ieee", mac_extendhfsf2},
    {"__gnu_f2h_ieee", mac_truncsfhf2},
    {"exp2f", exp2f},
    {"fmaf", fmaf},
    {"fmal", fmal},
    {"rintl", rintl},
    {"rintf", rintf},
    {"nearbyintl", nearbyintl},
    {"nearbyintf", nearbyintf},
    {"remainderf", remainderf},
    {"remainderl", remainderl},
    {"acosf", acosf}, {"acosl", acosl}, {"asinf", asinf}, {"asinl", asinl}, {"atanl", atanl},
    {"acoshf", acoshf}, {"acoshl", acoshl}, {"asinhf", asinhf}, {"asinhl", asinhl},
    {"atanhf", atanhf}, {"atanhl", atanhl}, {"coshf", coshf}, {"coshl", coshl}, {"sinhf", sinhf},
    {"sinhl", sinhl}, {"tanhf", tanhf}, {"tanhl", tanhl}, {"expm1f", expm1f}, {"expm1l", expm1l},
    {"frexpf", frexpf}, {"ilogbf", ilogbf}, {"ilogbl", ilogbl}, {"ldexpf", ldexpf},
    {"log1pf", log1pf}, {"log1pl", log1pl}, {"logbf", logbf}, {"logbl", logbl}, {"modff", modff},
    {"scalbnf", scalbnf}, {"scalbnl", scalbnl}, {"scalblnf", scalblnf}, {"scalblnl", scalblnl},
    {"cbrtf", cbrtf}, {"cbrtl", cbrtl}, {"hypotl", hypotl}, {"erff", erff}, {"erfl", erfl},
    {"erfcf", erfcf}, {"erfcl", erfcl}, {"lgammaf", lgammaf}, {"lgammal", lgammal},
    {"tgammaf", tgammaf}, {"tgammal", tgammal}, {"lrintf", lrintf}, {"lrintl", lrintl},
    {"llrintf", llrintf}, {"llrintl", llrintl}, {"lroundf", lroundf}, {"lroundl", lroundl},
    {"llroundf", llroundf}, {"llroundl", llroundl}, {"remquof", remquof}, {"remquol", remquol},
    {"copysignf", copysignf}, {"nanf", nanf}, {"nanl", nanl}, {"nextafterf", nextafterf},
    {"nextafterl", nextafterl}, {"nexttowardf", nexttowardf}, {"nexttowardl", nexttowardl},
    {"fdimf", fdimf}, {"fdiml", fdiml},
    {"j0", j0}, {"j1", j1}, {"jn", jn}, {"y0", y0}, {"y1", y1}, {"yn", yn},
    {"ilogb", ilogb}, {"logb", logb}, {"scalbln", scalbln}, {"llrint", llrint}, {"nan", nan}, {"nexttoward", nexttoward},
    {"remquo", remquo}, {"lgamma_r", lgamma_r}, {"lgammaf_r", lgammaf_r}, {"lgammal_r", lgammal_r},
    {"sem_open", mac_sem_open}, {"sem_close", sem_close}, {"sem_unlink", sem_unlink},
    {"sem_wait", sem_wait}, {"sem_trywait", sem_trywait}, {"sem_post", sem_post},
    {"environ", &environ},
    {"__progname", &mac_progname},
    {"memset_pattern4", mac_memset_pattern4},
    {"memset_pattern8", mac_memset_pattern8},
    {"memset_pattern16", mac_memset_pattern16},
    {"_swift_stdlib_operatingSystemVersion", mac_swift_stdlib_operatingSystemVersion},
    {"$ss042_stdlib_isOSVersionAtLeastOrVariantVersiondE0yBi1_Bw_BwBwBwBwBwtF", mac_swift_isOSVersionAtLeastOrVariant},
    {"$ss26_stdlib_isOSVersionAtLeastyBi1_Bw_BwBwtF", mac_swift_isOSVersionAtLeast},
    {NULL, NULL},
};
