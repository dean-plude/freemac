/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSRunLoop, NSTimer, NSPort, the delayed and
 * cross-thread performs, NSNotification and NSNotificationCenter.
 *
 * Each thread has a run loop of its own, made the first time the thread
 * asks for it (or another thread performs a selector on it), and run only
 * by that thread. A run loop waits with poll(), so file descriptors can be
 * added as input sources (AppKit adds its Wayland connection to the main
 * run loop that way), and on a pipe of its own that other threads write to
 * when they give it work (performBlock:, performSelector:onThread:...,
 * CFRunLoopWakeUp) so that it wakes at once. The main run loop also runs
 * the main dispatch queue's work, which wakes it the same way. A run loop
 * with nothing to wait for (no timer, port, descriptor or block) returns
 * at once from run, as on a Mac. Observers (CFRunLoopObserver, freemac
 * 1.230) are told as a run starts and ends, before each pass's timers and
 * sources and around its wait; they don't keep a loop running. */
#import "FInternal.h"
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <os/lock.h>
#include <poll.h>
#include <pthread.h>
#include <sys/time.h>
#include <unistd.h>

NSString *const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";
NSString *const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";

@interface NSTimer () {
@public
    NSTimeInterval _interval, _fire, _tolerance;
    id _target;
    SEL _sel;
    id _info;
    void (^_block)(NSTimer *);
    BOOL _repeats, _valid, _scheduled;
    NSRunLoop *_loop; /* not retained: the run loop it was added to */
}
@end

@interface NSRunLoop ()
- (void)_wakeUp;
@end

struct fsource {
    int fd;
    void (*callback)(int fd, void *ctx);
    void *ctx;
    short events;                                    /* POLLIN unless a handler asked otherwise */
    void (*handler)(int fd, short revents, void *ctx); /* the streams' and CFSocket's, given what is ready */
};

/* libSystem's dispatch queues (src/objc/dispatch.c): the main queue's work
 * runs on the main run loop. */
extern int ferry_dispatch_drain(void);
extern int ferry_dispatch_timeout_ms(void);
extern int ferry_dispatch_busy(void);
extern void ferry_dispatch_set_main_wakeup(void (*fn)(void));

/* ---- run loop observers --------------------------------------------------------------- */

@interface FRunLoopObserver : NSObject {
@public
    CFOptionFlags activities;
    BOOL repeats, valid;
    CFIndex order;
    CFRunLoopObserverCallBack callout;
    void (^block)(CFRunLoopObserverRef, CFRunLoopActivity);
    CFRunLoopObserverContext context;
    NSMutableArray *loops; /* the run loops it is in, not retained */
}
@end

@interface NSRunLoop (FObservers)
- (void)_removeObserver:(FRunLoopObserver *)o;
@end

@implementation FRunLoopObserver
- (void)invalidate
{
    NSArray *in;
    @synchronized(self) {
        if (!valid)
            return;
        valid = NO;
        in = [loops copy];
        [loops removeAllObjects];
    }
    for (NSValue *v in in)
        [(NSRunLoop *)[v nonretainedObjectValue] _removeObserver:self];
    [in release];
}
- (void)dealloc
{
    if (context.release && context.info)
        context.release(context.info);
    [block release];
    [loops release];
    [super dealloc];
}
@end

static FRunLoopObserver *new_observer(CFOptionFlags activities, Boolean repeats, CFIndex order)
{
    FRunLoopObserver *o = [[FRunLoopObserver alloc] init];
    o->activities = activities;
    o->repeats = repeats;
    o->order = order;
    o->valid = YES;
    o->loops = [[NSMutableArray alloc] init];
    return o;
}

#define OBS(x) ((FRunLoopObserver *)(x))

@implementation NSRunLoop {
    NSMutableArray *_observers;
    NSMutableArray *_timers;
    NSMutableArray *_blocks;
    NSMutableArray *_ports;
    struct fsource *_sources;
    int _nsources;
    BOOL _stopped, _main;
    NSString *_mode;
    os_unfair_lock _lock; /* other threads add blocks and timers, and stop it */
    int _wake[2];
    int _keepAlive; /* sources with nothing to poll for yet (CFRunLoopSource, a stream being opened) */
}

/* NSThread.m keeps each thread's run loop. */
NSRunLoop *FRunLoopOfThread(NSThread *thread, BOOL create);

static NSRunLoop *main_loop;

static void wake_main_loop(void) { [main_loop _wakeUp]; }

+ (NSRunLoop *)currentRunLoop { return FRunLoopOfThread([NSThread currentThread], YES); }
+ (NSRunLoop *)mainRunLoop { return FRunLoopOfThread([NSThread mainThread], YES); }

/* Made by NSThread.m, for the thread that will run it. */
- (instancetype)_initForMainThread:(BOOL)isMain
{
    _timers = [[NSMutableArray alloc] init];
    _blocks = [[NSMutableArray alloc] init];
    _ports = [[NSMutableArray alloc] init];
    _lock = OS_UNFAIR_LOCK_INIT;
    _main = isMain;
    if (pipe(_wake) == 0) {
        fcntl(_wake[0], F_SETFL, O_NONBLOCK);
        fcntl(_wake[1], F_SETFL, O_NONBLOCK);
        fcntl(_wake[0], F_SETFD, FD_CLOEXEC);
        fcntl(_wake[1], F_SETFD, FD_CLOEXEC);
    } else {
        _wake[0] = _wake[1] = -1;
    }
    if (isMain) {
        main_loop = self;
        ferry_dispatch_set_main_wakeup(wake_main_loop);
    }
    return self;
}
- (instancetype)init { return [self _initForMainThread:NO]; }
- (void)dealloc
{
    [_observers release];
    [_timers release];
    [_blocks release];
    [_ports release];
    free(_sources);
    if (_wake[0] >= 0) {
        close(_wake[0]);
        close(_wake[1]);
    }
    [super dealloc];
}
/* Wakes the loop from its wait, from any thread. */
- (void)_wakeUp
{
    if (_wake[1] >= 0) {
        char c = 1;
        (void)write(_wake[1], &c, 1);
    }
}
- (NSRunLoopMode)currentMode { return _mode; }

