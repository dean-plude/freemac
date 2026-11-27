/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * AVFoundation's capture sessions, for cameras (freemac 1.257, Ferry 0.80.0):
 * see AVFoundation/AVCaptureSession.h.
 *
 * A running session reads its camera (the device of its one device input)
 * on a thread of its own, in the device's active format at its active
 * rate, and hands each picture to every video data output: copied into a
 * CVPixelBuffer from the output's own pool (IOSurface-backed, as a Mac's
 * are), turned into the pixel format the output asks for, and sent to the
 * output's delegate on its queue in a CMSampleBuffer timed by the host
 * clock. While a delegate still has the last picture, a new one is
 * dropped unless the output keeps late pictures
 * (alwaysDiscardsLateVideoFrames NO).
 *
 * The session's preset picks the device's format when an input is added
 * or the preset changes; an app that sets the device's active format
 * makes the preset AVCaptureSessionPresetInputPriority, as on a Mac. A
 * change while running restarts the camera with it, after
 * commitConfiguration when it was made inside a configuration.
 *
 * Starting asks the user about the camera, as requestAccessForMediaType:
 * does, when they haven't been asked; a camera they said no to, or one
 * that can't be opened, posts AVCaptureSessionRuntimeErrorNotification. A
 * camera that goes away while running is tried again every second, so it
 * is read again once it is plugged back in.
 *
 * Colours: the camera's Y'CbCr (Rec. 601, video range) turns into BGRA and
 * back with Rec. 601's integer coefficients; 4:2:0 from 4:2:2 takes the
 * even rows' colour. */
#import "AVCaptureInternal.h"
#import "ACapture.h"
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

AVCaptureSessionPreset const AVCaptureSessionPresetPhoto = @"AVCaptureSessionPresetPhoto";
AVCaptureSessionPreset const AVCaptureSessionPresetHigh = @"AVCaptureSessionPresetHigh";
AVCaptureSessionPreset const AVCaptureSessionPresetMedium = @"AVCaptureSessionPresetMedium";
AVCaptureSessionPreset const AVCaptureSessionPresetLow = @"AVCaptureSessionPresetLow";
AVCaptureSessionPreset const AVCaptureSessionPreset320x240 = @"AVCaptureSessionPreset320x240";
AVCaptureSessionPreset const AVCaptureSessionPreset352x288 = @"AVCaptureSessionPreset352x288";
AVCaptureSessionPreset const AVCaptureSessionPreset640x480 = @"AVCaptureSessionPreset640x480";
AVCaptureSessionPreset const AVCaptureSessionPreset960x540 = @"AVCaptureSessionPreset960x540";
AVCaptureSessionPreset const AVCaptureSessionPreset1280x720 = @"AVCaptureSessionPreset1280x720";
AVCaptureSessionPreset const AVCaptureSessionPreset1920x1080 = @"AVCaptureSessionPreset1920x1080";
AVCaptureSessionPreset const AVCaptureSessionPreset3840x2160 = @"AVCaptureSessionPreset3840x2160";
AVCaptureSessionPreset const AVCaptureSessionPresetiFrame960x540 = @"AVCaptureSessionPresetiFrame960x540";
AVCaptureSessionPreset const AVCaptureSessionPresetiFrame1280x720 = @"AVCaptureSessionPresetiFrame1280x720";
AVCaptureSessionPreset const AVCaptureSessionPresetInputPriority = @"AVCaptureSessionPresetInputPriority";

NSNotificationName const AVCaptureSessionRuntimeErrorNotification = @"AVCaptureSessionRuntimeErrorNotification";
NSNotificationName const AVCaptureSessionDidStartRunningNotification = @"AVCaptureSessionDidStartRunningNotification";
NSNotificationName const AVCaptureSessionDidStopRunningNotification = @"AVCaptureSessionDidStopRunningNotification";
NSNotificationName const AVCaptureSessionWasInterruptedNotification = @"AVCaptureSessionWasInterruptedNotification";
NSNotificationName const AVCaptureSessionInterruptionEndedNotification =
    @"AVCaptureSessionInterruptionEndedNotification";
NSString *const AVCaptureSessionErrorKey = @"AVCaptureSessionErrorKey";
NSString *const AVFoundationErrorDomain = @"AVFoundationErrorDomain";

static NSError *av_error(AVError code, NSString *what)
{
    return [NSError errorWithDomain:AVFoundationErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : what}];
}

/* ---- pixels ------------------------------------------------------------------------------------ */

static inline uint8_t clamp8(int v) { return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v); }

/* One row of a camera's Y'CbCr picture: Y at y[x * ys], Cb and Cr at u and
 * v [(x / 2) * us]. */
struct yuv_row {
    const uint8_t *y, *u, *v;
    int ys, us;
};

