/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: attributed strings from and to documents. RTF is read
 * from Microsoft's public RTF 1.9 specification (groups, control words, the
 * font and colour tables, \'hh and \u escapes, the ANSI, Windows and Mac
 * code pages); the look it keeps is bold, italic, underline, font, size,
 * colour and alignment, and destinations it doesn't know are skipped. HTML
 * is read simply: paragraphs, line breaks, headings, list items, bold,
 * italic, links and entities. Plain text is read as UTF-8, or Latin-1 when
 * it isn't. RTF is written with the same features. */
#import "AInternal.h"

NSAttributedStringKey const NSLinkAttributeName = @"NSLink";
NSAttributedStringDocumentAttributeKey const NSDocumentTypeDocumentAttribute = @"DocumentType";
NSAttributedStringDocumentAttributeKey const NSCharacterEncodingDocumentAttribute = @"CharacterEncoding";
NSAttributedStringDocumentReadingOptionKey const NSDocumentTypeDocumentOption = @"DocumentType";
NSAttributedStringDocumentReadingOptionKey const NSCharacterEncodingDocumentOption = @"CharacterEncoding";
NSAttributedStringDocumentType const NSPlainTextDocumentType = @"NSPlainText";
NSAttributedStringDocumentType const NSRTFTextDocumentType = @"NSRTF";
NSAttributedStringDocumentType const NSRTFDTextDocumentType = @"NSRTFD";
NSAttributedStringDocumentType const NSHTMLTextDocumentType = @"NSHTML";

/* ---- code pages for \'hh: bytes 0x80 to 0xff ------------------------------------------- */

static const unichar cp1252_high[32] = {
    0x20ac, 0x81, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021, 0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8d, 0x017d,
    0x8f, 0x90, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, 0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x9d,
    0x017e, 0x0178,
};
static const unichar mac_roman_high[128] = {
    0x00c4, 0x00c5, 0x00c7, 0x00c9, 0x00d1, 0x00d6, 0x00dc, 0x00e1, 0x00e0, 0x00e2, 0x00e4, 0x00e3, 0x00e5, 0x00e7,
    0x00e9, 0x00e8, 0x00ea, 0x00eb, 0x00ed, 0x00ec, 0x00ee, 0x00ef, 0x00f1, 0x00f3, 0x00f2, 0x00f4, 0x00f6, 0x00f5,
    0x00fa, 0x00f9, 0x00fb, 0x00fc, 0x2020, 0x00b0, 0x00a2, 0x00a3, 0x00a7, 0x2022, 0x00b6, 0x00df, 0x00ae, 0x00a9,
    0x2122, 0x00b4, 0x00a8, 0x2260, 0x00c6, 0x00d8, 0x221e, 0x00b1, 0x2264, 0x2265, 0x00a5, 0x00b5, 0x2202, 0x2211,
    0x220f, 0x03c0, 0x222b, 0x00aa, 0x00ba, 0x03a9, 0x00e6, 0x00f8, 0x00bf, 0x00a1, 0x00ac, 0x221a, 0x0192, 0x2248,
    0x2206, 0x00ab, 0x00bb, 0x2026, 0x00a0, 0x00c0, 0x00c3, 0x00d5, 0x0152, 0x0153, 0x2013, 0x2014, 0x201c, 0x201d,
    0x2018, 0x2019, 0x00f7, 0x25ca, 0x00ff, 0x0178, 0x2044, 0x20ac, 0x2039, 0x203a, 0xfb01, 0xfb02, 0x2021, 0x00b7,
    0x201a, 0x201e, 0x2030, 0x00c2, 0x00ca, 0x00c1, 0x00cb, 0x00c8, 0x00cd, 0x00ce, 0x00cf, 0x00cc, 0x00d3, 0x00d4,
    0xf8ff, 0x00d2, 0x00da, 0x00db, 0x00d9, 0x0131, 0x02c6, 0x02dc, 0x00af, 0x02d8, 0x02d9, 0x02da, 0x00b8, 0x02dd,
    0x02db, 0x02c7,
};
static unichar from_code_page(unsigned byte, int page)
{
    if (byte < 0x80)
        return (unichar)byte;
    if (page == 10000)
        return mac_roman_high[byte - 0x80];
    if (byte < 0xa0 && page != 28591)
        return cp1252_high[byte - 0x80];
    return (unichar)byte;
}

