/* SPDX-License-Identifier: GPL-3.0-or-later
 * Exceptions a program catches (M7): @try/@catch/@finally, catching by
 * class, @catch (id), rethrowing, throwing through Foundation's own frames
 * and through methods, the old NS_DURING macros, and the values a function
 * keeps in registers surviving the unwind. Built twice by run.sh: as is
 * and with -fomit-frame-pointer, so both kinds of compact unwind entry
 * (frame-pointer and frameless) are walked. */
#import <Foundation/Foundation.h>

@interface MyError : NSException
@end
@implementation MyError
@end

@interface Thrower : NSObject
- (void)throwName:(NSString *)name depth:(int)depth;
@end
@implementation Thrower
- (void)throwName:(NSString *)name depth:(int)depth
{
    volatile char pad[200]; /* a frame with a large stack */
    pad[0] = (char)depth;
    if (depth > 0) {
        [self throwName:name depth:depth - 1];
        return;
    }
    if ([name isEqualToString:@"MyError"])
        @throw [MyError exceptionWithName:@"MyError" reason:@"mine" userInfo:nil];
    [NSException raise:name format:@"deep %d", (int)pad[0]];
}
@end

static int finally_runs;

__attribute__((noinline)) static long deep(int n, long acc)
{
    if (n == 0)
        @throw @"a string, not an NSException";
    return deep(n - 1, acc * 3 + n) + 1; /* not a tail call */
}

/* Values held in callee-saved registers across the call must be as they
 * were when the @catch runs. */
__attribute__((noinline)) static void keeps_registers(void)
{
    long a = random() | 1, b = a * 7, c = a ^ 0x5555, d = b + c, e = d * 3;
    long before = a + b * 2 + c * 3 + d * 5 + e * 7;
    @try {
        deep(6, a);
    } @catch (id x) {
        long after = a + b * 2 + c * 3 + d * 5 + e * 7;
        printf("registers kept: %s; caught %s\n", before == after ? "yes" : "NO", [[x description] UTF8String]);
    }
}

static void with_finally(BOOL raise)
{
    @try {
        if (raise)
            [NSException raise:NSRangeException format:@"in with_finally"];
        printf("  body ran to the end\n");
    } @finally {
        finally_runs++;
        printf("  finally (%s)\n", raise ? "after raise" : "normal");
    }
}

static void rethrows(void)
{
    @try {
        [NSException raise:NSGenericException format:@"first"];
    } @catch (NSException *e) {
        printf("  inner caught %s, rethrowing\n", [[e reason] UTF8String]);
        @throw;
    }
}

int main(void)
{
    @autoreleasepool {
        Thrower *t = [[Thrower alloc] init];

        /* the simplest case */
        @try {
            [NSException raise:NSInvalidArgumentException format:@"bad %d", 42];
            printf("not reached\n");
        } @catch (NSException *e) {
            printf("caught %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        }

        /* through several method frames, by class */
        @try {
            [t throwName:@"MyError" depth:5];
        } @catch (MyError *e) {
            printf("caught MyError by its class: %s\n", [[e reason] UTF8String]);
        } @catch (NSException *e) {
            printf("wrong handler\n");
        }

        /* the first @catch doesn't match: the next one does */
        @try {
            @try {
                [t throwName:NSRangeException depth:3];
            } @catch (MyError *e) {
                printf("wrong handler\n");
            }
        } @catch (NSException *e) {
            printf("outer caught %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        }

        /* any object can be thrown; @catch (id) takes it */
        keeps_registers();

        /* @finally, with and without an exception */
        with_finally(NO);
        @try {
            with_finally(YES);
        } @catch (NSException *e) {
            printf("after finally, caught %s\n", [[e reason] UTF8String]);
        }
        printf("finally ran %d times\n", finally_runs);

        /* rethrowing */
        @try {
            rethrows();
        } @catch (NSException *e) {
            printf("outer caught the rethrown %s\n", [[e reason] UTF8String]);
        }

        /* through Foundation's own frames: thrown from a block it calls */
        __block int seen = 0;
        @try {
            [@[ @1, @2, @3 ] enumerateObjectsUsingBlock:^(id obj, NSUInteger i, BOOL *stop) {
                seen++;
                if ([obj intValue] == 2)
                    [NSException raise:@"Stop" format:@"at %lu", (unsigned long)i];
            }];
        } @catch (NSException *e) {
            printf("out of enumerateObjectsUsingBlock: %s after %d\n", [[e reason] UTF8String], seen);
        }

        /* Foundation's own exceptions */
        @try {
            [@[] objectAtIndex:3];
        } @catch (NSException *e) {
            printf("NSArray: %s\n", [[e name] UTF8String]);
        }

        /* @synchronized lets go of its lock on the way out */
        NSObject *lock = [[NSObject alloc] init];
        @try {
            @synchronized(lock) {
                [NSException raise:NSGenericException format:@"inside @synchronized"];
            }
        } @catch (NSException *e) {
            @synchronized(lock) {
                printf("lock free again after: %s\n", [[e reason] UTF8String]);
            }
        }

        /* the old macros */
        NS_DURING
            [NSException raise:NSGenericException format:@"old style"];
        NS_HANDLER
            printf("NS_HANDLER: %s\n", [[localException reason] UTF8String]);
        NS_ENDHANDLER

        /* many in a row */
        int count = 0;
        for (int i = 0; i < 1000; i++) {
            @try {
                [t throwName:NSGenericException depth:i % 7];
            } @catch (NSException *e) {
                count++;
            }
        }
        printf("caught %d of 1000\n", count);
    }
    return 0;
}
