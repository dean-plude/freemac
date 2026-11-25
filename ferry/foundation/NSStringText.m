/* SPDX-License-Identifier: GPL-3.0-or-later
 * The text calls of NSString (freemac 1.219, Ferry 0.43.0): line and
 * paragraph ranges, enumerating lines, paragraphs, composed characters,
 * words and sentences, composed character sequences, Unicode normalization,
 * searching for a character set with options, and the old percent escapes
 * (with CFURL's calls for them). Written for freemac from Apple's public
 * documentation of NSString and CFURL.
 *
 * Words, sentences and composed characters come from this system's ICU
 * break iterators, and normalization from ICU's normalizers, reached as
 * NSRegularExpression reaches ICU. Without ICU, composed characters fall
 * back to surrogate pairs and combining marks, and words to runs of letters
 * and digits. */
#import "FInternal.h"

void *ferry_twin_symbol(const char *install_name, const char *name);

typedef int UErrorCode;
#define U_FAILURE(e) ((e) > 0)
typedef struct UBreakIterator UBreakIterator;
typedef struct UNormalizer2 UNormalizer2;
enum { UBRK_CHARACTER = 0, UBRK_WORD = 1, UBRK_SENTENCE = 3, UBRK_DONE = -1 };

static struct {
    BOOL tried, ok;
    UBreakIterator *(*open)(int type, const char *locale, const unichar *text, int32_t len, UErrorCode *err);
    void (*close)(UBreakIterator *bi);
    int32_t (*first)(UBreakIterator *bi);
    int32_t (*next)(UBreakIterator *bi);
    int32_t (*ruleStatus)(UBreakIterator *bi);
    const UNormalizer2 *(*nfc)(UErrorCode *err), *(*nfd)(UErrorCode *err), *(*nfkc)(UErrorCode *err),
        *(*nfkd)(UErrorCode *err);
    int32_t (*normalize)(const UNormalizer2 *n, const unichar *src, int32_t len, unichar *dest, int32_t cap,
                         UErrorCode *err);
} icu;

static BOOL load_icu(void)
{
    if (icu.tried)
        return icu.ok;
    icu.tried = YES;
    const char *lib = "/usr/lib/libicucore.A.dylib";
#define LOAD(field, name) *(void **)&icu.field = ferry_twin_symbol(lib, name)
    LOAD(open, "ubrk_open");
    LOAD(close, "ubrk_close");
    LOAD(first, "ubrk_first");
    LOAD(next, "ubrk_next");
    LOAD(ruleStatus, "ubrk_getRuleStatus");
    LOAD(nfc, "unorm2_getNFCInstance");
    LOAD(nfd, "unorm2_getNFDInstance");
    LOAD(nfkc, "unorm2_getNFKCInstance");
    LOAD(nfkd, "unorm2_getNFKDInstance");
    LOAD(normalize, "unorm2_normalize");
#undef LOAD
    icu.ok = icu.open && icu.close && icu.first && icu.next && icu.ruleStatus && icu.nfc && icu.nfd && icu.nfkc &&
             icu.nfkd && icu.normalize;
    return icu.ok;
}

static unichar *copy_chars(NSString *s, NSUInteger *n)
{
    *n = [s length];
    unichar *c = malloc((*n + 1) * sizeof(unichar));
    [s getCharacters:c range:NSMakeRange(0, *n)];
    return c;
}

static BOOL is_line_end(unichar c) { return c == '\n' || c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029; }
static BOOL is_paragraph_end(unichar c) { return c == '\n' || c == '\r' || c == 0x2029; }

