/* SPDX-License-Identifier: GPL-3.0-or-later
 * Tab view controllers, with no display: the segmented control on top and
 * on the bottom (where it sits, its labels, choosing a segment), a tab's
 * view loaded only when the tab is first shown, selectedTabViewItemIndex
 * observed however the tab is chosen, a subclass that overrides the tab
 * view's delegate calls and calls super, as MacPass's preferences do, the
 * toolbar style in a window (one item for each tab, the selected one
 * marked, choosing one), children added and removed the general way, the
 * selected child's title passed on, and the errors a Mac documents. */
#import <Cocoa/Cocoa.h>

@interface Pane : NSViewController
@property (copy) NSString *name;
@end
@implementation Pane
- (void)loadView
{
    printf("  %s loads its view\n", [self.name UTF8String]);
    [self setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 240)]];
}
@end
static Pane *pane(NSString *name, NSString *title)
{
    Pane *p = [[Pane alloc] init];
    p.name = name;
    p.title = title;
    return p;
}

/* As MacPass's MPTabViewController: told of each new tab, after super. */
@interface Preferences : NSTabViewController
@end
@implementation Preferences
- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item
{
    [super tabView:tv didSelectTabViewItem:item];
    printf("  the subclass hears of %s\n", [[item label] UTF8String]);
}
@end

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)o change:(NSDictionary *)change context:(void *)ctx
{
    printf("  observed %s: %s\n", [path UTF8String], [[change[NSKeyValueChangeNewKey] description] UTF8String]);
}
@end

