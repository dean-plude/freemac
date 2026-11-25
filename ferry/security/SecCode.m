/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: code signing. Our own code, written from
 * Apple's public API documentation of Security (SecCode.h,
 * SecStaticCode.h, SecRequirement.h, CSCommon.h and the "Code Signing
 * Services" reference).
 *
 * Ferry can't check a Mac code signature: that needs Apple's certificate
 * authorities and the Mac's own trust decisions, and Ferry reads none of a
 * program's signature. So it gives one plain, documented answer, the same
 * every time:
 *
 * - every piece of code reads as unsigned: its signing information has no
 *   identifier, team or certificates (only kSecCodeInfoMainExecutable and,
 *   for a bundle, kSecCodeInfoPList), and SecCodeCopyDesignatedRequirement
 *   and every validity check answer errSecCSUnsigned;
 * - except one case: a validity check of the running program's own code
 *   (SecCodeCopySelf, its static code, or a static code made for the main
 *   bundle's or the main executable's path), with or without a
 *   requirement, answers errSecSuccess.
 *
 * Many apps check their own signature when they start and stop if it fails.
 * That check only guards the bundle the user already chose to run, so it is
 * allowed to go on; a program asking about any other code is told plainly
 * that Ferry found no signature, rather than told a signature is good.
 * With FERRY_VERBOSE set, each of these answers is said once on stderr. */
#include "SInternal.h"

#include <stdlib.h>
#include <unistd.h>

#define K(name, value) S_EXPORT const CFStringRef name = (CFStringRef)@value;
K(kSecCodeInfoCertificates, "kSecCodeInfoCertificates")
K(kSecCodeInfoChangedFiles, "kSecCodeInfoChangedFiles")
K(kSecCodeInfoCMS, "kSecCodeInfoCMS")
K(kSecCodeInfoDesignatedRequirement, "kSecCodeInfoDesignatedRequirement")
K(kSecCodeInfoEntitlements, "kSecCodeInfoEntitlements")
K(kSecCodeInfoEntitlementsDict, "kSecCodeInfoEntitlementsDict")
K(kSecCodeInfoFlags, "kSecCodeInfoFlags")
K(kSecCodeInfoFormat, "kSecCodeInfoFormat")
K(kSecCodeInfoDigestAlgorithm, "kSecCodeInfoDigestAlgorithm")
K(kSecCodeInfoIdentifier, "kSecCodeInfoIdentifier")
K(kSecCodeInfoImplicitDesignatedRequirement, "kSecCodeInfoImplicitDesignatedRequirement")
K(kSecCodeInfoMainExecutable, "kSecCodeInfoMainExecutable")
K(kSecCodeInfoPList, "kSecCodeInfoPList")
K(kSecCodeInfoRequirements, "kSecCodeInfoRequirements")
K(kSecCodeInfoRequirementData, "kSecCodeInfoRequirementData")
K(kSecCodeInfoSource, "kSecCodeInfoSource")
K(kSecCodeInfoStatus, "kSecCodeInfoStatus")
K(kSecCodeInfoTeamIdentifier, "kSecCodeInfoTeamIdentifier")
K(kSecCodeInfoTime, "kSecCodeInfoTime")
K(kSecCodeInfoTimestamp, "kSecCodeInfoTimestamp")
K(kSecCodeInfoTrust, "kSecCodeInfoTrust")
K(kSecCodeInfoUnique, "kSecCodeInfoUnique")
K(kSecGuestAttributePid, "kSecGuestAttributePid")
#undef K

static NSString *canonical(NSString *path)
{
    char buf[1024]; /* PATH_MAX on a Mac */
    if (!path)
        return nil;
    const char *real = realpath([path fileSystemRepresentation], buf);
    return real ? [NSString stringWithUTF8String:real] : [path stringByStandardizingPath];
}

/* The running program's code: its app bundle, or its executable when it has none. */
static NSString *own_path(void)
{
    NSBundle *b = [NSBundle mainBundle];
    NSString *exe = canonical([b executablePath]), *bundle = canonical([b bundlePath]);
    if (bundle && exe && ![bundle isEqual:[exe stringByDeletingLastPathComponent]])
        return bundle;
    return exe;
}

static BOOL is_own(NSString *path)
{
    NSString *p = canonical(path);
    return p && ([p isEqual:own_path()] || [p isEqual:canonical([[NSBundle mainBundle] executablePath])]);
}

