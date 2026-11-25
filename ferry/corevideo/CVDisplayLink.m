/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's display links and host time (freemac 1.235, Ferry 0.59.0),
 * written from Apple's public Core Video reference.
 *
 * A running display link has a thread of its own that calls its output
 * callback once each refresh of the display, at the refresh rate Ferry's
 * OpenGL paces swaps by (60 a second unless set otherwise), with the time
 * now and the time the next frame will be seen, both in host time, which
 * is mach_absolute_time's count: nanoseconds here. Every display is the
 * same display to it. CVDisplayLinkStop waits for a callback under way to
 * return, unless the callback itself stops the link. Built without ARC. */
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <time.h>
#include "../opengl/FerryGL.h"

uint64_t CVGetCurrentHostTime(void) { return mach_absolute_time(); }
double CVGetHostClockFrequency(void) { return 1e9; }
uint32_t CVGetHostClockMinimumTimeDelta(void) { return 1; }

@interface FerryCVDisplayLink : NSObject {
  @public
    pthread_mutex_t _lock;
    pthread_cond_t _changed;
    CGDirectDisplayID _display;
    CVDisplayLinkOutputCallback _callback;
    void *_context;
    id _handler; /* a copied block */
    BOOL _running, _threadAlive;
    pthread_t _thread;
    uint64_t _start;   /* host time of frame 0 */
    uint64_t _frame;   /* the frame the next callback is for */
    uint64_t _period;  /* nanoseconds a frame */
    double _measured;  /* the period seen, in host time */
    uint64_t _lastCall;
}
@end

static void *link_thread(void *arg);

@implementation FerryCVDisplayLink
- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_lock, NULL);
        pthread_cond_init(&_changed, NULL);
        double hz = FerryGLRefreshRate();
        _period = (uint64_t)(1e9 / (hz > 0 ? hz : 60) + 0.5);
        _display = 1;
    }
    return self;
}
- (void)dealloc
{
    CVDisplayLinkStop((CVDisplayLinkRef)self);
    [_handler release];
    pthread_cond_destroy(&_changed);
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}
@end

#define LINK(ref) ((FerryCVDisplayLink *)(ref))
static BOOL is_link(CVDisplayLinkRef l) { return l && [(id)l isKindOfClass:[FerryCVDisplayLink class]]; }

static void stamp(FerryCVDisplayLink *l, uint64_t host, int64_t frame, CVTimeStamp *t)
{
    memset(t, 0, sizeof *t);
    t->version = 0;
    t->videoTimeScale = 1000000000;
    t->videoTime = frame * (int64_t)l->_period;
    t->hostTime = host;
    t->rateScalar = l->_measured > 0 ? l->_measured / (double)l->_period : 1.0;
    t->videoRefreshPeriod = (int64_t)l->_period;
    t->flags = kCVTimeStampVideoHostTimeValid | kCVTimeStampVideoRefreshPeriodValid | kCVTimeStampRateScalarValid;
}

static void sleep_until(uint64_t when)
{
    for (;;) {
        uint64_t now = mach_absolute_time();
        if (now >= when)
            return;
        uint64_t left = when - now;
        struct timespec ts = {(time_t)(left / 1000000000u), (long)(left % 1000000000u)};
        nanosleep(&ts, NULL);
    }
}

static void *link_thread(void *arg)
{
    FerryCVDisplayLink *l = arg; /* retained by CVDisplayLinkStart for the thread */
    pthread_mutex_lock(&l->_lock);
    while (l->_running) {
        uint64_t due = l->_start + l->_frame * l->_period;
        pthread_mutex_unlock(&l->_lock);
        sleep_until(due);
        pthread_mutex_lock(&l->_lock);
        if (!l->_running)
            break;
        uint64_t now = mach_absolute_time();
        /* a late frame: skip the ones missed, as a display would */
        if (now > due + l->_period)
            l->_frame = (now - l->_start) / l->_period;
        if (l->_lastCall)
            l->_measured = l->_measured > 0 ? l->_measured * 0.9 + (double)(now - l->_lastCall) * 0.1
                                            : (double)(now - l->_lastCall);
        l->_lastCall = now;
        CVTimeStamp inNow, inOutput;
        stamp(l, l->_start + l->_frame * l->_period, (int64_t)l->_frame, &inNow);
        stamp(l, l->_start + (l->_frame + 1) * l->_period, (int64_t)l->_frame + 1, &inOutput);
        l->_frame++;
        CVDisplayLinkOutputCallback cb = l->_callback;
        void *ctx = l->_context;
        CVDisplayLinkOutputHandler handler = [[l->_handler retain] autorelease];
        pthread_mutex_unlock(&l->_lock);
        @autoreleasepool {
            CVOptionFlags out = 0;
            if (handler)
                handler((CVDisplayLinkRef)l, &inNow, &inOutput, 0, &out);
            else if (cb)
                cb((CVDisplayLinkRef)l, &inNow, &inOutput, 0, &out, ctx);
        }
        pthread_mutex_lock(&l->_lock);
    }
    l->_threadAlive = NO;
    pthread_cond_broadcast(&l->_changed);
    pthread_mutex_unlock(&l->_lock);
    [l release];
    return NULL;
}

