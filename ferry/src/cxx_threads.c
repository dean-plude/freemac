/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The parts of the C++ library whose data a Mac program lays out
 * differently from this system's libc++ (src/cxx.c).
 *
 * A Mac program compiles the inline parts of libc++ into itself, against
 * the Mac's types, and calls the rest in the library. Where an object's
 * layout comes from a Mac type that differs on Linux, the inline code and
 * this system's library would disagree about the same bytes, so Ferry
 * serves those calls itself, on the Mac layout:
 *
 *   - std::mutex holds a Mac pthread_mutex_t (64 bytes, Linux's is 40) and
 *     std::condition_variable a Mac pthread_cond_t, both set up by the
 *     program's inline constructors with the Mac's static initializers.
 *     Their calls go to Ferry's Mac pthreads (pthread.c), which accept them.
 *     timed_mutex, recursive_timed_mutex and shared_timed_mutex hold those
 *     at Mac offsets, and so do the shared states of std::future and
 *     std::promise: Ferry serves their library calls too.
 *   - std::thread: joining and detaching go through Ferry's pthreads.
 *   - std::ctype<char> answers is() from a table of class bits the program
 *     reads directly; a Mac's bits are not this system's, so the facets a
 *     program gets carry a table in the Mac's form.
 *   - std::fpos (streampos) holds a Mac mbstate_t, 128 bytes, so the stream
 *     calls that take or return a position convert it. A Mac program gets a
 *     position back in memory where this system's library returns it in
 *     two registers, and the stream buffers' virtual seekoff and seekpos
 *     are called both ways, by the program's inline code and by the
 *     library: Ferry puts in their place calls that tell the two apart.
 *   - std::basic_filebuf<char> holds two of those, so std::ifstream and
 *     std::ofstream, whose stream state follows their file buffer, place it
 *     further on than this system's library does. Their virtual tables,
 *     which say where it is, are given out in the Mac's form.
 *
 * Errors come back as on a Mac, with Mac error numbers. Each call does
 * what the C++ standard and LLVM libc++'s public interface say it does;
 * written from the C++ standard and the Itanium C++ ABI, with this
 * system's libc++ called for everything else.
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <link.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

#include "cxx.h"
#include "ferry.h"

/* ---- Ferry's Mac pthreads, and this system's libc++ ------------------------------- */

static int (*m_lock)(void *), (*m_trylock)(void *), (*m_unlock)(void *), (*m_destroy)(void *);
static int (*c_wait)(void *, void *), (*c_timedwait)(void *, void *, const struct timespec *);
static int (*c_signal)(void *), (*c_broadcast)(void *), (*c_destroy)(void *);
static int (*t_join)(pthread_t, void **), (*t_detach)(pthread_t);
static pthread_t (*t_self)(void);

static void (*throw_system_error)(int, const char *);
static void *(*allocate_exception)(size_t);
static void (*cxa_throw)(void *, void *, void (*)(void *));
static void *(*init_primary_exception)(void *, void *, void (*)(void *));
struct error_code { int value; const void *category; };
static const void *(*future_category)(void);
static void (*future_error_ctor)(void *, struct error_code);
static void *future_error_typeinfo, *assoc_typeinfo;
static void (*future_error_dtor)(void *);
static void (*eptr_copy)(void *, const void *), (*eptr_dtor)(void *);
static void (*eptr_rethrow)(void *);
static void (*eptr_from_native)(void *, void *);
static void (*terminate)(void);

/* Mac error numbers the C++ library reports */
enum { MAC_EPERM = 1, MAC_EINVAL = 22, MAC_EAGAIN = 35, MAC_ETIMEDOUT = 60 };

/* ---- the Mac layouts ---------------------------------------------------------------- */

#define MAC_MUTEX_SIG 0x32AAABA7L   /* PTHREAD_MUTEX_INITIALIZER's signature */
#define MAC_COND_SIG 0x3CB0B1BBL    /* PTHREAD_COND_INITIALIZER's */
enum { MUTEX_SIZE = 64, COND_SIZE = 48 };

struct unique_lock { void *m; _Bool owns; };

static void mutex_init(void *m)
{
    memset(m, 0, MUTEX_SIZE);
    *(long *)m = MAC_MUTEX_SIG;
}
static void cond_init(void *c)
{
    memset(c, 0, COND_SIZE);
    *(long *)c = MAC_COND_SIG;
}

/* ---- std::mutex ------------------------------------------------------------------- */

static void mutex_lock(void *m)
{
    int ec = m_lock(m);
    if (ec)
        throw_system_error(ec, "mutex lock failed");
}
static _Bool mutex_try_lock(void *m) { return m_trylock(m) == 0; }
static void mutex_unlock(void *m) { m_unlock(m); }
static void mutex_dtor(void *m) { m_destroy(m); }

/* ---- std::condition_variable ------------------------------------------------------ */

static void cv_dtor(void *c) { c_destroy(c); }
static void cv_notify_one(void *c) { c_signal(c); }
static void cv_notify_all(void *c) { c_broadcast(c); }

static void cv_wait(void *c, struct unique_lock *lk)
{
    if (!lk->owns)
        throw_system_error(MAC_EPERM, "condition_variable::wait: mutex not locked");
    int ec = c_wait(c, lk->m);
    if (ec)
        throw_system_error(ec, "condition_variable wait failed");
}

/* until a time on the system clock, in nanoseconds since 1970 */
static void cv_timed_wait(void *c, struct unique_lock *lk, long long ns)
{
    if (!lk->owns)
        throw_system_error(MAC_EPERM, "condition_variable::timed wait: mutex not locked");
    struct timespec t;
    if (ns < 0)
        ns = 0;
    t.tv_sec = (time_t)(ns / 1000000000);
    t.tv_nsec = (long)(ns % 1000000000);
    int ec = c_timedwait(c, lk->m, &t);
    if (ec && ec != MAC_ETIMEDOUT)
        throw_system_error(ec, "condition_variable timed_wait failed");
}

/* a unique_lock of the program's kind, over Ferry's calls */
static void lock_of(struct unique_lock *lk, void *m)
{
    lk->m = m;
    mutex_lock(m);
    lk->owns = 1;
}
static void unlock_of(struct unique_lock *lk)
{
    if (lk->owns)
        mutex_unlock(lk->m);
    lk->owns = 0;
}

/* ---- timed_mutex: {mutex; condition_variable at 64; bool locked at 112} ---------- */

#define TM_CV(t) ((char *)(t) + 64)
#define TM_LOCKED(t) (*(_Bool *)((char *)(t) + 112))

static void timed_mutex_ctor(void *t)
{
    mutex_init(t);
    cond_init(TM_CV(t));
    TM_LOCKED(t) = 0;
}
static void timed_mutex_dtor(void *t)
{
    mutex_lock(t);
    mutex_unlock(t);
    cv_dtor(TM_CV(t));
    mutex_dtor(t);
}
static void timed_mutex_lock(void *t)
{
    struct unique_lock lk;
    lock_of(&lk, t);
    while (TM_LOCKED(t))
        cv_wait(TM_CV(t), &lk);
    TM_LOCKED(t) = 1;
    unlock_of(&lk);
}
static _Bool timed_mutex_try_lock(void *t)
{
    if (!mutex_try_lock(t))
        return 0;
    _Bool got = !TM_LOCKED(t);
    if (got)
        TM_LOCKED(t) = 1;
    mutex_unlock(t);
    return got;
}
static void timed_mutex_unlock(void *t)
{
    struct unique_lock lk;
    lock_of(&lk, t);
    TM_LOCKED(t) = 0;
    unlock_of(&lk);
    cv_notify_one(TM_CV(t));
}

/* ---- recursive_timed_mutex: {mutex; cv at 64; size_t count at 112; thread id at 120} */

#define RT_COUNT(t) (*(size_t *)((char *)(t) + 112))
#define RT_ID(t) (*(pthread_t *)((char *)(t) + 120))

static void rtm_ctor(void *t)
{
    mutex_init(t);
    cond_init(TM_CV(t));
    RT_COUNT(t) = 0;
    RT_ID(t) = 0;
}
static void rtm_dtor(void *t) { timed_mutex_dtor(t); }
static void rtm_lock(void *t)
{
    pthread_t me = t_self();
    struct unique_lock lk;
    lock_of(&lk, t);
    if (RT_ID(t) == me) {
        if (RT_COUNT(t) == SIZE_MAX) {
            unlock_of(&lk);
            throw_system_error(MAC_EAGAIN, "recursive_timed_mutex lock limit reached");
        }
        RT_COUNT(t)++;
        unlock_of(&lk);
        return;
    }
    while (RT_COUNT(t))
        cv_wait(TM_CV(t), &lk);
    RT_COUNT(t) = 1;
    RT_ID(t) = me;
    unlock_of(&lk);
}
static _Bool rtm_try_lock(void *t)
{
    pthread_t me = t_self();
    if (!mutex_try_lock(t))
        return 0;
    _Bool got = 0;
    if ((RT_COUNT(t) == 0 || RT_ID(t) == me) && RT_COUNT(t) != SIZE_MAX) {
        RT_COUNT(t)++;
        RT_ID(t) = me;
        got = 1;
    }
    mutex_unlock(t);
    return got;
}
static void rtm_unlock(void *t)
{
    struct unique_lock lk;
    lock_of(&lk, t);
    if (--RT_COUNT(t) == 0) {
        RT_ID(t) = 0;
        unlock_of(&lk);
        cv_notify_one(TM_CV(t));
    } else {
        unlock_of(&lk);
    }
}

/* ---- shared_timed_mutex and shared_mutex: {mutex; gate1 at 64; gate2 at 112;
 * unsigned state at 160}, a writer bit and a count of readers --------------------- */

#define SM_GATE1(s) ((char *)(s) + 64)
#define SM_GATE2(s) ((char *)(s) + 112)
#define SM_STATE(s) (*(unsigned *)((char *)(s) + 160))
#define WRITER (1U << (sizeof(unsigned) * CHAR_BIT - 1))
#define READERS (~WRITER)

static void sm_ctor(void *s)
{
    mutex_init(s);
    cond_init(SM_GATE1(s));
    cond_init(SM_GATE2(s));
    SM_STATE(s) = 0;
}
static void sm_lock(void *s)
{
    struct unique_lock lk;
    lock_of(&lk, s);
    while (SM_STATE(s) & WRITER)
        cv_wait(SM_GATE1(s), &lk);
    SM_STATE(s) |= WRITER;
    while (SM_STATE(s) & READERS)
        cv_wait(SM_GATE2(s), &lk);
    unlock_of(&lk);
}
static _Bool sm_try_lock(void *s)
{
    struct unique_lock lk;
    lock_of(&lk, s);
    _Bool got = SM_STATE(s) == 0;
    if (got)
        SM_STATE(s) = WRITER;
    unlock_of(&lk);
    return got;
}
static void sm_unlock(void *s)
{
    struct unique_lock lk;
    lock_of(&lk, s);
    SM_STATE(s) = 0;
    unlock_of(&lk);
    cv_notify_all(SM_GATE1(s));
}
static void sm_lock_shared(void *s)
{
    struct unique_lock lk;
    lock_of(&lk, s);
    while ((SM_STATE(s) & WRITER) || (SM_STATE(s) & READERS) == READERS)
        cv_wait(SM_GATE1(s), &lk);
    unsigned n = (SM_STATE(s) & READERS) + 1;
    SM_STATE(s) = (SM_STATE(s) & ~READERS) | n;
    unlock_of(&lk);
}
static _Bool sm_try_lock_shared(void *s)
{
    struct unique_lock lk;
    lock_of(&lk, s);
    unsigned n = SM_STATE(s) & READERS;
    _Bool got = !(SM_STATE(s) & WRITER) && n != READERS;
    if (got)
        SM_STATE(s) = (SM_STATE(s) & ~READERS) | (n + 1);
    unlock_of(&lk);
    return got;
}
static void sm_unlock_shared(void *s)
{
    struct unique_lock lk;
    lock_of(&lk, s);
    unsigned n = (SM_STATE(s) & READERS) - 1;
    SM_STATE(s) = (SM_STATE(s) & ~READERS) | n;
    int wake_writer = (SM_STATE(s) & WRITER) && n == 0;
    int wake_reader = !(SM_STATE(s) & WRITER) && n == READERS - 1;
    unlock_of(&lk);
    if (wake_writer)
        cv_notify_one(SM_GATE2(s));
    else if (wake_reader)
        cv_notify_one(SM_GATE1(s));
}

/* ---- std::thread: {pthread_t} ------------------------------------------------------ */

static void thread_join(pthread_t *t)
{
    int ec = MAC_EINVAL;
    if (*t) {
        ec = t_join(*t, NULL);
        if (!ec)
            *t = 0;
    }
    if (ec)
        throw_system_error(ec, "thread::join failed");
}
static void thread_detach(pthread_t *t)
{
    int ec = MAC_EINVAL;
    if (*t) {
        ec = t_detach(*t);
        if (!ec)
            *t = 0;
    }
    if (ec)
        throw_system_error(ec, "thread::detach failed");
}
static void thread_dtor(pthread_t *t)
{
    if (*t)
        terminate();
}

/* ---- future and promise: the shared state, {vptr; long owners at 8;
 * exception_ptr at 16; mutex at 24; condition_variable at 88; unsigned at 136} ---- */

struct state {
    void **vptr;
    long owners;          /* one less than the number of owners */
    void *exception;      /* exception_ptr */
    char mutex[MUTEX_SIZE];
    char cv[COND_SIZE];
    unsigned flags;
};
_Static_assert(__builtin_offsetof(struct state, mutex) == 24 && __builtin_offsetof(struct state, cv) == 88 &&
                   __builtin_offsetof(struct state, flags) == 136,
               "the Mac's __assoc_sub_state");
enum { CONSTRUCTED = 1, FUTURE_ATTACHED = 2, READY = 4, DEFERRED = 8 };
enum { ALREADY_RETRIEVED = 1, ALREADY_SATISFIED = 2, NO_STATE = 3, BROKEN_PROMISE = 4 };

/* the virtual calls: destructor, deleting destructor, __on_zero_shared, __execute */
#define VCALL(s, slot) ((void (*)(struct state *))(s)->vptr[slot])(s)

static void make_future_error(void *ex, int code)
{
    struct error_code ec = {code, future_category()};
    future_error_ctor(ex, ec);
}

__attribute__((noreturn)) static void throw_future_error(int code)
{
    void *ex = allocate_exception(32);   /* logic_error and an error_code */
    make_future_error(ex, code);
    cxa_throw(ex, future_error_typeinfo, future_error_dtor);
    __builtin_unreachable();
}

static void add_shared(struct state *s) { __atomic_add_fetch(&s->owners, 1, __ATOMIC_RELAXED); }
static void release_shared(struct state *s)
{
    if (__atomic_add_fetch(&s->owners, -1, __ATOMIC_ACQ_REL) == -1)
        VCALL(s, 2);
}
static _Bool has_value(struct state *s) { return (s->flags & CONSTRUCTED) || s->exception; }

static void state_dtor(struct state *s)
{
    cv_dtor(s->cv);
    mutex_dtor(s->mutex);
    eptr_dtor(&s->exception);
}
static void state_delete(struct state *s)
{
    state_dtor(s);
    free(s);
}
static void state_on_zero_shared(struct state *s) { VCALL(s, 1); }
static void state_execute(struct state *s) { throw_future_error(NO_STATE); }

static void *state_vtable[6];

static struct state *state_new(void)
{
    struct state *s = calloc(1, sizeof *s);
    if (!s)
        throw_system_error(12, "out of memory");
    s->vptr = &state_vtable[2];
    mutex_init(s->mutex);
    cond_init(s->cv);
    return s;
}

static void state_make_ready(struct state *s)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    s->flags |= READY;
    cv_notify_all(s->cv);
    unlock_of(&lk);
}

