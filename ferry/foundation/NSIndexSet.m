/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSIndexSet, NSMutableIndexSet and NSSortDescriptor,
 * written from Apple's public documentation. An index set keeps its
 * indexes as a sorted list of ranges that neither touch nor overlap, so a
 * table's selection of a million rows is one range. A sort descriptor
 * compares two objects by the value at its key path, with its selector
 * (compare: unless told otherwise) or its block, ascending or descending;
 * arrays sort by a list of them, the first deciding unless two objects tie.
 * Nibs keep a descriptor's key under "NSKey", its direction under
 * "NSAscending" and its selector's name under "NSSelector". */
#import "FInternal.h"

F_EXPORT NSRange NSIntersectionRange(NSRange a, NSRange b)
{
    NSUInteger lo = MAX(a.location, b.location), hi = MIN(NSMaxRange(a), NSMaxRange(b));
    return hi > lo ? NSMakeRange(lo, hi - lo) : NSMakeRange(0, 0);
}
F_EXPORT NSRange NSUnionRange(NSRange a, NSRange b)
{
    NSUInteger lo = MIN(a.location, b.location), hi = MAX(NSMaxRange(a), NSMaxRange(b));
    return NSMakeRange(lo, hi - lo);
}

/* ---- NSIndexSet ---------------------------------------------------------------------- */

@implementation NSIndexSet {
@protected
    NSRange *_ranges;
    NSUInteger _count;   /* ranges */
    NSUInteger _cap;
}

+ (instancetype)indexSet { return [[[self alloc] init] autorelease]; }
+ (instancetype)indexSetWithIndex:(NSUInteger)i { return [[[self alloc] initWithIndex:i] autorelease]; }
+ (instancetype)indexSetWithIndexesInRange:(NSRange)r { return [[[self alloc] initWithIndexesInRange:r] autorelease]; }
- (instancetype)init { return [super init]; }
- (instancetype)initWithIndexesInRange:(NSRange)r
{
    if ((self = [super init]) && r.length) {
        _cap = 1;
        _ranges = malloc(sizeof(NSRange));
        _ranges[0] = r;
        _count = 1;
    }
    return self;
}
- (instancetype)initWithIndex:(NSUInteger)i { return [self initWithIndexesInRange:NSMakeRange(i, 1)]; }
- (instancetype)initWithIndexSet:(NSIndexSet *)other
{
    if ((self = [super init]) && other && other->_count) {
        _cap = _count = other->_count;
        _ranges = malloc(_cap * sizeof(NSRange));
        memcpy(_ranges, other->_ranges, _count * sizeof(NSRange));
    }
    return self;
}
- (void)dealloc
{
    free(_ranges);
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    if ([self class] == [NSIndexSet class])
        return [self retain];
    return [[NSIndexSet allocWithZone:zone] initWithIndexSet:self];
}
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableIndexSet allocWithZone:zone] initWithIndexSet:self]; }

- (NSUInteger)count
{
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < _count; i++)
        n += _ranges[i].length;
    return n;
}
- (NSUInteger)firstIndex { return _count ? _ranges[0].location : NSNotFound; }
- (NSUInteger)lastIndex { return _count ? NSMaxRange(_ranges[_count - 1]) - 1 : NSNotFound; }

/* The first range that ends after i (so holds i, or comes after it). */
static NSUInteger range_after(NSIndexSet *s, NSRange *ranges, NSUInteger count, NSUInteger i)
{
    NSUInteger lo = 0, hi = count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (NSMaxRange(ranges[mid]) <= i)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}
