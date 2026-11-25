/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Image I/O: reading image files into Core Graphics images. Written
 * for Ferry from Apple's public API documentation; served from Ferry's Core
 * Graphics library. Image files are written by CGImageDestination
 * (freemac 1.225): PNG, JPEG, TIFF and BMP, one image to a file. */
#ifndef FERRY_IMAGEIO_H
#define FERRY_IMAGEIO_H
#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif
/* audited for ARC, as on a Mac: an object passes as a CF argument without __bridge */
CF_IMPLICIT_BRIDGING_ENABLED

typedef struct CGImageSource *CGImageSourceRef;
typedef enum {
    kCGImageStatusUnexpectedEOF = -5, kCGImageStatusInvalidData = -4, kCGImageStatusUnknownType = -3,
    kCGImageStatusReadingHeader = -2, kCGImageStatusIncomplete = -1, kCGImageStatusComplete = 0,
} CGImageSourceStatus;

extern const CFStringRef kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyHasAlpha;
extern const CFStringRef kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight;
extern const CFStringRef kCGImageSourceShouldCache, kCGImageSourceShouldAllowFloat,
    kCGImageSourceTypeIdentifierHint;
extern const CFStringRef kCGImageSourceCreateThumbnailFromImageAlways,
    kCGImageSourceCreateThumbnailFromImageIfAbsent, kCGImageSourceThumbnailMaxPixelSize,
    kCGImageSourceCreateThumbnailWithTransform;

typedef struct CGImageDestination *CGImageDestinationRef;
extern const CFStringRef kCGImageDestinationLossyCompressionQuality, kCGImageDestinationBackgroundColor;
CFTypeID CGImageDestinationGetTypeID(void);
CFArrayRef CGImageDestinationCopyTypeIdentifiers(void);
CGImageDestinationRef CGImageDestinationCreateWithData(CFMutableDataRef data, CFStringRef type, size_t count,
                                                       CFDictionaryRef options);
CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef type, size_t count,
                                                      CFDictionaryRef options);
void CGImageDestinationSetProperties(CGImageDestinationRef idst, CFDictionaryRef properties);
void CGImageDestinationAddImage(CGImageDestinationRef idst, CGImageRef image, CFDictionaryRef properties);
void CGImageDestinationAddImageFromSource(CGImageDestinationRef idst, CGImageSourceRef isrc, size_t index,
                                          CFDictionaryRef properties);
bool CGImageDestinationFinalize(CGImageDestinationRef idst);

CFTypeID CGImageSourceGetTypeID(void);
CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options);
CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef provider, CFDictionaryRef options);
CGImageSourceRef CGImageSourceCreateWithURL(CFURLRef url, CFDictionaryRef options);
CFStringRef CGImageSourceGetType(CGImageSourceRef source);
size_t CGImageSourceGetCount(CGImageSourceRef source);
CGImageSourceStatus CGImageSourceGetStatus(CGImageSourceRef source);
CGImageSourceStatus CGImageSourceGetStatusAtIndex(CGImageSourceRef source, size_t index);
CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options);
CGImageRef CGImageSourceCreateThumbnailAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options);
CFDictionaryRef CGImageSourceCopyProperties(CGImageSourceRef source, CFDictionaryRef options);
CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options);

CF_IMPLICIT_BRIDGING_DISABLED
#ifdef __cplusplus
}
#endif
#endif
