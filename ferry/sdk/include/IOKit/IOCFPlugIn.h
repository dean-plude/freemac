/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * IOKit's user-space driver plug-ins (freemac 1.233, Ferry 0.57.0),
 * written from Apple's public IOKit documentation; not Apple's header.
 * Ferry has no I/O Kit registry, so no service has a plug-in: making one
 * answers kIOReturnUnsupported. Served from Foundation (foundation/IOKit.m). */
#ifndef _FERRY_IOKIT_IOCFPLUGIN_H_
#define _FERRY_IOKIT_IOCFPLUGIN_H_
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CFPlugInCOM.h>

__FERRY_BEGIN
#define kIOCFPlugInInterfaceID                                                                            \
    CFUUIDGetConstantUUIDWithBytes(NULL, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, \
                                   0x50, 0xE4, 0xC6, 0x42, 0x6F)
#define IOCFPLUGINBASE                                                                                 \
    UInt16 version;                                                                                    \
    UInt16 revision;                                                                                   \
    IOReturn (*Probe)(void *thisPointer, CFDictionaryRef propertyTable, io_service_t service, SInt32 *order); \
    IOReturn (*Start)(void *thisPointer, CFDictionaryRef propertyTable, io_service_t service);         \
    IOReturn (*Stop)(void *thisPointer)
typedef struct IOCFPlugInInterfaceStruct {
    IUNKNOWN_C_GUTS;
    IOCFPLUGINBASE;
} IOCFPlugInInterface;

kern_return_t IOCreatePlugInInterfaceForService(io_service_t service, CFUUIDRef pluginType, CFUUIDRef interfaceType,
                                                IOCFPlugInInterface ***theInterface, SInt32 *theScore);
kern_return_t IODestroyPlugInInterface(IOCFPlugInInterface **interface);
__FERRY_END
#endif
