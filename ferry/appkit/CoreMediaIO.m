/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * CoreMediaIO's system object (freemac 1.257, Ferry 0.80.0): see
 * CoreMediaIO/CoreMediaIO.h. Nothing changes the device list (cameras
 * come through AVCaptureDevice), so listeners are kept by nobody and
 * never called. */
#include <CoreMediaIO/CoreMediaIO.h>
#include <stdatomic.h>
#include <string.h>

static _Atomic UInt32 allow_screen = 0, allow_wireless = 0;

static _Atomic UInt32 *switch_for(CMIOObjectPropertySelector selector)
{
    if (selector == kCMIOHardwarePropertyAllowScreenCaptureDevices)
        return &allow_screen;
    if (selector == kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices)
        return &allow_wireless;
    return NULL;
}

static int known(CMIOObjectPropertySelector s)
{
    return s == kCMIOObjectPropertyClass || s == kCMIOObjectPropertyName || s == kCMIOObjectPropertyOwnedObjects ||
           s == kCMIOHardwarePropertyDevices || s == kCMIOHardwarePropertyDefaultInputDevice || switch_for(s);
}

Boolean CMIOObjectHasProperty(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address)
{
    return objectID == kCMIOObjectSystemObject && address && known(address->mSelector);
}

OSStatus CMIOObjectIsPropertySettable(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                      Boolean *isSettable)
{
    if (objectID != kCMIOObjectSystemObject)
        return kCMIOHardwareBadObjectError;
    if (!address || !isSettable)
        return kCMIOHardwareIllegalOperationError;
    if (!known(address->mSelector))
        return kCMIOHardwareUnknownPropertyError;
    *isSettable = switch_for(address->mSelector) != NULL;
    return kCMIOHardwareNoError;
}

static UInt32 size_of(CMIOObjectPropertySelector s)
{
    switch (s) {
    case kCMIOObjectPropertyName: return sizeof(CFStringRef);
    case kCMIOObjectPropertyOwnedObjects:
    case kCMIOHardwarePropertyDevices: return 0; /* no devices */
    default: return sizeof(UInt32);
    }
}

OSStatus CMIOObjectGetPropertyDataSize(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                       UInt32 qualifierDataSize, const void *qualifierData, UInt32 *dataSize)
{
    (void)qualifierDataSize, (void)qualifierData;
    if (objectID != kCMIOObjectSystemObject)
        return kCMIOHardwareBadObjectError;
    if (!address || !dataSize)
        return kCMIOHardwareIllegalOperationError;
    if (!known(address->mSelector))
        return kCMIOHardwareUnknownPropertyError;
    *dataSize = size_of(address->mSelector);
    return kCMIOHardwareNoError;
}

OSStatus CMIOObjectGetPropertyData(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                   UInt32 qualifierDataSize, const void *qualifierData, UInt32 dataSize,
                                   UInt32 *dataUsed, void *data)
{
    (void)qualifierDataSize, (void)qualifierData;
    if (objectID != kCMIOObjectSystemObject)
        return kCMIOHardwareBadObjectError;
    if (!address || !dataUsed || (dataSize && !data))
        return kCMIOHardwareIllegalOperationError;
    CMIOObjectPropertySelector s = address->mSelector;
    if (!known(s))
        return kCMIOHardwareUnknownPropertyError;
    UInt32 need = size_of(s);
    if (dataSize < need)
        return kCMIOHardwareBadPropertySizeError;
    *dataUsed = need;
    if (!need)
        return kCMIOHardwareNoError;
    if (s == kCMIOObjectPropertyName) {
        CFStringRef name = CFSTR("The system");
        CFRetain(name);
        memcpy(data, &name, sizeof name);
        return kCMIOHardwareNoError;
    }
    UInt32 value = 0;
    if (s == kCMIOObjectPropertyClass)
        value = kCMIOSystemObjectClassID;
    else if (s == kCMIOHardwarePropertyDefaultInputDevice)
        value = kCMIOObjectUnknown;
    else
        value = atomic_load(switch_for(s));
    memcpy(data, &value, sizeof value);
    return kCMIOHardwareNoError;
}

OSStatus CMIOObjectSetPropertyData(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                   UInt32 qualifierDataSize, const void *qualifierData, UInt32 dataSize,
                                   const void *data)
{
    (void)qualifierDataSize, (void)qualifierData;
    if (objectID != kCMIOObjectSystemObject)
        return kCMIOHardwareBadObjectError;
    if (!address || !data)
        return kCMIOHardwareIllegalOperationError;
    if (!known(address->mSelector))
        return kCMIOHardwareUnknownPropertyError;
    _Atomic UInt32 *sw = switch_for(address->mSelector);
    if (!sw)
        return kCMIOHardwareIllegalOperationError;
    if (dataSize != sizeof(UInt32))
        return kCMIOHardwareBadPropertySizeError;
    UInt32 value;
    memcpy(&value, data, sizeof value);
    atomic_store(sw, value ? 1 : 0);
    return kCMIOHardwareNoError;
}

OSStatus CMIOObjectAddPropertyListener(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                       CMIOObjectPropertyListenerProc listener, void *clientData)
{
    (void)address, (void)clientData;
    if (objectID != kCMIOObjectSystemObject)
        return kCMIOHardwareBadObjectError;
    return listener ? kCMIOHardwareNoError : kCMIOHardwareIllegalOperationError;
}

OSStatus CMIOObjectRemovePropertyListener(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                          CMIOObjectPropertyListenerProc listener, void *clientData)
{
    return CMIOObjectAddPropertyListener(objectID, address, listener, clientData);
}

OSStatus CMIOObjectAddPropertyListenerBlock(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                            dispatch_queue_t dispatchQueue, CMIOObjectPropertyListenerBlock listener)
{
    (void)address, (void)dispatchQueue;
    if (objectID != kCMIOObjectSystemObject)
        return kCMIOHardwareBadObjectError;
    return listener ? kCMIOHardwareNoError : kCMIOHardwareIllegalOperationError;
}

OSStatus CMIOObjectRemovePropertyListenerBlock(CMIOObjectID objectID, const CMIOObjectPropertyAddress *address,
                                               dispatch_queue_t dispatchQueue,
                                               CMIOObjectPropertyListenerBlock listener)
{
    return CMIOObjectAddPropertyListenerBlock(objectID, address, dispatchQueue, listener);
}
