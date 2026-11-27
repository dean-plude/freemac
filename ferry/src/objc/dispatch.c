/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Grand Central Dispatch (libdispatch), the part of libSystem that Mac
 * programs use to run blocks later or elsewhere: queues, dispatch_async and
 * dispatch_sync, dispatch_once, dispatch_after, dispatch_apply, groups,
 * semaphores and timer, data, read, write, signal and process sources.
 *
 * Work runs on real threads, as on a Mac. The global queues are concurrent:
 * their blocks run on a pool of worker threads that grows when every
 * worker is busy (or stuck waiting) and work is waiting, and shrinks again
 * when workers have been idle a while. A serial queue runs one block at a
 * time, in the order they were queued, on whichever worker is free; a
 * concurrent queue of the program's own runs its blocks together, except
 * that a barrier block waits for the blocks before it and runs alone.
 * Queues that target other queues share their target's ordering. The main
 * queue (and anything that targets it) runs only on the main thread:
 * Foundation's run loop asks for its work on each pass (and dispatch_main
 * runs it for ever), and is woken when some arrives.
 *
 * dispatch_sync runs its block on the calling thread once the queue is
 * free, as on a Mac; on the main queue, from another thread, the main
 * thread runs it. A dispatch_sync that could never return (onto the queue
 * whose block is calling it, or onto the main queue from the main thread)
 * stops the program with a message instead of hanging. A wait on the main
 * thread for something nothing could ever do (no other thread running, no
 * work queued or due) also stops with a message rather than hang.
 *
 * Dispatch objects are Objective-C objects, as on a Mac, so that code built
 * with ARC can retain and release them. Written from Apple's public
 * documentation of libdispatch's calls; no Apple code was used.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "../ferry.h"
#include "objc-private.h"

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *token);

#define M(sel, types, fn) {sel, types, (IMP)(void (*)(void))(fn)}

struct block_header {
    Class isa;
    int32_t flags, reserved;
    void (*invoke)(void *, ...);
};
void *_Block_copy(const void *);
void _Block_release(const void *);

enum kind { K_QUEUE, K_GROUP, K_SEMAPHORE, K_SOURCE };

struct dobj {
    Class isa;
    enum kind kind;
    void *context;
    void (*finalizer)(void *);
    /* queues */
    char label[64];
    int suspended;
    int concurrent, inactive, global;
    struct specific *specifics;
    struct dobj *target;
    /* a queue that orders work itself (see domain_of): what waits, what runs */
    struct work *head, *tail;
    int running, barrier, listed;
    struct dobj *next_listed;
    /* groups */
    long pending;
    struct work *notify;
    /* semaphores */
    long value, wakeups;
    /* sources */
    int source_type;
    uint64_t start, interval;
    void *handler, *cancel_handler; /* blocks */
    void (*handler_f)(void *), (*cancel_f)(void *); /* or functions, called with the context */
    int cancelled, armed;
    unsigned long data, fired_data;
    /* read, write, signal and process sources: what they watch, and their
     * registration with the kqueue that the sources thread waits on */
    uintptr_t handle;
    unsigned long mask;
    uint64_t kid;
    int kregistered, kpending, kdone;
    int mach_fd; /* a mach_send source: readable once the port is dead */
    struct dobj *next_k;
};

struct specific {
    const void *key;
    void *value;
    struct specific *next;
};

/* a dispatch_sync waiting for its turn */
struct syncwait {
    int granted, done;
};

struct work {
    struct dobj *queue;      /* where it was sent (retained) */
    void *block;             /* a copied block, or NULL */
    void (*fn)(void *);
    void *ctx;
    struct dobj *group;      /* left when the work is done */
    uint64_t when;           /* for dispatch_after */
    int barrier;
    struct syncwait *sync;
    struct work *next;
};

/* The classes, by the names a Mac gives them, since a Swift app compiled
 * on a Mac names them (DispatchQueue is OS_dispatch_queue there, freemac
 * 1.260): OS_dispatch_object, and under it a class for each kind of object
 * made at run time; and the main and global queues', kinds of
 * OS_dispatch_queue which live as long as the program and ignore retain
 * and release. */
static struct fobjc_class static_class, static_meta;
/* an app's references to these classes find them by name (the table at the end) */
static struct fobjc_class dispatch_class, dispatch_meta;
static struct fobjc_class kind_class[4], kind_meta[4];
static struct fobjc_class global_class, global_meta;

/* one of the objects made at run time, which are retained and released */
static int counted(const struct dobj *o)
{
    for (int i = 0; i < 4; i++)
        if (o->isa == (Class)&kind_class[i])
            return 1;
    return 0;
}

/* The main queue's symbol is a variable (dispatch_get_main_queue() is a macro
 * for its address); the global queues are returned by a call. */
struct dobj ferry_dispatch_main_q;
static struct dobj global_queues[4];
#define MAIN_Q (&ferry_dispatch_main_q)
#define DEFAULT_Q (&global_queues[1])

/* Everything here is guarded by one lock. Workers sleep on work_cond; the
 * manager thread (timers, and adding workers) on manager_cond; anyone
 * waiting for something to happen (a dispatch_sync's turn, a group, a
 * semaphore, a dispatch_once, the main queue's work) on event_cond. */
static pthread_mutex_t dq = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t work_cond, manager_cond, event_cond;
static struct dobj *listed_head, *listed_tail;  /* worker queues with work waiting */
static struct work *later;                       /* dispatch_after's, soonest first */
static int workers, idle_workers, busy_workers, manager_started;
static unsigned long progress;                   /* work started so far, to see when the pool is stuck */
static int soft_max_workers, hard_max_workers = 64;
static pthread_t main_thread;
static void (*main_wakeup)(void);

static __thread struct dobj *current_queue;
/* the queues whose turn this thread holds (running one of their blocks) */
struct held {
    struct dobj *domain;
    struct held *prev;
};
static __thread struct held *held_top;

static uint64_t now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void stop(const char *why)
{
    fflush(stdout);
    fprintf(stderr, "ferry: %s\n", why);
    _exit(70);
}

static int on_main_thread(void) { return pthread_equal(pthread_self(), main_thread); }

/* a wait on one of the conditions until a point on the monotonic clock */
static int wait_until(pthread_cond_t *c, uint64_t deadline)
{
    if (deadline == ~0ull)
        return pthread_cond_wait(c, &dq);
    struct timespec ts = {(time_t)(deadline / 1000000000ull), (long)(deadline % 1000000000ull)};
    return pthread_cond_timedwait(c, &dq, &ts);
}

/* ---- objects ------------------------------------------------------------------ */

static struct dobj *new_object(enum kind kind)
{
    struct dobj *o = (struct dobj *)class_createInstance((Class)&kind_class[kind], 0);
    o->kind = kind;
    return o;
}

static void d_dealloc(struct dobj *self, SEL _cmd)
{
    (void)_cmd;
    if (self->finalizer)
        self->finalizer(self->context);
    if (self->handler)
        _Block_release(self->handler);
    if (self->cancel_handler)
        _Block_release(self->cancel_handler);
    for (struct specific *s = self->specifics, *n; s; s = n) {
        n = s->next;
        free(s);
    }
    if (self->target)
        objc_release((id)self->target);
    object_dispose((id)self);
}

void *dispatch_retain(void *o) { return objc_retain(o); }
void dispatch_release(void *o) { objc_release(o); }

/* os_retain and os_release (freemac 1.230), for any OS object, which here
 * is an Objective-C object like dispatch's. */
void *os_retain(void *o) { return o ? objc_retain(o) : o; }
void os_release(void *o)
{
    if (o)
        objc_release(o);
}

/* The global activities <os/activity.h> names (freemac 1.232): only their
 * addresses mean anything, since an activity only groups log messages. */
static char ferry_os_activity_current[16], ferry_os_activity_none[16];

/* Vouchers (freemac 1.230), which carry a Mac's activity and importance
 * across queues, and which Swift's concurrency runtime passes along with its
 * tasks. Ferry has none: there is never a voucher to copy, and adopting one
 * gives back the one in place before, which is none. */
void *voucher_copy(void) { return NULL; }
void *voucher_adopt(void *v)
{
    if (v != (void *)-1) /* not the "dead" voucher Swift marks spent ones with */
        os_release(v);
    return NULL;
}
void *dispatch_get_context(struct dobj *o) { return o ? o->context : NULL; }
void dispatch_set_context(struct dobj *o, void *ctx)
{
    if (o)
        o->context = ctx;
}
void dispatch_set_finalizer_f(struct dobj *o, void (*fn)(void *))
{
    if (o)
        o->finalizer = fn;
}

