/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSExpression, as Apple's class reference and the
 * "Predicate Format String Syntax" of the Predicate Programming Guide
 * describe it (freemac 1.NEXT, Ferry 0.NEXT). Our own code; no Apple code
 * was used.
 *
 * Every documented kind is here: constants, the evaluated object (SELF),
 * variables, key paths (also read from another expression's value, as in
 * $x.name), function expressions (the built-in functions by name, and a
 * method sent to a target with FUNCTION), aggregates, the set expressions,
 * subqueries, ANYKEY, blocks and conditionals (TERNARY).
 *
 * The built-in functions take numbers as doubles, except that the four
 * arithmetic functions work in exact decimals when an argument is an
 * NSDecimalNumber, and the bitwise ones and modulus:by: in integers when
 * their arguments are integers. An arithmetic function with a nil argument
 * gives nil. sum:, count:, min:, max:, average:, median:, mode: and
 * stddev: take a collection and leave out its NSNull members; stddev: is
 * the population's standard deviation, and mode: gives an array of the
 * values seen most often. */
#import "FExpression.h"

@implementation NSExpression {
    NSExpressionType _type;
    id _value;               /* the constant, key path, variable or function name, or the block */
    NSExpression *_operand;  /* a key path's operand (nil for SELF), FUNCTION's target, a subquery's collection,
                                a set expression's left side, a conditional's true expression */
    NSExpression *_other;    /* a set expression's right side, a conditional's false expression */
    NSArray *_args;          /* a function's or block's arguments, an aggregate's members */
    NSPredicate *_predicate; /* a subquery's or conditional's predicate */
    NSString *_iterator;     /* a subquery's variable */
}

static NSExpression *make(NSExpressionType type)
{
    NSExpression *e = [[[NSExpression alloc] init] autorelease];
    e->_type = type;
    return e;
}

/* ---- the built-in functions --------------------------------------------------------------- */

typedef id (*FFunction)(NSArray *args);

static BOOL is_nil(id v) { return !v || v == [NSNull null]; }

static NSNumber *number_arg(id v, NSString *function)
{
    if (![v isKindOfClass:[NSNumber class]])
        FRaise(NSInvalidArgumentException, @"%@ needs numbers, not %@", function, v);
    return v;
}

/* The members of a collection argument, NSNull left out. */
static NSArray *collection_arg(id v, NSString *function)
{
    if ([v isKindOfClass:[NSSet class]])
        v = [v allObjects];
    else if ([v isKindOfClass:[NSOrderedSet class]])
        v = [v array];
    if (![v isKindOfClass:[NSArray class]])
        FRaise(NSInvalidArgumentException, @"%@ needs a collection, not %@", function, v);
    NSMutableArray *out = [NSMutableArray array];
    for (id x in v)
        if (x != [NSNull null])
            [out addObject:x];
    return out;
}

static BOOL any_decimal(NSArray *values)
{
    for (id v in values)
        if ([v isKindOfClass:[NSDecimalNumber class]])
            return YES;
    return NO;
}

static NSDecimalNumber *as_decimal(id v)
{
    if ([v isKindOfClass:[NSDecimalNumber class]])
        return v;
    return [NSDecimalNumber decimalNumberWithDecimal:[v decimalValue]];
}

static BOOL is_integer(NSNumber *n)
{
    const char *t = [n objCType];
    return t && strchr("cCsSiIlLqQB", *t) && ![n isKindOfClass:[NSDecimalNumber class]];
}

