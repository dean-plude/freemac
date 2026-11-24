/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSPredicate and NSCompoundPredicate, as Apple's
 * "Predicate Programming Guide" and the class references describe them.
 * Our own code; no Apple code was used.
 *
 * A predicate is read from a format string by NSPredicateParser.m into a
 * tree: NSCompoundPredicate (AND, OR and NOT) over NSComparisonPredicate
 * (NSComparisonPredicate.m), whose two sides are NSExpressions
 * (NSExpression.m); TRUEPREDICATE and FALSEPREDICATE; and blocks.
 *
 * Not done: keyed archiving of predicates. */
#import "FExpression.h"
#include <stdarg.h>

/* ---- the predicate classes --------------------------------------------------------- */

@interface FValuePredicate : NSPredicate {
@public
    BOOL value;
}
@end
@interface FBlockPredicate : NSPredicate {
@public
    BOOL (^block)(id, NSDictionary *);
}
@end

@implementation NSPredicate
+ (NSPredicate *)predicateWithFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    NSPredicate *p = FParsePredicate(format, &ap, nil);
    va_end(ap);
    return p;
}
+ (NSPredicate *)predicateWithFormat:(NSString *)format arguments:(va_list)args
{
    va_list ap;
    va_copy(ap, args);
    NSPredicate *p = FParsePredicate(format, &ap, nil);
    va_end(ap);
    return p;
}
+ (NSPredicate *)predicateWithFormat:(NSString *)format argumentArray:(NSArray *)arguments
{
    return FParsePredicate(format, NULL, arguments ?: @[]);
}
+ (NSPredicate *)predicateWithValue:(BOOL)v
{
    FValuePredicate *p = [[[FValuePredicate alloc] init] autorelease];
    p->value = v;
    return p;
}
+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id, NSDictionary *))block
{
    FBlockPredicate *p = [[[FBlockPredicate alloc] init] autorelease];
    p->block = [block copy];
    return p;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
/* Archived as its format string, which reads back as the same predicate
 * (a block predicate can't be archived). */
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    if ([self isKindOfClass:[FBlockPredicate class]])
        FRaise(NSInvalidArgumentException, @"*** -[NSPredicate encodeWithCoder:]: block predicates can't be archived");
    [coder encodeObject:[self predicateFormat] forKey:@"NS.predicateFormat"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *format = [coder decodeObjectForKey:@"NS.predicateFormat"];
    [self release];
    if (![format isKindOfClass:[NSString class]])
        return nil;
    return [FParsePredicate(format, NULL, @[]) retain];
}
- (NSString *)predicateFormat { return @""; }
- (NSString *)description { return [self predicateFormat]; }
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars { return NO; }
- (NSPredicate *)_substitute:(NSDictionary *)vars { return self; }
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set {}
/* The predicate's tree, for Core Data's SQLite store to read (freemac
 * 1.209, Ferry 0.35.0): nil for a predicate it can't describe. */
- (id)_ferryStructure { return nil; }
- (BOOL)evaluateWithObject:(id)object { return [self _evaluate:object vars:nil]; }
- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings
{
    return [self _evaluate:object vars:bindings ?: @{}];
}
- (instancetype)predicateWithSubstitutionVariables:(NSDictionary *)variables
{
    return (id)[self _substitute:variables ?: @{}];
}
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[NSPredicate class]] && ![self isKindOfClass:[FBlockPredicate class]] &&
                             [[self predicateFormat] isEqualToString:[other predicateFormat]]);
}
- (NSUInteger)hash { return [[self predicateFormat] hash]; }
@end

@implementation FValuePredicate
- (NSString *)predicateFormat { return value ? @"TRUEPREDICATE" : @"FALSEPREDICATE"; }
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars { return value; }
- (id)_ferryStructure { return @{@"type" : @"value", @"value" : @(value)}; }
@end

@implementation FBlockPredicate
- (void)dealloc
{
    [block release];
    [super dealloc];
}
- (NSString *)predicateFormat { return @"BLOCKPREDICATE"; }
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars { return block(object, vars); }
@end

