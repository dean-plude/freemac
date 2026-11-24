/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSComparisonPredicate, as Apple's class reference and
 * the "Predicate Programming Guide" describe it (freemac 1.NEXT, Ferry
 * 0.NEXT). Our own code; no Apple code was used.
 *
 * A comparison has two NSExpressions, an operator (==, !=, <, <=, >, >=,
 * BETWEEN, IN, CONTAINS, BEGINSWITH, ENDSWITH, LIKE, MATCHES or a custom
 * selector), a modifier (ANY or ALL before a left side that gives a
 * collection) and options: [c] folds case, [d] drops the accents of Latin
 * letters, [n] is accepted and changes nothing. MATCHES takes an ICU
 * regular expression, through Ferry's NSRegularExpression, which must match
 * the whole string. NONE is NOT over an ANY comparison, written as NONE. */
#import "FExpression.h"

/* Strings folded as the options ask: lower case, and Latin letters without
 * their accents. */
static NSString *fold(NSString *s, NSUInteger options)
{
    if (![s isKindOfClass:[NSString class]])
        return s;
    if (options & NSCaseInsensitivePredicateOption)
        s = [s lowercaseString];
    if (options & NSDiacriticInsensitivePredicateOption) {
        static const char *latin1 = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTsaaaaaaaceeeeiiiidnooooo/ouuuuyty";
        NSMutableString *m = [NSMutableString string];
        for (NSUInteger i = 0; i < [s length]; i++) {
            unichar c = [s characterAtIndex:i];
            if (c >= 0x300 && c <= 0x36f)
                continue;   /* a combining accent */
            if (c >= 0xc0 && c <= 0xff && c != 0xd7 && c != 0xf7 && c != 0xc6 && c != 0xe6 && c != 0xdf)
                c = (unichar)latin1[c - 0xc0];
            [m appendFormat:@"%C", c];
        }
        s = m;
    }
    return s;
}

/* LIKE: * for any run of characters, ? for one. */
static BOOL like(NSString *s, NSUInteger si, NSString *p, NSUInteger pi)
{
    NSUInteger sn = [s length], pn = [p length];
    while (pi < pn) {
        unichar c = [p characterAtIndex:pi];
        if (c == '*') {
            for (NSUInteger k = si; k <= sn; k++)
                if (like(s, k, p, pi + 1))
                    return YES;
            return NO;
        }
        if (si >= sn)
            return NO;
        if (c == '\\' && pi + 1 < pn)
            c = [p characterAtIndex:++pi];
        else if (c == '?') {
            si++, pi++;
            continue;
        }
        if ([s characterAtIndex:si] != c)
            return NO;
        si++, pi++;
    }
    return si == sn;
}

/* MATCHES: the whole string against an ICU regular expression. */
static BOOL matches(NSString *s, NSString *pattern, NSUInteger options)
{
    NSError *error = nil;
    NSRegularExpressionOptions ro = (options & NSCaseInsensitivePredicateOption) ? NSRegularExpressionCaseInsensitive : 0;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:[NSString stringWithFormat:@"(?:%@)\\z", fold(pattern, options & ~NSCaseInsensitivePredicateOption)]
                             options:ro
                               error:&error];
    if (!re)
        FRaise(NSInvalidArgumentException, @"Can't do regex matching: \"%@\" isn't a regular expression (%@)", pattern,
               [error localizedDescription]);
    s = fold(s, options & ~NSCaseInsensitivePredicateOption);
    NSRange r = [re rangeOfFirstMatchInString:s options:NSMatchingAnchored range:NSMakeRange(0, [s length])];
    return r.location == 0 && r.length == [s length];
}

static BOOL equal(id a, id b, NSUInteger options)
{
    if (a == [NSNull null])
        a = nil;
    if (b == [NSNull null])
        b = nil;
    if (!a || !b)
        return a == b;
    if (options && [a isKindOfClass:[NSString class]] && [b isKindOfClass:[NSString class]])
        return [fold(a, options) isEqualToString:fold(b, options)];
    return [a isEqual:b];
}

