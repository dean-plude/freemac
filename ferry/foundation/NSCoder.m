/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSCoder, NSKeyedArchiver and NSKeyedUnarchiver: keyed archives, the
 * format nib files and saved documents use. Written from Apple's public
 * documentation of these classes and of the archive layout (a property
 * list with "$archiver", "$version", "$top" and "$objects", where objects
 * refer to each other by UID and each object names its class through a
 * "$class" entry holding "$classname" and "$classes"). Values coded
 * without keys are given keys of their own ("$0", "$1"...), and NSArchiver
 * and NSUnarchiver (freemac 1.221, Ferry 0.45.0) write and read archives
 * of that form; see below. */
#import "FInternal.h"

NSString *const NSKeyedArchiveRootObjectKey = @"root";
NSString *const NSInvalidArchiveOperationException = @"NSInvalidArchiveOperationException";
NSString *const NSInvalidUnarchiveOperationException = @"NSInvalidUnarchiveOperationException";

/* A UID in Ferry's property lists is a one-entry dictionary {"CF$UID": n},
 * which is also how Apple's XML property lists write one. The binary
 * reader and writer turn these into real UIDs. */
static NSDictionary *make_uid(NSUInteger n)
{
    return [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLongLong:n] forKey:@"CF$UID"];
}

static BOOL get_uid(id obj, NSUInteger *out)
{
    if (![obj isKindOfClass:[NSDictionary class]] || [obj count] != 1)
        return NO;
    id n = [obj objectForKey:@"CF$UID"];
    if (![n isKindOfClass:[NSNumber class]])
        return NO;
    *out = [n unsignedLongLongValue];
    return YES;
}

static NSError *archive_error(NSInteger code, NSString *why)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:why forKey:NSLocalizedDescriptionKey]];
}

static void subclass_responsibility(id self, SEL cmd)
{
    FRaise(NSInvalidArgumentException, @"*** -[%s %s]: only an archiver implements this",
           object_getClassName(self), sel_getName(cmd));
}
/* ---- coding without keys: walking a value by its type encoding ---------------------- */

/* How many values without a key the object at each depth has had. */
static NSUInteger *seq_slot(NSUInteger **seq, NSUInteger *cap, NSUInteger depth)
{
    if (depth >= *cap) {
        NSUInteger n = depth + 8;
        *seq = realloc(*seq, n * sizeof **seq);
        for (NSUInteger i = *cap; i < n; i++)
            (*seq)[i] = 0;
        *cap = n;
    }
    return &(*seq)[depth];
}

static const char *skip_qualifiers(const char *t)
{
    while (*t && strchr("rnNoORVA", *t))
        t++;
    return t;
}

enum leaf_kind { LEAF_INT, LEAF_UINT, LEAF_BOOL, LEAF_FLOAT, LEAF_DOUBLE, LEAF_OBJECT, LEAF_CLASS, LEAF_SEL,
                 LEAF_CSTRING, LEAF_BYTES };
typedef void (^leaf_fn)(enum leaf_kind kind, void *addr, size_t size);

static size_t size_of_type(const char *t)
{
    NSUInteger size = 0;
    NSGetSizeAndAlignment(t, &size, NULL);
    return size;
}

/* Each value a type is made of, in order: a structure's fields and an
 * array's elements one by one, and anything else (unions, bit fields,
 * long doubles) as its bytes. */
static void walk_value(const char *type, char *addr, leaf_fn leaf)
{
    const char *t = skip_qualifiers(type);
    switch (*t) {
    case 'v': return;
    case 'c': leaf(LEAF_INT, addr, 1); return;
    case 's': case 'i': case 'l': case 'q': leaf(LEAF_INT, addr, size_of_type(t)); return;
    case 'C': case 'S': case 'I': case 'L': case 'Q': leaf(LEAF_UINT, addr, size_of_type(t)); return;
    case 'B': leaf(LEAF_BOOL, addr, sizeof(bool)); return;
    case 'f': leaf(LEAF_FLOAT, addr, sizeof(float)); return;
    case 'd': leaf(LEAF_DOUBLE, addr, sizeof(double)); return;
    case '@': leaf(LEAF_OBJECT, addr, sizeof(id)); return;
    case '#': leaf(LEAF_CLASS, addr, sizeof(Class)); return;
    case ':': leaf(LEAF_SEL, addr, sizeof(SEL)); return;
    case '*': leaf(LEAF_CSTRING, addr, sizeof(char *)); return;
    case '[': {
        char *end;
        unsigned long n = strtoul(t + 1, &end, 10);
        size_t es = size_of_type(end);
        for (unsigned long i = 0; i < n; i++)
            walk_value(end, addr + i * es, leaf);
        return;
    }
    case '{': {
        const char *f = t + 1;
        while (*f && *f != '=' && *f != '}')
            f++;
        if (*f == '=') {
            enum { MAX_FIELDS = 64 };
            const char *types[MAX_FIELDS];
            size_t offsets[MAX_FIELDS];
            int count = 0;
            BOOL plain = YES;
            size_t off = 0;
            f++;
            while (*f && *f != '}' && plain) {
                if (*f == '"') {
                    f = strchr(f + 1, '"');
                    f = f ? f + 1 : "";
                    continue;
                }
                if (*f == 'b' || count == MAX_FIELDS) {
                    plain = NO;
                    break;
                }
                NSUInteger fs = 0, fa = 1;
                const char *next = NSGetSizeAndAlignment(f, &fs, &fa);
                off = (off + fa - 1) / fa * fa;
                types[count] = f;
                offsets[count++] = off;
                off += fs;
                f = next;
            }
            if (plain && count) {
                for (int i = 0; i < count; i++) {
                    const char *end = NSGetSizeAndAlignment(types[i], NULL, NULL);
                    char *one = strndup(types[i], (size_t)(end - types[i]));
                    walk_value(one, addr + offsets[i], leaf);
                    free(one);
                }
                return;
            }
        }
        leaf(LEAF_BYTES, addr, size_of_type(t));
        return;
    }
    default:
        leaf(LEAF_BYTES, addr, size_of_type(t));
        return;
    }
}

static int64_t read_int(const void *addr, size_t size, BOOL is_signed)
{
    switch (size) {
    case 1: return is_signed ? *(const int8_t *)addr : *(const uint8_t *)addr;
    case 2: return is_signed ? *(const int16_t *)addr : *(const uint16_t *)addr;
    case 4: return is_signed ? *(const int32_t *)addr : *(const uint32_t *)addr;
    default: return *(const int64_t *)addr;
    }
}

static void write_int(void *addr, size_t size, int64_t v)
{
    switch (size) {
    case 1: *(int8_t *)addr = (int8_t)v; break;
    case 2: *(int16_t *)addr = (int16_t)v; break;
    case 4: *(int32_t *)addr = (int32_t)v; break;
    default: *(int64_t *)addr = v; break;
    }
}

/* ---- NSCoder ------------------------------------------------------------------ */

