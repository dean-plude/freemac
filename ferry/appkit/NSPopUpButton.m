/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: pop-up buttons (NSPopUpButton, NSPopUpButtonCell and
 * NSMenuItemCell) and the menu they open (AMenuView). Ferry's own code,
 * written from Apple's public API documentation. The button and its menu
 * are drawn to look like a current Mac's (a white bezel with the accent
 * coloured arrow box, a rounded menu panel with a shadow), with Ferry's own
 * drawing code; no Apple artwork is used.
 *
 * The menu is drawn inside the window, over its views, because Wayland
 * doesn't let a program put a window of its own where it likes. It doesn't
 * run an event loop of its own either: opening it returns at once, and the
 * choice comes later, from the window's events (press, drag and release
 * on an item, or click to open and click an item; the arrow keys, Return,
 * Space, Escape and typing an item's first letters).
 *
 * Nibs keep a pop-up button's settings in its cell. The keys read here
 * ("NSMenu", "NSPullDown", "NSPreferredEdge", "NSUsesItemFromMenu",
 * "NSAltersState", "NSArrowPosition", and the chosen item as "NSMenuItem"
 * or its number as "NSSelectedIndex") are the names given in descriptions
 * of the format published by developers and by the GNUstep project; no
 * Apple code was read. A nib that names them differently loads with the
 * defaults. */
#import "AInternal.h"

NSNotificationName const NSPopUpButtonWillPopUpNotification = @"NSPopUpButtonWillPopUpNotification";
NSNotificationName const NSPopUpButtonCellWillPopUpNotification = @"NSPopUpButtonCellWillPopUpNotification";

static NSColor *accent(void) { return [NSColor controlAccentColor]; }

/* A chevron pointing up or down, its tip at the middle of rect's top or
 * bottom edge (in an unflipped view). */
static void chevron(NSRect r, BOOL up, NSColor *color, CGFloat width)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    CGFloat tip = up ? NSMaxY(r) : NSMinY(r), base = up ? NSMinY(r) : NSMaxY(r);
    [p moveToPoint:NSMakePoint(NSMinX(r), base)];
    [p lineToPoint:NSMakePoint(NSMidX(r), tip)];
    [p lineToPoint:NSMakePoint(NSMaxX(r), base)];
    [p setLineWidth:width];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [color setStroke];
    [p stroke];
}

/* A check mark in a square rect (unflipped). */
static void check_mark(NSRect r, NSColor *color)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.12, NSMinY(r) + r.size.height * 0.5)];
    [p lineToPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.4, NSMinY(r) + r.size.height * 0.18)];
    [p lineToPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.9, NSMinY(r) + r.size.height * 0.85)];
    [p setLineWidth:1.8];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [color setStroke];
    [p stroke];
}

/* ---- the menu ---------------------------------------------------------------------- */

enum { MENU_ROW = 22, MENU_SEPARATOR = 11, MENU_PAD = 5, MENU_INDENT = 22, MENU_RIGHT = 18, MENU_RADIUS = 7 };

/* What a menu's items say about themselves before it opens: the delegate
 * may fill it in, and with autoenabling, an item with an action is enabled
 * when something in the responder chain takes the action and doesn't
 * refuse it in validateMenuItem:. Items without an action stay as they
 * are (in a pop-up button, choosing them sends the button's action). */
static void prepare_menu(NSMenu *menu)
{
    id delegate = [menu delegate];
    if ([delegate respondsToSelector:@selector(menuNeedsUpdate:)])
        [delegate menuNeedsUpdate:menu];
    if (![menu autoenablesItems])
        return;
    for (NSMenuItem *item in [menu itemArray]) {
        SEL action = [item action];
        if (!action || [item isSeparatorItem] || [item hasSubmenu])
            continue;
        id target = [NSApp targetForAction:action to:[item target] from:item];
        [item setEnabled:target && AValidateItem(target, item)];
    }
}

static BOOL choosable(NSMenuItem *item)
{
    return item && [item isEnabled] && ![item isHidden] && ![item isSeparatorItem] && ![item hasSubmenu];
}

@implementation AMenuView {
    NSMenu *_menu;
    id<AMenuOwner> _owner;
    NSFont *_font;
    NSRect _menuRect;
    NSInteger _first, _highlighted;
    BOOL _dragged, _pressedInMenu, _done;
    NSMutableArray *_rows;     /* NSValue: each item's row in window coordinates, empty when not shown */
    NSMutableString *_typed;
}

+ (AMenuView *)openMenu:(NSMenu *)menu forView:(NSView *)view rect:(NSRect)rect alignItem:(NSInteger)aligned
              skipFirst:(BOOL)skip font:(NSFont *)font owner:(id<AMenuOwner>)owner
{
    NSWindow *w = [view window];
    if (!w || !menu)
        return nil;
    id old = [w _overlayView];
    if ([old isKindOfClass:[AMenuView class]])
        [(AMenuView *)old dismiss];
    prepare_menu(menu);
    id delegate = [menu delegate];
    if ([delegate respondsToSelector:@selector(menuWillOpen:)])
        [delegate menuWillOpen:menu];
    NSSize size = [w frame].size;
    AMenuView *m = [[[AMenuView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)] autorelease];
    m->_menu = [menu retain];
    m->_owner = owner;
    m->_font = [font ?: ADefaultFont() retain];
    m->_first = skip ? 1 : 0;
    m->_highlighted = -1;
    m->_typed = [[NSMutableString alloc] init];
    [m _layoutFor:[view convertRect:rect toView:nil] aligned:aligned window:size];
    if (aligned >= 0 && choosable([menu itemAtIndex:aligned]))
        m->_highlighted = aligned;
    [w _setOverlayView:m];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:menu];
    return m;
}

- (void)dealloc
{
    [_menu release];
    [_font release];
    [_rows release];
    [_typed release];
    [super dealloc];
}

- (NSMenu *)menu { return _menu; }
- (NSInteger)highlightedIndex { return _highlighted; }
- (NSRect)menuRect { return _menuRect; }
- (BOOL)isOpaque { return NO; }

- (NSAttributedString *)_titleOf:(NSMenuItem *)item color:(NSColor *)color
{
    return AAttributed([item title], _font, color);
}

