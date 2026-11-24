/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSOrderedSet and NSMutableOrderedSet, as Apple's
 * NSOrderedSet reference describes them, and key-value coding's
 * mutableOrderedSetValueForKey:. Core Data's ordered relationships hold
 * ordered sets (freemac 1.NEXT, Ferry 0.NEXT). Our own code; no Apple code
 * was used.
 *
 * As NSArray is, NSOrderedSet is a class cluster: the public classes
 * describe everything with a few primitive methods (count, objectAtIndex:
 * and indexOfObject:, and for the mutable class insertObject:atIndex:,
 * removeObjectAtIndex: and replaceObjectAtIndex:withObject:), so that a
 * subclass that gives those works, and allocating one gives a private
 * class that keeps the objects in an array, with a set beside it for
 * membership. Adding an object that is there already does nothing. */
#import "FInternal.h"
#include <Foundation/NSOrderedSet.h>

@interface FOrderedSet : NSOrderedSet {
@public
    NSMutableArray *_items;
    NSMutableSet *_members;
}
@end

@interface FMutableOrderedSet : NSMutableOrderedSet {
@public
    NSMutableArray *_items;
    NSMutableSet *_members;
}
@end

static void fill(NSMutableArray *items, NSMutableSet *members, const id *objects, NSUInteger n)
{
    for (NSUInteger i = 0; i < n; i++) {
        id o = objects[i];
        if (!o)
            FRaise(NSInvalidArgumentException, @"*** -[NSOrderedSet initWithObjects:count:]: attempt to insert nil "
                                               @"object from objects[%lu]",
                   (unsigned long)i);
        if (![members containsObject:o]) {
            [members addObject:o];
            [items addObject:o];
        }
    }
}

static void check_index(NSOrderedSet *self, SEL _cmd, NSUInteger i, NSUInteger n)
{
    if (i >= n)
        FRaise(NSRangeException, @"*** -[%s %s]: index %lu beyond bounds [0 .. %ld]", class_getName([self class]),
               sel_getName(_cmd), (unsigned long)i, (long)n - 1);
}

