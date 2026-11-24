/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSOperation, NSBlockOperation, NSInvocationOperation and
 * NSOperationQueue: order, priorities, dependencies, cancelling,
 * completion blocks, suspending, barriers, operations that finish later,
 * key-value notifications, waiting; and the locks, across threads. Queues
 * run their operations on worker threads, so the parts that look at order
 * use a queue that runs one operation at a time. */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <unistd.h>

/* An operation that finishes later, from a timer, as a download would. */
@interface Later : NSOperation {
    BOOL _run, _done;
}
@end
@implementation Later
- (BOOL)isAsynchronous { return YES; }
- (BOOL)isExecuting { return _run; }
- (BOOL)isFinished { return _done; }
- (void)start
{
    printf("later: started\n");
    [self willChangeValueForKey:@"isExecuting"];
    _run = YES;
    [self didChangeValueForKey:@"isExecuting"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        printf("later: finishing\n");
        [self willChangeValueForKey:@"isFinished"];
        [self willChangeValueForKey:@"isExecuting"];
        _run = NO;
        _done = YES;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    });
}
@end

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)obj change:(NSDictionary *)change context:(void *)ctx
{
    printf("  observed %s = %s\n", [path UTF8String], [[[obj valueForKey:path] description] UTF8String]);
}
@end

@interface Target : NSObject
@end
@implementation Target
- (NSString *)shout:(NSString *)s { return [s uppercaseString]; }
- (int)answer { return 42; }
- (void)nothing {}
@end