/* The rows, top to bottom, and where the panel goes: with an item lined
 * up over rect (its title where a pop-up button draws its own), or below
 * rect; then moved, if need be, to stay inside the window. */
- (void)_layoutFor:(NSRect)rect aligned:(NSInteger)aligned window:(NSSize)win
{
    NSInteger n = [_menu numberOfItems];
    CGFloat width = 0, height = 2 * MENU_PAD, alignedOffset = -1;
    CGFloat heights[n > 0 ? n : 1];
    for (NSInteger i = 0; i < n; i++) {
        NSMenuItem *item = [_menu itemAtIndex:i];
        heights[i] = 0;
        if (i < _first || [item isHidden])
            continue;
        if (i == aligned)
            alignedOffset = height - MENU_PAD + MENU_ROW / 2.0;
        if ([item isSeparatorItem]) {
            heights[i] = MENU_SEPARATOR;
        } else {
            heights[i] = MENU_ROW;
            CGFloat w = ceil(ALineSize([self _titleOf:item color:nil], NULL, NULL).width);
            if ([item image])
                w += fmin([[item image] size].width, 16) + 4;
            w += 10 * [item indentationLevel];
            if ([item hasSubmenu])
                w += 14;
            width = fmax(width, w);
        }
        height += heights[i];
    }
    width += 2 * MENU_PAD + MENU_INDENT + MENU_RIGHT;
    NSRect r;
    if (aligned >= 0 && alignedOffset >= 0) {
        /* a pop-up list: the item's title over the button's (8 points in
         * from the bezel), the item's row on the button's middle */
        CGFloat x = rect.origin.x + 8 - MENU_PAD - MENU_INDENT;
        width = fmax(width, NSMaxX(rect) - x + 4);
        CGFloat top = NSMidY(rect) + alignedOffset;
        r = NSMakeRect(x, top - height, width, height);
    } else {
        width = fmax(width, rect.size.width);
        r = NSMakeRect(rect.origin.x, rect.origin.y - 2 - height, width, height);
    }
    /* inside the window */
    if (NSMaxX(r) > win.width)
        r.origin.x = win.width - r.size.width;
    if (r.origin.x < 0)
        r.origin.x = 0;
    if (NSMaxY(r) > win.height)
        r.origin.y = win.height - r.size.height;
    if (r.origin.y < 0)     /* taller than the window: its top shows */
        r.origin.y = r.size.height > win.height ? win.height - r.size.height : 0;
    r = NSMakeRect(round(r.origin.x), round(r.origin.y), round(r.size.width), round(r.size.height));
    _menuRect = r;
    [_rows release];
    _rows = [[NSMutableArray alloc] init];
    CGFloat y = NSMaxY(r) - MENU_PAD;
    for (NSInteger i = 0; i < n; i++) {
        if (heights[i] <= 0) {
            [_rows addObject:[NSValue valueWithRect:NSZeroRect]];
            continue;
        }
        y -= heights[i];
        [_rows addObject:[NSValue valueWithRect:NSMakeRect(r.origin.x + MENU_PAD, y, r.size.width - 2 * MENU_PAD,
                                                           heights[i])]];
    }
}

- (NSRect)rectOfItemAtIndex:(NSInteger)index
{
    return index >= 0 && index < (NSInteger)[_rows count] ? [_rows[index] rectValue] : NSZeroRect;
}

- (NSInteger)_itemAt:(NSPoint)p
{
    for (NSInteger i = 0; i < (NSInteger)[_rows count]; i++) {
        NSRect r = [_rows[i] rectValue];
        if (r.size.height > 0 && NSPointInRect(p, r))
            return i;
    }
    return -1;
}

- (void)highlightItemAtIndex:(NSInteger)index
{
    if (index >= 0 && !choosable([_menu itemAtIndex:index]))
        index = -1;
    if (index == _highlighted)
        return;
    _highlighted = index;
    [self setNeedsDisplay:YES];
}

/* ---- closing ---- */

- (void)_closeWith:(NSMenuItem *)item
{
    if (_done)
        return;
    _done = YES;
    [self retain];
    NSWindow *w = [self window];
    if ([w _overlayView] == self) {
        [w _setOverlayView:nil];
        [[w contentView] setNeedsDisplay:YES];
        [[w _toolbarView] setNeedsDisplay:YES];
    }
    id delegate = [_menu delegate];
    if ([delegate respondsToSelector:@selector(menuDidClose:)])
        [delegate menuDidClose:_menu];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification object:_menu];
    [_owner _menuView:self didChooseItem:item];
    [self release];
}
- (void)chooseHighlightedItem
{
    NSMenuItem *item = [_menu itemAtIndex:_highlighted];
    if (choosable(item))
        [self _closeWith:item];
}
- (void)dismiss { [self _closeWith:nil]; }

/* ---- the mouse ---- */

- (NSPoint)_point:(NSEvent *)e { return [self convertPoint:[e locationInWindow] fromView:nil]; }

- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self _point:e];
    if (!NSPointInRect(p, _menuRect)) {
        [self dismiss];
        return;
    }
    _pressedInMenu = YES;
    [self highlightItemAtIndex:[self _itemAt:p]];
}
- (void)rightMouseDown:(NSEvent *)e { [self mouseDown:e]; }
- (void)mouseDragged:(NSEvent *)e
{
    _dragged = YES;
    [self highlightItemAtIndex:[self _itemAt:[self _point:e]]];
}
- (void)mouseMoved:(NSEvent *)e { [self highlightItemAtIndex:[self _itemAt:[self _point:e]]]; }
/* Releasing on an item chooses it, after a drag or a press in the menu.
 * The release of the click that opened the menu, with no drag, leaves it
 * open; after a drag, a release outside it closes it. */
- (void)mouseUp:(NSEvent *)e
{
    NSPoint p = [self _point:e];
    NSInteger i = [self _itemAt:p];
    if (i >= 0 && (_dragged || _pressedInMenu)) {
        [self highlightItemAtIndex:i];
        if (_highlighted == i) {
            [self chooseHighlightedItem];
            return;
        }
    }
    if (_dragged && !NSPointInRect(p, _menuRect))
        [self dismiss];
    _dragged = _pressedInMenu = NO;
}
- (void)scrollWheel:(NSEvent *)e {}

