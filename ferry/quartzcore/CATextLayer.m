/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CATextLayer, a string drawn with Ferry's Core
 * Text from the top of the layer's bounds, the right way up on the page.
 * As Apple's documentation describes: the string is an NSString or an
 * NSAttributedString; a plain string takes the font (a font object or a
 * font's name; Helvetica when none), fontSize (36 by default) and
 * foregroundColor (white by default); wrapped text is broken into lines
 * that fit the width, and otherwise each line that doesn't fit is
 * truncated as truncationMode says. */
#import "QInternal.h"

CATextLayerTruncationMode const kCATruncationNone = @"none";
CATextLayerTruncationMode const kCATruncationStart = @"start";
CATextLayerTruncationMode const kCATruncationEnd = @"end";
CATextLayerTruncationMode const kCATruncationMiddle = @"middle";
CATextLayerAlignmentMode const kCAAlignmentNatural = @"natural";
CATextLayerAlignmentMode const kCAAlignmentLeft = @"left";
CATextLayerAlignmentMode const kCAAlignmentRight = @"right";
CATextLayerAlignmentMode const kCAAlignmentCenter = @"center";
CATextLayerAlignmentMode const kCAAlignmentJustified = @"justified";

@implementation CATextLayer
@dynamic string, font, fontSize, foregroundColor, wrapped, truncationMode, alignmentMode,
    allowsFontSubpixelQuantization;

+ (NSSet *)_ferryKnownKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[[super _ferryKnownKeys] setByAddingObjectsFromArray:@[
            @"string", @"font", @"fontSize", @"foregroundColor", @"wrapped", @"truncationMode", @"alignmentMode",
            @"allowsFontSubpixelQuantization"
        ]] retain];
    return keys;
}

+ (NSSet *)_ferryAnimatableKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[[super _ferryAnimatableKeys] setByAddingObjectsFromArray:@[ @"fontSize", @"foregroundColor" ]] retain];
    return keys;
}

+ (id)defaultValueForKey:(NSString *)key
{
    static NSDictionary *defaults;
    if (!defaults) {
        CGColorRef white = CGColorCreateSRGB(1, 1, 1, 1);
        defaults = [@{
            @"fontSize" : @36.0,
            @"foregroundColor" : (id)white,
            @"wrapped" : @NO,
            @"truncationMode" : kCATruncationNone,
            @"alignmentMode" : kCAAlignmentNatural,
            @"allowsFontSubpixelQuantization" : @NO,
        } retain];
        CGColorRelease(white);
    }
    return defaults[key] ?: [super defaultValueForKey:key];
}

static CTFontRef font_for(id font, CGFloat size)
{
    if ([font isKindOfClass:[GFont class]])
        return CTFontCreateCopyWithAttributes((CTFontRef)font, size, NULL, NULL);
    if ([font isKindOfClass:[NSString class]])
        return CTFontCreateWithName((CFStringRef)font, size, NULL);
    if (font)
        QWarnOnce("text layer fonts other than font objects and names");
    return CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);
}

