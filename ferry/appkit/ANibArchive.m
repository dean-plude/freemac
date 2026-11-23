/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: reading nibs in the "NIBArchive" format, which is what
 * current versions of Xcode write when they compile a nib. It holds the
 * same objects and keys as a keyed archive, in a flatter binary form:
 *
 *   "NIBArchive", then ten little-endian 32-bit numbers: 1, 10, and the
 *   count and file offset of each of four tables (objects, keys, values,
 *   classes).
 *   Objects: a class index, the index of the object's first value and its
 *   number of values (each a variable-length number).
 *   Keys: a length and the key's UTF-8 bytes.
 *   Values: a key index, a type byte and the data. The types are 0 to 3
 *   integers of 1, 2, 4 and 8 bytes, 4 false, 5 true, 6 a float, 7 a
 *   double, 8 bytes (a length, then the bytes), 9 nil, and 10 a 32-bit
 *   object index.
 *   Classes: a length, a count of extra 32-bit numbers, those numbers,
 *   then the name with a closing NUL.
 *
 * The variable-length numbers hold seven bits a byte, lowest first, and the
 * byte with its top bit set is the last. Object 0 holds "IB.objectdata".
 * Strings and data keep their bytes under "NS.bytes", numbers "NS.intval"
 * or "NS.dblval", and arrays, sets and dictionaries list their elements
 * (dictionaries a key, then its value) under the empty-named key
 * "UINibEncoderEmptyKey" with "NSInlinedValue" set.
 *
 * Written from developers' published notes on the format and from the
 * layout of nib files shipped with open-source apps (their data only; no
 * Apple code was looked at or used). tests/appkit/make_nibs.py writes the
 * test file. */
#import "AInternal.h"

typedef struct {
    uint32_t key;
    uint8_t type;
    union {
        int64_t i;
        double d;
        uint32_t ref;
        struct {
            uint32_t off, len;
        } bytes;
    } u;
} AValue;

typedef struct {
    uint32_t cls, first, count;
} AObject;

enum { T_INT8, T_INT16, T_INT32, T_INT64, T_FALSE, T_TRUE, T_FLOAT, T_DOUBLE, T_DATA, T_NIL, T_OBJECT };
enum { UNSEEN, DECODING, DONE };

@implementation ANibArchive {
    NSData *_data;
    const uint8_t *_b;
    NSUInteger _len;
    AObject *_objects;
    AValue *_values;
    NSString **_keys;
    NSString **_classNames;
    uint32_t _nobjects, _nvalues, _nkeys, _nclasses;
    uint32_t **_fallbacks; /* per class: count, then class indexes */
    id *_decoded;
    uint8_t *_state;
    NSMutableArray *_stack; /* object indexes being decoded */
    NSDictionary *_keyIndex;
    BOOL _bad;
}

+ (BOOL)isNibArchive:(NSData *)data
{
    return [data length] >= 50 && !memcmp([data bytes], "NIBArchive", 10);
}

/* ---- reading the tables ---------------------------------------------------------------- */

static BOOL varint(const uint8_t *b, NSUInteger len, NSUInteger *p, uint32_t *out)
{
    uint64_t v = 0;
    for (int shift = 0; shift < 35; shift += 7) {
        if (*p >= len)
            return NO;
        uint8_t c = b[(*p)++];
        v |= (uint64_t)(c & 0x7f) << shift;
        if (c & 0x80) {
            if (v > UINT32_MAX)
                return NO;
            *out = (uint32_t)v;
            return YES;
        }
    }
    return NO;
}

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

