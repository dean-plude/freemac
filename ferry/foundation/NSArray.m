/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSArray, NSMutableArray and NSEnumerator. NSArray is a
 * class cluster as on a Mac: the public classes describe the behaviour in
 * terms of a few primitive methods, and allocating one gives a private
 * concrete class (FArray, FMutableArray) that stores the objects. */
#import "FInternal.h"

@interface FArray : NSArray {
@public
    id *_items;
    NSUInteger _count;
}
@end

@interface FMutableArray : NSMutableArray {
@public
    id *_items;
    NSUInteger _count, _cap;
    unsigned long _mutations;
}
@end

@interface FListEnumerator : NSEnumerator {
    NSArray *_array;
    NSUInteger _next;
    BOOL _reverse;
}
- (instancetype)initWithArray:(NSArray *)array reverse:(BOOL)reverse;
@end

static unsigned long never_mutated;

/* ---- sorting: a stable merge sort, as Mac Foundation's sorts are stable ---- */

typedef NSComparisonResult (*fcompare)(id a, id b, void *ctx);

static void merge_sort(id *items, NSUInteger n, fcompare cmp, void *ctx)
{
    if (n < 2)
        return;
    id *tmp = malloc(n * sizeof(id));
    for (NSUInteger width = 1; width < n; width *= 2) {
        for (NSUInteger lo = 0; lo < n; lo += 2 * width) {
            NSUInteger mid = lo + width < n ? lo + width : n;
            NSUInteger hi = lo + 2 * width < n ? lo + 2 * width : n;
            NSUInteger i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                tmp[k++] = cmp(items[j], items[i], ctx) == NSOrderedAscending ? items[j++] : items[i++];
            while (i < mid)
                tmp[k++] = items[i++];
            while (j < hi)
                tmp[k++] = items[j++];
        }
        memcpy(items, tmp, n * sizeof(id));
    }
    free(tmp);
}

static NSComparisonResult by_selector(id a, id b, void *ctx)
{
    return ((NSComparisonResult (*)(id, SEL, id))objc_msgSend)(a, (SEL)ctx, b);
}

static NSComparisonResult by_block(id a, id b, void *ctx)
{
    return ((NSComparator)ctx)(a, b);
}

void FSortObjects(id *items, NSUInteger n, SEL selector)
{
    merge_sort(items, n, by_selector, (void *)selector);
}

/* ---- NSArray ------------------------------------------------------------------- */

static void range_check(id self, SEL _cmd, NSUInteger index, NSUInteger count)
{
    if (index >= count) {
        if (count == 0)
            FRaise(NSRangeException, @"*** -[%s %s]: index %lu beyond bounds for empty array",
                   object_getClassName(self), sel_getName(_cmd), (unsigned long)index);
        FRaise(NSRangeException, @"*** -[%s %s]: index %lu beyond bounds [0 .. %lu]", object_getClassName(self),
               sel_getName(_cmd), (unsigned long)index, (unsigned long)count - 1);
    }
}

