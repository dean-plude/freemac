/* SPDX-License-Identifier: GPL-3.0-or-later
 * Gradients and shadows, with no display: NSGradient's stops (made from
 * two colours, an array, colours and locations given in any order, and an
 * archive), its interpolated colours, and its drawing into a bitmap: along
 * a line with and without the areas before and after it, in a rectangle
 * at 0, 90, 180 and 45 degrees, in a path (nothing outside it), between
 * circles and from a rectangle's centre; NSShadow's defaults, copies,
 * equality, archives and set (drawn, with nothing said on stderr), and a
 * shadow as a text attribute, the way Spectacle, KeyCastr and Sequel Pro
 * make one, drawn under the text. */
#import <Cocoa/Cocoa.h>

static NSBitmapImageRep *canvas(int w, int h)
{
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8
                                              samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:32];
}
static void draw_into(NSBitmapImageRep *rep, void (^body)(void))
{
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    body();
    [NSGraphicsContext restoreGraphicsState];
}
/* x and y as drawn: y counts up from the bottom row. */
static void pixel(const char *what, NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:[rep pixelsHigh] - 1 - y] getRed:&r green:&g blue:&b alpha:&a];
    printf("%s (%d,%d): %.1f %.1f %.1f %.1f\n", what, x, y, r, g, b, a);
}
static void color(const char *what, NSColor *c)
{
    CGFloat r, g, b, a;
    [c getRed:&r green:&g blue:&b alpha:&a];
    printf("%s: %.2f %.2f %.2f %.2f\n", what, r, g, b, a);
}
static void stops(const char *what, NSGradient *g)
{
    printf("%s: %ld stops:", what, (long)[g numberOfColorStops]);
    for (NSInteger i = 0; i < [g numberOfColorStops]; i++) {
        NSColor *c;
        CGFloat at;
        [g getColor:&c location:&at atIndex:i];
        printf(" %.2f=(%.1f %.1f %.1f)", at, [c redComponent], [c greenComponent], [c blueComponent]);
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSColor *red = [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1];
        NSColor *blue = [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1];
        NSColor *green = [NSColor colorWithSRGBRed:0 green:1 blue:0 alpha:1];

        /* ---- stops and colours ---- */
        NSGradient *rb = [[NSGradient alloc] initWithStartingColor:red endingColor:blue];
        stops("two colours", rb);
        stops("array", [[NSGradient alloc] initWithColors:@[ red, green, blue ]]);
        NSGradient *mixed = [[NSGradient alloc] initWithColorsAndLocations:blue, (CGFloat)1.0, red, (CGFloat)0.0,
                                                                           green, (CGFloat)0.25, nil];
        stops("colours and locations, sorted", mixed);
        CGFloat at[] = {0, 0.5, 2};
        stops("locations held to 0...1",
              [[NSGradient alloc] initWithColors:@[ red, green, blue ] atLocations:at colorSpace:nil]);
        printf("no colours: %s\n", [[NSGradient alloc] initWithColors:@[]] ? "a gradient" : "nil");
        printf("no ending colour: %s\n", [[NSGradient alloc] initWithStartingColor:red endingColor:nil] ? "a gradient" : "nil");
        color("at 0", [rb interpolatedColorAtLocation:0]);
        color("at 0.25", [rb interpolatedColorAtLocation:0.25]);
        color("at 1", [rb interpolatedColorAtLocation:1]);
        color("mixed at 0.125", [mixed interpolatedColorAtLocation:0.125]);
        color("mixed at 0.625", [mixed interpolatedColorAtLocation:0.625]);
        NSGradient *inner = [[NSGradient alloc] initWithColorsAndLocations:red, (CGFloat)0.25, blue, (CGFloat)0.75, nil];
        color("before the first stop", [inner interpolatedColorAtLocation:0.1]);
        color("after the last stop", [inner interpolatedColorAtLocation:0.9]);
        @try {
            [rb getColor:NULL location:NULL atIndex:2];
            printf("index 2: no exception\n");
        } @catch (NSException *e) {
            printf("index 2: %s\n", [[e name] UTF8String]);
        }
        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:mixed requiringSecureCoding:NO error:NULL];
        NSGradient *back = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSGradient class] fromData:archived error:NULL];
        stops("archived and read back", back);
        printf("a copy is the same gradient: %s\n", [rb copy] == rb ? "yes" : "no");

        /* ---- drawing ---- */
        NSBitmapImageRep *line = canvas(20, 4);
        draw_into(line, ^{
            [rb drawFromPoint:NSMakePoint(5, 0) toPoint:NSMakePoint(15, 0) options:0];
        });
        pixel("line, before the start", line, 2, 1);
        pixel("line, the start", line, 5, 1);
        pixel("line, the middle", line, 10, 1);
        pixel("line, after the end", line, 18, 1);
        NSBitmapImageRep *extended = canvas(20, 4);
        draw_into(extended, ^{
            [rb drawFromPoint:NSMakePoint(5, 0) toPoint:NSMakePoint(15, 0)
                      options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
        });
        pixel("extended, before the start", extended, 2, 1);
        pixel("extended, after the end", extended, 18, 1);

        NSBitmapImageRep *rect = canvas(20, 20);
        draw_into(rect, ^{
            [rb drawInRect:NSMakeRect(5, 5, 10, 10) angle:0];
        });
        pixel("0 degrees, left", rect, 5, 10);
        pixel("0 degrees, right", rect, 14, 10);
        pixel("0 degrees, outside the rectangle", rect, 2, 10);
        NSBitmapImageRep *up = canvas(20, 20);
        draw_into(up, ^{
            [rb drawInRect:NSMakeRect(0, 0, 20, 20) angle:90];
        });
        pixel("90 degrees, bottom", up, 10, 0);
        pixel("90 degrees, top", up, 10, 19);
        NSBitmapImageRep *back180 = canvas(20, 20);
        draw_into(back180, ^{
            [rb drawInRect:NSMakeRect(0, 0, 20, 20) angle:180];
        });
        pixel("180 degrees, left", back180, 0, 10);
        pixel("180 degrees, right", back180, 19, 10);
        NSBitmapImageRep *diag = canvas(20, 20);
        draw_into(diag, ^{
            [rb drawInRect:NSMakeRect(0, 0, 20, 20) angle:45];
        });
        pixel("45 degrees, bottom left corner", diag, 0, 0);
        pixel("45 degrees, top right corner", diag, 19, 19);
        pixel("45 degrees, top left corner", diag, 0, 19);

        NSBitmapImageRep *oval = canvas(20, 20);
        draw_into(oval, ^{
            [rb drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 20, 20)] angle:0];
        });
        pixel("in an oval, its middle", oval, 10, 10);
        pixel("in an oval, a corner outside it", oval, 0, 0);

        NSBitmapImageRep *radial = canvas(21, 21);
        draw_into(radial, ^{
            [rb drawInRect:NSMakeRect(0, 0, 21, 21) relativeCenterPosition:NSZeroPoint];
        });
        pixel("radial, the centre", radial, 10, 10);
        pixel("radial, a corner", radial, 0, 0);
        NSBitmapImageRep *moved = canvas(21, 21);
        draw_into(moved, ^{
            [rb drawInRect:NSMakeRect(0, 0, 21, 21) relativeCenterPosition:NSMakePoint(1, 1)];
        });
        pixel("radial to the top right, the centre", moved, 10, 10);
        pixel("radial to the top right, the bottom left", moved, 0, 0);
        @try {
            draw_into(moved, ^{
                [rb drawInRect:NSMakeRect(0, 0, 21, 21) relativeCenterPosition:NSMakePoint(2, 0)];
            });
            printf("relative position 2: no exception\n");
        } @catch (NSException *e) {
            printf("relative position 2: %s\n", [[e name] UTF8String]);
            [NSGraphicsContext restoreGraphicsState];
        }
        NSBitmapImageRep *circles = canvas(20, 20);
        draw_into(circles, ^{
            [rb drawFromCenter:NSMakePoint(10, 10) radius:0 toCenter:NSMakePoint(10, 10) radius:5 options:0];
        });
        pixel("between circles, the centre", circles, 10, 10);
        pixel("between circles, outside the end circle", circles, 0, 0);
        NSBitmapImageRep *solid = canvas(4, 4);
        draw_into(solid, ^{
            [[[NSGradient alloc] initWithColors:@[ green ]] drawInRect:NSMakeRect(0, 0, 4, 4) angle:0];
        });
        pixel("one colour", solid, 2, 2);

        /* ---- shadows ---- */
        NSShadow *s = [[NSShadow alloc] init];
        printf("shadow: offset %g,%g blur %g\n", [s shadowOffset].width, [s shadowOffset].height, [s shadowBlurRadius]);
        color("shadow colour", [s shadowColor]);
        [s setShadowOffset:NSMakeSize(1, -1)];
        [s setShadowBlurRadius:2];
        [s setShadowColor:[NSColor colorWithCalibratedWhite:1 alpha:0.5]];
        NSShadow *copy = [s copy];
        printf("copy equal: %s, then changed: ", [copy isEqual:s] ? "yes" : "no");
        [copy setShadowBlurRadius:3];
        printf("%s\n", [copy isEqual:s] ? "equal" : "not equal");
        [s setShadowBlurRadius:-4];
        printf("a blur below 0: %g\n", [s shadowBlurRadius]);
        NSData *sdata = [NSKeyedArchiver archivedDataWithRootObject:copy requiringSecureCoding:NO error:NULL];
        NSShadow *sback = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSShadow class] fromData:sdata error:NULL];
        printf("archived shadow: offset %g,%g blur %g, equal %s\n", [sback shadowOffset].width,
               [sback shadowOffset].height, [sback shadowBlurRadius], [sback isEqual:copy] ? "yes" : "no");
        [s setShadowColor:nil];
        printf("no colour: %s\n", [s shadowColor] ? "a colour" : "nil");
        NSBitmapImageRep *shadowed = canvas(10, 10);
        draw_into(shadowed, ^{
            NSShadow *none = [[NSShadow alloc] init];
            [none setShadowColor:nil];
            [none set];
            [red setFill];
            NSRectFill(NSMakeRect(2, 2, 4, 4));
        });
        pixel("filled under a shadow with no colour", shadowed, 3, 3);
        pixel("beside it", shadowed, 8, 8);
        NSBitmapImageRep *real = canvas(10, 10);
        draw_into(real, ^{
            NSShadow *drop = [[NSShadow alloc] init];
            [drop setShadowOffset:NSMakeSize(2, -2)];
            [drop setShadowBlurRadius:1];
            [drop set];
            [red setFill];
            NSRectFill(NSMakeRect(2, 4, 4, 4));
            NSRectFill(NSMakeRect(2, 4, 4, 4));
        });
        pixel("filled under a drop shadow", real, 3, 5);
        pixel("its shadow, below and right", real, 6, 3);
        printf("shadow attribute name: %s\n", [NSShadowAttributeName UTF8String]);
        NSShadow *text = [NSShadow new];
        [text setShadowOffset:NSMakeSize(0, -1)];
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        attrs[NSShadowAttributeName] = text;
        attrs[NSForegroundColorAttributeName] = blue;
        NSAttributedString *label = [[NSAttributedString alloc] initWithString:@"Spectacle" attributes:attrs];
        printf("text attributes: %lu, shadow kept: %s\n", (unsigned long)[attrs count],
               [label attribute:NSShadowAttributeName atIndex:0 effectiveRange:NULL] == text ? "yes" : "no");
        NSBitmapImageRep *drawn = canvas(80, 20);
        draw_into(drawn, ^{
            [label drawAtPoint:NSMakePoint(2, 2)];
        });
        NSBitmapImageRep *plain = canvas(80, 20);
        draw_into(plain, ^{
            [[[NSAttributedString alloc] initWithString:@"Spectacle" attributes:@{NSForegroundColorAttributeName : blue}]
                drawAtPoint:NSMakePoint(2, 2)];
        });
        int inked = 0, inkedPlain = 0;
        for (int y = 0; y < 20; y++)
            for (int x = 0; x < 80; x++) {
                inked += [[drawn colorAtX:x y:y] alphaComponent] > 0.05;
                inkedPlain += [[plain colorAtX:x y:y] alphaComponent] > 0.05;
            }
        printf("text with a shadow attribute drawn, more pixels inked than without: %s\n",
               inked > inkedPlain ? "yes" : "no");
    }
    return 0;
}