- (BOOL)containsIndex:(NSUInteger)i
{
    NSUInteger k = range_after(self, _ranges, _count, i);
    return k < _count && NSLocationInRange(i, _ranges[k]);
}
- (BOOL)containsIndexesInRange:(NSRange)r
{
    if (!r.length)
        return NO;
    NSUInteger k = range_after(self, _ranges, _count, r.location);
    return k < _count && _ranges[k].location <= r.location && NSMaxRange(_ranges[k]) >= NSMaxRange(r);
}
- (BOOL)containsIndexes:(NSIndexSet *)other
{
    for (NSUInteger i = 0; i < other->_count; i++)
        if (![self containsIndexesInRange:other->_ranges[i]])
            return NO;
    return YES;
}
- (BOOL)intersectsIndexesInRange:(NSRange)r
{
    if (!r.length)
        return NO;
    NSUInteger k = range_after(self, _ranges, _count, r.location);
    return k < _count && _ranges[k].location < NSMaxRange(r);
}
- (NSUInteger)countOfIndexesInRange:(NSRange)r
{
    NSUInteger n = 0;
    for (NSUInteger k = range_after(self, _ranges, _count, r.location); k < _count; k++) {
        NSRange both = NSIntersectionRange(_ranges[k], r);
        if (!both.length)
            break;
        n += both.length;
    }
    return n;
}
- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)i
{
    NSUInteger k = range_after(self, _ranges, _count, i);
    if (k >= _count)
        return NSNotFound;
    return _ranges[k].location > i ? _ranges[k].location : i;
}
- (NSUInteger)indexGreaterThanIndex:(NSUInteger)i
{
    return i == NSNotFound || i + 1 == 0 ? NSNotFound : [self indexGreaterThanOrEqualToIndex:i + 1];
}
- (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)i
{
    for (NSUInteger k = _count; k-- > 0;) {
        if (_ranges[k].location <= i)
            return NSLocationInRange(i, _ranges[k]) ? i : NSMaxRange(_ranges[k]) - 1;
    }
    return NSNotFound;
}
- (NSUInteger)indexLessThanIndex:(NSUInteger)i { return i == 0 ? NSNotFound : [self indexLessThanOrEqualToIndex:i - 1]; }
- (NSUInteger)getIndexes:(NSUInteger *)buffer maxCount:(NSUInteger)max inIndexRange:(NSRangePointer)within
{
    NSRange r = within ? *within : NSMakeRange(0, NSNotFound);
    NSUInteger n = 0, end = NSMaxRange(r) < r.location ? NSUIntegerMax : NSMaxRange(r);
    NSUInteger next = r.location;
    for (NSUInteger k = range_after(self, _ranges, _count, r.location); k < _count && n < max; k++) {
        NSUInteger i = MAX(_ranges[k].location, r.location);
        for (; i < NSMaxRange(_ranges[k]) && i < end && n < max; i++)
            buffer[n++] = i, next = i + 1;
        if (i >= end)
            break;
    }
    if (within) {
        NSUInteger stop = n == max ? next : end;
        within->length = end > stop ? end - stop : 0;
        within->location = stop;
    }
    return n;
}
- (BOOL)isEqualToIndexSet:(NSIndexSet *)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSIndexSet class]] || other->_count != _count)
        return NO;
    for (NSUInteger i = 0; i < _count; i++)
        if (!NSEqualRanges(_ranges[i], other->_ranges[i]))
            return NO;
    return YES;
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[NSIndexSet class]] && [self isEqualToIndexSet:other]; }
- (NSUInteger)hash { return [self count] ^ ([self firstIndex] << 8); }

