/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSOrderedSet and NSMutableOrderedSet (foundation/NSOrderedSet.m),
 * which Core Data's ordered relationships hold. Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSORDEREDSET_H_
#define _FERRY_FOUNDATION_NSORDEREDSET_H_
#include <Foundation/Foundation.h>

/* Distinct objects in an order: an array whose members are each there
 * once, compared with isEqual: and hash, as in a set. */
@interface NSOrderedSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration, NSSecureCoding>
@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndex:(NSUInteger)idx;
- (NSUInteger)indexOfObject:(ObjectType)object;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSet;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithObject:(ObjectType)object;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithObjects:(const ObjectType[])objects count:(NSUInteger)cnt;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithArray:(NSArray<ObjectType> *)array;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithSet:(NSSet<ObjectType> *)set;
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithOrderedSet:(NSOrderedSet<ObjectType> *)set;
- (instancetype FERRY_SWIFT_NONNULL)init;
- (instancetype FERRY_SWIFT_NONNULL)initWithObject:(ObjectType)object;
- (instancetype FERRY_SWIFT_NONNULL)initWithObjects:(const ObjectType[])objects count:(NSUInteger)cnt;
- (instancetype FERRY_SWIFT_NONNULL)initWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
- (instancetype FERRY_SWIFT_NONNULL)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype FERRY_SWIFT_NONNULL)initWithSet:(NSSet<ObjectType> *)set;
- (instancetype FERRY_SWIFT_NONNULL)initWithOrderedSet:(NSOrderedSet<ObjectType> *)set;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)idx;
- (void)getObjects:(ObjectType __unsafe_unretained[])objects range:(NSRange)range;
- (NSArray<ObjectType> *)objectsAtIndexes:(NSIndexSet *)indexes;
@property (readonly) ObjectType firstObject;
@property (readonly) ObjectType lastObject;
- (BOOL)containsObject:(ObjectType)object;
- (BOOL)isEqualToOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (BOOL)intersectsOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (BOOL)intersectsSet:(NSSet<ObjectType> *)set;
- (BOOL)isSubsetOfOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (BOOL)isSubsetOfSet:(NSSet<ObjectType> *)set;
@property (readonly, retain) NSArray<ObjectType> *array;
@property (readonly, retain) NSSet<ObjectType> *set;
@property (readonly, copy) NSOrderedSet<ObjectType> *reversedOrderedSet;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (NSEnumerator<ObjectType> *)reverseObjectEnumerator;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
- (NSIndexSet *)indexesOfObjectsPassingTest:(BOOL (^)(ObjectType obj, NSUInteger idx, BOOL *stop))predicate;
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(ObjectType obj, NSUInteger idx, BOOL *stop))predicate;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparator)cmptr;
- (NSArray<ObjectType> *)sortedArrayUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;
- (NSOrderedSet<ObjectType> *)filteredOrderedSetUsingPredicate:(NSPredicate *)p;
- (NSString *)descriptionWithLocale:(id)locale;
@end

@interface NSMutableOrderedSet<ObjectType> : NSOrderedSet<ObjectType>
+ (instancetype FERRY_SWIFT_NONNULL)orderedSetWithCapacity:(NSUInteger)numItems;
- (instancetype FERRY_SWIFT_NONNULL)initWithCapacity:(NSUInteger)numItems;
- (void)insertObject:(ObjectType)object atIndex:(NSUInteger)idx;
- (void)removeObjectAtIndex:(NSUInteger)idx;
- (void)replaceObjectAtIndex:(NSUInteger)idx withObject:(ObjectType)object;
- (void)addObject:(ObjectType)object;
- (void)addObjects:(const ObjectType[])objects count:(NSUInteger)count;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)insertObjects:(NSArray<ObjectType> *)objects atIndexes:(NSIndexSet *)indexes;
- (void)removeObject:(ObjectType)object;
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes;
- (void)removeObjectsInArray:(NSArray<ObjectType> *)array;
- (void)removeObjectsInRange:(NSRange)range;
- (void)removeAllObjects;
- (void)replaceObjectsAtIndexes:(NSIndexSet *)indexes withObjects:(NSArray<ObjectType> *)objects;
- (void)setObject:(ObjectType)obj atIndex:(NSUInteger)idx;
- (void)setObject:(ObjectType)obj atIndexedSubscript:(NSUInteger)idx;
- (void)exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2;
- (void)moveObjectsAtIndexes:(NSIndexSet *)indexes toIndex:(NSUInteger)idx;
- (void)unionOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (void)minusOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (void)intersectOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (void)unionSet:(NSSet<ObjectType> *)other;
- (void)minusSet:(NSSet<ObjectType> *)other;
- (void)intersectSet:(NSSet<ObjectType> *)other;
- (void)sortUsingComparator:(NSComparator)cmptr;
- (void)sortUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;
- (void)filterUsingPredicate:(NSPredicate *)p;
@end

/* Key-value coding's ordered to-many proxy: changes go through the
 * object's indexed accessors, or a changed copy set with set<Key>:. */
@interface NSObject (NSKeyValueCodingOrderedSets)
- (NSMutableOrderedSet *)mutableOrderedSetValueForKey:(NSString *)key;
- (NSMutableOrderedSet *)mutableOrderedSetValueForKeyPath:(NSString *)keyPath;
@end

#endif