static NSSegmentedControl *segments(NSTabViewController *c)
{
    for (NSView *v in [[c view] subviews])
        if ([v isKindOfClass:[NSSegmentedControl class]])
            return (NSSegmentedControl *)v;
    return nil;
}
static void show(const char *what, NSTabViewController *c)
{
    NSSegmentedControl *s = segments(c);
    NSRect t = [[c tabView] frame];
    printf("%s: tab view %.0f,%.0f %.0fx%.0f", what, t.origin.x, t.origin.y, t.size.width, t.size.height);
    if (s) {
        printf("; segments at y %.0f, centred %d:", [s frame].origin.y,
               fabs(NSMidX([s frame]) - NSMidX([[c view] bounds])) <= 1);
        for (NSInteger i = 0; i < [s segmentCount]; i++)
            printf(" %s%s", [[s labelForSegment:i] UTF8String], i == [s selectedSegment] ? "*" : "");
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* ---- segments on top ---- */
        NSTabViewController *c = [[NSTabViewController alloc] init];
        printf("style %ld, transition %#lx, tab view style %lu\n", (long)[c tabStyle],
               (unsigned long)[c transitionOptions], (unsigned long)[[c tabView] tabViewType]);
        printf("no tabs: selected %ld\n", (long)[c selectedTabViewItemIndex]);
        Watcher *watcher = [[Watcher alloc] init];
        [c addObserver:watcher forKeyPath:@"selectedTabViewItemIndex" options:NSKeyValueObservingOptionNew context:NULL];
        Pane *general = pane(@"general", @"General"), *colors = pane(@"colors", @"Colours");
        Pane *keys = pane(@"keys", @"Keys");
        printf("adding three tabs:\n");
        [c addTabViewItem:[NSTabViewItem tabViewItemWithViewController:general]];
        [c addTabViewItem:[NSTabViewItem tabViewItemWithViewController:colors]];
        [c addChildViewController:keys];
        printf("tabs %lu, children %lu, the third's label %s, selected %ld\n",
               (unsigned long)[[c tabViewItems] count], (unsigned long)[[c childViewControllers] count],
               [[[c tabViewItemForViewController:keys] label] UTF8String], (long)[c selectedTabViewItemIndex]);
        printf("loading the view:\n");
        NSWindow *w = [NSWindow windowWithContentViewController:c];
        show("on top", c);
        printf("the view is %.0fx%.0f, colours loaded %d\n", [[c view] frame].size.width, [[c view] frame].size.height,
               [colors isViewLoaded]);
        printf("choosing the second segment:\n");
        NSSegmentedControl *s = segments(c);
        [s setSelectedSegment:1];
        [NSApp sendAction:[s action] to:[s target] from:s];
        show("chosen", c);
        printf("colours loaded %d, its view in the tab view %d\n", [colors isViewLoaded],
               [[colors view] isDescendantOf:[c tabView]]);
        printf("selecting the third by index:\n");
        [c setSelectedTabViewItemIndex:2];
        show("by index", c);
        printf("selecting the first through the tab view:\n");
        [[c tabView] selectFirstTabViewItem:nil];
        show("through the tab view", c);
        @try {
            [c setSelectedTabViewItemIndex:3];
            printf("index 3: no exception\n");
        } @catch (NSException *e) {
            printf("index 3: %s\n", [[e name] UTF8String]);
        }
        @try {
            [c addTabViewItem:[[NSTabViewItem alloc] initWithIdentifier:@"bare"]];
            printf("a tab with no view controller: no exception\n");
        } @catch (NSException *e) {
            printf("a tab with no view controller: %s\n", [[e name] UTF8String]);
        }
        printf("removing the first child:\n");
        [c removeChildViewControllerAtIndex:0];
        show("removed", c);
        printf("tabs %lu, children %lu\n", (unsigned long)[[c tabViewItems] count],
               (unsigned long)[[c childViewControllers] count]);
        [c removeObserver:watcher forKeyPath:@"selectedTabViewItemIndex"];
        [c setTabStyle:NSTabViewControllerTabStyleSegmentedControlOnBottom];
        show("on the bottom", c);
        [c setTabStyle:NSTabViewControllerTabStyleUnspecified];
        show("unspecified", c);
        @try {
            [c setTabView:[[NSTabView alloc] init]];
            printf("a new tab view after loading: no exception\n");
        } @catch (NSException *e) {
            printf("a new tab view after loading: %s\n", [[e name] UTF8String]);
        }
        [w close];

        /* ---- the toolbar style, as MacPass's preferences ---- */
        Preferences *prefs = [[Preferences alloc] init];
        [prefs setTabStyle:NSTabViewControllerTabStyleToolbar];
        [prefs setCanPropagateSelectedChildViewControllerTitle:YES];
        NSTabViewItem *first = [NSTabViewItem tabViewItemWithViewController:pane(@"security", @"Security")];
        [first setIdentifier:@"security"];
        [prefs addTabViewItem:first];
        [prefs addTabViewItem:[NSTabViewItem tabViewItemWithViewController:pane(@"updates", @"Updates")]];
        printf("putting the toolbar style in a window:\n");
        NSWindow *pw = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 240)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        [pw setContentViewController:prefs];
        NSToolbar *bar = [pw toolbar];
        printf("toolbar %d, display mode %lu, items:", bar != nil, (unsigned long)[bar displayMode]);
        for (NSToolbarItem *item in [bar items])
            printf(" %s (%s)", [[item label] UTF8String], [[item itemIdentifier] UTF8String]);
        printf("\nselected %s, title %s, tab view fills the view %d\n", [[bar selectedItemIdentifier] UTF8String],
               [[prefs title] UTF8String], NSEqualRects([[prefs tabView] frame], [[prefs view] bounds]));
        printf("choosing the second toolbar item:\n");
        NSToolbarItem *second = [[bar items] objectAtIndex:1];
        [NSApp sendAction:[second action] to:[second target] from:second];
        printf("selected %s, index %ld, title %s\n", [[bar selectedItemIdentifier] UTF8String],
               (long)[prefs selectedTabViewItemIndex], [[prefs title] UTF8String]);
        printf("a third tab:\n");
        [prefs addChildViewController:pane(@"advanced", @"Advanced")];
        printf("toolbar items %lu, the last %s\n", (unsigned long)[[bar items] count],
               [[[[bar items] lastObject] label] UTF8String]);

        /* a window with a toolbar of the app's own keeps it */
        NSTabViewController *own = [[NSTabViewController alloc] init];
        [own setTabStyle:NSTabViewControllerTabStyleToolbar];
        [own addChildViewController:pane(@"one", @"One")];
        NSWindow *ow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 240)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        NSToolbar *mine = [[NSToolbar alloc] initWithIdentifier:@"mine"];
        [ow setToolbar:mine];
        [ow setContentViewController:own];
        printf("a window with its own toolbar keeps it %d\n", [ow toolbar] == mine);
    }
    return 0;
}
