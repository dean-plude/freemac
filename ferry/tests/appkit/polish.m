/* SPDX-License-Identifier: GPL-3.0-or-later
 * What the seven apps' windows needed in freemac's polish round, each in a
 * small program of Ferry's own, with no display: a window that grows or
 * shrinks to its content's required constraints keeping its top left
 * corner, a stack view's size along its axis from its views' fitting
 * sizes and across it from the widest, a field stretched across it, an
 * image view in one held to its own size constraints (MacPass's welcome,
 * freemac 1.236), a split view's panes kept where
 * the split view put them whatever their own constraints say, a split view
 * controller's split view pinned to its view and a pane kept to its minimum
 * thickness, the buttons a Mac draws its own way (a source list's badge, a
 * help button, a toolbar button made in code with only an image), a field
 * told it has no border, a toolbar item's view's image and size, and a
 * window's -update sent once after each event rather than on every turn of
 * the loop, whose background may be a pattern image, and an icon with only
 * a JPEG 2000 picture. Ferry's own test,
 * written from Apple's public documentation. */
#import <Cocoa/Cocoa.h>

@interface NSWindow (FerryPicture)
- (NSBitmapImageRep *)_pictureWithTitleBar:(BOOL)titleBar;
@end

static void show(const char *what, NSRect f)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, f.origin.x, f.origin.y, f.size.width, f.size.height);
}

static void turn(double seconds)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:end inMode:NSDefaultRunLoopMode
                                          dequeue:YES];
        if (e)
            [NSApp sendEvent:e];
    }
}

static NSView *pinned_at(NSView *parent, CGFloat w, CGFloat h, NSLayoutPriority sizes)
{
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:v];
    NSLayoutConstraint *cw = [v.widthAnchor constraintEqualToConstant:w], *ch = [v.heightAnchor constraintEqualToConstant:h];
    cw.priority = ch.priority = sizes;
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:10],
        [v.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-10],
        [v.topAnchor constraintEqualToAnchor:parent.topAnchor constant:10],
        [v.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-10], cw, ch,
    ]];
    return v;
}
static NSView *pinned(NSView *parent, CGFloat w, CGFloat h) { return pinned_at(parent, w, h, NSLayoutPriorityRequired); }

/* a window as KeyCastr's Sparkle prompt and Spectacle's are: its content's
 * required sizes beat the size it was made at, and it keeps its top left */
static void window_sizes(void)
{
    for (int resizable = 0; resizable < 2; resizable++) {
        NSWindowStyleMask style = NSWindowStyleMaskTitled | (resizable ? NSWindowStyleMaskResizable : 0);
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 500) styleMask:style
                                                    backing:NSBackingStoreBuffered defer:NO];
        w.releasedWhenClosed = NO;
        NSView *v = pinned(w.contentView, 300, 200);
        CGFloat top = NSMaxY(w.frame);
        [w layoutIfNeeded];
        printf("%s window:\n", resizable ? "a resizable" : "a fixed");
        show("  content shrunk to fit", [w contentRectForFrameRect:w.frame]);
        printf("  top left kept: %s\n", NSMaxY(w.frame) == top && w.frame.origin.x == 100 ? "yes" : "no");
        show("  view", v.frame);
        for (NSLayoutConstraint *c in v.constraints)
            if (c.firstAttribute == NSLayoutAttributeHeight)
                c.constant = 300;
        [w layoutIfNeeded];
        show("  content grown to fit", [w contentRectForFrameRect:w.frame]);
        printf("  top left kept: %s\n", NSMaxY(w.frame) == top ? "yes" : "no");
        [w close];
    }
    /* a weaker want of the content's gives way to the window's size */
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSView *v = pinned_at(w.contentView, 100, 100, NSLayoutPriorityDefaultLow);
    [w layoutIfNeeded];
    show("a window whose content only prefers a size", [w contentRectForFrameRect:w.frame]);
    show("  view", v.frame);
    [w close];
}

@interface Sized : NSView
@property NSSize natural;
@end
@implementation Sized
- (NSSize)intrinsicContentSize { return self.natural; }
@end

