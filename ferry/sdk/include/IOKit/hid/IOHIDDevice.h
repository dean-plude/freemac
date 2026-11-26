/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The HID Manager's device, element and value types (freemac OBS work),
 * written from Apple's public IOKit HID documentation; not Apple's header.
 * Ferry has no I/O Kit registry and finds no HID devices, so only the
 * types are here, for programs that bring the header in (OBS's libobs). */
#ifndef _FERRY_IOKIT_IOHIDDEVICE_H_
#define _FERRY_IOKIT_IOHIDDEVICE_H_
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/IOReturn.h>
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef struct __IOHIDDevice *IOHIDDeviceRef;
typedef struct __IOHIDElement *IOHIDElementRef;
typedef struct __IOHIDValue *IOHIDValueRef;
typedef void (*IOHIDCallback)(void *context, IOReturn result, void *sender);
typedef void (*IOHIDValueCallback)(void *context, IOReturn result, void *sender, IOHIDValueRef value);
typedef void (*IOHIDReportCallback)(void *context, IOReturn result, void *sender, IOHIDReportType type,
                                    uint32_t reportID, uint8_t *report, CFIndex reportLength);
typedef void (*IOHIDDeviceCallback)(void *context, IOReturn result, void *sender, IOHIDDeviceRef device);
__FERRY_END
#endif
