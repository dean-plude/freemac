/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Grand Central Dispatch (libdispatch), the part of libSystem that Mac
 * programs use to run blocks later or elsewhere: queues, dispatch_async and
 * dispatch_sync, dispatch_once, dispatch_after, groups, semaphores and timer
 * sources.
 *
 * Ferry runs a Mac program on one thread, so every queue's work runs on the
 * main thread, in the order it was queued: Foundation's run loop (and
 * dispatch_main) asks for it on each pass. That keeps the guarantees a
 * program can rely on (a serial queue runs one block at a time, in order;
 * dispatch_sync returns after its block has run) but nothing runs at the
 * same time as anything else. A wait (dispatch_semaphore_wait,
 * dispatch_group_wait) runs queued work until what it waits for happens;
 * if nothing queued could make it happen, Ferry says so and stops rather
 * than hang.
 *
 * Dispatch objects are Objective-C objects, as on a Mac, so that code built
 * with ARC can retain and release them. Written from Apple's public
 * documentation of libdispatch's calls; no Apple code was used.
 */
#define _GNU_SOURCE
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
    struct specific *specifics;
    /* groups */
    long pending;
    struct work *notify;
    /* semaphores */
    long value;
    /* sources */
    int source_type;
    struct dobj *target;
    uint64_t start, interval;
    void *handler, *cancel_handler; /* blocks */
    int cancelled, armed;
    unsigned long data;
};

struct specific {
    const void *key;
    void *value;
    struct specific *next;
};

struct work {
    struct dobj *queue;
    void *block;             /* a copied block, or NULL */
    void (*fn)(void *);
    void *ctx;
    struct dobj *group;      /* left when the work is done */
    uint64_t when;           /* for dispatch_after */
    struct work *next;
};

/* The classes: one for objects made at run time, and one for the main and
 * global queues, which live as long as the program and ignore retain and
 * release. */
static struct fobjc_class dispatch_class, dispatch_meta, static_class, static_meta;

/* The main queue's symbol is a variable (dispatch_get_main_queue() is a macro
 * for its address); the global queues are returned by a call. */
struct dobj ferry_dispatch_main_q;
static struct dobj global_queues[4];

/* What the program has asked to run, oldest first, and dispatch_after's
 * work, soonest first. */
static struct work *ready_head, *ready_tail, *later;
static struct dobj *current_queue;

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

/* ---- objects ------------------------------------------------------------------ */

static struct dobj *new_object(enum kind kind)
{
    struct dobj *o = (struct dobj *)class_createInstance(&dispatch_class, 0);
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
    object_dispose((id)self);
}

static const char *d_description_label(struct dobj *self) { return self->label; }

void *dispatch_retain(void *o) { return objc_retain(o); }
void dispatch_release(void *o) { objc_release(o); }
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

/* ---- running work ------------------------------------------------------------- */

static void run_work(struct work *w)
{
    struct dobj *saved = current_queue;
    current_queue = w->queue;
    void *pool = objc_autoreleasePoolPush();
    if (w->block) {
        struct block_header *b = w->block;
        ((void (*)(void *))b->invoke)(b);
        _Block_release(w->block);
    } else if (w->fn) {
        w->fn(w->ctx);
    }
    objc_autoreleasePoolPop(pool);
    current_queue = saved;
    if (w->group) {
        void dispatch_group_leave(struct dobj *);
        dispatch_group_leave(w->group);
        objc_release((id)w->group);
    }
    if (w->queue)
        objc_release((id)w->queue);
    free(w);
}

static struct work *make_work(struct dobj *q, void *block, void (*fn)(void *), void *ctx)
{
    struct work *w = calloc(1, sizeof *w);
    w->queue = q ? (struct dobj *)objc_retain((id)q) : NULL;
    w->block = block ? _Block_copy(block) : NULL;
    w->fn = fn;
    w->ctx = ctx;
    return w;
}

static void enqueue(struct work *w)
{
    w->next = NULL;
    if (ready_tail)
        ready_tail->next = w;
    else
        ready_head = w;
    ready_tail = w;
}

static int suspended(struct dobj *q)
{
    for (; q; q = q->target)
        if (q->suspended > 0)
            return 1;
    return 0;
}

/* Moves dispatch_after's due work and fires due timers. */
static void move_due(void)
{
    uint64_t t = now_ns();
    while (later && later->when <= t) {
        struct work *w = later;
        later = w->next;
        enqueue(w);
    }
}

