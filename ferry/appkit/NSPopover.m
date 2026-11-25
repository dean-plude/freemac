/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: popovers (NSPopover), written from Apple's public API
 * documentation.
 *
 * A popover shows its content view controller's view in a rounded bubble
 * with an arrow pointing at a rectangle of a view, on the edge asked for
 * when there is room in the window and on the opposite edge when there
 * isn't, moved along that edge to stay inside the window. Wayland doesn't
 * let a program place a window of its own beside another, so, like an
 * open menu, the bubble is drawn inside the view's window, over its other
 * views, and can't reach past the window's edges.
 *
 * While it is shown, the window's mouse and keys go through it: clicks in
 * the bubble reach its views (and make them first responder as a click
 * does), keys go to the first responder. A click elsewhere in the window
 * closes a transient or semitransient popover (asking popoverShouldClose:
 * first) and then reaches the view it was on, as it does for an
 * application-defined popover, which only closes when told to. A
 * transient popover also closes when its window stops being the key
 * window; Escape closes either kind. Its delegate and the notification
 * centre hear popoverWillShow:, popoverDidShow:, popoverWillClose: and
 * popoverDidClose: (with NSPopoverCloseReasonStandard). There is no
 * animation and no detaching into a window of its own.
 *
 * A menu bar item's button is in no window here (the desktop's menu bar
 * draws the item), so a popover shown from one (freemac 1.230) gets a
 * borderless window of its own, just big enough for the bubble, with its
 * arrow at the foot of the menu bar under where the menu bar says the item
 * was clicked (at its right when it hasn't said); the window goes when the
 * popover closes. A compositor that places windows itself may put it
 * elsewhere.
 *
 * A popover in a nib keeps its behaviour under "NSBehavior" and its size
 * under "NSContentSize" (names from developers' descriptions of the
 * format; no Apple code was read); its content view controller is an
 * outlet. */
#import "AInternal.h"

NSString *const NSPopoverCloseReasonKey = @"NSPopoverCloseReasonKey";
NSPopoverCloseReasonValue const NSPopoverCloseReasonStandard = @"NSPopoverCloseReasonStandard";
NSPopoverCloseReasonValue const NSPopoverCloseReasonDetachToWindow = @"NSPopoverCloseReasonDetachToWindow";
NSNotificationName const NSPopoverWillShowNotification = @"NSPopoverWillShowNotification";
NSNotificationName const NSPopoverDidShowNotification = @"NSPopoverDidShowNotification";
NSNotificationName const NSPopoverWillCloseNotification = @"NSPopoverWillCloseNotification";
NSNotificationName const NSPopoverDidCloseNotification = @"NSPopoverDidCloseNotification";

static const CGFloat arrow_length = 9, arrow_half = 9, corner = 9, margin = 4;

@interface NSPopover (FerryPopover)
- (void)_clickedOutside;
- (void)_escape;
@end

/* ---- the bubble ------------------------------------------------------------------------ */

@interface APopoverFrame : NSView {
@public
    NSRectEdge _edge;     /* the side of the bubble the arrow is on, in the window */
    CGFloat _arrowAt;     /* where along that side, from the frame's origin */
}
@end
@implementation APopoverFrame
/* The bubble without its arrow, in the frame's coordinates. */
- (NSRect)_bubble
{
    NSRect b = [self bounds];
    switch (_edge) {
    case NSRectEdgeMinY: b.origin.y += arrow_length; b.size.height -= arrow_length; break;
    case NSRectEdgeMaxY: b.size.height -= arrow_length; break;
    case NSRectEdgeMinX: b.origin.x += arrow_length; b.size.width -= arrow_length; break;
    default: b.size.width -= arrow_length; break;
    }
    return b;
}
/* The arrow's three points: its base (just inside the bubble) and its tip. */
- (void)_arrow:(NSPoint *)pts inBubble:(NSRect)r
{
    CGFloat t = _arrowAt;
    switch (_edge) {
    case NSRectEdgeMinY:
        pts[0] = NSMakePoint(t - arrow_half, NSMinY(r) + 1);
        pts[1] = NSMakePoint(t, NSMinY(r) - arrow_length + 0.5);
        pts[2] = NSMakePoint(t + arrow_half, NSMinY(r) + 1);
        break;
    case NSRectEdgeMaxY:
        pts[0] = NSMakePoint(t - arrow_half, NSMaxY(r) - 1);
        pts[1] = NSMakePoint(t, NSMaxY(r) + arrow_length - 0.5);
        pts[2] = NSMakePoint(t + arrow_half, NSMaxY(r) - 1);
        break;
    case NSRectEdgeMinX:
        pts[0] = NSMakePoint(NSMinX(r) + 1, t - arrow_half);
        pts[1] = NSMakePoint(NSMinX(r) - arrow_length + 0.5, t);
        pts[2] = NSMakePoint(NSMinX(r) + 1, t + arrow_half);
        break;
    default:
        pts[0] = NSMakePoint(NSMaxX(r) - 1, t - arrow_half);
        pts[1] = NSMakePoint(NSMaxX(r) + arrow_length - 0.5, t);
        pts[2] = NSMakePoint(NSMaxX(r) - 1, t + arrow_half);
        break;
    }
}
- (void)drawRect:(NSRect)dirty
{
    NSRect r = NSInsetRect([self _bubble], 0.5, 0.5);
    NSBezierPath *bubble = [NSBezierPath bezierPathWithRoundedRect:r xRadius:corner yRadius:corner];
    NSPoint pts[3];
    [self _arrow:pts inBubble:r];
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:pts[0]];
    [arrow lineToPoint:pts[1]];
    [arrow lineToPoint:pts[2]];
    [arrow closePath];
    NSBezierPath *outline = [[bubble copy] autorelease];
    [outline appendBezierPath:arrow];
    /* a soft edge in place of a shadow, as before Ferry drew shadows */
    for (int i = 3; i >= 1; i--) {
        [outline setLineWidth:i * 2];
        [[NSColor colorWithWhite:0 alpha:0.03] setStroke];
        [outline stroke];
    }
    NSColor *face = [NSColor controlBackgroundColor], *edge = [NSColor colorWithWhite:0 alpha:0.18];
    [face setFill];
    [outline fill];
    [bubble setLineWidth:1];
    [edge setStroke];
    [bubble stroke];
    /* the arrow joins the bubble: its base covers the bubble's edge, and
     * only its sides are drawn, from where they leave the bubble */
    [face setFill];
    [arrow fill];
    CGFloat f = 1.5 / (arrow_length + 0.5);
    NSBezierPath *sides = [NSBezierPath bezierPath];
    [sides moveToPoint:NSMakePoint(pts[0].x + (pts[1].x - pts[0].x) * f, pts[0].y + (pts[1].y - pts[0].y) * f)];
    [sides lineToPoint:pts[1]];
    [sides lineToPoint:NSMakePoint(pts[2].x + (pts[1].x - pts[2].x) * f, pts[2].y + (pts[1].y - pts[2].y) * f)];
    [sides setLineWidth:1];
    [sides setLineJoinStyle:NSLineJoinStyleRound];
    [edge setStroke];
    [sides stroke];
}
@end

