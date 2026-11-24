/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): NSAnimation and
 * NSViewAnimation on the run loop, with no display. Blocking animations
 * return when they end, non-blocking ones run while the run loop turns;
 * the curves, the delegate (may it start, the value for a progress, marks
 * reached, stopped, ended), the progress-mark notification, animations
 * started and stopped by another's marks, and view animations moving,
 * resizing, fading and hiding views and windows. Then the animator proxy
 * and NSAnimationContext, which set their values by the end. KeyCastr and
 * Sequel Pro animate this way. */
#import <Cocoa/Cocoa.h>

static NSMutableString *trail;

@interface Watcher : NSObject <NSAnimationDelegate>
@property BOOL refuse, halve;
@property (weak) NSView *view;
@property CGFloat seenX;
@end
@implementation Watcher
- (BOOL)animationShouldStart:(NSAnimation *)a
{
    [trail appendString:self.refuse ? @"refused; " : @"may start; "];
    return !self.refuse;
}
- (void)animationDidStop:(NSAnimation *)a { [trail appendString:@"stopped; "]; }
- (void)animationDidEnd:(NSAnimation *)a { [trail appendString:@"ended; "]; }
- (void)animation:(NSAnimation *)a didReachProgressMark:(NSAnimationProgress)p
{
    [trail appendFormat:@"mark %g; ", p];
    if (self.view && p == 0.5f)
        self.seenX = [self.view frame].origin.x;
}
- (float)animation:(NSAnimation *)a valueForProgress:(NSAnimationProgress)p
{
    return self.halve ? p / 2 : p;
}
@end

@interface Counted : NSAnimation
@property int frames;
@end
@implementation Counted
- (void)setCurrentProgress:(NSAnimationProgress)p
{
    [super setCurrentProgress:p];
    self.frames++;
}
@end

