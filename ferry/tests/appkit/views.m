/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit without a display: views, drawing, controls and events, sent the
 * way the window system would send them. */
#import <Cocoa/Cocoa.h>

static void show(const char *what, NSString *s) { printf("%s: %s\n", what, [s UTF8String]); }
static void pixel(const char *what, NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    printf("%s (%d,%d): %.2f %.2f %.2f %.2f\n", what, x, y, r, g, b, a);
}

/* Fills its bottom-left 10x10 corner in its own coordinates. */
@interface Corner : NSView
@property (retain) NSColor *color;
@property BOOL flip;
@property int draws;
@end
@implementation Corner
- (BOOL)isFlipped { return _flip; }
- (void)drawRect:(NSRect)dirty
{
    _draws++;
    [_color set];
    NSRectFill(NSMakeRect(0, 0, 10, 10));
}
@end

/* Records what reaches it. */
@interface Recorder : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
@property (retain) NSMutableArray *log;
@end
@implementation Recorder
- (instancetype)init
{
    if ((self = [super init]))
        _log = [[NSMutableArray alloc] init];
    return self;
}
- (void)note:(NSString *)s { [_log addObject:s]; }
- (void)clicked:(id)sender { [self note:[NSString stringWithFormat:@"clicked %@", [sender title]]]; }
- (void)entered:(id)sender { [self note:[NSString stringWithFormat:@"entered %@", [sender stringValue]]]; }
- (void)controlTextDidChange:(NSNotification *)n { [self note:@"changed"]; }
- (void)fromMenu:(id)sender { [self note:[NSString stringWithFormat:@"menu %@", [sender title]]]; }
- (void)tick:(NSTimer *)t
{
    [self note:@"tick"];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                        timestamp:0 windowNumber:0 context:nil subtype:7 data1:42 data2:0]
             atStart:NO];
}
- (void)applicationDidFinishLaunching:(NSNotification *)n { [self note:@"launched"]; }
- (void)dump:(const char *)what
{
    printf("%s: %s\n", what, [[_log componentsJoinedByString:@", "] UTF8String]);
    [_log removeAllObjects];
}
@end

@interface App : NSApplication
@end
@implementation App
- (void)sendEvent:(NSEvent *)e
{
    if ([e type] == NSEventTypeApplicationDefined && [e subtype] == 7) {
        printf("application event %ld\n", (long)[e data1]);
        [self stop:nil];
        return;
    }
    [super sendEvent:e];
}
@end

static NSEvent *mouse(NSWindow *w, NSEventType type, NSPoint p)
{
    return [NSEvent mouseEventWithType:type location:p modifierFlags:0 timestamp:0 windowNumber:[w windowNumber]
                               context:nil eventNumber:0 clickCount:1 pressure:1];
}

static void click(NSWindow *w, NSView *v)
{
    NSPoint p = [v convertPoint:NSMakePoint(NSMidX([v bounds]), NSMidY([v bounds])) toView:nil];
    [w sendEvent:mouse(w, NSEventTypeLeftMouseDown, p)];
    [w sendEvent:mouse(w, NSEventTypeLeftMouseUp, p)];
}

static NSEvent *key(NSWindow *w, NSString *chars, NSEventModifierFlags flags, unsigned short code)
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:[w windowNumber] context:nil characters:chars
         charactersIgnoringModifiers:chars isARepeat:NO keyCode:code];
}

static void type(NSWindow *w, NSString *text)
{
    for (NSUInteger i = 0; i < [text length]; i++)
        [w sendEvent:key(w, [text substringWithRange:NSMakeRange(i, 1)], 0, 0)];
}

