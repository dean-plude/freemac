/* SPDX-License-Identifier: GPL-3.0-or-later
 * A layer-backed view drawn the way Qt's Cocoa plugin draws (Qt 6, as OBS
 * uses it), without a display: the view overrides makeBackingLayer and
 * setLayer:, wraps the layer in a container layer whose setNeedsDisplay
 * and setNeedsDisplayInRect: call each other, draws only in displayLayer:,
 * and hands its pixels over as an IOSurface set as the layer's contents. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <IOSurface/IOSurface.h>

static const char *yes(BOOL b) { return b ? "yes" : "no"; }

static const char *colour_at(NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    static char buf[64];
    if (a < 0.05)
        return "clear";
    struct { const char *name; double r, g, b; } named[] = {
        {"red", 1, 0, 0}, {"green", 0, 1, 0}, {"blue", 0, 0, 1}, {"white", 1, 1, 1}, {"black", 0, 0, 0},
    };
    for (unsigned i = 0; i < sizeof named / sizeof *named; i++)
        if (fabs(r - named[i].r) < 0.1 && fabs(g - named[i].g) < 0.1 && fabs(b - named[i].b) < 0.1)
            return named[i].name;
    snprintf(buf, sizeof buf, "%.2f %.2f %.2f", r, g, b);
    return buf;
}

/* Like Qt's QContainerLayer: either way of marking it marks it once,
 * through the other, and it is displayed through its one sublayer. */
@interface Container : CALayer
@property int marks;
@end
@implementation Container
- (void)setNeedsDisplay { [self setNeedsDisplayInRect:self.bounds]; }
- (void)setNeedsDisplayInRect:(CGRect)r
{
    self.marks++;
    if (!self.needsDisplay)
        [super setNeedsDisplayInRect:r];
    for (CALayer *l in self.sublayers)
        [l setNeedsDisplayInRect:r];
}
@end

/* An IOSurface of w x h BGRA pixels, the top half blue, the bottom half red. */
static IOSurfaceRef surface(int w, int h)
{
    NSDictionary *p = @{
        (id)kIOSurfaceWidth : @(w), (id)kIOSurfaceHeight : @(h), (id)kIOSurfaceBytesPerElement : @4,
        (id)kIOSurfacePixelFormat : @((unsigned)'BGRA'),
    };
    IOSurfaceRef s = IOSurfaceCreate((__bridge CFDictionaryRef)p);
    IOSurfaceLock(s, 0, NULL);
    uint8_t *base = IOSurfaceGetBaseAddress(s);
    size_t row = IOSurfaceGetBytesPerRow(s);
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            uint8_t *px = base + y * row + x * 4;   /* B G R A */
            px[0] = y < h / 2 ? 255 : 0;
            px[1] = 0;
            px[2] = y < h / 2 ? 0 : 255;
            px[3] = 255;
        }
    IOSurfaceUnlock(s, 0, NULL);
    return s;
}

/* Like Qt's QNSView. */
@interface QtLike : NSView
@property int setLayers, displays;
@property (strong) CALayer *content;
@end
@implementation QtLike
- (CALayer *)makeBackingLayer { return [CALayer layer]; }
- (void)setLayer:(CALayer *)layer
{
    self.setLayers++;
    self.content = layer;
    layer.delegate = (id)self;
    Container *c = [Container layer];
    [c addSublayer:layer];
    [super setLayer:c];
}
- (void)displayLayer:(CALayer *)layer
{
    if (layer != self.content)
        return;   /* the container is displayed through its content */
    self.displays++;
    IOSurfaceRef s = surface((int)self.bounds.size.width, (int)self.bounds.size.height);
    layer.contents = (__bridge id)s;
    CFRelease(s);
}
- (void)layout
{
    [super layout];
    self.content.frame = self.layer.bounds;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        QtLike *v = [[QtLike alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
        v.wantsLayer = YES;
        printf("setLayer: called for the backing layer: %s (%d)\n", yes(v.setLayers == 1), v.setLayers);
        printf("the view's layer is the container: %s\n", yes([v.layer isKindOfClass:[Container class]]));
        v.content.frame = v.layer.bounds;

        Container *c = (Container *)v.layer;
        int before = c.marks;
        [c setNeedsDisplay];
        printf("container marked through setNeedsDisplayInRect: once: %s\n", yes(c.marks - before == 1));

        [v.content display];   /* nothing set yet: the view hasn't asked */
        int shown = v.displays;
        [v setNeedsDisplay:YES];
        printf("the view's setNeedsDisplay: marks the content layer: %s\n", yes(v.content.needsDisplay));

        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
        [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
        printf("displayLayer: asked when drawn: %s\n", yes(v.displays > shown));
        printf("IOSurface contents drawn: top %s, bottom %s\n", colour_at(rep, 20, 2), colour_at(rep, 20, 17));
    }
    return 0;
}
