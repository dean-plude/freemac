/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * AVFoundation's capture devices (freemac 1.233, Ferry 0.57.0): see
 * AVFoundation/AVCaptureDevice.h.
 *
 * Access to the microphone and the camera (freemac 1.241, Ferry 0.65.0) is
 * the user's say, as screen recording is: kept for each app in
 * ~/.config/freemac/microphone.json and camera.json, and asked once with
 * freemac-allow-control --kind microphone or camera (appkit/ACapture.m).
 * requestAccessForMediaType: answers on a queue of its own, as Apple
 * documents, once the user has: OBS Studio waits for the answer on its
 * main thread.
 *
 * Cameras (freemac 1.257, Ferry 0.80.0) are this system's, as src/camera.c
 * lists them: each one AVCaptureDevice object for the program's life, so
 * the one an app holds is the one it finds again, and a camera unplugged
 * is not connected until it comes back. Their formats are the camera's
 * modes, one for each pixel format and size, each with its frame rates;
 * the active one is the camera's best near 1280 by 720 at 30 a second
 * until the app or a session's preset chooses. Plugging a camera in or
 * out is noticed within two seconds, while the program has asked for the
 * cameras, and posted as AVCaptureDeviceWasConnected and
 * AVCaptureDeviceWasDisconnected. */
#import "AVCaptureInternal.h"
#import "ACapture.h"
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

AVMediaType const AVMediaTypeVideo = @"vide";
AVMediaType const AVMediaTypeAudio = @"soun";
AVMediaType const AVMediaTypeMuxed = @"muxx";
AVMediaType const AVMediaTypeText = @"text";
AVMediaType const AVMediaTypeSubtitle = @"sbtl";

AVCaptureDeviceType const AVCaptureDeviceTypeBuiltInWideAngleCamera = @"AVCaptureDeviceTypeBuiltInWideAngleCamera";
AVCaptureDeviceType const AVCaptureDeviceTypeExternal = @"AVCaptureDeviceTypeExternal";
AVCaptureDeviceType const AVCaptureDeviceTypeExternalUnknown = @"AVCaptureDeviceTypeExternal";
AVCaptureDeviceType const AVCaptureDeviceTypeContinuityCamera = @"AVCaptureDeviceTypeContinuityCamera";
AVCaptureDeviceType const AVCaptureDeviceTypeDeskViewCamera = @"AVCaptureDeviceTypeDeskViewCamera";
AVCaptureDeviceType const AVCaptureDeviceTypeMicrophone = @"AVCaptureDeviceTypeMicrophone";
AVCaptureDeviceType const AVCaptureDeviceTypeBuiltInMicrophone = @"AVCaptureDeviceTypeMicrophone";

NSNotificationName const AVCaptureDeviceWasConnectedNotification = @"AVCaptureDeviceWasConnectedNotification";
NSNotificationName const AVCaptureDeviceWasDisconnectedNotification = @"AVCaptureDeviceWasDisconnectedNotification";

void *ferry_camera_symbol(const char *name); /* src/camera.c */

void *AVCameraCall(const char *name) { return ferry_camera_symbol(name); }

OSType AVCameraNativePixelFormat(uint32_t fourcc)
{
    switch (fourcc) {
    case FERRY_CAMERA_YUYV: return kCVPixelFormatType_422YpCbCr8_yuvs;
    case FERRY_CAMERA_UYVY: return kCVPixelFormatType_422YpCbCr8;
    case FERRY_CAMERA_NV12:
    case FERRY_CAMERA_I420: return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    default: return kCVPixelFormatType_32BGRA;
    }
}

FourCharCode AVCameraSubtype(uint32_t fourcc)
{
    return fourcc == FERRY_CAMERA_MJPEG ? kCMVideoCodecType_JPEG_OpenDML : AVCameraNativePixelFormat(fourcc);
}

/* ---- rates and formats ------------------------------------------------------------------------- */

@implementation AVFrameRateRange {
    CMTime _duration;
}
- (instancetype)_initWithRate:(struct ferry_camera_rate)r
{
    if ((self = [super init]))
        _duration = CMTimeMake((int64_t)r.num, (int32_t)r.den);
    return self;
}
- (Float64)minFrameRate { return 1.0 / CMTimeGetSeconds(_duration); }
- (Float64)maxFrameRate { return 1.0 / CMTimeGetSeconds(_duration); }
- (CMTime)minFrameDuration { return _duration; }
- (CMTime)maxFrameDuration { return _duration; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<AVFrameRateRange: %p %.2f - %.2f>", self, self.minFrameRate, self.maxFrameRate];
}
@end

