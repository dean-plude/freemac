/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSThread, and performing selectors on other threads
 * (performSelectorOnMainThread:..., performSelector:onThread:...,
 * performSelectorInBackground:...). Written from Apple's public API
 * documentation.
 *
 * An NSThread runs on one of Ferry's real threads (pthread_create, in
 * src/pthread.c). Every thread, including ones NSThread didn't start (the
 * main thread, dispatch's workers, a program's own pthreads), gets an
 * NSThread object the first time it asks for +currentThread, kept in a
 * thread-specific slot and released when the thread ends. The object also
 * holds the thread's run loop, made when first wanted, which is where
 * selectors performed on that thread are delivered: they run when the
 * thread runs its run loop, as on a Mac. */
#import "FInternal.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <os/lock.h>
#include <pthread.h>
#include <time.h>

NSNotificationName const NSWillBecomeMultiThreadedNotification = @"NSWillBecomeMultiThreadedNotification";
NSNotificationName const NSDidBecomeSingleThreadedNotification = @"NSDidBecomeSingleThreadedNotification";
NSNotificationName const NSThreadWillExitNotification = @"NSThreadWillExitNotification";

@interface NSRunLoop ()
- (instancetype)_initForMainThread:(BOOL)isMain;
@end

#define MAC_DEFAULT_STACK (512 * 1024) /* a secondary thread's stack on a Mac */

static pthread_t main_pthread;
static pthread_key_t thread_key;
static BOOL multithreaded;
static NSInteger thread_numbers = 1; /* the main thread is number 1 */

static void thread_key_gone(void *value);

__attribute__((constructor)) static void note_main_thread(void)
{
    main_pthread = pthread_self();
    pthread_key_create(&thread_key, thread_key_gone);
}

@implementation NSThread {
    id _target;
    SEL _selector;
    id _argument;
    void (^_block)(void);
    NSMutableDictionary *_dictionary;
    NSString *_name;
    NSUInteger _stackSize;
    double _priority;
    NSQualityOfService _qos;
    BOOL _started, _executing, _finished, _cancelled, _isMain;
    NSInteger _number;
    NSRunLoop *_runLoop;
    os_unfair_lock _lock;
}

static NSThread *main_thread_object;

static NSThread *make_main_thread(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSThread *t = [[NSThread alloc] init];
      t->_isMain = YES;
      t->_number = 1;
      t->_started = t->_executing = YES;
      t->_name = [@"main" copy];
      main_thread_object = t;
    });
    return main_thread_object;
}

/* The run loop of a thread (made when first asked for). */
NSRunLoop *FRunLoopOfThread(NSThread *thread, BOOL create)
{
    if (!thread)
        return nil;
    os_unfair_lock_lock(&thread->_lock);
    if (!thread->_runLoop && create)
        thread->_runLoop = [[NSRunLoop alloc] _initForMainThread:thread->_isMain];
    NSRunLoop *loop = thread->_runLoop;
    os_unfair_lock_unlock(&thread->_lock);
    return loop;
}

static void thread_key_gone(void *value)
{
    @autoreleasepool {
        [(NSThread *)value release];
    }
}

+ (NSThread *)currentThread
{
    NSThread *t = pthread_getspecific(thread_key);
    if (t)
        return t;
    if (pthread_equal(pthread_self(), main_pthread)) {
        t = [make_main_thread() retain];
    } else {
        /* a thread NSThread didn't start: dispatch's workers, the program's own pthreads */
        t = [[NSThread alloc] init];
        t->_started = t->_executing = YES;
    }
    pthread_setspecific(thread_key, t);
    return t;
}
+ (NSThread *)mainThread { return make_main_thread(); }
+ (BOOL)isMainThread { return pthread_main_np() != 0; }
+ (BOOL)isMultiThreaded { return multithreaded; }