@implementation NSCoder
- (BOOL)allowsKeyedCoding { return NO; }
- (BOOL)requiresSecureCoding { return NO; }
- (NSError *)error { return nil; }
- (void)failWithError:(NSError *)error {}
- (void)encodeObject:(id)object forKey:(NSString *)key { subclass_responsibility(self, _cmd); }
- (void)encodeConditionalObject:(id)object forKey:(NSString *)key { [self encodeObject:object forKey:key]; }
- (void)encodeBool:(BOOL)value forKey:(NSString *)key { subclass_responsibility(self, _cmd); }
- (void)encodeInt:(int)value forKey:(NSString *)key { [self encodeInt64:value forKey:key]; }
- (void)encodeInt32:(int32_t)value forKey:(NSString *)key { [self encodeInt64:value forKey:key]; }
- (void)encodeInt64:(int64_t)value forKey:(NSString *)key { subclass_responsibility(self, _cmd); }
- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key { [self encodeInt64:value forKey:key]; }
- (void)encodeFloat:(float)value forKey:(NSString *)key { [self encodeDouble:value forKey:key]; }
- (void)encodeDouble:(double)value forKey:(NSString *)key { subclass_responsibility(self, _cmd); }
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key
{
    subclass_responsibility(self, _cmd);
}
/* Points, sizes and rectangles are kept as their strings ("{{0, 0}, {10, 20}}"). */
- (void)encodePoint:(NSPoint)point forKey:(NSString *)key { [self encodeObject:NSStringFromPoint(point) forKey:key]; }
- (void)encodeSize:(NSSize)size forKey:(NSString *)key { [self encodeObject:NSStringFromSize(size) forKey:key]; }
- (void)encodeRect:(NSRect)rect forKey:(NSString *)key { [self encodeObject:NSStringFromRect(rect) forKey:key]; }
- (BOOL)containsValueForKey:(NSString *)key { subclass_responsibility(self, _cmd); return NO; }
- (id)decodeObjectForKey:(NSString *)key { subclass_responsibility(self, _cmd); return nil; }
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key { return [self decodeObjectForKey:key]; }
- (id)decodeObjectOfClasses:(NSSet *)classes forKey:(NSString *)key { return [self decodeObjectForKey:key]; }
- (id)decodeTopLevelObjectForKey:(NSString *)key error:(NSError **)error { return [self decodeObjectForKey:key]; }
- (NSArray *)decodeArrayOfObjectsOfClass:(Class)cls forKey:(NSString *)key
{
    id a = [self decodeObjectForKey:key];
    return [a isKindOfClass:[NSArray class]] ? a : nil;
}
- (BOOL)decodeBoolForKey:(NSString *)key { subclass_responsibility(self, _cmd); return NO; }
- (int)decodeIntForKey:(NSString *)key { return (int)[self decodeInt64ForKey:key]; }
- (int32_t)decodeInt32ForKey:(NSString *)key { return (int32_t)[self decodeInt64ForKey:key]; }
- (int64_t)decodeInt64ForKey:(NSString *)key { subclass_responsibility(self, _cmd); return 0; }
- (NSInteger)decodeIntegerForKey:(NSString *)key { return (NSInteger)[self decodeInt64ForKey:key]; }
- (float)decodeFloatForKey:(NSString *)key { return (float)[self decodeDoubleForKey:key]; }
- (double)decodeDoubleForKey:(NSString *)key { subclass_responsibility(self, _cmd); return 0; }
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length
{
    subclass_responsibility(self, _cmd);
    return NULL;
}
- (NSPoint)decodePointForKey:(NSString *)key
{
    id s = [self decodeObjectForKey:key];
    return [s isKindOfClass:[NSString class]] ? NSPointFromString(s) : NSZeroPoint;
}
- (NSSize)decodeSizeForKey:(NSString *)key
{
    id s = [self decodeObjectForKey:key];
    return [s isKindOfClass:[NSString class]] ? NSSizeFromString(s) : NSZeroSize;
}
- (NSRect)decodeRectForKey:(NSString *)key
{
    id s = [self decodeObjectForKey:key];
    return [s isKindOfClass:[NSString class]] ? NSRectFromString(s) : NSZeroRect;
}

/* Coding without keys, written in terms of the two calls each coder
 * implements: encodeValueOfObjCType:at: and decodeValueOfObjCType:at:size:. */
- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr { subclass_responsibility(self, _cmd); }
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size
{
    subclass_responsibility(self, _cmd);
}
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
    [self decodeValueOfObjCType:type at:data size:size_of_type(type)];
}
- (void)encodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list ap;
    va_start(ap, types);
    for (const char *t = types; t && *t;) {
        const char *end = NSGetSizeAndAlignment(t, NULL, NULL);
        char *one = strndup(t, (size_t)(end - t));
        [self encodeValueOfObjCType:one at:va_arg(ap, const void *)];
        free(one);
        t = end;
    }
    va_end(ap);
}
- (void)decodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list ap;
    va_start(ap, types);
    for (const char *t = types; t && *t;) {
        const char *end = NSGetSizeAndAlignment(t, NULL, NULL);
        char *one = strndup(t, (size_t)(end - t));
        [self decodeValueOfObjCType:one at:va_arg(ap, void *) size:size_of_type(one)];
        free(one);
        t = end;
    }
    va_end(ap);
}
- (void)encodeArrayOfObjCType:(const char *)type count:(NSUInteger)count at:(const void *)array
{
    size_t size = size_of_type(type);
    for (NSUInteger i = 0; i < count; i++)
        [self encodeValueOfObjCType:type at:(const char *)array + i * size];
}
- (void)decodeArrayOfObjCType:(const char *)type count:(NSUInteger)count at:(void *)array
{
    size_t size = size_of_type(type);
    for (NSUInteger i = 0; i < count; i++)
        [self decodeValueOfObjCType:type at:(char *)array + i * size size:size];
}
- (void)encodeObject:(id)object { [self encodeValueOfObjCType:@encode(id) at:&object]; }
- (void)encodeRootObject:(id)rootObject { [self encodeObject:rootObject]; }
- (void)encodeBycopyObject:(id)anObject { [self encodeObject:anObject]; }
- (void)encodeByrefObject:(id)anObject { [self encodeObject:anObject]; }
- (void)encodeConditionalObject:(id)object { [self encodeObject:object]; }
- (id)decodeObject
{
    id object = nil;
    [self decodeValueOfObjCType:@encode(id) at:&object size:sizeof object];
    return [object autorelease];
}
- (void)encodeDataObject:(NSData *)data { [self encodeObject:data]; }
- (NSData *)decodeDataObject
{
    id data = [self decodeObject];
    return [data isKindOfClass:[NSData class]] ? data : nil;
}
- (void)encodeBytes:(const void *)byteaddr length:(NSUInteger)length
{
    [self encodeDataObject:[NSData dataWithBytes:byteaddr length:length]];
}
- (void *)decodeBytesWithReturnedLength:(NSUInteger *)lengthp
{
    NSData *data = [self decodeDataObject];
    if (lengthp)
        *lengthp = [data length];
    return (void *)[data bytes];
}
- (void)encodePropertyList:(id)aPropertyList { [self encodeObject:aPropertyList]; }
- (id)decodePropertyList { return [self decodeObject]; }
- (void)encodePoint:(NSPoint)point { [self encodeValueOfObjCType:@encode(NSPoint) at:&point]; }
- (NSPoint)decodePoint
{
    NSPoint p = NSZeroPoint;
    [self decodeValueOfObjCType:@encode(NSPoint) at:&p size:sizeof p];
    return p;
}
- (void)encodeSize:(NSSize)size { [self encodeValueOfObjCType:@encode(NSSize) at:&size]; }
- (NSSize)decodeSize
{
    NSSize s = NSZeroSize;
    [self decodeValueOfObjCType:@encode(NSSize) at:&s size:sizeof s];
    return s;
}
- (void)encodeRect:(NSRect)rect { [self encodeValueOfObjCType:@encode(NSRect) at:&rect]; }
- (NSRect)decodeRect
{
    NSRect r = NSZeroRect;
    [self decodeValueOfObjCType:@encode(NSRect) at:&r size:sizeof r];
    return r;
}
/* The version of the class this program has: archives don't record one. */
- (NSInteger)versionForClassName:(NSString *)className
{
    Class cls = NSClassFromString(className);
    return cls ? class_getVersion(cls) : NSNotFound;
}
- (unsigned)systemVersion { return 1000; }
@end

/* ---- which class an object is archived as ------------------------------------------- */

/* Foundation's own concrete classes (FArray, NSConcreteString...) archive
 * under their public names, as on a Mac. */
static BOOL private_class(id obj)
{
    const char *n = object_getClassName(obj);
    return (n[0] == 'F' && n[1] >= 'A' && n[1] <= 'Z') || !strncmp(n, "NSConcrete", 10) || !strncmp(n, "__NSCF", 6) ||
           /* Swift's own storage for a bridged array, dictionary, set or
            * string, such as _TtGCs23_ContiguousArrayStorage...: archived as
            * the public class, as on a Mac (freemac 1.262) */
           !strncmp(n, "_TtCs", 5) || !strncmp(n, "_TtGCs", 6) || !strncmp(n, "__Swift", 7);
}

@implementation NSObject (NSArchiving)
- (Class)classForCoder { return object_getClass(self); }
- (Class)classForKeyedArchiver { return [self classForCoder]; }
- (id)replacementObjectForCoder:(NSCoder *)coder { return self; }
- (id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)archiver { return [self replacementObjectForCoder:archiver]; }
- (id)awakeAfterUsingCoder:(NSCoder *)coder { return self; }
+ (NSArray *)classFallbacksForKeyedArchiver { return nil; }
- (Class)classForArchiver { return [self classForCoder]; }
- (id)replacementObjectForArchiver:(NSArchiver *)archiver { return [self replacementObjectForCoder:archiver]; }
+ (NSInteger)version { return class_getVersion(self); }
+ (void)setVersion:(NSInteger)aVersion { class_setVersion(self, (int)aVersion); }
@end

