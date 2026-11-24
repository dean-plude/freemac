/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSScanner, which reads numbers and words out of a
 * string from a moving location. Before each scan it passes over the
 * characters to be skipped (white space and line ends unless told
 * otherwise); a scan that finds nothing leaves the location where it was.
 * Written from Apple's public documentation of the class; no Apple code
 * was used. */
#import "FInternal.h"

@implementation NSScanner {
    NSString *_string;
    unichar *_c;
    NSUInteger _n, _loc;
    NSCharacterSet *_skip;
    BOOL _caseSensitive;
    id _locale;
}

+ (instancetype)scannerWithString:(NSString *)string { return [[[self alloc] initWithString:string] autorelease]; }
+ (id)localizedScannerWithString:(NSString *)string
{
    NSScanner *s = [self scannerWithString:string];
    [s setLocale:[NSLocale currentLocale]];
    return s;
}
- (instancetype)initWithString:(NSString *)string
{
    if (!(self = [super init]))
        return nil;
    _string = [string copy] ?: @"";
    _n = [_string length];
    _c = malloc((_n + 1) * sizeof(unichar));
    [_string getCharacters:_c range:NSMakeRange(0, _n)];
    _skip = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
    return self;
}
- (instancetype)init { return [self initWithString:@""]; }
- (void)dealloc
{
    free(_c);
    [_string release];
    [_skip release];
    [_locale release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSScanner *s = [[NSScanner allocWithZone:zone] initWithString:_string];
    s->_loc = _loc;
    [s setCharactersToBeSkipped:_skip];
    s->_caseSensitive = _caseSensitive;
    [s setLocale:_locale];
    return s;
}
- (NSString *)string { return _string; }
- (NSUInteger)scanLocation { return _loc; }
- (void)setScanLocation:(NSUInteger)loc
{
    if (loc > _n)
        FRaise(NSRangeException, @"*** -[NSConcreteScanner setScanLocation:]: Range or index out of bounds");
    _loc = loc;
}
- (NSCharacterSet *)charactersToBeSkipped { return _skip; }
- (void)setCharactersToBeSkipped:(NSCharacterSet *)set
{
    set = [set copy];
    [_skip release];
    _skip = set;
}
- (BOOL)caseSensitive { return _caseSensitive; }
- (void)setCaseSensitive:(BOOL)flag { _caseSensitive = flag; }
- (id)locale { return _locale; }
- (void)setLocale:(id)locale
{
    [locale retain];
    [_locale release];
    _locale = locale;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSConcreteScanner: %p>", self];
}

/* Where scanning starts: after the characters to be skipped. */
static NSUInteger skipped(NSScanner *s)
{
    NSUInteger i = s->_loc;
    if (s->_skip)
        while (i < s->_n && [s->_skip characterIsMember:s->_c[i]])
            i++;
    return i;
}
- (BOOL)isAtEnd { return skipped(self) >= _n; }

static int digit_value(unichar c, int base)
{
    int v = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : 99;
    return v < base ? v : -1;
}

/* A decimal integer, held to [min, max] if it is too big (the location
 * still goes past all its digits). */
static BOOL scan_signed(NSScanner *s, long long min, long long max, long long *out)
{
    NSUInteger i = skipped(s);
    BOOL neg = NO;
    if (i < s->_n && (s->_c[i] == '-' || s->_c[i] == '+'))
        neg = s->_c[i++] == '-';
    if (i >= s->_n || digit_value(s->_c[i], 10) < 0)
        return NO;
    unsigned long long v = 0, limit = neg ? (unsigned long long)(-(min + 1)) + 1 : (unsigned long long)max;
    BOOL over = NO;
    int d;
    for (; i < s->_n && (d = digit_value(s->_c[i], 10)) >= 0; i++) {
        if (!over && (v > (limit - d) / 10))
            over = YES;
        if (!over)
            v = v * 10 + d;
    }
    s->_loc = i;
    if (out)
        *out = over ? (neg ? min : max) : neg ? (long long)(0 - v) : (long long)v;
    return YES;
}
- (BOOL)scanInt:(int *)result
{
    long long v;
    if (!scan_signed(self, INT_MIN, INT_MAX, &v))
        return NO;
    if (result)
        *result = (int)v;
    return YES;
}
- (BOOL)scanInteger:(NSInteger *)result
{
    long long v;
    if (!scan_signed(self, LONG_MIN, LONG_MAX, &v))
        return NO;
    if (result)
        *result = (NSInteger)v;
    return YES;
}
- (BOOL)scanLongLong:(long long *)result { return scan_signed(self, LLONG_MIN, LLONG_MAX, result); }

static BOOL scan_unsigned(NSScanner *s, int base, unsigned long long max, unsigned long long *out)
{
    NSUInteger i = skipped(s);
    if (base == 10 && i < s->_n && s->_c[i] == '+')
        i++;
    if (base == 16 && i + 2 < s->_n && s->_c[i] == '0' && (s->_c[i + 1] == 'x' || s->_c[i + 1] == 'X') &&
        digit_value(s->_c[i + 2], 16) >= 0)
        i += 2;
    if (i >= s->_n || digit_value(s->_c[i], base) < 0)
        return NO;
    unsigned long long v = 0;
    BOOL over = NO;
    int d;
    for (; i < s->_n && (d = digit_value(s->_c[i], base)) >= 0; i++) {
        if (!over && v > (max - d) / base)
            over = YES;
        if (!over)
            v = v * base + d;
    }
    s->_loc = i;
    if (out)
        *out = over ? max : v;
    return YES;
}
- (BOOL)scanUnsignedLongLong:(unsigned long long *)result { return scan_unsigned(self, 10, ULLONG_MAX, result); }
- (BOOL)scanHexInt:(unsigned int *)result
{
    unsigned long long v;
    if (!scan_unsigned(self, 16, UINT_MAX, &v))
        return NO;
    if (result)
        *result = (unsigned)v;
    return YES;
}
- (BOOL)scanHexLongLong:(unsigned long long *)result { return scan_unsigned(self, 16, ULLONG_MAX, result); }

/* The decimal separator: the locale's, for a localized scanner. */
static unichar separator(NSScanner *s)
{
    if ([s->_locale isKindOfClass:[NSLocale class]]) {
        NSString *sep = [s->_locale objectForKey:NSLocaleDecimalSeparator];
        if ([sep length] == 1)
            return [sep characterAtIndex:0];
    }
    if ([s->_locale isKindOfClass:[NSDictionary class]]) {
        NSString *sep = [s->_locale objectForKey:@"NSDecimalSeparator"];
        if ([sep isKindOfClass:[NSString class]] && [sep length] == 1)
            return [sep characterAtIndex:0];
    }
    return '.';
}

/* A floating-point number, decimal (digits, a separator, an exponent) or
 * hexadecimal (0x1.8p3), read by the C library once its characters are
 * found. */
static BOOL scan_real(NSScanner *s, BOOL hex, double *out)
{
    NSUInteger i = skipped(s);
    char buf[512];
    int b = 0;
    if (i < s->_n && (s->_c[i] == '-' || s->_c[i] == '+'))
        buf[b++] = (char)s->_c[i++];
    int base = 10;
    unichar sep = hex ? '.' : separator(s);
    if (hex) {
        base = 16;
        if (i + 1 < s->_n && s->_c[i] == '0' && (s->_c[i + 1] == 'x' || s->_c[i + 1] == 'X'))
            i += 2;
        buf[b++] = '0';
        buf[b++] = 'x';
    }
    int digits = 0;
    for (; i < s->_n && digit_value(s->_c[i], base) >= 0; i++, digits++)
        if (b < 480)
            buf[b++] = (char)s->_c[i];
    if (i < s->_n && s->_c[i] == sep) {
        NSUInteger j = i + 1;
        int frac = 0;
        for (; j < s->_n && digit_value(s->_c[j], base) >= 0; j++, frac++)
            ;
        if (frac || digits) {
            if (b < 480)
                buf[b++] = '.';
            for (i++; i < j; i++)
                if (b < 480)
                    buf[b++] = (char)s->_c[i];
            digits += frac;
        }
    }
    if (!digits)
        return NO;
    unichar e1 = hex ? 'p' : 'e', e2 = hex ? 'P' : 'E';
    if (i < s->_n && (s->_c[i] == e1 || s->_c[i] == e2)) {
        NSUInteger j = i + 1;
        if (j < s->_n && (s->_c[j] == '-' || s->_c[j] == '+'))
            j++;
        if (j < s->_n && s->_c[j] >= '0' && s->_c[j] <= '9') {
            for (; i < j; i++)
                buf[b++] = (char)s->_c[i];
            for (; i < s->_n && s->_c[i] >= '0' && s->_c[i] <= '9'; i++)
                if (b < 500)
                    buf[b++] = (char)s->_c[i];
        }
    } else if (hex) {
        buf[b++] = 'p';
        buf[b++] = '0';
    }
    buf[b] = 0;
    s->_loc = i;
    if (out)
        *out = strtod(buf, NULL);
    return YES;
}
- (BOOL)scanDouble:(double *)result { return scan_real(self, NO, result); }
- (BOOL)scanHexDouble:(double *)result { return scan_real(self, YES, result); }
- (BOOL)scanFloat:(float *)result
{
    double d;
    if (!scan_real(self, NO, &d))
        return NO;
    if (result)
        *result = (float)d;
    return YES;
}
- (BOOL)scanHexFloat:(float *)result
{
    double d;
    if (!scan_real(self, YES, &d))
        return NO;
    if (result)
        *result = (float)d;
    return YES;
}

- (BOOL)scanString:(NSString *)string intoString:(NSString **)result
{
    NSUInteger i = skipped(self), len = [string length];
    if (!len || i + len > _n)
        return NO;
    NSRange r = [_string rangeOfString:string
                               options:NSAnchoredSearch | (_caseSensitive ? 0 : NSCaseInsensitiveSearch)
                                 range:NSMakeRange(i, _n - i)];
    if (r.location != i)
        return NO;
    _loc = NSMaxRange(r);
    if (result)
        *result = [_string substringWithRange:r];
    return YES;
}
- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result
{
    NSUInteger i = skipped(self), j = i;
    while (j < _n && [set characterIsMember:_c[j]])
        j++;
    if (j == i)
        return NO;
    _loc = j;
    if (result)
        *result = [_string substringWithRange:NSMakeRange(i, j - i)];
    return YES;
}
- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result
{
    NSUInteger i = skipped(self), j = i;
    while (j < _n && ![set characterIsMember:_c[j]])
        j++;
    if (j == i)
        return NO;
    _loc = j;
    if (result)
        *result = [_string substringWithRange:NSMakeRange(i, j - i)];
    return YES;
}
- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)result
{
    NSUInteger i = skipped(self);
    if (i >= _n)
        return NO;
    NSRange r = [string length] ? [_string rangeOfString:string
                                                 options:_caseSensitive ? 0 : NSCaseInsensitiveSearch
                                                   range:NSMakeRange(i, _n - i)]
                                : NSMakeRange(NSNotFound, 0);
    NSUInteger j = r.location == NSNotFound ? _n : r.location;
    if (j == i)
        return NO;
    _loc = j;
    if (result)
        *result = [_string substringWithRange:NSMakeRange(i, j - i)];
    return YES;
}
@end
