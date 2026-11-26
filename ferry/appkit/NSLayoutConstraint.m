/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Auto Layout (freemac 1.222, Ferry 0.46.0). Constraints,
 * anchors, layout guides, the visual format language and a solver that sets
 * views' frames from them. Ferry's own code, written from Apple's public API
 * documentation (the NSLayoutConstraint, NSLayoutAnchor and NSLayoutGuide
 * references and the Auto Layout Guide's description of the visual format
 * language).
 *
 * The solver. A window's (or a detached hierarchy's) constraints are solved
 * together, one axis at a time. Each view or guide taking part has two
 * unknowns on each axis, where it starts and its size, measured from the top
 * left of the topmost view in its own points; every attribute is a sum of
 * those (a trailing edge is start + size, a centre start + size / 2), so a
 * constraint is a linear equation or inequality. Rows go into a running
 * Gaussian elimination in priority order, required ones first; a row that
 * contradicts the rows already there is left out (a required one with a
 * note, as a Mac logs it), so higher priorities win. Below the app's own
 * constraints come a view's intrinsic size (its content hugging and
 * compression resistance, as inequalities at their priorities) and, last of
 * all, "stays" that keep each view where and as big as it was, which settle
 * whatever the constraints leave open. Inequalities start out inactive and
 * are made equalities, highest priority first, only while the answer breaks
 * them.
 *
 * The elimination is sparse and only ever goes forward (freemac 1.238,
 * Ferry 0.62.0): a row in it never changes once in, so when an inequality
 * is made active or let go only the rows after it are gone through again,
 * and of those only the ones that meet an unknown whose settling row
 * changed. The answer is the same as working it all out anew each time.
 * Views that translate their autoresizing mask into constraints stay
 * as their mask says against their superview, and are left to autoresizing;
 * the frames of the others are set, outermost first.
 *
 * Layout runs when a window displays, after anything has changed (a
 * constraint added, removed or changed, a view taking part resized, an
 * intrinsic size invalidated), and whenever an app asks
 * (layoutSubtreeIfNeeded, layoutIfNeeded, fittingSize).
 *
 * Nibs: a view's constraints under "NSViewConstraints" and its
 * "NSDoNotTranslateAutoresizingMask", and a constraint's "NSFirstItem",
 * "NSFirstAttribute", "NSRelation", "NSSecondItem", "NSSecondAttribute",
 * "NSMultiplier", "NSConstant", "NSPriority" and "NSShouldBeArchived", as the
 * GNUstep project's description of the format names them. */
#import "AInternal.h"
#include <objc/runtime.h>
#include <stdarg.h>
#include <time.h>

BOOL AConstraintsInUse;
static BOOL solving;
static int fit_depth;                 /* fitting solves inside one another */
static double fit_pull;               /* > 0: the fitting root is pulled to grow at this priority */
static BOOL fit_pull_vertical;
static unsigned long generation = 1;
static NSMutableSet *all_active;      /* every active constraint */
static BOOL updates_pending;          /* some view's needsUpdateConstraints is set */
static char constraints_key, guides_key, solved_key, update_key, guide_key;

static NSView *root_of(NSView *v)
{
    while ([v superview])
        v = [v superview];
    return v;
}

/* Something layout depends on has changed: the next pass solves again. */
static void changed(NSView *v)
{
    generation++;
    if (v && !solving) {
        NSWindow *w = [v window];
        [w ? [w contentView] : root_of(v) setNeedsDisplay:YES];
    }
}

/* ---- attributes ------------------------------------------------------------------------- */

static BOOL horizontal(NSLayoutAttribute a)
{
    return a == NSLayoutAttributeLeft || a == NSLayoutAttributeRight || a == NSLayoutAttributeLeading ||
           a == NSLayoutAttributeTrailing || a == NSLayoutAttributeWidth || a == NSLayoutAttributeCenterX;
}
static BOOL is_size(NSLayoutAttribute a) { return a == NSLayoutAttributeWidth || a == NSLayoutAttributeHeight; }

static NSString *attribute_name(NSLayoutAttribute a)
{
    switch (a) {
    case NSLayoutAttributeLeft: return @"left";
    case NSLayoutAttributeRight: return @"right";
    case NSLayoutAttributeTop: return @"top";
    case NSLayoutAttributeBottom: return @"bottom";
    case NSLayoutAttributeLeading: return @"leading";
    case NSLayoutAttributeTrailing: return @"trailing";
    case NSLayoutAttributeWidth: return @"width";
    case NSLayoutAttributeHeight: return @"height";
    case NSLayoutAttributeCenterX: return @"centerX";
    case NSLayoutAttributeCenterY: return @"centerY";
    case NSLayoutAttributeLastBaseline: return @"lastBaseline";
    case NSLayoutAttributeFirstBaseline: return @"firstBaseline";
    default: return @"notAnAttribute";
    }
}

/* ---- anchors ---------------------------------------------------------------------------- */

@interface NSLayoutConstraint ()
- (instancetype)_initWithItem:(id)i1 attribute:(NSLayoutAttribute)a1 minus:(id)i1b attribute:(NSLayoutAttribute)a1b
                     relation:(NSLayoutRelation)r
                         item:(id)i2 attribute:(NSLayoutAttribute)a2 minus:(id)i2b attribute:(NSLayoutAttribute)a2b
                   multiplier:(CGFloat)m constant:(CGFloat)c;
@end

@implementation NSLayoutAnchor {
@public
    id _item;                 /* not retained, as a constraint's items aren't */
    NSLayoutAttribute _attr;
    id _minusItem;            /* a dimension between two anchors: _item._attr - _minusItem._minusAttr */
    NSLayoutAttribute _minusAttr;
}
+ (instancetype)_anchorFor:(id)item attribute:(NSLayoutAttribute)a
{
    NSLayoutAnchor *x = [[[self alloc] init] autorelease];
    x->_item = item;
    x->_attr = a;
    return x;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)item { return _item; }