static id fn_sum(NSArray *a)
{
    NSArray *v = collection_arg([a objectAtIndex:0], @"sum:");
    if (any_decimal(v)) {
        NSDecimalNumber *s = [NSDecimalNumber zero];
        for (id x in v)
            s = [s decimalNumberByAdding:as_decimal(number_arg(x, @"sum:"))];
        return s;
    }
    double s = 0;
    for (id x in v)
        s += [number_arg(x, @"sum:") doubleValue];
    return @(s);
}
static id fn_count(NSArray *a) { return @([collection_arg([a objectAtIndex:0], @"count:") count]); }
static id extreme(NSArray *a, NSString *name, NSComparisonResult want)
{
    id best = nil;
    for (id x in collection_arg([a objectAtIndex:0], name))
        if (!best || [x compare:best] == want)
            best = x;
    return best;
}
static id fn_min(NSArray *a) { return extreme(a, @"min:", NSOrderedAscending); }
static id fn_max(NSArray *a) { return extreme(a, @"max:", NSOrderedDescending); }
static id fn_average(NSArray *a)
{
    NSArray *v = collection_arg([a objectAtIndex:0], @"average:");
    if (![v count])
        return nil;
    if (any_decimal(v))
        return [fn_sum(a) decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithMantissa:[v count]
                                                                                       exponent:0
                                                                                     isNegative:NO]];
    return @([fn_sum(a) doubleValue] / [v count]);
}
static NSArray *sorted_numbers(NSArray *a, NSString *name)
{
    NSArray *v = collection_arg([a objectAtIndex:0], name);
    for (id x in v)
        number_arg(x, name);
    return [v sortedArrayUsingSelector:@selector(compare:)];
}
static id fn_median(NSArray *a)
{
    NSArray *v = sorted_numbers(a, @"median:");
    NSUInteger n = [v count];
    if (!n)
        return nil;
    if (n % 2)
        return [v objectAtIndex:n / 2];
    return @(([[v objectAtIndex:n / 2 - 1] doubleValue] + [[v objectAtIndex:n / 2] doubleValue]) / 2);
}
static id fn_mode(NSArray *a)
{
    NSArray *v = collection_arg([a objectAtIndex:0], @"mode:");
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSUInteger most = 0;
    for (id x in v) {
        NSUInteger c = [[counts objectForKey:x] unsignedIntegerValue] + 1;
        if (c == 1)
            [order addObject:x];
        [counts setObject:@(c) forKey:x];
        if (c > most)
            most = c;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (id x in order)
        if ([[counts objectForKey:x] unsignedIntegerValue] == most)
            [out addObject:x];
    return out;
}
static id fn_stddev(NSArray *a)
{
    NSArray *v = sorted_numbers(a, @"stddev:");
    NSUInteger n = [v count];
    if (!n)
        return nil;
    double mean = 0, sq = 0;
    for (NSNumber *x in v)
        mean += [x doubleValue];
    mean /= n;
    for (NSNumber *x in v)
        sq += ([x doubleValue] - mean) * ([x doubleValue] - mean);
    return @(sqrt(sq / n));
}

/* The arithmetic: nil when an argument is nil, exact decimals when one is an NSDecimalNumber. */
typedef enum { AR_ADD, AR_SUB, AR_MUL, AR_DIV } FArith;
static id arith(NSArray *a, FArith op, NSString *name)
{
    id l = [a objectAtIndex:0], r = [a objectAtIndex:1];
    if (is_nil(l) || is_nil(r))
        return nil;
    if ([l isKindOfClass:[NSDate class]] && op == AR_ADD)
        return [l dateByAddingTimeInterval:[number_arg(r, name) doubleValue]];
    if ([r isKindOfClass:[NSDate class]] && op == AR_ADD)
        return [r dateByAddingTimeInterval:[number_arg(l, name) doubleValue]];
    number_arg(l, name), number_arg(r, name);
    if (any_decimal(a)) {
        NSDecimalNumber *x = as_decimal(l), *y = as_decimal(r);
        switch (op) {
        case AR_ADD: return [x decimalNumberByAdding:y];
        case AR_SUB: return [x decimalNumberBySubtracting:y];
        case AR_MUL: return [x decimalNumberByMultiplyingBy:y];
        case AR_DIV: return [x decimalNumberByDividingBy:y];
        }
    }
    double x = [l doubleValue], y = [r doubleValue];
    switch (op) {
    case AR_ADD: return @(x + y);
    case AR_SUB: return @(x - y);
    case AR_MUL: return @(x * y);
    case AR_DIV: return @(x / y);
    }
    return nil;
}
static id fn_add(NSArray *a) { return arith(a, AR_ADD, @"add:to:"); }
static id fn_subtract(NSArray *a) { return arith(a, AR_SUB, @"from:subtract:"); }
static id fn_multiply(NSArray *a) { return arith(a, AR_MUL, @"multiply:by:"); }
static id fn_divide(NSArray *a) { return arith(a, AR_DIV, @"divide:by:"); }
static id fn_modulus(NSArray *a)
{
    id l = [a objectAtIndex:0], r = [a objectAtIndex:1];
    if (is_nil(l) || is_nil(r))
        return nil;
    number_arg(l, @"modulus:by:"), number_arg(r, @"modulus:by:");
    if (is_integer(l) && is_integer(r) && [r longLongValue])
        return @([l longLongValue] % [r longLongValue]);
    return @(fmod([l doubleValue], [r doubleValue]));
}

typedef double (*FUnary)(double);
static id unary(NSArray *a, FUnary f, NSString *name)
{
    id v = [a objectAtIndex:0];
    if (is_nil(v))
        return nil;
    return @(f([number_arg(v, name) doubleValue]));
}
static double log10_(double x) { return log10(x); }
static id fn_sqrt(NSArray *a) { return unary(a, sqrt, @"sqrt:"); }
static id fn_log(NSArray *a) { return unary(a, log10_, @"log:"); }
static id fn_ln(NSArray *a) { return unary(a, log, @"ln:"); }
static id fn_exp(NSArray *a) { return unary(a, exp, @"exp:"); }
static id fn_ceiling(NSArray *a) { return unary(a, ceil, @"ceiling:"); }
static id fn_floor(NSArray *a) { return unary(a, floor, @"floor:"); }
static id fn_trunc(NSArray *a) { return unary(a, trunc, @"trunc:"); }
static id fn_abs(NSArray *a)
{
    id v = [a objectAtIndex:0];
    if (!is_nil(v) && is_integer(number_arg(v, @"abs:")))
        return @(llabs([v longLongValue]));
    if ([v isKindOfClass:[NSDecimalNumber class]])
        return [v compare:[NSDecimalNumber zero]] == NSOrderedAscending
                   ? [[NSDecimalNumber zero] decimalNumberBySubtracting:v]
                   : v;
    return unary(a, fabs, @"abs:");
}
static id fn_power(NSArray *a)
{
    id l = [a objectAtIndex:0], r = [a objectAtIndex:1];
    if (is_nil(l) || is_nil(r))
        return nil;
    return @(pow([number_arg(l, @"raise:toPower:") doubleValue], [number_arg(r, @"raise:toPower:") doubleValue]));
}
static id fn_random(NSArray *a) { return @((double)arc4random() / 4294967296.0); }
static id fn_random_of(NSArray *a)
{
    NSArray *v = collection_arg([a objectAtIndex:0], @"random:");
    return [v count] ? [v objectAtIndex:arc4random_uniform((uint32_t)[v count])] : nil;
}
static id fn_now(NSArray *a) { return [NSDate date]; }
static id fn_uppercase(NSArray *a)
{
    id v = [a objectAtIndex:0];
    return [v isKindOfClass:[NSString class]] ? [v uppercaseString] : nil;
}
static id fn_lowercase(NSArray *a)
{
    id v = [a objectAtIndex:0];
    return [v isKindOfClass:[NSString class]] ? [v lowercaseString] : nil;
}
static id fn_length(NSArray *a)
{
    id v = [a objectAtIndex:0];
    return [v isKindOfClass:[NSString class]] ? @([v length]) : nil;
}
typedef enum { BIT_AND, BIT_OR, BIT_XOR, BIT_LEFT, BIT_RIGHT } FBit;
static id bits(NSArray *a, FBit op, NSString *name)
{
    id l = [a objectAtIndex:0], r = [a objectAtIndex:1];
    if (is_nil(l) || is_nil(r))
        return nil;
    long long x = [number_arg(l, name) longLongValue], y = [number_arg(r, name) longLongValue];
    switch (op) {
    case BIT_AND: return @(x & y);
    case BIT_OR: return @(x | y);
    case BIT_XOR: return @(x ^ y);
    case BIT_LEFT: return @((long long)((unsigned long long)x << (y & 63)));
    case BIT_RIGHT: return @(x >> (y & 63));
    }
    return nil;
}
static id fn_and(NSArray *a) { return bits(a, BIT_AND, @"bitwiseAnd:with:"); }
static id fn_or(NSArray *a) { return bits(a, BIT_OR, @"bitwiseOr:with:"); }
static id fn_xor(NSArray *a) { return bits(a, BIT_XOR, @"bitwiseXor:with:"); }
static id fn_left(NSArray *a) { return bits(a, BIT_LEFT, @"leftshift:by:"); }
static id fn_right(NSArray *a) { return bits(a, BIT_RIGHT, @"rightshift:by:"); }
static id fn_complement(NSArray *a)
{
    id v = [a objectAtIndex:0];
    return is_nil(v) ? nil : @(~[number_arg(v, @"onesComplement:") longLongValue]);
}
static id fn_noindex(NSArray *a) { return [a objectAtIndex:0] == [NSNull null] ? nil : [a objectAtIndex:0]; }
/* CAST(value, 'NSDate'), 'NSNumber' or 'NSString'. */
static id fn_cast(NSArray *a)
{
    id v = [a objectAtIndex:0], type = [a objectAtIndex:1];
    if (is_nil(v))
        return nil;
    if ([type isEqual:@"NSDate"]) {
        if ([v isKindOfClass:[NSDate class]])
            return v;
        return [NSDate dateWithTimeIntervalSinceReferenceDate:[v doubleValue]];
    }
    if ([type isEqual:@"NSNumber"]) {
        if ([v isKindOfClass:[NSDate class]])
            return @([v timeIntervalSinceReferenceDate]);
        if ([v isKindOfClass:[NSString class]])
            return @([v doubleValue]);
        return number_arg(v, @"castObject:toType:");
    }
    if ([type isEqual:@"NSString"])
        return [v isKindOfClass:[NSString class]] ? v : [v description];
    if ([type isEqual:@"NSDecimalNumber"])
        return [v isKindOfClass:[NSString class]] ? [NSDecimalNumber decimalNumberWithString:v] : as_decimal(v);
    Class c = [type isKindOfClass:[NSString class]] ? NSClassFromString(type) : Nil;
    if (c && [v isKindOfClass:c])
        return v;
    FRaise(NSInvalidArgumentException, @"Can't cast %@ to the type %@", v, type);
    return nil;
}
/* collection[index], collection[FIRST], [LAST] and [SIZE], and dictionary[key]. */
static id fn_index(NSArray *a)
{
    id c = [a objectAtIndex:0], i = [a objectAtIndex:1];
    if (is_nil(c))
        return nil;
    if ([c isKindOfClass:[NSDictionary class]])
        return [c objectForKey:i];
    if ([c isKindOfClass:[NSOrderedSet class]])
        c = [c array];
    if ([c isKindOfClass:[NSSet class]])
        c = [c allObjects];
    if (![c isKindOfClass:[NSArray class]])
        FRaise(NSInvalidArgumentException, @"Can't index %@", c);
    if ([i isEqual:@"SIZE"])
        return @([c count]);
    if ([i isEqual:@"FIRST"])
        return [c firstObject];
    if ([i isEqual:@"LAST"])
        return [c lastObject];
    NSInteger n = [number_arg(i, @"objectFrom:withIndex:") integerValue];
    if (n < 0 || (NSUInteger)n >= [c count])
        FRaise(NSRangeException, @"Index %ld beyond bounds [0 .. %ld]", (long)n, (long)[c count] - 1);
    return [c objectAtIndex:n];
}
static id fn_distance(NSArray *a)
{
    FRaise(NSInvalidArgumentException, @"distanceToLocation:fromLocation: needs Core Location, which Ferry hasn't");
    return nil;
}

static const struct builtin {
    const char *name;
    int arity;
    FFunction f;
} builtins[] = {
    {"sum:", 1, fn_sum},
    {"count:", 1, fn_count},
    {"min:", 1, fn_min},
    {"max:", 1, fn_max},
    {"average:", 1, fn_average},
    {"median:", 1, fn_median},
    {"mode:", 1, fn_mode},
    {"stddev:", 1, fn_stddev},
    {"add:to:", 2, fn_add},
    {"from:subtract:", 2, fn_subtract},
    {"multiply:by:", 2, fn_multiply},
    {"divide:by:", 2, fn_divide},
    {"modulus:by:", 2, fn_modulus},
    {"sqrt:", 1, fn_sqrt},
    {"log:", 1, fn_log},
    {"ln:", 1, fn_ln},
    {"raise:toPower:", 2, fn_power},
    {"exp:", 1, fn_exp},
    {"ceiling:", 1, fn_ceiling},
    {"abs:", 1, fn_abs},
    {"trunc:", 1, fn_trunc},
    {"floor:", 1, fn_floor},
    {"random", 0, fn_random},
    {"random:", 1, fn_random_of},
    {"now", 0, fn_now},
    {"uppercase:", 1, fn_uppercase},
    {"lowercase:", 1, fn_lowercase},
    {"length:", 1, fn_length},
    {"bitwiseAnd:with:", 2, fn_and},
    {"bitwiseOr:with:", 2, fn_or},
    {"bitwiseXor:with:", 2, fn_xor},
    {"leftshift:by:", 2, fn_left},
    {"rightshift:by:", 2, fn_right},
    {"onesComplement:", 1, fn_complement},
    {"noindex:", 1, fn_noindex},
    {"castObject:toType:", 2, fn_cast},
    {"objectFrom:withIndex:", 2, fn_index},
    {"distanceToLocation:fromLocation:", 2, fn_distance},
};

static const struct builtin *builtin_named(NSString *name)
{
    const char *n = [name UTF8String];
    for (size_t i = 0; i < sizeof builtins / sizeof *builtins; i++)
        if (n && !strcmp(builtins[i].name, n))
            return &builtins[i];
    return NULL;
}

/* ---- making expressions --------------------------------------------------------------------- */

+ (NSExpression *)expressionWithFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    NSExpression *e = FParseExpression(format, &ap, nil);
    va_end(ap);
    return e;
}
+ (NSExpression *)expressionWithFormat:(NSString *)format arguments:(va_list)args
{
    va_list ap;
    va_copy(ap, args);
    NSExpression *e = FParseExpression(format, &ap, nil);
    va_end(ap);
    return e;
}
+ (NSExpression *)expressionWithFormat:(NSString *)format argumentArray:(NSArray *)arguments
{
    return FParseExpression(format, NULL, arguments ?: @[]);
}
+ (NSExpression *)expressionForConstantValue:(id)obj
{
    NSExpression *e = make(NSConstantValueExpressionType);
    e->_value = [obj retain];
    return e;
}
+ (NSExpression *)expressionForEvaluatedObject { return make(NSEvaluatedObjectExpressionType); }
+ (NSExpression *)expressionForVariable:(NSString *)string
{
    if (![string isKindOfClass:[NSString class]])
        FRaise(NSInvalidArgumentException, @"*** +[NSExpression expressionForVariable:]: the name isn't a string");
    NSExpression *e = make(NSVariableExpressionType);
    e->_value = [string copy];
    return e;
}
+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath { return [self _expressionForKeyPath:keyPath operand:nil]; }
+ (NSExpression *)_expressionForKeyPath:(NSString *)keyPath operand:(NSExpression *)operand
{
    if (![keyPath isKindOfClass:[NSString class]])
        FRaise(NSInvalidArgumentException, @"*** +[NSExpression expressionForKeyPath:]: the key path isn't a string");
    NSExpression *e = make(NSKeyPathExpressionType);
    e->_value = [keyPath copy];
    if (operand && [operand expressionType] != NSEvaluatedObjectExpressionType)
        e->_operand = [operand retain];
    return e;
}
+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters
{
    const struct builtin *b = builtin_named(name);
    if (!b)
        FRaise(NSInvalidArgumentException, @"Unsupported function name %@ for an expression", name);
    if (b->arity != (int)[parameters count])
        FRaise(NSInvalidArgumentException, @"The function %@ takes %d argument(s), not %lu", name, b->arity,
               (unsigned long)[parameters count]);
    NSExpression *e = make(NSFunctionExpressionType);
    e->_value = [name copy];
    e->_args = [parameters copy] ?: [[NSArray alloc] init];
    return e;
}
+ (NSExpression *)expressionForFunction:(NSExpression *)target selectorName:(NSString *)name arguments:(NSArray *)parameters
{
    if (!target || ![name isKindOfClass:[NSString class]])
        FRaise(NSInvalidArgumentException, @"FUNCTION needs a target and a selector name");
    NSExpression *e = make(NSFunctionExpressionType);
    e->_value = [name copy];
    e->_operand = [target retain];
    e->_args = [parameters copy] ?: [[NSArray alloc] init];
    return e;
}
+ (NSExpression *)expressionForAggregate:(NSArray *)subexpressions
{
    NSExpression *e = make(NSAggregateExpressionType);
    e->_args = [subexpressions copy] ?: [[NSArray alloc] init];
    return e;
}
static NSExpression *set_expression(NSExpressionType type, NSExpression *left, NSExpression *right)
{
    if (!left || !right)
        FRaise(NSInvalidArgumentException, @"A set expression needs two expressions");
    NSExpression *e = make(type);
    e->_operand = [left retain];
    e->_other = [right retain];
    return e;
}
+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right
{
    return set_expression(NSUnionSetExpressionType, left, right);
}
+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right
{
    return set_expression(NSIntersectSetExpressionType, left, right);
}
+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right
{
    return set_expression(NSMinusSetExpressionType, left, right);
}
+ (NSExpression *)expressionForSubquery:(NSExpression *)expression
                  usingIteratorVariable:(NSString *)variable
                              predicate:(NSPredicate *)predicate
{
    if (!expression || ![variable isKindOfClass:[NSString class]] || !predicate)
        FRaise(NSInvalidArgumentException, @"SUBQUERY needs a collection, a variable and a predicate");
    NSExpression *e = make(NSSubqueryExpressionType);
    e->_operand = [expression retain];
    e->_iterator = [variable copy];
    e->_predicate = [predicate retain];
    return e;
}
+ (NSExpression *)expressionForAnyKey { return make(NSAnyKeyExpressionType); }
+ (NSExpression *)expressionForBlock:(id (^)(id, NSArray<NSExpression *> *, NSMutableDictionary *))block arguments:(NSArray *)arguments
{
    if (!block)
        FRaise(NSInvalidArgumentException, @"*** +[NSExpression expressionForBlock:arguments:]: the block is nil");
    NSExpression *e = make(NSBlockExpressionType);
    e->_value = [block copy];
    e->_args = [arguments copy];
    return e;
}
+ (NSExpression *)expressionForConditional:(NSPredicate *)predicate
                            trueExpression:(NSExpression *)trueExpression
                           falseExpression:(NSExpression *)falseExpression
{
    if (!predicate || !trueExpression || !falseExpression)
        FRaise(NSInvalidArgumentException, @"TERNARY needs a predicate and two expressions");
    NSExpression *e = make(NSConditionalExpressionType);
    e->_predicate = [predicate retain];
    e->_operand = [trueExpression retain];
    e->_other = [falseExpression retain];
    return e;
}
- (instancetype)initWithExpressionType:(NSExpressionType)type
{
    if ((self = [super init]))
        _type = type;
    return self;
}
- (void)dealloc
{
    [_value release];
    [_operand release];
    [_other release];
    [_args release];
    [_predicate release];
    [_iterator release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
/* Archived as its format string (a block expression can't be archived). */
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_type == NSBlockExpressionType)
        FRaise(NSInvalidArgumentException, @"*** -[NSExpression encodeWithCoder:]: block expressions can't be archived");
    [coder encodeObject:[self _format] forKey:@"NS.expressionFormat"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *format = [coder decodeObjectForKey:@"NS.expressionFormat"];
    [self release];
    if (![format isKindOfClass:[NSString class]])
        return nil;
    return [FParseExpression(format, NULL, @[]) retain];
}
- (void)allowEvaluation {}

/* ---- what an expression is ------------------------------------------------------------------- */

- (NSExpressionType)expressionType { return _type; }
- (id)constantValue { return _type == NSConstantValueExpressionType ? _value : nil; }
- (NSString *)keyPath { return _type == NSKeyPathExpressionType ? _value : nil; }
- (NSString *)function { return _type == NSFunctionExpressionType ? _value : nil; }
- (NSString *)variable
{
    if (_type == NSVariableExpressionType)
        return _value;
    return _type == NSSubqueryExpressionType ? _iterator : nil;
}
- (NSExpression *)operand
{
    if (_type == NSKeyPathExpressionType)
        return _operand ?: [NSExpression expressionForEvaluatedObject];
    return _type == NSFunctionExpressionType ? _operand : nil;
}
- (NSArray *)arguments
{
    return _type == NSFunctionExpressionType || _type == NSBlockExpressionType ? _args : nil;
}
- (id)collection
{
    if (_type == NSAggregateExpressionType)
        return _args;
    return _type == NSSubqueryExpressionType ? _operand : nil;
}
- (NSPredicate *)predicate
{
    return _type == NSSubqueryExpressionType || _type == NSConditionalExpressionType ? _predicate : nil;
}
static BOOL is_set_type(NSExpressionType t)
{
    return t == NSUnionSetExpressionType || t == NSIntersectSetExpressionType || t == NSMinusSetExpressionType;
}
- (NSExpression *)leftExpression { return is_set_type(_type) ? _operand : nil; }
- (NSExpression *)rightExpression { return is_set_type(_type) ? _other : nil; }
- (NSExpression *)trueExpression { return _type == NSConditionalExpressionType ? _operand : nil; }
- (NSExpression *)falseExpression { return _type == NSConditionalExpressionType ? _other : nil; }
- (id (^)(id, NSArray<NSExpression *> *, NSMutableDictionary *))expressionBlock
{
    return _type == NSBlockExpressionType ? _value : nil;
}

/* ---- evaluating ------------------------------------------------------------------------------- */

static NSSet *as_set(id v)
{
    if ([v isKindOfClass:[NSSet class]])
        return v;
    if ([v isKindOfClass:[NSOrderedSet class]])
        return [v set];
    if ([v isKindOfClass:[NSArray class]])
        return [NSSet setWithArray:v];
    if (is_nil(v))
        return [NSSet set];
    FRaise(NSInvalidArgumentException, @"A set expression needs collections, not %@", v);
    return nil;
}

/* Sends a FUNCTION's selector, answering an object (scalars boxed as numbers). */
static id send(id target, NSString *name, NSArray *values)
{
    SEL sel = NSSelectorFromString(name);
    if (is_nil(target))
        return nil;
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig)
        FRaise(NSInvalidArgumentException, @"FUNCTION: %@ doesn't respond to %@", target, name);
    if ([sig numberOfArguments] - 2 != [values count])
        FRaise(NSInvalidArgumentException, @"FUNCTION: %@ takes %lu argument(s), not %lu", name,
               (unsigned long)([sig numberOfArguments] - 2), (unsigned long)[values count]);
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:sel];
    for (NSUInteger i = 0; i < [values count]; i++) {
        id v = [values objectAtIndex:i];
        if (v == [NSNull null])
            v = nil;
        const char *t = [sig getArgumentTypeAtIndex:i + 2];
        if (*t == '@')
            [inv setArgument:&v atIndex:i + 2];
        else if (strchr("cCsSiIlLqQB", *t)) {
            long long n = [v longLongValue];
            [inv setArgument:&n atIndex:i + 2];   /* the low bytes, on this little-endian machine */
        } else if (*t == 'd') {
            double d = [v doubleValue];
            [inv setArgument:&d atIndex:i + 2];
        } else if (*t == 'f') {
            float f = [v floatValue];
            [inv setArgument:&f atIndex:i + 2];
        } else
            FRaise(NSInvalidArgumentException, @"FUNCTION: can't pass an argument of type %s to %@", t, name);
    }
    [inv invokeWithTarget:target];
    const char *r = [sig methodReturnType];
    switch (*r) {
    case '@': {
        id out = nil;
        [inv getReturnValue:&out];
        return out;
    }
    case 'v': return nil;
    case 'B':
    case 'c': {
        char c = 0;
        [inv getReturnValue:&c];
        return @((BOOL)c);
    }
    case 'C': { unsigned char v = 0; [inv getReturnValue:&v]; return @(v); }
    case 's': { short v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'S': { unsigned short v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'i': { int v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'I': { unsigned v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'l':
    case 'q': { long long v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'L':
    case 'Q': { unsigned long long v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'f': { float v = 0; [inv getReturnValue:&v]; return @(v); }
    case 'd': { double v = 0; [inv getReturnValue:&v]; return @(v); }
    }
    FRaise(NSInvalidArgumentException, @"FUNCTION: %@ returns a type (%s) an expression can't hold", name, r);
    return nil;
}

- (id)expressionValueWithObject:(id)object context:(NSMutableDictionary *)context
{
    switch (_type) {
    case NSConstantValueExpressionType: return _value == [NSNull null] ? nil : _value;
    case NSEvaluatedObjectExpressionType: return object;
    case NSVariableExpressionType: {
        id v = [context objectForKey:_value];
        if (!v && !context)
            FRaise(NSInvalidArgumentException, @"Can't get value for '%@' in bindings %@.", _value, context);
        return v == [NSNull null] ? nil : v;
    }
    case NSKeyPathExpressionType: {
        id base = _operand ? [_operand expressionValueWithObject:object context:context] : object;
        return base ? [base valueForKeyPath:_value] : nil;
    }
    case NSFunctionExpressionType: {
        NSMutableArray *values = [NSMutableArray array];
        for (NSExpression *a in _args)
            [values addObject:[a expressionValueWithObject:object context:context] ?: [NSNull null]];
        if (_operand)
            return send([_operand expressionValueWithObject:object context:context], _value, values);
        const struct builtin *b = builtin_named(_value);
        return b->f(values);
    }
    case NSAggregateExpressionType: {
        NSMutableArray *out = [NSMutableArray array];
        for (NSExpression *x in _args)
            [out addObject:[x expressionValueWithObject:object context:context] ?: [NSNull null]];
        return out;
    }
    case NSUnionSetExpressionType:
    case NSIntersectSetExpressionType:
    case NSMinusSetExpressionType: {
        NSMutableSet *l = [[as_set([_operand expressionValueWithObject:object context:context]) mutableCopy] autorelease];
        NSSet *r = as_set([_other expressionValueWithObject:object context:context]);
        if (_type == NSUnionSetExpressionType)
            [l unionSet:r];
        else if (_type == NSIntersectSetExpressionType)
            [l intersectSet:r];
        else
            [l minusSet:r];
        return [NSSet setWithSet:l];
    }
    case NSSubqueryExpressionType: {
        id c = [_operand expressionValueWithObject:object context:context];
        if ([c isKindOfClass:[NSSet class]])
            c = [c allObjects];
        else if ([c isKindOfClass:[NSOrderedSet class]])
            c = [c array];
        if (is_nil(c))
            return @[];
        if (![c isKindOfClass:[NSArray class]])
            FRaise(NSInvalidArgumentException, @"SUBQUERY needs a collection, not %@", c);
        NSMutableDictionary *vars = context ? [[context mutableCopy] autorelease] : [NSMutableDictionary dictionary];
        NSMutableArray *out = [NSMutableArray array];
        for (id x in c) {
            [vars setObject:x forKey:_iterator];
            if ([_predicate _evaluate:x vars:vars])
                [out addObject:x];
        }
        return out;
    }
    case NSAnyKeyExpressionType: return nil;
    case NSBlockExpressionType: {
        NSMutableArray *values = [NSMutableArray array];
        for (NSExpression *a in _args)
            [values addObject:[a expressionValueWithObject:object context:context] ?: [NSNull null]];
        id (^block)(id, NSArray *, NSMutableDictionary *) = _value;
        return block(object, values, context);
    }
    case NSConditionalExpressionType:
        return [(([_predicate _evaluate:object vars:context]) ? _operand : _other) expressionValueWithObject:object
                                                                                                   context:context];
    }
    return nil;
}

/* ---- as a format string ----------------------------------------------------------------------- */

static NSString *quote(NSString *s)
{
    NSMutableString *m = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '\\')
            [m appendString:@"\\"];
        [m appendFormat:@"%C", c];
    }
    [m appendString:@"\""];
    return m;
}

NSString *FFormatConstant(id value)
{
    if (is_nil(value))
        return @"nil";
    if ([value isKindOfClass:[NSString class]])
        return quote(value);
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]] ||
        [value isKindOfClass:[NSOrderedSet class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        id items = [value isKindOfClass:[NSSet class]] ? [value allObjects]
                 : [value isKindOfClass:[NSOrderedSet class]] ? [value array]
                                                              : value;
        for (id x in items)
            [parts addObject:FFormatConstant(x)];
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
    }
    if ([value isKindOfClass:[NSDate class]])
        return [NSString stringWithFormat:@"CAST(%@, \"NSDate\")", @([value timeIntervalSinceReferenceDate])];
    return [value description];
}

/* The infix operators, and how tightly they bind. */
static NSString *infix(NSString *function, int *precedence)
{
    static const struct {
        const char *name, *op;
        int precedence;
    } ops[] = {
        {"add:to:", "+", 1}, {"from:subtract:", "-", 1}, {"multiply:by:", "*", 2}, {"divide:by:", "/", 2},
        {"raise:toPower:", "**", 3},
    };
    for (size_t i = 0; i < sizeof ops / sizeof *ops; i++)
        if ([function isEqualToString:@(ops[i].name)]) {
            *precedence = ops[i].precedence;
            return @(ops[i].op);
        }
    return nil;
}

static NSString *operand_format(NSExpression *e, int parent, BOOL right)
{
    int p = 0;
    if ([e expressionType] == NSFunctionExpressionType && ![e operand] && infix([e function], &p) &&
        (p < parent || (p == parent && right)))
        return [NSString stringWithFormat:@"(%@)", [e _format]];
    return [e _format];
}

static NSString *joined_formats(NSArray *exprs)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSExpression *x in exprs)
        [parts addObject:[x _format]];
    return [parts componentsJoinedByString:@", "];
}

