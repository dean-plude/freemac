/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CFReadStream and CFWriteStream (foundation/NSStream.m), the
 * same objects as NSInputStream and NSOutputStream. Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_CFSTREAM_H_
#define _FERRY_CFSTREAM_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFSocket.h>
#include <dispatch/dispatch.h>

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
typedef struct __CFReadStream *CFReadStreamRef;
typedef struct __CFWriteStream *CFWriteStreamRef;
typedef CFStringRef CFStreamPropertyKey;

typedef CFIndex CFStreamStatus;
enum {
    kCFStreamStatusNotOpen = 0,
    kCFStreamStatusOpening = 1,
    kCFStreamStatusOpen = 2,
    kCFStreamStatusReading = 3,
    kCFStreamStatusWriting = 4,
    kCFStreamStatusAtEnd = 5,
    kCFStreamStatusClosed = 6,
    kCFStreamStatusError = 7,
};
typedef CFOptionFlags CFStreamEventType;
enum {
    kCFStreamEventNone = 0,
    kCFStreamEventOpenCompleted = 1,
    kCFStreamEventHasBytesAvailable = 2,
    kCFStreamEventCanAcceptBytes = 4,
    kCFStreamEventErrorOccurred = 8,
    kCFStreamEventEndEncountered = 16,
};
typedef CFIndex CFStreamErrorDomain;
enum { kCFStreamErrorDomainCustom = -1, kCFStreamErrorDomainPOSIX = 1, kCFStreamErrorDomainMacOSStatus = 2 };
typedef struct {
    CFIndex domain;
    SInt32 error;
} CFStreamError;

typedef struct {
    CFIndex version;
    void *info;
    void *(*retain)(void *info);
    void (*release)(void *info);
    CFStringRef (*copyDescription)(void *info);
} CFStreamClientContext;
typedef void (*CFReadStreamClientCallBack)(CFReadStreamRef stream, CFStreamEventType type, void *clientCallBackInfo);
typedef void (*CFWriteStreamClientCallBack)(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo);

extern const CFStreamPropertyKey kCFStreamPropertyDataWritten;
extern const CFStreamPropertyKey kCFStreamPropertyAppendToFile;
extern const CFStreamPropertyKey kCFStreamPropertyFileCurrentOffset;
extern const CFStreamPropertyKey kCFStreamPropertySocketNativeHandle;
extern const CFStreamPropertyKey kCFStreamPropertySocketRemoteHostName;
extern const CFStreamPropertyKey kCFStreamPropertySocketRemotePortNumber;

CFTypeID CFReadStreamGetTypeID(void);
CFTypeID CFWriteStreamGetTypeID(void);
CFReadStreamRef CFReadStreamCreateWithBytesNoCopy(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex length,
                                                  CFAllocatorRef bytesDeallocator);
CFReadStreamRef CFReadStreamCreateWithData(CFAllocatorRef alloc, CFDataRef data);
CFReadStreamRef CFReadStreamCreateWithFile(CFAllocatorRef alloc, CFURLRef fileURL);
CFWriteStreamRef CFWriteStreamCreateWithBuffer(CFAllocatorRef alloc, UInt8 *buffer, CFIndex bufferCapacity);
CFWriteStreamRef CFWriteStreamCreateWithAllocatedBuffers(CFAllocatorRef alloc, CFAllocatorRef bufferAllocator);
CFWriteStreamRef CFWriteStreamCreateWithFile(CFAllocatorRef alloc, CFURLRef fileURL);
void CFStreamCreateBoundPair(CFAllocatorRef alloc, CFReadStreamRef *readStream, CFWriteStreamRef *writeStream,
                             CFIndex transferBufferSize);
void CFStreamCreatePairWithSocket(CFAllocatorRef alloc, CFSocketNativeHandle sock, CFReadStreamRef *readStream,
                                  CFWriteStreamRef *writeStream);
void CFStreamCreatePairWithSocketToHost(CFAllocatorRef alloc, CFStringRef host, UInt32 port,
                                        CFReadStreamRef *readStream, CFWriteStreamRef *writeStream);

CFStreamStatus CFReadStreamGetStatus(CFReadStreamRef stream);
CFStreamStatus CFWriteStreamGetStatus(CFWriteStreamRef stream);
CFErrorRef CFReadStreamCopyError(CFReadStreamRef stream);
CFErrorRef CFWriteStreamCopyError(CFWriteStreamRef stream);
CFStreamError CFReadStreamGetError(CFReadStreamRef stream);
CFStreamError CFWriteStreamGetError(CFWriteStreamRef stream);
Boolean CFReadStreamOpen(CFReadStreamRef stream);
Boolean CFWriteStreamOpen(CFWriteStreamRef stream);
void CFReadStreamClose(CFReadStreamRef stream);
void CFWriteStreamClose(CFWriteStreamRef stream);
Boolean CFReadStreamHasBytesAvailable(CFReadStreamRef stream);
CFIndex CFReadStreamRead(CFReadStreamRef stream, UInt8 *buffer, CFIndex bufferLength);
const UInt8 *CFReadStreamGetBuffer(CFReadStreamRef stream, CFIndex maxBytesToRead, CFIndex *numBytesRead);
Boolean CFWriteStreamCanAcceptBytes(CFWriteStreamRef stream);
CFIndex CFWriteStreamWrite(CFWriteStreamRef stream, const UInt8 *buffer, CFIndex bufferLength);
CFTypeRef CFReadStreamCopyProperty(CFReadStreamRef stream, CFStreamPropertyKey propertyName);
CFTypeRef CFWriteStreamCopyProperty(CFWriteStreamRef stream, CFStreamPropertyKey propertyName);
Boolean CFReadStreamSetProperty(CFReadStreamRef stream, CFStreamPropertyKey propertyName, CFTypeRef propertyValue);
Boolean CFWriteStreamSetProperty(CFWriteStreamRef stream, CFStreamPropertyKey propertyName, CFTypeRef propertyValue);
Boolean CFReadStreamSetClient(CFReadStreamRef stream, CFOptionFlags streamEvents, CFReadStreamClientCallBack clientCB,
                              CFStreamClientContext *clientContext);
Boolean CFWriteStreamSetClient(CFWriteStreamRef stream, CFOptionFlags streamEvents,
                               CFWriteStreamClientCallBack clientCB, CFStreamClientContext *clientContext);
void CFReadStreamScheduleWithRunLoop(CFReadStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode);
void CFWriteStreamScheduleWithRunLoop(CFWriteStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode);
void CFReadStreamUnscheduleFromRunLoop(CFReadStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode);
void CFWriteStreamUnscheduleFromRunLoop(CFWriteStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode);
void CFReadStreamSetDispatchQueue(CFReadStreamRef stream, dispatch_queue_t q);
void CFWriteStreamSetDispatchQueue(CFWriteStreamRef stream, dispatch_queue_t q);
dispatch_queue_t CFReadStreamCopyDispatchQueue(CFReadStreamRef stream);
dispatch_queue_t CFWriteStreamCopyDispatchQueue(CFWriteStreamRef stream);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
