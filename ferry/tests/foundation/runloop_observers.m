/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.230): CFRunLoopObserver, as KeyboardShortcuts and
 * other Swift Mac code use it: observers told as a run starts and ends,
 * before timers and sources and around the wait, in their order; a one-shot
 * observer; a context's retain and release; invalidating and removing. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static int retained, released;
static const void *ctx_retain(const void *info) { retained++; return info; }
static void ctx_release(const void *info) { (void)info; released++; }

static int counts[8];
static void count_activity(CFRunLoopObserverRef o, CFRunLoopActivity a, void *info)
{
    (void)o;
    int *c = info;
    switch (a) {
    case kCFRunLoopEntry: c[0]++; break;
    case kCFRunLoopBeforeTimers: c[1]++; break;
    case kCFRunLoopBeforeSources: c[2]++; break;
    case kCFRunLoopBeforeWaiting: c[3]++; break;
    case kCFRunLoopAfterWaiting: c[4]++; break;
    case kCFRunLoopExit: c[5]++; break;
    default: c[6]++; break;
    }
}

int main(void)
{
    @autoreleasepool {
        CFRunLoopRef rl = CFRunLoopGetCurrent();
        printf("same loop: %d\n", rl == [[NSRunLoop currentRunLoop] getCFRunLoop]);

        CFRunLoopObserverContext cx = {0, counts, ctx_retain, ctx_release, NULL};
        CFRunLoopObserverRef all = CFRunLoopObserverCreate(NULL, kCFRunLoopAllActivities, true, 0, count_activity, &cx);
        printf("retained on create: %d\n", retained);
        printf("activities all: %d repeats: %d order: %ld valid: %d\n",
               CFRunLoopObserverGetActivities(all) == kCFRunLoopAllActivities, CFRunLoopObserverDoesRepeat(all),
               (long)CFRunLoopObserverGetOrder(all), CFRunLoopObserverIsValid(all));
        CFRunLoopObserverContext back;
        CFRunLoopObserverGetContext(all, &back);
        printf("context info kept: %d\n", back.info == counts);

        /* two block observers, added out of order, are told in their order */
        NSMutableString *order = [NSMutableString string];
        CFRunLoopObserverRef late = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopEntry, true, 20,
            ^(CFRunLoopObserverRef o, CFRunLoopActivity a) { (void)o; (void)a; [order appendString:@"B"]; });
        CFRunLoopObserverRef early = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopEntry, true, 10,
            ^(CFRunLoopObserverRef o, CFRunLoopActivity a) { (void)o; (void)a; [order appendString:@"A"]; });
        __block int once = 0;
        CFRunLoopObserverRef oneShot = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeTimers, false, 0,
            ^(CFRunLoopObserverRef o, CFRunLoopActivity a) { (void)o; (void)a; once++; });

        CFRunLoopAddObserver(rl, all, kCFRunLoopDefaultMode);
        CFRunLoopAddObserver(rl, late, kCFRunLoopCommonModes);
        CFRunLoopAddObserver(rl, early, kCFRunLoopCommonModes);
        CFRunLoopAddObserver(rl, oneShot, kCFRunLoopDefaultMode);
        printf("contains: %d %d\n", CFRunLoopContainsObserver(rl, all, kCFRunLoopDefaultMode),
               CFRunLoopContainsObserver(rl, early, kCFRunLoopCommonModes));

        /* a timer keeps the loop running and makes it wait */
        __block int fired = 0;
        NSTimer *t = [NSTimer timerWithTimeInterval:0.05 repeats:NO block:^(NSTimer *timer) { (void)timer; fired++; }];
        [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        printf("timer fired: %d\n", fired);
        printf("entry seen: %d exit seen: %d\n", counts[0] > 0, counts[5] > 0);
        printf("entries match exits: %d\n", counts[0] == counts[5]);
        printf("before timers and sources: %d %d\n", counts[1] > 0, counts[2] > 0);
        printf("waited: %d %d\n", counts[3] > 0, counts[3] == counts[4]);
        printf("unknown activities: %d\n", counts[6]);
        printf("order: %s\n", [[order substringToIndex:2] UTF8String]);
        printf("one-shot told once: %d, still valid: %d, still in loop: %d\n", once,
               CFRunLoopObserverIsValid(oneShot), CFRunLoopContainsObserver(rl, oneShot, kCFRunLoopDefaultMode));

        /* removed and invalidated observers hear nothing more */
        CFRunLoopRemoveObserver(rl, late, kCFRunLoopCommonModes);
        CFRunLoopObserverInvalidate(all);
        printf("after remove/invalidate: in %d %d, valid %d\n", CFRunLoopContainsObserver(rl, late, kCFRunLoopCommonModes),
               CFRunLoopContainsObserver(rl, all, kCFRunLoopDefaultMode), CFRunLoopObserverIsValid(all));
        int entries = counts[0];
        NSUInteger len = [order length];
        printf("empty loop runs: %d\n", [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                                                beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]);
        printf("empty loop told no one: %d\n", [order length] == len);
        [[NSRunLoop currentRunLoop] addTimer:[NSTimer timerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *x) { (void)x; }]
                                     forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        printf("silent after: %d, early still told: %d\n", counts[0] == entries, [order length] > len);

        CFRunLoopRemoveObserver(rl, early, kCFRunLoopCommonModes);
        CFRelease(late);
        CFRelease(early);
        CFRelease(oneShot);
        CFRelease(all);
        printf("released context: %d\n", released);
    }
    return 0;
}