/* ---- the look of a run ------------------------------------------------------------------ */

typedef struct {
    BOOL bold, italic, underline, skip;
    int font, color, size;    /* size in half points */
    int uc;                   /* characters to skip after \uN */
    NSTextAlignment align;
    NSString *link;           /* not retained: held by the parser's list */
} Look;

static NSFont *font_for(NSString *name, CGFloat size, BOOL bold, BOOL italic)
{
    NSFont *f = name ? [NSFont fontWithName:name size:size] : nil;
    if (!f)
        f = [NSFont userFontOfSize:size] ?: [NSFont systemFontOfSize:size];
    uint32_t traits = (bold ? kCTFontTraitBold : 0) | (italic ? kCTFontTraitItalic : 0);
    if (traits) {
        CTFontRef t = CTFontCreateCopyWithSymbolicTraits((CTFontRef)f, size, NULL, traits, traits);
        if (t)
            f = [(id)t autorelease];
        else if (bold)
            f = [NSFont boldSystemFontOfSize:size];
    }
    return f;
}

static NSDictionary *attributes_for(Look *l, NSArray *fonts, NSArray *colors)
{
    NSMutableDictionary *a = [NSMutableDictionary dictionary];
    NSString *name = l->font >= 0 && l->font < (int)[fonts count] ? [fonts objectAtIndex:(NSUInteger)l->font] : nil;
    if ([name isKindOfClass:[NSNull class]])
        name = nil;
    [a setObject:font_for(name, l->size / 2.0, l->bold, l->italic) forKey:NSFontAttributeName];
    if (l->color > 0 && l->color < (int)[colors count] && ![[colors objectAtIndex:(NSUInteger)l->color] isKindOfClass:[NSNull class]])
        [a setObject:[colors objectAtIndex:(NSUInteger)l->color] forKey:NSForegroundColorAttributeName];
    if (l->underline)
        [a setObject:@(NSUnderlineStyleSingle) forKey:NSUnderlineStyleAttributeName];
    if (l->link) {
        [a setObject:l->link forKey:NSLinkAttributeName];
        [a setObject:[NSColor linkColor] forKey:NSForegroundColorAttributeName];
        [a setObject:@(NSUnderlineStyleSingle) forKey:NSUnderlineStyleAttributeName];
    }
    if (l->align != NSTextAlignmentNatural) {
        NSMutableParagraphStyle *p = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        [p setAlignment:l->align];
        [a setObject:p forKey:NSParagraphStyleAttributeName];
    }
    return a;
}

