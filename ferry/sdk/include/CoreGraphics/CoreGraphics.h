/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core Graphics (Quartz 2D) subset Ferry provides. Written for
 * freemac from Apple's public API documentation; not Apple's header. Every
 * CG object is also an Objective-C object, so CFRetain and CFRelease work on
 * them as they do on a Mac. */
#ifndef _FERRY_COREGRAPHICS_H_
#define _FERRY_COREGRAPHICS_H_
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

#include <CoreGraphics/CGGeometry.h>

__FERRY_BEGIN

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

typedef CF_ENUM(uint32_t, CGImageAlphaInfo) {
    kCGImageAlphaNone, kCGImageAlphaPremultipliedLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaLast,
    kCGImageAlphaFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaNoneSkipFirst, kCGImageAlphaOnly,
};
typedef CF_ENUM(uint32_t, CGImageByteOrderInfo) {
    kCGImageByteOrderMask = 0x7000,
    kCGImageByteOrderDefault = (0 << 12),
    kCGImageByteOrder16Little = (1 << 12),
    kCGImageByteOrder32Little = (2 << 12),
    kCGImageByteOrder16Big = (3 << 12),
    kCGImageByteOrder32Big = (4 << 12),
};
typedef CF_ENUM(uint32_t, CGImagePixelFormatInfo) {
    kCGImagePixelFormatMask = 0xF0000,
    kCGImagePixelFormatPacked = (0 << 16),
    kCGImagePixelFormatRGB555 = (1 << 16),
    kCGImagePixelFormatRGB565 = (2 << 16),
    kCGImagePixelFormatRGB101010 = (3 << 16),
    kCGImagePixelFormatRGBCIF10 = (4 << 16),
};
typedef CF_OPTIONS(uint32_t, CGBitmapInfo) {
    kCGBitmapAlphaInfoMask = 0x1F,
    kCGBitmapFloatInfoMask = 0xF00,
    kCGBitmapFloatComponents = (1 << 8),
    kCGBitmapByteOrderMask = kCGImageByteOrderMask,
    kCGBitmapByteOrderDefault = kCGImageByteOrderDefault,
    kCGBitmapByteOrder16Little = kCGImageByteOrder16Little,
    kCGBitmapByteOrder32Little = kCGImageByteOrder32Little,
    kCGBitmapByteOrder16Big = kCGImageByteOrder16Big,
    kCGBitmapByteOrder32Big = kCGImageByteOrder32Big,
};
#define kCGBitmapByteOrder32Host kCGBitmapByteOrder32Little
#define kCGBitmapByteOrder16Host kCGBitmapByteOrder16Little

CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size,
                                               CGDataProviderReleaseDataCallback releaseData);
CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data);
CGDataProviderRef CGDataProviderCreateWithFilename(const char *filename);
CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url);
CGDataProviderRef CGDataProviderRetain(CGDataProviderRef provider);
void CGDataProviderRelease(CGDataProviderRef provider);
CFDataRef CGDataProviderCopyData(CGDataProviderRef provider);
/* An ICC profile's space: Ferry draws RGB data in sRGB (grey and CMYK in its
 * own spaces), and a space has no profile to give back. */
CGColorSpaceRef CGColorSpaceCreateWithICCData(CFTypeRef data);
CGColorSpaceRef CGColorSpaceCreateICCBased(size_t nComponents, const CGFloat *range, CGDataProviderRef profile,
                                           CGColorSpaceRef alternate);
CFDataRef CGColorSpaceCopyICCData(CGColorSpaceRef space);

/* ---- fonts as Core Graphics sees them (a font file's data, or a Core Text font's) ---- */

typedef struct CGFont *CGFontRef;
CGFontRef CGFontCreateWithDataProvider(CGDataProviderRef provider);
CGFontRef CGFontCreateWithFontName(CFStringRef name);
CGFontRef CGFontRetain(CGFontRef font);
void CGFontRelease(CGFontRef font);
CFStringRef CGFontCopyFullName(CGFontRef font);
CFStringRef CGFontCopyPostScriptName(CGFontRef font);
int CGFontGetUnitsPerEm(CGFontRef font);
size_t CGFontGetNumberOfGlyphs(CGFontRef font);
CFDataRef CGFontCopyTableForTag(CGFontRef font, uint32_t tag);
CFTypeID CGFontGetTypeID(void);

CGImageRef CGImageCreate(size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
                         size_t bytesPerRow, CGColorSpaceRef space, CGBitmapInfo bitmapInfo,
                         CGDataProviderRef provider, const CGFloat *decode, bool shouldInterpolate,
                         CGColorRenderingIntent intent);