- (NSString *)name
{
    return _minusItem ? [NSString stringWithFormat:@"%@ - %@", attribute_name(_attr), attribute_name(_minusAttr)]
                      : attribute_name(_attr);
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@.%@>", [self class], [_item class], [self name]];
}
- (BOOL)isEqual:(id)o
{
    if (![o isKindOfClass:[NSLayoutAnchor class]])
        return NO;
    NSLayoutAnchor *a = o;
    return a->_item == _item && a->_attr == _attr && a->_minusItem == _minusItem && a->_minusAttr == _minusAttr;
}
- (NSUInteger)hash { return (NSUInteger)_item ^ (NSUInteger)_attr; }
- (NSLayoutConstraint *)_to:(NSLayoutAnchor *)o relation:(NSLayoutRelation)r multiplier:(CGFloat)m constant:(CGFloat)c
{
    return [[[NSLayoutConstraint alloc] _initWithItem:_item attribute:_attr minus:_minusItem attribute:_minusAttr
                                             relation:r
                                                 item:o ? o->_item : nil attribute:o ? o->_attr : NSLayoutAttributeNotAnAttribute
                                                minus:o ? o->_minusItem : nil
                                            attribute:o ? o->_minusAttr : NSLayoutAttributeNotAnAttribute
                                           multiplier:m constant:c] autorelease];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a
{
    return [self _to:a relation:NSLayoutRelationEqual multiplier:1 constant:0];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a
{
    return [self _to:a relation:NSLayoutRelationGreaterThanOrEqual multiplier:1 constant:0];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a
{
    return [self _to:a relation:NSLayoutRelationLessThanOrEqual multiplier:1 constant:0];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c
{
    return [self _to:a relation:NSLayoutRelationEqual multiplier:1 constant:c];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c
{
    return [self _to:a relation:NSLayoutRelationGreaterThanOrEqual multiplier:1 constant:c];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c
{
    return [self _to:a relation:NSLayoutRelationLessThanOrEqual multiplier:1 constant:c];
}
- (BOOL)hasAmbiguousLayout { return NO; }
- (NSArray *)constraintsAffectingLayout
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSLayoutConstraint *c in all_active)
        if (([c firstItem] == _item || [c secondItem] == _item) && horizontal([c firstAttribute]) == horizontal(_attr))
            [out addObject:c];
    return out;
}
@end

@implementation NSLayoutXAxisAnchor
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutXAxisAnchor *)other
{
    NSLayoutDimension *d = [NSLayoutDimension _anchorFor:other->_item attribute:other->_attr];
    ((NSLayoutAnchor *)d)->_minusItem = _item;
    ((NSLayoutAnchor *)d)->_minusAttr = _attr;
    return d;
}
@end
@implementation NSLayoutYAxisAnchor
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutYAxisAnchor *)other
{
    NSLayoutDimension *d = [NSLayoutDimension _anchorFor:other->_item attribute:other->_attr];
    ((NSLayoutAnchor *)d)->_minusItem = _item;
    ((NSLayoutAnchor *)d)->_minusAttr = _attr;
    return d;
}
@end
@implementation NSLayoutDimension
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c
{
    return [self _to:nil relation:NSLayoutRelationEqual multiplier:0 constant:c];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c
{
    return [self _to:nil relation:NSLayoutRelationGreaterThanOrEqual multiplier:0 constant:c];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c
{
    return [self _to:nil relation:NSLayoutRelationLessThanOrEqual multiplier:0 constant:c];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m
{
    return [self _to:a relation:NSLayoutRelationEqual multiplier:m constant:0];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m
{
    return [self _to:a relation:NSLayoutRelationGreaterThanOrEqual multiplier:m constant:0];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m
{
    return [self _to:a relation:NSLayoutRelationLessThanOrEqual multiplier:m constant:0];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m constant:(CGFloat)c
{
    return [self _to:a relation:NSLayoutRelationEqual multiplier:m constant:c];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m
                                                    constant:(CGFloat)c
{
    return [self _to:a relation:NSLayoutRelationGreaterThanOrEqual multiplier:m constant:c];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m
                                                 constant:(CGFloat)c
{
    return [self _to:a relation:NSLayoutRelationLessThanOrEqual multiplier:m constant:c];
}
@end

/* ---- constraints ------------------------------------------------------------------------ */

static NSView *view_of(id item)
{
    if ([item isKindOfClass:[NSView class]])
        return item;
    if ([item isKindOfClass:[NSLayoutGuide class]])
        return [(NSLayoutGuide *)item owningView];
    return nil;
}

/* The closest view holding both items (a guide counts as its owning view). */
static NSView *common_ancestor(NSView *a, NSView *b)
{
    if (!a)
        return b;
    if (!b)
        return a;
    for (NSView *x = a; x; x = [x superview])
        if (b == x || [b isDescendantOf:x])
            return x;
    return nil;
}

static NSMutableArray *installed(NSView *v, BOOL make)
{
    NSMutableArray *a = objc_getAssociatedObject(v, &constraints_key);
    if (!a && make) {
        a = [NSMutableArray array];
        objc_setAssociatedObject(v, &constraints_key, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return a;
}

NSDictionary *_NSDictionaryOfVariableBindings(NSString *keys, id first, ...)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSArray *names = [keys componentsSeparatedByString:@","];
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    va_list ap;
    va_start(ap, first);
    id v = first;
    for (NSString *name in names) {
        if (!v) break;
        d[[name stringByTrimmingCharactersInSet:space]] = v;
        v = va_arg(ap, id);
    }
    va_end(ap);
    return d;
}

@implementation NSLayoutConstraint {
    id _first, _firstMinus, _second, _secondMinus;   /* not retained */
    NSLayoutAttribute _a1, _a1b, _a2, _a2b;
    NSLayoutRelation _relation;
    CGFloat _multiplier, _constant;
    NSLayoutPriority _priority;
    NSView *_container;                               /* the view it is installed on, not retained */
    NSString *_identifier;
    BOOL _archived;
@public
    BOOL _noted;                                      /* its conflict has been reported */
}

- (instancetype)_initWithItem:(id)i1 attribute:(NSLayoutAttribute)a1 minus:(id)i1b attribute:(NSLayoutAttribute)a1b
                     relation:(NSLayoutRelation)r
                         item:(id)i2 attribute:(NSLayoutAttribute)a2 minus:(id)i2b attribute:(NSLayoutAttribute)a2b
                   multiplier:(CGFloat)m constant:(CGFloat)c
{
    if ((self = [super init])) {
        _first = i1;
        _a1 = a1;
        _firstMinus = i1b;
        _a1b = a1b;
        _relation = r;
        _second = i2;
        _a2 = i2 ? a2 : NSLayoutAttributeNotAnAttribute;
        _secondMinus = i2b;
        _a2b = a2b;
        _multiplier = i2 ? m : 0;
        _constant = c;
        _priority = NSLayoutPriorityRequired;
        _archived = YES;
    }
    return self;
}

+ (instancetype)constraintWithItem:(id)view1 attribute:(NSLayoutAttribute)attr1 relatedBy:(NSLayoutRelation)relation
                            toItem:(id)view2 attribute:(NSLayoutAttribute)attr2 multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c
{
    if (!view1 || attr1 == NSLayoutAttributeNotAnAttribute)
        [NSException raise:NSInvalidArgumentException
                    format:@"NSLayoutConstraint needs a first item and attribute"];
    /* (a width against a height, an aspect ratio, is the one pairing across the axes) */
    if (view2 && attr2 != NSLayoutAttributeNotAnAttribute && horizontal(attr1) != horizontal(attr2) &&
        !(is_size(attr1) && is_size(attr2)))
        [NSException raise:NSInvalidArgumentException
                    format:@"NSLayoutConstraint: a constraint can't relate %@ to %@", attribute_name(attr1),
                           attribute_name(attr2)];
    if (attr2 == NSLayoutAttributeNotAnAttribute)
        view2 = nil;
    return [[[self alloc] _initWithItem:view1 attribute:attr1 minus:nil attribute:NSLayoutAttributeNotAnAttribute
                               relation:relation
                                   item:view2 attribute:attr2 minus:nil attribute:NSLayoutAttributeNotAnAttribute
                             multiplier:multiplier constant:c] autorelease];
}

- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}

- (id)firstItem { return _first; }
- (id)secondItem { return _second; }
- (NSLayoutAttribute)firstAttribute { return _a1; }
- (NSLayoutAttribute)secondAttribute { return _a2; }
- (NSLayoutRelation)relation { return _relation; }
- (CGFloat)multiplier { return _multiplier; }
- (CGFloat)constant { return _constant; }
- (void)setConstant:(CGFloat)c
{
    if (c == _constant)
        return;
    _constant = c;
    if (_container)
        changed(_container);
}
- (NSLayoutPriority)priority { return _priority; }
- (void)setPriority:(NSLayoutPriority)p
{
    if (_container && ((_priority == NSLayoutPriorityRequired) != (p == NSLayoutPriorityRequired)))
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSLayoutConstraint: an installed constraint can't change between required and not"];
    _priority = p < 1 ? 1 : p > NSLayoutPriorityRequired ? NSLayoutPriorityRequired : p;
    if (_container)
        changed(_container);
}
- (NSString *)identifier { return _identifier; }
- (void)setIdentifier:(NSString *)identifier
{
    [_identifier release];
    _identifier = [identifier copy];
}
- (BOOL)shouldBeArchived { return _archived; }
- (void)setShouldBeArchived:(BOOL)flag { _archived = flag; }

static Class anchor_class(NSLayoutAttribute a)
{
    return is_size(a) ? [NSLayoutDimension class] : horizontal(a) ? [NSLayoutXAxisAnchor class]
                                                                   : [NSLayoutYAxisAnchor class];
}
- (NSLayoutAnchor *)firstAnchor
{
    NSLayoutAnchor *a = [anchor_class(_a1) _anchorFor:_first attribute:_a1];
    a->_minusItem = _firstMinus;
    a->_minusAttr = _a1b;
    return a;
}
- (NSLayoutAnchor *)secondAnchor
{
    if (!_second)
        return nil;
    NSLayoutAnchor *a = [anchor_class(_a2) _anchorFor:_second attribute:_a2];
    a->_minusItem = _secondMinus;
    a->_minusAttr = _a2b;
    return a;
}

- (NSView *)_container { return _container; }
- (void)_setContainer:(NSView *)v { _container = v; }
- (BOOL)_involves:(id)item
{
    return _first == item || _second == item || _firstMinus == item || _secondMinus == item;
}
- (NSArray *)_items
{
    NSMutableArray *a = [NSMutableArray array];
    id all[4] = {_first, _firstMinus, _second, _secondMinus};
    for (int k = 0; k < 4; k++)
        if (all[k] && [a indexOfObjectIdenticalTo:all[k]] == NSNotFound)
            [a addObject:all[k]];
    return a;
}
- (void)_getFirst:(id *)i1 attr:(NSLayoutAttribute *)a1 minus:(id *)i1b attr:(NSLayoutAttribute *)a1b
           second:(id *)i2 attr:(NSLayoutAttribute *)a2 minus:(id *)i2b attr:(NSLayoutAttribute *)a2b
{
    *i1 = _first, *a1 = _a1, *i1b = _firstMinus, *a1b = _a1b;
    *i2 = _second, *a2 = _a2, *i2b = _secondMinus, *a2b = _a2b;
}

/* The view a constraint belongs on: the closest one holding both items. */
- (NSView *)_naturalContainer
{
    NSView *v = view_of(_first);
    id rest[3] = {_firstMinus, _second, _secondMinus};
    for (int k = 0; k < 3; k++)
        if (rest[k])
            v = common_ancestor(v, view_of(rest[k]));
    return v;
}

- (BOOL)isActive { return _container != nil; }
- (void)setActive:(BOOL)active
{
    if (active == (_container != nil))
        return;
    if (active) {
        NSView *v = [self _naturalContainer];
        if (!v)
            [NSException raise:NSGenericException
                        format:@"NSLayoutConstraint: %@ relates items with no common ancestor", self];
        [v addConstraint:self];
    } else {
        [_container removeConstraint:self];
    }
}

+ (void)activateConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *c in constraints)
        [c setActive:YES];
}
+ (void)deactivateConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *c in constraints)
        [c setActive:NO];
}

static NSString *item_name(id item)
{
    if (!item)
        return @"nil";
    NSString *ident = [item respondsToSelector:@selector(identifier)] ? [item identifier] : nil;
    return ident ? [NSString stringWithFormat:@"%@'%@'", [item class], ident]
                 : [NSString stringWithFormat:@"%@:%p", [item class], item];
}
- (NSString *)description
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<NSLayoutConstraint:%p ", self];
    if (_identifier)
        [s appendFormat:@"'%@' ", _identifier];
    [s appendFormat:@"%@.%@", item_name(_first), attribute_name(_a1)];
    if (_firstMinus)
        [s appendFormat:@" - %@.%@", item_name(_firstMinus), attribute_name(_a1b)];
    [s appendString:_relation == NSLayoutRelationEqual ? @" == " : _relation < 0 ? @" <= " : @" >= "];
    if (_second) {
        if (_multiplier != 1)
            [s appendFormat:@"%g*", (double)_multiplier];
        [s appendFormat:@"%@.%@", item_name(_second), attribute_name(_a2)];
        if (_secondMinus)
            [s appendFormat:@" - %@.%@", item_name(_secondMinus), attribute_name(_a2b)];
        if (_constant)
            [s appendFormat:@" %@ %g", _constant < 0 ? @"-" : @"+", fabs((double)_constant)];
    } else {
        [s appendFormat:@"%g", (double)_constant];
    }
    if (_priority != NSLayoutPriorityRequired)
        [s appendFormat:@" @%g", (double)_priority];
    [s appendString:_container ? @" (active)>" : @" (inactive)>"];
    return s;
}

- (instancetype)initWithCoder:(NSCoder *)c
{
    id i1 = [c decodeObjectForKey:@"NSFirstItem"];
    id i2 = [c containsValueForKey:@"NSSecondItem"] ? [c decodeObjectForKey:@"NSSecondItem"] : nil;
    NSLayoutAttribute a1 = [c decodeIntegerForKey:@"NSFirstAttribute"];
    NSLayoutAttribute a2 = [c decodeIntegerForKey:@"NSSecondAttribute"];
    CGFloat m = [c containsValueForKey:@"NSMultiplier"] ? [c decodeDoubleForKey:@"NSMultiplier"] : 1;
    self = [self _initWithItem:i1 attribute:a1 minus:nil attribute:0
                      relation:[c decodeIntegerForKey:@"NSRelation"]
                          item:i2 attribute:a2 minus:nil attribute:0
                    multiplier:m constant:[c decodeDoubleForKey:@"NSConstant"]];
    if ([c containsValueForKey:@"NSPriority"])
        _priority = (NSLayoutPriority)[c decodeIntegerForKey:@"NSPriority"];
    if ([c containsValueForKey:@"NSShouldBeArchived"])
        _archived = [c decodeBoolForKey:@"NSShouldBeArchived"];
    if ([c containsValueForKey:@"NSLayoutIdentifier"])
        [self setIdentifier:[c decodeObjectForKey:@"NSLayoutIdentifier"]];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeConditionalObject:_first forKey:@"NSFirstItem"];
    [c encodeInteger:_a1 forKey:@"NSFirstAttribute"];
    [c encodeInteger:_relation forKey:@"NSRelation"];
    if (_second) {
        [c encodeConditionalObject:_second forKey:@"NSSecondItem"];
        [c encodeInteger:_a2 forKey:@"NSSecondAttribute"];
    }
    [c encodeDouble:_multiplier forKey:@"NSMultiplier"];
    [c encodeDouble:_constant forKey:@"NSConstant"];
    [c encodeInteger:(NSInteger)_priority forKey:@"NSPriority"];
    [c encodeBool:_archived forKey:@"NSShouldBeArchived"];
    if (_identifier)
        [c encodeObject:_identifier forKey:@"NSLayoutIdentifier"];
}

/* ---- the visual format language ---------------------------------------------------------- */

/* One predicate: (relation)(constant or view)(@priority). */
typedef struct {
    NSLayoutRelation relation;
    CGFloat constant;
    id view;
    NSLayoutPriority priority;
} predicate;

static void vfl_fail(NSString *format, NSUInteger at, NSString *why)
{
    [NSException raise:NSInvalidArgumentException
                format:@"Unable to parse constraint format: \n%@\n%@\n%@^", why, format,
                       [@"" stringByPaddingToLength:at withString:@" " startingAtIndex:0]];
}

typedef struct {
    NSString *s;
    NSUInteger i, n;
    NSDictionary *metrics, *views;
} vfl;

static unichar peek(vfl *p) { return p->i < p->n ? [p->s characterAtIndex:p->i] : 0; }
static BOOL take(vfl *p, unichar c)
{
    if (peek(p) == c) {
        p->i++;
        return YES;
    }
    return NO;
}
static BOOL name_char(unichar c, BOOL first)
{
    return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (!first && c >= '0' && c <= '9');
}
static NSString *read_name(vfl *p)
{
    NSUInteger start = p->i;
    if (!name_char(peek(p), YES))
        return nil;
    while (name_char(peek(p), NO))
        p->i++;
    return [p->s substringWithRange:NSMakeRange(start, p->i - start)];
}
static BOOL read_number(vfl *p, CGFloat *out)
{
    NSUInteger start = p->i;
    if (peek(p) == '-' || peek(p) == '+')
        p->i++;
    BOOL digits = NO;
    while ((peek(p) >= '0' && peek(p) <= '9') || peek(p) == '.') {
        digits = YES;
        p->i++;
    }
    if (!digits) {
        p->i = start;
        return NO;
    }
    *out = [[p->s substringWithRange:NSMakeRange(start, p->i - start)] doubleValue];
    return YES;
}
/* A number or a metric's name. */
static BOOL read_constant(vfl *p, CGFloat *out)
{
    if (read_number(p, out))
        return YES;
    NSUInteger start = p->i;
    NSString *name = read_name(p);
    if (name && [p->metrics[name] respondsToSelector:@selector(doubleValue)]) {
        *out = [p->metrics[name] doubleValue];
        return YES;
    }
    p->i = start;
    return NO;
}
static predicate read_predicate(vfl *p, BOOL views_allowed)
{
    predicate pr = {NSLayoutRelationEqual, 0, nil, NSLayoutPriorityRequired};
    if (take(p, '=')) {
        if (!take(p, '='))
            vfl_fail(p->s, p->i, @"Expected '=='");
    } else if (take(p, '<')) {
        if (!take(p, '='))
            vfl_fail(p->s, p->i, @"Expected '<='");
        pr.relation = NSLayoutRelationLessThanOrEqual;
    } else if (take(p, '>')) {
        if (!take(p, '='))
            vfl_fail(p->s, p->i, @"Expected '>='");
        pr.relation = NSLayoutRelationGreaterThanOrEqual;
    }
    if (!read_constant(p, &pr.constant)) {
        NSUInteger start = p->i;
        NSString *name = read_name(p);
        if (!name || !views_allowed || !p->views[name])
            vfl_fail(p->s, start, name ? [NSString stringWithFormat:@"%@ is not a key in the views or metrics dictionary", name]
                                       : @"Expected a number, metric or view");
        pr.view = p->views[name];
    }
    if (take(p, '@')) {
        CGFloat pri;
        if (!read_constant(p, &pri))
            vfl_fail(p->s, p->i, @"Expected a priority");
        pr.priority = (NSLayoutPriority)pri;
    }
    return pr;
}
/* "(pred, pred...)" or a single simple predicate. */
static NSUInteger read_predicates(vfl *p, predicate *out, NSUInteger max, BOOL views_allowed)
{
    NSUInteger n = 0;
    if (take(p, '(')) {
        do {
            if (n < max)
                out[n++] = read_predicate(p, views_allowed);
            else
                read_predicate(p, views_allowed);
        } while (take(p, ','));
        if (!take(p, ')'))
            vfl_fail(p->s, p->i, @"Expected ')'");
    } else {
        predicate pr = {NSLayoutRelationEqual, 0, nil, NSLayoutPriorityRequired};
        if (!read_constant(p, &pr.constant))
            vfl_fail(p->s, p->i, @"Expected a number or metric");
        out[n++] = pr;
    }
    return n;
}

+ (NSArray *)constraintsWithVisualFormat:(NSString *)format options:(NSLayoutFormatOptions)opts
                                 metrics:(NSDictionary *)metrics
                                   views:(NSDictionary *)views
{
    vfl p = {[format stringByReplacingOccurrencesOfString:@" " withString:@""], 0, 0, metrics ?: @{}, views ?: @{}};
    p.n = [p.s length];
    BOOL vertical = NO;
    if ([p.s hasPrefix:@"V:"]) {
        vertical = YES;
        p.i = 2;
    } else if ([p.s hasPrefix:@"H:"]) {
        p.i = 2;
    }
    BOOL ltr = (opts & NSLayoutFormatDirectionMask) == NSLayoutFormatDirectionLeftToRight;
    NSLayoutAttribute lead = vertical ? NSLayoutAttributeTop : ltr ? NSLayoutAttributeLeft : NSLayoutAttributeLeading;
    NSLayoutAttribute trail = vertical ? NSLayoutAttributeBottom : ltr ? NSLayoutAttributeRight : NSLayoutAttributeTrailing;
    NSLayoutAttribute size = vertical ? NSLayoutAttributeHeight : NSLayoutAttributeWidth;
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *chain = [NSMutableArray array];
    id previous = nil;            /* the view before the connection, or nil */
    BOOL previous_superview = NO; /* the connection starts at the superview */
    NSView *superview = nil;

    if (take(&p, '|'))
        previous_superview = YES;
    for (;;) {
        /* a connection: nothing, "-", or "-predicates-" */
        predicate space[8];
        NSUInteger nspace = 0;
        BOOL connected = NO, standard = NO;
        if (take(&p, '-')) {
            connected = YES;
            if (peek(&p) == '[' || peek(&p) == '|') {
                standard = YES;
            } else {
                nspace = read_predicates(&p, space, 8, NO);
                if (!take(&p, '-'))
                    vfl_fail(p.s, p.i, @"Expected '-'");
            }
        }
        BOOL to_superview = NO;
        id view = nil;
        if (take(&p, '|')) {
            to_superview = YES;
        } else if (take(&p, '[')) {
            NSUInteger start = p.i;
            NSString *name = read_name(&p);
            view = name ? p.views[name] : nil;
            if (!view)
                vfl_fail(p.s, start, [NSString stringWithFormat:@"%@ is not a key in the views dictionary", name ?: @"(nothing)"]);
            if (!superview && [view respondsToSelector:@selector(superview)])
                superview = [view superview];
            if (peek(&p) == '(') {
                predicate preds[8];
                NSUInteger n = read_predicates(&p, preds, 8, YES);
                for (NSUInteger k = 0; k < n; k++) {
                    NSLayoutConstraint *c = [self constraintWithItem:view attribute:size relatedBy:preds[k].relation
                                                              toItem:preds[k].view
                                                           attribute:preds[k].view ? size : NSLayoutAttributeNotAnAttribute
                                                          multiplier:1 constant:preds[k].constant];
                    [c setPriority:preds[k].priority];
                    [out addObject:c];
                }
            }
            if (!take(&p, ']'))
                vfl_fail(p.s, p.i, @"Expected ']'");
        } else if (p.i >= p.n && !connected) {
            break;
        } else {
            vfl_fail(p.s, p.i, @"Expected a view or '|'");
        }

        /* the spacing between what came before and this */
        if ((previous || previous_superview) && (view || to_superview)) {
            if (previous_superview && to_superview)
                vfl_fail(p.s, p.i, @"The superview can't be spaced from itself");
            if (connected && standard) {
                space[0] = (predicate){NSLayoutRelationEqual,
                                       (previous_superview || to_superview) ? NSLayoutConstraintStandardSuperviewSpacing
                                                                            : NSLayoutConstraintStandardSiblingSpacing,
                                       nil, NSLayoutPriorityRequired};
                nspace = 1;
            } else if (!connected) {
                space[0] = (predicate){NSLayoutRelationEqual, 0, nil, NSLayoutPriorityRequired};
                nspace = 1;
            }
            for (NSUInteger k = 0; k < nspace; k++) {
                NSLayoutConstraint *c;
                if (previous_superview) {
                    if (!superview)
                        vfl_fail(p.s, p.i, @"The view has no superview");
                    c = [self constraintWithItem:view attribute:lead relatedBy:space[k].relation toItem:superview
                                       attribute:lead multiplier:1 constant:space[k].constant];
                } else if (to_superview) {
                    if (!superview)
                        vfl_fail(p.s, p.i, @"The view has no superview");
                    c = [self constraintWithItem:superview attribute:trail relatedBy:space[k].relation toItem:previous
                                       attribute:trail multiplier:1 constant:space[k].constant];
                } else {
                    c = [self constraintWithItem:view attribute:lead relatedBy:space[k].relation toItem:previous
                                       attribute:trail multiplier:1 constant:space[k].constant];
                }
                [c setPriority:space[k].priority];
                [out addObject:c];
            }
        } else if (connected) {
            vfl_fail(p.s, p.i, @"A connection needs something on each side");
        }
        if (view)
            [chain addObject:view];
        previous = view;
        previous_superview = NO;
        if (to_superview) {
            if (p.i < p.n)
                vfl_fail(p.s, p.i, @"Nothing may follow the superview");
            break;
        }
        if (p.i >= p.n)
            break;
    }
    /* views lined up across the direction of the format */
    NSUInteger align = opts & NSLayoutFormatAlignmentMask;
    for (NSLayoutAttribute a = NSLayoutAttributeLeft; a <= NSLayoutAttributeFirstBaseline; a++) {
        if (!(align & (1u << a)))
            continue;
        if (horizontal(a) == !vertical)
            [NSException raise:NSInvalidArgumentException
                        format:@"Unable to parse constraint format: alignment along the format's own direction"];
        for (NSUInteger k = 1; k < [chain count]; k++)
            [out addObject:[self constraintWithItem:chain[k - 1] attribute:a relatedBy:NSLayoutRelationEqual
                                             toItem:chain[k] attribute:a multiplier:1 constant:0]];
    }
    return out;
}
@end

/* ---- layout guides ---------------------------------------------------------------------- */

@implementation NSLayoutGuide {
    NSRect _frame;
    NSView *_owner;      /* not retained */
    NSString *_identifier;
    BOOL _content;       /* a window's content layout guide: the content view's bounds */
}
- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSRect)frame { return _frame; }
- (void)_setFrame:(NSRect)f { _frame = f; }
- (BOOL)_isContentGuide { return _content; }
- (void)_setContentGuide:(BOOL)flag { _content = flag; }
- (NSView *)owningView { return _owner; }
- (void)setOwningView:(NSView *)v
{
    _owner = v;
    _frame = v ? [v bounds] : NSZeroRect;
}
- (NSUserInterfaceItemIdentifier)identifier { return _identifier; }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    [_identifier release];
    _identifier = [identifier copy];
}
#define ANCHOR(name, cls, attr) \
    -(cls *)name { return [cls _anchorFor:self attribute:attr]; }
ANCHOR(leadingAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeLeading)
ANCHOR(trailingAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeTrailing)
ANCHOR(leftAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeLeft)
ANCHOR(rightAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeRight)
ANCHOR(centerXAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeCenterX)
ANCHOR(topAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeTop)
ANCHOR(bottomAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeBottom)
ANCHOR(centerYAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeCenterY)
ANCHOR(widthAnchor, NSLayoutDimension, NSLayoutAttributeWidth)
ANCHOR(heightAnchor, NSLayoutDimension, NSLayoutAttributeHeight)
- (BOOL)hasAmbiguousLayout { return NO; }
- (NSArray *)constraintsAffectingLayoutForOrientation:(NSLayoutConstraintOrientation)o
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSLayoutConstraint *c in all_active)
        if ([c _involves:self] && horizontal([c firstAttribute]) == (o == NSLayoutConstraintOrientationHorizontal))
            [out addObject:c];
    return out;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSLayoutGuide:%p %@ %@>", self, _identifier ?: @"",
                                      NSStringFromRect(_frame)];
}
@end