CFTypeID CVDisplayLinkGetTypeID(void) { return (CFTypeID)[FerryCVDisplayLink class]; }

static CVReturn make(CGDirectDisplayID display, CVDisplayLinkRef *out)
{
    if (!out)
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = [[FerryCVDisplayLink alloc] init];
    if (display)
        l->_display = display;
    *out = (CVDisplayLinkRef)l;
    return kCVReturnSuccess;
}
CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *displays, CFIndex count, CVDisplayLinkRef *out)
{
    return make(displays && count > 0 ? displays[0] : 0, out);
}
CVReturn CVDisplayLinkCreateWithOpenGLDisplayMask(uint32_t mask, CVDisplayLinkRef *out) { return make(0, out); }
CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID display, CVDisplayLinkRef *out)
{
    return make(display, out);
}
CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *out) { return make(0, out); }

CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef link, CGDirectDisplayID display)
{
    if (!is_link(link))
        return kCVReturnInvalidArgument;
    pthread_mutex_lock(&LINK(link)->_lock);
    LINK(link)->_display = display ? display : 1;
    pthread_mutex_unlock(&LINK(link)->_lock);
    return kCVReturnSuccess;
}
CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef link, CGLContextObj ctx,
                                                           CGLPixelFormatObj pix)
{
    return is_link(link) && ctx ? kCVReturnSuccess : kCVReturnInvalidArgument;
}
CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef link)
{
    return is_link(link) ? LINK(link)->_display : 0;
}

CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef link, CVDisplayLinkOutputCallback callback, void *context)
{
    if (!is_link(link))
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = LINK(link);
    pthread_mutex_lock(&l->_lock);
    [l->_handler release];
    l->_handler = nil;
    l->_callback = callback;
    l->_context = context;
    pthread_mutex_unlock(&l->_lock);
    return kCVReturnSuccess;
}
CVReturn CVDisplayLinkSetOutputHandler(CVDisplayLinkRef link, CVDisplayLinkOutputHandler handler)
{
    if (!is_link(link))
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = LINK(link);
    id copy = [(id)handler copy];
    pthread_mutex_lock(&l->_lock);
    [l->_handler release];
    l->_handler = copy;
    l->_callback = NULL;
    pthread_mutex_unlock(&l->_lock);
    return kCVReturnSuccess;
}

CVReturn CVDisplayLinkStart(CVDisplayLinkRef link)
{
    if (!is_link(link))
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = LINK(link);
    pthread_mutex_lock(&l->_lock);
    if (!l->_callback && !l->_handler) {
        pthread_mutex_unlock(&l->_lock);
        return kCVReturnDisplayLinkCallbacksNotSet;
    }
    if (l->_running) {
        pthread_mutex_unlock(&l->_lock);
        return kCVReturnDisplayLinkAlreadyRunning;
    }
    /* a thread from a stop made by the callback may still be finishing */
    while (l->_threadAlive && !pthread_equal(l->_thread, pthread_self()))
        pthread_cond_wait(&l->_changed, &l->_lock);
    if (l->_threadAlive) { /* restarted from its own callback: the same thread goes on */
        l->_running = YES;
        pthread_mutex_unlock(&l->_lock);
        return kCVReturnSuccess;
    }
    double hz = FerryGLRefreshRate();
    l->_period = (uint64_t)(1e9 / (hz > 0 ? hz : 60) + 0.5);
    uint64_t now = mach_absolute_time();
    l->_start = now - now % l->_period; /* frames on a steady grid, as a display's are */
    l->_frame = (now - l->_start) / l->_period + 1;
    l->_lastCall = 0;
    l->_measured = 0;
    l->_running = YES;
    l->_threadAlive = YES;
    [l retain];
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    int e = pthread_create(&l->_thread, &attr, link_thread, l);
    pthread_attr_destroy(&attr);
    if (e) {
        l->_running = l->_threadAlive = NO;
        pthread_mutex_unlock(&l->_lock);
        [l release];
        return kCVReturnError;
    }
    pthread_mutex_unlock(&l->_lock);
    return kCVReturnSuccess;
}

