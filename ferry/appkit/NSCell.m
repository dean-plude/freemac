/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSCell and its common subclasses. Ferry's controls draw
 * and keep their state themselves, so a cell here is mostly a record of a
 * control's settings: nib files store a control's title, font, flags and
 * so on in its cell, and the control copies them when it is loaded. A
 * program can also make and read cells itself.
 *
 * Nibs keep a cell's switches in two flag words, "NSCellFlags" and
 * "NSCellFlags2". The bits used here (state, enabled, editable, selectable,
 * bordered, bezeled, scrollable, alignment, line breaking, control size)
 * follow descriptions of the format published by developers and by the
 * GNUstep project; no Apple code was read. Named keys are used instead
 * where a nib has them. */
#import "AInternal.h"

enum {
    CELL_STATE = 0x80000000u,
    CELL_HIGHLIGHTED = 0x40000000u,
    CELL_DISABLED = 0x20000000u,
    CELL_EDITABLE = 0x10000000u,
    CELL_BORDERED = 0x00800000u,
    CELL_BEZELED = 0x00400000u,
    CELL_SELECTABLE = 0x00200000u,
    CELL_SCROLLABLE = 0x00100000u,
    CELL_CONTINUOUS = 0x00080000u,
    CELL_WRAPS = 0x00000040u, /* written for wrapping cells; read as "truncates the last line" */
};

static id coder_value(NSCoder *c, NSString *key)
{
    return [c containsValueForKey:key] ? [c decodeObjectForKey:key] : nil;
}

/* a matrix shows its cells with buttons of their own: it hears of a change */
static void cell_changed(NSCell *cell, NSView *view)
{
    if ([view respondsToSelector:@selector(updateCell:)])
        [view performSelector:@selector(updateCell:) withObject:cell];
}
@implementation NSCell {
@protected
    id _value;
    NSFont *_font;
    NSTextAlignment _alignment;
    NSLineBreakMode _lineBreak;
    BOOL _enabled, _editable, _selectable, _bordered, _bezeled, _scrollable, _wraps, _highlighted, _continuous;
    NSControlStateValue _state;
    NSInteger _tag;
    NSControlSize _controlSize;
    id _target;
    SEL _action;
    NSView *_controlView;
    NSInteger _backgroundStyle;
    NSFormatter *_formatter;
    NSMenu *_menu;
    BOOL _showsFirstResponder;
    id _represented;
    BOOL _sendsOnEndEditing, _allowsMixed, _refusesFirstResponder, _allowsUndo, _singleLine;
    NSFocusRingType _focusRing;
    NSWritingDirection _writingDirection;
    NSInteger _sendMask;
}

/* Light or dark ground behind the cell (a selected table row is dark):
 * kept for the app; Ferry's cells draw the same either way. */
