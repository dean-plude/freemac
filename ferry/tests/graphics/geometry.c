/* Ferry M3 test: Core Graphics geometry and affine transforms, from plain C. */
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

static void rect(const char *what, CGRect r)
{
    if (CGRectIsNull(r))
        printf("%s: null\n", what);
    else
        printf("%s: %g %g %g %g\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}

static void xform(const char *what, CGAffineTransform t)
{
    printf("%s: [%g %g %g %g %g %g]\n", what, round(t.a * 1000) / 1000 + 0.0, round(t.b * 1000) / 1000 + 0.0,
           round(t.c * 1000) / 1000 + 0.0, round(t.d * 1000) / 1000 + 0.0, round(t.tx * 1000) / 1000 + 0.0,
           round(t.ty * 1000) / 1000 + 0.0);
}

int main(void)
{
    CGRect a = CGRectMake(10, 20, 100, 50), b = CGRectMake(60, 40, 100, 100);
    rect("standardize", CGRectStandardize(CGRectMake(10, 10, -5, -20)));
    printf("min/mid/max x: %g %g %g, height %g\n", CGRectGetMinX(a), CGRectGetMidX(a), CGRectGetMaxX(a),
           CGRectGetHeight(CGRectMake(0, 0, 3, -7)));
    rect("union", CGRectUnion(a, b));
    rect("intersection", CGRectIntersection(a, b));
    rect("no intersection", CGRectIntersection(a, CGRectMake(500, 500, 1, 1)));
    rect("inset", CGRectInset(a, 5, 10));
    rect("inset too far", CGRectInset(a, 60, 0));
    rect("offset", CGRectOffset(a, -10, 5));
    rect("integral", CGRectIntegral(CGRectMake(0.5, 1.2, 10.1, 3.3)));
    CGRect slice, rest;
    CGRectDivide(a, &slice, &rest, 30, CGRectMinXEdge);
    rect("divide slice", slice);
    rect("divide rest", rest);
    printf("contains point: %d %d, contains rect: %d, intersects: %d, empty: %d %d\n",
           CGRectContainsPoint(a, CGPointMake(10, 20)), CGRectContainsPoint(a, CGPointMake(110, 20)),
           CGRectContainsRect(a, CGRectMake(20, 30, 10, 10)), CGRectIntersectsRect(a, b),
           CGRectIsEmpty(CGRectMake(1, 1, 0, 5)), CGRectIsEmpty(a));
    printf("null union: %d, infinite: %d\n", CGRectEqualToRect(CGRectUnion(CGRectNull, a), a),
           CGRectIsInfinite(CGRectInfinite));

    CGAffineTransform t = CGAffineTransformMakeTranslation(10, 20);
    t = CGAffineTransformScale(t, 2, 3);
    xform("translate then scale", t);
    CGPoint p = CGPointApplyAffineTransform(CGPointMake(1, 1), t);
    printf("point: %g %g\n", p.x, p.y);
    xform("inverse", CGAffineTransformInvert(t));
    xform("rotate 90", CGAffineTransformMakeRotation(M_PI / 2));
    p = CGPointApplyAffineTransform(CGPointMake(1, 0), CGAffineTransformMakeRotation(M_PI / 2));
    printf("rotated point: %g %g\n", round(p.x * 1000) / 1000 + 0.0, round(p.y * 1000) / 1000 + 0.0);
    xform("concat", CGAffineTransformConcat(CGAffineTransformMakeScale(2, 2), CGAffineTransformMakeTranslation(5, 0)));
    printf("identity: %d %d\n", CGAffineTransformIsIdentity(CGAffineTransformIdentity),
           CGAffineTransformIsIdentity(t));
    rect("rect through rotation", CGRectApplyAffineTransform(CGRectMake(0, 0, 10, 20),
                                                              CGAffineTransformMakeRotation(M_PI / 2)));
    CFDictionaryRef d = CGRectCreateDictionaryRepresentation(a);
    CGRect back;
    printf("dictionary round trip: %d\n", CGRectMakeWithDictionaryRepresentation(d, &back) && CGRectEqualToRect(a, back));
    CFRelease(d);
    return 0;
}
