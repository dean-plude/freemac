/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSOperation, NSBlockOperation,
 * NSInvocationOperation and NSOperationQueue, and the locks (NSLock,
 * NSRecursiveLock, NSCondition, NSConditionLock).
 *
 * A queue runs its operations on libdispatch's worker threads: as many at
 * once as its maxConcurrentOperationCount allows, ready ones first and the
 * highest priority first, in the order they were added among equals. The
 * main queue runs its operations one at a time on the main thread, from the
 * main dispatch queue. Dependencies (across queues too), cancelling,
 * completion blocks (run on a worker thread once the operation has
 * finished), suspending, barriers, operations that finish later
 * ("asynchronous" ones that override -start) and the key-value
 * notifications of isExecuting, isFinished, isReady, isCancelled,
 * operations and operationCount are as Apple's documentation describes; the
 * notifications are sent on the thread that made the change. One recursive
 * lock (op_lock) guards every operation's and queue's state.
 *
 * waitUntilFinished, waitUntilAllOperationsAreFinished and
 * addOperations:waitUntilFinished:YES block the calling thread. On the main
 * thread they turn the run loop meanwhile, so that operations of the main
 * queue still run where a Mac would wait for ever; when nothing left could
 * end such a wait, it says so on standard error and returns.
 *
 * The locks are pthread mutexes and condition variables. A thread that
 * takes an NSLock it already holds, or a wait of the main thread that
 * nothing left could end, is a deadlock: Ferry says so and stops the
 * program, where a Mac would hang.
 *
 * Written from Apple's public documentation; no Apple code was used. */
#import "FInternal.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <pthread.h>

NSString *const NSInvocationOperationVoidResultException = @"NSInvocationOperationVoidResultException";
NSString *const NSInvocationOperationCancelledException = @"NSInvocationOperationCancelledException";

extern int ferry_dispatch_main_can_wake(void);  /* src/objc/dispatch.c */
extern void ferry_dispatch_stop(const char *why); /* src/objc/dispatch.c */

@interface NSRunLoop (FerryWake)
- (void)_wakeUp;
@end

/* ---- waiting ------------------------------------------------------------------- */

#define REFERENCE_TO_1970 978307200.0

/* Blocks on c (with m held) until it is signalled or limit passes (seconds
 * since the reference date). On the main thread a wait with no limit looks
 * every 250 ms whether anything could still wake it, and stops the program
 * with what's message if not. Returns 0 or ETIMEDOUT. */
int FCondWait(pthread_cond_t *c, pthread_mutex_t *m, NSTimeInterval limit, const char *what)
{
    BOOL forever = limit > 1e10;
    if (forever && pthread_main_np()) {
        if (!ferry_dispatch_main_can_wake()) {
            char msg[400];
            snprintf(msg, sizeof msg, "the program waits on the main thread for %s, which nothing left can do", what);
            ferry_dispatch_stop(msg);
        }
        limit = [NSDate timeIntervalSinceReferenceDate] + 0.25;
        forever = NO;
        struct timespec ts;
        double abs = limit + REFERENCE_TO_1970;
        ts.tv_sec = (time_t)abs;
        ts.tv_nsec = (long)((abs - (double)ts.tv_sec) * 1e9);
        pthread_cond_timedwait(c, m, &ts);
        return 0; /* the caller looks again either way */
    }
    if (forever)
        return pthread_cond_wait(c, m);
    struct timespec ts;
    double abs = limit + REFERENCE_TO_1970;
    if (abs < 0)
        abs = 0;
    ts.tv_sec = (time_t)abs;
    ts.tv_nsec = (long)((abs - (double)ts.tv_sec) * 1e9);
    return pthread_cond_timedwait(c, m, &ts);
}

/* Everything about operations and queues, and the condition broadcast
 * whenever an operation finishes or a queue empties. */
static pthread_mutex_t op_lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;
static pthread_cond_t op_cond = PTHREAD_COND_INITIALIZER;
static int main_waiting; /* the main thread is in run_until */
#define LOCK() pthread_mutex_lock(&op_lock)
#define UNLOCK() pthread_mutex_unlock(&op_lock)

/* Something an operation waits for may have happened. */
static void op_changed(void)
{
    LOCK();
    pthread_cond_broadcast(&op_cond);
    BOOL wake = main_waiting > 0;
    UNLOCK();
    if (wake)
        [[NSRunLoop mainRunLoop] _wakeUp];
}

/* Waits until done() says so (asked with op_lock held) or the limit passes.
 * Returns YES when done; NO on the limit, or when nothing is left that
 * could make it happen (then *stuck is set). */
