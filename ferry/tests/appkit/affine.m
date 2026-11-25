/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0), with no display:
 * NSAffineTransform, as ShiftIt, Hex Fiend and MacDown use it. Translating,
 * rotating and scaling in the documented order, appending and prepending,
 * inverting (and a transform that can't be), points and sizes, copies and
 * archives; then paths: transformed in place and as a copy, their elements
 * and points read back, an index past the end,
 * polylines and arcs between lines; and -concat and -set drawing into a
 * bitmap. */
#import <Cocoa/Cocoa.h>

static void st(const char *label, NSAffineTransform *t)
{
    NSAffineTransformStruct s = [t transformStruct];
    printf("%s: %g %g %g %g %g %g\n", label, s.m11 + 0.0, s.m12 + 0.0, s.m21 + 0.0, s.m22 + 0.0, s.tX + 0.0,
           s.tY + 0.0);
}
static void pt(const char *label, NSPoint p) { printf("%s: (%.3g, %.3g)\n", label, p.x + 0.0, p.y + 0.0); }

static void elements(const char *label, NSBezierPath *p)
{
    printf("%s (%ld):", label, (long)[p elementCount]);
    for (NSInteger i = 0; i < [p elementCount]; i++) {
        NSPoint pts[3];
        NSBezierPathElement e = [p elementAtIndex:i associatedPoints:pts];
        switch (e) {
        case NSBezierPathElementMoveTo: printf(" M %g,%g", pts[0].x, pts[0].y); break;
        case NSBezierPathElementLineTo: printf(" L %g,%g", pts[0].x, pts[0].y); break;
        case NSBezierPathElementCurveTo:
            printf(" C %.4g,%.4g %.4g,%.4g %g,%g", pts[0].x, pts[0].y, pts[1].x, pts[1].y, pts[2].x, pts[2].y);
            break;
        case NSBezierPathElementClosePath: printf(" Z"); break;
        default: printf(" ?"); break;
        }
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSAffineTransform *t = [NSAffineTransform transform];
        st("identity", t);
        [t translateXBy:10 yBy:20];
        [t scaleBy:2];
        pt("translate then scale (1, 1)", [t transformPoint:NSMakePoint(1, 1)]);
        NSAffineTransform *r = [NSAffineTransform transform];
        [r rotateByDegrees:90];
        st("rotate 90", r);
        pt("rotated (1, 0)", [r transformPoint:NSMakePoint(1, 0)]);
        NSAffineTransform *a = [[NSAffineTransform alloc] initWithTransform:t];
        [a appendTransform:r];
        pt("append rotation (1, 1)", [a transformPoint:NSMakePoint(1, 1)]);
        NSAffineTransform *b = [[NSAffineTransform alloc] initWithTransform:t];
        [b prependTransform:r];
        pt("prepend rotation (1, 1)", [b transformPoint:NSMakePoint(1, 1)]);
        NSAffineTransform *inv = [a copy];
        [inv invert];
        pt("inverse undoes it", [inv transformPoint:[a transformPoint:NSMakePoint(3, -4)]]);
        NSAffineTransform *flat = [NSAffineTransform transform];
        [flat scaleXBy:0 yBy:1];
        [flat invert];
        st("a flat transform isn't inverted", flat);
        NSAffineTransform *s = [NSAffineTransform transform];
        [s scaleXBy:2 yBy:3];
        [s translateXBy:5 yBy:5];
        NSSize sz = [s transformSize:NSMakeSize(1, 1)];
        printf("size (1, 1) scaled: (%g, %g), translation ignored\n", sz.width, sz.height);
        st("scale then translate", s);
        NSData *arch = [NSKeyedArchiver archivedDataWithRootObject:s requiringSecureCoding:YES error:NULL];
        NSAffineTransform *back = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSAffineTransform class] fromData:arch
                                                                       error:NULL];
        printf("archived and back equal: %s, copy equal: %s\n", [back isEqual:s] ? "yes" : "no",
               [[s copy] isEqual:s] ? "yes" : "no");
        NSAffineTransformStruct raw = {1, 0, 0, 1, 7, 8};
        [s setTransformStruct:raw];
        pt("set from a struct (0, 0)", [s transformPoint:NSZeroPoint]);

        /* Paths. */
        NSBezierPath *p = [NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, 10, 10)];
        NSAffineTransform *move = [NSAffineTransform transform];
        [move translateXBy:100 yBy:50];
        NSBezierPath *moved = [move transformBezierPath:p];
        printf("copy moved to (%g, %g), original still at (%g, %g)\n", [moved bounds].origin.x, [moved bounds].origin.y,
               [p bounds].origin.x, [p bounds].origin.y);
        [p transformUsingAffineTransform:r];
        NSRect rb = [p bounds];
        printf("rotated in place: (%g, %g) %g x %g\n", rb.origin.x + 0.0, rb.origin.y + 0.0, rb.size.width,
               rb.size.height);
        elements("rectangle", [NSBezierPath bezierPathWithRect:NSMakeRect(1, 2, 3, 4)]);
        NSBezierPath *c = [NSBezierPath bezierPath];
        [c moveToPoint:NSMakePoint(0, 0)];
        [c curveToPoint:NSMakePoint(10, 0) controlPoint1:NSMakePoint(0, 5) controlPoint2:NSMakePoint(10, 5)];
        [c closePath];
        elements("curve", c);
        printf("element 0 of the curve is a move: %s\n",
               [c elementAtIndex:0] == NSBezierPathElementMoveTo ? "yes" : "no");
        @try {
            [c elementAtIndex:9];
            printf("past the end: no exception\n");
        } @catch (NSException *e) {
            printf("past the end: %s\n", [[e name] UTF8String]);
        }
        NSPoint poly[] = {{0, 0}, {5, 0}, {5, 5}};
        NSBezierPath *pl = [NSBezierPath bezierPath];
        [pl appendBezierPathWithPoints:poly count:3];
        elements("polyline", pl);
        NSBezierPath *corner = [NSBezierPath bezierPath];
        [corner moveToPoint:NSMakePoint(0, 0)];
        [corner appendBezierPathWithArcFromPoint:NSMakePoint(10, 0) toPoint:NSMakePoint(10, 10) radius:2];
        NSRect cb = [corner bounds];
        printf("rounded corner: %ld elements, ends at (%g, %g), bounds to x %g\n", (long)[corner elementCount],
               [corner currentPoint].x, [corner currentPoint].y, NSMaxX(cb));
        @try {
            [[NSBezierPath bezierPath] appendBezierPathWithArcFromPoint:NSMakePoint(1, 0) toPoint:NSMakePoint(1, 1)
                                                                 radius:1];
            printf("an arc with no current point: no exception\n");
        } @catch (NSException *e) {
            printf("an arc with no current point: %s\n", [[e name] UTF8String]);
        }

        /* Drawing through a transform. */
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:20 pixelsHigh:20
                                                                     bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        NSAffineTransform *shift = [NSAffineTransform transform];
        [shift translateXBy:10 yBy:10];
        [shift concat];
        [[NSColor redColor] set];
        NSRectFill(NSMakeRect(0, 0, 5, 5));
        NSAffineTransform *home = [NSAffineTransform transform];
        [home set];
        [[NSColor blueColor] set];
        NSRectFill(NSMakeRect(0, 0, 5, 5));
        [NSGraphicsContext restoreGraphicsState];
        NSColor *hi = [rep colorAtX:12 y:7], *lo = [rep colorAtX:2 y:17], *none = [rep colorAtX:17 y:17];
        printf("concat drew red at the shifted place: %s; set put blue back at the origin: %s; elsewhere clear: %s\n",
               [hi redComponent] > 0.9 && [hi blueComponent] < 0.1 ? "yes" : "no",
               [lo blueComponent] > 0.9 && [lo redComponent] < 0.1 ? "yes" : "no", [none alphaComponent] < 0.1 ? "yes" : "no");
    }
    return 0;
}
