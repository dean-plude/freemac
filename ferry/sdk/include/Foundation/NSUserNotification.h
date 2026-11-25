/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSUserNotification, NSUserNotificationAction and
 * NSUserNotificationCenter, the older notification calls. On a Mac they are
 * part of Foundation; Ferry serves them from its AppKit file
 * (appkit/NSUserNotification.m), because they show notifications through
 * the desktop's notification server over D-Bus, which AppKit reaches. This
 * header is imported by AppKit.h. Written for freemac from Apple's public
 * API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSUSERNOTIFICATION_H_
#define _FERRY_FOUNDATION_NSUSERNOTIFICATION_H_
#import <Foundation/Foundation.h>

@class NSImage, NSUserNotificationCenter;

typedef NS_ENUM(NSInteger, NSUserNotificationActivationType) {
    NSUserNotificationActivationTypeNone = 0,
    NSUserNotificationActivationTypeContentsClicked = 1,
    NSUserNotificationActivationTypeActionButtonClicked = 2,
    NSUserNotificationActivationTypeReplied = 3,
    NSUserNotificationActivationTypeAdditionalActionClicked = 4,
};

FOUNDATION_EXPORT NSString *const NSUserNotificationDefaultSoundName;

@interface NSUserNotificationAction : NSObject <NSCopying>
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *title;
@end

@interface NSUserNotification : NSObject <NSCopying>
@property (copy) NSString *title;
@property (copy) NSString *subtitle;
@property (copy) NSString *informativeText;
@property (copy) NSString *actionButtonTitle;
@property (copy) NSString *otherButtonTitle;
@property (copy) NSDictionary<NSString *, id> *userInfo;
@property (copy) NSDate *deliveryDate;
@property (copy) NSTimeZone *deliveryTimeZone;
@property (copy) NSDateComponents *deliveryRepeatInterval;
@property (readonly, copy) NSDate *actualDeliveryDate;
@property (readonly, getter=isPresented) BOOL presented;
@property (readonly, getter=isRemote) BOOL remote;
@property (copy) NSString *soundName;
@property BOOL hasActionButton;
@property (readonly) NSUserNotificationActivationType activationType;
@property (copy) NSImage *contentImage;
@property (copy) NSString *identifier;
@property BOOL hasReplyButton;
@property (copy) NSString *responsePlaceholder;
@property (readonly, copy) NSAttributedString *response;
@property (copy) NSArray<NSUserNotificationAction *> *additionalActions;
@property (readonly, copy) NSUserNotificationAction *additionalActivationAction;
@end

@protocol NSUserNotificationCenterDelegate <NSObject>
@optional
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
        didDeliverNotification:(NSUserNotification *)notification;
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification;
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification;
@end

@interface NSUserNotificationCenter : NSObject
@property (class, readonly, strong) NSUserNotificationCenter * FERRY_SWIFT_NONNULL defaultUserNotificationCenter;
@property (assign) id<NSUserNotificationCenterDelegate> delegate;
@property (copy) NSArray<NSUserNotification *> *scheduledNotifications;
- (void)scheduleNotification:(NSUserNotification *)notification;
- (void)removeScheduledNotification:(NSUserNotification *)notification;
@property (readonly, copy) NSArray<NSUserNotification *> *deliveredNotifications;
- (void)deliverNotification:(NSUserNotification *)notification;
- (void)removeDeliveredNotification:(NSUserNotification *)notification;
- (void)removeAllDeliveredNotifications;
@end

#endif
