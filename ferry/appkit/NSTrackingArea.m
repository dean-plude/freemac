/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: tracking areas, tracking rectangles and cursor
 * rectangles, written from Apple's public documentation. A view keeps its
 * tracking areas; each mouse event a window is sent (see NSWindow's
 * sendEvent:) is checked against every area of every view shown in the
 * window, by geometry and not by which view is on top, as on a Mac. An
 * area the mouse goes into or out of tells its owner with mouseEntered:
 * and mouseExited:, cursorUpdate: when it asks for cursor updates, and
 * mouseMoved: while the mouse moves inside it, whether or not the window
 * takes mouse-moved events. An area is live only as its options say (in
 * the key window, in the active app, while its view is first responder,
 * or always); while a button is held an area that isn't enabled during
 * drags keeps its state until the button comes up. Exits are sent before
 * entries. updateTrackingAreas is sent, once the run loop next turns or a
 * mouse event comes, to each view whose frame or bounds changed (and the
 * views inside it) and to each view put in a window. The older tracking
 * rectangles are kept as areas of their own, with their tags and user
 * data, but not listed by trackingAreas; cursor rectangles are built when
 * needed by sending resetCursorRects to each view, and set the cursor of
 * the one the mouse is in. Built without ARC. */
#import "AInternal.h"

@implementation NSTrackingArea {
@public
    NSRect _rect;
    NSTrackingAreaOptions _options;
    id _owner;                  /* not retained, as on a Mac */
    NSDictionary *_userInfo;
    NSView *_view;              /* not retained: the view it was added to */
    BOOL _inside, _legacy;
    NSTrackingRectTag _tag;
    void *_userData;
}

- (instancetype)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options owner:(id)owner
                    userInfo:(NSDictionary *)userInfo
{
    if ((self = [super init])) {
        _rect = rect;
        _options = options;
        _owner = owner;
        _userInfo = [userInfo copy];
    }
    return self;
}
- (instancetype)init { return [self initWithRect:NSZeroRect options:0 owner:nil userInfo:nil]; }
- (void)dealloc
{
    [_userInfo release];
    [super dealloc];
}
- (NSRect)rect { return _rect; }
- (NSTrackingAreaOptions)options { return _options; }
- (id)owner { return _owner; }
- (NSDictionary *)userInfo { return _userInfo; }
- (id)copyWithZone:(NSZone *)zone
{
    return [[NSTrackingArea allocWithZone:zone] initWithRect:_rect options:_options owner:_owner userInfo:_userInfo];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSDictionary *info = [coder decodeObjectForKey:@"NSTrackingUserInfo"];
    return [self initWithRect:[coder decodeRectForKey:@"NSTrackingRect"]
                      options:(NSTrackingAreaOptions)[coder decodeInt64ForKey:@"NSTrackingOptions"]
                        owner:[coder decodeObjectForKey:@"NSTrackingOwner"]
                     userInfo:[info isKindOfClass:[NSDictionary class]] ? info : nil];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeRect:_rect forKey:@"NSTrackingRect"];
    [coder encodeInt64:(int64_t)_options forKey:@"NSTrackingOptions"];
    if (_userInfo)
        [coder encodeObject:_userInfo forKey:@"NSTrackingUserInfo"];
    if (_owner)
        [coder encodeConditionalObject:_owner forKey:@"NSTrackingOwner"];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSTrackingArea %p: rect=%@ options=0x%lx owner=%p>", self,
                                      NSStringFromRect(_rect), (unsigned long)_options, _owner];
}
@end

/* ---- a window's tracking state -------------------------------------------------------- */

@interface ACursorRect : NSObject {
@public
    NSView *view;               /* not retained; dropped when the view leaves */
    NSRect rect;
    NSCursor *cursor;
}
@end
@implementation ACursorRect
- (void)dealloc
{
    [cursor release];
    [super dealloc];
}
@end

