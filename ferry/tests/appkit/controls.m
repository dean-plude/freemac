/* SPDX-License-Identifier: GPL-3.0-or-later
 * More controls, with no display: pop-up buttons (a pop-up list and a
 * pull-down list, chosen by a click and a click, by press, drag and
 * release, by the keys and by typing, with the menu's delegate and the
 * items' own actions); segmented controls (select one, select any and
 * momentary, disabled segments, drags off a segment, the distributions,
 * a segment's menu and the keys with full keyboard access); search fields
 * (searching after a pause, at once or on Return, the clear button and
 * Escape, recent searches kept and saved, and the search menu); stack
 * views laid out in rows and columns (gravity areas, every distribution,
 * the alignments, hidden views, custom spacing, insets, views detached
 * for want of room and nested stacks); toolbars (a delegate's items, the
 * standard ones, the strip and the window's frame in every display and
 * size mode, validation, clicks, selectable items, items added and
 * removed, the overflow menu and the saved configuration); and all of
 * them loaded from a nib (Controls.nib, from make_nibs.py). Pictures go
 * to the directory FERRY_CONTROLS_PNG names, if it is set. */
#import <Cocoa/Cocoa.h>

/* Ferry's own: the window's open menu and toolbar strip, for a look. */
@interface NSWindow (FerryPeek)
- (NSView *)_overlayView;
- (NSView *)_toolbarView;
@end
@interface NSView (FerryMenuPeek)
- (NSMenu *)menu;
- (NSInteger)highlightedIndex;
- (NSRect)menuRect;
- (NSRect)rectOfItemAtIndex:(NSInteger)index;
@end

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
static NSPoint mid(NSRect r) { return NSMakePoint(NSMidX(r), NSMidY(r)); }
static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
}
static void down(NSWindow *w, NSView *v, NSPoint p) { [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, p)]; }
static void up(NSWindow *w, NSView *v, NSPoint p) { [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, p)]; }
static void dragged(NSWindow *w, NSView *v, NSPoint p) { [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, v, p)]; }
static void click(NSWindow *w, NSView *v, NSPoint p)
{
    down(w, v, p);
    up(w, v, p);
}
static void key(NSWindow *w, unichar c)
{
    NSString *s = [NSString stringWithFormat:@"%C", c];
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}
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
        [png writeToFile:[NSString stringWithFormat:@"%s/controls-%s.png", dir, name] atomically:YES];
    }
}
/* The whole window, toolbar and open menu included, as it shows. */
static void draw_window(NSWindow *w, const char *name)
{
    const char *dir = getenv("FERRY_CONTROLS_PNG");
    if (!dir)
        return;
    NSSize s = [w frame].size;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)s.width
                                                                    pixelsHigh:(NSInteger)s.height bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(NSMakeRect(0, 0, s.width, s.height));
    NSView *content = [w contentView], *strip = [w _toolbarView], *menu = [w _overlayView];
    for (NSView *v in @[ content ?: [NSNull null], strip ?: [NSNull null], menu ?: [NSNull null] ]) {
        if (![v isKindOfClass:[NSView class]] || [v isHidden])
            continue;
        NSBitmapImageRep *part = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
        [v cacheDisplayInRect:[v bounds] toBitmapImageRep:part];
        [part drawInRect:[v frame]];
    }
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[NSString stringWithFormat:@"%s/controls-%s.png", dir, name] atomically:YES];
}

/* ---- what the controls send ---- */

@interface Log : NSObject <NSMenuDelegate, NSSearchFieldDelegate, NSStackViewDelegate, NSToolbarDelegate,
                           NSToolbarItemValidation>
@property (strong) NSMutableArray *lines;
@property BOOL refuseShare;
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
- (void)popped:(NSPopUpButton *)p
{
    [self add:[NSString stringWithFormat:@"popped %ld \"%@\"", (long)[p indexOfSelectedItem], [p titleOfSelectedItem]]];
}
- (void)own:(NSMenuItem *)item { [self add:[NSString stringWithFormat:@"own action of \"%@\"", [item title]]]; }
- (void)menuNeedsUpdate:(NSMenu *)m { [self add:@"needs update"]; }
- (void)menuWillOpen:(NSMenu *)m { [self add:@"will open"]; }
- (void)menuDidClose:(NSMenu *)m { [self add:@"did close"]; }
- (void)willPopUp:(NSNotification *)n { [self add:@"will pop up"]; }
- (void)segmented:(NSSegmentedControl *)s
{
    NSMutableArray *on = [NSMutableArray array];
    for (NSInteger i = 0; i < [s segmentCount]; i++)
        if ([s isSelectedForSegment:i])
            [on addObject:[NSString stringWithFormat:@"%ld", (long)i]];
    [self add:[NSString stringWithFormat:@"segment %ld [%@]", (long)[s selectedSegment], [on componentsJoinedByString:@","]]];
}
- (void)segmentMenu:(NSMenuItem *)item { [self add:[NSString stringWithFormat:@"segment menu \"%@\"", [item title]]]; }
- (void)searched:(NSSearchField *)f { [self add:[NSString stringWithFormat:@"search \"%@\"", [f stringValue]]]; }
- (void)searchFieldDidStartSearching:(NSSearchField *)f { [self add:@"started"]; }
- (void)searchFieldDidEndSearching:(NSSearchField *)f { [self add:@"ended"]; }
- (void)stackView:(NSStackView *)s willDetachViews:(NSArray *)views
{
    [self add:[NSString stringWithFormat:@"detach %lu", (unsigned long)[views count]]];
}
- (void)stackView:(NSStackView *)s didReattachViews:(NSArray *)views
{
    [self add:[NSString stringWithFormat:@"reattach %lu", (unsigned long)[views count]]];
}

