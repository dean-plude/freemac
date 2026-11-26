/* SPDX-License-Identifier: GPL-3.0-or-later
 * The corner of IOKit that Cocoa apps and their frameworks link (freemac
 * 1.223, Ferry 0.47.0), served from Foundation as CoreServices is, and
 * written from Apple's public IOKit documentation: the registry, which
 * Ferry doesn't have (a search finds nothing), and power assertions, kept
 * for the program and listed back to it, but not passed on to this
 * system. */
#import "FInternal.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <string.h>
#include <unistd.h>

const mach_port_t kIOMasterPortDefault = 0;
const mach_port_t kIOMainPortDefault = 0;

/* ---- the registry ----------------------------------------------------------------- */

CFMutableDictionaryRef IOServiceMatching(const char *name)
{
    if (!name)
        return NULL;
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] initWithObjectsAndKeys:@(name), @"IOProviderClass", nil];
}
CFMutableDictionaryRef IOServiceNameMatching(const char *name)
{
    if (!name)
        return NULL;
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] initWithObjectsAndKeys:@(name), @"IONameMatch", nil];
}
/* Both consume the matching dictionary, as on a Mac. */
io_service_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching)
{
    if (matching)
        CFRelease(matching);
    return IO_OBJECT_NULL;
}
kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort, CFDictionaryRef matching, io_iterator_t *existing)
{
    if (matching)
        CFRelease(matching);
    if (existing)
        *existing = IO_OBJECT_NULL;
    return kIOReturnSuccess;
}
io_object_t IOIteratorNext(io_iterator_t iterator) { return IO_OBJECT_NULL; }
boolean_t IOIteratorIsValid(io_iterator_t iterator) { return iterator == IO_OBJECT_NULL; }
kern_return_t IOObjectRelease(io_object_t object) { return object == IO_OBJECT_NULL ? kIOReturnSuccess : kIOReturnBadArgument; }
kern_return_t IOObjectRetain(io_object_t object) { return IOObjectRelease(object); }
io_registry_entry_t IORegistryEntryFromPath(mach_port_t mainPort, const io_string_t path) { return IO_OBJECT_NULL; }
io_registry_entry_t IORegistryGetRootEntry(mach_port_t mainPort) { return IO_OBJECT_NULL; }
CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator,
                                          IOOptionBits options)
{
    return NULL;
}
CFTypeRef IORegistryEntrySearchCFProperty(io_registry_entry_t entry, const io_name_t plane, CFStringRef key,
                                          CFAllocatorRef allocator, IOOptionBits options)
{
    return NULL;
}

/* the null object has no class and conforms to none; there is no service
 * to open, so no connection to call (freemac 1.233, Ferry 0.57.0) */
boolean_t IOObjectConformsTo(io_object_t object, const io_name_t className) { return 0; }
kern_return_t IOObjectGetClass(io_object_t object, io_name_t className)
{
    if (!className)
        return kIOReturnBadArgument;
    className[0] = 0;
    return object == IO_OBJECT_NULL ? kIOReturnBadArgument : kIOReturnSuccess;
}
kern_return_t IOServiceOpen(io_service_t service, task_t owningTask, uint32_t type, io_connect_t *connect)
{
    if (connect)
        *connect = IO_OBJECT_NULL;
    return kIOReturnBadArgument;
}
kern_return_t IOServiceClose(io_connect_t connect) { return connect == IO_OBJECT_NULL ? kIOReturnBadArgument : kIOReturnSuccess; }
kern_return_t IOConnectCallScalarMethod(mach_port_t connection, uint32_t selector, const uint64_t *input,
                                        uint32_t inputCnt, uint64_t *output, uint32_t *outputCnt)
{
    if (outputCnt)
        *outputCnt = 0;
    return kIOReturnBadArgument;
}
CFMutableDictionaryRef IOBSDNameMatching(mach_port_t mainPort, uint32_t options, const char *bsdName)
{
    if (!bsdName)
        return NULL;
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] initWithObjectsAndKeys:@(bsdName), @"BSD Name", nil];
}

/* ---- plug-ins: no service has one ------------------------------------------------- */

kern_return_t IOCreatePlugInInterfaceForService(io_service_t service, CFUUIDRef pluginType, CFUUIDRef interfaceType,
                                                IOCFPlugInInterface ***theInterface, SInt32 *theScore)
{
    if (theInterface)
        *theInterface = NULL;
    if (theScore)
        *theScore = 0;
    return kIOReturnUnsupported;
}
kern_return_t IODestroyPlugInInterface(IOCFPlugInInterface **interface)
{
    return interface ? kIOReturnSuccess : kIOReturnBadArgument;
}