static void line_bounds(NSString *self, NSUInteger *startp, NSUInteger *endp, NSUInteger *contentsEndp, NSRange r,
                        BOOL (*ends)(unichar))
{
    NSUInteger n = [self length];
    if (r.location > n || r.length > n - r.location)
        FRaise(NSRangeException, @"-[NSString getLineStart:end:contentsEnd:forRange:]: range {%lu, %lu} out of bounds",
               (unsigned long)r.location, (unsigned long)r.length);
    unichar *c = malloc((n + 1) * sizeof(unichar));
    [self getCharacters:c range:NSMakeRange(0, n)];
    NSUInteger start = r.location;
    /* a \r\n pair is one line end: the start of a range on its \n is the \r's line */
    if (start > 0 && start < n && c[start] == '\n' && c[start - 1] == '\r')
        start--;
    while (start > 0 && !ends(c[start - 1]))
        start--;
    NSUInteger last = r.length ? r.location + r.length - 1 : r.location;
    NSUInteger i = r.length ? last : r.location;
    if (r.length && last < n && ends(c[last])) {
        i = last; /* the range ends on a line end: that line ends there */
    } else {
        while (i < n && !ends(c[i]))
            i++;
    }
    NSUInteger contentsEnd = i, end = i;
    if (i < n) {
        end = i + 1;
        if (c[i] == '\r' && i + 1 < n && c[i + 1] == '\n')
            end = i + 2;
        else if (c[i] == '\n' && i > 0 && c[i - 1] == '\r' && contentsEnd > start && contentsEnd - 1 >= start)
            contentsEnd = i - 1;
    }
    free(c);
    if (startp)
        *startp = start;
    if (endp)
        *endp = end;
    if (contentsEndp)
        *contentsEndp = contentsEnd;
}

/* The ranges of the pieces a range holds, as enumerateSubstringsInRange:
 * gives them: substring ranges and enclosing ranges, in order. */
typedef struct {
    NSRange sub, enclosing;
} Piece;

static void add_piece(Piece **list, NSUInteger *count, NSUInteger *cap, NSRange sub, NSRange enclosing)
{
    if (*count == *cap) {
        *cap = *cap ? *cap * 2 : 16;
        *list = realloc(*list, *cap * sizeof(Piece));
    }
    (*list)[(*count)++] = (Piece){sub, enclosing};
}

static BOOL is_word_char(unichar ch)
{
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch] || ch == '_' || ch == '\'';
}

/* Composed character sequences without ICU: a surrogate pair, or a character
 * and the combining marks after it. */
static NSUInteger next_composed(const unichar *c, NSUInteger n, NSUInteger i)
{
    if (i + 1 < n && c[i] >= 0xd800 && c[i] < 0xdc00 && c[i + 1] >= 0xdc00 && c[i + 1] < 0xe000)
        i += 2;
    else if (c[i] == '\r' && i + 1 < n && c[i + 1] == '\n')
        return i + 2;
    else
        i++;
    while (i < n && ((c[i] >= 0x300 && c[i] < 0x370) || (c[i] >= 0xfe20 && c[i] < 0xfe30) || c[i] == 0x200d ||
                     (c[i] >= 0xfe00 && c[i] < 0xfe10)))
        i++;
    return i;
}

/* The boundaries ICU's iterator of a kind finds in c[0..n), with each
 * segment's rule status; NULL without ICU. */
static int32_t *icu_breaks(int type, const unichar *c, NSUInteger n, int32_t **statuses, NSUInteger *count)
{
    if (!load_icu() || n > INT32_MAX)
        return NULL;
    UErrorCode err = 0;
    UBreakIterator *bi = icu.open(type, "", c, (int32_t)n, &err);
    if (!bi || U_FAILURE(err))
        return NULL;
    NSUInteger cap = 32, k = 0;
    int32_t *b = malloc(cap * sizeof(int32_t)), *st = malloc(cap * sizeof(int32_t));
    for (int32_t p = icu.first(bi); p != UBRK_DONE; p = icu.next(bi)) {
        if (k == cap) {
            cap *= 2;
            b = realloc(b, cap * sizeof(int32_t));
            st = realloc(st, cap * sizeof(int32_t));
        }
        st[k] = k ? icu.ruleStatus(bi) : 0;
        b[k++] = p;
    }
    icu.close(bi);
    *statuses = st;
    *count = k;
    return b;
}