- (NSBackgroundStyle)backgroundStyle { return (NSBackgroundStyle)_backgroundStyle; }
- (void)setBackgroundStyle:(NSBackgroundStyle)style { _backgroundStyle = style; }
- (NSBackgroundStyle)interiorBackgroundStyle { return (NSBackgroundStyle)_backgroundStyle; }
- (instancetype)init { return [self initTextCell:@""]; }
- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super init])) {
        _value = [string copy];
        _enabled = YES;
        _alignment = NSTextAlignmentNatural;
        _lineBreak = NSLineBreakByWordWrapping;
        _wraps = YES;
    }
    return self;
}
- (instancetype)initImageCell:(NSImage *)image
{
    if ((self = [self initTextCell:@""])) {
        [_value release];
        _value = [image retain];
    }
    return self;
}
- (void)dealloc
{
    [_represented release];
    [_value release];
    [_font release];
    [_formatter release];
    [_menu release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSCell *c = [[[self class] allocWithZone:zone] initTextCell:@""];
    [c setObjectValue:_value];
    [c setFont:_font];
    c->_alignment = _alignment;
    c->_lineBreak = _lineBreak;
    c->_enabled = _enabled;
    c->_editable = _editable;
    c->_selectable = _selectable;
    c->_bordered = _bordered;
    c->_bezeled = _bezeled;
    c->_scrollable = _scrollable;
    c->_wraps = _wraps;
    c->_state = _state;
    c->_tag = _tag;
    c->_controlSize = _controlSize;
    c->_target = _target;
    c->_action = _action;
    c->_formatter = [_formatter retain];
    return c;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [self initTextCell:@""]))
        return nil;
    id contents = coder_value(coder, @"NSContents");
    if ([contents isKindOfClass:[NSString class]] || [contents isKindOfClass:[NSAttributedString class]] ||
        [contents isKindOfClass:[NSNumber class]] || [contents isKindOfClass:[NSImage class]])
        [self setObjectValue:contents];
    NSFont *font = coder_value(coder, @"NSSupport");
    if ([font isKindOfClass:[NSFont class]])
        [self setFont:font];
    if ([coder containsValueForKey:@"NSCellFlags"]) {
        unsigned f = (unsigned)[coder decodeInt64ForKey:@"NSCellFlags"];
        _state = (f & CELL_STATE) ? NSControlStateValueOn : NSControlStateValueOff;
        _highlighted = (f & CELL_HIGHLIGHTED) != 0;
        _enabled = !(f & CELL_DISABLED);
        _editable = (f & CELL_EDITABLE) != 0;
        _bordered = (f & CELL_BORDERED) != 0;
        _bezeled = (f & CELL_BEZELED) != 0;
        _selectable = (f & CELL_SELECTABLE) != 0 || _editable;
        _scrollable = (f & CELL_SCROLLABLE) != 0;
        _continuous = (f & CELL_CONTINUOUS) != 0;
        _wraps = (f & CELL_WRAPS) != 0;
    }
    if ([coder containsValueForKey:@"NSCellFlags2"]) {
        unsigned f = (unsigned)[coder decodeInt64ForKey:@"NSCellFlags2"];
        /* Alignment is stored in the Mac's old order: left, right, centre,
         * justified, natural. */
        static const NSTextAlignment align[] = {NSTextAlignmentLeft, NSTextAlignmentRight, NSTextAlignmentCenter,
                                                NSTextAlignmentJustified, NSTextAlignmentNatural};
        unsigned a = (f >> 26) & 7;
        _alignment = a < 5 ? align[a] : NSTextAlignmentNatural;
        _lineBreak = (NSLineBreakMode)((f >> 9) & 7);
        _controlSize = (NSControlSize)((f >> 17) & 3);
    }
    /* A cell wraps when its line break mode is a wrapping one, as Apple
     * documents wraps and lineBreakMode going together; the 0x40 bit of the
     * first word is "truncates the last visible line" (freemac 1.260, which
     * had taken it for wrapping until Rectangle's labels showed otherwise).
     * A scrolling field never wraps. */
    if ([coder containsValueForKey:@"NSCellFlags2"]) {
        BOOL wrapping = _lineBreak == NSLineBreakByWordWrapping || _lineBreak == NSLineBreakByCharWrapping;
        if (_scrollable && wrapping)
            _lineBreak = NSLineBreakByClipping;
        _wraps = wrapping && !_scrollable;
    } else if (!_wraps && _lineBreak == NSLineBreakByWordWrapping)
        _lineBreak = _scrollable ? NSLineBreakByClipping : NSLineBreakByTruncatingTail;
    if ([coder containsValueForKey:@"NSState"])
        _state = [coder decodeIntegerForKey:@"NSState"];
    if ([coder containsValueForKey:@"NSEnabled"])
        _enabled = [coder decodeBoolForKey:@"NSEnabled"];
    if ([coder containsValueForKey:@"NSTag"])
        _tag = [coder decodeIntegerForKey:@"NSTag"];
    if ([coder containsValueForKey:@"NSControlSize"])
        _controlSize = [coder decodeIntegerForKey:@"NSControlSize"];
    if ([coder containsValueForKey:@"NSControlLineBreakMode"])
        _lineBreak = [coder decodeIntegerForKey:@"NSControlLineBreakMode"];
    NSString *action = coder_value(coder, @"NSAction");
    if ([action isKindOfClass:[NSString class]])
        _action = NSSelectorFromString(action);
    _target = coder_value(coder, @"NSTarget");
    NSFormatter *formatter = coder_value(coder, @"NSFormatter");
    if ([formatter isKindOfClass:[NSFormatter class]])
        _formatter = [formatter retain];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_value forKey:@"NSContents"];
    if (_font)
        [coder encodeObject:_font forKey:@"NSSupport"];
    unsigned f = (_state == NSControlStateValueOn ? CELL_STATE : 0) | (_enabled ? 0 : CELL_DISABLED) |
                 (_editable ? CELL_EDITABLE : 0) | (_bordered ? CELL_BORDERED : 0) | (_bezeled ? CELL_BEZELED : 0) |
                 (_selectable ? CELL_SELECTABLE : 0) | (_scrollable ? CELL_SCROLLABLE : 0) |
                 (_continuous ? CELL_CONTINUOUS : 0) | (_wraps ? CELL_WRAPS : 0);
    static const unsigned old_order[] = {0, 2, 1, 3, 4}; /* left, centre, right, justified, natural */
    unsigned f2 = old_order[_alignment < 5 ? _alignment : 4] << 26 | ((unsigned)_lineBreak & 7) << 9 |
                  ((unsigned)_controlSize & 3) << 17;
    [coder encodeInt64:f forKey:@"NSCellFlags"];
    [coder encodeInt64:f2 forKey:@"NSCellFlags2"];
    if (_tag)
        [coder encodeInteger:_tag forKey:@"NSTag"];
}

