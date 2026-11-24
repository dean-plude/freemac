/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSControl, NSButton and NSTextField. Ferry draws its own
 * simple controls with Core Graphics (rounded push buttons, check boxes,
 * radio buttons, labels and editable text fields), in a plain light style
 * of its own. Controls keep their state themselves rather than in NSCell
 * objects; a text field edits its own text, without a separate field
 * editor. A text field being edited in a table's cell (NSTableView.m)
 * hands Return, Tab, Shift-Tab and Escape to its table, which moves the
 * editing on; the end-of-editing notification says how editing ended,
 * under "NSTextMovement", as Apple documents. */
#import "AInternal.h"

NSNotificationName const NSControlTextDidBeginEditingNotification = @"NSControlTextDidBeginEditingNotification";
NSNotificationName const NSControlTextDidChangeNotification = @"NSControlTextDidChangeNotification";
NSNotificationName const NSControlTextDidEndEditingNotification = @"NSControlTextDidEndEditingNotification";
NSString *const NSTextMovementUserInfoKey = @"NSTextMovement";

static NSColor *accent(void) { return [NSColor controlAccentColor]; }
static BOOL is_low_surrogate(unichar c) { return c >= 0xDC00 && c <= 0xDFFF; }

/* A line of text: its width, and where each character starts. */
static CTLineRef make_line(NSString *s, NSFont *font, NSColor *color)
{
    return CTLineCreateWithAttributedString((CFAttributedStringRef)AAttributed(s, font, color));
}

/* ---- NSControl -------------------------------------------------------------------- */

@implementation NSControl {
@protected
    id _target;
    SEL _action;
    NSInteger _tag;
    BOOL _enabled, _continuous, _highlighted;
    id _value;
    NSFont *_font;
    NSTextAlignment _alignment;
    NSLineBreakMode _lineBreak;
    NSControlSize _controlSize;
    NSCell *_cell;
}

/* Defaults for a new control; subclasses add theirs. Used both by
 * initWithFrame: and when a control is loaded from a nib. */
- (void)_setDefaults
{
    _enabled = YES;
    _value = @"";
    _alignment = NSTextAlignmentNatural;
    _lineBreak = NSLineBreakByClipping;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setDefaults];
    return self;
}

/* From a nib: the view's keys, then the settings kept in the cell. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    [self _setDefaults];
    NSCell *cell = [coder decodeObjectForKey:@"NSCell"];
    if ([cell isKindOfClass:[NSCell class]]) {
        _cell = [cell retain];
        [cell setControlView:self];
        [self _takeFromCell:cell];
    }
    if ([coder containsValueForKey:@"NSEnabled"])
        _enabled = [coder decodeBoolForKey:@"NSEnabled"];
    if ([coder containsValueForKey:@"NSTag"])
        _tag = [coder decodeIntegerForKey:@"NSTag"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeBool:_enabled forKey:@"NSEnabled"];
    if (_cell)
        [coder encodeObject:_cell forKey:@"NSCell"];
}
- (void)_takeFromCell:(NSCell *)cell
{
    _enabled = [cell isEnabled];
    _tag = [cell tag];
    _continuous = [cell isContinuous];
    _controlSize = [cell controlSize];
    if ([cell font])
        [self setFont:[cell font]];
    _alignment = [cell alignment];
    if ([cell target])
        _target = [cell target];
    if ([cell action])
        _action = [cell action];
}

+ (Class)cellClass { return [NSActionCell class]; }
+ (void)setCellClass:(Class)cls {}
- (NSCell *)cell { return _cell; }
- (void)setCell:(NSCell *)cell
{
    [cell retain];
    [_cell release];
    _cell = cell;
    [cell setControlView:self];
}

- (void)dealloc
{
    [_value release];
    [_font release];
    [_cell release];
    [super dealloc];
}

- (id)target { return _target; }
- (void)setTarget:(id)target { _target = target; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)action { _action = action; }
/* Which mouse events send the action. A Ferry control sends it on mouse-up
 * whatever the mask, so that is what it says it did before. */
- (NSInteger)sendActionOn:(NSInteger)mask { return 1 << 2; /* NSEventMaskLeftMouseUp */ }
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)tag { _tag = tag; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)flag
{
    _enabled = flag;
    [self setNeedsDisplay:YES];
}
- (BOOL)isContinuous { return _continuous; }
- (void)setContinuous:(BOOL)flag { _continuous = flag; }
- (BOOL)isHighlighted { return _highlighted; }
- (void)setHighlighted:(BOOL)flag
{
    _highlighted = flag;
    [self setNeedsDisplay:YES];
}
- (NSFont *)font { return _font ?: [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:_controlSize]]; }
- (void)setFont:(NSFont *)font
{
    [font retain];
    [_font release];
    _font = font;
    [self setNeedsDisplay:YES];
}
- (NSTextAlignment)alignment { return _alignment; }
- (void)setAlignment:(NSTextAlignment)a
{
    _alignment = a;
    [self setNeedsDisplay:YES];
}
- (NSLineBreakMode)lineBreakMode { return _lineBreak; }
- (void)setLineBreakMode:(NSLineBreakMode)m
{
    _lineBreak = m;
    [self setNeedsDisplay:YES];
}
- (NSControlSize)controlSize { return _controlSize; }
- (void)setControlSize:(NSControlSize)s
{
    _controlSize = s;
    [self setNeedsDisplay:YES];
}

- (id)objectValue { return _value; }
- (void)setObjectValue:(id)value
{
    id v = [value copy];
    [_value release];
    _value = v;
    [self setNeedsDisplay:YES];
}
- (NSString *)stringValue
{
    if ([_value isKindOfClass:[NSString class]])
        return _value;
    if ([_value isKindOfClass:[NSAttributedString class]])
        return [_value string];
    if ([_value isKindOfClass:[NSNumber class]])
        return [_value stringValue];
    return _value ? [_value description] : @"";
}
- (void)setStringValue:(NSString *)s { [self setObjectValue:s ?: @""]; }
- (NSAttributedString *)attributedStringValue
{
    if ([_value isKindOfClass:[NSAttributedString class]])
        return _value;
    return AAttributed([self stringValue], [self font], nil);
}
- (void)setAttributedStringValue:(NSAttributedString *)s { [self setObjectValue:s]; }
- (int)intValue { return [_value isKindOfClass:[NSNumber class]] ? [_value intValue] : [[self stringValue] intValue]; }
- (void)setIntValue:(int)v { [self setObjectValue:@(v)]; }
- (NSInteger)integerValue
{
    return [_value isKindOfClass:[NSNumber class]] ? [_value integerValue] : [[self stringValue] integerValue];
}
- (void)setIntegerValue:(NSInteger)v { [self setObjectValue:@(v)]; }
- (float)floatValue { return (float)[self doubleValue]; }
- (void)setFloatValue:(float)v { [self setObjectValue:@(v)]; }
- (double)doubleValue
{
    return [_value isKindOfClass:[NSNumber class]] ? [_value doubleValue] : [[self stringValue] doubleValue];
}
- (void)setDoubleValue:(double)v { [self setObjectValue:@(v)]; }
- (void)takeStringValueFrom:(id)sender { [self setStringValue:[sender stringValue]]; }
- (void)takeIntValueFrom:(id)sender { [self setIntValue:[sender intValue]]; }
- (void)takeDoubleValueFrom:(id)sender { [self setDoubleValue:[sender doubleValue]]; }

