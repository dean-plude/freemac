/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the part of CoreServices Ferry provides, Gestalt's system
 * version selectors and (freemac 1.219, Ferry 0.43.0) the shared file lists
 * that keep login items, in LSSharedFileList.h. Written for freemac from Apple's public documentation
 * of Gestalt; not Apple's header. Ferry serves CoreServices from
 * Foundation's file; Gestalt answers the same version as NSProcessInfo,
 * uname and /System/Library/CoreServices/SystemVersion.plist. */
#ifndef _FERRY_CORESERVICES_H_
#define _FERRY_CORESERVICES_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CFNetwork/CFNetwork.h>

/* MacTypes.h makes nil a null pointer for C too, through CoreServices
 * (VLC's audio output passes it for a char *), as objc.h does (freemac
 * 1.237, VLC). */
#ifndef nil
#if defined(__cplusplus) && __cplusplus >= 201103L
#define nil nullptr
#elif defined(__cplusplus)
#define nil __null
#else
#define nil ((void *)0)
#endif
#endif
__FERRY_BEGIN
typedef int16_t OSErr;
typedef int32_t OSStatus;
typedef uint32_t OSType;
enum {
    gestaltSystemVersion = 'sysv',       /* 0xMMmb in binary-coded decimal; minor and bug fix at most 9 */
    gestaltSystemVersionMajor = 'sys1',
    gestaltSystemVersionMinor = 'sys2',
    gestaltSystemVersionBugFix = 'sys3',
};
enum { gestaltUndefSelectorErr = -5551 };
/* The Carbon-era result codes Launch Services answers with (MacErrors.h). */
/* noErr is MacTypes.h's, as on a Mac (freemac 1.234) */
enum { fnfErr = -43, paramErr = -50, memFullErr = -108, userCanceledErr = -128 };
/* freemac 1.226, Ferry 0.50.0: "not implemented", which Sequel Pro answers with */
enum { unimpErr = -4 };
/* Generic icons from IconsCore (freemac 1.226, Ferry 0.50.0): their type
 * codes, which NSFileTypeForHFSTypeCode makes a file type of. */
enum {
    kGenericDocumentIcon = 'docu',
    kGenericApplicationIcon = 'APPL',
    kGenericFolderIcon = 'fldr',
    kGenericHardDiskIcon = 'hdsk',
    kGenericNetworkIcon = 'gnet',
    kTrashIcon = 'trsh',
    /* the alert icons (freemac 1.233, VLC) */
    kAlertStopIcon = 'stop',
    kAlertNoteIcon = 'note',
    kAlertCautionIcon = 'caut',
};
enum { coreFoundationUnknownErr = -4960 };
/* the reference constants callbacks are given back (MacTypes.h) */
typedef void *SRefCon;
typedef void *URefCon;
OSErr Gestalt(OSType selector, SInt32 *response);
/* A result code's name and a few words on it, as CarbonCore's Debugging.h
 * gives them (freemac 1.NEXT); "" for a code Ferry doesn't know. */
const char *GetMacOSStatusErrorString(OSStatus err);
const char *GetMacOSStatusCommentString(OSStatus err);
__FERRY_END
#include <CoreServices/LSSharedFileList.h>
/* File references and the trash (freemac 1.221, Ferry 0.45.0). */
#include <CoreServices/Files.h>
/* Folders' changes (freemac 1.222, Ferry 0.46.0). */
#include <CoreServices/FSEvents.h>
/* Apple events' descriptors and Launch Services' application lookups. */
#include <CoreServices/AppleEvents.h>
#include <CoreServices/LaunchServices.h>
/* Uniform type identifiers and icon references (freemac 1.223, Ferry 0.47.0). */
#include <CoreServices/UTType.h>
/* The Carbon clock calls (freemac 1.226, Ferry 0.50.0). */
#include <CoreServices/DriverServices.h>
#include <CoreServices/IconsCore.h>
/* key codes into characters (freemac 1.230) */
#include <CoreServices/UnicodeUtilities.h>
/* text encodings and their converter, and a locale's name in parts (freemac 1.NEXT, Vim) */
#include <CoreServices/TextEncodingConverter.h>
/* On a Mac CoreServices brings in the POSIX calls (usleep and the like),
 * and Cocoa programs rely on it; its file calls bring in open and its
 * flags (freemac 1.223, Ferry 0.47.0). */
#include <unistd.h>
#include <sys/fcntl.h>
#endif
