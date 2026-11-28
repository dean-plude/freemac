/* SPDX-License-Identifier: GPL-3.0-or-later
 * DiskArbitration.framework for Ferry (freemac 1.232), from Apple's public
 * documentation. A session can be made and scheduled; callbacks registered
 * with it never run, since this system's disks aren't watched from here.
 *
 * Since freemac 1.271 (for the Stats system monitor) a disk can be looked
 * up by a mounted volume's path or by its name, and described: the names
 * are this system's own ("nvme0n1p2", "sda1"), read from /sys/class/block,
 * and the description gives the volume's name, path and kind, the drive's
 * model, size and connection, and whether it is internal, removable or
 * read-only. */
#import <Foundation/Foundation.h>
#include <DiskArbitration/DiskArbitration.h>
#include <sys/mount.h>
#include <string.h>

#define KEY(name, text) const CFStringRef name = (CFStringRef)@text;
KEY(kDADiskDescriptionVolumeNameKey, "DAVolumeName")
KEY(kDADiskDescriptionVolumePathKey, "DAVolumePath")
KEY(kDADiskDescriptionVolumeKindKey, "DAVolumeKind")
KEY(kDADiskDescriptionVolumeUUIDKey, "DAVolumeUUID")
KEY(kDADiskDescriptionVolumeMountableKey, "DAVolumeMountable")
KEY(kDADiskDescriptionVolumeNetworkKey, "DAVolumeNetwork")
KEY(kDADiskDescriptionMediaNameKey, "DAMediaName")
KEY(kDADiskDescriptionMediaRemovableKey, "DAMediaRemovable")
KEY(kDADiskDescriptionMediaEjectableKey, "DAMediaEjectable")
KEY(kDADiskDescriptionMediaUUIDKey, "DAMediaUUID")
KEY(kDADiskDescriptionMediaWritableKey, "DAMediaWritable")
KEY(kDADiskDescriptionMediaEncryptedKey, "DAMediaEncrypted")
KEY(kDADiskDescriptionMediaSizeKey, "DAMediaSize")
KEY(kDADiskDescriptionMediaWholeKey, "DAMediaWhole")
KEY(kDADiskDescriptionMediaLeafKey, "DAMediaLeaf")
KEY(kDADiskDescriptionMediaKindKey, "DAMediaKind")
KEY(kDADiskDescriptionDeviceInternalKey, "DADeviceInternal")
KEY(kDADiskDescriptionDevicePathKey, "DADevicePath")
KEY(kDADiskDescriptionDeviceModelKey, "DADeviceModel")
KEY(kDADiskDescriptionDeviceVendorKey, "DADeviceVendor")
KEY(kDADiskDescriptionDeviceProtocolKey, "DADeviceProtocol")
KEY(kDADiskDescriptionMediaBSDNameKey, "DAMediaBSDName")

@interface FDASession : NSObject
@end
@implementation FDASession
@end

@interface FDADisk : NSObject {
@public
    NSString *name;   /* in /sys/class/block */
    NSString *mount;  /* where its volume is mounted, if it is */
    char bsd[64];
}
@end
@implementation FDADisk
- (void)dealloc
{
    [name release];
    [mount release];
    [super dealloc];
}
@end

static NSString *block_dir(NSString *name) { return [@"/sys/class/block" stringByAppendingPathComponent:name]; }