- (BOOL)parse
{
    const uint8_t *b = _b;
    NSUInteger len = _len;
    uint32_t h[10];
    for (int i = 0; i < 10; i++)
        h[i] = le32(b + 10 + 4 * i);
    _nobjects = h[2];
    _nkeys = h[4];
    _nvalues = h[6];
    _nclasses = h[8];
    /* Every entry takes at least a byte, so a count can't pass the file's size. */
    for (int i = 2; i < 10; i += 2)
        if (h[i] > len || h[i + 1] > len)
            return NO;

    _objects = calloc(_nobjects ?: 1, sizeof *_objects);
    _values = calloc(_nvalues ?: 1, sizeof *_values);
    _keys = calloc(_nkeys ?: 1, sizeof *_keys);
    _classNames = calloc(_nclasses ?: 1, sizeof *_classNames);
    _fallbacks = calloc(_nclasses ?: 1, sizeof *_fallbacks);
    _decoded = calloc(_nobjects ?: 1, sizeof *_decoded);
    _state = calloc(_nobjects ?: 1, 1);

    NSUInteger p = h[3];
    for (uint32_t i = 0; i < _nobjects; i++) {
        AObject *o = &_objects[i];
        if (!varint(b, len, &p, &o->cls) || !varint(b, len, &p, &o->first) || !varint(b, len, &p, &o->count))
            return NO;
        if (o->cls >= _nclasses || o->first > _nvalues || o->count > _nvalues - o->first)
            return NO;
    }

    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    p = h[5];
    for (uint32_t i = 0; i < _nkeys; i++) {
        uint32_t n;
        if (!varint(b, len, &p, &n) || n > len - p)
            return NO;
        NSString *k = [[NSString alloc] initWithBytes:b + p length:n encoding:NSUTF8StringEncoding];
        if (!k)
            return NO;
        _keys[i] = k;
        if (![index objectForKey:k])
            [index setObject:[NSNumber numberWithUnsignedInt:i] forKey:k];
        p += n;
    }
    _keyIndex = [index copy];

    p = h[7];
    static const int sizes[] = {1, 2, 4, 8, 0, 0, 4, 8, -1, 0, 4};
    for (uint32_t i = 0; i < _nvalues; i++) {
        AValue *v = &_values[i];
        if (!varint(b, len, &p, &v->key) || v->key >= _nkeys || p >= len)
            return NO;
        v->type = b[p++];
        if (v->type > T_OBJECT)
            return NO;
        int size = sizes[v->type];
        if (size < 0) {
            uint32_t n;
            if (!varint(b, len, &p, &n) || n > len - p)
                return NO;
            v->u.bytes.off = (uint32_t)p;
            v->u.bytes.len = n;
            p += n;
            continue;
        }
        if ((NSUInteger)size > len - p)
            return NO;
        const uint8_t *d = b + p;
        switch (v->type) {
        case T_INT8: v->u.i = (int8_t)d[0]; break;
        case T_INT16: v->u.i = (int16_t)(d[0] | d[1] << 8); break;
        case T_INT32: v->u.i = (int32_t)le32(d); break;
        case T_INT64: v->u.i = (int64_t)((uint64_t)le32(d) | (uint64_t)le32(d + 4) << 32); break;
        case T_FALSE: v->u.i = 0; break;
        case T_TRUE: v->u.i = 1; break;
        case T_FLOAT: {
            uint32_t bits = le32(d);
            float f;
            memcpy(&f, &bits, 4);
            v->u.d = f;
            break;
        }
        case T_DOUBLE: {
            uint64_t bits = (uint64_t)le32(d) | (uint64_t)le32(d + 4) << 32;
            memcpy(&v->u.d, &bits, 8);
            break;
        }
        case T_OBJECT:
            v->u.ref = le32(d);
            if (v->u.ref >= _nobjects)
                return NO;
            break;
        }
        p += size;
    }

    p = h[9];
    for (uint32_t i = 0; i < _nclasses; i++) {
        uint32_t n, extra;
        if (!varint(b, len, &p, &n) || !varint(b, len, &p, &extra) || extra > (len - p) / 4)
            return NO;
        _fallbacks[i] = calloc(extra + 1, sizeof(uint32_t));
        _fallbacks[i][0] = extra;
        for (uint32_t j = 0; j < extra; j++)
            _fallbacks[i][j + 1] = le32(b + p + 4 * j);
        p += 4 * extra;
        if (n > len - p)
            return NO;
        NSUInteger nlen = n;
        while (nlen && b[p + nlen - 1] == 0)
            nlen--;
        _classNames[i] = [[NSString alloc] initWithBytes:b + p length:nlen encoding:NSUTF8StringEncoding];
        if (!_classNames[i])
            return NO;
        p += n;
    }
    return _nobjects > 0;
}

