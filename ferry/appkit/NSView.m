/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSView. A view has a frame in its superview's coordinates
 * and bounds in its own; a flipped view's y axis runs down from the top.
 * Each view's coordinates map to its superview's by an affine transform
 * (see _transformToSuperview), which drawing, hit-testing and the convert
 * calls all use, so they agree. Windows draw their views into a backing
 * image (see NSWindow.m). */
#import "AInternal.h"

NSNotificationName const NSViewFrameDidChangeNotification = @"NSViewFrameDidChangeNotification";
NSNotificationName const NSViewBoundsDidChangeNotification = @"NSViewBoundsDidChangeNotification";

@implementation NSView {
    NSRect _frame, _bounds;
    NSView *_superview;             /* not retained */
    NSMutableArray *_subviews;
    NSWindow *_window;              /* not retained */
    BOOL _hidden, _needsDisplay, _autoresizes, _wantsLayer, _postsFrame, _postsBounds, _translates;
    NSAutoresizingMaskOptions _mask;
    NSView *_nextKeyView, *_previousKeyView;  /* not retained */
    CGFloat _alpha;
    NSString *_toolTip, *_identifier;
    NSFocusRingType _focusRing;
    BOOL _focusLocked;
    NSViewController *_viewController;   /* not retained */
    NSArray *_draggedTypes;
}

/* Drag and drop: the types a view takes (NSDragging.m does the rest). */
- (void)registerForDraggedTypes:(NSArray *)types
{
    NSMutableArray *all = [NSMutableArray arrayWithArray:_draggedTypes ?: @[]];
    for (NSString *t in types)
        if (![all containsObject:t])
            [all addObject:t];
    [_draggedTypes release];
    _draggedTypes = [all copy];
    [_window _enableDrops];
}
- (void)unregisterDraggedTypes
{
    [_draggedTypes release];
    _draggedTypes = nil;
}
- (NSArray *)registeredDraggedTypes { return _draggedTypes ?: @[]; }

/* Backing coordinates: the window's pixels (see NSWindow). */
- (NSRect)convertRectToBacking:(NSRect)r
{
    NSRect w = [self convertRect:r toView:nil];
    CGFloat s = _window ? [_window backingScaleFactor] : AScreenScale();
    return NSMakeRect(w.origin.x * s, w.origin.y * s, w.size.width * s, w.size.height * s);
}
- (NSRect)convertRectFromBacking:(NSRect)r
{
    CGFloat s = _window ? [_window backingScaleFactor] : AScreenScale();
    return [self convertRect:NSMakeRect(r.origin.x / s, r.origin.y / s, r.size.width / s, r.size.height / s)
                    fromView:nil];
}
- (NSPoint)convertPointToBacking:(NSPoint)p
{
    return [self convertRectToBacking:NSMakeRect(p.x, p.y, 0, 0)].origin;
}
- (NSPoint)convertPointFromBacking:(NSPoint)p
{
    return [self convertRectFromBacking:NSMakeRect(p.x, p.y, 0, 0)].origin;
}
- (NSSize)convertSizeToBacking:(NSSize)size
{
    CGFloat s = _window ? [_window backingScaleFactor] : AScreenScale();
    return NSMakeSize(size.width * s, size.height * s);
}
- (NSSize)convertSizeFromBacking:(NSSize)size
{
    CGFloat s = _window ? [_window backingScaleFactor] : AScreenScale();
    return NSMakeSize(size.width / s, size.height / s);
}
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)options
{
    NSRect inWindow = [self convertRect:r toView:nil];
    NSRect aligned = _window ? [_window backingAlignedRect:inWindow options:options] : inWindow;
    return [self convertRect:aligned fromView:nil];
}
- (void)viewDidChangeBackingProperties {}
- (void)_backingPropertiesChanged
{
    [self viewDidChangeBackingProperties];
    [self setNeedsDisplay:YES];
    for (NSView *v in _subviews)
        [v _backingPropertiesChanged];
}

