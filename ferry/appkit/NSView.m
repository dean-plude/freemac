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

@interface NSWindow (FerryFocus)
- (CGContextRef)_focusContext;
- (void)_focusDrawn;
- (void)_noteViewNeedsDisplay;
@end

/* the view whose drawRect: runs, and the rectangle it draws */
static NSView *drawing_view;
static NSRect drawing_rect;

static void draw_rect(NSView *view, NSRect dirty)
{
    NSView *was = drawing_view;
    NSRect wasRect = drawing_rect;
    drawing_view = view;
    drawing_rect = dirty;
    /* The text matrix isn't part of the graphics state, so nothing restores
     * it; a Mac view starts drawing with the identity, and programs build
     * on what they read back (Hex Fiend's byte columns, freemac 1.270). */
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    if (cg)
        CGContextSetTextMatrix(cg, CGAffineTransformIdentity);
    [view drawRect:dirty];
    drawing_view = was;
    drawing_rect = wasRect;
}

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
    CALayer *_layer;                /* the backing or hosted layer */
    BOOL _hostsLayer, _drawsSubviewsIntoLayer;
    NSViewLayerContentsRedrawPolicy _redrawPolicy;
    NSDictionary *_animations;
    NSRect _dirtyRect;              /* what needs drawing, in bounds; empty: all of it */
}

