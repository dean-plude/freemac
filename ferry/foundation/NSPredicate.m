/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSPredicate, a subset, as Apple's "Predicate
 * Programming Guide" and the NSPredicate reference describe it. Our own
 * code; no Apple code was used.
 *
 * A predicate is read from a format string into a small tree: AND, OR and
 * NOT (also &&, || and !) over comparisons, with parentheses;
 * TRUEPREDICATE and FALSEPREDICATE. A comparison has two expressions, each
 * a key path (SELF for the object itself), a constant (a quoted string, a
 * number, YES/TRUE, NO/FALSE, NIL/NULL, or an aggregate {a, b}), a
 * $variable, or a format argument (%@ an object, %K a key path, %d, %i,
 * %ld, %lu, %u, %lld, %llu and %f, %lf numbers, %s a C string). The
 * operators are ==, =, !=, <>, <, <=, =<, >, >=, =>, BETWEEN, IN,
 * CONTAINS, BEGINSWITH, ENDSWITH and LIKE (* and ? as wildcards), with
 * [c] (case), [d] (accents, Latin letters only) or [cd] for strings, and
 * ANY, SOME, ALL and NONE before a key path that gives a collection.
 *
 * Not done: MATCHES (regular expressions), function expressions, SUBQUERY,
 * arithmetic, keyed archiving of predicates, NSExpression and
 * NSComparisonPredicate as public classes. */
#import "FInternal.h"
#include <stdarg.h>

/* ---- expressions ------------------------------------------------------------------- */

typedef enum { E_CONSTANT, E_KEYPATH, E_SELF, E_VARIABLE, E_AGGREGATE } FPExprKind;

@interface FPExpr : NSObject {
@public
    FPExprKind kind;
    id value;   /* the constant, the key path, the variable's name, or an array of FPExpr */
}
@end
@implementation FPExpr
+ (FPExpr *)kind:(FPExprKind)k value:(id)v
{
    FPExpr *e = [[[FPExpr alloc] init] autorelease];
    e->kind = k;
    e->value = [v retain];
    return e;
}
- (void)dealloc
{
    [value release];
    [super dealloc];
}
@end

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

static NSString *expr_format(FPExpr *e)
{
    switch (e->kind) {
    case E_SELF: return @"SELF";
    case E_KEYPATH: return e->value;
    case E_VARIABLE: return [@"$" stringByAppendingString:e->value];
    case E_AGGREGATE: {
        NSMutableArray *parts = [NSMutableArray array];
        for (FPExpr *x in e->value)
            [parts addObject:expr_format(x)];
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
    }
    case E_CONSTANT:
        if (!e->value || e->value == [NSNull null])
            return @"nil";
        if ([e->value isKindOfClass:[NSString class]])
            return quote(e->value);
        if ([e->value isKindOfClass:[NSArray class]] || [e->value isKindOfClass:[NSSet class]]) {
            NSMutableArray *parts = [NSMutableArray array];
            for (id x in ([e->value isKindOfClass:[NSSet class]] ? [e->value allObjects] : e->value))
                [parts addObject:[x isKindOfClass:[NSString class]] ? quote(x) : [x description]];
            return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
        }
        return [e->value description];
    }
    return @"";
}

static id expr_value(FPExpr *e, id object, NSDictionary *vars)
{
    switch (e->kind) {
    case E_CONSTANT: return e->value == [NSNull null] ? nil : e->value;
    case E_SELF: return object;
    case E_KEYPATH: return [object valueForKeyPath:e->value];
    case E_VARIABLE: {
        id v = [vars objectForKey:e->value];
        if (!v && !vars)
            FRaise(NSInvalidArgumentException, @"Can't get value for '%@' in bindings %@.", e->value, vars);
        return v == [NSNull null] ? nil : v;
    }
    case E_AGGREGATE: {
        NSMutableArray *out = [NSMutableArray array];
        for (FPExpr *x in e->value)
            [out addObject:expr_value(x, object, vars) ?: [NSNull null]];
        return out;
    }
    }
    return nil;
}

