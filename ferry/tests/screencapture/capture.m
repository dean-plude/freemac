/* SPDX-License-Identifier: GPL-3.0-or-later
 * Screen capture (freemac 1.238, Ferry 0.62.0), as OBS Studio's
 * mac-capture plugin uses it, on an X display of the test's own (Xvfb,
 * 320x240, no window manager; capture_test.sh). The program shows a window
 * in four coloured quarters, at a known place; another copy of it ("other")
 * shows another app's window beside it. Then: ScreenCaptureKit's content,
 * first refused (the user is asked) and then allowed; a display stream in
 * 'BGRA', changed to 'l10r' at half size, then to the window alone; the
 * pointer drawn in or not; only one app's windows, or all but one app's;
 * the computer's sound while a tone plays (Core Audio's null device,
 * which hears what it plays); stopping; CGDisplayStream on a part of the
 * screen; the display's mode; the window list and its pictures; and a
 * single picture through SCScreenshotManager. Colours are read at known
 * places in the frames. */
#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreGraphics/CGDisplayStream.h>
#include <IOSurface/IOSurface.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdatomic.h>
#include <unistd.h>

/* ---- the windows -------------------------------------------------------------------------------- */

@interface Quarters : NSView
@end
@implementation Quarters
- (void)drawRect:(NSRect)r
{
    NSRect b = [self bounds];
    CGFloat w = b.size.width / 2, h = b.size.height / 2;
    [[NSColor redColor] set];
    NSRectFill(NSMakeRect(0, h, w, h));          /* top left */
    [[NSColor greenColor] set];
    NSRectFill(NSMakeRect(w, h, w, h));          /* top right */
    [[NSColor blueColor] set];
    NSRectFill(NSMakeRect(0, 0, w, h));          /* bottom left */
    [[NSColor yellowColor] set];
    NSRectFill(NSMakeRect(w, 0, w, h));          /* bottom right */
}
@end

@interface Fill : NSView
@end
@implementation Fill
- (void)drawRect:(NSRect)r
{
    [[NSColor cyanColor] set];
    NSRectFill([self bounds]);
}
@end

static void spin(double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                           inMode:NSDefaultRunLoopMode dequeue:YES];
        if (e)
            [NSApp sendEvent:e];
    }
}

static BOOL spin_until(BOOL (^done)(void), double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done()) {
        if ([until timeIntervalSinceNow] < 0)
            return NO;
        spin(0.02);
    }
    return YES;
}

static NSWindow *window(NSRect r, NSString *title, NSView *content)
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:r styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:YES];
    [w setReleasedWhenClosed:NO];
    [w setTitle:title];
    [content setFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
    [w setContentView:content];
    return w;
}

/* ---- colours ------------------------------------------------------------------------------------- */

static const char *colour(int r, int g, int b)
{
    static char other[64];
    int hi = 200, lo = 60;
    if (r > hi && g < lo && b < lo) return "red";
    if (r < lo && g > hi && b < lo) return "green";
    if (r < lo && g < lo && b > hi) return "blue";
    if (r > hi && g > hi && b < lo) return "yellow";
    if (r < lo && g > hi && b > hi) return "cyan";
    if (r < lo && g < lo && b < lo) return "black";
    snprintf(other, sizeof other, "(%d,%d,%d)", r, g, b);
    return other;
}

static const char *bgra_at(const uint8_t *base, size_t bpr, size_t x, size_t y)
{
    const uint8_t *p = base + y * bpr + x * 4;
    return colour(p[2], p[1], p[0]);
}

static const char *pixel_colour(CVPixelBufferRef pb, size_t x, size_t y)
{
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    const uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t bpr = CVPixelBufferGetBytesPerRow(pb);
    const char *c;
    if (CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_ARGB2101010LEPacked) {
        uint32_t v = *(const uint32_t *)(base + y * bpr + x * 4);
        c = colour((int)(((v >> 20) & 0x3ff) >> 2), (int)(((v >> 10) & 0x3ff) >> 2), (int)((v & 0x3ff) >> 2));
    } else
        c = bgra_at(base, bpr, x, y);
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    return c;
}

