/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 *
 * ScreenCaptureKit (freemac 1.238, Ferry 0.62.0): the shareable content,
 * content filters, stream configurations, streams and single pictures,
 * over AppKit's capture core (appkit/ACapture.h), which asks the user, lists
 * the displays and windows and grabs their pixels. Written for freemac from
 * Apple's public ScreenCaptureKit reference.
 *
 * A filter becomes the core's source: a desktop-independent window its
 * one window, a display with no windows left out the whole display, and a
 * display with windows or apps included or left out the display with only
 * the picked windows showing (or all but them). Each frame comes as a
 * CMSampleBuffer stamped with the host clock, its image buffer the core's
 * IOSurface-backed pixel buffer, and goes to every screen output on its
 * queue.
 *
 * The audio is what the computer plays: with capturesAudio, a thread
 * records the default output's monitor through Ferry's Core Audio
 * (coreaudio/: the sound server's monitor source, or the null device's
 * loopback) and hands the audio outputs non-interleaved 32-bit float
 * samples in 1024-frame sample buffers on the host clock. The app's own
 * sound can't be left out of a monitor, so excludesCurrentProcessAudio
 * has no effect, and the microphone output gets nothing.
 */
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import "../appkit/ACapture.h"
#import "../coreaudio/CAInternal.h"
#include <stdatomic.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <unistd.h>

NSString *const SCStreamErrorDomain = @"com.apple.ScreenCaptureKit.SCStreamErrorDomain";

SCStreamFrameInfo const SCStreamFrameInfoStatus = @"SCStreamFrameInfoStatus";
SCStreamFrameInfo const SCStreamFrameInfoDisplayTime = @"SCStreamFrameInfoDisplayTime";
SCStreamFrameInfo const SCStreamFrameInfoScaleFactor = @"SCStreamFrameInfoScaleFactor";
SCStreamFrameInfo const SCStreamFrameInfoContentScale = @"SCStreamFrameInfoContentScale";
SCStreamFrameInfo const SCStreamFrameInfoContentRect = @"SCStreamFrameInfoContentRect";
SCStreamFrameInfo const SCStreamFrameInfoDirtyRects = @"SCStreamFrameInfoDirtyRects";
SCStreamFrameInfo const SCStreamFrameInfoScreenRect = @"SCStreamFrameInfoScreenRect";
SCStreamFrameInfo const SCStreamFrameInfoBoundingRect = @"SCStreamFrameInfoBoundingRect";
SCStreamFrameInfo const SCStreamFrameInfoPresenterOverlayContentRect = @"SCStreamFrameInfoPresenterOverlayContentRect";

static dispatch_queue_t answer_queue(void) { return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0); }

static NSString *own_name(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *k in @[ @"CFBundleDisplayName", @"CFBundleName" ])
        if ([info[k] isKindOfClass:[NSString class]] && [info[k] length])
            return info[k];
    return [[NSProcessInfo processInfo] processName];
}

static CGFloat main_scale(void)
{
    ACaptureDisplay *d = [ACaptureDisplays() firstObject];
    return d ? d->scale : 1;
}

/* ---- the content ------------------------------------------------------------------------------- */

@implementation SCRunningApplication {
  @public
    NSString *_bundleIdentifier, *_applicationName;
    pid_t _processID;
}
- (NSString *)bundleIdentifier { return _bundleIdentifier ?: @""; }
- (NSString *)applicationName { return _applicationName ?: @""; }
- (pid_t)processID { return _processID; }
- (void)dealloc
{
    [_bundleIdentifier release];
    [_applicationName release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<SCRunningApplication %d %@ (%@)>", (int)_processID, _applicationName,
                                      _bundleIdentifier];
}
@end

@implementation SCWindow {
  @public
    CGWindowID _windowID;
    CGRect _frame;
    NSString *_title;
    NSInteger _layer;
    SCRunningApplication *_app;
    BOOL _onScreen, _active;
}
- (CGWindowID)windowID { return _windowID; }
- (CGRect)frame { return _frame; }
- (NSString *)title { return _title; }
- (NSInteger)windowLayer { return _layer; }
- (SCRunningApplication *)owningApplication { return _app; }
- (BOOL)isOnScreen { return _onScreen; }
- (BOOL)isActive { return _active; }
- (void)dealloc
{
    [_title release];
    [_app release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<SCWindow %u \"%@\" of %@ %@%@>", _windowID, _title, _app.applicationName,
                                      NSStringFromRect(NSRectFromCGRect(_frame)), _onScreen ? @"" : @" hidden"];
}
@end

@implementation SCDisplay {
  @public
    CGDirectDisplayID _displayID;
    CGRect _frame;
    CGFloat _scale;
}
- (CGDirectDisplayID)displayID { return _displayID; }
- (NSInteger)width { return (NSInteger)lround(_frame.size.width); }
- (NSInteger)height { return (NSInteger)lround(_frame.size.height); }
- (CGRect)frame { return _frame; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<SCDisplay %u %@>", _displayID, NSStringFromRect(NSRectFromCGRect(_frame))];
}
@end

@implementation SCShareableContentInfo {
  @public
    SCShareableContentStyle _style;
    float _scale;
    CGRect _rect;
}
- (SCShareableContentStyle)style { return _style; }
- (float)pointPixelScale { return _scale; }
- (CGRect)contentRect { return _rect; }
@end