@implementation NSOrderedSet
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSOrderedSet class])
        return [FOrderedSet allocWithZone:zone];
    if (self == [NSMutableOrderedSet class])
        return [FMutableOrderedSet allocWithZone:zone];
    return [super allocWithZone:zone];
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)orderedSet { return [[[self alloc] init] autorelease]; }
+ (instancetype)orderedSetWithObject:(id)object { return [[[self alloc] initWithObjects:&object count:1] autorelease]; }
+ (instancetype)orderedSetWithObjects:(const id *)objects count:(NSUInteger)cnt
{
    return [[[self alloc] initWithObjects:objects count:cnt] autorelease];
}
+ (instancetype)orderedSetWithObjects:(id)first, ...
{
    NSMutableArray *a = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id))
        [a addObject:o];
    va_end(ap);
    return [[[self alloc] initWithArray:a] autorelease];
}
+ (instancetype)orderedSetWithArray:(NSArray *)array { return [[[self alloc] initWithArray:array] autorelease]; }
+ (instancetype)orderedSetWithSet:(NSSet *)set { return [[[self alloc] initWithSet:set] autorelease]; }
+ (instancetype)orderedSetWithOrderedSet:(NSOrderedSet *)set
{
    return [[[self alloc] initWithOrderedSet:set] autorelease];
}
- (instancetype)init { return [self initWithObjects:NULL count:0]; }
- (instancetype)initWithObject:(id)object { return [self initWithObjects:&object count:1]; }
- (instancetype)initWithObjects:(const id *)objects count:(NSUInteger)cnt { return [super init]; }
- (instancetype)initWithObjects:(id)first, ...
{
    NSMutableArray *a = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id))
        [a addObject:o];
    va_end(ap);
    return [self initWithArray:a];
}
- (instancetype)initWithArray:(NSArray *)array
{
    NSUInteger n = [array count];
    id *buf = malloc((n ? n : 1) * sizeof(id));
    [array getObjects:buf range:NSMakeRange(0, n)];
    self = [self initWithObjects:buf count:n];
    free(buf);
    return self;
}
- (instancetype)initWithSet:(NSSet *)set { return [self initWithArray:[set allObjects]]; }
- (instancetype)initWithOrderedSet:(NSOrderedSet *)set { return [self initWithArray:[set array]]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    id a = [coder decodeObjectForKey:@"NS.objects"];
    return [self initWithArray:[a isKindOfClass:[NSArray class]] ? a : [NSArray array]];
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:[self array] forKey:@"NS.objects"]; }
- (NSUInteger)count { return 0; }
- (id)objectAtIndex:(NSUInteger)idx
{
    check_index(self, _cmd, idx, 0);
    return nil;
}
- (NSUInteger)indexOfObject:(id)object
{
    NSUInteger n = [self count];
    for (NSUInteger i = 0; i < n; i++)
        if ([[self objectAtIndex:i] isEqual:object])
            return i;
    return NSNotFound;
}
- (id)objectAtIndexedSubscript:(NSUInteger)idx { return [self objectAtIndex:idx]; }
- (void)getObjects:(id *)objects range:(NSRange)range
{
    for (NSUInteger i = 0; i < range.length; i++)
        objects[i] = [self objectAtIndex:range.location + i];
}
- (NSArray *)objectsAtIndexes:(NSIndexSet *)indexes
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = [indexes firstIndex]; i != NSNotFound; i = [indexes indexGreaterThanIndex:i])
        [a addObject:[self objectAtIndex:i]];
    return a;
}
- (id)firstObject { return [self count] ? [self objectAtIndex:0] : nil; }
- (id)lastObject { return [self count] ? [self objectAtIndex:[self count] - 1] : nil; }
- (BOOL)containsObject:(id)object { return object && [self indexOfObject:object] != NSNotFound; }
- (NSArray *)array
{
    NSUInteger n = [self count];
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++)
        [a addObject:[self objectAtIndex:i]];
    return [[a copy] autorelease];
}
- (NSSet *)set { return [NSSet setWithArray:[self array]]; }
- (NSOrderedSet *)reversedOrderedSet
{
    return [NSOrderedSet orderedSetWithArray:[[[self array] reverseObjectEnumerator] allObjects]];
}
- (NSEnumerator *)objectEnumerator { return [[self array] objectEnumerator]; }
- (NSEnumerator *)reverseObjectEnumerator { return [[self array] reverseObjectEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    static unsigned long never_mutated;
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
- (void)enumerateObjectsUsingBlock:(void (^)(id, NSUInteger, BOOL *))block { [[self array] enumerateObjectsUsingBlock:block]; }
- (NSIndexSet *)indexesOfObjectsPassingTest:(BOOL (^)(id, NSUInteger, BOOL *))predicate
{
    NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
    BOOL stop = NO;
    NSUInteger n = [self count];
    for (NSUInteger i = 0; i < n && !stop; i++)
        if (predicate([self objectAtIndex:i], i, &stop))
            [s addIndex:i];
    return s;
}
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(id, NSUInteger, BOOL *))predicate
{
    return [[self array] indexOfObjectPassingTest:predicate];
}
- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr { return [[self array] sortedArrayUsingComparator:cmptr]; }
- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)d { return [[self array] sortedArrayUsingDescriptors:d]; }
- (NSOrderedSet *)filteredOrderedSetUsingPredicate:(NSPredicate *)p
{
    return [NSOrderedSet orderedSetWithArray:[[self array] filteredArrayUsingPredicate:p]];
}
- (BOOL)isEqualToOrderedSet:(NSOrderedSet *)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSOrderedSet class]] || [other count] != [self count])
        return NO;
    return [[self array] isEqualToArray:[other array]];
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSOrderedSet class]] && [self isEqualToOrderedSet:other];
}
- (NSUInteger)hash { return [self count]; }
- (BOOL)intersectsOrderedSet:(NSOrderedSet *)other { return [[self set] intersectsSet:[other set]]; }
- (BOOL)intersectsSet:(NSSet *)set { return [[self set] intersectsSet:set]; }
- (BOOL)isSubsetOfOrderedSet:(NSOrderedSet *)other { return [[self set] isSubsetOfSet:[other set]]; }
- (BOOL)isSubsetOfSet:(NSSet *)set { return [[self set] isSubsetOfSet:set]; }
- (id)copyWithZone:(NSZone *)zone { return [[NSOrderedSet alloc] initWithArray:[self array]]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableOrderedSet alloc] initWithArray:[self array]]; }
/* The ordered set of the objects' values, as for an array. */
- (id)valueForKey:(NSString *)key
{
    NSMutableArray *values = [NSMutableArray array];
    for (id o in [self array]) {
        id v = [o valueForKey:key];
        [values addObject:v ?: [NSNull null]];
    }
    return [NSOrderedSet orderedSetWithArray:values];
}
- (void)setValue:(id)value forKey:(NSString *)key
{
    for (id o in [self array])
        [o setValue:value forKey:key];
}
- (NSString *)descriptionWithLocale:(id)locale { return [self description]; }
- (NSString *)description
{
    NSString *inner = FDescribe([self array], 0);   /* "(\n    a,\n    b\n)" */
    return [NSString stringWithFormat:@"{%@}", inner];
}
@end