- (instancetype)init
{
    _lock = OS_UNFAIR_LOCK_INIT;
    _priority = 0.5;
    _qos = NSQualityOfServiceDefault;
    _number = __atomic_add_fetch(&thread_numbers, 1, __ATOMIC_RELAXED);
    return self;
}
- (instancetype)initWithTarget:(id)target selector:(SEL)selector object:(id)argument
{
    if (!(self = [self init]))
        return nil;
    _target = [target retain];
    _selector = selector;
    _argument = [argument retain];
    return self;
}
- (instancetype)initWithBlock:(void (^)(void))block
{
    if (!(self = [self init]))
        return nil;
    _block = [block copy];
    return self;
}
- (void)dealloc
{
    [_target release];
    [_argument release];
    [_block release];
    [_dictionary release];
    [_name release];
    [_runLoop release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p>{number = %ld, name = %@}", _isMain ? @"_NSMainThread" : @"NSThread",
                                      self, (long)_number, _name ?: @"(null)"];
}

- (NSMutableDictionary *)threadDictionary
{
    os_unfair_lock_lock(&_lock);
    if (!_dictionary)
        _dictionary = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *d = _dictionary;
    os_unfair_lock_unlock(&_lock);
    return d;
}
- (NSString *)name
{
    os_unfair_lock_lock(&_lock);
    NSString *n = [[_name retain] autorelease];
    os_unfair_lock_unlock(&_lock);
    return n;
}
- (void)setName:(NSString *)name
{
    NSString *copy = [name copy];
    os_unfair_lock_lock(&_lock);
    NSString *old = _name;
    _name = copy;
    os_unfair_lock_unlock(&_lock);
    [old release];
    if (pthread_getspecific(thread_key) == self && !_isMain)
        pthread_setname_np([name UTF8String] ?: "");
}
- (NSUInteger)stackSize
{
    if (_isMain)
        return pthread_get_stacksize_np(main_pthread);
    return _stackSize ?: MAC_DEFAULT_STACK;
}
- (void)setStackSize:(NSUInteger)size
{
    if (!_started)
        _stackSize = size;
}
- (double)threadPriority { return _priority; }
- (void)setThreadPriority:(double)p { _priority = p < 0 ? 0 : p > 1 ? 1 : p; }
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)qos
{
    if (!_started)
        _qos = qos;
}
- (BOOL)isMainThread { return _isMain; }
- (BOOL)isExecuting { return __atomic_load_n(&_executing, __ATOMIC_ACQUIRE); }
- (BOOL)isFinished { return __atomic_load_n(&_finished, __ATOMIC_ACQUIRE); }
- (BOOL)isCancelled { return __atomic_load_n(&_cancelled, __ATOMIC_ACQUIRE); }
- (void)cancel { __atomic_store_n(&_cancelled, YES, __ATOMIC_RELEASE); }

- (void)main
{
    if (_block)
        _block();
    else if (_target)
        ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, _argument);
}

/* The thread is about to end: tell the observers, on the thread itself. */
static void thread_ending(NSThread *t)
{
    if (t->_finished)
        return;
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] postNotificationName:NSThreadWillExitNotification object:t];
    }
    __atomic_store_n(&t->_executing, NO, __ATOMIC_RELEASE);
    __atomic_store_n(&t->_finished, YES, __ATOMIC_RELEASE);
    /* a Mac keeps the target and argument until the thread has run */
    id target = t->_target, argument = t->_argument;
    void (^block)(void) = t->_block;
    t->_target = t->_argument = nil;
    t->_block = nil;
    [target release];
    [argument release];
    [block release];
}

static void *thread_body(void *arg)
{
    NSThread *t = arg; /* the reference start took is the thread's own now */
    pthread_setspecific(thread_key, t);
    NSString *name = t->_name;
    if ([name length])
        pthread_setname_np([name UTF8String]);
    @autoreleasepool {
        [t main];
    }
    thread_ending(t);
    return NULL;
}

- (void)start
{
    os_unfair_lock_lock(&_lock);
    BOOL again = _started;
    _started = YES;
    os_unfair_lock_unlock(&_lock);
    if (again)
        FRaise(NSInvalidArgumentException, @"*** -[NSThread start]: attempt to start the thread again");
    if (_cancelled) {
        __atomic_store_n(&_finished, YES, __ATOMIC_RELEASE);
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      [[NSNotificationCenter defaultCenter] postNotificationName:NSWillBecomeMultiThreadedNotification object:nil];
      multithreaded = YES;
    });
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (_stackSize) {
        size_t size = (_stackSize + 4095) & ~(size_t)4095;
        pthread_attr_setstacksize(&attr, size < 16384 ? 16384 : size);
    }
    __atomic_store_n(&_executing, YES, __ATOMIC_RELEASE);
    pthread_t pt;
    [self retain];
    int rc = pthread_create(&pt, &attr, thread_body, self);
    pthread_attr_destroy(&attr);
    if (rc) {
        __atomic_store_n(&_executing, NO, __ATOMIC_RELEASE);
        [self release];
        FRaise(NSInternalInconsistencyException, @"*** -[NSThread start]: Thread creation failed with error %d", rc);
    }
}