static BOOL run_until(BOOL (^done)(void), NSTimeInterval limit, BOOL *stuck)
{
    if (stuck)
        *stuck = NO;
    BOOL ok;
    if (!pthread_main_np()) {
        LOCK();
        while (!(ok = done()))
            if (FCondWait(&op_cond, &op_lock, limit, "an operation") == ETIMEDOUT)
                break;
        if (!ok)
            ok = done();
        UNLOCK();
        return ok;
    }
    /* The main thread turns its run loop, so the main queue's work goes on. */
    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    LOCK();
    main_waiting++;
    UNLOCK();
    for (;;) {
        LOCK();
        ok = done();
        UNLOCK();
        if (ok)
            break;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now >= limit)
            break;
        NSTimeInterval until = limit < now + 0.25 ? limit : now + 0.25;
        if (![loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceReferenceDate:until]]) {
            /* nothing for the run loop: wait for another thread's operation */
            LOCK();
            if (!(ok = done())) {
                if (!ferry_dispatch_main_can_wake()) {
                    if (stuck)
                        *stuck = YES;
                    UNLOCK();
                    break;
                }
                FCondWait(&op_cond, &op_lock, until, "an operation");
            }
            UNLOCK();
        }
    }
    LOCK();
    main_waiting--;
    UNLOCK();
    return ok;
}
static void say_stuck(const char *what, id who)
{
    fprintf(stderr, "ferry: %s %s waits for something nothing left in the program can do; carrying on\n", what,
            [[who description] UTF8String]);
}

@interface NSOperationQueue ()
- (void)_finished:(NSOperation *)op;
- (void)_schedule;
@end
static void reschedule_queues(void);

/* ---- NSOperation ---------------------------------------------------------------- */

@interface NSOperation () {
@public
    BOOL _executing, _finished, _cancelled, _finishHandled, _started, _claimed;
    NSMutableArray *_dependencies;
    NSOperationQueuePriority _priority;
    void (^_completion)(void);
    NSString *_name;
    double _threadPriority;
    NSQualityOfService _qos;
    NSOperationQueue *_queue; /* the queue it was added to (not retained: the queue holds the operation) */
    BOOL _barrier;
}
- (void)_checkFinished;
@end

@implementation NSOperation
- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _dependencies = [[NSMutableArray alloc] init];
    _threadPriority = 0.5;
    _qos = NSQualityOfServiceDefault;
    return self;
}
- (void)dealloc
{
    [_dependencies release];
    [_completion release];
    [_name release];
    [super dealloc];
}
- (NSString *)description
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<%s %p", object_getClassName(self), self];
    if (_name)
        [s appendFormat:@" name='%@'", _name];
    [s appendFormat:@" isFinished=%s isReady=%s isCancelled=%s isExecuting=%s>", [self isFinished] ? "YES" : "NO",
                    [self isReady] ? "YES" : "NO", [self isCancelled] ? "YES" : "NO",
                    [self isExecuting] ? "YES" : "NO"];
    return s;
}

- (BOOL)isExecuting { return __atomic_load_n(&_executing, __ATOMIC_ACQUIRE); }
- (BOOL)isFinished { return __atomic_load_n(&_finished, __ATOMIC_ACQUIRE); }
- (BOOL)isCancelled { return __atomic_load_n(&_cancelled, __ATOMIC_ACQUIRE); }
- (BOOL)isAsynchronous { return NO; }
- (BOOL)isConcurrent { return [self isAsynchronous]; }
- (BOOL)isReady
{
    if ([self isCancelled])
        return YES; /* a cancelled operation no longer waits for its dependencies */
    LOCK();
    NSArray *deps = [_dependencies count] ? [_dependencies copy] : nil;
    UNLOCK();
    BOOL ready = YES;
    for (NSOperation *d in deps)
        if (![d isFinished]) {
            ready = NO;
            break;
        }
    [deps release];
    return ready;
}

/* Subclasses that finish later announce isFinished themselves; that is
 * when the completion block runs and the queue lets the operation go. */
- (void)didChangeValueForKey:(NSString *)key
{
    [super didChangeValueForKey:key];
    if ([key isEqualToString:@"isFinished"] || [key isEqualToString:@"finished"])
        [self _checkFinished];
    else if ([key isEqualToString:@"isReady"] || [key isEqualToString:@"ready"] ||
             [key isEqualToString:@"isExecuting"] || [key isEqualToString:@"executing"]) {
        LOCK();
        NSOperationQueue *q = [_queue retain];
        UNLOCK();
        [q _schedule];
        [q release];
    }
}
- (void)_checkFinished
{
    if (![self isFinished])
        return;
    LOCK();
    if (_finishHandled) {
        UNLOCK();
        return;
    }
    _finishHandled = YES;
    void (^completion)(void) = _completion;
    _completion = nil; /* it runs once, and is let go of then */
    NSOperationQueue *q = [_queue retain];
    UNLOCK();
    [self retain];
    if (completion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), completion);
        [completion release];
    }
    [q _finished:self];
    [q release];
    reschedule_queues(); /* operations that depended on this one may be ready now */
    op_changed();
    [self release];
}

