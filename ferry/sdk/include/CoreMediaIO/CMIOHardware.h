/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMediaIO's objects and their properties (freemac 1.257,
 * Ferry 0.80.0; appkit/CoreMediaIO.m). Written for freemac from Apple's
 * public API documentation; not Apple's header. The system object answers
 * its device list (empty: cameras come through AVCaptureDevice) and keeps
 * the two "allow screen capture devices" switches; every other object is
 * a bad object. */
#ifndef _FERRY_CMIOHARDWARE_H_
#define _FERRY_CMIOHARDWARE_H_
#include <MacTypes.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

__FERRY_BEGIN
typedef UInt32 CMIOObjectID;
typedef CMIOObjectID CMIODeviceID;
typedef CMIOObjectID CMIOStreamID;
typedef UInt32 CMIOClassID;
typedef UInt32 CMIOObjectPropertySelector;
typedef UInt32 CMIOObjectPropertyScope;
typedef UInt32 CMIOObjectPropertyElement;

typedef struct CMIOObjectPropertyAddress {
    CMIOObjectPropertySelector mSelector;
    CMIOObjectPropertyScope mScope;
    CMIOObjectPropertyElement mElement;
} CMIOObjectPropertyAddress;

enum {
    kCMIOObjectUnknown = 0,
    kCMIOObjectSystemObject = 1,
};
enum {
    kCMIOObjectPropertyScopeGlobal = 'glob',
    kCMIOObjectPropertyScopeWildcard = '****',
    kCMIODevicePropertyScopeInput = 'inpt',
    kCMIODevicePropertyScopeOutput = 'outp',
    kCMIOObjectPropertyElementMain = 0,
    kCMIOObjectPropertyElementMaster = 0,
    kCMIOObjectPropertyElementWildcard = 0xFFFFFFFF,
    kCMIOObjectPropertySelectorWildcard = '****',
};
enum {
    kCMIOHardwareNoError = 0,
    kCMIOHardwareNotRunningError = 'stop',
    kCMIOHardwareUnspecifiedError = 'what',
    kCMIOHardwareUnknownPropertyError = 'who?',
    kCMIOHardwareBadPropertySizeError = '!siz',
    kCMIOHardwareIllegalOperationError = 'nope',
    kCMIOHardwareBadObjectError = '!obj',
    kCMIOHardwareBadDeviceError = '!dev',
    kCMIOHardwareBadStreamError = '!str',
    kCMIOHardwareUnsupportedOperationError = 'unop',
};
enum {
    kCMIOSystemObjectClassID = 'asys',
    kCMIOObjectPropertyClass = 'clas',
    kCMIOObjectPropertyName = 'lnam',
    kCMIOObjectPropertyOwnedObjects = 'ownd',
    kCMIOHardwarePropertyDevices = 'dev#',
    kCMIOHardwarePropertyDefaultInputDevice = 'dIn ',
    kCMIOHardwarePropertyAllowScreenCaptureDevices = 'yes ',
    kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices = 'wscd',
};

typedef void (*CMIOObjectPropertyListenerProc)(CMIOObjectID objectID, UInt32 numberAddresses,
                                               const CMIOObjectPropertyAddress addresses[], void *clientData);

Boolean CMIOObjectHasProperty(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address);
OSStatus CMIOObjectIsPropertySettable(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                      Boolean *isSettable);
OSStatus CMIOObjectGetPropertyDataSize(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                       UInt32 qualifierDataSize, const void *qualifierData, UInt32 *dataSize);
OSStatus CMIOObjectGetPropertyData(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                   UInt32 qualifierDataSize, const void *qualifierData, UInt32 dataSize,
                                   UInt32 *dataUsed, void *data);
OSStatus CMIOObjectSetPropertyData(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                   UInt32 qualifierDataSize, const void *qualifierData, UInt32 dataSize,
                                   const void *data);
OSStatus CMIOObjectAddPropertyListener(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                       CMIOObjectPropertyListenerProc listener, void *clientData);
OSStatus CMIOObjectRemovePropertyListener(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                          CMIOObjectPropertyListenerProc listener, void *clientData);
#if __BLOCKS__
typedef void (^CMIOObjectPropertyListenerBlock)(UInt32 numberAddresses, const CMIOObjectPropertyAddress addresses[]);
OSStatus CMIOObjectAddPropertyListenerBlock(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                            dispatch_queue_t dispatchQueue, CMIOObjectPropertyListenerBlock listener);
OSStatus CMIOObjectRemovePropertyListenerBlock(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                               dispatch_queue_t dispatchQueue,
                                               CMIOObjectPropertyListenerBlock listener);
#endif
__FERRY_END
#endif
