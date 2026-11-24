/* SPDX-License-Identifier: GPL-3.0-or-later
 * Foundation's locks and the Objective-C runtime under real threads:
 * NSLock, NSRecursiveLock, NSCondition and NSConditionLock between threads
 * (counters under contention, timed waits, a producer and consumer, a
 * hand-off chain), @synchronized, and the runtime's own thread safety:
 * +initialize runs once while other threads wait for it, method caches
 * filled and methods added while other threads send messages, retain and
 * release, weak references to objects other threads let go, associated
 * objects and autorelease pools. Each part prints one fixed line from the
 * main thread; an alarm makes a hang fail. */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

#define THREADS 8

/* The runtime's weak-reference calls, which ARC code makes */
id objc_loadWeakRetained(id *location);
void objc_destroyWeak(id *location);

static void on_alarm(int sig)
{
    static const char msg[] = "foundation_locks: timed out\n";
    write(2, msg, sizeof msg - 1);
    _exit(3);
}

/* Runs body(i) on THREADS NSThreads at once and waits for them all. */
static void on_threads(int n, void (^body)(int))
{
    NSMutableArray *threads = [NSMutableArray array];
    for (int i = 0; i < n; i++)
        [threads addObject:[[[NSThread alloc] initWithBlock:^{
                     @autoreleasepool {
                         body(i);
                     }
                 }] autorelease]];
    for (NSThread *t in threads)
        [t start];
    for (NSThread *t in threads)
        while (![t isFinished])
            usleep(500);
}

static int initialize_runs;
static volatile int initialize_done;

@interface SlowInit : NSObject
+ (int)value;
@end
@implementation SlowInit
+ (void)initialize
{
    if (self != [SlowInit class])
        return;
    __atomic_add_fetch(&initialize_runs, 1, __ATOMIC_SEQ_CST);
    usleep(50000); /* the other threads arrive meanwhile, and must wait */
    initialize_done = 1;
}
+ (int)value { return initialize_done; }
@end

@interface Counter : NSObject {
@public
    long n;
}
- (long)one;
@end
@implementation Counter
- (long)one { return 1; }
@end

static long added_two(id self, SEL _cmd) { return 2; }

static char assoc_key;

