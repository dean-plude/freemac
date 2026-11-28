/* SPDX-License-Identifier: GPL-3.0-or-later
 * A screen at scale 2 (M7): run on a headless Weston compositor started
 * with --scale=2. Windows, views and screens report the scale, points
 * convert to the window's pixels and back, rectangles align to whole
 * pixels, and an image drawn with lockFocus has twice the pixels. */
#import <Cocoa/Cocoa.h>

@interface Probe : NSView
@property int changes;
@end
@implementation Probe
- (void)viewDidChangeBackingProperties { self.changes++; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        Probe *v = [[Probe alloc] initWithFrame:NSMakeRect(10, 10, 50, 50)];
        [[w contentView] addSubview:v];
        /* joining the window is one change, as on a Mac (freemac 1.271); none after */
        printf("joining the window told the view: %s\n", v.changes == 1 ? "yes" : "no");
        v.changes = 0;
        [w makeKeyAndOrderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        printf("scale: screen %.0f, window %.0f\n", [[NSScreen mainScreen] backingScaleFactor], [w backingScaleFactor]);
        NSRect r = [v convertRectToBacking:NSMakeRect(0, 0, 10, 10)];
        printf("view rect in pixels: %.0f,%.0f %.0fx%.0f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
        NSRect back = [v convertRectFromBacking:r];
        printf("and back: %.0f,%.0f %.0fx%.0f\n", back.origin.x, back.origin.y, back.size.width, back.size.height);
        NSSize s = [v convertSizeToBacking:NSMakeSize(3, 4)];
        printf("size: %.0fx%.0f\n", s.width, s.height);
        NSRect a = [w backingAlignedRect:NSMakeRect(0.3, 0.3, 10.1, 10.1) options:NSAlignAllEdgesOutward];
        printf("aligned outward: %.2f %.2f %.2f %.2f\n", a.origin.x, a.origin.y, a.size.width, a.size.height);
        a = [w backingAlignedRect:NSMakeRect(0.3, 0.3, 10.1, 10.1) options:NSAlignAllEdgesInward];
        printf("aligned inward: %.2f %.2f %.2f %.2f\n", a.origin.x, a.origin.y, a.size.width, a.size.height);
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
        [img lockFocus];
        [[NSColor blueColor] set];
        NSRectFill(NSMakeRect(0, 0, 8, 8));
        [img unlockFocus];
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[img TIFFRepresentation]];
        printf("an 8x8 point image has %ldx%ld pixels\n", (long)[rep pixelsWide], (long)[rep pixelsHigh]);
        printf("no change of scale seen: %s\n", v.changes == 0 ? "yes" : "no");
    }
    return 0;
}
