/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSValue and NSNumber. A number remembers the C type it
 * was made from (its objCType) and compares by value, as on a Mac. The two
 * booleans are shared objects, which CoreFoundation also hands out as
 * kCFBooleanTrue and kCFBooleanFalse. */
#import "FInternal.h"

@interface FValue : NSValue {
@public
    char _kind; /* 'r' range, 'p' pointer, 'P' point, 'S' size, 'R' rect, 'E' edge insets,
                 * 'B' any other bytes, of the type in _type */
    NSRange _range;
    void *_bytes;
    NSUInteger _size;
    char *_type;
    void *_ptr;
    NSRect _rect;           /* a point or size is kept in its first half */
    NSEdgeInsets _insets;
}
@end

@interface FNumber : NSNumber {
@public
    char _type; /* an @encode letter: c C s S i I q Q f d, or B for the booleans */
    union {
        long long i;
        unsigned long long u;
        double d;
    } _v;
}
@end

static FNumber *yes_number, *no_number;

/* A number that newer clang writes into the program itself for a literal
 * such as @3, as an object of the class NSConstantIntegerNumber: the class,
 * then the @encode letters of the literal's type, then its value. Qt and
 * OBS's plugins in OBS's own download hold these (freemac 1.263). */
@interface NSConstantIntegerNumber : NSNumber
@end

/* The fields sit right after the class pointer, where the program put
 * them; Ferry's own objects keep more there, so they are read by hand. */
struct constant_number {
    Class isa;
    const char *encoding;
    long long value;
};
#define LITERAL(n) ((const struct constant_number *)(const void *)(n))
static id ferry_plain_number(id n);

F_EXPORT CFBooleanRef ferry_true __asm__("_kCFBooleanTrue");
F_EXPORT CFBooleanRef ferry_false __asm__("_kCFBooleanFalse");
CFBooleanRef ferry_true, ferry_false;

@implementation NSValue
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSValue class])
        return [FValue allocWithZone:zone];
    return [super allocWithZone:zone];
}
+ (NSValue *)valueWithRange:(NSRange)range
{
    FValue *v = [[FValue alloc] init];
    v->_kind = 'r';
    v->_range = range;
    return [v autorelease];
}
+ (NSValue *)valueWithPointer:(const void *)pointer
{
    FValue *v = [[FValue alloc] init];
    v->_kind = 'p';
    v->_ptr = (void *)pointer;
    return [v autorelease];
}
/* A pointer to an object that the value doesn't retain. */
+ (NSValue *)valueWithNonretainedObject:(id)object
{
    FValue *v = [[FValue alloc] init];
    v->_kind = 'o';
    v->_ptr = object;
    return [v autorelease];
}
static NSValue *geometry_value(char kind, NSRect rect)
{
    FValue *v = [[FValue alloc] init];
    v->_kind = kind;
    v->_rect = rect;
    return [v autorelease];
}
+ (NSValue *)valueWithPoint:(NSPoint)p { return geometry_value('P', NSMakeRect(p.x, p.y, 0, 0)); }
+ (NSValue *)valueWithSize:(NSSize)s { return geometry_value('S', NSMakeRect(s.width, s.height, 0, 0)); }
+ (NSValue *)valueWithRect:(NSRect)r { return geometry_value('R', r); }
+ (NSValue *)valueWithEdgeInsets:(NSEdgeInsets)e
{
    FValue *v = [[FValue alloc] init];
    v->_kind = 'E';
    v->_insets = e;
    return [v autorelease];
}
/* Any value of a C type, kept as its bytes (freemac 1.225, Ferry 0.49.0); a
 * range, point, size, rect, edge insets, pointer or object is kept as the
 * value its own call makes, so that rangeValue and the rest answer it. */
