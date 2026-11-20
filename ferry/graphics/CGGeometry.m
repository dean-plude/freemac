/* SPDX-License-Identifier: GPL-3.0-or-later
 * Points, sizes, rectangles and affine transforms. Rectangles may have a
 * negative width or height; the functions work on the standardized form,
 * as Apple documents. */
#import "GInternal.h"

const CGPoint CGPointZero = {0, 0};
const CGSize CGSizeZero = {0, 0};
const CGRect CGRectZero = {{0, 0}, {0, 0}};
const CGRect CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
const CGRect CGRectInfinite = {{-__DBL_MAX__ / 2, -__DBL_MAX__ / 2}, {__DBL_MAX__, __DBL_MAX__}};
const CGAffineTransform CGAffineTransformIdentity = {1, 0, 0, 1, 0, 0};

void GWarnOnce(const char *what)
{
    static const char *said[64];
    static int nsaid;
    for (int i = 0; i < nsaid; i++)
        if (!strcmp(said[i], what))
            return;
    if (nsaid < 64)
        said[nsaid++] = what;
    fflush(stdout);
    fprintf(stderr, "ferry: %s isn't supported yet; skipping it\n", what);
}

CGRect CGRectStandardize(CGRect r)
{
    if (CGRectIsNull(r))
        return r;
    if (r.size.width < 0) {
        r.origin.x += r.size.width;
        r.size.width = -r.size.width;
    }
    if (r.size.height < 0) {
        r.origin.y += r.size.height;
        r.size.height = -r.size.height;
    }
    return r;
}

CGFloat CGRectGetMinX(CGRect r) { return CGRectStandardize(r).origin.x; }
CGFloat CGRectGetMinY(CGRect r) { return CGRectStandardize(r).origin.y; }
CGFloat CGRectGetMaxX(CGRect r) { r = CGRectStandardize(r); return r.origin.x + r.size.width; }
CGFloat CGRectGetMaxY(CGRect r) { r = CGRectStandardize(r); return r.origin.y + r.size.height; }
CGFloat CGRectGetMidX(CGRect r) { r = CGRectStandardize(r); return r.origin.x + r.size.width / 2; }
CGFloat CGRectGetMidY(CGRect r) { r = CGRectStandardize(r); return r.origin.y + r.size.height / 2; }
CGFloat CGRectGetWidth(CGRect r) { return fabs(r.size.width); }
CGFloat CGRectGetHeight(CGRect r) { return fabs(r.size.height); }

bool CGPointEqualToPoint(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
bool CGSizeEqualToSize(CGSize a, CGSize b) { return a.width == b.width && a.height == b.height; }

bool CGRectIsNull(CGRect r) { return isinf(r.origin.x) && r.origin.x > 0 && isinf(r.origin.y) && r.origin.y > 0; }

bool CGRectIsInfinite(CGRect r)
{
    return r.origin.x == CGRectInfinite.origin.x && r.origin.y == CGRectInfinite.origin.y &&
           r.size.width == CGRectInfinite.size.width && r.size.height == CGRectInfinite.size.height;
}

bool CGRectIsEmpty(CGRect r) { return CGRectIsNull(r) || r.size.width == 0 || r.size.height == 0; }

bool CGRectEqualToRect(CGRect a, CGRect b)
{
    if (CGRectIsNull(a) || CGRectIsNull(b))
        return CGRectIsNull(a) && CGRectIsNull(b);
    a = CGRectStandardize(a);
    b = CGRectStandardize(b);
    return CGPointEqualToPoint(a.origin, b.origin) && CGSizeEqualToSize(a.size, b.size);
}

CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy)
{
    if (CGRectIsNull(r))
        return r;
    r = CGRectStandardize(r);
    r.origin.x += dx;
    r.origin.y += dy;
    r.size.width -= 2 * dx;
    r.size.height -= 2 * dy;
    if (r.size.width < 0 || r.size.height < 0)
        return CGRectNull;
    return r;
}

CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy)
{
    if (CGRectIsNull(r))
        return r;
    r = CGRectStandardize(r);
    r.origin.x += dx;
    r.origin.y += dy;
    return r;
}

