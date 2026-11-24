/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSSplitView, written from Apple's public documentation.
 * Its subviews sit side by side (vertical dividers) or one above another
 * (horizontal dividers), with a divider between each two that can be
 * dragged. The delegate can limit where a divider goes, let a subview
 * collapse, and choose how the subviews share a change of size; without
 * it, the subview with the lowest holding priority takes the change. A
 * collapsed subview is hidden, as on a Mac. With an autosave name the
 * subviews' frames are kept in the user defaults under "NSSplitView
 * Subview Frames <name>", in the form a Mac uses. */
#import "AInternal.h"

NSNotificationName const NSSplitViewWillResizeSubviewsNotification = @"NSSplitViewWillResizeSubviewsNotification";
NSNotificationName const NSSplitViewDidResizeSubviewsNotification = @"NSSplitViewDidResizeSubviewsNotification";

@implementation NSSplitView {
    BOOL _vertical, _arrangesAll;
    NSSplitViewDividerStyle _style;
    id _delegate;
    NSString *_autosaveName;
    NSMutableDictionary *_holding; /* index -> priority */
    NSInteger _dragging;           /* the divider being dragged, or -1 */
    CGFloat _grab;                 /* where in the divider it was taken */
}
- (void)_setUp
{
    _style = NSSplitViewDividerStyleThick;
    _arrangesAll = YES;
    _dragging = -1;
    _holding = [[NSMutableDictionary alloc] init];
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
        _vertical = [coder decodeBoolForKey:@"NSIsVertical"];
        if ([coder containsValueForKey:@"NSDividerStyle"])
            _style = (NSSplitViewDividerStyle)[coder decodeIntegerForKey:@"NSDividerStyle"];
        if (_style < NSSplitViewDividerStyleThick || _style > NSSplitViewDividerStylePaneSplitter)
            _style = NSSplitViewDividerStyleThick;
        _delegate = [coder decodeObjectForKey:@"NSDelegate"];
        NSString *name = [coder decodeObjectForKey:@"NSAutosaveName"];
        if ([name isKindOfClass:[NSString class]] && [name length])
            [self setAutosaveName:name];
    }
    return self;
}
- (void)dealloc
{
    [_autosaveName release];
    [_holding release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }

/* ---- settings ---------------------------------------------------------------------- */

- (BOOL)isVertical { return _vertical; }
- (void)setVertical:(BOOL)f
{
    if (f == _vertical)
        return;
    _vertical = f;
    [self adjustSubviews];
}
- (NSSplitViewDividerStyle)dividerStyle { return _style; }
- (void)setDividerStyle:(NSSplitViewDividerStyle)s
{
    _style = s;
    [self adjustSubviews];
}
- (CGFloat)dividerThickness
{
    switch (_style) {
    case NSSplitViewDividerStyleThin:
        return 1;
    case NSSplitViewDividerStylePaneSplitter:
        return 10;
    default:
        return 9;
    }
}
- (NSColor *)dividerColor
{
    return _style == NSSplitViewDividerStyleThin ? [NSColor separatorColor]
                                                  : [NSColor colorWithCalibratedWhite:0.93 alpha:1];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)arrangesAllSubviews { return _arrangesAll; }
- (void)setArrangesAllSubviews:(BOOL)f
{
    if (!f)
        AWarnOnce("NSSplitView arrangesAllSubviews = NO (every subview is still arranged)");
}
- (NSArray *)arrangedSubviews { return [self subviews]; }
- (void)addArrangedSubview:(NSView *)v { [self addSubview:v]; }
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i
{
    NSArray *now = [self subviews];
    if (i >= (NSInteger)[now count])
        [self addSubview:v];
    else
        [self addSubview:v positioned:NSWindowBelow relativeTo:[now objectAtIndex:i]];
}
- (void)removeArrangedSubview:(NSView *)v { [v removeFromSuperview]; }
- (NSLayoutPriority)holdingPriorityForSubviewAtIndex:(NSInteger)i
{
    NSNumber *n = [_holding objectForKey:@(i)];
    return n ? [n floatValue] : NSLayoutPriorityDefaultLow;
}
- (void)setHoldingPriority:(NSLayoutPriority)p forSubviewAtIndex:(NSInteger)i
{
    [_holding setObject:@(p) forKey:@(i)];
}

/* ---- geometry ---------------------------------------------------------------------- */

/* Along the dividers' axis: x for vertical dividers, y (downwards) otherwise. */
- (CGFloat)_length { return _vertical ? [self bounds].size.width : [self bounds].size.height; }
- (CGFloat)_start:(NSView *)v { return [v isHidden] ? 0 : (_vertical ? NSMinX([v frame]) : NSMinY([v frame])); }
- (CGFloat)_size:(NSView *)v { return [v isHidden] ? 0 : (_vertical ? [v frame].size.width : [v frame].size.height); }

- (BOOL)isSubviewCollapsed:(NSView *)v { return [v superview] == self && [v isHidden]; }

/* Lays the subviews out end to end at the given sizes, a divider between
 * each two; a collapsed subview takes no room. */
- (void)_layOut:(CGFloat *)sizes
{
    NSArray *views = [self subviews];
    CGFloat t = [self dividerThickness], at = 0;
    NSRect b = [self bounds];
    for (NSUInteger i = 0; i < [views count]; i++) {
        NSView *v = [views objectAtIndex:i];
        if ([v isHidden]) {
            /* keep its size for when it comes back */
            continue;
        }
        CGFloat s = fmax(0, round(sizes[i]));
        [v setFrame:_vertical ? NSMakeRect(at, 0, s, b.size.height) : NSMakeRect(0, at, b.size.width, s)];
        at += s + t;
    }
    [self setNeedsDisplay:YES];
}
- (NSUInteger)_visibleCount
{
    NSUInteger n = 0;
    for (NSView *v in [self subviews])
        n += ![v isHidden];
    return n;
}
- (CGFloat)_room
{
    NSUInteger n = [self _visibleCount];
    return [self _length] - (n > 1 ? (n - 1) * [self dividerThickness] : 0);
}

- (void)_post:(NSString *)name selector:(SEL)sel
{
    NSNotification *n = [NSNotification notificationWithName:name object:self];
    if ([_delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

/* Shares the room among the visible subviews in proportion to their sizes now. */
- (void)adjustSubviews
{
    NSArray *views = [self subviews];
    NSUInteger n = [views count];
    if (!n)
        return;
    [self _post:NSSplitViewWillResizeSubviewsNotification selector:@selector(splitViewWillResizeSubviews:)];
    CGFloat sizes[n], total = 0, room = [self _room];
    NSUInteger visible = 0;
    for (NSUInteger i = 0; i < n; i++) {
        sizes[i] = [self _size:[views objectAtIndex:i]];
        total += sizes[i];
        visible += ![[views objectAtIndex:i] isHidden];
    }
    CGFloat given = 0;
    NSInteger last = -1;
    for (NSUInteger i = 0; i < n; i++) {
        if ([[views objectAtIndex:i] isHidden])
            continue;
        sizes[i] = total > 0 ? floor(room * sizes[i] / total) : floor(room / visible);
        given += sizes[i];
        last = i;
    }
    if (last >= 0)
        sizes[last] += room - given; /* what rounding left over */
    [self _layOut:sizes];
    [self _post:NSSplitViewDidResizeSubviewsNotification selector:@selector(splitViewDidResizeSubviews:)];
}

/* A change of size goes to the subviews the delegate lets change, those with
 * the lowest holding priority first, shared in proportion to their sizes. */
- (void)resizeSubviewsWithOldSize:(NSSize)old
{
    if ([_delegate respondsToSelector:@selector(splitView:resizeSubviewsWithOldSize:)]) {
        [_delegate splitView:self resizeSubviewsWithOldSize:old];
        return;
    }
    NSArray *views = [self subviews];
    NSUInteger n = [views count];
    if (!n)
        return;
    CGFloat sizes[n], used = 0;
    for (NSUInteger i = 0; i < n; i++) {
        sizes[i] = [self _size:[views objectAtIndex:i]];
        used += sizes[i];
    }
    CGFloat change = [self _room] - used;
    /* lowest priority first; a subview never goes below nothing */
    NSMutableArray *levels = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) {
        NSNumber *p = @([self holdingPriorityForSubviewAtIndex:i]);
        if (![levels containsObject:p])
            [levels addObject:p];
    }
    [levels sortUsingSelector:@selector(compare:)];
    for (NSNumber *level in levels) {
        if (fabs(change) < 0.5)
            break;
        CGFloat share = 0;
        NSUInteger count = 0;
        for (NSUInteger i = 0; i < n; i++) {
            NSView *v = [views objectAtIndex:i];
            if ([v isHidden] || [self holdingPriorityForSubviewAtIndex:i] != [level floatValue])
                continue;
            if ([_delegate respondsToSelector:@selector(splitView:shouldAdjustSizeOfSubview:)] &&
                ![_delegate splitView:self shouldAdjustSizeOfSubview:v])
                continue;
            share += sizes[i];
            count++;
        }
        if (!count)
            continue;
        CGFloat left = change;
        for (NSUInteger i = 0; i < n; i++) {
            NSView *v = [views objectAtIndex:i];
            if ([v isHidden] || [self holdingPriorityForSubviewAtIndex:i] != [level floatValue])
                continue;
            if ([_delegate respondsToSelector:@selector(splitView:shouldAdjustSizeOfSubview:)] &&
                ![_delegate splitView:self shouldAdjustSizeOfSubview:v])
                continue;
            CGFloat part = share > 0 ? change * sizes[i] / share : change / count;
            CGFloat now = fmax(0, sizes[i] + part);
            left -= now - sizes[i];
            sizes[i] = now;
        }
        change = left;
    }
    if (fabs(change) >= 0.5) {
        /* everyone held: the last visible subview takes it */
        for (NSInteger i = n - 1; i >= 0; i--)
            if (![[views objectAtIndex:i] isHidden]) {
                sizes[i] = fmax(0, sizes[i] + change);
                break;
            }
    }
    [self _post:NSSplitViewWillResizeSubviewsNotification selector:@selector(splitViewWillResizeSubviews:)];
    [self _layOut:sizes];
    [self _post:NSSplitViewDidResizeSubviewsNotification selector:@selector(splitViewDidResizeSubviews:)];
}

/* The divider after subview i: where it starts along the axis. */
- (CGFloat)positionOfDividerAtIndex:(NSInteger)i
{
    NSArray *views = [self subviews];
    if (i < 0 || i >= (NSInteger)[views count])
        return 0;
    NSView *v = [views objectAtIndex:i];
    if (![v isHidden])
        return [self _start:v] + [self _size:v];
    /* a collapsed subview: where the visible one before it ends, or 0 */
    for (NSInteger j = i - 1; j >= 0; j--) {
        NSView *u = [views objectAtIndex:j];
        if (![u isHidden])
            return [self _start:u] + [self _size:u];
    }
    return i == (NSInteger)[views count] - 1 ? [self _length] : 0;
}
- (NSRect)_dividerRect:(NSInteger)i
{
    CGFloat at = [self positionOfDividerAtIndex:i], t = [self dividerThickness];
    NSRect b = [self bounds];
    return _vertical ? NSMakeRect(at, 0, t, b.size.height) : NSMakeRect(0, at, b.size.width, t);
}
- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)i
{
    return i > 0 ? [self positionOfDividerAtIndex:i - 1] + [self dividerThickness] : 0;
}
- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)i
{
    NSInteger n = [[self subviews] count];
    CGFloat end = i + 1 < n - 1 ? [self positionOfDividerAtIndex:i + 1] : [self _length];
    return fmax(0, end - [self dividerThickness]);
}

/* Moves divider i, keeping it between its neighbours; the subviews either
 * side of it change size. */
- (void)setPosition:(CGFloat)pos ofDividerAtIndex:(NSInteger)i
{
    NSArray *views = [self subviews];
    NSInteger n = [views count];
    if (i < 0 || i >= n - 1)
        return;
    CGFloat lo = [self minPossiblePositionOfDividerAtIndex:i], hi = [self maxPossiblePositionOfDividerAtIndex:i];
    pos = round(fmin(fmax(pos, lo), hi));
    NSView *before = [views objectAtIndex:i], *after = [views objectAtIndex:i + 1];
    CGFloat t = [self dividerThickness], end = hi + t;
    /* dragging a collapsed subview open, or another closed */
    [before setHidden:NO];
    [after setHidden:NO];
    [self _post:NSSplitViewWillResizeSubviewsNotification selector:@selector(splitViewWillResizeSubviews:)];
    NSRect b = [self bounds];
    CGFloat start = lo;
    if (_vertical) {
        [before setFrame:NSMakeRect(start, 0, pos - start, b.size.height)];
        [after setFrame:NSMakeRect(pos + t, 0, fmax(0, end - pos - t), b.size.height)];
    } else {
        [before setFrame:NSMakeRect(0, start, b.size.width, pos - start)];
        [after setFrame:NSMakeRect(0, pos + t, b.size.width, fmax(0, end - pos - t))];
    }
    [self setNeedsDisplay:YES];
    [self _post:NSSplitViewDidResizeSubviewsNotification selector:@selector(splitViewDidResizeSubviews:)];
}

/* ---- dragging ---------------------------------------------------------------------- */

- (NSInteger)_dividerAt:(NSPoint)p
{
    NSInteger n = [[self subviews] count];
    for (NSInteger i = 0; i < n - 1; i++) {
        NSRect r = [self _dividerRect:i];
        if ([_delegate respondsToSelector:@selector(splitView:effectiveRect:forDrawnRect:ofDividerAtIndex:)])
            r = [_delegate splitView:self effectiveRect:r forDrawnRect:r ofDividerAtIndex:i];
        else if (_style == NSSplitViewDividerStyleThin)
            r = _vertical ? NSInsetRect(r, -3, 0) : NSInsetRect(r, 0, -3); /* easier to take hold of */
        if (NSPointInRect(p, r))
            return i;
        if ([_delegate respondsToSelector:@selector(splitView:additionalEffectiveRectOfDividerAtIndex:)] &&
            NSPointInRect([self convertPoint:p toView:nil],
                          [self convertRect:[_delegate splitView:self additionalEffectiveRectOfDividerAtIndex:i]
                                     toView:nil]))
            return i;
    }
    return -1;
}
- (NSView *)hitTest:(NSPoint)p
{
    /* a divider belongs to the split view, even where a subview reaches into it */
    NSView *hit = [super hitTest:p];
    if (hit && ![self isHidden]) {
        NSPoint mine = [self convertPoint:p fromView:[self superview]];
        if ([self _dividerAt:mine] >= 0)
            return self;
    }
    return hit;
}
- (CGFloat)_constrained:(CGFloat)pos divider:(NSInteger)i
{
    CGFloat lo = [self minPossiblePositionOfDividerAtIndex:i], hi = [self maxPossiblePositionOfDividerAtIndex:i];
    CGFloat min = lo, max = hi;
    if ([_delegate respondsToSelector:@selector(splitView:constrainMinCoordinate:ofSubviewAt:)])
        min = fmax(lo, [_delegate splitView:self constrainMinCoordinate:lo ofSubviewAt:i]);
    if ([_delegate respondsToSelector:@selector(splitView:constrainMaxCoordinate:ofSubviewAt:)])
        max = fmin(hi, [_delegate splitView:self constrainMaxCoordinate:hi ofSubviewAt:i]);
    if ([_delegate respondsToSelector:@selector(splitView:constrainSplitPosition:ofSubviewAt:)])
        pos = [_delegate splitView:self constrainSplitPosition:pos ofSubviewAt:i];
    NSArray *views = [self subviews];
    BOOL canCollapse = [_delegate respondsToSelector:@selector(splitView:canCollapseSubview:)];
    /* past halfway to a limit, a subview that may collapse does */
    if (pos < min) {
        if (canCollapse && pos < (lo + min) / 2 && [_delegate splitView:self canCollapseSubview:[views objectAtIndex:i]])
            return -1;
        return min;
    }
    if (pos > max) {
        if (canCollapse && pos > (max + hi) / 2 &&
            [_delegate splitView:self canCollapseSubview:[views objectAtIndex:i + 1]])
            return -2;
        return max;
    }
    return pos;
}
- (void)_collapse:(NSView *)v divider:(NSInteger)i
{
    if ([v isHidden])
        return;
    [self _post:NSSplitViewWillResizeSubviewsNotification selector:@selector(splitViewWillResizeSubviews:)];
    NSArray *views = [self subviews];
    NSView *other = [views objectAtIndex:v == [views objectAtIndex:i] ? i + 1 : i];
    CGFloat gain = [self _size:v] + [self dividerThickness];
    [v setHidden:YES];
    NSRect f = [other frame];
    if (_vertical) {
        if (v == [views objectAtIndex:i])
            f.origin.x -= gain;
        f.size.width += gain;
    } else {
        if (v == [views objectAtIndex:i])
            f.origin.y -= gain;
        f.size.height += gain;
    }
    [other setFrame:f];
    [self setNeedsDisplay:YES];
    [self _post:NSSplitViewDidResizeSubviewsNotification selector:@selector(splitViewDidResizeSubviews:)];
}
- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    _dragging = [self _dividerAt:p];
    if (_dragging < 0) {
        [super mouseDown:e];
        return;
    }
    _grab = (_vertical ? p.x : p.y) - [self positionOfDividerAtIndex:_dragging];
    if ([e clickCount] == 2 && [_delegate respondsToSelector:@selector(splitView:shouldCollapseSubview:forDoubleClickOnDividerAtIndex:)]) {
        NSArray *views = [self subviews];
        for (NSInteger k = _dragging; k <= _dragging + 1; k++) {
            NSView *v = [views objectAtIndex:k];
            if ([_delegate splitView:self canCollapseSubview:v] &&
                [_delegate splitView:self shouldCollapseSubview:v forDoubleClickOnDividerAtIndex:_dragging]) {
                [self _collapse:v divider:_dragging];
                break;
            }
        }
        _dragging = -1;
    }
}
- (void)mouseDragged:(NSEvent *)e
{
    if (_dragging < 0) {
        [super mouseDragged:e];
        return;
    }
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    CGFloat pos = [self _constrained:(_vertical ? p.x : p.y) - _grab divider:_dragging];
    NSArray *views = [self subviews];
    if (pos == -1)
        [self _collapse:[views objectAtIndex:_dragging] divider:_dragging];
    else if (pos == -2)
        [self _collapse:[views objectAtIndex:_dragging + 1] divider:_dragging];
    else
        [self setPosition:pos ofDividerAtIndex:_dragging];
}
- (void)mouseUp:(NSEvent *)e
{
    if (_dragging < 0) {
        [super mouseUp:e];
        return;
    }
    _dragging = -1;
    [self _save];
}

