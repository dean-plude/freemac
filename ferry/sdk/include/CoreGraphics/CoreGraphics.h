/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core Graphics (Quartz 2D) subset Ferry provides. Written for
 * freemac from Apple's public API documentation; not Apple's header. Every
 * CG object is also an Objective-C object, so CFRetain and CFRelease work on
 * them as they do on a Mac. */
#ifndef _FERRY_COREGRAPHICS_H_
#define _FERRY_COREGRAPHICS_H_
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

#define CG_EXTERN extern
#define CG_INLINE static inline

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

/* ---- colour spaces and colours ------------------------------------------------- */

typedef struct CGColorSpace *CGColorSpaceRef;
typedef struct CGColor *CGColorRef;
typedef enum {
    kCGColorSpaceModelUnknown = -1, kCGColorSpaceModelMonochrome, kCGColorSpaceModelRGB,
    kCGColorSpaceModelCMYK, kCGColorSpaceModelLab, kCGColorSpaceModelDeviceN, kCGColorSpaceModelIndexed,
    kCGColorSpaceModelPattern, kCGColorSpaceModelXYZ,
} CGColorSpaceModel;
typedef enum {
    kCGRenderingIntentDefault, kCGRenderingIntentAbsoluteColorimetric, kCGRenderingIntentRelativeColorimetric,
    kCGRenderingIntentPerceptual, kCGRenderingIntentSaturation,
} CGColorRenderingIntent;

extern const CFStringRef kCGColorSpaceSRGB;
extern const CFStringRef kCGColorSpaceGenericRGB;
extern const CFStringRef kCGColorSpaceGenericGray;
extern const CFStringRef kCGColorSpaceGenericGrayGamma2_2;
extern const CFStringRef kCGColorSpaceLinearSRGB;
extern const CFStringRef kCGColorSpaceExtendedSRGB;
extern const CFStringRef kCGColorSpaceDisplayP3;
extern const CFStringRef kCGColorSpaceGenericCMYK;
extern const CFStringRef kCGColorWhite;
extern const CFStringRef kCGColorBlack;
extern const CFStringRef kCGColorClear;

CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void);
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void);
CGColorSpaceRef CGColorSpaceCreateDeviceCMYK(void);
CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name);
CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef space);
void CGColorSpaceRelease(CGColorSpaceRef space);
size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef space);
CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef space);
CFStringRef CGColorSpaceGetName(CGColorSpaceRef space);
CFStringRef CGColorSpaceCopyName(CGColorSpaceRef space);
CFTypeID CGColorSpaceGetTypeID(void);

CGColorRef CGColorCreate(CGColorSpaceRef space, const CGFloat *components);
CGColorRef CGColorCreateGenericRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat alpha);
CGColorRef CGColorCreateGenericCMYK(CGFloat c, CGFloat m, CGFloat y, CGFloat k, CGFloat alpha);
CGColorRef CGColorCreateSRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
CGColorRef CGColorCreateCopy(CGColorRef color);
CGColorRef CGColorCreateCopyWithAlpha(CGColorRef color, CGFloat alpha);
CGColorRef CGColorGetConstantColor(CFStringRef name);
CGColorRef CGColorRetain(CGColorRef color);
void CGColorRelease(CGColorRef color);
bool CGColorEqualToColor(CGColorRef a, CGColorRef b);
size_t CGColorGetNumberOfComponents(CGColorRef color);
const CGFloat *CGColorGetComponents(CGColorRef color);
CGFloat CGColorGetAlpha(CGColorRef color);
CGColorSpaceRef CGColorGetColorSpace(CGColorRef color);
CFTypeID CGColorGetTypeID(void);

/* ---- paths ------------------------------------------------------------------- */

typedef const struct CGPath *CGPathRef;
typedef struct CGPath *CGMutablePathRef;
typedef enum {
    kCGPathElementMoveToPoint, kCGPathElementAddLineToPoint, kCGPathElementAddQuadCurveToPoint,
    kCGPathElementAddCurveToPoint, kCGPathElementCloseSubpath,
} CGPathElementType;
typedef struct CGPathElement { CGPathElementType type; CGPoint *points; } CGPathElement;
typedef void (*CGPathApplierFunction)(void *info, const CGPathElement *element);
typedef enum { kCGLineJoinMiter, kCGLineJoinRound, kCGLineJoinBevel } CGLineJoin;
typedef enum { kCGLineCapButt, kCGLineCapRound, kCGLineCapSquare } CGLineCap;

