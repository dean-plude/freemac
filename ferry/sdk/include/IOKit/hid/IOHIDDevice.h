/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The HID Manager's device, element and value types (freemac OBS work),
 * written from Apple's public IOKit HID documentation; not Apple's header.
 * Ferry has no I/O Kit registry and finds no HID devices, so the calls
 * here are only ever handed objects a program made up: they answer
 * nothing (freemac Godot work). */
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

CFTypeID IOHIDDeviceGetTypeID(void);
IOHIDDeviceRef IOHIDDeviceCreate(CFAllocatorRef allocator, io_service_t service);
io_service_t IOHIDDeviceGetService(IOHIDDeviceRef device);
IOReturn IOHIDDeviceOpen(IOHIDDeviceRef device, IOOptionBits options);
IOReturn IOHIDDeviceClose(IOHIDDeviceRef device, IOOptionBits options);
Boolean IOHIDDeviceConformsTo(IOHIDDeviceRef device, uint32_t usagePage, uint32_t usage);
CFTypeRef IOHIDDeviceGetProperty(IOHIDDeviceRef device, CFStringRef key);
Boolean IOHIDDeviceSetProperty(IOHIDDeviceRef device, CFStringRef key, CFTypeRef property);
CFArrayRef IOHIDDeviceCopyMatchingElements(IOHIDDeviceRef device, CFDictionaryRef matching, IOOptionBits options);
void IOHIDDeviceScheduleWithRunLoop(IOHIDDeviceRef device, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void IOHIDDeviceUnscheduleFromRunLoop(IOHIDDeviceRef device, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void IOHIDDeviceRegisterRemovalCallback(IOHIDDeviceRef device, IOHIDCallback callback, void *context);
void IOHIDDeviceRegisterInputValueCallback(IOHIDDeviceRef device, IOHIDValueCallback callback, void *context);
void IOHIDDeviceRegisterInputReportCallback(IOHIDDeviceRef device, uint8_t *report, CFIndex reportLength,
                                            IOHIDReportCallback callback, void *context);
IOReturn IOHIDDeviceSetValue(IOHIDDeviceRef device, IOHIDElementRef element, IOHIDValueRef value);
IOReturn IOHIDDeviceGetValue(IOHIDDeviceRef device, IOHIDElementRef element, IOHIDValueRef *pValue);
IOReturn IOHIDDeviceSetReport(IOHIDDeviceRef device, IOHIDReportType reportType, CFIndex reportID,
                              const uint8_t *report, CFIndex reportLength);
IOReturn IOHIDDeviceGetReport(IOHIDDeviceRef device, IOHIDReportType reportType, CFIndex reportID,
                              uint8_t *report, CFIndex *pReportLength);

CFTypeID IOHIDElementGetTypeID(void);
IOHIDDeviceRef IOHIDElementGetDevice(IOHIDElementRef element);
IOHIDElementRef IOHIDElementGetParent(IOHIDElementRef element);
CFArrayRef IOHIDElementGetChildren(IOHIDElementRef element);
IOHIDElementCookie IOHIDElementGetCookie(IOHIDElementRef element);
IOHIDElementType IOHIDElementGetType(IOHIDElementRef element);
uint32_t IOHIDElementGetUsagePage(IOHIDElementRef element);
uint32_t IOHIDElementGetUsage(IOHIDElementRef element);
CFIndex IOHIDElementGetLogicalMin(IOHIDElementRef element);
CFIndex IOHIDElementGetLogicalMax(IOHIDElementRef element);
CFIndex IOHIDElementGetPhysicalMin(IOHIDElementRef element);
CFIndex IOHIDElementGetPhysicalMax(IOHIDElementRef element);
CFStringRef IOHIDElementGetName(IOHIDElementRef element);

CFTypeID IOHIDValueGetTypeID(void);
IOHIDElementRef IOHIDValueGetElement(IOHIDValueRef value);
uint64_t IOHIDValueGetTimeStamp(IOHIDValueRef value);
CFIndex IOHIDValueGetIntegerValue(IOHIDValueRef value);
double IOHIDValueGetScaledValue(IOHIDValueRef value, uint32_t type);
CFIndex IOHIDValueGetLength(IOHIDValueRef value);
const uint8_t *IOHIDValueGetBytePtr(IOHIDValueRef value);
__FERRY_END
#endif
