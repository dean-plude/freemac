/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSTabView and NSTabViewItem, written from Apple's public
 * documentation. The tabs are drawn as a row of segments centred on the
 * top edge of a rounded box (or along the bottom or a side), as current
 * Macs draw them; clicking one shows its item's view in the box. In a nib
 * the tab view's subviews hold the selected item's view, which is put back
 * under its item. */
#import "AInternal.h"

static const CGFloat TAB_HEIGHT = 24, TAB_PAD = 22, TAB_MIN = 44;

@implementation NSTabViewItem {
    id _identifier;
    NSString *_label, *_toolTip;
    NSColor *_color;
    NSImage *_image;
    NSView *_view;
    NSViewController *_viewController;
    NSView *_initialFirstResponder;
    NSTabView *_tabView;
}
- (instancetype)init { return [self initWithIdentifier:nil]; }
- (instancetype)initWithIdentifier:(id)identifier
{
    if ((self = [super init])) {
        _identifier = [identifier retain];
        _label = [@"" copy];
    }
    return self;
}
+ (instancetype)tabViewItemWithViewController:(NSViewController *)vc
{
    NSTabViewItem *item = [[[self alloc] initWithIdentifier:nil] autorelease];
    [item setViewController:vc];
    if ([vc title])
        [item setLabel:[vc title]];
    return item;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _identifier = [[coder decodeObjectForKey:@"NSIdentifier"] retain];
        _label = [([coder decodeObjectForKey:@"NSLabel"] ?: @"") copy];
        _toolTip = [[coder decodeObjectForKey:@"NSToolTip"] copy];
        _color = [[coder decodeObjectForKey:@"NSColor"] retain];
        _view = [[coder decodeObjectForKey:@"NSView"] retain];
        _initialFirstResponder = [coder decodeObjectForKey:@"NSFirstResponder"];
        _tabView = [coder decodeObjectForKey:@"NSTabView"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_identifier forKey:@"NSIdentifier"];
    [coder encodeObject:_label forKey:@"NSLabel"];
    [coder encodeObject:_view forKey:@"NSView"];
}
- (void)dealloc
{
    [_identifier release];
    [_label release];
    [_toolTip release];
    [_color release];
    [_image release];
    [_view release];
    [_viewController release];
    [super dealloc];
}
- (id)identifier { return _identifier; }
- (void)setIdentifier:(id)i
{
    [_identifier autorelease];
    _identifier = [i retain];
}
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l
{
    [_label autorelease];
    _label = [(l ?: @"") copy];
    [_tabView setNeedsDisplay:YES];
}
- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)t
{
    [_toolTip autorelease];
    _toolTip = [t copy];
}
- (NSColor *)color { return _color ?: [NSColor controlColor]; }
- (void)setColor:(NSColor *)c
{
    [_color autorelease];
    _color = [c copy];
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)i
{
    [_image autorelease];
    _image = [i retain];
    [_tabView setNeedsDisplay:YES];
}
- (NSView *)view { return _viewController ? [_viewController view] : _view; }
- (void)setView:(NSView *)v
{
    if (v == _view)
        return;
    BOOL shown = _tabView && [_tabView selectedTabViewItem] == self;
    if (shown)
        [_view removeFromSuperview];
    [_view autorelease];
    _view = [v retain];
    if (shown && v) {
        [v setFrame:[_tabView contentRect]];
        [_tabView addSubview:v];
    }
}
- (NSViewController *)viewController { return _viewController; }
- (void)setViewController:(NSViewController *)vc
{
    [_viewController autorelease];
    _viewController = [vc retain];
}
- (NSView *)initialFirstResponder { return _initialFirstResponder; }
- (void)setInitialFirstResponder:(NSView *)v { _initialFirstResponder = v; }
- (NSTabView *)tabView { return _tabView; }
- (void)_setTabView:(NSTabView *)tv { _tabView = tv; }
- (NSTabState)tabState
{
    return _tabView && [_tabView selectedTabViewItem] == self ? NSSelectedTab : NSBackgroundTab;
}
- (NSDictionary *)_labelAttributes
{
    NSFont *font = [_tabView font] ?: [NSFont systemFontOfSize:13];
    return @{NSFontAttributeName : font, NSForegroundColorAttributeName : [NSColor labelColor]};
}
- (NSSize)sizeOfLabel:(BOOL)shouldTruncate
{
    NSSize s = [_label sizeWithAttributes:[self _labelAttributes]];
    if (_image)
        s.width += 16 + 4;
    return NSMakeSize(ceil(s.width), ceil(s.height));
}
- (void)drawLabel:(BOOL)shouldTruncate inRect:(NSRect)rect
{
    NSDictionary *attrs = [self _labelAttributes];
    NSString *text = _label;
    NSSize s = [text sizeWithAttributes:attrs];
    CGFloat room = rect.size.width - (_image ? 20 : 0);
    if (shouldTruncate && s.width > room && [text length] > 1) {
        /* cut the end off and add an ellipsis until it fits */
        NSUInteger n = [text length];
        while (n > 1 && [[[text substringToIndex:n] stringByAppendingString:@"…"] sizeWithAttributes:attrs].width > room)
            n--;
        text = [[text substringToIndex:n] stringByAppendingString:@"…"];
        s = [text sizeWithAttributes:attrs];
    }
    CGFloat x = NSMinX(rect);
    if (_image) {
        [_image drawInRect:NSMakeRect(x, NSMidY(rect) - 8, 16, 16) fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        x += 20;
    }
    [text drawAtPoint:NSMakePoint(x, NSMidY(rect) - s.height / 2) withAttributes:attrs];
}
@end

@implementation NSTabView {
    NSMutableArray *_items;
    NSTabViewItem *_selected;
    NSTabViewType _type;
    id _delegate;
    NSFont *_font;
    BOOL _drawsBackground, _truncates;
    NSControlSize _size;
    NSInteger _pressed;
}
- (void)_setUp
{
    _items = [[NSMutableArray alloc] init];
    _drawsBackground = YES;
    _pressed = -1;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setUp];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUp];
        if ([coder containsValueForKey:@"NSTvFlags"]) {
            /* the low bits are the type; bits 27 and 28 the control size */
            unsigned flags = (unsigned)[coder decodeIntForKey:@"NSTvFlags"];
            _type = flags & 7;
            if (_type > NSNoTabsNoBorder)
                _type = NSTopTabsBezelBorder;
            _size = (flags >> 27) & 3;
        }
        if ([coder containsValueForKey:@"NSDrawsBackground"])
            _drawsBackground = [coder decodeBoolForKey:@"NSDrawsBackground"];
        _truncates = [coder decodeBoolForKey:@"NSAllowTruncatedLabels"];
        _font = [[coder decodeObjectForKey:@"NSFont"] retain];
        _delegate = [coder decodeObjectForKey:@"NSDelegate"];
        NSArray *items = [coder decodeObjectForKey:@"NSTabViewItems"];
        /* the nib keeps the selected item's view as a subview: it is the item's */
        for (NSView *v in [[[self subviews] copy] autorelease])
            for (NSTabViewItem *item in items)
                if ([item isKindOfClass:[NSTabViewItem class]] && [item view] == v)
                    [v removeFromSuperview];
        for (NSTabViewItem *item in items)
            if ([item isKindOfClass:[NSTabViewItem class]]) {
                [item _setTabView:self];
                [_items addObject:item];
            }
        NSTabViewItem *sel = [coder decodeObjectForKey:@"NSSelectedTabViewItem"];
        if (![_items containsObject:sel])
            sel = [_items firstObject];
        [self _show:sel];
    }
    return self;
}
- (void)dealloc
{
    for (NSTabViewItem *item in _items)
        [item _setTabView:nil];
    [_items release];
    [_font release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }

/* ---- settings ---------------------------------------------------------------------- */

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSFont *)font
{
    return _font ?: [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:_size]];
}
- (void)setFont:(NSFont *)f
{
    [_font autorelease];
    _font = [f retain];
    [self setNeedsDisplay:YES];
}
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f
{
    _drawsBackground = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)allowsTruncatedLabels { return _truncates; }
