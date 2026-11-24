/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: NSExpressionDescription, and the dictionary results
 * of a fetch that has expressions, propertiesToGroupBy or a
 * havingPredicate, as Apple's NSExpressionDescription and NSFetchRequest
 * class references describe them (freemac 1.NEXT, Ferry 0.NEXT). Our own
 * code; no Apple code was used.
 *
 * It is all done in memory, on the objects the fetch's predicate picks.
 * An aggregate function (sum:, count:, min:, max:, average:, median:,
 * mode:, stddev:) whose argument is read from each object is worked out
 * over the objects of a group, leaving nil out; count: of no values is 0
 * and the others are nil then. With no propertiesToGroupBy, all the
 * objects are one group, and the fetch gives one dictionary. Without
 * aggregates or grouping, each object gives a dictionary, and an
 * expression is evaluated with the object as SELF. A having predicate is
 * evaluated on each group's dictionary, with its values also as variables;
 * then the dictionaries are sorted, and the offset and limit are taken. */
#import "CDInternal.h"

@implementation NSExpressionDescription {
    NSExpression *_expression;
    NSAttributeType _resultType;
}
- (void)dealloc
{
    [_expression release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSExpressionDescription *c = [super copyWithZone:zone];
    c->_expression = [_expression retain];
    c->_resultType = _resultType;
    return c;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _expression = [[coder decodeObjectForKey:@"expression"] retain];
        _resultType = (NSAttributeType)[coder decodeIntegerForKey:@"expressionResultType"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_expression forKey:@"expression"];
    [coder encodeInteger:_resultType forKey:@"expressionResultType"];
}
- (NSExpression *)expression { return _expression; }
- (void)setExpression:(NSExpression *)expression
{
    [_expression autorelease];
    _expression = [expression retain];
}
- (NSAttributeType)expressionResultType { return _resultType; }
- (void)setExpressionResultType:(NSAttributeType)type { _resultType = type; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"(<NSExpressionDescription: %p>), name %@, expression %@, expressionResultType %lu",
                                      self, [self name], _expression, (unsigned long)_resultType];
}
@end

/* ---- results ---------------------------------------------------------------------------------- */

static BOOL is_aggregate_name(NSString *f)
{
    return [@[ @"sum:", @"count:", @"min:", @"max:", @"average:", @"median:", @"mode:", @"stddev:" ] containsObject:f];
}

/* Whether the argument is read from each object (and not a constant collection). */
static BOOL reads_object(NSExpression *e)
{
    switch ([e expressionType]) {
    case NSKeyPathExpressionType:
    case NSEvaluatedObjectExpressionType: return YES;
    case NSFunctionExpressionType:
        for (NSExpression *a in [e arguments])
            if (reads_object(a))
                return YES;
        return NO;
    default: return NO;
    }
}

static BOOL is_aggregate(NSExpression *e)
{
    return [e expressionType] == NSFunctionExpressionType && is_aggregate_name([e function]) &&
           [[e arguments] count] == 1 && reads_object([[e arguments] objectAtIndex:0]);
}

static BOOL has_aggregate(NSExpression *e)
{
    if ([e expressionType] != NSFunctionExpressionType)
        return NO;
    if (is_aggregate(e))
        return YES;
    for (NSExpression *a in [e arguments])
        if (has_aggregate(a))
            return YES;
    return NO;
}

static id plain_value(id v)
{
    if ([v isKindOfClass:[NSManagedObject class]])
        return [v objectID];
    return v == [NSNull null] ? nil : v;
}

