/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CALayer, written from Apple's public
 * documentation. A layer keeps its properties as objects in a dictionary
 * (numbers, NSValues of points, sizes and rectangles, transforms, colours,
 * paths, images), filled at first with its class's defaults; the declared
 * properties are @dynamic and their accessors are made on first use from
 * the property's type, for this class, its kinds and any subclass an app
 * declares with @dynamic, as on a Mac. A layer is a key-value coding
 * container: keys it doesn't declare are kept with it too.
 *
 * Changing a property looks up its action (the delegate's, the actions
 * dictionary, the style, the class's default, then an implicit basic
 * animation from the value shown now for the animatable properties) and
 * runs it, unless the transaction disables actions or the layer hasn't yet
 * been committed. The layer tree is drawn by QRender.m. */
#import "QInternal.h"
#include <ctype.h>

CALayerContentsGravity const kCAGravityCenter = @"center";
CALayerContentsGravity const kCAGravityTop = @"top";
CALayerContentsGravity const kCAGravityBottom = @"bottom";
CALayerContentsGravity const kCAGravityLeft = @"left";
CALayerContentsGravity const kCAGravityRight = @"right";
CALayerContentsGravity const kCAGravityTopLeft = @"topLeft";
CALayerContentsGravity const kCAGravityTopRight = @"topRight";
CALayerContentsGravity const kCAGravityBottomLeft = @"bottomLeft";
CALayerContentsGravity const kCAGravityBottomRight = @"bottomRight";
CALayerContentsGravity const kCAGravityResize = @"resize";
CALayerContentsGravity const kCAGravityResizeAspect = @"resizeAspect";
CALayerContentsGravity const kCAGravityResizeAspectFill = @"resizeAspectFill";
CALayerContentsFilter const kCAFilterNearest = @"nearest";
CALayerContentsFilter const kCAFilterLinear = @"linear";
CALayerCornerCurve const kCACornerCurveCircular = @"circular";
CALayerCornerCurve const kCACornerCurveContinuous = @"continuous";
CALayerContentsFilter const kCAFilterTrilinear = @"trilinear";
CALayerContentsFormat const kCAContentsFormatRGBA8Uint = @"RGBA8";
NSString *const kCAOnOrderIn = @"onOrderIn";
NSString *const kCAOnOrderOut = @"onOrderOut";
NSString *const kCATransition = @"transition";

/* ---- values from a dictionary ------------------------------------------------------ */

CGFloat QNum(NSDictionary *v, NSString *key) { return [v[key] doubleValue]; }
BOOL QBool(NSDictionary *v, NSString *key) { return [v[key] doubleValue] > 0.5; }
id QObj(NSDictionary *v, NSString *key) { return v[key]; }
CGColorRef QColor(NSDictionary *v, NSString *key)
{
    id c = v[key];
    return QIsColor(c) ? (CGColorRef)c : NULL;
}
static CGPoint point_of(id x) { return [x isKindOfClass:[NSValue class]] ? [x pointValue] : CGPointZero; }
static CGSize size_of(id x) { return [x isKindOfClass:[NSValue class]] ? [x sizeValue] : CGSizeZero; }
static CGRect rect_of(id x) { return [x isKindOfClass:[NSValue class]] ? [x rectValue] : CGRectZero; }
static CATransform3D transform_of(id x)
{
    return [x isKindOfClass:[QTransformValue class]] ? ((QTransformValue *)x)->t : CATransform3DIdentity;
}
CGPoint QPoint(NSDictionary *v, NSString *key) { return point_of(v[key]); }
CGSize QSize(NSDictionary *v, NSString *key) { return size_of(v[key]); }
CGRect QRect(NSDictionary *v, NSString *key) { return rect_of(v[key]); }
CATransform3D QTransform(NSDictionary *v, NSString *key) { return transform_of(v[key]); }

/* ---- accessors for @dynamic properties ------------------------------------------- */

static NSMutableDictionary *accessor_keys;   /* selector name -> key */
static NSMutableSet *copying_setters;

static NSString *key_of(SEL sel) { return accessor_keys[NSStringFromSelector(sel)]; }

