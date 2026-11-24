/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: stack views (NSStackView), and what a view says about its
 * own size (the NSConstraintBasedLayout methods of NSView). Ferry's own
 * code, written from Apple's public API documentation.
 *
 * Ferry has no Auto Layout, so a stack view lays its views out by hand,
 * whenever they or its settings or size change: in a row or a column, each
 * at its intrinsic content size (or its frame's size, when it has none; a
 * stack view inside another counts at its fitting size), spaced and inset
 * as asked, spread by the distribution and lined up across by the
 * alignment. Views with gravity areas go at the start, the middle or the
 * end. Hidden views drop out (detachesHiddenViews), and when the views
 * don't fit, the ones with the lowest visibility priority are taken out
 * until they do. Like a Mac's, a stack view is flipped: a column runs from
 * the top down.
 *
 * Nibs: the keys read here ("NSStackViewOrientation",
 * "NSStackViewAlignment", "NSStackViewSpacing", "NSStackViewDistribution",
 * "NSStackViewDetachesHiddenViews", "NSStackViewEdgeInsets.top" and its
 * left, bottom and right, and the gravity areas as NSStackViewContainer
 * objects under "NSStackViewBeginningContainer", "NSStackViewMiddleContainer"
 * and "NSStackViewEndContainer", each with its views under
 * "NSStackViewContainerNonDroppedViews") are the names given in
 * descriptions of the format published by developers and by the GNUstep
 * project; no Apple code was read. Without containers, the stack view's
 * subviews are its views, in order. */
#import "AInternal.h"
#include <objc/runtime.h>

/* ---- what a view says about its size ---------------------------------------------------- */

static char hugging_key[2], compression_key[2], needs_layout_key;

static NSLayoutPriority stored_priority(NSView *v, char *key, NSLayoutPriority dflt)
{
    NSNumber *n = objc_getAssociatedObject(v, key);
    return n ? [n floatValue] : dflt;
}

@implementation NSView (NSConstraintBasedLayout)
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (NSSize)fittingSize
{
    NSSize s = [self intrinsicContentSize], f = [self frame].size;
    return NSMakeSize(s.width >= 0 ? s.width : f.width, s.height >= 0 ? s.height : f.height);
}
- (BOOL)needsLayout { return [objc_getAssociatedObject(self, &needs_layout_key) boolValue]; }
- (void)setNeedsLayout:(BOOL)flag
{
    objc_setAssociatedObject(self, &needs_layout_key, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
/* There are no constraints to apply; a stack view arranges its views here. */
- (void)layout {}
- (void)layoutSubtreeIfNeeded
{
    if ([self needsLayout]) {
        [self setNeedsLayout:NO];
        [self layout];
    }
    for (NSView *v in [[[self subviews] copy] autorelease])
        [v layoutSubtreeIfNeeded];
}
/* A stack view the view is in lays its views out again. */
- (void)invalidateIntrinsicContentSize
{
    NSView *s = [self superview];
    if ([s isKindOfClass:[NSStackView class]])
        [s layout];
}
- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)o
{
    return stored_priority(self, &hugging_key[o ? 1 : 0], NSLayoutPriorityDefaultLow);
}
- (void)setContentHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o
{
    objc_setAssociatedObject(self, &hugging_key[o ? 1 : 0], @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self invalidateIntrinsicContentSize];
}
- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)o
{
    return stored_priority(self, &compression_key[o ? 1 : 0], NSLayoutPriorityDefaultHigh);
}
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o
{
    objc_setAssociatedObject(self, &compression_key[o ? 1 : 0], @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self invalidateIntrinsicContentSize];
}
@end

/* ---- a nib's gravity area ---------------------------------------------------------------- */

