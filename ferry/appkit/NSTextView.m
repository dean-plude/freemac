/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSText and NSTextView, multi-line text that can be
 * selected and edited, usually inside an NSScrollView. The text lives in an
 * NSTextStorage; the view lays it out itself with a Core Text frame as wide
 * as its text container and keeps the lines, which drawing, the caret,
 * selection and hit-testing all use. NSLayoutManager and NSTextContainer
 * exist for the code that asks for them, and for nibs, but the layout is the
 * view's; a layout manager lays text out itself only when no view shows it.
 * The view is flipped, as on a Mac. */
#import "AInternal.h"

NSNotificationName const NSTextDidBeginEditingNotification = @"NSTextDidBeginEditingNotification";
NSNotificationName const NSTextDidEndEditingNotification = @"NSTextDidEndEditingNotification";
NSNotificationName const NSTextDidChangeNotification = @"NSTextDidChangeNotification";
NSNotificationName const NSTextViewDidChangeSelectionNotification = @"NSTextViewDidChangeSelectionNotification";

@interface NSTextView (FerryLayout)
- (void)_textStorageChanged;
- (NSRect)_usedRect;
- (NSRect)_rectForRange:(NSRange)range;
- (NSRange)_rangeForRect:(NSRect)rect;
- (NSRect)_lineRectForIndex:(NSUInteger)index range:(NSRangePointer)range;
@end
@interface NSLayoutManager (FerryLayout)
- (void)_textStorageChanged;
@end

/* ---- NSTextStorage: an attributed string that tells its layout managers when it changes ---- */

NSNotificationName const NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification";
NSNotificationName const NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";

/* Each change is recorded with edited:range:changeInLength: (the range is
 * where the text was before the change); once the outermost endEditing
 * comes, processEditing tells the delegate, posts the notifications and
 * has the layout managers' text views lay the text out again. editedMask,
 * editedRange and changeInLength describe the changes, in the text as it is
 * now, while that happens (freemac 1.221, Ferry 0.45.0). */
@implementation NSTextStorage {
    NSMutableArray *_managers;
    id _delegate;
    NSInteger _editing, _change;
    BOOL _pending;
    NSTextStorageEditActions _mask;
    NSRange _edited;
}
- (void)dealloc
{
    [_managers release];
    [super dealloc];
}
- (NSArray *)layoutManagers { return [[(_managers ?: @[]) copy] autorelease]; }
- (void)addLayoutManager:(NSLayoutManager *)lm
{
    if (!_managers)
        _managers = [[NSMutableArray alloc] init];
    if (![_managers containsObject:lm]) {
        [_managers addObject:lm];
        [lm setTextStorage:self];
    }
}
- (void)removeLayoutManager:(NSLayoutManager *)lm { [_managers removeObject:lm]; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSInteger)changeInLength { return _change; }
- (NSTextStorageEditActions)editedMask { return _mask; }
- (NSRange)editedRange { return _pending ? _edited : NSMakeRange(NSNotFound, 0); }
- (BOOL)fixesAttributesLazily { return NO; }
- (void)ensureAttributesAreFixedInRange:(NSRange)range {}
- (void)invalidateAttributesInRange:(NSRange)range {}
- (void)edited:(NSTextStorageEditActions)mask range:(NSRange)range changeInLength:(NSInteger)delta
{
    /* the range after the change */
    NSRange now = NSMakeRange(range.location, (NSUInteger)MAX((NSInteger)range.length + delta, 0));
    if (!_pending) {
        _edited = now;
    } else {
        /* the earlier edits' range, moved by this change where it lies after it */
        NSUInteger start = _edited.location, end = NSMaxRange(_edited);
        if (end > range.location)
            end = (NSUInteger)MAX((NSInteger)end + delta, (NSInteger)NSMaxRange(now));
        start = MIN(start, now.location);
        end = MAX(end, NSMaxRange(now));
        _edited = NSMakeRange(start, end - start);
    }
    _mask |= mask;
    _change += delta;
    _pending = YES;
    if (!_editing)
        [self processEditing];
}
- (void)processEditing
{
    if (!_pending)
        return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSRange range = _edited;
    if ([_delegate respondsToSelector:@selector(textStorage:willProcessEditing:range:changeInLength:)])
        [_delegate textStorage:self willProcessEditing:_mask range:range changeInLength:_change];
    NSNotification *will = [NSNotification notificationWithName:NSTextStorageWillProcessEditingNotification object:self];
    if ([_delegate respondsToSelector:@selector(textStorageWillProcessEditing:)])
        [_delegate textStorageWillProcessEditing:will];
    [nc postNotification:will];
    if ([_delegate respondsToSelector:@selector(textStorage:didProcessEditing:range:changeInLength:)])
        [_delegate textStorage:self didProcessEditing:_mask range:_edited changeInLength:_change];
    NSNotification *did = [NSNotification notificationWithName:NSTextStorageDidProcessEditingNotification object:self];
    if ([_delegate respondsToSelector:@selector(textStorageDidProcessEditing:)])
        [_delegate textStorageDidProcessEditing:did];
    [nc postNotification:did];
    _pending = NO;
    _mask = 0;
    _change = 0;
    for (NSLayoutManager *lm in [[_managers copy] autorelease])
        [lm _textStorageChanged];
}
- (void)beginEditing { _editing++; }
- (void)endEditing
{
    if (_editing > 0 && --_editing == 0 && _pending)
        [self processEditing];
}
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s
{
    [super replaceCharactersInRange:r withString:s];
    [self edited:NSTextStorageEditedCharacters range:r changeInLength:(NSInteger)[s length] - (NSInteger)r.length];
}
- (void)replaceCharactersInRange:(NSRange)r withAttributedString:(NSAttributedString *)s
{
    [super replaceCharactersInRange:r withAttributedString:s];
    [self edited:NSTextStorageEditedCharacters | NSTextStorageEditedAttributes range:r
        changeInLength:(NSInteger)[s length] - (NSInteger)r.length];
}
- (void)deleteCharactersInRange:(NSRange)r
{
    [super deleteCharactersInRange:r];
    [self edited:NSTextStorageEditedCharacters range:r changeInLength:-(NSInteger)r.length];
}
- (void)setAttributes:(NSDictionary *)a range:(NSRange)r
{
    [super setAttributes:a range:r];
    [self edited:NSTextStorageEditedAttributes range:r changeInLength:0];
}
- (void)addAttribute:(NSString *)n value:(id)v range:(NSRange)r
{
    [super addAttribute:n value:v range:r];
    [self edited:NSTextStorageEditedAttributes range:r changeInLength:0];
}
- (void)addAttributes:(NSDictionary *)a range:(NSRange)r
{
    [super addAttributes:a range:r];
    [self edited:NSTextStorageEditedAttributes range:r changeInLength:0];
}
- (void)removeAttribute:(NSString *)n range:(NSRange)r
{
    [super removeAttribute:n range:r];
    [self edited:NSTextStorageEditedAttributes range:r changeInLength:0];
}
@end

/* ---- NSTextContainer and NSLayoutManager ------------------------------------------------ */

@implementation NSTextContainer {
    NSSize _size;
    NSTextView *_textView;
    NSLayoutManager *_layoutManager;
    BOOL _tracksWidth, _tracksHeight;
    CGFloat _padding;
    NSUInteger _maxLines;
    NSLineBreakMode _lineBreak;
}
- (instancetype)initWithSize:(NSSize)size
{
    if ((self = [super init])) {
        _size = size;
        _padding = 5;
    }
    return self;
}
- (instancetype)initWithContainerSize:(NSSize)size { return [self initWithSize:size]; }
- (instancetype)init { return [self initWithSize:NSMakeSize(1e7, 1e7)]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self initWithSize:NSMakeSize([coder containsValueForKey:@"NSWidth"] ? [coder decodeDoubleForKey:@"NSWidth"]
                                                                                       : 1e7,
                                              1e7)])) {
        /* flag 1: the width follows the text view */
        _tracksWidth = !([coder containsValueForKey:@"NSTCFlags"]) || ([coder decodeIntForKey:@"NSTCFlags"] & 1);
        _layoutManager = [coder decodeObjectForKey:@"NSLayoutManager"];
        _textView = [coder decodeObjectForKey:@"NSTextView"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeDouble:_size.width forKey:@"NSWidth"]; }
- (NSSize)size { return _size; }
- (void)setSize:(NSSize)s { _size = s; }
- (NSSize)containerSize { return _size; }
- (void)setContainerSize:(NSSize)s { _size = s; }
- (NSTextView *)textView { return _textView; }
- (void)setTextView:(NSTextView *)tv { _textView = tv; }
- (NSLayoutManager *)layoutManager { return _layoutManager; }
- (void)setLayoutManager:(NSLayoutManager *)lm { _layoutManager = lm; }
- (BOOL)widthTracksTextView { return _tracksWidth; }
- (void)setWidthTracksTextView:(BOOL)f { _tracksWidth = f; }
- (BOOL)heightTracksTextView { return _tracksHeight; }
- (void)setHeightTracksTextView:(BOOL)f { _tracksHeight = f; }
- (CGFloat)lineFragmentPadding { return _padding; }
- (void)setLineFragmentPadding:(CGFloat)p { _padding = p; }
- (NSUInteger)maximumNumberOfLines { return _maxLines; }
- (void)setMaximumNumberOfLines:(NSUInteger)n { _maxLines = n; }
- (NSLineBreakMode)lineBreakMode { return _lineBreak; }
- (void)setLineBreakMode:(NSLineBreakMode)m { _lineBreak = m; }
@end