struct picture {
    uint32_t fourcc; /* the camera's, or 'BGRA' once a JPEG is read */
    int w, h, stride;
    const uint8_t *p;
};

#define PICTURE_BGRA 0x41524742u

static struct yuv_row row_of(const struct picture *s, int y)
{
    struct yuv_row r = {0};
    const uint8_t *row = s->p + (size_t)y * s->stride;
    switch (s->fourcc) {
    case FERRY_CAMERA_YUYV: r = (struct yuv_row){row, row + 1, row + 3, 2, 4}; break;
    case FERRY_CAMERA_UYVY: r = (struct yuv_row){row + 1, row, row + 2, 2, 4}; break;
    case FERRY_CAMERA_NV12: {
        const uint8_t *uv = s->p + (size_t)s->stride * s->h + (size_t)(y / 2) * s->stride;
        r = (struct yuv_row){row, uv, uv + 1, 1, 2};
        break;
    }
    case FERRY_CAMERA_I420: {
        int cs = s->stride / 2;
        const uint8_t *u = s->p + (size_t)s->stride * s->h, *v = u + (size_t)cs * ((s->h + 1) / 2);
        r = (struct yuv_row){row, u + (size_t)(y / 2) * cs, v + (size_t)(y / 2) * cs, 1, 1};
        break;
    }
    }
    return r;
}

static void yuv_to_bgra(struct yuv_row r, int w, uint8_t *out)
{
    for (int x = 0; x < w; x++) {
        int c = 298 * (r.y[x * r.ys] - 16), d = r.u[(x / 2) * r.us] - 128, e = r.v[(x / 2) * r.us] - 128;
        out[0] = clamp8((c + 516 * d + 128) >> 8);
        out[1] = clamp8((c - 100 * d - 208 * e + 128) >> 8);
        out[2] = clamp8((c + 409 * e + 128) >> 8);
        out[3] = 255;
        out += 4;
    }
}