- (void)start
{
    LOCK();
    if (_finished || _executing || _started) {
        UNLOCK();
        FRaise(NSInvalidArgumentException, @"*** -[%s start]: receiver is %s", object_getClassName(self),
               _finished ? "finished and cannot be started" : "already executing");
    }
    UNLOCK();
    if (![self isReady])
        FRaise(NSInvalidArgumentException, @"*** -[%s start]: receiver is not yet ready to execute",
               object_getClassName(self));
    LOCK();
    _started = YES;
    UNLOCK();
    [self retain];
    if (![self isCancelled]) {
        [self willChangeValueForKey:@"isExecuting"];
        __atomic_store_n(&_executing, YES, __ATOMIC_RELEASE);
        [self didChangeValueForKey:@"isExecuting"];
        @try {
            [self main];
        } @finally {
            [self willChangeValueForKey:@"isExecuting"];
            __atomic_store_n(&_executing, NO, __ATOMIC_RELEASE);
            [self didChangeValueForKey:@"isExecuting"];
        }
    }
    [self willChangeValueForKey:@"isFinished"];
    __atomic_store_n(&_finished, YES, __ATOMIC_RELEASE);
    [self didChangeValueForKey:@"isFinished"];
    [self release];
}
- (void)main {}
- (void)cancel
{
    LOCK();
    if (_cancelled || _finished) {
        UNLOCK();
        return;
    }
    UNLOCK();
    BOOL wasReady = [self isReady];
    [self willChangeValueForKey:@"isCancelled"];
    if (!wasReady)
        [self willChangeValueForKey:@"isReady"];
    __atomic_store_n(&_cancelled, YES, __ATOMIC_RELEASE);
    if (!wasReady)
        [self didChangeValueForKey:@"isReady"];
    [self didChangeValueForKey:@"isCancelled"];
    op_changed();
}

- (void)addDependency:(NSOperation *)op
{
    LOCK();
    BOOL have = !op || [_dependencies indexOfObjectIdenticalTo:op] != NSNotFound;
    UNLOCK();
    if (have)
        return;
    [self willChangeValueForKey:@"dependencies"];
    LOCK();
    [_dependencies addObject:op];
    UNLOCK();
    [self didChangeValueForKey:@"dependencies"];
}
- (void)removeDependency:(NSOperation *)op
{
    LOCK();
    BOOL have = [_dependencies indexOfObjectIdenticalTo:op] != NSNotFound;
    UNLOCK();
    if (!have)
        return;
    [self willChangeValueForKey:@"dependencies"];
    LOCK();
    [_dependencies removeObjectIdenticalTo:op];
    NSOperationQueue *q = [_queue retain];
    UNLOCK();
    [self didChangeValueForKey:@"dependencies"];
    [q _schedule];
    [q release];
}
- (NSArray *)dependencies
{
    LOCK();
    NSArray *a = [[_dependencies copy] autorelease];
    UNLOCK();
    return a;
}
- (NSOperationQueuePriority)queuePriority { return _priority; }
- (void)setQueuePriority:(NSOperationQueuePriority)p
{
    /* held to the five named values, as documented */
    _priority = p <= -6 ? NSOperationQueuePriorityVeryLow : p <= -2 ? NSOperationQueuePriorityLow
              : p < 2   ? NSOperationQueuePriorityNormal  : p < 6   ? NSOperationQueuePriorityHigh
                        : NSOperationQueuePriorityVeryHigh;
}
- (void (^)(void))completionBlock
{
    LOCK();
    id b = [[_completion retain] autorelease];
    UNLOCK();
    return b;
}
- (void)setCompletionBlock:(void (^)(void))block
{
    block = [block copy];
    LOCK();
    void (^old)(void) = _completion;
    _completion = block;
    UNLOCK();
    [old release];
}
- (NSString *)name
{
    LOCK();
    id n = [[_name retain] autorelease];
    UNLOCK();
    return n;
}
- (void)setName:(NSString *)name
{
    name = [name copy];
    LOCK();
    NSString *old = _name;
    _name = name;
    UNLOCK();
    [old release];
}
- (double)threadPriority { return _threadPriority; }
- (void)setThreadPriority:(double)p { _threadPriority = p; }
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (void)waitUntilFinished
{
    BOOL stuck;
    if (!run_until(^{ return [self isFinished]; }, [[NSDate distantFuture] timeIntervalSinceReferenceDate], &stuck) &&
        stuck)
        say_stuck("-[NSOperation waitUntilFinished]:", self);
}
@end

/* ---- NSBlockOperation ------------------------------------------------------------- */

