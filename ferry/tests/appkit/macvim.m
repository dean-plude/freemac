/* SPDX-License-Identifier: GPL-3.0-or-later
 * What MacVim needs of AppKit, Core Text and Core Graphics (freemac
 * 1.NEXT): a line's glyph runs, which MacVim draws its text with; colours
 * in a Lab colour space, which it works out its tab bar's colours in; a
 * copied menu that keeps its submenus and alternate items, as MacVim hands
 * NSApp a copy of its menu, and that copy's key equivalents; and typed
 * keys reaching insertText:replacementRange: and doCommandBySelector:. */
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

static int near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.02; }

static void runs(void)
{
    CTFontRef font = CTFontCreateWithName(CFSTR("Monospace"), 13, NULL);
    NSDictionary *attrs = @{(id)kCTFontAttributeName : (id)font};
    NSAttributedString *s = [[NSAttributedString alloc] initWithString:@"Hello" attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)s);
    CFArrayRef list = CTLineGetGlyphRuns(line);
    printf("runs: %ld, the same array again: %d\n", (long)CFArrayGetCount(list), CTLineGetGlyphRuns(line) == list);
    CTRunRef run = CFArrayGetValueAtIndex(list, 0);
    CFIndex n = CTRunGetGlyphCount(run);
    CFRange r = CTRunGetStringRange(run);
    printf("glyphs: %ld, string range %ld %ld, status %d\n", (long)n, (long)r.location, (long)r.length,
           (int)CTRunGetStatus(run));
    CGGlyph g[8];
    CGPoint p[8];
    CGSize a[8];
    CFIndex idx[8];
    CTRunGetGlyphs(run, CFRangeMake(0, 0), g);
    CTRunGetPositions(run, CFRangeMake(0, 0), p);
    CTRunGetAdvances(run, CFRangeMake(0, 0), a);
    CTRunGetStringIndices(run, CFRangeMake(0, 0), idx);
    int glyphs_ok = 1, rising = 1, ahead = 1;
    for (CFIndex i = 0; i < n; i++) {
        glyphs_ok &= g[i] != 0;
        ahead &= a[i].width > 0;
        if (i)
            rising &= p[i].x > p[i - 1].x && near(p[i].x - p[i - 1].x, a[i - 1].width);
        printf("  glyph %ld from character %ld\n", (long)i, (long)idx[i]);
    }
    printf("glyphs found %d, advances %d, positions follow the advances %d, both l's alike %d\n", glyphs_ok,
           ahead, rising, g[2] == g[3]);
    printf("pointers: %d\n", CTRunGetGlyphsPtr(run) != NULL && CTRunGetPositionsPtr(run) != NULL);
    CGFloat ascent = 0, descent = 0;
    double width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, NULL);
    printf("bounds: width %d, ascent %d, descent %d\n", width > 0 && near(width, p[n - 1].x + a[n - 1].width),
           ascent > 0, descent > 0);
    CTFontRef used = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
    printf("its font: %d, size %.0f\n", used != NULL, used ? CTFontGetSize(used) : 0);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 80, 20, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    CGContextSetTextPosition(c, 2, 5);
    CTRunDraw(run, c, CFRangeMake(0, 0));
    const unsigned char *px = CGBitmapContextGetData(c);
    int inked = 0;
    for (size_t i = 0; i < CGBitmapContextGetBytesPerRow(c) * 20; i += 4)
        inked += px[i + 3] != 0;
    printf("drawn: %d\n", inked > 10);
    CGContextRelease(c);
    CGColorSpaceRelease(rgb);
    CFRelease(line);
    [s release];
    CFRelease(font);
}

