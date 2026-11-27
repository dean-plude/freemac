/* SPDX-License-Identifier: GPL-3.0-or-later
 * What darktable 5.2's Mac build asks of AppKit and Core Services (freemac
 * darktable work). Its toolkit, GTK 3, draws each window through a view
 * that says it wants a layer by overriding wantsLayer (never calling
 * setWantsLayer:) and draws in updateLayer, setting a CVPixelBuffer's
 * IOSurface as the layer's contents. Also: a window given its own title
 * again, and Unicode collation without a collator. */
#import <Cocoa/Cocoa.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreServices/CoreServices.h>
#include <IOSurface/IOSurface.h>

static const char *yes(BOOL b) { return b ? "yes" : "no"; }

static const char *colour_at(NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    static char buf[64];
    if (a < 0.05)
        return "clear";
    if (r < 0.1 && g > 0.9 && b < 0.1)
        return "green";
    snprintf(buf, sizeof buf, "%.2f %.2f %.2f", r, g, b);
    return buf;
}

/* Like GTK's GdkQuartzView */
@interface GdkLike : NSView
@property int updates;
@end
@implementation GdkLike {
    CVPixelBufferRef _pixels;
}
- (BOOL)wantsLayer { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer
{
    self.updates++;
    if (!_pixels)
        CVPixelBufferCreate(NULL, (size_t)self.bounds.size.width, (size_t)self.bounds.size.height,
                            kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey : @1},
                            &_pixels);
    CVPixelBufferLockBaseAddress(_pixels, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(_pixels);
    size_t row = CVPixelBufferGetBytesPerRow(_pixels);
    for (size_t y = 0; y < CVPixelBufferGetHeight(_pixels); y++)
        for (size_t x = 0; x < CVPixelBufferGetWidth(_pixels); x++) {
            uint8_t *px = base + y * row + x * 4;   /* B G R A */
            px[0] = 0, px[1] = 255, px[2] = 0, px[3] = 255;
        }
    CVPixelBufferUnlockBaseAddress(_pixels, 0);
    self.layer.contents = nil;
    self.layer.contents = (__bridge id)CVPixelBufferGetIOSurface(_pixels);
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        GdkLike *v = [[GdkLike alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
        printf("a view overriding wantsLayer has a layer: %s\n", yes(v.layer != nil));
        printf("its layer's delegate is the view: %s\n", yes(v.layer.delegate == (id)v));
        [v setNeedsDisplay:YES];
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
        [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
        printf("updateLayer asked when drawn: %s\n", yes(v.updates > 0));
        printf("CVPixelBuffer contents drawn: %s\n", colour_at(rep, 20, 10));

        NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        printf("a plain view still has no layer: %s\n", yes(plain.layer == nil));

        /* GTK sets the title it already has */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
        NSString *t = [NSString stringWithFormat:@"%@ %d", @"darktable", 5];
        [w setTitle:t];
        [w setTitle:[w title]];
        printf("title set to itself: %s\n", [[w title] UTF8String]);

        /* collation without a collator, as darktable's sorting asks */
        UniChar a[] = {'a', 'p', 'p', 'l', 'e'}, b[] = {'B', 'a', 'n', 'a', 'n', 'a'}, c[] = {'A', 'P', 'P', 'L', 'E'};
        Boolean eq = false;
        SInt32 order = 0;
        OSStatus st = UCCompareTextDefault(kUCCollateCaseInsensitiveMask, a, 5, b, 6, &eq, &order);
        printf("UCCompareTextDefault apple < Banana: %s (status %d)\n", yes(order < 0 && !eq), (int)st);
        UCCompareTextDefault(kUCCollateCaseInsensitiveMask, a, 5, c, 5, &eq, &order);
        printf("apple equals APPLE ignoring case: %s\n", yes(eq && order == 0));
        UCCompareTextNoLocale(0, b, 6, a, 5, &eq, &order);
        printf("UCCompareTextNoLocale Banana > apple: %s\n", yes(order > 0));
    }
    return 0;
}