static inline void bgra_to_yuv(const uint8_t *p, uint8_t *y, uint8_t *u, uint8_t *v)
{
    int b = p[0], g = p[1], r = p[2];
    *y = clamp8(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
    if (u)
        *u = clamp8(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
    if (v)
        *v = clamp8(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
}

static BOOL is_packed_422(OSType f) { return f == kCVPixelFormatType_422YpCbCr8_yuvs || f == kCVPixelFormatType_422YpCbCr8; }
static BOOL is_420(OSType f)
{
    return f == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || f == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
}

/* A camera's picture into a pixel buffer of one of the formats the outputs offer. */
static void convert(const struct picture *s, CVPixelBufferRef pb)
{
    OSType to = CVPixelBufferGetPixelFormatType(pb);
    int w = (int)CVPixelBufferGetWidth(pb), h = (int)CVPixelBufferGetHeight(pb);
    if (w > s->w)
        w = s->w;
    if (h > s->h)
        h = s->h;
    CVPixelBufferLockBaseAddress(pb, 0);
    BOOL bgra_in = s->fourcc == PICTURE_BGRA;
    if (to == kCVPixelFormatType_32BGRA) {
        uint8_t *base = CVPixelBufferGetBaseAddress(pb);
        size_t stride = CVPixelBufferGetBytesPerRow(pb);
        for (int y = 0; y < h; y++) {
            if (bgra_in)
                memcpy(base + (size_t)y * stride, s->p + (size_t)y * s->stride, (size_t)w * 4);
            else
                yuv_to_bgra(row_of(s, y), w, base + (size_t)y * stride);
        }
    } else if (is_packed_422(to)) {
        uint8_t *base = CVPixelBufferGetBaseAddress(pb);
        size_t stride = CVPixelBufferGetBytesPerRow(pb);
        BOOL yuvs = to == kCVPixelFormatType_422YpCbCr8_yuvs;
        uint32_t same = yuvs ? FERRY_CAMERA_YUYV : FERRY_CAMERA_UYVY;
        for (int y = 0; y < h; y++) {
            uint8_t *o = base + (size_t)y * stride;
            if (s->fourcc == same) {
                memcpy(o, s->p + (size_t)y * s->stride, (size_t)w * 2);
                continue;
            }
            for (int x = 0; x + 1 < w; x += 2, o += 4) {
                uint8_t y0, y1, cb, cr;
                if (bgra_in) {
                    const uint8_t *p = s->p + (size_t)y * s->stride + (size_t)x * 4;
                    bgra_to_yuv(p, &y0, &cb, &cr);
                    bgra_to_yuv(p + 4, &y1, NULL, NULL);
                } else {
                    struct yuv_row r = row_of(s, y);
                    y0 = r.y[x * r.ys], y1 = r.y[(x + 1) * r.ys];
                    cb = r.u[(x / 2) * r.us], cr = r.v[(x / 2) * r.us];
                }
                if (yuvs)
                    o[0] = y0, o[1] = cb, o[2] = y1, o[3] = cr;
                else
                    o[0] = cb, o[1] = y0, o[2] = cr, o[3] = y1;
            }
        }
    } else if (is_420(to)) {
        uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uvp = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
        for (int y = 0; y < h; y++) {
            uint8_t *yo = yp + (size_t)y * ys, *uvo = y % 2 ? NULL : uvp + (size_t)(y / 2) * uvs;
            if (bgra_in) {
                const uint8_t *p = s->p + (size_t)y * s->stride;
                for (int x = 0; x < w; x++)
                    bgra_to_yuv(p + (size_t)x * 4, &yo[x], uvo && !(x % 2) ? &uvo[x] : NULL,
                                uvo && !(x % 2) ? &uvo[x + 1] : NULL);
                continue;
            }
            struct yuv_row r = row_of(s, y);
            if (r.ys == 1)
                memcpy(yo, r.y, (size_t)w);
            else
                for (int x = 0; x < w; x++)
                    yo[x] = r.y[x * r.ys];
            if (uvo) {
                if (s->fourcc == FERRY_CAMERA_NV12)
                    memcpy(uvo, r.u, (size_t)(w / 2) * 2);
                else
                    for (int x = 0; x < w / 2; x++)
                        uvo[x * 2] = r.u[x * r.us], uvo[x * 2 + 1] = r.v[x * r.us];
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
}

static NSArray<NSNumber *> *offered_formats(void)
{
    return @[
        @(kCVPixelFormatType_422YpCbCr8), @(kCVPixelFormatType_422YpCbCr8_yuvs),
        @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange), @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        @(kCVPixelFormatType_32BGRA)
    ];
}

/* ---- inputs, connections and outputs ----------------------------------------------------------- */

@implementation AVCaptureInputPort {
    @public
    AVCaptureDevice *_device; /* not retained: the input it belongs to holds it */
    BOOL _enabled;
}
- (AVMediaType)mediaType { return AVMediaTypeVideo; }
- (CMFormatDescriptionRef)formatDescription { return _device.activeFormat.formatDescription; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; }
@end

@implementation AVCaptureInput
- (NSArray<AVCaptureInputPort *> *)ports { return @[]; }
@end

@implementation AVCaptureDeviceInput {
    AVCaptureDevice *_device;
    AVCaptureInputPort *_port;
}
+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError
{
    return [[[self alloc] initWithDevice:device error:outError] autorelease];
}
- (instancetype)initWithDevice:(AVCaptureDevice *)device error:(NSError **)outError
{
    if (!device || ![device hasMediaType:AVMediaTypeVideo] || !device.connected) {
        if (outError)
            *outError = av_error(AVErrorDeviceNotConnected, @"Cannot use this camera");
        [self release];
        return nil;
    }
    if (!(self = [super init]))
        return nil;
    _device = [device retain];
    _port = [[AVCaptureInputPort alloc] init];
    _port->_device = device;
    _port->_enabled = YES;
    return self;
}
- (void)dealloc
{
    [_port release];
    [_device release];
    [super dealloc];
}
- (AVCaptureDevice *)device { return _device; }
- (NSArray<AVCaptureInputPort *> *)ports { return @[ _port ]; }
@end

@implementation AVCaptureConnection {
    @public
    AVCaptureOutput *_output; /* not retained: the output holds the connection */
    NSArray *_ports;
    BOOL _enabled, _active, _mirrored, _autoMirror;
    CMTime _minDuration, _maxDuration;
}
- (instancetype)_initWithOutput:(AVCaptureOutput *)output
{
    if ((self = [super init])) {
        _output = output;
        _ports = [@[] retain];
        _enabled = YES;
        _autoMirror = YES;
        _minDuration = _maxDuration = kCMTimeInvalid;
    }
    return self;
}
- (void)dealloc
{
    [_ports release];
    [super dealloc];
}
- (NSArray<AVCaptureInputPort *> *)inputPorts { return _ports; }
- (AVCaptureOutput *)output { return _output; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; }
- (BOOL)isActive { return _active && _enabled && [_ports count]; }
- (BOOL)isVideoMirroringSupported { return NO; }
- (BOOL)isVideoMirrored { return _mirrored; }
- (void)setVideoMirrored:(BOOL)mirrored { _mirrored = mirrored; }
- (BOOL)automaticallyAdjustsVideoMirroring { return _autoMirror; }
- (void)setAutomaticallyAdjustsVideoMirroring:(BOOL)a { _autoMirror = a; }
- (CMTime)videoMinFrameDuration { return _minDuration; }
- (void)setVideoMinFrameDuration:(CMTime)t { _minDuration = t; }
- (CMTime)videoMaxFrameDuration { return _maxDuration; }
- (void)setVideoMaxFrameDuration:(CMTime)t { _maxDuration = t; }
@end

@implementation AVCaptureOutput {
    @public
    AVCaptureConnection *_connection;
    AVCaptureSession *_session; /* not retained */
}
- (instancetype)init
{
    if ((self = [super init]))
        _connection = [[AVCaptureConnection alloc] _initWithOutput:self];
    return self;
}
- (void)dealloc
{
    [_connection release];
    [super dealloc];
}
- (NSArray<AVCaptureConnection *> *)connections { return [_connection->_ports count] ? @[ _connection ] : @[]; }
- (AVCaptureConnection *)connectionWithMediaType:(AVMediaType)mediaType
{
    return [mediaType isEqualToString:AVMediaTypeVideo] && [_connection->_ports count] && [self _takesVideo]
               ? _connection
               : nil;
}
- (BOOL)_takesVideo { return NO; }
@end

@implementation AVCaptureVideoDataOutput {
    @public
    NSDictionary *_settings;
    id _delegate; /* not retained, as a Mac's isn't */
    dispatch_queue_t _queue;
    BOOL _discardLate;
    atomic_int _inFlight;
    atomic_int _generation; /* moved on when the session stops: pictures queued before it aren't handed over */
    CVPixelBufferPoolRef _pool;
    OSType _poolFormat;
    int _poolW, _poolH;
    pthread_mutex_t _lock;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _discardLate = YES;
        pthread_mutex_init(&_lock, NULL);
    }
    return self;
}
- (void)dealloc
{
    [_settings release];
    if (_queue)
        dispatch_release(_queue);
    if (_pool)
        CVPixelBufferPoolRelease(_pool);
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}
- (BOOL)_takesVideo { return YES; }

/* the device of the session's input, if it has one */
- (AVCaptureDevice *)_device
{
    for (AVCaptureInput *i in _session.inputs)
        if ([i isKindOfClass:[AVCaptureDeviceInput class]])
            return [(AVCaptureDeviceInput *)i device];
    return nil;
}

/* the pixel format sent: the one asked for if offered, else the camera's own */
- (OSType)_pixelFormatFor:(uint32_t)fourcc
{
    pthread_mutex_lock(&_lock);
    id asked = _settings[(id)kCVPixelBufferPixelFormatTypeKey];
    pthread_mutex_unlock(&_lock);
    if ([asked isKindOfClass:[NSArray class]])
        asked = [asked firstObject];
    if ([asked isKindOfClass:[NSNumber class]] && [offered_formats() containsObject:asked])
        return (OSType)[asked unsignedIntValue];
    return AVCameraNativePixelFormat(fourcc);
}

- (NSDictionary<NSString *, id> *)videoSettings
{
    AVCaptureDevice *d = [self _device];
    const struct ferry_camera_mode *m = d.activeFormat ? [d.activeFormat _mode] : NULL;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    pthread_mutex_lock(&_lock);
    if (_settings)
        [out addEntriesFromDictionary:_settings];
    pthread_mutex_unlock(&_lock);
    out[(id)kCVPixelBufferPixelFormatTypeKey] =
        @([self _pixelFormatFor:m ? m->fourcc : FERRY_CAMERA_UYVY]);
    if (m) {
        out[(id)kCVPixelBufferWidthKey] = @(m->width);
        out[(id)kCVPixelBufferHeightKey] = @(m->height);
    }
    return out;
}
- (void)setVideoSettings:(NSDictionary<NSString *, id> *)settings
{
    id asked = settings[(id)kCVPixelBufferPixelFormatTypeKey];
    if ([asked isKindOfClass:[NSNumber class]] && ![offered_formats() containsObject:asked])
        [NSException raise:NSInvalidArgumentException format:@"pixel format %@ isn't offered", asked];
    NSDictionary *copy = [settings copy];
    pthread_mutex_lock(&_lock);
    [_settings release];
    _settings = copy;
    pthread_mutex_unlock(&_lock);
}
- (NSArray<NSNumber *> *)availableVideoCVPixelFormatTypes { return offered_formats(); }
- (BOOL)alwaysDiscardsLateVideoFrames { return _discardLate; }
- (void)setAlwaysDiscardsLateVideoFrames:(BOOL)d { _discardLate = d; }
- (id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate { return _delegate; }
- (dispatch_queue_t)sampleBufferCallbackQueue { return _queue; }
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)queue
{
    if (delegate && !queue)
        [NSException raise:NSInvalidArgumentException format:@"a sample buffer delegate needs a queue"];
    pthread_mutex_lock(&_lock);
    if (queue)
        dispatch_retain(queue);
    if (_queue)
        dispatch_release(_queue);
    _queue = queue;
    _delegate = delegate;
    pthread_mutex_unlock(&_lock);
}

/* One picture, on the session's capture thread. */
- (void)_deliver:(const struct picture *)pic time:(uint64_t)ns duration:(CMTime)duration
{
    pthread_mutex_lock(&_lock);
    id delegate = _delegate;
    dispatch_queue_t queue = _queue;
    if (queue)
        dispatch_retain(queue);
    pthread_mutex_unlock(&_lock);
    if (!delegate || !queue || !_connection->_enabled ||
        ![delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        if (queue)
            dispatch_release(queue);
        return;
    }
    if (_discardLate && atomic_load(&_inFlight) > 0) { /* the delegate still has the last one */
        dispatch_release(queue);
        return;
    }
    OSType format = [self _pixelFormatFor:pic->fourcc == PICTURE_BGRA ? FERRY_CAMERA_MJPEG : pic->fourcc];
    if (!_pool || _poolFormat != format || _poolW != pic->w || _poolH != pic->h) {
        if (_pool)
            CVPixelBufferPoolRelease(_pool);
        NSDictionary *attrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey : @(format),
            (id)kCVPixelBufferWidthKey : @(pic->w),
            (id)kCVPixelBufferHeightKey : @(pic->h),
            (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        };
        _pool = NULL;
        CVPixelBufferPoolCreate(NULL, NULL, (CFDictionaryRef)attrs, &_pool);
        _poolFormat = format, _poolW = pic->w, _poolH = pic->h;
    }
    CVPixelBufferRef pb = NULL;
    if (!_pool || CVPixelBufferPoolCreatePixelBuffer(NULL, _pool, &pb) != kCVReturnSuccess || !pb) {
        dispatch_release(queue);
        return;
    }
    convert(pic, pb);
    if (format != kCVPixelFormatType_32BGRA)
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4,
                              kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
                          kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2,
                          kCVAttachmentMode_ShouldPropagate);
    CMVideoFormatDescriptionRef desc = NULL;
    CMSampleBufferRef sample = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(NULL, pb, &desc) == noErr) {
        CMSampleTimingInfo timing = {duration, CMClockMakeHostTimeFromSystemUnits(ns), kCMTimeInvalid};
        CMSampleBufferCreateReadyWithImageBuffer(NULL, pb, desc, &timing, &sample);
        CFRelease(desc);
    }
    CVPixelBufferRelease(pb);
    if (!sample) {
        dispatch_release(queue);
        return;
    }
    atomic_fetch_add(&_inFlight, 1);
    [self retain];
    AVCaptureConnection *connection = _connection;
    int generation = atomic_load(&_generation);
    dispatch_async(queue, ^{
        @autoreleasepool {
            id d = self->_delegate;
            if (d && atomic_load(&self->_generation) == generation)
                [d captureOutput:self didOutputSampleBuffer:sample fromConnection:connection];
        }
        CFRelease(sample);
        atomic_fetch_sub(&self->_inFlight, 1);
        [self release];
    });
    dispatch_release(queue);
}
@end

@implementation AVCaptureAudioDataOutput {
    NSDictionary *_settings;
    id _delegate;
    dispatch_queue_t _queue;
}
- (void)dealloc
{
    [_settings release];
    if (_queue)
        dispatch_release(_queue);
    [super dealloc];
}
- (NSDictionary<NSString *, id> *)audioSettings { return _settings ?: @{}; }
- (void)setAudioSettings:(NSDictionary<NSString *, id> *)s
{
    NSDictionary *copy = [s copy];
    [_settings release];
    _settings = copy;
}
- (id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate { return _delegate; }
- (dispatch_queue_t)sampleBufferCallbackQueue { return _queue; }
- (void)setSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)queue
{
    if (queue)
        dispatch_retain(queue);
    if (_queue)
        dispatch_release(_queue);
    _queue = queue;
    _delegate = delegate;
}
@end

/* ---- the session ------------------------------------------------------------------------------- */

@implementation AVCaptureSession {
    pthread_mutex_t _lock;
    NSMutableArray *_inputs, *_outputs;
    NSString *_preset;
    int _configuring;
    BOOL _changed;   /* a change made inside a configuration, for its commit */
    BOOL _running;
    atomic_int _stop, _restart;
    pthread_t _thread;
    BOOL _haveThread;
}

- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_lock, NULL);
        _inputs = [[NSMutableArray alloc] init];
        _outputs = [[NSMutableArray alloc] init];
        _preset = [AVCaptureSessionPresetHigh copy];
    }
    return self;
}

