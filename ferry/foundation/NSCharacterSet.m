/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSMutableCharacterSet, and the parts of NSCharacterSet
 * that NSString.m doesn't have (the other predefined sets, the URL sets,
 * ranges, bitmaps, supersets and planes), with NSString's percent encoding.
 *
 * NSString.m keeps the first predefined sets as tests on a character. The
 * sets made here are bitmaps of all seventeen Unicode planes, a plane being
 * made only when it has a member, in the layout Apple documents for
 * bitmapRepresentation: one bit a character, the low bit of each byte first.
 * The Unicode categories of the further predefined sets come from this
 * system's ICU (u_charType), reached through ferry_twin_symbol the first
 * time one is asked for, and from a few Latin rules when ICU isn't there.
 *
 * Written from Apple's public documentation of these classes, ICU's of its
 * C interface (uchar.h) and RFC 3986 for the URL sets; no Apple code was
 * used. */
#import "FInternal.h"
#import <Foundation/NSCharacterSet.h>

void *ferry_twin_symbol(const char *install_name, const char *name);

#define PLANES 17
#define PLANE_BYTES 8192
#define LAST_CHAR 0x10FFFF

typedef struct {
    uint8_t *p[PLANES];
} bits;

static BOOL bits_has(const bits *b, uint32_t c)
{
    if (c > LAST_CHAR)
        return NO;
    const uint8_t *p = b->p[c >> 16];
    return p && ((p[(c & 0xffff) >> 3] >> (c & 7)) & 1);
}

static uint8_t *plane_of(bits *b, unsigned i)
{
    if (!b->p[i])
        b->p[i] = calloc(1, PLANE_BYTES);
    return b->p[i];
}

static void bits_set(bits *b, uint32_t c, BOOL on)
{
    if (c > LAST_CHAR || (!on && !b->p[c >> 16]))
        return;
    uint8_t *p = plane_of(b, c >> 16);
    if (on)
        p[(c & 0xffff) >> 3] |= (uint8_t)(1 << (c & 7));
    else
        p[(c & 0xffff) >> 3] &= (uint8_t)~(1 << (c & 7));
}

static void bits_range(bits *b, uint64_t lo, uint64_t n, BOOL on)
{
    uint64_t end = lo + n;
    if (end > LAST_CHAR + 1)
        end = LAST_CHAR + 1;
    for (uint64_t c = lo; c < end;) {
        if (!on && !b->p[c >> 16]) {
            c = ((c >> 16) + 1) << 16;
            continue;
        }
        if ((c & 7) == 0 && c + 8 <= end) {
            plane_of(b, (unsigned)(c >> 16))[(c & 0xffff) >> 3] = on ? 0xff : 0;
            c += 8;
        } else
            bits_set(b, (uint32_t)c++, on);
    }
}

static void bits_free(bits *b)
{
    for (int i = 0; i < PLANES; i++) {
        free(b->p[i]);
        b->p[i] = NULL;
    }
}

static void bits_copy(bits *to, const bits *from)
{
    bits_free(to);
    for (int i = 0; i < PLANES; i++)
        if (from->p[i]) {
            to->p[i] = malloc(PLANE_BYTES);
            memcpy(to->p[i], from->p[i], PLANE_BYTES);
        }
}

static void bits_invert(bits *b)
{
    for (int i = 0; i < PLANES; i++) {
        uint8_t *p = plane_of(b, i);
        for (int k = 0; k < PLANE_BYTES; k++)
            p[k] = (uint8_t)~p[k];
    }
}

static BOOL plane_empty(const uint8_t *p)
{
    if (!p)
        return YES;
    for (int k = 0; k < PLANE_BYTES; k++)
        if (p[k])
            return NO;
    return YES;
}

/* ---- the two bitmap classes -------------------------------------------------------------- */

@interface FBitmapCharacterSet : NSCharacterSet {
@public
    bits _b;
}
@end

@interface NSCharacterSet (FBits)
- (const bits *)_ferryBits;
@end

static void bits_from(NSCharacterSet *s, bits *out);