/* Drag and drop: the types a view takes (NSDragging.m does the rest). */
- (void)registerForDraggedTypes:(NSArray *)types
{
    NSMutableArray *all = [NSMutableArray arrayWithArray:_draggedTypes ?: @[]];
    for (NSString *t in types)
        if (![all containsObject:t])
            [all addObject:t];
    id wasDraggedTypes = _draggedTypes;
    _draggedTypes = [all copy];
    [wasDraggedTypes release];
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
    v->_redrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
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
    /* Interface Builder keeps the identifier set in its inspector under this
     * key in compiled nibs (Hex Fiend finds its banners' fields by it) */
    if (!ident && [c containsValueForKey:@"NSReuseIdentifierKey"])
        ident = [c decodeObjectForKey:@"NSReuseIdentifierKey"];
    if ([ident isKindOfClass:[NSString class]])
        [v setIdentifier:ident];
    AViewDecodeConstraints(v, c);
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
    AConstraintsViewDying(self);
    for (NSView *v in _subviews) {
        v->_superview = nil;
        [v setNextResponder:nil];
    }
    [_subviews release];
    [_toolTip release];
    [_identifier release];
    [_draggedTypes release];
    [self _dropLayer];
    [_animations release];
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
    ATrackingGeometryChanged(self);
    if (_postsFrame)
        [[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
}

- (void)setFrameOrigin:(NSPoint)origin
{
    if (NSEqualPoints(origin, _frame.origin))
        return;
    [_superview setNeedsDisplay:YES];
    _frame.origin = origin;
    [self _syncLayer];
    [self setNeedsDisplay:YES];
    [self _postFrameChanged];
    AConstraintsViewChanged(self);
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
    [self _syncLayer];
    if (_autoresizes)
        [self resizeSubviewsWithOldSize:old];
    [_superview setNeedsDisplay:YES];
    [self setNeedsDisplay:YES];
    [self _postFrameChanged];
    AConstraintsViewChanged(self);
}

/* A frame set to what it is already posts nothing (observers that set
 * frames as the notification comes, as Sequel Pro's connection view does,
 * would otherwise be called again and again). */
- (void)setFrame:(NSRect)frame
{
    if (NSEqualRects(frame, _frame))
        return;
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
    [self _syncLayer];
    [self setNeedsDisplay:YES];
    ATrackingGeometryChanged(self);
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
    [self _syncLayer];
    if (hidden && _window) {
        NSResponder *first = [_window firstResponder];
        if ([first isKindOfClass:[NSView class]] && [(NSView *)first isDescendantOf:self])
            [_window makeFirstResponder:nil];
    }
    [_superview setNeedsDisplay:YES];
    /* a stack view lays its views out again (NSStackView.m) */
    if ([_superview respondsToSelector:@selector(_arrangedSubviewVisibilityChanged:)])
        [_superview performSelector:@selector(_arrangedSubviewVisibilityChanged:) withObject:self];
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
- (CGFloat)alphaValue { return _alpha; }
- (void)setAlphaValue:(CGFloat)alpha
{
    _alpha = alpha;
    [self _syncLayer];
    [self setNeedsDisplay:YES];
}

/* ---- layers --------------------------------------------------------------------------
 * A view that wants a layer is given one by makeBackingLayer, with the view
 * as its delegate; a layer set with setLayer: before wantsLayer is a hosted
 * layer, which the view shows but doesn't draw into. Either way the view
 * keeps the layer's geometry, opacity and hidden flag in step with its own
 * (the layer's bounds are the view's bounds, its anchor point stays where
 * it was, (0, 0) for a backing layer), and draws the layer tree in its own
 * coordinates when it draws: the layer's background, contents and border,
 * the view's drawRect: (or updateLayer) and subviews as the layer's
 * content, and the sublayers above them. A view's layer isn't a sublayer
 * of its superview's: each view's layer is drawn from the view. */

- (BOOL)wantsLayer { return _wantsLayer; }
- (void)setWantsLayer:(BOOL)flag
{
    if (flag == _wantsLayer)
        return;
    _wantsLayer = flag;
    if (flag && !_layer)   /* through setLayer:, as on a Mac, for views that override it (Qt's) */
        [self setLayer:[self makeBackingLayer]];
    else if (!flag && _layer && !_hostsLayer)
        [self _dropLayer];
    [self setNeedsDisplay:YES];
}
- (CALayer *)makeBackingLayer { return [CALayer layer]; }
/* A class may say it wants a layer by overriding wantsLayer rather than
 * calling setWantsLayer: (GTK's GdkQuartzView, darktable): AppKit then gives
 * it a backing layer all the same, the first time the layer is asked for or
 * the view is drawn. */
static IMP view_wants_layer;
- (void)_takeWantedLayer
{
    static __thread BOOL asking;
    if (_layer || _wantsLayer || asking)
        return;
    if (!view_wants_layer)
        view_wants_layer = class_getMethodImplementation([NSView class], @selector(wantsLayer));
    if (class_getMethodImplementation(object_getClass(self), @selector(wantsLayer)) == view_wants_layer)
        return;
    asking = YES;
    BOOL wants = [self wantsLayer];
    asking = NO;
    if (!wants)
        return;
    _wantsLayer = YES;
    [self setLayer:[self makeBackingLayer]];
}
- (CALayer *)layer
{
    [self _takeWantedLayer];
    return _layer;
}
- (void)setLayer:(CALayer *)layer
{
    if (layer == _layer)
        return;
    [self _dropLayer];
    if (layer)
        [self _adoptLayer:layer hosting:!_wantsLayer];
    [self setNeedsDisplay:YES];
}
- (BOOL)wantsUpdateLayer { return NO; }
- (void)updateLayer {}
- (NSViewLayerContentsRedrawPolicy)layerContentsRedrawPolicy { return _redrawPolicy; }
- (void)setLayerContentsRedrawPolicy:(NSViewLayerContentsRedrawPolicy)policy { _redrawPolicy = policy; }
- (BOOL)canDrawSubviewsIntoLayer { return _drawsSubviewsIntoLayer; }
- (void)setCanDrawSubviewsIntoLayer:(BOOL)flag { _drawsSubviewsIntoLayer = flag; }

- (void)_adoptLayer:(CALayer *)layer hosting:(BOOL)hosting
{
    if (!layer)
        return;
    _layer = [layer retain];
    _hostsLayer = hosting;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!hosting) {
        [layer setDelegate:(id)self];
        [layer setAnchorPoint:CGPointZero];
    }
    [CATransaction commit];
    FerryCALayerSetHost(layer, self);
    [self _syncLayer];
}

- (void)_dropLayer
{
    if (!_layer)
        return;
    if ([_layer delegate] == (id)self)
        [_layer setDelegate:nil];
    FerryCALayerSetHost(_layer, nil);
    [_layer release];
    _layer = nil;
    _hostsLayer = NO;
}

/* The layer follows the view. Its changes animate only when the current
 * animation context allows implicit animation. */
- (void)_syncLayer
{
    if (!_layer)
        return;
    [CATransaction begin];
    if (![[NSAnimationContext currentContext] allowsImplicitAnimation])
        [CATransaction setDisableActions:YES];
    CGPoint ap = [_layer anchorPoint];
    [_layer setBounds:_bounds];
    [_layer setPosition:CGPointMake(_frame.origin.x + ap.x * _frame.size.width,
                                    _frame.origin.y + ap.y * _frame.size.height)];
    [_layer setOpacity:(float)_alpha];
    [_layer setHidden:_hidden];
    [CATransaction commit];
}

/* As the backing layer's delegate: no implicit animations unless the
 * current animation context allows them. */
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if (layer == _layer && ![[NSAnimationContext currentContext] allowsImplicitAnimation])
        return (id<CAAction>)[NSNull null];
    return nil;
}

static int layers_drawing;   /* changes made while a view draws its layer don't ask for another draw */

/* The layer tree changed or is animating: the window draws again. */
- (void)_ferryLayerTreeChanged
{
    if (!layers_drawing)
        [_window _noteNeedsDisplay];
}

/* ---- animator proxies (NSAnimationContext.m) ---- */

- (instancetype)animator { return AAnimatorFor(self); }
- (NSDictionary *)animations { return _animations ?: @{}; }
- (void)setAnimations:(NSDictionary *)animations
{
    id wasAnimations = _animations;
    _animations = [animations copy];
    [wasAnimations release];
}
- (id)animationForKey:(NSString *)key
{
    id a = _animations[key];
    if (a)
        return a == [NSNull null] ? nil : a;
    return [[self class] defaultAnimationForKey:key];
}
+ (id)defaultAnimationForKey:(NSString *)key
{
    static NSSet *keys;
    if (!keys)
        keys = [[NSSet setWithArray:@[ @"frame", @"frameOrigin", @"frameSize", @"bounds", @"boundsOrigin",
                                       @"boundsSize", @"alphaValue" ]] retain];
    return [keys containsObject:key] ? [CABasicAnimation animation] : nil;
}
- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)tip
{
    id wasToolTip = _toolTip;
    _toolTip = [tip copy];
    [wasToolTip release];
}
- (NSUserInterfaceItemIdentifier)identifier { return _identifier; }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    id wasIdentifier = _identifier;
    _identifier = [identifier copy];
    [wasIdentifier release];
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

