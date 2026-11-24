// SPDX-License-Identifier: GPL-3.0-or-later
// NSUserNotificationCenter over the desktop's notification server:
// delivering, scheduling and removing, the buttons, a reply and more
// actions, and the delegate's three calls. Run by notifications.sh, whose
// stand-in server (fake_notify.py) clicks and replies to some of them.
#import <Cocoa/Cocoa.h>

static NSMutableArray *activated, *told;

static BOOL wait_until(double seconds, BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

static void pause_a_moment(void)
{
    wait_until(0.3, ^{ return NO; });
}

static void list(const char *what, NSArray *notes)
{
    printf("%s: %s\n", what, [[[notes valueForKey:@"title"] componentsJoinedByString:@", "] UTF8String]);
}

@interface Delegate : NSObject <NSUserNotificationCenterDelegate>
@property BOOL present;
@end

@implementation Delegate
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)n
{
    printf("should present \"%s\"? %s (the app is in front)\n", n.title.UTF8String, self.present ? "yes" : "no");
    return self.present;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)n
{
    printf("delivered \"%s\", presented: %s, has a delivery date: %s\n", n.title.UTF8String,
           n.presented ? "yes" : "no", n.actualDeliveryDate ? "yes" : "no");
    [told addObject:n.title];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)n
{
    NSMutableString *line = [NSMutableString stringWithFormat:@"activated \"%@\": type %ld", n.title,
                                                              (long)n.activationType];
    if (n.response)
        [line appendFormat:@", response \"%@\"", n.response.string];
    if (n.additionalActivationAction)
        [line appendFormat:@", action %@ (%@)", n.additionalActivationAction.identifier,
                           n.additionalActivationAction.title];
    if (n.userInfo)
        [line appendFormat:@", userInfo %@", n.userInfo[@"build"]];
    printf("%s; app active: %s\n", line.UTF8String, NSApp.isActive ? "yes" : "no");
    [activated addObject:n.title];
    [NSApp deactivate];
}
@end

static NSUserNotification *note(NSString *title, NSString *text)
{
    NSUserNotification *n = [[NSUserNotification alloc] init];
    n.title = title;
    n.informativeText = text;
    return n;
}

static void activated_by(NSString *title)
{
    if (!wait_until(5, ^{ return [activated containsObject:title]; }))
        printf("\"%s\" was not activated\n", title.UTF8String);
}

int main(void)
{
    @autoreleasepool {
        activated = [NSMutableArray array];
        told = [NSMutableArray array];
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        [NSApp deactivate];
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        Delegate *delegate = [[Delegate alloc] init];
        center.delegate = delegate;

        NSUserNotification *plain = [[NSUserNotification alloc] init];
        printf("defaults: action button %s \"%s\", other \"%s\", sound %s, activation %ld\n",
               plain.hasActionButton ? "yes" : "no", plain.actionButtonTitle.UTF8String,
               plain.otherButtonTitle.UTF8String, plain.soundName ? "some" : "none", (long)plain.activationType);

        // The action button, with another button and a sound.
        NSUserNotification *n = note(@"Build finished", @"All 12 targets <built>");
        n.subtitle = @"freemac";
        n.actionButtonTitle = @"Open";
        n.otherButtonTitle = @"Later";
        n.soundName = NSUserNotificationDefaultSoundName;
        n.userInfo = @{@"build" : @42};
        [center deliverNotification:n];
        printf("delivered list straight after: %lu\n", (unsigned long)center.deliveredNotifications.count);
        activated_by(@"Build finished");
        list("delivered after the click", center.deliveredNotifications);

        // A reply.
        n = note(@"Ping", @"Are you there?");
        n.hasReplyButton = YES;
        n.responsePlaceholder = @"Say something";
        [center deliverNotification:n];
        activated_by(@"Ping");

        // More actions.
        n = note(@"Choices", @"Pick one");
        n.additionalActions = @[
            [NSUserNotificationAction actionWithIdentifier:@"copy" title:@"Copy"],
            [NSUserNotificationAction actionWithIdentifier:@"share" title:@"Share"],
        ];
        [center deliverNotification:n];
        activated_by(@"Choices");

        // The other button closes it, and the delegate doesn't hear of it.
        n = note(@"Not now", @"Closed with the other button");
        n.otherButtonTitle = @"Close";
        [center deliverNotification:n];
        wait_until(5, ^{ return (BOOL)![[center.deliveredNotifications valueForKey:@"title"] containsObject:@"Not now"]; });
        list("delivered after the other button", center.deliveredNotifications);
        // The notification itself clicked.
        [center deliverNotification:note(@"Click me", @"Anywhere")];
        activated_by(@"Click me");
        list("delivered", center.deliveredNotifications);

        // Scheduled half a second on, and one an hour on that is taken back.
        n = note(@"Scheduled", @"Half a second later");
        n.deliveryDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
        [center scheduleNotification:n];
        NSUserNotification *hour = note(@"In an hour", @"");
        hour.deliveryDate = [NSDate dateWithTimeIntervalSinceNow:3600];
        [center scheduleNotification:hour];
        list("scheduled", center.scheduledNotifications);
        [center removeScheduledNotification:hour];
        list("scheduled after removing one", center.scheduledNotifications);
        wait_until(5, ^{ return [told containsObject:@"Scheduled"]; });
        list("scheduled after it was delivered", center.scheduledNotifications);
        list("delivered", center.deliveredNotifications);

        // Removed after delivery: closed on the server.
        pause_a_moment();
        [center removeDeliveredNotification:n];
        list("delivered after removing it", center.deliveredNotifications);

        // The same identifier again replaces the one on screen.
        n = note(@"Download", @"50%");
        n.identifier = @"download";
        [center deliverNotification:n];
        pause_a_moment();
        n = note(@"Download", @"Done");
        n.identifier = @"download";
        [center deliverNotification:n];
        pause_a_moment();
        list("delivered", center.deliveredNotifications);

        // With the app in front the delegate decides.
        [NSApp activateIgnoringOtherApps:YES];
        [center deliverNotification:note(@"Kept quiet", @"Not shown")];
        delegate.present = YES;
        [center deliverNotification:note(@"Shown anyway", @"The delegate said yes")];
        pause_a_moment();
        list("delivered", center.deliveredNotifications);
        [center removeAllDeliveredNotifications];
        list("delivered after removing all", center.deliveredNotifications);
        pause_a_moment();
        printf("done\n");
    }
    return 0;
}