int main(void)
{
    signal(SIGALRM, on_alarm);
    alarm(60);
    @autoreleasepool {
        /* NSLock: a counter under contention */
        NSLock *lock = [[[NSLock alloc] init] autorelease];
        [lock setName:@"counter lock"];
        __block long counter = 0;
        on_threads(THREADS, ^(int i) {
            for (int k = 0; k < 20000; k++) {
                [lock lock];
                counter++;
                [lock unlock];
            }
        });
        printf("NSLock: %ld (expected %d), name %s\n", counter, THREADS * 20000, [[lock name] UTF8String]);

        /* tryLock and lockBeforeDate: against another thread's hold */
        dispatch_semaphore_t held = dispatch_semaphore_create(0), release_it = dispatch_semaphore_create(0);
        [NSThread detachNewThreadWithBlock:^{
            [lock lock];
            dispatch_semaphore_signal(held);
            dispatch_semaphore_wait(release_it, DISPATCH_TIME_FOREVER);
            [lock unlock];
        }];
        dispatch_semaphore_wait(held, DISPATCH_TIME_FOREVER);
        NSDate *start = [NSDate date];
        BOOL tried = [lock tryLock];
        BOOL timed = [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        BOOL waitedLong = -[start timeIntervalSinceNow] >= 0.045;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                       ^{ dispatch_semaphore_signal(release_it); });
        BOOL got = [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5]];
        printf("NSLock held elsewhere: try %d, before 50 ms %d (waited it out %d), before 5 s once let go %d\n", tried,
               timed, waitedLong, got);
        [lock unlock];

        /* NSRecursiveLock: nested on each thread, exclusive between them */
        NSRecursiveLock *rl = [[[NSRecursiveLock alloc] init] autorelease];
        __block long rcount = 0;
        __block int inside = 0, overlap = 0;
        on_threads(THREADS, ^(int i) {
            for (int k = 0; k < 2000; k++) {
                [rl lock];
                [rl lock];
                if (__atomic_add_fetch(&inside, 1, __ATOMIC_SEQ_CST) != 1)
                    overlap++;
                rcount++;
                __atomic_sub_fetch(&inside, 1, __ATOMIC_SEQ_CST);
                [rl unlock];
                [rl unlock];
            }
        });
        printf("NSRecursiveLock: %ld (expected %d), overlaps %d\n", rcount, THREADS * 2000, overlap);

        /* NSCondition: one producer, four consumers, a bounded queue */
        NSCondition *cond = [[[NSCondition alloc] init] autorelease];
        NSMutableArray *items = [NSMutableArray array];
        __block long consumed = 0, sum = 0;
        __block BOOL finished = NO;
        __block int overfull = 0;
        dispatch_group_t g = dispatch_group_create();
        for (int c = 0; c < 4; c++)
            dispatch_group_async(g, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                for (;;) {
                    [cond lock];
                    while (![items count] && !finished)
                        [cond wait];
                    if (![items count] && finished) {
                        [cond unlock];
                        break;
                    }
                    NSNumber *n = [[[items objectAtIndex:0] retain] autorelease];
                    [items removeObjectAtIndex:0];
                    consumed++;
                    sum += [n longValue];
                    [cond broadcast];
                    [cond unlock];
                }
            });
        for (long v = 1; v <= 2000; v++) {
            [cond lock];
            while ([items count] >= 8)
                [cond wait];
            [items addObject:@(v)];
            if ([items count] > 8)
                overfull++;
            [cond signal];
            [cond unlock];
        }
        [cond lock];
        finished = YES;
        [cond broadcast];
        [cond unlock];
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        dispatch_release(g);
        [cond lock];
        BOOL timedOut = ![cond waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        [cond unlock];
        printf("NSCondition: consumed %ld, sum %ld (expected 2001000), over 8 %d, a wait with no signal timed out %d\n",
               consumed, sum, overfull, timedOut);

        /* NSConditionLock: a baton passed along a chain of threads */
        NSConditionLock *cl = [[[NSConditionLock alloc] initWithCondition:0] autorelease];
        NSMutableArray *order = [NSMutableArray array];
        dispatch_group_t chain = dispatch_group_create();
        for (int s = 4; s >= 1; s--) /* started backwards: each waits for the one before */
            dispatch_group_async(chain, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [cl lockWhenCondition:s];
                [order addObject:@(s)];
                [cl unlockWithCondition:s + 1];
            });
        [cl lock];
        [order addObject:@0];
        [cl unlockWithCondition:1];
        BOOL tooSoon = [cl lockWhenCondition:9 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        dispatch_group_wait(chain, DISPATCH_TIME_FOREVER);
        dispatch_release(chain);
        printf("NSConditionLock: order %s, condition %ld, a condition never set timed out %d\n",
               [[order componentsJoinedByString:@" "] UTF8String], (long)[cl condition], !tooSoon);

        /* @synchronized */
        NSObject *token = [[[NSObject alloc] init] autorelease];
        __block long synced = 0;
        __block int syncOverlap = 0, syncInside = 0;
        on_threads(THREADS, ^(int i) {
            for (int k = 0; k < 5000; k++)
                @synchronized(token) {
                    @synchronized(token) { /* recursive on one thread */
                        if (__atomic_add_fetch(&syncInside, 1, __ATOMIC_SEQ_CST) != 1)
                            syncOverlap++;
                        synced++;
                        __atomic_sub_fetch(&syncInside, 1, __ATOMIC_SEQ_CST);
                    }
                }
        });
        printf("@synchronized: %ld (expected %d), overlaps %d\n", synced, THREADS * 5000, syncOverlap);

        /* +initialize: once, and every thread waits for it to end */
        __block int sawUninitialized = 0;
        on_threads(THREADS, ^(int i) {
            if ([SlowInit value] != 1)
                __atomic_add_fetch(&sawUninitialized, 1, __ATOMIC_SEQ_CST);
        });
        printf("+initialize: ran %d time(s), a thread got in before it ended %d\n", initialize_runs,
               sawUninitialized);

        /* method caches: many threads send messages while a method is added */
        Counter *ctr = [[[Counter alloc] init] autorelease];
        __block long ones = 0, twos = 0;
        __block volatile int added = 0;
        on_threads(THREADS, ^(int i) {
            long mine1 = 0, mine2 = 0;
            for (int k = 0; k < 50000; k++) {
                mine1 += [ctr one];
                if (i == 0 && k == 1000) {
                    class_addMethod([Counter class], sel_registerName("two"), (IMP)added_two, "l@:");
                    added = 1;
                }
                if (added)
                    mine2 += ((long (*)(id, SEL))objc_msgSend)(ctr, sel_registerName("two")) == 2;
            }
            while (!added) /* then every thread calls it once more */
                usleep(100);
            mine2 += ((long (*)(id, SEL))objc_msgSend)(ctr, sel_registerName("two")) == 2;
            __atomic_add_fetch(&ones, mine1, __ATOMIC_SEQ_CST);
            __atomic_add_fetch(&twos, mine2 > 0, __ATOMIC_SEQ_CST);
        });
        printf("messages during a method add: %ld (expected %d), threads that called the new method %ld\n", ones,
               THREADS * 50000, twos);

        /* retain and release of one object from every thread */
        NSObject *shared = [[NSObject alloc] init];
        on_threads(THREADS, ^(int i) {
            for (int k = 0; k < 20000; k++) {
                [shared retain];
                [shared release];
            }
        });
        printf("retain/release: count back to %lu\n", (unsigned long)[shared retainCount]);
        [shared release];

        /* weak references read while other threads let the objects go */
        __block int weakWrong = 0, weakSeenGone = 0;
        for (int round = 0; round < 200; round++) {
            NSObject *obj = [[NSObject alloc] init];
            id *weakSlot = calloc(1, sizeof(id)); /* a weak slot must not move */
            objc_storeWeak(weakSlot, obj);
            dispatch_group_t wg = dispatch_group_create();
            dispatch_group_async(wg, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [obj release]; /* the last strong reference */
            });
            for (int k = 0; k < 4; k++)
                dispatch_group_async(wg, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    for (int r = 0; r < 50; r++) {
                        id strong = objc_loadWeakRetained(weakSlot);
                        if (strong) {
                            if ([strong class] != [NSObject class])
                                __atomic_add_fetch(&weakWrong, 1, __ATOMIC_SEQ_CST);
                            [strong release];
                        }
                    }
                });
            dispatch_group_wait(wg, DISPATCH_TIME_FOREVER);
            dispatch_release(wg);
            if (objc_loadWeak(weakSlot) == nil)
                weakSeenGone++;
            objc_destroyWeak(weakSlot);
            free(weakSlot);
        }
        printf("weak references: bad loads %d, cleared after the last release %d of 200\n", weakWrong, weakSeenGone);

        /* associated objects set and read from many threads */
        NSObject *host = [[[NSObject alloc] init] autorelease];
        __block int assocBad = 0;
        on_threads(THREADS, ^(int i) {
            for (int k = 0; k < 2000; k++) {
                NSString *v = [NSString stringWithFormat:@"%d", k];
                objc_setAssociatedObject(host, &assoc_key, v, OBJC_ASSOCIATION_RETAIN);
                id got = objc_getAssociatedObject(host, &assoc_key);
                if (![got isKindOfClass:[NSString class]])
                    __atomic_add_fetch(&assocBad, 1, __ATOMIC_SEQ_CST);
                if (k % 100 == 0)
                    objc_setAssociatedObject(host, (void *)(intptr_t)(i + 1), v, OBJC_ASSOCIATION_COPY);
            }
        });
        objc_removeAssociatedObjects(host);
        printf("associated objects: bad reads %d, removed %d\n", assocBad,
               objc_getAssociatedObject(host, &assoc_key) == nil);

        /* autorelease pools on every thread, deep and drained */
        __block int poolsOk = 0;
        on_threads(THREADS, ^(int i) {
            int ok = 1;
            for (int round = 0; round < 50; round++) {
                @autoreleasepool {
                    NSMutableArray *keep = [NSMutableArray array];
                    for (int k = 0; k < 200; k++)
                        [keep addObject:[NSString stringWithFormat:@"%d/%d", i, k]];
                    @autoreleasepool {
                        if ([[keep lastObject] length] < 3)
                            ok = 0;
                    }
                }
            }
            if (ok)
                __atomic_add_fetch(&poolsOk, 1, __ATOMIC_SEQ_CST);
        });
        printf("autorelease pools: %d threads all right\n", poolsOk);

        /* notifications posted and observed from many threads */
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        __block long heard = 0;
        id observer = [nc addObserverForName:@"FerryThreadsNote"
                                      object:nil
                                       queue:nil
                                  usingBlock:^(NSNotification *n) { __atomic_add_fetch(&heard, 1, __ATOMIC_SEQ_CST); }];
        on_threads(THREADS, ^(int i) {
            for (int k = 0; k < 1000; k++) {
                [nc postNotificationName:@"FerryThreadsNote" object:nil];
                if (k % 100 == 0) {
                    id extra = [nc addObserverForName:@"FerryOther" object:nil queue:nil usingBlock:^(NSNotification *n) {}];
                    [nc removeObserver:extra];
                }
            }
        });
        [nc removeObserver:observer];
        printf("notifications from %d threads: heard %ld\n", THREADS, heard);
        dispatch_release(held);
        dispatch_release(release_it);
    }
    return 0;
}
