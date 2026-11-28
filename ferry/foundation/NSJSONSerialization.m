/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSJSONSerialization, written from Apple's public
 * documentation of the class and from the JSON standard (RFC 8259); no
 * Apple code was used.
 *
 * Reading takes UTF-8, UTF-16 or UTF-32 (either byte order, told apart by a
 * byte order mark or by where the zero bytes fall, as the standard
 * suggests) and gives NSDictionary, NSArray, NSString, NSNumber and NSNull,
 * mutable when asked. Whole numbers that fit are kept as integers, the rest
 * as doubles. A mistake is reported as an NSError in the Cocoa domain, code
 * 3840, with the place it was found. With JSON5Allowed, JSON5 is read as
 * its public specification (json5.org) describes: comments, unquoted and
 * single-quoted keys, single-quoted strings, more escapes, hexadecimal
 * numbers, Infinity and NaN, and numbers with a leading plus or a bare
 * decimal point; TopLevelDictionaryAssumed then reads a text without its
 * outer braces as a dictionary (freemac 1.270, Hex Fiend's byte themes are
 * JSON5). Writing takes the same classes and raises
 * NSInvalidArgumentException for anything else, as on a Mac; doubles are
 * written in the shortest form that reads back the same. Built without
 * ARC. */
#import "FInternal.h"

#define JSON_ERROR 3840
#define MAX_DEPTH 512

/* ---- reading -------------------------------------------------------------------- */

struct reader {
    const uint8_t *p, *start, *end;
    NSJSONReadingOptions opt;
    NSString *why;   /* the first mistake */
    size_t at;
    int depth;
    BOOL json5;
};

static id fail(struct reader *r, const uint8_t *at, NSString *why)
{
    if (!r->why) {
        r->why = why;
        r->at = (size_t)(at - r->start);
    }
    return nil;
}

static void skip_space(struct reader *r)
{
    for (;;) {
        while (r->p < r->end && (*r->p == ' ' || *r->p == '\t' || *r->p == '\n' || *r->p == '\r'))
            r->p++;
        if (!r->json5 || r->p >= r->end)
            return;
        size_t left = (size_t)(r->end - r->p);
        const uint8_t *q = r->p;
        if (*q == '\v' || *q == '\f') {
            r->p++;
        } else if (left >= 2 && q[0] == 0xc2 && q[1] == 0xa0) {
            r->p += 2;   /* no-break space */
        } else if (left >= 3 && ((q[0] == 0xe2 && q[1] == 0x80 && (q[2] == 0xa8 || q[2] == 0xa9)) ||
                                 (q[0] == 0xef && q[1] == 0xbb && q[2] == 0xbf))) {
            r->p += 3;   /* line and paragraph separators, a byte order mark */
        } else if (left >= 2 && q[0] == '/' && q[1] == '/') {
            while (r->p < r->end && *r->p != '\n' && *r->p != '\r')
                r->p++;
        } else if (left >= 2 && q[0] == '/' && q[1] == '*') {
            const uint8_t *e = r->p + 2;
            while (e + 1 < r->end && !(e[0] == '*' && e[1] == '/'))
                e++;
            if (e + 1 >= r->end)
                return;   /* unclosed: left for the caller to report */
            r->p = e + 2;
        } else {
            return;
        }
    }
}

static id read_value(struct reader *r);

static void put_utf8(NSMutableData *out, uint32_t c)
{
    uint8_t b[4];
    size_t n;
    if (c < 0x80) {
        b[0] = (uint8_t)c;
        n = 1;
    } else if (c < 0x800) {
        b[0] = (uint8_t)(0xc0 | c >> 6);
        b[1] = (uint8_t)(0x80 | (c & 0x3f));
        n = 2;
    } else if (c < 0x10000) {
        b[0] = (uint8_t)(0xe0 | c >> 12);
        b[1] = (uint8_t)(0x80 | (c >> 6 & 0x3f));
        b[2] = (uint8_t)(0x80 | (c & 0x3f));
        n = 3;
    } else {
        b[0] = (uint8_t)(0xf0 | c >> 18);
        b[1] = (uint8_t)(0x80 | (c >> 12 & 0x3f));
        b[2] = (uint8_t)(0x80 | (c >> 6 & 0x3f));
        b[3] = (uint8_t)(0x80 | (c & 0x3f));
        n = 4;
    }
    [out appendBytes:b length:n];
}