typedef enum { ListAll, ListOnScreen, ListBelow, ListAbove } ListMode;

@implementation SCShareableContent {
    NSArray *_windows, *_displays, *_applications;
}
- (NSArray *)windows { return _windows; }
- (NSArray *)displays { return _displays; }
- (NSArray *)applications { return _applications; }
- (void)dealloc
{
    [_windows release];
    [_displays release];
    [_applications release];
    [super dealloc];
}

+ (SCShareableContent *)_listExcludingDesktop:(BOOL)excludeDesktop mode:(ListMode)mode
                                     relative:(CGWindowID)relative ownOnly:(BOOL)ownOnly
{
    NSMutableArray *displays = [NSMutableArray array], *windows = [NSMutableArray array],
                   *apps = [NSMutableArray array];
    for (ACaptureDisplay *d in ACaptureDisplays()) {
        SCDisplay *s = [[[SCDisplay alloc] init] autorelease];
        s->_displayID = d->number;
        s->_frame = d->frame;
        s->_scale = d->scale;
        [displays addObject:s];
    }
    NSMutableDictionary *byPid = [NSMutableDictionary dictionary];
    pid_t me = getpid();
    SCRunningApplication *(^app)(pid_t, NSString *, NSString *) = ^SCRunningApplication *(pid_t pid, NSString *name,
                                                                                          NSString *bundleID) {
        SCRunningApplication *a = byPid[@(pid)];
        if (!a) {
            a = [[[SCRunningApplication alloc] init] autorelease];
            a->_processID = pid;
            a->_applicationName = [name copy];
            a->_bundleIdentifier = [bundleID copy];
            byPid[@(pid)] = a;
            [apps addObject:a];
        }
        return a;
    };
    app(me, own_name(), [[NSBundle mainBundle] bundleIdentifier] ?: @"");

    NSArray *all = ACaptureWindows();
    NSUInteger at = NSNotFound;
    if (mode == ListBelow || mode == ListAbove)
        for (NSUInteger i = 0; i < [all count] && at == NSNotFound; i++)
            if (((ACaptureWindow *)all[i])->number == relative)
                at = i;
    for (NSUInteger i = 0; i < [all count]; i++) {
        ACaptureWindow *w = all[i];
        if (ownOnly && !w->own)
            continue;
        if (excludeDesktop && w->layer < 0)
            continue;
        if (mode != ListAll && !w->onscreen)
            continue;
        if (mode == ListBelow && (at == NSNotFound || i <= at))
            continue;
        if (mode == ListAbove && (at == NSNotFound || i >= at))
            continue;
        SCWindow *s = [[[SCWindow alloc] init] autorelease];
        s->_windowID = w->number;
        s->_frame = w->frame;
        s->_title = [w->title copy];
        s->_layer = w->layer;
        s->_onScreen = w->onscreen;
        s->_app = [app(w->pid, w->owner ?: @"", w->bundleID ?: @"") retain];
        [windows addObject:s];
    }
    SCShareableContent *c = [[[SCShareableContent alloc] init] autorelease];
    c->_displays = [displays copy];
    c->_windows = [windows copy];
    c->_applications = [apps copy];
    return c;
}

+ (void)_getExcludingDesktop:(BOOL)excludeDesktop mode:(ListMode)mode relative:(CGWindowID)relative
                     ownOnly:(BOOL)ownOnly
           completionHandler:(void (^)(SCShareableContent *, NSError *))handler
{
    if (!handler)
        return;
    ACaptureNoteOwnWindows();
    dispatch_async(answer_queue(), ^{
        @autoreleasepool {
            NSError *e = nil;
            SCShareableContent *c = nil;
            if (!ownOnly && !ACaptureAllowed()) {
                ACaptureAsk();
                e = ACaptureError(SCStreamErrorUserDeclined, @"The user hasn't let this app record the screen.");
            } else if (!ACaptureAvailable())
                e = ACaptureError(SCStreamErrorNoDisplayList, @"There's no display this computer can record.");
            else
                c = [self _listExcludingDesktop:excludeDesktop mode:mode relative:relative ownOnly:ownOnly];
            handler(c, e);
        }
    });
}

+ (void)getShareableContentWithCompletionHandler:(void (^)(SCShareableContent *, NSError *))handler
{
    [self _getExcludingDesktop:NO mode:ListAll relative:0 ownOnly:NO completionHandler:handler];
}
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                               onScreenWindowsOnly:(BOOL)onScreenWindowsOnly
                                 completionHandler:(void (^)(SCShareableContent *, NSError *))handler
{
    [self _getExcludingDesktop:excludeDesktopWindows mode:onScreenWindowsOnly ? ListOnScreen : ListAll relative:0
                       ownOnly:NO completionHandler:handler];
}
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                    onScreenWindowsOnlyBelowWindow:(SCWindow *)window
                                 completionHandler:(void (^)(SCShareableContent *, NSError *))handler
{
    [self _getExcludingDesktop:excludeDesktopWindows mode:ListBelow relative:window.windowID ownOnly:NO
             completionHandler:handler];
}
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                    onScreenWindowsOnlyAboveWindow:(SCWindow *)window
                                 completionHandler:(void (^)(SCShareableContent *, NSError *))handler
{
    [self _getExcludingDesktop:excludeDesktopWindows mode:ListAbove relative:window.windowID ownOnly:NO
             completionHandler:handler];
}
+ (void)getCurrentProcessShareableContentWithCompletionHandler:(void (^)(SCShareableContent *, NSError *))handler
{
    [self _getExcludingDesktop:NO mode:ListAll relative:0 ownOnly:YES completionHandler:handler];
}

