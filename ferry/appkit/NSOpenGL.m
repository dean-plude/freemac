/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSOpenGLPixelFormat, NSOpenGLContext and NSOpenGLView
 * (freemac 1.235, Ferry 0.59.0), written from Apple's public AppKit
 * reference.
 *
 * A context drawing into a view draws into a drawable of the view's size
 * (in backing pixels when the view wants the best resolution) that Ferry's
 * OpenGL keeps off screen; each flushBuffer reads it back, and the view
 * shows the newest frame over its own drawing whenever it is drawn. A
 * flush made outside the view's drawing, on any thread, has the view
 * drawn again on the main thread; for an NSOpenGLView that draw shows the
 * new frame without calling drawRect: again, as a Mac shows a GL surface
 * without asking the view. Built without ARC. */
#import "AInternal.h"
#import <AppKit/NSOpenGL.h>
#import <AppKit/NSOpenGLView.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <math.h>
#include "../opengl/FerryGL.h"

/* ---- pixel formats ---- */

@implementation NSOpenGLPixelFormat {
    CGLPixelFormatObj _pf;
}

- (instancetype)initWithAttributes:(const NSOpenGLPixelFormatAttribute *)attribs
{
    if (!(self = [super init]))
        return nil;
    size_t n = 0;
    while (attribs && attribs[n])
        n++;
    CGLPixelFormatAttribute *a = calloc(n + 1, sizeof *a);
    for (size_t i = 0; i < n; i++)
        a[i] = (CGLPixelFormatAttribute)attribs[i];
    GLint screens = 0;
    CGLChoosePixelFormat(a, &_pf, &screens);
    free(a);
    if (!_pf) {
        [self release];
        return nil;
    }
    return self;
}

- (instancetype)initWithCGLPixelFormatObj:(CGLPixelFormatObj)format
{
    if (!format) {
        [self release];
        return nil;
    }
    if ((self = [super init]))
        _pf = CGLRetainPixelFormat(format);
    return self;
}

- (instancetype)initWithData:(NSData *)attribs
{
    NSMutableData *d = [[attribs mutableCopy] autorelease];
    NSOpenGLPixelFormatAttribute zero = 0;
    [d appendBytes:&zero length:sizeof zero];
    return [self initWithAttributes:[d bytes]];
}

- (instancetype)init
{
    NSOpenGLPixelFormatAttribute a[] = {NSOpenGLPFAColorSize, 24, NSOpenGLPFAAlphaSize, 8, NSOpenGLPFADepthSize, 16,
                                        0};
    return [self initWithAttributes:a];
}

- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}

- (void)dealloc
{
    CGLReleasePixelFormat(_pf);
    [super dealloc];
}

- (void)getValues:(GLint *)vals forAttribute:(NSOpenGLPixelFormatAttribute)attrib forVirtualScreen:(GLint)screen
{
    if (vals)
        CGLDescribePixelFormat(_pf, screen, (CGLPixelFormatAttribute)attrib, vals);
}
- (GLint)numberOfVirtualScreens
{
    GLint n = 0;
    CGLDescribePixelFormat(_pf, 0, kCGLPFAVirtualScreenCount, &n);
    return n ? n : 1;
}
- (CGLPixelFormatObj)CGLPixelFormatObj { return _pf; }
@end

/* ---- contexts ---- */

int AGLViewCount;

@interface NSOpenGLContext () {
  @public
    CGLContextObj _cgl;
    NSOpenGLPixelFormat *_format;
    NSView *_view;  /* not retained; let go when the view goes */
    int _redraw;    /* a draw of the view is on its way to the main thread */
}
- (void)_ferryViewGone:(NSView *)view;
@end

/* Every context, to find the one wrapping the current CGL context. */
static pthread_mutex_t contexts_lock = PTHREAD_MUTEX_INITIALIZER;
static NSOpenGLContext **contexts;
static size_t ncontexts, contexts_size;

