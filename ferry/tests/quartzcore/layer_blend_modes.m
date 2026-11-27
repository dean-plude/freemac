/* SPDX-License-Identifier: GPL-3.0-or-later
 * A layer's compositingFilter as a blend mode (freemac 1.256, Ferry
 * 0.79.0), by Core Animation's own names and Core Image's, drawn with
 * renderInContext: over a coloured layer and checked pixel by pixel. */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

#define W 40
#define H 40

static CGColorRef rgb(double r, double g, double b)
{
    static NSMutableArray *keep;
    if (!keep)
        keep = [NSMutableArray new];
    CGColorRef c = CGColorCreateSRGB(r, g, b, 1);
    [keep addObject:(__bridge id)c];
    CGColorRelease(c);
    return c;
}

/* the colour at the middle of a layer of `top` put over one of `under` */
static void show(const char *what, id filter, CGColorRef under, CGColorRef top, double opacity)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CALayer *root = [CALayer layer];
    root.frame = CGRectMake(0, 0, W, H);
    root.backgroundColor = under;
    CALayer *l = [CALayer layer];
    l.frame = CGRectMake(10, 10, 20, 20);
    l.backgroundColor = top;
    l.opacity = opacity;
    l.compositingFilter = filter;
    [root addSublayer:l];
    [root renderInContext:c];
    const unsigned char *d = CGBitmapContextGetData(c);
    const unsigned char *p = d + (H / 2) * CGBitmapContextGetBytesPerRow(c) + (W / 2) * 4;
    const unsigned char *o = d + 2 * CGBitmapContextGetBytesPerRow(c) + 2 * 4;
    printf("%s: %d,%d,%d (outside %d,%d,%d)\n", what, p[0], p[1], p[2], o[0], o[1], o[2]);
    CGContextRelease(c);
}

int main(void)
{
    @autoreleasepool {
        CGColorRef red = rgb(1, 0, 0), blue = rgb(0, 0, 1), grey = rgb(0.5, 0.5, 0.5), white = rgb(1, 1, 1);
        show("none", nil, red, grey, 1);
        show("multiply", @"multiplyBlendMode", red, grey, 1);
        show("screen", @"screenBlendMode", blue, grey, 1);
        show("plus lighter", @"plusL", red, blue, 1);
        show("Core Image difference", @"CIDifferenceBlendMode", red, white, 1);
        show("Core Image addition", @"CIAdditionCompositing", red, blue, 1);
        show("multiply at half opacity", @"multiplyBlendMode", red, rgb(0, 0, 0), 0.5);
        show("an unknown filter is drawn normally", @"noSuchFilter", red, grey, 1);
    }
    return 0;
}