- (void)dealloc
{
    [self stopRunning];
    for (AVCaptureDeviceInput *i in _inputs)
        if ([i isKindOfClass:[AVCaptureDeviceInput class]])
            [i.device _setSession:nil];
    for (AVCaptureOutput *o in _outputs)
        o->_session = nil;
    [_inputs release];
    [_outputs release];
    [_preset release];
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}

- (NSArray<AVCaptureInput *> *)inputs
{
    pthread_mutex_lock(&_lock);
    NSArray *a = [[_inputs copy] autorelease];
    pthread_mutex_unlock(&_lock);
    return a;
}
- (NSArray<AVCaptureOutput *> *)outputs
{
    pthread_mutex_lock(&_lock);
    NSArray *a = [[_outputs copy] autorelease];
    pthread_mutex_unlock(&_lock);
    return a;
}
- (NSArray<AVCaptureConnection *> *)connections
{
    NSMutableArray *c = [NSMutableArray array];
    for (AVCaptureOutput *o in self.outputs)
        [c addObjectsFromArray:o.connections];
    return c;
}

- (AVCaptureDevice *)_device
{
    for (AVCaptureInput *i in self.inputs)
        if ([i isKindOfClass:[AVCaptureDeviceInput class]])
            return [(AVCaptureDeviceInput *)i device];
    return nil;
}

