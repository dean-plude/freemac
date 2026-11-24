/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation (QuartzCore): shared internals. Our own code,
 * written from Apple's public API documentation of QuartzCore; built as a
 * Mach-O library with ferry-cc. Layers keep their properties as objects in
 * a dictionary (a layer is a key-value coding container, as on a Mac), are
 * drawn with Ferry's Core Graphics, and are animated by a timer on the main
 * run loop (QAnimator.m), all on the main thread. Built without ARC. */
#ifndef FERRY_QUARTZCORE_INTERNAL_H
#define FERRY_QUARTZCORE_INTERNAL_H
#include "../graphics/GInternal.h"
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>

#define Q_EXPORT __attribute__((visibility("default")))

void QWarnOnce(const char *what);

/* ---- values (QValue.m) ----------------------------------------------------------- */

/* A property's value taken apart, so it can be interpolated: numbers,
 * points, sizes, rectangles, 3D transforms, colours (as sRGB), paths and
 * arrays of those. Anything else is only ever swapped, not blended. */
typedef enum {
    QV_NONE, QV_NUMBER, QV_POINT, QV_SIZE, QV_RECT, QV_TRANSFORM, QV_COLOR, QV_OTHER,
} QKind;
struct qval {
    QKind kind;
    double d[16];
};
QKind QValueRead(id value, struct qval *out);   /* QV_OTHER for what can't be blended */
id QValueMake(const struct qval *v);              /* autoreleased */
/* a + (b - a) * t; for transforms, the 2D parts (translation, rotation,
 * scale) are blended when both are 2D, else the matrices are. */
void QValueBlend(const struct qval *a, const struct qval *b, double t, struct qval *out);
void QValueAdd(const struct qval *a, const struct qval *b, struct qval *out);
void QValueSubtract(const struct qval *a, const struct qval *b, struct qval *out);
double QValueDistance(const struct qval *a, const struct qval *b);
/* Blends two values of any kind (arrays element by element, paths point by
 * point when they have the same shape); swaps at the end when they can't
 * be blended. */
id QBlend(id from, id to, double t);
id QAdd(id a, id b);
id QSubtract(id a, id b);
BOOL QValuesEqual(id a, id b);

/* Structure fields in key paths ("position.x", "bounds.size.width",
 * "transform.rotation.z", "transform.scale"): the field's value, and the
 * whole value with the field replaced. */
id QFieldGet(id whole, NSString *field);
id QFieldSet(id whole, NSString *field, id part);

/* The colour's components as sRGB, not premultiplied. */
void QColorRGBA(CGColorRef color, double rgba[4]);
BOOL QIsColor(id value);
BOOL QIsPath(id value);

/* A transform in an NSValue. */
@interface QTransformValue : NSValue {
@public
    CATransform3D t;
}
@end

/* ---- timing (CAMediaTimingFunction.m, CAAnimation.m) ------------------------------- */

double QTimingSolve(CAMediaTimingFunction *f, double x);   /* nil is linear */

/* An animation's own time, given its parent's: before (< 0), during, or
 * after its active span, and where in one cycle that falls. */
enum qphase { Q_BEFORE, Q_ACTIVE, Q_AFTER };
struct qtime {
    enum qphase phase;
    double progress;        /* 0..1 within the current cycle, before the timing function */
    double iteration;       /* completed cycles, for cumulative animations */
    BOOL applies;           /* whether the animation affects the value now (fill modes) */
};
void QTimingEvaluate(id<CAMediaTiming> timing, double parentTime, double defaultDuration, struct qtime *out);
double QAnimationActiveDuration(CAAnimation *a);

@interface CAAnimation (FerryPrivate)
/* The animation's value for its key path at its local time, given the
 * value beneath it; nil when it doesn't apply then. Groups apply each of
 * theirs (QApply). */
- (void)_ferryApplyAtTime:(double)parentTime to:(NSMutableDictionary *)values layer:(CALayer *)layer;
- (double)_ferryDefaultDuration;
@end

/* Applies an animation of a key path to a set of values (keyed by the
 * path's first key): the property animations' shared step. */
id QValueAtKeyPath(NSDictionary *values, NSString *keyPath, CALayer *layer);
void QSetValueAtKeyPath(NSMutableDictionary *values, NSString *keyPath, id value, CALayer *layer);

/* ---- transactions (CATransaction.m) ------------------------------------------------- */

/* A transaction that an animation can be counted against: its completion
 * block runs once it has been committed and every animation counted has
 * finished or been removed. */
@interface QTransaction : NSObject {
@public
    NSMutableDictionary *values;
    NSInteger pending;
    NSUInteger serial;
    BOOL committed, done, implicit;
}
@end
NSArray *QOpenTransactions(void);      /* innermost last; makes the implicit one if none */
void QTransactionRelease(NSArray *transactions);   /* one counted animation ended */
void QCommitImplicitTransaction(void);
/* Each transaction's number, so a layer can tell whether the one it was
 * made in has been committed yet (its properties aren't animated until
 * then, as a layer that has never been shown has nothing to animate from). */