/* stack views, as Sparkle's prompt and MacPass's inspector use them */
static void stacks(void)
{
    /* a stack's height is its views' fitting heights and the spacing between them */
    NSView *laid = [[NSView alloc] initWithFrame:NSZeroRect];
    laid.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *inner = pinned(laid, 120, 40);
    (void)inner;
    Sized *label = [[Sized alloc] initWithFrame:NSZeroRect];
    label.natural = NSMakeSize(80, 17);
    NSStackView *stack = [NSStackView stackViewWithViews:@[ label, laid ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    show("a vertical stack's natural size", (NSRect){NSZeroPoint, stack.intrinsicContentSize});
    show("  its fitting size", (NSRect){NSZeroPoint, stack.fittingSize});
    printf("  hugs vertically at %.0f\n", [stack contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical]);

    /* a field with no width of its own, hugging less than the stack, is stretched across it */
    NSTextField *field = [NSTextField textFieldWithString:@""];
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    Sized *fixed = [[Sized alloc] initWithFrame:NSZeroRect];
    fixed.natural = NSMakeSize(60, 20);
    [fixed setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *column = [NSStackView stackViewWithViews:@[ field, fixed ]];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    [column setFrame:NSMakeRect(0, 0, 300, 100)];
    [column layoutSubtreeIfNeeded];
    show("  a field across a 300-wide stack", field.frame);
    show("  a view that hugs its width", fixed.frame);

    /* MacPass's welcome: an image view held at 128 by 128 by its own
     * constraints shows a 512-point picture; above a title wider than the
     * stack was made, which the stack grows to hold */
    Sized *icon = [[Sized alloc] initWithFrame:NSZeroRect];
    icon.natural = NSMakeSize(512, 512);
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:128], [icon.heightAnchor constraintEqualToConstant:128],
    ]];
    Sized *title = [[Sized alloc] initWithFrame:NSZeroRect];
    title.natural = NSMakeSize(240, 29);
    NSStackView *welcome = [NSStackView stackViewWithViews:@[ icon, title ]];
    welcome.orientation = NSUserInterfaceLayoutOrientationVertical;
    welcome.spacing = 8;
    show("a stack holding a held image view, natural size", (NSRect){NSZeroPoint, welcome.intrinsicContentSize});
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    [welcome setFrame:NSMakeRect(90, 40, 222, 222)];
    welcome.translatesAutoresizingMaskIntoConstraints = NO;
    [w.contentView addSubview:welcome];
    [NSLayoutConstraint activateConstraints:@[
        [welcome.centerXAnchor constraintEqualToAnchor:[w.contentView centerXAnchor]],
        [welcome.centerYAnchor constraintEqualToAnchor:[w.contentView centerYAnchor]],
    ]];
    [w layoutIfNeeded];
    show("  in a window, the stack", welcome.frame);
    show("  the image view", icon.frame);
    show("  the title", title.frame);
    [w close];
}

/* MacPass's document window: a split view's panes keep the frames the
 * split view gives them, whatever their content's constraints prefer */
@interface Pane : NSViewController
@property CGFloat natural;
@end
@implementation Pane
- (void)loadView
{
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    Sized *label = [[Sized alloc] initWithFrame:NSZeroRect];
    label.natural = NSMakeSize(self.natural, 17);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:label];
    /* a label that hugs, pinned on both sides: a Mac keeps the pane's width */
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-8],
        [label.topAnchor constraintEqualToAnchor:v.topAnchor constant:8],
    ]];
    self.view = v;
}
@end

@interface Split : NSSplitViewController
@end
@implementation Split
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)]; }
@end

