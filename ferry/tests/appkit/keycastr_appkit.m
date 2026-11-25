/* SPDX-License-Identifier: GPL-3.0-or-later
 * What KeyCastr and its ShortcutRecorder and Sparkle call in AppKit and
 * Carbon (freemac 1.224, Ferry 0.48.0), with no display and in a home of
 * the test's own: window frames saved by name, a relative curve, the layout
 * direction and control tint, tab stops, a catalogue colour, a menu item's
 * parent, tool-tip rects, string drawing with a context, three- and
 * nine-part images, the process type, and the current input source kept as
 * one object. */
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static NSImage *solid(NSColor *c, CGFloat w, CGFloat h)
{
    NSImage *i = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
    [i lockFocus];
    [c set];
    NSRectFill(NSMakeRect(0, 0, w, h));
    [i unlockFocus];
    return i;
}

static const char *which(NSColor *c)
{
    c = [c colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    if ([c alphaComponent] < 0.1)
        return "clear";
    if ([c redComponent] > 0.9 && [c greenComponent] < 0.1 && [c blueComponent] < 0.1)
        return "red";
    if ([c greenComponent] > 0.4 && [c redComponent] < 0.1 && [c blueComponent] < 0.1)
        return "green";
    if ([c blueComponent] > 0.9 && [c redComponent] < 0.1 && [c greenComponent] < 0.1)
        return "blue";
    return "other";
}

@interface TipOwner : NSObject <NSViewToolTipOwner>
@end
@implementation TipOwner
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    return [NSString stringWithFormat:@"tip %s", (const char *)data];
}
@end

static void frames(void)
{
    printf("window frames by name\n");
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 120, 300, 200)
                                              styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered
                                                  defer:YES];
    [w saveFrameUsingName:@"Ferry Test"];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"NSWindow Frame Ferry Test"];
    printf("  saved: %s\n", saved ? "yes" : "no");
    printf("  as a string matches: %s\n", [saved isEqualToString:[w stringWithSavedFrame]] ? "yes" : "no");
    NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    BOOL ok = [other setFrameUsingName:@"Ferry Test" force:YES];
    printf("  read back: %d, same frame %s\n", ok, NSEqualRects([other frame], [w frame]) ? "yes" : "no");
    [NSWindow removeFrameUsingName:@"Ferry Test"];
    printf("  removed: %s, unknown name read: %d\n",
           [[NSUserDefaults standardUserDefaults] stringForKey:@"NSWindow Frame Ferry Test"] ? "no" : "yes",
           [other setFrameUsingName:@"Ferry Test" force:YES]);
    [other setFrameFromString:@"10 20 200 150 0 0 1280 800 "];
    NSRect f = [other frame];
    printf("  from a string: %.0f %.0f %.0f %.0f\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
    /* a window that can't be resized only moves */
    [w setFrameFromString:@"10 20 200 150 0 0 1280 800 "];
    f = [w frame];
    printf("  a fixed window from it: %.0f %.0f %.0f %.0f\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
}

static void paths_and_looks(void)
{
    printf("paths and looks\n");
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(10, 10)];
    [p relativeCurveToPoint:NSMakePoint(20, 0) controlPoint1:NSMakePoint(5, 10) controlPoint2:NSMakePoint(15, 10)];
    NSPoint pts[3];
    NSBezierPathElement e = [p elementAtIndex:1 associatedPoints:pts];
    printf("  relative curve: element %s, to %.0f,%.0f via %.0f,%.0f and %.0f,%.0f\n",
           e == NSBezierPathElementCurveTo ? "curve" : "other", pts[2].x, pts[2].y, pts[0].x, pts[0].y, pts[1].x,
           pts[1].y);
    printf("  layout direction %ld, control tint %lu\n", (long)[NSApp userInterfaceLayoutDirection],
           (unsigned long)[NSColor currentControlTint]);
    NSColor *c = [NSColor colorWithCatalogName:@"System" colorName:@"controlTextColor"];
    printf("  System/controlTextColor is controlTextColor: %s; System/nope: %s; Other/controlTextColor: %s\n",
           [c isEqual:[NSColor controlTextColor]] ? "yes" : "no",
           [NSColor colorWithCatalogName:@"System" colorName:@"nope"] ? "a colour" : "nil",
           [NSColor colorWithCatalogName:@"Other" colorName:@"controlTextColor"] ? "a colour" : "nil");
}

static void tabs(void)
{
    printf("tab stops\n");
    NSParagraphStyle *d = [NSParagraphStyle defaultParagraphStyle];
    NSArray *stops = [d tabStops];
    printf("  default: %lu stops, first at %.0f, last at %.0f, interval %.0f\n", (unsigned long)[stops count],
           [[stops firstObject] location], [[stops lastObject] location], [d defaultTabInterval]);
    NSMutableParagraphStyle *m = [d mutableCopy];
    [m setTabStops:@[
        [[NSTextTab alloc] initWithType:NSRightTabStopType location:90],
        [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:30 options:@{}]
    ]];
    [m addTabStop:[[NSTextTab alloc] initWithType:NSDecimalTabStopType location:60]];
    [m removeTabStop:[[NSTextTab alloc] initWithType:NSRightTabStopType location:90]];
    [m setDefaultTabInterval:36];
    NSParagraphStyle *copy = [m copy];
    for (NSTextTab *t in [copy tabStops])
        printf("  a stop at %.0f, type %lu, alignment %ld\n", [t location], (unsigned long)[t tabStopType],
               (long)[t alignment]);
    printf("  the copy's interval %.0f\n", [copy defaultTabInterval]);
}