static id get_obj(CALayer *self, SEL _cmd) { return [self _ferryValueForKey:key_of(_cmd)]; }
static void set_obj(CALayer *self, SEL _cmd, id v)
{
    if ([copying_setters containsObject:NSStringFromSelector(_cmd)])
        v = [[v copy] autorelease];
    [self _ferrySetValue:v forKey:key_of(_cmd)];
}
static void *get_ptr(CALayer *self, SEL _cmd) { return (void *)[self _ferryValueForKey:key_of(_cmd)]; }
static void set_ptr(CALayer *self, SEL _cmd, void *v) { [self _ferrySetValue:(id)v forKey:key_of(_cmd)]; }
static double get_d(CALayer *self, SEL _cmd) { return [[self _ferryValueForKey:key_of(_cmd)] doubleValue]; }
static void set_d(CALayer *self, SEL _cmd, double v) { [self _ferrySetValue:@(v) forKey:key_of(_cmd)]; }
static float get_f(CALayer *self, SEL _cmd) { return [[self _ferryValueForKey:key_of(_cmd)] floatValue]; }
static void set_f(CALayer *self, SEL _cmd, float v) { [self _ferrySetValue:@(v) forKey:key_of(_cmd)]; }
static int get_i(CALayer *self, SEL _cmd) { return [[self _ferryValueForKey:key_of(_cmd)] intValue]; }
static void set_i(CALayer *self, SEL _cmd, int v) { [self _ferrySetValue:@(v) forKey:key_of(_cmd)]; }
static unsigned get_I(CALayer *self, SEL _cmd) { return [[self _ferryValueForKey:key_of(_cmd)] unsignedIntValue]; }
static void set_I(CALayer *self, SEL _cmd, unsigned v) { [self _ferrySetValue:@(v) forKey:key_of(_cmd)]; }
static long long get_q(CALayer *self, SEL _cmd) { return [[self _ferryValueForKey:key_of(_cmd)] longLongValue]; }
static void set_q(CALayer *self, SEL _cmd, long long v) { [self _ferrySetValue:@(v) forKey:key_of(_cmd)]; }
static unsigned long long get_Q(CALayer *self, SEL _cmd)
{
    return [[self _ferryValueForKey:key_of(_cmd)] unsignedLongLongValue];
}
static void set_Q(CALayer *self, SEL _cmd, unsigned long long v) { [self _ferrySetValue:@(v) forKey:key_of(_cmd)]; }
static BOOL get_B(CALayer *self, SEL _cmd) { return [[self _ferryValueForKey:key_of(_cmd)] doubleValue] > 0.5; }
static void set_B(CALayer *self, SEL _cmd, BOOL v) { [self _ferrySetValue:@((BOOL)!!v) forKey:key_of(_cmd)]; }
static CGPoint get_point(CALayer *self, SEL _cmd)
{
    return point_of([self _ferryValueForKey:key_of(_cmd)]);
}
static void set_point(CALayer *self, SEL _cmd, CGPoint v)
{
    [self _ferrySetValue:[NSValue valueWithPoint:v] forKey:key_of(_cmd)];
}
static CGSize get_size(CALayer *self, SEL _cmd)
{
    return size_of([self _ferryValueForKey:key_of(_cmd)]);
}
static void set_size(CALayer *self, SEL _cmd, CGSize v) { [self _ferrySetValue:[NSValue valueWithSize:v] forKey:key_of(_cmd)]; }
static CGRect get_rect(CALayer *self, SEL _cmd)
{
    return rect_of([self _ferryValueForKey:key_of(_cmd)]);
}
static void set_rect(CALayer *self, SEL _cmd, CGRect v) { [self _ferrySetValue:[NSValue valueWithRect:v] forKey:key_of(_cmd)]; }
static CATransform3D get_transform(CALayer *self, SEL _cmd)
{
    return transform_of([self _ferryValueForKey:key_of(_cmd)]);
}
static void set_transform(CALayer *self, SEL _cmd, CATransform3D v)
{
    [self _ferrySetValue:[NSValue valueWithCATransform3D:v] forKey:key_of(_cmd)];
}

/* The accessor for a property's type code: getter or setter. */
static IMP accessor_for(const char *type, BOOL setter, char *types, size_t n)
{
    struct {
        const char *prefix;
        IMP get, set;
        const char *enc;
    } table[] = {
        {"@", (IMP)get_obj, (IMP)set_obj, "@"},
        {"^", (IMP)get_ptr, (IMP)set_ptr, "^v"},
        {"r^", (IMP)get_ptr, (IMP)set_ptr, "^v"},
        {"d", (IMP)get_d, (IMP)set_d, "d"},
        {"f", (IMP)get_f, (IMP)set_f, "f"},
        {"i", (IMP)get_i, (IMP)set_i, "i"},
        {"I", (IMP)get_I, (IMP)set_I, "I"},
        {"q", (IMP)get_q, (IMP)set_q, "q"},
        {"l", (IMP)get_q, (IMP)set_q, "q"},
        {"Q", (IMP)get_Q, (IMP)set_Q, "Q"},
        {"L", (IMP)get_Q, (IMP)set_Q, "Q"},
        {"B", (IMP)get_B, (IMP)set_B, "B"},
        {"c", (IMP)get_B, (IMP)set_B, "c"},
        {"{CGPoint", (IMP)get_point, (IMP)set_point, "{CGPoint=dd}"},
        {"{CGSize", (IMP)get_size, (IMP)set_size, "{CGSize=dd}"},
        {"{CGRect", (IMP)get_rect, (IMP)set_rect, "{CGRect={CGPoint=dd}{CGSize=dd}}"},
        {"{CATransform3D", (IMP)get_transform, (IMP)set_transform, "{CATransform3D=dddddddddddddddd}"},
    };
    for (size_t i = 0; i < sizeof table / sizeof *table; i++) {
        size_t len = strlen(table[i].prefix);
        if (strncmp(type, table[i].prefix, len) != 0)
            continue;
        if (table[i].prefix[0] == '{' && type[len] != '=' && type[len] != '}')
            continue;
        if (setter)
            snprintf(types, n, "v@:%s", table[i].enc);
        else
            snprintf(types, n, "%s@:", table[i].enc);
        return setter ? table[i].set : table[i].get;
    }
    return NULL;
}

/* Makes the accessor sel names, if a @dynamic property of cls or a class
 * above it (up to CALayer) declares it. */
