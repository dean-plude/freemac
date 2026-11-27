/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core Animation (QuartzCore) subset Ferry provides. Written
 * for freemac from Apple's public API documentation; not Apple's header.
 * Every class and call declared here is implemented in ferry/quartzcore.
 * Layers are drawn with Ferry's own Core Graphics, on the program's one
 * thread; animations are stepped by a timer on the main run loop. From C
 * (VLC's cvpx module, freemac 1.NEXT) only the time and 3D transform calls
 * are declared, with Core Video, as on a Mac; the rest is Objective-C. */
#ifndef _FERRY_QUARTZCORE_H_
#define _FERRY_QUARTZCORE_H_
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#else
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#endif
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>

#define CA_EXTERN extern

__FERRY_BEGIN

/* ---- time and 3D transforms ------------------------------------------------------- */

/* Seconds since an arbitrary moment, from a clock that never goes back. */
CFTimeInterval CACurrentMediaTime(void);

typedef struct CATransform3D {
    CGFloat m11, m12, m13, m14;
    CGFloat m21, m22, m23, m24;
    CGFloat m31, m32, m33, m34;
    CGFloat m41, m42, m43, m44;
} CATransform3D;

CA_EXTERN const CATransform3D CATransform3DIdentity;
bool CATransform3DIsIdentity(CATransform3D t);
bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b);
CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz);
CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz);
CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z);
CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz);
CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz);
CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z);
CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b);
CATransform3D CATransform3DInvert(CATransform3D t);
CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform m);
bool CATransform3DIsAffine(CATransform3D t);
CGAffineTransform CATransform3DGetAffineTransform(CATransform3D t);

__FERRY_END

#ifdef __OBJC__
@interface NSValue (CATransform3DAdditions)
+ (NSValue *)valueWithCATransform3D:(CATransform3D)t;
@property (readonly) CATransform3D CATransform3DValue;
@end

/* ---- timing --------------------------------------------------------------------- */

typedef NSString *CAMediaTimingFillMode;
CA_EXTERN CAMediaTimingFillMode const kCAFillModeForwards;
CA_EXTERN CAMediaTimingFillMode const kCAFillModeBackwards;
CA_EXTERN CAMediaTimingFillMode const kCAFillModeBoth;
CA_EXTERN CAMediaTimingFillMode const kCAFillModeRemoved;

@protocol CAMediaTiming
@property CFTimeInterval beginTime;
@property CFTimeInterval duration;
@property float speed;
@property CFTimeInterval timeOffset;
@property float repeatCount;
@property CFTimeInterval repeatDuration;
@property BOOL autoreverses;
@property (copy) CAMediaTimingFillMode fillMode;
@end

typedef NSString *CAMediaTimingFunctionName;
CA_EXTERN CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear;
CA_EXTERN CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseIn;
CA_EXTERN CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseOut;
CA_EXTERN CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseInEaseOut;
CA_EXTERN CAMediaTimingFunctionName const kCAMediaTimingFunctionDefault;

@interface CAMediaTimingFunction : NSObject <NSSecureCoding, NSCopying>
+ (instancetype)functionWithName:(CAMediaTimingFunctionName)name;
+ (instancetype)functionWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y;
- (instancetype)initWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y;
- (void)getControlPointAtIndex:(size_t)idx values:(float[2])ptr;
@end

/* ---- transactions --------------------------------------------------------------- */

CA_EXTERN NSString *const kCATransactionAnimationDuration;
CA_EXTERN NSString *const kCATransactionDisableActions;
CA_EXTERN NSString *const kCATransactionAnimationTimingFunction;
CA_EXTERN NSString *const kCATransactionCompletionBlock;