+ (SCShareableContentInfo *)infoForFilter:(SCContentFilter *)filter
{
    SCShareableContentInfo *i = [[[SCShareableContentInfo alloc] init] autorelease];
    i->_style = filter.style;
    i->_scale = filter.pointPixelScale;
    i->_rect = filter.contentRect;
    return i;
}
@end

/* ---- filters ----------------------------------------------------------------------------------- */

static NSArray *window_numbers(NSArray *windows)
{
    NSMutableArray *a = [NSMutableArray array];
    for (SCWindow *w in windows)
        [a addObject:@(w.windowID)];
    return a;
}

static NSArray *app_pids(NSArray *apps)
{
    NSMutableArray *a = [NSMutableArray array];
    for (SCRunningApplication *app in apps)
        [a addObject:@(app.processID)];
    return a;
}

@implementation SCContentFilter {
  @public
    SCShareableContentStyle _style;
    ACaptureSourceKind _kind;
    CGDirectDisplayID _display;
    CGWindowID _window;
    CGRect _windowFrame, _displayFrame;
    NSArray *_windows, *_pids, *_exceptions;
    BOOL _excluding, _includeMenuBar;
    CGFloat _scale;
}

- (instancetype)_initWithDisplay:(SCDisplay *)display
{
    if ((self = [super init])) {
        _style = SCShareableContentStyleDisplay;
        _kind = ACaptureSourceDisplay;
        _display = display.displayID;
        _displayFrame = display.frame;
        _scale = display ? display->_scale : 1;
        if (_scale <= 0)
            _scale = 1;
        _includeMenuBar = YES;
    }
    return self;
}

- (instancetype)initWithDesktopIndependentWindow:(SCWindow *)window
{
    if ((self = [super init])) {
        _style = SCShareableContentStyleWindow;
        _kind = ACaptureSourceWindow;
        _window = window.windowID;
        _windowFrame = window.frame;
        _display = 1;
        _scale = main_scale();
    }
    return self;
}

- (instancetype)initWithDisplay:(SCDisplay *)display excludingWindows:(NSArray *)excluded
{
    if ((self = [self _initWithDisplay:display]) && [excluded count]) {
        _kind = ACaptureSourceWindows;
        _windows = [window_numbers(excluded) copy];
        _excluding = YES;
    }
    return self;
}

- (instancetype)initWithDisplay:(SCDisplay *)display includingWindows:(NSArray *)included
{
    if ((self = [self _initWithDisplay:display])) {
        _kind = ACaptureSourceWindows;
        _windows = [window_numbers(included) copy];
    }
    return self;
}

- (instancetype)initWithDisplay:(SCDisplay *)display includingApplications:(NSArray *)applications
               exceptingWindows:(NSArray *)exceptingWindows
{
    if ((self = [self _initWithDisplay:display])) {
        _style = SCShareableContentStyleApplication;
        _kind = ACaptureSourceWindows;
        _pids = [app_pids(applications) copy];
        _exceptions = [window_numbers(exceptingWindows) copy];
    }
    return self;
}

- (instancetype)initWithDisplay:(SCDisplay *)display excludingApplications:(NSArray *)applications
               exceptingWindows:(NSArray *)exceptingWindows
{
    if ((self = [self _initWithDisplay:display]) && [applications count]) {
        _kind = ACaptureSourceWindows;
        _pids = [app_pids(applications) copy];
        _exceptions = [window_numbers(exceptingWindows) copy];
        _excluding = YES;
    }
    return self;
}

- (void)dealloc
{
    [_windows release];
    [_pids release];
    [_exceptions release];
    [super dealloc];
}

- (SCShareableContentStyle)style { return _style; }
- (float)pointPixelScale { return (float)_scale; }
- (CGRect)contentRect
{
    CGRect r = _kind == ACaptureSourceWindow ? _windowFrame : _displayFrame;
    return CGRectMake(0, 0, r.size.width, r.size.height);
}
- (BOOL)includeMenuBar { return _includeMenuBar; }
- (void)setIncludeMenuBar:(BOOL)b { _includeMenuBar = b; }

/* where the source is on the screen, in points */
- (CGRect)_screenRect:(CGRect)sourceRect
{
    if (_kind == ACaptureSourceWindow)
        return _windowFrame;
    if (!CGRectIsNull(sourceRect) && !CGRectIsEmpty(sourceRect))
        return CGRectOffset(sourceRect, _displayFrame.origin.x, _displayFrame.origin.y);
    return _displayFrame;
}

- (NSString *)description
{
    static const char *kinds[] = {"display", "window", "windows"};
    return [NSString stringWithFormat:@"<SCContentFilter %s %u%@>", kinds[_kind],
                                      _kind == ACaptureSourceWindow ? _window : _display,
                                      _excluding ? @" excluding" : @""];
}
@end

/* ---- configurations ---------------------------------------------------------------------------- */

