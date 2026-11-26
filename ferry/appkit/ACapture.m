/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Ferry's screen capture (freemac 1.238, Ferry 0.62.0): the user's say,
 * the choice of back end, the displays and windows with the app's own
 * matched to its NSWindows, and the streams that ScreenCaptureKit and
 * CGDisplayStream are made of. See ACapture.h. */
#import "AInternal.h"
#import "ACapture.h"
#include <IOSurface/IOSurface.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const CGWindowID other_bit = 0x40000000;    /* as CGServices.m numbers other apps' windows */

void ACaptureSayOnce(const char *what)
{
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static NSMutableSet *said;
    pthread_mutex_lock(&lock);
    if (!said)
        said = [[NSMutableSet alloc] init];
    NSString *s = @(what);
    BOOL again = [said containsObject:s];
    [said addObject:s];
    pthread_mutex_unlock(&lock);
    if (again)
        return;
    fflush(stdout);
    fprintf(stderr, "AppKit (Ferry): %s\n", what);
}

NSError *ACaptureError(NSInteger code, NSString *description)
{
    return [NSError errorWithDomain:@"com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                               code:code
                           userInfo:description ? @{NSLocalizedDescriptionKey : description} : nil];
}

/* ---- the user's say --------------------------------------------------------------------------- */

static NSString *app_key(void)
{
    NSBundle *b = [NSBundle mainBundle];
    NSString *identifier = [b bundleIdentifier];
    if ([identifier length])
        return identifier;
    NSString *exe = [b executablePath] ?: [[[NSProcessInfo processInfo] arguments] firstObject];
    return [exe length] ? [exe stringByStandardizingPath] : [[NSProcessInfo processInfo] processName];
}

NSString *ACaptureAppKey(void) { return app_key(); }

static NSString *app_name(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *k in @[ @"CFBundleDisplayName", @"CFBundleName" ])
        if ([info[k] isKindOfClass:[NSString class]] && [info[k] length])
            return info[k];
    return [[NSProcessInfo processInfo] processName];
}

static NSString *grants_path(void)
{
    const char *config = getenv("XDG_CONFIG_HOME");
    NSString *base = config && *config ? @(config) : [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    return [base stringByAppendingPathComponent:@"freemac/screen-recording.json"];
}

int ACaptureStoredAnswer(void)
{
    @autoreleasepool {
        NSData *d = [NSData dataWithContentsOfFile:grants_path()];
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        id apps = [j isKindOfClass:[NSDictionary class]] ? j[@"apps"] : nil;
        id entry = [apps isKindOfClass:[NSDictionary class]] ? apps[app_key()] : nil;
        id allowed = [entry isKindOfClass:[NSDictionary class]] ? entry[@"allowed"] : nil;
        if (![allowed isKindOfClass:[NSNumber class]])
            return -1;
        return [allowed boolValue] ? 1 : 0;
    }
}

BOOL ACaptureAllowed(void) { return ACaptureStoredAnswer() == 1; }

void ACaptureAsk(void)
{
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static BOOL asked;
    pthread_mutex_lock(&lock);
    BOOL again = asked;
    asked = YES;
    pthread_mutex_unlock(&lock);
    if (again || ACaptureStoredAnswer() >= 0)
        return;
    @autoreleasepool {
        const char *forced = getenv("FERRY_ACCESS_ASKER");
        const char *wl = getenv("WAYLAND_DISPLAY"), *xd = getenv("DISPLAY");
        if (!(forced && *forced) && !(wl && *wl) && !(xd && *xd))
            return;    /* no display to ask on */
        char *found = forced && *forced ? NULL : g_find_program_in_path("freemac-allow-control");
        NSString *asker = forced && *forced ? @(forced) : found ? @(found) : nil;
        if (found)
            g_free(found);
        if (!asker) {
            fflush(stdout);
            fprintf(stderr, "AppKit (Ferry): can't ask whether %s may record the screen "
                            "(freemac-allow-control isn't installed)\n", [app_name() UTF8String]);
            return;
        }
        char *argv[] = {(char *)[asker fileSystemRepresentation], "--kind", "screen-recording", "--app-id",
                        (char *)[app_key() UTF8String], "--name", (char *)[app_name() UTF8String], NULL};
        GError *error = NULL;
        g_spawn_async(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL, NULL, NULL, NULL, &error);
        if (error)
            g_error_free(error);
    }
}

bool CGPreflightScreenCaptureAccess(void) { return ACaptureAllowed(); }
bool CGRequestScreenCaptureAccess(void)
{
    int answer = ACaptureStoredAnswer();
    if (answer < 0)
        ACaptureAsk();
    return answer == 1;
}

/* ---- the back end ------------------------------------------------------------------------------- */

static const ACaptureBackend *backend(void)
{
    static const ACaptureBackend *chosen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *forced = getenv("FERRY_CAPTURE");
        const char *wl = getenv("WAYLAND_DISPLAY"), *xd = getenv("DISPLAY");
        if (forced && !strcmp(forced, "x11"))
            chosen = &ACaptureX11Backend;
        else if (forced && !strcmp(forced, "portal"))
            chosen = &ACapturePortalBackend;
        else if (forced && !strcmp(forced, "none"))
            chosen = NULL;
        else if (wl && *wl && (ACapturePortalReachable() || !(xd && *xd)))
            chosen = &ACapturePortalBackend;    /* a portal that doesn't answer says why */
        else if (xd && *xd)
            chosen = &ACaptureX11Backend;       /* X11, or Xwayland where the portal doesn't answer */
    });
    return chosen;
}