@interface CATransaction : NSObject
+ (void)begin;
+ (void)commit;
+ (void)flush;
+ (void)lock;
+ (void)unlock;
+ (CFTimeInterval)animationDuration;
+ (void)setAnimationDuration:(CFTimeInterval)duration;
+ (CAMediaTimingFunction *)animationTimingFunction;
+ (void)setAnimationTimingFunction:(CAMediaTimingFunction *)function;
+ (BOOL)disableActions;
+ (void)setDisableActions:(BOOL)flag;
+ (void (^)(void))completionBlock;
+ (void)setCompletionBlock:(void (^)(void))block;
+ (id)valueForKey:(NSString *)key;
+ (void)setValue:(id)value forKey:(NSString *)key;
@end

/* ---- layers ----------------------------------------------------------------------- */

@class CALayer, CAAnimation;

@protocol CAAction
- (void)runActionForKey:(NSString *)event object:(id)anObject arguments:(NSDictionary *)dict;
@end
@interface NSNull (CAActionAdditions) <CAAction>
@end

@protocol CALayerDelegate <NSObject>
@optional
- (void)displayLayer:(CALayer *)layer;
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
- (void)layerWillDraw:(CALayer *)layer;
- (void)layoutSublayersOfLayer:(CALayer *)layer;
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event;
@end

@protocol CALayoutManager <NSObject>
@optional
- (CGSize)preferredSizeOfLayer:(CALayer *)layer;
- (void)invalidateLayoutOfLayer:(CALayer *)layer;
- (void)layoutSublayersOfLayer:(CALayer *)layer;
@end

typedef NSString *CALayerContentsGravity;
CA_EXTERN CALayerContentsGravity const kCAGravityCenter;
CA_EXTERN CALayerContentsGravity const kCAGravityTop;
CA_EXTERN CALayerContentsGravity const kCAGravityBottom;
CA_EXTERN CALayerContentsGravity const kCAGravityLeft;
CA_EXTERN CALayerContentsGravity const kCAGravityRight;
CA_EXTERN CALayerContentsGravity const kCAGravityTopLeft;
CA_EXTERN CALayerContentsGravity const kCAGravityTopRight;
CA_EXTERN CALayerContentsGravity const kCAGravityBottomLeft;
CA_EXTERN CALayerContentsGravity const kCAGravityBottomRight;
CA_EXTERN CALayerContentsGravity const kCAGravityResize;
CA_EXTERN CALayerContentsGravity const kCAGravityResizeAspect;
CA_EXTERN CALayerContentsGravity const kCAGravityResizeAspectFill;

typedef NSString *CALayerContentsFilter;
CA_EXTERN CALayerContentsFilter const kCAFilterNearest;
CA_EXTERN CALayerContentsFilter const kCAFilterLinear;
CA_EXTERN CALayerContentsFilter const kCAFilterTrilinear;

typedef NSString *CALayerContentsFormat;
CA_EXTERN CALayerContentsFormat const kCAContentsFormatRGBA8Uint;

CA_EXTERN NSString *const kCAOnOrderIn;
CA_EXTERN NSString *const kCAOnOrderOut;
CA_EXTERN NSString *const kCATransition;

typedef NS_OPTIONS(unsigned int, CAAutoresizingMask) {
    kCALayerNotSizable = 0, kCALayerMinXMargin = 1 << 0, kCALayerWidthSizable = 1 << 1,
    kCALayerMaxXMargin = 1 << 2, kCALayerMinYMargin = 1 << 3, kCALayerHeightSizable = 1 << 4,
    kCALayerMaxYMargin = 1 << 5,
};
typedef NS_OPTIONS(NSUInteger, CACornerMask) {
    kCALayerMinXMinYCorner = 1U << 0, kCALayerMaxXMinYCorner = 1U << 1,
    kCALayerMinXMaxYCorner = 1U << 2, kCALayerMaxXMaxYCorner = 1U << 3,
};
/* How a rounded corner meets the straight edges (freemac 1.232); kept,
 * and drawn as a circular corner either way. */
