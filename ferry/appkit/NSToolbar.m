/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: window toolbars (NSToolbar, NSToolbarItem,
 * NSToolbarItemGroup). Ferry's own code, written from Apple's public API
 * documentation. The toolbar is drawn in a strip at the top of the window,
 * just under the title bar the compositor draws and in the same colour, so
 * the two read as one, as a current Mac's unified title bar and toolbar
 * do; the strip, its buttons and the standard items' icons are drawn with
 * Ferry's own code (no Apple artwork).
 *
 * The items come from the delegate (toolbarDefaultItemIdentifiers: and
 * toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:), or from a
 * nib, the first time they are needed, so that a nib's delegate outlet is
 * connected by then. Spaces, flexible spaces and the standard items are
 * the toolbar's own. Items are laid out from the left: flexible spaces and
 * items whose view may grow share the room left over; when there isn't
 * room, the items of lowest visibility priority go into a menu behind a
 * chevron at the end. Items are validated each time round the event loop
 * (validateToolbarItem:, or whether anything takes their action). With
 * autosavesConfiguration, the items, the display mode and whether the
 * toolbar shows are kept in the user defaults ("NSToolbar Configuration"
 * and the identifier). There is no customization sheet.
 *
 * The nib keys read here ("NSToolbarIdentifier", "NSToolbarDelegate",
 * "NSToolbarDisplayMode", "NSToolbarSizeMode", "NSToolbarPrefersToBeShown",
 * "NSToolbarShowsBaselineSeparator", "NSToolbarAllowsUserCustomization",
 * "NSToolbarAutosavesConfiguration", "NSToolbarIBDefaultItems",
 * "NSToolbarIBAllowedItems", "NSToolbarIBIdentifiedItems",
 * "NSToolbarIBSelectableItems", and the "NSToolbarItem..." keys of an
 * item) are the names given in descriptions of the format published by
 * developers and by the GNUstep project; no Apple code was read. A nib
 * that names them differently loads with the defaults. */
#import "AInternal.h"

NSToolbarItemIdentifier const NSToolbarSpaceItemIdentifier = @"NSToolbarSpaceItem";
NSToolbarItemIdentifier const NSToolbarFlexibleSpaceItemIdentifier = @"NSToolbarFlexibleSpaceItem";
NSToolbarItemIdentifier const NSToolbarSeparatorItemIdentifier = @"NSToolbarSeparatorItem";
NSToolbarItemIdentifier const NSToolbarShowColorsItemIdentifier = @"NSToolbarShowColorsItem";
NSToolbarItemIdentifier const NSToolbarShowFontsItemIdentifier = @"NSToolbarShowFontsItem";
NSToolbarItemIdentifier const NSToolbarCustomizeToolbarItemIdentifier = @"NSToolbarCustomizeToolbarItem";
NSToolbarItemIdentifier const NSToolbarPrintItemIdentifier = @"NSToolbarPrintItem";
NSToolbarItemIdentifier const NSToolbarToggleSidebarItemIdentifier = @"NSToolbarToggleSidebarItem";
NSToolbarItemIdentifier const NSToolbarCloudSharingItemIdentifier = @"NSToolbarCloudSharingItem";
NSToolbarItemIdentifier const NSToolbarSidebarTrackingSeparatorItemIdentifier =
    @"NSToolbarSidebarTrackingSeparatorItemIdentifier";
NSNotificationName const NSToolbarWillAddItemNotification = @"NSToolbarWillAddItemNotification";
NSNotificationName const NSToolbarDidRemoveItemNotification = @"NSToolbarDidRemoveItemNotification";

static id coded(NSCoder *c, NSString *key, Class cls)
{
    id v = [c containsValueForKey:key] ? [c decodeObjectForKey:key] : nil;
    return [v isKindOfClass:cls] ? v : nil;
}

static BOOL is_space(NSString *ident)
{
    return [ident isEqualToString:NSToolbarSpaceItemIdentifier] ||
           [ident isEqualToString:NSToolbarFlexibleSpaceItemIdentifier] ||
           [ident isEqualToString:NSToolbarSeparatorItemIdentifier] ||
           [ident isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier];
}

@interface NSToolbar ()
- (void)_itemChanged:(NSToolbarItem *)item;
- (NSToolbarDisplayMode)_mode;
- (BOOL)_small;
- (BOOL)_isSelectable:(NSString *)identifier;
@end
@interface NSToolbarItem ()
- (void)_changed;
- (void)_setToolbar:(NSToolbar *)toolbar;
- (void)_setVisible:(BOOL)visible;
@end

/* ---- NSToolbarItem -------------------------------------------------------------------- */

@implementation NSToolbarItem {
    NSString *_identifier, *_label, *_paletteLabel, *_toolTip, *_title;
    NSToolbar *_toolbar;
    NSMenuItem *_menuForm;
    NSInteger _tag;
    id _target;
    SEL _action;
    BOOL _enabled, _autovalidates, _bordered, _navigational, _visible;
    NSImage *_image;
    NSView *_view;
    NSSize _minSize, _maxSize;
    NSToolbarItemVisibilityPriority _priority;
}

