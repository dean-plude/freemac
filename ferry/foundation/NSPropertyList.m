/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: property lists. Reads the three formats a Mac app may
 * carry (XML, binary "bplist00" and the old OpenStep text form, which
 * .strings files use) and writes XML and binary. Written from the published
 * descriptions of these formats. */
#import "FInternal.h"

static NSError *format_error(NSString *why)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain
                               code:3840
                           userInfo:[NSDictionary dictionaryWithObject:why forKey:@"NSDebugDescription"]];
}

static id finish_container(id obj, NSPropertyListMutabilityOptions opt)
{
    if (opt == NSPropertyListImmutable)
        return obj;
    return obj; /* containers are built mutable and stay so */
}

static id finish_leaf(id obj, NSPropertyListMutabilityOptions opt)
{
    if (opt == NSPropertyListMutableContainersAndLeaves &&
        ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSData class]]))
        return [[obj mutableCopy] autorelease];
    return obj;
}

static id freeze(id obj, NSPropertyListMutabilityOptions opt)
{
    if (opt != NSPropertyListImmutable)
        return obj;
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id o in obj)
            [a addObject:freeze(o, opt)];
        return [NSArray arrayWithArray:a];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id k in obj)
            [d setObject:freeze([obj objectForKey:k], opt) forKey:k];
        return [NSDictionary dictionaryWithDictionary:d];
    }
    return obj;
}

/* ---- XML -------------------------------------------------------------------------- */

struct xml {
    const char *p, *end;
    NSPropertyListMutabilityOptions opt;
    BOOL bad;
};

static void skip_space(struct xml *x)
{
    for (;;) {
        while (x->p < x->end && (*x->p == ' ' || *x->p == '\t' || *x->p == '\n' || *x->p == '\r'))
            x->p++;
        if (x->end - x->p >= 4 && !memcmp(x->p, "<!--", 4)) {
            const char *e = strstr(x->p, "-->");
            x->p = e && e < x->end ? e + 3 : x->end;
            continue;
        }
        if (x->end - x->p >= 2 && (!memcmp(x->p, "<?", 2) || !memcmp(x->p, "<!", 2))) {
            while (x->p < x->end && *x->p != '>')
                x->p++;
            if (x->p < x->end)
                x->p++;
            continue;
        }
        return;
    }
}

/* Reads "<name ...>" or "<name/>"; returns 1 for an open tag, 2 for an empty
 * tag, 3 for a closing tag, 0 on error. */
static int read_tag(struct xml *x, char *name, size_t size)
{
    skip_space(x);
    if (x->p >= x->end || *x->p != '<')
        return 0;
    x->p++;
    int kind = 1;
    if (x->p < x->end && *x->p == '/') {
        kind = 3;
        x->p++;
    }
    size_t n = 0;
    while (x->p < x->end && *x->p != '>' && *x->p != ' ' && *x->p != '/' && n + 1 < size)
        name[n++] = *x->p++;
    name[n] = 0;
    while (x->p < x->end && *x->p != '>')
        x->p++;
    if (x->p >= x->end)
        return 0;
    if (x->p[-1] == '/' && kind == 1)
        kind = 2;
    x->p++;
    return kind;
}

static NSString *read_text(struct xml *x, const char *close)
{
    NSMutableData *buf = [NSMutableData data];
    while (x->p < x->end && *x->p != '<') {
        if (*x->p == '&') {
            const char *semi = memchr(x->p, ';', x->end - x->p);
            if (!semi) {
                x->bad = YES;
                return nil;
            }
            char ent[16] = {0};
            size_t len = semi - x->p - 1;
            memcpy(ent, x->p + 1, len < 15 ? len : 15);
            unsigned long cp = 0;
            if (!strcmp(ent, "lt")) cp = '<';
            else if (!strcmp(ent, "gt")) cp = '>';
            else if (!strcmp(ent, "amp")) cp = '&';
            else if (!strcmp(ent, "quot")) cp = '"';
            else if (!strcmp(ent, "apos")) cp = '\'';
            else if (ent[0] == '#') cp = ent[1] == 'x' ? strtoul(ent + 2, NULL, 16) : strtoul(ent + 1, NULL, 10);
            unichar u[2];
            NSUInteger un = 1;
            if (cp >= 0x10000) {
                u[0] = 0xd800 + ((cp - 0x10000) >> 10);
                u[1] = 0xdc00 + ((cp - 0x10000) & 0x3ff);
                un = 2;
            } else {
                u[0] = (unichar)cp;
            }
            NSUInteger ol;
            char *utf8 = FEncodeUTF8(u, un, &ol);
            [buf appendBytes:utf8 length:ol];
            free(utf8);
            x->p = semi + 1;
        } else if (x->end - x->p >= 9 && !memcmp(x->p, "<![CDATA[", 9)) {
            break;
        } else {
            [buf appendBytes:x->p length:1];
            x->p++;
        }
        if (x->p < x->end && *x->p == '<' && x->end - x->p >= 9 && !memcmp(x->p, "<![CDATA[", 9)) {
            const char *e = strstr(x->p, "]]>");
            if (!e) {
                x->bad = YES;
                return nil;
            }
            [buf appendBytes:x->p + 9 length:e - x->p - 9];
            x->p = e + 3;
        }
    }
    char name[32];
    if (read_tag(x, name, sizeof name) != 3 || strcmp(name, close)) {
        x->bad = YES;
        return nil;
    }
    return FStringFromUTF8([buf bytes], [buf length]);
}