NSUInteger QCurrentTransactionSerial(void);
BOOL QTransactionIsOpen(NSUInteger serial);

/* ---- the animation clock (QAnimator.m) ------------------------------------------------ */

/* One animation running on a layer, or a property driven on any object
 * (AppKit's animator proxies). */
@interface QRunning : NSObject {
@public
    CAAnimation *animation;    /* the copy added */
    NSString *key;             /* nil when added without one */
    CALayer *layer;            /* not retained: the layer removes its own */
    id target;                 /* a driven object, retained */
    NSString *targetKey;
    id targetFrom, targetTo;
    NSArray *transactions;     /* counted against */
    BOOL started, stopped;
}
@end
void QAnimatorAdd(QRunning *r);       /* starts the clock */
void QAnimatorRemove(QRunning *r, BOOL finished);
void QAnimatorTick(void);
double QNow(void);
BOOL QClockIsManual(void);

/* For AppKit's animator proxies: sets target's key from `from` to `to`
 * over the animation's time, through setValue:forKey:, and to `to` at the
 * end. A newer one for the same object and key replaces it. */
Q_EXPORT void FerryCADriveValue(id target, NSString *key, id from, id to, CAAnimation *animation);
/* The test hook: the clock stands at `now` and moves only when told to,
 * and each move steps the animations at once. */
Q_EXPORT void FerryCASetManualClock(CFTimeInterval now);
Q_EXPORT void FerryCAAdvanceTime(CFTimeInterval seconds);

/* ---- layers (CALayer.m) --------------------------------------------------------------- */

@interface CALayer (FerryPrivate)
- (NSDictionary *)_ferryValues;                 /* the model's, with the class's defaults */
- (id)_ferryValueForKey:(NSString *)key;       /* the model's, or the default */
- (void)_ferrySetValue:(id)value forKey:(NSString *)key;   /* with actions */
- (NSDictionary *)_ferryPresentationValues;     /* model values with animations applied */
- (NSArray *)_ferryRunning;
- (void)_ferryAnimationEnded:(QRunning *)r;
- (void)_ferryChanged;                          /* tells the host something is to be drawn again */
+ (NSSet *)_ferryAnimatableKeys;
+ (NSSet *)_ferryKnownKeys;
/* Draws the layer's own content (contents, or a kind's drawing) in its
 * bounds space, the right way up when the space is flipped. */
- (void)_ferryDrawContentWithValues:(NSDictionary *)v inContext:(CGContextRef)ctx flipped:(BOOL)flipped;
- (NSArray *)_ferrySublayers;                    /* the model's own array, not copied */
- (void)_ferryMarkRendered;                      /* drawn once: its changes animate from now on */
- (void)_ferrySetHost:(id)host;
- (id)_ferryHost;
- (BOOL)_ferryIsPresentation;
@end

/* Layers' hosts (AppKit's views): told when the tree is to be drawn again. */
@interface NSObject (FerryLayerHost)
- (void)_ferryLayerTreeChanged;
@end

/* From a layer's bounds space to its superlayer's, with the given values. */
CGAffineTransform QLayerToSuperlayer(NSDictionary *v, CALayer *layer);
/* Draws a layer tree in the layer's own bounds space: with presentation
 * values when presentation is YES, flipped telling whether that space is
 * already y-down on the page; content, when given, stands for the layer's
 * own content and is drawn where it would be (AppKit draws a view there). */
Q_EXPORT void FerryCALayerRender(CALayer *layer, CGContextRef ctx, BOOL presentation, BOOL flipped,
                                 void (^content)(CGContextRef ctx));
/* The placement of a root layer, as its values place it, relative to where
 * its model's position and bounds alone (without its transform) would:
 * AppKit adds it to a layer-backed view's own placement. */
Q_EXPORT CGAffineTransform FerryCALayerPresentationOffset(CALayer *layer);
/* Whether any animation is running on the layer or under it. */
Q_EXPORT BOOL FerryCALayerTreeIsAnimating(CALayer *layer);
Q_EXPORT void FerryCALayerSetHost(CALayer *layer, id host);

/* values from a dictionary, with defaults */
CGFloat QNum(NSDictionary *v, NSString *key);
CGPoint QPoint(NSDictionary *v, NSString *key);
CGSize QSize(NSDictionary *v, NSString *key);
CGRect QRect(NSDictionary *v, NSString *key);
CATransform3D QTransform(NSDictionary *v, NSString *key);
BOOL QBool(NSDictionary *v, NSString *key);
id QObj(NSDictionary *v, NSString *key);
CGColorRef QColor(NSDictionary *v, NSString *key);
CGAffineTransform QAffine2D(CATransform3D t);   /* the transform as drawn on the page */

/* shared by the layer kinds: paths, pieces of a path between two fractions
 * of its length (CAShapeLayer.m) */
CGPathRef QPathPiece(CGPathRef path, double start, double end);   /* retained */

#endif