static FBitmapCharacterSet *bitmap_set(bits *taken) /* takes the planes; autoreleased */
{
    FBitmapCharacterSet *s = [[FBitmapCharacterSet alloc] init];
    s->_b = *taken;
    memset(taken, 0, sizeof *taken);
    return [s autorelease];
}

/* What the two share: membership, copies and the inverted set. */
#define BITMAP_METHODS                                                                                      \
    -(const bits *)_ferryBits { return &_b; }                                                               \
    -(BOOL)characterIsMember : (unichar)c { return bits_has(&_b, c); }                                     \
    -(BOOL)longCharacterIsMember : (UTF32Char)c { return bits_has(&_b, c); }                               \
    -(NSCharacterSet *)invertedSet                                                                          \
    {                                                                                                       \
        bits b = {{0}};                                                                                     \
        bits_copy(&b, &_b);                                                                                 \
        bits_invert(&b);                                                                                    \
        return bitmap_set(&b);                                                                              \
    }                                                                                                       \
    -(void)dealloc                                                                                          \
    {                                                                                                       \
        bits_free(&_b);                                                                                     \
        [super dealloc];                                                                                    \
    }

@implementation FBitmapCharacterSet
BITMAP_METHODS
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

@implementation NSMutableCharacterSet {
    bits _b;
}
BITMAP_METHODS
- (id)copyWithZone:(NSZone *)zone
{
    bits b = {{0}};
    bits_copy(&b, &_b);
    return [bitmap_set(&b) retain];
}
- (void)addCharactersInRange:(NSRange)range { bits_range(&_b, range.location, range.length, YES); }
- (void)removeCharactersInRange:(NSRange)range { bits_range(&_b, range.location, range.length, NO); }
static void each_character(NSString *s, void (^f)(uint32_t))
{
    NSUInteger n = [s length];
    unichar *c = malloc((n + 1) * sizeof(unichar));
    [s getCharacters:c range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i < n; i++) {
        uint32_t u = c[i];
        if (u >= 0xD800 && u < 0xDC00 && i + 1 < n && c[i + 1] >= 0xDC00 && c[i + 1] < 0xE000)
            u = 0x10000 + ((u - 0xD800) << 10) + (c[++i] - 0xDC00);
        f(u);
    }
    free(c);
}
- (void)addCharactersInString:(NSString *)s
{
    each_character(s, ^(uint32_t u) { bits_set(&_b, u, YES); });
}
- (void)removeCharactersInString:(NSString *)s
{
    each_character(s, ^(uint32_t u) { bits_set(&_b, u, NO); });
}
- (void)formUnionWithCharacterSet:(NSCharacterSet *)other
{
    bits o = {{0}};
    bits_from(other, &o);
    for (int i = 0; i < PLANES; i++)
        if (o.p[i]) {
            uint8_t *p = plane_of(&_b, i);
            for (int k = 0; k < PLANE_BYTES; k++)
                p[k] |= o.p[i][k];
        }
    bits_free(&o);
}
- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)other
{
    bits o = {{0}};
    bits_from(other, &o);
    for (int i = 0; i < PLANES; i++) {
        if (!_b.p[i])
            continue;
        if (!o.p[i]) {
            free(_b.p[i]);
            _b.p[i] = NULL;
            continue;
        }
        for (int k = 0; k < PLANE_BYTES; k++)
            _b.p[i][k] &= o.p[i][k];
    }
    bits_free(&o);
}
- (void)invert { bits_invert(&_b); }