#define PUBLIC_CLASS(Base, Mutable)                                                   \
    -(Class)classForCoder                                                            \
    {                                                                                \
        if (!private_class(self))                                                    \
            return object_getClass(self);                                            \
        return [self isKindOfClass:[Mutable class]] ? [Mutable class] : [Base class]; \
    }

@implementation NSString (NSArchiving)
PUBLIC_CLASS(NSString, NSMutableString)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:[NSString stringWithString:self] forKey:@"NS.string"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    id s = [coder decodeObjectForKey:@"NS.string"];
    if (!s) {
        NSUInteger n = 0;
        const uint8_t *b = [coder decodeBytesForKey:@"NS.bytes" returnedLength:&n];
        s = b ? FStringFromUTF8((const char *)b, n) : @"";
    }
    return [self initWithString:s];
}
@end

@implementation NSArray (NSArchiving)
PUBLIC_CLASS(NSArray, NSMutableArray)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:self forKey:@"NS.objects"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    /* Handled by the unarchiver, which knows the element UIDs. */
    return [self initWithArray:[coder decodeObjectForKey:@"NS.objects"] ?: [NSArray array]];
}
@end

@implementation NSDictionary (NSArchiving)
PUBLIC_CLASS(NSDictionary, NSMutableDictionary)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    NSArray *keys = [self allKeys];
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:[keys count]];
    for (id k in keys)
        [values addObject:[self objectForKey:k]];
    [coder encodeObject:keys forKey:@"NS.keys"];
    [coder encodeObject:values forKey:@"NS.objects"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSArray *keys = [coder decodeObjectForKey:@"NS.keys"];
    NSArray *values = [coder decodeObjectForKey:@"NS.objects"];
    NSUInteger n = [keys count] == [values count] ? [keys count] : 0;
    id *k = malloc((n + 1) * sizeof(id)), *v = malloc((n + 1) * sizeof(id));
    for (NSUInteger i = 0; i < n; i++) {
        k[i] = [keys objectAtIndex:i];
        v[i] = [values objectAtIndex:i];
    }
    self = [self initWithObjects:v forKeys:k count:n];
    free(k);
    free(v);
    return self;
}
@end

@implementation NSSet (NSArchiving)
PUBLIC_CLASS(NSSet, NSMutableSet)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:[self allObjects] forKey:@"NS.objects"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSArray *a = [coder decodeObjectForKey:@"NS.objects"];
    NSUInteger n = [a count];
    id *o = malloc((n + 1) * sizeof(id));
    for (NSUInteger i = 0; i < n; i++)
        o[i] = [a objectAtIndex:i];
    self = [self initWithObjects:o count:n];
    free(o);
    return self;
}
@end

@implementation NSData (NSArchiving)
PUBLIC_CLASS(NSData, NSMutableData)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeBytes:[self bytes] length:[self length] forKey:@"NS.bytes"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSUInteger n = 0;
    const uint8_t *b = [coder decodeBytesForKey:@"NS.bytes" returnedLength:&n];
    return [self initWithBytes:b length:n];
}
@end

@implementation NSNumber (NSArchiving)
- (Class)classForCoder { return private_class(self) ? [NSNumber class] : object_getClass(self); }
@end

@implementation NSDate (NSArchiving)
- (Class)classForCoder { return private_class(self) ? [NSDate class] : object_getClass(self); }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:[self timeIntervalSinceReferenceDate] forKey:@"NS.time"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithTimeIntervalSinceReferenceDate:[coder decodeDoubleForKey:@"NS.time"]];
}
@end

@implementation NSNull (NSArchiving)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    [self release];
    return [[NSNull null] retain];
}
@end

@implementation NSURL (NSArchiving)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self baseURL] forKey:@"NS.base"];
    [coder encodeObject:[self relativeString] forKey:@"NS.relative"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSURL *base = [coder decodeObjectForKey:@"NS.base"];
    NSString *rel = [coder decodeObjectForKey:@"NS.relative"];
    return [self initWithString:rel ?: @"" relativeToURL:base];
}
@end

/* NSValue keeps the geometry kinds; "NS.special" says which. */
enum { SPECIAL_POINT = 1, SPECIAL_SIZE = 2, SPECIAL_RECT = 3, SPECIAL_RANGE = 4 };

@implementation NSValue (NSArchiving)
- (Class)classForCoder
{
    if (!private_class(self))
        return object_getClass(self);
    return [self isKindOfClass:[NSNumber class]] ? [NSNumber class] : [NSValue class];
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    const char *t = [self objCType];
    if (!strcmp(t, @encode(NSPoint))) {
        [coder encodeInt:SPECIAL_POINT forKey:@"NS.special"];
        [coder encodePoint:[self pointValue] forKey:@"NS.pointval"];
    } else if (!strcmp(t, @encode(NSSize))) {
        [coder encodeInt:SPECIAL_SIZE forKey:@"NS.special"];
        [coder encodeSize:[self sizeValue] forKey:@"NS.sizeval"];
    } else if (!strcmp(t, @encode(NSRect))) {
        [coder encodeInt:SPECIAL_RECT forKey:@"NS.special"];
        [coder encodeRect:[self rectValue] forKey:@"NS.rectval"];
    } else if (!strcmp(t, @encode(NSRange))) {
        NSRange r = [self rangeValue];
        [coder encodeInt:SPECIAL_RANGE forKey:@"NS.special"];
        [coder encodeInt64:(int64_t)r.location forKey:@"NS.rangeval.location"];
        [coder encodeInt64:(int64_t)r.length forKey:@"NS.rangeval.length"];
    } else {
        FRaise(NSInvalidArchiveOperationException, @"Ferry can't archive an NSValue of type %s", t);
    }
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSValue *v = nil;
    switch ([coder decodeIntForKey:@"NS.special"]) {
    case SPECIAL_POINT: v = [NSValue valueWithPoint:[coder decodePointForKey:@"NS.pointval"]]; break;
    case SPECIAL_SIZE: v = [NSValue valueWithSize:[coder decodeSizeForKey:@"NS.sizeval"]]; break;
    case SPECIAL_RECT: v = [NSValue valueWithRect:[coder decodeRectForKey:@"NS.rectval"]]; break;
    case SPECIAL_RANGE:
        v = [NSValue valueWithRange:NSMakeRange((NSUInteger)[coder decodeInt64ForKey:@"NS.rangeval.location"],
                                                (NSUInteger)[coder decodeInt64ForKey:@"NS.rangeval.length"])];
        break;
    }
    [self release];
    return [v retain];
}
@end

/* NSAttributedString: "NSString" is the text, "NSAttributes" one dictionary
 * when the whole string has the same attributes, or else an array of the
 * distinct dictionaries with "NSAttributeInfo" holding (length, index)
 * pairs as base-128 numbers. */
static void put_varint(NSMutableData *d, NSUInteger v)
{
    do {
        uint8_t b = v & 0x7f;
        v >>= 7;
        if (v)
            b |= 0x80;
        [d appendBytes:&b length:1];
    } while (v);
}

static BOOL get_varint(const uint8_t **p, const uint8_t *end, NSUInteger *v)
{
    *v = 0;
    for (int shift = 0; *p < end && shift < 64; shift += 7) {
        uint8_t b = *(*p)++;
        *v |= (NSUInteger)(b & 0x7f) << shift;
        if (!(b & 0x80))
            return YES;
    }
    return NO;
}