BOOL ACaptureAvailable(void)
{
    const ACaptureBackend *b = backend();
    if (!b) {
        ACaptureSayOnce("there's no display to record (no DISPLAY or WAYLAND_DISPLAY, or FERRY_CAPTURE=none)");
        return NO;
    }
    return b->available();
}
const char *ACaptureBackendName(void) { return backend() ? backend()->name : "none"; }

/* ---- displays and windows ------------------------------------------------------------------------ */

@implementation ACaptureDisplay
@end
@implementation ACaptureWindow
- (void)dealloc
{
    [title release];
    [owner release];
    [bundleID release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<window %u %@ (%@, %d) %@>", number, title, owner, (int)pid,
                                      NSStringFromRect(NSRectFromCGRect(frame))];
}
@end

NSArray *ACaptureDisplays(void) { return ACaptureAvailable() ? backend()->displays() : @[]; }

ACaptureDisplay *ACaptureDisplayNumbered(CGDirectDisplayID number)
{
    for (ACaptureDisplay *d in ACaptureDisplays())
        if (d->number == number)
            return d;
    return nil;
}

/* The app's own windows as last seen on the main thread: {number, title, level}. */
static pthread_mutex_t own_lock = PTHREAD_MUTEX_INITIALIZER;
static NSArray *own_snapshot;
static BOOL own_refresh_pending;

static void snapshot_own_windows(void)
{
    NSMutableArray *list = [NSMutableArray array];
    for (NSWindow *w in AAllWindows())
        if ([w windowNumber] > 0)
            [list addObject:@{@"number" : @([w windowNumber]), @"title" : [w title] ?: @"", @"level" : @([w level])}];
    pthread_mutex_lock(&own_lock);
    [own_snapshot release];
    own_snapshot = [list copy];
    own_refresh_pending = NO;
    pthread_mutex_unlock(&own_lock);
}

static NSArray *own_windows(void)
{
    if ([NSThread isMainThread])
        snapshot_own_windows();
    pthread_mutex_lock(&own_lock);
    NSArray *s = [[own_snapshot retain] autorelease];
    BOOL refresh = !own_refresh_pending && ![NSThread isMainThread];
    if (refresh)
        own_refresh_pending = YES;
    pthread_mutex_unlock(&own_lock);
    if (refresh)
        dispatch_async(dispatch_get_main_queue(), ^{
            snapshot_own_windows();
        });
    return s ?: @[];
}

void ACaptureNoteOwnWindows(void)
{
    if ([NSThread isMainThread])
        snapshot_own_windows();
}

