/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAKeyframeAnimation, through a list of values or
 * along a path. As Apple's documentation describes: key times (fractions
 * of the duration, one for each value; one more than the values for the
 * discrete mode) place the values, and by default they are evenly spaced;
 * one timing function per segment eases it; the paced modes space the
 * values by distance instead; the cubic modes pass through the values on
 * a smooth (Catmull-Rom) curve. Each element of a path after its first
 * point is one segment. */
#import "QInternal.h"

CAAnimationCalculationMode const kCAAnimationLinear = @"linear";
CAAnimationCalculationMode const kCAAnimationDiscrete = @"discrete";
CAAnimationCalculationMode const kCAAnimationPaced = @"paced";
CAAnimationCalculationMode const kCAAnimationCubic = @"cubic";
CAAnimationCalculationMode const kCAAnimationCubicPaced = @"cubicPaced";
CAAnimationRotationMode const kCAAnimationRotateAuto = @"auto";
CAAnimationRotationMode const kCAAnimationRotateAutoReverse = @"autoReverse";

@interface CAPropertyAnimation (FerryKinds)
- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model;
- (id)_ferryCycleChangeBeneath:(id)beneath model:(id)model;
@end

/* One piece of a path: a line, or a quadratic or cubic curve. */
struct seg {
    int n;              /* control points after the start: 1, 2 or 3 */
    CGPoint p[4];       /* the start, then those */
    double length;
};
struct segs {
    struct seg *s;
    size_t count, cap;
    CGPoint start, current;
};

static void seg_add(struct segs *z, int n, const CGPoint *pts)
{
    if (z->count == z->cap) {
        z->cap = z->cap ? z->cap * 2 : 16;
        z->s = realloc(z->s, z->cap * sizeof *z->s);
    }
    struct seg *s = &z->s[z->count++];
    s->n = n;
    s->p[0] = z->current;
    for (int i = 0; i < n; i++)
        s->p[i + 1] = pts[i];
    z->current = pts[n - 1];
}

static void seg_collect(void *info, const CGPathElement *e)
{
    struct segs *z = info;
    switch (e->type) {
    case kCGPathElementMoveToPoint: z->start = z->current = e->points[0]; break;
    case kCGPathElementAddLineToPoint: seg_add(z, 1, e->points); break;
    case kCGPathElementAddQuadCurveToPoint: seg_add(z, 2, e->points); break;
    case kCGPathElementAddCurveToPoint: seg_add(z, 3, e->points); break;
    case kCGPathElementCloseSubpath:
        if (!CGPointEqualToPoint(z->current, z->start))
            seg_add(z, 1, &z->start);
        z->current = z->start;
        break;
    }
}

static CGPoint seg_point(const struct seg *s, double t)
{
    double u = 1 - t;
    const CGPoint *p = s->p;
    switch (s->n) {
    case 1: return CGPointMake(p[0].x + (p[1].x - p[0].x) * t, p[0].y + (p[1].y - p[0].y) * t);
    case 2:
        return CGPointMake(u * u * p[0].x + 2 * u * t * p[1].x + t * t * p[2].x,
                           u * u * p[0].y + 2 * u * t * p[1].y + t * t * p[2].y);
    default:
        return CGPointMake(u * u * u * p[0].x + 3 * u * u * t * p[1].x + 3 * u * t * t * p[2].x + t * t * t * p[3].x,
                           u * u * u * p[0].y + 3 * u * u * t * p[1].y + 3 * u * t * t * p[2].y + t * t * t * p[3].y);
    }
}

static double seg_length(const struct seg *s)
{
    if (s->n == 1)
        return hypot(s->p[1].x - s->p[0].x, s->p[1].y - s->p[0].y);
    double len = 0;
    CGPoint last = s->p[0];
    for (int i = 1; i <= 32; i++) {
        CGPoint q = seg_point(s, i / 32.0);
        len += hypot(q.x - last.x, q.y - last.y);
        last = q;
    }
    return len;
}