static id xml_value(struct xml *x, const char *tag, int kind);

static id xml_next(struct xml *x)
{
    char name[32];
    int kind = read_tag(x, name, sizeof name);
    if (kind == 0 || kind == 3) {
        x->bad = YES;
        return nil;
    }
    return xml_value(x, name, kind);
}

static NSDate *parse_iso_date(NSString *s)
{
    struct tm tm = {0};
    int y, mo, d, h = 0, mi = 0, sec = 0;
    if (sscanf([s UTF8String], "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &sec) < 3)
        return nil;
    tm.tm_year = y - 1900;
    tm.tm_mon = mo - 1;
    tm.tm_mday = d;
    tm.tm_hour = h;
    tm.tm_min = mi;
    tm.tm_sec = sec;
    return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timegm(&tm)];
}

static id xml_value(struct xml *x, const char *tag, int kind)
{
    if (!strcmp(tag, "dict")) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        if (kind == 2)
            return finish_container(d, x->opt);
        for (;;) {
            char name[32];
            int k = read_tag(x, name, sizeof name);
            if (k == 3 && !strcmp(name, "dict"))
                return finish_container(d, x->opt);
            NSString *key = k == 2 && !strcmp(name, "key") ? @"" : k == 1 && !strcmp(name, "key") ? read_text(x, "key")
                                                                                                    : nil;
            if (!key) {
                x->bad = YES;
                return nil;
            }
            id v = xml_next(x);
            if (!v)
                return nil;
            [d setObject:v forKey:key];
        }
    }
    if (!strcmp(tag, "array")) {
        NSMutableArray *a = [NSMutableArray array];
        if (kind == 2)
            return finish_container(a, x->opt);
        for (;;) {
            skip_space(x);
            if (x->end - x->p >= 8 && !memcmp(x->p, "</array>", 8)) {
                x->p += 8;
                return finish_container(a, x->opt);
            }
            id v = xml_next(x);
            if (!v)
                return nil;
            [a addObject:v];
        }
    }
    if (!strcmp(tag, "true") || !strcmp(tag, "false")) {
        if (kind == 1) {
            char name[32];
            if (read_tag(x, name, sizeof name) != 3)
                x->bad = YES;
        }
        return [NSNumber numberWithBool:tag[0] == 't'];
    }
    NSString *text = kind == 2 ? @"" : read_text(x, tag);
    if (!text)
        return nil;
    if (!strcmp(tag, "string") || !strcmp(tag, "key"))
        return finish_leaf(text, x->opt);
    if (!strcmp(tag, "integer")) {
        const char *t = [text UTF8String];
        while (*t == ' ' || *t == '\n' || *t == '\t')
            t++;
        if (*t == '-')
            return [NSNumber numberWithLongLong:strtoll(t, NULL, 0)];
        unsigned long long u = strtoull(t, NULL, 0);
        return u > LLONG_MAX ? [NSNumber numberWithUnsignedLongLong:u] : [NSNumber numberWithLongLong:(long long)u];
    }
    if (!strcmp(tag, "real"))
        return [NSNumber numberWithDouble:strtod([text UTF8String], NULL)];
    if (!strcmp(tag, "date")) {
        NSDate *d = parse_iso_date(text);
        if (!d)
            x->bad = YES;
        return d;
    }
    if (!strcmp(tag, "data")) {
        NSData *d = [[[NSData alloc] initWithBase64EncodedString:text options:0] autorelease];
        if (!d)
            x->bad = YES;
        return finish_leaf(d, x->opt);
    }
    x->bad = YES;
    return nil;
}