@interface NSStackViewContainer : NSObject <NSCoding> {
@public
    NSArray *views;
}
@end
@implementation NSStackViewContainer
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        id v = [c containsValueForKey:@"NSStackViewContainerNonDroppedViews"]
                   ? [c decodeObjectForKey:@"NSStackViewContainerNonDroppedViews"]
                   : nil;
        views = [[v isKindOfClass:[NSArray class]] ? v : @[] retain];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:views forKey:@"NSStackViewContainerNonDroppedViews"]; }
- (void)dealloc
{
    [views release];
    [super dealloc];
}
@end

/* ---- NSStackView -------------------------------------------------------------------- */

static NSValue *key_of(NSView *v) { return [NSValue valueWithNonretainedObject:v]; }

@implementation NSStackView {
    id<NSStackViewDelegate> _delegate;
    NSUserInterfaceLayoutOrientation _orientation;
    NSLayoutAttribute _alignment;
    NSEdgeInsets _insets;
    NSStackViewDistribution _distribution;
    CGFloat _spacing;
    BOOL _detachesHidden, _laying, _detaching;
    NSMutableArray *_views;           /* the arranged views, in order */
    NSMutableArray *_gravities;       /* NSNumber for each */
    NSMutableDictionary *_priorities, *_custom; /* NSNumber by view */
    NSMutableArray *_dropped;         /* taken out for want of room */
    NSLayoutPriority _clipping[2], _hugging[2];
}

+ (instancetype)stackViewWithViews:(NSArray *)views
{
    NSStackView *s = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    for (NSView *v in views)
        [s addArrangedSubview:v];
    [s setFrameSize:[s fittingSize]];
    return s;
}