@interface ATrackState : NSObject {
@public
    NSMutableArray *inside;     /* areas the mouse is in, outermost first */
    NSMutableArray *cursorRects;
    NSMutableSet *changed;      /* views whose geometry changed, as pointers (compared only) */
    BOOL cursorRectsValid, cursorRectsDisabled, flushScheduled, wantsMoves;
    ACursorRect *cursorRect;    /* the cursor rectangle the mouse is in, if any */
    BOOL cursorStale;           /* the cursor shown came from a rectangle since dropped */
}
@end
@implementation ATrackState
- (instancetype)init
{
    if ((self = [super init])) {
        inside = [[NSMutableArray alloc] init];
        cursorRects = [[NSMutableArray alloc] init];
        changed = [[NSMutableSet alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [inside release];
    [cursorRects release];
    [changed release];
    [super dealloc];
}
@end

static char state_key, areas_key;

static ATrackState *state_of(NSWindow *w, BOOL make)
{
    if (!w)
        return nil;
    ATrackState *s = objc_getAssociatedObject(w, &state_key);
    if (!s && make) {
        s = [[ATrackState alloc] init];
        objc_setAssociatedObject(w, &state_key, s, OBJC_ASSOCIATION_RETAIN);
        [s release];
    }
    return s;
}

static NSMutableArray *areas_of(NSView *v, BOOL make)
{
    NSMutableArray *a = objc_getAssociatedObject(v, &areas_key);
    if (!a && make) {
        a = [[NSMutableArray alloc] init];
        objc_setAssociatedObject(v, &areas_key, a, OBJC_ASSOCIATION_RETAIN);
        [a release];
    }
    return a;
}

/* The views a window's tracking looks at: the content view and those in
 * it, back to front. */
static void collect(NSView *v, BOOL hidden, NSMutableArray *out)
{
    if (!v || (!hidden && [v isHidden]))
        return;
    [out addObject:v];
    for (NSView *sub in [v subviews])
        collect(sub, hidden, out);
}
static NSArray *views_of(NSWindow *w, BOOL hidden)
{
    NSMutableArray *out = [NSMutableArray array];
    collect([w contentView], hidden, out);
    return out;
}

static void note_wants_moves(NSWindow *w)
{
    ATrackState *s = state_of(w, YES);
    s->wantsMoves = YES;
}

/* ---- updateTrackingAreas ---------------------------------------------------------------- */

@interface NSWindow (ATracking)
- (void)_ferryUpdateTracking;
@end

/* Each view marked as changed, and each view inside one, is told. */
static void flush(NSWindow *w)
{
    ATrackState *s = state_of(w, NO);
    if (!s || ![s->changed count])
        return;
    NSMutableArray *due = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray array];
    if ([w contentView])
        [stack addObject:@[ [w contentView], @NO ]];
    while ([stack count]) {
        NSArray *top = [[[stack lastObject] retain] autorelease];
        [stack removeLastObject];
        NSView *v = top[0];
        BOOL under = [top[1] boolValue] || [s->changed containsObject:[NSValue valueWithPointer:v]];
        if (under)
            [due addObject:v];
        NSArray *subs = [v subviews];
        for (NSInteger i = (NSInteger)[subs count] - 1; i >= 0; i--)
            [stack addObject:@[ subs[(NSUInteger)i], @(under) ]];
    }
    [s->changed removeAllObjects];
    for (NSView *v in due)
        if ([v window] == w)
            [v updateTrackingAreas];
}

@implementation NSWindow (ATracking)
- (void)_ferryUpdateTracking
{
    ATrackState *s = state_of(self, NO);
    if (s)
        s->flushScheduled = NO;
    flush(self);
}
@end

static void mark(NSView *v, NSWindow *w)
{
    ATrackState *s = state_of(w, YES);
    [s->changed addObject:[NSValue valueWithPointer:v]];
    s->cursorRectsValid = NO;
    if (!s->flushScheduled) {
        s->flushScheduled = YES;
        [w performSelector:@selector(_ferryUpdateTracking) withObject:nil afterDelay:0
                   inModes:@[ NSRunLoopCommonModes ]];
    }
}

void ATrackingGeometryChanged(NSView *view)
{
    NSWindow *w = [view window];
    if (w)
        mark(view, w);
}

void ATrackingViewMoving(NSView *view, NSWindow *from, NSWindow *to)
{
    ATrackState *s = state_of(from, NO);
    if (s) {
        /* what the view had in the old window goes, quietly */
        for (NSTrackingArea *a in areas_of(view, NO)) {
            a->_inside = (a->_options & NSTrackingAssumeInside) != 0;
            [s->inside removeObjectIdenticalTo:a];
        }
        for (NSInteger i = (NSInteger)[s->cursorRects count] - 1; i >= 0; i--) {
            ACursorRect *r = s->cursorRects[(NSUInteger)i];
            if (r->view == view) {
                if (s->cursorRect == r)
                    s->cursorRect = nil, s->cursorStale = YES;
                [s->cursorRects removeObjectAtIndex:(NSUInteger)i];
            }
        }
        [s->changed removeObject:[NSValue valueWithPointer:view]];
        s->cursorRectsValid = NO;
    }
    if (to) {
        mark(view, to);
        if ([areas_of(view, NO) count])
            note_wants_moves(to);
    }
}

BOOL ATrackingWantsMoves(NSWindow *window)
{
    ATrackState *s = state_of(window, NO);
    return s && (s->wantsMoves || !s->cursorRectsValid || [s->cursorRects count]);
}

/* ---- NSView's tracking areas and rectangles ------------------------------------------- */

static NSTrackingRectTag next_tag;

@implementation NSView (NSTrackingArea)
- (void)addTrackingArea:(NSTrackingArea *)area
{
    if (!area || [areas_of(self, YES) indexOfObjectIdenticalTo:area] != NSNotFound)
        return;
    area->_view = self;
    area->_inside = (area->_options & NSTrackingAssumeInside) != 0;
    [areas_of(self, YES) addObject:area];
    if ([self window])
        note_wants_moves([self window]);
}
- (void)removeTrackingArea:(NSTrackingArea *)area
{
    NSMutableArray *areas = areas_of(self, NO);
    if (!area || [areas indexOfObjectIdenticalTo:area] == NSNotFound)
        return;
    [area retain];
    ATrackState *s = state_of([self window], NO);
    if (s)
        [s->inside removeObjectIdenticalTo:area];
    area->_view = nil;
    [areas removeObjectIdenticalTo:area];
    [area release];
}
- (NSArray *)trackingAreas
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSTrackingArea *a in areas_of(self, NO))
        if (!a->_legacy)
            [out addObject:a];
    return out;
}
- (void)updateTrackingAreas {}