static id parse_xml(NSData *data, NSPropertyListMutabilityOptions opt)
{
    struct xml x = {(const char *)[data bytes], (const char *)[data bytes] + [data length], opt, NO};
    char name[32];
    int k = read_tag(&x, name, sizeof name);
    if (k != 1 || strcmp(name, "plist"))
        return nil;
    id v = xml_next(&x);
    if (x.bad || !v)
        return nil;
    if (read_tag(&x, name, sizeof name) != 3)
        return nil;
    return v;
}

/* ---- binary ("bplist00") ----------------------------------------------------------- */

struct bplist {
    const unsigned char *b;
    size_t len;
    int offsize, refsize;
    uint64_t nobjects, offtable;
    NSPropertyListMutabilityOptions opt;
    int depth;
};

static uint64_t be(const unsigned char *p, int n)
{
    uint64_t v = 0;
    for (int i = 0; i < n; i++)
        v = v << 8 | p[i];
    return v;
}

static id bp_object(struct bplist *bp, uint64_t ref);

static BOOL bp_count(struct bplist *bp, const unsigned char **p, uint64_t *count)
{
    unsigned low = **p & 0x0f;
    (*p)++;
    if (low != 0x0f) {
        *count = low;
        return YES;
    }
    if (*p >= bp->b + bp->len || (**p & 0xf0) != 0x10)
        return NO;
    int n = 1 << (**p & 0x0f);
    (*p)++;
    if (*p + n > bp->b + bp->len)
        return NO;
    *count = be(*p, n);
    *p += n;
    return YES;
}

static id bp_object(struct bplist *bp, uint64_t ref)
{
    if (ref >= bp->nobjects || bp->depth > 512)
        return nil;
    uint64_t off = be(bp->b + bp->offtable + ref * bp->offsize, bp->offsize);
    if (off >= bp->len)
        return nil;
    const unsigned char *p = bp->b + off, *end = bp->b + bp->len;
    unsigned marker = *p;
    uint64_t count;
    switch (marker >> 4) {
    case 0x0:
        if (marker == 0x08 || marker == 0x09)
            return [NSNumber numberWithBool:marker == 0x09];
        return nil;
    case 0x1: {
        int n = 1 << (marker & 0x0f);
        if (p + 1 + n > end)
            return nil;
        uint64_t v = be(p + 1, n);
        if (n == 16) /* 128-bit: the low 8 bytes hold the value */
            v = be(p + 9, 8);
        return n >= 8 ? [NSNumber numberWithLongLong:(long long)v] : [NSNumber numberWithLongLong:(long long)v];
    }
    case 0x2: {
        int n = 1 << (marker & 0x0f);
        if (p + 1 + n > end)
            return nil;
        uint64_t v = be(p + 1, n);
        if (n == 4) {
            union { uint32_t u; float f; } c = {.u = (uint32_t)v};
            return [NSNumber numberWithFloat:c.f];
        }
        union { uint64_t u; double d; } c = {.u = v};
        return [NSNumber numberWithDouble:c.d];
    }
    case 0x3: {
        if (p + 9 > end)
            return nil;
        union { uint64_t u; double d; } c = {.u = be(p + 1, 8)};
        return [NSDate dateWithTimeIntervalSinceReferenceDate:c.d];
    }
    case 0x4:
        if (!bp_count(bp, &p, &count) || p + count > end)
            return nil;
        return finish_leaf([NSData dataWithBytes:p length:count], bp->opt);
    case 0x5:
        if (!bp_count(bp, &p, &count) || p + count > end)
            return nil;
        return finish_leaf(FStringFromUTF8((const char *)p, count), bp->opt);
    case 0x6: {
        if (!bp_count(bp, &p, &count) || p + count * 2 > end)
            return nil;
        unichar *u = malloc((count ? count : 1) * sizeof(unichar));
        for (uint64_t i = 0; i < count; i++)
            u[i] = (unichar)be(p + i * 2, 2);
        NSString *s = FStringFromChars(u, count);
        free(u);
        return finish_leaf(s, bp->opt);
    }
    case 0x8: { /* UID, used by keyed archives */
        int n = (marker & 0x0f) + 1;
        return [NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:(long long)be(p + 1, n)]
                                           forKey:@"CF$UID"];
    }
    case 0xa:
    case 0xc: {
        if (!bp_count(bp, &p, &count) || p + count * bp->refsize > end)
            return nil;
        NSMutableArray *a = [NSMutableArray array];
        bp->depth++;
        for (uint64_t i = 0; i < count; i++) {
            id o = bp_object(bp, be(p + i * bp->refsize, bp->refsize));
            if (!o)
                return nil;
            [a addObject:o];
        }
        bp->depth--;
        if (marker >> 4 == 0xc)
            return bp->opt ? [NSMutableSet setWithArray:a] : [NSSet setWithArray:a];
        return finish_container(a, bp->opt);
    }
    case 0xd: {
        if (!bp_count(bp, &p, &count) || p + count * 2 * bp->refsize > end)
            return nil;
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        bp->depth++;
        for (uint64_t i = 0; i < count; i++) {
            id k = bp_object(bp, be(p + i * bp->refsize, bp->refsize));
            id v = bp_object(bp, be(p + (count + i) * bp->refsize, bp->refsize));
            if (!k || !v)
                return nil;
            [d setObject:v forKey:k];
        }
        bp->depth--;
        return finish_container(d, bp->opt);
    }
    }
    return nil;
}

