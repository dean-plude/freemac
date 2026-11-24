/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSScanner: numbers (decimal, hexadecimal, floating point,
 * too big), words, character sets, scanning up to something, case,
 * skipped characters and the scan location. */
#import <Foundation/Foundation.h>

int main(void)
{
    @autoreleasepool {
        NSScanner *s = [NSScanner scannerWithString:@"  width = 640, height=-480 ;  scale 1.5e2 x"];
        NSString *word = nil;
        int i = 0;
        printf("defaults: case sensitive %d, skips spaces %d, location %lu\n", [s caseSensitive],
               [[s charactersToBeSkipped] characterIsMember:' '], (unsigned long)[s scanLocation]);
        printf("letters: %d %s, location %lu\n",
               [s scanCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&word], [word UTF8String],
               (unsigned long)[s scanLocation]);
        printf("int instead of '=': %d, location %lu\n", [s scanInt:&i], (unsigned long)[s scanLocation]);
        printf("'=': %d\n", [s scanString:@"=" intoString:NULL]);
        printf("int: %d %d\n", [s scanInt:&i], i);
        printf("up to height: %d \"%s\"\n", [s scanUpToString:@"HEIGHT" intoString:&word], [word UTF8String]);
        printf("HEIGHT, case-insensitively: %d \"%s\"\n", [s scanString:@"HEIGHT" intoString:&word], [word UTF8String]);
        [s scanString:@"=" intoString:NULL];
        NSInteger n = 0;
        printf("negative: %d %ld\n", [s scanInteger:&n], (long)n);
        printf("up to a letter: %d \"%s\"\n",
               [s scanUpToCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&word], [word UTF8String]);
        [s scanString:@"scale" intoString:NULL];
        double d = 0;
        printf("double: %d %g\n", [s scanDouble:&d], d);
        printf("at end: %d; x: %d; at end: %d\n", [s isAtEnd], [s scanString:@"x" intoString:NULL], [s isAtEnd]);
        printf("past the end: %d %d\n", [s scanInt:&i], [s scanUpToString:@"z" intoString:NULL]);

        s = [NSScanner scannerWithString:@"Hello hello"];
        [s setCaseSensitive:YES];
        printf("case-sensitive: %d %d\n", [s scanString:@"hello" intoString:NULL], [s scanString:@"Hello" intoString:NULL]);
        printf("up to, case-sensitive: %d \"%s\"\n", [s scanUpToString:@"HELLO" intoString:&word], [word UTF8String]);

        /* numbers */
        const char *ints[] = {"42", "+7", "-0", "2147483648 next", "-99999999999", "12abc", "abc", "- 3", NULL};
        for (int k = 0; ints[k]; k++) {
            s = [NSScanner scannerWithString:[NSString stringWithUTF8String:ints[k]]];
            i = 12345;
            BOOL ok = [s scanInt:&i];
            printf("scanInt \"%s\": %d %d, location %lu\n", ints[k], ok, i, (unsigned long)[s scanLocation]);
        }
        long long ll;
        s = [NSScanner scannerWithString:@"9223372036854775808 -9223372036854775808"];
        [s scanLongLong:&ll];
        printf("long long too big: %lld,", ll);
        [s scanLongLong:&ll];
        printf(" smallest: %lld\n", ll);
        unsigned long long ull;
        s = [NSScanner scannerWithString:@"18446744073709551615 18446744073709551616"];
        [s scanUnsignedLongLong:&ull];
        printf("unsigned: %llu,", ull);
        [s scanUnsignedLongLong:&ull];
        printf(" too big: %llu\n", ull);
        const char *hexes[] = {"ff", "0x1F", "0XaB rest", "0x", "0xg", "100000000", "zz", NULL};
        for (int k = 0; hexes[k]; k++) {
            unsigned u = 7;
            s = [NSScanner scannerWithString:[NSString stringWithUTF8String:hexes[k]]];
            BOOL ok = [s scanHexInt:&u];
            printf("scanHexInt \"%s\": %d %u (0x%x), location %lu\n", hexes[k], ok, u, u, (unsigned long)[s scanLocation]);
        }
        s = [NSScanner scannerWithString:@"0xDEADBEEFCAFE"];
        [s scanHexLongLong:&ull];
        printf("hex long long: %llx\n", ull);
        const char *reals[] = {"3.25", "-.5", "7.", "1e3", "2.5E-2x", "1e", "1e+", ".", "-", "+4.0e+1", "6,5", NULL};
        for (int k = 0; reals[k]; k++) {
            s = [NSScanner scannerWithString:[NSString stringWithUTF8String:reals[k]]];
            d = -1;
            BOOL ok = [s scanDouble:&d];
            printf("scanDouble \"%s\": %d %g, location %lu\n", reals[k], ok, d, (unsigned long)[s scanLocation]);
        }
        float f = 0;
        s = [NSScanner scannerWithString:@"0.1"];
        printf("float: %d %.7g\n", [s scanFloat:&f], f);
        s = [NSScanner scannerWithString:@"0x1.8p3 1A -0x10"];
        printf("hex double: %d %g", [s scanHexDouble:&d], d);
        printf(", %d %g", [s scanHexDouble:&d], d);
        printf(", %d %g\n", [s scanHexDouble:&d], d);
        s = [NSScanner scannerWithString:@"6,5"];
        [s setLocale:@{@"NSDecimalSeparator" : @","}];
        printf("with a comma for a separator: %d %g\n", [s scanDouble:&d], d);

        /* skipped characters and the location */
        s = [NSScanner scannerWithString:@"--a--b"];
        [s setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"-"]];
        printf("skipping dashes: %d \"%s\"", [s scanUpToString:@"-" intoString:&word], [word UTF8String]);
        printf(" then %d \"%s\"\n", [s scanCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&word],
               [word UTF8String]);
        s = [NSScanner scannerWithString:@"  7"];
        [s setCharactersToBeSkipped:nil];
        printf("skipping nothing: %d", [s scanInt:&i]);
        [s setScanLocation:2];
        printf(", from 2: %d %d\n", [s scanInt:&i], i);
        @try {
            [s setScanLocation:10];
        } @catch (NSException *e) {
            printf("location past the end: %s\n", [[e name] UTF8String]);
        }
        s = [NSScanner scannerWithString:@"a b"];
        [s scanString:@"a" intoString:NULL];
        NSScanner *c = [s copy];
        printf("copy at %lu: %d\n", (unsigned long)[c scanLocation], [c scanString:@"b" intoString:NULL]);
        [c release];
        printf("string: %s\n", [[s string] UTF8String]);
        printf("empty: at end %d, up to: %d\n", [[NSScanner scannerWithString:@""] isAtEnd],
               [[NSScanner scannerWithString:@""] scanUpToString:@"x" intoString:NULL]);
        printf("only spaces: at end %d\n", [[NSScanner scannerWithString:@" \n\t "] isAtEnd]);

        /* a typical use: key=value lines */
        s = [NSScanner scannerWithString:@"name=Ferry\nversion=0.20\nfast=yes\n"];
        NSMutableDictionary *pairs = [NSMutableDictionary dictionary];
        NSString *key, *value;
        while ([s scanUpToString:@"=" intoString:&key] && [s scanString:@"=" intoString:NULL] &&
               [s scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&value])
            [pairs setObject:value forKey:key];
        for (NSString *k in [[pairs allKeys] sortedArrayUsingSelector:@selector(compare:)])
            printf("%s -> %s\n", [k UTF8String], [[pairs objectForKey:k] UTF8String]);
    }
    return 0;
}