@implementation NSArray
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSArray class])
        return [FArray allocWithZone:zone];
    if (self == [NSMutableArray class])
        return [FMutableArray allocWithZone:zone];
    return [super allocWithZone:zone];
}
- (NSUInteger)count { return 0; }
- (id)objectAtIndex:(NSUInteger)index
{
    range_check(self, _cmd, index, 0);
    return nil;
}
- (void)getObjects:(id *)objects range:(NSRange)range
{
    for (NSUInteger i = 0; i < range.length; i++)
        objects[i] = [self objectAtIndex:range.location + i];
}
+ (instancetype)array { return [[[self alloc] init] autorelease]; }
+ (instancetype)arrayWithObject:(id)obj { return [[[self alloc] initWithObjects:&obj count:1] autorelease]; }
+ (instancetype)arrayWithObjects:(const id[])objects count:(NSUInteger)count
{
    return [[[self alloc] initWithObjects:objects count:count] autorelease];
}
+ (instancetype)arrayWithArray:(NSArray *)array { return [[[self alloc] initWithArray:array] autorelease]; }
+ (instancetype)arrayWithObjects:(id)first, ...
{
    NSMutableArray *tmp = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id))
        [tmp addObject:o];
    va_end(ap);
    return [self arrayWithArray:tmp];
}
+ (NSArray *)arrayWithContentsOfFile:(NSString *)path
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    id plist = d ? FParsePlist(d, NSPropertyListImmutable, NULL) : nil;
    if (![plist isKindOfClass:[NSArray class]])
        return nil;
    if ([self isSubclassOfClass:[NSMutableArray class]])
        return [[plist mutableCopy] autorelease];
    return plist;
}
- (instancetype)init { return [self initWithObjects:NULL count:0]; }
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    if (!count)
        return self;   /* a subclass of its own that calls [super init] */
    [self release];
    FRaise(NSInvalidArgumentException, @"*** -[NSArray initWithObjects:count:]: method only defined for abstract class");
}
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
- (instancetype)initWithContentsOfFile:(NSString *)path
{
    NSArray *a = [NSArray arrayWithContentsOfFile:path];
    if (!a) {
        [self release];
        return nil;
    }
    return [self initWithArray:a];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url { return [self initWithContentsOfFile:[url path]]; }
- (instancetype)initWithArray:(NSArray *)array
{
    NSUInteger n = [array count];
    id *objs = malloc((n ? n : 1) * sizeof(id));
    [array getObjects:objs range:NSMakeRange(0, n)];
    self = [self initWithObjects:objs count:n];
    free(objs);
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return [[NSArray allocWithZone:zone] initWithArray:self]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableArray allocWithZone:zone] initWithArray:self]; }
- (id)objectAtIndexedSubscript:(NSUInteger)index { return [self objectAtIndex:index]; }
- (id)firstObject { return [self count] ? [self objectAtIndex:0] : nil; }
- (id)lastObject
{
    NSUInteger n = [self count];
    return n ? [self objectAtIndex:n - 1] : nil;
}
- (BOOL)containsObject:(id)obj { return [self indexOfObject:obj] != NSNotFound; }
- (NSUInteger)indexOfObject:(id)obj
{
    NSUInteger n = [self count];
    for (NSUInteger i = 0; i < n; i++)
        if ([[self objectAtIndex:i] isEqual:obj])
            return i;
    return NSNotFound;
}
- (NSUInteger)indexOfObjectIdenticalTo:(id)obj
{
    NSUInteger n = [self count];
    for (NSUInteger i = 0; i < n; i++)
        if ([self objectAtIndex:i] == obj)
            return i;
    return NSNotFound;
}
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(id, NSUInteger, BOOL *))predicate
{
    NSUInteger n = [self count];
    BOOL stop = NO;
    for (NSUInteger i = 0; i < n && !stop; i++)
        if (predicate([self objectAtIndex:i], i, &stop))
            return i;
    return NSNotFound;
}
- (BOOL)isEqualToArray:(NSArray *)other
{
    if (other == self)
        return YES;
    NSUInteger n = [self count];
    if ([other count] != n)
        return NO;
    for (NSUInteger i = 0; i < n; i++)
        if (![[self objectAtIndex:i] isEqual:[other objectAtIndex:i]])
            return NO;
    return YES;
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSArray class]] && [self isEqualToArray:other];
}
- (NSUInteger)hash { return [self count]; }
- (NSArray *)arrayByAddingObject:(id)obj
{
    NSMutableArray *m = [[self mutableCopy] autorelease];
    [m addObject:obj];
    return [NSArray arrayWithArray:m];
}
- (NSArray *)arrayByAddingObjectsFromArray:(NSArray *)other
{
    NSMutableArray *m = [[self mutableCopy] autorelease];
    [m addObjectsFromArray:other];
    return [NSArray arrayWithArray:m];
}
- (NSArray *)subarrayWithRange:(NSRange)range
{
    if (NSMaxRange(range) > [self count])
        FRaise(NSRangeException, @"*** -[NSArray subarrayWithRange:]: range {%lu, %lu} extends beyond bounds [0 .. %ld]",
               (unsigned long)range.location, (unsigned long)range.length, (long)[self count] - 1);
    id *objs = malloc((range.length ? range.length : 1) * sizeof(id));
    [self getObjects:objs range:range];
    NSArray *a = [NSArray arrayWithObjects:objs count:range.length];
    free(objs);
    return a;
}
- (NSString *)componentsJoinedByString:(NSString *)separator
{
    NSMutableString *s = [NSMutableString string];
    NSUInteger n = [self count];
    for (NSUInteger i = 0; i < n; i++) {
        if (i)
            [s appendString:separator];
        [s appendString:[[self objectAtIndex:i] description]];
    }
    return [NSString stringWithString:s];
}
- (NSArray *)sortedWith:(fcompare)cmp context:(void *)ctx
{
    NSUInteger n = [self count];
    id *objs = malloc((n ? n : 1) * sizeof(id));
    [self getObjects:objs range:NSMakeRange(0, n)];
    merge_sort(objs, n, cmp, ctx);
    NSArray *a = [NSArray arrayWithObjects:objs count:n];
    free(objs);
    return a;
}
- (NSArray *)sortedArrayUsingSelector:(SEL)comparator { return [self sortedWith:by_selector context:(void *)comparator]; }
- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr { return [self sortedWith:by_block context:(void *)cmptr]; }
- (NSArray *)sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))fn context:(void *)ctx
{
    return [self sortedWith:(fcompare)fn context:ctx];
}
- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id))predicate
{
    NSMutableArray *m = [NSMutableArray array];
    for (id o in self)
        if (predicate(o))
            [m addObject:o];
    return [NSArray arrayWithArray:m];
}
- (void)makeObjectsPerformSelector:(SEL)sel
{
    for (id o in [[self copy] autorelease])
        ((void (*)(id, SEL))objc_msgSend)(o, sel);
}
- (void)makeObjectsPerformSelector:(SEL)sel withObject:(id)arg
{
    for (id o in [[self copy] autorelease])
        ((void (*)(id, SEL, id))objc_msgSend)(o, sel, arg);
}
- (void)enumerateObjectsUsingBlock:(void (^)(id, NSUInteger, BOOL *))block
{
    [self enumerateObjectsWithOptions:0 usingBlock:block];
}
- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(id, NSUInteger, BOOL *))block
{
    NSUInteger n = [self count];
    BOOL stop = NO;
    for (NSUInteger k = 0; k < n && !stop; k++) {
        NSUInteger i = (opts & NSEnumerationReverse) ? n - 1 - k : k;
        block([self objectAtIndex:i], i, &stop);
    }
}
- (NSEnumerator *)objectEnumerator { return [[[FListEnumerator alloc] initWithArray:self reverse:NO] autorelease]; }
- (NSEnumerator *)reverseObjectEnumerator
{
    return [[[FListEnumerator alloc] initWithArray:self reverse:YES] autorelease];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    NSUInteger n = [self count];
    if (state->state == 0)
        state->mutationsPtr = &never_mutated;
    if (state->state >= n)
        return 0;
    NSUInteger k = n - state->state < len ? n - state->state : len;
    [self getObjects:buffer range:NSMakeRange(state->state, k)];
    state->itemsPtr = buffer;
    state->state += k;
    return k;
}
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically
{
    NSData *d = FWriteXMLPlist(self);
    return d && [d writeToFile:path atomically:atomically];
}
- (NSString *)description { return FDescribe(self, 0); }
- (NSString *)descriptionWithLocale:(id)locale { return FDescribe(self, 0); }
- (id)valueForKey:(NSString *)key
{
    NSMutableArray *m = [NSMutableArray array];
    for (id o in self)
        [m addObject:[o valueForKey:key] ?: (id)[NSNull null]];
    return m;
}
@end