/* Observers, kept in their order; each is told on the thread that runs the loop. */
- (void)_addObserver:(FRunLoopObserver *)o
{
    @synchronized(o) {
        if (!o->valid)
            return;
    }
    os_unfair_lock_lock(&_lock);
    if (!_observers)
        _observers = [[NSMutableArray alloc] init];
    BOOL added = NO;
    if ([_observers indexOfObjectIdenticalTo:o] == NSNotFound) {
        NSUInteger i = 0, n = [_observers count];
        while (i < n && OBS([_observers objectAtIndex:i])->order <= o->order)
            i++;
        [_observers insertObject:o atIndex:i];
        added = YES;
    }
    os_unfair_lock_unlock(&_lock);
    if (added) {
        @synchronized(o) {
            [o->loops addObject:[NSValue valueWithNonretainedObject:self]];
        }
    }
}
- (void)_removeObserver:(FRunLoopObserver *)o
{
    os_unfair_lock_lock(&_lock);
    [o retain];
    [_observers removeObjectIdenticalTo:o];
    os_unfair_lock_unlock(&_lock);
    @synchronized(o) {
        for (NSUInteger i = [o->loops count]; i-- > 0;)
            if ([[o->loops objectAtIndex:i] nonretainedObjectValue] == self)
                [o->loops removeObjectAtIndex:i];
    }
    [o release];
}
- (BOOL)_containsObserver:(FRunLoopObserver *)o
{
    os_unfair_lock_lock(&_lock);
    BOOL in = [_observers indexOfObjectIdenticalTo:o] != NSNotFound;
    os_unfair_lock_unlock(&_lock);
    return in;
}
- (void)_tellObservers:(CFRunLoopActivity)activity
{
    if (!_observers)
        return;
    os_unfair_lock_lock(&_lock);
    NSArray *now = [_observers count] ? [_observers copy] : nil;
    os_unfair_lock_unlock(&_lock);
    for (FRunLoopObserver *o in now) {
        if (!(o->activities & activity) || !o->valid)
            continue;
        @autoreleasepool {
            if (o->block)
                o->block((CFRunLoopObserverRef)o, activity);
            else if (o->callout)
                o->callout((CFRunLoopObserverRef)o, activity, o->context.info);
        }
        if (!o->repeats)
            [o invalidate];
    }
    [now release];
}
- (CFRunLoopRef)getCFRunLoop { return (CFRunLoopRef)self; }
- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode
{
    os_unfair_lock_lock(&_lock);
    if (timer->_valid && [_timers indexOfObjectIdenticalTo:timer] == NSNotFound) {
        timer->_scheduled = YES;
        timer->_loop = self;
        [_timers addObject:timer];
    }
    os_unfair_lock_unlock(&_lock);
    [self _wakeUp];
}
- (void)removeTimer:(NSTimer *)timer
{
    os_unfair_lock_lock(&_lock);
    [_timers removeObjectIdenticalTo:timer];
    os_unfair_lock_unlock(&_lock);
}
- (void)performBlock:(void (^)(void))block
{
    id copy = [block copy];
    os_unfair_lock_lock(&_lock);
    [_blocks addObject:copy];
    os_unfair_lock_unlock(&_lock);
    [copy release];
    [self _wakeUp];
}
- (void)performInModes:(NSArray *)modes block:(void (^)(void))block { [self performBlock:block]; }
- (void)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay
{
    [self addTimer:[NSTimer timerWithTimeInterval:delay
                                          repeats:NO
                                            block:^(NSTimer *t) {
                                              block();
                                            }]
           forMode:NSDefaultRunLoopMode];
}
- (void)addPort:(NSPort *)port forMode:(NSRunLoopMode)mode
{
    os_unfair_lock_lock(&_lock);
    if (port && [_ports indexOfObjectIdenticalTo:port] == NSNotFound)
        [_ports addObject:port];
    os_unfair_lock_unlock(&_lock);
}
- (void)removePort:(NSPort *)port forMode:(NSRunLoopMode)mode
{
    os_unfair_lock_lock(&_lock);
    [_ports removeObjectIdenticalTo:port];
    os_unfair_lock_unlock(&_lock);
}
- (void)addDescriptor:(int)fd callback:(void (*)(int, void *))callback context:(void *)ctx
{
    os_unfair_lock_lock(&_lock);
    _sources = realloc(_sources, (_nsources + 1) * sizeof *_sources);
    _sources[_nsources++] = (struct fsource){fd, callback, ctx, POLLIN, NULL};
    os_unfair_lock_unlock(&_lock);
    [self _wakeUp];
}
/* A descriptor watched for events, given to handler with what is ready; the
 * same descriptor and context again changes the events (0 keeps it as a
 * source, watching nothing). */