NSArray *ACaptureWindows(void)
{
    if (!ACaptureAvailable())
        return @[];
    NSArray *all = backend()->windows();
    NSArray *own = own_windows();
    NSMutableSet *matched = [NSMutableSet set];
    pid_t me = getpid();
    NSString *myName = nil, *myKey = nil;
    NSMutableArray *out = [NSMutableArray array];
    for (ACaptureWindow *w in all) {
        if (w->pid == me) {
            NSDictionary *mine = nil;
            for (NSDictionary *o in own)
                if (!mine && ![matched containsObject:o[@"number"]] && [o[@"title"] isEqual:w->title])
                    mine = o;
            if (!mine)
                continue;   /* a surface of the app's that isn't one of its windows */
            [matched addObject:mine[@"number"]];
            if (!myName) {
                myName = app_name();
                myKey = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
            }
            w->number = (CGWindowID)[mine[@"number"] unsignedIntValue];
            w->own = YES;
            w->layer = [mine[@"level"] integerValue];
            [w->owner release];
            w->owner = [myName copy];
            [w->bundleID release];
            w->bundleID = [myKey copy];
        } else {
            w->number = other_bit | (CGWindowID)(w->handle & 0x3fffffff);
        }
        [out addObject:w];
    }
    return out;
}

ACaptureWindow *ACaptureWindowNumbered(CGWindowID number)
{
    for (ACaptureWindow *w in ACaptureWindows())
        if (w->number == number)
            return w;
    return nil;
}

/* ---- pictures --------------------------------------------------------------------------------------- */

