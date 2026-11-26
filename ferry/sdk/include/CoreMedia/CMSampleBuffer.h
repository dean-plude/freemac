/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia's sample buffers (freemac 1.238, Ferry 0.62.0;
 * appkit/CMSampleBuffer.m). Written for freemac from Apple's public API
 * documentation; not Apple's header. A sample buffer holds either a Core
 * Video image buffer or a block buffer of samples, with its format
 * description, its timing and its attachments (the per-sample attachments
 * array, and the buffer's own through CMGetAttachment). Sample buffers
 * whose data is made ready later, and those of compressed audio with
 * packet descriptions, aren't here. */
#ifndef _FERRY_CMSAMPLEBUFFER_H_
#define _FERRY_CMSAMPLEBUFFER_H_
#include <CoreMedia/CMTime.h>
#include <CoreMedia/CMBlockBuffer.h>
#include <CoreMedia/CMFormatDescription.h>
#include <CoreMedia/CMAttachment.h>

__FERRY_BEGIN
typedef struct opaqueCMSampleBuffer *CMSampleBufferRef;
typedef long CMItemCount;
typedef long CMItemIndex;

enum {
    kCMSampleBufferError_AllocationFailed = -12730,
    kCMSampleBufferError_RequiredParameterMissing = -12731,
    kCMSampleBufferError_AlreadyHasDataBuffer = -12732,
    kCMSampleBufferError_BufferNotReady = -12733,
    kCMSampleBufferError_SampleIndexOutOfRange = -12734,
    kCMSampleBufferError_BufferHasNoSampleSizes = -12735,
    kCMSampleBufferError_BufferHasNoSampleTimingInfo = -12736,
    kCMSampleBufferError_ArrayTooSmall = -12737,
    kCMSampleBufferError_InvalidEntryCount = -12738,
    kCMSampleBufferError_CannotSubdivide = -12739,
    kCMSampleBufferError_SampleTimingInfoInvalid = -12740,
    kCMSampleBufferError_InvalidMediaTypeForOperation = -12741,
    kCMSampleBufferError_InvalidSampleData = -12742,
    kCMSampleBufferError_InvalidMediaFormat = -12743,
    kCMSampleBufferError_Invalidated = -12744,
    kCMSampleBufferError_DataFailed = -16750,
    kCMSampleBufferError_DataCanceled = -16751,
};
enum { kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment = 1U << 0 };

typedef struct {
    CMTime duration;
    CMTime presentationTimeStamp;
    CMTime decodeTimeStamp;
} CMSampleTimingInfo;
extern const CMSampleTimingInfo kCMTimingInfoInvalid;

typedef OSStatus (*CMSampleBufferMakeDataReadyCallback)(CMSampleBufferRef sbuf, void *makeDataReadyRefcon);

/* the keys of a sample's attachments */
extern const CFStringRef kCMSampleAttachmentKey_NotSync;
extern const CFStringRef kCMSampleAttachmentKey_PartialSync;
extern const CFStringRef kCMSampleAttachmentKey_HasRedundantCoding;
extern const CFStringRef kCMSampleAttachmentKey_IsDependedOnByOthers;
extern const CFStringRef kCMSampleAttachmentKey_DependsOnOthers;
extern const CFStringRef kCMSampleAttachmentKey_EarlierDisplayTimesAllowed;
extern const CFStringRef kCMSampleAttachmentKey_DisplayImmediately;
extern const CFStringRef kCMSampleAttachmentKey_DoNotDisplay;
/* and of a buffer's own */
extern const CFStringRef kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding;
extern const CFStringRef kCMSampleBufferAttachmentKey_DrainAfterDecoding;
extern const CFStringRef kCMSampleBufferAttachmentKey_EmptyMedia;
extern const CFStringRef kCMSampleBufferAttachmentKey_DisplayEmptyMediaImmediately;

CFTypeID CMSampleBufferGetTypeID(void);
OSStatus CMSampleBufferCreate(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, Boolean dataReady,
                              CMSampleBufferMakeDataReadyCallback makeDataReadyCallback, void *makeDataReadyRefcon,
                              CMFormatDescriptionRef formatDescription, CMItemCount numSamples,
                              CMItemCount numSampleTimingEntries, const CMSampleTimingInfo *sampleTimingArray,
                              CMItemCount numSampleSizeEntries, const size_t *sampleSizeArray,
                              CMSampleBufferRef *sampleBufferOut);
OSStatus CMSampleBufferCreateReady(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer,
                                   CMFormatDescriptionRef formatDescription, CMItemCount numSamples,
                                   CMItemCount numSampleTimingEntries, const CMSampleTimingInfo *sampleTimingArray,
                                   CMItemCount numSampleSizeEntries, const size_t *sampleSizeArray,
                                   CMSampleBufferRef *sampleBufferOut);
OSStatus CMSampleBufferCreateForImageBuffer(CFAllocatorRef allocator, CVImageBufferRef imageBuffer, Boolean dataReady,
                                            CMSampleBufferMakeDataReadyCallback makeDataReadyCallback,
                                            void *makeDataReadyRefcon, CMVideoFormatDescriptionRef formatDescription,
                                            const CMSampleTimingInfo *sampleTiming, CMSampleBufferRef *sampleBufferOut);
OSStatus CMSampleBufferCreateReadyWithImageBuffer(CFAllocatorRef allocator, CVImageBufferRef imageBuffer,
                                                  CMVideoFormatDescriptionRef formatDescription,
                                                  const CMSampleTimingInfo *sampleTiming,
                                                  CMSampleBufferRef *sampleBufferOut);
OSStatus CMSampleBufferCreateCopy(CFAllocatorRef allocator, CMSampleBufferRef sbuf, CMSampleBufferRef *sampleBufferOut);
OSStatus CMSampleBufferCreateCopyWithNewTiming(CFAllocatorRef allocator, CMSampleBufferRef originalSBuf,
                                               CMItemCount numSampleTimingEntries,
                                               const CMSampleTimingInfo *sampleTimingArray,
                                               CMSampleBufferRef *sampleBufferOut);
OSStatus CMSampleBufferSetDataBuffer(CMSampleBufferRef sbuf, CMBlockBufferRef dataBuffer);
OSStatus CMSampleBufferSetDataReady(CMSampleBufferRef sbuf);
OSStatus CMSampleBufferMakeDataReady(CMSampleBufferRef sbuf);
Boolean CMSampleBufferDataIsReady(CMSampleBufferRef sbuf);
Boolean CMSampleBufferIsValid(CMSampleBufferRef sbuf);
OSStatus CMSampleBufferInvalidate(CMSampleBufferRef sbuf);

CVImageBufferRef CMSampleBufferGetImageBuffer(CMSampleBufferRef sbuf);
CMBlockBufferRef CMSampleBufferGetDataBuffer(CMSampleBufferRef sbuf);
CMFormatDescriptionRef CMSampleBufferGetFormatDescription(CMSampleBufferRef sbuf);
CMItemCount CMSampleBufferGetNumSamples(CMSampleBufferRef sbuf);
CMTime CMSampleBufferGetDuration(CMSampleBufferRef sbuf);
CMTime CMSampleBufferGetPresentationTimeStamp(CMSampleBufferRef sbuf);
CMTime CMSampleBufferGetDecodeTimeStamp(CMSampleBufferRef sbuf);
CMTime CMSampleBufferGetOutputDuration(CMSampleBufferRef sbuf);
CMTime CMSampleBufferGetOutputPresentationTimeStamp(CMSampleBufferRef sbuf);
OSStatus CMSampleBufferSetOutputPresentationTimeStamp(CMSampleBufferRef sbuf, CMTime outputPresentationTimeStamp);
CMTime CMSampleBufferGetOutputDecodeTimeStamp(CMSampleBufferRef sbuf);
OSStatus CMSampleBufferGetSampleTimingInfo(CMSampleBufferRef sbuf, CMItemIndex sampleIndex,
                                           CMSampleTimingInfo *timingInfoOut);
OSStatus CMSampleBufferGetSampleTimingInfoArray(CMSampleBufferRef sbuf, CMItemCount numSampleTimingEntries,
                                                CMSampleTimingInfo *timingArrayOut,
                                                CMItemCount *timingArrayEntriesNeededOut);
size_t CMSampleBufferGetTotalSampleSize(CMSampleBufferRef sbuf);
size_t CMSampleBufferGetSampleSize(CMSampleBufferRef sbuf, CMItemIndex sampleIndex);
/* one mutable dictionary for each sample, made on asking when createIfNecessary */
CFArrayRef CMSampleBufferGetSampleAttachmentsArray(CMSampleBufferRef sbuf, Boolean createIfNecessary);

/* audio: the samples of a linear PCM sample buffer as an AudioBufferList,
 * one buffer for each channel when they aren't interleaved */
OSStatus CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
    CMSampleBufferRef sbuf, size_t *bufferListSizeNeededOut, AudioBufferList *bufferListOut, size_t bufferListSize,
    CFAllocatorRef blockBufferStructureAllocator, CFAllocatorRef blockBufferBlockAllocator, uint32_t flags,
    CMBlockBufferRef *blockBufferOut);
OSStatus CMSampleBufferSetDataBufferFromAudioBufferList(CMSampleBufferRef sbuf,
                                                        CFAllocatorRef blockBufferStructureAllocator,
                                                        CFAllocatorRef blockBufferBlockAllocator, uint32_t flags,
                                                        const AudioBufferList *bufferList);
OSStatus CMSampleBufferCopyPCMDataIntoAudioBufferList(CMSampleBufferRef sbuf, int32_t frameOffset, int32_t numFrames,
                                                      AudioBufferList *bufferList);
OSStatus CMAudioSampleBufferCreateWithPacketDescriptions(
    CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, Boolean dataReady,
    CMSampleBufferMakeDataReadyCallback makeDataReadyCallback, void *makeDataReadyRefcon,
    CMFormatDescriptionRef formatDescription, CMItemCount numSamples, CMTime presentationTimeStamp,
    const AudioStreamPacketDescription *packetDescriptions, CMSampleBufferRef *sampleBufferOut);
__FERRY_END
#endif
