/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Core MIDI (freemac 1.263, Ferry 0.86.0), served from Core Audio's
 * library: a system with no MIDI devices. Clients and ports can be made
 * and disposed, every count is zero, sends go nowhere, and packet lists
 * are built as Core MIDI lays them out, so a program that lists its MIDI
 * devices at start (Audacity does) finds none and carries on. Written from
 * Apple's public documentation of MIDIServices.h; not Apple's header.
 */
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

typedef UInt32 MIDIObjectRef;
typedef MIDIObjectRef MIDIClientRef, MIDIPortRef, MIDIDeviceRef, MIDIEntityRef, MIDIEndpointRef;
typedef UInt64 MIDITimeStamp;
typedef SInt32 MIDIObjectType;
typedef SInt32 MIDIUniqueID;

#pragma pack(push, 4)
typedef struct MIDIPacket {
    MIDITimeStamp timeStamp;
    UInt16 length;
    Byte data[256];
} MIDIPacket;
typedef struct MIDIPacketList {
    UInt32 numPackets;
    MIDIPacket packet[1];
} MIDIPacketList;
#pragma pack(pop)

typedef void (*MIDINotifyProc)(const void *message, void *refCon);
typedef void (*MIDIReadProc)(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon);

enum {
    kMIDIInvalidClient = -10830,
    kMIDIInvalidPort = -10831,
    kMIDIUnknownEndpoint = -10834,
    kMIDIUnknownProperty = -10835,
    kMIDIObjectNotFound = -10842,
};

/* clients and ports get numbers of their own; nothing else exists */
static _Atomic UInt32 next_ref = 0x4d000001;

static OSStatus new_ref(MIDIObjectRef *out)
{
    if (!out) return paramErr;
    *out = atomic_fetch_add(&next_ref, 1);
    return noErr;
}

OSStatus MIDIClientCreate(CFStringRef name, MIDINotifyProc notifyProc, void *notifyRefCon, MIDIClientRef *outClient)
{
    (void)name; (void)notifyProc; (void)notifyRefCon;
    return new_ref(outClient);
}

OSStatus MIDIClientCreateWithBlock(CFStringRef name, MIDIClientRef *outClient, void *notifyBlock)
{
    (void)name; (void)notifyBlock;
    return new_ref(outClient);
}

OSStatus MIDIClientDispose(MIDIClientRef client) { return client ? noErr : kMIDIInvalidClient; }

OSStatus MIDIInputPortCreate(MIDIClientRef client, CFStringRef name, MIDIReadProc readProc, void *refCon,
                             MIDIPortRef *outPort)
{
    (void)name; (void)readProc; (void)refCon;
    if (!client) return kMIDIInvalidClient;
    return new_ref(outPort);
}

OSStatus MIDIInputPortCreateWithBlock(MIDIClientRef client, CFStringRef name, MIDIPortRef *outPort, void *readBlock)
{
    (void)name; (void)readBlock;
    if (!client) return kMIDIInvalidClient;
    return new_ref(outPort);
}

OSStatus MIDIOutputPortCreate(MIDIClientRef client, CFStringRef name, MIDIPortRef *outPort)
{
    (void)name;
    if (!client) return kMIDIInvalidClient;
    return new_ref(outPort);
}

OSStatus MIDIPortDispose(MIDIPortRef port) { return port ? noErr : kMIDIInvalidPort; }

OSStatus MIDIPortConnectSource(MIDIPortRef port, MIDIEndpointRef source, void *connRefCon)
{
    (void)connRefCon;
    if (!port) return kMIDIInvalidPort;
    (void)source;
    return kMIDIUnknownEndpoint;
}

OSStatus MIDIPortDisconnectSource(MIDIPortRef port, MIDIEndpointRef source)
{
    (void)source;
    return port ? kMIDIUnknownEndpoint : kMIDIInvalidPort;
}