static void splits(void)
{
    Split *c = [[Split alloc] init];
    CGFloat widths[3] = {40, 60, 30}, mins[3] = {150, 150, 200};
    for (int i = 0; i < 3; i++) {
        Pane *p = [[Pane alloc] init];
        p.natural = widths[i];
        NSSplitViewItem *item = [NSSplitViewItem splitViewItemWithViewController:p];
        item.minimumThickness = mins[i];
        [c addSplitViewItem:item];
    }
    NSWindow *w = [NSWindow windowWithContentViewController:c];
    w.releasedWhenClosed = NO;
    [w setContentSize:NSMakeSize(700, 400)];
    [w layoutIfNeeded];
    printf("a split view controller's view holding its split view:\n");
    printf("  split view pinned: %s, ", c.splitView.translatesAutoresizingMaskIntoConstraints ? "no" : "yes");
    show("frame", c.splitView.frame);
    printf("  panes:");
    for (NSSplitViewItem *item in c.splitViewItems)
        printf(" %.0f+%.0f", item.viewController.view.frame.origin.x, item.viewController.view.frame.size.width);
    printf("\n");
    BOOL atLeast = YES;
    for (int i = 0; i < 3; i++)
        if (c.splitViewItems[i].viewController.view.frame.size.width < mins[i])
            atLeast = NO;
    printf("  each pane at least its minimum thickness: %s\n", atLeast ? "yes" : "no");
    [w setContentSize:NSMakeSize(540, 400)];
    [w layoutIfNeeded];
    printf("  narrow:");
    for (NSSplitViewItem *item in c.splitViewItems)
        printf(" %.0f+%.0f", item.viewController.view.frame.origin.x, item.viewController.view.frame.size.width);
    printf("\n");
    [w setContentSize:NSMakeSize(900, 400)];
    [w layoutIfNeeded];
    printf("  wider:");
    for (NSSplitViewItem *item in c.splitViewItems)
        printf(" %.0f+%.0f", item.viewController.view.frame.origin.x, item.viewController.view.frame.size.width);
    printf("\n");
    [w close];
}

/* buttons a Mac draws its own way, and fields */
static void buttons(void)
{
    NSButton *badge = [NSButton buttonWithTitle:@"12" target:nil action:NULL];
    badge.bezelStyle = NSBezelStyleInline;
    show("an inline badge's natural size", (NSRect){NSZeroPoint, badge.intrinsicContentSize});
    NSButton *help = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 25, 25)];
    help.bezelStyle = NSBezelStyleHelpButton;
    help.title = @"";
    show("a help button's natural size", (NSRect){NSZeroPoint, help.intrinsicContentSize});

    NSImage *image = [NSImage imageWithSize:NSMakeSize(19, 19) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] set];
        NSRectFill(NSInsetRect(r, 4, 4));
        return YES;
    }];
    NSButton *tool = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 37, 27)];
    tool.image = image;
    printf("a button made in code and given an image: title \"%s\", %s\n", tool.title.UTF8String,
           tool.imagePosition == NSImageOnly ? "image only" : "image and title");
    NSButton *titled = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 27)];
    titled.title = @"Open";
    titled.image = image;
    printf("one given a title too: %s\n", titled.imagePosition == NSImageLeft ? "image left of the title" : "other");

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
    printf("a field made in code: bezeled %d, bordered %d\n", field.bezeled, field.bordered);
    field.bordered = NO;
    printf("  told it has no border: bezeled %d, bordered %d\n", field.bezeled, field.bordered);
    field.bordered = YES;
    printf("  given a border: bezeled %d, bordered %d\n", field.bezeled, field.bordered);
    field.bezeled = YES;
    printf("  given a bezel: bezeled %d, bordered %d\n", field.bezeled, field.bordered);
}

/* a toolbar's items as MacDown's controller makes them */
@interface ToolbarMaker : NSObject <NSToolbarDelegate>
@property NSImage *image;
@end
@implementation ToolbarMaker
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return @[ @"bold", @"group" ]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return @[ @"bold", @"group" ]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)f
{
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 37, 27)];
    b.image = self.image;
    b.bezelStyle = NSBezelStyleTexturedRounded;
    if ([ident isEqualToString:@"bold"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
        item.view = b;
        return item;
    }
    NSToolbarItemGroup *group = [[NSToolbarItemGroup alloc] initWithItemIdentifier:ident];
    NSToolbarItem *sub = [[NSToolbarItem alloc] initWithItemIdentifier:@"sub"];
    sub.view = b;
    group.subitems = @[ sub ];
    NSSegmentedControl *seg = [[NSSegmentedControl alloc] init];
    seg.segmentCount = 1;
    [seg setImage:sub.image forSegment:0];
    [seg setWidth:33 forSegment:0];
    group.view = seg;
    group.maxSize = NSMakeSize(37, 25);
    return group;
}
@end