- (void)_addDescriptor:(int)fd events:(short)events handler:(void (*)(int, short, void *))handler context:(void *)ctx
{
    os_unfair_lock_lock(&_lock);
    int i = 0;
    while (i < _nsources && !(_sources[i].fd == fd && _sources[i].ctx == ctx && _sources[i].handler))
        i++;
    if (i == _nsources) {
        _sources = realloc(_sources, (_nsources + 1) * sizeof *_sources);
        _nsources++;
    }
    _sources[i] = (struct fsource){fd, NULL, ctx, events, handler};
    os_unfair_lock_unlock(&_lock);
    [self _wakeUp];
}
- (void)_removeDescriptor:(int)fd context:(void *)ctx
{
    os_unfair_lock_lock(&_lock);
    for (int i = 0; i < _nsources; i++) {
        if (_sources[i].fd == fd && _sources[i].ctx == ctx && _sources[i].handler) {
            memmove(_sources + i, _sources + i + 1, (_nsources - i - 1) * sizeof *_sources);
            _nsources--;
            break;
        }
    }
    os_unfair_lock_unlock(&_lock);
}
- (BOOL)_stillWatching:(const struct fsource *)f
{
    BOOL found = NO;
    os_unfair_lock_lock(&_lock);
    for (int i = 0; i < _nsources && !found; i++)
        found = _sources[i].fd == f->fd && _sources[i].ctx == f->ctx && _sources[i].handler == f->handler &&
                (_sources[i].events & f->events);
    os_unfair_lock_unlock(&_lock);
    return found;
}
- (void)_addKeepAlive
{
    __atomic_add_fetch(&_keepAlive, 1, __ATOMIC_SEQ_CST);
    [self _wakeUp];
}
- (void)_removeKeepAlive { __atomic_sub_fetch(&_keepAlive, 1, __ATOMIC_SEQ_CST); }
- (void)removeDescriptor:(int)fd
{
    os_unfair_lock_lock(&_lock);
    for (int i = 0; i < _nsources; i++) {
        if (_sources[i].fd == fd && !_sources[i].handler) {
            memmove(_sources + i, _sources + i + 1, (_nsources - i - 1) * sizeof *_sources);
            _nsources--;
            break;
        }
    }
    os_unfair_lock_unlock(&_lock);
}
- (void)stop
{
    _stopped = YES;
    [self _wakeUp];
}
/* Another event loop waited on together with the main one (AppKit's GLib
 * main context): before each wait it adds its descriptors and may shorten
 * the wait; after it, it handles what is ready. */
static int (*hook_prepare)(void *ctx, int *timeout_ms, struct pollfd *fds, int max);
static BOOL (*hook_dispatch)(void *ctx, struct pollfd *fds, int count);
static void *hook_ctx;
#define HOOK_FDS 64

/* Foundation's own pollers, waited on by the main run loop with the rest
 * while active. */
struct fpoller {
    int (*prepare)(void *ctx, int *timeout_ms, struct pollfd *fds, int max);
    BOOL (*dispatch)(void *ctx, struct pollfd *fds, int count);
    BOOL (*active)(void *ctx);
    void *ctx;
};
#define MAX_POLLERS 4
static struct fpoller pollers[MAX_POLLERS];
static int npollers;

void FRunLoopAddPoller(int (*prepare)(void *, int *, struct pollfd *, int), BOOL (*dispatch)(void *, struct pollfd *, int),
                       BOOL (*active)(void *), void *ctx)
{
    if (npollers < MAX_POLLERS)
        pollers[npollers++] = (struct fpoller){prepare, dispatch, active, ctx};
}

static BOOL pollers_active(void)
{
    for (int i = 0; i < npollers; i++)
        if (pollers[i].active(pollers[i].ctx))
            return YES;
    return NO;
}

- (BOOL)hasWork
{
    os_unfair_lock_lock(&_lock);
    BOOL own = [_timers count] || [_blocks count] || [_ports count] || _nsources ||
               __atomic_load_n(&_keepAlive, __ATOMIC_SEQ_CST) > 0;
    os_unfair_lock_unlock(&_lock);
    if (own)
        return YES;
    /* the main run loop also runs the main queue, which work on other threads may still add to */
    return _main && (hook_prepare || ferry_dispatch_busy() || pollers_active());
}

static void drain_wake(int fd)
{
    char buf[64];
    while (read(fd, buf, sizeof buf) > 0)
        ;
}

/* One pass: run queued blocks, fire due timers, then wait for a descriptor
 * or the next timer, but not past limit. Returns NO when there is nothing that
 * could ever wake the loop. */
