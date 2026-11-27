/* SPDX-License-Identifier: GPL-3.0-or-later
 * What the Godot engine's Mac build calls besides (freemac Godot work): a
 * HID manager that finds no devices, Force Feedback with none, registry
 * IDs, the main program's segments, whole-vector math, more colour spaces
 * by name and the newer file and volume keys. */
#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <ForceFeedback/ForceFeedback.h>
#include <CoreGraphics/CoreGraphics.h>
#include <mach-o/getsect.h>
#include <stdio.h>

static int matched;
static void on_match(void *ctx, IOReturn r, void *sender, IOHIDDeviceRef d) { matched++; }

typedef float f4 __attribute__((ext_vector_type(4)));
f4 _simd_pow_f4(f4 x, f4 y);

int main(void)
{
    @autoreleasepool {
        IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
        printf("manager %s, type matches %d\n", m ? "made" : "none", CFGetTypeID(m) == IOHIDManagerGetTypeID());
        NSArray *match = @[ @{@kIOHIDPrimaryUsagePageKey : @1, @kIOHIDPrimaryUsageKey : @5} ];
        IOHIDManagerSetDeviceMatchingMultiple(m, (__bridge CFArrayRef)match);
        IOHIDManagerRegisterDeviceMatchingCallback(m, on_match, NULL);
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        printf("open %d\n", IOHIDManagerOpen(m, kIOHIDOptionsTypeNone) == kIOReturnSuccess);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
        CFSetRef devices = IOHIDManagerCopyDevices(m);
        printf("devices %s, matched %d\n", devices ? "some" : "none", matched);
        IOHIDManagerSetProperty(m, CFSTR("Name"), CFSTR("pads"));
        printf("property %s\n", [(__bridge NSString *)IOHIDManagerGetProperty(m, CFSTR("Name")) UTF8String]);
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        printf("close %d\n", IOHIDManagerClose(m, 0) == kIOReturnSuccess);
        CFRelease(m);
        printf("no device: value %ld, elements %p\n", (long)IOHIDValueGetIntegerValue(NULL),
               (void *)IOHIDDeviceCopyMatchingElements(NULL, NULL, 0));

        FFDeviceObjectReference ff = (FFDeviceObjectReference)1;
        printf("force feedback %d, create %d, device %p\n", FFIsForceFeedback(0) == FF_OK,
               FFCreateDevice(0, &ff) == FF_OK, ff);

        uint64_t id = 7;
        printf("entry id %d %llu, parent %d, same %d\n", IORegistryEntryGetRegistryEntryID(0, &id) == KERN_SUCCESS,
               (unsigned long long)id, IORegistryEntryGetParentEntry(0, "IOService", &(io_registry_entry_t){1}) == 0,
               IOObjectIsEqualTo(0, 0));
        CFMutableDictionaryRef idm = IORegistryEntryIDMatching(42);
        printf("id matching %s\n", [[(__bridge NSDictionary *)idm description] containsString:@"42"] ? "has 42" : "?");
        CFRelease(idm);

        const struct segment_command_64 *text = getsegbyname("__TEXT");
        printf("__TEXT %s, __nope %s, __text section %s\n", text && !strcmp(text->segname, "__TEXT") ? "found" : "no",
               getsegbyname("__nope") ? "found" : "no", getsectbyname("__TEXT", "__text") ? "found" : "no");

        f4 p = _simd_pow_f4((f4){2, 3, 4, 9}, (f4){3, 2, 0.5f, 0.5f});
        printf("pow %g %g %g %g\n", p.x, p.y, p.z, p.w);

        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceDCIP3);
        CGColorSpaceRef lin = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
        printf("colour spaces %zu %zu\n", CGColorSpaceGetNumberOfComponents(cs), CGColorSpaceGetNumberOfComponents(lin));
        CGColorSpaceRelease(cs);
        CGColorSpaceRelease(lin);

        NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory()];
        NSNumber *cased = nil, *immutable = nil;
        NSURL *volume = nil;
        [home getResourceValue:&cased forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:NULL];
        [home getResourceValue:&immutable forKey:NSURLIsSystemImmutableKey error:NULL];
        [home getResourceValue:&volume forKey:NSURLVolumeURLKey error:NULL];
        printf("volume keys: case %s, immutable %d, volume %s\n", cased ? "answered" : "none", [immutable boolValue],
               volume && [[home path] hasPrefix:[volume path]] ? "holds home" : "?");
    }
    return 0;
}
