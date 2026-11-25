/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * POSIX threads for Mac programs, on this system's own threads.
 *
 * A Mac program's pthread objects have the sizes and the static initializer
 * values of macOS's public <pthread.h> (each begins with a "signature"
 * word, then opaque bytes): a mutex is 64 bytes, a condition variable 48,
 * a read-write lock 200, a once-control 16, a thread attribute 64. This
 * system's own objects fit inside most of those, after the signature word,
 * and are kept there; a condition variable is bigger than its Mac opaque
 * part, so Ferry keeps it on the heap and the Mac object holds a pointer to
 * it. Objects set up by a Mac static initializer are completed the first
 * time they are used. The numbers that differ between the systems (mutex
 * types, detach states, scheduling policies, error numbers) are converted.
 *
 * Threads Ferry starts for a Mac program (pthread_create here, and so
 * NSThread and dispatch's worker threads) run the Mac function directly;
 * pthread_exit from one of them returns to Ferry's start routine, which
 * then ends the thread as this system's pthread_exit would.
 *
 * Written from the public POSIX and macOS interface descriptions; no Apple
 * code was used.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"

/* Mac signature words (the first word of each object). The *_INIT values
 * are what macOS's static initializers store; FERRY_* mark an object Ferry
 * has set up. */
#define MAC_MUTEX_INIT 0x32AAABA7L
#define MAC_MUTEX_ERRORCHECK_INIT 0x32AAABA1L
#define MAC_MUTEX_RECURSIVE_INIT 0x32AAABA2L
#define MAC_MUTEX_FIRSTFIT_INIT 0x32AAABA3L
#define MAC_COND_INIT 0x3CB0B1BBL
#define MAC_RWLOCK_INIT 0x2DA8B3B4L
#define MAC_ONCE_INIT 0x30B1BCBAL
#define FERRY_MUTEX 0x4D555458L     /* "MUTX" */
#define FERRY_BUSY 0x42555359L      /* being completed by another thread */
#define FERRY_COND 0x434F4E44L
#define FERRY_RWLOCK 0x52574C4BL
#define FERRY_ATTR 0x54484154L
#define FERRY_MUTEXATTR 0x4D584154L
#define FERRY_CONDATTR 0x43444154L
#define FERRY_RWLOCKATTR 0x52574154L

struct mac_mutex { long sig; pthread_mutex_t m; char pad[64 - 8 - sizeof(pthread_mutex_t)]; };
struct mac_mutexattr { long sig; pthread_mutexattr_t a; char pad[16 - 8 - sizeof(pthread_mutexattr_t)]; };
struct mac_cond { long sig; pthread_cond_t *c; char pad[32]; };
struct mac_condattr { long sig; pthread_condattr_t a; char pad[16 - 8 - sizeof(pthread_condattr_t)]; };
struct mac_rwlock { long sig; pthread_rwlock_t r; char pad[200 - 8 - sizeof(pthread_rwlock_t)]; };
struct mac_rwlockattr { long sig; pthread_rwlockattr_t a; char pad[24 - 8 - sizeof(pthread_rwlockattr_t)]; };
struct mac_once { long sig; pthread_once_t o; char pad[4]; };
struct mac_attr { long sig; pthread_attr_t a; };
struct mac_sched_param { int priority; char opaque[4]; };
_Static_assert(sizeof(struct mac_mutex) == 64, "Mac mutex is 64 bytes");
_Static_assert(sizeof(struct mac_mutexattr) == 16, "Mac mutex attribute is 16 bytes");
_Static_assert(sizeof(struct mac_cond) == 48, "Mac condition variable is 48 bytes");
_Static_assert(sizeof(struct mac_condattr) == 16, "Mac condition attribute is 16 bytes");
_Static_assert(sizeof(struct mac_rwlock) == 200, "Mac read-write lock is 200 bytes");
_Static_assert(sizeof(struct mac_rwlockattr) == 24, "Mac read-write lock attribute is 24 bytes");
_Static_assert(sizeof(struct mac_once) == 16, "Mac once-control is 16 bytes");
_Static_assert(sizeof(struct mac_attr) == 64, "Mac thread attribute is 64 bytes");

/* Mac values of the numbers that differ */
#define MAC_CREATE_JOINABLE 1
#define MAC_CREATE_DETACHED 2
#define MAC_MUTEX_NORMAL 0
#define MAC_MUTEX_ERRORCHECK 1
#define MAC_MUTEX_RECURSIVE 2
#define MAC_PROCESS_SHARED 1
#define MAC_PROCESS_PRIVATE 2
#define MAC_SCHED_OTHER 1
#define MAC_SCOPE_SYSTEM 1
#define MAC_INHERIT_SCHED 1
#define MAC_STACK_MIN 8192
#define MAC_QOS_DEFAULT 0x15

static int err(int linux_errno) { return ferry_errno_to_mac(linux_errno); }

static void spin_while(volatile long *sig, long value)
{
    while (__atomic_load_n(sig, __ATOMIC_ACQUIRE) == value)
        sched_yield();
}

/* ---- threads ---------------------------------------------------------------- */

static pthread_t main_thread;
static int threaded;                /* a second thread has been started */
static int live_threads;            /* threads started for the program, still running */

/* The kernel's thread ids of the threads Ferry started, for pthread_threadid_np. */
struct known { pthread_t t; pid_t tid; int cancel; struct known *next; };
static struct known *known_threads;
static pthread_mutex_t known_lock = PTHREAD_MUTEX_INITIALIZER;

__attribute__((constructor)) static void note_main_thread(void) { main_thread = pthread_self(); }

static pid_t gettid_now(void) { return (pid_t)syscall(SYS_gettid); }

/* with known_lock held */
static void remember_locked(pthread_t t, pid_t tid)
{
    for (struct known *k = known_threads; k; k = k->next)
        if (pthread_equal(k->t, t)) {
            if (tid)
                k->tid = tid;
            return;
        }
    struct known *k = malloc(sizeof *k);
    if (!k)
        return;
    k->t = t;
    k->tid = tid;
    k->cancel = 0;
    k->next = known_threads;
    known_threads = k;
}

static void remember(pthread_t t, pid_t tid)
{
    pthread_mutex_lock(&known_lock);
    remember_locked(t, tid);
    pthread_mutex_unlock(&known_lock);
}

static void forget(pthread_t t)
{
    pthread_mutex_lock(&known_lock);
    for (struct known **p = &known_threads; *p; p = &(*p)->next)
        if (pthread_equal((*p)->t, t)) {
            struct known *k = *p;
            *p = k->next;
            free(k);
            break;
        }
    pthread_mutex_unlock(&known_lock);
}

struct start {
    void *(*fn)(void *);
    void *arg;
};

/* Where pthread_exit on one of Ferry's threads goes back to. */
static __thread jmp_buf *exit_point;
static __thread void *exit_value;

/* Cleanup handlers (freemac 1.226, Ferry 0.50.0). pthread_cleanup_push and
 * pthread_cleanup_pop are macros in Ferry's <pthread.h>, as on a Mac, that
 * keep each handler's record on the caller's stack and call these;
 * pthread_exit, and a cancellation, run the thread's handlers newest first. */
struct mac_cleanup {
    void (*routine)(void *);
    void *arg;
    struct mac_cleanup *next;
};
static __thread struct mac_cleanup *cleanup_stack;

static void mac___ferry_pthread_cleanup_push(struct mac_cleanup *c, void (*routine)(void *), void *arg)
{
    c->routine = routine;
    c->arg = arg;
    c->next = cleanup_stack;
    cleanup_stack = c;
}

static void mac___ferry_pthread_cleanup_pop(struct mac_cleanup *c, int execute)
{
    if (cleanup_stack == c)
        cleanup_stack = c->next;
    if (execute && c->routine)
        c->routine(c->arg);
}

static void run_cleanup_handlers(void)
{
    while (cleanup_stack) {
        struct mac_cleanup *c = cleanup_stack;
        cleanup_stack = c->next;
        if (c->routine)
            c->routine(c->arg);
    }
}

static void *thread_main(void *p)
{
    struct start s = *(struct start *)p;
    free(p);
    remember(pthread_self(), gettid_now());
    jmp_buf here;
    void *result;
    exit_point = &here;
    if (setjmp(here) == 0)
        result = s.fn(s.arg);
    else
        result = exit_value;
    exit_point = NULL;
    cleanup_stack = NULL;
    forget(pthread_self());
    __atomic_sub_fetch(&live_threads, 1, __ATOMIC_ACQ_REL);
    return result;
}

/* Starts a thread for the program (also used by Ferry's own dispatch and
 * Foundation code through the Mac call). */
static int mac_pthread_create(pthread_t *out, const struct mac_attr *attr, void *(*fn)(void *), void *arg)
{
    struct start *s = malloc(sizeof *s);
    if (!s)
        return err(EAGAIN);
    s->fn = fn;
    s->arg = arg;
    __atomic_store_n(&threaded, 1, __ATOMIC_RELEASE);
    __atomic_add_fetch(&live_threads, 1, __ATOMIC_ACQ_REL);
    pthread_t t;
    /* The thread is known from here on, before it runs (its thread_main
     * waits for the lock), so pthread_cancel finds it at once. */
    pthread_mutex_lock(&known_lock);
    int rc = pthread_create(&t, attr && attr->sig == FERRY_ATTR ? &attr->a : NULL, thread_main, s);
    if (!rc)
        remember_locked(t, 0);
    pthread_mutex_unlock(&known_lock);
    if (rc) {
        __atomic_sub_fetch(&live_threads, 1, __ATOMIC_ACQ_REL);
        free(s);
        return err(rc);
    }
    if (out)
        *out = t;
    return 0;
}

/* For dispatch's stuck-wait check: threads the program started that are still running. */
int ferry_pthread_live_threads(void) { return __atomic_load_n(&live_threads, __ATOMIC_ACQUIRE); }
int ferry_pthread_is_main(void) { return pthread_equal(pthread_self(), main_thread); }

static void mac_pthread_exit(void *value)
{
    run_cleanup_handlers();
    if (exit_point) {
        exit_value = value;
        longjmp(*exit_point, 1);
    }
    pthread_exit(value);
}

static int mac_pthread_join(pthread_t t, void **value) { return err(pthread_join(t, value)); }
static int mac_pthread_detach(pthread_t t) { return err(pthread_detach(t)); }
static pthread_t mac_pthread_self(void) { return pthread_self(); }
static int mac_pthread_equal(pthread_t a, pthread_t b) { return pthread_equal(a, b); }
static int mac_pthread_main_np(void) { return pthread_equal(pthread_self(), main_thread); }
static int mac_pthread_is_threaded_np(void) { return __atomic_load_n(&threaded, __ATOMIC_ACQUIRE); }

static int mac_pthread_threadid_np(pthread_t t, uint64_t *id)
{
    if (!id)
        return err(EINVAL);
    if (!t || pthread_equal(t, pthread_self())) {
        *id = (uint64_t)gettid_now();
        return 0;
    }
    if (pthread_equal(t, main_thread)) {
        *id = (uint64_t)getpid();
        return 0;
    }
    pthread_mutex_lock(&known_lock);
    for (struct known *k = known_threads; k; k = k->next)
        if (pthread_equal(k->t, t)) {
            *id = (uint64_t)k->tid;
            pthread_mutex_unlock(&known_lock);
            return 0;
        }
    pthread_mutex_unlock(&known_lock);
    *id = (uint64_t)t;
    return 0;
}

static unsigned mac_pthread_mach_thread_np(pthread_t t)
{
    uint64_t id = 0;
    mac_pthread_threadid_np(t, &id);
    return (unsigned)id;
}

static unsigned mac_mach_thread_self(void) { return (unsigned)gettid_now(); }

/* A Mac thread names itself; this system keeps 15 characters of it. */
static int mac_pthread_setname_np(const char *name)
{
    char shortened[16];
    snprintf(shortened, sizeof shortened, "%s", name ? name : "");
    return err(pthread_setname_np(pthread_self(), shortened));
}

static int mac_pthread_getname_np(pthread_t t, char *buf, size_t len)
{
    char name[16] = "";
    int rc = pthread_getname_np(t, name, sizeof name);
    if (rc)
        return err(rc);
    if (len)
        snprintf(buf, len, "%s", name);
    return 0;
}

static int stack_of(pthread_t t, void **addr, size_t *size)
{
    pthread_attr_t a;
    if (pthread_getattr_np(t, &a))
        return -1;
    int rc = pthread_attr_getstack(&a, addr, size);
    pthread_attr_destroy(&a);
    return rc;
}

static size_t mac_pthread_get_stacksize_np(pthread_t t)
{
    void *addr;
    size_t size;
    return stack_of(t, &addr, &size) ? 0 : size;
}

/* the top of the stack, where a Mac's stack address points */
static void *mac_pthread_get_stackaddr_np(pthread_t t)
{
    void *addr;
    size_t size;
    return stack_of(t, &addr, &size) ? NULL : (char *)addr + size;
}

static int mac_pthread_once(struct mac_once *once, void (*fn)(void)) { return err(pthread_once(&once->o, fn)); }

static int mac_pthread_getschedparam(pthread_t t, int *policy, struct mac_sched_param *p)
{
    (void)t;
    if (policy)
        *policy = MAC_SCHED_OTHER;
    if (p)
        p->priority = 31;   /* a Mac thread's default priority */
    return 0;
}

static int mac_pthread_setschedparam(pthread_t t, int policy, const struct mac_sched_param *p)
{
    (void)t; (void)policy; (void)p;
    return 0;   /* priorities are left to this system's scheduler */
}

static int mac_sched_get_priority_max(int policy) { (void)policy; return 47; }
static int mac_sched_get_priority_min(int policy) { (void)policy; return 15; }
/* Cancellation (freemac 1.226, Ferry 0.50.0) is deferred, and only
 * pthread_testcancel acts on it: a thread that pthread_cancel has marked,
 * with cancellation enabled, leaves there as pthread_exit(PTHREAD_CANCELED)
 * would, its cleanup handlers run. A thread blocked in a read is not woken;
 * a program that has to end one sends it a signal, as SPMySQL does. Only
 * the program's own threads can be marked (ESRCH otherwise). */
static __thread int cancel_disabled;
#define MAC_PTHREAD_CANCEL_ENABLE 1
#define MAC_PTHREAD_CANCEL_DISABLE 0
#define MAC_PTHREAD_CANCEL_DEFERRED 2
#define MAC_PTHREAD_CANCEL_ASYNCHRONOUS 0
#define MAC_PTHREAD_CANCELED ((void *)1)

static int mac_pthread_cancel(pthread_t t)
{
    int found = 0;
    pthread_mutex_lock(&known_lock);
    for (struct known *k = known_threads; k; k = k->next)
        if (pthread_equal(k->t, t)) {
            k->cancel = 1;
            found = 1;
            break;
        }
    pthread_mutex_unlock(&known_lock);
    return found ? 0 : ESRCH;
}

static int mac_pthread_setcancelstate(int state, int *old)
{
    if (state != MAC_PTHREAD_CANCEL_ENABLE && state != MAC_PTHREAD_CANCEL_DISABLE)
        return EINVAL;
    if (old)
        *old = cancel_disabled ? MAC_PTHREAD_CANCEL_DISABLE : MAC_PTHREAD_CANCEL_ENABLE;
    cancel_disabled = state == MAC_PTHREAD_CANCEL_DISABLE;
    return 0;
}
static int mac_pthread_setcanceltype(int type, int *old)
{
    (void)type;
    if (old)
        *old = MAC_PTHREAD_CANCEL_DEFERRED;
    return 0;
}
static void mac_pthread_testcancel(void)
{
    if (cancel_disabled)
        return;
    int cancel = 0;
    pthread_t self = pthread_self();
    pthread_mutex_lock(&known_lock);
    for (struct known *k = known_threads; k; k = k->next)
        if (pthread_equal(k->t, self)) {
            cancel = k->cancel;
            break;
        }
    pthread_mutex_unlock(&known_lock);
    if (cancel)
        mac_pthread_exit(MAC_PTHREAD_CANCELED);
}
static int mac_pthread_getconcurrency(void) { return 0; }
static int mac_pthread_setconcurrency(int n) { (void)n; return 0; }

/* Quality of service: recorded nowhere, all threads are treated alike. */
static int mac_pthread_set_qos_class_self_np(unsigned qos, int rel) { (void)qos; (void)rel; return 0; }
static unsigned mac_qos_class_self(void) { return MAC_QOS_DEFAULT; }
static unsigned mac_qos_class_main(void) { return 0x21; }
static int mac_pthread_get_qos_class_np(pthread_t t, unsigned *qos, int *rel)
{
    (void)t;
    if (qos)
        *qos = MAC_QOS_DEFAULT;
    if (rel)
        *rel = 0;
    return 0;
}

/* ---- thread attributes -------------------------------------------------------------- */

static int mac_pthread_attr_init(struct mac_attr *a)
{
    int rc = pthread_attr_init(&a->a);
    if (!rc)
        a->sig = FERRY_ATTR;
    return err(rc);
}

static int mac_pthread_attr_destroy(struct mac_attr *a)
{
    if (a->sig != FERRY_ATTR)
        return err(EINVAL);
    a->sig = 0;
    return err(pthread_attr_destroy(&a->a));
}

static int mac_pthread_attr_setdetachstate(struct mac_attr *a, int state)
{
    if (state != MAC_CREATE_JOINABLE && state != MAC_CREATE_DETACHED)
        return err(EINVAL);
    return err(pthread_attr_setdetachstate(&a->a, state == MAC_CREATE_DETACHED ? PTHREAD_CREATE_DETACHED
                                                                               : PTHREAD_CREATE_JOINABLE));
}

static int mac_pthread_attr_getdetachstate(const struct mac_attr *a, int *state)
{
    int s;
    int rc = pthread_attr_getdetachstate(&a->a, &s);
    if (!rc)
        *state = s == PTHREAD_CREATE_DETACHED ? MAC_CREATE_DETACHED : MAC_CREATE_JOINABLE;
    return err(rc);
}

static int mac_pthread_attr_setstacksize(struct mac_attr *a, size_t size)
{
    if (size < MAC_STACK_MIN)
        return err(EINVAL);
    if (size < (size_t)PTHREAD_STACK_MIN)
        size = (size_t)PTHREAD_STACK_MIN;
    return err(pthread_attr_setstacksize(&a->a, size));
}

static int mac_pthread_attr_getstacksize(const struct mac_attr *a, size_t *size)
{
    return err(pthread_attr_getstacksize(&a->a, size));
}

static int mac_pthread_attr_setstack(struct mac_attr *a, void *addr, size_t size)
{
    return err(pthread_attr_setstack(&a->a, addr, size));
}

static int mac_pthread_attr_getstack(const struct mac_attr *a, void **addr, size_t *size)
{
    return err(pthread_attr_getstack(&a->a, addr, size));
}

static int mac_pthread_attr_setguardsize(struct mac_attr *a, size_t size)
{
    return err(pthread_attr_setguardsize(&a->a, size));
}

static int mac_pthread_attr_getguardsize(const struct mac_attr *a, size_t *size)
{
    return err(pthread_attr_getguardsize(&a->a, size));
}

/* Scope, inheritance, policy, priority and QoS are accepted and left to
 * this system's defaults. */
static int mac_pthread_attr_set_any(struct mac_attr *a, int v) { (void)a; (void)v; return 0; }
static int mac_pthread_attr_getscope(const struct mac_attr *a, int *v) { (void)a; *v = MAC_SCOPE_SYSTEM; return 0; }
static int mac_pthread_attr_getinheritsched(const struct mac_attr *a, int *v)
{
    (void)a;
    *v = MAC_INHERIT_SCHED;
    return 0;
}
static int mac_pthread_attr_getschedpolicy(const struct mac_attr *a, int *v) { (void)a; *v = MAC_SCHED_OTHER; return 0; }
static int mac_pthread_attr_setschedparam(struct mac_attr *a, const struct mac_sched_param *p)
{
    (void)a; (void)p;
    return 0;
}
static int mac_pthread_attr_getschedparam(const struct mac_attr *a, struct mac_sched_param *p)
{
    (void)a;
    p->priority = 31;
    return 0;
}
static int mac_pthread_attr_set_qos_class_np(struct mac_attr *a, unsigned qos, int rel)
{
    (void)a; (void)qos; (void)rel;
    return 0;
}
static int mac_pthread_attr_get_qos_class_np(struct mac_attr *a, unsigned *qos, int *rel)
{
    (void)a;
    if (qos)
        *qos = MAC_QOS_DEFAULT;
    if (rel)
        *rel = 0;
    return 0;
}

/* ---- mutexes ------------------------------------------------------------------------ */

static int mac_pthread_mutexattr_init(struct mac_mutexattr *a)
{
    int rc = pthread_mutexattr_init(&a->a);
    if (!rc)
        a->sig = FERRY_MUTEXATTR;
    return err(rc);
}

static int mac_pthread_mutexattr_destroy(struct mac_mutexattr *a)
{
    a->sig = 0;
    return err(pthread_mutexattr_destroy(&a->a));
}

static int mac_pthread_mutexattr_settype(struct mac_mutexattr *a, int type)
{
    int t = type == MAC_MUTEX_NORMAL ? PTHREAD_MUTEX_NORMAL : type == MAC_MUTEX_ERRORCHECK ? PTHREAD_MUTEX_ERRORCHECK
          : type == MAC_MUTEX_RECURSIVE ? PTHREAD_MUTEX_RECURSIVE : -1;
    if (t < 0)
        return err(EINVAL);
    return err(pthread_mutexattr_settype(&a->a, t));
}

static int mac_pthread_mutexattr_gettype(const struct mac_mutexattr *a, int *type)
{
    int t;
    int rc = pthread_mutexattr_gettype(&a->a, &t);
    if (!rc)
        *type = t == PTHREAD_MUTEX_ERRORCHECK ? MAC_MUTEX_ERRORCHECK : t == PTHREAD_MUTEX_RECURSIVE ? MAC_MUTEX_RECURSIVE
              : MAC_MUTEX_NORMAL;
    return err(rc);
}

static int mac_pthread_mutexattr_setpshared(struct mac_mutexattr *a, int v)
{
    return err(pthread_mutexattr_setpshared(&a->a, v == MAC_PROCESS_SHARED ? PTHREAD_PROCESS_SHARED
                                                                           : PTHREAD_PROCESS_PRIVATE));
}

static int mac_pthread_mutexattr_getpshared(const struct mac_mutexattr *a, int *v)
{
    int s;
    int rc = pthread_mutexattr_getpshared(&a->a, &s);
    if (!rc)
        *v = s == PTHREAD_PROCESS_SHARED ? MAC_PROCESS_SHARED : MAC_PROCESS_PRIVATE;
    return err(rc);
}

/* priority protocols and macOS's fairness policy: accepted, not used */
static int mac_pthread_mutexattr_set_any(struct mac_mutexattr *a, int v) { (void)a; (void)v; return 0; }
static int mac_pthread_mutexattr_get_zero(const struct mac_mutexattr *a, int *v) { (void)a; *v = 0; return 0; }

/* This system's mutex inside a Mac one, completing one made by a static
 * initializer of a recursive or error-checking mutex on first use. (The
 * plain initializer leaves the opaque bytes zero, which is this system's
 * own plain initializer.) */
static pthread_mutex_t *mutex_of(struct mac_mutex *m)
{
    long sig = __atomic_load_n(&m->sig, __ATOMIC_ACQUIRE);
    if (sig == MAC_MUTEX_RECURSIVE_INIT || sig == MAC_MUTEX_ERRORCHECK_INIT) {
        if (__atomic_compare_exchange_n(&m->sig, &sig, FERRY_BUSY, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
            pthread_mutexattr_t a;
            pthread_mutexattr_init(&a);
            pthread_mutexattr_settype(&a, sig == MAC_MUTEX_RECURSIVE_INIT ? PTHREAD_MUTEX_RECURSIVE
                                                                           : PTHREAD_MUTEX_ERRORCHECK);
            pthread_mutex_init(&m->m, &a);
            pthread_mutexattr_destroy(&a);
            __atomic_store_n(&m->sig, FERRY_MUTEX, __ATOMIC_RELEASE);
        }
        spin_while(&m->sig, FERRY_BUSY);
    } else if (sig == FERRY_BUSY) {
        spin_while(&m->sig, FERRY_BUSY);
    }
    return &m->m;
}

static int mac_pthread_mutex_init(struct mac_mutex *m, const struct mac_mutexattr *a)
{
    int rc = pthread_mutex_init(&m->m, a && a->sig == FERRY_MUTEXATTR ? &a->a : NULL);
    if (!rc)
        __atomic_store_n(&m->sig, FERRY_MUTEX, __ATOMIC_RELEASE);
    return err(rc);
}

static int mac_pthread_mutex_destroy(struct mac_mutex *m)
{
    int rc = pthread_mutex_destroy(mutex_of(m));
    if (!rc)
        m->sig = 0;
    return err(rc);
}

static int mac_pthread_mutex_lock(struct mac_mutex *m) { return err(pthread_mutex_lock(mutex_of(m))); }
static int mac_pthread_mutex_trylock(struct mac_mutex *m) { return err(pthread_mutex_trylock(mutex_of(m))); }
static int mac_pthread_mutex_unlock(struct mac_mutex *m) { return err(pthread_mutex_unlock(mutex_of(m))); }

/* ---- condition variables ---------------------------------------------------------- */

static int mac_pthread_condattr_init(struct mac_condattr *a)
{
    int rc = pthread_condattr_init(&a->a);
    if (!rc)
        a->sig = FERRY_CONDATTR;
    return err(rc);
}

static int mac_pthread_condattr_destroy(struct mac_condattr *a)
{
    a->sig = 0;
    return err(pthread_condattr_destroy(&a->a));
}

static int mac_pthread_condattr_setpshared(struct mac_condattr *a, int v)
{
    return err(pthread_condattr_setpshared(&a->a, v == MAC_PROCESS_SHARED ? PTHREAD_PROCESS_SHARED
                                                                          : PTHREAD_PROCESS_PRIVATE));
}

static int mac_pthread_condattr_getpshared(const struct mac_condattr *a, int *v)
{
    int s;
    int rc = pthread_condattr_getpshared(&a->a, &s);
    if (!rc)
        *v = s == PTHREAD_PROCESS_SHARED ? MAC_PROCESS_SHARED : MAC_PROCESS_PRIVATE;
    return err(rc);
}

static pthread_cond_t *cond_of(struct mac_cond *c)
{
    pthread_cond_t *real = __atomic_load_n(&c->c, __ATOMIC_ACQUIRE);
    if (real)
        return real;
    /* a static initializer's (or an all-zero) condition: made on first use */
    pthread_cond_t *made = malloc(sizeof *made);
    pthread_cond_init(made, NULL);
    if (__atomic_compare_exchange_n(&c->c, &real, made, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        c->sig = FERRY_COND;
        return made;
    }
    pthread_cond_destroy(made);
    free(made);
    return real;
}

static int mac_pthread_cond_init(struct mac_cond *c, const struct mac_condattr *a)
{
    pthread_cond_t *made = malloc(sizeof *made);
    if (!made)
        return err(ENOMEM);
    int rc = pthread_cond_init(made, a && a->sig == FERRY_CONDATTR ? &a->a : NULL);
    if (rc) {
        free(made);
        return err(rc);
    }
    c->sig = FERRY_COND;
    __atomic_store_n(&c->c, made, __ATOMIC_RELEASE);
    return 0;
}

static int mac_pthread_cond_destroy(struct mac_cond *c)
{
    pthread_cond_t *real = __atomic_exchange_n(&c->c, NULL, __ATOMIC_ACQ_REL);
    c->sig = 0;
    if (real) {
        int rc = pthread_cond_destroy(real);
        if (rc) {
            __atomic_store_n(&c->c, real, __ATOMIC_RELEASE);
            return err(rc);
        }
        free(real);
    }
    return 0;
}

/* Waits on a condition are cancellation points, as on a Mac (freemac 1.235,
 * VLC): VLC ends its decoder and output threads with pthread_cancel while
 * they wait. A thread of the program's own whose cancellation is enabled
 * waits in tenths of a second, and between them leaves as a cancelled
 * thread if pthread_cancel has marked it, its mutex held again as a Mac's
 * would be for its cleanup handlers. The end of a slice returns as a
 * spurious wakeup would (POSIX allows them, and a program's waits check
 * their condition again): a wake that a slice's end took (glibc may give
 * ETIMEDOUT for a wait it was also signalled in) is then never lost. Before
 * that, FFmpeg's decoding threads could hang under VLC's window. Other
 * threads, the main one among them, wait as before. */
static __thread struct known *self_known;
static __thread int self_known_looked;

static struct known *known_self(void)
{
    if (!self_known_looked) {
        pthread_t self = pthread_self();
        pthread_mutex_lock(&known_lock);
        for (struct known *k = known_threads; k; k = k->next)
            if (pthread_equal(k->t, self)) {
                self_known = k;
                break;
            }
        pthread_mutex_unlock(&known_lock);
        self_known_looked = 1;
    }
    return self_known;
}

static int cancel_marked(struct known *k)
{
    pthread_mutex_lock(&known_lock);
    int marked = k->cancel;
    pthread_mutex_unlock(&known_lock);
    return marked;
}

static int wait_cancellable(pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *deadline)
{
    struct known *k = cancel_disabled ? NULL : known_self();
    if (!k)
        return deadline ? pthread_cond_timedwait(c, m, deadline) : pthread_cond_wait(c, m);
    if (!cancel_disabled && cancel_marked(k))
        mac_pthread_exit(MAC_PTHREAD_CANCELED);
    struct timespec slice;
    clock_gettime(CLOCK_REALTIME, &slice);
    slice.tv_nsec += 100000000;
    if (slice.tv_nsec >= 1000000000) {
        slice.tv_sec++;
        slice.tv_nsec -= 1000000000;
    }
    int last = deadline && (deadline->tv_sec < slice.tv_sec ||
                            (deadline->tv_sec == slice.tv_sec && deadline->tv_nsec <= slice.tv_nsec));
    int r = pthread_cond_timedwait(c, m, last ? deadline : &slice);
    if (!cancel_disabled && cancel_marked(k))
        mac_pthread_exit(MAC_PTHREAD_CANCELED);
    return r == ETIMEDOUT && !last ? 0 : r;
}

static int mac_pthread_cond_wait(struct mac_cond *c, struct mac_mutex *m)
{
    return err(wait_cancellable(cond_of(c), mutex_of(m), NULL));
}

static int mac_pthread_cond_timedwait(struct mac_cond *c, struct mac_mutex *m, const struct timespec *t)
{
    return err(wait_cancellable(cond_of(c), mutex_of(m), t));
}

/* macOS's own: a wait for at most a length of time */
static int mac_pthread_cond_timedwait_relative_np(struct mac_cond *c, struct mac_mutex *m, const struct timespec *rel)
{
    struct timespec t;
    clock_gettime(CLOCK_REALTIME, &t);
    if (rel) {
        t.tv_sec += rel->tv_sec;
        t.tv_nsec += rel->tv_nsec;
        if (t.tv_nsec >= 1000000000) {
            t.tv_sec++;
            t.tv_nsec -= 1000000000;
        }
    }
    return mac_pthread_cond_timedwait(c, m, &t);
}

static int mac_pthread_cond_signal(struct mac_cond *c) { return err(pthread_cond_signal(cond_of(c))); }
static int mac_pthread_cond_broadcast(struct mac_cond *c) { return err(pthread_cond_broadcast(cond_of(c))); }
/* waking one particular thread can't be asked of this system: wake them all */
static int mac_pthread_cond_signal_thread_np(struct mac_cond *c, pthread_t t)
{
    (void)t;
    return mac_pthread_cond_broadcast(c);
}

/* ---- read-write locks ---------------------------------------------------------------- */

static int mac_pthread_rwlockattr_init(struct mac_rwlockattr *a)
{
    int rc = pthread_rwlockattr_init(&a->a);
    if (!rc)
        a->sig = FERRY_RWLOCKATTR;
    return err(rc);
}

static int mac_pthread_rwlockattr_destroy(struct mac_rwlockattr *a)
{
    a->sig = 0;
    return err(pthread_rwlockattr_destroy(&a->a));
}

static int mac_pthread_rwlockattr_setpshared(struct mac_rwlockattr *a, int v)
{
    return err(pthread_rwlockattr_setpshared(&a->a, v == MAC_PROCESS_SHARED ? PTHREAD_PROCESS_SHARED
                                                                            : PTHREAD_PROCESS_PRIVATE));
}

static int mac_pthread_rwlockattr_getpshared(const struct mac_rwlockattr *a, int *v)
{
    int s;
    int rc = pthread_rwlockattr_getpshared(&a->a, &s);
    if (!rc)
        *v = s == PTHREAD_PROCESS_SHARED ? MAC_PROCESS_SHARED : MAC_PROCESS_PRIVATE;
    return err(rc);
}

/* The Mac static initializer leaves the opaque bytes zero, which is this
 * system's own initializer too. */
static int mac_pthread_rwlock_init(struct mac_rwlock *l, const struct mac_rwlockattr *a)
{
    int rc = pthread_rwlock_init(&l->r, a && a->sig == FERRY_RWLOCKATTR ? &a->a : NULL);
    if (!rc)
        l->sig = FERRY_RWLOCK;
    return err(rc);
}

static int mac_pthread_rwlock_destroy(struct mac_rwlock *l)
{
    int rc = pthread_rwlock_destroy(&l->r);
    if (!rc)
        l->sig = 0;
    return err(rc);
}

static int mac_pthread_rwlock_rdlock(struct mac_rwlock *l) { return err(pthread_rwlock_rdlock(&l->r)); }
static int mac_pthread_rwlock_tryrdlock(struct mac_rwlock *l) { return err(pthread_rwlock_tryrdlock(&l->r)); }
static int mac_pthread_rwlock_wrlock(struct mac_rwlock *l) { return err(pthread_rwlock_wrlock(&l->r)); }
static int mac_pthread_rwlock_trywrlock(struct mac_rwlock *l) { return err(pthread_rwlock_trywrlock(&l->r)); }
static int mac_pthread_rwlock_unlock(struct mac_rwlock *l) { return err(pthread_rwlock_unlock(&l->r)); }

/* ---- thread-specific data ------------------------------------------------------------- */

/* A Mac key is an unsigned long, this system's an unsigned int. */
static int mac_pthread_key_create(unsigned long *key, void (*destructor)(void *))
{
    pthread_key_t k;
    int rc = pthread_key_create(&k, destructor);
    if (!rc)
        *key = k;
    return err(rc);
}

static int mac_pthread_key_delete(unsigned long key) { return err(pthread_key_delete((pthread_key_t)key)); }
static void *mac_pthread_getspecific(unsigned long key) { return pthread_getspecific((pthread_key_t)key); }
static int mac_pthread_setspecific(unsigned long key, const void *value)
{
    return err(pthread_setspecific((pthread_key_t)key, value));
}

/* ---- os_unfair_lock and OSSpinLock ----------------------------------------------------
 * An unfair lock is one 32-bit word, 0 when free: here 1 when held and 2
 * when held with threads waiting, who sleep in the kernel (a futex) rather
 * than spin. */

static long futex(volatile uint32_t *word, int op, uint32_t value)
{
    return syscall(SYS_futex, word, op | FUTEX_PRIVATE_FLAG, value, NULL, NULL, 0);
}

static void mac_os_unfair_lock_lock(volatile uint32_t *l)
{
    uint32_t c = 0;
    if (__atomic_compare_exchange_n(l, &c, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED))
        return;
    for (int i = 0; i < 64; i++) {      /* a short spin first: most holds are brief */
        c = 0;
        if (__atomic_load_n(l, __ATOMIC_RELAXED) == 0 &&
            __atomic_compare_exchange_n(l, &c, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED))
            return;
        __builtin_ia32_pause();
    }
    if (c != 2)
        c = __atomic_exchange_n(l, 2, __ATOMIC_ACQUIRE);
    while (c != 0) {
        futex(l, FUTEX_WAIT, 2);
        c = __atomic_exchange_n(l, 2, __ATOMIC_ACQUIRE);
    }
}

static bool mac_os_unfair_lock_trylock(volatile uint32_t *l)
{
    uint32_t c = 0;
    return __atomic_compare_exchange_n(l, &c, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}

static void mac_os_unfair_lock_unlock(volatile uint32_t *l)
{
    if (__atomic_exchange_n(l, 0, __ATOMIC_RELEASE) == 2)
        futex(l, FUTEX_WAKE, 1);
}

static void mac_os_unfair_lock_assert(const volatile uint32_t *l) { (void)l; }

/* OSSpinLock: an int32, 0 when free. It spins, then yields the processor. */
static void mac_OSSpinLockLock(volatile int32_t *l)
{
    for (unsigned n = 0; __atomic_exchange_n(l, 1, __ATOMIC_ACQUIRE); n++) {
        while (__atomic_load_n(l, __ATOMIC_RELAXED)) {
            if (n++ < 100)
                __builtin_ia32_pause();
            else
                sched_yield();
        }
    }
}
static bool mac_OSSpinLockTry(volatile int32_t *l) { return !__atomic_exchange_n(l, 1, __ATOMIC_ACQUIRE); }
static void mac_OSSpinLockUnlock(volatile int32_t *l) { __atomic_store_n(l, 0, __ATOMIC_RELEASE); }

static int mac_sched_yield(void) { return sched_yield(); }

/* ---- the table ------------------------------------------------------------------------ */

#define F(name) {#name, (void *)mac_##name}
const struct ferry_symbol ferry_pthread_symbols[] = {
    F(pthread_create), F(pthread_join), F(pthread_detach), F(pthread_self), F(pthread_equal), F(pthread_exit),
    F(pthread_main_np), F(pthread_is_threaded_np), F(pthread_threadid_np), F(pthread_mach_thread_np),
    F(mach_thread_self), F(pthread_setname_np), F(pthread_getname_np), F(pthread_get_stacksize_np),
    F(pthread_get_stackaddr_np), F(pthread_once), F(pthread_getschedparam), F(pthread_setschedparam),
    F(sched_get_priority_max), F(sched_get_priority_min), F(sched_yield), F(pthread_setcancelstate),
    F(pthread_setcanceltype), F(pthread_testcancel), F(pthread_cancel), F(__ferry_pthread_cleanup_push),
    F(__ferry_pthread_cleanup_pop), F(pthread_getconcurrency), F(pthread_setconcurrency),
    F(pthread_set_qos_class_self_np), F(qos_class_self), F(qos_class_main), F(pthread_get_qos_class_np),
    F(pthread_attr_init), F(pthread_attr_destroy), F(pthread_attr_setdetachstate), F(pthread_attr_getdetachstate),
    F(pthread_attr_setstacksize), F(pthread_attr_getstacksize), F(pthread_attr_setstack), F(pthread_attr_getstack),
    F(pthread_attr_setguardsize), F(pthread_attr_getguardsize), F(pthread_attr_getscope),
    F(pthread_attr_getinheritsched), F(pthread_attr_getschedpolicy), F(pthread_attr_setschedparam),
    F(pthread_attr_getschedparam), F(pthread_attr_set_qos_class_np), F(pthread_attr_get_qos_class_np),
    {"pthread_attr_setscope", (void *)mac_pthread_attr_set_any},
    {"pthread_attr_setinheritsched", (void *)mac_pthread_attr_set_any},
    {"pthread_attr_setschedpolicy", (void *)mac_pthread_attr_set_any},
    F(pthread_mutexattr_init), F(pthread_mutexattr_destroy), F(pthread_mutexattr_settype),
    F(pthread_mutexattr_gettype), F(pthread_mutexattr_setpshared), F(pthread_mutexattr_getpshared),
    {"pthread_mutexattr_setprotocol", (void *)mac_pthread_mutexattr_set_any},
    {"pthread_mutexattr_getprotocol", (void *)mac_pthread_mutexattr_get_zero},
    {"pthread_mutexattr_setprioceiling", (void *)mac_pthread_mutexattr_set_any},
    {"pthread_mutexattr_getprioceiling", (void *)mac_pthread_mutexattr_get_zero},
    {"pthread_mutexattr_setpolicy_np", (void *)mac_pthread_mutexattr_set_any},
    {"pthread_mutexattr_getpolicy_np", (void *)mac_pthread_mutexattr_get_zero},
    F(pthread_mutex_init), F(pthread_mutex_destroy), F(pthread_mutex_lock), F(pthread_mutex_trylock),
    F(pthread_mutex_unlock),
    F(pthread_condattr_init), F(pthread_condattr_destroy), F(pthread_condattr_setpshared),
    F(pthread_condattr_getpshared), F(pthread_cond_init), F(pthread_cond_destroy), F(pthread_cond_wait),
    F(pthread_cond_timedwait), F(pthread_cond_timedwait_relative_np), F(pthread_cond_signal),
    F(pthread_cond_broadcast), F(pthread_cond_signal_thread_np),
    F(pthread_rwlockattr_init), F(pthread_rwlockattr_destroy), F(pthread_rwlockattr_setpshared),
    F(pthread_rwlockattr_getpshared), F(pthread_rwlock_init), F(pthread_rwlock_destroy), F(pthread_rwlock_rdlock),
    F(pthread_rwlock_tryrdlock), F(pthread_rwlock_wrlock), F(pthread_rwlock_trywrlock), F(pthread_rwlock_unlock),
    F(pthread_key_create), F(pthread_key_delete), F(pthread_getspecific), F(pthread_setspecific),
    F(os_unfair_lock_lock), F(os_unfair_lock_trylock), F(os_unfair_lock_unlock),
    {"os_unfair_lock_assert_owner", (void *)mac_os_unfair_lock_assert},
    {"os_unfair_lock_assert_not_owner", (void *)mac_os_unfair_lock_assert},
    F(OSSpinLockLock), F(OSSpinLockTry), F(OSSpinLockUnlock),
    {NULL, NULL},
};
