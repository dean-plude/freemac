/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSString, NSMutableString, string literals (@"..."),
 * NSCharacterSet and printf-style formatting with %@. Strings hold UTF-16
 * code units, so lengths and indexes match a Mac's. */
#import "FInternal.h"

/* ---- UTF-8 and UTF-16 --------------------------------------------------------- */

unichar *FDecodeUTF8(const char *s, NSUInteger len, NSUInteger *outLen)
{
    unichar *out = malloc((len + 1) * sizeof(unichar));
    NSUInteger n = 0;
    const unsigned char *p = (const unsigned char *)s, *end = p + len;
    while (p < end) {
        uint32_t c = *p++;
        int extra = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : c >= 0xc0 ? 1 : 0;
        if (c >= 0x80 && c < 0xc0) {
            out[n++] = 0xfffd;
            continue;
        }
        c &= extra == 3 ? 0x07 : extra == 2 ? 0x0f : extra == 1 ? 0x1f : 0x7f;
        for (int i = 0; i < extra; i++) {
            if (p >= end || (*p & 0xc0) != 0x80) {
                c = 0xfffd;
                break;
            }
            c = (c << 6) | (*p++ & 0x3f);
        }
        if (c >= 0x10000) {
            c -= 0x10000;
            out[n++] = 0xd800 + (c >> 10);
            out[n++] = 0xdc00 + (c & 0x3ff);
        } else {
            out[n++] = c;
        }
    }
    *outLen = n;
    return out;
}

char *FEncodeUTF8(const unichar *c, NSUInteger len, NSUInteger *outLen)
{
    char *out = malloc(len * 3 + 1);
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < len; i++) {
        uint32_t u = c[i];
        if (u >= 0xd800 && u < 0xdc00 && i + 1 < len && c[i + 1] >= 0xdc00 && c[i + 1] < 0xe000) {
            u = 0x10000 + ((u - 0xd800) << 10) + (c[i + 1] - 0xdc00);
            i++;
        }
        if (u < 0x80) {
            out[n++] = u;
        } else if (u < 0x800) {
            out[n++] = 0xc0 | (u >> 6);
            out[n++] = 0x80 | (u & 0x3f);
        } else if (u < 0x10000) {
            out[n++] = 0xe0 | (u >> 12);
            out[n++] = 0x80 | ((u >> 6) & 0x3f);
            out[n++] = 0x80 | (u & 0x3f);
        } else {
            out[n++] = 0xf0 | (u >> 18);
            out[n++] = 0x80 | ((u >> 12) & 0x3f);
            out[n++] = 0x80 | ((u >> 6) & 0x3f);
            out[n++] = 0x80 | (u & 0x3f);
        }
    }
    out[n] = 0;
    if (outLen)
        *outLen = n;
    return out;
}

NSUInteger FHashChars(const unichar *c, NSUInteger len)
{
    NSUInteger h = 5381;
    for (NSUInteger i = 0; i < len; i++)
        h = h * 33 + c[i];
    return h;
}

/* ---- the concrete classes --------------------------------------------------------- */

@interface NSConcreteString : NSString {
@public
    unichar *_chars;
    NSUInteger _len;
    char *_utf8;
}
@end

@interface NSConcreteMutableString : NSMutableString {
@public
    unichar *_chars;
    NSUInteger _len, _cap;
    char *_utf8;
}
@end

/* What clang emits for @"...": the class, flags, the bytes and the length. */
@interface __NSCFConstantString : NSString {
    int _flags;
    const char *_ptr;
    long _length;
}
@end

__asm__(".globl ___CFConstantStringClassReference\n"
        ".set ___CFConstantStringClassReference, _OBJC_CLASS_$___NSCFConstantString\n");

static unichar *chars_of(NSString *s, NSUInteger *len, BOOL *mustFree)
{
    NSUInteger n = [s length];
    *len = n;
    Class c = object_getClass(s);
    if (c == [NSConcreteString class]) {
        *mustFree = NO;
        return ((NSConcreteString *)s)->_chars;
    }
    if (c == [NSConcreteMutableString class]) {
        *mustFree = NO;
        return ((NSConcreteMutableString *)s)->_chars;
    }
    unichar *buf = malloc((n + 1) * sizeof(unichar));
    [s getCharacters:buf range:NSMakeRange(0, n)];
    *mustFree = YES;
    return buf;
}

#define WITH_CHARS(str, var, lenvar) \
    NSUInteger lenvar; BOOL var##_free; unichar *var = chars_of((str), &lenvar, &var##_free)
#define DONE_CHARS(var) do { if (var##_free) free(var); } while (0)

NSString *FStringFromChars(const unichar *c, NSUInteger len)
{
    return [[[NSConcreteString alloc] initWithCharacters:c length:len] autorelease];
}

NSString *FStringFromUTF8(const char *s, NSUInteger len)
{
    NSUInteger n;
    unichar *c = FDecodeUTF8(s, len, &n);
    NSConcreteString *str = [NSConcreteString alloc];
    str->_chars = c;
    str->_len = n;
    return [str autorelease];
}

/* ---- NSString ------------------------------------------------------------------------- */

@implementation NSString

+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSString class])
        return class_createInstance([NSConcreteString class], 0);
    if (self == [NSMutableString class])
        return class_createInstance([NSConcreteMutableString class], 0);
    return [super allocWithZone:zone];
}

/* primitives (subclasses override) */
- (NSUInteger)length { return 0; }
- (unichar)characterAtIndex:(NSUInteger)index
{
    FRaise(NSRangeException, @"-[NSString characterAtIndex:]: index %lu out of bounds", (unsigned long)index);
}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range
{
    for (NSUInteger i = 0; i < range.length; i++)
        buffer[i] = [self characterAtIndex:range.location + i];
}
/* every character, as Apple's older -getCharacters: (deprecated, still
 * sent: Chromium's text input does) (freemac 1.266) */
- (void)getCharacters:(unichar *)buffer { [self getCharacters:buffer range:NSMakeRange(0, [self length])]; }
- (instancetype)initWithCharacters:(const unichar *)chars length:(NSUInteger)length
{
    [self release];
    return [[NSConcreteString alloc] initWithCharacters:chars length:length];
}