@implementation FOrderedSet
- (instancetype)initWithObjects:(const id *)objects count:(NSUInteger)cnt
{
    if ((self = [super initWithObjects:NULL count:0])) {
        _items = [[NSMutableArray alloc] initWithCapacity:cnt];
        _members = [[NSMutableSet alloc] init];
        fill(_items, _members, objects, cnt);
    }
    return self;
}
- (void)dealloc
{
    [_items release];
    [_members release];
    [super dealloc];
}
- (NSUInteger)count { return [_items count]; }
- (id)objectAtIndex:(NSUInteger)idx
{
    check_index(self, _cmd, idx, [_items count]);
    return [_items objectAtIndex:idx];
}
- (NSUInteger)indexOfObject:(id)object
{
    return object && [_members containsObject:object] ? [_items indexOfObject:object] : NSNotFound;
}
- (BOOL)containsObject:(id)object { return object && [_members containsObject:object]; }
- (NSArray *)array { return [[_items copy] autorelease]; }
- (NSSet *)set { return [[_members copy] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

@implementation NSMutableOrderedSet
+ (instancetype)orderedSetWithCapacity:(NSUInteger)numItems
{
    return [[[self alloc] initWithCapacity:numItems] autorelease];
}
- (instancetype)initWithCapacity:(NSUInteger)numItems { return [self initWithObjects:NULL count:0]; }
- (void)insertObject:(id)object atIndex:(NSUInteger)idx
{
    FRaise(NSInternalInconsistencyException, @"-[%s insertObject:atIndex:] must be implemented by a subclass",
           class_getName([self class]));
}
- (void)removeObjectAtIndex:(NSUInteger)idx
{
    FRaise(NSInternalInconsistencyException, @"-[%s removeObjectAtIndex:] must be implemented by a subclass",
           class_getName([self class]));
}
- (void)replaceObjectAtIndex:(NSUInteger)idx withObject:(id)object
{
    [self removeObjectAtIndex:idx];
    [self insertObject:object atIndex:idx];
}
- (void)addObject:(id)object
{
    if (![self containsObject:object])
        [self insertObject:object atIndex:[self count]];
}
- (void)addObjects:(const id *)objects count:(NSUInteger)count
{
    for (NSUInteger i = 0; i < count; i++)
        [self addObject:objects[i]];
}
- (void)addObjectsFromArray:(NSArray *)array
{
    for (id o in array)
        [self addObject:o];
}
- (void)insertObjects:(NSArray *)objects atIndexes:(NSIndexSet *)indexes
{
    NSUInteger k = 0;
    for (NSUInteger i = [indexes firstIndex]; i != NSNotFound && k < [objects count]; i = [indexes indexGreaterThanIndex:i])
        [self insertObject:[objects objectAtIndex:k++] atIndex:i];
}
- (void)removeObject:(id)object
{
    NSUInteger i = object ? [self indexOfObject:object] : NSNotFound;
    if (i != NSNotFound)
        [self removeObjectAtIndex:i];
}
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes
{
    for (NSUInteger i = [indexes lastIndex]; i != NSNotFound; i = [indexes indexLessThanIndex:i])
        [self removeObjectAtIndex:i];
}
- (void)removeObjectsInArray:(NSArray *)array
{
    for (id o in array)
        [self removeObject:o];
}
- (void)removeObjectsInRange:(NSRange)range
{
    [self removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range]];
}
- (void)removeAllObjects
{
    while ([self count])
        [self removeObjectAtIndex:[self count] - 1];
}
- (void)replaceObjectsAtIndexes:(NSIndexSet *)indexes withObjects:(NSArray *)objects
{
    NSUInteger k = 0;
    for (NSUInteger i = [indexes firstIndex]; i != NSNotFound && k < [objects count]; i = [indexes indexGreaterThanIndex:i])
        [self replaceObjectAtIndex:i withObject:[objects objectAtIndex:k++]];
}
- (void)setObject:(id)obj atIndex:(NSUInteger)idx
{
    if (idx == [self count])
        [self addObject:obj];
    else
        [self replaceObjectAtIndex:idx withObject:obj];
}
- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx { [self setObject:obj atIndex:idx]; }
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b
{
    if (a == b)
        return;
    NSMutableArray *all = [[[self array] mutableCopy] autorelease];
    [all exchangeObjectAtIndex:a withObjectAtIndex:b];
    [self removeAllObjects];
    [self addObjectsFromArray:all];
}
- (void)moveObjectsAtIndexes:(NSIndexSet *)indexes toIndex:(NSUInteger)idx
{
    NSArray *moving = [self objectsAtIndexes:indexes];
    [self removeObjectsAtIndexes:indexes];
    [self insertObjects:moving atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(idx, [moving count])]];
}
- (void)unionOrderedSet:(NSOrderedSet *)other { [self addObjectsFromArray:[other array]]; }
- (void)minusOrderedSet:(NSOrderedSet *)other { [self removeObjectsInArray:[other array]]; }
- (void)intersectOrderedSet:(NSOrderedSet *)other { [self intersectSet:[other set]]; }
- (void)unionSet:(NSSet *)other { [self addObjectsFromArray:[other allObjects]]; }
- (void)minusSet:(NSSet *)other { [self removeObjectsInArray:[other allObjects]]; }
- (void)intersectSet:(NSSet *)other
{
    for (NSUInteger i = [self count]; i > 0; i--)
        if (![other containsObject:[self objectAtIndex:i - 1]])
            [self removeObjectAtIndex:i - 1];
}
- (void)_ferrySetOrder:(NSArray *)sorted
{
    [self removeAllObjects];
    [self addObjectsFromArray:sorted];
}
- (void)sortUsingComparator:(NSComparator)cmptr { [self _ferrySetOrder:[self sortedArrayUsingComparator:cmptr]]; }
- (void)sortUsingDescriptors:(NSArray *)d { [self _ferrySetOrder:[self sortedArrayUsingDescriptors:d]]; }
- (void)filterUsingPredicate:(NSPredicate *)p { [self _ferrySetOrder:[[self array] filteredArrayUsingPredicate:p]]; }
@end

