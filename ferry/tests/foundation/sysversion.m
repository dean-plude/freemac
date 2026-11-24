// SPDX-License-Identifier: GPL-3.0-or-later
// The macOS version Ferry presents, read every way an app reads it: the
// Mac's version file (as a property list, with C stdio and with open and
// stat), uname's Darwin release, NSProcessInfo and Gestalt. They must all
// agree. Built without ARC.
#import <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#define PLIST "/System/Library/CoreServices/SystemVersion.plist"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@PLIST];
    printf("plist: %s %s (%s), user-visible %s\n", [[d objectForKey:@"ProductName"] UTF8String],
           [[d objectForKey:@"ProductVersion"] UTF8String], [[d objectForKey:@"ProductBuildVersion"] UTF8String],
           [[d objectForKey:@"ProductUserVisibleVersion"] UTF8String]);

    // the same bytes through stdio, open and stat; written to, never
    FILE *f = fopen("//System/Library/CoreServices//SystemVersion.plist", "r");
    char buf[4096];
    size_t n = f ? fread(buf, 1, sizeof buf, f) : 0;
    if (f)
        fclose(f);
    struct stat st;
    int s = stat(PLIST, &st);
    printf("stdio read %zu bytes; stat %d: size %lld, regular %d, mode %o\n", n, s, (long long)st.st_size,
           S_ISREG(st.st_mode), (unsigned)(st.st_mode & 0777));
    printf("same as the property list's file: %s\n",
           n == (size_t)st.st_size && [[NSData dataWithBytes:buf length:n]
                                          isEqual:[NSData dataWithContentsOfFile:@PLIST]] ? "yes" : "no");
    int fd = open(PLIST, O_RDONLY);
    char first[6] = {0};
    printf("open: %s, reads \"%s\"\n", fd >= 0 ? "yes" : "no", fd >= 0 && read(fd, first, 5) == 5 ? first : "");
    if (fd >= 0)
        close(fd);
    errno = 0;
    fd = open(PLIST, O_WRONLY);
    printf("open for writing: %d, %s\n", fd, errno == EACCES ? "EACCES" : strerror(errno));
    printf("writable: %d, readable: %d\n", access(PLIST, W_OK), access(PLIST, R_OK));

    struct utsname u;
    uname(&u);
    printf("uname: %s %s\n", u.sysname, u.release);

    NSProcessInfo *p = [NSProcessInfo processInfo];
    NSOperatingSystemVersion v = p.operatingSystemVersion;
    printf("NSProcessInfo: %ld.%ld.%ld, \"%s\"\n", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion,
           [p.operatingSystemVersionString UTF8String]);
    NSOperatingSystemVersion v11 = {11, 0, 0}, v14 = {14, 7, 0}, v147 = {14, 7, 1}, v15 = {15, 0, 0};
    printf("at least 11.0 %d, 14.7 %d, 14.7.1 %d, 15.0 %d\n", [p isOperatingSystemAtLeastVersion:v11],
           [p isOperatingSystemAtLeastVersion:v14], [p isOperatingSystemAtLeastVersion:v147],
           [p isOperatingSystemAtLeastVersion:v15]);

    SInt32 major = 0, minor = 0, fix = 0, bcd = 0, other = 7;
    OSErr e1 = Gestalt(gestaltSystemVersionMajor, &major), e2 = Gestalt(gestaltSystemVersionMinor, &minor),
          e3 = Gestalt(gestaltSystemVersionBugFix, &fix), e4 = Gestalt(gestaltSystemVersion, &bcd),
          e5 = Gestalt('zzzz', &other);
    printf("Gestalt: %d.%d.%d (%d %d %d), sysv 0x%04x (%d), unknown selector %d, left %d\n", (int)major, (int)minor,
           (int)fix, e1, e2, e3, (unsigned)bcd, e4, e5, (int)other);

    NSString *joined = [NSString stringWithFormat:@"%ld.%ld", (long)v.majorVersion, (long)v.minorVersion];
    if (v.patchVersion)
        joined = [joined stringByAppendingFormat:@".%ld", (long)v.patchVersion];
    printf("all agree: %s\n", [joined isEqual:[d objectForKey:@"ProductVersion"]] && major == v.majorVersion &&
                                      minor == v.minorVersion && fix == v.patchVersion &&
                                      atoi(u.release) == v.majorVersion + 9
                                  ? "yes"
                                  : "no");
    [pool drain];
    return 0;
}