CGMutablePathRef CGPathCreateMutable(void);
CGPathRef CGPathCreateCopy(CGPathRef path);
CGPathRef CGPathCreateCopyByTransformingPath(CGPathRef path, const CGAffineTransform *m);
CGMutablePathRef CGPathCreateMutableCopy(CGPathRef path);
CGMutablePathRef CGPathCreateMutableCopyByTransformingPath(CGPathRef path, const CGAffineTransform *m);
CGPathRef CGPathCreateWithRect(CGRect rect, const CGAffineTransform *m);
CGPathRef CGPathCreateWithEllipseInRect(CGRect rect, const CGAffineTransform *m);
CGPathRef CGPathCreateWithRoundedRect(CGRect rect, CGFloat cornerWidth, CGFloat cornerHeight,
                                      const CGAffineTransform *m);
CGPathRef CGPathRetain(CGPathRef path);
void CGPathRelease(CGPathRef path);
bool CGPathEqualToPath(CGPathRef a, CGPathRef b);
void CGPathMoveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y);
void CGPathAddLineToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y);
void CGPathAddQuadCurveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat cpx, CGFloat cpy,
                               CGFloat x, CGFloat y);
void CGPathAddCurveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat cp1x, CGFloat cp1y,
                           CGFloat cp2x, CGFloat cp2y, CGFloat x, CGFloat y);
void CGPathCloseSubpath(CGMutablePathRef path);
void CGPathAddRect(CGMutablePathRef path, const CGAffineTransform *m, CGRect rect);
void CGPathAddRects(CGMutablePathRef path, const CGAffineTransform *m, const CGRect *rects, size_t count);
void CGPathAddLines(CGMutablePathRef path, const CGAffineTransform *m, const CGPoint *points, size_t count);
void CGPathAddEllipseInRect(CGMutablePathRef path, const CGAffineTransform *m, CGRect rect);
void CGPathAddRoundedRect(CGMutablePathRef path, const CGAffineTransform *m, CGRect rect, CGFloat cornerWidth,
                          CGFloat cornerHeight);
void CGPathAddRelativeArc(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y, CGFloat radius,
                          CGFloat startAngle, CGFloat delta);
void CGPathAddArc(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y, CGFloat radius,
                  CGFloat startAngle, CGFloat endAngle, bool clockwise);
void CGPathAddArcToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x1, CGFloat y1, CGFloat x2,
                         CGFloat y2, CGFloat radius);
void CGPathAddPath(CGMutablePathRef path1, const CGAffineTransform *m, CGPathRef path2);
bool CGPathIsEmpty(CGPathRef path);
bool CGPathIsRect(CGPathRef path, CGRect *rect);
CGPoint CGPathGetCurrentPoint(CGPathRef path);
CGRect CGPathGetBoundingBox(CGPathRef path);
CGRect CGPathGetPathBoundingBox(CGPathRef path);
bool CGPathContainsPoint(CGPathRef path, const CGAffineTransform *m, CGPoint point, bool eoFill);
void CGPathApply(CGPathRef path, void *info, CGPathApplierFunction function);
CFTypeID CGPathGetTypeID(void);

/* ---- data providers, images and gradients ------------------------------------- */

typedef struct CGDataProvider *CGDataProviderRef;
typedef struct CGImage *CGImageRef;
typedef struct CGGradient *CGGradientRef;
typedef void (*CGDataProviderReleaseDataCallback)(void *info, const void *data, size_t size);

typedef enum {
    kCGImageAlphaNone, kCGImageAlphaPremultipliedLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaLast,
    kCGImageAlphaFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaNoneSkipFirst, kCGImageAlphaOnly,
} CGImageAlphaInfo;
typedef enum {
    kCGBitmapAlphaInfoMask = 0x1F,
    kCGBitmapFloatInfoMask = 0xF00,
    kCGBitmapFloatComponents = (1 << 8),
    kCGBitmapByteOrderMask = 0x7000,
    kCGBitmapByteOrderDefault = (0 << 12),
    kCGBitmapByteOrder16Little = (1 << 12),
    kCGBitmapByteOrder32Little = (2 << 12),
    kCGBitmapByteOrder16Big = (3 << 12),
    kCGBitmapByteOrder32Big = (4 << 12),
} CGBitmapInfo;
#define kCGBitmapByteOrder32Host kCGBitmapByteOrder32Little
#define kCGBitmapByteOrder16Host kCGBitmapByteOrder16Little
typedef uint32_t CGImageByteOrderInfo;

CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size,
                                               CGDataProviderReleaseDataCallback releaseData);
CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data);
CGDataProviderRef CGDataProviderCreateWithFilename(const char *filename);
CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url);
CGDataProviderRef CGDataProviderRetain(CGDataProviderRef provider);
void CGDataProviderRelease(CGDataProviderRef provider);
CFDataRef CGDataProviderCopyData(CGDataProviderRef provider);

CGImageRef CGImageCreate(size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
                         size_t bytesPerRow, CGColorSpaceRef space, CGBitmapInfo bitmapInfo,
                         CGDataProviderRef provider, const CGFloat *decode, bool shouldInterpolate,
                         CGColorRenderingIntent intent);
CGImageRef CGImageCreateWithPNGDataProvider(CGDataProviderRef source, const CGFloat *decode, bool shouldInterpolate,
                                            CGColorRenderingIntent intent);
CGImageRef CGImageCreateWithImageInRect(CGImageRef image, CGRect rect);
CGImageRef CGImageCreateCopy(CGImageRef image);
CGImageRef CGImageRetain(CGImageRef image);
void CGImageRelease(CGImageRef image);
size_t CGImageGetWidth(CGImageRef image);
size_t CGImageGetHeight(CGImageRef image);
size_t CGImageGetBitsPerComponent(CGImageRef image);
size_t CGImageGetBitsPerPixel(CGImageRef image);
size_t CGImageGetBytesPerRow(CGImageRef image);
CGColorSpaceRef CGImageGetColorSpace(CGImageRef image);
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef image);
CGBitmapInfo CGImageGetBitmapInfo(CGImageRef image);
CGDataProviderRef CGImageGetDataProvider(CGImageRef image);
bool CGImageIsMask(CGImageRef image);
CFTypeID CGImageGetTypeID(void);

typedef enum {
    kCGGradientDrawsBeforeStartLocation = (1 << 0),
    kCGGradientDrawsAfterEndLocation = (1 << 1),
} CGGradientDrawingOptions;
CGGradientRef CGGradientCreateWithColorComponents(CGColorSpaceRef space, const CGFloat *components,
                                                  const CGFloat *locations, size_t count);
CGGradientRef CGGradientCreateWithColors(CGColorSpaceRef space, CFArrayRef colors, const CGFloat *locations);
CGGradientRef CGGradientRetain(CGGradientRef gradient);
void CGGradientRelease(CGGradientRef gradient);

/* ---- contexts ----------------------------------------------------------------- */

typedef struct CGContext *CGContextRef;
typedef enum { kCGPathFill, kCGPathEOFill, kCGPathStroke, kCGPathFillStroke, kCGPathEOFillStroke } CGPathDrawingMode;
typedef enum {
    kCGTextFill, kCGTextStroke, kCGTextFillStroke, kCGTextInvisible, kCGTextFillClip, kCGTextStrokeClip,
    kCGTextFillStrokeClip, kCGTextClip,
} CGTextDrawingMode;
typedef enum {
    kCGInterpolationDefault = 0, kCGInterpolationNone = 1, kCGInterpolationLow = 2, kCGInterpolationMedium = 4,
    kCGInterpolationHigh = 3,
} CGInterpolationQuality;
typedef enum {
    kCGBlendModeNormal, kCGBlendModeMultiply, kCGBlendModeScreen, kCGBlendModeOverlay, kCGBlendModeDarken,
    kCGBlendModeLighten, kCGBlendModeColorDodge, kCGBlendModeColorBurn, kCGBlendModeSoftLight,
    kCGBlendModeHardLight, kCGBlendModeDifference, kCGBlendModeExclusion, kCGBlendModeHue,
    kCGBlendModeSaturation, kCGBlendModeColor, kCGBlendModeLuminosity, kCGBlendModeClear, kCGBlendModeCopy,
    kCGBlendModeSourceIn, kCGBlendModeSourceOut, kCGBlendModeSourceAtop, kCGBlendModeDestinationOver,
    kCGBlendModeDestinationIn, kCGBlendModeDestinationOut, kCGBlendModeDestinationAtop, kCGBlendModeXOR,
    kCGBlendModePlusDarker, kCGBlendModePlusLighter,
} CGBlendMode;
typedef uint16_t CGGlyph;