/* ---- the solver ------------------------------------------------------------------------- */

#define EPS 1e-7

/* The elimination (freemac 1.238, Ferry 0.62.0). Rows go in one at a
 * time, in priority order, each reduced by the rows already in and kept
 * when it says something new; one that contradicts them is left out. Rows
 * are sparse, as constraints are (a few unknowns each), and reduced only
 * forwards: a row never changes once it is in, so the elimination after
 * the first k pending rows is its first depth[k] rows, and a row names
 * only the pivots of rows after it. */
typedef struct {
    int pivot;                   /* the unknown it settles, with coefficient 1 */
    int n;                       /* its other unknowns */
    const int *col;
    const double *val;
    double rhs;
} erow;

/* What a pending row did when it was last held: whether it went in, and
 * the unknowns it met on the way (its own and those of the rows that
 * reduced it). While none of those has a different row settling it, it
 * would do the same again. */
typedef struct {
    char held, result;           /* result: 0 contradicted, 1 implied, 2 went in */
    int pivot, n, met;
    double rhs;
    int *col;
    double *val;
    int *touched;
    int room;
} rowcache;

typedef struct {
    int nvars, nrows;
    erow *rows;
    int *pivot_row;              /* unknown -> the row it is the pivot of, or -1 */
    int *refs;                   /* unknown -> how many rows name it besides */
    double *r;                   /* the row being added, dense; zero between rows */
    int *nz, nnz;                /* the unknowns it has met */
    char *seen;
    int *heap, nheap;            /* rows still to reduce it by, first first */
    int best;                    /* after el_reduce: its pivot */
    double rhs;                  /* and its right side, before dividing */
    /* across the solves of one axis */
    rowcache *cache;             /* one for each pending row */
    rowcache *units;             /* and for each unit row */
    int *changed, stamp;         /* unknown -> stamp: settled by another row than last time */
    int *depth;                  /* pending row k: rows in before it; [npending]: before the unit rows */
    double *x;                   /* the last answer */
    BOOL valid;
    struct chunk *chunks;        /* the memory of it all, given back at once */
} elim;