/* A line laid out by a layout manager that has no text view (below). */
typedef struct {
    CTLineRef line;
    NSRange range;
    NSRect rect;   /* the line fragment, in the container */
    CGFloat x, width;
} LMLine;

@implementation NSLayoutManager {
    NSTextStorage *_storage;   /* not retained: the storage holds us */
    NSMutableArray *_containers;
    BOOL _nonContiguous, _fontLeading, _invisibles, _controls, _noBackgroundLayout;
    LMLine *_own;   /* its own layout, when no text view shows the text */
    NSUInteger _ownCount;
    BOOL _ownValid;
    CGFloat _ownWidth;
    NSRect _ownUsed;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _containers = [[NSMutableArray alloc] init];
        _fontLeading = YES;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        NSTextStorage *s = [coder decodeObjectForKey:@"NSTextStorage"];
        if ([s isKindOfClass:[NSTextStorage class]])
            [s addLayoutManager:self];
        for (NSTextContainer *c in [coder decodeObjectForKey:@"NSTextContainers"])
            if ([c isKindOfClass:[NSTextContainer class]])
                [self addTextContainer:c];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)_freeOwnLayout
{
    for (NSUInteger i = 0; i < _ownCount; i++)
        CFRelease(_own[i].line);
    free(_own);
    _own = NULL;
    _ownCount = 0;
    _ownValid = NO;
}
- (void)dealloc
{
    [self _freeOwnLayout];
    [_containers release];
    [super dealloc];
}
/* Text measured with a layout manager and a text container and no text
 * view, as apps do to wrap or size text (VLC wraps its preferences' help
 * this way): the manager lays the text out itself, in the first
 * container's width less its padding, one glyph to a character (freemac
 * 1.NEXT). Laid out again when the text or the width changes. */
- (BOOL)_ownLayout
{
    if ([self firstTextView] || !_storage)
        return NO;
    NSTextContainer *c = [_containers firstObject];
    CGFloat pad = c ? [c lineFragmentPadding] : 0;
    CGFloat width = fmax((c ? [c size].width : 1e7) - 2 * pad, 1);
    if (_ownValid && width == _ownWidth)
        return YES;
    [self _freeOwnLayout];
    NSMutableAttributedString *text = [[_storage mutableCopy] autorelease];
    NSUInteger n = [text length], i = 0;
    while (i < n) {
        NSRange r;
        if (![text attribute:NSFontAttributeName atIndex:i effectiveRange:&r])
            [text addAttribute:NSFontAttributeName value:ADefaultFont() range:r];
        i = NSMaxRange(r);
    }
    CGFloat bottom = 0, widest = 0;
    if (n) {
        const CGFloat tall = 1e6;
        CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)text);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(0, 0, width, tall));
        CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
        CFArrayRef lines = CTFrameGetLines(frame);
        CFIndex count = CFArrayGetCount(lines);
        _own = calloc((size_t)count + 1, sizeof *_own);
        CGPoint *origins = calloc((size_t)count + 1, sizeof *origins);
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), origins);
        for (CFIndex k = 0; k < count; k++) {
            CTLineRef line = CFArrayGetValueAtIndex(lines, k);
            CGFloat a, d, l;
            double w = CTLineGetTypographicBounds(line, &a, &d, &l);
            CFRange r = CTLineGetStringRange(line);
            LMLine *t = &_own[_ownCount++];
            t->line = CFRetain(line);
            t->range = NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length);
            t->x = origins[k].x + pad;
            t->width = w - CTLineGetTrailingWhitespaceWidth(line);
            t->rect = NSMakeRect(0, tall - origins[k].y - a, width + 2 * pad, a + d + l);
            bottom = NSMaxY(t->rect);
            widest = fmax(widest, t->x + t->width + pad);
        }
        free(origins);
        CFRelease(frame);
        CGPathRelease(path);
        CFRelease(fs);
        /* each line runs to the next, as on a Mac: its paragraph's newline
         * is its own last character */
        for (NSUInteger k = 0; k < _ownCount; k++) {
            NSUInteger end = k + 1 < _ownCount ? _own[k + 1].range.location : n;
            if (end > _own[k].range.location)
                _own[k].range.length = end - _own[k].range.location;
        }
    }
    _ownUsed = NSMakeRect(0, 0, ceil(widest), ceil(bottom));
    _ownWidth = width;
    _ownValid = YES;
    return YES;
}
- (void)_textStorageChanged
{
    _ownValid = NO;
    [[self firstTextView] _textStorageChanged];
}
- (NSUInteger)_ownLineFor:(NSUInteger)i
{
    NSUInteger k = 0;
    while (k + 1 < _ownCount && i >= NSMaxRange(_own[k].range))
        k++;
    return k;
}
- (NSTextStorage *)textStorage { return _storage; }
- (void)setTextStorage:(NSTextStorage *)s
{
    _storage = s;
    _ownValid = NO;
}
- (void)replaceTextStorage:(NSTextStorage *)s
{
    [_storage removeLayoutManager:self];
    [s addLayoutManager:self];
}
- (NSArray *)textContainers { return [[_containers copy] autorelease]; }
- (void)addTextContainer:(NSTextContainer *)c
{
    if (![_containers containsObject:c]) {
        [_containers addObject:c];
        [c setLayoutManager:self];
        _ownValid = NO;
    }
}
- (NSTextView *)firstTextView
{
    for (NSTextContainer *c in _containers)
        if ([c textView])
            return [c textView];
    return nil;
}
- (NSRect)usedRectForTextContainer:(NSTextContainer *)c
{
    NSTextView *tv = [c textView];
    if (tv)
        return [tv _usedRect];
    return [self _ownLayout] ? _ownUsed : NSZeroRect;
}
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)c
{
    /* laid out by itself: the lines that fit in the container's height */
    if (![c textView] && [self _ownLayout] && _ownCount) {
        CGFloat h = [c size].height;
        NSUInteger end = 0;
        for (NSUInteger k = 0; k < _ownCount && (k == 0 || NSMaxY(_own[k].rect) <= h); k++)
            end = NSMaxRange(_own[k].range);
        return NSMakeRange(0, end);
    }
    return NSMakeRange(0, [_storage length]);
}
/* One glyph for each character (freemac 1.221, Ferry 0.45.0): the text
 * view that shows the container answers for the rectangles. */
- (NSRect)boundingRectForGlyphRange:(NSRange)range inTextContainer:(NSTextContainer *)c
{
    NSTextView *tv = [c textView] ?: [self firstTextView];
    if (tv)
        return [tv _rectForRange:range];
    if (![self _ownLayout] || !_ownCount)
        return NSZeroRect;
    NSRect r = NSZeroRect;
    for (NSUInteger k = 0; k < _ownCount; k++) {
        LMLine *t = &_own[k];
        NSUInteger s = MAX(range.location, t->range.location), e = MIN(NSMaxRange(range), NSMaxRange(t->range));
        if (s > e || (s == e && range.length))
            continue;
        CGFloat x0 = t->x + CTLineGetOffsetForStringIndex(t->line, (CFIndex)s, NULL);
        CGFloat x1 = t->x + CTLineGetOffsetForStringIndex(t->line, (CFIndex)e, NULL);
        NSRect lr = NSMakeRect(x0, NSMinY(t->rect), fmax(x1 - x0, 0), NSHeight(t->rect));
        r = NSIsEmptyRect(r) && NSWidth(r) == 0 && NSHeight(r) == 0 ? lr : NSUnionRect(r, lr);
    }
    return r;
}
- (NSRange)glyphRangeForCharacterRange:(NSRange)range actualCharacterRange:(NSRangePointer)actual
{
    NSUInteger n = [_storage length], start = MIN(range.location, n);
    NSRange r = NSMakeRange(start, MIN(range.length, n - start));
    if (actual)
        *actual = r;
    return r;
}
- (NSRange)characterRangeForGlyphRange:(NSRange)range actualGlyphRange:(NSRangePointer)actual
{
    return [self glyphRangeForCharacterRange:range actualCharacterRange:actual];
}
- (NSUInteger)glyphIndexForCharacterAtIndex:(NSUInteger)i { return i; }
- (NSUInteger)characterIndexForGlyphAtIndex:(NSUInteger)i { return i; }
- (NSRange)glyphRangeForBoundingRect:(NSRect)rect inTextContainer:(NSTextContainer *)c
{
    NSTextView *tv = [c textView] ?: [self firstTextView];
    return tv ? [tv _rangeForRect:rect] : NSMakeRange(0, 0);
}
- (NSUInteger)glyphIndexForPoint:(NSPoint)p inTextContainer:(NSTextContainer *)c
{
    NSTextView *tv = [c textView] ?: [self firstTextView];
    NSSize inset = [tv textContainerInset];
    return tv ? [tv characterIndexForInsertionAtPoint:NSMakePoint(p.x + inset.width, p.y + inset.height)] : 0;
}
- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)range
{
    NSTextView *tv = [self firstTextView];
    if (tv)
        return [tv _lineRectForIndex:i range:range];
    if (![self _ownLayout] || !_ownCount) {
        if (range)
            *range = NSMakeRange(0, 0);
        return NSZeroRect;
    }
    LMLine *t = &_own[[self _ownLineFor:i]];
    if (range)
        *range = t->range;
    return t->rect;
}
- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)range
{
    NSRect r = [self lineFragmentRectForGlyphAtIndex:i effectiveRange:range];
    if ([self firstTextView] || !_ownCount)
        return r;
    LMLine *t = &_own[[self _ownLineFor:i]];
    return NSMakeRect(0, NSMinY(r), ceil(t->x + t->width + [[_containers firstObject] lineFragmentPadding]), NSHeight(r));
}
- (void)ensureLayoutForTextContainer:(NSTextContainer *)c
{
    if ([c textView])
        [[c textView] _usedRect];
    else
        [self _ownLayout];
}
- (NSUInteger)numberOfGlyphs { return [_storage length]; }
- (CGFloat)defaultLineHeightForFont:(NSFont *)f
{
    return ceil(CTFontGetAscent((CTFontRef)f) + CTFontGetDescent((CTFontRef)f) + CTFontGetLeading((CTFontRef)f));
}
- (BOOL)allowsNonContiguousLayout { return _nonContiguous; }
- (void)setAllowsNonContiguousLayout:(BOOL)f { _nonContiguous = f; }
- (BOOL)backgroundLayoutEnabled { return !_noBackgroundLayout; }
- (void)setBackgroundLayoutEnabled:(BOOL)f { _noBackgroundLayout = !f; }
- (BOOL)usesFontLeading { return _fontLeading; }
- (void)setUsesFontLeading:(BOOL)f { _fontLeading = f; }
- (BOOL)showsInvisibleCharacters { return _invisibles; }
- (void)setShowsInvisibleCharacters:(BOOL)f { _invisibles = f; }
- (BOOL)showsControlCharacters { return _controls; }
- (void)setShowsControlCharacters:(BOOL)f { _controls = f; }
@end