static id parse_binary(NSData *data, NSPropertyListMutabilityOptions opt)
{
    const unsigned char *b = [data bytes];
    size_t len = [data length];
    if (len < 8 + 32)
        return nil;
    const unsigned char *t = b + len - 32;
    struct bplist bp = {b, len, t[6], t[7], be(t + 8, 8), be(t + 24, 8), opt, 0};
    uint64_t top = be(t + 16, 8);
    if (bp.offsize < 1 || bp.offsize > 8 || bp.refsize < 1 || bp.refsize > 8 ||
        bp.offtable + bp.nobjects * bp.offsize > len - 32)
        return nil;
    return bp_object(&bp, top);
}

/* ---- OpenStep text (and .strings files) ------------------------------------------------- */

struct ostep {
    const unichar *c;
    NSUInteger i, n;
    BOOL bad;
};

static void os_space(struct ostep *o)
{
    while (o->i < o->n) {
        unichar c = o->c[o->i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0xfeff) {
            o->i++;
        } else if (c == '/' && o->i + 1 < o->n && o->c[o->i + 1] == '/') {
            while (o->i < o->n && o->c[o->i] != '\n')
                o->i++;
        } else if (c == '/' && o->i + 1 < o->n && o->c[o->i + 1] == '*') {
            o->i += 2;
            while (o->i + 1 < o->n && !(o->c[o->i] == '*' && o->c[o->i + 1] == '/'))
                o->i++;
            o->i += 2;
        } else {
            return;
        }
    }
}

static BOOL os_plain(unichar c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '$' ||
           c == '/' || c == ':' || c == '.' || c == '-';
}

static id os_value(struct ostep *o);

static NSString *os_string(struct ostep *o)
{
    os_space(o);
    if (o->i >= o->n) {
        o->bad = YES;
        return nil;
    }
    unichar q = o->c[o->i];
    if (q == '"' || q == '\'') {
        o->i++;
        NSMutableString *s = [NSMutableString string];
        while (o->i < o->n && o->c[o->i] != q) {
            unichar c = o->c[o->i++];
            if (c == '\\' && o->i < o->n) {
                c = o->c[o->i++];
                switch (c) {
                case 'n': c = '\n'; break;
                case 't': c = '\t'; break;
                case 'r': c = '\r'; break;
                case 'a': c = 7; break;
                case 'b': c = 8; break;
                case 'f': c = 12; break;
                case 'v': c = 11; break;
                case 'U':
                case 'u': {
                    unsigned v = 0;
                    for (int k = 0; k < 4 && o->i < o->n; k++) {
                        unichar h = o->c[o->i];
                        int d = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10
                                : h >= 'A' && h <= 'F'                              ? h - 'A' + 10
                                                                                    : -1;
                        if (d < 0)
                            break;
                        v = v * 16 + d;
                        o->i++;
                    }
                    c = v;
                    break;
                }
                default:
                    if (c >= '0' && c <= '7') {
                        unsigned v = c - '0';
                        for (int k = 0; k < 2 && o->i < o->n && o->c[o->i] >= '0' && o->c[o->i] <= '7'; k++)
                            v = v * 8 + (o->c[o->i++] - '0');
                        c = v;
                    }
                }
            }
            [s appendString:FStringFromChars(&c, 1)];
        }
        if (o->i >= o->n) {
            o->bad = YES;
            return nil;
        }
        o->i++;
        return s;
    }
    NSUInteger start = o->i;
    while (o->i < o->n && os_plain(o->c[o->i]))
        o->i++;
    if (o->i == start) {
        o->bad = YES;
        return nil;
    }
    return FStringFromChars(o->c + start, o->i - start);
}

