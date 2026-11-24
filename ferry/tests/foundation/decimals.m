/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSDecimal and its functions, NSDecimalNumber, NSDecimalNumberHandler,
 * and decimal numbers with NSNumber, NSNumberFormatter, NSScanner, keyed
 * archiving and NSJSONSerialization (freemac 1.211, Ferry 0.37.0). */
#import <Foundation/Foundation.h>
#include <stdio.h>

static NSDecimalNumber *D(NSString *s) { return [NSDecimalNumber decimalNumberWithString:s]; }

static void show(NSString *label, id value)
{
    printf("%s: %s\n", [label UTF8String], value ? [[value description] UTF8String] : "nil");
}

static const char *error_name(NSCalculationError e)
{
    switch (e) {
    case NSCalculationNoError: return "no error";
    case NSCalculationLossOfPrecision: return "loss of precision";
    case NSCalculationUnderflow: return "underflow";
    case NSCalculationOverflow: return "overflow";
    case NSCalculationDivideByZero: return "divide by zero";
    }
    return "?";
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

static NSDecimalNumberHandler *handler(NSRoundingMode mode, short scale)
{
    return [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:mode
                                                                  scale:scale
                                                       raiseOnExactness:NO
                                                        raiseOnOverflow:NO
                                                       raiseOnUnderflow:NO
                                                    raiseOnDivideByZero:NO];
}

int main(void)
{
    @autoreleasepool {
        /* exact base-10 arithmetic */
        NSDecimalNumber *tenth = D(@"0.1"), *fifth = D(@"0.2");
        show(@"0.1 + 0.2", [tenth decimalNumberByAdding:fifth]);
        show(@"0.1 + 0.2 == 0.3", @([[tenth decimalNumberByAdding:fifth] isEqual:D(@"0.3")]));
        show(@"1.10 - 0.25", [D(@"1.10") decimalNumberBySubtracting:D(@"0.25")]);
        show(@"19.99 * 3", [D(@"19.99") decimalNumberByMultiplyingBy:D(@"3")]);
        show(@"1 / 8", [D(@"1") decimalNumberByDividingBy:D(@"8")]);
        show(@"1 / 3", [D(@"1") decimalNumberByDividingBy:D(@"3")]);
        show(@"2 / 3", [D(@"2") decimalNumberByDividingBy:D(@"3")]);
        show(@"-7 / 2", [D(@"-7") decimalNumberByDividingBy:D(@"2")]);
        show(@"1.5 ^ 3", [D(@"1.5") decimalNumberByRaisingToPower:3]);
        show(@"2 ^ 100", [D(@"2") decimalNumberByRaisingToPower:100]);
        show(@"7 ^ 0", [D(@"7") decimalNumberByRaisingToPower:0]);
        show(@"12.5 x 10^3", [D(@"12.5") decimalNumberByMultiplyingByPowerOf10:3]);
        show(@"12.5 x 10^-3", [D(@"12.5") decimalNumberByMultiplyingByPowerOf10:-3]);
        show(@"big", D(@"123456789012345678901234567890.123456789"));
        show(@"38 digits", [D(@"99999999999999999999999999999999999999") decimalNumberByAdding:D(@"1")]);
        show(@"too many digits", D(@"1234567890123456789012345678901234567890123"));
        show(@"tiny", D(@"0.000000000000000000000000000000000001"));
        show(@"exponent", D(@"1.5e10"));
        show(@"negative exponent", D(@"-2.5E-3"));
        show(@"trailing zeros", D(@"1.2300"));
        show(@"leading text kept", D(@"42abc"));
        show(@"not a number", D(@"abc"));
        show(@"NaN is notANumber", @([D(@"abc") isEqual:[NSDecimalNumber notANumber]]));
        show(@"locale", [NSDecimalNumber decimalNumberWithString:@"3,75" locale:@{NSLocaleDecimalSeparator : @","}]);
        show(@"described in a locale", [D(@"3.75") descriptionWithLocale:@{NSLocaleDecimalSeparator : @","}]);
        show(@"mantissa", [NSDecimalNumber decimalNumberWithMantissa:12345 exponent:-2 isNegative:YES]);
        show(@"zero", [NSDecimalNumber zero]);
        show(@"one", [NSDecimalNumber one]);
        show(@"maximum", [NSDecimalNumber maximumDecimalNumber]);
        show(@"minimum", [NSDecimalNumber minimumDecimalNumber]);
        show(@"from a double", [[NSDecimalNumber alloc] initWithDouble:0.1]);
        show(@"from an integer", [[NSDecimalNumber alloc] initWithInteger:-9007199254740993]);
        show(@"objCType", @([D(@"1.5") objCType]));
        show(@"doubleValue", @([D(@"2.25") doubleValue]));
        show(@"intValue", @([D(@"-7.9") intValue]));
        show(@"longLongValue", @([D(@"123456789012345678") longLongValue]));
        show(@"boolValue", @([D(@"0.0") boolValue]));

        /* rounding */
        NSString *values[] = { @"2.345", @"2.355", @"-2.345", @"2.3451", @"-2.355" };
        NSRoundingMode modes[] = { NSRoundPlain, NSRoundDown, NSRoundUp, NSRoundBankers };
        const char *mode_names[] = { "plain", "down", "up", "bankers" };
        for (unsigned v = 0; v < 5; v++) {
            printf("%s:", [values[v] UTF8String]);
            for (unsigned m = 0; m < 4; m++)
                printf(" %s %s", mode_names[m],
                       [[[D(values[v]) decimalNumberByRoundingAccordingToBehavior:handler(modes[m], 2)] description] UTF8String]);
            printf("\n");
        }
        show(@"to tens", [D(@"1234.5") decimalNumberByRoundingAccordingToBehavior:handler(NSRoundPlain, -1)]);
        show(@"scale in arithmetic", [D(@"10") decimalNumberByDividingBy:D(@"3") withBehavior:handler(NSRoundUp, 4)]);
        show(@"no scale", [D(@"1.23456") decimalNumberByRoundingAccordingToBehavior:handler(NSRoundPlain, NSDecimalNoScale)]);

        /* the C functions */
        NSDecimal a = [D(@"1.25") decimalValue], b = [D(@"0.75") decimalValue], r;
        printf("NSDecimalAdd: %s, %s\n", error_name(NSDecimalAdd(&r, &a, &b, NSRoundPlain)), [NSDecimalString(&r, nil) UTF8String]);
        printf("NSDecimalSubtract: %s, %s\n", error_name(NSDecimalSubtract(&r, &b, &a, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        printf("NSDecimalMultiply: %s, %s\n", error_name(NSDecimalMultiply(&r, &a, &b, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        printf("NSDecimalDivide: %s, %s\n", error_name(NSDecimalDivide(&r, &a, &b, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        printf("NSDecimalPower: %s, %s\n", error_name(NSDecimalPower(&r, &a, 4, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        printf("NSDecimalMultiplyByPowerOf10: %s, %s\n", error_name(NSDecimalMultiplyByPowerOf10(&r, &a, 2, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        printf("NSDecimalCompare: %ld %ld %ld\n", (long)NSDecimalCompare(&a, &b), (long)NSDecimalCompare(&b, &a),
               (long)NSDecimalCompare(&a, &a));
        NSDecimal zero = [[NSDecimalNumber zero] decimalValue];
        printf("divide by zero: %s, %s\n", error_name(NSDecimalDivide(&r, &a, &zero, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        printf("NaN: %d\n", NSDecimalIsNotANumber(&r));
        NSDecimal max = [[NSDecimalNumber maximumDecimalNumber] decimalValue];
        printf("overflow: %s\n", error_name(NSDecimalMultiply(&r, &max, &max, NSRoundPlain)));
        NSDecimal small = [D(@"1e-100") decimalValue];
        printf("underflow: %s, %s\n", error_name(NSDecimalMultiply(&r, &small, &small, NSRoundPlain)),
               [NSDecimalString(&r, nil) UTF8String]);
        NSDecimal third = [[D(@"1") decimalNumberByDividingBy:D(@"3")] decimalValue], one = [[NSDecimalNumber one] decimalValue];
        printf("loss of precision: %s\n", error_name(NSDecimalAdd(&r, &third, &max, NSRoundPlain)));
        NSDecimal rounded;
        NSDecimalRound(&rounded, &third, 3, NSRoundUp);
        printf("NSDecimalRound: %s\n", [NSDecimalString(&rounded, nil) UTF8String]);
        NSDecimal n1 = [D(@"1.5") decimalValue], n2 = [D(@"200") decimalValue];
        printf("NSDecimalNormalize: %s, exponents %d %d, %s %s\n", error_name(NSDecimalNormalize(&n1, &n2, NSRoundPlain)),
               n1._exponent, n2._exponent, [NSDecimalString(&n1, nil) UTF8String], [NSDecimalString(&n2, nil) UTF8String]);
        NSDecimal copy;
        NSDecimalCopy(&copy, &one);
        NSDecimalCompact(&copy);
        printf("NSDecimalCopy: %s, length %u, compact %u\n", [NSDecimalString(&copy, nil) UTF8String], copy._length,
               copy._isCompact);

        /* exceptions */
        raises(@"divide by zero raises", ^{
            [D(@"1") decimalNumberByDividingBy:[NSDecimalNumber zero]];
        });
        raises(@"overflow raises", ^{
            [[NSDecimalNumber maximumDecimalNumber] decimalNumberByMultiplyingBy:D(@"10")];
        });
        raises(@"underflow raises", ^{
            [D(@"1e-100") decimalNumberByMultiplyingBy:D(@"1e-100")];
        });
        raises(@"loss of precision is quiet", ^{
            [D(@"1") decimalNumberByDividingBy:D(@"3")];
        });
        NSDecimalNumberHandler *strict = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain
                                                                                                scale:2
                                                                                     raiseOnExactness:YES
                                                                                      raiseOnOverflow:YES
                                                                                     raiseOnUnderflow:YES
                                                                                  raiseOnDivideByZero:YES];
        raises(@"exactness raises when asked", ^{
            [D(@"1") decimalNumberByDividingBy:D(@"3") withBehavior:strict];
        });
        show(@"exact enough", [D(@"1") decimalNumberByDividingBy:D(@"4") withBehavior:strict]);
        show(@"quiet divide by zero", [D(@"1") decimalNumberByDividingBy:[NSDecimalNumber zero] withBehavior:handler(NSRoundPlain, 2)]);
        [NSDecimalNumber setDefaultBehavior:handler(NSRoundDown, 1)];
        show(@"a new default behaviour", [D(@"2") decimalNumberByDividingBy:D(@"3")]);
        [NSDecimalNumber setDefaultBehavior:[NSDecimalNumberHandler defaultDecimalNumberHandler]];
        show(@"the default again", [D(@"2") decimalNumberByDividingBy:D(@"3")]);

        /* with NSNumber */
        show(@"equal to an NSNumber", @([D(@"2.5") isEqual:@2.5]));
        show(@"an NSNumber equal to it", @([@2.5 isEqual:D(@"2.5")]));
        show(@"integer equal", @([@3 isEqualToNumber:D(@"3")]));
        show(@"compare with an NSNumber", @([D(@"0.1") compare:@0.2]));
        show(@"an NSNumber compared", @([@1 compare:D(@"0.5")]));
        show(@"same hash", @([D(@"3") hash] == [@3 hash]));
        NSDecimal fromNumber = [@0.1 decimalValue];
        printf("NSNumber decimalValue: %s\n", [NSDecimalString(&fromNumber, nil) UTF8String]);
        fromNumber = [@(-123456789012345678LL) decimalValue];
        printf("an integer's decimalValue: %s\n", [NSDecimalString(&fromNumber, nil) UTF8String]);
        NSArray *sorted = [@[ D(@"2.5"), @1, D(@"-0.5"), @2 ] sortedArrayUsingSelector:@selector(compare:)];
        show(@"sorted", [sorted componentsJoinedByString:@" "]);
        show(@"sum by key-value coding", [@[ D(@"0.1"), D(@"0.2"), D(@"0.3") ] valueForKeyPath:@"@sum.self"]);

        /* NSScanner */
        NSScanner *scanner = [NSScanner scannerWithString:@"  12.75 and -0.5e2"];
        NSDecimal scanned;
        BOOL ok = [scanner scanDecimal:&scanned];
        printf("scanned %d: %s\n", ok, [NSDecimalString(&scanned, nil) UTF8String]);
        [scanner scanString:@"and" intoString:NULL];
        ok = [scanner scanDecimal:&scanned];
        printf("scanned %d: %s, at end %d\n", ok, [NSDecimalString(&scanned, nil) UTF8String], [scanner isAtEnd]);
        printf("nothing to scan: %d\n", [[NSScanner scannerWithString:@"x"] scanDecimal:&scanned]);

        /* NSNumberFormatter */
        NSNumberFormatter *f = [NSNumberFormatter new];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        f.numberStyle = NSNumberFormatterDecimalStyle;
        f.maximumFractionDigits = 20;
        show(@"formatted", [f stringFromNumber:D(@"12345678901234567890.123456789")]);
        f.maximumFractionDigits = 2;
        show(@"formatted and rounded", [f stringFromNumber:D(@"0.125")]);
        f.generatesDecimalNumbers = YES;
        NSNumber *parsed = [f numberFromString:@"1,234.10"];
        show(@"parsed", parsed);
        show(@"parsed class", @([parsed isKindOfClass:[NSDecimalNumber class]]));
        show(@"parsed exactly", [f numberFromString:@"0.1"]);
        f.generatesDecimalNumbers = NO;
        show(@"parsed as a double", @([[f numberFromString:@"0.1"] isKindOfClass:[NSDecimalNumber class]]));

        /* keyed archiving */
        NSDecimalNumber *price = D(@"1234567890.0987654321");
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@[ price, handler(NSRoundBankers, 3) ]
                                             requiringSecureCoding:YES
                                                             error:NULL];
        NSArray *back = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[NSArray class],
                                                                         [NSDecimalNumber class],
                                                                         [NSDecimalNumberHandler class], nil]
                                                             fromData:data
                                                                error:NULL];
        show(@"archived", back[0]);
        show(@"archived class", @([back[0] isKindOfClass:[NSDecimalNumber class]]));
        show(@"archived handler", @([back[1] roundingMode] == NSRoundBankers && [back[1] scale] == 3));

        /* JSON */
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"price" : price, @"tiny" : D(@"0.000001") }
                                                       options:NSJSONWritingSortedKeys
                                                         error:NULL];
        show(@"JSON", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
        show(@"NaN is valid JSON", @([NSJSONSerialization isValidJSONObject:@[ [NSDecimalNumber notANumber] ]]));
        raises(@"NaN in JSON raises", ^{
            [NSJSONSerialization dataWithJSONObject:@[ [NSDecimalNumber notANumber] ] options:0 error:NULL];
        });
    }
    return 0;
}