static BOOL add_dynamic_accessor(Class cls, SEL sel)
{
    const char *want = sel_getName(sel);
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        unsigned count = 0;
        objc_property_t *props = class_copyPropertyList(c, &count);
        for (unsigned i = 0; i < count; i++) {
            const char *attrs = property_getAttributes(props[i]);
            if (!attrs || attrs[0] != 'T')
                continue;
            char buf[512];
            snprintf(buf, sizeof buf, "%s", attrs);
            char *type = buf + 1, *rest = strchr(buf, ',');
            if (rest)
                *rest++ = 0;
            BOOL dynamic = NO, copying = NO, readonly = NO;
            const char *getter = NULL, *setterName = NULL;
            for (char *a = rest; a && *a;) {
                char *next = strchr(a, ',');
                if (next)
                    *next++ = 0;
                if (a[0] == 'D')
                    dynamic = YES;
                else if (a[0] == 'C')
                    copying = YES;
                else if (a[0] == 'R')
                    readonly = YES;
                else if (a[0] == 'G')
                    getter = a + 1;
                else if (a[0] == 'S')
                    setterName = a + 1;
                a = next;
            }
            if (!dynamic)
                continue;
            const char *name = property_getName(props[i]);
            char setbuf[300];
            if (!setterName) {
                snprintf(setbuf, sizeof setbuf, "set%c%s:", toupper((unsigned char)name[0]), name + 1);
                setterName = setbuf;
            }
            BOOL isGetter = strcmp(want, getter ? getter : name) == 0;
            BOOL isSetter = !readonly && strcmp(want, setterName) == 0;
            if (!isGetter && !isSetter)
                continue;
            char types[128];
            IMP imp = accessor_for(type, isSetter, types, sizeof types);
            if (!imp)
                continue;
            if (!accessor_keys) {
                accessor_keys = [[NSMutableDictionary alloc] init];
                copying_setters = [[NSMutableSet alloc] init];
            }
            NSString *selName = [NSString stringWithUTF8String:want];
            accessor_keys[selName] = [NSString stringWithUTF8String:name];
            if (isSetter && copying)
                [copying_setters addObject:selName];
            free(props);
            return class_addMethod(c, sel, imp, types);
        }
        free(props);
        if (c == [CALayer class])
            break;
    }
    return NO;
}

/* ---- CALayer ---------------------------------------------------------------------- */

@implementation CALayer {
    NSMutableDictionary *_values;
    CALayer *_superlayer;           /* not retained */
    NSMutableArray *_sublayers;
    CALayer *_mask;
    id _delegate;                   /* weak */
    id _host;                       /* not retained */
    NSMutableArray *_animations;    /* of QRunning */
    CALayer *_model;                /* for a presentation layer */
    NSUInteger _bornIn;             /* the transaction it was made in */
    BOOL _presentation, _rendered, _needsDisplay, _needsLayout;
    id _pendingValue;               /* the value being set, while its action is found */
}

@dynamic bounds, position, zPosition, anchorPoint, anchorPointZ, transform, hidden, doubleSided, geometryFlipped,
    sublayerTransform, masksToBounds, contents, contentsRect, contentsGravity, contentsScale, contentsCenter,
    contentsFormat, minificationFilter, magnificationFilter, minificationFilterBias, opaque,
    needsDisplayOnBoundsChange, drawsAsynchronously, edgeAntialiasingMask, allowsEdgeAntialiasing, backgroundColor,
    cornerRadius, maskedCorners, cornerCurve, borderWidth, borderColor, opacity, allowsGroupOpacity, compositingFilter, filters,
    backgroundFilters, shouldRasterize, rasterizationScale, shadowColor, shadowOpacity, shadowOffset, shadowRadius,
    shadowPath, layoutManager, autoresizingMask, actions, name, style, beginTime, duration, speed, timeOffset,
    repeatCount, repeatDuration, autoreverses, fillMode;

+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)layer { return [[[self alloc] init] autorelease]; }

+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    if (add_dynamic_accessor(self, sel))
        return YES;
    return [super resolveInstanceMethod:sel];
}

+ (NSSet *)_ferryKnownKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[NSSet setWithArray:@[
            @"bounds", @"position", @"zPosition", @"anchorPoint", @"anchorPointZ", @"transform", @"hidden",
            @"doubleSided", @"geometryFlipped", @"sublayerTransform", @"masksToBounds", @"contents",
            @"contentsRect", @"contentsGravity", @"contentsScale", @"contentsCenter", @"contentsFormat",
            @"minificationFilter", @"magnificationFilter", @"minificationFilterBias", @"opaque",
            @"needsDisplayOnBoundsChange", @"drawsAsynchronously", @"edgeAntialiasingMask",
            @"allowsEdgeAntialiasing", @"backgroundColor", @"cornerRadius", @"maskedCorners", @"cornerCurve",
            @"borderWidth", @"borderColor", @"opacity", @"allowsGroupOpacity", @"compositingFilter", @"filters",
            @"backgroundFilters", @"shouldRasterize", @"rasterizationScale", @"shadowColor", @"shadowOpacity",
            @"shadowOffset", @"shadowRadius", @"shadowPath", @"layoutManager", @"autoresizingMask", @"actions",
            @"name", @"style", @"beginTime", @"duration", @"speed", @"timeOffset", @"repeatCount",
            @"repeatDuration", @"autoreverses", @"fillMode"
        ]] retain];
    return keys;
}

+ (NSSet *)_ferryAnimatableKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[NSSet setWithArray:@[
            @"bounds", @"position", @"zPosition", @"anchorPoint", @"anchorPointZ", @"transform",
            @"sublayerTransform", @"contentsRect", @"contentsCenter", @"backgroundColor", @"cornerRadius",
            @"borderWidth", @"borderColor", @"opacity", @"shadowColor", @"shadowOpacity", @"shadowOffset",
            @"shadowRadius", @"shadowPath", @"minificationFilterBias", @"rasterizationScale"
        ]] retain];
    return keys;
}