static Piece *pieces(NSString *self, NSRange range, NSStringEnumerationOptions opts, NSUInteger *count)
{
    NSUInteger n;
    unichar *all = copy_chars(self, &n);
    if (range.location > n || range.length > n - range.location) {
        free(all);
        FRaise(NSRangeException, @"-[NSString enumerateSubstringsInRange:options:usingBlock:]: range {%lu, %lu} out "
                                  "of bounds", (unsigned long)range.location, (unsigned long)range.length);
    }
    const unichar *c = all + range.location;
    NSUInteger len = range.length, base = range.location, cap = 0;
    Piece *list = NULL;
    *count = 0;
    NSUInteger kind = opts & 0xff;
    if (kind == NSStringEnumerationByLines || kind == NSStringEnumerationByParagraphs) {
        BOOL (*ends)(unichar) = kind == NSStringEnumerationByLines ? is_line_end : is_paragraph_end;
        NSUInteger start = 0;
        for (NSUInteger i = 0; i < len; i++) {
            if (!ends(c[i]))
                continue;
            NSUInteger e = i + 1;
            if (c[i] == '\r' && i + 1 < len && c[i + 1] == '\n')
                e++;
            add_piece(&list, count, &cap, NSMakeRange(base + start, i - start), NSMakeRange(base + start, e - start));
            start = e;
            i = e - 1;
        }
        if (start < len)
            add_piece(&list, count, &cap, NSMakeRange(base + start, len - start),
                      NSMakeRange(base + start, len - start));
    } else if (kind == NSStringEnumerationByComposedCharacterSequences) {
        int32_t *st = NULL;
        NSUInteger k = 0;
        int32_t *b = icu_breaks(UBRK_CHARACTER, c, len, &st, &k);
        if (b) {
            for (NSUInteger i = 1; i < k; i++)
                add_piece(&list, count, &cap, NSMakeRange(base + (NSUInteger)b[i - 1], (NSUInteger)(b[i] - b[i - 1])),
                          NSMakeRange(base + (NSUInteger)b[i - 1], (NSUInteger)(b[i] - b[i - 1])));
            free(b);
            free(st);
        } else {
            for (NSUInteger i = 0; i < len;) {
                NSUInteger e = next_composed(c, len, i);
                add_piece(&list, count, &cap, NSMakeRange(base + i, e - i), NSMakeRange(base + i, e - i));
                i = e;
            }
        }
    } else if (kind == NSStringEnumerationByWords) {
        /* A word's enclosing range runs to the next word (the first one's from
         * the start of the range); spaces and punctuation are no word. */
        NSRange *words = NULL;
        NSUInteger nw = 0, wcap = 0;
        int32_t *st = NULL;
        NSUInteger k = 0;
        int32_t *b = icu_breaks(UBRK_WORD, c, len, &st, &k);
        if (b) {
            for (NSUInteger i = 1; i < k; i++) {
                if (st[i] < 100) /* UBRK_WORD_NONE: spaces, punctuation */
                    continue;
                if (nw == wcap)
                    words = realloc(words, (wcap = wcap ? wcap * 2 : 16) * sizeof(NSRange));
                words[nw++] = NSMakeRange((NSUInteger)b[i - 1], (NSUInteger)(b[i] - b[i - 1]));
            }
            free(b);
            free(st);
        } else {
            for (NSUInteger i = 0; i < len;) {
                if (!is_word_char(c[i])) {
                    i++;
                    continue;
                }
                NSUInteger e = i;
                while (e < len && is_word_char(c[e]))
                    e++;
                if (nw == wcap)
                    words = realloc(words, (wcap = wcap ? wcap * 2 : 16) * sizeof(NSRange));
                words[nw++] = NSMakeRange(i, e - i);
                i = e;
            }
        }
        for (NSUInteger i = 0; i < nw; i++) {
            NSUInteger es = i ? words[i].location : 0, ee = i + 1 < nw ? words[i + 1].location : len;
            add_piece(&list, count, &cap, NSMakeRange(base + words[i].location, words[i].length),
                      NSMakeRange(base + es, ee - es));
        }
        free(words);
    } else if (kind == NSStringEnumerationBySentences) {
        int32_t *st = NULL;
        NSUInteger k = 0;
        int32_t *b = icu_breaks(UBRK_SENTENCE, c, len, &st, &k);
        NSUInteger *cuts = NULL, nc = 0;
        if (b) {
            cuts = malloc(k * sizeof(NSUInteger));
            for (NSUInteger i = 0; i < k; i++)
                cuts[nc++] = (NSUInteger)b[i];
            free(b);
            free(st);
        } else {
            /* without ICU: a sentence ends after . ! or ? and the spaces after them */
            cuts = malloc((len + 2) * sizeof(NSUInteger));
            cuts[nc++] = 0;
            for (NSUInteger i = 0; i < len; i++) {
                if (c[i] != '.' && c[i] != '!' && c[i] != '?' && !is_paragraph_end(c[i]))
                    continue;
                NSUInteger e = i + 1;
                while (e < len && (c[e] == ' ' || c[e] == '\t' || is_line_end(c[e])))
                    e++;
                if (e < len)
                    cuts[nc++] = e;
                i = e - 1;
            }
            if (len)
                cuts[nc++] = len;
        }
        for (NSUInteger i = 1; i < nc; i++) {
            NSUInteger s = cuts[i - 1], e = cuts[i], t = e;
            while (t > s && (c[t - 1] == ' ' || c[t - 1] == '\t' || is_line_end(c[t - 1])))
                t--;
            add_piece(&list, count, &cap, NSMakeRange(base + s, t - s), NSMakeRange(base + s, e - s));
        }
        free(cuts);
    }
    free(all);
    return list;
}