static NSString *fourcc_string(FourCharCode c)
{
    char s[5] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c, 0};
    return @(s);
}

@implementation AVCaptureDeviceFormat {
    struct ferry_camera_mode _m;
    CMFormatDescriptionRef _description;
    NSArray *_ranges;
}
- (instancetype)_initWithMode:(const struct ferry_camera_mode *)mode
{
    if (!(self = [super init]))
        return nil;
    _m = *mode;
    NSMutableDictionary *ext = [NSMutableDictionary dictionary];
    if (mode->fourcc != FERRY_CAMERA_MJPEG) {
        /* what this system's cameras send: Rec. 601 colours, in video range */
        ext[(id)kCMFormatDescriptionExtension_YCbCrMatrix] = (id)kCVImageBufferYCbCrMatrix_ITU_R_601_4;
        ext[(id)kCMFormatDescriptionExtension_FullRangeVideo] = @NO;
    }
    ext[(id)kCMFormatDescriptionExtension_ColorPrimaries] = (id)kCVImageBufferColorPrimaries_ITU_R_709_2;
    ext[(id)kCMFormatDescriptionExtension_TransferFunction] = (id)kCVImageBufferTransferFunction_ITU_R_709_2;
    CMVideoFormatDescriptionCreate(NULL, AVCameraSubtype(mode->fourcc), mode->width, mode->height,
                                   (CFDictionaryRef)ext, (CMVideoFormatDescriptionRef *)&_description);
    NSMutableArray *ranges = [NSMutableArray array];
    for (uint32_t i = 0; i < mode->nrates && i < 12; i++) {
        AVFrameRateRange *r = [[AVFrameRateRange alloc] _initWithRate:mode->rates[i]];
        [ranges addObject:r];
        [r release];
    }
    /* fastest first, as a Mac lists them */
    [ranges sortUsingComparator:^NSComparisonResult(AVFrameRateRange *a, AVFrameRateRange *b) {
        return a.maxFrameRate > b.maxFrameRate ? NSOrderedAscending
             : a.maxFrameRate < b.maxFrameRate ? NSOrderedDescending
                                               : NSOrderedSame;
    }];
    _ranges = [ranges copy];
    return self;
}
- (void)dealloc
{
    if (_description)
        CFRelease(_description);
    [_ranges release];
    [super dealloc];
}
- (const struct ferry_camera_mode *)_mode { return &_m; }
- (AVMediaType)mediaType { return AVMediaTypeVideo; }
- (CMFormatDescriptionRef)formatDescription { return _description; }
- (NSArray<AVFrameRateRange *> *)videoSupportedFrameRateRanges { return _ranges; }
- (float)videoFieldOfView { return 0; }
- (CMVideoDimensions)highResolutionStillImageDimensions { return (CMVideoDimensions){_m.width, _m.height}; }
- (BOOL)isVideoBinned { return NO; }
- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[AVCaptureDeviceFormat class]])
        return NO;
    const struct ferry_camera_mode *o = [other _mode];
    return o->fourcc == _m.fourcc && o->width == _m.width && o->height == _m.height;
}
- (NSUInteger)hash { return _m.fourcc ^ ((NSUInteger)_m.width << 16) ^ (NSUInteger)_m.height; }
- (NSString *)description
{
    AVFrameRateRange *fast = [_ranges firstObject], *slow = [_ranges lastObject];
    return [NSString stringWithFormat:@"<AVCaptureDeviceFormat: %p 'vide'/'%@' %dx%d, { %.0f-%.0f fps }>", self,
                                      fourcc_string(AVCameraSubtype(_m.fourcc)), _m.width, _m.height,
                                      slow.minFrameRate, fast.maxFrameRate];
}
@end

/* ---- the cameras ------------------------------------------------------------------------------- */

static pthread_mutex_t cameras_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary<NSString *, AVCaptureDevice *> *by_id; /* every camera seen, by its unique ID */
static NSMutableArray<NSString *> *order;                          /* in the order they were first seen */
static NSArray<NSString *> *video_nodes;                           /* /dev/video* when last listed */