/* the device tree: empty */
ItemCount MIDIGetNumberOfDevices(void) { return 0; }
ItemCount MIDIGetNumberOfExternalDevices(void) { return 0; }
ItemCount MIDIGetNumberOfSources(void) { return 0; }
ItemCount MIDIGetNumberOfDestinations(void) { return 0; }
MIDIDeviceRef MIDIGetDevice(ItemCount i) { (void)i; return 0; }
MIDIDeviceRef MIDIGetExternalDevice(ItemCount i) { (void)i; return 0; }
MIDIEndpointRef MIDIGetSource(ItemCount i) { (void)i; return 0; }
MIDIEndpointRef MIDIGetDestination(ItemCount i) { (void)i; return 0; }
ItemCount MIDIDeviceGetNumberOfEntities(MIDIDeviceRef d) { (void)d; return 0; }
MIDIEntityRef MIDIDeviceGetEntity(MIDIDeviceRef d, ItemCount i) { (void)d; (void)i; return 0; }
ItemCount MIDIEntityGetNumberOfSources(MIDIEntityRef e) { (void)e; return 0; }
ItemCount MIDIEntityGetNumberOfDestinations(MIDIEntityRef e) { (void)e; return 0; }
MIDIEndpointRef MIDIEntityGetSource(MIDIEntityRef e, ItemCount i) { (void)e; (void)i; return 0; }
MIDIEndpointRef MIDIEntityGetDestination(MIDIEntityRef e, ItemCount i) { (void)e; (void)i; return 0; }

OSStatus MIDIEndpointGetEntity(MIDIEndpointRef endpoint, MIDIEntityRef *outEntity)
{
    (void)endpoint;
    if (outEntity) *outEntity = 0;
    return kMIDIObjectNotFound;
}

OSStatus MIDIEntityGetDevice(MIDIEntityRef entity, MIDIDeviceRef *outDevice)
{
    (void)entity;
    if (outDevice) *outDevice = 0;
    return kMIDIObjectNotFound;
}

OSStatus MIDIObjectFindByUniqueID(MIDIUniqueID uid, MIDIObjectRef *outObject, MIDIObjectType *outType)
{
    (void)uid;
    if (outObject) *outObject = 0;
    if (outType) *outType = -1;
    return kMIDIObjectNotFound;
}

static OSStatus no_property(void *out)
{
    if (out) memset(out, 0, sizeof(void *));
    return kMIDIUnknownProperty;
}

OSStatus MIDIObjectGetStringProperty(MIDIObjectRef obj, CFStringRef propertyID, CFStringRef *str)
{
    (void)obj; (void)propertyID;
    return no_property(str);
}

OSStatus MIDIObjectGetDataProperty(MIDIObjectRef obj, CFStringRef propertyID, CFDataRef *outData)
{
    (void)obj; (void)propertyID;
    return no_property(outData);
}

OSStatus MIDIObjectGetDictionaryProperty(MIDIObjectRef obj, CFStringRef propertyID, CFDictionaryRef *outDict)
{
    (void)obj; (void)propertyID;
    return no_property(outDict);
}

OSStatus MIDIObjectGetIntegerProperty(MIDIObjectRef obj, CFStringRef propertyID, SInt32 *outValue)
{
    (void)obj; (void)propertyID;
    if (outValue) *outValue = 0;
    return kMIDIUnknownProperty;
}

OSStatus MIDIObjectGetProperties(MIDIObjectRef obj, CFPropertyListRef *outProperties, Boolean deep)
{
    (void)obj; (void)deep;
    return no_property(outProperties);
}

OSStatus MIDIObjectSetStringProperty(MIDIObjectRef obj, CFStringRef propertyID, CFStringRef str)
{
    (void)obj; (void)propertyID; (void)str;
    return kMIDIObjectNotFound;
}

OSStatus MIDIObjectSetIntegerProperty(MIDIObjectRef obj, CFStringRef propertyID, SInt32 value)
{
    (void)obj; (void)propertyID; (void)value;
    return kMIDIObjectNotFound;
}

