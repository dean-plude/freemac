/* SPDX-License-Identifier: GPL-3.0-or-later
 * More controls again, with no display: steppers (the ends, wrapping,
 * clicks, the keys and holding the mouse down); level indicators (every
 * style, the colours at the warning and critical levels, tick marks, and
 * setting the value by clicking and dragging); colour wells and the
 * colour panel (activating, the colour the panel gives, changeColor: and
 * the panel's own action); date pickers (the parts, stepping and typing,
 * the limits and the delegate, the calendar style and ranges); combo
 * boxes (their items and a data source, the list opened, moved through
 * and chosen from, completion, the arrows with the list closed);
 * popovers (where they show, their behaviours, the delegate and a view
 * controller presented as one); path controls (the components, clicks,
 * the pop-up style's menu); sounds (named sounds, playing, stopping,
 * pausing, a delegate) with a stand-in player; token fields (typing
 * tokens, the delegate, deleting); and all of them from a nib
 * (MoreControls.nib, from make_nibs.py). Pictures go to the directory
 * FERRY_CONTROLS_PNG names, if it is set. */
#import <Cocoa/Cocoa.h>

@interface NSWindow (FerryPeek)
- (NSView *)_overlayView;
@end

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
static NSPoint mid(NSRect r) { return NSMakePoint(NSMidX(r), NSMidY(r)); }
static NSEvent *mouse_n(NSEventType type, NSWindow *w, NSView *v, NSPoint p, NSInteger clicks, NSEventModifierFlags mods)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:mods timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:clicks pressure:1];
}
static void down(NSWindow *w, NSView *v, NSPoint p) { [w sendEvent:mouse_n(NSEventTypeLeftMouseDown, w, v, p, 1, 0)]; }
static void up(NSWindow *w, NSView *v, NSPoint p) { [w sendEvent:mouse_n(NSEventTypeLeftMouseUp, w, v, p, 1, 0)]; }
static void dragged(NSWindow *w, NSView *v, NSPoint p)
{
    [w sendEvent:mouse_n(NSEventTypeLeftMouseDragged, w, v, p, 1, 0)];
}
static void click(NSWindow *w, NSView *v, NSPoint p)
{
    down(w, v, p);
    up(w, v, p);
}
static void double_click(NSWindow *w, NSView *v, NSPoint p)
{
    click(w, v, p);
    [w sendEvent:mouse_n(NSEventTypeLeftMouseDown, w, v, p, 2, 0)];
    [w sendEvent:mouse_n(NSEventTypeLeftMouseUp, w, v, p, 2, 0)];
}
static void key_with(NSWindow *w, unichar c, NSEventModifierFlags mods)
{
    NSString *s = [NSString stringWithFormat:@"%C", c];
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}
static void key(NSWindow *w, unichar c) { key_with(w, c, 0); }
static void type(NSWindow *w, NSString *s)
{
    for (NSUInteger i = 0; i < [s length]; i++)
        key(w, [s characterAtIndex:i]);
}
static void wait_for(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static void draw(NSView *v, const char *name)
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    const char *dir = getenv("FERRY_CONTROLS_PNG");
    if (dir) {
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithFormat:@"%s/more-%s.png", dir, name] atomically:YES];
    }
}
/* The window's content and what's drawn over it (an open list or a popover). */
static void draw_window(NSWindow *w, const char *name)
{
    const char *dir = getenv("FERRY_CONTROLS_PNG");
    if (!dir)
        return;
    NSSize s = [[w contentView] frame].size;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)s.width
                                                                    pixelsHigh:(NSInteger)s.height bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(NSMakeRect(0, 0, s.width, s.height));
    for (NSView *v in @[ [w contentView], [w _overlayView] ?: [NSNull null] ]) {
        if (![v isKindOfClass:[NSView class]])
            continue;
        NSBitmapImageRep *part = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
        [v cacheDisplayInRect:[v bounds] toBitmapImageRep:part];
        [part drawInRect:NSMakeRect(0, 0, s.width, s.height)];
    }
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[NSString stringWithFormat:@"%s/more-%s.png", dir, name] atomically:YES];
}
static const char *color_text(NSColor *c)
{
    if (!c)
        return "(none)";
    CGFloat r, g, b, a;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [[NSString stringWithFormat:@"%.2f %.2f %.2f %.2f", r, g, b, a] UTF8String];
}

/* ---- what the controls send ---- */

@interface Log : NSObject <NSDatePickerCellDelegate, NSComboBoxDelegate, NSComboBoxDataSource, NSPopoverDelegate,
                           NSPathControlDelegate, NSSoundDelegate, NSTokenFieldDelegate>