static NSMutableDictionary *os_dict_body(struct ostep *o, unichar close)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (;;) {
        os_space(o);
        if (o->i >= o->n) {
            if (close) {
                o->bad = YES;
                return nil;
            }
            return d;
        }
        if (o->c[o->i] == close) {
            o->i++;
            return d;
        }
        NSString *k = os_string(o);
        if (!k)
            return nil;
        os_space(o);
        id v;
        if (o->i < o->n && o->c[o->i] == ';') {
            v = k; /* .strings shorthand: "key"; means "key" = "key"; */
        } else {
            if (o->i >= o->n || o->c[o->i] != '=') {
                o->bad = YES;
                return nil;
            }
            o->i++;
            v = os_value(o);
            if (!v)
                return nil;
            os_space(o);
        }
        if (o->i >= o->n || o->c[o->i] != ';') {
            o->bad = YES;
            return nil;
        }
        o->i++;
        [d setObject:v forKey:k];
    }
}

static id os_value(struct ostep *o)
{
    os_space(o);
    if (o->i >= o->n) {
        o->bad = YES;
        return nil;
    }
    unichar c = o->c[o->i];
    if (c == '{') {
        o->i++;
        return os_dict_body(o, '}');
    }
    if (c == '(') {
        o->i++;
        NSMutableArray *a = [NSMutableArray array];
        os_space(o);
        if (o->i < o->n && o->c[o->i] == ')') {
            o->i++;
            return a;
        }
        for (;;) {
            id v = os_value(o);
            if (!v)
                return nil;
            [a addObject:v];
            os_space(o);
            if (o->i < o->n && o->c[o->i] == ',') {
                o->i++;
                os_space(o);
                if (o->i < o->n && o->c[o->i] == ')') {
                    o->i++;
                    return a;
                }
                continue;
            }
            if (o->i < o->n && o->c[o->i] == ')') {
                o->i++;
                return a;
            }
            o->bad = YES;
            return nil;
        }
    }
    if (c == '<') {
        o->i++;
        NSMutableData *d = [NSMutableData data];
        int half = -1;
        while (o->i < o->n && o->c[o->i] != '>') {
            unichar h = o->c[o->i++];
            int v = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10 : h >= 'A' && h <= 'F' ? h - 'A' + 10 : -1;
            if (v < 0)
                continue;
            if (half < 0) {
                half = v;
            } else {
                unsigned char byte = half << 4 | v;
                [d appendBytes:&byte length:1];
                half = -1;
            }
        }
        o->i++;
        return d;
    }
    return os_string(o);
}

static id parse_openstep(NSData *data, NSPropertyListMutabilityOptions opt)
{
    const unsigned char *b = [data bytes];
    NSUInteger len = [data length], n;
    unichar *chars;
    if (len >= 2 && ((b[0] == 0xff && b[1] == 0xfe) || (b[0] == 0xfe && b[1] == 0xff))) {
        BOOL bigEndian = b[0] == 0xfe;
        n = (len - 2) / 2;
        chars = malloc((n ? n : 1) * sizeof(unichar));
        for (NSUInteger i = 0; i < n; i++)
            chars[i] = bigEndian ? b[2 + 2 * i] << 8 | b[3 + 2 * i] : b[3 + 2 * i] << 8 | b[2 + 2 * i];
    } else {
        chars = FDecodeUTF8((const char *)b, len, &n);
    }
    struct ostep o = {chars, 0, n, NO};
    id v;
    os_space(&o);
    NSUInteger save = o.i;
    /* A .strings file is a dictionary without its braces. */
    if (o.i < o.n && o.c[o.i] != '{' && o.c[o.i] != '(' && o.c[o.i] != '<') {
        NSString *first = os_string(&o);
        os_space(&o);
        o.i = save;
        o.bad = NO;
        if (first && o.i < o.n) {
            NSUInteger k = save;
            struct ostep peek = o;
            os_string(&peek);
            os_space(&peek);
            k = peek.i;
            if (k < o.n && (o.c[k] == '=' || o.c[k] == ';')) {
                v = os_dict_body(&o, 0);
                free(chars);
                return o.bad ? nil : v;
            }
        }
    }
    v = os_value(&o);
    os_space(&o);
    if (o.i < o.n)
        o.bad = YES;
    free(chars);
    return o.bad ? nil : v;
}

