/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSDictionary, NSMutableDictionary, NSSet and
 * NSMutableSet. All four keep their objects in one kind of open-addressing
 * hash table (struct fmap), using -hash and -isEqual: as a Mac does.
 * Dictionaries copy their keys; sets and values are retained. */
#import "FInternal.h"

#define TOMB ((id)1)

struct fmap {
    id *keys, *vals; /* vals is NULL for a set */
    NSUInteger cap, count, used;
};

static void fmap_init(struct fmap *m, NSUInteger n, BOOL withValues)
{
    NSUInteger cap = 8;
    while (cap < n * 2)
        cap *= 2;
    m->cap = cap;
    m->count = m->used = 0;
    m->keys = calloc(cap, sizeof(id));
    m->vals = withValues ? calloc(cap, sizeof(id)) : NULL;
}

static void fmap_free(struct fmap *m)
{
    for (NSUInteger i = 0; i < m->cap; i++) {
        if (m->keys[i] && m->keys[i] != TOMB) {
            [m->keys[i] release];
            if (m->vals)
                [m->vals[i] release];
        }
    }
    free(m->keys);
    free(m->vals);
    m->keys = m->vals = NULL;
    m->cap = m->count = m->used = 0;
}

static NSUInteger fmap_find(struct fmap *m, id key)
{
    if (!key || !m->cap)
        return NSNotFound;
    NSUInteger mask = m->cap - 1, i = [key hash] & mask;
    for (NSUInteger probes = 0; probes < m->cap; probes++, i = (i + 1) & mask) {
        id k = m->keys[i];
        if (!k)
            return NSNotFound;
        if (k != TOMB && (k == key || [k isEqual:key]))
            return i;
    }
    return NSNotFound;
}

static void fmap_put(struct fmap *m, id key, id val);

static void fmap_grow(struct fmap *m)
{
    struct fmap old = *m;
    fmap_init(m, old.count + 1, old.vals != NULL);
    for (NSUInteger i = 0; i < old.cap; i++)
        if (old.keys[i] && old.keys[i] != TOMB)
            fmap_put(m, old.keys[i], old.vals ? old.vals[i] : nil);
    free(old.keys);
    free(old.vals);
}

/* Takes over one reference to key and to val. */
static void fmap_put(struct fmap *m, id key, id val)
{
    NSUInteger at = fmap_find(m, key);
    if (at != NSNotFound) {
        [key release];
        if (m->vals) {
            id old = m->vals[at];
            m->vals[at] = val;
            [old release];
        } else {
            [val release];
        }
        return;
    }
    if ((m->used + 1) * 4 > m->cap * 3)
        fmap_grow(m);
    NSUInteger mask = m->cap - 1, i = [key hash] & mask;
    while (m->keys[i] && m->keys[i] != TOMB)
        i = (i + 1) & mask;
    if (!m->keys[i])
        m->used++;
    m->keys[i] = key;
    if (m->vals)
        m->vals[i] = val;
    m->count++;
}

static void fmap_remove(struct fmap *m, id key)
{
    NSUInteger at = fmap_find(m, key);
    if (at == NSNotFound)
        return;
    id k = m->keys[at], v = m->vals ? m->vals[at] : nil;
    m->keys[at] = TOMB;
    if (m->vals)
        m->vals[at] = nil;
    m->count--;
    [k release];
    [v release];
}

/* Fills keys (and vals) with the live entries; returns how many. */
static NSUInteger fmap_entries(struct fmap *m, id *keys, id *vals)
{
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < m->cap; i++) {
        if (m->keys[i] && m->keys[i] != TOMB) {
            if (keys)
                keys[n] = m->keys[i];
            if (vals)
                vals[n] = m->vals[i];
            n++;
        }
    }
    return n;
}

static NSUInteger fmap_enumerate(struct fmap *m, NSFastEnumerationState *state, id *buffer, NSUInteger len)
{
    NSUInteger k = 0, i = state->state;
    while (i < m->cap && k < len) {
        if (m->keys[i] && m->keys[i] != TOMB)
            buffer[k++] = m->keys[i];
        i++;
    }
    state->state = i;
    state->itemsPtr = buffer;
    return k;
}