typedef struct chunk {
    struct chunk *next;
    size_t used, room;
    double align;
} chunk;

/* Zeroed memory that lasts as long as e. */
static void *el_alloc(elim *e, size_t bytes)
{
    bytes = (bytes + 15) & ~(size_t)15;
    chunk *c = e->chunks;
    if (!c || c->used + bytes > c->room) {
        size_t room = c ? 2 * c->room : 0;
        if (room < bytes)
            room = bytes;
        if (room < 4096)
            room = 4096;
        c = malloc(sizeof(chunk) + room);
        c->next = e->chunks;
        c->used = 0;
        c->room = room;
        e->chunks = c;
    }
    void *at = (char *)(c + 1) + c->used;
    c->used += bytes;
    memset(at, 0, bytes);
    return at;
}

static void el_init(elim *e, int nvars, int npending)
{
    memset(e, 0, sizeof(*e));
    e->nvars = nvars;
    size_t n = (size_t)nvars + 1, m = (size_t)npending + 1;
    /* one piece for the fixed parts, with room for the rows' own */
    size_t room = n * (sizeof(erow) + 6 * sizeof(int) + 2 * sizeof(double) + sizeof(rowcache) + 64) +
                  m * (sizeof(rowcache) + sizeof(int) + 160) + 512;
    chunk *c = malloc(sizeof(chunk) + room);
    c->next = NULL;
    c->used = 0;
    c->room = room;
    e->chunks = c;
    e->rows = el_alloc(e, sizeof(erow) * n);
    e->pivot_row = el_alloc(e, sizeof(int) * n);
    for (int j = 0; j < nvars; j++)
        e->pivot_row[j] = -1;
    e->refs = el_alloc(e, sizeof(int) * n);
    e->r = el_alloc(e, sizeof(double) * n);
    e->nz = el_alloc(e, sizeof(int) * n);
    e->seen = el_alloc(e, n);
    e->heap = el_alloc(e, sizeof(int) * n);
    e->cache = el_alloc(e, sizeof(rowcache) * m);
    e->units = el_alloc(e, sizeof(rowcache) * n);
    e->changed = el_alloc(e, sizeof(int) * n);
    e->depth = el_alloc(e, sizeof(int) * m);
    e->x = el_alloc(e, sizeof(double) * n);
}

static void el_free(elim *e)
{
    while (e->chunks) {
        chunk *c = e->chunks;
        e->chunks = c->next;
        free(c);
    }
}

static void heap_push(elim *e, int i)
{
    int k = e->nheap++;
    while (k > 0 && e->heap[(k - 1) / 2] > i) {
        e->heap[k] = e->heap[(k - 1) / 2];
        k = (k - 1) / 2;
    }
    e->heap[k] = i;
}

static int heap_pop(elim *e)
{
    int top = e->heap[0], last = e->heap[--e->nheap], k = 0;
    for (;;) {
        int c = 2 * k + 1;
        if (c >= e->nheap)
            break;
        if (c + 1 < e->nheap && e->heap[c + 1] < e->heap[c])
            c++;
        if (e->heap[c] >= last)
            break;
        e->heap[k] = e->heap[c];
        k = c;
    }
    e->heap[k] = last;
    return top;
}

/* The row being added meets unknown j: the row among the first limit that
 * settles j, if any, is to reduce it. */
static void el_touch(elim *e, int j, int limit)
{
    if (e->seen[j])
        return;
    e->seen[j] = 1;
    e->nz[e->nnz++] = j;
    int i = e->pivot_row[j];
    if (i >= 0 && i < limit)
        heap_push(e, i);
}

/* Reduces a·x = rhs by the first limit rows: 0 when it contradicts them,
 * 1 when they imply it, 2 when it says something new, and then e->best is
 * the unknown it would settle. el_clear afterwards. */
static int el_reduce(elim *e, const int *col, const double *val, int n, double rhs, int limit)
{
    double *r = e->r;
    e->nnz = e->nheap = 0;
    for (int t = 0; t < n; t++) {
        el_touch(e, col[t], limit);
        r[col[t]] += val[t];
    }
    /* by the rows in their order, as a row names only the pivots of rows after it */
    while (e->nheap) {
        const erow *q = &e->rows[heap_pop(e)];
        double f = r[q->pivot];
        r[q->pivot] = 0;
        if (fabs(f) <= EPS)
            continue;
        for (int t = 0; t < q->n; t++) {
            el_touch(e, q->col[t], limit);
            r[q->col[t]] -= f * q->val[t];
        }
        rhs -= f * q->rhs;
    }
    e->rhs = rhs;
    int best = -1;
    double big = 0;
    for (int t = 0; t < e->nnz; t++) {
        int j = e->nz[t];
        double v = fabs(r[j]);
        if (v > big)
            big = v, best = j;
    }
    if (big < 1e-9)
        return fabs(rhs) < 1e-6;
    /* of the unknowns it names with a coefficient near the biggest, the
     * one fewest rows name, so that rows reduce in fewer steps */
    for (int t = 0; t < e->nnz; t++) {
        int j = e->nz[t];
        if (fabs(r[j]) >= 0.5 * big && (e->refs[j] < e->refs[best] || (e->refs[j] == e->refs[best] && j > best)))
            best = j;
    }
    e->best = best;
    return 2;
}

static void el_clear(elim *e)
{
    for (int t = 0; t < e->nnz; t++) {
        e->r[e->nz[t]] = 0;
        e->seen[e->nz[t]] = 0;
    }
}

/* The reduced row, divided by its pivot's coefficient, into col and val
 * (room for nnz entries): how many. */
static int el_entries(elim *e, int *col, double *val)
{
    double f = e->r[e->best];
    int n = 0;
    for (int t = 0; t < e->nnz; t++) {
        int j = e->nz[t];
        double v = e->r[j] / f;
        if (j != e->best && fabs(v) > 1e-12) {
            col[n] = j;
            val[n++] = v;
        }
    }
    return n;
}

static void el_push(elim *e, int pivot, int n, const int *col, const double *val, double rhs)
{
    erow *q = &e->rows[e->nrows];
    *q = (erow){pivot, n, col, val, rhs};
    for (int t = 0; t < n; t++)
        e->refs[col[t]]++;
    e->pivot_row[pivot] = e->nrows++;
}

/* Back to the first n rows. */
static void el_truncate(elim *e, int n)
{
    while (e->nrows > n) {
        const erow *q = &e->rows[--e->nrows];
        e->pivot_row[q->pivot] = -1;
        for (int t = 0; t < q->n; t++)
            e->refs[q->col[t]]--;
    }
}

/* Every unknown is some row's pivot, and a row names only the pivots of
 * rows after it: the answer comes from the last row back. */
static void el_solution(elim *e, double *x)
{
    for (int j = 0; j < e->nvars; j++)
        x[j] = 0;
    for (int i = e->nrows - 1; i >= 0; i--) {
        const erow *q = &e->rows[i];
        double v = q->rhs;
        for (int t = 0; t < q->n; t++)
            v -= q->val[t] * x[q->col[t]];
        x[q->pivot] = v;
    }
}

/* The reduced row just made into pending row k's cache; whether what goes
 * in has changed (a row in where there was none or the other way, or
 * another row). */
static BOOL el_keep(elim *e, rowcache *c, int result)
{
    BOOL was = c->held && c->result == 2;
    BOOL differs = was != (result == 2);
    if (c->room < e->nnz) {
        int room = e->nnz + 4;
        int *col = el_alloc(e, sizeof(int) * (size_t)room), *touched = el_alloc(e, sizeof(int) * (size_t)room);
        double *val = el_alloc(e, sizeof(double) * (size_t)room);
        if (c->n) {
            memcpy(col, c->col, sizeof(int) * (size_t)c->n);
            memcpy(val, c->val, sizeof(double) * (size_t)c->n);
        }
        c->col = col, c->val = val, c->touched = touched, c->room = room;
    }
    if (result == 2) {
        double f = e->r[e->best], rhs = e->rhs / f;
        if (was && e->best == c->pivot && rhs == c->rhs) {
            /* the same row again? */
            int n = 0;
            BOOL same = YES;
            for (int t = 0; t < e->nnz && same; t++) {
                int j = e->nz[t];
                double v = e->r[j] / f;
                if (j != e->best && fabs(v) > 1e-12) {
                    same = n < c->n && c->col[n] == j && c->val[n] == v;
                    n++;
                }
            }
            differs = !same || n != c->n;
        } else if (was) {
            differs = YES;
        }
        if (differs && was)
            e->changed[c->pivot] = e->stamp;
        if (differs)
            e->changed[e->best] = e->stamp;
        c->n = el_entries(e, c->col, c->val);
        c->pivot = e->best;
        c->rhs = rhs;
    } else if (was) {
        e->changed[c->pivot] = e->stamp;
    }
    memcpy(c->touched, e->nz, sizeof(int) * (size_t)e->nnz);
    c->met = e->nnz;
    c->held = 1;
    c->result = (char)result;
    return differs;
}

/* Whether a held row would do the same as last time. */
static BOOL el_unchanged(elim *e, const rowcache *c)
{
    if (!c->held)
        return NO;
    for (int t = 0; t < c->met; t++)
        if (e->changed[c->touched[t]] == e->stamp)
            return NO;
    return YES;
}

/* A row waiting to be solved: a·x (relation) rhs, at a priority. A
 * constraint names at most four attributes, each at most two unknowns. */
#define ROW_TERMS 8
typedef struct {
    int col[ROW_TERMS];           /* the unknowns it names, in order once sorted */
    double val[ROW_TERMS];
    int n;
    double rhs;
    NSLayoutRelation relation;
    double priority;
    NSLayoutConstraint *source;   /* nil for the solver's own rows */
    int order;
} pending;

typedef struct {
    NSMutableArray *items;        /* views and guides, each with a start and a size on each axis */
    NSMapTable *index;            /* item -> NSNumber */
    pending *rows;
    int nrows, cap;
    int nvars;                    /* 2 per item on the axis being solved */
    const double *other;          /* the other axis as solved, for aspect ratios (NULL: as things are) */
    BOOL across[2];               /* aspect ratios were met solving across (horizontal, vertical) */
} problem;

static int item_index(problem *p, id item)
{
    NSNumber *n = [p->index objectForKey:item];
    return n ? [n intValue] : -1;
}

static pending *new_row(problem *p, double priority, NSLayoutRelation rel, NSLayoutConstraint *src)
{
    if (p->nrows == p->cap) {
        p->cap = p->cap ? p->cap * 2 : 64;
        p->rows = realloc(p->rows, sizeof(pending) * (size_t)p->cap);
    }
    pending *r = &p->rows[p->nrows];
    r->n = 0;
    r->rhs = 0;
    r->relation = rel;
    r->priority = priority;
    r->source = src;
    r->order = p->nrows++;
    return r;
}

/* A row's coefficient of unknown j. */
static double *coef(pending *r, int j)
{
    static double spare;
    for (int t = 0; t < r->n; t++)
        if (r->col[t] == j)
            return &r->val[t];
    if (r->n == ROW_TERMS) {
        spare = 0;
        return &spare;
    }
    r->col[r->n] = j;
    r->val[r->n] = 0;
    return &r->val[r->n++];
}
#define A(r, j) (*coef((r), (j)))