static FPExpr *expr_substitute(FPExpr *e, NSDictionary *vars)
{
    if (e->kind == E_VARIABLE) {
        id v = [vars objectForKey:e->value];
        if (!v)
            FRaise(NSInvalidArgumentException, @"Can't get value for '%@' in bindings %@.", e->value, vars);
        return [FPExpr kind:E_CONSTANT value:v];
    }
    if (e->kind == E_AGGREGATE) {
        NSMutableArray *out = [NSMutableArray array];
        for (FPExpr *x in e->value)
            [out addObject:expr_substitute(x, vars)];
        return [FPExpr kind:E_AGGREGATE value:out];
    }
    return e;
}

/* ---- the predicate classes --------------------------------------------------------- */

typedef enum {
    OP_EQ, OP_NE, OP_LT, OP_LE, OP_GT, OP_GE, OP_BETWEEN, OP_IN, OP_CONTAINS, OP_BEGINS, OP_ENDS, OP_LIKE
} FPOp;
typedef enum { MOD_DIRECT, MOD_ANY, MOD_ALL, MOD_NONE } FPModifier;
enum { OPT_CASE = 1, OPT_DIACRITIC = 2 };

static NSString *const op_names[] = {@"==", @"!=", @"<", @"<=", @">", @">=", @"BETWEEN", @"IN",
                                     @"CONTAINS", @"BEGINSWITH", @"ENDSWITH", @"LIKE"};

@interface FComparisonPredicate : NSPredicate {
@public
    FPExpr *left, *right;
    FPOp op;
    FPModifier modifier;
    unsigned options;
}
@end
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

@interface NSPredicate ()
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars;
- (NSPredicate *)_substitute:(NSDictionary *)vars;
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set;
@end

/* Strings folded as the options ask: lower case, and Latin letters without
 * their accents. */
static NSString *fold(NSString *s, unsigned options)
{
    if (![s isKindOfClass:[NSString class]])
        return s;
    if (options & OPT_CASE)
        s = [s lowercaseString];
    if (options & OPT_DIACRITIC) {
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

static BOOL equal(id a, id b, unsigned options)
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

static NSComparisonResult order(id a, id b, unsigned options, BOOL *ok)
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

static BOOL compare_values(FPOp op, unsigned options, id l, id r)
{
    BOOL ok;
    NSComparisonResult c;
    switch (op) {
    case OP_EQ: return equal(l, r, options);
    case OP_NE: return !equal(l, r, options);
    case OP_LT: c = order(l, r, options, &ok); return ok && c == NSOrderedAscending;
    case OP_LE: c = order(l, r, options, &ok); return ok && c != NSOrderedDescending;
    case OP_GT: c = order(l, r, options, &ok); return ok && c == NSOrderedDescending;
    case OP_GE: c = order(l, r, options, &ok); return ok && c != NSOrderedAscending;
    case OP_BETWEEN: {
        if (![r isKindOfClass:[NSArray class]] || [r count] != 2)
            FRaise(NSInvalidArgumentException, @"BETWEEN needs a pair of values, not %@", r);
        NSComparisonResult lo = order(l, [r objectAtIndex:0], options, &ok);
        if (!ok || lo == NSOrderedAscending)
            return NO;
        NSComparisonResult hi = order(l, [r objectAtIndex:1], options, &ok);
        return ok && hi != NSOrderedDescending;
    }
    case OP_IN:
        if ([r isKindOfClass:[NSString class]])
            return [l isKindOfClass:[NSString class]] &&
                   [fold(r, options) rangeOfString:fold(l, options)].location != NSNotFound;
        if ([r isKindOfClass:[NSDictionary class]])
            r = [r allValues];
        if ([r isKindOfClass:[NSSet class]])
            r = [r allObjects];
        if (![r isKindOfClass:[NSArray class]])
            return NO;
        for (id x in r)
            if (equal(l, x, options))
                return YES;
        return NO;
    case OP_CONTAINS:
        if ([l isKindOfClass:[NSString class]])
            return [r isKindOfClass:[NSString class]] &&
                   [fold(l, options) rangeOfString:fold(r, options)].location != NSNotFound;
        return compare_values(OP_IN, options, r, l);
    case OP_BEGINS:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] &&
               [fold(l, options) hasPrefix:fold(r, options)];
    case OP_ENDS:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] &&
               [fold(l, options) hasSuffix:fold(r, options)];
    case OP_LIKE:
        return [l isKindOfClass:[NSString class]] && [r isKindOfClass:[NSString class]] &&
               like(fold(l, options), 0, fold(r, options), 0);
    }
    return NO;
}

