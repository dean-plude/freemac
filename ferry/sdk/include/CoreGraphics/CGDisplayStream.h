/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: display streams (freemac 1.238, Ferry 0.62.0), the older way
 * to record a display: frames as IOSurfaces handed to a block on a queue.
 * Written for freemac from Apple's public documentation of
 * CGDisplayStream; not Apple's header. Served from AppKit's file
 * (appkit/CGDisplayStream.m), and only once the user has let the app
 * record the screen (CGRequestScreenCaptureAccess): without the say,
 * CGDisplayStreamCreate... gives NULL. A run loop stream is not here, only
 * the dispatch queue one. Every update says the whole frame changed. */
#ifndef _FERRY_CGDISPLAYSTREAM_H_
#define _FERRY_CGDISPLAYSTREAM_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreGraphics/CGDirectDisplay.h>
/* IOSurfaceRef as IOSurface/IOSurfaceRef.h has it, without that header,
 * which needs Foundation (and Foundation this framework) */
#ifndef _FERRY_IOSURFACEREF_DEFINED
#define _FERRY_IOSURFACEREF_DEFINED
#if defined(__has_attribute) && __has_attribute(objc_bridge)
typedef struct __attribute__((objc_bridge(id))) __IOSurface *IOSurfaceRef;
#else
typedef struct __IOSurface *IOSurfaceRef;
#endif
#endif
#include <dispatch/dispatch.h>

__FERRY_BEGIN

typedef struct CGDisplayStream *CGDisplayStreamRef;
typedef const struct CGDisplayStreamUpdate *CGDisplayStreamUpdateRef;

typedef int32_t CGDisplayStreamUpdateRectType;
enum {
    kCGDisplayStreamUpdateRefreshedRects = 0,
    kCGDisplayStreamUpdateMovedRects = 1,
    kCGDisplayStreamUpdateDirtyRects = 2,
    kCGDisplayStreamUpdateReducedDirtyRects = 3,
};
typedef int32_t CGDisplayStreamFrameStatus;
enum {
    kCGDisplayStreamFrameStatusFrameComplete = 0,
    kCGDisplayStreamFrameStatusFrameIdle = 1,
    kCGDisplayStreamFrameStatusFrameBlank = 2,
    kCGDisplayStreamFrameStatusStopped = 3,
};

/* the keys of the properties a stream is made with */
extern const CFStringRef kCGDisplayStreamSourceRect;          /* a CGRect's dictionary, in points */
extern const CFStringRef kCGDisplayStreamDestinationRect;     /* a CGRect's dictionary, in the output's pixels */
extern const CFStringRef kCGDisplayStreamPreserveAspectRatio; /* CFBoolean, true when not given */
extern const CFStringRef kCGDisplayStreamColorSpace;          /* a colour space's name */
extern const CFStringRef kCGDisplayStreamMinimumFrameTime;    /* CFNumber, seconds */
extern const CFStringRef kCGDisplayStreamShowCursor;          /* CFBoolean */
extern const CFStringRef kCGDisplayStreamQueueDepth;          /* CFNumber, 3 when not given, at most 8 */
extern const CFStringRef kCGDisplayStreamYCbCrMatrix;
extern const CFStringRef kCGDisplayStreamYCbCrMatrix_ITU_R_709_2;
extern const CFStringRef kCGDisplayStreamYCbCrMatrix_ITU_R_601_4;
extern const CFStringRef kCGDisplayStreamYCbCrMatrix_SMPTE_240M_1995;

#ifdef __BLOCKS__
typedef void (^CGDisplayStreamFrameAvailableHandler)(CGDisplayStreamFrameStatus status, uint64_t displayTime,
                                                     IOSurfaceRef frameSurface,
                                                     CGDisplayStreamUpdateRef updateRef);
#else
typedef void *CGDisplayStreamFrameAvailableHandler;
#endif

CFTypeID CGDisplayStreamGetTypeID(void);
CFTypeID CGDisplayStreamUpdateGetTypeID(void);
/* outputPixelFormat is 'BGRA', 'l10r', '420v' or '420f' */
CGDisplayStreamRef CGDisplayStreamCreateWithDispatchQueue(CGDirectDisplayID display, size_t outputWidth,
                                                          size_t outputHeight, int32_t pixelFormat,
                                                          CFDictionaryRef properties, dispatch_queue_t queue,
                                                          CGDisplayStreamFrameAvailableHandler handler);
CGError CGDisplayStreamStart(CGDisplayStreamRef displayStream);
CGError CGDisplayStreamStop(CGDisplayStreamRef displayStream);
const CGRect *CGDisplayStreamUpdateGetRects(CGDisplayStreamUpdateRef updateRef, CGDisplayStreamUpdateRectType rectType,
                                            size_t *rectCount);
CGDisplayStreamUpdateRef CGDisplayStreamUpdateCreateMergedUpdate(CGDisplayStreamUpdateRef firstUpdate,
                                                                 CGDisplayStreamUpdateRef secondUpdate);
void CGDisplayStreamUpdateGetMovedRectsDelta(CGDisplayStreamUpdateRef updateRef, CGFloat *dx, CGFloat *dy);
size_t CGDisplayStreamUpdateGetDropCount(CGDisplayStreamUpdateRef updateRef);

__FERRY_END
#endif
