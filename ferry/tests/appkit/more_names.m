/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit names the nine apps' sources use that Ferry hadn't had
 * (freemac 1.221, Ferry 0.45.0), with no display: the run loop's tracking
 * and modal modes, the AppKit version, the older names, modal sessions,
 * focus rings and lists of rectangles, more system colours, the text
 * storage's edits, the layout manager's rectangles, the button cell's
 * masks, a cell's menu and hit testing, a text field as its own field
 * editor, cancelling an open menu and its tracking notifications, stable
 * sorts, Mach's booleans, more image names, and appearances. */
#import <Cocoa/Cocoa.h>

@interface NSWindow (FerryPeek)
- (NSView *)_overlayView;
@end

@interface Recorder : NSObject <NSTextStorageDelegate, NSMenuDelegate>
@property (strong) NSMutableArray *lines;
@end
@implementation Recorder
- (void)textStorage:(NSTextStorage *)ts willProcessEditing:(NSTextStorageEditActions)mask range:(NSRange)range
     changeInLength:(NSInteger)delta
{
    [self.lines addObject:[NSString stringWithFormat:@"will mask %lu range %@ delta %ld", (unsigned long)mask,
                                                     NSStringFromRange(range), (long)delta]];
}
- (void)textStorage:(NSTextStorage *)ts didProcessEditing:(NSTextStorageEditActions)mask range:(NSRange)range
     changeInLength:(NSInteger)delta
{
    [self.lines addObject:[NSString stringWithFormat:@"did mask %lu/%lu range %@/%@ \"%@\"", (unsigned long)mask,
                                                     (unsigned long)ts.editedMask, NSStringFromRange(range),
                                                     NSStringFromRange(ts.editedRange), ts.string]];
}
- (void)textStorageDidProcessEditing:(NSNotification *)n
{
    [self.lines addObject:[@"notified " stringByAppendingString:[[n object] class] == [NSTextStorage class] ? @"yes" : @"no"]];
}
- (void)menuDidClose:(NSMenu *)menu { [self.lines addObject:[@"closed " stringByAppendingString:menu.title]]; }
- (void)fire:(NSTimer *)t
{
    [self.lines addObject:[@"timer in " stringByAppendingString:[[NSRunLoop currentRunLoop] currentMode]]];
}
@end