- (void)setAllowsTruncatedLabels:(BOOL)f { _truncates = f; }
- (NSControlSize)controlSize { return _size; }
- (void)setControlSize:(NSControlSize)s
{
    _size = s;
    [self _relayOut];
}
- (NSTabViewType)tabViewType { return _type; }
- (void)setTabViewType:(NSTabViewType)t
{
    _type = t;
    [self _relayOut];
}
- (NSTabPosition)tabPosition
{
    switch (_type) {
    case NSTopTabsBezelBorder:
        return NSTabPositionTop;
    case NSLeftTabsBezelBorder:
        return NSTabPositionLeft;
    case NSBottomTabsBezelBorder:
        return NSTabPositionBottom;
    case NSRightTabsBezelBorder:
        return NSTabPositionRight;
    default:
        return NSTabPositionNone;
    }
}
- (void)setTabPosition:(NSTabPosition)p
{
    static const NSTabViewType types[] = {NSNoTabsBezelBorder, NSTopTabsBezelBorder, NSLeftTabsBezelBorder,
                                          NSBottomTabsBezelBorder, NSRightTabsBezelBorder};
    NSTabViewType t = p <= NSTabPositionRight ? types[p] : NSTopTabsBezelBorder;
    if (t == NSNoTabsBezelBorder)
        t = [self tabViewBorderType] == NSTabViewBorderTypeNone   ? NSNoTabsNoBorder
            : [self tabViewBorderType] == NSTabViewBorderTypeLine ? NSNoTabsLineBorder
                                                                  : NSNoTabsBezelBorder;
    [self setTabViewType:t];
}
- (NSTabViewBorderType)tabViewBorderType
{
    return _type == NSNoTabsNoBorder ? NSTabViewBorderTypeNone
           : _type == NSNoTabsLineBorder ? NSTabViewBorderTypeLine
                                         : NSTabViewBorderTypeBezel;
}
- (void)setTabViewBorderType:(NSTabViewBorderType)b
{
    if ([self tabPosition] != NSTabPositionNone)
        return; /* tabs always sit on a bezel */
    [self setTabViewType:b == NSTabViewBorderTypeNone ? NSNoTabsNoBorder
                         : b == NSTabViewBorderTypeLine ? NSNoTabsLineBorder
                                                        : NSNoTabsBezelBorder];
}