- (void)enumerateRangesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSRange, BOOL *))block
{
    BOOL stop = NO;
    NSUInteger n = _count;
    NSRange copy[n ? n : 1];
    memcpy(copy, _ranges, n * sizeof(NSRange));
    for (NSUInteger k = 0; k < n && !stop; k++)
        block(copy[(opts & NSEnumerationReverse) ? n - 1 - k : k], &stop);
}
- (void)enumerateRangesUsingBlock:(void (^)(NSRange, BOOL *))block { [self enumerateRangesWithOptions:0 usingBlock:block]; }
- (void)enumerateIndexesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger, BOOL *))block
{
    [self enumerateRangesWithOptions:opts usingBlock:^(NSRange r, BOOL *stop) {
        for (NSUInteger j = 0; j < r.length && !*stop; j++)
            block((opts & NSEnumerationReverse) ? NSMaxRange(r) - 1 - j : r.location + j, stop);
    }];
}
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger, BOOL *))block { [self enumerateIndexesWithOptions:0 usingBlock:block]; }
- (NSUInteger)indexPassingTest:(BOOL (^)(NSUInteger, BOOL *))predicate
{
    __block NSUInteger found = NSNotFound;
    [self enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (predicate(i, stop)) {
            found = i;
            *stop = YES;
        }
    }];
    return found;
}
- (NSIndexSet *)indexesPassingTest:(BOOL (^)(NSUInteger, BOOL *))predicate
{
    NSMutableIndexSet *out = [NSMutableIndexSet indexSet];
    [self enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (predicate(i, stop))
            [out addIndex:i];
    }];
    return out;
}
- (NSString *)description
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<%s: %p>[number of indexes: %lu (in %lu ranges), indexes: (",
                                                           object_getClassName(self), (void *)self,
                                                           (unsigned long)[self count], (unsigned long)_count];
    for (NSUInteger k = 0; k < _count; k++) {
        if (k)
            [s appendString:@" "];
        if (_ranges[k].length == 1)
            [s appendFormat:@"%lu", (unsigned long)_ranges[k].location];
        else
            [s appendFormat:@"%lu-%lu", (unsigned long)_ranges[k].location, (unsigned long)NSMaxRange(_ranges[k]) - 1];
    }
    [s appendString:@")]"];
    return s;
}
@end

/* ---- NSMutableIndexSet ------------------------------------------------------------------- */

@implementation NSMutableIndexSet
- (id)copyWithZone:(NSZone *)zone { return [[NSIndexSet allocWithZone:zone] initWithIndexSet:self]; }

static void make_room(NSMutableIndexSet *s, NSRange **ranges, NSUInteger *count, NSUInteger *cap, NSUInteger more)
{
    if (*count + more <= *cap)
        return;
    *cap = (*count + more) * 2;
    *ranges = realloc(*ranges, *cap * sizeof(NSRange));
}
- (void)addIndexesInRange:(NSRange)r
{
    if (!r.length)
        return;
    /* the ranges that touch or overlap r are merged into one */
    NSUInteger first = range_after(self, _ranges, _count, r.location ? r.location - 1 : 0);
    if (first < _count && NSMaxRange(_ranges[first]) < r.location)
        first++;
    NSUInteger last = first;
    NSUInteger lo = r.location, hi = NSMaxRange(r);
    while (last < _count && _ranges[last].location <= hi) {
        lo = MIN(lo, _ranges[last].location);
        hi = MAX(hi, NSMaxRange(_ranges[last]));
        last++;
    }
    NSUInteger merged = last - first;
    if (merged == 0) {
        make_room(self, &_ranges, &_count, &_cap, 1);
        memmove(_ranges + first + 1, _ranges + first, (_count - first) * sizeof(NSRange));
        _count++;
    } else if (merged > 1) {
        memmove(_ranges + first + 1, _ranges + last, (_count - last) * sizeof(NSRange));
        _count -= merged - 1;
    }
    _ranges[first] = NSMakeRange(lo, hi - lo);
}
- (void)addIndex:(NSUInteger)i { [self addIndexesInRange:NSMakeRange(i, 1)]; }
- (void)addIndexes:(NSIndexSet *)other
{
    if (other == self)
        return;
    for (NSUInteger k = 0; k < other->_count; k++)
        [self addIndexesInRange:other->_ranges[k]];
}
- (void)removeIndexesInRange:(NSRange)r
{
    if (!r.length)
        return;
    NSUInteger end = NSMaxRange(r);
    for (NSUInteger k = range_after(self, _ranges, _count, r.location); k < _count && _ranges[k].location < end;) {
        NSRange g = _ranges[k];
        BOOL before = g.location < r.location, after = NSMaxRange(g) > end;
        if (before && after) {
            /* split in two */
            make_room(self, &_ranges, &_count, &_cap, 1);
            memmove(_ranges + k + 2, _ranges + k + 1, (_count - k - 1) * sizeof(NSRange));
            _count++;
            _ranges[k] = NSMakeRange(g.location, r.location - g.location);
            _ranges[k + 1] = NSMakeRange(end, NSMaxRange(g) - end);
            return;
        }
        if (before) {
            _ranges[k].length = r.location - g.location;
            k++;
        } else if (after) {
            _ranges[k] = NSMakeRange(end, NSMaxRange(g) - end);
            return;
        } else {
            memmove(_ranges + k, _ranges + k + 1, (_count - k - 1) * sizeof(NSRange));
            _count--;
        }
    }
}
- (void)removeIndex:(NSUInteger)i { [self removeIndexesInRange:NSMakeRange(i, 1)]; }
- (void)removeIndexes:(NSIndexSet *)other
{
    if (other == self) {
        [self removeAllIndexes];
        return;
    }
    for (NSUInteger k = 0; k < other->_count; k++)
        [self removeIndexesInRange:other->_ranges[k]];
}
- (void)removeAllIndexes { _count = 0; }
/* Moves the indexes from i on by delta; moving down drops those it passes over. */
- (void)shiftIndexesStartingAtIndex:(NSUInteger)i by:(NSInteger)delta
{
    if (!delta || !_count)
        return;
    NSIndexSet *old = [[NSIndexSet alloc] initWithIndexSet:self];
    [self removeIndexesInRange:NSMakeRange(i, NSUIntegerMax - i)];
    if (delta < 0)
        [self removeIndexesInRange:NSMakeRange(i >= (NSUInteger)-delta ? i + delta : 0,
                                               i >= (NSUInteger)-delta ? (NSUInteger)-delta : i)];
    for (NSUInteger k = 0; k < old->_count; k++) {
        NSRange g = NSIntersectionRange(old->_ranges[k], NSMakeRange(i, NSUIntegerMax - i));
        if (!g.length)
            continue;
        NSInteger at = (NSInteger)g.location + delta;
        if (at < 0) {
            if ((NSInteger)g.length + at <= 0)
                continue;
            g.length += at;
            at = 0;
        }
        [self addIndexesInRange:NSMakeRange((NSUInteger)at, g.length)];
    }
    [old release];
}
@end

