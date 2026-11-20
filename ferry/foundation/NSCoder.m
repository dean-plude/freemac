/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSCoder, NSKeyedArchiver and NSKeyedUnarchiver: keyed archives, the
 * format nib files and saved documents use. Written from Apple's public
 * documentation of these classes and of the archive layout (a property
 * list with "$archiver", "$version", "$top" and "$objects", where objects
 * refer to each other by UID and each object names its class through a
 * "$class" entry holding "$classname" and "$classes"). Only keyed coding
 * is supported; the old sequential NSArchiver form is not. */
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
    FRaise(NSInvalidArgumentException, @"*** -[%s %s]: only keyed archivers implement this",
           object_getClassName(self), sel_getName(cmd));
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
@end

/* ---- which class an object is archived as ------------------------------------------- */

/* Foundation's own concrete classes (FArray, NSConcreteString...) archive
 * under their public names, as on a Mac. */
static BOOL private_class(id obj)
{
    const char *n = object_getClassName(obj);
    return (n[0] == 'F' && n[1] >= 'A' && n[1] <= 'Z') || !strncmp(n, "NSConcrete", 10) || !strncmp(n, "__NSCF", 6);
}

@implementation NSObject (NSArchiving)
- (Class)classForCoder { return object_getClass(self); }
- (Class)classForKeyedArchiver { return [self classForCoder]; }
- (id)replacementObjectForCoder:(NSCoder *)coder { return self; }
- (id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)archiver { return [self replacementObjectForCoder:archiver]; }
- (id)awakeAfterUsingCoder:(NSCoder *)coder { return self; }
+ (NSArray *)classFallbacksForKeyedArchiver { return nil; }
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

static NSMutableDictionary *global_class_names(void)
{
    static NSMutableDictionary *names;
    if (!names)
        names = [[NSMutableDictionary alloc] init];
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
    free(_uids.keys);
    free(_uids.vals);
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
    if (name)
        [global_class_names() setObject:name forKey:NSStringFromClass(cls)];
    else
        [global_class_names() removeObjectForKey:NSStringFromClass(cls)];
}
+ (NSString *)classNameForClass:(Class)cls { return [global_class_names() objectForKey:NSStringFromClass(cls)]; }
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
    obj = [obj replacementObjectForKeyedArchiver:self];
    if (!obj)
        return 0;
    NSUInteger *known = ptrmap_find(&_uids, obj, NO);
    if (known)
        return *known;
    Class cls = [obj classForKeyedArchiver];
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
        [obj encodeWithCoder:self];
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
        @"NSKeyedArchiver", @"$archiver", [NSNumber numberWithInt:100000], @"$version",
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
@end

/* ---- NSKeyedUnarchiver ------------------------------------------------------------------- */

static NSMutableDictionary *global_classes(void)
{
    static NSMutableDictionary *classes;
    if (!classes)
        classes = [[NSMutableDictionary alloc] init];
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
    if (cls)
        [global_classes() setObject:cls forKey:name];
    else
        [global_classes() removeObjectForKey:name];
}
+ (Class)classForClassName:(NSString *)name { return [global_classes() objectForKey:name]; }
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
        cls = [self classForClassName:n] ?: NSClassFromString(n);
        if (cls) {
            static NSMutableSet *warned;
            if (!warned)
                warned = [[NSMutableSet alloc] init];
            if ([warned containsObject:name])
                return cls;
            [warned addObject:name];
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
@end