int main(void)
{
    @autoreleasepool {
        [App sharedApplication];
        printf("NSApp is an App: %d\n", [NSApp isKindOfClass:[App class]]);
        Recorder *rec = [[Recorder alloc] init];
        [NSApp setDelegate:rec];

        /* ---- geometry, conversion and hit-testing ---- */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 100)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w setReleasedWhenClosed:NO];
        NSView *content = [w contentView];
        show("content frame", NSStringFromRect([content frame]));
        Corner *plain = [[Corner alloc] initWithFrame:NSMakeRect(10, 20, 50, 40)];
        Corner *flipped = [[Corner alloc] initWithFrame:NSMakeRect(100, 20, 50, 40)];
        flipped.flip = YES;
        plain.color = [NSColor redColor];
        flipped.color = [NSColor blueColor];
        [content addSubview:plain];
        [content addSubview:flipped];
        printf("window set: %d, next responder is content: %d\n", [plain window] == w, [plain nextResponder] == content);
        show("plain (0,0) in window", NSStringFromPoint([plain convertPoint:NSZeroPoint toView:nil]));
        show("flipped (0,0) in window", NSStringFromPoint([flipped convertPoint:NSZeroPoint toView:nil]));
        show("flipped (5,5) from plain", NSStringFromPoint([flipped convertPoint:NSMakePoint(5, 5) fromView:plain]));
        show("rect to window", NSStringFromRect([flipped convertRect:NSMakeRect(0, 0, 10, 10) toView:nil]));
        printf("hit (15,25): %s\n", [content hitTest:NSMakePoint(15, 25)] == plain ? "plain" : "other");
        printf("hit (105,55): %s\n", [content hitTest:NSMakePoint(105, 55)] == flipped ? "flipped" : "other");
        printf("hit (80,80): %s\n", [content hitTest:NSMakePoint(80, 80)] == content ? "content" : "other");

        /* ---- drawing: each corner is at the origin of its own coordinates ---- */
        NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:[content bounds]];
        [content cacheDisplayInRect:[content bounds] toBitmapImageRep:rep];
        printf("bitmap %ldx%ld\n", (long)[rep pixelsWide], (long)[rep pixelsHigh]);
        /* rows run top down: the plain view's bottom-left corner is at y = 100-20-1 */
        pixel("plain corner", rep, 12, 78);
        pixel("plain top", rep, 12, 42);
        /* the flipped view's origin is its top-left: y = 100-60 */
        pixel("flipped corner", rep, 102, 42);
        pixel("flipped bottom", rep, 102, 78);
        printf("drawn once each: %d %d\n", plain.draws, flipped.draws);

        /* paths and text */
        NSBitmapImageRep *art = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:20
                                                                     bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:32];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:art]];
        [[NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 20, 20)] fill];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(20, 10)];
        [line lineToPoint:NSMakePoint(40, 10)];
        [line setLineWidth:4];
        [[NSColor blackColor] setStroke];
        [line stroke];
        [NSGraphicsContext restoreGraphicsState];
        pixel("oval centre", art, 10, 10);
        pixel("oval corner", art, 0, 0);
        pixel("line", art, 30, 10);
        printf("path bounds %s, elements %ld, contains centre %d\n", [NSStringFromRect([line bounds]) UTF8String],
               (long)[line elementCount], [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 20, 20)]
                                               containsPoint:NSMakePoint(10, 10)]);
        [art release];

        /* ---- colours and fonts ---- */
        NSColor *c = [NSColor colorWithCalibratedRed:1 green:0.5 blue:0.25 alpha:1];
        CGFloat h, s, v;
        [c getHue:&h saturation:&s brightness:&v alpha:NULL];
        printf("colour %.2f %.2f %.2f, hue %.3f sat %.2f bri %.2f, white %.2f\n", [c redComponent],
               [c greenComponent], [c blueComponent], h, s, v, [[NSColor colorWithWhite:0.3 alpha:1] whiteComponent]);
        printf("blend %.2f, with alpha %.2f, CGColor alpha %.2f\n",
               [[[NSColor blackColor] blendedColorWithFraction:0.25 ofColor:[NSColor whiteColor]] redComponent],
               [[c colorWithAlphaComponent:0.5] alphaComponent], CGColorGetAlpha([c CGColor]));
        NSFont *font = [NSFont systemFontOfSize:20];
        NSFont *bold = [NSFont boldSystemFontOfSize:20];
        NSFont *mono = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        printf("font %g pt, ascender > 0: %d, descender < 0: %d, bold differs: %d, mono fixed: %d\n",
               [font pointSize], [font ascender] > 0, [font descender] < 0,
               ![[font fontName] isEqualToString:[bold fontName]], [mono isFixedPitch]);
        CTFontRef ct = (CTFontRef)font;
        printf("an NSFont is a CTFont: %g; a CTFont is an NSFont: %d\n", CTFontGetSize(ct),
               [(id)CTFontCreateWithName(CFSTR("Helvetica"), 9, NULL) isKindOfClass:[NSFont class]]);
        NSSize one = [@"x" sizeWithAttributes:@{NSFontAttributeName : font}];
        NSSize two = [@"xx" sizeWithAttributes:@{NSFontAttributeName : font}];
        printf("text grows with length: %d, height ~ line height: %d\n", two.width > one.width * 1.5,
               fabs(one.height - ([font ascender] - [font descender])) < 2);
        NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
        [para setAlignment:NSTextAlignmentCenter];
        [para setLineBreakMode:NSLineBreakByTruncatingTail];
        NSParagraphStyle *copy = [para copy];
        printf("paragraph style alignment %ld break %ld\n", (long)[copy alignment], (long)[copy lineBreakMode]);

        /* ---- autoresizing ---- */
        NSView *stretchy = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 180, 80)];
        [stretchy setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        NSView *pinned = [[NSView alloc] initWithFrame:NSMakeRect(150, 60, 40, 30)];
        [pinned setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
        [content addSubview:stretchy positioned:NSWindowBelow relativeTo:nil];
        [content addSubview:pinned];
        [w setContentSize:NSMakeSize(300, 150)];
        show("window frame", NSStringFromRect([w frame]));
        show("stretchy", NSStringFromRect([stretchy frame]));
        show("pinned", NSStringFromRect([pinned frame]));
        [pinned removeFromSuperview];
        printf("removed: superview nil %d, window nil %d\n", [pinned superview] == nil, [pinned window] == nil);

        /* ---- controls: a button, a check box, two radio buttons and text fields ---- */
        NSButton *ok = [NSButton buttonWithTitle:@"OK" target:rec action:@selector(clicked:)];
        [ok setFrameOrigin:NSMakePoint(200, 10)];
        [ok setKeyEquivalent:@"\r"];
        NSButton *box = [NSButton checkboxWithTitle:@"Check" target:rec action:@selector(clicked:)];
        [box setFrameOrigin:NSMakePoint(10, 110)];
        NSButton *r1 = [NSButton radioButtonWithTitle:@"One" target:rec action:@selector(clicked:)];
        NSButton *r2 = [NSButton radioButtonWithTitle:@"Two" target:rec action:@selector(clicked:)];
        [r1 setFrameOrigin:NSMakePoint(100, 110)];
        [r2 setFrameOrigin:NSMakePoint(160, 110)];
        NSTextField *label = [NSTextField labelWithString:@"Name:"];
        [label setFrameOrigin:NSMakePoint(10, 60)];
        NSTextField *name = [NSTextField textFieldWithString:@""];
        [name setFrame:NSMakeRect(60, 60, 120, 22)];
        [name setTarget:rec];
        [name setAction:@selector(entered:)];
        [name setDelegate:rec];
        [name setPlaceholderString:@"Your name"];
        NSTextField *other = [NSTextField textFieldWithString:@"second"];
        [other setFrame:NSMakeRect(190, 60, 100, 22)];
        for (NSView *v in @[ ok, box, r1, r2, label, name, other ])
            [content addSubview:v];
        printf("button size %s, check box height %g, label editable %d, label takes focus %d\n",
               [NSStringFromSize([ok frame].size) UTF8String], [box frame].size.height, [label isEditable],
               [label acceptsFirstResponder]);

        [w makeKeyAndOrderFront:nil];
        printf("key window: %d, visible: %d\n", [w isKeyWindow], [w isVisible]);
        click(w, ok);
        click(w, box);
        click(w, box);
        click(w, r1);
        click(w, r2);
        printf("check box %ld, radios %ld %ld\n", (long)[box state], (long)[r1 state], (long)[r2 state]);
        [rec dump:"clicks"];

        /* a press that leaves the button before the release doesn't click */
        NSPoint in = [ok convertPoint:NSMakePoint(NSMidX([ok bounds]), NSMidY([ok bounds])) toView:nil];
        [w sendEvent:mouse(w, NSEventTypeLeftMouseDown, in)];
        printf("highlighted while pressed: %d\n", [ok isHighlighted]);
        [w sendEvent:mouse(w, NSEventTypeLeftMouseDragged, NSMakePoint(5, 5))];
        printf("not highlighted outside: %d\n", ![ok isHighlighted]);
        [w sendEvent:mouse(w, NSEventTypeLeftMouseUp, NSMakePoint(5, 5))];
        [rec dump:"dragged away"];

        /* typing into the text field */
        click(w, name);
        printf("first responder is the field: %d\n", [w firstResponder] == name);
        type(w, @"Adx");
        [w sendEvent:key(w, @"\x7f", 0, 51)];                                       /* Backspace */
        [w sendEvent:key(w, [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey],
                         NSEventModifierFlagFunction, 123)];
        type(w, @"a");
        [w sendEvent:key(w, [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey],
                         NSEventModifierFlagFunction, 124)];
        type(w, @"!");
        printf("typed: %s\n", [[name stringValue] UTF8String]);
        [rec dump:"while typing"];
        [w sendEvent:key(w, @"\r", 0, 36)];                                          /* Return */
        [rec dump:"return"];
        [w sendEvent:key(w, @"\t", 0, 48)];                                          /* Tab */
        printf("tab moved to the next field: %d\n", [w firstResponder] == other);
        printf("first field kept its text: %s\n", [[name stringValue] UTF8String]);
        [w sendEvent:key(w, @"\x19", NSEventModifierFlagShift, 48)];                 /* Shift-Tab */
        printf("shift-tab moved back: %d\n", [w firstResponder] == name);
        printf("everything selected on the way in: %s\n", [[name stringValue] UTF8String]);
        [w sendEvent:key(w, [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey],
                         NSEventModifierFlagCommand | NSEventModifierFlagFunction, 124)];
        type(w, @" ok");
        [w sendEvent:key(w, [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey],
                         NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagFunction, 123)];
        type(w, @"Z");
        printf("select a word back and type: %s\n", [[name stringValue] UTF8String]);
        [rec dump:"edits"];

        /* the drawn field shows its text; a label draws nothing behind it */
        [content display];
        rep = [content bitmapImageRepForCachingDisplayInRect:[content bounds]];
        [content cacheDisplayInRect:[content bounds] toBitmapImageRep:rep];
        int ink = 0;
        for (int x = 62; x < 178; x++)
            for (int y = 150 - 80; y < 150 - 62; y++) {
                CGFloat r;
                [[rep colorAtX:x y:y] getRed:&r green:NULL blue:NULL alpha:NULL];
                ink += r < 0.5;
            }
        printf("text drawn in the field: %d\n", ink > 10);

        /* ---- menus, key equivalents and the responder chain ---- */
        NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *appItem = [main addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
        NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
        [appMenu addItemWithTitle:@"Do It" action:@selector(fromMenu:) keyEquivalent:@"d"];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:@"Shifted" action:@selector(fromMenu:) keyEquivalent:@"D"];
        [appMenu addItemWithTitle:@"Nobody" action:@selector(nobodyHandlesThis:) keyEquivalent:@"n"];
        [main setSubmenu:appMenu forItem:appItem];
        [NSApp setMainMenu:main];
        [NSApp sendEvent:key(w, @"d", NSEventModifierFlagCommand, 2)];
        [NSApp sendEvent:key(w, @"d", NSEventModifierFlagCommand | NSEventModifierFlagShift, 2)];
        printf("unhandled key equivalent: %d\n",
               [main performKeyEquivalent:key(w, @"n", NSEventModifierFlagCommand, 45)]);
        printf("nil-targeted action found the delegate: %d\n", [NSApp sendAction:@selector(fromMenu:) to:nil from:appItem]);
        printf("first responder target: %d\n", [NSApp targetForAction:@selector(selectAll:)] == name);
        [rec dump:"menus"];

        /* ---- the run loop: launching, a timer, an application event, stop ---- */
        [NSTimer scheduledTimerWithTimeInterval:0.05 target:rec selector:@selector(tick:) userInfo:nil repeats:NO];
        [NSApp run];
        [rec dump:"run"];

        /* ---- closing ---- */
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:w queue:nil
                                                      usingBlock:^(NSNotification *n) { printf("will close\n"); }];
        [w performClose:nil];
        printf("after close: visible %d, key %d, windows %lu\n", [w isVisible], [w isKeyWindow],
               (unsigned long)[[NSApp windows] count]);
    }
    return 0;
}