/* ---- geometry ---------------------------------------------------------------------- */

- (BOOL)_hasTabs { return _type <= NSRightTabsBezelBorder && [_items count]; }
- (CGFloat)_tabHeight { return _size == NSControlSizeRegular || _size == NSControlSizeLarge ? TAB_HEIGHT : 20; }
- (BOOL)_sideways { return _type == NSLeftTabsBezelBorder || _type == NSRightTabsBezelBorder; }
- (CGFloat)_tabLength:(NSTabViewItem *)item { return fmax(TAB_MIN, [item sizeOfLabel:NO].width + TAB_PAD); }

/* The box the content sits in: the bounds less half the row of tabs. */
- (NSRect)_boxRect
{
    NSRect b = [self bounds];
    if (![self _hasTabs])
        return b;
    CGFloat half = [self _sideways] ? [self _columnWidth] / 2 : [self _tabHeight] / 2;
    switch (_type) {
    case NSTopTabsBezelBorder:
        b.origin.y += half;
        b.size.height -= half;
        break;
    case NSBottomTabsBezelBorder:
        b.size.height -= half;
        break;
    case NSLeftTabsBezelBorder:
        b.origin.x += half;
        b.size.width -= half;
        break;
    default:
        b.size.width -= half;
        break;
    }
    return b;
}
- (CGFloat)_columnWidth
{
    CGFloat w = TAB_MIN;
    for (NSTabViewItem *item in _items)
        w = fmax(w, [self _tabLength:item]);
    return w;
}
- (NSRect)contentRect
{
    NSRect box = [self _boxRect];
    switch (_type) {
    case NSNoTabsNoBorder:
        return box;
    case NSNoTabsLineBorder:
        return NSInsetRect(box, 1, 1);
    case NSNoTabsBezelBorder:
        return NSInsetRect(box, 3, 3);
    default:
        break;
    }
    if (![self _hasTabs])
        return NSInsetRect(box, 3, 3);
    /* room for the other half of the tabs, then a margin */
    CGFloat half = [self _sideways] ? [self _columnWidth] / 2 : [self _tabHeight] / 2;
    NSRect r = NSInsetRect(box, 7, 7);
    switch (_type) {
    case NSTopTabsBezelBorder:
        r.origin.y += half;
        r.size.height -= half;
        break;
    case NSBottomTabsBezelBorder:
        r.size.height -= half;
        break;
    case NSLeftTabsBezelBorder:
        r.origin.x += half;
        r.size.width -= half;
        break;
    default:
        r.size.width -= half;
        break;
    }
    r.size.width = fmax(0, r.size.width);
    r.size.height = fmax(0, r.size.height);
    return r;
}
- (NSSize)minimumSize
{
    if (![self _hasTabs])
        return NSMakeSize(6, 6);
    CGFloat total = 0;
    for (NSTabViewItem *item in _items)
        total += [self _tabLength:item];
    return [self _sideways] ? NSMakeSize([self _columnWidth] + 14, [_items count] * [self _tabHeight] + 14)
                            : NSMakeSize(total + 14, [self _tabHeight] + 14);
}
/* Where each tab is drawn: a row centred on the box's edge, or a column on a
 * side; squeezed to fit when there isn't room. */
