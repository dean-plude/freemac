/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSSplitViewController and NSSplitViewItem, written from
 * Apple's public documentation. The controller keeps a list of items, each
 * holding a child view controller, and shows the children's views side by
 * side in its split view, which it is the delegate of. Each item says how
 * thick its pane may be, how firmly it holds its size, and whether it is
 * collapsed or may be collapsed. Without Auto Layout, an item's limits are
 * kept by the split view's delegate calls, and a collapsed pane is hidden
 * with the room going to the others, as a split view does. A pane whose
 * view is laid out by constraints is never thinner than its content needs
 * (its fitting size), even past the item's minimum (freemac 1.229), as
 * Auto Layout keeps it on a Mac. The panes are shared out only once the
 * split view is in a window, so a pane keeps the thickness of its nib
 * rather than being squeezed into the size the controller's own nib gave
 * (also 1.229). MacPass's document window is one of these. Built without
 * ARC. */
#import "AInternal.h"

@interface NSSplitViewController (FerryItems)
- (void)_itemDidChangeCollapsed:(NSSplitViewItem *)item;
- (void)_itemDidChangeHolding:(NSSplitViewItem *)item;
@end
@interface NSSplitViewItem (FerryItems)
- (void)_setOwner:(NSSplitViewController *)owner;
- (void)_noteCollapsed:(BOOL)f;
- (CGFloat)_leastThickness;
- (void)_setContentThickness:(CGFloat)t;
@end

/* ---- NSSplitViewItem ----------------------------------------------------------------- */

@implementation NSSplitViewItem {
    NSViewController *_viewController;
    NSSplitViewController *_owner; /* not retained */
    NSSplitViewItemBehavior _behavior;
    NSSplitViewItemCollapseBehavior _collapseBehavior;
    NSTitlebarSeparatorStyle _separator;
    NSLayoutPriority _holding;
    CGFloat _min, _max, _fraction, _automaticMax;
    CGFloat _content; /* the thickness its view's constraints need, or 0 */
    BOOL _collapsed, _canCollapse, _springLoaded, _fromResize, _fullHeight, _safeArea;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _holding = NSLayoutPriorityDefaultLow;
        _min = _max = _fraction = _automaticMax = NSSplitViewItemUnspecifiedDimension;
        _safeArea = YES;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        id vc = [coder decodeObjectForKey:@"NSViewController"];
        if ([vc isKindOfClass:[NSViewController class]])
            _viewController = [vc retain];
        _collapsed = [coder decodeBoolForKey:@"NSCollapsed"];
        _canCollapse = [coder decodeBoolForKey:@"NSCanCollapse"];
        if ([coder containsValueForKey:@"NSHoldingPriority"])
            _holding = [coder decodeFloatForKey:@"NSHoldingPriority"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_viewController forKey:@"NSViewController"];
    [coder encodeBool:_collapsed forKey:@"NSCollapsed"];
    [coder encodeBool:_canCollapse forKey:@"NSCanCollapse"];
    [coder encodeFloat:_holding forKey:@"NSHoldingPriority"];
}
+ (instancetype)splitViewItemWithViewController:(NSViewController *)vc
{
    NSSplitViewItem *item = [[[self alloc] init] autorelease];
    [item setViewController:vc];
    return item;
}
/* A sidebar may collapse, and holds its size a little more firmly than the
 * content beside it; its limits are Ferry's own choice of a standard
 * sidebar's (see docs/ferry-gui.md). */