- (NSTrackingRectTag)addTrackingRect:(NSRect)rect owner:(id)owner userData:(void *)data assumeInside:(BOOL)flag
{
    NSTrackingArea *a = [[NSTrackingArea alloc]
        initWithRect:rect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | (flag ? NSTrackingAssumeInside : 0)
               owner:owner
            userInfo:nil];
    a->_legacy = YES;
    a->_tag = ++next_tag;
    a->_userData = data;
    [self addTrackingArea:a];
    [a release];
    return a->_tag;
}
- (void)removeTrackingRect:(NSTrackingRectTag)tag
{
    for (NSTrackingArea *a in [[areas_of(self, NO) copy] autorelease])
        if (a->_legacy && a->_tag == tag)
            [self removeTrackingArea:a];
}

- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)cursor
{
    ATrackState *s = state_of([self window], YES);
    if (!s || !cursor || NSIsEmptyRect(rect))
        return;
    ACursorRect *r = [[ACursorRect alloc] init];
    r->view = self;
    r->rect = rect;
    r->cursor = [cursor retain];
    [s->cursorRects addObject:r];
    [r release];
}
- (void)removeCursorRect:(NSRect)rect cursor:(NSCursor *)cursor
{
    ATrackState *s = state_of([self window], NO);
    if (!s)
        return;
    for (NSInteger i = (NSInteger)[s->cursorRects count] - 1; i >= 0; i--) {
        ACursorRect *r = s->cursorRects[(NSUInteger)i];
        if (r->view == self && r->cursor == cursor && NSEqualRects(r->rect, rect)) {
            if (s->cursorRect == r)
                s->cursorRect = nil, s->cursorStale = YES;
            [s->cursorRects removeObjectAtIndex:(NSUInteger)i];
            return;
        }
    }
}
- (void)discardCursorRects
{
    ATrackState *s = state_of([self window], NO);
    if (!s)
        return;
    for (NSInteger i = (NSInteger)[s->cursorRects count] - 1; i >= 0; i--) {
        ACursorRect *r = s->cursorRects[(NSUInteger)i];
        if (r->view == self) {
            if (s->cursorRect == r)
                s->cursorRect = nil, s->cursorStale = YES;
            [s->cursorRects removeObjectAtIndex:(NSUInteger)i];
        }
    }
}
- (void)resetCursorRects {}
@end

/* ---- NSWindow's cursor rectangles ------------------------------------------------------- */