/* The window's overlay while a popover shows: the bubble, and the way the
 * window's events go. */
@interface APopoverHost : NSView {
@public
    NSPopover *_popover;   /* not retained: it owns us */
    APopoverFrame *_frame;
    NSView *_target;       /* where the mouse went down */
    BOOL _passing;         /* an event is being passed on to a view */
}
@end
@implementation APopoverHost
- (void)dealloc
{
    [_frame release];
    [_target release];
    [super dealloc];
}
- (BOOL)isFlipped { return NO; }
- (NSView *)hitTest:(NSPoint)p { return NSPointInRect(p, [self frame]) ? self : nil; }
/* What a point (in the window) is over: the bubble's views, or the
 * window's own. */
- (NSView *)_viewAt:(NSPoint)p inside:(BOOL *)inside
{
    NSView *v = [_frame hitTest:p];
    *inside = v != nil;
    if (v)
        return v;
    NSWindow *w = [self window];
    NSView *toolbar = [w _toolbarView];
    if (toolbar && ![toolbar isHidden] && (v = [toolbar hitTest:p]))
        return v;
    return [[w contentView] hitTest:p];
}
/* A view that does not take an event passes it up its superviews, which
 * leads back here: it stops here then, as it would at a window (freemac
 * 1.231; a click on a label in a popover went round for ever). */
