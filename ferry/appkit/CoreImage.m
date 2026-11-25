/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's small Core Image (freemac 1.225, Ferry 0.49.0), written for Ferry
 * from Apple's public API documentation: images that are Core Graphics
 * images with an extent, the CIAffineTransform filter, a QR code generator
 * that gives an empty image (no QR encoder is written yet), detectors that
 * find nothing, and AppKit's NSCIImageRep. MacPass's TOTP setup uses it. */
#import "AInternal.h"
#import <CoreImage/CoreImage.h>

NSString *const kCIInputImageKey = @"inputImage";
NSString *const kCIInputTransformKey = @"inputTransform";
NSString *const kCIOutputImageKey = @"outputImage";
NSString *const CIDetectorTypeQRCode = @"CIDetectorTypeQRCode";
NSString *const CIDetectorTypeFace = @"CIDetectorTypeFace";
NSString *const CIDetectorTypeRectangle = @"CIDetectorTypeRectangle";
NSString *const CIDetectorTypeText = @"CIDetectorTypeText";
NSString *const CIDetectorAccuracy = @"CIDetectorAccuracy";
NSString *const CIDetectorAccuracyLow = @"CIDetectorAccuracyLow";
NSString *const CIDetectorAccuracyHigh = @"CIDetectorAccuracyHigh";
NSString *const CIFeatureTypeQRCode = @"QRCode";
NSString *const CIFeatureTypeFace = @"Face";
NSString *const CIFeatureTypeRectangle = @"Rectangle";
NSString *const CIFeatureTypeText = @"Text";

/* ---- images ---------------------------------------------------------------------------- */

