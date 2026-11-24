/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): NSTextAttachment, with no
 * display. An attachment's string and attribute; the room it takes in a
 * line; its image drawn inline into bitmaps, upright in unflipped and
 * flipped contexts, at its own size or at the bounds it is given; an image
 * read from the attachment's data; a cell that draws itself; and an image
 * in an NSTextView. Gas Mask puts its icons in text this way. */
#import <Cocoa/Cocoa.h>

static NSBitmapImageRep *canvas(int w, int h)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:32];
    return rep;
}
static void draw_into(NSBitmapImageRep *rep, BOOL flipped, void (^body)(void))
{
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (flipped) {
        CGContextRef cg = [gc CGContext];
        CGContextTranslateCTM(cg, 0, [rep pixelsHigh]);
        CGContextScaleCTM(cg, 1, -1);
        gc = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
    }
    [NSGraphicsContext setCurrentContext:gc];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, [rep pixelsWide], [rep pixelsHigh]));
    body();
    [NSGraphicsContext restoreGraphicsState];
}

/* the pixels of one colour: how many, and their box with y counted up from the bottom row */
typedef enum { RED, BLUE, GREEN } hue;
static BOOL is(NSBitmapImageRep *rep, int x, int row, hue h)
{
    CGFloat c[4];
    [[rep colorAtX:x y:row] getRed:&c[0] green:&c[1] blue:&c[2] alpha:&c[3]];
    double want[3] = {h == RED, h == GREEN, h == BLUE};
    for (int i = 0; i < 3; i++)
        if (fabs(c[i] - want[i]) > 0.2)
            return NO;
    return YES;
}
/* Reports the box of one colour against the box expected (y counted up from
 * the bottom row). Text is placed at fractions of a pixel, so the edges of a
 * box may be half covered: a box within a pixel and a half of the one
 * expected is as expected. */
static void report(const char *what, NSBitmapImageRep *rep, hue h, double w, double ht, double bottom)
{
    int n = 0, x0 = 1 << 20, y0 = 1 << 20, x1 = -1, y1 = -1, high = (int)[rep pixelsHigh];
    for (int row = 0; row < high; row++)
        for (int x = 0; x < (int)[rep pixelsWide]; x++)
            if (is(rep, x, row, h)) {
                int y = high - 1 - row;
                n++;
                x0 = x < x0 ? x : x0;
                x1 = x > x1 ? x : x1;
                y0 = y < y0 ? y : y0;
                y1 = y > y1 ? y : y1;
            }
    if (!n) {
        printf("%s: none\n", what);
        return;
    }
    int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    if (fabs(bw - w) <= 1.5 && fabs(bh - ht) <= 1.5 && fabs(y0 - bottom) <= 1.5)
        printf("%s: %g by %g, where expected\n", what, w, ht);
    else
        printf("%s: %d by %d with its bottom at y %d, not the %g by %g at y %g expected\n", what, bw, bh, y0, w, ht,
               bottom);
}

/* 10 by 10: the top half red, the bottom half blue */
static NSImage *two_tone(void)
{
    NSBitmapImageRep *rep = canvas(10, 10);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSColor colorWithDeviceRed:0 green:0 blue:1 alpha:1] set];
    NSRectFill(NSMakeRect(0, 0, 10, 5));
    [[NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1] set];
    NSRectFill(NSMakeRect(0, 5, 10, 5));
    [NSGraphicsContext restoreGraphicsState];
    NSImage *im = [[NSImage alloc] initWithSize:NSMakeSize(10, 10)];
    [im addRepresentation:rep];
    return im;
}

/* an attachment's string in the system font, so that its line has the font's descent */
static NSAttributedString *alone(NSTextAttachment *att)
{
    NSMutableAttributedString *m = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
    [m addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:12] range:NSMakeRange(0, 1)];
    return m;
}