#define PASS_ONCE(...) do { if (_passing) return; _passing = YES; __VA_ARGS__; _passing = NO; } while (0)
- (void)mouseDown:(NSEvent *)e { PASS_ONCE([self _mouseDown:e]); }
- (void)_mouseDown:(NSEvent *)e
{
    NSWindow *w = [[[self window] retain] autorelease];
    BOOL inside;
    NSView *v = [self _viewAt:[e locationInWindow] inside:&inside];
    if (!inside) {
        [[self retain] autorelease];
        [_popover _clickedOutside];
        /* the click goes on to what it was on */
        BOOL dummy;
        v = [self _viewAt:[e locationInWindow] inside:&dummy];
    }
    [_target release];
    _target = [v retain];
    if (!v)
        return;
    if (v != (NSView *)[w firstResponder] && [v acceptsFirstResponder])
        [w makeFirstResponder:v];
    [v mouseDown:e];
}
- (void)mouseDragged:(NSEvent *)e { PASS_ONCE([_target mouseDragged:e]); }
- (void)mouseUp:(NSEvent *)e
{
    NSView *v = [_target autorelease];
    _target = nil;
    PASS_ONCE([v mouseUp:e]);
}
- (void)rightMouseDown:(NSEvent *)e
{
    BOOL inside;
    NSView *v = [self _viewAt:[e locationInWindow] inside:&inside];
    if (!inside)
        [_popover _clickedOutside];
    PASS_ONCE([v rightMouseDown:e]);
}
- (void)scrollWheel:(NSEvent *)e
{
    BOOL inside;
    PASS_ONCE([[self _viewAt:[e locationInWindow] inside:&inside] scrollWheel:e]);
}
- (void)mouseMoved:(NSEvent *)e {}
- (void)keyDown:(NSEvent *)e
{
    NSWindow *w = [self window];
    NSString *c = [e charactersIgnoringModifiers];
    if ([c isEqualToString:@"\x1b"]) {
        [_popover _escape];
        return;
    }
    if (([e modifierFlags] & NSEventModifierFlagCommand) && [w performKeyEquivalent:e])
        return;
    NSResponder *first = [w firstResponder];
    if (first && first != (NSResponder *)self)
        PASS_ONCE([first keyDown:e]);
}
@end

/* ---- NSPopover ------------------------------------------------------------------------- */

@implementation NSPopover {
    NSViewController *_content;
    NSSize _size;
    NSPopoverBehavior _behavior;
    BOOL _animates, _shown;
    NSAppearance *_appearance;
    id _delegate;
    NSRect _positioningRect;
    NSView *_positioningView;
    NSRectEdge _preferredEdge;
    APopoverHost *_host;
    NSWindow *_window;
    NSWindow *_ownWindow; /* for a popover from a menu bar item */
}