- (id)objectValue { return _value; }
- (void)setObjectValue:(id)value
{
    id old = _value;
    _value = [value isKindOfClass:[NSImage class]] ? [value retain] : [value copy]; /* images are shared */
    [old release];
}
/* With a formatter, the value is shown as the formatter writes it; a string
 * given to the cell is read by the formatter, and kept as it is if the
 * formatter can't read it. */
- (NSString *)stringValue
{
    if (_formatter && _value && ![_value isKindOfClass:[NSString class]]) {
        NSString *s = [_formatter stringForObjectValue:_value];
        if (s)
            return s;
    }
    if ([_value isKindOfClass:[NSAttributedString class]])
        return [_value string];
    if ([_value isKindOfClass:[NSString class]])
        return _value;
    return _value ? [_value description] : @"";
}
- (void)setStringValue:(NSString *)s
{
    id obj = nil;
    if (_formatter && s && [_formatter getObjectValue:&obj forString:s errorDescription:NULL]) {
        [self setObjectValue:obj];
        return;
    }
    [self setObjectValue:s ?: @""];
}
- (NSFormatter *)formatter { return _formatter; }
- (void)setFormatter:(NSFormatter *)f
{
    [f retain];
    [_formatter release];
    _formatter = f;
}
- (NSString *)title { return [self stringValue]; }
- (void)setTitle:(NSString *)t { [self setStringValue:t]; }
- (NSAttributedString *)attributedStringValue
{
    if ([_value isKindOfClass:[NSAttributedString class]])
        return _value;
    return [[[NSAttributedString alloc] initWithString:[self stringValue]] autorelease];
}
- (void)setAttributedStringValue:(NSAttributedString *)s { [self setObjectValue:s]; }
- (int)intValue { return [_value isKindOfClass:[NSNumber class]] ? [_value intValue] : [[self stringValue] intValue]; }
- (NSInteger)integerValue
{
    return [_value isKindOfClass:[NSNumber class]] ? [_value integerValue] : [[self stringValue] integerValue];
}
- (double)doubleValue
{
    return [_value isKindOfClass:[NSNumber class]] ? [_value doubleValue] : [[self stringValue] doubleValue];
}
- (NSFont *)font { return _font; }
- (void)setFont:(NSFont *)font
{
    [font retain];
    [_font release];
    _font = font;
}
- (NSTextAlignment)alignment { return _alignment; }
- (void)setAlignment:(NSTextAlignment)a { _alignment = a; }
- (NSLineBreakMode)lineBreakMode { return _lineBreak; }
- (void)setLineBreakMode:(NSLineBreakMode)m { _lineBreak = m; }
- (BOOL)wraps { return _wraps; }
- (void)setWraps:(BOOL)f { _wraps = f; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)f
{
    _enabled = f;
    cell_changed(self, _controlView);
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
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)f { _bordered = f; }
- (BOOL)isBezeled { return _bezeled; }
- (void)setBezeled:(BOOL)f { _bezeled = f; }
- (BOOL)isScrollable { return _scrollable; }
- (void)setScrollable:(BOOL)f { _scrollable = f; }
- (BOOL)isHighlighted { return _highlighted; }
- (void)setHighlighted:(BOOL)f { _highlighted = f; }
- (BOOL)isContinuous { return _continuous; }
- (void)setContinuous:(BOOL)f { _continuous = f; }
- (NSControlStateValue)state { return _state; }
- (void)setState:(NSControlStateValue)s
{
    _state = s;
    cell_changed(self, _controlView);
}
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (NSControlSize)controlSize { return _controlSize; }
- (void)setControlSize:(NSControlSize)s { _controlSize = s; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (NSImage *)image { return [_value isKindOfClass:[NSImage class]] ? _value : nil; }
- (void)setImage:(NSImage *)image { [self setObjectValue:image]; }
- (NSView *)controlView { return _controlView; }
- (void)setControlView:(NSView *)v { _controlView = v; }
- (BOOL)showsFirstResponder { return _showsFirstResponder; }
- (void)setShowsFirstResponder:(BOOL)flag { _showsFirstResponder = flag; }
/* A click with no mouse: a cell that keeps a state takes its next one,
 * then the action goes to the target, from the control the cell is in. */
- (void)performClick:(id)sender
{
    if (!_enabled)
        return;
    /* a control's own cell: the control holds the state, target and action */
    if ([_controlView isKindOfClass:[NSControl class]] && [(NSControl *)_controlView cell] == self) {
        [(NSControl *)_controlView performClick:sender];
        return;
    }
    if ([self isKindOfClass:[NSButtonCell class]])
        [self setNextState];
    if (_action)
        [NSApp sendAction:_action to:_target from:_controlView ?: (id)self];
}

/* the cell's contextual menu (freemac 1.221, Ferry 0.45.0) */
- (NSMenu *)menu { return _menu; }
- (void)setMenu:(NSMenu *)m
{
    [m retain];
    [_menu release];
    _menu = m;
}
- (NSMenu *)menuForEvent:(NSEvent *)event inRect:(NSRect)rect ofView:(NSView *)view { return _menu; }

/* ---- more of the cell's settings (freemac 1.226, Ferry 0.50.0) ----
 * The object a cell stands for (tab bar cells and menu-like cells keep
 * theirs here), the setters for numbers, and switches that are kept for
 * the program: Ferry's controls decide editing, focus rings and undo
 * themselves. */
- (id)representedObject { return _represented; }
- (void)setRepresentedObject:(id)object
{
    [object retain];
    [_represented release];
    _represented = object;
}
- (float)floatValue { return (float)[self doubleValue]; }
- (void)setIntValue:(int)v { [self setObjectValue:@(v)]; }
- (void)setIntegerValue:(NSInteger)v { [self setObjectValue:@(v)]; }
- (void)setFloatValue:(float)v { [self setObjectValue:@(v)]; }
- (void)setDoubleValue:(double)v { [self setObjectValue:@(v)]; }
- (void)takeIntValueFrom:(id)sender { [self setIntValue:[sender intValue]]; }
- (void)takeIntegerValueFrom:(id)sender { [self setIntegerValue:[sender integerValue]]; }
- (void)takeFloatValueFrom:(id)sender { [self setFloatValue:[sender floatValue]]; }
- (void)takeDoubleValueFrom:(id)sender { [self setDoubleValue:[sender doubleValue]]; }
- (void)takeStringValueFrom:(id)sender { [self setStringValue:[sender stringValue]]; }
- (void)takeObjectValueFrom:(id)sender { [self setObjectValue:[sender objectValue]]; }
- (BOOL)hasValidObjectValue { return YES; }
- (NSCellType)type
{
    if ([_value isKindOfClass:[NSImage class]])
        return NSImageCellType;
    return _value ? NSTextCellType : NSNullCellType;
}
- (void)setType:(NSCellType)type
{
    if (type == NSTextCellType && ![_value isKindOfClass:[NSString class]])
        [self setStringValue:@""];
}
- (BOOL)sendsActionOnEndEditing { return _sendsOnEndEditing; }
- (void)setSendsActionOnEndEditing:(BOOL)f { _sendsOnEndEditing = f; }
- (NSInteger)sendActionOn:(NSInteger)mask
{
    NSInteger old = _sendMask;
    _sendMask = mask;
    return old;
}
- (BOOL)allowsMixedState { return _allowsMixed; }
- (void)setAllowsMixedState:(BOOL)f { _allowsMixed = f; }
- (NSInteger)nextState
{
    NSInteger s = [self state];
    if (s == NSControlStateValueOff)
        return NSControlStateValueOn;
    if (s == NSControlStateValueOn && [self allowsMixedState])
        return NSControlStateValueMixed;
    return NSControlStateValueOff;
}
- (void)setNextState { [self setState:[self nextState]]; }
- (BOOL)refusesFirstResponder { return _refusesFirstResponder; }
- (void)setRefusesFirstResponder:(BOOL)f { _refusesFirstResponder = f; }
- (BOOL)acceptsFirstResponder { return _enabled && !_refusesFirstResponder; }
- (BOOL)allowsUndo { return _allowsUndo; }
- (void)setAllowsUndo:(BOOL)f { _allowsUndo = f; }
- (BOOL)usesSingleLineMode { return _singleLine; }
- (void)setUsesSingleLineMode:(BOOL)f { _singleLine = f; }
- (NSFocusRingType)focusRingType { return _focusRing; }
- (void)setFocusRingType:(NSFocusRingType)t { _focusRing = t; }
- (NSWritingDirection)baseWritingDirection { return _writingDirection; }
- (void)setBaseWritingDirection:(NSWritingDirection)d { _writingDirection = d; }
- (NSString *)keyEquivalent { return @""; }
- (BOOL)isOpaque { return NO; }
- (NSComparisonResult)compare:(id)other
{
    return [[self stringValue] compare:[other stringValue]];
}
/* the cell lights up as a press is tracked, and its view is drawn again */
- (void)highlight:(BOOL)flag withFrame:(NSRect)frame inView:(NSView *)view
{
    [self setHighlighted:flag];
    [view setNeedsDisplayInRect:frame];
}
- (NSText *)setUpFieldEditorAttributes:(NSText *)editor { return editor; }
/* What a click at the event's point would do, as Apple documents the
 * default: an editable or selectable text cell's text, an enabled button
 * cell's tracking, and anything inside the cell is content. */
- (NSCellHitResult)hitTestForEvent:(NSEvent *)event inRect:(NSRect)rect ofView:(NSView *)view
{
    NSPoint p = [view convertPoint:[event locationInWindow] fromView:nil];
    if (!NSMouseInRect(p, rect, [view isFlipped]))
        return NSCellHitNone;
    NSCellHitResult r = NSCellHitContentArea;
    if (_enabled && (_editable || _selectable) && ![_value isKindOfClass:[NSImage class]])
        r |= NSCellHitEditableTextArea;
    if (_enabled && [self isKindOfClass:[NSButtonCell class]])
        r |= NSCellHitTrackableArea;
    return r;
}
@end

@implementation NSActionCell
@end

/* ---- NSButtonCell ------------------------------------------------------------------- */

@implementation NSButtonCell {
    NSString *_alternate, *_key;
    NSEventModifierFlags _keyMask;
    NSBezelStyle _bezel;
    NSButtonType _type;
    BOOL _typeKnown, _transparent, _mixed, _imageOnly;
    id _image, _alternateImage;
    NSCellStyleMask _highlightsBy, _showsStateBy;
    NSCellImagePosition _imagePosition;
    NSAttributedString *_attributedTitle;
}
- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super initTextCell:string])) {
        _alternate = @"";
        _key = @"";
        _bezel = NSBezelStyleRounded;
        _bordered = YES;
        _alignment = NSTextAlignmentCenter;
        _highlightsBy = NSPushInCellMask | NSChangeGrayCellMask;
    }
    return self;
}
- (void)dealloc
{
    [_image release];
    [_alternateImage release];
    [_alternate release];
    [_key release];
    [_attributedTitle release];
    [super dealloc];
}

