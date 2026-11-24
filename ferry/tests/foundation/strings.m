/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: NSString, NSMutableString, string literals and formatting. */
#import <Foundation/Foundation.h>

static void show(NSString *label, id value) { printf("%s: %s\n", [label UTF8String], [[value description] UTF8String]); }

int main(void)
{
    @autoreleasepool {
        NSString *s = @"Hello, world";
        show(@"literal", s);
        printf("length %lu, char 4 '%c'\n", (unsigned long)[s length], [s characterAtIndex:4]);
        printf("class is NSString: %d, mutable: %d\n", [s isKindOfClass:[NSString class]],
               [s isKindOfClass:[NSMutableString class]]);

        /* formatting */
        show(@"format", [NSString stringWithFormat:@"%d|%5d|%-5d|%05d|%x|%X|%o|%u", 42, 42, 42, 42, 255, 255, 8, 7u]);
        show(@"format", [NSString stringWithFormat:@"%.2f|%8.3f|%e|%g|%g", 3.14159, 2.5, 12345.678, 0.0001, 100.0]);
        show(@"format", [NSString stringWithFormat:@"%s|%@|%@|%c|%%|%ld|%lld|%zu", "cstr", @"obj", @42, 'x', -5L,
                                                   1234567890123LL, (size_t)9]);
        show(@"format", [NSString stringWithFormat:@"%*d|%-*s|", 4, 7, 3, "ab"]);
        show(@"positional", [NSString stringWithFormat:@"%2$@ %1$@", @"world", @"hello"]);
        show(@"format", [NSString stringWithFormat:@"%@ and %@", nil, [NSArray arrayWithObject:@"x"]]);

        /* comparing and searching */
        printf("equal %d, compare %ld, caseless %ld\n", [s isEqualToString:@"Hello, world"], (long)[@"abc" compare:@"abd"],
               (long)[@"ABC" caseInsensitiveCompare:@"abc"]);
        printf("prefix %d suffix %d contains %d\n", [s hasPrefix:@"Hell"], [s hasSuffix:@"world"],
               [s containsString:@"o, w"]);
        NSRange r = [s rangeOfString:@"o"];
        NSRange back = [s rangeOfString:@"o" options:NSBackwardsSearch];
        NSRange none = [s rangeOfString:@"zzz"];
        printf("range %lu,%lu back %lu missing %d\n", (unsigned long)r.location, (unsigned long)r.length,
               (unsigned long)back.location, none.location == NSNotFound);
        printf("numeric compare %ld\n", (long)[@"file10" compare:@"file9" options:NSNumericSearch]);

        /* pieces */
        show(@"substring", [s substringWithRange:NSMakeRange(7, 5)]);
        show(@"from", [s substringFromIndex:7]);
        show(@"to", [s substringToIndex:5]);
        show(@"upper", [s uppercaseString]);
        show(@"lower", [s lowercaseString]);
        show(@"capitalized", [@"the quick fox" capitalizedString]);
        show(@"replace", [s stringByReplacingOccurrencesOfString:@"o" withString:@"0"]);
        show(@"components", [@"a,b,,c" componentsSeparatedByString:@","]);
        show(@"joined", [[@"x y z" componentsSeparatedByString:@" "] componentsJoinedByString:@"-"]);
        show(@"trimmed", [@"  \t padded \n" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
        show(@"padded", [@"ab" stringByPaddingToLength:5 withString:@"." startingAtIndex:0]);

        /* numbers in strings */
        printf("int %d, double %.2f, bool %d, longlong %lld\n", [@" 42abc" intValue], [@"3.75" doubleValue],
               [@"YES" boolValue], [@"-9000000000" longLongValue]);

        /* Unicode: lengths count UTF-16 units, as on a Mac */
        NSString *u = @"café \U0001F600";
        printf("unicode length %lu, utf8 bytes %lu, text %s\n", (unsigned long)[u length],
               (unsigned long)[u lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [u UTF8String]);
        NSString *fromUTF8 = [NSString stringWithUTF8String:"na\xc3\xafve"];
        printf("from UTF-8 length %lu equal %d\n", (unsigned long)[fromUTF8 length], [fromUTF8 isEqualToString:@"naïve"]);
        printf("hash equal for equal strings %d\n", [fromUTF8 hash] == [@"naïve" hash]);

        /* paths */
        NSString *p = @"/usr/local/lib/libfoo.dylib";
        show(@"last", [p lastPathComponent]);
        show(@"ext", [p pathExtension]);
        show(@"dir", [p stringByDeletingLastPathComponent]);
        show(@"noext", [p stringByDeletingPathExtension]);
        show(@"append", [@"/tmp" stringByAppendingPathComponent:@"x.txt"]);
        show(@"appendext", [@"photo" stringByAppendingPathExtension:@"png"]);
        show(@"components", [p pathComponents]);
        show(@"standard", [@"/a/./b/../c//d/" stringByStandardizingPath]);
        printf("absolute %d %d\n", [p isAbsolutePath], [@"rel/path" isAbsolutePath]);

        /* mutable strings */
        NSMutableString *m = [NSMutableString stringWithString:@"one"];
        [m appendString:@" two"];
        [m appendFormat:@" %d", 3];
        [m insertString:@"zero " atIndex:0];
        [m replaceCharactersInRange:NSMakeRange(0, 4) withString:@"ZERO"];
        [m deleteCharactersInRange:NSMakeRange([m length] - 2, 2)];
        show(@"mutable", m);
        NSUInteger n = [m replaceOccurrencesOfString:@"o" withString:@"0" options:0 range:NSMakeRange(0, [m length])];
        printf("replaced %lu -> %s\n", (unsigned long)n, [m UTF8String]);
        NSString *frozen = [m copy];
        [m setString:@"changed"];
        printf("copy kept %s, mutable now %s, copy is mutable %d\n", [frozen UTF8String], [m UTF8String],
               [frozen isKindOfClass:[NSMutableString class]]);
        [frozen release];

        /* lines */
        [@"first\nsecond\r\nthird" enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
          printf("line <%s>\n", [line UTF8String]);
        }];

        /* data round trip */
        NSData *d = [@"bytesé" dataUsingEncoding:NSUTF8StringEncoding];
        NSString *back2 = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
        printf("data %lu bytes, back equal %d\n", (unsigned long)[d length], [back2 isEqualToString:@"bytesé"]);
        /* one-byte encodings: nil for a character the encoding lacks, '?' when lossy */
        NSData *latin = [@"café" dataUsingEncoding:NSISOLatin1StringEncoding];
        printf("latin1 %lu bytes, last %02x, euro %s, ascii %s, lossy %.*s\n",
               (unsigned long)[latin length], ((const unsigned char *)[latin bytes])[3],
               [@"5 €" dataUsingEncoding:NSISOLatin1StringEncoding] ? "data" : "nil",
               [@"café" dataUsingEncoding:NSASCIIStringEncoding] ? "data" : "nil",
               4, (const char *)[[@"café" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES] bytes]);
    }
    return 0;
}
