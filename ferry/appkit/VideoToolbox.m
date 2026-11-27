/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * VideoToolbox (freemac 1.262, Ferry 0.85.0, for IINA and the FFmpeg it
 * carries), written from Apple's public VideoToolbox documentation.
 * freemac decodes and encodes video in software, so there is no hardware
 * decoder or encoder to hand out: making a session fails with the error
 * Apple documents for a missing codec, and a program such as FFmpeg goes on
 * with its own software decoder. The property keys are the strings the
 * keys' names spell, as a Mac's are. */
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef int32_t OSStatus;
typedef uint32_t FourCharCode;
typedef void *VTSessionRef;

enum {
    kVTPropertyNotSupportedErr = -12900,
    kVTCouldNotFindVideoDecoderErr = -12906,
    kVTCouldNotFindVideoEncoderErr = -12908,
    kVTInvalidSessionErr = -12903,
    kVTPixelTransferNotSupportedErr = -12905,
};

/* ---- decoding */

OSStatus VTDecompressionSessionCreate(CFAllocatorRef allocator, const void *videoFormatDescription,
                                      CFDictionaryRef videoDecoderSpecification,
                                      CFDictionaryRef destinationImageBufferAttributes,
                                      const void *outputCallback, VTSessionRef *decompressionSessionOut)
{
    (void)allocator; (void)videoFormatDescription; (void)videoDecoderSpecification;
    (void)destinationImageBufferAttributes; (void)outputCallback;
    if (decompressionSessionOut)
        *decompressionSessionOut = NULL;
    return kVTCouldNotFindVideoDecoderErr;
}

OSStatus VTDecompressionSessionDecodeFrame(VTSessionRef session, const void *sampleBuffer, uint32_t decodeFlags,
                                           void *sourceFrameRefCon, uint32_t *infoFlagsOut)
{
    (void)session; (void)sampleBuffer; (void)decodeFlags; (void)sourceFrameRefCon;
    if (infoFlagsOut)
        *infoFlagsOut = 0;
    return kVTInvalidSessionErr;
}

OSStatus VTDecompressionSessionWaitForAsynchronousFrames(VTSessionRef session)
{
    (void)session;
    return kVTInvalidSessionErr;
}

void VTDecompressionSessionInvalidate(VTSessionRef session) { (void)session; }

/* (freemac 1.NEXT, for VLC's videotoolbox module) No session opens, so
 * none takes a new format or holds frames back. */
Boolean VTDecompressionSessionCanAcceptFormatDescription(VTSessionRef session, const void *newFormatDesc)
{
    (void)session; (void)newFormatDesc;
    return false;
}

OSStatus VTDecompressionSessionFinishDelayedFrames(VTSessionRef session)
{
    (void)session;
    return kVTInvalidSessionErr;
}

/* Pixel transfer sessions (VLC's cvpx converter) convert between pixel
 * buffer formats on a Mac; freemac has no such converter, so making one
 * fails as Apple documents for a transfer it can't do and the program
 * converts in software. */
OSStatus VTPixelTransferSessionCreate(CFAllocatorRef allocator, VTSessionRef *pixelTransferSessionOut)
{
    (void)allocator;
    if (pixelTransferSessionOut)
        *pixelTransferSessionOut = NULL;
    return kVTPixelTransferNotSupportedErr;
}

OSStatus VTPixelTransferSessionTransferImage(VTSessionRef session, void *sourceBuffer, void *destinationBuffer)
{
    (void)session; (void)sourceBuffer; (void)destinationBuffer;
    return kVTInvalidSessionErr;
}

void VTPixelTransferSessionInvalidate(VTSessionRef session) { (void)session; }

/* No hardware decoder takes any codec here. */
bool VTIsHardwareDecodeSupported(FourCharCode codecType)
{
    (void)codecType;
    return false;
}

/* Extra decoders a Mac can add (professional formats, AV1 and VP9 on some
 * Macs); freemac has none to add. */