/* Its terms in the order of their unknowns, so that evaluating it adds
 * them up in the order the dense rows of earlier versions did. */
static void sort_terms(pending *r)
{
    for (int t = 1; t < r->n; t++)
        for (int u = t; u > 0 && r->col[u - 1] > r->col[u]; u--) {
            int c = r->col[u];
            double v = r->val[u];
            r->col[u] = r->col[u - 1], r->val[u] = r->val[u - 1];
            r->col[u - 1] = c, r->val[u - 1] = v;
        }
}

/* coefficient * attribute of an item, added to a row's left side; what isn't
 * an unknown goes to the right. */
static void add_attr(problem *p, pending *r, id item, NSLayoutAttribute a, double k, BOOL flipped_x)
{
    int i = item_index(p, item);
    if (i < 0 || a == NSLayoutAttributeNotAnAttribute)
        return;
    int start = 2 * i, size = 2 * i + 1;
    switch (a) {
    case NSLayoutAttributeLeft:
    case NSLayoutAttributeTop:
        A(r, start) += k;
        break;
    case NSLayoutAttributeLeading:
        A(r, start) += k;
        if (flipped_x)
            A(r, size) += k;
        break;
    case NSLayoutAttributeTrailing:
        A(r, start) += k;
        if (!flipped_x)
            A(r, size) += k;
        break;
    case NSLayoutAttributeRight:
    case NSLayoutAttributeBottom:
        A(r, start) += k;
        A(r, size) += k;
        break;
    case NSLayoutAttributeCenterX:
    case NSLayoutAttributeCenterY:
        A(r, start) += k;
        A(r, size) += k / 2;
        break;
    case NSLayoutAttributeWidth:
    case NSLayoutAttributeHeight:
        A(r, size) += k;
        break;
    case NSLayoutAttributeLastBaseline:
    case NSLayoutAttributeFirstBaseline: {
        /* from the bottom (or the top for the first baseline) by the view's own offset */
        A(r, start) += k;
        if ([item isKindOfClass:[NSView class]]) {
            if (a == NSLayoutAttributeFirstBaseline) {
                r->rhs -= k * [(NSView *)item firstBaselineOffsetFromTop];
            } else {
                A(r, size) += k;
                r->rhs += k * [(NSView *)item lastBaselineOffsetFromBottom];
            }
        } else {
            A(r, size) += k;
        }
        break;
    }
    default:
        break;
    }
}

/* What Auto Layout lines up for a view: its alignment rect, the frame less
 * its alignmentRectInsets, as on a Mac (freemac 1.250). A rounded push
 * button's is its bezel, inside the taller frame it is drawn in, so a nib's
 * spacing between buttons is between their bezels. Only a view with no
 * subviews of its own is taken by its alignment rect, so that what is
 * placed inside a view is placed against its frame. Insets in the root's
 * top-down terms: left, top, right, bottom. */
static NSEdgeInsets insets_of(id item)
{
    if (![item isKindOfClass:[NSView class]] || [[(NSView *)item subviews] count])
        return NSEdgeInsetsMake(0, 0, 0, 0);
    NSEdgeInsets e = [(NSView *)item alignmentRectInsets];
    if (!isfinite(e.top) || !isfinite(e.left) || !isfinite(e.bottom) || !isfinite(e.right))
        return NSEdgeInsetsMake(0, 0, 0, 0);
    return e;   /* top is the view's visual top, flipped or not */
}

@interface NSView (FerryIntrinsicFrame)
- (BOOL)_intrinsicSizeIsFrameSize;   /* NSControl.m: Ferry's own push buttons */
@end

/* A view's intrinsic size in alignment-rect terms. Ferry's own controls
 * give theirs as the frame they want; one the app's own class gives is
 * taken as it is, as a Mac takes it. */
static NSSize alignment_intrinsic(NSView *v)
{
    NSSize s = [v intrinsicContentSize];
    if ([v respondsToSelector:@selector(_intrinsicSizeIsFrameSize)] && [v _intrinsicSizeIsFrameSize]) {
        NSEdgeInsets e = insets_of(v);
        if (s.width >= 0)
            s.width = fmax(0, s.width - e.left - e.right);
        if (s.height >= 0)
            s.height = fmax(0, s.height - e.top - e.bottom);
    }
    return s;
}

/* Where an item is now, in the root's top-down points: a view's alignment
 * rect. */
static NSRect current_rect(id item, NSView *root)
{
    NSView *v = view_of(item);
    NSRect r = [item isKindOfClass:[NSView class]] ? [v bounds] : [(NSLayoutGuide *)item frame];
    if (!v)
        return NSZeroRect;
    NSRect inRoot = [v convertRect:r toView:root];
    if (![root isFlipped])
        inRoot.origin.y = [root bounds].size.height - NSMaxY(inRoot);
    inRoot.origin.x -= [root bounds].origin.x;
    if ([root isFlipped])
        inRoot.origin.y -= [root bounds].origin.y;
    if (item != root) {
        NSEdgeInsets e = insets_of(item);
        inRoot = NSMakeRect(inRoot.origin.x + e.left, inRoot.origin.y + e.top,
                            fmax(0, inRoot.size.width - e.left - e.right), fmax(0, inRoot.size.height - e.top - e.bottom));
    }
    return inRoot;
}

/* A view that doesn't translate its autoresizing mask but is placed by
 * its superview all the same: a split view's pane or a stack view's
 * arranged view, which Ferry's split and stack views size and place by
 * frame where a Mac's do it with constraints of their own. */
static BOOL in_container(NSView *v)
{
    NSView *s = [v superview];
    if ([s isKindOfClass:[NSSplitView class]])
        return YES;
    return [s isKindOfClass:[NSStackView class]] &&
           [[(NSStackView *)s arrangedSubviews] indexOfObjectIdenticalTo:v] != NSNotFound;
}

/* A view its superview places by frame whatever its constraints say. */
static BOOL placed_by_superview(id item)
{
    if (![item isKindOfClass:[NSView class]])
        return NO;
    NSView *v = item;
    return [v translatesAutoresizingMaskIntoConstraints] || in_container(v);
}

/* The item's parent in the layout: a view's superview, a guide's owning view. */
static NSView *parent_of(id item)
{
    return [item isKindOfClass:[NSView class]] ? [(NSView *)item superview] : [(NSLayoutGuide *)item owningView];
}

/* An item's frame from its start and size, in its parent's coordinates. */
static NSRect frame_from(id item, double x, double w, double y, double h, double px, double py, double ph)
{
    NSView *parent = parent_of(item);
    NSRect b = [parent bounds];
    NSRect f;
    f.origin.x = b.origin.x + (x - px);
    f.size.width = w;
    f.size.height = h;
    if ([parent isFlipped])
        f.origin.y = b.origin.y + (y - py);
    else
        f.origin.y = b.origin.y + ph - (y - py) - h;
    return f;
}

static void collect(NSView *v, NSMutableArray *constraints, NSMutableArray *guides)
{
    NSArray *mine = installed(v, NO);
    if (mine)
        [constraints addObjectsFromArray:mine];
    NSArray *g = objc_getAssociatedObject(v, &guides_key);
    if (g)
        [guides addObjectsFromArray:g];
    for (NSView *s in [v subviews])
        collect(s, constraints, guides);
}

static int compare_rows(const void *x, const void *y)
{
    const pending *a = x, *b = y;
    if (a->priority != b->priority)
        return a->priority > b->priority ? -1 : 1;
    return a->order - b->order;
}

static double evaluate(const pending *r, const double *x)
{
    double v = 0;
    for (int t = 0; t < r->n; t++)
        v += r->val[t] * x[r->col[t]];
    return v;
}

/* The rows of a mask that translates into constraints, on one axis, in
 * top-down terms: margins before and after, size, and which of them flex. */
static void mask_rows(problem *p, id item, int pi, double m1, double s, double m2, BOOL flex1, BOOL flexSize,
                      BOOL flex2, double parentSize)
{
    int i = item_index(p, item);
    int x = 2 * i, w = 2 * i + 1;
    int px = 2 * pi, pw = 2 * pi + 1;
    pending *a = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationEqual, nil);
    pending *b = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationEqual, nil);
    double ps = parentSize > 0 ? parentSize : 1;
    int nflex = flex1 + flexSize + flex2;
    if (pi < 0) {
        /* the root: where it is */
        A(a, x) = 1, a->rhs = m1;
        A(b, w) = 1, b->rhs = s;
        return;
    }
    if (nflex == 0 || (nflex == 1 && flex2)) {          /* pinned before, fixed size */
        A(a, x) = 1, A(a, px) = -1, a->rhs = m1;
        A(b, w) = 1, b->rhs = s;
    } else if (nflex == 1 && flex1) {                  /* pinned after, fixed size */
        A(a, x) = 1, A(a, w) = 1, A(a, px) = -1, A(a, pw) = -1, a->rhs = -m2;
        A(b, w) = 1, b->rhs = s;
    } else if (nflex == 1) {                           /* both margins pinned */
        A(a, x) = 1, A(a, px) = -1, a->rhs = m1;
        A(b, x) = 1, A(b, w) = 1, A(b, px) = -1, A(b, pw) = -1, b->rhs = -m2;
    } else if (flex1 && flex2 && !flexSize) {          /* centred in proportion, fixed size */
        A(a, x) = 1, A(a, w) = 0.5, A(a, px) = -1, A(a, pw) = -(m1 + s / 2) / ps;
        A(b, w) = 1, b->rhs = s;
    } else if (flexSize && flex2 && !flex1) {          /* pinned before, size in proportion */
        A(a, x) = 1, A(a, px) = -1, a->rhs = m1;
        A(b, w) = 1, A(b, pw) = -s / ps;
    } else if (flexSize && flex1 && !flex2) {          /* pinned after, size in proportion */
        A(a, x) = 1, A(a, w) = 1, A(a, px) = -1, A(a, pw) = -1, a->rhs = -m2;
        A(b, w) = 1, A(b, pw) = -s / ps;
    } else {                                           /* everything in proportion */
        A(a, x) = 1, A(a, px) = -1, A(a, pw) = -m1 / ps;
        A(b, w) = 1, A(b, pw) = -s / ps;
    }
}

static void note_required_failure(NSLayoutConstraint *c)
{
    static int notes;
    /* once for each constraint, as layout runs again and again */
    if (c && !c->_noted && notes < 20) {
        c->_noted = YES;
        notes++;
        fprintf(stderr, "ferry: Auto Layout can't satisfy every required constraint at once; leaving out %s\n",
                [[c description] UTF8String]);
    }
}

static BOOL breaks(pending *r, double *x)
{
    double v = evaluate(r, x);
    return (r->relation < 0 && v > r->rhs + 1e-6) || (r->relation > 0 && v < r->rhs - 1e-6);
}

/* How far x is past an inequality, 0 if it keeps it. */
static double broken_by(pending *r, double *x)
{
    double v = evaluate(r, x);
    if (r->relation < 0)
        return v > r->rhs + 1e-6 ? v - r->rhs : 0;
    return v < r->rhs - 1e-6 ? r->rhs - v : 0;
}

/* The inequality to hold next: of those x breaks that aren't held, the one
 * broken furthest at the highest priority any of them has, the first of
 * those in order if two are broken as far. A Mac's solver keeps the total
 * error down; holding whichever broken rule came first could leave a far
 * bigger one broken (at least 50, at least 100 and at most 90 at one
 * priority came out 50, 50 short of 100, where 90 to 100 is 10 short of
 * one), as the rounds that let rules go can't undo it (freemac 1.251). */
static int first_broken(problem *p, char *active, double *x)
{
    int best = -1;
    double most = 0;
    for (int k = 0; k < p->nrows; k++) {
        pending *r = &p->rows[k];
        if (best >= 0 && r->priority != p->rows[best].priority)
            break;
        if (r->relation == NSLayoutRelationEqual || active[k])
            continue;
        double d = broken_by(r, x);
        if (d > most + 1e-9)
            best = k, most = d;
    }
    return best;
}

