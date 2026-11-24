/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: search fields (NSSearchField, NSSearchFieldCell). Ferry's
 * own code, written from Apple's public API documentation. A search field
 * is a text field drawn to look like a current Mac's (a rounded field with
 * a magnifying glass at the start and, while there is text, a round clear
 * button at the end), with Ferry's own drawing code; it edits text as
 * NSTextField does (NSControl.m).
 *
 * It sends its action as the user types, a moment after they stop (or at
 * once, with sendsSearchStringImmediately), or only on Return, with
 * sendsWholeSearchString. The clear button and Escape empty it and send the
 * action. Searches sent with Return are kept as recent searches (saved in
 * the user defaults under the autosave name), and a search menu template
 * is shown from the magnifying glass with them filled in at the places
 * its tagged items mark.
 *
 * The cell's nib keys read here ("NSMaximumRecents",
 * "NSSendsWholeSearchString", "NSSendsSearchStringImmediately",
 * "NSRecentsAutosaveName") are the names given in descriptions of the
 * format published by developers and by the GNUstep project; no Apple code
 * was read. A nib that names them differently loads with the defaults. */
#import "AInternal.h"

/* ---- NSSearchFieldCell ---------------------------------------------------------------- */

@implementation NSSearchFieldCell {
    NSButtonCell *_searchButton, *_cancelButton;
    NSMenu *_template;
    BOOL _whole, _immediately;
    NSInteger _maxRecents;
    NSArray *_recents;
    NSString *_autosave;
}

- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super initTextCell:string])) {
        _maxRecents = 10;
        [self setEditable:YES];
        [self setBezeled:YES];
        [self resetSearchButtonCell];
        [self resetCancelButtonCell];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    if ([c containsValueForKey:@"NSMaximumRecents"])
        _maxRecents = [c decodeIntegerForKey:@"NSMaximumRecents"];
    _whole = [c decodeBoolForKey:@"NSSendsWholeSearchString"];
    _immediately = [c decodeBoolForKey:@"NSSendsSearchStringImmediately"];
    NSString *name = [c containsValueForKey:@"NSRecentsAutosaveName"] ? [c decodeObjectForKey:@"NSRecentsAutosaveName"] : nil;
    if ([name isKindOfClass:[NSString class]])
        [self setRecentsAutosaveName:name];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [super encodeWithCoder:c];
    [c encodeInteger:_maxRecents forKey:@"NSMaximumRecents"];
    [c encodeBool:_whole forKey:@"NSSendsWholeSearchString"];
    [c encodeBool:_immediately forKey:@"NSSendsSearchStringImmediately"];
    if (_autosave)
        [c encodeObject:_autosave forKey:@"NSRecentsAutosaveName"];
}
- (void)dealloc
{
    [_searchButton release];
    [_cancelButton release];
    [_template release];
    [_recents release];
    [_autosave release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSSearchFieldCell *c = [super copyWithZone:zone];
    c->_template = [_template retain];
    c->_whole = _whole;
    c->_immediately = _immediately;
    c->_maxRecents = _maxRecents;
    c->_recents = [_recents copy];
    c->_autosave = [_autosave copy];
    return c;
}

/* The two buttons are kept for the app to read and change; Ferry draws
 * its own glass and clear button whatever they say. */
- (NSButtonCell *)searchButtonCell { return _searchButton; }
- (void)setSearchButtonCell:(NSButtonCell *)cell
{
    [cell retain];
    [_searchButton release];
    _searchButton = cell;
}
- (NSButtonCell *)cancelButtonCell { return _cancelButton; }
- (void)setCancelButtonCell:(NSButtonCell *)cell
{
    [cell retain];
    [_cancelButton release];
    _cancelButton = cell;
}
- (void)resetSearchButtonCell
{
    NSButtonCell *b = [[NSButtonCell alloc] initTextCell:@""];
    [b setBordered:NO];
    [self setSearchButtonCell:b];
    [b release];
}
- (void)resetCancelButtonCell
{
    NSButtonCell *b = [[NSButtonCell alloc] initTextCell:@""];
    [b setBordered:NO];
    [self setCancelButtonCell:b];
    [b release];
}

/* The parts of a field of these bounds: the glass at the start, the clear
 * button at the end, the text between. */
- (NSRect)searchButtonRectForBounds:(NSRect)r
{
    return NSMakeRect(r.origin.x + 4, round(NSMidY(r) - 8), 16, 16);
}
- (NSRect)cancelButtonRectForBounds:(NSRect)r
{
    return NSMakeRect(NSMaxX(r) - 20, round(NSMidY(r) - 8), 16, 16);
}
- (NSRect)searchTextRectForBounds:(NSRect)r
{
    return NSMakeRect(r.origin.x + 22, r.origin.y + 2, fmax(r.size.width - 22 - 22, 0), fmax(r.size.height - 4, 0));
}

- (NSMenu *)searchMenuTemplate { return _template; }
- (void)setSearchMenuTemplate:(NSMenu *)menu
{
    [menu retain];
    [_template release];
    _template = menu;
}
- (BOOL)sendsWholeSearchString { return _whole; }
- (void)setSendsWholeSearchString:(BOOL)f { _whole = f; }
- (BOOL)sendsSearchStringImmediately { return _immediately; }
- (void)setSendsSearchStringImmediately:(BOOL)f { _immediately = f; }
- (NSInteger)maximumRecents { return _maxRecents; }
- (void)setMaximumRecents:(NSInteger)n
{
    _maxRecents = n < 0 ? 0 : n;
    if ((NSInteger)[_recents count] > _maxRecents)
        [self setRecentSearches:[_recents subarrayWithRange:NSMakeRange(0, (NSUInteger)_maxRecents)]];
}
- (NSArray *)recentSearches { return _recents ?: @[]; }
- (void)setRecentSearches:(NSArray *)recents
{
    [_recents release];
    _recents = [recents copy];
    if (_autosave)
        [[NSUserDefaults standardUserDefaults] setObject:[self recentSearches] forKey:_autosave];
}
- (NSString *)recentsAutosaveName { return _autosave; }
/* Naming the list reads back what was saved under that name. */
- (void)setRecentsAutosaveName:(NSString *)name
{
    [_autosave release];
    _autosave = [name length] ? [name copy] : nil;
    NSArray *saved = _autosave ? [[NSUserDefaults standardUserDefaults] arrayForKey:_autosave] : nil;
    if (saved) {
        [_recents release];
        _recents = [saved copy];
    }
}
/* A search just made goes first, once. */
- (void)_noteRecent:(NSString *)s
{
    if (![s length] || _maxRecents <= 0)
        return;
    NSMutableArray *a = [NSMutableArray arrayWithArray:[self recentSearches]];
    [a removeObject:s];
    [a insertObject:s atIndex:0];
    while ((NSInteger)[a count] > _maxRecents)
        [a removeLastObject];
    [self setRecentSearches:a];
}
@end

/* ---- NSSearchField -------------------------------------------------------------------- */

@interface NSSearchField () <AMenuOwner>
@end

@implementation NSSearchField {
    BOOL _loading, _centers, _searching;
}

+ (Class)cellClass { return [NSSearchFieldCell class]; }

- (NSSearchFieldCell *)_searchCell { return (NSSearchFieldCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    if (!_loading && ![[self cell] isKindOfClass:[NSSearchFieldCell class]]) {
        NSSearchFieldCell *cell = [[NSSearchFieldCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    _loading = YES;
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _loading = NO;
    if (![[self cell] isKindOfClass:[NSSearchFieldCell class]]) {
        NSSearchFieldCell *cell = [[NSSearchFieldCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    return self;
}
- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [super dealloc];
}

- (NSMenu *)searchMenuTemplate { return [[self _searchCell] searchMenuTemplate]; }
- (void)setSearchMenuTemplate:(NSMenu *)m { [[self _searchCell] setSearchMenuTemplate:m]; }
- (BOOL)sendsWholeSearchString { return [[self _searchCell] sendsWholeSearchString]; }
- (void)setSendsWholeSearchString:(BOOL)f { [[self _searchCell] setSendsWholeSearchString:f]; }
- (BOOL)sendsSearchStringImmediately { return [[self _searchCell] sendsSearchStringImmediately]; }
- (void)setSendsSearchStringImmediately:(BOOL)f { [[self _searchCell] setSendsSearchStringImmediately:f]; }
- (BOOL)centersPlaceholder { return _centers; }
- (void)setCentersPlaceholder:(BOOL)f
{
    _centers = f;
    [self setNeedsDisplay:YES];
}
- (NSInteger)maximumRecents { return [[self _searchCell] maximumRecents]; }
- (void)setMaximumRecents:(NSInteger)n { [[self _searchCell] setMaximumRecents:n]; }
- (NSArray *)recentSearches { return [[self _searchCell] recentSearches]; }
- (void)setRecentSearches:(NSArray *)a { [[self _searchCell] setRecentSearches:a]; }
- (NSString *)recentsAutosaveName { return [[self _searchCell] recentsAutosaveName]; }
- (void)setRecentsAutosaveName:(NSString *)n { [[self _searchCell] setRecentsAutosaveName:n]; }

- (BOOL)_hasText { return [[self stringValue] length] > 0; }

/* ---- geometry ---- */

- (NSRect)searchButtonBounds { return [[self _searchCell] searchButtonRectForBounds:[self bounds]]; }
- (NSRect)cancelButtonBounds { return [[self _searchCell] cancelButtonRectForBounds:[self bounds]]; }
- (NSRect)searchTextBounds { return [[self _searchCell] searchTextRectForBounds:[self bounds]]; }
/* Centred, the glass and the placeholder sit together in the middle. */
- (CGFloat)_centredShift
{
    NSAttributedString *ph = [self _shownPlaceholder];
    CGFloat w = 16 + 4 + (ph ? ALineSize(ph, NULL, NULL).width : 0);
    NSRect b = [self bounds];
    return fmax(0, round(NSMidX(b) - w / 2) - [self searchButtonBounds].origin.x);
}
- (NSRect)rectForSearchTextWhenCentered:(BOOL)centered
{
    NSRect r = [self searchTextBounds];
    if (centered) {
        CGFloat dx = [self _centredShift];
        r.origin.x += dx;
        r.size.width = fmax(r.size.width - dx, 0);
    }
    return r;
}
- (NSRect)rectForSearchButtonWhenCentered:(BOOL)centered
{
    return NSOffsetRect([self searchButtonBounds], centered ? [self _centredShift] : 0, 0);
}
- (NSRect)rectForCancelButtonWhenCentered:(BOOL)centered { return [self cancelButtonBounds]; }
- (BOOL)_showsCentred { return _centers && ![self _isEditing] && ![self _hasText]; }

- (NSRect)_textRect
{
    NSRect r = [self rectForSearchTextWhenCentered:[self _showsCentred]];
    if (![self _hasText]) {          /* no clear button: the text may run to the end */
        r.size.width += 16;
    }
    return r;
}
- (NSRect)_clipRect { return [self _textRect]; }
- (NSAttributedString *)_shownPlaceholder
{
    NSAttributedString *ph = [super _shownPlaceholder];
    if (ph || [self placeholderString])
        return ph;
    return AAttributed(@"Search", [self font], [NSColor placeholderTextColor]);
}

- (NSSize)intrinsicContentSize
{
    NSSize s = [super intrinsicContentSize];
    return NSMakeSize(fmax(s.width + 44, 96), 22);
}

/* ---- searching ---- */

- (void)_sendSearch
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sendSearch) object:nil];
    BOOL has = [self _hasText];
    id delegate = [self delegate];
    if (has && !_searching) {
        _searching = YES;
        if ([delegate respondsToSelector:@selector(searchFieldDidStartSearching:)])
            [delegate searchFieldDidStartSearching:self];
    }
    [self sendAction:[self action] to:[self target]];
    if (!has && _searching) {
        _searching = NO;
        if ([delegate respondsToSelector:@selector(searchFieldDidEndSearching:)])
            [delegate searchFieldDidEndSearching:self];
    }
}

/* The text changed: the search goes out now, after a pause, or on Return. */
- (void)_changed
{
    [super _changed];
    NSSearchFieldCell *cell = [self _searchCell];
    if ([cell sendsWholeSearchString])
        return;
    if ([cell sendsSearchStringImmediately] || ![self _hasText]) {
        [self _sendSearch];
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sendSearch) object:nil];
    [self performSelector:@selector(_sendSearch) withObject:nil afterDelay:0.25];
}

- (void)insertNewline:(id)sender
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sendSearch) object:nil];
    BOOL has = [self _hasText];
    id delegate = [self delegate];
    if (has && !_searching) {
        _searching = YES;
        if ([delegate respondsToSelector:@selector(searchFieldDidStartSearching:)])
            [delegate searchFieldDidStartSearching:self];
    }
    [super insertNewline:sender];          /* sends the action */
    [[self _searchCell] _noteRecent:[self stringValue]];
}