/* restart the camera when running, now or at the configuration's commit */
- (void)_changed
{
    pthread_mutex_lock(&_lock);
    if (_configuring)
        _changed = YES;
    else if (_running)
        atomic_store(&_restart, 1);
    pthread_mutex_unlock(&_lock);
}

- (void)_deviceChanged:(AVCaptureDevice *)device
{
    pthread_mutex_lock(&_lock);
    if (![_preset isEqualToString:AVCaptureSessionPresetInputPriority]) {
        id wasPreset = _preset;
        _preset = [AVCaptureSessionPresetInputPriority copy];
        [wasPreset release];
    }
    pthread_mutex_unlock(&_lock);
    [self _changed];
}

- (AVCaptureSessionPreset)sessionPreset
{
    pthread_mutex_lock(&_lock);
    NSString *p = [[_preset retain] autorelease];
    pthread_mutex_unlock(&_lock);
    return p;
}
- (BOOL)canSetSessionPreset:(AVCaptureSessionPreset)preset
{
    AVCaptureDevice *d = [self _device];
    if (!d) /* with no camera yet, any preset this session knows */
        return [preset isEqualToString:AVCaptureSessionPresetInputPriority] ||
               [d _formatForPreset:preset] != nil || [preset hasPrefix:@"AVCaptureSessionPreset"];
    return [d supportsAVCaptureSessionPreset:preset];
}
- (void)setSessionPreset:(AVCaptureSessionPreset)preset
{
    if (![self canSetSessionPreset:preset]) {
        [NSException raise:NSInvalidArgumentException format:@"can't set session preset %@", preset];
        return;
    }
    pthread_mutex_lock(&_lock);
    NSString *copy = [preset copy];
    [_preset release];
    _preset = copy;
    pthread_mutex_unlock(&_lock);
    AVCaptureDevice *d = [self _device];
    AVCaptureDeviceFormat *f = [d _formatForPreset:preset];
    if (f)
        [d _applyFormat:f];
    [self _changed];
}

