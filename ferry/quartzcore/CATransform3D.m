/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: 3D transforms, the media clock, and transforms
 * kept in NSValues. A CATransform3D is a 4x4 matrix used with row vectors,
 * as CGAffineTransform is: m41, m42 and m43 are the translation, and
 * CATransform3DConcat(a, b) applies a first, then b. Written from Apple's
 * public documentation of the functions. */
#import "QInternal.h"
#include <time.h>

const CATransform3D CATransform3DIdentity = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};

void QWarnOnce(const char *what)
{
    static NSMutableSet *said;
    if (!said)
        said = [[NSMutableSet alloc] init];
    NSString *s = [NSString stringWithUTF8String:what];
    if ([said containsObject:s])
        return;
    [said addObject:s];
    fflush(stdout);
    fprintf(stderr, "Ferry: Core Animation doesn't support %s yet\n", what);
}

/* ---- the clock ------------------------------------------------------------------------ */

static BOOL manual_clock;
static double manual_now;

double QNow(void)
{
    if (manual_clock)
        return manual_now;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

CFTimeInterval CACurrentMediaTime(void) { return QNow(); }
BOOL QClockIsManual(void) { return manual_clock; }

void FerryCASetManualClock(CFTimeInterval now)
{
    manual_clock = YES;
    manual_now = now;
}

void FerryCAAdvanceTime(CFTimeInterval seconds)
{
    if (!manual_clock)
        FerryCASetManualClock(QNow());
    QCommitImplicitTransaction();
    manual_now += seconds;
    QAnimatorTick();
}

/* ---- matrices ----------------------------------------------------------------------------- */

static double *M(CATransform3D *t) { return &t->m11; }
static const double *CM(const CATransform3D *t) { return &t->m11; }

bool CATransform3DIsIdentity(CATransform3D t) { return CATransform3DEqualToTransform(t, CATransform3DIdentity); }

bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b)
{
    for (int i = 0; i < 16; i++)
        if (CM(&a)[i] != CM(&b)[i])
            return false;
    return true;
}

CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b)
{
    CATransform3D r;
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            double s = 0;
            for (int k = 0; k < 4; k++)
                s += CM(&a)[i * 4 + k] * CM(&b)[k * 4 + j];
            M(&r)[i * 4 + j] = s;
        }
    return r;
}

CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz)
{
    CATransform3D t = CATransform3DIdentity;
    t.m41 = tx, t.m42 = ty, t.m43 = tz;
    return t;
}

CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz)
{
    CATransform3D t = CATransform3DIdentity;
    t.m11 = sx, t.m22 = sy, t.m33 = sz;
    return t;
}

/* A rotation by angle radians about the axis (x, y, z), counterclockwise
 * when the axis points at the viewer; an axis of no length is no rotation. */
CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z)
{
    double len = sqrt(x * x + y * y + z * z);
    if (len == 0)
        return CATransform3DIdentity;
    x /= len, y /= len, z /= len;
    double c = cos(angle), s = sin(angle), k = 1 - c;
    CATransform3D t = CATransform3DIdentity;
    /* the usual column-vector rotation matrix, transposed for row vectors */
    t.m11 = c + x * x * k, t.m21 = x * y * k - z * s, t.m31 = x * z * k + y * s;
    t.m12 = y * x * k + z * s, t.m22 = c + y * y * k, t.m32 = y * z * k - x * s;
    t.m13 = z * x * k - y * s, t.m23 = z * y * k + x * s, t.m33 = c + z * z * k;
    return t;
}

CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz)
{
    return CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t);
}

CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz)
{
    return CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t);
}

CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z)
{
    return CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t);
}

/* By cofactors; a matrix that can't be inverted comes back unchanged. */
CATransform3D CATransform3DInvert(CATransform3D t)
{
    const double *m = CM(&t);
    double inv[16];
    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] +
             m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] -
             m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] +
             m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] -
              m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] -
             m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] +
             m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] -
             m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] +
              m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] +
             m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] -
             m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] +
              m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] -
              m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] -
             m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] +
             m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] -
              m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] +
              m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
    double det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    if (det == 0)
        return t;
    CATransform3D r;
    for (int i = 0; i < 16; i++)
        M(&r)[i] = inv[i] / det;
    return r;
}

CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform m)
{
    CATransform3D t = CATransform3DIdentity;
    t.m11 = m.a, t.m12 = m.b, t.m21 = m.c, t.m22 = m.d, t.m41 = m.tx, t.m42 = m.ty;
    return t;
}

bool CATransform3DIsAffine(CATransform3D t)
{
    return t.m13 == 0 && t.m14 == 0 && t.m23 == 0 && t.m24 == 0 && t.m31 == 0 && t.m32 == 0 && t.m33 == 1 &&
           t.m34 == 0 && t.m43 == 0 && t.m44 == 1;
}

CGAffineTransform CATransform3DGetAffineTransform(CATransform3D t)
{
    return CGAffineTransformMake(t.m11, t.m12, t.m21, t.m22, t.m41, t.m42);
}

/* What Ferry draws: points of the plane z = 0, seen straight on, with no
 * perspective. A 2D transform is drawn exactly. */
CGAffineTransform QAffine2D(CATransform3D t)
{
    if (t.m14 || t.m24 || (t.m44 != 1 && t.m44 != 0))
        QWarnOnce("perspective in layer transforms (drawn flat)");
    double w = t.m44 ? t.m44 : 1;
    return CGAffineTransformMake(t.m11 / w, t.m12 / w, t.m21 / w, t.m22 / w, t.m41 / w, t.m42 / w);
}

/* ---- in NSValues --------------------------------------------------------------------------- */

@implementation QTransformValue
- (const char *)objCType { return @encode(CATransform3D); }
- (CATransform3D)CATransform3DValue { return t; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)other
{
    return other == self ||
           ([other isKindOfClass:[QTransformValue class]] &&
            CATransform3DEqualToTransform(t, ((QTransformValue *)other)->t));
}
- (NSUInteger)hash { return (NSUInteger)(t.m11 * 31 + t.m41 * 17 + t.m42); }
- (NSString *)description
{
    return [NSString stringWithFormat:@"CATransform3D: {%g %g %g %g; %g %g %g %g; %g %g %g %g; %g %g %g %g}", t.m11,
                                      t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24, t.m31, t.m32, t.m33, t.m34,
                                      t.m41, t.m42, t.m43, t.m44];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    for (int i = 0; i < 16; i++)
        [coder encodeDouble:CM(&t)[i] forKey:[NSString stringWithFormat:@"m%d%d", i / 4 + 1, i % 4 + 1]];
}
@end

@implementation NSValue (CATransform3DAdditions)
+ (NSValue *)valueWithCATransform3D:(CATransform3D)t
{
    QTransformValue *v = [[QTransformValue alloc] init];
    v->t = t;
    return [v autorelease];
}
- (CATransform3D)CATransform3DValue { return CATransform3DIdentity; }
@end