/* A view controller comes between its view and whatever would follow the
 * view in the responder chain. */
- (void)setNextResponder:(NSResponder *)next
{
    if (_viewController && next != (NSResponder *)_viewController) {
        [_viewController setNextResponder:next];
        [super setNextResponder:_viewController];
    } else {
        [super setNextResponder:next];
    }
}
- (NSViewController *)_viewController { return _viewController; }
- (void)_setViewController:(NSViewController *)vc
{
    NSResponder *outer = _viewController ? [_viewController nextResponder] : [self nextResponder];
    [_viewController setNextResponder:nil];
    _viewController = vc;
    [self setNextResponder:outer];
}

- (instancetype)init { return [self initWithFrame:NSZeroRect]; }

static void view_setup(NSView *v, NSRect frame)
{
    v->_frame = frame;
    v->_bounds = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    v->_subviews = [[NSMutableArray alloc] init];
    v->_autoresizes = YES;
    v->_postsFrame = v->_postsBounds = YES;
    v->_translates = YES;
    v->_alpha = 1;
    v->_needsDisplay = YES;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super init]))
        view_setup(self, frame);
    return self;
}

/* From a nib: the frame, then the flags word "NSvFlags" (the autoresizing
 * mask in its low six bits, 0x100 for autoresizing subviews, the top bit
 * for hidden), the subviews back to front and the next key view. */
NSRect AViewFrameFromCoder(NSCoder *c)
{
    if ([c containsValueForKey:@"NSFrame"])
        return [c decodeRectForKey:@"NSFrame"];
    NSRect r = NSZeroRect;
    r.size = [c decodeSizeForKey:@"NSFrameSize"];
    return r;
}

void AViewDecode(NSView *v, NSCoder *c)
{
    if ([c containsValueForKey:@"NSvFlags"]) {
        unsigned flags = (unsigned)[c decodeInt64ForKey:@"NSvFlags"];
        v->_mask = flags & 0x3f;
        v->_autoresizes = (flags & 0x100) != 0;
        v->_hidden = (flags & 0x80000000u) != 0;
    }
    if ([c containsValueForKey:@"NSHidden"])
        v->_hidden = [c decodeBoolForKey:@"NSHidden"];
    for (NSView *sub in [c decodeObjectForKey:@"NSSubviews"])
        if ([sub isKindOfClass:[NSView class]] && [sub superview] != v)
            [v addSubview:sub];
    NSView *next = [c decodeObjectForKey:@"NSNextKeyView"];
    if ([next isKindOfClass:[NSView class]])
        [v setNextKeyView:next];
    NSString *tip = [c decodeObjectForKey:@"NSToolTip"];
    if ([tip isKindOfClass:[NSString class]])
        [v setToolTip:tip];
    NSString *ident = [c containsValueForKey:@"NSIdentifier"] ? [c decodeObjectForKey:@"NSIdentifier"] : nil;
    if ([ident isKindOfClass:[NSString class]])
        [v setIdentifier:ident];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        view_setup(self, AViewFrameFromCoder(coder));
        AViewDecode(self, coder);
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeRect:_frame forKey:@"NSFrame"];
    [coder encodeInt64:(int64_t)((_mask & 0x3f) | (_autoresizes ? 0x100 : 0) | (_hidden ? 0x80000000u : 0))
                forKey:@"NSvFlags"];
    if ([_subviews count])
        [coder encodeObject:_subviews forKey:@"NSSubviews"];
    if (_nextKeyView)
        [coder encodeConditionalObject:_nextKeyView forKey:@"NSNextKeyView"];
}