static NSPredicate *parse(NSString *format, va_list *ap, NSArray *args);

@implementation NSPredicate
+ (NSPredicate *)predicateWithFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    NSPredicate *p = parse(format, &ap, nil);
    va_end(ap);
    return p;
}
+ (NSPredicate *)predicateWithFormat:(NSString *)format arguments:(va_list)args
{
    va_list ap;
    va_copy(ap, args);
    NSPredicate *p = parse(format, &ap, nil);
    va_end(ap);
    return p;
}
+ (NSPredicate *)predicateWithFormat:(NSString *)format argumentArray:(NSArray *)arguments
{
    return parse(format, NULL, arguments ?: @[]);
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
- (NSString *)predicateFormat { return @""; }
- (NSString *)description { return [self predicateFormat]; }
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars { return NO; }
- (NSPredicate *)_substitute:(NSDictionary *)vars { return self; }
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set {}
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

@implementation FComparisonPredicate
- (void)dealloc
{
    [left release];
    [right release];
    [super dealloc];
}
- (NSString *)predicateFormat
{
    NSString *mod = modifier == MOD_ANY ? @"ANY " : modifier == MOD_ALL ? @"ALL " : modifier == MOD_NONE ? @"NONE " : @"";
    NSString *opts = options == (OPT_CASE | OPT_DIACRITIC) ? @"[cd]" : options == OPT_CASE ? @"[c]"
                     : options == OPT_DIACRITIC                ? @"[d]"
                                                                : @"";
    return [NSString stringWithFormat:@"%@%@ %@%@ %@", mod, expr_format(left), op_names[op], opts, expr_format(right)];
}
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars
{
    id l = expr_value(left, object, vars), r = expr_value(right, object, vars);
    if (modifier == MOD_DIRECT)
        return compare_values(op, options, l, r);
    if ([l isKindOfClass:[NSSet class]])
        l = [l allObjects];
    if ([l isKindOfClass:[NSDictionary class]])
        l = [l allValues];
    if (![l isKindOfClass:[NSArray class]])
        FRaise(NSInvalidArgumentException, @"The left hand side for an ALL or ANY operator must be either an NSArray "
                                           @"or an NSSet.");
    for (id x in l) {
        BOOL hit = compare_values(op, options, x == [NSNull null] ? nil : x, r);
        if (modifier == MOD_ALL && !hit)
            return NO;
        if (modifier != MOD_ALL && hit)
            return modifier == MOD_ANY;
    }
    return modifier != MOD_ANY;
}
- (NSPredicate *)_substitute:(NSDictionary *)vars
{
    FComparisonPredicate *p = [[[FComparisonPredicate alloc] init] autorelease];
    p->left = [expr_substitute(left, vars) retain];
    p->right = [expr_substitute(right, vars) retain];
    p->op = op;
    p->modifier = modifier;
    p->options = options;
    return p;
}
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set
{
    for (FPExpr *e in @[ left, right ])
        if (e->kind == E_KEYPATH)
            [set addObject:e->value];
}
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
@end

/* ---- reading a format string ------------------------------------------------------- */

typedef struct {
    NSString *s;
    NSUInteger at, n;
    va_list *ap;          /* the arguments, from a va_list ... */
    NSArray *args;        /* ... or an array */
    NSUInteger next;
} FPParser;

static void parse_error(FPParser *p)
{
    FRaise(NSInvalidArgumentException, @"Unable to parse the format string \"%@\"", p->s);
}

static void skip_space(FPParser *p)
{
    while (p->at < p->n && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[p->s characterAtIndex:p->at]])
        p->at++;
}
static unichar peek(FPParser *p, NSUInteger ahead)
{
    return p->at + ahead < p->n ? [p->s characterAtIndex:p->at + ahead] : 0;
}
static BOOL ident_char(unichar c, BOOL first)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '@' || c > 127 ||
           (!first && ((c >= '0' && c <= '9') || c == '.'));
}
/* The next word (letters, digits, _, @ and dots), not consumed. */
static NSString *peek_word(FPParser *p)
{
    skip_space(p);
    NSUInteger e = p->at;
    while (e < p->n && ident_char([p->s characterAtIndex:e], e == p->at))
        e++;
    return [p->s substringWithRange:NSMakeRange(p->at, e - p->at)];
}
static BOOL take_word(FPParser *p, NSString *word)
{
    NSString *w = peek_word(p);
    if ([w caseInsensitiveCompare:word] != NSOrderedSame)
        return NO;
    p->at += [w length];
    return YES;
}
static BOOL take(FPParser *p, NSString *sym)
{
    skip_space(p);
    NSUInteger l = [sym length];
    if (p->at + l > p->n || ![[p->s substringWithRange:NSMakeRange(p->at, l)] isEqualToString:sym])
        return NO;
    p->at += l;
    return YES;
}