@implementation NSAttributedString (NSArchiving)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    NSString *text = [self string];
    [coder encodeObject:[NSString stringWithString:text] forKey:@"NSString"];
    NSUInteger len = [text length];
    NSRange r;
    if (len == 0) {
        return;
    }
    NSDictionary *first = [self attributesAtIndex:0 effectiveRange:&r];
    if (r.length == len) {
        [coder encodeObject:first forKey:@"NSAttributes"];
        return;
    }
    NSMutableArray *dicts = [NSMutableArray array];
    NSMutableData *info = [NSMutableData data];
    for (NSUInteger i = 0; i < len; i = NSMaxRange(r)) {
        NSDictionary *a = [self attributesAtIndex:i effectiveRange:&r];
        NSUInteger idx = [dicts indexOfObject:a];
        if (idx == NSNotFound) {
            idx = [dicts count];
            [dicts addObject:a];
        }
        put_varint(info, NSMaxRange(r) - i);
        put_varint(info, idx);
    }
    [coder encodeObject:dicts forKey:@"NSAttributes"];
    [coder encodeObject:info forKey:@"NSAttributeInfo"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *text = [coder decodeObjectForKey:@"NSString"];
    if ([text isKindOfClass:[NSAttributedString class]])
        text = [(NSAttributedString *)text string];
    if (![text isKindOfClass:[NSString class]])
        text = @"";
    id attrs = [coder decodeObjectForKey:@"NSAttributes"];
    if ([attrs isKindOfClass:[NSDictionary class]] || !attrs)
        return [self initWithString:text attributes:attrs];
    NSMutableAttributedString *m = [[NSMutableAttributedString alloc] initWithString:text];
    NSData *info = [coder decodeObjectForKey:@"NSAttributeInfo"];
    const uint8_t *p = [info bytes], *end = p + [info length];
    NSUInteger at = 0, n, idx;
    while (p < end && get_varint(&p, end, &n) && get_varint(&p, end, &idx)) {
        if (idx < [attrs count] && at + n <= [text length])
            [m setAttributes:[attrs objectAtIndex:idx] range:NSMakeRange(at, n)];
        at += n;
    }
    self = [self initWithAttributedString:m];
    [m release];
    return self;
}
@end

/* ---- NSKeyedArchiver ------------------------------------------------------------------- */

/* Object identity to UID, an open-addressing table keyed by pointer. */
struct ptrmap {
    const void **keys;
    NSUInteger *vals, cap, count;
};

static NSUInteger ptr_hash(const void *p) { return ((uintptr_t)p >> 4) * 2654435761u; }

static NSUInteger *ptrmap_find(struct ptrmap *m, const void *key, BOOL add)
{
    if (add && (m->count + 1) * 2 > m->cap) {
        struct ptrmap old = *m;
        m->cap = old.cap ? old.cap * 2 : 64;
        m->keys = calloc(m->cap, sizeof *m->keys);
        m->vals = calloc(m->cap, sizeof *m->vals);
        m->count = 0;
        for (NSUInteger i = 0; i < old.cap; i++)
            if (old.keys[i])
                *ptrmap_find(m, old.keys[i], YES) = old.vals[i];
        free(old.keys);
        free(old.vals);
    }
    if (!m->cap)
        return NULL;
    for (NSUInteger i = ptr_hash(key) & (m->cap - 1);; i = (i + 1) & (m->cap - 1)) {
        if (m->keys[i] == key)
            return &m->vals[i];
        if (!m->keys[i]) {
            if (!add)
                return NULL;
            m->keys[i] = key;
            m->count++;
            return &m->vals[i];
        }
    }
}

/* The class-wide name tables of NSKeyedArchiver and NSKeyedUnarchiver,
 * which any thread may use. */
static os_unfair_lock tables_lock = OS_UNFAIR_LOCK_INIT;

static NSMutableDictionary *global_class_names(void)
{
    static NSMutableDictionary *names;
    static dispatch_once_t names_once;
    dispatch_once(&names_once, ^{
      names = [[NSMutableDictionary alloc] init];
    });
    return names;
}

@implementation NSKeyedArchiver {
    NSMutableArray *_objects;      /* "$objects" */
    NSMutableArray *_keep;         /* encoded objects, kept alive so their addresses stay unique */
    NSMutableArray *_stack;        /* dictionaries being filled */
    NSMutableDictionary *_classUIDs, *_classNames;
    NSMutableDictionary *_top;
    NSMutableData *_data;
    NSData *_encoded;
    struct ptrmap _uids;
    BOOL _secure, _finished;
    NSPropertyListFormat _format;
    NSUInteger *_seq, _seqCap; /* how many values each object being filled has had without a key */
    NSCoder *_facade;          /* the NSArchiver objects are given, when one writes through this */
    NSString *_archiverName;
}

- (instancetype)initRequiringSecureCoding:(BOOL)secure
{
    if ((self = [super init])) {
        _objects = [[NSMutableArray alloc] initWithObjects:@"$null", nil];
        _keep = [[NSMutableArray alloc] init];
        _top = [[NSMutableDictionary alloc] init];
        _stack = [[NSMutableArray alloc] initWithObjects:_top, nil];
        _classUIDs = [[NSMutableDictionary alloc] init];
        _classNames = [[NSMutableDictionary alloc] init];
        _secure = secure;
        _format = NSPropertyListBinaryFormat_v1_0;
        *seq_slot(&_seq, &_seqCap, 0) = 0;
    }
    return self;
}
- (instancetype)init { return [self initRequiringSecureCoding:YES]; }
- (instancetype)initForWritingWithMutableData:(NSMutableData *)data
{
    if ((self = [self initRequiringSecureCoding:NO]))
        _data = [data retain];
    return self;
}
- (void)dealloc
{
    [_objects release];
    [_keep release];
    [_stack release];
    [_classUIDs release];
    [_classNames release];
    [_top release];
    [_data release];
    [_encoded release];
    [_archiverName release];
    free(_uids.keys);
    free(_uids.vals);
    free(_seq);
    [super dealloc];
}

+ (NSData *)archivedDataWithRootObject:(id)root requiringSecureCoding:(BOOL)secure error:(NSError **)error
{
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:secure];
    [a encodeObject:root forKey:NSKeyedArchiveRootObjectKey];
    NSData *d = [[a encodedData] retain];
    [a release];
    return [d autorelease];
}
+ (NSData *)archivedDataWithRootObject:(id)root
{
    return [self archivedDataWithRootObject:root requiringSecureCoding:NO error:NULL];
}
+ (BOOL)archiveRootObject:(id)root toFile:(NSString *)path
{
    return [[self archivedDataWithRootObject:root] writeToFile:path atomically:YES];
}

- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return _secure; }
- (NSPropertyListFormat)outputFormat { return _format; }
- (void)setOutputFormat:(NSPropertyListFormat)format { _format = format; }

+ (void)setClassName:(NSString *)name forClass:(Class)cls
{
    NSString *key = NSStringFromClass(cls);
    os_unfair_lock_lock(&tables_lock);
    if (name)
        [global_class_names() setObject:name forKey:key];
    else
        [global_class_names() removeObjectForKey:key];
    os_unfair_lock_unlock(&tables_lock);
}
+ (NSString *)classNameForClass:(Class)cls
{
    NSString *key = NSStringFromClass(cls);
    os_unfair_lock_lock(&tables_lock);
    NSString *name = [[[global_class_names() objectForKey:key] retain] autorelease];
    os_unfair_lock_unlock(&tables_lock);
    return name;
}
- (void)setClassName:(NSString *)name forClass:(Class)cls
{
    if (name)
        [_classNames setObject:name forKey:NSStringFromClass(cls)];
    else
        [_classNames removeObjectForKey:NSStringFromClass(cls)];
}
- (NSString *)classNameForClass:(Class)cls { return [_classNames objectForKey:NSStringFromClass(cls)]; }

- (NSString *)nameForClass:(Class)cls
{
    NSString *n = [self classNameForClass:cls] ?: [NSKeyedArchiver classNameForClass:cls];
    return n ?: NSStringFromClass(cls);
}

- (NSUInteger)uidForClass:(Class)cls
{
    NSString *name = [self nameForClass:cls];
    NSNumber *known = [_classUIDs objectForKey:name];
    if (known)
        return [known unsignedIntegerValue];
    NSMutableArray *chain = [NSMutableArray arrayWithObject:name];
    for (Class c = class_getSuperclass(cls); c; c = class_getSuperclass(c))
        [chain addObject:[self nameForClass:c]];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObjectsAndKeys:name, @"$classname", chain, @"$classes", nil];
    NSArray *hints = [cls classFallbacksForKeyedArchiver];
    if ([hints count])
        [d setObject:hints forKey:@"$classhints"];
    NSUInteger uid = [_objects count];
    [_objects addObject:d];
    [_classUIDs setObject:[NSNumber numberWithUnsignedInteger:uid] forKey:name];
    return uid;
}