@implementation AVCaptureDevice {
    NSString *_uniqueID, *_name, *_model, *_maker, *_path;
    BOOL _builtin, _connected;
    NSArray *_formats;
    AVCaptureDeviceFormat *_active;
    CMTime _minDuration, _maxDuration;
    NSInteger _locks;
    AVCaptureSession *_session; /* not retained: the session tells it when it lets go */
}

static AVCaptureDeviceFormat *best_format(NSArray<AVCaptureDeviceFormat *> *formats)
{
    AVCaptureDeviceFormat *best = nil;
    double best_score = -1e30;
    for (AVCaptureDeviceFormat *f in formats) {
        const struct ferry_camera_mode *m = [f _mode];
        double fps = [[f.videoSupportedFrameRateRanges firstObject] maxFrameRate];
        double area = (double)m->width * m->height;
        double score = -fabs(log(area / (1280.0 * 720.0))) * 4 /* near 720p */ + (fps >= 25 ? 8 : fps / 4) +
                       (m->fourcc == FERRY_CAMERA_MJPEG ? -1 : 0);
        if (score > best_score)
            best_score = score, best = f;
    }
    return best;
}

- (instancetype)_initWithCamera:(const struct ferry_camera *)c
{
    if (!(self = [super init]))
        return nil;
    _uniqueID = [@(c->id) copy];
    _connected = YES;
    [self _update:c];
    return self;
}

- (void)_update:(const struct ferry_camera *)c
{
    [_name release], [_model release], [_maker release], [_path release];
    _name = [@(c->name) copy];
    _model = [@(c->model) copy];
    _maker = [@(c->manufacturer) copy];
    _path = [@(c->path) copy];
    _builtin = c->builtin != 0;
    ferry_camera_modes_fn modes = (ferry_camera_modes_fn)AVCameraCall("modes");
    struct ferry_camera_mode m[96];
    int n = modes ? modes(c->path, m, 96) : 0;
    NSMutableArray *formats = [NSMutableArray array];
    for (int i = 0; i < n; i++) {
        AVCaptureDeviceFormat *f = [[AVCaptureDeviceFormat alloc] _initWithMode:&m[i]];
        if (![formats containsObject:f])
            [formats addObject:f];
        [f release];
    }
    [_formats release];
    _formats = [formats copy];
    AVCaptureDeviceFormat *keep = _active && [_formats containsObject:_active]
                                      ? [_formats objectAtIndex:[_formats indexOfObject:_active]]
                                      : best_format(_formats);
    [self _applyFormat:keep];
}

- (void)dealloc
{
    [_uniqueID release], [_name release], [_model release], [_maker release], [_path release];
    [_formats release];
    [_active release];
    [super dealloc];
}

/* Lists the cameras, keeping the objects already made; says which came and went. */
static void refresh(NSMutableArray *came, NSMutableArray *went)
{
    ferry_camera_list_fn list = (ferry_camera_list_fn)AVCameraCall("list");
    struct ferry_camera *cams = calloc(32, sizeof *cams);
    int n = list && cams ? list(cams, 32) : 0;
    if (!by_id) {
        by_id = [[NSMutableDictionary alloc] init];
        order = [[NSMutableArray alloc] init];
    }
    NSMutableSet *now = [NSMutableSet set];
    for (int i = 0; i < n; i++) {
        NSString *key = @(cams[i].id);
        [now addObject:key];
        AVCaptureDevice *d = by_id[key];
        if (!d) {
            d = [[AVCaptureDevice alloc] _initWithCamera:&cams[i]];
            by_id[key] = d;
            [order addObject:key];
            [d release];
            [came addObject:d];
        } else if (!d->_connected) {
            d->_connected = YES;
            [d _update:&cams[i]];
            [came addObject:d];
        } else if (strcmp([d->_path UTF8String], cams[i].path))
            [d _update:&cams[i]];
    }
    for (NSString *key in order) {
        AVCaptureDevice *d = by_id[key];
        if (d->_connected && ![now containsObject:key]) {
            d->_connected = NO;
            [went addObject:d];
        }
    }
    free(cams);
}

