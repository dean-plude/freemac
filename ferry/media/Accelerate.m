/* SPDX-License-Identifier: GPL-3.0-or-later
 * Accelerate.framework for Ferry (freemac 1.232): vImage's buffers, from
 * Apple's public documentation, drawn with Ferry's Core Graphics. Only the
 * calls in Accelerate/Accelerate.h are here. */
#import <Foundation/Foundation.h>
#include <Accelerate/Accelerate.h>
#include <stdlib.h>
#include <string.h>

vImage_Error vImageBuffer_Init(vImage_Buffer *buf, vImagePixelCount height, vImagePixelCount width,
                               uint32_t pixelBits, vImage_Flags flags)
{
    if (!buf || !pixelBits)
        return kvImageNullPointerArgument;
    size_t row = ((width * pixelBits + 7) / 8 + 63) / 64 * 64;
    if (flags & kvImageNoAllocate) {
        buf->height = height;
        buf->width = width;
        buf->rowBytes = row;
        return (vImage_Error)(row * height);
    }
    void *data = NULL;
    if (posix_memalign(&data, 64, row * height ? row * height : 64))
        return kvImageMemoryAllocationError;
    buf->data = data;
    buf->height = height;
    buf->width = width;
    buf->rowBytes = row;
    return kvImageNoError;
}

vImage_Error vImageCopyBuffer(const vImage_Buffer *src, const vImage_Buffer *dest, size_t pixelSize, vImage_Flags flags)
{
    if (!src || !dest || !src->data || !dest->data)
        return kvImageNullPointerArgument;
    if (src->width != dest->width || src->height != dest->height)
        return kvImageBufferSizeMismatch;
    size_t bytes = src->width * pixelSize;
    for (vImagePixelCount y = 0; y < src->height; y++)
        memmove((char *)dest->data + y * dest->rowBytes, (const char *)src->data + y * src->rowBytes, bytes);
    return kvImageNoError;
}

static CGColorSpaceRef space_of(const vImage_CGImageFormat *f)
{
    return f->colorSpace ? CGColorSpaceRetain(f->colorSpace) : CGColorSpaceCreateDeviceRGB();
}

vImage_Error vImageBuffer_InitWithCGImage(vImage_Buffer *buf, vImage_CGImageFormat *format,
                                          const CGFloat *backgroundColor, CGImageRef image, vImage_Flags flags)
{
    if (!buf || !format || !image)
        return kvImageNullPointerArgument;
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    if (!(flags & kvImageNoAllocate)) {
        vImage_Error e = vImageBuffer_Init(buf, h, w, format->bitsPerPixel, flags);
        if (e != kvImageNoError)
            return e;
    } else if (!buf->data) {
        return kvImageNullPointerArgument;
    }
    CGColorSpaceRef space = space_of(format);
    CGContextRef c = CGBitmapContextCreate(buf->data, buf->width, buf->height, format->bitsPerComponent,
                                           buf->rowBytes, space, format->bitmapInfo);
    CGColorSpaceRelease(space);
    if (!c)
        return kvImageInvalidImageFormat;
    if (flags & kvImageBackgroundColorFill && backgroundColor) {
        CGContextSetRGBFillColor(c, backgroundColor[0], backgroundColor[1], backgroundColor[2], 1);
        CGContextFillRect(c, CGRectMake(0, 0, buf->width, buf->height));
    } else {
        CGContextClearRect(c, CGRectMake(0, 0, buf->width, buf->height));
    }
    CGContextDrawImage(c, CGRectMake(0, 0, buf->width, buf->height), image);
    CGContextRelease(c);
    return kvImageNoError;
}

CGImageRef vImageCreateCGImageFromBuffer(const vImage_Buffer *buf, const vImage_CGImageFormat *format,
                                         void (*callback)(void *userData, void *buf_data), void *userData,
                                         vImage_Flags flags, vImage_Error *error)
{
    if (!buf || !format || !buf->data) {
        if (error) *error = kvImageNullPointerArgument;
        return NULL;
    }
    CGColorSpaceRef space = space_of(format);
    CGContextRef c = CGBitmapContextCreate(buf->data, buf->width, buf->height, format->bitsPerComponent,
                                           buf->rowBytes, space, format->bitmapInfo);
    CGColorSpaceRelease(space);
    CGImageRef image = c ? CGBitmapContextCreateImage(c) : NULL;
    if (c)
        CGContextRelease(c);
    if (error) *error = image ? kvImageNoError : kvImageInvalidImageFormat;
    /* the picture holds its own copy, so the buffer is the caller's again */
    if (image && callback)
        callback(userData, buf->data);
    return image;
}
