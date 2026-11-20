/* Ferry M3 test: drawing into bitmap contexts, checked pixel by pixel. Only
 * the inside of shapes is checked, never their antialiased edges. */
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 64
#define H 48

static CGColorSpaceRef rgb;

/* An RGBA context (the layout most Mac code asks for), cleared to white. */
static CGContextRef rgba_context(void)
{
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    return c;
}

/* The pixel at (x, y) in Core Graphics' coordinates: y counts up from the bottom. */
static const unsigned char *pixel(CGContextRef c, int x, int y)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    return d + (CGBitmapContextGetHeight(c) - 1 - y) * CGBitmapContextGetBytesPerRow(c) +
           x * (CGBitmapContextGetBitsPerPixel(c) / 8);
}

static void show(const char *what, CGContextRef c, int x, int y)
{
    const unsigned char *p = pixel(c, x, y);
    printf("%s: %d %d %d %d\n", what, p[0], p[1], p[2], p[3]);
}

static const char *near(int v, int want) { return abs(v - want) <= 3 ? "ok" : "off"; }

static void path_element(void *info, const CGPathElement *e)
{
    static const char *names[] = {"move", "line", "quad", "curve", "close"};
    int n = e->type == kCGPathElementAddCurveToPoint ? 3 : e->type == kCGPathElementAddQuadCurveToPoint ? 2
            : e->type == kCGPathElementCloseSubpath ? 0 : 1;
    printf(" %s", names[e->type]);
    if (n)
        printf("(%g,%g)", round(e->points[n - 1].x * 100) / 100 + 0.0, round(e->points[n - 1].y * 100) / 100 + 0.0);
}

static const unsigned char png[] = {0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x03,0x00,0x00,0x00,0x02,0x08,0x06,0x00,0x00,0x00,0x9d,0x74,0x66,0x1a,0x00,0x00,0x00,0x17,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0xf8,0xcf,0xc0,0xf0,0x1f,0x0c,0x19,0xfe,0x03,0x49,0x20,0x60,0x80,0x80,0x06,0x00,0x9b,0xfe,0x0a,0x77,0x8e,0xf5,0x04,0xa2,0x00,0x00,0x00,0x00,0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82};