/* ---- where work runs ---------------------------------------------------------
 * Each queue's work is kept, in order, by the queue that decides when it may
 * run (its domain): the outermost serial queue on its chain of targets, or
 * else the first concurrent queue of the program's own, or else the global
 * queue at the end of the chain. Anything that ends at the main queue is
 * the main queue's, run by the main thread. */

static int is_serial(struct dobj *d) { return d == MAIN_Q || (!d->global && !d->concurrent); }

static struct dobj *domain_of(struct dobj *q)
{
    struct dobj *serial = NULL, *concurrent = NULL;
    for (struct dobj *p = q; p; p = p->target) {
        if (p == MAIN_Q)
            return MAIN_Q;
        if (p->global)
            return serial ? serial : concurrent ? concurrent : p;
        if (!p->concurrent)
            serial = p;
        else if (!concurrent && !serial)
            concurrent = p;
    }
    return serial ? serial : concurrent ? concurrent : DEFAULT_Q;
}

static int chain_suspended(struct dobj *q)
{
    for (; q; q = q->target)
        if (q->suspended > 0 && !q->global)
            return 1;
    return 0;
}

static void wake_main(void)
{
    pthread_cond_broadcast(&event_cond);
    if (main_wakeup)
        main_wakeup();
}

static void spawn_worker(void);
static void start_manager(void);

/* A worker queue now may have work to start: put it on the list and get a
 * worker to it. */
static void kick(struct dobj *d)
{
    if (d == MAIN_Q) {
        wake_main();
        return;
    }
    if (!d->listed) {
        d->listed = 1;
        d->next_listed = NULL;
        if (listed_tail)
            listed_tail->next_listed = d;
        else
            listed_head = d;
        listed_tail = d;
    }
    if (idle_workers > 0)
        pthread_cond_signal(&work_cond);
    else if (workers < soft_max_workers)
        spawn_worker();
    else
        start_manager();
}

static void append(struct dobj *d, struct work *w)
{
    w->next = NULL;
    if (d->tail)
        d->tail->next = w;
    else
        d->head = w;
    d->tail = w;
}

/* Called with the lock held. */
static void enqueue_locked(struct work *w)
{
    struct dobj *d = domain_of(w->queue);
    append(d, w);
    kick(d);
}

/* The next piece of work that may start on domain d, taken off it and
 * counted as running; NULL if none may start now. */
static struct work *take(struct dobj *d)
{
    if (d->barrier || (is_serial(d) && d->running && d != MAIN_Q))
        return NULL;
    struct work *prev = NULL;
    for (struct work *w = d->head; w; prev = w, w = w->next) {
        if (chain_suspended(w->queue))
            continue;
        int barrier = w->barrier && !is_serial(d) && !d->global;
        if (barrier && d->running)
            return NULL;
        if (prev)
            prev->next = w->next;
        else
            d->head = w->next;
        if (d->tail == w)
            d->tail = prev;
        d->running++;
        if (barrier)
            d->barrier = 1;
        return w;
    }
    return NULL;
}

/* For workers: the next piece of work from any worker queue, round robin. */
static struct work *take_any(struct dobj **domain)
{
    struct dobj *prev = NULL;
    for (struct dobj *d = listed_head; d;) {
        struct dobj *next = d->next_listed;
        if (!d->head) {
            /* nothing waits there any more: off the list */
            if (prev)
                prev->next_listed = next;
            else
                listed_head = next;
            if (listed_tail == d)
                listed_tail = prev;
            d->listed = 0;
            d = next;
            continue;
        }
        struct work *w = take(d);
        if (w) {
            /* to the back of the list, so other queues get their turn */
            if (d->head && next) {
                if (prev)
                    prev->next_listed = next;
                else
                    listed_head = next;
                d->next_listed = NULL;
                listed_tail->next_listed = d;
                listed_tail = d;
            }
            *domain = d;
            return w;
        }
        prev = d;
        d = next;
    }
    return NULL;
}

static int startable_work(void)
{
    for (struct dobj *d = listed_head; d; d = d->next_listed) {
        if (!d->head || d->barrier || (is_serial(d) && d->running))
            continue;
        for (struct work *w = d->head; w; w = w->next)
            if (!chain_suspended(w->queue))
                return 1;
    }
    return 0;
}

/* A block of domain d has finished (or a dispatch_sync has given back its turn). */
static void finished_locked(struct dobj *d, struct work *w)
{
    d->running--;
    if (w && w->barrier && d->barrier)
        d->barrier = 0;
    if (d->head)
        kick(d);
}

struct apply_state;
static void group_leave_locked(struct dobj *g);

/* Runs a piece of work on this thread, with domain d's turn held. */
static void execute(struct work *w, struct dobj *d)
{
    struct dobj *saved = current_queue;
    struct held h = {d, held_top};
    current_queue = w->queue;
    held_top = &h;
    void *pool = objc_autoreleasePoolPush();
    if (w->block) {
        struct block_header *b = w->block;
        ((void (*)(void *))b->invoke)(b);
        _Block_release(w->block);
    } else if (w->fn) {
        w->fn(w->ctx);
    }
    objc_autoreleasePoolPop(pool);
    held_top = h.prev;
    current_queue = saved;
    pthread_mutex_lock(&dq);
    finished_locked(d, w);
    if (w->sync) {
        w->sync->done = 1;
        pthread_cond_broadcast(&event_cond);
    }
    if (w->group)
        group_leave_locked(w->group);
    pthread_mutex_unlock(&dq);
    if (w->group)
        objc_release((id)w->group);
    if (w->queue)
        objc_release((id)w->queue);
    free(w);
}

static struct work *make_work(struct dobj *q, void *block, void (*fn)(void *), void *ctx)
{
    struct work *w = calloc(1, sizeof *w);
    if (!q)
        q = DEFAULT_Q;
    w->queue = (struct dobj *)objc_retain((id)q);
    w->block = block ? _Block_copy(block) : NULL;
    w->fn = fn;
    w->ctx = ctx;
    return w;
}

static void enqueue(struct work *w)
{
    pthread_mutex_lock(&dq);
    enqueue_locked(w);
    pthread_mutex_unlock(&dq);
}

/* ---- the worker threads -------------------------------------------------------- */

#define IDLE_EXIT_NS (10 * 1000000000ull)

static void *worker_main(void *unused)
{
    (void)unused;
    ferry_thread_tsd_init();
    pthread_setname_np(pthread_self(), "dispatch-worker");
    pthread_mutex_lock(&dq);
    for (;;) {
        struct dobj *d;
        struct work *w = take_any(&d);
        if (w) {
            progress++;
            if (w->sync) {
                /* a dispatch_sync's turn: its own thread runs the block */
                w->sync->granted = 1;
                pthread_cond_broadcast(&event_cond);
                continue;
            }
            busy_workers++;
            /* More work still waiting and nobody idle to take it: a kick
             * that only signalled an idle worker (this one) counted on it
             * for all of it, so get the next piece a thread now, or tell
             * the manager, which adds one if this block blocks. */
            if (idle_workers == 0 && startable_work()) {
                if (workers < soft_max_workers)
                    spawn_worker();
                else
                    start_manager();
            }
            pthread_mutex_unlock(&dq);
            execute(w, d);
            pthread_mutex_lock(&dq);
            busy_workers--;
            continue;
        }
        idle_workers++;
        int rc = wait_until(&work_cond, now_ns() + IDLE_EXIT_NS);
        idle_workers--;
        if (rc == ETIMEDOUT && !startable_work() && workers > 1)
            break;
    }
    workers--;
    pthread_mutex_unlock(&dq);
    return NULL;
}

static void spawn_worker(void)
{
    pthread_t t;
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &a, worker_main, NULL) == 0)
        workers++;
    pthread_attr_destroy(&a);
}

/* Moves dispatch_after's due work to its queue. */
static void move_due_locked(void)
{
    uint64_t t = now_ns();
    while (later && later->when <= t) {
        struct work *w = later;
        later = w->next;
        enqueue_locked(w);
    }
}

/* The manager: fires dispatch_after's work when it is due, and adds a
 * worker when work is waiting and every worker has been busy without
 * starting anything new for a while (they may all be waiting for work
 * that is still queued, which more threads let run). */
#define STALL_NS (20 * 1000000ull)

static void *manager_main(void *unused)
{
    (void)unused;
    ferry_thread_tsd_init();
    pthread_setname_np(pthread_self(), "dispatch-manager");
    pthread_mutex_lock(&dq);
    unsigned long seen = progress;
    for (;;) {
        move_due_locked();
        uint64_t until = later ? later->when : ~0ull;
        if (idle_workers == 0 && startable_work()) {
            if (progress == seen && workers < hard_max_workers)
                spawn_worker();
            seen = progress;
            uint64_t check = now_ns() + STALL_NS;
            if (check < until)
                until = check;
        } else {
            seen = progress;
        }
        wait_until(&manager_cond, until);
    }
    return NULL;
}

