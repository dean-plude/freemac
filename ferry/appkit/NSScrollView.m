/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: scrolling. An NSScrollView holds an NSClipView, which
 * shows part of its document view by moving its own bounds origin, and
 * NSScrollers beside it. Scrollers take room beside the content (the
 * "legacy" style), which works the same with a mouse and a touchpad. The
 * clip view follows its document view's flippedness, as on a Mac, so a
 * flipped document starts at the top. */
#import "AInternal.h"

NSNotificationName const NSScrollViewWillStartLiveScrollNotification = @"NSScrollViewWillStartLiveScrollNotification";
NSNotificationName const NSScrollViewDidLiveScrollNotification = @"NSScrollViewDidLiveScrollNotification";
NSNotificationName const NSScrollViewDidEndLiveScrollNotification = @"NSScrollViewDidEndLiveScrollNotification";

static const CGFloat scroller_width = 15;

/* ---- NSScroller ----------------------------------------------------------------------- */

@implementation NSScroller {
    CGFloat _proportion;
    double _position;
    NSScrollerStyle _style;
    NSInteger _knobStyle;
    NSScrollerPart _hit;
    CGFloat _grab;   /* where in the knob the pointer took it */
}
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)size scrollerStyle:(NSScrollerStyle)style
{
    return size == NSControlSizeRegular || size == NSControlSizeLarge ? scroller_width : 11;
}
+ (CGFloat)scrollerWidth { return scroller_width; }
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)size { return [self scrollerWidthForControlSize:size scrollerStyle:0]; }
+ (NSScrollerStyle)preferredScrollerStyle { return NSScrollerStyleLegacy; }
+ (BOOL)isCompatibleWithOverlayScrollers { return YES; }

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        _proportion = 1;
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _proportion = [coder containsValueForKey:@"NSPercent"] ? [coder decodeDoubleForKey:@"NSPercent"] : 1;
        _position = [coder decodeDoubleForKey:@"NSCurValue"];
    }
    return self;
}
- (BOOL)_vertical { return [self frame].size.height >= [self frame].size.width; }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (CGFloat)knobProportion { return _proportion; }
- (void)setKnobProportion:(CGFloat)p
{
    _proportion = fmin(fmax(p, 0), 1);
    [self setNeedsDisplay:YES];
}
- (double)doubleValue { return _position; }
- (void)setDoubleValue:(double)v
{
    _position = fmin(fmax(v, 0), 1);
    [self setNeedsDisplay:YES];
}
- (float)floatValue { return (float)_position; }
- (void)setFloatValue:(float)v { [self setDoubleValue:v]; }
- (void)setFloatValue:(float)v knobProportion:(CGFloat)p
{
    [self setKnobProportion:p];
    [self setDoubleValue:v];
}
- (NSScrollerStyle)scrollerStyle { return _style; }
- (void)setScrollerStyle:(NSScrollerStyle)s { _style = s; }
- (NSInteger)knobStyle { return _knobStyle; }
- (void)setKnobStyle:(NSInteger)s { _knobStyle = s; }
- (NSScrollerPart)hitPart { return _hit; }
- (BOOL)isEnabled { return [super isEnabled] && _proportion < 1; }

- (NSRect)rectForPart:(NSScrollerPart)part
{
    NSRect b = [self bounds];
    BOOL v = [self _vertical];
    CGFloat length = v ? b.size.height : b.size.width;
    CGFloat knob = fmax(length * _proportion, fmin(20, length));
    CGFloat at = (length - knob) * _position;
    switch (part) {
    case NSScrollerKnob:
        if (_proportion >= 1)
            return NSZeroRect;
        return v ? NSMakeRect(0, at, b.size.width, knob) : NSMakeRect(at, 0, knob, b.size.height);
    case NSScrollerKnobSlot:
        return b;
    case NSScrollerDecrementPage:
        return v ? NSMakeRect(0, 0, b.size.width, at) : NSMakeRect(0, 0, at, b.size.height);
    case NSScrollerIncrementPage:
        return v ? NSMakeRect(0, at + knob, b.size.width, length - at - knob)
                 : NSMakeRect(at + knob, 0, length - at - knob, b.size.height);
    default:
        return NSZeroRect;
    }
}
- (NSScrollerPart)testPart:(NSPoint)p
{
    p = [self convertPoint:p fromView:nil];
    if (!NSMouseInRect(p, [self bounds], YES))
        return NSScrollerNoPart;
    for (NSScrollerPart part = NSScrollerDecrementPage; part <= NSScrollerIncrementPage; part++)
        if (NSMouseInRect(p, [self rectForPart:part], YES))
            return part;
    return NSScrollerKnobSlot;
}

