/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: level indicators (NSLevelIndicator, NSLevelIndicatorCell),
 * written from Apple's public API documentation and drawn Ferry's own way:
 *
 * - continuous capacity: a rounded bar filled from the start, green, then
 *   yellow past the warning value and red past the critical value (or,
 *   with the critical value below the warning value, yellow and red as the
 *   value falls to them);
 * - discrete capacity: one rounded segment for each whole step between the
 *   minimum and the maximum, filled up to the value (rounded), each in its
 *   own tier's colour with drawsTieredCapacityLevels;
 * - relevancy: thin grey bars up to the value;
 * - rating: a star for each whole step, filled up to the value, with dots
 *   in place of the empty stars when placeholders are shown (always, while
 *   the user edits, or, automatically, when it can be edited).
 *
 * The cell draws (so a table column can use one, as rating columns do) and
 * keeps the settings; the control shows its cell. An editable indicator
 * takes a click or a drag to set its value (a click at the very start of a
 * rating clears it) and sends its action when the mouse goes up, or as it
 * moves if continuous; with full keyboard access the arrow keys step it.
 *
 * Nib keys, from developers' published descriptions of the format (no
 * Apple code was read): "NSMinValue", "NSMaxValue", "NSValue",
 * "NSWarningValue", "NSCriticalValue", "NSIndicatorStyle",
 * "NSNumberOfTickMarks", "NSNumberOfMajorTickMarks", "NSTickMarkPosition"
 * and "NSRatingPlaceholder" kept in the cell. */
#import "AInternal.h"

