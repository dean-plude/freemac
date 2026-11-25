/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Core Video (freemac 1.235, Ferry 0.59.0): buffers and their
 * attachments, pixel buffers (packed and planar, in memory or on an
 * IOSurface) and their pools, display links, host time, and OpenGL
 * textures made from pixel buffers. Written for freemac from Apple's
 * public Core Video reference; not Apple's header. Every call declared
 * here is implemented in ferry/corevideo. */
#ifndef _FERRY_COREVIDEO_COREVIDEO_H_
#define _FERRY_COREVIDEO_COREVIDEO_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <MacTypes.h>
#include <IOSurface/IOSurface.h>
#include <OpenGL/OpenGL.h>

__FERRY_BEGIN

#define COREVIDEO_SUPPORTS_OPENGL 1
#define COREVIDEO_SUPPORTS_IOSURFACE 1
#define COREVIDEO_SUPPORTS_DISPLAYLINK 1
#define CV_EXPORT extern
#define CV_INLINE static inline
#define CV_RETURNS_RETAINED CF_RETURNS_RETAINED
#define CV_RETURNS_RETAINED_PARAMETER
#define CV_RELEASES_ARGUMENT

/* ---- base types (CVBase.h) ------------------------------------------------------ */

typedef int32_t CVReturn;
typedef uint64_t CVOptionFlags;

typedef struct {
    int16_t subframes;
    int16_t subframeDivisor;
    uint32_t counter;
    uint32_t type;
    uint32_t flags;
    int16_t hours;
    int16_t minutes;
    int16_t seconds;
    int16_t frames;
} CVSMPTETime;

enum {
    kCVSMPTETimeType24 = 0,
    kCVSMPTETimeType25 = 1,
    kCVSMPTETimeType30Drop = 2,
    kCVSMPTETimeType30 = 3,
    kCVSMPTETimeType2997 = 4,
    kCVSMPTETimeType2997Drop = 5,
    kCVSMPTETimeType60 = 6,
    kCVSMPTETimeType5994 = 7,
};
enum { kCVSMPTETimeValid = 1 << 0, kCVSMPTETimeRunning = 1 << 1 };

typedef struct {
    int64_t timeValue;
    int32_t timeScale;
    int32_t flags;
} CVTime;
enum { kCVTimeIsIndefinite = 1 << 0 };
extern const CVTime kCVZeroTime;
extern const CVTime kCVIndefiniteTime;

typedef struct {
    uint32_t version;
    int32_t videoTimeScale;
    int64_t videoTime;
    uint64_t hostTime;
    double rateScalar;
    int64_t videoRefreshPeriod;
    CVSMPTETime smpteTime;
    uint64_t flags;
    uint64_t reserved;
} CVTimeStamp;

enum {
    kCVTimeStampVideoTimeValid = 1 << 0,
    kCVTimeStampHostTimeValid = 1 << 1,
    kCVTimeStampSMPTETimeValid = 1 << 2,
    kCVTimeStampVideoRefreshPeriodValid = 1 << 3,
    kCVTimeStampRateScalarValid = 1 << 4,
    kCVTimeStampTopField = 1 << 16,
    kCVTimeStampBottomField = 1 << 17,
    kCVTimeStampVideoHostTimeValid = kCVTimeStampVideoTimeValid | kCVTimeStampHostTimeValid,
    kCVTimeStampIsInterlaced = kCVTimeStampTopField | kCVTimeStampBottomField,
};

/* ---- results (CVReturn.h) --------------------------------------------------------- */

