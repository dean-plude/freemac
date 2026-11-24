/* SPDX-License-Identifier: GPL-3.0-or-later
 * POSIX threads from plain C: threads that really run at once, the Mac
 * static initializers, recursive and error-checking mutexes, condition
 * variables, read-write locks, once-controls, thread-specific data with
 * destructors, pthread_exit, names, and os_unfair_lock and OSSpinLock
 * counters under contention. */
#include <errno.h>
#include <libkern/OSAtomic.h>
#include <os/lock.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define THREADS 8
#define ROUNDS 20000

static pthread_mutex_t counter_lock = PTHREAD_MUTEX_INITIALIZER;
static long counter;

static void *count(void *arg)
{
    for (int i = 0; i < ROUNDS; i++) {
        pthread_mutex_lock(&counter_lock);
        counter++;
        pthread_mutex_unlock(&counter_lock);
    }
    return arg;
}

static os_unfair_lock unfair = OS_UNFAIR_LOCK_INIT;
static OSSpinLock spin = OS_SPINLOCK_INIT;
static long unfair_count, spin_count;

static void *count_unfair(void *arg)
{
    for (int i = 0; i < ROUNDS; i++) {
        os_unfair_lock_lock(&unfair);
        unfair_count++;
        os_unfair_lock_unlock(&unfair);
        OSSpinLockLock(&spin);
        spin_count++;
        OSSpinLockUnlock(&spin);
    }
    return NULL;
}

/* Two threads that must both be inside at the same time to get out: shows
 * they really run at once. */
static pthread_mutex_t meet_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t meet_cond = PTHREAD_COND_INITIALIZER;
static int arrived;

static void *meet(void *arg)
{
    pthread_mutex_lock(&meet_lock);
    arrived++;
    pthread_cond_broadcast(&meet_cond);
    while (arrived < 2)
        pthread_cond_wait(&meet_cond, &meet_lock);
    pthread_mutex_unlock(&meet_lock);
    return NULL;
}

/* producer and consumer through a one-slot box */
static pthread_mutex_t box_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t box_cond = PTHREAD_COND_INITIALIZER;
static int box_full, box_value;

static void *produce(void *arg)
{
    for (int i = 1; i <= 100; i++) {
        pthread_mutex_lock(&box_lock);
        while (box_full)
            pthread_cond_wait(&box_cond, &box_lock);
        box_value = i;
        box_full = 1;
        pthread_cond_signal(&box_cond);
        pthread_mutex_unlock(&box_lock);
    }
    return NULL;
}

static pthread_once_t once = PTHREAD_ONCE_INIT;
static int once_runs;
static void once_fn(void) { once_runs++; }
static void *call_once(void *arg)
{
    pthread_once(&once, once_fn);
    return NULL;
}

static pthread_key_t key;
static int destructed;
static pthread_mutex_t destructed_lock = PTHREAD_MUTEX_INITIALIZER;
static void destructor(void *value)
{
    pthread_mutex_lock(&destructed_lock);
    destructed += (int)(long)value;
    pthread_mutex_unlock(&destructed_lock);
}

static void *use_key(void *arg)
{
    pthread_setspecific(key, arg);
    return pthread_getspecific(key);
}

static void leave(int depth)
{
    if (depth == 0)
        pthread_exit((void *)77);
    leave(depth - 1);
}

static void *exits_early(void *arg)
{
    leave(5);
    return (void *)1;
}

static pthread_rwlock_t rw = PTHREAD_RWLOCK_INITIALIZER;
static long shared_value;
static void *rw_writer(void *arg)
{
    for (int i = 0; i < ROUNDS / 4; i++) {
        pthread_rwlock_wrlock(&rw);
        shared_value++;
        pthread_rwlock_unlock(&rw);
        pthread_rwlock_rdlock(&rw);
        (void)shared_value;
        pthread_rwlock_unlock(&rw);
    }
    return NULL;
}

static void *named(void *arg)
{
    char name[64];
    pthread_setname_np("worker-thread");
    pthread_getname_np(pthread_self(), name, sizeof name);
    printf("thread name %s, main %d\n", name, pthread_main_np());
    return NULL;
}