- (instancetype)initWithBytes:(const void *)value objCType:(const char *)type
{
    [self release];
    return [[NSValue valueWithBytes:value objCType:type] retain];
}
+ (NSValue *)valueWithBytes:(const void *)value objCType:(const char *)type
{
    if (!type)
        FRaise(NSInvalidArgumentException, @"+[NSValue valueWithBytes:objCType:]: no type");
    if (!strcmp(type, @encode(NSRange)))
        return [self valueWithRange:*(const NSRange *)value];
    if (!strcmp(type, @encode(NSPoint)))
        return [self valueWithPoint:*(const NSPoint *)value];
    if (!strcmp(type, @encode(NSSize)))
        return [self valueWithSize:*(const NSSize *)value];
    if (!strcmp(type, @encode(NSRect)))
        return [self valueWithRect:*(const NSRect *)value];
    if (!strcmp(type, @encode(NSEdgeInsets)))
        return [self valueWithEdgeInsets:*(const NSEdgeInsets *)value];
    if (!strcmp(type, @encode(void *)))
        return [self valueWithPointer:*(void *const *)value];
    if (!strcmp(type, @encode(id)))
        return [self valueWithNonretainedObject:*(const id *)value];
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    FValue *v = [[FValue alloc] init];
    v->_kind = 'B';
    v->_size = size;
    v->_bytes = malloc(size ? size : 1);
    memcpy(v->_bytes, value, size);
    v->_type = strdup(type);
    return [v autorelease];
}
+ (NSValue *)value:(const void *)value withObjCType:(const char *)type
{
    return [self valueWithBytes:value objCType:type];
}
- (void)getValue:(void *)value { }
- (void)getValue:(void *)value size:(NSUInteger)size
{
    NSUInteger have = 0;
    NSGetSizeAndAlignment([self objCType], &have, NULL);
    if (size != have)
        FRaise(NSInvalidArgumentException, @"-[NSValue getValue:size:]: %lu bytes asked, the value has %lu",
               (unsigned long)size, (unsigned long)have);
    [self getValue:value];
}
- (BOOL)isEqualToValue:(NSValue *)value { return [self isEqual:value]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSRange)rangeValue { return NSMakeRange(0, 0); }
- (void *)pointerValue { return NULL; }
- (id)nonretainedObjectValue { return (id)[self pointerValue]; }
- (NSPoint)pointValue { return NSZeroPoint; }
- (NSSize)sizeValue { return NSZeroSize; }
- (NSRect)rectValue { return NSZeroRect; }
- (NSEdgeInsets)edgeInsetsValue { return NSEdgeInsetsZero; }
@end