/* Editing, for the controls that edit text (NSTextField and NSTableView). */
- (BOOL)abortEditing { return NO; }
- (void)validateEditing {}

- (BOOL)sendAction:(SEL)action to:(id)target
{
    if (!action)
        return NO;
    return [[NSApplication sharedApplication] sendAction:action to:target from:self];
}

- (void)performClick:(id)sender
{
    if (!_enabled)
        return;
    [self sendAction:_action to:_target];
}

- (NSSize)intrinsicContentSize { return NSMakeSize(-1, -1); }
- (void)sizeToFit
{
    NSSize s = [self intrinsicContentSize];
    if (s.width >= 0 && s.height >= 0)
        [self setFrameSize:s];
}
@end

/* ---- NSButton ------------------------------------------------------------------------ */

@implementation NSButton {
    NSString *_title, *_alternateTitle, *_key;
    NSAttributedString *_attributedTitle;
    NSButtonType _type;
    NSBezelStyle _bezel;
    NSControlStateValue _state;
    BOOL _mixed, _bordered, _transparent, _tracking, _inside;
    NSEventModifierFlags _keyMask;
    NSColor *_tint, *_bezelColor;
    id _image, _alternateImage;
    NSCellImagePosition _imagePosition;
    NSImageScaling _imageScaling;
    BOOL _imagePositionSet;
}

/* An image a button can draw: nibs also hold stand-ins for the system's
 * check box and radio button images, which aren't drawn as images. */
static NSImage *drawable(id image) { return [image isKindOfClass:[NSImage class]] ? image : nil; }

+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
    NSButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 80, 32)] autorelease];
    [b setTitle:title];
    [b setTarget:target];
    [b setAction:action];
    [b sizeToFit];
    return b;
}
+ (instancetype)buttonWithImage:(NSImage *)image target:(id)target action:(SEL)action
{
    NSButton *b = [self buttonWithTitle:@"" target:target action:action];
    [b setImage:image];
    [b setImagePosition:NSImageOnly];
    [b sizeToFit];
    return b;
}
+ (instancetype)buttonWithTitle:(NSString *)title image:(NSImage *)image target:(id)target action:(SEL)action
{
    NSButton *b = [self buttonWithTitle:title target:target action:action];
    [b setImage:image];
    [b setImagePosition:NSImageLeading];
    [b sizeToFit];
    return b;
}
+ (instancetype)checkboxWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
    NSButton *b = [self buttonWithTitle:title target:target action:action];
    [b setButtonType:NSButtonTypeSwitch];
    [b sizeToFit];
    return b;
}
+ (instancetype)radioButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
    NSButton *b = [self buttonWithTitle:title target:target action:action];
    [b setButtonType:NSButtonTypeRadio];
    [b sizeToFit];
    return b;
}

- (void)_setDefaults
{
    [super _setDefaults];
    _title = @"Button";
    _alternateTitle = @"";
    _key = @"";
    _type = NSButtonTypeMomentaryPushIn;
    _bezel = NSBezelStyleRounded;
    _bordered = YES;
    _alignment = NSTextAlignmentCenter;
}

+ (Class)cellClass { return [NSButtonCell class]; }

- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
    [self setTitle:[cell title]];
    if ([cell isKindOfClass:[NSButtonCell class]]) {
        NSButtonCell *b = (NSButtonCell *)cell;
        [self setAlternateTitle:[b alternateTitle]];
        [self setKeyEquivalent:[b keyEquivalent]];
        _keyMask = [b keyEquivalentModifierMask];
        _bezel = [b bezelStyle];
        _bordered = [b isBordered];
        _transparent = [b isTransparent];
        _mixed = [b allowsMixedState];
        if ([b _hasButtonType])
            [self setButtonType:[b _buttonType]];
        if (drawable([b image]))
            [self setImage:[b image]];
        if (drawable([b alternateImage]))
            [self setAlternateImage:[b alternateImage]];
    }
    _state = [cell state];
}

- (void)dealloc
{
    [_title release];
    [_alternateTitle release];
    [_key release];
    [_attributedTitle release];
    [_tint release];
    [_bezelColor release];
    [_image release];
    [_alternateImage release];
    [super dealloc];
}

- (NSString *)title { return _attributedTitle ? [_attributedTitle string] : _title; }
- (void)setTitle:(NSString *)t
{
    [_title release];
    _title = [t ?: @"" copy];
    [_attributedTitle release];
    _attributedTitle = nil;
    [self setNeedsDisplay:YES];
}
- (NSString *)alternateTitle { return _alternateTitle; }
- (void)setAlternateTitle:(NSString *)t
{
    [_alternateTitle release];
    _alternateTitle = [t ?: @"" copy];
}
- (NSAttributedString *)attributedTitle { return _attributedTitle ?: AAttributed(_title, [self font], nil); }
- (void)setAttributedTitle:(NSAttributedString *)t
{
    [_attributedTitle release];
    _attributedTitle = [t copy];
    [self setNeedsDisplay:YES];
}
- (NSBezelStyle)bezelStyle { return _bezel; }
- (void)setBezelStyle:(NSBezelStyle)b
{
    _bezel = b;
    [self setNeedsDisplay:YES];
}
- (BOOL)allowsMixedState { return _mixed; }
- (void)setAllowsMixedState:(BOOL)f { _mixed = f; }
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)f
{
    _bordered = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)isTransparent { return _transparent; }
