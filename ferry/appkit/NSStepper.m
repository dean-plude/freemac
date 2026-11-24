/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: steppers (NSStepper, NSStepperCell), written from Apple's
 * public API documentation. Ferry draws a stepper its own way: a small
 * white rounded box split across the middle, an arrow up above and an
 * arrow down below, the half being pressed shaded.
 *
 * The value runs from minValue to maxValue (0 and 59 unless set, as Apple
 * documents) and moves by increment (1). Pressing the top half adds the
 * increment, the bottom half takes it away; past either end the value wraps
 * round to the other end when valueWraps is on (the default) and stops
 * there otherwise. With autorepeat (also the default) holding the arrow
 * steps again after a short delay and then quickly until the button is let
 * go, and stops while the pointer is off the half it pressed. Each step
 * sends the action. With full keyboard access the up and down arrow keys
 * step too.
 *
 * The settings live in the cell, which a nib holds: "NSMinValue",
 * "NSMaxValue", "NSIncrement", "NSValue", "NSAutorepeat" and
 * "NSValueWraps", the names given in descriptions of the format published
 * by developers and by the GNUstep project; no Apple code was read. */
#import "AInternal.h"

/* The delay before a held arrow repeats, and the time between repeats:
 * the button cell's documented periodic defaults. */
static const NSTimeInterval repeat_delay = 0.4, repeat_interval = 0.075;

@interface NSStepper (FerryStepper)
- (NSInteger)_pressedHalf;
@end

@implementation NSStepperCell {
@public
    double _min, _max, _increment;
    BOOL _autorepeat, _wraps;
}
- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super initTextCell:string])) {
        _max = 59;
        _increment = 1;
        _autorepeat = _wraps = YES;
        [self setObjectValue:@0.0];
    }
    return self;
}
static double coder_double(NSCoder *c, NSString *key, double fallback)
{
    return [c containsValueForKey:key] ? [c decodeDoubleForKey:key] : fallback;
}
static BOOL coder_bool(NSCoder *c, NSString *key, BOOL fallback)
{
    return [c containsValueForKey:key] ? [c decodeBoolForKey:key] : fallback;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    _min = coder_double(c, @"NSMinValue", 0);
    _max = coder_double(c, @"NSMaxValue", 59);
    _increment = coder_double(c, @"NSIncrement", 1);
    _autorepeat = coder_bool(c, @"NSAutorepeat", YES);
    _wraps = coder_bool(c, @"NSValueWraps", YES);
    [self setObjectValue:@(coder_double(c, @"NSValue", _min))];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [super encodeWithCoder:c];
    [c encodeDouble:_min forKey:@"NSMinValue"];
    [c encodeDouble:_max forKey:@"NSMaxValue"];
    [c encodeDouble:_increment forKey:@"NSIncrement"];
    [c encodeDouble:[self doubleValue] forKey:@"NSValue"];
    [c encodeBool:_autorepeat forKey:@"NSAutorepeat"];
    [c encodeBool:_wraps forKey:@"NSValueWraps"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSStepperCell *c = [super copyWithZone:zone];
    c->_min = _min;
    c->_max = _max;
    c->_increment = _increment;
    c->_autorepeat = _autorepeat;
    c->_wraps = _wraps;
    return c;
}
- (double)minValue { return _min; }
- (void)setMinValue:(double)v { _min = v; }
- (double)maxValue { return _max; }
- (void)setMaxValue:(double)v { _max = v; }
- (double)increment { return _increment; }
- (void)setIncrement:(double)v { _increment = v; }
- (BOOL)autorepeat { return _autorepeat; }
- (void)setAutorepeat:(BOOL)f { _autorepeat = f; }
- (BOOL)valueWraps { return _wraps; }
- (void)setValueWraps:(BOOL)f { _wraps = f; }
- (double)doubleValue
{
    id v = [self objectValue];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}

/* Drawn for a table's cells and for the control alike. */
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view { [self drawInteriorWithFrame:frame inView:view]; }
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    NSInteger pressed = [view respondsToSelector:@selector(_pressedHalf)] ? [(NSStepper *)view _pressedHalf] : 0;
    CGFloat dim = [self isEnabled] ? 1 : 0.45;
    CGFloat w = fmin(frame.size.width, 15), h = fmin(frame.size.height, 23);
    NSRect box = NSMakeRect(round(NSMidX(frame) - w / 2) + 0.5, round(NSMidY(frame) - h / 2) + 0.5, w - 1, h - 1);
    BOOL flipped = [view isFlipped];
    NSRect top = box, bottom = box;
    top.size.height = bottom.size.height = box.size.height / 2;
    if (flipped)
        bottom.origin.y = NSMidY(box);
    else
        top.origin.y = NSMidY(box);
    AFillRoundedRect(box, 5, [[NSColor whiteColor] colorWithAlphaComponent:dim], nil);
    if (pressed) {
        CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
        CGContextSaveGState(cg);
        CGContextClipToRect(cg, pressed > 0 ? top : bottom);
        AFillRoundedRect(box, 5, [NSColor colorWithWhite:0 alpha:0.12], nil);
        CGContextRestoreGState(cg);
    }
    AFillRoundedRect(box, 5, nil, [NSColor colorWithWhite:0 alpha:0.22 * dim]);
    [[NSColor colorWithWhite:0 alpha:0.15 * dim] setFill];
    NSRectFill(NSMakeRect(box.origin.x + 2, round(NSMidY(box)) - 0.5, box.size.width - 4, 1));
    /* the arrows: small chevrons */
    NSColor *ink = [NSColor colorWithWhite:0.2 alpha:dim];
    [ink setStroke];
    for (int i = 0; i < 2; i++) {
        NSRect half = i == 0 ? top : bottom;
        BOOL up = i == 0;
        /* "up" points to larger y unless flipped */
        CGFloat dir = (up != flipped) ? 1 : -1;
        CGFloat cx = NSMidX(half), cy = NSMidY(half), s = 2.5;
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(cx - s, cy - dir * s / 2)];
        [p lineToPoint:NSMakePoint(cx, cy + dir * s / 2)];
        [p lineToPoint:NSMakePoint(cx + s, cy - dir * s / 2)];
        [p setLineWidth:1.5];
        [p setLineCapStyle:NSLineCapStyleRound];
        [p setLineJoinStyle:NSLineJoinStyleRound];
        [p stroke];
    }
}
- (NSSize)cellSize { return NSMakeSize(19, 27); }
@end