int main(void)
{
    rgb = CGColorSpaceCreateDeviceRGB();

    /* Shapes, colours and the y-up coordinate system. */
    CGContextRef c = rgba_context();
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 20, 10));            /* bottom left */
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillEllipseInRect(c, CGRectMake(30, 20, 30, 20));
    CGContextSetRGBStrokeColor(c, 0, 0.5, 0, 1);
    CGContextSetLineWidth(c, 4);
    CGContextMoveToPoint(c, 0, 40);
    CGContextAddLineToPoint(c, 25, 40);
    CGContextStrokePath(c);
    show("rect, bottom left", c, 5, 5);
    show("rect is not at the top", c, 5, H - 5);
    show("ellipse centre", c, 45, 30);
    show("outside ellipse corner", c, 31, 21);
    show("stroked line", c, 12, 40);
    show("background", c, 40, 5);

    /* Half-transparent fill over white, and a global alpha. */
    CGContextSetRGBFillColor(c, 0, 0, 0, 0.5);
    CGContextFillRect(c, CGRectMake(40, 0, 10, 10));
    printf("half black over white: %s\n", near(pixel(c, 45, 5)[0], 127));
    CGContextSetAlpha(c, 0.25);
    CGContextSetRGBFillColor(c, 0, 0, 0, 1);
    CGContextFillRect(c, CGRectMake(52, 0, 10, 10));
    printf("quarter alpha: %s\n", near(pixel(c, 57, 5)[0], 191));
    CGContextSetAlpha(c, 1);

    /* Save and restore, transforms. */
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 20, 0);
    CGContextScaleCTM(c, 2, 2);
    CGAffineTransform ctm = CGContextGetCTM(c);
    printf("ctm: %g %g %g %g %g %g\n", ctm.a, ctm.b, ctm.c, ctm.d, ctm.tx, ctm.ty);
    CGContextSetRGBFillColor(c, 0, 1, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 6, 4, 4));   /* lands on 20..28, 12..20 */
    CGContextRestoreGState(c);
    show("scaled square", c, 24, 16);
    show("fill colour restored", c, 1, 1);
    ctm = CGContextGetCTM(c);
    printf("ctm restored: %g %g %g %g %g %g\n", ctm.a, ctm.b, ctm.c, ctm.d, ctm.tx, ctm.ty);
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 10, 30);
    CGContextRotateCTM(c, M_PI / 2);
    CGContextSetRGBFillColor(c, 1, 1, 0, 1);
    CGContextFillRect(c, CGRectMake(2, 2, 6, 4));  /* rotated: x 4..8, y 32..38 */
    CGContextRestoreGState(c);
    show("rotated rect", c, 6, 35);
    CGContextRelease(c);

    /* Clipping, and the clip being undone by restore. */
    c = rgba_context();
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(10, 10, 10, 10));
    CGRect clip = CGContextGetClipBoundingBox(c);
    printf("clip box: %g %g %g %g\n", clip.origin.x, clip.origin.y, clip.size.width, clip.size.height);
    CGContextSetRGBFillColor(c, 0, 0, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    CGContextRestoreGState(c);
    show("inside clip", c, 15, 15);
    show("outside clip", c, 25, 15);
    /* even-odd: a ring */
    CGContextAddEllipseInRect(c, CGRectMake(30, 4, 30, 30));
    CGContextAddEllipseInRect(c, CGRectMake(40, 14, 10, 10));
    CGContextSetRGBFillColor(c, 1, 0, 1, 1);
    CGContextEOFillPath(c);
    show("ring", c, 34, 19);
    show("ring hole", c, 45, 19);
    printf("path empty after fill: %d\n", CGContextIsPathEmpty(c));
    /* Clear and copy blend modes */
    CGContextClearRect(c, CGRectMake(0, 40, 8, 8));
    show("cleared", c, 3, 44);
    CGContextRelease(c);

    /* Gradients. */
    c = rgba_context();
    CGFloat comps[] = {0, 0, 0, 1, 1, 1, 1, 1};
    CGGradientRef g = CGGradientCreateWithColorComponents(rgb, comps, NULL, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(W, 0), 0);
    int left = pixel(c, 2, 20)[0], mid = pixel(c, 32, 20)[0], right = pixel(c, 61, 20)[0];
    printf("linear gradient rises: %s, middle about half: %s\n", left < mid && mid < right ? "yes" : "no",
           near(mid, 128));
    CGContextRelease(c);
    c = rgba_context();
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 10), CGPointMake(0, 30), 0);
    printf("not drawn past the end without the option: %s\n", pixel(c, 5, 40)[0] == 255 ? "yes" : "no");
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 10), CGPointMake(0, 30), kCGGradientDrawsBeforeStartLocation);
    printf("drawn before the start with the option: %s\n", pixel(c, 5, 3)[0] == 0 ? "yes" : "no");
    CGContextRelease(c);
    c = rgba_context();
    CGContextDrawRadialGradient(c, g, CGPointMake(32, 24), 0, CGPointMake(32, 24), 20, 0);
    printf("radial centre dark: %s, outside untouched: %s\n", pixel(c, 32, 24)[0] < 20 ? "yes" : "no",
           pixel(c, 2, 2)[0] == 255 ? "yes" : "no");
    CGGradientRelease(g);
    CGContextRelease(c);

    /* Images: a context's image drawn into another keeps its top at the top. */
    CGContextRef src = CGBitmapContextCreate(NULL, 4, 4, 8, 0, rgb, kCGImageAlphaPremultipliedFirst |
                                                                       kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(src, 0, 0, 1, 1);
    CGContextFillRect(src, CGRectMake(0, 0, 4, 4));
    CGContextSetRGBFillColor(src, 1, 0, 0, 1);
    CGContextFillRect(src, CGRectMake(0, 2, 4, 2));   /* top half red */
    CGImageRef im = CGBitmapContextCreateImage(src);
    printf("image: %zu x %zu, %zu bits per pixel, alpha info %d\n", CGImageGetWidth(im), CGImageGetHeight(im),
           CGImageGetBitsPerPixel(im), CGImageGetAlphaInfo(im));
    c = rgba_context();
    CGContextSetInterpolationQuality(c, kCGInterpolationNone);
    CGContextDrawImage(c, CGRectMake(8, 8, 16, 16), im);
    show("image top half", c, 16, 20);
    show("image bottom half", c, 16, 12);
    show("beside image", c, 30, 12);
    CGImageRef part = CGImageCreateWithImageInRect(im, CGRectMake(0, 0, 4, 2));  /* the top rows */
    CGContextDrawImage(c, CGRectMake(40, 8, 8, 8), part);
    show("cropped image is the red part", c, 44, 12);
    CGImageRelease(part);
    CGImageRelease(im);
    CGContextRelease(src);
    CGContextRelease(c);

    /* PNG files, read through Cairo. */
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, png, sizeof png, NULL);
    im = CGImageCreateWithPNGDataProvider(prov, NULL, false, kCGRenderingIntentDefault);
    printf("png: %zu x %zu\n", CGImageGetWidth(im), CGImageGetHeight(im));
    c = CGBitmapContextCreate(NULL, 3, 2, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(c, CGRectMake(0, 0, 3, 2), im);
    show("png top left", c, 0, 1);
    show("png top right", c, 2, 1);
    show("png bottom left", c, 0, 0);
    show("png clear", c, 1, 0);
    show("png half alpha", c, 2, 0);
    CGImageRelease(im);
    CGDataProviderRelease(prov);
    CGContextRelease(c);

    /* Other pixel layouts. */
    unsigned char bgra[4 * 4 * 4];
    memset(bgra, 0, sizeof bgra);
    c = CGBitmapContextCreate(bgra, 4, 4, 8, 16, rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(c, 1, 0.5, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 4, 4));
    printf("BGRA memory: %d %d %d %d\n", bgra[0], bgra[1], bgra[2], bgra[3]);
    CGContextRelease(c);
    unsigned char argb[16 * 4];
    c = CGBitmapContextCreate(argb, 4, 4, 8, 16, rgb, kCGImageAlphaNoneSkipFirst);
    CGContextSetRGBFillColor(c, 1, 0.5, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 4, 4));
    printf("xRGB memory: %d %d %d %d\n", argb[0], argb[1], argb[2], argb[3]);
    CGContextRelease(c);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    unsigned char g8[4 * 4];
    c = CGBitmapContextCreate(g8, 4, 4, 8, 4, gray, kCGImageAlphaNone);
    CGContextSetGrayFillColor(c, 0.5, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 4, 4));
    printf("grey memory: %s\n", near(g8[5], 128));
    CGContextRelease(c);
    unsigned char a8[8 * 2];
    memset(a8, 0, sizeof a8);
    c = CGBitmapContextCreate(a8, 8, 2, 8, 8, NULL, kCGImageAlphaOnly);
    CGContextFillRect(c, CGRectMake(0, 0, 4, 2));
    printf("alpha only: %d %d\n", a8[1], a8[6]);
    CGContextRelease(c);
    CGColorSpaceRelease(gray);
    printf("unsupported layout gives NULL: %s\n",
           CGBitmapContextCreate(NULL, 4, 4, 8, 0, rgb, kCGImageAlphaLast) ? "no" : "yes");

    /* Paths. */
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddRect(p, NULL, CGRectMake(0, 0, 10, 10));
    CGRect r;
    printf("rect path is a rect: %d\n", CGPathIsRect(p, &r) && CGRectEqualToRect(r, CGRectMake(0, 0, 10, 10)));
    CGPathMoveToPoint(p, NULL, 20, 0);
    CGPathAddQuadCurveToPoint(p, NULL, 25, 10, 30, 0);
    CGPathAddArc(p, NULL, 50, 0, 5, 0, M_PI, false);
    CGPathCloseSubpath(p);
    printf("elements:");
    CGPathApply(p, NULL, path_element);
    printf("\n");
    r = CGPathGetBoundingBox(p);
    printf("control-point box: %g %g %g %g\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
    r = CGPathGetPathBoundingBox(p);
    printf("path box: %g %g %g %g\n", round(r.origin.x) + 0.0, round(r.origin.y) + 0.0, round(r.size.width),
           round(r.size.height));
    printf("contains: %d %d %d\n", CGPathContainsPoint(p, NULL, CGPointMake(5, 5), false),
           CGPathContainsPoint(p, NULL, CGPointMake(15, 5), false),
           CGPathContainsPoint(p, NULL, CGPointMake(50, 2), false));
    CGAffineTransform move = CGAffineTransformMakeTranslation(100, 0);
    CGPathRef moved = CGPathCreateCopyByTransformingPath(p, &move);
    printf("moved current point: %g %g, equal to original: %d, copy equal: %d\n", CGPathGetCurrentPoint(moved).x,
           CGPathGetCurrentPoint(moved).y, CGPathEqualToPath(p, moved), CGPathEqualToPath(p, CGPathCreateCopy(p)));
    CGPathRelease(moved);
    CGPathRelease(p);
    p = CGPathCreateMutable();
    CGPathAddRoundedRect(p, NULL, CGRectMake(0, 0, 40, 20), 5, 5);
    printf("rounded rect: centre %d, corner %d\n", CGPathContainsPoint(p, NULL, CGPointMake(20, 10), false),
           CGPathContainsPoint(p, NULL, CGPointMake(0.5, 0.5), false));
    CGPathRelease(p);
    /* the context's own path, copied out */
    c = rgba_context();
    CGContextTranslateCTM(c, 5, 5);
    CGContextAddArcToPoint(c, 0, 0, 0, 0, 0);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, 0, 0);
    CGContextAddLineToPoint(c, 10, 0);
    CGContextAddArcToPoint(c, 20, 0, 20, 10, 5);
    CGPoint cur = CGContextGetPathCurrentPoint(c);
    printf("arc to point ends at: %g %g\n", round(cur.x * 100) / 100 + 0.0, round(cur.y * 100) / 100 + 0.0);
    CGPathRef copy = CGContextCopyPath(c);
    r = CGPathGetBoundingBox(copy);
    printf("copied path box: %g %g %g %g\n", round(r.origin.x) + 0.0, round(r.origin.y) + 0.0, round(r.size.width),
           round(r.size.height));
    CGPathRelease(copy);
    CGContextRelease(c);

    /* Colours. */
    CGColorRef col = CGColorCreateGenericRGB(0.25, 0.5, 0.75, 1);
    const CGFloat *k = CGColorGetComponents(col);
    printf("colour: %zu components %g %g %g %g\n", CGColorGetNumberOfComponents(col), k[0], k[1], k[2], k[3]);
    CGColorRef faded = CGColorCreateCopyWithAlpha(col, 0.5);
    printf("alpha %g, equal %d %d\n", CGColorGetAlpha(faded), CGColorEqualToColor(col, faded),
           CGColorEqualToColor(col, col));
    printf("black: %zu components, model %d\n", CGColorGetNumberOfComponents(CGColorGetConstantColor(kCGColorBlack)),
           CGColorSpaceGetModel(CGColorGetColorSpace(CGColorGetConstantColor(kCGColorBlack))));
    CGColorRelease(faded);
    CGColorRelease(col);
    CGColorSpaceRelease(rgb);
    return 0;
}