int main(void)
{
    pthread_t t[THREADS];
    printf("main thread: %d, threaded before: %d\n", pthread_main_np(), pthread_is_threaded_np());

    for (int i = 0; i < THREADS; i++)
        pthread_create(&t[i], NULL, count, (void *)(long)i);
    long sum = 0;
    for (int i = 0; i < THREADS; i++) {
        void *r;
        pthread_join(t[i], &r);
        sum += (long)r;
    }
    printf("counter %ld (expected %d), results %ld, threaded after: %d\n", counter, THREADS * ROUNDS, sum,
           pthread_is_threaded_np());

    for (int i = 0; i < THREADS; i++)
        pthread_create(&t[i], NULL, count_unfair, NULL);
    for (int i = 0; i < THREADS; i++)
        pthread_join(t[i], NULL);
    printf("unfair lock %ld, spin lock %ld\n", unfair_count, spin_count);

    pthread_create(&t[0], NULL, meet, NULL);
    pthread_create(&t[1], NULL, meet, NULL);
    pthread_join(t[0], NULL);
    pthread_join(t[1], NULL);
    printf("both threads met: %d\n", arrived);

    pthread_create(&t[0], NULL, produce, NULL);
    long total = 0;
    for (int i = 0; i < 100; i++) {
        pthread_mutex_lock(&box_lock);
        while (!box_full)
            pthread_cond_wait(&box_cond, &box_lock);
        total += box_value;
        box_full = 0;
        pthread_cond_signal(&box_cond);
        pthread_mutex_unlock(&box_lock);
    }
    pthread_join(t[0], NULL);
    printf("consumed total %ld\n", total);

    for (int i = 0; i < THREADS; i++)
        pthread_create(&t[i], NULL, call_once, NULL);
    for (int i = 0; i < THREADS; i++)
        pthread_join(t[i], NULL);
    printf("once ran %d time(s)\n", once_runs);

    pthread_key_create(&key, destructor);
    for (int i = 0; i < 4; i++)
        pthread_create(&t[i], NULL, use_key, (void *)(long)(i + 1));
    sum = 0;
    for (int i = 0; i < 4; i++) {
        void *r;
        pthread_join(t[i], &r);
        sum += (long)r;
    }
    printf("keys read back %ld, destructors got %d\n", sum, destructed);
    pthread_key_delete(key);

    void *r = NULL;
    pthread_create(&t[0], NULL, exits_early, NULL);
    pthread_join(t[0], &r);
    printf("pthread_exit value %ld\n", (long)r);

    for (int i = 0; i < 4; i++)
        pthread_create(&t[i], NULL, rw_writer, NULL);
    for (int i = 0; i < 4; i++)
        pthread_join(t[i], NULL);
    printf("read-write lock value %ld\n", shared_value);

    pthread_create(&t[0], NULL, named, NULL);
    pthread_join(t[0], NULL);

    /* attributes */
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    int state = 0;
    pthread_attr_getdetachstate(&attr, &state);
    printf("default detach state %s\n", state == PTHREAD_CREATE_JOINABLE ? "joinable" : "detached");
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_getdetachstate(&attr, &state);
    printf("detach state now %s\n", state == PTHREAD_CREATE_DETACHED ? "detached" : "joinable");
    printf("tiny stack refused: %s\n", pthread_attr_setstacksize(&attr, 100) == EINVAL ? "yes" : "no");
    pthread_attr_setstacksize(&attr, 1 << 20);
    size_t size = 0;
    pthread_attr_getstacksize(&attr, &size);
    printf("stack size %zu\n", size);
    pthread_attr_destroy(&attr);

    /* recursive and error-checking mutexes */
    pthread_mutex_t rec = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;
    printf("recursive: %d %d %d %d\n", pthread_mutex_lock(&rec), pthread_mutex_lock(&rec), pthread_mutex_unlock(&rec),
           pthread_mutex_unlock(&rec));
    pthread_mutexattr_t ma;
    pthread_mutexattr_init(&ma);
    pthread_mutexattr_settype(&ma, PTHREAD_MUTEX_ERRORCHECK);
    int type = -1;
    pthread_mutexattr_gettype(&ma, &type);
    pthread_mutex_t ec;
    pthread_mutex_init(&ec, &ma);
    pthread_mutex_lock(&ec);
    printf("error-checking (type %d): relock %s, trylock %s\n", type,
           pthread_mutex_lock(&ec) == EDEADLK ? "EDEADLK" : "?", pthread_mutex_trylock(&ec) == EBUSY ? "EBUSY" : "?");
    pthread_mutex_unlock(&ec);
    pthread_mutex_destroy(&ec);
    pthread_mutexattr_destroy(&ma);

    /* a wait that runs out */
    pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t c = PTHREAD_COND_INITIALIZER;
    struct timespec rel = {0, 20 * 1000 * 1000};
    pthread_mutex_lock(&m);
    printf("relative wait: %s\n", pthread_cond_timedwait_relative_np(&c, &m, &rel) == ETIMEDOUT ? "ETIMEDOUT" : "?");
    struct timespec abs;
    clock_gettime(CLOCK_REALTIME, &abs);
    abs.tv_nsec += 10 * 1000 * 1000;
    if (abs.tv_nsec >= 1000000000) {
        abs.tv_sec++;
        abs.tv_nsec -= 1000000000;
    }
    printf("absolute wait: %s\n", pthread_cond_timedwait(&c, &m, &abs) == ETIMEDOUT ? "ETIMEDOUT" : "?");
    pthread_mutex_unlock(&m);
    pthread_cond_destroy(&c);
    pthread_mutex_destroy(&m);

    uint64_t id = 0;
    pthread_threadid_np(NULL, &id);
    printf("thread id known: %s, stack size known: %s\n", id ? "yes" : "no",
           pthread_get_stacksize_np(pthread_self()) > 0 ? "yes" : "no");
    printf("equal self: %d, qos %s\n", pthread_equal(pthread_self(), pthread_self()),
           qos_class_self() == QOS_CLASS_DEFAULT || qos_class_self() == QOS_CLASS_USER_INTERACTIVE ? "known" : "?");
    return 0;
}