static int stat_calls, stat_solves;   /* for FERRY_LAYOUT_STATS */
/* Solves the equalities and the held inequalities, in priority order;
 * failed marks the rows that couldn't be kept. e holds what the last solve
 * of the same rows did. The solve starts again at the first row held then
 * and not now, or now and not then (a row taken up that the rows before it
 * already settle, or let go of that never went in, changes nothing), and
 * of the rows after that does again only those that meet an unknown that
 * some row before them now settles differently. */
static void solve_rows(problem *p, elim *e, char *active, char *failed, double *x)
{
    stat_calls++;
    int start = 0;
    if (e->valid) {
        for (; start < p->nrows; start++) {
            pending *r = &p->rows[start];
            rowcache *c = &e->cache[start];
            char held = r->relation == NSLayoutRelationEqual || active[start];
            if (held == c->held)
                continue;
            if (!held && c->result != 2) {
                c->held = 0;
                failed[start] = 0;
                continue;
            }
            if (held) {
                int k = el_reduce(e, r->col, r->val, r->n, r->rhs, e->depth[start]);
                if (k < 2) {
                    el_keep(e, c, k);
                    el_clear(e);
                    failed[start] = k == 0;
                    continue;
                }
                el_clear(e);
            }
            break;
        }
        if (start == p->nrows) {
            memcpy(x, e->x, sizeof(double) * (size_t)p->nvars);
            return;
        }
        el_truncate(e, e->depth[start]);
    }
    stat_solves++;
    e->stamp++;
    for (int k = start; k < p->nrows; k++) {
        pending *r = &p->rows[k];
        rowcache *c = &e->cache[k];
        e->depth[k] = e->nrows;
        if (r->relation != NSLayoutRelationEqual && !active[k]) {
            if (c->held && c->result == 2)
                e->changed[c->pivot] = e->stamp;
            c->held = 0;
            failed[k] = 0;
            continue;
        }
        if (!el_unchanged(e, c)) {
            int result = el_reduce(e, r->col, r->val, r->n, r->rhs, e->nrows);
            el_keep(e, c, result);
            el_clear(e);
        }
        if (c->result == 2)
            el_push(e, c->pivot, c->n, c->col, c->val, c->rhs);
        failed[k] = c->result == 0;
    }
    e->depth[p->nrows] = e->nrows;
    /* anything still open (an item no row mentions) stays at zero */
    for (int j = 0; j < p->nvars && e->nrows < p->nvars; j++) {
        double one = 1;
        rowcache *c = &e->units[j];
        if (el_reduce(e, &j, &one, 1, 0, e->nrows) == 2) {
            c->held = 0;
            el_keep(e, c, 2);
            el_push(e, c->pivot, c->n, c->col, c->val, c->rhs);
        }
        el_clear(e);
    }
    el_solution(e, e->x);
    e->valid = YES;
    memcpy(x, e->x, sizeof(double) * (size_t)p->nvars);
}

/* Solves one axis. fitting: the root's size is free, pulled towards nothing. */
static void solve_axis(problem *p, NSArray *constraints, NSView *root, BOOL vertical, BOOL fitting, double *out)
{
    NSUInteger n = [p->items count];
    p->nvars = (int)(2 * n);
    p->nrows = 0;
    /* room for every row up front, so that a pointer to a row stays good
     * while the next is made (an item has five rows at most) */
    int need = (int)([constraints count] + 5 * n + 8);
    if (p->cap < need) {
        p->cap = need;
        p->rows = realloc(p->rows, sizeof(pending) * (size_t)p->cap);
    }
    BOOL rtl = NO;
    NSRect rootRect = NSMakeRect(0, 0, [root bounds].size.width, [root bounds].size.height);

    /* the app's constraints on this axis */
    for (NSLayoutConstraint *c in constraints) {
        id i1, i1b, i2, i2b;
        NSLayoutAttribute a1, a1b, a2, a2b;
        [c _getFirst:&i1 attr:&a1 minus:&i1b attr:&a1b second:&i2 attr:&a2 minus:&i2b attr:&a2b];
        if (horizontal(a1) == vertical)
            continue;
        if (!i2 && !is_size(a1) && !i1b)
            continue;   /* a position against nothing means nothing */
        if (i2 && is_size(a1) && is_size(a2) && a1 != a2 && !i1b && !i2b) {
            /* an aspect ratio, a width against a height: the other size is
             * the other axis's, as solved there (or as it is, the first time) */
            int i = item_index(p, i2);
            double other = p->other && i >= 0 ? p->other[2 * i + 1]
                         : vertical ? current_rect(i2, root).size.width : current_rect(i2, root).size.height;
            pending *r = new_row(p, [c priority], [c relation], c);
            add_attr(p, r, i1, a1, 1, rtl);
            r->rhs += [c multiplier] * other + [c constant];
            p->across[vertical ? 1 : 0] = YES;
            continue;
        }
        pending *r = new_row(p, [c priority], [c relation], c);
        add_attr(p, r, i1, a1, 1, rtl);
        if (i1b)
            add_attr(p, r, i1b, a1b, -1, rtl);
        if (i2) {
            double m = [c multiplier];
            add_attr(p, r, i2, a2, -m, rtl);
            if (i2b)
                add_attr(p, r, i2b, a2b, m, rtl);
        }
        r->rhs += [c constant];
    }

    /* each item's place against its parent */
    for (NSUInteger k = 0; k < n; k++) {
        id item = p->items[k];
        NSRect now = current_rect(item, root);
        double start = vertical ? now.origin.y : now.origin.x;
        double size = vertical ? now.size.height : now.size.width;
        int i = (int)k;
        if (item == root) {
            NSWindow *w = [root window];
            if (fitting) {
                pending *a = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationEqual, nil);
                A(a, 2 * i) = 1;
                pending *b = new_row(p, fit_pull > 0 && vertical == fit_pull_vertical ? fit_pull
                                                                                     : NSLayoutPriorityFittingSizeCompression,
                                     NSLayoutRelationEqual, nil);
                A(b, 2 * i + 1) = 1;
                if (fit_pull > 0 && vertical == fit_pull_vertical)
                    b->rhs = 10000;
            } else if (w && [w contentView] == root) {
                /* a window's content view: as on a Mac, the window holds its
                 * size only at NSLayoutPriorityWindowSizeStayPut, so stronger
                 * constraints inside it make it bigger or smaller (within
                 * its minimum and maximum content size) */
                pending *a = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationEqual, nil);
                A(a, 2 * i) = 1;
                pending *b = new_row(p, NSLayoutPriorityWindowSizeStayPut, NSLayoutRelationEqual, nil);
                A(b, 2 * i + 1) = 1;
                b->rhs = vertical ? rootRect.size.height : rootRect.size.width;
                NSSize lo = [w contentMinSize], hi = [w contentMaxSize];
                double mn = vertical ? lo.height : lo.width, mx = vertical ? hi.height : hi.width;
                if (mn > 0) {
                    pending *m = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationGreaterThanOrEqual, nil);
                    A(m, 2 * i + 1) = 1, m->rhs = mn;
                }
                if (mx > 0 && mx < 100000) {
                    pending *m = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationLessThanOrEqual, nil);
                    A(m, 2 * i + 1) = 1, m->rhs = mx;
                }
            } else {
                mask_rows(p, item, -1, 0, vertical ? rootRect.size.height : rootRect.size.width, 0, NO, NO, NO, 0);
            }
            continue;
        }
        id parent = parent_of(item);
        int pi = item_index(p, parent);
        NSRect pnow = current_rect(parent, root);
        double pstart = vertical ? pnow.origin.y : pnow.origin.x;
        double psize = vertical ? pnow.size.height : pnow.size.width;
        if ([item isKindOfClass:[NSLayoutGuide class]] && [(NSLayoutGuide *)item _isContentGuide]) {
            /* the window's content layout guide is its content view's bounds */
            pending *a = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationEqual, nil);
            A(a, 2 * i) = 1, A(a, 2 * pi) = -1;
            pending *b = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationEqual, nil);
            A(b, 2 * i + 1) = 1, A(b, 2 * pi + 1) = -1;
            continue;
        }
        if ([item isKindOfClass:[NSView class]] && ![(NSView *)item translatesAutoresizingMaskIntoConstraints] &&
            in_container(item)) {
            /* a split view's pane, a stack view's view: where it was put */
            mask_rows(p, item, pi, start - pstart, size, psize - (start - pstart) - size, NO, NO, NO, psize);
            continue;
        }
        if ([item isKindOfClass:[NSView class]] && [(NSView *)item translatesAutoresizingMaskIntoConstraints]) {
            NSAutoresizingMaskOptions m = [(NSView *)item autoresizingMask];
            NSView *pv = parent;
            BOOL flexMin, flexSize, flexMax;
            if (!vertical) {
                flexMin = (m & NSViewMinXMargin) != 0, flexSize = (m & NSViewWidthSizable) != 0;
                flexMax = (m & NSViewMaxXMargin) != 0;
            } else if ([pv isFlipped]) {
                flexMin = (m & NSViewMinYMargin) != 0, flexSize = (m & NSViewHeightSizable) != 0;
                flexMax = (m & NSViewMaxYMargin) != 0;
            } else {
                /* a superview that isn't flipped measures from the bottom */
                flexMin = (m & NSViewMaxYMargin) != 0, flexSize = (m & NSViewHeightSizable) != 0;
                flexMax = (m & NSViewMinYMargin) != 0;
            }
            if (![pv autoresizesSubviews])
                flexMin = flexSize = flexMax = NO;
            mask_rows(p, item, pi, start - pstart, size, psize - (start - pstart) - size, flexMin, flexSize, flexMax,
                      psize);
            continue;
        }
        /* a view placed by constraints: its intrinsic size, then where it was */
        if ([item isKindOfClass:[NSView class]]) {
            NSSize is = alignment_intrinsic(item);
            double want = vertical ? is.height : is.width;
            if (want >= 0) {
                NSLayoutConstraintOrientation o = vertical ? NSLayoutConstraintOrientationVertical
                                                           : NSLayoutConstraintOrientationHorizontal;
                pending *hug = new_row(p, [(NSView *)item contentHuggingPriorityForOrientation:o],
                                       NSLayoutRelationLessThanOrEqual, nil);
                A(hug, 2 * i + 1) = 1, hug->rhs = want;
                pending *resist = new_row(p, [(NSView *)item contentCompressionResistancePriorityForOrientation:o],
                                          NSLayoutRelationGreaterThanOrEqual, nil);
                A(resist, 2 * i + 1) = 1, resist->rhs = want;
            }
        }
        pending *stayStart = new_row(p, 0.02, NSLayoutRelationEqual, nil);
        A(stayStart, 2 * i) = 1;
        if (pi >= 0)
            A(stayStart, 2 * pi) = -1;
        stayStart->rhs = pi >= 0 ? start - pstart : start;
        pending *staySize = new_row(p, fitting ? 0.01 : 0.03, NSLayoutRelationEqual, nil);
        A(staySize, 2 * i + 1) = 1;
        staySize->rhs = fitting ? 0 : size;
    }
    /* a size is never negative */
    for (NSUInteger k = 0; k < n; k++) {
        pending *r = new_row(p, NSLayoutPriorityRequired, NSLayoutRelationGreaterThanOrEqual, nil);
        A(r, 2 * k + 1) = 1;
    }

    qsort(p->rows, (size_t)p->nrows, sizeof(pending), compare_rows);
    for (int k = 0; k < p->nrows; k++)
        sort_terms(&p->rows[k]);
    elim e;
    el_init(&e, p->nvars, p->nrows);
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    stat_calls = stat_solves = 0;
    /* inequalities are active (held as equalities) only while the answer
     * would break them otherwise */
    char *active = calloc((size_t)p->nrows, 1), *failed = calloc((size_t)p->nrows, 1);
    char *let_go = calloc((size_t)p->nrows, 1);
    double *x = calloc((size_t)p->nvars, sizeof(double));
    int limit = 4 * p->nrows + 8;
    for (int round = 0; round < limit; round++) {
        solve_rows(p, &e, active, failed, x);
        int broken = first_broken(p, active, x);
        if (broken >= 0) {
            active[broken] = 1;
            continue;
        }
        /* an inequality held earlier may no longer be needed, and may be in
         * the way of a weaker wish that keeps it anyway (a size held at zero
         * blocking an intrinsic width): let go of each one that the answer
         * keeps without it. The rows before it in priority order come out
         * the same, so nothing stronger loses. A weaker wish the answer then
         * breaks (a label hugging its text at priority 1 once a zero width
         * no longer holds it) is taken up in the rounds that follow
         * (freemac 1.232: Itsycal's month title). */
        BOOL released = NO;
        for (int k = p->nrows - 1; k >= 0; k--) {
            if (!active[k])
                continue;
            active[k] = 0;
            solve_rows(p, &e, active, failed, x);
            int fb = first_broken(p, active, x);
            /* letting go while a weaker wish breaks happens once a row, so
             * the rounds can't go back and forth between the two */
            BOOL weaker = fb >= 0 && p->rows[fb].priority < p->rows[k].priority && !let_go[k];
            if ((fb < 0 || weaker) && !breaks(&p->rows[k], x)) {
                released = YES;
                if (weaker)
                    let_go[k] = 1;
            } else {
                active[k] = 1;
            }
        }
        if (!released)
            break;
    }
    solve_rows(p, &e, active, failed, x);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    /* FERRY_LAYOUT_STATS: a line for each axis of a window's solve */
    static int stats = -1;
    if (stats < 0)
        stats = getenv("FERRY_LAYOUT_STATS") != NULL;
    if (stats && !fitting)
        fprintf(stderr, "ferry: layout %s: %d rows, %d unknowns, %d solves, %d of them anew, %.2f ms\n",
                vertical ? "V" : "H", p->nrows, p->nvars, stat_calls, stat_solves,
                (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6);
    for (int k = 0; k < p->nrows; k++)
        if (failed[k] && p->rows[k].priority >= NSLayoutPriorityRequired)
            note_required_failure(p->rows[k].source);
    /* what the order of the arithmetic leaves (a hair either side of a
     * quarter point, a zero below zero) doesn't count */
    for (int j = 0; j < p->nvars; j++)
        out[j] = round(x[j] * 1048576) / 1048576 + 0.0;
    free(x);
    free(active);
    free(failed);
    free(let_go);
    el_free(&e);
}