static CGImageRef image_from(const ACaptureImage *im, CGRect part)
{
    size_t w = (size_t)part.size.width, h = (size_t)part.size.height;
    if (!w || !h)
        return NULL;
    size_t rowBytes = w * 4;
    uint8_t *data = malloc(rowBytes * h);
    for (size_t y = 0; y < h; y++) {
        const uint32_t *from = (const uint32_t *)(im->data + ((size_t)part.origin.y + y) * im->bytesPerRow) +
                               (size_t)part.origin.x;
        uint32_t *to = (uint32_t *)(data + y * rowBytes);
        for (size_t i = 0; i < w; i++)
            to[i] = from[i] | 0xff000000u;
    }
    CFDataRef bytes = CFDataCreate(NULL, data, (CFIndex)(rowBytes * h));
    free(data);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(w, h, 8, 32, rowBytes, space,
                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, provider, NULL,
                                     false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    CFRelease(bytes);
    return image;
}

/* a grabber for a stream's source, or for a single picture */
static void *open_for(ACaptureSourceKind kind, CGDirectDisplayID display, uint64_t window, BOOL cursor, BOOL once)
{
    const ACaptureBackend *b = backend();
    if (!b->openTarget)
        return b->open();
    ACaptureTarget t = {kind, display, window, cursor, once};
    return b->openTarget(&t);
}

CGImageRef ACaptureCreateScreenImage(CGRect points)
{
    if (!ACaptureAvailable())
        return NULL;
    ACaptureDisplay *main = [ACaptureDisplays() firstObject];
    if (!main)
        return NULL;
    CGFloat s = main->scale;
    CGRect px = CGRectIsNull(points) || CGRectIsInfinite(points)
                    ? main->pixelFrame
                    : CGRectIntegral(CGRectMake(points.origin.x * s, points.origin.y * s, points.size.width * s,
                                                points.size.height * s));
    px = CGRectIntersection(px, main->pixelFrame);
    if (CGRectIsEmpty(px))
        return NULL;
    void *g = open_for(ACaptureSourceDisplay, main->number, 0, NO, YES);
    if (!g)
        return NULL;
    ACaptureImage im;
    CGImageRef image = NULL;
    if (backend()->grabScreen(g, px, &im))
        image = image_from(&im, CGRectMake(0, 0, im.width, im.height));
    backend()->close(g);
    return image;
}

CGImageRef ACaptureCreateWindowImage(CGWindowID number)
{
    ACaptureWindow *w = ACaptureWindowNumbered(number);
    if (!w)
        return NULL;
    void *g = open_for(ACaptureSourceWindow, 0, w->handle, NO, YES);
    if (!g)
        return NULL;
    ACaptureImage im;
    CGImageRef image = NULL;
    if (backend()->grabWindow(g, w->handle, &im, NULL))
        image = image_from(&im, CGRectMake(0, 0, im.width, im.height));
    backend()->close(g);
    return image;
}

/* ---- streams: their settings ------------------------------------------------------------------------- */

@implementation ACaptureConfig
- (instancetype)init
{
    if ((self = [super init])) {
        display = 1;
        sourceRect = CGRectNull;
        destinationRect = CGRectNull;
        width = 1920;
        height = 1080;
        pixelFormat = kCVPixelFormatType_32BGRA;
        queueDepth = 3;
        preservesAspectRatio = YES;
        background = 0xff000000u;
    }
    return self;
}
- (void)dealloc
{
    [windows release];
    [pids release];
    [exceptions release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    ACaptureConfig *c = [[ACaptureConfig alloc] init];
    c->kind = kind;
    c->display = display;
    c->window = window;
    c->windows = [windows copy];
    c->pids = [pids copy];
    c->exceptions = [exceptions copy];
    c->excluding = excluding;
    c->sourceRect = sourceRect;
    c->destinationRect = destinationRect;
    c->width = width;
    c->height = height;
    c->pixelFormat = pixelFormat;
    c->queueDepth = queueDepth;
    c->showsCursor = showsCursor;
    c->scalesToFit = scalesToFit;
    c->preservesAspectRatio = preservesAspectRatio;
    c->windowAtTopLeft = windowAtTopLeft;
    c->minimumInterval = minimumInterval;
    c->background = background;
    c->ycbcr601 = ycbcr601;
    return c;
}
@end

/* ---- streams: drawing a frame ------------------------------------------------------------------------- */

/* the pointer over the grabbed pixels, which start at (ox, oy) in the back end's pixels */
static void draw_cursor(ACaptureImage *im, const ACaptureCursor *c, long ox, long oy)
{
    for (size_t cy = 0; cy < c->height; cy++) {
        long y = c->y + (long)cy - oy;
        if (y < 0 || y >= (long)im->height)
            continue;
        uint32_t *row = (uint32_t *)(im->data + (size_t)y * im->bytesPerRow);
        for (size_t cx = 0; cx < c->width; cx++) {
            long xx = c->x + (long)cx - ox;
            if (xx < 0 || xx >= (long)im->width)
                continue;
            uint32_t s = c->argb[cy * c->width + cx], a = s >> 24;
            if (!a)
                continue;
            uint32_t d = row[xx], keep = d & 0xff000000u, inv = 255 - a;
            uint32_t r = ((s >> 16) & 0xff) + (((d >> 16) & 0xff) * inv + 127) / 255;
            uint32_t g = ((s >> 8) & 0xff) + (((d >> 8) & 0xff) * inv + 127) / 255;
            uint32_t b = (s & 0xff) + ((d & 0xff) * inv + 127) / 255;
            row[xx] = keep | (MIN(r, 255u) << 16) | (MIN(g, 255u) << 8) | MIN(b, 255u);
        }
    }
}

static CGRect fit(CGSize source, CGRect into, BOOL keepAspect, BOOL centred)
{
    if (!keepAspect || source.width <= 0 || source.height <= 0)
        return into;
    CGFloat s = MIN(into.size.width / source.width, into.size.height / source.height);
    CGFloat w = floor(source.width * s + 0.5), h = floor(source.height * s + 0.5);
    if (!centred)
        return CGRectMake(into.origin.x, into.origin.y, w, h);
    return CGRectMake(into.origin.x + floor((into.size.width - w) / 2), into.origin.y + floor((into.size.height - h) / 2),
                      w, h);
}

static inline uint32_t premultiplied(uint32_t argb)
{
    uint32_t a = argb >> 24;
    if (a == 255)
        return argb;
    uint32_t r = ((argb >> 16) & 0xff) * a / 255, g = ((argb >> 8) & 0xff) * a / 255, b = (argb & 0xff) * a / 255;
    return (a << 24) | (r << 16) | (g << 8) | b;
}

/* BGRA (0xAARRGGBB in memory order B, G, R, A) into the pixel buffer's format */
static void store(CVPixelBufferRef pb, const uint32_t *argb, size_t w, size_t h, BOOL bt601)
{
    OSType f = CVPixelBufferGetPixelFormatType(pb);
    CVPixelBufferLockBaseAddress(pb, 0);
    if (f == kCVPixelFormatType_32BGRA) {
        uint8_t *base = CVPixelBufferGetBaseAddress(pb);
        size_t rb = CVPixelBufferGetBytesPerRow(pb);
        for (size_t y = 0; y < h; y++)
            memcpy(base + y * rb, argb + y * w, w * 4);
    } else if (f == kCVPixelFormatType_ARGB2101010LEPacked) {
        uint8_t *base = CVPixelBufferGetBaseAddress(pb);
        size_t rb = CVPixelBufferGetBytesPerRow(pb);
        for (size_t y = 0; y < h; y++) {
            uint32_t *to = (uint32_t *)(base + y * rb);
            const uint32_t *from = argb + y * w;
            for (size_t i = 0; i < w; i++) {
                uint32_t p = from[i], a = p >> 24, r = (p >> 16) & 0xff, g = (p >> 8) & 0xff, b = p & 0xff;
                to[i] = ((a >> 6) << 30) | (((r << 2) | (r >> 6)) << 20) | (((g << 2) | (g >> 6)) << 10) |
                        ((b << 2) | (b >> 6));
            }
        }
    } else {
        BOOL full = f == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        double kr = bt601 ? 0.299 : 0.2126, kb = bt601 ? 0.114 : 0.0722, kg = 1 - kr - kb;
        double ys = full ? 255 : 219, yo = full ? 0 : 16, cs = full ? 255 : 224;
        uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *cp = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        size_t yrb = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), crb = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
        for (size_t y = 0; y < h; y++)
            for (size_t i = 0; i < w; i++) {
                uint32_t p = argb[y * w + i];
                double r = ((p >> 16) & 0xff) / 255.0, g = ((p >> 8) & 0xff) / 255.0, b = (p & 0xff) / 255.0;
                yp[y * yrb + i] = (uint8_t)lround(yo + ys * (kr * r + kg * g + kb * b));
            }
        for (size_t y = 0; y < (h + 1) / 2; y++)
            for (size_t i = 0; i < (w + 1) / 2; i++) {
                double r = 0, g = 0, b = 0;
                int n = 0;
                for (size_t dy = 0; dy < 2; dy++)
                    for (size_t dx = 0; dx < 2; dx++) {
                        size_t sy = 2 * y + dy, sx = 2 * i + dx;
                        if (sy >= h || sx >= w)
                            continue;
                        uint32_t p = argb[sy * w + sx];
                        r += ((p >> 16) & 0xff) / 255.0, g += ((p >> 8) & 0xff) / 255.0, b += (p & 0xff) / 255.0;
                        n++;
                    }
                r /= n, g /= n, b /= n;
                double yy = kr * r + kg * g + kb * b;
                double cb = (b - yy) / (2 * (1 - kb)), cr = (r - yy) / (2 * (1 - kr));
                long u = lround(128 + cs * cb), v = lround(128 + cs * cr);
                cp[y * crb + 2 * i] = (uint8_t)MAX(0, MIN(255, u));
                cp[y * crb + 2 * i + 1] = (uint8_t)MAX(0, MIN(255, v));
            }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
}

/* ---- streams ---------------------------------------------------------------------------------------- */

@implementation ACaptureStream {
    ACaptureConfig *_config;
    dispatch_queue_t _queue, _captureQueue;
    dispatch_source_t _timer;
    ACaptureFrameHandler _handler;
    void *_grabber;
    NSMutableArray *_ring;
    size_t _ringWidth, _ringHeight;
    OSType _ringFormat;
    uint32_t *_scratch;
    size_t _scratchSize;
    size_t _dropped;
    BOOL _running, _stopped;
    uint64_t _handle;           /* the window's, for ACaptureSourceWindow */
    NSArray *_maskRects;        /* NSValues of pixel rects, for ACaptureSourceWindows */
    uint64_t _maskRead;
    uint64_t _interval;
}

- (instancetype)initWithConfig:(ACaptureConfig *)config queue:(dispatch_queue_t)queue
                       handler:(ACaptureFrameHandler)handler
{
    if ((self = [super init])) {
        _config = [config copy];
        if (queue) {
            dispatch_retain(queue);
            _queue = queue;
        } else
            _queue = dispatch_queue_create("Ferry screen capture output", DISPATCH_QUEUE_SERIAL);
        _captureQueue = dispatch_queue_create("Ferry screen capture", DISPATCH_QUEUE_SERIAL);
        _handler = [handler copy];
        _ring = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    if (_timer) {
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);
    }
    if (_grabber)
        backend()->close(_grabber);
    [_config release];
    dispatch_release(_queue);
    dispatch_release(_captureQueue);
    [_handler release];
    [_ring release];
    [_maskRects release];
    free(_scratch);
    [super dealloc];
}

- (BOOL)isRunning { return _running; }

/* called on the capture queue: what the configuration's source needs before frames */
- (BOOL)_prepare:(ACaptureConfig *)c error:(NSError **)error
{
    if (c->kind == ACaptureSourceWindow) {
        ACaptureWindow *w = ACaptureWindowNumbered(c->window);
        if (!w) {
            if (error)
                *error = ACaptureError(-3815, @"The window to record isn't there.");
            return NO;
        }
        _handle = w->handle;
    } else if (!ACaptureDisplayNumbered(c->display)) {
        if (error)
            *error = ACaptureError(-3815, @"The display to record isn't there.");
        return NO;
    }
    [_maskRects release];
    _maskRects = nil;
    _maskRead = 0;
    uint64_t want = c->minimumInterval ? c->minimumInterval : 1000000000ull / 60;
    if (want != _interval && _timer) {
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)want), want, want / 10);
    }
    _interval = want;
    return YES;
}

