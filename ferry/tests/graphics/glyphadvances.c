/* SPDX-License-Identifier: GPL-3.0-or-later
 * CGContextShowGlyphsWithAdvances and CGContextShowGlyphs draw from the
 * text position, one advance after another, and move the text position on
 * (Apple's CGContext documentation; Hex Fiend draws its bytes this way,
 * freemac 1.270). */
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <stdio.h>

static int inked(const unsigned char *px, int w, int x0, int x1)
{
    int n = 0;
    for (int y = 0; y < 40; y++)
        for (int x = x0; x < x1; x++)
            if (px[(y * w + x) * 4 + 3] > 128)
                n++;
    return n;
}

int main(void)
{
    enum { W = 200, H = 40 };
    static unsigned char px[W * H * 4];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
    CTFontRef ct = CTFontCreateWithName(CFSTR("Menlo"), 20, NULL);
    CGFontRef font = CTFontCopyGraphicsFont(ct, NULL);
    UniChar chars[4] = {'H', 'H', 'H', 'H'};
    CGGlyph g[4];
    CTFontGetGlyphsForCharacters(ct, chars, g, 4);
    CGContextSetFont(c, font);
    CGContextSetFontSize(c, 20);
    CGContextSetRGBFillColor(c, 0, 0, 0, 1);
    CGContextSetTextMatrix(c, CGAffineTransformIdentity);
    CGContextSetTextPosition(c, 10, 10);
    CGSize adv[2] = {{30, 0}, {30, 0}};
    CGContextShowGlyphsWithAdvances(c, g, adv, 2);
    CGPoint at = CGContextGetTextPosition(c);
    printf("text position after: %g, %g\n", at.x, at.y);
    printf("first glyph drawn: %s\n", inked(px, W, 10, 30) > 20 ? "yes" : "no");
    printf("second glyph 30 points on: %s\n", inked(px, W, 40, 60) > 20 ? "yes" : "no");
    printf("nothing in the gap: %s\n", inked(px, W, 32, 38) == 0 ? "yes" : "no");
    CGContextShowGlyphs(c, g, 1);
    printf("CGContextShowGlyphs draws at the new position: %s\n", inked(px, W, 70, 90) > 20 ? "yes" : "no");
    /* no font draws a control character, so none stands in for one; a hex
     * editor then shows its own '.' for the byte */
    CTFontRef forControl = CTFontCreateForString(ct, CFSTR("\x01"), CFRangeMake(0, 1));
    printf("font for a control character is the font itself: %s\n", forControl == ct ? "yes" : "no");
    return 0;
}
