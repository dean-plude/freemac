/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * The array and dictionary calls that a collection wrapping one (as
 * M13OrderedDictionary, which MacDown brings, wraps an array and a
 * dictionary) passes on (freemac 1.225, Ferry 0.49.0): searching with
 * options and among indexes, sort hints, observing the objects at
 * indexes, and the dictionary's from-arrays calls. Written from Apple's
 * public documentation; no Apple code was read. A concurrent search runs
 * in order here, which the documentation allows. */
#import <Foundation/Foundation.h>

/* NSZone is kept only as the name of an allocation's zone: there is one */
static struct _NSZone {
    int unused;
} default_zone;
NSZone *NSDefaultMallocZone(void) { return &default_zone; }
NSZone *NSZoneFromPointer(void *ptr) { return ptr ? &default_zone : NULL; }

@implementation NSArray (FerrySearching)
- (id)firstObjectCommonWithArray:(NSArray *)other
{
    for (id obj in self)
        if ([other containsObject:obj])
            return obj;
    return nil;
}

/* the indexes to look at, in the order the options ask */
static void each_index(NSArray *self, NSIndexSet *indexes, NSEnumerationOptions opts, BOOL (^body)(NSUInteger i))
{
    NSUInteger n = [self count];
    if (!indexes) {
        if (opts & NSEnumerationReverse) {
            for (NSUInteger i = n; i-- > 0;)
                if (!body(i))
                    return;
        } else {
            for (NSUInteger i = 0; i < n; i++)
                if (!body(i))
                    return;
        }
        return;
    }
    if ([indexes count] && [indexes lastIndex] >= n)
        [NSException raise:NSRangeException format:@"*** -[NSArray indexesOfObjectsAtIndexes:]: index %lu beyond "
                                                   @"bounds [0 .. %lu]",
                                                   (unsigned long)[indexes lastIndex], (unsigned long)(n ? n - 1 : 0)];
    [indexes enumerateIndexesWithOptions:opts & NSEnumerationReverse
                              usingBlock:^(NSUInteger i, BOOL *stop) {
                                  if (!body(i))
                                      *stop = YES;
                              }];
}

- (NSUInteger)indexOfObjectAtIndexes:(NSIndexSet *)indexes options:(NSEnumerationOptions)opts
                         passingTest:(BOOL (^)(id obj, NSUInteger idx, BOOL *stop))predicate
{
    __block NSUInteger found = NSNotFound;
    each_index(self, indexes, opts, ^BOOL(NSUInteger i) {
        BOOL stop = NO;
        if (predicate([self objectAtIndex:i], i, &stop)) {
            found = i;
            return NO;
        }
        return !stop;
    });
    return found;
}
- (NSUInteger)indexOfObjectWithOptions:(NSEnumerationOptions)opts
                           passingTest:(BOOL (^)(id obj, NSUInteger idx, BOOL *stop))predicate
{
    return [self indexOfObjectAtIndexes:nil options:opts passingTest:predicate];
}
- (NSIndexSet *)indexesOfObjectsAtIndexes:(NSIndexSet *)indexes options:(NSEnumerationOptions)opts
                              passingTest:(BOOL (^)(id obj, NSUInteger idx, BOOL *stop))predicate
{
    NSMutableIndexSet *found = [NSMutableIndexSet indexSet];
    each_index(self, indexes, opts, ^BOOL(NSUInteger i) {
        BOOL stop = NO;
        if (predicate([self objectAtIndex:i], i, &stop))
            [found addIndex:i];
        return !stop;
    });
    return found;
}
- (NSIndexSet *)indexesOfObjectsWithOptions:(NSEnumerationOptions)opts
                                passingTest:(BOOL (^)(id obj, NSUInteger idx, BOOL *stop))predicate
{
    return [self indexesOfObjectsAtIndexes:nil options:opts passingTest:predicate];
}

/* A hint speeds up sorting an array that is mostly sorted already; this
 * sort needs none, so the hint is the array's count, and is not needed
 * back. */
- (NSData *)sortedArrayHint
{
    uint64_t n = [self count];
    return [NSData dataWithBytes:&n length:sizeof n];
}
- (NSArray *)sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))fn context:(void *)ctx hint:(NSData *)hint
{
    return [self sortedArrayUsingFunction:fn context:ctx];
}

- (void)addObserver:(NSObject *)observer toObjectsAtIndexes:(NSIndexSet *)indexes forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options context:(void *)context
{
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [[self objectAtIndex:i] addObserver:observer forKeyPath:keyPath options:options context:context];
    }];
}
- (void)removeObserver:(NSObject *)observer fromObjectsAtIndexes:(NSIndexSet *)indexes forKeyPath:(NSString *)keyPath
{
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [[self objectAtIndex:i] removeObserver:observer forKeyPath:keyPath];
    }];
}
- (void)removeObserver:(NSObject *)observer fromObjectsAtIndexes:(NSIndexSet *)indexes
            forKeyPath:(NSString *)keyPath context:(void *)context
{
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [[self objectAtIndex:i] removeObserver:observer forKeyPath:keyPath context:context];
    }];
}
@end

@implementation NSDictionary (FerryFromArrays)
- (instancetype)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys
{
    NSUInteger n = [objects count];
    if ([keys count] != n) {
        [self release];
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSDictionary initWithObjects:forKeys:]: count of objects (%lu) differs from "
                           @"count of keys (%lu)",
                           (unsigned long)n, (unsigned long)[keys count]];
    }
    id *o = malloc((n ? n : 1) * sizeof(id)), *k = malloc((n ? n : 1) * sizeof(id));
    [objects getObjects:o range:NSMakeRange(0, n)];
    [keys getObjects:k range:NSMakeRange(0, n)];
    self = [self initWithObjects:o forKeys:k count:n];
    free(o);
    free(k);
    return self;
}
- (NSArray *)objectsForKeys:(NSArray *)keys notFoundMarker:(id)marker
{
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:[keys count]];
    for (id key in keys) {
        id obj = [self objectForKey:key] ?: marker;
        if (obj)
            [out addObject:obj];
    }
    return out;
}
@end