@implementation NSString (FerryText)

- (void)getLineStart:(NSUInteger *)start end:(NSUInteger *)end contentsEnd:(NSUInteger *)contentsEnd
            forRange:(NSRange)range
{
    line_bounds(self, start, end, contentsEnd, range, is_line_end);
}
- (void)getParagraphStart:(NSUInteger *)start end:(NSUInteger *)end contentsEnd:(NSUInteger *)contentsEnd
                 forRange:(NSRange)range
{
    line_bounds(self, start, end, contentsEnd, range, is_paragraph_end);
}
- (NSRange)lineRangeForRange:(NSRange)range
{
    NSUInteger s, e;
    line_bounds(self, &s, &e, NULL, range, is_line_end);
    return NSMakeRange(s, e - s);
}
- (NSRange)paragraphRangeForRange:(NSRange)range
{
    NSUInteger s, e;
    line_bounds(self, &s, &e, NULL, range, is_paragraph_end);
    return NSMakeRange(s, e - s);
}
- (void)enumerateSubstringsInRange:(NSRange)range options:(NSStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSString *substring, NSRange substringRange, NSRange enclosingRange,
                                             BOOL *stop))block
{
    NSUInteger count;
    Piece *list = pieces(self, range, opts, &count);
    BOOL stop = NO, reverse = (opts & NSStringEnumerationReverse) != 0;
    for (NSUInteger k = 0; k < count && !stop; k++) {
        Piece p = list[reverse ? count - 1 - k : k];
        NSString *sub = (opts & NSStringEnumerationSubstringNotRequired) ? nil : [self substringWithRange:p.sub];
        block(sub, p.sub, p.enclosing, &stop);
    }
    free(list);
}
- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index
{
    NSUInteger n = [self length];
    if (index >= n)
        FRaise(NSRangeException, @"-[NSString rangeOfComposedCharacterSequenceAtIndex:]: index %lu out of bounds",
               (unsigned long)index);
    NSUInteger count;
    Piece *list = pieces(self, NSMakeRange(0, n), NSStringEnumerationByComposedCharacterSequences, &count);
    NSRange r = NSMakeRange(index, 1);
    for (NSUInteger k = 0; k < count; k++)
        if (NSLocationInRange(index, list[k].sub)) {
            r = list[k].sub;
            break;
        }
    free(list);
    return r;
}
- (NSRange)rangeOfComposedCharacterSequencesForRange:(NSRange)range
{
    NSUInteger n = [self length];
    if (range.location >= n)
        return NSMakeRange(n, 0);
    NSUInteger s = [self rangeOfComposedCharacterSequenceAtIndex:range.location].location;
    if (range.length == 0)
        return NSMakeRange(s, 0);
    NSUInteger last = MIN(NSMaxRange(range), n) - 1;
    return NSMakeRange(s, NSMaxRange([self rangeOfComposedCharacterSequenceAtIndex:last]) - s);
}