- (void)_setup
{
    _views = [[NSMutableArray alloc] init];
    _gravities = [[NSMutableArray alloc] init];
    _priorities = [[NSMutableDictionary alloc] init];
    _custom = [[NSMutableDictionary alloc] init];
    _dropped = [[NSMutableArray alloc] init];
    _alignment = NSLayoutAttributeCenterY;
    _distribution = NSStackViewDistributionGravityAreas;
    _spacing = 8;
    _clipping[0] = _clipping[1] = NSLayoutPriorityRequired;
    _hugging[0] = _hugging[1] = NSLayoutPriorityDefaultLow;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setup];
    return self;
}
static id coded(NSCoder *c, NSString *key)
{
    return [c containsValueForKey:key] ? [c decodeObjectForKey:key] : nil;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    [self _setup];
    if ([c containsValueForKey:@"NSStackViewOrientation"])
        _orientation = [c decodeIntegerForKey:@"NSStackViewOrientation"];
    _alignment = _orientation == NSUserInterfaceLayoutOrientationHorizontal ? NSLayoutAttributeCenterY
                                                                            : NSLayoutAttributeCenterX;
    if ([c containsValueForKey:@"NSStackViewAlignment"])
        _alignment = [c decodeIntegerForKey:@"NSStackViewAlignment"];
    if ([c containsValueForKey:@"NSStackViewSpacing"])
        _spacing = [c decodeDoubleForKey:@"NSStackViewSpacing"];
    if ([c containsValueForKey:@"NSStackViewDistribution"])
        _distribution = [c decodeIntegerForKey:@"NSStackViewDistribution"];
    _detachesHidden = [c decodeBoolForKey:@"NSStackViewDetachesHiddenViews"];
    _insets.top = [c decodeDoubleForKey:@"NSStackViewEdgeInsets.top"];
    _insets.left = [c decodeDoubleForKey:@"NSStackViewEdgeInsets.left"];
    _insets.bottom = [c decodeDoubleForKey:@"NSStackViewEdgeInsets.bottom"];
    _insets.right = [c decodeDoubleForKey:@"NSStackViewEdgeInsets.right"];
    NSString *keys[3] = {@"NSStackViewBeginningContainer", @"NSStackViewMiddleContainer", @"NSStackViewEndContainer"};
    BOOL containers = NO;
    for (int g = 0; g < 3; g++) {
        NSStackViewContainer *box = coded(c, keys[g]);
        if (![box isKindOfClass:[NSStackViewContainer class]])
            continue;
        containers = YES;
        for (NSView *v in box->views)
            if ([v isKindOfClass:[NSView class]]) {
                [_views addObject:v];
                [_gravities addObject:@(g + 1)];
                if ([v superview] != self)
                    [super addSubview:v];
            }
    }
    if (!containers)
        for (NSView *v in [self subviews]) {
            [_views addObject:v];
            [_gravities addObject:@(NSStackViewGravityLeading)];
        }
    [self _relayout];
    return self;
}
- (void)dealloc
{
    [_views release];
    [_gravities release];
    [_priorities release];
    [_custom release];
    [_dropped release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }

/* ---- settings ---- */

- (id<NSStackViewDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSStackViewDelegate>)d { _delegate = d; }
- (NSUserInterfaceLayoutOrientation)orientation { return _orientation; }
- (void)setOrientation:(NSUserInterfaceLayoutOrientation)o
{
    if (o != _orientation) {
        /* the alignment turns with it, as the documentation says */
        _alignment = o == NSUserInterfaceLayoutOrientationHorizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX;
        _orientation = o;
    }
    [self _relayout];
}
- (NSLayoutAttribute)alignment { return _alignment; }
- (void)setAlignment:(NSLayoutAttribute)a
{
    _alignment = a;
    [self _relayout];
}
- (NSEdgeInsets)edgeInsets { return _insets; }
- (void)setEdgeInsets:(NSEdgeInsets)e
{
    _insets = e;
    [self _relayout];
}
- (NSStackViewDistribution)distribution { return _distribution; }
- (void)setDistribution:(NSStackViewDistribution)d
{
    _distribution = d;
    [self _relayout];
}
- (CGFloat)spacing { return _spacing; }
- (void)setSpacing:(CGFloat)s
{
    _spacing = s;
    [self _relayout];
}
- (BOOL)detachesHiddenViews { return _detachesHidden; }
- (void)setDetachesHiddenViews:(BOOL)f
{
    _detachesHidden = f;
    [self _relayout];
}
- (NSLayoutPriority)clippingResistancePriorityForOrientation:(NSLayoutConstraintOrientation)o { return _clipping[o ? 1 : 0]; }
- (void)setClippingResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o
{
    _clipping[o ? 1 : 0] = p;
}
- (NSLayoutPriority)huggingPriorityForOrientation:(NSLayoutConstraintOrientation)o { return _hugging[o ? 1 : 0]; }
- (void)setHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o
{
    _hugging[o ? 1 : 0] = p;
}

/* ---- the views ---- */

- (NSArray *)arrangedSubviews { return [[_views copy] autorelease]; }
- (NSArray *)views { return [self arrangedSubviews]; }
- (NSArray *)detachedViews
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSView *v in _views)
        if ([_dropped indexOfObjectIdenticalTo:v] != NSNotFound || (_detachesHidden && [v isHidden]) ||
            [self visibilityPriorityForView:v] == NSStackViewVisibilityPriorityNotVisible)
            [a addObject:v];
    return a;
}