CVReturn CVDisplayLinkStop(CVDisplayLinkRef link)
{
    if (!is_link(link))
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = LINK(link);
    pthread_mutex_lock(&l->_lock);
    l->_running = NO;
    if (l->_threadAlive && !pthread_equal(l->_thread, pthread_self()))
        while (l->_threadAlive)
            pthread_cond_wait(&l->_changed, &l->_lock);
    pthread_mutex_unlock(&l->_lock);
    return kCVReturnSuccess;
}

Boolean CVDisplayLinkIsRunning(CVDisplayLinkRef link)
{
    if (!is_link(link))
        return false;
    pthread_mutex_lock(&LINK(link)->_lock);
    Boolean r = LINK(link)->_running;
    pthread_mutex_unlock(&LINK(link)->_lock);
    return r;
}

CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef link)
{
    if (!is_link(link))
        return kCVIndefiniteTime;
    return (CVTime){(int64_t)LINK(link)->_period, 1000000000, 0};
}
CVTime CVDisplayLinkGetOutputVideoLatency(CVDisplayLinkRef link)
{
    return is_link(link) ? kCVZeroTime : kCVIndefiniteTime;
}
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef link)
{
    if (!is_link(link))
        return 0;
    pthread_mutex_lock(&LINK(link)->_lock);
    double m = LINK(link)->_running ? LINK(link)->_measured : 0;
    pthread_mutex_unlock(&LINK(link)->_lock);
    return m / 1e9;
}

CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef link, CVTimeStamp *out)
{
    if (!is_link(link) || !out)
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = LINK(link);
    pthread_mutex_lock(&l->_lock);
    if (!l->_running) {
        pthread_mutex_unlock(&l->_lock);
        return kCVReturnDisplayLinkNotRunning;
    }
    uint64_t now = mach_absolute_time();
    int64_t frame = (int64_t)((now - l->_start) / l->_period);
    uint64_t version = out->version;
    stamp(l, now, frame, out);
    out->videoTime = (int64_t)(now - l->_start);
    out->version = (uint32_t)version;
    pthread_mutex_unlock(&l->_lock);
    return kCVReturnSuccess;
}

/* Fills in out's flagged fields from whichever of in's are valid. */
CVReturn CVDisplayLinkTranslateTime(CVDisplayLinkRef link, const CVTimeStamp *in, CVTimeStamp *out)
{
    if (!is_link(link) || !in || !out)
        return kCVReturnInvalidArgument;
    FerryCVDisplayLink *l = LINK(link);
    pthread_mutex_lock(&l->_lock);
    if (!l->_running) {
        pthread_mutex_unlock(&l->_lock);
        return kCVReturnDisplayLinkNotRunning;
    }
    uint64_t host;
    if (in->flags & kCVTimeStampHostTimeValid)
        host = in->hostTime;
    else if ((in->flags & kCVTimeStampVideoTimeValid) && in->videoTimeScale > 0)
        host = l->_start + (uint64_t)((double)in->videoTime * 1e9 / in->videoTimeScale);
    else {
        pthread_mutex_unlock(&l->_lock);
        return kCVReturnInvalidArgument;
    }
    uint64_t want = out->flags;
    out->videoTimeScale = 1000000000;
    out->videoRefreshPeriod = (int64_t)l->_period;
    out->rateScalar = 1.0;
    if (want & kCVTimeStampHostTimeValid)
        out->hostTime = host;
    if (want & kCVTimeStampVideoTimeValid)
        out->videoTime = (int64_t)(host - l->_start);
    out->flags = want & (kCVTimeStampVideoHostTimeValid | kCVTimeStampVideoRefreshPeriodValid |
                         kCVTimeStampRateScalarValid);
    pthread_mutex_unlock(&l->_lock);
    return kCVReturnSuccess;
}

CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef link) { return link ? (CVDisplayLinkRef)[(id)link retain] : NULL; }
void CVDisplayLinkRelease(CVDisplayLinkRef link)
{
    if (link)
        [(id)link release];
}