static NSBitmapImageRep *canvas(int w, int h)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    return rep;
}
static NSString *pixel(NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    if (a < 0.05)
        return @"clear";
    return b > r + 0.3 ? @"blue" : r > b + 0.3 ? @"red" : g > 0.6 ? @"green" : @"other";
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Recorder *rec = [Recorder new];
        rec.lines = [NSMutableArray array];

        /* run loop modes */
        NSTimer *t = [NSTimer timerWithTimeInterval:0.01 target:rec selector:@selector(fire:) userInfo:nil repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:t forMode:NSEventTrackingRunLoopMode];
        [[NSRunLoop currentRunLoop] runMode:NSEventTrackingRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        printf("modes: %s, %s; %s\n", NSEventTrackingRunLoopMode.UTF8String, NSModalPanelRunLoopMode.UTF8String,
               [[rec.lines componentsJoinedByString:@", "] UTF8String]);
        [rec.lines removeAllObjects];

        /* the version and older names */
        printf("version: past 10.10 %d, past 11 %d\n", NSAppKitVersionNumber > NSAppKitVersionNumber10_10,
               NSAppKitVersionNumber > NSAppKitVersionNumber11_0);
        printf("older names: %d %d %d %d %d %d %d %d %d\n", NSLeftMouseDraggedMask == NSEventMaskLeftMouseDragged,
               NSLeftMouseUpMask == NSEventMaskLeftMouseUp, NSSmallControlSize == NSControlSizeSmall,
               NSCompositeSourceAtop == NSCompositingOperationSourceAtop,
               NSShadowlessSquareBezelStyle == NSBezelStyleShadowlessSquare, NSPNGFileType == NSBitmapImageFileTypePNG,
               NSEvenOddWindingRule == NSWindingRuleEvenOdd, NSRunContinuesResponse == NSModalResponseContinue,
               NSFontPanelSizeModeMask == NSFontPanelModeMaskSize);

        /* a modal session, run a turn at a time */
        NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        NSModalSession session = [NSApp beginModalSessionForWindow:panel];
        NSModalResponse first = [NSApp runModalSession:session];
        BOOL modal = [NSApp modalWindow] == panel;
        [NSApp stopModalWithCode:42];
        NSModalResponse second = [NSApp runModalSession:session];
        [NSApp endModalSession:session];
        printf("modal session: first turn continues %d, modal %d, after stopping %ld, after ending modal %d\n",
               first == NSModalResponseContinue, modal, (long)second, [NSApp modalWindow] != nil);

        /* focus rings and lists of rectangles */
        NSBitmapImageRep *rep = canvas(60, 60);
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [NSGraphicsContext saveGraphicsState];
        NSSetFocusRingStyle(NSFocusRingOnly);
        [[NSColor redColor] setFill];
        NSRectFill(NSMakeRect(20, 20, 20, 20));
        [NSGraphicsContext restoreGraphicsState];
        printf("ring only: inside %s, just outside %s, far away %s\n", pixel(rep, 30, 30).UTF8String,
               pixel(rep, 18, 30).UTF8String, pixel(rep, 2, 2).UTF8String);
        NSRect rects[2] = {NSMakeRect(0, 0, 10, 10), NSMakeRect(50, 50, 10, 10)};
        NSColor *colors[2] = {[NSColor redColor], [NSColor blueColor]};
        NSRectFillListWithColors(rects, colors, 2);
        [NSGraphicsContext saveGraphicsState];
        NSSetFocusRingStyle(NSFocusRingBelow);
        [[NSColor greenColor] setFill];
        NSRectFill(NSMakeRect(20, 20, 20, 20));
        [NSGraphicsContext restoreGraphicsState];
        [[NSColor redColor] setFill];
        NSRectFill(NSMakeRect(0, 25, 4, 4));
        [NSGraphicsContext restoreGraphicsState];
        /* the bitmap's rows run from the top */
        printf("list: bottom left %s, top right %s; ring below: inside %s, just outside %s; afterwards %s\n",
               pixel(rep, 5, 55).UTF8String, pixel(rep, 55, 5).UTF8String, pixel(rep, 30, 30).UTF8String,
               pixel(rep, 18, 30).UTF8String, pixel(rep, 2, 33).UTF8String);

        /* colours */
        printf("colours: frame %d, menu item %d, control shadow %d, named %s\n", [NSColor windowFrameColor] != nil,
               [NSColor selectedMenuItemColor] != nil, [NSColor controlShadowColor] != nil,
               [NSColor colorNamed:@"AccentColor"] ? "found" : "nil");

        /* the text storage's edits */
        NSTextStorage *ts = [[NSTextStorage alloc] initWithString:@"hello world"];
        ts.delegate = rec;
        __block int posted = 0;
        id observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSTextStorageWillProcessEditingNotification object:ts queue:nil
                    usingBlock:^(NSNotification *n) { posted++; }];
        [ts replaceCharactersInRange:NSMakeRange(0, 5) withString:@"goodbye"];
        [ts beginEditing];
        [ts addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(8, 5)];
        [ts deleteCharactersInRange:NSMakeRange(0, 4)];
        [ts endEditing];
        printf("text storage: %s; posted %d; after %s\n", [[rec.lines componentsJoinedByString:@"; "] UTF8String],
               posted, ts.editedRange.location == NSNotFound ? "none" : "some");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [rec.lines removeAllObjects];

        /* the layout manager's rectangles */
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        tv.string = @"hello\nworld";
        NSLayoutManager *lm = tv.layoutManager;
        NSRect hello = [lm boundingRectForGlyphRange:NSMakeRange(0, 5) inTextContainer:tv.textContainer];
        NSRect world = [lm boundingRectForGlyphRange:NSMakeRange(6, 5) inTextContainer:tv.textContainer];
        NSRect both = [lm boundingRectForGlyphRange:NSMakeRange(0, 11) inTextContainer:tv.textContainer];
        NSRange actual;
        NSRange clipped = [lm glyphRangeForCharacterRange:NSMakeRange(8, 10) actualCharacterRange:&actual];
        NSRange effective;
        NSRect line2 = [lm lineFragmentRectForGlyphAtIndex:7 effectiveRange:&effective];
        printf("layout: hello wide %d, world below %d, same left %d, both covers %d, clipped %s, line %s at %d, "
               "rect finds %s\n",
               hello.size.width > 10, NSMinY(world) >= NSMaxY(hello) - 0.5, fabs(NSMinX(hello) - NSMinX(world)) < 1,
               NSContainsRect(NSInsetRect(both, -0.5, -0.5), world), NSStringFromRange(clipped).UTF8String,
               NSStringFromRange(effective).UTF8String, fabs(NSMinY(line2) - NSMinY(world)) < 0.5,
               NSStringFromRange([lm glyphRangeForBoundingRect:world inTextContainer:tv.textContainer]).UTF8String);

        /* button cell masks */
        NSButtonCell *bc = [[NSButtonCell alloc] initTextCell:@"OK"];
        printf("button cell: push %lu/%lu", (unsigned long)bc.highlightsBy, (unsigned long)bc.showsStateBy);
        [bc setButtonType:NSButtonTypeSwitch];
        printf(", switch %lu/%lu", (unsigned long)bc.highlightsBy, (unsigned long)bc.showsStateBy);
        [bc setButtonType:NSButtonTypeToggle];
        printf(", toggle %lu/%lu", (unsigned long)bc.highlightsBy, (unsigned long)bc.showsStateBy);
        bc.highlightsBy = NSNoCellMask;
        bc.imagePosition = NSImageLeft;
        bc.attributedTitle = [[NSAttributedString alloc] initWithString:@"Styled"];
        printf(", set %lu, image %lu, title %s\n", (unsigned long)bc.highlightsBy, (unsigned long)bc.imagePosition,
               bc.title.UTF8String);

        /* a cell's menu and hit testing */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        NSView *content = w.contentView;
        NSTextFieldCell *tc = [[NSTextFieldCell alloc] initTextCell:@"text"];
        tc.editable = YES;
        tc.menu = [[NSMenu alloc] initWithTitle:@"Cell menu"];
        NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(15, 15)
                                       modifierFlags:0 timestamp:0 windowNumber:w.windowNumber context:nil
                                         eventNumber:0 clickCount:1 pressure:1];
        printf("cell: menu %s, text cell hit %lu, button hit %lu, outside %lu\n",
               [[tc menuForEvent:click inRect:NSMakeRect(0, 0, 30, 30) ofView:content] title].UTF8String,
               (unsigned long)[tc hitTestForEvent:click inRect:NSMakeRect(0, 0, 30, 30) ofView:content],
               (unsigned long)[bc hitTestForEvent:click inRect:NSMakeRect(0, 0, 30, 30) ofView:content],
               (unsigned long)[tc hitTestForEvent:click inRect:NSMakeRect(100, 100, 30, 30) ofView:content]);

        /* a text field is its own field editor */
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 150, 200, 22)];
        field.stringValue = @"Sequel";
        [content addSubview:field];
        printf("field editor: before %s", [field currentEditor] ? "some" : "none");
        [w makeFirstResponder:field];
        NSText *editor = [field currentEditor];
        printf(", editing %s, selected %s", editor == (id)field ? "itself" : "other",
               NSStringFromRange(editor.selectedRange).UTF8String);
        editor.selectedRange = NSMakeRange(6, 0);
        printf(", caret %s", NSStringFromRange([field currentEditor].selectedRange).UTF8String);
        [w endEditingFor:nil];
        printf(", ended %s, first responder the window %d, text %s, shared editor %s\n",
               [field currentEditor] ? "no" : "yes", w.firstResponder == w, field.stringValue.UTF8String,
               [w fieldEditor:YES forObject:field] ? "some" : "none");

        /* cancelling an open menu */
        NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, 100, 120, 25) pullsDown:NO];
        [pop addItemsWithTitles:@[ @"One", @"Two" ]];
        pop.menu.title = @"Choices";
        pop.menu.delegate = rec;
        [content addSubview:pop];
        [pop selectItemAtIndex:1];
        __block int began = 0, ended = 0;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        id o1 = [nc addObserverForName:NSMenuDidBeginTrackingNotification object:pop.menu queue:nil
                            usingBlock:^(NSNotification *n) { began++; }];
        id o2 = [nc addObserverForName:NSMenuDidEndTrackingNotification object:pop.menu queue:nil
                            usingBlock:^(NSNotification *n) { ended++; }];
        [pop performClick:nil];
        BOOL open = [[w _overlayView] isKindOfClass:NSClassFromString(@"AMenuView")];
        [[[NSMenu alloc] initWithTitle:@"Other"] cancelTracking];
        BOOL stillOpen = [w _overlayView] != nil;
        [pop.menu cancelTracking];
        printf("menu: open %d, another menu's cancel leaves it %d, closed %d, %s, chosen still %s, tracking %d/%d\n",
               open, stillOpen, [w _overlayView] == nil, [[rec.lines componentsJoinedByString:@", "] UTF8String],
               pop.titleOfSelectedItem.UTF8String, began, ended);
        [nc removeObserver:o1];
        [nc removeObserver:o2];

        /* small names: stable sorts, Mach's booleans, an error code, image names */
        NSArray *pairs = @[ @"b1", @"a1", @"b2", @"a2" ];
        NSArray *sorted = [pairs sortedArrayWithOptions:NSSortStable
                                        usingComparator:^NSComparisonResult(NSString *x, NSString *y) {
                                            return [[x substringToIndex:1] compare:[y substringToIndex:1]];
                                        }];
        boolean_t yes = TRUE;
        printf("small names: %s, TRUE %u FALSE %d, cancelled %d, %s %s\n",
               [[sorted componentsJoinedByString:@" "] UTF8String], yes, FALSE, userCanceledErr,
               NSImageNameComputer.UTF8String, NSImageNameNetwork.UTF8String);

        /* appearances */
        NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSView *inner = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [content addSubview:inner];
        printf("appearance: app %s, view %s", NSApp.effectiveAppearance.name.UTF8String,
               inner.effectiveAppearance.name.UTF8String);
        content.appearance = dark;
        printf(", under a dark view %s, the window still %s", inner.effectiveAppearance.name.UTF8String,
               w.effectiveAppearance.name.UTF8String);
        printf(", best match %s, unknown %s, current %s\n",
               [dark bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]].UTF8String,
               [NSAppearance appearanceNamed:@"Nonsense"] ? "some" : "nil",
               [NSAppearance currentAppearance].name.UTF8String);
    }
    return 0;
}