/* ---- the keyboard ---- */

- (BOOL)acceptsFirstResponder { return YES; }

- (void)_step:(NSInteger)dir
{
    NSInteger n = [_menu numberOfItems];
    if (n <= 0)
        return;
    NSInteger i = _highlighted;
    for (NSInteger tries = 0; tries < n; tries++) {
        i = i < 0 ? (dir > 0 ? _first : n - 1) : i + dir;
        if (i < _first || i >= n)
            return;          /* stops at the ends, as a Mac's menus do */
        if (choosable([_menu itemAtIndex:i])) {
            [self highlightItemAtIndex:i];
            return;
        }
    }
}

/* Typing selects the next item whose title starts with what was typed. */
- (void)_typeSelect:(NSString *)s
{
    [_typed appendString:[s lowercaseString]];
    NSInteger n = [_menu numberOfItems];
    for (int pass = 0; pass < 2; pass++) {
        for (NSInteger k = 0; k < n; k++) {
            NSInteger i = (_highlighted + (pass ? 1 : 0) + k + n) % n;
            if (i < _first)
                continue;
            NSMenuItem *item = [_menu itemAtIndex:i];
            if (choosable(item) && [[[item title] lowercaseString] hasPrefix:_typed]) {
                [self highlightItemAtIndex:i];
                return;
            }
        }
        /* nothing starts so: start again from this letter alone */
        [_typed setString:[s lowercaseString]];
    }
}

- (void)keyDown:(NSEvent *)e
{
    NSString *c = [e charactersIgnoringModifiers];
    unichar k = [c length] ? [c characterAtIndex:0] : 0;
    switch (k) {
    case NSUpArrowFunctionKey:
        [self _step:-1];
        break;
    case NSDownArrowFunctionKey:
        [self _step:1];
        break;
    case '\r':
    case 3:
    case ' ':
        if (_highlighted >= 0)
            [self chooseHighlightedItem];
        else if (k != ' ')
            [self dismiss];
        break;
    case 27:
        [self dismiss];
        break;
    default:
        if (k >= ' ' && k < 0xF700 && !([e modifierFlags] & NSEventModifierFlagCommand))
            [self _typeSelect:c];
        break;
    }
}

/* ---- drawing ---- */

- (void)drawRect:(NSRect)dirty
{
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(cg);
    CGColorRef shadow = CGColorCreateGenericRGB(0, 0, 0, 0.3);
    CGContextSetShadowWithColor(cg, CGSizeMake(0, -4), 12, shadow);
    CGColorRelease(shadow);
    AFillRoundedRect(_menuRect, MENU_RADIUS, [NSColor colorWithWhite:0.965 alpha:1], nil);
    CGContextRestoreGState(cg);
    AFillRoundedRect(_menuRect, MENU_RADIUS, nil, [NSColor colorWithWhite:0 alpha:0.14]);

    for (NSInteger i = 0; i < (NSInteger)[_rows count]; i++) {
        NSRect row = [_rows[i] rectValue];
        if (row.size.height <= 0)
            continue;
        NSMenuItem *item = [_menu itemAtIndex:i];
        if ([item isSeparatorItem]) {
            [[NSColor colorWithWhite:0 alpha:0.1] setFill];
            NSRectFill(NSMakeRect(row.origin.x + 5, floor(NSMidY(row)), row.size.width - 10, 1));
            continue;
        }
        BOOL lit = i == _highlighted;
        BOOL enabled = [item isEnabled];
        NSColor *text = lit ? [NSColor whiteColor] : enabled ? [NSColor colorWithWhite:0 alpha:0.85]
                                                             : [NSColor colorWithWhite:0 alpha:0.28];
        if (lit)
            AFillRoundedRect(row, 4, accent(), nil);
        if ([item state] == NSControlStateValueOn)
            check_mark(NSMakeRect(row.origin.x + 6, NSMidY(row) - 4.5, 10, 9), text);
        else if ([item state] == NSControlStateValueMixed) {
            [text setFill];
            NSRectFill(NSMakeRect(row.origin.x + 7, floor(NSMidY(row)) - 1, 8, 2));
        }
        CGFloat x = row.origin.x + MENU_INDENT + 10 * [item indentationLevel];
        if ([item image]) {
            NSSize s = [[item image] size];
            CGFloat k = fmin(1, fmin(16 / fmax(s.width, 1), 16 / fmax(s.height, 1)));
            NSRect ir = NSMakeRect(x, round(NSMidY(row) - s.height * k / 2), s.width * k, s.height * k);
            [[item image] _drawInControlRect:ir color:text fraction:enabled ? 1 : 0.4];
            x += ir.size.width + 4;
        }
        CGFloat a, d;
        NSAttributedString *t = [self _titleOf:item color:text];
        ALineSize(t, &a, &d);
        CGContextSaveGState(cg);
        CGContextClipToRect(cg, NSMakeRect(row.origin.x, row.origin.y, row.size.width - 8, row.size.height));
        ADrawLine(t, x, floor(NSMidY(row) - (a + d) / 2 + d));
        CGContextRestoreGState(cg);
        if ([item hasSubmenu]) {
            NSBezierPath *p = [NSBezierPath bezierPath];
            CGFloat cx = NSMaxX(row) - 10, cy = NSMidY(row);
            [p moveToPoint:NSMakePoint(cx - 3, cy + 4)];
            [p lineToPoint:NSMakePoint(cx + 1, cy)];
            [p lineToPoint:NSMakePoint(cx - 3, cy - 4)];
            [p setLineWidth:1.5];
            [text setStroke];
            [p stroke];
        }
    }
}
@end

/* ---- NSMenuItemCell ------------------------------------------------------------------ */

@implementation NSMenuItemCell {
    NSMenuItem *_menuItem;
}
- (void)dealloc
{
    [_menuItem release];
    [super dealloc];
}
- (NSMenuItem *)menuItem { return _menuItem; }
- (void)setMenuItem:(NSMenuItem *)item
{
    [item retain];
    [_menuItem release];
    _menuItem = item;
}
@end

/* ---- NSPopUpButtonCell ---------------------------------------------------------------- */

