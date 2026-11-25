/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Video: buffers and their attachments, pixel buffers and
 * their pools, pixel format descriptions and OpenGL texture caches (freemac
 * 1.235, Ferry 0.59.0), written from Apple's public Core Video reference.
 *
 * Every Core Video object is an Objective-C object, so CFRetain, CFRelease
 * and CFGetTypeID work on them as on a Mac. A pixel buffer Core Video makes
 * (CVPixelBufferCreate, a pool) lies on an IOSurface, laid out as a Mac
 * lays it out: rows aligned to 64 bytes unless asked otherwise, each plane
 * of a planar format after the one before, and at the start of a planar
 * buffer the big-endian table of where the planes are
 * (CVPlanarPixelBufferInfo) that CVPixelBufferGetBaseAddress points at.
 * Locking the base address only counts, as the memory never moves. Built
 * without ARC. */
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* ---- the keys and values -------------------------------------------------------------- */

#define KEY(name, value) const CFStringRef name = (CFStringRef)@value;
KEY(kCVBufferPropagatedAttachmentsKey, "PropagatedAttachments")
KEY(kCVBufferNonPropagatedAttachmentsKey, "NonPropagatedAttachments")
KEY(kCVBufferMovieTimeKey, "QTMovieTime")
KEY(kCVBufferTimeValueKey, "TimeValue")
KEY(kCVBufferTimeScaleKey, "TimeScale")
KEY(kCVImageBufferCGColorSpaceKey, "CGColorSpace")
KEY(kCVImageBufferCleanApertureKey, "CVCleanAperture")
KEY(kCVImageBufferCleanApertureWidthKey, "Width")
KEY(kCVImageBufferCleanApertureHeightKey, "Height")
KEY(kCVImageBufferCleanApertureHorizontalOffsetKey, "HorizontalOffset")
KEY(kCVImageBufferCleanApertureVerticalOffsetKey, "VerticalOffset")
KEY(kCVImageBufferPreferredCleanApertureKey, "CVPreferredCleanAperture")
KEY(kCVImageBufferFieldCountKey, "CVFieldCount")
KEY(kCVImageBufferFieldDetailKey, "CVFieldDetail")
KEY(kCVImageBufferFieldDetailTemporalTopFirst, "TemporalTopFirst")
KEY(kCVImageBufferFieldDetailTemporalBottomFirst, "TemporalBottomFirst")
KEY(kCVImageBufferFieldDetailSpatialFirstLineEarly, "SpatialFirstLineEarly")
KEY(kCVImageBufferFieldDetailSpatialFirstLineLate, "SpatialFirstLineLate")
KEY(kCVImageBufferPixelAspectRatioKey, "CVPixelAspectRatio")
KEY(kCVImageBufferPixelAspectRatioHorizontalSpacingKey, "HorizontalSpacing")
KEY(kCVImageBufferPixelAspectRatioVerticalSpacingKey, "VerticalSpacing")
KEY(kCVImageBufferDisplayDimensionsKey, "CVDisplayDimensions")
KEY(kCVImageBufferDisplayWidthKey, "Width")
KEY(kCVImageBufferDisplayHeightKey, "Height")
KEY(kCVImageBufferGammaLevelKey, "CVImageBufferGammaLevel")
KEY(kCVImageBufferICCProfileKey, "CVImageBufferICCProfile")
KEY(kCVImageBufferYCbCrMatrixKey, "CVImageBufferYCbCrMatrix")
KEY(kCVImageBufferYCbCrMatrix_ITU_R_709_2, "ITU_R_709_2")
KEY(kCVImageBufferYCbCrMatrix_ITU_R_601_4, "ITU_R_601_4")
KEY(kCVImageBufferYCbCrMatrix_SMPTE_240M_1995, "SMPTE_240M_1995")
KEY(kCVImageBufferYCbCrMatrix_DCI_P3, "DCI_P3")
KEY(kCVImageBufferYCbCrMatrix_P3_D65, "P3_D65")
KEY(kCVImageBufferYCbCrMatrix_ITU_R_2020, "ITU_R_2020")
KEY(kCVImageBufferColorPrimariesKey, "CVImageBufferColorPrimaries")
KEY(kCVImageBufferColorPrimaries_ITU_R_709_2, "ITU_R_709_2")
KEY(kCVImageBufferColorPrimaries_EBU_3213, "EBU_3213")
KEY(kCVImageBufferColorPrimaries_SMPTE_C, "SMPTE_C")
KEY(kCVImageBufferColorPrimaries_P22, "P22")
KEY(kCVImageBufferColorPrimaries_DCI_P3, "DCI_P3")
KEY(kCVImageBufferColorPrimaries_P3_D65, "P3_D65")
KEY(kCVImageBufferColorPrimaries_ITU_R_2020, "ITU_R_2020")
KEY(kCVImageBufferTransferFunctionKey, "CVImageBufferTransferFunction")
KEY(kCVImageBufferTransferFunction_ITU_R_709_2, "ITU_R_709_2")
KEY(kCVImageBufferTransferFunction_SMPTE_240M_1995, "SMPTE_240M_1995")
KEY(kCVImageBufferTransferFunction_UseGamma, "UseGamma")
KEY(kCVImageBufferTransferFunction_sRGB, "IEC_sRGB")
KEY(kCVImageBufferTransferFunction_ITU_R_2020, "ITU_R_2020")
KEY(kCVImageBufferTransferFunction_SMPTE_ST_428_1, "SMPTE_ST_428_1")
KEY(kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, "SMPTE_ST_2084_PQ")
KEY(kCVImageBufferTransferFunction_ITU_R_2100_HLG, "ITU_R_2100_HLG")
KEY(kCVImageBufferTransferFunction_Linear, "Linear")
KEY(kCVImageBufferChromaLocationTopFieldKey, "CVImageBufferChromaLocationTopField")
KEY(kCVImageBufferChromaLocationBottomFieldKey, "CVImageBufferChromaLocationBottomField")
KEY(kCVImageBufferChromaLocation_Left, "Left")
KEY(kCVImageBufferChromaLocation_Center, "Center")
KEY(kCVImageBufferChromaLocation_TopLeft, "TopLeft")
KEY(kCVImageBufferChromaLocation_Top, "Top")
KEY(kCVImageBufferChromaLocation_BottomLeft, "BottomLeft")
KEY(kCVImageBufferChromaLocation_Bottom, "Bottom")
KEY(kCVImageBufferChromaLocation_DV420, "DV 4:2:0")
KEY(kCVImageBufferChromaSubsamplingKey, "CVImageBufferChromaSubsampling")
KEY(kCVImageBufferChromaSubsampling_420, "4:2:0")
KEY(kCVImageBufferChromaSubsampling_422, "4:2:2")
KEY(kCVImageBufferChromaSubsampling_411, "4:1:1")
KEY(kCVImageBufferAlphaChannelIsOpaque, "CVImageBufferAlphaChannelIsOpaque")
KEY(kCVImageBufferMasteringDisplayColorVolumeKey, "CVImageBufferMasteringDisplayColorVolume")
KEY(kCVImageBufferContentLightLevelInfoKey, "CVImageBufferContentLightLevelInfo")
KEY(kCVPixelBufferPixelFormatTypeKey, "PixelFormatType")
KEY(kCVPixelBufferMemoryAllocatorKey, "MemoryAllocator")
KEY(kCVPixelBufferWidthKey, "Width")
KEY(kCVPixelBufferHeightKey, "Height")
KEY(kCVPixelBufferExtendedPixelsLeftKey, "ExtendedPixelsLeft")
KEY(kCVPixelBufferExtendedPixelsTopKey, "ExtendedPixelsTop")
KEY(kCVPixelBufferExtendedPixelsRightKey, "ExtendedPixelsRight")
KEY(kCVPixelBufferExtendedPixelsBottomKey, "ExtendedPixelsBottom")
KEY(kCVPixelBufferBytesPerRowAlignmentKey, "BytesPerRowAlignment")
KEY(kCVPixelBufferCGBitmapContextCompatibilityKey, "CGBitmapContextCompatibility")
KEY(kCVPixelBufferCGImageCompatibilityKey, "CGImageCompatibility")
KEY(kCVPixelBufferOpenGLCompatibilityKey, "OpenGLCompatibility")
KEY(kCVPixelBufferPlaneAlignmentKey, "PlaneAlignment")
KEY(kCVPixelBufferIOSurfacePropertiesKey, "IOSurfaceProperties")
KEY(kCVPixelBufferOpenGLESCompatibilityKey, "OpenGLESCompatibility")
KEY(kCVPixelBufferMetalCompatibilityKey, "MetalCompatibility")
KEY(kCVPixelBufferOpenGLTextureCacheCompatibilityKey, "OpenGLTextureCacheCompatibility")
KEY(kCVPixelBufferOpenGLESTextureCacheCompatibilityKey, "OpenGLESTextureCacheCompatibility")
KEY(kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, "IOSurfaceOpenGLTextureCompatibility")
KEY(kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey, "IOSurfaceOpenGLFBOCompatibility")
KEY(kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey, "IOSurfaceCoreAnimationCompatibility")
KEY(kCVPixelBufferIOSurfaceOpenGLESTextureCompatibilityKey, "IOSurfaceOpenGLESTextureCompatibility")
KEY(kCVPixelBufferIOSurfaceOpenGLESFBOCompatibilityKey, "IOSurfaceOpenGLESFBOCompatibility")
KEY(kCVPixelBufferPoolMinimumBufferCountKey, "MinimumBufferCount")
KEY(kCVPixelBufferPoolMaximumBufferAgeKey, "MaximumBufferAge")
KEY(kCVPixelBufferPoolAllocationThresholdKey, "kCVPixelBufferPoolAllocationThresholdKey")
KEY(kCVPixelBufferPoolFreeBufferNotification, "kCVPixelBufferPoolFreeBufferNotification")
KEY(kCVPixelFormatName, "Name")
KEY(kCVPixelFormatConstant, "PixelFormat")
KEY(kCVPixelFormatCodecType, "CodecType")
KEY(kCVPixelFormatFourCC, "FourCC")
KEY(kCVPixelFormatContainsAlpha, "ContainsAlpha")
KEY(kCVPixelFormatContainsYCbCr, "ContainsYCbCr")
KEY(kCVPixelFormatContainsRGB, "ContainsRGB")
KEY(kCVPixelFormatPlanes, "Planes")
KEY(kCVPixelFormatBlockWidth, "BlockWidth")
KEY(kCVPixelFormatBlockHeight, "BlockHeight")
KEY(kCVPixelFormatBitsPerBlock, "BitsPerBlock")
KEY(kCVPixelFormatHorizontalSubsampling, "HorizontalSubsampling")
KEY(kCVPixelFormatVerticalSubsampling, "VerticalSubsampling")
KEY(kCVPixelFormatOpenGLFormat, "OpenGLFormat")
KEY(kCVPixelFormatOpenGLType, "OpenGLType")
KEY(kCVPixelFormatOpenGLInternalFormat, "OpenGLInternalFormat")
KEY(kCVPixelFormatCGBitmapInfo, "CGBitmapInfo")
KEY(kCVPixelFormatOpenGLCompatibility, "OpenGLCompatibility")
KEY(kCVPixelFormatCGBitmapContextCompatibility, "CGBitmapContextCompatibility")
KEY(kCVPixelFormatCGImageCompatibility, "CGImageCompatibility")
KEY(kCVPixelFormatComponentRange, "ComponentRange")
KEY(kCVPixelFormatComponentRange_VideoRange, "VideoRange")
KEY(kCVPixelFormatComponentRange_FullRange, "FullRange")
KEY(kCVPixelFormatComponentRange_WideRange, "WideRange")
KEY(kCVOpenGLTextureCacheChromaSamplingModeKey, "ChromaSamplingMode")
KEY(kCVOpenGLTextureCacheChromaSamplingModeAutomatic, "Automatic")
KEY(kCVOpenGLTextureCacheChromaSamplingModeHighestQuality, "HighestQuality")
KEY(kCVOpenGLTextureCacheChromaSamplingModeBestPerformance, "BestPerformance")
#undef KEY

