/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's screen capture (freemac 1.238, Ferry 0.62.0): what
 * ScreenCaptureKit (screencapturekit/), display streams
 * (CGDisplayStream.m) and the window list's pictures (CGServices.m) share.
 * It lives in AppKit's file beside the window list, as it needs the
 * user's say and the app's own windows.
 *
 * The user's say: kept in ~/.config/freemac/screen-recording.json, asked
 * once with freemac-allow-control --kind screen-recording (or the program
 * FERRY_ACCESS_ASKER names, for the tests).
 *
 * Back ends: what lists the displays and windows and grabs their pixels.
 * X11 (ACaptureX11.m) reads the X server's screen and windows; the
 * Wayland one (ACapturePortal.m) would go through the xdg-desktop-portal's
 * ScreenCast portal and PipeWire, and is not written yet. FERRY_CAPTURE
 * (x11, portal or none) chooses one; otherwise a Wayland session gets the
 * portal and an X11 session X11.
 *
 * Streams: a frame each interval on a capture queue of the stream's own,
 * grabbed, scaled into a ring of IOSurface-backed Core Video pixel buffers
 * in the output's size and pixel format, and handed to the stream's
 * handler on its queue. A buffer is used again only once nobody holds it
 * (the app hasn't retained it, its surface or its use count); with none
 * free the frame is dropped and counted.
 */
#ifndef FERRY_APPKIT_ACAPTURE_H
#define FERRY_APPKIT_ACAPTURE_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreVideo/CoreVideo.h>
#include <dispatch/dispatch.h>

/* ---- the user's say ------------------------------------------------------------------ */

/* 1 allowed, 0 not allowed, -1 not asked yet */
int ACaptureStoredAnswer(void);
BOOL ACaptureAllowed(void);
/* asks the user, once in the program's life, without waiting */
void ACaptureAsk(void);

/* ---- displays and windows --------------------------------------------------------------- */

@interface ACaptureDisplay : NSObject {
  @public
    CGDirectDisplayID number;
    CGRect frame;          /* in points, from the main display's top left, y down */
    CGRect pixelFrame;     /* the same in the back end's pixels */
    CGFloat scale;
    double refreshRate;
}
@end

@interface ACaptureWindow : NSObject {
  @public
    CGWindowID number;     /* the window list's: an own window's windowNumber, or 0x40000000 | handle */
    uint64_t handle;       /* the back end's (an X window id) */
    pid_t pid;
    NSString *title, *owner, *bundleID;
    CGRect frame;          /* in points, from the main display's top left, y down */
    CGRect pixelFrame;     /* the same in the back end's pixels */
    BOOL onscreen, own;
    NSInteger layer;
}
@end

/* Any thread. The windows come front to back, the app's own among them
 * (matched to its NSWindows). */
NSArray<ACaptureDisplay *> *ACaptureDisplays(void);
NSArray<ACaptureWindow *> *ACaptureWindows(void);
ACaptureDisplay *ACaptureDisplayNumbered(CGDirectDisplayID number);
ACaptureWindow *ACaptureWindowNumbered(CGWindowID number);
/* On the main thread, notes the app's own windows now, so that a listing
 * made off it soon after has them (off it, it does nothing). */
void ACaptureNoteOwnWindows(void);
/* whether there is a back end that can capture, and its name */
BOOL ACaptureAvailable(void);
const char *ACaptureBackendName(void);
/* A picture of the screen (a rect in points from the main display's top
 * left; CGRectInfinite or CGRectNull for all of it) or of a window, as a
 * CGImage, without asking for the say: the caller has. */
CGImageRef ACaptureCreateScreenImage(CGRect points);
CGImageRef ACaptureCreateWindowImage(CGWindowID number);

/* ---- streams ------------------------------------------------------------------------------ */

typedef enum {
    ACaptureSourceDisplay = 0,  /* a display, or the part of it in sourceRect */
    ACaptureSourceWindow = 1,   /* one window, by itself */
    ACaptureSourceWindows = 2,  /* a display showing only some windows (or all but some) */
} ACaptureSourceKind;

@interface ACaptureConfig : NSObject <NSCopying> {
  @public
    ACaptureSourceKind kind;
    CGDirectDisplayID display;
    CGWindowID window;
    /* For ACaptureSourceWindows: a window is picked when its number is in
     * windows or its pid in pids, and its number isn't in exceptions. The
     * picked windows show (the rest of the display is the background), or,
     * with excluding set, all but the picked ones show (they are painted
     * over with the background). NSNumbers. */
    NSArray *windows, *pids, *exceptions;
    BOOL excluding;
    CGRect sourceRect;          /* points within the display; CGRectNull for all of it */
    CGRect destinationRect;     /* pixels of the output; CGRectNull to fit */
    size_t width, height;       /* the output's, in pixels */
    OSType pixelFormat;         /* 'BGRA', 'l10r', '420v' or '420f' */
    NSInteger queueDepth;
    BOOL showsCursor, scalesToFit, preservesAspectRatio, windowAtTopLeft;
    uint64_t minimumInterval;   /* nanoseconds between frames, at least */
    uint32_t background;        /* 0xAARRGGBB, not premultiplied */
    BOOL ycbcr601;
}
@end

typedef struct {
    CVPixelBufferRef frame;     /* NULL when stopped */
    uint64_t displayTime;       /* mach_absolute_time of the grab */
    CGRect contentRect;         /* where the content is drawn, in the frame's pixels */
    CGFloat contentScale;       /* drawn size over the source's size in pixels */
    CGFloat scaleFactor;        /* the source's pixels per point */
    size_t dropped;             /* frames dropped since the last one delivered */
    BOOL stopped;
    NSError *error;             /* why it stopped, when not asked to */
} ACaptureFrame;
typedef void (^ACaptureFrameHandler)(const ACaptureFrame *frame);

@interface ACaptureStream : NSObject
- (instancetype)initWithConfig:(ACaptureConfig *)config queue:(dispatch_queue_t)queue
                       handler:(ACaptureFrameHandler)handler;
/* NO when there's no back end or the source isn't there (error says which) */
- (BOOL)start:(NSError **)error;
/* the handler is called once more, with stopped set; then never again */
- (void)stop;
- (void)stopWithError:(NSError *)error;
- (void)setConfig:(ACaptureConfig *)config;
- (BOOL)isRunning;
@end

/* ---- the back ends' interface (ACaptureX11.m, ACapturePortal.m) --------------------- */

typedef struct {
    uint8_t *data;              /* B, G, R, X bytes for each pixel, top row first; writable */
    size_t width, height, bytesPerRow;
} ACaptureImage;
typedef struct {
    const uint32_t *argb;       /* premultiplied 0xAARRGGBB */
    size_t width, height;
    long x, y;                  /* the image's top left, in the back end's pixels */
} ACaptureCursor;

typedef struct ACaptureBackend {
    const char *name;
    BOOL (*available)(void);
    /* autoreleased; windows front to back with number left 0 and own NO */
    NSArray *(*displays)(void);
    NSArray *(*windows)(void);
    /* a connection for one stream, used on one queue at a time */
    void *(*open)(void);
    void (*close)(void *grabber);
    /* the image stays the grabber's, good until its next grab */
    BOOL (*grabScreen)(void *grabber, CGRect pixels, ACaptureImage *out);
    BOOL (*grabWindow)(void *grabber, uint64_t handle, ACaptureImage *out, CGRect *pixelFrame);
    BOOL (*cursor)(void *grabber, ACaptureCursor *out);
} ACaptureBackend;
extern const ACaptureBackend ACaptureX11Backend;
extern const ACaptureBackend ACapturePortalBackend;
/* says once on stderr why a back end can't be used */
void ACaptureSayOnce(const char *what);

/* the error ScreenCaptureKit reports (SCStreamErrorDomain) */
NSError *ACaptureError(NSInteger code, NSString *description);

#endif