static NSString *normalized(NSString *self, int form)
{
    if (!load_icu())
        return [[self copy] autorelease];
    UErrorCode err = 0;
    const UNormalizer2 *nz = form == 0 ? icu.nfc(&err) : form == 1 ? icu.nfd(&err) : form == 2 ? icu.nfkc(&err)
                                                                                           : icu.nfkd(&err);
    if (!nz || U_FAILURE(err))
        return [[self copy] autorelease];
    NSUInteger n;
    unichar *c = copy_chars(self, &n);
    int32_t cap = (int32_t)n * 4 + 16;
    unichar *out = malloc((size_t)cap * sizeof(unichar));
    err = 0;
    int32_t got = icu.normalize(nz, c, (int32_t)n, out, cap, &err);
    NSString *r = U_FAILURE(err) ? [[self copy] autorelease] : FStringFromChars(out, (NSUInteger)got);
    free(c);
    free(out);
    return r;
}
- (NSString *)precomposedStringWithCanonicalMapping { return normalized(self, 0); }
- (NSString *)decomposedStringWithCanonicalMapping { return normalized(self, 1); }
- (NSString *)precomposedStringWithCompatibilityMapping { return normalized(self, 2); }
- (NSString *)decomposedStringWithCompatibilityMapping { return normalized(self, 3); }

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(NSStringCompareOptions)mask
{
    return [self rangeOfCharacterFromSet:set options:mask range:NSMakeRange(0, [self length])];
}
/* Backwards and anchored searches; a character is a UTF-16 unit, or a
 * surrogate pair as one character. Case and diacritics are always literal. */
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(NSStringCompareOptions)mask range:(NSRange)range
{
    NSUInteger n = [self length];
    if (range.location > n || range.length > n - range.location)
        FRaise(NSRangeException, @"-[NSString rangeOfCharacterFromSet:options:range:]: range {%lu, %lu} out of bounds",
               (unsigned long)range.location, (unsigned long)range.length);
    if (!range.length)
        return NSMakeRange(NSNotFound, 0);
    unichar *c = malloc(range.length * sizeof(unichar));
    [self getCharacters:c range:range];
    BOOL back = (mask & NSBackwardsSearch) != 0, anchored = (mask & NSAnchoredSearch) != 0;
    NSRange found = NSMakeRange(NSNotFound, 0);
    for (NSUInteger k = 0; k < range.length; k++) {
        NSUInteger i = back ? range.length - 1 - k : k, w = 1;
        UTF32Char ch = c[i];
        if (!back && ch >= 0xd800 && ch < 0xdc00 && i + 1 < range.length && c[i + 1] >= 0xdc00 && c[i + 1] < 0xe000)
            ch = 0x10000 + ((ch - 0xd800) << 10) + (c[i + 1] - 0xdc00u), w = 2;
        else if (back && ch >= 0xdc00 && ch < 0xe000 && i > 0 && c[i - 1] >= 0xd800 && c[i - 1] < 0xdc00)
            ch = 0x10000 + ((c[i - 1] - 0xd800u) << 10) + (ch - 0xdc00), w = 2, i--;
        if (ch > 0xffff ? [set longCharacterIsMember:ch] : [set characterIsMember:(unichar)ch]) {
            found = NSMakeRange(range.location + i, w);
            break;
        }
        if (w == 2)
            k++;
        if (anchored)
            break;
    }
    free(c);
    return found;
}

- (NSString *)stringByAddingPercentEscapesUsingEncoding:(NSStringEncoding)enc
{
    return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)self, NULL, NULL,
                                                                 CFStringConvertNSStringEncodingToEncoding(enc))
        autorelease];
}
- (NSString *)stringByReplacingPercentEscapesUsingEncoding:(NSStringEncoding)enc
{
    return [(NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
        NULL, (CFStringRef)self, CFSTR(""), CFStringConvertNSStringEncodingToEncoding(enc)) autorelease];
}
@end

void CFStringNormalize(CFMutableStringRef s, CFStringNormalizationForm form)
{
    /* the forms are numbered D, KD, C, KC */
    static const int forms[] = {1, 3, 0, 2};
    if (form >= 0 && form <= 3)
        [(NSMutableString *)s setString:normalized((NSString *)s, forms[form])];
}

/* ---- the old percent escapes ------------------------------------------------------------ */

