/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSMethodSignature, NSInvocation and message forwarding: signatures read
 * from type encodings; invocations of methods taking and returning
 * integers of each size, pointers, objects, blocks, C strings, floats,
 * doubles, a long double, small structs (in general registers, vector
 * registers or both), large structs (in memory) and arguments that spill
 * onto the stack; retainArguments; return values set and read back; a
 * proxy (NSProxy) and an NSObject subclass catching messages with
 * forwardInvocation:, for instance and class methods; forwarding targets
 * still going first; exceptions thrown through invoke and forwarding;
 * NSUndoManager's prepareWithInvocationTarget: with groups, undo and redo;
 * and last, a message nothing implements, which stops the program. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

typedef struct { double d; long l; } Mixed;      /* xmm0, then rax */
typedef struct { int i; float f; } IntFloat;     /* one general register */
typedef struct { float x, y, z; } Vec3;          /* xmm0 (x, y), xmm1 (z) */
typedef struct { long a, b, c; } Big;            /* memory */
typedef struct { char c; short s; } Tiny;

@interface Calc : NSObject
@property int calls;
@end

@implementation Calc
- (int)add:(int)a to:(int)b { self.calls++; return a + b; }
- (char)negate:(char)c { return (char)-c; }
- (unsigned short)half:(unsigned short)u { return u / 2; }
- (BOOL)isPositive:(int)v { return v > 0; }
- (long long)sumOf:(long)a :(long)b :(long)c :(long)d :(long)e :(long)f :(short)g :(unsigned char)h
{
    return a + b + c + d + e + f + g + h;
}
- (double)mix:(int)i f:(float)f d:(double)d
{
    return i + f + d;
}
- (double)tenDoubles:(double)a :(double)b :(double)c :(double)d :(double)e :(double)f :(double)g :(double)h
                    :(double)i :(float)j
{
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + 9 * i + 10 * j;
}
- (float)fsum:(float)a :(float)b { return a + b; }
- (NSRect)rectAt:(NSPoint)p size:(NSSize)s { return NSMakeRect(p.x, p.y, s.width, s.height); }
- (NSPoint)move:(NSPoint)p by:(CGFloat)d { return NSMakePoint(p.x + d, p.y - d); }
- (NSRange)shift:(NSRange)r by:(NSUInteger)n { return NSMakeRange(r.location + n, r.length * 2); }
- (Mixed)mixed:(Mixed)m { m.d *= 2; m.l += 1; return m; }
- (IntFloat)intFloat:(IntFloat)v { v.i *= 3; v.f /= 2; return v; }
- (Vec3)scale:(Vec3)v by:(float)k { v.x *= k; v.y *= k; v.z *= k; return v; }
- (long)sumBig:(Big)b plus:(int)x { return b.a + b.b + b.c + x; }
- (Big)bigFrom:(long)x { Big b = {x, x * 10, x * 100}; return b; }
- (Tiny)tiny:(Tiny)t { t.c++; t.s--; return t; }
- (long double)third:(long double)x { return x / 3; }
- (id)echo:(id)o { return o; }
- (NSString *)join:(NSString *)a with:(const char *)b { return [NSString stringWithFormat:@"%@+%s", a, b]; }
- (int)call:(int (^)(int))block with:(int)v { return block(v); }
- (SEL)selectorBack:(SEL)s { return s; }
- (void)fail:(NSString *)why { [NSException raise:@"CalcFailure" format:@"failed: %@", why]; }
- (oneway void)ping {}
+ (int)classAdd:(int)a { return a + 1000; }
@end

/* Stands in for a Calc: logs each message, then sends it on. */
@interface Logger : NSProxy {
@public
    id target;
    int forwarded;
}
@end
@implementation Logger
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [target methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)inv
{
    forwarded++;
    printf("  [proxy] %s\n", sel_getName([inv selector]));
    [inv invokeWithTarget:target];
}
@end