/* The class's own makers answer mutable sets. */
+ (instancetype)characterSetWithCharactersInString:(NSString *)s
{
    NSMutableCharacterSet *m = [[self alloc] init];
    [m addCharactersInString:s];
    return [m autorelease];
}
+ (instancetype)characterSetWithRange:(NSRange)range
{
    NSMutableCharacterSet *m = [[self alloc] init];
    [m addCharactersInRange:range];
    return [m autorelease];
}
+ (instancetype)_ferryMutableFrom:(NSCharacterSet *)s
{
    NSMutableCharacterSet *m = [[self alloc] init];
    if (s)
        bits_from(s, &m->_b);
    return [m autorelease];
}
+ (instancetype)characterSetWithBitmapRepresentation:(NSData *)data
{
    return [self _ferryMutableFrom:[NSCharacterSet characterSetWithBitmapRepresentation:data]];
}
+ (instancetype)characterSetWithContentsOfFile:(NSString *)path
{
    NSCharacterSet *s = [NSCharacterSet characterSetWithContentsOfFile:path];
    return s ? [self _ferryMutableFrom:s] : nil;
}
#define MUTABLE_MAKER(name)                                                                                 \
    +(NSMutableCharacterSet *)name { return [self _ferryMutableFrom:[NSCharacterSet name]]; }
MUTABLE_MAKER(whitespaceCharacterSet)
MUTABLE_MAKER(whitespaceAndNewlineCharacterSet)
MUTABLE_MAKER(newlineCharacterSet)
MUTABLE_MAKER(decimalDigitCharacterSet)
MUTABLE_MAKER(letterCharacterSet)
MUTABLE_MAKER(alphanumericCharacterSet)
MUTABLE_MAKER(punctuationCharacterSet)
MUTABLE_MAKER(controlCharacterSet)
MUTABLE_MAKER(uppercaseLetterCharacterSet)
MUTABLE_MAKER(lowercaseLetterCharacterSet)
MUTABLE_MAKER(capitalizedLetterCharacterSet)
MUTABLE_MAKER(nonBaseCharacterSet)
MUTABLE_MAKER(decomposableCharacterSet)
MUTABLE_MAKER(illegalCharacterSet)
MUTABLE_MAKER(symbolCharacterSet)
MUTABLE_MAKER(URLUserAllowedCharacterSet)
MUTABLE_MAKER(URLPasswordAllowedCharacterSet)
MUTABLE_MAKER(URLHostAllowedCharacterSet)
MUTABLE_MAKER(URLPathAllowedCharacterSet)
MUTABLE_MAKER(URLQueryAllowedCharacterSet)
MUTABLE_MAKER(URLFragmentAllowedCharacterSet)
@end

/* ---- any set as a bitmap ----------------------------------------------------------------- */

static IMP base_long_member;

/* NSString.m's sets answer only characterIsMember:, for the Basic
 * Multilingual Plane. None of their tests holds U+FFFF, which isn't a
 * character, so a set holding it is an inverted one, which holds every
 * character of the further planes too. */
static void bits_from(NSCharacterSet *s, bits *out)
{
    bits_free(out);
    if ([s respondsToSelector:@selector(_ferryBits)]) {
        bits_copy(out, [s _ferryBits]);
        return;
    }
    for (uint32_t c = 0; c < 0x10000; c++)
        if ([s characterIsMember:(unichar)c])
            bits_set(out, c, YES);
    if ([s methodForSelector:@selector(longCharacterIsMember:)] == base_long_member) {
        if ([s characterIsMember:0xFFFF])
            bits_range(out, 0x10000, LAST_CHAR + 1 - 0x10000, YES);
    } else
        for (uint32_t c = 0x10000; c <= LAST_CHAR; c++)
            if ([s longCharacterIsMember:c])
                bits_set(out, c, YES);
}

/* ---- the predefined sets made here ------------------------------------------------------- */

enum { CONTROL, UPPER, LOWER, TITLE, NONBASE, DECOMPOSABLE, ILLEGAL, SYMBOL, KINDS };

/* ICU's general categories (UCharCategory) */
enum {
    U_UNASSIGNED = 0, U_UPPERCASE_LETTER = 1, U_LOWERCASE_LETTER = 2, U_TITLECASE_LETTER = 3,
    U_NON_SPACING_MARK = 6, U_ENCLOSING_MARK = 7, U_COMBINING_SPACING_MARK = 8, U_CONTROL_CHAR = 15,
    U_FORMAT_CHAR = 16, U_MATH_SYMBOL = 24, U_CURRENCY_SYMBOL = 25, U_MODIFIER_SYMBOL = 26, U_OTHER_SYMBOL = 27,
};
enum { UCHAR_DECOMPOSITION_TYPE = 0x1003, U_DT_CANONICAL = 1 };

