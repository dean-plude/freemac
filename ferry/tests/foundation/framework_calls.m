/* SPDX-License-Identifier: GPL-3.0-or-later
 * Foundation calls KeePassKit and the apps' other frameworks make (freemac
 * 1.223, Ferry 0.47.0): NSCountedSet; NSMutableData growing, shrinking
 * and zeroing in place; NSNumber's initializers; NSMutableSet's
 * initWithCapacity:; enumerating an index set within a range, both ways;
 * strings made from characters that are then freed, and searched with a
 * locale; and uuid_t with NSUUID. Built with ARC. */
#import <Foundation/Foundation.h>

static void show(const char *what, NSData *d)
{
    printf("%s:", what);
    const unsigned char *b = [d bytes];
    for (NSUInteger i = 0; i < [d length]; i++)
        printf(" %02x", b[i]);
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSCountedSet *bag = [[NSCountedSet alloc] initWithArray:@[ @"a", @"b", @"a", @"c", @"a" ]];
        [bag addObject:[NSMutableString stringWithString:@"b"]];
        [bag removeObject:@"c"];
        printf("counted set: %lu objects, a %lu, b %lu, c %lu, member of b is the first %s\n",
               (unsigned long)[bag count], (unsigned long)[bag countForObject:@"a"],
               (unsigned long)[bag countForObject:@"b"], (unsigned long)[bag countForObject:@"c"],
               [[bag member:@"b"] isKindOfClass:[NSMutableString class]] ? "no" : "yes");
        NSArray *sorted = [[bag allObjects] sortedArrayUsingSelector:@selector(compare:)];
        printf("  objects %s, contains a %s, a copy counts a %lu\n", [[sorted componentsJoinedByString:@","] UTF8String],
               [bag containsObject:@"a"] ? "yes" : "no", (unsigned long)[[bag copy] countForObject:@"a"]);
        NSUInteger seen = 0;
        for (id o in bag)
            seen += [bag countForObject:o];
        printf("  enumerated counts add up to %lu\n", (unsigned long)seen);

        NSMutableData *d = [NSMutableData dataWithBytes:"\x01\x02\x03\x04\x05" length:5];
        [d replaceBytesInRange:NSMakeRange(1, 2) withBytes:"\xaa\xbb\xcc" length:3];
        show("replaced 2 bytes with 3", d);
        [d replaceBytesInRange:NSMakeRange(0, 3) withBytes:"\xee" length:1];
        show("3 with 1", d);
        [d replaceBytesInRange:NSMakeRange(2, 0) withBytes:[d bytes] length:2];
        show("2 of its own bytes inserted", d);
        [d increaseLengthBy:2];
        [d resetBytesInRange:NSMakeRange(0, 1)];
        show("longer by 2, first zeroed", d);

        NSNumber *n = [[NSNumber alloc] initWithLong:-7];
        NSNumber *u = [[NSNumber alloc] initWithUnsignedLongLong:18446744073709551615ULL];
        NSNumber *f = [[NSNumber alloc] initWithFloat:1.5f];
        printf("numbers: %ld %llu %.1f %d, equal to numberWithLong: %s\n", [n longValue], [u unsignedLongLongValue],
               [f floatValue], [[[NSNumber alloc] initWithUnsignedChar:200] intValue],
               [n isEqualToNumber:@(-7L)] ? "yes" : "no");

        NSMutableSet *s = [[NSMutableSet alloc] initWithCapacity:10];
        [s addObject:@1];
        printf("set with capacity: %lu\n", (unsigned long)[s count]);

        NSMutableIndexSet *ix = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < 20; i += 3)
            [ix addIndex:i];
        printf("indexes in 4..12:");
        [ix enumerateIndexesInRange:NSMakeRange(4, 9) options:0 usingBlock:^(NSUInteger i, BOOL *stop) { printf(" %lu", (unsigned long)i); }];
        printf("; reversed:");
        [ix enumerateIndexesInRange:NSMakeRange(4, 9) options:NSEnumerationReverse
                         usingBlock:^(NSUInteger i, BOOL *stop) { printf(" %lu", (unsigned long)i); }];
        printf("\n");

        unichar *chars = malloc(3 * sizeof(unichar));
        chars[0] = 'K', chars[1] = 'P', chars[2] = 'K';
        NSString *str = [[NSString alloc] initWithCharactersNoCopy:chars length:3 freeWhenDone:YES];
        printf("string from characters: %s, found at %lu with a locale\n", [str UTF8String],
               (unsigned long)[@"KeePassKit" rangeOfString:@"pass" options:NSCaseInsensitiveSearch
                                                      range:NSMakeRange(0, 10)
                                                     locale:[NSLocale currentLocale]]
                   .location);

        uuid_t bytes;
        NSUUID *id1 = [[NSUUID alloc] initWithUUIDString:@"68753A44-4D6F-1226-9C60-0050E4C00067"];
        [id1 getUUIDBytes:bytes];
        printf("uuid_t: %zu bytes, first %02x last %02x, back %s\n", sizeof(uuid_t), bytes[0], bytes[15],
               [[[[NSUUID alloc] initWithUUIDBytes:bytes] UUIDString] UTF8String]);
    }
    return 0;
}