/* Runs one piece of ready work. Returns 0 when there was none. */
static int run_one(void)
{
    move_due();
    for (struct work **p = &ready_head, *prev = NULL; *p; prev = *p, p = &(*p)->next) {
        struct work *w = *p;
        if (suspended(w->queue))
            continue;
        *p = w->next;
        if (ready_tail == w)
            ready_tail = prev;
        run_work(w);
        return 1;
    }
    return 0;
}

/* For Foundation's run loop: run everything that is ready now. Returns how
 * many blocks ran. */
int ferry_dispatch_drain(void)
{
    int n = 0;
    while (n < 10000 && run_one())
        n++;
    return n;
}

/* For Foundation's run loop: how long it may wait before dispatch has work,
 * in milliseconds; -1 for as long as it likes. */
int ferry_dispatch_timeout_ms(void)
{
    for (struct work *w = ready_head; w; w = w->next)
        if (!suspended(w->queue))
            return 0;
    if (!later)
        return -1;
    uint64_t t = now_ns();
    if (later->when <= t)
        return 0;
    uint64_t ms = (later->when - t + 999999) / 1000000;
    return ms > 2000000000 ? 2000000000 : (int)ms;
}

/* Waits for dispatch's next piece of work, running it. Returns 0 if there
 * is nothing that could ever become ready. */