typedef NSString *CALayerCornerCurve;
CA_EXTERN CALayerCornerCurve const kCACornerCurveCircular, kCACornerCurveContinuous;
typedef NS_OPTIONS(unsigned int, CAEdgeAntialiasingMask) {
    kCALayerLeftEdge = 1U << 0, kCALayerRightEdge = 1U << 1, kCALayerBottomEdge = 1U << 2,
    kCALayerTopEdge = 1U << 3,
};

@interface CALayer : NSObject <NSSecureCoding, CAMediaTiming>
+ (instancetype)layer;
- (instancetype)init;
- (instancetype)initWithLayer:(id)layer;
- (instancetype)presentationLayer;
- (instancetype)modelLayer;

+ (id)defaultValueForKey:(NSString *)key;
+ (BOOL)needsDisplayForKey:(NSString *)key;
- (BOOL)shouldArchiveValueForKey:(NSString *)key;

@property CGRect bounds;
@property CGPoint position;
@property CGFloat zPosition;
@property CGPoint anchorPoint;
@property CGFloat anchorPointZ;
@property CATransform3D transform;
- (CGAffineTransform)affineTransform;
- (void)setAffineTransform:(CGAffineTransform)m;
@property CGRect frame;
@property (getter=isHidden) BOOL hidden;
@property (getter=isDoubleSided) BOOL doubleSided;
@property (getter=isGeometryFlipped) BOOL geometryFlipped;
- (BOOL)contentsAreFlipped;

@property (readonly) CALayer *superlayer;
- (void)removeFromSuperlayer;
@property (copy) NSArray<CALayer *> *sublayers;
- (void)addSublayer:(CALayer *)layer;
- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)idx;
- (void)insertSublayer:(CALayer *)layer below:(CALayer *)sibling;
- (void)insertSublayer:(CALayer *)layer above:(CALayer *)sibling;
- (void)replaceSublayer:(CALayer *)oldLayer with:(CALayer *)newLayer;
@property CATransform3D sublayerTransform;
@property (strong) CALayer *mask;
@property BOOL masksToBounds;

- (CGPoint)convertPoint:(CGPoint)p fromLayer:(CALayer *)l;
- (CGPoint)convertPoint:(CGPoint)p toLayer:(CALayer *)l;
- (CGRect)convertRect:(CGRect)r fromLayer:(CALayer *)l;
- (CGRect)convertRect:(CGRect)r toLayer:(CALayer *)l;
- (CFTimeInterval)convertTime:(CFTimeInterval)t fromLayer:(CALayer *)l;
- (CFTimeInterval)convertTime:(CFTimeInterval)t toLayer:(CALayer *)l;
- (CALayer *)hitTest:(CGPoint)p;
- (BOOL)containsPoint:(CGPoint)p;

@property (strong) id contents;
@property CGRect contentsRect;
@property (copy) CALayerContentsGravity contentsGravity;
@property CGFloat contentsScale;
@property CGRect contentsCenter;
@property (copy) CALayerContentsFormat contentsFormat;
@property (copy) CALayerContentsFilter minificationFilter;
@property (copy) CALayerContentsFilter magnificationFilter;
@property float minificationFilterBias;
@property (getter=isOpaque) BOOL opaque;
- (void)display;
- (void)setNeedsDisplay;
- (void)setNeedsDisplayInRect:(CGRect)r;
- (BOOL)needsDisplay;
- (void)displayIfNeeded;
@property BOOL needsDisplayOnBoundsChange;
@property BOOL drawsAsynchronously;
- (void)drawInContext:(CGContextRef)ctx;
- (void)renderInContext:(CGContextRef)ctx;
@property CAEdgeAntialiasingMask edgeAntialiasingMask;
@property BOOL allowsEdgeAntialiasing;
@property CGColorRef backgroundColor;
@property CGFloat cornerRadius;
@property CACornerMask maskedCorners;
@property (copy) CALayerCornerCurve cornerCurve;
@property CGFloat borderWidth;
@property CGColorRef borderColor;
@property float opacity;
@property BOOL allowsGroupOpacity;
@property (strong) id compositingFilter;
@property (copy) NSArray *filters;
@property (copy) NSArray *backgroundFilters;
@property BOOL shouldRasterize;
@property CGFloat rasterizationScale;
@property CGColorRef shadowColor;
@property float shadowOpacity;
@property CGSize shadowOffset;
@property CGFloat shadowRadius;
@property CGPathRef shadowPath;

