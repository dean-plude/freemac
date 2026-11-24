/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSTabViewController, written from Apple's public
 * documentation. Each tab is a child view controller held by a tab view
 * item; the controller's tab view shows the selected child's view, loading
 * it only when it is first shown. The tabs are chosen with a segmented
 * control above or below the content, with the window's toolbar (an item
 * for each tab, the selected one marked), or with a control of the app's
 * own. The controller is its tab view's delegate. MacPass's preferences
 * window is one of these. Built without ARC. */
#import "AInternal.h"

static const CGFloat SEGMENT_MARGIN = 8;

/* The controller's own view, which says when it goes into a window, so the
 * toolbar style can put the tabs in that window's toolbar. */
@interface FTabControllerView : NSView
@property (assign) NSTabViewController *controller;
@end
@interface NSTabViewController (FerryTabs)
- (void)_viewMovedToWindow:(NSWindow *)window;
@end
@implementation FTabControllerView
- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [_controller _viewMovedToWindow:[self window]];
}
@end

@implementation NSTabViewController {
    NSTabView *_tabView;
    NSSegmentedControl *_segments;
    NSToolbar *_toolbar;
    NSWindow *_toolbarWindow; /* not retained: the window we gave our toolbar */
    NSTabViewControllerTabStyle _style;
    NSViewControllerTransitionOptions _transition;
    BOOL _propagates, _installed, _changingItems;
    NSSize _firstSize; /* the first tab's view's own size, before the tab view sized it */
}

- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle
{
    if ((self = [super initWithNibName:name bundle:bundle])) {
        _style = NSTabViewControllerTabStyleSegmentedControlOnTop;
        _transition = NSViewControllerTransitionCrossfade | NSViewControllerTransitionSlideForward;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _style = [coder containsValueForKey:@"NSTabStyle"] ? [coder decodeIntegerForKey:@"NSTabStyle"]
                                                           : NSTabViewControllerTabStyleSegmentedControlOnTop;
        _transition = NSViewControllerTransitionCrossfade | NSViewControllerTransitionSlideForward;
        _propagates = [coder decodeBoolForKey:@"NSCanPropagateSelectedChildViewControllerTitle"];
        NSArray *items = [coder decodeObjectForKey:@"NSTabViewItems"];
        if ([items isKindOfClass:[NSArray class]])
            for (id item in items)
                if ([item isKindOfClass:[NSTabViewItem class]])
                    [self addTabViewItem:item];
    }
    return self;
}
- (void)dealloc
{
    if ([_tabView delegate] == (id)self)
        [_tabView setDelegate:nil];
    [_segments setTarget:nil];
    if (_toolbarWindow && [_toolbarWindow toolbar] == _toolbar)
        [_toolbarWindow setToolbar:nil];
    [_toolbar setDelegate:nil];
    [_toolbar release];
    [_segments release];
    [_tabView release];
    [super dealloc];
}

/* ---- settings ---------------------------------------------------------------------- */

- (NSTabView *)tabView
{
    if (!_tabView) {
        _tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
        [_tabView setTabViewType:NSNoTabsNoBorder];
        [_tabView setDelegate:self];
    }
    return _tabView;
}
- (void)setTabView:(NSTabView *)tv
{
    if (tv == _tabView)
        return;
    if (_installed)
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSTabViewController: the tab view can't change once the view has loaded"];
    NSArray *items = [_tabView tabViewItems];
    [tv retain];
    if ([_tabView delegate] == (id)self)
        [_tabView setDelegate:nil];
    [_tabView release];
    _tabView = tv;
    [_tabView setDelegate:self];
    for (NSTabViewItem *item in items)
        [_tabView addTabViewItem:item];
}
- (NSTabViewControllerTabStyle)tabStyle { return _style; }
- (void)setTabStyle:(NSTabViewControllerTabStyle)s
{
    if (s == _style)
        return;
    _style = s;
    if (_installed)
        [self _arrange];
}
- (NSViewControllerTransitionOptions)transitionOptions { return _transition; }
- (void)setTransitionOptions:(NSViewControllerTransitionOptions)t { _transition = t; }
- (BOOL)canPropagateSelectedChildViewControllerTitle { return _propagates; }
- (void)setCanPropagateSelectedChildViewControllerTitle:(BOOL)f { _propagates = f; }

/* ---- the view ---------------------------------------------------------------------- */

