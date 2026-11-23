/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSRunLoop, NSTimer, NSNotification and
 * NSNotificationCenter. There is one run loop, on the main thread (Ferry
 * doesn't run Mac threads yet). It waits with poll(), so file descriptors
 * can be added as input sources; AppKit (M4) adds its Wayland connection that
 * way. */
#import "FInternal.h"
#include <os/lock.h>
#include <poll.h>
#include <sys/time.h>

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
}
@end

struct fsource {
    int fd;
    void (*callback)(int fd, void *ctx);
    void *ctx;
};

@implementation NSRunLoop {
    NSMutableArray *_timers;
    NSMutableArray *_blocks;
    struct fsource *_sources;
    int _nsources;
    BOOL _stopped;
    NSString *_mode;
}

static NSRunLoop *main_loop;

+ (NSRunLoop *)currentRunLoop { return [self mainRunLoop]; }
+ (NSRunLoop *)mainRunLoop
{
    if (!main_loop)
        main_loop = [[NSRunLoop alloc] init];
    return main_loop;
}
- (instancetype)init
{
    _timers = [[NSMutableArray alloc] init];
    _blocks = [[NSMutableArray alloc] init];
    return self;
}
- (NSRunLoopMode)currentMode { return _mode; }
- (CFRunLoopRef)getCFRunLoop { return (CFRunLoopRef)self; }
- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode
{
    if (!timer->_valid || [_timers indexOfObjectIdenticalTo:timer] != NSNotFound)
        return;
    timer->_scheduled = YES;
    [_timers addObject:timer];
}
- (void)removeTimer:(NSTimer *)timer { [_timers removeObjectIdenticalTo:timer]; }
- (void)performBlock:(void (^)(void))block
{
    id copy = [block copy];
    [_blocks addObject:copy];
    [copy release];
}
- (void)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay
{
    [self addTimer:[NSTimer timerWithTimeInterval:delay
                                          repeats:NO
                                            block:^(NSTimer *t) {
                                              block();
                                            }]
           forMode:NSDefaultRunLoopMode];
}
- (void)addDescriptor:(int)fd callback:(void (*)(int, void *))callback context:(void *)ctx
{
    _sources = realloc(_sources, (_nsources + 1) * sizeof *_sources);
    _sources[_nsources++] = (struct fsource){fd, callback, ctx};
}
- (void)removeDescriptor:(int)fd
{
    for (int i = 0; i < _nsources; i++) {
        if (_sources[i].fd == fd) {
            memmove(_sources + i, _sources + i + 1, (_nsources - i - 1) * sizeof *_sources);
            _nsources--;
            return;
        }
    }
}
- (void)stop { _stopped = YES; }
/* Another event loop waited on together with this one (AppKit's GLib main
 * context): before each wait it adds its descriptors and may shorten the
 * wait; after it, it handles what is ready. */
static int (*hook_prepare)(void *ctx, int *timeout_ms, struct pollfd *fds, int max);
static BOOL (*hook_dispatch)(void *ctx, struct pollfd *fds, int count);
static void *hook_ctx;
#define HOOK_FDS 64

/* libSystem's dispatch queues (src/objc/dispatch.c) run on this loop. */
extern int ferry_dispatch_drain(void);
extern int ferry_dispatch_timeout_ms(void);

- (BOOL)hasWork
{
    return [_timers count] || [_blocks count] || _nsources || hook_prepare || ferry_dispatch_timeout_ms() >= 0;
}

/* One pass: run queued blocks, fire due timers, then wait for a descriptor
 * or the next timer, but not past limit. Returns NO when there is nothing that
 * could ever wake the loop. */