/* Escape, or a click on the clear button: empty and searched again. */
- (void)_clear
{
    if (![self _hasText])
        return;
    [self setStringValue:@""];
    [super _changed];
    [self _sendSearch];
    [self setNeedsDisplay:YES];
}
- (void)cancelOperation:(id)sender
{
    if ([self _hasText])
        [self _clear];
    else
        [super cancelOperation:sender];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if ([self _hasText] && NSPointInRect(p, NSInsetRect([self cancelButtonBounds], -2, -3)) && [self isEnabled]) {
        [self _clear];
        return;
    }
    if (NSPointInRect(p, NSInsetRect([self rectForSearchButtonWhenCentered:[self _showsCentred]], -2, -3)) &&
        [self isEnabled]) {
        NSMenu *menu = [self _searchMenu];
        if (menu)
            [AMenuView openMenu:menu forView:self rect:[self bounds] alignItem:-1 skipFirst:NO font:[self font]
                          owner:self];
        else if ([self _hasText])
            [self _sendSearch];
        return;
    }
    [super mouseDown:event];
}

/* The template, with the recent searches where its tagged items say:
 * the title and the clear item only when there are some, the "none" item
 * only when there are none. */
- (NSMenu *)_searchMenu
{
    NSMenu *template = [self searchMenuTemplate];
    if (!template)
        return nil;
    NSArray *recents = [self recentSearches];
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:[template title]] autorelease];
    [menu setAutoenablesItems:NO];
    for (NSMenuItem *t in [template itemArray]) {
        NSInteger tag = [t tag];
        if (tag == NSSearchFieldRecentsMenuItemTag) {
            for (NSString *r in recents) {
                NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:r action:NULL keyEquivalent:@""];
                [i setTag:NSSearchFieldRecentsMenuItemTag];
                [i setRepresentedObject:r];
                [i setIndentationLevel:[t indentationLevel]];
                [menu addItem:i];
                [i release];
            }
            continue;
        }
        if ((tag == NSSearchFieldRecentsTitleMenuItemTag || tag == NSSearchFieldClearRecentsMenuItemTag) &&
            ![recents count])
            continue;
        if (tag == NSSearchFieldNoRecentsMenuItemTag && [recents count])
            continue;
        NSMenuItem *c = [t copy];
        if (tag == NSSearchFieldRecentsTitleMenuItemTag || tag == NSSearchFieldNoRecentsMenuItemTag)
            [c setEnabled:NO];
        [menu addItem:c];
        [c release];
    }
    return menu;
}