void VTRegisterProfessionalVideoWorkflowVideoDecoders(void) {}
void VTRegisterProfessionalVideoWorkflowVideoEncoders(void) {}
void VTRegisterSupplementalVideoDecoderIfAvailable(FourCharCode codecType) { (void)codecType; }

/* ---- encoding */

OSStatus VTCompressionSessionCreate(CFAllocatorRef allocator, int32_t width, int32_t height, FourCharCode codecType,
                                    CFDictionaryRef encoderSpecification, CFDictionaryRef sourceImageBufferAttributes,
                                    CFAllocatorRef compressedDataAllocator, const void *outputCallback,
                                    void *outputCallbackRefCon, VTSessionRef *compressionSessionOut)
{
    (void)allocator; (void)width; (void)height; (void)codecType; (void)encoderSpecification;
    (void)sourceImageBufferAttributes; (void)compressedDataAllocator; (void)outputCallback;
    (void)outputCallbackRefCon;
    if (compressionSessionOut)
        *compressionSessionOut = NULL;
    return kVTCouldNotFindVideoEncoderErr;
}

OSStatus VTCompressionSessionEncodeFrame(VTSessionRef session, const void *imageBuffer, int64_t ptsValue,
                                         int32_t ptsScale, uint32_t ptsFlags, int64_t ptsEpoch, int64_t durValue,
                                         int32_t durScale, uint32_t durFlags, int64_t durEpoch,
                                         CFDictionaryRef frameProperties, void *sourceFrameRefcon,
                                         uint32_t *infoFlagsOut)
{
    /* the two CMTimes come as their four fields each */
    (void)session; (void)imageBuffer; (void)ptsValue; (void)ptsScale; (void)ptsFlags; (void)ptsEpoch;
    (void)durValue; (void)durScale; (void)durFlags; (void)durEpoch; (void)frameProperties; (void)sourceFrameRefcon;
    if (infoFlagsOut)
        *infoFlagsOut = 0;
    return kVTInvalidSessionErr;
}

OSStatus VTCompressionSessionCompleteFrames(VTSessionRef session, int64_t value, int32_t timescale, uint32_t flags,
                                            int64_t epoch)
{
    (void)session; (void)value; (void)timescale; (void)flags; (void)epoch;
    return kVTInvalidSessionErr;
}

OSStatus VTCompressionSessionPrepareToEncodeFrames(VTSessionRef session)
{
    (void)session;
    return kVTInvalidSessionErr;
}

void *VTCompressionSessionGetPixelBufferPool(VTSessionRef session)
{
    (void)session;
    return NULL;
}

void VTCompressionSessionInvalidate(VTSessionRef session) { (void)session; }

/* ---- multi-pass encoding: with no encoder sessions there are no passes to
 * run, and no storage to keep a first pass's results in (freemac 1.264,
 * HandBrake) */

typedef struct {
    int64_t value;
    int32_t timescale;
    uint32_t flags;
    int64_t epoch;
} VTTime;
typedef struct {
    VTTime start, duration;
} VTTimeRange;
typedef void *VTMultiPassStorageRef;

OSStatus VTCompressionSessionBeginPass(VTSessionRef session, uint32_t beginPassFlags, uint32_t *reserved)
{
    (void)session; (void)beginPassFlags; (void)reserved;
    return kVTInvalidSessionErr;
}

OSStatus VTCompressionSessionEndPass(VTSessionRef session, Boolean *furtherPassesRequestedOut, uint32_t *reserved)
{
    (void)session; (void)reserved;
    if (furtherPassesRequestedOut)
        *furtherPassesRequestedOut = false;
    return kVTInvalidSessionErr;
}

OSStatus VTCompressionSessionGetTimeRangesForNextPass(VTSessionRef session, long *timeRangeCountOut,
                                                      const VTTimeRange **timeRangeArrayOut)
{
    (void)session;
    if (timeRangeCountOut)
        *timeRangeCountOut = 0;
    if (timeRangeArrayOut)
        *timeRangeArrayOut = NULL;
    return kVTInvalidSessionErr;
}

