/* SPDX-License-Identifier: GPL-3.0-or-later
 * Disk Arbitration's sessions and disks, from Apple's public documentation.
 * Ferry gives no disk descriptions: DADiskCreateFromBSDName and
 * DADiskCreateFromVolumePath answer NULL, and callbacks registered with a
 * session are never called, as on a Mac with no disks to report. */
#ifndef FERRY_DISKARBITRATION_H
#define FERRY_DISKARBITRATION_H
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

typedef struct __DASession *DASessionRef;
typedef struct __DADisk *DADiskRef;
typedef struct __DADissenter *DADissenterRef;
typedef void (*DADiskAppearedCallback)(DADiskRef disk, void *context);
typedef void (*DADiskDisappearedCallback)(DADiskRef disk, void *context);
typedef void (*DADiskDescriptionChangedCallback)(DADiskRef disk, CFArrayRef keys, void *context);

extern const CFStringRef kDADiskDescriptionVolumeNameKey;
extern const CFStringRef kDADiskDescriptionVolumePathKey;
extern const CFStringRef kDADiskDescriptionVolumeKindKey;
extern const CFStringRef kDADiskDescriptionVolumeUUIDKey;
extern const CFStringRef kDADiskDescriptionMediaNameKey;
extern const CFStringRef kDADiskDescriptionMediaRemovableKey;
extern const CFStringRef kDADiskDescriptionMediaEjectableKey;
extern const CFStringRef kDADiskDescriptionMediaUUIDKey;
extern const CFStringRef kDADiskDescriptionDeviceInternalKey;
extern const CFStringRef kDADiskDescriptionDevicePathKey;
extern const CFStringRef kDADiskDescriptionMediaBSDNameKey;

CFTypeID DASessionGetTypeID(void);
DASessionRef DASessionCreate(CFAllocatorRef allocator);
void DASessionScheduleWithRunLoop(DASessionRef session, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void DASessionUnscheduleFromRunLoop(DASessionRef session, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void DASessionSetDispatchQueue(DASessionRef session, dispatch_queue_t queue);
CFTypeID DADiskGetTypeID(void);
DADiskRef DADiskCreateFromBSDName(CFAllocatorRef allocator, DASessionRef session, const char *name);
DADiskRef DADiskCreateFromVolumePath(CFAllocatorRef allocator, DASessionRef session, CFURLRef path);
const char *DADiskGetBSDName(DADiskRef disk);
CFDictionaryRef DADiskCopyDescription(DADiskRef disk);
DADiskRef DADiskCopyWholeDisk(DADiskRef disk);
void DARegisterDiskAppearedCallback(DASessionRef session, CFDictionaryRef match, DADiskAppearedCallback callback, void *context);
void DARegisterDiskDisappearedCallback(DASessionRef session, CFDictionaryRef match, DADiskDisappearedCallback callback, void *context);
void DARegisterDiskDescriptionChangedCallback(DASessionRef session, CFDictionaryRef match, CFArrayRef watch,
                                              DADiskDescriptionChangedCallback callback, void *context);
void DAUnregisterCallback(DASessionRef session, void *callback, void *context);

#endif