static NSString *read_line(NSString *path)
{
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static FDADisk *make_disk(NSString *name, NSString *mount)
{
    if (![name length] || [name rangeOfString:@"/"].location != NSNotFound ||
        ![[NSFileManager defaultManager] fileExistsAtPath:block_dir(name)])
        return nil;
    FDADisk *d = [[FDADisk alloc] init];
    d->name = [name copy];
    d->mount = [mount copy];
    snprintf(d->bsd, sizeof d->bsd, "%s", [name UTF8String]);
    return d;
}

/* The mount point of a block device, from /proc/mounts. */
static NSString *mount_of(NSString *name)
{
    NSString *table = [NSString stringWithContentsOfFile:@"/proc/mounts" encoding:NSUTF8StringEncoding error:NULL];
    NSString *dev = [@"/dev/" stringByAppendingString:name];
    for (NSString *line in [table componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@" "];
        if ([f count] > 2 && [[[f objectAtIndex:0] stringByResolvingSymlinksInPath] isEqualToString:dev])
            return [[f objectAtIndex:1] stringByReplacingOccurrencesOfString:@"\\040" withString:@" "];
    }
    return nil;
}

CFTypeID DASessionGetTypeID(void) { return (CFTypeID)(uintptr_t)[FDASession class]; }
CFTypeID DADiskGetTypeID(void) { return (CFTypeID)(uintptr_t)[FDADisk class]; }
DASessionRef DASessionCreate(CFAllocatorRef allocator) { return (DASessionRef)[[FDASession alloc] init]; }
void DASessionScheduleWithRunLoop(DASessionRef s, CFRunLoopRef rl, CFStringRef mode) { }
void DASessionUnscheduleFromRunLoop(DASessionRef s, CFRunLoopRef rl, CFStringRef mode) { }
void DASessionSetDispatchQueue(DASessionRef s, dispatch_queue_t q) { }

DADiskRef DADiskCreateFromBSDName(CFAllocatorRef a, DASessionRef s, const char *name)
{
    if (!name)
        return NULL;
    if (!strncmp(name, "/dev/", 5))
        name += 5;
    NSString *n = [NSString stringWithUTF8String:name];
    return (DADiskRef)make_disk(n, mount_of(n));
}

DADiskRef DADiskCreateFromVolumePath(CFAllocatorRef a, DASessionRef s, CFURLRef path)
{
    NSString *p = [(NSURL *)path path];
    struct statfs fs;
    if (![p length] || statfs([p fileSystemRepresentation], &fs) != 0 || strncmp(fs.f_mntfromname, "/dev/", 5))
        return NULL;
    NSString *dev = [[NSString stringWithUTF8String:fs.f_mntfromname] stringByResolvingSymlinksInPath];
    return (DADiskRef)make_disk([dev lastPathComponent], [NSString stringWithUTF8String:fs.f_mntonname]);
}

static FDADisk *as_disk(DADiskRef d) { return [(id)d isKindOfClass:[FDADisk class]] ? (FDADisk *)d : nil; }

const char *DADiskGetBSDName(DADiskRef disk)
{
    FDADisk *d = as_disk(disk);
    return d ? d->bsd : NULL;
}

/* The whole drive a partition is on: the directory above it in /sys. */
static NSString *whole_name(NSString *name)
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:[block_dir(name) stringByAppendingPathComponent:@"partition"]])
        return [[[block_dir(name) stringByResolvingSymlinksInPath] stringByDeletingLastPathComponent] lastPathComponent];
    return name;
}

DADiskRef DADiskCopyWholeDisk(DADiskRef disk)
{
    FDADisk *d = as_disk(disk);
    if (!d)
        return NULL;
    NSString *whole = whole_name(d->name);
    return (DADiskRef)make_disk(whole, [whole isEqualToString:d->name] ? d->mount : mount_of(whole));
}

