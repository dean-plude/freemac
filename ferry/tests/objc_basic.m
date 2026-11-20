/* Objective-C basics: classes, inheritance, super, class methods, ivars,
 * properties, categories, protocols, +load/+initialize, struct and floating
 * point returns, variadic methods, introspection, dynamic classes,
 * swizzling, associated objects, method resolution and forwarding.
 * Built without ARC so it can also test manual memory management. */
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#include <objc/NSObject.h>
#include <objc/runtime.h>
#include <objc/message.h>

typedef struct { double x, y, w, h; } Rect;

@protocol Shape <NSObject>
- (double)area;
@optional
- (const char *)nickname;
@end

@protocol Named
@property (readonly) const char *name;
@end

@interface Animal : NSObject <Named> {
@public
    int legs;
}
@property (nonatomic) int age;
@property (nonatomic, readonly) const char *name;
+ (instancetype)animalWithLegs:(int)n;
- (const char *)sound;
- (const char *)describe;
@end

static char describe_buf[256];

@implementation Animal
+ (void)load { printf("+load Animal\n"); }
+ (void)initialize { printf("+initialize %s\n", class_getName(self)); }
+ (instancetype)animalWithLegs:(int)n
{
    Animal *a = [[self alloc] init];
    a->legs = n;
    return [a autorelease];
}
- (const char *)name { return "animal"; }
- (const char *)sound { return "..."; }
- (const char *)describe
{
    snprintf(describe_buf, sizeof describe_buf, "%s with %d legs says %s", [self name], legs, [self sound]);
    return describe_buf;
}
@end

@interface Dog : Animal
@property (nonatomic) long tricks;
@end

@implementation Dog
+ (void)load { printf("+load Dog\n"); }
- (const char *)name { return "dog"; }
- (const char *)sound { return "woof"; }
- (const char *)describe
{
    static char buf[300];
    snprintf(buf, sizeof buf, "[%s] and knows %ld tricks", [super describe], self.tricks);
    return buf;
}
@end

@interface Square : NSObject <Shape>
@property double side;
- (Rect)bounds;
- (long double)bigArea;
- (float)half:(float)f;
- (double)sum:(int)count, ...;
@end

@implementation Square
- (double)area { return self.side * self.side; }
- (Rect)bounds { return (Rect){0, 0, self.side, self.side}; }
- (long double)bigArea { return (long double)self.side * self.side * 1000; }
- (float)half:(float)f { return f / 2; }
- (double)sum:(int)count, ...
{
    va_list ap;
    va_start(ap, count);
    double total = 0;
    for (int i = 0; i < count; i++)
        total += va_arg(ap, double);
    va_end(ap);
    return total;
}
@end

@interface Animal (Pet)
- (const char *)petName;
@end

@implementation Animal (Pet)
+ (void)load { printf("+load Animal(Pet)\n"); }
- (const char *)petName { return "Rex"; }
@end

@interface Dog (Override)
@end

@implementation Dog (Override)
- (const char *)sound { return "WOOF"; }
@end

/* Method resolution and forwarding */
@interface Resolver : NSObject
@end

@interface Resolver (Dynamic)
- (int)magic;   /* added at run time by +resolveInstanceMethod: */
@end

static int magic_imp(id self, SEL _cmd) { (void)self; (void)_cmd; return 42; }

@implementation Resolver
+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    if (sel == @selector(magic)) {
        class_addMethod(self, sel, (IMP)magic_imp, "i16@0:8");
        printf("resolved %s\n", sel_getName(sel));
        return YES;
    }
    return [super resolveInstanceMethod:sel];
}
@end

@interface Forwarder : NSObject
@property (retain) id target;
@end

@implementation Forwarder
- (id)forwardingTargetForSelector:(SEL)sel
{
    printf("forwarding %s\n", sel_getName(sel));
    return self.target;
}
- (void)dealloc
{
    [_target release];
    [super dealloc];
}
@end

/* Reference counting without ARC */
static int deallocs;

@interface Counted : NSObject
@property (assign) const char *label;
@property (retain) Counted *other;
@end