/* The views contexts draw into: the view's associated watcher tells the
 * context when the view goes. */
@interface AGLViewWatch : NSObject {
  @public
    NSOpenGLContext *_context; /* not retained */
    NSView *_view;             /* not retained */
}
@end
@implementation AGLViewWatch
- (void)dealloc
{
    pthread_mutex_lock(&contexts_lock);
    NSOpenGLContext *c = _context;
    pthread_mutex_unlock(&contexts_lock);
    [c _ferryViewGone:_view];
    [super dealloc];
}
@end
static char watch_key;

static __thread NSView *drawing_view; /* the view whose drawRect: is running on this thread */

static NSOpenGLContext *context_for_view(NSView *view)
{
    NSOpenGLContext *found = nil;
    pthread_mutex_lock(&contexts_lock);
    for (size_t i = ncontexts; i-- > 0 && !found;)
        if (contexts[i]->_view == view)
            found = [[contexts[i] retain] autorelease];
    pthread_mutex_unlock(&contexts_lock);
    return found;
}

static void flushed(CGLContextObj cgl, void *info);

@implementation NSOpenGLContext

- (instancetype)_ferryInitWithCGL:(CGLContextObj)cgl format:(NSOpenGLPixelFormat *)format
{
    if (!(self = [super init]))
        return nil;
    _cgl = cgl;
    _format = [format retain];
    FerryCGLSetFlushCallback(cgl, flushed, self);
    pthread_mutex_lock(&contexts_lock);
    if (ncontexts == contexts_size) {
        size_t n = contexts_size ? contexts_size * 2 : 8;
        NSOpenGLContext **c = realloc(contexts, n * sizeof *c);
        if (c) {
            contexts = c;
            contexts_size = n;
        }
    }
    if (ncontexts < contexts_size)
        contexts[ncontexts++] = self;
    pthread_mutex_unlock(&contexts_lock);
    return self;
}

- (instancetype)initWithFormat:(NSOpenGLPixelFormat *)format shareContext:(NSOpenGLContext *)share
{
    CGLContextObj cgl = NULL;
    if (!format || CGLCreateContext([format CGLPixelFormatObj], share ? share->_cgl : NULL, &cgl) || !cgl) {
        [self release];
        return nil;
    }
    return [self _ferryInitWithCGL:cgl format:format];
}

- (instancetype)initWithCGLContextObj:(CGLContextObj)context
{
    if (!context) {
        [self release];
        return nil;
    }
    NSOpenGLPixelFormat *f =
        [[[NSOpenGLPixelFormat alloc] initWithCGLPixelFormatObj:CGLGetPixelFormat(context)] autorelease];
    return [self _ferryInitWithCGL:CGLRetainContext(context) format:f];
}

- (void)dealloc
{
    [self setView:nil];
    pthread_mutex_lock(&contexts_lock);
    for (size_t i = 0; i < ncontexts; i++)
        if (contexts[i] == self) {
            contexts[i] = contexts[--ncontexts];
            break;
        }
    pthread_mutex_unlock(&contexts_lock);
    FerryCGLSetFlushCallback(_cgl, NULL, NULL);
    if (CGLGetCurrentContext() == _cgl)
        CGLSetCurrentContext(NULL);
    CGLReleaseContext(_cgl);
    [_format release];
    [super dealloc];
}

- (NSOpenGLPixelFormat *)pixelFormat { return _format; }
- (CGLContextObj)CGLContextObj { return _cgl; }

- (NSView *)view { return _view; }

- (void)_ferryViewGone:(NSView *)view
{
    pthread_mutex_lock(&contexts_lock);
    BOOL mine = _view == view;
    if (mine) {
        _view = nil;
        AGLViewCount--;
    }
    pthread_mutex_unlock(&contexts_lock);
    if (mine)
        CGLClearDrawable(_cgl);
}

/* Draws into view from now on; any thread may set it, as OBS does from
 * its graphics thread. */