+ (id)defaultValueForKey:(NSString *)key
{
    static NSDictionary *defaults;
    if (!defaults) {
        CGColorRef black = CGColorCreateSRGB(0, 0, 0, 1);
        defaults = [@{
            @"bounds" : [NSValue valueWithRect:CGRectZero],
            @"position" : [NSValue valueWithPoint:CGPointZero],
            @"zPosition" : @0.0,
            @"anchorPoint" : [NSValue valueWithPoint:CGPointMake(0.5, 0.5)],
            @"anchorPointZ" : @0.0,
            @"transform" : [NSValue valueWithCATransform3D:CATransform3DIdentity],
            @"sublayerTransform" : [NSValue valueWithCATransform3D:CATransform3DIdentity],
            @"hidden" : @NO,
            @"doubleSided" : @YES,
            @"geometryFlipped" : @NO,
            @"masksToBounds" : @NO,
            @"contentsRect" : [NSValue valueWithRect:CGRectMake(0, 0, 1, 1)],
            @"contentsGravity" : kCAGravityResize,
            @"contentsScale" : @1.0,
            @"contentsCenter" : [NSValue valueWithRect:CGRectMake(0, 0, 1, 1)],
            @"contentsFormat" : kCAContentsFormatRGBA8Uint,
            @"minificationFilter" : kCAFilterLinear,
            @"magnificationFilter" : kCAFilterLinear,
            @"minificationFilterBias" : @0.0f,
            @"opaque" : @NO,
            @"needsDisplayOnBoundsChange" : @NO,
            @"drawsAsynchronously" : @NO,
            @"edgeAntialiasingMask" : @15u,
            @"allowsEdgeAntialiasing" : @NO,
            @"cornerRadius" : @0.0,
            @"maskedCorners" : @15u,
            @"cornerCurve" : kCACornerCurveCircular,
            @"borderWidth" : @0.0,
            @"borderColor" : (id)black,
            @"opacity" : @1.0f,
            @"allowsGroupOpacity" : @YES,
            @"shouldRasterize" : @NO,
            @"rasterizationScale" : @1.0,
            @"shadowColor" : (id)black,
            @"shadowOpacity" : @0.0f,
            @"shadowOffset" : [NSValue valueWithSize:CGSizeMake(0, -3)],
            @"shadowRadius" : @3.0,
            @"autoresizingMask" : @0u,
            @"beginTime" : @0.0,
            @"duration" : @0.0,
            @"speed" : @1.0f,
            @"timeOffset" : @0.0,
            @"repeatCount" : @0.0f,
            @"repeatDuration" : @0.0,
            @"autoreverses" : @NO,
            @"fillMode" : kCAFillModeRemoved,
        } retain];
        CGColorRelease(black);
    }
    return defaults[key];
}

/* The class's defaults for its known keys, worked out once. */
+ (NSDictionary *)_ferryDefaults
{
    static NSMutableDictionary *byClass;
    if (!byClass)
        byClass = [[NSMutableDictionary alloc] init];
    NSString *name = NSStringFromClass(self);
    NSDictionary *d = byClass[name];
    if (!d) {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSString *k in [self _ferryKnownKeys]) {
            id v = [self defaultValueForKey:k];
            if (v)
                m[k] = v;
        }
        byClass[name] = m;
        d = m;
    }
    return d;
}

+ (BOOL)needsDisplayForKey:(NSString *)key { return NO; }
- (BOOL)shouldArchiveValueForKey:(NSString *)key { return YES; }

- (instancetype)init
{
    if ((self = [super init])) {
        _values = [[[self class] _ferryDefaults] mutableCopy];
        _bornIn = QCurrentTransactionSerial();
    }
    return self;
}

- (instancetype)initWithLayer:(id)layer
{
    if ((self = [super init])) {
        CALayer *other = layer;
        _values = [other->_values mutableCopy];
        _delegate = other->_delegate;
        _rendered = YES;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        for (NSString *k in [[self class] _ferryKnownKeys])
            if ([coder containsValueForKey:k]) {
                id v = [coder decodeObjectForKey:k];
                if (v)
                    _values[k] = v;
            }
        for (CALayer *s in [coder decodeObjectForKey:@"sublayers"])
            [self addSublayer:s];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    for (NSString *k in _values) {
        id v = _values[k];
        if ([self shouldArchiveValueForKey:k] && [v conformsToProtocol:@protocol(NSCoding)])
            [coder encodeObject:v forKey:k];
    }
    if ([_sublayers count])
        [coder encodeObject:_sublayers forKey:@"sublayers"];
}

- (void)dealloc
{
    if (!_presentation)
        [self removeAllAnimations];
    for (CALayer *s in _sublayers)
        s->_superlayer = nil;
    [_sublayers release];
    [_mask release];
    [_animations release];
    [_values release];
    [_model release];
    [super dealloc];
}

/* ---- the stored values ---- */

- (NSDictionary *)_ferryValues { return _values; }

- (id)_ferryValueForKey:(NSString *)key
{
    id v = _values[key];
    if (v || [[[self class] _ferryKnownKeys] containsObject:key])
        return v;
    return [[self class] defaultValueForKey:key];
}

- (BOOL)_ferryLive
{
    if (_presentation)
        return NO;
    if (!_rendered && QTransactionIsOpen(_bornIn))
        return NO;
    return YES;
}

- (void)_ferrySetValue:(id)value forKey:(NSString *)key
{
    if (!key)
        return;
    id<CAAction> action = nil;
    if ([self _ferryLive] && ![CATransaction disableActions]) {
        _pendingValue = value;
        action = [(id)[self actionForKey:key] retain];
        _pendingValue = nil;
    }
    id old = [_values[key] retain];
    if (value)
        _values[key] = value;
    else
        [_values removeObjectForKey:key];
    if (!_presentation) {
        if ([key isEqualToString:@"bounds"]) {
            CGSize was = [old isKindOfClass:[NSValue class]] ? [old rectValue].size : CGSizeZero;
            CGSize now = QRect(_values, @"bounds").size;
            if (!CGSizeEqualToSize(was, now)) {
                if (QBool(_values, @"needsDisplayOnBoundsChange"))
                    [self setNeedsDisplay];
                [self setNeedsLayout];
                [self resizeSublayersWithOldSize:was];
            }
        } else if ([[self class] needsDisplayForKey:key]) {
            [self setNeedsDisplay];
        }
        [action runActionForKey:key object:self arguments:nil];
    }
    [(id)action release];
    [old release];
    [self _ferryChanged];
}

- (id)valueForKey:(NSString *)key
{
    if ([[[self class] _ferryKnownKeys] containsObject:key])
        return _values[key];
    if ([self respondsToSelector:NSSelectorFromString(key)])
        return [super valueForKey:key];
    return [self _ferryValueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
    if ([[[self class] _ferryKnownKeys] containsObject:key]) {
        [self _ferrySetValue:value forKey:key];
        return;
    }
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString],
                                                  [key substringFromIndex:1]];
    if ([key length] && [self respondsToSelector:NSSelectorFromString(setter)]) {
        [super setValue:value forKey:key];
        return;
    }
    [self _ferrySetValue:value forKey:key];
}