- (BOOL)runOnceBefore:(NSTimeInterval)limit handled:(BOOL *)handled
{
    *handled = NO;
    if (![self hasWork])
        return NO;
    [self _tellObservers:kCFRunLoopBeforeTimers];
    [self _tellObservers:kCFRunLoopBeforeSources];
    os_unfair_lock_lock(&_lock);
    NSArray *now = [_blocks count] ? [_blocks copy] : nil;
    [_blocks removeAllObjects];
    os_unfair_lock_unlock(&_lock);
    if (now) {
        for (void (^b)(void) in now) {
            @autoreleasepool {
                b();
            }
        }
        [now release];
        *handled = YES;
        return YES;
    }
    if (_main && ferry_dispatch_drain()) {
        *handled = YES;
        return YES;
    }
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    NSTimer *due = nil;
    NSTimeInterval next = limit;
    os_unfair_lock_lock(&_lock);
    for (NSTimer *timer in _timers) {
        if (timer->_fire <= t && (!due || timer->_fire < due->_fire))
            due = timer;
        if (timer->_fire < next)
            next = timer->_fire;
    }
    if (due) {
        [due retain];
        if (due->_repeats) {
            NSTimeInterval f = due->_fire + due->_interval;
            if (f <= t) /* skip the firings that were missed */
                f = t + due->_interval - fmod(t - due->_fire, due->_interval);
            due->_fire = f;
        } else {
            [_timers removeObjectIdenticalTo:due];
        }
    }
    os_unfair_lock_unlock(&_lock);
    if (due) {
        @autoreleasepool {
            [due fire];
        }
        if (!due->_repeats)
            [due invalidate];
        [due release];
        *handled = YES;
        return YES;
    }
    double wait = next - t;
    int ms = wait <= 0 ? 0 : wait > 2e6 ? 2000000000 : (int)ceil(wait * 1000);
    if (_main) {
        int dms = ferry_dispatch_timeout_ms();
        if (dms >= 0 && dms < ms)
            ms = dms;
        /* work on other threads may end without sending anything here: look again now and then */
        if (ms > 100 && ferry_dispatch_busy())
            ms = 100;
    }
    os_unfair_lock_lock(&_lock);
    int count = _nsources;
    struct fsource *snapshot = malloc((count ? count : 1) * sizeof *snapshot);
    memcpy(snapshot, _sources, count * sizeof *snapshot);
    os_unfair_lock_unlock(&_lock);
    struct pollfd *fds = calloc(1 + count + HOOK_FDS * (1 + MAX_POLLERS) + 1, sizeof *fds);
    fds[0].fd = _wake[0];
    fds[0].events = POLLIN;
    for (int i = 0; i < count; i++) {
        fds[1 + i].fd = snapshot[i].events ? snapshot[i].fd : -1; /* poll skips a negative one */
        fds[1 + i].events = snapshot[i].events;
    }
    int base = 1 + count, extra = 0;
    int pstart[MAX_POLLERS], pcount[MAX_POLLERS], np = _main ? npollers : 0;
    if (_main && hook_prepare)
        extra = hook_prepare(hook_ctx, &ms, fds + base, HOOK_FDS);
    int all = base + extra;
    for (int i = 0; i < np; i++) {
        pstart[i] = all;
        pcount[i] = -1;
        if (pollers[i].active(pollers[i].ctx)) {
            pcount[i] = pollers[i].prepare(pollers[i].ctx, &ms, fds + all, HOOK_FDS);
            all += pcount[i];
        }
    }
    if (ms > 0)
        [self _tellObservers:kCFRunLoopBeforeWaiting];
    int ready = poll(fds, all, ms);
    if (ms > 0)
        [self _tellObservers:kCFRunLoopAfterWaiting];
    if (ready > 0 && fds[0].revents)
        drain_wake(_wake[0]);
    if (_main && hook_dispatch && hook_dispatch(hook_ctx, fds + base, extra))
        *handled = YES;
    for (int i = 0; i < np; i++)
        if (pcount[i] >= 0 && pollers[i].dispatch(pollers[i].ctx, fds + pstart[i], pcount[i]))
            *handled = YES;
    if (ready > 0) {
        for (int i = 0; i < count; i++) {
            if (fds[1 + i].revents) {
                @autoreleasepool {
                    if (snapshot[i].handler) {
                        /* an earlier handler may have removed it (and freed its context) */
                        if ([self _stillWatching:&snapshot[i]])
                            snapshot[i].handler(snapshot[i].fd, fds[1 + i].revents, snapshot[i].ctx);
                    } else
                        snapshot[i].callback(snapshot[i].fd, snapshot[i].ctx);
                }
                *handled = YES;
            }
        }
    }
    free(snapshot);
    free(fds);
    return YES;
}
- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate
{
    NSTimeInterval limit = [limitDate timeIntervalSinceReferenceDate];
    NSString *saved = _mode;
    _mode = mode;
    BOOL handled = NO, alive = YES;
    /* a loop with nothing to run returns at once, telling no observer, as a
     * Mac's does: observers alone don't make a mode worth running */
    if (![self hasWork]) {
        _mode = saved;
        return NO;
    }
    [self _tellObservers:kCFRunLoopEntry];
    while (alive && !handled && !_stopped && [NSDate timeIntervalSinceReferenceDate] < limit)
        alive = [self runOnceBefore:limit handled:&handled];
    [self _tellObservers:kCFRunLoopExit];
    _mode = saved;
    return alive;
}
- (void)runUntilDate:(NSDate *)limit
{
    _stopped = NO;
    while (!_stopped && [limit timeIntervalSinceNow] > 0 && [self runMode:NSDefaultRunLoopMode beforeDate:limit])
        ;
    _stopped = NO;
}
- (void)run { [self runUntilDate:[NSDate distantFuture]]; }
- (void)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limit
{
    [self runMode:mode beforeDate:limit];
}
- (NSDate *)limitDateForMode:(NSRunLoopMode)mode
{
    if (![self hasWork])
        return nil;
    NSTimeInterval next = 1e15;
    os_unfair_lock_lock(&_lock);
    for (NSTimer *timer in _timers)
        if (timer->_fire < next)
            next = timer->_fire;
    os_unfair_lock_unlock(&_lock);
    return next < 1e15 ? [NSDate dateWithTimeIntervalSinceReferenceDate:next] : [NSDate distantFuture];
}

/* Set by CFRunLoopRun (CoreFoundation.m) while it runs (freemac 1.235, VLC). */
__thread BOOL _FerryRunLoopRunForever;

/* For CFRunLoopRunInMode. */
- (SInt32)runFor:(CFTimeInterval)seconds returnAfterSource:(BOOL)once
{
    NSTimeInterval limit = [NSDate timeIntervalSinceReferenceDate] + seconds;
    _stopped = NO;
    for (;;) {
        BOOL handled = NO;
        /* A Mac counts the main queue as a source of the main run loop, so
         * CFRunLoopRun there waits until CFRunLoopStop (VLC's main does). */
        if (![self hasWork] && !(_FerryRunLoopRunForever && _main && pthread_main_np()))
            return kCFRunLoopRunFinished;
        if (_stopped) {
            _stopped = NO;
            return kCFRunLoopRunStopped;
        }
        if ([NSDate timeIntervalSinceReferenceDate] >= limit)
            return kCFRunLoopRunTimedOut;
        [self runOnceBefore:limit handled:&handled];
        if (handled && once)
            return kCFRunLoopRunHandledSource;
    }
}
@end