/* ---- arrays and index sets -------------------------------------------------------------- */

@implementation NSArray (NSIndexSetAccess)
- (NSArray *)objectsAtIndexes:(NSIndexSet *)indexes
{
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:[indexes count]];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [out addObject:[self objectAtIndex:i]];
    }];
    return out;
}
- (NSIndexSet *)indexesOfObjectsPassingTest:(BOOL (^)(id, NSUInteger, BOOL *))predicate
{
    NSMutableIndexSet *out = [NSMutableIndexSet indexSet];
    [self enumerateObjectsUsingBlock:^(id o, NSUInteger i, BOOL *stop) {
        if (predicate(o, i, stop))
            [out addIndex:i];
    }];
    return out;
}
- (void)enumerateObjectsAtIndexes:(NSIndexSet *)indexes options:(NSEnumerationOptions)opts
                       usingBlock:(void (^)(id, NSUInteger, BOOL *))block
{
    [indexes enumerateIndexesWithOptions:opts usingBlock:^(NSUInteger i, BOOL *stop) {
        block([self objectAtIndex:i], i, stop);
    }];
}
@end

@implementation NSMutableArray (NSIndexSetAccess)
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes
{
    [indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *stop) {
        [self removeObjectAtIndex:i];
    }];
}
- (void)insertObjects:(NSArray *)objects atIndexes:(NSIndexSet *)indexes
{
    __block NSUInteger j = 0;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [self insertObject:[objects objectAtIndex:j++] atIndex:i];
    }];
}
- (void)replaceObjectsAtIndexes:(NSIndexSet *)indexes withObjects:(NSArray *)objects
{
    __block NSUInteger j = 0;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [self replaceObjectAtIndex:i withObject:[objects objectAtIndex:j++]];
    }];
}
@end

/* ---- NSSortDescriptor ---------------------------------------------------------------------- */