@interface NSPopUpButtonCell (FerryPrivate) <AMenuOwner>
- (NSString *)_shownTitle;
- (NSMenuItem *)_shownItem;
- (void)_openForView:(NSView *)view frame:(NSRect)frame;
- (BOOL)_isOpen;
@end

@implementation NSPopUpButtonCell {
    NSMenu *_menu;
    NSString *_ownTitle;
    NSMenuItem *_selected;
    BOOL _pullsDown, _usesItemFromMenu, _altersState;
    NSRectEdge _edge;
    NSPopUpArrowPosition _arrow;
    AMenuView *_open;
}

- (instancetype)initTextCell:(NSString *)string { return [self initTextCell:string pullsDown:NO]; }
- (instancetype)initTextCell:(NSString *)string pullsDown:(BOOL)pullDown
{
    if ((self = [super initTextCell:@""])) {
        _menu = [[NSMenu alloc] initWithTitle:@""];
        _pullsDown = pullDown;
        _usesItemFromMenu = YES;
        _altersState = YES;
        _edge = NSMaxYEdge;
        _arrow = NSPopUpArrowAtCenter;
        [self setAlignment:NSTextAlignmentLeft];
        if ([string length])
            [self addItemWithTitle:string];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    [_menu release];
    _usesItemFromMenu = YES;
    _altersState = YES;
    _edge = NSMaxYEdge;
    _arrow = NSPopUpArrowAtCenter;
    NSMenu *menu = [c containsValueForKey:@"NSMenu"] ? [c decodeObjectForKey:@"NSMenu"] : nil;
    _menu = [menu isKindOfClass:[NSMenu class]] ? [menu retain] : [[NSMenu alloc] initWithTitle:@""];
    if ([c containsValueForKey:@"NSPullDown"])
        _pullsDown = [c decodeBoolForKey:@"NSPullDown"];
    if ([c containsValueForKey:@"NSPreferredEdge"])
        _edge = (NSRectEdge)[c decodeIntegerForKey:@"NSPreferredEdge"];
    if ([c containsValueForKey:@"NSUsesItemFromMenu"])
        _usesItemFromMenu = [c decodeBoolForKey:@"NSUsesItemFromMenu"];
    if ([c containsValueForKey:@"NSAltersState"])
        _altersState = [c decodeBoolForKey:@"NSAltersState"];
    if ([c containsValueForKey:@"NSArrowPosition"])
        _arrow = (NSPopUpArrowPosition)[c decodeIntegerForKey:@"NSArrowPosition"];
    NSMenuItem *item = [c containsValueForKey:@"NSMenuItem"] ? [c decodeObjectForKey:@"NSMenuItem"] : nil;
    if ([item isKindOfClass:[NSMenuItem class]] && [_menu indexOfItem:item] >= 0)
        _selected = [item retain];
    else if ([c containsValueForKey:@"NSSelectedIndex"])
        _selected = [[_menu itemAtIndex:[c decodeIntegerForKey:@"NSSelectedIndex"]] retain];
    if (!_selected && !_pullsDown)
        _selected = [[_menu itemAtIndex:0] retain];
    if (_selected && _altersState && !_pullsDown)
        for (NSMenuItem *i in [_menu itemArray])
            [i setState:i == _selected ? NSControlStateValueOn : NSControlStateValueOff];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [super encodeWithCoder:c];
    [c encodeObject:_menu forKey:@"NSMenu"];
    [c encodeBool:_pullsDown forKey:@"NSPullDown"];
    [c encodeInteger:_edge forKey:@"NSPreferredEdge"];
    [c encodeBool:_usesItemFromMenu forKey:@"NSUsesItemFromMenu"];
    [c encodeBool:_altersState forKey:@"NSAltersState"];
    [c encodeInteger:_arrow forKey:@"NSArrowPosition"];
    [c encodeInteger:[self indexOfSelectedItem] forKey:@"NSSelectedIndex"];
}

- (void)dealloc
{
    [_open dismiss];
    [_menu release];
    [_selected release];
    [_ownTitle release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSPopUpButtonCell *c = [super copyWithZone:zone];
    [c->_menu release];
    c->_menu = [_menu copy];
    c->_ownTitle = [_ownTitle copy];
    c->_selected = [[c->_menu itemAtIndex:[self indexOfSelectedItem]] retain];
    c->_pullsDown = _pullsDown;
    c->_usesItemFromMenu = _usesItemFromMenu;
    c->_altersState = _altersState;
    c->_edge = _edge;
    c->_arrow = _arrow;
    c->_open = nil;
    return c;
}

- (void)_changed { [[self controlView] setNeedsDisplay:YES]; }

/* A pop-up list always has an item chosen while it has any. */
- (void)_fixSelection
{
    if (_selected && [_menu indexOfItem:_selected] < 0) {
        [_selected release];
        _selected = nil;
    }
    if (!_selected && !_pullsDown && [_menu numberOfItems] > 0)
        [self selectItemAtIndex:0];
    [self _changed];
}

- (NSMenu *)menu { return _menu; }
- (void)setMenu:(NSMenu *)menu
{
    if (menu == _menu)
        return;
    [_open dismiss];
    [menu retain];
    [_menu release];
    _menu = menu ?: [[NSMenu alloc] initWithTitle:@""];
    [_selected release];
    _selected = nil;
    for (NSMenuItem *i in [_menu itemArray])
        if (!_selected && [i state] == NSControlStateValueOn && !_pullsDown)
            _selected = [i retain];
    [self _fixSelection];
}
- (BOOL)pullsDown { return _pullsDown; }
- (void)setPullsDown:(BOOL)flag
{
    _pullsDown = flag;
    [self _fixSelection];
}
- (BOOL)autoenablesItems { return [_menu autoenablesItems]; }
- (void)setAutoenablesItems:(BOOL)flag { [_menu setAutoenablesItems:flag]; }
- (BOOL)usesItemFromMenu { return _usesItemFromMenu; }
- (void)setUsesItemFromMenu:(BOOL)flag
{
    _usesItemFromMenu = flag;
    [self _changed];
}
- (BOOL)altersStateOfSelectedItem { return _altersState; }
- (void)setAltersStateOfSelectedItem:(BOOL)flag
{
    _altersState = flag;
    if (!flag)
        [_selected setState:NSControlStateValueOff];
    else if (!_pullsDown)
        [_selected setState:NSControlStateValueOn];
}
- (NSRectEdge)preferredEdge { return _edge; }
- (void)setPreferredEdge:(NSRectEdge)edge { _edge = edge; }
- (NSPopUpArrowPosition)arrowPosition { return _arrow; }
- (void)setArrowPosition:(NSPopUpArrowPosition)position
{
    _arrow = position;
    [self _changed];
}

/* ---- items ---- */

/* Adding an item with a title already in the menu removes the old one
 * first, as the documentation says. */
- (void)addItemWithTitle:(NSString *)title { [self insertItemWithTitle:title atIndex:[_menu numberOfItems]]; }
- (void)addItemsWithTitles:(NSArray *)titles
{
    for (NSString *t in titles)
        [self addItemWithTitle:t];
}
- (void)insertItemWithTitle:(NSString *)title atIndex:(NSInteger)index
{
    NSInteger old = [_menu indexOfItemWithTitle:title ?: @""];
    if (old >= 0) {
        [_menu removeItemAtIndex:old];
        if (old < index)
            index--;
    }
    if (index < 0 || index > [_menu numberOfItems])
        index = [_menu numberOfItems];
    [_menu insertItemWithTitle:title ?: @"" action:NULL keyEquivalent:@"" atIndex:index];
    [self _fixSelection];
}
- (void)removeItemWithTitle:(NSString *)title
{
    NSInteger i = [_menu indexOfItemWithTitle:title];
    if (i >= 0)
        [self removeItemAtIndex:i];
}
- (void)removeItemAtIndex:(NSInteger)index
{
    if (index < 0 || index >= [_menu numberOfItems])
        return;
    [_menu removeItemAtIndex:index];
    [self _fixSelection];
}
- (void)removeAllItems
{
    [_menu removeAllItems];
    [self _fixSelection];
}
- (NSArray *)itemArray { return [_menu itemArray]; }
- (NSInteger)numberOfItems { return [_menu numberOfItems]; }
- (NSInteger)indexOfItem:(NSMenuItem *)item { return [_menu indexOfItem:item]; }
- (NSInteger)indexOfItemWithTitle:(NSString *)title { return [_menu indexOfItemWithTitle:title]; }
- (NSInteger)indexOfItemWithTag:(NSInteger)tag
{
    NSMenuItem *i = [_menu itemWithTag:tag];
    return i ? [_menu indexOfItem:i] : -1;
}
- (NSInteger)indexOfItemWithRepresentedObject:(id)obj
{
    NSArray *items = [_menu itemArray];
    for (NSUInteger i = 0; i < [items count]; i++) {
        id r = [items[i] representedObject];
        if (r == obj || [r isEqual:obj])
            return (NSInteger)i;
    }
    return -1;
}
- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)action
{
    NSArray *items = [_menu itemArray];
    for (NSUInteger i = 0; i < [items count]; i++)
        if ([items[i] target] == target && (!action || [items[i] action] == action))
            return (NSInteger)i;
    return -1;
}
- (NSMenuItem *)itemAtIndex:(NSInteger)index { return [_menu itemAtIndex:index]; }
- (NSMenuItem *)itemWithTitle:(NSString *)title { return [_menu itemWithTitle:title]; }
- (NSMenuItem *)lastItem { return [_menu itemAtIndex:[_menu numberOfItems] - 1]; }

/* ---- the chosen item ---- */

- (void)selectItem:(NSMenuItem *)item
{
    if (item && [_menu indexOfItem:item] < 0)
        return;
    if (_altersState && !_pullsDown) {
        [_selected setState:NSControlStateValueOff];
        [item setState:NSControlStateValueOn];
    }
    [item retain];
    [_selected release];
    _selected = item;
    [self _changed];
}
- (void)selectItemAtIndex:(NSInteger)index { [self selectItem:[_menu itemAtIndex:index]]; }
- (BOOL)selectItemWithTag:(NSInteger)tag
{
    NSMenuItem *item = [_menu itemWithTag:tag];
    if (!item)
        return NO;
    [self selectItem:item];
    return YES;
}
- (void)selectItemWithTitle:(NSString *)title { [self selectItem:[_menu itemWithTitle:title]]; }
- (NSMenuItem *)selectedItem { return [_menu indexOfItem:_selected] >= 0 ? _selected : nil; }
- (NSInteger)indexOfSelectedItem { return _selected ? [_menu indexOfItem:_selected] : -1; }
- (NSInteger)selectedTag { return [self selectedItem] ? [[self selectedItem] tag] : -1; }
- (void)synchronizeTitleAndSelectedItem
{
    [self _fixSelection];
    [self _changed];
}
- (NSString *)itemTitleAtIndex:(NSInteger)index { return [[_menu itemAtIndex:index] title]; }
- (NSArray *)itemTitles
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSMenuItem *i in [_menu itemArray])
        [a addObject:[i title]];
    return a;
}
- (NSString *)titleOfSelectedItem { return [[self selectedItem] title] ?: @""; }

