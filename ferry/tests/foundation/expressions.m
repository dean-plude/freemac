/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSExpression in its forms, the built-in functions, NSComparisonPredicate,
 * MATCHES and predicateWithSubstitutionVariables: (freemac 1.211, Ferry 0.37.0). */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface Dish : NSObject
@property (copy) NSString *name;
@property (strong) NSNumber *price;
@property (strong) NSArray *tags;
@end
@implementation Dish
- (NSNumber *)doubled { return @([self.price doubleValue] * 2); }
- (NSString *)greet:(NSString *)who { return [NSString stringWithFormat:@"%@ greets %@", self.name, who]; }
@end

static Dish *dish(NSString *name, double price, NSArray *tags)
{
    Dish *d = [Dish new];
    d.name = name;
    d.price = @(price);
    d.tags = tags;
    return d;
}

static void show(NSString *label, id value)
{
    printf("%s: %s\n", [label UTF8String], [[value description] UTF8String]);
}

static void eval(NSString *format, id object)
{
    NSExpression *e = [NSExpression expressionWithFormat:format];
    id v = [e expressionValueWithObject:object context:nil];
    printf("%s => %s (type %ld, %s)\n", [format UTF8String], v ? [[v description] UTF8String] : "nil",
           (long)[e expressionType], [[e description] UTF8String]);
}

static void raises(NSString *label, void (^block)(void))
{
    @try {
        block();
        printf("%s: no exception\n", [label UTF8String]);
    } @catch (NSException *x) {
        printf("%s: %s\n", [label UTF8String], [[x name] UTF8String]);
    }
}