@property (strong) NSMutableArray *lines;
@property BOOL refuseClose, noWeekends, upperTokens;
@end
@implementation Log
- (instancetype)init
{
    if ((self = [super init]))
        _lines = [NSMutableArray array];
    return self;
}
- (void)add:(NSString *)s { [_lines addObject:s]; }
- (void)dump:(const char *)what
{
    printf("%s: %s\n", what, [_lines count] ? [[_lines componentsJoinedByString:@"; "] UTF8String] : "(nothing)");
    [_lines removeAllObjects];
}
- (void)stepped:(NSStepper *)s { [self add:[NSString stringWithFormat:@"stepped %g", [s doubleValue]]]; }
- (void)leveled:(NSLevelIndicator *)l { [self add:[NSString stringWithFormat:@"level %g", [l doubleValue]]]; }
- (void)wellChanged:(NSColorWell *)w { [self add:[NSString stringWithFormat:@"well %s", color_text([w color])]]; }
- (void)panelChanged:(NSColorPanel *)p { [self add:[NSString stringWithFormat:@"panel %s", color_text([p color])]]; }
- (void)dated:(NSDatePicker *)p { [self add:[NSString stringWithFormat:@"date %@", [p stringValue]]]; }
- (void)datePickerCell:(NSDatePickerCell *)cell validateProposedDateValue:(NSDate **)date timeInterval:(NSTimeInterval *)t
{
    if (!_noWeekends)
        return;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [cal setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSInteger wd = [cal component:NSCalendarUnitWeekday fromDate:*date];
    if (wd == 1 || wd == 7) {
        [self add:@"weekend moved to Monday"];
        *date = [cal dateByAddingUnit:NSCalendarUnitDay value:wd == 1 ? 1 : 2 toDate:*date options:0];
    }
}
- (void)combo:(NSComboBox *)c
{
    [self add:[NSString stringWithFormat:@"combo action \"%@\" %ld", [c stringValue], (long)[c indexOfSelectedItem]]];
}
- (void)comboBoxWillPopUp:(NSNotification *)n { [self add:@"will pop up"]; }
- (void)comboBoxWillDismiss:(NSNotification *)n { [self add:@"will dismiss"]; }
- (void)comboBoxSelectionDidChange:(NSNotification *)n
{
    [self add:[NSString stringWithFormat:@"selection %ld", (long)[[n object] indexOfSelectedItem]]];
}
- (void)comboBoxSelectionIsChanging:(NSNotification *)n { [self add:@"changing"]; }
- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)c { return 40; }
- (id)comboBox:(NSComboBox *)c objectValueForItemAtIndex:(NSInteger)i { return [NSString stringWithFormat:@"Item %ld", (long)i]; }
- (NSUInteger)comboBox:(NSComboBox *)c indexOfItemWithStringValue:(NSString *)s
{
    return [s hasPrefix:@"Item "] ? (NSUInteger)[[s substringFromIndex:5] integerValue] : NSNotFound;
}
- (NSString *)comboBox:(NSComboBox *)c completedString:(NSString *)s
{
    return [@"Item 1" hasPrefix:s] ? @"Item 17" : nil;
}
- (void)popoverWillShow:(NSNotification *)n { [self add:@"will show"]; }
- (void)popoverDidShow:(NSNotification *)n { [self add:@"did show"]; }
- (BOOL)popoverShouldClose:(NSPopover *)p
{
    [self add:_refuseClose ? @"should close? no" : @"should close? yes"];
    return !_refuseClose;
}
- (void)popoverWillClose:(NSNotification *)n
{
    [self add:[NSString stringWithFormat:@"will close (%@)", [n userInfo][NSPopoverCloseReasonKey]]];
}
- (void)popoverDidClose:(NSNotification *)n { [self add:@"did close"]; }
- (void)clicked:(id)sender { [self add:[NSString stringWithFormat:@"clicked %@", NSStringFromClass([sender class])]]; }
- (void)pathClicked:(NSPathControl *)p
{
    [self add:[NSString stringWithFormat:@"path clicked \"%@\" %@", [[p clickedPathItem] title], [[[p clickedPathItem] URL] path]]];
}
- (void)pathDoubleClicked:(NSPathControl *)p { [self add:@"path double-clicked"]; }
- (void)pathControl:(NSPathControl *)p willPopUpMenu:(NSMenu *)menu
{
    NSMutableArray *titles = [NSMutableArray array];
    for (NSMenuItem *i in [menu itemArray])
        [titles addObject:[i title]];
    [self add:[NSString stringWithFormat:@"menu [%@]", [titles componentsJoinedByString:@", "]]];
}
- (void)sound:(NSSound *)s didFinishPlaying:(BOOL)finished
{
    [self add:[NSString stringWithFormat:@"%@ finished %d", [s name] ?: @"sound", finished]];
}
- (id)tokenField:(NSTokenField *)f representedObjectForEditingString:(NSString *)s
{
    return _upperTokens ? [s uppercaseString] : s;
}
- (NSArray *)tokenField:(NSTokenField *)f shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)i
{
    [self add:[NSString stringWithFormat:@"add [%@] at %lu", [tokens componentsJoinedByString:@","], (unsigned long)i]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *t in tokens)
        if (![t isEqualToString:@"NO"] && ![t isEqualToString:@"no"])
            [kept addObject:t];
    return kept;
}
- (void)tokens:(NSTokenField *)f { [self add:[NSString stringWithFormat:@"tokens action %@", [[f objectValue] componentsJoinedByString:@"|"]]]; }
@end

/* A view that takes the colour panel's changeColor:. */
@interface ColorTaker : NSView
@property (strong) Log *log;
@end
@implementation ColorTaker
- (BOOL)acceptsFirstResponder { return YES; }
- (void)changeColor:(id)sender
{
    [_log add:[NSString stringWithFormat:@"changeColor: from %@ %s", NSStringFromClass([sender class]), color_text([sender color])]];
}
@end

@interface MoreOwner : NSObject
@property (strong) NSWindow *window;
@property (weak) NSStepper *stepper;
@property (weak) NSLevelIndicator *level;
@property (weak) NSColorWell *well;
@property (weak) NSDatePicker *picker;
@property (weak) NSComboBox *combo;
@property (weak) NSPathControl *pathControl;
@property (weak) NSTokenField *tokens;
@property NSInteger steps;
@end
@implementation MoreOwner
- (void)stepped:(id)sender { _steps++; }
@end

