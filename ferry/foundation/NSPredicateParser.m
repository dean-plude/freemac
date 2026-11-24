/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: reading predicates and expressions from format
 * strings, as the "Predicate Format String Syntax" of Apple's Predicate
 * Programming Guide describes them (freemac 1.211, Ferry 0.37.0). Our own
 * code; no Apple code was used.
 *
 * Predicates: AND, OR and NOT (also &&, || and !) over comparisons, with
 * parentheses; TRUEPREDICATE and FALSEPREDICATE. A comparison is an
 * expression, an operator (==, =, !=, <>, <, <=, =<, >, >=, =>, BETWEEN,
 * IN, CONTAINS, BEGINSWITH, ENDSWITH, LIKE or MATCHES) with [c], [d], [n]
 * or a mix of them, and another expression, after ANY, SOME, ALL or NONE
 * when the left side gives a collection.
 *
 * Expressions: constants (a quoted string, a number in decimal or with
 * 0x, 0o or 0b, YES/TRUE, NO/FALSE, NIL/NULL), key paths (SELF for the
 * object itself, # before a reserved word used as a key), $variables, the
 * format arguments (%@ an object, %K a key path, %d, %i, %ld, %lu, %u,
 * %lld, %llu and %f, %lf numbers, %s a C string), aggregates {a, b},
 * arithmetic (+, -, *, / and **, with unary minus), the built-in functions
 * by name (sum:(list), now(), add:to:(1, 2)), FUNCTION(target, 'selector',
 * arguments), SUBQUERY(collection, $x, predicate), TERNARY(predicate, a,
 * b), CAST(value, 'type'), UNION, INTERSECT and MINUS, ANYKEY, an index
 * (list[0], list[FIRST], list[LAST], list[SIZE], dictionary['key']) and a
 * key path read from any of these (SUBQUERY(...).@count, $x.name). */
#import "FExpression.h"
#include <stdarg.h>

typedef struct {
    NSString *s;
    NSUInteger at, n;
    va_list *ap;     /* the arguments, from a va_list ... */
    NSArray *args;   /* ... or an array */
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
static void expect(FPParser *p, NSString *sym)
{
    if (!take(p, sym))
        parse_error(p);
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

static NSExpression *constant(id v) { return [NSExpression expressionForConstantValue:v]; }

/* A format argument: %@, %K and the number and string forms. */
static NSExpression *parse_argument(FPParser *p)
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
        return constant(v);
    }
    switch (c) {
    case '@': return constant(next_object(p));
    case 'K': {
        id k = next_object(p);
        return [NSExpression expressionForKeyPath:[k description] ?: @""];
    }
    case 'd':
    case 'i':
        if (!p->ap)
            parse_error(p);
        return constant(l ? @(va_arg(*p->ap, long long)) : @(va_arg(*p->ap, int)));
    case 'u':
        if (!p->ap)
            parse_error(p);
        return constant(l ? @(va_arg(*p->ap, unsigned long long)) : @(va_arg(*p->ap, unsigned int)));
    case 'f':
    case 'g':
    case 'e':
        if (!p->ap)
            parse_error(p);
        return constant(@(va_arg(*p->ap, double)));
    case 's': {
        if (!p->ap)
            parse_error(p);
        const char *cs = va_arg(*p->ap, const char *);
        return constant(cs ? [NSString stringWithUTF8String:cs] : nil);
    }
    }
    parse_error(p);
    return nil;
}

static NSPredicate *parse_or(FPParser *p);
static NSExpression *parse_expr(FPParser *p);

static NSArray *parse_list(FPParser *p, NSString *close)
{
    NSMutableArray *items = [NSMutableArray array];
    if (take(p, close))
        return items;
    do
        [items addObject:parse_expr(p)];
    while (take(p, @","));
    expect(p, close);
    return items;
}

static NSExpression *parse_number(FPParser *p)
{
    NSUInteger start = p->at;
    BOOL neg = NO;
    if (peek(p, 0) == '-' || peek(p, 0) == '+') {
        neg = peek(p, 0) == '-';
        p->at++;
    }
    unichar base = peek(p, 1);
    if (peek(p, 0) == '0' && (base == 'x' || base == 'X' || base == 'o' || base == 'O' || base == 'b' || base == 'B')) {
        int radix = (base == 'x' || base == 'X') ? 16 : (base == 'o' || base == 'O') ? 8 : 2;
        p->at += 2;
        unsigned long long v = 0;
        BOOL any = NO;
        for (;;) {
            unichar d = peek(p, 0);
            int digit = (d >= '0' && d <= '9') ? d - '0' : (d >= 'a' && d <= 'f') ? d - 'a' + 10
                      : (d >= 'A' && d <= 'F')                                   ? d - 'A' + 10
                                                                                  : 99;
            if (digit >= radix)
                break;
            v = v * radix + digit;
            any = YES;
            p->at++;
        }
        if (!any)
            parse_error(p);
        return constant(@(neg ? -(long long)v : (long long)v));
    }
    BOOL real = NO;
    while (p->at < p->n) {
        unichar d = [p->s characterAtIndex:p->at];
        if (d == '.' || d == 'e' || d == 'E') {
            if (d == '.' && real)
                break;
            real = YES;
        } else if (!(d >= '0' && d <= '9') && !((d == '-' || d == '+') &&
                                                ([p->s characterAtIndex:p->at - 1] == 'e' ||
                                                 [p->s characterAtIndex:p->at - 1] == 'E')))
            break;
        p->at++;
    }
    NSString *num = [p->s substringWithRange:NSMakeRange(start, p->at - start)];
    return constant(real ? @([num doubleValue]) : @([num longLongValue]));
}

/* NAME(arguments) for a function name written with its colons, as sum:(...) or add:to:(...). */
static NSExpression *parse_function_call(FPParser *p, NSString *first)
{
    NSMutableString *name = [NSMutableString stringWithString:first];
    while (peek(p, 0) == ':') {
        p->at++;
        [name appendString:@":"];
        NSUInteger e = p->at;
        while (e < p->n && ident_char([p->s characterAtIndex:e], e == p->at) && [p->s characterAtIndex:e] != '.')
            e++;
        if (e > p->at && e < p->n && [p->s characterAtIndex:e] == ':') {
            [name appendString:[p->s substringWithRange:NSMakeRange(p->at, e - p->at)]];
            p->at = e;
        }
    }
    skip_space(p);
    expect(p, @"(");
    return [NSExpression expressionForFunction:name arguments:parse_list(p, @")")];
}

static NSExpression *parse_primary_expr(FPParser *p)
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
        return constant([NSString stringWithString:m]);
    }
    if ((c >= '0' && c <= '9') || ((c == '-' || c == '+' || c == '.') && peek(p, 1) >= '0' && peek(p, 1) <= '9'))
        return parse_number(p);
    if (c == '{') {
        p->at++;
        return [NSExpression expressionForAggregate:parse_list(p, @"}")];
    }
    if (c == '(') {
        p->at++;
        NSExpression *inner = parse_expr(p);
        expect(p, @")");
        return inner;
    }
    if (c == '$') {
        p->at++;
        NSString *w = peek_word(p);
        if (![w length])
            parse_error(p);
        p->at += [w length];
        NSRange dot = [w rangeOfString:@"."];
        if (dot.location == NSNotFound)
            return [NSExpression expressionForVariable:w];
        return [NSExpression _expressionForKeyPath:[w substringFromIndex:dot.location + 1]
                                           operand:[NSExpression expressionForVariable:[w substringToIndex:dot.location]]];
    }
    BOOL escaped = NO;
    if (c == '#') {
        p->at++;   /* a reserved word used as a key */
        escaped = YES;
    }
    NSString *w = peek_word(p);
    if (![w length])
        parse_error(p);
    p->at += [w length];
    NSString *u = [w uppercaseString];
    unichar after = peek(p, 0);
    if (!escaped) {
        if (after == '(' && [u isEqualToString:@"FUNCTION"]) {
            p->at++;
            NSExpression *target = parse_expr(p);
            expect(p, @",");
            NSExpression *sel = parse_expr(p);
            if ([sel expressionType] != NSConstantValueExpressionType || ![[sel constantValue] isKindOfClass:[NSString class]])
                parse_error(p);
            NSArray *args = take(p, @",") ? parse_list(p, @")") : (expect(p, @")"), @[]);
            return [NSExpression expressionForFunction:target selectorName:[sel constantValue] arguments:args];
        }
        if (after == '(' && [u isEqualToString:@"SUBQUERY"]) {
            p->at++;
            NSExpression *collection = parse_expr(p);
            expect(p, @",");
            NSExpression *var = parse_expr(p);
            if ([var expressionType] != NSVariableExpressionType)
                parse_error(p);
            expect(p, @",");
            NSPredicate *pred = parse_or(p);
            expect(p, @")");
            return [NSExpression expressionForSubquery:collection usingIteratorVariable:[var variable] predicate:pred];
        }
        if (after == '(' && [u isEqualToString:@"TERNARY"]) {
            p->at++;
            NSPredicate *pred = parse_or(p);
            expect(p, @",");
            NSExpression *yes = parse_expr(p);
            expect(p, @",");
            NSExpression *no = parse_expr(p);
            expect(p, @")");
            return [NSExpression expressionForConditional:pred trueExpression:yes falseExpression:no];
        }
        if (after == '(' && [u isEqualToString:@"CAST"]) {
            p->at++;
            NSArray *args = parse_list(p, @")");
            if ([args count] != 2)
                parse_error(p);
            return [NSExpression expressionForFunction:@"castObject:toType:" arguments:args];
        }
        if (after == '(' || (after == ':' && peek(p, 1) != '=')) {
            if ([w rangeOfString:@"."].location != NSNotFound)
                parse_error(p);
            return parse_function_call(p, w);
        }
        if ([u isEqualToString:@"SELF"])
            return [NSExpression expressionForEvaluatedObject];
        if ([u isEqualToString:@"YES"] || [u isEqualToString:@"TRUE"])
            return constant(@YES);
        if ([u isEqualToString:@"NO"] || [u isEqualToString:@"FALSE"])
            return constant(@NO);
        if ([u isEqualToString:@"NIL"] || [u isEqualToString:@"NULL"])
            return constant(nil);
        if ([u isEqualToString:@"ANYKEY"])
            return [NSExpression expressionForAnyKey];
        if ([u hasPrefix:@"SELF."])
            w = [w substringFromIndex:5];
    }
    return [NSExpression expressionForKeyPath:w];
}