/* the toolbar's items */
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t
{
    return @[ @"open", @"find", NSToolbarFlexibleSpaceItemIdentifier, @"share", @"info" ];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)t
{
    return @[ @"open", @"find", @"share", @"info", @"extra", NSToolbarFlexibleSpaceItemIdentifier,
              NSToolbarSpaceItemIdentifier ];
}
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)t { return @[ @"info" ]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    [item setLabel:[ident capitalizedString]];
    [item setTarget:self];
    [item setAction:@selector(tool:)];
    if ([ident isEqualToString:@"find"]) {
        NSSearchField *f = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)];
        [item setView:f];
        [item setMinSize:NSMakeSize(80, 22)];
        [item setMaxSize:NSMakeSize(160, 22)];
    } else {
        BOOL round = [ident isEqualToString:@"info"] || [ident isEqualToString:@"extra"];
        NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect r) {
            NSBezierPath *p = round ? [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 2, 2)]
                                    : [NSBezierPath bezierPathWithRect:NSInsetRect(r, 3, 4)];
            [p setLineWidth:1.5];
            [[NSColor blackColor] setStroke];
            [p stroke];
            return YES;
        }];
        [image setTemplate:YES];
        [item setImage:image];
    }
    if ([ident isEqualToString:@"share"])
        [item setVisibilityPriority:NSToolbarItemVisibilityPriorityLow];
    [self add:[NSString stringWithFormat:@"made %@%s", ident, flag ? "" : " (not to insert)"]];
    return item;
}
- (void)toolbarWillAddItem:(NSNotification *)n
{
    [self add:[NSString stringWithFormat:@"will add %@", [n.userInfo[@"item"] itemIdentifier]]];
}
- (void)toolbarDidRemoveItem:(NSNotification *)n
{
    [self add:[NSString stringWithFormat:@"did remove %@", [n.userInfo[@"item"] itemIdentifier]]];
}
- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
    return !([[item itemIdentifier] isEqualToString:@"share"] && _refuseShare);
}
- (void)tool:(id)sender
{
    [self add:[NSString stringWithFormat:@"tool %@ from %@", [sender isKindOfClass:[NSToolbarItem class]]
                                                                 ? [sender itemIdentifier] : [sender title],
                                         NSStringFromClass([sender class])]];
}
@end

/* A view of a set size, as a label or a button has. */
@interface Box : NSView
@property NSSize size;
@end
@implementation Box
- (NSSize)intrinsicContentSize { return _size; }
@end
static Box *box(CGFloat w, CGFloat h)
{
    Box *b = [[Box alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    b.size = NSMakeSize(w, h);
    return b;
}
static void frames(const char *what, NSStackView *s)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSView *v in [s views]) {
        NSRect f = [v frame];
        BOOL shown = [v superview] == s && ![v isHidden];
        [a addObject:[NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f%s", f.origin.x, f.origin.y, f.size.width,
                                                f.size.height, shown ? "" : " (out)"]];
    }
    printf("%s: %s\n", what, [[a componentsJoinedByString:@" | "] UTF8String]);
}

/* the nib's owner */
@interface ControlsOwner : NSObject <NSToolbarDelegate>
@property (strong) NSWindow *window;
@property (strong) NSPopUpButton *popup;
@property (strong) NSSegmentedControl *segments;
@property (strong) NSSearchField *search;
@property (strong) NSStackView *stack;
@property (strong) NSToolbar *toolbar;
@property (strong) NSMutableArray *lines;
@end
@implementation ControlsOwner
- (instancetype)init
{
    if ((self = [super init]))
        _lines = [NSMutableArray array];
    return self;
}
- (void)sizeChosen:(NSPopUpButton *)p { [_lines addObject:[@"size " stringByAppendingString:[p titleOfSelectedItem]]]; }
- (void)openThing:(id)sender { [_lines addObject:[@"open from " stringByAppendingString:NSStringFromClass([sender class])]]; }
@end