static unsigned long never_mutated;

@interface FDictionary : NSDictionary {
@public
    struct fmap _m;
}
@end

@interface FMutableDictionary : NSMutableDictionary {
@public
    struct fmap _m;
    unsigned long _mutations;
}
@end

@interface FSet : NSSet {
@public
    struct fmap _m;
}
@end

@interface FMutableSet : NSMutableSet {
@public
    struct fmap _m;
    unsigned long _mutations;
}
@end

/* ---- NSDictionary --------------------------------------------------------------- */

@implementation NSDictionary
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSDictionary class])
        return [FDictionary allocWithZone:zone];
    if (self == [NSMutableDictionary class])
        return [FMutableDictionary allocWithZone:zone];
    return [super allocWithZone:zone];
}
- (NSUInteger)count { return 0; }
- (id)objectForKey:(id)key { return nil; }
- (NSEnumerator *)keyEnumerator { return [[self allKeys] objectEnumerator]; }
/* The empty NSDictionary is one shared object that is never freed, as on a
 * Mac: Swift's runtime keeps the one it is given for every error it bridges
 * without taking a reference (freemac 1.271, Stats) */
extern struct ferry_constant_dictionary __NSDictionary0__struct;
+ (instancetype)dictionary
{
    if (self == [NSDictionary class])
        return (id)(void *)&__NSDictionary0__struct;
    return [[[self alloc] init] autorelease];
}
+ (instancetype)dictionaryWithObject:(id)object forKey:(id)key
{
    return [[[self alloc] initWithObjects:&object forKeys:&key count:1] autorelease];
}
+ (instancetype)dictionaryWithObjects:(const id[])objects forKeys:(const id<NSCopying>[])keys count:(NSUInteger)count
{
    return [[[self alloc] initWithObjects:objects forKeys:keys count:count] autorelease];
}
+ (instancetype)dictionaryWithObjectsAndKeys:(id)first, ...
{
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    va_list ap;
    va_start(ap, first);
    for (id v = first; v; v = va_arg(ap, id)) {
        id k = va_arg(ap, id);
        if (!k)
            FRaise(NSInvalidArgumentException, @"+[NSDictionary dictionaryWithObjectsAndKeys:]: second object of each "
                                                @"pair must be non-nil.");
        [m setObject:v forKey:k];
    }
    va_end(ap);
    return [self dictionaryWithDictionary:m];
}
+ (instancetype)dictionaryWithDictionary:(NSDictionary *)dict
{
    return [[[self alloc] initWithDictionary:dict] autorelease];
}
+ (instancetype)dictionaryWithObjects:(NSArray *)objects forKeys:(NSArray *)keys
{
    NSUInteger n = [objects count];
    if ([keys count] != n)
        FRaise(NSInvalidArgumentException, @"*** -[NSDictionary initWithObjects:forKeys:]: count of objects (%lu) "
                                            @"differs from count of keys (%lu)",
               (unsigned long)n, (unsigned long)[keys count]);
    id *o = malloc((n ? n : 1) * sizeof(id)), *k = malloc((n ? n : 1) * sizeof(id));
    [objects getObjects:o range:NSMakeRange(0, n)];
    [keys getObjects:k range:NSMakeRange(0, n)];
    NSDictionary *d = [self dictionaryWithObjects:o forKeys:k count:n];
    free(o);
    free(k);
    return d;
}
+ (NSDictionary *)dictionaryWithContentsOfFile:(NSString *)path
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    id plist = d ? FParsePlist(d, NSPropertyListImmutable, NULL) : nil;
    if (![plist isKindOfClass:[NSDictionary class]])
        return nil;
    if ([self isSubclassOfClass:[NSMutableDictionary class]])
        return [[plist mutableCopy] autorelease];
    return plist;
}
- (instancetype)init { return [self initWithObjects:NULL forKeys:NULL count:0]; }
- (instancetype)initWithObjects:(const id[])objects forKeys:(const id<NSCopying>[])keys count:(NSUInteger)count
{
    [self release];
    FRaise(NSInvalidArgumentException, @"*** -[NSDictionary initWithObjects:forKeys:count:]: method only defined for "
                                        @"abstract class");
}
- (instancetype)initWithObjectsAndKeys:(id)first, ...
{
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    va_list ap;
    va_start(ap, first);
    for (id v = first; v; v = va_arg(ap, id)) {
        id k = va_arg(ap, id);
        if (!k)
            FRaise(NSInvalidArgumentException, @"-[NSDictionary initWithObjectsAndKeys:]: second object of each pair "
                                                @"must be non-nil.");
        [m setObject:v forKey:k];
    }
    va_end(ap);
    return [self initWithDictionary:m];
}
- (instancetype)initWithContentsOfFile:(NSString *)path
{
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!d) {
        [self release];
        return nil;
    }
    return [self initWithDictionary:d];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url { return [self initWithContentsOfFile:[url path]]; }
