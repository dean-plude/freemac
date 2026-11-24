/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSJSONSerialization: reading objects, arrays, strings with every escape
 * and surrogate pairs, numbers (integers, large integers, decimals,
 * exponents), true, false and null; the mutability options; fragments;
 * UTF-16 and UTF-32 text; mistakes reported as errors with their place;
 * writing compactly, pretty-printed and with sorted keys, slashes escaped
 * or not, fragments; isValidJSONObject:; and what raises. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static NSString *text(NSData *d) { return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease]; }

static id parse(const char *json, NSJSONReadingOptions opt)
{
    NSError *err = nil;
    id v = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:json length:strlen(json)] options:opt
                                             error:&err];
    if (!v)
        printf("  %.24s -> error %ld: %s (at %s)\n", json, (long)[err code],
               [[err userInfo][@"NSDebugDescription"] UTF8String],
               [[[err userInfo][@"NSJSONSerializationErrorIndex"] description] UTF8String]);
    return v;
}

static void show(id v)
{
    NSData *d = [NSJSONSerialization dataWithJSONObject:v options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                  error:NULL];
    printf("%s", [text(d) UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        printf("reading\n");
        id v = parse(" { \"name\" : \"Ferry\", \"version\" : 14, \"tags\" : [\"mac\", \"linux\"], \"ok\" : true, "
                     "\"none\" : null, \"ratio\" : 0.25, \"neg\" : -12, \"big\" : 18446744073709551615, "
                     "\"huge\" : 1e300, \"exp\" : 2.5E-3, \"zero\" : 0, \"no\" : false } ",
                     0);
        printf("  ");
        show(v);
        printf("\n  version is an integer: %s, ratio %g, big %llu, ok is a boolean: %s, none is NSNull: %s\n",
               strcmp([v[@"version"] objCType], "q") == 0 ? "yes" : "no", [v[@"ratio"] doubleValue],
               [v[@"big"] unsignedLongLongValue], v[@"ok"] == (id)kCFBooleanTrue ? "yes" : "no",
               v[@"none"] == [NSNull null] ? "yes" : "no");
        printf("  mutable: dictionary %d, array %d\n", [v isKindOfClass:[NSMutableDictionary class]],
               [v[@"tags"] isKindOfClass:[NSMutableArray class]]);
        id s = parse("[\"q\\\"b\\\\s\\/n\\nt\\tr\\rb\\bf\\f\", \"\\u00e9\\u4e2d\", \"\\ud83d\\ude00\", \"caf\xc3\xa9\"]", 0);
        for (NSString *e in s) {
            printf("  string of %lu characters:", (unsigned long)[e length]);
            for (NSUInteger i = 0; i < [e length]; i++)
                printf(" %04x", [e characterAtIndex:i]);
            printf("\n");
        }

        id m = parse("{\"list\": [1, {\"inner\": \"x\"}], \"word\": \"leaf\"}", NSJSONReadingMutableContainers);
        [m[@"list"] addObject:@3];
        [m[@"list"][1] setObject:@"y" forKey:@"added"];
        [m setObject:@"new" forKey:@"key"];
        printf("  mutable containers (%d, %d): ", [m isKindOfClass:[NSMutableDictionary class]],
               [m[@"list"] isKindOfClass:[NSMutableArray class]]);
        show(m);
        printf("\n");
        id ml = parse("[\"leaf\"]", NSJSONReadingMutableLeaves);
        [ml[0] appendString:@"y"];
        printf("  mutable leaves: %s\n", [ml[0] UTF8String]);

        printf("  fragments: ");
        show(parse("\"just a string\"", NSJSONReadingFragmentsAllowed));
        printf(" ");
        show(parse(" 42 ", NSJSONReadingFragmentsAllowed));
        printf(" ");
        show(parse("null", NSJSONReadingFragmentsAllowed));
        printf("\n");

        const unichar u16[] = {0xfeff, '[', '"', 0xe9, '"', ',', '1', ']'};
        NSMutableData *le = [NSMutableData data], *be = [NSMutableData data], *be32 = [NSMutableData data];
        for (unsigned i = 0; i < 8; i++) {
            uint8_t lo = u16[i] & 0xff, hi = u16[i] >> 8;
            [le appendBytes:&lo length:1];
            [le appendBytes:&hi length:1];
            if (i) {
                [be appendBytes:&hi length:1];
                [be appendBytes:&lo length:1];
                uint8_t z = 0;
                [be32 appendBytes:&z length:1];
                [be32 appendBytes:&z length:1];
                [be32 appendBytes:&hi length:1];
                [be32 appendBytes:&lo length:1];
            }
        }
        printf("  UTF-16LE with a byte order mark: ");
        show([NSJSONSerialization JSONObjectWithData:le options:0 error:NULL]);
        printf(", UTF-16BE: ");
        show([NSJSONSerialization JSONObjectWithData:be options:0 error:NULL]);
        printf(", UTF-32BE: ");
        show([NSJSONSerialization JSONObjectWithData:be32 options:0 error:NULL]);
        printf("\n");

        printf("mistakes\n");
        const char *bad[] = {"", "   ", "\"fragment\"", "[1, 2", "[1 2]", "[1,]", "{\"a\" 1}", "{\"a\":1,}", "{1:2}",
                             "[01]", "[1.]", "[1e]", "[-]", "[tru]", "[\"\\x\"]", "[\"\\ud800\"]", "[\"a\nb\"]",
                             "[\"open]", "[1] x", "{\"a\":\n  [1,\n   nope]}", "[1e999]"};
        for (unsigned i = 0; i < sizeof bad / sizeof bad[0]; i++)
            parse(bad[i], 0);
        NSMutableString *deep = [NSMutableString string];
        for (int i = 0; i < 600; i++)
            [deep appendString:@"["];
        parse([deep UTF8String], 0);

        printf("writing\n");
        NSDictionary *obj = @{
            @"name" : @"Ferry \"boat\"",
            @"path" : @"/usr/lib/ferry",
            @"list" : @[ @1, @2.5, @-3, @YES, @NO, [NSNull null], @"tab\there", @"\x01" ],
            @"empty" : @[],
            @"nothing" : @{},
            @"nested" : @{@"b" : @"2", @"a" : @[ @{@"deep" : @1e-7} ]},
            @"unicode" : @"caf\u00e9 \u4e2d",
            @"numbers" : @[ @0.1, @(1.0 / 3), @1e100, @123456789012345678LL, @(UINT64_MAX) ],
        };
        NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys error:NULL];
        printf("  %s\n", [text(d) UTF8String]);
        d = [NSJSONSerialization dataWithJSONObject:obj
                                            options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted |
                                                    NSJSONWritingWithoutEscapingSlashes
                                              error:NULL];
        printf("%s\n", [text(d) UTF8String]);
        id back = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
        printf("  reads back equal: %s\n", [back isEqual:obj] ? "yes" : "no");
        d = [NSJSONSerialization dataWithJSONObject:@[ @"a/b" ] options:0 error:NULL];
        printf("  %s\n", [text(d) UTF8String]);
        d = [NSJSONSerialization dataWithJSONObject:@"alone" options:NSJSONWritingFragmentsAllowed error:NULL];
        printf("  fragment: %s, a float: ", [text(d) UTF8String]);
        show(@0.1f);
        printf("\n");

        printf("  valid: %d %d %d %d %d %d\n", [NSJSONSerialization isValidJSONObject:obj],
               [NSJSONSerialization isValidJSONObject:@"string"],
               [NSJSONSerialization isValidJSONObject:@[ [NSDate date] ]],
               [NSJSONSerialization isValidJSONObject:@{@1 : @2}],
               [NSJSONSerialization isValidJSONObject:@[ @(NAN) ]],
               [NSJSONSerialization isValidJSONObject:@[ @{@"k" : @[ [NSNull null] ]} ]]);
        id raising[] = {@[ [NSDate dateWithTimeIntervalSince1970:0] ], @"top", @[ @(INFINITY) ], @{@1 : @"x"}};
        for (unsigned i = 0; i < 4; i++) {
            @try {
                [NSJSONSerialization dataWithJSONObject:raising[i] options:0 error:NULL];
                printf("  no exception\n");
            } @catch (NSException *e) {
                printf("  %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
            }
        }
    }
    return 0;
}
