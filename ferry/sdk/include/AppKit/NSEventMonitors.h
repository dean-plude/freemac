/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: event monitors (appkit/NSEvent.m), written from Apple's public
 * documentation (freemac 1.215, Ferry 0.41.0). A local monitor sees the
 * events the app sends itself through sendEvent:, and may change or drop
 * them. A global monitor sees no other app's keys on freemac: only the
 * app's own registered hotkeys, as key-down events. */
#import <AppKit/AppKit.h>

@interface NSEvent (FerryMonitors)
+ (id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask
                                   handler:(NSEvent * FERRY_SWIFT_NULLABLE (^)(NSEvent * FERRY_SWIFT_NONNULL event))block;
+ (id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^)(NSEvent * FERRY_SWIFT_NONNULL event))block;
+ (void)removeMonitor:(id)eventMonitor;
+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)delay withPeriod:(NSTimeInterval)period;
+ (void)stopPeriodicEvents;
@end
