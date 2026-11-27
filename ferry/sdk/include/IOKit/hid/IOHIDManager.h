/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The HID Manager's type and its options (freemac OBS work), written from
 * Apple's public IOKit HID documentation; not Apple's header. Ferry finds
 * no HID devices (freemac Godot work): a manager opens and matches nothing,
 * and its callbacks never run. */
#ifndef _FERRY_IOKIT_IOHIDMANAGER_H_
#define _FERRY_IOKIT_IOHIDMANAGER_H_
#include <IOKit/hid/IOHIDDevice.h>

__FERRY_BEGIN
typedef struct __IOHIDManager *IOHIDManagerRef;
enum {
    kIOHIDManagerOptionNone = 0x0,
    kIOHIDManagerOptionUsePersistentProperties = 0x1,
    kIOHIDManagerOptionDoNotLoadProperties = 0x2,
    kIOHIDManagerOptionDoNotSaveProperties = 0x4,
};
typedef uint32_t IOHIDManagerOptions;

CFTypeID IOHIDManagerGetTypeID(void);
IOHIDManagerRef IOHIDManagerCreate(CFAllocatorRef allocator, IOOptionBits options);
IOReturn IOHIDManagerOpen(IOHIDManagerRef manager, IOOptionBits options);
IOReturn IOHIDManagerClose(IOHIDManagerRef manager, IOOptionBits options);
CFTypeRef IOHIDManagerGetProperty(IOHIDManagerRef manager, CFStringRef key);
Boolean IOHIDManagerSetProperty(IOHIDManagerRef manager, CFStringRef key, CFTypeRef value);
void IOHIDManagerScheduleWithRunLoop(IOHIDManagerRef manager, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void IOHIDManagerUnscheduleFromRunLoop(IOHIDManagerRef manager, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void IOHIDManagerSetDispatchQueue(IOHIDManagerRef manager, void *queue);
void IOHIDManagerActivate(IOHIDManagerRef manager);
void IOHIDManagerCancel(IOHIDManagerRef manager);
void IOHIDManagerSetDeviceMatching(IOHIDManagerRef manager, CFDictionaryRef matching);
void IOHIDManagerSetDeviceMatchingMultiple(IOHIDManagerRef manager, CFArrayRef multiple);
CFSetRef IOHIDManagerCopyDevices(IOHIDManagerRef manager);
void IOHIDManagerRegisterDeviceMatchingCallback(IOHIDManagerRef manager, IOHIDDeviceCallback callback, void *context);
void IOHIDManagerRegisterDeviceRemovalCallback(IOHIDManagerRef manager, IOHIDDeviceCallback callback, void *context);
void IOHIDManagerRegisterInputValueCallback(IOHIDManagerRef manager, IOHIDValueCallback callback, void *context);
void IOHIDManagerRegisterInputReportCallback(IOHIDManagerRef manager, IOHIDReportCallback callback, void *context);
void IOHIDManagerSetInputValueMatching(IOHIDManagerRef manager, CFDictionaryRef matching);
void IOHIDManagerSetInputValueMatchingMultiple(IOHIDManagerRef manager, CFArrayRef multiple);
__FERRY_END
#endif