static struct {
    BOOL tried;
    int8_t (*charType)(int32_t);
    int32_t (*intProperty)(int32_t, int);
} icu;

static BOOL load_icu(void)
{
    if (!icu.tried) {
        icu.tried = YES;
        const char *lib = "/usr/lib/libicucore.A.dylib";
        *(void **)&icu.charType = ferry_twin_symbol(lib, "u_charType");
        *(void **)&icu.intProperty = ferry_twin_symbol(lib, "u_getIntPropertyValue");
    }
    return icu.charType && icu.intProperty;
}

static BOOL icu_test(int kind, uint32_t c)
{
    int t = icu.charType((int32_t)c);
    switch (kind) {
    case CONTROL: return t == U_CONTROL_CHAR || t == U_FORMAT_CHAR;
    case UPPER: return t == U_UPPERCASE_LETTER || t == U_TITLECASE_LETTER;
    case LOWER: return t == U_LOWERCASE_LETTER;
    case TITLE: return t == U_TITLECASE_LETTER;
    case NONBASE: return t == U_NON_SPACING_MARK || t == U_ENCLOSING_MARK || t == U_COMBINING_SPACING_MARK;
    case DECOMPOSABLE: return icu.intProperty((int32_t)c, UCHAR_DECOMPOSITION_TYPE) == U_DT_CANONICAL;
    case ILLEGAL: return t == U_UNASSIGNED;
    case SYMBOL: return t >= U_MATH_SYMBOL && t <= U_OTHER_SYMBOL;
    }
    return NO;
}

/* Without ICU: the Latin letters and the commonest marks and signs. */
static BOOL latin_test(int kind, uint32_t c)
{
    BOOL latin_upper = (c >= 'A' && c <= 'Z') || (c >= 0xC0 && c <= 0xDE && c != 0xD7);
    BOOL latin_lower = (c >= 'a' && c <= 'z') || (c >= 0xDF && c <= 0xFF && c != 0xF7) || c == 0xB5;
    switch (kind) {
    case CONTROL:
        return c < 0x20 || (c >= 0x7F && c <= 0x9F) || c == 0xAD || (c >= 0x200B && c <= 0x200F) ||
               (c >= 0x202A && c <= 0x202E) || (c >= 0x2060 && c <= 0x2064) || c == 0xFEFF;
    case UPPER: return latin_upper || c == 0x1C5 || c == 0x1C8 || c == 0x1CB || c == 0x1F2;
    case LOWER: return latin_lower;
    case TITLE: return c == 0x1C5 || c == 0x1C8 || c == 0x1CB || c == 0x1F2;
    case NONBASE:
        return (c >= 0x300 && c <= 0x36F) || (c >= 0x1AB0 && c <= 0x1AFF) || (c >= 0x1DC0 && c <= 0x1DFF) ||
               (c >= 0x20D0 && c <= 0x20FF) || (c >= 0xFE20 && c <= 0xFE2F);
    case DECOMPOSABLE:
        return (latin_upper || latin_lower) && c >= 0xC0 && !strchr("\xC6\xD0\xD8\xDE\xDF\xE6\xF0\xF8\xFE", (int)c);
    case ILLEGAL: return (c & 0xFFFE) == 0xFFFE || (c >= 0xFDD0 && c <= 0xFDEF);
    case SYMBOL:
        return (c < 0x80 && c && strchr("$+<=>^`|~", (int)c)) || (c >= 0xA2 && c <= 0xA9 && c != 0xA7) || c == 0xAC ||
               (c >= 0xAE && c <= 0xB1) || c == 0xB4 || c == 0xB8 || c == 0xD7 || c == 0xF7 ||
               (c >= 0x2190 && c <= 0x23FF) || (c >= 0x20A0 && c <= 0x20CF);
    }
    return NO;
}