static id next_object(FPParser *p)
{
    if (p->args) {
        if (p->next >= [p->args count])
            parse_error(p);
        id v = [p->args objectAtIndex:p->next++];
        return v == [NSNull null] ? nil : v;
    }
    return p->ap ? va_arg(*p->ap, id) : nil;
}

/* A format argument: %@, %K and the number and string forms. */
static FPExpr *parse_argument(FPParser *p)
{
    p->at++;   /* % */
    NSUInteger l = 0;
    while (peek(p, 0) == 'l' || peek(p, 0) == 'q' || peek(p, 0) == 'h' || peek(p, 0) == 'z') {
        l++;
        p->at++;
    }
    unichar c = peek(p, 0);
    p->at++;
    if (p->args && c != 'K' && c != '@') {
        id v = next_object(p);
        if (c == 's' && ![v isKindOfClass:[NSString class]])
            v = [v description];
        return [FPExpr kind:E_CONSTANT value:v];
    }
    switch (c) {
    case '@': return [FPExpr kind:E_CONSTANT value:next_object(p)];
    case 'K': {
        id k = next_object(p);
        return [FPExpr kind:E_KEYPATH value:[k description]];
    }
    case 'd':
    case 'i':
        if (!p->ap)
            parse_error(p);
        return [FPExpr kind:E_CONSTANT value:l ? @(va_arg(*p->ap, long long)) : @(va_arg(*p->ap, int))];
    case 'u':
        if (!p->ap)
            parse_error(p);
        return [FPExpr kind:E_CONSTANT
                      value:l ? @(va_arg(*p->ap, unsigned long long)) : @(va_arg(*p->ap, unsigned int))];
    case 'f':
    case 'g':
    case 'e':
        if (!p->ap)
            parse_error(p);
        return [FPExpr kind:E_CONSTANT value:@(va_arg(*p->ap, double))];
    case 's': {
        if (!p->ap)
            parse_error(p);
        const char *cs = va_arg(*p->ap, const char *);
        return [FPExpr kind:E_CONSTANT value:cs ? [NSString stringWithUTF8String:cs] : nil];
    }
    }
    parse_error(p);
    return nil;
}