- (void)_insert:(NSView *)view at:(NSInteger)index gravity:(NSStackViewGravity)g
{
    if (!view)
        return;
    NSUInteger old = [_views indexOfObjectIdenticalTo:view];
    if (old != NSNotFound) {
        [_views removeObjectAtIndex:old];
        [_gravities removeObjectAtIndex:old];
        if ((NSInteger)old < index)
            index--;
    }
    if (index < 0 || index > (NSInteger)[_views count])
        index = (NSInteger)[_views count];
    [_views insertObject:view atIndex:(NSUInteger)index];
    [_gravities insertObject:@(g) atIndex:(NSUInteger)index];
    if ([view superview] != self)
        [super addSubview:view];
    [self _relayout];
}
/* A view added to the end goes with the views now last. */
- (void)addArrangedSubview:(NSView *)view
{
    NSStackViewGravity g = [_gravities count] ? [[_gravities lastObject] integerValue] : NSStackViewGravityLeading;
    [self _insert:view at:(NSInteger)[_views count] gravity:g];
}
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)index
{
    NSStackViewGravity g = NSStackViewGravityLeading;
    if (index > 0 && index <= (NSInteger)[_gravities count])
        g = [_gravities[(NSUInteger)index - 1] integerValue];
    else if ([_gravities count])
        g = [_gravities[0] integerValue];
    [self _insert:view at:index gravity:g];
}
/* It stays a subview, no longer arranged. */
- (void)removeArrangedSubview:(NSView *)view
{
    NSUInteger i = [_views indexOfObjectIdenticalTo:view];
    if (i == NSNotFound)
        return;
    [[view retain] autorelease];
    [_views removeObjectAtIndex:i];
    [_gravities removeObjectAtIndex:i];
    [_dropped removeObjectIdenticalTo:view];
    [_priorities removeObjectForKey:key_of(view)];
    [_custom removeObjectForKey:key_of(view)];
    [self _relayout];
}
- (void)addView:(NSView *)view inGravity:(NSStackViewGravity)gravity
{
    [self insertView:view atIndex:[[self viewsInGravity:gravity] count] inGravity:gravity];
}
/* Gravity areas keep their order in the list: start, middle, end. */
- (void)insertView:(NSView *)view atIndex:(NSUInteger)index inGravity:(NSStackViewGravity)gravity
{
    NSInteger at = 0, seen = 0;
    for (NSUInteger i = 0; i < [_gravities count]; i++) {
        NSInteger g = [_gravities[i] integerValue];
        if (g < gravity || (g == gravity && seen < (NSInteger)index)) {
            at = (NSInteger)i + 1;
            if (g == gravity)
                seen++;
        }
    }
    [self _insert:view at:at gravity:gravity];
}
- (void)removeView:(NSView *)view
{
    [[view retain] autorelease];
    [self removeArrangedSubview:view];
    if ([view superview] == self)
        [view removeFromSuperview];
}
- (NSArray *)viewsInGravity:(NSStackViewGravity)gravity
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < [_views count]; i++)
        if ([_gravities[i] integerValue] == gravity)
            [a addObject:_views[i]];
    return a;
}
- (void)setViews:(NSArray *)views inGravity:(NSStackViewGravity)gravity
{
    for (NSView *v in [self viewsInGravity:gravity])
        [self removeView:v];
    for (NSView *v in views)
        [self addView:v inGravity:gravity];
}
- (void)setVisibilityPriority:(NSStackViewVisibilityPriority)p forView:(NSView *)view
{
    if (view)
        [_priorities setObject:@(p) forKey:key_of(view)];
    [self _relayout];
}
- (NSStackViewVisibilityPriority)visibilityPriorityForView:(NSView *)view
{
    NSNumber *n = view ? [_priorities objectForKey:key_of(view)] : nil;
    return n ? [n floatValue] : NSStackViewVisibilityPriorityMustHold;
}
- (void)setCustomSpacing:(CGFloat)spacing afterView:(NSView *)view
{
    if (!view)
        return;
    if (spacing == NSStackViewSpacingUseDefault)
        [_custom removeObjectForKey:key_of(view)];
    else
        [_custom setObject:@(spacing) forKey:key_of(view)];
    [self _relayout];
}
- (CGFloat)customSpacingAfterView:(NSView *)view
{
    NSNumber *n = view ? [_custom objectForKey:key_of(view)] : nil;
    return n ? [n doubleValue] : NSStackViewSpacingUseDefault;
}