/* ---- NSText, NSTextView ---------------------------------------------------------------- */

typedef struct {
    CTLineRef line;          /* NULL for the empty line after a final newline */
    NSRange range;
    CGFloat x, top, ascent, descent, height;
} TVLine;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation NSText
+ (instancetype)allocWithZone:(NSZone *)zone
{
    /* NSText is abstract; on a Mac too an NSText is made as an NSTextView */
    return self == [NSText class] ? [NSTextView allocWithZone:zone] : [super allocWithZone:zone];
}
@end
#pragma clang diagnostic pop

/* What a nib's text view lets its user do, which ferry-ibtool writes from
 * the xib (freemac 1.229, Ferry 0.53.0): "NSFlags", whose bits are
 * Ferry's own (the order of TEXT_VIEW_FLAGS in sdk/ferry-ibtool), the
 * background, insertion point and text colours, a font and the find style
 * (1 the find panel, 2 the find bar). The text view applies it as it is
 * decoded. */
@interface NSTextViewSharedData : NSObject <NSCoding>
@end
@implementation NSTextViewSharedData {
    unsigned _flags;
    NSInteger _findStyle;
    NSColor *_background, *_insertion, *_text;
    NSFont *_font;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _flags = (unsigned)[coder decodeInt64ForKey:@"NSFlags"];
        _findStyle = [coder decodeIntegerForKey:@"NSFindStyle"];
        id v = [coder decodeObjectForKey:@"NSBackgroundColor"];
        _background = [v isKindOfClass:[NSColor class]] ? [v retain] : nil;
        v = [coder decodeObjectForKey:@"NSInsertionColor"];
        _insertion = [v isKindOfClass:[NSColor class]] ? [v retain] : nil;
        v = [coder decodeObjectForKey:@"NSTextColor"];
        _text = [v isKindOfClass:[NSColor class]] ? [v retain] : nil;
        v = [coder decodeObjectForKey:@"NSFont"];
        _font = [v isKindOfClass:[NSFont class]] ? [v retain] : nil;
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)dealloc
{
    [_background release];
    [_insertion release];
    [_text release];
    [_font release];
    [super dealloc];
}
- (void)_ferryApplyTo:(NSTextView *)tv
{
    static const char *const setters[] = {
        "setEditable:", "setSelectable:", "setRichText:", "setImportsGraphics:", "setFieldEditor:",
        "setUsesFontPanel:", "setUsesRuler:", "setDrawsBackground:", "setAllowsUndo:",
        "setContinuousSpellCheckingEnabled:", "setSmartInsertDeleteEnabled:",
        "setAllowsDocumentBackgroundColorChange:", "setRulerVisible:", "setAutomaticQuoteSubstitutionEnabled:",
        "setAutomaticDashSubstitutionEnabled:", "setAutomaticSpellingCorrectionEnabled:", "setAllowsImageEditing:",
        "setUsesInspectorBar:", "setAutomaticLinkDetectionEnabled:", "setAutomaticTextReplacementEnabled:",
        "setAutomaticDataDetectionEnabled:", "setGrammarCheckingEnabled:", "setAllowsNonContiguousLayout:",
        "setIncrementalSearchingEnabled:"};
    for (unsigned i = 0; i < sizeof setters / sizeof *setters; i++) {
        SEL sel = sel_registerName(setters[i]);
        if ([tv respondsToSelector:sel])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(tv, sel, (_flags >> i) & 1);
    }
    if (_findStyle == 1)
        [tv setUsesFindPanel:YES];
    else if (_findStyle == 2)
        [tv setUsesFindBar:YES];
    if (_background)
        [tv setBackgroundColor:_background];
    if (_insertion)
        [tv setInsertionPointColor:_insertion];
    /* the font and colour are what's typed next: the document's own text
     * keeps the ones its runs have */
    if ([[tv textStorage] length] && [tv respondsToSelector:@selector(setTypingAttributes:)]) {
        NSMutableDictionary *t = [[[tv typingAttributes] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
        if (_font)
            [t setObject:_font forKey:NSFontAttributeName];
        if (_text)
            [t setObject:_text forKey:NSForegroundColorAttributeName];
        [tv setTypingAttributes:t];
        return;
    }
    if (_font)
        [tv setFont:_font];
    if (_text)
        [tv setTextColor:_text];
}
@end

@implementation NSTextView {
    NSSelectionGranularity _granularity;
    NSTextStorage *_storage;
    NSLayoutManager *_manager;
    NSTextContainer *_container;
    NSSize _inset, _minSize, _maxSize;
    NSRange _selection;
    NSUInteger _anchor;
    NSUInteger _typingAt;    /* where the typing attributes were last set, or NSNotFound */
    CGFloat _wantX;          /* the column up and down keep to, or -1 */
    BOOL _editable, _selectable, _rich, _graphics, _fieldEditor, _fontPanel, _drawsBackground;
    BOOL _horizontal, _vertical, _undo, _began, _dragging;
    NSColor *_background, *_insertionColor;
    NSDictionary *_typing, *_selectedAttrs, *_linkAttrs, *_markedAttrs;
    NSParagraphStyle *_paragraph;
    id _delegate;
    /* the layout */
    TVLine *_lines;
    NSUInteger _lineCount;
    BOOL _laidOut, _sizing;
    CGFloat _laidWidth;
    NSRect _used;
    /* switches kept for the code that sets them */
    BOOL _findBar, _findPanel, _ruler, _rulerVisible, _smart, _spelling, _grammar, _quotes, _dashes, _links,
        _replacement, _correction, _detection, _linkTips, _images, _bgChange, _inspector, _completion;
}

/* ---- making one ---- */

- (void)_setUpWithContainer:(NSTextContainer *)c
{
    _storage = [[NSTextStorage alloc] init];
    _manager = [[NSLayoutManager alloc] init];
    [_storage addLayoutManager:_manager];
    [self setTextContainer:c ?: [[[NSTextContainer alloc] initWithSize:NSMakeSize([self frame].size.width, 1e7)]
                                     autorelease]];
    if (!c)
        [_container setWidthTracksTextView:YES];
    _editable = _selectable = _rich = _drawsBackground = _vertical = YES;
    _fontPanel = YES;
    _typingAt = NSNotFound;
    _inset = NSZeroSize;
    _minSize = [self frame].size;
    _maxSize = NSMakeSize(1e7, 1e7);
    _wantX = -1;
    _typing = [@{NSFontAttributeName : [NSFont userFontOfSize:0] ?: ADefaultFont(),
                 NSForegroundColorAttributeName : [NSColor textColor]} retain];
}
- (instancetype)initWithFrame:(NSRect)frame textContainer:(NSTextContainer *)c
{
    if ((self = [super initWithFrame:frame]))
        [self _setUpWithContainer:c];
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame textContainer:nil]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUpWithContainer:nil];
        /* the text of a nib's text view hangs off its container's layout manager */
        NSTextContainer *c = [coder decodeObjectForKey:@"NSTextContainer"];
        NSTextStorage *s = [[c layoutManager] textStorage];
        if ([s isKindOfClass:[NSAttributedString class]] && [s length])
            [_storage setAttributedString:s];
        id shared = [coder decodeObjectForKey:@"NSSharedData"];
        if ([shared respondsToSelector:@selector(_ferryApplyTo:)])
            [shared performSelector:@selector(_ferryApplyTo:) withObject:self];
        if ([coder containsValueForKey:@"NSTextContainerInset"])
            _inset = [coder decodeSizeForKey:@"NSTextContainerInset"];
        if ([coder containsValueForKey:@"NSMinize"])
            _minSize = [coder decodeSizeForKey:@"NSMinize"];
        if ([coder containsValueForKey:@"NSMaxSize"])
            _maxSize = [coder decodeSizeForKey:@"NSMaxSize"];
        if ([coder containsValueForKey:@"NSTVFlags"]) {
            int f = [coder decodeIntForKey:@"NSTVFlags"];
            _horizontal = (f & 1) != 0;
            _vertical = (f & 2) != 0;
        }
    }
    return self;
}
+ (NSScrollView *)scrollableTextView
{
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 240, 135)] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setBorderType:NSNoBorder];
    NSSize size = [sv contentSize];
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)] autorelease];
    [tv setMinSize:NSMakeSize(0, 0)]; /* it is never shorter than its clip view */
    [tv setAutoresizingMask:NSViewWidthSizable];
    [sv setDocumentView:tv];
    return sv;
}
- (void)_freeLines
{
    for (NSUInteger i = 0; i < _lineCount; i++)
        if (_lines[i].line)
            CFRelease(_lines[i].line);
    free(_lines);
    _lines = NULL;
    _lineCount = 0;
}
- (void)dealloc
{
    [self _freeLines];
    [_storage removeLayoutManager:_manager];
    [_container setTextView:nil];
    [_container release];
    [_manager release];
    [_storage release];
    [_background release];
    [_insertionColor release];
    [_typing release];
    [_selectedAttrs release];
    [_linkAttrs release];
    [_markedAttrs release];
    [_paragraph release];
    [super dealloc];
}

