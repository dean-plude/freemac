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
enum { noErr = 0, fnfErr = -43, paramErr = -50, memFullErr = -108 };
OSErr Gestalt(OSType selector, SInt32 *response);
__FERRY_END
#include <CoreServices/LSSharedFileList.h>
#endif