+ (instancetype)string { return [[[self alloc] init] autorelease]; }
+ (instancetype)stringWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
+ (instancetype)stringWithUTF8String:(const char *)s { return [[[self alloc] initWithUTF8String:s] autorelease]; }
+ (instancetype)stringWithCString:(const char *)s encoding:(NSStringEncoding)enc
{
    return [[[self alloc] initWithCString:s encoding:enc] autorelease];
}
+ (instancetype)stringWithCharacters:(const unichar *)c length:(NSUInteger)n
{
    return [[[self alloc] initWithCharacters:c length:n] autorelease];
}
+ (instancetype)stringWithFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    id s = [[self alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    return [s autorelease];
}
+ (instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error
{
    return [[[self alloc] initWithContentsOfFile:path encoding:enc error:error] autorelease];
}
+ (instancetype)stringWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding)enc error:(NSError **)error
{
    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"data"]) {
        NSString *s = FStringWithContentsOfNetworkURL(url, enc, NULL, error);
        return s ? [self stringWithString:s] : nil;
    }
    return [self stringWithContentsOfFile:[url path] encoding:enc error:error];
}

- (instancetype)init
{
    /* a subclass of the app's own that keeps its characters itself and calls
     * [super init] is itself, as on a Mac (freemac 1.225) */
    if ([self methodForSelector:@selector(initWithCharacters:length:)] ==
        [NSString instanceMethodForSelector:@selector(initWithCharacters:length:)])
        return self;
    return [self initWithCharacters:NULL length:0];
}
- (instancetype)initWithString:(NSString *)s
{
    WITH_CHARS(s, c, n);
    id r = [self initWithCharacters:c length:n];
    DONE_CHARS(c);
    return r;
}
- (instancetype)initWithUTF8String:(const char *)s
{
    if (!s) {
        [self release];
        FRaise(NSInvalidArgumentException, @"-[NSString initWithUTF8String:]: NULL cString");
    }
    NSUInteger n;
    unichar *c = FDecodeUTF8(s, strlen(s), &n);   /* lenient: a bad byte reads as U+FFFD */
    id r = [self initWithCharacters:c length:n];
    free(c);
    return r;
}
- (instancetype)initWithCString:(const char *)s encoding:(NSStringEncoding)enc
{
    return [self initWithBytes:s length:s ? strlen(s) : 0 encoding:enc];
}
- (instancetype)initWithData:(NSData *)data encoding:(NSStringEncoding)enc
{
    return [self initWithBytes:[data bytes] length:[data length] encoding:enc];
}
- (instancetype)initWithFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    id r = [self initWithFormat:format arguments:ap];
    va_end(ap);
    return r;
}
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)args
{
    return [self initWithString:FFormat(format, args)];
}
- (instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) {
        FSetError(error, FPosixError(errno, path));
        [self release];
        return nil;
    }
    id r = [self initWithData:d encoding:enc];
    if (!r)   /* the bytes aren't in that encoding */
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:261
                                         userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]]);
    return r;
}

- (id)copyWithZone:(NSZone *)zone { return [[NSString allocWithZone:zone] initWithString:self]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableString allocWithZone:zone] initWithString:self]; }
- (NSString *)description { return self; }
- (NSUInteger)hash
{
    WITH_CHARS(self, c, n);
    NSUInteger h = FHashChars(c, n);
    DONE_CHARS(c);
    return h;
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    return [other isKindOfClass:[NSString class]] && [self isEqualToString:other];
}
- (BOOL)isEqualToString:(NSString *)other
{
    if (other == self)
        return YES;
    if (!other || [other length] != [self length])
        return NO;
    return [self compare:other] == NSOrderedSame;
}

- (const char *)UTF8String
{
    WITH_CHARS(self, c, n);
    char *s = FEncodeUTF8(c, n, NULL);
    DONE_CHARS(c);
    [NSData dataWithBytesNoCopy:s length:strlen(s) + 1 freeWhenDone:YES];   /* frees it later */
    return s;
}
- (const char *)fileSystemRepresentation { return [self UTF8String]; }
/* comparing */
static unichar fold(unichar c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }

/* The base letters of the accented Latin letters of U+00C0 to U+017F, for
 * NSDiacriticInsensitiveSearch (freemac 1.221, Ferry 0.45.0); 0 where a
 * letter has no one-letter base. */
static const char latin_base[] =
    "AAAAAAACEEEEIIII" "DNOOOOO\0OUUUUYTs" "aaaaaaaceeeeiiii" "dnooooo\0ouuuuyty"
    "AaAaAaCcCcCcCcDd" "DdEeEeEeEeEeGgGg" "GgGgHhHhIiIiIiIi" "IiJjJjKkkLlLlLlL"
    "lLlNnNnNnnNnOoOo" "OoOoRrRrRrSsSsSs" "SsTtTtTtUuUuUuUu" "UuUuWwYyYZzZzZzs";

/* A character as the options compare it: with case folded (ASCII and
 * Latin-1), accents taken off Latin letters, and full-width forms as ASCII. */
static unichar fold_with(unichar c, NSStringCompareOptions mask)
{
    if ((mask & NSWidthInsensitiveSearch) && c >= 0xFF01 && c <= 0xFF5E)
        c = (unichar)(c - 0xFF01 + 0x21);
    if ((mask & NSDiacriticInsensitiveSearch) && c >= 0xC0 && c <= 0x17F && c != 0xD7 && c != 0xF7) {
        char b = latin_base[c - 0xC0];
        if (b)
            c = (unichar)b;
    }
    if (mask & NSCaseInsensitiveSearch) {
        c = fold(c);
        if (c >= 0xC0 && c <= 0xDE && c != 0xD7)
            c += 0x20;
    }
    return c;
}
#define FOLDING (NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch)

- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask
{
    WITH_CHARS(self, a, na);
    WITH_CHARS(other, b, nb);
    NSComparisonResult r = NSOrderedSame;
    NSUInteger i = 0, j = 0;
    while (r == NSOrderedSame && i < na && j < nb) {
        if ((mask & NSNumericSearch) && a[i] >= '0' && a[i] <= '9' && b[j] >= '0' && b[j] <= '9') {
            unsigned long long x = 0, y = 0;
            while (i < na && a[i] >= '0' && a[i] <= '9')
                x = x * 10 + (a[i++] - '0');
            while (j < nb && b[j] >= '0' && b[j] <= '9')
                y = y * 10 + (b[j++] - '0');
            r = x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
            continue;
        }
        unichar x = a[i++], y = b[j++];
        if (mask & FOLDING) {
            x = fold_with(x, mask);
            y = fold_with(y, mask);
        }
        r = x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }
    if (r == NSOrderedSame)
        r = (na - i) < (nb - j) ? NSOrderedAscending : (na - i) > (nb - j) ? NSOrderedDescending : NSOrderedSame;
    DONE_CHARS(a);
    DONE_CHARS(b);
    return r;
}
- (NSComparisonResult)compare:(NSString *)other { return [self compare:other options:0]; }
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)other
{
    return [self compare:other options:NSCaseInsensitiveSearch];
}
- (NSComparisonResult)localizedCompare:(NSString *)other { return [self compare:other]; }
- (NSComparisonResult)localizedCaseInsensitiveCompare:(NSString *)other { return [self caseInsensitiveCompare:other]; }