/* ---- properties ---- */

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return _drawsBackground; }
- (NSTextStorage *)textStorage { return _storage; }
- (NSAttributedString *)attributedString { return _storage; }
- (NSSelectionAffinity)selectionAffinity { return NSSelectionAffinityDownstream; }
- (NSLayoutManager *)layoutManager { return _manager; }
- (NSTextContainer *)textContainer { return _container; }
- (void)setTextContainer:(NSTextContainer *)c
{
    if (c == _container)
        return;
    [_container setTextView:nil];
    [_container release];
    _container = [c retain];
    [c setTextView:self];
    if (![c layoutManager])
        [_manager addTextContainer:c];
    [self _invalidate];
}
- (void)replaceTextContainer:(NSTextContainer *)c { [self setTextContainer:c]; }
- (NSSize)textContainerInset { return _inset; }
- (void)setTextContainerInset:(NSSize)s
{
    _inset = s;
    [self _invalidate];
}
- (NSPoint)textContainerOrigin { return NSMakePoint(_inset.width, _inset.height); }
- (NSString *)string { return [_storage string]; }
- (void)setString:(NSString *)s
{
    [_storage replaceCharactersInRange:NSMakeRange(0, [_storage length])
                  withAttributedString:[[[NSAttributedString alloc] initWithString:s ?: @"" attributes:_typing] autorelease]];
    _selection = NSMakeRange([s length], 0);
    _anchor = _selection.location;
}
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)f
{
    _editable = f;
    if (f)
        _selectable = YES;
}
- (BOOL)isSelectable { return _selectable; }
- (void)setSelectable:(BOOL)f { _selectable = f; }
- (BOOL)isRichText { return _rich; }
- (void)setRichText:(BOOL)f { _rich = f; }
- (BOOL)importsGraphics { return _graphics; }
- (void)setImportsGraphics:(BOOL)f { _graphics = f; }
- (BOOL)isFieldEditor { return _fieldEditor; }
- (void)setFieldEditor:(BOOL)f { _fieldEditor = f; }
- (BOOL)usesFontPanel { return _fontPanel; }
- (void)setUsesFontPanel:(BOOL)f { _fontPanel = f; }
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f
{
    _drawsBackground = f;
    [self setNeedsDisplay:YES];
}
- (NSColor *)backgroundColor { return _background ?: [NSColor textBackgroundColor]; }
- (void)setBackgroundColor:(NSColor *)c
{
    [_background release];
    _background = [c copy];
    [self setNeedsDisplay:YES];
}
- (NSColor *)insertionPointColor { return _insertionColor ?: [NSColor textColor]; }
- (void)setInsertionPointColor:(NSColor *)c
{
    [_insertionColor release];
    _insertionColor = [c copy];
}
- (NSDictionary *)typingAttributes { return _typing; }
- (void)setTypingAttributes:(NSDictionary *)a
{
    [_typing release];
    _typing = [a copy];
}
#define ATTRS(get, set, ivar)                                                                                    \
    -(NSDictionary *)get { return ivar; }                                                                        \
    -(void)set:(NSDictionary *)a                                                                                 \
    {                                                                                                            \
        [ivar release];                                                                                          \
        ivar = [a copy];                                                                                         \
    }
