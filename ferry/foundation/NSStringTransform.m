/* SPDX-License-Identifier: GPL-3.0-or-later
 * String transforms (freemac 1.225, Ferry 0.49.0): CFStringTransform and
 * -[NSString stringByApplyingTransform:reverse:], written for freemac from
 * Apple's public documentation of them. The transforms are named by their
 * ICU transform names, as on a Mac. Served here: characters to and from
 * XML's hex references (KissXML's), and back; fullwidth to halfwidth and
 * back; and the removal of combining marks and diacritics. The ones that
 * change script (to Latin and the like) and the Unicode names are not, and
 * answer false (nil), as a transform a Mac doesn't know does. */
#import "FInternal.h"

const CFStringRef kCFStringTransformToXMLHex = (CFStringRef)@"Any-Hex/XML";
const CFStringRef kCFStringTransformFullwidthHalfwidth = (CFStringRef)@"Fullwidth-Halfwidth";
const CFStringRef kCFStringTransformStripCombiningMarks = (CFStringRef)@"NFD; [:nonspacing mark:] Remove; NFC";
const CFStringRef kCFStringTransformStripDiacritics = (CFStringRef)@"NFD; [:M:] Remove; NFC";
const CFStringRef kCFStringTransformToLatin = (CFStringRef)@"Any-Latin";
const CFStringRef kCFStringTransformToUnicodeName = (CFStringRef)@"Any-Name";
const CFStringRef kCFStringTransformLatinHiragana = (CFStringRef)@"Latin-Hiragana";
const CFStringRef kCFStringTransformLatinKatakana = (CFStringRef)@"Latin-Katakana";
const CFStringRef kCFStringTransformHiraganaKatakana = (CFStringRef)@"Hiragana-Katakana";
const CFStringRef kCFStringTransformMandarinLatin = (CFStringRef)@"Han-Latin";
const CFStringRef kCFStringTransformLatinGreek = (CFStringRef)@"Latin-Greek";
const CFStringRef kCFStringTransformLatinCyrillic = (CFStringRef)@"Latin-Cyrillic";
const CFStringRef kCFStringTransformLatinArabic = (CFStringRef)@"Latin-Arabic";
const CFStringRef kCFStringTransformLatinHebrew = (CFStringRef)@"Latin-Hebrew";
const CFStringRef kCFStringTransformLatinThai = (CFStringRef)@"Latin-Thai";
const CFStringRef kCFStringTransformLatinKorean = (CFStringRef)@"Latin-Hangul";

NSString *const NSStringTransformToXMLHex = @"Any-Hex/XML";
NSString *const NSStringTransformFullwidthToHalfwidth = @"Fullwidth-Halfwidth";
NSString *const NSStringTransformStripCombiningMarks = @"NFD; [:nonspacing mark:] Remove; NFC";
NSString *const NSStringTransformStripDiacritics = @"NFD; [:M:] Remove; NFC";
NSString *const NSStringTransformToLatin = @"Any-Latin";
NSString *const NSStringTransformToUnicodeName = @"Any-Name";
NSString *const NSStringTransformLatinToHiragana = @"Latin-Hiragana";
NSString *const NSStringTransformLatinToKatakana = @"Latin-Katakana";
NSString *const NSStringTransformHiraganaToKatakana = @"Hiragana-Katakana";
NSString *const NSStringTransformMandarinToLatin = @"Han-Latin";
NSString *const NSStringTransformLatinToGreek = @"Latin-Greek";
NSString *const NSStringTransformLatinToCyrillic = @"Latin-Cyrillic";
NSString *const NSStringTransformLatinToArabic = @"Latin-Arabic";
NSString *const NSStringTransformLatinToHebrew = @"Latin-Hebrew";
NSString *const NSStringTransformLatinToThai = @"Latin-Thai";
NSString *const NSStringTransformLatinToKorean = @"Latin-Hangul";

/* Each character, ASCII too, as &#xHEX; (a pair of surrogates as one), as
 * ICU's Any-Hex/XML writes them. */
static NSString *to_xml_hex(NSString *s)
{
    NSUInteger n = [s length];
    NSMutableString *out = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        unsigned cp = c;
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < n) {
            unichar d = [s characterAtIndex:i + 1];
            if (d >= 0xdc00 && d < 0xe000) {
                cp = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
                i++;
            }
        }
        [out appendFormat:@"&#x%X;", cp];
    }
    return out;
}

static void append_code_point(NSMutableString *out, unsigned cp)
{
    if (cp >= 0x10000) {
        cp -= 0x10000;
        [out appendFormat:@"%C%C", (unichar)(0xd800 + (cp >> 10)), (unichar)(0xdc00 + (cp & 0x3ff))];
    } else
        [out appendFormat:@"%C", (unichar)cp];
}