- (BOOL)canAddInput:(AVCaptureInput *)input
{
    if (![input isKindOfClass:[AVCaptureDeviceInput class]])
        return NO;
    pthread_mutex_lock(&_lock);
    BOOL ok = ![_inputs count]; /* one camera to a session */
    pthread_mutex_unlock(&_lock);
    return ok;
}
- (void)addInput:(AVCaptureInput *)input
{
    if (![self canAddInput:input]) {
        [NSException raise:NSInvalidArgumentException format:@"can't add %@ to this session", input];
        return;
    }
    AVCaptureDevice *d = [(AVCaptureDeviceInput *)input device];
    pthread_mutex_lock(&_lock);
    [_inputs addObject:input];
    NSString *preset = [[_preset retain] autorelease];
    for (AVCaptureOutput *o in _outputs) {
        [o->_connection->_ports release];
        o->_connection->_ports = [input.ports copy];
    }
    pthread_mutex_unlock(&_lock);
    [d _setSession:self];
    AVCaptureDeviceFormat *f = [d _formatForPreset:preset];
    if (f)
        [d _applyFormat:f];
    [self _changed];
}
- (void)removeInput:(AVCaptureInput *)input
{
    if (!input)
        return;
    pthread_mutex_lock(&_lock);
    BOOL had = [_inputs containsObject:input];
    if (had) {
        [[input retain] autorelease];
        [_inputs removeObject:input];
        for (AVCaptureOutput *o in _outputs) {
            [o->_connection->_ports release];
            o->_connection->_ports = [@[] retain];
        }
    }
    pthread_mutex_unlock(&_lock);
    if (had && [input isKindOfClass:[AVCaptureDeviceInput class]])
        [[(AVCaptureDeviceInput *)input device] _setSession:nil];
    if (had)
        [self _changed];
}

