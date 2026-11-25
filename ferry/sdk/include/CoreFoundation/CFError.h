/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CFError, written from Apple's public "CFError Reference". A
 * CFError is an NSError: the domains and keys are NSError's strings. Not
 * Apple's header. */
#ifndef _FERRY_CFERROR_H_
#define _FERRY_CFERROR_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
typedef CFStringRef CFErrorDomain;
extern const CFStringRef kCFErrorDomainPOSIX;
extern const CFStringRef kCFErrorDomainOSStatus;
extern const CFStringRef kCFErrorDomainMach;
extern const CFStringRef kCFErrorDomainCocoa;
extern const CFStringRef kCFErrorLocalizedDescriptionKey;
extern const CFStringRef kCFErrorLocalizedFailureReasonKey;
extern const CFStringRef kCFErrorLocalizedRecoverySuggestionKey;
extern const CFStringRef kCFErrorDescriptionKey;
extern const CFStringRef kCFErrorUnderlyingErrorKey;
extern const CFStringRef kCFErrorURLKey;
extern const CFStringRef kCFErrorFilePathKey;

CFTypeID CFErrorGetTypeID(void);
CFErrorRef CFErrorCreate(CFAllocatorRef allocator, CFErrorDomain domain, CFIndex code, CFDictionaryRef userInfo);
CFErrorRef CFErrorCreateWithUserInfoKeysAndValues(CFAllocatorRef allocator, CFErrorDomain domain, CFIndex code,
                                                  const void *const *userInfoKeys,
                                                  const void *const *userInfoValues, CFIndex numUserInfoValues);
CFErrorDomain CFErrorGetDomain(CFErrorRef err);
CFIndex CFErrorGetCode(CFErrorRef err);
CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef err);
CFStringRef CFErrorCopyDescription(CFErrorRef err);
CFStringRef CFErrorCopyFailureReason(CFErrorRef err);
CFStringRef CFErrorCopyRecoverySuggestion(CFErrorRef err);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