static NSArray<NSString *> *current_nodes(void)
{
    NSMutableArray *nodes = [NSMutableArray array];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev" error:NULL])
        if ([name hasPrefix:@"video"])
            [nodes addObject:name];
    [nodes sortUsingSelector:@selector(compare:)];
    return nodes;
}

static void post(NSArray *devices, NSNotificationName name)
{
    if (![devices count])
        return;
    NSArray *copy = [devices copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (AVCaptureDevice *d in copy)
            [[NSNotificationCenter defaultCenter] postNotificationName:name object:d];
        [copy release];
    });
}

/* every two seconds, while the program runs: the cameras again when /dev/video* changed */
static void watch(void)
{
    static dispatch_source_t timer;
    if (timer)
        return;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC,
                              NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{
        @autoreleasepool {
            NSArray *nodes = current_nodes();
            pthread_mutex_lock(&cameras_lock);
            BOOL changed = ![nodes isEqualToArray:video_nodes];
            NSMutableArray *came = [NSMutableArray array], *went = [NSMutableArray array];
            if (changed) {
                [video_nodes release];
                video_nodes = [nodes copy];
                refresh(came, went);
            }
            pthread_mutex_unlock(&cameras_lock);
            post(went, AVCaptureDeviceWasDisconnectedNotification);
            post(came, AVCaptureDeviceWasConnectedNotification);
        }
    });
    dispatch_resume(timer);
}

/* the connected cameras, listed now */
static NSArray<AVCaptureDevice *> *cameras(void)
{
    NSMutableArray *out = [NSMutableArray array];
    NSArray *nodes = current_nodes();
    pthread_mutex_lock(&cameras_lock);
    NSMutableArray *came = [NSMutableArray array], *went = [NSMutableArray array];
    [video_nodes release];
    video_nodes = [nodes copy];
    refresh(came, went);
    for (NSString *key in order)
        if (by_id[key]->_connected)
            [out addObject:by_id[key]];
    pthread_mutex_unlock(&cameras_lock);
    watch();
    return out;
}

static BOOL is_camera_type(AVMediaType mediaType)
{
    return [mediaType isEqualToString:AVMediaTypeVideo] || [mediaType isEqualToString:AVMediaTypeMuxed];
}

+ (NSArray<AVCaptureDevice *> *)devices { return cameras(); }
+ (NSArray<AVCaptureDevice *> *)devicesWithMediaType:(AVMediaType)mediaType
{
    return [mediaType isEqualToString:AVMediaTypeVideo] ? cameras() : @[];
}
+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType
{
    if (![mediaType isEqualToString:AVMediaTypeVideo])
        return nil;
    NSArray *all = cameras();
    for (AVCaptureDevice *d in all) /* a built-in camera first, as on a Mac */
        if (d->_builtin)
            return d;
    return [all firstObject];
}
+ (AVCaptureDevice *)deviceWithUniqueID:(NSString *)deviceUniqueID
{
    if (![deviceUniqueID length])
        return nil;
    cameras();
    pthread_mutex_lock(&cameras_lock);
    AVCaptureDevice *d = [[by_id[deviceUniqueID] retain] autorelease];
    pthread_mutex_unlock(&cameras_lock);
    return d;
}

/* the file a media type's answer is kept in: video and muxed (a camera
 * with its sound) is the camera's, audio the microphone's */
static NSString *access_kind(AVMediaType mediaType)
{
    if ([mediaType isEqualToString:AVMediaTypeAudio])
        return @"microphone";
    if (is_camera_type(mediaType))
        return @"camera";
    return nil;
}

static AVAuthorizationStatus status_of(int answer)
{
    return answer == 1 ? AVAuthorizationStatusAuthorized
         : answer == 0 ? AVAuthorizationStatusDenied
                       : AVAuthorizationStatusNotDetermined;
}

+ (AVAuthorizationStatus)authorizationStatusForMediaType:(AVMediaType)mediaType
{
    NSString *kind = access_kind(mediaType);
    return kind ? status_of(ACaptureStoredAnswerOfKind(kind)) : AVAuthorizationStatusNotDetermined;
}
+ (void)requestAccessForMediaType:(AVMediaType)mediaType completionHandler:(void (^)(BOOL))handler
{
    NSString *kind = access_kind(mediaType);
    void (^answer)(BOOL) = [handler copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL granted = NO;
        if (kind) {
            if (ACaptureStoredAnswerOfKind(kind) < 0)
                ACaptureAskKind(kind, YES);
            granted = ACaptureStoredAnswerOfKind(kind) == 1;
        }
        if (answer)
            answer(granted);
        [answer release];
    });
}