- (void)dealloc
{
    for (NSView *v in _subviews) {
        v->_superview = nil;
        [v setNextResponder:nil];
    }
    [_subviews release];
    [_toolTip release];
    [_identifier release];
    [_draggedTypes release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> %@", [self class], self, NSStringFromRect(_frame)];
}

/* ---- geometry ----------------------------------------------------------------------- */

- (NSRect)frame { return _frame; }
- (NSRect)bounds { return _bounds; }
- (NSPoint)frameOrigin { return _frame.origin; }
- (NSSize)frameSize { return _frame.size; }

- (void)_postFrameChanged
{
    if (_postsFrame)
        [[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
}

- (void)setFrameOrigin:(NSPoint)origin
{
    if (NSEqualPoints(origin, _frame.origin))
        return;
    [_superview setNeedsDisplay:YES];
    _frame.origin = origin;
    [self setNeedsDisplay:YES];
    [self _postFrameChanged];
}

- (void)setFrameSize:(NSSize)size
{
    NSSize old = _frame.size;
    if (NSEqualSizes(size, old))
        return;
    /* the bounds keep their scale */
    _bounds.size.width = old.width ? _bounds.size.width * size.width / old.width : size.width;
    _bounds.size.height = old.height ? _bounds.size.height * size.height / old.height : size.height;
    _frame.size = size;
    if (_autoresizes)
        [self resizeSubviewsWithOldSize:old];
    [_superview setNeedsDisplay:YES];
    [self setNeedsDisplay:YES];
    [self _postFrameChanged];
}

- (void)setFrame:(NSRect)frame
{
    BOOL posts = _postsFrame;
    _postsFrame = NO;
    [self setFrameOrigin:frame.origin];
    [self setFrameSize:frame.size];
    _postsFrame = posts;
    [self _postFrameChanged];
}

- (void)setBounds:(NSRect)bounds
{
    _bounds = bounds;
    [self setNeedsDisplay:YES];
    if (_postsBounds)
        [[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
}
- (void)setBoundsOrigin:(NSPoint)origin { [self setBounds:(NSRect){origin, _bounds.size}]; }
- (void)setBoundsSize:(NSSize)size { [self setBounds:(NSRect){_bounds.origin, size}]; }

- (BOOL)isFlipped { return NO; }
- (BOOL)isOpaque { return NO; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)hidden
{
    if (hidden == _hidden)
        return;
    _hidden = hidden;
    if (hidden && _window) {
        NSResponder *first = [_window firstResponder];
        if ([first isKindOfClass:[NSView class]] && [(NSView *)first isDescendantOf:self])
            [_window makeFirstResponder:nil];
    }
    [_superview setNeedsDisplay:YES];
}
- (BOOL)isHiddenOrHasHiddenAncestor
{
    for (NSView *v = self; v; v = v->_superview)
        if (v->_hidden)
            return YES;
    return NO;
}
- (BOOL)autoresizesSubviews { return _autoresizes; }
- (void)setAutoresizesSubviews:(BOOL)flag { _autoresizes = flag; }
- (NSAutoresizingMaskOptions)autoresizingMask { return _mask; }
- (void)setAutoresizingMask:(NSAutoresizingMaskOptions)mask { _mask = mask; }
- (NSInteger)tag { return -1; }
- (BOOL)wantsLayer { return _wantsLayer; }
- (void)setWantsLayer:(BOOL)flag { _wantsLayer = flag; }
- (CGFloat)alphaValue { return _alpha; }
- (void)setAlphaValue:(CGFloat)alpha
{
    _alpha = alpha;
    [self setNeedsDisplay:YES];
}
- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)tip
{
    [_toolTip release];
    _toolTip = [tip copy];
}
- (NSUserInterfaceItemIdentifier)identifier { return _identifier; }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    [_identifier release];
    _identifier = [identifier copy];
}
- (NSFocusRingType)focusRingType { return _focusRing; }
- (void)setFocusRingType:(NSFocusRingType)type { _focusRing = type; }
- (BOOL)postsFrameChangedNotifications { return _postsFrame; }
- (void)setPostsFrameChangedNotifications:(BOOL)flag { _postsFrame = flag; }
- (BOOL)postsBoundsChangedNotifications { return _postsBounds; }
- (void)setPostsBoundsChangedNotifications:(BOOL)flag { _postsBounds = flag; }
- (BOOL)inLiveResize { return NO; }
- (BOOL)translatesAutoresizingMaskIntoConstraints { return _translates; }
- (void)setTranslatesAutoresizingMaskIntoConstraints:(BOOL)flag { _translates = flag; }
/* The part of the bounds that no superview clips away. */
- (NSRect)visibleRect
{
    if (!_window && _superview)
        return NSZeroRect;
    NSRect r = _bounds;
    NSView *v = self;
    while (v->_superview && !NSIsEmptyRect(r)) {
        r = NSIntersectionRect(CGRectApplyAffineTransform(r, [v _transformToSuperview]), v->_superview->_bounds);
        v = v->_superview;
    }
    return NSIsEmptyRect(r) ? NSZeroRect : [self convertRect:r fromView:v];
}

/* ---- the view tree ----------------------------------------------------------------- */

- (NSView *)superview { return _superview; }
- (NSArray *)subviews { return [[_subviews copy] autorelease]; }
- (NSWindow *)window { return _window; }

- (void)setSubviews:(NSArray *)views
{
    for (NSView *v in [[_subviews copy] autorelease])
        if (![views containsObject:v])
            [v removeFromSuperview];
    for (NSView *v in views)
        if (v->_superview != self)
            [self addSubview:v];
    [_subviews setArray:views];
    [self setNeedsDisplay:YES];
}

- (void)_setWindow:(NSWindow *)window
{
    if (_window == window)
        return;
    [self viewWillMoveToWindow:window];
    _window = window;
    if ([_draggedTypes count])
        [window _enableDrops];
    for (NSView *v in _subviews)
        [v _setWindow:window];
    [self viewDidMoveToWindow];
    if (window)
        [self setNeedsDisplay:YES];
}

- (void)addSubview:(NSView *)view positioned:(NSInteger)place relativeTo:(NSView *)other
{
    if (!view || view == self)
        return;
    [view retain];
    if (view->_superview)
        [view removeFromSuperview];
    [view viewWillMoveToSuperview:self];
    NSUInteger i = other ? [_subviews indexOfObjectIdenticalTo:other] : NSNotFound;
    if (i == NSNotFound)
        [_subviews insertObject:view atIndex:place == NSWindowBelow ? 0 : [_subviews count]];
    else
        [_subviews insertObject:view atIndex:place == NSWindowBelow ? i : i + 1];
    view->_superview = self;
    [view setNextResponder:self];
    [view _setWindow:_window];
    [view viewDidMoveToSuperview];
    [self didAddSubview:view];
    [view setNeedsDisplay:YES];
    [view release];
}

- (void)addSubview:(NSView *)view { [self addSubview:view positioned:NSWindowAbove relativeTo:nil]; }

- (void)removeFromSuperview
{
    NSView *s = _superview;
    if (!s)
        return;
    [self retain];
    if (_window) {
        NSResponder *first = [_window firstResponder];
        if (first == self || ([first isKindOfClass:[NSView class]] && [(NSView *)first isDescendantOf:self]))
            [_window makeFirstResponder:nil];
    }
    [s willRemoveSubview:self];
    [self viewWillMoveToSuperview:nil];
    [s setNeedsDisplay:YES];
    _superview = nil;
    [self setNextResponder:nil];
    [s->_subviews removeObjectIdenticalTo:self];
    [self _setWindow:nil];
    [self viewDidMoveToSuperview];
    [self autorelease];
}

- (void)replaceSubview:(NSView *)old with:(NSView *)replacement
{
    if (old->_superview != self)
        return;
    NSUInteger i = [_subviews indexOfObjectIdenticalTo:old];
    NSView *below = i > 0 ? _subviews[i - 1] : nil;
    [old removeFromSuperview];
    if (below)
        [self addSubview:replacement positioned:NSWindowAbove relativeTo:below];
    else
        [self addSubview:replacement positioned:NSWindowBelow relativeTo:nil];
}

- (BOOL)isDescendantOf:(NSView *)view
{
    for (NSView *v = self; v; v = v->_superview)
        if (v == view)
            return YES;
    return NO;
}

- (NSView *)viewWithTag:(NSInteger)tag
{
    if ([self tag] == tag)
        return self;
    for (NSView *v in _subviews) {
        NSView *found = [v viewWithTag:tag];
        if (found)
            return found;
    }
    return nil;
}

- (void)viewWillMoveToWindow:(NSWindow *)window {}
- (void)viewDidMoveToWindow {}
- (void)viewWillMoveToSuperview:(NSView *)superview {}
- (void)viewDidMoveToSuperview {}
- (void)didAddSubview:(NSView *)view {}
- (void)willRemoveSubview:(NSView *)view {}

/* ---- autoresizing ------------------------------------------------------------------- */

- (void)resizeSubviewsWithOldSize:(NSSize)old
{
    for (NSView *v in [[_subviews copy] autorelease])
        [v resizeWithOldSuperviewSize:old];
}

/* Spreads a change in the superview's size over the flexible parts along one
 * axis (the margin before, the size, the margin after), in proportion to
 * their sizes, or equally when they are all empty. */
static void spread(CGFloat delta, BOOL flexMin, BOOL flexSize, BOOL flexMax, CGFloat *min, CGFloat *size, CGFloat max)
{
    int n = flexMin + flexSize + flexMax;
    if (!n || delta == 0)
        return;
    CGFloat total = (flexMin ? *min : 0) + (flexSize ? *size : 0) + (flexMax ? max : 0);
    CGFloat dMin = 0, dSize = 0;
    if (total > 0) {
        if (flexMin)
            dMin = delta * *min / total;
        if (flexSize)
            dSize = delta * *size / total;
    } else {
        if (flexMin)
            dMin = delta / n;
        if (flexSize)
            dSize = delta / n;
    }
    *min += dMin;
    *size += dSize;
    if (*size < 0)
        *size = 0;
}

- (void)resizeWithOldSuperviewSize:(NSSize)old
{
    if (!_superview || _mask == NSViewNotSizable)
        return;
    NSSize now = [_superview bounds].size;
    NSRect f = _frame;
    spread(now.width - old.width, _mask & NSViewMinXMargin, _mask & NSViewWidthSizable, _mask & NSViewMaxXMargin,
           &f.origin.x, &f.size.width, old.width - NSMaxX(_frame));
    spread(now.height - old.height, _mask & NSViewMinYMargin, _mask & NSViewHeightSizable, _mask & NSViewMaxYMargin,
           &f.origin.y, &f.size.height, old.height - NSMaxY(_frame));
    [self setFrame:f];
}

/* ---- coordinates -------------------------------------------------------------------- */

/* From this view's bounds to its superview's (or, for a window's content
 * view, the window's) coordinates. */
- (CGAffineTransform)_transformToSuperview
{
    NSRect f = _frame, b = _bounds;
    CGFloat sx = b.size.width ? f.size.width / b.size.width : 1;
    CGFloat sy = b.size.height ? f.size.height / b.size.height : 1;
    CGAffineTransform local = [self isFlipped]
                                  ? CGAffineTransformMake(sx, 0, 0, -sy, -b.origin.x * sx, f.size.height + b.origin.y * sy)
                                  : CGAffineTransformMake(sx, 0, 0, sy, -b.origin.x * sx, -b.origin.y * sy);
    CGAffineTransform place = _superview && [_superview isFlipped]
                                  ? CGAffineTransformMake(1, 0, 0, -1, f.origin.x, f.origin.y + f.size.height)
                                  : CGAffineTransformMakeTranslation(f.origin.x, f.origin.y);
    return CGAffineTransformConcat(local, place);
}

- (CGAffineTransform)_transformToWindow
{
    CGAffineTransform t = CGAffineTransformIdentity;
    for (NSView *v = self; v; v = v->_superview)
        t = CGAffineTransformConcat(t, [v _transformToSuperview]);
    return t;
}

/* From view's coordinates (the window's when view is nil) to this view's. */
static CGAffineTransform between(NSView *from, NSView *to)
{
    CGAffineTransform a = from ? [from _transformToWindow] : CGAffineTransformIdentity;
    CGAffineTransform b = to ? [to _transformToWindow] : CGAffineTransformIdentity;
    return CGAffineTransformConcat(a, CGAffineTransformInvert(b));
}

- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)view
{
    return CGPointApplyAffineTransform(p, between(view, self));
}
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)view
{
    return CGPointApplyAffineTransform(p, between(self, view));
}
- (NSRect)convertRect:(NSRect)r fromView:(NSView *)view { return CGRectApplyAffineTransform(r, between(view, self)); }
- (NSRect)convertRect:(NSRect)r toView:(NSView *)view { return CGRectApplyAffineTransform(r, between(self, view)); }
static NSSize abs_size(NSSize s) { return NSMakeSize(fabs(s.width), fabs(s.height)); }
- (NSSize)convertSize:(NSSize)s fromView:(NSView *)view
{
    return abs_size(CGSizeApplyAffineTransform(s, between(view, self)));
}
- (NSSize)convertSize:(NSSize)s toView:(NSView *)view
{
    return abs_size(CGSizeApplyAffineTransform(s, between(self, view)));
}
- (NSRect)centerScanRect:(NSRect)r
{
    NSRect w = NSIntegralRect([self convertRect:r toView:nil]);
    return [self convertRect:w fromView:nil];
}

/* ---- events ------------------------------------------------------------------------ */

/* point is in the superview's coordinates. */
- (NSView *)hitTest:(NSPoint)point
{
    if (_hidden)
        return nil;
    NSPoint local = CGPointApplyAffineTransform(point, CGAffineTransformInvert([self _transformToSuperview]));
    if (![self mouse:local inRect:_bounds])
        return nil;
    for (NSView *v in [_subviews reverseObjectEnumerator]) {
        NSView *hit = [v hitTest:local];
        if (hit)
            return hit;
    }
    return self;
}

- (BOOL)mouse:(NSPoint)p inRect:(NSRect)r { return NSMouseInRect(p, r, [self isFlipped]); }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return NO; }

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    for (NSView *v in [[_subviews copy] autorelease])
        if (!v->_hidden && [v performKeyEquivalent:event])
            return YES;
    return NO;
}