- (void)_ferryDrawContentWithValues:(NSDictionary *)v inContext:(CGContextRef)ctx flipped:(BOOL)flipped
{
    id string = v[@"string"];
    if (![string length])
        return;
    CGRect b = QRect(v, @"bounds");
    NSAttributedString *text;
    if ([string isKindOfClass:[NSAttributedString class]]) {
        text = string;
    } else {
        CTFontRef font = font_for(v[@"font"], QNum(v, @"fontSize"));
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        attrs[(id)kCTFontAttributeName] = (id)font;
        CGColorRef fg = QColor(v, @"foregroundColor");
        if (fg)
            attrs[(id)kCTForegroundColorAttributeName] = (id)fg;
        text = [[[NSAttributedString alloc] initWithString:[string description] attributes:attrs] autorelease];
        CFRelease(font);
    }
    NSString *align = v[@"alignmentMode"];
    BOOL wrapped = QBool(v, @"wrapped");
    NSString *trunc = v[@"truncationMode"];

    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, b);
    /* lay out in a space that is the right way up on the page */
    if (flipped) {
        CGContextTranslateCTM(ctx, 0, 2 * b.origin.y + b.size.height);
        CGContextScaleCTM(ctx, 1, -1);
    }
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    if (wrapped) {
        CTTextAlignment a = [align isEqual:kCAAlignmentRight]       ? kCTTextAlignmentRight
                            : [align isEqual:kCAAlignmentCenter]    ? kCTTextAlignmentCenter
                            : [align isEqual:kCAAlignmentJustified] ? kCTTextAlignmentJustified
                                                                    : kCTTextAlignmentLeft;
        uint8_t ab = (uint8_t)a;
        CTParagraphStyleSetting s = {kCTParagraphStyleSpecifierAlignment, sizeof ab, &ab};
        CTParagraphStyleRef ps = CTParagraphStyleCreate(&s, 1);
        NSMutableAttributedString *m = [[text mutableCopy] autorelease];
        [m addAttribute:(id)kCTParagraphStyleAttributeName value:(id)ps range:NSMakeRange(0, [m length])];
        CFRelease(ps);
        CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)m);
        CGPathRef path = CGPathCreateWithRect(b, NULL);
        CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
        CTFrameDraw(frame, ctx);
        CFRelease(frame);
        CGPathRelease(path);
        CFRelease(fs);
    } else {
        NSString *plain = [text string];
        double y = CGRectGetMaxY(b);
        NSUInteger start = 0;
        while (start <= [plain length]) {
            NSRange nl = [plain rangeOfString:@"\n" options:0 range:NSMakeRange(start, [plain length] - start)];
            NSUInteger end = nl.location == NSNotFound ? [plain length] : nl.location;
            NSAttributedString *part = [text attributedSubstringFromRange:NSMakeRange(start, end - start)];
            CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)part);
            CGFloat ascent = 0, descent = 0, leading = 0;
            double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            if (!end && !start && [plain length] == 0)
                break;
            if (width > b.size.width && trunc && ![trunc isEqual:kCATruncationNone]) {
                CTLineTruncationType type = [trunc isEqual:kCATruncationStart]    ? kCTLineTruncationStart
                                            : [trunc isEqual:kCATruncationMiddle] ? kCTLineTruncationMiddle
                                                                                  : kCTLineTruncationEnd;
                NSDictionary *attrs = [part length] ? [part attributesAtIndex:0 effectiveRange:NULL] : @{};
                NSAttributedString *dots = [[[NSAttributedString alloc] initWithString:@"…" attributes:attrs] autorelease];
                CTLineRef token = CTLineCreateWithAttributedString((CFAttributedStringRef)dots);
                CTLineRef cut = CTLineCreateTruncatedLine(line, b.size.width, type, token);
                CFRelease(token);
                if (cut) {
                    CFRelease(line);
                    line = cut;
                    width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
                }
            }
            if (ascent <= 0 && descent <= 0) {
                CTFontRef f = font_for(v[@"font"], QNum(v, @"fontSize"));
                ascent = CTFontGetAscent(f), descent = CTFontGetDescent(f), leading = CTFontGetLeading(f);
                CFRelease(f);
            }
            y -= ascent;
            double x = b.origin.x;
            if ([align isEqual:kCAAlignmentRight])
                x = CGRectGetMaxX(b) - width;
            else if ([align isEqual:kCAAlignmentCenter])
                x = CGRectGetMidX(b) - width / 2;
            CGContextSetTextPosition(ctx, x, y);
            CTLineDraw(line, ctx);
            CFRelease(line);
            y -= descent + leading;
            if (nl.location == NSNotFound || y < CGRectGetMinY(b))
                break;
            start = end + 1;
        }
    }
    CGContextRestoreGState(ctx);
}
@end