static void state_set_value(struct state *s)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    if (has_value(s)) {
        unlock_of(&lk);
        throw_future_error(ALREADY_SATISFIED);
    }
    s->flags |= CONSTRUCTED | READY;
    cv_notify_all(s->cv);
    unlock_of(&lk);
}

/* the exception_ptr comes by reference, as the C++ ABI passes one by value */
static void state_set_exception(struct state *s, void **p)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    if (has_value(s)) {
        unlock_of(&lk);
        throw_future_error(ALREADY_SATISFIED);
    }
    eptr_dtor(&s->exception);
    eptr_copy(&s->exception, p);
    s->flags |= READY;
    cv_notify_all(s->cv);
    unlock_of(&lk);
}

/* made ready when the thread that set it ends */
static pthread_key_t at_exit_key;
struct at_exit { struct state *s; struct at_exit *next; };

static void run_at_exit(void *p)
{
    for (struct at_exit *a = p, *next; a; a = next) {
        next = a->next;
        state_make_ready(a->s);
        release_shared(a->s);
        free(a);
    }
}

static void make_ready_at_thread_exit(struct state *s)
{
    struct at_exit *a = malloc(sizeof *a);
    if (!a)
        return;
    add_shared(s);
    a->s = s;
    a->next = pthread_getspecific(at_exit_key);
    pthread_setspecific(at_exit_key, a);
}

