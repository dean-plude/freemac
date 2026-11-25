/* SPDX-License-Identifier: GPL-3.0-or-later
 * Foundation calls the apps' own frameworks make (KeePassKit, which
 * MacPass is built on, first), found by compiling those frameworks' source
 * against Ferry's SDK (freemac 1.223, Ferry 0.47.0). Each is written from
 * Apple's public reference for it, on the classes' public methods, so it
 * works for every subclass:
 *
 * - NSCountedSet, a set that counts how many times each object was added.
 * - NSMutableData's increaseLengthBy:, replaceBytesInRange:withBytes:length:
 *   (which grows or shrinks the data when the lengths differ) and
 *   resetBytesInRange:.
 * - NSNumber's initializers for the C types it had only factory methods for.
 * - NSMutableSet's initWithCapacity:.
 * - NSIndexSet's enumerateIndexesInRange:options:usingBlock:.
 * - NSString's initWithCharactersNoCopy:length:freeWhenDone: (the
 *   characters are copied, and freed at once when the string was to free
 *   them) and rangeOfString:options:range:locale: (the locale is used only
 *   as rangeOfString:options:range: uses the current one). */
#import "FInternal.h"

/* ---- NSCountedSet ----------------------------------------------------------------------- */

@implementation NSCountedSet {
    NSMapTable *_counts; /* object -> NSNumber, compared with isEqual: */
}
- (instancetype)init { return [self initWithCapacity:0]; }
/* the designated initializer; NSSet's init would come back here through
 * initWithObjects:count:, and NSObject's has nothing to set up */
- (instancetype)initWithCapacity:(NSUInteger)capacity
{
    _counts = [[NSMapTable strongToStrongObjectsMapTable] retain];
    return self;
}
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    if ((self = [self initWithCapacity:count]))
        for (NSUInteger i = 0; i < count; i++)
            [self addObject:objects[i]];
    return self;
}
- (instancetype)initWithArray:(NSArray *)array
{
    if ((self = [self initWithCapacity:[array count]]))
        [self addObjectsFromArray:array];
    return self;
}
- (instancetype)initWithSet:(NSSet *)set
{
    if ((self = [self initWithCapacity:[set count]]))
        for (id o in set)
            [self addObject:o];
    return self;
}
- (void)dealloc
{
    [_counts release];
    [super dealloc];
}
- (NSUInteger)count { return [_counts count]; }
- (id)member:(id)obj
{
    if (!obj)
        return nil;
    for (id key in _counts)
        if ([key isEqual:obj])
            return key;
    return nil;
}
- (NSUInteger)countForObject:(id)obj { return [[_counts objectForKey:obj] unsignedIntegerValue]; }
- (NSEnumerator *)objectEnumerator { return [_counts keyEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    return [_counts countByEnumeratingWithState:state objects:buffer count:len];
}
- (void)addObject:(id)obj
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[NSCountedSet addObject:]: object cannot be nil");
    id key = [self member:obj] ?: obj;
    [_counts setObject:@([self countForObject:key] + 1) forKey:key];
}
- (void)removeObject:(id)obj
{
    id key = [self member:obj];
    if (!key)
        return;
    NSUInteger n = [self countForObject:key];
    if (n > 1)
        [_counts setObject:@(n - 1) forKey:key];
    else
        [_counts removeObjectForKey:key];
}
- (void)removeAllObjects { [_counts removeAllObjects]; }
- (id)copyWithZone:(NSZone *)zone { return [[NSCountedSet allocWithZone:zone] initWithCountedSet:self]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [self copyWithZone:zone]; }
- (instancetype)initWithCountedSet:(NSCountedSet *)other
{
    if ((self = [self initWithCapacity:[other count]]))
        for (id o in other)
            [_counts setObject:@([other countForObject:o]) forKey:o];
    return self;
}
@end

/* ---- NSMutableData ---------------------------------------------------------------------- */

