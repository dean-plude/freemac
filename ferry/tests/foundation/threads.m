/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSThread on real threads: starting threads every documented way, the
 * current and main thread, thread dictionaries and names, sleeping,
 * cancelling and exiting, the will-exit and became-multithreaded
 * notifications, performs onto the main thread, onto another thread's run
 * loop and into the background, each thread's own run loop and autorelease
 * pools, NSRunLoop's performBlock: across threads, and NSOperationQueue
 * running operations at the same time on worker threads while its main
 * queue stays on the main thread. Lines are printed by the main thread
 * only, in a fixed order; an alarm makes a hang fail. */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

static void on_alarm(int sig)
{
    static const char msg[] = "foundation_threads: timed out\n";
    write(2, msg, sizeof msg - 1);
    _exit(3);
}

static int multithreaded_notes, exit_notes;
static NSMutableArray *exited_names;

/* Waits (on the main thread, turning its run loop) until flag is set. */
static BOOL wait_for(volatile BOOL *flag)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!*flag && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return *flag;
}

@interface Worker : NSObject {
@public
    volatile BOOL done;
    BOOL wasMain, sawArgument, isCurrent, poolDrained;
    NSString *name;
    NSThread *thread;
    NSRunLoop *loop;
    volatile BOOL loopReady, stop;
    int performed;
    BOOL performedOnThatThread;
}
@end

@interface Dropped : NSObject {
@public
    volatile BOOL *flag;
}
@end
@implementation Dropped
- (void)dealloc
{
    *flag = YES;
    [super dealloc];
}
@end

