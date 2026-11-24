/* Ferry test (freemac 1.213, Ferry 0.39.0): shadows drawn by Core
 * Graphics, checked pixel by pixel in bitmap contexts. Each shape, image,
 * gradient and line of text drawn while a shadow is set gets a copy under
 * it, moved by the offset in base space and blurred. Only pixels well
 * inside a shape or its shadow are checked exactly; blurred edges are
 * checked for the way they fall off. */
#import <Foundation/Foundation.h>
#include <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define W 80
#define H 60

static CGColorSpaceRef rgb;

static CGContextRef canvas(void)
{
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    return c;
}

/* The pixel at (x, y), y counting up from the bottom. */
static const unsigned char *pixel(CGContextRef c, int x, int y)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    return d + (CGBitmapContextGetHeight(c) - 1 - y) * CGBitmapContextGetBytesPerRow(c) +
           x * (CGBitmapContextGetBitsPerPixel(c) / 8);
}

static void show(const char *what, CGContextRef c, int x, int y)
{
    const unsigned char *p = pixel(c, x, y);
    printf("  %s: %d %d %d %d\n", what, p[0], p[1], p[2], p[3]);
}

static const char *near(int v, int want) { return abs(v - want) <= 2 ? "ok" : "off"; }

/* Pixels darker than white in a rectangle, y up. */
static int shaded(CGContextRef c, int x0, int y0, int x1, int y1)
{
    int n = 0;
    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++)
            if (pixel(c, x, y)[0] < 250)
                n++;
    return n;
}