- (NSString *)uniqueID { return _uniqueID; }
- (NSString *)modelID { return _model; }
- (NSString *)localizedName { return _name; }
- (NSString *)manufacturer { return _maker; }
- (BOOL)isConnected { return _connected; }
- (AVCaptureDevicePosition)position { return AVCaptureDevicePositionUnspecified; }
- (BOOL)hasMediaType:(AVMediaType)mediaType { return [mediaType isEqualToString:AVMediaTypeVideo]; }
- (AVCaptureDeviceType)deviceType
{
    return _builtin ? AVCaptureDeviceTypeBuiltInWideAngleCamera : AVCaptureDeviceTypeExternal;
}
- (BOOL)isSuspended { return NO; }
- (BOOL)isInUseByAnotherApplication { return NO; }
- (BOOL)transportControlsSupported { return NO; }
- (int32_t)transportType { return _builtin ? 'bltn' : 'usb '; }
- (NSString *)_path { return _path; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<AVCaptureDevice: %p [%@][%@]>", self, _name, _uniqueID];
}

- (NSArray<AVCaptureDeviceFormat *> *)formats { return _formats; }
- (AVCaptureDeviceFormat *)activeFormat { return [[_active retain] autorelease]; }

/* a format of this device's own, with its fastest rate */
- (void)_applyFormat:(AVCaptureDeviceFormat *)format
{
    if (!format)
        return;
    [format retain];
    [_active release];
    _active = format;
    AVFrameRateRange *fast = [format.videoSupportedFrameRateRanges firstObject];
    _minDuration = _maxDuration = fast ? fast.minFrameDuration : CMTimeMake(1, 30);
}

- (void)setActiveFormat:(AVCaptureDeviceFormat *)format
{
    if (!format || ![_formats containsObject:format]) {
        [NSException raise:NSInvalidArgumentException format:@"%@ is not one of %@'s formats", format, _name];
        return;
    }
    [self _applyFormat:[_formats objectAtIndex:[_formats indexOfObject:format]]];
    [_session _deviceChanged:self];
}

- (CMTime)activeVideoMinFrameDuration { return _minDuration; }
- (CMTime)activeVideoMaxFrameDuration { return _maxDuration; }

/* a duration the active format has, the nearest one; invalid: the format's own */
- (CMTime)_supported:(CMTime)t
{
    NSArray *ranges = _active.videoSupportedFrameRateRanges;
    if (!CMTIME_IS_NUMERIC(t) || ![ranges count])
        return [[ranges firstObject] minFrameDuration];
    double want = CMTimeGetSeconds(t), best_gap = 1e30;
    CMTime best = [[ranges firstObject] minFrameDuration];
    for (AVFrameRateRange *r in ranges) {
        double gap = fabs(CMTimeGetSeconds(r.minFrameDuration) - want);
        if (gap < best_gap)
            best_gap = gap, best = r.minFrameDuration;
    }
    return best;
}
- (void)setActiveVideoMinFrameDuration:(CMTime)t
{
    _minDuration = [self _supported:t];
    if (CMTimeCompare(_maxDuration, _minDuration) < 0)
        _maxDuration = _minDuration;
    [_session _deviceChanged:self];
}
- (void)setActiveVideoMaxFrameDuration:(CMTime)t
{
    _maxDuration = [self _supported:t];
    if (CMTimeCompare(_minDuration, _maxDuration) > 0)
        _minDuration = _maxDuration;
    [_session _deviceChanged:self];
}

- (BOOL)lockForConfiguration:(NSError **)outError
{
    @synchronized(self) {
        _locks++;
    }
    return YES;
}
- (void)unlockForConfiguration
{
    @synchronized(self) {
        if (_locks > 0)
            _locks--;
    }
}