/* searching */
NSRange FRegexSearch(NSString *string, NSString *pattern, NSStringCompareOptions mask, NSRange range);
NSUInteger FRegexReplace(NSMutableString *string, NSString *pattern, NSString *templ, NSStringCompareOptions mask,
                         NSRange range); /* NSRegularExpression.m */
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)mask range:(NSRange)range
{
    if (mask & NSRegularExpressionSearch)
        return FRegexSearch(self, s, mask, range);
    NSRange none = {NSNotFound, 0};
    WITH_CHARS(self, a, na);
    WITH_CHARS(s, b, nb);
    if (NSMaxRange(range) > na || nb == 0 || nb > range.length) {
        DONE_CHARS(a);
        DONE_CHARS(b);
        return none;
    }
    NSUInteger first = range.location, last = NSMaxRange(range) - nb;
    BOOL back = (mask & NSBackwardsSearch) != 0, ci = (mask & FOLDING) != 0;
    NSRange found = none;
    for (NSUInteger k = 0; k <= last - first; k++) {
        NSUInteger i = back ? last - k : first + k;
        NSUInteger j = 0;
        while (j < nb && (ci ? fold_with(a[i + j], mask) == fold_with(b[j], mask) : a[i + j] == b[j]))
            j++;
        if (j == nb) {
            found = NSMakeRange(i, nb);
            break;
        }
        if (mask & NSAnchoredSearch)
            break;
    }
    DONE_CHARS(a);
    DONE_CHARS(b);
    return found;
}
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)mask
{
    return [self rangeOfString:s options:mask range:NSMakeRange(0, [self length])];
}
- (NSRange)rangeOfString:(NSString *)s { return [self rangeOfString:s options:0]; }
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set
{
    NSUInteger n = [self length];
    for (NSUInteger i = 0; i < n; i++)
        if ([set characterIsMember:[self characterAtIndex:i]])
            return NSMakeRange(i, 1);
    return NSMakeRange(NSNotFound, 0);
}
- (BOOL)hasPrefix:(NSString *)s
{
    return [s length] && [self rangeOfString:s options:NSAnchoredSearch].location == 0;
}
- (BOOL)hasSuffix:(NSString *)s
{
    return [s length] && [s length] <= [self length]
        && [self rangeOfString:s options:NSAnchoredSearch | NSBackwardsSearch].location == [self length] - [s length];
}
- (BOOL)containsString:(NSString *)s { return [self rangeOfString:s].location != NSNotFound; }
/* freemac 1.225: the user's locale changes no letter here */
- (BOOL)localizedCaseInsensitiveContainsString:(NSString *)s
{
    return [self rangeOfString:s options:NSCaseInsensitiveSearch].location != NSNotFound;
}
- (NSRange)localizedStandardRangeOfString:(NSString *)s
{
    return [self rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
}
- (BOOL)localizedStandardContainsString:(NSString *)s
{
    return [self localizedStandardRangeOfString:s].location != NSNotFound;
}

/* pieces */
- (NSString *)substringWithRange:(NSRange)r
{
    if (NSMaxRange(r) > [self length])
        FRaise(NSRangeException, @"-[NSString substringWithRange:]: range {%lu, %lu} out of bounds; string length %lu",
               (unsigned long)r.location, (unsigned long)r.length, (unsigned long)[self length]);
    unichar *buf = malloc((r.length + 1) * sizeof(unichar));
    [self getCharacters:buf range:r];
    NSString *s = FStringFromChars(buf, r.length);
    free(buf);
    return s;
}
- (NSString *)substringFromIndex:(NSUInteger)i { return [self substringWithRange:NSMakeRange(i, [self length] - i)]; }
- (NSString *)substringToIndex:(NSUInteger)i { return [self substringWithRange:NSMakeRange(0, i)]; }
- (NSString *)stringByAppendingString:(NSString *)s
{
    NSMutableString *m = [NSMutableString stringWithString:self];
    [m appendString:s];
    return [NSString stringWithString:m];
}
- (NSString *)stringByAppendingFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    NSString *s = FFormat(format, ap);
    va_end(ap);
    return [self stringByAppendingString:s];
}
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement
{
    NSMutableString *m = [NSMutableString stringWithString:self];
    [m replaceOccurrencesOfString:target withString:replacement options:0 range:NSMakeRange(0, [m length])];
    return [NSString stringWithString:m];
}
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set
{
    NSUInteger n = [self length], a = 0, b = n;
    while (a < n && [set characterIsMember:[self characterAtIndex:a]])
        a++;
    while (b > a && [set characterIsMember:[self characterAtIndex:b - 1]])
        b--;
    return [self substringWithRange:NSMakeRange(a, b - a)];
}
- (NSString *)stringByPaddingToLength:(NSUInteger)len withString:(NSString *)pad startingAtIndex:(NSUInteger)idx
{
    NSUInteger n = [self length];
    if (len <= n)
        return [self substringToIndex:len];
    NSMutableString *m = [NSMutableString stringWithString:self];
    NSUInteger pn = [pad length];
    for (NSUInteger i = 0; i < len - n; i++) {
        unichar c = [pad characterAtIndex:(idx + i) % pn];
        [m appendString:FStringFromChars(&c, 1)];
    }
    return m;
}
- (NSArray *)componentsSeparatedByString:(NSString *)sep
{
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger n = [self length], start = 0;
    while (start <= n) {
        NSRange r = start < n ? [self rangeOfString:sep options:0 range:NSMakeRange(start, n - start)]
                              : NSMakeRange(NSNotFound, 0);
        if (r.location == NSNotFound) {
            [parts addObject:[self substringFromIndex:start]];
            break;
        }
        [parts addObject:[self substringWithRange:NSMakeRange(start, r.location - start)]];
        start = NSMaxRange(r);
        if (start == n) {
            [parts addObject:@""];
            break;
        }
    }
    return parts;
}
- (NSArray *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set
{
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger n = [self length], start = 0;
    for (NSUInteger i = 0; i <= n; i++)
        if (i == n || [set characterIsMember:[self characterAtIndex:i]]) {
            [parts addObject:[self substringWithRange:NSMakeRange(start, i - start)]];
            start = i + 1;
        }
    return parts;
}
- (NSString *)mapChars:(unichar (*)(unichar, BOOL))f
{
    WITH_CHARS(self, c, n);
    unichar *buf = malloc((n + 1) * sizeof(unichar));
    BOOL wordStart = YES;
    for (NSUInteger i = 0; i < n; i++) {
        buf[i] = f(c[i], wordStart);
        wordStart = !((c[i] >= 'a' && c[i] <= 'z') || (c[i] >= 'A' && c[i] <= 'Z') || (c[i] >= '0' && c[i] <= '9')
                      || c[i] >= 0x80 || c[i] == '\'');
    }
    NSString *s = FStringFromChars(buf, n);
    free(buf);
    DONE_CHARS(c);
    return s;
}
static unichar to_upper(unichar c, BOOL w) { return (c >= 'a' && c <= 'z') || (c >= 0xe0 && c <= 0xfe && c != 0xf7) ? c - 32 : c; }
static unichar to_lower(unichar c, BOOL w) { return (c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0xde && c != 0xd7) ? c + 32 : c; }
static unichar to_cap(unichar c, BOOL w) { return w ? to_upper(c, w) : to_lower(c, w); }
/* With ICU, Unicode's full mappings (NSStringText.m, freemac 1.225); this
 * table, Latin-1's letters, without it. */
NSString *FStringCaseMapped(NSString *s, int kind);
- (NSString *)uppercaseString { return FStringCaseMapped(self, 0) ?: [self mapChars:to_upper]; }
- (NSString *)lowercaseString { return FStringCaseMapped(self, 1) ?: [self mapChars:to_lower]; }
- (NSString *)capitalizedString { return FStringCaseMapped(self, 2) ?: [self mapChars:to_cap]; }
/* freemac 1.224: the user's locale changes no letter here */
- (NSString *)localizedUppercaseString { return [self uppercaseString]; }
- (NSString *)localizedLowercaseString { return [self lowercaseString]; }
- (NSString *)localizedCapitalizedString { return [self capitalizedString]; }
/* Ferry 0.66: in the given locale's rules, as ICU has them (Turkish's dotted
 * capital I, for one); nil is no locale's, the same as uppercaseString. */
NSString *FStringCaseMappedInLocale(NSString *s, int kind, const char *locale);
static const char *case_locale(id locale)
{
    NSString *ident = [locale respondsToSelector:@selector(localeIdentifier)] ? [locale localeIdentifier] : nil;
    return ident ? [ident UTF8String] : "";
}
- (NSString *)uppercaseStringWithLocale:(NSLocale *)locale
{
    return FStringCaseMappedInLocale(self, 0, case_locale(locale)) ?: [self mapChars:to_upper];
}
- (NSString *)lowercaseStringWithLocale:(NSLocale *)locale
{
    return FStringCaseMappedInLocale(self, 1, case_locale(locale)) ?: [self mapChars:to_lower];
}
- (NSString *)capitalizedStringWithLocale:(NSLocale *)locale
{
    return FStringCaseMappedInLocale(self, 2, case_locale(locale)) ?: [self mapChars:to_cap];
}

/* numbers */
- (int)intValue { return (int)[self longLongValue]; }
- (NSInteger)integerValue { return (NSInteger)[self longLongValue]; }
- (long long)longLongValue { return strtoll([self UTF8String], NULL, 10); }
- (double)doubleValue { return strtod([self UTF8String], NULL); }
- (float)floatValue { return (float)[self doubleValue]; }
- (BOOL)boolValue
{
    const char *s = [self UTF8String];
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '+' || *s == '-' || *s == '0')
        s++;
    return *s == 'Y' || *s == 'y' || *s == 'T' || *s == 't' || (*s >= '1' && *s <= '9');
}