enum {
    kCVReturnSuccess = 0,
    kCVReturnFirst = -6660,
    kCVReturnError = kCVReturnFirst,
    kCVReturnInvalidArgument = -6661,
    kCVReturnAllocationFailed = -6662,
    kCVReturnUnsupported = -6663,
    kCVReturnInvalidDisplay = -6670,
    kCVReturnDisplayLinkAlreadyRunning = -6671,
    kCVReturnDisplayLinkNotRunning = -6672,
    kCVReturnDisplayLinkCallbacksNotSet = -6673,
    kCVReturnInvalidPixelFormat = -6680,
    kCVReturnInvalidSize = -6681,
    kCVReturnInvalidPixelBufferAttributes = -6682,
    kCVReturnPixelBufferNotOpenGLCompatible = -6683,
    kCVReturnPixelBufferNotMetalCompatible = -6684,
    kCVReturnWouldExceedAllocationThreshold = -6689,
    kCVReturnPoolAllocationFailed = -6690,
    kCVReturnInvalidPoolAttributes = -6691,
    kCVReturnRetry = -6692,
    kCVReturnLast = -6699,
};

/* ---- host time (CVHostTime.h) ---------------------------------------------------- */

uint64_t CVGetCurrentHostTime(void);
double CVGetHostClockFrequency(void);
uint32_t CVGetHostClockMinimumTimeDelta(void);

/* ---- buffers and their attachments (CVBuffer.h) ---------------------------------- */

typedef struct CF_BRIDGED_TYPE(id) __CVBuffer *CVBufferRef;

typedef CF_ENUM(uint32_t, CVAttachmentMode) {
    kCVAttachmentMode_ShouldNotPropagate = 0,
    kCVAttachmentMode_ShouldPropagate = 1,
};

extern const CFStringRef kCVBufferPropagatedAttachmentsKey;
extern const CFStringRef kCVBufferNonPropagatedAttachmentsKey;
extern const CFStringRef kCVBufferMovieTimeKey;
extern const CFStringRef kCVBufferTimeValueKey;
extern const CFStringRef kCVBufferTimeScaleKey;

CVBufferRef CVBufferRetain(CVBufferRef buffer);
void CVBufferRelease(CVBufferRef buffer);
void CVBufferSetAttachment(CVBufferRef buffer, CFStringRef key, CFTypeRef value, CVAttachmentMode attachmentMode);
CFTypeRef CVBufferGetAttachment(CVBufferRef buffer, CFStringRef key, CVAttachmentMode *attachmentMode);
CFTypeRef CVBufferCopyAttachment(CVBufferRef buffer, CFStringRef key, CVAttachmentMode *attachmentMode)
    CF_RETURNS_RETAINED;
void CVBufferRemoveAttachment(CVBufferRef buffer, CFStringRef key);
void CVBufferRemoveAllAttachments(CVBufferRef buffer);
CFDictionaryRef CVBufferGetAttachments(CVBufferRef buffer, CVAttachmentMode attachmentMode);
CFDictionaryRef CVBufferCopyAttachments(CVBufferRef buffer, CVAttachmentMode attachmentMode) CF_RETURNS_RETAINED;
void CVBufferSetAttachments(CVBufferRef buffer, CFDictionaryRef theAttachments, CVAttachmentMode attachmentMode);
void CVBufferPropagateAttachments(CVBufferRef sourceBuffer, CVBufferRef destinationBuffer);
Boolean CVBufferHasAttachment(CVBufferRef buffer, CFStringRef key);

/* ---- image buffers (CVImageBuffer.h) ---------------------------------------------- */

typedef CVBufferRef CVImageBufferRef;

CGSize CVImageBufferGetEncodedSize(CVImageBufferRef imageBuffer);
CGSize CVImageBufferGetDisplaySize(CVImageBufferRef imageBuffer);
CGRect CVImageBufferGetCleanRect(CVImageBufferRef imageBuffer);
Boolean CVImageBufferIsFlipped(CVImageBufferRef imageBuffer);
CGColorSpaceRef CVImageBufferGetColorSpace(CVImageBufferRef imageBuffer);
CGColorSpaceRef CVImageBufferCreateColorSpaceFromAttachments(CFDictionaryRef attachments) CF_RETURNS_RETAINED;

