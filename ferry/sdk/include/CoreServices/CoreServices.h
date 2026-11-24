/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the part of CoreServices Ferry provides, Gestalt's system
 * version selectors. Written for freemac from Apple's public documentation
 * of Gestalt; not Apple's header. Ferry serves CoreServices from
 * Foundation's file; Gestalt answers the same version as NSProcessInfo,
 * uname and /System/Library/CoreServices/SystemVersion.plist. */
#ifndef _FERRY_CORESERVICES_H_
#define _FERRY_CORESERVICES_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef int16_t OSErr;
typedef uint32_t OSType;
enum {
    gestaltSystemVersion = 'sysv',       /* 0xMMmb in binary-coded decimal; minor and bug fix at most 9 */
    gestaltSystemVersionMajor = 'sys1',
    gestaltSystemVersionMinor = 'sys2',
    gestaltSystemVersionBugFix = 'sys3',
};
enum { gestaltUndefSelectorErr = -5551 };
OSErr Gestalt(OSType selector, SInt32 *response);
__FERRY_END
#endif