- (id)valueForKeyPath:(NSString *)keyPath
{
    NSRange dot = [keyPath rangeOfString:@"."];
    if (dot.location != NSNotFound) {
        NSString *first = [keyPath substringToIndex:dot.location];
        id whole = [self valueForKey:first];
        if ([whole isKindOfClass:[NSValue class]] && ![whole isKindOfClass:[NSNumber class]])
            return QFieldGet(whole, [keyPath substringFromIndex:dot.location + 1]);
    }
    return [super valueForKeyPath:keyPath];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath
{
    NSRange dot = [keyPath rangeOfString:@"."];
    if (dot.location != NSNotFound) {
        NSString *first = [keyPath substringToIndex:dot.location];
        id whole = [self valueForKey:first];
        if ([whole isKindOfClass:[NSValue class]] && ![whole isKindOfClass:[NSNumber class]]) {
            id changed = QFieldSet(whole, [keyPath substringFromIndex:dot.location + 1], value);
            if (changed) {
                [self setValue:changed forKey:first];
                return;
            }
        }
    }
    [super setValue:value forKeyPath:keyPath];
}

- (void)setNilValueForKey:(NSString *)key { [self _ferrySetValue:nil forKey:key]; }

/* ---- geometry that isn't stored ---- */

- (CGRect)frame
{
    CGRect b = QRect(_values, @"bounds");
    CGPoint p = QPoint(_values, @"position"), a = QPoint(_values, @"anchorPoint");
    CGRect r = CGRectMake(-a.x * b.size.width, -a.y * b.size.height, b.size.width, b.size.height);
    r = CGRectApplyAffineTransform(r, QAffine2D(QTransform(_values, @"transform")));
    return CGRectOffset(r, p.x, p.y);
}

- (void)setFrame:(CGRect)f
{
    f = CGRectStandardize(f);
    CGRect b = QRect(_values, @"bounds");
    CGPoint a = QPoint(_values, @"anchorPoint");
    CATransform3D t = QTransform(_values, @"transform");
    CGSize size = f.size;
    if (!CATransform3DIsIdentity(t)) {
        /* the bounds that, transformed, fill the frame */
        CGAffineTransform m = QAffine2D(t);
        if (fabs(m.b) < 1e-9 && fabs(m.c) < 1e-9 && m.a != 0 && m.d != 0)
            size = CGSizeMake(f.size.width / fabs(m.a), f.size.height / fabs(m.d));
        else
            size = b.size;
    }
    CGPoint p = CGPointMake(f.origin.x + a.x * f.size.width, f.origin.y + a.y * f.size.height);
    [self _ferrySetValue:[NSValue valueWithPoint:p] forKey:@"position"];
    [self _ferrySetValue:[NSValue valueWithRect:CGRectMake(b.origin.x, b.origin.y, size.width, size.height)]
                  forKey:@"bounds"];
}

- (CGAffineTransform)affineTransform { return CATransform3DGetAffineTransform(QTransform(_values, @"transform")); }
- (void)setAffineTransform:(CGAffineTransform)m
{
    [self _ferrySetValue:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(m)] forKey:@"transform"];
}

- (BOOL)contentsAreFlipped
{
    BOOL flipped = NO;
    CALayer *l = [self modelLayer], *root = l;
    for (CALayer *s = l->_superlayer; s; s = s->_superlayer) {
        if (QBool(s->_values, @"geometryFlipped"))
            flipped = !flipped;
        root = s;
    }
    if ([root->_host respondsToSelector:@selector(isFlipped)] && ((BOOL(*)(id, SEL))objc_msgSend)(root->_host, @selector(isFlipped)))
        flipped = !flipped;
    return flipped;
}

/* ---- the tree ---- */

- (CALayer *)superlayer
{
    if (_presentation)
        return [_model->_superlayer presentationLayer];
    return _superlayer;
}

- (NSArray *)sublayers
{
    if (_presentation) {
        NSMutableArray *a = [NSMutableArray array];
        for (CALayer *s in _model->_sublayers)
            [a addObject:[s presentationLayer]];
        return [a count] ? a : nil;
    }
    return [_sublayers count] ? [[_sublayers copy] autorelease] : nil;
}

- (NSArray *)_ferrySublayers { return _sublayers; }

- (void)setSublayers:(NSArray *)sublayers
{
    for (CALayer *s in [[_sublayers copy] autorelease])
        [s removeFromSuperlayer];
    for (CALayer *s in sublayers)
        [self addSublayer:s];
}

- (void)_ferryRunOrderAction:(NSString *)event
{
    if (![self _ferryLive] || [CATransaction disableActions])
        return;
    [[self actionForKey:event] runActionForKey:event object:self arguments:nil];
}

- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)idx
{
    if (!layer || layer == self || _presentation)
        return;
    [layer retain];
    if (layer->_superlayer) {
        CALayer *was = layer->_superlayer;
        [was->_sublayers removeObjectIdenticalTo:layer];
        layer->_superlayer = nil;
        [was _ferryChanged];
    }
    if (!_sublayers)
        _sublayers = [[NSMutableArray alloc] init];
    if (idx > [_sublayers count])
        idx = (unsigned)[_sublayers count];
    [_sublayers insertObject:layer atIndex:idx];
    layer->_superlayer = self;
    [layer release];
    [layer _ferryRunOrderAction:kCAOnOrderIn];
    [self setNeedsLayout];
    [self _ferryChanged];
}

- (void)addSublayer:(CALayer *)layer { [self insertSublayer:layer atIndex:(unsigned)[_sublayers count]]; }

- (void)insertSublayer:(CALayer *)layer below:(CALayer *)sibling
{
    NSUInteger i = sibling ? [_sublayers indexOfObjectIdenticalTo:sibling] : NSNotFound;
    if (layer->_superlayer == self && i != NSNotFound && [_sublayers indexOfObjectIdenticalTo:layer] < i)
        i--;
    [self insertSublayer:layer atIndex:i == NSNotFound ? 0 : (unsigned)i];
}

- (void)insertSublayer:(CALayer *)layer above:(CALayer *)sibling
{
    NSUInteger i = sibling ? [_sublayers indexOfObjectIdenticalTo:sibling] : NSNotFound;
    if (layer->_superlayer == self && i != NSNotFound && [_sublayers indexOfObjectIdenticalTo:layer] < i)
        i--;
    [self insertSublayer:layer atIndex:i == NSNotFound ? (unsigned)[_sublayers count] : (unsigned)i + 1];
}

- (void)replaceSublayer:(CALayer *)oldLayer with:(CALayer *)newLayer
{
    NSUInteger i = [_sublayers indexOfObjectIdenticalTo:oldLayer];
    if (i == NSNotFound || oldLayer == newLayer)
        return;
    [[oldLayer retain] autorelease];
    [oldLayer removeFromSuperlayer];
    [self insertSublayer:newLayer atIndex:(unsigned)i];
}

- (void)removeFromSuperlayer
{
    CALayer *s = _superlayer;
    if (!s)
        return;
    [[self retain] autorelease];
    [self _ferryRunOrderAction:kCAOnOrderOut];
    [s->_sublayers removeObjectIdenticalTo:self];
    _superlayer = nil;
    [s setNeedsLayout];
    [s _ferryChanged];
}

- (CALayer *)mask { return _mask; }
- (void)setMask:(CALayer *)mask
{
    [mask retain];
    [_mask release];
    _mask = mask;
    [self _ferryChanged];
}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }

- (void)_ferrySetHost:(id)host { _host = host; }
- (id)_ferryHost { return _host; }

- (void)_ferryChanged
{
    if (_presentation)
        return;
    CALayer *l = self;
    while (l->_superlayer)
        l = l->_superlayer;
    if ([l->_host respondsToSelector:@selector(_ferryLayerTreeChanged)])
        [l->_host _ferryLayerTreeChanged];
}

/* ---- presentation ---- */

- (BOOL)_ferryIsPresentation { return _presentation; }

- (NSDictionary *)_ferryPresentationValues
{
    if (![_animations count])
        return _values;
    NSMutableDictionary *v = [[_values mutableCopy] autorelease];
    double t = [self convertTime:QNow() fromLayer:nil];
    for (QRunning *r in [[_animations copy] autorelease]) {
        CAAnimation *a = r->animation;
        if ([a isKindOfClass:[CAPropertyAnimation class]]) {
            NSString *path = [(CAPropertyAnimation *)a keyPath];
            NSRange dot = [path rangeOfString:@"."];
            NSString *first = dot.location == NSNotFound ? path : [path substringToIndex:dot.location];
            if (first && !v[first]) {
                id d = [self _ferryValueForKey:first];
                if (d)
                    v[first] = d;
            }
        }
        [a _ferryApplyAtTime:t to:v layer:self];
    }
    return v;
}

- (instancetype)presentationLayer
{
    if (_presentation)
        return self;
    CALayer *p = [[[self class] alloc] initWithLayer:self];
    if (!p)
        return nil;
    [p->_values release];
    p->_values = [[self _ferryPresentationValues] mutableCopy];
    p->_presentation = YES;
    p->_model = [self retain];
    p->_delegate = _delegate;
    return [p autorelease];
}

- (instancetype)modelLayer { return _presentation ? _model : self; }

/* ---- time ---- */

static double to_local(CALayer *l, double t)
{
    if (!l)
        return t;
    t = to_local(l->_superlayer, t);
    NSDictionary *v = l->_values;
    return (t - QNum(v, @"beginTime")) * QNum(v, @"speed") + QNum(v, @"timeOffset");
}

static double from_local(CALayer *l, double t)
{
    if (!l)
        return t;
    NSDictionary *v = l->_values;
    double speed = QNum(v, @"speed");
    t = (t - QNum(v, @"timeOffset")) / (speed ? speed : 1) + QNum(v, @"beginTime");
    return from_local(l->_superlayer, t);
}

- (CFTimeInterval)convertTime:(CFTimeInterval)t fromLayer:(CALayer *)l
{
    return to_local([self modelLayer], from_local([l modelLayer], t));
}

- (CFTimeInterval)convertTime:(CFTimeInterval)t toLayer:(CALayer *)l
{
    return to_local([l modelLayer], from_local([self modelLayer], t));
}

/* ---- space ---- */

static CGAffineTransform to_root(CALayer *l)
{
    CGAffineTransform m = CGAffineTransformIdentity;
    for (; l; l = l->_superlayer)
        m = CGAffineTransformConcat(m, QLayerToSuperlayer(l->_values, l));
    return m;
}

