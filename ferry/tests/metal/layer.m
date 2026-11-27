/* SPDX-License-Identifier: GPL-3.0-or-later
 * CAMetalLayer as Blender's and most Metal programs' windows
 * use it: the backing layer of a layer-backed view, its device and format,
 * drawables the drawable size, a clear presented by a command buffer and
 * shown as the layer's contents on the main thread, read back with
 * cacheDisplayInRect:, drawables taken in turns from another thread, and a
 * new drawable size after a resize. A picture goes to $FERRY_TEST_SHOTS when
 * it is set. */
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <pthread.h>
#include <stdio.h>

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
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
static int near_at(NSBitmapImageRep *rep, int x, int y, int r, int g, int b)
{
    unsigned char *p = [rep bitmapData] + (NSInteger)y * [rep bytesPerRow] + x * ([rep bitsPerPixel] / 8);
    return abs(p[0] - r) < 8 && abs(p[1] - g) < 8 && abs(p[2] - b) < 8;
}
static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

@interface MetalView : NSView
@end
@implementation MetalView
- (CALayer *)makeBackingLayer { return [CAMetalLayer layer]; }
@end

static id<MTLCommandQueue> queue;
static void clear_to(CAMetalLayer *l, double r, double g, double b)
{
    @autoreleasepool {
        id<CAMetalDrawable> d = [l nextDrawable];
        if (!d) return;
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = d.texture;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, 1);
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        [cb presentDrawable:d];
        [cb commit];
    }
}

static CAMetalLayer *layer;
static int threadFrames;
static void *render_thread(void *arg)
{
    for (int i = 0; i < 20; i++) {
        clear_to(layer, 0, 0.5, 1);
        threadFrames++;
    }
    return NULL;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 160, 120)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        MetalView *v = [[MetalView alloc] initWithFrame:NSMakeRect(0, 0, 160, 120)];
        v.wantsLayer = YES;
        [w setContentView:v];
        [w makeKeyAndOrderFront:nil];
        layer = (CAMetalLayer *)v.layer;
        check("the view's backing layer is a Metal layer", [layer isKindOfClass:[CAMetalLayer class]]);
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        check("the layer's preferred device is the device", layer.preferredDevice == dev);
        layer.device = dev;
        check("BGRA8 by default", layer.pixelFormat == MTLPixelFormatBGRA8Unorm);
        layer.drawableSize = CGSizeMake(160, 120);
        queue = [dev newCommandQueue];

        id<CAMetalDrawable> d = [layer nextDrawable];
        check("a drawable the drawable size",
              d && d.texture.width == 160 && d.texture.height == 120 && d.layer == layer);
        d = nil;

        clear_to(layer, 1, 0.5, 0);
        spin(0.3);
        check("presented as the layer's contents", layer.contents != nil);
        NSBitmapImageRep *rep = picture(v, "metal_layer");
        check("orange in the view", near_at(rep, 80, 60, 255, 128, 0));

        pthread_t t;
        pthread_create(&t, NULL, render_thread, NULL);
        pthread_join(t, NULL);
        spin(0.3);
        check("20 frames from another thread", threadFrames == 20);
        rep = picture(v, NULL);
        check("its last frame shown", near_at(rep, 80, 60, 0, 128, 255));

        layer.drawableSize = CGSizeMake(320, 240);
        d = [layer nextDrawable];
        check("resized: drawables 320 by 240", d.texture.width == 320 && d.texture.height == 240);
    }
    return 0;
}