@implementation SCode
- (void)dealloc
{
    [path release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[SCode class]] && ((SCode *)other)->dynamic == dynamic &&
           [((SCode *)other)->path isEqual:path];
}
- (NSUInteger)hash { return [path hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p %@>", dynamic ? @"SecCode" : @"SecStaticCode", self, path];
}
@end

@implementation SRequirement
- (void)dealloc
{
    [text release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[SRequirement class]] && [((SRequirement *)other)->text isEqual:text]; }
- (NSUInteger)hash { return [text hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"<SecRequirement %p %@>", self, text]; }
@end

static SCode *new_code(NSString *path, BOOL dynamic)
{
    SCode *c = [[SCode alloc] init];
    c->path = [path copy];
    c->dynamic = dynamic;
    c->isSelf = is_own(path);
    return c;
}

static OSStatus with_errors(OSStatus status, CFErrorRef *errors)
{
    if (errors)
        *errors = status == errSecSuccess ? NULL : (CFErrorRef)SCopyError(status, nil);
    return status;
}

S_EXPORT OSStatus SecCodeCopySelf(SecCSFlags flags, SecCodeRef *self)
{
    if (!self)
        return errSecCSObjectRequired;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *path = own_path();
    *self = path ? (SecCodeRef)new_code(path, YES) : NULL;
    [pool drain];
    return *self ? errSecSuccess : errSecCSNoSuchCode;
}

S_EXPORT OSStatus SecCodeCopyStaticCode(SecCodeRef code, SecCSFlags flags, SecStaticCodeRef *staticCode)
{
    SCode *c = (SCode *)code;
    if (!staticCode || !c)
        return errSecCSObjectRequired;
    if (![c isKindOfClass:[SCode class]])
        return errSecCSInvalidObjectRef;
    *staticCode = (SecStaticCodeRef)new_code(c->path, NO);
    return errSecSuccess;
}

/* Only the running program is a guest Ferry knows: by its process id. */
S_EXPORT OSStatus SecCodeCopyGuestWithAttributes(SecCodeRef host, CFDictionaryRef attributes, SecCSFlags flags,
                                                 SecCodeRef *guest)
{
    if (!guest)
        return errSecCSObjectRequired;
    *guest = NULL;
    id pid = [(NSDictionary *)attributes objectForKey:(id)kSecGuestAttributePid];
    if (![pid isKindOfClass:[NSNumber class]])
        return errSecCSUnsupportedGuestAttributes;
    if ([pid intValue] != getpid())
        return errSecCSNoSuchCode;
    return SecCodeCopySelf(flags, guest);
}

S_EXPORT OSStatus SecCodeCopyPath(SecStaticCodeRef staticCode, SecCSFlags flags, CFURLRef *path)
{
    SCode *c = (SCode *)staticCode;
    if (!path || !c)
        return errSecCSObjectRequired;
    if (![c isKindOfClass:[SCode class]])
        return errSecCSInvalidObjectRef;
    *path = (CFURLRef)[[NSURL alloc] initFileURLWithPath:c->path];
    return errSecSuccess;
}

S_EXPORT OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode)
{
    NSURL *url = (NSURL *)path;
    if (!staticCode || !url)
        return errSecCSObjectRequired;
    *staticCode = NULL;
    if (![url isKindOfClass:[NSURL class]] || ![url isFileURL])
        return errSecParam;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *p = [url path];
    OSStatus status = errSecCSStaticCodeNotFound;
    if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
        *staticCode = (SecStaticCodeRef)new_code(canonical(p), NO);
        status = errSecSuccess;
    }
    [pool drain];
    return status;
}

S_EXPORT OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes,
                                                           SecStaticCodeRef *staticCode)
{
    return SecStaticCodeCreateWithPath(path, flags, staticCode);
}

static OSStatus check(id code, id requirement)
{
    if (!code)
        return errSecCSObjectRequired;
    if (![code isKindOfClass:[SCode class]] || (requirement && ![requirement isKindOfClass:[SRequirement class]]))
        return errSecCSInvalidObjectRef;
    if (((SCode *)code)->isSelf) {
        SVerboseOnce(@"the program's check of its own code signature passes; Ferry can't check Mac signatures, "
                     @"and lets a program's check of itself go on (every other code reads as unsigned)");
        return errSecSuccess;
    }
    SVerboseOnce(@"code other than the running program reads as unsigned (errSecCSUnsigned); Ferry can't check "
                 @"Mac signatures");
    return errSecCSUnsigned;
}

S_EXPORT OSStatus SecCodeCheckValidity(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement)
{
    return check((id)code, (id)requirement);
}

S_EXPORT OSStatus SecCodeCheckValidityWithErrors(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement,
                                                 CFErrorRef *errors)
{
    return with_errors(check((id)code, (id)requirement), errors);
}

S_EXPORT OSStatus SecStaticCodeCheckValidity(SecStaticCodeRef staticCode, SecCSFlags flags,
                                             SecRequirementRef requirement)
{
    return check((id)staticCode, (id)requirement);
}