id FParsePlist(NSData *data, NSPropertyListMutabilityOptions opt, NSPropertyListFormat *format)
{
    if (!data)
        return nil;
    const char *b = [data bytes];
    NSUInteger len = [data length];
    id v = nil;
    if (len >= 8 && !memcmp(b, "bplist00", 8)) {
        v = parse_binary(data, opt);
        if (format)
            *format = NSPropertyListBinaryFormat_v1_0;
    } else {
        NSUInteger i = 0;
        if (len >= 3 && !memcmp(b, "\xef\xbb\xbf", 3))
            i = 3;
        while (i < len && (b[i] == ' ' || b[i] == '\n' || b[i] == '\r' || b[i] == '\t'))
            i++;
        if (i < len && b[i] == '<' && i + 1 < len && (b[i + 1] == '?' || b[i + 1] == '!' || b[i + 1] == 'p')) {
            v = parse_xml([data subdataWithRange:NSMakeRange(i, len - i)], opt);
            if (format)
                *format = NSPropertyListXMLFormat_v1_0;
        } else {
            v = parse_openstep(data, opt);
            if (format)
                *format = NSPropertyListOpenStepFormat;
        }
    }
    return freeze(v, opt);
}

/* ---- writing XML ---------------------------------------------------------------------- */

static void xml_escape(NSMutableString *out, NSString *s)
{
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '<')
            [out appendString:@"&lt;"];
        else if (c == '>')
            [out appendString:@"&gt;"];
        else if (c == '&')
            [out appendString:@"&amp;"];
        else
            [out appendString:FStringFromChars(&c, 1)];
    }
}

