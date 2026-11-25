/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.221, Ferry 0.45.0): Core Graphics functions and
 * shadings, as Sequel Pro's tab bar draws its tabs: an axial shading from
 * a function of the program's, extended past one end and not the other, a
 * radial one, a function's range clamping its colours, and the function's
 * info released with it. Checked pixel by pixel in a bitmap context. */
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

#define W 100
#define H 20

static int calls, released;

/* red rising from 0 to 1 across the domain, blue falling, opaque */
static void ramp(void *info, const CGFloat *in, CGFloat *out)
{
    calls++;
    CGFloat t = in[0];
    out[0] = t;
    out[1] = 0;
    out[2] = 1 - t;
    out[3] = 1;
}
/* asks for too much green, which the range keeps to a half */
static void green(void *info, const CGFloat *in, CGFloat *out)
{
    out[0] = 0;
    out[1] = 2;
    out[2] = 0;
    out[3] = 1;
}
static void release_info(void *info) { released += *(int *)info; }

static void show(CGContextRef c, const char *what, int x, int y)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    const unsigned char *p = d + (H - 1 - y) * CGBitmapContextGetBytesPerRow(c) + x * 4;
    printf("%s (%d,%d): %3d %3d %3d %3d\n", what, x, y, p[0], p[1], p[2], p[3]);
}

int main(void)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    int weight = 1;
    CGFloat domain[2] = {0, 1};
    CGFunctionCallbacks cb = {0, ramp, release_info};
    CGFunctionRef f = CGFunctionCreate(&weight, 1, domain, 4, NULL, &cb);

    /* from x 20 to x 80, extended before the start only */
    CGShadingRef axial = CGShadingCreateAxial(rgb, CGPointMake(20, 0), CGPointMake(80, 0), f, true, false);
    CGContextDrawShading(c, axial);
    printf("the function was asked %s\n", calls > 2 ? "at many points" : "too few times");
    show(c, "before the start, extended", 5, 10);
    show(c, "start", 21, 10);
    show(c, "middle", 50, 10);
    show(c, "end", 79, 10);
    show(c, "after the end, not extended", 95, 10);

    /* a radial shading, within a clip */
    CGContextClearRect(c, CGRectMake(0, 0, W, H));
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(0, 0, 50, H));
    CGShadingRef radial = CGShadingCreateRadial(rgb, CGPointMake(25, 10), 0, CGPointMake(25, 10), 20, f, false, true);
    CGContextDrawShading(c, radial);
    CGContextRestoreGState(c);
    show(c, "radial centre", 25, 10);
    show(c, "radial edge", 44, 10);
    show(c, "outside the clip", 75, 10);

    /* the range clamps what the function gives */
    CGFloat range[8] = {0, 1, 0, 0.5, 0, 1, 0, 1};
    CGFunctionCallbacks gcb = {0, green, NULL};
    CGFunctionRef g = CGFunctionCreate(NULL, 1, domain, 4, range, &gcb);
    CGShadingRef flat = CGShadingCreateAxial(rgb, CGPointMake(0, 0), CGPointMake(W, 0), g, true, true);
    CGContextDrawShading(c, flat);
    show(c, "clamped green", 50, 10);

    CGShadingRelease(axial);
    CGShadingRelease(radial);
    CGShadingRelease(flat);
    CGFunctionRelease(g);
    printf("info released while shadings hold the function: %d\n", released);
    CGFunctionRelease(f);
    printf("info released after: %d\n", released);
    CGContextRelease(c);
    CGColorSpaceRelease(rgb);
    return 0;
}
