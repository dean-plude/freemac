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

/* ---- vDSP (freemac 1.265, Ferry 0.88.0; first seen in Obsidian, whose
 * Chromium uses it for audio). From Apple's public documentation of each
 * call: strides count elements, and vDSP_vsub's first vector is the one
 * subtracted. The real FFT keeps vDSP's packing and scaling: forward, the
 * spectrum comes out doubled, the DC term in realp[0] and the Nyquist term
 * in imagp[0]; inverse undoes the packing without dividing, so a forward
 * then inverse pass gives back 2N times the input, as on a Mac. */
#include <math.h>

void vDSP_vadd(const float *A, vDSP_Stride IA, const float *B, vDSP_Stride IB, float *C, vDSP_Stride IC, vDSP_Length N)
{
    for (vDSP_Length n = 0; n < N; n++)
        C[n * IC] = A[n * IA] + B[n * IB];
}

void vDSP_vsub(const float *B, vDSP_Stride IB, const float *A, vDSP_Stride IA, float *C, vDSP_Stride IC, vDSP_Length N)
{
    for (vDSP_Length n = 0; n < N; n++)
        C[n * IC] = A[n * IA] - B[n * IB];
}

void vDSP_vmul(const float *A, vDSP_Stride IA, const float *B, vDSP_Stride IB, float *C, vDSP_Stride IC, vDSP_Length N)
{
    for (vDSP_Length n = 0; n < N; n++)
        C[n * IC] = A[n * IA] * B[n * IB];
}

void vDSP_vsmul(const float *A, vDSP_Stride IA, const float *B, float *C, vDSP_Stride IC, vDSP_Length N)
{
    float b = *B;
    for (vDSP_Length n = 0; n < N; n++)
        C[n * IC] = A[n * IA] * b;
}

void vDSP_vsadd(const float *A, vDSP_Stride IA, const float *B, float *C, vDSP_Stride IC, vDSP_Length N)
{
    float b = *B;
    for (vDSP_Length n = 0; n < N; n++)
        C[n * IC] = A[n * IA] + b;
}

void vDSP_vsma(const float *A, vDSP_Stride IA, const float *B, const float *C, vDSP_Stride IC, float *D,
               vDSP_Stride ID, vDSP_Length N)
{
    float b = *B;
    for (vDSP_Length n = 0; n < N; n++)
        D[n * ID] = A[n * IA] * b + C[n * IC];
}

void vDSP_vclip(const float *A, vDSP_Stride IA, const float *B, const float *C, float *D, vDSP_Stride ID, vDSP_Length N)
{
    float lo = *B, hi = *C;
    for (vDSP_Length n = 0; n < N; n++) {
        float v = A[n * IA];
        D[n * ID] = v < lo ? lo : v > hi ? hi : v;
    }
}

void vDSP_maxmgv(const float *A, vDSP_Stride IA, float *C, vDSP_Length N)
{
    float m = 0;
    for (vDSP_Length n = 0; n < N; n++)
        if (fabsf(A[n * IA]) > m)
            m = fabsf(A[n * IA]);
    *C = m;
}

void vDSP_svesq(const float *A, vDSP_Stride IA, float *C, vDSP_Length N)
{
    float s = 0;
    for (vDSP_Length n = 0; n < N; n++)
        s += A[n * IA] * A[n * IA];
    *C = s;
}

/* correlation with a positive filter stride; convolution when F points at the
 * filter's last element and IF is negative */
void vDSP_conv(const float *A, vDSP_Stride IA, const float *F, vDSP_Stride IF, float *C, vDSP_Stride IC,
               vDSP_Length N, vDSP_Length P)
{
    for (vDSP_Length n = 0; n < N; n++) {
        float s = 0;
        for (vDSP_Length p = 0; p < P; p++)
            s += A[(n + p) * IA] * F[(vDSP_Stride)p * IF];
        C[n * IC] = s;
    }
}

/* a two-pole, two-zero filter: C holds N + 2 values, the first two given */
void vDSP_deq22D(const double *A, vDSP_Stride IA, const double *B, double *C, vDSP_Stride IC, vDSP_Length N)
{
    for (vDSP_Length n = 2; n < N + 2; n++)
        C[n * IC] = A[n * IA] * B[0] + A[(n - 1) * IA] * B[1] + A[(n - 2) * IA] * B[2] - C[(n - 1) * IC] * B[3] -
                    C[(n - 2) * IC] * B[4];
}

void vDSP_deq22(const float *A, vDSP_Stride IA, const float *B, float *C, vDSP_Stride IC, vDSP_Length N)
{
    for (vDSP_Length n = 2; n < N + 2; n++)
        C[n * IC] = A[n * IA] * B[0] + A[(n - 1) * IA] * B[1] + A[(n - 2) * IA] * B[2] - C[(n - 1) * IC] * B[3] -
                    C[(n - 2) * IC] * B[4];
}