- (NSRect)_tabRect:(NSUInteger)index
{
    NSUInteger n = [_items count];
    NSRect b = [self bounds];
    CGFloat h = [self _tabHeight];
    if ([self _sideways]) {
        CGFloat w = [self _columnWidth], total = n * h;
        CGFloat y = floor(NSMidY(b) - total / 2);
        CGFloat x = _type == NSLeftTabsBezelBorder ? 0 : NSMaxX(b) - w;
        return NSMakeRect(x, y + index * h, w, h);
    }
    CGFloat lengths[n], total = 0;
    for (NSUInteger i = 0; i < n; i++) {
        lengths[i] = [self _tabLength:[_items objectAtIndex:i]];
        total += lengths[i];
    }
    CGFloat room = b.size.width - 4;
    CGFloat scale = total > room && total > 0 ? room / total : 1;
    CGFloat x = floor(NSMidX(b) - total * scale / 2);
    for (NSUInteger i = 0; i < index; i++)
        x += floor(lengths[i] * scale);
    CGFloat y = _type == NSBottomTabsBezelBorder ? NSMaxY(b) - h : 0;
    return NSMakeRect(x, y, floor(lengths[index] * scale), h);
}
- (NSTabViewItem *)tabViewItemAtPoint:(NSPoint)p
{
    if (![self _hasTabs])
        return nil;
    for (NSUInteger i = 0; i < [_items count]; i++)
        if (NSPointInRect(p, [self _tabRect:i]))
            return [_items objectAtIndex:i];
    return nil;
}
- (void)_relayOut
{
    [[_selected view] setFrame:[self contentRect]];
    [self setNeedsDisplay:YES];
}
- (void)resizeSubviewsWithOldSize:(NSSize)old
{
    [super resizeSubviewsWithOldSize:old];
    [[_selected view] setFrame:[self contentRect]];
}

/* ---- items ------------------------------------------------------------------------- */

- (NSArray *)tabViewItems { return [[_items copy] autorelease]; }
- (void)setTabViewItems:(NSArray *)items
{
    for (NSTabViewItem *item in [[_items copy] autorelease])
        [self removeTabViewItem:item];
    for (NSTabViewItem *item in items)
        [self addTabViewItem:item];
}
- (NSInteger)numberOfTabViewItems { return [_items count]; }
- (NSTabViewItem *)tabViewItemAtIndex:(NSInteger)i
{
    if (i < 0 || i >= (NSInteger)[_items count])
        [NSException raise:NSRangeException format:@"-[NSTabView tabViewItemAtIndex:]: index %ld beyond bounds %lu",
                                                   (long)i, (unsigned long)[_items count]];
    return [_items objectAtIndex:i];
}
- (NSInteger)indexOfTabViewItem:(NSTabViewItem *)item { return [_items indexOfObjectIdenticalTo:item]; }
- (NSInteger)indexOfTabViewItemWithIdentifier:(id)identifier
{
    for (NSUInteger i = 0; i < [_items count]; i++) {
        id mine = [[_items objectAtIndex:i] identifier];
        if (mine == identifier || [mine isEqual:identifier])
            return i;
    }
    return NSNotFound;
}
- (void)_countChanged
{
    if ([_delegate respondsToSelector:@selector(tabViewDidChangeNumberOfTabViewItems:)])
        [_delegate tabViewDidChangeNumberOfTabViewItems:self];
    [self _relayOut];
}
- (void)addTabViewItem:(NSTabViewItem *)item { [self insertTabViewItem:item atIndex:[_items count]]; }
- (void)insertTabViewItem:(NSTabViewItem *)item atIndex:(NSInteger)i
{
    if (!item || [_items containsObject:item])
        return;
    [[item tabView] removeTabViewItem:item];
    [_items insertObject:item atIndex:MIN((NSUInteger)MAX(i, 0), [_items count])];
    [item _setTabView:self];
    if (!_selected)
        [self _show:item];
    [self _countChanged];
}
- (void)removeTabViewItem:(NSTabViewItem *)item
{
    NSUInteger i = [_items indexOfObjectIdenticalTo:item];
    if (i == NSNotFound)
        return;
    [item retain];
    if (item == _selected) {
        [[item view] removeFromSuperview];
        _selected = nil;
    }
    [_items removeObjectAtIndex:i];
    [item _setTabView:nil];
    if (!_selected && [_items count])
        [self _show:[_items objectAtIndex:MIN(i, [_items count] - 1)]];
    [item release];
    [self _countChanged];
}