@implementation NSSortDescriptor {
    NSString *_key;
    BOOL _ascending;
    SEL _selector;
    NSComparator _comparator;
}
+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending
{
    return [[[self alloc] initWithKey:key ascending:ascending] autorelease];
}
+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector
{
    return [[[self alloc] initWithKey:key ascending:ascending selector:selector] autorelease];
}
+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)cmp
{
    return [[[self alloc] initWithKey:key ascending:ascending comparator:cmp] autorelease];
}
- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending
{
    return [self initWithKey:key ascending:ascending selector:@selector(compare:)];
}
- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector
{
    if ((self = [super init])) {
        _key = [key copy];
        _ascending = ascending;
        _selector = selector ? selector : @selector(compare:);
    }
    return self;
}
- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)cmp
{
    if ((self = [self initWithKey:key ascending:ascending selector:@selector(compare:)]))
        _comparator = [cmp copy];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *key = [coder decodeObjectForKey:@"NSKey"];
    NSString *sel = [coder decodeObjectForKey:@"NSSelector"];
    BOOL ascending = [coder containsValueForKey:@"NSAscending"] ? [coder decodeBoolForKey:@"NSAscending"] : YES;
    return [self initWithKey:[key isKindOfClass:[NSString class]] ? key : nil ascending:ascending
                    selector:[sel isKindOfClass:[NSString class]] ? NSSelectorFromString(sel) : @selector(compare:)];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_key)
        [coder encodeObject:_key forKey:@"NSKey"];
    [coder encodeBool:_ascending forKey:@"NSAscending"];
    [coder encodeObject:NSStringFromSelector(_selector) forKey:@"NSSelector"];
}
- (void)dealloc
{
    [_key release];
    [_comparator release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
+ (BOOL)supportsSecureCoding { return YES; }
- (NSString *)key { return _key; }
- (BOOL)ascending { return _ascending; }
- (SEL)selector { return _selector; }
- (NSComparator)comparator { return _comparator; }
- (id)reversedSortDescriptor
{
    NSSortDescriptor *d = [[[self class] alloc] initWithKey:_key ascending:!_ascending selector:_selector];
    d->_comparator = [_comparator copy];
    return [d autorelease];
}
- (NSComparisonResult)compareObject:(id)a toObject:(id)b
{
    id va = _key ? [a valueForKeyPath:_key] : a, vb = _key ? [b valueForKeyPath:_key] : b;
    NSComparisonResult r;
    if (va == vb)
        r = NSOrderedSame;
    else if (!va)
        r = NSOrderedAscending;   /* nothing sorts first */
    else if (!vb)
        r = NSOrderedDescending;
    else if (_comparator)
        r = _comparator(va, vb);
    else
        r = (NSComparisonResult)((NSInteger(*)(id, SEL, id))objc_msgSend)(va, _selector, vb);
    return _ascending ? r : -r;
}
- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[NSSortDescriptor class]])
        return NO;
    NSSortDescriptor *o = other;
    return o->_ascending == _ascending && o->_selector == _selector &&
           (o->_key == _key || [o->_key isEqualToString:_key]);
}
- (NSUInteger)hash { return [_key hash] ^ _ascending; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"(%@, %@, %@)", _key, _ascending ? @"ascending" : @"descending",
                                      NSStringFromSelector(_selector)];
}
@end

static NSComparisonResult by_descriptors(NSArray *descriptors, id a, id b)
{
    for (NSSortDescriptor *d in descriptors) {
        NSComparisonResult r = [d compareObject:a toObject:b];
        if (r != NSOrderedSame)
            return r;
    }
    return NSOrderedSame;
}

@implementation NSArray (NSSortDescriptorSorting)
- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)descriptors
{
    if (![descriptors count])
        return [[self copy] autorelease];
    return [self sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return by_descriptors(descriptors, a, b);
    }];
}
@end

@implementation NSMutableArray (NSSortDescriptorSorting)
- (void)sortUsingDescriptors:(NSArray *)descriptors
{
    if (![descriptors count])
        return;
    [self sortUsingComparator:^NSComparisonResult(id a, id b) {
        return by_descriptors(descriptors, a, b);
    }];
}
@end
