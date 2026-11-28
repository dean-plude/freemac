/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia's format descriptions (freemac 1.238, Ferry 0.62.0;
 * appkit/CMSampleBuffer.m), for video made of Core Video image buffers and
 * for linear PCM audio. Written for freemac from Apple's public API
 * documentation; not Apple's header. Compressed formats' parameter sets
 * and the extension atoms of codecs aren't here. */
#ifndef _FERRY_CMFORMATDESCRIPTION_H_
#define _FERRY_CMFORMATDESCRIPTION_H_
#include <CoreFoundation/CoreFoundation.h>
#include <MacTypes.h>
#include <CoreVideo/CoreVideo.h>
#include <CoreAudioTypes/CoreAudioTypes.h>

__FERRY_BEGIN
typedef const struct opaqueCMFormatDescription *CMFormatDescriptionRef;
typedef CMFormatDescriptionRef CMVideoFormatDescriptionRef;
typedef CMFormatDescriptionRef CMAudioFormatDescriptionRef;

typedef FourCharCode CMMediaType;
enum {
    kCMMediaType_Video = 'vide', kCMMediaType_Audio = 'soun', kCMMediaType_Muxed = 'muxx',
    kCMMediaType_Text = 'text', kCMMediaType_ClosedCaption = 'clcp', kCMMediaType_Subtitle = 'sbtl',
    kCMMediaType_TimeCode = 'tmcd', kCMMediaType_Metadata = 'meta',
};
typedef FourCharCode CMVideoCodecType;
enum {
    kCMVideoCodecType_422YpCbCr8 = '2vuy', kCMVideoCodecType_JPEG = 'jpeg', kCMVideoCodecType_H264 = 'avc1',
    kCMVideoCodecType_HEVC = 'hvc1', kCMVideoCodecType_MPEG4Video = 'mp4v', kCMVideoCodecType_AppleProRes422 = 'apcn',
    kCMVideoCodecType_JPEG_OpenDML = 'dmb1',
    kCMVideoCodecType_Animation = 'rle ', kCMVideoCodecType_Cinepak = 'cvid',
    kCMVideoCodecType_SorensonVideo = 'SVQ1', kCMVideoCodecType_SorensonVideo3 = 'SVQ3',
    kCMVideoCodecType_H263 = 'h263', kCMVideoCodecType_MPEG1Video = 'mp1v', kCMVideoCodecType_MPEG2Video = 'mp2v',
    kCMVideoCodecType_DVCNTSC = 'dvc ', kCMVideoCodecType_DVCPAL = 'dvcp', kCMVideoCodecType_DVCProPAL = 'dvpp',
    kCMVideoCodecType_DVCPro50NTSC = 'dv5n', kCMVideoCodecType_DVCPro50PAL = 'dv5p',
    kCMVideoCodecType_DVCPROHD720p60 = 'dvhp', kCMVideoCodecType_DVCPROHD720p50 = 'dvhq',
    kCMVideoCodecType_DVCPROHD1080i60 = 'dvh6', kCMVideoCodecType_DVCPROHD1080i50 = 'dvh5',
    kCMVideoCodecType_DVCPROHD1080p30 = 'dvh3', kCMVideoCodecType_DVCPROHD1080p25 = 'dvh2',
    kCMVideoCodecType_AppleProRes4444XQ = 'ap4x', kCMVideoCodecType_AppleProRes4444 = 'ap4h',
    kCMVideoCodecType_AppleProRes422HQ = 'apch', kCMVideoCodecType_AppleProRes422LT = 'apcs',
    kCMVideoCodecType_AppleProRes422Proxy = 'apco', kCMVideoCodecType_VP9 = 'vp09', kCMVideoCodecType_AV1 = 'av01',
};
typedef FourCharCode CMAudioCodecType;
typedef struct {
    int32_t width;
    int32_t height;
} CMVideoDimensions;

enum {
    kCMFormatDescriptionError_InvalidParameter = -12710,
    kCMFormatDescriptionError_AllocationFailed = -12711,
    kCMFormatDescriptionError_ValueNotAvailable = -12718,
};

/* the values of the colour extensions: the same strings as Core Video's */
extern const CFStringRef kCMFormatDescriptionColorPrimaries_ITU_R_709_2, kCMFormatDescriptionColorPrimaries_EBU_3213,
    kCMFormatDescriptionColorPrimaries_SMPTE_C, kCMFormatDescriptionColorPrimaries_DCI_P3,
    kCMFormatDescriptionColorPrimaries_P3_D65, kCMFormatDescriptionColorPrimaries_ITU_R_2020,
    kCMFormatDescriptionColorPrimaries_P22;
extern const CFStringRef kCMFormatDescriptionTransferFunction_ITU_R_709_2,
    kCMFormatDescriptionTransferFunction_SMPTE_240M_1995, kCMFormatDescriptionTransferFunction_UseGamma,
    kCMFormatDescriptionTransferFunction_ITU_R_2020, kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1,
    kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG,
    kCMFormatDescriptionTransferFunction_Linear, kCMFormatDescriptionTransferFunction_sRGB;
extern const CFStringRef kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2, kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4,
    kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020;