/* freemac 1.224: a property list (of this class) read from a file URL */
static id plist_at_url(NSURL *url, Class cls, NSError **error)
{
    NSData *data = [url isFileURL] ? [NSData dataWithContentsOfFile:[url path] options:0 error:error] : nil;
    if (!data) {
        if (error && ![url isFileURL])
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError userInfo:nil];
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
    if (plist && ![plist isKindOfClass:cls]) {
        plist = nil;
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError userInfo:nil];
    }
    return plist;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
    NSDictionary *o = plist_at_url(url, [NSDictionary class], error);
    if (!o) {
        [self release];
        return nil;
    }
    return [self initWithDictionary:o];
}
+ (id)dictionaryWithContentsOfURL:(NSURL *)url
{
    return [[[self alloc] initWithContentsOfURL:url error:NULL] autorelease];
}
+ (id)dictionaryWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
    return [[[self alloc] initWithContentsOfURL:url error:error] autorelease];
}
/* The values are copied; keys always are (freemac 1.221, Ferry 0.45.0). */
- (instancetype)initWithDictionary:(NSDictionary *)dict copyItems:(BOOL)flag
{
    if (!flag)
        return [self initWithDictionary:dict];
    NSUInteger n = [dict count];
    id *k = malloc((n ? n : 1) * sizeof(id)), *v = malloc((n ? n : 1) * sizeof(id));
    NSUInteger i = 0;
    for (id key in dict) {
        k[i] = key;
        v[i] = [[dict objectForKey:key] copyWithZone:NULL];
        i++;
    }
    self = [self initWithObjects:v forKeys:k count:i];
    while (i--)
        [v[i] release];
    free(k);
    free(v);
    return self;
}
- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    NSUInteger n = [dict count];
    id *k = malloc((n ? n : 1) * sizeof(id)), *v = malloc((n ? n : 1) * sizeof(id));
    NSUInteger i = 0;
    for (id key in dict) {
        k[i] = key;
        v[i] = [dict objectForKey:key];
        i++;
    }
    self = [self initWithObjects:v forKeys:k count:i];
    free(k);
    free(v);
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return [[NSDictionary allocWithZone:zone] initWithDictionary:self]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableDictionary allocWithZone:zone] initWithDictionary:self]; }
- (id)objectForKeyedSubscript:(id)key { return [self objectForKey:key]; }
/* what Swift's bridged dictionaries call for a subscript (freemac 1.271) */
- (id)__swift_objectForKeyedSubscript:(id)key { return [self objectForKey:key]; }
/* A key starting with "@" is a key of the dictionary object itself (@count). */
- (id)valueForKey:(NSString *)key
{
    if ([key hasPrefix:@"@"] && [key length] > 1)
        return [super valueForKey:[key substringFromIndex:1]];
    return [self objectForKey:key];
}
- (NSArray *)allKeys
{
    NSMutableArray *m = [NSMutableArray array];
    for (id k in self)
        [m addObject:k];
    return [NSArray arrayWithArray:m];
}
- (NSArray *)allValues
{
    NSMutableArray *m = [NSMutableArray array];
    for (id k in self)
        [m addObject:[self objectForKey:k]];
    return [NSArray arrayWithArray:m];
}
- (NSArray *)allKeysForObject:(id)obj
{
    NSMutableArray *m = [NSMutableArray array];
    for (id k in self)
        if ([[self objectForKey:k] isEqual:obj])
            [m addObject:k];
    return [NSArray arrayWithArray:m];
}
- (NSArray *)keysSortedByValueUsingSelector:(SEL)comparator
{
    NSArray *keys = [self allKeys];
    NSUInteger n = [keys count];
    id *k = malloc((n ? n : 1) * sizeof(id));
    [keys getObjects:k range:NSMakeRange(0, n)];
    /* insertion sort on the values keeps equal values in key order */
    for (NSUInteger i = 1; i < n; i++) {
        id key = k[i], v = [self objectForKey:key];
        NSUInteger j = i;
        while (j > 0 &&
               ((NSComparisonResult (*)(id, SEL, id))objc_msgSend)([self objectForKey:k[j - 1]], comparator, v) ==
                   NSOrderedDescending) {
            k[j] = k[j - 1];
            j--;
        }
        k[j] = key;
    }
    NSArray *a = [NSArray arrayWithObjects:k count:n];
    free(k);
    return a;
}
/* keys in the order of their values, equal values keeping key order (freemac 1.258) */
- (NSArray *)keysSortedByValueWithOptions:(NSSortOptions)opts usingComparator:(NSComparator)cmptr
{
    (void)opts;
    NSArray *keys = [self allKeys];
    NSUInteger n = [keys count];
    id *k = malloc((n ? n : 1) * sizeof(id));
    [keys getObjects:k range:NSMakeRange(0, n)];
    for (NSUInteger i = 1; i < n; i++) {
        id key = k[i], v = [self objectForKey:key];
        NSUInteger j = i;
        while (j > 0 && cmptr([self objectForKey:k[j - 1]], v) == NSOrderedDescending) {
            k[j] = k[j - 1];
            j--;
        }
        k[j] = key;
    }
    NSArray *a = [NSArray arrayWithObjects:k count:n];
    free(k);
    return a;
}
- (NSArray *)keysSortedByValueUsingComparator:(NSComparator)cmptr
{
    return [self keysSortedByValueWithOptions:0 usingComparator:cmptr];
}
- (BOOL)isEqualToDictionary:(NSDictionary *)other
{
    if (other == self)
        return YES;
    if ([other count] != [self count])
        return NO;
    for (id k in self)
        if (![[self objectForKey:k] isEqual:[other objectForKey:k]])
            return NO;
    return YES;
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSDictionary class]] && [self isEqualToDictionary:other];
}
- (NSUInteger)hash { return [self count]; }
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id, id, BOOL *))block
{
    BOOL stop = NO;
    for (id k in [self allKeys]) {
        block(k, [self objectForKey:k], &stop);
        if (stop)
            break;
    }
}
- (NSEnumerator *)objectEnumerator { return [[self allValues] objectEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    if (state->state == 0) {
        state->mutationsPtr = &never_mutated;
        state->extra[0] = (unsigned long)[[self keyEnumerator] retain];
        state->state = 1;
    }
    NSEnumerator *e = (NSEnumerator *)state->extra[0];
    if (!e)
        return 0;
    NSUInteger k = 0;
    id o;
    while (k < len && (o = [e nextObject]))
        buffer[k++] = o;
    if (k == 0) {
        state->extra[0] = 0;
        [e autorelease];
    }
    state->itemsPtr = buffer;
    return k;
}
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically
{
    NSData *d = FWriteXMLPlist(self);
    return d && [d writeToFile:path atomically:atomically];
}
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically
{
    NSData *d = FWriteXMLPlist(self);
    return d && [d writeToURL:url options:atomically ? NSDataWritingAtomic : 0 error:NULL];
}
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error
{
    NSData *d = FWriteXMLPlist(self);
    if (!d) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListWriteInvalidError userInfo:nil]);
        return NO;
    }
    return [d writeToURL:url options:NSDataWritingAtomic error:error];
}
- (NSString *)description { return FDescribe(self, 0); }
- (NSString *)descriptionInStringsFileFormat { return FDescribe(self, 0); }
- (NSString *)descriptionWithLocale:(id)locale { return FDescribe(self, 0); }
- (unsigned long long)fileSize { return [[self objectForKey:NSFileSize] unsignedLongLongValue]; }
- (NSString *)fileType { return [self objectForKey:NSFileType]; }
- (NSDate *)fileModificationDate { return [self objectForKey:NSFileModificationDate]; }
@end

