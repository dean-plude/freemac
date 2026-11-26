/* SPDX-License-Identifier: GPL-3.0-or-later
 * Screen capture on Wayland (freemac 1.240, Ferry 0.64.0), through the
 * ScreenCast portal and PipeWire, with no X display (portal_test.sh): a
 * fake portal on a private session bus, a private PipeWire daemon, a
 * stand-in for Wayfire's IPC with one display (eDP-1, 320x200 points) and
 * one other app's window, and two producers in the compositor's place:
 * the display at 640x400 in BGRx (red, green, blue and yellow quarters,
 * with the pointer as metadata, a white square at 100,60), and the window
 * at 200x100 in RGBx, cyan. Then: the content, its display taking its
 * scale from the first frame; a display stream with the pointer left out
 * and drawn in; the window alone through its own screen cast; the restore
 * token handed back the next time; the user saying no in the portal's
 * dialog; and a picture of the screen. Colours are read at known places. */
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdatomic.h>
#include <unistd.h>

static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
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

static const char *colour(int r, int g, int b)
{
    static char other[64];
    int hi = 200, lo = 60;
    if (r > hi && g > hi && b > hi) return "white";
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
    const char *c = bgra_at(CVPixelBufferGetBaseAddress(pb), CVPixelBufferGetBytesPerRow(pb), x, y);
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

/* the portal's calls since the last look; a session's Close comes from the thread that ends it,
 * at no set place among the next session's calls, so those are only counted */
static NSArray *portal_lines(void)
{
    NSString *path = [@(getenv("FERRY_TEST_PORTAL_LOG") ?: "") stringByStandardizingPath];
    NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    NSArray *lines = [log componentsSeparatedByString:@"\n"];
    return [lines count] ? [lines subarrayWithRange:NSMakeRange(0, [lines count] - 1)] : @[];
}

static void portal_log(void)
{
    static NSUInteger seen;
    NSArray *lines = portal_lines();
    for (NSUInteger i = seen; i < [lines count]; i++)
        if (![lines[i] isEqual:@"Session.Close"])
            printf("  portal: %s\n", [lines[i] UTF8String]);
    seen = [lines count];
}

static int portal_count(NSString *call)
{
    int n = 0;
    for (NSString *l in portal_lines())
        n += [l isEqual:call];
    return n;
}

/* ---- a stream's output ---------------------------------------------------------------------------- */

@interface Output : NSObject <SCStreamOutput, SCStreamDelegate>
@property (atomic) int frames;
@property (atomic) int stopped;
@property (atomic) long stopCode;
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
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type
{
    if (type != SCStreamOutputTypeScreen)
        return;
    CFArrayRef atts = CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSDictionary *info = atts && CFArrayGetCount(atts) ? (__bridge NSDictionary *)CFArrayGetValueAtIndex(atts, 0) : nil;
    if ([info[SCStreamFrameInfoStatus] integerValue] != SCFrameStatusComplete)
        return;
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
    self.stopCode = error.code;
    self.stopped++;
}
- (CMSampleBufferRef)copyFrameAfter:(int)count
{
    int from = self.frames;
    if (!spin_until(^BOOL { return self.frames >= from + count; }, 20))
        return NULL;
    [_lock lock];
    CMSampleBufferRef s = _latest ? (CMSampleBufferRef)CFRetain(_latest) : NULL;
    [_lock unlock];
    return s;
}
@end

static void describe(CMSampleBufferRef s, NSArray *places)
{
    CVPixelBufferRef pb = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(s);
    printf("  %zux%zu, on an IOSurface %d\n", CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb),
           CVPixelBufferGetIOSurface(pb) != NULL);
    for (NSArray *p in places)
        printf("  at %s: %s\n", [p[0] UTF8String],
               pixel_colour(pb, [p[1] unsignedIntegerValue], [p[2] unsignedIntegerValue]));
}

static SCShareableContent *content(NSError **error)
{
    __block SCShareableContent *got = nil;
    __block NSError *why = nil;
    __block atomic_int done = 0;
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES
                                                 completionHandler:^(SCShareableContent *c, NSError *e) {
                                                     got = c;
                                                     why = e;
                                                     atomic_store(&done, 1);
                                                 }];
    if (!spin_until(^BOOL { return atomic_load(&done); }, 10))
        printf("no answer\n");
    if (error)
        *error = why;
    return got;
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

static SCStream *stream_of(SCContentFilter *filter, SCStreamConfiguration *config, Output *out)
{
    SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:out];
    [stream addStreamOutput:out type:SCStreamOutputTypeScreen
         sampleHandlerQueue:dispatch_queue_create("portal test", DISPATCH_QUEUE_SERIAL) error:NULL];
    return stream;
}

