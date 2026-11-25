/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSMapTable, NSHashTable and NSPointerArray (freemac 1.221, Ferry 0.45.0),
 * as HexFiend and Sequel Pro use them: weak keys and values that go when
 * their objects do, keys compared by equality or by address, pointers that
 * aren't objects, copied keys, and enumerating. */
#import <Foundation/Foundation.h>

@interface Tracked : NSObject
@property (copy) NSString *name;
@end
static int gone;
@implementation Tracked
- (void)dealloc { gone++; }
@end

static Tracked *make(NSString *name)
{
    Tracked *t = [Tracked new];
    t.name = name;
    return t;
}

int main(void)
{
    @autoreleasepool {
        /* weak keys to strong values, as HexFiend's object graph */
        NSMapTable *graph = [NSMapTable weakToStrongObjectsMapTable];
        Tracked *a = make(@"a");
        @autoreleasepool {
            Tracked *b = make(@"b");
            [graph setObject:[NSMutableSet setWithObject:@1] forKey:a];
            [graph setObject:[NSMutableSet setWithObject:@2] forKey:b];
            printf("weak keys: %lu entries, a's value %s\n", (unsigned long)graph.count,
                   [[[graph objectForKey:a] anyObject] description].UTF8String);
            b = nil;
        }
        printf("after b went: %lu entries, gone %d\n", (unsigned long)graph.count, gone);

        /* strong keys to weak values, as Sequel Pro's byte array map */
        NSMapTable *byName = [NSMapTable strongToWeakObjectsMapTable];
        @autoreleasepool {
            Tracked *c = make(@"c");
            [byName setObject:c forKey:@"c"];
            [byName setObject:a forKey:@"a"];
            printf("weak values: c is %s\n", [[[byName objectForKey:@"c"] name] UTF8String]);
            c = nil;
        }
        printf("after c went: c is %s, a is %s, %lu entries\n", [byName objectForKey:@"c"] ? "there" : "nil",
               [[[byName objectForKey:@"a"] name] UTF8String], (unsigned long)byName.count);

        /* equal keys by default, the same object only with the pointer personality */
        NSMapTable *equal = [NSMapTable strongToStrongObjectsMapTable];
        NSMapTable *identity = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory | NSMapTableObjectPointerPersonality
                                                     valueOptions:NSMapTableStrongMemory];
        NSString *k1 = [NSMutableString stringWithString:@"key"], *k2 = [NSMutableString stringWithString:@"key"];
        [equal setObject:@"one" forKey:k1];
        [identity setObject:@"one" forKey:k1];
        printf("equal key finds %s, other object of the same value finds %s\n", [[equal objectForKey:k2] UTF8String],
               [identity objectForKey:k2] ? "it" : "nothing");
        [equal setObject:@"two" forKey:k2];
        [equal setObject:nil forKey:@"none"];
        printf("replaced: %lu entry, %s\n", (unsigned long)equal.count, [[equal objectForKey:@"key"] UTF8String]);

        /* copied keys */
        NSMapTable *copied = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsCopyIn
                                                   valueOptions:NSPointerFunctionsStrongMemory];
        NSMutableString *mk = [NSMutableString stringWithString:@"before"];
        [copied setObject:@"v" forKey:mk];
        [mk setString:@"after"];
        printf("copied key still found as before %d, as after %d\n", [copied objectForKey:@"before"] != nil,
               [copied objectForKey:@"after"] != nil);

        /* opaque pointers and integers */
        NSMapTable *opaque = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory |
                                                                NSPointerFunctionsIntegerPersonality
                                                   valueOptions:NSPointerFunctionsStrongMemory];
        for (uintptr_t i = 1; i <= 40; i++)
            [opaque setObject:@(i * i) forKey:(__bridge id)(void *)i];
        printf("integer keys: %lu, 7 -> %s\n", (unsigned long)opaque.count,
               [[[opaque objectForKey:(__bridge id)(void *)7] description] UTF8String]);

        /* enumerating, and the dictionary */
        NSMapTable *m = [NSMapTable strongToStrongObjectsMapTable];
        for (NSString *s in @[ @"x", @"y", @"z" ])
            [m setObject:[s uppercaseString] forKey:s];
        NSMutableArray *keys = [NSMutableArray array];
        for (NSString *key in m)
            [keys addObject:key];
        [keys sortUsingSelector:@selector(compare:)];
        NSArray *values = [[[m objectEnumerator] allObjects] sortedArrayUsingSelector:@selector(compare:)];
        printf("keys %s, values %s, dictionary %s\n", [[keys componentsJoinedByString:@","] UTF8String],
               [[values componentsJoinedByString:@","] UTF8String],
               [[m dictionaryRepresentation][@"y"] UTF8String]);
        NSMapTable *mc = [m copy];
        [m removeObjectForKey:@"x"];
        printf("after a removal %lu, the copy %lu; cleared %lu\n", (unsigned long)m.count, (unsigned long)mc.count,
               ([m removeAllObjects], (unsigned long)m.count));

        /* weak hash tables, as HexFiend's searches */
        NSHashTable *visited = [NSHashTable weakObjectsHashTable];
        Tracked *d = make(@"d");
        @autoreleasepool {
            Tracked *e = make(@"e");
            [visited addObject:d];
            [visited addObject:e];
            [visited addObject:d];
            printf("hash table: %lu, has e %d\n", (unsigned long)visited.count, [visited containsObject:e]);
            e = nil;
        }
        printf("after e went: %lu, member d %s\n", (unsigned long)visited.count, [[visited member:d] name].UTF8String);
        NSHashTable *strong = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
        [strong addObject:@"p"];
        [strong addObject:@"q"];
        NSHashTable *other = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
        [other addObject:@"q"];
        [other addObject:@"r"];
        printf("intersects %d, subset %d", [strong intersectsHashTable:other], [other isSubsetOfHashTable:strong]);
        [strong unionHashTable:other];
        printf(", union %lu", (unsigned long)strong.count);
        [strong minusHashTable:other];
        printf(", minus %s", [[[strong allObjects] componentsJoinedByString:@","] UTF8String]);
        [strong unionHashTable:other];
        [strong intersectHashTable:other];
        printf(", intersect %lu, set %d\n", (unsigned long)strong.count,
               [[strong setRepresentation] isEqual:[NSSet setWithObjects:@"q", @"r", nil]]);

        /* pointer arrays, as Sequel Pro's row store */
        NSPointerArray *rows = [[NSPointerArray alloc] init];
        [rows addPointer:(__bridge void *)@"row 0"];
        [rows addPointer:NULL];
        [rows addPointer:(__bridge void *)@"row 2"];
        [rows insertPointer:(__bridge void *)@"row -1" atIndex:0];
        printf("pointer array %lu, [3] %s, [2] %s\n", (unsigned long)rows.count,
               [(__bridge NSString *)[rows pointerAtIndex:3] UTF8String], [rows pointerAtIndex:2] ? "set" : "NULL");
        int seen = 0, nils = 0;
        for (id o in rows) {
            seen++;
            nils += o == nil;
        }
        [rows replacePointerAtIndex:0 withPointer:(__bridge void *)@"first"];
        [rows removePointerAtIndex:1];
        [rows compact];
        printf("enumerated %d (%d nil), after compacting %s\n", seen, nils,
               [[rows.allObjects componentsJoinedByString:@" | "] UTF8String]);
        rows.count = 5;
        printf("grown to %lu, [4] %s\n", (unsigned long)rows.count, [rows pointerAtIndex:4] ? "set" : "NULL");
        NSPointerArray *weak = [NSPointerArray weakObjectsPointerArray];
        @autoreleasepool {
            Tracked *f = make(@"f");
            [weak addPointer:(__bridge void *)f];
            [weak addPointer:(__bridge void *)d];
            f = nil;
        }
        printf("weak pointer array: [0] %s, [1] %s", [weak pointerAtIndex:0] ? "set" : "NULL",
               [[(__bridge Tracked *)[weak pointerAtIndex:1] name] UTF8String]);
        [weak compact];
        printf(", compacted to %lu\n", (unsigned long)weak.count);
        @try {
            [weak pointerAtIndex:9];
        } @catch (NSException *ex) {
            printf("out of range: %s\n", [[ex name] UTF8String]);
        }
        printf("gone in all %d\n", gone);
    }
    return 0;
}