static void lab(void)
{
    const CGFloat white[3] = {0.9505, 1.0, 1.089}, black[3] = {0, 0, 0}, range[4] = {-128, 127, -128, 127};
    CGColorSpaceRef space = CGColorSpaceCreateLab(white, black, range);
    printf("lab space: model %d, components %zu\n", (int)CGColorSpaceGetModel(space),
           CGColorSpaceGetNumberOfComponents(space));
    const CGFloat red[4] = {53.24, 80.09, 67.20, 1};
    CGColorRef c = CGColorCreate(space, red);
    printf("a Lab colour made: %d\n", c != NULL);
    CGColorRelease(c);
    CGColorSpaceRelease(space);
    NSColorSpace *ns = [[NSColorSpace alloc] initWithCGColorSpace:CGColorSpaceCreateWithName(kCGColorSpaceGenericLab)];
    printf("NSColorSpace model is Lab: %d\n", [ns colorSpaceModel] == NSColorSpaceModelLAB);
    NSColor *col = [NSColor colorWithColorSpace:ns components:red count:4];
    NSColor *srgb = [col colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    printf("as sRGB: %d %d %d\n", near([srgb redComponent], 1), near([srgb greenComponent], 0),
           near([srgb blueComponent], 0));
    CGFloat k[4];
    [col getComponents:k];
    printf("kept its Lab components: %d, count %ld\n", near(k[0], 53.24) && near(k[1], 80.09) && near(k[3], 1),
           (long)[col numberOfComponents]);
    NSColor *back = [[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] colorUsingColorSpace:ns];
    [back getComponents:k];
    printf("white in Lab: %d %d %d\n", near(k[0], 100), fabs(k[1]) < 0.5, fabs(k[2]) < 0.5);
    [ns release];
}

@interface Receiver : NSObject
@property NSInteger count;
@end
@implementation Receiver
- (void)newWindow:(id)sender { self.count++; }
@end

static void menus(void)
{
    Receiver *r = [[Receiver alloc] init];
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
    [top setSubmenu:file];
    [main addItem:top];
    NSMenuItem *item = [file addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@"n"];
    [item setTarget:r];
    [item setToolTip:@"Opens a window"];
    NSMenuItem *alt = [file addItemWithTitle:@"New Clean Window" action:@selector(newWindow:) keyEquivalent:@"n"];
    [alt setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [alt setAlternate:YES];
    NSMenu *copy = [main copy];
    NSMenu *sub = [[copy itemAtIndex:0] submenu];
    printf("the copy has its submenu: %d, a copy of it: %d, items %ld\n", sub != nil, sub != file,
           (long)[sub numberOfItems]);
    printf("copied item: key %s, tip %s, target kept %d, alternate %d %d\n",
           [[[sub itemAtIndex:0] keyEquivalent] UTF8String], [[[sub itemAtIndex:0] toolTip] UTF8String],
           [[sub itemAtIndex:0] target] == r, [[sub itemAtIndex:0] isAlternate], [[sub itemAtIndex:1] isAlternate]);
    printf("its supermenu: %d\n", [sub supermenu] == copy);
    NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                             modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil
                                characters:@"n" charactersIgnoringModifiers:@"n" isARepeat:NO keyCode:45];
    printf("Command-N in the copy: %d, sent %ld\n", [copy performKeyEquivalent:e], (long)r.count);
    [copy release];
    [file release];
    [top release];
    [main release];
    [r release];
}

@interface Typing : NSView
@property (retain) NSMutableArray *got;
@end
@implementation Typing
- (void)insertText:(id)s replacementRange:(NSRange)range
{
    [self.got addObject:[NSString stringWithFormat:@"insert %@ %s", s, range.location == NSNotFound ? "nowhere" : "somewhere"]];
}
- (void)doCommandBySelector:(SEL)sel { [self.got addObject:NSStringFromSelector(sel)]; }
@end

static void keys(void)
{
    Typing *t = [[Typing alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    t.got = [NSMutableArray array];
    NSEvent *a = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                              windowNumber:0 context:nil characters:@"a" charactersIgnoringModifiers:@"a"
                                 isARepeat:NO keyCode:0];
    NSEvent *ret = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                windowNumber:0 context:nil characters:@"\r" charactersIgnoringModifiers:@"\r"
                                   isARepeat:NO keyCode:36];
    [t interpretKeyEvents:@[ a, ret ]];
    for (NSString *s in t.got)
        printf("typed: %s\n", [s UTF8String]);
    [t release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        runs();
        lab();
        menus();
        keys();
    }
    return 0;
}