static NSDate *gmt_date(NSInteger y, NSInteger mo, NSInteger d, NSInteger h, NSInteger mi, NSInteger s)
{
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [cal setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    return [cal dateWithEra:1 year:y month:mo day:d hour:h minute:mi second:s nanosecond:0];
}
static NSString *path_titles(NSPathControl *p)
{
    NSMutableArray *t = [NSMutableArray array];
    for (NSPathControlItem *i in [p pathItems])
        [t addObject:[i title]];
    return [t componentsJoinedByString:@" > "];
}

/* A short WAV file: a second of silence at 8000 bytes a second. */
static void write_wav(NSString *path, int seconds)
{
    uint32_t data = 8000 * seconds;
    NSMutableData *d = [NSMutableData data];
    uint32_t riff = 36 + data, fmt = 16, rate = 8000, bytes = 8000;
    uint16_t pcm = 1, channels = 1, align = 1, bits = 8;
    [d appendBytes:"RIFF" length:4];
    [d appendBytes:&riff length:4];
    [d appendBytes:"WAVEfmt " length:8];
    [d appendBytes:&fmt length:4];
    [d appendBytes:&pcm length:2];
    [d appendBytes:&channels length:2];
    [d appendBytes:&rate length:4];
    [d appendBytes:&bytes length:4];
    [d appendBytes:&align length:2];
    [d appendBytes:&bits length:2];
    [d appendBytes:"data" length:4];
    [d appendBytes:&data length:4];
    [d setLength:[d length] + data];
    [d writeToFile:path atomically:YES];
}
static BOOL wait_until(BOOL (^done)(void), double limit)
{
    for (double t = 0; t < limit; t += 0.05) {
        if (done())
            return YES;
        wait_for(0.05);
    }
    return done();
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"AppleKeyboardUIMode" : @2}];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 360) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];
        NSView *content = [w contentView];
        Log *log = [[Log alloc] init];

        /* ---- steppers ---- */
        NSStepper *st = [[NSStepper alloc] initWithFrame:NSMakeRect(20, 300, 19, 27)];
        printf("stepper: cell %s, min %g max %g increment %g value %g, autorepeat %d wraps %d, size %.0fx%.0f\n",
               [NSStringFromClass([[st cell] class]) UTF8String], [st minValue], [st maxValue], [st increment],
               [st doubleValue], [st autorepeat], [st valueWraps], [st intrinsicContentSize].width,
               [st intrinsicContentSize].height);
        [content addSubview:st];
        [st setMaxValue:10];
        [st setIncrement:3];
        [st setDoubleValue:9];
        [st setTarget:log];
        [st setAction:@selector(stepped:)];
        NSRect sb = [st bounds];
        NSPoint top = NSMakePoint(NSMidX(sb), [st isFlipped] ? 6 : sb.size.height - 6);
        NSPoint bottom = NSMakePoint(NSMidX(sb), [st isFlipped] ? sb.size.height - 6 : 6);
        click(w, st, top);
        click(w, st, top);
        click(w, st, bottom);
        click(w, st, bottom);
        [log dump:"wrapping"];
        [st setValueWraps:NO];
        [st setDoubleValue:8];
        click(w, st, top);
        click(w, st, top);
        [st setDoubleValue:2];
        click(w, st, bottom);
        click(w, st, bottom);
        [log dump:"stopping at the ends"];
        [st setDoubleValue:42];
        printf("set past the end: %g; set to -5: ", [st doubleValue]);
        [st setDoubleValue:-5];
        printf("%g\n", [st doubleValue]);
        [st setDoubleValue:4];
        [w makeFirstResponder:st];
        key(w, NSUpArrowFunctionKey);
        key(w, NSDownArrowFunctionKey);
        key(w, NSDownArrowFunctionKey);
        [log dump:"keys"];
        [st setDoubleValue:0];
        [st setIncrement:1];
        [st setMaxValue:100];
        down(w, st, top);
        wait_for(0.9);
        up(w, st, top);
        NSUInteger repeats = [[log lines] count];
        [[log lines] removeAllObjects];
        printf("held down: %s\n", repeats >= 4 ? "repeats" : "doesn't repeat");
        [st setAutorepeat:NO];
        [st setDoubleValue:0];
        down(w, st, top);
        wait_for(0.6);
        up(w, st, top);
        [log dump:"held down, autorepeat off"];
        draw(st, "stepper");

        /* ---- level indicators ---- */
        NSLevelIndicator *lv = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(60, 300, 120, 18)];
        printf("level: cell %s, style %lu, min %g max %g warning %g critical %g, editable %d\n",
               [NSStringFromClass([[lv cell] class]) UTF8String], (unsigned long)[lv levelIndicatorStyle],
               [lv minValue], [lv maxValue], [lv warningValue], [lv criticalValue], [lv isEditable]);
        [content addSubview:lv];
        [lv setLevelIndicatorStyle:NSLevelIndicatorStyleDiscreteCapacity];
        [lv setMaxValue:10];
        [lv setWarningValue:6];
        [lv setCriticalValue:8];
        [lv setNumberOfTickMarks:11];
        [lv setNumberOfMajorTickMarks:3];
        [lv setTickMarkPosition:NSTickMarkPositionBelow];
        rect("tick 0", [lv rectOfTickMarkAtIndex:0]);
        rect("tick 10", [lv rectOfTickMarkAtIndex:10]);
        @try {
            [lv rectOfTickMarkAtIndex:11];
            printf("tick 11: no exception\n");
        } @catch (NSException *e) {
            printf("tick 11: %s\n", [[e name] UTF8String]);
        }
        [lv setDoubleValue:12];
        printf("set past the end: %g\n", [lv doubleValue]);
        [lv setEditable:YES];
        [lv setTarget:log];
        [lv setAction:@selector(leveled:)];
        NSRect lb = [lv bounds];
        click(w, lv, NSMakePoint(lb.size.width * 0.25, NSMidY(lb)));
        down(w, lv, NSMakePoint(lb.size.width * 0.5, NSMidY(lb)));
        dragged(w, lv, NSMakePoint(lb.size.width * 0.75, NSMidY(lb)));
        up(w, lv, NSMakePoint(lb.size.width * 0.75, NSMidY(lb)));
        [log dump:"clicked and dragged"];
        [lv setContinuous:YES];
        down(w, lv, NSMakePoint(lb.size.width * 0.1, NSMidY(lb)));
        dragged(w, lv, NSMakePoint(lb.size.width * 0.2, NSMidY(lb)));
        up(w, lv, NSMakePoint(lb.size.width * 0.2, NSMidY(lb)));
        [log dump:"continuous"];
        [w makeFirstResponder:lv];
        key(w, NSRightArrowFunctionKey);
        key(w, NSRightArrowFunctionKey);
        key(w, NSLeftArrowFunctionKey);
        [log dump:"keys"];
        for (double v = 2; v <= 10; v += 4) {
            [lv setDoubleValue:v];
            draw(lv, [[NSString stringWithFormat:@"level-discrete-%g", v] UTF8String]);
        }
        NSLevelIndicator *stars = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(200, 300, 80, 16)];
        [stars setLevelIndicatorStyle:NSLevelIndicatorStyleRating];
        [stars setMaxValue:5];
        [stars setEditable:YES];
        [stars setTarget:log];
        [stars setAction:@selector(leveled:)];
        [content addSubview:stars];
        click(w, stars, NSMakePoint(36, 8));
        click(w, stars, NSMakePoint(1, 8));
        click(w, stars, NSMakePoint(79, 8));
        [log dump:"rating clicks"];
        draw(stars, "level-rating");
        NSLevelIndicatorCell *relevancy = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle:NSLevelIndicatorStyleRelevancy];
        printf("relevancy cell: style %lu, max %g\n", (unsigned long)[relevancy levelIndicatorStyle], [relevancy maxValue]);
        NSLevelIndicator *cont = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(200, 280, 100, 16)];
        [cont setLevelIndicatorStyle:NSLevelIndicatorStyleContinuousCapacity];
        [cont setMaxValue:100];
        [cont setWarningValue:70];
        [cont setCriticalValue:90];
        [cont setDoubleValue:95];
        [content addSubview:cont];
        draw(cont, "level-continuous");

        /* ---- colour wells and the colour panel ---- */
        printf("colour panel exists before: %d\n", [NSColorPanel sharedColorPanelExists]);
        NSColorWell *cw = [[NSColorWell alloc] initWithFrame:NSMakeRect(300, 300, 44, 23)];
        NSColorWell *cw2 = [[NSColorWell alloc] initWithFrame:NSMakeRect(350, 300, 44, 23)];
        [content addSubview:cw];
        [content addSubview:cw2];
        printf("well: colour %s, bordered %d, active %d\n", color_text([cw color]), [cw isBordered], [cw isActive]);
        [cw setColor:[NSColor colorWithSRGBRed:0 green:0.5 blue:1 alpha:1]];
        [cw setTarget:log];
        [cw setAction:@selector(wellChanged:)];
        ColorTaker *taker = [[ColorTaker alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        taker.log = log;
        [content addSubview:taker];
        [w makeFirstResponder:taker];
        NSColorPanel *panel = [NSColorPanel sharedColorPanel];
        [panel setTarget:log];
        [panel setAction:@selector(panelChanged:)];
        setenv("FERRY_COLOR_ANSWER", "1 0.25 0", 1);
        [cw2 activate:YES];
        [cw activate:YES];
        printf("activated: well %d, other well %d, panel shown %d, panel colour %s\n", [cw isActive], [cw2 isActive],
               [panel isVisible], color_text([panel color]));
        wait_for(0.1);
        printf("after the panel's answer: well %s, active %d, panel shown %d\n", color_text([cw color]), [cw isActive],
               [panel isVisible]);
        [log dump:"sent"];
        unsetenv("FERRY_COLOR_ANSWER");
        [w makeFirstResponder:nil];
        click(w, cw2, NSMakePoint(22, 11));
        printf("clicked the other well: active %d, panel shown %d\n", [cw2 isActive], [panel isVisible]);
        click(w, cw2, NSMakePoint(22, 11));
        printf("clicked again: active %d\n", [cw2 isActive]);
        [cw activate:YES];
        [panel close];
        printf("panel closed: well active %d\n", [cw isActive]);
        [log dump:"no answer"];
        draw(cw, "well");

        /* ---- date pickers ---- */
        NSTimeZone *gmt = [NSTimeZone timeZoneForSecondsFromGMT:0];
        NSCalendar *greg = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        NSDatePicker *dp = [[NSDatePicker alloc] initWithFrame:NSMakeRect(20, 250, 220, 27)];
        printf("date picker: cell %s, style %lu, elements 0x%lx, mode %lu, bezeled %d\n",
               [NSStringFromClass([[dp cell] class]) UTF8String], (unsigned long)[dp datePickerStyle],
               (unsigned long)[dp datePickerElements], (unsigned long)[dp datePickerMode], [dp isBezeled]);
        [dp setTimeZone:gmt];
        [dp setCalendar:greg];
        [dp setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        [dp setDateValue:gmt_date(2025, 1, 31, 23, 59, 30)];
        [dp setTarget:log];
        [dp setAction:@selector(dated:)];
        [content addSubview:dp];
        printf("shown: \"%s\", size %.0fx%.0f\n", [[dp stringValue] UTF8String], [dp intrinsicContentSize].width,
               [dp intrinsicContentSize].height);
        [w makeFirstResponder:dp];
        key(w, NSUpArrowFunctionKey);   /* the month */
        key(w, '\t');
        key(w, NSUpArrowFunctionKey);   /* the day: the 28th of February is the last */
        key(w, NSUpArrowFunctionKey);
        [log dump:"month and day"];
        key(w, NSRightArrowFunctionKey);
        key(w, NSRightArrowFunctionKey);
        key(w, NSUpArrowFunctionKey);   /* the hour */
        key(w, NSRightArrowFunctionKey);
        key(w, NSUpArrowFunctionKey);   /* the minute wraps without carrying */
        key(w, NSRightArrowFunctionKey);
        key(w, NSRightArrowFunctionKey);
        key(w, 'a');                    /* AM */
        key(w, 'p');
        [log dump:"time"];
        [w makeFirstResponder:nil];
        [w makeFirstResponder:dp];      /* the month again */
        type(w, @"12");                 /* moves on to the day */
        type(w, @"25");
        type(w, @"1999");
        [log dump:"typed"];
        key(w, NSLeftArrowFunctionKey);   /* from the hour back to the month */
        key(w, NSLeftArrowFunctionKey);
        key(w, NSLeftArrowFunctionKey);
        type(w, @"3");                  /* no month starts 3x: the day is next */
        type(w, @"05");
        [log dump:"typed a single-digit month"];
        [dp setMinDate:gmt_date(1999, 3, 1, 0, 0, 0)];
        [dp setMaxDate:gmt_date(1999, 3, 31, 0, 0, 0)];
        printf("kept between the limits: \"%s\"\n", [[dp stringValue] UTF8String]);
        [w makeFirstResponder:nil];
        [w makeFirstResponder:dp];
        key(w, NSDownArrowFunctionKey);
        [log dump:"below the minimum"];
        [dp setMinDate:nil];
        [dp setMaxDate:nil];
        [dp setDelegate:log];
        log.noWeekends = YES;
        [dp setDateValue:gmt_date(2025, 6, 6, 9, 0, 0)];   /* a Friday */
        [w makeFirstResponder:nil];
        [w makeFirstResponder:dp];
        key(w, '\t');
        key(w, NSUpArrowFunctionKey);
        [log dump:"delegate"];
        log.noWeekends = NO;
        [dp setDelegate:nil];
        draw(dp, "date-text");
        NSRect stepper = NSMakeRect([dp bounds].size.width - 19, 0, 19, 27);
        [dp setDateValue:gmt_date(2025, 6, 6, 9, 0, 0)];
        [w makeFirstResponder:nil];
        click(w, dp, NSMakePoint(NSMidX(stepper), 7));
        click(w, dp, NSMakePoint(NSMidX(stepper), 20));
        click(w, dp, NSMakePoint(NSMidX(stepper), 20));
        [log dump:"stepper part"];

        NSDatePicker *cal = [[NSDatePicker alloc] initWithFrame:NSMakeRect(20, 20, 280, 160)];
        [cal setDatePickerStyle:NSDatePickerStyleClockAndCalendar];
        [cal setDatePickerElements:NSDatePickerElementFlagYearMonthDay];
        [cal setTimeZone:gmt];
        [cal setCalendar:greg];
        [cal setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        [cal setDateValue:gmt_date(2025, 6, 18, 14, 30, 0)];
        [cal setTarget:log];
        [cal setAction:@selector(dated:)];
        [content addSubview:cal];
        printf("calendar: size %.0fx%.0f\n", [cal intrinsicContentSize].width, [cal intrinsicContentSize].height);
        /* June 2025 starts on a Sunday: the 1st is the first box, the 10th
         * the third of the second row */
        click(w, cal, NSMakePoint(6 + 2 * 20 + 10, 6 + 24 + 16 + 1 * 18 + 9));
        click(w, cal, NSMakePoint(6 + 140 - 8, 6 + 12));      /* the next month */
        [w makeFirstResponder:cal];
        key(w, NSRightArrowFunctionKey);
        key(w, NSUpArrowFunctionKey);
        [log dump:"calendar"];
        [cal setDatePickerMode:NSDatePickerModeRange];
        [cal setDateValue:gmt_date(2025, 6, 18, 14, 30, 0)];
        down(w, cal, NSMakePoint(6 + 1 * 20 + 10, 6 + 24 + 16 + 1 * 18 + 9));   /* the 9th */
        dragged(w, cal, NSMakePoint(6 + 4 * 20 + 10, 6 + 24 + 16 + 2 * 18 + 9)); /* the 19th */
        up(w, cal, NSMakePoint(6 + 4 * 20 + 10, 6 + 24 + 16 + 2 * 18 + 9));
        printf("range: %s for %.0f days\n", [[[cal dateValue] description] UTF8String], [cal timeInterval] / 86400);
        [log dump:"range"];
        draw(cal, "date-calendar");
        [cal setDatePickerElements:NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinuteSecond];
        [cal setFrameSize:[cal intrinsicContentSize]];
        printf("calendar and clock: size %.0fx%.0f\n", [cal intrinsicContentSize].width, [cal intrinsicContentSize].height);
        draw(cal, "date-clock");
        [cal removeFromSuperview];
        [dp removeFromSuperview];

        /* ---- combo boxes ---- */
        NSComboBox *cb = [[NSComboBox alloc] initWithFrame:NSMakeRect(20, 250, 160, 22)];
        printf("combo box: cell %s, visible %ld, item height %g, spacing %gx%g, completes %d, scroller %d\n",
               [NSStringFromClass([[cb cell] class]) UTF8String], (long)[cb numberOfVisibleItems], [cb itemHeight],
               [cb intercellSpacing].width, [cb intercellSpacing].height, [cb completes], [cb hasVerticalScroller]);
        [cb addItemsWithObjectValues:@[ @"Apple", @"Apricot", @"Banana", @"Blueberry", @"Cherry", @"Date", @"Fig" ]];
        [cb insertItemWithObjectValue:@"Avocado" atIndex:2];
        [cb removeItemWithObjectValue:@"Date"];
        printf("items %ld: %s, \"Banana\" at %ld, selected %ld\n", (long)[cb numberOfItems],
               [[[cb objectValues] componentsJoinedByString:@","] UTF8String],
               (long)[cb indexOfItemWithObjectValue:@"Banana"], (long)[cb indexOfSelectedItem]);
        [cb setDelegate:log];
        [cb setTarget:log];
        [cb setAction:@selector(combo:)];
        [content addSubview:cb];
        [cb selectItemAtIndex:3];
        printf("selected 3: \"%s\", %s\n", [[cb stringValue] UTF8String], [[cb objectValueOfSelectedItem] UTF8String]);
        [log dump:"select"];
        NSRect button = NSMakeRect(160 - 18, 0, 18, 22);
        click(w, cb, mid(button));
        NSView *list = [w _overlayView];
        printf("list open: %d\n", list != nil);
        [log dump:"opened"];
        draw_window(w, "combo-open");
        key(w, NSDownArrowFunctionKey);
        key(w, NSDownArrowFunctionKey);
        printf("moved down twice: \"%s\" %ld\n", [[cb stringValue] UTF8String], (long)[cb indexOfSelectedItem]);
        key(w, '\r');
        printf("list open after Return: %d\n", [w _overlayView] != nil);
        [log dump:"chose with the keys"];
        click(w, cb, mid(button));
        /* the list is below the field: the first row */
        NSRect field = [cb convertRect:[cb bounds] toView:nil];
        NSPoint row0 = NSMakePoint(NSMidX(field), NSMinY(field) - 1 - 2 - 9);
        [w sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:row0 modifierFlags:0 timestamp:0
                                    windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1]];
        NSPoint row1 = NSMakePoint(row0.x, row0.y - 18);
        [w sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:row1 modifierFlags:0 timestamp:0
                                    windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1]];
        [w sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:row1 modifierFlags:0 timestamp:0
                                    windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1]];
        printf("clicked the second row: \"%s\" %ld, open %d\n", [[cb stringValue] UTF8String],
               (long)[cb indexOfSelectedItem], [w _overlayView] != nil);
        [log dump:"chose with the mouse"];
        click(w, cb, mid(button));
        key(w, 27);
        printf("Escape: open %d\n", [w _overlayView] != nil);
        [log dump:"dismissed"];
        click(w, cb, mid(button));
        click(w, content, NSMakePoint(400, 20));
        printf("clicked elsewhere: open %d\n", [w _overlayView] != nil);
        [log dump:"clicked elsewhere"];
        [cb setCompletes:YES];
        [cb setStringValue:@""];
        [w makeFirstResponder:cb];
        type(w, @"bl");
        printf("completed \"bl\": \"%s\", selected %ld\n", [[cb stringValue] UTF8String], (long)[cb indexOfSelectedItem]);
        key(w, NSBackspaceCharacter);
        printf("Backspace: \"%s\"\n", [[cb stringValue] UTF8String]);
        key(w, 127);
        key(w, 127);
        type(w, @"aPr");
        printf("completed \"aPr\": \"%s\"\n", [[cb stringValue] UTF8String]);
        type(w, @"x");
        printf("typed over the completion: \"%s\", selected %ld\n", [[cb stringValue] UTF8String],
               (long)[cb indexOfSelectedItem]);
        [log dump:"completion"];
        [w makeFirstResponder:nil];
        [cb setStringValue:@"Banana"];
        [w makeFirstResponder:cb];
        key(w, NSDownArrowFunctionKey);
        printf("down with the list closed: \"%s\" %ld\n", [[cb stringValue] UTF8String], (long)[cb indexOfSelectedItem]);
        key(w, NSUpArrowFunctionKey);
        key(w, NSUpArrowFunctionKey);
        printf("up twice: \"%s\" %ld\n", [[cb stringValue] UTF8String], (long)[cb indexOfSelectedItem]);
        [log dump:"arrows"];
        [w makeFirstResponder:nil];
        NSComboBox *ds = [[NSComboBox alloc] initWithFrame:NSMakeRect(200, 250, 160, 22)];
        [ds setUsesDataSource:YES];
        [ds setDataSource:log];
        [ds setCompletes:YES];
        [content addSubview:ds];
        printf("data source: %ld items, item 5 \"%s\"\n", (long)[ds numberOfItems],
               [[ds itemObjectValueAtIndex:5] UTF8String]);
        [ds scrollItemAtIndexToVisible:30];
        [ds selectItemAtIndex:30];
        printf("selected 30: \"%s\"\n", [[ds stringValue] UTF8String]);
        [w makeFirstResponder:ds];
        [ds setStringValue:@""];
        [w makeFirstResponder:nil];
        [w makeFirstResponder:ds];
        type(w, @"It");
        printf("data source completed \"It\": \"%s\"\n", [[ds stringValue] UTF8String]);
        [w makeFirstResponder:nil];
        click(w, ds, NSMakePoint(160 - 9, 11));
        draw_window(w, "combo-data-source");
        key(w, 27);
        draw(cb, "combo");
        [cb removeFromSuperview];
        [ds removeFromSuperview];
        [log dump:"data source"];

        /* ---- popovers ---- */
        NSPopover *pop = [[NSPopover alloc] init];
        printf("popover: behavior %ld, animates %d, shown %d, size %.0fx%.0f\n", (long)[pop behavior], [pop animates],
               [pop isShown], [pop contentSize].width, [pop contentSize].height);
        NSViewController *vc = [[NSViewController alloc] init];
        NSView *inside = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 160, 80)];
        NSButton *inButton = [NSButton buttonWithTitle:@"Inside" target:log action:@selector(clicked:)];
        [inButton setFrame:NSMakeRect(20, 20, 100, 24)];
        [inside addSubview:inButton];
        [vc setView:inside];
        [pop setContentViewController:vc];
        [pop setDelegate:log];
        printf("size from the view: %.0fx%.0f\n", [pop contentSize].width, [pop contentSize].height);
        NSButton *anchor = [NSButton buttonWithTitle:@"Show" target:log action:@selector(clicked:)];
        [anchor setFrame:NSMakeRect(180, 160, 80, 24)];
        [content addSubview:anchor];
        NSButton *outside = [NSButton buttonWithTitle:@"Outside" target:log action:@selector(clicked:)];
        [outside setFrame:NSMakeRect(20, 20, 80, 24)];
        [content addSubview:outside];
        @try {
            [[[NSPopover alloc] init] showRelativeToRect:NSZeroRect ofView:anchor preferredEdge:NSRectEdgeMaxY];
        } @catch (NSException *e) {
            printf("no content: %s\n", [[e name] UTF8String]);
        }
        [pop showRelativeToRect:NSZeroRect ofView:anchor preferredEdge:NSRectEdgeMaxY];
        printf("shown %d, overlay %d, view in a window %d\n", [pop isShown], [w _overlayView] != nil, [inside window] == w);
        rect("content view in the window", [inside convertRect:[inside bounds] toView:nil]);
        [log dump:"show"];
        draw_window(w, "popover");
        click(w, inButton, NSMakePoint(50, 12));
        printf("clicked inside: shown %d\n", [pop isShown]);
        [log dump:"inside"];
        click(w, outside, NSMakePoint(40, 12));
        printf("clicked outside (application defined): shown %d\n", [pop isShown]);
        [log dump:"outside"];
        [pop setBehavior:NSPopoverBehaviorTransient];
        log.refuseClose = YES;
        click(w, outside, NSMakePoint(40, 12));
        printf("clicked outside, refused: shown %d\n", [pop isShown]);
        log.refuseClose = NO;
        [log dump:"refused"];
        click(w, outside, NSMakePoint(40, 12));
        printf("clicked outside (transient): shown %d, overlay %d, view in a window %d\n", [pop isShown],
               [w _overlayView] != nil, [inside window] != nil);
        [log dump:"closed by a click"];
        [pop setBehavior:NSPopoverBehaviorSemitransient];
        [pop setContentSize:NSMakeSize(200, 60)];
        [pop showRelativeToRect:NSZeroRect ofView:anchor preferredEdge:NSRectEdgeMinY];
        rect("below the button", [inside convertRect:[inside bounds] toView:nil]);
        key(w, 27);
        printf("Escape: shown %d\n", [pop isShown]);
        [log dump:"semitransient"];
        NSButton *high = [NSButton buttonWithTitle:@"High" target:nil action:NULL];
        [high setFrame:NSMakeRect(380, 320, 60, 24)];
        [content addSubview:high];
        [pop showRelativeToRect:NSZeroRect ofView:high preferredEdge:NSRectEdgeMaxY];
        rect("no room above: below instead, kept in the window", [inside convertRect:[inside bounds] toView:nil]);
        [pop setContentSize:NSMakeSize(100, 40)];
        rect("a new size", [inside convertRect:[inside bounds] toView:nil]);
        [pop performClose:nil];
        printf("performClose: shown %d\n", [pop isShown]);
        [log dump:"edges"];
        [pop setDelegate:nil];
        NSViewController *presenter = [[NSViewController alloc] init];
        [presenter setView:[[NSView alloc] initWithFrame:NSZeroRect]];
        NSViewController *shown = [[NSViewController alloc] init];
        [shown setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 50)]];
        [presenter presentViewController:shown asPopoverRelativeToRect:[anchor bounds] ofView:anchor
                           preferredEdge:NSRectEdgeMaxY behavior:NSPopoverBehaviorTransient];
        printf("presented as a popover: in the window %d, overlay %d\n", [[shown view] window] == w, [w _overlayView] != nil);
        [presenter dismissViewController:shown];
        printf("dismissed: in a window %d, overlay %d\n", [[shown view] window] != nil, [w _overlayView] != nil);
        [anchor removeFromSuperview];
        [outside removeFromSuperview];
        [high removeFromSuperview];
        [log dump:"presented"];

        /* ---- path controls ---- */
        NSPathControl *pc = [[NSPathControl alloc] initWithFrame:NSMakeRect(20, 200, 400, 22)];
        printf("path control: cell %s, style %ld, URL %s\n", [NSStringFromClass([[pc cell] class]) UTF8String],
               (long)[pc pathStyle], [[[pc URL] description] UTF8String]);
        [pc setURL:[NSURL fileURLWithPath:@"/usr/share/doc"]];
        [content addSubview:pc];
        printf("components: %s; cells %lu, first image %d\n", [path_titles(pc) UTF8String],
               (unsigned long)[[pc pathComponentCells] count], [[[pc pathComponentCells] firstObject] image] != nil);
        [pc setTarget:log];
        [pc setAction:@selector(pathClicked:)];
        [pc setDoubleAction:@selector(pathDoubleClicked:)];
        [pc setDelegate:log];
        NSPathCell *pcell = [pc cell];
        NSArray *pcells = [pc pathComponentCells];
        NSRect second = [pcell rectOfPathComponentCell:pcells[1] withFrame:[pc bounds] inView:pc];
        rect("second component", second);
        click(w, pc, mid(second));
        double_click(w, pc, mid([pcell rectOfPathComponentCell:pcells[3] withFrame:[pc bounds] inView:pc]));
        down(w, pc, mid(second));
        up(w, pc, NSMakePoint(399, 11));
        [log dump:"clicks"];
        [pc setURL:[NSURL URLWithString:@"https://example.org/docs/guide/index.html"]];
        printf("a web address: %s\n", [path_titles(pc) UTF8String]);
        [pc setPathItems:@[]];
        [pc setPlaceholderString:@"No file"];
        printf("no items: URL %s, placeholder \"%s\"\n", [[[pc URL] description] UTF8String],
               [[pc placeholderString] UTF8String]);
        draw(pc, "path-empty");
        NSPathControlItem *a = [[NSPathControlItem alloc] init];
        [a setTitle:@"Projects"];
        NSPathControlItem *b = [[NSPathControlItem alloc] init];
        [b setTitle:@"Ferry"];
        [pc setPathItems:@[ a, b ]];
        printf("own items: %s\n", [path_titles(pc) UTF8String]);
        [pc setURL:[NSURL fileURLWithPath:@"/usr/share/doc/a-very-long-folder-name-to-cut-short/another-long-one/and-the-last"]];
        [pc setFrameSize:NSMakeSize(330, 22)];
        NSArray *longCells = [pc pathComponentCells];
        rect("long path, last component", [pcell rectOfPathComponentCell:[longCells lastObject] withFrame:[pc bounds] inView:pc]);
        rect("long path, a middle one", [pcell rectOfPathComponentCell:longCells[4] withFrame:[pc bounds] inView:pc]);
        draw(pc, "path-long");
        [pc setFrameSize:NSMakeSize(400, 22)];
        [pc setURL:[NSURL fileURLWithPath:@"/usr/share/doc"]];
        draw(pc, "path");
        [pc setPathStyle:NSPathStylePopUp];
        click(w, pc, NSMakePoint(40, 11));
        printf("pop-up menu open: %d\n", [w _overlayView] != nil);
        draw_window(w, "path-popup");
        key(w, NSDownArrowFunctionKey);
        key(w, '\r');
        [log dump:"pop-up"];
        [pc removeFromSuperview];

        /* ---- sounds ---- */
        NSString *home = NSHomeDirectory();
        NSString *sounds = [home stringByAppendingPathComponent:@"sounds"];
        [[NSFileManager defaultManager] createDirectoryAtPath:sounds withIntermediateDirectories:YES attributes:nil error:NULL];
        write_wav([sounds stringByAppendingPathComponent:@"alert-bell.wav"], 2);
        write_wav([sounds stringByAppendingPathComponent:@"pop.wav"], 1);
        setenv("FERRY_SOUNDS_DIR", [sounds fileSystemRepresentation], 1);
        printf("types: %lu, includes WAV %d\n", (unsigned long)[[NSSound soundUnfilteredTypes] count],
               [[NSSound soundUnfilteredTypes] containsObject:@"com.microsoft.waveform-audio"]);
        NSSound *glass = [NSSound soundNamed:@"Glass"];
        printf("Glass: %s, name %s, duration %.1f, same again %d\n", glass ? "found" : "missing",
               [[glass name] UTF8String], [glass duration], [NSSound soundNamed:@"Glass"] == glass);
        printf("Pop: %s; pop: %s; Basso: %s\n", [NSSound soundNamed:@"Pop"] ? "found" : "missing",
               [NSSound soundNamed:@"pop"] ? "found" : "missing", [NSSound soundNamed:@"Basso"] ? "found" : "missing");
        printf("no such file: %d\n", [[NSSound alloc] initWithContentsOfFile:@"/no/such.wav" byReference:YES] != nil);
        [glass setDelegate:log];
        BOOL played = [glass play];
        printf("play: %d, playing %d, again %d\n", played, [glass isPlaying], [glass play]);
        wait_until(^{ return (BOOL)![glass isPlaying]; }, 5);
        printf("finished: playing %d\n", [glass isPlaying]);
        [log dump:"played"];
        NSString *player_log = [home stringByAppendingPathComponent:@"player.log"];
        BOOL (^logged)(NSUInteger) = ^BOOL(NSUInteger lines) {
            NSString *text = [NSString stringWithContentsOfFile:player_log encoding:NSUTF8StringEncoding error:NULL];
            return [[text componentsSeparatedByString:@"\n"] count] > lines;
        };
        [glass setVolume:0.5];
        [glass play];
        wait_until(^{ return logged(2); }, 5);
        printf("pause %d, pause again %d, resume %d\n", [glass pause], [glass pause], [glass resume]);
        printf("stop %d, playing %d, stop again %d\n", [glass stop], [glass isPlaying], [glass stop]);
        [log dump:"stopped"];
        NSData *wav = [NSData dataWithContentsOfFile:[sounds stringByAppendingPathComponent:@"pop.wav"]];
        NSSound *fromData = [[NSSound alloc] initWithData:wav];
        [fromData setDelegate:log];
        printf("from data: duration %.1f, name set %d, taken again %d\n", [fromData duration], [fromData setName:@"Mine"],
               [[NSSound soundNamed:@"Mine"] isEqual:fromData]);
        [fromData setLoops:YES];
        [fromData play];
        wait_until(^{ return logged(4); }, 5);   /* played twice */
        printf("looping: playing %d\n", [fromData isPlaying]);
        [fromData stop];
        [log dump:"from data"];
        NSString *played_log = [NSString stringWithContentsOfFile:player_log encoding:NSUTF8StringEncoding error:NULL];
        printf("the player was given:\n%s", [played_log UTF8String] ?: "(nothing)\n");

        /* ---- token fields ---- */
        NSTokenField *tf = [[NSTokenField alloc] initWithFrame:NSMakeRect(20, 200, 400, 22)];
        printf("token field: cell %s, style %lu, tokenizing \",\" %d, delay %g\n",
               [NSStringFromClass([[tf cell] class]) UTF8String], (unsigned long)[tf tokenStyle],
               [[tf tokenizingCharacterSet] characterIsMember:','], [tf completionDelay]);
        [content addSubview:tf];
        [tf setObjectValue:@[ @"one", @"two" ]];
        printf("set: %s, \"%s\"\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String], [[tf stringValue] UTF8String]);
        [tf setDelegate:log];
        [tf setTarget:log];
        [tf setAction:@selector(tokens:)];
        [w makeFirstResponder:tf];
        type(w, @"three, four,fi");
        printf("typed: %s, \"%s\"\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String], [[tf stringValue] UTF8String]);
        draw(tf, "tokens-editing");
        key(w, '\r');
        printf("Return: %s\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String]);
        key(w, 127);
        key(w, 127);
        printf("Backspace twice: %s\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String]);
        log.upperTokens = YES;
        type(w, @"six,no,");
        log.upperTokens = NO;
        printf("the delegate's tokens: %s\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String]);
        type(w, @"seven");
        [w makeFirstResponder:nil];
        printf("editing ended: %s\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String]);
        [log dump:"tokens"];
        [tf setStringValue:@"a, b ,c"];
        printf("a string: %s\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String]);
        [tf setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@";"]];
        [w makeFirstResponder:tf];
        type(w, @"x,y;z;");
        printf("tokenized at \";\": %s\n", [[[tf objectValue] componentsJoinedByString:@"|"] UTF8String]);
        [w makeFirstResponder:nil];
        draw(tf, "tokens");
        [log dump:"more tokens"];
        [tf removeFromSuperview];

        /* ---- from a nib ---- */
        NSString *path = [NSString stringWithFormat:@"%s/MoreControls.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        MoreOwner *owner = [[MoreOwner alloc] init];
        NSArray *top_level = nil;
        printf("nib loaded: %d\n", [nib instantiateWithOwner:owner topLevelObjects:&top_level]);
        NSStepper *ns = owner.stepper;
        printf("stepper %s: min %g max %g increment %g value %g autorepeat %d wraps %d, target owner %d, action %s\n",
               [NSStringFromClass([ns class]) UTF8String], [ns minValue], [ns maxValue], [ns increment], [ns doubleValue],
               [ns autorepeat], [ns valueWraps], [ns target] == owner, [NSStringFromSelector([ns action]) UTF8String]);
        NSLevelIndicator *nl = owner.level;
        printf("level %s: style %lu, max %g, value %g\n", [NSStringFromClass([nl class]) UTF8String],
               (unsigned long)[nl levelIndicatorStyle], [nl maxValue], [nl doubleValue]);
        printf("well %s: %s, bordered %d\n", [NSStringFromClass([owner.well class]) UTF8String],
               color_text([owner.well color]), [owner.well isBordered]);
        NSDatePicker *np = owner.picker;
        [np setTimeZone:gmt];
        [np setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        printf("date picker %s: elements 0x%lx, style %lu, \"%s\"\n", [NSStringFromClass([np class]) UTF8String],
               (unsigned long)[np datePickerElements], (unsigned long)[np datePickerStyle], [[np stringValue] UTF8String]);
        NSComboBox *nc = owner.combo;
        printf("combo box %s: %s, completes %d, visible %ld\n", [NSStringFromClass([nc class]) UTF8String],
               [[[nc objectValues] componentsJoinedByString:@","] UTF8String], [nc completes],
               (long)[nc numberOfVisibleItems]);
        printf("path control %s: %s\n", [NSStringFromClass([owner.pathControl class]) UTF8String],
               [path_titles(owner.pathControl) UTF8String]);
        printf("token field %s: %s, style %lu\n", [NSStringFromClass([owner.tokens class]) UTF8String],
               [[[owner.tokens objectValue] componentsJoinedByString:@"|"] UTF8String],
               (unsigned long)[owner.tokens tokenStyle]);
        NSWindow *nw = owner.window;
        [nw makeKeyAndOrderFront:nil];
        NSRect nb = [ns bounds];
        click(nw, ns, NSMakePoint(NSMidX(nb), [ns isFlipped] ? 6 : nb.size.height - 6));
        printf("stepped in the nib: %g, owner told %ld\n", [ns doubleValue], (long)owner.steps);
        draw([nw contentView], "nib");
    }
    return 0;
}