@implementation FArray
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    _items = malloc((count ? count : 1) * sizeof(id));
    for (NSUInteger i = 0; i < count; i++) {
        if (!objects[i]) {
            for (NSUInteger j = 0; j < i; j++)
                [_items[j] release];
            free(_items);
            _items = NULL;
            [self release];
            FRaise(NSInvalidArgumentException,
                   @"*** -[__NSPlaceholderArray initWithObjects:count:]: attempt to insert nil object from objects[%lu]",
                   (unsigned long)i);
        }
        _items[i] = [objects[i] retain];
    }
    _count = count;
    return self;
}
- (void)dealloc
{
    for (NSUInteger i = 0; i < _count; i++)
        [_items[i] release];
    free(_items);
    [super dealloc];
}
- (NSUInteger)count { return _count; }
- (id)objectAtIndex:(NSUInteger)index
{
    range_check(self, _cmd, index, _count);
    return _items[index];
}
- (void)getObjects:(id *)objects range:(NSRange)range
{
    if (NSMaxRange(range) > _count)
        range_check(self, _cmd, NSMaxRange(range) - 1, _count);
    memcpy(objects, _items + range.location, range.length * sizeof(id));
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    if (state->state)
        return 0;
    state->state = 1;
    state->mutationsPtr = &never_mutated;
    state->itemsPtr = _items;
    return _count;
}
@end