/* ---- CFRunLoopObserver ------------------------------------------------------------------ */

CFTypeID CFRunLoopObserverGetTypeID(void) { return 0x46520003; }
CFRunLoopObserverRef CFRunLoopObserverCreate(CFAllocatorRef allocator, CFOptionFlags activities, Boolean repeats,
                                             CFIndex order, CFRunLoopObserverCallBack callout,
                                             CFRunLoopObserverContext *context)
{
    (void)allocator;
    FRunLoopObserver *o = new_observer(activities, repeats, order);
    o->callout = callout;
    if (context) {
        o->context = *context;
        if (context->retain && context->info)
            o->context.info = (void *)context->retain(context->info);
    }
    return (CFRunLoopObserverRef)o;
}
CFRunLoopObserverRef CFRunLoopObserverCreateWithHandler(CFAllocatorRef allocator, CFOptionFlags activities,
                                                        Boolean repeats, CFIndex order,
                                                        void (^block)(CFRunLoopObserverRef, CFRunLoopActivity))
{
    (void)allocator;
    FRunLoopObserver *o = new_observer(activities, repeats, order);
    o->block = [block copy];
    return (CFRunLoopObserverRef)o;
}
CFOptionFlags CFRunLoopObserverGetActivities(CFRunLoopObserverRef observer) { return OBS(observer)->activities; }
Boolean CFRunLoopObserverDoesRepeat(CFRunLoopObserverRef observer) { return OBS(observer)->repeats; }
CFIndex CFRunLoopObserverGetOrder(CFRunLoopObserverRef observer) { return OBS(observer)->order; }
void CFRunLoopObserverInvalidate(CFRunLoopObserverRef observer) { [OBS(observer) invalidate]; }
Boolean CFRunLoopObserverIsValid(CFRunLoopObserverRef observer)
{
    @synchronized(OBS(observer)) {
        return OBS(observer)->valid;
    }
}
void CFRunLoopObserverGetContext(CFRunLoopObserverRef observer, CFRunLoopObserverContext *context)
{
    if (context)
        *context = OBS(observer)->context;
}
void CFRunLoopAddObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode)
{
    (void)mode;
    if (rl && observer)
        [(NSRunLoop *)rl _addObserver:OBS(observer)];
}
void CFRunLoopRemoveObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode)
{
    (void)mode;
    if (rl && observer)
        [(NSRunLoop *)rl _removeObserver:OBS(observer)];
}
Boolean CFRunLoopContainsObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode)
{
    (void)mode;
    return rl && observer && [(NSRunLoop *)rl _containsObserver:OBS(observer)];
}

F_EXPORT void FerryRunLoopAddDescriptor(int fd, void (*callback)(int, void *), void *ctx)
{
    [[NSRunLoop mainRunLoop] addDescriptor:fd callback:callback context:ctx];
}

F_EXPORT void FerryRunLoopRemoveDescriptor(int fd) { [[NSRunLoop mainRunLoop] removeDescriptor:fd]; }

F_EXPORT void FerryRunLoopSetPollHook(int (*prepare)(void *, int *, struct pollfd *, int),
                                      BOOL (*dispatch)(void *, struct pollfd *, int), void *ctx)
{
    hook_prepare = prepare;
    hook_dispatch = dispatch;
    hook_ctx = ctx;
}

/* ---- CFRunLoopTimer ------------------------------------------------------------------ */

/* A CFRunLoopTimer is an NSTimer, as on a Mac (freemac 1.232, Ferry 0.56.0;
 * Qt's event dispatcher drives its timers with one). An interval of 0 fires
 * once. The context's info is retained for the timer's life. */
@interface FCFRunLoopTimer : NSTimer {
@public
    CFRunLoopTimerContext _context;
    CFIndex _order;
}
@end

@implementation FCFRunLoopTimer
- (void)dealloc
{
    if (_context.release && _context.info)
        _context.release(_context.info);
    [super dealloc];
}
@end

static FCFRunLoopTimer *new_cf_timer(CFAbsoluteTime fireDate, CFTimeInterval interval, CFIndex order)
{
    FCFRunLoopTimer *t = (FCFRunLoopTimer *)[[FCFRunLoopTimer timerWithTimeInterval:interval > 0 ? interval : 0
                                                           target:nil
                                                         selector:NULL
                                                         userInfo:nil
                                                          repeats:interval > 0] retain];
    t->_fire = fireDate;
    t->_order = order;
    return t;
}

CFTypeID CFRunLoopTimerGetTypeID(void) { return 0x46520004; }

CFRunLoopTimerRef CFRunLoopTimerCreate(CFAllocatorRef allocator, CFAbsoluteTime fireDate, CFTimeInterval interval,
                                       CFOptionFlags flags, CFIndex order, CFRunLoopTimerCallBack callout,
                                       CFRunLoopTimerContext *context)
{
    FCFRunLoopTimer *t = new_cf_timer(fireDate, interval, order);
    if (context) {
        t->_context = *context;
        if (context->retain && context->info)
            t->_context.info = (void *)context->retain(context->info);
    }
    void *info = t->_context.info;
    t->_block = [^(NSTimer *timer) {
      if (callout)
          callout((CFRunLoopTimerRef)timer, info);
    } copy];
    return (CFRunLoopTimerRef)t;
}

