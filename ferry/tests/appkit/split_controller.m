/* SPDX-License-Identifier: GPL-3.0-or-later
 * Split view controllers, with no display: one with no nib, whose view is
 * its split view (side by side, thin dividers); and one laid out the way
 * MacPass's document window is, its view a plain view (as MacPass's nib
 * gives it) holding the split view, with a sidebar, a content pane and a
 * collapsed inspector added in viewDidLoad. The panes' frames, holding
 * priorities when the window grows, the items' thickness limits when a
 * divider is dragged, collapsing by code, by toggleSidebar: and
 * toggleInspector: and by dragging (observed on the item), menu
 * validation, child view controllers added and removed the general way,
 * the errors a Mac documents, and (1.229) an inspector whose content's
 * constraints need more than its item's minimum, which opens that wide. */
#import <Cocoa/Cocoa.h>

static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
}

@interface Pane : NSViewController
@end
@implementation Pane
- (void)loadView { [self setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)]]; }
@end

/* As MacPass's MPDocumentSplitViewController: a nib's plain view, and the
 * items made in viewDidLoad after super's. */
@interface DocumentSplit : NSSplitViewController
@property (strong) Pane *outline, *entries, *inspector;
@property BOOL opensInspector;
@end
@implementation DocumentSplit
- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle
{
    if ((self = [super initWithNibName:name bundle:bundle])) {
        _outline = [[Pane alloc] init];
        _entries = [[Pane alloc] init];
        _inspector = [[Pane alloc] init];
    }
    return self;
}
- (void)loadView { [self setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 272)]]; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.splitView.translatesAutoresizingMaskIntoConstraints = NO;
    NSSplitViewItem *outline = [NSSplitViewItem sidebarWithViewController:self.outline];
    outline.holdingPriority = NSLayoutPriorityDefaultLow + 2;
    outline.canCollapse = NO;
    outline.minimumThickness = 150;
    NSSplitViewItem *entries = [NSSplitViewItem splitViewItemWithViewController:self.entries];
    entries.canCollapse = NO;
    entries.minimumThickness = 150;
    NSSplitViewItem *inspector = [NSSplitViewItem splitViewItemWithViewController:self.inspector];
    inspector.canCollapse = YES;
    inspector.minimumThickness = 120;
    inspector.holdingPriority = NSLayoutPriorityDefaultLow + 1;
    [self addSplitViewItem:outline];
    [self addSplitViewItem:entries];
    [self addSplitViewItem:inspector];
    inspector.collapsed = !self.opensInspector;
}
@end

/* As MacPass's inspector nib: a view 278 wide, its content in a scroll view
 * whose constraints ask for no width. */
@interface WidePane : Pane
@end
@implementation WidePane
- (void)loadView { [self setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 278, 100)]]; }
@end

/* As MacPass's inspector: a field held 20 points in from each side and at
 * least 220 wide, so the pane needs 260. */
@interface FittedPane : Pane
@end
@implementation FittedPane
- (void)loadView
{
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    NSTextField *field = [NSTextField textFieldWithString:@"a password"];
    [field setTranslatesAutoresizingMaskIntoConstraints:NO];
    [v addSubview:field];
    [[field.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:20] setActive:YES];
    [[field.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-20] setActive:YES];
    [[field.topAnchor constraintEqualToAnchor:v.topAnchor constant:10] setActive:YES];
    [[field.widthAnchor constraintGreaterThanOrEqualToConstant:220] setActive:YES];
    [self setView:v];
}
@end

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)o change:(NSDictionary *)change context:(void *)ctx
{
    printf("observed %s: %s\n", [path UTF8String], [[change[NSKeyValueChangeNewKey] description] UTF8String]);
}
@end