- (BOOL)start:(NSError **)error
{
    if (_running || _stopped) {
        if (error)
            *error = ACaptureError(-3807, @"The stream has already started.");
        return NO;
    }
    if (!ACaptureAvailable()) {
        if (error)
            *error = ACaptureError(-3802, @"There's no display this computer can record.");
        return NO;
    }
    __block BOOL ok = NO;
    __block NSError *why = nil;
    dispatch_sync(_captureQueue, ^{
        ok = [self _prepare:_config error:&why];
        [why retain];
        if (ok)
            _grabber = open_for(_config->kind, _config->display, _handle, _config->showsCursor, NO);
        if (ok && !_grabber) {
            ok = NO;
            why = [ACaptureError(-3802, @"The display server can't be read.") retain];
        }
    });
    if (!ok) {
        if (error)
            *error = [why autorelease];
        else
            [why release];
        return NO;
    }
    _running = YES;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _captureQueue);
    __block ACaptureStream *me = self;    /* not retained: stop and dealloc cancel the timer */
    dispatch_source_set_event_handler(_timer, ^{
        [me _tick];
    });
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), _interval, _interval / 10);
    [self retain];                        /* held while it runs */
    dispatch_resume(_timer);
    return YES;
}

- (void)stop { [self stopWithError:nil]; }