- (BOOL)canAddOutput:(AVCaptureOutput *)output
{
    if (![output isKindOfClass:[AVCaptureVideoDataOutput class]] && ![output isKindOfClass:[AVCaptureAudioDataOutput class]])
        return NO;
    pthread_mutex_lock(&_lock);
    BOOL ok = ![_outputs containsObject:output] && !output->_session;
    pthread_mutex_unlock(&_lock);
    return ok;
}
- (void)addOutput:(AVCaptureOutput *)output
{
    if (![self canAddOutput:output]) {
        [NSException raise:NSInvalidArgumentException format:@"can't add %@ to this session", output];
        return;
    }
    pthread_mutex_lock(&_lock);
    [_outputs addObject:output];
    output->_session = self;
    AVCaptureInput *input = [_inputs firstObject];
    if (input && [output _takesVideo]) {
        [output->_connection->_ports release];
        output->_connection->_ports = [input.ports copy];
    }
    output->_connection->_active = _running;
    pthread_mutex_unlock(&_lock);
}
- (void)removeOutput:(AVCaptureOutput *)output
{
    pthread_mutex_lock(&_lock);
    if ([_outputs containsObject:output]) {
        output->_session = nil;
        output->_connection->_active = NO;
        [_outputs removeObject:output];
    }
    pthread_mutex_unlock(&_lock);
}

- (void)beginConfiguration
{
    pthread_mutex_lock(&_lock);
    _configuring++;
    pthread_mutex_unlock(&_lock);
}
- (void)commitConfiguration
{
    pthread_mutex_lock(&_lock);
    if (_configuring > 0 && --_configuring == 0 && _changed) {
        _changed = NO;
        if (_running)
            atomic_store(&_restart, 1);
    }
    pthread_mutex_unlock(&_lock);
}

- (BOOL)isRunning
{
    pthread_mutex_lock(&_lock);
    BOOL r = _running;
    pthread_mutex_unlock(&_lock);
    return r;
}
- (BOOL)isInterrupted { return NO; }

- (void)_postError:(NSError *)error
{
    /* the capture thread says nothing once the session is stopping, perhaps
     * because the app let it go */
    if (atomic_load(&_stop) && pthread_equal(pthread_self(), _thread))
        return;
    [self retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AVCaptureSessionRuntimeErrorNotification
                                                            object:self
                                                          userInfo:@{AVCaptureSessionErrorKey : error}];
        [self release];
    });
}

static void *capture_main(void *arg);

- (void)startRunning
{
    if (self.running)
        return;
    if (ACaptureStoredAnswerOfKind(@"camera") < 0)
        ACaptureAskKind(@"camera", YES);
    if (ACaptureStoredAnswerOfKind(@"camera") != 1) {
        ACaptureSayOnce("the camera isn't allowed for this app, so its capture session gets no pictures "
                        "(Dials, Privacy & Security, Camera can allow it)");
        [self _postError:av_error(AVErrorApplicationIsNotAuthorizedToUseDevice,
                                  @"This app isn't allowed to use the camera")];
        return;
    }
    if (!AVCameraCall("start")) {
        [self _postError:av_error(AVErrorUnknown, @"This Ferry can't read cameras")];
        return;
    }
    pthread_mutex_lock(&_lock);
    _running = YES;
    atomic_store(&_stop, 0);
    atomic_store(&_restart, 0);
    for (AVCaptureOutput *o in _outputs)
        o->_connection->_active = YES;
    /* the thread doesn't keep the session: as on a Mac, a running session
     * that its app lets go of stops (dealloc joins the thread), so an app
     * that frees its delegate's state with the session, as OBS's legacy
     * camera source does, isn't handed pictures after (freemac 1.259) */
    _haveThread = pthread_create(&_thread, NULL, capture_main, self) == 0;
    if (!_haveThread)
        _running = NO;
    BOOL started = _haveThread;
    pthread_mutex_unlock(&_lock);
    if (started)
        [[NSNotificationCenter defaultCenter] postNotificationName:AVCaptureSessionDidStartRunningNotification
                                                            object:self];
}

- (void)stopRunning
{
    pthread_mutex_lock(&_lock);
    BOOL had = _haveThread;
    pthread_t t = _thread;
    _haveThread = NO;
    _running = NO;
    for (AVCaptureOutput *o in _outputs)
        o->_connection->_active = NO;
    atomic_store(&_stop, 1);
    pthread_mutex_unlock(&_lock);
    if (!had)
        return;
    if (pthread_equal(t, pthread_self()))
        pthread_detach(t);
    else
        pthread_join(t, NULL);
    /* pictures already on their way to a delegate's queue aren't handed over */
    pthread_mutex_lock(&_lock);
    for (AVCaptureOutput *o in _outputs)
        if ([o isKindOfClass:[AVCaptureVideoDataOutput class]])
            atomic_fetch_add(&((AVCaptureVideoDataOutput *)o)->_generation, 1);
    pthread_mutex_unlock(&_lock);
    [[NSNotificationCenter defaultCenter] postNotificationName:AVCaptureSessionDidStopRunningNotification
                                                        object:self];
}