@implementation CIImage {
    CGImageRef _image;
    CGRect _extent;
}
+ (CIImage *)imageWithCGImage:(CGImageRef)image { return [[[self alloc] initWithCGImage:image] autorelease]; }
+ (CIImage *)emptyImage { return [[[self alloc] init] autorelease]; }
- (instancetype)initWithCGImage:(CGImageRef)image { return [self initWithCGImage:image options:nil]; }
- (instancetype)initWithCGImage:(CGImageRef)image options:(NSDictionary *)options
{
    if ((self = [super init])) {
        _image = image ? CGImageRetain(image) : NULL;
        _extent = image ? CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)) : CGRectZero;
    }
    return self;
}
- (instancetype)initWithData:(NSData *)data
{
    NSBitmapImageRep *rep = data ? [NSBitmapImageRep imageRepWithData:data] : nil;
    if (![rep CGImage]) {
        [self release];
        return nil;
    }
    return [self initWithCGImage:[rep CGImage]];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url
{
    return [self initWithData:[NSData dataWithContentsOfURL:url]];
}
- (instancetype)initWithBitmapImageRep:(NSBitmapImageRep *)rep
{
    if (![rep CGImage]) {
        [self release];
        return nil;
    }
    return [self initWithCGImage:[rep CGImage]];
}
- (void)dealloc
{
    if (_image)
        CGImageRelease(_image);
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (CGRect)extent { return _extent; }
- (CGImageRef)CGImage { return _image; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CIImage %p extent %gx%g>", self, _extent.size.width, _extent.size.height];
}

/* the pixels drawn through a transform into a bitmap that holds the result's bounds */
- (CIImage *)imageByApplyingTransform:(CGAffineTransform)m
{
    if (!_image)
        return self;
    CGRect to = CGRectIntegral(CGRectApplyAffineTransform(_extent, m));
    size_t w = (size_t)to.size.width, h = (size_t)to.size.height;
    if (!w || !h)
        return [CIImage emptyImage];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(NULL, w, h, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!cg)
        return [CIImage emptyImage];
    /* a scaled-up image keeps its pixels square: a QR code stays sharp */
    CGContextSetInterpolationQuality(cg, kCGInterpolationNone);
    CGContextTranslateCTM(cg, -to.origin.x, -to.origin.y);
    CGContextConcatCTM(cg, m);
    CGContextDrawImage(cg, _extent, _image);
    CGImageRef out = CGBitmapContextCreateImage(cg);
    CGContextRelease(cg);
    CIImage *result = [CIImage imageWithCGImage:out];
    CGImageRelease(out);
    return result;
}
- (CIImage *)imageByCroppingToRect:(CGRect)rect
{
    if (!_image)
        return self;
    CGRect r = CGRectIntegral(CGRectIntersection(rect, _extent));
    if (CGRectIsEmpty(r))
        return [CIImage emptyImage];
    /* the image's rows run top down */
    r.origin.y = _extent.size.height - CGRectGetMaxY(r);
    CGImageRef part = CGImageCreateWithImageInRect(_image, r);
    CIImage *result = [CIImage imageWithCGImage:part];
    CGImageRelease(part);
    return result;
}
@end

/* ---- filters --------------------------------------------------------------------------- */

static NSArray *filter_names(void) { return @[ @"CIAffineTransform", @"CIQRCodeGenerator" ]; }

@implementation CIFilter {
    NSString *_name;
    NSMutableDictionary *_inputs;
}
+ (CIFilter *)filterWithName:(NSString *)name { return [self filterWithName:name withInputParameters:nil]; }
+ (CIFilter *)filterWithName:(NSString *)name withInputParameters:(NSDictionary *)params
{
    if (![filter_names() containsObject:name])
        return nil;
    CIFilter *f = [[[self alloc] init] autorelease];
    f->_name = [name copy];
    f->_inputs = [[NSMutableDictionary alloc] init];
    [f setDefaults];
    if (params)
        [f->_inputs addEntriesFromDictionary:params];
    return f;
}
+ (NSArray *)filterNamesInCategory:(NSString *)category { return filter_names(); }
- (void)dealloc
{
    [_name release];
    [_inputs release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    return [[CIFilter filterWithName:_name withInputParameters:_inputs] retain];
}
- (NSString *)name { return _name; }
- (NSArray *)inputKeys
{
    return [_name isEqual:@"CIAffineTransform"] ? @[ kCIInputImageKey, kCIInputTransformKey ]
                                                : @[ @"inputMessage", @"inputCorrectionLevel" ];
}
- (void)setDefaults
{
    if ([_name isEqual:@"CIQRCodeGenerator"])
        _inputs[@"inputCorrectionLevel"] = @"M";
    else
        _inputs[kCIInputTransformKey] = [NSAffineTransform transform];
}
- (void)setValue:(id)value forKey:(NSString *)key
{
    if ([key hasPrefix:@"input"]) {
        if (value)
            _inputs[key] = value;
        else
            [_inputs removeObjectForKey:key];
    } else
        [super setValue:value forKey:key];
}
- (id)valueForKey:(NSString *)key
{
    if ([key isEqual:kCIOutputImageKey])
        return [self outputImage];
    if ([key hasPrefix:@"input"])
        return _inputs[key];
    return [super valueForKey:key];
}
- (CIImage *)outputImage
{
    if ([_name isEqual:@"CIQRCodeGenerator"])
        return [CIImage emptyImage]; /* no QR encoder yet */
    CIImage *image = _inputs[kCIInputImageKey];
    if (!image)
        return nil;
    id t = _inputs[kCIInputTransformKey];
    CGAffineTransform m = CGAffineTransformIdentity;
    if ([t isKindOfClass:[NSAffineTransform class]]) {
        NSAffineTransformStruct s = [(NSAffineTransform *)t transformStruct];
        m = CGAffineTransformMake(s.m11, s.m12, s.m21, s.m22, s.tX, s.tY);
    } else if ([t isKindOfClass:[NSValue class]] && !strcmp([t objCType], @encode(CGAffineTransform)))
        [t getValue:&m];
    return [image imageByApplyingTransform:m];
}
@end

@implementation CIContext
+ (CIContext *)context { return [[[self alloc] init] autorelease]; }
+ (CIContext *)contextWithOptions:(NSDictionary *)options { return [self context]; }
- (CGImageRef)createCGImage:(CIImage *)image fromRect:(CGRect)rect
{
    CGImageRef cg = [[image imageByCroppingToRect:rect] CGImage];
    return cg ? CGImageRetain(cg) : NULL;
}
@end

/* ---- detectors ------------------------------------------------------------------------- */

@implementation CIFeature
- (NSString *)type { return @""; }
- (CGRect)bounds { return CGRectZero; }
@end
@implementation CIQRCodeFeature
- (NSString *)type { return CIFeatureTypeQRCode; }
- (NSString *)messageString { return nil; }
- (CGPoint)topLeft { return CGPointZero; }
- (CGPoint)topRight { return CGPointZero; }
- (CGPoint)bottomLeft { return CGPointZero; }
- (CGPoint)bottomRight { return CGPointZero; }
@end

@implementation CIDetector
+ (CIDetector *)detectorOfType:(NSString *)type context:(CIContext *)context options:(NSDictionary *)options
{
    return type ? [[[self alloc] init] autorelease] : nil;
}
- (NSArray *)featuresInImage:(CIImage *)image { return @[]; }
- (NSArray *)featuresInImage:(CIImage *)image options:(NSDictionary *)options { return @[]; }
@end

/* ---- AppKit's image rep ---------------------------------------------------------------- */

@implementation NSCIImageRep {
    CIImage *_ciImage;
}
+ (instancetype)imageRepWithCIImage:(CIImage *)image { return [[[self alloc] initWithCIImage:image] autorelease]; }
- (instancetype)initWithCIImage:(CIImage *)image
{
    if (!(self = [super init]))
        return nil;
    _ciImage = [image retain];
    CGRect e = [image extent];
    [self setSize:NSMakeSize(e.size.width, e.size.height)];
    [self setPixelsWide:(NSInteger)e.size.width];
    [self setPixelsHigh:(NSInteger)e.size.height];
    return self;
}
- (void)dealloc
{
    [_ciImage release];
    [super dealloc];
}
- (CIImage *)CIImage { return _ciImage; }
- (BOOL)drawInRect:(NSRect)rect
{
    CGImageRef cg = [_ciImage CGImage];
    CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
    if (!cg || !c)
        return NO;
    CGContextSaveGState(c);
    CGContextSetInterpolationQuality(c, kCGInterpolationNone);
    CGContextDrawImage(c, NSRectToCGRect(rect), cg);
    CGContextRestoreGState(c);
    return YES;
}
- (CGImageRef)CGImageForProposedRect:(NSRect *)rect context:(NSGraphicsContext *)context hints:(NSDictionary *)hints
{
    return [_ciImage CGImage];
}
@end