/* &#xHEX; and &#DECIMAL; back to their characters; anything else is kept. */
static NSString *from_xml_hex(NSString *s)
{
    NSUInteger n = [s length];
    NSMutableString *out = [NSMutableString stringWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '&' && i + 3 < n && [s characterAtIndex:i + 1] == '#') {
            NSUInteger j = i + 2;
            int base = 10;
            if ([s characterAtIndex:j] == 'x' || [s characterAtIndex:j] == 'X') {
                base = 16;
                j++;
            }
            unsigned long cp = 0;
            NSUInteger start = j;
            for (; j < n; j++) {
                unichar d = [s characterAtIndex:j];
                int v = d >= '0' && d <= '9' ? d - '0'
                      : base == 16 && d >= 'a' && d <= 'f' ? d - 'a' + 10
                      : base == 16 && d >= 'A' && d <= 'F' ? d - 'A' + 10 : -1;
                if (v < 0 || cp > 0x10ffff)
                    break;
                cp = cp * base + v;
            }
            if (j > start && j < n && [s characterAtIndex:j] == ';' && cp <= 0x10ffff) {
                append_code_point(out, (unsigned)cp);
                i = j;
                continue;
            }
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

/* The fullwidth forms of ASCII and the ideographic space, either way. */
static NSString *fullwidth(NSString *s, BOOL toHalf)
{
    NSUInteger n = [s length];
    unichar *buf = malloc((n ? n : 1) * sizeof(unichar));
    [s getCharacters:buf range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = buf[i];
        if (toHalf) {
            if (c >= 0xff01 && c <= 0xff5e)
                buf[i] = c - 0xff01 + 0x21;
            else if (c == 0x3000)
                buf[i] = ' ';
        } else {
            if (c >= 0x21 && c <= 0x7e)
                buf[i] = c - 0x21 + 0xff01;
            else if (c == ' ')
                buf[i] = 0x3000;
        }
    }
    NSString *r = [NSString stringWithCharacters:buf length:n];
    free(buf);
    return r;
}

static BOOL is_combining(unichar c)
{
    return (c >= 0x300 && c <= 0x36f) || (c >= 0x483 && c <= 0x489) || (c >= 0x591 && c <= 0x5bd)
        || (c >= 0x610 && c <= 0x61a) || (c >= 0x64b && c <= 0x65f) || (c >= 0x1ab0 && c <= 0x1aff)
        || (c >= 0x1dc0 && c <= 0x1dff) || (c >= 0x20d0 && c <= 0x20ff) || (c >= 0x3099 && c <= 0x309a)
        || (c >= 0xfe20 && c <= 0xfe2f);
}

/* Decomposed, the combining marks taken out, and composed again. */
static NSString *strip_marks(NSString *s)
{
    NSString *d = [s decomposedStringWithCanonicalMapping];
    NSUInteger n = [d length], k = 0;
    unichar *buf = malloc((n ? n : 1) * sizeof(unichar));
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [d characterAtIndex:i];
        if (!is_combining(c))
            buf[k++] = c;
    }
    NSString *r = [[NSString stringWithCharacters:buf length:k] precomposedStringWithCanonicalMapping];
    free(buf);
    return r;
}

static NSString *apply_transform(NSString *s, NSString *t, BOOL reverse)
{
    if ([t isEqualToString:@"Any-Hex/XML"] || [t isEqualToString:@"Hex/XML-Any"])
        return reverse != [t hasPrefix:@"Hex"] ? from_xml_hex(s) : to_xml_hex(s);
    if ([t isEqualToString:@"Fullwidth-Halfwidth"] || [t isEqualToString:@"Halfwidth-Fullwidth"])
        return fullwidth(s, reverse == [t hasPrefix:@"Half"]);
    if ([t isEqualToString:(NSString *)kCFStringTransformStripCombiningMarks]
        || [t isEqualToString:(NSString *)kCFStringTransformStripDiacritics])
        return reverse ? nil : strip_marks(s);
    return nil;
}

@implementation NSString (FerryTransform)
- (NSString *)stringByApplyingTransform:(NSString *)transform reverse:(BOOL)reverse
{
    return transform ? apply_transform(self, transform, reverse) : nil;
}
@end

Boolean CFStringTransform(CFMutableStringRef string, CFRange *range, CFStringRef transform, Boolean reverse)
{
    NSMutableString *s = (NSMutableString *)string;
    NSRange r = range ? NSMakeRange(range->location, range->length) : NSMakeRange(0, [s length]);
    if (NSMaxRange(r) > [s length])
        return false;
    NSString *t = apply_transform([s substringWithRange:r], (NSString *)transform, reverse);
    if (!t)
        return false;
    [s replaceCharactersInRange:r withString:t];
    if (range)
        range->length = [t length];
    return true;
}