static FPExpr *parse_expr(FPParser *p)
{
    skip_space(p);
    unichar c = peek(p, 0);
    if (c == '%')
        return parse_argument(p);
    if (c == '"' || c == '\'') {
        p->at++;
        NSMutableString *m = [NSMutableString string];
        for (;;) {
            if (p->at >= p->n)
                parse_error(p);
            unichar d = [p->s characterAtIndex:p->at++];
            if (d == c)
                break;
            if (d == '\\' && p->at < p->n) {
                d = [p->s characterAtIndex:p->at++];
                d = d == 'n' ? '\n' : d == 't' ? '\t' : d;
            }
            [m appendFormat:@"%C", d];
        }
        return [FPExpr kind:E_CONSTANT value:[NSString stringWithString:m]];
    }
    if ((c >= '0' && c <= '9') || ((c == '-' || c == '+' || c == '.') && peek(p, 1) >= '0' && peek(p, 1) <= '9')) {
        NSUInteger start = p->at;
        BOOL real = NO;
        p->at++;
        while (p->at < p->n) {
            unichar d = [p->s characterAtIndex:p->at];
            if (d == '.' || d == 'e' || d == 'E')
                real = YES;
            else if (!(d >= '0' && d <= '9') && !((d == '-' || d == '+') && real))
                break;
            p->at++;
        }
        NSString *num = [p->s substringWithRange:NSMakeRange(start, p->at - start)];
        return [FPExpr kind:E_CONSTANT value:real ? @([num doubleValue]) : @([num longLongValue])];
    }
    if (c == '{') {
        p->at++;
        NSMutableArray *items = [NSMutableArray array];
        if (!take(p, @"}")) {
            do
                [items addObject:parse_expr(p)];
            while (take(p, @","));
            if (!take(p, @"}"))
                parse_error(p);
        }
        BOOL constant = YES;
        for (FPExpr *x in items)
            constant = constant && x->kind == E_CONSTANT;
        if (constant) {
            NSMutableArray *values = [NSMutableArray array];
            for (FPExpr *x in items)
                [values addObject:x->value ?: [NSNull null]];
            return [FPExpr kind:E_CONSTANT value:values];
        }
        return [FPExpr kind:E_AGGREGATE value:items];
    }
    if (c == '$') {
        p->at++;
        NSString *w = peek_word(p);
        if (![w length])
            parse_error(p);
        p->at += [w length];
        return [FPExpr kind:E_VARIABLE value:w];
    }
    if (c == '#')
        p->at++;   /* a reserved word used as a key */
    NSString *w = peek_word(p);
    if (![w length])
        parse_error(p);
    p->at += [w length];
    NSString *u = [w uppercaseString];
    if ([u isEqualToString:@"SELF"])
        return [FPExpr kind:E_SELF value:nil];
    if ([u isEqualToString:@"YES"] || [u isEqualToString:@"TRUE"])
        return [FPExpr kind:E_CONSTANT value:@YES];
    if ([u isEqualToString:@"NO"] || [u isEqualToString:@"FALSE"])
        return [FPExpr kind:E_CONSTANT value:@NO];
    if ([u isEqualToString:@"NIL"] || [u isEqualToString:@"NULL"])
        return [FPExpr kind:E_CONSTANT value:nil];
    if ([u hasPrefix:@"SELF."])
        w = [w substringFromIndex:5];
    return [FPExpr kind:E_KEYPATH value:w];
}

static NSPredicate *parse_or(FPParser *p);