- (void)setTransparent:(BOOL)f
{
    _transparent = f;
    [self setNeedsDisplay:YES];
}
- (NSString *)keyEquivalent { return _key; }
- (void)setKeyEquivalent:(NSString *)k
{
    [_key release];
    _key = [k ?: @"" copy];
    [self setNeedsDisplay:YES];
}
- (NSEventModifierFlags)keyEquivalentModifierMask { return _keyMask; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _keyMask = m; }
- (NSColor *)contentTintColor { return _tint; }
- (void)setContentTintColor:(NSColor *)c
{
    [_tint release];
    _tint = [c retain];
}
- (NSColor *)bezelColor { return _bezelColor; }
- (void)setBezelColor:(NSColor *)c
{
    [_bezelColor release];
    _bezelColor = [c retain];
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image
{
    [(id)image retain];
    [_image release];
    _image = image;
    [self setNeedsDisplay:YES];
}
- (NSImage *)alternateImage { return _alternateImage; }
- (void)setAlternateImage:(NSImage *)image
{
    [(id)image retain];
    [_alternateImage release];
    _alternateImage = image;
    [self setNeedsDisplay:YES];
}
/* Unless set, a button with an image and no title shows only the image,
 * and one with both shows the image before the title. */
- (NSCellImagePosition)imagePosition
{
    if (_imagePositionSet)
        return _imagePosition;
    if (!drawable(_image))
        return NSNoImage;
    return [[self title] length] ? NSImageLeft : NSImageOnly;
}
- (void)setImagePosition:(NSCellImagePosition)p
{
    _imagePosition = p;
    _imagePositionSet = YES;
    [self setNeedsDisplay:YES];
}
- (NSImageScaling)imageScaling { return _imageScaling; }
- (void)setImageScaling:(NSImageScaling)s
{
    _imageScaling = s;
    [self setNeedsDisplay:YES];
}
- (BOOL)imageHugsTitle { return YES; }
- (void)setImageHugsTitle:(BOOL)f {}
- (void)setButtonType:(NSButtonType)type
{
    _type = type;
    if (type == NSButtonTypeSwitch || type == NSButtonTypeRadio)
        _alignment = NSTextAlignmentLeft;
    [self setNeedsDisplay:YES];
}

- (NSControlStateValue)state { return _state; }
- (void)setState:(NSControlStateValue)s
{
    if (s == NSControlStateValueMixed && !_mixed)
        s = NSControlStateValueOn;
    _state = s;
    [self setNeedsDisplay:YES];
}
- (id)objectValue { return @(_state); }
- (void)setObjectValue:(id)v { [self setState:[v integerValue]]; }
- (NSString *)stringValue { return [NSString stringWithFormat:@"%ld", (long)_state]; }
- (void)setStringValue:(NSString *)s { [self setState:[s integerValue]]; }
- (int)intValue { return (int)_state; }
- (void)setIntValue:(int)v { [self setState:v]; }
- (NSInteger)integerValue { return _state; }
- (void)setIntegerValue:(NSInteger)v { [self setState:v]; }
- (double)doubleValue { return _state; }
- (void)setDoubleValue:(double)v { [self setState:(NSInteger)v]; }

static BOOL keeps_state(NSButtonType t)
{
    return t == NSButtonTypeSwitch || t == NSButtonTypeRadio || t == NSButtonTypeToggle ||
           t == NSButtonTypePushOnPushOff || t == NSButtonTypeOnOff;
}

- (void)setNextState
{
    if (!keeps_state(_type))
        return;
    if (_type == NSButtonTypeRadio) {
        [self setState:NSControlStateValueOn];
        return;
    }
    if (_state == NSControlStateValueOff)
        [self setState:NSControlStateValueOn];
    else if (_state == NSControlStateValueOn && _mixed)
        [self setState:NSControlStateValueMixed];
    else
        [self setState:_state == NSControlStateValueMixed ? NSControlStateValueOn : NSControlStateValueOff];
}

/* Radio buttons with the same superview and action are a group: turning
 * one on turns the others off. */
- (void)_turnOffSiblings
{
    if (_type != NSButtonTypeRadio)
        return;
    for (NSView *v in [[self superview] subviews])
        if (v != self && [v isKindOfClass:[NSButton class]]) {
            NSButton *b = (NSButton *)v;
            if (b->_type == NSButtonTypeRadio && b->_action == _action)
                [b setState:NSControlStateValueOff];
        }
}

- (void)highlight:(BOOL)flag { [self setHighlighted:flag]; }

- (void)performClick:(id)sender
{
    if (!_enabled)
        return;
    [self setNextState];
    [self _turnOffSiblings];
    [self sendAction:_action to:_target];
}

- (void)mouseDown:(NSEvent *)event
{
    if (!_enabled)
        return;
    _tracking = _inside = YES;
    [self highlight:YES];
}
- (void)mouseDragged:(NSEvent *)event
{
    if (!_tracking)
        return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    _inside = [self mouse:p inRect:[self bounds]];
    if (_inside != _highlighted)
        [self highlight:_inside];
}
- (void)mouseUp:(NSEvent *)event
{
    if (!_tracking)
        return;
    _tracking = NO;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    BOOL inside = [self mouse:p inRect:[self bounds]];
    [self highlight:NO];
    if (inside)
        [self performClick:self];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)keyDown:(NSEvent *)event
{
    if ([[event characters] isEqualToString:@" "] && _enabled)
        [self performClick:self];
    else
        [super keyDown:event];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (!_enabled || ![_key length] || [self isHiddenOrHasHiddenAncestor])
        return NO;
    NSEventModifierFlags relevant = NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                    NSEventModifierFlagControl | NSEventModifierFlagShift;
    if (([event modifierFlags] & relevant) != (_keyMask & relevant))
        return NO;
    NSString *typed = [event charactersIgnoringModifiers];
    BOOL same = [typed isEqualToString:_key] ||
                ([_key isEqualToString:@"\r"] && [typed isEqualToString:@"\x03"]);
    if (!same)
        return NO;
    [self highlight:YES];
    [self highlight:NO];
    [self performClick:self];
    return YES;
}

- (NSSize)intrinsicContentSize
{
    NSSize t = ALineSize([self attributedTitle], NULL, NULL);
    if (_type == NSButtonTypeSwitch || _type == NSButtonTypeRadio)
        return NSMakeSize(ceil(t.width) + 22, 18);
    NSCellImagePosition pos = [self imagePosition];
    NSSize im = pos != NSNoImage ? [drawable(_image) size] : NSZeroSize;
    if (pos == NSImageOnly || pos == NSImageOverlaps || ![[self title] length])
        t = im.width > 0 ? im : t;
    else if (pos == NSImageAbove || pos == NSImageBelow)
        t = NSMakeSize(fmax(t.width, im.width), t.height + im.height + 2);
    else if (im.width > 0)
        t = NSMakeSize(t.width + im.width + 4, fmax(t.height, im.height));
    if (!_bordered)
        return NSMakeSize(ceil(t.width) + 4, ceil(t.height) + 2);
    if (pos == NSImageOnly)
        return NSMakeSize(fmax(ceil(t.width) + 16, 32), fmax(32, ceil(t.height) + 10));
    return NSMakeSize(fmax(ceil(t.width) + 28, 60), fmax(32, ceil(t.height) + 10));
}

/* ---- drawing ---------------------------------------------------------------------- */

- (BOOL)_isDefault { return [_key isEqualToString:@"\r"] && _bordered; }

/* The image (scaled down to fit if need be) and the title, placed as the
 * image position says. */
- (void)_drawContentIn:(NSRect)rect color:(NSColor *)color
{
    NSImage *image = drawable(_state == NSControlStateValueOn && drawable(_alternateImage) ? _alternateImage : _image);
    NSCellImagePosition pos = image ? [self imagePosition] : NSNoImage;
    if (pos == NSNoImage) {
        [self _drawTitleIn:rect color:color];
        return;
    }
    NSSize s = [image size];
    BOOL titled = [[self title] length] && pos != NSImageOnly;
    CGFloat maxW = rect.size.width, maxH = rect.size.height;
    if (s.width > maxW || s.height > maxH || _imageScaling == NSImageScaleProportionallyUpOrDown) {
        CGFloat k = fmin(maxW / s.width, maxH / s.height);
        if (_imageScaling != NSImageScaleProportionallyUpOrDown)
            k = fmin(k, 1);
        s = NSMakeSize(s.width * k, s.height * k);
    }
    NSSize t = titled ? ALineSize([self attributedTitle], NULL, NULL) : NSZeroSize;
    NSRect img = NSMakeRect(NSMidX(rect) - s.width / 2, NSMidY(rect) - s.height / 2, s.width, s.height);
    NSRect text = rect;
    if (titled && pos != NSImageOverlaps) {
        BOOL flipped = [self isFlipped];
        if (pos == NSImageAbove || pos == NSImageBelow) {
            CGFloat total = s.height + 2 + t.height, top = NSMidY(rect) + total / 2;
            BOOL imageTop = (pos == NSImageAbove) != flipped;
            img.origin.y = imageTop ? top - s.height : top - total;
            text.origin.y = imageTop ? top - total : top - t.height;
            text.size.height = t.height;
        } else {
            BOOL imageFirst = pos != NSImageRight && pos != NSImageTrailing;
            CGFloat total = s.width + 4 + ceil(t.width);
            CGFloat x0 = _alignment == NSTextAlignmentLeft ? rect.origin.x : NSMidX(rect) - total / 2;
            img.origin.x = imageFirst ? x0 : x0 + total - s.width;
            text.origin.x = imageFirst ? x0 + s.width + 4 : x0;
            text.size.width = ceil(t.width) + 1;
        }
    }
    img = NSMakeRect(round(img.origin.x), round(img.origin.y), s.width, s.height);
    [image _drawInControlRect:img color:_tint ?: color fraction:_enabled ? 1 : 0.5];
    if (titled) {
        NSTextAlignment saved = _alignment;
        if (pos != NSImageOverlaps && pos != NSImageAbove && pos != NSImageBelow)
            _alignment = NSTextAlignmentLeft;
        [self _drawTitleIn:text color:color];
        _alignment = saved;
    }
}

- (void)_drawTitleIn:(NSRect)rect color:(NSColor *)color
{
    NSAttributedString *t = [self attributedTitle];
    if (!_attributedTitle)
        t = AAttributed(_title, [self font], color);
    CGFloat a, d;
    NSSize s = ALineSize(t, &a, &d);
    CGFloat x = rect.origin.x;
    if (_alignment == NSTextAlignmentCenter)
        x = NSMidX(rect) - s.width / 2;
    else if (_alignment == NSTextAlignmentRight)
        x = NSMaxX(rect) - s.width;
    CGFloat baseline = floor(NSMidY(rect) - (a + d) / 2 + d);
    if ([self isFlipped])
        baseline = ceil(NSMidY(rect) + (a + d) / 2 - d);
    ADrawLine(t, round(x), baseline);
}

- (void)drawRect:(NSRect)dirty
{
    if (_transparent)
        return;
    NSRect b = [self bounds];
    BOOL focused = [[self window] firstResponder] == self && [[self window] isKeyWindow];
    CGFloat dim = _enabled ? 1 : 0.45;
    NSColor *text = [[NSColor controlTextColor] colorWithAlphaComponent:0.88 * dim];

    if (_type == NSButtonTypeSwitch || _type == NSButtonTypeRadio) {
        CGFloat size = 14;
        NSRect box = NSMakeRect(b.origin.x + 1, floor(NSMidY(b) - size / 2), size, size);
        BOOL on = _state != NSControlStateValueOff;
        NSColor *fill = on ? (_highlighted ? [accent() shadowWithLevel:0.2] : accent())
                           : (_highlighted ? [NSColor colorWithWhite:0.88 alpha:1] : [NSColor whiteColor]);
        fill = [fill colorWithAlphaComponent:dim];
        NSColor *edge = on ? nil : [NSColor colorWithWhite:0 alpha:0.3 * dim];
        CGFloat radius = _type == NSButtonTypeRadio ? size / 2 : 3.5;
        AFillRoundedRect(box, radius, fill, edge);
        if (on) {
            [[NSColor colorWithWhite:1 alpha:dim] set];
            if (_type == NSButtonTypeRadio) {
                [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 4.5, 4.5)] fill];
            } else if (_state == NSControlStateValueMixed) {
                NSRectFill(NSMakeRect(box.origin.x + 3.5, NSMidY(box) - 1, size - 7, 2));
            } else {
                NSBezierPath *tick = [NSBezierPath bezierPath];
                BOOL f = [self isFlipped];
                CGFloat y0 = box.origin.y, h = size;
                #define Y(v) (f ? y0 + h - (v) : y0 + (v))
                [tick moveToPoint:NSMakePoint(box.origin.x + 3.5, Y(7.2))];
                [tick lineToPoint:NSMakePoint(box.origin.x + 6, Y(4.5))];
                [tick lineToPoint:NSMakePoint(box.origin.x + 10.5, Y(10))];
                #undef Y
                [tick setLineWidth:2];
                [tick setLineCapStyle:NSLineCapStyleRound];
                [tick setLineJoinStyle:NSLineJoinStyleRound];
                [tick stroke];
            }
        }
        if (focused)
            AFillRoundedRect(NSInsetRect(box, -2, -2), radius + 2, nil, [NSColor keyboardFocusIndicatorColor]);
        [self _drawTitleIn:NSMakeRect(NSMaxX(box) + 6, b.origin.y, NSMaxX(b) - NSMaxX(box) - 6, b.size.height)
                     color:text];
        return;
    }

    if (!_bordered) {
        [self _drawContentIn:b color:_highlighted ? [text shadowWithLevel:0.4] : text];
        return;
    }

    /* a rounded push button, drawn in the middle of a taller frame as a Mac
     * does for the classic 32-point button frame */
    CGFloat h = fmin(b.size.height - 4, 22), inset = b.size.height >= 28 ? 6 : 2;
    if (drawable(_image) && [drawable(_image) size].height > 16)   /* a tall image gets a tall bezel */
        h = fmax(h, fmin(b.size.height - 4, [drawable(_image) size].height + 8));
    NSRect bezel = NSMakeRect(b.origin.x + inset, floor(NSMidY(b) - h / 2), b.size.width - 2 * inset, h);
    BOOL pressedOn = keeps_state(_type) && _state == NSControlStateValueOn;
    NSColor *fill, *edge;
    if ([self _isDefault] || pressedOn) {
        fill = _highlighted ? [accent() shadowWithLevel:0.2] : accent();
        edge = nil;
        text = [NSColor colorWithWhite:1 alpha:dim];
    } else {
        fill = _highlighted ? [NSColor colorWithWhite:0.85 alpha:1] : [NSColor whiteColor];
        edge = [NSColor colorWithWhite:0 alpha:0.22];
    }
    if (_bezelColor && !_highlighted)
        fill = _bezelColor;
    AFillRoundedRect(bezel, 5, [fill colorWithAlphaComponent:[fill alphaComponent] * dim], edge);
    if (focused)
        AFillRoundedRect(NSInsetRect(bezel, -2.5, -2.5), 7.5, nil, [NSColor keyboardFocusIndicatorColor]);
    [self _drawContentIn:NSInsetRect(bezel, [self imagePosition] == NSImageOnly ? 4 : 8, 1) color:text];
}
@end