@implementation FValue
- (const char *)objCType
{
    switch (_kind) {
    case 'r': return @encode(NSRange);
    case 'P': return @encode(NSPoint);
    case 'S': return @encode(NSSize);
    case 'R': return @encode(NSRect);
    case 'E': return @encode(NSEdgeInsets);
    case 'o': return @encode(id);
    case 'B': return _type;
    }
    return @encode(void *);
}
- (void)getValue:(void *)value
{
    switch (_kind) {
    case 'r': *(NSRange *)value = _range; break;
    case 'P': *(NSPoint *)value = _rect.origin; break;
    case 'S': *(NSSize *)value = [self sizeValue]; break;
    case 'R': *(NSRect *)value = _rect; break;
    case 'E': *(NSEdgeInsets *)value = _insets; break;
    case 'B': memcpy(value, _bytes, _size); break;
    default: *(void **)value = _ptr; break;
    }
}
- (void)dealloc
{
    free(_bytes);
    free(_type);
    [super dealloc];
}
- (NSRange)rangeValue { return _range; }
- (void *)pointerValue { return _ptr; }
- (NSPoint)pointValue { return _rect.origin; }
- (NSSize)sizeValue { return NSMakeSize(_rect.origin.x, _rect.origin.y); }
- (NSRect)rectValue { return _rect; }
- (NSEdgeInsets)edgeInsetsValue { return _insets; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[FValue class]])
        return NO;
    FValue *o = other;
    if (o->_kind != _kind)
        return NO;
    switch (_kind) {
    case 'r': return NSEqualRanges(o->_range, _range);
    case 'p':
    case 'o': return o->_ptr == _ptr;
    case 'E': return !memcmp(&o->_insets, &_insets, sizeof _insets);
    case 'B': return o->_size == _size && !strcmp(o->_type, _type) && !memcmp(o->_bytes, _bytes, _size);
    default: return NSEqualRects(o->_rect, _rect);
    }
}
- (NSUInteger)hash
{
    switch (_kind) {
    case 'r': return _range.location * 31 + _range.length;
    case 'p':
    case 'o': return (NSUInteger)_ptr;
    case 'E': return (NSUInteger)(_insets.top * 31 + _insets.left);
    case 'B': {
        NSUInteger h = _size;
        for (NSUInteger i = 0; i < _size; i++)
            h = h * 31 + ((unsigned char *)_bytes)[i];
        return h;
    }
    default: return (NSUInteger)(_rect.origin.x * 31 + _rect.origin.y * 17 + _rect.size.width);
    }
}
- (NSString *)description
{
    if (_kind == 'r')
        return [NSString stringWithFormat:@"NSRange: {%lu, %lu}", (unsigned long)_range.location,
                                          (unsigned long)_range.length];
    switch (_kind) {
    case 'P': return [@"NSPoint: " stringByAppendingString:NSStringFromPoint(_rect.origin)];
    case 'S': return [@"NSSize: " stringByAppendingString:NSStringFromSize([self sizeValue])];
    case 'R': return [@"NSRect: " stringByAppendingString:NSStringFromRect(_rect)];
    case 'E':
        return [NSString stringWithFormat:@"NSEdgeInsets: {%g, %g, %g, %g}", _insets.top, _insets.left,
                                          _insets.bottom, _insets.right];
    case 'B': {
        NSMutableString *m = [NSMutableString stringWithString:@"<"];
        for (NSUInteger i = 0; i < _size; i++) {
            if (i && !(i % 4))
                [m appendString:@" "];
            [m appendFormat:@"%02x", ((unsigned char *)_bytes)[i]];
        }
        [m appendString:@">"];
        return m;
    }
    }
    return [NSString stringWithFormat:@"<%p>", _ptr];
}
@end

/* ---- NSNumber ------------------------------------------------------------------ */

static BOOL is_float(FNumber *n) { return n->_type == 'f' || n->_type == 'd'; }
static BOOL is_unsigned(FNumber *n) { return n->_type == 'Q'; }

static double as_double(FNumber *n)
{
    if (is_float(n))
        return n->_v.d;
    return is_unsigned(n) ? (double)n->_v.u : (double)n->_v.i;
}

static long long as_ll(FNumber *n)
{
    if (is_float(n))
        return (long long)n->_v.d;
    return n->_v.i;
}

static FNumber *make(char type)
{
    FNumber *n = [[FNumber alloc] init];
    n->_type = type;
    return n;
}

static NSNumber *signed_number(char type, long long v)
{
    FNumber *n = make(type);
    n->_v.i = v;
    return [n autorelease];
}

static NSNumber *unsigned_number(char type, unsigned long long v)
{
    /* Mac Foundation keeps unsigned values that fit in a signed type as that
     * signed type; only the very largest stay unsigned ("Q"). */
    if (type == 'Q' && v <= (unsigned long long)LLONG_MAX)
        type = 'q';
    FNumber *n = make(type);
    n->_v.u = v;
    return [n autorelease];
}

static NSNumber *float_number(char type, double v)
{
    FNumber *n = make(type);
    n->_v.d = v;
    return [n autorelease];
}

/* The shortest text that reads back as the same value, as Mac Foundation
 * prints 0.1 rather than 0.10000000000000001. */
