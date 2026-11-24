/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSRegularExpression (ICU's syntax, on this system's ICU),
 * NSTextCheckingResult, templates, and NSString's
 * NSRegularExpressionSearch. */
#import <Foundation/Foundation.h>

static const char *R(NSRange r)
{
    static char buf[8][32];
    static int i;
    char *b = buf[i++ & 7];
    if (r.location == NSNotFound)
        snprintf(b, 32, "{NSNotFound, %lu}", (unsigned long)r.length);
    else
        snprintf(b, 32, "{%lu, %lu}", (unsigned long)r.location, (unsigned long)r.length);
    return b;
}

static NSRegularExpression *re(NSString *p, NSRegularExpressionOptions o)
{
    NSError *e = nil;
    NSRegularExpression *x = [NSRegularExpression regularExpressionWithPattern:p options:o error:&e];
    if (!x)
        printf("pattern %s failed: %s %ld\n", [p UTF8String], [[e domain] UTF8String], (long)[e code]);
    return x;
}

static void show(NSString *pattern, NSRegularExpressionOptions o, NSString *s)
{
    NSRegularExpression *x = re(pattern, o);
    NSArray *m = [x matchesInString:s options:0 range:NSMakeRange(0, [s length])];
    printf("%-22s %lu:", [pattern UTF8String], (unsigned long)[m count]);
    for (NSTextCheckingResult *r in m)
        printf(" \"%s\"%s", [[s substringWithRange:[r range]] UTF8String], R([r range]));
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSString *s = @"John Smith 42, Jane Doe 7, and nobody 2024";
        NSRegularExpression *x = re(@"(\\w+) (\\w+) (\\d+)", 0);
        printf("pattern %s, options %lu, groups %lu\n", [[x pattern] UTF8String], (unsigned long)[x options],
               (unsigned long)[x numberOfCaptureGroups]);
        for (NSTextCheckingResult *r in [x matchesInString:s options:0 range:NSMakeRange(0, [s length])]) {
            printf("match %s type %llu ranges %lu:", R([r range]), (unsigned long long)[r resultType],
                   (unsigned long)[r numberOfRanges]);
            for (NSUInteger g = 1; g < [r numberOfRanges]; g++)
                printf(" %s", [[s substringWithRange:[r rangeAtIndex:g]] UTF8String]);
            printf("%s\n", [r regularExpression] == x ? " (same expression)" : "");
        }
        printf("number of matches %lu\n", (unsigned long)[x numberOfMatchesInString:s options:0
                                                                               range:NSMakeRange(0, [s length])]);
        printf("first in a range %s\n", R([x rangeOfFirstMatchInString:s options:0 range:NSMakeRange(5, 30)]));
        printf("none: %s, %s\n", R([re(@"xyz", 0) rangeOfFirstMatchInString:s options:0 range:NSMakeRange(0, [s length])]),
               [re(@"xyz", 0) firstMatchInString:s options:0 range:NSMakeRange(0, [s length])] ? "a result" : "nil");

        /* an optional group that didn't take part */
        NSTextCheckingResult *r = [re(@"a(b)?(c)", 0) firstMatchInString:@"xac" options:0 range:NSMakeRange(0, 3)];
        printf("optional group: %s %s %s\n", R([r rangeAtIndex:0]), R([r rangeAtIndex:1]), R([r rangeAtIndex:2]));
        /* named groups */
        r = [re(@"(?<year>\\d{4})-(?<month>\\d\\d)", 0) firstMatchInString:@"on 2026-11 we" options:0
                                                                    range:NSMakeRange(0, 13)];
        printf("named: year %s month %s\n", R([r rangeWithName:@"year"]), R([r rangeWithName:@"month"]));
        @try {
            [r rangeWithName:@"day"];
        } @catch (NSException *e) {
            printf("no such name: %s\n", [[e name] UTF8String]);
        }

        /* the options, and ICU's syntax */
        show(@"hello", NSRegularExpressionCaseInsensitive, @"Hello HELLO hello");
        show(@"^\\w+$", 0, @"one\ntwo");
        show(@"^\\w+$", NSRegularExpressionAnchorsMatchLines, @"one\ntwo");
        show(@"a.b", 0, @"a\nb a-b");
        show(@"a.b", NSRegularExpressionDotMatchesLineSeparators, @"a\nb a-b");
        show(@"a.b", NSRegularExpressionIgnoreMetacharacters, @"a.b axb");
        show(@"\\d+ # digits", NSRegularExpressionAllowCommentsAndWhitespace, @"12 ab 345");
        show(@"(?<=\\$)\\d+", 0, @"$5 and 6 and $70");
        show(@"\\bcat\\b", 0, @"cat concat cat.");
        show(@"(\\w)\\1", 0, @"aabbcd ee");
        show(@"[[:upper:]]+", 0, @"abcDEFghIJ");
        show(@"\\p{Lu}\\p{Ll}+", 0, @"Élan vital Ödön");
        show(@"x*", 0, @"axxb");
        show(@"😀+", 0, @"a😀😀b😀");
        show(@"\\N{GREEK SMALL LETTER ALPHA}", 0, @"βαγ");

        /* enumerating, stopping, completion and anchoring */
        x = re(@"\\d", 0);
        NSString *digits = @"1a23b456";
        __block int calls = 0;
        [x enumerateMatchesInString:digits
                            options:NSMatchingReportCompletion
                              range:NSMakeRange(0, [digits length])
                         usingBlock:^(NSTextCheckingResult *res, NSMatchingFlags flags, BOOL *stop) {
                           calls++;
                           if (res)
                               printf(" %s", [[digits substringWithRange:[res range]] UTF8String]);
                           else
                               printf(" (done, completed %d, hit end %d)", (flags & NSMatchingCompleted) != 0,
                                      (flags & NSMatchingHitEnd) != 0);
                         }];
        printf(" in %d calls\n", calls);
        [x enumerateMatchesInString:digits
                            options:0
                              range:NSMakeRange(0, [digits length])
                         usingBlock:^(NSTextCheckingResult *res, NSMatchingFlags flags, BOOL *stop) {
                           printf("stops after %s", [[digits substringWithRange:[res range]] UTF8String]);
                           *stop = [[digits substringWithRange:[res range]] isEqualToString:@"2"];
                           printf("%s", *stop ? "\n" : "; ");
                         }];
        printf("anchored at 2: %lu, at 1: %lu\n",
               (unsigned long)[x numberOfMatchesInString:digits options:NSMatchingAnchored range:NSMakeRange(2, 6)],
               (unsigned long)[x numberOfMatchesInString:digits options:NSMatchingAnchored range:NSMakeRange(1, 7)]);
        NSRegularExpression *start = re(@"^\\d", 0);
        printf("^ in a range: %lu, without anchoring bounds: %lu\n",
               (unsigned long)[start numberOfMatchesInString:digits options:0 range:NSMakeRange(2, 3)],
               (unsigned long)[start numberOfMatchesInString:digits options:NSMatchingWithoutAnchoringBounds
                                                       range:NSMakeRange(2, 3)]);
        NSRegularExpression *edge = re(@"\\b\\d", 0);
        printf("\\b at the range's start: %lu, with transparent bounds: %lu\n",
               (unsigned long)[edge numberOfMatchesInString:@"a1" options:0 range:NSMakeRange(1, 1)],
               (unsigned long)[edge numberOfMatchesInString:@"a1" options:NSMatchingWithTransparentBounds
                                                      range:NSMakeRange(1, 1)]);
        /* the same expression used again inside its own block */
        __block NSMutableString *nested = [NSMutableString string];
        [x enumerateMatchesInString:@"12"
                            options:0
                              range:NSMakeRange(0, 2)
                         usingBlock:^(NSTextCheckingResult *res, NSMatchingFlags flags, BOOL *stop) {
                           [nested appendFormat:@"%lu+%lu ", (unsigned long)[res range].location,
                                                (unsigned long)[x numberOfMatchesInString:@"345"
                                                                                  options:0
                                                                                    range:NSMakeRange(0, 3)]];
                         }];
        printf("nested: %s\n", [nested UTF8String]);

        /* templates */
        x = re(@"(\\w+)@(\\w+)\\.com", 0);
        NSString *mail = @"write to ann@example.com or bob@test.com";
        printf("%s\n", [[x stringByReplacingMatchesInString:mail options:0 range:NSMakeRange(0, [mail length])
                                               withTemplate:@"$2:$1 (\\$1, $0)"] UTF8String]);
        NSMutableString *m = [NSMutableString stringWithString:mail];
        NSUInteger count = [x replaceMatchesInString:m options:0 range:NSMakeRange(0, [m length]) withTemplate:@"<$1>"];
        printf("replaced %lu: %s\n", (unsigned long)count, [m UTF8String]);
        printf("%s\n", [[re(@"(a)(b)?", 0) stringByReplacingMatchesInString:@"ab a" options:0 range:NSMakeRange(0, 4)
                                                                 withTemplate:@"[$2|$12|$3]"] UTF8String]);
        printf("%s\n", [[re(@"(?<w>o+)", 0) stringByReplacingMatchesInString:@"foo boo" options:0
                                                                         range:NSMakeRange(0, 7)
                                                                  withTemplate:@"${w}${w}"] UTF8String]);
        r = [x firstMatchInString:mail options:0 range:NSMakeRange(0, [mail length])];
        NSString *shifted = [@">>>" stringByAppendingString:mail];
        printf("offset: %s, moved %s\n",
               [[x replacementStringForResult:r inString:shifted offset:3 template:@"$1"] UTF8String],
               R([[r resultByAdjustingRangesWithOffset:3] range]));
        NSRange made[2] = {{1, 3}, {NSNotFound, 0}};
        r = [NSTextCheckingResult regularExpressionCheckingResultWithRanges:made count:2 regularExpression:x];
        printf("made: %s %s, %lu ranges\n", R([r range]), R([r rangeAtIndex:1]), (unsigned long)[r numberOfRanges]);
        printf("escaped pattern: %s\n", [[NSRegularExpression escapedPatternForString:@"$1.00 (a+b)*[c]"] UTF8String]);
        printf("escaped template: %s\n", [[NSRegularExpression escapedTemplateForString:@"\\$1"] UTF8String]);
        NSString *lit = [NSRegularExpression escapedPatternForString:@"a.b(c)"];
        printf("an escaped pattern finds itself: %s\n",
               R([re(lit, 0) rangeOfFirstMatchInString:@"xa.b(c)" options:0 range:NSMakeRange(0, 7)]));

        /* patterns that don't compile */
        NSError *error = nil;
        x = [NSRegularExpression regularExpressionWithPattern:@"(unclosed" options:0 error:&error];
        printf("bad pattern: %s, %s %ld, value %s\n", x ? "made" : "nil", [[error domain] UTF8String],
               (long)[error code], [[[error userInfo] objectForKey:@"NSInvalidValue"] UTF8String]);
        printf("bad quantifier: %s\n", re(@"*a", 0) ? "made" : "nil");
        printf("equal: %d, copy is itself: %d\n", [re(@"a+", 1) isEqual:re(@"a+", 1)], [x copy] == x);

        /* NSString */
        NSString *str = @"Version 10.4.11 (build 8S2167)";
        printf("rangeOfString regex: %s\n", R([str rangeOfString:@"\\d+\\.\\d+" options:NSRegularExpressionSearch]));
        printf("case-insensitive: %s\n",
               R([str rangeOfString:@"BUILD \\w+" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch]));
        printf("anchored: %s %s\n", R([str rangeOfString:@"\\d+" options:NSRegularExpressionSearch | NSAnchoredSearch]),
               R([str rangeOfString:@"V\\w+" options:NSRegularExpressionSearch | NSAnchoredSearch]));
        printf("in a range: %s\n", R([str rangeOfString:@"\\d+" options:NSRegularExpressionSearch
                                                  range:NSMakeRange(12, 10)]));
        printf("bad pattern in a search: %s\n", R([str rangeOfString:@"(" options:NSRegularExpressionSearch]));
        printf("replace: %s\n", [[str stringByReplacingOccurrencesOfString:@"(\\d+)"
                                                                withString:@"<$1>"
                                                                   options:NSRegularExpressionSearch
                                                                     range:NSMakeRange(0, [str length])] UTF8String]);
        printf("literal replace: %s\n", [[str stringByReplacingOccurrencesOfString:@"."
                                                                        withString:@"$"
                                                                           options:0
                                                                             range:NSMakeRange(0, 15)] UTF8String]);
        NSMutableString *ms = [NSMutableString stringWithString:@"a1b22c333"];
        count = [ms replaceOccurrencesOfString:@"\\d+" withString:@"#" options:NSRegularExpressionSearch
                                         range:NSMakeRange(0, [ms length])];
        printf("mutable: %lu, %s\n", (unsigned long)count, [ms UTF8String]);
        printf("description has the pattern: %d\n", [[re(@"q+", 0) description] hasSuffix:@"q+ 0x0"]);
    }
    return 0;
}