// Reorders the subviews (their drawing order) by the app's own comparison,
// which is how wxWidgets puts a view it raises on top.
- (void)sortSubviewsUsingFunction:(NSComparisonResult (*)(__kindof NSView *, __kindof NSView *, void *))compare
                          context:(void *)context
{
    if ([_subviews count] < 2 || !compare)
        return;
    NSArray *sorted = [_subviews sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))compare context:context];
    [_subviews setArray:sorted];
    [self setNeedsDisplay:YES];
}

- (void)_setWindow:(NSWindow *)window
{
    if (_window == window)
        return;
    [self viewWillMoveToWindow:window];
    ATrackingViewMoving(self, _window, window);
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
    AMainThreadOnly("-[NSView addSubview:]");
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
    AConstraintsViewRemoved(self, s);
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
    AMainThreadOnly("-[NSView setNeedsDisplay:]");
    _needsDisplay = flag;
    _dirtyRect = NSZeroRect;
    if (flag)
        [_window _noteViewNeedsDisplay];
    /* A backing layer whose delegate displays it (displayLayer:, as Qt's
     * view does) is displayed when the view is: the layer is marked too. */
    if (flag && _layer && !_hostsLayer && [[_layer delegate] respondsToSelector:@selector(displayLayer:)])
        [_layer setNeedsDisplay];
}
/* Only the part asked for is drawn again (a meter's bar, a playhead's
 * column), not the whole window, as on a Mac. */
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    if (NSIsEmptyRect(rect))
        return;
    NSRect had = _needsDisplay ? (NSIsEmptyRect(_dirtyRect) ? _bounds : _dirtyRect) : NSZeroRect;
    [self setNeedsDisplay:YES];
    if (_needsDisplay)
        _dirtyRect = NSIsEmptyRect(had) ? rect : NSUnionRect(had, rect);
}
- (void)setKeyboardFocusRingNeedsDisplayInRect:(NSRect)rect { [self setNeedsDisplay:YES]; }
- (BOOL)_needsDisplayAnywhere
{
    /* A hidden view isn't drawn, so a mark under it is never cleared; counting
     * it would have the window draw itself again on every turn of the run
     * loop. Showing the view again marks its superview (setHidden:). */
    if (_hidden)
        return NO;
    if (_needsDisplay)
        return YES;
    for (NSView *v in _subviews)
        if ([v _needsDisplayAnywhere])
            return YES;
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {}
/* The rectangles drawRect: is drawing, for a view that draws only those
 * (NSView's getRectsBeingDrawn:count: and needsToDrawRect:, as Apple's
 * documentation describes them): Ferry draws one rectangle at a time, so
 * there is one (freemac 1.267). */
- (void)getRectsBeingDrawn:(const NSRect **)rects count:(NSInteger *)count
{
    BOOL mine = drawing_view == self;
    if (rects)
        *rects = mine ? &drawing_rect : NULL;
    if (count)
        *count = mine ? 1 : 0;
}
- (BOOL)needsToDrawRect:(NSRect)rect
{
    return NSIntersectsRect(rect, drawing_view == self ? drawing_rect : [self visibleRect]);
}

/* Adds the window rectangles this view and those under it need drawn to
 * rects (merging ones that touch, all into one past max). NO when the whole
 * window must be drawn: a layer, whose animation can show anywhere. */
static void add_dirty(NSRect r, NSRect *rects, int *n, int max)
{
    r = NSInsetRect(NSIntegralRect(r), -1, -1);
    for (;;) {
        BOOL merged = NO;
        for (int i = 0; i < *n; i++)
            if (NSIntersectsRect(rects[i], r)) {
                r = NSUnionRect(r, rects[i]);
                rects[i] = rects[--*n];
                merged = YES;
                break;
            }
        if (!merged)
            break;
    }
    if (*n == max) {
        for (int i = 0; i < *n; i++)
            r = NSUnionRect(r, rects[i]);
        *n = 0;
    }
    rects[(*n)++] = r;
}
- (BOOL)_collectDirty:(NSRect *)rects count:(int *)n max:(int)max
{
    if (_hidden)
        return YES;
    if (_layer && [self _needsDisplayAnywhere])
        return NO;
    if (_needsDisplay) {
        NSRect r = NSIntersectionRect(NSIsEmptyRect(_dirtyRect) ? _bounds : _dirtyRect, _bounds);
        if (!NSIsEmptyRect(r))
            add_dirty(CGRectApplyAffineTransform(r, [self _transformToWindow]), rects, n, max);
        /* cleared now: a view clipped away by its superview is never reached */
        _needsDisplay = NO;
        _dirtyRect = NSZeroRect;
    }
    for (NSView *v in _subviews)
        if (![v _collectDirty:rects count:n max:max])
            return NO;
    return YES;
}

/* Draws this view and its subviews; the context's CTM is already this
 * view's own coordinates, and dirty is in them too. */
- (void)_drawContentInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen
{
    dirty = NSIntersectionRect(dirty, _bounds);
    [self _takeWantedLayer];
    BOOL wanted = _needsDisplay;
    _needsDisplay = NO;
    _dirtyRect = NSZeroRect;
    if (_layer) {
        [self _drawLayerInContext:ctx dirty:dirty screen:screen update:wanted];
        return;
    }
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
    /* an OpenGL context's drawing shows over the view's own (NSOpenGL.m, 1.235) */
    BOOL gl = AGLViewCount > 0, skip = gl && AGLViewWillDraw(self);
    @autoreleasepool {
        if (!skip)
            draw_rect(self, dirty);
    }
    if (gl)
        AGLViewDidDraw(self, ctx);
    for (NSView *v in [[_subviews copy] autorelease])
        [v _drawInContext:ctx dirty:dirty screen:screen];
    [NSGraphicsContext setCurrentContext:saved];
    [saved release];
    CGContextRestoreGState(ctx);
}

/* A view with a layer draws the layer tree, its own drawing being the
 * layer's content. updateLayer stands for drawRect: when the view wants
 * it; a hosted layer has no drawing of the view's. */
- (void)_drawLayerInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen update:(BOOL)update
{
    BOOL updates = !_hostsLayer && [self wantsUpdateLayer];
    layers_drawing++;
    if (updates && update && !(AGLViewCount > 0 && AGLViewTakeFrameOnly(self)))
        [self updateLayer];
    NSRect b = _bounds;
    FerryCALayerRender(_layer, ctx, YES, [self isFlipped], ^(CGContextRef c) {
      CGContextClipToRect(c, b);
      NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
      NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:c flipped:[self isFlipped]];
      [gc _setDrawingToScreen:screen];
      [NSGraphicsContext setCurrentContext:gc];
      if (!_hostsLayer && !updates && !NSIsEmptyRect(dirty)) {
          BOOL gl = AGLViewCount > 0, skip = gl && AGLViewWillDraw(self);
          @autoreleasepool {
              if (!skip)
                  draw_rect(self, dirty);
          }
          if (gl)
              AGLViewDidDraw(self, c);
      } else if (AGLViewCount > 0 && !_hostsLayer) {
          /* a view that updates its layer itself still shows what an
           * OpenGL context draws into it: Qt 5 composes a window that
           * holds a 3D view with OpenGL into the window's own layer-backed
           * view (freemac 1.267) */
          AGLViewDidDraw(self, c);
      }
      for (NSView *v in [[_subviews copy] autorelease])
          [v _drawInContext:c dirty:dirty screen:screen];
      [NSGraphicsContext setCurrentContext:saved];
      [saved release];
    });
    layers_drawing--;
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
    if (_layer) {
        /* where an animation of the layer shows it */
        CGAffineTransform shown = FerryCALayerPresentationOffset(_layer);
        CGContextConcatCTM(ctx, shown);
        local = CGRectApplyAffineTransform(local, CGAffineTransformInvert(shown));
    }
    /* in the view's own appearance, if it has one (freemac 1.245) */
    NSAppearance *appearance = ABeginDrawingAppearance(self);
    [self _drawContentInContext:ctx dirty:local screen:screen];
    AEndDrawingAppearance(appearance);
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

/* lockFocus: the view's drawing goes straight onto its window, in the
 * view's own coordinates and clipped to what shows of it, until
 * unlockFocus; the window's next full redraw draws over it, as on a Mac.
 * Focus nests, so each lock keeps what it replaced. */
typedef struct {
    NSView *view;
    CGContextRef ctx;
    NSGraphicsContext *saved;
} AFocus;
static AFocus focus_stack[32];
static int focus_depth;

- (BOOL)_pushFocus:(BOOL)mustDraw
{
    if (focus_depth >= 32 || ![NSThread isMainThread])
        return NO;
    CGContextRef ctx = NULL;
    if (_window && ![self isHiddenOrHasHiddenAncestor] && !NSIsEmptyRect([self visibleRect]))
        ctx = [_window _focusContext];
    if (!ctx && mustDraw)
        return NO;
    AFocus *f = &focus_stack[focus_depth++];
    f->view = self;
    f->ctx = ctx;
    f->saved = [[NSGraphicsContext currentContext] retain];
    if (ctx) {
        CGContextSaveGState(ctx);
        CGContextConcatCTM(ctx, [self _transformToWindow]);
        CGContextClipToRect(ctx, [self visibleRect]);
        NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:[self isFlipped]];
        [gc _setDrawingToScreen:YES];
        [NSGraphicsContext setCurrentContext:gc];
    }
    return YES;
}
- (void)lockFocus { [self _pushFocus:NO]; }
- (BOOL)lockFocusIfCanDraw { return [self _pushFocus:YES]; }
- (void)unlockFocus
{
    if (focus_depth == 0 || focus_stack[focus_depth - 1].view != self)
        return;
    AFocus *f = &focus_stack[--focus_depth];
    if (f->ctx) {
        CGContextRestoreGState(f->ctx);
        [_window _focusDrawn];
    }
    [NSGraphicsContext setCurrentContext:f->saved];
    [f->saved release];
    f->view = nil;
}
+ (NSView *)focusView { return focus_depth ? focus_stack[focus_depth - 1].view : nil; }

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