static void put_pairs(struct fmap *m, const id *objects, const id *keys, NSUInteger count, id self)
{
    for (NSUInteger i = 0; i < count; i++) {
        if (!objects[i] || !keys[i])
            FRaise(NSInvalidArgumentException,
                   @"*** -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil %@ from "
                   @"objects[%lu]",
                   objects[i] ? @"key" : @"object", (unsigned long)i);
        fmap_put(m, [keys[i] copy], [objects[i] retain]);
    }
}

@implementation FDictionary
- (instancetype)initWithObjects:(const id[])objects forKeys:(const id<NSCopying>[])keys count:(NSUInteger)count
{
    fmap_init(&_m, count, YES);
    put_pairs(&_m, objects, keys, count, self);
    return self;
}
- (void)dealloc
{
    fmap_free(&_m);
    [super dealloc];
}
- (NSUInteger)count { return _m.count; }
- (id)objectForKey:(id)key
{
    NSUInteger at = fmap_find(&_m, key);
    return at == NSNotFound ? nil : _m.vals[at];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    state->mutationsPtr = &never_mutated;
    return fmap_enumerate(&_m, state, buffer, len);
}
- (NSEnumerator *)keyEnumerator
{
    id *k = malloc((_m.count ? _m.count : 1) * sizeof(id));
    NSUInteger n = fmap_entries(&_m, k, NULL);
    NSArray *a = [NSArray arrayWithObjects:k count:n];
    free(k);
    return [a objectEnumerator];
}
@end