- (CGPoint)convertPoint:(CGPoint)p fromLayer:(CALayer *)l
{
    CGAffineTransform m = CGAffineTransformConcat(to_root([l modelLayer]), CGAffineTransformInvert(to_root([self modelLayer])));
    return CGPointApplyAffineTransform(p, m);
}

- (CGPoint)convertPoint:(CGPoint)p toLayer:(CALayer *)l
{
    CGAffineTransform m = CGAffineTransformConcat(to_root([self modelLayer]), CGAffineTransformInvert(to_root([l modelLayer])));
    return CGPointApplyAffineTransform(p, m);
}

- (CGRect)convertRect:(CGRect)r fromLayer:(CALayer *)l
{
    CGAffineTransform m = CGAffineTransformConcat(to_root([l modelLayer]), CGAffineTransformInvert(to_root([self modelLayer])));
    return CGRectApplyAffineTransform(r, m);
}

- (CGRect)convertRect:(CGRect)r toLayer:(CALayer *)l
{
    CGAffineTransform m = CGAffineTransformConcat(to_root([self modelLayer]), CGAffineTransformInvert(to_root([l modelLayer])));
    return CGRectApplyAffineTransform(r, m);
}

- (BOOL)containsPoint:(CGPoint)p { return CGRectContainsPoint(QRect(_values, @"bounds"), p); }

- (CALayer *)hitTest:(CGPoint)p
{
    if (QBool(_values, @"hidden") || QNum(_values, @"opacity") <= 0)
        return nil;
    CGAffineTransform up = QLayerToSuperlayer(_values, self);
    CGPoint q = CGPointApplyAffineTransform(p, CGAffineTransformInvert(up));
    BOOL inside = [self containsPoint:q];
    if (QBool(_values, @"masksToBounds") && !inside)
        return nil;
    for (CALayer *s in [_sublayers reverseObjectEnumerator]) {
        CALayer *hit = [s hitTest:q];
        if (hit)
            return hit;
    }
    return inside ? self : nil;
}

/* ---- drawing ---- */

- (BOOL)needsDisplay { return _needsDisplay; }

- (void)setNeedsDisplay
{
    if (_presentation)
        return;
    _needsDisplay = YES;
    [self _ferryChanged];
}

- (void)setNeedsDisplayInRect:(CGRect)r { [self setNeedsDisplay]; }

- (void)displayIfNeeded
{
    if (_needsDisplay)
        [self display];
}

/* whether display would draw anything: a delegate that draws, or a
 * drawInContext: of a subclass's own */
- (BOOL)_ferryDraws
{
    if ([_delegate respondsToSelector:@selector(drawLayer:inContext:)])
        return YES;
    return [self methodForSelector:@selector(drawInContext:)] != [CALayer instanceMethodForSelector:@selector(drawInContext:)];
}

- (void)display
{
    _needsDisplay = NO;
    if ([_delegate respondsToSelector:@selector(layerWillDraw:)])
        [_delegate layerWillDraw:self];
    if ([_delegate respondsToSelector:@selector(displayLayer:)]) {
        [_delegate displayLayer:self];
        return;
    }
    if (![self _ferryDraws])
        return;
    CGRect b = QRect(_values, @"bounds");
    double scale = QNum(_values, @"contentsScale");
    if (scale <= 0)
        scale = 1;
    size_t w = (size_t)ceil(b.size.width * scale), h = (size_t)ceil(b.size.height * scale);
    id image = nil;
    if (w && h && w < 32768 && h < 32768) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(cs);
        if (ctx) {
            CGContextScaleCTM(ctx, scale, scale);
            if ([self contentsAreFlipped]) {
                CGContextTranslateCTM(ctx, 0, b.size.height);
                CGContextScaleCTM(ctx, 1, -1);
            }
            CGContextTranslateCTM(ctx, -b.origin.x, -b.origin.y);
            [self drawInContext:ctx];
            CGImageRef img = CGBitmapContextCreateImage(ctx);
            image = [(id)img autorelease];
            CGContextRelease(ctx);
        }
    }
    /* the new contents are shown at once, not faded in */
    if (image)
        _values[@"contents"] = image;
    else
        [_values removeObjectForKey:@"contents"];
    [self _ferryChanged];
}

- (void)drawInContext:(CGContextRef)ctx
{
    if ([_delegate respondsToSelector:@selector(drawLayer:inContext:)])
        [_delegate drawLayer:self inContext:ctx];
}

- (void)renderInContext:(CGContextRef)ctx { FerryCALayerRender(self, ctx, NO, NO, nil); }

- (void)_ferryMarkRendered { _rendered = YES; }

- (void)_ferryDrawContentWithValues:(NSDictionary *)v inContext:(CGContextRef)ctx flipped:(BOOL)flipped {}

/* ---- layout ---- */

- (CGSize)preferredFrameSize
{
    id lm = [self layoutManager];
    if ([lm respondsToSelector:@selector(preferredSizeOfLayer:)])
        return [lm preferredSizeOfLayer:self];
    return QRect(_values, @"bounds").size;
}

- (BOOL)needsLayout { return _needsLayout; }

- (void)setNeedsLayout
{
    if (_presentation)
        return;
    _needsLayout = YES;
    id lm = [self layoutManager];
    if ([lm respondsToSelector:@selector(invalidateLayoutOfLayer:)])
        [lm invalidateLayoutOfLayer:self];
    [self _ferryChanged];
}

- (void)layoutIfNeeded
{
    if (_needsLayout) {
        _needsLayout = NO;
        [self layoutSublayers];
    }
    for (CALayer *s in [[_sublayers copy] autorelease])
        [s layoutIfNeeded];
}

