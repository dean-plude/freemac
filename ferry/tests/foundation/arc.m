/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: Foundation used from ARC code, as most Mac apps are built:
 * collections own their objects, weak references clear, blocks capture. */
#import <Foundation/Foundation.h>

@interface Item : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, weak) Item *peer;
@end

@implementation Item
- (instancetype)initWithLabel:(NSString *)label
{
    if ((self = [super init]))
        _label = [label copy];
    return self;
}
- (void)dealloc { printf("dealloc %s\n", _label.UTF8String); }
@end

static NSArray<Item *> *make_items(void)
{
    NSMutableArray *items = [[NSMutableArray alloc] init];
    for (int i = 0; i < 3; i++)
        [items addObject:[[Item alloc] initWithLabel:[NSString stringWithFormat:@"item%d", i]]];
    return [items copy];
}

int main(void)
{
    @autoreleasepool {
        NSArray<Item *> *items = make_items();
        items[0].peer = items[1];
        printf("peer of item0 is %s\n", items[0].peer.label.UTF8String);
        NSMutableDictionary<NSString *, Item *> *byName = [NSMutableDictionary dictionary];
        for (Item *it in items)
            byName[it.label] = it;
        NSString *joined = [[items valueForKey:@"label"] componentsJoinedByString:@","];
        printf("labels %s, dictionary has %lu\n", joined.UTF8String, (unsigned long)byName.count);
        __block NSUInteger total = 0;
        [items enumerateObjectsUsingBlock:^(Item *obj, NSUInteger idx, BOOL *stop) { total += obj.label.length; }];
        printf("total label length %lu\n", (unsigned long)total);
        items = nil;
        [byName removeObjectForKey:@"item1"];
        printf("item1 removed; weak peer now %s\n", byName[@"item0"].peer ? "set" : "nil");
        byName = nil;
        printf("dictionary dropped\n");
    }
    printf("done\n");
    return 0;
}
