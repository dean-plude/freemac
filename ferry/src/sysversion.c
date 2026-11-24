/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The macOS version Ferry presents, and the Mac's version file.
 *
 * Programs (and updaters such as Sparkle) ask which macOS they run on in
 * several ways: uname's Darwin release (posix.c), sysctl's kern.osrelease,
 * kern.osversion and kern.osproductversion (sysctl.c), NSProcessInfo's
 * operatingSystemVersion and Gestalt (Foundation), the compiler's
 * @available checks (below), and by reading
 * /System/Library/CoreServices/SystemVersion.plist, the property list a Mac
 * keeps there. All of them answer from the numbers in ferry.h, so they
 * agree. The version file doesn't exist on this system: reading it, and
 * asking about it with stat or access, gets a read-only file Ferry makes
 * in memory. Its keys are the ones Apple documents for the file.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include "ferry.h"

static const char version_file[] = "/System/Library/CoreServices/SystemVersion.plist";

static const char version_plist[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n"
    "<dict>\n"
    "\t<key>ProductBuildVersion</key>\n"
    "\t<string>" FERRY_MACOS_BUILD "</string>\n"
    "\t<key>ProductName</key>\n"
    "\t<string>macOS</string>\n"
    "\t<key>ProductUserVisibleVersion</key>\n"
    "\t<string>" FERRY_MACOS_VERSION "</string>\n"
    "\t<key>ProductVersion</key>\n"
    "\t<string>" FERRY_MACOS_VERSION "</string>\n"
    "</dict>\n"
    "</plist>\n";

/* For Ferry's Foundation (NSProcessInfo and Gestalt). */
const char *ferry_macos_version(const char **build)
{
    if (build)
        *build = FERRY_MACOS_BUILD;
    return FERRY_MACOS_VERSION;
}

/* The path with repeated slashes taken as one, as the system does. */
static int is_version_file(const char *path)
{
    if (!path || path[0] != '/')
        return 0;
    const char *a = path, *b = version_file;
    while (*a && *b) {
        if (*a != *b)
            return 0;
        if (*a == '/')
            while (a[1] == '/')
                a++;
        a++, b++;
    }
    return !*a && !*b;
}

int ferry_is_virtual(const char *path) { return is_version_file(path); }

/* A descriptor reading the file from its start, or -1 with errno set. */
int ferry_virtual_open(const char *path, int linux_flags)
{
    if (!is_version_file(path)) {
        errno = ENOENT;
        return -1;
    }
    if ((linux_flags & O_ACCMODE) != O_RDONLY || (linux_flags & (O_CREAT | O_TRUNC))) {
        errno = EACCES; /* it belongs to the system */
        return -1;
    }
    int fd = memfd_create("SystemVersion.plist", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0)
        return -1;
    size_t len = sizeof version_plist - 1;
    if (write(fd, version_plist, len) != (ssize_t)len || lseek(fd, 0, SEEK_SET) != 0) {
        int e = errno;
        close(fd);
        errno = e ? e : EIO;
        return -1;
    }
    fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE | F_SEAL_SEAL);
    if (!(linux_flags & O_CLOEXEC))
        fcntl(fd, F_SETFD, 0);
    return fd;
}

/* What stat says about it: a plain file the system owns, readable by all. */
int ferry_virtual_stat(const char *path, struct stat *s)
{
    if (!is_version_file(path))
        return 0;
    memset(s, 0, sizeof *s);
    s->st_mode = S_IFREG | 0644;
    s->st_nlink = 1;
    s->st_size = sizeof version_plist - 1;
    s->st_blksize = 4096;
    s->st_blocks = 8;
    /* a fixed time, so that the file looks the same on every run */
    s->st_mtim.tv_sec = s->st_ctim.tv_sec = s->st_atim.tv_sec = 1704067200; /* 2024-01-01 */
    return 1;
}