/* A key path or an index after an expression. */
static NSExpression *parse_postfix(FPParser *p)
{
    NSExpression *e = parse_primary_expr(p);
    for (;;) {
        if (peek(p, 0) == '.' && ident_char(peek(p, 1), YES)) {
            p->at++;
            NSString *w = peek_word(p);
            p->at += [w length];
            e = [NSExpression _expressionForKeyPath:w operand:e];
            continue;
        }
        NSUInteger save = p->at;
        skip_space(p);
        if (peek(p, 0) == '[') {
            p->at++;
            NSExpression *index;
            NSString *w = [peek_word(p) uppercaseString];
            if ([w isEqualToString:@"FIRST"] || [w isEqualToString:@"LAST"] || [w isEqualToString:@"SIZE"]) {
                p->at += [w length];
                index = constant(w);
            } else
                index = parse_expr(p);
            expect(p, @"]");
            e = [NSExpression expressionForFunction:@"objectFrom:withIndex:" arguments:@[ e, index ]];
            continue;
        }
        p->at = save;
        return e;
    }
}

static NSExpression *parse_unary(FPParser *p)
{
    skip_space(p);
    if (peek(p, 0) == '-' && !(peek(p, 1) >= '0' && peek(p, 1) <= '9') && peek(p, 1) != '.') {
        p->at++;
        return [NSExpression expressionForFunction:@"from:subtract:" arguments:@[ constant(@0), parse_unary(p) ]];
    }
    return parse_postfix(p);
}