@implementation Worker
- (void)dealloc
{
    [name release];
    [super dealloc];
}
- (void)run:(id)argument
{
    wasMain = [NSThread isMainThread];
    sawArgument = [argument isEqual:@"argument"];
    isCurrent = [NSThread currentThread] == thread;
    name = [[[NSThread currentThread] name] copy];
    done = YES;
}
/* A thread that keeps its run loop running until told to stop. */
- (void)serve:(id)unused
{
    @autoreleasepool {
        loop = [NSRunLoop currentRunLoop];
        [loop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode]; /* keeps it running */
        loopReady = YES;
        while (!stop)
            [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    done = YES;
}
- (void)onWorker:(NSNumber *)n
{
    performed += [n intValue];
    performedOnThatThread = [NSThread currentThread] == thread;
}
- (void)stopServing:(id)unused { stop = YES; }
- (void)inBackground:(id)argument
{
    wasMain = [NSThread isMainThread];
    sawArgument = [argument isEqual:@"argument"];
    done = YES;
}
@end

@interface MainSide : NSObject {
@public
    int calls;
    BOOL onMain;
}
@end
@implementation MainSide
- (void)touch:(NSNumber *)n
{
    calls += [n intValue];
    onMain = [NSThread isMainThread];
}
@end

int main(void)
{
    signal(SIGALRM, on_alarm);
    alarm(60);
    @autoreleasepool {
        exited_names = [[NSMutableArray alloc] init];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:NSWillBecomeMultiThreadedNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) { __atomic_add_fetch(&multithreaded_notes, 1, __ATOMIC_SEQ_CST); }];
        [nc addObserverForName:NSThreadWillExitNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
                        __atomic_add_fetch(&exit_notes, 1, __ATOMIC_SEQ_CST);
                        NSString *n = [[note object] name];
                        @synchronized(exited_names) {
                            if ([n length])
                                [exited_names addObject:n];
                        }
                    }];

        /* the main thread */
        NSThread *main = [NSThread mainThread];
        printf("main: is main %d, current is main %d, instance is main %d, name '%s', multithreaded %d\n",
               [NSThread isMainThread], [NSThread currentThread] == main, [main isMainThread], [[main name] UTF8String],
               [NSThread isMultiThreaded]);
        [[main threadDictionary] setObject:@"main value" forKey:@"key"];
        printf("main thread dictionary: %s\n", [[[main threadDictionary] objectForKey:@"key"] UTF8String]);

        /* initWithTarget:selector:object: and start */
        Worker *w = [[[Worker alloc] init] autorelease];
        NSThread *t = [[[NSThread alloc] initWithTarget:w selector:@selector(run:) object:@"argument"] autorelease];
        w->thread = t;
        [t setName:@"first worker"];
        [t setStackSize:1 << 20];
        printf("before start: executing %d, finished %d, stack size %lu\n", [t isExecuting], [t isFinished],
               (unsigned long)[t stackSize]);
        [t start];
        wait_for(&w->done);
        while (![t isFinished])
            usleep(1000);
        printf("initWithTarget: ran %d, on the main thread %d, argument %d, current thread %d, name '%s'\n", w->done,
               w->wasMain, w->sawArgument, w->isCurrent, [w->name UTF8String]);
        printf("after: executing %d, finished %d, multithreaded %d, notified once %d\n", [t isExecuting],
               [t isFinished], [NSThread isMultiThreaded], multithreaded_notes);
        @try {
            [t start];
        } @catch (NSException *e) {
            printf("start again: %s\n", [[e name] UTF8String]);
        }

        /* initWithBlock:, cancel, threadDictionary, sleeping, +exit */
        __block volatile BOOL blockDone = NO, sawCancel = NO, ownDictionary = NO, sleptEnough = NO;
        __block volatile BOOL pastExit = NO;
        static volatile BOOL dropped = NO;
        __block NSThread *bt = nil;
        bt = [[NSThread alloc] initWithBlock:^{
            @autoreleasepool {
                Dropped *d = [[[Dropped alloc] init] autorelease];
                d->flag = (BOOL *)&dropped; /* released when this pool drains */
            }
            NSMutableDictionary *mine = [[NSThread currentThread] threadDictionary];
            ownDictionary = mine != [[NSThread mainThread] threadDictionary] && ![mine objectForKey:@"key"];
            NSDate *start = [NSDate date];
            [NSThread sleepForTimeInterval:0.02];
            [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            sleptEnough = -[start timeIntervalSinceNow] >= 0.029;
            while (![[NSThread currentThread] isCancelled])
                usleep(1000);
            sawCancel = YES;
            blockDone = YES;
            [NSThread exit];
            pastExit = YES;
        }];
        [bt setName:@"block worker"];
        [bt setQualityOfService:NSQualityOfServiceUtility];
        [bt start];
        usleep(5000);
        [bt cancel];
        wait_for(&blockDone);
        while (![bt isFinished])
            usleep(1000);
        printf("initWithBlock: cancelled %d, saw it %d, own dictionary %d, slept enough %d, pool drained %d, "
               "returned past +exit %d, qos utility %d\n",
               [bt isCancelled], sawCancel, ownDictionary, sleptEnough, dropped, pastExit,
               [bt qualityOfService] == NSQualityOfServiceUtility);
        [bt release];

        /* detachNewThreadSelector: and detachNewThreadWithBlock: */
        Worker *d1 = [[[Worker alloc] init] autorelease];
        [NSThread detachNewThreadSelector:@selector(run:) toTarget:d1 withObject:@"argument"];
        wait_for(&d1->done);
        __block volatile BOOL d2 = NO, d2main = YES;
        [NSThread detachNewThreadWithBlock:^{
            d2main = [NSThread isMainThread];
            d2 = YES;
        }];
        wait_for(&d2);
        printf("detached: selector ran %d (main %d, argument %d), block ran %d (main %d)\n", d1->done, d1->wasMain,
               d1->sawArgument, d2, d2main);

        /* performSelectorOnMainThread, waiting and not */
        MainSide *ms = [[[MainSide alloc] init] autorelease];
        __block volatile BOOL waitedOk = NO;
        __block int sawAfterWait = -1;
        [NSThread detachNewThreadWithBlock:^{
            [ms performSelectorOnMainThread:@selector(touch:) withObject:@1 waitUntilDone:YES];
            sawAfterWait = ms->calls; /* the main thread ran it before this returned */
            [ms performSelectorOnMainThread:@selector(touch:)
                                 withObject:@10
                              waitUntilDone:NO
                                      modes:@[ NSDefaultRunLoopMode ]];
            waitedOk = YES;
        }];
        wait_for(&waitedOk);
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
        while (ms->calls < 11 && [until timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        printf("performSelectorOnMainThread: calls %d, on main %d, waitUntilDone saw %d\n", ms->calls, ms->onMain,
               sawAfterWait);
        [ms performSelectorOnMainThread:@selector(touch:) withObject:@100 waitUntilDone:YES];
        printf("from the main thread itself with waitUntilDone: runs at once, calls %d\n", ms->calls);

        /* a thread with its own run loop, and performs onto it */
        Worker *server = [[[Worker alloc] init] autorelease];
        NSThread *st = [[[NSThread alloc] initWithTarget:server selector:@selector(serve:) object:nil] autorelease];
        server->thread = st;
        [st start];
        wait_for(&server->loopReady);
        printf("its run loop is its own: %d\n", server->loop != [NSRunLoop mainRunLoop] &&
                                                     server->loop != [NSRunLoop currentRunLoop]);
        [server performSelector:@selector(onWorker:) onThread:st withObject:@2 waitUntilDone:YES];
        printf("performSelector:onThread: waited, performed %d on that thread %d\n", server->performed,
               server->performedOnThatThread);
        for (int i = 0; i < 100; i++)
            [server performSelector:@selector(onWorker:) onThread:st withObject:@1 waitUntilDone:NO];
        [server performSelector:@selector(onWorker:)
                       onThread:st
                     withObject:@0
                  waitUntilDone:YES
                          modes:@[ NSDefaultRunLoopMode ]];
        printf("100 more without waiting, then one waited for: performed %d\n", server->performed);
        __block volatile BOOL blockOnLoop = NO;
        __block BOOL blockOnThat = NO;
        [server->loop performBlock:^{
            blockOnThat = [NSThread currentThread] == st;
            blockOnLoop = YES;
        }];
        wait_for(&blockOnLoop);
        printf("performBlock: on that thread's run loop: %d\n", blockOnThat);
        [server performSelector:@selector(stopServing:) onThread:st withObject:nil waitUntilDone:NO];
        wait_for(&server->done);

        /* performSelectorInBackground */
        Worker *bg = [[[Worker alloc] init] autorelease];
        [bg performSelectorInBackground:@selector(inBackground:) withObject:@"argument"];
        wait_for(&bg->done);
        printf("performSelectorInBackground: ran %d, main %d, argument %d\n", bg->done, bg->wasMain,
               bg->sawArgument);

        /* NSOperationQueue: two operations that only finish if they run at
         * the same time; the main queue's on the main thread */
        NSOperationQueue *q = [[[NSOperationQueue alloc] init] autorelease];
        [q setMaxConcurrentOperationCount:4];
        __block int arrived = 0;
        __block volatile BOOL met = YES, anyOnMain = NO;
        for (int i = 0; i < 2; i++)
            [q addOperationWithBlock:^{
                if ([NSThread isMainThread])
                    anyOnMain = YES;
                __atomic_add_fetch(&arrived, 1, __ATOMIC_SEQ_CST);
                int spins = 0;
                while (__atomic_load_n(&arrived, __ATOMIC_SEQ_CST) < 2 && spins++ < 4000)
                    usleep(1000);
                if (__atomic_load_n(&arrived, __ATOMIC_SEQ_CST) < 2)
                    met = NO;
            }];
        [q waitUntilAllOperationsAreFinished];
        printf("operation queue: two operations ran at once %d, any on the main thread %d\n", met, anyOnMain);
        __block int running = 0, worst = 0;
        for (int i = 0; i < 40; i++)
            [q addOperationWithBlock:^{
                int now = __atomic_add_fetch(&running, 1, __ATOMIC_SEQ_CST);
                int was;
                while ((was = __atomic_load_n(&worst, __ATOMIC_SEQ_CST)) < now &&
                       !__atomic_compare_exchange_n(&worst, &was, now, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
                    ;
                usleep(2000);
                __atomic_sub_fetch(&running, 1, __ATOMIC_SEQ_CST);
            }];
        [q waitUntilAllOperationsAreFinished];
        printf("operation queue limit 4: at most %d at once, more than one %d\n", worst, worst > 1);
        __block volatile BOOL mainOp = NO;
        __block BOOL mainOpOnMain = NO, currentIsMain = NO;
        [q addOperationWithBlock:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                mainOpOnMain = [NSThread isMainThread];
                currentIsMain = [NSOperationQueue currentQueue] == [NSOperationQueue mainQueue];
                mainOp = YES;
            }];
        }];
        wait_for(&mainOp);
        printf("main queue operation from a worker: on the main thread %d, current queue main %d\n", mainOpOnMain,
               currentIsMain);

        /* many threads at once, each with its own pool and dictionary */
        __block int good = 0;
        NSMutableArray *threads = [NSMutableArray array];
        for (int i = 0; i < 16; i++) {
            NSThread *th = [[[NSThread alloc] initWithBlock:^{
                @autoreleasepool {
                    NSMutableDictionary *d = [[NSThread currentThread] threadDictionary];
                    [d setObject:@(i) forKey:@"n"];
                    NSMutableArray *a = [NSMutableArray array];
                    for (int k = 0; k < 1000; k++)
                        [a addObject:[NSString stringWithFormat:@"%d-%d", i, k]];
                    if ([[d objectForKey:@"n"] intValue] == i && [a count] == 1000)
                        __atomic_add_fetch(&good, 1, __ATOMIC_SEQ_CST);
                }
            }] autorelease];
            [th setName:[NSString stringWithFormat:@"many-%02d", i]];
            [threads addObject:th];
        }
        for (NSThread *th in threads)
            [th start];
        for (NSThread *th in threads)
            while (![th isFinished])
                usleep(1000);
        usleep(20000); /* the will-exit notifications are posted before isFinished */
        NSArray *names;
        @synchronized(exited_names) {
            names = [[exited_names copy] autorelease];
        }
        int many = 0;
        for (NSString *n in names)
            if ([n hasPrefix:@"many-"])
                many++;
        printf("16 threads at once: all right %d, will-exit notifications from them %d, became multithreaded "
               "notified %d time(s)\n",
               good, many, multithreaded_notes);
        printf("first worker's exit was notified: %d\n", [names containsObject:@"first worker"]);
    }
    return 0;
}
