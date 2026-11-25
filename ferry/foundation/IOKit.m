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
