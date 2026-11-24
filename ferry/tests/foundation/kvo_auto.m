/* SPDX-License-Identifier: GPL-3.0-or-later
 * Automatic key-value observing (Ferry 0.17.0): the hidden subclass a Mac
 * makes for an observed object, whose setters (of objects, scalars and
 * structs, set<Key>: and _set<Key>:) and indexed to-many mutators announce
 * their changes; -class still answering the original class;
 * automaticallyNotifiesObserversForKey: and ...Of<Key> keeping a key
 * quiet; dependent keys (keyPathsForValuesAffecting<Key> and the general
 * method, through to-one key paths, dependents of dependents); key paths
 * followed as their objects change; the New, Old, Initial and Prior
 * options; mutableArrayValueForKey: through accessors, a setter and an
 * instance variable, with insertion, removal and replacement at indexes;
 * and key-value coding's search for accessors and instance variables. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

@interface Person : NSObject {
    int _shoeSize;       /* no accessors: reached as an instance variable */
    NSString *_nickname;
}
@property (copy) NSString *name, *first, *last;
@property (retain) Person *friend;
@property BOOL awake;
@property int age;
@property double height;
@property NSRect frame;
@property NSPoint spot;
@property (copy) NSString *secret;   /* kept quiet by automaticallyNotifiesObserversOfSecret */
@property (copy) NSString *code;     /* kept quiet by automaticallyNotifiesObserversForKey: */
@property (readonly) NSString *fullName, *greeting, *friendLabel;
@property (retain) NSMutableArray *items;   /* with indexed accessors */
@property (retain) NSArray *tags;           /* with a setter only */
@end

@implementation Person {
    NSString *_hidden;
    NSMutableArray *_notes;   /* only an instance variable */
}
+ (BOOL)automaticallyNotifiesObserversOfSecret { return NO; }
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:@"code"])
        return NO;
    return [super automaticallyNotifiesObserversForKey:key];
}
- (NSString *)fullName { return [NSString stringWithFormat:@"%@ %@", _first ?: @"?", _last ?: @"?"]; }
+ (NSSet *)keyPathsForValuesAffectingFullName { return [NSSet setWithObjects:@"first", @"last", nil]; }
- (NSString *)greeting { return [@"Hello, " stringByAppendingString:[self fullName]]; }
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    if ([key isEqualToString:@"greeting"])
        return [NSSet setWithObject:@"fullName"];   /* a dependent of a dependent */
    return [super keyPathsForValuesAffectingValueForKey:key];
}
- (NSString *)friendLabel { return [NSString stringWithFormat:@"friend of %@", _friend.name ?: @"nobody"]; }
+ (NSSet *)keyPathsForValuesAffectingFriendLabel { return [NSSet setWithObject:@"friend.name"]; }
- (NSString *)hidden { return _hidden; }
- (void)_setHidden:(NSString *)h   /* KVC's second choice of setter */
{
    [_hidden release];
    _hidden = [h copy];
}
- (NSUInteger)countOfItems { return [_items count]; }
- (void)insertObject:(id)o inItemsAtIndex:(NSUInteger)i { [_items insertObject:o atIndex:i]; }
- (void)removeObjectFromItemsAtIndex:(NSUInteger)i { [_items removeObjectAtIndex:i]; }
- (void)replaceObjectInItemsAtIndex:(NSUInteger)i withObject:(id)o { [_items replaceObjectAtIndex:i withObject:o]; }
- (NSArray *)notes { return _notes; }
@end

@interface Student : Person
@property (copy) NSString *school;
@end
@implementation Student
- (void)setName:(NSString *)name { [super setName:[name uppercaseString]]; }
@end