static int hex4(const uint8_t *p, const uint8_t *end, uint32_t *out)
{
    if (end - p < 4)
        return 0;
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        int c = p[i], d;
        if (c >= '0' && c <= '9')
            d = c - '0';
        else if (c >= 'a' && c <= 'f')
            d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            d = c - 'A' + 10;
        else
            return 0;
        v = v << 4 | (uint32_t)d;
    }
    *out = v;
    return 1;
}

/* r->p is just past the opening quote, which (in JSON5) may be ' */
static NSString *read_string(struct reader *r, BOOL mutable_)
{
    const uint8_t *open = r->p - 1;
    const uint8_t quote = *open;
    NSMutableData *buf = nil;
    const uint8_t *run = r->p;
    for (;;) {
        if (r->p >= r->end)
            return fail(r, open, @"Unterminated string");
        uint8_t c = *r->p;
        if (c == quote)
            break;
        if (c < 0x20 && !(r->json5 && c == '\t'))
            return fail(r, r->p, @"Unescaped control character");
        if (c != '\\') {
            r->p++;
            continue;
        }
        if (!buf)
            buf = [NSMutableData data];
        [buf appendBytes:run length:(NSUInteger)(r->p - run)];
        const uint8_t *esc = r->p++;
        if (r->p >= r->end)
            return fail(r, open, @"Unterminated string");
        switch (*r->p++) {
        case '"': put_utf8(buf, '"'); break;
        case '\\': put_utf8(buf, '\\'); break;
        case '/': put_utf8(buf, '/'); break;
        case 'b': put_utf8(buf, '\b'); break;
        case 'f': put_utf8(buf, '\f'); break;
        case 'n': put_utf8(buf, '\n'); break;
        case 'r': put_utf8(buf, '\r'); break;
        case 't': put_utf8(buf, '\t'); break;
        case '\'':
        case 'v': case '0': case 'x': case '\n': case '\r':
            if (!r->json5)
                return fail(r, esc, @"Invalid escape sequence");
            if (r->p[-1] == '\'') {
                put_utf8(buf, '\'');
            } else if (r->p[-1] == 'v') {
                put_utf8(buf, '\v');
            } else if (r->p[-1] == '0') {
                if (r->p < r->end && *r->p >= '0' && *r->p <= '9')
                    return fail(r, esc, @"Invalid escape sequence");
                put_utf8(buf, 0);
            } else if (r->p[-1] == 'x') {
                uint32_t hi, lo;
                const char *digits = "0123456789abcdef";
                if (r->end - r->p < 2 || !strchr(digits, tolower(r->p[0])) || !strchr(digits, tolower(r->p[1])) ||
                    !r->p[0] || !r->p[1])
                    return fail(r, esc, @"Invalid escape sequence");
                hi = (uint32_t)(strchr(digits, tolower(r->p[0])) - digits);
                lo = (uint32_t)(strchr(digits, tolower(r->p[1])) - digits);
                put_utf8(buf, hi * 16 + lo);
                r->p += 2;
            } else if (r->p[-1] == '\r' && r->p < r->end && *r->p == '\n') {
                r->p++;   /* a line continuation: the escaped line break is dropped */
            }
            break;
        case 'u': {
            uint32_t u;
            if (!hex4(r->p, r->end, &u))
                return fail(r, esc, @"Invalid escape sequence");
            r->p += 4;
            if (u >= 0xd800 && u < 0xdc00) {
                uint32_t lo;
                if (r->end - r->p < 6 || r->p[0] != '\\' || r->p[1] != 'u' || !hex4(r->p + 2, r->end, &lo) ||
                    lo < 0xdc00 || lo >= 0xe000)
                    return fail(r, esc, @"Missing low code point in surrogate pair");
                r->p += 6;
                u = 0x10000 + ((u - 0xd800) << 10) + (lo - 0xdc00);
            } else if (u >= 0xdc00 && u < 0xe000) {
                return fail(r, esc, @"Invalid unicode escape sequence");
            }
            put_utf8(buf, u);
            break;
        }
        default:
            if (!r->json5 || r->p[-1] < 0x20 || (r->p[-1] >= '1' && r->p[-1] <= '9'))
                return fail(r, esc, @"Invalid escape sequence");
            /* JSON5: any other character stands for itself */
            r->p--;
            run = r->p;
            continue;
        }
        run = r->p;
    }
    NSString *s;
    if (buf) {
        [buf appendBytes:run length:(NSUInteger)(r->p - run)];
        s = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    } else {
        s = [[NSString alloc] initWithBytes:run length:(NSUInteger)(r->p - run) encoding:NSUTF8StringEncoding];
    }
    if (!s)
        return fail(r, open, @"Unable to convert data to string");
    r->p++;
    if (mutable_) {
        NSMutableString *m = [s mutableCopy];
        [s release];
        return [m autorelease];
    }
    return [s autorelease];
}

