/* SPDX-License-Identifier: GPL-3.0-or-later
 * Layer shadows (freemac 1.253, Ferry 0.76.0), drawn with renderInContext:
 * into a bitmap context and checked pixel by pixel: a layer casts its
 * shadow from all it draws taken as one (a sublayer's shape, not the
 * layer's empty bounds), at shadowOpacity, moved by shadowOffset (down for
 * a negative height, as on a Mac) and blurred by shadowRadius; with a
 * shadowPath, from that path. */
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

/* the red value at (x, y), y counting up from the bottom: 255 white or red,
 * 0 black */
static int red(CGContextRef c, int x, int y)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    return d[(H - 1 - y) * CGBitmapContextGetBytesPerRow(c) + x * 4];
}

/* a 20-point red square in the middle (22 to 42 each way) */
static CALayer *square(void)
{
    CALayer *l = [CALayer layer];
    l.bounds = CGRectMake(0, 0, 20, 20);
    l.position = CGPointMake(32, 32);
    l.backgroundColor = rgb(1, 0, 0, 1);
    return l;
}

int main(void)
{
    @autoreleasepool {
        CALayer *l = square();
        CGContextRef c = draw(l);
        printf("no shadow: below %d\n", red(c, 32, 18));
        CGContextRelease(c);

        l.shadowOpacity = 1;
        l.shadowRadius = 0;
        l.shadowOffset = CGSizeMake(0, -6);
        c = draw(l);
        printf("shadow 6 down: below %d, square %d, above %d, beside %d\n", red(c, 32, 18), red(c, 32, 32),
               red(c, 32, 45), red(c, 19, 30));
        CGContextRelease(c);

        l.shadowOpacity = 0.5;
        c = draw(l);
        int half = red(c, 32, 18);
        printf("at half opacity, below is grey: %d\n", half > 100 && half < 155);
        CGContextRelease(c);

        l.shadowOpacity = 1;
        l.shadowOffset = CGSizeZero;
        l.shadowRadius = 4;
        c = draw(l);
        int near = red(c, 43, 32), far = red(c, 56, 32);
        printf("blurred by 4: just outside grey %d, far out %d\n", near > 20 && near < 235, far);
        CGContextRelease(c);

        l.shadowRadius = 0;
        l.shadowPath = CGPathCreateWithRect(CGRectMake(-4, -4, 28, 28), NULL);
        c = draw(l);
        printf("a larger shadow path: 2 left of the square %d, square %d\n", red(c, 20, 32), red(c, 32, 32));
        CGContextRelease(c);

        /* a layer with nothing of its own casts its sublayer's shadow */
        CALayer *box = [CALayer layer];
        box.bounds = CGRectMake(0, 0, 40, 40);
        box.position = CGPointMake(32, 32);
        box.shadowOpacity = 1;
        box.shadowRadius = 0;
        box.shadowOffset = CGSizeMake(0, -6);
        CALayer *dot = [CALayer layer];
        dot.frame = CGRectMake(15, 15, 10, 10);
        dot.backgroundColor = rgb(0, 1, 0, 1);
        [box addSublayer:dot];
        c = draw(box);
        printf("sublayer's shadow: under the dot %d, under the empty box %d\n", red(c, 32, 24), red(c, 16, 14));
        CGContextRelease(c);

        /* the layer's own opacity fades its shadow too */
        l = square();
        l.shadowOpacity = 1;
        l.shadowRadius = 0;
        l.shadowOffset = CGSizeMake(0, -6);
        l.opacity = 0.5;
        c = draw(l);
        int faded = red(c, 32, 18);
        printf("layer at half opacity, shadow grey: %d\n", faded > 100 && faded < 155);
        CGContextRelease(c);
    }
    return 0;
}