static void start_manager(void)
{
    if (manager_started) {
        pthread_cond_signal(&manager_cond);
        return;
    }
    pthread_t t;
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &a, manager_main, NULL) == 0)
        manager_started = 1;
    pthread_attr_destroy(&a);
}

/* ---- the main queue -------------------------------------------------------------- */

/* For Foundation's run loop, on the main thread: run what the main queue has
 * ready now. Returns how many blocks ran. */
int ferry_dispatch_drain(void)
{
    if (!on_main_thread())
        return 0;
    int n = 0;
    pthread_mutex_lock(&dq);
    struct work *w;
    while (n < 10000 && (w = take(MAIN_Q))) {
        pthread_mutex_unlock(&dq);
        execute(w, MAIN_Q);
        n++;
        pthread_mutex_lock(&dq);
    }
    pthread_mutex_unlock(&dq);
    return n;
}

/* For Foundation's run loop: 0 when the main queue has work ready, else -1
 * (work that arrives later wakes the run loop through main_wakeup). */
int ferry_dispatch_timeout_ms(void)
{
    pthread_mutex_lock(&dq);
    int ready = 0;
    for (struct work *w = MAIN_Q->head; w && !ready; w = w->next)
        ready = !chain_suspended(w->queue);
    pthread_mutex_unlock(&dq);
    return ready ? 0 : -1;
}

/* For Foundation's run loop: is dispatch doing anything, or due to (work
 * queued or running anywhere, or dispatch_after's still to come)? Work that
 * isn't the main queue's may still send some there. */
static int live_ksources; /* read, write, signal and process sources that may still fire */

int ferry_dispatch_busy(void)
{
    pthread_mutex_lock(&dq);
    int busy = busy_workers > 0 || later || MAIN_Q->head || listed_head || live_ksources;
    pthread_mutex_unlock(&dq);
    return busy;
}

/* Foundation's main run loop gives the call that wakes it. */
void ferry_dispatch_set_main_wakeup(void (*fn)(void))
{
    pthread_mutex_lock(&dq);
    main_wakeup = fn;
    pthread_mutex_unlock(&dq);
}

/* Nothing could ever end a wait of the main thread: no other thread of the
 * program's is running, no worker is busy, nothing is queued or due. */
static int nothing_can_happen(void)
{
    return busy_workers == 0 && !later && !startable_work() && ferry_pthread_live_threads() == 0 && !live_ksources;
}

/* For Foundation's waits that block a thread (its locks and NSOperation's
 * waits): could anything still wake the main thread? And the way such a
 * wait stops the program when nothing can. */
int ferry_dispatch_main_can_wake(void)
{
    pthread_mutex_lock(&dq);
    int r = !nothing_can_happen();
    pthread_mutex_unlock(&dq);
    return r;
}
void ferry_dispatch_stop(const char *why) { stop(why); }

/* Waits on event_cond until the deadline. On the main thread a wait for
 * ever looks now and then whether anything could still end it, and stops
 * the program if not. Returns ETIMEDOUT when the deadline passed. */
static int wait_event(uint64_t deadline, const char *what)
{
    if (deadline != ~0ull || !on_main_thread())
        return wait_until(&event_cond, deadline);
    if (nothing_can_happen()) {
        char msg[300];
        snprintf(msg, sizeof msg, "the program waits on the main thread for %s that nothing will %s%s", what,
                 strstr(what, "group") ? "finish" : strstr(what, "semaphore") ? "signal" : "do",
                 MAIN_Q->head ? " (what would is queued for the main queue, which only the main thread runs)" : "");
        stop(msg);
    }
    wait_until(&event_cond, now_ns() + 250 * 1000000ull);
    return 0;
}

/* ---- time --------------------------------------------------------------------- */

#define TIME_NOW 0ull
#define TIME_FOREVER (~0ull)

uint64_t dispatch_time(uint64_t when, int64_t delta)
{
    if (when == TIME_FOREVER)
        return TIME_FOREVER;
    uint64_t base = when == TIME_NOW ? now_ns() : (int64_t)when < 0 ? (uint64_t)-(int64_t)when : when;
    int64_t r = (int64_t)base + delta;
    if (delta > 0 && r < (int64_t)base)
        return TIME_FOREVER;
    if ((int64_t)when < 0 && when != TIME_FOREVER)
        return (uint64_t)-(r < 1 ? 1 : r); /* stays a wall-clock time */
    return r < 1 ? 1 : (uint64_t)r;
}

/* A wall-clock time is stored negated, as on a Mac. */
uint64_t dispatch_walltime(const struct timespec *when, int64_t delta)
{
    struct timespec ts;
    if (!when) {
        clock_gettime(CLOCK_REALTIME, &ts);
        when = &ts;
    }
    int64_t ns = (int64_t)when->tv_sec * 1000000000ll + when->tv_nsec + delta;
    return (uint64_t)-(ns < 1 ? 1 : ns);
}

/* A dispatch time as a point on the monotonic clock. */
static uint64_t deadline_of(uint64_t when)
{
    if (when == TIME_FOREVER)
        return TIME_FOREVER;
    if (when == TIME_NOW)
        return now_ns();
    if ((int64_t)when < 0) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        int64_t wall = (int64_t)ts.tv_sec * 1000000000ll + ts.tv_nsec;
        int64_t left = -(int64_t)when - wall;
        return now_ns() + (left > 0 ? (uint64_t)left : 0);
    }
    return when;
}

/* ---- queues ------------------------------------------------------------------- */

struct dobj *dispatch_get_global_queue(long priority, unsigned long flags)
{
    (void)flags;
    /* DISPATCH_QUEUE_PRIORITY_HIGH 2, DEFAULT 0, LOW -2, BACKGROUND INT16_MIN,
     * or a QoS class; they all run the same way here. */
    int i = priority == 2 || priority == 0x21 || priority == 0x19 ? 0 : priority == -2 || priority == 0x11 ? 2
          : priority == -32768 || priority == 0x09 ? 3 : 1;
    return &global_queues[i];
}

/* DISPATCH_QUEUE_CONCURRENT is the address of this variable; the others
 * are what dispatch_queue_attr_make_initially_inactive returns. */
char ferry_dispatch_queue_attr_concurrent[16];
static char attr_serial_inactive[16], attr_concurrent_inactive[16];

static int attr_concurrent(void *attr)
{
    return attr == ferry_dispatch_queue_attr_concurrent || attr == attr_concurrent_inactive;
}

void *dispatch_queue_attr_make_with_qos_class(void *attr, int qos, int prio)
{
    (void)qos;
    (void)prio;
    return attr;
}
void *dispatch_queue_attr_make_initially_inactive(void *attr)
{
    return attr_concurrent(attr) ? attr_concurrent_inactive : attr_serial_inactive;
}
void *dispatch_queue_attr_make_with_autorelease_frequency(void *attr, unsigned long f)
{
    (void)f;
    return attr;
}

struct dobj *dispatch_queue_create(const char *label, void *attr)
{
    struct dobj *q = new_object(K_QUEUE);
    if (label)
        snprintf(q->label, sizeof q->label, "%s", label);
    q->concurrent = attr_concurrent(attr);
    if (attr == attr_serial_inactive || attr == attr_concurrent_inactive) {
        q->inactive = 1;
        q->suspended = 1;
    }
    return q;
}
struct dobj *dispatch_queue_create_with_target(const char *label, void *attr, struct dobj *target)
{
    struct dobj *q = dispatch_queue_create(label, attr);
    if (target && counted(target))
        objc_retain((id)target);
    q->target = target;
    return q;
}

static struct dobj *current_or_default(void)
{
    if (current_queue)
        return current_queue;
    return on_main_thread() ? MAIN_Q : DEFAULT_Q;
}

const char *dispatch_queue_get_label(struct dobj *q)
{
    if (!q)
        q = current_or_default();
    return q->label;
}

struct dobj *dispatch_get_current_queue(void) { return current_or_default(); }

/* dispatch_assert_queue(3) (freemac 1.230), which Swift's concurrency
 * runtime calls to check an actor's isolation: whether the work running
 * now runs on the queue, directly or through the queues it targets. The
 * main queue's work is whatever runs on the main thread outside other
 * queues. When it isn't, the program stops, as on a Mac. */