static void add_item(problem *p, id item, NSView *root)
{
    if (!item || [p->index objectForKey:item])
        return;
    /* its parents first, up to the root */
    if (item != root) {
        NSView *parent = parent_of(item);
        if (!parent || (parent != root && ![parent isDescendantOf:root]))
            return;
        add_item(p, parent, root);
    }
    [p->index setObject:@([p->items count]) forKey:item];
    [p->items addObject:item];
}

/* Fitting sizes asked for while a window's rows are made (freemac 1.238,
 * Ferry 0.62.0). A stack view asks how big each of its views wants to be
 * and how firmly, for its own size and hugging, again and again, and
 * nothing moves until the window's rows are solved: each is worked out
 * once. */
typedef struct {
    NSView *view;
    double pull;
    BOOL pullVertical, ok;
    int depth;
    NSSize size;
} fitted;
static fitted *fit_memo;
static int fit_memo_count, fit_memo_room;
static BOOL fit_memo_on;

static unsigned fit_slot(NSView *v, int mask)
{
    uintptr_t h = (uintptr_t)v;
    h ^= h >> 17;
    h *= 0x9e3779b1u;
    return (unsigned)(h ^ ((unsigned)fit_depth * 31u) ^ (fit_pull > 0 ? (unsigned)fit_pull * 7u + fit_pull_vertical : 0u)) &
           (unsigned)mask;
}
static fitted *remembered(NSView *v)
{
    if (!fit_memo_on || !fit_memo_room)
        return NULL;
    for (unsigned i = fit_slot(v, fit_memo_room - 1);; i = (i + 1) & (unsigned)(fit_memo_room - 1)) {
        fitted *f = &fit_memo[i];
        if (!f->view)
            return NULL;
        if (f->view == v && f->depth == fit_depth && f->pull == fit_pull &&
            (fit_pull <= 0 || f->pullVertical == fit_pull_vertical))
            return f;
    }
}
static void remember(NSView *v, BOOL ok, NSSize size)
{
    if (!fit_memo_on)
        return;
    if (2 * (fit_memo_count + 1) > fit_memo_room) {
        fitted *old = fit_memo;
        int oldRoom = fit_memo_room;
        fit_memo_room = oldRoom ? 2 * oldRoom : 256;
        fit_memo = calloc((size_t)fit_memo_room, sizeof(fitted));
        fit_memo_count = 0;
        double pull = fit_pull;
        BOOL pullVertical = fit_pull_vertical;
        int depth = fit_depth;
        for (int k = 0; k < oldRoom; k++)
            if (old[k].view) {
                fit_pull = old[k].pull, fit_pull_vertical = old[k].pullVertical, fit_depth = old[k].depth;
                remember(old[k].view, old[k].ok, old[k].size);
            }
        fit_pull = pull, fit_pull_vertical = pullVertical, fit_depth = depth;
        free(old);
    }
    unsigned i = fit_slot(v, fit_memo_room - 1);
    while (fit_memo[i].view)
        i = (i + 1) & (unsigned)(fit_memo_room - 1);
    fit_memo[i] = (fitted){v, fit_pull, fit_pull_vertical, ok, fit_depth, size};
    fit_memo_count++;
}
static void forget_fitted(void)
{
    fit_memo_on = NO;
    if (fit_memo_count)
        memset(fit_memo, 0, sizeof(fitted) * (size_t)fit_memo_room);
    fit_memo_count = 0;
}

/* Solves the constraints of root's subtree once. With fitting, answers the
 * smallest size of root they allow and moves nothing. *again is set when a
 * view the solver doesn't place (one placed by a stack view, say) came out
 * another size than the solver took it to be. */
static NSSize solve_once(NSView *root, BOOL fitting, BOOL *again)
{
    NSMutableArray *constraints = [NSMutableArray array], *guides = [NSMutableArray array];
    collect(root, constraints, guides);
    if (![constraints count])
        return [root frame].size;
    problem p = {0};
    p.items = [NSMutableArray array];
    p.index = [NSMapTable strongToStrongObjectsMapTable];
    add_item(&p, root, root);
    for (NSLayoutConstraint *c in constraints)
        for (id item in [c _items])
            add_item(&p, item, root);
    /* constraints reaching outside root (fitting a view inside a window) leave
     * those items as they are */
    NSMutableArray *usable = [NSMutableArray array];
    for (NSLayoutConstraint *c in constraints) {
        BOOL inside = YES;
        for (id item in [c _items])
            if (![p.index objectForKey:item])
                inside = NO;
        if (inside)
            [usable addObject:c];
    }
    NSUInteger n = [p.items count];
    double *hx = calloc(2 * n, sizeof(double)), *vx = calloc(2 * n, sizeof(double));
    BOOL wasSolving = solving;
    solving = YES;
    @try {
        if (!fitting)
            fit_memo_on = YES;
        solve_axis(&p, usable, root, NO, fitting, hx);
        p.other = hx;
        solve_axis(&p, usable, root, YES, fitting, vx);
        if (p.across[0]) {
            /* a width that follows a height: again, with the heights solved */
            p.other = vx;
            solve_axis(&p, usable, root, NO, fitting, hx);
            if (p.across[1]) {
                p.other = hx;
                solve_axis(&p, usable, root, YES, fitting, vx);
            }
        }
        if (!fitting)
            forget_fitted();
        if (!fitting) {
            /* a window whose content the constraints make bigger or smaller
             * grows or shrinks to fit, keeping its top left corner */
            NSWindow *w = [root window];
            NSSize now = [root frame].size;
            if (w && [w contentView] == root && (fabs(hx[1] - now.width) >= 0.5 || fabs(vx[1] - now.height) >= 0.5)) {
                NSRect f = [w frame];
                NSRect c = [w contentRectForFrameRect:f];
                c.size = NSMakeSize(round(fmax(1, hx[1])), round(fmax(1, vx[1])));
                NSRect nf = [w frameRectForContentRect:c];
                nf.origin.y = NSMaxY(f) - nf.size.height;
                [w setFrame:nf display:NO];
            }
            /* outermost first, so a view's frame is set after its superview's */
            for (NSUInteger k = 1; k < n; k++) {
                id item = p.items[k];
                if (placed_by_superview(item))
                    continue;
                int pi = item_index(&p, parent_of(item));
                double px = pi >= 0 ? hx[2 * pi] : 0, py = pi >= 0 ? vx[2 * pi] : 0;
                double ph = pi >= 0 ? vx[2 * pi + 1] : [parent_of(item) bounds].size.height;
                /* the frame around the alignment rect solved for */
                NSEdgeInsets e = insets_of(item);
                double w = fmax(0, hx[2 * k + 1]) + e.left + e.right, h = fmax(0, vx[2 * k + 1]) + e.top + e.bottom;
                NSRect f = frame_from(item, hx[2 * k] - e.left, w, vx[2 * k] - e.top, h, px, py, ph);
                f = NSMakeRect(round(f.origin.x * 2) / 2, round(f.origin.y * 2) / 2, round(w * 2) / 2,
                               round(h * 2) / 2);
                if ([item isKindOfClass:[NSView class]]) {
                    if (!NSEqualRects(f, [(NSView *)item frame]))
                        [(NSView *)item setFrame:f];
                } else {
                    [(NSLayoutGuide *)item _setFrame:f];
                }
            }
            for (NSUInteger k = 1; k < n && again; k++) {
                id item = p.items[k];
                if (!placed_by_superview(item))
                    continue;
                NSEdgeInsets e = insets_of(item);
                NSSize now = [(NSView *)item frame].size;
                now.width -= e.left + e.right, now.height -= e.top + e.bottom;
                if (fabs(now.width - hx[2 * k + 1]) >= 0.5 || fabs(now.height - vx[2 * k + 1]) >= 0.5)
                    *again = YES;
            }
        }
    } @finally {
        if (!fitting)
            forget_fitted();
        solving = wasSolving;
    }
    NSSize size = NSMakeSize(fmax(0, hx[1]), fmax(0, vx[1]));
    free(hx);
    free(vx);
    free(p.rows);
    return size;
}

/* Solves the constraints of root's subtree, again while what the solver
 * doesn't place settles (a few times at most). */
static NSSize solve(NSView *root, BOOL fitting)
{
    NSSize size = NSZeroSize;
    for (int i = 0; i < 4; i++) {
        BOOL again = NO;
        size = solve_once(root, fitting, fitting || i == 3 ? NULL : &again);
        if (!again)
            break;
    }
    return size;
}

/* ---- updating constraints --------------------------------------------------------------- */

static void update_subtree(NSView *v)
{
    for (NSView *s in [[[v subviews] copy] autorelease])
        update_subtree(s);
    if ([objc_getAssociatedObject(v, &update_key) boolValue])
        [v updateConstraints];
}

/* For the layout pass (NSStackView.m's layoutSubtreeIfNeeded and the
 * window's display): solves root's constraints when anything has changed. */