- (instancetype)init { return [self initWithItemIdentifier:@""]; }
- (instancetype)initWithItemIdentifier:(NSToolbarItemIdentifier)identifier
{
    if ((self = [super init])) {
        _identifier = [identifier ?: @"" copy];
        _label = @"";
        _paletteLabel = @"";
        _title = @"";
        _enabled = YES;
        _autovalidates = YES;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [self initWithItemIdentifier:coded(c, @"NSToolbarItemIdentifier", [NSString class])]))
        return nil;
    NSString *s;
    if ((s = coded(c, @"NSToolbarItemLabel", [NSString class])))
        [self setLabel:s];
    if ((s = coded(c, @"NSToolbarItemPaletteLabel", [NSString class])))
        [self setPaletteLabel:s];
    if ((s = coded(c, @"NSToolbarItemToolTip", [NSString class])))
        [self setToolTip:s];
    if ((s = coded(c, @"NSToolbarItemTitle", [NSString class])))
        [self setTitle:s];
    _image = [coded(c, @"NSToolbarItemImage", [NSImage class]) retain];
    _view = [coded(c, @"NSToolbarItemView", [NSView class]) retain];
    _target = [c containsValueForKey:@"NSToolbarItemTarget"] ? [c decodeObjectForKey:@"NSToolbarItemTarget"] : nil;
    if ((s = coded(c, @"NSToolbarItemAction", [NSString class])))
        _action = NSSelectorFromString(s);
    if ([c containsValueForKey:@"NSToolbarItemMinSize"])
        _minSize = [c decodeSizeForKey:@"NSToolbarItemMinSize"];
    if ([c containsValueForKey:@"NSToolbarItemMaxSize"])
        _maxSize = [c decodeSizeForKey:@"NSToolbarItemMaxSize"];
    if ([c containsValueForKey:@"NSToolbarItemEnabled"])
        _enabled = [c decodeBoolForKey:@"NSToolbarItemEnabled"];
    if ([c containsValueForKey:@"NSToolbarItemAutovalidates"])
        _autovalidates = [c decodeBoolForKey:@"NSToolbarItemAutovalidates"];
    _tag = [c decodeIntegerForKey:@"NSToolbarItemTag"];
    _priority = [c decodeIntegerForKey:@"NSToolbarItemVisibilityPriority"];
    _bordered = [c decodeBoolForKey:@"NSToolbarItemBordered"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_identifier forKey:@"NSToolbarItemIdentifier"];
    [c encodeObject:_label forKey:@"NSToolbarItemLabel"];
    [c encodeObject:_paletteLabel forKey:@"NSToolbarItemPaletteLabel"];
    if (_image)
        [c encodeObject:_image forKey:@"NSToolbarItemImage"];
    if (_view)
        [c encodeObject:_view forKey:@"NSToolbarItemView"];
    if (_action)
        [c encodeObject:NSStringFromSelector(_action) forKey:@"NSToolbarItemAction"];
    [c encodeInteger:_tag forKey:@"NSToolbarItemTag"];
}
- (void)dealloc
{
    [_identifier release];
    [_label release];
    [_paletteLabel release];
    [_toolTip release];
    [_title release];
    [_menuForm release];
    [_image release];
    [_view release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSToolbarItem *c = [[[self class] allocWithZone:zone] initWithItemIdentifier:_identifier];
    [c setLabel:_label];
    [c setPaletteLabel:_paletteLabel];
    [c setToolTip:_toolTip];
    [c setTitle:_title];
    [c setMenuFormRepresentation:_menuForm];
    c->_tag = _tag;
    c->_target = _target;
    c->_action = _action;
    c->_enabled = _enabled;
    c->_autovalidates = _autovalidates;
    c->_bordered = _bordered;
    c->_navigational = _navigational;
    [c setImage:_image];
    [c setView:_view];
    c->_minSize = _minSize;
    c->_maxSize = _maxSize;
    c->_priority = _priority;
    return c;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p %@>", [self class], self, _identifier];
}

- (void)_changed { [_toolbar _itemChanged:self]; }
- (NSToolbarItemIdentifier)itemIdentifier { return _identifier; }
- (NSToolbar *)toolbar { return _toolbar; }
- (void)_setToolbar:(NSToolbar *)toolbar { _toolbar = toolbar; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)s
{
    [_label release];
    _label = [s ?: @"" copy];
    [self _changed];
}
- (NSString *)paletteLabel { return [_paletteLabel length] ? _paletteLabel : _label; }
- (void)setPaletteLabel:(NSString *)s
{
    [_paletteLabel release];
    _paletteLabel = [s ?: @"" copy];
}
- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)s
{
    [_toolTip release];
    _toolTip = [s copy];
}
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)s
{
    [_title release];
    _title = [s ?: @"" copy];
    [self _changed];
}
- (NSMenuItem *)menuFormRepresentation { return _menuForm; }
- (void)setMenuFormRepresentation:(NSMenuItem *)m
{
    [m retain];
    [_menuForm release];
    _menuForm = m;
}
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)t { _tag = t; }
/* An item with a control as its view is the control's target and action. */
- (id)target { return [_view respondsToSelector:@selector(target)] ? [(NSControl *)_view target] : _target; }
- (void)setTarget:(id)t
{
    if ([_view respondsToSelector:@selector(setTarget:)])
        [(NSControl *)_view setTarget:t];
    _target = t;
}
- (SEL)action { return [_view respondsToSelector:@selector(action)] ? [(NSControl *)_view action] : _action; }
- (void)setAction:(SEL)a
{
    if ([_view respondsToSelector:@selector(setAction:)])
        [(NSControl *)_view setAction:a];
    _action = a;
}
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)f
{
    if ([_view respondsToSelector:@selector(setEnabled:)])
        [(NSControl *)_view setEnabled:f];
    if (f == _enabled)
        return;
    _enabled = f;
    [self _changed];
}
/* An item with a view and no image of its own answers its view's image,
 * as on a Mac, where a group's segments are often drawn from the images
 * of subitems whose views are buttons. */
- (NSImage *)image
{
    if (_image || !_view || ![_view respondsToSelector:@selector(image)])
        return _image;
    id image = [(id)_view image];
    return [image isKindOfClass:[NSImage class]] ? image : nil;
}
- (void)setImage:(NSImage *)image
{
    [image retain];
    [_image release];
    _image = image;
    [self _changed];
}
- (NSView *)view { return _view; }
- (void)setView:(NSView *)view
{
    if (view == _view)
        return;
    [view retain];
    [_view removeFromSuperview];
    [_view release];
    _view = view;
    [self _changed];
}
- (NSSize)minSize { return _minSize; }
- (void)setMinSize:(NSSize)s
{
    _minSize = s;
    [self _changed];
}
- (NSSize)maxSize { return _maxSize; }
- (void)setMaxSize:(NSSize)s
{
    _maxSize = s;
    [self _changed];
}
- (NSToolbarItemVisibilityPriority)visibilityPriority { return _priority; }
- (void)setVisibilityPriority:(NSToolbarItemVisibilityPriority)p
{
    _priority = p;
    [self _changed];
}
- (BOOL)autovalidates { return _autovalidates; }
- (void)setAutovalidates:(BOOL)f { _autovalidates = f; }
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)f
{
    _bordered = f;
    [self _changed];
}
- (BOOL)isNavigational { return _navigational; }
- (void)setNavigational:(BOOL)f { _navigational = f; }
- (BOOL)allowsDuplicatesInToolbar { return is_space(_identifier); }
- (BOOL)isVisible { return _visible; }
- (void)_setVisible:(BOOL)v { _visible = v; }

