/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: VideoToolbox's error codes and frame flags, included by
 * VideoToolbox.h (VLC includes this one by name). Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_VTERRORS_H_
#define _FERRY_VTERRORS_H_
#include <stdint.h>

/* errors */
enum {
    kVTPropertyNotSupportedErr = -12900,
    kVTPropertyReadOnlyErr = -12901,
    kVTParameterErr = -12902,
    kVTInvalidSessionErr = -12903,
    kVTAllocationFailedErr = -12904,
    kVTPixelTransferNotSupportedErr = -12905,
    kVTCouldNotFindVideoDecoderErr = -12906,
    kVTCouldNotCreateInstanceErr = -12907,
    kVTCouldNotFindVideoEncoderErr = -12908,
    kVTVideoDecoderBadDataErr = -12909,
    kVTVideoDecoderUnsupportedDataFormatErr = -12910,
    kVTVideoDecoderMalfunctionErr = -12911,
    kVTVideoEncoderMalfunctionErr = -12912,
    kVTVideoDecoderNotAvailableNowErr = -12913,
    kVTImageRotationNotSupportedErr = -12914,
    kVTVideoEncoderNotAvailableNowErr = -12915,
    kVTFormatDescriptionChangeNotSupportedErr = -12916,
    kVTInsufficientSourceColorDataErr = -12917,
    kVTCouldNotCreateColorCorrectionDataErr = -12918,
    kVTColorSyncTransformConvertFailedErr = -12919,
    kVTVideoDecoderAuthorizationErr = -12210,
    kVTVideoEncoderAuthorizationErr = -12211,
    kVTColorCorrectionPixelTransferFailedErr = -12212,
    kVTMultiPassStorageIdentifierMismatchErr = -12213,
    kVTMultiPassStorageInvalidErr = -12214,
    kVTFrameSiloInvalidTimeStampErr = -12215,
    kVTFrameSiloInvalidTimeRangeErr = -12216,
    kVTCouldNotFindTemporalFilterErr = -12217,
    kVTPixelTransferNotPermittedErr = -12218,
    kVTColorCorrectionImageRotationFailedErr = -12219,
    kVTVideoDecoderRemovedErr = -17690,
    kVTVideoDecoderReferenceMissingErr = -17694,
};

typedef uint32_t VTDecodeFrameFlags;
enum {
    kVTDecodeFrame_EnableAsynchronousDecompression = 1 << 0,
    kVTDecodeFrame_DoNotOutputFrame = 1 << 1,
    kVTDecodeFrame_1xRealTimePlayback = 1 << 2,
    kVTDecodeFrame_EnableTemporalProcessing = 1 << 3,
};

typedef uint32_t VTDecodeInfoFlags;
enum {
    kVTDecodeInfo_Asynchronous = 1 << 0,
    kVTDecodeInfo_FrameDropped = 1 << 1,
    kVTDecodeInfo_ImageBufferModifiable = 1 << 2,
};

typedef uint32_t VTEncodeInfoFlags;
enum {
    kVTEncodeInfo_Asynchronous = 1 << 0,
    kVTEncodeInfo_FrameDropped = 1 << 1,
};

#endif