CGRect CGRectIntegral(CGRect r)
{
    if (CGRectIsNull(r) || CGRectIsInfinite(r))
        return r;
    r = CGRectStandardize(r);
    CGFloat x0 = floor(r.origin.x), y0 = floor(r.origin.y);
    CGFloat x1 = ceil(r.origin.x + r.size.width), y1 = ceil(r.origin.y + r.size.height);
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

CGRect CGRectUnion(CGRect a, CGRect b)
{
    if (CGRectIsNull(a))
        return CGRectStandardize(b);
    if (CGRectIsNull(b))
        return CGRectStandardize(a);
    a = CGRectStandardize(a);
    b = CGRectStandardize(b);
    CGFloat x0 = fmin(a.origin.x, b.origin.x), y0 = fmin(a.origin.y, b.origin.y);
    CGFloat x1 = fmax(CGRectGetMaxX(a), CGRectGetMaxX(b)), y1 = fmax(CGRectGetMaxY(a), CGRectGetMaxY(b));
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

CGRect CGRectIntersection(CGRect a, CGRect b)
{
    if (CGRectIsNull(a) || CGRectIsNull(b))
        return CGRectNull;
    a = CGRectStandardize(a);
    b = CGRectStandardize(b);
    CGFloat x0 = fmax(a.origin.x, b.origin.x), y0 = fmax(a.origin.y, b.origin.y);
    CGFloat x1 = fmin(CGRectGetMaxX(a), CGRectGetMaxX(b)), y1 = fmin(CGRectGetMaxY(a), CGRectGetMaxY(b));
    if (x1 < x0 || y1 < y0)
        return CGRectNull;
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

bool CGRectIntersectsRect(CGRect a, CGRect b) { return !CGRectIsEmpty(CGRectIntersection(a, b)); }

bool CGRectContainsPoint(CGRect r, CGPoint p)
{
    if (CGRectIsNull(r))
        return false;
    r = CGRectStandardize(r);
    return p.x >= r.origin.x && p.x < r.origin.x + r.size.width && p.y >= r.origin.y &&
           p.y < r.origin.y + r.size.height;
}

bool CGRectContainsRect(CGRect a, CGRect b)
{
    if (CGRectIsNull(a) || CGRectIsNull(b))
        return false;
    return CGRectEqualToRect(CGRectUnion(a, b), CGRectStandardize(a));
}

void CGRectDivide(CGRect r, CGRect *slice, CGRect *remainder, CGFloat amount, CGRectEdge edge)
{
    r = CGRectStandardize(r);
    CGRect s = r, rest = r;
    switch (edge) {
    case CGRectMinXEdge:
        amount = fmin(fmax(amount, 0), r.size.width);
        s.size.width = amount;
        rest.origin.x += amount;
        rest.size.width -= amount;
        break;
    case CGRectMaxXEdge:
        amount = fmin(fmax(amount, 0), r.size.width);
        s.origin.x = CGRectGetMaxX(r) - amount;
        s.size.width = amount;
        rest.size.width -= amount;
        break;
    case CGRectMinYEdge:
        amount = fmin(fmax(amount, 0), r.size.height);
        s.size.height = amount;
        rest.origin.y += amount;
        rest.size.height -= amount;
        break;
    case CGRectMaxYEdge:
        amount = fmin(fmax(amount, 0), r.size.height);
        s.origin.y = CGRectGetMaxY(r) - amount;
        s.size.height = amount;
        rest.size.height -= amount;
        break;
    }
    if (slice)
        *slice = s;
    if (remainder)
        *remainder = rest;
}

/* ---- affine transforms ----------------------------------------------------------- */

CGAffineTransform CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx, CGFloat ty)
{
    CGAffineTransform t = {a, b, c, d, tx, ty};
    return t;
}

CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty)
{
    return CGAffineTransformMake(1, 0, 0, 1, tx, ty);
}

CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy)
{
    return CGAffineTransformMake(sx, 0, 0, sy, 0, 0);
}

CGAffineTransform CGAffineTransformMakeRotation(CGFloat angle)
{
    CGFloat s = sin(angle), c = cos(angle);
    return CGAffineTransformMake(c, s, -s, c, 0, 0);
}

bool CGAffineTransformIsIdentity(CGAffineTransform t)
{
    return CGAffineTransformEqualToTransform(t, CGAffineTransformIdentity);
}

bool CGAffineTransformEqualToTransform(CGAffineTransform x, CGAffineTransform y)
{
    return x.a == y.a && x.b == y.b && x.c == y.c && x.d == y.d && x.tx == y.tx && x.ty == y.ty;
}

/* t1 then t2 */
CGAffineTransform CGAffineTransformConcat(CGAffineTransform t1, CGAffineTransform t2)
{
    return CGAffineTransformMake(t1.a * t2.a + t1.b * t2.c, t1.a * t2.b + t1.b * t2.d, t1.c * t2.a + t1.d * t2.c,
                                 t1.c * t2.b + t1.d * t2.d, t1.tx * t2.a + t1.ty * t2.c + t2.tx,
                                 t1.tx * t2.b + t1.ty * t2.d + t2.ty);
}