static void menus_and_tips(void)
{
    printf("menus and tool tips\n");
    NSMenu *top = [[NSMenu alloc] initWithTitle:@"Top"];
    NSMenuItem *file = [top addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *open = [sub addItemWithTitle:@"Open" action:NULL keyEquivalent:@"o"];
    [file setSubmenu:sub];
    printf("  Open's parent: %s; File's parent: %s\n", [[[open parentItem] title] UTF8String],
           [file parentItem] ? "an item" : "nil");
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    TipOwner *owner = [TipOwner new];
    NSToolTipTag a = [v addToolTipRect:NSMakeRect(0, 0, 50, 50) owner:owner userData:"one"];
    NSToolTipTag b = [v addToolTipRect:NSMakeRect(50, 50, 50, 50) owner:@"a plain string" userData:NULL];
    printf("  two tags, different: %s\n", a != b ? "yes" : "no");
    [v removeToolTip:a];
    [v removeAllToolTips];
    [v setToolTip:@"whole view"];
    printf("  the view answers as an owner: %s\n",
           [[v view:v stringForToolTip:0 point:NSZeroPoint userData:NULL] UTF8String]);
    printf("  needs to draw inside: %d, outside: %d\n", [v needsToDrawRect:NSMakeRect(10, 10, 5, 5)],
           [v needsToDrawRect:NSMakeRect(200, 200, 5, 5)]);
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    printf("  a text view has marked text: %d, marked range %s; the cursor attribute: %s\n", [tv hasMarkedText],
           [tv markedRange].location == NSNotFound ? "none" : "some", [NSCursorAttributeName UTF8String]);
    tv.automaticQuoteSubstitutionEnabled = YES;
    printf("  quote substitution read by its is-name: %d, spelling: %d\n", [tv isAutomaticQuoteSubstitutionEnabled],
           tv.continuousSpellCheckingEnabled);
}

static void strings(void)
{
    printf("strings with a drawing context\n");
    NSStringDrawingContext *ctx = [NSStringDrawingContext new];
    ctx.minimumScaleFactor = 0.5;
    NSDictionary *attrs = @{NSFontAttributeName : [NSFont systemFontOfSize:13]};
    NSRect plain = [@"Ferry" boundingRectWithSize:NSMakeSize(500, 100) options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:attrs];
    NSRect with = [@"Ferry" boundingRectWithSize:NSMakeSize(500, 100) options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:attrs
                                         context:ctx];
    printf("  same size as without: %s, scale %.1f\n", NSEqualSizes(plain.size, with.size) ? "yes" : "no",
           ctx.actualScaleFactor);
}

static void parts(void)
{
    printf("three- and nine-part images\n");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:20
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    NSImage *r = solid([NSColor redColor], 5, 5), *g = solid([NSColor greenColor], 5, 5),
            *b = solid([NSColor blueColor], 5, 5);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    NSDrawThreePartImage(NSMakeRect(0, 0, 40, 10), r, g, b, NO, NSCompositingOperationSourceOver, 1, NO);
    [NSGraphicsContext restoreGraphicsState];
    /* the bitmap's rows run from the top: y 15 is in the bottom half */
    printf("  across: %s %s %s %s, above: %s\n", which([rep colorAtX:2 y:15]), which([rep colorAtX:20 y:15]),
           which([rep colorAtX:37 y:15]), which([rep colorAtX:6 y:15]), which([rep colorAtX:20 y:5]));

    rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:30 pixelsHigh:30 bitsPerSample:8
                                             samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                              colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    NSDrawNinePartImage(NSMakeRect(0, 0, 30, 30), r, g, r, g, b, g, r, g, r, NSCompositingOperationSourceOver, 1, NO);
    [NSGraphicsContext restoreGraphicsState];
    printf("  corners %s %s %s %s, edges %s %s, middle %s\n", which([rep colorAtX:1 y:1]),
           which([rep colorAtX:28 y:1]), which([rep colorAtX:1 y:28]), which([rep colorAtX:28 y:28]),
           which([rep colorAtX:15 y:1]), which([rep colorAtX:1 y:15]), which([rep colorAtX:15 y:15]));
}

static void process_and_input(void)
{
    printf("the process and the input source\n");
    printf("  policy at start: %ld\n", (long)[NSApp activationPolicy]);
    ProcessSerialNumber me = {0, kCurrentProcess};
    OSStatus s = TransformProcessType(&me, kProcessTransformToUIElementApplication);
    printf("  to a UI element: %d, policy %ld\n", (int)s, (long)[NSApp activationPolicy]);
    s = TransformProcessType(&me, kProcessTransformToForegroundApplication);
    printf("  to the foreground: %d, policy %ld\n", (int)s, (long)[NSApp activationPolicy]);
    ProcessSerialNumber other = {0, 12345};
    printf("  another process: %d\n", (int)TransformProcessType(&other, kProcessTransformToForegroundApplication));
    TISInputSourceRef one = TISCopyCurrentKeyboardLayoutInputSource();
    TISInputSourceRef two = TISCopyCurrentKeyboardLayoutInputSource();
    printf("  the current input source twice is one object: %s\n", one == two ? "yes" : "no");
    CFRelease(one);
    CFRelease(two);
    TISInputSourceRef three = TISCopyCurrentKeyboardLayoutInputSource();
    printf("  and still is after both are released: %s, id %s\n", three == one ? "yes" : "no",
           [(__bridge NSString *)TISGetInputSourceProperty(three, kTISPropertyInputSourceID) UTF8String]);
    CFRelease(three);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        frames();
        paths_and_looks();
        tabs();
        menus_and_tips();
        strings();
        parts();
        process_and_input();
    }
    return 0;
}