ATTRS(selectedTextAttributes, setSelectedTextAttributes, _selectedAttrs)
ATTRS(linkTextAttributes, setLinkTextAttributes, _linkAttrs)
ATTRS(markedTextAttributes, setMarkedTextAttributes, _markedAttrs)
- (NSParagraphStyle *)defaultParagraphStyle { return _paragraph; }
- (void)setDefaultParagraphStyle:(NSParagraphStyle *)p
{
    [_paragraph release];
    _paragraph = [p copy];
}
- (NSFont *)font
{
    NSFont *f = [_storage length] ? [_storage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil;
    return f ?: [_typing objectForKey:NSFontAttributeName];
}
- (void)setFont:(NSFont *)f
{
    if (!f)
        return;
    [self setFont:f range:NSMakeRange(0, [_storage length])];
    NSMutableDictionary *t = [[_typing mutableCopy] autorelease];
    [t setObject:f forKey:NSFontAttributeName];
    [self setTypingAttributes:t];
}
- (void)setFont:(NSFont *)f range:(NSRange)r
{
    if (f && r.length)
        [_storage addAttribute:NSFontAttributeName value:f range:r];
}
- (NSColor *)textColor
{
    NSColor *c = [_storage length] ? [_storage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]
                                   : nil;
    return c ?: [_typing objectForKey:NSForegroundColorAttributeName];
}
- (void)setTextColor:(NSColor *)c
{
    [self setTextColor:c range:NSMakeRange(0, [_storage length])];
    NSMutableDictionary *t = [[_typing mutableCopy] autorelease];
    if (c)
        [t setObject:c forKey:NSForegroundColorAttributeName];
    else
        [t removeObjectForKey:NSForegroundColorAttributeName];
    [self setTypingAttributes:t];
}
- (void)setTextColor:(NSColor *)c range:(NSRange)r
{
    if (!r.length)
        return;
    if (c)
        [_storage addAttribute:NSForegroundColorAttributeName value:c range:r];
    else
        [_storage removeAttribute:NSForegroundColorAttributeName range:r];
}
- (NSTextAlignment)alignment
{
    NSParagraphStyle *p = [_storage length] ? [_storage attribute:NSParagraphStyleAttributeName atIndex:0
                                                   effectiveRange:NULL]
                                            : [_typing objectForKey:NSParagraphStyleAttributeName];
    return p ? [p alignment] : NSTextAlignmentNatural;
}
- (void)setAlignment:(NSTextAlignment)a
{
    NSMutableParagraphStyle *p = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [p setAlignment:a];
    if ([_storage length])
        [_storage addAttribute:NSParagraphStyleAttributeName value:p range:NSMakeRange(0, [_storage length])];
    NSMutableDictionary *t = [[_typing mutableCopy] autorelease];
    [t setObject:p forKey:NSParagraphStyleAttributeName];
    [self setTypingAttributes:t];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isHorizontallyResizable { return _horizontal; }
- (void)setHorizontallyResizable:(BOOL)f { _horizontal = f; }
- (BOOL)isVerticallyResizable { return _vertical; }
- (void)setVerticallyResizable:(BOOL)f
{
    _vertical = f;
    [self _invalidate];
}
- (NSSize)minSize { return _minSize; }
- (void)setMinSize:(NSSize)s
{
    _minSize = s;
    [self _invalidate];
}
- (NSSize)maxSize { return _maxSize; }
- (void)setMaxSize:(NSSize)s { _maxSize = s; }
- (BOOL)allowsUndo { return _undo; }
- (void)setAllowsUndo:(BOOL)f { _undo = f; } /* kept: edits aren't undoable yet */
#define SWITCH(get, set, ivar)                                                                                   \
    -(BOOL)get { return ivar; }                                                                                  \
    -(void)set:(BOOL)f { ivar = f; }
SWITCH(usesFindBar, setUsesFindBar, _findBar)
SWITCH(usesFindPanel, setUsesFindPanel, _findPanel)
SWITCH(usesRuler, setUsesRuler, _ruler)
SWITCH(isRulerVisible, setRulerVisible, _rulerVisible)
SWITCH(smartInsertDeleteEnabled, setSmartInsertDeleteEnabled, _smart)
SWITCH(isContinuousSpellCheckingEnabled, setContinuousSpellCheckingEnabled, _spelling)
SWITCH(isGrammarCheckingEnabled, setGrammarCheckingEnabled, _grammar)
SWITCH(isAutomaticQuoteSubstitutionEnabled, setAutomaticQuoteSubstitutionEnabled, _quotes)
SWITCH(isAutomaticDashSubstitutionEnabled, setAutomaticDashSubstitutionEnabled, _dashes)
SWITCH(isAutomaticLinkDetectionEnabled, setAutomaticLinkDetectionEnabled, _links)
SWITCH(isAutomaticTextReplacementEnabled, setAutomaticTextReplacementEnabled, _replacement)
SWITCH(isAutomaticSpellingCorrectionEnabled, setAutomaticSpellingCorrectionEnabled, _correction)
SWITCH(isAutomaticDataDetectionEnabled, setAutomaticDataDetectionEnabled, _detection)
SWITCH(displaysLinkToolTips, setDisplaysLinkToolTips, _linkTips)
SWITCH(allowsImageEditing, setAllowsImageEditing, _images)
SWITCH(allowsDocumentBackgroundColorChange, setAllowsDocumentBackgroundColorChange, _bgChange)
SWITCH(usesInspectorBar, setUsesInspectorBar, _inspector)
SWITCH(isAutomaticTextCompletionEnabled, setAutomaticTextCompletionEnabled, _completion)
- (BOOL)continuousSpellCheckingEnabled { return _spelling; }
- (BOOL)grammarCheckingEnabled { return _grammar; }
- (BOOL)automaticQuoteSubstitutionEnabled { return _quotes; }
- (BOOL)automaticDashSubstitutionEnabled { return _dashes; }
- (BOOL)automaticLinkDetectionEnabled { return _links; }
- (BOOL)automaticTextReplacementEnabled { return _replacement; }
- (BOOL)automaticSpellingCorrectionEnabled { return _correction; }
- (BOOL)automaticDataDetectionEnabled { return _detection; }
- (BOOL)rulerVisible { return _rulerVisible; }

/* ---- layout ---- */

- (void)_invalidate
{
    _laidOut = NO;
    [self setNeedsDisplay:YES];
}
- (void)_textStorageChanged
{
    if (NSMaxRange(_selection) > [_storage length])
        _selection = NSMakeRange([_storage length], 0);
    if (_anchor > [_storage length])
        _anchor = [_storage length];
    [self _invalidate];
    [self _layout];
}
- (CGFloat)_containerWidth
{
    CGFloat w = [_container widthTracksTextView] ? [self bounds].size.width - 2 * _inset.width : [_container size].width;
    return fmax(w - 2 * [_container lineFragmentPadding], 1);
}
/* The text with the typing attributes filled in where a run has none. */
- (NSAttributedString *)_laidText
{
    NSMutableAttributedString *m = [[_storage mutableCopy] autorelease];
    NSUInteger i = 0, n = [m length];
    NSFont *font = [_typing objectForKey:NSFontAttributeName] ?: ADefaultFont();
    NSColor *color = [_typing objectForKey:NSForegroundColorAttributeName] ?: [NSColor textColor];
    while (i < n) {
        NSRange r;
        NSDictionary *a = [m attributesAtIndex:i effectiveRange:&r];
        if (![a objectForKey:NSFontAttributeName])
            [m addAttribute:NSFontAttributeName value:font range:r];
        if (![a objectForKey:NSForegroundColorAttributeName])
            [m addAttribute:NSForegroundColorAttributeName value:color range:r];
        if (_paragraph && ![a objectForKey:NSParagraphStyleAttributeName])
            [m addAttribute:NSParagraphStyleAttributeName value:_paragraph range:r];
        i = NSMaxRange(r);
    }
    return m;
}
- (void)_layout
{
    if (_laidOut && _laidWidth == [self _containerWidth])
        return;
    [self _freeLines];
    CGFloat width = [self _containerWidth], pad = [_container lineFragmentPadding];
    NSAttributedString *text = [self _laidText];
    NSUInteger n = [text length];
    CGFloat bottom = 0;
    if (n) {
        const CGFloat tall = 1e6;
        CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)text);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(0, 0, width, tall));
        CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
        CFArrayRef lines = CTFrameGetLines(frame);
        CFIndex count = CFArrayGetCount(lines);
        _lines = calloc((size_t)count + 1, sizeof *_lines);
        CGPoint *origins = calloc((size_t)count + 1, sizeof *origins);
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), origins);
        for (CFIndex i = 0; i < count; i++) {
            CTLineRef line = CFArrayGetValueAtIndex(lines, i);
            CGFloat a, d, l;
            CTLineGetTypographicBounds(line, &a, &d, &l);
            CFRange r = CTLineGetStringRange(line);
            TVLine *t = &_lines[_lineCount++];
            t->line = CFRetain(line);
            t->range = NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length);
            t->x = origins[i].x + pad;
            t->ascent = a;
            t->descent = d;
            t->top = tall - origins[i].y - a;
            t->height = a + d + l;
            bottom = t->top + t->height;
        }
        free(origins);
        CFRelease(frame);
        CGPathRelease(path);
        CFRelease(fs);
    }
    /* a caret after a final newline (or in empty text) sits on a line of its own */
    if (!n || [[text string] characterAtIndex:n - 1] == '\n') {
        if (!_lines)
            _lines = calloc(1, sizeof *_lines);
        NSFont *font = n ? [text attribute:NSFontAttributeName atIndex:n - 1 effectiveRange:NULL]
                         : [_typing objectForKey:NSFontAttributeName];
        font = font ?: ADefaultFont();
        TVLine *t = &_lines[_lineCount++];
        t->range = NSMakeRange(n, 0);
        t->x = pad;
        t->ascent = CTFontGetAscent((CTFontRef)font);
        t->descent = CTFontGetDescent((CTFontRef)font);
        t->height = t->ascent + t->descent + CTFontGetLeading((CTFontRef)font);
        t->top = bottom;
        bottom += t->height;
    }
    _used = NSMakeRect(0, 0, width + 2 * pad, ceil(bottom));
    _laidOut = YES;
    _laidWidth = width;
    [self _sizeToText];
}
- (NSRect)_usedRect
{
    [self _layout];
    return _used;
}
/* Grows or shrinks a vertically resizable view to its text, never below its
 * minimum size or the clip view showing it. */
- (void)_sizeToText
{
    if (_sizing || !_vertical)
        return;
    CGFloat h = fmax(_used.size.height + 2 * _inset.height, _minSize.height);
    NSView *sv = [self superview];
    if ([sv isKindOfClass:[NSClipView class]])
        h = fmax(h, [sv bounds].size.height);
    h = fmin(h, _maxSize.height);
    if (fabs(h - [self frame].size.height) < 0.5)
        return;
    _sizing = YES;
    [self setFrameSize:NSMakeSize([self frame].size.width, h)];
    _sizing = NO;
}
- (void)_clipViewResized:(NSClipView *)clip
{
    NSSize s = [self frame].size;
    if (!_horizontal && ([self autoresizingMask] & NSViewWidthSizable || [_container widthTracksTextView]))
        s.width = [clip bounds].size.width;
    if (!NSEqualSizes(s, [self frame].size)) {
        _sizing = YES;
        [self setFrameSize:s];
        _sizing = NO;
    }
    _laidOut = NO;
    [self _layout];
}
- (void)setFrameSize:(NSSize)s
{
    BOOL widthChanged = s.width != [self frame].size.width;
    [super setFrameSize:s];
    if (widthChanged && !_sizing) {
        _laidOut = NO;
        [self _layout];
    }
}
- (void)sizeToFit
{
    _laidOut = NO;
    [self _layout];
}

/* ---- geometry of the text ---- */

- (NSUInteger)_lineFor:(NSUInteger)index
{
    [self _layout];
    for (NSUInteger i = 0; i < _lineCount; i++) {
        NSRange r = _lines[i].range;
        if (index < NSMaxRange(r) || (i + 1 == _lineCount))
            return i;
        /* the end of a line that doesn't end in a newline is still that line */
        if (index == NSMaxRange(r) && (i + 1 == _lineCount || _lines[i + 1].range.location > index))
            return i;
    }
    return 0;
}
- (CGFloat)_xFor:(NSUInteger)index onLine:(NSUInteger)i
{
    TVLine *t = &_lines[i];
    if (!t->line)
        return t->x + _inset.width;
    return t->x + _inset.width + CTLineGetOffsetForStringIndex(t->line, (CFIndex)index, NULL);
}
- (NSUInteger)_indexOnLine:(NSUInteger)i atX:(CGFloat)x
{
    TVLine *t = &_lines[i];
    if (!t->line)
        return t->range.location;
    CFIndex k = CTLineGetStringIndexForPosition(t->line, CGPointMake(x - t->x - _inset.width, 0));
    NSUInteger index = k < 0 ? t->range.location : (NSUInteger)k;
    NSUInteger end = NSMaxRange(t->range);
    NSString *s = [_storage string];
    /* stay before the line's own newline */
    if (index >= end && end > t->range.location && [s characterAtIndex:end - 1] == '\n')
        index = end - 1;
    return MIN(MAX(index, t->range.location), end);
}
- (NSUInteger)characterIndexForInsertionAtPoint:(NSPoint)p
{
    [self _layout];
    if (!_lineCount)
        return 0;
    CGFloat y = p.y - _inset.height;
    NSUInteger i = 0;
    while (i + 1 < _lineCount && y >= _lines[i].top + _lines[i].height)
        i++;
    return [self _indexOnLine:i atX:p.x];
}
/* The rectangle the characters in a range take, in the text container's
 * coordinates (the view's, less the inset): the union of each line's part. */