static NSPredicate *parse_comparison(FPParser *p)
{
    FPModifier mod = MOD_DIRECT;
    if (take_word(p, @"ANY") || take_word(p, @"SOME"))
        mod = MOD_ANY;
    else if (take_word(p, @"ALL"))
        mod = MOD_ALL;
    else if (take_word(p, @"NONE"))
        mod = MOD_NONE;
    FPExpr *l = parse_expr(p);
    FPOp op;
    skip_space(p);
    if (take(p, @"=="))
        op = OP_EQ;
    else if (take(p, @"=>") || take(p, @">="))
        op = OP_GE;
    else if (take(p, @"=<") || take(p, @"<="))
        op = OP_LE;
    else if (take(p, @"!=") || take(p, @"<>"))
        op = OP_NE;
    else if (take(p, @"<"))
        op = OP_LT;
    else if (take(p, @">"))
        op = OP_GT;
    else if (take(p, @"="))
        op = OP_EQ;
    else if (take_word(p, @"BETWEEN"))
        op = OP_BETWEEN;
    else if (take_word(p, @"IN"))
        op = OP_IN;
    else if (take_word(p, @"CONTAINS"))
        op = OP_CONTAINS;
    else if (take_word(p, @"BEGINSWITH"))
        op = OP_BEGINS;
    else if (take_word(p, @"ENDSWITH"))
        op = OP_ENDS;
    else if (take_word(p, @"LIKE"))
        op = OP_LIKE;
    else {
        parse_error(p);
        return nil;
    }
    unsigned options = 0;
    if (peek(p, 0) == '[') {
        p->at++;
        while (p->at < p->n && peek(p, 0) != ']') {
            unichar c = peek(p, 0);
            if (c == 'c' || c == 'C')
                options |= OPT_CASE;
            else if (c == 'd' || c == 'D')
                options |= OPT_DIACRITIC;
            else if (c != 'n' && c != 'l')
                parse_error(p);
            p->at++;
        }
        if (!take(p, @"]"))
            parse_error(p);
    }
    FComparisonPredicate *c = [[[FComparisonPredicate alloc] init] autorelease];
    c->left = [l retain];
    c->right = [parse_expr(p) retain];
    c->op = op;
    c->modifier = mod;
    c->options = options;
    return c;
}

static NSPredicate *parse_primary(FPParser *p)
{
    if (take(p, @"(")) {
        NSPredicate *inner = parse_or(p);
        if (!take(p, @")"))
            parse_error(p);
        return inner;
    }
    if (take_word(p, @"TRUEPREDICATE"))
        return [NSPredicate predicateWithValue:YES];
    if (take_word(p, @"FALSEPREDICATE"))
        return [NSPredicate predicateWithValue:NO];
    return parse_comparison(p);
}
static NSPredicate *parse_not(FPParser *p)
{
    skip_space(p);
    if (take_word(p, @"NOT") || (peek(p, 0) == '!' && peek(p, 1) != '=' && take(p, @"!")))
        return [NSCompoundPredicate notPredicateWithSubpredicate:parse_not(p)];
    return parse_primary(p);
}
static NSPredicate *parse_and(FPParser *p)
{
    NSMutableArray *parts = [NSMutableArray arrayWithObject:parse_not(p)];
    while (take_word(p, @"AND") || take(p, @"&&"))
        [parts addObject:parse_not(p)];
    return [parts count] == 1 ? [parts firstObject] : [NSCompoundPredicate andPredicateWithSubpredicates:parts];
}
static NSPredicate *parse_or(FPParser *p)
{
    NSMutableArray *parts = [NSMutableArray arrayWithObject:parse_and(p)];
    while (take_word(p, @"OR") || take(p, @"||"))
        [parts addObject:parse_and(p)];
    return [parts count] == 1 ? [parts firstObject] : [NSCompoundPredicate orPredicateWithSubpredicates:parts];
}

static NSPredicate *parse(NSString *format, va_list *ap, NSArray *args)
{
    if (!format)
        FRaise(NSInvalidArgumentException, @"*** -[NSPredicate predicateWithFormat:]: the format is nil");
    FPParser p = {format, 0, [format length], ap, args, 0};
    NSPredicate *result = parse_or(&p);
    skip_space(&p);
    if (p.at != p.n)
        parse_error(&p);
    return result;
}

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