/* "NSButtonFlags2" holds the bezel style (low three bits, plus 0x20 for the
 * styles past 7) and the key equivalent's modifiers (from bit 8). The kind
 * of button is "NSAuxButtonType" when present; older nibs only say so
 * through the alternate image, NSSwitch for check boxes and NSRadioButton
 * for radio buttons. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    if ([coder containsValueForKey:@"NSCellFlags2"] && ![coder containsValueForKey:@"NSAlignment"]) {
        /* Buttons are centred unless the nib says otherwise; the flags'
         * zero means natural/left for text cells. */
        unsigned f2 = (unsigned)[coder decodeInt64ForKey:@"NSCellFlags2"];
        if (((f2 >> 26) & 7) == 0)
            _alignment = NSTextAlignmentCenter;
    } else if (![coder containsValueForKey:@"NSCellFlags2"]) {
        _alignment = NSTextAlignmentCenter;
    }
    NSString *alt = coder_value(coder, @"NSAlternateContents");
    if ([alt isKindOfClass:[NSString class]])
        [self setAlternateTitle:alt];
    NSString *key = coder_value(coder, @"NSKeyEquivalent");
    if ([key isKindOfClass:[NSString class]])
        [self setKeyEquivalent:key];
    if ([coder containsValueForKey:@"NSButtonFlags"]) {
        unsigned f = (unsigned)[coder decodeInt64ForKey:@"NSButtonFlags"];
        _bordered = (f & 0x00800000u) != 0;
        _transparent = (f & 0x00008000u) != 0;
    }
    if ([coder containsValueForKey:@"NSButtonFlags2"]) {
        unsigned f2 = (unsigned)[coder decodeInt64ForKey:@"NSButtonFlags2"];
        _bezel = (NSBezelStyle)((f2 & 7) | ((f2 & 0x20) >> 2));
        _keyMask = (NSEventModifierFlags)(f2 >> 8);
    }
    if ([coder containsValueForKey:@"NSBezelStyle"])
        _bezel = [coder decodeIntegerForKey:@"NSBezelStyle"];
    if ([coder containsValueForKey:@"NSAuxButtonType"]) {
        _type = [coder decodeIntegerForKey:@"NSAuxButtonType"];
        _typeKnown = YES;
    } else {
        id image = coder_value(coder, @"NSAlternateImage") ?: coder_value(coder, @"NSNormalImage");
        NSString *name = [image respondsToSelector:@selector(_imageName)] ? [image _imageName] : nil;
        if ([name isEqualToString:@"NSSwitch"]) {
            _type = NSButtonTypeSwitch;
            _typeKnown = YES;
        } else if ([name isEqualToString:@"NSRadioButton"]) {
            _type = NSButtonTypeRadio;
            _typeKnown = YES;
        }
    }
    if (_typeKnown)
        [self _setMasksForType:_type];
    if ([coder containsValueForKey:@"NSAllowsMixedState"])
        _mixed = [coder decodeBoolForKey:@"NSAllowsMixedState"];
    _image = [coder_value(coder, @"NSNormalImage") retain];
    _alternateImage = [coder_value(coder, @"NSAlternateImage") retain];
    return self;
}
/* The button's own image, not its title (the cell's value) */
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image
{
    [(id)image retain];
    [_image release];
    _image = image;
}
- (NSImage *)alternateImage { return _alternateImage; }
- (void)setAlternateImage:(NSImage *)image
{
    [(id)image retain];
    [_alternateImage release];
    _alternateImage = image;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_alternate forKey:@"NSAlternateContents"];
    [coder encodeObject:_key forKey:@"NSKeyEquivalent"];
    [coder encodeInt64:(_bordered ? 0x00800000u : 0) | (_transparent ? 0x00008000u : 0) forKey:@"NSButtonFlags"];
    [coder encodeInt64:(int64_t)(((unsigned)_bezel & 7) | (((unsigned)_bezel & 8) << 2) | (unsigned)(_keyMask << 8))
                forKey:@"NSButtonFlags2"];
    if (_typeKnown)
        [coder encodeInteger:_type forKey:@"NSAuxButtonType"];
}
- (NSString *)alternateTitle { return _alternate; }
- (void)setAlternateTitle:(NSString *)t
{
    [_alternate release];
    _alternate = [t copy] ?: @"";
}
- (NSString *)keyEquivalent { return _key; }
- (void)setKeyEquivalent:(NSString *)k
{
    [_key release];
    _key = [k copy] ?: @"";
}
- (NSEventModifierFlags)keyEquivalentModifierMask { return _keyMask; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _keyMask = m; }
- (NSBezelStyle)bezelStyle { return _bezel; }
- (void)setBezelStyle:(NSBezelStyle)b { _bezel = b; }
- (void)setButtonType:(NSButtonType)t
{
    _type = t;
    _typeKnown = YES;
    [self _setMasksForType:t];
}
/* The highlight and state masks each kind of button has, as Apple's
 * documentation of setButtonType: lists them (freemac 1.221, Ferry 0.45.0). */