/* Enabled when something takes the action and, if it validates toolbar
 * items, says yes. Items with a view, and items without an action, are
 * left as they are. */
- (void)validate
{
    if (_view || !_action)
        return;
    id target = [NSApp targetForAction:_action to:_target from:self];
    BOOL ok = target != nil;
    if (ok && [target respondsToSelector:@selector(validateToolbarItem:)])
        ok = [target validateToolbarItem:self];
    [self setEnabled:ok];
}
@end

@implementation NSToolbarItemGroup {
    NSArray *_subitems;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super initWithCoder:c]))
        _subitems = [coded(c, @"NSToolbarItemGroupSubitems", [NSArray class]) copy];
    return self;
}
- (void)dealloc
{
    [_subitems release];
    [super dealloc];
}
- (NSArray *)subitems { return _subitems ?: @[]; }
- (void)setSubitems:(NSArray *)items
{
    [_subitems release];
    _subitems = [items copy];
    for (NSToolbarItem *i in _subitems)
        [i _setToolbar:[self toolbar]];
    [self _changed];
}
- (void)_setToolbar:(NSToolbar *)toolbar
{
    [super _setToolbar:toolbar];
    for (NSToolbarItem *i in _subitems)
        [i _setToolbar:toolbar];
}
/* The group is enabled as its parts are. */
- (void)validate
{
    for (NSToolbarItem *i in _subitems)
        if ([i autovalidates])
            [i validate];
    [super validate];
}
@end

/* ---- the standard items' icons, drawn here ---------------------------------------------- */

static NSImage *icon(void (^draw)(NSRect))
{
    NSImage *im = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] set];
        draw(r);
        return YES;
    }];
    [im setTemplate:YES];
    return im;
}
static NSImage *standard_icon(NSString *ident)
{
    if ([ident isEqualToString:NSToolbarToggleSidebarItemIdentifier])
        return icon(^(NSRect r) {
            NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 1.5, 3.5) xRadius:2.5 yRadius:2.5];
            [p setLineWidth:1.4];
            [p stroke];
            NSRectFill(NSMakeRect(6.5, 4, 1.2, 10));
        });
    if ([ident isEqualToString:NSToolbarPrintItemIdentifier])
        return icon(^(NSRect r) {
            NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1.5, 5.5, 15, 7) xRadius:2 yRadius:2];
            [body setLineWidth:1.4];
            [body stroke];
            NSBezierPath *paper = [NSBezierPath bezierPathWithRect:NSMakeRect(5, 1.5, 8, 6)];
            [paper setLineWidth:1.2];
            [paper stroke];
            [[NSBezierPath bezierPathWithRect:NSMakeRect(5, 12.5, 8, 4)] stroke];
        });
    if ([ident isEqualToString:NSToolbarShowColorsItemIdentifier])
        return icon(^(NSRect r) {
            NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 2, 2)];
            [p setLineWidth:1.4];
            [p stroke];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5, 9, 3, 3)] fill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(10, 9, 3, 3)] fill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.5, 4.5, 3, 3)] fill];
        });
    if ([ident isEqualToString:NSToolbarShowFontsItemIdentifier])
        return icon(^(NSRect r) {
            NSBezierPath *p = [NSBezierPath bezierPath];
            [p moveToPoint:NSMakePoint(3, 2)];
            [p lineToPoint:NSMakePoint(9, 16)];
            [p lineToPoint:NSMakePoint(15, 2)];
            [p moveToPoint:NSMakePoint(5.5, 7)];
            [p lineToPoint:NSMakePoint(12.5, 7)];
            [p setLineWidth:1.6];
            [p stroke];
        });
    if ([ident isEqualToString:NSToolbarCustomizeToolbarItemIdentifier] ||
        [ident isEqualToString:NSToolbarCloudSharingItemIdentifier])
        return icon(^(NSRect r) {
            for (int i = 0; i < 3; i++) {
                CGFloat y = 4 + i * 5;
                NSRectFill(NSMakeRect(2, y, 14, 1.4));
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(i == 1 ? 10 : 5, y - 1.5, 4, 4)] fill];
            }
        });
    return nil;
}

/* ---- the strip ----------------------------------------------------------------------- */

@class AToolbarView;
/* An item drawn by the toolbar: its image and label, pressed and chosen
 * like a button. */
@interface AToolbarButton : NSView {
@public
    NSToolbarItem *item;      /* assign: the toolbar keeps it */
    AToolbarView *strip;
    BOOL pressed, inside;
}
@end
@interface AToolbarView : NSView <AMenuOwner> {
@public
    NSToolbar *toolbar;       /* assign: the toolbar outlives its strip's use */
    BOOL tiled;
    NSMutableArray *buttons;  /* AToolbarButton */
    NSMutableArray *overflow; /* the items that didn't fit */
    NSRect chevron;
    BOOL chevronPressed;
}
- (void)tile;
- (void)invalidate;
@end

/* ---- NSToolbar ----------------------------------------------------------------------- */

@implementation NSToolbar {
    NSString *_identifier;
    id<NSToolbarDelegate> _delegate;
    NSMutableArray *_items;
    NSToolbarDisplayMode _displayMode;
    NSToolbarSizeMode _sizeMode;
    BOOL _visible, _baseline, _customizable, _autosaves, _extensions, _loaded, _warned;
    NSString *_selected, *_centered;
    NSWindow *_window;
    AToolbarView *_view;
    NSArray *_nibDefault, *_nibAllowed, *_nibSelectable;
    NSDictionary *_nibItems;
}