static void state_set_value_at_thread_exit(struct state *s)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    if (has_value(s)) {
        unlock_of(&lk);
        throw_future_error(ALREADY_SATISFIED);
    }
    s->flags |= CONSTRUCTED;
    make_ready_at_thread_exit(s);
    unlock_of(&lk);
}

static void state_set_exception_at_thread_exit(struct state *s, void **p)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    if (has_value(s)) {
        unlock_of(&lk);
        throw_future_error(ALREADY_SATISFIED);
    }
    eptr_dtor(&s->exception);
    eptr_copy(&s->exception, p);
    make_ready_at_thread_exit(s);
    unlock_of(&lk);
}

static void state_sub_wait(struct state *s, struct unique_lock *lk)
{
    if (s->flags & READY)
        return;
    if (s->flags & DEFERRED) {
        s->flags &= ~DEFERRED;
        unlock_of(lk);
        VCALL(s, 3);
    } else {
        while (!(s->flags & READY))
            cv_wait(s->cv, lk);
    }
}

static void state_wait(struct state *s)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    state_sub_wait(s, &lk);
    unlock_of(&lk);
}

/* waits, then throws what the state holds; release, if set, drops the
 * caller's share of the state first */
static void state_copy_releasing(struct state *s, int release)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    state_sub_wait(s, &lk);
    void *e = NULL;
    if (s->exception)
        eptr_copy(&e, &s->exception);
    unlock_of(&lk);
    if (release)
        release_shared(s);
    if (e)
        eptr_rethrow(&e);   /* (this copy is not released) */
}
static void state_copy(struct state *s) { state_copy_releasing(s, 0); }

static void attach_future(struct state *s)
{
    struct unique_lock lk;
    lock_of(&lk, s->mutex);
    if (s->flags & FUTURE_ATTACHED) {
        unlock_of(&lk);
        throw_future_error(ALREADY_RETRIEVED);
    }
    add_shared(s);
    s->flags |= FUTURE_ATTACHED;
    unlock_of(&lk);
}

/* future<void>, promise<void>, shared_future<void>: {state *} */
static void future_ctor(struct state **f, struct state *s)
{
    *f = s;
    attach_future(s);
}
static void future_dtor(struct state **f)
{
    if (*f)
        release_shared(*f);
}
static void future_get(struct state **f)
{
    struct state *s = *f;
    *f = NULL;
    state_copy_releasing(s, 1);
}

static void promise_ctor(struct state **p) { *p = state_new(); }
static void promise_dtor(struct state **p)
{
    struct state *s = *p;
    if (!s)
        return;
    if (!has_value(s) && s->owners > 0) {
        /* the future's owner learns that no value will come */
        void *ex = allocate_exception(32);
        make_future_error(ex, BROKEN_PROMISE);
        void *e = NULL;
        if (init_primary_exception) {
            init_primary_exception(ex, future_error_typeinfo, future_error_dtor);
            eptr_from_native(&e, ex);
            state_set_exception(s, &e);
            eptr_dtor(&e);
        } else {
            state_make_ready(s);
        }
    }
    release_shared(s);
}
static void promise_get_future(struct state **ret, struct state **p)
{
    if (!*p)
        throw_future_error(NO_STATE);
    future_ctor(ret, *p);
}
static void promise_set_value(struct state **p)
{
    if (!*p)
        throw_future_error(NO_STATE);
    state_set_value(*p);
}
static void promise_set_exception(struct state **p, void **e)
{
    if (!*p)
        throw_future_error(NO_STATE);
    state_set_exception(*p, e);
}
static void promise_set_value_at_thread_exit(struct state **p)
{
    if (!*p)
        throw_future_error(NO_STATE);
    state_set_value_at_thread_exit(*p);
}
static void promise_set_exception_at_thread_exit(struct state **p, void **e)
{
    if (!*p)
        throw_future_error(NO_STATE);
    state_set_exception_at_thread_exit(*p, e);
}
static struct state **shared_future_assign(struct state **f, struct state *const *other)
{
    if (*other)
        add_shared(*other);
    if (*f)
        release_shared(*f);
    *f = *other;
    return f;
}

/* ---- ctype<char>: {vptr; shared count; const mask *table at 16; bool} --------------- */

static void *ctype_id, *ctype_vtable, *ctype_byname_vtable;
static void *(*host_use_facet)(const void *, void *);
static const unsigned short *(*host_classic_table)(void);
static pthread_mutex_t facet_lock = PTHREAD_MUTEX_INITIALIZER;

/* this system's class bits, as the Mac's <ctype.h> numbers them */
static uint32_t *mac_table(const unsigned short *t)
{
    static struct { const unsigned short *from; uint32_t *to; } made[16];
    for (int i = 0; i < 16; i++)
        if (made[i].from == t)
            return made[i].to;
    uint32_t *to = calloc(256, sizeof *to);
    for (int c = 0; c < 256 && to; c++) {
        unsigned short b = t[c];
        uint32_t m = 0;
        if (b & _ISalpha) m |= 0x100;
        if (b & _IScntrl) m |= 0x200;
        if (b & _ISdigit) m |= 0x400 | (c >= '0' && c <= '9' ? (uint32_t)(c - '0') : 0);
        if (b & _ISgraph) m |= 0x800;
        if (b & _ISlower) m |= 0x1000;
        if (b & _ISpunct) m |= 0x2000;
        if (b & _ISspace) m |= 0x4000;
        if (b & _ISupper) m |= 0x8000;
        if (b & _ISxdigit) m |= 0x10000;
        if (b & _ISblank) m |= 0x20000;
        if (b & _ISprint) m |= 0x40000;
        to[c] = m;
    }
    for (int i = 0; i < 16; i++)
        if (!made[i].from) {
            made[i].from = t;
            made[i].to = to;
            break;
        }
    return to;
}