@implementation NSBlockOperation {
    NSMutableArray *_blocks;
}
+ (instancetype)blockOperationWithBlock:(void (^)(void))block
{
    NSBlockOperation *op = [[[self alloc] init] autorelease];
    [op addExecutionBlock:block];
    return op;
}
- (instancetype)init
{
    if ((self = [super init]))
        _blocks = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc
{
    [_blocks release];
    [super dealloc];
}
- (void)addExecutionBlock:(void (^)(void))block
{
    if (!block)
        FRaise(NSInvalidArgumentException, @"*** -[NSBlockOperation addExecutionBlock:]: block is nil");
    if ([self isExecuting] || [self isFinished])
        FRaise(NSInvalidArgumentException, @"*** -[NSBlockOperation addExecutionBlock:]: blocks cannot be added "
                                           @"after the operation has started executing or finished");
    void (^copy)(void) = [block copy];
    LOCK();
    [_blocks addObject:copy];
    UNLOCK();
    [copy release];
}
- (NSArray *)executionBlocks
{
    LOCK();
    NSArray *a = [[_blocks copy] autorelease];
    UNLOCK();
    return a;
}
- (void)main
{
    /* One after another, in the order they were added. (A Mac may run
     * them at the same time; the documentation promises no order.) */
    LOCK();
    NSArray *blocks = [_blocks copy];
    UNLOCK();
    for (NSUInteger i = 0; i < [blocks count]; i++) {
        void (^b)(void) = [blocks objectAtIndex:i];
        b();
    }
    [blocks release];
}
@end

/* ---- NSInvocationOperation ------------------------------------------------------- */

@implementation NSInvocationOperation {
    NSInvocation *_invocation;
    NSException *_raised;
}
- (instancetype)initWithInvocation:(NSInvocation *)inv
{
    if (!(self = [super init]))
        return nil;
    _invocation = [inv retain];
    [_invocation retainArguments];
    return self;
}
- (instancetype)initWithTarget:(id)target selector:(SEL)sel object:(id)arg
{
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig) {
        [self release];
        return nil;
    }
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:target];
    [inv setSelector:sel];
    if ([sig numberOfArguments] > 2)
        [inv setArgument:&arg atIndex:2];
    return [self initWithInvocation:inv];
}
- (void)dealloc
{
    [_invocation release];
    [_raised release];
    [super dealloc];
}
- (NSInvocation *)invocation { return _invocation; }
- (void)main
{
    @try {
        [_invocation invoke];
    } @catch (NSException *e) {
        _raised = [e retain];
    }
}
- (id)result
{
    if (_cancelled)
        [[NSException exceptionWithName:NSInvocationOperationCancelledException
                                 reason:@"*** -[NSInvocationOperation result]: operation was cancelled"
                               userInfo:nil] raise];
    if (_raised)
        [_raised raise];
    if (!_finished)
        return nil;
    NSMethodSignature *sig = [_invocation methodSignature];
    const char *t = [sig methodReturnType];
    while (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'R' || *t == 'V')
        t++;
    if (*t == 'v')
        [[NSException exceptionWithName:NSInvocationOperationVoidResultException
                                 reason:@"*** -[NSInvocationOperation result]: void result"
                               userInfo:nil] raise];
    NSUInteger len = [sig methodReturnLength];
    void *buf = calloc(1, len < 16 ? 16 : len);
    [_invocation getReturnValue:buf];
    id r;
    switch (*t) {
    case '@':
    case '#': r = *(id *)buf; break;
    case 'c': r = [NSNumber numberWithChar:*(char *)buf]; break;
    case 'C': r = [NSNumber numberWithUnsignedChar:*(unsigned char *)buf]; break;
    case 'B': r = [NSNumber numberWithBool:*(BOOL *)buf]; break;
    case 's': r = [NSNumber numberWithShort:*(short *)buf]; break;
    case 'S': r = [NSNumber numberWithUnsignedShort:*(unsigned short *)buf]; break;
    case 'i': r = [NSNumber numberWithInt:*(int *)buf]; break;
    case 'I': r = [NSNumber numberWithUnsignedInt:*(unsigned *)buf]; break;
    case 'l': r = [NSNumber numberWithLong:*(long *)buf]; break;
    case 'L': r = [NSNumber numberWithUnsignedLong:*(unsigned long *)buf]; break;
    case 'q': r = [NSNumber numberWithLongLong:*(long long *)buf]; break;
    case 'Q': r = [NSNumber numberWithUnsignedLongLong:*(unsigned long long *)buf]; break;
    case 'f': r = [NSNumber numberWithFloat:*(float *)buf]; break;
    case 'd': r = [NSNumber numberWithDouble:*(double *)buf]; break;
    default: r = [NSData dataWithBytes:buf length:len]; break; /* a structure: its bytes */
    }
    free(buf);
    return r;
}
@end

/* An operation that waits for every operation added before it, and holds
 * back every operation added after it until it has run. */
@interface FBarrierOperation : NSBlockOperation
@end
@implementation FBarrierOperation
@end

/* ---- NSOperationQueue ------------------------------------------------------------ */

static NSMutableArray *busy_queues; /* queues with operations, kept while they have some */
static NSOperationQueue *main_queue;
static pthread_key_t current_key;   /* the queue whose operation this thread runs */
static dispatch_once_t current_once;

static void make_current_key(void *unused) { pthread_key_create(&current_key, NULL); }

/* At most this many of a queue's operations at once when it sets no limit. */
#define DEFAULT_WIDTH 64

@implementation NSOperationQueue {
    NSMutableArray *_ops;
    NSInteger _max;
    BOOL _suspended;
    NSString *_name;
    NSQualityOfService _qos;
    id _underlying;
    NSProgress *_progress;
}

static void run_operation(void *ctx);