- (void)drawKnobSlotInRect:(NSRect)rect highlight:(BOOL)flag
{
    [[NSColor colorWithCalibratedWhite:0.97 alpha:1] setFill];
    NSRectFill(rect);
    [[NSColor colorWithCalibratedWhite:0.88 alpha:1] setFill];
    NSRectFill([self _vertical] ? NSMakeRect(0, 0, 1, rect.size.height) : NSMakeRect(0, 0, rect.size.width, 1));
}
- (void)drawKnob
{
    NSRect k = [self rectForPart:NSScrollerKnob];
    if (NSIsEmptyRect(k))
        return;
    k = NSInsetRect(k, 3.5, 3.5);
    CGFloat r = fmin(k.size.width, k.size.height) / 2;
    AFillRoundedRect(k, r, [NSColor colorWithCalibratedWhite:_hit == NSScrollerKnob ? 0.45 : 0.62 alpha:1], nil);
}
- (void)drawRect:(NSRect)dirty
{
    [self drawKnobSlotInRect:[self bounds] highlight:NO];
    if ([self isEnabled])
        [self drawKnob];
}

- (CGFloat)_along:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    return [self _vertical] ? p.y : p.x;
}
- (void)_moveKnobTo:(CGFloat)start
{
    NSRect b = [self bounds], k = [self rectForPart:NSScrollerKnob];
    CGFloat room = ([self _vertical] ? b.size.height - k.size.height : b.size.width - k.size.width);
    [self setDoubleValue:room > 0 ? start / room : 0];
}
- (void)mouseDown:(NSEvent *)e
{
    if (![self isEnabled])
        return;
    _hit = [self testPart:[e locationInWindow]];
    NSRect k = [self rectForPart:NSScrollerKnob];
    CGFloat at = [self _along:e], knobStart = [self _vertical] ? k.origin.y : k.origin.x;
    if (_hit == NSScrollerKnob) {
        _grab = at - knobStart;
    } else if (_hit == NSScrollerDecrementPage || _hit == NSScrollerIncrementPage) {
        /* a click in the slot jumps there, as with "Jump to the spot that's clicked" */
        _grab = ([self _vertical] ? k.size.height : k.size.width) / 2;
        _hit = NSScrollerKnob;
        [self _moveKnobTo:at - _grab];
    }
    [self sendAction:[self action] to:[self target]];
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)e
{
    if (_hit != NSScrollerKnob)
        return;
    [self _moveKnobTo:[self _along:e] - _grab];
    [self sendAction:[self action] to:[self target]];
}
- (void)mouseUp:(NSEvent *)e
{
    _hit = NSScrollerNoPart;
    [self setNeedsDisplay:YES];
}
@end

/* ---- NSClipView ---------------------------------------------------------------------- */

@interface NSView (FerryClipViewSizing)
- (void)_clipViewResized:(NSClipView *)clip;
@end

