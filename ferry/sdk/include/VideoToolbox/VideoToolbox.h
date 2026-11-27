/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: VideoToolbox, served from Ferry's AppKit file
 * (appkit/VideoToolbox.m). Written for freemac from Apple's public API
 * documentation; not Apple's header. freemac decodes and encodes in
 * software, so every session fails to open with the error Apple documents
 * for a missing codec and a program goes on with its own decoder; the
 * header is here so programs that carry a VideoToolbox path (VLC's
 * videotoolbox and cvpx modules, freemac 1.NEXT) build as they do for a
 * Mac. */
#ifndef _FERRY_VIDEOTOOLBOX_H_
#define _FERRY_VIDEOTOOLBOX_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#include <VideoToolbox/VTErrors.h>

/* sessions */
typedef CFTypeRef VTSessionRef;
typedef struct OpaqueVTDecompressionSession *VTDecompressionSessionRef;
typedef struct OpaqueVTCompressionSession *VTCompressionSessionRef;
typedef struct OpaqueVTPixelTransferSession *VTPixelTransferSessionRef;

OSStatus VTSessionSetProperty(VTSessionRef session, CFStringRef propertyKey, CFTypeRef propertyValue);
OSStatus VTSessionCopyProperty(VTSessionRef session, CFStringRef propertyKey, CFAllocatorRef allocator,
                               void *propertyValueOut);
OSStatus VTSessionSetProperties(VTSessionRef session, CFDictionaryRef propertyDictionary);

/* decoding */
typedef void (*VTDecompressionOutputCallback)(void *decompressionOutputRefCon, void *sourceFrameRefCon,
                                              OSStatus status, VTDecodeInfoFlags infoFlags,
                                              CVImageBufferRef imageBuffer, CMTime presentationTimeStamp,
                                              CMTime presentationDuration);
typedef struct {
    VTDecompressionOutputCallback decompressionOutputCallback;
    void *decompressionOutputRefCon;
} VTDecompressionOutputCallbackRecord;

OSStatus VTDecompressionSessionCreate(CFAllocatorRef allocator, CMVideoFormatDescriptionRef videoFormatDescription,
                                      CFDictionaryRef videoDecoderSpecification,
                                      CFDictionaryRef destinationImageBufferAttributes,
                                      const VTDecompressionOutputCallbackRecord *outputCallback,
                                      VTDecompressionSessionRef *decompressionSessionOut);
OSStatus VTDecompressionSessionDecodeFrame(VTDecompressionSessionRef session, CMSampleBufferRef sampleBuffer,
                                           VTDecodeFrameFlags decodeFlags, void *sourceFrameRefCon,
                                           VTDecodeInfoFlags *infoFlagsOut);
OSStatus VTDecompressionSessionFinishDelayedFrames(VTDecompressionSessionRef session);
OSStatus VTDecompressionSessionWaitForAsynchronousFrames(VTDecompressionSessionRef session);
Boolean VTDecompressionSessionCanAcceptFormatDescription(VTDecompressionSessionRef session,
                                                         CMFormatDescriptionRef newFormatDesc);
void VTDecompressionSessionInvalidate(VTDecompressionSessionRef session);
Boolean VTIsHardwareDecodeSupported(CMVideoCodecType codecType);

extern const CFStringRef kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder;
extern const CFStringRef kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder;
extern const CFStringRef kVTDecompressionPropertyKey_RealTime;
extern const CFStringRef kVTDecompressionPropertyKey_FieldMode;
extern const CFStringRef kVTDecompressionProperty_FieldMode_BothFields;
extern const CFStringRef kVTDecompressionProperty_FieldMode_TopFieldOnly;
extern const CFStringRef kVTDecompressionProperty_FieldMode_BottomFieldOnly;
extern const CFStringRef kVTDecompressionProperty_FieldMode_SingleField;
extern const CFStringRef kVTDecompressionProperty_FieldMode_DeinterlaceFields;
extern const CFStringRef kVTDecompressionPropertyKey_DeinterlaceMode;
extern const CFStringRef kVTDecompressionProperty_DeinterlaceMode_VerticalFilter;
extern const CFStringRef kVTDecompressionProperty_DeinterlaceMode_Temporal;

/* pixel transfer */
OSStatus VTPixelTransferSessionCreate(CFAllocatorRef allocator, VTPixelTransferSessionRef *pixelTransferSessionOut);
OSStatus VTPixelTransferSessionTransferImage(VTPixelTransferSessionRef session, CVPixelBufferRef sourceBuffer,
                                             CVPixelBufferRef destinationBuffer);
void VTPixelTransferSessionInvalidate(VTPixelTransferSessionRef session);

#ifdef __cplusplus
}
#endif
#endif
