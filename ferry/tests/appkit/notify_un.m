// SPDX-License-Identifier: GPL-3.0-or-later
// UNUserNotificationCenter over the desktop's notification server:
// authorization and settings, categories, the three kinds of trigger, the
// pending and delivered lists, removing, the badge, and the delegate hearing
// what the user did. Run by notifications.sh, which starts a stand-in
// server (fake_notify.py) that clicks, replies to and dismisses some of them.
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

static NSMutableArray *heard;

/* Runs the main run loop until the block says yes, or the time is up. */
static BOOL wait_until(double seconds, BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

/* Sends a call whose handler runs on another queue, and waits for it. */
static id answer(void (^call)(void (^give)(id)))
{
    __block id got = nil;
    __block BOOL back = NO;
    call(^(id value) {
        dispatch_async(dispatch_get_main_queue(), ^{
            got = value;
            back = YES;
        });
    });
    if (!wait_until(5, ^{ return back; }))
        printf("no answer\n");
    return got;
}

static NSArray *pending(void)
{
    NSArray *requests = answer(^(void (^give)(id)) {
        [[UNUserNotificationCenter currentNotificationCenter]
            getPendingNotificationRequestsWithCompletionHandler:^(NSArray *r) { give(r); }];
    });
    return [requests valueForKey:@"identifier"];
}

static NSArray *delivered(void)
{
    NSArray *notes = answer(^(void (^give)(id)) {
        [[UNUserNotificationCenter currentNotificationCenter]
            getDeliveredNotificationsWithCompletionHandler:^(NSArray *n) { give(n); }];
    });
    return [notes valueForKeyPath:@"request.identifier"];
}

static void list(const char *what, NSArray *idents)
{
    printf("%s: %s\n", what, [[idents componentsJoinedByString:@", "] UTF8String]);
}

@interface Delegate : NSObject <UNUserNotificationCenterDelegate>
@property UNNotificationPresentationOptions options;
@end

@implementation Delegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))handler
{
    printf("will present %s (the app is in front)\n", notification.request.identifier.UTF8String);
    handler(self.options);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))handler
{
    NSString *line = [NSString stringWithFormat:@"%@ -> %@", response.notification.request.identifier,
                                                response.actionIdentifier];
    if ([response isKindOfClass:[UNTextInputNotificationResponse class]])
        line = [line stringByAppendingFormat:@" text \"%@\"", ((UNTextInputNotificationResponse *)response).userText];
    id thread = response.notification.request.content.userInfo[@"thread"];
    if (thread)
        line = [line stringByAppendingFormat:@" (userInfo thread %@)", thread];
    printf("response %s; app active: %s\n", line.UTF8String, NSApp.isActive ? "yes" : "no");
    [heard addObject:response.notification.request.identifier];
    handler();
}
@end

static UNMutableNotificationContent *content(NSString *title, NSString *body)
{
    UNMutableNotificationContent *c = [[UNMutableNotificationContent alloc] init];
    c.title = title;
    c.body = body;
    c.sound = [UNNotificationSound defaultSound];
    return c;
}

static void add(NSString *ident, UNNotificationContent *c, UNNotificationTrigger *trigger)
{
    NSError *error = answer(^(void (^give)(id)) {
        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:[UNNotificationRequest requestWithIdentifier:ident content:c trigger:trigger]
             withCompletionHandler:^(NSError *e) { give(e); }];
    });
    printf("added %s: %s\n", ident.UTF8String, error ? error.description.UTF8String : "no error");
}

static void heard_from(NSString *ident)
{
    if (!wait_until(5, ^{ return [heard containsObject:ident]; }))
        printf("no response for %s\n", ident.UTF8String);
}