/* ---- NSMutableArray ---------------------------------------------------------------- */

@implementation NSMutableArray
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity { return [[[self alloc] initWithCapacity:capacity] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return [self init]; }
- (id)copyWithZone:(NSZone *)zone { return [[NSArray allocWithZone:zone] initWithArray:self]; }
- (void)insertObject:(id)obj atIndex:(NSUInteger)index {}
- (void)removeObjectAtIndex:(NSUInteger)index {}
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)obj
{
    [obj retain];
    [self removeObjectAtIndex:index];
    [self insertObject:obj atIndex:index];
    [obj release];
}
- (void)addObject:(id)obj { [self insertObject:obj atIndex:[self count]]; }
- (void)removeLastObject
{
    NSUInteger n = [self count];
    if (n)
        [self removeObjectAtIndex:n - 1];
}
- (void)removeObject:(id)obj
{
    for (NSUInteger i = [self count]; i-- > 0;)
        if ([[self objectAtIndex:i] isEqual:obj])
            [self removeObjectAtIndex:i];
}
- (void)removeObjectIdenticalTo:(id)obj
{
    for (NSUInteger i = [self count]; i-- > 0;)
        if ([self objectAtIndex:i] == obj)
            [self removeObjectAtIndex:i];
}
- (void)removeAllObjects
{
    while ([self count])
        [self removeLastObject];
}
- (void)removeObjectsInArray:(NSArray *)other
{
    for (id o in other)
        [self removeObject:o];
}
- (void)removeObjectsInRange:(NSRange)range
{
    for (NSUInteger i = 0; i < range.length; i++)
        [self removeObjectAtIndex:range.location];
}
- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)index
{
    if (index == [self count])
        [self addObject:obj];
    else
        [self replaceObjectAtIndex:index withObject:obj];
}
- (void)addObjectsFromArray:(NSArray *)array
{
    for (id o in [[array copy] autorelease])
        [self addObject:o];
}
- (void)setArray:(NSArray *)array
{
    [array retain];
    [self removeAllObjects];
    [self addObjectsFromArray:array];
    [array release];
}
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b
{
    id x = [[self objectAtIndex:a] retain], y = [self objectAtIndex:b];
    [self replaceObjectAtIndex:a withObject:y];
    [self replaceObjectAtIndex:b withObject:x];
    [x release];
}
- (void)sortUsingSelector:(SEL)comparator { [self setArray:[self sortedArrayUsingSelector:comparator]]; }
- (void)sortUsingComparator:(NSComparator)cmptr { [self setArray:[self sortedArrayUsingComparator:cmptr]]; }
@end