- (instancetype)initForReadingWithData:(NSData *)data
{
    if (!(self = [super init]))
        return nil;
    if (![ANibArchive isNibArchive:data]) {
        [self release];
        return nil;
    }
    _data = [data copy];
    _b = [_data bytes];
    _len = [_data length];
    _stack = [[NSMutableArray alloc] init];
    if (![self parse]) {
        fprintf(stderr, "ferry: this nib is damaged or in a NIBArchive form Ferry doesn't know\n");
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc
{
    for (uint32_t i = 0; i < _nkeys && _keys; i++)
        [_keys[i] release];
    for (uint32_t i = 0; i < _nclasses && _classNames; i++) {
        [_classNames[i] release];
        free(_fallbacks[i]);
    }
    for (uint32_t i = 0; i < _nobjects && _decoded; i++)
        [_decoded[i] release];
    free(_objects);
    free(_values);
    free(_keys);
    free(_classNames);
    free(_fallbacks);
    free(_decoded);
    free(_state);
    [_keyIndex release];
    [_stack release];
    [_data release];
    [super dealloc];
}

- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return NO; }

/* ---- looking up values --------------------------------------------------------------- */

- (AObject *)current
{
    NSNumber *n = [_stack lastObject];
    return &_objects[n ? [n unsignedIntValue] : 0];
}

static AValue *find_in(ANibArchive *self, AObject *o, NSString *key)
{
    NSNumber *k = [self->_keyIndex objectForKey:key];
    if (!k)
        return NULL;
    uint32_t ki = [k unsignedIntValue];
    for (uint32_t i = 0; i < o->count; i++)
        if (self->_values[o->first + i].key == ki)
            return &self->_values[o->first + i];
    return NULL;
}

- (AValue *)findValue:(NSString *)key { return find_in(self, [self current], key); }

- (NSData *)bytesOf:(AValue *)v
{
    return [NSData dataWithBytes:_b + v->u.bytes.off length:v->u.bytes.len];
}

- (id)objectFromValue:(AValue *)v
{
    if (!v)
        return nil;
    switch (v->type) {
    case T_OBJECT: return [self objectAt:v->u.ref];
    case T_DATA: return [self bytesOf:v];
    case T_NIL: return nil;
    case T_FALSE:
    case T_TRUE: return [NSNumber numberWithBool:v->type == T_TRUE];
    case T_FLOAT:
    case T_DOUBLE: return [NSNumber numberWithDouble:v->u.d];
    default: return [NSNumber numberWithLongLong:v->u.i];
    }
}

/* The values of an object under one key, in order (an array's elements). */
- (NSMutableArray *)all:(NSString *)key of:(AObject *)o keepingNulls:(BOOL)nulls
{
    NSMutableArray *a = [NSMutableArray array];
    NSNumber *k = [_keyIndex objectForKey:key];
    if (!k)
        return a;
    uint32_t ki = [k unsignedIntValue];
    for (uint32_t i = 0; i < o->count; i++) {
        AValue *v = &_values[o->first + i];
        if (v->key != ki)
            continue;
        id obj = [self objectFromValue:v];
        if (obj)
            [a addObject:obj];
        else if (nulls)
            [a addObject:[NSNull null]];
    }
    return a;
}

/* ---- making objects ---------------------------------------------------------------- */

static void warn_missing(NSString *name)
{
    static NSMutableSet *warned;
    /* Interface Builder's own records, which an app has no use for. */
    static NSString *const quiet[] = {@"IBClassReference", @"NSColorSpace", @"NSIBHelpConnector",
                                      @"NSAccessibilityConnector", nil};
    for (int i = 0; quiet[i]; i++)
        if ([name isEqualToString:quiet[i]])
            return;
    if (!warned)
        warned = [[NSMutableSet alloc] init];
    if ([warned containsObject:name])
        return;
    [warned addObject:name];
    fprintf(stderr, "ferry: a nib uses the class %s, which Ferry doesn't have yet; leaving it out\n",
            [name UTF8String]);
}

- (Class)classAtIndex:(uint32_t)ci
{
    Class cls = NSClassFromString(_classNames[ci]);
    for (uint32_t j = 1; !cls && j <= _fallbacks[ci][0]; j++) {
        uint32_t f = _fallbacks[ci][j];
        if (f < _nclasses)
            cls = NSClassFromString(_classNames[f]);
    }
    if (!cls)
        warn_missing(_classNames[ci]);
    return cls;
}

- (NSString *)stringOf:(AObject *)o
{
    AValue *v = find_in(self, o, @"NS.bytes");
    if (!v || v->type != T_DATA)
        return @"";
    NSString *s = [[NSString alloc] initWithBytes:_b + v->u.bytes.off length:v->u.bytes.len
                                         encoding:NSUTF8StringEncoding];
    return [s autorelease] ?: @"";
}

/* Strings, numbers, data and collections are made here; anything else by its
 * class's initWithCoder:. */
- (id)makeObject:(uint32_t)index class:(NSString *)name
{
    AObject *o = &_objects[index];
    if ([name isEqualToString:@"NSString"] || [name isEqualToString:@"NSLocalizableString"])
        return [[self stringOf:o] copy];
    if ([name isEqualToString:@"NSMutableString"])
        return [[self stringOf:o] mutableCopy];
    if ([name isEqualToString:@"NSData"] || [name isEqualToString:@"NSMutableData"]) {
        AValue *v = find_in(self, o, @"NS.bytes");
        NSData *d = v && v->type == T_DATA ? [self bytesOf:v] : [NSData data];
        return [name isEqualToString:@"NSData"] ? [d copy] : [d mutableCopy];
    }
    if ([name isEqualToString:@"NSNumber"]) {
        AValue *v = find_in(self, o, @"NS.intval") ?: find_in(self, o, @"NS.dblval");
        return [[self objectFromValue:v] ?: [NSNumber numberWithInt:0] retain];
    }
    BOOL inlined = find_in(self, o, @"NSInlinedValue") != NULL;
    if (inlined || find_in(self, o, @"UINibEncoderEmptyKey")) {
        NSMutableArray *items = [self all:@"UINibEncoderEmptyKey" of:o keepingNulls:NO];
        if ([name hasSuffix:@"Array"])
            return [name isEqualToString:@"NSArray"] ? [items copy] : [items retain];
        if ([name hasSuffix:@"Set"] && ![name hasSuffix:@"OrderedSet"])
            return [name isEqualToString:@"NSSet"] ? [[NSSet setWithArray:items] retain]
                                                   : [[NSMutableSet setWithArray:items] retain];
        if ([name hasSuffix:@"Dictionary"]) {
            NSMutableArray *all = [self all:@"UINibEncoderEmptyKey" of:o keepingNulls:YES];
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (NSUInteger i = 0; i + 1 < [all count]; i += 2) {
                id k = [all objectAtIndex:i], v = [all objectAtIndex:i + 1];
                if (k != [NSNull null] && v != [NSNull null])
                    [d setObject:v forKey:k];
            }
            return [name isEqualToString:@"NSDictionary"] ? [d copy] : [d retain];
        }
    }
    return (id)[NSNull null]; /* not one of these: decode it with its class */
}

- (id)objectAt:(uint32_t)index
{
    if (index >= _nobjects)
        return nil;
    if (_state[index] != UNSEEN)
        return _decoded[index]; /* an object still being made gets what was allocated */
    uint32_t ci = _objects[index].cls;
    NSString *name = _classNames[ci];
    id simple = [self makeObject:index class:name];
    if (simple != [NSNull null]) {
        _state[index] = DONE;
        _decoded[index] = simple;
        return simple;
    }
    Class cls = [self classAtIndex:ci];
    if (!cls) {
        _state[index] = DONE;
        return nil;
    }
    _state[index] = DECODING;
    id obj = [cls alloc];
    _decoded[index] = obj;
    [_stack addObject:[NSNumber numberWithUnsignedInt:index]];
    id made = [obj initWithCoder:self];
    [_stack removeLastObject];
    if (made) {
        id after = [made awakeAfterUsingCoder:self];
        if (after != made) {
            [after retain];
            [made release];
            made = after;
        }
    }
    _decoded[index] = made;
    _state[index] = DONE;
    return made;
}

/* ---- NSCoder ---------------------------------------------------------------------- */

- (BOOL)containsValueForKey:(NSString *)key { return [self findValue:key] != NULL; }

- (id)decodeObjectForKey:(NSString *)key
{
    if ([_stack count] == 0) {
        /* The top: the keys of object 0. */
        return [self objectFromValue:find_in(self, &_objects[0], key)];
    }
    AValue *v = [self findValue:key];
    if (!v && ([key isEqualToString:@"NS.objects"] || [key isEqualToString:@"NS.keys"])) {
        NSArray *a = [self all:@"UINibEncoderEmptyKey" of:[self current] keepingNulls:NO];
        return [a count] ? a : nil;
    }
    return [self objectFromValue:v];
}

- (id)decodeObjectOfClasses:(NSSet *)classes forKey:(NSString *)key { return [self decodeObjectForKey:key]; }
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key { return [self decodeObjectForKey:key]; }

- (NSArray *)_decodeArrayKeepingNullsForKey:(NSString *)key
{
    AValue *v = [self findValue:key];
    if (!v || v->type != T_OBJECT)
        return nil;
    AObject *o = &_objects[v->u.ref];
    if (!find_in(self, o, @"NSInlinedValue")) {
        id a = [self objectAt:v->u.ref];
        return [a isKindOfClass:[NSArray class]] ? a : nil;
    }
    return [self all:@"UINibEncoderEmptyKey" of:o keepingNulls:YES];
}

- (int64_t)decodeInt64ForKey:(NSString *)key
{
    AValue *v = [self findValue:key];
    if (!v)
        return 0;
    switch (v->type) {
    case T_FLOAT:
    case T_DOUBLE: return (int64_t)v->u.d;
    case T_INT8:
    case T_INT16:
    case T_INT32:
    case T_INT64:
    case T_FALSE:
    case T_TRUE: return v->u.i;
    case T_OBJECT: {
        id n = [self objectAt:v->u.ref];
        return [n isKindOfClass:[NSNumber class]] ? [n longLongValue] : 0;
    }
    default: return 0;
    }
}
- (BOOL)decodeBoolForKey:(NSString *)key { return [self decodeInt64ForKey:key] != 0; }
- (double)decodeDoubleForKey:(NSString *)key
{
    AValue *v = [self findValue:key];
    if (v && (v->type == T_FLOAT || v->type == T_DOUBLE))
        return v->u.d;
    if (v && v->type == T_OBJECT) {
        id n = [self objectAt:v->u.ref];
        return [n isKindOfClass:[NSNumber class]] ? [n doubleValue] : 0;
    }
    return (double)[self decodeInt64ForKey:key];
}
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length
{
    AValue *v = [self findValue:key];
    NSData *d = nil;
    if (v && v->type == T_DATA) {
        if (length)
            *length = v->u.bytes.len;
        return _b + v->u.bytes.off;
    }
    if (v && v->type == T_OBJECT)
        d = [self objectAt:v->u.ref];
    if (![d isKindOfClass:[NSData class]])
        d = nil;
    if (length)
        *length = [d length];
    return [d bytes];
}

/* Geometry is kept as strings ("{{x, y}, {w, h}}"), as in a keyed archive;
 * NSCoder's own decodeRectForKey: and its kin read those. */
@end