static const uint32_t *ctype_classic_table(void) { return mac_table(host_classic_table()); }

static const void *use_facet(const void *loc, void *id)
{
    void *f = host_use_facet(loc, id);
    if (id != ctype_id || !f)
        return f;
    void *vptr = *(void **)f;
    if (vptr != (char *)ctype_vtable + 16 && vptr != (char *)ctype_byname_vtable + 16)
        return f;   /* the program's own ctype<char>, with its own table */
    static struct { void *from, *to; } shadows[64];
    pthread_mutex_lock(&facet_lock);
    void *to = NULL;
    for (int i = 0; i < 64 && !to; i++)
        if (shadows[i].from == f)
            to = shadows[i].to;
    if (!to) {
        /* a copy whose table is the Mac's: the program reads the table
         * itself and calls the rest through the same virtual functions */
        const unsigned short *tab = *(const unsigned short **)((char *)f + 16);
        to = malloc(32);
        if (to && tab) {
            memcpy(to, f, 32);
            *(uint32_t **)((char *)to + 16) = mac_table(tab);
            *(_Bool *)((char *)to + 24) = 0;
            for (int i = 0; i < 64; i++)
                if (!shadows[i].from) {
                    shadows[i].from = f;
                    shadows[i].to = to;
                    break;
                }
        } else {
            free(to);
            to = f;
        }
    }
    pthread_mutex_unlock(&facet_lock);
    return to;
}

/* ---- stream positions: fpos<mbstate_t> is {mbstate_t (128 bytes); long long} on a
 * Mac and {8 bytes; long long} here ------------------------------------------------ */

struct mac_fpos { unsigned char state[128]; long long off; };
struct host_fpos { uint64_t state; long long off; };

static struct host_fpos (*host_tellg_c)(void *), (*host_tellg_w)(void *);
static struct host_fpos (*host_tellp_c)(void *), (*host_tellp_w)(void *);
static void *(*host_seekg_c)(void *, struct host_fpos), *(*host_seekg_w)(void *, struct host_fpos);
static void *(*host_seekp_c)(void *, struct host_fpos), *(*host_seekp_w)(void *, struct host_fpos);
static struct host_fpos (*host_pubseekpos_c)(void *, struct host_fpos, unsigned);
static struct host_fpos (*host_pubseekpos_w)(void *, struct host_fpos, unsigned);

static void to_mac(struct mac_fpos *m, struct host_fpos h)
{
    memset(m->state, 0, sizeof m->state);
    memcpy(m->state, &h.state, sizeof h.state);
    m->off = h.off;
}
static struct host_fpos to_host(const struct mac_fpos *m)
{
    struct host_fpos h;
    memcpy(&h.state, m->state, sizeof h.state);
    h.off = m->off;
    return h;
}

/* A stream buffer's seekoff(off, way, which) and seekpos(pos, which), called
 * the Mac's way (the position returned in memory, its address first) or this
 * system's (returned in two registers). A seekoff called this system's way has
 * the open mode (in 8, out 16) fourth, the Mac's way the direction (0-2); a
 * seekpos called this system's way has the position's 8-byte state second,
 * which is 0 for the byte streams, the Mac's way the buffer. */
enum { NSEEK = 5 };
static const char *const seekoff_names[NSEEK] = {
    "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj",
    "_ZNSt3__115basic_streambufIwNS_11char_traitsIwEEE7seekoffExNS_8ios_base7seekdirEj",
    "_ZNSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE7seekoffExNS_8ios_base7seekdirEj",
    "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj",
    "_ZNSt3__112strstreambuf7seekoffExNS_8ios_base7seekdirEj",
};
static const char *const seekpos_names[NSEEK] = {
    "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj",
    "_ZNSt3__115basic_streambufIwNS_11char_traitsIwEEE7seekposENS_4fposI11__mbstate_tEEj",
    NULL,
    "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj",
    "_ZNSt3__112strstreambuf7seekposENS_4fposI11__mbstate_tEEj",
};
static struct host_fpos (*host_seekoff[NSEEK])(void *, long long, int, unsigned);
static struct host_fpos (*host_seekpos[NSEEK])(void *, struct host_fpos, unsigned);

static int is_direction(long v) { return (unsigned)v <= 2; }
static int is_mode(long v) { return (unsigned)v && !((unsigned)v & ~0x3fu) && ((unsigned)v & (8 | 16)); }

static struct host_fpos seekoff_any(int i, long a, long b, long c, long d, long e)
{
    if (!is_direction(d))   /* this system's way: (buffer, off, way, which) */
        return host_seekoff[i]((void *)a, b, (int)c, (unsigned)d);
    struct host_fpos r = host_seekoff[i]((void *)b, c, (int)d, (unsigned)e);
    to_mac((struct mac_fpos *)a, r);
    return (struct host_fpos){(uint64_t)a, 0};
}
static struct host_fpos seekpos_any(int i, long a, long b, long c, long d, const struct mac_fpos *pos)
{
    if (!b || !is_mode(c)) {   /* this system's way: (buffer, state, off, which) */
        struct host_fpos p = {(uint64_t)b, c};
        return host_seekpos[i]((void *)a, p, (unsigned)d);
    }
    struct host_fpos r = host_seekpos[i]((void *)b, to_host(pos), (unsigned)c);
    to_mac((struct mac_fpos *)a, r);
    return (struct host_fpos){(uint64_t)a, 0};
}
#define SEEKERS(i)                                                                                             \
    static struct host_fpos seekoff_##i(long a, long b, long c, long d, long e)                                \
    {                                                                                                          \
        return seekoff_any(i, a, b, c, d, e);                                                                  \
    }                                                                                                          \
    __attribute__((unused)) static struct host_fpos seekpos_##i(long a, long b, long c, long d, long e, long f, \
                                                                struct mac_fpos pos)                           \
    {                                                                                                          \
        (void)e, (void)f;                                                                                      \
        return seekpos_any(i, a, b, c, d, &pos);                                                               \
    }
SEEKERS(0)
SEEKERS(1)
SEEKERS(2)
SEEKERS(3)
SEEKERS(4)
static void *const seekoff_fns[NSEEK] = {seekoff_0, seekoff_1, seekoff_2, seekoff_3, seekoff_4};
static void *const seekpos_fns[NSEEK] = {seekpos_0, seekpos_1, NULL, seekpos_3, seekpos_4};

/* A Mac library can hold its own copies of stream buffers' seekoff and
 * seekpos (libc++'s templates made in the library, or its own stream
 * buffers), and its virtual tables point at them. This system's libc++
 * calls those through the tables its own way (pubseekoff from seekg, for
 * one), so those slots get calls that tell the two ways apart too and
 * then call the library's copy the Mac's way (freemac Blender work:
 * OpenColorIO reads its files so). */
enum { NMACSEEK = 96 };
/* slot k's calls are numbered (k / 8 + 1) * 10 + k % 8, 10 to 127 */
#define SLOT_NUMBER(k) (((k) / 8 + 1) * 10 + (k) % 8)
static struct mac_fpos (*mac_seekoff_fn[128])(void *, long long, int, unsigned);
static struct mac_fpos (*mac_seekpos_fn[128])(void *, struct mac_fpos, unsigned);
static int nmac_seekoff, nmac_seekpos;
static pthread_mutex_t mac_seek_lock = PTHREAD_MUTEX_INITIALIZER;