/* ---- NSTextField --------------------------------------------------------------------- */

@implementation NSTextField {
    NSString *_placeholder;
    NSAttributedString *_placeholderAttributed;
    BOOL _editable, _selectable, _bezeled, _bordered, _drawsBackground, _singleLine;
    NSTextFieldBezelStyle _bezelStyle;
    NSColor *_background, *_textColor;
    id _delegate;
    NSInteger _maxLines;
    CGFloat _preferredWidth;
    /* editing */
    BOOL _editing, _began;
    NSInteger _movement;            /* how the editing is ending: an NSTextMovement */
    NSMutableString *_text;
    NSUInteger _caret, _anchor;     /* the selection runs between them */
    CGFloat _scroll;                /* how far the text is scrolled left */
}

+ (instancetype)labelWithString:(NSString *)string
{
    NSTextField *f = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    [f setStringValue:string];
    [f setEditable:NO];
    [f setSelectable:NO];
    [f setBezeled:NO];
    [f setDrawsBackground:NO];
    [f setTextColor:[NSColor labelColor]];
    [f sizeToFit];
    return f;
}
+ (instancetype)wrappingLabelWithString:(NSString *)string
{
    NSTextField *f = [self labelWithString:string];
    [f setLineBreakMode:NSLineBreakByWordWrapping];
    f->_maxLines = 0;
    return f;
}
+ (instancetype)labelWithAttributedString:(NSAttributedString *)string
{
    NSTextField *f = [self labelWithString:@""];
    [f setAttributedStringValue:string];
    [f sizeToFit];
    return f;
}
+ (instancetype)textFieldWithString:(NSString *)string
{
    NSTextField *f = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    [f setStringValue:string];
    [f sizeToFit];
    [f setFrameSize:NSMakeSize(fmax([f frame].size.width, 96), [f frame].size.height)];
    return f;
}