@implementation NSClipView {
    NSView *_document;
    BOOL _drawsBackground, _copiesOnScroll, _adjustsInsets;
    NSColor *_background;
    NSEdgeInsets _insets;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _drawsBackground = _copiesOnScroll = YES;
        [self setAutoresizesSubviews:NO];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _copiesOnScroll = YES;
        [self setAutoresizesSubviews:NO];
        _drawsBackground = [coder containsValueForKey:@"NSDrawsBackground"] ? [coder decodeBoolForKey:@"NSDrawsBackground"] : YES;
        _background = [[coder decodeObjectForKey:@"NSBGColor"] retain];
        NSView *doc = [coder decodeObjectForKey:@"NSDocView"] ?: [[self subviews] firstObject];
        if (doc)
            [self setDocumentView:doc];
    }
    return self;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_document release];
    [_background release];
    [super dealloc];
}
- (BOOL)isFlipped { return _document ? [_document isFlipped] : NO; }
- (BOOL)isOpaque { return _drawsBackground; }
- (id)documentView { return _document; }
- (void)setDocumentView:(NSView *)view
{
    if (view == _document)
        return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_document) {
        [nc removeObserver:self name:NSViewFrameDidChangeNotification object:_document];
        if ([_document superview] == self)
            [_document removeFromSuperview];
        [_document release];
    }
    _document = [view retain];
    if (view) {
        if ([view superview] != self)
            [self addSubview:view];
        [view setPostsFrameChangedNotifications:YES];
        [nc addObserver:self selector:@selector(viewFrameChanged:) name:NSViewFrameDidChangeNotification object:view];
        if ([view respondsToSelector:@selector(_clipViewResized:)])
            [view _clipViewResized:self];
        NSRect f = [view frame];
        [self setBoundsOrigin:[self isFlipped] ? f.origin
                                               : NSMakePoint(f.origin.x, NSMaxY(f) - [self bounds].size.height)];
    }
    [self viewFrameChanged:nil];
}
- (void)willRemoveSubview:(NSView *)v
{
    [super willRemoveSubview:v];
    if (v == _document) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:v];
        [_document autorelease];
        _document = nil;
    }
}
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f
{
    _drawsBackground = f;
    [self setNeedsDisplay:YES];
}
- (NSColor *)backgroundColor { return _background ?: [NSColor controlBackgroundColor]; }
- (void)setBackgroundColor:(NSColor *)c
{
    [_background release];
    _background = [c copy];
    [self setNeedsDisplay:YES];
}
- (BOOL)copiesOnScroll { return _copiesOnScroll; }
- (void)setCopiesOnScroll:(BOOL)f { _copiesOnScroll = f; }
- (NSEdgeInsets)contentInsets { return _insets; }
- (void)setContentInsets:(NSEdgeInsets)i { _insets = i; }
- (BOOL)automaticallyAdjustsContentInsets { return _adjustsInsets; }
- (void)setAutomaticallyAdjustsContentInsets:(BOOL)f { _adjustsInsets = f; }