static NSCharacterSet *predefined(int kind)
{
    static NSCharacterSet *made[KINDS];
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    if (!made[kind]) {
        BOOL with_icu = load_icu();
        bits b = {{0}};
        for (uint32_t c = 0; c <= LAST_CHAR; c++)
            if (with_icu ? icu_test(kind, c) : latin_test(kind, c))
                bits_set(&b, c, YES);
        made[kind] = [bitmap_set(&b) retain];
    }
    NSCharacterSet *s = made[kind];
    os_unfair_lock_unlock(&lock);
    return s;
}

/* RFC 3986: the unreserved characters, then what each part may also hold. */
static NSCharacterSet *url_set(int which)
{
    static NSCharacterSet *made[6];
    static const char *const extra[6] = {
        "!$&'()*+,;=",        /* user */
        "!$&'()*+,;=",        /* password */
        "!$&'()*+,;=:[]",     /* host */
        "!$&'()*+,=:@/",      /* path */
        "!$&'()*+,;=:@/?",    /* query */
        "!$&'()*+,;=:@/?",    /* fragment */
    };
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    if (!made[which]) {
        bits b = {{0}};
        bits_range(&b, 'A', 26, YES);
        bits_range(&b, 'a', 26, YES);
        bits_range(&b, '0', 10, YES);
        for (const char *p = "-._~"; *p; p++)
            bits_set(&b, (uint8_t)*p, YES);
        for (const char *p = extra[which]; *p; p++)
            bits_set(&b, (uint8_t)*p, YES);
        made[which] = [bitmap_set(&b) retain];
    }
    NSCharacterSet *s = made[which];
    os_unfair_lock_unlock(&lock);
    return s;
}