static struct host_fpos mac_seekoff_any(int i, long a, long b, long c, long d, long e)
{
    if (!is_direction(d)) { /* this system's way: (buffer, off, way, which) */
        struct mac_fpos r = mac_seekoff_fn[i]((void *)a, b, (int)c, (unsigned)d);
        return to_host(&r);
    }
    *(struct mac_fpos *)a = mac_seekoff_fn[i]((void *)b, c, (int)d, (unsigned)e);
    return (struct host_fpos){(uint64_t)a, 0};
}
static struct host_fpos mac_seekpos_any(int i, long a, long b, long c, long d, const struct mac_fpos *pos)
{
    if (!b || !is_mode(c)) { /* this system's way: (buffer, state, off, which) */
        struct mac_fpos p;
        to_mac(&p, (struct host_fpos){(uint64_t)b, c});
        struct mac_fpos r = mac_seekpos_fn[i]((void *)a, p, (unsigned)d);
        return to_host(&r);
    }
    *(struct mac_fpos *)a = mac_seekpos_fn[i]((void *)b, *pos, (unsigned)c);
    return (struct host_fpos){(uint64_t)a, 0};
}
#define MAC_SEEKERS(i)                                                                                         \
    static struct host_fpos mac_seekoff_##i(long a, long b, long c, long d, long e)                            \
    {                                                                                                          \
        return mac_seekoff_any(i, a, b, c, d, e);                                                              \
    }                                                                                                          \
    static struct host_fpos mac_seekpos_##i(long a, long b, long c, long d, long e, long f, struct mac_fpos pos) \
    {                                                                                                          \
        (void)e, (void)f;                                                                                      \
        return mac_seekpos_any(i, a, b, c, d, &pos);                                                           \
    }