+ (instancetype)sidebarWithViewController:(NSViewController *)vc
{
    NSSplitViewItem *item = [self splitViewItemWithViewController:vc];
    item->_behavior = NSSplitViewItemBehaviorSidebar;
    item->_canCollapse = item->_springLoaded = item->_fromResize = YES;
    item->_holding = NSLayoutPriorityDefaultLow + 10;
    item->_min = 150;
    item->_max = 400;
    item->_fraction = 0.15;
    return item;
}
+ (instancetype)contentListWithViewController:(NSViewController *)vc
{
    NSSplitViewItem *item = [self splitViewItemWithViewController:vc];
    item->_behavior = NSSplitViewItemBehaviorContentList;
    item->_min = 200;
    return item;
}
+ (instancetype)inspectorWithViewController:(NSViewController *)vc
{
    NSSplitViewItem *item = [self splitViewItemWithViewController:vc];
    item->_behavior = NSSplitViewItemBehaviorInspector;
    item->_canCollapse = item->_fromResize = YES;
    item->_holding = NSLayoutPriorityDefaultLow + 10;
    item->_min = 200;
    item->_max = 400;
    return item;
}
- (void)dealloc
{
    [_viewController release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSSplitViewItem %p: %@%s>", self, _viewController,
                                      _collapsed ? ", collapsed" : ""];
}

- (void)_setOwner:(NSSplitViewController *)owner { _owner = owner; }
/* the thinnest the pane may be: the item's minimum, or what its content
 * needs when that is more */
- (CGFloat)_leastThickness { return fmax(_min >= 0 ? _min : 0, _content); }
- (void)_setContentThickness:(CGFloat)t { _content = t; }
- (NSViewController *)viewController { return _viewController; }
- (void)setViewController:(NSViewController *)vc
{
    if (_owner && vc != _viewController)
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSSplitViewItem: the view controller of an item in a split view controller can't change"];
    [vc retain];
    [_viewController release];
    _viewController = vc;
}
- (NSSplitViewItemBehavior)behavior { return _behavior; }
- (BOOL)isCollapsed { return _collapsed; }
- (void)setCollapsed:(BOOL)f
{
    if (f == _collapsed)
        return;
    _collapsed = f;
    [_owner _itemDidChangeCollapsed:self];
}
/* The split view collapsed or opened the pane itself. */
- (void)_noteCollapsed:(BOOL)f
{
    if (f == _collapsed)
        return;
    [self willChangeValueForKey:@"collapsed"];
    _collapsed = f;
    [self didChangeValueForKey:@"collapsed"];
}
- (BOOL)canCollapse { return _canCollapse; }
- (void)setCanCollapse:(BOOL)f { _canCollapse = f; }
- (BOOL)isSpringLoaded { return _springLoaded; }
- (void)setSpringLoaded:(BOOL)f { _springLoaded = f; }
- (BOOL)canCollapseFromWindowResize { return _fromResize; }
- (void)setCanCollapseFromWindowResize:(BOOL)f { _fromResize = f; }
- (NSSplitViewItemCollapseBehavior)collapseBehavior { return _collapseBehavior; }
- (void)setCollapseBehavior:(NSSplitViewItemCollapseBehavior)b { _collapseBehavior = b; }
- (NSLayoutPriority)holdingPriority { return _holding; }
- (void)setHoldingPriority:(NSLayoutPriority)p
{
    _holding = p;
    [_owner _itemDidChangeHolding:self];
}
- (CGFloat)minimumThickness { return _min; }
- (void)setMinimumThickness:(CGFloat)t { _min = t; }
- (CGFloat)maximumThickness { return _max; }
- (void)setMaximumThickness:(CGFloat)t { _max = t; }
- (CGFloat)preferredThicknessFraction { return _fraction; }
- (void)setPreferredThicknessFraction:(CGFloat)f { _fraction = f; }
- (CGFloat)automaticMaximumThickness { return _automaticMax; }
- (void)setAutomaticMaximumThickness:(CGFloat)t { _automaticMax = t; }
- (BOOL)allowsFullHeightLayout { return _fullHeight; }
- (void)setAllowsFullHeightLayout:(BOOL)f { _fullHeight = f; }
- (BOOL)automaticallyAdjustsSafeAreaInsets { return _safeArea; }
- (void)setAutomaticallyAdjustsSafeAreaInsets:(BOOL)f { _safeArea = f; }
- (NSTitlebarSeparatorStyle)titlebarSeparatorStyle { return _separator; }
- (void)setTitlebarSeparatorStyle:(NSTitlebarSeparatorStyle)s { _separator = s; }
@end