/* The expression with each aggregate in it worked out over the group, as a constant. */
static NSExpression *collapse(NSExpression *e, NSArray *group, NSMutableDictionary *context)
{
    if ([e expressionType] != NSFunctionExpressionType)
        return e;
    if (is_aggregate(e)) {
        NSExpression *arg = [[e arguments] objectAtIndex:0];
        NSMutableArray *values = [NSMutableArray array];
        for (id o in group) {
            id v = plain_value([arg expressionValueWithObject:o context:context]);
            if (v)
                [values addObject:v];
        }
        id result;
        if (![values count])
            result = [[e function] isEqualToString:@"count:"] ? @0 : nil;
        else
            result = [[NSExpression expressionForFunction:[e function]
                                                arguments:@[ [NSExpression expressionForConstantValue:values] ]]
                expressionValueWithObject:nil
                                  context:context];
        return [NSExpression expressionForConstantValue:result];
    }
    if (!has_aggregate(e))
        return e;
    NSMutableArray *args = [NSMutableArray array];
    for (NSExpression *a in [e arguments])
        [args addObject:collapse(a, group, context)];
    return [NSExpression expressionForFunction:[e function] arguments:args];
}

/* A value as the expression description's result type asks. */
static id result_value(id v, NSAttributeType type)
{
    if (!v || v == [NSNull null])
        return nil;
    BOOL number = [v isKindOfClass:[NSNumber class]];
    switch (type) {
    case NSInteger16AttributeType: return number ? [NSNumber numberWithShort:[v shortValue]] : v;
    case NSInteger32AttributeType: return number ? [NSNumber numberWithInt:[v intValue]] : v;
    case NSInteger64AttributeType: return number ? [NSNumber numberWithLongLong:[v longLongValue]] : v;
    case NSDoubleAttributeType: return number ? [NSNumber numberWithDouble:[v doubleValue]] : v;
    case NSFloatAttributeType: return number ? [NSNumber numberWithFloat:[v floatValue]] : v;
    case NSBooleanAttributeType: return number ? [NSNumber numberWithBool:[v boolValue]] : v;
    case NSDecimalAttributeType: return number ? [NSDecimalNumber decimalNumberWithDecimal:[v decimalValue]] : v;
    case NSDateAttributeType: return number ? [NSDate dateWithTimeIntervalSinceReferenceDate:[v doubleValue]] : v;
    case NSStringAttributeType: return [v isKindOfClass:[NSString class]] ? v : [v description];
    default: return v;
    }
}

/* What propertiesToFetch or propertiesToGroupBy names: an expression description,
 * a property description, or a name or key path (as a string). */
static NSArray *resolve(NSArray *items, NSEntityDescription *entity)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id p in items) {
        if ([p isKindOfClass:[NSString class]]) {
            NSPropertyDescription *d = [entity cd_propertyNamed:p];
            [out addObject:d ?: p];
        } else if ([p isKindOfClass:[NSPropertyDescription class]])
            [out addObject:p];
        else
            CDRaise(NSInvalidArgumentException, @"%@ isn't a property, a property name or an expression description", p);
    }
    return out;
}

static NSString *key_of(id item) { return [item isKindOfClass:[NSString class]] ? item : [item name]; }

static id value_of(id item, id object, NSMutableDictionary *context)
{
    if (!object)
        return nil;
    if ([item isKindOfClass:[NSExpressionDescription class]])
        return plain_value([[item expression] expressionValueWithObject:object context:context]);
    if ([item isKindOfClass:[NSString class]])
        return plain_value([object valueForKeyPath:item]);
    id v = [object valueForKey:[item name]];
    if ([v isKindOfClass:[NSSet class]] || [v isKindOfClass:[NSOrderedSet class]])
        return nil;
    return plain_value(v);
}

BOOL CDFetchesExpressions(NSFetchRequest *request)
{
    if ([[request propertiesToGroupBy] count] || [request havingPredicate])
        return YES;
    for (id p in [request propertiesToFetch])
        if ([p isKindOfClass:[NSExpressionDescription class]])
            return YES;
    return NO;
}

