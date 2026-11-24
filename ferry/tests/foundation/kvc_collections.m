/* SPDX-License-Identifier: GPL-3.0-or-later
 * Key-value coding and observing of collections (Ferry 0.18.0):
 * mutableSetValueForKey: through a class's set accessors, through its
 * setter and straight to an instance variable, with the set mutation kinds
 * its observers hear (union, minus, intersect and set, with the old, new
 * and prior options); the collection operators in key paths on arrays,
 * sets and through a to-one key (@count, @sum, @avg, @min, @max and the
 * unions), with nil values and empty collections; arrays and sets of
 * objects answering and taking keys; removing an observer that isn't
 * registered raising; and NSPredicate's format strings, arguments,
 * variables, compound predicates and filtering. */
#import <Foundation/Foundation.h>

static const char *sorted(id collection)
{
    NSArray *all = [collection isKindOfClass:[NSSet class]] ? [collection allObjects] : collection;
    NSMutableArray *parts = [NSMutableArray array];
    for (id o in [all sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[o description]];
    return [[NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@" "]] UTF8String];
}
static const char *str(id v) { return v ? [[v description] UTF8String] : "nil"; }

@interface Watcher : NSObject
@property (strong) NSMutableArray *heard;
@end
@implementation Watcher
- (instancetype)init
{
    if ((self = [super init]))
        _heard = [NSMutableArray array];
    return self;
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@ kind %@", path, change[NSKeyValueChangeKindKey]];
    if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue])
        [s appendString:@" prior"];
    id old = change[NSKeyValueChangeOldKey], new = change[NSKeyValueChangeNewKey];
    if (old)
        [s appendFormat:@" old %s", [old isKindOfClass:[NSSet class]] ? sorted(old) : [[old description] UTF8String]];
    if (new)
        [s appendFormat:@" new %s", [new isKindOfClass:[NSSet class]] ? sorted(new) : [[new description] UTF8String]];
    [_heard addObject:s];
}
- (void)dump:(const char *)what
{
    printf("%s:\n", what);
    for (NSString *s in _heard)
        printf("  %s\n", [s UTF8String]);
    if (![_heard count])
        printf("  (nothing)\n");
    [_heard removeAllObjects];
}
@end

/* A to-many key with set accessors. */
@interface Club : NSObject {
    NSMutableSet *_members;
}
@property (strong) NSMutableArray *calls;
@end
@implementation Club
- (instancetype)init
{
    if ((self = [super init])) {
        _members = [NSMutableSet set];
        _calls = [NSMutableArray array];
    }
    return self;
}
- (NSSet *)members { return _members; }
- (void)addMembersObject:(id)o
{
    [_calls addObject:[NSString stringWithFormat:@"addMembersObject: %@", o]];
    [_members addObject:o];
}
- (void)removeMembersObject:(id)o
{
    [_calls addObject:[NSString stringWithFormat:@"removeMembersObject: %@", o]];
    [_members removeObject:o];
}
- (void)addMembers:(NSSet *)s
{
    [_calls addObject:[NSString stringWithFormat:@"addMembers: %s", sorted(s)]];
    [_members unionSet:s];
}
- (void)dump
{
    for (NSString *c in _calls)
        printf("  club: %s\n", [c UTF8String]);
    [_calls removeAllObjects];
}
@end

/* A set kept behind a setter, and one in an instance variable only. */
@interface Shelf : NSObject {
    NSMutableSet *loose;
}
@property (nonatomic, copy) NSSet *books;
@property NSInteger sets;
@end
@implementation Shelf
- (void)setBooks:(NSSet *)b
{
    _sets++;
    _books = [b copy];
}
@end

@interface Item : NSObject
@property (copy) NSString *name;
@property (strong) NSNumber *price;
@property NSInteger count;
@property (strong) NSArray *tags;
@property (strong) NSSet *colors;
@end
@implementation Item
+ (instancetype)name:(NSString *)n price:(NSNumber *)p count:(NSInteger)c
{
    Item *i = [[Item alloc] init];
    i.name = n;
    i.price = p;
    i.count = c;
    return i;
}
- (NSString *)description { return _name; }
@end