CFRunLoopTimerRef CFRunLoopTimerCreateWithHandler(CFAllocatorRef allocator, CFAbsoluteTime fireDate,
                                                  CFTimeInterval interval, CFOptionFlags flags, CFIndex order,
                                                  void (^block)(CFRunLoopTimerRef timer))
{
    FCFRunLoopTimer *t = new_cf_timer(fireDate, interval, order);
    void (^b)(CFRunLoopTimerRef) = [block copy];
    t->_block = [^(NSTimer *timer) {
      b((CFRunLoopTimerRef)timer);
    } copy];
    [b release];
    return (CFRunLoopTimerRef)t;
}

#define TIMER(t) ((NSTimer *)(t))
void CFRunLoopAddTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFRunLoopMode mode)
{
    [(NSRunLoop *)rl addTimer:TIMER(timer) forMode:(NSString *)mode];
}
void CFRunLoopRemoveTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFRunLoopMode mode)
{
    [(NSRunLoop *)rl removeTimer:TIMER(timer)];
    TIMER(timer)->_scheduled = NO;
}
Boolean CFRunLoopContainsTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFRunLoopMode mode)
{
    return TIMER(timer)->_valid && TIMER(timer)->_scheduled && TIMER(timer)->_loop == (NSRunLoop *)rl;
}
void CFRunLoopTimerInvalidate(CFRunLoopTimerRef timer) { [TIMER(timer) invalidate]; }
Boolean CFRunLoopTimerIsValid(CFRunLoopTimerRef timer) { return TIMER(timer)->_valid; }
CFAbsoluteTime CFRunLoopTimerGetNextFireDate(CFRunLoopTimerRef timer) { return TIMER(timer)->_fire; }
void CFRunLoopTimerSetNextFireDate(CFRunLoopTimerRef timer, CFAbsoluteTime fireDate)
{
    TIMER(timer)->_fire = fireDate;
    [TIMER(timer)->_loop _wakeUp];
}
CFTimeInterval CFRunLoopTimerGetInterval(CFRunLoopTimerRef timer) { return [TIMER(timer) timeInterval]; }
Boolean CFRunLoopTimerDoesRepeat(CFRunLoopTimerRef timer) { return TIMER(timer)->_repeats; }
CFIndex CFRunLoopTimerGetOrder(CFRunLoopTimerRef timer)
{
    return [TIMER(timer) isKindOfClass:[FCFRunLoopTimer class]] ? ((FCFRunLoopTimer *)(id)timer)->_order : 0;
}
void CFRunLoopTimerGetContext(CFRunLoopTimerRef timer, CFRunLoopTimerContext *context)
{
    if (!context)
        return;
    if ([TIMER(timer) isKindOfClass:[FCFRunLoopTimer class]])
        *context = ((FCFRunLoopTimer *)(id)timer)->_context;
    else
        memset(context, 0, sizeof *context);
}
CFTimeInterval CFRunLoopTimerGetTolerance(CFRunLoopTimerRef timer) { return TIMER(timer)->_tolerance; }
void CFRunLoopTimerSetTolerance(CFRunLoopTimerRef timer, CFTimeInterval tolerance)
{
    TIMER(timer)->_tolerance = tolerance;
}
/* Ferry's run loops don't tell modes apart, so every mode is already common. */
void CFRunLoopAddCommonMode(CFRunLoopRef rl, CFRunLoopMode mode) {}
#undef TIMER

/* ---- NSPort ------------------------------------------------------------------------- */