static NSNumber *read_json5_number(struct reader *r);

static NSNumber *read_number(struct reader *r)
{
    if (r->json5)
        return read_json5_number(r);
    const uint8_t *s = r->p, *q = r->p;
    BOOL integral = YES;
    if (q < r->end && *q == '-')
        q++;
    if (q >= r->end || *q < '0' || *q > '9')
        return fail(r, s, @"Invalid value");
    if (*q == '0') {
        q++;
        if (q < r->end && *q >= '0' && *q <= '9')
            return fail(r, s, @"Leading zeros are not allowed");
    } else {
        while (q < r->end && *q >= '0' && *q <= '9')
            q++;
    }
    if (q < r->end && *q == '.') {
        integral = NO;
        q++;
        if (q >= r->end || *q < '0' || *q > '9')
            return fail(r, s, @"Invalid number: no digits after the decimal point");
        while (q < r->end && *q >= '0' && *q <= '9')
            q++;
    }
    if (q < r->end && (*q == 'e' || *q == 'E')) {
        integral = NO;
        q++;
        if (q < r->end && (*q == '+' || *q == '-'))
            q++;
        if (q >= r->end || *q < '0' || *q > '9')
            return fail(r, s, @"Invalid number: no digits in the exponent");
        while (q < r->end && *q >= '0' && *q <= '9')
            q++;
    }
    char text[512];
    size_t n = (size_t)(q - s);
    char *t = n < sizeof text ? text : malloc(n + 1);
    memcpy(t, s, n);
    t[n] = 0;
    r->p = q;
    NSNumber *num = nil;
    if (integral) {
        errno = 0;
        if (*t == '-') {
            long long v = strtoll(t, NULL, 10);
            if (!errno)
                num = [NSNumber numberWithLongLong:v];
        } else {
            unsigned long long v = strtoull(t, NULL, 10);
            if (!errno)
                num = v <= LLONG_MAX ? [NSNumber numberWithLongLong:(long long)v] : [NSNumber numberWithUnsignedLongLong:v];
        }
    }
    if (!num) {
        double d = strtod(t, NULL);
        if (isinf(d)) {
            if (t != text)
                free(t);
            return fail(r, s, @"Number out of range");
        }
        num = [NSNumber numberWithDouble:d];
    }
    if (t != text)
        free(t);
    return num;
}

/* JSON5's numbers: a sign of either kind, Infinity, NaN, hexadecimal, and
 * decimals that start or end with their point */