static int on_queue(struct dobj *q)
{
    if (q == MAIN_Q && on_main_thread() && (!current_queue || current_queue == MAIN_Q))
        return 1;
    for (struct dobj *c = current_queue; c; c = c->target)
        if (c == q)
            return 1;
    return 0;
}
void dispatch_assert_queue(struct dobj *q)
{
    if (!on_queue(q)) {
        fprintf(stderr, "ferry: BUG IN CLIENT OF LIBDISPATCH: the work runs on queue \"%s\", not on \"%s\" as expected\n",
                current_or_default()->label, q->label);
        abort();
    }
}
void dispatch_assert_queue_not(struct dobj *q)
{
    if (on_queue(q)) {
        fprintf(stderr, "ferry: BUG IN CLIENT OF LIBDISPATCH: the work runs on queue \"%s\", which it shouldn't\n", q->label);
        abort();
    }
}
void dispatch_assert_queue_barrier(struct dobj *q) { dispatch_assert_queue(q); }

void dispatch_set_target_queue(struct dobj *o, struct dobj *target)
{
    if (!o || o == target || !counted(o))
        return;
    if (target && counted(target))
        objc_retain((id)target);
    pthread_mutex_lock(&dq);
    struct dobj *old = o->target;
    o->target = target;
    pthread_mutex_unlock(&dq);
    if (old && counted(old))
        objc_release((id)old);
}

void dispatch_suspend(struct dobj *o)
{
    if (!o || !counted(o))
        return;
    pthread_mutex_lock(&dq);
    o->suspended++;
    pthread_mutex_unlock(&dq);
}

static void arm_timer_locked(struct dobj *s);
static void ksource_resumed_locked(struct dobj *s);

/* After a resume, any queue's work may be free to run again. */
static void kick_all_locked(void)
{
    for (int i = 0; i < 4; i++)
        if (global_queues[i].head)
            kick(&global_queues[i]);
    if (MAIN_Q->head)
        wake_main();
    if (listed_head) {
        if (idle_workers > 0)
            pthread_cond_broadcast(&work_cond);
        else if (workers < soft_max_workers)
            spawn_worker();
    }
}

static void resume_locked(struct dobj *o, struct dobj *domain)
{
    if (o->kind == K_SOURCE) {
        if (o->suspended > 0 && --o->suspended == 0) {
            arm_timer_locked(o);
            ksource_resumed_locked(o);
        }
        return;
    }
    if (o->suspended > 0 && --o->suspended == 0) {
        if (domain->head)
            kick(domain);
        kick_all_locked();
    }
}

void dispatch_resume(struct dobj *o)
{
    if (!o || !counted(o))
        return;
    pthread_mutex_lock(&dq);
    resume_locked(o, o->kind == K_QUEUE ? domain_of(o) : DEFAULT_Q);
    pthread_mutex_unlock(&dq);
}

void dispatch_activate(struct dobj *o)
{
    if (!o || !counted(o))
        return;
    pthread_mutex_lock(&dq);
    if (o->kind == K_SOURCE && o->suspended > 0 && !o->armed)
        resume_locked(o, NULL);
    else if (o->kind == K_QUEUE && o->inactive) {
        o->inactive = 0;
        resume_locked(o, domain_of(o));
    }
    pthread_mutex_unlock(&dq);
}

void dispatch_async(struct dobj *q, void *block) { enqueue(make_work(q, block, NULL, NULL)); }
void dispatch_async_f(struct dobj *q, void *ctx, void (*fn)(void *)) { enqueue(make_work(q, NULL, fn, ctx)); }
void dispatch_barrier_async(struct dobj *q, void *block)
{
    struct work *w = make_work(q, block, NULL, NULL);
    w->barrier = 1;
    enqueue(w);
}
void dispatch_barrier_async_f(struct dobj *q, void *ctx, void (*fn)(void *))
{
    struct work *w = make_work(q, NULL, fn, ctx);
    w->barrier = 1;
    enqueue(w);
}

static int holds(struct dobj *d)
{
    if (d == MAIN_Q && on_main_thread())
        return 1;
    for (struct held *h = held_top; h; h = h->prev)
        if (h->domain == d)
            return 1;
    return 0;
}

/* dispatch_sync: the block runs on this thread once the queue gives it a
 * turn (at once when nothing is ahead of it); the main queue's on the main
 * thread. */
static void sync_run(struct dobj *q, void *block, void (*fn)(void *), void *ctx, int barrier)
{
    if (!q)
        q = DEFAULT_Q;
    pthread_mutex_lock(&dq);
    struct dobj *d = domain_of(q);
    if (holds(d)) {
        pthread_mutex_unlock(&dq);
        if (d == MAIN_Q)
            stop("dispatch_sync onto the main queue from the main thread would never return "
                 "(a Mac stops the program there too)");
        char msg[200];
        snprintf(msg, sizeof msg,
                 "dispatch_sync onto queue \"%s\" from a block that queue is running would never return "
                 "(a Mac stops the program there too)",
                 q->label);
        stop(msg);
    }
    struct syncwait sw = {0, 0};
    if (d == MAIN_Q) {
        /* the main thread runs it, among the main queue's other work */
        struct work *w = make_work(q, block, fn, ctx);
        w->sync = &sw;
        append(d, w);
        wake_main();
        while (!sw.done)
            wait_event(~0ull, "a dispatch_sync onto the main queue");
        pthread_mutex_unlock(&dq);
        return;
    }
    int bar = barrier && !is_serial(d) && !d->global;
    int free_now = !d->head && !d->barrier && !chain_suspended(q) &&
                   (d->global || (is_serial(d) ? !d->running : !(bar && d->running)));
    if (free_now) {
        d->running++;
        if (bar)
            d->barrier = 1;
    } else {
        struct work *w = make_work(q, NULL, NULL, NULL);
        w->barrier = barrier;
        w->sync = &sw;
        append(d, w);
        kick(d);
        while (!sw.granted)
            wait_event(~0ull, "a dispatch_sync's turn");
        objc_release((id)w->queue);
        free(w);
    }
    pthread_mutex_unlock(&dq);

    struct dobj *saved = current_queue;
    struct held h = {d, held_top};
    current_queue = q;
    held_top = &h;
    if (block) {
        struct block_header *b = block;
        ((void (*)(void *))b->invoke)(b);
    } else {
        fn(ctx);
    }
    held_top = h.prev;
    current_queue = saved;

    pthread_mutex_lock(&dq);
    d->running--;
    if (bar)
        d->barrier = 0;
    if (d->head)
        kick(d);
    pthread_mutex_unlock(&dq);
}

void dispatch_sync_f(struct dobj *q, void *ctx, void (*fn)(void *)) { sync_run(q, NULL, fn, ctx, 0); }
void dispatch_sync(struct dobj *q, void *block) { sync_run(q, block, NULL, NULL, 0); }
void dispatch_barrier_sync(struct dobj *q, void *block) { sync_run(q, block, NULL, NULL, 1); }
void dispatch_barrier_sync_f(struct dobj *q, void *ctx, void (*fn)(void *)) { sync_run(q, NULL, fn, ctx, 1); }

/* dispatch_apply: the iterations are shared out between the calling thread
 * and workers when the queue is concurrent; a serial queue runs them one
 * after another on the calling thread. */
struct apply_state {
    size_t n, next, done;
    int refs;
    void *block, *ctx;
    void (*fn)(void *, size_t);
    struct dobj *queue;
};

static void apply_unref(struct apply_state *a)
{
    if (__atomic_sub_fetch(&a->refs, 1, __ATOMIC_ACQ_REL) == 0)
        free(a);
}

static void apply_iterate(struct apply_state *a)
{
    struct dobj *saved = current_queue;
    current_queue = a->queue;
    for (;;) {
        size_t i = __atomic_fetch_add(&a->next, 1, __ATOMIC_RELAXED);
        if (i >= a->n)
            break;
        if (a->block) {
            struct block_header *b = a->block;
            ((void (*)(void *, size_t))b->invoke)(b, i);
        } else {
            a->fn(a->ctx, i);
        }
        if (__atomic_add_fetch(&a->done, 1, __ATOMIC_ACQ_REL) == a->n) {
            pthread_mutex_lock(&dq);
            pthread_cond_broadcast(&event_cond);
            pthread_mutex_unlock(&dq);
        }
    }
    current_queue = saved;
}

static void apply_helper(void *p)
{
    apply_iterate(p);
    apply_unref(p);
}