void ALayoutConstraintsIfNeeded(NSView *v)
{
    if (!AConstraintsInUse || solving || !v)
        return;
    NSView *root = root_of(v);
    NSWindow *w = [root window];
    if (w && [w contentView] && ([[w contentView] isDescendantOf:root] || root == [w contentView]))
        root = [w contentView];
    if (updates_pending) {
        updates_pending = NO;
        update_subtree(root);
    }
    NSNumber *done = objc_getAssociatedObject(root, &solved_key);
    if (done && [done unsignedLongValue] == generation)
        return;
    solve(root, NO);
    objc_setAssociatedObject(root, &solved_key, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* The smallest size v's own constraints allow; NO when it has none. A
 * fitting solve moves nothing, so one may run while the window's
 * constraints are being solved (a stack view measuring its views). */
BOOL AConstraintFittingSize(NSView *v, NSSize *size)
{
    if (!AConstraintsInUse || fit_depth > 8)
        return NO;
    fitted *known = remembered(v);
    if (known) {
        *size = known->size;
        return known->ok;
    }
    NSMutableArray *cs = [NSMutableArray array], *gs = [NSMutableArray array];
    collect(v, cs, gs);
    if (![cs count]) {
        remember(v, NO, NSZeroSize);
        return NO;
    }
    if (!solving)
        update_subtree(v);
    fit_depth++;
    @try {
        *size = solve(v, YES);
    } @finally {
        fit_depth--;
    }
    remember(v, YES, *size);
    return YES;
}

/* Whether the constraints inside v let it grow along one axis when pulled
 * at priority pr: how firmly its content sets its length. */
BOOL AConstraintStretches(NSView *v, BOOL vertical, NSLayoutPriority pr)
{
    NSSize fit, pulled;
    if (!AConstraintFittingSize(v, &fit))
        return YES;
    double oldPull = fit_pull;
    BOOL oldVertical = fit_pull_vertical;
    fit_pull = pr, fit_pull_vertical = vertical;
    @try {
        AConstraintFittingSize(v, &pulled);
    } @finally {
        fit_pull = oldPull, fit_pull_vertical = oldVertical;
    }
    return vertical ? pulled.height > fit.height + 0.5 : pulled.width > fit.width + 0.5;
}

/* A view's frame or intrinsic size changed (NSView.m, NSStackView.m). */
void AConstraintsViewChanged(NSView *v)
{
    if (AConstraintsInUse && !solving)
        changed(v);
}

/* A view left its superview: the constraints between it (or what is inside
 * it) and views outside go, as on a Mac. */
void AConstraintsViewRemoved(NSView *v, NSView *oldSuperview)
{
    if (!AConstraintsInUse || ![all_active count])
        return;
    for (NSLayoutConstraint *c in [[all_active allObjects] copy]) {
        NSView *container = [c _container];
        BOOL containerInside = container == v || [container isDescendantOf:v];
        if (containerInside)
            continue;
        for (id item in [c _items]) {
            NSView *iv = view_of(item);
            if (iv == v || [iv isDescendantOf:v]) {
                [c setActive:NO];
                break;
            }
        }
    }
    changed(oldSuperview);
}

/* A view is going away: its constraints, and the ones naming it, go too. */
void AConstraintsViewDying(NSView *v)
{
    if (!AConstraintsInUse)
        return;
    for (NSLayoutConstraint *c in [[[all_active allObjects] copy] autorelease])
        if ([c _container] == v || [c _involves:v])
            [[c _container] removeConstraint:c];
    for (NSLayoutGuide *g in objc_getAssociatedObject(v, &guides_key))
        [g setOwningView:nil];
}

/* ---- NSView ----------------------------------------------------------------------------- */

@implementation NSView (NSConstraintBasedLayoutInstallingConstraints)
- (NSArray *)constraints { return [[installed(self, NO) copy] autorelease] ?: @[]; }
- (void)addConstraint:(NSLayoutConstraint *)c
{
    if (!c)
        return;
    if ([c _container] == self)
        return;
    if ([c _container])
        [[c _container] removeConstraint:c];
    for (id item in [c _items]) {
        NSView *iv = view_of(item);
        if (iv && iv != self && ![iv isDescendantOf:self])
            [NSException raise:NSGenericException
                        format:@"NSView: %@ can't hold %@, which names a view outside it", self, c];
    }
    AConstraintsInUse = YES;
    if (!all_active)
        all_active = [[NSMutableSet alloc] init];
    [installed(self, YES) addObject:c];
    [all_active addObject:c];
    [c _setContainer:self];
    changed(self);
}
- (void)addConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *c in constraints)
        [self addConstraint:c];
}
- (void)removeConstraint:(NSLayoutConstraint *)c
{
    if ([c _container] != self)
        return;
    [c retain];
    [c _setContainer:nil];
    [all_active removeObject:c];
    [installed(self, NO) removeObjectIdenticalTo:c];
    [c release];
    changed(self);
}
- (void)removeConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *c in [[constraints copy] autorelease])
        [self removeConstraint:c];
}
ANCHOR(leadingAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeLeading)
ANCHOR(trailingAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeTrailing)
ANCHOR(leftAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeLeft)
ANCHOR(rightAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeRight)
ANCHOR(centerXAnchor, NSLayoutXAxisAnchor, NSLayoutAttributeCenterX)
ANCHOR(topAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeTop)
ANCHOR(bottomAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeBottom)
ANCHOR(centerYAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeCenterY)
ANCHOR(firstBaselineAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeFirstBaseline)
ANCHOR(lastBaselineAnchor, NSLayoutYAxisAnchor, NSLayoutAttributeLastBaseline)
ANCHOR(widthAnchor, NSLayoutDimension, NSLayoutAttributeWidth)
ANCHOR(heightAnchor, NSLayoutDimension, NSLayoutAttributeHeight)
- (NSArray *)layoutGuides { return [[objc_getAssociatedObject(self, &guides_key) copy] autorelease] ?: @[]; }
- (void)addLayoutGuide:(NSLayoutGuide *)g
{
    NSMutableArray *a = objc_getAssociatedObject(self, &guides_key);
    if (!a) {
        a = [NSMutableArray array];
        objc_setAssociatedObject(self, &guides_key, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([a indexOfObjectIdenticalTo:g] == NSNotFound) {
        [[g owningView] removeLayoutGuide:g];
        [a addObject:g];
        [g setOwningView:self];
        changed(self);
    }
}
- (void)removeLayoutGuide:(NSLayoutGuide *)g
{
    NSMutableArray *a = objc_getAssociatedObject(self, &guides_key);
    if ([a indexOfObjectIdenticalTo:g] == NSNotFound)
        return;
    for (NSLayoutConstraint *c in [[[all_active allObjects] copy] autorelease])
        if ([c _involves:g])
            [[c _container] removeConstraint:c];
    [g setOwningView:nil];
    [a removeObjectIdenticalTo:g];
    changed(self);
}
@end

@implementation NSView (NSConstraintBasedLayoutCoreMethods)
- (void)updateConstraintsForSubtreeIfNeeded { update_subtree(self); }
- (void)updateConstraints
{
    objc_setAssociatedObject(self, &update_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)needsUpdateConstraints { return [objc_getAssociatedObject(self, &update_key) boolValue]; }
- (void)setNeedsUpdateConstraints:(BOOL)flag
{
    objc_setAssociatedObject(self, &update_key, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (flag) {
        AConstraintsInUse = YES;
        updates_pending = YES;
        changed(self);
    }
}
+ (BOOL)requiresConstraintBasedLayout { return NO; }
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
- (NSRect)alignmentRectForFrame:(NSRect)f
{
    NSEdgeInsets e = [self alignmentRectInsets];
    return NSMakeRect(f.origin.x + e.left, f.origin.y + e.bottom, f.size.width - e.left - e.right,
                      f.size.height - e.top - e.bottom);
}
- (NSRect)frameForAlignmentRect:(NSRect)r
{
    NSEdgeInsets e = [self alignmentRectInsets];
    return NSMakeRect(r.origin.x - e.left, r.origin.y - e.bottom, r.size.width + e.left + e.right,
                      r.size.height + e.top + e.bottom);
}
- (CGFloat)baselineOffsetFromBottom { return 0; }
- (CGFloat)lastBaselineOffsetFromBottom { return [self baselineOffsetFromBottom]; }
- (CGFloat)firstBaselineOffsetFromTop { return [self frame].size.height - [self baselineOffsetFromBottom]; }
@end

@implementation NSView (NSConstraintBasedLayoutDebugging)
- (NSArray *)constraintsAffectingLayoutForOrientation:(NSLayoutConstraintOrientation)o
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSLayoutConstraint *c in all_active)
        if ([c _involves:self] && horizontal([c firstAttribute]) == (o == NSLayoutConstraintOrientationHorizontal))
            [out addObject:c];
    return out;
}
- (BOOL)hasAmbiguousLayout { return NO; }
- (void)exerciseAmbiguityInLayout {}
@end

/* NSView (NSConstraintBasedLayoutCoreMethods) declares nothing else here;
 * decoding a nib's constraints (NSView.m calls this). */
void AViewDecodeConstraints(NSView *v, NSCoder *c)
{
    if ([c containsValueForKey:@"NSDoNotTranslateAutoresizingMask"] &&
        [c decodeBoolForKey:@"NSDoNotTranslateAutoresizingMask"])
        [v setTranslatesAutoresizingMaskIntoConstraints:NO];
    /* content hugging and compression resistance, each "{horizontal, vertical}" */
    static NSString *const priority_keys[2] = {@"NSHuggingPriority", @"NSAntiCompressionPriority"};
    for (int k = 0; k < 2; k++) {
        NSString *pair = [c containsValueForKey:priority_keys[k]] ? [c decodeObjectForKey:priority_keys[k]] : nil;
        if (![pair isKindOfClass:[NSString class]])
            continue;
        NSSize p = NSSizeFromString(pair);
        if (k == 0) {
            [v setContentHuggingPriority:(NSLayoutPriority)p.width forOrientation:NSLayoutConstraintOrientationHorizontal];
            [v setContentHuggingPriority:(NSLayoutPriority)p.height forOrientation:NSLayoutConstraintOrientationVertical];
        } else {
            [v setContentCompressionResistancePriority:(NSLayoutPriority)p.width
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
            [v setContentCompressionResistancePriority:(NSLayoutPriority)p.height
                                        forOrientation:NSLayoutConstraintOrientationVertical];
        }
    }
    if (![c containsValueForKey:@"NSViewConstraints"])
        return;
    id list = [c decodeObjectForKey:@"NSViewConstraints"];
    if ([list isKindOfClass:[NSArray class]])
        for (id x in list)
            if ([x isKindOfClass:[NSLayoutConstraint class]] && [x firstItem])
                [v addConstraint:x];
}

/* ---- NSWindow --------------------------------------------------------------------------- */

@implementation NSWindow (NSConstraintBasedLayout)
- (void)updateConstraintsIfNeeded { [[self contentView] updateConstraintsForSubtreeIfNeeded]; }
- (void)layoutIfNeeded { [[self contentView] layoutSubtreeIfNeeded]; }
- (void)setNeedsLayout:(BOOL)flag
{
    if (flag)
        [[self contentView] setNeedsLayout:YES];
}
- (void)setNeedsUpdateConstraints:(BOOL)flag { [[self contentView] setNeedsUpdateConstraints:flag]; }
- (void)visualizeConstraints:(NSArray *)constraints {}
- (id)contentLayoutGuide
{
    NSView *content = [self contentView];
    if (!content)
        return nil;
    NSLayoutGuide *g = objc_getAssociatedObject(self, &guide_key);
    if (!g || [g owningView] != content) {
        g = [[[NSLayoutGuide alloc] init] autorelease];
        [g _setContentGuide:YES];
        [g setIdentifier:@"NSWindow-contentLayoutGuide"];
        [content addLayoutGuide:g];
        objc_setAssociatedObject(self, &guide_key, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return g;
}
- (NSRect)contentLayoutRect { return [[self contentView] bounds]; }
- (NSLayoutAttribute)anchorAttributeForOrientation:(NSLayoutConstraintOrientation)o
{
    return o == NSLayoutConstraintOrientationHorizontal ? NSLayoutAttributeLeft : NSLayoutAttributeTop;
}
@end
