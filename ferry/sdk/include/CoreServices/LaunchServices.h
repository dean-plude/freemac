/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Launch Services calls that look up and open applications,
 * written from Apple's public "Launch Services Reference". freemac keeps no
 * register of Mac applications, so the lookups by creator, bundle
 * identifier or URL scheme find none (kLSApplicationNotFoundErr, or NULL),
 * and setting a default handler is refused; LSOpenCFURLRef opens a URL or
 * file through the desktop's own launcher, as NSWorkspace does. Served from
 * Foundation's file, as CoreServices is. (The shared file lists, for login
 * items, are in LSSharedFileList.h.) */
#ifndef _FERRY_CORESERVICES_LAUNCHSERVICES_H_
#define _FERRY_CORESERVICES_LAUNCHSERVICES_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>

__FERRY_BEGIN
#ifndef _FERRY_PSN_DEFINED
#define _FERRY_PSN_DEFINED
typedef struct ProcessSerialNumber {
    UInt32 highLongOfPSN;
    UInt32 lowLongOfPSN;
} ProcessSerialNumber;
typedef ProcessSerialNumber *ProcessSerialNumberPtr;
enum { kNoProcess = 0, kSystemProcess = 1, kCurrentProcess = 2 };
#endif
typedef OptionBits LSRolesMask;
typedef OptionBits LSLaunchFlags;
enum {
    kLSRolesNone = 1, kLSRolesViewer = 2, kLSRolesEditor = 4, kLSRolesShell = 8, kLSRolesAll = (int)0xFFFFFFFF,
};
enum {
    kLSLaunchDefaults = 0x00000001, kLSLaunchAndPrint = 0x00000002, kLSLaunchAndDisplayErrors = 0x00000040,
    kLSLaunchDontAddToRecents = 0x00000100, kLSLaunchDontSwitch = 0x00000200, kLSLaunchAsync = 0x00010000,
    kLSLaunchNewInstance = 0x00080000, kLSLaunchAndHide = 0x00100000, kLSLaunchAndHideOthers = 0x00200000,
};
enum {
    kLSAppInTrashErr = -10660, kLSUnknownErr = -10810, kLSNotAnApplicationErr = -10811,
    kLSDataUnavailableErr = -10813, kLSApplicationNotFoundErr = -10814, kLSDataErr = -10817,
    kLSLaunchInProgressErr = -10818, kLSServerCommunicationErr = -10822, kLSCannotSetInfoErr = -10823,
    kLSNoExecutableErr = -10827, kLSNoLaunchPermissionErr = -10828,
};
enum { kLSUnknownType = 0, kLSUnknownCreator = 0 };
typedef struct LSApplicationParameters {
    CFIndex version;
    LSLaunchFlags flags;
    const FSRef *application;
    void *asyncLaunchRefCon;
    CFDictionaryRef environment;
    CFArrayRef argv;
    const void *initialEvent;
} LSApplicationParameters;
typedef struct LSLaunchURLSpec {
    CFURLRef appURL;
    CFArrayRef itemURLs;
    const void *passThruParams;
    LSLaunchFlags launchFlags;
    void *asyncRefCon;
} LSLaunchURLSpec;

OSStatus LSFindApplicationForInfo(OSType inCreator, CFStringRef inBundleID, CFStringRef inName, FSRef *outAppRef,
                                  CFURLRef *outAppURL);
OSStatus LSOpenApplication(const LSApplicationParameters *appParams, ProcessSerialNumber *outPSN);
OSStatus LSOpenCFURLRef(CFURLRef inURL, CFURLRef *outLaunchedURL);
OSStatus LSOpenFromURLSpec(const LSLaunchURLSpec *inLaunchSpec, CFURLRef *outLaunchedURL);
CFArrayRef LSCopyApplicationURLsForBundleIdentifier(CFStringRef inBundleIdentifier, CFErrorRef *outError)
    CF_RETURNS_RETAINED;
CFArrayRef LSCopyApplicationURLsForURL(CFURLRef inURL, LSRolesMask inRoleMask) CF_RETURNS_RETAINED;
CFURLRef LSCopyDefaultApplicationURLForURL(CFURLRef inURL, LSRolesMask inRoleMask, CFErrorRef *outError)
    CF_RETURNS_RETAINED;
CFStringRef LSCopyDefaultHandlerForURLScheme(CFStringRef inURLScheme) CF_RETURNS_RETAINED;
CFArrayRef LSCopyAllHandlersForURLScheme(CFStringRef inURLScheme) CF_RETURNS_RETAINED;
OSStatus LSSetDefaultHandlerForURLScheme(CFStringRef inURLScheme, CFStringRef inHandlerBundleID);
CFStringRef LSCopyDefaultRoleHandlerForContentType(CFStringRef inContentType, LSRolesMask inRole) CF_RETURNS_RETAINED;
OSStatus LSSetDefaultRoleHandlerForContentType(CFStringRef inContentType, LSRolesMask inRole,
                                               CFStringRef inHandlerBundleID);
OSStatus LSRegisterURL(CFURLRef inURL, Boolean inUpdate);
__FERRY_END
#endif