@implementation NSCharacterSet (NSCharacterSetMore)
+ (void)load
{
    base_long_member = [NSCharacterSet instanceMethodForSelector:@selector(longCharacterIsMember:)];
}
+ (NSCharacterSet *)controlCharacterSet { return predefined(CONTROL); }
+ (NSCharacterSet *)uppercaseLetterCharacterSet { return predefined(UPPER); }
+ (NSCharacterSet *)lowercaseLetterCharacterSet { return predefined(LOWER); }
+ (NSCharacterSet *)capitalizedLetterCharacterSet { return predefined(TITLE); }
+ (NSCharacterSet *)nonBaseCharacterSet { return predefined(NONBASE); }
+ (NSCharacterSet *)decomposableCharacterSet { return predefined(DECOMPOSABLE); }
+ (NSCharacterSet *)illegalCharacterSet { return predefined(ILLEGAL); }
+ (NSCharacterSet *)symbolCharacterSet { return predefined(SYMBOL); }
+ (NSCharacterSet *)URLUserAllowedCharacterSet { return url_set(0); }
+ (NSCharacterSet *)URLPasswordAllowedCharacterSet { return url_set(1); }
+ (NSCharacterSet *)URLHostAllowedCharacterSet { return url_set(2); }
+ (NSCharacterSet *)URLPathAllowedCharacterSet { return url_set(3); }
+ (NSCharacterSet *)URLQueryAllowedCharacterSet { return url_set(4); }
+ (NSCharacterSet *)URLFragmentAllowedCharacterSet { return url_set(5); }
+ (NSCharacterSet *)characterSetWithRange:(NSRange)range
{
    bits b = {{0}};
    bits_range(&b, range.location, range.length, YES);
    return bitmap_set(&b);
}
+ (NSCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)data
{
    bits b = {{0}};
    const uint8_t *d = [data bytes];
    NSUInteger n = [data length];
    if (n) {
        NSUInteger first = n < PLANE_BYTES ? n : PLANE_BYTES;
        memcpy(plane_of(&b, 0), d, first);
        for (NSUInteger at = PLANE_BYTES; at + 1 + PLANE_BYTES <= n; at += 1 + PLANE_BYTES)
            if (d[at] > 0 && d[at] < PLANES)
                memcpy(plane_of(&b, d[at]), d + at + 1, PLANE_BYTES);
    }
    return bitmap_set(&b);
}
+ (NSCharacterSet *)characterSetWithContentsOfFile:(NSString *)path
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? [self characterSetWithBitmapRepresentation:d] : nil;
}
- (BOOL)longCharacterIsMember:(UTF32Char)c
{
    if (c < 0x10000)
        return [self characterIsMember:(unichar)c];
    return c <= LAST_CHAR && [self characterIsMember:0xFFFF];
}
- (BOOL)isSupersetOfSet:(NSCharacterSet *)other
{
    bits me = {{0}}, o = {{0}};
    bits_from(self, &me);
    bits_from(other, &o);
    BOOL yes = YES;
    for (int i = 0; i < PLANES && yes; i++)
        if (o.p[i])
            for (int k = 0; k < PLANE_BYTES && yes; k++)
                yes = !(o.p[i][k] & ~(me.p[i] ? me.p[i][k] : 0));
    bits_free(&me);
    bits_free(&o);
    return yes;
}
- (BOOL)hasMemberInPlane:(uint8_t)plane
{
    if (plane >= PLANES)
        return NO;
    if ([self respondsToSelector:@selector(_ferryBits)])
        return !plane_empty([self _ferryBits]->p[plane]);
    bits b = {{0}};
    bits_from(self, &b);
    BOOL yes = !plane_empty(b.p[plane]);
    bits_free(&b);
    return yes;
}
- (NSData *)bitmapRepresentation
{
    bits b = {{0}};
    bits_from(self, &b);
    NSMutableData *d = [NSMutableData dataWithLength:PLANE_BYTES];
    if (b.p[0])
        memcpy([d mutableBytes], b.p[0], PLANE_BYTES);
    for (int i = 1; i < PLANES; i++)
        if (!plane_empty(b.p[i])) {
            uint8_t index = (uint8_t)i;
            [d appendBytes:&index length:1];
            [d appendBytes:b.p[i] length:PLANE_BYTES];
        }
    bits_free(&b);
    return d;
}
- (id)mutableCopyWithZone:(NSZone *)zone
{
    return [[NSMutableCharacterSet _ferryMutableFrom:self] retain];
}
- (id)mutableCopy
{
    return [self mutableCopyWithZone:NULL];
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSCharacterSet class]])
        return NO;
    return [[self bitmapRepresentation] isEqual:[other bitmapRepresentation]];
}
- (NSUInteger)hash
{
    NSUInteger h = 0;
    for (uint32_t c = 0; c < 0x100; c++)
        h = h * 31 + [self characterIsMember:(unichar)c];
    return h;
}
@end

/* ---- percent encoding -------------------------------------------------------------------- */

@implementation NSString (NSCharacterSetPercentEncoding)
- (NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)allowed
{
    NSUInteger n = [self length];
    unichar *c = malloc((n + 1) * sizeof(unichar));
    [self getCharacters:c range:NSMakeRange(0, n)];
    NSMutableString *out = [NSMutableString stringWithCapacity:n];
    BOOL ok = YES;
    for (NSUInteger i = 0; i < n && ok; i++) {
        uint32_t u = c[i];
        NSUInteger units = 1;
        if (u >= 0xD800 && u < 0xDC00) {
            if (i + 1 < n && c[i + 1] >= 0xDC00 && c[i + 1] < 0xE000) {
                u = 0x10000 + ((u - 0xD800) << 10) + (c[i + 1] - 0xDC00);
                units = 2;
            } else
                ok = NO;
        } else if (u >= 0xDC00 && u < 0xE000)
            ok = NO;
        if (!ok)
            break;
        if ([allowed longCharacterIsMember:u]) {
            [out appendString:FStringFromChars(c + i, units)];
        } else {
            uint8_t b[4];
            int k;
            if (u < 0x80)
                b[0] = (uint8_t)u, k = 1;
            else if (u < 0x800)
                b[0] = (uint8_t)(0xC0 | (u >> 6)), b[1] = (uint8_t)(0x80 | (u & 0x3F)), k = 2;
            else if (u < 0x10000)
                b[0] = (uint8_t)(0xE0 | (u >> 12)), b[1] = (uint8_t)(0x80 | ((u >> 6) & 0x3F)),
                b[2] = (uint8_t)(0x80 | (u & 0x3F)), k = 3;
            else
                b[0] = (uint8_t)(0xF0 | (u >> 18)), b[1] = (uint8_t)(0x80 | ((u >> 12) & 0x3F)),
                b[2] = (uint8_t)(0x80 | ((u >> 6) & 0x3F)), b[3] = (uint8_t)(0x80 | (u & 0x3F)), k = 4;
            for (int j = 0; j < k; j++)
                [out appendFormat:@"%%%02X", b[j]];
        }
        i += units - 1;
    }
    free(c);
    return ok ? [[out copy] autorelease] : nil;
}