@implementation NSStepper {
    BOOL _loading;
    NSInteger _pressed;     /* 1: the top half, -1: the bottom one, 0: neither */
    NSInteger _tracking;    /* the half the mouse went down in */
    NSTimer *_repeat;
    BOOL _fast;             /* repeating quickly, after the first delay */
}

+ (Class)cellClass { return [NSStepperCell class]; }
- (NSStepperCell *)_stepperCell { return (NSStepperCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    [self setObjectValue:@0.0];
    if (!_loading && ![[self cell] isKindOfClass:[NSStepperCell class]]) {
        NSStepperCell *cell = [[NSStepperCell alloc] initTextCell:@""];
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
    if (![[self cell] isKindOfClass:[NSStepperCell class]]) {
        NSStepperCell *cell = [[NSStepperCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    return self;
}
- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
    if ([cell isKindOfClass:[NSStepperCell class]])
        [super setObjectValue:@([(NSStepperCell *)cell doubleValue])];
}
- (void)dealloc
{
    [_repeat invalidate];
    [_repeat release];
    [super dealloc];
}

/* ---- the settings, kept in the cell ---- */

- (double)minValue { return [[self _stepperCell] minValue]; }
- (void)setMinValue:(double)v
{
    [[self _stepperCell] setMinValue:v];
    [self setDoubleValue:[self doubleValue]];
}
- (double)maxValue { return [[self _stepperCell] maxValue]; }
- (void)setMaxValue:(double)v
{
    [[self _stepperCell] setMaxValue:v];
    [self setDoubleValue:[self doubleValue]];
}
- (double)increment { return [[self _stepperCell] increment]; }
- (void)setIncrement:(double)v { [[self _stepperCell] setIncrement:v]; }
- (BOOL)autorepeat { return [[self _stepperCell] autorepeat]; }
- (void)setAutorepeat:(BOOL)f { [[self _stepperCell] setAutorepeat:f]; }
- (BOOL)valueWraps { return [[self _stepperCell] valueWraps]; }
- (void)setValueWraps:(BOOL)f { [[self _stepperCell] setValueWraps:f]; }

/* ---- the value, kept between the ends ---- */

- (void)setObjectValue:(id)value
{
    double v = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    NSStepperCell *c = [self _stepperCell];
    if (c) {
        double lo = fmin([c minValue], [c maxValue]), hi = fmax([c minValue], [c maxValue]);
        if (isnan(v))
            v = lo;
        v = fmin(fmax(v, lo), hi);
        [c setObjectValue:@(v)];
    }
    [super setObjectValue:@(v)];
}
- (double)doubleValue { return [[super objectValue] doubleValue]; }
- (float)floatValue { return (float)[self doubleValue]; }
- (int)intValue { return (int)[self doubleValue]; }
- (NSInteger)integerValue { return (NSInteger)[self doubleValue]; }
- (NSString *)stringValue
{
    if ([self formatter]) {
        NSString *s = [[self formatter] stringForObjectValue:[super objectValue]];
        if (s)
            return s;
    }
    return [[super objectValue] stringValue];
}
- (void)setStringValue:(NSString *)s { [self setDoubleValue:[s doubleValue]]; }

/* One step up (+1) or down (-1), wrapping or stopping at the ends; the
 * action goes out each time. */
- (void)_step:(NSInteger)direction
{
    NSStepperCell *c = [self _stepperCell];
    double lo = [c minValue], hi = [c maxValue], v = [self doubleValue];
    double next = v + (double)direction * [c increment];
    /* a rounding error shouldn't stop a step landing on an end */
    double slop = fabs([c increment]) * 1e-9;
    if (next > hi + slop)
        next = [c valueWraps] ? lo : hi;
    else if (next < lo - slop)
        next = [c valueWraps] ? hi : lo;
    [self setDoubleValue:next];
    if ([self doubleValue] != v)
        ABindingsPush(self, NO);
    [self sendAction:[self action] to:[self target]];
}

/* ---- the mouse and the keyboard ---- */

- (NSInteger)_pressedHalf { return _pressed; }
- (NSInteger)_halfAt:(NSPoint)p
{
    NSRect b = [self bounds];
    if (!NSPointInRect(p, b))
        return 0;
    BOOL upper = [self isFlipped] ? p.y < NSMidY(b) : p.y >= NSMidY(b);
    return upper ? 1 : -1;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder { return [self isEnabled] && [NSApp isFullKeyboardAccessEnabled]; }

- (void)_stopRepeating
{
    [_repeat invalidate];
    [_repeat release];
    _repeat = nil;
}
- (void)_repeatStep:(NSTimer *)t
{
    if (!_tracking)
        return;
    if (_pressed == _tracking)
        [self _step:_tracking];
    if (!_fast) {
        /* the first repeat came after the delay; the rest come quickly */
        [self _stopRepeating];
        _fast = YES;
        _repeat = [[NSTimer scheduledTimerWithTimeInterval:repeat_interval target:self selector:@selector(_repeatStep:)
                                                  userInfo:nil repeats:YES] retain];
    }
}
- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    NSInteger half = [self _halfAt:[self convertPoint:[event locationInWindow] fromView:nil]];
    if (!half)
        return;
    _tracking = _pressed = half;
    [self setHighlighted:YES];
    [self _step:half];
    if ([self autorepeat]) {
        [self _stopRepeating];
        _fast = NO;
        _repeat = [[NSTimer scheduledTimerWithTimeInterval:repeat_delay target:self selector:@selector(_repeatStep:)
                                                  userInfo:nil repeats:NO] retain];
    }
}
- (void)mouseDragged:(NSEvent *)event
{
    if (!_tracking)
        return;
    NSInteger half = [self _halfAt:[self convertPoint:[event locationInWindow] fromView:nil]];
    NSInteger now = half == _tracking ? half : 0;
    if (now != _pressed) {
        _pressed = now;
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseUp:(NSEvent *)event
{
    if (!_tracking)
        return;
    _tracking = _pressed = 0;
    [self _stopRepeating];
    [self setHighlighted:NO];
    [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent *)event
{
    if ([self isEnabled])
        [self interpretKeyEvents:@[ event ]];
    else
        [super keyDown:event];
}
- (void)moveUp:(id)sender { [self _step:1]; }
- (void)moveDown:(id)sender { [self _step:-1]; }
- (void)doCommandBySelector:(SEL)sel
{
    if (sel == @selector(moveUp:) || sel == @selector(moveDown:))
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
    else
        [super doCommandBySelector:sel];
}
- (void)insertText:(id)string {}

/* ---- drawing ---- */

- (NSSize)intrinsicContentSize { return NSMakeSize(19, 27); }
- (void)drawRect:(NSRect)dirty
{
    [[self cell] setEnabled:[self isEnabled]];
    [[self cell] drawWithFrame:[self bounds] inView:self];
    if ([[self window] firstResponder] == self && [[self window] isKeyWindow]) {
        NSRect b = [self bounds];
        CGFloat w = fmin(b.size.width, 15), h = fmin(b.size.height, 23);
        NSRect box = NSMakeRect(round(NSMidX(b) - w / 2) + 0.5, round(NSMidY(b) - h / 2) + 0.5, w - 1, h - 1);
        AFillRoundedRect(NSInsetRect(box, -1.5, -1.5), 6.5, nil, [NSColor keyboardFocusIndicatorColor]);
    }
}
@end
