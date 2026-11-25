/* SPDX-License-Identifier: GPL-3.0-or-later
 * DiskArbitration.framework for Ferry (freemac 1.232), from Apple's public
 * documentation. A session can be made and scheduled, but it knows no
 * disks: Ferry describes volumes through NSFileManager and NSURL's
 * resource values instead, so lookups answer NULL and callbacks never run. */
#import <Foundation/Foundation.h>
#include <DiskArbitration/DiskArbitration.h>

#define KEY(name, text) const CFStringRef name = (CFStringRef)@text;
KEY(kDADiskDescriptionVolumeNameKey, "DAVolumeName")
KEY(kDADiskDescriptionVolumePathKey, "DAVolumePath")
KEY(kDADiskDescriptionVolumeKindKey, "DAVolumeKind")
KEY(kDADiskDescriptionVolumeUUIDKey, "DAVolumeUUID")
KEY(kDADiskDescriptionMediaNameKey, "DAMediaName")
KEY(kDADiskDescriptionMediaRemovableKey, "DAMediaRemovable")
KEY(kDADiskDescriptionMediaEjectableKey, "DAMediaEjectable")
KEY(kDADiskDescriptionMediaUUIDKey, "DAMediaUUID")
KEY(kDADiskDescriptionDeviceInternalKey, "DADeviceInternal")
KEY(kDADiskDescriptionDevicePathKey, "DADevicePath")
KEY(kDADiskDescriptionMediaBSDNameKey, "DAMediaBSDName")

@interface FDASession : NSObject
@end
@implementation FDASession
@end
@interface FDADisk : NSObject
@end
@implementation FDADisk
@end

CFTypeID DASessionGetTypeID(void) { return (CFTypeID)(uintptr_t)[FDASession class]; }
CFTypeID DADiskGetTypeID(void) { return (CFTypeID)(uintptr_t)[FDADisk class]; }
DASessionRef DASessionCreate(CFAllocatorRef allocator) { return (DASessionRef)[[FDASession alloc] init]; }
void DASessionScheduleWithRunLoop(DASessionRef s, CFRunLoopRef rl, CFStringRef mode) { }
void DASessionUnscheduleFromRunLoop(DASessionRef s, CFRunLoopRef rl, CFStringRef mode) { }
void DASessionSetDispatchQueue(DASessionRef s, dispatch_queue_t q) { }
DADiskRef DADiskCreateFromBSDName(CFAllocatorRef a, DASessionRef s, const char *name) { return NULL; }
DADiskRef DADiskCreateFromVolumePath(CFAllocatorRef a, DASessionRef s, CFURLRef path) { return NULL; }
const char *DADiskGetBSDName(DADiskRef disk) { return NULL; }
CFDictionaryRef DADiskCopyDescription(DADiskRef disk) { return NULL; }
DADiskRef DADiskCopyWholeDisk(DADiskRef disk) { return NULL; }
void DARegisterDiskAppearedCallback(DASessionRef s, CFDictionaryRef m, DADiskAppearedCallback cb, void *c) { }
void DARegisterDiskDisappearedCallback(DASessionRef s, CFDictionaryRef m, DADiskDisappearedCallback cb, void *c) { }
void DARegisterDiskDescriptionChangedCallback(DASessionRef s, CFDictionaryRef m, CFArrayRef w,
                                              DADiskDescriptionChangedCallback cb, void *c) { }
void DAUnregisterCallback(DASessionRef s, void *cb, void *c) { }