OSStatus VTMultiPassStorageCreate(CFAllocatorRef allocator, CFURLRef fileURL, VTTimeRange timeRange,
                                  CFDictionaryRef options, VTMultiPassStorageRef *multiPassStorageOut)
{
    (void)allocator; (void)fileURL; (void)timeRange; (void)options;
    if (multiPassStorageOut)
        *multiPassStorageOut = NULL;
    return kVTCouldNotFindVideoEncoderErr;
}

OSStatus VTMultiPassStorageClose(VTMultiPassStorageRef multiPassStorage)
{
    return multiPassStorage ? 0 : -12902 /* kVTParameterErr */;
}

/* ---- the list of encoders: none in hardware, so an empty list, and a
 * program such as OBS offers its own software encoders (freemac 1.263) */

OSStatus VTCopyVideoEncoderList(CFDictionaryRef options, CFArrayRef *listOfVideoEncodersOut)
{
    (void)options;
    if (listOfVideoEncodersOut)
        *listOfVideoEncodersOut = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    return 0;
}

OSStatus VTCopySupportedPropertyDictionaryForEncoder(int32_t width, int32_t height, FourCharCode codecType,
                                                     CFDictionaryRef encoderSpecification, CFStringRef *encoderIDOut,
                                                     CFDictionaryRef *supportedPropertiesOut)
{
    (void)width; (void)height; (void)codecType; (void)encoderSpecification;
    if (encoderIDOut)
        *encoderIDOut = NULL;
    if (supportedPropertiesOut)
        *supportedPropertiesOut = NULL;
    return kVTCouldNotFindVideoEncoderErr;
}

/* ---- a session's properties */

OSStatus VTSessionSetProperty(VTSessionRef session, CFStringRef propertyKey, CFTypeRef propertyValue)
{
    (void)session; (void)propertyKey; (void)propertyValue;
    return kVTPropertyNotSupportedErr;
}

OSStatus VTSessionCopyProperty(VTSessionRef session, CFStringRef propertyKey, CFAllocatorRef allocator,
                               void *propertyValueOut)
{
    (void)session; (void)propertyKey; (void)allocator;
    if (propertyValueOut)
        *(CFTypeRef *)propertyValueOut = NULL;
    return kVTPropertyNotSupportedErr;
}

OSStatus VTSessionSetProperties(VTSessionRef session, CFDictionaryRef propertyDictionary)
{
    (void)session; (void)propertyDictionary;
    return kVTPropertyNotSupportedErr;
}

/* ---- the keys */