/* interleaved to split complex: IC counts floats (2 for packed pairs) */
void vDSP_ctoz(const DSPComplex *C, vDSP_Stride IC, const DSPSplitComplex *Z, vDSP_Stride IZ, vDSP_Length N)
{
    const float *c = (const float *)C;
    for (vDSP_Length n = 0; n < N; n++) {
        Z->realp[n * IZ] = c[n * IC];
        Z->imagp[n * IZ] = c[n * IC + 1];
    }
}

void vDSP_ztoc(const DSPSplitComplex *Z, vDSP_Stride IZ, DSPComplex *C, vDSP_Stride IC, vDSP_Length N)
{
    float *c = (float *)C;
    for (vDSP_Length n = 0; n < N; n++) {
        c[n * IC] = Z->realp[n * IZ];
        c[n * IC + 1] = Z->imagp[n * IZ];
    }
}

/* C = A * B, or conj(A) * B when Conjugate is -1 */
void vDSP_zvmul(const DSPSplitComplex *A, vDSP_Stride IA, const DSPSplitComplex *B, vDSP_Stride IB,
                const DSPSplitComplex *C, vDSP_Stride IC, vDSP_Length N, int Conjugate)
{
    for (vDSP_Length n = 0; n < N; n++) {
        float ar = A->realp[n * IA], ai = A->imagp[n * IA];
        if (Conjugate == -1)
            ai = -ai;
        float br = B->realp[n * IB], bi = B->imagp[n * IB];
        C->realp[n * IC] = ar * br - ai * bi;
        C->imagp[n * IC] = ar * bi + ai * br;
    }
}

struct OpaqueFFTSetup {
    vDSP_Length log2n;
};

FFTSetup vDSP_create_fftsetup(vDSP_Length Log2n, FFTRadix Radix)
{
    (void)Radix;
    if (Log2n > 24)
        return NULL;
    FFTSetup s = malloc(sizeof *s);
    if (s)
        s->log2n = Log2n;
    return s;
}

void vDSP_destroy_fftsetup(FFTSetup setup) { free(setup); }

/* an in-place radix-2 FFT of n (a power of two) points; sign -1 forward.
 * The complex products are written out, as there is no compiler runtime here. */
static void fft_complex(double *xr, double *xi, size_t n, int sign)
{
    for (size_t i = 1, j = 0; i < n; i++) {
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j) {
            double t = xr[i]; xr[i] = xr[j]; xr[j] = t;
            t = xi[i]; xi[i] = xi[j]; xi[j] = t;
        }
    }
    for (size_t len = 2; len <= n; len <<= 1) {
        double a = sign * 2 * M_PI / (double)len;
        for (size_t k = 0; k < len / 2; k++) {
            double wr = cos(a * (double)k), wi = sin(a * (double)k);
            for (size_t i = k; i < n; i += len) {
                size_t m = i + len / 2;
                double vr = xr[m] * wr - xi[m] * wi, vi = xr[m] * wi + xi[m] * wr;
                xr[m] = xr[i] - vr;
                xi[m] = xi[i] - vi;
                xr[i] += vr;
                xi[i] += vi;
            }
        }
    }
}

void vDSP_fft_zrip(FFTSetup Setup, const DSPSplitComplex *C, vDSP_Stride IC, vDSP_Length Log2N, FFTDirection Direction)
{
    if (!Setup || Log2N > Setup->log2n || Log2N < 1)
        return;
    size_t n = (size_t)1 << Log2N, h = n / 2;
    double *xr = calloc(2 * n, sizeof *xr);
    if (!xr)
        return;
    double *xi = xr + n;
    float *re = C->realp, *im = C->imagp;
    if (Direction == kFFTDirection_Forward) {
        for (size_t k = 0; k < h; k++) {
            xr[2 * k] = re[k * IC];
            xr[2 * k + 1] = im[k * IC];
        }
        fft_complex(xr, xi, n, -1);
        re[0] = (float)(2 * xr[0]);
        im[0] = (float)(2 * xr[h]);
        for (size_t k = 1; k < h; k++) {
            re[k * IC] = (float)(2 * xr[k]);
            im[k * IC] = (float)(2 * xi[k]);
        }
    } else {
        xr[0] = re[0];
        xr[h] = im[0];
        for (size_t k = 1; k < h; k++) {
            xr[k] = re[k * IC];
            xi[k] = im[k * IC];
            xr[n - k] = xr[k];
            xi[n - k] = -xi[k];
        }
        fft_complex(xr, xi, n, +1);
        for (size_t k = 0; k < h; k++) {
            re[k * IC] = (float)xr[2 * k];
            im[k * IC] = (float)xr[2 * k + 1];
        }
    }
    free(xr);
}