- (instancetype)init { return [self initWithIdentifier:@""]; }
- (instancetype)initWithIdentifier:(NSToolbarIdentifier)identifier
{
    if ((self = [super init])) {
        _identifier = [identifier ?: @"" copy];
        _items = [[NSMutableArray alloc] init];
        _visible = YES;
        _baseline = YES;
    }
    return self;
}
static NSArray *identifiers_of(NSArray *items)
{
    NSMutableArray *a = [NSMutableArray array];
    for (id i in items) {
        if ([i isKindOfClass:[NSToolbarItem class]])
            [a addObject:[i itemIdentifier]];
        else if ([i isKindOfClass:[NSString class]])
            [a addObject:i];
    }
    return a;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [self initWithIdentifier:coded(c, @"NSToolbarIdentifier", [NSString class])]))
        return nil;
    _delegate = [c containsValueForKey:@"NSToolbarDelegate"] ? [c decodeObjectForKey:@"NSToolbarDelegate"] : nil;
    _displayMode = [c decodeIntegerForKey:@"NSToolbarDisplayMode"];
    _sizeMode = [c decodeIntegerForKey:@"NSToolbarSizeMode"];
    if ([c containsValueForKey:@"NSToolbarPrefersToBeShown"])
        _visible = [c decodeBoolForKey:@"NSToolbarPrefersToBeShown"];
    if ([c containsValueForKey:@"NSToolbarShowsBaselineSeparator"])
        _baseline = [c decodeBoolForKey:@"NSToolbarShowsBaselineSeparator"];
    _customizable = [c decodeBoolForKey:@"NSToolbarAllowsUserCustomization"];
    _autosaves = [c decodeBoolForKey:@"NSToolbarAutosavesConfiguration"];
    NSArray *def = coded(c, @"NSToolbarIBDefaultItems", [NSArray class]);
    NSArray *allowed = coded(c, @"NSToolbarIBAllowedItems", [NSArray class]);
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    NSDictionary *ided = coded(c, @"NSToolbarIBIdentifiedItems", [NSDictionary class]);
    for (id key in ided)
        if ([ided[key] isKindOfClass:[NSToolbarItem class]])
            byId[key] = ided[key];
    for (NSArray *list in @[ def ?: @[], allowed ?: @[] ])
        for (NSToolbarItem *i in list)
            if ([i isKindOfClass:[NSToolbarItem class]] && !byId[[i itemIdentifier]])
                byId[[i itemIdentifier]] = i;
    _nibItems = [byId copy];
    _nibDefault = def ? [identifiers_of(def) copy] : nil;
    _nibAllowed = allowed ? [identifiers_of(allowed) copy] : nil;
    NSArray *sel = coded(c, @"NSToolbarIBSelectableItems", [NSArray class]);
    _nibSelectable = sel ? [identifiers_of(sel) copy] : nil;
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_identifier forKey:@"NSToolbarIdentifier"];
    [c encodeInteger:_displayMode forKey:@"NSToolbarDisplayMode"];
    [c encodeInteger:_sizeMode forKey:@"NSToolbarSizeMode"];
    [c encodeBool:_visible forKey:@"NSToolbarPrefersToBeShown"];
    [c encodeBool:_baseline forKey:@"NSToolbarShowsBaselineSeparator"];
}
- (void)dealloc
{
    for (NSToolbarItem *i in _items)
        [i _setToolbar:nil];
    if (_view)
        _view->toolbar = nil;
    [_identifier release];
    [_items release];
    [_selected release];
    [_centered release];
    [_nibDefault release];
    [_nibAllowed release];
    [_nibSelectable release];
    [_nibItems release];
    [super dealloc];
}

- (NSToolbarIdentifier)identifier { return _identifier; }
- (id<NSToolbarDelegate>)delegate { return _delegate; }
/* A toolbar that found no items before it had a delegate asks again. */
- (void)setDelegate:(id<NSToolbarDelegate>)d
{
    _delegate = d;
    if (_loaded && ![_items count] && d) {
        _loaded = NO;
        [_view invalidate];
    }
}

/* ---- making items ---- */

- (NSToolbarItem *)_standardItem:(NSString *)ident
{
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:ident] autorelease];
    struct { NSString *ident, *label; SEL action; } table[] = {
        {NSToolbarShowColorsItemIdentifier, @"Colors", @selector(orderFrontColorPanel:)},
        {NSToolbarShowFontsItemIdentifier, @"Fonts", @selector(orderFrontFontPanel:)},
        {NSToolbarCustomizeToolbarItemIdentifier, @"Customize", @selector(runToolbarCustomizationPalette:)},
        {NSToolbarPrintItemIdentifier, @"Print", @selector(print:)},
        {NSToolbarToggleSidebarItemIdentifier, @"Sidebar", @selector(toggleSidebar:)},
        {NSToolbarCloudSharingItemIdentifier, @"Share", NULL},
    };
    for (size_t i = 0; i < sizeof table / sizeof *table; i++)
        if ([ident isEqualToString:table[i].ident]) {
            [item setLabel:table[i].label];
            [item setPaletteLabel:table[i].label];
            [item setAction:table[i].action];
            /* Show Fonts goes to the font manager, as on a Mac */
            if ([ident isEqualToString:NSToolbarShowFontsItemIdentifier])
                [item setTarget:[NSFontManager sharedFontManager]];
            [item setImage:standard_icon(ident)];
            return item;
        }
    if ([ident isEqualToString:NSToolbarSpaceItemIdentifier])
        [item setPaletteLabel:@"Space"];
    else if ([ident isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
        [item setPaletteLabel:@"Flexible Space"];
    else if ([ident isEqualToString:NSToolbarSeparatorItemIdentifier])
        [item setPaletteLabel:@"Separator"];
    else if (![ident isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier])
        return nil;
    return item;
}

- (BOOL)_isStandard:(NSString *)ident
{
    return is_space(ident) || [ident hasPrefix:@"NSToolbar"];
}

/* An item for an identifier: the nib's, the toolbar's own standard one,
 * or the delegate's. */
- (NSToolbarItem *)_itemFor:(NSString *)ident
{
    NSToolbarItem *item = _nibItems[ident];
    if (item) {
        if ([_items indexOfObjectIdenticalTo:item] != NSNotFound)
            item = [[item copy] autorelease];
        /* a standard item from a nib: what the nib leaves out is the standard one's */
        NSToolbarItem *standard = [self _isStandard:ident] ? [self _standardItem:ident] : nil;
        if (standard && ![item image] && ![item view])
            [item setImage:[standard image]];
        if (standard && ![item action] && ![item view])
            [item setAction:[standard action]];
        if (standard && ![[item label] length])
            [item setLabel:[standard label]];
    } else if ([self _isStandard:ident] && (item = [self _standardItem:ident])) {
    } else if ([_delegate respondsToSelector:@selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:)]) {
        item = [_delegate toolbar:self itemForItemIdentifier:ident willBeInsertedIntoToolbar:YES];
    }
    return item;
}