- (BOOL)runOnceBefore:(NSTimeInterval)limit handled:(BOOL *)handled
{
    *handled = NO;
    if (![self hasWork])
        return NO;
    if ([_blocks count]) {
        NSArray *now = [_blocks copy];
        [_blocks removeAllObjects];
        for (void (^b)(void) in now) {
            @autoreleasepool {
                b();
            }
        }
        [now release];
        *handled = YES;
        return YES;
    }
    if (ferry_dispatch_drain()) {
        *handled = YES;
        return YES;
    }
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    NSTimer *due = nil;
    NSTimeInterval next = limit;
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
    int dms = ferry_dispatch_timeout_ms();
    if (dms >= 0 && dms < ms)
        ms = dms;
    struct pollfd *fds = calloc(_nsources + HOOK_FDS + 1, sizeof *fds);
    for (int i = 0; i < _nsources; i++) {
        fds[i].fd = _sources[i].fd;
        fds[i].events = POLLIN;
    }
    int count = _nsources, extra = 0;
    if (hook_prepare)
        extra = hook_prepare(hook_ctx, &ms, fds + count, HOOK_FDS);
    struct fsource *snapshot = malloc((count ? count : 1) * sizeof *snapshot);
    memcpy(snapshot, _sources, count * sizeof *snapshot);
    int ready = poll(fds, count + extra, ms);
    if (hook_dispatch && hook_dispatch(hook_ctx, fds + count, extra))
        *handled = YES;
    if (ready > 0) {
        for (int i = 0; i < count; i++) {
            if (fds[i].revents) {
                @autoreleasepool {
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
    while (alive && !handled && !_stopped && [NSDate timeIntervalSinceReferenceDate] < limit)
        alive = [self runOnceBefore:limit handled:&handled];
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

/* For CFRunLoopRunInMode. */
- (SInt32)runFor:(CFTimeInterval)seconds returnAfterSource:(BOOL)once
{
    NSTimeInterval limit = [NSDate timeIntervalSinceReferenceDate] + seconds;
    _stopped = NO;
    for (;;) {
        BOOL handled = NO;
        if (![self hasWork])
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
        [[NSRunLoop mainRunLoop] removeTimer:self];
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
- (void)setFireDate:(NSDate *)date { _fire = [date timeIntervalSinceReferenceDate]; }
- (id)userInfo { return _info; }
- (NSTimeInterval)tolerance { return _tolerance; }
- (void)setTolerance:(NSTimeInterval)t { _tolerance = t; }
@end

/* ---- delayed and main-thread performs ------------------------------------------------- */

/* Each delayed perform waiting to happen, so that
 * cancelPreviousPerformRequestsWithTarget: can find it. */
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
    [[NSRunLoop mainRunLoop] addTimer:p->timer forMode:NSDefaultRunLoopMode];
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
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait
{
    if (wait) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, aSelector, arg);
        return;
    }
    [self retain];
    [arg retain];
    [[NSRunLoop mainRunLoop] performBlock:^{
      ((void (*)(id, SEL, id))objc_msgSend)(self, aSelector, arg);
      [self release];
      [arg release];
    }];
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
    NSNotification *n = [[[self alloc] init] autorelease];
    n->_name = [name copy];
    n->_object = [object retain];
    n->_userInfo = [info copy];
    return n;
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

@implementation NSNotificationCenter {
    NSMutableArray *_observations;
}
+ (NSNotificationCenter *)defaultCenter
{
    static NSNotificationCenter *shared;
    if (!shared)
        shared = [[NSNotificationCenter alloc] init];
    return shared;
}
- (instancetype)init
{
    _observations = [[NSMutableArray alloc] init];
    return self;
}
- (void)addObserver:(id)observer selector:(SEL)sel name:(NSNotificationName)name object:(id)object
{
    FObservation *o = [[FObservation alloc] init];
    o->_observer = observer;
    o->_sel = sel;
    o->_name = [name copy];
    o->_object = object;
    [_observations addObject:o];
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
    [_observations addObject:o];
    return [o autorelease];
}
- (void)postNotification:(NSNotification *)note
{
    NSArray *now = [_observations copy];
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
- (void)postNotificationName:(NSNotificationName)name object:(id)object
{
    [self postNotification:[NSNotification notificationWithName:name object:object]];
}
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)info
{
    [self postNotification:[NSNotification notificationWithName:name object:object userInfo:info]];
}
- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(id)object
{
    for (NSUInteger i = [_observations count]; i-- > 0;) {
        FObservation *o = [_observations objectAtIndex:i];
        if (o->_observer != observer)
            continue;
        if (name && ![o->_name isEqualToString:name])
            continue;
        if (object && o->_object != object)
            continue;
        o->_removed = YES;
        [_observations removeObjectAtIndex:i];
    }
}
- (void)removeObserver:(id)observer { [self removeObserver:observer name:nil object:nil]; }
@end
