/* SPDX-License-Identifier: GPL-3.0-or-later
 * CFError, written for freemac from Apple's public "CFError Reference": a
 * CFError is an NSError, toll-free as on a Mac, so the domains and keys are
 * NSError's own strings. */
#import "FInternal.h"
#include <CoreFoundation/CFError.h>

#define FERRY_TYPE_ERROR 0x4652001a

@implementation NSError (FerryCFError)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_ERROR; }
@end

const CFStringRef kCFErrorDomainPOSIX = (CFStringRef)@"NSPOSIXErrorDomain";
const CFStringRef kCFErrorDomainOSStatus = (CFStringRef)@"NSOSStatusErrorDomain";
const CFStringRef kCFErrorDomainMach = (CFStringRef)@"NSMachErrorDomain";
const CFStringRef kCFErrorDomainCocoa = (CFStringRef)@"NSCocoaErrorDomain";
const CFStringRef kCFErrorLocalizedDescriptionKey = (CFStringRef)@"NSLocalizedDescription";
const CFStringRef kCFErrorLocalizedFailureReasonKey = (CFStringRef)@"NSLocalizedFailureReason";
const CFStringRef kCFErrorLocalizedRecoverySuggestionKey = (CFStringRef)@"NSLocalizedRecoverySuggestion";
const CFStringRef kCFErrorDescriptionKey = (CFStringRef)@"NSDescription";
const CFStringRef kCFErrorUnderlyingErrorKey = (CFStringRef)@"NSUnderlyingError";
const CFStringRef kCFErrorURLKey = (CFStringRef)@"NSURL";
const CFStringRef kCFErrorFilePathKey = (CFStringRef)@"NSFilePath";

CFTypeID CFErrorGetTypeID(void) { return FERRY_TYPE_ERROR; }

CFErrorRef CFErrorCreate(CFAllocatorRef allocator, CFErrorDomain domain, CFIndex code, CFDictionaryRef userInfo)
{
    if (!domain)
        return NULL;
    return (CFErrorRef)[[NSError alloc] initWithDomain:(NSString *)domain code:code userInfo:(NSDictionary *)userInfo];
}

CFErrorRef CFErrorCreateWithUserInfoKeysAndValues(CFAllocatorRef allocator, CFErrorDomain domain, CFIndex code,
                                                  const void *const *keys, const void *const *values, CFIndex n)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)(n > 0 ? n : 0)];
    for (CFIndex i = 0; i < n; i++)
        if (keys[i] && values[i])
            [info setObject:(id)values[i] forKey:(id)keys[i]];
    return CFErrorCreate(allocator, domain, code, (CFDictionaryRef)info);
}

CFErrorDomain CFErrorGetDomain(CFErrorRef err) { return (CFStringRef)[(NSError *)err domain]; }
CFIndex CFErrorGetCode(CFErrorRef err) { return [(NSError *)err code]; }

CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef err)
{
    NSDictionary *info = [(NSError *)err userInfo];
    return (CFDictionaryRef)[(info ? info : [NSDictionary dictionary]) copy];
}

/* What a Mac answers: the localized description, else the description
 * key, else a sentence made of the domain and code. */
CFStringRef CFErrorCopyDescription(CFErrorRef err)
{
    NSError *e = (NSError *)err;
    NSString *s = [[e userInfo] objectForKey:(NSString *)kCFErrorLocalizedDescriptionKey];
    if (!s)
        s = [[e userInfo] objectForKey:(NSString *)kCFErrorDescriptionKey];
    if (!s)
        s = [e localizedDescription];
    return (CFStringRef)[s copy];
}

CFStringRef CFErrorCopyFailureReason(CFErrorRef err)
{
    return (CFStringRef)[[[(NSError *)err userInfo] objectForKey:(NSString *)kCFErrorLocalizedFailureReasonKey] copy];
}

CFStringRef CFErrorCopyRecoverySuggestion(CFErrorRef err)
{
    return (CFStringRef)[[[(NSError *)err userInfo] objectForKey:(NSString *)kCFErrorLocalizedRecoverySuggestionKey]
        copy];
}