- (void)_setDefaults
{
    [super _setDefaults];
    _editable = _selectable = _bezeled = _drawsBackground = YES;
    _maxLines = 1;
}

+ (Class)cellClass { return [NSTextFieldCell class]; }

- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
    [self setObjectValue:[cell objectValue] ?: @""];
    _editable = [cell isEditable];
    _selectable = [cell isSelectable];
    _bezeled = [cell isBezeled];
    _bordered = [cell isBordered];
    _lineBreak = [cell lineBreakMode];
    if ([cell wraps] && !_editable && _lineBreak == NSLineBreakByWordWrapping)
        _maxLines = 0;
    if ([cell isKindOfClass:[NSTextFieldCell class]]) {
        NSTextFieldCell *t = (NSTextFieldCell *)cell;
        if ([t placeholderAttributedString])
            [self setPlaceholderAttributedString:[t placeholderAttributedString]];
        else
            [self setPlaceholderString:[t placeholderString]];
        _drawsBackground = [t drawsBackground];
        if ([t backgroundColor])
            [self setBackgroundColor:[t backgroundColor]];
        if ([t textColor])
            [self setTextColor:[t textColor]];
    }
}

- (void)dealloc
{
    [_placeholder release];
    [_placeholderAttributed release];
    [_background release];
    [_textColor release];
    [_text release];
    [super dealloc];
}

- (NSString *)placeholderString { return _placeholder; }
- (void)setPlaceholderString:(NSString *)s
{
    [_placeholder release];
    _placeholder = [s copy];
    [self setNeedsDisplay:YES];
}
- (NSAttributedString *)placeholderAttributedString { return _placeholderAttributed; }
- (void)setPlaceholderAttributedString:(NSAttributedString *)s
{
    [_placeholderAttributed release];
    _placeholderAttributed = [s copy];
    [self setNeedsDisplay:YES];
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
- (BOOL)isBezeled { return _bezeled; }
- (void)setBezeled:(BOOL)f
{
    _bezeled = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)f
{
    _bordered = f;
    [self setNeedsDisplay:YES];
}
- (NSTextFieldBezelStyle)bezelStyle { return _bezelStyle; }
- (void)setBezelStyle:(NSTextFieldBezelStyle)s { _bezelStyle = s; }
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
    _background = [c retain];
    [self setNeedsDisplay:YES];
}
- (NSColor *)textColor { return _textColor ?: [NSColor textColor]; }
- (void)setTextColor:(NSColor *)c
{
    [_textColor release];
    _textColor = [c retain];
    [self setNeedsDisplay:YES];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSInteger)maximumNumberOfLines { return _maxLines; }
- (void)setMaximumNumberOfLines:(NSInteger)n { _maxLines = n; }
- (CGFloat)preferredMaxLayoutWidth { return _preferredWidth; }
- (void)setPreferredMaxLayoutWidth:(CGFloat)w { _preferredWidth = w; }
- (BOOL)usesSingleLineMode { return _singleLine; }
- (void)setUsesSingleLineMode:(BOOL)f { _singleLine = f; }

- (NSString *)stringValue { return _editing ? [[_text copy] autorelease] : [super stringValue]; }
- (void)setObjectValue:(id)value
{
    [super setObjectValue:value];
    if (_editing) {
        [_text setString:[super stringValue]];
        _caret = _anchor = [_text length];
    }
}

/* What is shown: bullets in a secure field. */
- (NSString *)_shown:(NSString *)s
{
    if (![self isKindOfClass:[NSSecureTextField class]])
        return s;
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < [s length]; i++)
        [m appendString:@"•"];
    return m;
}

- (NSSize)intrinsicContentSize
{
    NSAttributedString *s = AAttributed([self _shown:[self stringValue]], [self font], nil);
    NSSize t;
    if (_lineBreak == NSLineBreakByWordWrapping && _maxLines != 1) {
        CGFloat w = _preferredWidth > 0 ? _preferredWidth : ([self frame].size.width > 0 ? [self frame].size.width - 4 : 1e6);
        t = [s boundingRectWithSize:NSMakeSize(w, 0) options:NSStringDrawingUsesLineFragmentOrigin].size;
    } else {
        t = ALineSize(s, NULL, NULL);
    }
    if (_bezeled || _bordered)
        return NSMakeSize(ceil(t.width) + 8, fmax(ceil(t.height) + 6, 22));
    return NSMakeSize(ceil(t.width) + 4, ceil(t.height));
}

/* ---- editing ------------------------------------------------------------------------- */

- (BOOL)acceptsFirstResponder { return _editable || _selectable; }