- (void)setView:(NSView *)view
{
    if (view == _view) {
        if (view)
            [self update];
        return;
    }
    NSView *old = _view;
    if (old) {
        AGLViewWatch *w = objc_getAssociatedObject(old, &watch_key);
        pthread_mutex_lock(&contexts_lock);
        if (w && w->_context == self)
            w->_context = nil;
        _view = nil;
        AGLViewCount--;
        pthread_mutex_unlock(&contexts_lock);
        if (w && !w->_context)
            objc_setAssociatedObject(old, &watch_key, nil, OBJC_ASSOCIATION_RETAIN);
    }
    if (view) {
        /* one context to a view: the other one lets it go */
        NSOpenGLContext *other = context_for_view(view);
        if (other)
            [other clearDrawable];
        AGLViewWatch *w = [[AGLViewWatch alloc] init];
        w->_context = self;
        w->_view = view;
        pthread_mutex_lock(&contexts_lock);
        _view = view;
        AGLViewCount++;
        pthread_mutex_unlock(&contexts_lock);
        objc_setAssociatedObject(view, &watch_key, w, OBJC_ASSOCIATION_RETAIN);
        [w release];
        [self update];
    } else {
        CGLClearDrawable(_cgl);
    }
}

/* The drawable follows the view's size. */
- (void)update
{
    NSView *v = _view;
    if (!v)
        return;
    NSRect b = [v bounds];
    if ([v wantsBestResolutionOpenGLSurface])
        b = [v convertRectToBacking:b];
    GLint w = (GLint)ceil(b.size.width), h = (GLint)ceil(b.size.height);
    FerryCGLSetDrawableSize(_cgl, w > 0 ? w : 1, h > 0 ? h : 1);
}

- (void)clearDrawable { [self setView:nil]; }

- (void)setOffScreen:(void *)baseaddr width:(GLsizei)width height:(GLsizei)height rowbytes:(GLint)rowbytes
{
    [self setView:nil];
    CGLSetOffScreen(_cgl, width, height, rowbytes, baseaddr);
}
- (void)setFullScreen { AWarnOnce("-[NSOpenGLContext setFullScreen]"); }

- (void)flushBuffer { CGLFlushDrawable(_cgl); }

- (void)makeCurrentContext { CGLSetCurrentContext(_cgl); }
+ (void)clearCurrentContext { CGLSetCurrentContext(NULL); }
+ (NSOpenGLContext *)currentContext
{
    CGLContextObj cgl = CGLGetCurrentContext();
    if (!cgl)
        return nil;
    NSOpenGLContext *found = nil;
    pthread_mutex_lock(&contexts_lock);
    for (size_t i = 0; i < ncontexts && !found; i++)
        if (contexts[i]->_cgl == cgl)
            found = [[contexts[i] retain] autorelease];
    pthread_mutex_unlock(&contexts_lock);
    return found;
}

- (void)copyAttributesFromContext:(NSOpenGLContext *)context withMask:(GLbitfield)mask
{
    if (context)
        CGLCopyContext(context->_cgl, _cgl, mask);
}
- (void)setValues:(const GLint *)vals forParameter:(NSOpenGLContextParameter)param
{
    CGLSetParameter(_cgl, (CGLContextParameter)param, vals);
}
- (void)getValues:(GLint *)vals forParameter:(NSOpenGLContextParameter)param
{
    CGLGetParameter(_cgl, (CGLContextParameter)param, vals);
}
- (GLint)currentVirtualScreen
{
    GLint s = 0;
    CGLGetVirtualScreen(_cgl, &s);
    return s;
}
- (void)setCurrentVirtualScreen:(GLint)screen { CGLSetVirtualScreen(_cgl, screen); }
- (void)lock { CGLLockContext(_cgl); }
- (void)unlock { CGLUnlockContext(_cgl); }
@end

/* ---- showing what a context drew ---- */