static void toolbars(void)
{
    ToolbarMaker *maker = [[ToolbarMaker alloc] init];
    maker.image = [NSImage imageWithSize:NSMakeSize(19, 19) flipped:NO drawingHandler:^BOOL(NSRect r) { return YES; }];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 200)
                                              styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.releasedWhenClosed = NO;
    NSToolbar *t = [[NSToolbar alloc] initWithIdentifier:@"polish"];
    t.delegate = maker;
    t.displayMode = NSToolbarDisplayModeIconOnly;
    w.toolbar = t;
    [w orderFront:nil];
    turn(0.05);
    for (NSToolbarItem *item in t.items) {
        printf("toolbar item %s: image %s, view %s, ", item.itemIdentifier.UTF8String,
               item.image == maker.image ? "its view's" : item.image ? "other" : "none",
               item.view.className.UTF8String);
        show("view", item.view.frame);
    }
    NSSegmentedControl *seg = (NSSegmentedControl *)[t.items[1] view];
    printf("  the group's segment shows its subitem's image: %s\n", [seg imageForSegment:0] == maker.image ? "yes" : "no");
    [w close];
}

/* a window as Flycut's bezel is: -update sets its background, a pattern
 * of a rounded rectangle, which marks it for display */
@interface Bezel : NSWindow
@property int updates;
@end
@implementation Bezel
- (NSColor *)backgroundColor
{
    NSImage *bg = [[NSImage alloc] initWithSize:self.frame.size];
    [bg lockFocus];
    [[NSColor colorWithCalibratedWhite:0.1 alpha:0.6] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, bg.size.width, bg.size.height) xRadius:25
                                     yRadius:25] fill];
    [bg unlockFocus];
    return [NSColor colorWithPatternImage:bg];
}
- (void)update
{
    [super update];
    self.updates++;
    [self setBackgroundColor:[self backgroundColor]];
}
@end

