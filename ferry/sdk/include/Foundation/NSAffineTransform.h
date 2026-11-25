/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSAffineTransform (freemac 1.219, Ferry 0.43.0). Written for
 * freemac from Apple's public documentation; not Apple's header. A point
 * (x, y) goes to (m11 x + m21 y + tX, m12 x + m22 y + tY). AppKit adds
 * -set, -concat and -transformBezierPath:. */
#ifndef _FERRY_FOUNDATION_NSAFFINETRANSFORM_H_
#define _FERRY_FOUNDATION_NSAFFINETRANSFORM_H_
#include <Foundation/Foundation.h>

typedef struct {
    CGFloat m11, m12, m21, m22;
    CGFloat tX, tY;
} NSAffineTransformStruct;

@interface NSAffineTransform : NSObject <NSCopying, NSSecureCoding>
+ (NSAffineTransform *)transform;
- (instancetype FERRY_SWIFT_NONNULL)init;
- (instancetype FERRY_SWIFT_NONNULL)initWithTransform:(NSAffineTransform *)transform;
- (void)translateXBy:(CGFloat)deltaX yBy:(CGFloat)deltaY;
- (void)rotateByDegrees:(CGFloat)angle;
- (void)rotateByRadians:(CGFloat)angle;
- (void)scaleBy:(CGFloat)scale;
- (void)scaleXBy:(CGFloat)scaleX yBy:(CGFloat)scaleY;
- (void)invert;
- (void)appendTransform:(NSAffineTransform *)transform;
- (void)prependTransform:(NSAffineTransform *)transform;
- (NSPoint)transformPoint:(NSPoint)aPoint;
- (NSSize)transformSize:(NSSize)aSize;
@property NSAffineTransformStruct transformStruct;
@end

#endif
