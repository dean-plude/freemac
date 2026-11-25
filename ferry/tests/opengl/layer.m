/* SPDX-License-Identifier: GPL-3.0-or-later
 * CAOpenGLLayer (freemac 1.235, Ferry 0.59.0) as VLC's video output uses
 * it: the backing layer of a layer-backed view, with a context of the
 * program's own, drawn when the window draws, then displayed from a thread
 * of the program's own, and asynchronously, at the display's rate; its
 * drawing read back with cacheDisplayInRect:. A picture goes to
 * $FERRY_TEST_SHOTS when it is set. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <OpenGL/gl.h>
#include <pthread.h>
#include <stdio.h>

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

static void pixel(NSBitmapImageRep *rep, int x, int y, unsigned char out[3])
{
    unsigned char *p = [rep bitmapData] + (NSInteger)y * [rep bytesPerRow] + x * 4;
    out[0] = p[0], out[1] = p[1], out[2] = p[2];
}
static int near(const unsigned char *c, int r, int g, int b)
{
    return abs(c[0] - r) < 24 && abs(c[1] - g) < 24 && abs(c[2] - b) < 24;
}
static NSBitmapImageRep *picture(NSView *v, const char *name)
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    const char *dir = getenv("FERRY_TEST_SHOTS");
    if (dir && *dir && name) {
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithFormat:@"%s/%s.png", dir, name] atomically:YES];
    }
    return rep;
}
static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static CGLContextObj own;   /* the program's context, as VLC makes its own */
static float colour[3] = {1, 0.5f, 0};

@interface VideoLayer : CAOpenGLLayer
@property (atomic) BOOL ready;
@property (atomic) int draws, mainDraws;
@property (atomic) GLint viewportW, viewportH;
@property (atomic) BOOL hadTime;
@end

@implementation VideoLayer
- (BOOL)canDrawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
               forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts
{
    return self.ready;
}
- (void)drawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
            forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts
{
    self.draws++;
    if (pthread_main_np())
        self.mainDraws++;
    self.hadTime = ts && (ts->flags & kCVTimeStampHostTimeValid) && t > 0 && CGLGetCurrentContext() == ctx;
    GLint vp[4] = {0};
    glGetIntegerv(GL_VIEWPORT, vp);
    self.viewportW = vp[2];
    self.viewportH = vp[3];
    glClearColor(colour[0], colour[1], colour[2], 1);
    glClear(GL_COLOR_BUFFER_BIT);
    /* a white band along the bottom */
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, vp[2], vp[3] / 8);
    glClearColor(1, 1, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
    [super drawInCGLContext:ctx pixelFormat:pf forLayerTime:t displayTime:ts];
}
- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask
{
    return CGLRetainPixelFormat(CGLGetPixelFormat(own));
}
- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pf { return CGLRetainContext(own); }
@end

@interface VideoView : NSView
@end
@implementation VideoView
- (CALayer *)makeBackingLayer
{
    VideoLayer *l = [[VideoLayer alloc] init];
    l.needsDisplayOnBoundsChange = YES;
    l.opaque = YES;
    return [l autorelease];
}
@end

static VideoLayer *layer;
static void *vout_thread(void *arg)
{
    @autoreleasepool {
        colour[0] = 0, colour[1] = 0.6f, colour[2] = 1;
        [layer display];
        [CATransaction flush];
    }
    return NULL;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        CGLPixelFormatAttribute attrs[] = {kCGLPFAAccelerated, kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
                                           (CGLPixelFormatAttribute)0};
        CGLPixelFormatObj pf = NULL;
        GLint n = 0;
        CGLChoosePixelFormat(attrs, &pf, &n);
        CGLCreateContext(pf, NULL, &own);
        CGLReleasePixelFormat(pf);
        if (!check("a context of the program's own", own != NULL))
            return 1;
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 220, 140) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        VideoView *v = [[VideoView alloc] initWithFrame:NSMakeRect(10, 10, 200, 120)];
        [v setWantsLayer:YES];
        [[w contentView] addSubview:v];
        layer = (VideoLayer *)[v layer];
        check("the view's backing layer is the OpenGL layer",
              [layer isKindOfClass:[CAOpenGLLayer class]] && [layer isKindOfClass:[VideoLayer class]]);
        check("not asynchronous at first", ![layer isAsynchronous]);

        [w display];
        check("not drawn while it can't draw", layer.draws == 0 && [layer contents] == nil);
        layer.ready = YES;
        [layer setNeedsDisplay];
        [w display];
        check("drawn on the main thread once it can", layer.draws == 1 && layer.mainDraws == 1);
        check("its context current, with a time stamp", layer.hadTime);
        check("the viewport the layer's size in pixels", layer.viewportW == 200 && layer.viewportH == 120);
        check("its drawing is the layer's contents", [layer contents] != nil);
        check("the context put back after", CGLGetCurrentContext() == NULL);
        NSBitmapImageRep *rep = picture(v, NULL);
        unsigned char c[3];
        pixel(rep, 100, 40, c);
        check("orange in the view", near(c, 255, 128, 0));
        pixel(rep, 100, 115, c);
        check("the white band at the bottom", near(c, 255, 255, 255));
        pixel(rep, 100, 5, c);
        check("not at the top", near(c, 255, 128, 0));

        /* displayed from the program's own thread, as VLC's output does */
        pthread_t t;
        pthread_create(&t, NULL, vout_thread, NULL);
        pthread_join(t, NULL);
        check("drawn on the other thread", layer.draws == 2 && layer.mainDraws == 1);
        spin(0.1);
        rep = picture(v, "opengl-layer");
        pixel(rep, 100, 40, c);
        check("its new contents shown on the main thread", near(c, 0, 153, 255));
        int before = layer.draws;
        [w displayIfNeeded];
        check("a window draw doesn't draw the layer again", layer.draws == before);

        /* bigger, and twice the pixels */
        [layer setContentsScale:2];
        [v setFrameSize:NSMakeSize(160, 100)];
        [w display];
        check("resized: drawn again at 320 by 200 pixels", layer.viewportW == 320 && layer.viewportH == 200);
        [layer setContentsScale:1];

        /* asynchronous: drawn at the display's rate */
        before = layer.draws;
        layer.asynchronous = YES;
        check("asynchronous", [layer isAsynchronous]);
        spin(0.5);
        layer.asynchronous = NO;
        int drawn = layer.draws - before;
        printf("asynchronous for half a second: %s\n", drawn >= 12 && drawn <= 34 ? "about 30 draws" : "NOT about 30");
        if (drawn < 12 || drawn > 34)
            fprintf(stderr, "%d draws\n", drawn);
        before = layer.draws;
        spin(0.2);
        check("not after", layer.draws == before);

        /* the part that shows */
        CALayer *outer = [CALayer layer], *inner = [CALayer layer];
        outer.bounds = CGRectMake(0, 0, 100, 100);
        outer.masksToBounds = YES;
        inner.frame = CGRectMake(50, 50, 100, 100);
        [outer addSublayer:inner];
        CGRect vis = [inner visibleRect];
        check("visibleRect: the part inside the clipping superlayer", CGRectEqualToRect(vis, CGRectMake(0, 0, 50, 50)));

        [v removeFromSuperview];
        [v release];
        CGLReleaseContext(own);
    }
    return 0;
}