static BOOL xml_write(NSMutableString *out, id obj, int depth)
{
    NSMutableString *tabs = [NSMutableString string];
    for (int i = 0; i < depth; i++)
        [tabs appendString:@"\t"];
    if ([obj isKindOfClass:[NSString class]]) {
        [out appendFormat:@"%@<string>", tabs];
        xml_escape(out, obj);
        [out appendString:@"</string>\n"];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        const char *t = [obj objCType];
        if (obj == (id)kCFBooleanTrue || obj == (id)kCFBooleanFalse)
            [out appendFormat:@"%@<%s/>\n", tabs, [obj boolValue] ? "true" : "false"];
        else if (*t == 'f' || *t == 'd')
            [out appendFormat:@"%@<real>%@</real>\n", tabs, obj];
        else
            [out appendFormat:@"%@<integer>%@</integer>\n", tabs, obj];
    } else if ([obj isKindOfClass:[NSDate class]]) {
        time_t t = (time_t)floor([obj timeIntervalSince1970]);
        struct tm tm;
        char buf[32];
        gmtime_r(&t, &tm);
        strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &tm);
        [out appendFormat:@"%@<date>%s</date>\n", tabs, buf];
    } else if ([obj isKindOfClass:[NSData class]]) {
        [out appendFormat:@"%@<data>\n%@%@\n%@</data>\n", tabs, tabs, [obj base64EncodedStringWithOptions:0], tabs];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        if ([obj count] == 0) {
            [out appendFormat:@"%@<array/>\n", tabs];
            return YES;
        }
        [out appendFormat:@"%@<array>\n", tabs];
        for (id o in obj)
            if (!xml_write(out, o, depth + 1))
                return NO;
        [out appendFormat:@"%@</array>\n", tabs];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        if ([obj count] == 0) {
            [out appendFormat:@"%@<dict/>\n", tabs];
            return YES;
        }
        [out appendFormat:@"%@<dict>\n", tabs];
        NSArray *keys = [[obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (id k in keys) {
            if (![k isKindOfClass:[NSString class]])
                return NO;
            [out appendFormat:@"%@\t<key>", tabs];
            xml_escape(out, k);
            [out appendString:@"</key>\n"];
            if (!xml_write(out, [obj objectForKey:k], depth + 1))
                return NO;
        }
        [out appendFormat:@"%@</dict>\n", tabs];
    } else {
        return NO;
    }
    return YES;
}

NSData *FWriteXMLPlist(id plist)
{
    NSMutableString *out = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"];
    if (!xml_write(out, plist, 0))
        return nil;
    [out appendString:@"</plist>\n"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

/* ---- writing binary --------------------------------------------------------------------- */

struct bpw {
    NSMutableArray *objects; /* flattened, index = object reference */
    NSMutableData *out;
    int refsize;
};

/* Keyed archives' UIDs are one-entry dictionaries {"CF$UID": n}. */
static BOOL is_uid(id obj, uint64_t *n)
{
    if (![obj isKindOfClass:[NSDictionary class]] || [obj count] != 1)
        return NO;
    id v = [obj objectForKey:@"CF$UID"];
    if (![v isKindOfClass:[NSNumber class]] || [v longLongValue] < 0)
        return NO;
    if (n)
        *n = [v unsignedLongLongValue];
    return YES;
}

static NSUInteger bpw_flatten(struct bpw *w, id obj)
{
    NSUInteger ref = [w->objects count];
    [w->objects addObject:obj];
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id o in obj)
            bpw_flatten(w, o);
    } else if ([obj isKindOfClass:[NSDictionary class]] && !is_uid(obj, NULL)) {
        NSArray *keys = [[obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (id k in keys)
            bpw_flatten(w, k);
        for (id k in keys)
            bpw_flatten(w, [obj objectForKey:k]);
    }
    return ref;
}

static void put_be(NSMutableData *d, uint64_t v, int n)
{
    unsigned char b[8];
    for (int i = n - 1; i >= 0; i--, v >>= 8)
        b[i] = v & 0xff;
    [d appendBytes:b length:n];
}

static void put_marker(NSMutableData *d, unsigned type, uint64_t count)
{
    unsigned char m;
    if (count < 15) {
        m = type << 4 | count;
        [d appendBytes:&m length:1];
        return;
    }
    m = type << 4 | 0xf;
    [d appendBytes:&m length:1];
    int lg = count < 256 ? 0 : count < 65536 ? 1 : count < 4294967296ull ? 2 : 3;
    m = 0x10 | lg;
    [d appendBytes:&m length:1];
    put_be(d, count, 1 << lg);
}

static NSUInteger bpw_count_tree(id obj)
{
    NSUInteger n = 1;
    if ([obj isKindOfClass:[NSArray class]])
        for (id o in obj)
            n += bpw_count_tree(o);
    else if ([obj isKindOfClass:[NSDictionary class]] && !is_uid(obj, NULL))
        for (id k in obj)
            n += 1 + bpw_count_tree([obj objectForKey:k]);
    return n;
}

static NSUInteger bpw_write(struct bpw *w, NSUInteger ref, uint64_t *offsets)
{
    id obj = [w->objects objectAtIndex:ref];
    NSMutableData *d = w->out;
    uint64_t uid;
    offsets[ref] = [d length];
    if ([obj isKindOfClass:[NSString class]]) {
        NSUInteger n = [obj length];
        BOOL ascii = YES;
        for (NSUInteger i = 0; i < n; i++)
            if ([obj characterAtIndex:i] >= 0x80)
                ascii = NO;
        if (ascii) {
            put_marker(d, 0x5, n);
            [d appendBytes:[obj UTF8String] length:n];
        } else {
            put_marker(d, 0x6, n);
            for (NSUInteger i = 0; i < n; i++)
                put_be(d, [obj characterAtIndex:i], 2);
        }
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        const char *t = [obj objCType];
        if (obj == (id)kCFBooleanTrue || obj == (id)kCFBooleanFalse) {
            unsigned char m = [obj boolValue] ? 0x09 : 0x08;
            [d appendBytes:&m length:1];
        } else if (*t == 'f' || *t == 'd') {
            unsigned char m = 0x23;
            union { double dv; uint64_t u; } c = {.dv = [obj doubleValue]};
            [d appendBytes:&m length:1];
            put_be(d, c.u, 8);
        } else {
            long long v = [obj longLongValue];
            int lg = v >= 0 && v < 256 ? 0 : v >= 0 && v < 65536 ? 1 : v >= 0 && v < 4294967296ll ? 2 : 3;
            unsigned char m = 0x10 | lg;
            [d appendBytes:&m length:1];
            put_be(d, (uint64_t)v, 1 << lg);
        }
    } else if ([obj isKindOfClass:[NSDate class]]) {
        unsigned char m = 0x33;
        union { double dv; uint64_t u; } c = {.dv = [obj timeIntervalSinceReferenceDate]};
        [d appendBytes:&m length:1];
        put_be(d, c.u, 8);
    } else if ([obj isKindOfClass:[NSData class]]) {
        put_marker(d, 0x4, [obj length]);
        [d appendData:obj];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        put_marker(d, 0xa, [obj count]);
        NSUInteger child = ref + 1;
        NSUInteger *refs = malloc(([obj count] + 1) * sizeof(NSUInteger));
        NSUInteger i = 0;
        for (id o in obj) {
            refs[i++] = child;
            child += bpw_count_tree(o);
        }
        for (i = 0; i < [obj count]; i++)
            put_be(d, refs[i], w->refsize);
        for (i = 0; i < [obj count]; i++)
            bpw_write(w, refs[i], offsets);
        free(refs);
    } else if (is_uid(obj, &uid)) {
        int n = uid < 256 ? 1 : uid < 65536 ? 2 : uid < 4294967296ull ? 4 : 8;
        unsigned char m = 0x80 | (n - 1);
        [d appendBytes:&m length:1];
        put_be(d, uid, n);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger n = [keys count], child = ref + 1;
        put_marker(d, 0xd, n);
        NSUInteger *refs = malloc((2 * n + 1) * sizeof(NSUInteger));
        for (NSUInteger i = 0; i < n; i++)
            refs[i] = child++;
        for (NSUInteger i = 0; i < n; i++) {
            refs[n + i] = child;
            child += bpw_count_tree([obj objectForKey:[keys objectAtIndex:i]]);
        }
        for (NSUInteger i = 0; i < 2 * n; i++)
            put_be(d, refs[i], w->refsize);
        for (NSUInteger i = 0; i < 2 * n; i++)
            bpw_write(w, refs[i], offsets);
        free(refs);
    }
    return ref;
}

static BOOL plist_ok(id obj)
{
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]] ||
        [obj isKindOfClass:[NSDate class]] || [obj isKindOfClass:[NSData class]])
        return YES;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id o in obj)
            if (!plist_ok(o))
                return NO;
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in obj)
            if (![k isKindOfClass:[NSString class]] || !plist_ok([obj objectForKey:k]))
                return NO;
        return YES;
    }
    return NO;
}

