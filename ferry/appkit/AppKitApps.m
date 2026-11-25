/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit calls the nine apps need to link and start (see
 * sdk/include/AppKit/AppKitApps.h), written for freemac from Apple's
 * public documentation.
 *
 * Remote notifications: freemac has no push notification service, so a
 * registration always fails. As on a Mac, the answer comes later: the
 * delegate hears of it the next time round the main run loop. */
#import "AInternal.h"

@implementation NSApplication (NSRemoteNotifications)
- (void)_ferryRemoteNotificationsFailed
{
    id delegate = [self delegate];
    SEL sel = @selector(application:didFailToRegisterForRemoteNotificationsWithError:);
    if (![delegate respondsToSelector:sel])
        return;
    NSDictionary *info = @{
        NSLocalizedDescriptionKey : @"Remote notifications aren't available: there is no push notification service "
                                    @"on this system."
    };
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:3010 userInfo:info];
    ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, sel, self, error);
}
- (void)registerForRemoteNotifications
{
    [[NSRunLoop mainRunLoop] performSelector:@selector(_ferryRemoteNotificationsFailed) target:self argument:nil
                                       order:0 modes:@[ NSRunLoopCommonModes ]];
}
- (void)registerForRemoteNotificationTypes:(NSRemoteNotificationType)types
{
    [self registerForRemoteNotifications];
}
- (void)unregisterForRemoteNotifications
{
}
- (BOOL)isRegisteredForRemoteNotifications { return NO; }
- (NSRemoteNotificationType)enabledRemoteNotificationTypes { return NSRemoteNotificationTypeNone; }
@end