/* without PipeWire: nothing to record, said once */
static int missing_main(void)
{
    NSError *error = nil;
    SCShareableContent *c = content(&error);
    printf("without PipeWire: content %d, %lu displays, error %ld\n", c != nil, (unsigned long)[c.displays count],
           (long)error.code);
    return 0;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "missing"))
            return missing_main();

        NSError *error = nil;
        SCShareableContent *c = content(&error);
        printf("before asking: content %d, error %ld\n", c != nil, (long)error.code);
        BOOL allowed = spin_until(^BOOL { return CGPreflightScreenCaptureAccess(); }, 20);
        printf("after the user's answer: allowed %d\n", allowed);

        c = content(&error);
        SCDisplay *display = [c.displays firstObject];
        printf("content: error %ld, %lu displays\n", (long)error.code, (unsigned long)[c.displays count]);
        printf("  display %u: %ldx%ld at %s, the main display %d\n", display.displayID, (long)display.width,
               (long)display.height, [rect_text(display.frame) UTF8String], display.displayID == CGMainDisplayID());
        SCWindow *cyan = nil;
        for (SCWindow *w in c.windows)
            if ([w.title isEqual:@"Cyan"])
                cyan = w;
        printf("  the other app's window: listed %d, at %s, on screen %d, app \"%s\" (%s) pid %d, "
               "numbered as another app's %d\n",
               cyan != nil, [rect_text(cyan.frame) UTF8String], cyan.isOnScreen,
               [cyan.owningApplication.applicationName UTF8String], [cyan.owningApplication.bundleIdentifier UTF8String],
               cyan.owningApplication.processID, (cyan.windowID & 0x40000000) != 0);
        NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
        NSDictionary *listed = nil;
        for (NSDictionary *d in list)
            if ([d[(id)kCGWindowName] isEqual:@"Cyan"])
                listed = d;
        printf("  the window list: the other app's window listed %d, the same number as ScreenCaptureKit's %d\n",
               listed != nil, [listed[(id)kCGWindowNumber] unsignedIntValue] == cyan.windowID);
        portal_log();

        /* the display: the portal's dialog as the stream starts, the user picks */
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
        SCStreamConfiguration *config = [SCStreamConfiguration new];
        config.width = 320;
        config.height = 200;
        config.minimumFrameInterval = CMTimeMake(1, 30);
        config.showsCursor = NO;
        Output *out = [Output new];
        SCStream *stream = stream_of(filter, config, out);
        wait_for(^(void (^h)(NSError *)) { [stream startCaptureWithCompletionHandler:h]; }, "display stream started");
        CMSampleBufferRef s = [out copyFrameAfter:4];
        printf("the display, the pointer left out:\n");
        if (s) {
            describe(s, @[
                @[ @"the top left quarter", @80, @50 ], @[ @"the top right", @240, @50 ],
                @[ @"the bottom left", @80, @150 ], @[ @"the bottom right", @240, @150 ],
                @[ @"the pointer's place", @53, @33 ]
            ]);
            CFRelease(s);
        }
        portal_log();
        c = content(&error);
        display = [c.displays firstObject];
        printf("  the display now: %ldx%ld at %s\n", (long)display.width, (long)display.height,
               [rect_text(display.frame) UTF8String]);
        SCContentFilter *now = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
        printf("  a filter of it: scale %.1f, rect %s\n", now.pointPixelScale, [rect_text(now.contentRect) UTF8String]);

        config.showsCursor = YES;
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "pointer shown");
        spin(0.3);
        s = [out copyFrameAfter:3];
        printf("the display, the pointer drawn in:\n");
        if (s) {
            describe(s, @[ @[ @"the pointer's place", @53, @33 ], @[ @"beside it", @70, @33 ] ]);
            CFRelease(s);
        }

        /* the other app's window, through a screen cast of its own */
        config.showsCursor = NO;
        config.width = 200;
        config.height = 100;
        SCContentFilter *alone = [[SCContentFilter alloc] initWithDesktopIndependentWindow:cyan];
        wait_for(^(void (^h)(NSError *)) { [stream updateConfiguration:config completionHandler:h]; }, "configured");
        wait_for(^(void (^h)(NSError *)) { [stream updateContentFilter:alone completionHandler:h]; }, "filtered");
        spin(0.5);
        s = [out copyFrameAfter:4];
        printf("the window alone:\n");
        if (s) {
            describe(s, @[ @[ @"its middle", @100, @50 ], @[ @"near its corner", @5, @5 ] ]);
            CFRelease(s);
        }
        wait_for(^(void (^h)(NSError *)) { [stream stopCaptureWithCompletionHandler:h]; }, "stopped");
        spin_until(^BOOL { return out.stopped > 0; }, 5);
        printf("  the delegate told of an error %d\n", out.stopCode != 0);
        spin(0.5);
        portal_log();

        /* the display again: the restore token comes back, the dialog isn't needed */
        config.width = 320;
        config.height = 200;
        Output *again = [Output new];
        SCStream *second = stream_of(filter, config, again);
        wait_for(^(void (^h)(NSError *)) { [second startCaptureWithCompletionHandler:h]; }, "the display again");
        s = [again copyFrameAfter:2];
        printf("  a frame came %d, at the bottom right %s\n", s != NULL,
               s ? pixel_colour((CVPixelBufferRef)CMSampleBufferGetImageBuffer(s), 240, 150) : "-");
        if (s)
            CFRelease(s);
        wait_for(^(void (^h)(NSError *)) { [second stopCaptureWithCompletionHandler:h]; }, "stopped");
        spin(0.5);
        portal_log();

        /* the user says no in the dialog */
        Output *refused = [Output new];
        SCStream *third = stream_of(alone, config, refused);
        wait_for(^(void (^h)(NSError *)) { [third startCaptureWithCompletionHandler:h]; }, "the window, refused");
        spin_until(^BOOL { return refused.stopped > 0; }, 10);
        printf("  stopped %d, with error %ld, frames %d\n", refused.stopped, refused.stopCode, refused.frames);
        spin(0.5);
        portal_log();

        /* a picture of the screen */
        CGImageRef screen = CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly, kCGNullWindowID,
                                                    kCGWindowImageDefault);
        printf("the screen's picture: %zux%zu, top left %s, bottom right %s\n", screen ? CGImageGetWidth(screen) : 0,
               screen ? CGImageGetHeight(screen) : 0, screen ? image_colour(screen, 100, 60) : "-",
               screen ? image_colour(screen, 500, 300) : "-");
        if (screen)
            CGImageRelease(screen);
        portal_log();
        BOOL closed = spin_until(^BOOL { return portal_count(@"Session.Close") == portal_count(@"CreateSession"); }, 10);
        printf("sessions: %d, every one closed %d\n", portal_count(@"CreateSession"), closed);
    }
    return 0;
}
