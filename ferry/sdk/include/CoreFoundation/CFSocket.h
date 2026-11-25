/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: run loop sources and CFSocket (foundation/CFSocket.m). Written
 * for freemac from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_CFSOCKET_H_
#define _FERRY_CFSOCKET_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
/* ---- run loop sources ------------------------------------------------------------- */

typedef struct __CFRunLoopSource *CFRunLoopSourceRef;
typedef struct {
    CFIndex version; /* 0: a source the program signals (CFRunLoopSourceSignal) */
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
    Boolean (*equal)(const void *info1, const void *info2);
    CFHashCode (*hash)(const void *info);
    void (*schedule)(void *info, CFRunLoopRef rl, CFRunLoopMode mode);
    void (*cancel)(void *info, CFRunLoopRef rl, CFRunLoopMode mode);
    void (*perform)(void *info);
} CFRunLoopSourceContext;

CFTypeID CFRunLoopSourceGetTypeID(void);
CFRunLoopSourceRef CFRunLoopSourceCreate(CFAllocatorRef allocator, CFIndex order, CFRunLoopSourceContext *context);
CFIndex CFRunLoopSourceGetOrder(CFRunLoopSourceRef source);
void CFRunLoopSourceGetContext(CFRunLoopSourceRef source, CFRunLoopSourceContext *context);
void CFRunLoopSourceSignal(CFRunLoopSourceRef source);
void CFRunLoopSourceInvalidate(CFRunLoopSourceRef source);
Boolean CFRunLoopSourceIsValid(CFRunLoopSourceRef source);
void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFRunLoopMode mode);
void CFRunLoopRemoveSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFRunLoopMode mode);
Boolean CFRunLoopContainsSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFRunLoopMode mode);

/* ---- CFSocket ---------------------------------------------------------------------- */

typedef struct __CFSocket *CFSocketRef;
typedef int CFSocketNativeHandle;

typedef CFIndex CFSocketError;
enum { kCFSocketSuccess = 0, kCFSocketError = -1, kCFSocketTimeout = -2 };

typedef CFOptionFlags CFSocketCallBackType;
enum {
    kCFSocketNoCallBack = 0,
    kCFSocketReadCallBack = 1,
    kCFSocketAcceptCallBack = 2,
    kCFSocketDataCallBack = 3,
    kCFSocketConnectCallBack = 4,
    kCFSocketWriteCallBack = 8,
};
enum {
    kCFSocketAutomaticallyReenableReadCallBack = 1,
    kCFSocketAutomaticallyReenableAcceptCallBack = 2,
    kCFSocketAutomaticallyReenableDataCallBack = 3,
    kCFSocketAutomaticallyReenableWriteCallBack = 8,
    kCFSocketLeaveErrors = 64,
    kCFSocketCloseOnInvalidate = 128,
};

typedef void (*CFSocketCallBack)(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data,
                                 void *info);
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFSocketContext;
typedef struct {
    SInt32 protocolFamily;
    SInt32 socketType;
    SInt32 protocol;
    CFDataRef address;
} CFSocketSignature;

CFTypeID CFSocketGetTypeID(void);
CFSocketRef CFSocketCreate(CFAllocatorRef allocator, SInt32 protocolFamily, SInt32 socketType, SInt32 protocol,
                           CFOptionFlags callBackTypes, CFSocketCallBack callout, const CFSocketContext *context);
CFSocketRef CFSocketCreateWithNative(CFAllocatorRef allocator, CFSocketNativeHandle sock, CFOptionFlags callBackTypes,
                                     CFSocketCallBack callout, const CFSocketContext *context);
CFSocketRef CFSocketCreateWithSocketSignature(CFAllocatorRef allocator, const CFSocketSignature *signature,
                                              CFOptionFlags callBackTypes, CFSocketCallBack callout,
                                              const CFSocketContext *context);
CFSocketRef CFSocketCreateConnectedToSocketSignature(CFAllocatorRef allocator, const CFSocketSignature *signature,
                                                     CFOptionFlags callBackTypes, CFSocketCallBack callout,
                                                     const CFSocketContext *context, CFTimeInterval timeout);
CFSocketError CFSocketSetAddress(CFSocketRef s, CFDataRef address);
CFSocketError CFSocketConnectToAddress(CFSocketRef s, CFDataRef address, CFTimeInterval timeout);
CFSocketError CFSocketSendData(CFSocketRef s, CFDataRef address, CFDataRef data, CFTimeInterval timeout);
CFDataRef CFSocketCopyAddress(CFSocketRef s);
CFDataRef CFSocketCopyPeerAddress(CFSocketRef s);
CFSocketNativeHandle CFSocketGetNative(CFSocketRef s);
void CFSocketGetContext(CFSocketRef s, CFSocketContext *context);
CFOptionFlags CFSocketGetSocketFlags(CFSocketRef s);
void CFSocketSetSocketFlags(CFSocketRef s, CFOptionFlags flags);
void CFSocketEnableCallBacks(CFSocketRef s, CFOptionFlags callBackTypes);
void CFSocketDisableCallBacks(CFSocketRef s, CFOptionFlags callBackTypes);
void CFSocketInvalidate(CFSocketRef s);
Boolean CFSocketIsValid(CFSocketRef s);
CFRunLoopSourceRef CFSocketCreateRunLoopSource(CFAllocatorRef allocator, CFSocketRef s, CFIndex order);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
