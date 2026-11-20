/* NSAttributedString and CFAttributedString (added for M3's Core Text). */
#import <Foundation/Foundation.h>
#include <stdio.h>

static void show(NSAttributedString *s)
{
    printf("\"%s\":", s.string.UTF8String);
    [s enumerateAttributesInRange:NSMakeRange(0, s.length)
                          options:0
                       usingBlock:^(NSDictionary *attrs, NSRange r, BOOL *stop) {
                           NSArray *keys = [attrs.allKeys sortedArrayUsingSelector:@selector(compare:)];
                           printf(" [%lu,%lu", (unsigned long)r.location, (unsigned long)r.length);
                           for (NSString *k in keys)
                               printf(" %s=%s", k.UTF8String, [[attrs[k] description] UTF8String]);
                           printf("]");
                       }];
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSMutableAttributedString *s =
            [[NSMutableAttributedString alloc] initWithString:@"Hello world" attributes:@{@"a" : @1}];
        show(s);
        [s addAttribute:@"b" value:@"x" range:NSMakeRange(6, 5)];
        show(s);
        [s setAttributes:@{@"c" : @3} range:NSMakeRange(2, 6)];
        show(s);
        [s removeAttribute:@"c" range:NSMakeRange(0, 11)];
        show(s);
        [s replaceCharactersInRange:NSMakeRange(0, 5) withString:@"Goodbye"];
        show(s);
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:@"!" attributes:@{@"d" : @4}]];
        show(s);
        [s deleteCharactersInRange:NSMakeRange(7, 1)];
        show(s);

        NSRange r;
        id v = [s attribute:@"a" atIndex:3 effectiveRange:&r];
        printf("a at 3 = %s over {%lu, %lu}\n", [[v description] UTF8String], (unsigned long)r.location,
               (unsigned long)r.length);
        NSDictionary *d = [s attributesAtIndex:12 effectiveRange:&r];
        printf("attributes at 12: %lu keys over {%lu, %lu}\n", (unsigned long)d.count, (unsigned long)r.location,
               (unsigned long)r.length);
        NSAttributedString *sub = [s attributedSubstringFromRange:NSMakeRange(5, 7)];
        show(sub);
        NSAttributedString *copy = [s copy];
        printf("copy equal: %s, mutable copy is mutable: %s\n", [copy isEqual:s] ? "yes" : "no",
               [[s mutableCopy] isKindOfClass:[NSMutableAttributedString class]] ? "yes" : "no");
        [s enumerateAttribute:@"a"
                      inRange:NSMakeRange(0, s.length)
                      options:NSAttributedStringEnumerationReverse
                   usingBlock:^(id value, NSRange range, BOOL *stop) {
                       printf("a %s over {%lu, %lu}\n", value ? [[value description] UTF8String] : "(none)",
                              (unsigned long)range.location, (unsigned long)range.length);
                   }];

        CFMutableAttributedStringRef cf = CFAttributedStringCreateMutable(NULL, 0);
        CFAttributedStringReplaceString(cf, CFRangeMake(0, 0), CFSTR("plain C"));
        CFAttributedStringSetAttribute(cf, CFRangeMake(6, 1), CFSTR("k"), CFSTR("v"));
        CFRange er;
        CFTypeRef cv = CFAttributedStringGetAttribute(cf, 6, CFSTR("k"), &er);
        printf("CF: %ld chars, k=%s over {%ld, %ld}\n", (long)CFAttributedStringGetLength(cf),
               [[(id)cv description] UTF8String], (long)er.location, (long)er.length);
        CFRelease(cf);
    }
    return 0;
}