int main(void)
{
    @autoreleasepool {
        heard = [NSMutableArray array];
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        [NSApp deactivate];
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        printf("same center: %s\n", center == [UNUserNotificationCenter currentNotificationCenter] ? "yes" : "no");
        Delegate *delegate = [[Delegate alloc] init];
        delegate.options = UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound;
        center.delegate = delegate;

        NSArray *auth = answer(^(void (^give)(id)) {
            [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound |
                                                    UNAuthorizationOptionBadge
                                  completionHandler:^(BOOL granted, NSError *error) {
                                      give(@[ @(granted), error ?: [NSNull null], @(!NSThread.isMainThread) ]);
                                  }];
        });
        printf("authorization granted: %s, error: %s, answered off the main thread: %s\n",
               [auth[0] boolValue] ? "yes" : "no", auth[1] == [NSNull null] ? "none" : "some",
               [auth[2] boolValue] ? "yes" : "no");
        UNNotificationSettings *settings = answer(^(void (^give)(id)) {
            [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s) { give(s); }];
        });
        printf("settings: authorization %ld, alert %ld, sound %ld, badge %ld, style %ld, previews %ld\n",
               (long)settings.authorizationStatus, (long)settings.alertSetting, (long)settings.soundSetting,
               (long)settings.badgeSetting, (long)settings.alertStyle, (long)settings.showPreviewsSetting);

        UNNotificationCategory *invite = [UNNotificationCategory
            categoryWithIdentifier:@"INVITE"
                           actions:@[
                               [UNNotificationAction actionWithIdentifier:@"ACCEPT" title:@"Accept"
                                                                  options:UNNotificationActionOptionForeground],
                               [UNNotificationAction actionWithIdentifier:@"DECLINE" title:@"Decline"
                                                                  options:UNNotificationActionOptionDestructive],
                           ]
                 intentIdentifiers:@[]
                           options:0];
        UNNotificationCategory *message = [UNNotificationCategory
            categoryWithIdentifier:@"MESSAGE"
                           actions:@[
                               [UNTextInputNotificationAction actionWithIdentifier:@"REPLY" title:@"Reply" options:0
                                                              textInputButtonTitle:@"Send"
                                                              textInputPlaceholder:@"Your answer"],
                               [UNNotificationAction actionWithIdentifier:@"READ" title:@"Mark as Read" options:0],
                           ]
                 intentIdentifiers:@[]
                           options:UNNotificationCategoryOptionCustomDismissAction];
        [center setNotificationCategories:[NSSet setWithObjects:invite, message, nil]];
        NSSet *categories = answer(^(void (^give)(id)) {
            [center getNotificationCategoriesWithCompletionHandler:^(NSSet *c) { give(c); }];
        });
        list("categories", [[[categories valueForKey:@"identifier"] allObjects]
                               sortedArrayUsingSelector:@selector(compare:)]);

        // Now (no trigger), with actions; the server clicks Accept.
        UNMutableNotificationContent *c = content(@"Lunch?", @"Noon at <Café> & co");
        c.subtitle = @"From Sam";
        c.categoryIdentifier = @"INVITE";
        c.threadIdentifier = @"lunch";
        c.userInfo = @{@"thread" : @"lunch"};
        add(@"invite", c, nil);
        list("pending (a request with no trigger isn't)", pending());
        heard_from(@"invite");
        list("delivered after the click", delivered());
        [NSApp deactivate];

        // A text reply, and a dismissal the category asked to hear about.
        c = content(@"New message", @"Are you coming?");
        c.categoryIdentifier = @"MESSAGE";
        add(@"chat", c, nil);
        heard_from(@"chat");
        add(@"ignored", content(@"Ignored", @"Swiped away"), nil);
        wait_until(5, ^{ return [delivered() containsObject:@"ignored"]; });
        wait_until(5, ^{ return (BOOL)![delivered() containsObject:@"ignored"]; });
        list("delivered after it was swiped away", delivered());
        c = content(@"Dismissed", @"The category wants to know");
        c.categoryIdentifier = @"MESSAGE";
        add(@"dismissed", c, nil);
        heard_from(@"dismissed");
        // The default action: the notification itself clicked.
        add(@"tap", content(@"Tap me", @"Opens the app"), nil);
        heard_from(@"tap");
        list("delivered", delivered());
        [NSApp deactivate];

        // A delayed trigger: pending until it fires half a second later.
        UNTimeIntervalNotificationTrigger *soon = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.5
                                                                                                    repeats:NO];
        add(@"soon", content(@"Half a second later", @""), soon);
        NSTimeInterval wait = [[soon nextTriggerDate] timeIntervalSinceNow];
        printf("time-interval trigger: %.1f s, repeats %s, next in under a second: %s\n", soon.timeInterval,
               soon.repeats ? "yes" : "no", wait > 0 && wait <= 0.5 ? "yes" : "no");
        list("pending", pending());
        wait_until(5, ^{ return [delivered() containsObject:@"soon"]; });
        list("pending after it fired", pending());
        list("delivered", delivered());
        @try {
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:30 repeats:YES];
            printf("a repeating trigger under a minute: taken\n");
        } @catch (NSException *e) {
            printf("a repeating trigger under a minute: %s\n", e.name.UTF8String);
        }

        // A calendar trigger, two seconds on, and one far off that is removed.
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDateComponents *at = [[NSDateComponents alloc] init];
        at.second = [cal component:NSCalendarUnitSecond fromDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        UNCalendarNotificationTrigger *clock = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:at
                                                                                                       repeats:NO];
        printf("calendar trigger next in under three seconds: %s\n",
               [[clock nextTriggerDate] timeIntervalSinceNow] < 3 ? "yes" : "no");
        add(@"clock", content(@"On the second", @"From a calendar trigger"), clock);
        NSDateComponents *morning = [[NSDateComponents alloc] init];
        morning.hour = 9;
        morning.minute = 30;
        UNCalendarNotificationTrigger *daily = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:morning
                                                                                                       repeats:YES];
        NSDateComponents *next = [cal components:NSCalendarUnitHour | NSCalendarUnitMinute
                                        fromDate:[daily nextTriggerDate]];
        printf("daily trigger next at %02ld:%02ld\n", (long)next.hour, (long)next.minute);
        add(@"daily", content(@"Every morning", @""), daily);
        add(@"later", content(@"In an hour", @""),
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:3600 repeats:NO]);
        list("pending", pending());
        [center removePendingNotificationRequestsWithIdentifiers:@[ @"daily" ]];
        list("pending after removing daily", pending());
        wait_until(5, ^{ return [delivered() containsObject:@"clock"]; });
        wait_until(0.3, ^{ return NO; });
        list("pending after the calendar trigger fired", pending());
        [center removeAllPendingNotificationRequests];
        list("pending after removing all", pending());

        // Removing a delivered notification closes it on the server.
        [center removeDeliveredNotificationsWithIdentifiers:@[ @"soon" ]];
        list("delivered after removing soon", delivered());
        // The same identifier again replaces the one on screen.
        c = content(@"On the second", @"Updated");
        add(@"clock", c, nil);
        wait_until(0.3, ^{ return NO; });
        list("delivered", delivered());

        // The badge, from a notification and set directly.
        delegate.options |= UNNotificationPresentationOptionBadge;
        c = content(@"", @"");
        c.badge = @4;
        add(@"badge only", c, nil);
        wait_until(0.3, ^{ return NO; });
        id error = answer(^(void (^give)(id)) {
            [center setBadgeCount:0 withCompletionHandler:^(NSError *e) { give(e ?: [NSNull null]); }];
        });
        printf("badge cleared: %s\n", error == [NSNull null] ? "no error" : "error");

        // With the app in front, the delegate decides: nothing, then a banner.
        [NSApp activateIgnoringOtherApps:YES];
        delegate.options = UNNotificationPresentationOptionNone;
        add(@"quiet", content(@"Not shown", @"The app is in front"), nil);
        wait_until(0.3, ^{ return NO; });
        delegate.options = UNNotificationPresentationOptionBanner;
        add(@"front", content(@"Shown in front", @"The delegate asked for a banner"), nil);
        wait_until(0.3, ^{ return NO; });
        list("delivered", delivered());
        [center removeAllDeliveredNotifications];
        list("delivered after removing all", delivered());
        wait_until(0.3, ^{ return NO; });
        printf("done\n");
    }
    return 0;
}