- (void)_menuView:(AMenuView *)menu didChooseItem:(NSMenuItem *)item
{
    if (!item)
        return;
    if ([item tag] == NSSearchFieldClearRecentsMenuItemTag) {
        [self setRecentSearches:@[]];
    } else if ([item tag] == NSSearchFieldRecentsMenuItemTag && [item representedObject]) {
        [self setStringValue:[item representedObject]];
        [self _sendSearch];
    } else if ([item action]) {
        [NSApp sendAction:[item action] to:[item target] from:item];
    }
    [self setNeedsDisplay:YES];
}

/* ---- drawing ---- */

static void draw_glass(NSRect r, NSColor *color, BOOL flipped)
{
    CGFloat cx = r.origin.x + 7, cy = NSMidY(r) + (flipped ? -1 : 1), rad = 4.5;
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx - rad, cy - rad, 2 * rad, 2 * rad)];
    [p setLineWidth:1.5];
    [color setStroke];
    [p stroke];
    NSBezierPath *h = [NSBezierPath bezierPath];
    CGFloat k = 0.7071, dy = flipped ? 1 : -1;
    [h moveToPoint:NSMakePoint(cx + rad * k, cy + dy * rad * k)];
    [h lineToPoint:NSMakePoint(cx + rad * k + 3.5, cy + dy * (rad * k + 3.5))];
    [h setLineWidth:1.8];
    [h setLineCapStyle:NSLineCapStyleRound];
    [h stroke];
}

static void draw_clear(NSRect r, CGFloat dim)
{
    NSRect c = NSMakeRect(NSMidX(r) - 7, NSMidY(r) - 7, 14, 14);
    [[NSColor colorWithWhite:0 alpha:0.3 * dim] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:c] fill];
    NSBezierPath *x = [NSBezierPath bezierPath];
    [x moveToPoint:NSMakePoint(NSMidX(c) - 3, NSMidY(c) - 3)];
    [x lineToPoint:NSMakePoint(NSMidX(c) + 3, NSMidY(c) + 3)];
    [x moveToPoint:NSMakePoint(NSMidX(c) - 3, NSMidY(c) + 3)];
    [x lineToPoint:NSMakePoint(NSMidX(c) + 3, NSMidY(c) - 3)];
    [x setLineWidth:1.5];
    [x setLineCapStyle:NSLineCapStyleRound];
    [[NSColor colorWithWhite:1 alpha:dim] setStroke];
    [x stroke];
}

/* The rounded field, the glass and (with text) the clear button; the text
 * field draws the text and the placeholder between them. */
- (void)_drawBezelInRect:(NSRect)b focused:(BOOL)focused
{
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    NSRect f = NSInsetRect(b, 0.5, 0.5);
    f.size.height = fmin(f.size.height, 22);
    f.origin.y = round(NSMidY(b) - f.size.height / 2);
    if ([self drawsBackground])
        AFillRoundedRect(f, 6, [[self backgroundColor] colorWithAlphaComponent:dim], nil);
    AFillRoundedRect(f, 6, nil, [NSColor colorWithWhite:0 alpha:0.2 * dim]);
    if (focused)
        AFillRoundedRect(NSInsetRect(f, -2.5, -2.5), 8.5, nil, [NSColor keyboardFocusIndicatorColor]);
    NSColor *gray = [NSColor colorWithWhite:0 alpha:0.5 * dim];
    draw_glass([self rectForSearchButtonWhenCentered:[self _showsCentred]], gray, [self isFlipped]);
    if ([self _hasText])
        draw_clear([self cancelButtonBounds], dim);
}
@end