- (NSRect)documentRect
{
    if (!_document)
        return [self bounds];
    NSRect f = [_document frame];
    NSSize b = [self bounds].size;
    f.size.width = fmax(f.size.width, b.width);
    f.size.height = fmax(f.size.height, b.height);
    return f;
}
- (NSRect)documentVisibleRect
{
    if (!_document)
        return NSZeroRect;
    return [self convertRect:NSIntersectionRect([self bounds], [_document frame]) toView:_document];
}
- (NSRect)constrainBoundsRect:(NSRect)r
{
    if (!_document)
        return r;
    NSRect d = [_document frame];
    r.origin.x = fmax(d.origin.x, fmin(r.origin.x, NSMaxX(d) - r.size.width));
    if ([self isFlipped] || d.size.height >= r.size.height)
        r.origin.y = fmax(d.origin.y, fmin(r.origin.y, NSMaxY(d) - r.size.height));
    else /* a short, unflipped document sits at the top */
        r.origin.y = NSMaxY(d) - r.size.height;
    return r;
}
- (void)scrollToPoint:(NSPoint)p
{
    NSRect b = [self bounds];
    b.origin = p;
    b = [self constrainBoundsRect:b];
    if (NSEqualPoints(b.origin, [self bounds].origin))
        return;
    [self setBoundsOrigin:b.origin];
    [self setNeedsDisplay:YES];
    NSView *sv = [self superview];
    if ([sv respondsToSelector:@selector(reflectScrolledClipView:)])
        [(NSScrollView *)sv reflectScrolledClipView:self];
}
- (void)viewFrameChanged:(NSNotification *)note
{
    NSRect b = [self bounds], c = [self constrainBoundsRect:b];
    if (!NSEqualPoints(b.origin, c.origin))
        [self setBoundsOrigin:c.origin];
    [self setNeedsDisplay:YES];
    NSView *sv = [self superview];
    if ([sv respondsToSelector:@selector(reflectScrolledClipView:)])
        [(NSScrollView *)sv reflectScrolledClipView:self];
}
- (void)setFrameSize:(NSSize)size
{
    /* keep the top of the view where it is in an unflipped document */
    CGFloat top = NSMaxY([self bounds]);
    [super setFrameSize:size];
    if (_document && ![self isFlipped])
        [self setBoundsOrigin:NSMakePoint([self bounds].origin.x, top - size.height)];
    if ([_document respondsToSelector:@selector(_clipViewResized:)])
        [_document _clipViewResized:self];
    [self viewFrameChanged:nil];
}
- (BOOL)autoscroll:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSRect b = [self bounds];
    NSPoint o = b.origin;
    if (p.x < NSMinX(b)) o.x -= NSMinX(b) - p.x;
    if (p.x > NSMaxX(b)) o.x += p.x - NSMaxX(b);
    if (p.y < NSMinY(b)) o.y -= NSMinY(b) - p.y;
    if (p.y > NSMaxY(b)) o.y += p.y - NSMaxY(b);
    if (NSEqualPoints(o, b.origin))
        return NO;
    [self scrollToPoint:o];
    return YES;
}
- (void)drawRect:(NSRect)dirty
{
    if (_drawsBackground) {
        [[self backgroundColor] setFill];
        NSRectFill(dirty);
    }
}
@end

/* ---- NSScrollView --------------------------------------------------------------------- */

@implementation NSScrollView {
    NSClipView *_clip;
    NSScroller *_vertical, *_horizontal;
    BOOL _hasV, _hasH, _autohides, _drawsBackground;
    NSBorderType _border;
    CGFloat _lineV, _lineH, _pageV, _pageH, _magnification, _minMag, _maxMag;
    NSScrollerStyle _style;
    NSScrollElasticity _elasticV, _elasticH;
    BOOL _dynamic, _predominant, _magnifies, _adjustsInsets, _findBar, _rulerV, _rulerH, _rulersVisible;
    NSEdgeInsets _contentInsets, _scrollerInsets;
    NSInteger _findBarPosition;
    BOOL _tiling;
}

static NSSize border_size(NSBorderType t) { return t == NSNoBorder ? NSZeroSize : NSMakeSize(1, 1); }

+ (NSSize)contentSizeForFrameSize:(NSSize)s horizontalScrollerClass:(Class)h verticalScrollerClass:(Class)v
                       borderType:(NSBorderType)type controlSize:(NSControlSize)size
                    scrollerStyle:(NSScrollerStyle)style
{
    NSSize b = border_size(type);
    CGFloat w = [NSScroller scrollerWidthForControlSize:size scrollerStyle:style];
    return NSMakeSize(s.width - 2 * b.width - (v ? w : 0), s.height - 2 * b.height - (h ? w : 0));
}
+ (NSSize)frameSizeForContentSize:(NSSize)s horizontalScrollerClass:(Class)h verticalScrollerClass:(Class)v
                       borderType:(NSBorderType)type controlSize:(NSControlSize)size
                    scrollerStyle:(NSScrollerStyle)style
{
    NSSize b = border_size(type);
    CGFloat w = [NSScroller scrollerWidthForControlSize:size scrollerStyle:style];
    return NSMakeSize(s.width + 2 * b.width + (v ? w : 0), s.height + 2 * b.height + (h ? w : 0));
}
+ (NSSize)contentSizeForFrameSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v
                       borderType:(NSBorderType)type
{
    return [self contentSizeForFrameSize:s horizontalScrollerClass:h ? [NSScroller class] : Nil
                   verticalScrollerClass:v ? [NSScroller class] : Nil borderType:type controlSize:0 scrollerStyle:0];
}
+ (NSSize)frameSizeForContentSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v
                       borderType:(NSBorderType)type
{
    return [self frameSizeForContentSize:s horizontalScrollerClass:h ? [NSScroller class] : Nil
                   verticalScrollerClass:v ? [NSScroller class] : Nil borderType:type controlSize:0 scrollerStyle:0];
}