- (void)layoutSublayers
{
    if ([_delegate respondsToSelector:@selector(layoutSublayersOfLayer:)]) {
        [_delegate layoutSublayersOfLayer:self];
        return;
    }
    id lm = [self layoutManager];
    if ([lm respondsToSelector:@selector(layoutSublayersOfLayer:)])
        [lm layoutSublayersOfLayer:self];
}

- (void)resizeSublayersWithOldSize:(CGSize)size
{
    for (CALayer *s in [[_sublayers copy] autorelease])
        [s resizeWithOldSuperlayerSize:size];
}

/* Shares out the change in the superlayer's size among the flexible parts
 * (the two margins and the size, on each axis), as the mask says. */
static void resize_axis(double *origin, double *length, double delta, BOOL minFlex, BOOL sizeFlex, BOOL maxFlex)
{
    int parts = minFlex + sizeFlex + maxFlex;
    if (!parts)
        return;
    double share = delta / parts;
    if (minFlex)
        *origin += share;
    if (sizeFlex)
        *length = fmax(0, *length + share);
}

- (void)resizeWithOldSuperlayerSize:(CGSize)size
{
    unsigned mask = [_values[@"autoresizingMask"] unsignedIntValue];
    if (!mask || !_superlayer)
        return;
    CGSize now = QRect(_superlayer->_values, @"bounds").size;
    CGRect f = [self frame];
    resize_axis(&f.origin.x, &f.size.width, now.width - size.width, mask & kCALayerMinXMargin,
                mask & kCALayerWidthSizable, mask & kCALayerMaxXMargin);
    resize_axis(&f.origin.y, &f.size.height, now.height - size.height, mask & kCALayerMinYMargin,
                mask & kCALayerHeightSizable, mask & kCALayerMaxYMargin);
    [self setFrame:f];
}

/* ---- actions ---- */

+ (id<CAAction>)defaultActionForKey:(NSString *)event { return nil; }

static id style_action(NSDictionary *style, NSString *event)
{
    for (int depth = 0; [style isKindOfClass:[NSDictionary class]] && depth < 32; depth++) {
        id a = style[@"actions"][event];
        if (a)
            return a;
        style = style[@"style"];
    }
    return nil;
}

- (id<CAAction>)actionForKey:(NSString *)event
{
    id a = nil;
    if ([_delegate respondsToSelector:@selector(actionForLayer:forKey:)]) {
        a = [_delegate actionForLayer:self forKey:event];
        if (a)
            return a == [NSNull null] ? nil : a;
    }
    a = [self actions][event];
    if (!a)
        a = style_action([self style], event);
    if (!a)
        a = [[self class] defaultActionForKey:event];
    if (a)
        return a == [NSNull null] ? nil : a;
    if (![[[self class] _ferryAnimatableKeys] containsObject:event])
        return nil;
    /* the implicit animation, from what's shown now */
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:event];
    id from = [self _ferryPresentationValues][event];
    if (!from && QIsColor(_pendingValue)) {
        CGColorRef clear = CGColorCreateCopyWithAlpha((CGColorRef)_pendingValue, 0);
        from = [(id)clear autorelease];
    }
    [anim setFromValue:from];
    [anim setDuration:[CATransaction animationDuration]];
    [anim setTimingFunction:[CATransaction animationTimingFunction]
                                ?: [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
    return anim;
}

/* ---- animations ---- */

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key
{
    if (!anim || _presentation)
        return;
    CAAnimation *a = [anim copy];
    if ([a beginTime] == 0)
        [a setBeginTime:[self convertTime:QNow() fromLayer:nil]];
    if (key)
        [self removeAnimationForKey:key];
    QRunning *r = [[QRunning alloc] init];
    r->animation = a;
    r->key = [key copy];
    r->layer = self;
    NSArray *open = QOpenTransactions();
    for (QTransaction *t in open)
        t->pending++;
    r->transactions = [open copy];
    if (!_animations)
        _animations = [[NSMutableArray alloc] init];
    [_animations addObject:r];
    QAnimatorAdd(r);
    [r release];
    [self _ferryChanged];
}

- (void)removeAnimationForKey:(NSString *)key
{
    for (QRunning *r in [[_animations copy] autorelease])
        if (r->key && [r->key isEqualToString:key]) {
            [[r retain] autorelease];
            [_animations removeObjectIdenticalTo:r];
            r->layer = nil;
            QAnimatorRemove(r, NO);
            [self _ferryChanged];
        }
}

- (void)removeAllAnimations
{
    NSArray *all = [[_animations copy] autorelease];
    [_animations removeAllObjects];
    for (QRunning *r in all) {
        r->layer = nil;
        QAnimatorRemove(r, NO);
    }
    if ([all count])
        [self _ferryChanged];
}

- (NSArray *)animationKeys
{
    NSMutableArray *keys = [NSMutableArray array];
    for (QRunning *r in _animations)
        if (r->key)
            [keys addObject:r->key];
    return [keys count] ? keys : nil;
}

- (CAAnimation *)animationForKey:(NSString *)key
{
    for (QRunning *r in _animations)
        if (r->key && [r->key isEqualToString:key])
            return r->animation;
    return nil;
}

- (NSArray *)_ferryRunning { return _animations; }

- (void)_ferryAnimationEnded:(QRunning *)r
{
    [[r retain] autorelease];
    [_animations removeObjectIdenticalTo:r];
    r->layer = nil;
    [self _ferryChanged];
}
@end

void FerryCALayerSetHost(CALayer *layer, id host) { [layer _ferrySetHost:host]; }

BOOL FerryCALayerTreeIsAnimating(CALayer *layer)
{
    if ([[layer _ferryRunning] count])
        return YES;
    for (CALayer *s in [layer _ferrySublayers])
        if (FerryCALayerTreeIsAnimating(s))
            return YES;
    return NO;
}