static void apply_run(size_t n, struct dobj *q, void *block, void *ctx, void (*fn)(void *, size_t))
{
    if (!n)
        return;
    if (!q)
        q = DEFAULT_Q;
    pthread_mutex_lock(&dq);
    struct dobj *d = domain_of(q);
    int parallel = !is_serial(d) && n > 1;
    pthread_mutex_unlock(&dq);
    if (!parallel) {
        struct dobj *saved = current_queue;
        current_queue = q;
        for (size_t i = 0; i < n; i++) {
            if (block) {
                struct block_header *b = block;
                ((void (*)(void *, size_t))b->invoke)(b, i);
            } else {
                fn(ctx, i);
            }
        }
        current_queue = saved;
        return;
    }
    struct apply_state *a = calloc(1, sizeof *a);
    a->n = n;
    a->block = block;
    a->ctx = ctx;
    a->fn = fn;
    a->queue = q;
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    size_t helpers = (size_t)(cpus > 1 ? cpus - 1 : 1);
    if (helpers > n - 1)
        helpers = n - 1;
    a->refs = (int)helpers + 1;
    for (size_t i = 0; i < helpers; i++)
        dispatch_async_f(q, a, apply_helper);
    apply_iterate(a);
    pthread_mutex_lock(&dq);
    while (__atomic_load_n(&a->done, __ATOMIC_ACQUIRE) < n)
        wait_until(&event_cond, ~0ull);
    pthread_mutex_unlock(&dq);
    apply_unref(a);
}

void dispatch_apply(size_t n, struct dobj *q, void *block) { apply_run(n, q, block, NULL, NULL); }
void dispatch_apply_f(size_t n, struct dobj *q, void *ctx, void (*fn)(void *, size_t))
{
    apply_run(n, q, NULL, ctx, fn);
}

static void add_later_locked(struct work *w, uint64_t when)
{
    w->when = deadline_of(when);
    struct work **p = &later;
    while (*p && (*p)->when <= w->when)
        p = &(*p)->next;
    w->next = *p;
    *p = w;
    start_manager();
}

void dispatch_after(uint64_t when, struct dobj *q, void *block)
{
    if (when == TIME_FOREVER)
        return;
    struct work *w = make_work(q, block, NULL, NULL);
    pthread_mutex_lock(&dq);
    add_later_locked(w, when);
    pthread_mutex_unlock(&dq);
}
void dispatch_after_f(uint64_t when, struct dobj *q, void *ctx, void (*fn)(void *))
{
    if (when == TIME_FOREVER)
        return;
    struct work *w = make_work(q, NULL, fn, ctx);
    pthread_mutex_lock(&dq);
    add_later_locked(w, when);
    pthread_mutex_unlock(&dq);
}

void dispatch_queue_set_specific(struct dobj *q, const void *key, void *value, void (*destructor)(void *))
{
    (void)destructor;
    if (!q || !key)
        return;
    pthread_mutex_lock(&dq);
    struct specific *s;
    for (s = q->specifics; s && s->key != key; s = s->next)
        ;
    if (!s) {
        s = calloc(1, sizeof *s);
        s->key = key;
        s->next = q->specifics;
        q->specifics = s;
    }
    s->value = value;
    pthread_mutex_unlock(&dq);
}
void *dispatch_queue_get_specific(struct dobj *q, const void *key)
{
    void *value = NULL;
    pthread_mutex_lock(&dq);
    for (; q && !value; q = q->target)
        for (struct specific *s = q->specifics; s; s = s->next)
            if (s->key == key) {
                value = s->value;
                break;
            }
    pthread_mutex_unlock(&dq);
    return value;
}
void *dispatch_get_specific(const void *key) { return dispatch_queue_get_specific(current_or_default(), key); }

/* The main thread runs the main queue's work for ever. */
void dispatch_main(void)
{
    if (!on_main_thread())
        stop("dispatch_main was called on a thread other than the main thread");
    pthread_mutex_lock(&dq);
    for (;;) {
        struct work *w = take(MAIN_Q);
        if (w) {
            pthread_mutex_unlock(&dq);
            execute(w, MAIN_Q);
            pthread_mutex_lock(&dq);
            continue;
        }
        wait_until(&event_cond, ~0ull);
    }
}

/* dispatch_once: the predicate becomes ~0 once the block has run, which is
 * what the inline version in Apple's header checks for. While it runs, the
 * predicate holds an address that is the running thread's own, so other
 * threads wait and the same thread calling again is caught. */
static __thread char once_mark;