/* ---- NSConstantDictionary: a literal dictionary kept in the program ------------
 * Newer clang writes a literal such as @{@"a": @YES} into the program itself,
 * as an object of the class NSConstantDictionary: the class, an options word,
 * the count, then pointers to the keys and to the objects. kitty's GLFW holds
 * these. The fields sit right after the class pointer, read by hand. */
@interface NSConstantDictionary : NSDictionary
@end

struct ferry_constant_dictionary {
    Class isa;
    NSUInteger options;
    NSUInteger count;
    const id *keys;
    const id *objects;
};
#define CONSTANT_DICT(d) ((const struct ferry_constant_dictionary *)(const void *)(d))

@implementation NSConstantDictionary
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }
- (void)dealloc { /* kept in the program, never freed */ if (0) [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)count { return CONSTANT_DICT(self)->count; }
- (id)objectForKey:(id)key
{
    if (!key)
        return nil;
    const struct ferry_constant_dictionary *d = CONSTANT_DICT(self);
    for (NSUInteger i = 0; i < d->count; i++)
        if (d->keys[i] == key || [d->keys[i] isEqual:key])
            return d->objects[i];
    return nil;
}
- (NSEnumerator *)keyEnumerator
{
    return [[NSArray arrayWithObjects:CONSTANT_DICT(self)->keys count:CONSTANT_DICT(self)->count] objectEnumerator];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    const struct ferry_constant_dictionary *d = CONSTANT_DICT(self);
    state->mutationsPtr = &never_mutated;
    if (state->state >= d->count)
        return 0;
    state->itemsPtr = (id *)d->keys + state->state;
    NSUInteger n = d->count - state->state;
    state->state = d->count;
    return n;
}
@end

/* clang refers to these for the literal @{}: older clang reads the pointer
 * __NSDictionary0__, newer clang uses __NSDictionary0__struct itself as the
 * empty dictionary (freemac 1.271, Stats) */
F_EXPORT id __NSDictionary0__;
id __NSDictionary0__;
F_EXPORT struct ferry_constant_dictionary __NSDictionary0__struct;
struct ferry_constant_dictionary __NSDictionary0__struct;

__attribute__((constructor)) static void empty_dictionary_init(void)
{
    __NSDictionary0__ = [[NSDictionary alloc] init];
    __NSDictionary0__struct.isa = [NSConstantDictionary class];
}

/* ---- NSMutableDictionary -------------------------------------------------------- */

@implementation NSMutableDictionary
/* NSDictionary's make a mutable copy when called on a mutable class */
+ (NSMutableDictionary *)dictionaryWithContentsOfFile:(NSString *)path
{
    return (NSMutableDictionary *)[super dictionaryWithContentsOfFile:path];
}
+ (NSMutableDictionary *)dictionaryWithContentsOfURL:(NSURL *)url
{
    return (NSMutableDictionary *)[super dictionaryWithContentsOfURL:url];
}
+ (instancetype)dictionaryWithCapacity:(NSUInteger)capacity
{
    return [[[self alloc] initWithCapacity:capacity] autorelease];
}
- (instancetype)initWithCapacity:(NSUInteger)capacity { return [self init]; }
- (id)copyWithZone:(NSZone *)zone { return [[NSDictionary allocWithZone:zone] initWithDictionary:self]; }
- (void)setObject:(id)object forKey:(id)key {}
- (void)removeObjectForKey:(id)key {}
- (void)setObject:(id)object forKeyedSubscript:(id)key
{
    if (object)
        [self setObject:object forKey:key];
    else
        [self removeObjectForKey:key];
}
/* Observers of the key hear of a change made by key-value coding. */
- (void)setValue:(id)value forKey:(NSString *)key
{
    BOOL observed = FKVOIsObserved(self);
    if (observed)
        [self willChangeValueForKey:key];
    [self setObject:value forKeyedSubscript:key];
    if (observed)
        [self didChangeValueForKey:key];
}
- (void)removeObjectsForKeys:(NSArray *)keys
{
    for (id k in keys)
        [self removeObjectForKey:k];
}
- (void)removeAllObjects { [self removeObjectsForKeys:[self allKeys]]; }
- (void)addEntriesFromDictionary:(NSDictionary *)other
{
    for (id k in other)
        [self setObject:[other objectForKey:k] forKey:k];
}
- (void)setDictionary:(NSDictionary *)other
{
    [other retain];
    [self removeAllObjects];
    [self addEntriesFromDictionary:other];
    [other release];
}
@end

@implementation FMutableDictionary
- (instancetype)init { return [self initWithCapacity:0]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity
{
    fmap_init(&_m, capacity, YES);
    return self;
}
- (instancetype)initWithObjects:(const id[])objects forKeys:(const id<NSCopying>[])keys count:(NSUInteger)count
{
    fmap_init(&_m, count, YES);
    put_pairs(&_m, objects, keys, count, self);
    return self;
}
- (void)dealloc
{
    fmap_free(&_m);
    [super dealloc];
}
- (NSUInteger)count { return _m.count; }
- (id)objectForKey:(id)key
{
    NSUInteger at = fmap_find(&_m, key);
    return at == NSNotFound ? nil : _m.vals[at];
}
- (void)setObject:(id)object forKey:(id)key
{
    if (!object)
        FRaise(NSInvalidArgumentException, @"*** -[__NSDictionaryM setObject:forKey:]: object cannot be nil (key: %@)",
               key);
    if (!key)
        FRaise(NSInvalidArgumentException, @"*** -[__NSDictionaryM setObject:forKey:]: key cannot be nil");
    [object retain];
    fmap_put(&_m, [key copy], object);
    _mutations++;
}
- (void)removeObjectForKey:(id)key
{
    fmap_remove(&_m, key);
    _mutations++;
}
- (void)removeAllObjects
{
    fmap_free(&_m);
    fmap_init(&_m, 0, YES);
    _mutations++;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    state->mutationsPtr = &_mutations;
    return fmap_enumerate(&_m, state, buffer, len);
}
- (NSEnumerator *)keyEnumerator
{
    id *k = malloc((_m.count ? _m.count : 1) * sizeof(id));
    NSUInteger n = fmap_entries(&_m, k, NULL);
    NSArray *a = [NSArray arrayWithObjects:k count:n];
    free(k);
    return [a objectEnumerator];
}
@end

/* ---- NSSet ------------------------------------------------------------------------ */

@implementation NSSet
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSSet class])
        return [FSet allocWithZone:zone];
    if (self == [NSMutableSet class])
        return [FMutableSet allocWithZone:zone];
    return [super allocWithZone:zone];
}
- (NSUInteger)count { return 0; }
- (id)member:(id)obj { return nil; }
- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }
+ (instancetype)set { return [[[self alloc] init] autorelease]; }
+ (instancetype)setWithObject:(id)obj { return [[[self alloc] initWithObjects:&obj count:1] autorelease]; }
+ (instancetype)setWithObjects:(const id[])objects count:(NSUInteger)count
{
    return [[[self alloc] initWithObjects:objects count:count] autorelease];
}
+ (instancetype)setWithArray:(NSArray *)array
{
    NSUInteger n = [array count];
    id *o = malloc((n ? n : 1) * sizeof(id));
    [array getObjects:o range:NSMakeRange(0, n)];
    NSSet *s = [self setWithObjects:o count:n];
    free(o);
    return s;
}
+ (instancetype)setWithObjects:(id)first, ...
{
    NSMutableArray *tmp = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id))
        [tmp addObject:o];
    va_end(ap);
    return [self setWithArray:tmp];
}
- (instancetype)init { return [self initWithObjects:NULL count:0]; }
/* The other initialisers, as the class methods (freemac 1.224, Ferry
 * 0.48.0). */