int main(void)
{
    @autoreleasepool {
        NSMutableArray *log = [NSMutableArray array];
        NSOperationQueue *q = [[[NSOperationQueue alloc] init] autorelease];
        [q setName:@"test queue"];
        printf("queue: %s, max %ld, suspended %d, current is main %d\n", [[q name] UTF8String],
               (long)[q maxConcurrentOperationCount], [q isSuspended],
               [NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);
        printf("main queue: %s, max %ld\n", [[[NSOperationQueue mainQueue] name] UTF8String],
               (long)[[NSOperationQueue mainQueue] maxConcurrentOperationCount]);

        /* order, priority and dependencies, one at a time */
        [q setMaxConcurrentOperationCount:1];
        [q setSuspended:YES];
        dispatch_semaphore_t completed = dispatch_semaphore_create(0);
        NSBlockOperation *a = [NSBlockOperation blockOperationWithBlock:^{ [log addObject:@"a"]; }];
        NSBlockOperation *b = [NSBlockOperation blockOperationWithBlock:^{ [log addObject:@"b"]; }];
        NSBlockOperation *c = [NSBlockOperation blockOperationWithBlock:^{
            [log addObject:@"c"];
            printf("c runs on the test queue: %d\n", [NSOperationQueue currentQueue] == q);
        }];
        NSBlockOperation *d = [NSBlockOperation blockOperationWithBlock:^{ [log addObject:@"d"]; }];
        [d addExecutionBlock:^{ [log addObject:@"d2"]; }];
        [c setQueuePriority:NSOperationQueuePriorityVeryHigh];
        [a addDependency:b];
        __block BOOL offMain = NO;
        [a setCompletionBlock:^{
            offMain = ![NSThread isMainThread];
            dispatch_semaphore_signal(completed);
        }];
        printf("a ready %d, b ready %d, priority of 3: %ld\n", [a isReady], [b isReady],
               (long)({ [d setQueuePriority:3]; [d queuePriority]; }));
        [q addOperations:@[ a, b, c, d ] waitUntilFinished:NO];
        printf("suspended, %lu operations, nothing ran: %lu\n", (unsigned long)[q operationCount],
               (unsigned long)[log count]);
        [q setSuspended:NO];
        [q waitUntilAllOperationsAreFinished];
        printf("ran: %s\n", [[log componentsJoinedByString:@" "] UTF8String]);
        printf("a finished %d executing %d, queue has %lu\n", [a isFinished], [a isExecuting],
               (unsigned long)[q operationCount]);
        dispatch_semaphore_wait(completed, DISPATCH_TIME_FOREVER);
        dispatch_release(completed);
        printf("a's completion block ran off the main thread: %d\n", offMain);
        [q setMaxConcurrentOperationCount:NSOperationQueueDefaultMaxConcurrentOperationCount];
        @try {
            [q addOperation:a];
        } @catch (NSException *e) {
            printf("adding a finished operation: %s\n", [[e name] UTF8String]);
        }

        /* cancelling */
        [log removeAllObjects];
        NSBlockOperation *e = [NSBlockOperation blockOperationWithBlock:^{ [log addObject:@"e"]; }];
        NSBlockOperation *f = [NSBlockOperation blockOperationWithBlock:^{ [log addObject:@"f"]; }];
        [f addDependency:e];
        [q setSuspended:YES];
        [q addOperation:e];
        [q addOperation:f];
        [f cancel];
        printf("f cancelled %d, ready %d\n", [f isCancelled], [f isReady]);
        [q setSuspended:NO];
        [f waitUntilFinished];
        [q waitUntilAllOperationsAreFinished];
        printf("ran: %s; f finished %d\n", [[log componentsJoinedByString:@" "] UTF8String], [f isFinished]);

        /* one at a time, and a barrier */
        [log removeAllObjects];
        NSOperationQueue *serial = [[[NSOperationQueue alloc] init] autorelease];
        [serial setMaxConcurrentOperationCount:1];
        Later *later = [[[Later alloc] init] autorelease];
        Watcher *w = [[[Watcher alloc] init] autorelease];
        [later addObserver:w forKeyPath:@"isFinished" options:0 context:NULL];
        [serial addOperation:later];
        [serial addOperationWithBlock:^{ printf("after later\n"); }];
        [serial addBarrierBlock:^{ printf("barrier\n"); }];
        [serial addOperationWithBlock:^{ printf("after the barrier\n"); }];
        [serial waitUntilAllOperationsAreFinished];
        [later removeObserver:w forKeyPath:@"isFinished"];

        /* operationCount is observable */
        NSOperationQueue *watched = [[[NSOperationQueue alloc] init] autorelease];
        [watched addObserver:w forKeyPath:@"operationCount" options:0 context:NULL];
        [watched addOperationWithBlock:^{}];
        [watched waitUntilAllOperationsAreFinished];
        [watched removeObserver:w forKeyPath:@"operationCount"];

        /* the main queue, and a plain start */
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{ printf("on the main queue: %d\n",
                                                                      [NSOperationQueue currentQueue] ==
                                                                          [NSOperationQueue mainQueue]); }];
        [[NSOperationQueue mainQueue] waitUntilAllOperationsAreFinished];
        NSBlockOperation *g = [NSBlockOperation blockOperationWithBlock:^{ printf("started by hand\n"); }];
        [g start];
        @try {
            [g start];
        } @catch (NSException *ex) {
            printf("started twice: %s\n", [[ex name] UTF8String]);
        }

        /* invocations */
        Target *t = [[[Target alloc] init] autorelease];
        NSInvocationOperation *i1 = [[[NSInvocationOperation alloc] initWithTarget:t selector:@selector(shout:)
                                                                            object:@"hey"] autorelease];
        NSInvocationOperation *i2 = [[[NSInvocationOperation alloc] initWithTarget:t selector:@selector(answer)
                                                                            object:nil] autorelease];
        NSInvocationOperation *i3 = [[[NSInvocationOperation alloc] initWithTarget:t selector:@selector(nothing)
                                                                            object:nil] autorelease];
        [q addOperations:@[ i1, i2, i3 ] waitUntilFinished:YES];
        printf("results: %s %s\n", [[i1 result] UTF8String], [[[i2 result] description] UTF8String]);
        @try {
            [i3 result];
        } @catch (NSException *ex) {
            printf("void result: %s\n", [[ex name] UTF8String]);
        }

        /* locks, with another thread on the other side */
        dispatch_queue_t other = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        NSLock *lock = [[[NSLock alloc] init] autorelease];
        [lock lock];
        printf("NSLock: try while locked %d", [lock tryLock]);
        [lock unlock];
        printf(", after unlock %d", [lock tryLock]);
        printf(", before a date while locked %d\n",
               [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]);
        [lock unlock];
        dispatch_semaphore_t taken = dispatch_semaphore_create(0);
        __block BOOL inside = NO;
        dispatch_async(other, ^{
            [lock lock];
            inside = YES;
            dispatch_semaphore_signal(taken);
            usleep(20000);
            inside = NO;
            [lock unlock];
        });
        dispatch_semaphore_wait(taken, DISPATCH_TIME_FOREVER);
        printf("NSLock: try while another thread holds it %d\n", [lock tryLock]);
        [lock lock]; /* waits until the other thread unlocks it */
        printf("NSLock: taken after the other unlocked it, other still inside %d\n", inside);
        [lock unlock];
        NSRecursiveLock *rl = [[[NSRecursiveLock alloc] init] autorelease];
        [rl lock];
        [rl lock];
        printf("NSRecursiveLock: twice, try %d", [rl tryLock]);
        __block BOOL otherGot = YES;
        dispatch_sync(other, ^{ otherGot = [rl tryLock]; });
        printf(", another thread's try %d\n", otherGot);
        [rl unlock];
        [rl unlock];
        [rl unlock];

        NSCondition *cond = [[[NSCondition alloc] init] autorelease];
        __block BOOL ready = NO;
        [cond lock];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), other, ^{
            [cond lock];
            ready = YES;
            [cond signal];
            [cond unlock];
        });
        while (!ready)
            [cond wait];
        printf("NSCondition: signalled, ready %d\n", ready);
        printf("NSCondition: a wait with no signal times out: %d\n",
               [cond waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]);
        [cond unlock];

        NSConditionLock *cl = [[[NSConditionLock alloc] initWithCondition:1] autorelease];
        printf("NSConditionLock: condition %ld, try when 2: %d", (long)[cl condition], [cl tryLockWhenCondition:2]);
        dispatch_async(other, ^{
            [cl lock];
            [cl unlockWithCondition:2];
        });
        [cl lockWhenCondition:2];
        printf(", got it when 2, condition %ld\n", (long)[cl condition]);
        [cl unlockWithCondition:3];
        dispatch_release(taken);
    }
    return 0;
}