static const char *image_colour(CGImageRef image, size_t x, size_t y)
{
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    uint8_t *px = calloc(w * h, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cx = CGBitmapContextCreate(px, w, h, 8, w * 4, space,
                                            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextDrawImage(cx, CGRectMake(0, 0, w, h), image);
    const char *c = bgra_at(px, w * 4, x, y);
    CGContextRelease(cx);
    CGColorSpaceRelease(space);
    free(px);
    return c;
}

static NSString *rect_text(CGRect r)
{
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *four(OSType t)
{
    return [NSString stringWithFormat:@"%c%c%c%c", (char)(t >> 24), (char)(t >> 16), (char)(t >> 8), (char)t];
}

/* ---- a stream's output ---------------------------------------------------------------------------- */

@interface Output : NSObject <SCStreamOutput, SCStreamDelegate>
@property (atomic) int frames;
@property (atomic) int stopErrors;
@property (atomic) int audio;
@property (atomic) int heard;             /* buffers with what the test plays in them */
@property (atomic, copy) NSString *audioFormat;
@end
@implementation Output {
    CMSampleBufferRef _latest;
    NSLock *_lock;
}
- (instancetype)init
{
    if ((self = [super init]))
        _lock = [NSLock new];
    return self;
}
- (void)_heard:(CMSampleBufferRef)sample
{
    CMFormatDescriptionRef f = CMSampleBufferGetFormatDescription(sample);
    const AudioStreamBasicDescription *a = CMAudioFormatDescriptionGetStreamBasicDescription(f);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    if (!self.audioFormat && a)
        self.audioFormat = [NSString stringWithFormat:@"%s, %.0f Hz, %u channels, float %d, not interleaved %d, "
                                                      @"%ld frames, on the host clock %d",
                                                      [four(CMFormatDescriptionGetMediaType(f)) UTF8String],
                                                      a->mSampleRate, a->mChannelsPerFrame,
                                                      (a->mFormatFlags & kAudioFormatFlagIsFloat) != 0,
                                                      (a->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0,
                                                      (long)CMSampleBufferGetNumSamples(sample),
                                                      pts.timescale == 1000000000];
    struct {
        AudioBufferList list;
        AudioBuffer more[1];
    } l;
    CMBlockBufferRef kept = NULL;
    if (CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, NULL, &l.list, sizeof l, NULL, NULL, 0, &kept))
        return;
    if (l.list.mNumberBuffers == 2) {
        const float *left = l.list.mBuffers[0].mData, *right = l.list.mBuffers[1].mData;
        size_t mid = l.list.mBuffers[0].mDataByteSize / 8;
        if (fabsf(left[mid] - 0.5f) < 0.01f && fabsf(right[mid] + 0.25f) < 0.01f)
            self.heard++;
    }
    CFRelease(kept);
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type
{
    if (type != SCStreamOutputTypeScreen) {
        self.audio++;
        [self _heard:sample];
        return;
    }
    [_lock lock];
    CFRetain(sample);
    if (_latest)
        CFRelease(_latest);
    _latest = sample;
    [_lock unlock];
    self.frames++;
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error
{
    self.stopErrors++;
}
/* the latest frame, once `count` more have come */
- (CMSampleBufferRef)copyFrameAfter:(int)count
{
    int from = self.frames;
    if (!spin_until(^BOOL { return self.frames >= from + count; }, 10))
        return NULL;
    [_lock lock];
    CMSampleBufferRef s = _latest ? (CMSampleBufferRef)CFRetain(_latest) : NULL;
    [_lock unlock];
    return s;
}
@end

static void describe_sample(CMSampleBufferRef s, NSArray *places)
{
    CVPixelBufferRef pb = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(s);
    IOSurfaceRef surface = pb ? CVPixelBufferGetIOSurface(pb) : NULL;
    printf("  %zux%zu %s, on an IOSurface %d, valid %d ready %d samples %ld\n", CVPixelBufferGetWidth(pb),
           CVPixelBufferGetHeight(pb), [four(CVPixelBufferGetPixelFormatType(pb)) UTF8String], surface != NULL,
           CMSampleBufferIsValid(s), CMSampleBufferDataIsReady(s), (long)CMSampleBufferGetNumSamples(s));
    CMFormatDescriptionRef f = CMSampleBufferGetFormatDescription(s);
    CMVideoDimensions d = CMVideoFormatDescriptionGetDimensions(f);
    printf("  format: %s %s %dx%d, matches %d\n", [four(CMFormatDescriptionGetMediaType(f)) UTF8String],
           [four(CMFormatDescriptionGetMediaSubType(f)) UTF8String], d.width, d.height,
           CMVideoFormatDescriptionMatchesImageBuffer(f, pb));
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(s);
    CMTime now = CMClockGetTime(CMClockGetHostTimeClock());
    printf("  time: on the host clock %d, not after now %d\n", pts.timescale == 1000000000 && CMTIME_IS_VALID(pts),
           CMTimeCompare(pts, now) <= 0);
    CFArrayRef atts = CMSampleBufferGetSampleAttachmentsArray(s, false);
    NSDictionary *info = atts && CFArrayGetCount(atts) ? (__bridge NSDictionary *)CFArrayGetValueAtIndex(atts, 0) : nil;
    CGRect content = CGRectNull, screen = CGRectNull;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[SCStreamFrameInfoContentRect], &content);
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[SCStreamFrameInfoScreenRect], &screen);
    uint64_t shown = [info[SCStreamFrameInfoDisplayTime] unsignedLongLongValue];
    printf("  info: status %ld, content %s, scale factor %.1f, content scale %.2f, screen %s, shown before now %d\n",
           (long)[info[SCStreamFrameInfoStatus] integerValue], [rect_text(content) UTF8String],
           [info[SCStreamFrameInfoScaleFactor] doubleValue], [info[SCStreamFrameInfoContentScale] doubleValue],
           [rect_text(screen) UTF8String], shown > 0 && shown <= mach_absolute_time());
    for (NSArray *p in places)
        printf("  at %s: %s\n", [p[0] UTF8String],
               pixel_colour(pb, [p[1] unsignedIntegerValue], [p[2] unsignedIntegerValue]));
}

static int differing(CVPixelBufferRef a, CVPixelBufferRef b, CGRect r)
{
    CVPixelBufferLockBaseAddress(a, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(b, kCVPixelBufferLock_ReadOnly);
    const uint8_t *pa = CVPixelBufferGetBaseAddress(a), *pb = CVPixelBufferGetBaseAddress(b);
    size_t ra = CVPixelBufferGetBytesPerRow(a), rb = CVPixelBufferGetBytesPerRow(b);
    int n = 0;
    for (size_t y = (size_t)r.origin.y; y < (size_t)CGRectGetMaxY(r); y++)
        for (size_t x = (size_t)r.origin.x; x < (size_t)CGRectGetMaxX(r); x++)
            n += memcmp(pa + y * ra + x * 4, pb + y * rb + x * 4, 3) != 0;
    CVPixelBufferUnlockBaseAddress(a, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferUnlockBaseAddress(b, kCVPixelBufferLock_ReadOnly);
    return n;
}

/* ---- the content ------------------------------------------------------------------------------- */

static SCShareableContent *content(BOOL onScreenOnly, NSError **error)
{
    __block SCShareableContent *got = nil;
    __block NSError *why = nil;
    __block atomic_int done = 0;
    __block int onMain = -1;
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:onScreenOnly
                                                 completionHandler:^(SCShareableContent *c, NSError *e) {
                                                     got = c;
                                                     why = e;
                                                     onMain = [NSThread isMainThread];
                                                     atomic_store(&done, 1);
                                                 }];
    if (!spin_until(^BOOL { return atomic_load(&done); }, 10))
        printf("no answer\n");
    if (onMain == 1)
        printf("answered on the main thread\n");
    if (error)
        *error = why;
    return got;
}

static int other_main(void)
{
    [NSApplication sharedApplication];
    NSWindow *w = window(NSMakeRect(220, 20, 80, 60), @"Another app", [Fill new]);
    [w orderFront:nil];
    spin(0.5);
    printf("shown %d\n", (int)getpid());
    fflush(stdout);
    for (;;)
        spin(1);
}

static void wait_for(void (^start)(void (^)(NSError *)), const char *what)
{
    __block atomic_int done = 0;
    __block NSError *why = nil;
    start(^(NSError *e) {
        why = e;
        atomic_store(&done, 1);
    });
    if (!spin_until(^BOOL { return atomic_load(&done); }, 10))
        printf("%s: no answer\n", what);
    else if (why)
        printf("%s: error %ld\n", what, (long)why.code);
    else
        printf("%s: done\n", what);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "other"))
            return other_main();
        [NSApplication sharedApplication];
        NSWindow *mine = window(NSMakeRect(40, 60, 160, 120), @"Ferry capture test", [Quarters new]);
        [mine orderFront:nil];
        spin(0.8);
        pid_t other = (pid_t)atoi(getenv("FERRY_TEST_OTHER_PID") ?: "0");

        /* the content: refused until the user has said */
        NSError *error = nil;
        SCShareableContent *c = content(NO, &error);
        printf("before asking: content %d, error %s %ld\n", c != nil, [error.domain UTF8String], (long)error.code);
        BOOL allowed = spin_until(^BOOL { return CGPreflightScreenCaptureAccess(); }, 20);
        printf("after the user's answer: allowed %d\n", allowed);
        NSString *log = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"asker.log"]
                                                  encoding:NSUTF8StringEncoding error:NULL];
        printf("asked: %s", log ? [log UTF8String] : "never\n");

        c = content(YES, &error);
        printf("content: error %ld, %lu displays\n", (long)error.code, (unsigned long)[c.displays count]);
        SCDisplay *display = [c.displays firstObject];
        printf("  display %u: %ldx%ld at %s, the main display %d\n", display.displayID, (long)display.width,
               (long)display.height, [rect_text(display.frame) UTF8String], display.displayID == CGMainDisplayID());
        SCWindow *mineSC = nil, *otherSC = nil;
        for (SCWindow *w in c.windows) {
            if ([w.title isEqual:@"Ferry capture test"])
                mineSC = w;
            if ([w.title isEqual:@"Another app"])
                otherSC = w;
        }
        printf("  my window: id is its number %d, at %s, on screen %d, layer %ld, mine %d, app \"%s\" (%s)\n",
               mineSC.windowID == (CGWindowID)[mine windowNumber], [rect_text(mineSC.frame) UTF8String],
               mineSC.isOnScreen, (long)mineSC.windowLayer, mineSC.owningApplication.processID == getpid(),
               [mineSC.owningApplication.applicationName UTF8String],
               [mineSC.owningApplication.bundleIdentifier UTF8String]);
        printf("  the other app's window: listed %d, at %s, on screen %d, its pid %d, numbered as another app's %d\n",
               otherSC != nil, [rect_text(otherSC.frame) UTF8String], otherSC.isOnScreen,
               other && otherSC.owningApplication.processID == other, (otherSC.windowID & 0x40000000) != 0);
        int apps = 0;
        for (SCRunningApplication *a in c.applications)
            apps += a.processID == getpid() || a.processID == other;
        printf("  applications: both listed %d\n", apps == 2);

        /* a display stream, 'BGRA' */
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
        SCShareableContentInfo *fi = [SCShareableContent infoForFilter:filter];
        printf("display filter: style %ld, scale %.1f, rect %s\n", (long)fi.style, fi.pointPixelScale,
               [rect_text(fi.contentRect) UTF8String]);
        SCStreamConfiguration *config = [SCStreamConfiguration new];
        config.width = 320;
        config.height = 240;
        config.minimumFrameInterval = CMTimeMake(1, 30);
        config.showsCursor = NO;
        config.queueDepth = 4;
        Output *out = [Output new];
        SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:out];
        dispatch_queue_t q = dispatch_queue_create("capture test", DISPATCH_QUEUE_SERIAL);
        printf("outputs added: screen %d, audio %d\n",
               [stream addStreamOutput:out type:SCStreamOutputTypeScreen sampleHandlerQueue:q error:NULL],
               [stream addStreamOutput:out type:SCStreamOutputTypeAudio sampleHandlerQueue:q error:NULL]);
        printf("synchronised with the host clock %d\n", stream.synchronizationClock == CMClockGetHostTimeClock());
        wait_for(^(void (^h)(NSError *)) { [stream startCaptureWithCompletionHandler:h]; }, "started");
        wait_for(^(void (^h)(NSError *)) { [stream startCaptureWithCompletionHandler:h]; }, "started again");
        CMSampleBufferRef s = [out copyFrameAfter:4];
        printf("the screen, 'BGRA':\n");
        if (s) {
            describe_sample(s, @[
                @[ @"the top left", @10, @10 ], @[ @"my window's top left quarter", @80, @90 ],
                @[ @"its top right", @160, @90 ], @[ @"its bottom left", @80, @150 ],
                @[ @"its bottom right", @160, @150 ], @[ @"the other app's window", @260, @190 ]
            ]);
            CFRelease(s);
        }

        /* the pointer, at the middle of the screen */
        s = [out copyFrameAfter:2];
        config.showsCursor = YES;
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "pointer shown");
        spin(0.3);
        CMSampleBufferRef withCursor = [out copyFrameAfter:3];
        if (s && withCursor)
            printf("the pointer drawn in: %d\n",
                   differing((CVPixelBufferRef)CMSampleBufferGetImageBuffer(s),
                             (CVPixelBufferRef)CMSampleBufferGetImageBuffer(withCursor), CGRectMake(140, 100, 40, 40)) > 0);
        if (s)
            CFRelease(s);
        if (withCursor)
            CFRelease(withCursor);

        /* 'l10r' at half size */
        config.showsCursor = NO;
        config.width = 160;
        config.height = 120;
        config.pixelFormat = kCVPixelFormatType_ARGB2101010LEPacked;
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "configured");
        spin(0.3);
        s = [out copyFrameAfter:3];
        printf("the screen, 'l10r' at half size:\n");
        if (s) {
            describe_sample(s, @[ @[ @"my window's top left quarter", @40, @45 ], @[ @"its bottom right", @80, @75 ] ]);
            CFRelease(s);
        }

        /* the window alone */
        config.pixelFormat = kCVPixelFormatType_32BGRA;
        SCContentFilter *alone = [[SCContentFilter alloc] initWithDesktopIndependentWindow:mineSC];
        fi = [SCShareableContent infoForFilter:alone];
        printf("window filter: style %ld, scale %.1f, rect %s\n", (long)fi.style, fi.pointPixelScale,
               [rect_text(fi.contentRect) UTF8String]);
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "configured");
        wait_for(^(void (^h)(NSError *)) { [stream updateContentFilter:alone completionHandler:h]; }, "filtered");
        spin(0.3);
        s = [out copyFrameAfter:3];
        printf("the window alone:\n");
        if (s) {
            describe_sample(s, @[ @[ @"the top left of its content", @40, @(CGRectGetHeight(mineSC.frame) - 90) ],
                                  @[ @"its bottom right", @120, @(CGRectGetHeight(mineSC.frame) - 30) ] ]);
            CFRelease(s);
        }

        /* only the other app's windows on the display */
        SCRunningApplication *otherApp = otherSC.owningApplication;
        SCContentFilter *apps_only = [[SCContentFilter alloc] initWithDisplay:display
                                                         includingApplications:otherApp ? @[ otherApp ] : @[]
                                                              exceptingWindows:@[]];
        config.width = 320;
        config.height = 240;
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "configured");
        wait_for(^(void (^h)(NSError *)) { [stream updateContentFilter:apps_only completionHandler:h]; }, "filtered");
        spin(0.7);
        s = [out copyFrameAfter:3];
        printf("only the other app (style %ld):\n", (long)apps_only.style);
        if (s) {
            CVPixelBufferRef pb = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(s);
            printf("  at my window: %s\n  at the other app's: %s\n", pixel_colour(pb, 80, 90), pixel_colour(pb, 260, 190));
            CFRelease(s);
        }
        SCContentFilter *hide_me = [[SCContentFilter alloc] initWithDisplay:display
                                                       excludingApplications:@[ mineSC.owningApplication ]
                                                            exceptingWindows:@[]];
        wait_for(^(void (^h)(NSError *)) { [stream updateContentFilter:hide_me completionHandler:h]; }, "filtered");
        spin(0.7);
        s = [out copyFrameAfter:3];
        printf("all but my app:\n");
        if (s) {
            CVPixelBufferRef pb = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(s);
            printf("  at my window: %s\n  at the other app's: %s\n", pixel_colour(pb, 80, 90), pixel_colour(pb, 260, 190));
            CFRelease(s);
        }

        /* the computer's sound (the null device's, which hears what it plays), while a tone plays */
        printf("audio before asking for it: %d\n", out.audio);
        config.capturesAudio = YES;
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "audio asked for");
        AudioStreamBasicDescription tone = {48000, kAudioFormatLinearPCM,
                                            kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
        AudioQueueRef player = NULL;
        AudioQueueNewOutputWithDispatchQueue(&player, &tone, 0, q, ^(AudioQueueRef aq, AudioQueueBufferRef b) {
            AudioQueueEnqueueBuffer(aq, b, 0, NULL);
        });
        for (int i = 0; i < 3; i++) {
            AudioQueueBufferRef b = NULL;
            AudioQueueAllocateBuffer(player, 4096 * 8, &b);
            float *f = b->mAudioData;
            for (int k = 0; k < 4096; k++)
                f[2 * k] = 0.5f, f[2 * k + 1] = -0.25f;
            b->mAudioDataByteSize = 4096 * 8;
            AudioQueueEnqueueBuffer(player, b, 0, NULL);
        }
        AudioQueueStart(player, NULL);
        BOOL heard = spin_until(^BOOL { return out.heard > 2; }, 10);
        AudioQueueStop(player, true);
        AudioQueueDispose(player, true);
        printf("audio: came %d, heard what was played %d\n  %s\n", out.audio > 0, heard,
               [out.audioFormat ?: @"no format" UTF8String]);

        wait_for(^(void (^h)(NSError *)) { [stream stopCaptureWithCompletionHandler:h]; }, "stopped");
        int frames = out.frames, sounds = out.audio;
        spin(0.3);
        printf("after stopping: frames came %d, audio came %d, the delegate told of errors %d\n",
               out.frames != frames, out.audio != sounds, out.stopErrors);
        wait_for(^(void (^h)(NSError *)) { [stream stopCaptureWithCompletionHandler:h]; }, "stopped again");

        /* a single picture */
        __block CGImageRef shot = NULL;
        __block atomic_int shotDone = 0;
        SCStreamConfiguration *small = [SCStreamConfiguration new];
        small.width = 160;
        small.height = 120;
        small.showsCursor = NO;
        [SCScreenshotManager captureImageWithFilter:filter configuration:small
                                  completionHandler:^(CGImageRef image, NSError *e) {
                                      if (image)
                                          shot = CGImageRetain(image);
                                      atomic_store(&shotDone, 1);
                                  }];
        spin_until(^BOOL { return atomic_load(&shotDone); }, 10);
        printf("a picture: %zux%zu, at my window %s\n", shot ? CGImageGetWidth(shot) : 0,
               shot ? CGImageGetHeight(shot) : 0, shot ? image_colour(shot, 40, 45) : "-");
        if (shot)
            CGImageRelease(shot);

        /* a display stream of part of the screen */
        __block atomic_int complete = 0, stopped = 0;
        __block IOSurfaceRef firstSurface = NULL;
        __block size_t rects = 0;
        __block CGRect rect0 = CGRectNull;
        CFDictionaryRef part = CGRectCreateDictionaryRepresentation(CGRectMake(40, 60, 160, 120));
        NSDictionary *props = @{(__bridge id)kCGDisplayStreamSourceRect : (__bridge id)part,
                                (__bridge id)kCGDisplayStreamShowCursor : @NO,
                                (__bridge id)kCGDisplayStreamMinimumFrameTime : @(1.0 / 30)};
        CFRelease(part);
        CGDisplayStreamRef ds = CGDisplayStreamCreateWithDispatchQueue(
            CGMainDisplayID(), 160, 120, 'BGRA', (__bridge CFDictionaryRef)props, q,
            ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
                if (status == kCGDisplayStreamFrameStatusFrameComplete && surface &&
                    atomic_fetch_add(&complete, 1) == 2) {
                    CFRetain(surface);
                    IOSurfaceIncrementUseCount(surface);
                    firstSurface = surface;
                    const CGRect *r = CGDisplayStreamUpdateGetRects(update, kCGDisplayStreamUpdateDirtyRects, &rects);
                    if (r && rects)
                        rect0 = r[0];
                } else if (status == kCGDisplayStreamFrameStatusStopped)
                    atomic_store(&stopped, 1);
            });
        printf("a display stream: made %d, started %d\n", ds != NULL, ds && CGDisplayStreamStart(ds) == kCGErrorSuccess);
        spin_until(^BOOL { return firstSurface != NULL; }, 10);
        if (firstSurface) {
            IOSurfaceLock(firstSurface, kIOSurfaceLockReadOnly, NULL);
            const uint8_t *base = IOSurfaceGetBaseAddress(firstSurface);
            size_t bpr = IOSurfaceGetBytesPerRow(firstSurface);
            printf("  a frame: %zux%zu, %zu rect %s, top left %s, bottom right %s\n", IOSurfaceGetWidth(firstSurface),
                   IOSurfaceGetHeight(firstSurface), rects, [rect_text(rect0) UTF8String], bgra_at(base, bpr, 40, 30),
                   bgra_at(base, bpr, 120, 90));
            IOSurfaceUnlock(firstSurface, kIOSurfaceLockReadOnly, NULL);
            IOSurfaceDecrementUseCount(firstSurface);
            CFRelease(firstSurface);
        }
        if (ds) {
            CGDisplayStreamStop(ds);
            printf("  stopped: told %d\n", spin_until(^BOOL { return atomic_load(&stopped); }, 10));
            CFRelease(ds);
        }

        /* the display's mode */
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(CGMainDisplayID());
        printf("display mode: %zux%zu, %zux%zu pixels, usable %d; display %zux%zu\n", CGDisplayModeGetWidth(mode),
               CGDisplayModeGetHeight(mode), CGDisplayModeGetPixelWidth(mode), CGDisplayModeGetPixelHeight(mode),
               CGDisplayModeIsUsableForDesktopGUI(mode), CGDisplayPixelsWide(CGMainDisplayID()),
               CGDisplayPixelsHigh(CGMainDisplayID()));
        CGDisplayModeRelease(mode);

        /* the window list */
        NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
        NSDictionary *mineInfo = nil, *otherInfo = nil;
        for (NSDictionary *d in list) {
            if ([d[(id)kCGWindowName] isEqual:@"Ferry capture test"])
                mineInfo = d;
            if ([d[(id)kCGWindowName] isEqual:@"Another app"])
                otherInfo = d;
        }
        CGRect b = CGRectNull;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)mineInfo[(id)kCGWindowBounds], &b);
        printf("the window list: mine numbered %d, its pid %d, layer %ld, on screen %d, at %s\n",
               [mineInfo[(id)kCGWindowNumber] integerValue] == [mine windowNumber],
               [mineInfo[(id)kCGWindowOwnerPID] intValue] == getpid(), (long)[mineInfo[(id)kCGWindowLayer] integerValue],
               [mineInfo[(id)kCGWindowIsOnscreen] boolValue], [rect_text(b) UTF8String]);
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)otherInfo[(id)kCGWindowBounds], &b);
        printf("  the other app's: listed %d, its pid %d, at %s, the same number as ScreenCaptureKit's %d\n",
               otherInfo != nil, other && [otherInfo[(id)kCGWindowOwnerPID] intValue] == other,
               [rect_text(b) UTF8String], [otherInfo[(id)kCGWindowNumber] unsignedIntValue] == otherSC.windowID);
        CGImageRef screen = CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly, kCGNullWindowID,
                                                    kCGWindowImageDefault);
        printf("  the screen's picture: %zux%zu, at my window %s, at the other's %s\n",
               screen ? CGImageGetWidth(screen) : 0, screen ? CGImageGetHeight(screen) : 0,
               screen ? image_colour(screen, 80, 90) : "-", screen ? image_colour(screen, 260, 190) : "-");
        CGImageRelease(screen);
        CGImageRef theirs = otherInfo ? CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                                                                 [otherInfo[(id)kCGWindowNumber] unsignedIntValue],
                                                                 kCGWindowImageBoundsIgnoreFraming)
                                      : NULL;
        printf("  the other app's picture: %zux%zu, %s\n", theirs ? CGImageGetWidth(theirs) : 0,
               theirs ? CGImageGetHeight(theirs) : 0,
               theirs ? image_colour(theirs, CGImageGetWidth(theirs) / 2, CGImageGetHeight(theirs) - 10) : "-");
        if (theirs)
            CGImageRelease(theirs);
        [mine close];
    }
    return 0;
}