#define MAC_SEEKERS8(i) MAC_SEEKERS(i##0) MAC_SEEKERS(i##1) MAC_SEEKERS(i##2) MAC_SEEKERS(i##3) \
                        MAC_SEEKERS(i##4) MAC_SEEKERS(i##5) MAC_SEEKERS(i##6) MAC_SEEKERS(i##7)
MAC_SEEKERS8(1) MAC_SEEKERS8(2) MAC_SEEKERS8(3) MAC_SEEKERS8(4) MAC_SEEKERS8(5) MAC_SEEKERS8(6)
MAC_SEEKERS8(7) MAC_SEEKERS8(8) MAC_SEEKERS8(9) MAC_SEEKERS8(10) MAC_SEEKERS8(11) MAC_SEEKERS8(12)
#define MAC_SLOTS8(f, i) f##i##0, f##i##1, f##i##2, f##i##3, f##i##4, f##i##5, f##i##6, f##i##7
static void *const mac_seekoff_slots[NMACSEEK] = {
    MAC_SLOTS8(mac_seekoff_, 1), MAC_SLOTS8(mac_seekoff_, 2),  MAC_SLOTS8(mac_seekoff_, 3),
    MAC_SLOTS8(mac_seekoff_, 4), MAC_SLOTS8(mac_seekoff_, 5),  MAC_SLOTS8(mac_seekoff_, 6),
    MAC_SLOTS8(mac_seekoff_, 7), MAC_SLOTS8(mac_seekoff_, 8),  MAC_SLOTS8(mac_seekoff_, 9),
    MAC_SLOTS8(mac_seekoff_, 10), MAC_SLOTS8(mac_seekoff_, 11), MAC_SLOTS8(mac_seekoff_, 12),
};
static void *const mac_seekpos_slots[NMACSEEK] = {
    MAC_SLOTS8(mac_seekpos_, 1), MAC_SLOTS8(mac_seekpos_, 2),  MAC_SLOTS8(mac_seekpos_, 3),
    MAC_SLOTS8(mac_seekpos_, 4), MAC_SLOTS8(mac_seekpos_, 5),  MAC_SLOTS8(mac_seekpos_, 6),
    MAC_SLOTS8(mac_seekpos_, 7), MAC_SLOTS8(mac_seekpos_, 8),  MAC_SLOTS8(mac_seekpos_, 9),
    MAC_SLOTS8(mac_seekpos_, 10), MAC_SLOTS8(mac_seekpos_, 11), MAC_SLOTS8(mac_seekpos_, 12),
};

static int ends_with(const char *s, const char *tail)
{
    size_t n = strlen(s), m = strlen(tail);
    return n >= m && !memcmp(s + n - m, tail, m);
}

struct seek_scan {
    uintptr_t pairs[2 * NMACSEEK][2];
    int n;
};

static void find_mac_seek(const char *name, void *addr, void *ctx)
{
    struct seek_scan *scan = ctx;
    int off = ends_with(name, "7seekoffExNS_8ios_base7seekdirEj");
    if (!off && !ends_with(name, "7seekposENS_4fposI11__mbstate_tEEj"))
        return;
    if (strncmp(name, "__ZN", 4) || scan->n >= 2 * NMACSEEK)
        return;
    for (int i = 0; i < scan->n; i++)
        if (scan->pairs[i][0] == (uintptr_t)addr)
            return;
    void *slot;
    if (off) {
        for (int i = 0; i < nmac_seekoff; i++)
            if ((void *)mac_seekoff_fn[SLOT_NUMBER(i)] == addr) {
                slot = mac_seekoff_slots[i];
                goto found;
            }
        if (nmac_seekoff == NMACSEEK) {
            fprintf(stderr, "ferry: too many C++ stream buffers to convert; %s is left as it is\n", name);
            return;
        }
        *(void **)&mac_seekoff_fn[SLOT_NUMBER(nmac_seekoff)] = addr;
        slot = mac_seekoff_slots[nmac_seekoff++];
    } else {
        for (int i = 0; i < nmac_seekpos; i++)
            if ((void *)mac_seekpos_fn[SLOT_NUMBER(i)] == addr) {
                slot = mac_seekpos_slots[i];
                goto found;
            }
        if (nmac_seekpos == NMACSEEK) {
            fprintf(stderr, "ferry: too many C++ stream buffers to convert; %s is left as it is\n", name);
            return;
        }
        *(void **)&mac_seekpos_fn[SLOT_NUMBER(nmac_seekpos)] = addr;
        slot = mac_seekpos_slots[nmac_seekpos++];
    }
found:
    scan->pairs[scan->n][0] = (uintptr_t)addr;
    scan->pairs[scan->n][1] = (uintptr_t)slot;
    scan->n++;
}

void ferry_cxx_wrap_image_seeks(struct image *im)
{
    static struct seek_scan scan;
    pthread_mutex_lock(&mac_seek_lock);
    scan.n = 0;
    ferry_image_each_symbol(im, find_mac_seek, &scan);
    int replaced = scan.n ? ferry_image_replace_pointers(im, scan.pairs, scan.n) : 0;
    pthread_mutex_unlock(&mac_seek_lock);
    if (ferry_verbose && scan.n)
        fprintf(stderr, "ferry: %d stream buffer calls of %s take positions both ways (%d table slots)\n", scan.n,
                ferry_image_path(im), replaced);
}

/* The library's own virtual tables (and its pointers to these calls) are in
 * its read-only-after-start data: point them at the calls above. */
static int relro_of(struct dl_phdr_info *info, size_t size, void *data)
{
    uintptr_t *range = data;
    if (info->dlpi_addr != range[0])
        return 0;
    for (int i = 0; i < info->dlpi_phnum; i++)
        if (info->dlpi_phdr[i].p_type == PT_GNU_RELRO) {
            range[1] = info->dlpi_addr + info->dlpi_phdr[i].p_vaddr;
            range[2] = range[1] + info->dlpi_phdr[i].p_memsz;
        }
    return 1;
}

static void redirect_seeks(void)
{
    Dl_info info;
    if (!host_seekoff[0] || !dladdr((void *)host_seekoff[0], &info))
        return;
    uintptr_t range[3] = {(uintptr_t)info.dli_fbase, 0, 0};
    dl_iterate_phdr(relro_of, range);
    if (!range[1])
        return;
    uintptr_t start = range[1] & ~(uintptr_t)4095, end = (range[2] + 4095) & ~(uintptr_t)4095;
    if (mprotect((void *)start, end - start, PROT_READ | PROT_WRITE))
        return;
    int n = 0;
    for (void **w = (void **)((range[1] + 7) & ~(uintptr_t)7); (uintptr_t)(w + 1) <= range[2]; w++)
        for (int i = 0; i < NSEEK; i++) {
            if (host_seekoff[i] && *w == (void *)host_seekoff[i])
                *w = seekoff_fns[i], n++;
            else if (host_seekpos[i] && *w == (void *)host_seekpos[i])
                *w = seekpos_fns[i], n++;
        }
    mprotect((void *)start, end - start, PROT_READ);
    if (ferry_verbose)
        fprintf(stderr, "ferry: %d of this system's libc++'s stream buffer slots take Mac stream positions\n", n);
}

static void tellg_c(struct mac_fpos *r, void *s) { to_mac(r, host_tellg_c(s)); }
static void tellg_w(struct mac_fpos *r, void *s) { to_mac(r, host_tellg_w(s)); }
static void tellp_c(struct mac_fpos *r, void *s) { to_mac(r, host_tellp_c(s)); }
static void tellp_w(struct mac_fpos *r, void *s) { to_mac(r, host_tellp_w(s)); }
static void *seekg_c(void *s, struct mac_fpos p) { return host_seekg_c(s, to_host(&p)); }
static void *seekg_w(void *s, struct mac_fpos p) { return host_seekg_w(s, to_host(&p)); }
static void *seekp_c(void *s, struct mac_fpos p) { return host_seekp_c(s, to_host(&p)); }
static void *seekp_w(void *s, struct mac_fpos p) { return host_seekp_w(s, to_host(&p)); }
static void pubseekpos_c(struct mac_fpos *r, void *b, struct mac_fpos p, unsigned which)
{
    to_mac(r, host_pubseekpos_c(b, to_host(&p), which));
}
static void pubseekpos_w(struct mac_fpos *r, void *b, struct mac_fpos p, unsigned which)
{
    to_mac(r, host_pubseekpos_w(b, to_host(&p), which));
}

/* ---- ifstream and ofstream: {basic_istream or basic_ostream; basic_filebuf<char>;
 * the virtual base basic_ios}. A Mac's filebuf is larger by two mbstate_t, so the
 * virtual base is further on: the tables that give its place (the virtual table,
 * the construction table and the VTT) are copied with the Mac's offset, and the
 * destructors reached through them destroy the Mac's layout. ------------------ */

#define FILEBUF_GROWTH (2 * (128 - 8))

struct fstream_class {
    const char *vtable, *vtt, *ctor_vtable, *base_d2;
    long buf;                 /* where the filebuf is */
    long host_vbase, mac_vbase;
    void *vt[16], *ctc[16], *tt[8];
    void (*base_dtor)(void *, void **);
};
static struct fstream_class ifstream_class = {
    "_ZTVNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEE", "_ZTTNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEE",
    "_ZTCNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEE0_NS_13basic_istreamIcS2_EE",
    "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED2Ev", 16, 0, 0, {0}, {0}, {0}, NULL,
};
static struct fstream_class ofstream_class = {
    "_ZTVNSt3__114basic_ofstreamIcNS_11char_traitsIcEEEE", "_ZTTNSt3__114basic_ofstreamIcNS_11char_traitsIcEEEE",
    "_ZTCNSt3__114basic_ofstreamIcNS_11char_traitsIcEEEE0_NS_13basic_ostreamIcS2_EE",
    "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEED2Ev", 8, 0, 0, {0}, {0}, {0}, NULL,
};
static void (*filebuf_dtor)(void *), (*basic_ios_dtor)(void *), (*operator_delete)(void *);

static void fstream_destroy(struct fstream_class *k, void *self)
{
    filebuf_dtor((char *)self + k->buf);
    k->base_dtor(self, &k->tt[1]);
    basic_ios_dtor((char *)self + k->mac_vbase);
}
static void ifstream_d1(void *self) { fstream_destroy(&ifstream_class, self); }
static void ifstream_d0(void *self) { ifstream_d1(self); operator_delete(self); }
static void ifstream_ios_d1(void *ios) { ifstream_d1((char *)ios - ifstream_class.mac_vbase); }
static void ifstream_ios_d0(void *ios) { ifstream_d0((char *)ios - ifstream_class.mac_vbase); }
static void ofstream_d1(void *self) { fstream_destroy(&ofstream_class, self); }
static void ofstream_d0(void *self) { ofstream_d1(self); operator_delete(self); }
static void ofstream_ios_d1(void *ios) { ofstream_d1((char *)ios - ofstream_class.mac_vbase); }
static void ofstream_ios_d0(void *ios) { ofstream_d0((char *)ios - ofstream_class.mac_vbase); }

static size_t symbol_size(void *addr)
{
    Dl_info info;
    ElfW(Sym) *sym = NULL;
    if (!dladdr1(addr, &info, (void **)&sym, RTLD_DL_SYMENT) || !sym)
        return 0;
    return sym->st_size;
}

/* copies a table, with the Mac's offset to the virtual base in place of this system's */
static int copy_table(void **to, size_t cap, void *from, size_t size, long host, long mac)
{
    size_t n = size / sizeof(void *);
    if (!from || !n || n > cap)
        return 0;
    memcpy(to, from, size);
    for (size_t i = 0; i < n; i++) {
        if ((long)to[i] == host)
            to[i] = (void *)mac;
        else if ((long)to[i] == -host)
            to[i] = (void *)-mac;
    }
    return 1;
}

static int make_fstream_class(struct fstream_class *k, void *d1, void *d0, void *ios_d1, void *ios_d0)
{
    void **vt = ferry_cxx_symbol(k->vtable), **tt = ferry_cxx_symbol(k->vtt);
    void **ctc = ferry_cxx_symbol(k->ctor_vtable);
    *(void **)&k->base_dtor = ferry_cxx_symbol(k->base_d2);
    size_t vts = vt ? symbol_size(vt) : 0, tts = tt ? symbol_size(tt) : 0, ctcs = ctc ? symbol_size(ctc) : 0;
    /* the layout this file expects: {vbase offset, 0, typeinfo, D1, D0} and the
     * virtual base's {vcall offset, offset to top, typeinfo, D1, D0} */
    if (!k->base_dtor || vts != 10 * sizeof(void *) || !tts || tts > sizeof k->tt || (long)vt[1] != 0 ||
        (long)vt[6] != -(long)vt[0])
        return 0;
    k->host_vbase = (long)vt[0];
    k->mac_vbase = k->host_vbase + FILEBUF_GROWTH;
    if (!copy_table(k->vt, 16, vt, vts, k->host_vbase, k->mac_vbase) ||
        !copy_table(k->ctc, 16, ctc, ctcs, k->host_vbase, k->mac_vbase))
        return 0;
    k->vt[3] = d1, k->vt[4] = d0, k->vt[8] = ios_d1, k->vt[9] = ios_d0;
    for (size_t i = 0; i < tts / sizeof(void *); i++) {
        char *p = tt[i];
        if (p >= (char *)vt && p < (char *)vt + vts)
            k->tt[i] = (char *)k->vt + (p - (char *)vt);
        else if (p >= (char *)ctc && p < (char *)ctc + ctcs)
            k->tt[i] = (char *)k->ctc + (p - (char *)ctc);
        else
            k->tt[i] = p;
    }
    return 1;
}

static int fstreams_ready;

/* the tables in the Mac's form, for the names a program imports */
void *ferry_cxx_layout_table(const char *name)
{
    if (!fstreams_ready)
        return NULL;
    struct fstream_class *ks[] = {&ifstream_class, &ofstream_class};
    for (int i = 0; i < 2; i++) {
        if (!strcmp(name, ks[i]->vtable))
            return ks[i]->vt;
        if (!strcmp(name, ks[i]->vtt))
            return ks[i]->tt;
        if (!strcmp(name, ks[i]->ctor_vtable))
            return ks[i]->ctc;
    }
    return NULL;
}

/* ---- the table ---------------------------------------------------------------------- */

#define S(name, fn) {name, (void *)fn}
#define BOTH(stem, fn) S(stem "C1Ev", fn), S(stem "C2Ev", fn)
#define DTORS(stem, fn) S(stem "D1Ev", fn), S(stem "D2Ev", fn)

const struct ferry_symbol ferry_cxx_overrides[] = {
    /* std::mutex */
    S("_ZNSt3__15mutex4lockEv", mutex_lock), S("_ZNSt3__15mutex6unlockEv", mutex_unlock),
    S("_ZNSt3__15mutex8try_lockEv", mutex_try_lock), DTORS("_ZNSt3__15mutex", mutex_dtor),
    /* std::condition_variable */
    S("_ZNSt3__118condition_variable10notify_oneEv", cv_notify_one),
    S("_ZNSt3__118condition_variable10notify_allEv", cv_notify_all),
    S("_ZNSt3__118condition_variable4waitERNS_11unique_lockINS_5mutexEEE", cv_wait),
    S("_ZNSt3__118condition_variable15__do_timed_waitERNS_11unique_lockINS_5mutexEEENS_6chrono10time_pointINS5_"
      "12system_clockENS5_8durationIxNS_5ratioILl1ELl1000000000EEEEEEE",
      cv_timed_wait),
    DTORS("_ZNSt3__118condition_variable", cv_dtor),
    /* std::timed_mutex */
    BOTH("_ZNSt3__111timed_mutex", timed_mutex_ctor), DTORS("_ZNSt3__111timed_mutex", timed_mutex_dtor),
    S("_ZNSt3__111timed_mutex4lockEv", timed_mutex_lock), S("_ZNSt3__111timed_mutex6unlockEv", timed_mutex_unlock),
    S("_ZNSt3__111timed_mutex8try_lockEv", timed_mutex_try_lock),
    /* std::recursive_timed_mutex */
    BOTH("_ZNSt3__121recursive_timed_mutex", rtm_ctor), DTORS("_ZNSt3__121recursive_timed_mutex", rtm_dtor),
    S("_ZNSt3__121recursive_timed_mutex4lockEv", rtm_lock), S("_ZNSt3__121recursive_timed_mutex6unlockEv", rtm_unlock),
    S("_ZNSt3__121recursive_timed_mutex8try_lockEv", rtm_try_lock),
    /* std::shared_mutex's base, and std::shared_timed_mutex */
    BOTH("_ZNSt3__119__shared_mutex_base", sm_ctor), BOTH("_ZNSt3__118shared_timed_mutex", sm_ctor),
    S("_ZNSt3__119__shared_mutex_base4lockEv", sm_lock), S("_ZNSt3__118shared_timed_mutex4lockEv", sm_lock),
    S("_ZNSt3__119__shared_mutex_base6unlockEv", sm_unlock), S("_ZNSt3__118shared_timed_mutex6unlockEv", sm_unlock),
    S("_ZNSt3__119__shared_mutex_base8try_lockEv", sm_try_lock),
    S("_ZNSt3__118shared_timed_mutex8try_lockEv", sm_try_lock),
    S("_ZNSt3__119__shared_mutex_base11lock_sharedEv", sm_lock_shared),
    S("_ZNSt3__118shared_timed_mutex11lock_sharedEv", sm_lock_shared),
    S("_ZNSt3__119__shared_mutex_base13unlock_sharedEv", sm_unlock_shared),
    S("_ZNSt3__118shared_timed_mutex13unlock_sharedEv", sm_unlock_shared),
    S("_ZNSt3__119__shared_mutex_base15try_lock_sharedEv", sm_try_lock_shared),
    S("_ZNSt3__118shared_timed_mutex15try_lock_sharedEv", sm_try_lock_shared),
    /* std::thread */
    S("_ZNSt3__16thread4joinEv", thread_join), S("_ZNSt3__16thread6detachEv", thread_detach),
    DTORS("_ZNSt3__16thread", thread_dtor),
    /* std::future, std::promise and their shared state */
    S("_ZNSt3__117__assoc_sub_state10__sub_waitERNS_11unique_lockINS_5mutexEEE", state_sub_wait),
    S("_ZNSt3__117__assoc_sub_state12__make_readyEv", state_make_ready),
    S("_ZNSt3__117__assoc_sub_state13set_exceptionESt13exception_ptr", state_set_exception),
    S("_ZNSt3__117__assoc_sub_state16__on_zero_sharedEv", state_on_zero_shared),
    S("_ZNSt3__117__assoc_sub_state24set_value_at_thread_exitEv", state_set_value_at_thread_exit),
    S("_ZNSt3__117__assoc_sub_state28set_exception_at_thread_exitESt13exception_ptr",
      state_set_exception_at_thread_exit),
    S("_ZNSt3__117__assoc_sub_state4copyEv", state_copy), S("_ZNSt3__117__assoc_sub_state4waitEv", state_wait),
    S("_ZNSt3__117__assoc_sub_state9__executeEv", state_execute),
    S("_ZNSt3__117__assoc_sub_state9set_valueEv", state_set_value),
    S("_ZNSt3__16futureIvEC1EPNS_17__assoc_sub_stateE", future_ctor),
    S("_ZNSt3__16futureIvEC2EPNS_17__assoc_sub_stateE", future_ctor),
    S("_ZNSt3__16futureIvE3getEv", future_get),
    S("_ZNSt3__16futureIvED1Ev", future_dtor), S("_ZNSt3__16futureIvED2Ev", future_dtor),
    BOTH("_ZNSt3__17promiseIvE", promise_ctor), DTORS("_ZNSt3__17promiseIvE", promise_dtor),
    S("_ZNSt3__17promiseIvE10get_futureEv", promise_get_future),
    S("_ZNSt3__17promiseIvE9set_valueEv", promise_set_value),
    S("_ZNSt3__17promiseIvE13set_exceptionESt13exception_ptr", promise_set_exception),
    S("_ZNSt3__17promiseIvE24set_value_at_thread_exitEv", promise_set_value_at_thread_exit),
    S("_ZNSt3__17promiseIvE28set_exception_at_thread_exitESt13exception_ptr", promise_set_exception_at_thread_exit),
    DTORS("_ZNSt3__113shared_futureIvE", future_dtor),
    S("_ZNSt3__113shared_futureIvEaSERKS1_", shared_future_assign),
    /* std::ctype<char>'s table */
    S("_ZNKSt3__16locale9use_facetERNS0_2idE", use_facet),
    S("_ZNSt3__15ctypeIcE13classic_tableEv", ctype_classic_table),
    /* stream positions */
    S("_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5tellgEv", tellg_c),
    S("_ZNSt3__113basic_istreamIwNS_11char_traitsIwEEE5tellgEv", tellg_w),
    S("_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE5tellpEv", tellp_c),
    S("_ZNSt3__113basic_ostreamIwNS_11char_traitsIwEEE5tellpEv", tellp_w),
    S("_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgENS_4fposI11__mbstate_tEE", seekg_c),
    S("_ZNSt3__113basic_istreamIwNS_11char_traitsIwEEE5seekgENS_4fposI11__mbstate_tEE", seekg_w),
    S("_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE5seekpENS_4fposI11__mbstate_tEE", seekp_c),
    S("_ZNSt3__113basic_ostreamIwNS_11char_traitsIwEEE5seekpENS_4fposI11__mbstate_tEE", seekp_w),
    S("_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE10pubseekposENS_4fposI11__mbstate_tEEj", pubseekpos_c),
    S("_ZNSt3__115basic_streambufIwNS_11char_traitsIwEEE10pubseekposENS_4fposI11__mbstate_tEEj", pubseekpos_w),
    /* the stream buffers' seekoff and seekpos, as a Mac program's own buffers inherit them */
    S("_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj", seekoff_0),
    S("_ZNSt3__115basic_streambufIwNS_11char_traitsIwEEE7seekoffExNS_8ios_base7seekdirEj", seekoff_1),
    S("_ZNSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE7seekoffExNS_8ios_base7seekdirEj",
      seekoff_2),
    S("_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj", seekoff_3),
    S("_ZNSt3__112strstreambuf7seekoffExNS_8ios_base7seekdirEj", seekoff_4),
    S("_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj", seekpos_0),
    S("_ZNSt3__115basic_streambufIwNS_11char_traitsIwEEE7seekposENS_4fposI11__mbstate_tEEj", seekpos_1),
    S("_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj", seekpos_3),
    S("_ZNSt3__112strstreambuf7seekposENS_4fposI11__mbstate_tEEj", seekpos_4),
    {NULL, NULL},
};

#define GET(var, name)                                                                                         \
    do {                                                                                                       \
        *(void **)&(var) = ferry_cxx_symbol(name);                                                             \
        if (!(var))                                                                                            \
            missing = name;                                                                                    \
    } while (0)

void ferry_cxx_threads_init(void)
{
    const char *missing = NULL;
    *(void **)&m_lock = ferry_lookup("pthread_mutex_lock");
    *(void **)&m_trylock = ferry_lookup("pthread_mutex_trylock");
    *(void **)&m_unlock = ferry_lookup("pthread_mutex_unlock");
    *(void **)&m_destroy = ferry_lookup("pthread_mutex_destroy");
    *(void **)&c_wait = ferry_lookup("pthread_cond_wait");
    *(void **)&c_timedwait = ferry_lookup("pthread_cond_timedwait");
    *(void **)&c_signal = ferry_lookup("pthread_cond_signal");
    *(void **)&c_broadcast = ferry_lookup("pthread_cond_broadcast");
    *(void **)&c_destroy = ferry_lookup("pthread_cond_destroy");
    *(void **)&t_join = ferry_lookup("pthread_join");
    *(void **)&t_detach = ferry_lookup("pthread_detach");
    *(void **)&t_self = ferry_lookup("pthread_self");
    GET(throw_system_error, "_ZNSt3__120__throw_system_errorEiPKc");
    GET(allocate_exception, "__cxa_allocate_exception");
    GET(cxa_throw, "__cxa_throw");
    *(void **)&init_primary_exception = ferry_cxx_symbol("__cxa_init_primary_exception");
    GET(future_category, "_ZNSt3__115future_categoryEv");
    GET(future_error_ctor, "_ZNSt3__112future_errorC1ENS_10error_codeE");
    GET(future_error_dtor, "_ZNSt3__112future_errorD1Ev");
    GET(future_error_typeinfo, "_ZTINSt3__112future_errorE");
    GET(assoc_typeinfo, "_ZTINSt3__117__assoc_sub_stateE");
    GET(eptr_copy, "_ZNSt13exception_ptrC1ERKS_");
    GET(eptr_dtor, "_ZNSt13exception_ptrD1Ev");
    GET(eptr_rethrow, "_ZSt17rethrow_exceptionSt13exception_ptr");
    GET(eptr_from_native, "_ZNSt13exception_ptr31__from_native_exception_pointerEPv");
    GET(terminate, "_ZSt9terminatev");
    GET(ctype_id, "_ZNSt3__15ctypeIcE2idE");
    GET(ctype_vtable, "_ZTVNSt3__15ctypeIcEE");
    GET(ctype_byname_vtable, "_ZTVNSt3__112ctype_bynameIcEE");
    GET(host_use_facet, "_ZNKSt3__16locale9use_facetERNS0_2idE");
    GET(host_classic_table, "_ZNSt3__15ctypeIcE13classic_tableEv");
    GET(host_tellg_c, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5tellgEv");
    GET(host_tellg_w, "_ZNSt3__113basic_istreamIwNS_11char_traitsIwEEE5tellgEv");
    GET(host_tellp_c, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE5tellpEv");
    GET(host_tellp_w, "_ZNSt3__113basic_ostreamIwNS_11char_traitsIwEEE5tellpEv");
    GET(host_seekg_c, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgENS_4fposI11__mbstate_tEE");
    GET(host_seekg_w, "_ZNSt3__113basic_istreamIwNS_11char_traitsIwEEE5seekgENS_4fposI11__mbstate_tEE");
    GET(host_seekp_c, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE5seekpENS_4fposI11__mbstate_tEE");
    GET(host_seekp_w, "_ZNSt3__113basic_ostreamIwNS_11char_traitsIwEEE5seekpENS_4fposI11__mbstate_tEE");
    GET(host_pubseekpos_c, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE10pubseekposENS_4fposI11__mbstate_tEEj");
    GET(host_pubseekpos_w, "_ZNSt3__115basic_streambufIwNS_11char_traitsIwEEE10pubseekposENS_4fposI11__mbstate_tEEj");
    if (missing) {
        fflush(stdout);
        fprintf(stderr, "ferry: this system's libc++ lacks %s, which Ferry needs to run C++ programs\n", missing);
        exit(127);
    }
    state_vtable[0] = NULL;
    state_vtable[1] = assoc_typeinfo;
    state_vtable[2] = (void *)state_dtor;
    state_vtable[3] = (void *)state_delete;
    state_vtable[4] = (void *)state_on_zero_shared;
    state_vtable[5] = (void *)state_execute;
    pthread_key_create(&at_exit_key, run_at_exit);
    for (int i = 0; i < NSEEK; i++) {
        GET(host_seekoff[i], seekoff_names[i]);
        if (seekpos_names[i])
            GET(host_seekpos[i], seekpos_names[i]);
    }
    if (!missing)
        redirect_seeks();
    GET(filebuf_dtor, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEED1Ev");
    GET(basic_ios_dtor, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED2Ev");
    GET(operator_delete, "_ZdlPv");
    if (!missing) {
        fstreams_ready =
            make_fstream_class(&ifstream_class, ifstream_d1, ifstream_d0, ifstream_ios_d1, ifstream_ios_d0) &&
            make_fstream_class(&ofstream_class, ofstream_d1, ofstream_d0, ofstream_ios_d1, ofstream_ios_d0);
        if (!fstreams_ready && ferry_verbose)
            fprintf(stderr, "ferry: this system's libc++ lays out file streams in a way Ferry doesn't know; "
                            "std::ifstream and std::ofstream may not work\n");
    }
}
