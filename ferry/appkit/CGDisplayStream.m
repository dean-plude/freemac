/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Display streams and display modes (freemac 1.238, Ferry 0.62.0),
 * written from Apple's public documentation of CGDisplayStream and
 * CGDisplayMode: see CoreGraphics/CGDisplayStream.h. A display stream is
 * one of Ferry's capture streams (ACapture.h) handing its frames'
 * IOSurfaces to the app's block; OBS Studio's older display capture reads
 * the screen this way. A display has one mode, the one it runs in. */
#import "AInternal.h"
#import "ACapture.h"
#include <IOSurface/IOSurface.h>
#include <mach/mach_time.h>

/* ---- display modes ----------------------------------------------------------------------------- */

@interface FerryCGDisplayMode : NSObject {
  @public
    size_t width, height, pixelWidth, pixelHeight;
    double refreshRate;
}
@end
@implementation FerryCGDisplayMode
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CGDisplayMode %zux%zu (%zux%zu pixels) %gHz>", width, height, pixelWidth,
                                      pixelHeight, refreshRate];
}
@end
#define MODE(m) ((FerryCGDisplayMode *)(m))
static BOOL is_mode(CGDisplayModeRef m) { return m && [(id)m isKindOfClass:[FerryCGDisplayMode class]]; }


CFTypeID CGDisplayModeGetTypeID(void) { return (CFTypeID)[FerryCGDisplayMode class]; }

CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID display)
{
    @autoreleasepool {
        FerryCGDisplayMode *m = [[FerryCGDisplayMode alloc] init];
        /* the capture back end's answer works on any thread; AppKit's screens otherwise */
        ACaptureDisplay *d = ACaptureAvailable() ? ACaptureDisplayNumbered(display) : nil;
        if (d) {
            m->width = (size_t)d->frame.size.width;
            m->height = (size_t)d->frame.size.height;
            m->pixelWidth = (size_t)d->pixelFrame.size.width;
            m->pixelHeight = (size_t)d->pixelFrame.size.height;
            m->refreshRate = d->refreshRate;
        } else {
            CGRect b = CGDisplayBounds(display);
            if (CGRectIsEmpty(b)) {
                [m release];
                return NULL;
            }
            m->width = (size_t)b.size.width;
            m->height = (size_t)b.size.height;
            m->pixelWidth = CGDisplayPixelsWide(display);
            m->pixelHeight = CGDisplayPixelsHigh(display);
            m->refreshRate = 60;
        }
        return (CGDisplayModeRef)m;
    }
}
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID display, CFDictionaryRef options)
{
    CGDisplayModeRef m = CGDisplayCopyDisplayMode(display);
    if (!m)
        return NULL;
    CFArrayRef a = (CFArrayRef)[[NSArray alloc] initWithObjects:(id)m, nil];
    CFRelease(m);
    return a;
}
CGError CGDisplaySetDisplayMode(CGDirectDisplayID display, CGDisplayModeRef mode, CFDictionaryRef options)
{
    /* the one mode it has is all a display can be set to */
    CGDisplayModeRef now = CGDisplayCopyDisplayMode(display);
    BOOL same = now && is_mode(mode) && MODE(mode)->pixelWidth == MODE(now)->pixelWidth &&
                MODE(mode)->pixelHeight == MODE(now)->pixelHeight;
    if (now)
        CFRelease(now);
    return same ? kCGErrorSuccess : kCGErrorIllegalArgument;
}
CGDisplayModeRef CGDisplayModeRetain(CGDisplayModeRef m) { return m ? (CGDisplayModeRef)[(id)m retain] : NULL; }
void CGDisplayModeRelease(CGDisplayModeRef m)
{
    if (m)
        [(id)m release];
}
size_t CGDisplayModeGetWidth(CGDisplayModeRef m) { return is_mode(m) ? MODE(m)->width : 0; }
size_t CGDisplayModeGetHeight(CGDisplayModeRef m) { return is_mode(m) ? MODE(m)->height : 0; }
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef m) { return is_mode(m) ? MODE(m)->pixelWidth : 0; }
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef m) { return is_mode(m) ? MODE(m)->pixelHeight : 0; }
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m) { return is_mode(m) ? MODE(m)->refreshRate : 0; }
uint32_t CGDisplayModeGetIOFlags(CGDisplayModeRef m)
{
    return is_mode(m) ? kDisplayModeValidFlag | kDisplayModeSafeFlag | kDisplayModeDefaultFlag | kDisplayModeNativeFlag : 0;
}
int32_t CGDisplayModeGetIODisplayModeID(CGDisplayModeRef m) { return is_mode(m) ? 1 : 0; }
bool CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef m) { return is_mode(m); }