- (NSRect)_rectForRange:(NSRange)range
{
    [self _layout];
    if (!_lineCount)
        return NSZeroRect;
    NSUInteger end = NSMaxRange(range);
    NSRect all = NSZeroRect;
    BOOL any = NO;
    for (NSUInteger i = 0; i < _lineCount; i++) {
        TVLine *t = &_lines[i];
        NSUInteger ls = t->range.location, le = NSMaxRange(t->range);
        BOOL touches = range.length ? (ls < end && le > range.location)
                                    : (range.location >= ls && (range.location < le || i + 1 == _lineCount));
        if (!touches)
            continue;
        NSUInteger a = MAX(ls, range.location), b = MIN(le, end);
        CGFloat x0 = [self _xFor:a onLine:i] - _inset.width, x1 = [self _xFor:b onLine:i] - _inset.width;
        NSRect r = NSMakeRect(fmin(x0, x1), t->top, fabs(x1 - x0), t->height);
        all = any ? NSUnionRect(all, r) : r;
        any = YES;
        if (!range.length)
            break;
    }
    return all;
}
/* the characters of the lines a rectangle (in the container's coordinates) crosses */
- (NSRange)_rangeForRect:(NSRect)rect
{
    [self _layout];
    NSUInteger start = NSNotFound, end = 0;
    for (NSUInteger i = 0; i < _lineCount; i++) {
        TVLine *t = &_lines[i];
        if (t->top + t->height <= NSMinY(rect) || t->top >= NSMaxY(rect))
            continue;
        start = MIN(start, t->range.location);
        end = MAX(end, NSMaxRange(t->range));
    }
    return start == NSNotFound ? NSMakeRange(0, 0) : NSMakeRange(start, end - start);
}
- (NSRect)_lineRectForIndex:(NSUInteger)index range:(NSRangePointer)range
{
    [self _layout];
    if (!_lineCount) {
        if (range)
            *range = NSMakeRange(0, 0);
        return NSZeroRect;
    }
    NSUInteger i = [self _lineFor:index];
    TVLine *t = &_lines[i];
    if (range)
        *range = t->range;
    return NSMakeRect(0, t->top, [self _containerWidth] + 2 * [_container lineFragmentPadding], t->height);
}
- (NSRect)_caretRect
{
    NSUInteger i = [self _lineFor:_selection.location];
    TVLine *t = &_lines[i];
    return NSMakeRect(floor([self _xFor:_selection.location onLine:i]), t->top + _inset.height, 1, ceil(t->height));
}

/* ---- drawing ---- */

- (void)drawRect:(NSRect)dirty
{
    [self _layout];
    if (_drawsBackground) {
        [[self backgroundColor] setFill];
        NSRectFill(dirty);
    }
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    BOOL focused = [[self window] firstResponder] == self && [[self window] isKeyWindow];
    /* printed (or drawn into an image), the text has no selection or caret */
    BOOL screen = [NSGraphicsContext currentContextDrawingToScreen];
    focused = focused && screen;
    if (_selection.length && screen) {
        [(focused ? [NSColor selectedTextBackgroundColor] : [NSColor colorWithCalibratedWhite:0.86 alpha:1]) setFill];
        NSUInteger end = NSMaxRange(_selection);
        for (NSUInteger i = 0; i < _lineCount; i++) {
            NSRange r = _lines[i].range;
            if (NSMaxRange(r) <= _selection.location || r.location >= end)
                continue;
            CGFloat x0 = [self _xFor:MAX(r.location, _selection.location) onLine:i];
            CGFloat x1 = end >= NSMaxRange(r) && end > r.location && i + 1 < _lineCount
                             ? [self bounds].size.width - _inset.width
                             : [self _xFor:MIN(end, NSMaxRange(r)) onLine:i];
            NSRectFill(NSMakeRect(x0, _lines[i].top + _inset.height, fmax(x1 - x0, 1), ceil(_lines[i].height)));
        }
    }
    if (cg) {
        CGContextSaveGState(cg);
        CGAffineTransform saved = CGContextGetTextMatrix(cg);
        CGContextSetTextMatrix(cg, CGAffineTransformMakeScale(1, -1));
        for (NSUInteger i = 0; i < _lineCount; i++) {
            TVLine *t = &_lines[i];
            CGFloat top = t->top + _inset.height;
            if (!t->line || top > NSMaxY(dirty) || top + t->height < NSMinY(dirty))
                continue;
            CGContextSetTextPosition(cg, t->x + _inset.width, top + t->ascent);
            CTLineDraw(t->line, cg);
        }
        CGContextSetTextMatrix(cg, saved);
        CGContextRestoreGState(cg);
    }
    if (focused && _editable && !_selection.length) {
        [[self insertionPointColor] setFill];
        NSRectFill([self _caretRect]);
    }
}

/* ---- printing ---- */

/* A page ends above a line that its bottom would cut through, so each
 * line is printed whole on one page (unless that would move the bottom
 * past the limit). */
- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)top bottom:(CGFloat)bottom limit:(CGFloat)limit
{
    [self _layout];
    *newBottom = bottom;
    for (NSUInteger i = 0; i < _lineCount; i++) {
        CGFloat lineTop = _lines[i].top + _inset.height, lineBottom = lineTop + _lines[i].height;
        if (lineTop < bottom && lineBottom > bottom) {
            if (lineTop >= limit && lineTop > top)
                *newBottom = lineTop;
            return;
        }
    }
}

/* ---- fonts ---- */

/* The font of the selection (or of what typing would insert), told to the
 * font manager, with whether the selection has more than one. */
- (void)_tellFontManager
{
    NSFontManager *fm = AExistingFontManager();
    if (!fm || !_fontPanel || ([self window] && [[self window] firstResponder] != self))
        return;
    NSFont *font = nil;
    BOOL multiple = NO;
    NSUInteger n = [_storage length];
    if (_selection.length && _selection.location < n) {
        NSRange run;
        font = [_storage attribute:NSFontAttributeName atIndex:_selection.location longestEffectiveRange:&run
                           inRange:_selection];
        multiple = NSMaxRange(run) < NSMaxRange(_selection);
    } else if (_typingAt != _selection.location && _selection.location > 0 && _selection.location <= n) {
        font = [_storage attribute:NSFontAttributeName atIndex:_selection.location - 1 effectiveRange:NULL];
    }
    [fm setSelectedFont:font ?: [_typing objectForKey:NSFontAttributeName] ?: ADefaultFont() isMultiple:multiple];
}

/* The font manager's changeFont: converts each font in the selection (all
 * of plain text), or the font typing will use. */
- (void)changeFont:(id)sender
{
    if (!_fontPanel || ![sender respondsToSelector:@selector(convertFont:)])
        return;
    NSUInteger n = [_storage length];
    NSRange r = _rich ? _selection : NSMakeRange(0, n);
    if (r.length && NSMaxRange(r) <= n) {
        if (![self shouldChangeTextInRange:r replacementString:nil])
            return;
        NSFont *fallback = [_typing objectForKey:NSFontAttributeName] ?: ADefaultFont();
        [_storage beginEditing];
        for (NSUInteger i = r.location; i < NSMaxRange(r);) {
            NSRange run;
            NSFont *f = [_storage attribute:NSFontAttributeName atIndex:i longestEffectiveRange:&run inRange:r];
            NSFont *converted = [sender convertFont:f ?: fallback];
            if (converted)
                [_storage addAttribute:NSFontAttributeName value:converted range:run];
            i = MAX(NSMaxRange(run), i + 1);
        }
        [_storage endEditing];
        [self didChangeText];
    }
    if (!_selection.length || !_rich) {
        /* an empty selection: the next text typed here takes the new font */
        NSFont *now = nil;
        if (_typingAt != _selection.location && _selection.location > 0 && _selection.location <= n)
            now = [_storage attribute:NSFontAttributeName atIndex:_selection.location - 1 effectiveRange:NULL];
        NSMutableDictionary *t = [[_typing mutableCopy] autorelease];
        if (_typingAt != _selection.location && _selection.location > 0 && _selection.location <= n)
            [t addEntriesFromDictionary:[_storage attributesAtIndex:_selection.location - 1 effectiveRange:NULL]];
        NSFont *converted = [sender convertFont:now ?: [_typing objectForKey:NSFontAttributeName] ?: ADefaultFont()];
        if (converted)
            [t setObject:converted forKey:NSFontAttributeName];
        [self setTypingAttributes:t];
        _typingAt = _selection.location;
    }
    [self _tellFontManager];
    [self setNeedsDisplay:YES];
}

/* ---- selection ---- */