const CVTime kCVZeroTime = {0, 1, 0};
const CVTime kCVIndefiniteTime = {0, 1, kCVTimeIsIndefinite};

/* ---- the pixel formats ------------------------------------------------------------------ */

/* A plane: its width and height are the image's divided by the
 * subsampling (rounding up), and each block of blockWidth pixels takes
 * bytesPerBlock bytes. */
struct plane_layout {
    int hsub, vsub, blockWidth, bytesPerBlock;
};
struct format {
    OSType type;
    const char *name;
    int planes; /* 0: one packed plane, not planar */
    struct plane_layout layout[3];
    int rgb, ycbcr, alpha, fullRange;
    uint32_t glFormat, glType, glInternal, cgBitmapInfo;
};

enum { BGRA = 0x80E1, RGBA_ = 0x1908, RGB_ = 0x1907, UB = 0x1401, REV8888 = 0x8367, R8x = 0x1903, RGx = 0x8227 };
static const struct format formats[] = {
    {kCVPixelFormatType_32BGRA, "32BGRA", 0, {{1, 1, 1, 4}}, 1, 0, 1, 1, BGRA, REV8888, RGBA_, 0x2002},
    {kCVPixelFormatType_32ARGB, "32ARGB", 0, {{1, 1, 1, 4}}, 1, 0, 1, 1, BGRA, 0x8035, RGBA_, 0x4002},
    {kCVPixelFormatType_32RGBA, "32RGBA", 0, {{1, 1, 1, 4}}, 1, 0, 1, 1, RGBA_, UB, RGBA_, 0x0003},
    {kCVPixelFormatType_32ABGR, "32ABGR", 0, {{1, 1, 1, 4}}, 1, 0, 1, 1, RGBA_, REV8888, RGBA_, 0x2001},
    {kCVPixelFormatType_24RGB, "24RGB", 0, {{1, 1, 1, 3}}, 1, 0, 0, 1, RGB_, UB, RGB_, 0},
    {kCVPixelFormatType_24BGR, "24BGR", 0, {{1, 1, 1, 3}}, 1, 0, 0, 1, 0x80E0, UB, RGB_, 0},
    {kCVPixelFormatType_16BE555, "16BE555", 0, {{1, 1, 1, 2}}, 1, 0, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_16LE555, "16LE555", 0, {{1, 1, 1, 2}}, 1, 0, 0, 1, BGRA, 0x8366, RGBA_, 0},
    {kCVPixelFormatType_16LE565, "16LE565", 0, {{1, 1, 1, 2}}, 1, 0, 0, 1, RGB_, 0x8363, RGB_, 0},
    {kCVPixelFormatType_16BE565, "16BE565", 0, {{1, 1, 1, 2}}, 1, 0, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_64ARGB, "64ARGB", 0, {{1, 1, 1, 8}}, 1, 0, 1, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_64RGBALE, "64RGBALE", 0, {{1, 1, 1, 8}}, 1, 0, 1, 1, RGBA_, 0x1403, 0x805B, 0},
    {kCVPixelFormatType_64RGBAHalf, "64RGBAHalf", 0, {{1, 1, 1, 8}}, 1, 0, 1, 1, RGBA_, 0x140B, 0x881A, 0},
    {kCVPixelFormatType_128RGBAFloat, "128RGBAFloat", 0, {{1, 1, 1, 16}}, 1, 0, 1, 1, RGBA_, 0x1406, 0x8814, 0},
    {kCVPixelFormatType_48RGB, "48RGB", 0, {{1, 1, 1, 6}}, 1, 0, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_30RGB, "30RGB", 0, {{1, 1, 1, 4}}, 1, 0, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_30RGBLEPackedWideGamut, "30RGBLEPackedWideGamut", 0, {{1, 1, 1, 4}}, 1, 0, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_ARGB2101010LEPacked, "ARGB2101010LEPacked", 0, {{1, 1, 1, 4}}, 1, 0, 1, 1, BGRA, 0x8368,
     0x8059, 0},
    {kCVPixelFormatType_32AlphaGray, "32AlphaGray", 0, {{1, 1, 1, 4}}, 0, 0, 1, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_16Gray, "16Gray", 0, {{1, 1, 1, 2}}, 0, 0, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_OneComponent8, "OneComponent8", 0, {{1, 1, 1, 1}}, 0, 0, 0, 1, R8x, UB, 0x8229, 0},
    {kCVPixelFormatType_OneComponent16, "OneComponent16", 0, {{1, 1, 1, 2}}, 0, 0, 0, 1, R8x, 0x1403, 0x822A, 0},
    {kCVPixelFormatType_OneComponent16Half, "OneComponent16Half", 0, {{1, 1, 1, 2}}, 0, 0, 0, 1, R8x, 0x140B, 0x822D,
     0},
    {kCVPixelFormatType_OneComponent32Float, "OneComponent32Float", 0, {{1, 1, 1, 4}}, 0, 0, 0, 1, R8x, 0x1406,
     0x822E, 0},
    {kCVPixelFormatType_TwoComponent8, "TwoComponent8", 0, {{1, 1, 1, 2}}, 0, 0, 0, 1, RGx, UB, 0x822B, 0},
    {kCVPixelFormatType_TwoComponent16, "TwoComponent16", 0, {{1, 1, 1, 4}}, 0, 0, 0, 1, RGx, 0x1403, 0x822C, 0},
    {kCVPixelFormatType_TwoComponent16Half, "TwoComponent16Half", 0, {{1, 1, 1, 4}}, 0, 0, 0, 1, RGx, 0x140B, 0x822F,
     0},
    {kCVPixelFormatType_TwoComponent32Float, "TwoComponent32Float", 0, {{1, 1, 1, 8}}, 0, 0, 0, 1, RGx, 0x1406,
     0x8230, 0},
    {kCVPixelFormatType_422YpCbCr8, "422YpCbCr8", 0, {{1, 1, 2, 4}}, 0, 1, 0, 0, 0x8A1F, 0x85BA, RGB_, 0},
    {kCVPixelFormatType_422YpCbCr8_yuvs, "422YpCbCr8_yuvs", 0, {{1, 1, 2, 4}}, 0, 1, 0, 0, 0x8A1F, 0x85BB, RGB_, 0},
    {kCVPixelFormatType_422YpCbCr8FullRange, "422YpCbCr8FullRange", 0, {{1, 1, 2, 4}}, 0, 1, 0, 1, 0x8A1F, 0x85BB,
     RGB_, 0},
    {kCVPixelFormatType_422YpCbCr10, "422YpCbCr10", 0, {{1, 1, 48, 128}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_422YpCbCr16, "422YpCbCr16", 0, {{1, 1, 2, 8}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_444YpCbCr8, "444YpCbCr8", 0, {{1, 1, 1, 3}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_444YpCbCr10, "444YpCbCr10", 0, {{1, 1, 1, 4}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_4444YpCbCrA8, "4444YpCbCrA8", 0, {{1, 1, 1, 4}}, 0, 1, 1, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_4444YpCbCrA8R, "4444YpCbCrA8R", 0, {{1, 1, 1, 4}}, 0, 1, 1, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_4444AYpCbCr8, "4444AYpCbCr8", 0, {{1, 1, 1, 4}}, 0, 1, 1, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_4444AYpCbCr16, "4444AYpCbCr16", 0, {{1, 1, 1, 8}}, 0, 1, 1, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr8Planar, "420YpCbCr8Planar", 3, {{1, 1, 1, 1}, {2, 2, 1, 1}, {2, 2, 1, 1}}, 0, 1, 0,
     0, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr8PlanarFullRange, "420YpCbCr8PlanarFullRange", 3,
     {{1, 1, 1, 1}, {2, 2, 1, 1}, {2, 2, 1, 1}}, 0, 1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, "420YpCbCr8BiPlanarVideoRange", 2, {{1, 1, 1, 1}, {2, 2, 1, 2}},
     0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, "420YpCbCr8BiPlanarFullRange", 2, {{1, 1, 1, 1}, {2, 2, 1, 2}}, 0,
     1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange, "422YpCbCr8BiPlanarVideoRange", 2, {{1, 1, 1, 1}, {2, 1, 1, 2}},
     0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_422YpCbCr8BiPlanarFullRange, "422YpCbCr8BiPlanarFullRange", 2, {{1, 1, 1, 1}, {2, 1, 1, 2}}, 0,
     1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange, "444YpCbCr8BiPlanarVideoRange", 2, {{1, 1, 1, 1}, {1, 1, 1, 2}},
     0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_444YpCbCr8BiPlanarFullRange, "444YpCbCr8BiPlanarFullRange", 2, {{1, 1, 1, 1}, {1, 1, 1, 2}}, 0,
     1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, "420YpCbCr10BiPlanarVideoRange", 2,
     {{1, 1, 1, 2}, {2, 2, 1, 4}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr10BiPlanarFullRange, "420YpCbCr10BiPlanarFullRange", 2, {{1, 1, 1, 2}, {2, 2, 1, 4}},
     0, 1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, "422YpCbCr10BiPlanarVideoRange", 2,
     {{1, 1, 1, 2}, {2, 1, 1, 4}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_422YpCbCr10BiPlanarFullRange, "422YpCbCr10BiPlanarFullRange", 2, {{1, 1, 1, 2}, {2, 1, 1, 4}},
     0, 1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange, "444YpCbCr10BiPlanarVideoRange", 2,
     {{1, 1, 1, 2}, {1, 1, 1, 4}}, 0, 1, 0, 0, 0, 0, 0, 0},
    {kCVPixelFormatType_444YpCbCr10BiPlanarFullRange, "444YpCbCr10BiPlanarFullRange", 2, {{1, 1, 1, 2}, {1, 1, 1, 4}},
     0, 1, 0, 1, 0, 0, 0, 0},
    {kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar, "420YpCbCr8VideoRange_8A_TriPlanar", 3,
     {{1, 1, 1, 1}, {2, 2, 1, 2}, {1, 1, 1, 1}}, 0, 1, 1, 0, 0, 0, 0, 0},
};

static const struct format *format_of(OSType t)
{
    for (size_t i = 0; i < sizeof formats / sizeof *formats; i++)
        if (formats[i].type == t)
            return &formats[i];
    return NULL;
}

static size_t align_to(size_t v, size_t a) { return a > 1 ? (v + a - 1) / a * a : v; }

static size_t number_of(NSDictionary *d, id key, size_t otherwise)
{
    id v = [d isKindOfClass:[NSDictionary class]] ? [d objectForKey:key] : nil;
    return [v respondsToSelector:@selector(unsignedLongLongValue)] ? (size_t)[v unsignedLongLongValue] : otherwise;
}

/* ---- buffers ---------------------------------------------------------------------------- */

@interface FerryCVBuffer : NSObject {
  @public
    NSMutableDictionary *_attachments[2]; /* not propagated, propagated */
    NSDictionary *_snapshot[2];
    pthread_mutex_t _attachmentLock;
}
@end

@implementation FerryCVBuffer
- (instancetype)init
{
    if ((self = [super init])) {
        _attachments[0] = [[NSMutableDictionary alloc] init];
        _attachments[1] = [[NSMutableDictionary alloc] init];
        pthread_mutex_init(&_attachmentLock, NULL);
    }
    return self;
}
- (void)dealloc
{
    for (int i = 0; i < 2; i++) {
        [_attachments[i] release];
        [_snapshot[i] release];
    }
    pthread_mutex_destroy(&_attachmentLock);
    [super dealloc];
}
- (void)_changed:(int)mode
{
    [_snapshot[mode] autorelease];
    _snapshot[mode] = nil;
}
@end

#define BUF(ref) ((FerryCVBuffer *)(ref))

CVBufferRef CVBufferRetain(CVBufferRef b) { return b ? (CVBufferRef)[(id)b retain] : NULL; }
void CVBufferRelease(CVBufferRef b)
{
    if (b)
        [(id)b release];
}

void CVBufferSetAttachment(CVBufferRef b, CFStringRef key, CFTypeRef value, CVAttachmentMode mode)
{
    if (!b || !key || ![(id)b isKindOfClass:[FerryCVBuffer class]])
        return;
    FerryCVBuffer *o = BUF(b);
    int m = mode == kCVAttachmentMode_ShouldPropagate;
    pthread_mutex_lock(&o->_attachmentLock);
    [o->_attachments[!m] removeObjectForKey:(id)key];
    [o _changed:!m];
    if (value)
        [o->_attachments[m] setObject:(id)value forKey:(id)key];
    else
        [o->_attachments[m] removeObjectForKey:(id)key];
    [o _changed:m];
    pthread_mutex_unlock(&o->_attachmentLock);
}

static id attachment_of(CVBufferRef b, CFStringRef key, CVAttachmentMode *mode, BOOL retained)
{
    if (!b || !key || ![(id)b isKindOfClass:[FerryCVBuffer class]])
        return nil;
    FerryCVBuffer *o = BUF(b);
    id v = nil;
    pthread_mutex_lock(&o->_attachmentLock);
    for (int m = 1; m >= 0 && !v; m--)
        if ((v = [o->_attachments[m] objectForKey:(id)key]) && mode)
            *mode = m ? kCVAttachmentMode_ShouldPropagate : kCVAttachmentMode_ShouldNotPropagate;
    if (retained)
        [v retain];
    pthread_mutex_unlock(&o->_attachmentLock);
    return v;
}
CFTypeRef CVBufferGetAttachment(CVBufferRef b, CFStringRef key, CVAttachmentMode *mode)
{
    return (CFTypeRef)attachment_of(b, key, mode, NO);
}
CFTypeRef CVBufferCopyAttachment(CVBufferRef b, CFStringRef key, CVAttachmentMode *mode)
{
    return (CFTypeRef)attachment_of(b, key, mode, YES);
}
Boolean CVBufferHasAttachment(CVBufferRef b, CFStringRef key) { return attachment_of(b, key, NULL, NO) != nil; }

void CVBufferRemoveAttachment(CVBufferRef b, CFStringRef key)
{
    if (!b || !key || ![(id)b isKindOfClass:[FerryCVBuffer class]])
        return;
    FerryCVBuffer *o = BUF(b);
    pthread_mutex_lock(&o->_attachmentLock);
    for (int m = 0; m < 2; m++) {
        [o->_attachments[m] removeObjectForKey:(id)key];
        [o _changed:m];
    }
    pthread_mutex_unlock(&o->_attachmentLock);
}
void CVBufferRemoveAllAttachments(CVBufferRef b)
{
    if (!b || ![(id)b isKindOfClass:[FerryCVBuffer class]])
        return;
    FerryCVBuffer *o = BUF(b);
    pthread_mutex_lock(&o->_attachmentLock);
    for (int m = 0; m < 2; m++) {
        [o->_attachments[m] removeAllObjects];
        [o _changed:m];
    }
    pthread_mutex_unlock(&o->_attachmentLock);
}

/* The dictionary stays the buffer's until its attachments next change. */
CFDictionaryRef CVBufferGetAttachments(CVBufferRef b, CVAttachmentMode mode)
{
    if (!b || ![(id)b isKindOfClass:[FerryCVBuffer class]])
        return NULL;
    FerryCVBuffer *o = BUF(b);
    int m = mode == kCVAttachmentMode_ShouldPropagate;
    pthread_mutex_lock(&o->_attachmentLock);
    if (!o->_snapshot[m])
        o->_snapshot[m] = [o->_attachments[m] copy];
    NSDictionary *d = o->_snapshot[m];
    pthread_mutex_unlock(&o->_attachmentLock);
    return d.count ? (CFDictionaryRef)d : NULL;
}
CFDictionaryRef CVBufferCopyAttachments(CVBufferRef b, CVAttachmentMode mode)
{
    if (!b || ![(id)b isKindOfClass:[FerryCVBuffer class]])
        return NULL;
    FerryCVBuffer *o = BUF(b);
    int m = mode == kCVAttachmentMode_ShouldPropagate;
    pthread_mutex_lock(&o->_attachmentLock);
    NSDictionary *d = o->_attachments[m].count ? [o->_attachments[m] copy] : nil;
    pthread_mutex_unlock(&o->_attachmentLock);
    return (CFDictionaryRef)d;
}
void CVBufferSetAttachments(CVBufferRef b, CFDictionaryRef d, CVAttachmentMode mode)
{
    for (id key in [[(NSDictionary *)d copy] autorelease])
        CVBufferSetAttachment(b, (CFStringRef)key, (CFTypeRef)[(NSDictionary *)d objectForKey:key], mode);
}
void CVBufferPropagateAttachments(CVBufferRef src, CVBufferRef dst)
{
    CFDictionaryRef d = CVBufferCopyAttachments(src, kCVAttachmentMode_ShouldPropagate);
    if (d) {
        CVBufferSetAttachments(dst, d, kCVAttachmentMode_ShouldPropagate);
        CFRelease(d);
    }
}

/* ---- pixel buffers ---------------------------------------------------------------------- */

#define MAX_PLANES 3

@interface FerryCVPixelBuffer : FerryCVBuffer {
  @public
    size_t _width, _height;
    OSType _format;
    size_t _planeCount; /* 0 if packed */
    size_t _planeWidth[MAX_PLANES], _planeHeight[MAX_PLANES], _planeBytesPerRow[MAX_PLANES];
    unsigned char *_planeBase[MAX_PLANES];
    unsigned char *_base;
    size_t _bytesPerRow, _dataSize;
    size_t _extLeft, _extRight, _extTop, _extBottom;
    IOSurfaceRef _surface;
    CVPixelBufferReleaseBytesCallback _releaseBytes;
    CVPixelBufferReleasePlanarBytesCallback _releasePlanar;
    void *_releaseRefCon;
    NSDictionary *_creationAttributes;
    int _locks;
}
@end

@implementation FerryCVPixelBuffer
- (void)dealloc
{
    if (_releaseBytes)
        _releaseBytes(_releaseRefCon, _base);
    if (_releasePlanar) {
        const void *planes[MAX_PLANES] = {_planeBase[0], _planeBase[1], _planeBase[2]};
        _releasePlanar(_releaseRefCon, _base, _dataSize, _planeCount, planes);
    }
    if (_surface)
        CFRelease(_surface);
    [_creationAttributes release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CVPixelBuffer %p %zux%zu '%c%c%c%c' planes %zu iosurface %p>", self, _width,
                                      _height, (int)(_format >> 24 & 0xff), (int)(_format >> 16 & 0xff),
                                      (int)(_format >> 8 & 0xff), (int)(_format & 0xff), _planeCount, _surface];
}
@end

#define PB(ref) ((FerryCVPixelBuffer *)(ref))
static BOOL is_pb(CVPixelBufferRef b) { return b && [(id)b isKindOfClass:[FerryCVPixelBuffer class]]; }

CFTypeID CVPixelBufferGetTypeID(void) { return (CFTypeID)[FerryCVPixelBuffer class]; }
CVPixelBufferRef CVPixelBufferRetain(CVPixelBufferRef b) { return CVBufferRetain(b); }
void CVPixelBufferRelease(CVPixelBufferRef b) { CVBufferRelease(b); }

/* Lays a buffer of format f out on an IOSurface, as described above. */
static CVReturn make_on_surface(size_t w, size_t h, OSType type, NSDictionary *attrs, FerryCVPixelBuffer **out)
{
    const struct format *f = format_of(type);
    if (!f)
        return kCVReturnInvalidPixelFormat;
    if (!w || !h || w > 16384 || h > 16384)
        return kCVReturnInvalidSize;
    size_t rowAlign = number_of(attrs, @"BytesPerRowAlignment", 64), planeAlign = number_of(attrs, @"PlaneAlignment", 64);
    if (rowAlign < 1)
        rowAlign = 1;
    if (planeAlign < 1)
        planeAlign = 1;
    size_t extL = number_of(attrs, @"ExtendedPixelsLeft", 0), extR = number_of(attrs, @"ExtendedPixelsRight", 0);
    size_t extT = number_of(attrs, @"ExtendedPixelsTop", 0), extB = number_of(attrs, @"ExtendedPixelsBottom", 0);
    size_t fullW = w + extL + extR, fullH = h + extT + extB;
    size_t planes = f->planes ? (size_t)f->planes : 1;
    size_t pw[MAX_PLANES], ph[MAX_PLANES], prb[MAX_PLANES], poff[MAX_PLANES], pext[MAX_PLANES];
    size_t offset = f->planes ? align_to(f->planes == 2 ? sizeof(CVPlanarPixelBufferInfo_YCbCrBiPlanar)
                                                       : sizeof(CVPlanarPixelBufferInfo_YCbCrPlanar),
                                         planeAlign)
                              : 0;
    for (size_t i = 0; i < planes; i++) {
        const struct plane_layout *l = &f->layout[i];
        size_t fw = (fullW + (size_t)l->hsub - 1) / (size_t)l->hsub, fh = (fullH + (size_t)l->vsub - 1) / (size_t)l->vsub;
        pw[i] = (w + (size_t)l->hsub - 1) / (size_t)l->hsub;
        ph[i] = (h + (size_t)l->vsub - 1) / (size_t)l->vsub;
        prb[i] = align_to((fw + (size_t)l->blockWidth - 1) / (size_t)l->blockWidth * (size_t)l->bytesPerBlock, rowAlign);
        poff[i] = offset;
        /* where the image starts, after the extended rows and columns */
        pext[i] = extT / (size_t)l->vsub * prb[i] + extL / (size_t)l->hsub / (size_t)l->blockWidth * (size_t)l->bytesPerBlock;
        offset = align_to(offset + prb[i] * fh, planeAlign);
    }
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    NSDictionary *extra = [attrs isKindOfClass:[NSDictionary class]] ? [attrs objectForKey:@"IOSurfaceProperties"] : nil;
    if ([extra isKindOfClass:[NSDictionary class]])
        [props addEntriesFromDictionary:extra];
    [props setObject:@(fullW) forKey:@"IOSurfaceWidth"];
    [props setObject:@(fullH) forKey:@"IOSurfaceHeight"];
    [props setObject:@(type) forKey:@"IOSurfacePixelFormat"];
    [props setObject:@(offset) forKey:@"IOSurfaceAllocSize"];
    if (f->planes) {
        NSMutableArray *info = [NSMutableArray array];
        for (size_t i = 0; i < planes; i++)
            [info addObject:@{
                @"IOSurfacePlaneWidth" : @(pw[i]),
                @"IOSurfacePlaneHeight" : @(ph[i]),
                @"IOSurfacePlaneBytesPerRow" : @(prb[i]),
                @"IOSurfacePlaneOffset" : @(poff[i]),
                @"IOSurfacePlaneSize" : @(prb[i] * ((fullH + (size_t)f->layout[i].vsub - 1) / (size_t)f->layout[i].vsub)),
                @"IOSurfacePlaneBytesPerElement" : @(f->layout[i].bytesPerBlock),
                @"IOSurfacePlaneElementWidth" : @(f->layout[i].blockWidth),
                @"IOSurfacePlaneElementHeight" : @1,
            }];
        [props setObject:info forKey:@"IOSurfacePlaneInfo"];
    } else {
        [props setObject:@(prb[0]) forKey:@"IOSurfaceBytesPerRow"];
        [props setObject:@(f->layout[0].bytesPerBlock) forKey:@"IOSurfaceBytesPerElement"];
        [props setObject:@(f->layout[0].blockWidth) forKey:@"IOSurfaceElementWidth"];
    }
    IOSurfaceRef s = IOSurfaceCreate((CFDictionaryRef)props);
    if (!s)
        return kCVReturnAllocationFailed;
    FerryCVPixelBuffer *b = [[FerryCVPixelBuffer alloc] init];
    b->_width = w;
    b->_height = h;
    b->_format = type;
    b->_surface = s;
    b->_extLeft = extL;
    b->_extRight = extR;
    b->_extTop = extT;
    b->_extBottom = extB;
    b->_dataSize = IOSurfaceGetAllocSize(s);
    unsigned char *mem = f->planes ? IOSurfaceGetBaseAddressOfPlane(s, 0) - poff[0] : IOSurfaceGetBaseAddress(s);
    if (f->planes) {
        b->_planeCount = planes;
        b->_base = mem;
        for (size_t i = 0; i < planes; i++) {
            b->_planeWidth[i] = pw[i];
            b->_planeHeight[i] = ph[i];
            b->_planeBytesPerRow[i] = prb[i];
            b->_planeBase[i] = mem + poff[i] + pext[i];
        }
        /* the table at the start, big-endian, offsets from the base address */
        CVPlanarComponentInfo *ci = (CVPlanarComponentInfo *)mem;
        for (size_t i = 0; i < planes; i++) {
            ci[i].offset = (int32_t)__builtin_bswap32((uint32_t)(poff[i] + pext[i]));
            ci[i].rowBytes = __builtin_bswap32((uint32_t)prb[i]);
        }
        b->_bytesPerRow = 0;
    } else {
        b->_base = mem + pext[0];
        b->_bytesPerRow = prb[0];
    }
    b->_creationAttributes = [attrs isKindOfClass:[NSDictionary class]] ? [attrs copy] : [[NSDictionary alloc] init];
    *out = b;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferCreate(CFAllocatorRef allocator, size_t w, size_t h, OSType type, CFDictionaryRef attrs,
                             CVPixelBufferRef *out)
{
    if (!out)
        return kCVReturnInvalidArgument;
    *out = NULL;
    FerryCVPixelBuffer *b = nil;
    CVReturn r = make_on_surface(w, h, type, (NSDictionary *)attrs, &b);
    if (r == kCVReturnSuccess)
        *out = (CVPixelBufferRef)b;
    return r;
}

CVReturn CVPixelBufferCreateWithBytes(CFAllocatorRef allocator, size_t w, size_t h, OSType type, void *base,
                                      size_t bytesPerRow, CVPixelBufferReleaseBytesCallback release, void *refCon,
                                      CFDictionaryRef attrs, CVPixelBufferRef *out)
{
    if (!out || !base)
        return kCVReturnInvalidArgument;
    *out = NULL;
    const struct format *f = format_of(type);
    if (f && f->planes)
        return kCVReturnInvalidPixelFormat;
    if (!w || !h)
        return kCVReturnInvalidSize;
    FerryCVPixelBuffer *b = [[FerryCVPixelBuffer alloc] init];
    b->_width = w;
    b->_height = h;
    b->_format = type;
    b->_base = base;
    b->_bytesPerRow = bytesPerRow;
    b->_dataSize = bytesPerRow * h;
    b->_releaseBytes = release;
    b->_releaseRefCon = refCon;
    b->_creationAttributes = attrs ? [(NSDictionary *)attrs copy] : [[NSDictionary alloc] init];
    *out = (CVPixelBufferRef)b;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferCreateWithPlanarBytes(CFAllocatorRef allocator, size_t w, size_t h, OSType type, void *data,
                                            size_t dataSize, size_t planes, void *planeBase[], size_t planeWidth[],
                                            size_t planeHeight[], size_t planeBytesPerRow[],
                                            CVPixelBufferReleasePlanarBytesCallback release, void *refCon,
                                            CFDictionaryRef attrs, CVPixelBufferRef *out)
{
    if (!out || !planeBase || !planes || planes > MAX_PLANES)
        return kCVReturnInvalidArgument;
    *out = NULL;
    if (!w || !h)
        return kCVReturnInvalidSize;
    FerryCVPixelBuffer *b = [[FerryCVPixelBuffer alloc] init];
    b->_width = w;
    b->_height = h;
    b->_format = type;
    b->_base = data ? data : planeBase[0];
    b->_dataSize = dataSize;
    b->_planeCount = planes;
    for (size_t i = 0; i < planes; i++) {
        b->_planeBase[i] = planeBase[i];
        b->_planeWidth[i] = planeWidth ? planeWidth[i] : w;
        b->_planeHeight[i] = planeHeight ? planeHeight[i] : h;
        b->_planeBytesPerRow[i] = planeBytesPerRow ? planeBytesPerRow[i] : 0;
    }
    b->_releasePlanar = release;
    b->_releaseRefCon = refCon;
    b->_creationAttributes = attrs ? [(NSDictionary *)attrs copy] : [[NSDictionary alloc] init];
    *out = (CVPixelBufferRef)b;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferCreateWithIOSurface(CFAllocatorRef allocator, IOSurfaceRef s, CFDictionaryRef attrs,
                                          CVPixelBufferRef *out)
{
    if (!out || !s)
        return kCVReturnInvalidArgument;
    *out = NULL;
    FerryCVPixelBuffer *b = [[FerryCVPixelBuffer alloc] init];
    b->_width = IOSurfaceGetWidth(s);
    b->_height = IOSurfaceGetHeight(s);
    b->_format = IOSurfaceGetPixelFormat(s);
    b->_surface = (IOSurfaceRef)CFRetain(s);
    b->_dataSize = IOSurfaceGetAllocSize(s);
    size_t planes = IOSurfaceGetPlaneCount(s);
    if (planes) {
        if (planes > MAX_PLANES)
            planes = MAX_PLANES;
        b->_planeCount = planes;
        b->_base = IOSurfaceGetBaseAddress(s);
        for (size_t i = 0; i < planes; i++) {
            b->_planeBase[i] = IOSurfaceGetBaseAddressOfPlane(s, i);
            b->_planeWidth[i] = IOSurfaceGetWidthOfPlane(s, i);
            b->_planeHeight[i] = IOSurfaceGetHeightOfPlane(s, i);
            b->_planeBytesPerRow[i] = IOSurfaceGetBytesPerRowOfPlane(s, i);
        }
    } else {
        b->_base = IOSurfaceGetBaseAddress(s);
        b->_bytesPerRow = IOSurfaceGetBytesPerRow(s);
    }
    b->_creationAttributes = attrs ? [(NSDictionary *)attrs copy] : [[NSDictionary alloc] init];
    *out = (CVPixelBufferRef)b;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferCreateResolvedAttributesDictionary(CFAllocatorRef allocator, CFArrayRef attributes,
                                                         CFDictionaryRef *out)
{
    if (!out)
        return kCVReturnInvalidArgument;
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    for (id one in (NSArray *)attributes)
        if ([one isKindOfClass:[NSDictionary class]])
            [d addEntriesFromDictionary:one];
    *out = (CFDictionaryRef)d;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferLockBaseAddress(CVPixelBufferRef b, CVPixelBufferLockFlags flags)
{
    if (!is_pb(b))
        return kCVReturnInvalidArgument;
    __atomic_add_fetch(&PB(b)->_locks, 1, __ATOMIC_ACQ_REL);
    if (PB(b)->_surface)
        IOSurfaceLock(PB(b)->_surface, (flags & kCVPixelBufferLock_ReadOnly) ? kIOSurfaceLockReadOnly : 0, NULL);
    return kCVReturnSuccess;
}
CVReturn CVPixelBufferUnlockBaseAddress(CVPixelBufferRef b, CVPixelBufferLockFlags flags)
{
    if (!is_pb(b))
        return kCVReturnInvalidArgument;
    if (__atomic_sub_fetch(&PB(b)->_locks, 1, __ATOMIC_ACQ_REL) < 0) {
        __atomic_add_fetch(&PB(b)->_locks, 1, __ATOMIC_ACQ_REL);
        return kCVReturnError;
    }
    if (PB(b)->_surface)
        IOSurfaceUnlock(PB(b)->_surface, (flags & kCVPixelBufferLock_ReadOnly) ? kIOSurfaceLockReadOnly : 0, NULL);
    return kCVReturnSuccess;
}

size_t CVPixelBufferGetWidth(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_width : 0; }
size_t CVPixelBufferGetHeight(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_height : 0; }
OSType CVPixelBufferGetPixelFormatType(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_format : 0; }
void *CVPixelBufferGetBaseAddress(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_base : NULL; }
size_t CVPixelBufferGetBytesPerRow(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_bytesPerRow : 0; }
size_t CVPixelBufferGetDataSize(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_dataSize : 0; }
Boolean CVPixelBufferIsPlanar(CVPixelBufferRef b) { return is_pb(b) && PB(b)->_planeCount > 0; }
size_t CVPixelBufferGetPlaneCount(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_planeCount : 0; }
size_t CVPixelBufferGetWidthOfPlane(CVPixelBufferRef b, size_t i)
{
    return is_pb(b) && i < PB(b)->_planeCount ? PB(b)->_planeWidth[i] : 0;
}
size_t CVPixelBufferGetHeightOfPlane(CVPixelBufferRef b, size_t i)
{
    return is_pb(b) && i < PB(b)->_planeCount ? PB(b)->_planeHeight[i] : 0;
}
void *CVPixelBufferGetBaseAddressOfPlane(CVPixelBufferRef b, size_t i)
{
    return is_pb(b) && i < PB(b)->_planeCount ? PB(b)->_planeBase[i] : NULL;
}
size_t CVPixelBufferGetBytesPerRowOfPlane(CVPixelBufferRef b, size_t i)
{
    return is_pb(b) && i < PB(b)->_planeCount ? PB(b)->_planeBytesPerRow[i] : 0;
}
void CVPixelBufferGetExtendedPixels(CVPixelBufferRef b, size_t *l, size_t *r, size_t *t, size_t *bo)
{
    FerryCVPixelBuffer *p = is_pb(b) ? PB(b) : nil;
    if (l)
        *l = p ? p->_extLeft : 0;
    if (r)
        *r = p ? p->_extRight : 0;
    if (t)
        *t = p ? p->_extTop : 0;
    if (bo)
        *bo = p ? p->_extBottom : 0;
}

/* Copies the edge pixels of a packed buffer out into its extended ones. */
CVReturn CVPixelBufferFillExtendedPixels(CVPixelBufferRef b)
{
    if (!is_pb(b))
        return kCVReturnInvalidArgument;
    FerryCVPixelBuffer *p = PB(b);
    const struct format *f = format_of(p->_format);
    if (!f || f->planes || f->layout[0].blockWidth != 1 ||
        !(p->_extLeft || p->_extRight || p->_extTop || p->_extBottom))
        return kCVReturnSuccess;
    size_t bpp = (size_t)f->layout[0].bytesPerBlock, rb = p->_bytesPerRow;
    for (size_t y = 0; y < p->_height; y++) {
        unsigned char *row = p->_base + y * rb;
        for (size_t x = 1; x <= p->_extLeft; x++)
            memcpy(row - x * bpp, row, bpp);
        for (size_t x = 0; x < p->_extRight; x++)
            memcpy(row + (p->_width + x) * bpp, row + (p->_width - 1) * bpp, bpp);
    }
    size_t full = (p->_width + p->_extLeft + p->_extRight) * bpp;
    unsigned char *first = p->_base - p->_extLeft * bpp, *last = first + (p->_height - 1) * rb;
    for (size_t y = 1; y <= p->_extTop; y++)
        memcpy(first - y * rb, first, full);
    for (size_t y = 1; y <= p->_extBottom; y++)
        memcpy(last + y * rb, last, full);
    return kCVReturnSuccess;
}

CFDictionaryRef CVPixelBufferCopyCreationAttributes(CVPixelBufferRef b)
{
    if (!is_pb(b))
        return NULL;
    FerryCVPixelBuffer *p = PB(b);
    NSMutableDictionary *d = [p->_creationAttributes mutableCopy];
    [d setObject:@(p->_width) forKey:@"Width"];
    [d setObject:@(p->_height) forKey:@"Height"];
    [d setObject:@(p->_format) forKey:@"PixelFormatType"];
    return (CFDictionaryRef)d;
}

IOSurfaceRef CVPixelBufferGetIOSurface(CVPixelBufferRef b) { return is_pb(b) ? PB(b)->_surface : NULL; }

/* ---- image buffers ------------------------------------------------------------------------ */

static double num(id v) { return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0; }

CGSize CVImageBufferGetEncodedSize(CVImageBufferRef b)
{
    if (is_pb(b))
        return CGSizeMake(PB(b)->_width, PB(b)->_height);
    return CGSizeZero;
}
CGSize CVImageBufferGetDisplaySize(CVImageBufferRef b)
{
    NSDictionary *d = (NSDictionary *)CVBufferGetAttachment(b, kCVImageBufferDisplayDimensionsKey, NULL);
    if ([d isKindOfClass:[NSDictionary class]] && num([d objectForKey:@"Width"]) > 0)
        return CGSizeMake(num([d objectForKey:@"Width"]), num([d objectForKey:@"Height"]));
    CGSize s = CVImageBufferGetEncodedSize(b);
    NSDictionary *par = (NSDictionary *)CVBufferGetAttachment(b, kCVImageBufferPixelAspectRatioKey, NULL);
    double hs = num([par objectForKey:@"HorizontalSpacing"]), vs = num([par objectForKey:@"VerticalSpacing"]);
    if ([par isKindOfClass:[NSDictionary class]] && hs > 0 && vs > 0)
        s.width = s.width * hs / vs;
    return s;
}
CGRect CVImageBufferGetCleanRect(CVImageBufferRef b)
{
    CGSize s = CVImageBufferGetEncodedSize(b);
    NSDictionary *a = (NSDictionary *)CVBufferGetAttachment(b, kCVImageBufferCleanApertureKey, NULL);
    if (![a isKindOfClass:[NSDictionary class]])
        return CGRectMake(0, 0, s.width, s.height);
    double w = num([a objectForKey:@"Width"]), h = num([a objectForKey:@"Height"]);
    double ho = num([a objectForKey:@"HorizontalOffset"]), vo = num([a objectForKey:@"VerticalOffset"]);
    return CGRectMake((s.width - w) / 2 + ho, (s.height - h) / 2 + vo, w, h);
}
Boolean CVImageBufferIsFlipped(CVImageBufferRef b);
CGColorSpaceRef CVImageBufferGetColorSpace(CVImageBufferRef b)
{
    return (CGColorSpaceRef)CVBufferGetAttachment(b, kCVImageBufferCGColorSpaceKey, NULL);
}
CGColorSpaceRef CVImageBufferCreateColorSpaceFromAttachments(CFDictionaryRef attachments)
{
    NSDictionary *d = (NSDictionary *)attachments;
    id cs = [d objectForKey:@"CGColorSpace"];
    if (cs)
        return (CGColorSpaceRef)[cs retain];
    NSString *primaries = [d objectForKey:@"CVImageBufferColorPrimaries"];
    if ([primaries isEqual:@"P3_D65"] || [primaries isEqual:@"DCI_P3"])
        return CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    if (primaries || [d objectForKey:@"CVImageBufferTransferFunction"])
        return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return NULL;
}

/* ---- pools ---------------------------------------------------------------------------------- */

@interface FerryCVPixelBufferPool : NSObject {
  @public
    NSDictionary *_attributes, *_bufferAttributes;
    NSMutableArray *_buffers;  /* every buffer it made that is still alive in it */
    NSMutableArray *_freedAt;  /* when each was last seen free (NSDate or NSNull) */
    size_t _width, _height;
    OSType _format;
    double _maxAge;
    pthread_mutex_t _lock;
}
@end

@implementation FerryCVPixelBufferPool
- (void)dealloc
{
    [_attributes release];
    [_bufferAttributes release];
    [_buffers release];
    [_freedAt release];
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}
@end

#define POOL(ref) ((FerryCVPixelBufferPool *)(ref))
CFTypeID CVPixelBufferPoolGetTypeID(void) { return (CFTypeID)[FerryCVPixelBufferPool class]; }
CVPixelBufferPoolRef CVPixelBufferPoolRetain(CVPixelBufferPoolRef p)
{
    return p ? (CVPixelBufferPoolRef)[(id)p retain] : NULL;
}
void CVPixelBufferPoolRelease(CVPixelBufferPoolRef p)
{
    if (p)
        [(id)p release];
}

CVReturn CVPixelBufferPoolCreate(CFAllocatorRef allocator, CFDictionaryRef poolAttrs, CFDictionaryRef bufferAttrs,
                                 CVPixelBufferPoolRef *out)
{
    if (!out)
        return kCVReturnInvalidArgument;
    *out = NULL;
    NSDictionary *b = (NSDictionary *)bufferAttrs;
    size_t w = number_of(b, @"Width", 0), h = number_of(b, @"Height", 0);
    id fmt = [b isKindOfClass:[NSDictionary class]] ? [b objectForKey:@"PixelFormatType"] : nil;
    if ([fmt isKindOfClass:[NSArray class]])
        fmt = [(NSArray *)fmt firstObject];
    if (!w || !h || ![fmt respondsToSelector:@selector(unsignedIntValue)])
        return kCVReturnInvalidPixelBufferAttributes;
    if (!format_of([fmt unsignedIntValue]))
        return kCVReturnInvalidPixelFormat;
    FerryCVPixelBufferPool *p = [[FerryCVPixelBufferPool alloc] init];
    p->_attributes = poolAttrs ? [(NSDictionary *)poolAttrs copy] : [[NSDictionary alloc] init];
    p->_bufferAttributes = [b copy];
    p->_buffers = [[NSMutableArray alloc] init];
    p->_freedAt = [[NSMutableArray alloc] init];
    p->_width = w;
    p->_height = h;
    p->_format = [fmt unsignedIntValue];
    id age = [p->_attributes objectForKey:@"MaximumBufferAge"];
    p->_maxAge = age ? num(age) : 1.0;
    pthread_mutex_init(&p->_lock, NULL);
    size_t minimum = number_of(p->_attributes, @"MinimumBufferCount", 0);
    for (size_t i = 0; i < minimum && i < 64; i++) {
        FerryCVPixelBuffer *one = nil;
        if (make_on_surface(w, h, p->_format, p->_bufferAttributes, &one) != kCVReturnSuccess)
            break;
        [p->_buffers addObject:one];
        [p->_freedAt addObject:[NSNull null]];
        [one release];
    }
    *out = (CVPixelBufferPoolRef)p;
    return kCVReturnSuccess;
}

CFDictionaryRef CVPixelBufferPoolGetAttributes(CVPixelBufferPoolRef p)
{
    return p ? (CFDictionaryRef)POOL(p)->_attributes : NULL;
}
CFDictionaryRef CVPixelBufferPoolGetPixelBufferAttributes(CVPixelBufferPoolRef p)
{
    return p ? (CFDictionaryRef)POOL(p)->_bufferAttributes : NULL;
}

/* Buffers only the pool holds are free; those free longer than the
 * maximum age are let go. Called with the pool's lock held. */
static void pool_age(FerryCVPixelBufferPool *p, BOOL all)
{
    NSDate *now = [NSDate date];
    for (NSInteger i = (NSInteger)p->_buffers.count - 1; i >= 0; i--) {
        id b = [p->_buffers objectAtIndex:(NSUInteger)i];
        if ([b retainCount] != 1) {
            [p->_freedAt replaceObjectAtIndex:(NSUInteger)i withObject:[NSNull null]];
            continue;
        }
        id since = [p->_freedAt objectAtIndex:(NSUInteger)i];
        if (since == [NSNull null]) {
            [p->_freedAt replaceObjectAtIndex:(NSUInteger)i withObject:now];
            since = now;
        }
        if (all || (p->_maxAge > 0 && [now timeIntervalSinceDate:since] > p->_maxAge)) {
            [p->_buffers removeObjectAtIndex:(NSUInteger)i];
            [p->_freedAt removeObjectAtIndex:(NSUInteger)i];
        }
    }
}

CVReturn CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(CFAllocatorRef allocator, CVPixelBufferPoolRef pool,
                                                             CFDictionaryRef aux, CVPixelBufferRef *out)
{
    if (!out || !pool)
        return kCVReturnInvalidArgument;
    *out = NULL;
    FerryCVPixelBufferPool *p = POOL(pool);
    size_t threshold = number_of((NSDictionary *)aux, @"kCVPixelBufferPoolAllocationThresholdKey", 0);
    CVReturn r = kCVReturnSuccess;
    pthread_mutex_lock(&p->_lock);
    @autoreleasepool {
        pool_age(p, NO);
        FerryCVPixelBuffer *found = nil;
        for (FerryCVPixelBuffer *b in p->_buffers)
            if ([b retainCount] == 1) {
                found = b;
                break;
            }
        if (found) {
            [found retain];
            CVBufferRemoveAllAttachments((CVBufferRef)found);
            [p->_freedAt replaceObjectAtIndex:[p->_buffers indexOfObjectIdenticalTo:found] withObject:[NSNull null]];
        } else if (threshold && p->_buffers.count >= threshold) {
            r = kCVReturnWouldExceedAllocationThreshold;
        } else {
            r = make_on_surface(p->_width, p->_height, p->_format, p->_bufferAttributes, &found);
            if (r == kCVReturnSuccess) {
                [p->_buffers addObject:found];
                [p->_freedAt addObject:[NSNull null]];
            }
        }
        *out = (CVPixelBufferRef)found;
    }
    pthread_mutex_unlock(&p->_lock);
    return r;
}

CVReturn CVPixelBufferPoolCreatePixelBuffer(CFAllocatorRef allocator, CVPixelBufferPoolRef pool, CVPixelBufferRef *out)
{
    return CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(allocator, pool, NULL, out);
}

void CVPixelBufferPoolFlush(CVPixelBufferPoolRef pool, CVPixelBufferPoolFlushFlags options)
{
    if (!pool)
        return;
    FerryCVPixelBufferPool *p = POOL(pool);
    pthread_mutex_lock(&p->_lock);
    @autoreleasepool {
        pool_age(p, (options & kCVPixelBufferPoolFlushExcessBuffers) != 0);
    }
    pthread_mutex_unlock(&p->_lock);
}

/* ---- pixel format descriptions --------------------------------------------------------------- */

static NSMutableDictionary *registered;
static pthread_mutex_t registered_lock = PTHREAD_MUTEX_INITIALIZER;

CFDictionaryRef CVPixelFormatDescriptionCreateWithPixelFormatType(CFAllocatorRef allocator, OSType type)
{
    pthread_mutex_lock(&registered_lock);
    NSDictionary *own = [[registered objectForKey:@(type)] retain];
    pthread_mutex_unlock(&registered_lock);
    if (own)
        return (CFDictionaryRef)own;
    const struct format *f = format_of(type);
    if (!f)
        return NULL;
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [d setObject:[NSString stringWithUTF8String:f->name] forKey:@"Name"];
    [d setObject:@(type) forKey:@"PixelFormat"];
    [d setObject:@(f->alpha != 0) forKey:@"ContainsAlpha"];
    [d setObject:@(f->ycbcr != 0) forKey:@"ContainsYCbCr"];
    [d setObject:@(f->rgb != 0) forKey:@"ContainsRGB"];
    [d setObject:@YES forKey:@"IOSurfaceCoreAnimationCompatibility"];
    if (f->ycbcr)
        [d setObject:f->fullRange ? @"FullRange" : @"VideoRange" forKey:@"ComponentRange"];
    NSMutableArray *planes = [NSMutableArray array];
    for (int i = 0; i < (f->planes ? f->planes : 1); i++) {
        const struct plane_layout *l = &f->layout[i];
        NSMutableDictionary *pd = [NSMutableDictionary dictionary];
        [pd setObject:@(l->bytesPerBlock * 8) forKey:@"BitsPerBlock"];
        if (l->blockWidth != 1)
            [pd setObject:@(l->blockWidth) forKey:@"BlockWidth"];
        if (l->hsub != 1)
            [pd setObject:@(l->hsub) forKey:@"HorizontalSubsampling"];
        if (l->vsub != 1)
            [pd setObject:@(l->vsub) forKey:@"VerticalSubsampling"];
        [planes addObject:pd];
    }
    if (f->planes)
        [d setObject:planes forKey:@"Planes"];
    else
        [d addEntriesFromDictionary:[planes firstObject]];
    if (f->glFormat) {
        [d setObject:@(f->glFormat) forKey:@"OpenGLFormat"];
        [d setObject:@(f->glType) forKey:@"OpenGLType"];
        [d setObject:@(f->glInternal) forKey:@"OpenGLInternalFormat"];
        [d setObject:@YES forKey:@"OpenGLCompatibility"];
    }
    if (f->cgBitmapInfo) {
        [d setObject:@(f->cgBitmapInfo) forKey:@"CGBitmapInfo"];
        [d setObject:@YES forKey:@"CGBitmapContextCompatibility"];
        [d setObject:@YES forKey:@"CGImageCompatibility"];
    }
    return (CFDictionaryRef)d;
}

CFArrayRef CVPixelFormatDescriptionArrayCreateWithAllPixelFormatTypes(CFAllocatorRef allocator)
{
    NSMutableArray *a = [[NSMutableArray alloc] init];
    for (size_t i = 0; i < sizeof formats / sizeof *formats; i++)
        [a addObject:@(formats[i].type)];
    pthread_mutex_lock(&registered_lock);
    for (NSNumber *n in registered)
        if (![a containsObject:n])
            [a addObject:n];
    pthread_mutex_unlock(&registered_lock);
    return (CFArrayRef)a;
}

void CVPixelFormatDescriptionRegisterDescriptionWithPixelFormatType(CFDictionaryRef description, OSType type)
{
    if (!description)
        return;
    pthread_mutex_lock(&registered_lock);
    if (!registered)
        registered = [[NSMutableDictionary alloc] init];
    [registered setObject:[[(NSDictionary *)description copy] autorelease] forKey:@(type)];
    pthread_mutex_unlock(&registered_lock);
}

/* ---- OpenGL textures from pixel buffers -------------------------------------------------------- */

#define GL_TEXTURE_RECTANGLE_ 0x84F5
#define GL_TEXTURE_BINDING_RECTANGLE_ 0x84F6
#define GL_TEXTURE_MIN_FILTER_ 0x2801
#define GL_TEXTURE_MAG_FILTER_ 0x2800
#define GL_TEXTURE_WRAP_S_ 0x2802
#define GL_TEXTURE_WRAP_T_ 0x2803
#define GL_LINEAR_ 0x2601
#define GL_CLAMP_TO_EDGE_ 0x812F
void glGenTextures(GLsizei, GLuint *);
void glDeleteTextures(GLsizei, const GLuint *);
void glBindTexture(GLenum, GLuint);
void glTexParameteri(GLenum, GLenum, GLint);
void glGetIntegerv(GLenum, GLint *);

@interface FerryCVOpenGLTextureCache : NSObject {
  @public
    CGLContextObj _context;
    CGLPixelFormatObj _pixelFormat;
    NSDictionary *_attributes;
    GLuint *_dead; /* textures let go, deleted in the cache's context */
    size_t _deadCount, _deadSize;
    pthread_mutex_t _lock;
}
@end

@interface FerryCVOpenGLTexture : FerryCVBuffer {
  @public
    FerryCVOpenGLTextureCache *_cache;
    CVImageBufferRef _image;
    GLuint _name;
    GLenum _target;
    size_t _width, _height;
}
@end

static void delete_dead_locked(FerryCVOpenGLTextureCache *c)
{
    if (c->_deadCount)
        glDeleteTextures((GLsizei)c->_deadCount, c->_dead);
    c->_deadCount = 0;
}

@implementation FerryCVOpenGLTextureCache
- (void)dealloc
{
    if (_deadCount) {
        CGLContextObj saved = CGLGetCurrentContext();
        CGLSetCurrentContext(_context);
        delete_dead_locked(self);
        CGLSetCurrentContext(saved);
    }
    free(_dead);
    CGLReleaseContext(_context);
    CGLReleasePixelFormat(_pixelFormat);
    [_attributes release];
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}
@end

@implementation FerryCVOpenGLTexture
- (void)dealloc
{
    if (_name && _cache) {
        pthread_mutex_lock(&_cache->_lock);
        if (_cache->_deadCount == _cache->_deadSize) {
            size_t n = _cache->_deadSize ? _cache->_deadSize * 2 : 16;
            GLuint *d = realloc(_cache->_dead, n * sizeof *d);
            if (d) {
                _cache->_dead = d;
                _cache->_deadSize = n;
            }
        }
        if (_cache->_deadCount < _cache->_deadSize)
            _cache->_dead[_cache->_deadCount++] = _name;
        pthread_mutex_unlock(&_cache->_lock);
    }
    if (_image)
        CFRelease(_image);
    [_cache release];
    [super dealloc];
}
@end

#define TEX(ref) ((FerryCVOpenGLTexture *)(ref))
static BOOL is_tex(CVOpenGLTextureRef t) { return t && [(id)t isKindOfClass:[FerryCVOpenGLTexture class]]; }

CFTypeID CVOpenGLTextureGetTypeID(void) { return (CFTypeID)[FerryCVOpenGLTexture class]; }
CVOpenGLTextureRef CVOpenGLTextureRetain(CVOpenGLTextureRef t) { return CVBufferRetain(t); }
void CVOpenGLTextureRelease(CVOpenGLTextureRef t) { CVBufferRelease(t); }
GLenum CVOpenGLTextureGetTarget(CVOpenGLTextureRef t) { return is_tex(t) ? TEX(t)->_target : 0; }
GLuint CVOpenGLTextureGetName(CVOpenGLTextureRef t) { return is_tex(t) ? TEX(t)->_name : 0; }
/* the texture's first row is the image's top one */
Boolean CVOpenGLTextureIsFlipped(CVOpenGLTextureRef t) { return is_tex(t); }
Boolean CVImageBufferIsFlipped(CVImageBufferRef b) { return is_tex(b); }
void CVOpenGLTextureGetCleanTexCoords(CVOpenGLTextureRef t, GLfloat ll[2], GLfloat lr[2], GLfloat ur[2], GLfloat ul[2])
{
    GLfloat w = is_tex(t) ? (GLfloat)TEX(t)->_width : 0, h = is_tex(t) ? (GLfloat)TEX(t)->_height : 0;
    if (ll)
        ll[0] = 0, ll[1] = h;
    if (lr)
        lr[0] = w, lr[1] = h;
    if (ur)
        ur[0] = w, ur[1] = 0;
    if (ul)
        ul[0] = 0, ul[1] = 0;
}

CFTypeID CVOpenGLTextureCacheGetTypeID(void) { return (CFTypeID)[FerryCVOpenGLTextureCache class]; }
CVOpenGLTextureCacheRef CVOpenGLTextureCacheRetain(CVOpenGLTextureCacheRef c)
{
    return c ? (CVOpenGLTextureCacheRef)[(id)c retain] : NULL;
}
void CVOpenGLTextureCacheRelease(CVOpenGLTextureCacheRef c)
{
    if (c)
        [(id)c release];
}

CVReturn CVOpenGLTextureCacheCreate(CFAllocatorRef allocator, CFDictionaryRef cacheAttributes, CGLContextObj ctx,
                                    CGLPixelFormatObj pix, CFDictionaryRef textureAttributes,
                                    CVOpenGLTextureCacheRef *out)
{
    if (!out || !ctx)
        return kCVReturnInvalidArgument;
    FerryCVOpenGLTextureCache *c = [[FerryCVOpenGLTextureCache alloc] init];
    c->_context = CGLRetainContext(ctx);
    c->_pixelFormat = CGLRetainPixelFormat(pix ? pix : CGLGetPixelFormat(ctx));
    c->_attributes = cacheAttributes ? [(NSDictionary *)cacheAttributes copy] : [[NSDictionary alloc] init];
    pthread_mutex_init(&c->_lock, NULL);
    *out = (CVOpenGLTextureCacheRef)c;
    return kCVReturnSuccess;
}

/* A rectangle texture with the buffer's image as it is now, made in the
 * cache's context (made current for the call if another is). */
CVReturn CVOpenGLTextureCacheCreateTextureFromImage(CFAllocatorRef allocator, CVOpenGLTextureCacheRef cache,
                                                    CVImageBufferRef image, CFDictionaryRef attributes,
                                                    CVOpenGLTextureRef *out)
{
    if (!out || !cache || !is_pb(image))
        return kCVReturnInvalidArgument;
    *out = NULL;
    FerryCVOpenGLTextureCache *c = (FerryCVOpenGLTextureCache *)cache;
    FerryCVPixelBuffer *p = PB(image);
    const struct format *f = format_of(p->_format);
    if (!f || f->planes || !f->glFormat)
        return kCVReturnPixelBufferNotOpenGLCompatible;
    IOSurfaceRef s = p->_surface;
    IOSurfaceRef made = NULL;
    if (!s) {
        /* a buffer of the program's own memory: through a surface of its size */
        CVPixelBufferRef copy = NULL;
        if (CVPixelBufferCreate(NULL, p->_width, p->_height, p->_format, NULL, &copy) != kCVReturnSuccess)
            return kCVReturnAllocationFailed;
        size_t rb = CVPixelBufferGetBytesPerRow(copy), n = rb < p->_bytesPerRow ? rb : p->_bytesPerRow;
        for (size_t y = 0; y < p->_height; y++)
            memcpy((unsigned char *)CVPixelBufferGetBaseAddress(copy) + y * rb, p->_base + y * p->_bytesPerRow, n);
        made = s = (IOSurfaceRef)CFRetain(CVPixelBufferGetIOSurface(copy));
        CVPixelBufferRelease(copy);
    }
    CGLContextObj saved = CGLGetCurrentContext();
    if (saved != c->_context)
        CGLSetCurrentContext(c->_context);
    pthread_mutex_lock(&c->_lock);
    delete_dead_locked(c);
    pthread_mutex_unlock(&c->_lock);
    GLint old = 0;
    GLuint name = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE_, &old);
    glGenTextures(1, &name);
    glBindTexture(GL_TEXTURE_RECTANGLE_, name);
    glTexParameteri(GL_TEXTURE_RECTANGLE_, GL_TEXTURE_MIN_FILTER_, GL_LINEAR_);
    glTexParameteri(GL_TEXTURE_RECTANGLE_, GL_TEXTURE_MAG_FILTER_, GL_LINEAR_);
    glTexParameteri(GL_TEXTURE_RECTANGLE_, GL_TEXTURE_WRAP_S_, GL_CLAMP_TO_EDGE_);
    glTexParameteri(GL_TEXTURE_RECTANGLE_, GL_TEXTURE_WRAP_T_, GL_CLAMP_TO_EDGE_);
    CGLError e = CGLTexImageIOSurface2D(c->_context, GL_TEXTURE_RECTANGLE_, f->glInternal, (GLsizei)p->_width,
                                        (GLsizei)p->_height, f->glFormat, f->glType, s, 0);
    glBindTexture(GL_TEXTURE_RECTANGLE_, (GLuint)old);
    if (saved != c->_context)
        CGLSetCurrentContext(saved);
    if (made)
        CFRelease(made);
    if (e != kCGLNoError) {
        pthread_mutex_lock(&c->_lock);
        if (c->_deadCount < c->_deadSize)
            c->_dead[c->_deadCount++] = name;
        pthread_mutex_unlock(&c->_lock);
        return kCVReturnPixelBufferNotOpenGLCompatible;
    }
    FerryCVOpenGLTexture *t = [[FerryCVOpenGLTexture alloc] init];
    t->_cache = [c retain];
    t->_image = (CVImageBufferRef)CFRetain(image);
    t->_name = name;
    t->_target = GL_TEXTURE_RECTANGLE_;
    t->_width = p->_width;
    t->_height = p->_height;
    CVBufferPropagateAttachments(image, (CVBufferRef)t);
    *out = (CVOpenGLTextureRef)t;
    return kCVReturnSuccess;
}

void CVOpenGLTextureCacheFlush(CVOpenGLTextureCacheRef cache, CVOptionFlags options)
{
    if (!cache)
        return;
    FerryCVOpenGLTextureCache *c = (FerryCVOpenGLTextureCache *)cache;
    pthread_mutex_lock(&c->_lock);
    if (c->_deadCount && CGLGetCurrentContext() == c->_context)
        delete_dead_locked(c);
    pthread_mutex_unlock(&c->_lock);
}