extern const CFStringRef kCVImageBufferCGColorSpaceKey;
extern const CFStringRef kCVImageBufferCleanApertureKey;
extern const CFStringRef kCVImageBufferCleanApertureWidthKey;
extern const CFStringRef kCVImageBufferCleanApertureHeightKey;
extern const CFStringRef kCVImageBufferCleanApertureHorizontalOffsetKey;
extern const CFStringRef kCVImageBufferCleanApertureVerticalOffsetKey;
extern const CFStringRef kCVImageBufferPreferredCleanApertureKey;
extern const CFStringRef kCVImageBufferFieldCountKey;
extern const CFStringRef kCVImageBufferFieldDetailKey;
extern const CFStringRef kCVImageBufferFieldDetailTemporalTopFirst;
extern const CFStringRef kCVImageBufferFieldDetailTemporalBottomFirst;
extern const CFStringRef kCVImageBufferFieldDetailSpatialFirstLineEarly;
extern const CFStringRef kCVImageBufferFieldDetailSpatialFirstLineLate;
extern const CFStringRef kCVImageBufferPixelAspectRatioKey;
extern const CFStringRef kCVImageBufferPixelAspectRatioHorizontalSpacingKey;
extern const CFStringRef kCVImageBufferPixelAspectRatioVerticalSpacingKey;
extern const CFStringRef kCVImageBufferDisplayDimensionsKey;
extern const CFStringRef kCVImageBufferDisplayWidthKey;
extern const CFStringRef kCVImageBufferDisplayHeightKey;
extern const CFStringRef kCVImageBufferGammaLevelKey;
extern const CFStringRef kCVImageBufferICCProfileKey;
extern const CFStringRef kCVImageBufferYCbCrMatrixKey;
extern const CFStringRef kCVImageBufferYCbCrMatrix_ITU_R_709_2;
extern const CFStringRef kCVImageBufferYCbCrMatrix_ITU_R_601_4;
extern const CFStringRef kCVImageBufferYCbCrMatrix_SMPTE_240M_1995;
extern const CFStringRef kCVImageBufferYCbCrMatrix_DCI_P3;
extern const CFStringRef kCVImageBufferYCbCrMatrix_P3_D65;
extern const CFStringRef kCVImageBufferYCbCrMatrix_ITU_R_2020;
extern const CFStringRef kCVImageBufferColorPrimariesKey;
extern const CFStringRef kCVImageBufferColorPrimaries_ITU_R_709_2;
extern const CFStringRef kCVImageBufferColorPrimaries_EBU_3213;
extern const CFStringRef kCVImageBufferColorPrimaries_SMPTE_C;
extern const CFStringRef kCVImageBufferColorPrimaries_P22;
extern const CFStringRef kCVImageBufferColorPrimaries_DCI_P3;
extern const CFStringRef kCVImageBufferColorPrimaries_P3_D65;
extern const CFStringRef kCVImageBufferColorPrimaries_ITU_R_2020;
extern const CFStringRef kCVImageBufferTransferFunctionKey;
extern const CFStringRef kCVImageBufferTransferFunction_ITU_R_709_2;
extern const CFStringRef kCVImageBufferTransferFunction_SMPTE_240M_1995;
extern const CFStringRef kCVImageBufferTransferFunction_UseGamma;
extern const CFStringRef kCVImageBufferTransferFunction_sRGB;
extern const CFStringRef kCVImageBufferTransferFunction_ITU_R_2020;
extern const CFStringRef kCVImageBufferTransferFunction_SMPTE_ST_428_1;
extern const CFStringRef kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ;
extern const CFStringRef kCVImageBufferTransferFunction_ITU_R_2100_HLG;
extern const CFStringRef kCVImageBufferTransferFunction_Linear;
extern const CFStringRef kCVImageBufferChromaLocationTopFieldKey;
extern const CFStringRef kCVImageBufferChromaLocationBottomFieldKey;
extern const CFStringRef kCVImageBufferChromaLocation_Left;
extern const CFStringRef kCVImageBufferChromaLocation_Center;
extern const CFStringRef kCVImageBufferChromaLocation_TopLeft;
extern const CFStringRef kCVImageBufferChromaLocation_Top;
extern const CFStringRef kCVImageBufferChromaLocation_BottomLeft;
extern const CFStringRef kCVImageBufferChromaLocation_Bottom;
extern const CFStringRef kCVImageBufferChromaLocation_DV420;
extern const CFStringRef kCVImageBufferChromaSubsamplingKey;
extern const CFStringRef kCVImageBufferChromaSubsampling_420;
extern const CFStringRef kCVImageBufferChromaSubsampling_422;
extern const CFStringRef kCVImageBufferChromaSubsampling_411;
extern const CFStringRef kCVImageBufferAlphaChannelIsOpaque;
extern const CFStringRef kCVImageBufferMasteringDisplayColorVolumeKey;
extern const CFStringRef kCVImageBufferContentLightLevelInfoKey;