- (CGSize)preferredFrameSize;
- (void)setNeedsLayout;
- (BOOL)needsLayout;
- (void)layoutIfNeeded;
- (void)layoutSublayers;
/* An id<CALayoutManager>. Typed id here (freemac 1.226, Ferry 0.50.0):
 * AppKit imports this header before its text classes, so for a message to
 * an id this would be the first layoutManager clang meets, and
 * [[textView layoutManager] glyphRange…] would find no such method, as it
 * does on a Mac, where NSTextView's comes first. */
@property (strong) id layoutManager;
@property CAAutoresizingMask autoresizingMask;
- (void)resizeSublayersWithOldSize:(CGSize)size;
- (void)resizeWithOldSuperlayerSize:(CGSize)size;

+ (id<CAAction>)defaultActionForKey:(NSString *)event;
- (id<CAAction>)actionForKey:(NSString *)event;
@property (copy) NSDictionary<NSString *, id<CAAction>> *actions;

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key;
- (void)removeAllAnimations;
- (void)removeAnimationForKey:(NSString *)key;
- (NSArray<NSString *> *)animationKeys;
- (CAAnimation *)animationForKey:(NSString *)key;

@property (copy) NSString *name;
@property (weak) id<CALayerDelegate> delegate;
@property (copy) NSDictionary *style;

/* CAMediaTiming */
@property CFTimeInterval beginTime;
@property CFTimeInterval duration;
@property float speed;
@property CFTimeInterval timeOffset;
@property float repeatCount;
@property CFTimeInterval repeatDuration;
@property BOOL autoreverses;
@property (copy) CAMediaTimingFillMode fillMode;
@end

/* whether the layer's content may be brighter than white (macOS 14); Ferry
 * keeps the setting and draws in standard range */
@interface CALayer (FerryExtendedDynamicRange)
@property BOOL wantsExtendedDynamicRangeContent;
@end

/* ---- animations ------------------------------------------------------------------- */

@protocol CAAnimationDelegate <NSObject>
@optional
- (void)animationDidStart:(CAAnimation *)anim;
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
@end

@interface CAAnimation : NSObject <NSSecureCoding, NSCopying, CAMediaTiming, CAAction>
+ (instancetype)animation;
+ (id)defaultValueForKey:(NSString *)key;
- (BOOL)shouldArchiveValueForKey:(NSString *)key;
@property (strong) CAMediaTimingFunction *timingFunction;
@property (strong) id<CAAnimationDelegate> delegate;
@property (getter=isRemovedOnCompletion) BOOL removedOnCompletion;
@property CFTimeInterval beginTime;
@property CFTimeInterval duration;
@property float speed;
@property CFTimeInterval timeOffset;
@property float repeatCount;
@property CFTimeInterval repeatDuration;
@property BOOL autoreverses;
@property (copy) CAMediaTimingFillMode fillMode;
@end