/* An arranged view taken out of the view some other way leaves the list. */
- (void)willRemoveSubview:(NSView *)view
{
    [super willRemoveSubview:view];
    if (_detaching)
        return;
    NSUInteger i = [_views indexOfObjectIdenticalTo:view];
    if (i != NSNotFound) {
        [_views removeObjectAtIndex:i];
        [_gravities removeObjectAtIndex:i];
        [_priorities removeObjectForKey:key_of(view)];
        [_custom removeObjectForKey:key_of(view)];
        [self performSelector:@selector(_relayout) withObject:nil afterDelay:0];
    }
}
- (void)_arrangedSubviewVisibilityChanged:(NSView *)view
{
    if ([_views indexOfObjectIdenticalTo:view] != NSNotFound)
        [self _relayout];
}

/* ---- layout ---- */

- (BOOL)_horizontal { return _orientation == NSUserInterfaceLayoutOrientationHorizontal; }

/* A view's size as the stack sees it. */
static NSSize size_of(NSView *v)
{
    if ([v isKindOfClass:[NSStackView class]])
        return [v fittingSize];
    NSSize s = [v intrinsicContentSize], f = [v frame].size;
    return NSMakeSize(s.width >= 0 ? s.width : f.width, s.height >= 0 ? s.height : f.height);
}

- (CGFloat)_spacingAfter:(NSView *)v
{
    CGFloat c = [self customSpacingAfterView:v];
    return c == NSStackViewSpacingUseDefault ? _spacing : c;
}

/* The views that take part, in order: not hidden (when hidden views are
 * detached), not set never to show, not dropped for want of room. */
- (NSArray *)_shown
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSView *v in _views) {
        if (_detachesHidden && [v isHidden])
            continue;
        if ([self visibilityPriorityForView:v] <= NSStackViewVisibilityPriorityNotVisible)
            continue;
        if ([_dropped indexOfObjectIdenticalTo:v] != NSNotFound)
            continue;
        [a addObject:v];
    }
    return a;
}

- (CGFloat)_lengthOf:(NSArray *)views
{
    BOOL h = [self _horizontal];
    CGFloat total = 0;
    for (NSUInteger i = 0; i < [views count]; i++) {
        NSSize s = size_of(views[i]);
        total += h ? s.width : s.height;
        if (i + 1 < [views count])
            total += [self _spacingAfter:views[i]];
    }
    return total;
}

- (NSSize)fittingSize
{
    NSArray *shown = [self _shown];
    BOOL h = [self _horizontal];
    CGFloat main = [self _lengthOf:shown], cross = 0;
    for (NSView *v in shown) {
        NSSize s = size_of(v);
        cross = fmax(cross, h ? s.height : s.width);
    }
    if (h)
        return NSMakeSize(ceil(main + _insets.left + _insets.right), ceil(cross + _insets.top + _insets.bottom));
    return NSMakeSize(ceil(cross + _insets.left + _insets.right), ceil(main + _insets.top + _insets.bottom));
}

/* Views of low visibility priority are taken out, lowest first, until the
 * rest fit; ones taken out before come back when there is room again. */
- (void)_dropForRoom:(CGFloat)room
{
    NSArray *before = [[_dropped copy] autorelease];
    [_dropped removeAllObjects];
    while ([self _lengthOf:[self _shown]] > room + 0.5) {
        NSView *lowest = nil;
        NSStackViewVisibilityPriority lp = NSStackViewVisibilityPriorityMustHold;
        for (NSView *v in [self _shown]) {
            NSStackViewVisibilityPriority p = [self visibilityPriorityForView:v];
            if (p < lp) {
                lp = p;
                lowest = v;
            }
        }
        if (!lowest)
            break;
        [_dropped addObject:lowest];
    }
    NSMutableArray *gone = [NSMutableArray array], *back = [NSMutableArray array];
    for (NSView *v in _dropped)
        if ([before indexOfObjectIdenticalTo:v] == NSNotFound)
            [gone addObject:v];
    for (NSView *v in before)
        if ([_dropped indexOfObjectIdenticalTo:v] == NSNotFound && [_views indexOfObjectIdenticalTo:v] != NSNotFound)
            [back addObject:v];
    if ([gone count]) {
        if ([_delegate respondsToSelector:@selector(stackView:willDetachViews:)])
            [_delegate stackView:self willDetachViews:gone];
        _detaching = YES;
        for (NSView *v in gone)
            [v removeFromSuperview];
        _detaching = NO;
    }
    if ([back count]) {
        for (NSView *v in back)
            [super addSubview:v];
        if ([_delegate respondsToSelector:@selector(stackView:didReattachViews:)])
            [_delegate stackView:self didReattachViews:back];
    }
}