/* Collects text in runs of one look. */
@interface ARunBuilder : NSObject {
@public
    NSMutableAttributedString *out;
    NSMutableString *pending;
    Look look, pendingLook;
    NSArray *fonts, *colors;
}
@end
@implementation ARunBuilder
- (instancetype)init
{
    if ((self = [super init])) {
        out = [[NSMutableAttributedString alloc] init];
        pending = [[NSMutableString alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [out release];
    [pending release];
    [fonts release];
    [colors release];
    [super dealloc];
}
- (void)flush
{
    if (![pending length])
        return;
    NSAttributedString *a = [[NSAttributedString alloc] initWithString:pending
                                                            attributes:attributes_for(&pendingLook, fonts, colors)];
    [out appendAttributedString:a];
    [a release];
    [pending setString:@""];
}
static BOOL same_look(Look *a, Look *b)
{
    return a->bold == b->bold && a->italic == b->italic && a->underline == b->underline && a->font == b->font &&
           a->color == b->color && a->size == b->size && a->align == b->align && a->link == b->link;
}
- (void)add:(NSString *)s
{
    if (![s length])
        return;
    if ([pending length] && !same_look(&look, &pendingLook))
        [self flush];
    pendingLook = look;
    [pending appendString:s];
}
- (void)addChar:(unichar)c { [self add:[NSString stringWithCharacters:&c length:1]]; }
/* Ends the text with at least n line breaks, unless there is no text yet. */
- (void)breakLines:(int)n
{
    NSString *all = [[out string] stringByAppendingString:pending];
    NSUInteger len = [all length];
    if (!len)
        return;
    int have = 0;
    while (have < (int)len && [all characterAtIndex:len - 1 - (NSUInteger)have] == '\n')
        have++;
    while (have++ < n)
        [self add:@"\n"];
}
@end

/* ---- RTF -------------------------------------------------------------------------------- */

static NSAttributedString *read_rtf(NSData *data, NSDictionary **docAttrs)
{
    const unsigned char *p = [data bytes], *end = p + [data length];
    while (p < end && (*p == ' ' || *p == '\r' || *p == '\n' || *p == 0xef || *p == 0xbb || *p == 0xbf))
        p++;
    if (end - p < 5 || memcmp(p, "{\\rtf", 5) != 0)
        return nil;
    ARunBuilder *b = [[[ARunBuilder alloc] init] autorelease];
    NSMutableArray *fonts = [NSMutableArray array], *colors = [NSMutableArray array];
    Look stack[64];
    int depth = 0, page = 1252;
    int skipChars = 0;                 /* left to skip after \uN */
    enum { NORMAL, FONTS, COLORS } dest[64] = {NORMAL};
    b->fonts = [fonts retain]; /* filled in as the tables are read */
    b->colors = [colors retain];
    Look *l = &b->look;
    memset(l, 0, sizeof *l);
    l->size = 24;
    l->font = 0;
    l->uc = 1;
    l->align = NSTextAlignmentNatural;
    int fontIndex = -1;
    NSMutableString *fontName = [NSMutableString string];
    int red = 0, green = 0, blue = 0;
    BOOL starred = NO;
    while (p < end) {
        unsigned char c = *p++;
        if (c == '{') {
            if (depth < 63) {
                stack[depth] = *l;
                dest[depth + 1] = dest[depth];
                depth++;
            }
            starred = NO;
            continue;
        }
        if (c == '}') {
            if (dest[depth] == FONTS && fontIndex >= 0 && [fontName length]) {
                while ((int)[fonts count] <= fontIndex)
                    [fonts addObject:[NSNull null]];
                [fonts replaceObjectAtIndex:(NSUInteger)fontIndex
                                 withObject:[fontName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
                [fontName setString:@""];
                fontIndex = -1;
            }
            if (depth > 0)
                *l = stack[--depth];
            if (depth == 0)
                break;
            continue;
        }
        if (c == '\r' || c == '\n')
            continue;
        if (c != '\\') {
            if (skipChars > 0) {
                skipChars--;
                continue;
            }
            if (l->skip)
                continue;
            if (dest[depth] == FONTS) {
                if (c == ';') {
                    if (fontIndex >= 0) {
                        while ((int)[fonts count] <= fontIndex)
                            [fonts addObject:[NSNull null]];
                        [fonts replaceObjectAtIndex:(NSUInteger)fontIndex
                                         withObject:[fontName stringByTrimmingCharactersInSet:
                                                                  [NSCharacterSet whitespaceCharacterSet]]];
                    }
                    [fontName setString:@""];
                    fontIndex = -1;
                } else
                    [fontName appendFormat:@"%c", c];
                continue;
            }
            if (dest[depth] == COLORS) {
                if (c == ';') {
                    [colors addObject:[NSColor colorWithCalibratedRed:red / 255.0 green:green / 255.0
                                                                 blue:blue / 255.0 alpha:1]];
                    red = green = blue = 0;
                }
                continue;
            }
            [b addChar:from_code_page(c, page)];
            continue;
        }
        /* a control symbol or word */
        if (p >= end)
            break;
        c = *p;
        if (!isalpha(c)) {
            p++;
            if (c == '\'' && end - p >= 2) {
                char hex[3] = {(char)p[0], (char)p[1], 0};
                p += 2;
                if (skipChars > 0) {
                    skipChars--;
                    continue;
                }
                if (!l->skip && dest[depth] == NORMAL)
                    [b addChar:from_code_page((unsigned)strtoul(hex, NULL, 16), page)];
                else if (dest[depth] == FONTS)
                    [fontName appendFormat:@"%C", from_code_page((unsigned)strtoul(hex, NULL, 16), page)];
                continue;
            }
            if (c == '*') {
                starred = YES;
                l->skip = YES;    /* an optional destination this reader doesn't know */
                continue;
            }
            if (l->skip || dest[depth] != NORMAL)
                continue;
            if (c == '\n' || c == '\r')
                [b add:@"\n"];
            else if (c == '~')
                [b addChar:0xa0];
            else if (c == '_')
                [b addChar:0x2011];
            else if (c == '\\' || c == '{' || c == '}')
                [b addChar:c];
            continue;
        }
        char word[32];
        int n = 0;
        while (p < end && isalpha(*p) && n < 31)
            word[n++] = (char)*p++;
        word[n] = 0;
        BOOL hasArg = NO;
        long arg = 0;
        if (p < end && (*p == '-' || isdigit(*p))) {
            hasArg = YES;
            char *stop;
            arg = strtol((const char *)p, &stop, 10);
            p = (const unsigned char *)stop;
        }
        if (p < end && *p == ' ')
            p++;
#define IS(w) (!strcmp(word, w))
        if (IS("u")) {
            if (!l->skip && dest[depth] == NORMAL)
                [b addChar:(unichar)(arg < 0 ? arg + 65536 : arg)];
            skipChars = l->uc;
            continue;
        }
        if (skipChars > 0)
            skipChars = 0;
        if (IS("fonttbl")) {
            dest[depth] = FONTS;
            continue;
        }
        if (IS("colortbl")) {
            dest[depth] = COLORS;
            continue;
        }
        if (dest[depth] == FONTS) {
            if (IS("f"))
                fontIndex = (int)arg;
            continue;
        }
        if (dest[depth] == COLORS) {
            if (IS("red")) red = (int)arg;
            else if (IS("green")) green = (int)arg;
            else if (IS("blue")) blue = (int)arg;
            continue;
        }
        if (IS("stylesheet") || IS("info") || IS("pict") || IS("header") || IS("footer") || IS("headerl") ||
            IS("headerr") || IS("footerl") || IS("footerr") || IS("listtable") || IS("listoverridetable") ||
            IS("revtbl") || IS("rsidtbl") || IS("generator") || IS("xmlnstbl") || IS("themedata") ||
            IS("colorschememapping") || IS("latentstyles") || IS("datastore") || IS("fldinst") || IS("object") ||
            IS("NeXTGraphic") || IS("expandedcolortbl")) {
            l->skip = YES;
            continue;
        }
        (void)starred;
        if (IS("ansicpg")) page = (int)arg;
        else if (IS("mac")) page = 10000;
        else if (IS("pc")) page = 437;
        else if (IS("ansi")) page = 1252;
        else if (IS("uc")) l->uc = (int)arg;
        if (l->skip)
            continue;
        if (IS("par") || IS("line") || IS("sect") || IS("page")) [b add:@"\n"];
        else if (IS("tab")) [b add:@"\t"];
        else if (IS("b")) l->bold = !hasArg || arg != 0;
        else if (IS("i")) l->italic = !hasArg || arg != 0;
        else if (IS("ul")) l->underline = !hasArg || arg != 0;
        else if (IS("ulnone")) l->underline = NO;
        else if (IS("fs")) l->size = arg > 0 ? (int)arg : 24;
        else if (IS("f")) l->font = (int)arg;
        else if (IS("cf")) l->color = (int)arg;
        else if (IS("plain")) {
            l->bold = l->italic = l->underline = NO;
            l->size = 24;
            l->color = 0;
        } else if (IS("pard")) l->align = NSTextAlignmentNatural;
        else if (IS("qc")) l->align = NSTextAlignmentCenter;
        else if (IS("qr")) l->align = NSTextAlignmentRight;
        else if (IS("qj")) l->align = NSTextAlignmentJustified;
        else if (IS("ql")) l->align = NSTextAlignmentLeft;
        else if (IS("emdash")) [b addChar:0x2014];
        else if (IS("endash")) [b addChar:0x2013];
        else if (IS("bullet")) [b addChar:0x2022];
        else if (IS("lquote")) [b addChar:0x2018];
        else if (IS("rquote")) [b addChar:0x2019];
        else if (IS("ldblquote")) [b addChar:0x201c];
        else if (IS("rdblquote")) [b addChar:0x201d];
#undef IS
    }
    [b flush];
    if (docAttrs)
        *docAttrs = @{NSDocumentTypeDocumentAttribute : NSRTFTextDocumentType};
    return [[b->out copy] autorelease];
}

static void rtf_escape(NSMutableString *out, NSString *s)
{
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' || c == '{' || c == '}')
            [out appendFormat:@"\\%C", c];
        else if (c == '\n')
            [out appendString:@"\\\n"];
        else if (c == '\t')
            [out appendString:@"\\tab "];
        else if (c < 0x80)
            [out appendFormat:@"%C", c];
        else
            [out appendFormat:@"\\uc0\\u%d ", (int)(short)c];
    }
}

static NSData *write_rtf(NSAttributedString *s)
{
    NSMutableArray *fonts = [NSMutableArray array], *colors = [NSMutableArray array];
    NSMutableString *body = [NSMutableString string];
    NSUInteger i = 0, n = [s length];
    while (i < n) {
        NSRange r;
        NSDictionary *a = [s attributesAtIndex:i effectiveRange:&r];
        NSFont *f = [a objectForKey:NSFontAttributeName] ?: ADefaultFont();
        NSString *family = [(id)CTFontCopyFamilyName((CTFontRef)f) autorelease] ?: @"Helvetica";
        uint32_t traits = CTFontGetSymbolicTraits((CTFontRef)f);
        if (![fonts containsObject:family])
            [fonts addObject:family];
        int cf = 0;
        NSColor *color = [a objectForKey:NSForegroundColorAttributeName];
        if (color) {
            CGFloat rgba[4];
            AColorRGBA(color, rgba);
            NSString *entry = [NSString stringWithFormat:@"\\red%d\\green%d\\blue%d;", (int)lround(rgba[0] * 255),
                                                         (int)lround(rgba[1] * 255), (int)lround(rgba[2] * 255)];
            if (![colors containsObject:entry])
                [colors addObject:entry];
            cf = (int)[colors indexOfObject:entry] + 1;
        }
        NSParagraphStyle *ps = [a objectForKey:NSParagraphStyleAttributeName];
        NSTextAlignment al = ps ? [ps alignment] : NSTextAlignmentNatural;
        [body appendFormat:@"\\pard%@\\plain\\f%lu\\fs%d\\cf%d%@%@%@ ",
                           al == NSTextAlignmentCenter ? @"\\qc" : al == NSTextAlignmentRight ? @"\\qr"
                                                       : al == NSTextAlignmentJustified    ? @"\\qj" : @"",
                           (unsigned long)[fonts indexOfObject:family], (int)lround([f pointSize] * 2), cf,
                           traits & kCTFontTraitBold ? @"\\b" : @"", traits & kCTFontTraitItalic ? @"\\i" : @"",
                           [[a objectForKey:NSUnderlineStyleAttributeName] integerValue] ? @"\\ul" : @""];
        rtf_escape(body, [[s string] substringWithRange:r]);
        i = NSMaxRange(r);
    }
    NSMutableString *out = [NSMutableString stringWithString:@"{\\rtf1\\ansi\\ansicpg1252\\deff0\n{\\fonttbl"];
    for (NSUInteger k = 0; k < [fonts count]; k++)
        [out appendFormat:@"\\f%lu\\fnil %@;", (unsigned long)k, [fonts objectAtIndex:k]];
    if (![fonts count])
        [out appendString:@"\\f0\\fnil Helvetica;"];
    [out appendString:@"}\n{\\colortbl;"];
    for (NSString *c in colors)
        [out appendString:c];
    [out appendFormat:@"}\n%@}\n", body];
    return [out dataUsingEncoding:NSUTF8StringEncoding]; /* all ASCII: the rest is escaped */
}

/* ---- HTML, simply ------------------------------------------------------------------------- */

static NSString *html_entity(NSString *name)
{
    static NSDictionary *named;
    if (!named)
        named = [@{@"amp" : @"&", @"lt" : @"<", @"gt" : @">", @"quot" : @"\"", @"apos" : @"'", @"nbsp" : @" ",
                   @"copy" : @"©", @"reg" : @"®", @"trade" : @"™", @"mdash" : @"—",
                   @"ndash" : @"–", @"hellip" : @"…", @"lsquo" : @"‘", @"rsquo" : @"’",
                   @"ldquo" : @"“", @"rdquo" : @"”", @"bull" : @"•"} retain];
    if ([name hasPrefix:@"#"]) {
        unsigned v = [name hasPrefix:@"#x"] || [name hasPrefix:@"#X"]
                         ? (unsigned)strtoul([[name substringFromIndex:2] UTF8String], NULL, 16)
                         : (unsigned)strtoul([[name substringFromIndex:1] UTF8String], NULL, 10);
        unichar c = v > 0xffff ? 0xfffd : (unichar)v;
        return [NSString stringWithCharacters:&c length:1];
    }
    return [named objectForKey:[name lowercaseString]];
}

static NSAttributedString *read_html(NSString *html)
{
    ARunBuilder *b = [[[ARunBuilder alloc] init] autorelease];
    NSMutableArray *links = [NSMutableArray array];
    Look *l = &b->look;
    memset(l, 0, sizeof *l);
    l->size = 24;
    l->align = NSTextAlignmentNatural;
    int bold = 0, italic = 0, skip = 0, pre = 0;
    BOOL space = YES;   /* collapse white space, and none at the start of a line */
    NSUInteger i = 0, n = [html length];
    while (i < n) {
        unichar c = [html characterAtIndex:i];
        if (c == '<') {
            NSRange close = [html rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            if (close.location == NSNotFound)
                break;
            NSString *tag = [html substringWithRange:NSMakeRange(i + 1, close.location - i - 1)];
            i = NSMaxRange(close);
            if ([tag hasPrefix:@"!--"]) {
                NSRange endc = [html rangeOfString:@"-->" options:0 range:NSMakeRange(i - [tag length] - 1, n - (i - [tag length] - 1))];
                if (endc.location != NSNotFound)
                    i = NSMaxRange(endc);
                continue;
            }
            BOOL closing = [tag hasPrefix:@"/"];
            NSString *body = closing ? [tag substringFromIndex:1] : tag;
            NSRange sp = [body rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *name = [(sp.location == NSNotFound ? body : [body substringToIndex:sp.location]) lowercaseString];
            if ([name hasSuffix:@"/"])
                name = [name substringToIndex:[name length] - 1];
            if ([name isEqualToString:@"script"] || [name isEqualToString:@"style"] || [name isEqualToString:@"head"] ||
                [name isEqualToString:@"title"])
                skip += closing ? -1 : 1;
            else if ([name isEqualToString:@"b"] || [name isEqualToString:@"strong"] || [name isEqualToString:@"th"])
                bold += closing ? -1 : 1;
            else if ([name isEqualToString:@"i"] || [name isEqualToString:@"em"] || [name isEqualToString:@"cite"])
                italic += closing ? -1 : 1;
            else if ([name isEqualToString:@"pre"])
                pre += closing ? -1 : 1;
            else if ([name length] == 2 && [name characterAtIndex:0] == 'h' && isdigit([name characterAtIndex:1])) {
                bold += closing ? -1 : 1;
                l->size = closing ? 24 : 24 + 2 * (7 - ([name characterAtIndex:1] - '0'));
                [b breakLines:closing ? 1 : 2];
                space = YES;
            } else if ([name isEqualToString:@"br"]) {
                [b add:@"\n"];
                space = YES;
            } else if ([name isEqualToString:@"p"]) {
                [b breakLines:2];
                space = YES;
            } else if ([name isEqualToString:@"div"] || [name isEqualToString:@"tr"] || [name isEqualToString:@"ul"] ||
                       [name isEqualToString:@"ol"] || [name isEqualToString:@"table"] ||
                       [name isEqualToString:@"blockquote"]) {
                [b breakLines:1];
                space = YES;
            } else if ([name isEqualToString:@"li"] && !closing) {
                [b breakLines:1];
                [b add:@"\u2022 "];
                space = YES;
            } else if ([name isEqualToString:@"a"]) {
                if (closing)
                    l->link = nil;
                else {
                    NSRange h = [body rangeOfString:@"href=" options:NSCaseInsensitiveSearch];
                    if (h.location != NSNotFound) {
                        NSString *rest = [body substringFromIndex:NSMaxRange(h)];
                        NSString *q = [rest length] && ([rest characterAtIndex:0] == '"' || [rest characterAtIndex:0] == '\'')
                                          ? [rest substringToIndex:1] : @" ";
                        if (![q isEqualToString:@" "])
                            rest = [rest substringFromIndex:1];
                        NSRange e = [rest rangeOfString:q];
                        NSString *url = e.location == NSNotFound ? rest : [rest substringToIndex:e.location];
                        [links addObject:url];
                        l->link = url;
                    }
                }
            }
            l->bold = bold > 0;
            l->italic = italic > 0;
            continue;
        }
        i++;
        if (skip > 0)
            continue;
        NSString *add;
        if (c == '&') {
            NSRange semi = [html rangeOfString:@";" options:0 range:NSMakeRange(i, MIN(n - i, 10))];
            add = semi.location != NSNotFound ? html_entity([html substringWithRange:NSMakeRange(i, semi.location - i)]) : nil;
            if (add)
                i = NSMaxRange(semi);
            else
                add = @"&";
        } else if (!pre && (c == ' ' || c == '\t' || c == '\n' || c == '\r')) {
            if (space)
                continue;
            add = @" ";
        } else
            add = [NSString stringWithCharacters:&c length:1];
        [b add:add];
        space = !pre && [add isEqualToString:@" "];
        if (pre && [add isEqualToString:@"\n"])
            space = YES;
    }
    [b flush];
    NSMutableAttributedString *out = b->out;
    /* trim white space at the end */
    while ([out length] && [[NSCharacterSet whitespaceAndNewlineCharacterSet]
                               characterIsMember:[[out string] characterAtIndex:[out length] - 1]])
        [out deleteCharactersInRange:NSMakeRange([out length] - 1, 1)];
    return [[out copy] autorelease];
}

static NSString *plain_text(NSData *data, NSStringEncoding enc)
{
    NSString *s = enc ? [[[NSString alloc] initWithData:data encoding:enc] autorelease] : nil;
    if (!s)
        s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!s)
        s = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    return s;
}

static NSString *html_string(NSData *data, NSStringEncoding enc)
{
    NSString *s = plain_text(data, enc);
    /* a <meta> charset of iso-8859-1 means Latin-1 even when the bytes happen to be valid UTF-8 */
    NSRange head = NSMakeRange(0, MIN([s length], 1024));
    if (!enc && [s rangeOfString:@"charset=iso-8859-1" options:NSCaseInsensitiveSearch range:head].location != NSNotFound)
        s = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    return s;
}

/* ---- the AppKit additions to NSAttributedString --------------------------------------------- */

@implementation NSAttributedString (NSAttributedStringDocumentFormats)
- (instancetype)initWithRTF:(NSData *)data documentAttributes:(NSDictionary **)attrs
{
    NSAttributedString *s = data ? read_rtf(data, attrs) : nil;
    if (!s) {
        [self release];
        return nil;
    }
    return [self initWithAttributedString:s];
}
- (instancetype)initWithRTFD:(NSData *)data documentAttributes:(NSDictionary **)attrs
{
    return [self initWithRTF:data documentAttributes:attrs];
}
- (instancetype)initWithHTML:(NSData *)data documentAttributes:(NSDictionary **)attrs
{
    if (attrs)
        *attrs = @{NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType};
    return [self initWithAttributedString:read_html(html_string(data, 0) ?: @"")];
}
- (instancetype)initWithHTML:(NSData *)data baseURL:(NSURL *)base documentAttributes:(NSDictionary **)attrs
{
    return [self initWithHTML:data documentAttributes:attrs];
}
- (instancetype)initWithData:(NSData *)data options:(NSDictionary *)options documentAttributes:(NSDictionary **)attrs
                       error:(NSError **)error
{
    NSString *type = [options objectForKey:NSDocumentTypeDocumentOption];
    NSStringEncoding enc = [[options objectForKey:NSCharacterEncodingDocumentOption] unsignedIntegerValue];
    const char *bytes = [data bytes];
    NSUInteger len = [data length];
    if (!type) {
        if (len >= 5 && !memcmp(bytes, "{\\rtf", 5))
            type = NSRTFTextDocumentType;
        else {
            NSString *head = [plain_text([data subdataWithRange:NSMakeRange(0, MIN(len, 512))], enc) lowercaseString];
            type = [head rangeOfString:@"<html"].location != NSNotFound || [head rangeOfString:@"<!doctype html"].location != NSNotFound ||
                           [head rangeOfString:@"<body"].location != NSNotFound || [head rangeOfString:@"<p>"].location != NSNotFound
                       ? NSHTMLTextDocumentType : NSPlainTextDocumentType;
        }
    }
    if ([type isEqualToString:NSRTFTextDocumentType] || [type isEqualToString:NSRTFDTextDocumentType])
        return [self initWithRTF:data documentAttributes:attrs];
    if ([type isEqualToString:NSHTMLTextDocumentType]) {
        if (attrs)
            *attrs = @{NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType};
        return [self initWithAttributedString:read_html(html_string(data, enc) ?: @"")];
    }
    NSString *s = plain_text(data, enc);
    if (!s) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:259 userInfo:nil];
        [self release];
        return nil;
    }
    if (attrs)
        *attrs = @{NSDocumentTypeDocumentAttribute : NSPlainTextDocumentType};
    return [self initWithString:s attributes:@{NSFontAttributeName : [NSFont userFontOfSize:0] ?: ADefaultFont()}];
}
- (instancetype)initWithURL:(NSURL *)url options:(NSDictionary *)options documentAttributes:(NSDictionary **)attrs
                      error:(NSError **)error
{
    NSData *d = [url isFileURL] ? [NSData dataWithContentsOfFile:[url path]] : nil;
    if (!d) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:nil];
        [self release];
        return nil;
    }
    NSMutableDictionary *o = [NSMutableDictionary dictionaryWithDictionary:options ?: @{}];
    NSString *ext = [[url pathExtension] lowercaseString];
    if (![o objectForKey:NSDocumentTypeDocumentOption]) {
        if ([ext isEqualToString:@"rtf"])
            [o setObject:NSRTFTextDocumentType forKey:NSDocumentTypeDocumentOption];
        else if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"])
            [o setObject:NSHTMLTextDocumentType forKey:NSDocumentTypeDocumentOption];
        else if ([ext isEqualToString:@"txt"])
            [o setObject:NSPlainTextDocumentType forKey:NSDocumentTypeDocumentOption];
    }
    return [self initWithData:d options:o documentAttributes:attrs error:error];
}
- (instancetype)initWithPath:(NSString *)path documentAttributes:(NSDictionary **)attrs
{
    return [self initWithURL:[NSURL fileURLWithPath:path] options:@{} documentAttributes:attrs error:NULL];
}
- (NSData *)RTFFromRange:(NSRange)r documentAttributes:(NSDictionary *)attrs
{
    return write_rtf([self attributedSubstringFromRange:r]);
}
- (NSData *)RTFDFromRange:(NSRange)r documentAttributes:(NSDictionary *)attrs
{
    return [self RTFFromRange:r documentAttributes:attrs];
}
- (NSData *)dataFromRange:(NSRange)r documentAttributes:(NSDictionary *)attrs error:(NSError **)error
{
    NSString *type = [attrs objectForKey:NSDocumentTypeDocumentAttribute];
    if ([type isEqualToString:NSPlainTextDocumentType])
        return [[[self string] substringWithRange:r] dataUsingEncoding:NSUTF8StringEncoding];
    return [self RTFFromRange:r documentAttributes:attrs];
}
@end