static NSNumber *read_json5_number(struct reader *r)
{
    const uint8_t *s = r->p, *q = r->p;
    BOOL negative = NO;
    if (q < r->end && (*q == '-' || *q == '+'))
        negative = *q++ == '-';
    size_t left = (size_t)(r->end - q);
    if (left >= 8 && !memcmp(q, "Infinity", 8)) {
        r->p = q + 8;
        return [NSNumber numberWithDouble:negative ? -INFINITY : INFINITY];
    }
    if (left >= 3 && !memcmp(q, "NaN", 3)) {
        r->p = q + 3;
        return [NSNumber numberWithDouble:NAN];
    }
    if (left >= 2 && q[0] == '0' && (q[1] == 'x' || q[1] == 'X')) {
        const uint8_t *h = q + 2;
        unsigned long long v = 0;
        BOOL any = NO, over = NO;
        while (h < r->end && isxdigit(*h)) {
            unsigned d = isdigit(*h) ? (unsigned)(*h - '0') : (unsigned)(tolower(*h) - 'a' + 10);
            if (v > (ULLONG_MAX >> 4))
                over = YES;
            v = (v << 4) | d;
            any = YES;
            h++;
        }
        if (!any)
            return fail(r, s, @"Invalid value");
        r->p = h;
        if (over)
            return [NSNumber numberWithDouble:negative ? -HUGE_VAL : HUGE_VAL];
        if (negative)
            return v <= (unsigned long long)LLONG_MAX + 1 ? [NSNumber numberWithLongLong:(long long)(0 - v)]
                                                          : [NSNumber numberWithDouble:-(double)v];
        return v <= LLONG_MAX ? [NSNumber numberWithLongLong:(long long)v] : [NSNumber numberWithUnsignedLongLong:v];
    }
    const uint8_t *digits = q;
    BOOL integral = YES, any = NO;
    while (q < r->end && *q >= '0' && *q <= '9')
        q++, any = YES;
    if (q < r->end && *q == '.') {
        integral = NO;
        q++;
        while (q < r->end && *q >= '0' && *q <= '9')
            q++, any = YES;
    }
    if (!any)
        return fail(r, s, @"Invalid value");
    if (q < r->end && (*q == 'e' || *q == 'E')) {
        integral = NO;
        q++;
        if (q < r->end && (*q == '+' || *q == '-'))
            q++;
        if (q >= r->end || *q < '0' || *q > '9')
            return fail(r, s, @"Invalid number: no digits in the exponent");
        while (q < r->end && *q >= '0' && *q <= '9')
            q++;
    }
    size_t n = (size_t)(q - digits);
    char *t = malloc(n + 2);
    t[0] = negative ? '-' : '+';
    memcpy(t + 1, digits, n);
    t[n + 1] = 0;
    r->p = q;
    NSNumber *num = nil;
    errno = 0;
    if (integral) {
        long long v = strtoll(t, NULL, 10);
        if (!errno)
            num = [NSNumber numberWithLongLong:v];
    }
    if (!num)
        num = [NSNumber numberWithDouble:strtod(t, NULL)];
    free(t);
    return num;
}

/* A JSON5 key without quotes: an ECMAScript identifier name. Letters beyond
 * ASCII are let through whole. */
static NSString *read_identifier(struct reader *r)
{
    const uint8_t *s = r->p;
    while (r->p < r->end && (isalnum(*r->p) || *r->p == '_' || *r->p == '$' || *r->p >= 0x80))
        r->p++;
    if (r->p == s || isdigit(*s))
        return fail(r, s, @"No string key for value in object");
    NSString *k = [[NSString alloc] initWithBytes:s length:(NSUInteger)(r->p - s) encoding:NSUTF8StringEncoding];
    return k ? [k autorelease] : fail(r, s, @"Unable to convert data to string");
}

static BOOL word(struct reader *r, const char *w)
{
    size_t n = strlen(w);
    if ((size_t)(r->end - r->p) < n || memcmp(r->p, w, n))
        return NO;
    r->p += n;
    return YES;
}

