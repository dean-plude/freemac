/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: token fields (NSTokenField, NSTokenFieldCell), written
 * from Apple's public API documentation.
 *
 * A token field's value is an array of represented objects, each shown as
 * a rounded token. What is typed after the tokens becomes new tokens when
 * a tokenizing character (a comma unless set otherwise) is typed, on
 * Return, and when the editing ends. The delegate can turn the typed
 * string into an object (tokenField:representedObjectForEditingString:),
 * name an object (displayStringForRepresentedObject:), refuse or change
 * new tokens (shouldAddObjects:atIndex:) and draw one as plain text
 * (styleForRepresentedObject:). Backspace after the last token selects
 * it, a second Backspace removes it; clicking a token selects it.
 *
 * The tokens stay on one line (a Mac wraps them onto more), there is no
 * completion list (tokenField:completionsForSubstring:...), and tokens
 * can't be edited again, dragged or given menus.
 *
 * In a nib the cell keeps its style under "NSTokenStyle" (a name from
 * developers' descriptions of the format; no Apple code was read). */
#import "AInternal.h"

static const CGFloat token_gap = 3, token_pad = 6;

@interface NSTextField (FerryTokenEditing)
- (NSString *)_editingString;
- (BOOL)_commitText:(BOOL)complain;
@end

@implementation NSTokenFieldCell {
    NSTokenStyle _tokenStyle;
    NSCharacterSet *_tokenizing;
    NSTimeInterval _delay;
}
+ (NSCharacterSet *)defaultTokenizingCharacterSet { return [NSCharacterSet characterSetWithCharactersInString:@","]; }
+ (NSTimeInterval)defaultCompletionDelay { return 0; }
- (instancetype)initTextCell:(NSString *)s
{
    if ((self = [super initTextCell:s])) {
        [self setEditable:YES];
        [self setBezeled:YES];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        _tokenStyle = [coder decodeIntegerForKey:@"NSTokenStyle"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:_tokenStyle forKey:@"NSTokenStyle"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSTokenFieldCell *c = [super copyWithZone:zone];
    c->_tokenStyle = _tokenStyle;
    c->_tokenizing = [_tokenizing copy];
    c->_delay = _delay;
    return c;
}
- (void)dealloc
{
    [_tokenizing release];
    [super dealloc];
}
- (NSTokenStyle)tokenStyle { return _tokenStyle; }
- (void)setTokenStyle:(NSTokenStyle)s { _tokenStyle = s; }
- (NSCharacterSet *)tokenizingCharacterSet { return _tokenizing ?: [[self class] defaultTokenizingCharacterSet]; }
- (void)setTokenizingCharacterSet:(NSCharacterSet *)set
{
    set = [set copy];
    [_tokenizing release];
    _tokenizing = set;
}
- (NSTimeInterval)completionDelay { return _delay; }
- (void)setCompletionDelay:(NSTimeInterval)d { _delay = d; }
@end

@implementation NSTokenField {
    BOOL _loading;
    NSMutableArray *_tokens;
    NSInteger _selectedToken;   /* -1: none */
}

+ (Class)cellClass { return [NSTokenFieldCell class]; }
+ (NSCharacterSet *)defaultTokenizingCharacterSet { return [NSTokenFieldCell defaultTokenizingCharacterSet]; }
+ (NSTimeInterval)defaultCompletionDelay { return [NSTokenFieldCell defaultCompletionDelay]; }
- (NSTokenFieldCell *)_tokenCell { return (NSTokenFieldCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    if (!_tokens)
        _tokens = [[NSMutableArray alloc] init];
    _selectedToken = -1;
    if (!_loading && ![[self cell] isKindOfClass:[NSTokenFieldCell class]]) {
        NSTokenFieldCell *cell = [[NSTokenFieldCell alloc] initTextCell:@""];
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
    if (!_tokens)
        _tokens = [[NSMutableArray alloc] init];
    if (![[self cell] isKindOfClass:[NSTokenFieldCell class]]) {
        NSTokenFieldCell *cell = [[NSTokenFieldCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    /* a string in the nib becomes tokens */
    NSString *s = [super stringValue];
    if ([s length])
        [self setObjectValue:s];
    return self;
}
- (void)dealloc
{
    [_tokens release];
    [super dealloc];
}

- (NSTokenStyle)tokenStyle { return [[self _tokenCell] tokenStyle]; }
- (void)setTokenStyle:(NSTokenStyle)s
{
    [[self _tokenCell] setTokenStyle:s];
    [self setNeedsDisplay:YES];
}
- (NSCharacterSet *)tokenizingCharacterSet { return [[self _tokenCell] tokenizingCharacterSet]; }
- (void)setTokenizingCharacterSet:(NSCharacterSet *)set { [[self _tokenCell] setTokenizingCharacterSet:set]; }
- (NSTimeInterval)completionDelay { return [[self _tokenCell] completionDelay]; }
- (void)setCompletionDelay:(NSTimeInterval)d { [[self _tokenCell] setCompletionDelay:d]; }

/* ---- the tokens ---- */

- (NSString *)_displayStringFor:(id)object
{
    id d = [self delegate];
    if ([d respondsToSelector:@selector(tokenField:displayStringForRepresentedObject:)]) {
        NSString *s = [d tokenField:self displayStringForRepresentedObject:object];
        if (s)
            return s;
    }
    return [object isKindOfClass:[NSString class]] ? object : [object description];
}
- (NSTokenStyle)_styleFor:(id)object
{
    id d = [self delegate];
    NSTokenStyle s = [self tokenStyle];
    if ([d respondsToSelector:@selector(tokenField:styleForRepresentedObject:)])
        s = [d tokenField:self styleForRepresentedObject:object];
    return s;
}
/* The shown value: the tokens' names, joined. */
- (NSString *)_joined
{
    NSMutableArray *names = [NSMutableArray array];
    for (id t in _tokens)
        [names addObject:[self _displayStringFor:t]];
    return [names componentsJoinedByString:@", "];
}
- (void)_syncValue { [super setObjectValue:[self _joined]]; }
/* Strings typed become tokens at index, as the delegate allows. */
- (void)_addStrings:(NSArray *)strings atIndex:(NSUInteger)index
{
    id d = [self delegate];
    NSMutableArray *objects = [NSMutableArray array];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *raw in strings) {
        NSString *s = [raw stringByTrimmingCharactersInSet:ws];
        if (![s length])
            continue;
        id o = s;
        if ([d respondsToSelector:@selector(tokenField:representedObjectForEditingString:)])
            o = [d tokenField:self representedObjectForEditingString:s] ?: s;
        [objects addObject:o];
    }
    if (![objects count])
        return;
    if ([d respondsToSelector:@selector(tokenField:shouldAddObjects:atIndex:)])
        objects = [[[d tokenField:self shouldAddObjects:objects atIndex:index] mutableCopy] autorelease];
    for (id o in objects)
        [_tokens insertObject:o atIndex:index++];
}
- (NSArray *)_split:(NSString *)s
{
    NSCharacterSet *set = [self tokenizingCharacterSet];
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger start = 0, n = [s length];
    for (NSUInteger i = 0; i < n; i++)
        if ([set characterIsMember:[s characterAtIndex:i]]) {
            [parts addObject:[s substringWithRange:NSMakeRange(start, i - start)]];
            start = i + 1;
        }
    [parts addObject:[s substringFromIndex:start]];
    return parts;
}

- (id)objectValue { return [[_tokens copy] autorelease]; }
- (void)setObjectValue:(id)value
{
    if (!_tokens)
        _tokens = [[NSMutableArray alloc] init];
    [_tokens removeAllObjects];
    _selectedToken = -1;
    if ([value isKindOfClass:[NSArray class]])
        [_tokens addObjectsFromArray:value];
    else if ([value isKindOfClass:[NSString class]] && [value length]) {
        for (NSString *s in [self _split:value]) {
            s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([s length])
                [_tokens addObject:s];
        }
    } else if (value && ![value isKindOfClass:[NSString class]])
        [_tokens addObject:value];
    [self _syncValue];
    [self setNeedsDisplay:YES];
}
- (void)setStringValue:(NSString *)s { [self setObjectValue:s]; }
- (NSString *)stringValue
{
    NSString *joined = [self _joined];
    NSString *tail = [self _isEditing] ? [super stringValue] : @"";
    if (![tail length])
        return joined;
    return [joined length] ? [NSString stringWithFormat:@"%@, %@", joined, tail] : tail;
}

/* ---- editing: the text after the tokens ---- */

- (NSString *)_editingString { return @""; }
- (NSString *)_tail { return [self _isEditing] ? [super stringValue] : @""; }
- (BOOL)_commitText:(BOOL)complain
{
    NSString *tail = [self _tail];
    [self _addStrings:[self _split:tail] atIndex:[_tokens count]];
    [self _syncValue];   /* the text after the tokens empties */
    [self setNeedsDisplay:YES];
    return YES;
}
- (BOOL)becomeFirstResponder
{
    _selectedToken = -1;
    return [super becomeFirstResponder];
}
- (BOOL)resignFirstResponder
{
    BOOL ok = [super resignFirstResponder];
    if (ok)
        _selectedToken = -1;
    return ok;
}
- (void)insertText:(id)string
{
    if (_selectedToken >= 0) {
        [_tokens removeObjectAtIndex:_selectedToken];
        _selectedToken = -1;
        [self _syncValue];
    }
    [super insertText:string];
    NSString *tail = [self _tail];
    NSArray *parts = [self _split:tail];
    if ([parts count] > 1) {
        [self _addStrings:[parts subarrayWithRange:NSMakeRange(0, [parts count] - 1)] atIndex:[_tokens count]];
        NSString *rest = [parts lastObject];
        [self _syncValue];
        [self _setEditingText:rest selectedRange:NSMakeRange([rest length], 0)];
        [self _changed];
    }
    [self setNeedsDisplay:YES];
}
- (void)deleteBackward:(id)sender
{
    NSRange sel = [self _selectedTextRange];
    if ([self _isEditing] && sel.location == 0 && sel.length == 0 && [_tokens count]) {
        if (_selectedToken >= 0) {
            [_tokens removeObjectAtIndex:_selectedToken];
            _selectedToken = -1;
            NSString *tail = [[[self _tail] copy] autorelease];
            [self _syncValue];
            [self _setEditingText:tail selectedRange:NSMakeRange(0, 0)];
            [self _changed];
        } else {
            _selectedToken = (NSInteger)[_tokens count] - 1;
        }
        [self setNeedsDisplay:YES];
        return;
    }
    _selectedToken = -1;
    [super deleteBackward:sender];
}
- (void)moveLeft:(id)sender
{
    NSRange sel = [self _selectedTextRange];
    if ([self _isEditing] && sel.location == 0 && sel.length == 0 && [_tokens count]) {
        _selectedToken = _selectedToken < 0 ? (NSInteger)[_tokens count] - 1 : MAX(0, _selectedToken - 1);
        [self setNeedsDisplay:YES];
        return;
    }
    [super moveLeft:sender];
}
- (void)moveRight:(id)sender
{
    if (_selectedToken >= 0) {
        _selectedToken = _selectedToken + 1 < (NSInteger)[_tokens count] ? _selectedToken + 1 : -1;
        [self setNeedsDisplay:YES];
        return;
    }
    [super moveRight:sender];
}

/* ---- layout and drawing ---- */

- (NSRect)_baseTextRect { return [super _textRect]; }
/* The tokens' rectangles, in a row from the start of the text. */
- (NSArray *)_tokenRects
{
    NSMutableArray *rects = [NSMutableArray array];
    NSRect base = [self _baseTextRect];
    NSFont *font = [self font] ?: ADefaultFont();
    CGFloat x = NSMinX(base), h = fmin(base.size.height, 17);
    for (id t in _tokens) {
        CGFloat w = ceil(ALineSize(AAttributed([self _displayStringFor:t], font, nil), NULL, NULL).width);
        if ([self _styleFor:t] != NSTokenStyleNone)
            w += token_pad * 2;
        else
            w += ceil(ALineSize(AAttributed(@",", font, nil), NULL, NULL).width);
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x, round(NSMidY(base) - h / 2), w, h)]];
        x += w + token_gap;
    }
    return rects;
}
- (CGFloat)_tokensWidth
{
    NSValue *last = [[self _tokenRects] lastObject];
    return last ? NSMaxX([last rectValue]) + token_gap - NSMinX([self _baseTextRect]) : 0;
}
- (NSRect)_textRect
{
    NSRect r = [super _textRect];
    CGFloat w = fmin([self _tokensWidth], fmax(0, r.size.width - 20));
    r.origin.x += w;
    r.size.width -= w;
    return r;
}
- (NSRect)_clipRect
{
    NSRect r = [super _clipRect];
    CGFloat w = fmin([self _tokensWidth], fmax(0, r.size.width - 20));
    r.origin.x += w;
    r.size.width -= w;
    return r;
}
- (NSSize)intrinsicContentSize
{
    NSSize s = [super intrinsicContentSize];
    return NSMakeSize(fmax(s.width, 60), s.height);
}
- (NSAttributedString *)_shownPlaceholder { return [_tokens count] ? nil : [super _shownPlaceholder]; }

- (void)_drawTokens
{
    NSArray *rects = [self _tokenRects];
    NSFont *font = [self font] ?: ADefaultFont();
    BOOL enabled = [self isEnabled];
    NSRect clip = [super _clipRect];
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(clip);
    for (NSUInteger i = 0; i < [_tokens count]; i++) {
        id t = _tokens[i];
        NSRect r = [rects[i] rectValue];
        NSTokenStyle style = [self _styleFor:t];
        BOOL sel = (NSInteger)i == _selectedToken && [self _isEditing];
        NSColor *accent = [NSColor controlAccentColor];
        NSColor *text = !enabled ? [NSColor disabledControlTextColor] : sel ? [NSColor whiteColor] : [NSColor labelColor];
        NSString *name = [self _displayStringFor:t];
        CGFloat x = NSMinX(r) + token_pad;
        if (style == NSTokenStyleNone) {
            name = [name stringByAppendingString:@","];
            x = NSMinX(r);
            if (sel)
                AFillRoundedRect(r, 3, accent, nil);
        } else {
            CGFloat radius = style == NSTokenStyleSquared || style == NSTokenStylePlainSquared ? 3 : r.size.height / 2;
            NSColor *fill = sel ? accent : [accent colorWithAlphaComponent:enabled ? 0.16 : 0.08];
            NSColor *stroke = style == NSTokenStylePlainSquared || sel ? nil : [accent colorWithAlphaComponent:enabled ? 0.45 : 0.2];
            AFillRoundedRect(NSInsetRect(r, 0.5, 0.5), radius, fill, stroke);
        }
        NSAttributedString *a = AAttributed(name, font, text);
        CGFloat asc, desc;
        ALineSize(a, &asc, &desc);
        CGFloat base = [self isFlipped] ? NSMidY(r) + (asc - desc) / 2 : NSMidY(r) - (asc - desc) / 2;
        ADrawLine(a, x, round(base));
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (void)drawRect:(NSRect)dirty
{
    if ([self _isEditing]) {
        [super drawRect:dirty];
        [self _drawTokens];
        return;
    }
    NSRect b = [self bounds];
    if ([self isBezeled] || [self isBordered])
        [self _drawBezelInRect:b focused:NO];
    else if ([self drawsBackground]) {
        [[self backgroundColor] setFill];
        NSRectFill(b);
    }
    if ([_tokens count]) {
        [self _drawTokens];
        return;
    }
    NSAttributedString *ph = [self _shownPlaceholder];
    if (ph) {
        NSRect tr = [super _textRect];
        CGFloat asc, desc;
        ALineSize(ph, &asc, &desc);
        CGFloat base = [self isFlipped] ? NSMidY(tr) + (asc - desc) / 2 : NSMidY(tr) - (asc - desc) / 2;
        ADrawLine(ph, NSMinX(tr), round(base));
    }
}

- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSArray *rects = [self _tokenRects];
    for (NSUInteger i = 0; i < [rects count]; i++)
        if (NSPointInRect(p, [rects[i] rectValue]) && [self isEnabled]) {
            if ([[self window] firstResponder] != self)
                [[self window] makeFirstResponder:self];
            _selectedToken = (NSInteger)i;
            [self setNeedsDisplay:YES];
            return;
        }
    _selectedToken = -1;
    [super mouseDown:e];
}
@end
