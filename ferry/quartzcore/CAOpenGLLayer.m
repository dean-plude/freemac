/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAOpenGLLayer (freemac 1.235, Ferry 0.59.0),
 * written from Apple's public Core Animation reference.
 *
 * The layer's context, from copyCGLContextForPixelFormat:, draws into a
 * drawable of the layer's size in pixels (its bounds times its contents
 * scale), with the viewport set to all of it. When the layer is displayed,
 * on whichever thread calls display (VLC's video output calls it from its
 * own), the context is locked and made current, drawInCGLContext: draws if
 * canDrawInCGLContext: says it may, and what it drew is read back
 * (glReadPixels) as an image that becomes the layer's contents, on the main
 * thread, which shows it as any layer's contents are shown. An
 * asynchronous layer is displayed at each refresh of the display, from a
 * timer on the main run loop. Built without ARC. */
#import "QInternal.h"
#include <OpenGL/OpenGL.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include "../opengl/FerryGL.h"

void glFlush(void);
void glViewport(GLint x, GLint y, GLsizei w, GLsizei h);

/* The timer's target, so the timer doesn't keep the layer. */
@interface QOpenGLTick : NSObject {
  @public
    CAOpenGLLayer *_layer; /* not retained */
}
@end

@interface CAOpenGLLayer () {
    pthread_mutex_t _glLock;     /* the context, the pixel format and the sizes below */
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _context;
    CGSize _size;                /* the bounds' size, kept for other threads */
    double _scale;
    BOOL _async;
    NSTimer *_timer;
    QOpenGLTick *_tick;
    CGColorSpaceRef _colorspace;
    BOOL _edr;
    NSUInteger _serial;          /* of the newest image, so an older one doesn't replace it */
    BOOL _ready;                 /* _glLock made */
}
@end

@implementation QOpenGLTick
- (void)tick:(NSTimer *)t
{
    if ([_layer isHidden])
        return;
    [_layer display];
}
@end

static void release_frame(void *info, const void *data, size_t size) { FerryGLFrameRelease(info); }

@implementation CAOpenGLLayer

- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_glLock, NULL);
        _ready = YES;
        _size = [self bounds].size;
        _scale = [self contentsScale];
        [self setNeedsDisplay];
    }
    return self;
}

- (instancetype)initWithLayer:(id)layer
{
    if ((self = [super initWithLayer:layer])) {
        pthread_mutex_init(&_glLock, NULL);
        _ready = YES;
        _size = [self bounds].size;
        _scale = [self contentsScale];
    }
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
    [_timer release];
    [_tick release];
    if (_context)
        [self releaseCGLContext:_context];
    if (_pixelFormat)
        [self releaseCGLPixelFormat:_pixelFormat];
    CGColorSpaceRelease(_colorspace);
    pthread_mutex_destroy(&_glLock);
    [super dealloc];
}

/* the sizes display needs, kept where another thread can read them */
- (void)_ferrySetValue:(id)value forKey:(NSString *)key
{
    [super _ferrySetValue:value forKey:key];
    if (_ready && ([key isEqualToString:@"bounds"] || [key isEqualToString:@"contentsScale"])) {
        CGSize size = [self bounds].size;
        double scale = [self contentsScale];
        pthread_mutex_lock(&_glLock);
        _size = size;
        _scale = scale;
        pthread_mutex_unlock(&_glLock);
    }
}

- (BOOL)isAsynchronous { return _async; }
- (void)setAsynchronous:(BOOL)flag
{
    if (!pthread_main_np()) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self setAsynchronous:flag];
        });
        return;
    }
    if (flag == _async)
        return;
    _async = flag;
    if (flag) {
        if (!_tick) {
            _tick = [[QOpenGLTick alloc] init];
            _tick->_layer = self;
        }
        _timer = [[NSTimer timerWithTimeInterval:1.0 / FerryGLRefreshRate() target:_tick selector:@selector(tick:)
                                        userInfo:nil
                                         repeats:YES] retain];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    } else {
        [_timer invalidate];
        [_timer release];
        _timer = nil;
    }
}

- (CGColorSpaceRef)colorspace { return _colorspace; }
- (void)setColorspace:(CGColorSpaceRef)cs
{
    CGColorSpaceRetain(cs);
    CGColorSpaceRelease(_colorspace);
    _colorspace = cs;
}
- (BOOL)wantsExtendedDynamicRangeContent { return _edr; }
- (void)setWantsExtendedDynamicRangeContent:(BOOL)flag { _edr = flag; }

/* ---- what a subclass overrides ---- */

- (BOOL)canDrawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
               forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts
{
    return YES;
}

- (void)drawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
            forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts
{
    glFlush();
}

- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask
{
    CGLPixelFormatAttribute attrs[] = {kCGLPFADisplayMask, (CGLPixelFormatAttribute)mask, kCGLPFAAccelerated,
                                       kCGLPFAColorSize, (CGLPixelFormatAttribute)24, kCGLPFAAlphaSize,
                                       (CGLPixelFormatAttribute)8, kCGLPFADepthSize, (CGLPixelFormatAttribute)16,
                                       (CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pf = NULL;
    GLint n = 0;
    CGLChoosePixelFormat(attrs, &pf, &n);
    return pf;
}
- (void)releaseCGLPixelFormat:(CGLPixelFormatObj)pf { CGLReleasePixelFormat(pf); }

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pf
{
    CGLContextObj ctx = NULL;
    CGLCreateContext(pf, NULL, &ctx);
    return ctx;
}
- (void)releaseCGLContext:(CGLContextObj)ctx { CGLReleaseContext(ctx); }

/* ---- displaying ---- */

- (void)_ferryShowImage:(CGImageRef)image serial:(NSUInteger)serial
{
    if (serial < _serial)
        return;
    _serial = serial;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self _ferrySetValue:(id)image forKey:@"contents"];
    [CATransaction commit];
}

- (void)display
{
    [self _ferryClearNeedsDisplay];
    static NSUInteger serials;
    pthread_mutex_lock(&_glLock);
    if (!_context) {
        if (!_pixelFormat)
            _pixelFormat = [self copyCGLPixelFormatForDisplayMask:0xffffffff];
        if (_pixelFormat)
            _context = [self copyCGLContextForPixelFormat:_pixelFormat];
        if (!_context) {
            BOOL format = _pixelFormat != NULL; /* without one, CGL has said why */
            pthread_mutex_unlock(&_glLock);
            if (format)
                QWarnOnce("CAOpenGLLayer without an OpenGL context");
            return;
        }
    }
    CGLContextObj ctx = CGLRetainContext(_context);
    CGLPixelFormatObj pf = CGLRetainPixelFormat(_pixelFormat);
    double scale = _scale > 0 ? _scale : 1;
    GLsizei w = (GLsizei)ceil(_size.width * scale), h = (GLsizei)ceil(_size.height * scale);
    BOOL opaque = [self isOpaque];
    NSUInteger serial = __atomic_add_fetch(&serials, 1, __ATOMIC_RELAXED);
    pthread_mutex_unlock(&_glLock);
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) {
        CGLReleasePixelFormat(pf);
        CGLReleaseContext(ctx);
        return;
    }

    FerryGLFrame *frame = NULL;
    CGLLockContext(ctx);
    CGLContextObj saved = CGLGetCurrentContext();
    CGLSetCurrentContext(ctx);
    FerryCGLSetDrawableSize(ctx, w, h);
    glViewport(0, 0, w, h);
    CVTimeStamp ts = {0};
    ts.videoTimeScale = 1000000000;
    ts.hostTime = mach_absolute_time();
    ts.videoTime = (int64_t)ts.hostTime;
    ts.rateScalar = 1;
    ts.videoRefreshPeriod = (int64_t)(1e9 / FerryGLRefreshRate());
    ts.flags = kCVTimeStampVideoHostTimeValid | kCVTimeStampVideoRefreshPeriodValid | kCVTimeStampRateScalarValid;
    CFTimeInterval t = CACurrentMediaTime();
    @autoreleasepool {
        if ([self canDrawInCGLContext:ctx pixelFormat:pf forLayerTime:t displayTime:&ts]) {
            [self drawInCGLContext:ctx pixelFormat:pf forLayerTime:t displayTime:&ts];
            /* the subclass may have made another context current */
            if (CGLGetCurrentContext() != ctx)
                CGLSetCurrentContext(ctx);
            frame = FerryCGLCaptureFrame(ctx, 1);
        }
    }
    CGLSetCurrentContext(saved);
    CGLUnlockContext(ctx);
    CGLReleasePixelFormat(pf);
    CGLReleaseContext(ctx);
    if (!frame)
        return;

    CGDataProviderRef provider =
        CGDataProviderCreateWithData(frame, frame->data, (size_t)frame->rowBytes * (size_t)frame->height, release_frame);
    CGColorSpaceRef cs = _colorspace ? CGColorSpaceRetain(_colorspace) : CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate((size_t)frame->width, (size_t)frame->height, 8, 32, (size_t)frame->rowBytes, cs,
                                     (opaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst) |
                                         kCGBitmapByteOrder32Little,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(provider);
    if (!image)
        return;
    if (pthread_main_np()) {
        [self _ferryShowImage:image serial:serial];
        CGImageRelease(image);
    } else {
        [self retain];
        dispatch_async(dispatch_get_main_queue(), ^{
          [self _ferryShowImage:image serial:serial];
          CGImageRelease(image);
          [self release];
        });
    }
}

@end

/* ---- the part of a layer that shows ---- */

@implementation CALayer (CALayerScrolling)

- (CGRect)visibleRect
{
    CGRect r = [self bounds];
    for (CALayer *l = [self superlayer]; l; l = [l superlayer]) {
        if (![l masksToBounds])
            continue;
        CGRect clip = [self convertRect:[l bounds] fromLayer:l];
        r = CGRectIntersection(r, clip);
    }
    return CGRectIsNull(r) ? CGRectZero : r;
}

/* Scrolling moves the bounds' origin of the nearest superlayer that clips. */
- (void)scrollPoint:(CGPoint)p
{
    for (CALayer *l = [self superlayer]; l; l = [l superlayer])
        if ([l masksToBounds]) {
            CGRect b = [l bounds];
            b.origin = [l convertPoint:p fromLayer:self];
            [l setBounds:b];
            return;
        }
}

- (void)scrollRectToVisible:(CGRect)r
{
    for (CALayer *l = [self superlayer]; l; l = [l superlayer])
        if ([l masksToBounds]) {
            CGRect want = [l convertRect:r fromLayer:self], b = [l bounds];
            if (CGRectGetMaxX(want) > CGRectGetMaxX(b))
                b.origin.x = CGRectGetMaxX(want) - b.size.width;
            if (CGRectGetMinX(want) < CGRectGetMinX(b))
                b.origin.x = CGRectGetMinX(want);
            if (CGRectGetMaxY(want) > CGRectGetMaxY(b))
                b.origin.y = CGRectGetMaxY(want) - b.size.height;
            if (CGRectGetMinY(want) < CGRectGetMinY(b))
                b.origin.y = CGRectGetMinY(want);
            [l setBounds:b];
            return;
        }
}

@end
