/* SPDX-License-Identifier: GPL-3.0-or-later
 * Disclosure buttons (freemac 1.NEXT): a disclosure triangle, as VLC's Open
 * dialog shows its address field with, and the rounded kind. Each is its
 * own small size, turns on and off as it's clicked, and draws a chevron:
 * the triangle points right when closed and down when open, with no push
 * button's bezel behind it. */
#import <Cocoa/Cocoa.h>

/* Where the dark pixels are in a picture of the button, and whether its
 * middle is white (a push button's bezel). */
static NSString *picture(NSButton *b)
{
    NSBitmapImageRep *rep = [b bitmapImageRepForCachingDisplayInRect:[b bounds]];
    [b cacheDisplayInRect:[b bounds] toBitmapImageRep:rep];
    NSInteger w = [rep pixelsWide], h = [rep pixelsHigh], minx = w, maxx = -1, miny = h, maxy = -1;
    for (NSInteger y = 0; y < h; y++)
        for (NSInteger x = 0; x < w; x++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            if ([c alphaComponent] > 0.3 && [c redComponent] < 0.7) {
                minx = MIN(minx, x); maxx = MAX(maxx, x);
                miny = MIN(miny, y); maxy = MAX(maxy, y);
            }
        }
    if (maxx < 0)
        return @"nothing drawn";
    return [NSString stringWithFormat:@"chevron %s than tall", maxx - minx < maxy - miny ? "narrower" : "wider"];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSButton *t = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 13, 13)];
        [t setButtonType:NSButtonTypePushOnPushOff];
        [t setBezelStyle:NSBezelStyleDisclosure];
        [t setTitle:@""];
        NSSize s = [t intrinsicContentSize];
        printf("triangle %gx%g, %s closed", s.width, s.height, [picture(t) UTF8String]);
        [t performClick:nil];
        printf(", %s, %s open\n", [t state] == NSControlStateValueOn ? "on" : "off", [picture(t) UTF8String]);
        [t setTitle:@"More"];
        printf("with a title it's wider: %s\n", [t intrinsicContentSize].width > 13 + 10 ? "yes" : "no");
        NSButton *r = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 21, 21)];
        [r setButtonType:NSButtonTypePushOnPushOff];
        [r setBezelStyle:NSBezelStyleRoundedDisclosure];
        [r setTitle:@""];
        s = [r intrinsicContentSize];
        printf("rounded %gx%g, %s\n", s.width, s.height, [picture(r) UTF8String]);
    }
    return 0;
}