- (void)_setUp
{
    _lineV = _lineH = 10;
    _pageV = _pageH = 10;
    _magnification = _minMag = _maxMag = 1;
    _drawsBackground = _dynamic = _predominant = YES;
    [self setAutoresizesSubviews:NO];
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self _setUp];
        NSClipView *clip = [[NSClipView alloc] initWithFrame:[self bounds]];
        [self setContentView:clip];
        [clip release];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUp];
        /* a nib lists the clip view and scrollers among the subviews too */
        NSClipView *clip = [coder decodeObjectForKey:@"NSContentView"];
        NSScroller *v = [coder decodeObjectForKey:@"NSVScroller"], *h = [coder decodeObjectForKey:@"NSHScroller"];
        for (NSView *sub in [self subviews]) {
            if (!clip && [sub isKindOfClass:[NSClipView class]])
                clip = (NSClipView *)sub;
            else if ([sub isKindOfClass:[NSScroller class]]) {
                if ([(NSScroller *)sub _vertical] && !v)
                    v = (NSScroller *)sub;
                else if (!h && sub != v)
                    h = (NSScroller *)sub;
            }
        }
        _tiling = YES;
        if (clip)
            [self setContentView:clip];
        else {
            clip = [[[NSClipView alloc] initWithFrame:[self bounds]] autorelease];
            [self setContentView:clip];
        }
        if (v) {
            [self setVerticalScroller:v];
            _hasV = ![v isHidden];
        }
        if (h) {
            [self setHorizontalScroller:h];
            _hasH = ![h isHidden];
        }
        if ([coder containsValueForKey:@"NSsFlags"]) {
            /* the border is the flags' low two bits */
            _border = (NSBorderType)([coder decodeInt64ForKey:@"NSsFlags"] & 3);
        }
        if ([coder containsValueForKey:@"NSAutohidesScrollers"])
            _autohides = [coder decodeBoolForKey:@"NSAutohidesScrollers"];
        _tiling = NO;
        [self tile];
    }
    return self;
}
- (void)dealloc
{
    [_clip release];
    [_vertical release];
    [_horizontal release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return _drawsBackground; }

- (NSClipView *)contentView { return _clip; }
- (void)setContentView:(NSClipView *)clip
{
    if (clip == _clip)
        return;
    if ([_clip superview] == self)
        [_clip removeFromSuperview];
    [_clip release];
    _clip = [clip retain];
    if ([clip superview] != self)
        [self addSubview:clip positioned:NSWindowBelow relativeTo:nil];
    [self tile];
}
- (id)documentView { return [_clip documentView]; }
- (void)setDocumentView:(NSView *)v
{
    [_clip setDocumentView:v];
    [self tile];
}
- (NSSize)contentSize { return [_clip frame].size; }
- (NSRect)documentVisibleRect { return [_clip documentVisibleRect]; }

- (NSScroller *)_newScroller:(BOOL)vertical
{
    NSRect f = vertical ? NSMakeRect(0, 0, scroller_width, 100) : NSMakeRect(0, 0, 100, scroller_width);
    return [[NSScroller alloc] initWithFrame:f];
}
- (void)_adopt:(NSScroller *)s
{
    [s setTarget:self];
    [s setAction:@selector(_scrollerMoved:)];
    if ([s superview] != self)
        [self addSubview:s];
}
- (NSScroller *)verticalScroller
{
    if (!_vertical) {
        _vertical = [self _newScroller:YES];
        [self _adopt:_vertical];
        [_vertical setHidden:!_hasV];
    }
    return _vertical;
}
- (void)setVerticalScroller:(NSScroller *)s
{
    if (_vertical != s) {
        [_vertical removeFromSuperview];
        [_vertical release];
        _vertical = [s retain];
    }
    [self _adopt:s];
    [self tile];
}
- (NSScroller *)horizontalScroller
{
    if (!_horizontal) {
        _horizontal = [self _newScroller:NO];
        [self _adopt:_horizontal];
        [_horizontal setHidden:!_hasH];
    }
    return _horizontal;
}
- (void)setHorizontalScroller:(NSScroller *)s
{
    if (_horizontal != s) {
        [_horizontal removeFromSuperview];
        [_horizontal release];
        _horizontal = [s retain];
    }
    [self _adopt:s];
    [self tile];
}
- (BOOL)hasVerticalScroller { return _hasV; }
- (void)setHasVerticalScroller:(BOOL)f
{
    _hasV = f;
    if (f)
        [self verticalScroller];
    [self tile];
}
- (BOOL)hasHorizontalScroller { return _hasH; }
- (void)setHasHorizontalScroller:(BOOL)f
{
    _hasH = f;
    if (f)
        [self horizontalScroller];
    [self tile];
}
- (BOOL)autohidesScrollers { return _autohides; }
- (void)setAutohidesScrollers:(BOOL)f
{
    _autohides = f;
    [self tile];
}
- (NSBorderType)borderType { return _border; }
- (void)setBorderType:(NSBorderType)t
{
    _border = t;
    [self tile];
}
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f
{
    _drawsBackground = f;
    [_clip setDrawsBackground:f];
}
- (NSColor *)backgroundColor { return [_clip backgroundColor]; }
- (void)setBackgroundColor:(NSColor *)c { [_clip setBackgroundColor:c]; }
- (CGFloat)lineScroll { return _lineV; }
- (void)setLineScroll:(CGFloat)v { _lineV = _lineH = v; }
- (CGFloat)verticalLineScroll { return _lineV; }
- (void)setVerticalLineScroll:(CGFloat)v { _lineV = v; }
- (CGFloat)horizontalLineScroll { return _lineH; }
- (void)setHorizontalLineScroll:(CGFloat)v { _lineH = v; }
- (CGFloat)pageScroll { return _pageV; }
- (void)setPageScroll:(CGFloat)v { _pageV = _pageH = v; }
- (CGFloat)verticalPageScroll { return _pageV; }
- (void)setVerticalPageScroll:(CGFloat)v { _pageV = v; }
- (CGFloat)horizontalPageScroll { return _pageH; }
- (void)setHorizontalPageScroll:(CGFloat)v { _pageH = v; }
- (NSScrollerStyle)scrollerStyle { return _style; }
- (void)setScrollerStyle:(NSScrollerStyle)s { _style = s; } /* scrollers always take room */
- (NSScrollElasticity)verticalScrollElasticity { return _elasticV; }
- (void)setVerticalScrollElasticity:(NSScrollElasticity)e { _elasticV = e; }
- (NSScrollElasticity)horizontalScrollElasticity { return _elasticH; }
- (void)setHorizontalScrollElasticity:(NSScrollElasticity)e { _elasticH = e; }
- (BOOL)scrollsDynamically { return _dynamic; }
- (void)setScrollsDynamically:(BOOL)f { _dynamic = f; }
- (BOOL)usesPredominantAxisScrolling { return _predominant; }
- (void)setUsesPredominantAxisScrolling:(BOOL)f { _predominant = f; }
- (BOOL)allowsMagnification { return _magnifies; }
- (void)setAllowsMagnification:(BOOL)f { _magnifies = f; }
- (CGFloat)magnification { return _magnification; }
- (void)setMagnification:(CGFloat)m { _magnification = m; } /* not applied */
- (CGFloat)minMagnification { return _minMag; }
- (void)setMinMagnification:(CGFloat)m { _minMag = m; }
- (CGFloat)maxMagnification { return _maxMag; }
- (void)setMaxMagnification:(CGFloat)m { _maxMag = m; }
- (NSEdgeInsets)contentInsets { return _contentInsets; }
- (void)setContentInsets:(NSEdgeInsets)i { _contentInsets = i; }
- (NSEdgeInsets)scrollerInsets { return _scrollerInsets; }
- (void)setScrollerInsets:(NSEdgeInsets)i { _scrollerInsets = i; }
- (BOOL)automaticallyAdjustsContentInsets { return _adjustsInsets; }
- (void)setAutomaticallyAdjustsContentInsets:(BOOL)f { _adjustsInsets = f; }
- (BOOL)isFindBarVisible { return _findBar; }
- (void)setFindBarVisible:(BOOL)f { _findBar = f; }
- (NSInteger)findBarPosition { return _findBarPosition; }
- (void)setFindBarPosition:(NSInteger)p { _findBarPosition = p; }
- (BOOL)hasVerticalRuler { return _rulerV; }
- (void)setHasVerticalRuler:(BOOL)f { _rulerV = f; }
- (BOOL)hasHorizontalRuler { return _rulerH; }
- (void)setHasHorizontalRuler:(BOOL)f { _rulerH = f; }
- (BOOL)rulersVisible { return _rulersVisible; }
- (void)setRulersVisible:(BOOL)f { _rulersVisible = f; }
- (void)flashScrollers {}

/* Which scrollers show inside room r. With autohiding, a scroller shows
 * only while the document is larger than the room left for it. */
- (void)_wantsVertical:(BOOL *)v horizontal:(BOOL *)h inside:(NSRect)r
{
    *v = _hasV;
    *h = _hasH;
    if (!_autohides)
        return;
    NSSize doc = [[_clip documentView] frame].size;
    *v = _hasV && doc.height > r.size.height;
    *h = _hasH && doc.width > r.size.width - (*v ? scroller_width : 0);
    *v = _hasV && doc.height > r.size.height - (*h ? scroller_width : 0);
}

/* Lays out the clip view and the scrollers. With autohiding, a scroller
 * shows only while the document is larger than the room for it. */
- (void)tile
{
    if (_tiling || !_clip)
        return;
    _tiling = YES;
    NSRect b = NSInsetRect([self bounds], border_size(_border).width, border_size(_border).height);
    BOOL v, h;
    [self _wantsVertical:&v horizontal:&h inside:b];
    NSRect content = b;
    if (v)
        content.size.width -= scroller_width;
    if (h)
        content.size.height -= scroller_width;
    content.size.width = fmax(content.size.width, 0);
    content.size.height = fmax(content.size.height, 0);
    if (!NSEqualRects([_clip frame], content)) {
        [_clip setFrameOrigin:content.origin];
        [_clip setFrameSize:content.size];
    }
    if (_vertical) {
        [_vertical setHidden:!v];
        [_vertical setFrame:NSMakeRect(NSMaxX(content), b.origin.y, scroller_width, content.size.height)];
    }
    if (_horizontal) {
        [_horizontal setHidden:!h];
        [_horizontal setFrame:NSMakeRect(b.origin.x, NSMaxY(content), content.size.width, scroller_width)];
    }
    _tiling = NO;
    [self reflectScrolledClipView:_clip];
    [self setNeedsDisplay:YES];
}
- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self tile];
}
- (void)resizeSubviewsWithOldSize:(NSSize)old { [self tile]; }