/* ---- pixel buffers (CVPixelBuffer.h) ---------------------------------------------- */

typedef CVImageBufferRef CVPixelBufferRef;

enum {
    kCVPixelFormatType_1Monochrome = 0x00000001,
    kCVPixelFormatType_2Indexed = 0x00000002,
    kCVPixelFormatType_4Indexed = 0x00000004,
    kCVPixelFormatType_8Indexed = 0x00000008,
    kCVPixelFormatType_16BE555 = 0x00000010,
    kCVPixelFormatType_16LE555 = 'L555',
    kCVPixelFormatType_16BE565 = 'B565',
    kCVPixelFormatType_16LE565 = 'L565',
    kCVPixelFormatType_24RGB = 0x00000018,
    kCVPixelFormatType_24BGR = '24BG',
    kCVPixelFormatType_32ARGB = 0x00000020,
    kCVPixelFormatType_32BGRA = 'BGRA',
    kCVPixelFormatType_32ABGR = 'ABGR',
    kCVPixelFormatType_32RGBA = 'RGBA',
    kCVPixelFormatType_64ARGB = 'b64a',
    kCVPixelFormatType_64RGBALE = 'l64r',
    kCVPixelFormatType_48RGB = 'b48r',
    kCVPixelFormatType_32AlphaGray = 'b32a',
    kCVPixelFormatType_16Gray = 'b16g',
    kCVPixelFormatType_30RGB = 'R10k',
    kCVPixelFormatType_30RGBLEPackedWideGamut = 'w30r',
    kCVPixelFormatType_ARGB2101010LEPacked = 'l10r',
    kCVPixelFormatType_422YpCbCr8 = '2vuy',
    kCVPixelFormatType_4444YpCbCrA8 = 'v408',
    kCVPixelFormatType_4444YpCbCrA8R = 'r408',
    kCVPixelFormatType_4444AYpCbCr8 = 'y408',
    kCVPixelFormatType_4444AYpCbCr16 = 'y416',
    kCVPixelFormatType_444YpCbCr8 = 'v308',
    kCVPixelFormatType_422YpCbCr16 = 'v216',
    kCVPixelFormatType_422YpCbCr10 = 'v210',
    kCVPixelFormatType_444YpCbCr10 = 'v410',
    kCVPixelFormatType_420YpCbCr8Planar = 'y420',
    kCVPixelFormatType_420YpCbCr8PlanarFullRange = 'f420',
    kCVPixelFormatType_422YpCbCr_4A_8BiPlanar = 'a2vy',
    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange = '420v',
    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange = '420f',
    kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange = '422v',
    kCVPixelFormatType_422YpCbCr8BiPlanarFullRange = '422f',
    kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange = '444v',
    kCVPixelFormatType_444YpCbCr8BiPlanarFullRange = '444f',
    kCVPixelFormatType_422YpCbCr8_yuvs = 'yuvs',
    kCVPixelFormatType_422YpCbCr8FullRange = 'yuvf',
    kCVPixelFormatType_OneComponent8 = 'L008',
    kCVPixelFormatType_TwoComponent8 = '2C08',
    kCVPixelFormatType_OneComponent16Half = 'L00h',
    kCVPixelFormatType_OneComponent32Float = 'L00f',
    kCVPixelFormatType_TwoComponent16Half = '2C0h',
    kCVPixelFormatType_TwoComponent32Float = '2C0f',
    kCVPixelFormatType_64RGBAHalf = 'RGhA',
    kCVPixelFormatType_128RGBAFloat = 'RGfA',
    kCVPixelFormatType_OneComponent16 = 'L016',
    kCVPixelFormatType_TwoComponent16 = '2C16',
    kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange = 'x420',
    kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange = 'x422',
    kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange = 'x444',
    kCVPixelFormatType_420YpCbCr10BiPlanarFullRange = 'xf20',
    kCVPixelFormatType_422YpCbCr10BiPlanarFullRange = 'xf22',
    kCVPixelFormatType_444YpCbCr10BiPlanarFullRange = 'xf44',
    kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar = 'v0a8',
};