static void updates(void)
{
    Bezel *w = [[Bezel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskBorderless
                                          backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.opaque = NO;
    [w orderFront:nil];
    turn(0.3);
    int shown = w.updates;
    printf("a window whose -update marks it for display, updated once it is shown: %s\n",
           shown >= 1 && shown <= 2 ? "yes" : "no");
    turn(0.3);
    printf("  and not again with no event: %s\n", w.updates == shown ? "yes" : "no");
    NSEvent *e = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                   timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    [NSApp postEvent:e atStart:NO];
    turn(0.2);
    printf("  updated once after an event: %s\n", w.updates == shown + 1 ? "yes" : "no");
    [NSApp setWindowsNeedUpdate:YES];
    turn(0.1);
    printf("  and once when the app says its windows need it: %s\n", w.updates == shown + 2 ? "yes" : "no");

    NSBitmapImageRep *rep = [w _pictureWithTitleBar:NO];
    NSColor *corner = [rep colorAtX:1 y:1], *middle = [rep colorAtX:100 y:50];
    printf("  its pattern background: corner alpha %.2f, middle alpha %.2f white %.2f\n", corner.alphaComponent,
           middle.alphaComponent, [[middle colorUsingColorSpace:[NSColorSpace genericGrayColorSpace]] whiteComponent]);
    [w close];
}

/* a nib ferry-ibtool compiled from polish.xib: a toolbar with its items,
 * its delegate and an item's action, constraints and hugging priorities,
 * and progress indicators shown or hidden while stopped */
@interface PolishOwner : NSObject <NSToolbarDelegate>
@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSToolbar *toolbar;
@property (strong) IBOutlet NSTextField *label;
@property (strong) IBOutlet NSProgressIndicator *spinner, *bar;
@end
@implementation PolishOwner
- (void)toolbarWillAddItem:(NSNotification *)n
{
    printf("  the delegate hears of %s\n", [[n.userInfo[@"item"] itemIdentifier] UTF8String]);
}
- (IBAction)refresh:(id)sender { printf("  refresh: from %s\n", [sender className].UTF8String); }
@end

static void nib(void)
{
    const char *data = getenv("FERRY_TEST_DATA");
    if (!data)
        return;
    NSString *path = [NSString stringWithFormat:@"%s/Polish.nib", data];
    NSNib *n = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
    PolishOwner *owner = [[PolishOwner alloc] init];
    NSArray *top = nil;
    printf("the nib: instantiated %s\n", [n instantiateWithOwner:owner topLevelObjects:&top] ? "yes" : "no");
    NSToolbar *t = owner.toolbar;
    printf("  toolbar: %s, the window's %s, delegate %s, display mode %ld, size mode %ld, customizable %d\n",
           t ? "yes" : "no", owner.window.toolbar == t ? "yes" : "no", t.delegate == owner ? "the owner" : "other",
           (long)t.displayMode, (long)t.sizeMode, t.allowsUserCustomization);
    for (NSToolbarItem *item in t.items) {
        printf("  item %s: label \"%s\" palette \"%s\" tip \"%s\" tag %ld view %s",
               item.itemIdentifier.UTF8String, item.label.UTF8String, item.paletteLabel.UTF8String,
               item.toolTip.UTF8String ?: "", (long)item.tag, item.view ? item.view.className.UTF8String : "none");
        if (item.view)
            printf(" min %.0fx%.0f max %.0fx%.0f", item.minSize.width, item.minSize.height, item.maxSize.width,
                   item.maxSize.height);
        printf("\n");
    }
    NSToolbarItem *refresh = t.items.firstObject;
    [NSApp sendAction:refresh.action to:refresh.target from:refresh];
    NSTextField *label = owner.label;
    printf("  label: translates its mask %d, hugs %.0f,%.0f, resists %.0f,%.0f, %lu constraints in the window\n",
           label.translatesAutoresizingMaskIntoConstraints,
           [label contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal],
           [label contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical],
           [label contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal],
           [label contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical],
           (unsigned long)owner.window.contentView.constraints.count);
    [owner.window layoutIfNeeded];
    show("  the window's content, grown to the content view's height",
         [owner.window contentRectForFrameRect:owner.window.frame]);
    NSRect lf = label.frame;
    printf("  label from the top left: %.0f,%.0f\n", lf.origin.x,
           owner.window.contentView.frame.size.height - NSMaxY(lf));
    printf("  spinner shown while stopped: %d, bar: %d\n", owner.spinner.displayedWhenStopped,
           owner.bar.displayedWhenStopped);
    [owner.window close];
}

/* an .icns file with only a JPEG 2000 picture, as both of KeyCastr's are:
 * Ferry's own, 1024 across in four quarters (red, blue, half-transparent
 * green and clear), read at 512 */
static void icons(void)
{
    const char *data = getenv("FERRY_TEST_DATA");
    if (!data)
        return;
    NSString *path = [NSString stringWithFormat:@"%s/polish-j2k.icns", data];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    NSBitmapImageRep *rep = nil;
    for (NSImageRep *r in image.representations)
        if ([r isKindOfClass:[NSBitmapImageRep class]])
            rep = (NSBitmapImageRep *)r;
    printf("a JPEG 2000 icon: %s, %ldx%ld pixels\n", rep ? "read" : "not read", (long)rep.pixelsWide,
           (long)rep.pixelsHigh);
    if (!rep)
        return;
    NSInteger w = rep.pixelsWide, h = rep.pixelsHigh;
    NSPoint at[] = {{w / 4, h / 4}, {3 * w / 4, h / 4}, {w / 4, 3 * h / 4}, {3 * w / 4, 3 * h / 4}};
    for (int i = 0; i < 4; i++) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [[rep colorAtX:(NSInteger)at[i].x y:(NSInteger)at[i].y] getRed:&r green:&g blue:&b alpha:&a];
        printf("  at %.0f,%.0f from the top left: %.0f %.0f %.0f alpha %.0f\n", at[i].x, at[i].y, r * 255, g * 255,
               b * 255, a * 255);
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        window_sizes();
        stacks();
        splits();
        buttons();
        toolbars();
        updates();
        nib();
        icons();
    }
    return 0;
}
