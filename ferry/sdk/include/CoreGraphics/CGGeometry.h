/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Core Graphics geometry (points, sizes, rectangles and affine
 * transforms). Foundation's NSGeometry types are these, as on a Mac.
 * Written for freemac from Apple's public API documentation. */
#ifndef _FERRY_CGGEOMETRY_H_
#define _FERRY_CGGEOMETRY_H_
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#ifndef CG_EXTERN
#define CG_EXTERN extern
#define CG_INLINE static inline
#endif

__FERRY_BEGIN

/* ---- geometry --------------------------------------------------------------- */

typedef double CGFloat;
#define CGFLOAT_IS_DOUBLE 1
#define CGFLOAT_MIN 2.2250738585072014e-308
#define CGFLOAT_MAX 1.7976931348623157e+308
typedef struct CGPoint { CGFloat x, y; } CGPoint;
typedef struct CGSize { CGFloat width, height; } CGSize;
typedef struct CGVector { CGFloat dx, dy; } CGVector;
typedef struct CGRect { CGPoint origin; CGSize size; } CGRect;
typedef struct CGAffineTransform { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
typedef enum { CGRectMinXEdge, CGRectMinYEdge, CGRectMaxXEdge, CGRectMaxYEdge } CGRectEdge;

extern const CGPoint CGPointZero;
extern const CGSize CGSizeZero;
extern const CGRect CGRectZero;
extern const CGRect CGRectNull;
extern const CGRect CGRectInfinite;
extern const CGAffineTransform CGAffineTransformIdentity;

CG_INLINE CGPoint CGPointMake(CGFloat x, CGFloat y) { CGPoint p = {x, y}; return p; }
CG_INLINE CGSize CGSizeMake(CGFloat w, CGFloat h) { CGSize s = {w, h}; return s; }
CG_INLINE CGVector CGVectorMake(CGFloat dx, CGFloat dy) { CGVector v = {dx, dy}; return v; }
CG_INLINE CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
    CGRect r = {{x, y}, {w, h}};
    return r;
}

CGFloat CGRectGetMinX(CGRect r);
CGFloat CGRectGetMidX(CGRect r);
CGFloat CGRectGetMaxX(CGRect r);
CGFloat CGRectGetMinY(CGRect r);
CGFloat CGRectGetMidY(CGRect r);
CGFloat CGRectGetMaxY(CGRect r);
CGFloat CGRectGetWidth(CGRect r);
CGFloat CGRectGetHeight(CGRect r);
bool CGPointEqualToPoint(CGPoint a, CGPoint b);
bool CGSizeEqualToSize(CGSize a, CGSize b);
bool CGRectEqualToRect(CGRect a, CGRect b);
CGRect CGRectStandardize(CGRect r);
bool CGRectIsEmpty(CGRect r);
bool CGRectIsNull(CGRect r);
bool CGRectIsInfinite(CGRect r);
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy);
CGRect CGRectIntegral(CGRect r);
CGRect CGRectUnion(CGRect a, CGRect b);
CGRect CGRectIntersection(CGRect a, CGRect b);
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy);
void CGRectDivide(CGRect r, CGRect *slice, CGRect *remainder, CGFloat amount, CGRectEdge edge);
bool CGRectContainsPoint(CGRect r, CGPoint p);
bool CGRectContainsRect(CGRect a, CGRect b);
bool CGRectIntersectsRect(CGRect a, CGRect b);

CGAffineTransform CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy);
CGAffineTransform CGAffineTransformMakeRotation(CGFloat angle);
bool CGAffineTransformIsIdentity(CGAffineTransform t);
CGAffineTransform CGAffineTransformTranslate(CGAffineTransform t, CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformScale(CGAffineTransform t, CGFloat sx, CGFloat sy);
CGAffineTransform CGAffineTransformRotate(CGAffineTransform t, CGFloat angle);
CGAffineTransform CGAffineTransformInvert(CGAffineTransform t);
CGAffineTransform CGAffineTransformConcat(CGAffineTransform t1, CGAffineTransform t2);
bool CGAffineTransformEqualToTransform(CGAffineTransform t1, CGAffineTransform t2);
CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t);
CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t);
CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t);

CFDictionaryRef CGPointCreateDictionaryRepresentation(CGPoint p);
CFDictionaryRef CGSizeCreateDictionaryRepresentation(CGSize s);
CFDictionaryRef CGRectCreateDictionaryRepresentation(CGRect r);
bool CGPointMakeWithDictionaryRepresentation(CFDictionaryRef d, CGPoint *p);
bool CGSizeMakeWithDictionaryRepresentation(CFDictionaryRef d, CGSize *s);
bool CGRectMakeWithDictionaryRepresentation(CFDictionaryRef d, CGRect *r);
__FERRY_END

#endif