/* ---- NSSplitViewController ------------------------------------------------------------- */

/* An item's thickness held within its minimum and maximum. */
static CGFloat clamp_thickness(NSSplitViewItem *item, CGFloat t);

@implementation NSSplitViewController {
    NSSplitView *_splitView;
    NSMutableArray *_items;
    CGFloat _inlineSidebars;
    BOOL _installed; /* the split view is in the view, with the items' panes */
}

- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle
{
    if ((self = [super initWithNibName:name bundle:bundle])) {
        _items = [[NSMutableArray alloc] init];
        _inlineSidebars = NSSplitViewControllerAutomaticDimension;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        if (!_items)
            _items = [[NSMutableArray alloc] init];
        _inlineSidebars = NSSplitViewControllerAutomaticDimension;
        NSArray *items = [coder decodeObjectForKey:@"NSSplitViewItems"];
        if ([items isKindOfClass:[NSArray class]])
            for (id item in items)
                if ([item isKindOfClass:[NSSplitViewItem class]])
                    [self addSplitViewItem:item];
    }
    return self;
}
- (void)dealloc
{
    if ([_splitView delegate] == (id)self)
        [_splitView setDelegate:nil];
    for (NSSplitViewItem *item in _items)
        [item _setOwner:nil];
    [_items release];
    [_splitView release];
    [super dealloc];
}

/* Side by side, with thin dividers, until the app says otherwise. */
- (NSSplitView *)splitView
{
    if (!_splitView) {
        NSView *v = [self isViewLoaded] ? [self view] : nil;
        if ([v isKindOfClass:[NSSplitView class]])
            _splitView = (NSSplitView *)[v retain];
        else {
            _splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
            [_splitView setVertical:YES];
            [_splitView setDividerStyle:NSSplitViewDividerStyleThin];
        }
    }
    return _splitView;
}
- (void)setSplitView:(NSSplitView *)sv
{
    if (sv == _splitView)
        return;
    if (_installed)
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSSplitViewController: the split view can't change once the view has loaded"];
    [sv retain];
    [_splitView release];
    _splitView = sv;
}
- (CGFloat)minimumThicknessForInlineSidebars { return _inlineSidebars; }
- (void)setMinimumThicknessForInlineSidebars:(CGFloat)t { _inlineSidebars = t; }

/* With no nib, the view is the split view itself. */
- (void)loadView
{
    if ([self nibName]) {
        [super loadView];
        return;
    }
    [self setView:[self splitView]];
}

/* A view from a nib that isn't a split view holds the split view, filling it. */
- (void)_install
{
    if (_installed)
        return;
    NSView *v = [self view];
    if (!v)
        return;
    if (!_splitView && [v isKindOfClass:[NSSplitView class]])
        _splitView = (NSSplitView *)[v retain];
    NSSplitView *sv = [self splitView];
    if (sv != v && ![sv isDescendantOf:v]) {
        [sv setFrame:[v bounds]];
        [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [v addSubview:sv];
        /* held to the view's edges by constraints, as on a Mac, so it still
         * fills the view when the app has it stop translating its mask */
        [sv setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[sv leadingAnchor] constraintEqualToAnchor:[v leadingAnchor]],
            [[sv trailingAnchor] constraintEqualToAnchor:[v trailingAnchor]],
            [[sv topAnchor] constraintEqualToAnchor:[v topAnchor]],
            [[sv bottomAnchor] constraintEqualToAnchor:[v bottomAnchor]],
        ]];
    }
    [sv setDelegate:self];
    _installed = YES;
    for (NSUInteger i = 0; i < [_items count]; i++)
        [self _showItem:[_items objectAtIndex:i] atIndex:i];
    [self _fit];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    [self _install];
}

/* ---- items ------------------------------------------------------------------------- */