static id read_array(struct reader *r)
{
    const uint8_t *open = r->p++;
    NSMutableArray *a = [NSMutableArray array];
    skip_space(r);
    if (r->p < r->end && *r->p == ']') {
        r->p++;
        return a;
    }
    for (;;) {
        id v = read_value(r);
        if (!v)
            return nil;
        [a addObject:v];
        skip_space(r);
        if (r->p >= r->end)
            return fail(r, open, @"Unexpected end of file while parsing array");
        if (*r->p == ',') {
            r->p++;
            skip_space(r);
            /* a comma before the close is let through, as a Mac's reader
             * does: ShortcutRecorder's own style files have them (freemac
             * 1.224) */
            if (r->p < r->end && *r->p == ']') {
                r->p++;
                return a;
            }
            continue;
        }
        if (*r->p == ']') {
            r->p++;
            return a;
        }
        return fail(r, r->p, @"Badly formed array");
    }
}

/* bare: the members of a top-level dictionary without its braces, read to the end */
static id read_members(struct reader *r, BOOL bare)
{
    const uint8_t *open = bare ? r->p : r->p++;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    skip_space(r);
    if (r->p < r->end && *r->p == '}' && !bare) {
        r->p++;
        return d;
    }
    if (bare && r->p >= r->end)
        return d;
    for (;;) {
        skip_space(r);
        if (r->p >= r->end)
            return fail(r, open, @"Unexpected end of file while parsing object");
        NSString *key;
        if (*r->p == '"' || (r->json5 && *r->p == '\'')) {
            r->p++;
            key = read_string(r, NO);
        } else if (r->json5) {
            key = read_identifier(r);
        } else {
            return fail(r, r->p, @"No string key for value in object");
        }
        if (!key)
            return nil;
        skip_space(r);
        if (r->p >= r->end || *r->p != ':')
            return fail(r, r->p, @"No value for key in object");
        r->p++;
        id v = read_value(r);
        if (!v)
            return nil;
        [d setObject:v forKey:key];
        skip_space(r);
        if (r->p >= r->end)
            return bare ? d : fail(r, open, @"Unexpected end of file while parsing object");
        if (*r->p == ',') {
            r->p++;
            skip_space(r);
            if (bare && r->p >= r->end)
                return d;
            if (r->p < r->end && *r->p == '}' && !bare) {
                r->p++;
                return d;
            }
            continue;
        }
        if (*r->p == '}') {
            r->p++;
            return d;
        }
        return fail(r, r->p, @"Badly formed object");
    }
}

static id read_object(struct reader *r) { return read_members(r, NO); }

static id read_value(struct reader *r)
{
    skip_space(r);
    if (r->p >= r->end)
        return fail(r, r->p, @"Unexpected end of file during JSON parse");
    switch (*r->p) {
    case '{':
    case '[': {
        if (++r->depth > MAX_DEPTH)
            return fail(r, r->p, @"Too many nested arrays or dictionaries");
        id v = *r->p == '{' ? read_object(r) : read_array(r);
        r->depth--;
        if (v && !(r->opt & NSJSONReadingMutableContainers))
            v = [[v copy] autorelease];
        return v;
    }
    case '\'':
        if (!r->json5)
            break;
        /* fall through */
    case '"':
        r->p++;
        return read_string(r, (r->opt & NSJSONReadingMutableLeaves) != 0);
    case 't':
        if (word(r, "true"))
            return [NSNumber numberWithBool:YES];
        break;
    case 'f':
        if (word(r, "false"))
            return [NSNumber numberWithBool:NO];
        break;
    case 'n':
        if (word(r, "null"))
            return [NSNull null];
        break;
    default:
        if (*r->p == '-' || (*r->p >= '0' && *r->p <= '9'))
            return read_number(r);
        if (r->json5 && (*r->p == '+' || *r->p == '.' || *r->p == 'I' || *r->p == 'N'))
            return read_number(r);
        break;
    }
    return fail(r, r->p, @"Invalid value");
}

