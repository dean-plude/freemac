/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * AppKit names the nine apps need to link and start, written from Apple's
 * public documentation: remote (push) notifications, which freemac has no
 * service for, so registering for them always fails, telling the delegate
 * so from the run loop. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_APPS_H_
#define _FERRY_APPKIT_APPS_H_

typedef NS_OPTIONS(NSUInteger, NSRemoteNotificationType) {
    NSRemoteNotificationTypeNone = 0,
    NSRemoteNotificationTypeBadge = 1 << 0,
    NSRemoteNotificationTypeSound = 1 << 1,
    NSRemoteNotificationTypeAlert = 1 << 2,
};

@interface NSApplication (NSRemoteNotifications)
/* The delegate's application:didFailToRegisterForRemoteNotificationsWithError:
 * is called next time round the run loop, with NSCocoaErrorDomain's 3010. */
- (void)registerForRemoteNotifications;
- (void)registerForRemoteNotificationTypes:(NSRemoteNotificationType)types;
- (void)unregisterForRemoteNotifications;
@property (readonly, getter=isRegisteredForRemoteNotifications) BOOL registeredForRemoteNotifications;
@property (readonly) NSRemoteNotificationType enabledRemoteNotificationTypes;
@end

@protocol NSApplicationRemoteNotificationDelegate <NSObject>
@optional
- (void)application:(NSApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)application:(NSApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
- (void)application:(NSApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo;
@end

#endif