static NSExpression *parse_power(FPParser *p)
{
    NSExpression *base = parse_unary(p);
    if (take(p, @"**"))
        return [NSExpression expressionForFunction:@"raise:toPower:" arguments:@[ base, parse_power(p) ]];
    return base;
}

static NSExpression *parse_multiplicative(FPParser *p)
{
    NSExpression *e = parse_power(p);
    for (;;) {
        skip_space(p);
        if (peek(p, 0) == '*' && peek(p, 1) != '*') {
            p->at++;
            e = [NSExpression expressionForFunction:@"multiply:by:" arguments:@[ e, parse_power(p) ]];
        } else if (peek(p, 0) == '/') {
            p->at++;
            e = [NSExpression expressionForFunction:@"divide:by:" arguments:@[ e, parse_power(p) ]];
        } else
            return e;
    }
}

static NSExpression *parse_additive(FPParser *p)
{
    NSExpression *e = parse_multiplicative(p);
    for (;;) {
        skip_space(p);
        if (peek(p, 0) == '+') {
            p->at++;
            e = [NSExpression expressionForFunction:@"add:to:" arguments:@[ e, parse_multiplicative(p) ]];
        } else if (peek(p, 0) == '-') {
            p->at++;
            e = [NSExpression expressionForFunction:@"from:subtract:" arguments:@[ e, parse_multiplicative(p) ]];
        } else
            return e;
    }
}

static NSExpression *parse_expr(FPParser *p)
{
    NSExpression *e = parse_additive(p);
    for (;;) {
        if (take_word(p, @"UNION"))
            e = [NSExpression expressionForUnionSet:e with:parse_additive(p)];
        else if (take_word(p, @"INTERSECT"))
            e = [NSExpression expressionForIntersectSet:e with:parse_additive(p)];
        else if (take_word(p, @"MINUS"))
            e = [NSExpression expressionForMinusSet:e with:parse_additive(p)];
        else
            return e;
    }
}

/* ---- predicates ------------------------------------------------------------------------------- */