- (void)_relayout
{
    if (_laying || !_views)
        return;
    _laying = YES;
    BOOL h = [self _horizontal];
    NSRect b = [self bounds];
    CGFloat start = h ? b.origin.x + _insets.left : b.origin.y + _insets.top;
    CGFloat room = (h ? b.size.width - _insets.left - _insets.right : b.size.height - _insets.top - _insets.bottom);
    CGFloat crossStart = h ? b.origin.y + _insets.top : b.origin.x + _insets.left;
    CGFloat crossRoom = h ? b.size.height - _insets.top - _insets.bottom : b.size.width - _insets.left - _insets.right;
    [self _dropForRoom:room];
    NSArray *shown = [self _shown];
    NSUInteger n = [shown count];
    CGFloat len[n ? n : 1], pos[n ? n : 1], gaps = 0, sum = 0;
    for (NSUInteger i = 0; i < n; i++) {
        NSSize s = size_of(shown[i]);
        len[i] = h ? s.width : s.height;
        sum += len[i];
        if (i + 1 < n)
            gaps += [self _spacingAfter:shown[i]];
    }
    CGFloat extra = room - sum - gaps;
    NSLayoutConstraintOrientation o = h ? NSLayoutConstraintOrientationHorizontal : NSLayoutConstraintOrientationVertical;

    switch (_distribution) {
    case NSStackViewDistributionFill: {
        /* the room left over goes to the views that hug least; short of
         * room, the ones that resist least give it up */
        NSLayoutPriority best = 1e9;
        for (NSUInteger i = 0; i < n; i++) {
            NSLayoutPriority p = extra >= 0 ? [shown[i] contentHuggingPriorityForOrientation:o]
                                            : [shown[i] contentCompressionResistancePriorityForOrientation:o];
            best = fmin(best, p);
        }
        NSUInteger k = 0;
        for (NSUInteger i = 0; i < n; i++) {
            NSLayoutPriority p = extra >= 0 ? [shown[i] contentHuggingPriorityForOrientation:o]
                                            : [shown[i] contentCompressionResistancePriorityForOrientation:o];
            k += p == best;
        }
        for (NSUInteger i = 0; i < n && k; i++) {
            NSLayoutPriority p = extra >= 0 ? [shown[i] contentHuggingPriorityForOrientation:o]
                                            : [shown[i] contentCompressionResistancePriorityForOrientation:o];
            if (p == best)
                len[i] = fmax(len[i] + extra / k, 0);
        }
        break;
    }
    case NSStackViewDistributionFillEqually:
        for (NSUInteger i = 0; i < n; i++)
            len[i] = fmax((room - gaps) / n, 0);
        break;
    case NSStackViewDistributionFillProportionally:
        for (NSUInteger i = 0; i < n; i++)
            len[i] = sum > 0 ? fmax(len[i] + extra * len[i] / sum, 0) : fmax((room - gaps) / n, 0);
        break;
    default:
        break;
    }

    /* where each view starts along the stack */
    if (_distribution == NSStackViewDistributionEqualSpacing && n > 1 && extra > 0) {
        CGFloat x = start, step = (room - sum) / (n - 1);
        for (NSUInteger i = 0; i < n; i++) {
            pos[i] = x;
            x += len[i] + fmax(step, i + 1 < n ? [self _spacingAfter:shown[i]] : 0);
        }
    } else if (_distribution == NSStackViewDistributionEqualCentering && n > 1 && extra > 0) {
        CGFloat c0 = start + len[0] / 2, c1 = start + room - len[n - 1] / 2, step = (c1 - c0) / (n - 1);
        for (NSUInteger i = 0; i < n; i++)
            pos[i] = c0 + step * i - len[i] / 2;
    } else if (_distribution == NSStackViewDistributionGravityAreas) {
        /* the start's views from the start, the end's from the end, the
         * middle's centred between them */
        CGFloat glen[4] = {0, 0, 0, 0};
        NSUInteger count[4] = {0, 0, 0, 0};
        NSInteger grav[n ? n : 1];
        for (NSUInteger i = 0; i < n; i++) {
            NSInteger g = [_gravities[[_views indexOfObjectIdenticalTo:shown[i]]] integerValue];
            grav[i] = g >= 1 && g <= 3 ? g : 1;
        }
        for (NSUInteger i = 0; i < n; i++) {
            glen[grav[i]] += len[i];
            if (count[grav[i]]++)
                glen[grav[i]] += [self _spacingAfter:shown[i - 1]];
        }
        CGFloat leadEnd = start + glen[1] + (count[1] && (count[2] || count[3]) ? _spacing : 0);
        CGFloat trailStart = start + room - glen[3];
        CGFloat midStart = round(start + (room - glen[2]) / 2);
        if (midStart < leadEnd)
            midStart = leadEnd;
        if (count[3] && midStart + glen[2] + _spacing > trailStart)
            midStart = fmax(leadEnd, trailStart - _spacing - glen[2]);
        CGFloat at[4] = {0, start, midStart, trailStart};
        if (glen[3] > room - glen[1] - glen[2])
            at[3] = midStart + glen[2] + (count[2] ? _spacing : 0);
        if (!count[2] && count[3] && at[3] < leadEnd)
            at[3] = leadEnd;
        for (NSUInteger i = 0; i < n; i++) {
            pos[i] = at[grav[i]];
            at[grav[i]] += len[i] + (i + 1 < n ? [self _spacingAfter:shown[i]] : 0);
        }
    } else {
        CGFloat x = start;
        for (NSUInteger i = 0; i < n; i++) {
            pos[i] = x;
            x += len[i] + (i + 1 < n ? [self _spacingAfter:shown[i]] : 0);
        }
    }

    /* and across it, by the alignment */
    for (NSUInteger i = 0; i < n; i++) {
        NSView *v = shown[i];
        NSSize s = size_of(v);
        CGFloat c = h ? s.height : s.width, at = crossStart;
        switch (_alignment) {
        case NSLayoutAttributeTop:
        case NSLayoutAttributeLeading:
        case NSLayoutAttributeLeft:
            at = crossStart;
            break;
        case NSLayoutAttributeBottom:
        case NSLayoutAttributeTrailing:
        case NSLayoutAttributeRight:
        case NSLayoutAttributeLastBaseline:
            at = crossStart + crossRoom - c;
            break;
        case NSLayoutAttributeWidth:
        case NSLayoutAttributeHeight:
            c = crossRoom;
            break;
        default:     /* centred (the first baseline is taken as the centre) */
            at = crossStart + round((crossRoom - c) / 2);
            break;
        }
        NSRect f = h ? NSMakeRect(round(pos[i]), at, round(pos[i] + len[i]) - round(pos[i]), c)
                     : NSMakeRect(at, round(pos[i]), c, round(pos[i] + len[i]) - round(pos[i]));
        if (!NSEqualRects(f, [v frame]))
            [v setFrame:f];
    }
    [self setNeedsDisplay:YES];
    _laying = NO;
}

- (void)layout { [self _relayout]; }
- (void)setNeedsLayout:(BOOL)flag
{
    [super setNeedsLayout:NO];
    if (flag)
        [self _relayout];
}
- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self _relayout];
}
/* The views are placed by the stack, not by their autoresizing masks. */
- (void)resizeSubviewsWithOldSize:(NSSize)old { [self _relayout]; }
@end