static void show(const char *what)
{
    printf("%s: %s\n", what, [trail length] ? [trail UTF8String] : "nothing");
    [trail setString:@""];
}
static void spin(NSTimeInterval t) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:t]]; }
static void spin_until(BOOL (^done)(void))
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && [limit timeIntervalSinceNow] > 0)
        spin(0.01);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        trail = [NSMutableString string];

        NSAnimation *plain = [[NSAnimation alloc] initWithDuration:2 animationCurve:NSAnimationEaseIn];
        printf("duration %g, curve %lu, blocking mode %lu, frame rate above 0: %s, progress %g, animating %s\n",
               [plain duration], (unsigned long)[plain animationCurve], (unsigned long)[plain animationBlockingMode],
               [plain frameRate] > 0 ? "yes" : "no", [plain currentProgress], [plain isAnimating] ? "yes" : "no");
        const char *names[] = {"ease in and out", "ease in", "ease out", "linear"};
        for (NSAnimationCurve c = NSAnimationEaseInOut; c <= NSAnimationLinear; c++) {
            [plain setAnimationCurve:c];
            [plain setCurrentProgress:0.25];
            float q = [plain currentValue];
            [plain setCurrentProgress:0.5];
            float h = [plain currentValue];
            [plain setCurrentProgress:1];
            printf("%s: at a quarter %.3f, at half %.3f, at the end %.3f\n", names[c], q, h, [plain currentValue]);
        }
        [plain setCurrentProgress:7];
        printf("progress past the end: %g\n", [plain currentProgress]);
        [plain addProgressMark:0.75];
        [plain addProgressMark:0.25];
        [plain addProgressMark:0.75];
        printf("marks, in order and once each: %s\n", [[[plain progressMarks] description] UTF8String]);
        [plain removeProgressMark:0.75];
        printf("one removed: %lu left\n", (unsigned long)[[plain progressMarks] count]);
        Watcher *w = [Watcher new];
        w.halve = YES;
        [plain setDelegate:w];
        [plain setCurrentProgress:0.5];
        printf("the delegate's value for half way: %.3f\n", [plain currentValue]);
        [plain setDelegate:nil];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:plain requiringSecureCoding:NO error:NULL];
        NSAnimation *back = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        printf("archived: duration %g, marks %lu\n", [back duration], (unsigned long)[[back progressMarks] count]);
        NSAnimation *copy = [plain copy];
        printf("copied: duration %g, curve %lu\n", [copy duration], (unsigned long)[copy animationCurve]);
        @try {
            [plain setDuration:-1];
            printf("a duration below 0: taken\n");
        } @catch (NSException *x) {
            printf("a duration below 0: %s\n", [[x name] UTF8String]);
        }

        printf("-- blocking\n");
        Counted *a = [[Counted alloc] initWithDuration:0.2 animationCurve:NSAnimationLinear];
        [a setDelegate:w];
        w.halve = NO;
        [a setProgressMarks:@[ @0.5, @0.25, @1 ]];
        __block int notes = 0;
        id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSAnimationProgressMarkNotification
                        object:a
                         queue:nil
                    usingBlock:^(NSNotification *n) {
                      if ([n.userInfo[NSAnimationProgressMark] floatValue] > 0)
                          notes++;
                    }];
        NSDate *t0 = [NSDate date];
        [a startAnimation];
        NSTimeInterval took = -[t0 timeIntervalSinceNow];
        show("a blocking animation");
        printf("returned when it ended: %s, after its duration: %s, progress %g, more than three frames: %s, "
               "notifications %d\n",
               [a isAnimating] ? "no" : "yes", took >= 0.18 ? "yes" : "no", [a currentProgress],
               a.frames > 3 ? "yes" : "no", notes);
        [[NSNotificationCenter defaultCenter] removeObserver:obs];
        w.refuse = YES;
        [a startAnimation];
        show("one its delegate won't let start");
        printf("progress after: %g\n", [a currentProgress]);
        w.refuse = NO;

        printf("-- non-blocking\n");
        Counted *n = [[Counted alloc] initWithDuration:0.3 animationCurve:NSAnimationEaseInOut];
        [n setAnimationBlockingMode:NSAnimationNonblocking];
        [n setDelegate:w];
        [n startAnimation];
        printf("returned at once: %s\n", [n isAnimating] ? "yes" : "no");
        spin(0.1);
        [n stopAnimation];
        float stoppedAt = [n currentProgress];
        show("stopped a third of the way");
        printf("stopped part way: %s, still animating: %s\n", stoppedAt > 0 && stoppedAt < 1 ? "yes" : "no",
               [n isAnimating] ? "yes" : "no");
        [n startAnimation];
        spin(0.02);
        printf("started again, it goes on from there: %s\n", [n currentProgress] >= stoppedAt ? "yes" : "no");
        spin_until(^{ return (BOOL)![n isAnimating]; });
        show("then to the end");
        printf("progress %g\n", [n currentProgress]);
        [n startAnimation];
        printf("started after its end, it starts over: %s\n", [n currentProgress] < 1 ? "yes" : "no");
        [n stopAnimation];
        [trail setString:@""];

        printf("-- one animation starting and stopping others\n");
        Counted *first = [[Counted alloc] initWithDuration:0.2 animationCurve:NSAnimationLinear];
        Counted *second = [[Counted alloc] initWithDuration:5 animationCurve:NSAnimationLinear];
        Counted *third = [[Counted alloc] initWithDuration:5 animationCurve:NSAnimationLinear];
        for (NSAnimation *x in @[ first, second, third ])
            [x setAnimationBlockingMode:NSAnimationNonblocking];
        [second startWhenAnimation:first reachesProgress:0.5];
        [third startAnimation];
        [third stopWhenAnimation:first reachesProgress:0.75];
        printf("the first's marks: %s\n", [[[first progressMarks] description] UTF8String]);
        [first startAnimation];
        spin_until(^{ return (BOOL)![first isAnimating]; });
        printf("the second started at half way: %s, the third stopped: %s\n", [second isAnimating] ? "yes" : "no",
               [third isAnimating] ? "no" : "yes");
        [second stopAnimation];
        [second clearStartAnimation];
        [first startAnimation];
        spin_until(^{ return (BOOL)![first isAnimating]; });
        printf("cleared, the second not started again: %s\n", [second isAnimating] ? "no" : "yes");

        printf("-- view animations\n");
        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        [win setReleasedWhenClosed:NO];
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSView *fader = [[NSView alloc] initWithFrame:NSMakeRect(0, 50, 10, 10)];
        NSView *hiddenOne = [[NSView alloc] initWithFrame:NSMakeRect(0, 80, 10, 10)];
        NSView *shrink = [[NSView alloc] initWithFrame:NSMakeRect(0, 110, 10, 10)];
        [hiddenOne setHidden:YES];
        for (NSView *v in @[ box, fader, hiddenOne, shrink ])
            [[win contentView] addSubview:v];
        NSViewAnimation *va = [[NSViewAnimation alloc] initWithViewAnimations:@[
            @{NSViewAnimationTargetKey : box, NSViewAnimationEndFrameKey : [NSValue valueWithRect:NSMakeRect(100, 0, 30, 20)]},
            @{NSViewAnimationTargetKey : fader, NSViewAnimationEffectKey : NSViewAnimationFadeOutEffect},
            @{NSViewAnimationTargetKey : hiddenOne, NSViewAnimationEffectKey : NSViewAnimationFadeInEffect},
            @{NSViewAnimationTargetKey : shrink, NSViewAnimationEndFrameKey : [NSValue valueWithRect:NSZeroRect]},
        ]];
        printf("a view animation: duration %g, curve %lu, %lu views\n", [va duration], (unsigned long)[va animationCurve],
               (unsigned long)[[va viewAnimations] count]);
        [va setDuration:0.2];
        [va setAnimationCurve:NSAnimationLinear];
        [va addProgressMark:0.5];
        w.view = box;
        [va setDelegate:w];
        [va startAnimation];
        show("it ran");
        printf("half way, the box between its frames: %s\n", w.seenX > 10 && w.seenX < 90 ? "yes" : "no");
        printf("the box: %s\n", [NSStringFromRect([box frame]) UTF8String]);
        printf("faded out: hidden %s, alpha %g\n", [fader isHidden] ? "yes" : "no", [fader alphaValue]);
        printf("faded in: hidden %s, alpha %g\n", [hiddenOne isHidden] ? "yes" : "no", [hiddenOne alphaValue]);
        printf("to an empty frame: hidden %s\n", [shrink isHidden] ? "yes" : "no");
        NSViewAnimation *wa = [[NSViewAnimation alloc] initWithViewAnimations:@[ @{
            NSViewAnimationTargetKey : win,
            NSViewAnimationStartFrameKey : [NSValue valueWithRect:NSMakeRect(10, 10, 200, 100)],
            NSViewAnimationEndFrameKey : [NSValue valueWithRect:NSMakeRect(40, 30, 260, 140)]
        } ]];
        [wa setDuration:0.1];
        [wa startAnimation];
        printf("a window moved and resized: %s\n", [NSStringFromRect([win frame]) UTF8String]);

        printf("-- the animator proxy and NSAnimationContext\n");
        NSView *slid = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [[win contentView] addSubview:slid];
        __block BOOL finished = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
          [ctx setDuration:0.1];
          [[slid animator] setFrameOrigin:NSMakePoint(50, 60)];
          [[slid animator] setAlphaValue:0.5];
        }
            completionHandler:^{
              finished = YES;
            }];
        spin_until(^{ return finished; });
        printf("after the group: origin %s, alpha %g, completion ran %s\n",
               [NSStringFromPoint([slid frame].origin) UTF8String], [slid alphaValue], finished ? "yes" : "no");
        [[slid animator] setFrameSize:NSMakeSize(30, 40)];
        spin(0.4);
        printf("outside a group, by the end: size %s\n", [NSStringFromSize([slid frame].size) UTF8String]);
        [win close];
    }
    return 0;
}