- (instancetype)initWithObjects:(id)first, ...
{
    NSMutableArray *tmp = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id))
        [tmp addObject:o];
    va_end(ap);
    return [self initWithArray:tmp];
}
- (instancetype)initWithArray:(NSArray *)array
{
    NSUInteger n = [array count];
    id *objs = malloc((n ? n : 1) * sizeof(id));
    [array getObjects:objs range:NSMakeRange(0, n)];
    self = [self initWithObjects:objs count:n];
    free(objs);
    return self;
}
- (instancetype)initWithSet:(NSSet *)set { return [self initWithSet:set copyItems:NO]; }
- (instancetype)initWithSet:(NSSet *)set copyItems:(BOOL)flag
{
    NSArray *all = [set allObjects];
    if (flag)
        all = [[[NSArray alloc] initWithArray:all copyItems:YES] autorelease];
    NSUInteger n = [all count];
    id *objs = malloc((n ? n : 1) * sizeof(id));
    [all getObjects:objs range:NSMakeRange(0, n)];
    self = [self initWithObjects:objs count:n];
    free(objs);
    return self;
}
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    if (!count)
        return self;   /* a subclass of its own that calls [super init] (freemac 1.225) */
    [self release];
    FRaise(NSInvalidArgumentException, @"*** -[NSSet initWithObjects:count:]: method only defined for abstract class");
}
- (id)copyWithZone:(NSZone *)zone { return [[NSSet setWithArray:[self allObjects]] retain]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableSet setWithArray:[self allObjects]] retain]; }
- (BOOL)containsObject:(id)obj { return [self member:obj] != nil; }
- (id)anyObject
{
    for (id o in self)
        return o;
    return nil;
}
- (NSArray *)allObjects
{
    NSMutableArray *m = [NSMutableArray array];
    for (id o in self)
        [m addObject:o];
    return [NSArray arrayWithArray:m];
}
+ (instancetype)setWithSet:(NSSet *)set { return [self setWithArray:[set allObjects]]; }
/* NSSet reference: each object, in no set order, as the array's own methods. */
- (void)makeObjectsPerformSelector:(SEL)sel { [[self allObjects] makeObjectsPerformSelector:sel]; }
- (void)makeObjectsPerformSelector:(SEL)sel withObject:(id)arg
{
    [[self allObjects] makeObjectsPerformSelector:sel withObject:arg];
}
- (BOOL)isEqualToSet:(NSSet *)other { return [self isEqual:other]; }
- (BOOL)intersectsSet:(NSSet *)other
{
    for (id o in self)
        if ([other containsObject:o])
            return YES;
    return NO;
}
- (NSSet *)setByAddingObject:(id)obj { return [self setByAddingObjectsFromArray:@[ obj ]]; }
- (NSSet *)setByAddingObjectsFromSet:(NSSet *)other { return [self setByAddingObjectsFromArray:[other allObjects]]; }
- (NSSet *)setByAddingObjectsFromArray:(NSArray *)other
{
    NSMutableSet *m = [[self mutableCopy] autorelease];
    [m addObjectsFromArray:other];
    return [NSSet setWithSet:m];
}
- (BOOL)isSubsetOfSet:(NSSet *)other
{
    for (id o in self)
        if (![other containsObject:o])
            return NO;
    return YES;
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSSet class]] && [other count] == [self count] && [self isSubsetOfSet:other];
}
- (NSUInteger)hash { return [self count]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    return [[self allObjects] countByEnumeratingWithState:state objects:buffer count:len];
}
- (NSString *)description { return FDescribe(self, 0); }
@end