/* A display's size, rotation, numbers and UUID are in CGDirectDisplay.m. */

/* ---- display streams ----------------------------------------------------------------------------- */

#define DKEY(name, value) const CFStringRef name = (CFStringRef)@value;
DKEY(kCGDisplayStreamSourceRect, "kCGDisplayStreamSourceRect")
DKEY(kCGDisplayStreamDestinationRect, "kCGDisplayStreamDestinationRect")
DKEY(kCGDisplayStreamPreserveAspectRatio, "kCGDisplayStreamPreserveAspectRatio")
DKEY(kCGDisplayStreamColorSpace, "kCGDisplayStreamColorSpace")
DKEY(kCGDisplayStreamMinimumFrameTime, "kCGDisplayStreamMinimumFrameTime")
DKEY(kCGDisplayStreamShowCursor, "kCGDisplayStreamShowCursor")
DKEY(kCGDisplayStreamQueueDepth, "kCGDisplayStreamQueueDepth")
DKEY(kCGDisplayStreamYCbCrMatrix, "kCGDisplayStreamYCbCrMatrix")
DKEY(kCGDisplayStreamYCbCrMatrix_ITU_R_709_2, "ITU_R_709_2")
DKEY(kCGDisplayStreamYCbCrMatrix_ITU_R_601_4, "ITU_R_601_4")
DKEY(kCGDisplayStreamYCbCrMatrix_SMPTE_240M_1995, "SMPTE_240M_1995")

@interface FerryCGDisplayStreamUpdate : NSObject {
  @public
    CGRect rect;
    size_t dropCount;
}
@end
@implementation FerryCGDisplayStreamUpdate
@end
#define UPD(u) ((FerryCGDisplayStreamUpdate *)(u))
static BOOL is_update(CGDisplayStreamUpdateRef u) { return u && [(id)u isKindOfClass:[FerryCGDisplayStreamUpdate class]]; }

@interface FerryCGDisplayStream : NSObject {
  @public
    ACaptureStream *stream;
    BOOL started;
}
@end
@implementation FerryCGDisplayStream
- (void)dealloc
{
    [stream stop];
    [stream release];
    [super dealloc];
}
@end
#define DS(s) ((FerryCGDisplayStream *)(s))
static BOOL is_stream(CGDisplayStreamRef s) { return s && [(id)s isKindOfClass:[FerryCGDisplayStream class]]; }

CFTypeID CGDisplayStreamGetTypeID(void) { return (CFTypeID)[FerryCGDisplayStream class]; }
CFTypeID CGDisplayStreamUpdateGetTypeID(void) { return (CFTypeID)[FerryCGDisplayStreamUpdate class]; }

static BOOL bool_of(NSDictionary *d, CFStringRef key, BOOL otherwise)
{
    id v = [d objectForKey:(id)key];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : otherwise;
}