typedef CF_OPTIONS(CVOptionFlags, CVPixelBufferLockFlags) {
    kCVPixelBufferLock_ReadOnly = 0x00000001,
};

/* the layouts GetBaseAddress points at for a planar buffer made by Core
 * Video; the offsets and row bytes are big-endian, as on a Mac */
typedef struct {
    int32_t offset;
    uint32_t rowBytes;
} CVPlanarComponentInfo;
typedef struct {
    CVPlanarComponentInfo componentInfo[1];
} CVPlanarPixelBufferInfo;
typedef struct {
    CVPlanarComponentInfo componentInfoY;
    CVPlanarComponentInfo componentInfoCb;
    CVPlanarComponentInfo componentInfoCr;
} CVPlanarPixelBufferInfo_YCbCrPlanar;
typedef struct {
    CVPlanarComponentInfo componentInfoY;
    CVPlanarComponentInfo componentInfoCbCr;
} CVPlanarPixelBufferInfo_YCbCrBiPlanar;

extern const CFStringRef kCVPixelBufferPixelFormatTypeKey;
extern const CFStringRef kCVPixelBufferMemoryAllocatorKey;
extern const CFStringRef kCVPixelBufferWidthKey;
extern const CFStringRef kCVPixelBufferHeightKey;
extern const CFStringRef kCVPixelBufferExtendedPixelsLeftKey;
extern const CFStringRef kCVPixelBufferExtendedPixelsTopKey;
extern const CFStringRef kCVPixelBufferExtendedPixelsRightKey;
extern const CFStringRef kCVPixelBufferExtendedPixelsBottomKey;
extern const CFStringRef kCVPixelBufferBytesPerRowAlignmentKey;
extern const CFStringRef kCVPixelBufferCGBitmapContextCompatibilityKey;
extern const CFStringRef kCVPixelBufferCGImageCompatibilityKey;
extern const CFStringRef kCVPixelBufferOpenGLCompatibilityKey;
extern const CFStringRef kCVPixelBufferPlaneAlignmentKey;
extern const CFStringRef kCVPixelBufferIOSurfacePropertiesKey;
extern const CFStringRef kCVPixelBufferOpenGLESCompatibilityKey;
extern const CFStringRef kCVPixelBufferMetalCompatibilityKey;
extern const CFStringRef kCVPixelBufferOpenGLTextureCacheCompatibilityKey;
extern const CFStringRef kCVPixelBufferOpenGLESTextureCacheCompatibilityKey;
extern const CFStringRef kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey;
extern const CFStringRef kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey;
extern const CFStringRef kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey;
extern const CFStringRef kCVPixelBufferIOSurfaceOpenGLESTextureCompatibilityKey;
extern const CFStringRef kCVPixelBufferIOSurfaceOpenGLESFBOCompatibilityKey;

typedef void (*CVPixelBufferReleaseBytesCallback)(void *releaseRefCon, const void *baseAddress);
typedef void (*CVPixelBufferReleasePlanarBytesCallback)(void *releaseRefCon, const void *dataPtr, size_t dataSize,
                                                         size_t numberOfPlanes, const void *planeAddresses[]);