static NSComparisonResult order(id a, id b, NSUInteger options, BOOL *ok)
{
    *ok = NO;
    if (!a || !b || a == [NSNull null] || b == [NSNull null] || ![a respondsToSelector:@selector(compare:)])
        return NSOrderedSame;
    if ([a isKindOfClass:[NSString class]] != [b isKindOfClass:[NSString class]])
        return NSOrderedSame;
    *ok = YES;
    a = fold(a, options), b = fold(b, options);
    return (NSComparisonResult)((NSInteger(*)(id, SEL, id))objc_msgSend)(a, @selector(compare:), b);
}

static BOOL compare_values(NSPredicateOperatorType op, NSUInteger options, id l, id r)
{
    BOOL ok;
    NSComparisonResult c;
    switch (op) {
    case NSEqualToPredicateOperatorType: return equal(l, r, options);
    case NSNotEqualToPredicateOperatorType: return !equal(l, r, options);
    case NSLessThanPredicateOperatorType: c = order(l, r, options, &ok); return ok && c == NSOrderedAscending;
    case NSLessThanOrEqualToPredicateOperatorType: c = order(l, r, options, &ok); return ok && c != NSOrderedDescending;
    case NSGreaterThanPredicateOperatorType: c = order(l, r, options, &ok); return ok && c == NSOrderedDescending;
    case NSGreaterThanOrEqualToPredicateOperatorType: c = order(l, r, options, &ok); return ok && c != NSOrderedAscending;
    case NSBetweenPredicateOperatorType: {
        if (![r isKindOfClass:[NSArray class]] || [r count] != 2)
            FRaise(NSInvalidArgumentException, @"BETWEEN needs a pair of values, not %@", r);
        NSComparisonResult lo = order(l, [r objectAtIndex:0], options, &ok);
        if (!ok || lo == NSOrderedAscending)
            return NO;
        NSComparisonResult hi = order(l, [r objectAtIndex:1], options, &ok);
        return ok && hi != NSOrderedDescending;
    }
    case NSInPredicateOperatorType:
        if ([r isKindOfClass:[NSString class]])
            return [l isKindOfClass:[NSString class]] &&
                   [fold(r, options) rangeOfString:fold(l, options)].location != NSNotFound;
        if ([r isKindOfClass:[NSDictionary class]])
            r = [r allValues];
        if ([r isKindOfClass:[NSSet class]])
            r = [r allObjects];
        if ([r isKindOfClass:[NSOrderedSet class]])
            r = [r array];
        if (![r isKindOfClass:[NSArray class]])
            return NO;
        for (id x in r)
            if (equal(l, x, options))
                return YES;
        return NO;
    case NSContainsPredicateOperatorType:
        if ([l isKindOfClass:[NSString class]])
            return [r isKindOfClass:[NSString class]] &&
                   [fold(l, options) rangeOfString:fold(r, options)].location != NSNotFound;
        return compare_values(NSInPredicateOperatorType, options, r, l);
    case NSBeginsWithPredicateOperatorType:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] &&
               [fold(l, options) hasPrefix:fold(r, options)];
    case NSEndsWithPredicateOperatorType:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] &&
               [fold(l, options) hasSuffix:fold(r, options)];
    case NSLikePredicateOperatorType:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] &&
               like(fold(l, options), 0, fold(r, options), 0);
    case NSMatchesPredicateOperatorType:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] && matches(l, r, options);
    default: return NO;
    }
}

static NSString *op_name(NSPredicateOperatorType op)
{
    switch (op) {
    case NSLessThanPredicateOperatorType: return @"<";
    case NSLessThanOrEqualToPredicateOperatorType: return @"<=";
    case NSGreaterThanPredicateOperatorType: return @">";
    case NSGreaterThanOrEqualToPredicateOperatorType: return @">=";
    case NSEqualToPredicateOperatorType: return @"==";
    case NSNotEqualToPredicateOperatorType: return @"!=";
    case NSMatchesPredicateOperatorType: return @"MATCHES";
    case NSLikePredicateOperatorType: return @"LIKE";
    case NSBeginsWithPredicateOperatorType: return @"BEGINSWITH";
    case NSEndsWithPredicateOperatorType: return @"ENDSWITH";
    case NSInPredicateOperatorType: return @"IN";
    case NSContainsPredicateOperatorType: return @"CONTAINS";
    case NSBetweenPredicateOperatorType: return @"BETWEEN";
    default: return nil;
    }
}