- (NSUInteger)uidForObject:(id)obj
{
    if (!obj)
        return 0;
    obj = _facade ? [obj replacementObjectForArchiver:(NSArchiver *)_facade] : [obj replacementObjectForKeyedArchiver:self];
    if (!obj)
        return 0;
    NSUInteger *known = ptrmap_find(&_uids, obj, NO);
    if (known)
        return *known;
    Class cls = _facade ? [obj classForArchiver] : [obj classForKeyedArchiver];
    NSUInteger uid = [_objects count];
    *ptrmap_find(&_uids, obj, YES) = uid;
    [_keep addObject:obj];
    /* Strings, numbers and data go into "$objects" as they are. */
    if (cls == [NSString class] || cls == [NSNumber class] || cls == [NSData class]) {
        id plain = cls == [NSString class] ? [NSString stringWithString:obj]
                 : cls == [NSData class]   ? [NSData dataWithData:obj]
                                           : obj;
        [_objects addObject:plain];
        return uid;
    }
    if (_secure && ![cls respondsToSelector:@selector(supportsSecureCoding)])
        FRaise(NSInvalidArchiveOperationException, @"Class '%@' does not adopt NSSecureCoding", NSStringFromClass(cls));
    if (![obj respondsToSelector:@selector(encodeWithCoder:)])
        FRaise(NSInvalidArgumentException, @"-[%s encodeWithCoder:]: unrecognized selector sent to instance %p",
               object_getClassName(obj), obj);
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [_objects addObject:d];
    [d setObject:make_uid([self uidForClass:cls]) forKey:@"$class"];
    [_stack addObject:d];
    *seq_slot(&_seq, &_seqCap, [_stack count] - 1) = 0;
    /* Collections write their elements' UIDs straight into NS.objects
     * (and NS.keys), rather than as an archived array. */
    if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSSet class]]) {
        NSMutableArray *refs = [NSMutableArray array];
        for (id o in ([obj isKindOfClass:[NSSet class]] ? [obj allObjects] : obj))
            [refs addObject:make_uid([self uidForObject:o])];
        [d setObject:refs forKey:@"NS.objects"];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *keys = [NSMutableArray array], *vals = [NSMutableArray array];
        for (id k in obj) {
            [keys addObject:make_uid([self uidForObject:k])];
            [vals addObject:make_uid([self uidForObject:[obj objectForKey:k]])];
        }
        [d setObject:keys forKey:@"NS.keys"];
        [d setObject:vals forKey:@"NS.objects"];
    } else {
        [obj encodeWithCoder:_facade ?: self];
    }
    [_stack removeLastObject];
    return uid;
}

- (NSMutableDictionary *)current { return [_stack lastObject]; }

- (void)encodeObject:(id)object forKey:(NSString *)key
{
    [[self current] setObject:make_uid([self uidForObject:object]) forKey:key];
}
- (void)encodeBool:(BOOL)value forKey:(NSString *)key
{
    [[self current] setObject:(value ? (id)kCFBooleanTrue : (id)kCFBooleanFalse) forKey:key];
}
- (void)encodeInt64:(int64_t)value forKey:(NSString *)key
{
    [[self current] setObject:[NSNumber numberWithLongLong:value] forKey:key];
}
- (void)encodeDouble:(double)value forKey:(NSString *)key
{
    [[self current] setObject:[NSNumber numberWithDouble:value] forKey:key];
}
- (void)encodeFloat:(float)value forKey:(NSString *)key
{
    [[self current] setObject:[NSNumber numberWithFloat:value] forKey:key];
}
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key
{
    [[self current] setObject:[NSData dataWithBytes:bytes length:length] forKey:key];
}
/* Geometry is kept inline, as its string. */
- (void)encodePoint:(NSPoint)point forKey:(NSString *)key { [[self current] setObject:NSStringFromPoint(point) forKey:key]; }
- (void)encodeSize:(NSSize)size forKey:(NSString *)key { [[self current] setObject:NSStringFromSize(size) forKey:key]; }
- (void)encodeRect:(NSRect)rect forKey:(NSString *)key { [[self current] setObject:NSStringFromRect(rect) forKey:key]; }

- (void)finishEncoding
{
    if (_finished)
        return;
    _finished = YES;
    NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
        _archiverName ?: @"NSKeyedArchiver", @"$archiver", [NSNumber numberWithInt:100000], @"$version",
        _top, @"$top", _objects, @"$objects", nil];
    _encoded = [[NSPropertyListSerialization dataWithPropertyList:plist format:_format options:0 error:NULL] retain];
    if (_data && _encoded)
        [_data appendData:_encoded];
}
- (NSData *)encodedData
{
    [self finishEncoding];
    return _encoded;
}

/* Values without a key get one of their own, "$0", "$1" and so on, in
 * the object being written. */
- (NSString *)nextUnkeyed
{
    NSUInteger *n = seq_slot(&_seq, &_seqCap, [_stack count] - 1);
    return [NSString stringWithFormat:@"$%lu", (unsigned long)(*n)++];
}
- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    walk_value(type, (char *)addr, ^(enum leaf_kind kind, void *p, size_t size) {
      NSString *key = [self nextUnkeyed];
      switch (kind) {
      case LEAF_INT: [self encodeInt64:read_int(p, size, YES) forKey:key]; break;
      case LEAF_UINT: [self encodeInt64:read_int(p, size, NO) forKey:key]; break;
      case LEAF_BOOL: [self encodeBool:*(bool *)p forKey:key]; break;
      case LEAF_FLOAT: [self encodeFloat:*(float *)p forKey:key]; break;
      case LEAF_DOUBLE: [self encodeDouble:*(double *)p forKey:key]; break;
      case LEAF_OBJECT: [self encodeObject:*(id *)p forKey:key]; break;
      case LEAF_CLASS: [self encodeObject:*(Class *)p ? NSStringFromClass(*(Class *)p) : nil forKey:key]; break;
      case LEAF_SEL: [self encodeObject:*(SEL *)p ? NSStringFromSelector(*(SEL *)p) : nil forKey:key]; break;
      case LEAF_CSTRING: {
          const char *s = *(const char **)p;
          [self encodeObject:s ? [NSData dataWithBytes:s length:strlen(s)] : nil forKey:key];
          break;
      }
      case LEAF_BYTES: [self encodeBytes:p length:size forKey:key]; break;
      }
    });
}
/* For NSArchiver, which writes through a keyed archiver of its own. */
- (void)_ferrySetFacade:(NSCoder *)facade name:(NSString *)name
{
    _facade = facade;
    [_archiverName release];
    _archiverName = [name copy];
}
@end

/* ---- NSKeyedUnarchiver ------------------------------------------------------------------- */

static NSMutableDictionary *global_classes(void)
{
    static NSMutableDictionary *classes;
    static dispatch_once_t classes_once;
    dispatch_once(&classes_once, ^{
      classes = [[NSMutableDictionary alloc] init];
    });
    return classes;
}

enum { UNSEEN, DECODING, DONE };

@implementation NSKeyedUnarchiver {
    NSArray *_objects;
    NSDictionary *_top;
    NSMutableArray *_stack;
    NSMutableDictionary *_classes;
    id *_decoded;
    unsigned char *_state;
    NSUInteger _count;
    NSError *_error;
    NSSet *_allowed;
    BOOL _secure;
    NSDecodingFailurePolicy _policy;
    NSUInteger *_seq, _seqCap; /* how many values each object being read has given without a key */
    NSCoder *_facade;          /* the NSUnarchiver objects are given, when one reads through this */
}

- (instancetype)initForReadingFromData:(NSData *)data error:(NSError **)error
{
    if (!(self = [super init]))
        return nil;
    _stack = [[NSMutableArray alloc] init];
    _classes = [[NSMutableDictionary alloc] init];
    _policy = NSDecodingFailurePolicySetErrorAndReturn;
    _secure = YES;
    id plist = data ? FParsePlist(data, NSPropertyListImmutable, NULL) : nil;
    id objects = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"$objects"] : nil;
    id top = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"$top"] : nil;
    if (![objects isKindOfClass:[NSArray class]] || ![top isKindOfClass:[NSDictionary class]]) {
        FSetError(error, archive_error(4864, @"The data isn't in the correct format (it is not a keyed archive)."));
        [self release];
        return nil;
    }
    _objects = [objects retain];
    _top = [top retain];
    _count = [_objects count];
    _decoded = calloc(_count + 1, sizeof(id));
    _state = calloc(_count + 1, 1);
    [_stack addObject:_top];
    *seq_slot(&_seq, &_seqCap, 0) = 0;
    return self;
}
- (instancetype)initForReadingWithData:(NSData *)data
{
    self = [self initForReadingFromData:data error:NULL];
    if (self) {
        _secure = NO;
        _policy = NSDecodingFailurePolicyRaiseException;
    } else {
        FRaise(NSInvalidArgumentException, @"*** -[NSKeyedUnarchiver initForReadingWithData:]: incomprehensible archive");
    }
    return self;
}
- (void)dealloc
{
    for (NSUInteger i = 0; i < _count; i++)
        [_decoded[i] release];
    free(_decoded);
    free(_state);
    free(_seq);
    [_objects release];
    [_top release];
    [_stack release];
    [_classes release];
    [_error release];
    [_allowed release];
    [super dealloc];
}