CFTypeID CVPixelBufferGetTypeID(void);
CVPixelBufferRef CVPixelBufferRetain(CVPixelBufferRef texture);
void CVPixelBufferRelease(CVPixelBufferRef texture);
CVReturn CVPixelBufferCreateResolvedAttributesDictionary(CFAllocatorRef allocator, CFArrayRef attributes,
                                                         CFDictionaryRef *resolvedDictionaryOut);
CVReturn CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType,
                             CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferCreateWithBytes(CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType,
                                      void *baseAddress, size_t bytesPerRow,
                                      CVPixelBufferReleaseBytesCallback releaseCallback, void *releaseRefCon,
                                      CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferCreateWithPlanarBytes(CFAllocatorRef allocator, size_t width, size_t height,
                                            OSType pixelFormatType, void *dataPtr, size_t dataSize,
                                            size_t numberOfPlanes, void *planeBaseAddress[], size_t planeWidth[],
                                            size_t planeHeight[], size_t planeBytesPerRow[],
                                            CVPixelBufferReleasePlanarBytesCallback releaseCallback,
                                            void *releaseRefCon, CFDictionaryRef pixelBufferAttributes,
                                            CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferLockBaseAddress(CVPixelBufferRef pixelBuffer, CVPixelBufferLockFlags lockFlags);
CVReturn CVPixelBufferUnlockBaseAddress(CVPixelBufferRef pixelBuffer, CVPixelBufferLockFlags unlockFlags);
size_t CVPixelBufferGetWidth(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetHeight(CVPixelBufferRef pixelBuffer);
OSType CVPixelBufferGetPixelFormatType(CVPixelBufferRef pixelBuffer);
void *CVPixelBufferGetBaseAddress(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetBytesPerRow(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetDataSize(CVPixelBufferRef pixelBuffer);
Boolean CVPixelBufferIsPlanar(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetPlaneCount(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetWidthOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
size_t CVPixelBufferGetHeightOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
void *CVPixelBufferGetBaseAddressOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
size_t CVPixelBufferGetBytesPerRowOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
void CVPixelBufferGetExtendedPixels(CVPixelBufferRef pixelBuffer, size_t *extraColumnsOnLeft,
                                    size_t *extraColumnsOnRight, size_t *extraRowsOnTop, size_t *extraRowsOnBottom);
CVReturn CVPixelBufferFillExtendedPixels(CVPixelBufferRef pixelBuffer);
CFDictionaryRef CVPixelBufferCopyCreationAttributes(CVPixelBufferRef pixelBuffer) CF_RETURNS_RETAINED;

/* ---- on an IOSurface (CVPixelBufferIOSurface.h) ----------------------------------- */

IOSurfaceRef CVPixelBufferGetIOSurface(CVPixelBufferRef pixelBuffer);
CVReturn CVPixelBufferCreateWithIOSurface(CFAllocatorRef allocator, IOSurfaceRef surface,
                                          CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut);

/* ---- pools (CVPixelBufferPool.h) -------------------------------------------------- */

typedef struct CF_BRIDGED_TYPE(id) __CVPixelBufferPool *CVPixelBufferPoolRef;
typedef CF_OPTIONS(CVOptionFlags, CVPixelBufferPoolFlushFlags) {
    kCVPixelBufferPoolFlushExcessBuffers = 1,
};
extern const CFStringRef kCVPixelBufferPoolMinimumBufferCountKey;
extern const CFStringRef kCVPixelBufferPoolMaximumBufferAgeKey;
extern const CFStringRef kCVPixelBufferPoolAllocationThresholdKey;
extern const CFStringRef kCVPixelBufferPoolFreeBufferNotification;

CFTypeID CVPixelBufferPoolGetTypeID(void);
CVPixelBufferPoolRef CVPixelBufferPoolRetain(CVPixelBufferPoolRef pixelBufferPool);
void CVPixelBufferPoolRelease(CVPixelBufferPoolRef pixelBufferPool);
CVReturn CVPixelBufferPoolCreate(CFAllocatorRef allocator, CFDictionaryRef poolAttributes,
                                 CFDictionaryRef pixelBufferAttributes, CVPixelBufferPoolRef *poolOut);
CFDictionaryRef CVPixelBufferPoolGetAttributes(CVPixelBufferPoolRef pool);
CFDictionaryRef CVPixelBufferPoolGetPixelBufferAttributes(CVPixelBufferPoolRef pool);
CVReturn CVPixelBufferPoolCreatePixelBuffer(CFAllocatorRef allocator, CVPixelBufferPoolRef pixelBufferPool,
                                            CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(CFAllocatorRef allocator,
                                                             CVPixelBufferPoolRef pixelBufferPool,
                                                             CFDictionaryRef auxAttributes,
                                                             CVPixelBufferRef *pixelBufferOut);
void CVPixelBufferPoolFlush(CVPixelBufferPoolRef pool, CVPixelBufferPoolFlushFlags options);

/* ---- pixel format descriptions (CVPixelFormatDescription.h) ------------------------ */

extern const CFStringRef kCVPixelFormatName;
extern const CFStringRef kCVPixelFormatConstant;
extern const CFStringRef kCVPixelFormatCodecType;
extern const CFStringRef kCVPixelFormatFourCC;
extern const CFStringRef kCVPixelFormatContainsAlpha;
extern const CFStringRef kCVPixelFormatContainsYCbCr;
extern const CFStringRef kCVPixelFormatContainsRGB;
extern const CFStringRef kCVPixelFormatPlanes;
extern const CFStringRef kCVPixelFormatBlockWidth;
extern const CFStringRef kCVPixelFormatBlockHeight;
extern const CFStringRef kCVPixelFormatBitsPerBlock;
extern const CFStringRef kCVPixelFormatHorizontalSubsampling;
extern const CFStringRef kCVPixelFormatVerticalSubsampling;
extern const CFStringRef kCVPixelFormatOpenGLFormat;
extern const CFStringRef kCVPixelFormatOpenGLType;
extern const CFStringRef kCVPixelFormatOpenGLInternalFormat;
extern const CFStringRef kCVPixelFormatCGBitmapInfo;
extern const CFStringRef kCVPixelFormatOpenGLCompatibility;
extern const CFStringRef kCVPixelFormatCGBitmapContextCompatibility;
extern const CFStringRef kCVPixelFormatCGImageCompatibility;
extern const CFStringRef kCVPixelFormatComponentRange;
extern const CFStringRef kCVPixelFormatComponentRange_VideoRange;
extern const CFStringRef kCVPixelFormatComponentRange_FullRange;
extern const CFStringRef kCVPixelFormatComponentRange_WideRange;
CFDictionaryRef CVPixelFormatDescriptionCreateWithPixelFormatType(CFAllocatorRef allocator, OSType pixelFormat)
    CF_RETURNS_RETAINED;
CFArrayRef CVPixelFormatDescriptionArrayCreateWithAllPixelFormatTypes(CFAllocatorRef allocator) CF_RETURNS_RETAINED;
void CVPixelFormatDescriptionRegisterDescriptionWithPixelFormatType(CFDictionaryRef description, OSType pixelFormat);

/* ---- display links (CVDisplayLink.h) ---------------------------------------------- */

typedef struct __CVDisplayLink *CVDisplayLinkRef;
/* the display type of Core Graphics' display calls (CGDirectDisplay.h) */
#ifndef _FERRY_CGDIRECTDISPLAYID_DEFINED
#define _FERRY_CGDIRECTDISPLAYID_DEFINED
typedef uint32_t CGDirectDisplayID;
#endif
typedef CVReturn (*CVDisplayLinkOutputCallback)(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow,
                                                const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn,
                                                CVOptionFlags *flagsOut, void *displayLinkContext);
#if __BLOCKS__
typedef CVReturn (^CVDisplayLinkOutputHandler)(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow,
                                               const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn,
                                               CVOptionFlags *flagsOut);
#endif

CFTypeID CVDisplayLinkGetTypeID(void);
CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *displayArray, CFIndex count,
                                           CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkCreateWithOpenGLDisplayMask(uint32_t mask, CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID displayID, CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef displayLink, CGDirectDisplayID displayID);
CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef displayLink, CGLContextObj cglContext,
                                                           CGLPixelFormatObj cglPixelFormat);
CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef displayLink);
CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef displayLink, CVDisplayLinkOutputCallback callback,
                                        void *userInfo);
#if __BLOCKS__
CVReturn CVDisplayLinkSetOutputHandler(CVDisplayLinkRef displayLink, CVDisplayLinkOutputHandler handler);
#endif
CVReturn CVDisplayLinkStart(CVDisplayLinkRef displayLink);
CVReturn CVDisplayLinkStop(CVDisplayLinkRef displayLink);
CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef displayLink);
CVTime CVDisplayLinkGetOutputVideoLatency(CVDisplayLinkRef displayLink);
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef displayLink);
Boolean CVDisplayLinkIsRunning(CVDisplayLinkRef displayLink);
CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef displayLink, CVTimeStamp *outTime);
CVReturn CVDisplayLinkTranslateTime(CVDisplayLinkRef displayLink, const CVTimeStamp *inTime, CVTimeStamp *outTime);
CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef displayLink);
void CVDisplayLinkRelease(CVDisplayLinkRef displayLink);

/* ---- OpenGL textures (CVOpenGLTexture.h, CVOpenGLTextureCache.h) ------------------- */

typedef CVImageBufferRef CVOpenGLTextureRef;
typedef struct CF_BRIDGED_TYPE(id) __CVOpenGLTextureCache *CVOpenGLTextureCacheRef;

CFTypeID CVOpenGLTextureGetTypeID(void);
CVOpenGLTextureRef CVOpenGLTextureRetain(CVOpenGLTextureRef texture);
void CVOpenGLTextureRelease(CVOpenGLTextureRef texture);
GLenum CVOpenGLTextureGetTarget(CVOpenGLTextureRef image);
GLuint CVOpenGLTextureGetName(CVOpenGLTextureRef image);
Boolean CVOpenGLTextureIsFlipped(CVOpenGLTextureRef image);
void CVOpenGLTextureGetCleanTexCoords(CVOpenGLTextureRef image, GLfloat lowerLeft[2], GLfloat lowerRight[2],
                                      GLfloat upperRight[2], GLfloat upperLeft[2]);

extern const CFStringRef kCVOpenGLTextureCacheChromaSamplingModeKey;
extern const CFStringRef kCVOpenGLTextureCacheChromaSamplingModeAutomatic;
extern const CFStringRef kCVOpenGLTextureCacheChromaSamplingModeHighestQuality;
extern const CFStringRef kCVOpenGLTextureCacheChromaSamplingModeBestPerformance;
CFTypeID CVOpenGLTextureCacheGetTypeID(void);
CVReturn CVOpenGLTextureCacheCreate(CFAllocatorRef allocator, CFDictionaryRef cacheAttributes,
                                    CGLContextObj cglContext, CGLPixelFormatObj cglPixelFormat,
                                    CFDictionaryRef textureAttributes, CVOpenGLTextureCacheRef *cacheOut);
CVReturn CVOpenGLTextureCacheCreateTextureFromImage(CFAllocatorRef allocator, CVOpenGLTextureCacheRef textureCache,
                                                    CVImageBufferRef sourceImage, CFDictionaryRef attributes,
                                                    CVOpenGLTextureRef *textureOut);
void CVOpenGLTextureCacheFlush(CVOpenGLTextureCacheRef textureCache, CVOptionFlags options);
CVOpenGLTextureCacheRef CVOpenGLTextureCacheRetain(CVOpenGLTextureCacheRef textureCache);
void CVOpenGLTextureCacheRelease(CVOpenGLTextureCacheRef textureCache);

__FERRY_END

#endif