@interface Watcher : NSObject
@property int heard;
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    self.heard++;
    id cls = [object isKindOfClass:[NSDictionary class]] ? @"a dictionary" : (id)[object class];
    NSMutableString *s = [NSMutableString stringWithFormat:@"  %@ of %@:", path, cls];
    static const char *kinds[] = {"?", "setting", "insertion", "removal", "replacement"};
    [s appendFormat:@" %s", kinds[[change[NSKeyValueChangeKindKey] intValue] & 7]];
    if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue])
        [s appendString:@" (prior)"];
    NSIndexSet *at = change[NSKeyValueChangeIndexesKey];
    if (at) {
        [s appendString:@" at"];
        [at enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [s appendFormat:@" %lu", (unsigned long)i]; }];
    }
    for (NSString *k in @[ NSKeyValueChangeOldKey, NSKeyValueChangeNewKey ]) {
        id v = change[k];
        if (!v)
            continue;
        NSString *d = [v isKindOfClass:[NSArray class]] ? [v componentsJoinedByString:@","] : [v description];
        if ([v isKindOfClass:[NSValue class]] && ![v isKindOfClass:[NSNumber class]]) {
            const char *t = [v objCType];
            d = strstr(t, "Rect") ? NSStringFromRect([v rectValue]) : NSStringFromPoint([v pointValue]);
        }
        [s appendFormat:@", %@ %@", k, d];
    }
    if (context)
        [s appendFormat:@" [%s]", (const char *)context];
    printf("%s\n", [s UTF8String]);
}
@end

/* A message with its object's address taken out. */
static NSString *unpointed(NSString *s)
{
    NSRange r = [s rangeOfString:@" 0x"];
    if (r.location == NSNotFound)
        return s;
    NSRange end = [s rangeOfString:@">" options:0 range:NSMakeRange(r.location, [s length] - r.location)];
    return [[[s substringToIndex:r.location] stringByAppendingString:@" 0x..."] stringByAppendingString:[s substringFromIndex:end.location]];
}

static void show(const char *what, Watcher *w, int before)
{
    printf("%s: %d heard\n", what, w.heard - before);
}

