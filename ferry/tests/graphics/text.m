/* Ferry M3 test: Core Text. Fonts differ between systems, so this checks
 * what must hold for any font (sizes scale, ink lands where the text was
 * drawn, Mac names map to the right kind of font) rather than exact sizes. */
#import <Foundation/Foundation.h>
#include <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

static const char *yes(BOOL b) { return b ? "yes" : "no"; }

/* Dark pixels inside a rectangle given in y-up coordinates. */
static int ink(CGContextRef c, int x0, int y0, int x1, int y1)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    size_t bpr = CGBitmapContextGetBytesPerRow(c), h = CGBitmapContextGetHeight(c);
    int n = 0;
    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++)
            if (d[(h - 1 - y) * bpr + x * 4] < 128)
                n++;
    return n;
}

static CGContextRef canvas(int w, int h)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    return c;
}

int main(void)
{
    @autoreleasepool {
        /* Mac font names map to the system's fonts. */
        CTFontRef helvetica = CTFontCreateWithName(CFSTR("Helvetica"), 24, NULL);
        CTFontRef system = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0, NULL);
        CTFontRef bold = CTFontCreateWithName(CFSTR("Helvetica-Bold"), 24, NULL);
        CTFontRef menlo = CTFontCreateWithName(CFSTR("Menlo-Regular"), 12, NULL);
        CTFontRef sfmono = CTFontCreateWithName(CFSTR("SFMono-Regular"), 12, NULL);
        NSString *fam = (NSString *)CTFontCopyFamilyName(helvetica);
        printf("Helvetica is the system font: %s\n", yes([fam isEqual:(id)CTFontCopyFamilyName(system)]));
        printf("Menlo and SF Mono are the same monospace font: %s\n",
               yes([(id)CTFontCopyFamilyName(menlo) isEqual:(id)CTFontCopyFamilyName(sfmono)] &&
                   ![(id)CTFontCopyFamilyName(menlo) isEqual:fam]));
        printf("system font size: %g, default size: %g\n", CTFontGetSize(system),
               CTFontGetSize(CTFontCreateWithName(CFSTR("Helvetica"), 0, NULL)));
        printf("traits: bold %s, regular %s, mono %s\n", yes((CTFontGetSymbolicTraits(bold) & kCTFontTraitBold) != 0),
               yes(!(CTFontGetSymbolicTraits(helvetica) & kCTFontTraitBold)),
               yes((CTFontGetSymbolicTraits(menlo) & kCTFontTraitMonoSpace) != 0));
        CTFontRef made_bold = CTFontCreateCopyWithSymbolicTraits(helvetica, 0, NULL, kCTFontTraitBold, kCTFontTraitBold);
        printf("bold copy is bold: %s, same size: %s\n", yes((CTFontGetSymbolicTraits(made_bold) & kCTFontTraitBold) != 0),
               yes(CTFontGetSize(made_bold) == 24));
        printf("PostScript name ends in -Bold: %s\n", yes([(id)CTFontCopyPostScriptName(bold) hasSuffix:@"-Bold"]));

        /* Metrics scale with the size. */
        CGFloat a = CTFontGetAscent(helvetica), d = CTFontGetDescent(helvetica);
        CTFontRef big = CTFontCreateWithName(CFSTR("Helvetica"), 48, NULL);
        printf("ascent and descent positive: %s, ascent above cap height above x-height: %s\n", yes(a > 0 && d > 0),
               yes(a > CTFontGetCapHeight(helvetica) && CTFontGetCapHeight(helvetica) > CTFontGetXHeight(helvetica)));
        printf("double size, double ascent: %s, units per em: %s\n",
               yes(fabs(CTFontGetAscent(big) - 2 * a) < 0.01), yes(CTFontGetUnitsPerEm(helvetica) >= 256));

        /* Glyphs and advances. */
        UniChar chars[] = {'A', 'i', 'W'};
        CGGlyph glyphs[3];
        CGSize adv[3];
        BOOL all = CTFontGetGlyphsForCharacters(helvetica, chars, glyphs, 3);
        double total = CTFontGetAdvancesForGlyphs(helvetica, kCTFontOrientationHorizontal, glyphs, adv, 3);
        printf("glyphs found: %s, distinct: %s, W wider than i: %s, total is the sum: %s\n",
               yes(all && glyphs[0] && glyphs[1] && glyphs[2]), yes(glyphs[0] != glyphs[1]),
               yes(adv[2].width > adv[1].width), yes(fabs(total - adv[0].width - adv[1].width - adv[2].width) < 1e-9));
        CGGlyph big_glyphs[3];
        CTFontGetGlyphsForCharacters(big, chars, big_glyphs, 3);
        printf("advance doubles with size: %s\n",
               yes(fabs(CTFontGetAdvancesForGlyphs(big, 0, big_glyphs, NULL, 3) - 2 * total) < 0.01));
        CGRect box;
        CTFontGetBoundingRectsForGlyphs(helvetica, 0, glyphs, &box, 1);
        printf("A's box sits on the baseline: %s\n", yes(fabs(box.origin.y) < 1 && box.size.height > 10));
        CGPathRef outline = CTFontCreatePathForGlyph(helvetica, glyphs[0], NULL);
        CGRect ob = CGPathGetBoundingBox(outline);
        printf("A's outline matches its box: %s\n",
               yes(fabs(ob.size.height - box.size.height) < 1 && fabs(ob.origin.y - box.origin.y) < 1));
        CGPathRelease(outline);

        /* A line. */
        NSAttributedString *s = [[NSAttributedString alloc]
            initWithString:@"Hello, Ferry"
                attributes:@{(id)kCTFontAttributeName : (id)helvetica}];
        CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)s);
        CGFloat la, ld, ll;
        double width = CTLineGetTypographicBounds(line, &la, &ld, &ll);
        printf("line: %ld glyphs, %ld characters, width between 80 and 250: %s, ascent matches font: %s\n",
               (long)CTLineGetGlyphCount(line), (long)CTLineGetStringRange(line).length,
               yes(width > 80 && width < 250), yes(fabs(la - a) < 1));
        CGFloat x5 = CTLineGetOffsetForStringIndex(line, 5, NULL);
        printf("offsets increase: %s, end is the width: %s, position maps back: %s\n",
               yes(x5 > 0 && x5 < width), yes(fabs(CTLineGetOffsetForStringIndex(line, 12, NULL) - width) < 0.01),
               yes(CTLineGetStringIndexForPosition(line, CGPointMake(x5 + 0.1, 0)) == 5));

        CGContextRef c = canvas(300, 60);
        CGContextSetTextPosition(c, 10, 20);
        CTLineDraw(line, c);
        CGRect ib = CTLineGetImageBounds(line, c);
        int inside = ink(c, (int)ib.origin.x, (int)ib.origin.y, (int)ceil(CGRectGetMaxX(ib)), (int)ceil(CGRectGetMaxY(ib)));
        printf("ink drawn: %s, all of it inside the image bounds: %s\n", yes(inside > 100),
               yes(ink(c, 0, 0, 300, 60) == inside));
        printf("image bounds start near the text position: %s, rise above the baseline: %s\n",
               yes(ib.origin.x >= 10 && ib.origin.x < 14), yes(CGRectGetMaxY(ib) > 35 && ib.origin.y >= 14));
        printf("nothing below the descent: %s\n", yes(ink(c, 0, 0, 300, (int)floor(20 - ld - 1)) == 0));
        CGContextRelease(c);

        /* The line's glyph runs (freemac 1.268, for Zed): one run here, its
         * glyphs, positions, string indices and font. */
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        CTRunRef run = CFArrayGetCount(runs) ? CFArrayGetValueAtIndex(runs, 0) : NULL;
        CFIndex rn = run ? CTRunGetGlyphCount(run) : 0;
        printf("glyph runs: %ld, a run: %s, its type: %s, glyphs as the line's: %s\n", (long)CFArrayGetCount(runs),
               yes(run != NULL), yes(run && CFGetTypeID(run) == CTRunGetTypeID()),
               yes(rn == CTLineGetGlyphCount(line)));
        if (run) {
            CGGlyph gl[64];
            CGPoint pos[64];
            CFIndex idx[64];
            CTRunGetGlyphs(run, CFRangeMake(0, 0), gl);
            CTRunGetPositions(run, CFRangeMake(0, 0), pos);
            CTRunGetStringIndices(run, CFRangeMake(0, 0), idx);
            CFRange rr = CTRunGetStringRange(run);
            int rising = 1, glyphs = 1;
            for (CFIndex i = 1; i < rn && i < 64; i++) rising &= pos[i].x > pos[i - 1].x && idx[i] > idx[i - 1];
            for (CFIndex i = 0; i < rn && i < 64; i++) glyphs &= gl[i] != 0;
            CTFontRef rf = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
            double rw = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), NULL, NULL, NULL);
            printf("run covers the string: %s, glyphs found: %s, positions and indices rise: %s\n",
                   yes(rr.location == 0 && rr.length == 12), yes(glyphs), yes(rising));
            printf("run's font: %s, run as wide as the line: %s, first glyph at the start: %s\n",
                   yes(rf && CFGetTypeID(rf) == CTFontGetTypeID() && fabs(CTFontGetSize(rf) - CTFontGetSize(helvetica)) < 0.01),
                   yes(fabs(rw - width) < 0.5), yes(fabs(pos[0].x) < 0.01 && idx[0] == 0));
        }

        /* Colour from the attributes, or from the context when asked. */
        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        NSAttributedString *rs = [[NSAttributedString alloc]
            initWithString:@"IIIIII"
                attributes:@{(id)kCTFontAttributeName : (id)bold, (id)kCTForegroundColorAttributeName : (id)red}];
        CTLineRef rl = CTLineCreateWithAttributedString((CFAttributedStringRef)rs);
        c = canvas(100, 40);
        CGContextSetTextPosition(c, 5, 10);
        CTLineDraw(rl, c);
        const unsigned char *px = CGBitmapContextGetData(c);
        int reds = 0;
        for (int i = 0; i < 100 * 40; i++)
            if (px[i * 4] > 200 && px[i * 4 + 1] < 60)
                reds++;
        printf("red text is red: %s\n", yes(reds > 50));
        CGContextRelease(c);
        CFRelease(rl);

        /* Truncation. */
        CTLineRef dots = CTLineCreateWithAttributedString((CFAttributedStringRef)[[NSAttributedString alloc]
            initWithString:@"…"
                attributes:@{(id)kCTFontAttributeName : (id)helvetica}]);
        CTLineRef cut = CTLineCreateTruncatedLine(line, 60, kCTLineTruncationEnd, NULL);
        double cw = CTLineGetTypographicBounds(cut, NULL, NULL, NULL);
        printf("truncated line fits: %s, keeps more than the ellipsis: %s\n", yes(cw <= 60),
               yes(cw > CTLineGetTypographicBounds(dots, NULL, NULL, NULL)));
        CFRelease(cut);
        CFRelease(dots);
        CFRelease(line);

        /* Frames: wrapping in a rectangle. */
        NSString *text = @"The quick brown fox jumps over the lazy dog, then naps in the warm afternoon sun.";
        NSAttributedString *para = [[NSAttributedString alloc]
            initWithString:text
                attributes:@{(id)kCTFontAttributeName : (id)CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL)}];
        CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)para);
        CFRange fit;
        CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), NULL,
                                                                   CGSizeMake(150, CGFLOAT_MAX), &fit);
        printf("suggested size fits the width: %s, several lines tall: %s, whole text fits: %s\n",
               yes(size.width <= 150 && size.width > 100), yes(size.height > 30), yes(fit.length == (CFIndex)text.length));
        CGPathRef path = CGPathCreateWithRect(CGRectMake(10, 10, 150, 200), NULL);
        CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
        CFArrayRef lines = CTFrameGetLines(frame);
        CFIndex n = CFArrayGetCount(lines);
        CGPoint origins[16];
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), origins);
        BOOL descending = YES, contiguous = YES;
        CFIndex next = 0;
        for (CFIndex i = 0; i < n; i++) {
            if (i && origins[i].y >= origins[i - 1].y)
                descending = NO;
            CFRange r = CTLineGetStringRange(CFArrayGetValueAtIndex(lines, i));
            if (r.location != next)
                contiguous = NO;
            next = r.location + r.length;
        }
        printf("frame: several lines: %s, going down: %s, covering the text in order: %s\n", yes(n >= 3),
               yes(descending), yes(contiguous && next == (CFIndex)text.length));
        printf("first line starts at the top: %s\n", yes(origins[0].y > 180 && origins[0].y < 200));
        c = canvas(200, 230);
        CTFrameDraw(frame, c);
        printf("frame ink inside its rectangle: %s, none outside: %s\n", yes(ink(c, 10, 10, 160, 210) > 300),
               yes(ink(c, 0, 0, 200, 230) == ink(c, 10, 10, 160, 210)));
        CGContextRelease(c);
        CFRelease(frame);
        CGPathRelease(path);
        path = CGPathCreateWithRect(CGRectMake(0, 0, 150, 20), NULL);
        frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
        CFRange vis = CTFrameGetVisibleStringRange(frame);
        printf("short frame shows one line: %s\n",
               yes(CFArrayGetCount(CTFrameGetLines(frame)) == 1 && vis.length > 0 && vis.length < (CFIndex)text.length));

        /* Centred paragraphs. */
        CTTextAlignment centre = kCTTextAlignmentCenter;
        CTParagraphStyleSetting setting = {kCTParagraphStyleSpecifierAlignment, sizeof centre, &centre};
        CTParagraphStyleRef style = CTParagraphStyleCreate(&setting, 1);
        NSAttributedString *centred = [[NSAttributedString alloc]
            initWithString:@"Hi"
                attributes:@{(id)kCTFontAttributeName : (id)helvetica, (id)kCTParagraphStyleAttributeName : (id)style}];
        CTFramesetterRef cfs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)centred);
        CGPathRelease(path);
        path = CGPathCreateWithRect(CGRectMake(0, 0, 150, 40), NULL);
        CTFrameRef cf = CTFramesetterCreateFrame(cfs, CFRangeMake(0, 0), path, NULL);
        CGPoint co;
        CTFrameGetLineOrigins(cf, CFRangeMake(0, 1), &co);
        CTTextAlignment back;
        CTParagraphStyleGetValueForSpecifier(style, kCTParagraphStyleSpecifierAlignment, sizeof back, &back);
        printf("centred line starts mid-way: %s, style reads back: %s\n", yes(co.x > 50 && co.x < 75),
               yes(back == kCTTextAlignmentCenter));
    }
    return 0;
}
