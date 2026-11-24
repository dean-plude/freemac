/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAAnimation, the timing every animation shares
 * (the CAMediaTiming protocol: begin time, speed, time offset, duration,
 * repeats, autoreversing and fill modes, as Apple's documentation describes
 * them), and NSNull as the action that does nothing. An animation is a
 * key-value coding container: values for keys it doesn't have are kept
 * with it, and copied with it. Its delegate is retained, as on a Mac. */
#import "QInternal.h"

CAMediaTimingFillMode const kCAFillModeForwards = @"forwards";
CAMediaTimingFillMode const kCAFillModeBackwards = @"backwards";
CAMediaTimingFillMode const kCAFillModeBoth = @"both";
CAMediaTimingFillMode const kCAFillModeRemoved = @"removed";

/* ---- time ---------------------------------------------------------------------------- */

static double active_duration(id<CAMediaTiming> m, double defaultDuration)
{
    double dur = [m duration] > 0 ? [m duration] : defaultDuration;
    double cycle = dur * ([m autoreverses] ? 2 : 1);
    if ([m repeatDuration] > 0)
        return [m repeatDuration];
    float n = [m repeatCount];
    if (isinf(n))
        return INFINITY;
    return n > 0 ? cycle * n : cycle;
}

void QTimingEvaluate(id<CAMediaTiming> m, double parentTime, double defaultDuration, struct qtime *out)
{
    double local = (parentTime - [m beginTime]) * [m speed] + [m timeOffset];
    double dur = [m duration] > 0 ? [m duration] : defaultDuration;
    double cycle = dur * ([m autoreverses] ? 2 : 1);
    double active = active_duration(m, defaultDuration);
    NSString *fill = [m fillMode];
    BOOL backwards = [fill isEqualToString:kCAFillModeBackwards] || [fill isEqualToString:kCAFillModeBoth];
    BOOL forwards = [fill isEqualToString:kCAFillModeForwards] || [fill isEqualToString:kCAFillModeBoth];
    double t;
    if (local < 0) {
        out->phase = Q_BEFORE, out->applies = backwards, t = 0;
    } else if (local >= active) {
        out->phase = Q_AFTER, out->applies = forwards, t = active;
    } else {
        out->phase = Q_ACTIVE, out->applies = YES, t = local;
    }
    if (cycle <= 0 || isinf(t)) {
        out->progress = 1, out->iteration = 0;
        return;
    }
    double iteration = floor(t / cycle);
    double f = t - iteration * cycle;
    if (out->phase == Q_AFTER && f < 1e-12 && t > 0) {
        /* ended at a cycle's end: show that end, not the next cycle's start */
        f = cycle;
        iteration -= 1;
    }
    double p = f / dur;
    if ([m autoreverses] && f > dur)
        p = (cycle - f) / dur;
    out->progress = fmax(0, fmin(1, p));
    out->iteration = fmax(0, iteration);
}

double QAnimationActiveDuration(CAAnimation *a) { return active_duration(a, [a _ferryDefaultDuration]); }

/* ---- NSNull: no action ------------------------------------------------------------------- */

@implementation NSNull (CAActionAdditions)
- (void)runActionForKey:(NSString *)event object:(id)anObject arguments:(NSDictionary *)dict {}
@end

/* ---- value functions --------------------------------------------------------------------- */

CAValueFunctionName const kCAValueFunctionRotateX = @"rotateX";
CAValueFunctionName const kCAValueFunctionRotateY = @"rotateY";
CAValueFunctionName const kCAValueFunctionRotateZ = @"rotateZ";
CAValueFunctionName const kCAValueFunctionScale = @"scale";
CAValueFunctionName const kCAValueFunctionScaleX = @"scaleX";
CAValueFunctionName const kCAValueFunctionScaleY = @"scaleY";
CAValueFunctionName const kCAValueFunctionScaleZ = @"scaleZ";
CAValueFunctionName const kCAValueFunctionTranslate = @"translate";
CAValueFunctionName const kCAValueFunctionTranslateX = @"translateX";
CAValueFunctionName const kCAValueFunctionTranslateY = @"translateY";
CAValueFunctionName const kCAValueFunctionTranslateZ = @"translateZ";

@implementation CAValueFunction {
    NSString *_name;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)functionWithName:(CAValueFunctionName)name
{
    CAValueFunction *f = [[self alloc] init];
    f->_name = [name copy];
    return [f autorelease];
}
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        _name = [[coder decodeObjectForKey:@"name"] copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_name forKey:@"name"]; }
@end

/* ---- CAAnimation --------------------------------------------------------------------- */

@implementation CAAnimation {
    CAMediaTimingFunction *_timingFunction;
    id _delegate;
    BOOL _removedOnCompletion, _autoreverses;
    CFTimeInterval _beginTime, _duration, _timeOffset, _repeatDuration;
    float _speed, _repeatCount;
    NSString *_fillMode;
    NSMutableDictionary *_extra;
}

