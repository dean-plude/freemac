/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSOperation, NSBlockOperation,
 * NSInvocationOperation and NSOperationQueue, and the locks (NSLock,
 * NSRecursiveLock, NSCondition, NSConditionLock).
 *
 * Ferry runs a program on one thread, so a queue's operations run on it
 * too: a queue hands its ready operations to the main dispatch queue one
 * at a time, highest priority first, and they run when the run loop turns
 * or a dispatch wait runs work. Dependencies, cancelling, completion
 * blocks, suspending, barriers, the limit on operations running at once
 * (which only matters for operations that finish later, "asynchronous"
 * ones that override -start) and the key-value notifications of
 * isExecuting, isFinished, isReady, isCancelled, operations and
 * operationCount are as Apple's documentation describes. A wait
 * (waitUntilFinished, waitUntilAllOperationsAreFinished, a lock that is
 * taken, -[NSCondition wait]) runs the run loop until what it waits for
 * happens; when nothing left could make it happen, where a Mac would wait
 * forever, it says so on standard error and returns.
 *
 * Written from Apple's public documentation; no Apple code was used. */
#import "FInternal.h"
#include <dispatch/dispatch.h>

NSString *const NSInvocationOperationVoidResultException = @"NSInvocationOperationVoidResultException";
NSString *const NSInvocationOperationCancelledException = @"NSInvocationOperationCancelledException";

/* Runs the run loop until done() says so or the time limit passes. Returns
 * YES when done; NO on the time limit, or when nothing is left that could
 * make it happen (then *stuck is set). */
static BOOL run_until(BOOL (^done)(void), NSTimeInterval limit, BOOL *stuck)
{
    if (stuck)
        *stuck = NO;
    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    while (!done()) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now >= limit)
            return NO;
        NSDate *before = [NSDate dateWithTimeIntervalSinceReferenceDate:limit < now + 0.25 ? limit : now + 0.25];
        if (![loop runMode:NSDefaultRunLoopMode beforeDate:before] && !done()) {
            if (stuck)
                *stuck = YES;
            return NO;
        }
    }
    return YES;
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
    BOOL _executing, _finished, _cancelled, _finishHandled, _started;
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

- (BOOL)isExecuting { return _executing; }
- (BOOL)isFinished { return _finished; }
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isAsynchronous { return NO; }
- (BOOL)isConcurrent { return [self isAsynchronous]; }
- (BOOL)isReady
{
    if (_cancelled)
        return YES; /* a cancelled operation no longer waits for its dependencies */
    for (NSOperation *d in _dependencies)
        if (![d isFinished])
            return NO;
    return YES;
}

/* Subclasses that finish later announce isFinished themselves; that is
 * when the completion block runs and the queue lets the operation go. */
- (void)didChangeValueForKey:(NSString *)key
{
    [super didChangeValueForKey:key];
    if ([key isEqualToString:@"isFinished"] || [key isEqualToString:@"finished"])
        [self _checkFinished];
    else if ([key isEqualToString:@"isReady"] || [key isEqualToString:@"ready"] ||
             [key isEqualToString:@"isExecuting"] || [key isEqualToString:@"executing"])
        [_queue _schedule];
}
- (void)_checkFinished
{
    if (_finishHandled || ![self isFinished])
        return;
    _finishHandled = YES;
    [self retain];
    void (^completion)(void) = _completion;
    _completion = nil; /* it runs once, and is let go of then */
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), completion);
        [completion release];
    }
    [_queue _finished:self];
    reschedule_queues(); /* operations that depended on this one may be ready now */
    [self release];
}