- (void)_setMasksForType:(NSButtonType)t
{
    NSCellStyleMask h = NSPushInCellMask | NSChangeGrayCellMask, shows = NSNoCellMask;
    switch (t) {
    case NSButtonTypeMomentaryLight: h = NSChangeBackgroundCellMask; break;
    case NSButtonTypePushOnPushOff: shows = NSChangeBackgroundCellMask; break;
    case NSButtonTypeToggle: h = NSPushInCellMask | NSContentsCellMask, shows = NSContentsCellMask; break;
    case NSButtonTypeSwitch:
    case NSButtonTypeRadio: h = shows = NSContentsCellMask; break;
    case NSButtonTypeMomentaryChange: h = NSContentsCellMask; break;
    case NSButtonTypeOnOff: h = shows = NSChangeBackgroundCellMask; break;
    default: break;
    }
    _highlightsBy = h;
    _showsStateBy = shows;
}
- (NSCellStyleMask)highlightsBy { return _highlightsBy; }
- (void)setHighlightsBy:(NSCellStyleMask)m { _highlightsBy = m; }
- (NSCellStyleMask)showsStateBy { return _showsStateBy; }
- (void)setShowsStateBy:(NSCellStyleMask)m { _showsStateBy = m; }
- (NSCellImagePosition)imagePosition { return _imagePosition; }
- (void)setImagePosition:(NSCellImagePosition)p { _imagePosition = p; }
/* the title in the cell's font, or the attributed title it was given while
 * the title is still that one's text */