static NSString *format_double(double d, BOOL single)
{
    char buf[64];
    if (isnan(d))
        return @"nan";
    if (isinf(d))
        return d > 0 ? @"inf" : @"-inf";
    int prec;
    for (prec = 1; prec <= 17; prec++) {
        snprintf(buf, sizeof buf, "%.*g", prec, d);
        if (single ? (float)strtod(buf, NULL) == (float)d : strtod(buf, NULL) == d)
            break;
    }
    /* whole digits are written out, as with "%.16g": 30, not 3e+01 */
    int exp = d != 0 ? (int)floor(log10(fabs(d))) : 0;
    if (prec <= 17 && exp >= prec && exp + 1 <= 16) {
        snprintf(buf, sizeof buf, "%.*g", exp + 1, d);
    }
    return [NSString stringWithUTF8String:buf];
}

@implementation NSNumber
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSNumber class])
        return [FNumber allocWithZone:zone];
    return [super allocWithZone:zone];
}
+ (NSNumber *)numberWithChar:(char)v { return signed_number('c', v); }
+ (NSNumber *)numberWithUnsignedChar:(unsigned char)v { return signed_number('s', v); }
+ (NSNumber *)numberWithShort:(short)v { return signed_number('s', v); }
+ (NSNumber *)numberWithUnsignedShort:(unsigned short)v { return signed_number('i', v); }
+ (NSNumber *)numberWithInt:(int)v { return signed_number('i', v); }
+ (NSNumber *)numberWithUnsignedInt:(unsigned int)v { return signed_number('q', v); }
+ (NSNumber *)numberWithLong:(long)v { return signed_number('q', v); }
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)v { return unsigned_number('Q', v); }
+ (NSNumber *)numberWithLongLong:(long long)v { return signed_number('q', v); }
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)v { return unsigned_number('Q', v); }
+ (NSNumber *)numberWithFloat:(float)v { return float_number('f', v); }
+ (NSNumber *)numberWithDouble:(double)v { return float_number('d', v); }
+ (NSNumber *)numberWithBool:(BOOL)v { return v ? yes_number : no_number; }
+ (NSNumber *)numberWithInteger:(NSInteger)v { return signed_number('q', v); }
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)v { return unsigned_number('Q', v); }
- (instancetype)initWithInt:(int)v
{
    [self release];
    return [[NSNumber numberWithInt:v] retain];
}
- (instancetype)initWithInteger:(NSInteger)v
{
    [self release];
    return [[NSNumber numberWithInteger:v] retain];
}
- (instancetype)initWithDouble:(double)v
{
    [self release];
    return [[NSNumber numberWithDouble:v] retain];
}
- (instancetype)initWithBool:(BOOL)v
{
    [self release];
    return [[NSNumber numberWithBool:v] retain];
}
- (char)charValue { return (char)[self longLongValue]; }
- (unsigned char)unsignedCharValue { return (unsigned char)[self longLongValue]; }
- (short)shortValue { return (short)[self longLongValue]; }
- (unsigned short)unsignedShortValue { return (unsigned short)[self longLongValue]; }
- (int)intValue { return (int)[self longLongValue]; }
- (unsigned int)unsignedIntValue { return (unsigned int)[self longLongValue]; }
- (long)longValue { return (long)[self longLongValue]; }
- (unsigned long)unsignedLongValue { return (unsigned long)[self unsignedLongLongValue]; }
- (long long)longLongValue { return 0; }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)[self longLongValue]; }
- (float)floatValue { return (float)[self doubleValue]; }
- (double)doubleValue { return 0; }
- (BOOL)boolValue { return [self longLongValue] != 0 || [self doubleValue] != 0; }
- (NSInteger)integerValue { return (NSInteger)[self longLongValue]; }
- (NSUInteger)unsignedIntegerValue { return (NSUInteger)[self unsignedLongLongValue]; }
- (NSString *)stringValue { return [self description]; }
- (const char *)objCType { return "i"; }
- (NSComparisonResult)compare:(NSNumber *)other { return NSOrderedSame; }
- (BOOL)isEqualToNumber:(NSNumber *)number { return [self compare:number] == NSOrderedSame; }
- (NSString *)descriptionWithLocale:(id)locale { return [self description]; }
@end