CGContextRef CGBitmapContextCreate(void *data, size_t width, size_t height, size_t bitsPerComponent,
                                   size_t bytesPerRow, CGColorSpaceRef space, uint32_t bitmapInfo);
void *CGBitmapContextGetData(CGContextRef c);
size_t CGBitmapContextGetWidth(CGContextRef c);
size_t CGBitmapContextGetHeight(CGContextRef c);
size_t CGBitmapContextGetBitsPerComponent(CGContextRef c);
size_t CGBitmapContextGetBitsPerPixel(CGContextRef c);
size_t CGBitmapContextGetBytesPerRow(CGContextRef c);
CGColorSpaceRef CGBitmapContextGetColorSpace(CGContextRef c);
CGImageAlphaInfo CGBitmapContextGetAlphaInfo(CGContextRef c);
CGBitmapInfo CGBitmapContextGetBitmapInfo(CGContextRef c);
CGImageRef CGBitmapContextCreateImage(CGContextRef c);

CGContextRef CGContextRetain(CGContextRef c);
void CGContextRelease(CGContextRef c);
CFTypeID CGContextGetTypeID(void);
void CGContextFlush(CGContextRef c);
void CGContextSynchronize(CGContextRef c);

void CGContextSaveGState(CGContextRef c);
void CGContextRestoreGState(CGContextRef c);
void CGContextScaleCTM(CGContextRef c, CGFloat sx, CGFloat sy);
void CGContextTranslateCTM(CGContextRef c, CGFloat tx, CGFloat ty);
void CGContextRotateCTM(CGContextRef c, CGFloat angle);
void CGContextConcatCTM(CGContextRef c, CGAffineTransform transform);
CGAffineTransform CGContextGetCTM(CGContextRef c);
CGAffineTransform CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef c);
CGPoint CGContextConvertPointToDeviceSpace(CGContextRef c, CGPoint point);
CGPoint CGContextConvertPointToUserSpace(CGContextRef c, CGPoint point);
CGSize CGContextConvertSizeToDeviceSpace(CGContextRef c, CGSize size);
CGSize CGContextConvertSizeToUserSpace(CGContextRef c, CGSize size);
CGRect CGContextConvertRectToDeviceSpace(CGContextRef c, CGRect rect);
CGRect CGContextConvertRectToUserSpace(CGContextRef c, CGRect rect);

void CGContextSetLineWidth(CGContextRef c, CGFloat width);
void CGContextSetLineCap(CGContextRef c, CGLineCap cap);
void CGContextSetLineJoin(CGContextRef c, CGLineJoin join);
void CGContextSetMiterLimit(CGContextRef c, CGFloat limit);
void CGContextSetLineDash(CGContextRef c, CGFloat phase, const CGFloat *lengths, size_t count);
void CGContextSetFlatness(CGContextRef c, CGFloat flatness);
void CGContextSetAlpha(CGContextRef c, CGFloat alpha);
void CGContextSetBlendMode(CGContextRef c, CGBlendMode mode);
void CGContextSetShouldAntialias(CGContextRef c, bool shouldAntialias);
void CGContextSetAllowsAntialiasing(CGContextRef c, bool allowsAntialiasing);
void CGContextSetShouldSmoothFonts(CGContextRef c, bool shouldSmoothFonts);
void CGContextSetAllowsFontSmoothing(CGContextRef c, bool allows);
void CGContextSetShouldSubpixelPositionFonts(CGContextRef c, bool should);
void CGContextSetAllowsFontSubpixelPositioning(CGContextRef c, bool allows);
void CGContextSetInterpolationQuality(CGContextRef c, CGInterpolationQuality quality);
CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef c);
void CGContextSetShadow(CGContextRef c, CGSize offset, CGFloat blur);
void CGContextSetShadowWithColor(CGContextRef c, CGSize offset, CGFloat blur, CGColorRef color);

void CGContextBeginPath(CGContextRef c);
void CGContextMoveToPoint(CGContextRef c, CGFloat x, CGFloat y);
void CGContextAddLineToPoint(CGContextRef c, CGFloat x, CGFloat y);
void CGContextAddCurveToPoint(CGContextRef c, CGFloat cp1x, CGFloat cp1y, CGFloat cp2x, CGFloat cp2y, CGFloat x,
                              CGFloat y);