static NSString *titles(NSArray *items)
{
    NSMutableArray *a = [NSMutableArray array];
    for (id i in items)
        [a addObject:[i isKindOfClass:[NSToolbarItem class]] ? [i itemIdentifier]
                     : [i isSeparatorItem]                    ? @"-"
                                                              : [i title]];
    return [a componentsJoinedByString:@", "];
}
static NSString *states(NSPopUpButton *p)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSMenuItem *i in [p itemArray])
        if (![i isSeparatorItem])
            [a addObject:[NSString stringWithFormat:@"%ld", (long)[i state]]];
    return [a componentsJoinedByString:@""];
}
static NSArray *buttons_of(NSWindow *w)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSView *v in [[w _toolbarView] subviews])
        if ([NSStringFromClass([v class]) isEqualToString:@"AToolbarButton"])
            [a addObject:v];
    return a;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];
        NSView *content = [w contentView];
        Log *log = [[Log alloc] init];

        /* ---- a pop-up list ---- */
        NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 200, 140, 25) pullsDown:NO];
        [pop addItemsWithTitles:@[ @"Red", @"Green", @"Blue" ]];
        [[pop menu] addItem:[NSMenuItem separatorItem]];
        [pop addItemWithTitle:@"Other"];
        [[pop lastItem] setTag:9];
        [pop addItemWithTitle:@"Red"];       /* a title already there moves to the end */
        [pop setTarget:log];
        [pop setAction:@selector(popped:)];
        [[pop menu] setDelegate:log];
        [content addSubview:pop];
        [[NSNotificationCenter defaultCenter] addObserver:log selector:@selector(willPopUp:)
                                                     name:NSPopUpButtonWillPopUpNotification object:pop];
        printf("pop-up: %s; %ld items, chosen %ld \"%s\", title \"%s\", states %s, tag of Other at %ld, pulls down %d\n",
               [titles([pop itemArray]) UTF8String], (long)[pop numberOfItems], (long)[pop indexOfSelectedItem],
               [[pop titleOfSelectedItem] UTF8String], [[pop title] UTF8String], [states(pop) UTF8String],
               (long)[pop indexOfItemWithTag:9], [pop pullsDown]);
        printf("intrinsic size %.0fx%.0f; cell %s\n", [pop intrinsicContentSize].width,
               [pop intrinsicContentSize].height, [NSStringFromClass([[pop cell] class]) UTF8String]);
        [pop selectItemWithTitle:@"Blue"];
        printf("selected by title: %ld \"%s\", object value %s, states %s\n", (long)[pop indexOfSelectedItem],
               [[pop title] UTF8String], [[[pop objectValue] description] UTF8String], [states(pop) UTF8String]);
        draw(pop, "popup");

        /* a click opens the menu with the chosen item over the button; a
         * click on an item chooses it */
        NSPoint centre = mid([pop bounds]);
        click(w, pop, centre);
        NSView *ov = [w _overlayView];
        printf("open: %s, highlighted %ld\n", [NSStringFromClass([ov class]) UTF8String], (long)[ov highlightedIndex]);
        NSRect blue = [ov rectOfItemAtIndex:1], button = [pop convertRect:[pop bounds] toView:nil];
        rect("menu", [ov menuRect]);
        printf("chosen row's middle %.0f, the button's %.0f; rows %.0f high, the separator %.0f\n", NSMidY(blue),
               NSMidY(button), blue.size.height, [ov rectOfItemAtIndex:2].size.height);
        draw_window(w, "popup-open");
        click(w, ov, mid([ov rectOfItemAtIndex:0]));
        printf("after a click on Green: open %d, chosen %ld \"%s\", states %s\n", [w _overlayView] != nil,
               (long)[pop indexOfSelectedItem], [[pop title] UTF8String], [states(pop) UTF8String]);
        [log dump:"sent"];

        /* press, drag to an item and let go */
        down(w, pop, centre);
        ov = [w _overlayView];
        dragged(w, ov, mid([ov rectOfItemAtIndex:1]));
        printf("dragging: highlighted %ld", (long)[ov highlightedIndex]);
        dragged(w, ov, mid([ov rectOfItemAtIndex:2]));
        printf(", on the separator %ld\n", (long)[ov highlightedIndex]);
        dragged(w, ov, mid([ov rectOfItemAtIndex:3]));
        up(w, ov, mid([ov rectOfItemAtIndex:3]));
        printf("after a drag to Other: open %d, chosen \"%s\", tag %ld\n", [w _overlayView] != nil,
               [[pop titleOfSelectedItem] UTF8String], (long)[pop selectedTag]);
        [log dump:"sent"];

        /* a click outside closes it with nothing chosen */
        click(w, pop, centre);
        click(w, content, NSMakePoint(380, 20));
        printf("after a click outside: open %d, chosen \"%s\"\n", [w _overlayView] != nil,
               [[pop titleOfSelectedItem] UTF8String]);
        [log dump:"sent"];

        /* the keys: up and down skip the separator, Return chooses; Escape
         * closes; typing finds an item */
        click(w, pop, centre);
        ov = [w _overlayView];
        printf("open on Other: %ld", (long)[ov highlightedIndex]);
        key(w, NSUpArrowFunctionKey);
        printf(", up past the separator: %ld\n", (long)[ov highlightedIndex]);
        key(w, '\r');
        printf("after up, Return: \"%s\"\n", [[pop titleOfSelectedItem] UTF8String]);
        click(w, pop, centre);
        key(w, 27);
        printf("after Escape: open %d\n", [w _overlayView] != nil);
        click(w, pop, centre);
        ov = [w _overlayView];
        type(w, @"gr");
        printf("typed \"gr\": %ld\n", (long)[ov highlightedIndex]);
        key(w, ' ');
        printf("after Space: \"%s\"\n", [[pop titleOfSelectedItem] UTF8String]);
        [log dump:"sent"];

        /* a disabled item is passed over, and can't be chosen */
        [pop setAutoenablesItems:NO];
        [[pop itemAtIndex:1] setEnabled:NO];
        click(w, pop, centre);
        ov = [w _overlayView];
        key(w, NSDownArrowFunctionKey);
        printf("down from Green past disabled Blue: %ld\n", (long)[ov highlightedIndex]);
        click(w, ov, mid([ov rectOfItemAtIndex:1]));
        printf("click on disabled Blue: open %d, chosen \"%s\"\n", [w _overlayView] != nil,
               [[pop titleOfSelectedItem] UTF8String]);
        key(w, 27);
        [[pop itemAtIndex:1] setEnabled:YES];
        [log dump:"sent"];

        /* an item with an action of its own sends that, not the button's */
        [[pop itemAtIndex:0] setTarget:log];
        [[pop itemAtIndex:0] setAction:@selector(own:)];
        click(w, pop, centre);
        ov = [w _overlayView];
        click(w, ov, mid([ov rectOfItemAtIndex:0]));
        printf("chosen \"%s\"\n", [[pop titleOfSelectedItem] UTF8String]);
        [log dump:"sent"];

        /* full keyboard access: then it takes the focus, and Space opens it */
        printf("takes the focus: %d", [pop acceptsFirstResponder]);
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"AppleKeyboardUIMode" : @2}];
        printf(", with full keyboard access %d (%d)\n", [pop acceptsFirstResponder], [NSApp isFullKeyboardAccessEnabled]);
        [w makeFirstResponder:pop];
        key(w, ' ');
        ov = [w _overlayView];
        printf("Space opened it: %d, highlighted %ld\n", ov != nil, (long)[ov highlightedIndex]);
        key(w, NSDownArrowFunctionKey);
        key(w, '\r');
        printf("after down, Return: \"%s\"\n", [[pop titleOfSelectedItem] UTF8String]);
        [log dump:"sent"];

        /* ---- a pull-down list: the first item is the title ---- */
        NSPopUpButton *pull = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 200, 120, 25) pullsDown:YES];
        [pull addItemsWithTitles:@[ @"Actions", @"Copy", @"Paste" ]];
        [pull setTarget:log];
        [pull setAction:@selector(popped:)];
        [content addSubview:pull];
        printf("pull-down: title \"%s\", chosen %ld\n", [[pull title] UTF8String], (long)[pull indexOfSelectedItem]);
        click(w, pull, mid([pull bounds]));
        ov = [w _overlayView];
        NSRect bezel = [pull convertRect:[pull bounds] toView:nil];
        printf("open below it: %d, the title row shown %d, highlighted %ld\n", NSMaxY([ov menuRect]) <= NSMinY(bezel) + 3,
               [ov rectOfItemAtIndex:0].size.height > 0, (long)[ov highlightedIndex]);
        draw_window(w, "pulldown-open");
        click(w, ov, mid([ov rectOfItemAtIndex:2]));
        printf("after Paste: title \"%s\", chosen %ld, states %s\n", [[pull title] UTF8String],
               (long)[pull indexOfSelectedItem], [states(pull) UTF8String]);
        [log dump:"sent"];
        [pull removeFromSuperview];
        [pop removeFromSuperview];

        /* ---- segmented controls ---- */
        NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithLabels:@[ @"One", @"Two", @"Three" ]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:log action:@selector(segmented:)];
        [seg setFrame:NSMakeRect(20, 200, 180, 24)];
        for (NSInteger i = 0; i < 3; i++) {
            [seg setWidth:60 forSegment:i];
            [seg setTag:10 + i forSegment:i];
        }
        [content addSubview:seg];
        printf("segments: %ld, \"%s\" \"%s\" \"%s\", chosen %ld, width %.0f, intrinsic %.0fx%.0f, cell %s\n",
               (long)[seg segmentCount], [[seg labelForSegment:0] UTF8String], [[seg labelForSegment:1] UTF8String],
               [[seg labelForSegment:2] UTF8String], (long)[seg selectedSegment], [seg widthForSegment:1],
               [seg intrinsicContentSize].width, [seg intrinsicContentSize].height,
               [NSStringFromClass([[seg cell] class]) UTF8String]);
        click(w, seg, NSMakePoint(90, 12));
        click(w, seg, NSMakePoint(150, 12));
        printf("chosen %ld, selected %d%d%d\n", (long)[seg selectedSegment], [seg isSelectedForSegment:0],
               [seg isSelectedForSegment:1], [seg isSelectedForSegment:2]);
        [seg setEnabled:NO forSegment:0];
        click(w, seg, NSMakePoint(30, 12));
        printf("click on disabled 0: chosen %ld\n", (long)[seg selectedSegment]);
        [seg setEnabled:YES forSegment:0];
        down(w, seg, NSMakePoint(30, 12));
        dragged(w, seg, NSMakePoint(90, 12));
        up(w, seg, NSMakePoint(90, 12));
        printf("pressed on 0, let go on 1: chosen %ld\n", (long)[seg selectedSegment]);
        printf("select tag 11: %d, chosen %ld; tag 99: %d\n", [seg selectSegmentWithTag:11],
               (long)[seg selectedSegment], [seg selectSegmentWithTag:99]);
        draw(seg, "segmented");
        [log dump:"sent"];

        [seg setTrackingMode:NSSegmentSwitchTrackingSelectAny];
        click(w, seg, NSMakePoint(30, 12));
        click(w, seg, NSMakePoint(150, 12));
        click(w, seg, NSMakePoint(90, 12));
        printf("select any: selected %d%d%d\n", [seg isSelectedForSegment:0], [seg isSelectedForSegment:1],
               [seg isSelectedForSegment:2]);
        draw(seg, "segmented-any");
        [log dump:"sent"];
        [seg setTrackingMode:NSSegmentSwitchTrackingMomentary];
        click(w, seg, NSMakePoint(30, 12));
        printf("momentary: selected %d%d%d\n", [seg isSelectedForSegment:0], [seg isSelectedForSegment:1],
               [seg isSelectedForSegment:2]);
        [log dump:"sent"];

        /* the keys move the key segment and Space presses it */
        [seg setTrackingMode:NSSegmentSwitchTrackingSelectOne];
        [w makeFirstResponder:seg];
        printf("first responder: %d\n", [w firstResponder] == seg);
        key(w, NSRightArrowFunctionKey);
        key(w, NSRightArrowFunctionKey);
        key(w, ' ');
        key(w, NSLeftArrowFunctionKey);
        key(w, ' ');
        [log dump:"keys"];

        /* a segment with a menu opens it */
        NSMenu *more = [[NSMenu alloc] initWithTitle:@""];
        [more addItemWithTitle:@"Sort" action:@selector(segmentMenu:) keyEquivalent:@""];
        [more addItemWithTitle:@"Filter" action:@selector(segmentMenu:) keyEquivalent:@""];
        for (NSMenuItem *i in [more itemArray])
            [i setTarget:log];
        [seg setMenu:more forSegment:2];
        click(w, seg, NSMakePoint(150, 12));
        ov = [w _overlayView];
        printf("segment menu: open %d, below the segment %d\n", ov != nil,
               NSMaxY([ov menuRect]) <= NSMinY([seg convertRect:[seg bounds] toView:nil]) + 1);
        click(w, ov, mid([ov rectOfItemAtIndex:1]));
        printf("closed %d, chosen %ld\n", [w _overlayView] == nil, (long)[seg selectedSegment]);
        [log dump:"sent"];
        [seg removeFromSuperview];

        /* the distributions, with widths of their own */
        NSSegmentedControl *fit = [NSSegmentedControl segmentedControlWithLabels:@[ @"A", @"A longer label" ]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:log action:@selector(segmented:)];
        [fit setFrame:NSMakeRect(20, 200, 300, 24)];
        [content addSubview:fit];
        for (NSNumber *d in @[ @(NSSegmentDistributionFit), @(NSSegmentDistributionFill),
                               @(NSSegmentDistributionFillEqually), @(NSSegmentDistributionFillProportionally) ]) {
            [fit setSegmentDistribution:[d integerValue]];
            NSMutableString *hits = [NSMutableString string];
            for (CGFloat x = 10; x < 300; x += 40) {
                [fit setSelectedSegment:-1];
                click(w, fit, NSMakePoint(x, 12));
                [hits appendFormat:@"%ld ", (long)[fit selectedSegment]];
            }
            printf("distribution %ld: %s\n", (long)[d integerValue], [hits UTF8String]);
            draw(fit, [[NSString stringWithFormat:@"segmented-distribution-%ld", (long)[d integerValue]] UTF8String]);
        }
        printf("%lu actions\n", (unsigned long)[log.lines count]);
        [log.lines removeAllObjects];
        [fit removeFromSuperview];

        /* ---- search fields ---- */
        NSSearchField *sf = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, 200, 200, 22)];
        [sf setTarget:log];
        [sf setAction:@selector(searched:)];
        [sf setDelegate:log];
        [content addSubview:sf];
        printf("search field: cell %s, whole %d, immediately %d, recents %ld, intrinsic height %.0f\n",
               [NSStringFromClass([[sf cell] class]) UTF8String], [sf sendsWholeSearchString],
               [sf sendsSearchStringImmediately], (long)[sf maximumRecents], [sf intrinsicContentSize].height);
        rect("glass", [sf searchButtonBounds]);
        rect("text", [sf searchTextBounds]);
        rect("clear", [sf cancelButtonBounds]);
        draw(sf, "search-empty");
        [w makeFirstResponder:sf];
        type(w, @"ab");
        [log dump:"typed ab"];
        wait_for(0.4);
        [log dump:"a moment later"];
        type(w, @"c");
        type(w, @"d");
        wait_for(0.4);
        [log dump:"typed c, d, then waited"];
        draw(sf, "search-text");
        key(w, 27);
        printf("Escape: \"%s\"\n", [[sf stringValue] UTF8String]);
        [log dump:"sent"];
        [sf setSendsSearchStringImmediately:YES];
        type(w, @"xy");
        [log dump:"at once"];
        click(w, sf, mid([sf cancelButtonBounds]));
        printf("the clear button: \"%s\"\n", [[sf stringValue] UTF8String]);
        [log dump:"sent"];

        /* only on Return, kept as recent searches */
        [sf setSendsSearchStringImmediately:NO];
        [sf setSendsWholeSearchString:YES];
        [sf setMaximumRecents:2];
        [sf setRecentsAutosaveName:@"Finds"];
        [w makeFirstResponder:sf];
        for (NSString *s in @[ @"one", @"two", @"three" ]) {
            [sf selectText:nil];
            type(w, s);
            wait_for(0.3);
            key(w, '\r');
        }
        [log dump:"whole"];
        printf("recents: %s; saved: %s\n", [[[sf recentSearches] componentsJoinedByString:@", "] UTF8String],
               [[[[NSUserDefaults standardUserDefaults] objectForKey:@"Finds"] componentsJoinedByString:@", "]
                   UTF8String] ?: "nothing");

        /* the search menu, from a template */
        NSMenu *template = [[NSMenu alloc] initWithTitle:@""];
        NSArray *parts = @[ @[ @"Recent Searches", @1000 ], @[ @"recent", @1001 ], @[ @"Clear Recents", @1002 ],
                            @[ @"No Recent Searches", @1003 ] ];
        for (NSArray *p in parts)
            [[template addItemWithTitle:p[0] action:NULL keyEquivalent:@""] setTag:[p[1] integerValue]];
        [sf setSearchMenuTemplate:template];
        click(w, sf, mid([sf searchButtonBounds]));
        ov = [w _overlayView];
        printf("search menu: %s\n", [titles([[ov menu] itemArray]) UTF8String]);
        draw_window(w, "search-menu");
        click(w, ov, mid([ov rectOfItemAtIndex:2]));
        printf("chose a recent one: \"%s\"\n", [[sf stringValue] UTF8String]);
        [log dump:"sent"];
        click(w, sf, mid([sf searchButtonBounds]));
        ov = [w _overlayView];
        click(w, ov, mid([ov rectOfItemAtIndex:3]));
        click(w, sf, mid([sf searchButtonBounds]));
        ov = [w _overlayView];
        printf("after Clear Recents: %ld recents, menu %s\n", (long)[[sf recentSearches] count],
               [titles([[ov menu] itemArray]) UTF8String]);
        key(w, 27);
        [log dump:"sent"];
        [sf removeFromSuperview];
        [w makeFirstResponder:nil];

        /* ---- stack views ---- */
        NSStackView *row = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, 40)];
        printf("stack: orientation %ld, alignment %ld, spacing %.0f, distribution %ld, detaches hidden %d, flipped %d\n",
               (long)[row orientation], (long)[row alignment], [row spacing], (long)[row distribution],
               [row detachesHiddenViews], [row isFlipped]);
        Box *a1 = box(50, 20), *a2 = box(60, 30), *a3 = box(40, 10);
        [row addArrangedSubview:a1];
        [row addArrangedSubview:a2];
        [row addArrangedSubview:a3];
        frames("row", row);
        printf("fitting %.0fx%.0f\n", [row fittingSize].width, [row fittingSize].height);
        [row removeArrangedSubview:a3];
        [row addView:a3 inGravity:NSStackViewGravityTrailing];
        frames("one trailing", row);
        [row removeArrangedSubview:a2];
        [row addView:a2 inGravity:NSStackViewGravityCenter];
        frames("one in the middle", row);
        printf("in the gravities: %lu %lu %lu\n", (unsigned long)[[row viewsInGravity:NSStackViewGravityLeading] count],
               (unsigned long)[[row viewsInGravity:NSStackViewGravityCenter] count],
               (unsigned long)[[row viewsInGravity:NSStackViewGravityTrailing] count]);
        NSStackView *dist = [NSStackView stackViewWithViews:@[ box(50, 20), box(60, 30), box(40, 10) ]];
        [dist setFrame:NSMakeRect(0, 0, 300, 40)];
        [[dist views][1] setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
        for (NSNumber *d in @[ @(NSStackViewDistributionFill), @(NSStackViewDistributionFillEqually),
                               @(NSStackViewDistributionFillProportionally), @(NSStackViewDistributionEqualSpacing),
                               @(NSStackViewDistributionEqualCentering) ]) {
            [dist setDistribution:[d integerValue]];
            frames([[NSString stringWithFormat:@"distribution %ld", (long)[d integerValue]] UTF8String], dist);
        }
        [dist setDistribution:NSStackViewDistributionFill];
        for (NSNumber *al in @[ @(NSLayoutAttributeTop), @(NSLayoutAttributeBottom) ]) {
            [dist setAlignment:[al integerValue]];
            frames([[NSString stringWithFormat:@"alignment %ld", (long)[al integerValue]] UTF8String], dist);
        }
        [dist setEdgeInsets:NSEdgeInsetsMake(5, 10, 5, 10)];
        [dist setCustomSpacing:20 afterView:[dist views][0]];
        printf("custom spacing %.0f\n", [dist customSpacingAfterView:[dist views][0]]);
        frames("insets and spacing", dist);
        [[dist views][1] setHidden:YES];
        frames("one hidden", dist);
        [[dist views][1] setHidden:NO];
        frames("shown again", dist);
        [dist setDetachesHiddenViews:YES];
        [[dist views][1] setHidden:YES];
        frames("hidden, detached", dist);
        printf("detached %lu\n", (unsigned long)[[dist detachedViews] count]);
        [[dist views][1] setHidden:NO];
        frames("shown, attached", dist);
        draw(dist, "stack-row");

        /* a column, from the top down */
        NSStackView *col = [NSStackView stackViewWithViews:@[ box(80, 20), box(40, 30) ]];
        [col setOrientation:NSUserInterfaceLayoutOrientationVertical];
        [col setAlignment:NSLayoutAttributeLeading];
        [col setFrame:NSMakeRect(0, 0, 100, 120)];
        frames("column", col);
        [col setAlignment:NSLayoutAttributeCenterX];
        [col setDistribution:NSStackViewDistributionFillEqually];
        frames("column filled equally", col);

        /* too little room: the views that may go, go, least needed first */
        NSStackView *tight = [NSStackView stackViewWithViews:@[ box(60, 20), box(60, 20), box(60, 20) ]];
        [tight setDelegate:log];
        [tight setVisibilityPriority:NSStackViewVisibilityPriorityDetachOnlyIfNecessary forView:[tight views][1]];
        [tight setVisibilityPriority:800 forView:[tight views][2]];
        [tight setFrame:NSMakeRect(0, 0, 200, 30)];
        frames("200 wide", tight);
        [tight setFrameSize:NSMakeSize(130, 30)];
        frames("130 wide", tight);
        printf("detached %lu, arranged %lu\n", (unsigned long)[[tight detachedViews] count],
               (unsigned long)[[tight arrangedSubviews] count]);
        [tight setFrameSize:NSMakeSize(70, 30)];
        frames("70 wide", tight);
        [tight setFrameSize:NSMakeSize(300, 30)];
        frames("300 wide", tight);
        [log dump:"delegate"];

        /* stacks in a stack count at their fitting size */
        NSStackView *inner = [NSStackView stackViewWithViews:@[ box(30, 10), box(30, 20) ]];
        [inner setOrientation:NSUserInterfaceLayoutOrientationVertical];
        NSStackView *outer = [NSStackView stackViewWithViews:@[ inner, box(50, 50) ]];
        [outer setFrame:NSMakeRect(0, 0, 200, 60)];
        printf("inner fitting %.0fx%.0f\n", [inner fittingSize].width, [inner fittingSize].height);
        frames("outer", outer);
        frames("inner", inner);
        [[outer views][1] removeFromSuperview];
        printf("after a view left: %lu arranged\n", (unsigned long)[[outer arrangedSubviews] count]);

        /* ---- a toolbar ---- */
        NSWindow *tw = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 480, 200)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered defer:NO];
        [tw makeKeyAndOrderFront:nil];
        NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"Main"];
        [tb setDelegate:log];
        printf("toolbar: display mode %lu, size mode %lu, visible %d, customizable %d, autosaves %d\n",
               (unsigned long)[tb displayMode], (unsigned long)[tb sizeMode], [tb isVisible],
               [tb allowsUserCustomization], [tb autosavesConfiguration]);
        rect("frame before", [tw frame]);
        [tw setToolbar:tb];
        rect("frame with the toolbar", [tw frame]);
        rect("content", [[tw contentView] frame]);
        rect("strip", [[tw _toolbarView] frame]);
        rect("content rect", [tw contentRectForFrameRect:[tw frame]]);
        printf("items: %s; visible: %s\n", [titles([tb items]) UTF8String], [titles([tb visibleItems]) UTF8String]);
        [log dump:"delegate"];
        NSToolbarItem *find = [tb items][1];
        rect("find's view", [[find view] frame]);
        NSArray *bs = buttons_of(tw);
        for (NSView *b in bs)
            rect("button", [b frame]);
        log.refuseShare = YES;
        [tw update];
        printf("validated: share enabled %d, open enabled %d\n", [[tb items][3] isEnabled], [[tb items][0] isEnabled]);
        click(tw, bs[2], mid([bs[2] bounds]));
        click(tw, bs[0], mid([bs[0] bounds]));
        click(tw, bs[1], mid([bs[1] bounds]));
        printf("selected: %s\n", [[tb selectedItemIdentifier] UTF8String] ?: "none");
        [log dump:"clicks"];
        draw_window(tw, "toolbar");

        /* the modes: the strip's height changes and the frame with it */
        for (NSNumber *m in @[ @(NSToolbarDisplayModeIconAndLabel), @(NSToolbarDisplayModeLabelOnly),
                               @(NSToolbarDisplayModeIconOnly) ]) {
            [tb setDisplayMode:[m unsignedIntegerValue]];
            [tb visibleItems];
            printf("display mode %lu: strip %.0f, frame %.0f high at %.0f, content %.0f, buttons %.0f wide\n",
                   (unsigned long)[m unsignedIntegerValue], [[tw _toolbarView] frame].size.height,
                   [tw frame].size.height, [tw frame].origin.y, [[tw contentView] frame].size.height,
                   [buttons_of(tw)[0] frame].size.width);
            draw_window(tw, [[NSString stringWithFormat:@"toolbar-mode-%lu", (unsigned long)[m unsignedIntegerValue]]
                                UTF8String]);
        }
        [tb setSizeMode:NSToolbarSizeModeSmall];
        printf("small: strip %.0f\n", [[tw _toolbarView] frame].size.height);
        [tb setSizeMode:NSToolbarSizeModeRegular];
        [tw toggleToolbarShown:nil];
        printf("hidden: visible %d, frame %.0f high, content %.0f\n", [tb isVisible], [tw frame].size.height,
               [[tw contentView] frame].size.height);
        [tw toggleToolbarShown:nil];
        printf("shown: frame %.0f high\n", [tw frame].size.height);

        /* added and removed */
        [tb insertItemWithItemIdentifier:@"extra" atIndex:1];
        [tb insertItemWithItemIdentifier:NSToolbarSpaceItemIdentifier atIndex:0];
        [tb removeItemAtIndex:2];
        printf("items: %s\n", [titles([tb items]) UTF8String]);
        [log dump:"delegate"];
        printf("configuration: %s\n",
               [[[[tb configurationDictionary][@"TB Item Identifiers"] valueForKey:@"description"]
                   componentsJoinedByString:@", "] UTF8String]);

        /* narrower: the least wanted go to the chevron's menu */
        [tw setContentSize:NSMakeSize(210, 200)];
        printf("narrow: visible %s\n", [titles([tb visibleItems]) UTF8String]);
        NSView *strip = [tw _toolbarView];
        click(tw, strip, NSMakePoint([strip bounds].size.width - 19, [strip bounds].size.height / 2));
        ov = [tw _overlayView];
        printf("overflow menu: %s\n", [titles([[ov menu] itemArray]) UTF8String]);
        draw_window(tw, "toolbar-overflow");
        click(tw, ov, mid([ov rectOfItemAtIndex:[[ov menu] numberOfItems] - 1]));
        [log dump:"chosen"];
        [tw setContentSize:NSMakeSize(480, 200)];
        printf("wide again: visible %s\n", [titles([tb visibleItems]) UTF8String]);

        /* the configuration is saved, and a new toolbar of the same name takes it */
        [tb setAutosavesConfiguration:YES];
        [tb removeItemAtIndex:0];
        [tb setDisplayMode:NSToolbarDisplayModeLabelOnly];
        NSToolbar *again = [[NSToolbar alloc] initWithIdentifier:@"Main"];
        [again setAutosavesConfiguration:YES];
        [again setDelegate:log];
        printf("restored: %s, display mode %lu\n", [titles([again items]) UTF8String],
               (unsigned long)[again displayMode]);
        [log dump:"delegate"];
        [tw setToolbar:nil];
        printf("no toolbar: frame %.0f high, content %.0f\n", [tw frame].size.height,
               [[tw contentView] frame].size.height);

        /* ---- from a nib ---- */
        NSString *path = [NSString stringWithFormat:@"%s/Controls.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        ControlsOwner *owner = [[ControlsOwner alloc] init];
        NSArray *top = nil;
        printf("nib loaded: %d\n", [nib instantiateWithOwner:owner topLevelObjects:&top]);
        NSPopUpButton *np = owner.popup;
        printf("pop-up %s: %s, chosen %ld \"%s\", states %s, pulls down %d, target owner %d, action %s\n",
               [NSStringFromClass([np class]) UTF8String], [titles([np itemArray]) UTF8String],
               (long)[np indexOfSelectedItem], [[np title] UTF8String], [states(np) UTF8String], [np pullsDown],
               [np target] == owner, [NSStringFromSelector([np action]) UTF8String]);
        NSSegmentedControl *ns = owner.segments;
        printf("segments %s: %ld, \"%s\" \"%s\" \"%s\", chosen %ld, mode %lu\n",
               [NSStringFromClass([ns class]) UTF8String], (long)[ns segmentCount],
               [[ns labelForSegment:0] UTF8String], [[ns labelForSegment:1] UTF8String],
               [[ns labelForSegment:2] UTF8String], (long)[ns selectedSegment], (unsigned long)[ns trackingMode]);
        NSSearchField *nf = owner.search;
        printf("search %s: placeholder \"%s\", whole %d, recents %ld\n", [NSStringFromClass([nf class]) UTF8String],
               [[nf placeholderString] UTF8String], [nf sendsWholeSearchString], (long)[nf maximumRecents]);
        NSStackView *nv = owner.stack;
        printf("stack %s: orientation %ld, alignment %ld, spacing %.0f, %lu arranged\n",
               [NSStringFromClass([nv class]) UTF8String], (long)[nv orientation], (long)[nv alignment],
               [nv spacing], (unsigned long)[[nv arrangedSubviews] count]);
        frames("nib stack", nv);
        NSWindow *nw = owner.window;
        NSToolbar *nt = owner.toolbar;
        printf("toolbar %s \"%s\": the window's %d, delegate owner %d, display mode %lu, size mode %lu, items %s\n",
               [NSStringFromClass([nt class]) UTF8String], [[nt identifier] UTF8String], [nw toolbar] == nt,
               [nt delegate] == (id)owner, (unsigned long)[nt displayMode], (unsigned long)[nt sizeMode],
               [titles([nt items]) UTF8String]);
        NSToolbarItem *open = [nt items][0];
        printf("open item: label \"%s\", target owner %d, action %s, tag %ld\n", [[open label] UTF8String],
               [open target] == owner, [NSStringFromSelector([open action]) UTF8String], (long)[open tag]);
        rect("nib window", [nw frame]);
        rect("nib content", [[nw contentView] frame]);
        [nw makeKeyAndOrderFront:nil];
        click(nw, np, mid([np bounds]));
        ov = [nw _overlayView];
        click(nw, ov, mid([ov rectOfItemAtIndex:2]));
        [nt visibleItems];
        NSArray *nb = buttons_of(nw);
        click(nw, nb[0], mid([nb[0] bounds]));
        printf("owner: %s\n", [[owner.lines componentsJoinedByString:@"; "] UTF8String]);
        draw_window(nw, "nib");
    }
    return 0;
}