/* Answers unknown messages itself, with return values it makes up. */
@interface Recorder : NSObject
@property (retain) NSMutableArray *log;
@end
@implementation Recorder
- (id)forwardingTargetForSelector:(SEL)sel
{
    if (sel == @selector(add:to:))
        return [[[Calc alloc] init] autorelease];
    return nil;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    NSMethodSignature *s = [super methodSignatureForSelector:sel];
    if (s)
        return s;
    if (sel == @selector(frame))
        return [NSMethodSignature signatureWithObjCTypes:"{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8"];
    if (sel == @selector(ratio))
        return [NSMethodSignature signatureWithObjCTypes:"d16@0:8"];
    if (sel == @selector(grade))
        return [NSMethodSignature signatureWithObjCTypes:"c16@0:8"];
    if (sel == @selector(name))
        return [NSMethodSignature signatureWithObjCTypes:"@16@0:8"];
    if (sel == @selector(note:count:))
        return [NSMethodSignature signatureWithObjCTypes:"v28@0:8@16i24"];
    if (sel == @selector(boom))
        return [NSMethodSignature signatureWithObjCTypes:"v16@0:8"];
    return nil;
}
- (void)forwardInvocation:(NSInvocation *)inv
{
    SEL sel = [inv selector];
    [self.log addObject:NSStringFromSelector(sel)];
    if (sel == @selector(frame)) {
        NSRect r = NSMakeRect(1, 2, 30, 40);
        [inv setReturnValue:&r];
    } else if (sel == @selector(ratio)) {
        double d = 0.625;
        [inv setReturnValue:&d];
    } else if (sel == @selector(grade)) {
        char c = -7;
        [inv setReturnValue:&c];
    } else if (sel == @selector(name)) {
        NSString *s = @"recorded";
        [inv setReturnValue:&s];
    } else if (sel == @selector(note:count:)) {
        NSString *s;
        int n;
        [inv getArgument:&s atIndex:2];
        [inv getArgument:&n atIndex:3];
        printf("  note: %s x%d\n", [s UTF8String], n);
    } else if (sel == @selector(boom)) {
        [NSException raise:@"Boom" format:@"raised in forwardInvocation:"];
    } else {
        [super forwardInvocation:inv];
    }
}
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    if (sel == @selector(classTwice:))
        return [NSMethodSignature signatureWithObjCTypes:"q24@0:8q16"];
    return [super methodSignatureForSelector:sel];
}
+ (void)forwardInvocation:(NSInvocation *)inv
{
    long long v;
    [inv getArgument:&v atIndex:2];
    v *= 2;
    [inv setReturnValue:&v];
}
@end

@interface Recorder (Unknown)
- (NSRect)frame;
- (double)ratio;
- (char)grade;
- (NSString *)name;
- (void)note:(NSString *)s count:(int)n;
- (void)boom;
- (int)add:(int)a to:(int)b;
+ (long long)classTwice:(long long)v;
@end

/* A document whose changes are undone through prepareWithInvocationTarget:. */
@interface Doc : NSObject
@property (retain) NSUndoManager *undo;
@property (nonatomic) int size;
@property (nonatomic) NSRect frame;
@property (nonatomic, copy) NSString *title;
@end
@implementation Doc
- (void)setSize:(int)size
{
    [(Doc *)[self.undo prepareWithInvocationTarget:self] setSize:_size];
    _size = size;
}
- (void)setFrame:(NSRect)frame
{
    [[self.undo prepareWithInvocationTarget:self] setFrame:_frame];
    _frame = frame;
}
- (void)setTitle:(NSString *)title
{
    [(Doc *)[self.undo prepareWithInvocationTarget:self] setTitle:_title];
    [_title release];
    _title = [title copy];
}
- (void)dealloc
{
    [_title release];
    [_undo release];
    [super dealloc];
}
- (void)show:(const char *)when
{
    printf("  %s: size %d, frame {%g, %g, %g, %g}, title %s\n", when, _size, _frame.origin.x, _frame.origin.y,
           _frame.size.width, _frame.size.height, _title ? [_title UTF8String] : "(none)");
}
@end