+ (id)unarchivedObjectOfClasses:(NSSet *)classes fromData:(NSData *)data error:(NSError **)error
{
    NSKeyedUnarchiver *u = [[self alloc] initForReadingFromData:data error:error];
    if (!u)
        return nil;
    id root = [[u decodeObjectOfClasses:classes forKey:NSKeyedArchiveRootObjectKey] retain];
    if ([u error]) {
        FSetError(error, [u error]);
        [root release];
        root = nil;
    }
    [u release];
    return [root autorelease];
}
+ (id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error
{
    return [self unarchivedObjectOfClasses:[NSSet setWithObject:cls] fromData:data error:error];
}
+ (id)unarchiveTopLevelObjectWithData:(NSData *)data error:(NSError **)error
{
    NSKeyedUnarchiver *u = [[self alloc] initForReadingFromData:data error:error];
    if (!u)
        return nil;
    [u setRequiresSecureCoding:NO];
    id root = [[u decodeObjectForKey:NSKeyedArchiveRootObjectKey] retain];
    if ([u error]) {
        FSetError(error, [u error]);
        [root release];
        root = nil;
    }
    [u release];
    return [root autorelease];
}
+ (id)unarchiveObjectWithData:(NSData *)data
{
    NSKeyedUnarchiver *u = [[self alloc] initForReadingWithData:data];
    id root = [[u decodeObjectForKey:NSKeyedArchiveRootObjectKey] retain];
    [u release];
    return [root autorelease];
}
+ (id)unarchiveObjectWithFile:(NSString *)path
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? [self unarchiveObjectWithData:d] : nil;
}

- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return _secure; }
- (void)setRequiresSecureCoding:(BOOL)secure { _secure = secure; }
- (NSDecodingFailurePolicy)decodingFailurePolicy { return _policy; }
- (void)setDecodingFailurePolicy:(NSDecodingFailurePolicy)policy { _policy = policy; }
- (NSError *)error { return _error; }
- (void)finishDecoding {}

- (void)failWithError:(NSError *)error
{
    if (_policy == NSDecodingFailurePolicyRaiseException)
        FRaise(NSInvalidUnarchiveOperationException, @"%@", [error localizedDescription]);
    if (!_error)
        _error = [error retain];
}
- (void)fail:(NSString *)why { [self failWithError:archive_error(4864, why)]; }

+ (void)setClass:(Class)cls forClassName:(NSString *)name
{
    os_unfair_lock_lock(&tables_lock);
    if (cls)
        [global_classes() setObject:cls forKey:name];
    else
        [global_classes() removeObjectForKey:name];
    os_unfair_lock_unlock(&tables_lock);
}
+ (Class)classForClassName:(NSString *)name
{
    os_unfair_lock_lock(&tables_lock);
    Class cls = [global_classes() objectForKey:name];
    os_unfair_lock_unlock(&tables_lock);
    return cls;
}
- (void)setClass:(Class)cls forClassName:(NSString *)name
{
    if (cls)
        [_classes setObject:cls forKey:name];
    else
        [_classes removeObjectForKey:name];
}
- (Class)classForClassName:(NSString *)name { return [_classes objectForKey:name]; }

- (NSDictionary *)current { return [_stack lastObject]; }

- (BOOL)containsValueForKey:(NSString *)key { return [[self current] objectForKey:key] != nil; }

/* The class to make for a "$class" dictionary: a substitution if one was
 * set, else the class by name, else the first known class among its hints
 * and superclasses. */
- (Class)classFromInfo:(id)info
{
    if (![info isKindOfClass:[NSDictionary class]])
        return Nil;
    NSString *name = [info objectForKey:@"$classname"];
    if (![name isKindOfClass:[NSString class]])
        return Nil;
    Class cls = [self classForClassName:name] ?: [NSKeyedUnarchiver classForClassName:name];
    if (!cls)
        cls = NSClassFromString(name);
    if (cls)
        return cls;
    NSMutableArray *others = [NSMutableArray array];
    id hints = [info objectForKey:@"$classhints"];
    if ([hints isKindOfClass:[NSArray class]])
        [others addObjectsFromArray:hints];
    id chain = [info objectForKey:@"$classes"];
    if ([chain isKindOfClass:[NSArray class]])
        [others addObjectsFromArray:chain];
    for (id n in others) {
        if (![n isKindOfClass:[NSString class]] || [n isEqualToString:@"NSObject"])
            continue;
        /* Swift's private storage classes can't be made from an archive;
         * the public class further up the chain can (freemac 1.262) */
        if ([n hasPrefix:@"_TtCs"] || [n hasPrefix:@"_TtGCs"] || [n hasPrefix:@"__Swift"])
            continue;
        cls = [self classForClassName:n] ?: NSClassFromString(n);
        if (cls) {
            static NSMutableSet *warned;
            static dispatch_once_t warned_once;
            dispatch_once(&warned_once, ^{
              warned = [[NSMutableSet alloc] init];
            });
            os_unfair_lock_lock(&tables_lock);
            BOOL told = [warned containsObject:name];
            if (!told)
                [warned addObject:name];
            os_unfair_lock_unlock(&tables_lock);
            if (told)
                return cls;
            fprintf(stderr, "ferry: an archive has an object of class %s, which this program doesn't have; using %s\n",
                    [name UTF8String], [n UTF8String]);
            return cls;
        }
    }
    return Nil;
}

- (id)objectForUID:(NSUInteger)uid
{
    if (uid == 0)
        return nil;
    if (uid >= _count) {
        [self fail:@"an archive refers to an object that isn't there"];
        return nil;
    }
    if (_state[uid] != UNSEEN)
        return _decoded[uid]; /* a reference back to an object still being made gets what was allocated */
    id raw = [_objects objectAtIndex:uid];
    if (![raw isKindOfClass:[NSDictionary class]] || ![raw objectForKey:@"$class"]) {
        /* Strings, numbers and data stand for themselves. */
        if ([raw isEqual:@"$null"])
            return nil;
        _state[uid] = DONE;
        _decoded[uid] = [raw retain];
        return raw;
    }
    NSUInteger cuid;
    Class cls = Nil;
    if (get_uid([raw objectForKey:@"$class"], &cuid) && cuid < _count)
        cls = [self classFromInfo:[_objects objectAtIndex:cuid]];
    if (!cls) {
        id info = cuid < _count ? [_objects objectAtIndex:cuid] : nil;
        [self fail:[NSString stringWithFormat:@"cannot decode object of class (%@)",
                                              [info isKindOfClass:[NSDictionary class]] ? [info objectForKey:@"$classname"] : @"?"]];
        return nil;
    }
    _state[uid] = DECODING;
    id obj = [cls alloc];
    _decoded[uid] = obj;
    [_stack addObject:raw];
    *seq_slot(&_seq, &_seqCap, [_stack count] - 1) = 0;
    id made = [obj initWithCoder:_facade ?: self];
    [_stack removeLastObject];
    if (made) {
        id after = [made awakeAfterUsingCoder:_facade ?: self];
        if (after != made) {
            [after retain];
            [made release];
            made = after;
        }
    }
    _decoded[uid] = made;
    _state[uid] = DONE;
    return made;
}

/* Arrays, sets and dictionaries are made here from their element UIDs, so
 * that their initWithCoder: gets plain arrays. */
- (id)valueForRaw:(id)raw
{
    NSUInteger uid;
    if (get_uid(raw, &uid))
        return [self objectForUID:uid];
    if ([raw isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:[raw count]];
        for (id r in raw) {
            id o = [self valueForRaw:r];
            if (o)
                [a addObject:o];
        }
        return a;
    }
    return raw;
}

- (BOOL)allowed:(id)obj classes:(NSSet *)classes
{
    if (!obj || !_secure || !classes)
        return YES;
    for (Class c in classes)
        if ([obj isKindOfClass:c])
            return YES;
    return NO;
}