- (NSArray *)splitViewItems { return [[_items copy] autorelease]; }
- (void)setSplitViewItems:(NSArray *)items
{
    for (NSSplitViewItem *item in [[_items copy] autorelease])
        if (![items containsObject:item])
            [self removeSplitViewItem:item];
    for (NSUInteger i = 0; i < [items count]; i++) {
        NSSplitViewItem *item = [items objectAtIndex:i];
        if ([_items indexOfObjectIdenticalTo:item] == NSNotFound)
            [self insertSplitViewItem:item atIndex:i];
    }
}
- (NSSplitViewItem *)splitViewItemForViewController:(NSViewController *)vc
{
    for (NSSplitViewItem *item in _items)
        if ([item viewController] == vc)
            return item;
    return nil;
}
- (NSSplitViewItem *)_itemForView:(NSView *)v
{
    for (NSSplitViewItem *item in _items)
        if ([[item viewController] viewIfLoaded] == v)
            return item;
    return nil;
}
- (void)addSplitViewItem:(NSSplitViewItem *)item { [self insertSplitViewItem:item atIndex:[_items count]]; }
- (void)insertSplitViewItem:(NSSplitViewItem *)item atIndex:(NSInteger)index
{
    NSViewController *vc = [item viewController];
    if (!item || !vc)
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSSplitViewController insertSplitViewItem:atIndex:]: the item has no view controller"];
    if ([_items indexOfObjectIdenticalTo:item] != NSNotFound)
        return;
    NSUInteger at = (NSUInteger)MIN(MAX(index, 0), (NSInteger)[_items count]);
    [_items insertObject:item atIndex:at];
    [item _setOwner:self];
    [super insertChildViewController:vc atIndex:(NSInteger)at];
    if ([self isViewLoaded] && !_installed)
        [self _install];
    else if (_installed) {
        [self _showItem:item atIndex:at];
        /* a new pane lays the panes out afresh: those with a preferred
         * fraction go back to it, and the room is shared again */
        for (NSSplitViewItem *other in _items) {
            NSView *v = [[other viewController] viewIfLoaded];
            if (v && [v superview] == _splitView && [other preferredThicknessFraction] > 0)
                [self _setThickness:clamp_thickness(other, [self _length] * [other preferredThicknessFraction]) of:v];
        }
        [self _fit];
    }
}
- (void)removeSplitViewItem:(NSSplitViewItem *)item
{
    NSUInteger i = [_items indexOfObjectIdenticalTo:item];
    if (i == NSNotFound)
        return;
    [item retain];
    [_items removeObjectAtIndex:i];
    [item _setOwner:nil];
    NSViewController *vc = [item viewController];
    NSView *v = [vc viewIfLoaded];
    if (v && [v superview] == _splitView)
        [_splitView removeArrangedSubview:v];
    NSUInteger child = [[self childViewControllers] indexOfObjectIdenticalTo:vc];
    if (child != NSNotFound)
        [super removeChildViewControllerAtIndex:(NSInteger)child];
    if (_installed)
        [self _fit];
    [item release];
}

/* A child view controller added the general way gets an item of its own. */
- (void)insertChildViewController:(NSViewController *)child atIndex:(NSInteger)index
{
    if (!child || [self splitViewItemForViewController:child])
        return;
    [self insertSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:child] atIndex:index];
}
- (void)removeChildViewControllerAtIndex:(NSInteger)index
{
    NSArray *children = [self childViewControllers];
    if (index < 0 || index >= (NSInteger)[children count])
        return;
    NSSplitViewItem *item = [self splitViewItemForViewController:[children objectAtIndex:(NSUInteger)index]];
    if (item)
        [self removeSplitViewItem:item];
    else
        [super removeChildViewControllerAtIndex:index];
}

/* ---- panes ------------------------------------------------------------------------- */