/* uname's version field and sysctl's kern.version: shaped like a Mac's
 * ("Darwin Kernel Version 23.6.0: <when>; root:<build>/RELEASE_X86_64"),
 * with this system's kernel where a Mac names its build date. Programs that
 * tell Intel from Apple silicon by the RELEASE_ suffix find X86_64. */
const char *ferry_kernel_version(void)
{
    static char version[256];
    if (!version[0]) {
        struct utsname u;
        if (uname(&u) < 0)
            snprintf(u.release, sizeof u.release, "unknown");
        snprintf(version, sizeof version,
                 "Darwin Kernel Version " FERRY_DARWIN_RELEASE ": Ferry on Linux %s; root:ferry/RELEASE_X86_64",
                 u.release);
    }
    return version;
}

/* ---- availability checks ----------------------------------------------------
 * if (@available(macOS 13, *)) and __builtin_available compile to a call into
 * the compiler's runtime. With Ferry's SDK it is a call into libSystem, served
 * here; an app built on a Mac carries the compiler's runtime inside it, and
 * that asks dyld's _availability_version_check, which it finds with
 * dlsym(RTLD_DEFAULT, "_availability_version_check") (dyld.c). The calls'
 * interfaces are the ones LLVM's compiler-rt publishes. A version is packed
 * as dyld writes it: major << 16 | minor << 8 | patch. Only macOS (platform
 * 1) is answered; a check for another platform (iOS, Mac Catalyst...) alone
 * is false. */

#define PLATFORM_MACOS 1

static uint32_t pack(long major, long minor, long patch)
{
    if (major < 0)
        major = 0;
    if (minor < 0)
        minor = 0;
    if (patch < 0)
        patch = 0;
    return (uint32_t)(major > 0xffff ? 0xffff : major) << 16 | (uint32_t)(minor > 0xff ? 0xff : minor) << 8 |
           (uint32_t)(patch > 0xff ? 0xff : patch);
}

uint32_t ferry_macos_version_packed(void)
{
    const char *s = FERRY_MACOS_VERSION;
    char *end;
    long major = strtol(s, &end, 10), minor = 0, patch = 0;
    if (*end == '.')
        minor = strtol(end + 1, &end, 10);
    if (*end == '.')
        patch = strtol(end + 1, &end, 10);
    return pack(major, minor, patch);
}

struct build_version { uint32_t platform, version; };

/* True if this is at least the version listed for macOS; false if none of
 * those listed is for macOS. */
static bool availability_version_check(uint32_t count, const struct build_version *versions)
{
    for (uint32_t i = 0; versions && i < count; i++)
        if (versions[i].platform == PLATFORM_MACOS)
            return ferry_macos_version_packed() >= versions[i].version;
    return false;
}

static int32_t is_platform_version_at_least(uint32_t platform, uint32_t major, uint32_t minor, uint32_t patch)
{
    struct build_version v = {platform, pack(major, minor, patch)};
    return availability_version_check(1, &v);
}

/* Code built for both macOS and Mac Catalyst asks about either. */
static int32_t is_platform_or_variant_at_least(uint32_t platform, uint32_t major, uint32_t minor, uint32_t patch,
                                               uint32_t platform2, uint32_t major2, uint32_t minor2, uint32_t patch2)
{
    struct build_version v[2] = {{platform, pack(major, minor, patch)}, {platform2, pack(major2, minor2, patch2)}};
    return availability_version_check(2, v);
}

/* The older form, from before the platform was passed: always macOS. */
static int32_t is_os_version_at_least(int32_t major, int32_t minor, int32_t patch)
{
    return ferry_macos_version_packed() >= pack(major, minor, patch);
}

const struct ferry_symbol ferry_sysversion_symbols[] = {
    {"_availability_version_check", availability_version_check},
    {"__isPlatformVersionAtLeast", is_platform_version_at_least},
    {"__isPlatformOrVariantPlatformVersionAtLeast", is_platform_or_variant_at_least},
    {"__isOSVersionAtLeast", is_os_version_at_least},
    {NULL, NULL},
};
