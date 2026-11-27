/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.235): what VLC's core needs of threads and the main
 * run loop. Waiting on a condition is a cancellation point, as POSIX says, so
 * pthread_cancel ends a thread waiting there (VLC stops its decoder threads
 * that way), with the mutex held again for the cleanup handlers. On the main
 * thread CFRunLoopRun waits for work from the main queue until CFRunLoopStop,
 * as VLC's main does, while CFRunLoopRunInMode still finishes at once with
 * nothing to do. Since freemac 1.237: nil is a null pointer in C too,
 * through CoreServices (VLC's sound out uses it so), and a cancellable wait
 * wakes taken at the end of one of its slices aren't lost: threads handing
 * work to each other through a condition, as FFmpeg's decoding threads do,
 * never hang. Since the darktable work, a wait that nobody signals goes on
 * waiting, as a Mac's does (some programs don't check their condition
 * again), and a signal sent between two of its slices still ends it. */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static volatile int waiting, cleaned, owned, signalled;

static void cleanup(void *arg)
{
    (void)arg;
    owned = pthread_mutex_trylock(&lock) == EBUSY;   /* held again, by us */
    cleaned++;
    pthread_mutex_unlock(&lock);
}

static void *waiter(void *arg)
{
    int timed = arg != NULL;
    pthread_mutex_lock(&lock);
    pthread_cleanup_push(cleanup, NULL);
    waiting = 1;
    for (;;) {
        if (timed) {
            struct timespec t;
            clock_gettime(CLOCK_REALTIME, &t);
            t.tv_sec += 30;
            pthread_cond_timedwait(&cond, &lock, &t);
        } else
            pthread_cond_wait(&cond, &lock);
    }
    pthread_cleanup_pop(0);
    return NULL;
}

static void *uncancellable(void *arg)
{
    (void)arg;
    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);
    pthread_mutex_lock(&lock);
    waiting = 1;
    while (!signalled)
        pthread_cond_wait(&cond, &lock);
    pthread_mutex_unlock(&lock);
    return (void *)42;
}

/* two threads take turns, each waiting for the other's */
static int turn, turns_done;
static pthread_cond_t turn_cond = PTHREAD_COND_INITIALIZER;

static void *taker(void *arg)
{
    int me = (int)(long)arg;
    pthread_mutex_lock(&lock);
    for (int i = 0; i < 20000; i++) {
        while (turn != me)
            pthread_cond_wait(&turn_cond, &lock);
        turn = !me;
        turns_done++;
        pthread_cond_signal(&turn_cond);
    }
    pthread_mutex_unlock(&lock);
    return NULL;
}

static volatile int looked, woke;
static void *looker(void *arg)
{
    (void)arg;
    pthread_mutex_lock(&lock);
    looked = 1;
    pthread_cond_wait(&turn_cond, &lock);   /* once, without checking again */
    woke = 1;
    pthread_mutex_unlock(&lock);
    return NULL;
}

static void cancel_one(const char *name, void *(*fn)(void *), void *arg)
{
    pthread_t t;
    void *result = NULL;
    waiting = 0;
    cleaned = 0;
    owned = 0;
    pthread_create(&t, NULL, fn, arg);
    while (!waiting)
        sched_yield();
    pthread_mutex_lock(&lock);      /* the waiter is in its wait now */
    pthread_mutex_unlock(&lock);
    pthread_cancel(t);
    pthread_join(t, &result);
    printf("%s: canceled %d, cleanup ran %d, with the mutex held %d\n", name,
           result == PTHREAD_CANCELED, cleaned, owned);
}

int main(void)
{
    cancel_one("cond wait", waiter, NULL);
    cancel_one("timed wait", waiter, (void *)1);

    pthread_t t;
    void *result = NULL;
    waiting = 0;
    pthread_create(&t, NULL, uncancellable, NULL);
    while (!waiting)
        sched_yield();
    pthread_cancel(t);
    struct timespec pause = { 0, 300000000 };
    nanosleep(&pause, NULL);
    pthread_mutex_lock(&lock);
    signalled = 1;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&lock);
    pthread_join(t, &result);
    printf("cancellation disabled: woken by the signal %d\n", result == (void *)42);

    /* nothing to do: CFRunLoopRunInMode finishes */
    printf("run in mode with nothing to do: finished %d\n",
           CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, false) == kCFRunLoopRunFinished);

    /* CFRunLoopRun waits for the main queue until it is stopped */
    __block int ran = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200000000ll), dispatch_get_main_queue(), ^{
        ran++;
        dispatch_async(dispatch_get_main_queue(), ^{
            ran++;
            CFRunLoopStop(CFRunLoopGetMain());
        });
    });
    CFRunLoopRun();
    printf("CFRunLoopRun on the main thread: ran both blocks %d, then returned\n", ran == 2);
    char *none = nil;
    printf("nil in C: %d\n", none == NULL);

    pthread_t a, b;
    pthread_create(&a, NULL, taker, (void *)0L);
    pthread_create(&b, NULL, taker, (void *)1L);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    printf("turns taken through a condition: %d\n", turns_done);
    pthread_create(&a, NULL, looker, NULL);
    while (!looked)
        sched_yield();
    struct timespec quiet = { 0, 450000000 };   /* several of its slices */
    nanosleep(&quiet, NULL);
    pthread_mutex_lock(&lock);
    int still = !woke;
    pthread_cond_signal(&turn_cond);
    pthread_mutex_unlock(&lock);
    pthread_join(a, NULL);
    printf("an unsignalled wait goes on waiting: %d, then the signal ends it: %d\n", still, woke);
    return 0;
}
