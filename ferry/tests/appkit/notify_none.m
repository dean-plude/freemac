// SPDX-License-Identifier: GPL-3.0-or-later
// Notifications and the Dock with no notification server, and with no
// session bus at all: nothing is shown, but every call still answers and
// the program carries on. Run twice by tests/run.sh, once by
// notifications.sh with fake_notify.py --no-server (a bus, and a stand-in
// Dock that hears the badge), and once with no bus; with FERRY_VERBOSE set,
// Ferry says once why nothing is shown.
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

static BOOL wait_until(double seconds, BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

@interface Delegate : NSObject <UNUserNotificationCenterDelegate, NSUserNotificationCenterDelegate>
@property int delivered;
@end

@implementation Delegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))handler
{
    printf("a response, with no server?\n");
    handler();
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)n
{
    self.delivered++;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)n
{
    printf("an activation, with no server?\n");
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        [NSApp deactivate];
        Delegate *delegate = [[Delegate alloc] init];
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = delegate;
        __block int answers = 0;
        [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                              completionHandler:^(BOOL granted, NSError *error) {
                                  dispatch_async(dispatch_get_main_queue(), ^{
                                      printf("authorization granted: %s\n", granted ? "yes" : "no");
                                      answers++;
                                  });
                              }];
        wait_until(5, ^{ return (BOOL)(answers == 1); });
        for (int i = 0; i < 3; i++) {
            UNMutableNotificationContent *c = [[UNMutableNotificationContent alloc] init];
            c.title = [NSString stringWithFormat:@"Message %d", i + 1];
            c.body = @"Nobody shows this";
            UNTimeIntervalNotificationTrigger *t = i == 2 ? [UNTimeIntervalNotificationTrigger
                                                                triggerWithTimeInterval:0.2 repeats:NO]
                                                          : nil;
            [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:c.title content:c trigger:t]
                     withCompletionHandler:^(NSError *error) {
                         dispatch_async(dispatch_get_main_queue(), ^{
                             answers++;
                         });
                     }];
        }
        wait_until(5, ^{ return (BOOL)(answers == 4); });
        printf("added: %d answered\n", answers - 1);
        wait_until(0.5, ^{ return NO; });
        [center removeAllDeliveredNotifications];
        [center setBadgeCount:2 withCompletionHandler:nil];

        NSUserNotificationCenter *old = [NSUserNotificationCenter defaultUserNotificationCenter];
        old.delegate = delegate;
        for (int i = 0; i < 2; i++) {
            NSUserNotification *n = [[NSUserNotification alloc] init];
            n.title = @"Still delivered";
            n.actionButtonTitle = @"Open";
            [old deliverNotification:n];
        }
        wait_until(0.3, ^{ return NO; });
        printf("NSUserNotification: delegate told of %d, %lu in the list\n", delegate.delivered,
               (unsigned long)old.deliveredNotifications.count);
        [old removeAllDeliveredNotifications];

        NSApp.dockTile.badgeLabel = @"3";
        NSInteger request = [NSApp requestUserAttention:NSCriticalRequest];
        printf("attention request: %s\n", request ? "an id" : "none");
        [NSApp cancelUserAttentionRequest:request];
        wait_until(0.3, ^{ return NO; });
        printf("done\n");
    }
    return 0;
}