+ (NSOperationQueue *)mainQueue
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      main_queue = [[NSOperationQueue alloc] init];
      main_queue->_max = 1;
      [main_queue setName:@"NSOperationQueue Main Queue"];
    });
    return main_queue;
}
+ (NSOperationQueue *)currentQueue
{
    dispatch_once_f(&current_once, NULL, make_current_key);
    NSOperationQueue *q = pthread_getspecific(current_key);
    if (q)
        return q;
    /* outside an operation, the main thread's is the main queue */
    return pthread_main_np() ? [self mainQueue] : nil;
}
- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _ops = [[NSMutableArray alloc] init];
    _max = NSOperationQueueDefaultMaxConcurrentOperationCount;
    _qos = NSQualityOfServiceDefault;
    _name = [[NSString alloc] initWithFormat:@"NSOperationQueue %p", self];
    return self;
}
- (void)dealloc
{
    for (NSOperation *op in _ops)
        op->_queue = nil;
    [_ops release];
    [_name release];
    [_underlying release];
    [_progress release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s %p>{name = '%@'}", object_getClassName(self), self, [self name]];
}

- (NSString *)name
{
    LOCK();
    id n = [[_name retain] autorelease];
    UNLOCK();
    return n;
}
- (void)setName:(NSString *)name
{
    name = [name copy];
    LOCK();
    NSString *old = _name;
    _name = name;
    UNLOCK();
    [old release];
}
- (NSInteger)maxConcurrentOperationCount { return _max; }
- (void)setMaxConcurrentOperationCount:(NSInteger)n
{
    if (n < -1)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue setMaxConcurrentOperationCount:]: count (%ld) "
                                           @"cannot be negative",
               (long)n);
    LOCK();
    _max = n;
    UNLOCK();
    [self _schedule];
}
- (BOOL)isSuspended { return _suspended; }
- (void)setSuspended:(BOOL)flag
{
    LOCK();
    _suspended = flag;
    UNLOCK();
    if (!flag)
        [self _schedule];
}
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (id)underlyingQueue
{
    LOCK();
    id u = [[_underlying retain] autorelease];
    UNLOCK();
    return u;
}
- (void)setUnderlyingQueue:(id)q
{
    if (self == main_queue)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue setUnderlyingQueue:]: the main queue's "
                                           @"underlying queue cannot be changed");
    [q retain];
    LOCK();
    id old = _underlying;
    _underlying = q;
    UNLOCK();
    [old release];
}
- (NSProgress *)progress
{
    LOCK();
    if (!_progress)
        _progress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    NSProgress *p = _progress;
    UNLOCK();
    return p;
}
- (NSArray *)operations
{
    LOCK();
    NSArray *a = [[_ops copy] autorelease];
    UNLOCK();
    return a;
}
- (NSUInteger)operationCount
{
    LOCK();
    NSUInteger n = [_ops count];
    UNLOCK();
    return n;
}

- (void)addOperation:(NSOperation *)op
{
    if (!op)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue addOperation:]: operation is nil");
    LOCK();
    const char *bad = op->_queue                                       ? "already enqueued on a queue"
                    : [op isFinished]                                   ? "finished and cannot be enqueued"
                    : [op isExecuting] || op->_started                  ? "executing and cannot be enqueued"
                                                                        : NULL;
    if (!bad)
        op->_queue = self; /* claimed for this queue */
    UNLOCK();
    if (bad)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue addOperation:]: operation is %s", bad);
    [self willChangeValueForKey:@"operations"];
    [self willChangeValueForKey:@"operationCount"];
    LOCK();
    if (![_ops count]) {
        if (!busy_queues)
            busy_queues = [[NSMutableArray alloc] init];
        [busy_queues addObject:self]; /* kept while it has operations */
    }
    [_ops addObject:op];
    UNLOCK();
    [self didChangeValueForKey:@"operationCount"];
    [self didChangeValueForKey:@"operations"];
    [self _schedule];
}
- (void)addOperations:(NSArray *)ops waitUntilFinished:(BOOL)wait
{
    for (NSOperation *op in ops)
        [self addOperation:op];
    if (!wait)
        return;
    BOOL stuck;
    if (!run_until(^{
            for (NSOperation *op in ops)
                if (![op isFinished])
                    return NO;
            return YES;
        },
                   [[NSDate distantFuture] timeIntervalSinceReferenceDate], &stuck) &&
        stuck)
        say_stuck("-[NSOperationQueue addOperations:waitUntilFinished:]:", self);
}
- (void)addOperationWithBlock:(void (^)(void))block
{
    [self addOperation:[NSBlockOperation blockOperationWithBlock:block]];
}
- (void)addBarrierBlock:(void (^)(void))barrier
{
    FBarrierOperation *op = [FBarrierOperation blockOperationWithBlock:barrier];
    op->_barrier = YES;
    for (NSOperation *o in [self operations])
        [op addDependency:o];
    [self addOperation:op];
}
- (void)cancelAllOperations
{
    for (NSOperation *op in [self operations])
        [op cancel];
}
- (void)waitUntilAllOperationsAreFinished
{
    BOOL stuck;
    if (!run_until(^{ return (BOOL)([_ops count] == 0); }, [[NSDate distantFuture] timeIntervalSinceReferenceDate],
                   &stuck) &&
        stuck)
        say_stuck("-[NSOperationQueue waitUntilAllOperationsAreFinished]:", self);
}

/* The next operation to start (op_lock held): ready, the highest
 * priority, the first added among equals, and none after a barrier that
 * hasn't run, while fewer than the limit are running. */
- (NSOperation *)_next
{
    NSInteger running = 0;
    NSOperation *best = nil;
    for (NSOperation *op in _ops) {
        if (op->_claimed) {
            /* running until the queue has heard it finished */
            if (!op->_finishHandled)
                running++;
            if (op->_barrier && !op->_finishHandled)
                break;
            continue;
        }
        if ([op isReady] && (!best || [op queuePriority] > [best queuePriority]))
            best = op;
        if (op->_barrier)
            break;
    }
    NSInteger width = _max >= 0 ? _max : DEFAULT_WIDTH;
    if (running >= width)
        return nil;
    return best;
}

