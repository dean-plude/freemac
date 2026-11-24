// SPDX-License-Identifier: GPL-3.0-or-later
// Code signing as Ferry answers it: the running program's check of its own
// code passes, with or without a requirement; any other code reads as
// unsigned; signing information is a plain dictionary with no identifier,
// team or certificates; requirements are kept as text. Built without ARC.
#import <Foundation/Foundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *keys(CFDictionaryRef info)
{
    NSArray *k = [[(NSDictionary *)info allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *names = [NSMutableArray array];
    for (id key in k) {
        if ([key isEqual:(id)kSecCodeInfoMainExecutable])
            [names addObject:@"main executable"];
        else if ([key isEqual:(id)kSecCodeInfoPList])
            [names addObject:@"Info.plist"];
        else
            [names addObject:@"other"];
    }
    return [[names componentsJoinedByString:@", "] UTF8String];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    SecCodeRef me = NULL, again = NULL, guest = NULL;
    SecStaticCodeRef mine = NULL, byPath = NULL, sh = NULL, missing = NULL;
    SecRequirementRef req = NULL, bad = NULL;

    printf("the program's own code\n");
    printf("  copy self: %d\n", (int)SecCodeCopySelf(kSecCSDefaultFlags, &me));
    printf("  check: %d\n", (int)SecCodeCheckValidity(me, kSecCSDefaultFlags, NULL));
    OSStatus s = SecRequirementCreateWithString(
        CFSTR("anchor apple generic and identifier \"org.example.app\" and certificate leaf[subject.OU] = \"ABCDE12345\""),
        kSecCSDefaultFlags, &req);
    printf("  a requirement: %d\n", (int)s);
    printf("  check against it: %d\n", (int)SecCodeCheckValidity(me, kSecCSDefaultFlags, req));
    printf("  static code: %d\n", (int)SecCodeCopyStaticCode(me, kSecCSDefaultFlags, &mine));
    printf("  check it: %d, strictly against the requirement %d\n",
           (int)SecStaticCodeCheckValidity(mine, kSecCSDefaultFlags, NULL),
           (int)SecStaticCodeCheckValidity(mine, kSecCSStrictValidate | kSecCSCheckAllArchitectures, req));
    CFURLRef url = NULL;
    printf("  path: %d, %s\n", (int)SecCodeCopyPath(mine, kSecCSDefaultFlags, &url),
           [[(NSURL *)url lastPathComponent] UTF8String]);
    char a[1024], b[1024];
    printf("  same as the executable: %s\n",
           realpath([[(NSURL *)url path] fileSystemRepresentation], a) &&
                   realpath([[[NSBundle mainBundle] executablePath] fileSystemRepresentation], b) && !strcmp(a, b)
               ? "yes"
               : "no");
    printf("  static code from that path: %d, check %d\n",
           (int)SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &byPath),
           (int)SecStaticCodeCheckValidity(byPath, kSecCSDefaultFlags, req));
    CFDictionaryRef info = NULL;
    s = SecCodeCopySigningInformation(mine, kSecCSSigningInformation | kSecCSRequirementInformation, &info);
    printf("  signing information: %d, %s\n", (int)s, keys(info));
    printf("  identifier %s, team %s, certificates %s\n",
           CFDictionaryGetValue(info, kSecCodeInfoIdentifier) ? "yes" : "(none)",
           CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) ? "yes" : "(none)",
           CFDictionaryGetValue(info, kSecCodeInfoCertificates) ? "yes" : "(none)");
    printf("  main executable: %s\n",
           [[(NSURL *)CFDictionaryGetValue(info, kSecCodeInfoMainExecutable) lastPathComponent] UTF8String]);
    SecRequirementRef dr = (SecRequirementRef)1;
    printf("  designated requirement: %d, %s\n", (int)SecCodeCopyDesignatedRequirement(mine, kSecCSDefaultFlags, &dr),
           dr ? "one" : "none");
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:getpid()]
                                                      forKey:(id)kSecGuestAttributePid];
    printf("  guest by pid: %d, the same code %d\n",
           (int)SecCodeCopyGuestWithAttributes(NULL, (CFDictionaryRef)attrs, kSecCSDefaultFlags, &guest),
           guest && CFEqual(guest, me));
    SecCodeCopySelf(kSecCSDefaultFlags, &again);
    printf("  self twice: equal %d\n", CFEqual(me, again));
    attrs = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:1] forKey:(id)kSecGuestAttributePid];
    SecCodeRef other = NULL;
    printf("  another process: %d\n",
           (int)SecCodeCopyGuestWithAttributes(NULL, (CFDictionaryRef)attrs, kSecCSDefaultFlags, &other));

    printf("other code\n");
    NSURL *shURL = [NSURL fileURLWithPath:@"/bin/sh"];
    printf("  /bin/sh: %d\n", (int)SecStaticCodeCreateWithPath((CFURLRef)shURL, kSecCSDefaultFlags, &sh));
    printf("  check: %d, against the requirement %d\n", (int)SecStaticCodeCheckValidity(sh, kSecCSDefaultFlags, NULL),
           (int)SecStaticCodeCheckValidity(sh, kSecCSDefaultFlags, req));
    CFErrorRef error = NULL;
    s = SecStaticCodeCheckValidityWithErrors(sh, kSecCSDefaultFlags, NULL, &error);
    printf("  with errors: %d, an error in %s, code %ld\n", (int)s,
           [[(NSError *)error domain] isEqual:NSOSStatusErrorDomain] ? "NSOSStatusErrorDomain" : "?",
           (long)[(NSError *)error code]);
    if (error)
        CFRelease(error);
    CFDictionaryRef shInfo = NULL;
    SecCodeCopySigningInformation(sh, kSecCSSigningInformation, &shInfo);
    printf("  signing information: %s\n", keys(shInfo));
    printf("  designated requirement: %d\n", (int)SecCodeCopyDesignatedRequirement(sh, kSecCSDefaultFlags, &dr));
    NSURL *gone = [NSURL fileURLWithPath:@"/nonexistent/Example.app"];
    printf("  a path with nothing there: %d\n",
           (int)SecStaticCodeCreateWithPath((CFURLRef)gone, kSecCSDefaultFlags, &missing));
    printf("  no code: %d\n", (int)SecStaticCodeCheckValidity(NULL, kSecCSDefaultFlags, NULL));

    printf("requirements\n");
    CFStringRef text = NULL;
    printf("  as text: %d, %s\n", (int)SecRequirementCopyString(req, kSecCSDefaultFlags, &text),
           [(NSString *)text UTF8String]);
    const char *wrong[] = {"", "identifier \"org.example", "(anchor apple", "anchor apple)"};
    for (int i = 0; i < 4; i++) {
        error = NULL;
        s = SecRequirementCreateWithStringAndErrors((CFStringRef)[NSString stringWithUTF8String:wrong[i]],
                                                    kSecCSDefaultFlags, &error, &bad);
        printf("  \"%s\": %d, an error %d\n", wrong[i], (int)s, error != NULL);
        if (error)
            CFRelease(error);
    }

    CFStringRef m = SecCopyErrorMessageString(errSecCSUnsigned, NULL);
    printf("errSecCSUnsigned: %s\n", [(NSString *)m UTF8String]);
    CFRelease(m);
    CFRelease(me);
    CFRelease(again);
    CFRelease(guest);
    CFRelease(mine);
    CFRelease(byPath);
    CFRelease(sh);
    CFRelease(req);
    CFRelease(url);
    CFRelease(info);
    CFRelease(shInfo);
    CFRelease(text);
    [pool drain];
    return 0;
}