@interface NSOpenGLView () {
  @public
    BOOL _glOnly; /* the next draw is for a new frame alone: drawRect: isn't called */
}
- (void)_ferryPrepareToDraw;
- (void)_ferryDidDraw;
@end

/* After each flush: the view is drawn again, unless the flush came from
 * its own drawRect:, after which the view shows the new frame anyway. */
static void flushed(CGLContextObj cgl, void *info)
{
    NSOpenGLContext *c = info;
    NSView *v = c->_view;
    if (!v || (drawing_view == v && pthread_main_np()))
        return;
    if (__atomic_exchange_n(&c->_redraw, 1, __ATOMIC_ACQ_REL))
        return;
    [c retain];
    dispatch_async(dispatch_get_main_queue(), ^{
      __atomic_store_n(&c->_redraw, 0, __ATOMIC_RELEASE);
      NSView *view = c->_view;
      if (view) {
          [view setNeedsDisplay:YES];
          if ([view isKindOfClass:[NSOpenGLView class]])
              ((NSOpenGLView *)view)->_glOnly = YES;
      }
      [c release];
    });
}

BOOL AGLViewWillDraw(NSView *view)
{
    if ([view isKindOfClass:[NSOpenGLView class]]) {
        NSOpenGLView *gv = (NSOpenGLView *)view;
        BOOL glOnly = gv->_glOnly;
        gv->_glOnly = NO;
        if (glOnly)
            return YES;
        [gv _ferryPrepareToDraw];
    }
    drawing_view = view;
    return NO;
}

void AGLViewDidDraw(NSView *view, CGContextRef ctx)
{
    if (drawing_view == view) {
        drawing_view = nil;
        if ([view isKindOfClass:[NSOpenGLView class]])
            [(NSOpenGLView *)view _ferryDidDraw];
    }
    NSOpenGLContext *c = context_for_view(view);
    FerryGLFrame *f = c ? FerryCGLCopyFrame(c->_cgl) : NULL;
    if (!f)
        return;
    CGDataProviderRef p = CGDataProviderCreateWithData(NULL, f->data, (size_t)f->rowBytes * (size_t)f->height, NULL);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate((size_t)f->width, (size_t)f->height, 8, 32, (size_t)f->rowBytes, cs,
                                   (f->opaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst) |
                                       kCGBitmapByteOrder32Little,
                                   p, NULL, true, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(p);
    if (img) {
        NSRect b = [view bounds];
        CGContextSaveGState(ctx);
        /* the frame's first row is the bottom one: upright as it is in a
         * flipped view, turned over in an unflipped one */
        if (![view isFlipped] && !f->topDown) {
            CGContextTranslateCTM(ctx, 0, NSMinY(b) * 2 + NSHeight(b));
            CGContextScaleCTM(ctx, 1, -1);
        }
        /* pixel for pixel when it's the view's size, which is cairo's
         * quick way */
        CGRect device = CGContextConvertRectToDeviceSpace(ctx, b);
        if (fabs(fabs(device.size.width) - f->width) < 0.5 && fabs(fabs(device.size.height) - f->height) < 0.5)
            CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
        CGContextDrawImage(ctx, b, img);
        CGContextRestoreGState(ctx);
        CGImageRelease(img);
    }
    FerryGLFrameRelease(f);
}

/* ---- the view ---- */

@implementation NSOpenGLView {
    NSOpenGLContext *_context;
    NSOpenGLPixelFormat *_format;
    BOOL _prepared, _needsReshape;
    CGLContextObj _savedCurrent;
    BOOL _locked;
}

+ (NSOpenGLPixelFormat *)defaultPixelFormat { return [[[NSOpenGLPixelFormat alloc] init] autorelease]; }

- (instancetype)initWithFrame:(NSRect)frame pixelFormat:(NSOpenGLPixelFormat *)format
{
    if ((self = [super initWithFrame:frame])) {
        _format = [(format ?: [[self class] defaultPixelFormat]) retain];
        _needsReshape = YES;
    }
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame pixelFormat:nil]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _format = [[[self class] defaultPixelFormat] retain];
        _needsReshape = YES;
    }
    return self;
}