/* ---- power assertions ------------------------------------------------------------- */

static NSMutableDictionary *assertions; /* id -> {type, level, name, count} */
static IOPMAssertionID next_id;

static IOReturn create(CFStringRef type, IOPMAssertionLevel level, CFStringRef name, IOPMAssertionID *out)
{
    if (!type || !out)
        return kIOReturnBadArgument;
    @synchronized([NSProcessInfo class]) {
        if (!assertions)
            assertions = [[NSMutableDictionary alloc] init];
        IOPMAssertionID n = ++next_id;
        assertions[@(n)] = [NSMutableDictionary dictionaryWithObjectsAndKeys:(id)type, (id)kIOPMAssertionTypeKey,
                                                @(level), (id)kIOPMAssertionLevelKey,
                                                (id)name ?: @"", (id)kIOPMAssertionNameKey, @1, @"count", nil];
        *out = n;
    }
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionCreateWithName(CFStringRef type, IOPMAssertionLevel level, CFStringRef name, IOPMAssertionID *out)
{
    return create(type, level, name, out);
}
IOReturn IOPMAssertionCreateWithDescription(CFStringRef type, CFStringRef name, CFStringRef details,
                                            CFStringRef reason, CFStringRef bundlePath, CFTimeInterval timeout,
                                            CFStringRef timeoutAction, IOPMAssertionID *out)
{
    return create(type, kIOPMAssertionLevelOn, name, out);
}
IOReturn IOPMAssertionCreate(CFStringRef type, IOPMAssertionLevel level, IOPMAssertionID *out)
{
    return create(type, level, NULL, out);
}
IOReturn IOPMAssertionRetain(IOPMAssertionID n)
{
    @synchronized([NSProcessInfo class]) {
        NSMutableDictionary *a = assertions[@(n)];
        if (!a)
            return kIOReturnNotFound;
        a[@"count"] = @([a[@"count"] intValue] + 1);
    }
    return kIOReturnSuccess;
}
IOReturn IOPMAssertionRelease(IOPMAssertionID n)
{
    @synchronized([NSProcessInfo class]) {
        NSMutableDictionary *a = assertions[@(n)];
        if (!a)
            return kIOReturnNotFound;
        int count = [a[@"count"] intValue] - 1;
        if (count <= 0)
            [assertions removeObjectForKey:@(n)];
        else
            a[@"count"] = @(count);
    }
    return kIOReturnSuccess;
}
IOReturn IOPMAssertionDeclareUserActivity(CFStringRef name, IOPMUserActiveType userType, IOPMAssertionID *out)
{
    if (!out)
        return kIOReturnBadArgument;
    if (*out == kIOPMNullAssertionID)
        return create(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, name, out);
    return kIOReturnSuccess;
}
IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *byPID)
{
    if (!byPID)
        return kIOReturnBadArgument;
    NSMutableArray *list = [NSMutableArray array];
    @synchronized([NSProcessInfo class]) {
        for (NSNumber *n in [[assertions allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSMutableDictionary *a = [[assertions[n] mutableCopy] autorelease];
            [a removeObjectForKey:@"count"];
            [list addObject:a];
        }
    }
    *byPID = (CFDictionaryRef)[[NSDictionary alloc] initWithObjectsAndKeys:list, @(getpid()), nil];
    return kIOReturnSuccess;
}
IOReturn IOPMCopyAssertionsStatus(CFDictionaryRef *status)
{
    if (!status)
        return kIOReturnBadArgument;
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    @synchronized([NSProcessInfo class]) {
        for (NSDictionary *a in [assertions allValues]) {
            id type = a[(id)kIOPMAssertionTypeKey];
            if ([a[(id)kIOPMAssertionLevelKey] intValue] == kIOPMAssertionLevelOn)
                s[type] = @(kIOPMAssertionLevelOn);
            else if (!s[type])
                s[type] = @(kIOPMAssertionLevelOff);
        }
    }
    *status = (CFDictionaryRef)[s copy];
    return kIOReturnSuccess;
}

/* freemac's displays aren't IOKit services, so there is nothing to tell. */
CFDictionaryRef IODisplayCreateInfoDictionary(io_service_t framebuffer, IOOptionBits options)
{
    (void)framebuffer;
    (void)options;
    return NULL;
}