@implementation NSPort {
    BOOL _invalid;
}
+ (NSPort *)port { return [[[NSMachPort alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (void)invalidate { _invalid = YES; }
- (BOOL)isValid { return !_invalid; }
@end

@implementation NSMachPort
@end

/* ---- NSTimer ------------------------------------------------------------------------- */

@implementation NSTimer
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel userInfo:(id)info
                           repeats:(BOOL)repeats
{
    NSTimer *t = [[[self alloc] init] autorelease];
    t->_interval = ti > 0 ? ti : 0.0001;
    t->_fire = [NSDate timeIntervalSinceReferenceDate] + (ti > 0 ? ti : 0);
    t->_target = [target retain];
    t->_sel = sel;
    t->_info = [info retain];
    t->_repeats = repeats;
    t->_valid = YES;
    return t;
}
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel userInfo:(id)info
                                    repeats:(BOOL)repeats
{
    NSTimer *t = [self timerWithTimeInterval:ti target:target selector:sel userInfo:info repeats:repeats];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
    return t;
}
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti repeats:(BOOL)repeats block:(void (^)(NSTimer *))block
{
    NSTimer *t = [self timerWithTimeInterval:ti target:nil selector:NULL userInfo:nil repeats:repeats];
    t->_block = [block copy];
    return t;
}
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti repeats:(BOOL)repeats block:(void (^)(NSTimer *))block
{
    NSTimer *t = [self timerWithTimeInterval:ti repeats:repeats block:block];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
    return t;
}
- (instancetype)initWithFireDate:(NSDate *)date interval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel
                        userInfo:(id)info repeats:(BOOL)repeats
{
    [self release];
    NSTimer *t = [[NSTimer timerWithTimeInterval:ti target:target selector:sel userInfo:info repeats:repeats] retain];
    t->_fire = [date timeIntervalSinceReferenceDate];
    return t;
}
- (void)dealloc
{
    [_target release];
    [_info release];
    [_block release];
    [super dealloc];
}
- (void)fire
{
    if (!_valid)
        return;
    if (_block)
        _block(self);
    else if (_target)
        ((void (*)(id, SEL, id))objc_msgSend)(_target, _sel, self);
}
- (void)invalidate
{
    if (!_valid)
        return;
    _valid = NO;
    [self retain];
    if (_scheduled)
        [_loop ?: [NSRunLoop mainRunLoop] removeTimer:self];
    [_target release];
    _target = nil;
    [_info release];
    _info = nil;
    [_block release];
    _block = nil;
    [self release];
}
- (BOOL)isValid { return _valid; }
- (NSTimeInterval)timeInterval { return _repeats ? _interval : 0; }
- (NSDate *)fireDate { return [NSDate dateWithTimeIntervalSinceReferenceDate:_fire]; }
- (void)setFireDate:(NSDate *)date
{
    _fire = [date timeIntervalSinceReferenceDate];
    [_loop _wakeUp];
}
- (id)userInfo { return _info; }
- (NSTimeInterval)tolerance { return _tolerance; }
- (void)setTolerance:(NSTimeInterval)t { _tolerance = t; }
@end

/* ---- delayed performs ---------------------------------------------------------------- */

/* Each delayed perform waiting to happen, so that
 * cancelPreviousPerformRequestsWithTarget: can find it. A delayed perform
 * runs on the run loop of the thread that asked for it. */
@interface FDelayedPerform : NSObject {
@public
    id target, arg;
    SEL sel;
    NSTimer *timer;
}
@end
@implementation FDelayedPerform
@end
static NSMutableArray *delayed_performs;
static os_unfair_lock delayed_lock = OS_UNFAIR_LOCK_INIT;

@implementation NSObject (NSDelayedPerforming)
- (void)performSelector:(SEL)aSelector withObject:(id)arg afterDelay:(NSTimeInterval)delay
{
    FDelayedPerform *p = [[FDelayedPerform alloc] init];
    p->target = [self retain];
    p->arg = [arg retain];
    p->sel = aSelector;
    p->timer = [NSTimer timerWithTimeInterval:delay
                                      repeats:NO
                                        block:^(NSTimer *t) {
                                          os_unfair_lock_lock(&delayed_lock);
                                          [p retain];
                                          [delayed_performs removeObjectIdenticalTo:p];
                                          os_unfair_lock_unlock(&delayed_lock);
                                          ((void (*)(id, SEL, id))objc_msgSend)(p->target, p->sel, p->arg);
                                          [p->target release];
                                          [p->arg release];
                                          p->target = p->arg = nil;
                                          [p release];
                                        }];
    os_unfair_lock_lock(&delayed_lock);
    if (!delayed_performs)
        delayed_performs = [[NSMutableArray alloc] init];
    [delayed_performs addObject:p];
    os_unfair_lock_unlock(&delayed_lock);
    [p release];
    [[NSRunLoop currentRunLoop] addTimer:p->timer forMode:NSDefaultRunLoopMode];
}
static void cancel_performs(id target, BOOL any, SEL sel, id arg)
{
    NSMutableArray *gone = [NSMutableArray array];
    os_unfair_lock_lock(&delayed_lock);
    for (FDelayedPerform *p in delayed_performs)
        if (p->target == target && (any || (p->sel == sel && (p->arg == arg || [p->arg isEqual:arg]))))
            [gone addObject:p];
    for (FDelayedPerform *p in gone)
        [delayed_performs removeObjectIdenticalTo:p];
    os_unfair_lock_unlock(&delayed_lock);
    for (FDelayedPerform *p in gone) {
        [p->timer invalidate];
        [p->target release];
        [p->arg release];
        p->target = p->arg = nil;
    }
}
+ (void)cancelPreviousPerformRequestsWithTarget:(id)target
{
    cancel_performs(target, YES, NULL, nil);
}
+ (void)cancelPreviousPerformRequestsWithTarget:(id)target selector:(SEL)sel object:(id)arg
{
    cancel_performs(target, NO, sel, arg);
}
- (void)performSelector:(SEL)aSelector withObject:(id)arg afterDelay:(NSTimeInterval)delay
                inModes:(NSArray *)modes
{
    [self performSelector:aSelector withObject:arg afterDelay:delay];
}
@end

/* ---- notifications ------------------------------------------------------------------- */

@implementation NSNotification {
    NSString *_name;
    id _object;
    NSDictionary *_userInfo;
}
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object
{
    return [self notificationWithName:name object:object userInfo:nil];
}
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)info
{
    return [[[self alloc] initWithName:name object:object userInfo:info] autorelease];
}
- (instancetype)initWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)info
{
    if ((self = [super init])) {
        _name = [name copy];
        _object = [object retain];
        _userInfo = [info copy];
    }
    return self;
}
- (void)dealloc
{
    [_name release];
    [_object release];
    [_userInfo release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSNotificationName)name { return _name; }
- (id)object { return _object; }
- (NSDictionary *)userInfo { return _userInfo; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"NSConcreteNotification %p {name = %@%@}", self, _name,
                                      _object ? [NSString stringWithFormat:@"; object = %@", _object] : @""];
}
@end

@interface FObservation : NSObject {
@public
    id _observer; /* not retained, as on a Mac */
    SEL _sel;
    NSString *_name;
    id _object; /* not retained */
    void (^_block)(NSNotification *);
    BOOL _removed;
}
@end

@implementation FObservation
- (void)dealloc
{
    [_name release];
    [_block release];
    [super dealloc];
}
@end

/* Observers may be added, removed and notified from any thread; a
 * notification is delivered on the thread that posts it. */
@implementation NSNotificationCenter {
    NSMutableArray *_observations;
    os_unfair_lock _lock;
}
+ (NSNotificationCenter *)defaultCenter
{
    static NSNotificationCenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      shared = [[NSNotificationCenter alloc] init];
    });
    return shared;
}
- (instancetype)init
{
    _observations = [[NSMutableArray alloc] init];
    _lock = OS_UNFAIR_LOCK_INIT;
    return self;
}
- (void)addObserver:(id)observer selector:(SEL)sel name:(NSNotificationName)name object:(id)object
{
    FObservation *o = [[FObservation alloc] init];
    o->_observer = observer;
    o->_sel = sel;
    o->_name = [name copy];
    o->_object = object;
    os_unfair_lock_lock(&_lock);
    [_observations addObject:o];
    os_unfair_lock_unlock(&_lock);
    [o release];
}
- (id)addObserverForName:(NSNotificationName)name object:(id)obj queue:(NSOperationQueue *)queue
              usingBlock:(void (^)(NSNotification *))block
{
    FObservation *o = [[FObservation alloc] init];
    o->_observer = o;
    o->_name = [name copy];
    o->_object = obj;
    o->_block = [block copy];
    os_unfair_lock_lock(&_lock);
    [_observations addObject:o];
    os_unfair_lock_unlock(&_lock);
    return [o autorelease];
}
- (void)postNotification:(NSNotification *)note
{
    os_unfair_lock_lock(&_lock);
    NSArray *now = [_observations copy];
    os_unfair_lock_unlock(&_lock);
    NSString *name = [note name];
    id object = [note object];
    for (FObservation *o in now) {
        if (o->_removed)
            continue;
        if (o->_name && ![o->_name isEqualToString:name])
            continue;
        if (o->_object && o->_object != object)
            continue;
        if (o->_block)
            o->_block(note);
        else
            ((void (*)(id, SEL, id))objc_msgSend)(o->_observer, o->_sel, note);
    }
    [now release];
}
/* As on a Mac, the notification is let go of once it has been posted, not
 * left to an autorelease pool: a thread whose pool isn't drained for a long
 * time (OBS loads its scenes in one) would otherwise keep the object the
 * notification is about, like a capture session that should stop when its
 * app lets go of it (freemac 1.259) */