@implementation NSLevelIndicatorCell {
@public
    NSLevelIndicatorStyle _style;
    double _min, _max, _warning, _critical;
    NSTickMarkPosition _tickPosition;
    NSInteger _ticks, _majorTicks;
    NSImage *_ratingImage, *_ratingPlaceholder;
    NSColor *_fill, *_warningFill, *_criticalFill;
    BOOL _tiered;
    NSLevelIndicatorPlaceholderVisibility _placeholders;
    BOOL _tracking;
}
- (instancetype)initTextCell:(NSString *)string { return [self initWithLevelIndicatorStyle:NSLevelIndicatorStyleRelevancy]; }
- (instancetype)initWithLevelIndicatorStyle:(NSLevelIndicatorStyle)style
{
    if ((self = [super initTextCell:@""])) {
        _style = style;
        _max = 2;
        [self setObjectValue:@0.0];
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
    _max = coder_double(c, @"NSMaxValue", 2);
    _warning = coder_double(c, @"NSWarningValue", 0);
    _critical = coder_double(c, @"NSCriticalValue", 0);
    _style = [c containsValueForKey:@"NSIndicatorStyle"] ? (NSLevelIndicatorStyle)[c decodeIntegerForKey:@"NSIndicatorStyle"] : 0;
    _ticks = [c containsValueForKey:@"NSNumberOfTickMarks"] ? [c decodeIntegerForKey:@"NSNumberOfTickMarks"] : 0;
    _majorTicks = [c containsValueForKey:@"NSNumberOfMajorTickMarks"] ? [c decodeIntegerForKey:@"NSNumberOfMajorTickMarks"] : 0;
    _tickPosition = [c containsValueForKey:@"NSTickMarkPosition"] ? (NSTickMarkPosition)[c decodeIntegerForKey:@"NSTickMarkPosition"] : 0;
    _placeholders = [c containsValueForKey:@"NSRatingPlaceholder"] ? [c decodeIntegerForKey:@"NSRatingPlaceholder"] : 0;
    [self setObjectValue:@(coder_double(c, @"NSValue", _min))];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [super encodeWithCoder:c];
    [c encodeDouble:_min forKey:@"NSMinValue"];
    [c encodeDouble:_max forKey:@"NSMaxValue"];
    [c encodeDouble:_warning forKey:@"NSWarningValue"];
    [c encodeDouble:_critical forKey:@"NSCriticalValue"];
    [c encodeDouble:[self doubleValue] forKey:@"NSValue"];
    [c encodeInteger:(NSInteger)_style forKey:@"NSIndicatorStyle"];
    [c encodeInteger:_ticks forKey:@"NSNumberOfTickMarks"];
    [c encodeInteger:_majorTicks forKey:@"NSNumberOfMajorTickMarks"];
    [c encodeInteger:(NSInteger)_tickPosition forKey:@"NSTickMarkPosition"];
}
- (void)dealloc
{
    [_ratingImage release];
    [_ratingPlaceholder release];
    [_fill release];
    [_warningFill release];
    [_criticalFill release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSLevelIndicatorCell *c = [super copyWithZone:zone];
    c->_style = _style;
    c->_min = _min;
    c->_max = _max;
    c->_warning = _warning;
    c->_critical = _critical;
    c->_tickPosition = _tickPosition;
    c->_ticks = _ticks;
    c->_majorTicks = _majorTicks;
    c->_ratingImage = [_ratingImage retain];
    c->_ratingPlaceholder = [_ratingPlaceholder retain];
    c->_fill = [_fill retain];
    c->_warningFill = [_warningFill retain];
    c->_criticalFill = [_criticalFill retain];
    c->_tiered = _tiered;
    c->_placeholders = _placeholders;
    c->_tracking = NO;
    return c;
}

- (NSLevelIndicatorStyle)levelIndicatorStyle { return _style; }
- (void)setLevelIndicatorStyle:(NSLevelIndicatorStyle)s { _style = s; }
- (double)minValue { return _min; }
- (void)setMinValue:(double)v { _min = v; }
- (double)maxValue { return _max; }
- (void)setMaxValue:(double)v { _max = v; }
- (double)warningValue { return _warning; }
- (void)setWarningValue:(double)v { _warning = v; }
- (double)criticalValue { return _critical; }
- (void)setCriticalValue:(double)v { _critical = v; }
- (NSTickMarkPosition)tickMarkPosition { return _tickPosition; }
- (void)setTickMarkPosition:(NSTickMarkPosition)p { _tickPosition = p; }
- (NSInteger)numberOfTickMarks { return _ticks; }
- (void)setNumberOfTickMarks:(NSInteger)n { _ticks = n < 0 ? 0 : n; }
- (NSInteger)numberOfMajorTickMarks { return _majorTicks; }
- (void)setNumberOfMajorTickMarks:(NSInteger)n { _majorTicks = n < 0 ? 0 : n; }
- (NSImage *)ratingImage { return _ratingImage; }
- (void)setRatingImage:(NSImage *)i
{
    id wasRatingImage = _ratingImage;
    _ratingImage = [i retain];
    [wasRatingImage release];
}
- (NSImage *)ratingPlaceholderImage { return _ratingPlaceholder; }
- (void)setRatingPlaceholderImage:(NSImage *)i
{
    id wasRatingPlaceholder = _ratingPlaceholder;
    _ratingPlaceholder = [i retain];
    [wasRatingPlaceholder release];
}
- (double)doubleValue
{
    id v = [self objectValue];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}
- (void)setDoubleValue:(double)v { [self setObjectValue:@(v)]; }

- (double)tickMarkValueAtIndex:(NSInteger)index
{
    if (_ticks <= 1)
        return _ticks == 1 ? (_min + _max) / 2 : _min;
    return _min + (_max - _min) * (double)index / (double)(_ticks - 1);
}

/* ---- geometry ---- */

static const CGFloat tick_room = 5;

/* The bar (or the row of stars), leaving room for the tick marks. */
- (NSRect)_barRectForBounds:(NSRect)r flipped:(BOOL)flipped
{
    if (_style == NSLevelIndicatorStyleRating) {
        CGFloat h = fmin(r.size.height, 13);
        return NSMakeRect(r.origin.x + 1, round(NSMidY(r) - h / 2), r.size.width - 2, h);
    }
    CGFloat h = fmin(r.size.height - (_ticks > 0 ? tick_room : 0), 14);
    BOOL ticksAbove = _ticks > 0 && _tickPosition == NSTickMarkPositionAbove;
    BOOL ticksBelow = _ticks > 0 && !ticksAbove;
    CGFloat y = round(NSMidY(r) - h / 2);
    CGFloat shift = (ticksBelow ? 1 : ticksAbove ? -1 : 0) * tick_room / 2 * (flipped ? -1 : 1);
    return NSMakeRect(r.origin.x + 1, y + shift, r.size.width - 2, h);
}
- (NSRect)_tick:(NSInteger)index bar:(NSRect)bar flipped:(BOOL)flipped
{
    double f = _ticks == 1 ? 0.5 : (double)index / (double)(_ticks - 1);
    CGFloat x = round(bar.origin.x + (bar.size.width - 1) * f);
    BOOL major = _majorTicks > 0 && (_ticks <= 1 || index % MAX((_ticks - 1) / MAX(_majorTicks - 1, 1), 1) == 0);
    CGFloat len = major ? 4 : 2;
    /* above is towards larger y, unless the view is flipped */
    BOOL above = _tickPosition == NSTickMarkPositionAbove;
    CGFloat y = (above != flipped) ? NSMaxY(bar) + 1 : bar.origin.y - 1 - len;
    return NSMakeRect(x, y, 1, len);
}
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index
{
    if (index < 0 || index >= _ticks)
        [NSException raise:NSRangeException format:@"-[NSLevelIndicatorCell rectOfTickMarkAtIndex:]: no tick mark %ld",
                                                    (long)index];
    NSView *view = [self controlView];
    NSRect bounds = view ? [view bounds] : NSMakeRect(0, 0, 100, 20);
    return [self _tick:index bar:[self _barRectForBounds:bounds flipped:[view isFlipped]] flipped:[view isFlipped]];
}

/* The colour of a level: green, or the warning or critical tier's. */
- (NSColor *)_colorForLevel:(double)v
{
    NSColor *normal = _fill ?: [NSColor systemGreenColor];
    NSColor *warn = _warningFill ?: [NSColor systemYellowColor];
    NSColor *crit = _criticalFill ?: [NSColor systemRedColor];
    if (_warning < _critical) {
        if (v >= _critical)
            return crit;
        if (v >= _warning && _warning > _min)
            return warn;
    } else if (_critical < _warning) {
        if (v <= _critical)
            return crit;
        if (v <= _warning)
            return warn;
    }
    return normal;
}

- (NSInteger)_steps
{
    double n = round(_max - _min);
    return n < 1 ? 1 : (NSInteger)n;
}
- (CGFloat)_starStepForBar:(NSRect)bar { return bar.size.height + 2; }

- (BOOL)_showsPlaceholders
{
    switch (_placeholders) {
    case NSLevelIndicatorPlaceholderVisibilityAlways: return YES;
    case NSLevelIndicatorPlaceholderVisibilityWhileEditing: return _tracking;
    default: return [self isEditable];
    }
}

/* ---- drawing ---- */

static void star_path(NSBezierPath *p, NSPoint c, CGFloat r, BOOL flipped)
{
    for (int i = 0; i < 10; i++) {
        CGFloat a = M_PI / 2 + i * M_PI / 5, rad = (i % 2) ? r * 0.45 : r;
        NSPoint q = NSMakePoint(c.x + cos(a) * rad, c.y + (flipped ? -1 : 1) * sin(a) * rad);
        if (i == 0)
            [p moveToPoint:q];
        else
            [p lineToPoint:q];
    }
    [p closePath];
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view { [self drawInteriorWithFrame:frame inView:view]; }
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    BOOL light = [self backgroundStyle] == NSBackgroundStyleEmphasized;
    NSRect bar = [self _barRectForBounds:frame flipped:flipped];
    double v = fmin(fmax([self doubleValue], fmin(_min, _max)), fmax(_min, _max));
    double span = _max - _min;
    double f = span == 0 ? 0 : (v - _min) / span;

    switch (_style) {
    case NSLevelIndicatorStyleRating: {
        NSInteger n = [self _steps];
        CGFloat step = [self _starStepForBar:bar], r = bar.size.height / 2;
        NSInteger filled = (NSInteger)floor(v - _min + 0.5);
        NSColor *ink = light ? [NSColor whiteColor] : [NSColor colorWithWhite:0.3 alpha:1];
        for (NSInteger i = 0; i < n; i++) {
            NSPoint c = NSMakePoint(bar.origin.x + step * i + r, NSMidY(bar));
            if (i < filled) {
                if (_ratingImage) {
                    [_ratingImage _drawInControlRect:NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r) color:ink fraction:dim];
                    continue;
                }
                NSBezierPath *p = [NSBezierPath bezierPath];
                star_path(p, c, r, flipped);
                [[ink colorWithAlphaComponent:dim] setFill];
                [p fill];
            } else if ([self _showsPlaceholders]) {
                if (_ratingPlaceholder) {
                    [_ratingPlaceholder _drawInControlRect:NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r) color:ink
                                                  fraction:dim * 0.5];
                    continue;
                }
                [[ink colorWithAlphaComponent:0.35 * dim] setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 1.5, c.y - 1.5, 3, 3)] fill];
            }
        }
        break;
    }
    case NSLevelIndicatorStyleRelevancy: {
        NSColor *ink = light ? [NSColor whiteColor] : [NSColor colorWithWhite:0.45 alpha:1];
        [[ink colorWithAlphaComponent:dim] setFill];
        CGFloat end = bar.origin.x + bar.size.width * f;
        for (CGFloat x = bar.origin.x; x + 1 <= end + 0.01; x += 3)
            NSRectFill(NSMakeRect(x, bar.origin.y, 1, bar.size.height));
        break;
    }
    case NSLevelIndicatorStyleDiscreteCapacity: {
        NSInteger n = [self _steps];
        CGFloat gap = 2, w = (bar.size.width - gap * (n - 1)) / n;
        NSInteger filled = (NSInteger)floor((v - _min) + 0.5);
        NSColor *current = [self _colorForLevel:v];
        for (NSInteger i = 0; i < n; i++) {
            NSRect seg = NSMakeRect(round(bar.origin.x + i * (w + gap)) + 0.5, bar.origin.y + 0.5, round(w) - 1,
                                    bar.size.height - 1);
            NSColor *fill = nil;
            if (i < filled)
                fill = _tiered ? [self _colorForLevel:_min + i + 1] : current;
            AFillRoundedRect(seg, 2.5, fill ? [fill colorWithAlphaComponent:dim] : [NSColor colorWithWhite:0 alpha:0.06],
                             [NSColor colorWithWhite:0 alpha:0.2 * dim]);
        }
        break;
    }
    default: {   /* continuous capacity */
        NSRect r = NSInsetRect(bar, 0.5, 0.5);
        AFillRoundedRect(r, 3.5, [NSColor colorWithWhite:0 alpha:0.06], nil);
        if (f > 0) {
            CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
            CGContextSaveGState(cg);
            CGContextClipToRect(cg, NSMakeRect(r.origin.x, r.origin.y - 1, r.size.width * f, r.size.height + 2));
            if (_tiered && _warning != _critical) {
                /* each tier in its own colour, along the bar */
                CGFloat x0 = r.origin.x;
                for (int i = 0; i < 64; i++) {
                    double a = (double)i / 64, b = (double)(i + 1) / 64;
                    NSColor *c = [self _colorForLevel:_min + span * (a + b) / 2];
                    CGContextSaveGState(cg);
                    CGContextClipToRect(cg, NSMakeRect(x0 + r.size.width * a, r.origin.y - 1, r.size.width / 64 + 0.5,
                                                       r.size.height + 2));
                    AFillRoundedRect(r, 3.5, [c colorWithAlphaComponent:dim], nil);
                    CGContextRestoreGState(cg);
                }
            } else {
                AFillRoundedRect(r, 3.5, [[self _colorForLevel:v] colorWithAlphaComponent:dim], nil);
            }
            CGContextRestoreGState(cg);
        }
        AFillRoundedRect(r, 3.5, nil, [NSColor colorWithWhite:0 alpha:0.2 * dim]);
        break;
    }
    }
    if (_ticks > 0 && _style != NSLevelIndicatorStyleRating) {
        [[NSColor colorWithWhite:light ? 1 : 0 alpha:0.4 * dim] setFill];
        for (NSInteger i = 0; i < _ticks; i++)
            NSRectFill([self _tick:i bar:bar flipped:flipped]);
    }
}
- (NSSize)cellSize
{
    if (_style == NSLevelIndicatorStyleRating)
        return NSMakeSize([self _steps] * 15 + 2, 15);
    return NSMakeSize(100, 16 + (_ticks > 0 ? tick_room : 0));
}