- (NSView *)nextKeyView { return _nextKeyView; }
- (void)setNextKeyView:(NSView *)view
{
    _nextKeyView = view;
    if (view)
        view->_previousKeyView = self;
}
- (NSView *)previousKeyView { return _previousKeyView; }
- (BOOL)canBecomeKeyView { return [self acceptsFirstResponder] && ![self isHiddenOrHasHiddenAncestor] && _window; }
- (NSView *)nextValidKeyView
{
    NSView *v = _nextKeyView;
    for (int guard = 0; v && v != self && guard < 1000; guard++, v = v->_nextKeyView)
        if ([v canBecomeKeyView])
            return v;
    return nil;
}

/* ---- drawing ---------------------------------------------------------------------- */

- (BOOL)needsDisplay { return _needsDisplay; }
- (void)setNeedsDisplay:(BOOL)flag
{
    _needsDisplay = flag;
    if (flag)
        [_window _noteNeedsDisplay];
}
- (void)setNeedsDisplayInRect:(NSRect)rect { [self setNeedsDisplay:YES]; }
- (void)setKeyboardFocusRingNeedsDisplayInRect:(NSRect)rect { [self setNeedsDisplay:YES]; }
- (BOOL)_needsDisplayAnywhere
{
    if (_needsDisplay)
        return YES;
    for (NSView *v in _subviews)
        if ([v _needsDisplayAnywhere])
            return YES;
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {}

/* Draws this view and its subviews; the context's CTM is already this
 * view's own coordinates, and dirty is in them too. */
- (void)_drawContentInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen
{
    dirty = NSIntersectionRect(dirty, _bounds);
    _needsDisplay = NO;
    if (NSIsEmptyRect(dirty))
        return;
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, _bounds);
    if (_alpha < 1)
        CGContextSetAlpha(ctx, _alpha);
    NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:[self isFlipped]];
    [gc _setDrawingToScreen:screen];
    [NSGraphicsContext setCurrentContext:gc];
    @autoreleasepool {
        [self drawRect:dirty];
    }
    for (NSView *v in [[_subviews copy] autorelease])
        [v _drawInContext:ctx dirty:dirty screen:screen];
    [NSGraphicsContext setCurrentContext:saved];
    [saved release];
    CGContextRestoreGState(ctx);
}

