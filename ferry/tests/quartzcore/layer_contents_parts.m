/* SPDX-License-Identifier: GPL-3.0-or-later
 * A part of a layer's image (contentsRect) and an image stretched in nine
 * parts (contentsCenter) (freemac 1.255, Ferry 0.78.0), drawn with
 * renderInContext: and checked pixel by pixel. The unit space of both is
 * the layer's own: y = 0 is the image's bottom, or its top where the layer
 * is drawn flipped. */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

#define W 80
#define H 80

static CGContextRef bitmap(int w, int h)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    return c;
}

static void fill(CGContextRef c, double r, double g, double b, CGRect rect)
{
    CGContextSetRGBFillColor(c, r, g, b, 1);
    CGContextFillRect(c, rect);
}

/* a picture of n-pixel blocks, three by three: corners red (top left), blue
 * (top right), green (bottom left) and black; edges grey; the middle pink */
static CGImageRef nine(int n)
{
    CGContextRef c = bitmap(3 * n, 3 * n);
    fill(c, 0.5, 0.5, 0.5, CGRectMake(0, 0, 3 * n, 3 * n));
    fill(c, 1, 0, 1, CGRectMake(n, n, n, n));
    fill(c, 0, 1, 0, CGRectMake(0, 0, n, n));          /* bottom left: y counts up here */
    fill(c, 0, 0, 0, CGRectMake(2 * n, 0, n, n));
    fill(c, 1, 0, 0, CGRectMake(0, 2 * n, n, n));
    fill(c, 0, 0, 1, CGRectMake(2 * n, 2 * n, n, n));
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return img;
}

static CGContextRef draw(CALayer *layer, BOOL flipped)
{
    CGContextRef c = bitmap(W, H);
    fill(c, 1, 1, 1, CGRectMake(0, 0, W, H));
    CALayer *root = [CALayer layer];
    root.frame = CGRectMake(0, 0, W, H);
    root.geometryFlipped = flipped;
    [root addSublayer:layer];
    [root renderInContext:c];
    [layer removeFromSuperlayer];
    return c;
}

/* the colour seen at (x, y) on the page, y counting up from the bottom */
static const char *at(CGContextRef c, int x, int y)
{
    const unsigned char *p = (const unsigned char *)CGBitmapContextGetData(c) +
                             (H - 1 - y) * CGBitmapContextGetBytesPerRow(c) + x * 4;
    struct { const char *n; int r, g, b; } known[] = {
        {"white", 255, 255, 255}, {"red", 255, 0, 0}, {"blue", 0, 0, 255}, {"green", 0, 255, 0},
        {"black", 0, 0, 0}, {"grey", 128, 128, 128}, {"pink", 255, 0, 255},
    };
    for (size_t i = 0; i < sizeof known / sizeof *known; i++)
        if (abs(p[0] - known[i].r) <= 3 && abs(p[1] - known[i].g) <= 3 && abs(p[2] - known[i].b) <= 3)
            return known[i].n;
    static char buf[4][32];
    static int k;
    char *b = buf[k++ % 4];
    snprintf(b, 32, "%d,%d,%d", p[0], p[1], p[2]);
    return b;
}

static CALayer *picture(CGImageRef img, CGRect frame)
{
    CALayer *l = [CALayer layer];
    l.frame = frame;
    l.contents = (__bridge id)img;
    return l;
}

int main(void)
{
    @autoreleasepool {
        CGImageRef img = nine(10);

        CALayer *l = picture(img, CGRectMake(10, 10, 60, 60));
        CGContextRef c = draw(l, NO);
        printf("whole image: top left %s, middle %s, bottom right %s\n", at(c, 15, 65), at(c, 40, 40), at(c, 65, 15));
        CGContextRelease(c);

        /* the bottom-left third, filling the layer */
        l.contentsRect = CGRectMake(0, 0, 1.0 / 3, 1.0 / 3);
        c = draw(l, NO);
        printf("bottom-left third: corners %s and %s\n", at(c, 12, 68), at(c, 68, 12));
        CGContextRelease(c);

        /* the top half's middle third, on a flipped page: y counts down */
        l.contentsRect = CGRectMake(1.0 / 3, 0, 1.0 / 3, 1.0 / 3);
        c = draw(l, YES);
        printf("flipped, top-middle third: %s\n", at(c, 40, 40));
        CGContextRelease(c);

        /* the right two thirds kept at their size, placed top left */
        l.contentsRect = CGRectMake(1.0 / 3, 0, 2.0 / 3, 1);
        l.contentsGravity = kCAGravityTopLeft;
        c = draw(l, NO);
        printf("right two thirds at the top left: %s, %s; past them %s\n", at(c, 15, 65), at(c, 25, 65), at(c, 35, 65));
        CGContextRelease(c);

        /* nine parts: the corners stay 10 points, the rest stretches */
        l = picture(img, CGRectMake(5, 5, 70, 70));
        l.contentsCenter = CGRectMake(1.0 / 3, 1.0 / 3, 1.0 / 3, 1.0 / 3);
        c = draw(l, NO);
        printf("nine parts: corners %s %s %s %s, inside the corners %s %s, edges %s %s, middle %s %s\n",
               at(c, 7, 72), at(c, 72, 72), at(c, 7, 7), at(c, 72, 7), at(c, 13, 66), at(c, 66, 13),
               at(c, 40, 72), at(c, 7, 40), at(c, 17, 17), at(c, 62, 62));
        CGContextRelease(c);

        /* too small for its corners: they shrink alike */
        l.frame = CGRectMake(30, 30, 10, 10);
        c = draw(l, NO);
        printf("small: %s %s %s %s\n", at(c, 31, 38), at(c, 38, 38), at(c, 31, 31), at(c, 38, 31));
        CGContextRelease(c);

        /* a 2x image: its 20-pixel corners are 10 points */
        CGImageRef sharp = nine(20);
        l = picture(sharp, CGRectMake(10, 10, 60, 60));
        l.contentsScale = 2;
        l.contentsCenter = CGRectMake(1.0 / 3, 1.0 / 3, 1.0 / 3, 1.0 / 3);
        c = draw(l, NO);
        printf("scale 2: corner %s, past it %s\n", at(c, 18, 62), at(c, 22, 58));
        CGContextRelease(c);
        CGImageRelease(sharp);
        CGImageRelease(img);
    }
    return 0;
}