@implementation FMutableOrderedSet
- (instancetype)initWithObjects:(const id *)objects count:(NSUInteger)cnt
{
    if ((self = [super initWithObjects:NULL count:0])) {
        _items = [[NSMutableArray alloc] initWithCapacity:cnt];
        _members = [[NSMutableSet alloc] init];
        fill(_items, _members, objects, cnt);
    }
    return self;
}
- (instancetype)initWithCapacity:(NSUInteger)numItems { return [self initWithObjects:NULL count:0]; }
- (void)dealloc
{
    [_items release];
    [_members release];
    [super dealloc];
}
- (NSUInteger)count { return [_items count]; }
- (id)objectAtIndex:(NSUInteger)idx
{
    check_index(self, _cmd, idx, [_items count]);
    return [_items objectAtIndex:idx];
}
- (NSUInteger)indexOfObject:(id)object
{
    return object && [_members containsObject:object] ? [_items indexOfObject:object] : NSNotFound;
}
- (BOOL)containsObject:(id)object { return object && [_members containsObject:object]; }
- (NSArray *)array { return [[_items copy] autorelease]; }
- (NSSet *)set { return [[_members copy] autorelease]; }
- (void)insertObject:(id)object atIndex:(NSUInteger)idx
{
    if (!object)
        FRaise(NSInvalidArgumentException, @"*** -[NSMutableOrderedSet insertObject:atIndex:]: object cannot be nil");
    if (idx > [_items count])
        check_index(self, _cmd, idx, [_items count]);
    if ([_members containsObject:object])
        return;
    [_members addObject:object];
    [_items insertObject:object atIndex:idx];
}
- (void)removeObjectAtIndex:(NSUInteger)idx
{
    check_index(self, _cmd, idx, [_items count]);
    [_members removeObject:[_items objectAtIndex:idx]];
    [_items removeObjectAtIndex:idx];
}
- (void)replaceObjectAtIndex:(NSUInteger)idx withObject:(id)object
{
    check_index(self, _cmd, idx, [_items count]);
    id old = [_items objectAtIndex:idx];
    if ([old isEqual:object])
        return;
    if ([_members containsObject:object])
        return;   /* already elsewhere: as on a Mac, nothing changes */
    [_members removeObject:old];
    [_members addObject:object];
    [_items replaceObjectAtIndex:idx withObject:object];
}
- (void)removeAllObjects
{
    [_items removeAllObjects];
    [_members removeAllObjects];
}
@end

