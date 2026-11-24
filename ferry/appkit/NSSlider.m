/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: sliders (NSSlider, NSSliderCell), written from Apple's
 * public API documentation. Ferry draws a current Mac's slider its own way:
 * a thin rounded track filled with the accent colour up to a round white
 * knob, and tick marks below (or right of) it when there are any.
 *
 * The value runs from minValue to maxValue (0 and 1 unless set) and is
 * kept inside them. Pressing on the track moves the knob there; dragging
 * moves it on. A slider is continuous unless told otherwise: it sends its
 * action as the knob moves, and on letting go. With tick marks and
 * allowsTickMarkValuesOnly the value snaps to the nearest mark. With full
 * keyboard access the arrow keys move it a step (a tick mark, or a
 * twentieth of its range). A slider taller than it is wide is vertical.
 *
 * A nib keeps the settings in the cell: "NSMinValue", "NSMaxValue",
 * "NSValue", "NSAltIncValue", "NSNumberOfTickMarks", "NSTickMarkPosition",
 * "NSAllowsTickMarkValuesOnly" and "NSVertical", the names given in
 * descriptions of the format published by developers; no Apple code was
 * read. Circular sliders are drawn and tracked as linear ones. */
#import "AInternal.h"

/* ---- NSSliderCell -------------------------------------------------------------------- */

@implementation NSSliderCell {
@public
    double _min, _max, _alt;
    NSInteger _ticks;
    BOOL _ticksOnly;
    NSInteger _vertical;   /* -1: as the frame is */
    NSTickMarkPosition _tickPosition;
    NSSliderType _sliderType;
}
- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super initTextCell:string])) {
        _max = 1;
        _vertical = -1;
        [self setObjectValue:@0.0];
        [self setContinuous:YES];
    }
    return self;
}
static double coder_double(NSCoder *c, NSString *key, double fallback)
{
    return [c containsValueForKey:key] ? [c decodeDoubleForKey:key] : fallback;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    _min = coder_double(c, @"NSMinValue", 0);
    _max = coder_double(c, @"NSMaxValue", 1);
    _alt = coder_double(c, @"NSAltIncValue", 0);
    if ([c containsValueForKey:@"NSValue"])
        [self setObjectValue:@([c decodeDoubleForKey:@"NSValue"])];
    else if (![[self objectValue] isKindOfClass:[NSNumber class]])
        [self setObjectValue:@(_min)];
    _ticks = [c containsValueForKey:@"NSNumberOfTickMarks"] ? [c decodeIntegerForKey:@"NSNumberOfTickMarks"] : 0;
    _ticksOnly = [c containsValueForKey:@"NSAllowsTickMarkValuesOnly"] && [c decodeBoolForKey:@"NSAllowsTickMarkValuesOnly"];
    _tickPosition = [c containsValueForKey:@"NSTickMarkPosition"] ? [c decodeIntegerForKey:@"NSTickMarkPosition"] : 0;
    _vertical = [c containsValueForKey:@"NSVertical"] ? [c decodeBoolForKey:@"NSVertical"] : -1;
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    NSSliderCell *c = [super copyWithZone:zone];
    c->_min = _min;
    c->_max = _max;
    c->_alt = _alt;
    c->_ticks = _ticks;
    c->_ticksOnly = _ticksOnly;
    c->_vertical = _vertical;
    c->_tickPosition = _tickPosition;
    c->_sliderType = _sliderType;
    return c;
}
- (double)minValue { return _min; }
- (void)setMinValue:(double)v { _min = v; }
- (double)maxValue { return _max; }
- (void)setMaxValue:(double)v { _max = v; }
- (double)altIncrementValue { return _alt; }
- (void)setAltIncrementValue:(double)v { _alt = v; }
- (NSInteger)numberOfTickMarks { return _ticks; }
- (void)setNumberOfTickMarks:(NSInteger)n { _ticks = n < 0 ? 0 : n; }
- (BOOL)allowsTickMarkValuesOnly { return _ticksOnly; }
- (void)setAllowsTickMarkValuesOnly:(BOOL)f { _ticksOnly = f; }
- (NSTickMarkPosition)tickMarkPosition { return _tickPosition; }
- (void)setTickMarkPosition:(NSTickMarkPosition)p { _tickPosition = p; }
- (NSSliderType)sliderType { return _sliderType; }
- (void)setSliderType:(NSSliderType)t { _sliderType = t; }
- (BOOL)isVertical { return _vertical > 0; }
- (void)setVertical:(BOOL)f { _vertical = f; }
- (NSInteger)_verticalSetting { return _vertical; }
@end