/* sending: there is nowhere to send to */
OSStatus MIDISend(MIDIPortRef port, MIDIEndpointRef dest, const MIDIPacketList *pktlist)
{
    (void)pktlist;
    if (!port) return kMIDIInvalidPort;
    return dest ? kMIDIUnknownEndpoint : kMIDIUnknownEndpoint;
}

OSStatus MIDIReceived(MIDIEndpointRef src, const MIDIPacketList *pktlist)
{
    (void)src; (void)pktlist;
    return kMIDIUnknownEndpoint;
}

OSStatus MIDIFlushOutput(MIDIEndpointRef dest) { (void)dest; return noErr; }
OSStatus MIDIRestart(void) { return noErr; }

OSStatus MIDISourceCreate(MIDIClientRef client, CFStringRef name, MIDIEndpointRef *outSrc)
{
    (void)name;
    if (!client) return kMIDIInvalidClient;
    return new_ref(outSrc);
}

OSStatus MIDIDestinationCreate(MIDIClientRef client, CFStringRef name, MIDIReadProc readProc, void *refCon,
                               MIDIEndpointRef *outDest)
{
    (void)name; (void)readProc; (void)refCon;
    if (!client) return kMIDIInvalidClient;
    return new_ref(outDest);
}

OSStatus MIDIEndpointDispose(MIDIEndpointRef endpt) { (void)endpt; return noErr; }

/* packet lists, laid out as Core MIDI documents them: each packet follows
 * the last byte of the one before, packed to four bytes */
MIDIPacket *MIDIPacketListInit(MIDIPacketList *pktlist)
{
    pktlist->numPackets = 0;
    return &pktlist->packet[0];
}

MIDIPacket *MIDIPacketListAdd(MIDIPacketList *pktlist, ByteCount listSize, MIDIPacket *curPacket, MIDITimeStamp time,
                              ByteCount nData, const Byte *data)
{
    Byte *end = (Byte *)pktlist + listSize;
    if (!curPacket || nData > 65535) return NULL;
    if (pktlist->numPackets > 0 && curPacket->timeStamp == time && curPacket->length > 0 && nData > 0 &&
        curPacket->data[0] != 0xF0 && data[0] != 0xF0 && curPacket->length + nData <= 65535 &&
        curPacket->data + curPacket->length + nData <= end) {
        memcpy(curPacket->data + curPacket->length, data, nData);
        curPacket->length += (UInt16)nData;
        return curPacket;
    }
    MIDIPacket *next = pktlist->numPackets ? (MIDIPacket *)(curPacket->data + curPacket->length) : curPacket;
    if ((Byte *)next->data + nData > end) return NULL;
    next->timeStamp = time;
    next->length = (UInt16)nData;
    if (nData) memcpy(next->data, data, nData);
    pktlist->numPackets++;
    return next;
}

/* property names, as the documentation gives them */
const CFStringRef kMIDIPropertyName = (CFStringRef)@"name";
const CFStringRef kMIDIPropertyManufacturer = (CFStringRef)@"manufacturer";
const CFStringRef kMIDIPropertyModel = (CFStringRef)@"model";
const CFStringRef kMIDIPropertyUniqueID = (CFStringRef)@"uniqueID";
const CFStringRef kMIDIPropertyDeviceID = (CFStringRef)@"deviceID";
const CFStringRef kMIDIPropertyDisplayName = (CFStringRef)@"displayName";
const CFStringRef kMIDIPropertyOffline = (CFStringRef)@"offline";
const CFStringRef kMIDIPropertyPrivate = (CFStringRef)@"private";
const CFStringRef kMIDIPropertyConnectionUniqueID = (CFStringRef)@"connUniqueID";
const CFStringRef kMIDIPropertyDriverOwner = (CFStringRef)@"driver";
const CFStringRef kMIDIPropertyIsEmbeddedEntity = (CFStringRef)@"embedded";
const CFStringRef kMIDIPropertyIsBroadcast = (CFStringRef)@"broadcast";
const CFStringRef kMIDIPropertyImage = (CFStringRef)@"image";