int main(void)
{
    @autoreleasepool {
        Dish *tart = dish(@"tart", 4.5, @[ @"sweet", @"baked" ]);
        NSArray *nums = @[ @1, @2, @2, @3, @7 ];

        /* the forms */
        NSExpression *c = [NSExpression expressionForConstantValue:@42];
        show(@"constant", @([c expressionType]));
        show(@"constant value", [c constantValue]);
        show(@"self", [[NSExpression expressionForEvaluatedObject] expressionValueWithObject:@"me" context:nil]);
        NSExpression *kp = [NSExpression expressionForKeyPath:@"name"];
        show(@"keypath", [kp keyPath]);
        show(@"keypath value", [kp expressionValueWithObject:tart context:nil]);
        NSExpression *v = [NSExpression expressionForVariable:@"x"];
        show(@"variable", [v variable]);
        NSMutableDictionary *ctx = [@{ @"x" : @5 } mutableCopy];
        show(@"variable value", [v expressionValueWithObject:nil context:ctx]);
        show(@"description", [NSExpression expressionForKeyPath:@"price"]);
        show(@"variable description", v);

        /* format strings */
        eval(@"1 + 2 * 3", nil);
        eval(@"(1 + 2) * 3", nil);
        eval(@"2 ** 3 ** 2", nil);
        eval(@"-4 + 10", nil);
        eval(@"10 / 4", nil);
        eval(@"price * 2", tart);
        eval(@"name", tart);
        eval(@"SELF", @"itself");
        eval(@"0x1F + 0b101 + 0o17", nil);
        eval(@"sum:({1, 2, 3.5})", nil);
        eval(@"count:(tags)", tart);
        eval(@"uppercase:(name)", tart);
        eval(@"lowercase:('ABC')", nil);
        eval(@"length:('hello')", nil);
        eval(@"sqrt:(16)", nil);
        eval(@"abs:(-3)", nil);
        eval(@"ceiling:(2.1)", nil);
        eval(@"floor:(2.9)", nil);
        eval(@"trunc:(-2.9)", nil);
        eval(@"modulus:by:(17, 5)", nil);
        eval(@"raise:toPower:(2, 10)", nil);
        eval(@"log:(1000)", nil);
        eval(@"ln:(1)", nil);
        eval(@"exp:(0)", nil);
        eval(@"bitwiseAnd:with:(12, 10)", nil);
        eval(@"bitwiseOr:with:(12, 10)", nil);
        eval(@"bitwiseXor:with:(12, 10)", nil);
        eval(@"leftshift:by:(1, 4)", nil);
        eval(@"rightshift:by:(64, 2)", nil);
        eval(@"onesComplement:(0)", nil);
        eval(@"tags[FIRST]", tart);
        eval(@"tags[LAST]", tart);
        eval(@"tags[SIZE]", tart);
        eval(@"tags[0]", tart);
        eval(@"FUNCTION(SELF, 'greet:', 'Ana')", tart);
        eval(@"FUNCTION(SELF, 'doubled')", tart);
        eval(@"TERNARY(price > 4, 'dear', 'cheap')", tart);
        eval(@"TERNARY(price > 9, 'dear', 'cheap')", tart);
        eval(@"CAST('3.25', 'NSNumber')", nil);
        eval(@"CAST(0, 'NSDate')", nil);
        eval(@"SUBQUERY(tags, $t, $t BEGINSWITH 's')", tart);
        eval(@"SUBQUERY(tags, $t, $t BEGINSWITH 's').@count", tart);
        eval(@"{1, 'two', name}", tart);

        /* aggregates over an array */
        NSString *stats[] = { @"sum:", @"count:", @"min:", @"max:", @"average:", @"median:", @"mode:", @"stddev:" };
        for (unsigned i = 0; i < sizeof stats / sizeof *stats; i++) {
            NSExpression *f = [NSExpression expressionForFunction:stats[i]
                                                        arguments:@[ [NSExpression expressionForConstantValue:nums] ]];
            printf("%s %s\n", [stats[i] UTF8String], [[[f expressionValueWithObject:nil context:nil] description] UTF8String]);
        }
        NSExpression *fn = [NSExpression expressionForFunction:@"add:to:"
                                                     arguments:@[ [NSExpression expressionForKeyPath:@"price"],
                                                                  [NSExpression expressionForConstantValue:@1] ]];
        show(@"function", [fn function]);
        show(@"function arguments", @([[fn arguments] count]));
        show(@"function value", [fn expressionValueWithObject:tart context:nil]);
        show(@"function description", fn);
        NSExpression *random = [NSExpression expressionForFunction:@"random" arguments:@[]];
        double r = [[random expressionValueWithObject:nil context:nil] doubleValue];
        show(@"random in [0, 1)", @(r >= 0 && r < 1));
        NSDate *now = [[NSExpression expressionForFunction:@"now" arguments:@[]] expressionValueWithObject:nil context:nil];
        show(@"now is a date", @([now isKindOfClass:[NSDate class]] && fabs([now timeIntervalSinceNow]) < 5));
        NSExpression *target = [NSExpression expressionForFunction:[NSExpression expressionForEvaluatedObject]
                                                      selectorName:@"greet:"
                                                         arguments:@[ [NSExpression expressionForConstantValue:@"Bo"] ]];
        show(@"function on a target", [target expressionValueWithObject:tart context:nil]);
        show(@"its operand", @([[target operand] expressionType]));

        /* sets */
        NSExpression *a = [NSExpression expressionForConstantValue:[NSSet setWithObjects:@1, @2, @3, nil]];
        NSExpression *b = [NSExpression expressionForConstantValue:@[ @2, @3, @4 ]];
        show(@"union", [[[[NSExpression expressionForUnionSet:a with:b] expressionValueWithObject:nil context:nil]
                           allObjects] sortedArrayUsingSelector:@selector(compare:)]);
        show(@"intersect", [[[[NSExpression expressionForIntersectSet:a with:b] expressionValueWithObject:nil context:nil]
                               allObjects] sortedArrayUsingSelector:@selector(compare:)]);
        show(@"minus", [[[[NSExpression expressionForMinusSet:a with:b] expressionValueWithObject:nil context:nil]
                           allObjects] sortedArrayUsingSelector:@selector(compare:)]);
        NSExpression *agg = [NSExpression expressionForAggregate:@[ [NSExpression expressionForConstantValue:@1],
                                                                    [NSExpression expressionForKeyPath:@"price"] ]];
        show(@"aggregate", [agg expressionValueWithObject:tart context:nil]);
        show(@"aggregate type", @([agg expressionType]));

        /* blocks, conditionals and subqueries built by hand */
        NSExpression *blk = [NSExpression expressionForBlock:^id(id object, NSArray *args, NSMutableDictionary *context) {
            return @([args[0] intValue] + [[object price] intValue]);
        } arguments:@[ [NSExpression expressionForConstantValue:@10] ]];
        show(@"block", [blk expressionValueWithObject:tart context:nil]);
        show(@"block type", @([blk expressionType]));
        NSExpression *cond = [NSExpression expressionForConditional:[NSPredicate predicateWithFormat:@"price < 5"]
                                                     trueExpression:[NSExpression expressionForConstantValue:@"yes"]
                                                    falseExpression:[NSExpression expressionForConstantValue:@"no"]];
        show(@"conditional", [cond expressionValueWithObject:tart context:nil]);
        show(@"conditional description", cond);
        NSExpression *sub = [NSExpression expressionForSubquery:[NSExpression expressionForKeyPath:@"tags"]
                                          usingIteratorVariable:@"t"
                                                      predicate:[NSPredicate predicateWithFormat:@"$t CONTAINS 'a'"]];
        show(@"subquery", [sub expressionValueWithObject:tart context:nil]);
        show(@"subquery description", sub);
        show(@"any key", @([[NSExpression expressionForAnyKey] expressionType]));
        show(@"format with arguments", [NSExpression expressionWithFormat:@"%K + %@", @"price", @3]);
        show(@"format with an array",
             [[NSExpression expressionWithFormat:@"%@ * %@" argumentArray:@[ @6, @7 ]] expressionValueWithObject:nil
                                                                                                         context:nil]);

        /* comparison predicates built by hand */
        NSComparisonPredicate *cp =
            (NSComparisonPredicate *)[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"name"]
                                                                        rightExpression:[NSExpression expressionForConstantValue:@"TA"]
                                                                               modifier:NSDirectPredicateModifier
                                                                                   type:NSBeginsWithPredicateOperatorType
                                                                                options:NSCaseInsensitivePredicateOption];
        show(@"built", cp);
        show(@"built evaluates", @([cp evaluateWithObject:tart]));
        show(@"operator", @([cp predicateOperatorType]));
        show(@"options", @([cp options]));
        NSComparisonPredicate *parsed = (NSComparisonPredicate *)[NSPredicate predicateWithFormat:@"ANY tags == 'sweet'"];
        show(@"parsed class", @([parsed isKindOfClass:[NSComparisonPredicate class]]));
        show(@"parsed modifier", @([parsed comparisonPredicateModifier]));
        show(@"parsed left", [parsed leftExpression]);
        show(@"parsed left type", @([[parsed leftExpression] expressionType]));
        show(@"parsed right", [[parsed rightExpression] constantValue]);
        show(@"parsed evaluates", @([parsed evaluateWithObject:tart]));
        NSPredicate *custom = [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"name"]
                                                                 rightExpression:[NSExpression expressionForConstantValue:@"tart"]
                                                                  customSelector:@selector(isEqualToString:)];
        show(@"custom selector", @([custom evaluateWithObject:tart]));
        show(@"arithmetic in a predicate", @([[NSPredicate predicateWithFormat:@"price * 2 == 9"] evaluateWithObject:tart]));
        show(@"function in a predicate",
             @([[NSPredicate predicateWithFormat:@"uppercase:(name) == 'TART'"] evaluateWithObject:tart]));
        show(@"subquery in a predicate",
             @([[NSPredicate predicateWithFormat:@"SUBQUERY(tags, $t, $t ENDSWITH 'd').@count == 1"] evaluateWithObject:tart]));
        show(@"subquery predicate format",
             [NSPredicate predicateWithFormat:@"SUBQUERY(tags, $t, $t ENDSWITH 'd').@count == 1"]);

        /* MATCHES */
        NSString *patterns[] = { @"t.*t", @"ta", @"[a-z]+", @"T.RT", @"\\w{4}" };
        for (unsigned i = 0; i < sizeof patterns / sizeof *patterns; i++) {
            NSPredicate *p = [NSPredicate predicateWithFormat:@"name MATCHES %@", patterns[i]];
            NSPredicate *pc = [NSPredicate predicateWithFormat:@"name MATCHES[c] %@", patterns[i]];
            printf("%s: %d, case-insensitively %d\n", [[p predicateFormat] UTF8String], [p evaluateWithObject:tart],
                   [pc evaluateWithObject:tart]);
        }
        show(@"MATCHES with an accent",
             @([[NSPredicate predicateWithFormat:@"SELF MATCHES[d] 'creme'"] evaluateWithObject:@"crème"]));
        show(@"MATCHES on several lines",
             @([[NSPredicate predicateWithFormat:@"SELF MATCHES 'a.b'"] evaluateWithObject:@"a\nb"]));
        raises(@"a bad pattern", ^{
            [[NSPredicate predicateWithFormat:@"SELF MATCHES '(unclosed'"] evaluateWithObject:@"x"];
        });
        NSArray *dishes = @[ tart, dish(@"pie", 3, @[ @"sweet" ]), dish(@"soup", 5, @[ @"salty" ]) ];
        show(@"filtered by MATCHES",
             [[dishes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name MATCHES '^[ps].*'"]]
                 valueForKey:@"name"]);

        /* substitution variables */
        NSPredicate *template = [NSPredicate predicateWithFormat:@"price > $low AND name BEGINSWITH $start"];
        NSPredicate *filled = [template predicateWithSubstitutionVariables:@{ @"low" : @4, @"start" : @"t" }];
        show(@"template", template);
        show(@"substituted", filled);
        show(@"substituted evaluates", @([filled evaluateWithObject:tart]));
        show(@"evaluated with variables",
             @([template evaluateWithObject:tart substitutionVariables:@{ @"low" : @5, @"start" : @"t" }]));
        raises(@"a missing variable", ^{
            [template predicateWithSubstitutionVariables:@{ @"low" : @1 }];
        });
        raises(@"an unknown function", ^{
            [NSExpression expressionForFunction:@"nosuch:" arguments:@[]];
        });
        raises(@"a variable without a context", ^{
            [[NSExpression expressionForVariable:@"q"] expressionValueWithObject:nil context:nil];
        });
        raises(@"a bad expression", ^{
            [NSExpression expressionWithFormat:@"1 +"];
        });

        /* copying, equality and archiving */
        NSExpression *e1 = [NSExpression expressionWithFormat:@"price + 1"];
        NSExpression *e2 = [NSExpression expressionWithFormat:@"price + 1"];
        show(@"equal", @([e1 isEqual:e2] && [e1 hash] == [e2 hash]));
        show(@"copy equal", @([[e1 copy] isEqual:e1]));
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[NSPredicate predicateWithFormat:@"price * 2 > 5"]
                                             requiringSecureCoding:NO
                                                             error:NULL];
        NSPredicate *back = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        show(@"archived predicate", back);
        show(@"archived evaluates", @([back evaluateWithObject:tart]));
    }
    return 0;
}
