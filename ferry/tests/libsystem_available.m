/* SPDX-License-Identifier: GPL-3.0-or-later
 * @available compiled the normal way (the compiler calls
 * __isPlatformVersionAtLeast, which Ferry's libSystem answers for macOS
 * 14.7), the older __isOSVersionAtLeast, and NSProcessInfo agreeing with
 * both and with sysctl. */
#import <Foundation/Foundation.h>
#include <sys/sysctl.h>

int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor);
int32_t __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t subminor);

static const char *yes(BOOL ok) { return ok ? "yes" : "NO"; }

static BOOL at_least(NSInteger major, NSInteger minor, NSInteger patch)
{
    NSOperatingSystemVersion v = {major, minor, patch};
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:v];
}

static void report(const char *what, BOOL available, NSInteger major, NSInteger minor, NSInteger patch)
{
    BOOL older = __isOSVersionAtLeast((int32_t)major, (int32_t)minor, (int32_t)patch) != 0;
    BOOL platform = __isPlatformVersionAtLeast(1, (uint32_t)major, (uint32_t)minor, (uint32_t)patch) != 0;
    printf("%-14s %s; __isOSVersionAtLeast agrees: %s, __isPlatformVersionAtLeast agrees: %s, NSProcessInfo agrees: %s\n",
           what, available ? "available" : "not available", yes(older == available), yes(platform == available),
           yes(at_least(major, minor, patch) == available));
}

static uint64_t number(const char *name)
{
    uint64_t v = 0;
    size_t len = sizeof v;
    sysctlbyname(name, &v, &len, NULL, 0);
    return len == 4 ? (uint32_t)v : v;
}

int main(void)
{
    @autoreleasepool {
        BOOL a;
        a = NO;
        if (@available(macOS 10.15, *))
            a = YES;
        report("macOS 10.15", a, 10, 15, 0);
        a = NO;
        if (@available(macOS 14, *))
            a = YES;
        report("macOS 14", a, 14, 0, 0);
        a = NO;
        if (@available(macOS 14.7, *))
            a = YES;
        report("macOS 14.7", a, 14, 7, 0);
        a = NO;
        if (@available(macOS 14.7.1, *))
            a = YES;
        report("macOS 14.7.1", a, 14, 7, 1);
        a = NO;
        if (@available(macOS 14.8, *))
            a = YES;
        report("macOS 14.8", a, 14, 8, 0);
        a = NO;
        if (@available(macOS 15, *))
            a = YES;
        report("macOS 15", a, 15, 0, 0);
        a = NO;
        if (__builtin_available(macOS 13.5, *))
            a = YES;
        report("macOS 13.5", a, 13, 5, 0);
        printf("an iOS version, asked of macOS: %s\n", __isPlatformVersionAtLeast(2, 1, 0, 0) ? "available" : "not available");

        NSProcessInfo *info = [NSProcessInfo processInfo];
        NSOperatingSystemVersion v = [info operatingSystemVersion];
        char product[32];
        size_t len = sizeof product;
        sysctlbyname("kern.osproductversion", product, &len, NULL, 0);
        NSString *joined = v.patchVersion ? [NSString stringWithFormat:@"%ld.%ld.%ld", (long)v.majorVersion,
                                                                       (long)v.minorVersion, (long)v.patchVersion]
                                          : [NSString stringWithFormat:@"%ld.%ld", (long)v.majorVersion,
                                                                       (long)v.minorVersion];
        printf("operatingSystemVersion is kern.osproductversion: %s\n", yes([joined isEqualToString:@(product)]));
        printf("processorCount is hw.ncpu: %s\n", yes([info processorCount] == number("hw.ncpu")));
        printf("activeProcessorCount is hw.activecpu: %s\n", yes([info activeProcessorCount] == number("hw.activecpu")));
        printf("physicalMemory is hw.memsize: %s\n", yes([info physicalMemory] == number("hw.memsize")));
    }
    return 0;
}
