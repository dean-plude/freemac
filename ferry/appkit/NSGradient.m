/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSGradient and NSShadow, written from Apple's public
 * documentation. A gradient is a list of colours at locations from 0 to 1,
 * drawn with Core Graphics' linear and radial gradients in the current
 * graphics context: along a line, between two circles, or filling a
 * rectangle or a path at an angle or from a centre. A shadow is an offset,
 * a blur radius and a colour that, once set, apply to what is drawn next;
 * Ferry's Core Graphics doesn't draw shadows yet, so it says so once, and
 * a shadow given as a text attribute is kept but not drawn. Six of the
 * nine apps docs/ferry-compat.md follows draw with these classes. Built
 * without ARC. */
#import "AInternal.h"

NSAttributedStringKey const NSShadowAttributeName = @"NSShadow";

/* ---- NSGradient --------------------------------------------------------------------- */

@implementation NSGradient {
    NSArray *_colors;    /* NSColor, in order of location */
    CGFloat *_locations;
    NSInteger _count;
}

/* Keeps the stops sorted by location (a stable sort, so equal locations
 * keep the order they were given in), each location held to 0...1. */
- (instancetype)_initWithColors:(NSArray *)colors locations:(const CGFloat *)locations
{
    if (!(self = [super init]))
        return nil;
    NSInteger n = [colors count];
    if (n < 1) {
        [self release];
        return nil;
    }
    NSInteger order[n];
    CGFloat at[n];
    for (NSInteger i = 0; i < n; i++) {
        order[i] = i;
        at[i] = locations ? fmin(fmax(locations[i], 0), 1) : (n > 1 ? (CGFloat)i / (n - 1) : 0);
    }
    for (NSInteger i = 1; i < n; i++)
        for (NSInteger j = i; j > 0 && at[order[j - 1]] > at[order[j]]; j--) {
            NSInteger t = order[j];
            order[j] = order[j - 1];
            order[j - 1] = t;
        }
    NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:n];
    _locations = malloc(sizeof(CGFloat) * n);
    for (NSInteger i = 0; i < n; i++) {
        id c = [colors objectAtIndex:order[i]];
        [sorted addObject:[c isKindOfClass:[NSColor class]] ? c : [NSColor blackColor]];
        _locations[i] = at[order[i]];
    }
    _colors = [sorted copy];
    _count = n;
    return self;
}
- (instancetype)init { return [self initWithColors:@[]]; }
- (instancetype)initWithStartingColor:(NSColor *)start endingColor:(NSColor *)end
{
    if (!start || !end) {
        [self release];
        return nil;
    }
    return [self _initWithColors:@[ start, end ] locations:NULL];
}
- (instancetype)initWithColors:(NSArray *)colors { return [self _initWithColors:colors locations:NULL]; }
- (instancetype)initWithColors:(NSArray *)colors atLocations:(const CGFloat *)locations colorSpace:(id)space
{
    return [self _initWithColors:colors locations:locations];
}
/* firstColor, then a location, then colour and location pairs, ending in nil. */
- (instancetype)initWithColorsAndLocations:(NSColor *)firstColor, ...
{
    if (!firstColor) {
        [self release];
        return nil;
    }
    NSMutableArray *colors = [NSMutableArray arrayWithObject:firstColor];
    NSInteger cap = 8;
    CGFloat *at = malloc(sizeof(CGFloat) * cap);
    va_list ap;
    va_start(ap, firstColor);
    at[0] = (CGFloat)va_arg(ap, double);
    for (;;) {
        id c = va_arg(ap, id);
        if (!c)
            break;
        if ((NSInteger)[colors count] == cap)
            at = realloc(at, sizeof(CGFloat) * (cap *= 2));
        at[[colors count]] = (CGFloat)va_arg(ap, double);
        [colors addObject:c];
    }
    va_end(ap);
    self = [self _initWithColors:colors locations:at];
    free(at);
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSArray *colors = [coder decodeObjectForKey:@"NSColors"];
    NSArray *locations = [coder decodeObjectForKey:@"NSLocations"];
    if (![colors isKindOfClass:[NSArray class]] || ![locations isKindOfClass:[NSArray class]] ||
        [locations count] != [colors count])
        return [self _initWithColors:[colors isKindOfClass:[NSArray class]] ? colors : @[] locations:NULL];
    CGFloat at[[locations count] + 1];
    for (NSUInteger i = 0; i < [locations count]; i++)
        at[i] = [[locations objectAtIndex:i] doubleValue];
    return [self _initWithColors:colors locations:at];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    NSMutableArray *locations = [NSMutableArray array];
    for (NSInteger i = 0; i < _count; i++)
        [locations addObject:@(_locations[i])];
    [coder encodeObject:_colors forKey:@"NSColors"];
    [coder encodeObject:locations forKey:@"NSLocations"];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; } /* gradients don't change */
- (void)dealloc
{
    [_colors release];
    free(_locations);
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSGradient %p: %ld colour stops>", self, (long)_count];
}