@implementation NSMutableData (FerryFrameworkCalls)
- (void)increaseLengthBy:(NSUInteger)extra { [self setLength:[self length] + extra]; }
- (void)resetBytesInRange:(NSRange)range
{
    if (NSMaxRange(range) > [self length])
        [self setLength:NSMaxRange(range)];
    memset((char *)[self mutableBytes] + range.location, 0, range.length);
}
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes length:(NSUInteger)length
{
    NSUInteger old = [self length];
    if (range.location > old)
        FRaise(NSRangeException, @"*** -[NSMutableData replaceBytesInRange:withBytes:length:]: range %@ beyond "
                                 @"length %lu",
               NSStringFromRange(range), (unsigned long)old);
    NSUInteger end = MIN(NSMaxRange(range), old);
    NSUInteger tail = old - end;
    /* keep the replacement if it lies inside the data, which moves */
    void *copy = NULL;
    if (length && bytes) {
        copy = malloc(length);
        memcpy(copy, bytes, length);
    }
    NSUInteger now = range.location + length + tail;
    if (now > old)
        [self setLength:now];
    char *p = [self mutableBytes];
    memmove(p + range.location + length, p + end, tail);
    if (length)
        copy ? memcpy(p + range.location, copy, length) : memset(p + range.location, 0, length);
    free(copy);
    if (now < old)
        [self setLength:now];
}
@end

/* ---- NSNumber --------------------------------------------------------------------------- */

#define NUMBER_INIT(sel, type, factory)       \
    -(instancetype)sel(type)v                 \
    {                                         \
        [self release];                       \
        return [[NSNumber factory:v] retain]; \
    }

@implementation NSNumber (FerryFrameworkCalls)
NUMBER_INIT(initWithChar:, char, numberWithChar)
NUMBER_INIT(initWithUnsignedChar:, unsigned char, numberWithUnsignedChar)
NUMBER_INIT(initWithShort:, short, numberWithShort)
NUMBER_INIT(initWithUnsignedShort:, unsigned short, numberWithUnsignedShort)
NUMBER_INIT(initWithUnsignedInt:, unsigned int, numberWithUnsignedInt)
NUMBER_INIT(initWithLong:, long, numberWithLong)
NUMBER_INIT(initWithUnsignedLong:, unsigned long, numberWithUnsignedLong)
NUMBER_INIT(initWithLongLong:, long long, numberWithLongLong)
NUMBER_INIT(initWithUnsignedLongLong:, unsigned long long, numberWithUnsignedLongLong)
NUMBER_INIT(initWithFloat:, float, numberWithFloat)
NUMBER_INIT(initWithUnsignedInteger:, NSUInteger, numberWithUnsignedInteger)
@end

/* ---- NSMutableSet and NSIndexSet ---------------------------------------------------------- */

@implementation NSMutableSet (FerryFrameworkCalls)
- (instancetype)initWithCapacity:(NSUInteger)capacity { return [self init]; }
@end

@implementation NSIndexSet (FerryFrameworkCalls)
- (void)enumerateIndexesInRange:(NSRange)range
                        options:(NSEnumerationOptions)opts
                     usingBlock:(void (^)(NSUInteger idx, BOOL *stop))block
{
    [self enumerateIndexesWithOptions:opts usingBlock:^(NSUInteger idx, BOOL *stop) {
        if (NSLocationInRange(idx, range))
            block(idx, stop);
        else if ((opts & NSEnumerationReverse) ? idx < range.location : idx >= NSMaxRange(range))
            *stop = YES;
    }];
}
@end

/* ---- NSString --------------------------------------------------------------------------- */

@implementation NSString (FerryFrameworkCalls)
- (instancetype)initWithCharactersNoCopy:(unichar *)characters length:(NSUInteger)length freeWhenDone:(BOOL)free_
{
    self = [self initWithCharacters:characters length:length];
    if (free_)
        free(characters);
    return self;
}
- (NSRange)rangeOfString:(NSString *)str options:(NSStringCompareOptions)mask range:(NSRange)range locale:(NSLocale *)locale
{
    return [self rangeOfString:str options:mask range:range];
}
@end