/* The characters a URL may hold as they are (RFC 2396, with % and #). */
static BOOL url_legal(unichar c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || (c && strchr("-_.!~*'();/?:@&=+$,#%", c));
}

CFStringRef CFURLCreateStringByAddingPercentEscapes(CFAllocatorRef allocator, CFStringRef original,
                                                    CFStringRef leaveUnescaped, CFStringRef escapeAnyway,
                                                    CFStringEncoding encoding)
{
    NSString *s = (NSString *)original, *leave = (NSString *)leaveUnescaped, *escape = (NSString *)escapeAnyway;
    NSMutableString *out = [[NSMutableString alloc] init];
    NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(encoding);
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL keep = leave && [leave rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound;
        if (!keep)
            keep = url_legal(c) && !(escape && [escape rangeOfString:[NSString stringWithCharacters:&c length:1]].location !=
                                                   NSNotFound);
        if (keep) {
            [out appendFormat:@"%C", c];
            continue;
        }
        NSUInteger w = (c >= 0xd800 && c < 0xdc00 && i + 1 < n) ? 2 : 1;
        NSData *d = [[s substringWithRange:NSMakeRange(i, w)] dataUsingEncoding:enc];
        if (!d) {
            [out release];
            return NULL;
        }
        const unsigned char *b = [d bytes];
        for (NSUInteger k = 0; k < [d length]; k++)
            [out appendFormat:@"%%%02X", b[k]];
        i += w - 1;
    }
    return (CFStringRef)out;
}

static int hexval(unichar c)
{
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10
                                                                                                     : -1;
}

/* charactersToLeaveEscaped NULL replaces no escape, "" every one; the bytes
 * of a run of escapes must be text in the encoding, or the result is NULL. */
CFStringRef CFURLCreateStringByReplacingPercentEscapesUsingEncoding(CFAllocatorRef allocator, CFStringRef original,
                                                                    CFStringRef leaveEscaped,
                                                                    CFStringEncoding encoding)
{
    NSString *s = (NSString *)original, *leave = (NSString *)leaveEscaped;
    if (!leave)
        return (CFStringRef)[s copy];
    NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(encoding);
    NSMutableString *out = [[NSMutableString alloc] init];
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n;) {
        unichar c = [s characterAtIndex:i];
        if (c != '%') {
            [out appendFormat:@"%C", c];
            i++;
            continue;
        }
        NSMutableData *bytes = [NSMutableData data];
        NSUInteger j = i;
        while (j + 2 < n && [s characterAtIndex:j] == '%' && hexval([s characterAtIndex:j + 1]) >= 0 &&
               hexval([s characterAtIndex:j + 2]) >= 0) {
            unsigned char b = (unsigned char)(hexval([s characterAtIndex:j + 1]) * 16 + hexval([s characterAtIndex:j + 2]));
            [bytes appendBytes:&b length:1];
            j += 3;
        }
        if (![bytes length]) {
            [out release];
            return NULL;
        }
        NSString *t = [[[NSString alloc] initWithData:bytes encoding:enc] autorelease];
        if (!t) {
            [out release];
            return NULL;
        }
        if ([leave length]) {
            /* put back the escapes of the characters to leave */
            NSMutableString *kept = [NSMutableString string];
            for (NSUInteger k = 0; k < [t length]; k++) {
                NSString *ch = [t substringWithRange:NSMakeRange(k, 1)];
                if ([leave rangeOfString:ch].location != NSNotFound) {
                    NSData *d = [ch dataUsingEncoding:enc];
                    for (NSUInteger q = 0; q < [d length]; q++)
                        [kept appendFormat:@"%%%02X", ((const unsigned char *)[d bytes])[q]];
                } else {
                    [kept appendString:ch];
                }
            }
            t = kept;
        }
        [out appendString:t];
        i = j;
    }
    return (CFStringRef)out;
}
CFStringRef CFURLCreateStringByReplacingPercentEscapes(CFAllocatorRef allocator, CFStringRef original,
                                                       CFStringRef leaveEscaped)
{
    return CFURLCreateStringByReplacingPercentEscapesUsingEncoding(allocator, original, leaveEscaped,
                                                                   kCFStringEncodingUTF8);
}