- (void)stopWithError:(NSError *)error
{
    if (!_running)
        return;
    _running = NO;
    _stopped = YES;
    dispatch_source_cancel(_timer);
    [error retain];
    dispatch_async(_captureQueue, ^{
        if (_grabber) {
            backend()->close(_grabber);
            _grabber = NULL;
        }
        dispatch_async(_queue, ^{
            ACaptureFrame f;
            memset(&f, 0, sizeof f);
            f.stopped = YES;
            f.error = error;
            f.displayTime = mach_absolute_time();
            _handler(&f);
            [error release];
            [self release];
        });
    });
}

- (void)setConfig:(ACaptureConfig *)config
{
    ACaptureConfig *c = [config copy];
    dispatch_async(_captureQueue, ^{
        NSError *why = nil;
        if (![self _prepare:c error:&why]) {
            [c release];
            return;
        }
        [_config release];
        _config = c;
    });
}

/* a free buffer of the ring: nobody holds it, its surface or its use count */
- (CVPixelBufferRef)_freeBuffer:(ACaptureConfig *)c
{
    if (_ringWidth != c->width || _ringHeight != c->height || _ringFormat != c->pixelFormat) {
        [_ring removeAllObjects];
        _ringWidth = c->width;
        _ringHeight = c->height;
        _ringFormat = c->pixelFormat;
    }
    for (id b in _ring) {
        IOSurfaceRef s = CVPixelBufferGetIOSurface((CVPixelBufferRef)b);
        if ([b retainCount] == 1 && (!s || (!IOSurfaceIsInUse(s) && [(id)s retainCount] <= 1)))
            return (CVPixelBufferRef)b;
    }
    NSInteger depth = c->queueDepth > 0 ? MIN(c->queueDepth, 16) : 3;
    if ((NSInteger)[_ring count] >= depth)
        return NULL;
    CVPixelBufferRef b = NULL;
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    if (CVPixelBufferCreate(NULL, c->width, c->height, c->pixelFormat, (CFDictionaryRef)attrs, &b) != kCVReturnSuccess)
        return NULL;
    BOOL yuv = c->pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
               c->pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    if (yuv)
        CVBufferSetAttachment(b, kCVImageBufferYCbCrMatrixKey,
                              c->ycbcr601 ? kCVImageBufferYCbCrMatrix_ITU_R_601_4 : kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                              kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(b, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
                          kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(b, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2,
                          kCVAttachmentMode_ShouldPropagate);
    [_ring addObject:(id)b];
    CVPixelBufferRelease(b);
    return b;
}

/* For ACaptureSourceWindows, the shown windows' rects, back to front, each
 * as {rect, whether it shows}; read twice a second. */
- (NSArray *)_mask:(ACaptureConfig *)c
{
    uint64_t now = mach_absolute_time();
    if (_maskRects && now - _maskRead < 500000000ull)
        return _maskRects;
    NSMutableArray *rects = [NSMutableArray array];
    NSSet *numbers = [NSSet setWithArray:c->windows ?: @[]], *pids = [NSSet setWithArray:c->pids ?: @[]],
          *exceptions = [NSSet setWithArray:c->exceptions ?: @[]];
    for (ACaptureWindow *w in [ACaptureWindows() reverseObjectEnumerator]) {
        if (!w->onscreen)
            continue;
        BOOL picked = ([numbers containsObject:@(w->number)] || [pids containsObject:@(w->pid)]) &&
                      ![exceptions containsObject:@(w->number)];
        [rects addObject:@[ [NSValue valueWithRect:NSRectFromCGRect(w->pixelFrame)], @(picked != c->excluding) ]];
    }
    [_maskRects release];
    _maskRects = [rects copy];
    _maskRead = now;
    return _maskRects;
}

- (void)_tick
{
    if (!_running || !_grabber)
        return;
    @autoreleasepool {
        ACaptureConfig *c = [[_config retain] autorelease];
        const ACaptureBackend *be = backend();
        NSError *failed = be->failure ? be->failure(_grabber) : nil;
        if (failed) {
            /* the portal's user said no, or its session ended */
            [self stopWithError:failed];
            return;
        }
        ACaptureImage im;
        CGRect origin = CGRectZero;     /* where the grabbed pixels are, in the back end's pixels */
        CGFloat scale = 1;
        BOOL masked = NO;
        uint64_t when = mach_absolute_time();
        if (c->kind == ACaptureSourceWindow) {
            if (!be->grabWindow(_grabber, _handle, &im, &origin)) {
                /* gone, or not shown: an own window may have been made again */
                ACaptureWindow *w = ACaptureWindowNumbered(c->window);
                if (!w || w->handle == _handle || !be->grabWindow(_grabber, w->handle, &im, &origin))
                    return;
                _handle = w->handle;
            }
            ACaptureDisplay *d = [ACaptureDisplays() firstObject];
            scale = d ? d->scale : 1;
        } else {
            ACaptureDisplay *d = ACaptureDisplayNumbered(c->display);
            if (!d)
                return;
            scale = d->scale;
            CGRect px = d->pixelFrame;
            if (!CGRectIsNull(c->sourceRect))
                px = CGRectIntersection(px, CGRectIntegral(CGRectMake(d->pixelFrame.origin.x + c->sourceRect.origin.x * scale,
                                                                      d->pixelFrame.origin.y + c->sourceRect.origin.y * scale,
                                                                      c->sourceRect.size.width * scale,
                                                                      c->sourceRect.size.height * scale)));
            if (CGRectIsEmpty(px) || !be->grabScreen(_grabber, px, &im))
                return;
            origin = px;
            if (c->kind == ACaptureSourceWindows) {
                /* only the shown windows show (the topmost window at a pixel
                 * decides; the desktop shows when excluding): the alpha
                 * byte says which pixels */
                NSArray *rects = [self _mask:c];
                uint32_t base = c->excluding ? 0xff000000u : 0;
                for (size_t y = 0; y < im.height; y++) {
                    uint32_t *row = (uint32_t *)(im.data + y * im.bytesPerRow);
                    for (size_t i = 0; i < im.width; i++)
                        row[i] = (row[i] & 0x00ffffffu) | base;
                }
                for (NSArray *m in rects) {
                    CGRect r = CGRectIntersection(NSRectToCGRect([m[0] rectValue]), origin);
                    if (CGRectIsEmpty(r))
                        continue;
                    uint32_t a = [m[1] boolValue] ? 0xff000000u : 0;
                    for (size_t y = (size_t)(r.origin.y - origin.origin.y); y < (size_t)(CGRectGetMaxY(r) - origin.origin.y); y++) {
                        uint32_t *row = (uint32_t *)(im.data + y * im.bytesPerRow);
                        for (size_t i = (size_t)(r.origin.x - origin.origin.x); i < (size_t)(CGRectGetMaxX(r) - origin.origin.x); i++)
                            row[i] = (row[i] & 0x00ffffffu) | a;
                    }
                }
                masked = YES;
            }
        }
        if (!im.width || !im.height)
            return;
        if (c->showsCursor) {
            ACaptureCursor cur;
            if (be->cursor(_grabber, &cur))
                draw_cursor(&im, &cur, (long)origin.origin.x, (long)origin.origin.y);
        }

        size_t W = c->width, H = c->height;
        if (!W || !H)
            return;
        CGSize src = CGSizeMake(im.width, im.height);
        CGRect out = CGRectMake(0, 0, W, H), dst;
        if (!CGRectIsNull(c->destinationRect))
            dst = fit(src, CGRectIntersection(c->destinationRect, out), c->preservesAspectRatio, YES);
        else if (c->kind == ACaptureSourceWindow && c->windowAtTopLeft) {
            if (!c->scalesToFit && src.width <= W && src.height <= H)
                dst = CGRectMake(0, 0, src.width, src.height);
            else
                dst = fit(src, out, c->preservesAspectRatio, NO);
        } else
            dst = fit(src, out, c->preservesAspectRatio, YES);
        dst = CGRectIntersection(CGRectIntegral(dst), out);
        if (CGRectIsEmpty(dst))
            return;

        CVPixelBufferRef pb = [self _freeBuffer:c];
        if (!pb) {
            _dropped++;
            return;
        }
        if (_scratchSize < W * H) {
            free(_scratch);
            _scratch = malloc(W * H * sizeof *_scratch);
            _scratchSize = W * H;
        }
        uint32_t bg = premultiplied(c->background);
        size_t dx = (size_t)dst.origin.x, dy = (size_t)dst.origin.y, dw = (size_t)dst.size.width,
               dh = (size_t)dst.size.height;
        for (size_t y = 0; y < H; y++) {
            uint32_t *row = _scratch + y * W;
            if (y < dy || y >= dy + dh) {
                for (size_t i = 0; i < W; i++)
                    row[i] = bg;
                continue;
            }
            const uint32_t *from = (const uint32_t *)(im.data + ((y - dy) * im.height / dh) * im.bytesPerRow);
            for (size_t i = 0; i < W; i++) {
                if (i < dx || i >= dx + dw) {
                    row[i] = bg;
                    continue;
                }
                uint32_t p = from[(i - dx) * im.width / dw];
                row[i] = masked && !(p >> 24) ? bg : (p | 0xff000000u);
            }
        }
        store(pb, _scratch, W, H, c->ycbcr601);

        ACaptureFrame f;
        memset(&f, 0, sizeof f);
        f.frame = pb;
        f.displayTime = when;
        f.contentRect = dst;
        f.contentScale = MIN(dst.size.width / src.width, dst.size.height / src.height);
        f.scaleFactor = scale;
        f.dropped = _dropped;
        _dropped = 0;
        CVPixelBufferRetain(pb);
        [self retain];
        dispatch_async(_queue, ^{
            if (_running)
                _handler(&f);
            CVPixelBufferRelease(f.frame);
            [self release];
        });
    }
}
@end

/* ---- the screens' pixels (OBS's display capture converts with these) ---------------------------------- */

@implementation NSScreen (FerryBacking)
- (NSRect)convertRectToBacking:(NSRect)r
{
    CGFloat s = [self backingScaleFactor];
    return NSMakeRect(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s);
}
- (NSRect)convertRectFromBacking:(NSRect)r
{
    CGFloat s = [self backingScaleFactor];
    return s > 0 ? NSMakeRect(r.origin.x / s, r.origin.y / s, r.size.width / s, r.size.height / s) : r;
}
@end