typedef NSString *CAValueFunctionName;
CA_EXTERN CAValueFunctionName const kCAValueFunctionRotateX;
CA_EXTERN CAValueFunctionName const kCAValueFunctionRotateY;
CA_EXTERN CAValueFunctionName const kCAValueFunctionRotateZ;
CA_EXTERN CAValueFunctionName const kCAValueFunctionScale;
CA_EXTERN CAValueFunctionName const kCAValueFunctionScaleX;
CA_EXTERN CAValueFunctionName const kCAValueFunctionScaleY;
CA_EXTERN CAValueFunctionName const kCAValueFunctionScaleZ;
CA_EXTERN CAValueFunctionName const kCAValueFunctionTranslate;
CA_EXTERN CAValueFunctionName const kCAValueFunctionTranslateX;
CA_EXTERN CAValueFunctionName const kCAValueFunctionTranslateY;
CA_EXTERN CAValueFunctionName const kCAValueFunctionTranslateZ;
@interface CAValueFunction : NSObject <NSSecureCoding>
+ (instancetype)functionWithName:(CAValueFunctionName)name;
@property (readonly) CAValueFunctionName name;
@end

@interface CAPropertyAnimation : CAAnimation
+ (instancetype)animationWithKeyPath:(NSString *)path;
@property (copy) NSString *keyPath;
@property (getter=isAdditive) BOOL additive;
@property (getter=isCumulative) BOOL cumulative;
@property (strong) CAValueFunction *valueFunction;
@end

@interface CABasicAnimation : CAPropertyAnimation
@property (strong) id fromValue;
@property (strong) id toValue;
@property (strong) id byValue;
@end

typedef NSString *CAAnimationCalculationMode;
CA_EXTERN CAAnimationCalculationMode const kCAAnimationLinear;
CA_EXTERN CAAnimationCalculationMode const kCAAnimationDiscrete;
CA_EXTERN CAAnimationCalculationMode const kCAAnimationPaced;
CA_EXTERN CAAnimationCalculationMode const kCAAnimationCubic;
CA_EXTERN CAAnimationCalculationMode const kCAAnimationCubicPaced;
typedef NSString *CAAnimationRotationMode;
CA_EXTERN CAAnimationRotationMode const kCAAnimationRotateAuto;
CA_EXTERN CAAnimationRotationMode const kCAAnimationRotateAutoReverse;

@interface CAKeyframeAnimation : CAPropertyAnimation
@property (copy) NSArray *values;
@property CGPathRef path;
@property (copy) NSArray<NSNumber *> *keyTimes;
@property (copy) NSArray<CAMediaTimingFunction *> *timingFunctions;
@property (copy) CAAnimationCalculationMode calculationMode;
@property (copy) NSArray<NSNumber *> *tensionValues;
@property (copy) NSArray<NSNumber *> *continuityValues;
@property (copy) NSArray<NSNumber *> *biasValues;
@property (copy) CAAnimationRotationMode rotationMode;
@end

@interface CASpringAnimation : CABasicAnimation
@property CGFloat mass;
@property CGFloat stiffness;
@property CGFloat damping;
@property CGFloat initialVelocity;
@property (readonly) CFTimeInterval settlingDuration;
@end

@interface CAAnimationGroup : CAAnimation
@property (copy) NSArray<CAAnimation *> *animations;
@end

typedef NSString *CATransitionType;
CA_EXTERN CATransitionType const kCATransitionFade;
CA_EXTERN CATransitionType const kCATransitionMoveIn;
CA_EXTERN CATransitionType const kCATransitionPush;
CA_EXTERN CATransitionType const kCATransitionReveal;
typedef NSString *CATransitionSubtype;
CA_EXTERN CATransitionSubtype const kCATransitionFromRight;
CA_EXTERN CATransitionSubtype const kCATransitionFromLeft;
CA_EXTERN CATransitionSubtype const kCATransitionFromTop;
CA_EXTERN CATransitionSubtype const kCATransitionFromBottom;

@interface CATransition : CAAnimation
@property (copy) CATransitionType type;
@property (copy) CATransitionSubtype subtype;
@property float startProgress;
@property float endProgress;
@property (strong) id filter;
@end

/* ---- layer kinds ---------------------------------------------------------------- */

