/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the corner of Icon Services that Cocoa apps call to hand a
 * file's icon to Launch Services (freemac 1.223, Ferry 0.47.0), written
 * from Apple's public documentation; not Apple's header. An icon reference
 * here names the file it was asked for; nothing draws it, and the calls
 * that take one (LSSharedFileListInsertItemURL) don't need it. Served from
 * Foundation's file (foundation/FSRefs.m), as the rest of CoreServices is. */
#ifndef _FERRY_CORESERVICES_ICONSCORE_H_
#define _FERRY_CORESERVICES_ICONSCORE_H_
#include <CoreServices/Files.h>
#include <CoreServices/LSSharedFileList.h>
__FERRY_BEGIN

typedef uint32_t IconServicesUsageFlags;
enum { kIconServicesNormalUsageFlag = 0x00000000, kIconServicesNoBadgeFlag = 0x00000001,
       kIconServicesUpdateIfNeededFlag = 0x00000002 };
#ifndef _FERRY_UNICHARCOUNT_
#define _FERRY_UNICHARCOUNT_
typedef unsigned long UniCharCount;
#endif

OSErr GetIconRefFromFileInfo(const FSRef *inRef, UniCharCount inFileNameLength, const UniChar *inFileName,
                             FSCatalogInfoBitmap inWhichInfo, const FSCatalogInfo *inCatalogInfo,
                             IconServicesUsageFlags inUsageFlags, IconRef *outIconRef, SInt16 *outLabel);
/* The system's own icons, by their four-letter types. GetIconRef answers a
 * reference naming the type, which PlotIconRefInContext draws with the
 * desktop's icon for it. */
enum { kOnSystemDisk = -32768, kOnAppropriateDisk = -32767 };
/* (the generic document, folder, disk and alert types are in CoreServices.h) */
enum {
    kSystemIconsCreator = 'macs',
    kGenericFloppyIcon = 'flpy',
    kGenericCDROMIcon = 'cddr',
    kGenericRemovableMediaIcon = 'rmov',
    kGenericURLIcon = 'gurl',
    kComputerIcon = 'root',
    kDesktopIcon = 'desk',
    kFullTrashIcon = 'ftrh',
    kQuestionMarkIcon = 'ques',
    kToolbarHomeIcon = 'tbhm',
    kToolbarDesktopFolderIcon = 'tbds'
};
OSErr GetIconRef(SInt16 vRefNum, OSType creator, OSType iconType, IconRef *theIconRef);
OSErr AcquireIconRef(IconRef theIconRef);
OSErr ReleaseIconRef(IconRef theIconRef);

__FERRY_END
#endif