- (void)enumerateLinesUsingBlock:(void (^)(NSString *, BOOL *))block
{
    BOOL stop = NO;
    NSUInteger n = [self length], start = 0;
    unichar *c = malloc((n ? n : 1) * sizeof(unichar));
    [self getCharacters:c range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i < n && !stop; i++) {
        unichar ch = c[i];
        if (ch != '\n' && ch != '\r' && ch != 0x85 && ch != 0x2028 && ch != 0x2029)
            continue;
        block(FStringFromChars(c + start, i - start), &stop);
        if (ch == '\r' && i + 1 < n && c[i + 1] == '\n')
            i++;
        start = i + 1;
    }
    if (!stop && start < n)
        block(FStringFromChars(c + start, n - start), &stop);
    free(c);
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically encoding:(NSStringEncoding)enc error:(NSError **)error
{
    return [[self dataUsingEncoding:enc] writeToFile:path options:atomically ? NSDataWritingAtomic : 0 error:error];
}
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically encoding:(NSStringEncoding)enc error:(NSError **)error
{
    return [self writeToFile:[url path] atomically:atomically encoding:enc error:error];
}

/* paths */
+ (NSString *)pathWithComponents:(NSArray *)components
{
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < [components count]; i++) {
        NSString *c = components[i];
        if (i && !(i == 1 && [components[0] isEqualToString:@"/"]))
            [m appendString:@"/"];
        [m appendString:c];
    }
    return m;
}
- (NSArray *)pathComponents
{
    NSMutableArray *a = [NSMutableArray array];
    if ([self hasPrefix:@"/"])
        [a addObject:@"/"];
    for (NSString *p in [self componentsSeparatedByString:@"/"])
        if ([p length])
            [a addObject:p];
    if ([self length] > 1 && [self hasSuffix:@"/"])
        [a addObject:@"/"];
    return a;
}
- (NSString *)trimmedPath
{
    NSString *s = self;
    while ([s length] > 1 && [s hasSuffix:@"/"])
        s = [s substringToIndex:[s length] - 1];
    return s;
}
- (NSString *)lastPathComponent
{
    NSString *s = [self trimmedPath];
    NSRange r = [s rangeOfString:@"/" options:NSBackwardsSearch];
    if (r.location == NSNotFound || [s length] == 1)
        return s;
    return [s substringFromIndex:r.location + 1];
}
- (NSString *)pathExtension
{
    NSString *last = [self lastPathComponent];
    NSRange r = [last rangeOfString:@"." options:NSBackwardsSearch];
    if (r.location == NSNotFound || r.location == 0)
        return @"";
    return [last substringFromIndex:r.location + 1];
}
- (NSString *)stringByDeletingLastPathComponent
{
    NSString *s = [self trimmedPath];
    NSRange r = [s rangeOfString:@"/" options:NSBackwardsSearch];
    if (r.location == NSNotFound)
        return @"";
    if (r.location == 0)
        return [s length] > 1 ? @"/" : @"/";
    return [s substringToIndex:r.location];
}
- (NSString *)stringByDeletingPathExtension
{
    NSString *s = [self trimmedPath];
    NSString *ext = [s pathExtension];
    if (![ext length])
        return s;
    return [s substringToIndex:[s length] - [ext length] - 1];
}
- (NSString *)stringByAppendingPathComponent:(NSString *)c
{
    if (![self length])
        return c;
    if ([self hasSuffix:@"/"])
        return [self stringByAppendingString:c];
    return [NSString stringWithFormat:@"%@/%@", self, c];
}
- (NSString *)stringByAppendingPathExtension:(NSString *)ext
{
    return [NSString stringWithFormat:@"%@.%@", [self trimmedPath], ext];
}
- (NSString *)stringByExpandingTildeInPath
{
    if ([self isEqualToString:@"~"])
        return FHome();
    if ([self hasPrefix:@"~/"])
        return [FHome() stringByAppendingString:[self substringFromIndex:1]];
    return self;
}
- (NSString *)stringByAbbreviatingWithTildeInPath
{
    NSString *home = FHome();
    if ([self isEqualToString:home])
        return @"~";
    if ([self hasPrefix:[home stringByAppendingString:@"/"]])
        return [@"~" stringByAppendingString:[self substringFromIndex:[home length]]];
    return self;
}
- (NSString *)stringByStandardizingPath
{
    NSString *s = [self stringByExpandingTildeInPath];
    NSMutableArray *out = [NSMutableArray array];
    BOOL abs = [s hasPrefix:@"/"];
    for (NSString *p in [s componentsSeparatedByString:@"/"]) {
        if (![p length] || [p isEqualToString:@"."])
            continue;
        if ([p isEqualToString:@".."] && [out count] && ![[out lastObject] isEqualToString:@".."]) {
            [out removeLastObject];
            continue;
        }
        if ([p isEqualToString:@".."] && abs)
            continue;
        [out addObject:p];
    }
    NSString *joined = [out componentsJoinedByString:@"/"];
    return abs ? [@"/" stringByAppendingString:joined] : ([joined length] ? joined : @".");
}
- (BOOL)isAbsolutePath { return [self hasPrefix:@"/"] || [self hasPrefix:@"~"]; }
/* The path with its symbolic links followed (freemac 1.265): an absolute path
 * that exists comes back as the file system has it; any other path is only
 * standardized, as Apple's documentation describes. */
- (NSString *)stringByResolvingSymlinksInPath
{
    NSString *s = [self stringByExpandingTildeInPath];
    if (![s hasPrefix:@"/"])
        return [s stringByStandardizingPath];
    char real[PATH_MAX];
    if (realpath([s fileSystemRepresentation], real))
        return [NSString stringWithUTF8String:real];
    return [s stringByStandardizingPath];
}
@end

/* ---- the concrete immutable string ---------------------------------------------------- */