CGImageRef CGImageCreateWithPNGDataProvider(CGDataProviderRef source, const CGFloat *decode, bool shouldInterpolate,
                                            CGColorRenderingIntent intent);
CGImageRef CGImageCreateWithJPEGDataProvider(CGDataProviderRef source, const CGFloat *decode, bool shouldInterpolate,
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

/* Functions and shadings (freemac 1.221, Ferry 0.45.0): a shading's colours
 * come from the program's function, which Ferry asks at 256 points along the
 * shading and draws as a gradient through them. */
typedef struct CGFunction *CGFunctionRef;
typedef void (*CGFunctionEvaluateCallback)(void *info, const CGFloat *in, CGFloat *out);
typedef void (*CGFunctionReleaseInfoCallback)(void *info);
typedef struct CGFunctionCallbacks {
    unsigned int version;
    CGFunctionEvaluateCallback evaluate;
    CGFunctionReleaseInfoCallback releaseInfo;
} CGFunctionCallbacks;
CGFunctionRef CGFunctionCreate(void *info, size_t domainDimension, const CGFloat *domain, size_t rangeDimension,
                               const CGFloat *range, const CGFunctionCallbacks *callbacks);
CGFunctionRef CGFunctionRetain(CGFunctionRef function);
void CGFunctionRelease(CGFunctionRef function);
typedef struct CGShading *CGShadingRef;
CGShadingRef CGShadingCreateAxial(CGColorSpaceRef space, CGPoint start, CGPoint end, CGFunctionRef function,
                                  bool extendStart, bool extendEnd);
CGShadingRef CGShadingCreateRadial(CGColorSpaceRef space, CGPoint start, CGFloat startRadius, CGPoint end,
                                   CGFloat endRadius, CGFunctionRef function, bool extendStart, bool extendEnd);
CGShadingRef CGShadingRetain(CGShadingRef shading);
void CGShadingRelease(CGShadingRef shading);

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
void CGContextBeginTransparencyLayer(CGContextRef c, CFDictionaryRef auxiliaryInfo);
void CGContextBeginTransparencyLayerWithRect(CGContextRef c, CGRect rect, CFDictionaryRef auxiliaryInfo);
void CGContextEndTransparencyLayer(CGContextRef c);

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

/* ---- PDF documents (drawn by this system's Poppler) ------------------------------ */

typedef struct CGPDFDocument *CGPDFDocumentRef;
typedef struct CGPDFPage *CGPDFPageRef;
typedef enum { kCGPDFMediaBox = 0, kCGPDFCropBox = 1, kCGPDFBleedBox = 2, kCGPDFTrimBox = 3, kCGPDFArtBox = 4 } CGPDFBox;
CGPDFDocumentRef CGPDFDocumentCreateWithProvider(CGDataProviderRef provider);
CGPDFDocumentRef CGPDFDocumentCreateWithURL(CFURLRef url);
CGPDFDocumentRef CGPDFDocumentRetain(CGPDFDocumentRef document);
void CGPDFDocumentRelease(CGPDFDocumentRef document);
CFTypeID CGPDFDocumentGetTypeID(void);
size_t CGPDFDocumentGetNumberOfPages(CGPDFDocumentRef document);
CGPDFPageRef CGPDFDocumentGetPage(CGPDFDocumentRef document, size_t pageNumber);
bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef document);
bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef document);
bool CGPDFDocumentAllowsPrinting(CGPDFDocumentRef document);
bool CGPDFDocumentAllowsCopying(CGPDFDocumentRef document);
CGPDFPageRef CGPDFPageRetain(CGPDFPageRef page);
void CGPDFPageRelease(CGPDFPageRef page);
CFTypeID CGPDFPageGetTypeID(void);
size_t CGPDFPageGetPageNumber(CGPDFPageRef page);
int CGPDFPageGetRotationAngle(CGPDFPageRef page);
CGRect CGPDFPageGetBoxRect(CGPDFPageRef page, CGPDFBox box);
CGAffineTransform CGPDFPageGetDrawingTransform(CGPDFPageRef page, CGPDFBox box, CGRect rect, int rotate,
                                               bool preserveAspectRatio);
void CGContextDrawPDFPage(CGContextRef c, CGPDFPageRef page);
void CGContextDrawLinearGradient(CGContextRef c, CGGradientRef gradient, CGPoint startPoint, CGPoint endPoint,
                                 CGGradientDrawingOptions options);
void CGContextDrawShading(CGContextRef c, CGShadingRef shading);
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

/* Quartz Event Services and Window Services (freemac 1.220, Ferry 0.44.0),
 * served from AppKit's file. */
#include <CoreGraphics/CGEvent.h>
#include <CoreGraphics/CGWindow.h>
#include <CoreGraphics/CGDirectDisplay.h>

#endif
