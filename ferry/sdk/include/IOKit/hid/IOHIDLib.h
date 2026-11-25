/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The HID device and queue plug-in interfaces (freemac 1.233, Ferry
 * 0.57.0), written from Apple's public IOKit HID documentation; not Apple's
 * header. Ferry has no I/O Kit registry, so IOCreatePlugInInterfaceForService
 * never hands one out: an app that looks for a device (VLC's Apple Remote)
 * finds none. */
#ifndef _FERRY_IOKIT_IOHIDLIB_H_
#define _FERRY_IOKIT_IOHIDLIB_H_
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/hid/IOHIDKeys.h>

__FERRY_BEGIN
#ifndef _FERRY_ABSOLUTETIME_
#define _FERRY_ABSOLUTETIME_
typedef UnsignedWide AbsoluteTime;
#endif

#define kIOHIDDeviceUserClientTypeID                                                                      \
    CFUUIDGetConstantUUIDWithBytes(NULL, 0xFA, 0x12, 0xFA, 0x38, 0x6F, 0x1A, 0x11, 0xD4, 0xBA, 0x0C, 0x00, \
                                   0x05, 0x02, 0x8F, 0x18, 0xD5)
#define kIOHIDDeviceInterfaceID                                                                           \
    CFUUIDGetConstantUUIDWithBytes(NULL, 0x78, 0xBD, 0x42, 0x0C, 0x6F, 0x14, 0x11, 0xD4, 0x94, 0x74, 0x00, \
                                   0x05, 0x02, 0x8F, 0x18, 0xD5)
#define kIOHIDQueueInterfaceID                                                                            \
    CFUUIDGetConstantUUIDWithBytes(NULL, 0x81, 0x38, 0x62, 0x9E, 0x6F, 0x14, 0x11, 0xD4, 0x97, 0x0E, 0x00, \
                                   0x05, 0x02, 0x8F, 0x18, 0xD5)

typedef void (*IOHIDCallbackFunction)(void *target, IOReturn result, void *refcon, void *sender);
typedef void (*IOHIDElementCallbackFunction)(void *target, IOReturn result, void *refcon, void *sender,
                                             IOHIDElementCookie elementCookie);

typedef struct IOHIDEventStruct {
    IOHIDElementType type;
    IOHIDElementCookie elementCookie;
    SInt32 value;
    AbsoluteTime timestamp;
    UInt32 longValueSize;
    void *longValue;
} IOHIDEventStruct;

typedef struct IOHIDQueueInterface {
    IUNKNOWN_C_GUTS;
    IOReturn (*createAsyncEventSource)(void *self, CFRunLoopSourceRef *source);
    CFRunLoopSourceRef (*getAsyncEventSource)(void *self);
    IOReturn (*createAsyncPort)(void *self, mach_port_t *port);
    mach_port_t (*getAsyncPort)(void *self);
    IOReturn (*create)(void *self, UInt32 flags, UInt32 depth);
    IOReturn (*dispose)(void *self);
    IOReturn (*addElement)(void *self, IOHIDElementCookie elementCookie, UInt32 flags);
    IOReturn (*removeElement)(void *self, IOHIDElementCookie elementCookie);
    Boolean (*hasElement)(void *self, IOHIDElementCookie elementCookie);
    IOReturn (*start)(void *self);
    IOReturn (*stop)(void *self);
    IOReturn (*getNextEvent)(void *self, IOHIDEventStruct *event, AbsoluteTime maxTime, UInt32 timeoutMS);
    IOReturn (*setEventCallout)(void *self, IOHIDCallbackFunction callback, void *callbackTarget,
                                void *callbackRefcon);
    IOReturn (*getEventCallout)(void *self, IOHIDCallbackFunction *outCallback, void **outCallbackTarget,
                                void **outCallbackRefcon);
} IOHIDQueueInterface;

typedef struct IOHIDDeviceInterface {
    IUNKNOWN_C_GUTS;
    IOReturn (*createAsyncEventSource)(void *self, CFRunLoopSourceRef *source);
    CFRunLoopSourceRef (*getAsyncEventSource)(void *self);
    IOReturn (*createAsyncPort)(void *self, mach_port_t *port);
    mach_port_t (*getAsyncPort)(void *self);
    IOReturn (*open)(void *self, IOHIDOptionsType flags);
    IOReturn (*close)(void *self);
    IOReturn (*setRemovalCallback)(void *self, IOHIDCallbackFunction removalCallback, void *removalTarget,
                                   void *removalRefcon);
    IOReturn (*getElementValue)(void *self, IOHIDElementCookie elementCookie, IOHIDEventStruct *valueEvent);
    IOReturn (*setElementValue)(void *self, IOHIDElementCookie elementCookie, IOHIDEventStruct *valueEvent,
                                UInt32 timeoutMS, IOHIDElementCallbackFunction callback, void *callbackTarget,
                                void *callbackRefcon);
    IOReturn (*queryElementValue)(void *self, IOHIDElementCookie elementCookie, IOHIDEventStruct *valueEvent,
                                  UInt32 timeoutMS, IOHIDElementCallbackFunction callback, void *callbackTarget,
                                  void *callbackRefcon);
    IOReturn (*startAllQueues)(void *self);
    IOReturn (*stopAllQueues)(void *self);
    IOHIDQueueInterface **(*allocQueue)(void *self);
    void **(*allocOutputTransaction)(void *self);
    IOReturn (*setReport)(void *self, IOHIDReportType reportType, UInt32 reportID, void *reportBuffer,
                          UInt32 reportBufferSize, UInt32 timeoutMS, IOHIDCallbackFunction callback,
                          void *callbackTarget, void *callbackRefcon);
    IOReturn (*getReport)(void *self, IOHIDReportType reportType, UInt32 reportID, void *reportBuffer,
                          UInt32 *reportBufferSize, UInt32 timeoutMS, IOHIDCallbackFunction callback,
                          void *callbackTarget, void *callbackRefcon);
    IOReturn (*copyMatchingElements)(void *self, CFDictionaryRef matchingDict, CFArrayRef *elements);
    IOReturn (*setInterruptReportHandlerCallback)(void *self, void *reportBuffer, UInt32 reportBufferSize,
                                                  void *callback, void *callbackTarget, void *callbackRefcon);
} IOHIDDeviceInterface;
typedef IOHIDDeviceInterface IOHIDDeviceInterface122;
__FERRY_END
#endif