- (NSRange)selectedRange { return _selection; }
- (NSArray *)selectedRanges { return @[ [NSValue valueWithRange:_selection] ]; }
- (void)setSelectedRange:(NSRange)r affinity:(NSInteger)affinity stillSelecting:(BOOL)still
{
    NSUInteger n = [_storage length];
    r.location = MIN(r.location, n);
    r.length = MIN(r.length, n - r.location);
    BOOL changed = !NSEqualRanges(r, _selection);
    if (r.location != _typingAt || r.length)
        _typingAt = NSNotFound; /* typing attributes set for another place */
    _selection = r;
    [self setNeedsDisplay:YES];
    if (changed && !still)
        [self _tellFontManager];
    if (changed && !still) {
        NSNotification *note = [NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:self];
        if ([_delegate respondsToSelector:@selector(textViewDidChangeSelection:)])
            [_delegate textViewDidChangeSelection:note];
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
}
- (void)setSelectedRange:(NSRange)r
{
    _anchor = r.location;
    [self setSelectedRange:r affinity:0 stillSelecting:NO];
}
- (void)selectAll:(id)sender
{
    if (_selectable)
        [self setSelectedRange:NSMakeRange(0, [_storage length])];
}
- (void)_selectFromAnchorTo:(NSUInteger)i
{
    NSRange r = i < _anchor ? NSMakeRange(i, _anchor - i) : NSMakeRange(_anchor, i - _anchor);
    [self setSelectedRange:r affinity:0 stillSelecting:_dragging];
}
/* The end of the selection that moves: the one away from the anchor. */
- (NSUInteger)_head { return _selection.location < _anchor ? _selection.location : NSMaxRange(_selection); }
- (void)_moveTo:(NSUInteger)i select:(BOOL)select
{
    i = MIN(i, [_storage length]);
    if (select)
        [self _selectFromAnchorTo:i];
    else {
        _anchor = i;
        [self setSelectedRange:NSMakeRange(i, 0) affinity:0 stillSelecting:NO];
    }
    [self scrollRangeToVisible:NSMakeRange(i, 0)];
}
- (void)scrollRangeToVisible:(NSRange)r
{
    if (![self window] && ![self superview])
        return;
    NSUInteger saved = _selection.location;
    _selection.location = MIN(r.location, [_storage length]);
    NSRect caret = [self _caretRect];
    _selection.location = saved;
    [self scrollRectToVisible:NSInsetRect(caret, -2, 0)];
}

/* ---- the mouse ---- */

- (BOOL)acceptsFirstResponder { return _selectable; }
- (BOOL)becomeFirstResponder
{
    [self setNeedsDisplay:YES];
    return YES;
}
- (BOOL)resignFirstResponder
{
    if (_began) {
        _began = NO;
        ABindingsPush(self, NO);
        [self _post:NSTextDidEndEditingNotification selector:@selector(textDidEndEditing:)];
    }
    [self setNeedsDisplay:YES];
    return YES;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (void)mouseDown:(NSEvent *)e
{
    if (!_selectable)
        return;
    if ([[self window] firstResponder] != self)
        [[self window] makeFirstResponder:self];
    NSUInteger i = [self characterIndexForInsertionAtPoint:[self convertPoint:[e locationInWindow] fromView:nil]];
    if ([e clickCount] == 2) {
        [self _selectWordAt:i];
        return;
    }
    if ([e modifierFlags] & NSEventModifierFlagShift)
        [self _selectFromAnchorTo:i];
    else {
        _anchor = i;
        [self setSelectedRange:NSMakeRange(i, 0) affinity:0 stillSelecting:YES];
    }
    _dragging = YES;
    _wantX = -1;
}
- (void)mouseDragged:(NSEvent *)e
{
    if (!_dragging)
        return;
    [self autoscroll:e];
    [self _selectFromAnchorTo:[self characterIndexForInsertionAtPoint:[self convertPoint:[e locationInWindow]
                                                                               fromView:nil]]];
}
- (void)mouseUp:(NSEvent *)e
{
    if (!_dragging)
        return;
    _dragging = NO;
    [self setSelectedRange:_selection affinity:0 stillSelecting:NO];
}
- (void)_selectWordAt:(NSUInteger)i
{
    NSString *s = [_storage string];
    NSCharacterSet *word = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger a = i, b = i;
    while (a > 0 && [word characterIsMember:[s characterAtIndex:a - 1]])
        a--;
    while (b < [s length] && [word characterIsMember:[s characterAtIndex:b]])
        b++;
    _anchor = a;
    [self setSelectedRange:NSMakeRange(a, b - a) affinity:0 stillSelecting:NO];
}

/* ---- typing ---- */

- (void)_post:(NSNotificationName)name selector:(SEL)sel
{
    NSNotification *note = [NSNotification notificationWithName:name object:self];
    if ([_delegate respondsToSelector:sel])
        [_delegate performSelector:sel withObject:note];
    [[NSNotificationCenter defaultCenter] postNotification:note];
}
- (BOOL)shouldChangeTextInRange:(NSRange)r replacementString:(NSString *)s
{
    if (!_editable)
        return NO;
    if ([_delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementString:)] &&
        ![_delegate textView:self shouldChangeTextInRange:r replacementString:s])
        return NO;
    if (!_began) {
        _began = YES;
        [self _post:NSTextDidBeginEditingNotification selector:@selector(textDidBeginEditing:)];
    }
    return YES;
}
- (void)didChangeText
{
    ABindingsPush(self, YES);
    [self _post:NSTextDidChangeNotification selector:@selector(textDidChange:)];
}
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s
{
    NSAttributedString *a = [[[NSAttributedString alloc] initWithString:s ?: @"" attributes:_typing] autorelease];
    [_storage replaceCharactersInRange:r withAttributedString:a];
}
- (void)_typeIn:(NSString *)s
{
    if (![self shouldChangeTextInRange:_selection replacementString:s])
        return;
    NSRange r = _selection;
    /* text typed after a run takes that run's look, as on a Mac */
    NSDictionary *look = _typing;
    if (r.location > 0 && r.location <= [_storage length] && [_storage length] && _typingAt != r.location)
        look = [_storage attributesAtIndex:r.location - 1 effectiveRange:NULL];
    NSAttributedString *a = [[[NSAttributedString alloc] initWithString:s attributes:look] autorelease];
    [_storage replaceCharactersInRange:r withAttributedString:a];
    _anchor = r.location + [s length];
    [self setSelectedRange:NSMakeRange(_anchor, 0) affinity:0 stillSelecting:NO];
    _wantX = -1;
    [self didChangeText];
    [self scrollRangeToVisible:_selection];
}
- (void)keyDown:(NSEvent *)e
{
    if (_selectable)
        [self interpretKeyEvents:@[ e ]];
    else
        [super keyDown:e];
}
- (void)insertText:(id)string
{
    if (!_editable) {
        NSBeep();
        return;
    }
    [self _typeIn:[string isKindOfClass:[NSAttributedString class]] ? [string string] : string];
}
- (void)insertText:(id)string replacementRange:(NSRange)r
{
    if (r.location != NSNotFound)
        [self setSelectedRange:r];
    [self insertText:string];
}
- (void)doCommandBySelector:(SEL)sel
{
    if ([_delegate respondsToSelector:@selector(textView:doCommandBySelector:)] &&
        [_delegate textView:self doCommandBySelector:sel])
        return;
    [super doCommandBySelector:sel];
}
- (void)insertNewline:(id)sender
{
    if (_fieldEditor) {
        [[self window] makeFirstResponder:nil];
        return;
    }
    [self insertText:@"\n"];
}
- (void)insertTab:(id)sender
{
    if (_fieldEditor)
        [[self window] selectNextKeyView:self];
    else
        [self insertText:@"\t"];
}
- (void)insertBacktab:(id)sender { [[self window] selectPreviousKeyView:self]; }
- (void)insertNewlineIgnoringFieldEditor:(id)sender { [self _typeIn:@"\n"]; }
- (void)insertTabIgnoringFieldEditor:(id)sender { [self _typeIn:@"\t"]; }

- (NSUInteger)_step:(NSUInteger)i forward:(BOOL)forward
{
    /* keeps surrogate pairs whole */
    NSString *s = [_storage string];
    NSUInteger n = [s length];
    if (forward) {
        if (i >= n)
            return n;
        i++;
        if (i < n && ([s characterAtIndex:i] >= 0xdc00 && [s characterAtIndex:i] <= 0xdfff))
            i++;
        return i;
    }
    if (i == 0)
        return 0;
    i--;
    if (i > 0 && ([s characterAtIndex:i] >= 0xdc00 && [s characterAtIndex:i] <= 0xdfff))
        i--;
    return i;
}
- (NSUInteger)_word:(NSUInteger)i forward:(BOOL)forward
{
    NSString *s = [_storage string];
    NSCharacterSet *w = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger n = [s length];
    if (forward) {
        while (i < n && ![w characterIsMember:[s characterAtIndex:i]])
            i++;
        while (i < n && [w characterIsMember:[s characterAtIndex:i]])
            i++;
    } else {
        while (i > 0 && ![w characterIsMember:[s characterAtIndex:i - 1]])
            i--;
        while (i > 0 && [w characterIsMember:[s characterAtIndex:i - 1]])
            i--;
    }
    return i;
}
- (void)_deleteTo:(NSUInteger)i
{
    if (!_editable) {
        NSBeep();
        return;
    }
    NSRange r = _selection;
    if (!r.length)
        r = i < r.location ? NSMakeRange(i, r.location - i) : NSMakeRange(r.location, i - r.location);
    if (!r.length)
        return;
    _selection = r;
    [self _typeIn:@""];
}
- (NSUInteger)_lineStart:(NSUInteger)i { return _lines[[self _lineFor:i]].range.location; }
- (NSUInteger)_lineEnd:(NSUInteger)i
{
    TVLine *t = &_lines[[self _lineFor:i]];
    NSUInteger end = NSMaxRange(t->range);
    if (end > t->range.location && [[_storage string] characterAtIndex:end - 1] == '\n')
        end--;
    return end;
}
- (NSUInteger)_vertical:(NSInteger)lines from:(NSUInteger)i
{
    NSUInteger at = [self _lineFor:i];
    if (_wantX < 0)
        _wantX = [self _xFor:i onLine:at];
    NSInteger to = (NSInteger)at + lines;
    if (to < 0)
        return 0;
    if (to >= (NSInteger)_lineCount)
        return [_storage length];
    return [self _indexOnLine:(NSUInteger)to atX:_wantX];
}
- (NSInteger)_linesPerPage
{
    CGFloat h = [self visibleRect].size.height;
    CGFloat line = _lineCount ? _lines[0].height : 14;
    return MAX((NSInteger)(h / fmax(line, 1)) - 1, 1);
}
- (void)deleteBackward:(id)sender { [self _deleteTo:[self _step:_selection.location forward:NO]]; }
- (void)deleteForward:(id)sender { [self _deleteTo:[self _step:NSMaxRange(_selection) forward:YES]]; }
- (void)deleteWordBackward:(id)sender { [self _deleteTo:[self _word:_selection.location forward:NO]]; }
- (void)deleteWordForward:(id)sender { [self _deleteTo:[self _word:_selection.location forward:YES]]; }
- (void)deleteToBeginningOfLine:(id)sender { [self _deleteTo:[self _lineStart:_selection.location]]; }
- (void)deleteToEndOfLine:(id)sender { [self _deleteTo:[self _lineEnd:_selection.location]]; }
- (void)deleteToEndOfParagraph:(id)sender { [self deleteToEndOfLine:sender]; }

#define MOVE(name, target, extend)                                                                               \
    -(void)name:(id)sender                                                                                       \
    {                                                                                                            \
        NSUInteger head = [self _head];                                                                          \
        (void)head;                                                                                              \
        [self _moveTo:(target) select:extend];                                                                   \
    }
- (void)moveLeft:(id)sender
{
    _wantX = -1;
    [self _moveTo:_selection.length ? _selection.location : [self _step:_selection.location forward:NO] select:NO];
}
- (void)moveRight:(id)sender
{
    _wantX = -1;
    [self _moveTo:_selection.length ? NSMaxRange(_selection) : [self _step:_selection.location forward:YES] select:NO];
}
- (void)moveBackward:(id)sender { [self moveLeft:sender]; }
- (void)moveForward:(id)sender { [self moveRight:sender]; }
MOVE(moveLeftAndModifySelection, [self _step:head forward:NO], YES)
MOVE(moveRightAndModifySelection, [self _step:head forward:YES], YES)
MOVE(moveWordLeft, [self _word:head forward:NO], NO)
MOVE(moveWordRight, [self _word:head forward:YES], NO)
MOVE(moveWordLeftAndModifySelection, [self _word:head forward:NO], YES)
MOVE(moveWordRightAndModifySelection, [self _word:head forward:YES], YES)
MOVE(moveToBeginningOfLine, [self _lineStart:head], NO)
MOVE(moveToEndOfLine, [self _lineEnd:head], NO)
MOVE(moveToBeginningOfLineAndModifySelection, [self _lineStart:head], YES)
MOVE(moveToEndOfLineAndModifySelection, [self _lineEnd:head], YES)
MOVE(moveToLeftEndOfLine, [self _lineStart:head], NO)
MOVE(moveToRightEndOfLine, [self _lineEnd:head], NO)
MOVE(moveToBeginningOfDocument, 0, NO)
MOVE(moveToEndOfDocument, [_storage length], NO)
MOVE(moveToBeginningOfDocumentAndModifySelection, 0, YES)
MOVE(moveToEndOfDocumentAndModifySelection, [_storage length], YES)
MOVE(moveUp, [self _vertical:-1 from:head], NO)
MOVE(moveDown, [self _vertical:1 from:head], NO)
MOVE(moveUpAndModifySelection, [self _vertical:-1 from:head], YES)
MOVE(moveDownAndModifySelection, [self _vertical:1 from:head], YES)
MOVE(pageUp, [self _vertical:-[self _linesPerPage] from:head], NO)
MOVE(pageDown, [self _vertical:[self _linesPerPage] from:head], NO)
MOVE(pageUpAndModifySelection, [self _vertical:-[self _linesPerPage] from:head], YES)
MOVE(pageDownAndModifySelection, [self _vertical:[self _linesPerPage] from:head], YES)
- (void)moveToBeginningOfParagraph:(id)sender { [self moveToBeginningOfLine:sender]; }
- (void)moveToEndOfParagraph:(id)sender { [self moveToEndOfLine:sender]; }
- (void)scrollToBeginningOfDocument:(id)sender { [self scrollRangeToVisible:NSMakeRange(0, 0)]; }
- (void)scrollToEndOfDocument:(id)sender { [self scrollRangeToVisible:NSMakeRange([_storage length], 0)]; }
- (void)scrollPageUp:(id)sender
{
    NSRect v = [self visibleRect];
    [self scrollPoint:NSMakePoint(v.origin.x, v.origin.y - v.size.height)];
}
- (void)scrollPageDown:(id)sender
{
    NSRect v = [self visibleRect];
    [self scrollPoint:NSMakePoint(v.origin.x, NSMaxY(v))];
}
- (void)cancelOperation:(id)sender {}

- (void)copy:(id)sender
{
    if (!_selection.length) {
        NSBeep();
        return;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[[_storage string] substringWithRange:_selection] forType:NSPasteboardTypeString];
}
- (void)cut:(id)sender
{
    if (!_editable || !_selection.length) {
        NSBeep();
        return;
    }
    [self copy:sender];
    [self _typeIn:@""];
}
- (void)paste:(id)sender
{
    NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (!s || !_editable) {
        NSBeep();
        return;
    }
    [self insertText:s];
}
- (void)pasteAsPlainText:(id)sender { [self paste:sender]; }
- (void)delete:(id)sender { [self deleteBackward:sender]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL a = [item action];
    if (a == @selector(copy:))
        return _selection.length > 0;
    if (a == @selector(cut:) || a == @selector(delete:))
        return _editable && _selection.length > 0;
    if (a == @selector(paste:) || a == @selector(pasteAsPlainText:))
        return _editable && [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] != nil;
    if (a == @selector(selectAll:))
        return _selectable && [_storage length] > 0;
    return [self respondsToSelector:a];
}

/* ---- rich text in and out ---- */

- (NSData *)RTFFromRange:(NSRange)r
{
    return [[_storage attributedSubstringFromRange:r] RTFFromRange:NSMakeRange(0, r.length) documentAttributes:@{}];
}
- (BOOL)readRTFDFromFile:(NSString *)path
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d && [[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"TXT.rtf"]])
        d = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"TXT.rtf"]];
    NSAttributedString *a = d ? [[[NSAttributedString alloc] initWithRTF:d documentAttributes:NULL] autorelease] : nil;
    if (!a)
        return NO;
    [_storage setAttributedString:a];
    return YES;
}
- (void)replaceCharactersInRange:(NSRange)r withRTF:(NSData *)rtf
{
    NSAttributedString *a = [[[NSAttributedString alloc] initWithRTF:rtf documentAttributes:NULL] autorelease];
    if (a)
        [_storage replaceCharactersInRange:r withAttributedString:a];
}

