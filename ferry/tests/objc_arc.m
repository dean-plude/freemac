/* Automatic reference counting: objects are freed at the right moment,
 * weak references become nil, autorelease pools drain, strong and copy
 * properties, blocks that capture objects, __block variables,
 * imp_implementationWithBlock and @synchronized. */
#include <stdio.h>
#include <objc/NSObject.h>
#include <objc/runtime.h>

@interface Thing : NSObject <NSObject>
@property (nonatomic, assign) const char *name;
@property (nonatomic, strong) Thing *child;
@property (nonatomic, weak) Thing *parent;
@property (copy) Thing *copied;
@property (atomic, strong) Thing *shared;
+ (instancetype)thingNamed:(const char *)name;
@end

static int alive;

@implementation Thing
+ (instancetype)thingNamed:(const char *)name
{
    Thing *t = [[self alloc] init];
    t.name = name;
    return t;
}
- (instancetype)init
{
    if ((self = [super init]))
        alive++;
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    static char names[8][32];
    static int next;
    char *n = names[next++ % 8];
    snprintf(n, 32, "copy of %s", self.name);
    return [Thing thingNamed:n];
}
- (void)dealloc
{
    alive--;
    printf("dealloc %s\n", self.name);
}
@end

static Thing *make_autoreleased(const char *name)
{
    return [Thing thingNamed:name];
}

typedef int (^Counter)(void);

static Counter make_counter(void)
{
    __block int count = 0;
    Thing *t = [Thing thingNamed:"captured"];
    return ^{
        count++;
        printf("counter %d (%s)\n", count, t.name);
        return count;
    };
}

int main(void)
{
    printf("-- scope\n");
    {
        Thing *a = [Thing thingNamed:"a"];
        printf("made %s, alive %d\n", a.name, alive);
    }
    printf("after scope, alive %d\n", alive);

    printf("-- strong and weak\n");
    Thing *parent = [Thing thingNamed:"parent"];
    __weak Thing *weakChild;
    {
        Thing *child = [Thing thingNamed:"child"];
        child.parent = parent;
        parent.child = child;
        weakChild = child;
    }
    printf("child alive through parent: %s, its parent %s\n", weakChild.name, weakChild.parent.name);
    parent.child = nil;
    printf("weak child now %s\n", weakChild ? "set" : "nil");
    __weak Thing *weakParent = parent;
    parent = nil;
    printf("weak parent now %s, alive %d\n", weakParent ? "set" : "nil", alive);

    printf("-- autorelease pool\n");
    @autoreleasepool {
        __autoreleasing Thing *x = make_autoreleased("pooled");
        __weak Thing *w = x;
        printf("in pool: %s\n", w ? w.name : "nil");
    }
    printf("after pool, alive %d\n", alive);

    printf("-- copy and atomic properties\n");
    Thing *orig = [Thing thingNamed:"orig"];
    Thing *holder = [Thing thingNamed:"holder"];
    holder.copied = orig;
    holder.shared = orig;
    printf("copied: %s, shared same: %d\n", holder.copied.name, holder.shared == orig);
    orig = nil;
    holder = nil;
    printf("alive %d\n", alive);

    printf("-- blocks\n");
    Counter c = make_counter();
    c();
    c();
    Counter c2 = [c copy];
    c2();
    printf("same heap block: %d\n", c == c2);
    c = nil;
    c2 = nil;
    printf("alive %d\n", alive);
    int (^global)(int) = ^(int x) { return x * 2; };
    printf("global block %d\n", global(21));
    __block Thing *swap = [Thing thingNamed:"first"];
    void (^replace)(void) = ^{ swap = [Thing thingNamed:"second"]; };
    replace();
    printf("swap is %s\n", swap.name);
    replace = nil;
    swap = nil;
    void (^check)(void);
    {
        Thing *temp = [Thing thingNamed:"temp"];
        __weak Thing *w = temp;
        check = ^{ printf("block sees %s\n", w ? w.name : "nil"); };
        check();
    }
    check();
    check = nil;

    printf("-- imp_implementationWithBlock\n");
    IMP imp = imp_implementationWithBlock(^(Thing *self, int n) {
        printf("%s got %d\n", self.name, n);
        return n + 1;
    });
    class_addMethod([Thing class], sel_registerName("bump:"), imp, "i20@0:8i16");
    Thing *t = [Thing thingNamed:"bumper"];
    int r = ((int (*)(id, SEL, int))[t methodForSelector:sel_registerName("bump:")])(t, sel_registerName("bump:"), 4);
    printf("returned %d\n", r);
    t = nil;

    printf("-- @synchronized\n");
    Thing *lock = [Thing thingNamed:"lock"];
    @synchronized(lock) {
        @synchronized(lock) {
            printf("inside twice\n");
        }
    }
    lock = nil;
    printf("end, alive %d\n", alive);
    return 0;
}