- (void)postNotificationName:(NSNotificationName)name object:(id)object
{
    [self postNotificationName:name object:object userInfo:nil];
}
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)info
{
    NSNotification *note = [[NSNotification alloc] initWithName:name object:object userInfo:info];
    [self postNotification:note];
    [note release];
}
- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(id)object
{
    NSMutableArray *gone = [[NSMutableArray alloc] init];
    os_unfair_lock_lock(&_lock);
    for (NSUInteger i = [_observations count]; i-- > 0;) {
        FObservation *o = [_observations objectAtIndex:i];
        if (o->_observer != observer)
            continue;
        if (name && ![o->_name isEqualToString:name])
            continue;
        if (object && o->_object != object)
            continue;
        o->_removed = YES;
        [gone addObject:o];
        [_observations removeObjectAtIndex:i];
    }
    os_unfair_lock_unlock(&_lock);
    [gone release]; /* outside the lock: an observer's block may hold the last reference to anything */
}
- (void)removeObserver:(id)observer { [self removeObserver:observer name:nil object:nil]; }
@end

/* ---- messages for the next turn (freemac 1.221, Ferry 0.45.0) -------------------------- */

@interface FOrderedPerform : NSObject {
@public
    SEL sel;
    id target, argument;
    NSUInteger order;
}
@end
@implementation FOrderedPerform
- (void)dealloc
{
    [target release];
    [argument release];
    [super dealloc];
}
@end

static char pending_key;

@implementation NSRunLoop (FerryOrderedPerform)
- (NSMutableArray *)_ferryPending
{
    @synchronized(self) {
        NSMutableArray *a = objc_getAssociatedObject(self, &pending_key);
        if (!a) {
            a = [NSMutableArray array];
            objc_setAssociatedObject(self, &pending_key, a, OBJC_ASSOCIATION_RETAIN);
        }
        return a;
    }
}
- (void)performSelector:(SEL)aSelector target:(id)target argument:(id)arg order:(NSUInteger)order
                  modes:(NSArray *)modes
{
    FOrderedPerform *p = [[FOrderedPerform alloc] init];
    p->sel = aSelector;
    p->target = [target retain];
    p->argument = [arg retain];
    p->order = order;
    NSMutableArray *pending = [self _ferryPending];
    BOOL first;
    @synchronized(pending) {
        first = [pending count] == 0;
        NSUInteger i = [pending count];
        while (i > 0 && ((FOrderedPerform *)[pending objectAtIndex:i - 1])->order > order)
            i--;
        [pending insertObject:p atIndex:i];
    }
    [p release];
    if (!first)
        return;
    [self performBlock:^{
      NSArray *now;
      @synchronized(pending) {
          now = [[pending copy] autorelease];
          [pending removeAllObjects];
      }
      for (FOrderedPerform *q in now)
          ((void (*)(id, SEL, id))objc_msgSend)(q->target, q->sel, q->argument);
    }];
}
- (void)cancelPerformSelector:(SEL)aSelector target:(id)target argument:(id)arg
{
    NSMutableArray *pending = [self _ferryPending];
    @synchronized(pending) {
        for (NSUInteger i = [pending count]; i > 0; i--) {
            FOrderedPerform *q = [pending objectAtIndex:i - 1];
            if (q->target == target && q->sel == aSelector && (q->argument == arg || [q->argument isEqual:arg]))
                [pending removeObjectAtIndex:i - 1];
        }
    }
}
- (void)cancelPerformSelectorsWithTarget:(id)target
{
    NSMutableArray *pending = [self _ferryPending];
    @synchronized(pending) {
        for (NSUInteger i = [pending count]; i > 0; i--)
            if (((FOrderedPerform *)[pending objectAtIndex:i - 1])->target == target)
                [pending removeObjectAtIndex:i - 1];
    }
}
@end