/* Scroller positions run from the top (vertical) and the left (horizontal). */
- (void)reflectScrolledClipView:(NSClipView *)clip
{
    if (clip != _clip || _tiling)
        return;
    NSRect d = [_clip documentView] ? [[_clip documentView] frame] : NSZeroRect, b = [_clip bounds];
    if (_autohides && [_clip documentView]) {
        BOOL v, h;
        NSRect r = NSInsetRect([self bounds], border_size(_border).width, border_size(_border).height);
        [self _wantsVertical:&v horizontal:&h inside:r];
        if (v != (_vertical && ![_vertical isHidden]) || h != (_horizontal && ![_horizontal isHidden])) {
            [self tile];
            return;
        }
    }
    if (_vertical) {
        CGFloat room = d.size.height - b.size.height;
        double pos = room > 0 ? ([_clip isFlipped] ? (b.origin.y - d.origin.y) / room
                                                    : (NSMaxY(d) - NSMaxY(b)) / room)
                              : 0;
        [_vertical setFloatValue:(float)pos knobProportion:d.size.height > 0 ? b.size.height / d.size.height : 1];
    }
    if (_horizontal) {
        CGFloat room = d.size.width - b.size.width;
        [_horizontal setFloatValue:room > 0 ? (float)((b.origin.x - d.origin.x) / room) : 0
                    knobProportion:d.size.width > 0 ? b.size.width / d.size.width : 1];
    }
}
- (void)_scrollerMoved:(NSScroller *)s
{
    NSRect d = [[_clip documentView] frame], b = [_clip bounds];
    NSPoint o = b.origin;
    if (s == _vertical) {
        CGFloat room = fmax(d.size.height - b.size.height, 0);
        o.y = [_clip isFlipped] ? d.origin.y + room * [s doubleValue] : NSMaxY(d) - b.size.height - room * [s doubleValue];
    } else {
        o.x = d.origin.x + fmax(d.size.width - b.size.width, 0) * [s doubleValue];
    }
    [_clip scrollToPoint:o];
}
/* Wheel and touchpad: positive deltas scroll toward the top and left. */
- (void)scrollWheel:(NSEvent *)e
{
    if (![_clip documentView]) {
        [super scrollWheel:e];
        return;
    }
    BOOL precise = [e hasPreciseScrollingDeltas];
    CGFloat dx = [e scrollingDeltaX] * (precise ? 1 : _lineH * 4);
    CGFloat dy = [e scrollingDeltaY] * (precise ? 1 : _lineV * 4);
    if (!_hasH)
        dx = 0;
    NSPoint o = [_clip bounds].origin;
    o.x -= dx;
    o.y += [_clip isFlipped] ? -dy : dy;
    [_clip scrollToPoint:o];
}
- (void)drawRect:(NSRect)dirty
{
    if (_border != NSNoBorder) {
        [[NSColor colorWithCalibratedWhite:_border == NSLineBorder ? 0.3 : 0.72 alpha:1] setFill];
        NSFrameRect([self bounds]);
    }
}
@end

