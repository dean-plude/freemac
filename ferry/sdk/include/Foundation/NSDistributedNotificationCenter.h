/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSDistributedNotificationCenter
 * (foundation/NSDistributedNotificationCenter.m), carried between programs
 * on the D-Bus session bus. Written for freemac from Apple's public API
 * documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSDISTRIBUTEDNOTIFICATIONCENTER_H_
#define _FERRY_FOUNDATION_NSDISTRIBUTEDNOTIFICATIONCENTER_H_
#include <Foundation/Foundation.h>

typedef NSString *NSDistributedNotificationCenterType;
FOUNDATION_EXPORT NSDistributedNotificationCenterType const NSLocalNotificationCenterType;

typedef NS_ENUM(NSUInteger, NSNotificationSuspensionBehavior) {
    NSNotificationSuspensionBehaviorDrop = 1,
    NSNotificationSuspensionBehaviorCoalesce = 2,
    NSNotificationSuspensionBehaviorHold = 3,
    NSNotificationSuspensionBehaviorDeliverImmediately = 4,
};

typedef NS_OPTIONS(NSUInteger, NSDistributedNotificationOptions) {
    NSDistributedNotificationDeliverImmediately = 1UL << 0,
    NSDistributedNotificationPostToAllSessions = 1UL << 1,
};

@interface NSDistributedNotificationCenter : NSNotificationCenter
+ (NSDistributedNotificationCenter *)notificationCenterForType:(NSDistributedNotificationCenterType)type;
+ (NSDistributedNotificationCenter *)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(NSString *)object
    suspensionBehavior:(NSNotificationSuspensionBehavior)suspensionBehavior;
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(NSString *)object;
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)userInfo
          deliverImmediately:(BOOL)deliverImmediately;
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)userInfo
                     options:(NSDistributedNotificationOptions)options;
- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object;
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)userInfo;
- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(NSString *)object;
@property BOOL suspended;
@end

#endif