@implementation CAKeyframeAnimation {
    NSArray *_values, *_keyTimes, *_timingFunctions, *_tension, *_continuity, *_bias;
    CGPathRef _path;
    NSString *_calculationMode, *_rotationMode;
}

- (instancetype)init
{
    if ((self = [super init]))
        _calculationMode = [kCAAnimationLinear copy];
    return self;
}

- (void)dealloc
{
    [_values release];
    [_keyTimes release];
    [_timingFunctions release];
    [_tension release];
    [_continuity release];
    [_bias release];
    CGPathRelease(_path);
    [_calculationMode release];
    [_rotationMode release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CAKeyframeAnimation *c = [super copyWithZone:zone];
    c->_values = [_values copy];
    c->_keyTimes = [_keyTimes copy];
    c->_timingFunctions = [_timingFunctions copy];
    c->_tension = [_tension copy];
    c->_continuity = [_continuity copy];
    c->_bias = [_bias copy];
    c->_path = CGPathRetain(_path);
    [c->_calculationMode release];
    c->_calculationMode = [_calculationMode copy];
    c->_rotationMode = [_rotationMode copy];
    return c;
}

#define COPY_PROP(getter, setter, ivar)                                                                             \
    -(id)getter { return ivar; }                                                                                \
    -(void)setter(id)v                                                                                          \
    {                                                                                                           \
        id c = [v copy];                                                                                        \
        [ivar release];                                                                                         \
        ivar = c;                                                                                               \
    }
COPY_PROP(values, setValues:, _values)
COPY_PROP(keyTimes, setKeyTimes:, _keyTimes)
COPY_PROP(timingFunctions, setTimingFunctions:, _timingFunctions)
COPY_PROP(tensionValues, setTensionValues:, _tension)
COPY_PROP(continuityValues, setContinuityValues:, _continuity)
COPY_PROP(biasValues, setBiasValues:, _bias)
COPY_PROP(calculationMode, setCalculationMode:, _calculationMode)
COPY_PROP(rotationMode, setRotationMode:, _rotationMode)

- (CGPathRef)path { return _path; }
- (void)setPath:(CGPathRef)path
{
    CGPathRef c = path ? CGPathCreateCopy(path) : NULL;
    CGPathRelease(_path);
    _path = c;
}

/* The fraction of the duration at which each of n keyframes falls. */
static double *key_times(CAKeyframeAnimation *a, size_t n, const double *distances, BOOL paced, BOOL discrete)
{
    double *kt = calloc(n + 1, sizeof *kt);
    size_t want = discrete ? n + 1 : n;
    if (paced && distances) {
        double total = 0;
        for (size_t i = 0; i + 1 < n; i++)
            total += distances[i];
        double sum = 0;
        for (size_t i = 0; i < n; i++) {
            kt[i] = total > 0 ? sum / total : (n > 1 ? (double)i / (n - 1) : 0);
            if (i + 1 < n)
                sum += distances[i];
        }
        return kt;
    }
    if ([a->_keyTimes count] == want) {
        for (size_t i = 0; i < want; i++)
            kt[i] = [a->_keyTimes[i] doubleValue];
        return kt;
    }
    size_t steps = discrete ? n : n - 1;
    for (size_t i = 0; i < want; i++)
        kt[i] = steps ? (double)i / steps : 0;
    return kt;
}

/* the segment p falls in, and where within it */
static size_t find_segment(const double *kt, size_t n, double p, double *local)
{
    size_t i = 0;
    while (i + 2 < n && p >= kt[i + 1])
        i++;
    double span = kt[i + 1] - kt[i];
    *local = span > 0 ? fmax(0, fmin(1, (p - kt[i]) / span)) : 1;
    return i;
}

- (id)_ferryPathValueAt:(double)p
{
    struct segs z = {0};
    CGPathApply(_path, &z, seg_collect);
    if (!z.count) {
        free(z.s);
        return [NSValue valueWithPoint:z.current];
    }
    BOOL paced = [_calculationMode isEqualToString:kCAAnimationPaced] ||
                 [_calculationMode isEqualToString:kCAAnimationCubicPaced];
    size_t n = z.count + 1;
    double *d = calloc(n, sizeof *d);
    for (size_t i = 0; i < z.count; i++)
        d[i] = z.s[i].length = seg_length(&z.s[i]);
    double *kt = key_times(self, n, d, paced, NO);
    double local;
    size_t i = find_segment(kt, n, p, &local);
    if (!paced && i < [_timingFunctions count])
        local = QTimingSolve(_timingFunctions[i], local);
    CGPoint q = seg_point(&z.s[i], local);
    if (_rotationMode)
        QWarnOnce("keyframe animations' rotation modes");
    free(kt), free(d), free(z.s);
    return [NSValue valueWithPoint:q];
}

/* Catmull-Rom between b and c, with a before and d after. */
static id cubic(id a, id b, id c, id d, double t)
{
    struct qval va, vb, vc, vd, out;
    QKind k = QValueRead(b, &vb);
    if (k == QV_OTHER || k == QV_NONE || k == QV_TRANSFORM || QValueRead(c, &vc) != k)
        return QBlend(b, c, t);
    if (QValueRead(a, &va) != k)
        va = vb;
    if (QValueRead(d, &vd) != k)
        vd = vc;
    out = vb;
    double t2 = t * t, t3 = t2 * t;
    for (int i = 0; i < 4; i++)
        out.d[i] = 0.5 * (2 * vb.d[i] + (-va.d[i] + vc.d[i]) * t + (2 * va.d[i] - 5 * vb.d[i] + 4 * vc.d[i] - vd.d[i]) * t2 +
                          (-va.d[i] + 3 * vb.d[i] - 3 * vc.d[i] + vd.d[i]) * t3);
    return QValueMake(&out);
}

- (id)_ferryValueAt:(double)p time:(double)time beneath:(id)beneath model:(id)model
{
    if (_path)
        return [self _ferryPathValueAt:p];
    size_t n = [_values count];
    if (!n)
        return nil;
    if (n == 1)
        return _values[0];
    BOOL discrete = [_calculationMode isEqualToString:kCAAnimationDiscrete];
    BOOL paced = [_calculationMode isEqualToString:kCAAnimationPaced] ||
                 [_calculationMode isEqualToString:kCAAnimationCubicPaced];
    BOOL smooth = [_calculationMode isEqualToString:kCAAnimationCubic] ||
                  [_calculationMode isEqualToString:kCAAnimationCubicPaced];
    double *d = NULL;
    if (paced) {
        d = calloc(n, sizeof *d);
        for (size_t i = 0; i + 1 < n; i++) {
            struct qval a, b;
            QValueRead(_values[i], &a);
            QValueRead(_values[i + 1], &b);
            d[i] = a.kind == b.kind ? QValueDistance(&a, &b) : 1;
        }
    }
    double *kt = key_times(self, n, d, paced, discrete);
    id result;
    if (discrete) {
        size_t i = 0;
        while (i + 1 < n && p >= kt[i + 1])
            i++;
        result = _values[i];
    } else {
        double local;
        size_t i = find_segment(kt, n, p, &local);
        if (!paced && i < [_timingFunctions count])
            local = QTimingSolve(_timingFunctions[i], local);
        if (smooth)
            result = cubic(_values[i ? i - 1 : 0], _values[i], _values[i + 1], _values[i + 2 < n ? i + 2 : n - 1], local);
        else
            result = QBlend(_values[i], _values[i + 1], local);
    }
    free(kt);
    free(d);
    return result;
}

- (id)_ferryCycleChangeBeneath:(id)beneath model:(id)model
{
    if (_path || [_values count] < 2)
        return nil;
    return QSubtract([_values lastObject], _values[0]);
}
@end