int main(void)
{
    @autoreleasepool {
        Watcher *w = [[Watcher alloc] init];
        Person *p = [[Person alloc] init];
        p.name = @"Ada";
        printf("before: class %s, isa %s\n", class_getName([p class]), object_getClassName(p));

        /* the hidden subclass, and setters of every kind announcing their changes */
        NSKeyValueObservingOptions both = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
        for (NSString *k in @[ @"name", @"awake", @"age", @"height", @"frame", @"spot", @"hidden" ])
            [p addObserver:w forKeyPath:k options:both context:NULL];
        printf("observed: class %s, isa %s, member of Person %d, kind of Person %d, superclass of isa %s\n",
               class_getName([p class]), object_getClassName(p), [p isMemberOfClass:[Person class]],
               [p isKindOfClass:[Person class]], class_getName(class_getSuperclass(object_getClass(p))));
        printf("description: %s\n", [[p description] hasPrefix:@"<Person: 0x"] ? "<Person: 0x...>" : [[p description] UTF8String]);
        printf("responds to setName: %d; its setter is the subclass's %d\n", [p respondsToSelector:@selector(setName:)],
               class_getMethodImplementation(object_getClass(p), @selector(setName:)) !=
                   class_getMethodImplementation([Person class], @selector(setName:)));
        int n = w.heard;
        p.name = @"Grace";
        p.awake = YES;
        p.age = 37;
        p.height = 1.68;
        p.frame = NSMakeRect(1, 2, 3, 4);
        p.spot = NSMakePoint(5, 6);
        [p setValue:@"shy" forKey:@"hidden"];   /* through _setHidden: */
        show("setters", w, n);
        printf("values kept: %s %d %d %.2f %s %s %s\n", [p.name UTF8String], p.awake, p.age, p.height,
               [NSStringFromRect(p.frame) UTF8String], [NSStringFromPoint(p.spot) UTF8String], [[p hidden] UTF8String]);

        /* key-value coding goes through the setter, which announces it once */
        n = w.heard;
        [p setValue:@"Lise" forKey:@"name"];
        [p setValue:@40 forKey:@"age"];
        [p setValue:[NSValue valueWithRect:NSMakeRect(0, 0, 10, 10)] forKey:@"frame"];
        show("key-value coding", w, n);

        /* keys a class keeps quiet: only its own announcements are heard */
        [p addObserver:w forKeyPath:@"secret" options:NSKeyValueObservingOptionNew context:"secret"];
        [p addObserver:w forKeyPath:@"code" options:NSKeyValueObservingOptionNew context:"code"];
        n = w.heard;
        p.secret = @"s1";
        p.code = @"c1";
        [p setValue:@"s2" forKey:@"secret"];
        show("quiet keys, by their setters", w, n);
        [p willChangeValueForKey:@"secret"];
        p.secret = @"s3";
        [p didChangeValueForKey:@"secret"];
        show("quiet keys, announced", w, n);

        /* an instance variable with no accessors, set by key-value coding */
        [p addObserver:w forKeyPath:@"shoeSize" options:both context:NULL];
        [p addObserver:w forKeyPath:@"nickname" options:both context:NULL];
        n = w.heard;
        [p setValue:@42 forKey:@"shoeSize"];
        [p setValue:@"Addie" forKey:@"nickname"];
        show("instance variables", w, n);
        printf("read back: shoe size %d, nickname %s\n", [[p valueForKey:@"shoeSize"] intValue],
               [[p valueForKey:@"nickname"] UTF8String]);

        /* the last observer gone: the subclass stays, and nobody hears */
        for (NSString *k in @[ @"name", @"awake", @"age", @"height", @"frame", @"spot", @"hidden", @"secret",
                               @"code", @"shoeSize", @"nickname" ])
            [p removeObserver:w forKeyPath:k];
        n = w.heard;
        p.name = @"quiet";
        p.age = 1;
        show("after removing every observer", w, n);
        printf("isa after: %s\n", object_getClassName(p));

        /* a subclass gets a hidden subclass of its own; its setter calling
         * super's is announced once */
        Student *s = [[Student alloc] init];
        [s addObserver:w forKeyPath:@"name" options:NSKeyValueObservingOptionNew context:NULL];
        [s addObserver:w forKeyPath:@"school" options:NSKeyValueObservingOptionNew context:NULL];
        n = w.heard;
        s.name = @"bob";
        s.school = @"Ferry High";
        show("a subclass", w, n);
        printf("student: class %s, isa %s\n", class_getName([s class]), object_getClassName(s));
        [s removeObserver:w forKeyPath:@"name"];
        [s removeObserver:w forKeyPath:@"school"];

        /* dependent keys */
        printf("dependent keys:\n");
        Person *d = [[Person alloc] init];
        d.first = @"Ada";
        d.last = @"Byron";
        [d addObserver:w forKeyPath:@"fullName" options:both | NSKeyValueObservingOptionPrior context:"full"];
        [d addObserver:w forKeyPath:@"greeting" options:NSKeyValueObservingOptionNew context:"greeting"];
        d.last = @"Lovelace";
        d.first = @"Augusta";
        [d removeObserver:w forKeyPath:@"fullName"];
        d.first = @"Ada";
        [d removeObserver:w forKeyPath:@"greeting"];
        n = w.heard;
        d.first = @"none";
        show("after removing both", w, n);

        /* a dependency through a to-one key path */
        Person *f1 = [[Person alloc] init], *f2 = [[Person alloc] init];
        f1.name = @"Alan";
        f2.name = @"Kurt";
        d.friend = f1;
        [d addObserver:w forKeyPath:@"friendLabel" options:both context:"label"];
        f1.name = @"Alonzo";
        d.friend = f2;
        f1.name = @"not followed";
        f2.name = @"Emmy";
        d.friend = nil;
        [d removeObserver:w forKeyPath:@"friendLabel"];

        /* key paths: the observation follows the path's objects */
        printf("key paths:\n");
        d.friend = f1;
        [d addObserver:w forKeyPath:@"friend.name"
               options:both | NSKeyValueObservingOptionInitial
               context:"path"];
        f1.name = @"Alan";
        d.friend = f2;
        n = w.heard;
        f1.name = @"old friend, not heard";
        show("the old friend's change", w, n);
        f2.name = @"Hedy";
        d.friend = nil;
        d.friend = f1;
        [d removeObserver:w forKeyPath:@"friend.name"];
        n = w.heard;
        f1.name = @"unwatched";
        show("after removal", w, n);

        /* the to-many mutators and mutableArrayValueForKey: */
        printf("to-many:\n");
        Person *c = [[Person alloc] init];
        c.items = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
        [c addObserver:w forKeyPath:@"items" options:both context:"items"];
        NSMutableArray *items = [c mutableArrayValueForKey:@"items"];
        [items addObject:@"c"];
        [items removeObjectAtIndex:0];
        [items replaceObjectAtIndex:0 withObject:@"B"];
        [c insertObject:@"z" inItemsAtIndex:0];   /* the accessor itself announces it */
        printf("  items now %s (%lu through the proxy)\n", [[c.items componentsJoinedByString:@","] UTF8String],
               (unsigned long)[items count]);
        [c removeObserver:w forKeyPath:@"items"];

        [c addObserver:w forKeyPath:@"notes" options:both context:"notes"];
        NSMutableArray *notes = [c mutableArrayValueForKey:@"notes"];
        [notes addObject:@"one"];
        [notes addObject:@"two"];
        [notes insertObject:@"zero" atIndex:0];
        [notes replaceObjectAtIndex:1 withObject:@"ONE"];
        [notes removeLastObject];
        printf("  notes now %s\n", [[[c notes] componentsJoinedByString:@","] UTF8String]);
        [c removeObserver:w forKeyPath:@"notes"];

        c.tags = @[ @"x" ];
        [c addObserver:w forKeyPath:@"tags" options:both context:"tags"];
        [[c mutableArrayValueForKey:@"tags"] addObject:@"y"];
        printf("  tags now %s\n", [[c.tags componentsJoinedByString:@","] UTF8String]);
        [c removeObserver:w forKeyPath:@"tags"];

        /* announced by hand, with indexes */
        [c addObserver:w forKeyPath:@"items" options:both | NSKeyValueObservingOptionPrior context:"by hand"];
        NSIndexSet *at = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)];
        [c willChange:NSKeyValueChangeRemoval valuesAtIndexes:at forKey:@"items"];
        [c.items removeObjectsAtIndexes:at];
        [c didChange:NSKeyValueChangeRemoval valuesAtIndexes:at forKey:@"items"];
        [c removeObserver:w forKeyPath:@"items"];

        /* a change announced inside another of the same key keeps each old value */
        printf("nested:\n");
        [c addObserver:w forKeyPath:@"name" options:both context:"nested"];
        c.name = @"one";
        [c willChangeValueForKey:@"name"];
        c.name = @"two";
        [c didChangeValueForKey:@"name"];
        [c removeObserver:w forKeyPath:@"name"];

        /* dictionaries and the user's defaults */
        printf("dictionaries and defaults:\n");
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObject:@"v1" forKey:@"k"];
        [dict addObserver:w forKeyPath:@"k" options:both context:"dict"];
        [dict setValue:@"v2" forKey:@"k"];
        [dict removeObserver:w forKeyPath:@"k"];
        printf("  dictionary still a %s\n", [dict isKindOfClass:[NSMutableDictionary class]] ? "mutable dictionary" : "?");
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud addObserver:w forKeyPath:@"FerryKVOTest" options:both context:"defaults"];
        [ud setObject:@"on" forKey:@"FerryKVOTest"];
        [ud removeObjectForKey:@"FerryKVOTest"];
        [ud removeObserver:w forKeyPath:@"FerryKVOTest"];

        /* key-value coding's search */
        printf("key-value coding:\n");
        NSDictionary *vals = [d dictionaryWithValuesForKeys:@[ @"first", @"friend", @"age" ]];
        printf("  values: first %s, friend %s, age %s\n", [vals[@"first"] UTF8String], [[vals[@"friend"] name] UTF8String],
               [[vals[@"age"] description] UTF8String]);
        [d setValuesForKeysWithDictionary:@{@"first" : @"Mary", @"age" : @7}];
        printf("  set from a dictionary: %s, %d\n", [d.first UTF8String], d.age);
        printf("  a rect by its getter: %s\n", [NSStringFromRect([[p valueForKey:@"frame"] rectValue]) UTF8String]);
        @try {
            [p setValue:nil forKey:@"age"];
        } @catch (NSException *e) {
            printf("  nil for a scalar: %s\n", [[e name] UTF8String]);
        }
        @try {
            [p valueForKey:@"nothing"];
        } @catch (NSException *e) {
            printf("  %s: %s\n", [[e name] UTF8String], [unpointed([e reason]) UTF8String]);
        }
        @try {
            [p setValue:@1 forKey:@"nothing"];
        } @catch (NSException *e) {
            printf("  %s: %s\n", [[e name] UTF8String], [unpointed([e reason]) UTF8String]);
        }
        printf("heard %d in all\n", w.heard);
        [c release];
        [d release];
        [f1 release];
        [f2 release];
        [s release];
        [p release];
        [w release];
    }
    return 0;
}
