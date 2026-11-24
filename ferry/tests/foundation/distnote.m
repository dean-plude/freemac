/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): NSDistributedNotificationCenter.
 * Run on a private session bus, the test starts itself again as a second
 * program (through NSTask) and the two pass notifications, with objects
 * and user info, both ways. Run with "alone" and no session bus, the
 * center works within the program. Either way: observers by name and
 * object, block observers, removal, suspension and the four suspension
 * behaviours, posts delivered at once, and an object that isn't a string.
 * Flycut, Sequel Pro and KeyCastr listen this way for the system's
 * appearance and their own other copies. */
#import <Foundation/Foundation.h>

static NSMutableArray *got;

@interface Ear : NSObject
@property (copy) NSString *tag;
@end
@implementation Ear
- (void)heard:(NSNotification *)n
{
    [got addObject:[NSString stringWithFormat:@"%@:%@%@%@", self.tag, [n name], [n object] ? @"/" : @"",
                                              [n object] ?: @""]];
}
@end

static void spin(NSTimeInterval t) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:t]]; }
static BOOL wait_for(BOOL (^done)(void))
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done() && [limit timeIntervalSinceNow] > 0)
        spin(0.02);
    return done();
}
static void show(const char *what)
{
    spin(0.3);
    NSArray *sorted = [got sortedArrayUsingSelector:@selector(compare:)];
    printf("%s: %s\n", what, [sorted count] ? [[sorted componentsJoinedByString:@" "] UTF8String] : "nothing");
    [got removeAllObjects];
}