@implementation NSConcreteString
- (instancetype)initWithCharacters:(const unichar *)chars length:(NSUInteger)length
{
    _chars = malloc((length + 1) * sizeof(unichar));
    if (length)
        memcpy(_chars, chars, length * sizeof(unichar));
    _len = length;
    return self;
}
- (void)dealloc
{
    free(_chars);
    free(_utf8);
    [super dealloc];
}
- (NSUInteger)length { return _len; }
- (unichar)characterAtIndex:(NSUInteger)i
{
    if (i >= _len)
        FRaise(NSRangeException, @"-[__NSCFString characterAtIndex:]: Range or index out of bounds");
    return _chars[i];
}
- (void)getCharacters:(unichar *)buf range:(NSRange)r
{
    if (NSMaxRange(r) > _len)
        FRaise(NSRangeException, @"-[__NSCFString getCharacters:range:]: Range or index out of bounds");
    memcpy(buf, _chars + r.location, r.length * sizeof(unichar));
}
- (const char *)UTF8String
{
    if (!_utf8)
        _utf8 = FEncodeUTF8(_chars, _len, NULL);
    return _utf8;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

/* ---- the concrete mutable string -------------------------------------------------------- */

@implementation NSMutableString
+ (instancetype)stringWithCapacity:(NSUInteger)capacity { return [[[self alloc] initWithCapacity:capacity] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return [self init]; }
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)s { [self doesNotRecognizeSelector:_cmd]; }
- (void)appendString:(NSString *)s { [self replaceCharactersInRange:NSMakeRange([self length], 0) withString:s]; }
- (void)appendFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    [self appendString:FFormat(format, ap)];
    va_end(ap);
}
- (void)setString:(NSString *)s { [self replaceCharactersInRange:NSMakeRange(0, [self length]) withString:s]; }
- (void)insertString:(NSString *)s atIndex:(NSUInteger)i { [self replaceCharactersInRange:NSMakeRange(i, 0) withString:s]; }
- (void)deleteCharactersInRange:(NSRange)r { [self replaceCharactersInRange:r withString:@""]; }
- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString *)replacement
                                 options:(NSStringCompareOptions)options range:(NSRange)range
{
    if (options & NSRegularExpressionSearch) /* the replacement is a template */
        return FRegexReplace(self, target, replacement, options, range);
    NSUInteger count = 0, pos = range.location, end = NSMaxRange(range);
    while (pos < end) {
        NSRange r = [self rangeOfString:target options:options & ~NSBackwardsSearch range:NSMakeRange(pos, end - pos)];
        if (r.location == NSNotFound)
            break;
        [self replaceCharactersInRange:r withString:replacement];
        pos = r.location + [replacement length];
        end = end - r.length + [replacement length];
        count++;
    }
    return count;
}
- (id)copyWithZone:(NSZone *)zone { return [[NSString allocWithZone:zone] initWithString:self]; }
@end

@implementation NSConcreteMutableString
- (instancetype)initWithCharacters:(const unichar *)chars length:(NSUInteger)length
{
    _cap = length < 16 ? 16 : length;
    _chars = malloc((_cap + 1) * sizeof(unichar));
    if (length)
        memcpy(_chars, chars, length * sizeof(unichar));
    _len = length;
    return self;
}
- (void)dealloc
{
    free(_chars);
    free(_utf8);
    [super dealloc];
}
- (NSUInteger)length { return _len; }
- (unichar)characterAtIndex:(NSUInteger)i
{
    if (i >= _len)
        FRaise(NSRangeException, @"-[__NSCFString characterAtIndex:]: Range or index out of bounds");
    return _chars[i];
}
- (void)getCharacters:(unichar *)buf range:(NSRange)r
{
    if (NSMaxRange(r) > _len)
        FRaise(NSRangeException, @"-[__NSCFString getCharacters:range:]: Range or index out of bounds");
    memcpy(buf, _chars + r.location, r.length * sizeof(unichar));
}
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s
{
    if (NSMaxRange(r) > _len)
        FRaise(NSRangeException, @"-[__NSCFString replaceCharactersInRange:withString:]: Range or index out of bounds");
    WITH_CHARS(s, c, n);
    NSUInteger newLen = _len - r.length + n;
    if (newLen > _cap) {
        _cap = newLen * 2;
        _chars = realloc(_chars, (_cap + 1) * sizeof(unichar));
    }
    memmove(_chars + r.location + n, _chars + NSMaxRange(r), (_len - NSMaxRange(r)) * sizeof(unichar));
    memcpy(_chars + r.location, c, n * sizeof(unichar));
    _len = newLen;
    DONE_CHARS(c);
    free(_utf8);
    _utf8 = NULL;
}
- (const char *)UTF8String
{
    /* the result stays valid until the string changes or is freed */
    free(_utf8);
    _utf8 = FEncodeUTF8(_chars, _len, NULL);
    return _utf8;
}
@end

/* ---- string literals ------------------------------------------------------------------------ */

#define CONSTANT_UTF16 0x7d0

@implementation __NSCFConstantString
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }
- (BOOL)_isDeallocating { return NO; }
- (void)dealloc { if (0) [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)length { return _length; }
- (unichar)characterAtIndex:(NSUInteger)i
{
    if (i >= (NSUInteger)_length)
        FRaise(NSRangeException, @"-[__NSCFConstantString characterAtIndex:]: Range or index out of bounds");
    if (_flags == CONSTANT_UTF16)
        return ((const unichar *)_ptr)[i];
    return (unsigned char)_ptr[i];
}
- (void)getCharacters:(unichar *)buf range:(NSRange)r
{
    if (NSMaxRange(r) > (NSUInteger)_length)
        FRaise(NSRangeException, @"-[__NSCFConstantString getCharacters:range:]: Range or index out of bounds");
    for (NSUInteger i = 0; i < r.length; i++)
        buf[i] = _flags == CONSTANT_UTF16 ? ((const unichar *)_ptr)[r.location + i]
                                          : (unsigned char)_ptr[r.location + i];
}
- (const char *)UTF8String
{
    if (_flags != CONSTANT_UTF16)
        return _ptr;
    return [super UTF8String];
}
@end

/* ---- NSCharacterSet ----------------------------------------------------------------------- */

typedef BOOL (*char_test)(unichar);
static BOOL is_space(unichar c) { return c == ' ' || c == '\t' || c == 0xa0 || c == 0x2028 || c == 0x3000; }
static BOOL is_newline(unichar c) { return c == '\n' || c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029; }
static BOOL is_space_nl(unichar c) { return is_space(c) || is_newline(c) || c == 0x0b || c == 0x0c; }
static BOOL is_digit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL is_letter(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= 0xc0 && c != 0xd7 && c != 0xf7 && c < 0x2000); }
static BOOL is_alnum(unichar c) { return is_letter(c) || is_digit(c); }
static BOOL is_punct(unichar c) { return c < 0x80 && c > ' ' && c != 0x7f && !is_alnum(c) && !strchr("$+<=>^`|~", c); }

@interface FCharacterSet : NSCharacterSet {
@public
    char_test _test;
    NSString *_chars;
    BOOL _inverted;
}
@end

