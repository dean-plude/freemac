/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSValue and NSNumber. A number remembers the C type it
 * was made from (its objCType) and compares by value, as on a Mac. The two
 * booleans are shared objects, which CoreFoundation also hands out as
 * kCFBooleanTrue and kCFBooleanFalse. */
#import "FInternal.h"

@interface FValue : NSValue {
@public
    char _kind; /* 'r' range, 'p' pointer, 'P' point, 'S' size, 'R' rect, 'E' edge insets */
    NSRange _range;
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
    }
    return @encode(void *);
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
    for (int prec = 1; prec <= 17; prec++) {
        snprintf(buf, sizeof buf, "%.*g", prec, d);
        if (single ? (float)strtod(buf, NULL) == (float)d : strtod(buf, NULL) == d)
            break;
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

__attribute__((constructor)) static void numbers_init(void)
{
    yes_number = make('B');
    yes_number->_v.i = 1;
    no_number = make('B');
    no_number->_v.i = 0;
    ferry_true = (CFBooleanRef)yes_number;
    ferry_false = (CFBooleanRef)no_number;
}