int main(void)
{
    @autoreleasepool {
        rgb = CGColorSpaceCreateDeviceRGB();

        printf("a filled rectangle, offset (5, -5), no blur, the default colour\n");
        CGContextRef c = canvas();
        CGContextSetShadow(c, CGSizeMake(5, -5), 0);
        CGContextSetRGBFillColor(c, 1, 0, 0, 1);
        CGContextFillRect(c, CGRectMake(10, 30, 20, 20));
        show("inside the rectangle", c, 20, 40);
        show("in the shadow, right of it", c, 32, 40);
        show("in the shadow, below it", c, 20, 27);
        show("left of the rectangle", c, 7, 40);
        show("above the rectangle", c, 20, 52);
        const unsigned char *p = pixel(c, 32, 40);
        printf("  black at a third over white: %s\n", near(p[0], 170));
        CGContextRelease(c);

        printf("a shadow turned off with no colour, and one kept by the graphics state\n");
        c = canvas();
        CGContextSaveGState(c);
        CGContextSetShadow(c, CGSizeMake(5, -5), 0);
        CGContextSetShadowWithColor(c, CGSizeMake(5, -5), 0, NULL);
        CGContextSetRGBFillColor(c, 0, 0, 1, 1);
        CGContextFillRect(c, CGRectMake(10, 30, 20, 20));
        show("no colour, no shadow", c, 32, 40);
        CGContextSetShadow(c, CGSizeMake(5, -5), 0);
        CGContextSaveGState(c);
        CGContextRestoreGState(c);
        CGContextFillRect(c, CGRectMake(45, 30, 20, 20));
        show("set before a save and restore", c, 67, 40);
        CGContextRestoreGState(c);
        CGContextFillRect(c, CGRectMake(10, 2, 20, 20));
        show("after the restore that ends it", c, 32, 10);
        CGContextRelease(c);

        printf("a shadow in a colour of its own, half transparent\n");
        c = canvas();
        CGColorRef green = CGColorCreateGenericRGB(0, 0.5, 0, 0.5);
        CGContextSetShadowWithColor(c, CGSizeMake(0, -8), 0, green);
        CGColorRelease(green);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1);
        CGContextFillRect(c, CGRectMake(10, 30, 20, 20));
        p = pixel(c, 20, 26);
        printf("  under the rectangle: %d %d %d (%s %s %s)\n", p[0], p[1], p[2], near(p[0], 128), near(p[1], 191),
               near(p[2], 128));
        CGContextRelease(c);

        printf("the offset is in base space, whatever the transform\n");
        c = canvas();
        CGContextTranslateCTM(c, 10, 10);
        CGContextScaleCTM(c, 2, 2);
        CGContextSetShadow(c, CGSizeMake(6, 0), 0);
        CGContextSetRGBFillColor(c, 1, 0, 0, 1);
        CGContextFillRect(c, CGRectMake(0, 0, 10, 10));   /* covers 10..30 in both directions */
        show("6 pixels right of the scaled rectangle", c, 34, 20);
        show("9 pixels right of it", c, 38, 20);
        CGContextRelease(c);

        printf("a blurred shadow falls off away from the shape\n");
        c = canvas();
        CGContextSetShadowWithColor(c, CGSizeZero, 8, CGColorGetConstantColor(kCGColorBlack));
        CGContextSetRGBFillColor(c, 1, 1, 1, 1);
        CGContextFillRect(c, CGRectMake(30, 20, 20, 20));
        int v[6];
        for (int i = 0; i < 6; i++)
            v[i] = pixel(c, 50 + i * 2, 30)[0];
        printf("  from the edge outwards:");
        for (int i = 0; i < 6; i++)
            printf(" %s", i == 0 ? "" : v[i] > v[i - 1] ? "lighter" : v[i] == v[i - 1] ? "same" : "darker");
        printf("\n  just outside the edge is grey: %s, 12 pixels out is white: %s\n",
               v[0] > 60 && v[0] < 220 ? "yes" : "no", pixel(c, 62, 30)[0] >= 250 ? "yes" : "no");
        show("inside the shape, still white", c, 40, 30);
        int sides[4] = {pixel(c, 27, 30)[0], pixel(c, 52, 30)[0], pixel(c, 40, 17)[0], pixel(c, 40, 42)[0]};
        printf("  the same on every side: %s\n",
               abs(sides[0] - sides[1]) <= 2 && abs(sides[0] - sides[2]) <= 2 && abs(sides[0] - sides[3]) <= 2 ? "yes"
                                                                                                                 : "no");
        CGContextRelease(c);

        printf("strokes, images, gradients and text cast shadows too\n");
        c = canvas();
        CGContextSetShadow(c, CGSizeMake(0, -6), 0);
        CGContextSetRGBStrokeColor(c, 0, 0, 1, 1);
        CGContextSetLineWidth(c, 4);
        CGContextStrokeRect(c, CGRectMake(10, 30, 20, 20));
        show("under the stroke's bottom edge", c, 20, 24);
        show("in the stroke's hollow middle, its top edge's shadow", c, 20, 44);
        show("in the hollow middle, away from the edges", c, 20, 38);
        CGContextRelease(c);

        CGContextRef src = CGBitmapContextCreate(NULL, 4, 4, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(src, 0, 1, 0, 1);
        CGContextFillRect(src, CGRectMake(0, 0, 4, 4));
        CGImageRef image = CGBitmapContextCreateImage(src);
        CGContextRelease(src);
        c = canvas();
        CGContextSetShadow(c, CGSizeMake(10, 0), 0);
        CGContextDrawImage(c, CGRectMake(10, 10, 20, 20), image);
        show("the image", c, 20, 20);
        show("its shadow", c, 35, 20);
        CGImageRelease(image);
        CGContextRelease(c);

        c = canvas();
        CGContextSetShadow(c, CGSizeMake(10, 0), 0);
        CGFloat comps[] = {1, 0, 0, 1, 0, 0, 1, 1};
        CGGradientRef g = CGGradientCreateWithColorComponents(rgb, comps, NULL, 2);
        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(10, 10, 20, 20));
        CGContextDrawLinearGradient(c, g, CGPointMake(10, 0), CGPointMake(30, 0), 0);
        CGContextRestoreGState(c);
        show("a gradient's middle", c, 20, 20);
        show("beside it, inside the clip it was drawn in: no room for a shadow", c, 35, 20);
        CGContextDrawLinearGradient(c, g, CGPointMake(10, 0), CGPointMake(30, 0), 0);
        show("the same gradient unclipped, a band from 10 to 30: its shadow", c, 35, 20);
        show("past the shadow", c, 45, 20);
        CGGradientRelease(g);
        CGContextRelease(c);

        c = CGBitmapContextCreate(NULL, 160, 60, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(c, 1, 1, 1, 1);
        CGContextFillRect(c, CGRectMake(0, 0, 160, 60));
        CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica-Bold"), 28, NULL);
        NSDictionary *attrs = @{(id)kCTFontAttributeName : (__bridge id)font};
        NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"HHHH" attributes:attrs];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
        CGContextSetTextPosition(c, 10, 30);
        CTLineDraw(line, c);
        int plain = shaded(c, 0, 0, 160, 30);
        CGContextSetRGBFillColor(c, 1, 1, 1, 1);
        CGContextFillRect(c, CGRectMake(0, 0, 160, 60));
        CGContextSetShadow(c, CGSizeMake(0, -20), 0);
        CGContextSetTextPosition(c, 10, 30);
        CTLineDraw(line, c);
        int with = shaded(c, 0, 0, 160, 30);
        printf("  text: grey below the baseline without a shadow: %s, with one: %s\n", plain < 20 ? "little" : "much",
               with > 200 ? "much" : "little");
        CFRelease(line);
        CFRelease(font);
        CGContextRelease(c);

        printf("a transparency layer casts one shadow for all it holds\n");
        c = canvas();
        CGContextSetShadow(c, CGSizeMake(0, -10), 0);
        CGContextBeginTransparencyLayer(c, NULL);
        CGContextSetRGBFillColor(c, 1, 0, 0, 1);
        CGContextFillRect(c, CGRectMake(10, 30, 20, 20));
        CGContextFillRect(c, CGRectMake(20, 30, 20, 20));
        CGContextEndTransparencyLayer(c);
        p = pixel(c, 25, 25);
        printf("  under the overlap, one shadow's grey: %s\n", near(p[0], 170));
        show("a shape in the layer", c, 25, 40);
        CGContextRelease(c);

        printf("an alpha-only context\n");
        c = CGBitmapContextCreate(NULL, W, H, 8, 0, NULL, kCGImageAlphaOnly);
        CGContextSetShadow(c, CGSizeMake(5, 0), 0);
        CGContextFillRect(c, CGRectMake(10, 10, 20, 20));
        const unsigned char *a = CGBitmapContextGetData(c);
        size_t bpr = CGBitmapContextGetBytesPerRow(c);
        printf("  the shape: %d, its shadow: %d, outside: %d\n", a[(H - 1 - 20) * bpr + 20], a[(H - 1 - 20) * bpr + 32],
               a[(H - 1 - 20) * bpr + 40]);
        CGContextRelease(c);

        CGColorSpaceRelease(rgb);
    }
    return 0;
}