/* Starts every operation that may start now, each on a thread of its own
 * (or, for the main queue, on the main thread). */
- (void)_schedule
{
    LOCK();
    NSOperation *op;
    while (!_suspended && (op = [self _next])) {
        op->_claimed = YES;
        [self retain];
        [op retain];
        void **ctx = malloc(2 * sizeof *ctx);
        ctx[0] = self;
        ctx[1] = op;
        dispatch_queue_t where;
        if (self == main_queue)
            where = dispatch_get_main_queue();
        else if (_underlying)
            where = _underlying;
        else {
            long qos = _qos == NSQualityOfServiceDefault ? (op->_qos == NSQualityOfServiceDefault ? 0 : op->_qos)
                                                          : _qos;
            where = dispatch_get_global_queue(qos, 0);
        }
        dispatch_async_f(where, ctx, run_operation);
    }
    UNLOCK();
}
- (void)_finished:(NSOperation *)op
{
    LOCK();
    NSUInteger i = [_ops indexOfObjectIdenticalTo:op];
    UNLOCK();
    if (i == NSNotFound)
        return;
    [[op retain] autorelease];
    [[self retain] autorelease];
    [self willChangeValueForKey:@"operations"];
    [self willChangeValueForKey:@"operationCount"];
    LOCK();
    i = [_ops indexOfObjectIdenticalTo:op];
    if (i != NSNotFound) {
        op->_queue = nil;
        [_ops removeObjectAtIndex:i];
        if (![_ops count])
            [busy_queues removeObjectIdenticalTo:self];
    }
    NSProgress *p = _progress;
    UNLOCK();
    [self didChangeValueForKey:@"operationCount"];
    [self didChangeValueForKey:@"operations"];
    if (p && [p totalUnitCount] > 0)
        [p setCompletedUnitCount:[p completedUnitCount] + 1];
    [self _schedule];
}

static void run_operation(void *ctx)
{
    void **pair = ctx;
    NSOperationQueue *q = pair[0];
    NSOperation *op = pair[1];
    free(ctx);
    dispatch_once_f(&current_once, NULL, make_current_key);
    void *saved = pthread_getspecific(current_key);
    pthread_setspecific(current_key, q);
    @try {
        @autoreleasepool {
            if ([op isFinished]) /* finished some other way meanwhile */
                ;
            else
                [op start];
        }
    } @finally {
        pthread_setspecific(current_key, saved);
        [op _checkFinished];
        [op release];
        [q _schedule]; /* the next one */
        [q release];
    }
}
@end

static void reschedule_queues(void)
{
    LOCK();
    NSArray *now = [busy_queues copy];
    UNLOCK();
    for (NSOperationQueue *q in now)
        [q _schedule];
    [now release];
}

/* ---- locks ------------------------------------------------------------------------ */

static NSString *lock_description(id lock, NSString *name)
{
    return [NSString stringWithFormat:@"<%s: %p>%@%@", object_getClassName(lock), lock, name ? @" " : @"",
                                      name ? name : @""];
}

/* The message a Mac prints when a lock is misused, with what is wrong. */
static void lock_error(id lock, const char *method, NSString *name, const char *what)
{
    fprintf(stderr, "*** -[%s %s]: %s (<%s: %p> '%s')\n*** Break on _NSLockError() to debug.\n",
            object_getClassName(lock), method, what, object_getClassName(lock), lock,
            name ? [name UTF8String] : "(null)");
}

/* A thread that waits for a lock it holds itself waits for ever. */
static void self_deadlock(id lock, const char *method, NSString *name)
{
    lock_error(lock, method, name, "deadlock");
    char msg[200];
    snprintf(msg, sizeof msg, "a thread waits for a %s it holds itself, which nothing can unlock",
             object_getClassName(lock));
    ferry_dispatch_stop(msg);
}

#define NAME_METHODS                                                                                                 \
    -(NSString *)name                                                                                                \
    {                                                                                                                \
        pthread_mutex_lock(&_m);                                                                                     \
        id n = [[_name retain] autorelease];                                                                         \
        pthread_mutex_unlock(&_m);                                                                                   \
        return n;                                                                                                    \
    }                                                                                                                \
    -(void)setName : (NSString *)name                                                                                \
    {                                                                                                                \
        name = [name copy];                                                                                          \
        pthread_mutex_lock(&_m);                                                                                     \
        NSString *old = _name;                                                                                       \
        _name = name;                                                                                                \
        pthread_mutex_unlock(&_m);                                                                                   \
        [old release];                                                                                               \
    }                                                                                                                \
    -(NSString *)description { return lock_description(self, [self name]); }

/* Each lock keeps its state under a small mutex of its own (_m), and
 * threads that wait for it sleep on _cv. */
