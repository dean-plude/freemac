/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSIndexPath (Ferry 0.19.0), written from Apple's
 * public documentation. An index path is a list of indexes, each one a
 * step down a tree: {1, 0} is the first child of the second node at the
 * top. Paths are immutable; adding or removing an index gives a new one.
 * They compare index by index, a shorter path that the longer one starts
 * with coming first, so sorting paths puts a tree's nodes in the order an
 * outline shows them. Its description follows the form Apple documents,
 * "<NSIndexPath: 0x...> {length = 2, path = 1 - 0}". Keyed archiving of
 * index paths isn't done. */
#import "FInternal.h"

@implementation NSIndexPath {
    NSUInteger *_indexes;
    NSUInteger _length;
}

+ (instancetype)indexPathWithIndex:(NSUInteger)index { return [[[self alloc] initWithIndex:index] autorelease]; }
+ (instancetype)indexPathWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length
{
    return [[[self alloc] initWithIndexes:indexes length:length] autorelease];
}
- (instancetype)init { return [self initWithIndexes:NULL length:0]; }
- (instancetype)initWithIndex:(NSUInteger)index { return [self initWithIndexes:&index length:1]; }
- (instancetype)initWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length
{
    if ((self = [super init])) {
        if (!indexes)
            length = 0;
        _length = length;
        if (length) {
            _indexes = malloc(length * sizeof(NSUInteger));
            memcpy(_indexes, indexes, length * sizeof(NSUInteger));
        }
    }
    return self;
}
- (void)dealloc
{
    free(_indexes);
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (NSUInteger)length { return _length; }
- (NSUInteger)indexAtPosition:(NSUInteger)position { return position < _length ? _indexes[position] : NSNotFound; }
- (void)getIndexes:(NSUInteger *)indexes range:(NSRange)range
{
    if (NSMaxRange(range) > _length)
        FRaise(NSRangeException, @"-[NSIndexPath getIndexes:range:]: range {%lu, %lu} beyond length %lu",
               (unsigned long)range.location, (unsigned long)range.length, (unsigned long)_length);
    if (indexes && range.length)
        memcpy(indexes, _indexes + range.location, range.length * sizeof(NSUInteger));
}
- (void)getIndexes:(NSUInteger *)indexes { [self getIndexes:indexes range:NSMakeRange(0, _length)]; }

- (NSIndexPath *)indexPathByAddingIndex:(NSUInteger)index
{
    NSUInteger *buf = malloc((_length + 1) * sizeof(NSUInteger));
    if (_length)
        memcpy(buf, _indexes, _length * sizeof(NSUInteger));
    buf[_length] = index;
    NSIndexPath *p = [[[self class] alloc] initWithIndexes:buf length:_length + 1];
    free(buf);
    return [p autorelease];
}
- (NSIndexPath *)indexPathByRemovingLastIndex
{
    return [[[[self class] alloc] initWithIndexes:_indexes length:_length ? _length - 1 : 0] autorelease];
}

- (NSComparisonResult)compare:(NSIndexPath *)other
{
    NSUInteger n = [other length];
    for (NSUInteger i = 0; i < _length && i < n; i++) {
        NSUInteger o = [other indexAtPosition:i];
        if (_indexes[i] != o)
            return _indexes[i] < o ? NSOrderedAscending : NSOrderedDescending;
    }
    return _length == n ? NSOrderedSame : _length < n ? NSOrderedAscending : NSOrderedDescending;
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    return [other isKindOfClass:[NSIndexPath class]] && [other length] == _length &&
           [self compare:other] == NSOrderedSame;
}
- (NSUInteger)hash
{
    NSUInteger h = _length;
    for (NSUInteger i = 0; i < _length; i++)
        h = h * 31 + _indexes[i];
    return h;
}
- (NSString *)description
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<%@: %p> {length = %lu, path = ", [self class], self,
                                                           (unsigned long)_length];
    for (NSUInteger i = 0; i < _length; i++)
        [s appendFormat:i ? @" - %lu" : @"%lu", (unsigned long)_indexes[i]];
    [s appendString:@"}"];
    return s;
}
@end