/* The text as UTF-8: UTF-16 and UTF-32 are converted; a byte order mark is dropped. */
static NSData *as_utf8(NSData *data)
{
    const uint8_t *b = [data bytes];
    NSUInteger n = [data length];
    int width = 1, big = 0, skip = 0;
    if (n >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) {
        return [data subdataWithRange:NSMakeRange(3, n - 3)];
    } else if (n >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0xfe && b[3] == 0xff) {
        width = 4, big = 1, skip = 4;
    } else if (n >= 4 && b[0] == 0xff && b[1] == 0xfe && b[2] == 0 && b[3] == 0) {
        width = 4, skip = 4;
    } else if (n >= 2 && b[0] == 0xfe && b[1] == 0xff) {
        width = 2, big = 1, skip = 2;
    } else if (n >= 2 && b[0] == 0xff && b[1] == 0xfe) {
        width = 2, skip = 2;
    } else if (n >= 4 && !b[0] && !b[1] && !b[2] && b[3]) {
        width = 4, big = 1;
    } else if (n >= 4 && b[0] && !b[1] && !b[2] && !b[3]) {
        width = 4;
    } else if (n >= 2 && !b[0] && b[1]) {
        width = 2, big = 1;
    } else if (n >= 2 && b[0] && !b[1]) {
        width = 2;
    }
    if (width == 1)
        return data;
    NSMutableData *out = [NSMutableData dataWithCapacity:n];
    for (NSUInteger i = (NSUInteger)skip; i + (NSUInteger)width <= n; i += (NSUInteger)width) {
        uint32_t c;
        if (width == 4) {
            c = big ? (uint32_t)b[i] << 24 | (uint32_t)b[i + 1] << 16 | (uint32_t)b[i + 2] << 8 | b[i + 3]
                    : (uint32_t)b[i + 3] << 24 | (uint32_t)b[i + 2] << 16 | (uint32_t)b[i + 1] << 8 | b[i];
        } else {
            c = big ? (uint32_t)b[i] << 8 | b[i + 1] : (uint32_t)b[i + 1] << 8 | b[i];
            if (c >= 0xd800 && c < 0xdc00 && i + 4 <= n) {
                uint32_t lo = big ? (uint32_t)b[i + 2] << 8 | b[i + 3] : (uint32_t)b[i + 3] << 8 | b[i + 2];
                if (lo >= 0xdc00 && lo < 0xe000) {
                    c = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00);
                    i += 2;
                }
            }
        }
        if (c > 0x10ffff || (c >= 0xd800 && c < 0xe000))
            return nil;
        put_utf8(out, c);
    }
    return out;
}

static NSError *json_error(NSString *why, NSUInteger at, NSData *text)
{
    NSUInteger line = 1, column = 1;
    const uint8_t *b = [text bytes];
    for (NSUInteger i = 0; i < at && i < [text length]; i++) {
        if (b[i] == '\n') {
            line++;
            column = 1;
        } else if ((b[i] & 0xc0) != 0x80) {
            column++;
        }
    }
    NSString *debug = [NSString stringWithFormat:@"%@ around line %lu, column %lu.", why, (unsigned long)line,
                                                 (unsigned long)column];
    return [NSError errorWithDomain:NSCocoaErrorDomain
                               code:JSON_ERROR
                           userInfo:@{
                               @"NSDebugDescription" : debug,
                               @"NSJSONSerializationErrorIndex" : [NSNumber numberWithUnsignedInteger:at],
                               NSLocalizedDescriptionKey : @"The data couldn’t be read because it isn’t in "
                                                           @"the correct format.",
                           }];
}

/* ---- writing ------------------------------------------------------------------------- */

static BOOL is_bool(id n) { return n == (id)kCFBooleanTrue || n == (id)kCFBooleanFalse; }

static void write_string(NSMutableData *out, NSString *s, NSJSONWritingOptions opt)
{
    const char *u = [s UTF8String];
    [out appendBytes:"\"" length:1];
    const char *run = u;
    for (const char *c = u; *c; c++) {
        unsigned char ch = (unsigned char)*c;
        const char *esc = NULL;
        char hex[8];
        switch (ch) {
        case '"': esc = "\\\""; break;
        case '\\': esc = "\\\\"; break;
        case '\n': esc = "\\n"; break;
        case '\r': esc = "\\r"; break;
        case '\t': esc = "\\t"; break;
        case '\b': esc = "\\b"; break;
        case '\f': esc = "\\f"; break;
        case '/':
            if (!(opt & NSJSONWritingWithoutEscapingSlashes))
                esc = "\\/";
            break;
        default:
            if (ch < 0x20) {
                snprintf(hex, sizeof hex, "\\u%04x", ch);
                esc = hex;
            }
            break;
        }
        if (esc) {
            [out appendBytes:run length:(NSUInteger)(c - run)];
            [out appendBytes:esc length:strlen(esc)];
            run = c + 1;
        }
    }
    [out appendBytes:run length:strlen(run)];
    [out appendBytes:"\"" length:1];
}

