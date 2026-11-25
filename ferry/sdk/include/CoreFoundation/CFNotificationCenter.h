/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CFNotificationCenter and CFMachPort (foundation/
 * CFNotificationCenter.m, freemac 1.224, Ferry 0.48.0). Written for
 * freemac from Apple's public API documentation; not Apple's header.
 *
 * The local center is the program's NSNotificationCenter and the
 * distributed one its NSDistributedNotificationCenter, so a notification
 * posted either way reaches observers added the other way. The Darwin
 * notify center carries names only, within the program.
 *
 * There are no Mach ports on this system: a CFMachPort is only what
 * CGEventTapCreate would hand back, which Ferry never makes, so the calls
 * below answer NULL or nothing for one. */
#ifndef _FERRY_CFNOTIFICATIONCENTER_H_
#define _FERRY_CFNOTIFICATIONCENTER_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
typedef struct __CFNotificationCenter *CFNotificationCenterRef;
typedef CFStringRef CFNotificationName;
typedef void (*CFNotificationCallback)(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                                       const void *object, CFDictionaryRef userInfo);
typedef CF_ENUM(CFIndex, CFNotificationSuspensionBehavior) {
    CFNotificationSuspensionBehaviorDrop = 1,
    CFNotificationSuspensionBehaviorCoalesce = 2,
    CFNotificationSuspensionBehaviorHold = 3,
    CFNotificationSuspensionBehaviorDeliverImmediately = 4,
};
enum {
    kCFNotificationDeliverImmediately = (1UL << 0),
    kCFNotificationPostToAllSessions = (1UL << 1),
};

CFTypeID CFNotificationCenterGetTypeID(void);
CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void);
CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);
CFNotificationCenterRef CFNotificationCenterGetDarwinNotifyCenter(void);
/* name or object NULL: any; the suspension behaviour is the delivery's
 * (there is no suspension here) */
void CFNotificationCenterAddObserver(CFNotificationCenterRef center, const void *observer,
                                     CFNotificationCallback callBack, CFStringRef name, const void *object,
                                     CFNotificationSuspensionBehavior suspensionBehavior);
void CFNotificationCenterRemoveObserver(CFNotificationCenterRef center, const void *observer, CFNotificationName name,
                                        const void *object);
void CFNotificationCenterRemoveEveryObserver(CFNotificationCenterRef center, const void *observer);
void CFNotificationCenterPostNotification(CFNotificationCenterRef center, CFNotificationName name,
                                          const void *object, CFDictionaryRef userInfo, Boolean deliverImmediately);
void CFNotificationCenterPostNotificationWithOptions(CFNotificationCenterRef center, CFNotificationName name,
                                                     const void *object, CFDictionaryRef userInfo,
                                                     CFOptionFlags options);

/* ---- Mach ports ------------------------------------------------------------------- */
#ifndef _FERRY_CFMACHPORT_
#define _FERRY_CFMACHPORT_
typedef struct __CFMachPort *CFMachPortRef;
#endif
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFMachPortContext;
typedef void (*CFMachPortCallBack)(CFMachPortRef port, void *msg, CFIndex size, void *info);
typedef void (*CFMachPortInvalidationCallBack)(CFMachPortRef port, void *info);
CFTypeID CFMachPortGetTypeID(void);
/* NULL: there are no Mach ports */
CFMachPortRef CFMachPortCreate(CFAllocatorRef allocator, CFMachPortCallBack callout, CFMachPortContext *context,
                               Boolean *shouldFreeInfo);
CFRunLoopSourceRef CFMachPortCreateRunLoopSource(CFAllocatorRef allocator, CFMachPortRef port, CFIndex order);
void CFMachPortInvalidate(CFMachPortRef port);
Boolean CFMachPortIsValid(CFMachPortRef port);
void CFMachPortGetContext(CFMachPortRef port, CFMachPortContext *context);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