- (void)_insertItem:(NSToolbarItem *)item atIndex:(NSInteger)index
{
    NSNotification *n = [NSNotification notificationWithName:NSToolbarWillAddItemNotification object:self
                                                     userInfo:@{@"item" : item}];
    if ([_delegate respondsToSelector:@selector(toolbarWillAddItem:)])
        [_delegate toolbarWillAddItem:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
    if (index < 0 || index > (NSInteger)[_items count])
        index = (NSInteger)[_items count];
    [_items insertObject:item atIndex:(NSUInteger)index];
    [item _setToolbar:self];
}

- (NSString *)_defaultsKey { return [@"NSToolbar Configuration " stringByAppendingString:_identifier]; }

- (NSArray *)_defaultIdentifiers
{
    if ([_delegate respondsToSelector:@selector(toolbarDefaultItemIdentifiers:)])
        return [_delegate toolbarDefaultItemIdentifiers:self];
    return _nibDefault ?: @[];
}

- (void)_ensureItems
{
    if (_loaded)
        return;
    _loaded = YES;
    NSArray *ids = [self _defaultIdentifiers];
    if (_autosaves && [_identifier length]) {
        NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[self _defaultsKey]];
        if (saved)
            [self _applyConfiguration:saved];
        NSArray *savedIds = saved[@"TB Item Identifiers"];
        if ([savedIds isKindOfClass:[NSArray class]])
            ids = savedIds;
    }
    for (NSString *ident in ids) {
        NSToolbarItem *item = [self _itemFor:ident];
        if (item)
            [self _insertItem:item atIndex:(NSInteger)[_items count]];
    }
}

- (NSArray *)items
{
    [self _ensureItems];
    return [[_items copy] autorelease];
}
- (NSArray *)visibleItems
{
    [self _ensureItems];
    [_view tile];
    NSMutableArray *a = [NSMutableArray array];
    for (NSToolbarItem *i in _items)
        if ([i isVisible])
            [a addObject:i];
    return a;
}

- (void)_save
{
    if (!_autosaves || ![_identifier length] || !_loaded)
        return;
    [[NSUserDefaults standardUserDefaults] setObject:[self configurationDictionary] forKey:[self _defaultsKey]];
}
- (void)_itemChanged:(NSToolbarItem *)item
{
    [_view invalidate];
}
- (void)_layoutChanged
{
    [_window _toolbarLayoutChanged];
    [_view invalidate];
}

