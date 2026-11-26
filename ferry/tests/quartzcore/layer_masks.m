/* SPDX-License-Identifier: GPL-3.0-or-later
 * Layer masks (freemac 1.254, Ferry 0.77.0), drawn with renderInContext:
 * into a bitmap context and checked pixel by pixel: a layer, its sublayers
 * and border, shows only where its mask layer, placed in the layer's own
 * space by its frame, is opaque, and as far as it is; a shape layer masks
 * by its shape; the layer's shadow is cast by what the mask leaves. */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

#define W 64
#define H 64

static CGColorRef rgb(double r, double g, double b, double a)
{
    static NSMutableArray *keep;
    if (!keep)
        keep = [NSMutableArray new];
    CGColorRef c = CGColorCreateSRGB(r, g, b, a);
    [keep addObject:(__bridge id)c];
    CGColorRelease(c);
    return c;
}

static CGContextRef draw(CALayer *layer)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    CALayer *root = [CALayer layer];   /* renderInContext: draws in the layer's own space */
    root.frame = CGRectMake(0, 0, W, H);
    [root addSublayer:layer];
    [root renderInContext:c];
    [layer removeFromSuperlayer];
    return c;
}

/* the pixel at (x, y), y counting up from the bottom, by name */
static const char *at(CGContextRef c, int x, int y)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    const unsigned char *p = d + (H - 1 - y) * CGBitmapContextGetBytesPerRow(c) + x * 4;
    static char buf[4][32];
    static int n;
    char *b = buf[n++ % 4];
    struct { const char *n; int r, g, b; } known[] = {
        {"white", 255, 255, 255}, {"red", 255, 0, 0}, {"blue", 0, 0, 255}, {"black", 0, 0, 0},
        {"pink", 255, 128, 128},
    };
    for (size_t i = 0; i < sizeof known / sizeof *known; i++)
        if (abs(p[0] - known[i].r) <= 3 && abs(p[1] - known[i].g) <= 3 && abs(p[2] - known[i].b) <= 3)
            return known[i].n;
    snprintf(b, 32, "%d,%d,%d", p[0], p[1], p[2]);
    return b;
}

/* a 40-point red square in the middle (12 to 52 each way) */
static CALayer *square(void)
{
    CALayer *l = [CALayer layer];
    l.bounds = CGRectMake(0, 0, 40, 40);
    l.position = CGPointMake(32, 32);
    l.backgroundColor = rgb(1, 0, 0, 1);
    return l;
}

static CALayer *mask_rect(CGRect frame, double alpha)
{
    CALayer *m = [CALayer layer];
    m.frame = frame;
    m.backgroundColor = rgb(0, 0, 1, alpha);   /* its colour doesn't count, only how opaque it is */
    return m;
}

int main(void)
{
    @autoreleasepool {
        CALayer *l = square();
        l.mask = mask_rect(CGRectMake(10, 10, 20, 20), 1);
        CGContextRef c = draw(l);
        printf("masked to its middle: middle %s, edge %s\n", at(c, 32, 32), at(c, 15, 32));
        CGContextRelease(c);

        l.mask = mask_rect(CGRectMake(0, 0, 40, 40), 0.5);
        c = draw(l);
        printf("half-opaque mask: %s\n", at(c, 32, 32));
        CGContextRelease(c);

        CAShapeLayer *circle = [CAShapeLayer layer];
        circle.frame = CGRectMake(0, 0, 40, 40);
        circle.path = CGPathCreateWithEllipseInRect(CGRectMake(0, 0, 40, 40), NULL);
        l.mask = circle;
        c = draw(l);
        printf("a circle: middle %s, corner %s\n", at(c, 32, 32), at(c, 14, 14));
        CGContextRelease(c);

        /* sublayers and the border are masked with the layer */
        l = square();
        CALayer *blue = [CALayer layer];
        blue.frame = CGRectMake(0, 0, 40, 10);
        blue.backgroundColor = rgb(0, 0, 1, 1);
        [l addSublayer:blue];
        l.borderWidth = 4;
        l.borderColor = rgb(0, 0, 0, 1);
        l.mask = mask_rect(CGRectMake(10, 0, 20, 35), 1);
        c = draw(l);
        printf("sublayer and border masked: blue kept %s, blue cut %s, border cut %s, border kept %s\n",
               at(c, 32, 19), at(c, 14, 19), at(c, 13, 32), at(c, 32, 13));
        CGContextRelease(c);

        /* the shadow is the masked layer's */
        l = square();
        l.mask = mask_rect(CGRectMake(10, 10, 20, 20), 1);
        l.shadowOpacity = 1;
        l.shadowRadius = 0;
        l.shadowOffset = CGSizeMake(0, -6);
        c = draw(l);
        printf("masked shadow: under the middle %s, under the cut-away part %s\n", at(c, 32, 18), at(c, 32, 9));
        CGContextRelease(c);
    }
    return 0;
}