/* What the button shows: the chosen item of a pop-up list, the first item
 * of a pull-down list, or the cell's own title when it doesn't use the
 * menu's items. */
- (NSMenuItem *)_shownItem
{
    if (!_usesItemFromMenu)
        return nil;
    return _pullsDown ? [_menu itemAtIndex:0] : [self selectedItem];
}
- (NSString *)_shownTitle
{
    if (!_usesItemFromMenu)
        return _ownTitle ?: @"";
    return [[self _shownItem] title] ?: @"";
}
- (NSString *)title { return [self _shownTitle]; }
/* For a pop-up list, the item with that title is chosen, added if need
 * be; a pull-down list's title is its first item's. */
- (void)setTitle:(NSString *)title
{
    if (!_usesItemFromMenu) {
        [_ownTitle release];
        _ownTitle = [title copy];
    } else if (_pullsDown) {
        if ([_menu numberOfItems] > 0)
            [[_menu itemAtIndex:0] setTitle:title ?: @""];
        else
            [_menu addItemWithTitle:title ?: @"" action:NULL keyEquivalent:@""];
    } else {
        if ([_menu indexOfItemWithTitle:title ?: @""] < 0)
            [self addItemWithTitle:title];
        [self selectItemWithTitle:title];
    }
    [self _changed];
}
- (id)objectValue { return @([self indexOfSelectedItem]); }
/* A number chooses that item; a title (a nib keeps the shown one) is kept
 * as the cell's own, for when it doesn't use the menu's items. */