- (BOOL)_vertical { return [_splitView isVertical]; }
- (CGFloat)_length
{
    NSRect b = [_splitView bounds];
    return [self _vertical] ? b.size.width : b.size.height;
}
- (CGFloat)_thickness:(NSView *)v { return [self _vertical] ? [v frame].size.width : [v frame].size.height; }
- (void)_setThickness:(CGFloat)t of:(NSView *)v
{
    NSRect f = [v frame];
    if ([self _vertical])
        f.size.width = t;
    else
        f.size.height = t;
    [v setFrame:f];
}
static CGFloat clamp_thickness(NSSplitViewItem *item, CGFloat t)
{
    if ([item maximumThickness] >= 0)
        t = fmin(t, [item maximumThickness]);
    return fmax(t, [item _leastThickness]);
}

/* What each pane's content needs along the split view's axis: the fitting
 * size of a view laid out by constraints (a collapsed pane's too, whose
 * constraints hold while it is hidden, as on a Mac). */
- (void)_measureContent
{
    for (NSSplitViewItem *item in _items) {
        NSView *v = [[item viewController] viewIfLoaded];
        NSSize fit;
        CGFloat t = 0;
        if (v && AConstraintFittingSize(v, &fit))
            t = ceil([self _vertical] ? fit.width : fit.height);
        [item _setContentThickness:t];
    }
}

/* Puts an item's pane in the split view, in the items' order, at a first
 * thickness: its preferred fraction, or an equal share, within its limits. */