- (BOOL)becomeFirstResponder
{
    _editing = YES;
    _began = NO;
    [_text release];
    _text = [[super stringValue] mutableCopy];
    _anchor = 0;
    _caret = [_text length];     /* everything selected, as on a Mac */
    _scroll = 0;
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)_post:(NSNotificationName)name selector:(SEL)sel
{
    NSDictionary *info = [name isEqualToString:NSControlTextDidEndEditingNotification]
                             ? @{NSTextMovementUserInfoKey : @(_movement)}
                             : nil;
    NSNotification *n = [NSNotification notificationWithName:name object:self userInfo:info];
    if ([_delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

/* The table whose cell this field is being edited in, if any. */
- (NSTableView *)_editingTable
{
    for (NSView *v = [self superview]; v; v = [v superview])
        if ([v isKindOfClass:[NSTableView class]])
            return [(NSTableView *)v _isEditingField:self] ? (NSTableView *)v : nil;
    return nil;
}
- (NSInteger)_textMovement { return _movement; }
- (void)_setTextMovement:(NSInteger)m { _movement = m; }
/* Puts back the value editing started with (Escape in a table's cell). */
- (void)_discardEditsTo:(id)value
{
    if (!_editing)
        return;
    [super setObjectValue:value];
    [_text setString:[super stringValue]];
    _caret = _anchor = [_text length];
    [self setNeedsDisplay:YES];
}
- (void)_placeCaretAtEnd
{
    if (_editing)
        _caret = _anchor = [_text length];
    [self setNeedsDisplay:YES];
}

- (BOOL)resignFirstResponder
{
    NSTableView *table = [[[self _editingTable] retain] autorelease];
    if (_editing) {
        /* the delegate may keep the editing going, unless it is cancelled */
        if (_began && _movement != NSTextMovementCancel &&
            [_delegate respondsToSelector:@selector(control:textShouldEndEditing:)] &&
            ![_delegate control:self textShouldEndEditing:nil]) {
            _movement = NSTextMovementOther;
            return NO;
        }
        [[self retain] autorelease];
        NSString *s = [[_text copy] autorelease];
        _editing = NO;
        [super setObjectValue:s];
        /* in a table, the field's action is sent when editing ends with a
         * change, or by Return, so that its target can find the row with
         * rowForView: */
        if (table && _action && _movement != NSTextMovementCancel && (_began || _movement == NSTextMovementReturn))
            [self sendAction:_action to:_target];
        if (_began)
            [self _post:NSControlTextDidEndEditingNotification selector:@selector(controlTextDidEndEditing:)];
        _began = NO;
        [_text release];
        _text = nil;
    }
    _movement = NSTextMovementOther;
    if (table)
        [table _editingFieldDidResign:self];
    [self setNeedsDisplay:YES];
    return YES;
}

/* Ends the editing and gives up what was typed. */
- (BOOL)abortEditing
{
    if (!_editing)
        return NO;
    NSTableView *table = [self _editingTable];
    if (table)
        return [table abortEditing];
    _began = NO;
    [_text setString:[super stringValue]];
    _movement = NSTextMovementCancel;
    if ([[self window] firstResponder] == self)
        [[self window] makeFirstResponder:nil];
    else
        [self resignFirstResponder];
    return YES;
}
/* What has been typed becomes the field's value; the editing goes on. */
- (void)validateEditing
{
    if (_editing)
        [super setObjectValue:[[_text copy] autorelease]];
}

- (void)selectText:(id)sender
{
    if ([[self window] firstResponder] != self)
        [[self window] makeFirstResponder:self];
    _anchor = 0;
    _caret = [_text length];
    [self setNeedsDisplay:YES];
}

- (NSRange)_selection
{
    NSUInteger a = MIN(_caret, _anchor), b = MAX(_caret, _anchor);
    return NSMakeRange(a, b - a);
}

- (void)_changed
{
    if (!_began) {
        _began = YES;
        [self _post:NSControlTextDidBeginEditingNotification selector:@selector(controlTextDidBeginEditing:)];
    }
    [self _post:NSControlTextDidChangeNotification selector:@selector(controlTextDidChange:)];
    if (_continuous)
        [self sendAction:_action to:_target];
    [self setNeedsDisplay:YES];
}

- (void)_replaceSelectionWith:(NSString *)s
{
    if (!_editable) {
        NSBeep();
        return;
    }
    /* the first change asks the delegate whether editing may begin */
    if (!_began && [_delegate respondsToSelector:@selector(control:textShouldBeginEditing:)] &&
        ![_delegate control:self textShouldBeginEditing:nil]) {
        NSBeep();
        return;
    }
    NSRange r = [self _selection];
    [_text replaceCharactersInRange:r withString:s];
    _caret = _anchor = r.location + [s length];
    [self _changed];
}

- (void)keyDown:(NSEvent *)event
{
    if (_editing)
        [self interpretKeyEvents:@[ event ]];
    else
        [super keyDown:event];
}

- (void)insertText:(id)string
{
    NSString *s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    if (_maxLines == 1)
        s = [[s componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "];
    [self _replaceSelectionWith:s];
}

- (void)doCommandBySelector:(SEL)sel
{
    if ([_delegate respondsToSelector:@selector(control:textView:doCommandBySelector:)] &&
        [_delegate control:self textView:nil doCommandBySelector:sel])
        return;
    [super doCommandBySelector:sel];
}

/* The previous or next character boundary, keeping surrogate pairs whole. */
- (NSUInteger)_step:(NSUInteger)i forward:(BOOL)forward
{
    NSUInteger n = [_text length];
    if (forward) {
        if (i >= n)
            return n;
        i++;
        if (i < n && is_low_surrogate([_text characterAtIndex:i]))
            i++;
        return i;
    }
    if (i == 0)
        return 0;
    i--;
    if (i > 0 && is_low_surrogate([_text characterAtIndex:i]))
        i--;
    return i;
}

- (NSUInteger)_word:(NSUInteger)i forward:(BOOL)forward
{
    NSUInteger n = [_text length];
    NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
    if (forward) {
        while (i < n && ![letters characterIsMember:[_text characterAtIndex:i]])
            i++;
        while (i < n && [letters characterIsMember:[_text characterAtIndex:i]])
            i++;
    } else {
        while (i > 0 && ![letters characterIsMember:[_text characterAtIndex:i - 1]])
            i--;
        while (i > 0 && [letters characterIsMember:[_text characterAtIndex:i - 1]])
            i--;
    }
    return i;
}

- (void)_moveTo:(NSUInteger)i select:(BOOL)select
{
    _caret = i;
    if (!select)
        _anchor = i;
    [self setNeedsDisplay:YES];
}

- (void)_deleteTo:(NSUInteger)i
{
    if ([self _selection].length == 0) {
        _anchor = i;
        if (_anchor == _caret)
            return;
    }
    [self _replaceSelectionWith:@""];
}

- (void)deleteBackward:(id)sender { [self _deleteTo:[self _step:_caret forward:NO]]; }
- (void)deleteForward:(id)sender { [self _deleteTo:[self _step:_caret forward:YES]]; }
- (void)deleteWordBackward:(id)sender { [self _deleteTo:[self _word:_caret forward:NO]]; }
- (void)deleteWordForward:(id)sender { [self _deleteTo:[self _word:_caret forward:YES]]; }
- (void)deleteToBeginningOfLine:(id)sender { [self _deleteTo:0]; }
- (void)deleteToEndOfLine:(id)sender { [self _deleteTo:[_text length]]; }
- (void)deleteToEndOfParagraph:(id)sender { [self _deleteTo:[_text length]]; }

/* The clipboard: the general pasteboard, which is this system's clipboard. */
- (void)copy:(id)sender
{
    NSRange r = [self _selection];
    if (!_editing || !r.length || [self isKindOfClass:[NSSecureTextField class]]) {
        NSBeep();
        return;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[_text substringWithRange:r] forType:NSPasteboardTypeString];
}
- (void)cut:(id)sender
{
    if (!_editable || ![self _selection].length || [self isKindOfClass:[NSSecureTextField class]]) {
        NSBeep();
        return;
    }
    [self copy:sender];
    [self _replaceSelectionWith:@""];
}
- (void)paste:(id)sender
{
    NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (!s || !_editing) {
        NSBeep();
        return;
    }
    [self insertText:s];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL a = [item action];
    if (a == @selector(copy:))
        return _editing && [self _selection].length && ![self isKindOfClass:[NSSecureTextField class]];
    if (a == @selector(cut:))
        return _editing && _editable && [self _selection].length && ![self isKindOfClass:[NSSecureTextField class]];
    if (a == @selector(paste:))
        return _editing && _editable &&
               [[NSPasteboard generalPasteboard] availableTypeFromArray:@[ NSPasteboardTypeString ]] != nil;
    if (a == @selector(selectAll:))
        return _editing;
    return YES;
}
- (void)moveLeft:(id)sender
{
    NSRange r = [self _selection];
    [self _moveTo:r.length ? r.location : [self _step:_caret forward:NO] select:NO];
}
- (void)moveRight:(id)sender
{
    NSRange r = [self _selection];
    [self _moveTo:r.length ? NSMaxRange(r) : [self _step:_caret forward:YES] select:NO];
}
- (void)moveBackward:(id)sender { [self moveLeft:sender]; }
- (void)moveForward:(id)sender { [self moveRight:sender]; }
- (void)moveLeftAndModifySelection:(id)sender { [self _moveTo:[self _step:_caret forward:NO] select:YES]; }
- (void)moveRightAndModifySelection:(id)sender { [self _moveTo:[self _step:_caret forward:YES] select:YES]; }
- (void)moveWordLeft:(id)sender { [self _moveTo:[self _word:_caret forward:NO] select:NO]; }
- (void)moveWordRight:(id)sender { [self _moveTo:[self _word:_caret forward:YES] select:NO]; }
- (void)moveWordLeftAndModifySelection:(id)sender { [self _moveTo:[self _word:_caret forward:NO] select:YES]; }
- (void)moveWordRightAndModifySelection:(id)sender { [self _moveTo:[self _word:_caret forward:YES] select:YES]; }
- (void)moveToBeginningOfLine:(id)sender { [self _moveTo:0 select:NO]; }
- (void)moveToEndOfLine:(id)sender { [self _moveTo:[_text length] select:NO]; }
- (void)moveToBeginningOfLineAndModifySelection:(id)sender { [self _moveTo:0 select:YES]; }
- (void)moveToEndOfLineAndModifySelection:(id)sender { [self _moveTo:[_text length] select:YES]; }
- (void)moveToBeginningOfParagraph:(id)sender { [self moveToBeginningOfLine:sender]; }
- (void)moveToEndOfParagraph:(id)sender { [self moveToEndOfLine:sender]; }
- (void)moveToBeginningOfDocument:(id)sender { [self moveToBeginningOfLine:sender]; }
- (void)moveToEndOfDocument:(id)sender { [self moveToEndOfLine:sender]; }
- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender { [self moveToBeginningOfLineAndModifySelection:sender]; }
- (void)moveToEndOfDocumentAndModifySelection:(id)sender { [self moveToEndOfLineAndModifySelection:sender]; }
- (void)moveUp:(id)sender { [self moveToBeginningOfLine:sender]; }
- (void)moveDown:(id)sender { [self moveToEndOfLine:sender]; }
- (void)moveUpAndModifySelection:(id)sender { [self moveToBeginningOfLineAndModifySelection:sender]; }
- (void)moveDownAndModifySelection:(id)sender { [self moveToEndOfLineAndModifySelection:sender]; }
- (void)selectAll:(id)sender
{
    if (!_editing)
        return;
    _anchor = 0;
    _caret = [_text length];
    [self setNeedsDisplay:YES];
}
- (void)noop:(id)sender {}

/* Return sends the action; then, as in a Mac dialog, the window's default
 * button gets the key too. */
- (void)insertNewline:(id)sender
{
    NSTableView *table = [self _editingTable];
    if (table) {
        [table _endEditingWithMovement:NSTextMovementReturn];
        return;
    }
    if (_maxLines != 1 && !_singleLine) {
        [self _replaceSelectionWith:@"\n"];
        return;
    }
    [_text retain];
    [super setObjectValue:[[_text copy] autorelease]];
    [_text release];
    [self sendAction:_action to:_target];
    NSEvent *e = [[self window] currentEvent];
    if (e && [e type] == NSEventTypeKeyDown)
        [[self window] performKeyEquivalent:e];
    _anchor = 0;
    _caret = [_text length];
    [self setNeedsDisplay:YES];
}
- (void)insertNewlineIgnoringFieldEditor:(id)sender { [self _replaceSelectionWith:@"\n"]; }
- (void)insertTab:(id)sender
{
    NSTableView *table = [self _editingTable];
    if (table) {
        [table _endEditingWithMovement:NSTextMovementTab];
        return;
    }
    _movement = NSTextMovementTab;
    [[self window] selectKeyViewFollowingView:self];
    _movement = NSTextMovementOther;
}
- (void)insertBacktab:(id)sender
{
    NSTableView *table = [self _editingTable];
    if (table) {
        [table _endEditingWithMovement:NSTextMovementBacktab];
        return;
    }
    _movement = NSTextMovementBacktab;
    [[self window] selectKeyViewPrecedingView:self];
    _movement = NSTextMovementOther;
}
- (void)insertTabIgnoringFieldEditor:(id)sender { [self _replaceSelectionWith:@"\t"]; }
- (void)cancelOperation:(id)sender
{
    NSTableView *table = [self _editingTable];
    if (table) {
        [table _endEditingWithMovement:NSTextMovementCancel];
        return;
    }
    NSEvent *e = [[self window] currentEvent];
    if (e && [e type] == NSEventTypeKeyDown)
        [[self window] performKeyEquivalent:e];
}

/* ---- layout and drawing -------------------------------------------------------------- */

- (NSRect)_textRect
{
    NSRect b = [self bounds];
    if (_bezeled || _bordered)
        return NSInsetRect(b, 4, 2);
    return NSInsetRect(b, 2, 0);
}

- (CGFloat)_baseline
{
    NSRect r = [self _textRect];
    NSFont *f = [self font];
    CGFloat a = [f ascender], d = -[f descender];
    if (_bezeled || _bordered || !(_lineBreak == NSLineBreakByWordWrapping && _maxLines != 1)) {
        CGFloat y = floor(NSMidY(r) - (a + d) / 2 + d);
        return [self isFlipped] ? ceil(NSMidY(r) + (a + d) / 2 - d) : y;
    }
    return [self isFlipped] ? r.origin.y + a : NSMaxY(r) - a;
}

/* Where character i of the shown text starts, in view coordinates. */
- (CGFloat)_xOfIndex:(NSUInteger)i line:(CTLineRef)line
{
    return [self _textRect].origin.x - _scroll + CTLineGetOffsetForStringIndex(line, (CFIndex)i, NULL);
}

- (NSUInteger)_indexAtX:(CGFloat)x
{
    NSString *s = [self _shown:_editing ? _text : [self stringValue]];
    CTLineRef line = make_line(s, [self font], nil);
    CFIndex i = CTLineGetStringIndexForPosition(line, CGPointMake(x - [self _textRect].origin.x + _scroll, 0));
    CFRelease(line);
    if (i < 0)
        i = 0;
    if ((NSUInteger)i > [s length])
        i = (CFIndex)[s length];
    return (NSUInteger)i;
}

- (void)mouseDown:(NSEvent *)event
{
    if (!_selectable) {
        [super mouseDown:event];
        return;
    }
    if (!_editing)
        return;   /* the click made us first responder, which selected everything */
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if ([event clickCount] >= 2) {
        [self selectAll:nil];
        return;
    }
    NSUInteger i = [self _indexAtX:p.x];
    [self _moveTo:i select:([event modifierFlags] & NSEventModifierFlagShift) != 0];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!_editing)
        return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    [self _moveTo:[self _indexAtX:p.x] select:YES];
}

/* The steps of drawing a text field that a search field (NSSearchField.m)
 * does its own way: the bezel, where the text is clipped, the placeholder. */
- (BOOL)_isEditing { return _editing; }
- (void)_drawBezelInRect:(NSRect)b focused:(BOOL)focused
{
    if (_drawsBackground) {
        [[self backgroundColor] setFill];
        NSRectFill(b);
    }
    [[NSColor colorWithWhite:0 alpha:_bezeled ? 0.25 : 0.5] setFill];
    NSFrameRect(b);
    if (focused) {
        [[NSColor keyboardFocusIndicatorColor] setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithRect:NSInsetRect(b, 1, 1)];
        [ring setLineWidth:2];
        [ring stroke];
    }
}
- (NSRect)_clipRect { return NSInsetRect([self bounds], 1, 1); }
- (NSAttributedString *)_shownPlaceholder
{
    if (_placeholderAttributed)
        return _placeholderAttributed;
    return _placeholder ? AAttributed(_placeholder, [self font], [NSColor placeholderTextColor]) : nil;
}

- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    BOOL focused = _editing && [[self window] isKeyWindow];
    if (_bezeled || _bordered) {
        [self _drawBezelInRect:b focused:focused];
    } else if (_drawsBackground) {
        [[self backgroundColor] setFill];
        NSRectFill(b);
    }

    NSRect tr = [self _textRect];
    NSFont *font = [self font];
    NSColor *color = _enabled ? [self textColor] : [NSColor disabledControlTextColor];
    /* on a selected table row (its cell's background is emphasized) the
     * usual label colours turn white, as on a Mac */
    if (_enabled && !_editing && [_cell backgroundStyle] == NSBackgroundStyleEmphasized) {
        NSColor *c = [self textColor];
        if ([c isEqual:[NSColor labelColor]] || [c isEqual:[NSColor textColor]] || [c isEqual:[NSColor controlTextColor]])
            color = [NSColor whiteColor];
        else if ([c isEqual:[NSColor secondaryLabelColor]] || [c isEqual:[NSColor tertiaryLabelColor]])
            color = [NSColor colorWithWhite:1 alpha:0.8];
    }

    if (!_editing && _lineBreak == NSLineBreakByWordWrapping && _maxLines != 1) {
        NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
        [style setAlignment:_alignment];
        NSAttributedString *s = [[[NSAttributedString alloc]
            initWithString:[self stringValue]
                attributes:@{NSFontAttributeName : font, NSForegroundColorAttributeName : color,
                             NSParagraphStyleAttributeName : style}] autorelease];
        [s drawInRect:tr];
        return;
    }

    NSString *text = _editing ? _text : [self stringValue];
    NSString *shown = [self _shown:text];
    CGFloat baseline = [self _baseline];
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, [self _clipRect]);

    if (![shown length]) {
        NSAttributedString *ph = [self _shownPlaceholder];
        if (ph)
            ADrawLine(ph, tr.origin.x, baseline);
    }

    CTLineRef line = make_line(shown, font, color);
    double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CGFloat x = tr.origin.x;
    if (_editing) {
        /* keep the caret in view */
        CGFloat cx = CTLineGetOffsetForStringIndex(line, (CFIndex)_caret, NULL);
        if (cx - _scroll > tr.size.width - 2)
            _scroll = cx - tr.size.width + 2;
        if (cx - _scroll < 0)
            _scroll = cx;
        x -= _scroll;
    } else if (width < tr.size.width) {
        if (_alignment == NSTextAlignmentRight)
            x = NSMaxX(tr) - width;
        else if (_alignment == NSTextAlignmentCenter)
            x = NSMidX(tr) - width / 2;
    }
    CGFloat a = [font ascender], d = -[font descender];
    CGFloat top = [self isFlipped] ? baseline - a : baseline + a;
    CGFloat lineBottom = [self isFlipped] ? baseline + d : baseline - d;
    if (_editing) {
        NSRange sel = [self _selection];
        if (sel.length) {
            CGFloat x0 = x + CTLineGetOffsetForStringIndex(line, (CFIndex)sel.location, NULL);
            CGFloat x1 = x + CTLineGetOffsetForStringIndex(line, (CFIndex)NSMaxRange(sel), NULL);
            [(focused ? [NSColor selectedTextBackgroundColor] : [NSColor colorWithWhite:0.86 alpha:1]) setFill];
            NSRectFill(NSMakeRect(x0, fmin(top, lineBottom), x1 - x0, fabs(top - lineBottom)));
        }
    }
    if ([shown length])
        ADrawLine(AAttributed(shown, font, color), round(x * 2) / 2, baseline);
    if (_editing && focused && [self _selection].length == 0) {
        CGFloat cx = round(x + CTLineGetOffsetForStringIndex(line, (CFIndex)_caret, NULL)) + 0.5;
        [[NSColor textColor] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(cx, fmin(top, lineBottom))
                                  toPoint:NSMakePoint(cx, fmax(top, lineBottom))];
    }
    CFRelease(line);
    CGContextRestoreGState(cg);
}
@end

@implementation NSSecureTextField
@end
