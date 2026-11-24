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
 * 3840, with the place it was found. JSON5 isn't read: with that option,
 * plain JSON still is, and TopLevelDictionaryAssumed (a JSON5 option) has
 * no effect. Writing takes the same classes and raises
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
    while (r->p < r->end && (*r->p == ' ' || *r->p == '\t' || *r->p == '\n' || *r->p == '\r'))
        r->p++;
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

/* r->p is just past the opening quote. */
static NSString *read_string(struct reader *r, BOOL mutable_)
{
    const uint8_t *open = r->p - 1;
    NSMutableData *buf = nil;
    const uint8_t *run = r->p;
    for (;;) {
        if (r->p >= r->end)
            return fail(r, open, @"Unterminated string");
        uint8_t c = *r->p;
        if (c == '"')
            break;
        if (c < 0x20)
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
            return fail(r, esc, @"Invalid escape sequence");
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

static NSNumber *read_number(struct reader *r)
{
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
            if (r->p < r->end && *r->p == ']')
                return fail(r, r->p, @"Trailing comma in array");
            continue;
        }
        if (*r->p == ']') {
            r->p++;
            return a;
        }
        return fail(r, r->p, @"Badly formed array");
    }
}

static id read_object(struct reader *r)
{
    const uint8_t *open = r->p++;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    skip_space(r);
    if (r->p < r->end && *r->p == '}') {
        r->p++;
        return d;
    }
    for (;;) {
        skip_space(r);
        if (r->p >= r->end)
            return fail(r, open, @"Unexpected end of file while parsing object");
        if (*r->p != '"')
            return fail(r, r->p, @"No string key for value in object");
        r->p++;
        NSString *key = read_string(r, NO);
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
            return fail(r, open, @"Unexpected end of file while parsing object");
        if (*r->p == ',') {
            r->p++;
            skip_space(r);
            if (r->p < r->end && *r->p == '}')
                return fail(r, r->p, @"Trailing comma in object");
            continue;
        }
        if (*r->p == '}') {
            r->p++;
            return d;
        }
        return fail(r, r->p, @"Badly formed object");
    }
}

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
    skip_space(&r);
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
@end