- (void)setObjectValue:(id)value
{
    if ([value isKindOfClass:[NSNumber class]]) {
        [self selectItemAtIndex:[value integerValue]];
    } else if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSAttributedString class]]) {
        [_ownTitle release];
        _ownTitle = [[value isKindOfClass:[NSString class]] ? value : [value string] copy];
    }
}
- (NSString *)stringValue { return [NSString stringWithFormat:@"%ld", (long)[self indexOfSelectedItem]]; }

/* ---- opening ---- */

- (BOOL)_isOpen { return _open != nil; }
- (void)_openForView:(NSView *)view frame:(NSRect)frame
{
    if (_open || !view)
        return;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopUpButtonCellWillPopUpNotification object:self];
    if ([view isKindOfClass:[NSPopUpButton class]])
        [[NSNotificationCenter defaultCenter] postNotificationName:NSPopUpButtonWillPopUpNotification object:view];
    NSInteger aligned = _pullsDown ? -1 : [self indexOfSelectedItem];
    NSFont *font = [self font] ?: ([view respondsToSelector:@selector(font)] ? [(NSControl *)view font] : nil);
    _open = [AMenuView openMenu:_menu forView:view rect:frame alignItem:aligned skipFirst:_pullsDown font:font
                          owner:self];
    if (_open && [view respondsToSelector:@selector(setHighlighted:)])
        [(NSControl *)view setHighlighted:YES];
}
- (void)attachPopUpWithFrame:(NSRect)frame inView:(NSView *)view { [self _openForView:view frame:frame]; }
- (void)performClickWithFrame:(NSRect)frame inView:(NSView *)view { [self _openForView:view frame:frame]; }
- (void)dismissPopUp { [_open dismiss]; }

/* The menu closed: a chosen item becomes the selection (a pull-down list
 * remembers it too), then its own action is sent if it has one, else the
 * button's. */
- (void)_menuView:(AMenuView *)menu didChooseItem:(NSMenuItem *)item
{
    _open = nil;
    NSView *view = [self controlView];
    if ([view respondsToSelector:@selector(setHighlighted:)])
        [(NSControl *)view setHighlighted:NO];
    if (!item)
        return;
    [self selectItem:item];
    if (!_pullsDown)
        [self synchronizeTitleAndSelectedItem];
    if (view)
        ABindingsPush(view, NO);   /* its selection bindings learn the choice */
    if ([item action])
        [NSApp sendAction:[item action] to:[item target] from:item];
    else if ([view isKindOfClass:[NSControl class]])
        [(NSControl *)view sendAction:[(NSControl *)view action] to:[(NSControl *)view target]];
    else if ([self action])
        [NSApp sendAction:[self action] to:[self target] from:self];
}
@end

/* ---- NSPopUpButton ------------------------------------------------------------------- */

@implementation NSPopUpButton {
    BOOL _loading;
}

+ (Class)cellClass { return [NSPopUpButtonCell class]; }

+ (instancetype)popUpButtonWithMenu:(NSMenu *)menu target:(id)target action:(SEL)action
{
    NSPopUpButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 25) pullsDown:NO] autorelease];
    [b setMenu:menu];
    [b setTarget:target];
    [b setAction:action];
    [b sizeToFit];
    return b;
}
+ (instancetype)pullDownButtonWithTitle:(NSString *)title menu:(NSMenu *)menu
{
    NSPopUpButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 25) pullsDown:YES] autorelease];
    /* the title is shown by an item put first, which the menu doesn't show */
    NSMenu *m = menu ?: [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [m insertItemWithTitle:title ?: @"" action:NULL keyEquivalent:@"" atIndex:0];
    [b setMenu:m];
    [b sizeToFit];
    return b;
}

- (NSPopUpButtonCell *)_popUpCell { return (NSPopUpButtonCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    [super setTitle:@""];
    if (!_loading && ![[self cell] isKindOfClass:[NSPopUpButtonCell class]]) {
        NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
        [self setCell:cell];
        [cell release];
    }
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame pullsDown:NO]; }
- (instancetype)initWithFrame:(NSRect)frame pullsDown:(BOOL)flag
{
    if ((self = [super initWithFrame:frame]))
        [[self _popUpCell] setPullsDown:flag];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    _loading = YES;
    self = [super initWithCoder:coder];
    if (!self)
        return nil;
    _loading = NO;
    if (![[self cell] isKindOfClass:[NSPopUpButtonCell class]]) {
        NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
        [self setCell:cell];
        [cell release];
    }
    [[self _popUpCell] synchronizeTitleAndSelectedItem];
    return self;
}