@implementation FMutableArray
- (instancetype)init { return [self initWithCapacity:0]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity
{
    _cap = capacity < 4 ? 4 : capacity;
    _items = malloc(_cap * sizeof(id));
    return self;
}
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    self = [self initWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++)
        [self addObject:objects[i]];
    return self;
}
- (void)dealloc
{
    for (NSUInteger i = 0; i < _count; i++)
        [_items[i] release];
    free(_items);
    [super dealloc];
}
- (NSUInteger)count { return _count; }
- (id)objectAtIndex:(NSUInteger)index
{
    range_check(self, _cmd, index, _count);
    return _items[index];
}
- (void)getObjects:(id *)objects range:(NSRange)range
{
    if (NSMaxRange(range) > _count)
        range_check(self, _cmd, NSMaxRange(range) - 1, _count);
    memcpy(objects, _items + range.location, range.length * sizeof(id));
}
- (void)insertObject:(id)obj atIndex:(NSUInteger)index
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[__NSArrayM insertObject:atIndex:]: object cannot be nil");
    if (index > _count)
        FRaise(NSRangeException, @"*** -[__NSArrayM insertObject:atIndex:]: index %lu beyond bounds [0 .. %lu]",
               (unsigned long)index, (unsigned long)_count);
    if (_count == _cap) {
        _cap *= 2;
        _items = realloc(_items, _cap * sizeof(id));
    }
    memmove(_items + index + 1, _items + index, (_count - index) * sizeof(id));
    _items[index] = [obj retain];
    _count++;
    _mutations++;
}
- (void)addObject:(id)obj
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[__NSArrayM insertObject:atIndex:]: object cannot be nil");
    [self insertObject:obj atIndex:_count];
}
- (void)removeObjectAtIndex:(NSUInteger)index
{
    range_check(self, _cmd, index, _count);
    id old = _items[index];
    memmove(_items + index, _items + index + 1, (_count - index - 1) * sizeof(id));
    _count--;
    _mutations++;
    [old release];
}
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)obj
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[__NSArrayM replaceObjectAtIndex:withObject:]: object cannot be nil");
    range_check(self, _cmd, index, _count);
    id old = _items[index];
    _items[index] = [obj retain];
    _mutations++;
    [old release];
}
- (void)removeAllObjects
{
    NSUInteger n = _count;
    _count = 0;
    _mutations++;
    for (NSUInteger i = 0; i < n; i++)
        [_items[i] release];
}
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b
{
    range_check(self, _cmd, a, _count);
    range_check(self, _cmd, b, _count);
    id t = _items[a];
    _items[a] = _items[b];
    _items[b] = t;
    _mutations++;
}
- (void)sortUsingSelector:(SEL)comparator
{
    merge_sort(_items, _count, by_selector, (void *)comparator);
    _mutations++;
}
- (void)sortUsingComparator:(NSComparator)cmptr
{
    merge_sort(_items, _count, by_block, (void *)cmptr);
    _mutations++;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    if (state->state)
        return 0;
    state->state = 1;
    state->mutationsPtr = &_mutations;
    state->itemsPtr = _items;
    return _count;
}
@end

/* ---- NSEnumerator ------------------------------------------------------------------ */

@implementation NSEnumerator
- (id)nextObject { return nil; }
- (NSArray *)allObjects
{
    NSMutableArray *m = [NSMutableArray array];
    for (id o; (o = [self nextObject]);)
        [m addObject:o];
    return m;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    state->mutationsPtr = &never_mutated;
    NSUInteger k = 0;
    id o;
    while (k < len && (o = [self nextObject]))
        buffer[k++] = o;
    state->itemsPtr = buffer;
    return k;
}
@end

@implementation FListEnumerator
- (instancetype)initWithArray:(NSArray *)array reverse:(BOOL)reverse
{
    _array = [array retain];
    _reverse = reverse;
    return self;
}
- (void)dealloc
{
    [_array release];
    [super dealloc];
}
- (id)nextObject
{
    NSUInteger n = [_array count];
    if (_next >= n)
        return nil;
    NSUInteger i = _reverse ? n - 1 - _next : _next;
    _next++;
    return [_array objectAtIndex:i];
}
@end

/* clang refers to these for the literals @[] (and NSDictionary.m's @{}). */
F_EXPORT id __NSArray0__;
id __NSArray0__;

__attribute__((constructor)) static void empty_array_init(void) { __NSArray0__ = [[NSArray alloc] init]; }

/* ---- NSNull ------------------------------------------------------------------------ */

@implementation NSNull
+ (NSNull *)null
{
    static NSNull *shared;
    static dispatch_once_t shared_once;
    dispatch_once(&shared_once, ^{
      shared = [[NSNull alloc] init];
    });
    return shared;
}
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return @"<null>"; }
@end