- (void)insertItemWithItemIdentifier:(NSToolbarItemIdentifier)identifier atIndex:(NSInteger)index
{
    [self _ensureItems];
    NSToolbarItem *item = [self _itemFor:identifier];
    if (!item)
        return;
    [self _insertItem:item atIndex:index];
    [_view invalidate];
    [self _save];
}
- (void)removeItemAtIndex:(NSInteger)index
{
    [self _ensureItems];
    if (index < 0 || index >= (NSInteger)[_items count])
        return;
    NSToolbarItem *item = [[_items[(NSUInteger)index] retain] autorelease];
    [_items removeObjectAtIndex:(NSUInteger)index];
    [[item view] removeFromSuperview];
    [item _setToolbar:nil];
    [item _setVisible:NO];
    NSNotification *n = [NSNotification notificationWithName:NSToolbarDidRemoveItemNotification object:self
                                                     userInfo:@{@"item" : item}];
    if ([_delegate respondsToSelector:@selector(toolbarDidRemoveItem:)])
        [_delegate toolbarDidRemoveItem:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
    [_view invalidate];
    [self _save];
}

/* ---- settings ---- */

- (NSToolbarDisplayMode)displayMode { return _displayMode; }
- (void)setDisplayMode:(NSToolbarDisplayMode)m
{
    _displayMode = m;
    [self _layoutChanged];
    [self _save];
}
- (NSToolbarSizeMode)sizeMode { return _sizeMode; }
- (void)setSizeMode:(NSToolbarSizeMode)m
{
    _sizeMode = m;
    [self _layoutChanged];
    [self _save];
}
- (BOOL)isVisible { return _visible; }
- (void)setVisible:(BOOL)f
{
    if (f == _visible)
        return;
    _visible = f;
    [self _layoutChanged];
    [self _save];
}
- (BOOL)showsBaselineSeparator { return _baseline; }
- (void)setShowsBaselineSeparator:(BOOL)f
{
    _baseline = f;
    [_view setNeedsDisplay:YES];
}
- (BOOL)allowsUserCustomization { return _customizable; }
- (void)setAllowsUserCustomization:(BOOL)f { _customizable = f; }
- (BOOL)autosavesConfiguration { return _autosaves; }
- (void)setAutosavesConfiguration:(BOOL)f
{
    _autosaves = f;
    [self _save];
}
- (BOOL)allowsExtensionItems { return _extensions; }
- (void)setAllowsExtensionItems:(BOOL)f { _extensions = f; }
- (NSToolbarItemIdentifier)selectedItemIdentifier { return _selected; }
- (void)setSelectedItemIdentifier:(NSToolbarItemIdentifier)ident
{
    [_selected release];
    _selected = [ident copy];
    [_view setNeedsDisplay:YES];
    for (NSView *b in [_view subviews])
        [b setNeedsDisplay:YES];
}
- (NSToolbarItemIdentifier)centeredItemIdentifier { return _centered; }
- (void)setCenteredItemIdentifier:(NSToolbarItemIdentifier)ident
{
    [_centered release];
    _centered = [ident copy];
    [_view invalidate];
}
- (BOOL)customizationPaletteIsRunning { return NO; }
- (void)runCustomizationPalette:(id)sender
{
    if (!_warned) {
        _warned = YES;
        AWarnOnce("-[NSToolbar runCustomizationPalette:] (Ferry has no customization sheet)");
    }
}

- (BOOL)_isSelectable:(NSString *)ident
{
    NSArray *sel = [_delegate respondsToSelector:@selector(toolbarSelectableItemIdentifiers:)]
                       ? [_delegate toolbarSelectableItemIdentifiers:self]
                       : _nibSelectable;
    return [sel containsObject:ident];
}

- (NSDictionary *)configurationDictionary
{
    [self _ensureItems];
    return @{
        @"TB Item Identifiers" : identifiers_of(_items),
        @"TB Display Mode" : @(_displayMode),
        @"TB Size Mode" : @(_sizeMode),
        @"TB Is Shown" : @(_visible),
    };
}
- (void)_applyConfiguration:(NSDictionary *)d
{
    if ([d[@"TB Display Mode"] respondsToSelector:@selector(integerValue)])
        _displayMode = [d[@"TB Display Mode"] integerValue];
    if ([d[@"TB Size Mode"] respondsToSelector:@selector(integerValue)])
        _sizeMode = [d[@"TB Size Mode"] integerValue];
    if ([d[@"TB Is Shown"] respondsToSelector:@selector(boolValue)])
        _visible = [d[@"TB Is Shown"] boolValue];
}
- (void)setConfigurationFromDictionary:(NSDictionary *)d
{
    _loaded = YES;
    [self _applyConfiguration:d];
    NSArray *ids = d[@"TB Item Identifiers"];
    if ([ids isKindOfClass:[NSArray class]]) {
        while ([_items count])
            [self removeItemAtIndex:(NSInteger)[_items count] - 1];
        for (NSString *ident in ids) {
            NSToolbarItem *item = [self _itemFor:ident];
            if (item)
                [self _insertItem:item atIndex:(NSInteger)[_items count]];
        }
    }
    [self _layoutChanged];
    [self _save];
}

/* Each item that validates itself, when the toolbar shows. */
- (void)validateVisibleItems
{
    if (!_visible || !_window)
        return;
    for (NSToolbarItem *i in [self visibleItems])
        if ([i autovalidates])
            [i validate];
}

/* ---- the window's strip ---- */

- (void)_setWindow:(NSWindow *)w
{
    _window = w;
    if (!w && _view) {
        _view->toolbar = nil;
        _view = nil;
    }
}
- (NSWindow *)_window { return _window; }
- (NSToolbarDisplayMode)_mode { return _displayMode == NSToolbarDisplayModeDefault ? NSToolbarDisplayModeIconOnly : _displayMode; }
- (BOOL)_small { return _sizeMode == NSToolbarSizeModeSmall; }
- (CGFloat)_height
{
    if (!_visible)
        return 0;
    BOOL small = [self _small];
    switch ([self _mode]) {
    case NSToolbarDisplayModeIconAndLabel:
        return small ? 46 : 54;
    case NSToolbarDisplayModeLabelOnly:
        return small ? 26 : 32;
    default:
        return small ? 32 : 38;
    }
}
- (NSView *)_makeView
{
    if (_view)
        _view->toolbar = nil;
    _view = [[[AToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 100, [self _height])] autorelease];
    _view->toolbar = self;
    return _view;
}
@end

/* ---- the strip and its buttons ---------------------------------------------------------- */

enum { TB_PAD = 8, TB_GAP = 6, TB_SPACE = 16, TB_FLEX_MIN = 8, TB_SEPARATOR = 12, TB_CHEVRON = 22 };

static NSFont *label_font(NSToolbar *t) { return [NSFont systemFontOfSize:[t _small] ? 10 : 11]; }

@implementation AToolbarButton
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSRect)_iconBox
{
    NSToolbar *t = strip ? strip->toolbar : nil;
    NSToolbarDisplayMode mode = [t _mode];
    CGFloat side = [t _small] ? 24 : 28;
    NSRect b = [self bounds];
    if (mode == NSToolbarDisplayModeLabelOnly)
        return NSInsetRect(b, 0, 3);
    CGFloat y = mode == NSToolbarDisplayModeIconAndLabel ? 4 : round(NSMidY(b) - side / 2);
    CGFloat w = fmax(side + 4, fmin(b.size.width, side + 12));
    return NSMakeRect(round(NSMidX(b) - w / 2), y, w, side);
}
- (void)mouseDown:(NSEvent *)e
{
    if (![item isEnabled])
        return;
    pressed = inside = YES;
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)e
{
    if (!pressed)
        return;
    BOOL now = NSPointInRect([self convertPoint:[e locationInWindow] fromView:nil], [self bounds]);
    if (now != inside) {
        inside = now;
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseUp:(NSEvent *)e
{
    if (!pressed)
        return;
    pressed = NO;
    [self setNeedsDisplay:YES];
    if (!NSPointInRect([self convertPoint:[e locationInWindow] fromView:nil], [self bounds]))
        return;
    NSToolbarItem *it = [[item retain] autorelease];
    NSToolbar *t = [it toolbar];
    if ([t _isSelectable:[it itemIdentifier]])
        [t setSelectedItemIdentifier:[it itemIdentifier]];
    if ([it action])
        [NSApp sendAction:[it action] to:[it target] from:it];
}
- (void)drawRect:(NSRect)dirty
{
    NSToolbar *t = strip ? strip->toolbar : nil;
    NSToolbarDisplayMode mode = [t _mode];
    BOOL enabled = [item isEnabled];
    BOOL selected = [[t selectedItemIdentifier] isEqualToString:[item itemIdentifier]];
    NSRect box = [self _iconBox];
    if ([item isBordered])
        AFillRoundedRect(NSInsetRect(box, 0, 1), 6, [NSColor colorWithWhite:1 alpha:0.9],
                         [NSColor colorWithWhite:0 alpha:0.12]);
    if ((pressed && inside) || selected)
        AFillRoundedRect(NSInsetRect(box, 0, 1), 6, [NSColor colorWithWhite:0 alpha:pressed && inside ? 0.14 : 0.08],
                         nil);
    NSColor *ink = [NSColor colorWithWhite:0 alpha:enabled ? 0.62 : 0.25];
    if (mode != NSToolbarDisplayModeLabelOnly && [item image]) {
        NSSize s = [[item image] size];
        CGFloat max = [t _small] ? 16 : 20;
        CGFloat k = fmin(1, fmin(max / fmax(s.width, 1), max / fmax(s.height, 1)));
        NSRect ir = NSMakeRect(round(NSMidX(box) - s.width * k / 2), round(NSMidY(box) - s.height * k / 2),
                               s.width * k, s.height * k);
        [[item image] _drawInControlRect:ir color:ink fraction:enabled ? 1 : 0.4];
    }
    if (mode != NSToolbarDisplayModeIconOnly && [[item label] length]) {
        NSAttributedString *l = AAttributed([item label], label_font(t),
                                            [NSColor colorWithWhite:0 alpha:enabled ? 0.75 : 0.3]);
        CGFloat a, d;
        NSSize s = ALineSize(l, &a, &d);
        NSRect b = [self bounds];
        CGFloat base = mode == NSToolbarDisplayModeLabelOnly ? ceil(NSMidY(b) + (a + d) / 2 - d)
                                                              : NSMaxY(box) + 2 + ceil(a);
        ADrawLine(l, round(NSMidX(b) - s.width / 2), base);
    }
}
@end

@implementation AToolbarView
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        buttons = [[NSMutableArray alloc] init];
        overflow = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [buttons release];
    [overflow release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)invalidate
{
    tiled = NO;
    [self setNeedsDisplay:YES];
}
- (void)setFrameSize:(NSSize)size
{
    BOOL same = NSEqualSizes(size, [self frame].size);
    [super setFrameSize:size];
    if (!same)
        tiled = NO;
}

/* The size a view item asks for. A view laid out by frame, in an item
 * given no maximum size, keeps the size it was made at, as on a Mac (a
 * toolbar button made 37 points wide is 37 wide whatever its image);
 * otherwise the view's fitting size. */
static NSSize view_size(NSToolbarItem *item, NSView *v)
{
    NSSize fr = [v frame].size;
    if ([v translatesAutoresizingMaskIntoConstraints] && fr.width > 0 && fr.height > 0 && [item maxSize].width <= 0)
        return fr;
    return [v fittingSize];
}

/* How wide an item is at least, and at most (a flexible one can grow). */
- (void)_widthOf:(NSToolbarItem *)item min:(CGFloat *)min max:(CGFloat *)max
{
    NSString *ident = [item itemIdentifier];
    NSToolbarDisplayMode mode = [toolbar _mode];
    CGFloat side = [toolbar _small] ? 24 : 28;
    if ([ident isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
        *min = TB_FLEX_MIN;
        *max = 1e6;
        return;
    }
    if ([ident isEqualToString:NSToolbarSpaceItemIdentifier]) {
        *min = *max = TB_SPACE;
        return;
    }
    if ([ident isEqualToString:NSToolbarSeparatorItemIdentifier]) {
        *min = *max = TB_SEPARATOR;
        return;
    }
    if ([ident isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier]) {
        *min = *max = 0;
        return;
    }
    CGFloat label = 0;
    if (mode != NSToolbarDisplayModeIconOnly && [[item label] length])
        label = ceil(ALineSize(AAttributed([item label], label_font(toolbar), nil), NULL, NULL).width) + 8;
    NSView *v = [item view];
    if (v) {
        NSSize mn = [item minSize], mx = [item maxSize];
        NSSize f = view_size(item, v);
        CGFloat w = mn.width > 0 ? mn.width : f.width;
        *min = fmax(w, label);
        *max = mx.width > *min ? mx.width : *min;
        return;
    }
    CGFloat w = mode == NSToolbarDisplayModeLabelOnly ? label + 8 : fmax(side + 8, label);
    if ([item minSize].width > w)
        w = [item minSize].width;
    *min = *max = w;
}

/* The items in a row: groups without a view of their own show their parts. */
- (NSArray *)_flatItems
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSToolbarItem *i in [toolbar items]) {
        if ([i isKindOfClass:[NSToolbarItemGroup class]] && ![i view] && [[(NSToolbarItemGroup *)i subitems] count]) {
            [i _setVisible:YES];
            [a addObjectsFromArray:[(NSToolbarItemGroup *)i subitems]];
        } else {
            [a addObject:i];
        }
    }
    return a;
}

- (void)tile
{
    if (tiled || !toolbar)
        return;
    tiled = YES;
    NSArray<NSToolbarItem *> *items = [self _flatItems];
    NSUInteger n = [items count];
    CGFloat mins[n ? n : 1], maxs[n ? n : 1], widths[n ? n : 1];
    BOOL shown[n ? n : 1];
    CGFloat room = [self bounds].size.width - 2 * TB_PAD, total = 0;
    for (NSUInteger i = 0; i < n; i++) {
        [self _widthOf:items[i] min:&mins[i] max:&maxs[i]];
        shown[i] = YES;
        total += mins[i] + (i ? TB_GAP : 0);
    }
    /* too many: the lowest priority (the rightmost of equals) goes first,
     * and a chevron at the end shows a menu of them */
    [overflow removeAllObjects];
    if (total > room) {
        room -= TB_CHEVRON + TB_GAP;
        while (total > room) {
            NSInteger worst = -1;
            for (NSInteger i = (NSInteger)n - 1; i >= 0; i--)
                if (shown[i] && (worst < 0 || [items[i] visibilityPriority] < [items[worst] visibilityPriority]))
                    worst = i;
            if (worst < 0)
                break;
            shown[worst] = NO;
            total -= mins[worst] + TB_GAP;
        }
        for (NSUInteger i = 0; i < n; i++)
            if (!shown[i] && !is_space([items[i] itemIdentifier]))
                [overflow addObject:items[i]];
    }
    /* the room left over: to the views that may grow, up to their most,
     * then to the flexible spaces */
    CGFloat extra = fmax(room - total, 0);
    for (NSUInteger i = 0; i < n; i++)
        widths[i] = mins[i];
    NSUInteger grow = 0, flex = 0;
    for (NSUInteger i = 0; i < n; i++)
        if (shown[i] && maxs[i] > mins[i]) {
            if ([[items[i] itemIdentifier] isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
                flex++;
            else
                grow++;
        }
    for (int pass = 0; pass < 4 && extra > 0.5 && grow; pass++) {
        NSUInteger open = 0;
        for (NSUInteger i = 0; i < n; i++)
            if (shown[i] && widths[i] < maxs[i] &&
                ![[items[i] itemIdentifier] isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
                open++;
        if (!open)
            break;
        CGFloat each = extra / open;
        for (NSUInteger i = 0; i < n; i++)
            if (shown[i] && widths[i] < maxs[i] &&
                ![[items[i] itemIdentifier] isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
                CGFloat add = fmin(each, maxs[i] - widths[i]);
                widths[i] += add;
                extra -= add;
            }
    }
    if (flex && extra > 0)
        for (NSUInteger i = 0; i < n; i++)
            if (shown[i] && [[items[i] itemIdentifier] isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
                widths[i] += extra / flex;

    /* place them, with buttons for the items drawn here (the same button
     * for an item as before, so that one being pressed stays) */
    NSMutableArray *old = [buttons mutableCopy];
    [buttons removeAllObjects];
    NSToolbarDisplayMode mode = [toolbar _mode];
    CGFloat h = [self bounds].size.height, side = [toolbar _small] ? 24 : 28;
    CGFloat x = TB_PAD;
    for (NSUInteger i = 0; i < n; i++) {
        NSToolbarItem *item = items[i];
        [item _setVisible:shown[i]];
        NSView *v = [item view];
        if (!shown[i]) {
            [v removeFromSuperview];
            continue;
        }
        NSRect slot = NSMakeRect(round(x), 0, round(x + widths[i]) - round(x), h);
        x += widths[i] + TB_GAP;
        if (is_space([item itemIdentifier]))
            continue;
        if (v) {
            NSSize f = view_size(item, v);
            CGFloat vh = fmin(f.height > 0 ? f.height : side, mode == NSToolbarDisplayModeIconAndLabel ? side + 4 : h - 4);
            CGFloat top = mode == NSToolbarDisplayModeIconAndLabel ? 4 + round((side - vh) / 2) : round((h - vh) / 2);
            [v setFrame:NSMakeRect(slot.origin.x, top, slot.size.width, vh)];
            if ([v superview] != self)
                [self addSubview:v];
            continue;
        }
        AToolbarButton *b = nil;
        for (AToolbarButton *o in old)
            if (o->item == item) {
                b = [o retain];
                [old removeObjectIdenticalTo:o];
                break;
            }
        if (b)
            [b setFrame:slot];
        else
            b = [[AToolbarButton alloc] initWithFrame:slot];
        b->item = item;
        b->strip = self;
        if ([b superview] != self)
            [self addSubview:b];
        [b setNeedsDisplay:YES];
        [buttons addObject:b];
        [b release];
    }
    for (AToolbarButton *b in old)
        [b removeFromSuperview];
    [old release];
    chevron = [overflow count] ? NSMakeRect([self bounds].size.width - TB_PAD - TB_CHEVRON, round(h / 2 - 11),
                                            TB_CHEVRON, 22)
                               : NSZeroRect;
    [self setNeedsDisplay:YES];
}

- (void)_drawContentInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen
{
    [self tile];
    [super _drawContentInContext:ctx dirty:dirty screen:screen];
}
- (NSView *)hitTest:(NSPoint)p
{
    [self tile];
    return [super hitTest:p];
}

/* The same colour as the compositor's title bar (lighter when the window
 * isn't the key one), and a line under it. */
- (void)drawRect:(NSRect)dirty
{
    BOOL key = [[self window] isKeyWindow];
    [[NSColor colorWithSRGBRed:key ? 0xE9 / 255.0 : 0xF5 / 255.0 green:key ? 0xE9 / 255.0 : 0xF5 / 255.0
                          blue:key ? 0xEC / 255.0 : 0xF7 / 255.0 alpha:1] setFill];
    NSRectFill([self bounds]);
    NSRect b = [self bounds];
    if ([toolbar showsBaselineSeparator]) {
        [[NSColor colorWithWhite:0 alpha:0.11] setFill];
        NSRectFill(NSMakeRect(0, NSMaxY(b) - 1, b.size.width, 1));
    }
    NSToolbarDisplayMode mode = [toolbar _mode];
    CGFloat side = [toolbar _small] ? 24 : 28;
    for (NSToolbarItem *item in [self _flatItems]) {
        if (![item isVisible])
            continue;
        NSView *v = [item view];
        if ([[item itemIdentifier] isEqualToString:NSToolbarSeparatorItemIdentifier]) {
            continue;
        }
        /* the label under an item with a view */
        if (v && mode == NSToolbarDisplayModeIconAndLabel && [[item label] length]) {
            NSAttributedString *l = AAttributed([item label], label_font(toolbar),
                                                [NSColor colorWithWhite:0 alpha:[item isEnabled] ? 0.75 : 0.3]);
            CGFloat a, d;
            NSSize s = ALineSize(l, &a, &d);
            NSRect f = [v frame];
            ADrawLine(l, round(NSMidX(f) - s.width / 2), 4 + side + 2 + ceil(a));
        }
    }
    if (!NSIsEmptyRect(chevron)) {
        if (chevronPressed)
            AFillRoundedRect(chevron, 6, [NSColor colorWithWhite:0 alpha:0.14], nil);
        NSBezierPath *p = [NSBezierPath bezierPath];
        CGFloat cx = NSMidX(chevron), cy = NSMidY(chevron);
        for (int k = 0; k < 2; k++) {
            CGFloat dx = k * 5 - 4;
            [p moveToPoint:NSMakePoint(cx + dx, cy - 4)];
            [p lineToPoint:NSMakePoint(cx + dx + 3.5, cy)];
            [p lineToPoint:NSMakePoint(cx + dx, cy + 4)];
        }
        [p setLineWidth:1.5];
        [p setLineCapStyle:NSLineCapStyleRound];
        [[NSColor colorWithWhite:0 alpha:0.6] setStroke];
        [p stroke];
    }
}

/* The chevron: the items that didn't fit, in a menu. */
- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    if (NSIsEmptyRect(chevron) || !NSPointInRect(p, chevron))
        return;
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [menu setAutoenablesItems:NO];
    for (NSToolbarItem *item in overflow) {
        NSMenuItem *m = [[item menuFormRepresentation] copy];
        if (!m) {
            m = [[NSMenuItem alloc] initWithTitle:[[item label] length] ? [item label] : [item paletteLabel]
                                           action:[item action] keyEquivalent:@""];
            [m setTarget:[item target]];
            [m setImage:[item image]];
        }
        [m setEnabled:[item isEnabled]];
        [m setRepresentedObject:item];
        [menu addItem:m];
        [m release];
    }
    chevronPressed = YES;
    [self setNeedsDisplay:YES];
    [AMenuView openMenu:menu forView:self rect:chevron alignItem:-1 skipFirst:NO font:ADefaultFont() owner:self];
}
- (void)mouseDragged:(NSEvent *)e
{
    NSView *m = [[self window] _overlayView];
    if ([m isKindOfClass:[AMenuView class]])
        [m mouseDragged:e];
}
- (void)mouseUp:(NSEvent *)e
{
    NSView *m = [[self window] _overlayView];
    if ([m isKindOfClass:[AMenuView class]])
        [m mouseUp:e];
}
- (void)_menuView:(AMenuView *)menu didChooseItem:(NSMenuItem *)m
{
    chevronPressed = NO;
    [self setNeedsDisplay:YES];
    if (!m)
        return;
    NSToolbarItem *item = [m representedObject];
    if ([m action])
        [NSApp sendAction:[m action] to:[m target] from:[item isKindOfClass:[NSToolbarItem class]] ? item : m];
}
@end