/* ---- selection --------------------------------------------------------------------- */

- (NSTabViewItem *)selectedTabViewItem { return _selected; }
/* Shows an item's view in the box, with no word to the delegate. */
- (void)_show:(NSTabViewItem *)item
{
    if (item == _selected)
        return;
    [[_selected view] removeFromSuperview];
    _selected = item;
    NSView *v = [item view];
    if (v) {
        [v setFrame:[self contentRect]];
        [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [v setHidden:NO];
        [self addSubview:v];
    }
    [self setNeedsDisplay:YES];
}
- (void)selectTabViewItem:(NSTabViewItem *)item
{
    if (!item || item == _selected || ![_items containsObject:item])
        return;
    if ([_delegate respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)] &&
        ![_delegate tabView:self shouldSelectTabViewItem:item])
        return;
    if ([_delegate respondsToSelector:@selector(tabView:willSelectTabViewItem:)])
        [_delegate tabView:self willSelectTabViewItem:item];
    [self willChangeValueForKey:@"selectedTabViewItem"];
    [self _show:item];
    [self didChangeValueForKey:@"selectedTabViewItem"];
    NSView *first = [item initialFirstResponder];
    if (first && [first window] == [self window])
        [[self window] makeFirstResponder:first];
    if ([_delegate respondsToSelector:@selector(tabView:didSelectTabViewItem:)])
        [_delegate tabView:self didSelectTabViewItem:item];
}
- (void)selectTabViewItemAtIndex:(NSInteger)i { [self selectTabViewItem:[self tabViewItemAtIndex:i]]; }
- (void)selectTabViewItemWithIdentifier:(id)identifier
{
    NSInteger i = [self indexOfTabViewItemWithIdentifier:identifier];
    if (i != NSNotFound)
        [self selectTabViewItemAtIndex:i];
}
- (void)selectFirstTabViewItem:(id)sender
{
    if ([_items count])
        [self selectTabViewItemAtIndex:0];
}
- (void)selectLastTabViewItem:(id)sender
{
    if ([_items count])
        [self selectTabViewItemAtIndex:[_items count] - 1];
}
- (void)selectNextTabViewItem:(id)sender
{
    NSInteger i = [self indexOfTabViewItem:_selected];
    if (i != NSNotFound && i + 1 < (NSInteger)[_items count])
        [self selectTabViewItemAtIndex:i + 1];
}
- (void)selectPreviousTabViewItem:(id)sender
{
    NSInteger i = [self indexOfTabViewItem:_selected];
    if (i != NSNotFound && i > 0)
        [self selectTabViewItemAtIndex:i - 1];
}
- (void)takeSelectedTabViewItemFromSender:(id)sender
{
    NSInteger i = -1;
    if ([sender respondsToSelector:@selector(selectedSegment)])
        i = ((NSInteger(*)(id, SEL))objc_msgSend)(sender, @selector(selectedSegment));
    else if ([sender respondsToSelector:@selector(indexOfSelectedItem)])
        i = ((NSInteger(*)(id, SEL))objc_msgSend)(sender, @selector(indexOfSelectedItem));
    else if ([sender respondsToSelector:@selector(selectedRow)])
        i = ((NSInteger(*)(id, SEL))objc_msgSend)(sender, @selector(selectedRow));
    else if ([sender respondsToSelector:@selector(integerValue)])
        i = [sender integerValue];
    if (i >= 0 && i < (NSInteger)[_items count])
        [self selectTabViewItemAtIndex:i];
}

