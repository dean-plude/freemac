/* SPDX-License-Identifier: GPL-3.0-or-later
 * CFNotificationCenter and CFMachPort (freemac 1.224, Ferry 0.48.0), served
 * from Foundation's file as the rest of CoreFoundation is. Our own code,
 * written from Apple's public API documentation.
 *
 * The local center is [NSNotificationCenter defaultCenter] and the
 * distributed one [NSDistributedNotificationCenter defaultCenter]: each
 * observer is an object of ours registered there, which calls the
 * observer's callback. An observer's object is matched by the pointer on the
 * local center and as an equal string on the distributed one, as on a Mac.
 * The Darwin notify center is a center of the program's own that carries
 * names only. There are no Mach ports here (CFSocket.m says the same of
 * version 1 run loop sources). Built without ARC. */
#import "FInternal.h"
#import <Foundation/NSDistributedNotificationCenter.h>
#include <CoreFoundation/CFNotificationCenter.h>

static NSNotificationCenter *darwin_center(void)
{
    static NSNotificationCenter *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[NSNotificationCenter alloc] init];
    });
    return c;
}

CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void)
{
    return (CFNotificationCenterRef)[NSNotificationCenter defaultCenter];
}
CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void)
{
    return (CFNotificationCenterRef)[NSDistributedNotificationCenter defaultCenter];
}
CFNotificationCenterRef CFNotificationCenterGetDarwinNotifyCenter(void)
{
    return (CFNotificationCenterRef)darwin_center();
}
CFTypeID CFNotificationCenterGetTypeID(void) { return 0x46520010; }

@interface FCFNotificationObserver : NSObject {
@public
    NSNotificationCenter *center;
    const void *observer;
    CFNotificationCallback callback;
    NSString *name;
    const void *object;     /* the local center's: compared by pointer */
    NSString *objectString; /* the distributed center's: compared as a string */
}
@end

static NSMutableArray *all_observers;
static NSLock *observers_lock;

static void observers_init(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all_observers = [[NSMutableArray alloc] init];
        observers_lock = [[NSLock alloc] init];
    });
}

static BOOL is_distributed(NSNotificationCenter *c) { return [c isKindOfClass:[NSDistributedNotificationCenter class]]; }

@implementation FCFNotificationObserver
- (void)dealloc
{
    [name release];
    [objectString release];
    [super dealloc];
}
- (void)fire:(NSNotification *)note
{
    id obj = [note object];
    if (center == darwin_center())
        obj = nil;
    else if (objectString) {
        if (![obj isKindOfClass:[NSString class]] || ![obj isEqualToString:objectString])
            return;
    } else if (object && (const void *)obj != object)
        return;
    callback((CFNotificationCenterRef)center, (void *)observer, (CFNotificationName)[note name], (const void *)obj,
             center == darwin_center() ? NULL : (CFDictionaryRef)[note userInfo]);
}
@end

void CFNotificationCenterAddObserver(CFNotificationCenterRef cfcenter, const void *observer,
                                     CFNotificationCallback callBack, CFStringRef name, const void *object,
                                     CFNotificationSuspensionBehavior suspensionBehavior)
{
    NSNotificationCenter *center = (NSNotificationCenter *)cfcenter;
    if (!center || !callBack)
        return;
    observers_init();
    FCFNotificationObserver *o = [[FCFNotificationObserver alloc] init];
    o->center = center;
    o->observer = observer;
    o->callback = callBack;
    o->name = [(NSString *)name copy];
    if (center != darwin_center()) {
        if (is_distributed(center)) {
            id s = (id)object;
            if (s && [s isKindOfClass:[NSString class]])
                o->objectString = [s copy];
        } else
            o->object = object;
    }
    [center addObserver:o selector:@selector(fire:) name:o->name object:o->objectString];
    [observers_lock lock];
    [all_observers addObject:o];
    [observers_lock unlock];
    [o release];
}

static void remove_matching(NSNotificationCenter *center, const void *observer, NSString *name, const void *object,
                            BOOL every)
{
    if (!center)
        return;
    observers_init();
    NSMutableArray *gone = [NSMutableArray array];
    [observers_lock lock];
    for (FCFNotificationObserver *o in all_observers) {
        if (o->center != center || o->observer != observer)
            continue;
        if (!every) {
            if (name && !(o->name && [o->name isEqualToString:name]))
                continue;
            if (object && o->object != object &&
                !(o->objectString && [(id)object isKindOfClass:[NSString class]] &&
                  [o->objectString isEqualToString:(id)object]))
                continue;
        }
        [gone addObject:o];
    }
    [all_observers removeObjectsInArray:gone];
    [observers_lock unlock];
    for (FCFNotificationObserver *o in gone)
        [center removeObserver:o];
}

void CFNotificationCenterRemoveObserver(CFNotificationCenterRef center, const void *observer, CFNotificationName name,
                                        const void *object)
{
    remove_matching((NSNotificationCenter *)center, observer, (NSString *)name, object, NO);
}
void CFNotificationCenterRemoveEveryObserver(CFNotificationCenterRef center, const void *observer)
{
    remove_matching((NSNotificationCenter *)center, observer, nil, NULL, YES);
}

void CFNotificationCenterPostNotificationWithOptions(CFNotificationCenterRef cfcenter, CFNotificationName name,
                                                     const void *object, CFDictionaryRef userInfo,
                                                     CFOptionFlags options)
{
    NSNotificationCenter *center = (NSNotificationCenter *)cfcenter;
    if (!center || !name)
        return;
    if (center == darwin_center())
        [center postNotificationName:(NSString *)name object:nil userInfo:nil];
    else if (is_distributed(center))
        [(NSDistributedNotificationCenter *)center postNotificationName:(NSString *)name object:(id)object
                                                              userInfo:(NSDictionary *)userInfo
                                                    deliverImmediately:(options & kCFNotificationDeliverImmediately) != 0];
    else
        [center postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo];
}
void CFNotificationCenterPostNotification(CFNotificationCenterRef center, CFNotificationName name, const void *object,
                                          CFDictionaryRef userInfo, Boolean deliverImmediately)
{
    CFNotificationCenterPostNotificationWithOptions(center, name, object, userInfo,
                                                    deliverImmediately ? kCFNotificationDeliverImmediately : 0);
}

/* ---- Mach ports ---------------------------------------------------------------- */

CFTypeID CFMachPortGetTypeID(void) { return 0x46520011; }
CFMachPortRef CFMachPortCreate(CFAllocatorRef allocator, CFMachPortCallBack callout, CFMachPortContext *context,
                               Boolean *shouldFreeInfo)
{
    if (shouldFreeInfo)
        *shouldFreeInfo = true;
    return NULL;
}
CFRunLoopSourceRef CFMachPortCreateRunLoopSource(CFAllocatorRef allocator, CFMachPortRef port, CFIndex order)
{
    return NULL;
}
void CFMachPortInvalidate(CFMachPortRef port) {}
Boolean CFMachPortIsValid(CFMachPortRef port) { return false; }
void CFMachPortGetContext(CFMachPortRef port, CFMachPortContext *context)
{
    if (context)
        memset(context, 0, sizeof *context);
}