static void panes(const char *what, DocumentSplit *c)
{
    printf("%s:", what);
    for (NSSplitViewItem *item in [c splitViewItems]) {
        NSView *v = [[item viewController] view];
        printf(" %.0f+%.0f%s", [v frame].origin.x, [v frame].size.width, [item isCollapsed] ? " (collapsed)" : "");
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* ---- no nib: the view is the split view ---- */
        NSSplitViewController *plain = [[NSSplitViewController alloc] init];
        NSSplitView *sv = [plain splitView];
        printf("plain: vertical %d, thin %d, items %lu\n", [sv isVertical],
               [sv dividerStyle] == NSSplitViewDividerStyleThin, (unsigned long)[[plain splitViewItems] count]);
        printf("plain: view is the split view %d, its delegate is the controller %d\n", [plain view] == sv,
               [sv delegate] == (id)plain);
        Pane *one = [[Pane alloc] init], *two = [[Pane alloc] init];
        [plain addChildViewController:one];
        [plain addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:two]];
        printf("plain: a child added the general way has an item %d; items %lu, children %lu, panes %lu\n",
               [plain splitViewItemForViewController:one] != nil, (unsigned long)[[plain splitViewItems] count],
               (unsigned long)[[plain childViewControllers] count], (unsigned long)[[sv subviews] count]);
        [plain removeChildViewControllerAtIndex:0];
        printf("plain: removed the first child: items %lu, panes %lu, the other left %d\n",
               (unsigned long)[[plain splitViewItems] count], (unsigned long)[[sv subviews] count],
               [[[[plain splitViewItems] firstObject] viewController] isEqual:two]);
        NSSplitViewItem *defaults = [NSSplitViewItem splitViewItemWithViewController:one];
        NSSplitViewItem *sidebar = [NSSplitViewItem sidebarWithViewController:[[Pane alloc] init]];
        printf("an item: behavior %ld, can collapse %d, holding %.0f, minimum %.0f, maximum %.0f\n",
               (long)[defaults behavior], [defaults canCollapse], [defaults holdingPriority],
               [defaults minimumThickness], [defaults maximumThickness]);
        printf("a sidebar: behavior %ld, can collapse %d, spring loaded %d, fraction %.2f\n", (long)[sidebar behavior],
               [sidebar canCollapse], [sidebar isSpringLoaded], [sidebar preferredThicknessFraction]);
        printf("an inspector: behavior %ld, a content list: behavior %ld\n",
               (long)[[NSSplitViewItem inspectorWithViewController:one] behavior],
               (long)[[NSSplitViewItem contentListWithViewController:one] behavior]);
        @try {
            [plain setSplitView:[[NSSplitView alloc] init]];
            printf("a new split view after loading: no exception\n");
        } @catch (NSException *e) {
            printf("a new split view after loading: %s\n", [[e name] UTF8String]);
        }
        @try {
            [plain addSplitViewItem:[[NSSplitViewItem alloc] init]];
            printf("an item with no view controller: no exception\n");
        } @catch (NSException *e) {
            printf("an item with no view controller: %s\n", [[e name] UTF8String]);
        }

        /* ---- MacPass's document window ---- */
        DocumentSplit *doc = [[DocumentSplit alloc] init];
        NSWindow *w = [NSWindow windowWithContentViewController:doc];
        NSSplitView *dsv = [doc splitView];
        printf("document: the split view is in the view %d, fills it %d, vertical %d\n",
               [dsv superview] == [doc view], NSEqualRects([dsv frame], [[doc view] bounds]), [dsv isVertical]);
        printf("document: items %lu, children %lu, the window's content %s\n",
               (unsigned long)[[doc splitViewItems] count], (unsigned long)[[doc childViewControllers] count],
               [w contentViewController] == doc ? "is the controller" : "isn't");
        printf("document: item for the inspector found %d\n",
               [doc splitViewItemForViewController:doc.inspector] == [[doc splitViewItems] lastObject]);
        panes("document, inspector collapsed", doc);
        printf("holding: %.0f %.0f %.0f\n", [dsv holdingPriorityForSubviewAtIndex:0],
               [dsv holdingPriorityForSubviewAtIndex:1], [dsv holdingPriorityForSubviewAtIndex:2]);
        NSSplitViewItem *inspector = [doc splitViewItemForViewController:doc.inspector];
        Watcher *watcher = [[Watcher alloc] init];
        [inspector addObserver:watcher forKeyPath:@"collapsed" options:NSKeyValueObservingOptionNew context:NULL];
        [doc toggleInspector:nil];
        panes("toggleInspector: with no item of the inspector's behavior, nothing changes", doc);
        [inspector setCollapsed:NO];
        panes("opened by code: the content pane gives up the room", doc);
        [w setContentSize:NSMakeSize(680, 272)];
        panes("window wider: the content pane grows", doc);
        [w setContentSize:NSMakeSize(580, 272)];
        panes("narrower again", doc);

        /* dragging the dividers: held to the items' limits */
        CGFloat at = [dsv positionOfDividerAtIndex:0];
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, dsv, NSMakePoint(at, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, dsv, NSMakePoint(40, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, dsv, NSMakePoint(40, 50))];
        panes("sidebar dragged narrow: held at its minimum", doc);
        at = [dsv positionOfDividerAtIndex:0];
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, dsv, NSMakePoint(at, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, dsv, NSMakePoint(560, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, dsv, NSMakePoint(560, 50))];
        panes("sidebar dragged wide: held at the content pane's minimum", doc);
        [w setContentSize:NSMakeSize(780, 272)];
        at = [dsv positionOfDividerAtIndex:0];
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, dsv, NSMakePoint(at, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, dsv, NSMakePoint(560, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, dsv, NSMakePoint(560, 50))];
        panes("in a wider window, held at its own maximum", doc);
        [w setContentSize:NSMakeSize(580, 272)];
        panes("narrower: the content pane gives way to its minimum, then the sidebar", doc);
        at = [dsv positionOfDividerAtIndex:1];
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, dsv, NSMakePoint(at, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, dsv, NSMakePoint(575, 50))];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, dsv, NSMakePoint(575, 50))];
        panes("inspector dragged past halfway: it collapses", doc);
        [inspector setCollapsed:NO];
        panes("opened again by code, as thick as it was", doc);
        [inspector removeObserver:watcher forKeyPath:@"collapsed"];

        /* the sidebar, toggled and validated */
        NSSplitViewItem *outline = [[doc splitViewItems] firstObject];
        [doc toggleSidebar:nil];
        panes("toggleSidebar:", doc);
        NSMenuItem *menu = [[NSMenuItem alloc] initWithTitle:@"Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@""];
        printf("toggleSidebar: enabled %d, titled %s\n", [doc validateUserInterfaceItem:menu], [[menu title] UTF8String]);
        [doc toggleSidebar:nil];
        printf("toggled back: collapsed %d, enabled %d, titled %s\n", [outline isCollapsed],
               [doc validateUserInterfaceItem:menu], [[menu title] UTF8String]);
        printf("toggleSidebar: in the plain controller, with no sidebar, enabled %d\n",
               [plain validateUserInterfaceItem:menu]);

        /* removing an item takes its pane and child away */
        [doc removeSplitViewItem:inspector];
        printf("inspector removed: items %lu, children %lu, panes %lu\n", (unsigned long)[[doc splitViewItems] count],
               (unsigned long)[[doc childViewControllers] count], (unsigned long)[[dsv subviews] count]);
        panes("two panes share the room", doc);
        [doc insertSplitViewItem:inspector atIndex:0];
        printf("put back first: the first pane is the inspector's %d\n",
               [[dsv subviews] firstObject] == [doc.inspector view]);
        @try {
            [inspector setViewController:doc.entries];
            printf("an item's view controller changed: no exception\n");
        } @catch (NSException *e) {
            printf("an item's view controller changed: %s\n", [[e name] UTF8String]);
        }

        /* an inspector whose content needs more than its minimum (1.229) */
        DocumentSplit *fitted = [[DocumentSplit alloc] init];
        fitted.inspector = [[FittedPane alloc] init];
        NSWindow *fw = [NSWindow windowWithContentViewController:fitted];
        [fw setContentSize:NSMakeSize(700, 272)];
        NSSplitViewItem *wide = [fitted splitViewItemForViewController:fitted.inspector];
        [wide setCollapsed:NO];
        panes("an inspector needing 260 opened: it is 260, past its minimum of 120", fitted);
        [fw setContentSize:NSMakeSize(600, 272)];
        panes("narrower: the content pane gives way, the inspector keeps 260", fitted);
        CGFloat edge = [[fitted splitView] positionOfDividerAtIndex:1];
        [fw sendEvent:mouse(NSEventTypeLeftMouseDown, fw, [fitted splitView], NSMakePoint(edge, 50))];
        [fw sendEvent:mouse(NSEventTypeLeftMouseDragged, fw, [fitted splitView], NSMakePoint(edge + 60, 50))];
        [fw sendEvent:mouse(NSEventTypeLeftMouseUp, fw, [fitted splitView], NSMakePoint(edge + 60, 50))];
        panes("its divider dragged 60 points right: held where the content fits", fitted);

        /* MacPass sizes the view to the window's before putting it in: the
         * panes are shared out only in the window, so the inspector keeps
         * its nib's 278 rather than being squeezed into the nib's 480 (1.229) */
        DocumentSplit *mp = [[DocumentSplit alloc] init];
        mp.inspector = [[WidePane alloc] init];
        mp.opensInspector = YES;
        NSWindow *mw = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 272)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        [mp view].frame = [[mw contentView] frame];
        [mw setContentViewController:mp];
        panes("MacPass's window: the inspector keeps the 278 of its nib, the entries take the rest", mp);
    }
    return 0;
}