@interface Basket : NSObject
@property (strong) NSArray *items;
@end
@implementation Basket
@end

static void raises(const char *what, void (^block)(void))
{
    @try {
        block();
        printf("%s: no exception\n", what);
    } @catch (NSException *e) {
        printf("%s: %s\n", what, [[e name] UTF8String]);
    }
}

static void check(NSString *format, id object, ...)
{
    va_list ap;
    va_start(ap, object);
    NSPredicate *p = [NSPredicate predicateWithFormat:format arguments:ap];
    va_end(ap);
    printf("%-40s -> %-36s %s\n", [format UTF8String], [[p predicateFormat] UTF8String],
           [p evaluateWithObject:object] ? "YES" : "NO");
}

int main(void)
{
    @autoreleasepool {
        Watcher *w = [[Watcher alloc] init];
        NSKeyValueObservingOptions both = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;

        /* ---- mutableSetValueForKey: through the class's set accessors ---- */
        Club *club = [[Club alloc] init];
        [club addObserver:w forKeyPath:@"members" options:both context:NULL];
        NSMutableSet *members = [club mutableSetValueForKey:@"members"];
        [members addObject:@"ann"];
        [members addObject:@"bob"];
        [club dump];
        [w dump:"two added, one at a time"];
        [members unionSet:[NSSet setWithObjects:@"bob", @"cy", @"dee", nil]];
        [club dump];
        [w dump:"a union of three, one already there"];
        [members removeObject:@"ann"];
        [club dump];
        [w dump:"removed"];
        [members intersectSet:[NSSet setWithObjects:@"cy", @"dee", @"zed", nil]];
        [club dump];
        [w dump:"intersected (no intersectMembers:, so removals)"];
        printf("members %s, count %lu, contains cy %d, enumerated %s\n", sorted([club members]),
               (unsigned long)[members count], [members containsObject:@"cy"], sorted([members allObjects]));
        [members setSet:[NSSet setWithObjects:@"dee", @"eve", nil]];
        [club dump];
        [w dump:"set to dee and eve"];
        printf("members %s\n", sorted([club members]));
        [club removeObserver:w forKeyPath:@"members"];

        /* ---- the set mutations announced by hand, with the prior option ---- */
        [club addObserver:w forKeyPath:@"members" options:both | NSKeyValueObservingOptionPrior context:NULL];
        NSSet *two = [NSSet setWithObjects:@"eve", @"fay", nil];
        [club willChangeValueForKey:@"members" withSetMutation:NSKeyValueUnionSetMutation usingObjects:two];
        [club didChangeValueForKey:@"members" withSetMutation:NSKeyValueUnionSetMutation usingObjects:two];
        [w dump:"a union announced by hand"];
        [club willChangeValueForKey:@"members" withSetMutation:NSKeyValueSetSetMutation usingObjects:two];
        [club didChangeValueForKey:@"members" withSetMutation:NSKeyValueSetSetMutation usingObjects:two];
        [w dump:"setting announced by hand"];
        [club removeObserver:w forKeyPath:@"members"];

        /* ---- through a setter, and straight to an instance variable ---- */
        Shelf *shelf = [[Shelf alloc] init];
        shelf.books = [NSSet setWithObject:@"Emma"];
        shelf.sets = 0;
        [shelf addObserver:w forKeyPath:@"books" options:both context:NULL];
        NSMutableSet *books = [shelf mutableSetValueForKey:@"books"];
        [books addObject:@"Ivanhoe"];
        printf("through the setter: %s, set %ld time(s)\n", sorted(shelf.books), (long)shelf.sets);
        [w dump:"a setter's change"];
        [shelf removeObserver:w forKeyPath:@"books"];
        [shelf addObserver:w forKeyPath:@"loose" options:both context:NULL];
        NSMutableSet *loose = [shelf mutableSetValueForKey:@"loose"];
        [loose addObjectsFromArray:@[ @"pen", @"cup" ]];
        [loose removeObject:@"pen"];
        [loose removeAllObjects];
        [w dump:"an instance variable, changed directly"];
        printf("loose now %s\n", sorted([shelf valueForKey:@"loose"]));
        [shelf removeObserver:w forKeyPath:@"loose"];
        Basket *holder = [[Basket alloc] init];
        holder.items = @[ club ];
        printf("by key path: %s\n", sorted([[holder valueForKeyPath:@"items"][0] mutableSetValueForKeyPath:@"members"]));
        raises("a key with no set", ^{ [[shelf mutableSetValueForKey:@"nothing"] addObject:@"x"]; });

        /* ---- collection operators ---- */
        Item *a = [Item name:@"apple" price:@3 count:2];
        Item *b = [Item name:@"bread" price:@2.5 count:1];
        Item *c = [Item name:@"cheese" price:nil count:4];
        Item *d = [Item name:@"apple" price:@3 count:1];
        a.tags = @[ @"red", @"fruit" ];
        b.tags = @[ @"baked" ];
        c.tags = @[ @"dairy", @"fruit" ];
        d.tags = @[];
        a.colors = [NSSet setWithObjects:@"red", @"green", nil];
        b.colors = [NSSet setWithObject:@"brown"];
        c.colors = [NSSet setWithObjects:@"yellow", @"green", nil];
        d.colors = [NSSet set];
        NSArray *items = @[ a, b, c, d ];
        printf("@count %s, @count.name %s\n", str([items valueForKeyPath:@"@count"]),
               str([items valueForKeyPath:@"@count.name"]));
        printf("@sum.count %s, @sum.price %s\n", str([items valueForKeyPath:@"@sum.count"]),
               str([items valueForKeyPath:@"@sum.price"]));
        printf("@avg.count %s, @avg.price %s\n", str([items valueForKeyPath:@"@avg.count"]),
               str([items valueForKeyPath:@"@avg.price"]));
        printf("@min.price %s, @max.price %s, @max.name %s, @min.name %s\n", str([items valueForKeyPath:@"@min.price"]),
               str([items valueForKeyPath:@"@max.price"]), str([items valueForKeyPath:@"@max.name"]),
               str([items valueForKeyPath:@"@min.name"]));
        printf("@unionOfObjects.name %s\n", [[[items valueForKeyPath:@"@unionOfObjects.name"] componentsJoinedByString:@","] UTF8String]);
        printf("@unionOfObjects.price %s\n", [[[items valueForKeyPath:@"@unionOfObjects.price"] componentsJoinedByString:@","] UTF8String]);
        printf("@distinctUnionOfObjects.name %s\n", sorted([items valueForKeyPath:@"@distinctUnionOfObjects.name"]));
        printf("@unionOfArrays.tags %s\n", [[[items valueForKeyPath:@"@unionOfArrays.tags"] componentsJoinedByString:@","] UTF8String]);
        printf("@distinctUnionOfArrays.tags %s\n", sorted([items valueForKeyPath:@"@distinctUnionOfArrays.tags"]));
        id colors = [[NSSet setWithArray:items] valueForKeyPath:@"@distinctUnionOfSets.colors"];
        printf("@distinctUnionOfSets.colors %s (a set %d)\n", sorted(colors), [colors isKindOfClass:[NSSet class]]);
        NSSet *itemSet = [NSSet setWithArray:items];
        id names = [itemSet valueForKeyPath:@"@distinctUnionOfObjects.name"];
        printf("on a set: @count %s, @sum.count %s, names %s (a set %d)\n", str([itemSet valueForKeyPath:@"@count"]),
               str([itemSet valueForKeyPath:@"@sum.count"]), sorted(names), [names isKindOfClass:[NSSet class]]);
        printf("numbers: @sum.self %s, @avg.self %s, @max.self %s\n", str([@[ @1, @2, @4 ] valueForKeyPath:@"@sum.self"]),
               str([@[ @1, @2, @4 ] valueForKeyPath:@"@avg.self"]), str([@[ @1, @2, @4 ] valueForKeyPath:@"@max.self"]));
        printf("empty: @count %s, @sum %s, @avg %s, @max %s, union %lu\n", str([@[] valueForKeyPath:@"@count"]),
               str([@[] valueForKeyPath:@"@sum.price"]), str([@[] valueForKeyPath:@"@avg.price"]),
               str([@[] valueForKeyPath:@"@max.price"]), (unsigned long)[[@[] valueForKeyPath:@"@unionOfObjects.name"] count]);
        Basket *basket = [[Basket alloc] init];
        basket.items = items;
        printf("through a key: items.@count %s, items.@sum.price %s, items.@max.count %s\n",
               str([basket valueForKeyPath:@"items.@count"]), str([basket valueForKeyPath:@"items.@sum.price"]),
               str([basket valueForKeyPath:@"items.@max.count"]));
        printf("a dictionary's @count: %s\n", str([@{@"a" : @1, @"b" : @2} valueForKey:@"@count"]));
        raises("an unknown operator", ^{ [items valueForKeyPath:@"@median.count"]; });

        /* ---- arrays and sets of objects, by key ---- */
        printf("names %s\n", [[[items valueForKey:@"name"] componentsJoinedByString:@","] UTF8String]);
        printf("prices %s\n", [[[items valueForKey:@"price"] description] UTF8String]);
        printf("set of names %s\n", sorted([itemSet valueForKey:@"name"]));
        [items setValue:@"same" forKey:@"name"];
        printf("each named: %s\n", [[[items valueForKey:@"name"] componentsJoinedByString:@","] UTF8String]);
        [itemSet setValue:@7 forKey:@"count"];
        printf("each counted: %s\n", str([items valueForKeyPath:@"@sum.count"]));

        /* ---- removing an observer that isn't registered ---- */
        Item *e = [Item name:@"egg" price:@1 count:1];
        [e addObserver:w forKeyPath:@"name" options:0 context:NULL];
        [e removeObserver:w forKeyPath:@"name"];
        @try {
            [e removeObserver:w forKeyPath:@"name"];
            printf("removed twice: no exception\n");
        } @catch (NSException *x) {
            NSString *reason = [x reason];
            NSRange p1 = [reason rangeOfString:@" 0x"];
            printf("removed twice: %s, \"%s...\"\n", [[x name] UTF8String],
                   [[reason substringToIndex:p1.location == NSNotFound ? [reason length] : p1.location] UTF8String]);
            NSRange p2 = [reason rangeOfString:@" for the key path"], p3 = [reason rangeOfString:@" because"];
            printf("  then \"%s\"...", [[reason substringWithRange:NSMakeRange(p2.location, [reason rangeOfString:@" 0x"
                                                                                                  options:0
                                                                                                    range:NSMakeRange(p2.location, [reason length] - p2.location)].location - p2.location)] UTF8String]);
            printf(" \"%s\"\n", [[reason substringFromIndex:p3.location] UTF8String]);
        }
        raises("never registered, with a context", ^{ [e removeObserver:w forKeyPath:@"price" context:(void *)1]; });
        [e addObserver:w forKeyPath:@"price" options:0 context:(void *)1];
        raises("the wrong context", ^{ [e removeObserver:w forKeyPath:@"price" context:(void *)2]; });
        raises("the right context", ^{ [e removeObserver:w forKeyPath:@"price" context:(void *)1]; });

        /* ---- predicates ---- */
        Item *f = [Item name:@"Crème brûlée" price:@6.5 count:3];
        f.tags = @[ @"sweet", @"french" ];
        check(@"name == 'Crème brûlée'", f);
        check(@"name ==[c] \"CRÈME BRÛLÉE\"", f);
        check(@"name BEGINSWITH[cd] 'creme'", f);
        check(@"name BEGINSWITH 'creme'", f);
        check(@"name CONTAINS[c] 'BRÛ'", f);
        check(@"name ENDSWITH 'lée'", f);
        check(@"name LIKE 'Cr*br?l*'", f);
        check(@"name LIKE[c] '*CRÈME'", f);
        check(@"price > 6 AND count <= 3", f);
        check(@"price < 6 OR count = 3", f);
        check(@"NOT (price >= 7) && !(count != 3)", f);
        check(@"count BETWEEN {1, 3}", f);
        check(@"count IN {1, 2, 4}", f);
        check(@"'sweet' IN tags", f);
        check(@"tags CONTAINS 'french'", f);
        check(@"ANY tags BEGINSWITH 'fr'", f);
        check(@"ALL tags BEGINSWITH 'fr'", f);
        check(@"NONE tags == 'salty'", f);
        check(@"SELF.count == 3", f);
        check(@"price != nil AND name != NULL", f);
        check(@"TRUEPREDICATE", f);
        check(@"FALSEPREDICATE OR count > 2", f);
        check(@"%K == %@", f, @"name", @"Crème brûlée");
        check(@"count == %d AND price > %f", f, 3, 6.0);
        check(@"name BEGINSWITH %s", f, "Cr");
        check(@"(count == 1 OR count == 3) AND price < 10", f);
        check(@"count == 1 OR (count == 3 AND price < 10)", f);
        NSPredicate *byArray = [NSPredicate predicateWithFormat:@"%K > %@" argumentArray:@[ @"count", @2 ]];
        printf("argument array: %s %d\n", [[byArray predicateFormat] UTF8String], [byArray evaluateWithObject:f]);
        NSPredicate *withVar = [NSPredicate predicateWithFormat:@"count >= $least"];
        printf("variable: %s; %d with 3, %d with 4; substituted %s\n", [[withVar predicateFormat] UTF8String],
               [withVar evaluateWithObject:f substitutionVariables:@{@"least" : @3}],
               [withVar evaluateWithObject:f substitutionVariables:@{@"least" : @4}],
               [[[withVar predicateWithSubstitutionVariables:@{@"least" : @2}] predicateFormat] UTF8String]);
        NSPredicate *block = [NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *bindings) {
            return [[o name] length] > 5;
        }];
        NSArray *pool = @[ [Item name:@"fig" price:@1 count:5], [Item name:@"pepper" price:@2 count:1],
                           [Item name:@"onion" price:@1 count:3], f ];
        printf("filtered: %s\n", [[[pool filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"price < 2"]]
                                     componentsJoinedByString:@","] UTF8String]);
        printf("by a block: %s\n", [[[pool filteredArrayUsingPredicate:block] componentsJoinedByString:@","] UTF8String]);
        NSMutableArray *some = [pool mutableCopy];
        [some filterUsingPredicate:[NSPredicate predicateWithFormat:@"count > 2"]];
        printf("filtered in place: %s\n", [[some componentsJoinedByString:@","] UTF8String]);
        printf("a set: %s\n", sorted([[[NSSet setWithArray:pool] filteredSetUsingPredicate:
                                                                    [NSPredicate predicateWithFormat:@"name CONTAINS 'o'"]]
                                       valueForKey:@"name"]));
        NSPredicate *both2 = [NSCompoundPredicate andPredicateWithSubpredicates:@[
            [NSPredicate predicateWithFormat:@"count > 1"],
            [NSCompoundPredicate orPredicateWithSubpredicates:@[ [NSPredicate predicateWithFormat:@"price == 1"],
                                                                [NSPredicate predicateWithValue:NO] ]]
        ]];
        printf("compound: %s -> %s\n", [[both2 predicateFormat] UTF8String],
               [[[pool filteredArrayUsingPredicate:both2] componentsJoinedByString:@","] UTF8String]);
        printf("not: %s\n", [[[NSCompoundPredicate notPredicateWithSubpredicate:both2] predicateFormat] UTF8String]);
        raises("a format it can't read", ^{ [NSPredicate predicateWithFormat:@"name =="]; });
        raises("an unknown word", ^{ [NSPredicate predicateWithFormat:@"name SOUNDSLIKE 'x'"]; });
    }
    return 0;
}