static void indent(NSMutableData *out, NSJSONWritingOptions opt, int level)
{
    if (!(opt & NSJSONWritingPrettyPrinted))
        return;
    [out appendBytes:"\n" length:1];
    for (int i = 0; i < level; i++)
        [out appendBytes:"  " length:2];
}

static void write_value(NSMutableData *out, id v, NSJSONWritingOptions opt, int level)
{
    BOOL pretty = (opt & NSJSONWritingPrettyPrinted) != 0;
    if ([v isKindOfClass:[NSString class]]) {
        write_string(out, v, opt);
    } else if ([v isKindOfClass:[NSNumber class]]) {
        if (is_bool(v)) {
            const char *w = v == (id)kCFBooleanTrue ? "true" : "false";
            [out appendBytes:w length:strlen(w)];
            return;
        }
        const char *t = [v objCType];
        if (*t == 'f' || *t == 'd') {
            double d = [v doubleValue];
            if (isnan(d) || isinf(d))
                FRaise(NSInvalidArgumentException, @"Invalid number value (%@) in JSON write", isnan(d) ? @"NaN" : @"infinite");
        }
        NSString *s = [v stringValue];
        [out appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    } else if ([v isKindOfClass:[NSNull class]]) {
        [out appendBytes:"null" length:4];
    } else if ([v isKindOfClass:[NSArray class]]) {
        [out appendBytes:"[" length:1];
        NSUInteger i = 0;
        for (id e in v) {
            if (i++)
                [out appendBytes:"," length:1];
            indent(out, opt, level + 1);
            write_value(out, e, opt, level + 1);
        }
        if (pretty && !i)
            [out appendBytes:"\n" length:1];
        indent(out, opt, level);
        [out appendBytes:"]" length:1];
    } else if ([v isKindOfClass:[NSDictionary class]]) {
        [out appendBytes:"{" length:1];
        NSArray *keys = [v allKeys];
        for (id k in keys)
            if (![k isKindOfClass:[NSString class]])
                FRaise(NSInvalidArgumentException, @"Invalid (non-string) key in JSON dictionary");
        if (opt & NSJSONWritingSortedKeys)
            keys = [keys sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger i = 0;
        for (NSString *k in keys) {
            if (i++)
                [out appendBytes:"," length:1];
            indent(out, opt, level + 1);
            write_string(out, k, opt);
            if (pretty)
                [out appendBytes:" : " length:3];
            else
                [out appendBytes:":" length:1];
            write_value(out, [v objectForKey:k], opt, level + 1);
        }
        if (pretty && !i)
            [out appendBytes:"\n" length:1];
        indent(out, opt, level);
        [out appendBytes:"}" length:1];
    } else {
        FRaise(NSInvalidArgumentException, @"Invalid type in JSON write (%s)", object_getClassName(v));
    }
}

static BOOL valid(id v, int depth)
{
    if (depth > MAX_DEPTH)
        return NO;
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNull class]])
        return YES;
    if ([v isKindOfClass:[NSNumber class]]) {
        if (is_bool(v))
            return YES;
        double d = [v doubleValue];
        return !isnan(d) && !isinf(d);
    }
    if ([v isKindOfClass:[NSArray class]]) {
        for (id e in v)
            if (!valid(e, depth + 1))
                return NO;
        return YES;
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        for (id k in v)
            if (![k isKindOfClass:[NSString class]] || !valid([v objectForKey:k], depth + 1))
                return NO;
        return YES;
    }
    return NO;
}

static BOOL is_container(id v) { return [v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]]; }

@implementation NSJSONSerialization

