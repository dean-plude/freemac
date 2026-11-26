/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSImage without a display: images drawn with lockFocus, written as PNG,
 * JPEG, TIFF and BMP files and read back, found by name in the app's own
 * bundle (with an @2x version), a PDF image drawn at twice its size, the
 * standard template images, image views and buttons with images, and
 * Image I/O. The test writes every file it reads into its own bundle, so
 * the repository holds no image files for it. */
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

static void pixel(const char *what, NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    printf("%s (%d,%d): %.1f %.1f %.1f %.1f\n", what, x, y, r, g, b, a);
}
static void size(const char *what, NSSize s) { printf("%s: %gx%g\n", what, s.width, s.height); }

static NSBitmapImageRep *canvas(int w, int h)
{
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8
                                              samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:32];
}
/* Runs body with a bitmap as the current context. */
static void draw_into(NSBitmapImageRep *rep, void (^body)(void))
{
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    body();
    [NSGraphicsContext restoreGraphicsState];
}

/* A one-page PDF, 20 by 10 points: the right half green and the top-left
 * quarter red, so both the axes show. */
static NSData *small_pdf(void)
{
    NSString *content = @"0 1 0 rg 10 0 10 10 re f 1 0 0 rg 0 5 10 5 re f";
    NSMutableString *pdf = [NSMutableString stringWithString:@"%PDF-1.4\n"];
    NSArray *objects = @[
        @"<< /Type /Catalog /Pages 2 0 R >>", @"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        @"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 10] /Contents 4 0 R /Resources << >> >>",
        [NSString stringWithFormat:@"<< /Length %lu >>\nstream\n%@\nendstream", (unsigned long)content.length, content],
    ];
    NSMutableArray *offsets = [NSMutableArray array];
    for (NSUInteger i = 0; i < objects.count; i++) {
        [offsets addObject:@(pdf.length)];
        [pdf appendFormat:@"%lu 0 obj\n%@\nendobj\n", (unsigned long)i + 1, objects[i]];
    }
    NSUInteger xref = pdf.length;
    [pdf appendFormat:@"xref\n0 %lu\n0000000000 65535 f \n", (unsigned long)objects.count + 1];
    for (NSNumber *o in offsets)
        [pdf appendFormat:@"%010lu 00000 n \n", [o unsignedLongValue]];
    [pdf appendFormat:@"trailer\n<< /Size %lu /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
                      (unsigned long)objects.count + 1, (unsigned long)xref];
    return [pdf dataUsingEncoding:NSASCIIStringEncoding];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *res = [[NSBundle mainBundle] resourcePath];
        [[NSFileManager defaultManager] createDirectoryAtPath:res withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];

        /* ---- drawing into an image ---- */
        NSImage *art = [[NSImage alloc] initWithSize:NSMakeSize(4, 4)];
        [art lockFocus];
        [[NSColor blueColor] set];
        NSRectFill(NSMakeRect(0, 0, 4, 4));
        [[NSColor redColor] set];
        NSRectFill(NSMakeRect(0, 2, 4, 2)); /* the top half */
        [art unlockFocus];
        NSBitmapImageRep *made = (NSBitmapImageRep *)[art representations][0];
        printf("lockFocus: %s %ldx%ld valid %d\n", [NSStringFromClass([made class]) UTF8String],
               (long)[made pixelsWide], (long)[made pixelsHigh], [art isValid]);
        pixel("top row", made, 0, 0);
        pixel("bottom row", made, 0, 3);

        /* ---- files written and read back ---- */
        struct { const char *ext; NSBitmapImageFileType type; } kinds[] = {
            {"png", NSBitmapImageFileTypePNG}, {"jpg", NSBitmapImageFileTypeJPEG},
            {"tiff", NSBitmapImageFileTypeTIFF}, {"bmp", NSBitmapImageFileTypeBMP},
        };
        for (int i = 0; i < 4; i++) {
            NSData *data = [made representationUsingType:kinds[i].type properties:@{NSImageCompressionFactor : @1.0}];
            NSString *path = [res stringByAppendingPathComponent:
                                      [NSString stringWithFormat:@"pic-%s.%s", kinds[i].ext, kinds[i].ext]];
            [data writeToFile:path atomically:NO];
            NSImage *back = [[NSImage alloc] initWithContentsOfFile:path];
            NSBitmapImageRep *r = (NSBitmapImageRep *)[back representations][0];
            CGFloat red, green, blue, alpha;
            [[r colorAtX:1 y:0] getRed:&red green:&green blue:&blue alpha:&alpha];
            CGFloat red2, blue2;
            [[r colorAtX:1 y:3] getRed:&red2 green:&green blue:&blue2 alpha:&alpha];
            printf("%s: %s, %gx%g, top %s, bottom %s\n", kinds[i].ext, data.length ? "written" : "NOT written",
                   [back size].width, [back size].height, red > 0.8 && blue < 0.2 ? "red" : "wrong",
                   blue2 > 0.8 && red2 < 0.2 ? "blue" : "wrong");
        }
        [[made TIFFRepresentation] writeToFile:[res stringByAppendingPathComponent:@"art.tiff"] atomically:NO];
        printf("garbage: image %d rep %d\n", [[NSImage alloc] initWithData:[@"not an image" dataUsingEncoding:4]] != nil,
               [NSBitmapImageRep imageRepWithData:[NSData data]] != nil);

        /* ---- by name from the bundle, with a sharper @2x version ---- */
        [[made representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:[res stringByAppendingPathComponent:@"logo.png"] atomically:NO];
        NSImage *big = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
        [big lockFocus];
        [[NSColor greenColor] set];
        NSRectFill(NSMakeRect(0, 0, 8, 8));
        [big unlockFocus];
        [[(NSBitmapImageRep *)[big representations][0] representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:[res stringByAppendingPathComponent:@"logo@2x.png"] atomically:NO];
        NSImage *logo = [NSImage imageNamed:@"logo"];
        size("logo", [logo size]);
        printf("logo: name %s, reps %lu, same again %d, by file name %d\n", [[logo name] UTF8String],
               (unsigned long)[[logo representations] count], [NSImage imageNamed:@"logo"] == logo,
               [NSImage imageNamed:@"pic-png.png"] != nil);
        for (NSImageRep *r in [logo representations])
            printf("  rep %ldx%ld pixels, size %gx%g\n", (long)[r pixelsWide], (long)[r pixelsHigh], [r size].width,
                   [r size].height);
        printf("missing: %d\n", [NSImage imageNamed:@"no-such-image"] != nil);

        /* ---- drawing: scaled, part of the image, flipped ---- */
        NSBitmapImageRep *out = canvas(8, 8);
        draw_into(out, ^{
            [art drawInRect:NSMakeRect(0, 0, 8, 8) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                   fraction:1];
        });
        pixel("scaled top", out, 4, 1);
        pixel("scaled bottom", out, 4, 6);
        NSBitmapImageRep *part = canvas(8, 8);
        draw_into(part, ^{ /* only the bottom (blue) half, stretched over the whole bitmap */
            [art drawInRect:NSMakeRect(0, 0, 8, 8) fromRect:NSMakeRect(0, 0, 4, 2)
                  operation:NSCompositingOperationSourceOver fraction:1];
        });
        pixel("part top", part, 4, 1);
        NSBitmapImageRep *flip = canvas(8, 8);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext *base = [NSGraphicsContext graphicsContextWithBitmapImageRep:flip];
        CGContextRef cg = [base CGContext];
        CGContextTranslateCTM(cg, 0, 8);
        CGContextScaleCTM(cg, 1, -1);
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES]];
        [art drawInRect:NSMakeRect(0, 0, 8, 8)]; /* kept upright */
        [NSGraphicsContext restoreGraphicsState];
        pixel("flipped context, upright top", flip, 4, 1);
        NSBitmapImageRep *half = canvas(8, 8);
        draw_into(half, ^{
            [art drawAtPoint:NSMakePoint(2, 2) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                    fraction:0.5];
        });
        pixel("half strength", half, 3, 3);
        pixel("outside", half, 0, 0);

        /* ---- PDF ---- */
        [small_pdf() writeToFile:[res stringByAppendingPathComponent:@"shape.pdf"] atomically:NO];
        NSImage *shape = [NSImage imageNamed:@"shape"];
        NSImageRep *pdfRep = [shape representations][0];
        printf("pdf: %s pages %ld\n", [NSStringFromClass([pdfRep class]) UTF8String],
               (long)[(NSPDFImageRep *)pdfRep pageCount]);
        size("pdf size", [shape size]);
        NSBitmapImageRep *vec = canvas(40, 20);
        draw_into(vec, ^{
            [shape drawInRect:NSMakeRect(0, 0, 40, 20)];
        });
        pixel("pdf top-left", vec, 5, 3);
        pixel("pdf bottom-left", vec, 5, 15);
        pixel("pdf right", vec, 30, 10);
        CGImageRef flat = [shape CGImageForProposedRect:NULL context:nil hints:nil];
        printf("pdf as CGImage: %zux%zu\n", CGImageGetWidth(flat), CGImageGetHeight(flat));

        /* ---- standard images, template images in a view ---- */
        NSImage *plus = [NSImage imageNamed:NSImageNameAddTemplate];
        printf("add template: template %d, name %s\n", [plus isTemplate], [[plus name] UTF8String]);
        size("add template", [plus size]);
        printf("app icon: %d, caution: %d\n", [NSImage imageNamed:NSImageNameApplicationIcon] != nil,
               [NSImage imageNamed:NSImageNameCaution] != nil);
        NSImage *look = [NSImage imageNamed:@"NSQuickLookTemplate"];
        printf("quick look: template %d, %.0fx%.0f\n", [look isTemplate], [look size].width, [look size].height);
        NSImageView *iv = [NSImageView imageViewWithImage:plus];
        [iv setFrame:NSMakeRect(0, 0, 14, 14)];
        [iv setContentTintColor:[NSColor colorWithRed:1 green:0 blue:0 alpha:1]];
        NSBitmapImageRep *shot = [iv bitmapImageRepForCachingDisplayInRect:[iv bounds]];
        [iv cacheDisplayInRect:[iv bounds] toBitmapImageRep:shot];
        pixel("tinted plus centre", shot, 7, 7);
        pixel("tinted plus corner", shot, 0, 0);

        NSImageView *scaled = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 20, 10)];
        [scaled setImage:art];
        [scaled setImageScaling:NSImageScaleProportionallyUpOrDown];
        [scaled setImageAlignment:NSImageAlignLeft];
        NSBitmapImageRep *shot2 = [scaled bitmapImageRepForCachingDisplayInRect:[scaled bounds]];
        [scaled cacheDisplayInRect:[scaled bounds] toBitmapImageRep:shot2];
        pixel("image view left", shot2, 2, 2);
        pixel("image view right", shot2, 15, 5);
        size("image view intrinsic", [scaled intrinsicContentSize]);

        /* ---- buttons with images ---- */
        NSButton *icon = [NSButton buttonWithImage:plus target:nil action:NULL];
        printf("image button: position %lu\n", (unsigned long)[icon imagePosition]);
        size("image button", [icon frame].size);
        NSButton *both = [NSButton buttonWithTitle:@"Add" image:plus target:nil action:NULL];
        printf("titled image button: position %lu, wider %d\n", (unsigned long)[both imagePosition],
               [both frame].size.width > [[NSButton buttonWithTitle:@"Add" target:nil action:NULL] frame].size.width);

        /* ---- Image I/O ---- */
        NSURL *url = [NSURL fileURLWithPath:[res stringByAppendingPathComponent:@"pic-jpg.jpg"]];
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        printf("image source: %zu image(s), %s\n", CGImageSourceGetCount(src),
               [(__bridge NSString *)CGImageSourceGetType(src) UTF8String]);
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
        printf("properties: %s x %s\n", [[props[(__bridge NSString *)kCGImagePropertyPixelWidth] description] UTF8String],
               [[props[(__bridge NSString *)kCGImagePropertyPixelHeight] description] UTF8String]);
        CGImageRef one = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        printf("image: %zux%zu\n", CGImageGetWidth(one), CGImageGetHeight(one));
        CGImageRelease(one);
        CFRelease(src);

        /* ---- a pattern colour keeps its image ---- */
        NSColor *pattern = [NSColor colorWithPatternImage:big];
        CGFloat r, g, b, a;
        [pattern getRed:&r green:&g blue:&b alpha:&a];
        printf("pattern: image kept %d, average %.1f %.1f %.1f\n", [pattern patternImage] == big, r, g, b);
    }
    return 0;
}