@implementation FSet
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    fmap_init(&_m, count, NO);
    for (NSUInteger i = 0; i < count; i++) {
        if (!objects[i])
            FRaise(NSInvalidArgumentException, @"*** -[NSSet initWithObjects:count:]: attempt to insert nil object "
                                                @"from objects[%lu]",
                   (unsigned long)i);
        fmap_put(&_m, [objects[i] retain], nil);
    }
    return self;
}
- (void)dealloc
{
    fmap_free(&_m);
    [super dealloc];
}
- (NSUInteger)count { return _m.count; }
- (id)member:(id)obj
{
    NSUInteger at = fmap_find(&_m, obj);
    return at == NSNotFound ? nil : _m.keys[at];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    state->mutationsPtr = &never_mutated;
    return fmap_enumerate(&_m, state, buffer, len);
}
@end

@implementation NSMutableSet
+ (instancetype)setWithCapacity:(NSUInteger)capacity { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [[NSSet setWithArray:[self allObjects]] retain]; }
- (void)addObject:(id)obj {}
- (void)removeObject:(id)obj {}
- (void)removeAllObjects
{
    for (id o in [self allObjects])
        [self removeObject:o];
}
- (void)addObjectsFromArray:(NSArray *)array
{
    for (id o in array)
        [self addObject:o];
}
- (void)unionSet:(NSSet *)other
{
    for (id o in other)
        [self addObject:o];
}
- (void)minusSet:(NSSet *)other
{
    for (id o in other)
        [self removeObject:o];
}
- (void)intersectSet:(NSSet *)other
{
    for (id o in [self allObjects])
        if (![other containsObject:o])
            [self removeObject:o];
}
- (void)setSet:(NSSet *)other
{
    [self removeAllObjects];
    [self unionSet:other];
}
@end

@implementation FMutableSet
- (instancetype)init
{
    fmap_init(&_m, 0, NO);
    return self;
}
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    fmap_init(&_m, count, NO);
    for (NSUInteger i = 0; i < count; i++)
        [self addObject:objects[i]];
    return self;
}
- (void)dealloc
{
    fmap_free(&_m);
    [super dealloc];
}
- (NSUInteger)count { return _m.count; }
- (id)member:(id)obj
{
    NSUInteger at = fmap_find(&_m, obj);
    return at == NSNotFound ? nil : _m.keys[at];
}
- (void)addObject:(id)obj
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[__NSSetM addObject:]: object cannot be nil");
    if (fmap_find(&_m, obj) != NSNotFound)
        return;
    fmap_put(&_m, [obj retain], nil);
    _mutations++;
}
- (void)removeObject:(id)obj
{
    fmap_remove(&_m, obj);
    _mutations++;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    state->mutationsPtr = &_mutations;
    return fmap_enumerate(&_m, state, buffer, len);
}
@end