/* The settings are the cell's. */
- (NSMenu *)menu { return [[self _popUpCell] menu]; }
- (void)setMenu:(NSMenu *)menu { [[self _popUpCell] setMenu:menu]; }
- (BOOL)pullsDown { return [[self _popUpCell] pullsDown]; }
- (void)setPullsDown:(BOOL)flag { [[self _popUpCell] setPullsDown:flag]; }
- (BOOL)autoenablesItems { return [[self _popUpCell] autoenablesItems]; }
- (void)setAutoenablesItems:(BOOL)flag { [[self _popUpCell] setAutoenablesItems:flag]; }
- (BOOL)usesItemFromMenu { return [[self _popUpCell] usesItemFromMenu]; }
- (void)setUsesItemFromMenu:(BOOL)flag { [[self _popUpCell] setUsesItemFromMenu:flag]; }
- (NSRectEdge)preferredEdge { return [[self _popUpCell] preferredEdge]; }
- (void)setPreferredEdge:(NSRectEdge)edge { [[self _popUpCell] setPreferredEdge:edge]; }
- (void)addItemWithTitle:(NSString *)title { [[self _popUpCell] addItemWithTitle:title]; }
- (void)addItemsWithTitles:(NSArray *)titles { [[self _popUpCell] addItemsWithTitles:titles]; }
- (void)insertItemWithTitle:(NSString *)title atIndex:(NSInteger)index
{
    [[self _popUpCell] insertItemWithTitle:title atIndex:index];
}
- (void)removeItemWithTitle:(NSString *)title { [[self _popUpCell] removeItemWithTitle:title]; }
- (void)removeItemAtIndex:(NSInteger)index { [[self _popUpCell] removeItemAtIndex:index]; }
- (void)removeAllItems { [[self _popUpCell] removeAllItems]; }
- (NSArray *)itemArray { return [[self _popUpCell] itemArray]; }
- (NSInteger)numberOfItems { return [[self _popUpCell] numberOfItems]; }
- (NSInteger)indexOfItem:(NSMenuItem *)item { return [[self _popUpCell] indexOfItem:item]; }
- (NSInteger)indexOfItemWithTitle:(NSString *)title { return [[self _popUpCell] indexOfItemWithTitle:title]; }
- (NSInteger)indexOfItemWithTag:(NSInteger)tag { return [[self _popUpCell] indexOfItemWithTag:tag]; }
- (NSInteger)indexOfItemWithRepresentedObject:(id)obj
{
    return [[self _popUpCell] indexOfItemWithRepresentedObject:obj];
}
- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)action
{
    return [[self _popUpCell] indexOfItemWithTarget:target andAction:action];
}
- (NSMenuItem *)itemAtIndex:(NSInteger)index { return [[self _popUpCell] itemAtIndex:index]; }
- (NSMenuItem *)itemWithTitle:(NSString *)title { return [[self _popUpCell] itemWithTitle:title]; }
- (NSMenuItem *)lastItem { return [[self _popUpCell] lastItem]; }
- (void)selectItem:(NSMenuItem *)item { [[self _popUpCell] selectItem:item]; }
- (void)selectItemAtIndex:(NSInteger)index { [[self _popUpCell] selectItemAtIndex:index]; }
- (BOOL)selectItemWithTag:(NSInteger)tag { return [[self _popUpCell] selectItemWithTag:tag]; }
- (void)selectItemWithTitle:(NSString *)title { [[self _popUpCell] selectItemWithTitle:title]; }
- (NSMenuItem *)selectedItem { return [[self _popUpCell] selectedItem]; }
- (NSInteger)indexOfSelectedItem { return [[self _popUpCell] indexOfSelectedItem]; }
- (NSInteger)selectedTag { return [[self _popUpCell] selectedTag]; }
- (void)synchronizeTitleAndSelectedItem { [[self _popUpCell] synchronizeTitleAndSelectedItem]; }
- (NSString *)itemTitleAtIndex:(NSInteger)index { return [[self _popUpCell] itemTitleAtIndex:index]; }
- (NSArray *)itemTitles { return [[self _popUpCell] itemTitles]; }
- (NSString *)titleOfSelectedItem { return [[self _popUpCell] titleOfSelectedItem]; }

- (NSString *)title { return [[self _popUpCell] _shownTitle]; }
- (void)setTitle:(NSString *)title
{
    if (_loading)
        return;
    [[self _popUpCell] setTitle:title];
}
- (NSAttributedString *)attributedTitle { return AAttributed([self title], [self font], nil); }

/* The value is the chosen item's number. */
- (id)objectValue { return @([self indexOfSelectedItem]); }
- (void)setObjectValue:(id)v { [self selectItemAtIndex:[v integerValue]]; }
- (NSString *)stringValue { return [NSString stringWithFormat:@"%ld", (long)[self indexOfSelectedItem]]; }
- (void)setStringValue:(NSString *)s { [self selectItemAtIndex:[s integerValue]]; }
- (int)intValue { return (int)[self indexOfSelectedItem]; }
- (void)setIntValue:(int)v { [self selectItemAtIndex:v]; }
- (NSInteger)integerValue { return [self indexOfSelectedItem]; }
- (void)setIntegerValue:(NSInteger)v { [self selectItemAtIndex:v]; }
- (NSControlStateValue)state { return NSControlStateValueOff; }
- (void)setState:(NSControlStateValue)s {}
- (void)setNextState {}

/* ---- the mouse and keys ---- */

- (NSRect)_bezelRect
{
    NSRect b = [self bounds];
    CGFloat h = fmin(b.size.height - 2, 21);
    return NSMakeRect(b.origin.x + 3, round(NSMidY(b) - h / 2), b.size.width - 6, h);
}

- (void)_open
{
    if (![self isEnabled] || [[self _popUpCell] _isOpen])
        return;
    [[self _popUpCell] _openForView:self frame:[self _bezelRect]];
}
- (void)mouseDown:(NSEvent *)event { [self _open]; }
- (void)_forward:(SEL)sel event:(NSEvent *)event
{
    NSView *m = [[self window] _overlayView];
    if ([m isKindOfClass:[AMenuView class]])
        ((void (*)(id, SEL, id))objc_msgSend)(m, sel, event);
}
/* The press that opened the menu goes on in it. */
- (void)mouseDragged:(NSEvent *)event { [self _forward:@selector(mouseDragged:) event:event]; }
- (void)mouseUp:(NSEvent *)event { [self _forward:@selector(mouseUp:) event:event]; }
/* Opening returns at once; the choice comes from later events. */
- (void)performClick:(id)sender { [self _open]; }
- (BOOL)acceptsFirstResponder { return [self isEnabled] && [NSApp isFullKeyboardAccessEnabled]; }
- (void)keyDown:(NSEvent *)event
{
    NSString *c = [event charactersIgnoringModifiers];
    unichar k = [c length] ? [c characterAtIndex:0] : 0;
    if (k == ' ' || k == NSUpArrowFunctionKey || k == NSDownArrowFunctionKey)
        [self _open];
    else
        [super keyDown:event];
}

- (NSSize)intrinsicContentSize
{
    NSFont *font = [self font];
    CGFloat w = 0;
    for (NSMenuItem *item in [self itemArray]) {
        if ([item isSeparatorItem])
            continue;
        CGFloat iw = ALineSize(AAttributed([item title], font, nil), NULL, NULL).width;
        if ([item image])
            iw += fmin([[item image] size].width, 16) + 4;
        w = fmax(w, iw);
    }
    if (![self usesItemFromMenu])
        w = fmax(w, ALineSize(AAttributed([self title], font, nil), NULL, NULL).width);
    return NSMakeSize(fmax(ceil(w) + 8 + 4 + 16 + 2 + 6 + 6, 50), 25);
}

