/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia's block buffers (freemac 1.238, Ferry 0.62.0;
 * appkit/CMSampleBuffer.m). Written for freemac from Apple's public API
 * documentation; not Apple's header. A block buffer is a run of bytes
 * made of one or more memory blocks, its own or other block buffers'. */
#ifndef _FERRY_CMBLOCKBUFFER_H_
#define _FERRY_CMBLOCKBUFFER_H_
#include <CoreFoundation/CoreFoundation.h>
#include <MacTypes.h>

__FERRY_BEGIN
typedef struct OpaqueCMBlockBuffer *CMBlockBufferRef;
typedef uint32_t CMBlockBufferFlags;
enum {
    kCMBlockBufferAssureMemoryNowFlag = 1U << 0,
    kCMBlockBufferAlwaysCopyDataFlag = 1U << 1,
    kCMBlockBufferDontOptimizeDepthFlag = 1U << 2,
    kCMBlockBufferPermitEmptyReferenceFlag = 1U << 3,
};
enum {
    kCMBlockBufferNoErr = 0,
    kCMBlockBufferStructureAllocationFailedErr = -12700,
    kCMBlockBufferBlockAllocationFailedErr = -12701,
    kCMBlockBufferBadCustomBlockSourceErr = -12702,
    kCMBlockBufferBadOffsetParameterErr = -12703,
    kCMBlockBufferBadLengthParameterErr = -12704,
    kCMBlockBufferBadPointerParameterErr = -12705,
    kCMBlockBufferEmptyBBufErr = -12706,
    kCMBlockBufferUnallocatedBlockErr = -12707,
    kCMBlockBufferInsufficientSpaceErr = -12708,
};
enum { kCMBlockBufferCustomBlockSourceVersion = 0 };
typedef struct {
    uint32_t version;
    void *(*AllocateBlock)(void *refCon, size_t sizeInBytes);
    void (*FreeBlock)(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes);
    void *refCon;
} CMBlockBufferCustomBlockSource;

CFTypeID CMBlockBufferGetTypeID(void);
OSStatus CMBlockBufferCreateEmpty(CFAllocatorRef structureAllocator, uint32_t subBlockCapacity,
                                  CMBlockBufferFlags flags, CMBlockBufferRef *blockBufferOut);
OSStatus CMBlockBufferCreateWithMemoryBlock(CFAllocatorRef structureAllocator, void *memoryBlock, size_t blockLength,
                                            CFAllocatorRef blockAllocator,
                                            const CMBlockBufferCustomBlockSource *customBlockSource,
                                            size_t offsetToData, size_t dataLength, CMBlockBufferFlags flags,
                                            CMBlockBufferRef *blockBufferOut);
OSStatus CMBlockBufferCreateWithBufferReference(CFAllocatorRef structureAllocator, CMBlockBufferRef bufferReference,
                                                size_t offsetToData, size_t dataLength, CMBlockBufferFlags flags,
                                                CMBlockBufferRef *blockBufferOut);
OSStatus CMBlockBufferCreateContiguous(CFAllocatorRef structureAllocator, CMBlockBufferRef sourceBuffer,
                                       CFAllocatorRef blockAllocator,
                                       const CMBlockBufferCustomBlockSource *customBlockSource, size_t offsetToData,
                                       size_t dataLength, CMBlockBufferFlags flags, CMBlockBufferRef *blockBufferOut);
OSStatus CMBlockBufferAppendMemoryBlock(CMBlockBufferRef theBuffer, void *memoryBlock, size_t blockLength,
                                        CFAllocatorRef blockAllocator,
                                        const CMBlockBufferCustomBlockSource *customBlockSource, size_t offsetToData,
                                        size_t dataLength, CMBlockBufferFlags flags);
OSStatus CMBlockBufferAppendBufferReference(CMBlockBufferRef theBuffer, CMBlockBufferRef targetBBuf,
                                            size_t offsetToData, size_t dataLength, CMBlockBufferFlags flags);
OSStatus CMBlockBufferAssureBlockMemory(CMBlockBufferRef theBuffer);
OSStatus CMBlockBufferAccessDataBytes(CMBlockBufferRef theBuffer, size_t offset, size_t length, void *temporaryBlock,
                                      char **returnedPointerOut);
OSStatus CMBlockBufferCopyDataBytes(CMBlockBufferRef theSourceBuffer, size_t offsetToData, size_t dataLength,
                                    void *destination);
OSStatus CMBlockBufferReplaceDataBytes(const void *sourceBytes, CMBlockBufferRef destinationBuffer,
                                       size_t offsetIntoDestination, size_t dataLength);
OSStatus CMBlockBufferFillDataBytes(char fillByte, CMBlockBufferRef destinationBuffer, size_t offsetIntoDestination,
                                    size_t dataLength);
OSStatus CMBlockBufferGetDataPointer(CMBlockBufferRef theBuffer, size_t offset, size_t *lengthAtOffsetOut,
                                     size_t *totalLengthOut, char **dataPointerOut);
size_t CMBlockBufferGetDataLength(CMBlockBufferRef theBuffer);
Boolean CMBlockBufferIsRangeContiguous(CMBlockBufferRef theBuffer, size_t offset, size_t length);
Boolean CMBlockBufferIsEmpty(CMBlockBufferRef theBuffer);
__FERRY_END
#endif
