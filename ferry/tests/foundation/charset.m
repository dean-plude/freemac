/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): NSMutableCharacterSet and the
 * further parts of NSCharacterSet. Ranges and strings added and removed,
 * unions, intersections and inversion; characters past the Basic
 * Multilingual Plane; the predefined sets made from Unicode's categories;
 * bitmaps written and read back; supersets and planes; equality and copies;
 * the URL sets and percent encoding. MacPass builds its sets this way. */
#import <Foundation/Foundation.h>
#include <unistd.h>

static const char *yn(BOOL b) { return b ? "yes" : "no"; }

static void members(const char *label, NSCharacterSet *set, NSString *of)
{
    printf("%s:", label);
    for (NSUInteger i = 0; i < [of length]; i++)
        if ([set characterIsMember:[of characterAtIndex:i]])
            printf(" U+%04X", [of characterAtIndex:i]);
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSMutableCharacterSet *m = [[NSMutableCharacterSet alloc] init];
        printf("new: mutable %s, a character set %s, holds 'a' %s\n", yn([m isKindOfClass:[NSMutableCharacterSet class]]),
               yn([m isKindOfClass:[NSCharacterSet class]]), yn([m characterIsMember:'a']));
        [m addCharactersInRange:NSMakeRange('a', 26)];
        [m addCharactersInString:@"0123"];
        [m removeCharactersInRange:NSMakeRange('m', 3)];
        [m removeCharactersInString:@"z0"];
        members("a to z, 0 to 3, less m to o, z and 0", m, @"almnopyz0134");
        [m formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
        members("with the whitespace", m, @"a \t\nx");
        [m formIntersectionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"abc \n"]];
        members("cut to abc, space and newline", m, @"abcdx \t\n");
        [m invert];
        members("inverted", m, @"abcdx \t\n");
        printf("inverted holds U+1F600 %s\n", yn([m longCharacterIsMember:0x1F600]));
        [m invert];

        /* past the Basic Multilingual Plane */
        NSMutableCharacterSet *emoji = [NSMutableCharacterSet characterSetWithCharactersInString:@"x\U0001F600"];
        printf("from a string with an emoji: mutable %s, U+1F600 %s, U+1F601 %s, x %s, plane 1 %s, plane 2 %s\n",
               yn([emoji isKindOfClass:[NSMutableCharacterSet class]]), yn([emoji longCharacterIsMember:0x1F600]),
               yn([emoji longCharacterIsMember:0x1F601]), yn([emoji characterIsMember:'x']),
               yn([emoji hasMemberInPlane:1]), yn([emoji hasMemberInPlane:2]));
        NSCharacterSet *range = [NSCharacterSet characterSetWithRange:NSMakeRange(0x10000, 0x100)];
        printf("a range in plane 1: U+10000 %s, U+100FF %s, U+10100 %s, plane 0 %s\n",
               yn([range longCharacterIsMember:0x10000]), yn([range longCharacterIsMember:0x100FF]),
               yn([range longCharacterIsMember:0x10100]), yn([range hasMemberInPlane:0]));

        /* the predefined sets */
        NSString *sample = @"AaéÉǅ́+$\a­￿5 ";
        members("control", [NSCharacterSet controlCharacterSet], sample);
        members("uppercase", [NSCharacterSet uppercaseLetterCharacterSet], sample);
        members("lowercase", [NSCharacterSet lowercaseLetterCharacterSet], sample);
        members("capitalized", [NSCharacterSet capitalizedLetterCharacterSet], sample);
        members("non-base", [NSCharacterSet nonBaseCharacterSet], sample);
        members("decomposable", [NSCharacterSet decomposableCharacterSet], sample);
        members("illegal", [NSCharacterSet illegalCharacterSet], sample);
        members("symbol", [NSCharacterSet symbolCharacterSet], sample);
        printf("the same set each time: %s\n",
               yn([NSCharacterSet symbolCharacterSet] == [NSCharacterSet symbolCharacterSet]));
        NSMutableCharacterSet *digits = [NSMutableCharacterSet decimalDigitCharacterSet];
        [digits addCharactersInString:@"."];
        members("the mutable digits with a point", digits, @"09.a");
        printf("the shared digits keep no point: %s\n", yn(![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:'.']));

        /* bitmaps */
        NSData *bitmap = [emoji bitmapRepresentation];
        printf("the emoji set's bitmap: %lu bytes\n", (unsigned long)[bitmap length]);
        NSCharacterSet *back = [NSCharacterSet characterSetWithBitmapRepresentation:bitmap];
        printf("read back: U+1F600 %s, x %s, y %s, equal %s\n", yn([back longCharacterIsMember:0x1F600]),
               yn([back characterIsMember:'x']), yn([back characterIsMember:'y']), yn([back isEqual:emoji]));
        printf("the letters' bitmap: %lu bytes\n",
               (unsigned long)[[[NSCharacterSet characterSetWithCharactersInString:@"abc"] bitmapRepresentation] length]);
        NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"ferry-charset-%d.bitmap", getpid()]];
        [bitmap writeToFile:file atomically:YES];
        printf("from a file: U+1F600 %s; from no file: %s\n",
               yn([[NSCharacterSet characterSetWithContentsOfFile:file] longCharacterIsMember:0x1F600]),
               [NSCharacterSet characterSetWithContentsOfFile:@"/nonexistent/ferry"] ? "a set" : "nil");
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];

        /* supersets, equality, copies */
        NSCharacterSet *letters = [NSCharacterSet characterSetWithRange:NSMakeRange('a', 26)];
        NSCharacterSet *abc = [NSCharacterSet characterSetWithCharactersInString:@"abc"];
        printf("a to z holds abc: %s; abc holds a to z: %s\n", yn([letters isSupersetOfSet:abc]),
               yn([abc isSupersetOfSet:letters]));
        printf("the whitespace and newlines hold the newlines: %s\n",
               yn([[NSCharacterSet whitespaceAndNewlineCharacterSet] isSupersetOfSet:[NSCharacterSet newlineCharacterSet]]));
        printf("abc from a string and from a range equal: %s\n",
               yn([abc isEqual:[NSCharacterSet characterSetWithRange:NSMakeRange('a', 3)]]));
        NSMutableCharacterSet *copy = [abc mutableCopy];
        [copy addCharactersInString:@"d"];
        NSCharacterSet *frozen = [copy copy];
        [copy addCharactersInString:@"e"];
        printf("a mutable copy: mutable %s, d %s; its copy: mutable %s, d %s, e %s; abc unchanged %s\n",
               yn([copy isKindOfClass:[NSMutableCharacterSet class]]), yn([copy characterIsMember:'d']),
               yn([frozen isKindOfClass:[NSMutableCharacterSet class]]), yn([frozen characterIsMember:'d']),
               yn([frozen characterIsMember:'e']), yn(![abc characterIsMember:'d']));
        NSCharacterSet *notAbc = [copy invertedSet];
        printf("the mutable set inverted: a %s, f %s, U+1F600 %s\n", yn([notAbc characterIsMember:'a']),
               yn([notAbc characterIsMember:'f']), yn([notAbc longCharacterIsMember:0x1F600]));
        printf("an older set inverted holds U+1F600: %s; the older set does: %s\n",
               yn([[[NSCharacterSet letterCharacterSet] invertedSet] longCharacterIsMember:0x1F600]),
               yn([[NSCharacterSet letterCharacterSet] longCharacterIsMember:0x1F600]));
        NSString *trimmed = [@"..hello.." stringByTrimmingCharactersInSet:[NSMutableCharacterSet characterSetWithCharactersInString:@"."]];
        printf("trimmed with a mutable set: %s\n", [trimmed UTF8String]);

        /* the URL sets and percent encoding */
        NSString *raw = @"a b/c?d=e&f#gé\U0001F600";
        printf("query: %s\n",
               [[raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] UTF8String]);
        printf("path: %s\n",
               [[raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] UTF8String]);
        printf("user: %s\n",
               [[raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLUserAllowedCharacterSet]] UTF8String]);
        printf("host: %s\n",
               [[@"[::1]:80 x" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]] UTF8String]);
        NSString *coded = [raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
        printf("decoded again the same: %s\n", yn([[coded stringByRemovingPercentEncoding] isEqual:raw]));
        printf("bad escapes: %s, %s, %s\n", [@"100%" stringByRemovingPercentEncoding] ? "a string" : "nil",
               [@"%zz" stringByRemovingPercentEncoding] ? "a string" : "nil",
               [@"%C3" stringByRemovingPercentEncoding] ? "a string" : "nil");
        printf("mixed: %s\n", [[@"caf%C3%A9%20au%2Blait" stringByRemovingPercentEncoding] UTF8String]);
    }
    return 0;
}