static int hex_value(unichar h)
{
    if (h >= '0' && h <= '9')
        return h - '0';
    if (h >= 'a' && h <= 'f')
        return h - 'a' + 10;
    if (h >= 'A' && h <= 'F')
        return h - 'A' + 10;
    return -1;
}

/* The decoded bytes must be UTF-8, or the answer is nil. */
- (NSString *)stringByRemovingPercentEncoding
{
    NSUInteger n = [self length];
    unichar *c = malloc((n + 1) * sizeof(unichar));
    [self getCharacters:c range:NSMakeRange(0, n)];
    unichar *out = malloc((n + 1) * sizeof(unichar));
    NSUInteger o = 0;
    BOOL ok = YES;
    for (NSUInteger i = 0; i < n && ok;) {
        if (c[i] != '%') {
            out[o++] = c[i++];
            continue;
        }
        /* a run of escapes, read as UTF-8 */
        uint8_t bytes[4];
        int want = 0, have = 0;
        do {
            int hi, lo;
            if (i + 2 >= n || (hi = hex_value(c[i + 1])) < 0 || (lo = hex_value(c[i + 2])) < 0) {
                ok = NO;
                break;
            }
            uint8_t b = (uint8_t)(hi << 4 | lo);
            i += 3;
            if (!have) {
                want = b < 0x80 ? 1 : (b & 0xE0) == 0xC0 ? 2 : (b & 0xF0) == 0xE0 ? 3 : (b & 0xF8) == 0xF0 ? 4 : 0;
                if (!want || b == 0xC0 || b == 0xC1) {
                    ok = NO;
                    break;
                }
            } else if ((b & 0xC0) != 0x80) {
                ok = NO;
                break;
            }
            bytes[have++] = b;
        } while (have < want && i < n && c[i] == '%');
        if (!ok)
            break;
        if (have < want) {
            ok = NO;
            break;
        }
        uint32_t u = want == 1 ? bytes[0]
                   : want == 2 ? (uint32_t)(bytes[0] & 0x1F) << 6 | (bytes[1] & 0x3F)
                   : want == 3 ? (uint32_t)(bytes[0] & 0x0F) << 12 | (uint32_t)(bytes[1] & 0x3F) << 6 | (bytes[2] & 0x3F)
                               : (uint32_t)(bytes[0] & 0x07) << 18 | (uint32_t)(bytes[1] & 0x3F) << 12 |
                                     (uint32_t)(bytes[2] & 0x3F) << 6 | (bytes[3] & 0x3F);
        if ((want == 2 && u < 0x80) || (want == 3 && u < 0x800) || (want == 4 && (u < 0x10000 || u > LAST_CHAR)) ||
            (u >= 0xD800 && u < 0xE000)) {
            ok = NO;
            break;
        }
        if (u >= 0x10000) {
            out[o++] = (unichar)(0xD800 + ((u - 0x10000) >> 10));
            out[o++] = (unichar)(0xDC00 + ((u - 0x10000) & 0x3FF));
        } else
            out[o++] = (unichar)u;
    }
    NSString *s = ok ? FStringFromChars(out, o) : nil;
    free(c);
    free(out);
    return s;
}
@end