@implementation Counted
- (id)copyWithZone:(NSZone *)zone
{
    Counted *c = [[Counted alloc] init];
    c.label = self.label;
    return c;
}
- (void)dealloc
{
    printf("dealloc %s\n", self.label ? self.label : "(unnamed)");
    deallocs++;
    [_other release];
    [super dealloc];
}
@end

static const char *swizzled_sound(id self, SEL _cmd) { (void)self; (void)_cmd; return "meow"; }
static char assoc_key;

int main(void)
{
    printf("-- classes\n");
    Animal *a = [Animal animalWithLegs:4];
    printf("%s\n", [a describe]);
    Dog *d = [[Dog alloc] init];
    d->legs = 4;
    d.tricks = 3;
    d.age = 5;
    printf("%s, age %d\n", [d describe], d.age);
    printf("isKindOfClass Animal: %d, isMemberOfClass Animal: %d\n", [d isKindOfClass:[Animal class]],
           [d isMemberOfClass:[Animal class]]);
    printf("superclass of Dog: %s\n", class_getName([Dog superclass]));
    printf("Dog subclass of Animal: %d, of Square: %d\n", [Dog isSubclassOfClass:[Animal class]],
           [Dog isSubclassOfClass:[Square class]]);
    printf("respondsToSelector sound: %d, fly: %d\n", [d respondsToSelector:@selector(sound)],
           [d respondsToSelector:sel_registerName("fly")]);
    printf("instancesRespondToSelector petName: %d\n", [Dog instancesRespondToSelector:@selector(petName)]);
    printf("category: %s\n", [d petName]);

    printf("-- protocols\n");
    Square *s = [Square new];
    s.side = 3;
    printf("conforms Shape: %d, NSObject: %d, Named: %d\n", [s conformsToProtocol:@protocol(Shape)],
           [s conformsToProtocol:@protocol(NSObject)], [s conformsToProtocol:@protocol(Named)]);
    printf("Animal conforms Named: %d, Dog: %d\n", [Animal conformsToProtocol:@protocol(Named)],
           [Dog conformsToProtocol:@protocol(Named)]);
    printf("protocol name: %s, optional nickname: %d\n", protocol_getName(@protocol(Shape)),
           [s respondsToSelector:@selector(nickname)]);
    Protocol *shape = objc_getProtocol("Shape");
    struct objc_method_description md = protocol_getMethodDescription(shape, @selector(area), YES, YES);
    printf("Shape requires %s (%s)\n", sel_getName(md.name), md.types);

    printf("-- return values\n");
    printf("area %.1f\n", [s area]);
    Rect r = [s bounds];
    printf("bounds %.0f %.0f %.0f %.0f\n", r.x, r.y, r.w, r.h);
    printf("bigArea %.0Lf\n", [s bigArea]);
    printf("half %.2f\n", [s half:5.0f]);
    printf("sum %.1f\n", [s sum:3, 1.5, 2.5, 3.0]);
    Square *none = nil;
    Rect zero = [none bounds];
    printf("nil: %.1f %d %.0Lf\n", [none area], (int)[none respondsToSelector:@selector(area)], [none bigArea]);
    (void)zero;

    printf("-- introspection\n");
    unsigned n;
    Ivar *ivars = class_copyIvarList([Animal class], &n);
    for (unsigned i = 0; i < n; i++)
        printf("ivar %s %s at %ld\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]),
               (long)ivar_getOffset(ivars[i]));
    free(ivars);
    objc_property_t *props = class_copyPropertyList([Square class], &n);
    for (unsigned i = 0; i < n; i++)
        printf("property %s %s\n", property_getName(props[i]), property_getAttributes(props[i]));
    free(props);
    char *t = property_copyAttributeValue(class_getProperty([Square class], "side"), "T");
    printf("side type %s\n", t);
    free(t);
    Method m = class_getInstanceMethod([Square class], @selector(half:));
    char ret[16], arg[16];
    method_getReturnType(m, ret, sizeof ret);
    method_getArgumentType(m, 2, arg, sizeof arg);
    printf("half: %u args, returns %s, takes %s\n", method_getNumberOfArguments(m), ret, arg);
    printf("instance size Animal %zu Dog %zu\n", class_getInstanceSize([Animal class]),
           class_getInstanceSize([Dog class]));
    printf("objc_getClass Dog: %d, metaclass: %d\n", objc_getClass("Dog") == [Dog class],
           class_isMetaClass(object_getClass([Dog class])));
    int (*imp)(id, SEL, float) = (void *)[s methodForSelector:@selector(half:)];
    printf("via IMP %.1f\n", ((float (*)(id, SEL, float))imp)(s, @selector(half:), 9));

    printf("-- objc_msgSend by hand\n");
    const char *(*send)(id, SEL) = (const char *(*)(id, SEL))objc_msgSend;
    printf("%s\n", send(d, @selector(sound)));
    struct objc_super sup = {d, [Animal class]};
    const char *(*sendsuper)(struct objc_super *, SEL) = (const char *(*)(struct objc_super *, SEL))objc_msgSendSuper;
    printf("super: %s\n", sendsuper(&sup, @selector(sound)));

    printf("-- dynamic classes\n");
    Class Cat = objc_allocateClassPair([Animal class], "Cat", 0);
    class_addIvar(Cat, "lives", sizeof(int), 2, "i");
    class_addMethod(Cat, @selector(sound), (IMP)swizzled_sound, "*16@0:8");
    objc_registerClassPair(Cat);
    id cat = [[Cat alloc] init];
    object_setIvar(cat, class_getInstanceVariable(Cat, "lives"), (id)9);
    printf("%s, lives %ld\n", [cat describe], (long)object_getIvar(cat, class_getInstanceVariable(Cat, "lives")));
    printf("Cat is an Animal: %d\n", [cat isKindOfClass:[Animal class]]);

    printf("-- swizzling\n");
    Method m1 = class_getInstanceMethod([Dog class], @selector(sound));
    Method m2 = class_getInstanceMethod([Dog class], @selector(name));
    method_exchangeImplementations(m1, m2);
    printf("sound %s, name %s\n", [d sound], [d name]);
    method_exchangeImplementations(m1, m2);
    IMP old = method_setImplementation(m1, (IMP)swizzled_sound);
    printf("sound %s\n", [d sound]);
    method_setImplementation(m1, old);
    printf("sound %s\n", [d sound]);

    printf("-- associated objects\n");
    Counted *tag = [[Counted alloc] init];
    tag.label = "tag";
    objc_setAssociatedObject(d, &assoc_key, tag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [tag release];
    printf("associated: %s\n", ((Counted *)objc_getAssociatedObject(d, &assoc_key)).label);
    objc_setAssociatedObject(d, &assoc_key, nil, OBJC_ASSOCIATION_ASSIGN);

    printf("-- resolution and forwarding\n");
    Resolver *res = [Resolver new];
    printf("magic %d\n", [res magic]);
    printf("magic again %d\n", [res magic]);
    Forwarder *f = [Forwarder new];
    f.target = d;
    printf("forwarded: %s\n", [(Dog *)f sound]);
    [f release];
    [res release];

    printf("-- manual reference counting\n");
    Counted *c1 = [[Counted alloc] init];
    c1.label = "one";
    printf("retainCount %lu\n", (unsigned long)[c1 retainCount]);
    [c1 retain];
    printf("retainCount %lu\n", (unsigned long)[c1 retainCount]);
    [c1 release];
    Counted *c2 = [c1 copy];
    printf("copy label %s, same object %d\n", c2.label, c1 == c2);
    c1.other = c2;
    [c2 release];
    [c1 release];
    printf("deallocs %d\n", deallocs);
    @autoreleasepool {
        Counted *c3 = [[[Counted alloc] init] autorelease];
        c3.label = "pooled";
        printf("before pop\n");
    }
    printf("after pop, deallocs %d\n", deallocs);

    [d release];
    [s release];
    [cat release];
    return 0;
}
