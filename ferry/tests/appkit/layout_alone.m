/* SPDX-License-Identifier: GPL-3.0-or-later
 * A layout manager with a text container and no text view, as apps use one
 * to wrap or measure text (freemac 1.NEXT). VLC's preferences wrap their
 * help text this way, walking the lines with lineFragmentRectForGlyphAtIndex:
 * and inserting a newline at each break; with no view to lay the text out,
 * every line came back empty and the walk never ended. Here the same walk
 * ends, the lines fit the container's width, cover the text once, in order,
 * and the used rectangle and a range's bounds are as tall as the lines.
 * Changing the text lays it out again. */
#import <Cocoa/Cocoa.h>

static NSString *wrap(NSString *in, CGFloat width, NSUInteger *lines)
{
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:in
        attributes:@{NSFontAttributeName : [NSFont labelFontOfSize:0]}];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, 2000)];
    [lm addTextContainer:tc];
    [storage addLayoutManager:lm];
    NSMutableString *out = [in mutableCopy];
    NSRange glyphs = [lm glyphRangeForTextContainer:tc], eff = NSMakeRange(0, 0);
    NSUInteger inserted = 0, n = 0;
    for (NSUInteger g = glyphs.location; g < NSMaxRange(glyphs) && n < 1000; g += eff.length, n++) {
        NSRect r = [lm lineFragmentRectForGlyphAtIndex:g effectiveRange:&eff];
        NSRect used = [lm lineFragmentUsedRectForGlyphAtIndex:g effectiveRange:NULL];
        if (eff.length == 0 || NSWidth(r) > width + 0.5 || NSWidth(used) > width + 0.5 || NSHeight(r) <= 0) {
            printf("bad line %lu: %lu chars, %g wide, used %g\n", (unsigned long)n, (unsigned long)eff.length,
                   NSWidth(r), NSWidth(used));
            return nil;
        }
        NSRange chars = [lm characterRangeForGlyphRange:eff actualGlyphRange:&eff];
        if ([out lineRangeForRange:NSMakeRange(chars.location + inserted, chars.length)].length > chars.length) {
            [out insertString:@"\n" atIndex:NSMaxRange(chars) + inserted];
            inserted++;
        }
    }
    *lines = n;
    NSRect usedAll = [lm usedRectForTextContainer:tc];
    NSRect bounds = [lm boundingRectForGlyphRange:glyphs inTextContainer:tc];
    if ([in length])
        printf("  used %s as tall as the lines, bounds %s\n",
               NSHeight(usedAll) > 0 && fabs(NSHeight(usedAll) - NSHeight(bounds)) < 1 ? "is" : "isn't",
               NSWidth(bounds) <= width && NSWidth(bounds) > 0 ? "within the width" : "wrong");
    /* changed text is laid out again */
    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@"short"];
    NSRange e;
    [lm lineFragmentRectForGlyphAtIndex:0 effectiveRange:&e];
    printf("  after a change: %lu chars on the first line\n", (unsigned long)e.length);
    return out;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *help = @"Select the time (in ms) VLC waits before it gives up on reading a "
                         @"network stream. Larger values help on slow or unreliable connections, "
                         @"at the cost of waiting longer when the stream really is gone.";
        NSUInteger lines = 0;
        NSString *w = wrap(help, 200, &lines);
        if (!w)
            return 1;
        NSArray *parts = [w componentsSeparatedByString:@"\n"];
        BOOL same = [[w stringByReplacingOccurrencesOfString:@"\n" withString:@""]
                        isEqualToString:[help stringByReplacingOccurrencesOfString:@"\n" withString:@""]];
        printf("wrapped to 200: %lu lines, %s, text %s\n", (unsigned long)lines,
               lines > 3 && [parts count] == lines ? "a newline at each break" : "breaks wrong",
               same ? "unchanged" : "changed");
        NSString *two = wrap(@"First paragraph.\nSecond one.", 500, &lines);
        printf("two paragraphs at 500: %lu lines, %s\n", (unsigned long)lines,
               [two isEqualToString:@"First paragraph.\nSecond one."] ? "no newline added" : "newline added");
        NSString *none = wrap(@"", 100, &lines);
        printf("empty text: %lu lines, %s\n", (unsigned long)lines, [none length] ? "text" : "empty");
    }
    return 0;
}
