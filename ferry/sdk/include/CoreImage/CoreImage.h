/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: a small Core Image (freemac 1.225, Ferry 0.49.0), written for
 * Ferry from Apple's public API documentation and served from AppKit's
 * file (appkit/CoreImage.m). An image is a Core Graphics image with its
 * extent; of the filters only CIAffineTransform is made (any other name
 * gives no filter), and a detector finds nothing. So MacPass's QR codes
 * are neither drawn nor read. */
#ifndef FERRY_COREIMAGE_H
#define FERRY_COREIMAGE_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class NSBitmapImageRep, NSAffineTransform;

typedef NSString *CIImageOption NS_TYPED_ENUM;

@interface CIImage : NSObject <NSCopying>
+ (CIImage *)imageWithCGImage:(CGImageRef)image;
+ (CIImage *)emptyImage;
- (instancetype)initWithCGImage:(CGImageRef)image;
- (instancetype)initWithCGImage:(CGImageRef)image options:(nullable NSDictionary<CIImageOption, id> *)options;
- (nullable instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url;
/* the rectangle the image covers */
@property (readonly) CGRect extent;
/* the pixels, when the image has them (nil for the empty image) */
@property (nullable, readonly) CGImageRef CGImage;
/* scaled, rotated or moved by a transform: its pixels drawn into a new bitmap */
- (CIImage *)imageByApplyingTransform:(CGAffineTransform)matrix;
- (CIImage *)imageByCroppingToRect:(CGRect)rect;
@end

@interface CIImage (AppKitAdditions)
- (nullable instancetype)initWithBitmapImageRep:(NSBitmapImageRep *)bitmapImageRep;
@end

extern NSString *const kCIInputImageKey;
extern NSString *const kCIInputTransformKey;
extern NSString *const kCIOutputImageKey;

@interface CIFilter : NSObject <NSCopying>
/* a filter Ferry has (CIAffineTransform), or nil */
+ (nullable CIFilter *)filterWithName:(NSString *)name;
+ (nullable CIFilter *)filterWithName:(NSString *)name
                  withInputParameters:(nullable NSDictionary<NSString *, id> *)params;
+ (NSArray<NSString *> *)filterNamesInCategory:(nullable NSString *)category;
@property (readonly, copy) NSString *name;
@property (readonly, nullable) CIImage *outputImage;
@property (readonly, copy) NSArray<NSString *> *inputKeys;
- (void)setDefaults;
@end

@interface CIContext : NSObject
+ (CIContext *)context;
+ (CIContext *)contextWithOptions:(nullable NSDictionary<NSString *, id> *)options;
- (nullable CGImageRef)createCGImage:(CIImage *)image fromRect:(CGRect)fromRect CF_RETURNS_RETAINED;
@end

extern NSString *const CIDetectorTypeQRCode;
extern NSString *const CIDetectorTypeFace;
extern NSString *const CIDetectorTypeRectangle;
extern NSString *const CIDetectorTypeText;
extern NSString *const CIDetectorAccuracy;
extern NSString *const CIDetectorAccuracyLow;
extern NSString *const CIDetectorAccuracyHigh;
extern NSString *const CIFeatureTypeQRCode;
extern NSString *const CIFeatureTypeFace;
extern NSString *const CIFeatureTypeRectangle;
extern NSString *const CIFeatureTypeText;

@interface CIFeature : NSObject
@property (readonly, copy) NSString *type;
@property (readonly) CGRect bounds;
@end
@interface CIQRCodeFeature : CIFeature
@property (nullable, readonly, copy) NSString *messageString;
@property (readonly) CGPoint topLeft, topRight, bottomLeft, bottomRight;
@end

@interface CIDetector : NSObject
+ (nullable CIDetector *)detectorOfType:(NSString *)type context:(nullable CIContext *)context
                                options:(nullable NSDictionary<NSString *, id> *)options;
/* what was found: nothing, in Ferry */
- (NSArray<CIFeature *> *)featuresInImage:(CIImage *)image;
- (NSArray<CIFeature *> *)featuresInImage:(CIImage *)image options:(nullable NSDictionary<NSString *, id> *)options;
@end

NS_ASSUME_NONNULL_END
#endif