static void once_run(long *predicate, void *block, void *ctx, void (*fn)(void *))
{
    long mine = (long)(uintptr_t)&once_mark;
    long seen = __atomic_load_n(predicate, __ATOMIC_ACQUIRE);
    if (seen == ~0l)
        return;
    if (seen == 0 && __atomic_compare_exchange_n(predicate, &seen, mine, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        if (block) {
            struct block_header *b = block;
            ((void (*)(void *))b->invoke)(b);
        } else {
            fn(ctx);
        }
        pthread_mutex_lock(&dq);
        __atomic_store_n(predicate, ~0l, __ATOMIC_RELEASE);
        pthread_cond_broadcast(&event_cond);
        pthread_mutex_unlock(&dq);
        return;
    }
    if (seen == mine)
        stop("dispatch_once was called again from inside its own block");
    pthread_mutex_lock(&dq);
    while (__atomic_load_n(predicate, __ATOMIC_ACQUIRE) != ~0l)
        wait_event(~0ull, "a dispatch_once block running on another thread");
    pthread_mutex_unlock(&dq);
}

void dispatch_once(long *predicate, void *block) { once_run(predicate, block, NULL, NULL); }
void dispatch_once_f(long *predicate, void *ctx, void (*fn)(void *)) { once_run(predicate, NULL, ctx, fn); }

/* ---- groups -------------------------------------------------------------------- */

struct dobj *dispatch_group_create(void) { return new_object(K_GROUP); }

void dispatch_group_enter(struct dobj *g)
{
    pthread_mutex_lock(&dq);
    g->pending++;
    pthread_mutex_unlock(&dq);
}

static void group_leave_locked(struct dobj *g)
{
    if (--g->pending > 0)
        return;
    g->pending = 0;
    struct work *n = g->notify;
    g->notify = NULL;
    while (n) {
        struct work *next = n->next;
        enqueue_locked(n);
        n = next;
    }
    pthread_cond_broadcast(&event_cond);
}

void dispatch_group_leave(struct dobj *g)
{
    pthread_mutex_lock(&dq);
    group_leave_locked(g);
    pthread_mutex_unlock(&dq);
}

static void group_async(struct dobj *g, struct work *w)
{
    w->group = (struct dobj *)objc_retain((id)g);
    pthread_mutex_lock(&dq);
    g->pending++;
    enqueue_locked(w);
    pthread_mutex_unlock(&dq);
}
void dispatch_group_async(struct dobj *g, struct dobj *q, void *block)
{
    group_async(g, make_work(q, block, NULL, NULL));
}
void dispatch_group_async_f(struct dobj *g, struct dobj *q, void *ctx, void (*fn)(void *))
{
    group_async(g, make_work(q, NULL, fn, ctx));
}

static void add_notify(struct dobj *g, struct work *w)
{
    pthread_mutex_lock(&dq);
    if (g->pending <= 0) {
        enqueue_locked(w);
    } else {
        /* run in the order they were asked for */
        w->next = NULL;
        struct work **p = &g->notify;
        while (*p)
            p = &(*p)->next;
        *p = w;
    }
    pthread_mutex_unlock(&dq);
}
void dispatch_group_notify(struct dobj *g, struct dobj *q, void *block)
{
    add_notify(g, make_work(q, block, NULL, NULL));
}
void dispatch_group_notify_f(struct dobj *g, struct dobj *q, void *ctx, void (*fn)(void *))
{
    add_notify(g, make_work(q, NULL, fn, ctx));
}

long dispatch_group_wait(struct dobj *g, uint64_t timeout)
{
    uint64_t deadline = deadline_of(timeout);
    long result = 0;
    pthread_mutex_lock(&dq);
    while (g->pending > 0) {
        if (timeout == TIME_NOW || wait_event(deadline, "a dispatch group") == ETIMEDOUT) {
            result = g->pending > 0;
            break;
        }
    }
    pthread_mutex_unlock(&dq);
    return result;
}

/* ---- semaphores ------------------------------------------------------------- */

struct dobj *dispatch_semaphore_create(long value)
{
    if (value < 0)
        return NULL;
    struct dobj *s = new_object(K_SEMAPHORE);
    s->value = value;
    return s;
}

/* Returns non-zero when it woke a waiting thread, as on a Mac. */
long dispatch_semaphore_signal(struct dobj *s)
{
    long woke = 0;
    pthread_mutex_lock(&dq);
    if (++s->value <= 0) {
        s->wakeups++;
        woke = 1;
        pthread_cond_broadcast(&event_cond);
    }
    pthread_mutex_unlock(&dq);
    return woke;
}

long dispatch_semaphore_wait(struct dobj *s, uint64_t timeout)
{
    uint64_t deadline = deadline_of(timeout);
    pthread_mutex_lock(&dq);
    if (--s->value >= 0) {
        pthread_mutex_unlock(&dq);
        return 0;
    }
    for (;;) {
        if (s->wakeups > 0) {
            s->wakeups--;
            pthread_mutex_unlock(&dq);
            return 0;
        }
        if (timeout == TIME_NOW || wait_event(deadline, "a dispatch semaphore") == ETIMEDOUT) {
            if (s->wakeups > 0)
                continue;
            s->value++; /* no longer waiting */
            pthread_mutex_unlock(&dq);
            return 1;
        }
    }
}

/* ---- sources ---------------------------------------------------------------- */

/* DISPATCH_SOURCE_TYPE_TIMER and the others are addresses of variables. */
enum { S_TIMER, S_DATA_ADD, S_DATA_OR, S_DATA_REPLACE, S_READ, S_WRITE, S_SIGNAL, S_PROC, S_VNODE, S_MACH_RECV, S_MACH_SEND,
       S_OTHER };
char ferry_dispatch_source_type_timer[16], ferry_dispatch_source_type_data_add[16],
    ferry_dispatch_source_type_data_or[16], ferry_dispatch_source_type_data_replace[16],
    ferry_dispatch_source_type_read[16], ferry_dispatch_source_type_write[16],
    ferry_dispatch_source_type_signal[16], ferry_dispatch_source_type_proc[16],
    ferry_dispatch_source_type_vnode[16], ferry_dispatch_source_type_mach_recv[16],
    ferry_dispatch_source_type_mach_send[16], ferry_dispatch_source_type_memorypressure[16];

static const struct {
    const char *name;
    void *addr;
    int type;
} source_types[] = {
    {"timer", ferry_dispatch_source_type_timer, S_TIMER},
    {"data_add", ferry_dispatch_source_type_data_add, S_DATA_ADD},
    {"data_or", ferry_dispatch_source_type_data_or, S_DATA_OR},
    {"data_replace", ferry_dispatch_source_type_data_replace, S_DATA_REPLACE},
    {"read", ferry_dispatch_source_type_read, S_READ},
    {"write", ferry_dispatch_source_type_write, S_WRITE},
    {"signal", ferry_dispatch_source_type_signal, S_SIGNAL},
    {"proc", ferry_dispatch_source_type_proc, S_PROC},
    {"vnode", ferry_dispatch_source_type_vnode, S_VNODE},
    {"mach_recv", ferry_dispatch_source_type_mach_recv, S_MACH_RECV},
    {"mach_send", ferry_dispatch_source_type_mach_send, S_MACH_SEND},
    {"memorypressure", ferry_dispatch_source_type_memorypressure, S_OTHER},
};

/* A source's handler runs on its queue, but never twice at once: it runs
 * on a serial queue of the source's own that targets that queue. */
struct dobj *dispatch_source_create(const void *type, uintptr_t handle, unsigned long mask, struct dobj *q)
{
    int t = S_OTHER;
    for (size_t i = 0; i < sizeof source_types / sizeof source_types[0]; i++)
        if (type == source_types[i].addr) {
            t = source_types[i].type;
            if (t == S_OTHER)
                fprintf(stderr, "ferry: dispatch sources of type %s aren't supported yet; this one won't fire\n",
                        source_types[i].name);
        }
    /* what a Mac refuses: a signal that isn't one, a descriptor that can't be */
    if ((t == S_SIGNAL && (handle == 0 || handle >= 32)) || ((t == S_READ || t == S_WRITE || t == S_VNODE) && handle > INT32_MAX) ||
        (t == S_PROC && (handle == 0 || handle > INT32_MAX)) || ((t == S_MACH_RECV || t == S_MACH_SEND) && handle > UINT32_MAX))
        return NULL;
    struct dobj *s = new_object(K_SOURCE);
    s->source_type = t;
    s->handle = handle;
    s->mask = mask;
    s->mach_fd = -1;
    s->target = dispatch_queue_create_with_target("source", NULL, q ? q : DEFAULT_Q);
    s->suspended = 1; /* a new source starts suspended */
    return s;
}

static void call_handler(struct dobj *s, unsigned long data)
{
    s->fired_data = data;
    if (s->handler) {
        struct block_header *b = s->handler;
        ((void (*)(void *))b->invoke)(b);
    } else if (s->handler_f) {
        s->handler_f(s->context);
    }
}

static void fire_source(void *ctx)
{
    struct dobj *s = ctx;
    pthread_mutex_lock(&dq);
    if (s->cancelled || s->suspended > 0) {
        s->armed = 0;
        pthread_mutex_unlock(&dq);
        objc_release((id)s);
        return;
    }
    pthread_mutex_unlock(&dq);
    call_handler(s, 1);
    pthread_mutex_lock(&dq);
    if (s->interval && s->interval != TIME_FOREVER && !s->cancelled && s->armed) {
        s->start += s->interval;
        uint64_t t = now_ns();
        if (s->start < t) /* missed firings are merged into one, as on a Mac */
            s->start = t;
        add_later_locked(make_work(s->target, NULL, fire_source, s), s->start);
        pthread_mutex_unlock(&dq);
        return; /* the reference stays with the next firing */
    }
    s->armed = 0;
    pthread_mutex_unlock(&dq);
    objc_release((id)s);
}

static void arm_timer_locked(struct dobj *s)
{
    if (s->source_type != S_TIMER || s->armed || s->cancelled || s->start == TIME_FOREVER || !s->start)
        return;
    s->armed = 1;
    objc_retain((id)s);
    add_later_locked(make_work(s->target, NULL, fire_source, s), s->start);
}

void dispatch_source_set_timer(struct dobj *s, uint64_t start, uint64_t interval, uint64_t leeway)
{
    (void)leeway;
    struct work *gone = NULL;
    pthread_mutex_lock(&dq);
    s->start = deadline_of(start);
    s->interval = interval;
    if (s->armed) {
        /* Take the old firing out and put a new one in. */
        for (struct work **p = &later; *p; p = &(*p)->next)
            if ((*p)->fn == fire_source && (*p)->ctx == s) {
                gone = *p;
                *p = gone->next;
                s->armed = 0;
                break;
            }
    }
    if (s->suspended <= 0)
        arm_timer_locked(s);
    pthread_mutex_unlock(&dq);
    if (gone) {
        objc_release((id)gone->queue);
        free(gone);
        objc_release((id)s);
    }
}

void dispatch_source_set_event_handler(struct dobj *s, void *block)
{
    void *copy = block ? _Block_copy(block) : NULL;
    pthread_mutex_lock(&dq);
    void *old = s->handler;
    s->handler = copy;
    pthread_mutex_unlock(&dq);
    if (old)
        _Block_release(old);
}
/* The function forms (freemac 1.230), which Swift's concurrency runtime
 * uses: the function is called with the source's context. */
void dispatch_source_set_event_handler_f(struct dobj *s, void (*f)(void *))
{
    pthread_mutex_lock(&dq);
    void *old = s->handler;
    s->handler = NULL;
    s->handler_f = f;
    pthread_mutex_unlock(&dq);
    if (old)
        _Block_release(old);
}
void dispatch_source_set_cancel_handler_f(struct dobj *s, void (*f)(void *))
{
    pthread_mutex_lock(&dq);
    void *old = s->cancel_handler;
    s->cancel_handler = NULL;
    s->cancel_f = f;
    pthread_mutex_unlock(&dq);
    if (old)
        _Block_release(old);
}
void dispatch_source_set_cancel_handler(struct dobj *s, void *block)
{
    void *copy = block ? _Block_copy(block) : NULL;
    pthread_mutex_lock(&dq);
    void *old = s->cancel_handler;
    s->cancel_handler = copy;
    pthread_mutex_unlock(&dq);
    if (old)
        _Block_release(old);
}

/* Read, write, signal, process and Mach port sources wait on one kqueue
 * (src/kqueue.c) in a thread of their own. A mach_recv source watches its
 * port with EVFILT_MACHPORT and fires while messages wait, as a read source
 * does; a mach_send source watches for its port's death (src/mach.c). When it reports one, the source's data is
 * merged (bytes ready, signals counted, process events or'ed) and its
 * handler queued on its target queue, as for a data source. A read or
 * write source is registered EV_DISPATCH and enabled again once its
 * handler has run, so it fires again while the descriptor stays ready, as
 * on a Mac. The kqueue's udata is the source's registration number, looked
 * up among the live sources, so a cancelled source is never touched. */
static int kfd = -1;
static struct dobj *ksources;
static uint64_t next_kid;

/* A source the kqueue re-enables after its handler: it fires again while
 * its descriptor stays ready, or while messages wait on its port. */
static int level_source(const struct dobj *s)
{
    return s->source_type == S_READ || s->source_type == S_WRITE || s->source_type == S_MACH_RECV;
}

static int ksource_change(struct dobj *s, int flags)
{
    int16_t filter = s->source_type == S_READ ? FERRY_EVFILT_READ : s->source_type == S_WRITE ? FERRY_EVFILT_WRITE
                   : s->source_type == S_SIGNAL ? FERRY_EVFILT_SIGNAL
                   : s->source_type == S_VNODE ? FERRY_EVFILT_VNODE
                   : s->source_type == S_MACH_RECV ? FERRY_EVFILT_MACHPORT
                   : s->source_type == S_MACH_SEND ? FERRY_EVFILT_READ : FERRY_EVFILT_PROC;
    uint64_t ident = s->source_type == S_MACH_SEND ? (uint64_t)s->mach_fd : s->handle;
    struct kevent64_s k = {.ident = ident, .filter = filter, .flags = (uint16_t)flags, .udata = s->kid};
    if (s->source_type == S_PROC)
        k.fflags = (uint32_t)(s->mask | FERRY_NOTE_EXIT);
    if (s->source_type == S_VNODE) {
        k.fflags = (uint32_t)s->mask;
        if (flags & FERRY_EV_ADD)
            k.flags |= FERRY_EV_CLEAR;
    }
    return ferry_kevent64(kfd, &k, 1, NULL, 0, 0, NULL);
}

static void fire_ksource(void *ctx)
{
    struct dobj *s = ctx;
    pthread_mutex_lock(&dq);
    s->armed = 0;
    if (s->cancelled || s->suspended > 0) { /* kept for the resume */
        pthread_mutex_unlock(&dq);
        objc_release((id)s);
        return;
    }
    unsigned long data = s->data;
    int pending = s->kpending;
    s->data = 0;
    s->kpending = 0;
    pthread_mutex_unlock(&dq);
    if (pending && (data || level_source(s)))
        call_handler(s, data);
    if (level_source(s)) {
        pthread_mutex_lock(&dq);
        if (!s->cancelled && s->kregistered == 1) /* under the lock, so a cancel can't come between */
            ksource_change(s, FERRY_EV_ENABLE);
        pthread_mutex_unlock(&dq);
    }
    objc_release((id)s);
}

static void *ksource_main(void *unused)
{
    (void)unused;
    ferry_thread_tsd_init();
    struct kevent64_s ev[16];
    for (;;) {
        int n = ferry_kevent64(kfd, NULL, 0, ev, 16, 0, NULL);
        if (n <= 0)
            continue;
        pthread_mutex_lock(&dq);
        for (int i = 0; i < n; i++) {
            struct dobj *s = ksources;
            while (s && s->kid != ev[i].udata)
                s = s->next_k;
            if (!s || s->cancelled)
                continue;
            switch (s->source_type) {
            case S_READ:
            case S_WRITE: s->data = ev[i].data > 0 ? (unsigned long)ev[i].data : 0; break;
            case S_SIGNAL: s->data += (unsigned long)ev[i].data; break;
            case S_VNODE: s->data |= ev[i].fflags & s->mask; break;
            case S_MACH_RECV: break;
            case S_MACH_SEND:
                s->data |= 0x1 & s->mask; /* DISPATCH_MACH_SEND_DEAD */
                if (!s->kdone) {
                    s->kdone = 1;
                    live_ksources--;
                }
                break;
            case S_PROC:
                s->data |= ev[i].fflags & s->mask;
                if ((ev[i].flags & FERRY_EV_EOF) && !s->kdone) {
                    s->kdone = 1; /* nothing more will come */
                    live_ksources--;
                }
                break;
            }
            s->kpending = 1;
            if (!s->armed && s->suspended <= 0) {
                s->armed = 1;
                objc_retain((id)s);
                enqueue_locked(make_work(s->target, NULL, fire_ksource, s));
            }
        }
        pthread_mutex_unlock(&dq);
    }
    return NULL;
}

static void ksource_start_locked(struct dobj *s)
{
    if (kfd < 0) {
        kfd = ferry_kqueue();
        pthread_t t;
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        if (kfd < 0 || pthread_create(&t, &a, ksource_main, NULL) != 0) {
            pthread_attr_destroy(&a);
            fprintf(stderr, "ferry: can't watch descriptors, signals or processes for dispatch sources\n");
            s->kregistered = -1;
            return;
        }
        pthread_attr_destroy(&a);
    }
    s->kid = ++next_kid;
    if (s->source_type == S_MACH_SEND && s->mach_fd < 0)
        s->mach_fd = ferry_mach_port_fd((uint32_t)s->handle, 1);
    int flags = FERRY_EV_ADD | (level_source(s) ? FERRY_EV_DISPATCH : 0) |
                (s->source_type == S_MACH_SEND ? FERRY_EV_ONESHOT : 0);
    if (ksource_change(s, flags) < 0) {
        int e = errno;
        fprintf(stderr, "ferry: a dispatch %s source for %lu can't be watched (%s); it won't fire\n",
                s->source_type == S_READ ? "read" : s->source_type == S_WRITE ? "write"
                : s->source_type == S_SIGNAL ? "signal" : s->source_type == S_VNODE ? "vnode"
                : s->source_type == S_MACH_RECV ? "mach_recv" : s->source_type == S_MACH_SEND ? "mach_send" : "process",
                (unsigned long)s->handle, strerror(e));
        s->kregistered = -1;
        return;
    }
    s->kregistered = 1;
    objc_retain((id)s); /* until it is cancelled, as on a Mac */
    s->next_k = ksources;
    ksources = s;
    live_ksources++;
}

/* The source's count of suspensions came back to 0. */
static void ksource_resumed_locked(struct dobj *s)
{
    if (s->source_type != S_READ && s->source_type != S_WRITE && s->source_type != S_SIGNAL &&
        s->source_type != S_PROC && s->source_type != S_VNODE && s->source_type != S_MACH_RECV &&
        s->source_type != S_MACH_SEND)
        return;
    if (s->cancelled)
        return;
    if (!s->kregistered)
        ksource_start_locked(s);
    else if (s->kpending && !s->armed) {
        s->armed = 1;
        objc_retain((id)s);
        enqueue_locked(make_work(s->target, NULL, fire_ksource, s));
    }
}

/* At its cancel: out of the list; 1 if the kqueue has to forget it too. */
static int ksource_forget_locked(struct dobj *s)
{
    if (s->kregistered != 1)
        return 0;
    for (struct dobj **p = &ksources; *p; p = &(*p)->next_k)
        if (*p == s) {
            *p = s->next_k;
            break;
        }
    if (!s->kdone)
        live_ksources--;
    s->kregistered = 2;
    return 1;
}

static void ksource_unwatch(struct dobj *s)
{
    ksource_change(s, FERRY_EV_DELETE); /* fails when the descriptor was closed first, which is fine */
    if (s->mach_fd >= 0) {
        close(s->mach_fd);
        s->mach_fd = -1;
    }
    objc_release((id)s);
}

void dispatch_source_cancel(struct dobj *s)
{
    pthread_mutex_lock(&dq);
    if (s->cancelled) {
        pthread_mutex_unlock(&dq);
        return;
    }
    __atomic_store_n(&s->cancelled, 1, __ATOMIC_RELEASE);
    void *handler = s->cancel_handler;
    void (*handler_f)(void *) = s->cancel_f;
    s->cancel_handler = NULL;
    s->cancel_f = NULL;
    int unwatch = ksource_forget_locked(s);
    pthread_mutex_unlock(&dq);
    if (unwatch)
        ksource_unwatch(s);
    if (handler) {
        dispatch_async(s->target, handler);
        _Block_release(handler);
    } else if (handler_f) {
        dispatch_async_f(s->target, s->context, handler_f);
    }
}
long dispatch_source_testcancel(struct dobj *s) { return __atomic_load_n(&s->cancelled, __ATOMIC_ACQUIRE); }
unsigned long dispatch_source_get_data(struct dobj *s) { return s->fired_data; }
unsigned long dispatch_source_get_mask(struct dobj *s) { return s ? s->mask : 0; }
uintptr_t dispatch_source_get_handle(struct dobj *s) { return s ? s->handle : 0; }

static void fire_data(void *ctx)
{
    struct dobj *s = ctx;
    pthread_mutex_lock(&dq);
    unsigned long data = s->data;
    s->data = 0;
    s->armed = 0;
    int run = !s->cancelled && data;
    pthread_mutex_unlock(&dq);
    if (run)
        call_handler(s, data);
    objc_release((id)s);
}

void dispatch_source_merge_data(struct dobj *s, unsigned long value)
{
    pthread_mutex_lock(&dq);
    if (s->source_type == S_DATA_ADD)
        s->data += value;
    else if (s->source_type == S_DATA_OR)
        s->data |= value;
    else if (s->source_type == S_DATA_REPLACE)
        s->data = value;
    else {
        pthread_mutex_unlock(&dq);
        return;
    }
    if (!s->armed) {
        s->armed = 1;
        objc_retain((id)s);
        enqueue_locked(make_work(s->target, NULL, fire_data, s));
    }
    pthread_mutex_unlock(&dq);
}

/* ---- setup ------------------------------------------------------------------ */

static id q_init_with_queue(id self, SEL _cmd, id queue)
{
    (void)_cmd;
    objc_release(self);
    return objc_retain(queue);
}

void ferry_dispatch_init(void)
{
    static const struct fmethod methods[] = {
        M("dealloc", "v16@0:8", d_dealloc),
    };
    ferry_objc_make_class(&dispatch_class, &dispatch_meta, &ferry_class_NSObject, "OS_dispatch_object",
                          sizeof(struct dobj), methods, 1, NULL, 0, 0);
    static const char *const kinds[4] = {"OS_dispatch_queue", "OS_dispatch_group", "OS_dispatch_semaphore",
                                         "OS_dispatch_source"};
    /* -initWithFerryQueue: (freemac 1.262), which Swift's DispatchQueue(label:...) on OS_dispatch_queue calls
     * after +alloc: the queue Ferry made takes the place of the empty one */
    static const struct fmethod queue_methods[] = {
        M("initWithFerryQueue:", "@24@0:8@16", q_init_with_queue),
    };
    for (int i = 0; i < 4; i++)
        ferry_objc_make_class(&kind_class[i], &kind_meta[i], &dispatch_class, kinds[i], sizeof(struct dobj),
                              i == K_QUEUE ? queue_methods : NULL, i == K_QUEUE ? 1 : 0, NULL, 0, 0);
    ferry_objc_make_class(&static_class, &static_meta, &kind_class[K_QUEUE], "OS_dispatch_queue_main",
                          sizeof(struct dobj), ferry_static_rr_methods, ferry_static_rr_count, NULL, 0,
                          RT_STATIC_INSTANCES);
    ferry_objc_make_class(&global_class, &global_meta, &kind_class[K_QUEUE], "OS_dispatch_queue_global",
                          sizeof(struct dobj), ferry_static_rr_methods, ferry_static_rr_count, NULL, 0,
                          RT_STATIC_INSTANCES);
    static const char *const names[] = {"com.apple.root.user-interactive-qos", "com.apple.root.default-qos",
                                        "com.apple.root.utility-qos", "com.apple.root.background-qos"};
    ferry_dispatch_main_q.isa = &static_class;
    snprintf(ferry_dispatch_main_q.label, sizeof ferry_dispatch_main_q.label, "com.apple.main-thread");
    for (int i = 0; i < 4; i++) {
        global_queues[i].isa = (Class)&global_class;
        global_queues[i].global = 1;
        global_queues[i].concurrent = 1;
        snprintf(global_queues[i].label, sizeof global_queues[i].label, "%s", names[i]);
    }
    main_thread = pthread_self();
    pthread_condattr_t a;
    pthread_condattr_init(&a);
    pthread_condattr_setclock(&a, CLOCK_MONOTONIC);
    pthread_cond_init(&work_cond, &a);
    pthread_cond_init(&manager_cond, &a);
    pthread_cond_init(&event_cond, &a);
    pthread_condattr_destroy(&a);
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    soft_max_workers = cpus > 4 ? (int)cpus : 4;
    ferry_dispatch_io_init();
}

/* What libSystem exports for dispatch. */
#define F(name) {#name, (void *)name}
const struct ferry_symbol ferry_dispatch_symbols[] = {
    {"OBJC_CLASS_$_OS_dispatch_object", &dispatch_class},
    {"OBJC_METACLASS_$_OS_dispatch_object", &dispatch_meta},
    {"OBJC_CLASS_$_OS_dispatch_queue", &kind_class[K_QUEUE]},
    {"OBJC_METACLASS_$_OS_dispatch_queue", &kind_meta[K_QUEUE]},
    {"OBJC_CLASS_$_OS_dispatch_group", &kind_class[K_GROUP]},
    {"OBJC_METACLASS_$_OS_dispatch_group", &kind_meta[K_GROUP]},
    {"OBJC_CLASS_$_OS_dispatch_semaphore", &kind_class[K_SEMAPHORE]},
    {"OBJC_METACLASS_$_OS_dispatch_semaphore", &kind_meta[K_SEMAPHORE]},
    {"OBJC_CLASS_$_OS_dispatch_source", &kind_class[K_SOURCE]},
    {"OBJC_METACLASS_$_OS_dispatch_source", &kind_meta[K_SOURCE]},
    {"_dispatch_main_q", &ferry_dispatch_main_q},
    {"_dispatch_queue_attr_concurrent", ferry_dispatch_queue_attr_concurrent},
    {"_dispatch_source_type_timer", ferry_dispatch_source_type_timer},
    {"_dispatch_source_type_data_add", ferry_dispatch_source_type_data_add},
    {"_dispatch_source_type_data_or", ferry_dispatch_source_type_data_or},
    {"_dispatch_source_type_data_replace", ferry_dispatch_source_type_data_replace},
    {"_dispatch_source_type_read", ferry_dispatch_source_type_read},
    {"_dispatch_source_type_write", ferry_dispatch_source_type_write},
    {"_dispatch_source_type_signal", ferry_dispatch_source_type_signal},
    {"_dispatch_source_type_proc", ferry_dispatch_source_type_proc},
    {"_dispatch_source_type_vnode", ferry_dispatch_source_type_vnode},
    {"_dispatch_source_type_mach_recv", ferry_dispatch_source_type_mach_recv},
    {"_dispatch_source_type_mach_send", ferry_dispatch_source_type_mach_send},
    {"_dispatch_source_type_memorypressure", ferry_dispatch_source_type_memorypressure},
    {"_os_activity_current", ferry_os_activity_current},
    {"_os_activity_none", ferry_os_activity_none},
    F(dispatch_retain), F(dispatch_release), F(os_retain), F(os_release), F(voucher_copy), F(voucher_adopt), F(dispatch_get_context), F(dispatch_set_context),
    F(dispatch_set_finalizer_f), F(dispatch_time), F(dispatch_walltime), F(dispatch_get_global_queue),
    F(dispatch_queue_attr_make_with_qos_class), F(dispatch_queue_attr_make_initially_inactive),
    F(dispatch_queue_attr_make_with_autorelease_frequency), F(dispatch_queue_create),
    F(dispatch_queue_create_with_target), F(dispatch_queue_get_label), F(dispatch_get_current_queue),
    F(dispatch_set_target_queue), F(dispatch_suspend), F(dispatch_resume), F(dispatch_activate),
    F(dispatch_async), F(dispatch_async_f), F(dispatch_barrier_async), F(dispatch_barrier_async_f),
    F(dispatch_sync), F(dispatch_sync_f), F(dispatch_barrier_sync), F(dispatch_barrier_sync_f),
    F(dispatch_apply), F(dispatch_apply_f), F(dispatch_after), F(dispatch_after_f),
    F(dispatch_queue_set_specific), F(dispatch_queue_get_specific), F(dispatch_get_specific), F(dispatch_main),
    F(dispatch_once), F(dispatch_once_f), F(dispatch_group_create), F(dispatch_group_enter),
    F(dispatch_group_leave), F(dispatch_group_async), F(dispatch_group_async_f), F(dispatch_group_notify),
    F(dispatch_group_notify_f), F(dispatch_group_wait), F(dispatch_semaphore_create),
    F(dispatch_semaphore_signal), F(dispatch_semaphore_wait), F(dispatch_source_create),
    F(dispatch_source_set_timer), F(dispatch_source_set_event_handler), F(dispatch_source_set_cancel_handler),
    F(dispatch_source_set_event_handler_f), F(dispatch_source_set_cancel_handler_f),
    F(dispatch_assert_queue), F(dispatch_assert_queue_not), F(dispatch_assert_queue_barrier),
    F(dispatch_source_cancel), F(dispatch_source_testcancel), F(dispatch_source_get_data),
    F(dispatch_source_get_mask), F(dispatch_source_get_handle), F(dispatch_source_merge_data),
    F(ferry_dispatch_drain), F(ferry_dispatch_timeout_ms), F(ferry_dispatch_busy),
    F(ferry_dispatch_set_main_wakeup), F(ferry_dispatch_main_can_wake), F(ferry_dispatch_stop),
    {NULL, NULL},
};