typedef NSString *CATextLayerTruncationMode;
CA_EXTERN CATextLayerTruncationMode const kCATruncationNone;
CA_EXTERN CATextLayerTruncationMode const kCATruncationStart;
CA_EXTERN CATextLayerTruncationMode const kCATruncationEnd;
CA_EXTERN CATextLayerTruncationMode const kCATruncationMiddle;
typedef NSString *CATextLayerAlignmentMode;
CA_EXTERN CATextLayerAlignmentMode const kCAAlignmentNatural;
CA_EXTERN CATextLayerAlignmentMode const kCAAlignmentLeft;
CA_EXTERN CATextLayerAlignmentMode const kCAAlignmentRight;
CA_EXTERN CATextLayerAlignmentMode const kCAAlignmentCenter;
CA_EXTERN CATextLayerAlignmentMode const kCAAlignmentJustified;

@interface CATextLayer : CALayer
@property (copy) id string;
@property CFTypeRef font;
@property CGFloat fontSize;
@property CGColorRef foregroundColor;
@property (getter=isWrapped) BOOL wrapped;
@property (copy) CATextLayerTruncationMode truncationMode;
@property (copy) CATextLayerAlignmentMode alignmentMode;
@property BOOL allowsFontSubpixelQuantization;
@end

typedef NSString *CAShapeLayerFillRule;
CA_EXTERN CAShapeLayerFillRule const kCAFillRuleNonZero;
CA_EXTERN CAShapeLayerFillRule const kCAFillRuleEvenOdd;
typedef NSString *CAShapeLayerLineJoin;
CA_EXTERN CAShapeLayerLineJoin const kCALineJoinMiter;
CA_EXTERN CAShapeLayerLineJoin const kCALineJoinRound;
CA_EXTERN CAShapeLayerLineJoin const kCALineJoinBevel;
typedef NSString *CAShapeLayerLineCap;
CA_EXTERN CAShapeLayerLineCap const kCALineCapButt;
CA_EXTERN CAShapeLayerLineCap const kCALineCapRound;
CA_EXTERN CAShapeLayerLineCap const kCALineCapSquare;

@interface CAShapeLayer : CALayer
@property CGPathRef path;
@property CGColorRef fillColor;
@property (copy) CAShapeLayerFillRule fillRule;
@property CGColorRef strokeColor;
@property CGFloat strokeStart;
@property CGFloat strokeEnd;
@property CGFloat lineWidth;
@property CGFloat miterLimit;
@property (copy) CAShapeLayerLineCap lineCap;
@property (copy) CAShapeLayerLineJoin lineJoin;
@property CGFloat lineDashPhase;
@property (copy) NSArray<NSNumber *> *lineDashPattern;
@end

typedef NSString *CAGradientLayerType;
CA_EXTERN CAGradientLayerType const kCAGradientLayerAxial;
CA_EXTERN CAGradientLayerType const kCAGradientLayerRadial;
CA_EXTERN CAGradientLayerType const kCAGradientLayerConic;

@interface CAGradientLayer : CALayer
@property (copy) NSArray *colors;
@property (copy) NSArray<NSNumber *> *locations;
@property CGPoint startPoint;
@property CGPoint endPoint;
@property (copy) CAGradientLayerType type;
@end

/* A display link (freemac 1.232): calls its target once a frame, from a
 * timer on the run loops it is added to, at 60 frames a second; a Mac's
 * views, windows and screens make them (AppKit's displayLinkWithTarget:). */
typedef struct CAFrameRateRange {
    float minimum, maximum, preferred;
} CAFrameRateRange;
CA_EXTERN const CAFrameRateRange CAFrameRateRangeDefault;
CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred);
@interface CADisplayLink : NSObject
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel;
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@property (readonly) CFTimeInterval timestamp, duration, targetTimestamp;
@property (getter=isPaused) BOOL paused;
@property NSInteger preferredFramesPerSecond;
@property CAFrameRateRange preferredFrameRateRange;
@end

/* OpenGL layers (freemac 1.235) */
#import <QuartzCore/CAOpenGLLayer.h>

#endif /* __OBJC__ */

#endif