@implementation NSWindow (NSCursorRects)
- (void)invalidateCursorRectsForView:(NSView *)view
{
    ATrackState *s = state_of(self, YES);
    s->cursorRectsValid = NO;
}
- (void)discardCursorRects
{
    ATrackState *s = state_of(self, NO);
    if (!s)
        return;
    [s->cursorRects removeAllObjects];
    if (s->cursorRect)
        s->cursorRect = nil, s->cursorStale = YES;
}
- (void)resetCursorRects
{
    ATrackState *s = state_of(self, YES);
    [self discardCursorRects];
    for (NSView *v in views_of(self, NO))
        [v resetCursorRects];
    s->cursorRectsValid = YES;
}
- (void)enableCursorRects { state_of(self, YES)->cursorRectsDisabled = NO; }
- (void)disableCursorRects { state_of(self, YES)->cursorRectsDisabled = YES; }
- (BOOL)areCursorRectsEnabled
{
    ATrackState *s = state_of(self, NO);
    return !s || !s->cursorRectsDisabled;
}
@end

/* ---- events ---------------------------------------------------------------------------- */

@implementation NSResponder (NSCursorUpdate)
- (void)cursorUpdate:(NSEvent *)event { [[self nextResponder] cursorUpdate:event]; }
@end

static BOOL is_live(NSTrackingArea *a, NSWindow *w)
{
    NSTrackingAreaOptions o = a->_options;
    if (o & NSTrackingActiveAlways)
        return YES;
    if (o & NSTrackingActiveInActiveApp)
        return [NSApp isActive] || [w isKeyWindow];
    if (o & NSTrackingActiveInKeyWindow)
        return [w isKeyWindow];
    if (o & NSTrackingActiveWhenFirstResponder)
        return [w isKeyWindow] && [w firstResponder] == (NSResponder *)a->_view;
    return NO;
}

static BOOL is_in(NSTrackingArea *a, NSPoint inWindow)
{
    NSView *v = a->_view;
    NSRect r = a->_options & NSTrackingInVisibleRect ? [v visibleRect] : a->_rect;
    return [v mouse:[v convertPoint:inWindow fromView:nil] inRect:r];
}

static void tell(NSTrackingArea *a, NSEventType type, NSWindow *w, NSPoint p, NSEvent *cause)
{
    id owner = a->_owner;
    SEL sel = type == NSEventTypeMouseEntered  ? @selector(mouseEntered:)
              : type == NSEventTypeMouseExited ? @selector(mouseExited:)
                                               : @selector(cursorUpdate:);
    if (![owner respondsToSelector:sel])
        return;
    NSEvent *e = a->_legacy ? ATrackingEvent(type, p, cause, w, a->_tag, a->_userData, nil)
                            : ATrackingEvent(type, p, cause, w, (NSInteger)(intptr_t)a, (void *)a->_userInfo, a);
    ((void (*)(id, SEL, NSEvent *))objc_msgSend)(owner, sel, e);
}

static BOOL is_drag(NSEventType t)
{
    return t == NSEventTypeLeftMouseDragged || t == NSEventTypeRightMouseDragged || t == NSEventTypeOtherMouseDragged;
}

static void update_cursor_rects(NSWindow *w, ATrackState *s, NSPoint p)
{
    if (s->cursorRectsDisabled)
        return;
    if (!s->cursorRectsValid)
        [w resetCursorRects];
    ACursorRect *found = nil;
    for (ACursorRect *r in s->cursorRects) {
        NSView *v = r->view;
        if ([v window] != w || [v isHiddenOrHasHiddenAncestor])
            continue;
        NSRect shown = NSIntersectionRect(r->rect, [v visibleRect]);
        if ([v mouse:[v convertPoint:p fromView:nil] inRect:shown])
            found = r;      /* the last one built is the frontmost */
    }
    BOOL stale = s->cursorStale;
    s->cursorStale = NO;
    if (found == s->cursorRect && !(stale && !found))
        return;
    s->cursorRect = found;
    [found ? found->cursor : [NSCursor arrowCursor] set];
}