/* ---- drawing ----------------------------------------------------------------------- */

- (void)drawDividerInRect:(NSRect)r
{
    if (_style == NSSplitViewDividerStyleThin) {
        [[self dividerColor] setFill];
        NSRectFill(r);
        return;
    }
    [[self dividerColor] setFill];
    NSRectFill(r);
    [[NSColor colorWithCalibratedWhite:0 alpha:0.12] setFill];
    if (_style == NSSplitViewDividerStylePaneSplitter) {
        /* a line along each edge */
        NSRectFill(_vertical ? NSMakeRect(NSMinX(r), NSMinY(r), 1, r.size.height)
                             : NSMakeRect(NSMinX(r), NSMinY(r), r.size.width, 1));
        NSRectFill(_vertical ? NSMakeRect(NSMaxX(r) - 1, NSMinY(r), 1, r.size.height)
                             : NSMakeRect(NSMinX(r), NSMaxY(r) - 1, r.size.width, 1));
        return;
    }
    /* thick: a small dimple in the middle */
    CGFloat d = 5;
    NSRect dot = NSMakeRect(NSMidX(r) - d / 2, NSMidY(r) - d / 2, d, d);
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
}
- (void)drawRect:(NSRect)dirty
{
    NSInteger n = [[self subviews] count];
    for (NSInteger i = 0; i < n - 1; i++) {
        NSRect r = [self _dividerRect:i];
        if ([[[self subviews] objectAtIndex:i] isHidden] && [[[self subviews] objectAtIndex:i + 1] isHidden])
            continue;
        if ([_delegate respondsToSelector:@selector(splitView:shouldHideDividerAtIndex:)] &&
            [_delegate splitView:self shouldHideDividerAtIndex:i])
            continue;
        if (NSIntersectsRect(r, dirty))
            [self drawDividerInRect:r];
    }
}