CGAffineTransform CGAffineTransformTranslate(CGAffineTransform t, CGFloat tx, CGFloat ty)
{
    return CGAffineTransformConcat(CGAffineTransformMakeTranslation(tx, ty), t);
}

CGAffineTransform CGAffineTransformScale(CGAffineTransform t, CGFloat sx, CGFloat sy)
{
    return CGAffineTransformConcat(CGAffineTransformMakeScale(sx, sy), t);
}

CGAffineTransform CGAffineTransformRotate(CGAffineTransform t, CGFloat angle)
{
    return CGAffineTransformConcat(CGAffineTransformMakeRotation(angle), t);
}

CGAffineTransform CGAffineTransformInvert(CGAffineTransform t)
{
    CGFloat det = t.a * t.d - t.b * t.c;
    if (det == 0)
        return t;   /* Apple's documented behaviour for a transform that can't be inverted */
    return CGAffineTransformMake(t.d / det, -t.b / det, -t.c / det, t.a / det, (t.c * t.ty - t.d * t.tx) / det,
                                 (t.b * t.tx - t.a * t.ty) / det);
}

CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t)
{
    return CGPointMake(t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty);
}

CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t)
{
    return CGSizeMake(t.a * s.width + t.c * s.height, t.b * s.width + t.d * s.height);
}

CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t)
{
    if (CGRectIsNull(r))
        return r;
    r = CGRectStandardize(r);
    CGPoint p[4] = {
        CGPointApplyAffineTransform(r.origin, t),
        CGPointApplyAffineTransform(CGPointMake(CGRectGetMaxX(r), r.origin.y), t),
        CGPointApplyAffineTransform(CGPointMake(r.origin.x, CGRectGetMaxY(r)), t),
        CGPointApplyAffineTransform(CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)), t),
    };
    CGFloat x0 = p[0].x, x1 = p[0].x, y0 = p[0].y, y1 = p[0].y;
    for (int i = 1; i < 4; i++) {
        x0 = fmin(x0, p[i].x);
        x1 = fmax(x1, p[i].x);
        y0 = fmin(y0, p[i].y);
        y1 = fmax(y1, p[i].y);
    }
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

/* ---- dictionary forms ------------------------------------------------------------- */

CFDictionaryRef CGPointCreateDictionaryRepresentation(CGPoint p)
{
    return (CFDictionaryRef)[[NSDictionary alloc] initWithObjectsAndKeys:@(p.x), @"X", @(p.y), @"Y", nil];
}

CFDictionaryRef CGSizeCreateDictionaryRepresentation(CGSize s)
{
    return (CFDictionaryRef)[[NSDictionary alloc]
        initWithObjectsAndKeys:@(s.width), @"Width", @(s.height), @"Height", nil];
}

CFDictionaryRef CGRectCreateDictionaryRepresentation(CGRect r)
{
    return (CFDictionaryRef)[[NSDictionary alloc]
        initWithObjectsAndKeys:@(r.origin.x), @"X", @(r.origin.y), @"Y", @(r.size.width), @"Width",
                               @(r.size.height), @"Height", nil];
}

static BOOL number_for(CFDictionaryRef d, NSString *key, CGFloat *out)
{
    id n = [(NSDictionary *)d objectForKey:key];
    if (![n isKindOfClass:[NSNumber class]])
        return NO;
    *out = [n doubleValue];
    return YES;
}

bool CGPointMakeWithDictionaryRepresentation(CFDictionaryRef d, CGPoint *p)
{
    CGPoint q;
    if (!d || !number_for(d, @"X", &q.x) || !number_for(d, @"Y", &q.y))
        return false;
    if (p)
        *p = q;
    return true;
}

bool CGSizeMakeWithDictionaryRepresentation(CFDictionaryRef d, CGSize *s)
{
    CGSize q;
    if (!d || !number_for(d, @"Width", &q.width) || !number_for(d, @"Height", &q.height))
        return false;
    if (s)
        *s = q;
    return true;
}

bool CGRectMakeWithDictionaryRepresentation(CFDictionaryRef d, CGRect *r)
{
    CGRect q;
    if (!CGPointMakeWithDictionaryRepresentation(d, &q.origin) || !CGSizeMakeWithDictionaryRepresentation(d, &q.size))
        return false;
    if (r)
        *r = q;
    return true;
}