/* ---- scrolling from any view --------------------------------------------------------- */

@implementation NSView (NSScrolling)
- (NSScrollView *)enclosingScrollView
{
    for (NSView *v = [self superview]; v; v = [v superview])
        if ([v isKindOfClass:[NSScrollView class]])
            return (NSScrollView *)v;
    return nil;
}
- (NSClipView *)_enclosingClipView
{
    for (NSView *v = self; v; v = [v superview])
        if ([[v superview] isKindOfClass:[NSClipView class]] && [(NSClipView *)[v superview] documentView] == v)
            return (NSClipView *)[v superview];
    return nil;
}
- (BOOL)scrollRectToVisible:(NSRect)r
{
    NSClipView *clip = [self _enclosingClipView];
    if (!clip)
        return NO;
    r = [self convertRect:r toView:clip];
    NSRect b = [clip bounds];
    NSPoint o = b.origin;
    if (NSMinX(r) < NSMinX(b))
        o.x = NSMinX(r);
    else if (NSMaxX(r) > NSMaxX(b))
        o.x = fmin(NSMinX(r), NSMaxX(r) - b.size.width);
    if (NSMinY(r) < NSMinY(b))
        o.y = NSMinY(r);
    else if (NSMaxY(r) > NSMaxY(b))
        o.y = fmin(NSMinY(r), NSMaxY(r) - b.size.height);
    if (NSEqualPoints(o, b.origin))
        return NO;
    [clip scrollToPoint:o];
    return YES;
}
- (BOOL)autoscroll:(NSEvent *)e
{
    NSClipView *clip = [self _enclosingClipView];
    return clip ? [clip autoscroll:e] : NO;
}
- (NSRect)adjustScroll:(NSRect)proposed { return proposed; }
@end
