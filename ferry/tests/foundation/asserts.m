/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0): NSAssert and its kin, as
 * Sequel Pro, Hex Fiend and KeyCastr use them. A failed NSAssert raises
 * NSInternalInconsistencyException with the formatted message; a failed
 * NSParameterAssert raises NSInvalidArgumentException; the C forms work in
 * functions; a passing assertion does nothing; the current handler is one
 * per thread and can be replaced through the thread dictionary; and the
 * garbage-collection calls of old apps do nothing harmful. */
#import <Foundation/Foundation.h>

@interface Checker : NSObject
- (void)check:(int)n;
- (void)take:(id)arg;
+ (void)classCheck;
@end
@implementation Checker
- (void)check:(int)n { NSAssert1(n < 10, @"n is %d, too big", n); }
- (void)take:(id)arg { NSParameterAssert(arg != nil); }
+ (void)classCheck { NSAssert(NO, @"from a class method"); }
@end

static void c_check(int n) { NSCAssert2(n > 0, @"%s: n is %d", "c_check", n); }
static void c_param(const char *p) { NSCParameterAssert(p); }

@interface Counting : NSAssertionHandler
@property int failures;
@end
@implementation Counting
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)file lineNumber:(NSInteger)line
                  description:(NSString *)format, ...
{
    self.failures++;
    printf("custom handler: %s in %s\n", sel_getName(selector), [[file lastPathComponent] UTF8String]);
}
@end

static void attempt(const char *label, void (^block)(void))
{
    @try {
        block();
        printf("%s: passed\n", label);
    } @catch (NSException *e) {
        printf("%s: %s: %s\n", label, [[e name] UTF8String], [[e reason] UTF8String]);
    }
}

int main(void)
{
    @autoreleasepool {
        Checker *c = [Checker new];
        attempt("small n", ^{
            [c check:3];
        });
        attempt("big n", ^{
            [c check:30];
        });
        attempt("nil parameter", ^{
            [c take:nil];
        });
        attempt("class method", ^{
            [Checker classCheck];
        });
        attempt("C assertion", ^{
            c_check(-2);
        });
        attempt("C parameter", ^{
            c_param(NULL);
        });
        attempt("C passing", ^{
            c_check(2);
            c_param("x");
        });
        NSAssertionHandler *h = [NSAssertionHandler currentHandler];
        printf("same handler twice: %s, kept in the thread dictionary: %s\n",
               h == [NSAssertionHandler currentHandler] ? "yes" : "no",
               [[[NSThread currentThread] threadDictionary] objectForKey:NSAssertionHandlerKey] == h ? "yes" : "no");
        Counting *mine = [Counting new];
        [[[NSThread currentThread] threadDictionary] setObject:mine forKey:NSAssertionHandlerKey];
        attempt("with a handler that doesn't raise", ^{
            [c check:99];
        });
        printf("failures counted: %d\n", mine.failures);
        __block BOOL otherThreadHasOwn = NO;
        NSThread *t = [[NSThread alloc] initWithBlock:^{
            otherThreadHasOwn = [NSAssertionHandler currentHandler] != mine;
        }];
        [t start];
        while (![t isFinished])
            [NSThread sleepForTimeInterval:0.01];
        printf("another thread has its own handler: %s\n", otherThreadHasOwn ? "yes" : "no");

        printf("garbage collector: %s, collectable is the same object: %s\n",
               [NSGarbageCollector defaultCollector] ? "one" : "none",
               NSMakeCollectable((__bridge CFTypeRef)c) == c ? "yes" : "no");
        void *p = NSAllocateCollectable(16, 0);
        p = NSReallocateCollectable(p, 64, 0);
        printf("collectable memory: %s\n", p ? "allocated" : "none");
        free(p);
    }
    return 0;
}