/* ---- autosave ---------------------------------------------------------------------- */

- (NSString *)autosaveName { return _autosaveName; }
- (NSString *)_defaultsKey { return [@"NSSplitView Subview Frames " stringByAppendingString:_autosaveName]; }
- (void)setAutosaveName:(NSString *)name
{
    if (name == _autosaveName)
        return;
    [_autosaveName release];
    _autosaveName = [name copy];
    if (![_autosaveName length])
        return;
    /* each subview as "x, y, width, height, hidden, NO" (the last says whether it was flipped) */
    NSArray *frames = [[NSUserDefaults standardUserDefaults] arrayForKey:[self _defaultsKey]];
    NSArray *views = [self subviews];
    if ([frames count] != [views count])
        return;
    for (NSUInteger i = 0; i < [views count]; i++) {
        NSArray *parts = [[frames objectAtIndex:i] componentsSeparatedByString:@", "];
        if ([parts count] < 5)
            return;
        NSView *v = [views objectAtIndex:i];
        [v setFrame:NSMakeRect([[parts objectAtIndex:0] doubleValue], [[parts objectAtIndex:1] doubleValue],
                               [[parts objectAtIndex:2] doubleValue], [[parts objectAtIndex:3] doubleValue])];
        [v setHidden:[[parts objectAtIndex:4] boolValue]];
    }
    [self adjustSubviews];
}
- (void)_save
{
    if (![_autosaveName length])
        return;
    NSMutableArray *frames = [NSMutableArray array];
    for (NSView *v in [self subviews]) {
        NSRect f = [v frame];
        [frames addObject:[NSString stringWithFormat:@"%g, %g, %g, %g, %@, NO", f.origin.x, f.origin.y, f.size.width,
                                                     f.size.height, [v isHidden] ? @"YES" : @"NO"]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:frames forKey:[self _defaultsKey]];
}
@end