@implementation SCStreamConfiguration {
    CFStringRef _colorMatrix, _colorSpaceName;
    CGColorRef _backgroundColor;
}
@synthesize width = _width, height = _height, minimumFrameInterval = _minimumFrameInterval,
            pixelFormat = _pixelFormat, scalesToFit = _scalesToFit, preservesAspectRatio = _preservesAspectRatio,
            streamName = _streamName, shouldBeOpaque = _shouldBeOpaque, ignoreShadowsDisplay = _ignoreShadowsDisplay,
            ignoreShadowsSingleWindow = _ignoreShadowsSingleWindow, ignoreGlobalClipDisplay = _ignoreGlobalClipDisplay,
            ignoreGlobalClipSingleWindow = _ignoreGlobalClipSingleWindow, includeChildWindows = _includeChildWindows,
            captureResolution = _captureResolution, sourceRect = _sourceRect, destinationRect = _destinationRect,
            queueDepth = _queueDepth, showsCursor = _showsCursor, showMouseClicks = _showMouseClicks,
            presenterOverlayPrivacyAlertSetting = _presenterOverlayPrivacyAlertSetting, capturesAudio = _capturesAudio,
            sampleRate = _sampleRate, channelCount = _channelCount,
            excludesCurrentProcessAudio = _excludesCurrentProcessAudio, captureMicrophone = _captureMicrophone,
            microphoneCaptureDeviceID = _microphoneCaptureDeviceID;

- (instancetype)init
{
    if ((self = [super init])) {
        _width = 1920;
        _height = 1080;
        _minimumFrameInterval = kCMTimeZero;
        _pixelFormat = kCVPixelFormatType_32BGRA;
        _preservesAspectRatio = YES;
        _sourceRect = CGRectNull;
        _destinationRect = CGRectNull;
        _queueDepth = 3;
        _showsCursor = YES;
        _includeChildWindows = YES;
        _sampleRate = 48000;
        _channelCount = 2;
    }
    return self;
}

- (void)dealloc
{
    if (_colorMatrix)
        CFRelease(_colorMatrix);
    if (_colorSpaceName)
        CFRelease(_colorSpaceName);
    if (_backgroundColor)
        CGColorRelease(_backgroundColor);
    [_streamName release];
    [_microphoneCaptureDeviceID release];
    [super dealloc];
}

- (CFStringRef)colorMatrix { return _colorMatrix ? _colorMatrix : kCVImageBufferYCbCrMatrix_ITU_R_709_2; }
- (void)setColorMatrix:(CFStringRef)s
{
    if (s)
        CFRetain(s);
    if (_colorMatrix)
        CFRelease(_colorMatrix);
    _colorMatrix = s;
}
- (CFStringRef)colorSpaceName { return _colorSpaceName ? _colorSpaceName : kCGColorSpaceSRGB; }
- (void)setColorSpaceName:(CFStringRef)s
{
    if (s)
        CFRetain(s);
    if (_colorSpaceName)
        CFRelease(_colorSpaceName);
    _colorSpaceName = s;
}
- (CGColorRef)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(CGColorRef)c
{
    if (c)
        CGColorRetain(c);
    if (_backgroundColor)
        CGColorRelease(_backgroundColor);
    _backgroundColor = c;
}

/* the core's configuration for this filter */
- (ACaptureConfig *)_configFor:(SCContentFilter *)f
{
    ACaptureConfig *c = [[[ACaptureConfig alloc] init] autorelease];
    c->kind = f->_kind;
    c->display = f->_display ? f->_display : 1;
    c->window = f->_window;
    c->windows = [f->_windows copy];
    c->pids = [f->_pids copy];
    c->exceptions = [f->_exceptions copy];
    c->excluding = f->_excluding;
    c->sourceRect = CGRectIsEmpty(_sourceRect) || f->_kind == ACaptureSourceWindow ? CGRectNull : _sourceRect;
    c->destinationRect = CGRectIsEmpty(_destinationRect) ? CGRectNull : _destinationRect;
    c->width = _width;
    c->height = _height;
    c->pixelFormat = _pixelFormat;
    c->queueDepth = _queueDepth;
    c->showsCursor = _showsCursor;
    c->scalesToFit = _scalesToFit;
    c->preservesAspectRatio = _preservesAspectRatio;
    c->windowAtTopLeft = YES;
    double seconds = CMTIME_IS_NUMERIC(_minimumFrameInterval) ? CMTimeGetSeconds(_minimumFrameInterval) : 0;
    c->minimumInterval = seconds > 0 ? (uint64_t)llround(seconds * 1e9) : 0;
    if (_backgroundColor) {
        size_t n = CGColorGetNumberOfComponents(_backgroundColor);
        const CGFloat *k = CGColorGetComponents(_backgroundColor);
        CGFloat r = 0, g = 0, b = 0, a = CGColorGetAlpha(_backgroundColor);
        if (k && n >= 3)
            r = k[0], g = k[1], b = k[2];
        else if (k && n >= 1)
            r = g = b = k[0];
        uint32_t (^byte)(CGFloat) = ^uint32_t(CGFloat v) {
            return (uint32_t)lround(fmin(fmax(v, 0), 1) * 255);
        };
        c->background = byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b);
    }
    c->ycbcr601 = _colorMatrix && CFEqual(_colorMatrix, kCVImageBufferYCbCrMatrix_ITU_R_601_4);
    return c;
}
@end