+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)animation { return [[[self alloc] init] autorelease]; }
+ (id)defaultValueForKey:(NSString *)key { return nil; }
- (BOOL)shouldArchiveValueForKey:(NSString *)key { return YES; }

- (instancetype)init
{
    if ((self = [super init])) {
        _removedOnCompletion = YES;
        _speed = 1;
        _fillMode = [kCAFillModeRemoved copy];
    }
    return self;
}

- (void)dealloc
{
    [_timingFunction release];
    [_delegate release];
    [_fillMode release];
    [_extra release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CAAnimation *c = [[[self class] allocWithZone:zone] init];
    c->_timingFunction = [_timingFunction retain];
    c->_delegate = [_delegate retain];
    c->_removedOnCompletion = _removedOnCompletion;
    c->_autoreverses = _autoreverses;
    c->_beginTime = _beginTime, c->_duration = _duration, c->_timeOffset = _timeOffset;
    c->_repeatDuration = _repeatDuration, c->_speed = _speed, c->_repeatCount = _repeatCount;
    [c->_fillMode release];
    c->_fillMode = [_fillMode copy];
    c->_extra = [_extra mutableCopy];
    return c;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _duration = [coder decodeDoubleForKey:@"duration"];
        _beginTime = [coder decodeDoubleForKey:@"beginTime"];
        if ([coder containsValueForKey:@"speed"])
            _speed = [coder decodeFloatForKey:@"speed"];
        _repeatCount = [coder decodeFloatForKey:@"repeatCount"];
        _autoreverses = [coder decodeBoolForKey:@"autoreverses"];
        if ([coder containsValueForKey:@"removedOnCompletion"])
            _removedOnCompletion = [coder decodeBoolForKey:@"removedOnCompletion"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_duration forKey:@"duration"];
    [coder encodeDouble:_beginTime forKey:@"beginTime"];
    [coder encodeFloat:_speed forKey:@"speed"];
    [coder encodeFloat:_repeatCount forKey:@"repeatCount"];
    [coder encodeBool:_autoreverses forKey:@"autoreverses"];
    [coder encodeBool:_removedOnCompletion forKey:@"removedOnCompletion"];
}

- (CAMediaTimingFunction *)timingFunction { return _timingFunction; }
- (void)setTimingFunction:(CAMediaTimingFunction *)f
{
    [f retain];
    [_timingFunction release];
    _timingFunction = f;
}
- (id<CAAnimationDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<CAAnimationDelegate>)d
{
    [d retain];
    [_delegate release];
    _delegate = d;
}
- (BOOL)isRemovedOnCompletion { return _removedOnCompletion; }
- (void)setRemovedOnCompletion:(BOOL)flag { _removedOnCompletion = flag; }
- (CFTimeInterval)beginTime { return _beginTime; }
- (void)setBeginTime:(CFTimeInterval)t { _beginTime = t; }
- (CFTimeInterval)duration { return _duration; }
- (void)setDuration:(CFTimeInterval)d { _duration = d; }
- (float)speed { return _speed; }
- (void)setSpeed:(float)s { _speed = s; }
- (CFTimeInterval)timeOffset { return _timeOffset; }
- (void)setTimeOffset:(CFTimeInterval)t { _timeOffset = t; }
- (float)repeatCount { return _repeatCount; }
- (void)setRepeatCount:(float)n { _repeatCount = n; }
- (CFTimeInterval)repeatDuration { return _repeatDuration; }
- (void)setRepeatDuration:(CFTimeInterval)d { _repeatDuration = d; }
- (BOOL)autoreverses { return _autoreverses; }
- (void)setAutoreverses:(BOOL)flag { _autoreverses = flag; }
- (CAMediaTimingFillMode)fillMode { return _fillMode; }
- (void)setFillMode:(CAMediaTimingFillMode)mode
{
    [_fillMode release];
    _fillMode = [mode copy];
}

/* keys the class doesn't have */
- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
    if (!_extra)
        _extra = [[NSMutableDictionary alloc] init];
    if (value)
        _extra[key] = value;
    else
        [_extra removeObjectForKey:key];
}
- (id)valueForUndefinedKey:(NSString *)key { return _extra[key] ?: [[self class] defaultValueForKey:key]; }

/* As an action: added to the layer that asked, under the action's key. */
- (void)runActionForKey:(NSString *)event object:(id)anObject arguments:(NSDictionary *)dict
{
    if ([anObject isKindOfClass:[CALayer class]])
        [(CALayer *)anObject addAnimation:self forKey:event];
}

- (double)_ferryDefaultDuration { return 0.25; }
- (void)_ferryApplyAtTime:(double)parentTime to:(NSMutableDictionary *)values layer:(CALayer *)layer {}
@end