/* The value a point in the bar stands for. */
- (double)_valueAt:(NSPoint)p inFrame:(NSRect)frame flipped:(BOOL)flipped
{
    NSRect bar = [self _barRectForBounds:frame flipped:flipped];
    CGFloat x = p.x - bar.origin.x;
    switch (_style) {
    case NSLevelIndicatorStyleRating: {
        if (x < 3)
            return _min;
        CGFloat step = [self _starStepForBar:bar];
        return fmin(_min + ceil(x / step), _max);
    }
    case NSLevelIndicatorStyleDiscreteCapacity: {
        double f = fmin(fmax(x / bar.size.width, 0), 1);
        return _min + ceil(f * [self _steps] - 1e-9);
    }
    default: {
        double f = fmin(fmax(x / bar.size.width, 0), 1);
        return _min + (_max - _min) * f;
    }
    }
}
@end

/* ---- NSLevelIndicator ---------------------------------------------------------------- */

@implementation NSLevelIndicator {
    BOOL _loading, _tracking;
}

+ (Class)cellClass { return [NSLevelIndicatorCell class]; }
- (NSLevelIndicatorCell *)_levelCell { return (NSLevelIndicatorCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    [super setObjectValue:@0.0];
    if (!_loading && ![[self cell] isKindOfClass:[NSLevelIndicatorCell class]]) {
        NSLevelIndicatorCell *cell = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle:NSLevelIndicatorStyleRelevancy];
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
    if (![[self cell] isKindOfClass:[NSLevelIndicatorCell class]]) {
        NSLevelIndicatorCell *cell = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle:NSLevelIndicatorStyleRelevancy];
        [self setCell:cell];
        [cell release];
    }
    return self;
}
- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
    if ([cell isKindOfClass:[NSLevelIndicatorCell class]])
        [super setObjectValue:@([(NSLevelIndicatorCell *)cell doubleValue])];
}