/* ---- mutableOrderedSetValueForKey: ----------------------------------------------------
 * The proxy reads the key's value each time, and makes each change through
 * the object's indexed mutators when it has them (insertObject:in<Key>AtIndex:
 * and removeObjectFrom<Key>AtIndex:), else by setting a changed copy with
 * setValue:forKey:. */
@interface FKVCOrderedSetProxy : NSMutableOrderedSet {
    id _object;
    NSString *_key;
}
@end

static NSString *capital(NSString *key)
{
    return [key length] ? [[[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]]
                        : key;
}

@implementation FKVCOrderedSetProxy
- (instancetype)_initWithObject:(id)object key:(NSString *)key
{
    if ((self = [super initWithObjects:NULL count:0])) {
        _object = [object retain];
        _key = [key copy];
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [_key release];
    [super dealloc];
}
- (NSOrderedSet *)_current
{
    id v = [_object valueForKey:_key];
    if ([v isKindOfClass:[NSOrderedSet class]])
        return v;
    if ([v isKindOfClass:[NSArray class]])
        return [NSOrderedSet orderedSetWithArray:v];
    if ([v isKindOfClass:[NSSet class]])
        return [NSOrderedSet orderedSetWithSet:v];
    return [NSOrderedSet orderedSet];
}
- (NSUInteger)count { return [[self _current] count]; }
- (id)objectAtIndex:(NSUInteger)idx { return [[self _current] objectAtIndex:idx]; }
- (NSUInteger)indexOfObject:(id)object { return [[self _current] indexOfObject:object]; }
- (void)insertObject:(id)object atIndex:(NSUInteger)idx
{
    if ([self containsObject:object])
        return;
    SEL sel = NSSelectorFromString([NSString stringWithFormat:@"insertObject:in%@AtIndex:", capital(_key)]);
    if ([_object respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(_object, sel, object, idx);
        return;
    }
    NSMutableOrderedSet *m = [[[self _current] mutableCopy] autorelease];
    [m insertObject:object atIndex:idx];
    [_object setValue:m forKey:_key];
}
- (void)removeObjectAtIndex:(NSUInteger)idx
{
    SEL sel = NSSelectorFromString([NSString stringWithFormat:@"removeObjectFrom%@AtIndex:", capital(_key)]);
    if ([_object respondsToSelector:sel]) {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(_object, sel, idx);
        return;
    }
    NSMutableOrderedSet *m = [[[self _current] mutableCopy] autorelease];
    [m removeObjectAtIndex:idx];
    [_object setValue:m forKey:_key];
}
@end

@implementation NSObject (NSKeyValueCodingOrderedSets)
- (NSMutableOrderedSet *)mutableOrderedSetValueForKey:(NSString *)key
{
    return [[[FKVCOrderedSetProxy alloc] _initWithObject:self key:key] autorelease];
}
- (NSMutableOrderedSet *)mutableOrderedSetValueForKeyPath:(NSString *)keyPath
{
    NSRange dot = [keyPath rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound)
        return [self mutableOrderedSetValueForKey:keyPath];
    return [[self valueForKeyPath:[keyPath substringToIndex:dot.location]]
        mutableOrderedSetValueForKey:[keyPath substringFromIndex:dot.location + 1]];
}
@end