+ (void)detachNewThreadWithBlock:(void (^)(void))block
{
    NSThread *t = [[NSThread alloc] initWithBlock:block];
    [t start];
    [t release];
}
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument
{
    NSThread *t = [[NSThread alloc] initWithTarget:target selector:selector object:argument];
    [t start];
    [t release];
}

+ (void)sleepForTimeInterval:(NSTimeInterval)ti
{
    if (!(ti > 0))
        return;
    struct timespec ts = {(time_t)ti, (long)((ti - (time_t)ti) * 1e9)};
    while (nanosleep(&ts, &ts) == -1 && errno == EINTR)
        ;
}
+ (void)sleepUntilDate:(NSDate *)date { [self sleepForTimeInterval:[date timeIntervalSinceNow]]; }

+ (void)exit
{
    NSThread *t = [NSThread currentThread];
    if (t->_isMain) {
        /* a Mac ends the main thread and lets the others run on; Ferry ends the program */
        thread_ending(t);
        exit(0);
    }
    thread_ending(t);
    pthread_exit(NULL);
}

+ (double)threadPriority { return [[NSThread currentThread] threadPriority]; }
+ (BOOL)setThreadPriority:(double)p
{
    [[NSThread currentThread] setThreadPriority:p];
    return YES;
}
+ (NSArray *)callStackReturnAddresses { return [NSArray array]; }
+ (NSArray *)callStackSymbols { return [NSArray array]; }
@end

/* ---- performing selectors on other threads ------------------------------------------- */

struct perform_wait {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    BOOL done;
};

/* Runs the selector on thread's run loop; waits for it when asked to (on
 * the thread itself it runs at once instead, as on a Mac). */
static void perform_on(NSThread *thread, id target, SEL sel, id arg, BOOL wait)
{
    if (wait && thread == [NSThread currentThread]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
        return;
    }
    if ([thread isFinished])
        return; /* nothing will run it */
    NSRunLoop *loop = FRunLoopOfThread(thread, YES);
    [target retain];
    [arg retain];
    if (!wait) {
        [loop performBlock:^{
          ((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
          [target release];
          [arg release];
        }];
        return;
    }
    struct perform_wait *w = calloc(1, sizeof *w);
    pthread_mutex_init(&w->lock, NULL);
    pthread_cond_init(&w->cond, NULL);
    [loop performBlock:^{
      ((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
      [target release];
      [arg release];
      pthread_mutex_lock(&w->lock);
      w->done = YES;
      pthread_cond_signal(&w->cond);
      pthread_mutex_unlock(&w->lock);
    }];
    pthread_mutex_lock(&w->lock);
    while (!w->done)
        pthread_cond_wait(&w->cond, &w->lock);
    pthread_mutex_unlock(&w->lock);
    pthread_cond_destroy(&w->cond);
    pthread_mutex_destroy(&w->lock);
    free(w);
}

@implementation NSObject (NSThreadPerformAdditions)
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait
{
    perform_on([NSThread mainThread], self, aSelector, arg, wait);
}
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait
                              modes:(NSArray *)modes
{
    perform_on([NSThread mainThread], self, aSelector, arg, wait);
}
- (void)performSelector:(SEL)aSelector onThread:(NSThread *)thread withObject:(id)arg waitUntilDone:(BOOL)wait
{
    perform_on(thread, self, aSelector, arg, wait);
}
- (void)performSelector:(SEL)aSelector onThread:(NSThread *)thread withObject:(id)arg waitUntilDone:(BOOL)wait
                  modes:(NSArray *)modes
{
    perform_on(thread, self, aSelector, arg, wait);
}
- (void)performSelectorInBackground:(SEL)aSelector withObject:(id)arg
{
    [NSThread detachNewThreadSelector:aSelector toTarget:self withObject:arg];
}
@end