@interface GreenCell : NSTextAttachmentCell
@end
@implementation GreenCell
- (NSSize)cellSize { return NSMakeSize(8, 6); }
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    [[NSColor colorWithDeviceRed:0 green:1 blue:0 alpha:1] set];
    NSRectFill(frame);
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSImage *image = two_tone();
        NSTextAttachment *att = [[NSTextAttachment alloc] init];
        [att setImage:image];
        NSAttributedString *one = [NSAttributedString attributedStringWithAttachment:att];
        printf("the attachment's string: %lu character, U+%04X, its attribute the attachment %s\n",
               (unsigned long)[one length], [[one string] characterAtIndex:0],
               [one attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL] == att ? "yes" : "no");
        printf("bounds when none are set: %s\n", NSEqualRects([att bounds], NSZeroRect) ? "zero" : "set");

        NSDictionary *font = @{NSFontAttributeName : [NSFont systemFontOfSize:12]};
        NSMutableAttributedString *line = [[NSMutableAttributedString alloc] initWithString:@"A" attributes:font];
        [line appendAttributedString:one];
        [line appendAttributedString:[[NSAttributedString alloc] initWithString:@"B" attributes:font]];
        NSSize with = [line size];
        NSSize without = [[[NSAttributedString alloc] initWithString:@"AB" attributes:font] size];
        double extra = with.width - without.width;
        printf("the line is wider by the image's width: %s\n", extra > 9 && extra < 11.5 ? "yes" : "no");

        /* drawn inline, upright, unflipped and flipped */
        NSFont *system = [NSFont systemFontOfSize:12];
        CGFloat ascent = [system ascender], descent = -[system descender];
        NSBitmapImageRep *rep = canvas(60, 30);
        draw_into(rep, NO, ^{
            [line drawAtPoint:NSMakePoint(2, 8)];
        });
        double baseline = 8 + descent; /* the point is the text's bottom left */
        report("unflipped, red", rep, RED, 10, 5, baseline + 5);
        report("unflipped, blue", rep, BLUE, 10, 5, baseline);
        NSBitmapImageRep *flipped = canvas(60, 30);
        draw_into(flipped, YES, ^{
            [line drawAtPoint:NSMakePoint(2, 8)];
        });
        baseline = 30 - (8 + fmax(ascent, 10)); /* the point is the text's top left */
        report("flipped, red", flipped, RED, 10, 5, baseline + 5);
        report("flipped, blue", flipped, BLUE, 10, 5, baseline);

        /* at given bounds, below the baseline */
        NSTextAttachment *wide = [[NSTextAttachment alloc] init];
        [wide setImage:image];
        [wide setBounds:CGRectMake(0, -4, 20, 8)];
        NSMutableAttributedString *low = [[NSMutableAttributedString alloc] initWithString:@"x" attributes:font];
        [low appendAttributedString:[NSAttributedString attributedStringWithAttachment:wide]];
        NSBitmapImageRep *rep2 = canvas(60, 30);
        draw_into(rep2, NO, ^{
            [low drawAtPoint:NSMakePoint(2, 10 - descent)];
        });
        printf("given bounds 20 by 8, 4 below a baseline at y 10:\n");
        report("  red", rep2, RED, 20, 4, 10);
        report("  blue", rep2, BLUE, 20, 4, 6);

        /* an image from the attachment's data */
        NSBitmapImageRep *src = (NSBitmapImageRep *)[[image representations] firstObject];
        NSData *png = [src representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSTextAttachment *data = [[NSTextAttachment alloc] initWithData:png ofType:@"public.png"];
        printf("from data: contents %lu bytes, type %s, image set %s\n", (unsigned long)[[data contents] length],
               [[data fileType] UTF8String], [data image] ? "yes" : "no");
        NSBitmapImageRep *rep3 = canvas(30, 20);
        draw_into(rep3, NO, ^{
            [alone(data) drawAtPoint:NSMakePoint(3, 3)];
        });
        report("  drawn red", rep3, RED, 10, 5, 3 + descent + 5);
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:png];
        NSTextAttachment *wrapped = [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
        printf("from a file wrapper: contents %lu bytes, the wrapper kept %s\n",
               (unsigned long)[[wrapped contents] length], [wrapped fileWrapper] == wrapper ? "yes" : "no");

        /* a cell */
        NSTextAttachment *celled = [[NSTextAttachment alloc] init];
        GreenCell *cell = [[GreenCell alloc] init];
        [celled setAttachmentCell:cell];
        printf("the cell's attachment: %s\n", [cell attachment] == celled ? "the one it is in" : "another");
        NSBitmapImageRep *rep4 = canvas(30, 20);
        draw_into(rep4, NO, ^{
            [alone(celled) drawAtPoint:NSMakePoint(3, 3)];
        });
        report("a cell, green", rep4, GREEN, 8, 6, 3 + descent);
        NSTextAttachmentCell *plainCell = [[NSTextAttachmentCell alloc] initImageCell:image];
        printf("a plain cell: size %.0f by %.0f, baseline offset %.0f,%.0f, tracks the mouse %s\n",
               [plainCell cellSize].width, [plainCell cellSize].height, [plainCell cellBaselineOffset].x,
               [plainCell cellBaselineOffset].y, [plainCell wantsToTrackMouse] ? "yes" : "no");

        /* in a text view */
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 120, 40)];
        [[tv textStorage] setAttributedString:line];
        NSBitmapImageRep *shown = [tv bitmapImageRepForCachingDisplayInRect:[tv bounds]];
        [tv cacheDisplayInRect:[tv bounds] toBitmapImageRep:shown];
        int red = 0, blue = 0, redAboveBlue = 1;
        for (int y = 0; y < (int)[shown pixelsHigh]; y++)
            for (int x = 0; x < (int)[shown pixelsWide]; x++) {
                if (is(shown, x, y, RED)) {
                    red++;
                    for (int k = y + 1; k < (int)[shown pixelsHigh]; k++)
                        if (is(shown, x, k, BLUE))
                            goto ok; /* a blue pixel lower down (rows count down here) */
                    redAboveBlue = 0;
                ok:;
                } else if (is(shown, x, y, BLUE))
                    blue++;
            }
        printf("in a text view: red %s, blue %s, red above blue %s\n", red >= 25 ? "drawn" : "missing",
               blue >= 25 ? "drawn" : "missing", redAboveBlue ? "yes" : "no");

        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:data requiringSecureCoding:NO error:NULL];
        NSTextAttachment *back = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
        printf("archived and read back: contents %s, type %s\n",
               [[back contents] isEqual:png] ? "the same" : "different", [[back fileType] UTF8String]);
    }
    return 0;
}
