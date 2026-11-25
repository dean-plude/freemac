/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ServiceManagement's login-item call (freemac 1.219, Ferry
 * 0.43.0). Written for freemac from Apple's public documentation of
 * SMLoginItemSetEnabled; not Apple's header. The helper is the app in the
 * main bundle's Contents/Library/LoginItems whose CFBundleIdentifier is the
 * one given; turning it on writes a freedesktop autostart entry,
 * $XDG_CONFIG_HOME/autostart/ferry-login-IDENTIFIER.desktop, that runs
 * "ferry HELPER.app", and turning it off removes that entry. Launchd jobs
 * (freemac 1.224, Ferry 0.48.0): there is no launchd here, so a job is
 * never found, submitted or blessed; each call answers false with an error
 * in kSMErrorDomainLaunchd saying so. Served from Foundation's file. */
#ifndef _FERRY_SERVICEMANAGEMENT_H_
#define _FERRY_SERVICEMANAGEMENT_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
Boolean SMLoginItemSetEnabled(CFStringRef identifier, Boolean enabled);

extern const CFStringRef kSMDomainSystemLaunchd;
extern const CFStringRef kSMDomainUserLaunchd;
extern const CFStringRef kSMErrorDomainIPC;
extern const CFStringRef kSMErrorDomainFramework;
extern const CFStringRef kSMErrorDomainLaunchd;
enum {
    kSMErrorInternalFailure = 2, kSMErrorInvalidSignature = 3, kSMErrorAuthorizationFailure = 4,
    kSMErrorToolNotValid = 5, kSMErrorJobNotFound = 6, kSMErrorServiceUnavailable = 7,
    kSMErrorJobPlistNotFound = 8, kSMErrorJobMustBeEnabled = 9, kSMErrorInvalidPlist = 10,
};
#ifndef _FERRY_AUTHORIZATIONREF_
#define _FERRY_AUTHORIZATIONREF_
typedef const struct AuthorizationOpaqueRef *AuthorizationRef;
#endif
Boolean SMJobSubmit(CFStringRef domain, CFDictionaryRef job, AuthorizationRef auth, CFErrorRef *outError);
Boolean SMJobRemove(CFStringRef domain, CFStringRef jobLabel, AuthorizationRef auth, Boolean wait,
                    CFErrorRef *outError);
Boolean SMJobBless(CFStringRef domain, CFStringRef executableLabel, AuthorizationRef auth, CFErrorRef *outError);
CFDictionaryRef SMJobCopyDictionary(CFStringRef domain, CFStringRef jobLabel);
__FERRY_END
#endif
