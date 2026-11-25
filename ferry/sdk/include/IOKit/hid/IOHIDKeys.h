/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The HID Manager's keys and types (freemac 1.233, Ferry 0.57.0), written
 * from Apple's public IOKit HID documentation; not Apple's header. */
#ifndef _FERRY_IOKIT_IOHIDKEYS_H_
#define _FERRY_IOKIT_IOHIDKEYS_H_
#include <IOKit/IOKitLib.h>

__FERRY_BEGIN
typedef uint32_t IOHIDElementCookie;
typedef uint32_t IOHIDElementType;
enum {
    kIOHIDElementTypeInput_Misc = 1, kIOHIDElementTypeInput_Button = 2, kIOHIDElementTypeInput_Axis = 3,
    kIOHIDElementTypeInput_ScanCodes = 4, kIOHIDElementTypeOutput = 129, kIOHIDElementTypeFeature = 257,
    kIOHIDElementTypeCollection = 513,
};
typedef uint32_t IOHIDOptionsType;
enum { kIOHIDOptionsTypeNone = 0x00, kIOHIDOptionsTypeSeizeDevice = 0x01 };
typedef uint32_t IOHIDReportType;
enum { kIOHIDReportTypeInput = 0, kIOHIDReportTypeOutput, kIOHIDReportTypeFeature, kIOHIDReportTypeCount };

#define kIOHIDDeviceKey "IOHIDDevice"
#define kIOHIDTransportKey "Transport"
#define kIOHIDVendorIDKey "VendorID"
#define kIOHIDProductIDKey "ProductID"
#define kIOHIDProductKey "Product"
#define kIOHIDManufacturerKey "Manufacturer"
#define kIOHIDPrimaryUsageKey "PrimaryUsage"
#define kIOHIDPrimaryUsagePageKey "PrimaryUsagePage"
#define kIOHIDElementKey "Elements"
#define kIOHIDElementCookieKey "ElementCookie"
#define kIOHIDElementTypeKey "Type"
#define kIOHIDElementUsageKey "Usage"
#define kIOHIDElementUsagePageKey "UsagePage"
#define kIOHIDElementMinKey "Min"
#define kIOHIDElementMaxKey "Max"
__FERRY_END
#endif
