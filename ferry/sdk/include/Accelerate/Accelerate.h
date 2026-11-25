/* SPDX-License-Identifier: GPL-3.0-or-later
 * Accelerate: vImage's types, from Apple's public documentation, for the
 * programs (Qt) that describe pictures with them, and the few vImage calls
 * media/Accelerate.c makes. */
#ifndef FERRY_ACCELERATE_H
#define FERRY_ACCELERATE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stddef.h>

typedef unsigned long vImagePixelCount;
typedef ssize_t vImage_Error;
typedef uint32_t vImage_Flags;

typedef struct vImage_Buffer {
    void *data;
    vImagePixelCount height;
    vImagePixelCount width;
    size_t rowBytes;
} vImage_Buffer;

typedef struct vImage_CGImageFormat {
    uint32_t bitsPerComponent;
    uint32_t bitsPerPixel;
    CGColorSpaceRef colorSpace;
    CGBitmapInfo bitmapInfo;
    uint32_t version;
    const CGFloat *decode;
    CGColorRenderingIntent renderingIntent;
} vImage_CGImageFormat;

enum {
    kvImageNoError = 0,
    kvImageRoiLargerThanInputBuffer = -21766,
    kvImageInvalidKernelSize = -21767,
    kvImageInvalidEdgeStyle = -21768,
    kvImageInvalidOffset_X = -21769,
    kvImageInvalidOffset_Y = -21770,
    kvImageMemoryAllocationError = -21771,
    kvImageNullPointerArgument = -21772,
    kvImageInvalidParameter = -21773,
    kvImageBufferSizeMismatch = -21774,
    kvImageUnknownFlagsBit = -21775,
    kvImageInternalError = -21776,
    kvImageInvalidRowBytes = -21777,
    kvImageInvalidImageFormat = -21778,
    kvImageColorSyncIsAbsent = -21779,
    kvImageOutOfPlaceOperationRequired = -21780,
    kvImageInvalidImageObject = -21781,
    kvImageInvalidCVImageFormat = -21782,
    kvImageUnsupportedConversion = -21783,
    kvImageCoreVideoIsAbsent = -21784,
};
enum {
    kvImageNoFlags = 0,
    kvImageLeaveAlphaUnchanged = 1,
    kvImageCopyInPlace = 2,
    kvImageBackgroundColorFill = 4,
    kvImageEdgeExtend = 8,
    kvImageDoNotTile = 16,
    kvImageHighQualityResampling = 32,
    kvImageTruncateKernel = 64,
    kvImageGetTempBufferSize = 128,
    kvImagePrintDiagnosticsToConsole = 256,
    kvImageNoAllocate = 512,
};

vImage_Error vImageBuffer_Init(vImage_Buffer *buf, vImagePixelCount height, vImagePixelCount width,
                               uint32_t pixelBits, vImage_Flags flags);
vImage_Error vImageBuffer_InitWithCGImage(vImage_Buffer *buf, vImage_CGImageFormat *format,
                                          const CGFloat *backgroundColor, CGImageRef image, vImage_Flags flags);
CGImageRef vImageCreateCGImageFromBuffer(const vImage_Buffer *buf, const vImage_CGImageFormat *format,
                                         void (*callback)(void *userData, void *buf_data), void *userData,
                                         vImage_Flags flags, vImage_Error *error);
vImage_Error vImageCopyBuffer(const vImage_Buffer *src, const vImage_Buffer *dest, size_t pixelSize, vImage_Flags flags);

#endif