/* ---- NSSlider ------------------------------------------------------------------------ */

static const CGFloat knob_size = 20, track_width = 4;

@implementation NSSlider {
    double _min, _max, _alt;
    NSInteger _ticks;
    BOOL _ticksOnly, _tracking;
    NSInteger _vertical;   /* -1: as the frame is */
    NSTickMarkPosition _tickPosition;
    NSSliderType _sliderType;
    NSColor *_trackFill;
}

+ (Class)cellClass { return [NSSliderCell class]; }

+ (instancetype)sliderWithTarget:(id)target action:(SEL)action
{
    return [self sliderWithValue:0 minValue:0 maxValue:1 target:target action:action];
}
+ (instancetype)sliderWithValue:(double)value minValue:(double)min maxValue:(double)max target:(id)target
                         action:(SEL)action
{
    NSSlider *s = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 96, 21)] autorelease];
    [s setMinValue:min];
    [s setMaxValue:max];
    [s setDoubleValue:value];
    [s setTarget:target];
    [s setAction:action];
    return s;
}

- (void)_setDefaults
{
    [super _setDefaults];
    _max = 1;
    _vertical = -1;
    [self setContinuous:YES];
    [self setObjectValue:@0.0];
}

- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
    if (![cell isKindOfClass:[NSSliderCell class]])
        return;
    NSSliderCell *s = (NSSliderCell *)cell;
    _min = [s minValue];
    _max = [s maxValue];
    _alt = [s altIncrementValue];
    _ticks = [s numberOfTickMarks];
    _ticksOnly = [s allowsTickMarkValuesOnly];
    _tickPosition = [s tickMarkPosition];
    _sliderType = [s sliderType];
    _vertical = [s _verticalSetting];
    [self setDoubleValue:[s doubleValue]];
}

- (void)dealloc
{
    [_trackFill release];
    [super dealloc];
}

/* ---- the value ---- */

- (double)_clamp:(double)v
{
    double lo = fmin(_min, _max), hi = fmax(_min, _max);
    if (isnan(v))
        v = lo;
    v = fmin(fmax(v, lo), hi);
    if (_ticksOnly && _ticks > 0)
        v = [self closestTickMarkValueToValue:v];
    return v;
}
- (void)setObjectValue:(id)value
{
    double v = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : _min;
    [super setObjectValue:@([self _clamp:v])];
}
- (double)doubleValue { return [[super objectValue] doubleValue]; }
- (float)floatValue { return (float)[[super objectValue] doubleValue]; }
- (int)intValue { return (int)[[super objectValue] doubleValue]; }
- (NSInteger)integerValue { return (NSInteger)[[super objectValue] doubleValue]; }
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

- (double)minValue { return _min; }
- (void)setMinValue:(double)v
{
    _min = v;
    [self setDoubleValue:[self doubleValue]];
}
- (double)maxValue { return _max; }
- (void)setMaxValue:(double)v
{
    _max = v;
    [self setDoubleValue:[self doubleValue]];
}
- (double)altIncrementValue { return _alt; }
- (void)setAltIncrementValue:(double)v { _alt = v; }
- (NSInteger)numberOfTickMarks { return _ticks; }
- (void)setNumberOfTickMarks:(NSInteger)n
{
    _ticks = n < 0 ? 0 : n;
    [self setDoubleValue:[self doubleValue]];
}
- (BOOL)allowsTickMarkValuesOnly { return _ticksOnly; }
- (void)setAllowsTickMarkValuesOnly:(BOOL)f
{
    _ticksOnly = f;
    [self setDoubleValue:[self doubleValue]];
}
- (NSTickMarkPosition)tickMarkPosition { return _tickPosition; }
- (void)setTickMarkPosition:(NSTickMarkPosition)p
{
    _tickPosition = p;
    [self setNeedsDisplay:YES];
}
- (NSSliderType)sliderType { return _sliderType; }
- (void)setSliderType:(NSSliderType)t { _sliderType = t; }
- (BOOL)isVertical
{
    if (_vertical >= 0)
        return _vertical != 0;
    NSSize s = [self frame].size;
    return s.height > s.width;
}
- (void)setVertical:(BOOL)f
{
    _vertical = f;
    [self setNeedsDisplay:YES];
}
- (NSColor *)trackFillColor { return _trackFill; }
- (void)setTrackFillColor:(NSColor *)c
{
    [_trackFill release];
    _trackFill = [c retain];
    [self setNeedsDisplay:YES];
}
- (double)knobThickness { return knob_size; }