static NSInvocation *inv_for(id target, SEL sel)
{
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[target methodSignatureForSelector:sel]];
    [inv setTarget:target];
    [inv setSelector:sel];
    return inv;
}

static void signatures(void)
{
    printf("signatures\n");
    const char *types[] = {
        "v16@0:8", "{CGRect={CGPoint=dd}{CGSize=dd}}40@0:8{CGPoint=dd}16{CGSize=dd}32", "Vv16@0:8",
        "r*24@0:8^{_NSZone=}16", "D32@0:8D16", "@?<v@?i>24@0:8@\"NSString\"16",
        "{Tiny=cs}20@0:8{Tiny=cs}16", "(U=ic[3s])16@0:8", "{Bits=b3b5b9}16@0:8",
    };
    for (unsigned i = 0; i < sizeof types / sizeof types[0]; i++) {
        NSMethodSignature *s = [NSMethodSignature signatureWithObjCTypes:types[i]];
        printf("  %s: returns %s (%lu bytes)%s, %lu arguments:", types[i], [s methodReturnType],
               (unsigned long)[s methodReturnLength], [s isOneway] ? ", oneway" : "",
               (unsigned long)[s numberOfArguments]);
        for (NSUInteger a = 0; a < [s numberOfArguments]; a++)
            printf(" %s", [s getArgumentTypeAtIndex:a]);
        printf("\n");
    }
    NSMethodSignature *a = [NSMethodSignature signatureWithObjCTypes:"i24@0:8i16i20"];
    NSMethodSignature *b = [NSMethodSignature signatureWithObjCTypes:"i@:ii"];
    printf("  equal ignoring offsets: %s, hash equal: %s\n", [a isEqual:b] ? "yes" : "no",
           [a hash] == [b hash] ? "yes" : "no");
    printf("  from the class: %s\n", [[Calc instanceMethodSignatureForSelector:@selector(add:to:)] isEqual:b] ? "same" : "different");
    printf("  for a method nobody has: %s\n", [[[[Calc alloc] init] autorelease] methodSignatureForSelector:@selector(nothing)]
                                                  ? "a signature" : "nil");
    const char *sizes[] = {"c", "s", "i", "q", "f", "d", "D", "@", "^v", "{CGRect={CGPoint=dd}{CGSize=dd}}",
                           "{Tiny=cs}", "[5i]", "(U=ic[3s])", "{Bits=b3b5b9}", "{?=c{?=dc}}", "jf"};
    printf("  sizes:");
    for (unsigned i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
        NSUInteger size, align;
        NSGetSizeAndAlignment(sizes[i], &size, &align);
        printf(" %s=%lu/%lu", sizes[i], (unsigned long)size, (unsigned long)align);
    }
    printf("\n");
    @try {
        [NSMethodSignature signatureWithObjCTypes:"v@:%"];
    } @catch (NSException *e) {
        printf("  bad encoding: %s\n", [[e name] UTF8String]);
    }
    @try {
        [a getArgumentTypeAtIndex:4];
    } @catch (NSException *e) {
        printf("  index 4: %s\n", [[e name] UTF8String]);
    }
}