+ (BOOL)isValidJSONObject:(id)obj
{
    return obj && is_container(obj) && valid(obj, 0);
}

+ (NSData *)dataWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"+[NSJSONSerialization dataWithJSONObject:options:error:]: value "
                                           @"parameter is nil");
    if (!(opt & NSJSONWritingFragmentsAllowed) && !is_container(obj))
        FRaise(NSInvalidArgumentException, @"+[NSJSONSerialization dataWithJSONObject:options:error:]: Invalid "
                                           @"top-level type in JSON write");
    NSMutableData *out = [NSMutableData data];
    write_value(out, obj, opt, 0);
    return out;
}

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error
{
    if (!data)
        FRaise(NSInvalidArgumentException, @"+[NSJSONSerialization JSONObjectWithData:options:error:]: data "
                                           @"parameter is nil");
    NSData *text = as_utf8(data);
    if (!text) {
        FSetError(error, json_error(@"Unable to convert data to string", 0, data));
        return nil;
    }
    struct reader r = {0};
    r.start = r.p = [text bytes];
    r.end = r.start + [text length];
    r.opt = opt;
    r.json5 = (opt & NSJSONReadingJSON5Allowed) != 0;
    skip_space(&r);
    if (r.json5 && (opt & NSJSONReadingTopLevelDictionaryAssumed) && (r.p >= r.end || *r.p != '{')) {
        id d = read_members(&r, YES);
        if (d && !(opt & NSJSONReadingMutableContainers))
            d = [[d copy] autorelease];
        if (!d)
            FSetError(error, json_error(r.why ?: @"Invalid value", r.at, text));
        return d;
    }
    if (r.p >= r.end) {
        FSetError(error, json_error(@"Unexpected end of file during JSON parse", 0, text));
        return nil;
    }
    if (!(opt & NSJSONReadingFragmentsAllowed) && *r.p != '{' && *r.p != '[') {
        FSetError(error, json_error(@"JSON text did not start with array or object and option to allow fragments "
                                    @"not set",
                                    (NSUInteger)(r.p - r.start), text));
        return nil;
    }
    id v = read_value(&r);
    if (v) {
        skip_space(&r);
        if (r.p < r.end) {
            fail(&r, r.p, @"Garbage at end");
            v = nil;
        }
    }
    if (!v) {
        FSetError(error, json_error(r.why ?: @"Invalid value", r.at, text));
        return nil;
    }
    return v;
}

/* Streams (freemac 1.221, Ferry 0.45.0): the input is read to its end
 * (opened first if it isn't open), the output written whole. */
+ (id)JSONObjectWithStream:(NSInputStream *)stream options:(NSJSONReadingOptions)opt error:(NSError **)error
{
    if (!stream)
        FRaise(NSInvalidArgumentException, @"+[NSJSONSerialization JSONObjectWithStream:options:error:]: stream is nil");
    if ([stream streamStatus] == NSStreamStatusNotOpen)
        [stream open];
    NSMutableData *data = [NSMutableData data];
    uint8_t buf[4096];
    NSInteger n;
    while ((n = [stream read:buf maxLength:sizeof buf]) > 0)
        [data appendBytes:buf length:(NSUInteger)n];
    if (n < 0) {
        FSetError(error, [stream streamError]);
        return nil;
    }
    return [self JSONObjectWithData:data options:opt error:error];
}
+ (NSInteger)writeJSONObject:(id)obj toStream:(NSOutputStream *)stream options:(NSJSONWritingOptions)opt
                       error:(NSError **)error
{
    NSData *data = [self dataWithJSONObject:obj options:opt error:error];
    if (!data)
        return 0;
    if ([stream streamStatus] == NSStreamStatusNotOpen)
        [stream open];
    const uint8_t *p = [data bytes];
    NSUInteger left = [data length], done = 0;
    while (left) {
        NSInteger n = [stream write:p + done maxLength:left];
        if (n <= 0) {
            FSetError(error, [stream streamError]);
            return 0;
        }
        done += (NSUInteger)n;
        left -= (NSUInteger)n;
    }
    return (NSInteger)done;
}
@end