/* ---- events ------------------------------------------------------------------------ */

- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSTabViewItem *item = [self tabViewItemAtPoint:p];
    if (!item) {
        [super mouseDown:e];
        return;
    }
    _pressed = [_items indexOfObjectIdenticalTo:item];
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)e
{
    if (_pressed < 0) {
        [super mouseUp:e];
        return;
    }
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSTabViewItem *item = [self tabViewItemAtPoint:p];
    NSInteger pressed = _pressed;
    _pressed = -1;
    [self setNeedsDisplay:YES];
    if (item && [_items indexOfObjectIdenticalTo:item] == (NSUInteger)pressed)
        [self selectTabViewItem:item];
}
- (BOOL)acceptsFirstResponder { return [self _hasTabs]; }
- (void)keyDown:(NSEvent *)e
{
    NSString *c = [e charactersIgnoringModifiers];
    unichar k = [c length] ? [c characterAtIndex:0] : 0;
    BOOL back = [self _sideways] ? k == NSUpArrowFunctionKey : k == NSLeftArrowFunctionKey;
    BOOL on = [self _sideways] ? k == NSDownArrowFunctionKey : k == NSRightArrowFunctionKey;
    if (back)
        [self selectPreviousTabViewItem:self];
    else if (on)
        [self selectNextTabViewItem:self];
    else
        [super keyDown:e];
}

/* ---- drawing ----------------------------------------------------------------------- */

- (void)drawRect:(NSRect)dirty
{
    NSRect box = NSInsetRect([self _boxRect], 0.5, 0.5);
    switch (_type) {
    case NSNoTabsNoBorder:
        break;
    case NSNoTabsLineBorder:
        AFillRoundedRect(box, 0, _drawsBackground ? [NSColor colorWithCalibratedWhite:0 alpha:0.03] : nil,
                         [NSColor colorWithCalibratedWhite:0 alpha:0.25]);
        break;
    default:
        AFillRoundedRect(box, 5, _drawsBackground ? [NSColor colorWithCalibratedWhite:0 alpha:0.04] : nil,
                         [NSColor colorWithCalibratedWhite:0 alpha:0.12]);
        break;
    }
    if (![self _hasTabs])
        return;
    NSUInteger n = [_items count];
    NSRect row = NSUnionRect([self _tabRect:0], [self _tabRect:n - 1]);
    /* the track: a rounded bar the tabs sit in */
    AFillRoundedRect(NSInsetRect(row, 0.5, 0.5), 6, [NSColor colorWithCalibratedWhite:0.89 alpha:1],
                     [NSColor colorWithCalibratedWhite:0 alpha:0.10]);
    NSInteger sel = _selected ? (NSInteger)[_items indexOfObjectIdenticalTo:_selected] : -1;
    for (NSUInteger i = 0; i < n; i++) {
        NSRect r = [self _tabRect:i];
        if ((NSInteger)i == sel) {
            AFillRoundedRect(NSInsetRect(r, 2.5, 2.5), 4, [NSColor whiteColor],
                             [NSColor colorWithCalibratedWhite:0 alpha:0.16]);
        } else if ((NSInteger)i == _pressed) {
            AFillRoundedRect(NSInsetRect(r, 2.5, 2.5), 4, [NSColor colorWithCalibratedWhite:0 alpha:0.08], nil);
        } else if (i + 1 < n && (NSInteger)i + 1 != sel) {
            /* a thin line between two tabs that aren't selected */
            [[NSColor colorWithCalibratedWhite:0 alpha:0.14] setFill];
            NSRectFill([self _sideways] ? NSMakeRect(NSMinX(r) + 8, NSMaxY(r) - 0.5, r.size.width - 16, 1)
                                        : NSMakeRect(NSMaxX(r) - 0.5, NSMinY(r) + 6, 1, r.size.height - 12));
        }
        NSTabViewItem *item = [_items objectAtIndex:i];
        NSSize s = [item sizeOfLabel:NO];
        CGFloat w = fmin(s.width, r.size.width - 12);
        [item drawLabel:YES inRect:NSMakeRect(floor(NSMidX(r) - w / 2), NSMinY(r), w, r.size.height)];
    }
}
@end