- (void)_showItem:(NSSplitViewItem *)item atIndex:(NSUInteger)at
{
    NSView *v = [[item viewController] view];
    if (!v || [v superview] == _splitView)
        return;
    [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSSize fit;
    [item _setContentThickness:AConstraintFittingSize(v, &fit) ? ceil([self _vertical] ? fit.width : fit.height) : 0];
    CGFloat len = [self _length], t;
    if ([item preferredThicknessFraction] > 0)
        t = len * [item preferredThicknessFraction];
    else
        t = [self _thickness:v] > 0 ? [self _thickness:v] : len / ([_items count] ?: 1);
    [self _setThickness:clamp_thickness(item, t) of:v];
    [v setHidden:[item isCollapsed]];
    /* the panes come in the items' order */
    NSInteger before = 0;
    NSArray *subviews = [_splitView subviews];
    for (NSUInteger i = 0; i < at; i++) {
        NSView *u = [[[_items objectAtIndex:i] viewController] viewIfLoaded];
        if (u && [subviews indexOfObjectIdenticalTo:u] != NSNotFound)
            before++;
    }
    [_splitView insertArrangedSubview:v atIndex:before];
}

/* Holding priorities go to the split view by pane, then the panes share
 * its room. */
- (void)_fit
{
    if (!_installed)
        return;
    NSArray *subviews = [_splitView subviews];
    for (NSUInteger i = 0; i < [subviews count]; i++) {
        NSSplitViewItem *item = [self _itemForView:[subviews objectAtIndex:i]];
        if (item)
            [_splitView setHoldingPriority:[item holdingPriority] forSubviewAtIndex:(NSInteger)i];
    }
    [self _shareKeeping:nil];
}

/* Gives the room the visible panes don't fill, or takes what they fill too
 * much, from the panes with the lowest holding priority first, shared
 * equally among those at one priority and kept within each item's limits.
 * The pane to keep, one just opened or put in, keeps its thickness if the
 * others can make room. What no pane can take goes to the last one that
 * took a share, or the last visible pane. */
- (void)_shareKeeping:(NSView *)keep
{
    NSArray *subviews = [_splitView subviews];
    NSUInteger n = [subviews count], visible = 0;
    /* Panes are shared out only once the split view is in a window, as a
     * Mac lays it out then: a pane isn't squeezed to fit the size the view
     * had in its nib, before it is given the window's (1.229). */
    if (!n || ![_splitView window])
        return;
    CGFloat sizes[n], used = 0;
    BOOL held[n];
    NSInteger taker = -1;
    [self _measureContent];
    for (NSUInteger i = 0; i < n; i++) {
        NSView *v = [subviews objectAtIndex:i];
        sizes[i] = [self _thickness:v];
        /* a pane is never left outside its item's limits */
        NSSplitViewItem *item = [self _itemForView:v];
        if (item)
            sizes[i] = clamp_thickness(item, sizes[i]);
        held[i] = [v isHidden] || v == keep;
        if ([v isHidden]) {
            /* a collapsed pane takes no room, but its content's constraints
             * still hold, so it keeps a thickness they fit */
            if (sizes[i] != [self _thickness:v])
                [self _setThickness:sizes[i] of:v];
            continue;
        }
        used += sizes[i];
        visible++;
        taker = (NSInteger)i;
    }
    if (!visible)
        return;
    CGFloat room = [self _length] - (visible - 1) * [_splitView dividerThickness], change = room - used;
    while (fabs(change) >= 0.5) {
        /* the lowest holding priority among the panes that can still move */
        NSLayoutPriority level = 0;
        NSUInteger count = 0;
        for (NSUInteger i = 0; i < n; i++) {
            if (held[i])
                continue;
            NSLayoutPriority p = [_splitView holdingPriorityForSubviewAtIndex:(NSInteger)i];
            if (!count || p < level) {
                level = p;
                count = 0;
            }
            if (p == level)
                count++;
        }
        if (!count)
            break;
        CGFloat share = change / count;
        for (NSUInteger i = 0; i < n; i++) {
            if (held[i] || [_splitView holdingPriorityForSubviewAtIndex:(NSInteger)i] != level)
                continue;
            NSSplitViewItem *item = [self _itemForView:[subviews objectAtIndex:i]];
            CGFloat want = sizes[i] + share, now = fmax(0, item ? clamp_thickness(item, want) : want);
            if (now != want)
                held[i] = YES; /* at a limit: the others at its priority take the rest */
            else
                taker = (NSInteger)i;
            change -= now - sizes[i];
            sizes[i] = now;
        }
    }
    /* whole points, with what rounding and the limits left going to one pane */
    CGFloat given = 0;
    for (NSUInteger i = 0; i < n; i++)
        if (![[subviews objectAtIndex:i] isHidden]) {
            sizes[i] = floor(sizes[i]);
            given += sizes[i];
        }
    sizes[taker] = fmax(0, sizes[taker] + room - given);
    for (NSUInteger i = 0; i < n; i++)
        if (![[subviews objectAtIndex:i] isHidden])
            [self _setThickness:sizes[i] of:[subviews objectAtIndex:i]];
    [_splitView adjustSubviews];
}

- (void)_itemDidChangeHolding:(NSSplitViewItem *)item
{
    if (_installed)
        [self _fit];
}

/* Collapsing hides the pane, and the others take its room; opening it
 * again gives it back the thickness it had, within its limits. */
- (void)_itemDidChangeCollapsed:(NSSplitViewItem *)item
{
    if (!_installed)
        return;
    NSView *v = [[item viewController] viewIfLoaded];
    if (!v || [v superview] != _splitView)
        return;
    if ([item isCollapsed])
        [v setHidden:YES];
    else {
        CGFloat t = [self _thickness:v];
        if (t <= 0)
            t = [self _length] / ([_items count] ?: 1);
        NSSize fit;
        [item _setContentThickness:AConstraintFittingSize(v, &fit) ? ceil([self _vertical] ? fit.width : fit.height)
                                                                    : 0];
        [self _setThickness:clamp_thickness(item, t) of:v];
        [v setHidden:NO];
    }
    [self _shareKeeping:[item isCollapsed] ? nil : v];
}

- (NSSplitViewItem *)_firstItemWithBehavior:(NSSplitViewItemBehavior)b
{
    for (NSSplitViewItem *item in _items)
        if ([item behavior] == b)
            return item;
    return nil;
}
- (IBAction)toggleSidebar:(id)sender
{
    NSSplitViewItem *item = [self _firstItemWithBehavior:NSSplitViewItemBehaviorSidebar];
    [item setCollapsed:![item isCollapsed]];
}
- (IBAction)toggleInspector:(id)sender
{
    NSSplitViewItem *item = [self _firstItemWithBehavior:NSSplitViewItemBehaviorInspector];
    [item setCollapsed:![item isCollapsed]];
}
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    SEL a = [item action];
    if (a == @selector(toggleSidebar:) || a == @selector(toggleInspector:)) {
        NSSplitViewItem *mine = [self _firstItemWithBehavior:a == @selector(toggleSidebar:)
                                                                   ? NSSplitViewItemBehaviorSidebar
                                                                   : NSSplitViewItemBehaviorInspector];
        if ([(id)item respondsToSelector:@selector(setTitle:)] && [(id)item isKindOfClass:[NSMenuItem class]] && mine)
            [(NSMenuItem *)item setTitle:a == @selector(toggleSidebar:)
                                             ? ([mine isCollapsed] ? @"Show Sidebar" : @"Hide Sidebar")
                                             : ([mine isCollapsed] ? @"Show Inspector" : @"Hide Inspector")];
        return mine != nil;
    }
    return [self respondsToSelector:a];
}