- (id)decodeObjectForKey:(NSString *)key
{
    id raw = [[self current] objectForKey:key];
    if (!raw) {
        /* Arrays and dictionaries written element by element. */
        if ([key isEqualToString:@"NS.objects"] || [key isEqualToString:@"NS.keys"]) {
            NSString *prefix = [key isEqualToString:@"NS.keys"] ? @"NS.key." : @"NS.object.";
            NSMutableArray *a = [NSMutableArray array];
            for (NSUInteger i = 0;; i++) {
                id r = [[self current] objectForKey:[prefix stringByAppendingFormat:@"%lu", (unsigned long)i]];
                if (!r)
                    break;
                id o = [self valueForRaw:r];
                if (o)
                    [a addObject:o];
            }
            return [a count] ? a : nil;
        }
        return nil;
    }
    return [self valueForRaw:raw];
}
/* For nib loading: an archived array with NSNull where an element decoded
 * to nil, so that parallel arrays stay in step. */
- (NSArray *)_decodeArrayKeepingNullsForKey:(NSString *)key
{
    NSUInteger uid;
    if (!get_uid([[self current] objectForKey:key], &uid) || uid >= _count)
        return nil;
    id raw = [_objects objectAtIndex:uid];
    id refs = [raw isKindOfClass:[NSDictionary class]] ? [raw objectForKey:@"NS.objects"] : nil;
    if (![refs isKindOfClass:[NSArray class]])
        return [self decodeObjectForKey:key];
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:[refs count]];
    for (id r in refs)
        [a addObject:[self valueForRaw:r] ?: [NSNull null]];
    return a;
}

- (id)decodeObjectOfClasses:(NSSet *)classes forKey:(NSString *)key
{
    id obj = [self decodeObjectForKey:key];
    if (![self allowed:obj classes:classes]) {
        [self fail:[NSString stringWithFormat:@"value for key '%@' was of unexpected class '%s'", key,
                                              object_getClassName(obj)]];
        return nil;
    }
    return obj;
}
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key
{
    return [self decodeObjectOfClasses:cls ? [NSSet setWithObject:cls] : nil forKey:key];
}
- (id)decodeTopLevelObjectForKey:(NSString *)key error:(NSError **)error
{
    id obj = [self decodeObjectForKey:key];
    if (_error)
        FSetError(error, _error);
    return obj;
}

- (id)scalarForKey:(NSString *)key
{
    id v = [[self current] objectForKey:key];
    return [v isKindOfClass:[NSNumber class]] ? v : nil;
}
- (BOOL)decodeBoolForKey:(NSString *)key { return [[self scalarForKey:key] boolValue]; }
- (int64_t)decodeInt64ForKey:(NSString *)key { return [[self scalarForKey:key] longLongValue]; }
- (double)decodeDoubleForKey:(NSString *)key { return [[self scalarForKey:key] doubleValue]; }
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length
{
    id v = [[self current] objectForKey:key];
    NSUInteger uid;
    if (get_uid(v, &uid))
        v = [self objectForUID:uid];
    if (![v isKindOfClass:[NSData class]]) {
        if (length)
            *length = 0;
        return NULL;
    }
    if (length)
        *length = [v length];
    return [v bytes];
}

/* For copying a collection view's item prototype out of a nib (AppKit's
 * NSNib.m): the objects decoded so far, by their place in the archive, and
 * a fresh reader told to reuse some of them instead of decoding them again. */
- (NSUInteger)_ferryObjectCount { return _count; }
- (id)_ferryDecodedObjectAtIndex:(NSUInteger)index
{
    return index < _count && _state[index] == DONE ? _decoded[index] : nil;
}
- (void)_ferrySeedObject:(id)object atIndex:(NSUInteger)index
{
    if (index == 0 || index >= _count || _state[index] != UNSEEN || !object)
        return;
    _decoded[index] = [object retain];
    _state[index] = DONE;
}
- (id)_ferryDecodeObjectAtIndex:(NSUInteger)index { return [self objectForUID:index]; }
/* An object still being made that hands its place to another (AppKit's
 * class swapper): references back to it get the other (freemac 1.225). */
- (void)_ferryReplaceObjectInProgress:(id)old with:(id)object
{
    for (NSUInteger i = 1; i < _count; i++)
        if (_state[i] == DECODING && _decoded[i] == old) {
            _decoded[i] = object;
            return;
        }
}

/* Values written without a key, in the order they were written. */
- (NSString *)nextUnkeyed
{
    NSUInteger *n = seq_slot(&_seq, &_seqCap, [_stack count] - 1);
    return [NSString stringWithFormat:@"$%lu", (unsigned long)(*n)++];
}
- (BOOL)_ferryAtEnd
{
    NSUInteger *n = seq_slot(&_seq, &_seqCap, [_stack count] - 1);
    return [[self current] objectForKey:[NSString stringWithFormat:@"$%lu", (unsigned long)*n]] == nil;
}
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size
{
    if (size && size < size_of_type(type))
        FRaise(NSInvalidArgumentException, @"*** -[%s %s]: a value of type %s doesn't fit in %lu bytes",
               object_getClassName(self), sel_getName(_cmd), type, (unsigned long)size);
    walk_value(type, data, ^(enum leaf_kind kind, void *p, size_t len) {
      NSString *key = [self nextUnkeyed];
      switch (kind) {
      case LEAF_INT: case LEAF_UINT: write_int(p, len, [self decodeInt64ForKey:key]); break;
      case LEAF_BOOL: *(bool *)p = [self decodeBoolForKey:key]; break;
      case LEAF_FLOAT: *(float *)p = [self decodeFloatForKey:key]; break;
      case LEAF_DOUBLE: *(double *)p = [self decodeDoubleForKey:key]; break;
      /* an object comes retained, as the method's documentation says */
      case LEAF_OBJECT: *(id *)p = [[self decodeObjectForKey:key] retain]; break;
      case LEAF_CLASS: {
          id name = [self decodeObjectForKey:key];
          *(Class *)p = [name isKindOfClass:[NSString class]] ? NSClassFromString(name) : Nil;
          break;
      }
      case LEAF_SEL: {
          id name = [self decodeObjectForKey:key];
          *(SEL *)p = [name isKindOfClass:[NSString class]] ? NSSelectorFromString(name) : NULL;
          break;
      }
      case LEAF_CSTRING: {
          id bytes = [self decodeObjectForKey:key];
          if ([bytes isKindOfClass:[NSData class]]) {
              NSMutableData *copy = [NSMutableData dataWithData:bytes];
              [copy appendBytes:"" length:1];
              *(char **)p = [copy mutableBytes];
          } else {
              *(char **)p = NULL;
          }
          break;
      }
      case LEAF_BYTES: {
          NSUInteger got = 0;
          const uint8_t *b = [self decodeBytesForKey:key returnedLength:&got];
          memset(p, 0, len);
          if (b)
              memcpy(p, b, got < len ? got : len);
          break;
      }
      }
    });
}
- (void)_ferrySetFacade:(NSCoder *)facade { _facade = facade; }
@end

/* ---- NSArchiver and NSUnarchiver ---------------------------------------------------------- */

/* The sequential archivers (freemac 1.221, Ferry 0.45.0), written from
 * Apple's documentation of the two classes. Ferry's NSArchiver writes the
 * values it is given, with or without keys, through a keyed archiver of its
 * own, as a property list marked "FerryArchiver" in place of
 * "NSKeyedArchiver"; NSUnarchiver reads those (and keyed archives) back.
 * The objects being written or read are given the NSArchiver or
 * NSUnarchiver itself, which answers NO to allowsKeyedCoding as a Mac's
 * does, so that an object codes its values in order. Ferry's own classes,
 * which code theirs with keys, may do so here too. An archive a Mac's
 * NSArchiver wrote ("typedstream") isn't read: unarchiving one gives nil. */

NSString *const NSInconsistentArchiveException = @"NSInconsistentArchiveException";

@interface NSKeyedArchiver (FerrySequential)
- (void)_ferrySetFacade:(NSCoder *)facade name:(NSString *)name;
@end
@interface NSKeyedUnarchiver (FerrySequential)
- (void)_ferrySetFacade:(NSCoder *)facade;
- (BOOL)_ferryAtEnd;
@end