- (void)loadView
{
    if ([self nibName]) {
        [super loadView];
        return;
    }
    /* as big as the first tab's view, and its control */
    NSSize size = NSMakeSize(480, 270);
    if (_firstSize.width > 0 && _firstSize.height > 0)
        size = _firstSize;
    FTabControllerView *view = [[FTabControllerView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    [view setController:self];
    [self setView:view];
    [view release];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    [self _install];
}
- (void)_install
{
    if (_installed || ![self view])
        return;
    NSTabView *tv = [self tabView];
    NSView *v = [self view];
    if (tv != v && ![tv isDescendantOf:v]) {
        [tv setFrame:[v bounds]];
        [tv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [v addSubview:tv];
    }
    _installed = YES;
    [self _arrange];
}

/* Puts the tab view and the tabs' control in place for the style. */
- (void)_arrange
{
    NSView *v = [self view];
    NSTabView *tv = [self tabView];
    NSRect b = [v bounds];
    BOOL segmented = _style == NSTabViewControllerTabStyleSegmentedControlOnTop ||
                     _style == NSTabViewControllerTabStyleSegmentedControlOnBottom;
    if (segmented && !_segments) {
        _segments = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
        [_segments setTrackingMode:NSSegmentSwitchTrackingSelectOne];
        [_segments setTarget:self];
        [_segments setAction:@selector(_segmentChosen:)];
    }
    if (!segmented)
        [_segments removeFromSuperview];
    if (_style != NSTabViewControllerTabStyleToolbar)
        [self _removeToolbar];
    CGFloat control = 0;
    if (segmented) {
        [self _updateSegments];
        NSRect f = [_segments frame];
        control = f.size.height + 2 * SEGMENT_MARGIN;
        BOOL top = _style == NSTabViewControllerTabStyleSegmentedControlOnTop;
        BOOL flipped = [v isFlipped];
        f.origin.x = floor((b.size.width - f.size.width) / 2);
        f.origin.y = top != flipped ? NSMaxY(b) - SEGMENT_MARGIN - f.size.height : SEGMENT_MARGIN;
        [_segments setFrame:f];
        [_segments setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin |
                                       (top != flipped ? NSViewMinYMargin : NSViewMaxYMargin)];
        if ([_segments superview] != v)
            [v addSubview:_segments];
        NSRect t = b;
        t.size.height = fmax(0, b.size.height - control);
        if (top == flipped)
            t.origin.y = control;
        if (tv != v)
            [tv setFrame:t];
    } else if (tv != v)
        [tv setFrame:b];
    if (_style == NSTabViewControllerTabStyleToolbar && [v window])
        [self _viewMovedToWindow:[v window]];
}

- (void)_updateSegments
{
    if (!_segments)
        return;
    NSArray *items = [[self tabView] tabViewItems];
    [_segments setSegmentCount:(NSInteger)[items count]];
    for (NSUInteger i = 0; i < [items count]; i++) {
        NSTabViewItem *item = [items objectAtIndex:i];
        [_segments setLabel:[item label] forSegment:(NSInteger)i];
        [_segments setImage:[item image] forSegment:(NSInteger)i];
        [_segments setToolTip:[item toolTip] forSegment:(NSInteger)i];
        [_segments setWidth:0 forSegment:(NSInteger)i];
    }
    [_segments setSelectedSegment:[self selectedTabViewItemIndex]];
    NSPoint at = [_segments frame].origin;
    [_segments sizeToFit];
    NSRect f = [_segments frame];
    NSRect b = [[self view] bounds];
    f.origin = NSMakePoint(floor((b.size.width - f.size.width) / 2), at.y);
    [_segments setFrame:f];
}
- (void)_segmentChosen:(id)sender
{
    NSInteger i = [_segments selectedSegment];
    if (i >= 0)
        [self setSelectedTabViewItemIndex:i];
    /* refused by a delegate: show the tab that stayed */
    [_segments setSelectedSegment:[self selectedTabViewItemIndex]];
}

/* ---- the toolbar style --------------------------------------------------------------- */

- (NSString *)_toolbarIdentifierFor:(NSTabViewItem *)item index:(NSUInteger)i
{
    id identifier = [item identifier];
    if ([identifier isKindOfClass:[NSString class]] && [identifier length])
        return identifier;
    return [NSString stringWithFormat:@"NSTabViewController.tab.%lu", (unsigned long)i];
}
- (NSArray *)_toolbarIdentifiers
{
    NSArray *items = [[self tabView] tabViewItems];
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:[items count]];
    for (NSUInteger i = 0; i < [items count]; i++)
        [ids addObject:[self _toolbarIdentifierFor:[items objectAtIndex:i] index:i]];
    return ids;
}
- (void)_viewMovedToWindow:(NSWindow *)window
{
    if (_style != NSTabViewControllerTabStyleToolbar || !_installed)
        return;
    if (!window) {
        [self _removeToolbar];
        return;
    }
    if (window == _toolbarWindow && [window toolbar] == _toolbar)
        return;
    if ([window toolbar] && [window toolbar] != _toolbar)
        return; /* the window has a toolbar of the app's own */
    if (!_toolbar) {
        _toolbar = [[NSToolbar alloc]
            initWithIdentifier:[NSString stringWithFormat:@"NSTabViewController.%p", (void *)self]];
        [_toolbar setDelegate:self];
        [_toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
        [_toolbar setAllowsUserCustomization:NO];
    }
    _toolbarWindow = window;
    [self _reloadToolbar];
    [window setToolbar:_toolbar];
}
- (void)_removeToolbar
{
    if (_toolbarWindow && [_toolbarWindow toolbar] == _toolbar)
        [_toolbarWindow setToolbar:nil];
    _toolbarWindow = nil;
}
- (void)_reloadToolbar
{
    if (!_toolbar)
        return;
    while ([[_toolbar items] count])
        [_toolbar removeItemAtIndex:0];
    NSArray *ids = [self _toolbarIdentifiers];
    for (NSUInteger i = 0; i < [ids count]; i++)
        [_toolbar insertItemWithItemIdentifier:[ids objectAtIndex:i] atIndex:(NSInteger)i];
    [self _markToolbarSelection];
}
- (void)_markToolbarSelection
{
    NSInteger i = [self selectedTabViewItemIndex];
    NSArray *ids = [self _toolbarIdentifiers];
    [_toolbar setSelectedItemIdentifier:i >= 0 && i < (NSInteger)[ids count] ? [ids objectAtIndex:(NSUInteger)i] : nil];
}
- (void)_toolbarItemChosen:(NSToolbarItem *)sender
{
    NSUInteger i = [[self _toolbarIdentifiers] indexOfObject:[sender itemIdentifier]];
    if (i != NSNotFound)
        [self setSelectedTabViewItemIndex:(NSInteger)i];
    [self _markToolbarSelection];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)flag
{
    NSUInteger i = [[self _toolbarIdentifiers] indexOfObject:identifier];
    if (i == NSNotFound)
        return nil;
    NSTabViewItem *tab = [[[self tabView] tabViewItems] objectAtIndex:i];
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    [item setLabel:[tab label]];
    [item setPaletteLabel:[tab label]];
    [item setToolTip:[tab toolTip]];
    [item setImage:[tab image]];
    [item setTarget:self];
    [item setAction:@selector(_toolbarItemChosen:)];
    return item;
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return [self _toolbarIdentifiers]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return [self _toolbarIdentifiers]; }
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar { return [self _toolbarIdentifiers]; }

/* ---- items ------------------------------------------------------------------------- */

- (NSArray *)tabViewItems { return [[self tabView] tabViewItems]; }
- (void)setTabViewItems:(NSArray *)items
{
    for (NSTabViewItem *item in [self tabViewItems])
        if (![items containsObject:item])
            [self removeTabViewItem:item];
    for (NSUInteger i = 0; i < [items count]; i++) {
        NSTabViewItem *item = [items objectAtIndex:i];
        if ([[self tabView] indexOfTabViewItem:item] == NSNotFound)
            [self insertTabViewItem:item atIndex:(NSInteger)i];
    }
}
- (NSTabViewItem *)tabViewItemForViewController:(NSViewController *)vc
{
    for (NSTabViewItem *item in [self tabViewItems])
        if ([item viewController] == vc)
            return item;
    return nil;
}
- (void)addTabViewItem:(NSTabViewItem *)item { [self insertTabViewItem:item atIndex:[[self tabViewItems] count]]; }
- (void)insertTabViewItem:(NSTabViewItem *)item atIndex:(NSInteger)index
{
    NSViewController *vc = [item viewController];
    if (!item || !vc)
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSTabViewController insertTabViewItem:atIndex:]: the item has no view controller"];
    NSTabView *tv = [self tabView];
    if ([tv indexOfTabViewItem:item] != NSNotFound)
        return;
    NSInteger at = MIN(MAX(index, 0), [tv numberOfTabViewItems]);
    BOOL first = [tv numberOfTabViewItems] == 0;
    /* the tab view shows a first tab at once, sized to fit it */
    if (first && ![self isViewLoaded])
        _firstSize = [[vc view] frame].size;
    _changingItems = YES;
    [super insertChildViewController:vc atIndex:at];
    if (first)
        [self willChangeValueForKey:@"selectedTabViewItemIndex"];
    [tv insertTabViewItem:item atIndex:at];
    if (first)
        [self didChangeValueForKey:@"selectedTabViewItemIndex"];
    _changingItems = NO;
    /* the first tab is selected with no word to the delegate, so its title
     * is passed on here */
    if (first && _propagates && [[item viewController] title])
        [self setTitle:[[item viewController] title]];
    [self _itemsChanged];
}
- (void)removeTabViewItem:(NSTabViewItem *)item
{
    NSTabView *tv = [self tabView];
    if ([tv indexOfTabViewItem:item] == NSNotFound)
        return;
    [item retain];
    _changingItems = YES;
    [self willChangeValueForKey:@"selectedTabViewItemIndex"];
    [tv removeTabViewItem:item];
    [self didChangeValueForKey:@"selectedTabViewItemIndex"];
    NSUInteger child = [[self childViewControllers] indexOfObjectIdenticalTo:[item viewController]];
    if (child != NSNotFound)
        [super removeChildViewControllerAtIndex:(NSInteger)child];
    _changingItems = NO;
    [item release];
    [self _itemsChanged];
}
- (void)_itemsChanged
{
    if (!_installed)
        return;
    [self _updateSegments];
    [self _reloadToolbar];
}

/* A child view controller added the general way gets a tab of its own. */
- (void)insertChildViewController:(NSViewController *)child atIndex:(NSInteger)index
{
    if (!child || [self tabViewItemForViewController:child])
        return;
    [self insertTabViewItem:[NSTabViewItem tabViewItemWithViewController:child] atIndex:index];
}
- (void)removeChildViewControllerAtIndex:(NSInteger)index
{
    NSArray *children = [self childViewControllers];
    if (index < 0 || index >= (NSInteger)[children count])
        return;
    NSTabViewItem *item = [self tabViewItemForViewController:[children objectAtIndex:(NSUInteger)index]];
    if (item)
        [self removeTabViewItem:item];
    else
        [super removeChildViewControllerAtIndex:index];
}

/* ---- selection --------------------------------------------------------------------- */

/* Observers hear of a new selection from the tab view's calls below, however
 * it was chosen, so the setter doesn't announce it again. */
+ (BOOL)automaticallyNotifiesObserversOfSelectedTabViewItemIndex { return NO; }
- (NSInteger)selectedTabViewItemIndex
{
    NSTabViewItem *selected = [[self tabView] selectedTabViewItem];
    return selected ? [[self tabView] indexOfTabViewItem:selected] : -1;
}
- (void)setSelectedTabViewItemIndex:(NSInteger)i
{
    NSTabView *tv = [self tabView];
    if (i < 0 || i >= [tv numberOfTabViewItems])
        [NSException raise:NSRangeException
                    format:@"-[NSTabViewController setSelectedTabViewItemIndex:]: index %ld beyond bounds %ld",
                           (long)i, (long)[tv numberOfTabViewItems]];
    [tv selectTabViewItemAtIndex:i];
}
/* The tab view tells of selections through these, and so does a subclass
 * that overrides them and calls super. */
- (BOOL)tabView:(NSTabView *)tv shouldSelectTabViewItem:(NSTabViewItem *)item { return YES; }
- (void)tabView:(NSTabView *)tv willSelectTabViewItem:(NSTabViewItem *)item {}
/* Observers of selectedTabViewItemIndex hear of the change here, so a
 * subclass that doesn't call super for the will-select can't unbalance them. */
- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item
{
    if (!_changingItems) {
        [self willChangeValueForKey:@"selectedTabViewItemIndex"];
        [self didChangeValueForKey:@"selectedTabViewItemIndex"];
    }
    [_segments setSelectedSegment:[self selectedTabViewItemIndex]];
    [self _markToolbarSelection];
    if (_propagates && [[item viewController] title])
        [self setTitle:[[item viewController] title]];
}
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tv {}
@end
