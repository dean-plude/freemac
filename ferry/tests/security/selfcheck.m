// SPDX-License-Identifier: GPL-3.0-or-later
// An app's check of its own signature, the way apps do it when they start,
// run from inside an app bundle: the running code is the bundle, a static
// code made for the bundle's path or for its executable passes, and the
// signing information carries the bundle's Info.plist but no identifier.
// Built without ARC.
#import <Foundation/Foundation.h>
#include <Security/Security.h>
#include <stdio.h>

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    SecCodeRef me = NULL;
    SecStaticCodeRef bundle = NULL, exe = NULL;
    SecRequirementRef req = NULL;
    CFURLRef path = NULL;
    SecCodeCopySelf(kSecCSDefaultFlags, &me);
    SecCodeCopyPath((SecStaticCodeRef)me, kSecCSDefaultFlags, &path);
    printf("running code: %s\n", [[(NSURL *)path lastPathComponent] UTF8String]);
    SecRequirementCreateWithString(CFSTR("identifier \"org.freemac.ferry.selfcheck\" and anchor apple generic"),
                                   kSecCSDefaultFlags, &req);
    NSURL *bundleURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    printf("bundle: %d, check %d\n", (int)SecStaticCodeCreateWithPath((CFURLRef)bundleURL, kSecCSDefaultFlags, &bundle),
           (int)SecStaticCodeCheckValidity(bundle, kSecCSCheckAllArchitectures | kSecCSStrictValidate, req));
    NSURL *exeURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] executablePath]];
    printf("executable: %d, check %d\n", (int)SecStaticCodeCreateWithPath((CFURLRef)exeURL, kSecCSDefaultFlags, &exe),
           (int)SecStaticCodeCheckValidity(exe, kSecCSDefaultFlags, NULL));
    printf("running code, checked: %d\n", (int)SecCodeCheckValidity(me, kSecCSDefaultFlags, req));
    CFDictionaryRef info = NULL;
    SecCodeCopySigningInformation(bundle, kSecCSSigningInformation, &info);
    NSDictionary *plist = [(NSDictionary *)info objectForKey:(id)kSecCodeInfoPList];
    printf("Info.plist: %s; main executable: %s; identifier: %s\n",
           [[plist objectForKey:@"CFBundleIdentifier"] UTF8String],
           [[(NSURL *)[(NSDictionary *)info objectForKey:(id)kSecCodeInfoMainExecutable] lastPathComponent] UTF8String],
           [(NSDictionary *)info objectForKey:(id)kSecCodeInfoIdentifier] ? "yes" : "(none)");
    CFRelease(info);
    CFRelease(me);
    CFRelease(bundle);
    CFRelease(exe);
    CFRelease(req);
    CFRelease(path);
    [pool drain];
    return 0;
}