@implementation NSCompoundPredicate {
    NSCompoundPredicateType _type;
    NSArray *_subpredicates;
}
- (instancetype)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates
{
    if ((self = [super init])) {
        _type = type;
        _subpredicates = [subpredicates copy] ?: [[NSArray alloc] init];
    }
    return self;
}
+ (NSCompoundPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates
{
    return [[[self alloc] initWithType:NSAndPredicateType subpredicates:subpredicates] autorelease];
}
+ (NSCompoundPredicate *)orPredicateWithSubpredicates:(NSArray *)subpredicates
{
    return [[[self alloc] initWithType:NSOrPredicateType subpredicates:subpredicates] autorelease];
}
+ (NSCompoundPredicate *)notPredicateWithSubpredicate:(NSPredicate *)predicate
{
    return [[[self alloc] initWithType:NSNotPredicateType subpredicates:@[ predicate ]] autorelease];
}
- (void)dealloc
{
    [_subpredicates release];
    [super dealloc];
}
- (NSCompoundPredicateType)compoundPredicateType { return _type; }
- (NSArray *)subpredicates { return _subpredicates; }
- (NSString *)predicateFormat
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSPredicate *p in _subpredicates) {
        NSString *f = [p predicateFormat];
        if ([p isKindOfClass:[NSCompoundPredicate class]] && [(NSCompoundPredicate *)p compoundPredicateType] != NSNotPredicateType &&
            [[(NSCompoundPredicate *)p subpredicates] count] > 1)
            f = [NSString stringWithFormat:@"(%@)", f];
        [parts addObject:f];
    }
    if (_type == NSNotPredicateType)
        return [@"NOT " stringByAppendingString:[parts firstObject] ?: @"TRUEPREDICATE"];
    return [parts componentsJoinedByString:_type == NSAndPredicateType ? @" AND " : @" OR "];
}
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars
{
    if (_type == NSNotPredicateType)
        return ![[_subpredicates firstObject] _evaluate:object vars:vars];
    for (NSPredicate *p in _subpredicates) {
        BOOL r = [p _evaluate:object vars:vars];
        if (_type == NSAndPredicateType && !r)
            return NO;
        if (_type == NSOrPredicateType && r)
            return YES;
    }
    return _type == NSAndPredicateType;
}
- (NSPredicate *)_substitute:(NSDictionary *)vars
{
    NSMutableArray *subs = [NSMutableArray array];
    for (NSPredicate *p in _subpredicates)
        [subs addObject:[p _substitute:vars]];
    return [[[NSCompoundPredicate alloc] initWithType:_type subpredicates:subs] autorelease];
}
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set
{
    for (NSPredicate *p in _subpredicates)
        [p _ferryAddKeyPathsTo:set];
}
- (id)_ferryStructure
{
    static NSString *const types[] = {@"not", @"and", @"or"};
    NSMutableArray *parts = [NSMutableArray array];
    for (NSPredicate *p in _subpredicates) {
        id s = [p _ferryStructure];
        if (!s)
            return nil;
        [parts addObject:s];
    }
    return @{@"type" : types[_type], @"subpredicates" : parts};
}
@end

/* ---- filtering collections ------------------------------------------------------------- */

@implementation NSArray (NSPredicateSupport)
- (NSArray *)filteredArrayUsingPredicate:(NSPredicate *)predicate
{
    if (!predicate)
        FRaise(NSInvalidArgumentException, @"*** -[NSArray filteredArrayUsingPredicate:]: predicate cannot be nil");
    NSMutableArray *out = [NSMutableArray array];
    for (id o in self)
        if ([predicate evaluateWithObject:o])
            [out addObject:o];
    return [NSArray arrayWithArray:out];
}
@end
@implementation NSMutableArray (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate
{
    NSArray *keep = [self filteredArrayUsingPredicate:predicate];
    [self setArray:keep];
}
@end
@implementation NSSet (NSPredicateSupport)
- (NSSet *)filteredSetUsingPredicate:(NSPredicate *)predicate
{
    return [NSSet setWithArray:[[self allObjects] filteredArrayUsingPredicate:predicate]];
}
@end
@implementation NSMutableSet (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate
{
    for (id o in [self allObjects])
        if (![predicate evaluateWithObject:o])
            [self removeObject:o];
}
@end