- (NSString *)_format
{
    switch (_type) {
    case NSConstantValueExpressionType: return FFormatConstant(_value);
    case NSEvaluatedObjectExpressionType: return @"SELF";
    case NSVariableExpressionType: return [@"$" stringByAppendingString:_value];
    case NSKeyPathExpressionType:
        return _operand ? [NSString stringWithFormat:@"%@.%@", [_operand _format], _value] : _value;
    case NSFunctionExpressionType: {
        if (_operand)
            return [NSString stringWithFormat:@"FUNCTION(%@, %@%@%@)", [_operand _format], quote(_value),
                                              [_args count] ? @", " : @"", joined_formats(_args)];
        int p = 0;
        NSString *op = infix(_value, &p);
        if (op && [_args count] == 2)
            return [NSString stringWithFormat:@"%@ %@ %@", operand_format([_args objectAtIndex:0], p, NO), op,
                                              operand_format([_args objectAtIndex:1], p, YES)];
        if ([_value isEqualToString:@"objectFrom:withIndex:"]) {
            NSExpression *i = [_args objectAtIndex:1];
            id iv = [i expressionType] == NSConstantValueExpressionType ? [i constantValue] : nil;
            NSString *index = [@[ @"FIRST", @"LAST", @"SIZE" ] containsObject:iv ?: @""] ? iv : [i _format];
            return [NSString stringWithFormat:@"%@[%@]", [[_args objectAtIndex:0] _format], index];
        }
        if ([_value isEqualToString:@"castObject:toType:"])
            return [NSString stringWithFormat:@"CAST(%@)", joined_formats(_args)];
        return [NSString stringWithFormat:@"%@(%@)", _value, joined_formats(_args)];
    }
    case NSAggregateExpressionType: return [NSString stringWithFormat:@"{%@}", joined_formats(_args)];
    case NSUnionSetExpressionType: return [NSString stringWithFormat:@"%@ UNION %@", [_operand _format], [_other _format]];
    case NSIntersectSetExpressionType:
        return [NSString stringWithFormat:@"%@ INTERSECT %@", [_operand _format], [_other _format]];
    case NSMinusSetExpressionType: return [NSString stringWithFormat:@"%@ MINUS %@", [_operand _format], [_other _format]];
    case NSSubqueryExpressionType:
        return [NSString stringWithFormat:@"SUBQUERY(%@, $%@, %@)", [_operand _format], _iterator,
                                          [_predicate predicateFormat]];
    case NSAnyKeyExpressionType: return @"ANYKEY";
    case NSBlockExpressionType:
        return [NSString stringWithFormat:@"BLOCK(%p, %@)", _value, joined_formats(_args)];
    case NSConditionalExpressionType:
        return [NSString stringWithFormat:@"TERNARY(%@, %@, %@)", [_predicate predicateFormat], [_operand _format],
                                          [_other _format]];
    }
    return @"";
}
- (NSString *)description { return [self _format]; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSExpression class]] || [other expressionType] != _type || _type == NSBlockExpressionType)
        return NO;
    if (_type == NSConstantValueExpressionType)
        return (is_nil(_value) && is_nil([other constantValue])) || [_value isEqual:[other constantValue]];
    return [[self _format] isEqualToString:[other _format]];
}
- (NSUInteger)hash { return [[self _format] hash]; }