static NSData *write_binary(id plist)
{
    struct bpw w = {[NSMutableArray array], [NSMutableData data], 0};
    bpw_flatten(&w, plist);
    NSUInteger n = [w.objects count];
    w.refsize = n < 256 ? 1 : n < 65536 ? 2 : 4;
    uint64_t *offsets = calloc(n, sizeof(uint64_t));
    [w.out appendBytes:"bplist00" length:8];
    bpw_write(&w, 0, offsets);
    uint64_t table = [w.out length];
    int offsize = table < 256 ? 1 : table < 65536 ? 2 : table < 4294967296ull ? 4 : 8;
    for (NSUInteger i = 0; i < n; i++)
        put_be(w.out, offsets[i], offsize);
    free(offsets);
    unsigned char trailer[8] = {0, 0, 0, 0, 0, 0, (unsigned char)offsize, (unsigned char)w.refsize};
    [w.out appendBytes:trailer length:8];
    put_be(w.out, n, 8);
    put_be(w.out, 0, 8);
    put_be(w.out, table, 8);
    return w.out;
}

@implementation NSString (NSExtendedStringPropertyListParsing)
- (id)propertyList
{
    id v = FParsePlist([self dataUsingEncoding:NSUTF8StringEncoding], NSPropertyListImmutable, NULL);
    if (!v && [self length])
        [NSException raise:NSParseErrorException format:@"-[NSString propertyList]: the string isn't a property list"];
    return v;
}
- (NSDictionary *)propertyListFromStringsFileFormat
{
    id v = FParsePlist([self dataUsingEncoding:NSUTF8StringEncoding], NSPropertyListImmutable, NULL);
    return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}
@end

@implementation NSPropertyListSerialization
+ (id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt format:(NSPropertyListFormat *)format
                     error:(NSError **)error
{
    id v = FParsePlist(data, opt, format);
    if (!v)
        FSetError(error, format_error(@"The data couldn’t be read because it isn’t in the correct format."));
    return v;
}
+ (id)propertyListFromData:(NSData *)data mutabilityOption:(NSPropertyListMutabilityOptions)opt
                    format:(NSPropertyListFormat *)format errorDescription:(NSString **)errorString
{
    id v = FParsePlist(data, opt, format);
    if (!v && errorString)
        *errorString = @"The data couldn’t be read because it isn’t in the correct format.";
    return v;
}
+ (NSData *)dataWithPropertyList:(id)plist format:(NSPropertyListFormat)format options:(NSPropertyListWriteOptions)opt
                           error:(NSError **)error
{
    if (!plist_ok(plist)) {
        FSetError(error, format_error(@"Property list invalid for format"));
        return nil;
    }
    if (format == NSPropertyListBinaryFormat_v1_0)
        return write_binary(plist);
    if (format == NSPropertyListXMLFormat_v1_0)
        return FWriteXMLPlist(plist);
    FSetError(error, format_error(@"Property list format not supported for writing"));
    return nil;
}
+ (BOOL)propertyList:(id)plist isValidForFormat:(NSPropertyListFormat)format
{
    return format != NSPropertyListOpenStepFormat && plist_ok(plist);
}
@end