/* ---- streams ------------------------------------------------------------------------------------- */

@interface SCStreamOutputEntry : NSObject {
  @public
    id<SCStreamOutput> output;
    SCStreamOutputType type;
    dispatch_queue_t queue;
}
@end
@implementation SCStreamOutputEntry
- (void)dealloc
{
    [(id)output release];
    dispatch_release(queue);
    [super dealloc];
}
@end

/* a frame of the core as a sample buffer with the frame's attachments */
static CMSampleBufferRef sample_of(const ACaptureFrame *f, SCStreamConfiguration *config, SCContentFilter *filter)
{
    CMVideoFormatDescriptionRef format = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(NULL, f->frame, &format) != noErr)
        return NULL;
    CMSampleTimingInfo timing;
    timing.duration = CMTIME_IS_NUMERIC(config.minimumFrameInterval) && CMTimeGetSeconds(config.minimumFrameInterval) > 0
                          ? config.minimumFrameInterval
                          : kCMTimeInvalid;
    timing.presentationTimeStamp = CMClockMakeHostTimeFromSystemUnits(f->displayTime);
    timing.decodeTimeStamp = kCMTimeInvalid;
    CMSampleBufferRef sample = NULL;
    OSStatus err = CMSampleBufferCreateReadyWithImageBuffer(NULL, f->frame, format, &timing, &sample);
    CFRelease(format);
    if (err != noErr)
        return NULL;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, true);
    NSMutableDictionary *info = attachments && CFArrayGetCount(attachments)
                                    ? (NSMutableDictionary *)CFArrayGetValueAtIndex(attachments, 0)
                                    : nil;
    CGFloat scale = f->scaleFactor > 0 ? f->scaleFactor : 1;
    CGRect content = CGRectMake(f->contentRect.origin.x / scale, f->contentRect.origin.y / scale,
                                f->contentRect.size.width / scale, f->contentRect.size.height / scale);
    CFDictionaryRef contentDict = CGRectCreateDictionaryRepresentation(content);
    CFDictionaryRef screenDict = CGRectCreateDictionaryRepresentation([filter _screenRect:config.sourceRect]);
    info[SCStreamFrameInfoStatus] = @(SCFrameStatusComplete);
    info[SCStreamFrameInfoDisplayTime] = @(f->displayTime);
    info[SCStreamFrameInfoScaleFactor] = @(scale);
    info[SCStreamFrameInfoContentScale] = @(f->contentScale);
    info[SCStreamFrameInfoContentRect] = (id)contentDict;
    info[SCStreamFrameInfoScreenRect] = (id)screenDict;
    info[SCStreamFrameInfoBoundingRect] = (id)contentDict;
    info[SCStreamFrameInfoDirtyRects] = @[ (id)contentDict ];
    CFRelease(contentDict);
    CFRelease(screenDict);
    return sample;
}

@implementation SCStream {
    SCContentFilter *_filter;
    SCStreamConfiguration *_config;
    id<SCStreamDelegate> _delegate;     /* not retained */
    NSMutableArray *_outputs;
    ACaptureStream *_capture;
    NSMutableArray *_stopHandlers;
    pthread_mutex_t _lock;
    dispatch_queue_t _deliveryQueue, _defaultOutputQueue;
    BOOL _running;
  @public
    BOOL _audioRunning;
    atomic_int _audioStop;
    dispatch_semaphore_t _audioDone;
}