/* ---- the settings, kept in the cell ---- */

#define CELL_PROPERTY(type, get, set)                                                                                   \
    -(type)get { return [[self _levelCell] get]; }                                                                     \
    -(void)set:(type)v                                                                                                 \
    {                                                                                                                  \
        [[self _levelCell] set:v];                                                                                     \
        [self setNeedsDisplay:YES];                                                                                    \
    }
CELL_PROPERTY(NSLevelIndicatorStyle, levelIndicatorStyle, setLevelIndicatorStyle)
CELL_PROPERTY(double, warningValue, setWarningValue)
CELL_PROPERTY(double, criticalValue, setCriticalValue)
CELL_PROPERTY(NSTickMarkPosition, tickMarkPosition, setTickMarkPosition)
CELL_PROPERTY(NSInteger, numberOfTickMarks, setNumberOfTickMarks)
CELL_PROPERTY(NSInteger, numberOfMajorTickMarks, setNumberOfMajorTickMarks)
CELL_PROPERTY(NSImage *, ratingImage, setRatingImage)
CELL_PROPERTY(NSImage *, ratingPlaceholderImage, setRatingPlaceholderImage)
#undef CELL_PROPERTY
- (double)minValue { return [[self _levelCell] minValue]; }
- (void)setMinValue:(double)v
{
    [[self _levelCell] setMinValue:v];
    [self setDoubleValue:[self doubleValue]];
}
- (double)maxValue { return [[self _levelCell] maxValue]; }
- (void)setMaxValue:(double)v
{
    [[self _levelCell] setMaxValue:v];
    [self setDoubleValue:[self doubleValue]];
}
- (BOOL)isEditable { return [[self _levelCell] isEditable]; }
- (void)setEditable:(BOOL)f
{
    [[self _levelCell] setEditable:f];
    [self setNeedsDisplay:YES];
}
- (NSColor *)fillColor { return [self _levelCell]->_fill; }
- (void)setFillColor:(NSColor *)c
{
    NSLevelIndicatorCell *cell = [self _levelCell];
    [cell->_fill release];
    cell->_fill = [c copy];
    [self setNeedsDisplay:YES];
}
- (NSColor *)warningFillColor { return [self _levelCell]->_warningFill; }
- (void)setWarningFillColor:(NSColor *)c
{
    NSLevelIndicatorCell *cell = [self _levelCell];
    [cell->_warningFill release];
    cell->_warningFill = [c copy];
    [self setNeedsDisplay:YES];
}
- (NSColor *)criticalFillColor { return [self _levelCell]->_criticalFill; }
- (void)setCriticalFillColor:(NSColor *)c
{
    NSLevelIndicatorCell *cell = [self _levelCell];
    [cell->_criticalFill release];
    cell->_criticalFill = [c copy];
    [self setNeedsDisplay:YES];
}
- (BOOL)drawsTieredCapacityLevels { return [self _levelCell]->_tiered; }
- (void)setDrawsTieredCapacityLevels:(BOOL)f
{
    [self _levelCell]->_tiered = f;
    [self setNeedsDisplay:YES];
}
- (NSLevelIndicatorPlaceholderVisibility)placeholderVisibility { return [self _levelCell]->_placeholders; }
- (void)setPlaceholderVisibility:(NSLevelIndicatorPlaceholderVisibility)v
{
    [self _levelCell]->_placeholders = v;
    [self setNeedsDisplay:YES];
}
- (double)tickMarkValueAtIndex:(NSInteger)index { return [[self _levelCell] tickMarkValueAtIndex:index]; }
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index { return [[self _levelCell] rectOfTickMarkAtIndex:index]; }