@implementation NSLock {
    pthread_mutex_t _m;
    pthread_cond_t _cv;
    pthread_t _owner;
    BOOL _locked;
    NSString *_name;
}
- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_m, NULL);
        pthread_cond_init(&_cv, NULL);
    }
    return self;
}
- (void)dealloc
{
    pthread_mutex_destroy(&_m);
    pthread_cond_destroy(&_cv);
    [_name release];
    [super dealloc];
}
NAME_METHODS
- (BOOL)tryLock
{
    pthread_mutex_lock(&_m);
    BOOL got = !_locked;
    if (got) {
        _locked = YES;
        _owner = pthread_self();
    }
    pthread_mutex_unlock(&_m);
    return got;
}
- (BOOL)lockBeforeDate:(NSDate *)limit
{
    NSTimeInterval t = [limit timeIntervalSinceReferenceDate];
    pthread_mutex_lock(&_m);
    while (_locked && FCondWait(&_cv, &_m, t, "an NSLock") != ETIMEDOUT)
        ;
    BOOL got = !_locked;
    if (got) {
        _locked = YES;
        _owner = pthread_self();
    }
    pthread_mutex_unlock(&_m);
    return got;
}
- (void)lock
{
    pthread_mutex_lock(&_m);
    if (_locked && pthread_equal(_owner, pthread_self())) {
        pthread_mutex_unlock(&_m);
        self_deadlock(self, "lock", _name);
    }
    while (_locked)
        FCondWait(&_cv, &_m, 1e300, "an NSLock that another thread holds");
    _locked = YES;
    _owner = pthread_self();
    pthread_mutex_unlock(&_m);
}
- (void)unlock
{
    pthread_mutex_lock(&_m);
    if (!_locked)
        lock_error(self, "unlock", _name, "unlocked when not locked");
    else if (!pthread_equal(_owner, pthread_self()))
        lock_error(self, "unlock", _name, "unlocked from thread which did not lock it");
    _locked = NO;
    pthread_cond_signal(&_cv);
    pthread_mutex_unlock(&_m);
}
@end

@implementation NSRecursiveLock {
    pthread_mutex_t _m;
    pthread_cond_t _cv;
    pthread_t _owner;
    NSUInteger _depth;
    NSString *_name;
}
- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_m, NULL);
        pthread_cond_init(&_cv, NULL);
    }
    return self;
}
- (void)dealloc
{
    pthread_mutex_destroy(&_m);
    pthread_cond_destroy(&_cv);
    [_name release];
    [super dealloc];
}
NAME_METHODS
static BOOL take_recursive(pthread_t me, pthread_t *owner, NSUInteger *depth)
{
    if (*depth && !pthread_equal(*owner, me))
        return NO;
    *owner = me;
    ++*depth;
    return YES;
}
- (BOOL)tryLock
{
    pthread_mutex_lock(&_m);
    BOOL got = take_recursive(pthread_self(), &_owner, &_depth);
    pthread_mutex_unlock(&_m);
    return got;
}
- (BOOL)lockBeforeDate:(NSDate *)limit
{
    NSTimeInterval t = [limit timeIntervalSinceReferenceDate];
    pthread_t me = pthread_self();
    pthread_mutex_lock(&_m);
    BOOL got;
    while (!(got = take_recursive(me, &_owner, &_depth)))
        if (FCondWait(&_cv, &_m, t, "an NSRecursiveLock") == ETIMEDOUT) {
            got = take_recursive(me, &_owner, &_depth);
            break;
        }
    pthread_mutex_unlock(&_m);
    return got;
}
- (void)lock
{
    pthread_t me = pthread_self();
    pthread_mutex_lock(&_m);
    while (!take_recursive(me, &_owner, &_depth))
        FCondWait(&_cv, &_m, 1e300, "an NSRecursiveLock that another thread holds");
    pthread_mutex_unlock(&_m);
}
- (void)unlock
{
    pthread_mutex_lock(&_m);
    if (!_depth)
        lock_error(self, "unlock", _name, "unlocked when not locked");
    else if (!pthread_equal(_owner, pthread_self()))
        lock_error(self, "unlock", _name, "unlocked from thread which did not lock it");
    else if (--_depth == 0)
        pthread_cond_signal(&_cv);
    pthread_mutex_unlock(&_m);
}
@end

/* NSCondition: the lock is _locked and _owner, kept under _m; a wait lets
 * go of it, sleeps on _signal and takes it back. */