@implementation FNumber
- (id)retain
{
    if (self == yes_number || self == no_number)
        return self;
    return [super retain];
}
- (oneway void)release
{
    if (self == yes_number || self == no_number)
        return;
    [super release];
}
- (long long)longLongValue { return as_ll(self); }
- (unsigned long long)unsignedLongLongValue { return is_float(self) ? (unsigned long long)_v.d : _v.u; }
- (double)doubleValue { return as_double(self); }
- (BOOL)boolValue { return is_float(self) ? _v.d != 0 : _v.i != 0; }
- (const char *)objCType
{
    static const char *types[] = {"c", "C", "s", "S", "i", "I", "q", "Q", "f", "d"};
    const char *letters = "cCsSiIqQfd";
    if (_type == 'B')
        return "c";
    return types[strchr(letters, _type) - letters];
}
/* a number read as a pointer gives its value, as on a Mac: apps read an
 * NSScreenNumber this way (OBS's screen capture does) (freemac 1.246) */
- (void *)pointerValue { return (void *)(uintptr_t)[self unsignedLongLongValue]; }
- (void)getValue:(void *)value
{
    switch (_type) {
    case 'c':
    case 'B': *(char *)value = (char)_v.i; break;
    case 'C': *(unsigned char *)value = (unsigned char)_v.u; break;
    case 's': *(short *)value = (short)_v.i; break;
    case 'S': *(unsigned short *)value = (unsigned short)_v.u; break;
    case 'i': *(int *)value = (int)_v.i; break;
    case 'I': *(unsigned int *)value = (unsigned int)_v.u; break;
    case 'f': *(float *)value = (float)_v.d; break;
    case 'd': *(double *)value = _v.d; break;
    default: *(long long *)value = _v.i; break;
    }
}
- (NSString *)description
{
    if (is_float(self))
        return format_double(_v.d, _type == 'f');
    if (is_unsigned(self))
        return FFormatC("%llu", _v.u);
    return FFormatC("%lld", _v.i);
}
- (NSComparisonResult)compare:(NSNumber *)other
{
    other = ferry_plain_number(other);
    if ([other isKindOfClass:[NSDecimalNumber class]])   /* exactly, in base 10 */
        return (NSComparisonResult) - [other compare:self];
    if (![other isKindOfClass:[FNumber class]])
        FRaise(NSInvalidArgumentException, @"-[NSNumber compare:]: nil argument");
    FNumber *o = (FNumber *)other;
    if (!is_float(self) && !is_float(o)) {
        if (is_unsigned(self) || is_unsigned(o)) {
            if (!is_unsigned(self) && _v.i < 0)
                return NSOrderedAscending;
            if (!is_unsigned(o) && o->_v.i < 0)
                return NSOrderedDescending;
            return _v.u < o->_v.u ? NSOrderedAscending : _v.u > o->_v.u ? NSOrderedDescending : NSOrderedSame;
        }
        return _v.i < o->_v.i ? NSOrderedAscending : _v.i > o->_v.i ? NSOrderedDescending : NSOrderedSame;
    }
    double a = as_double(self), b = as_double(o);
    return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    other = ferry_plain_number(other);
    if ([other isKindOfClass:[NSDecimalNumber class]])
        return [other isEqual:self];
    if (![other isKindOfClass:[FNumber class]])
        return NO;
    return [self compare:other] == NSOrderedSame;
}
- (NSUInteger)hash
{
    if (is_float(self)) {
        if (_v.d == floor(_v.d) && fabs(_v.d) < 9.2e18)
            return (NSUInteger)(long long)_v.d;
        union { double d; NSUInteger u; } bits = {.d = _v.d};
        return bits.u;
    }
    return (NSUInteger)_v.u;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

/* ---- NSConstantIntegerNumber: a literal number kept in the program ---- */

@implementation NSConstantIntegerNumber
/* the type letter, when the program's pointer to it reads as one */
static char literal_type(NSConstantIntegerNumber *n)
{
    const char *e = LITERAL(n)->encoding;
    if ((uintptr_t)e > 0x1000 && e[0] && !e[1] && strchr("cCsSiIlLqQB", e[0]))
        return e[0];
    return 'q';
}
static BOOL literal_unsigned(char t) { return strchr("CSILQ", t) != NULL; }
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }
- (void)dealloc { /* kept in the program, never freed */ if (0) [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (const char *)objCType
{
    switch (literal_type(self)) {
    case 'c': return "c";
    case 'C': return "C";
    case 's': return "s";
    case 'S': return "S";
    case 'i': return "i";
    case 'I': return "I";
    case 'l': return "l";
    case 'L': return "L";
    case 'Q': return "Q";
    case 'B': return "c";
    default: return "q";
    }
}
- (long long)longLongValue { return LITERAL(self)->value; }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)LITERAL(self)->value; }
- (double)doubleValue
{
    return literal_unsigned(literal_type(self)) ? (double)(unsigned long long)LITERAL(self)->value : (double)LITERAL(self)->value;
}
- (BOOL)boolValue { return LITERAL(self)->value != 0; }
- (void *)pointerValue { return (void *)(uintptr_t)LITERAL(self)->value; }
- (void)getValue:(void *)value
{
    switch (literal_type(self)) {
    case 'c': case 'C': case 'B': *(char *)value = (char)LITERAL(self)->value; break;
    case 's': case 'S': *(short *)value = (short)LITERAL(self)->value; break;
    case 'i': case 'I': *(int *)value = (int)LITERAL(self)->value; break;
    default: *(long long *)value = LITERAL(self)->value; break;
    }
}
- (NSNumber *)_ferryNumber
{
    char t = literal_type(self);
    if (t == 'B')
        return LITERAL(self)->value ? yes_number : no_number;
    if (literal_unsigned(t))
        return [NSNumber numberWithUnsignedLongLong:(unsigned long long)LITERAL(self)->value];
    return [NSNumber numberWithLongLong:LITERAL(self)->value];
}
- (NSComparisonResult)compare:(NSNumber *)other { return [[self _ferryNumber] compare:other]; }
- (BOOL)isEqual:(id)other { return other == self || [[self _ferryNumber] isEqual:other]; }
- (NSUInteger)hash { return [[self _ferryNumber] hash]; }
- (NSString *)description { return [[self _ferryNumber] description]; }
- (NSString *)stringValue { return [[self _ferryNumber] stringValue]; }
@end