/* ---- the value, kept between the ends ---- */

- (void)setObjectValue:(id)value
{
    double v = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    NSLevelIndicatorCell *c = [self _levelCell];
    if (c) {
        double lo = fmin([c minValue], [c maxValue]), hi = fmax([c minValue], [c maxValue]);
        v = isnan(v) ? lo : fmin(fmax(v, lo), hi);
        [c setObjectValue:@(v)];
    }
    [super setObjectValue:@(v)];
}
- (double)doubleValue { return [[super objectValue] doubleValue]; }
- (float)floatValue { return (float)[self doubleValue]; }
- (int)intValue { return (int)[self doubleValue]; }
- (NSInteger)integerValue { return (NSInteger)[self doubleValue]; }
- (NSString *)stringValue { return [[super objectValue] stringValue]; }
- (void)setStringValue:(NSString *)s { [self setDoubleValue:[s doubleValue]]; }

/* ---- the mouse and the keyboard (when editable) ---- */

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder
{
    return [self isEnabled] && [self isEditable] && [NSApp isFullKeyboardAccessEnabled];
}
- (void)_userSet:(double)v sendAction:(BOOL)send
{
    double before = [self doubleValue];
    [self setDoubleValue:v];
    if ([self doubleValue] != before)
        ABindingsPush(self, NO);
    if (send)
        [self sendAction:[self action] to:[self target]];
}
- (void)_trackTo:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    [self _userSet:[[self _levelCell] _valueAt:p inFrame:[self bounds] flipped:[self isFlipped]]
        sendAction:[self isContinuous]];
}
- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled] || ![self isEditable])
        return;
    _tracking = YES;
    [self _levelCell]->_tracking = YES;
    [self _trackTo:event];
}
- (void)mouseDragged:(NSEvent *)event
{
    if (_tracking)
        [self _trackTo:event];
}
- (void)mouseUp:(NSEvent *)event
{
    if (!_tracking)
        return;
    _tracking = NO;
    [self _levelCell]->_tracking = NO;
    [self setNeedsDisplay:YES];
    [self sendAction:[self action] to:[self target]];
}
- (double)_keyStep
{
    NSLevelIndicatorCell *c = [self _levelCell];
    NSLevelIndicatorStyle s = [c levelIndicatorStyle];
    if (s == NSLevelIndicatorStyleRating || s == NSLevelIndicatorStyleDiscreteCapacity)
        return 1;
    return fabs([c maxValue] - [c minValue]) / 20;
}
- (void)keyDown:(NSEvent *)event
{
    if ([self isEnabled] && [self isEditable])
        [self interpretKeyEvents:@[ event ]];
    else
        [super keyDown:event];
}
- (void)moveRight:(id)sender { [self _userSet:[self doubleValue] + [self _keyStep] sendAction:YES]; }
- (void)moveLeft:(id)sender { [self _userSet:[self doubleValue] - [self _keyStep] sendAction:YES]; }
- (void)moveUp:(id)sender { [self moveRight:sender]; }
- (void)moveDown:(id)sender { [self moveLeft:sender]; }
- (void)doCommandBySelector:(SEL)sel
{
    if ([self respondsToSelector:sel] && (sel == @selector(moveRight:) || sel == @selector(moveLeft:) ||
                                          sel == @selector(moveUp:) || sel == @selector(moveDown:)))
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
}
- (void)insertText:(id)string {}

/* ---- drawing ---- */

- (NSSize)intrinsicContentSize { return [[self cell] cellSize]; }
- (void)drawRect:(NSRect)dirty
{
    NSCell *cell = [self cell];
    [cell setEnabled:[self isEnabled]];
    [cell setControlView:self];
    [cell drawWithFrame:[self bounds] inView:self];
}
@end
