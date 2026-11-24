/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: combo boxes (NSComboBox, NSComboBoxCell), written from
 * Apple's public API documentation.
 *
 * A combo box is a text field with a button at its right end that opens
 * a list of values, its own (addItemWithObjectValue: and the rest) or its
 * data source's (usesDataSource). The list opens below the field, or
 * above it when there's no room, inside the window as an open menu is
 * (Wayland doesn't let a program place a window of its own there),
 * showing numberOfVisibleItems rows and scrolling for the rest. Moving
 * over it or using the up and down arrows highlights an item
 * (comboBoxSelectionIsChanging:); clicking one or pressing Return
 * chooses it: it becomes the text, the selected item
 * (comboBoxSelectionDidChange:) and the action is sent. Escape, a click
 * elsewhere or the button close it (comboBoxWillDismiss:). Typing goes on
 * into the field while the list is open. With the list closed, the up
 * and down arrows step through the items.
 *
 * With completes set, what is typed is completed from the first item
 * that starts with it (ignoring case), the added part selected so that
 * the next key replaces it; a data source can complete instead
 * (comboBox:completedString:).
 *
 * In a nib the cell keeps its items under "NSPopUpListData" and
 * "NSUsesDataSource", "NSCompletes", "NSVisibleItemCount",
 * "NSHasVerticalScroller", "NSIntercellSpacingWidth" and
 * "NSIntercellSpacingHeight", "NSRowHeight" and "NSDataSource" (names from
 * developers' descriptions of the format, not checked against a nib from
 * a Mac; no Apple code was read). */
#import "AInternal.h"

NSNotificationName const NSComboBoxWillPopUpNotification = @"NSComboBoxWillPopUpNotification";
NSNotificationName const NSComboBoxWillDismissNotification = @"NSComboBoxWillDismissNotification";
NSNotificationName const NSComboBoxSelectionDidChangeNotification = @"NSComboBoxSelectionDidChangeNotification";
NSNotificationName const NSComboBoxSelectionIsChangingNotification = @"NSComboBoxSelectionIsChangingNotification";

static const CGFloat button_width = 18;

@interface NSComboBoxCell (FerryCombo)
- (void)_setComboBox:(NSComboBox *)box;
- (NSString *)_stringAt:(NSInteger)i;
- (void)_setSelected:(NSInteger)i;
- (NSInteger)_top;
- (void)_setTop:(NSInteger)top;
- (CGFloat)_rowHeight;
@end
@interface NSComboBox (FerryCombo)
- (void)_listChose:(NSInteger)row;
- (void)_listHighlighted:(NSInteger)row;
- (void)_dismissList;
- (NSRect)_buttonRect;
- (void)_listKeyDown:(NSEvent *)e;
@end

/* ---- the cell: the items ---------------------------------------------------------------- */

@implementation NSComboBoxCell {
    NSMutableArray *_items;
    BOOL _usesDataSource, _completes, _scroller, _buttonBordered;
    id _dataSource;
    NSInteger _visible, _selected, _top;
    CGFloat _itemHeight;
    NSSize _spacing;
    NSComboBox *_combo;   /* not retained: the control the cell is in */
}

- (void)_setUp
{
    _items = [[NSMutableArray alloc] init];
    _scroller = _buttonBordered = YES;
    _visible = 5;
    _selected = -1;
    _itemHeight = 16;
    _spacing = NSMakeSize(3, 2);
}
- (instancetype)initTextCell:(NSString *)s
{
    if ((self = [super initTextCell:s])) {
        [self _setUp];
        [self setEditable:YES];
        [self setBezeled:YES];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    [self _setUp];
    id items = [coder decodeObjectForKey:@"NSPopUpListData"];
    if ([items isKindOfClass:[NSArray class]])
        [_items addObjectsFromArray:items];
    _usesDataSource = [coder decodeBoolForKey:@"NSUsesDataSource"];
    _completes = [coder decodeBoolForKey:@"NSCompletes"];
    if ([coder containsValueForKey:@"NSVisibleItemCount"])
        _visible = [coder decodeIntegerForKey:@"NSVisibleItemCount"];
    if ([coder containsValueForKey:@"NSHasVerticalScroller"])
        _scroller = [coder decodeBoolForKey:@"NSHasVerticalScroller"];
    if ([coder containsValueForKey:@"NSIntercellSpacingWidth"])
        _spacing.width = [coder decodeDoubleForKey:@"NSIntercellSpacingWidth"];
    if ([coder containsValueForKey:@"NSIntercellSpacingHeight"])
        _spacing.height = [coder decodeDoubleForKey:@"NSIntercellSpacingHeight"];
    if ([coder containsValueForKey:@"NSRowHeight"])
        _itemHeight = [coder decodeDoubleForKey:@"NSRowHeight"];
    if ([coder containsValueForKey:@"NSDataSource"])
        _dataSource = [coder decodeObjectForKey:@"NSDataSource"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_items forKey:@"NSPopUpListData"];
    [coder encodeBool:_usesDataSource forKey:@"NSUsesDataSource"];
    [coder encodeBool:_completes forKey:@"NSCompletes"];
    [coder encodeInteger:_visible forKey:@"NSVisibleItemCount"];
    [coder encodeBool:_scroller forKey:@"NSHasVerticalScroller"];
    [coder encodeDouble:_spacing.width forKey:@"NSIntercellSpacingWidth"];
    [coder encodeDouble:_spacing.height forKey:@"NSIntercellSpacingHeight"];
    [coder encodeDouble:_itemHeight forKey:@"NSRowHeight"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSComboBoxCell *c = [super copyWithZone:zone];
    [c->_items setArray:_items];
    c->_usesDataSource = _usesDataSource;
    c->_completes = _completes;
    c->_scroller = _scroller;
    c->_buttonBordered = _buttonBordered;
    c->_dataSource = _dataSource;
    c->_visible = _visible;
    c->_selected = _selected;
    c->_itemHeight = _itemHeight;
    c->_spacing = _spacing;
    return c;
}
- (void)dealloc
{
    [_items release];
    [super dealloc];
}
- (void)_setComboBox:(NSComboBox *)box { _combo = box; }

- (BOOL)usesDataSource { return _usesDataSource; }
- (void)setUsesDataSource:(BOOL)f { _usesDataSource = f; }
- (BOOL)completes { return _completes; }
- (void)setCompletes:(BOOL)f { _completes = f; }
- (BOOL)hasVerticalScroller { return _scroller; }
- (void)setHasVerticalScroller:(BOOL)f { _scroller = f; }
- (BOOL)isButtonBordered { return _buttonBordered; }
- (void)setButtonBordered:(BOOL)f { _buttonBordered = f; }
- (id)dataSource { return _dataSource; }
- (void)setDataSource:(id)ds { _dataSource = ds; }
- (NSInteger)numberOfVisibleItems { return _visible; }
- (void)setNumberOfVisibleItems:(NSInteger)n { _visible = MAX(1, n); }
- (CGFloat)itemHeight { return _itemHeight; }
- (void)setItemHeight:(CGFloat)h { _itemHeight = h > 0 ? h : 16; }
- (NSSize)intercellSpacing { return _spacing; }
- (void)setIntercellSpacing:(NSSize)s { _spacing = s; }
- (CGFloat)_rowHeight { return _itemHeight + _spacing.height; }
- (NSInteger)_top { return _top; }
- (void)_setTop:(NSInteger)top { _top = MAX(0, MIN(top, [self numberOfItems] - _visible)); }

/* ---- the items, its own or the data source's ---- */

- (BOOL)_warnIfDataSource
{
    if (_usesDataSource)
        NSLog(@"*** -[NSComboBoxCell]: this combo box uses a data source; its own items can't be changed");
    return _usesDataSource;
}
- (NSInteger)numberOfItems
{
    if (!_usesDataSource)
        return (NSInteger)[_items count];
    if (_combo && [_dataSource respondsToSelector:@selector(numberOfItemsInComboBox:)])
        return [_dataSource numberOfItemsInComboBox:_combo];
    if ([_dataSource respondsToSelector:@selector(numberOfItemsInComboBoxCell:)])
        return [_dataSource numberOfItemsInComboBoxCell:self];
    return 0;
}
- (id)itemObjectValueAtIndex:(NSInteger)i
{
    if (!_usesDataSource) {
        if (i < 0 || i >= (NSInteger)[_items count])
            [NSException raise:NSRangeException format:@"-[NSComboBoxCell itemObjectValueAtIndex:]: index %ld beyond bounds", (long)i];
        return _items[i];
    }
    if (_combo && [_dataSource respondsToSelector:@selector(comboBox:objectValueForItemAtIndex:)])
        return [_dataSource comboBox:_combo objectValueForItemAtIndex:i];
    if ([_dataSource respondsToSelector:@selector(comboBoxCell:objectValueForItemAtIndex:)])
        return [_dataSource comboBoxCell:self objectValueForItemAtIndex:i];
    return nil;
}
- (NSString *)_stringFor:(id)value
{
    if (!value)
        return @"";
    NSFormatter *f = [self formatter];
    NSString *s = f ? [f stringForObjectValue:value] : nil;
    if (s)
        return s;
    return [value isKindOfClass:[NSString class]] ? value : [value description];
}
- (NSString *)_stringAt:(NSInteger)i { return [self _stringFor:[self itemObjectValueAtIndex:i]]; }
- (NSArray *)objectValues
{
    if (_usesDataSource) {
        [self _warnIfDataSource];
        return @[];
    }
    return [[_items copy] autorelease];
}
- (void)addItemWithObjectValue:(id)object
{
    if (![self _warnIfDataSource] && object)
        [_items addObject:object];
}
- (void)addItemsWithObjectValues:(NSArray *)objects
{
    if (![self _warnIfDataSource])
        [_items addObjectsFromArray:objects];
}
- (void)insertItemWithObjectValue:(id)object atIndex:(NSInteger)i
{
    if (![self _warnIfDataSource] && object)
        [_items insertObject:object atIndex:i];
    if (_selected >= i)
        _selected++;
}
- (void)removeItemAtIndex:(NSInteger)i
{
    if ([self _warnIfDataSource])
        return;
    [_items removeObjectAtIndex:i];
    if (_selected == i)
        _selected = -1;
    else if (_selected > i)
        _selected--;
}
- (void)removeItemWithObjectValue:(id)object
{
    NSInteger i = [self indexOfItemWithObjectValue:object];
    if (i >= 0)
        [self removeItemAtIndex:i];
}
- (void)removeAllItems
{
    if ([self _warnIfDataSource])
        return;
    [_items removeAllObjects];
    _selected = -1;
    _top = 0;
}
- (NSInteger)indexOfItemWithObjectValue:(id)object
{
    if (_usesDataSource) {
        [self _warnIfDataSource];
        return NSNotFound;
    }
    NSUInteger i = [_items indexOfObject:object];
    return i == NSNotFound ? NSNotFound : (NSInteger)i;
}
/* The index of the item a string names: the data source's answer, or the
 * first item shown as that string. */
- (NSInteger)_indexOfString:(NSString *)s
{
    if (_usesDataSource) {
        NSUInteger i = NSNotFound;
        if (_combo && [_dataSource respondsToSelector:@selector(comboBox:indexOfItemWithStringValue:)])
            i = [_dataSource comboBox:_combo indexOfItemWithStringValue:s];
        else if ([_dataSource respondsToSelector:@selector(comboBoxCell:indexOfItemWithStringValue:)])
            i = [_dataSource comboBoxCell:self indexOfItemWithStringValue:s];
        else
            for (NSInteger k = 0, n = [self numberOfItems]; k < n; k++)
                if ([[self _stringAt:k] isEqualToString:s])
                    return k;
        return i == NSNotFound || (NSInteger)i >= [self numberOfItems] ? -1 : (NSInteger)i;
    }
    for (NSInteger k = 0, n = [self numberOfItems]; k < n; k++)
        if ([[self _stringAt:k] isEqualToString:s])
            return k;
    return -1;
}
- (NSInteger)indexOfSelectedItem { return _selected; }
- (id)objectValueOfSelectedItem
{
    if (_usesDataSource) {
        [self _warnIfDataSource];
        return nil;
    }
    return _selected >= 0 && _selected < (NSInteger)[_items count] ? _items[_selected] : nil;
}
- (void)_setSelected:(NSInteger)i { _selected = i; }
- (void)selectItemAtIndex:(NSInteger)i
{
    if (i < 0 || i >= [self numberOfItems]) {
        _selected = -1;
        return;
    }
    _selected = i;
    [self setObjectValue:[self itemObjectValueAtIndex:i]];
}
- (void)selectItemWithObjectValue:(id)object
{
    NSInteger i = [self indexOfItemWithObjectValue:object];
    [self selectItemAtIndex:i == NSNotFound ? -1 : i];
}
- (void)deselectItemAtIndex:(NSInteger)i
{
    if (i == _selected)
        _selected = -1;
}
- (void)noteNumberOfItemsChanged
{
    if (_selected >= [self numberOfItems])
        _selected = -1;
    [self _setTop:_top];
}
- (void)reloadData { [self noteNumberOfItemsChanged]; }
- (void)scrollItemAtIndexToTop:(NSInteger)i { [self _setTop:i]; }
- (void)scrollItemAtIndexToVisible:(NSInteger)i
{
    if (i < _top)
        [self _setTop:i];
    else if (i >= _top + _visible)
        [self _setTop:i - _visible + 1];
}

/* The first item that starts with the string, ignoring case. */
- (NSString *)completedString:(NSString *)string
{
    if (![string length])
        return nil;
    if (_usesDataSource) {
        if (_combo && [_dataSource respondsToSelector:@selector(comboBox:completedString:)])
            return [_dataSource comboBox:_combo completedString:string];
        if ([_dataSource respondsToSelector:@selector(comboBoxCell:completedString:)])
            return [_dataSource comboBoxCell:self completedString:string];
    }
    for (NSInteger i = 0, n = [self numberOfItems]; i < n; i++) {
        NSString *s = [self _stringAt:i];
        if ([s length] >= [string length] &&
            [[s substringToIndex:[string length]] caseInsensitiveCompare:string] == NSOrderedSame)
            return s;
    }
    return nil;
}
@end

/* ---- the open list --------------------------------------------------------------------- */

@interface AComboList : NSView {
@public
    NSComboBox *_box;     /* not retained */
    NSRect _list;         /* in the window */
    NSInteger _highlighted;
    BOOL _tracking;
}
@end
@implementation AComboList
- (BOOL)isFlipped { return NO; }
- (NSView *)hitTest:(NSPoint)p { return NSPointInRect(p, [self frame]) ? self : nil; }
- (NSComboBoxCell *)_cell { return (NSComboBoxCell *)[_box cell]; }
- (NSInteger)_rowAt:(NSPoint)p
{
    NSRect inner = NSInsetRect(_list, 0, 2);
    if (!NSPointInRect(p, inner))
        return -1;
    NSComboBoxCell *c = [self _cell];
    NSInteger row = [c _top] + (NSInteger)((NSMaxY(inner) - p.y) / [c _rowHeight]);
    return row < [c numberOfItems] ? row : -1;
}
- (NSRect)_rectOfRow:(NSInteger)row
{
    NSComboBoxCell *c = [self _cell];
    CGFloat h = [c _rowHeight];
    return NSMakeRect(NSMinX(_list), NSMaxY(_list) - 2 - (row - [c _top] + 1) * h, _list.size.width, h);
}
- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [e locationInWindow];
    if (NSPointInRect(p, _list)) {
        _tracking = YES;
        NSInteger row = [self _rowAt:p];
        if (row >= 0)
            [_box _listHighlighted:row];
        return;
    }
    NSWindow *w = [[[self window] retain] autorelease];
    NSComboBox *box = [[_box retain] autorelease];
    NSPoint inBox = [box convertPoint:p fromView:nil];
    [box _dismissList];
    /* the click goes on to what it was on, unless it was the button that
     * opened the list */
    if (!NSPointInRect(inBox, [box _buttonRect]))
        [w sendEvent:e];
}
- (void)mouseDragged:(NSEvent *)e
{
    NSInteger row = [self _rowAt:[e locationInWindow]];
    if (row >= 0 && row != _highlighted)
        [_box _listHighlighted:row];
}
- (void)mouseMoved:(NSEvent *)e { [self mouseDragged:e]; }
- (void)mouseUp:(NSEvent *)e
{
    if (!_tracking)
        return;
    _tracking = NO;
    NSInteger row = [self _rowAt:[e locationInWindow]];
    if (row >= 0)
        [_box _listChose:row];
}
- (void)scrollWheel:(NSEvent *)e
{
    NSComboBoxCell *c = [self _cell];
    CGFloat dy = [e scrollingDeltaY];
    if ([e hasPreciseScrollingDeltas])
        dy /= [c _rowHeight];
    NSInteger step = dy > 0 ? -(NSInteger)ceil(dy) : (NSInteger)ceil(-dy);
    [c _setTop:[c _top] + step];
    [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent *)e { [_box _listKeyDown:e]; }
- (void)drawRect:(NSRect)dirty
{
    NSComboBoxCell *c = [self _cell];
    AFillRoundedRect(NSInsetRect(_list, 0.5, 0.5), 5, [NSColor controlBackgroundColor], [NSColor colorWithWhite:0 alpha:0.22]);
    NSInteger n = [c numberOfItems], top = [c _top], visible = [c numberOfVisibleItems];
    NSFont *font = [_box font] ?: ADefaultFont();
    BOOL scroller = [c hasVerticalScroller] && n > visible;
    for (NSInteger row = top; row < n && row < top + visible; row++) {
        NSRect r = [self _rectOfRow:row];
        BOOL hl = row == _highlighted;
        if (hl)
            AFillRoundedRect(NSInsetRect(r, 3, 0), 4, [NSColor controlAccentColor], nil);
        NSAttributedString *s = AAttributed([c _stringAt:row], font, hl ? [NSColor whiteColor] : [NSColor labelColor]);
        CGFloat a, d;
        ALineSize(s, &a, &d);
        [NSGraphicsContext saveGraphicsState];
        NSRectClip(NSMakeRect(NSMinX(r) + 6, NSMinY(r), r.size.width - 12 - (scroller ? 8 : 0), r.size.height));
        ADrawLine(s, NSMinX(r) + 6 + [c intercellSpacing].width, round(NSMidY(r) - (a - d) / 2));
        [NSGraphicsContext restoreGraphicsState];
    }
    if (scroller) {
        NSRect track = NSMakeRect(NSMaxX(_list) - 8, NSMinY(_list) + 4, 5, _list.size.height - 8);
        CGFloat h = fmax(16, track.size.height * visible / n);
        CGFloat y = NSMaxY(track) - h - (track.size.height - h) * top / fmax(1, n - visible);
        AFillRoundedRect(NSMakeRect(NSMinX(track), y, track.size.width, h), 2.5, [NSColor colorWithWhite:0 alpha:0.3], nil);
    }
}
@end

/* ---- the control ----------------------------------------------------------------------- */

@implementation NSComboBox {
    BOOL _loading;
    id _comboDataSource;
    AComboList *_listView;
}

+ (Class)cellClass { return [NSComboBoxCell class]; }
- (NSComboBoxCell *)_comboCell { return (NSComboBoxCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    if (!_loading && ![[self cell] isKindOfClass:[NSComboBoxCell class]]) {
        NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    [[self _comboCell] _setComboBox:self];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    _loading = YES;
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _loading = NO;
    if (![[self cell] isKindOfClass:[NSComboBoxCell class]]) {
        NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    [[self _comboCell] _setComboBox:self];
    _comboDataSource = [[self _comboCell] dataSource];
    return self;
}
- (void)dealloc
{
    [self _dismissList];
    [[self _comboCell] _setComboBox:nil];
    [super dealloc];
}
- (void)setCell:(NSCell *)cell
{
    if ([[self cell] isKindOfClass:[NSComboBoxCell class]])
        [[self _comboCell] _setComboBox:nil];
    [super setCell:cell];
    if ([cell isKindOfClass:[NSComboBoxCell class]])
        [(NSComboBoxCell *)cell _setComboBox:self];
}

#define FORWARD(type, getter, setter)                    \
    -(type)getter { return [[self _comboCell] getter]; } \
    -(void)setter(type)v { [[self _comboCell] setter v]; }
FORWARD(BOOL, usesDataSource, setUsesDataSource:)
FORWARD(BOOL, completes, setCompletes:)
FORWARD(BOOL, hasVerticalScroller, setHasVerticalScroller:)
FORWARD(NSInteger, numberOfVisibleItems, setNumberOfVisibleItems:)
FORWARD(CGFloat, itemHeight, setItemHeight:)
FORWARD(NSSize, intercellSpacing, setIntercellSpacing:)
- (BOOL)isButtonBordered { return [[self _comboCell] isButtonBordered]; }
- (void)setButtonBordered:(BOOL)f
{
    [[self _comboCell] setButtonBordered:f];
    [self setNeedsDisplay:YES];
}
- (id)dataSource { return _comboDataSource; }
- (void)setDataSource:(id)ds
{
    _comboDataSource = ds;
    [[self _comboCell] setDataSource:ds];
}
- (NSInteger)numberOfItems { return [[self _comboCell] numberOfItems]; }
- (NSInteger)indexOfSelectedItem { return [[self _comboCell] indexOfSelectedItem]; }
- (NSArray *)objectValues { return [[self _comboCell] objectValues]; }
- (id)objectValueOfSelectedItem { return [[self _comboCell] objectValueOfSelectedItem]; }
- (void)addItemWithObjectValue:(id)o { [[self _comboCell] addItemWithObjectValue:o]; [self _listChanged]; }
- (void)addItemsWithObjectValues:(NSArray *)a { [[self _comboCell] addItemsWithObjectValues:a]; [self _listChanged]; }
- (void)insertItemWithObjectValue:(id)o atIndex:(NSInteger)i { [[self _comboCell] insertItemWithObjectValue:o atIndex:i]; [self _listChanged]; }
- (void)removeItemWithObjectValue:(id)o { [[self _comboCell] removeItemWithObjectValue:o]; [self _listChanged]; }
- (void)removeItemAtIndex:(NSInteger)i { [[self _comboCell] removeItemAtIndex:i]; [self _listChanged]; }
- (void)removeAllItems { [[self _comboCell] removeAllItems]; [self _listChanged]; }
- (id)itemObjectValueAtIndex:(NSInteger)i { return [[self _comboCell] itemObjectValueAtIndex:i]; }
- (NSInteger)indexOfItemWithObjectValue:(id)o { return [[self _comboCell] indexOfItemWithObjectValue:o]; }
- (void)noteNumberOfItemsChanged { [[self _comboCell] noteNumberOfItemsChanged]; [self _listChanged]; }
- (void)reloadData { [[self _comboCell] reloadData]; [self _listChanged]; }
- (void)scrollItemAtIndexToTop:(NSInteger)i { [[self _comboCell] scrollItemAtIndexToTop:i]; [self _listChanged]; }
- (void)scrollItemAtIndexToVisible:(NSInteger)i { [[self _comboCell] scrollItemAtIndexToVisible:i]; [self _listChanged]; }
- (void)_listChanged
{
    if (_listView) {
        [self _placeList];
        [_listView setNeedsDisplay:YES];
    }
}

- (void)_postSelection:(NSNotificationName)name
{
    SEL sel = name == NSComboBoxSelectionDidChangeNotification ? @selector(comboBoxSelectionDidChange:)
              : name == NSComboBoxSelectionIsChangingNotification ? @selector(comboBoxSelectionIsChanging:)
              : name == NSComboBoxWillPopUpNotification ? @selector(comboBoxWillPopUp:)
                                                        : @selector(comboBoxWillDismiss:);
    NSNotification *n = [NSNotification notificationWithName:name object:self];
    id delegate = [self delegate];
    if ([delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}
/* The text becomes the item's, in the field being edited or not. */
- (void)_showItem:(NSInteger)i
{
    NSString *s = [[self _comboCell] _stringAt:i];
    if ([self _isEditing]) {
        [self _setEditingText:s selectedRange:NSMakeRange(0, [s length])];
        [self validateEditing];
    } else {
        [self setObjectValue:[self itemObjectValueAtIndex:i]];
    }
}
- (void)selectItemAtIndex:(NSInteger)i
{
    NSComboBoxCell *c = [self _comboCell];
    NSInteger before = [c indexOfSelectedItem];
    if (i >= 0 && i < [c numberOfItems]) {
        [c _setSelected:i];
        [self _showItem:i];
    } else {
        [c _setSelected:-1];
    }
    if (_listView)
        _listView->_highlighted = [c indexOfSelectedItem];
    [self setNeedsDisplay:YES];
    if ([c indexOfSelectedItem] != before)
        [self _postSelection:NSComboBoxSelectionDidChangeNotification];
}
- (void)selectItemWithObjectValue:(id)o
{
    NSInteger i = [self indexOfItemWithObjectValue:o];
    [self selectItemAtIndex:i == NSNotFound ? -1 : i];
}
- (void)deselectItemAtIndex:(NSInteger)i
{
    NSComboBoxCell *c = [self _comboCell];
    if ([c indexOfSelectedItem] != i)
        return;
    [c deselectItemAtIndex:i];
    if (_listView)
        _listView->_highlighted = -1;
    [self _postSelection:NSComboBoxSelectionDidChangeNotification];
}

/* ---- size and drawing ---- */

- (NSRect)_buttonRect
{
    NSRect b = [self bounds];
    CGFloat h = fmin(b.size.height, 22);
    return NSMakeRect(NSMaxX(b) - button_width, round(NSMidY(b) - h / 2), button_width, h);
}
- (NSRect)_textRect
{
    NSRect r = [super _textRect];
    r.size.width -= button_width;
    return r;
}
- (NSRect)_clipRect
{
    NSRect r = [super _clipRect];
    r.size.width -= button_width;
    return r;
}
- (NSSize)intrinsicContentSize
{
    NSSize s = [super intrinsicContentSize];
    return NSMakeSize(fmax(s.width + button_width, 60), fmax(s.height, 22));
}
- (void)_drawBezelInRect:(NSRect)b focused:(BOOL)focused
{
    NSRect field = b;
    field.size.width -= button_width - 1;
    [super _drawBezelInRect:field focused:focused];
    NSRect r = NSInsetRect([self _buttonRect], 0.5, 0.5);
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    if ([self isButtonBordered])
        AFillRoundedRect(r, 4, _listView ? [NSColor colorWithWhite:0.88 alpha:1] : [NSColor whiteColor],
                         [NSColor colorWithWhite:0 alpha:0.22 * dim]);
    CGFloat cx = NSMidX(r), cy = NSMidY(r), dir = [self isFlipped] ? 1 : -1;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(cx - 3.5, cy - dir * 1.75)];
    [p lineToPoint:NSMakePoint(cx, cy + dir * 1.75)];
    [p lineToPoint:NSMakePoint(cx + 3.5, cy - dir * 1.75)];
    [p setLineWidth:1.5];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [[NSColor colorWithWhite:0 alpha:0.6 * dim] setStroke];
    [p stroke];
}

/* ---- the list ---- */

- (BOOL)_isListOpen { return _listView != nil; }
- (void)_placeList
{
    NSWindow *w = [self window];
    NSComboBoxCell *c = [self _comboCell];
    NSInteger rows = MAX(1, MIN([c numberOfVisibleItems], [c numberOfItems]));
    CGFloat h = rows * [c _rowHeight] + 4;
    NSRect field = [self convertRect:[self bounds] toView:nil];
    NSRect content = NSMakeRect(0, 0, [w frame].size.width, [[w contentView] frame].size.height);
    NSRect list = NSMakeRect(NSMinX(field), NSMinY(field) - h - 1, field.size.width, h);
    if (NSMinY(list) < NSMinY(content) + 2 && NSMaxY(field) + h + 1 <= NSMaxY(content))
        list.origin.y = NSMaxY(field) + 1;
    list.origin.y = fmax(list.origin.y, NSMinY(content) + 2);
    _listView->_list = NSIntegralRect(list);
}
- (void)_openList
{
    NSWindow *w = [self window];
    if (_listView || !w || ![self isEnabled])
        return;
    [self _postSelection:NSComboBoxWillPopUpNotification];
    NSComboBoxCell *c = [self _comboCell];
    /* the item the text names is the one highlighted */
    NSInteger sel = [c indexOfSelectedItem];
    if (sel < 0)
        sel = [c _indexOfString:[self stringValue]];
    [c _setSelected:sel];
    _listView = [[AComboList alloc] initWithFrame:NSZeroRect];
    _listView->_box = self;
    _listView->_highlighted = sel;
    if (sel >= 0)
        [c scrollItemAtIndexToVisible:sel];
    [self _placeList];
    [w _setOverlayView:_listView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_windowResigned:)
                                                 name:NSWindowDidResignKeyNotification object:w];
    [self setNeedsDisplay:YES];
}
- (void)_dismissList
{
    if (!_listView)
        return;
    [self _postSelection:NSComboBoxWillDismissNotification];
    NSWindow *w = [self window];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
    if ([w _overlayView] == _listView)
        [w _setOverlayView:nil];
    _listView->_box = nil;
    [_listView release];
    _listView = nil;
    [self setNeedsDisplay:YES];
}
- (void)_windowResigned:(NSNotification *)n { [self _dismissList]; }
- (void)viewWillMoveToWindow:(NSWindow *)w
{
    if (w != [self window])
        [self _dismissList];
    [super viewWillMoveToWindow:w];
}
- (void)_listHighlighted:(NSInteger)row
{
    if (!_listView || row == _listView->_highlighted)
        return;
    _listView->_highlighted = row;
    [_listView setNeedsDisplay:YES];
    [self _postSelection:NSComboBoxSelectionIsChangingNotification];
}
- (void)_listChose:(NSInteger)row
{
    [[self retain] autorelease];
    [self selectItemAtIndex:row];
    [self _dismissList];
    [self sendAction:[self action] to:[self target]];
}
/* The keys while the list is open: the arrows move through it, Return
 * chooses, Escape closes; everything else is typed into the field. */
- (void)_listKeyDown:(NSEvent *)e
{
    NSString *c = [e charactersIgnoringModifiers];
    unichar ch = [c length] ? [c characterAtIndex:0] : 0;
    NSInteger n = [self numberOfItems], h = _listView->_highlighted;
    if (ch == NSUpArrowFunctionKey || ch == NSDownArrowFunctionKey) {
        NSInteger next = ch == NSDownArrowFunctionKey ? (h < 0 ? 0 : MIN(h + 1, n - 1)) : (h < 0 ? n - 1 : MAX(h - 1, 0));
        if (next >= 0 && next < n) {
            [self _listHighlighted:next];
            [[self _comboCell] scrollItemAtIndexToVisible:next];
            [self selectItemAtIndex:next];
        }
        return;
    }
    if (ch == '\r' || ch == 3) {
        if (h >= 0)
            [self _listChose:h];
        else
            [self _dismissList];
        return;
    }
    if (ch == 27) {
        [self _dismissList];
        return;
    }
    NSWindow *w = [self window];
    if (([e modifierFlags] & NSEventModifierFlagCommand) && [w performKeyEquivalent:e])
        return;
    if (ch == '\t') {
        [self _dismissList];
        [w sendEvent:e];
        return;
    }
    [self keyDown:e];
    if (_listView) {
        NSInteger match = [[self _comboCell] _indexOfString:[self stringValue]];
        if (match >= 0) {
            [[self _comboCell] scrollItemAtIndexToVisible:match];
            [self _listHighlighted:match];
        }
        [_listView setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    if (NSPointInRect(p, [self _buttonRect]) && [self isEnabled]) {
        if (_listView)
            [self _dismissList];
        else
            [self _openList];
        return;
    }
    [super mouseDown:e];
}
- (BOOL)resignFirstResponder
{
    [self _dismissList];
    return [super resignFirstResponder];
}

/* ---- typing ---- */

- (void)_noteTypedSelection
{
    NSComboBoxCell *c = [self _comboCell];
    NSInteger before = [c indexOfSelectedItem];
    NSInteger now = [c _indexOfString:[self stringValue]];
    if (now != before) {
        [c _setSelected:now];
        [self _postSelection:NSComboBoxSelectionDidChangeNotification];
    }
}
- (void)insertText:(id)string
{
    [super insertText:string];
    NSComboBoxCell *c = [self _comboCell];
    if ([c completes] && [self _isEditing]) {
        NSString *typed = [self stringValue];
        NSRange sel = [self _selectedTextRange];
        if (sel.length == 0 && sel.location == [typed length]) {
            NSString *done = [c completedString:typed];
            if ([done length] > [typed length] &&
                [[done substringToIndex:[typed length]] caseInsensitiveCompare:typed] == NSOrderedSame) {
                NSString *full = [typed stringByAppendingString:[done substringFromIndex:[typed length]]];
                [self _setEditingText:full selectedRange:NSMakeRange([typed length], [full length] - [typed length])];
            }
        }
    }
    [self _noteTypedSelection];
}
- (void)deleteBackward:(id)sender
{
    [super deleteBackward:sender];
    [self _noteTypedSelection];
}
/* With the list closed the arrows step through the items. */
- (void)_stepItems:(NSInteger)dir
{
    NSInteger n = [self numberOfItems];
    if (!n)
        return;
    NSInteger i = [self indexOfSelectedItem];
    if (i < 0)
        i = [[self _comboCell] _indexOfString:[self stringValue]];
    NSInteger next = i < 0 ? (dir > 0 ? 0 : n - 1) : MAX(0, MIN(n - 1, i + dir));
    if (next != i)
        [self selectItemAtIndex:next];
}
- (void)moveDown:(id)sender { [self _stepItems:1]; }
- (void)moveUp:(id)sender { [self _stepItems:-1]; }
@end