static NSPredicate *parse_comparison(FPParser *p)
{
    NSComparisonPredicateModifier mod = NSDirectPredicateModifier;
    BOOL none = NO;
    if (take_word(p, @"ANY") || take_word(p, @"SOME"))
        mod = NSAnyPredicateModifier;
    else if (take_word(p, @"ALL"))
        mod = NSAllPredicateModifier;
    else if (take_word(p, @"NONE"))
        mod = NSAnyPredicateModifier, none = YES;
    NSExpression *l = parse_expr(p);
    NSPredicateOperatorType op;
    skip_space(p);
    if (take(p, @"=="))
        op = NSEqualToPredicateOperatorType;
    else if (take(p, @"=>") || take(p, @">="))
        op = NSGreaterThanOrEqualToPredicateOperatorType;
    else if (take(p, @"=<") || take(p, @"<="))
        op = NSLessThanOrEqualToPredicateOperatorType;
    else if (take(p, @"!=") || take(p, @"<>"))
        op = NSNotEqualToPredicateOperatorType;
    else if (take(p, @"<"))
        op = NSLessThanPredicateOperatorType;
    else if (take(p, @">"))
        op = NSGreaterThanPredicateOperatorType;
    else if (take(p, @"="))
        op = NSEqualToPredicateOperatorType;
    else if (take_word(p, @"BETWEEN"))
        op = NSBetweenPredicateOperatorType;
    else if (take_word(p, @"IN"))
        op = NSInPredicateOperatorType;
    else if (take_word(p, @"CONTAINS"))
        op = NSContainsPredicateOperatorType;
    else if (take_word(p, @"BEGINSWITH"))
        op = NSBeginsWithPredicateOperatorType;
    else if (take_word(p, @"ENDSWITH"))
        op = NSEndsWithPredicateOperatorType;
    else if (take_word(p, @"LIKE"))
        op = NSLikePredicateOperatorType;
    else if (take_word(p, @"MATCHES"))
        op = NSMatchesPredicateOperatorType;
    else {
        parse_error(p);
        return nil;
    }
    NSComparisonPredicateOptions options = 0;
    if (peek(p, 0) == '[') {
        p->at++;
        while (p->at < p->n && peek(p, 0) != ']') {
            unichar c = peek(p, 0);
            if (c == 'c' || c == 'C')
                options |= NSCaseInsensitivePredicateOption;
            else if (c == 'd' || c == 'D')
                options |= NSDiacriticInsensitivePredicateOption;
            else if (c == 'n' || c == 'N')
                options |= NSNormalizedPredicateOption;
            else if (c != 'l' && c != 'L')
                parse_error(p);
            p->at++;
        }
        expect(p, @"]");
    }
    NSPredicate *c = [NSComparisonPredicate predicateWithLeftExpression:l
                                                       rightExpression:parse_expr(p)
                                                              modifier:mod
                                                                  type:op
                                                               options:options];
    return none ? FNonePredicate(c) : c;
}

/* Whether the parenthesis at the parser's place opens an expression, as in
 * (a + b) > 2, rather than a predicate: what follows its closing
 * parenthesis is an operator. */
static BOOL parenthesis_opens_expression(FPParser *p)
{
    NSUInteger i = p->at, depth = 0;
    unichar quote = 0;
    for (; i < p->n; i++) {
        unichar c = [p->s characterAtIndex:i];
        if (quote) {
            if (c == '\\')
                i++;
            else if (c == quote)
                quote = 0;
            continue;
        }
        if (c == '"' || c == '\'')
            quote = c;
        else if (c == '(' || c == '{' || c == '[')
            depth++;
        else if ((c == ')' || c == '}' || c == ']') && --depth == 0)
            break;
    }
    if (i >= p->n)
        return NO;
    FPParser after = *p;
    after.at = i + 1;
    skip_space(&after);
    unichar c = peek(&after, 0);
    if (c && c < 128 && strchr("=!<>+-*/.[", (int)c))
        return YES;
    NSString *w = [peek_word(&after) uppercaseString];
    return [@[ @"BETWEEN", @"IN", @"CONTAINS", @"BEGINSWITH", @"ENDSWITH", @"LIKE", @"MATCHES", @"UNION", @"INTERSECT",
               @"MINUS" ] containsObject:w];
}

static NSPredicate *parse_primary(FPParser *p)
{
    skip_space(p);
    if (peek(p, 0) == '(' && !parenthesis_opens_expression(p)) {
        p->at++;
        NSPredicate *inner = parse_or(p);
        expect(p, @")");
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

NSPredicate *FParsePredicate(NSString *format, va_list *ap, NSArray *args)
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

NSExpression *FParseExpression(NSString *format, va_list *ap, NSArray *args)
{
    if (!format)
        FRaise(NSInvalidArgumentException, @"*** +[NSExpression expressionWithFormat:]: the format is nil");
    FPParser p = {format, 0, [format length], ap, args, 0};
    NSExpression *result = parse_expr(&p);
    skip_space(&p);
    if (p.at != p.n)
        parse_error(&p);
    return result;
}
