/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the corner of IOKit that Cocoa apps and their frameworks link
 * (freemac 1.223, Ferry 0.47.0), written from Apple's public IOKit
 * documentation; not Apple's header. Ferry has no I/O Kit registry: a
 * matching dictionary can be made, a search finds nothing, and releasing
 * the null object succeeds. Power assertions are in IOKit/pwr_mgt/IOPMLib.h.
 * The calls are served from Ferry's Foundation (foundation/IOKit.m). */
#ifndef _FERRY_IOKIT_IOKITLIB_H_
#define _FERRY_IOKIT_IOKITLIB_H_
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <IOKit/IOReturn.h>
__FERRY_BEGIN

typedef mach_port_t io_object_t;
typedef io_object_t io_iterator_t, io_registry_entry_t, io_service_t, io_connect_t;
typedef char io_name_t[128];
typedef char io_string_t[512];
typedef uint32_t IOOptionBits;
#define IO_OBJECT_NULL ((io_object_t)0)
extern const mach_port_t kIOMasterPortDefault;
extern const mach_port_t kIOMainPortDefault;
#define kIOServicePlane "IOService"
#define kIOPlatformUUIDKey "IOPlatformUUID"
#define kIOPlatformSerialNumberKey "IOPlatformSerialNumber"

CFMutableDictionaryRef IOServiceMatching(const char *name) CF_RETURNS_RETAINED;
CFMutableDictionaryRef IOServiceNameMatching(const char *name) CF_RETURNS_RETAINED;
io_service_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching);
kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort, CFDictionaryRef matching, io_iterator_t *existing);
io_object_t IOIteratorNext(io_iterator_t iterator);
boolean_t IOIteratorIsValid(io_iterator_t iterator);
kern_return_t IOObjectRelease(io_object_t object);
boolean_t IOObjectIsEqualTo(io_object_t object, io_object_t anObject);
kern_return_t IORegistryEntryGetParentEntry(io_registry_entry_t entry, const io_name_t plane,
                                            io_registry_entry_t *parent);
kern_return_t IORegistryEntryGetRegistryEntryID(io_registry_entry_t entry, uint64_t *entryID);
CFMutableDictionaryRef IORegistryEntryIDMatching(uint64_t entryID);
kern_return_t IOObjectRetain(io_object_t object);
io_registry_entry_t IORegistryEntryFromPath(mach_port_t mainPort, const io_string_t path);
io_registry_entry_t IORegistryGetRootEntry(mach_port_t mainPort);
CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator,
                                          IOOptionBits options) CF_RETURNS_RETAINED;
CFTypeRef IORegistryEntrySearchCFProperty(io_registry_entry_t entry, const io_name_t plane, CFStringRef key,
                                          CFAllocatorRef allocator, IOOptionBits options) CF_RETURNS_RETAINED;

/* the object's class, opening a service and calling its methods, and
 * matching by BSD name (freemac 1.233, Ferry 0.57.0): with no registry
 * there is no object, so these answer as for the null object */
boolean_t IOObjectConformsTo(io_object_t object, const io_name_t className);
kern_return_t IOObjectGetClass(io_object_t object, io_name_t className);
kern_return_t IOServiceOpen(io_service_t service, task_t owningTask, uint32_t type, io_connect_t *connect);
kern_return_t IOServiceClose(io_connect_t connect);
kern_return_t IOConnectCallScalarMethod(mach_port_t connection, uint32_t selector, const uint64_t *input,
                                        uint32_t inputCnt, uint64_t *output, uint32_t *outputCnt);
CFMutableDictionaryRef IOBSDNameMatching(mach_port_t mainPort, uint32_t options,
                                         const char *bsdName) CF_RETURNS_RETAINED;

/* Notification ports (freemac 1.265): a Mach port and a run loop source
 * that nothing is sent to. */
typedef struct IONotificationPort *IONotificationPortRef;
IONotificationPortRef IONotificationPortCreate(mach_port_t mainPort);
void IONotificationPortDestroy(IONotificationPortRef notify);
CFRunLoopSourceRef IONotificationPortGetRunLoopSource(IONotificationPortRef notify);
mach_port_t IONotificationPortGetMachPort(IONotificationPortRef notify);
__FERRY_END
#endif