S_EXPORT OSStatus SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef staticCode, SecCSFlags flags,
                                                       SecRequirementRef requirement, CFErrorRef *errors)
{
    return with_errors(check((id)staticCode, (id)requirement), errors);
}

/* What a Mac says of unsigned code: where its executable is, and its Info.plist. */
S_EXPORT OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *information)
{
    SCode *c = (SCode *)code;
    if (!information || !c)
        return errSecCSObjectRequired;
    *information = NULL;
    if (![c isKindOfClass:[SCode class]])
        return errSecCSInvalidObjectRef;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:c->path isDirectory:&isDir];
    NSString *exe = c->path;
    if (isDir) {
        NSBundle *b = c->isSelf ? [NSBundle mainBundle] : [NSBundle bundleWithPath:c->path];
        exe = [b executablePath];
        NSDictionary *plist = [b infoDictionary];
        if ([plist count])
            [info setObject:plist forKey:(id)kSecCodeInfoPList];
    }
    if (exe)
        [info setObject:[NSURL fileURLWithPath:exe] forKey:(id)kSecCodeInfoMainExecutable];
    *information = (CFDictionaryRef)info;
    [pool drain];
    return errSecSuccess;
}

S_EXPORT OSStatus SecCodeCopyDesignatedRequirement(SecStaticCodeRef code, SecCSFlags flags,
                                                   SecRequirementRef *requirement)
{
    if (!requirement || !code)
        return errSecCSObjectRequired;
    *requirement = NULL;
    return [(id)code isKindOfClass:[SCode class]] ? errSecCSUnsigned : errSecCSInvalidObjectRef;
}

/* Kept as text. Only its shape is checked (something written, quotes
 * closed, brackets balanced); a check against it always goes by the rule above. */
static OSStatus make_requirement(NSString *text, SecRequirementRef *requirement)
{
    if (!requirement)
        return errSecCSObjectRequired;
    *requirement = NULL;
    if (![text isKindOfClass:[NSString class]])
        return errSecParam;
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    const char *s = [t UTF8String];
    int depth = 0;
    BOOL quoted = NO;
    for (; *s; s++) {
        if (quoted) {
            if (*s == '\\' && s[1])
                s++;
            else if (*s == '"')
                quoted = NO;
        } else if (*s == '"') {
            quoted = YES;
        } else if (*s == '(') {
            depth++;
        } else if (*s == ')' && --depth < 0) {
            break;
        }
    }
    if (![t length] || quoted || depth)
        return errSecCSReqInvalid;
    SRequirement *r = [[SRequirement alloc] init];
    r->text = [t copy];
    *requirement = (SecRequirementRef)r;
    return errSecSuccess;
}

S_EXPORT OSStatus SecRequirementCreateWithString(CFStringRef text, SecCSFlags flags, SecRequirementRef *requirement)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OSStatus status = make_requirement((NSString *)text, requirement);
    [pool drain];
    return status;
}

S_EXPORT OSStatus SecRequirementCreateWithStringAndErrors(CFStringRef text, SecCSFlags flags, CFErrorRef *errors,
                                                          SecRequirementRef *requirement)
{
    return with_errors(SecRequirementCreateWithString(text, flags, requirement), errors);
}

S_EXPORT OSStatus SecRequirementCopyString(SecRequirementRef requirement, SecCSFlags flags, CFStringRef *text)
{
    SRequirement *r = (SRequirement *)requirement;
    if (!text || !r)
        return errSecCSObjectRequired;
    if (![r isKindOfClass:[SRequirement class]])
        return errSecCSInvalidObjectRef;
    *text = (CFStringRef)[r->text copy];
    return errSecSuccess;
}

/* ---- tasks (SecTask.h) ----------------------------------------------------------------
 * The running program as a task. It has no entitlements and no signing
 * identifier, since Ferry reads no signature (see the top of this file). */
#define FERRY_TYPE_SECTASK 0x46520040
@interface STask : NSObject
@end
@implementation STask
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECTASK; }
@end

S_EXPORT CFTypeID SecTaskGetTypeID(void) { return FERRY_TYPE_SECTASK; }

S_EXPORT SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator)
{
    return (SecTaskRef)[[STask alloc] init];
}

S_EXPORT CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    if (task && entitlement)
        SVerboseOnce([NSString stringWithFormat:@"the program has no entitlement %@ (Ferry reads no signature)",
                                                (NSString *)entitlement]);
    return NULL;
}

S_EXPORT CFDictionaryRef SecTaskCopyValuesForEntitlements(SecTaskRef task, CFArrayRef entitlements, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    return task ? (CFDictionaryRef)[[NSDictionary alloc] init] : NULL;
}

S_EXPORT CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    return NULL;
}