- (id)colorSpace { return nil; }
- (NSInteger)numberOfColorStops { return _count; }
- (void)getColor:(NSColor **)color location:(CGFloat *)location atIndex:(NSInteger)index
{
    if (index < 0 || index >= _count)
        [NSException raise:NSRangeException format:@"-[NSGradient getColor:location:atIndex:]: index %ld beyond "
                                                   @"bounds %ld", (long)index, (long)_count];
    if (color)
        *color = [_colors objectAtIndex:index];
    if (location)
        *location = _locations[index];
}

static void components(NSColor *c, CGFloat out[4])
{
    out[0] = out[1] = out[2] = 0;
    out[3] = 1;
    [c getRed:&out[0] green:&out[1] blue:&out[2] alpha:&out[3]];
}

/* Between two stops the colour is mixed in proportion; before the first and
 * after the last it is that stop's colour. */
- (NSColor *)interpolatedColorAtLocation:(CGFloat)location
{
    if (location <= _locations[0])
        return [_colors objectAtIndex:0];
    for (NSInteger i = 1; i < _count; i++) {
        if (location > _locations[i])
            continue;
        CGFloat span = _locations[i] - _locations[i - 1];
        CGFloat f = span > 0 ? (location - _locations[i - 1]) / span : 1;
        CGFloat a[4], b[4];
        components([_colors objectAtIndex:i - 1], a);
        components([_colors objectAtIndex:i], b);
        return [NSColor colorWithSRGBRed:a[0] + (b[0] - a[0]) * f green:a[1] + (b[1] - a[1]) * f
                                    blue:a[2] + (b[2] - a[2]) * f alpha:a[3] + (b[3] - a[3]) * f];
    }
    return [_colors lastObject];
}

/* ---- drawing ---------------------------------------------------------------------- */

static CGContextRef current_cg(void) { return [[NSGraphicsContext currentContext] CGContext]; }

/* A Core Graphics gradient of these stops; one stop draws as a solid colour. */
- (CGGradientRef)_CGGradient
{
    NSInteger n = _count > 1 ? _count : 2;
    CGFloat comps[n * 4], at[n];
    for (NSInteger i = 0; i < n; i++) {
        NSInteger k = _count > 1 ? i : 0;
        components([_colors objectAtIndex:k], &comps[i * 4]);
        at[i] = _count > 1 ? _locations[k] : i;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(space, comps, at, n);
    CGColorSpaceRelease(space);
    return g;
}

- (void)drawFromPoint:(NSPoint)start toPoint:(NSPoint)end options:(NSGradientDrawingOptions)options
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    CGGradientRef g = [self _CGGradient];
    CGContextDrawLinearGradient(cg, g, start, end, (CGGradientDrawingOptions)options);
    CGGradientRelease(g);
}

- (void)drawFromCenter:(NSPoint)startCenter radius:(CGFloat)startRadius toCenter:(NSPoint)endCenter
                radius:(CGFloat)endRadius options:(NSGradientDrawingOptions)options
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    CGGradientRef g = [self _CGGradient];
    CGContextDrawRadialGradient(cg, g, startCenter, startRadius, endCenter, endRadius,
                                (CGGradientDrawingOptions)options);
    CGGradientRelease(g);
}

/* Along a line through the rectangle's centre at the angle (counter-clockwise
 * from the x axis, in degrees), long enough that the first and last colours
 * reach two opposite corners. */
static void line_through(NSRect r, CGFloat angle, NSPoint *start, NSPoint *end)
{
    CGFloat a = angle * M_PI / 180, dx = cos(a), dy = sin(a);
    /* whole numbers of degrees land exactly on the axes */
    if (fabs(dx) < 1e-12)
        dx = 0;
    if (fabs(dy) < 1e-12)
        dy = 0;
    CGFloat half = fabs(r.size.width / 2 * dx) + fabs(r.size.height / 2 * dy);
    NSPoint c = NSMakePoint(NSMidX(r), NSMidY(r));
    *start = NSMakePoint(c.x - dx * half, c.y - dy * half);
    *end = NSMakePoint(c.x + dx * half, c.y + dy * half);
}