static BOOL size_of_preset(NSString *p, int *w, int *h)
{
    static const struct { const char *name; int w, h; } sizes[] = {
        {"AVCaptureSessionPreset320x240", 320, 240},    {"AVCaptureSessionPreset352x288", 352, 288},
        {"AVCaptureSessionPreset640x480", 640, 480},    {"AVCaptureSessionPreset960x540", 960, 540},
        {"AVCaptureSessionPreset1280x720", 1280, 720},  {"AVCaptureSessionPreset1920x1080", 1920, 1080},
        {"AVCaptureSessionPreset3840x2160", 3840, 2160}, {"AVCaptureSessionPresetiFrame960x540", 960, 540},
        {"AVCaptureSessionPresetiFrame1280x720", 1280, 720},
    };
    for (size_t i = 0; i < sizeof sizes / sizeof *sizes; i++)
        if ([p isEqualToString:@(sizes[i].name)]) {
            *w = sizes[i].w, *h = sizes[i].h;
            return YES;
        }
    return NO;
}

- (AVCaptureDeviceFormat *)_formatForPreset:(NSString *)preset
{
    if (![_formats count] || [preset isEqualToString:@"AVCaptureSessionPresetInputPriority"])
        return nil;
    int w = 0, h = 0;
    if (size_of_preset(preset, &w, &h)) { /* that size, the fastest of its formats */
        AVCaptureDeviceFormat *best = nil;
        double best_fps = -1;
        for (AVCaptureDeviceFormat *f in _formats) {
            const struct ferry_camera_mode *m = [f _mode];
            double fps = [[f.videoSupportedFrameRateRanges firstObject] maxFrameRate] -
                         (m->fourcc == FERRY_CAMERA_MJPEG ? 0.5 : 0);
            if (m->width == w && m->height == h && fps > best_fps)
                best_fps = fps, best = f;
        }
        return best;
    }
    if ([preset isEqualToString:@"AVCaptureSessionPresetHigh"])
        return best_format(_formats);
    /* Photo the largest, Medium near 480 by 360 and Low the smallest, the fastest of those */
    BOOL photo = [preset isEqualToString:@"AVCaptureSessionPresetPhoto"];
    BOOL low = [preset isEqualToString:@"AVCaptureSessionPresetLow"];
    if (!photo && !low && ![preset isEqualToString:@"AVCaptureSessionPresetMedium"])
        return nil;
    AVCaptureDeviceFormat *best = nil;
    double best_score = -1e30;
    for (AVCaptureDeviceFormat *f in _formats) {
        const struct ferry_camera_mode *m = [f _mode];
        double area = (double)m->width * m->height;
        double fps = [[f.videoSupportedFrameRateRanges firstObject] maxFrameRate];
        double score = (photo ? log(area) : low ? -log(area) : -fabs(log(area / (480.0 * 360.0)))) * 4 + fps / 100;
        if (score > best_score)
            best_score = score, best = f;
    }
    return best;
}

- (BOOL)supportsAVCaptureSessionPreset:(NSString *)preset
{
    return [preset isEqualToString:@"AVCaptureSessionPresetInputPriority"] || [self _formatForPreset:preset] != nil;
}

- (void)_setSession:(AVCaptureSession *)session { _session = session; }
@end

@implementation AVCaptureDeviceDiscoverySession {
    NSArray *_types;
    AVMediaType _mediaType;
    AVCaptureDevicePosition _position;
}
+ (instancetype)discoverySessionWithDeviceTypes:(NSArray<AVCaptureDeviceType> *)deviceTypes
                                      mediaType:(AVMediaType)mediaType
                                       position:(AVCaptureDevicePosition)position
{
    AVCaptureDeviceDiscoverySession *s = [[[self alloc] init] autorelease];
    s->_types = [deviceTypes copy];
    s->_mediaType = [mediaType copy];
    s->_position = position;
    return s;
}
- (void)dealloc
{
    [_types release];
    [_mediaType release];
    [super dealloc];
}
- (NSArray<AVCaptureDevice *> *)devices
{
    /* a camera's own sound isn't read here, so it isn't listed as muxed */
    if (_mediaType && ![_mediaType isEqualToString:AVMediaTypeVideo])
        return @[];
    if (_position != AVCaptureDevicePositionUnspecified)
        return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (AVCaptureDevice *d in cameras())
        if (!_types || [_types containsObject:d.deviceType])
            [out addObject:d];
    return out;
}
@end
