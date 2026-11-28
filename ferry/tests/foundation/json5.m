/* JSON5 reading (freemac 1.270): the forms json5.org specifies, the option
 * that reads a text without its outer braces, and plain JSON still refusing
 * them. Hex Fiend's byte themes are JSON5. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <math.h>

static id parse(const char *text, NSJSONReadingOptions opt)
{
    NSError *e = nil;
    id v = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:text length:strlen(text)] options:opt error:&e];
    if (!v)
        printf("  error %ld\n", (long)[e code]);
    return v;
}

int main(void)
{
    @autoreleasepool {
        NSJSONReadingOptions five = NSJSONReadingJSON5Allowed;
        const char *theme = "{\n  // the dark look\n  dark: { \"null\": 0x797979, 'printable': 0x38B8C7, },\n"
                            "  /* and the light */ light: { other: \"systemGreen\", },\n}";
        NSDictionary *d = parse(theme, five);
        printf("theme: dark null %ld, printable %ld, light other %s\n", [d[@"dark"][@"null"] longValue],
               [d[@"dark"][@"printable"] longValue], [d[@"light"][@"other"] UTF8String]);
        printf("plain JSON refuses it:\n");
        printf("  %s\n", parse(theme, 0) ? "read" : "refused");

        NSArray *n = parse("[+1, .5, 5., -0x10, Infinity, -Infinity, NaN, 1e3]", five);
        printf("numbers: %g %g %g %g %g %g %s %g\n", [n[0] doubleValue], [n[1] doubleValue], [n[2] doubleValue],
               [n[3] doubleValue], [n[4] doubleValue], [n[5] doubleValue], isnan([n[6] doubleValue]) ? "nan" : "?",
               [n[7] doubleValue]);
        NSArray *s = parse("['it\\'s', \"tab\\there\", 'hex \\x41', 'line \\\ncontinued', '\\q']", five);
        for (NSString *x in s)
            printf("string: [%s]\n", [x UTF8String]);
        NSDictionary *bare = parse("a: 1, $b_2: 'two', // end\n", five | NSJSONReadingTopLevelDictionaryAssumed);
        printf("braces assumed: a %ld, $b_2 %s, %lu keys\n", [bare[@"a"] longValue], [bare[@"$b_2"] UTF8String],
               (unsigned long)[bare count]);
        NSDictionary *braced = parse("{x: 1}", five | NSJSONReadingTopLevelDictionaryAssumed);
        printf("with braces anyway: x %ld\n", [braced[@"x"] longValue]);
        printf("unclosed comment:\n");
        parse("[1 /* never closed", five);
        printf("key starting with a digit:\n");
        parse("{1a: 2}", five);
    }
    return 0;
}