static id ferry_plain_number(id n)
{
    static Class constant;
    if (!constant)
        constant = [NSConstantIntegerNumber class];
    return n && object_getClass(n) == constant ? [(NSConstantIntegerNumber *)n _ferryNumber] : n;
}

/* Newer clang refers to the two booleans' own storage, __kCFBooleanTrue and
 * __kCFBooleanFalse, where older code read the kCFBooleanTrue pointer
 * (Qt's Cocoa plugin in OBS, freemac 1.263): the booleans live there. */
F_EXPORT _Alignas(16) unsigned char ferry_true_storage[48] __asm__("___kCFBooleanTrue");
F_EXPORT _Alignas(16) unsigned char ferry_false_storage[48] __asm__("___kCFBooleanFalse");
_Alignas(16) unsigned char ferry_true_storage[48], ferry_false_storage[48];

static FNumber *static_boolean(unsigned char *storage, long long v)
{
    Class c = [FNumber class];
    if (class_getInstanceSize(c) > 48)
        return make('B');
    memset(storage, 0, 48);
    *(Class *)storage = c;
    FNumber *n = (FNumber *)(void *)storage;
    n->_type = 'B';
    n->_v.i = v;
    return n;
}

__attribute__((constructor)) static void numbers_init(void)
{
    yes_number = static_boolean(ferry_true_storage, 1);
    no_number = static_boolean(ferry_false_storage, 0);
    ferry_true = (CFBooleanRef)yes_number;
    ferry_false = (CFBooleanRef)no_number;
}
