/* SPDX-License-Identifier: GPL-3.0-or-later
 * Buttons drawn through their cells, as Qt 6's Mac style draws its check
 * boxes, radio buttons and push buttons (OBS): an NSButton made in code
 * has its settings set on the button, then its cell is asked to draw. */
#import <Cocoa/Cocoa.h>

static NSBitmapImageRep *canvas(void)
{
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:20 pixelsHigh:20 bitsPerSample:8
                                              samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
}

/* clear, white, grey or coloured */
static const char *kind(NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&r green:&g blue:&b alpha:&a];
    if (a < 0.05)
        return "clear";
    CGFloat hi = fmax(r, fmax(g, b)), lo = fmin(r, fmin(g, b));
    if (hi - lo > 0.2)
        return "coloured";
    return hi > 0.95 ? "white" : "grey";
}

typedef void (^Drawing)(NSButton *b, NSRect r);

static NSBitmapImageRep *draw(NSButton *b, Drawing d)
{
    NSBitmapImageRep *rep = canvas();
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    d(b, NSMakeRect(0, 0, 20, 20));
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSButton *radio = [[NSButton alloc] init];
        [radio setButtonType:NSButtonTypeRadio];
        radio.title = @"";
        printf("a button made in code has a cell: %s\n", [radio.cell isKindOfClass:[NSButtonCell class]] ? "yes" : "no");
        printf("the same cell each time: %s\n", radio.cell == radio.cell ? "yes" : "no");
        printf("the cell's view is the button: %s\n", [radio.cell controlView] == radio ? "yes" : "no");

        Drawing interior = ^(NSButton *b, NSRect r) { [b.cell drawInteriorWithFrame:r inView:b]; };
        radio.state = NSControlStateValueOn;
        NSBitmapImageRep *on = draw(radio, interior);
        printf("radio button on: centre %s, ring %s\n", kind(on, 9, 10), kind(on, 4, 10));
        radio.state = NSControlStateValueOff;
        NSBitmapImageRep *off = draw(radio, interior);
        printf("radio button off: centre %s, edge %s\n", kind(off, 9, 10), kind(off, 2, 10));
        printf("the cell keeps the button's state: %s\n", [radio.cell state] == NSControlStateValueOff ? "yes" : "no");

        NSButton *check = [[NSButton alloc] init];
        [check setButtonType:NSButtonTypeSwitch];
        check.title = @"";
        check.state = NSControlStateValueOn;
        NSBitmapImageRep *ticked = draw(check, interior);
        printf("check box on: corner %s\n", kind(ticked, 4, 6));
        check.enabled = NO;
        printf("the cell keeps the button's enabled: %s\n", [check.cell isEnabled] ? "no" : "yes");

        NSButton *push = [[NSButton alloc] init];
        NSBitmapImageRep *bezel = draw(push, ^(NSButton *b, NSRect r) { [b.cell drawBezelWithFrame:r inView:b]; });
        printf("push button bezel: middle %s\n", kind(bezel, 10, 10));
    }
    return 0;
}