@implementation NSCondition {
    pthread_mutex_t _m;
    pthread_cond_t _cv;     /* the lock is free */
    pthread_cond_t _signal; /* signal and broadcast */
    pthread_t _owner;
    BOOL _locked;
    NSString *_name;
}
- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_m, NULL);
        pthread_cond_init(&_cv, NULL);
        pthread_cond_init(&_signal, NULL);
    }
    return self;
}
- (void)dealloc
{
    pthread_mutex_destroy(&_m);
    pthread_cond_destroy(&_cv);
    pthread_cond_destroy(&_signal);
    [_name release];
    [super dealloc];
}
NAME_METHODS
- (void)lock
{
    pthread_mutex_lock(&_m);
    if (_locked && pthread_equal(_owner, pthread_self())) {
        pthread_mutex_unlock(&_m);
        self_deadlock(self, "lock", _name);
    }
    while (_locked)
        FCondWait(&_cv, &_m, 1e300, "an NSCondition that another thread holds");
    _locked = YES;
    _owner = pthread_self();
    pthread_mutex_unlock(&_m);
}
- (void)unlock
{
    pthread_mutex_lock(&_m);
    if (!_locked)
        lock_error(self, "unlock", _name, "unlocked when not locked");
    _locked = NO;
    pthread_cond_signal(&_cv);
    pthread_mutex_unlock(&_m);
}
- (BOOL)waitUntilDate:(NSDate *)limit
{
    NSTimeInterval t = [limit timeIntervalSinceReferenceDate];
    pthread_mutex_lock(&_m);
    _locked = NO; /* a wait lets go of the lock while it waits */
    pthread_cond_signal(&_cv);
    /* (On the main thread a wait for ever wakes now and then to look
     * whether anything could still signal it, which a wait may: it is
     * allowed to end early.) */
    int rc = FCondWait(&_signal, &_m, t, "-[NSCondition wait] to be signalled");
    while (_locked) /* taken by another thread meanwhile: wait for it */
        FCondWait(&_cv, &_m, 1e300, "an NSCondition that another thread holds");
    _locked = YES;
    _owner = pthread_self();
    pthread_mutex_unlock(&_m);
    return rc != ETIMEDOUT;
}
- (void)wait { [self waitUntilDate:[NSDate distantFuture]]; }
- (void)signal
{
    pthread_mutex_lock(&_m);
    pthread_cond_signal(&_signal);
    pthread_mutex_unlock(&_m);
}
- (void)broadcast
{
    pthread_mutex_lock(&_m);
    pthread_cond_broadcast(&_signal);
    pthread_mutex_unlock(&_m);
}
@end

@implementation NSConditionLock {
    pthread_mutex_t _m;
    pthread_cond_t _cv; /* broadcast whenever the lock is let go */
    pthread_t _owner;
    NSInteger _condition;
    BOOL _locked;
    NSString *_name;
}
- (instancetype)init { return [self initWithCondition:0]; }
- (instancetype)initWithCondition:(NSInteger)condition
{
    if ((self = [super init])) {
        pthread_mutex_init(&_m, NULL);
        pthread_cond_init(&_cv, NULL);
        _condition = condition;
    }
    return self;
}
- (void)dealloc
{
    pthread_mutex_destroy(&_m);
    pthread_cond_destroy(&_cv);
    [_name release];
    [super dealloc];
}
NAME_METHODS
- (NSInteger)condition
{
    pthread_mutex_lock(&_m);
    NSInteger c = _condition;
    pthread_mutex_unlock(&_m);
    return c;
}
/* Takes the lock when it is free and, if any, the condition is c; waits
 * until limit for that. */
- (BOOL)_take:(BOOL)any condition:(NSInteger)c before:(NSTimeInterval)limit method:(const char *)method
{
    pthread_mutex_lock(&_m);
    if (limit > 1e10 && _locked && pthread_equal(_owner, pthread_self())) {
        pthread_mutex_unlock(&_m);
        self_deadlock(self, method, _name);
    }
    char what[120];
    snprintf(what, sizeof what, any ? "an NSConditionLock" : "an NSConditionLock's condition %ld", (long)c);
    BOOL got;
    for (;;) {
        got = !_locked && (any || _condition == c);
        if (got || limit <= 0)
            break;
        if (FCondWait(&_cv, &_m, limit, what) == ETIMEDOUT) {
            got = !_locked && (any || _condition == c);
            break;
        }
    }
    if (got) {
        _locked = YES;
        _owner = pthread_self();
    }
    pthread_mutex_unlock(&_m);
    return got;
}
- (BOOL)tryLock { return [self _take:YES condition:0 before:0 method:"tryLock"]; }
- (BOOL)tryLockWhenCondition:(NSInteger)c { return [self _take:NO condition:c before:0 method:"tryLockWhenCondition:"]; }
- (BOOL)lockBeforeDate:(NSDate *)limit
{
    return [self _take:YES condition:0 before:[limit timeIntervalSinceReferenceDate] method:"lockBeforeDate:"];
}
- (BOOL)lockWhenCondition:(NSInteger)c beforeDate:(NSDate *)limit
{
    return [self _take:NO condition:c before:[limit timeIntervalSinceReferenceDate] method:"lockWhenCondition:beforeDate:"];
}
- (void)lock { [self _take:YES condition:0 before:1e300 method:"lock"]; }
- (void)lockWhenCondition:(NSInteger)c { [self _take:NO condition:c before:1e300 method:"lockWhenCondition:"]; }
- (void)_unlockSetting:(BOOL)set condition:(NSInteger)c method:(const char *)method
{
    pthread_mutex_lock(&_m);
    if (!_locked)
        lock_error(self, method, _name, "unlocked when not locked");
    else if (!pthread_equal(_owner, pthread_self()))
        lock_error(self, method, _name, "unlocked from thread which did not lock it");
    if (set)
        _condition = c;
    _locked = NO;
    pthread_cond_broadcast(&_cv);
    pthread_mutex_unlock(&_m);
}
- (void)unlock { [self _unlockSetting:NO condition:0 method:"unlock"]; }
- (void)unlockWithCondition:(NSInteger)c { [self _unlockSetting:YES condition:c method:"unlockWithCondition:"]; }
@end