- (NSAttributedString *)attributedTitle
{
    NSString *title = [self title] ?: @"";
    if (_attributedTitle && [[_attributedTitle string] isEqualToString:title])
        return _attributedTitle;
    NSDictionary *attrs = [self font] ? @{NSFontAttributeName : [self font]} : @{};
    return [[[NSAttributedString alloc] initWithString:title attributes:attrs] autorelease];
}
- (void)setAttributedTitle:(NSAttributedString *)t
{
    [_attributedTitle release];
    _attributedTitle = [t copy];
    [self setTitle:[t string] ?: @""];
}
- (BOOL)_hasButtonType { return _typeKnown; }
- (NSButtonType)_buttonType { return _type; }
- (BOOL)isTransparent { return _transparent; }
- (void)setTransparent:(BOOL)f { _transparent = f; }
- (BOOL)allowsMixedState { return _mixed; }
- (void)setAllowsMixedState:(BOOL)f { _mixed = f; }
/* A cell on its own keeps its state as NSButton does: switches, radio
 * buttons and toggles change it when clicked. */
- (void)setNextState
{
    NSButtonType t = _type;
    if (t != NSButtonTypeSwitch && t != NSButtonTypeRadio && t != NSButtonTypeToggle &&
        t != NSButtonTypePushOnPushOff && t != NSButtonTypeOnOff)
        return;
    NSControlStateValue s = [self state];
    if (t == NSButtonTypeRadio)
        s = NSControlStateValueOn;
    else if (s == NSControlStateValueOff)
        s = NSControlStateValueOn;
    else if (s == NSControlStateValueOn && _mixed)
        s = NSControlStateValueMixed;
    else
        s = s == NSControlStateValueMixed ? NSControlStateValueOn : NSControlStateValueOff;
    [self setState:s];
}
@end