static int wait_one(uint64_t deadline)
{
    if (run_one())
        return 1;
    int ms = ferry_dispatch_timeout_ms();
    if (ms < 0)
        return 0;
    uint64_t t = now_ns();
    uint64_t until = later->when < deadline ? later->when : deadline;
    if (until > t) {
        struct timespec ts = {(time_t)((until - t) / 1000000000ull), (long)((until - t) % 1000000000ull)};
        nanosleep(&ts, NULL);
    }
    return run_one() || now_ns() < deadline;
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

/* DISPATCH_QUEUE_CONCURRENT is the address of this variable. */
char ferry_dispatch_queue_attr_concurrent[16];

void *dispatch_queue_attr_make_with_qos_class(void *attr, int qos, int prio)
{
    (void)qos;
    (void)prio;
    return attr;
}
void *dispatch_queue_attr_make_initially_inactive(void *attr) { return attr; }
void *dispatch_queue_attr_make_with_autorelease_frequency(void *attr, unsigned long f)
{
    (void)f;
    return attr;
}

struct dobj *dispatch_queue_create(const char *label, void *attr)
{
    (void)attr;
    struct dobj *q = new_object(K_QUEUE);
    if (label)
        snprintf(q->label, sizeof q->label, "%s", label);
    return q;
}
struct dobj *dispatch_queue_create_with_target(const char *label, void *attr, struct dobj *target)
{
    struct dobj *q = dispatch_queue_create(label, attr);
    q->target = target;
    return q;
}

const char *dispatch_queue_get_label(struct dobj *q)
{
    if (!q)
        q = current_queue ? current_queue : &ferry_dispatch_main_q;
    return d_description_label(q);
}

struct dobj *dispatch_get_current_queue(void) { return current_queue ? current_queue : &ferry_dispatch_main_q; }

void dispatch_set_target_queue(struct dobj *o, struct dobj *target)
{
    if (o && o != target && o->isa == &dispatch_class)
        o->target = target;
}

void dispatch_suspend(struct dobj *o)
{
    if (o)
        o->suspended++;
}

static void arm_timer(struct dobj *s);

void dispatch_resume(struct dobj *o)
{
    if (!o)
        return;
    if (o->kind == K_SOURCE) {
        if (o->suspended > 0 && --o->suspended == 0)
            arm_timer(o);
        return;
    }
    if (o->suspended > 0)
        o->suspended--;
}
void dispatch_activate(struct dobj *o)
{
    if (o && o->kind == K_SOURCE && o->suspended > 0)
        dispatch_resume(o);
}

void dispatch_async(struct dobj *q, void *block) { enqueue(make_work(q, block, NULL, NULL)); }
void dispatch_async_f(struct dobj *q, void *ctx, void (*fn)(void *)) { enqueue(make_work(q, NULL, fn, ctx)); }
void dispatch_barrier_async(struct dobj *q, void *block) { dispatch_async(q, block); }
void dispatch_barrier_async_f(struct dobj *q, void *ctx, void (*fn)(void *)) { dispatch_async_f(q, ctx, fn); }

/* There is only one thread, so a block sent with dispatch_sync runs at once. */
void dispatch_sync_f(struct dobj *q, void *ctx, void (*fn)(void *))
{
    struct dobj *saved = current_queue;
    current_queue = q;
    fn(ctx);
    current_queue = saved;
}
void dispatch_sync(struct dobj *q, void *block)
{
    struct dobj *saved = current_queue;
    current_queue = q;
    struct block_header *b = block;
    ((void (*)(void *))b->invoke)(b);
    current_queue = saved;
}
void dispatch_barrier_sync(struct dobj *q, void *block) { dispatch_sync(q, block); }
void dispatch_barrier_sync_f(struct dobj *q, void *ctx, void (*fn)(void *)) { dispatch_sync_f(q, ctx, fn); }

void dispatch_apply(size_t n, struct dobj *q, void *block)
{
    (void)q;
    struct block_header *b = block;
    for (size_t i = 0; i < n; i++)
        ((void (*)(void *, size_t))b->invoke)(b, i);
}
void dispatch_apply_f(size_t n, struct dobj *q, void *ctx, void (*fn)(void *, size_t))
{
    (void)q;
    for (size_t i = 0; i < n; i++)
        fn(ctx, i);
}

static void add_later(struct work *w, uint64_t when)
{
    w->when = deadline_of(when);
    struct work **p = &later;
    while (*p && (*p)->when <= w->when)
        p = &(*p)->next;
    w->next = *p;
    *p = w;
}

void dispatch_after(uint64_t when, struct dobj *q, void *block)
{
    if (when == TIME_FOREVER)
        return;
    add_later(make_work(q, block, NULL, NULL), when);
}
void dispatch_after_f(uint64_t when, struct dobj *q, void *ctx, void (*fn)(void *))
{
    if (when == TIME_FOREVER)
        return;
    add_later(make_work(q, NULL, fn, ctx), when);
}

void dispatch_queue_set_specific(struct dobj *q, const void *key, void *value, void (*destructor)(void *))
{
    (void)destructor;
    if (!q || !key)
        return;
    for (struct specific *s = q->specifics; s; s = s->next)
        if (s->key == key) {
            s->value = value;
            return;
        }
    struct specific *s = calloc(1, sizeof *s);
    s->key = key;
    s->value = value;
    s->next = q->specifics;
    q->specifics = s;
}
void *dispatch_queue_get_specific(struct dobj *q, const void *key)
{
    for (; q; q = q->target)
        for (struct specific *s = q->specifics; s; s = s->next)
            if (s->key == key)
                return s->value;
    return NULL;
}
void *dispatch_get_specific(const void *key)
{
    return dispatch_queue_get_specific(current_queue ? current_queue : &ferry_dispatch_main_q, key);
}

/* Runs the main queue (and every other queue) for ever. */
void dispatch_main(void)
{
    for (;;)
        if (!wait_one(TIME_FOREVER))
            pause();
}

/* dispatch_once: the predicate becomes ~0 once the block has run, which is
 * what the inline version in Apple's header checks for. */
void dispatch_once(long *predicate, void *block)
{
    if (*predicate == ~0l)
        return;
    if (*predicate == 1)
        stop("dispatch_once was called again from inside its own block");
    *predicate = 1;
    struct block_header *b = block;
    ((void (*)(void *))b->invoke)(b);
    *predicate = ~0l;
}
void dispatch_once_f(long *predicate, void *ctx, void (*fn)(void *))
{
    if (*predicate == ~0l)
        return;
    *predicate = 1;
    fn(ctx);
    *predicate = ~0l;
}

/* ---- groups -------------------------------------------------------------------- */

struct dobj *dispatch_group_create(void) { return new_object(K_GROUP); }

void dispatch_group_enter(struct dobj *g) { g->pending++; }

void dispatch_group_leave(struct dobj *g)
{
    if (--g->pending > 0)
        return;
    g->pending = 0;
    struct work *n = g->notify;
    g->notify = NULL;
    while (n) {
        struct work *next = n->next;
        enqueue(n);
        n = next;
    }
}

void dispatch_group_async(struct dobj *g, struct dobj *q, void *block)
{
    struct work *w = make_work(q, block, NULL, NULL);
    w->group = (struct dobj *)objc_retain((id)g);
    g->pending++;
    enqueue(w);
}
void dispatch_group_async_f(struct dobj *g, struct dobj *q, void *ctx, void (*fn)(void *))
{
    struct work *w = make_work(q, NULL, fn, ctx);
    w->group = (struct dobj *)objc_retain((id)g);
    g->pending++;
    enqueue(w);
}

static void add_notify(struct dobj *g, struct work *w)
{
    if (g->pending <= 0) {
        enqueue(w);
        return;
    }
    w->next = g->notify;
    g->notify = w;
}
void dispatch_group_notify(struct dobj *g, struct dobj *q, void *block) { add_notify(g, make_work(q, block, NULL, NULL)); }
void dispatch_group_notify_f(struct dobj *g, struct dobj *q, void *ctx, void (*fn)(void *))
{
    add_notify(g, make_work(q, NULL, fn, ctx));
}

long dispatch_group_wait(struct dobj *g, uint64_t timeout)
{
    uint64_t deadline = deadline_of(timeout);
    while (g->pending > 0) {
        if (!wait_one(deadline)) {
            if (timeout == TIME_FOREVER)
                stop("the program waits for a dispatch group that nothing will finish "
                     "(Ferry runs Mac programs on one thread)");
            return 1;
        }
        if (now_ns() >= deadline && g->pending > 0)
            return 1;
    }
    return 0;
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

long dispatch_semaphore_signal(struct dobj *s)
{
    s->value++;
    return 0;
}

long dispatch_semaphore_wait(struct dobj *s, uint64_t timeout)
{
    uint64_t deadline = deadline_of(timeout);
    while (s->value <= 0) {
        if (timeout == TIME_NOW)
            return 1;
        if (!wait_one(deadline)) {
            if (timeout == TIME_FOREVER)
                stop("the program waits on a dispatch semaphore that nothing will signal "
                     "(Ferry runs Mac programs on one thread)");
            return 1;
        }
        if (now_ns() >= deadline && s->value <= 0)
            return 1;
    }
    s->value--;
    return 0;
}

/* ---- sources ---------------------------------------------------------------- */

/* DISPATCH_SOURCE_TYPE_TIMER and the others are addresses of variables. */
enum { S_TIMER, S_DATA_ADD, S_DATA_OR, S_DATA_REPLACE, S_OTHER };
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
    {"read", ferry_dispatch_source_type_read, S_OTHER},
    {"write", ferry_dispatch_source_type_write, S_OTHER},
    {"signal", ferry_dispatch_source_type_signal, S_OTHER},
    {"proc", ferry_dispatch_source_type_proc, S_OTHER},
    {"vnode", ferry_dispatch_source_type_vnode, S_OTHER},
    {"mach_recv", ferry_dispatch_source_type_mach_recv, S_OTHER},
    {"mach_send", ferry_dispatch_source_type_mach_send, S_OTHER},
    {"memorypressure", ferry_dispatch_source_type_memorypressure, S_OTHER},
};

struct dobj *dispatch_source_create(const void *type, uintptr_t handle, unsigned long mask, struct dobj *q)
{
    (void)handle;
    (void)mask;
    struct dobj *s = new_object(K_SOURCE);
    s->source_type = S_OTHER;
    for (size_t i = 0; i < sizeof source_types / sizeof source_types[0]; i++)
        if (type == source_types[i].addr) {
            s->source_type = source_types[i].type;
            if (s->source_type == S_OTHER)
                fprintf(stderr, "ferry: dispatch sources of type %s aren't supported yet; this one won't fire\n",
                        source_types[i].name);
        }
    s->target = q ? q : &global_queues[1];
    s->suspended = 1; /* a new source starts suspended */
    return s;
}

static void fire_source(void *ctx)
{
    struct dobj *s = ctx;
    if (s->cancelled || s->suspended > 0) {
        s->armed = 0;
        objc_release((id)s);
        return;
    }
    if (s->source_type == S_TIMER)
        s->data = 1;
    if (s->handler) {
        struct block_header *b = s->handler;
        struct dobj *saved = current_queue;
        current_queue = s->target;
        ((void (*)(void *))b->invoke)(b);
        current_queue = saved;
    }
    s->data = 0;
    if (s->source_type == S_TIMER && s->interval && s->interval != TIME_FOREVER && !s->cancelled) {
        s->start += s->interval;
        uint64_t t = now_ns();
        if (s->start < t) /* missed firings are merged into one, as on a Mac */
            s->start = t;
        struct work *w = make_work(s->target, NULL, fire_source, s);
        add_later(w, s->start);
        return; /* the reference stays with the next firing */
    }
    s->armed = 0;
    objc_release((id)s);
}

static void arm_timer(struct dobj *s)
{
    if (s->source_type != S_TIMER || s->armed || s->cancelled || s->start == TIME_FOREVER || !s->start)
        return;
    s->armed = 1;
    objc_retain((id)s);
    add_later(make_work(s->target, NULL, fire_source, s), s->start);
}

void dispatch_source_set_timer(struct dobj *s, uint64_t start, uint64_t interval, uint64_t leeway)
{
    (void)leeway;
    s->start = deadline_of(start);
    s->interval = interval;
    if (s->armed) {
        /* Take the old firing out and put a new one in. */
        for (struct work **p = &later; *p; p = &(*p)->next)
            if ((*p)->fn == fire_source && (*p)->ctx == s) {
                struct work *w = *p;
                *p = w->next;
                objc_release((id)w->queue);
                free(w);
                break;
            }
        s->armed = 0;
        objc_release((id)s);
    }
    if (s->suspended <= 0)
        arm_timer(s);
}

void dispatch_source_set_event_handler(struct dobj *s, void *block)
{
    if (s->handler)
        _Block_release(s->handler);
    s->handler = block ? _Block_copy(block) : NULL;
}
void dispatch_source_set_cancel_handler(struct dobj *s, void *block)
{
    if (s->cancel_handler)
        _Block_release(s->cancel_handler);
    s->cancel_handler = block ? _Block_copy(block) : NULL;
}

void dispatch_source_cancel(struct dobj *s)
{
    if (s->cancelled)
        return;
    s->cancelled = 1;
    if (s->cancel_handler) {
        dispatch_async(s->target, s->cancel_handler);
        _Block_release(s->cancel_handler);
        s->cancel_handler = NULL;
    }
}
long dispatch_source_testcancel(struct dobj *s) { return s->cancelled; }
unsigned long dispatch_source_get_data(struct dobj *s) { return s->data; }
unsigned long dispatch_source_get_mask(struct dobj *s) { (void)s; return 0; }
uintptr_t dispatch_source_get_handle(struct dobj *s) { (void)s; return 0; }

static void fire_data(void *ctx)
{
    struct dobj *s = ctx;
    if (!s->cancelled && s->handler && s->data) {
        struct block_header *b = s->handler;
        ((void (*)(void *))b->invoke)(b);
    }
    s->data = 0;
    s->armed = 0;
    objc_release((id)s);
}

void dispatch_source_merge_data(struct dobj *s, unsigned long value)
{
    if (s->source_type == S_DATA_ADD)
        s->data += value;
    else if (s->source_type == S_DATA_OR)
        s->data |= value;
    else if (s->source_type == S_DATA_REPLACE)
        s->data = value;
    else
        return;
    if (!s->armed) {
        s->armed = 1;
        objc_retain((id)s);
        enqueue(make_work(s->target, NULL, fire_data, s));
    }
}

/* ---- setup ------------------------------------------------------------------ */

void ferry_dispatch_init(void)
{
    static const struct fmethod methods[] = {
        M("dealloc", "v16@0:8", d_dealloc),
    };
    ferry_objc_make_class(&dispatch_class, &dispatch_meta, &ferry_class_NSObject, "OS_dispatch_object",
                          sizeof(struct dobj), methods, 1, NULL, 0, 0);
    ferry_objc_make_class(&static_class, &static_meta, &ferry_class_NSObject, "OS_dispatch_queue_static",
                          sizeof(struct dobj), ferry_static_rr_methods, ferry_static_rr_count, NULL, 0,
                          RT_STATIC_INSTANCES);
    static const char *const names[] = {"com.apple.root.user-interactive-qos", "com.apple.root.default-qos",
                                        "com.apple.root.utility-qos", "com.apple.root.background-qos"};
    ferry_dispatch_main_q.isa = &static_class;
    snprintf(ferry_dispatch_main_q.label, sizeof ferry_dispatch_main_q.label, "com.apple.main-thread");
    for (int i = 0; i < 4; i++) {
        global_queues[i].isa = &static_class;
        snprintf(global_queues[i].label, sizeof global_queues[i].label, "%s", names[i]);
    }
}

/* What libSystem exports for dispatch. */
#define F(name) {#name, (void *)name}
const struct ferry_symbol ferry_dispatch_symbols[] = {
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
    F(dispatch_retain), F(dispatch_release), F(dispatch_get_context), F(dispatch_set_context),
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
    F(dispatch_source_cancel), F(dispatch_source_testcancel), F(dispatch_source_get_data),
    F(dispatch_source_get_mask), F(dispatch_source_get_handle), F(dispatch_source_merge_data),
    F(ferry_dispatch_drain), F(ferry_dispatch_timeout_ms),
    {NULL, NULL},
};