#define VT_KEY(name) const CFStringRef name = (CFStringRef)@#name;
VT_KEY(kVTCompressionPropertyKey_AllowFrameReordering)
VT_KEY(kVTCompressionPropertyKey_AverageBitRate)
VT_KEY(kVTCompressionPropertyKey_ColorPrimaries)
VT_KEY(kVTCompressionPropertyKey_DataRateLimits)
VT_KEY(kVTCompressionPropertyKey_MaxKeyFrameInterval)
VT_KEY(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration)
VT_KEY(kVTCompressionPropertyKey_MoreFramesAfterEnd)
VT_KEY(kVTCompressionPropertyKey_MoreFramesBeforeStart)
VT_KEY(kVTCompressionPropertyKey_PixelAspectRatio)
VT_KEY(kVTCompressionPropertyKey_ProfileLevel)
VT_KEY(kVTCompressionPropertyKey_Quality)
VT_KEY(kVTCompressionPropertyKey_RealTime)
VT_KEY(kVTCompressionPropertyKey_TransferFunction)
VT_KEY(kVTCompressionPropertyKey_YCbCrMatrix)
VT_KEY(kVTCompressionPropertyKey_MaxH264SliceBytes)
/* freemac 1.264, HandBrake */
VT_KEY(kVTCompressionPropertyKey_AllowTemporalCompression)
VT_KEY(kVTCompressionPropertyKey_ContentLightLevelInfo)
VT_KEY(kVTCompressionPropertyKey_EncoderID)
VT_KEY(kVTCompressionPropertyKey_ExpectedFrameRate)
VT_KEY(kVTCompressionPropertyKey_FieldCount)
VT_KEY(kVTCompressionPropertyKey_FieldDetail)
VT_KEY(kVTCompressionPropertyKey_H264EntropyMode)
VT_KEY(kVTCompressionPropertyKey_MasteringDisplayColorVolume)
VT_KEY(kVTCompressionPropertyKey_MaxFrameDelayCount)
VT_KEY(kVTCompressionPropertyKey_MultiPassStorage)
VT_KEY(kVTDownsamplingMode_Average)
VT_KEY(kVTH264EntropyMode_CABAC)
VT_KEY(kVTH264EntropyMode_CAVLC)
VT_KEY(kVTPixelTransferPropertyKey_DestinationCleanAperture)
VT_KEY(kVTPixelTransferPropertyKey_DownsamplingMode)
VT_KEY(kVTPixelTransferPropertyKey_ScalingMode)
VT_KEY(kVTPropertySupportedValueListKey)
VT_KEY(kVTScalingMode_CropSourceToCleanAperture)
VT_KEY(kVTDecompressionPropertyKey_RealTime)
VT_KEY(kVTVideoEncoderList_CodecName)
VT_KEY(kVTVideoEncoderList_CodecType)
VT_KEY(kVTVideoEncoderList_DisplayName)
VT_KEY(kVTVideoEncoderList_EncoderID)
VT_KEY(kVTVideoEncoderList_EncoderName)
VT_KEY(kVTVideoEncoderList_IsHardwareAccelerated)
VT_KEY(kVTVideoEncoderSpecification_EncoderID)
VT_KEY(kVTDecompressionPropertyKey_FieldMode)
VT_KEY(kVTDecompressionProperty_FieldMode_BothFields)
VT_KEY(kVTDecompressionProperty_FieldMode_TopFieldOnly)
VT_KEY(kVTDecompressionProperty_FieldMode_BottomFieldOnly)
VT_KEY(kVTDecompressionProperty_FieldMode_SingleField)
VT_KEY(kVTDecompressionProperty_FieldMode_DeinterlaceFields)
VT_KEY(kVTDecompressionPropertyKey_DeinterlaceMode)
VT_KEY(kVTDecompressionProperty_DeinterlaceMode_VerticalFilter)
VT_KEY(kVTDecompressionProperty_DeinterlaceMode_Temporal)
VT_KEY(kVTEncodeFrameOptionKey_ForceKeyFrame)
VT_KEY(kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder)
VT_KEY(kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder)
VT_KEY(kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder)
VT_KEY(kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder)
VT_KEY(kVTProfileLevel_H264_Baseline_1_3)
VT_KEY(kVTProfileLevel_H264_Baseline_3_0)
VT_KEY(kVTProfileLevel_H264_Baseline_3_1)
VT_KEY(kVTProfileLevel_H264_Baseline_3_2)
VT_KEY(kVTProfileLevel_H264_Baseline_4_0)
VT_KEY(kVTProfileLevel_H264_Baseline_4_1)
VT_KEY(kVTProfileLevel_H264_Baseline_AutoLevel)
VT_KEY(kVTProfileLevel_H264_High_5_0)
VT_KEY(kVTProfileLevel_H264_High_AutoLevel)
VT_KEY(kVTProfileLevel_H264_Main_3_0)
VT_KEY(kVTProfileLevel_H264_Main_3_1)
VT_KEY(kVTProfileLevel_H264_Main_3_2)
VT_KEY(kVTProfileLevel_H264_Main_4_0)
VT_KEY(kVTProfileLevel_H264_Main_4_1)
VT_KEY(kVTProfileLevel_H264_Main_5_0)
VT_KEY(kVTProfileLevel_H264_Main_AutoLevel)
VT_KEY(kVTProfileLevel_HEVC_Main_AutoLevel)
VT_KEY(kVTProfileLevel_HEVC_Main10_AutoLevel)