/* ---- NSTextFieldCell ------------------------------------------------------------------ */

@implementation NSTextFieldCell {
    id _placeholder;
    BOOL _drawsBackground;
    NSColor *_background, *_textColor;
}
- (void)dealloc
{
    [_placeholder release];
    [_background release];
    [_textColor release];
    [super dealloc];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    id p = coder_value(coder, @"NSPlaceholderString");
    if ([p isKindOfClass:[NSString class]] || [p isKindOfClass:[NSAttributedString class]])
        _placeholder = [p copy];
    _drawsBackground = [coder decodeBoolForKey:@"NSDrawsBackground"];
    NSColor *bg = coder_value(coder, @"NSBackgroundColor"), *fg = coder_value(coder, @"NSTextColor");
    if ([bg isKindOfClass:[NSColor class]])
        _background = [bg retain];
    if ([fg isKindOfClass:[NSColor class]])
        _textColor = [fg retain];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    if (_placeholder)
        [coder encodeObject:_placeholder forKey:@"NSPlaceholderString"];
    [coder encodeBool:_drawsBackground forKey:@"NSDrawsBackground"];
    if (_background)
        [coder encodeObject:_background forKey:@"NSBackgroundColor"];
    if (_textColor)
        [coder encodeObject:_textColor forKey:@"NSTextColor"];
}
- (NSString *)placeholderString
{
    return [_placeholder isKindOfClass:[NSAttributedString class]] ? [_placeholder string] : _placeholder;
}
- (void)setPlaceholderString:(NSString *)s
{
    [_placeholder release];
    _placeholder = [s copy];
}
- (NSAttributedString *)placeholderAttributedString
{
    return [_placeholder isKindOfClass:[NSAttributedString class]] ? _placeholder : nil;
}
- (void)setPlaceholderAttributedString:(NSAttributedString *)s
{
    [_placeholder release];
    _placeholder = [s copy];
}
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f { _drawsBackground = f; }
- (NSColor *)backgroundColor { return _background; }
- (void)setBackgroundColor:(NSColor *)c
{
    [c retain];
    [_background release];
    _background = c;
}
- (NSColor *)textColor { return _textColor; }
- (void)setTextColor:(NSColor *)c
{
    [c retain];
    [_textColor release];
    _textColor = c;
}
@end

@implementation NSSecureTextFieldCell
@end