- (void)_drawClippedTo:(NSBezierPath *)path inRect:(NSRect)r angle:(CGFloat)angle
{
    CGContextRef cg = current_cg();
    if (!cg || r.size.width <= 0 || r.size.height <= 0)
        return;
    NSPoint start, end;
    line_through(r, angle, &start, &end);
    CGContextSaveGState(cg);
    if (path)
        [path addClip];
    else
        CGContextClipToRect(cg, r);
    [self drawFromPoint:start toPoint:end
                options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
    CGContextRestoreGState(cg);
}
- (void)drawInRect:(NSRect)rect angle:(CGFloat)angle { [self _drawClippedTo:nil inRect:rect angle:angle]; }
- (void)drawInBezierPath:(NSBezierPath *)path angle:(CGFloat)angle
{
    if (path && ![path isEmpty])
        [self _drawClippedTo:path inRect:[path bounds] angle:angle];
}

/* From a point at the rectangle's centre to the smallest circle that covers
 * the rectangle, its centre moved by the relative position (-1 to 1 on each
 * axis, from the centre to an edge). */
- (void)_drawClippedTo:(NSBezierPath *)path inRect:(NSRect)r relativeCenterPosition:(NSPoint)rel
{
    CGContextRef cg = current_cg();
    if (!cg || r.size.width <= 0 || r.size.height <= 0)
        return;
    if (rel.x < -1 || rel.x > 1 || rel.y < -1 || rel.y > 1)
        [NSException raise:NSInvalidArgumentException
                    format:@"NSGradient: relativeCenterPosition (%g, %g) is outside -1...1", rel.x, rel.y];
    NSPoint c = NSMakePoint(NSMidX(r), NSMidY(r));
    NSPoint e = NSMakePoint(c.x + rel.x * r.size.width / 2, c.y + rel.y * r.size.height / 2);
    CGFloat radius = 0;
    for (int corner = 0; corner < 4; corner++) {
        CGFloat x = corner & 1 ? NSMaxX(r) : NSMinX(r), y = corner & 2 ? NSMaxY(r) : NSMinY(r);
        radius = fmax(radius, hypot(x - e.x, y - e.y));
    }
    CGContextSaveGState(cg);
    if (path)
        [path addClip];
    else
        CGContextClipToRect(cg, r);
    [self drawFromCenter:c radius:0 toCenter:e radius:radius options:NSGradientDrawsAfterEndingLocation];
    CGContextRestoreGState(cg);
}
- (void)drawInRect:(NSRect)rect relativeCenterPosition:(NSPoint)center
{
    [self _drawClippedTo:nil inRect:rect relativeCenterPosition:center];
}
- (void)drawInBezierPath:(NSBezierPath *)path relativeCenterPosition:(NSPoint)center
{
    if (path && ![path isEmpty])
        [self _drawClippedTo:path inRect:[path bounds] relativeCenterPosition:center];
}
@end

/* ---- NSShadow ----------------------------------------------------------------------- */

@implementation NSShadow {
    NSSize _offset;
    CGFloat _blur;
    NSColor *_color;
}
- (instancetype)init
{
    if ((self = [super init]))
        _color = [[NSColor colorWithCalibratedWhite:0 alpha:1.0 / 3] retain];
    return self;
}
/* The keys a nib's shadows are written with, as published descriptions of
 * the format give them. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _offset = NSMakeSize([coder decodeDoubleForKey:@"NSShadowHoriz"], [coder decodeDoubleForKey:@"NSShadowVert"]);
        _blur = [coder decodeDoubleForKey:@"NSShadowBlurRadius"];
        if ([coder containsValueForKey:@"NSShadowColor"]) {
            id c = [coder decodeObjectForKey:@"NSShadowColor"];
            [_color release];
            _color = [c isKindOfClass:[NSColor class]] ? [c retain] : nil;
        }
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_offset.width forKey:@"NSShadowHoriz"];
    [coder encodeDouble:_offset.height forKey:@"NSShadowVert"];
    [coder encodeDouble:_blur forKey:@"NSShadowBlurRadius"];
    if (_color)
        [coder encodeObject:_color forKey:@"NSShadowColor"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSShadow *s = [[NSShadow allocWithZone:zone] init];
    s->_offset = _offset;
    s->_blur = _blur;
    [s setShadowColor:_color];
    return s;
}
- (void)dealloc
{
    [_color release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSShadow class]])
        return NO;
    NSShadow *o = other;
    return NSEqualSizes(_offset, o->_offset) && _blur == o->_blur &&
           (_color == o->_color || [_color isEqual:o->_color]);
}
- (NSUInteger)hash { return (NSUInteger)(_offset.width * 31 + _offset.height * 7 + _blur) ^ [_color hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"NSShadow {%g, %g} blur = %g color = {%@}", _offset.width, _offset.height,
                                      _blur, _color];
}

- (NSSize)shadowOffset { return _offset; }
- (void)setShadowOffset:(NSSize)s { _offset = s; }
- (CGFloat)shadowBlurRadius { return _blur; }
- (void)setShadowBlurRadius:(CGFloat)b { _blur = fmax(0, b); }
- (NSColor *)shadowColor { return _color; }
- (void)setShadowColor:(NSColor *)c
{
    if (c == _color)
        return;
    [_color release];
    _color = [c copy];
}

/* Applies to what is drawn next, until another shadow is set or the
 * graphics state is restored; with no colour, no shadow is drawn. */
- (void)set
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    if (!_color)
        CGContextSetShadowWithColor(cg, CGSizeZero, 0, NULL);
    else
        CGContextSetShadowWithColor(cg, _offset, _blur, [_color CGColor]);
}
@end