- (void)start
{
    if (_finished || _executing || _started)
        FRaise(NSInvalidArgumentException, @"*** -[%s start]: receiver is %s", object_getClassName(self),
               _finished ? "finished and cannot be started" : "already executing");
    if (![self isReady])
        FRaise(NSInvalidArgumentException, @"*** -[%s start]: receiver is not yet ready to execute",
               object_getClassName(self));
    _started = YES;
    [self retain];
    if (!_cancelled) {
        [self willChangeValueForKey:@"isExecuting"];
        _executing = YES;
        [self didChangeValueForKey:@"isExecuting"];
        @try {
            [self main];
        } @finally {
            [self willChangeValueForKey:@"isExecuting"];
            _executing = NO;
            [self didChangeValueForKey:@"isExecuting"];
        }
    }
    [self willChangeValueForKey:@"isFinished"];
    _finished = YES;
    [self didChangeValueForKey:@"isFinished"];
    [self release];
}
- (void)main {}
- (void)cancel
{
    if (_cancelled || _finished)
        return;
    BOOL wasReady = [self isReady];
    [self willChangeValueForKey:@"isCancelled"];
    if (!wasReady)
        [self willChangeValueForKey:@"isReady"];
    _cancelled = YES;
    if (!wasReady)
        [self didChangeValueForKey:@"isReady"];
    [self didChangeValueForKey:@"isCancelled"];
}

- (void)addDependency:(NSOperation *)op
{
    if (!op || [_dependencies indexOfObjectIdenticalTo:op] != NSNotFound)
        return;
    [self willChangeValueForKey:@"dependencies"];
    [_dependencies addObject:op];
    [self didChangeValueForKey:@"dependencies"];
}
- (void)removeDependency:(NSOperation *)op
{
    if ([_dependencies indexOfObjectIdenticalTo:op] == NSNotFound)
        return;
    [self willChangeValueForKey:@"dependencies"];
    [_dependencies removeObjectIdenticalTo:op];
    [self didChangeValueForKey:@"dependencies"];
    [_queue _schedule];
}
- (NSArray *)dependencies { return [[_dependencies copy] autorelease]; }
- (NSOperationQueuePriority)queuePriority { return _priority; }
- (void)setQueuePriority:(NSOperationQueuePriority)p
{
    /* held to the five named values, as documented */
    _priority = p <= -6 ? NSOperationQueuePriorityVeryLow : p <= -2 ? NSOperationQueuePriorityLow
              : p < 2   ? NSOperationQueuePriorityNormal  : p < 6   ? NSOperationQueuePriorityHigh
                        : NSOperationQueuePriorityVeryHigh;
}
- (void (^)(void))completionBlock { return [[_completion retain] autorelease]; }
- (void)setCompletionBlock:(void (^)(void))block
{
    block = [block copy];
    [_completion release];
    _completion = block;
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
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
    if (_executing || _finished)
        FRaise(NSInvalidArgumentException, @"*** -[NSBlockOperation addExecutionBlock:]: blocks cannot be added "
                                           @"after the operation has started executing or finished");
    void (^copy)(void) = [block copy];
    [_blocks addObject:copy];
    [copy release];
}
- (NSArray *)executionBlocks { return [[_blocks copy] autorelease]; }
- (void)main
{
    /* one after another, in the order they were added */
    for (NSUInteger i = 0; i < [_blocks count]; i++) {
        void (^b)(void) = [_blocks objectAtIndex:i];
        b();
    }
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

static NSOperationQueue **live_queues;
static size_t live_count, live_room;
static NSOperationQueue *running_queue; /* whose operation is running now */
static NSOperationQueue *main_queue;

@implementation NSOperationQueue {
    NSMutableArray *_ops;
    NSInteger _max;
    BOOL _suspended, _scheduled;
    NSString *_name;
    NSQualityOfService _qos;
    id _underlying;
    NSProgress *_progress;
}

static void pump(void *ctx);

+ (NSOperationQueue *)mainQueue
{
    if (!main_queue) {
        main_queue = [[NSOperationQueue alloc] init];
        main_queue->_max = 1;
        [main_queue setName:@"NSOperationQueue Main Queue"];
    }
    return main_queue;
}
+ (NSOperationQueue *)currentQueue
{
    /* the program's one thread is the main thread: outside an operation,
     * that is the main queue's */
    return running_queue ? running_queue : [self mainQueue];
}
- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _ops = [[NSMutableArray alloc] init];
    _max = NSOperationQueueDefaultMaxConcurrentOperationCount;
    _qos = NSQualityOfServiceDefault;
    _name = [[NSString alloc] initWithFormat:@"NSOperationQueue %p", self];
    if (live_count == live_room) {
        live_room = live_room ? live_room * 2 : 8;
        live_queues = realloc(live_queues, live_room * sizeof *live_queues);
    }
    live_queues[live_count++] = self;
    return self;
}
- (void)dealloc
{
    for (size_t i = 0; i < live_count; i++)
        if (live_queues[i] == self) {
            live_queues[i] = live_queues[--live_count];
            break;
        }
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
    return [NSString stringWithFormat:@"<%s %p>{name = '%@'}", object_getClassName(self), self, _name];
}

- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}
- (NSInteger)maxConcurrentOperationCount { return _max; }
- (void)setMaxConcurrentOperationCount:(NSInteger)n
{
    if (n < -1)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue setMaxConcurrentOperationCount:]: count (%ld) "
                                           @"cannot be negative",
               (long)n);
    _max = n;
    [self _schedule];
}
- (BOOL)isSuspended { return _suspended; }
- (void)setSuspended:(BOOL)flag
{
    _suspended = flag;
    if (!flag)
        [self _schedule];
}
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (id)underlyingQueue { return _underlying; }
- (void)setUnderlyingQueue:(id)q
{
    [q retain];
    [_underlying release];
    _underlying = q;
}
- (NSProgress *)progress
{
    if (!_progress)
        _progress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    return _progress;
}
- (NSArray *)operations { return [[_ops copy] autorelease]; }
- (NSUInteger)operationCount { return [_ops count]; }

- (void)addOperation:(NSOperation *)op
{
    if (!op)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue addOperation:]: operation is nil");
    if (op->_queue)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue addOperation:]: operation is already enqueued "
                                           @"on a queue");
    if (op->_executing || op->_finished)
        FRaise(NSInvalidArgumentException, @"*** -[NSOperationQueue addOperation:]: operation is %s",
               op->_finished ? "finished and cannot be enqueued" : "executing and cannot be enqueued");
    [self willChangeValueForKey:@"operations"];
    [self willChangeValueForKey:@"operationCount"];
    op->_queue = self;
    [_ops addObject:op];
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
    for (NSOperation *o in _ops)
        [op addDependency:o];
    [self addOperation:op];
}
- (void)cancelAllOperations
{
    for (NSOperation *op in [[_ops copy] autorelease])
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

- (void)_schedule
{
    if (_scheduled || _suspended || ![_ops count])
        return;
    _scheduled = YES;
    [self retain];
    dispatch_async_f(dispatch_get_main_queue(), self, pump);
}
- (void)_finished:(NSOperation *)op
{
    NSUInteger i = [_ops indexOfObjectIdenticalTo:op];
    if (i == NSNotFound)
        return;
    [[op retain] autorelease];
    [self willChangeValueForKey:@"operations"];
    [self willChangeValueForKey:@"operationCount"];
    op->_queue = nil;
    [_ops removeObjectAtIndex:i];
    [self didChangeValueForKey:@"operationCount"];
    [self didChangeValueForKey:@"operations"];
    if (_progress && [_progress totalUnitCount] > 0)
        [_progress setCompletedUnitCount:[_progress completedUnitCount] + 1];
    [self _schedule];
}

/* The next operation to start: ready, the highest priority, the first
 * added among equals, and none after a barrier that hasn't run. */
- (NSOperation *)_next
{
    NSInteger running = 0;
    NSOperation *best = nil;
    for (NSOperation *op in _ops) {
        if (op->_started) {
            if (![op isFinished])
                running++;
            if (op->_barrier && ![op isFinished])
                break;
            continue;
        }
        if ([op isReady] && (!best || [op queuePriority] > [best queuePriority]))
            best = op;
        if (op->_barrier)
            break;
    }
    if (_max >= 0 && running >= _max)
        return nil;
    return best;
}

static void pump(void *ctx)
{
    NSOperationQueue *q = ctx;
    q->_scheduled = NO;
    NSOperation *op = q->_suspended ? nil : [q _next];
    if (op) {
        NSOperationQueue *saved = running_queue;
        running_queue = q;
        [op retain];
        @try {
            [op start];
        } @finally {
            running_queue = saved;
            op->_started = YES;
            [op _checkFinished];
            [op release];
        }
        [q _schedule]; /* the next one, after other work has had a turn */
    }
    [q release];
}
@end

static void reschedule_queues(void)
{
    for (size_t i = 0; i < live_count; i++)
        [live_queues[i] _schedule];
}

/* ---- locks ------------------------------------------------------------------------ */

static NSString *lock_description(id lock, NSString *name)
{
    return [NSString stringWithFormat:@"<%s: %p>%@%@", object_getClassName(lock), lock, name ? @" " : @"",
                                      name ? name : @""];
}

@implementation NSLock {
    BOOL _locked;
    NSString *_name;
}
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}
- (NSString *)description { return lock_description(self, _name); }
- (BOOL)tryLock
{
    if (_locked)
        return NO;
    _locked = YES;
    return YES;
}
- (BOOL)lockBeforeDate:(NSDate *)limit
{
    if (run_until(^{ return (BOOL)!_locked; }, [limit timeIntervalSinceReferenceDate], NULL))
        return [self tryLock];
    return NO;
}
- (void)lock
{
    BOOL stuck = NO;
    if (_locked && !run_until(^{ return (BOOL)!_locked; }, [[NSDate distantFuture] timeIntervalSinceReferenceDate],
                              &stuck))
        fprintf(stderr, "*** -[NSLock lock]: deadlock (%s)\nferry: nothing left can unlock it; carrying on\n",
                [[self description] UTF8String]);
    _locked = YES;
}
- (void)unlock
{
    if (!_locked)
        fprintf(stderr, "*** -[NSLock unlock]: lock (%s) unlocked when not locked\n", [[self description] UTF8String]);
    _locked = NO;
}
@end

