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
 * in kSMErrorDomainLaunchd saying so. Served from Foundation's file.
 * SMCopyAllJobDictionaries (freemac 1.230) lists the helpers turned on,
 * each as a job labelled with its identifier, as a Mac lists them. SMAppService
 * (freemac 1.230): the main app is a login item in the session's list (the
 * one LSSharedFileList keeps, so Dials > Login Items shows it), a login item
 * is a helper as above, and agents and daemons, being launchd jobs, are
 * never found. */
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
CFArrayRef SMCopyAllJobDictionaries(CFStringRef domain);
__FERRY_END

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#if defined(__has_attribute) && __has_attribute(swift_name)
#define _FERRY_SM_SWIFT(n) __attribute__((swift_name(n)))
#else
#define _FERRY_SM_SWIFT(n)
#endif

typedef NS_ENUM(NSInteger, SMAppServiceStatus) {
    SMAppServiceStatusNotRegistered = 0,
    SMAppServiceStatusEnabled = 1,
    SMAppServiceStatusRequiresApproval = 2,
    SMAppServiceStatusNotFound = 3,
} _FERRY_SM_SWIFT("SMAppService.Status");

FOUNDATION_EXPORT NSString *const SMAppServiceErrorDomain;

@interface SMAppService : NSObject
@property (class, readonly) SMAppService * FERRY_SWIFT_NONNULL mainAppService _FERRY_SM_SWIFT("mainApp");
+ (SMAppService * FERRY_SWIFT_NONNULL)loginItemServiceWithIdentifier:(NSString *)identifier
    _FERRY_SM_SWIFT("loginItem(identifier:)");
+ (SMAppService * FERRY_SWIFT_NONNULL)agentServiceWithPlistName:(NSString *)plistName _FERRY_SM_SWIFT("agent(plistName:)");
+ (SMAppService * FERRY_SWIFT_NONNULL)daemonServiceWithPlistName:(NSString *)plistName _FERRY_SM_SWIFT("daemon(plistName:)");
+ (SMAppServiceStatus)statusForLegacyURL:(NSURL *)url _FERRY_SM_SWIFT("statusForLegacyPlist(at:)");
+ (void)openSystemSettingsLoginItems;
@property (readonly) SMAppServiceStatus status;
- (BOOL)registerAndReturnError:(NSError **)error _FERRY_SM_SWIFT("register()");
- (BOOL)unregisterAndReturnError:(NSError **)error _FERRY_SM_SWIFT("unregister()");
@end
#endif
#endif