- (void)dealloc
{
    [_context clearDrawable];
    [_context release];
    [_format release];
    [super dealloc];
}

- (NSOpenGLPixelFormat *)pixelFormat { return _format; }
- (void)setPixelFormat:(NSOpenGLPixelFormat *)format
{
    [format retain];
    [_format release];
    _format = format;
}

- (NSOpenGLContext *)openGLContext
{
    if (!_context && _format) {
        _context = [[NSOpenGLContext alloc] initWithFormat:_format shareContext:nil];
        if (_context)
            [_context setView:self];
    }
    return _context;
}
- (void)setOpenGLContext:(NSOpenGLContext *)context
{
    if (context == _context)
        return;
    [_context clearDrawable];
    id wasContext = _context;
    _context = [context retain];
    [wasContext release];
    _prepared = NO;
    _needsReshape = YES;
    [_context setView:self];
}
- (void)clearGLContext
{
    [_context clearDrawable];
    [_context release];
    _context = nil;
    _prepared = NO;
}

- (void)prepareOpenGL {}
- (void)reshape {}
- (void)update { [_context update]; }

- (BOOL)isOpaque { return YES; }

/* the app asking for a draw of its own: drawRect: is called */
- (void)setNeedsDisplay:(BOOL)flag
{
    _glOnly = NO;
    [super setNeedsDisplay:flag];
}
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    _glOnly = NO;
    [super setNeedsDisplayInRect:rect];
}

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    _needsReshape = YES;
    _glOnly = NO;
}
- (void)setBoundsSize:(NSSize)size
{
    [super setBoundsSize:size];
    _needsReshape = YES;
    _glOnly = NO;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (_context && [_context view] != self)
        [_context setView:self];
    _needsReshape = YES;
}

/* Before drawRect:, as a Mac does: the context current and locked, ready
 * the first time, and reshaped after the view's size changed. */
- (void)_ferryPrepareToDraw
{
    NSOpenGLContext *c = [self openGLContext];
    if (!c)
        return;
    if ([c view] != self)
        [c setView:self];
    CGLLockContext([c CGLContextObj]);
    _locked = YES;
    _savedCurrent = CGLGetCurrentContext();
    if (_savedCurrent)
        CGLRetainContext(_savedCurrent);
    [c makeCurrentContext];
    if (!_prepared) {
        _prepared = YES;
        [self prepareOpenGL];
    }
    if (_needsReshape) {
        _needsReshape = NO;
        [self update];
        [self reshape];
    }
}
- (void)_ferryDidDraw
{
    if (!_locked)
        return;
    _locked = NO;
    CGLContextObj cgl = [_context CGLContextObj];
    CGLSetCurrentContext(_savedCurrent);
    if (_savedCurrent)
        CGLReleaseContext(_savedCurrent);
    _savedCurrent = NULL;
    CGLUnlockContext(cgl);
}
@end

/* ---- a view's surface resolution ---- */

static char best_key, edr_key;

@implementation NSView (NSOpenGLSurfaceResolution)
- (BOOL)wantsBestResolutionOpenGLSurface { return [objc_getAssociatedObject(self, &best_key) boolValue]; }
- (void)setWantsBestResolutionOpenGLSurface:(BOOL)flag
{
    objc_setAssociatedObject(self, &best_key, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN);
    NSOpenGLContext *c = AGLViewCount ? context_for_view(self) : nil;
    [c update];
}
- (BOOL)wantsExtendedDynamicRangeOpenGLSurface { return [objc_getAssociatedObject(self, &edr_key) boolValue]; }
- (void)setWantsExtendedDynamicRangeOpenGLSurface:(BOOL)flag
{
    objc_setAssociatedObject(self, &edr_key, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN);
}
@end