/* On one thread, every caller is the thread that holds the lock. */
@implementation NSRecursiveLock {
    NSUInteger _depth;
    NSString *_name;
}
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}
- (NSString *)description { return lock_description(self, _name); }
- (BOOL)tryLock
{
    _depth++;
    return YES;
}
- (BOOL)lockBeforeDate:(NSDate *)limit { return [self tryLock]; }
- (void)lock { _depth++; }
- (void)unlock
{
    if (!_depth)
        fprintf(stderr, "*** -[NSRecursiveLock unlock]: lock (%s) unlocked when not locked\n",
                [[self description] UTF8String]);
    else
        _depth--;
}
@end

@implementation NSCondition {
    BOOL _locked;
    NSString *_name;
    NSMutableArray *_waiters; /* one NSMutableData flag per wait in progress, innermost last */
}
- (instancetype)init
{
    if ((self = [super init]))
        _waiters = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc
{
    [_name release];
    [_waiters release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}
- (NSString *)description { return lock_description(self, _name); }
- (void)lock
{
    BOOL stuck = NO;
    if (_locked && !run_until(^{ return (BOOL)!_locked; }, [[NSDate distantFuture] timeIntervalSinceReferenceDate],
                              &stuck))
        fprintf(stderr, "*** -[NSCondition lock]: deadlock (%s)\nferry: nothing left can unlock it; carrying on\n",
                [[self description] UTF8String]);
    _locked = YES;
}
- (void)unlock
{
    if (!_locked)
        fprintf(stderr, "*** -[NSCondition unlock]: condition (%s) unlocked when not locked\n",
                [[self description] UTF8String]);
    _locked = NO;
}
- (BOOL)waitUntilDate:(NSDate *)limit
{
    NSMutableData *flag = [NSMutableData dataWithLength:1];
    char *signalled = [flag mutableBytes];
    [_waiters addObject:flag];
    _locked = NO; /* a wait lets go of the lock while it waits */
    BOOL stuck = NO;
    BOOL ok = run_until(^{ return (BOOL)(*signalled != 0); }, [limit timeIntervalSinceReferenceDate], &stuck);
    [_waiters removeObjectIdenticalTo:flag];
    if (stuck && [limit timeIntervalSinceNow] > 1e9)
        fprintf(stderr, "ferry: -[NSCondition wait] on %s: nothing left can signal it; carrying on\n",
                [[self description] UTF8String]);
    if (_locked) /* taken again while this wait ran: wait for it */
        run_until(^{ return (BOOL)!_locked; }, [[NSDate distantFuture] timeIntervalSinceReferenceDate], NULL);
    _locked = YES;
    return ok;
}
- (void)wait { [self waitUntilDate:[NSDate distantFuture]]; }
- (void)signal
{
    /* the innermost wait: on one thread it is the only one that can go on */
    for (NSUInteger i = [_waiters count]; i > 0; i--) {
        char *f = [[_waiters objectAtIndex:i - 1] mutableBytes];
        if (!*f) {
            *f = 1;
            return;
        }
    }
}
- (void)broadcast
{
    for (NSMutableData *d in _waiters)
        *(char *)[d mutableBytes] = 1;
}
@end

@implementation NSConditionLock {
    NSInteger _condition;
    BOOL _locked;
    NSString *_name;
}
- (instancetype)init { return [self initWithCondition:0]; }
- (instancetype)initWithCondition:(NSInteger)condition
{
    if ((self = [super init]))
        _condition = condition;
    return self;
}
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
}
- (NSString *)description { return lock_description(self, _name); }
- (NSInteger)condition { return _condition; }
- (BOOL)tryLock
{
    if (_locked)
        return NO;
    _locked = YES;
    return YES;
}
- (BOOL)tryLockWhenCondition:(NSInteger)c
{
    if (_locked || _condition != c)
        return NO;
    _locked = YES;
    return YES;
}
- (BOOL)lockBeforeDate:(NSDate *)limit
{
    return run_until(^{ return (BOOL)!_locked; }, [limit timeIntervalSinceReferenceDate], NULL) && [self tryLock];
}
- (BOOL)lockWhenCondition:(NSInteger)c beforeDate:(NSDate *)limit
{
    return run_until(^{ return (BOOL)(!_locked && _condition == c); }, [limit timeIntervalSinceReferenceDate], NULL) &&
           [self tryLockWhenCondition:c];
}
- (void)lock
{
    BOOL stuck = NO;
    if (!run_until(^{ return (BOOL)!_locked; }, [[NSDate distantFuture] timeIntervalSinceReferenceDate], &stuck))
        fprintf(stderr, "*** -[NSConditionLock lock]: deadlock (%s)\nferry: nothing left can unlock it; carrying on\n",
                [[self description] UTF8String]);
    _locked = YES;
}
- (void)lockWhenCondition:(NSInteger)c
{
    BOOL stuck = NO;
    if (!run_until(^{ return (BOOL)(!_locked && _condition == c); },
                   [[NSDate distantFuture] timeIntervalSinceReferenceDate], &stuck))
        fprintf(stderr, "ferry: -[NSConditionLock lockWhenCondition:%ld] on %s: nothing left can set that "
                        "condition; carrying on\n",
                (long)c, [[self description] UTF8String]);
    _locked = YES;
}
- (void)unlock
{
    if (!_locked)
        fprintf(stderr, "*** -[NSConditionLock unlock]: lock (%s) unlocked when not locked\n",
                [[self description] UTF8String]);
    _locked = NO;
}
- (void)unlockWithCondition:(NSInteger)c
{
    _condition = c;
    [self unlock];
}
@end