/* dirty is in the superview's coordinates. */
- (void)_drawInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen
{
    if (_hidden) {
        _needsDisplay = NO;
        return;
    }
    CGAffineTransform t = [self _transformToSuperview];
    NSRect local = CGRectApplyAffineTransform(dirty, CGAffineTransformInvert(t));
    CGContextSaveGState(ctx);
    CGContextConcatCTM(ctx, t);
    [self _drawContentInContext:ctx dirty:local screen:screen];
    CGContextRestoreGState(ctx);
}

- (void)display { [self displayRect:_bounds]; }
- (void)displayIfNeeded
{
    if ([self _needsDisplayAnywhere])
        [self display];
}
- (void)displayRect:(NSRect)rect
{
    if (_window)
        [_window display];
}

- (void)lockFocus
{
    AWarnOnce("-[NSView lockFocus] (draw in drawRect: instead)");
}
- (void)unlockFocus {}

- (NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)rect
{
    CGFloat scale = _window ? [_window backingScaleFactor] : 1;
    NSInteger w = (NSInteger)ceil(rect.size.width * scale), h = (NSInteger)ceil(rect.size.height * scale);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:32];
    [rep setSize:rect.size];
    return [rep autorelease];
}

/* Draws rect of this view (and its subviews) into the bitmap, the bitmap's
 * top row being the rect's top edge. */