CFDictionaryRef DADiskCopyDescription(DADiskRef disk)
{
    FDADisk *d = as_disk(disk);
    if (!d)
        return NULL;
    NSString *whole = whole_name(d->name);
    NSString *wdir = block_dir(whole);
    NSString *device = [[wdir stringByAppendingPathComponent:@"device"] stringByResolvingSymlinksInPath];
    BOOL removable = [read_line([wdir stringByAppendingPathComponent:@"removable"]) isEqualToString:@"1"];
    BOOL usb = [device rangeOfString:@"/usb"].location != NSNotFound;
    BOOL readOnly = [read_line([block_dir(d->name) stringByAppendingPathComponent:@"ro"]) isEqualToString:@"1"];
    unsigned long long sectors = [read_line([block_dir(d->name) stringByAppendingPathComponent:@"size"]) longLongValue];
    NSString *model = read_line([wdir stringByAppendingPathComponent:@"device/model"]);
    NSString *vendor = read_line([wdir stringByAppendingPathComponent:@"device/vendor"]);
    NSString *protocol = usb ? @"USB" : [whole hasPrefix:@"nvme"] ? @"PCI-Express"
                         : [whole hasPrefix:@"mmcblk"] ? @"Secure Digital" : [whole hasPrefix:@"sd"] ? @"SATA"
                         : [whole hasPrefix:@"vd"] ? @"Virtual Interface" : @"Unknown";
    BOOL encrypted = [read_line([block_dir(d->name) stringByAppendingPathComponent:@"dm/uuid"]) hasPrefix:@"CRYPT-"];
    NSMutableDictionary *desc = [NSMutableDictionary dictionary];
    [desc setObject:d->name forKey:(id)kDADiskDescriptionMediaBSDNameKey];
    [desc setObject:[@"/dev/" stringByAppendingString:d->name] forKey:(id)kDADiskDescriptionDevicePathKey];
    [desc setObject:[NSNumber numberWithUnsignedLongLong:sectors * 512] forKey:(id)kDADiskDescriptionMediaSizeKey];
    [desc setObject:[NSNumber numberWithBool:[whole isEqualToString:d->name]] forKey:(id)kDADiskDescriptionMediaWholeKey];
    [desc setObject:[NSNumber numberWithBool:removable || usb] forKey:(id)kDADiskDescriptionMediaRemovableKey];
    [desc setObject:[NSNumber numberWithBool:removable || usb] forKey:(id)kDADiskDescriptionMediaEjectableKey];
    [desc setObject:[NSNumber numberWithBool:!(removable || usb)] forKey:(id)kDADiskDescriptionDeviceInternalKey];
    [desc setObject:[NSNumber numberWithBool:!readOnly] forKey:(id)kDADiskDescriptionMediaWritableKey];
    [desc setObject:[NSNumber numberWithBool:encrypted] forKey:(id)kDADiskDescriptionMediaEncryptedKey];
    [desc setObject:protocol forKey:(id)kDADiskDescriptionDeviceProtocolKey];
    [desc setObject:@"IOMedia" forKey:(id)kDADiskDescriptionMediaKindKey];
    if ([model length]) {
        [desc setObject:model forKey:(id)kDADiskDescriptionDeviceModelKey];
        [desc setObject:model forKey:(id)kDADiskDescriptionMediaNameKey];
    }
    if ([vendor length])
        [desc setObject:vendor forKey:(id)kDADiskDescriptionDeviceVendorKey];
    if (d->mount) {
        NSURL *url = [NSURL fileURLWithPath:d->mount isDirectory:YES];
        [desc setObject:url forKey:(id)kDADiskDescriptionVolumePathKey];
        NSString *volume = nil;
        [url getResourceValue:&volume forKey:NSURLVolumeNameKey error:NULL];
        [desc setObject:volume ?: [d->mount lastPathComponent] forKey:(id)kDADiskDescriptionVolumeNameKey];
        struct statfs fs;
        if (statfs([d->mount fileSystemRepresentation], &fs) == 0)
            [desc setObject:[NSString stringWithUTF8String:fs.f_fstypename] forKey:(id)kDADiskDescriptionVolumeKindKey];
        [desc setObject:@YES forKey:(id)kDADiskDescriptionVolumeMountableKey];
        [desc setObject:@NO forKey:(id)kDADiskDescriptionVolumeNetworkKey];
    }
    return (CFDictionaryRef)[desc copy];
}

/* the drive's entry in the IOKit registry, which Ferry doesn't have */
unsigned int DADiskCopyIOMedia(DADiskRef disk) { return 0; }

void DARegisterDiskAppearedCallback(DASessionRef s, CFDictionaryRef m, DADiskAppearedCallback cb, void *c) { }
void DARegisterDiskDisappearedCallback(DASessionRef s, CFDictionaryRef m, DADiskDisappearedCallback cb, void *c) { }
void DARegisterDiskDescriptionChangedCallback(DASessionRef s, CFDictionaryRef m, CFArrayRef w,
                                              DADiskDescriptionChangedCallback cb, void *c) { }
void DAUnregisterCallback(DASessionRef s, void *cb, void *c) { }