/* the camera to read now, as the device is set */
struct plan {
    char path[64];
    uint32_t fourcc;
    int32_t width, height;
    struct ferry_camera_rate rate;
};

- (BOOL)_plan:(struct plan *)p
{
    AVCaptureDevice *d = [self _device];
    AVCaptureDeviceFormat *f = d.activeFormat;
    if (!d || !f || !d.connected || ![[d _path] length])
        return NO;
    const struct ferry_camera_mode *m = [f _mode];
    snprintf(p->path, sizeof p->path, "%s", [[d _path] UTF8String]);
    p->fourcc = m->fourcc;
    p->width = m->width;
    p->height = m->height;
    CMTime t = d.activeVideoMinFrameDuration;
    p->rate = CMTIME_IS_NUMERIC(t) && t.value > 0 ? (struct ferry_camera_rate){(uint32_t)t.value, (uint32_t)t.timescale}
                                                  : (struct ferry_camera_rate){1, 30};
    return YES;
}

- (void)_captureLoop
{
    ferry_camera_start_fn start = (ferry_camera_start_fn)AVCameraCall("start");
    ferry_camera_next_fn next = (ferry_camera_next_fn)AVCameraCall("next");
    ferry_camera_stop_fn stop = (ferry_camera_stop_fn)AVCameraCall("stop");
    ferry_camera_release_fn release = (ferry_camera_release_fn)AVCameraCall("release");
    ferry_camera_jpeg_fn jpeg = (ferry_camera_jpeg_fn)AVCameraCall("jpeg");
    void *camera = NULL;
    struct ferry_camera_started got = {0};
    uint8_t *decoded = NULL;
    size_t decoded_size = 0;
    BOOL said_lost = NO;
    while (!atomic_load(&_stop)) {
        @autoreleasepool {
            if (atomic_exchange(&_restart, 0) && camera) {
                stop(camera);
                camera = NULL;
            }
            if (!camera) {
                struct plan p;
                if ([self _plan:&p])
                    camera = start(p.path, p.fourcc, p.width, p.height, p.rate, &got);
                if (!camera) {
                    if (!said_lost) {
                        said_lost = YES;
                        [self _postError:av_error(AVErrorDeviceNotConnected, @"The camera couldn't be opened")];
                    }
                    for (int i = 0; i < 10 && !atomic_load(&_stop) && !atomic_load(&_restart); i++) {
                        struct timespec t = {0, 100000000};
                        nanosleep(&t, NULL);
                    }
                    continue;
                }
                said_lost = NO;
            }
            struct ferry_camera_frame frame;
            int r = next(camera, 200, &frame);
            if (r < 0) { /* it went away: try again in a moment */
                stop(camera);
                camera = NULL;
                continue;
            }
            if (r == 0)
                continue;
            struct picture pic = {got.fourcc, got.width, got.height, got.stride, frame.data};
            if (got.fourcc == FERRY_CAMERA_MJPEG) {
                size_t need = (size_t)got.width * got.height * 4;
                if (need > decoded_size) {
                    free(decoded);
                    decoded = malloc(need);
                    decoded_size = decoded ? need : 0;
                }
                if (!decoded || !jpeg || jpeg(frame.data, frame.size, decoded, got.width, got.height, got.width * 4)) {
                    release(camera);
                    continue; /* a picture that couldn't be read */
                }
                release(camera);
                pic = (struct picture){PICTURE_BGRA, got.width, got.height, got.width * 4, decoded};
            } else {
                size_t need = got.fourcc == FERRY_CAMERA_YUYV || got.fourcc == FERRY_CAMERA_UYVY
                                  ? (size_t)got.stride * got.height
                                  : (size_t)got.stride * got.height * 3 / 2;
                if (frame.size < need) { /* a short picture */
                    release(camera);
                    continue;
                }
            }
            CMTime duration = CMTimeMake((int64_t)got.rate.num, (int32_t)(got.rate.den ? got.rate.den : 30));
            for (AVCaptureOutput *o in self.outputs)
                if ([o isKindOfClass:[AVCaptureVideoDataOutput class]])
                    [(AVCaptureVideoDataOutput *)o _deliver:&pic time:frame.time_ns duration:duration];
            if (got.fourcc != FERRY_CAMERA_MJPEG)
                release(camera);
        }
    }
    if (camera)
        stop(camera);
    free(decoded);
}

static void *capture_main(void *arg)
{
    AVCaptureSession *s = arg;
    pthread_setname_np("com.apple.avfoundation.capture");
    [s _captureLoop];
    return NULL;
}
@end
