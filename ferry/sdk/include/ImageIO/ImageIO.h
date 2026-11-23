/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Image I/O: reading image files into Core Graphics images. Written
 * for Ferry from Apple's public API documentation; served from Ferry's Core
 * Graphics library. Writing image files (CGImageDestination) isn't here yet. */
#ifndef FERRY_IMAGEIO_H
#define FERRY_IMAGEIO_H
#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
#endif
