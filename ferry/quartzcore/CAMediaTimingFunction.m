/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAMediaTimingFunction, a cubic Bézier curve from
 * (0, 0) to (1, 1) whose two inner control points Apple's documentation
 * gives for each named function. The curve maps the fraction of an
 * animation's time gone to the fraction of its change made. */
#import "QInternal.h"

CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear = @"linear";
CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseIn = @"easeIn";
CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseOut = @"easeOut";
CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseInEaseOut = @"easeInEaseOut";
CAMediaTimingFunctionName const kCAMediaTimingFunctionDefault = @"default";

@implementation CAMediaTimingFunction {
    float _p[4];
}

+ (BOOL)supportsSecureCoding { return YES; }

+ (instancetype)functionWithName:(CAMediaTimingFunctionName)name
{
    static const struct {
        NSString *const *name;
        float p[4];
    } named[] = {
        {&kCAMediaTimingFunctionLinear, {0, 0, 1, 1}},
        {&kCAMediaTimingFunctionEaseIn, {0.42f, 0, 1, 1}},
        {&kCAMediaTimingFunctionEaseOut, {0, 0, 0.58f, 1}},
        {&kCAMediaTimingFunctionEaseInEaseOut, {0.42f, 0, 0.58f, 1}},
        {&kCAMediaTimingFunctionDefault, {0.25f, 0.1f, 0.25f, 1}},
    };
    for (size_t i = 0; i < sizeof named / sizeof named[0]; i++)
        if ([name isEqualToString:*named[i].name])
            return [self functionWithControlPoints:named[i].p[0]:named[i].p[1]:named[i].p[2]:named[i].p[3]];
    [NSException raise:NSInvalidArgumentException format:@"unknown timing function name %@", name];
    return nil;
}

+ (instancetype)functionWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y
{
    return [[[self alloc] initWithControlPoints:c1x:c1y:c2x:c2y] autorelease];
}

- (instancetype)initWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y
{
    if ((self = [super init])) {
        _p[0] = fmax(0, fmin(1, c1x)), _p[1] = c1y;
        _p[2] = fmax(0, fmin(1, c2x)), _p[3] = c2y;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithControlPoints:[coder decodeFloatForKey:@"c1x"]:[coder decodeFloatForKey:@"c1y"]
                                      :[coder decodeFloatForKey:@"c2x"]:[coder decodeFloatForKey:@"c2y"]];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeFloat:_p[0] forKey:@"c1x"];
    [coder encodeFloat:_p[1] forKey:@"c1y"];
    [coder encodeFloat:_p[2] forKey:@"c2x"];
    [coder encodeFloat:_p[3] forKey:@"c2y"];
}

/* Points 0 and 3 are the curve's ends, 1 and 2 the control points. */
- (void)getControlPointAtIndex:(size_t)idx values:(float[2])ptr
{
    switch (idx) {
    case 0: ptr[0] = ptr[1] = 0; break;
    case 1: ptr[0] = _p[0], ptr[1] = _p[1]; break;
    case 2: ptr[0] = _p[2], ptr[1] = _p[3]; break;
    default: ptr[0] = ptr[1] = 1; break;
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CAMediaTimingFunction: %p> (%g, %g) (%g, %g)", self, _p[0], _p[1], _p[2],
                                      _p[3]];
}

static double bez(double a, double b, double t)
{
    /* one coordinate of the curve with ends 0 and 1 and controls a and b */
    double u = 1 - t;
    return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
}
static double bez_slope(double a, double b, double t)
{
    double u = 1 - t;
    return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b);
}

/* y for x: x(t) = x is found by Newton's method, falling back to halving
 * where the slope is flat. */
- (double)_solve:(double)x
{
    if (x <= 0)
        return 0;
    if (x >= 1)
        return 1;
    double t = x;
    for (int i = 0; i < 8; i++) {
        double err = bez(_p[0], _p[2], t) - x;
        if (fabs(err) < 1e-7)
            return bez(_p[1], _p[3], t);
        double s = bez_slope(_p[0], _p[2], t);
        if (fabs(s) < 1e-6)
            break;
        t -= err / s;
    }
    double lo = 0, hi = 1;
    t = x;
    for (int i = 0; i < 60; i++) {
        double v = bez(_p[0], _p[2], t);
        if (fabs(v - x) < 1e-9)
            break;
        if (v < x)
            lo = t;
        else
            hi = t;
        t = (lo + hi) / 2;
    }
    return bez(_p[1], _p[3], t);
}
@end

double QTimingSolve(CAMediaTimingFunction *f, double x)
{
    return f ? [f _solve:x] : x;
}