BOOL CDGroupsResults(NSFetchRequest *request)
{
    if ([[request propertiesToGroupBy] count])
        return YES;
    for (id p in [request propertiesToFetch])
        if ([p isKindOfClass:[NSExpressionDescription class]] && has_aggregate([p expression]))
            return YES;
    return NO;
}

NSArray *CDExpressionResults(NSArray *objects, NSFetchRequest *request, NSEntityDescription *entity)
{
    NSArray *props = resolve([request propertiesToFetch] ?: [entity cd_persistentAttributes], entity);
    NSArray *groupBy = resolve([request propertiesToGroupBy], entity);
    NSMutableDictionary *context = [NSMutableDictionary dictionary];
    BOOL grouping = CDGroupsResults(request);
    NSMutableArray *rows = [NSMutableArray array];
    if (!grouping) {   /* one dictionary for each object */
        for (id o in objects) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (id p in props) {
                id v = value_of(p, o, context);
                if ([p isKindOfClass:[NSExpressionDescription class]])
                    v = result_value(v, [p expressionResultType]);
                if (v)
                    [d setObject:v forKey:key_of(p)];
            }
            [rows addObject:d];
        }
    } else {
        NSMutableArray *groupKeys = [NSMutableArray array];
        for (id g in groupBy)
            [groupKeys addObject:key_of(g)];
        for (id p in props)
            if (![p isKindOfClass:[NSExpressionDescription class]] && ![groupKeys containsObject:key_of(p)])
                CDRaise(NSInvalidArgumentException,
                        @"%@ is fetched with aggregates or grouping, so it must be in propertiesToGroupBy", key_of(p));
        NSMutableArray *order = [NSMutableArray array];
        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        if (![groupBy count]) {
            [order addObject:@[]];
            [groups setObject:[NSMutableArray arrayWithArray:objects] forKey:@[]];
        } else
            for (id o in objects) {
                NSMutableArray *key = [NSMutableArray array];
                for (id g in groupBy)
                    [key addObject:value_of(g, o, context) ?: [NSNull null]];
                NSMutableArray *members = [groups objectForKey:key];
                if (!members) {
                    [groups setObject:(members = [NSMutableArray array]) forKey:key];
                    [order addObject:key];
                }
                [members addObject:o];
            }
        for (NSArray *key in order) {
            NSArray *members = [groups objectForKey:key];
            id first = [members count] ? [members objectAtIndex:0] : nil;
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (id p in props) {
                id v;
                if ([p isKindOfClass:[NSExpressionDescription class]]) {
                    NSExpression *e = collapse([p expression], members, context);
                    v = result_value(plain_value([e expressionValueWithObject:first context:context]),
                                     [p expressionResultType]);
                } else
                    v = value_of(p, first, context);
                if (v)
                    [d setObject:v forKey:key_of(p)];
            }
            NSPredicate *having = [request havingPredicate];
            if (having) {
                NSMutableDictionary *vars = [NSMutableDictionary dictionaryWithDictionary:d];
                for (id p in props)
                    if (![vars objectForKey:key_of(p)])
                        [vars setObject:[NSNull null] forKey:key_of(p)];
                if (![having evaluateWithObject:d substitutionVariables:vars])
                    continue;
            }
            [rows addObject:d];
        }
    }
    if ([request returnsDistinctResults]) {
        NSMutableArray *kept = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *d in rows)
            if (![seen containsObject:d]) {
                [seen addObject:d];
                [kept addObject:d];
            }
        rows = kept;
    }
    if (!grouping)
        return rows;   /* the objects were sorted and limited already */
    NSArray *sorted = [request sortDescriptors] ? [rows sortedArrayUsingDescriptors:[request sortDescriptors]] : rows;
    NSUInteger offset = [request fetchOffset], limit = [request fetchLimit];
    if (offset >= [sorted count])
        return @[];
    NSUInteger n = [sorted count] - offset;
    if (limit && limit < n)
        n = limit;
    return [sorted subarrayWithRange:NSMakeRange(offset, n)];
}