/* ---- drawing ---- */

- (void)drawRect:(NSRect)dirty
{
    NSPopUpButtonCell *cell = [self _popUpCell];
    BOOL enabled = [self isEnabled], pressed = [self isHighlighted], pulls = [cell pullsDown];
    CGFloat dim = enabled ? 1 : 0.45;
    BOOL focused = [[self window] firstResponder] == self && [[self window] isKeyWindow];
    NSRect bezel = [self _bezelRect];
    BOOL up = ![self isFlipped];       /* "up" on the screen */
    BOOL dark = AViewIsDark(self);   /* in a HUD panel: light on dark */
    NSColor *text = [NSColor colorWithWhite:dark ? 1 : 0 alpha:(dark ? 0.9 : 0.85) * dim];
    NSRect arrows;
    if ([self isBordered]) {
        NSColor *fill = dark ? [NSColor colorWithWhite:1 alpha:pressed ? 0.3 : 0.18]
                      : pressed ? [NSColor colorWithWhite:0.86 alpha:1] : [NSColor whiteColor];
        CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
        CGContextSaveGState(cg);
        CGColorRef shadow = CGColorCreateGenericRGB(0, 0, 0, 0.12 * dim);
        CGContextSetShadowWithColor(cg, CGSizeMake(0, -0.5), 1, shadow);
        CGColorRelease(shadow);
        AFillRoundedRect(bezel, 5, [fill colorWithAlphaComponent:[fill alphaComponent] * dim], nil);
        CGContextRestoreGState(cg);
        AFillRoundedRect(bezel, 5, nil, [NSColor colorWithWhite:dark ? 1 : 0 alpha:(dark ? 0.12 : 0.16) * dim]);
        if (focused)
            AFillRoundedRect(NSInsetRect(bezel, -2.5, -2.5), 7.5, nil, [NSColor keyboardFocusIndicatorColor]);
        /* the arrow box at the right end */
        CGFloat s = bezel.size.height - 4;
        arrows = NSMakeRect(NSMaxX(bezel) - 2 - s, bezel.origin.y + 2, s, s);
        if ([cell arrowPosition] != NSPopUpNoArrow) {
            NSColor *box = pressed ? [accent() shadowWithLevel:0.2] : accent();
            AFillRoundedRect(arrows, 4, [box colorWithAlphaComponent:dim], nil);
            NSColor *white = [NSColor colorWithWhite:1 alpha:dim];
            if (pulls) {
                chevron(NSMakeRect(NSMidX(arrows) - 3.5, NSMidY(arrows) - 2, 7, 3.5), !up, white, 1.6);
            } else {
                chevron(NSMakeRect(NSMidX(arrows) - 3, NSMidY(arrows) + (up ? 1.5 : -4.5), 6, 3), up, white, 1.5);
                chevron(NSMakeRect(NSMidX(arrows) - 3, NSMidY(arrows) + (up ? -4.5 : 1.5), 6, 3), !up, white, 1.5);
            }
        }
    } else {
        arrows = NSMakeRect(NSMaxX(bezel) - 12, bezel.origin.y, 10, bezel.size.height);
        NSColor *gray = [NSColor colorWithWhite:dark ? 1 : 0 alpha:(pressed ? 0.8 : dark ? 0.6 : 0.5) * dim];
        if ([cell arrowPosition] != NSPopUpNoArrow) {
            if (pulls) {
                chevron(NSMakeRect(NSMidX(arrows) - 3, NSMidY(arrows) - 2, 6, 3), !up, gray, 1.4);
            } else {
                chevron(NSMakeRect(NSMidX(arrows) - 2.5, NSMidY(arrows) + (up ? 1.5 : -4), 5, 2.5), up, gray, 1.3);
                chevron(NSMakeRect(NSMidX(arrows) - 2.5, NSMidY(arrows) + (up ? -4 : 1.5), 5, 2.5), !up, gray, 1.3);
            }
        }
        if (pressed)
            text = [NSColor colorWithWhite:dark ? 1 : 0 alpha:dim];
    }
    /* the title, and the item's image before it */
    CGFloat x = bezel.origin.x + 8, right = arrows.origin.x - 4;
    NSMenuItem *shown = [cell _shownItem];
    NSImage *image = [shown image];
    if (image) {
        NSSize s = [image size];
        CGFloat k = fmin(1, fmin(16 / fmax(s.width, 1), 16 / fmax(s.height, 1)));
        NSRect ir = NSMakeRect(x, round(NSMidY(bezel) - s.height * k / 2), s.width * k, s.height * k);
        [image _drawInControlRect:ir color:text fraction:dim];
        x += ir.size.width + 4;
    }
    NSAttributedString *t = AAttributed([self title], [self font], text);
    CGFloat a, d;
    ALineSize(t, &a, &d);
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, NSMakeRect(x, bezel.origin.y, fmax(right - x, 0), bezel.size.height));
    CGFloat baseline = [self isFlipped] ? ceil(NSMidY(bezel) + (a + d) / 2 - d) : floor(NSMidY(bezel) - (a + d) / 2 + d);
    ADrawLine(t, x, baseline);
    CGContextRestoreGState(cg);
}
@end

/* ---- cancelling a menu (freemac 1.221, Ferry 0.45.0) ---------------------------------- */

/* Closes the menu where it is open over one of the program's windows (a
 * pop-up's, a pull-down's or a contextual menu), as if the person had
 * clicked away: nothing is chosen, and the delegate hears menuDidClose:.
 * A status item's menu is the desktop's and stays open. */
@implementation NSMenu (FerryTracking)
- (void)cancelTracking
{
    for (NSWindow *w in [[[NSApp windows] copy] autorelease]) {
        NSView *ov = [w _overlayView];
        if (![ov isKindOfClass:[AMenuView class]])
            continue;
        for (NSMenu *m = [(AMenuView *)ov menu]; m; m = [m supermenu])
            if (m == self) {
                [(AMenuView *)ov dismiss];
                break;
            }
    }
}
- (void)cancelTrackingWithoutAnimation { [self cancelTracking]; }
@end