- (double)tickMarkValueAtIndex:(NSInteger)index
{
    if (_ticks <= 1)
        return _ticks == 1 ? (_min + _max) / 2 : _min;
    return _min + (_max - _min) * (double)index / (double)(_ticks - 1);
}
- (double)closestTickMarkValueToValue:(double)value
{
    if (_ticks <= 0)
        return value;
    double best = [self tickMarkValueAtIndex:0];
    for (NSInteger i = 1; i < _ticks; i++) {
        double t = [self tickMarkValueAtIndex:i];
        if (fabs(t - value) < fabs(best - value))
            best = t;
    }
    return best;
}

/* ---- geometry ---- */

/* The line the knob's centre runs along, from the minimum's end. */
- (void)_trackFrom:(NSPoint *)from to:(NSPoint *)to
{
    NSRect b = [self bounds];
    CGFloat r = knob_size / 2;
    BOOL ticksBefore = _ticks > 0 && _tickPosition == NSTickMarkPositionAbove;   /* above, or left */
    BOOL ticksAfter = _ticks > 0 && !ticksBefore;
    if ([self isVertical]) {
        CGFloat x = NSMidX(b) + (ticksAfter ? -3 : ticksBefore ? 3 : 0);
        /* the minimum is at the bottom */
        BOOL flipped = [self isFlipped];
        *from = NSMakePoint(x, flipped ? NSMaxY(b) - r : NSMinY(b) + r);
        *to = NSMakePoint(x, flipped ? NSMinY(b) + r : NSMaxY(b) - r);
    } else {
        CGFloat y = NSMidY(b);
        if (_ticks > 0) {
            /* the ticks go below (above) the track */
            CGFloat shift = [self isFlipped] ? -3 : 3;
            y += ticksAfter ? shift : -shift;
        }
        *from = NSMakePoint(NSMinX(b) + r, y);
        *to = NSMakePoint(NSMaxX(b) - r, y);
    }
}
- (CGFloat)_fraction
{
    return _max == _min ? 0 : ([self doubleValue] - _min) / (_max - _min);
}
- (NSPoint)_knobCentre
{
    NSPoint a, z;
    [self _trackFrom:&a to:&z];
    CGFloat f = [self _fraction];
    return NSMakePoint(a.x + (z.x - a.x) * f, a.y + (z.y - a.y) * f);
}
- (double)_valueAt:(NSPoint)p
{
    NSPoint a, z;
    [self _trackFrom:&a to:&z];
    CGFloat len = [self isVertical] ? z.y - a.y : z.x - a.x;
    CGFloat at = [self isVertical] ? p.y - a.y : p.x - a.x;
    double f = len == 0 ? 0 : fmin(fmax(at / len, 0), 1);
    return _min + (_max - _min) * f;
}
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index
{
    if (index < 0 || index >= _ticks)
        [NSException raise:NSRangeException format:@"-[NSSlider rectOfTickMarkAtIndex:]: no tick mark %ld",
                                                    (long)index];
    NSPoint a, z;
    [self _trackFrom:&a to:&z];
    double f = _ticks == 1 ? 0.5 : (double)index / (double)(_ticks - 1);
    NSPoint c = NSMakePoint(a.x + (z.x - a.x) * f, a.y + (z.y - a.y) * f);
    BOOL before = _tickPosition == NSTickMarkPositionAbove;
    if ([self isVertical])
        return NSMakeRect(before ? c.x - knob_size / 2 - 5 : c.x + knob_size / 2 + 1, c.y - 0.5, 4, 1);
    CGFloat down = [self isFlipped] ? 1 : -1;   /* towards the bottom */
    CGFloat y = before ? c.y - down * (knob_size / 2 + 1) : c.y + down * (knob_size / 2 + 1);
    return NSMakeRect(c.x - 0.5, fmin(y, y + down * 4), 1, 4);
}
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point
{
    for (NSInteger i = 0; i < _ticks; i++)
        if (NSPointInRect(point, NSInsetRect([self rectOfTickMarkAtIndex:i], -2, -2)))
            return i;
    return NSNotFound;
}

/* ---- the mouse and the keyboard ---- */

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder { return [self isEnabled] && [NSApp isFullKeyboardAccessEnabled]; }

