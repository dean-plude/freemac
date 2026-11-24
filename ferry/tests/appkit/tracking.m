/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): tracking areas, tracking
 * rectangles, cursor rectangles and cursors, with no display, by mouse
 * events sent to a window. Entered, exited, moved and cursor-update
 * messages reach an area's owner as its options say: always, in the key
 * window or while first responder, assumed inside, in the visible rect,
 * during drags or only after them. Overlapping views each get theirs,
 * exits come before entries, hidden views get none, updateTrackingAreas
 * follows frame changes and moves to a window, and the older tracking
 * rectangles carry their tags and user data. This is what Spectacle's
 * shortcut recorder, MacPass's and Gas Mask's table rows and Sequel Pro's
 * tab bar do with them. */
#import <Cocoa/Cocoa.h>

static NSMutableString *trail;

@interface Spot : NSView
@property (copy) NSString *name;
@property int updates, resets;
@property (strong) NSCursor *rectCursor;
@end
@implementation Spot
- (void)note:(NSString *)what event:(NSEvent *)e
{
    [trail appendFormat:@"%@ %@%@; ", self.name, what,
                        [e type] == NSEventTypeMouseEntered || [e type] == NSEventTypeMouseExited
                            ? ([e trackingArea] ? @"" : [NSString stringWithFormat:@" #%ld", (long)[e trackingNumber]])
                            : @""];
}
- (void)mouseEntered:(NSEvent *)e { [self note:@"entered" event:e]; }
- (void)mouseExited:(NSEvent *)e { [self note:@"exited" event:e]; }
- (void)mouseMoved:(NSEvent *)e { [self note:@"moved" event:e]; }
- (void)cursorUpdate:(NSEvent *)e
{
    [self note:@"cursor" event:e];
    [[NSCursor IBeamCursor] set];
}
- (void)updateTrackingAreas
{
    self.updates++;
    [super updateTrackingAreas];
}
- (void)resetCursorRects
{
    self.resets++;
    if (self.rectCursor)
        [self addCursorRect:NSMakeRect(0, 0, 10, 10) cursor:self.rectCursor];
}
@end

/* An owner that keeps the last event it was sent. */
@interface Last : NSObject
@property (strong) NSEvent *event;
@end
@implementation Last
- (void)mouseEntered:(NSEvent *)e { self.event = e; }
- (void)mouseExited:(NSEvent *)e { self.event = e; }
@end

static NSWindow *win;

static void send(NSEventType type, CGFloat x, CGFloat y)
{
    [win sendEvent:[NSEvent mouseEventWithType:type location:NSMakePoint(x, y) modifierFlags:0 timestamp:0
                                  windowNumber:[win windowNumber] context:nil eventNumber:0 clickCount:1
                                      pressure:type == NSEventTypeMouseMoved ? 0 : 1]];
}
static void move(CGFloat x, CGFloat y) { send(NSEventTypeMouseMoved, x, y); }
static void show(const char *what)
{
    printf("%s: %s\n", what, [trail length] ? [trail UTF8String] : "nothing");
    [trail setString:@""];
}
static void spin(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }

static Spot *spot(NSString *name, NSRect frame)
{
    Spot *s = [[Spot alloc] initWithFrame:frame];
    s.name = name;
    [[win contentView] addSubview:s];
    return s;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        trail = [NSMutableString string];
        win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered defer:NO];
        [win setReleasedWhenClosed:NO];
        [win makeKeyAndOrderFront:nil];
        printf("window takes mouse-moved events: %s\n", [win acceptsMouseMovedEvents] ? "yes" : "no");

        Spot *a = spot(@"a", NSMakeRect(10, 10, 40, 40));
        NSDictionary *info = @{@"row" : @3};
        NSTrackingArea *area = [[NSTrackingArea alloc]
            initWithRect:[a bounds]
                 options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways
                   owner:a
                userInfo:info];
        [a addTrackingArea:area];
        printf("areas: %lu, the same one: %s, its options 0x%lx, owner a: %s, user info kept: %s\n",
               (unsigned long)[[a trackingAreas] count], [a trackingAreas][0] == area ? "yes" : "no",
               (unsigned long)[area options], [area owner] == a ? "yes" : "no",
               [[area userInfo] isEqual:info] ? "yes" : "no");
        NSTrackingArea *copy = [area copy];
        printf("a copy: same rect %s, same owner %s, not the same object %s\n",
               NSEqualRects([copy rect], [area rect]) ? "yes" : "no", [copy owner] == a ? "yes" : "no",
               copy != area ? "yes" : "no");

        move(100, 80);
        show("outside");
        move(20, 20);
        show("into a");
        move(30, 30);
        show("moving in a, though the window takes no mouse-moved events");
        move(120, 80);
        show("out of a");

        NSEvent *made = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSMakePoint(1, 2)
                                          modifierFlags:0 timestamp:0 windowNumber:[win windowNumber]
                                                context:nil eventNumber:0 trackingNumber:7
                                               userData:(__bridge void *)info];
        printf("an entered event made by hand: type %ld, tracking number %ld, user data kept %s, no area %s\n",
               (long)[made type], (long)[made trackingNumber], [made userData] == (__bridge void *)info ? "yes" : "no",
               [made trackingArea] ? "no" : "yes");
        Last *last = [Last new];
        NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(60, 10, 30, 30)];
        [[win contentView] addSubview:b];
        NSTrackingArea *ba = [[NSTrackingArea alloc] initWithRect:NSMakeRect(0, 0, 30, 30)
                                                          options:NSTrackingMouseEnteredAndExited |
                                                                  NSTrackingActiveAlways
                                                            owner:last
                                                         userInfo:info];
        [b addTrackingArea:ba];
        move(70, 20);
        NSEvent *e = last.event;
        printf("an owner that isn't a view: entered %s, the area %s, its number is the area %s, user data the user "
               "info %s, at %g,%g, in our window %s\n",
               [e type] == NSEventTypeMouseEntered ? "yes" : "no", [e trackingArea] == ba ? "yes" : "no",
               [e trackingNumber] == (NSInteger)(intptr_t)(__bridge void *)ba ? "yes" : "no",
               [e userData] == (__bridge void *)[ba userInfo] ? "yes" : "no", [e locationInWindow].x,
               [e locationInWindow].y, [e window] == win ? "yes" : "no");
        move(120, 80);
        printf("then exited: %s\n", [last.event type] == NSEventTypeMouseExited ? "yes" : "no");
        [b removeFromSuperview];

        printf("-- overlapping views and the order of exits and entries\n");
        Spot *inner = [[Spot alloc] initWithFrame:NSMakeRect(5, 5, 10, 10)];
        inner.name = @"inner";
        [a addSubview:inner];
        [inner addTrackingArea:[[NSTrackingArea alloc] initWithRect:[inner bounds]
                                                            options:NSTrackingMouseEnteredAndExited |
                                                                    NSTrackingActiveAlways
                                                              owner:inner
                                                           userInfo:nil]];
        move(20, 20);
        show("into inner, inside a");
        move(40, 40);
        show("out of inner, still in a");
        Spot *next = spot(@"next", NSMakeRect(50, 10, 40, 40));
        [next addTrackingArea:[[NSTrackingArea alloc] initWithRect:[next bounds]
                                                           options:NSTrackingMouseEnteredAndExited |
                                                                   NSTrackingActiveAlways
                                                             owner:next
                                                          userInfo:nil]];
        move(60, 30);
        show("from a to the view beside it");
        move(150, 80);
        show("out of both");

        printf("-- when an area is live\n");
        Spot *k = spot(@"key", NSMakeRect(100, 10, 30, 30));
        [k addTrackingArea:[[NSTrackingArea alloc] initWithRect:[k bounds]
                                                        options:NSTrackingMouseEnteredAndExited |
                                                                NSTrackingActiveInKeyWindow
                                                          owner:k
                                                       userInfo:nil]];
        NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        [other setReleasedWhenClosed:NO];
        [other makeKeyAndOrderFront:nil];
        printf("our window is key: %s\n", [win isKeyWindow] ? "yes" : "no");
        move(110, 20);
        show("into an area live in the key window, in a window that isn't key");
        [win makeKeyAndOrderFront:nil];
        move(111, 21);
        show("the window made key, the mouse moved");
        move(150, 80);
        show("out");
        Spot *fr = spot(@"first", NSMakeRect(140, 10, 30, 30));
        [fr addTrackingArea:[[NSTrackingArea alloc] initWithRect:[fr bounds]
                                                         options:NSTrackingMouseEnteredAndExited |
                                                                 NSTrackingActiveWhenFirstResponder
                                                           owner:fr
                                                        userInfo:nil]];
        move(150, 20);
        show("into an area live while its view is first responder, it isn't");
        move(150, 80);
        [trail setString:@""];

        printf("-- assumed inside, the visible rect, hidden views\n");
        Spot *assume = spot(@"assume", NSMakeRect(10, 60, 30, 30));
        [assume addTrackingArea:[[NSTrackingArea alloc] initWithRect:[assume bounds]
                                                             options:NSTrackingMouseEnteredAndExited |
                                                                     NSTrackingActiveAlways | NSTrackingAssumeInside
                                                               owner:assume
                                                            userInfo:nil]];
        move(150, 80);
        show("the first move, outside an area assumed to have the mouse in it");
        Spot *vis = spot(@"visible", NSMakeRect(60, 60, 20, 20));
        [vis addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                          options:NSTrackingMouseEnteredAndExited |
                                                                  NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                            owner:vis
                                                         userInfo:nil]];
        move(85, 70);
        show("beside an area in the visible rect, before the view grows");
        [vis setFrameSize:NSMakeSize(40, 20)];
        move(86, 70);
        show("the view grown under the mouse");
        move(150, 95);
        [trail setString:@""];
        [vis setHidden:YES];
        move(70, 70);
        show("into a hidden view");
        [vis setHidden:NO];
        move(150, 95);
        [trail setString:@""];

        printf("-- drags\n");
        Spot *d = spot(@"drag", NSMakeRect(100, 60, 30, 30));
        [d addTrackingArea:[[NSTrackingArea alloc] initWithRect:[d bounds]
                                                        options:NSTrackingMouseEnteredAndExited |
                                                                NSTrackingActiveAlways
                                                          owner:d
                                                       userInfo:nil]];
        Spot *dd = spot(@"dragToo", NSMakeRect(130, 60, 30, 30));
        [dd addTrackingArea:[[NSTrackingArea alloc] initWithRect:[dd bounds]
                                                         options:NSTrackingMouseEnteredAndExited |
                                                                 NSTrackingActiveAlways |
                                                                 NSTrackingEnabledDuringMouseDrag
                                                           owner:dd
                                                        userInfo:nil]];
        send(NSEventTypeLeftMouseDown, 190, 95);
        send(NSEventTypeLeftMouseDragged, 110, 70);
        show("dragged into an area not enabled during drags");
        send(NSEventTypeLeftMouseDragged, 140, 70);
        show("dragged on into one that is");
        send(NSEventTypeLeftMouseUp, 112, 70);
        show("the button up over the first");
        move(190, 95);
        show("out");

        printf("-- updateTrackingAreas\n");
        Spot *u = [[Spot alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
        u.name = @"u";
        printf("before it is in a window: %d\n", u.updates);
        [[win contentView] addSubview:u];
        spin();
        printf("put in the window, the run loop turned: %d\n", u.updates);
        [u setFrameSize:NSMakeSize(6, 6)];
        [u setFrameSize:NSMakeSize(7, 7)];
        printf("resized twice, not yet told: %d\n", u.updates);
        move(190, 95);
        printf("a mouse event: %d\n", u.updates);
        [[win contentView] setFrameOrigin:NSMakePoint(0, 0)];
        [[win contentView] setBoundsOrigin:NSMakePoint(1, 0)];
        spin();
        printf("its superview's bounds moved: %d\n", u.updates);
        [[win contentView] setBoundsOrigin:NSMakePoint(0, 0)];
        spin();
        u.updates = 0;
        spin();
        printf("nothing changed: %d\n", u.updates);

        printf("-- tracking rectangles\n");
        int datum = 5;
        Spot *r = spot(@"rect", NSMakeRect(170, 60, 20, 20));
        NSTrackingRectTag tag = [r addTrackingRect:[r bounds] owner:r userData:&datum assumeInside:NO];
        NSTrackingRectTag tag2 = [r addTrackingRect:NSMakeRect(0, 0, 5, 5) owner:r userData:NULL assumeInside:YES];
        printf("tags: above 0 %s, different %s; listed as tracking areas: %lu\n", tag > 0 ? "yes" : "no",
               tag2 != tag ? "yes" : "no", (unsigned long)[[r trackingAreas] count]);
        [r removeTrackingRect:tag2];
        [trail setString:@""];
        move(180, 70);
        NSString *entered = [trail copy];
        show("into a tracking rectangle");
        printf("its tag in the event: %s\n",
               [entered containsString:[NSString stringWithFormat:@"#%ld", (long)tag]] ? "yes" : "no");
        [r removeTrackingRect:tag];
        move(195, 95);
        show("out of it, removed");

        printf("-- cursors\n");
        printf("one arrow: %s, current at first: %s\n", [NSCursor arrowCursor] == [NSCursor arrowCursor] ? "yes" : "no",
               [NSCursor currentCursor] == [NSCursor arrowCursor] ? "the arrow" : "another");
        [[NSCursor pointingHandCursor] push];
        printf("pushed: %s\n", [NSCursor currentCursor] == [NSCursor pointingHandCursor] ? "the hand" : "another");
        [[NSCursor crosshairCursor] push];
        [NSCursor pop];
        printf("one popped: %s\n", [NSCursor currentCursor] == [NSCursor pointingHandCursor] ? "the hand" : "another");
        [NSCursor pop];
        printf("both popped: %s\n", [NSCursor currentCursor] == [NSCursor arrowCursor] ? "the arrow" : "another");
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
        NSCursor *mine = [[NSCursor alloc] initWithImage:img hotSpot:NSMakePoint(3, 4)];
        printf("an image cursor: hot spot %g,%g, its image kept %s\n", [mine hotSpot].x, [mine hotSpot].y,
               [mine image] == img ? "yes" : "no");
        [NSCursor hide];
        [NSCursor unhide];
        [NSCursor setHiddenUntilMouseMoves:YES];
        move(195, 96);

        Spot *cu = spot(@"cu", NSMakeRect(0, 0, 8, 8));
        [cu addTrackingArea:[[NSTrackingArea alloc] initWithRect:[cu bounds]
                                                         options:NSTrackingCursorUpdate | NSTrackingActiveAlways
                                                           owner:cu
                                                        userInfo:nil]];
        move(4, 4);
        show("into an area with cursor updates");
        printf("the cursor: %s\n", [NSCursor currentCursor] == [NSCursor IBeamCursor] ? "the I-beam" : "another");
        move(195, 96);
        printf("out of it, the cursor: %s\n", [NSCursor currentCursor] == [NSCursor arrowCursor] ? "the arrow" : "another");

        Spot *cr = spot(@"cr", NSMakeRect(20, 60, 20, 20));
        cr.rectCursor = [NSCursor openHandCursor];
        [win invalidateCursorRectsForView:cr];
        int resetsBefore = cr.resets;
        move(25, 65);
        printf("into a cursor rectangle: %s, its view asked for them: %s\n",
               [NSCursor currentCursor] == [NSCursor openHandCursor] ? "the open hand" : "another",
               cr.resets > resetsBefore ? "yes" : "no");
        move(35, 75);
        printf("in the view, outside the rectangle: %s\n",
               [NSCursor currentCursor] == [NSCursor arrowCursor] ? "the arrow" : "another");
        [win disableCursorRects];
        move(25, 65);
        printf("cursor rectangles off: enabled %s, the cursor %s\n", [win areCursorRectsEnabled] ? "yes" : "no",
               [NSCursor currentCursor] == [NSCursor arrowCursor] ? "the arrow" : "another");
        [win enableCursorRects];
        move(26, 65);
        printf("on again: %s\n", [NSCursor currentCursor] == [NSCursor openHandCursor] ? "the open hand" : "another");
        [cr discardCursorRects];
        cr.rectCursor = nil;
        [win invalidateCursorRectsForView:cr];
        move(27, 65);
        printf("its rectangles gone: %s\n", [NSCursor currentCursor] == [NSCursor arrowCursor] ? "the arrow" : "another");

        [trail setString:@""];
        printf("-- an area removed while the mouse is in it\n");
        Spot *gone = spot(@"gone", NSMakeRect(150, 40, 10, 10));
        NSTrackingArea *ga = [[NSTrackingArea alloc] initWithRect:[gone bounds]
                                                          options:NSTrackingMouseEnteredAndExited |
                                                                  NSTrackingActiveAlways
                                                            owner:gone
                                                         userInfo:nil];
        [gone addTrackingArea:ga];
        move(155, 45);
        show("into it");
        [gone removeTrackingArea:ga];
        move(195, 96);
        show("out, after it was removed");
        printf("its areas: %lu\n", (unsigned long)[[gone trackingAreas] count]);
        [other close];
    }
    return 0;
}
