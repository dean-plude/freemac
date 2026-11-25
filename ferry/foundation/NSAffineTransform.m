/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSAffineTransform (freemac 1.219, Ferry 0.43.0). Written for freemac from
 * Apple's public documentation of NSAffineTransform: a point (x, y) goes to
 * (m11 x + m21 y + tX, m12 x + m22 y + tY). translate, rotate and scale act
 * before the current transform, as the documentation says (the new operation
 * is applied to points first). append: self, then the other one; prepend: the
 * other one, then self. AppKit's -set, -concat and -transformBezierPath: are in
 * appkit/NSGraphics.m. */
#import "FInternal.h"
#include <math.h>

@implementation NSAffineTransform {
    NSAffineTransformStruct _t;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (NSAffineTransform *)transform { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        _t.m11 = 1;
        _t.m22 = 1;
    }
    return self;
}
- (instancetype)initWithTransform:(NSAffineTransform *)transform
{
    if ((self = [super init])) {
        if (transform)
            _t = [transform transformStruct];
        else {
            _t.m11 = 1;
            _t.m22 = 1;
        }
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return [[NSAffineTransform alloc] initWithTransform:self]; }
- (NSAffineTransformStruct)transformStruct { return _t; }
- (void)setTransformStruct:(NSAffineTransformStruct)s { _t = s; }

/* Row-vector matrices: the product a * b maps points through a, then b. */
static NSAffineTransformStruct multiply(NSAffineTransformStruct a, NSAffineTransformStruct b)
{
    NSAffineTransformStruct r;
    r.m11 = a.m11 * b.m11 + a.m12 * b.m21;
    r.m12 = a.m11 * b.m12 + a.m12 * b.m22;
    r.m21 = a.m21 * b.m11 + a.m22 * b.m21;
    r.m22 = a.m21 * b.m12 + a.m22 * b.m22;
    r.tX = a.tX * b.m11 + a.tY * b.m21 + b.tX;
    r.tY = a.tX * b.m12 + a.tY * b.m22 + b.tY;
    return r;
}
- (void)translateXBy:(CGFloat)dx yBy:(CGFloat)dy
{
    _t.tX += _t.m11 * dx + _t.m21 * dy;
    _t.tY += _t.m12 * dx + _t.m22 * dy;
}
- (void)scaleXBy:(CGFloat)sx yBy:(CGFloat)sy
{
    _t.m11 *= sx;
    _t.m12 *= sx;
    _t.m21 *= sy;
    _t.m22 *= sy;
}
- (void)scaleBy:(CGFloat)s { [self scaleXBy:s yBy:s]; }
- (void)rotateByRadians:(CGFloat)a
{
    CGFloat c = cos(a), s = sin(a);
    /* Snap the exact quarter turns so that 90 degrees gives clean zeros. */
    if (fabs(c) < 1e-15)
        c = 0;
    if (fabs(s) < 1e-15)
        s = 0;
    NSAffineTransformStruct o = _t;
    _t.m11 = c * o.m11 + s * o.m21;
    _t.m12 = c * o.m12 + s * o.m22;
    _t.m21 = -s * o.m11 + c * o.m21;
    _t.m22 = -s * o.m12 + c * o.m22;
}
- (void)rotateByDegrees:(CGFloat)a { [self rotateByRadians:a * M_PI / 180.0]; }
- (void)invert
{
    NSAffineTransformStruct o = _t;
    CGFloat det = o.m11 * o.m22 - o.m12 * o.m21;
    if (det == 0)
        return;
    _t.m11 = o.m22 / det;
    _t.m12 = -o.m12 / det;
    _t.m21 = -o.m21 / det;
    _t.m22 = o.m11 / det;
    _t.tX = (o.m21 * o.tY - o.m22 * o.tX) / det;
    _t.tY = (o.m12 * o.tX - o.m11 * o.tY) / det;
}
- (void)appendTransform:(NSAffineTransform *)t
{
    if (t)
        _t = multiply(_t, [t transformStruct]);
}
- (void)prependTransform:(NSAffineTransform *)t
{
    if (t)
        _t = multiply([t transformStruct], _t);
}
- (NSPoint)transformPoint:(NSPoint)p
{
    return NSMakePoint(_t.m11 * p.x + _t.m21 * p.y + _t.tX, _t.m12 * p.x + _t.m22 * p.y + _t.tY);
}
- (NSSize)transformSize:(NSSize)s
{
    return NSMakeSize(_t.m11 * s.width + _t.m21 * s.height, _t.m12 * s.width + _t.m22 * s.height);
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSAffineTransform class]])
        return NO;
    NSAffineTransformStruct o = [other transformStruct];
    return o.m11 == _t.m11 && o.m12 == _t.m12 && o.m21 == _t.m21 && o.m22 == _t.m22 && o.tX == _t.tX &&
           o.tY == _t.tY;
}
- (NSUInteger)hash { return (NSUInteger)(_t.m11 * 31 + _t.m22 * 17 + _t.tX * 7 + _t.tY); }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSAffineTransform m11=%g m12=%g m21=%g m22=%g tX=%g tY=%g>", _t.m11,
                                      _t.m12, _t.m21, _t.m22, _t.tX, _t.tY];
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeDouble:_t.m11 forKey:@"m11"];
    [c encodeDouble:_t.m12 forKey:@"m12"];
    [c encodeDouble:_t.m21 forKey:@"m21"];
    [c encodeDouble:_t.m22 forKey:@"m22"];
    [c encodeDouble:_t.tX forKey:@"tX"];
    [c encodeDouble:_t.tY forKey:@"tY"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        _t.m11 = [c decodeDoubleForKey:@"m11"];
        _t.m12 = [c decodeDoubleForKey:@"m12"];
        _t.m21 = [c decodeDoubleForKey:@"m21"];
        _t.m22 = [c decodeDoubleForKey:@"m22"];
        _t.tX = [c decodeDoubleForKey:@"tX"];
        _t.tY = [c decodeDoubleForKey:@"tY"];
    }
    return self;
}
@end