- (instancetype)init
{
    if ((self = [super init]))
        _animates = YES;
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super init]))
        return nil;
    _animates = [coder containsValueForKey:@"NSAnimates"] ? [coder decodeBoolForKey:@"NSAnimates"] : YES;
    if ([coder containsValueForKey:@"NSBehavior"])
        _behavior = [coder decodeIntegerForKey:@"NSBehavior"];
    if ([coder containsValueForKey:@"NSContentSize"])
        _size = [coder decodeSizeForKey:@"NSContentSize"];
    id vc = [coder containsValueForKey:@"NSContentViewController"] ? [coder decodeObjectForKey:@"NSContentViewController"] : nil;
    if ([vc isKindOfClass:[NSViewController class]])
        [self setContentViewController:vc];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBool:_animates forKey:@"NSAnimates"];
    [coder encodeInteger:_behavior forKey:@"NSBehavior"];
    [coder encodeSize:_size forKey:@"NSContentSize"];
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_host && [_window _overlayView] == _host)
        [_window _setOverlayView:nil];
    _host->_popover = nil;
    [_host release];
    [_content release];
    [_positioningView release];
    [_window release];
    [_ownWindow release];
    [_appearance release];
    [super dealloc];
}

- (NSViewController *)contentViewController { return _content; }
- (void)setContentViewController:(NSViewController *)vc
{
    if (vc == _content)
        return;
    [vc retain];
    if (_shown)
        [[_content view] removeFromSuperview];
    [_content release];
    _content = vc;
    if (_shown)
        [self _layOut];
}
- (NSSize)contentSize
{
    if (_size.width > 0 && _size.height > 0)
        return _size;
    NSSize preferred = [_content preferredContentSize];
    if (preferred.width > 0 && preferred.height > 0)
        return preferred;
    return _content ? [[_content view] frame].size : NSZeroSize;
}
- (void)setContentSize:(NSSize)s
{
    _size = s;
    if (_shown)
        [self _layOut];
}
- (NSPopoverBehavior)behavior { return _behavior; }
- (void)setBehavior:(NSPopoverBehavior)b { _behavior = b; }
- (BOOL)animates { return _animates; }
- (void)setAnimates:(BOOL)f { _animates = f; }
- (NSAppearance *)appearance { return _appearance; }
- (void)setAppearance:(NSAppearance *)a
{
    [a retain];
    [_appearance release];
    _appearance = a;
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isShown { return _shown; }
- (BOOL)isDetached { return NO; }
- (NSRect)positioningRect { return _positioningRect; }
- (void)setPositioningRect:(NSRect)r
{
    _positioningRect = r;
    if (_shown)
        [self _layOut];
}

- (void)_post:(NSNotificationName)name selector:(SEL)sel
{
    NSDictionary *info = nil;
    if ([name isEqualToString:NSPopoverWillCloseNotification] || [name isEqualToString:NSPopoverDidCloseNotification])
        info = @{NSPopoverCloseReasonKey : NSPopoverCloseReasonStandard};
    NSNotification *n = [NSNotification notificationWithName:name object:self userInfo:info];
    if ([_delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

/* Where the bubble goes: on the preferred edge of the rectangle if it fits
 * in the window there, else on the opposite one, slid along to stay in. */
- (void)_layOut
{
    NSView *content = [_content view];
    NSSize size = [self contentSize];
    NSRect r = [_positioningView convertRect:_positioningRect toView:nil];
    NSRect win = [_host bounds];
    /* the edge in the window's coordinates (a flipped view's minimum y is its top) */
    NSRectEdge edge = _preferredEdge;
    if ([_positioningView isFlipped] && (edge == NSRectEdgeMinY || edge == NSRectEdgeMaxY))
        edge = edge == NSRectEdgeMinY ? NSRectEdgeMaxY : NSRectEdgeMinY;
    BOOL vertical = edge == NSRectEdgeMinY || edge == NSRectEdgeMaxY;
    CGFloat need = (vertical ? size.height : size.width) + arrow_length;
    CGFloat room[4] = {NSMinX(r) - NSMinX(win), NSMinY(r) - NSMinY(win), NSMaxX(win) - NSMaxX(r), NSMaxY(win) - NSMaxY(r)};
    NSRectEdge opposite = (NSRectEdge)((edge + 2) % 4);
    if (room[edge] < need && room[opposite] > room[edge])
        edge = opposite;
    NSRect f;
    if (vertical) {
        f.size = NSMakeSize(size.width, size.height + arrow_length);
        f.origin.x = NSMidX(r) - size.width / 2;
        f.origin.y = edge == NSRectEdgeMaxY ? NSMaxY(r) : NSMinY(r) - f.size.height;
        f.origin.x = fmax(NSMinX(win) + margin, fmin(f.origin.x, NSMaxX(win) - margin - f.size.width));
    } else {
        f.size = NSMakeSize(size.width + arrow_length, size.height);
        f.origin.y = NSMidY(r) - size.height / 2;
        f.origin.x = edge == NSRectEdgeMaxX ? NSMaxX(r) : NSMinX(r) - f.size.width;
        f.origin.y = fmax(NSMinY(win) + margin, fmin(f.origin.y, NSMaxY(win) - margin - f.size.height));
    }
    f = NSIntegralRect(f);
    APopoverFrame *frame = _host->_frame;
    [frame setFrame:f];
    /* the arrow is on the bubble's side facing the rectangle */
    frame->_edge = (NSRectEdge)((edge + 2) % 4);
    CGFloat lo = corner + arrow_half, hi;
    if (vertical) {
        hi = f.size.width - corner - arrow_half;
        frame->_arrowAt = fmax(lo, fmin(NSMidX(r) - f.origin.x, hi));
    } else {
        hi = f.size.height - corner - arrow_half;
        frame->_arrowAt = fmax(lo, fmin(NSMidY(r) - f.origin.y, hi));
    }
    NSRect bubble = [frame _bubble];
    if (content) {
        if ([content superview] != frame)
            [frame addSubview:content];
        [content setFrame:bubble];
    }
    [frame setNeedsDisplay:YES];
    [_host setNeedsDisplay:YES];
}

/* A window of the popover's own under a menu bar item, and the bubble in it. */
- (void)_showUnderStatusItem:(NSStatusBarButton *)button
{
    NSSize size = [self contentSize];
    CGFloat w = size.width + 2 * margin, h = size.height + arrow_length + margin;
    NSScreen *screen = [NSScreen mainScreen];
    NSRect full = [screen frame], visible = [screen visibleFrame];
    NSPoint at = [button _clickedAt];
    CGFloat x = at.x >= 0 ? NSMinX(full) + at.x - w / 2 : NSMaxX(visible) - w - margin;
    x = fmax(NSMinX(visible) + margin, fmin(x, NSMaxX(visible) - margin - w));
    /* the arrow's tip at the foot of the menu bar, as on a Mac: under X the
     * work area may not leave out freemac's menu bar (Topline, 24 points
     * tall, as a Mac's is), so it is left out here too (freemac 1.231) */
    CGFloat top = fmin(NSMaxY(visible), NSMaxY(full) - 24);
    NSRect frame = NSMakeRect(x, top - h, w, h);
    if (!_ownWindow) {
        _ownWindow = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered defer:NO];
        [_ownWindow setReleasedWhenClosed:NO];
        [_ownWindow setOpaque:NO];
        [_ownWindow setBackgroundColor:[NSColor clearColor]];
        [_ownWindow setLevel:NSPopUpMenuWindowLevel];
    } else {
        [_ownWindow setFrame:frame display:NO];
    }
    CGFloat arrowX = at.x >= 0 ? NSMinX(full) + at.x - x : w / 2;
    arrowX = fmax(corner + arrow_half, fmin(arrowX, w - corner - arrow_half));
    [_ownWindow makeKeyAndOrderFront:nil];
    [self showRelativeToRect:NSMakeRect(arrowX - 1, h - 1, 2, 1) ofView:[_ownWindow contentView]
               preferredEdge:NSRectEdgeMinY];
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge
{
    if (view && ![view window] && [view isKindOfClass:[NSStatusBarButton class]] && _content) {
        [self _showUnderStatusItem:(NSStatusBarButton *)view];
        return;
    }
    NSWindow *window = [view window];
    if (!view || !window)
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSPopover: the positioning view must be in a window to show a popover"];
    if (!_content)
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSPopover: a popover needs a content view controller to be shown"];
    [view retain];
    [_positioningView release];
    _positioningView = view;
    _positioningRect = NSIsEmptyRect(rect) ? [view bounds] : rect;
    _preferredEdge = edge;
    if (_shown && window == _window) {
        [self _layOut];
        return;
    }
    if (_shown)
        [self close];
    [self _post:NSPopoverWillShowNotification selector:@selector(popoverWillShow:)];
    [window retain];
    [_window release];
    _window = window;
    if (!_host) {
        _host = [[APopoverHost alloc] initWithFrame:NSZeroRect];
        _host->_popover = self;
        _host->_frame = [[APopoverFrame alloc] initWithFrame:NSZeroRect];
        [_host addSubview:_host->_frame];
    }
    [_content viewWillAppear];
    [window _setOverlayView:_host];
    _shown = YES;
    [self _layOut];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_windowWillClose:) name:NSWindowWillCloseNotification object:window];
    [nc addObserver:self selector:@selector(_windowResignedKey:) name:NSWindowDidResignKeyNotification object:window];
    [_content viewDidAppear];
    [self _post:NSPopoverDidShowNotification selector:@selector(popoverDidShow:)];
}

- (void)close
{
    if (!_shown)
        return;
    [[self retain] autorelease];
    [self _post:NSPopoverWillCloseNotification selector:@selector(popoverWillClose:)];
    [_content viewWillDisappear];
    NSWindow *w = [[_window retain] autorelease];
    /* a field being edited in the bubble ends its editing first */
    NSResponder *first = [w firstResponder];
    if ([first isKindOfClass:[NSView class]] && [(NSView *)first isDescendantOf:_host])
        [w makeFirstResponder:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:w];
    if ([w _overlayView] == _host)
        [w _setOverlayView:nil];
    [[_content view] removeFromSuperview];
    _shown = NO;
    [_window release];
    _window = nil;
    if (_ownWindow && w == _ownWindow)
        [_ownWindow orderOut:nil];
    [_content viewDidDisappear];
    [self _post:NSPopoverDidCloseNotification selector:@selector(popoverDidClose:)];
}
- (BOOL)_mayClose
{
    return ![_delegate respondsToSelector:@selector(popoverShouldClose:)] || [_delegate popoverShouldClose:self];
}
- (void)performClose:(id)sender
{
    if (_shown && [self _mayClose])
        [self close];
}
- (void)_clickedOutside
{
    if (_behavior != NSPopoverBehaviorApplicationDefined && [self _mayClose])
        [self close];
}
- (void)_escape
{
    if ([self _mayClose])
        [self close];
}
- (void)_windowWillClose:(NSNotification *)n { [self close]; }
- (void)_windowResignedKey:(NSNotification *)n
{
    if (_behavior == NSPopoverBehaviorTransient && [self _mayClose])
        [self close];
}
- (void)cancelOperation:(id)sender { [self performClose:sender]; }
@end

/* ---- a view controller presented as a popover (NSViewController.m) ---------------------- */

static char popover_key;
void APresentAsPopover(NSViewController *vc, NSRect rect, NSView *view, NSRectEdge edge, NSInteger behavior)
{
    NSPopover *p = [[NSPopover alloc] init];
    [p setContentViewController:vc];
    [p setBehavior:behavior];
    objc_setAssociatedObject(vc, &popover_key, p, OBJC_ASSOCIATION_RETAIN);
    [p release];
    [p showRelativeToRect:rect ofView:view preferredEdge:edge];
}
BOOL ADismissPopover(NSViewController *vc)
{
    NSPopover *p = objc_getAssociatedObject(vc, &popover_key);
    if (!p)
        return NO;
    [[p retain] autorelease];
    objc_setAssociatedObject(vc, &popover_key, nil, OBJC_ASSOCIATION_RETAIN);
    [p close];
    return YES;
}