static void track(NSWindow *w, NSEvent *e, BOOL leaving)
{
    ATrackState *s = state_of(w, NO);
    if (!s)
        return;
    flush(w);
    NSEventType t = [e type];
    BOOL drag = is_drag(t);
    NSPoint p = [e locationInWindow];
    if (t == NSEventTypeMouseMoved || drag)
        ACursorMouseMoved();

    NSMutableArray *areas = [NSMutableArray array];
    for (NSView *v in views_of(w, NO))
        [areas addObjectsFromArray:areas_of(v, NO) ?: @[]];
    NSMutableArray *exits = [NSMutableArray array], *entries = [NSMutableArray array];
    BOOL hadCursorArea = NO;
    for (NSTrackingArea *a in s->inside)
        if (a->_options & NSTrackingCursorUpdate)
            hadCursorArea = YES;
    /* an area no longer shown (its view hidden or gone) goes quietly */
    for (NSTrackingArea *a in [[s->inside copy] autorelease])
        if ([areas indexOfObjectIdenticalTo:a] == NSNotFound)
            [s->inside removeObjectIdenticalTo:a];
    for (NSTrackingArea *a in areas) {
        if (drag && !(a->_options & NSTrackingEnabledDuringMouseDrag))
            continue;   /* until the button comes up */
        BOOL now = !leaving && is_live(a, w) && is_in(a, p);
        if (a->_inside && !now) {
            a->_inside = NO;
            [exits insertObject:a atIndex:0];   /* innermost first */
        } else if (!a->_inside && now) {
            a->_inside = YES;
            [entries addObject:a];
        }
    }
    [s->inside removeAllObjects];
    for (NSTrackingArea *a in areas)
        if (a->_inside)
            [s->inside addObject:a];

    if (!drag) {
        if (leaving) {
            if (s->cursorRect) {
                s->cursorRect = nil;
                [[NSCursor arrowCursor] set];
            }
        } else {
            update_cursor_rects(w, s, p);
        }
    }
    for (NSTrackingArea *a in exits)
        if (a->_options & NSTrackingMouseEnteredAndExited)
            tell(a, NSEventTypeMouseExited, w, p, e);
    for (NSTrackingArea *a in entries)
        if (a->_options & NSTrackingMouseEnteredAndExited)
            tell(a, NSEventTypeMouseEntered, w, p, e);
    BOOL hasCursorArea = NO;
    for (NSTrackingArea *a in entries)
        if (a->_options & NSTrackingCursorUpdate) {
            tell(a, NSEventTypeCursorUpdate, w, p, e);
            hasCursorArea = YES;
        }
    if (!hasCursorArea)
        for (NSTrackingArea *a in s->inside)
            if (a->_options & NSTrackingCursorUpdate)
                hasCursorArea = YES;
    if (hadCursorArea && !hasCursorArea && !s->cursorRect && !drag)
        [[NSCursor arrowCursor] set];
    if (t == NSEventTypeMouseMoved)
        for (NSTrackingArea *a in [[s->inside copy] autorelease])
            if ((a->_options & NSTrackingMouseMoved) && a->_inside &&
                [a->_owner respondsToSelector:@selector(mouseMoved:)])
                [a->_owner mouseMoved:e];
}

/* GTK's pointer leaving the window: an exited event with this tracking
 * number, which no tracking area or rectangle has. */
#define WINDOW_EXIT NSIntegerMin

NSEvent *ATrackingWindowExitEvent(NSWindow *window, NSPoint location)
{
    return ATrackingEvent(NSEventTypeMouseExited, location, nil, window, WINDOW_EXIT, NULL, nil);
}

BOOL ATrackEvent(NSWindow *w, NSEvent *e)
{
    switch ([e type]) {
    case NSEventTypeMouseEntered:
    case NSEventTypeMouseExited:
    case NSEventTypeCursorUpdate: {
        if ([e trackingNumber] == WINDOW_EXIT) {
            track(w, e, YES);
            return YES;
        }
        /* one made by the app: to its area's owner */
        NSTrackingArea *a = [e trackingArea];
        id owner = a ? a->_owner : nil;
        if (!owner)
            return YES;
        if ([e type] == NSEventTypeMouseEntered)
            [owner mouseEntered:e];
        else if ([e type] == NSEventTypeMouseExited)
            [owner mouseExited:e];
        else
            [owner cursorUpdate:e];
        return YES;
    }
    case NSEventTypeMouseMoved:
    case NSEventTypeLeftMouseDragged:
    case NSEventTypeRightMouseDragged:
    case NSEventTypeOtherMouseDragged:
    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown:
    case NSEventTypeOtherMouseDown:
    case NSEventTypeLeftMouseUp:
    case NSEventTypeRightMouseUp:
    case NSEventTypeOtherMouseUp:
        track(w, e, NO);
        return NO;
    default:
        return NO;
    }
}