/* ---- the split view's delegate --------------------------------------------------------- */

- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)subview
{
    return [[self _itemForView:subview] canCollapse];
}
/* Divider i lies between panes i and i + 1: it stops where either pane
 * would pass its minimum or maximum thickness. */
- (CGFloat)_edgeOf:(NSInteger)i in:(NSSplitView *)sv start:(BOOL)start
{
    NSView *v = [[sv subviews] objectAtIndex:i];
    NSRect f = [v frame];
    if ([v isHidden])
        return [sv positionOfDividerAtIndex:i];
    if ([sv isVertical])
        return start ? NSMinX(f) : NSMaxX(f);
    return start ? NSMinY(f) : NSMaxY(f);
}
- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i
{
    NSArray *subviews = [sv subviews];
    if (i < 0 || i + 1 >= (NSInteger)[subviews count])
        return p;
    NSSplitViewItem *a = [self _itemForView:[subviews objectAtIndex:i]];
    NSSplitViewItem *b = [self _itemForView:[subviews objectAtIndex:i + 1]];
    CGFloat start = [self _edgeOf:i in:sv start:YES], end = [self _edgeOf:i + 1 in:sv start:NO];
    if ([a _leastThickness] > 0)
        p = fmax(p, start + [a _leastThickness]);
    if ([b maximumThickness] >= 0)
        p = fmax(p, end - [b maximumThickness] - [sv dividerThickness]);
    return p;
}
- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i
{
    NSArray *subviews = [sv subviews];
    if (i < 0 || i + 1 >= (NSInteger)[subviews count])
        return p;
    NSSplitViewItem *a = [self _itemForView:[subviews objectAtIndex:i]];
    NSSplitViewItem *b = [self _itemForView:[subviews objectAtIndex:i + 1]];
    CGFloat start = [self _edgeOf:i in:sv start:YES], end = [self _edgeOf:i + 1 in:sv start:NO];
    if ([a maximumThickness] >= 0)
        p = fmin(p, start + [a maximumThickness]);
    if ([b _leastThickness] > 0)
        p = fmin(p, end - [b _leastThickness] - [sv dividerThickness]);
    return p;
}
/* When the split view changes size, the change goes by holding priority,
 * within the items' limits. */
- (void)splitView:(NSSplitView *)sv resizeSubviewsWithOldSize:(NSSize)old
{
    if (sv == _splitView && _installed)
        [self _shareKeeping:nil];
    else
        [sv adjustSubviews];
}
/* The split view is in a window: the panes are shared out for the first
 * time (NSSplitView.m). */
- (void)_splitViewDidMoveToWindow:(NSSplitView *)sv
{
    if (sv == _splitView && _installed && [sv window])
        [self _shareKeeping:nil];
}
/* A pane the user collapsed by dragging, or opened again, is noted on its item. */
- (void)splitViewDidResizeSubviews:(NSNotification *)note
{
    for (NSView *v in [_splitView subviews])
        [[self _itemForView:v] _noteCollapsed:[v isHidden]];
}
@end
