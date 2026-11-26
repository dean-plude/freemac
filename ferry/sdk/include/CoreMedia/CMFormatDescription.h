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
CGSize CMVideoFormatDescriptionGetPresentationDimensions(CMVideoFormatDescriptionRef videoDesc,
                                                         Boolean usePixelAspectRatio, Boolean useCleanAperture);
Boolean CMVideoFormatDescriptionMatchesImageBuffer(CMVideoFormatDescriptionRef desc, CVImageBufferRef imageBuffer);
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