@implementation NSCharacterSet
+ (NSCharacterSet *)setWithTest:(char_test)t
{
    FCharacterSet *s = [[FCharacterSet alloc] init];
    s->_test = t;
    return [s autorelease];
}
+ (NSCharacterSet *)whitespaceCharacterSet { return [self setWithTest:is_space]; }
+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet { return [self setWithTest:is_space_nl]; }
+ (NSCharacterSet *)newlineCharacterSet { return [self setWithTest:is_newline]; }
+ (NSCharacterSet *)decimalDigitCharacterSet { return [self setWithTest:is_digit]; }
+ (NSCharacterSet *)letterCharacterSet { return [self setWithTest:is_letter]; }
+ (NSCharacterSet *)alphanumericCharacterSet { return [self setWithTest:is_alnum]; }
+ (NSCharacterSet *)punctuationCharacterSet { return [self setWithTest:is_punct]; }
+ (NSCharacterSet *)characterSetWithCharactersInString:(NSString *)s
{
    FCharacterSet *set = [[FCharacterSet alloc] init];
    set->_chars = [s copy];
    return [set autorelease];
}
- (BOOL)characterIsMember:(unichar)c { return NO; }
- (NSCharacterSet *)invertedSet
{
    FCharacterSet *set = [[FCharacterSet alloc] init];
    FCharacterSet *me = (FCharacterSet *)self;
    set->_test = me->_test;
    set->_chars = [me->_chars copy];
    set->_inverted = !me->_inverted;
    return [set autorelease];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

@implementation FCharacterSet
- (BOOL)characterIsMember:(unichar)c
{
    BOOL in;
    if (_test)
        in = _test(c);
    else {
        in = NO;
        NSUInteger n = [_chars length];
        for (NSUInteger i = 0; i < n && !in; i++)
            in = [_chars characterAtIndex:i] == c;
    }
    return in != _inverted;
}
- (void)dealloc
{
    [_chars release];
    [super dealloc];
}
@end

/* ---- formatting ------------------------------------------------------------------------------ */

struct buf { char *p; size_t n, cap; };

static void put(struct buf *b, const char *s, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2;
        b->p = realloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
    b->p[b->n] = 0;
}

static void put_padded(struct buf *b, const char *s, int width, int left)
{
    size_t n = strlen(s);
    if (!left)
        for (int i = (int)n; i < width; i++)
            put(b, " ", 1);
    put(b, s, n);
    if (left)
        for (int i = (int)n; i < width; i++)
            put(b, " ", 1);
}

/* One conversion of a format: %[n$][flags][width][.precision][length]conversion. */
struct spec {
    int pos;           /* 1-based argument number, or 0 for "the next one" */
    char flags[8];
    int left;
    int width, width_star, prec, prec_star;
    int lng;           /* 0 int, 1 long, 2 long long, 3 short, 4 char, 5 long double, 6 size */
    char conv;
};

static const char *parse_spec(const char *f, struct spec *sp)
{
    memset(sp, 0, sizeof *sp);
    sp->prec = -1;
    const char *start = f;
    int n = 0;
    while (*f >= '0' && *f <= '9')
        n = n * 10 + (*f++ - '0');
    if (*f == '$' && n > 0) {
        sp->pos = n;
        f++;
    } else {
        f = start;
    }
    size_t fl = 0;
    while (*f && strchr("-+ #0'", *f)) {
        if (*f == '-')
            sp->left = 1;
        if (*f != '\'' && fl + 1 < sizeof sp->flags)
            sp->flags[fl++] = *f;
        f++;
    }
    if (*f == '*') {
        sp->width_star = 1;
        f++;
        while (*f >= '0' && *f <= '9') /* "*2$" form: treated as the next argument */
            f++;
        if (*f == '$')
            f++;
    } else {
        while (*f >= '0' && *f <= '9')
            sp->width = sp->width * 10 + (*f++ - '0');
    }
    if (*f == '.') {
        f++;
        sp->prec = 0;
        if (*f == '*') {
            sp->prec_star = 1;
            f++;
            while (*f >= '0' && *f <= '9')
                f++;
            if (*f == '$')
                f++;
        } else {
            while (*f >= '0' && *f <= '9')
                sp->prec = sp->prec * 10 + (*f++ - '0');
        }
    }
    for (;;) {
        if (*f == 'l') { sp->lng = sp->lng == 1 ? 2 : 1; f++; }
        else if (*f == 'q' || *f == 'j') { sp->lng = 2; f++; }
        else if (*f == 'z' || *f == 't') { sp->lng = 6; f++; }
        else if (*f == 'h') { sp->lng = sp->lng == 3 ? 4 : 3; f++; }
        else if (*f == 'L') { sp->lng = 5; f++; }
        else break;
    }
    sp->conv = *f ? *f++ : 0;
    return f;
}

/* The C type class an argument is passed as. */
enum { A_INT = 1, A_LONG, A_DOUBLE, A_LDOUBLE, A_PTR };

static int arg_class(const struct spec *sp)
{
    switch (sp->conv) {
    case 'd': case 'i': case 'u': case 'o': case 'x': case 'X':
        return sp->lng == 1 || sp->lng == 2 || sp->lng == 6 ? A_LONG : A_INT;
    case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A':
        return sp->lng == 5 ? A_LDOUBLE : A_DOUBLE;
    case 'c': case 'C':
        return A_INT;
    case '@': case 's': case 'S': case 'p': case 'n':
        return A_PTR;
    }
    return 0;
}

union farg {
    long long i;
    double d;
    long double ld;
    void *p;
};

struct fargs {
    va_list ap;
    union farg *vals; /* positional formats read every argument first */
    int count, next;
};

static union farg take(struct fargs *a, int cls, int pos)
{
    union farg v = {0};
    if (a->vals) {
        int i = pos ? pos - 1 : a->next++;
        if (i >= 0 && i < a->count)
            v = a->vals[i];
        return v;
    }
    switch (cls) {
    case A_INT: v.i = va_arg(a->ap, int); break;
    case A_LONG: v.i = va_arg(a->ap, long long); break;
    case A_DOUBLE: v.d = va_arg(a->ap, double); break;
    case A_LDOUBLE: v.ld = va_arg(a->ap, long double); break;
    case A_PTR: v.p = va_arg(a->ap, void *); break;
    }
    return v;
}

/* For "%2$@ %1$@": find each argument's type, then read them in order. */
static void read_positional(struct fargs *a, const char *f)
{
    int classes[64] = {0}, count = 0, seq = 0;
    while ((f = strchr(f, '%'))) {
        f++;
        if (*f == '%') {
            f++;
            continue;
        }
        struct spec sp;
        f = parse_spec(f, &sp);
        if (sp.width_star && seq < 64)
            classes[seq++] = A_INT;
        if (sp.prec_star && seq < 64)
            classes[seq++] = A_INT;
        int i = sp.pos ? sp.pos - 1 : seq++;
        if (i < 64 && arg_class(&sp))
            classes[i] = arg_class(&sp);
        if (i + 1 > count)
            count = i + 1;
        if (seq > count)
            count = seq;
    }
    if (count > 64)
        count = 64;
    a->vals = calloc(count ? count : 1, sizeof *a->vals);
    a->count = count;
    for (int i = 0; i < count; i++) {
        switch (classes[i]) {
        case A_LONG: a->vals[i].i = va_arg(a->ap, long long); break;
        case A_DOUBLE: a->vals[i].d = va_arg(a->ap, double); break;
        case A_LDOUBLE: a->vals[i].ld = va_arg(a->ap, long double); break;
        case A_PTR: a->vals[i].p = va_arg(a->ap, void *); break;
        default: a->vals[i].i = va_arg(a->ap, int); break;
        }
    }
}

NSString *FFormat(NSString *format, va_list ap)
{
    const char *f = [format UTF8String];
    struct buf b = {NULL, 0, 0};
    put(&b, "", 0);
    char spec[64], tmp[512];
    struct fargs a = {.vals = NULL};
    va_copy(a.ap, ap);
    for (const char *q = f; (q = strchr(q, '%'));) {
        q++;
        while (*q >= '0' && *q <= '9')
            q++;
        if (*q == '$') {
            read_positional(&a, f);
            break;
        }
    }
    while (*f) {
        const char *pct = strchr(f, '%');
        if (!pct) {
            put(&b, f, strlen(f));
            break;
        }
        put(&b, f, pct - f);
        f = pct + 1;
        if (*f == '%') {
            put(&b, "%", 1);
            f++;
            continue;
        }
        struct spec sp;
        f = parse_spec(f, &sp);
        int width = sp.width, left = sp.left;
        if (sp.width_star) {
            width = (int)take(&a, A_INT, 0).i;
            if (width < 0) {
                left = 1;
                width = -width;
            }
        }
        int prec = sp.prec;
        if (sp.prec_star)
            prec = (int)take(&a, A_INT, 0).i;
        /* the C format for snprintf, without the length and conversion */
        size_t sn = (size_t)snprintf(spec, sizeof spec, "%%%s%s", sp.flags, left && !strchr(sp.flags, '-') ? "-" : "");
        if (width)
            sn += snprintf(spec + sn, sizeof spec - sn, "%d", width);
        if (prec >= 0)
            sn += snprintf(spec + sn, sizeof spec - sn, ".%d", prec);
        char conv = sp.conv;
        switch (conv) {
        case '@': {
            id obj = (id)take(&a, A_PTR, sp.pos).p;
            const char *s = obj ? [[obj description] UTF8String] : "(null)";
            put_padded(&b, s ? s : "(null)", width, left);
            break;
        }
        case 'd': case 'i': case 'u': case 'o': case 'x': case 'X': {
            long long v = take(&a, arg_class(&sp), sp.pos).i;
            BOOL sign = conv == 'd' || conv == 'i';
            if (sp.lng == 0)
                v = sign ? (long long)(int)v : (long long)(unsigned int)v;
            else if (sp.lng == 3)
                v = sign ? (long long)(short)v : (long long)(unsigned short)v;
            else if (sp.lng == 4)
                v = sign ? (long long)(signed char)v : (long long)(unsigned char)v;
            snprintf(spec + sn, sizeof spec - sn, "ll%c", conv);
            snprintf(tmp, sizeof tmp, spec, v);
            put(&b, tmp, strlen(tmp));
            break;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A': {
            if (sp.lng == 5) {
                snprintf(spec + sn, sizeof spec - sn, "L%c", conv);
                snprintf(tmp, sizeof tmp, spec, take(&a, A_LDOUBLE, sp.pos).ld);
            } else {
                snprintf(spec + sn, sizeof spec - sn, "%c", conv);
                snprintf(tmp, sizeof tmp, spec, take(&a, A_DOUBLE, sp.pos).d);
            }
            put(&b, tmp, strlen(tmp));
            break;
        }
        case 'c': case 'C': {
            unichar c = (unichar)take(&a, A_INT, sp.pos).i;
            if (conv == 'c')
                c = (unsigned char)c;
            char *u = FEncodeUTF8(&c, 1, NULL);
            put_padded(&b, u, width, left);
            free(u);
            break;
        }
        case 's': {
            const char *s = take(&a, A_PTR, sp.pos).p;
            snprintf(spec + sn, sizeof spec - sn, "s");
            char *out = NULL;
            if (asprintf(&out, spec, s ? s : "(null)") >= 0) {
                put(&b, out, strlen(out));
                free(out);
            }
            break;
        }
        case 'S': {
            const unichar *s = take(&a, A_PTR, sp.pos).p;
            NSUInteger n = 0;
            while (s && s[n])
                n++;
            char *u = s ? FEncodeUTF8(s, n, NULL) : strdup("(null)");
            put_padded(&b, u, width, left);
            free(u);
            break;
        }
        case 'p': /* a Mac prints a null pointer as 0x0 */
            snprintf(tmp, sizeof tmp, "0x%lx", (unsigned long)take(&a, A_PTR, sp.pos).p);
            put_padded(&b, tmp, width, left);
            break;
        case 'n':
            (void)take(&a, A_PTR, sp.pos);
            break;
        default:
            put(&b, pct, f - pct);
        }
    }
    va_end(a.ap);
    free(a.vals);
    NSString *s = FStringFromUTF8(b.p, b.n);
    free(b.p);
    return s;
}

NSString *FFormatC(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    char *out = NULL;
    int n = vasprintf(&out, format, ap);
    va_end(ap);
    NSString *s = FStringFromUTF8(out ? out : "", n > 0 ? n : 0);
    free(out);
    return s;
}