/* The user moved the knob: the value, its bindings, and the action. */
- (void)_userSet:(double)v sendAction:(BOOL)send
{
    double before = [self doubleValue];
    [self setDoubleValue:v];
    if ([self doubleValue] != before)
        ABindingsPush(self, NO);
    if (send)
        [self sendAction:[self action] to:[self target]];
}

- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    _tracking = YES;
    [self setHighlighted:YES];
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    NSPoint k = [self _knobCentre];
    /* a press on the knob keeps it where it is; one on the track moves it there */
    if (hypot(p.x - k.x, p.y - k.y) > knob_size / 2)
        [self _userSet:[self _valueAt:p] sendAction:[self isContinuous]];
}
- (void)mouseDragged:(NSEvent *)event
{
    if (!_tracking)
        return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    [self _userSet:[self _valueAt:p] sendAction:[self isContinuous]];
}
- (void)mouseUp:(NSEvent *)event
{
    if (!_tracking)
        return;
    _tracking = NO;
    [self setHighlighted:NO];
    [self _userSet:[self doubleValue] sendAction:YES];
}

- (double)_step
{
    if (_ticks > 1)
        return fabs(_max - _min) / (double)(_ticks - 1);
    return fabs(_max - _min) / 20;
}
- (void)_stepBy:(double)n { [self _userSet:[self doubleValue] + n * [self _step] sendAction:YES]; }
- (void)keyDown:(NSEvent *)event
{
    if ([self isEnabled])
        [self interpretKeyEvents:@[ event ]];
    else
        [super keyDown:event];
}
- (void)moveRight:(id)sender { [self _stepBy:1]; }
- (void)moveLeft:(id)sender { [self _stepBy:-1]; }
- (void)moveUp:(id)sender { [self _stepBy:1]; }
- (void)moveDown:(id)sender { [self _stepBy:-1]; }
- (void)moveToBeginningOfLine:(id)sender { [self _userSet:_min sendAction:YES]; }
- (void)moveToEndOfLine:(id)sender { [self _userSet:_max sendAction:YES]; }
- (void)doCommandBySelector:(SEL)sel
{
    if ([self respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
}
- (void)insertText:(id)string {}

/* ---- drawing ---- */

- (NSSize)intrinsicContentSize
{
    CGFloat extra = _ticks > 0 ? 6 : 0;
    return [self isVertical] ? NSMakeSize(knob_size + 1 + extra, -1) : NSMakeSize(-1, knob_size + 1 + extra);
}

- (void)drawRect:(NSRect)dirty
{
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    NSPoint a, z;
    [self _trackFrom:&a to:&z];
    NSPoint k = [self _knobCentre];
    BOOL vertical = [self isVertical];
    NSRect track = vertical ? NSMakeRect(a.x - track_width / 2, fmin(a.y, z.y), track_width, fabs(z.y - a.y))
                            : NSMakeRect(a.x, a.y - track_width / 2, z.x - a.x, track_width);
    AFillRoundedRect(track, track_width / 2, [NSColor colorWithWhite:0 alpha:0.12 * dim], nil);
    NSRect filled = vertical ? NSMakeRect(track.origin.x, fmin(a.y, k.y), track_width, fabs(k.y - a.y))
                             : NSMakeRect(a.x, track.origin.y, k.x - a.x, track_width);
    NSColor *fill = _trackFill ?: [NSColor controlAccentColor];
    if (filled.size.width > 0 && filled.size.height > 0)
        AFillRoundedRect(filled, track_width / 2, [fill colorWithAlphaComponent:dim], nil);
    [[NSColor colorWithWhite:0 alpha:0.35 * dim] setFill];
    for (NSInteger i = 0; i < _ticks; i++)
        NSRectFill([self rectOfTickMarkAtIndex:i]);
    NSRect knob = NSMakeRect(k.x - knob_size / 2 + 0.5, k.y - knob_size / 2 + 0.5, knob_size - 1, knob_size - 1);
    NSColor *face = [self isHighlighted] ? [NSColor colorWithWhite:0.94 alpha:1] : [NSColor whiteColor];
    AFillRoundedRect(knob, (knob_size - 1) / 2, face, [NSColor colorWithWhite:0 alpha:0.25 * dim]);
    if ([[self window] firstResponder] == self && [[self window] isKeyWindow])
        AFillRoundedRect(NSInsetRect(knob, -1.5, -1.5), knob_size / 2 + 1.5, nil, [NSColor keyboardFocusIndicatorColor]);
}
@end