/* Calls every Calc method through calc (a Calc, or a proxy for one). */
static void calls(id calc)
{
    NSInvocation *inv;
    int a = 40, b = 2, ri;
    inv = inv_for(calc, @selector(add:to:));
    [inv setArgument:&a atIndex:2];
    [inv setArgument:&b atIndex:3];
    [inv invoke];
    [inv getReturnValue:&ri];
    printf("  add:to: %d, by message %d\n", ri, [calc add:-5 to:3]);

    char c = 5, rc;
    inv = inv_for(calc, @selector(negate:));
    [inv setArgument:&c atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rc];
    printf("  negate: %d, by message %d\n", rc, [calc negate:-100]);

    unsigned short us = 65000, rus;
    inv = inv_for(calc, @selector(half:));
    [inv setArgument:&us atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rus];
    BOOL pos = [calc isPositive:-3];
    printf("  half: %u, isPositive:-3 %d, isPositive:9 %d\n", rus, pos, [calc isPositive:9]);

    long l[6] = {1, 20, 300, 4000, 50000, 600000};
    short sh = -7;
    unsigned char uc = 250;
    long long rll;
    inv = inv_for(calc, @selector(sumOf::::::::));
    for (int i = 0; i < 6; i++)
        [inv setArgument:&l[i] atIndex:2 + i];
    [inv setArgument:&sh atIndex:8];
    [inv setArgument:&uc atIndex:9];
    [inv invoke];
    [inv getReturnValue:&rll];
    printf("  eight integers (two on the stack): %lld, by message %lld\n", rll,
           [calc sumOf:1 :2 :3 :4 :5 :6 :-100 :200]);

    int mi = 3;
    float mf = 0.5f;
    double md = 0.25, rd;
    inv = inv_for(calc, @selector(mix:f:d:));
    [inv setArgument:&mi atIndex:2];
    [inv setArgument:&mf atIndex:3];
    [inv setArgument:&md atIndex:4];
    [inv invoke];
    [inv getReturnValue:&rd];
    printf("  mix:f:d: %g, by message %g\n", rd, [calc mix:-1 f:1.5f d:100]);

    double d[9] = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    float j = 1;
    inv = inv_for(calc, @selector(tenDoubles::::::::::));
    for (int i = 0; i < 9; i++)
        [inv setArgument:&d[i] atIndex:2 + i];
    [inv setArgument:&j atIndex:11];
    [inv invoke];
    [inv getReturnValue:&rd];
    printf("  ten floating-point numbers (two on the stack): %g, by message %g\n", rd,
           [calc tenDoubles:1 :0 :0 :0 :0 :0 :0 :0 :2 :3]);

    float fa = 1.25f, fb = 2.5f, rf;
    inv = inv_for(calc, @selector(fsum::));
    [inv setArgument:&fa atIndex:2];
    [inv setArgument:&fb atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rf];
    printf("  fsum: %g, by message %g\n", rf, [calc fsum:0.125f :0.25f]);

    NSPoint p = NSMakePoint(3, 4);
    NSSize s = NSMakeSize(50, 60);
    NSRect rr;
    inv = inv_for(calc, @selector(rectAt:size:));
    [inv setArgument:&p atIndex:2];
    [inv setArgument:&s atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rr];
    NSRect rm = [calc rectAt:NSMakePoint(-1, -2) size:NSMakeSize(7, 8)];
    printf("  rectAt:size: (memory) {%g, %g, %g, %g}, by message {%g, %g, %g, %g}\n", rr.origin.x, rr.origin.y,
           rr.size.width, rr.size.height, rm.origin.x, rm.origin.y, rm.size.width, rm.size.height);

    CGFloat by = 0.5;
    NSPoint rp;
    inv = inv_for(calc, @selector(move:by:));
    [inv setArgument:&p atIndex:2];
    [inv setArgument:&by atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rp];
    NSPoint pm = [calc move:NSMakePoint(10, 10) by:1];
    printf("  move:by: (two vector registers) {%g, %g}, by message {%g, %g}\n", rp.x, rp.y, pm.x, pm.y);

    NSRange r = NSMakeRange(5, 6), rrg;
    NSUInteger n = 10;
    inv = inv_for(calc, @selector(shift:by:));
    [inv setArgument:&r atIndex:2];
    [inv setArgument:&n atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rrg];
    NSRange rgm = [calc shift:NSMakeRange(1, 1) by:1];
    printf("  shift:by: (two general registers) {%lu, %lu}, by message {%lu, %lu}\n", (unsigned long)rrg.location,
           (unsigned long)rrg.length, (unsigned long)rgm.location, (unsigned long)rgm.length);

    Mixed m = {1.5, 41}, rmx;
    inv = inv_for(calc, @selector(mixed:));
    [inv setArgument:&m atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rmx];
    Mixed mm = [calc mixed:(Mixed){-1, -1}];
    printf("  mixed: (a vector and a general register) {%g, %ld}, by message {%g, %ld}\n", rmx.d, rmx.l, mm.d, mm.l);

    IntFloat ifv = {7, 3}, rif;
    inv = inv_for(calc, @selector(intFloat:));
    [inv setArgument:&ifv atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rif];
    IntFloat ifm = [calc intFloat:(IntFloat){-2, 1}];
    printf("  intFloat: (one general register) {%d, %g}, by message {%d, %g}\n", rif.i, rif.f, ifm.i, ifm.f);

    Vec3 v = {1, 2, 3}, rv;
    float k = 2;
    inv = inv_for(calc, @selector(scale:by:));
    [inv setArgument:&v atIndex:2];
    [inv setArgument:&k atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rv];
    Vec3 vm = [calc scale:(Vec3){1, 1, 1} by:-1];
    printf("  scale:by: {%g, %g, %g}, by message {%g, %g, %g}\n", rv.x, rv.y, rv.z, vm.x, vm.y, vm.z);

    Big big = {1, 2, 3};
    int x = 1000;
    long rl;
    inv = inv_for(calc, @selector(sumBig:plus:));
    [inv setArgument:&big atIndex:2];
    [inv setArgument:&x atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rl];
    printf("  sumBig:plus: (a struct on the stack) %ld, by message %ld\n", rl, [calc sumBig:(Big){5, 5, 5} plus:-15]);

    long bx = 4;
    Big rb;
    inv = inv_for(calc, @selector(bigFrom:));
    [inv setArgument:&bx atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rb];
    Big bm = [calc bigFrom:-1];
    printf("  bigFrom: {%ld, %ld, %ld}, by message {%ld, %ld, %ld}\n", rb.a, rb.b, rb.c, bm.a, bm.b, bm.c);

    Tiny t = {'a', 100}, rt;
    inv = inv_for(calc, @selector(tiny:));
    [inv setArgument:&t atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rt];
    Tiny tm = [calc tiny:(Tiny){'y', 0}];
    printf("  tiny: {%c, %d}, by message {%c, %d}\n", rt.c, rt.s, tm.c, tm.s);

    long double ld = 10, rld;
    inv = inv_for(calc, @selector(third:));
    [inv setArgument:&ld atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rld];
    printf("  third: (x87) %.6f, by message %.6f\n", (double)rld, (double)[calc third:1]);

    NSString *str = @"ferry", *rs;
    inv = inv_for(calc, @selector(echo:));
    [inv setArgument:&str atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rs];
    printf("  echo: %s, by message %s\n", [rs UTF8String], [[calc echo:@"boat"] UTF8String]);

    const char *cs = "wave";
    inv = inv_for(calc, @selector(join:with:));
    [inv setArgument:&str atIndex:2];
    [inv setArgument:&cs atIndex:3];
    [inv invoke];
    [inv getReturnValue:&rs];
    printf("  join:with: %s, by message %s\n", [rs UTF8String], [[calc join:@"a" with:"b"] UTF8String]);

    int (^twice)(int) = ^(int z) { return z * 2; };
    int seven = 7;
    inv = inv_for(calc, @selector(call:with:));
    [inv setArgument:&twice atIndex:2];
    [inv setArgument:&seven atIndex:3];
    [inv invoke];
    [inv getReturnValue:&ri];
    printf("  call:with: %d, by message %d\n", ri, [calc call:^(int z) { return z + 1; } with:1]);

    SEL sel = @selector(description), rsel;
    inv = inv_for(calc, @selector(selectorBack:));
    [inv setArgument:&sel atIndex:2];
    [inv invoke];
    [inv getReturnValue:&rsel];
    printf("  selectorBack: %s\n", sel_getName(rsel));

    [calc ping];
    @try {
        [calc fail:@"by message"];
    } @catch (NSException *e) {
        printf("  caught %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
    }
}

static void invocations(void)
{
    printf("invocations\n");
    Calc *calc = [[Calc alloc] init];
    calls(calc);

    printf("the rest of NSInvocation\n");
    NSInvocation *inv = inv_for(calc, @selector(add:to:));
    printf("  target is calc: %s, selector %s, retained: %s\n", [inv target] == calc ? "yes" : "no",
           sel_getName([inv selector]), [inv argumentsRetained] ? "yes" : "no");
    int a = 1, b = 2, r = 99;
    [inv setArgument:&a atIndex:2];
    [inv setArgument:&b atIndex:3];
    [inv setReturnValue:&r];
    r = 0;
    [inv getReturnValue:&r];
    printf("  return value set by hand: %d\n", r);
    Calc *other = [[Calc alloc] init];
    [inv invokeWithTarget:other];
    [inv getReturnValue:&r];
    printf("  invokeWithTarget: %d, calls %d and %d, target is now other: %s\n", r, calc.calls, other.calls,
           [inv target] == other ? "yes" : "no");
    [inv setTarget:nil];
    [inv invoke];
    [inv getReturnValue:&r];
    printf("  to nil: %d\n", r);
    SEL s;
    [inv getArgument:&s atIndex:1];
    printf("  argument 1: %s\n", sel_getName(s));
    @try {
        [inv setArgument:&a atIndex:4];
    } @catch (NSException *e) {
        printf("  index 4: %s\n", [[e name] UTF8String]);
    }

    /* retainArguments: objects retained, C strings and blocks copied */
    NSMutableString *text = [[NSMutableString alloc] initWithString:@"kept"];
    char buffer[16];
    strcpy(buffer, "copied");
    inv = inv_for(calc, @selector(join:with:));
    [inv setArgument:&text atIndex:2];
    const char *bp = buffer;
    [inv setArgument:&bp atIndex:3];
    unsigned long before = [text retainCount];
    [inv retainArguments];
    [inv retainArguments];
    printf("  retainArguments: retained %s, count %lu -> %lu\n", [inv argumentsRetained] ? "yes" : "no", before,
           (unsigned long)[text retainCount]);
    strcpy(buffer, "changed");
    [text release];
    [inv invoke];
    NSString *joined;
    [inv getReturnValue:&joined];
    printf("  after the caller let go: %s\n", [joined UTF8String]);

    NSInvocation *blk = inv_for(calc, @selector(call:with:));
    {
        int base = 100;
        int (^add)(int) = ^(int z) { return z + base; };
        [blk setArgument:&add atIndex:2];
        [blk retainArguments];
    }
    int five = 5;
    [blk setArgument:&five atIndex:3];
    [blk invoke];
    [blk getReturnValue:&r];
    printf("  a stack block copied by retainArguments: %d\n", r);

    NSInvocation *fail = inv_for(calc, @selector(fail:));
    NSString *why = @"through invoke";
    [fail setArgument:&why atIndex:2];
    @try {
        [fail invoke];
        printf("  not reached\n");
    } @catch (NSException *e) {
        printf("  caught %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
    }

    /* a class method */
    NSInvocation *cls = [NSInvocation invocationWithMethodSignature:[Calc methodSignatureForSelector:@selector(classAdd:)]];
    [cls setTarget:[Calc class]];
    [cls setSelector:@selector(classAdd:)];
    [cls setArgument:&five atIndex:2];
    [cls invoke];
    [cls getReturnValue:&r];
    printf("  a class method: %d\n", r);
    [other release];
    [calc release];
}

static void forwarding(void)
{
    printf("through a proxy\n");
    Calc *calc = [[Calc alloc] init];
    Logger *proxy = [Logger alloc];
    proxy->target = calc;
    calls(proxy);
    printf("  forwarded %d messages; calc counted %d adds\n", proxy->forwarded, calc.calls);
    printf("  isProxy %d; isKindOfClass: Calc %d; respondsToSelector: add:to: %d, frob %d\n", [proxy isProxy],
           [proxy isKindOfClass:[Calc class]], [proxy respondsToSelector:@selector(add:to:)],
           [proxy respondsToSelector:NSSelectorFromString(@"frob")]);
    printf("  class %s, description starts %s\n", class_getName([proxy class]),
           [[[proxy description] substringToIndex:8] UTF8String]);
    unsigned long rc = [proxy retainCount];
    [proxy retain];
    printf("  retain count %lu -> %lu\n", rc, (unsigned long)[proxy retainCount]);
    [proxy release];
    [proxy release];
    [calc release];

    printf("an object answering for itself\n");
    Recorder *rec = [[Recorder alloc] init];
    rec.log = [NSMutableArray array];
    NSRect f = [rec frame];
    printf("  frame {%g, %g, %g, %g}\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
    printf("  ratio %g, grade %d, name %s\n", [rec ratio], [rec grade], [[rec name] UTF8String]);
    [rec note:@"hello" count:3];
    printf("  add:to: through forwardingTargetForSelector: %d\n", [rec add:20 to:22]);
    @try {
        [rec boom];
    } @catch (NSException *e) {
        printf("  caught %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
    }
    printf("  a class's own forwarding: %lld\n", [Recorder classTwice:21]);
    printf("  recorded: %s\n", [[rec.log componentsJoinedByString:@" "] UTF8String]);
    [rec release];
}

static void undo(void)
{
    printf("undo through prepareWithInvocationTarget:\n");
    Doc *doc = [[Doc alloc] init];
    NSUndoManager *um = [[NSUndoManager alloc] init];
    [um setGroupsByEvent:NO];
    doc.undo = um;
    printf("  prepare answers the undo manager: %s\n", [um prepareWithInvocationTarget:doc] == um ? "yes" : "no");
    [um beginUndoGrouping];
    doc.size = 10;
    [um endUndoGrouping];
    [um beginUndoGrouping];
    doc.size = 20;
    doc.frame = NSMakeRect(1, 2, 3, 4);
    NSMutableString *title = [[NSMutableString alloc] initWithString:@"First"];
    doc.title = title;
    [title release];
    [um setActionName:@"Edit"];
    [um endUndoGrouping];
    [um beginUndoGrouping];
    doc.title = @"Second";
    doc.frame = NSMakeRect(10, 20, 30, 40);
    [um endUndoGrouping];
    [doc show:"edited"];
    printf("  can undo %d, menu item \"%s\"\n", [um canUndo], [[um undoMenuItemTitle] UTF8String]);
    [um undo];
    [doc show:"undone once"];
    printf("  undo item \"%s\", redo item \"%s\"\n", [[um undoMenuItemTitle] UTF8String],
           [[um redoMenuItemTitle] UTF8String]);
    [um undo];
    [doc show:"undone twice"];
    [um redo];
    [doc show:"redone"];
    [um redo];
    [doc show:"redone again"];
    printf("  can redo %d\n", [um canRedo]);

    /* nested groups undo as one; disabled registration keeps nothing */
    [um beginUndoGrouping];
    doc.size = 1;
    [um beginUndoGrouping];
    doc.size = 2;
    doc.title = @"Nested";
    [um endUndoGrouping];
    doc.size = 3;
    [um endUndoGrouping];
    [um disableUndoRegistration];
    doc.size = 4;
    [um enableUndoRegistration];
    [doc show:"nested edits"];
    [um undo];
    [doc show:"nested undone"];
    [um undo];
    [doc show:"undone"];

    /* mixed with a selector action, then the target's actions removed */
    [um beginUndoGrouping];
    doc.size = 77;
    [um registerUndoWithTarget:doc selector:@selector(show:) object:nil];
    [um endUndoGrouping];
    [um removeAllActionsWithTarget:doc];
    printf("  after removeAllActionsWithTarget: can undo %d\n", [um canUndo]);
    [um release];
    doc.undo = nil;
    [doc release];
}

int main(void)
{
    @autoreleasepool {
        signatures();
        invocations();
        forwarding();
        undo();
        printf("a message nobody implements\n");
        fflush(stdout);
        [[[NSObject alloc] init] performSelector:NSSelectorFromString(@"frobnicate")];
        printf("not reached\n");
    }
    return 0;
}