/* ---- variables, key paths and Core Data's view ------------------------------------------------- */

static NSArray *substituted(NSArray *exprs, NSDictionary *vars)
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSExpression *x in exprs)
        [out addObject:[x _substitute:vars]];
    return out;
}

- (NSExpression *)_substitute:(NSDictionary *)vars
{
    NSExpression *e;
    switch (_type) {
    case NSVariableExpressionType: {
        id v = [vars objectForKey:_value];
        if (v == FKeepVariable())
            return self;
        if (!v)
            FRaise(NSInvalidArgumentException, @"Can't get value for '%@' in bindings %@.", _value, vars);
        return [NSExpression expressionForConstantValue:v];
    }
    case NSKeyPathExpressionType:
        return _operand ? [NSExpression _expressionForKeyPath:_value operand:[_operand _substitute:vars]] : self;
    case NSFunctionExpressionType:
        if (_operand)
            return [NSExpression expressionForFunction:[_operand _substitute:vars]
                                          selectorName:_value
                                             arguments:substituted(_args, vars)];
        return [NSExpression expressionForFunction:_value arguments:substituted(_args, vars)];
    case NSAggregateExpressionType: return [NSExpression expressionForAggregate:substituted(_args, vars)];
    case NSUnionSetExpressionType:
    case NSIntersectSetExpressionType:
    case NSMinusSetExpressionType:
        return set_expression(_type, [_operand _substitute:vars], [_other _substitute:vars]);
    case NSSubqueryExpressionType: {
        NSMutableDictionary *inner = [[vars mutableCopy] autorelease];
        [inner setObject:FKeepVariable() forKey:_iterator];
        return [NSExpression expressionForSubquery:[_operand _substitute:vars]
                             usingIteratorVariable:_iterator
                                         predicate:[_predicate _substitute:inner]];
    }
    case NSBlockExpressionType:
        e = [NSExpression expressionForBlock:_value arguments:substituted(_args, vars)];
        return e;
    case NSConditionalExpressionType:
        return [NSExpression expressionForConditional:[_predicate _substitute:vars]
                                       trueExpression:[_operand _substitute:vars]
                                      falseExpression:[_other _substitute:vars]];
    default: return self;
    }
}