void CGContextAddQuadCurveToPoint(CGContextRef c, CGFloat cpx, CGFloat cpy, CGFloat x, CGFloat y);
void CGContextClosePath(CGContextRef c);
void CGContextAddRect(CGContextRef c, CGRect rect);
void CGContextAddRects(CGContextRef c, const CGRect *rects, size_t count);
void CGContextAddLines(CGContextRef c, const CGPoint *points, size_t count);
void CGContextAddEllipseInRect(CGContextRef c, CGRect rect);
void CGContextAddArc(CGContextRef c, CGFloat x, CGFloat y, CGFloat radius, CGFloat startAngle, CGFloat endAngle,
                     int clockwise);
void CGContextAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat radius);
void CGContextAddPath(CGContextRef c, CGPathRef path);
bool CGContextIsPathEmpty(CGContextRef c);
CGPoint CGContextGetPathCurrentPoint(CGContextRef c);
CGRect CGContextGetPathBoundingBox(CGContextRef c);
CGPathRef CGContextCopyPath(CGContextRef c);
bool CGContextPathContainsPoint(CGContextRef c, CGPoint point, CGPathDrawingMode mode);

void CGContextDrawPath(CGContextRef c, CGPathDrawingMode mode);
void CGContextFillPath(CGContextRef c);
void CGContextEOFillPath(CGContextRef c);
void CGContextStrokePath(CGContextRef c);
void CGContextFillRect(CGContextRef c, CGRect rect);
void CGContextFillRects(CGContextRef c, const CGRect *rects, size_t count);
void CGContextStrokeRect(CGContextRef c, CGRect rect);
void CGContextStrokeRectWithWidth(CGContextRef c, CGRect rect, CGFloat width);
void CGContextClearRect(CGContextRef c, CGRect rect);
void CGContextFillEllipseInRect(CGContextRef c, CGRect rect);
void CGContextStrokeEllipseInRect(CGContextRef c, CGRect rect);
void CGContextStrokeLineSegments(CGContextRef c, const CGPoint *points, size_t count);

void CGContextClip(CGContextRef c);
void CGContextEOClip(CGContextRef c);
void CGContextClipToRect(CGContextRef c, CGRect rect);
void CGContextClipToRects(CGContextRef c, const CGRect *rects, size_t count);
CGRect CGContextGetClipBoundingBox(CGContextRef c);

void CGContextSetFillColorWithColor(CGContextRef c, CGColorRef color);
void CGContextSetStrokeColorWithColor(CGContextRef c, CGColorRef color);
void CGContextSetFillColorSpace(CGContextRef c, CGColorSpaceRef space);
void CGContextSetStrokeColorSpace(CGContextRef c, CGColorSpaceRef space);
void CGContextSetFillColor(CGContextRef c, const CGFloat *components);
void CGContextSetStrokeColor(CGContextRef c, const CGFloat *components);
void CGContextSetGrayFillColor(CGContextRef c, CGFloat gray, CGFloat alpha);
void CGContextSetGrayStrokeColor(CGContextRef c, CGFloat gray, CGFloat alpha);
void CGContextSetRGBFillColor(CGContextRef c, CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
void CGContextSetRGBStrokeColor(CGContextRef c, CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
void CGContextSetCMYKFillColor(CGContextRef c, CGFloat cyan, CGFloat magenta, CGFloat yellow, CGFloat black,
                               CGFloat alpha);
void CGContextSetCMYKStrokeColor(CGContextRef c, CGFloat cyan, CGFloat magenta, CGFloat yellow, CGFloat black,
                                 CGFloat alpha);

void CGContextDrawImage(CGContextRef c, CGRect rect, CGImageRef image);
void CGContextDrawTiledImage(CGContextRef c, CGRect rect, CGImageRef image);
void CGContextDrawLinearGradient(CGContextRef c, CGGradientRef gradient, CGPoint startPoint, CGPoint endPoint,
                                 CGGradientDrawingOptions options);
void CGContextDrawRadialGradient(CGContextRef c, CGGradientRef gradient, CGPoint startCenter, CGFloat startRadius,
                                 CGPoint endCenter, CGFloat endRadius, CGGradientDrawingOptions options);

void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t);
CGAffineTransform CGContextGetTextMatrix(CGContextRef c);
void CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y);
CGPoint CGContextGetTextPosition(CGContextRef c);
void CGContextSetTextDrawingMode(CGContextRef c, CGTextDrawingMode mode);
void CGContextSetCharacterSpacing(CGContextRef c, CGFloat spacing);
void CGContextSetFontSize(CGContextRef c, CGFloat size);

__FERRY_END

#endif