- (instancetype)initWithFilter:(SCContentFilter *)contentFilter configuration:(SCStreamConfiguration *)streamConfig
                      delegate:(id<SCStreamDelegate>)delegate
{
    if ((self = [super init])) {
        _filter = [contentFilter retain];
        _config = [streamConfig retain];
        _delegate = delegate;
        _outputs = [[NSMutableArray alloc] init];
        _stopHandlers = [[NSMutableArray alloc] init];
        pthread_mutex_init(&_lock, NULL);
        _deliveryQueue = dispatch_queue_create("ScreenCaptureKit (Ferry) frames", DISPATCH_QUEUE_SERIAL);
        _defaultOutputQueue = dispatch_queue_create("ScreenCaptureKit (Ferry) output", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc
{
    [_capture stop];
    [_capture release];
    if (_audioDone)
        dispatch_release(_audioDone);
    [_filter release];
    [_config release];
    [_outputs release];
    [_stopHandlers release];
    pthread_mutex_destroy(&_lock);
    dispatch_release(_deliveryQueue);
    dispatch_release(_defaultOutputQueue);
    [super dealloc];
}

- (CMClockRef)synchronizationClock { return CMClockGetHostTimeClock(); }

- (BOOL)addStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type
     sampleHandlerQueue:(dispatch_queue_t)queue error:(NSError **)error
{
    if (!output || type < SCStreamOutputTypeScreen || type > SCStreamOutputTypeMicrophone) {
        if (error)
            *error = ACaptureError(SCStreamErrorInvalidParameter, @"The stream output isn't one this stream takes.");
        return NO;
    }
    SCStreamOutputEntry *e = [[[SCStreamOutputEntry alloc] init] autorelease];
    e->output = [(id)output retain];
    e->type = type;
    e->queue = queue ? queue : _defaultOutputQueue;
    dispatch_retain(e->queue);
    pthread_mutex_lock(&_lock);
    [_outputs addObject:e];
    pthread_mutex_unlock(&_lock);
    return YES;
}

- (BOOL)removeStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type error:(NSError **)error
{
    BOOL found = NO;
    pthread_mutex_lock(&_lock);
    for (NSInteger i = (NSInteger)[_outputs count] - 1; i >= 0; i--) {
        SCStreamOutputEntry *e = _outputs[(NSUInteger)i];
        if (e->output == output && e->type == type) {
            [_outputs removeObjectAtIndex:(NSUInteger)i];
            found = YES;
        }
    }
    pthread_mutex_unlock(&_lock);
    if (!found && error)
        *error = ACaptureError(SCStreamErrorRemovingStream, @"The stream output wasn't added to this stream.");
    return found;
}

static void answer(void (^handler)(NSError *), NSError *e)
{
    if (!handler)
        return;
    [e retain];
    dispatch_async(answer_queue(), ^{
        handler(e);
        [e release];
    });
}

- (void)_deliver:(const ACaptureFrame *)f
{
    if (f->stopped) {
        pthread_mutex_lock(&_lock);
        NSArray *handlers = [[_stopHandlers copy] autorelease];
        [_stopHandlers removeAllObjects];
        ACaptureStream *capture = _capture;
        _capture = nil;
        _running = NO;
        pthread_mutex_unlock(&_lock);
        if (f->error && [(id)_delegate respondsToSelector:@selector(stream:didStopWithError:)])
            [_delegate stream:self didStopWithError:f->error];
        for (void (^h)(NSError *) in handlers)
            answer(h, nil);
        [capture autorelease];
        [self autorelease];     /* held while it ran */
        return;
    }
    pthread_mutex_lock(&_lock);
    SCStreamConfiguration *config = [[_config retain] autorelease];
    SCContentFilter *filter = [[_filter retain] autorelease];
    BOOL any = NO;
    for (SCStreamOutputEntry *e in _outputs)
        any |= e->type == SCStreamOutputTypeScreen;
    pthread_mutex_unlock(&_lock);
    if (!any)
        return;
    CMSampleBufferRef sample = sample_of(f, config, filter);
    if (!sample)
        return;
    [self _send:sample type:SCStreamOutputTypeScreen];
    CFRelease(sample);
}

/* to every output of that type, on its queue */
- (void)_send:(CMSampleBufferRef)sample type:(SCStreamOutputType)type
{
    NSMutableArray *to = [NSMutableArray array];
    pthread_mutex_lock(&_lock);
    for (SCStreamOutputEntry *e in _outputs)
        if (e->type == type)
            [to addObject:e];
    pthread_mutex_unlock(&_lock);
    for (SCStreamOutputEntry *e in to) {
        [e retain];
        CFRetain(sample);
        [self retain];
        dispatch_async(e->queue, ^{
            if ([(id)e->output respondsToSelector:@selector(stream:didOutputSampleBuffer:ofType:)])
                [e->output stream:self didOutputSampleBuffer:sample ofType:type];
            CFRelease(sample);
            [e release];
            [self release];
        });
    }
}

/* ---- the computer's sound ---- */

/* what records the sound the computer plays: the default output's monitor */
static ca_device *system_audio_device(void)
{
    ca_init();
    if (ca_backend_is_null())
        return ca_device_for(ca_default_device(CA_IN));   /* the null device's recording hears what it plays */
    pthread_mutex_lock(ca_lock());
    ca_device *out = ca_device_for(ca_default_device(CA_OUT)), *found = NULL;
    char want[300] = "";
    if (out)
        snprintf(want, sizeof want, "%s.monitor", out->server_name[CA_OUT]);
    AudioObjectID ids[128];
    UInt32 n = ca_device_list(ids, 128);
    for (UInt32 i = 0; i < n; i++) {
        ca_device *d = ca_device_for(ids[i]);
        if (!d || !d->alive || !d->monitor || !d->stream[CA_IN])
            continue;
        if (!strcmp(d->server_name[CA_IN], want)) {
            found = d;
            break;
        }
        if (!found)
            found = d;
    }
    pthread_mutex_unlock(ca_lock());
    return found;
}

enum { AUDIO_FRAMES = 1024 };

- (void)_recordAudio
{
    pthread_mutex_lock(&_lock);
    Float64 rate = _config.sampleRate > 0 ? (Float64)_config.sampleRate : 48000;
    UInt32 channels = _config.channelCount > 0 ? (UInt32)MIN(_config.channelCount, CA_MAX_CHANNELS) : 2;
    pthread_mutex_unlock(&_lock);
    ca_device *d = system_audio_device();
    ca_stream *in = d ? ca_stream_open(d, CA_IN, rate, channels, NULL, AUDIO_FRAMES) : NULL;
    if (!in) {
        ACaptureSayOnce("the sound the computer plays can't be recorded (the sound server has no monitor of its output)");
        return;
    }
    AudioStreamBasicDescription asbd;
    memset(&asbd, 0, sizeof asbd);
    asbd.mSampleRate = rate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    asbd.mBytesPerPacket = 4;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 4;
    asbd.mChannelsPerFrame = channels;
    asbd.mBitsPerChannel = 32;
    CMAudioFormatDescriptionRef format = NULL;
    CMAudioFormatDescriptionCreate(NULL, &asbd, 0, NULL, 0, NULL, NULL, &format);
    size_t bytes = (size_t)AUDIO_FRAMES * channels * sizeof(float);
    float *frames = malloc(bytes);
    uint64_t span = (uint64_t)((double)AUDIO_FRAMES * 1e9 / rate);
    while (format && frames && !atomic_load(&_audioStop)) {
        if (ca_stream_read(in, frames, AUDIO_FRAMES) < 0)
            break;
        uint64_t now = mach_absolute_time();
        @autoreleasepool {
            CMBlockBufferRef block = NULL;
            char *data = NULL;
            if (CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, NULL, NULL, 0, bytes,
                                                   kCMBlockBufferAssureMemoryNowFlag, &block) != noErr)
                break;
            CMBlockBufferGetDataPointer(block, 0, NULL, NULL, &data);
            float *planes = (float *)data;
            for (UInt32 c = 0; c < channels; c++)
                for (UInt32 i = 0; i < AUDIO_FRAMES; i++)
                    planes[c * AUDIO_FRAMES + i] = frames[i * channels + c];
            CMSampleBufferRef sample = NULL;
            CMAudioSampleBufferCreateWithPacketDescriptions(NULL, block, true, NULL, NULL, format, AUDIO_FRAMES,
                                                            CMClockMakeHostTimeFromSystemUnits(now > span ? now - span : 0),
                                                            NULL, &sample);
            CFRelease(block);
            if (sample) {
                [self _send:sample type:SCStreamOutputTypeAudio];
                CFRelease(sample);
            }
        }
    }
    free(frames);
    if (format)
        CFRelease(format);
    ca_stream_close(in, 0);
}

static void *audio_thread(void *p)
{
    SCStream *stream = p;
    dispatch_semaphore_t done = stream->_audioDone;
    dispatch_retain(done);
    @autoreleasepool {
        [stream _recordAudio];
    }
    [stream release];
    dispatch_semaphore_signal(done);
    dispatch_release(done);
    return NULL;
}

/* with the lock held */
- (void)_startAudio
{
    if (_audioRunning)
        return;
    if (!_audioDone)
        _audioDone = dispatch_semaphore_create(0);
    atomic_store(&_audioStop, 0);
    pthread_t t;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    [self retain];                    /* held while it records */
    if (pthread_create(&t, &attr, audio_thread, self) == 0)
        _audioRunning = YES;
    else
        [self autorelease];
    pthread_attr_destroy(&attr);
}

/* without the lock held: until its thread has finished */
- (void)_stopAudio
{
    pthread_mutex_lock(&_lock);
    BOOL was = _audioRunning;
    _audioRunning = NO;
    pthread_mutex_unlock(&_lock);
    if (!was)
        return;
    atomic_store(&_audioStop, 1);
    dispatch_semaphore_wait(_audioDone, dispatch_time(DISPATCH_TIME_NOW, 2 * (int64_t)NSEC_PER_SEC));
}

- (void)startCaptureWithCompletionHandler:(void (^)(NSError *))handler
{
    pthread_mutex_lock(&_lock);
    BOOL already = _running;
    pthread_mutex_unlock(&_lock);
    if (already) {
        answer(handler, ACaptureError(SCStreamErrorAttemptToStartStreamState, @"The stream is already running."));
        return;
    }
    if (!ACaptureAllowed()) {
        ACaptureAsk();
        answer(handler, ACaptureError(SCStreamErrorUserDeclined, @"The user hasn't let this app record the screen."));
        return;
    }
    __block SCStream *me = self;      /* not retained by the block: the stream holds itself while it runs */
    ACaptureStream *capture = [[ACaptureStream alloc] initWithConfig:[_config _configFor:_filter]
                                                               queue:_deliveryQueue
                                                             handler:^(const ACaptureFrame *f) {
                                                                 @autoreleasepool {
                                                                     [me _deliver:f];
                                                                 }
                                                             }];
    NSError *why = nil;
    pthread_mutex_lock(&_lock);
    _capture = capture;
    _running = YES;
    [self retain];
    BOOL audio = _config.capturesAudio;
    pthread_mutex_unlock(&_lock);
    if (![capture start:&why]) {
        pthread_mutex_lock(&_lock);
        _capture = nil;
        _running = NO;
        pthread_mutex_unlock(&_lock);
        [capture release];
        [self autorelease];
        answer(handler, why ?: ACaptureError(SCStreamErrorFailedToStart, @"The stream couldn't start."));
        return;
    }
    if (audio) {
        pthread_mutex_lock(&_lock);
        [self _startAudio];
        pthread_mutex_unlock(&_lock);
    }
    answer(handler, nil);
}

- (void)stopCaptureWithCompletionHandler:(void (^)(NSError *))handler
{
    pthread_mutex_lock(&_lock);
    ACaptureStream *capture = [[_capture retain] autorelease];
    if (capture && handler) {
        void (^h)(NSError *) = [handler copy];
        [_stopHandlers addObject:h];
        [h release];
    }
    pthread_mutex_unlock(&_lock);
    if (!capture) {
        answer(handler, ACaptureError(SCStreamErrorAttemptToStopStreamState, @"The stream isn't running."));
        return;
    }
    [self _stopAudio];
    [capture stop];
}

- (void)updateConfiguration:(SCStreamConfiguration *)streamConfig completionHandler:(void (^)(NSError *))handler
{
    if (!streamConfig) {
        answer(handler, ACaptureError(SCStreamErrorInvalidParameter, @"There's no configuration."));
        return;
    }
    pthread_mutex_lock(&_lock);
    [streamConfig retain];
    [_config release];
    _config = streamConfig;
    ACaptureStream *capture = [[_capture retain] autorelease];
    ACaptureConfig *c = [_config _configFor:_filter];
    BOOL audio = _config.capturesAudio, stopAudio = capture && _audioRunning && !audio;
    if (capture && audio)
        [self _startAudio];
    pthread_mutex_unlock(&_lock);
    if (stopAudio)
        [self _stopAudio];
    [capture setConfig:c];
    answer(handler, nil);
}

- (void)updateContentFilter:(SCContentFilter *)contentFilter completionHandler:(void (^)(NSError *))handler
{
    if (!contentFilter) {
        answer(handler, ACaptureError(SCStreamErrorInvalidParameter, @"There's no content filter."));
        return;
    }
    pthread_mutex_lock(&_lock);
    [contentFilter retain];
    [_filter release];
    _filter = contentFilter;
    ACaptureStream *capture = [[_capture retain] autorelease];
    ACaptureConfig *c = [_config _configFor:_filter];
    pthread_mutex_unlock(&_lock);
    [capture setConfig:c];
    answer(handler, nil);
}
@end

/* ---- single pictures ----------------------------------------------------------------------------- */

@implementation SCScreenshotManager

/* the first frame of a stream with this filter and configuration */
+ (void)_captureWithFilter:(SCContentFilter *)filter configuration:(SCStreamConfiguration *)config
                completion:(void (^)(CMSampleBufferRef, NSError *))done
{
    if (!ACaptureAllowed()) {
        ACaptureAsk();
        NSError *e = ACaptureError(SCStreamErrorUserDeclined, @"The user hasn't let this app record the screen.");
        dispatch_async(answer_queue(), ^{
            done(NULL, e);
        });
        return;
    }
    dispatch_queue_t q = dispatch_queue_create("ScreenCaptureKit (Ferry) picture", DISPATCH_QUEUE_SERIAL);
    __block BOOL answered = NO;
    __block ACaptureStream *capture = nil;
    filter = [filter retain];
    config = [config retain];
    void (^finish)(CMSampleBufferRef, NSError *) = ^(CMSampleBufferRef s, NSError *e) {
        /* on q */
        if (answered)
            return;
        answered = YES;
        if (s)
            CFRetain(s);
        [e retain];
        dispatch_async(answer_queue(), ^{
            done(s, e);
            if (s)
                CFRelease(s);
            [e release];
        });
        [capture stop];
    };
    capture = [[ACaptureStream alloc] initWithConfig:[config _configFor:filter] queue:q
                                             handler:^(const ACaptureFrame *f) {
                                                 @autoreleasepool {
                                                     if (f->stopped) {
                                                         finish(NULL, f->error ?: ACaptureError(SCStreamErrorFailedToStart,
                                                                                                @"Nothing could be recorded."));
                                                         [capture release];
                                                         [filter release];
                                                         [config release];
                                                         return;
                                                     }
                                                     CMSampleBufferRef s = sample_of(f, config, filter);
                                                     if (s) {
                                                         finish(s, nil);
                                                         CFRelease(s);
                                                     }
                                                 }
                                             }];
    NSError *why = nil;
    if (![capture start:&why]) {
        dispatch_async(q, ^{
            finish(NULL, why ?: ACaptureError(SCStreamErrorFailedToStart, @"Nothing could be recorded."));
            [capture release];
            [filter release];
            [config release];
        });
    }
    dispatch_release(q);
}

+ (void)captureSampleBufferWithFilter:(SCContentFilter *)contentFilter configuration:(SCStreamConfiguration *)config
                    completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler
{
    if (!handler)
        return;
    [self _captureWithFilter:contentFilter configuration:config completion:handler];
}

+ (void)captureImageWithFilter:(SCContentFilter *)contentFilter configuration:(SCStreamConfiguration *)config
             completionHandler:(void (^)(CGImageRef, NSError *))handler
{
    if (!handler)
        return;
    SCStreamConfiguration *c = config;
    [self _captureWithFilter:contentFilter configuration:c
                  completion:^(CMSampleBufferRef s, NSError *e) {
                      CGImageRef image = NULL;
                      CVPixelBufferRef pb = s ? (CVPixelBufferRef)CMSampleBufferGetImageBuffer(s) : NULL;
                      if (pb && CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA) {
                          CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                          size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb),
                                 bpr = CVPixelBufferGetBytesPerRow(pb);
                          CFDataRef data = CFDataCreate(NULL, CVPixelBufferGetBaseAddress(pb), (CFIndex)(bpr * h));
                          CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
                          CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
                          CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
                          image = CGImageCreate(w, h, 8, 32, bpr, space,
                                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider,
                                                NULL, false, kCGRenderingIntentDefault);
                          CGColorSpaceRelease(space);
                          CGDataProviderRelease(provider);
                          CFRelease(data);
                      } else if (s && !e)
                          e = ACaptureError(SCStreamErrorInvalidParameter,
                                            @"A picture as a CGImage needs the 'BGRA' pixel format.");
                      handler(image, e);
                      if (image)
                          CGImageRelease(image);
                  }];
}
@end