@interface NSComparisonPredicate (FBareFormat)
- (NSString *)_bareFormat;
@end

@implementation NSComparisonPredicate {
    NSExpression *_left, *_right;
    NSPredicateOperatorType _op;
    NSComparisonPredicateModifier _modifier;
    NSComparisonPredicateOptions _options;
    SEL _selector;
}
+ (NSComparisonPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                                       rightExpression:(NSExpression *)rhs
                                              modifier:(NSComparisonPredicateModifier)modifier
                                                  type:(NSPredicateOperatorType)type
                                               options:(NSComparisonPredicateOptions)options
{
    return [[[self alloc] initWithLeftExpression:lhs rightExpression:rhs modifier:modifier type:type options:options]
        autorelease];
}
+ (NSComparisonPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                                       rightExpression:(NSExpression *)rhs
                                        customSelector:(SEL)selector
{
    return [[[self alloc] initWithLeftExpression:lhs rightExpression:rhs customSelector:selector] autorelease];
}
- (instancetype)initWithLeftExpression:(NSExpression *)lhs
                       rightExpression:(NSExpression *)rhs
                              modifier:(NSComparisonPredicateModifier)modifier
                                  type:(NSPredicateOperatorType)type
                               options:(NSComparisonPredicateOptions)options
{
    if (!lhs || !rhs) {
        [self release];
        FRaise(NSInvalidArgumentException, @"*** -[NSComparisonPredicate initWithLeftExpression:rightExpression:...]: "
                                           @"an expression is nil");
    }
    if (type == NSCustomSelectorPredicateOperatorType || (!op_name(type))) {
        [self release];
        FRaise(NSInvalidArgumentException, @"Unknown predicate operator type %lu", (unsigned long)type);
    }
    if ((self = [super init])) {
        _left = [lhs retain];
        _right = [rhs retain];
        _op = type;
        _modifier = modifier;
        _options = options;
    }
    return self;
}
- (instancetype)initWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs customSelector:(SEL)selector
{
    if (!lhs || !rhs || !selector) {
        [self release];
        FRaise(NSInvalidArgumentException, @"*** -[NSComparisonPredicate initWithLeftExpression:rightExpression:"
                                           @"customSelector:]: an argument is nil");
    }
    if ((self = [super init])) {
        _left = [lhs retain];
        _right = [rhs retain];
        _op = NSCustomSelectorPredicateOperatorType;
        _selector = selector;
    }
    return self;
}
- (void)dealloc
{
    [_left release];
    [_right release];
    [super dealloc];
}
- (NSPredicateOperatorType)predicateOperatorType { return _op; }
- (NSComparisonPredicateModifier)comparisonPredicateModifier { return _modifier; }
- (NSExpression *)leftExpression { return _left; }
- (NSExpression *)rightExpression { return _right; }
- (SEL)customSelector { return _selector; }
- (NSComparisonPredicateOptions)options { return _options; }

/* The comparison as written, without its modifier. */
- (NSString *)_bareFormat
{
    if (_op == NSCustomSelectorPredicateOperatorType)
        return [NSString stringWithFormat:@"%@ %@ %@", [_left _format], NSStringFromSelector(_selector), [_right _format]];
    NSUInteger o = _options & (NSCaseInsensitivePredicateOption | NSDiacriticInsensitivePredicateOption);
    NSMutableString *opts = [NSMutableString string];
    if (o || (_options & NSNormalizedPredicateOption)) {
        [opts appendString:@"["];
        if (o & NSCaseInsensitivePredicateOption)
            [opts appendString:@"c"];
        if (o & NSDiacriticInsensitivePredicateOption)
            [opts appendString:@"d"];
        if (_options & NSNormalizedPredicateOption)
            [opts appendString:@"n"];
        [opts appendString:@"]"];
    }
    return [NSString stringWithFormat:@"%@ %@%@ %@", [_left _format], op_name(_op), opts, [_right _format]];
}
- (NSString *)predicateFormat
{
    NSString *mod = _modifier == NSAnyPredicateModifier ? @"ANY " : _modifier == NSAllPredicateModifier ? @"ALL " : @"";
    return [mod stringByAppendingString:[self _bareFormat]];
}
- (BOOL)_compare:(id)l with:(id)r
{
    if (_op == NSCustomSelectorPredicateOperatorType) {
        if (!l || l == [NSNull null] || ![l respondsToSelector:_selector])
            return NO;
        return ((BOOL(*)(id, SEL, id))objc_msgSend)(l, _selector, r == [NSNull null] ? nil : r);
    }
    return compare_values(_op, _options, l, r);
}
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars
{
    id l = [_left expressionValueWithObject:object context:(NSMutableDictionary *)vars];
    id r = [_right expressionValueWithObject:object context:(NSMutableDictionary *)vars];
    if (_modifier == NSDirectPredicateModifier)
        return [self _compare:l with:r];
    if ([l isKindOfClass:[NSSet class]])
        l = [l allObjects];
    if ([l isKindOfClass:[NSOrderedSet class]])
        l = [l array];
    if ([l isKindOfClass:[NSDictionary class]])
        l = [l allValues];
    if (![l isKindOfClass:[NSArray class]])
        FRaise(NSInvalidArgumentException, @"The left hand side for an ALL or ANY operator must be either an NSArray "
                                           @"or an NSSet.");
    BOOL all = _modifier == NSAllPredicateModifier;
    for (id x in l) {
        BOOL hit = [self _compare:(x == [NSNull null] ? nil : x) with:r];
        if (all && !hit)
            return NO;
        if (!all && hit)
            return YES;
    }
    return all;
}
- (NSPredicate *)_substitute:(NSDictionary *)vars
{
    NSExpression *l = [_left _substitute:vars], *r = [_right _substitute:vars];
    if (_op == NSCustomSelectorPredicateOperatorType)
        return [NSComparisonPredicate predicateWithLeftExpression:l rightExpression:r customSelector:_selector];
    return [NSComparisonPredicate predicateWithLeftExpression:l
                                              rightExpression:r
                                                     modifier:_modifier
                                                         type:_op
                                                      options:_options];
}
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set
{
    [_left _addKeyPathsTo:set];
    [_right _addKeyPathsTo:set];
}
/* {type: comparison, op, modifier, options, left, right}, each side
 * {kind: constant, keypath, self, variable, aggregate or other, value} */
- (id)_ferryStructure
{
    static NSString *const mods[] = {@"direct", @"all", @"any"};
    return @{
        @"type" : @"comparison",
        @"op" : op_name(_op) ?: @"CUSTOM",
        @"modifier" : _modifier <= NSAnyPredicateModifier ? mods[_modifier] : @"other",
        @"caseInsensitive" : @((_options & NSCaseInsensitivePredicateOption) != 0),
        @"diacriticInsensitive" : @((_options & NSDiacriticInsensitivePredicateOption) != 0),
        @"left" : [_left _ferryStructure],
        @"right" : [_right _ferryStructure],
    };
}
@end

/* ---- NONE ------------------------------------------------------------------------------ */

@interface FNoneCompoundPredicate : NSCompoundPredicate
@end
@implementation FNoneCompoundPredicate
- (NSComparisonPredicate *)_inner { return [[self subpredicates] firstObject]; }
- (NSString *)predicateFormat { return [@"NONE " stringByAppendingString:[[self _inner] _bareFormat]]; }
- (NSPredicate *)_substitute:(NSDictionary *)vars { return FNonePredicate([[self _inner] _substitute:vars]); }
- (id)_ferryStructure
{
    NSMutableDictionary *s = [[[[self _inner] _ferryStructure] mutableCopy] autorelease];
    [s setObject:@"none" forKey:@"modifier"];
    return s;
}
@end

NSPredicate *FNonePredicate(NSPredicate *anyComparison)
{
    return [[[FNoneCompoundPredicate alloc] initWithType:NSNotPredicateType subpredicates:@[ anyComparison ]] autorelease];
}
