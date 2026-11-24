/* SPDX-License-Identifier: GPL-3.0-or-later
 * Key-value observing: registration, the New/Old/Initial/Prior options,
 * changes announced with will/didChangeValueForKey: and made through
 * setValue:forKey:, key paths, contexts, removal, and an observed object
 * going away. */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface Person : NSObject
@property (copy) NSString *name;
@property (retain) Person *friend;
@property int age;
@end
@implementation Person
- (void)rename:(NSString *)n
{
    [self willChangeValueForKey:@"name"];
    _name = [n copy];   /* set straight, so announced around it */
    [self didChangeValueForKey:@"name"];
}
@end

@interface Watcher : NSObject
@property int heard;
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    self.heard++;
    id old = change[NSKeyValueChangeOldKey], new = change[NSKeyValueChangeNewKey];
    printf("%s: kind %d, old %s, new %s%s, context %s\n", [path UTF8String], [change[NSKeyValueChangeKindKey] intValue],
           old ? [[old description] UTF8String] : "-", new ? [[new description] UTF8String] : "-",
           [change[NSKeyValueChangeNotificationIsPriorKey] boolValue] ? " (prior)" : "",
           context ? (const char *)context : "none");
}
@end

int main(void)
{
    @autoreleasepool {
        Person *p = [[Person alloc] init];
        p.name = @"Ada";
        p.age = 36;
        Watcher *w = [[Watcher alloc] init];
        [p addObserver:w forKeyPath:@"name"
               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionInitial
               context:"one"];
        [p rename:@"Grace"];
        [p setValue:@"Hedy" forKey:@"name"];
        [p setValue:@37 forKey:@"age"];   /* nobody watches age yet */
        [p addObserver:w forKeyPath:@"age" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionPrior
               context:"two"];
        [p setValue:@38 forKey:@"age"];
        Person *f = [[Person alloc] init];
        f.name = @"Alan";
        [p addObserver:w forKeyPath:@"friend.name" options:NSKeyValueObservingOptionNew context:NULL];
        [p setValue:f forKey:@"friend"];
        [p removeObserver:w forKeyPath:@"name" context:"one"];
        [p setValue:@"Lise" forKey:@"name"];
        [p removeObserver:w forKeyPath:@"age"];
        [p removeObserver:w forKeyPath:@"friend.name"];
        [p setValue:@39 forKey:@"age"];
        printf("heard %d\n", w.heard);

        /* an observed object that goes away takes its registrations along */
        Person *gone = [[Person alloc] init];
        [gone addObserver:w forKeyPath:@"name" options:0 context:NULL];
        [gone release];
        Person *next = [[Person alloc] init];
        [next setValue:@"new" forKey:@"name"];
        printf("heard %d after the observed object went away\n", w.heard);
        [next release];
        [f release];
        [p release];
        [w release];
    }
    return 0;
}