CGDisplayStreamRef CGDisplayStreamCreateWithDispatchQueue(CGDirectDisplayID display, size_t outputWidth,
                                                          size_t outputHeight, int32_t pixelFormat,
                                                          CFDictionaryRef properties, dispatch_queue_t queue,
                                                          CGDisplayStreamFrameAvailableHandler handler)
{
    if (!handler || !queue || !outputWidth || !outputHeight)
        return NULL;
    if (pixelFormat != 'BGRA' && pixelFormat != 'l10r' && pixelFormat != '420v' && pixelFormat != '420f')
        return NULL;
    if (!CGRequestScreenCaptureAccess())
        return NULL;    /* the user hasn't let the app record the screen (asked, the first time) */
    @autoreleasepool {
        if (!ACaptureAvailable() || !ACaptureDisplayNumbered(display))
            return NULL;
        NSDictionary *p = [(id)properties isKindOfClass:[NSDictionary class]] ? (NSDictionary *)properties : @{};
        ACaptureConfig *c = [[[ACaptureConfig alloc] init] autorelease];
        c->kind = ACaptureSourceDisplay;
        c->display = display;
        c->width = outputWidth;
        c->height = outputHeight;
        c->pixelFormat = (OSType)pixelFormat;
        CGRect r;
        id v = [p objectForKey:(id)kCGDisplayStreamSourceRect];
        if ([v isKindOfClass:[NSDictionary class]] && CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)v, &r))
            c->sourceRect = r;
        v = [p objectForKey:(id)kCGDisplayStreamDestinationRect];
        if ([v isKindOfClass:[NSDictionary class]] && CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)v, &r))
            c->destinationRect = r;
        c->preservesAspectRatio = bool_of(p, kCGDisplayStreamPreserveAspectRatio, YES);
        c->showsCursor = bool_of(p, kCGDisplayStreamShowCursor, NO);
        v = [p objectForKey:(id)kCGDisplayStreamQueueDepth];
        c->queueDepth = [v respondsToSelector:@selector(integerValue)] ? MAX(1, MIN(8, [v integerValue])) : 3;
        v = [p objectForKey:(id)kCGDisplayStreamMinimumFrameTime];
        if ([v respondsToSelector:@selector(doubleValue)] && [v doubleValue] > 0)
            c->minimumInterval = (uint64_t)([v doubleValue] * 1e9);
        v = [p objectForKey:(id)kCGDisplayStreamYCbCrMatrix];
        c->ycbcr601 = [v isEqual:(id)kCGDisplayStreamYCbCrMatrix_ITU_R_601_4];
        c->background = 0xff000000u;

        CGDisplayStreamFrameAvailableHandler block = [[handler copy] autorelease];
        ACaptureFrameHandler h = ^(const ACaptureFrame *f) {
            if (f->stopped) {
                block(kCGDisplayStreamFrameStatusStopped, f->displayTime, NULL, NULL);
                return;
            }
            FerryCGDisplayStreamUpdate *u = [[FerryCGDisplayStreamUpdate alloc] init];
            u->rect = CGRectMake(0, 0, CVPixelBufferGetWidth(f->frame), CVPixelBufferGetHeight(f->frame));
            u->dropCount = f->dropped;
            block(kCGDisplayStreamFrameStatusFrameComplete, f->displayTime, CVPixelBufferGetIOSurface(f->frame),
                  (CGDisplayStreamUpdateRef)u);
            [u release];
        };
        FerryCGDisplayStream *s = [[FerryCGDisplayStream alloc] init];
        s->stream = [[ACaptureStream alloc] initWithConfig:c queue:queue handler:h];
        return (CGDisplayStreamRef)s;
    }
}

CGError CGDisplayStreamStart(CGDisplayStreamRef s)
{
    if (!is_stream(s))
        return kCGErrorIllegalArgument;
    if (DS(s)->started)
        return kCGErrorSuccess;
    if (![DS(s)->stream start:NULL])
        return kCGErrorFailure;
    DS(s)->started = YES;
    return kCGErrorSuccess;
}
CGError CGDisplayStreamStop(CGDisplayStreamRef s)
{
    if (!is_stream(s))
        return kCGErrorIllegalArgument;
    [DS(s)->stream stop];
    return kCGErrorSuccess;
}

const CGRect *CGDisplayStreamUpdateGetRects(CGDisplayStreamUpdateRef u, CGDisplayStreamUpdateRectType type, size_t *count)
{
    if (!is_update(u)) {
        if (count)
            *count = 0;
        return NULL;
    }
    /* every frame is drawn anew: all of it is refreshed and dirty, nothing moved */
    BOOL whole = type != kCGDisplayStreamUpdateMovedRects;
    if (count)
        *count = whole ? 1 : 0;
    return whole ? &UPD(u)->rect : NULL;
}
CGDisplayStreamUpdateRef CGDisplayStreamUpdateCreateMergedUpdate(CGDisplayStreamUpdateRef a, CGDisplayStreamUpdateRef b)
{
    if (!is_update(a) && !is_update(b))
        return NULL;
    FerryCGDisplayStreamUpdate *u = [[FerryCGDisplayStreamUpdate alloc] init];
    u->rect = is_update(a) && is_update(b) ? CGRectUnion(UPD(a)->rect, UPD(b)->rect) : UPD(is_update(a) ? a : b)->rect;
    u->dropCount = (is_update(a) ? UPD(a)->dropCount : 0) + (is_update(b) ? UPD(b)->dropCount : 0);
    return (CGDisplayStreamUpdateRef)u;
}
void CGDisplayStreamUpdateGetMovedRectsDelta(CGDisplayStreamUpdateRef u, CGFloat *dx, CGFloat *dy)
{
    if (dx)
        *dx = 0;
    if (dy)
        *dy = 0;
}
size_t CGDisplayStreamUpdateGetDropCount(CGDisplayStreamUpdateRef u) { return is_update(u) ? UPD(u)->dropCount : 0; }
