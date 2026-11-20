/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: NSNumber, NSValue, NSArray, NSDictionary, NSSet, NSData,
 * NSNull, descriptions, copying, key-value coding and object lifetimes. */
#import <Foundation/Foundation.h>

static void show(const char *label, id value) { printf("%s: %s\n", label, [[value description] UTF8String]); }

@interface Tracked : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int size;
@end

@implementation Tracked
- (void)dealloc
{
    printf("dealloc %s\n", [_name UTF8String]);
    [_name release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"Tracked(%@)", _name]; }
@end

static Tracked *tracked(NSString *name, int size)
{
    Tracked *t = [[[Tracked alloc] init] autorelease];
    t.name = name;
    t.size = size;
    return t;
}

int main(void)
{
    @autoreleasepool {
        /* numbers */
        NSNumber *i = @42, *d = @0.1, *b = @YES, *big = [NSNumber numberWithUnsignedLongLong:18446744073709551615ULL];
        printf("numbers %s %s %s %s\n", [[i description] UTF8String], [[d description] UTF8String],
               [[b description] UTF8String], [[big description] UTF8String]);
        printf("types %s %s %s %s\n", [i objCType], [d objCType], [b objCType], [@3.5f objCType]);
        printf("equal %d %d %d, compare %ld %ld\n", [@1 isEqual:@1.0], [@1 isEqualToNumber:@2], [@YES isEqual:@1],
               (long)[@1 compare:@2], (long)[@2.5 compare:@2]);
        NSNumber *yes1 = @YES, *yes2 = [NSNumber numberWithBool:YES];
        printf("same hash for 1 and 1.0: %d, shared YES %d\n", [@1 hash] == [@1.0 hash], yes1 == yes2);
        printf("conversions %d %.1f %lld %d\n", [@"7" intValue] + [@3.9 intValue], [@7 doubleValue], [@-1 longLongValue],
               [@0.0 boolValue]);
        NSValue *rv = [NSValue valueWithRange:NSMakeRange(3, 4)];
        printf("range value %s %lu\n", [[rv description] UTF8String], (unsigned long)[rv rangeValue].length);

        /* arrays */
        NSArray *a = @[@"pear", @"apple", @"fig", @"banana"];
        show("array", a);
        printf("count %lu first %s last %s index of fig %lu missing %d\n", (unsigned long)[a count],
               [[a firstObject] UTF8String], [[a lastObject] UTF8String], (unsigned long)[a indexOfObject:@"fig"],
               [a indexOfObject:@"kiwi"] == NSNotFound);
        show("sorted", [a sortedArrayUsingSelector:@selector(compare:)]);
        show("by length", [a sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
               return [@([x length]) compare:@([y length])];
             }]);
        show("filtered", [a filteredArrayUsingBlock:^BOOL(id s) { return [s length] > 3; }]);
        show("sub", [a subarrayWithRange:NSMakeRange(1, 2)]);
        show("plus", [a arrayByAddingObject:@"kiwi"]);
        for (NSString *s in [a reverseObjectEnumerator])
            printf("reverse %s\n", [s UTF8String]);
        [a enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
          printf("block %lu %s\n", (unsigned long)idx, [obj UTF8String]);
          if (idx == 1)
              *stop = YES;
        }];
        printf("literal class immutable %d, equal arrays %d\n", ![a isKindOfClass:[NSMutableArray class]],
               [a isEqual:[NSArray arrayWithObjects:@"pear", @"apple", @"fig", @"banana", nil]]);
        printf("empty: %s\n", [[@[] description] UTF8String]);

        NSMutableArray *m = [NSMutableArray arrayWithArray:a];
        [m addObject:@"cherry"];
        [m insertObject:@"date" atIndex:0];
        [m removeObject:@"fig"];
        [m removeObjectAtIndex:1];
        [m replaceObjectAtIndex:0 withObject:@"DATE"];
        [m exchangeObjectAtIndex:0 withObjectAtIndex:1];
        m[[m count]] = @"elder";
        [m sortUsingSelector:@selector(caseInsensitiveCompare:)];
        show("mutable", m);
        NSArray *snapshot = [m copy];
        [m removeAllObjects];
        printf("snapshot %lu, mutable %lu, snapshot mutable %d\n", (unsigned long)[snapshot count], (unsigned long)[m count],
               [snapshot isKindOfClass:[NSMutableArray class]]);
        [snapshot release];

        /* dictionaries */
        NSDictionary *dict = @{@"name": @"Ferry", @"version": @2, @"tags": @[@"mac", @"linux"], @"nested": @{@"a": @1}};
        show("dict", dict);
        printf("lookup %s %s missing %d\n", [dict[@"name"] UTF8String], [[dict objectForKey:@"version"] description].UTF8String,
               [dict objectForKey:@"nope"] == nil);
        show("keys", [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)]);
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        for (int k = 0; k < 100; k++)
            md[[NSString stringWithFormat:@"k%d", k]] = @(k * k);
        for (int k = 0; k < 100; k += 2)
            [md removeObjectForKey:[NSString stringWithFormat:@"k%d", k]];
        md[@"k99"] = @"replaced";
        printf("mutable dict %lu, k7 %s, k8 gone %d, k99 %s\n", (unsigned long)[md count], [[md[@"k7"] description] UTF8String],
               md[@"k8"] == nil, [md[@"k99"] UTF8String]);
        __block int seen = 0;
        [md enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) { seen++; }];
        int fast = 0;
        for (id key in md)
            fast += [md objectForKey:key] != nil;
        printf("enumerated %d, fast %d\n", seen, fast);
        NSMutableString *key = [NSMutableString stringWithString:@"mut"];
        md[key] = @"value";
        [key appendString:@"ated"];
        printf("keys are copied: %s %d\n", [md[@"mut"] UTF8String], md[@"mutated"] == nil);
        show("sorted by value", [@{@"b": @2, @"a": @3, @"c": @1} keysSortedByValueUsingSelector:@selector(compare:)]);

        /* sets */
        NSSet *set = [NSSet setWithObjects:@"x", @"y", @"x", @"z", nil];
        NSMutableSet *ms = [NSMutableSet setWithArray:@[@1, @2, @3]];
        [ms addObject:@2];
        [ms removeObject:@1];
        printf("set %lu contains y %d, mutable %lu contains 1 %d, subset %d\n", (unsigned long)[set count],
               [set containsObject:@"y"], (unsigned long)[ms count], [ms containsObject:@1],
               [[NSSet setWithObject:@"x"] isSubsetOfSet:set]);
        show("set sorted", [[set allObjects] sortedArrayUsingSelector:@selector(compare:)]);

        /* data */
        NSData *data = [NSData dataWithBytes:"Ferry\x00\xff" length:7];
        show("data", data);
        printf("base64 %s\n", [[data base64EncodedStringWithOptions:0] UTF8String]);
        NSData *round = [[[NSData alloc] initWithBase64EncodedString:@"RmVycnkA/w==" options:0] autorelease];
        printf("base64 round trip %d\n", [round isEqualToData:data]);
        NSMutableData *md2 = [NSMutableData dataWithLength:2];
        [md2 appendBytes:"ab" length:2];
        [md2 appendData:[@"cd" dataUsingEncoding:NSUTF8StringEncoding]];
        show("mutable data", md2);
        show("subdata", [md2 subdataWithRange:NSMakeRange(2, 3)]);

        /* NSNull and key-value coding */
        show("null", [NSNull null]);
        Tracked *t = tracked(@"kvc", 5);
        [t setValue:@"renamed" forKey:@"name"];
        [t setValue:@9 forKey:@"size"];
        printf("kvc %s %s\n", [[t valueForKey:@"name"] UTF8String], [[[t valueForKey:@"size"] description] UTF8String]);
        show("array kvc", [@[tracked(@"one", 1), tracked(@"two", 2)] valueForKey:@"size"]);
    }
    printf("pool drained\n");

    /* collections retain what they hold */
    @autoreleasepool {
        Tracked *t = [[Tracked alloc] init];
        t.name = @"held";
        NSMutableArray *holder = [[NSMutableArray alloc] init];
        [holder addObject:t];
        [t release];
        printf("still alive: %s\n", [[holder[0] name] UTF8String]);
        [holder release];
        printf("array released\n");
        NSDictionary *dd = [[NSDictionary alloc] initWithObjectsAndKeys:tracked(@"in dict", 0), @"k", nil];
        [dd release];
    }
    printf("done\n");
    return 0;
}