/* the proposed range made whole words or paragraphs (freemac 1.222, Ferry 0.46.0) */
- (NSSelectionGranularity)selectionGranularity { return _granularity; }
- (void)setSelectionGranularity:(NSSelectionGranularity)granularity { _granularity = granularity; }
- (NSRange)selectionRangeForProposedRange:(NSRange)proposed granularity:(NSSelectionGranularity)granularity
{
    NSString *text = [_storage string];
    NSUInteger length = [text length];
    if (proposed.location > length)
        proposed = NSMakeRange(length, 0);
    if (NSMaxRange(proposed) > length)
        proposed.length = length - proposed.location;
    if (granularity == NSSelectByParagraph)
        return [text paragraphRangeForRange:proposed];
    if (granularity != NSSelectByWord || !length)
        return proposed;
    NSCharacterSet *word = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger start = proposed.location, end = NSMaxRange(proposed);
    if (!proposed.length && start < length && ![word characterIsMember:[text characterAtIndex:start]])
        return NSMakeRange(start, 1); /* a space or a mark on its own */
    while (start > 0 && [word characterIsMember:[text characterAtIndex:start - 1]])
        start--;
    while (end < length && [word characterIsMember:[text characterAtIndex:end]])
        end++;
    return NSMakeRange(start, end - start);
}
@end

/* A text view's value binding is its plain text, its attributedString one
 * its text with its runs (1.229): what the user typed is written back when
 * they leave it, or as they type when the binding asks for that. */
@implementation NSTextView (FerryBindings)
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding]) {
        NSString *s = [value isKindOfClass:[NSString class]]             ? value
                      : [value isKindOfClass:[NSAttributedString class]] ? [value string]
                      : value && value != [NSNull null]                  ? [value description]
                                                                         : @"";
        if (![s isEqualToString:[self string]])
            [self setString:s];
    } else if ([binding isEqualToString:NSAttributedStringBinding]) {
        NSAttributedString *a = [value isKindOfClass:[NSAttributedString class]] ? value : nil;
        if (!a)
            a = [[[NSAttributedString alloc] initWithString:[value isKindOfClass:[NSString class]] ? value : @""]
                autorelease];
        [[self textStorage] setAttributedString:a];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding])
        return [[[self string] copy] autorelease];
    if ([binding isEqualToString:NSAttributedStringBinding])
        return [[[NSAttributedString alloc] initWithAttributedString:[self textStorage]] autorelease];
    return [super _ferryValueForBinding:binding];
}
@end