static void within(NSDistributedNotificationCenter *c)
{
    Ear *any = [Ear new], *named = [Ear new];
    any.tag = @"any";
    named.tag = @"x";
    [c addObserver:any selector:@selector(heard:) name:@"org.freemac.test.self" object:nil];
    [c addObserver:named selector:@selector(heard:) name:@"org.freemac.test.self" object:@"x"];
    [c postNotificationName:@"org.freemac.test.self" object:@"x"];
    [c postNotificationName:@"org.freemac.test.self" object:@"y"];
    [c postNotificationName:@"org.freemac.test.self" object:nil];
    printf("delivered before the run loop turns: %lu\n", (unsigned long)[got count]);
    show("by name and by object");

    __block NSDictionary *info = nil;
    id token = [c addObserverForName:@"org.freemac.test.info" object:nil queue:nil
                          usingBlock:^(NSNotification *n) {
                            info = [n userInfo];
                          }];
    [c postNotificationName:@"org.freemac.test.info" object:nil
                   userInfo:@{@"count" : @3, @"words" : @[ @"one", @"two" ], @"when" : [NSDate dateWithTimeIntervalSince1970:0]}];
    wait_for(^{ return (BOOL)(info != nil); });
    printf("a block observer's user info: count %d, words %s, a date %s\n", [info[@"count"] intValue],
           [[info[@"words"] componentsJoinedByString:@","] UTF8String],
           [info[@"when"] isKindOfClass:[NSDate class]] ? "yes" : "no");
    [c removeObserver:token];
    info = nil;
    [c postNotificationName:@"org.freemac.test.info" object:nil userInfo:@{@"a" : @1}];
    spin(0.3);
    printf("removed, the block not called: %s\n", info ? "no" : "yes");

    [c removeObserver:named];
    [c postNotificationName:@"org.freemac.test.self" object:@"x"];
    show("one observer removed");
    [c removeObserver:any name:@"org.freemac.test.self" object:nil];

    printf("-- suspended\n");
    NSArray *kinds = @[ @"drop", @"coalesce", @"hold", @"immediate" ];
    NSNotificationSuspensionBehavior behaviours[] = {
        NSNotificationSuspensionBehaviorDrop, NSNotificationSuspensionBehaviorCoalesce,
        NSNotificationSuspensionBehaviorHold, NSNotificationSuspensionBehaviorDeliverImmediately};
    NSMutableArray *ears = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++) {
        Ear *e = [Ear new];
        e.tag = kinds[i];
        [ears addObject:e];
        [c addObserver:e selector:@selector(heard:) name:@"org.freemac.test.held" object:nil
            suspensionBehavior:behaviours[i]];
    }
    printf("suspended at first: %s\n", [c suspended] ? "yes" : "no");
    [c setSuspended:YES];
    [c postNotificationName:@"org.freemac.test.held" object:@"a"];
    [c postNotificationName:@"org.freemac.test.held" object:@"a"];
    [c postNotificationName:@"org.freemac.test.held" object:@"b"];
    show("three posts while suspended");
    [c setSuspended:NO];
    show("then resumed");
    [c setSuspended:YES];
    [c postNotificationName:@"org.freemac.test.held" object:@"c"];
    spin(0.3);
    [c postNotificationName:@"org.freemac.test.held" object:@"now" userInfo:nil deliverImmediately:YES];
    show("one held, then one posted to deliver at once");
    [c setSuspended:NO];
    show("resumed, nothing left");
    for (Ear *e in ears)
        [c removeObserver:e];

    @try {
        [c postNotificationName:@"org.freemac.test.self" object:(id)@5];
        printf("an object that isn't a string: posted\n");
    } @catch (NSException *x) {
        printf("an object that isn't a string: %s\n", [[x name] UTF8String]);
    }
    printf("the local type: %s\n",
           [NSDistributedNotificationCenter notificationCenterForType:NSLocalNotificationCenterType] == c ? "the same center"
                                                                                                         : "another");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        got = [NSMutableArray array];
        NSDistributedNotificationCenter *c = [NSDistributedNotificationCenter defaultCenter];
        if (argc > 1 && !strcmp(argv[1], "child")) {
            /* the second program: says it's ready, answers a ping, then goes */
            __block BOOL done = NO;
            [c addObserverForName:@"org.freemac.test.ping" object:@"parent" queue:nil
                       usingBlock:^(NSNotification *n) {
                         NSMutableDictionary *back = [[n userInfo] mutableCopy];
                         back[@"from"] = @"child";
                         [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"org.freemac.test.pong"
                                                                                        object:@"child"
                                                                                      userInfo:back
                                                                            deliverImmediately:YES];
                         done = YES;
                       }];
            [c postNotificationName:@"org.freemac.test.ready" object:@"child"];
            wait_for(^{ return done; });
            return done ? 0 : 1;
        }
        BOOL alone = argc > 1 && !strcmp(argv[1], "alone");
        within(c);
        if (alone)
            return 0;

        printf("-- between two programs\n");
        __block BOOL ready = NO;
        __block NSNotification *pong = nil;
        Ear *other = [Ear new];
        other.tag = @"ready";
        [c addObserver:other selector:@selector(heard:) name:@"org.freemac.test.ready" object:nil];
        [c addObserverForName:@"org.freemac.test.ready" object:@"child" queue:nil
                   usingBlock:^(NSNotification *n) {
                     ready = YES;
                   }];
        [c addObserverForName:@"org.freemac.test.pong" object:nil queue:nil
                   usingBlock:^(NSNotification *n) {
                     pong = n;
                   }];
        NSTask *t = [[NSTask alloc] init];
        [t setLaunchPath:[[[NSProcessInfo processInfo] arguments] objectAtIndex:0]];
        [t setArguments:@[ @"child" ]];
        [t launch];
        printf("the other program said it was ready: %s\n", wait_for(^{ return ready; }) ? "yes" : "no");
        show("its notification, to an observer of the name");
        [c postNotificationName:@"org.freemac.test.ping" object:@"parent" userInfo:@{@"n" : @42, @"s" : @"hello"}];
        printf("it answered: %s\n", wait_for(^{ return (BOOL)(pong != nil); }) ? "yes" : "no");
        printf("the answer: object %s, n %d, s %s, from %s\n", [[pong object] UTF8String],
               [[pong userInfo][@"n"] intValue], [[pong userInfo][@"s"] UTF8String],
               [[pong userInfo][@"from"] UTF8String]);
        [t waitUntilExit];
        printf("the other program exited %d\n", [t terminationStatus]);
    }
    return 0;
}