- (void)cacheDisplayInRect:(NSRect)rect toBitmapImageRep:(NSBitmapImageRep *)rep
{
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!gc)
        return;
    CGContextRef ctx = [gc CGContext];
    /* this view's own coordinates, unflipped and relative to its frame */
    NSRect b = _bounds;
    CGFloat sx = b.size.width ? _frame.size.width / b.size.width : 1;
    CGFloat sy = b.size.height ? _frame.size.height / b.size.height : 1;
    CGAffineTransform local = [self isFlipped]
                                  ? CGAffineTransformMake(sx, 0, 0, -sy, -b.origin.x * sx, _frame.size.height + b.origin.y * sy)
                                  : CGAffineTransformMake(sx, 0, 0, sy, -b.origin.x * sx, -b.origin.y * sy);
    NSRect r = CGRectApplyAffineTransform(rect, local);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, -r.origin.x, -r.origin.y);
    CGContextConcatCTM(ctx, local);
    [self _drawContentInContext:ctx dirty:rect screen:NO];
    CGContextRestoreGState(ctx);
    CGContextFlush(ctx);
}

/* Scrolls the clip view this view is (or is inside) the document of. */
- (void)scrollPoint:(NSPoint)point
{
    for (NSView *v = self; v; v = v->_superview)
        if ([v->_superview isKindOfClass:[NSClipView class]]) {
            NSClipView *clip = (NSClipView *)v->_superview;
            [clip scrollToPoint:[clip constrainBoundsRect:(NSRect){[self convertPoint:point toView:clip],
                                                                  [clip bounds].size}].origin];
            return;
        }
}
@end