- (void)_addKeyPathsTo:(NSMutableSet *)set
{
    switch (_type) {
    case NSKeyPathExpressionType:
        if (!_operand)
            [set addObject:_value];
        else
            [_operand _addKeyPathsTo:set];
        break;
    case NSFunctionExpressionType:
    case NSAggregateExpressionType:
    case NSBlockExpressionType:
        [_operand _addKeyPathsTo:set];
        for (NSExpression *x in _args)
            [x _addKeyPathsTo:set];
        break;
    case NSUnionSetExpressionType:
    case NSIntersectSetExpressionType:
    case NSMinusSetExpressionType:
    case NSConditionalExpressionType:
        [_operand _addKeyPathsTo:set];
        [_other _addKeyPathsTo:set];
        [_predicate _ferryAddKeyPathsTo:set];
        break;
    case NSSubqueryExpressionType: [_operand _addKeyPathsTo:set]; break;
    default: break;
    }
}

- (id)_ferryStructure
{
    switch (_type) {
    case NSConstantValueExpressionType: return @{@"kind" : @"constant", @"value" : _value ?: [NSNull null]};
    case NSEvaluatedObjectExpressionType: return @{@"kind" : @"self", @"value" : [NSNull null]};
    case NSVariableExpressionType: return @{@"kind" : @"variable", @"value" : _value};
    case NSKeyPathExpressionType:
        if (!_operand)
            return @{@"kind" : @"keypath", @"value" : _value};
        break;
    case NSAggregateExpressionType: {
        /* an aggregate of constants is one constant, an array */
        NSMutableArray *values = [NSMutableArray array], *parts = [NSMutableArray array];
        BOOL constant = YES;
        for (NSExpression *x in _args) {
            constant = constant && [x expressionType] == NSConstantValueExpressionType;
            [values addObject:[x constantValue] ?: [NSNull null]];
            [parts addObject:[x _ferryStructure]];
        }
        if (constant)
            return @{@"kind" : @"constant", @"value" : values};
        return @{@"kind" : @"aggregate", @"value" : parts};
    }
    default: break;
    }
    return @{@"kind" : @"other", @"value" : [NSNull null]};
}
@end

id FKeepVariable(void)
{
    static id keep;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keep = [[NSObject alloc] init];
    });
    return keep;
}