static NSMutableDictionary *sequential_names(BOOL decoding)
{
    static NSMutableDictionary *encoded, *decoded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      encoded = [[NSMutableDictionary alloc] init];
      decoded = [[NSMutableDictionary alloc] init];
    });
    return decoding ? decoded : encoded;
}

static void set_sequential_name(BOOL decoding, NSString *from, NSString *to)
{
    os_unfair_lock_lock(&tables_lock);
    if (from && to)
        [sequential_names(decoding) setObject:to forKey:from];
    else if (from)
        [sequential_names(decoding) removeObjectForKey:from];
    os_unfair_lock_unlock(&tables_lock);
}

static NSString *sequential_name(BOOL decoding, NSString *from)
{
    os_unfair_lock_lock(&tables_lock);
    NSString *to = [[[sequential_names(decoding) objectForKey:from] retain] autorelease];
    os_unfair_lock_unlock(&tables_lock);
    return to;
}

@implementation NSArchiver {
    NSKeyedArchiver *_writer;
    NSMutableData *_data;
    NSMutableDictionary *_names;
    BOOL _written;
}

+ (NSData *)archivedDataWithRootObject:(id)rootObject
{
    NSMutableData *data = [NSMutableData data];
    NSArchiver *a = [[self alloc] initForWritingWithMutableData:data];
    [a encodeRootObject:rootObject];
    [a archiverData];
    [a release];
    return data;
}
+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path
{
    return [[self archivedDataWithRootObject:rootObject] writeToFile:path atomically:YES];
}

- (instancetype)initForWritingWithMutableData:(NSMutableData *)mdata
{
    if (!mdata)
        FRaise(NSInvalidArgumentException, @"*** -[NSArchiver initForWritingWithMutableData:]: data is nil");
    if ((self = [super init])) {
        _data = [mdata retain];
        _names = [[NSMutableDictionary alloc] init];
        _writer = [[NSKeyedArchiver alloc] initForWritingWithMutableData:_data];
        [_writer _ferrySetFacade:self name:@"FerryArchiver"];
    }
    return self;
}
- (instancetype)init { return [self initForWritingWithMutableData:[NSMutableData data]]; }
- (void)dealloc
{
    [self archiverData];
    [_writer _ferrySetFacade:nil name:@"FerryArchiver"];
    [_writer release];
    [_data release];
    [_names release];
    [super dealloc];
}

/* The property list is written whole, once the archive is asked for. */
- (NSMutableData *)archiverData
{
    if (!_written) {
        _written = YES;
        [_writer finishEncoding];
    }
    return _data;
}

- (BOOL)allowsKeyedCoding { return NO; }

+ (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName
{
    set_sequential_name(NO, trueName, inArchiveName);
}
+ (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName { return sequential_name(NO, trueName); }
- (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName
{
    if (trueName && inArchiveName)
        [_names setObject:inArchiveName forKey:trueName];
    else if (trueName)
        [_names removeObjectForKey:trueName];
    Class cls = NSClassFromString(trueName);
    if (cls)
        [_writer setClassName:inArchiveName forClass:cls];
}
- (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName
{
    return [_names objectForKey:trueName] ?: [NSArchiver classNameEncodedForTrueClassName:trueName];
}

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    if (_written)
        FRaise(NSInvalidArchiveOperationException, @"*** -[NSArchiver encodeValueOfObjCType:at:]: the archive is already written");
    /* the class names set for all archivers, as each class is first met */
    const char *t = skip_qualifiers(type);
    if (*t == '@' && *(id const *)addr) {
        Class cls = [*(id const *)addr classForArchiver];
        for (Class c = cls; c; c = class_getSuperclass(c)) {
            NSString *name = NSStringFromClass(c);
            NSString *mapped = [_names objectForKey:name] ?: sequential_name(NO, name);
            if (mapped && ![_writer classNameForClass:c])
                [_writer setClassName:mapped forClass:c];
        }
    }
    [_writer encodeValueOfObjCType:type at:addr];
}

/* Keyed values, for Ferry's own classes, which code theirs only so. */
- (void)encodeObject:(id)object forKey:(NSString *)key { [_writer encodeObject:object forKey:key]; }
- (void)encodeConditionalObject:(id)object forKey:(NSString *)key { [_writer encodeConditionalObject:object forKey:key]; }
- (void)encodeBool:(BOOL)value forKey:(NSString *)key { [_writer encodeBool:value forKey:key]; }
- (void)encodeInt64:(int64_t)value forKey:(NSString *)key { [_writer encodeInt64:value forKey:key]; }
- (void)encodeFloat:(float)value forKey:(NSString *)key { [_writer encodeFloat:value forKey:key]; }
- (void)encodeDouble:(double)value forKey:(NSString *)key { [_writer encodeDouble:value forKey:key]; }
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key
{
    [_writer encodeBytes:bytes length:length forKey:key];
}
@end

@implementation NSUnarchiver {
    NSKeyedUnarchiver *_reader;
    NSMutableDictionary *_names;
}

/* A Mac's NSArchiver begins its archives with this header. */
static BOOL is_typedstream(NSData *data)
{
    static const char mark[] = "\x04\x0bstreamtyped";
    return [data length] >= sizeof mark - 1 && !memcmp([data bytes], mark, sizeof mark - 1);
}

+ (id)unarchiveObjectWithData:(NSData *)data
{
    if (!data)
        return nil;
    NSUnarchiver *u = [[self alloc] initForReadingWithData:data];
    id root = [[u decodeObject] retain];
    [u release];
    return [root autorelease];
}
+ (id)unarchiveObjectWithFile:(NSString *)path
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? [self unarchiveObjectWithData:d] : nil;
}

- (instancetype)initForReadingWithData:(NSData *)data
{
    if (!data)
        FRaise(NSInvalidArgumentException, @"*** -[NSUnarchiver initForReadingWithData:]: data is nil");
    if (!(self = [super init]))
        return nil;
    _names = [[NSMutableDictionary alloc] init];
    _reader = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:NULL];
    if (!_reader) {
        static BOOL told;
        if (is_typedstream(data) && !told) {
            told = YES;
            fprintf(stderr, "ferry: an archive written by a Mac's NSArchiver can't be read here; "
                            "the program gets nil in its place\n");
        }
        [self release];
        return nil;
    }
    [_reader setRequiresSecureCoding:NO];
    [_reader setDecodingFailurePolicy:NSDecodingFailurePolicySetErrorAndReturn];
    [_reader _ferrySetFacade:self];
    os_unfair_lock_lock(&tables_lock);
    NSDictionary *names = [[sequential_names(YES) copy] autorelease];
    os_unfair_lock_unlock(&tables_lock);
    for (NSString *archived in names) {
        Class cls = NSClassFromString([names objectForKey:archived]);
        if (cls)
            [_reader setClass:cls forClassName:archived];
    }
    return self;
}
- (void)dealloc
{
    [_reader _ferrySetFacade:nil];
    [_reader release];
    [_names release];
    [super dealloc];
}

- (BOOL)allowsKeyedCoding { return NO; }
- (BOOL)isAtEnd { return [_reader _ferryAtEnd]; }
- (NSError *)error { return [_reader error]; }

+ (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName
{
    set_sequential_name(YES, inArchiveName, trueName);
}
+ (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName
{
    return sequential_name(YES, inArchiveName) ?: inArchiveName;
}
- (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName
{
    if (inArchiveName && trueName)
        [_names setObject:trueName forKey:inArchiveName];
    else if (inArchiveName)
        [_names removeObjectForKey:inArchiveName];
    [_reader setClass:NSClassFromString(trueName) forClassName:inArchiveName];
}
- (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName
{
    return [_names objectForKey:inArchiveName] ?: [NSUnarchiver classNameDecodedForArchiveClassName:inArchiveName];
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size
{
    [_reader decodeValueOfObjCType:type at:data size:size];
}

- (BOOL)containsValueForKey:(NSString *)key { return [_reader containsValueForKey:key]; }
- (id)decodeObjectForKey:(NSString *)key { return [_reader decodeObjectForKey:key]; }
- (BOOL)decodeBoolForKey:(NSString *)key { return [_reader decodeBoolForKey:key]; }
- (int64_t)decodeInt64ForKey:(NSString *)key { return [_reader decodeInt64ForKey:key]; }
- (double)decodeDoubleForKey:(NSString *)key { return [_reader decodeDoubleForKey:key]; }
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length
{
    return [_reader decodeBytesForKey:key returnedLength:length];
}
@end
