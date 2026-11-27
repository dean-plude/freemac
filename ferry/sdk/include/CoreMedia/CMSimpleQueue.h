/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CMSimpleQueue (appkit/CMSampleBuffer.m, freemac 1.264), a
 * fixed-size queue of pointers, first in first out. Written for freemac
 * from Apple's public Core Media documentation; not Apple's header. */
#ifndef _FERRY_CMSIMPLEQUEUE_H_
#define _FERRY_CMSIMPLEQUEUE_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef struct opaqueCMSimpleQueue *CMSimpleQueueRef;
enum {
    kCMSimpleQueueError_AllocationFailed = -12770,
    kCMSimpleQueueError_RequiredParameterMissing = -12771,
    kCMSimpleQueueError_ParameterOutOfRange = -12772,
    kCMSimpleQueueError_QueueIsFull = -12773,
};
CFTypeID CMSimpleQueueGetTypeID(void);
OSStatus CMSimpleQueueCreate(CFAllocatorRef allocator, int32_t capacity, CMSimpleQueueRef *queueOut);
OSStatus CMSimpleQueueEnqueue(CMSimpleQueueRef queue, const void *element);
const void *CMSimpleQueueDequeue(CMSimpleQueueRef queue);
const void *CMSimpleQueueGetHead(CMSimpleQueueRef queue);
OSStatus CMSimpleQueueReset(CMSimpleQueueRef queue);
int32_t CMSimpleQueueGetCapacity(CMSimpleQueueRef queue);
int32_t CMSimpleQueueGetCount(CMSimpleQueueRef queue);
__FERRY_END
#endif