extern const CFStringRef kCMFormatDescriptionExtension_FormatName;
extern const CFStringRef kCMFormatDescriptionExtension_Depth;
extern const CFStringRef kCMFormatDescriptionExtension_CleanAperture;
extern const CFStringRef kCMFormatDescriptionExtension_FieldCount;
extern const CFStringRef kCMFormatDescriptionExtension_PixelAspectRatio;
extern const CFStringRef kCMFormatDescriptionExtension_ColorPrimaries;
extern const CFStringRef kCMFormatDescriptionExtension_TransferFunction;
extern const CFStringRef kCMFormatDescriptionExtension_YCbCrMatrix;
extern const CFStringRef kCMFormatDescriptionExtension_FullRangeVideo;
extern const CFStringRef kCMFormatDescriptionExtension_BytesPerRow;
extern const CFStringRef kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms;

CFTypeID CMFormatDescriptionGetTypeID(void);
OSStatus CMFormatDescriptionCreate(CFAllocatorRef allocator, CMMediaType mediaType, FourCharCode mediaSubType,
                                   CFDictionaryRef extensions, CMFormatDescriptionRef *formatDescriptionOut);
CMMediaType CMFormatDescriptionGetMediaType(CMFormatDescriptionRef desc);
FourCharCode CMFormatDescriptionGetMediaSubType(CMFormatDescriptionRef desc);
CFDictionaryRef CMFormatDescriptionGetExtensions(CMFormatDescriptionRef desc);
CFPropertyListRef CMFormatDescriptionGetExtension(CMFormatDescriptionRef desc, CFStringRef extensionKey);
Boolean CMFormatDescriptionEqual(CMFormatDescriptionRef a, CMFormatDescriptionRef b);

/* video */
OSStatus CMVideoFormatDescriptionCreate(CFAllocatorRef allocator, CMVideoCodecType codecType, int32_t width,
                                        int32_t height, CFDictionaryRef extensions,
                                        CMVideoFormatDescriptionRef *formatDescriptionOut);
OSStatus CMVideoFormatDescriptionCreateForImageBuffer(CFAllocatorRef allocator, CVImageBufferRef imageBuffer,
                                                      CMVideoFormatDescriptionRef *formatDescriptionOut);
CMVideoDimensions CMVideoFormatDescriptionGetDimensions(CMVideoFormatDescriptionRef videoDesc);
/* H.264 and HEVC parameter sets (SPS, PPS, VPS), kept in the description's
 * avcC or hvcC atom as in an MP4 file (freemac 1.264) */
OSStatus CMVideoFormatDescriptionCreateFromH264ParameterSets(CFAllocatorRef allocator, size_t parameterSetCount,
                                                             const uint8_t *const *parameterSetPointers,
                                                             const size_t *parameterSetSizes, int NALUnitHeaderLength,
                                                             CMFormatDescriptionRef *formatDescriptionOut);
OSStatus CMVideoFormatDescriptionCreateFromHEVCParameterSets(CFAllocatorRef allocator, size_t parameterSetCount,
                                                             const uint8_t *const *parameterSetPointers,
                                                             const size_t *parameterSetSizes, int NALUnitHeaderLength,
                                                             CFDictionaryRef extensions,
                                                             CMFormatDescriptionRef *formatDescriptionOut);
OSStatus CMVideoFormatDescriptionGetH264ParameterSetAtIndex(CMFormatDescriptionRef videoDesc, size_t parameterSetIndex,
                                                            const uint8_t **parameterSetPointerOut,
                                                            size_t *parameterSetSizeOut, size_t *parameterSetCountOut,
                                                            int *NALUnitHeaderLengthOut);
OSStatus CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(CMFormatDescriptionRef videoDesc, size_t parameterSetIndex,
                                                            const uint8_t **parameterSetPointerOut,
                                                            size_t *parameterSetSizeOut, size_t *parameterSetCountOut,
                                                            int *NALUnitHeaderLengthOut);
CGSize CMVideoFormatDescriptionGetPresentationDimensions(CMVideoFormatDescriptionRef videoDesc,
                                                         Boolean usePixelAspectRatio, Boolean useCleanAperture);
Boolean CMVideoFormatDescriptionMatchesImageBuffer(CMVideoFormatDescriptionRef desc, CVImageBufferRef imageBuffer);
CGRect CMVideoFormatDescriptionGetCleanAperture(CMVideoFormatDescriptionRef videoDesc, Boolean originIsAtTopLeft);
#define CMVideoFormatDescriptionGetCodecType(desc) CMFormatDescriptionGetMediaSubType(desc)

/* audio */
OSStatus CMAudioFormatDescriptionCreate(CFAllocatorRef allocator, const AudioStreamBasicDescription *asbd,
                                        size_t layoutSize, const AudioChannelLayout *layout, size_t magicCookieSize,
                                        const void *magicCookie, CFDictionaryRef extensions,
                                        CMAudioFormatDescriptionRef *formatDescriptionOut);
const AudioStreamBasicDescription *CMAudioFormatDescriptionGetStreamBasicDescription(CMAudioFormatDescriptionRef desc);
const AudioChannelLayout *CMAudioFormatDescriptionGetChannelLayout(CMAudioFormatDescriptionRef desc,
                                                                   size_t *sizeOut);
const void *CMAudioFormatDescriptionGetMagicCookie(CMAudioFormatDescriptionRef desc, size_t *sizeOut);
#define CMAudioFormatDescriptionGetCodecType(desc) CMFormatDescriptionGetMediaSubType(desc)
__FERRY_END
#endif
