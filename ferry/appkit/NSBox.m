/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSProgressIndicator (a bar, or a spinner) and NSBox (a
 * titled group, a separator line or a custom filled box). Both draw
 * themselves; an indeterminate bar and a spinner animate on a timer while
 * started. */
#import "AInternal.h"

/* ---- NSProgressIndicator ------------------------------------------------------------- */

@implementation NSProgressIndicator {
    double _value, _min, _max;
    BOOL _indeterminate, _whenStopped, _threaded, _bezeled, _animating;
    NSProgressIndicatorStyle _style;
    NSControlSize _size;
    NSTimer *_timer;
    CGFloat _phase;
}
- (void)_setUp
{
    _max = 100;
    _indeterminate = _whenStopped = _bezeled = _threaded = YES;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setUp];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUp];
        if ([coder containsValueForKey:@"NSMaxValue"])
            _max = [coder decodeDoubleForKey:@"NSMaxValue"];
        _min = [coder decodeDoubleForKey:@"NSMinValue"];
        _value = [coder decodeDoubleForKey:@"NSValue"];
        if ([coder containsValueForKey:@"NSpiFlags"]) {
            /* 0x2: indeterminate, 0x1000: spinning, 0x2000: hidden when stopped */
            int f = [coder decodeIntForKey:@"NSpiFlags"];
            _indeterminate = (f & 2) != 0;
            _style = (f & 0x1000) ? NSProgressIndicatorStyleSpinning : NSProgressIndicatorStyleBar;
            _whenStopped = !(f & 0x2000);
        }
    }
    return self;
}
- (void)dealloc
{
    [_timer invalidate];
    [_timer release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)v
{
    _value = fmin(fmax(v, _min), _max);
    [self setNeedsDisplay:YES];
}
- (double)minValue { return _min; }
- (void)setMinValue:(double)v
{
    _min = v;
    [self setNeedsDisplay:YES];
}
- (double)maxValue { return _max; }
- (void)setMaxValue:(double)v
{
    _max = v;
    [self setNeedsDisplay:YES];
}
- (void)incrementBy:(double)d { [self setDoubleValue:_value + d]; }
- (BOOL)isIndeterminate { return _indeterminate; }
- (void)setIndeterminate:(BOOL)f
{
    _indeterminate = f;
    [self setNeedsDisplay:YES];
}
- (NSProgressIndicatorStyle)style { return _style; }
- (void)setStyle:(NSProgressIndicatorStyle)s
{
    _style = s;
    [self setNeedsDisplay:YES];
}
- (NSControlSize)controlSize { return _size; }
- (void)setControlSize:(NSControlSize)s { _size = s; }
- (BOOL)isDisplayedWhenStopped { return _whenStopped; }
- (BOOL)displayedWhenStopped { return _whenStopped; }
- (void)setDisplayedWhenStopped:(BOOL)f
{
    _whenStopped = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)usesThreadedAnimation { return _threaded; }
- (void)setUsesThreadedAnimation:(BOOL)f { _threaded = f; }
- (BOOL)isBezeled { return _bezeled; }
- (BOOL)bezeled { return _bezeled; }
- (void)setBezeled:(BOOL)f { _bezeled = f; }
- (void)_tick:(NSTimer *)t
{
    _phase += 1;
    [self setNeedsDisplay:YES];
}
- (void)startAnimation:(id)sender
{
    if (_animating)
        return;
    _animating = YES;
    if (_indeterminate || _style == NSProgressIndicatorStyleSpinning) {
        _timer = [[NSTimer scheduledTimerWithTimeInterval:1.0 / 12 target:self selector:@selector(_tick:) userInfo:nil
                                                  repeats:YES] retain];
    }
    [self setNeedsDisplay:YES];
}
- (void)stopAnimation:(id)sender
{
    _animating = NO;
    [_timer invalidate];
    [_timer release];
    _timer = nil;
    [self setNeedsDisplay:YES];
}
- (void)sizeToFit
{
    NSSize s = _style == NSProgressIndicatorStyleSpinning ? NSMakeSize(32, 32) : NSMakeSize([self frame].size.width, 20);
    if (_size == NSControlSizeSmall)
        s = _style == NSProgressIndicatorStyleSpinning ? NSMakeSize(16, 16) : NSMakeSize(s.width, 12);
    [self setFrameSize:s];
}
- (void)drawRect:(NSRect)dirty
{
    if (!_animating && !_whenStopped)
        return;
    NSRect b = [self bounds];
    if (_style == NSProgressIndicatorStyleSpinning) {
        CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
        CGFloat r = fmin(b.size.width, b.size.height) / 2;
        CGContextSaveGState(cg);
        CGContextTranslateCTM(cg, NSMidX(b), NSMidY(b));
        CGContextSetLineCap(cg, kCGLineCapRound);
        CGContextSetLineWidth(cg, fmax(r / 6, 1.5));
        for (int i = 0; i < 12; i++) {
            int step = ((int)_phase + i) % 12;
            CGFloat alpha = _animating ? 0.15 + 0.7 * step / 11.0 : 0.3;
            CGContextSetRGBStrokeColor(cg, 0.25, 0.25, 0.25, alpha);
            CGFloat a = i * M_PI / 6;
            CGContextMoveToPoint(cg, cos(a) * r * 0.5, sin(a) * r * 0.5);
            CGContextAddLineToPoint(cg, cos(a) * r * 0.92, sin(a) * r * 0.92);
            CGContextStrokePath(cg);
        }
        CGContextRestoreGState(cg);
        return;
    }
    CGFloat h = fmin(b.size.height, 6);
    NSRect track = NSMakeRect(1, (b.size.height - h) / 2, b.size.width - 2, h);
    AFillRoundedRect(track, h / 2, [NSColor colorWithCalibratedWhite:0.86 alpha:1], nil);
    NSColor *accent = [NSColor controlAccentColor];
    if (_indeterminate) {
        if (!_animating)
            return;
        CGFloat w = track.size.width / 4, x = fmod(_phase * 6, track.size.width + w) - w;
        CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
        CGContextSaveGState(cg);
        CGContextClipToRect(cg, track);
        AFillRoundedRect(NSMakeRect(track.origin.x + x, track.origin.y, w, h), h / 2, accent, nil);
        CGContextRestoreGState(cg);
        return;
    }
    double f = _max > _min ? (_value - _min) / (_max - _min) : 0;
    if (f > 0)
        AFillRoundedRect(NSMakeRect(track.origin.x, track.origin.y, fmax(track.size.width * f, h), h), h / 2, accent, nil);
}
@end

/* ---- NSBox ------------------------------------------------------------------------------ */

@implementation NSBox {
    NSBoxType _type;
    NSString *_title;
    NSFont *_titleFont;
    NSTitlePosition _position;
    BOOL _transparent;
    NSSize _margins;
    NSView *_content;
    NSColor *_fill, *_borderColor;
    CGFloat _borderWidth, _radius;
    NSBorderType _borderType;
}
- (void)_setUp
{
    _title = [@"Title" copy];
    _position = NSAtTop;
    _margins = NSMakeSize(5, 5);
    _borderWidth = 1;
    _borderType = NSBezelBorder;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self _setUp];
        NSView *v = [[NSView alloc] initWithFrame:[self _contentRect]];
        [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self setContentView:v];
        [v release];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUp];
        if ([coder containsValueForKey:@"NSBoxType"])
            _type = (NSBoxType)[coder decodeIntForKey:@"NSBoxType"];
        if ([coder containsValueForKey:@"NSTitlePosition"])
            _position = (NSTitlePosition)[coder decodeIntForKey:@"NSTitlePosition"];
        if ([coder containsValueForKey:@"NSTransparent"])
            _transparent = [coder decodeBoolForKey:@"NSTransparent"];
        if ([coder containsValueForKey:@"NSOffsets"])
            _margins = [coder decodeSizeForKey:@"NSOffsets"];
        id cell = [coder decodeObjectForKey:@"NSTitleCell"];
        if ([cell respondsToSelector:@selector(stringValue)]) {
            [_title release];
            _title = [[cell stringValue] copy];
        }
        NSView *content = [coder decodeObjectForKey:@"NSContentView"] ?: [[self subviews] firstObject];
        _content = [content retain];
        if (_content && [_content superview] != self)
            [self addSubview:_content];
        _fill = [[coder decodeObjectForKey:@"NSFillColor2"] retain];
        _borderColor = [[coder decodeObjectForKey:@"NSBorderColor2"] retain];
        if ([coder containsValueForKey:@"NSBorderWidth2"])
            _borderWidth = [coder decodeDoubleForKey:@"NSBorderWidth2"];
        if ([coder containsValueForKey:@"NSCornerRadius2"])
            _radius = [coder decodeDoubleForKey:@"NSCornerRadius2"];
    }
    return self;
}
- (void)dealloc
{
    [_title release];
    [_titleFont release];
    [_content release];
    [_fill release];
    [_borderColor release];
    [super dealloc];
}
- (BOOL)_hasTitle { return _type == NSBoxPrimary && _position != NSNoTitle && [_title length]; }
- (NSFont *)titleFont { return _titleFont ?: [NSFont systemFontOfSize:11]; }
- (void)setTitleFont:(NSFont *)f
{
    id wasTitleFont = _titleFont;
    _titleFont = [f retain];
    [wasTitleFont release];
    [self setNeedsDisplay:YES];
}
- (NSRect)titleRect
{
    if (![self _hasTitle])
        return NSZeroRect;
    NSSize s = [_title sizeWithAttributes:@{NSFontAttributeName : [self titleFont]}];
    NSRect b = [self bounds];
    return NSMakeRect(4, NSMaxY(b) - ceil(s.height), ceil(s.width) + 4, ceil(s.height));
}
- (NSRect)borderRect
{
    NSRect b = [self bounds];
    if ([self _hasTitle])
        b.size.height -= [self titleRect].size.height + 2;
    return b;
}
- (NSRect)_contentRect
{
    if (_type == NSBoxSeparator)
        return NSZeroRect;
    return NSInsetRect([self borderRect], _margins.width, _margins.height);
}
- (NSBoxType)boxType { return _type; }
- (void)setBoxType:(NSBoxType)t
{
    _type = t;
    [self setNeedsDisplay:YES];
}
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t
{
    id wasTitle = _title;
    _title = [t copy];
    [wasTitle release];
    [self setNeedsDisplay:YES];
}
- (NSTitlePosition)titlePosition { return _position; }
- (void)setTitlePosition:(NSTitlePosition)p
{
    _position = p;
    [self setNeedsDisplay:YES];
}
- (BOOL)isTransparent { return _transparent; }
- (void)setTransparent:(BOOL)f
{
    _transparent = f;
    [self setNeedsDisplay:YES];
}
- (NSSize)contentViewMargins { return _margins; }
- (void)setContentViewMargins:(NSSize)m
{
    _margins = m;
    [_content setFrame:[self _contentRect]];
}
- (id)contentView { return _content; }
- (void)setContentView:(NSView *)v
{
    if (v == _content)
        return;
    [_content removeFromSuperview];
    id wasContent = _content;
    _content = [v retain];
    [wasContent release];
    if (v) {
        [v setFrame:[self _contentRect]];
        [self addSubview:v];
    }
}
- (NSColor *)fillColor { return _fill ?: [NSColor clearColor]; }
- (void)setFillColor:(NSColor *)c
{
    id wasFill = _fill;
    _fill = [c copy];
    [wasFill release];
    [self setNeedsDisplay:YES];
}
- (NSColor *)borderColor { return _borderColor ?: [NSColor separatorColor]; }
- (void)setBorderColor:(NSColor *)c
{
    id wasBorderColor = _borderColor;
    _borderColor = [c copy];
    [wasBorderColor release];
    [self setNeedsDisplay:YES];
}
- (CGFloat)borderWidth { return _borderWidth; }
- (void)setBorderWidth:(CGFloat)w { _borderWidth = w; }
- (CGFloat)cornerRadius { return _radius; }
- (void)setCornerRadius:(CGFloat)r { _radius = r; }
- (NSBorderType)borderType { return _borderType; }
- (void)setBorderType:(NSBorderType)t { _borderType = t; }
- (void)setFrameFromContentFrame:(NSRect)f
{
    NSRect r = NSInsetRect(f, -_margins.width, -_margins.height);
    if ([self _hasTitle])
        r.size.height += [self titleRect].size.height + 2;
    [self setFrame:r];
}
- (void)sizeToFit
{
    NSRect u = NSZeroRect;
    for (NSView *v in [_content subviews])
        u = NSUnionRect(u, [v frame]);
    if (_content)
        [self setFrameFromContentFrame:[self convertRect:NSMakeRect(0, 0, NSMaxX(u), NSMaxY(u)) fromView:_content]];
}
- (void)resizeSubviewsWithOldSize:(NSSize)old
{
    [super resizeSubviewsWithOldSize:old];
    [_content setFrame:[self _contentRect]];
}
- (void)drawRect:(NSRect)dirty
{
    if (_transparent)
        return;
    NSRect b = [self bounds];
    if (_type == NSBoxSeparator) {
        [[NSColor separatorColor] setFill];
        NSRectFill(b.size.width >= b.size.height ? NSMakeRect(0, floor(NSMidY(b)), b.size.width, 1)
                                                 : NSMakeRect(floor(NSMidX(b)), 0, 1, b.size.height));
        return;
    }
    NSRect border = NSInsetRect([self borderRect], 0.5, 0.5);
    if (_type == NSBoxCustom) {
        AFillRoundedRect(border, _radius, [self fillColor], _borderWidth > 0 ? [self borderColor] : nil);
    } else {
        AFillRoundedRect(border, 5, [NSColor colorWithCalibratedWhite:0 alpha:0.04],
                         [NSColor colorWithCalibratedWhite:0 alpha:0.12]);
    }
    if ([self _hasTitle])
        [_title drawAtPoint:NSMakePoint(NSMinX([self titleRect]) + 2, NSMinY([self titleRect]))
             withAttributes:@{NSFontAttributeName : [self titleFont], NSForegroundColorAttributeName : [NSColor labelColor]}];
}
@end
