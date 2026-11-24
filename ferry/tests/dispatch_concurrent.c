/* SPDX-License-Identifier: GPL-3.0-or-later
 * Grand Central Dispatch on real threads, from plain C: the global queues
 * run blocks at the same time on worker threads, a serial queue runs one
 * block at a time and in order whichever threads feed it, dispatch_sync,
 * groups, semaphores, dispatch_after, barriers, dispatch_apply and
 * dispatch_once work across threads, and the main queue's work runs on
 * the main thread only. Each part checks what it saw and prints a fixed
 * line, so the output keeps one order; an alarm makes a hang fail. */
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define WAIT_LIMIT (5 * NSEC_PER_SEC) /* no wait in this test should come near it */

static dispatch_time_t limit(void) { return dispatch_time(DISPATCH_TIME_NOW, WAIT_LIMIT); }

static void on_alarm(int sig)
{
    (void)sig;
    static const char msg[] = "dispatch_concurrent: timed out\n";
    write(2, msg, sizeof msg - 1);
    _exit(3);
}

/* Up to 64 distinct threads seen. */
struct seen {
    pthread_mutex_t lock;
    pthread_t ids[64];
    int n;
};
static void saw(struct seen *s)
{
    pthread_t me = pthread_self();
    pthread_mutex_lock(&s->lock);
    int known = 0;
    for (int i = 0; i < s->n; i++)
        if (pthread_equal(s->ids[i], me))
            known = 1;
    if (!known && s->n < 64)
        s->ids[s->n++] = me;
    pthread_mutex_unlock(&s->lock);
}

static int once_runs;
static void once_body(void *ctx)
{
    (void)ctx;
    usleep(20000); /* long enough that the other threads arrive and wait */
    __atomic_fetch_add(&once_runs, 1, __ATOMIC_SEQ_CST);
}

int main(void)
{
    signal(SIGALRM, on_alarm);
    alarm(30);
    setvbuf(stdout, NULL, _IOLBF, 0);
    dispatch_queue_t global = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    /* 1. Four blocks on the global queue that each wait for all four to
     * have started: they can only finish if they run at the same time. */
    {
        __block int arrived = 0;
        dispatch_group_t g = dispatch_group_create();
        __block int ok = 1, on_main = 0;
        for (int i = 0; i < 4; i++)
            dispatch_group_async(g, global, ^{
                if (pthread_main_np())
                    on_main = 1;
                __atomic_fetch_add(&arrived, 1, __ATOMIC_SEQ_CST);
                for (int spin = 0; __atomic_load_n(&arrived, __ATOMIC_SEQ_CST) < 4; spin++) {
                    if (spin > 4000) { /* 4 s */
                        ok = 0;
                        break;
                    }
                    usleep(1000);
                }
            });
        long r = dispatch_group_wait(g, limit());
        printf("global queue: 4 blocks met at once: %s (wait %ld), any on the main thread: %d\n", ok ? "yes" : "no",
               r, on_main);
        dispatch_release(g);
    }

    /* 2. A serial queue fed from 8 threads at once: one block at a time,
     * and each feeder's blocks in the order it sent them. */
    {
        dispatch_queue_t serial = dispatch_queue_create("org.freemac.serial", DISPATCH_QUEUE_SERIAL);
        __block int inside = 0, worst = 0, out_of_order = 0;
        static int last[8];
        memset(last, 0xff, sizeof last);
        dispatch_group_t g = dispatch_group_create();
        for (int f = 0; f < 8; f++)
            dispatch_group_async(g, global, ^{
                for (int i = 0; i < 500; i++)
                    dispatch_async(serial, ^{
                        int now = __atomic_add_fetch(&inside, 1, __ATOMIC_SEQ_CST);
                        if (now > worst)
                            worst = now;
                        if (last[f] != i - 1)
                            out_of_order++;
                        last[f] = i;
                        __atomic_sub_fetch(&inside, 1, __ATOMIC_SEQ_CST);
                    });
            });
        dispatch_group_wait(g, limit());
        __block int total = 0;
        dispatch_sync(serial, ^{
            for (int f = 0; f < 8; f++)
                total += last[f] + 1;
        });
        printf("serial queue: %d blocks, at most %d at once, out of order %d\n", total, worst, out_of_order);
        dispatch_release(g);
        dispatch_release(serial);
    }

    /* 3. dispatch_sync onto one serial queue from many threads at once. */
    {
        dispatch_queue_t serial = dispatch_queue_create("org.freemac.sync", NULL);
        __block long shared = 0;
        dispatch_apply(16, global, ^(size_t i) {
            (void)i;
            for (int k = 0; k < 200; k++)
                dispatch_sync(serial, ^{ shared++; });
        });
        printf("dispatch_sync from 16 threads: %ld (expected 3200)\n", shared);
        dispatch_release(serial);
    }

    /* 4. A concurrent queue with a barrier: the blocks before it all end
     * before it starts, it runs alone, and the blocks after start after. */
    {
        dispatch_queue_t conc = dispatch_queue_create("org.freemac.concurrent", DISPATCH_QUEUE_CONCURRENT);
        __block int before_done = 0, during = 0, barrier_saw = -1, after_saw_barrier = 0, overlap = 0;
        __block int barrier_ran = 0;
        for (int i = 0; i < 6; i++)
            dispatch_async(conc, ^{
                __atomic_add_fetch(&during, 1, __ATOMIC_SEQ_CST);
                usleep(5000);
                __atomic_sub_fetch(&during, 1, __ATOMIC_SEQ_CST);
                __atomic_add_fetch(&before_done, 1, __ATOMIC_SEQ_CST);
            });
        dispatch_barrier_async(conc, ^{
            barrier_saw = __atomic_load_n(&before_done, __ATOMIC_SEQ_CST);
            if (__atomic_load_n(&during, __ATOMIC_SEQ_CST))
                overlap++;
            usleep(5000);
            __atomic_store_n(&barrier_ran, 1, __ATOMIC_SEQ_CST);
        });
        for (int i = 0; i < 6; i++)
            dispatch_async(conc, ^{
                if (__atomic_load_n(&barrier_ran, __ATOMIC_SEQ_CST))
                    __atomic_add_fetch(&after_saw_barrier, 1, __ATOMIC_SEQ_CST);
            });
        dispatch_barrier_sync(conc, ^{});
        printf("barrier: saw %d of 6 before it done, overlap %d, 6 after it saw it: %d\n", barrier_saw, overlap,
               after_saw_barrier);
        dispatch_release(conc);
    }

    /* 5. dispatch_apply shares its iterations among threads. */
    {
        static struct seen s = {PTHREAD_MUTEX_INITIALIZER, {0}, 0};
        __block long sum = 0;
        dispatch_apply(64, global, ^(size_t i) {
            saw(&s);
            usleep(2000);
            __atomic_add_fetch(&sum, (long)i, __ATOMIC_SEQ_CST);
        });
        printf("dispatch_apply: sum %ld, on more than one thread: %s\n", sum, s.n > 1 ? "yes" : "no");
    }

    /* 6. Semaphores: two threads take turns, 1000 times. */
    {
        dispatch_semaphore_t ping = dispatch_semaphore_create(0), pong = dispatch_semaphore_create(0);
        __block int turns = 0;
        dispatch_async(global, ^{
            for (int i = 0; i < 1000; i++) {
                dispatch_semaphore_wait(ping, DISPATCH_TIME_FOREVER);
                turns++;
                dispatch_semaphore_signal(pong);
            }
        });
        int lost = 0;
        for (int i = 0; i < 1000; i++) {
            dispatch_semaphore_signal(ping);
            if (dispatch_semaphore_wait(pong, limit()))
                lost++;
        }
        printf("semaphore ping-pong: %d turns, %d lost\n", turns, lost);
        dispatch_release(ping);
        dispatch_release(pong);
    }

    /* 7. A semaphore as a lock of 3: never more than 3 inside. */
    {
        dispatch_semaphore_t three = dispatch_semaphore_create(3);
        __block int inside = 0, worst = 0;
        dispatch_apply(24, global, ^(size_t i) {
            (void)i;
            dispatch_semaphore_wait(three, DISPATCH_TIME_FOREVER);
            int now = __atomic_add_fetch(&inside, 1, __ATOMIC_SEQ_CST);
            int w;
            while ((w = __atomic_load_n(&worst, __ATOMIC_SEQ_CST)) < now &&
                   !__atomic_compare_exchange_n(&worst, &w, now, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
                ;
            usleep(1000);
            __atomic_sub_fetch(&inside, 1, __ATOMIC_SEQ_CST);
            dispatch_semaphore_signal(three);
        });
        printf("counting semaphore: at most %d inside (limit 3)\n", worst);
        dispatch_release(three);
    }

    /* 8. dispatch_once raced by 8 threads: one run, and none returns before it ends. */
    {
        static dispatch_once_t pred;
        __block int early = 0;
        dispatch_apply(8, global, ^(size_t i) {
            (void)i;
            dispatch_once_f(&pred, NULL, once_body);
            if (__atomic_load_n(&once_runs, __ATOMIC_SEQ_CST) != 1)
                early++;
        });
        printf("dispatch_once from 8 threads: ran %d time(s), returned early %d\n", once_runs, early);
    }

    /* 9. dispatch_after on a global queue, and a group's notify. */
    {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, 0);
        __block int64_t waited = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), global, ^{
            waited = (int64_t)(dispatch_time(DISPATCH_TIME_NOW, 0) - start);
            dispatch_semaphore_signal(done);
        });
        long r = dispatch_semaphore_wait(done, limit());
        printf("dispatch_after on a global queue: fired %s, after at least 30 ms: %s\n", r ? "no" : "yes",
               waited >= 29 * (int64_t)NSEC_PER_MSEC ? "yes" : "no");
        dispatch_group_t g = dispatch_group_create();
        __block int ran = 0;
        for (int i = 0; i < 100; i++)
            dispatch_group_async(g, global, ^{ __atomic_add_fetch(&ran, 1, __ATOMIC_SEQ_CST); });
        __block int at_notify = 0;
        dispatch_group_notify(g, global, ^{
            at_notify = __atomic_load_n(&ran, __ATOMIC_SEQ_CST);
            dispatch_semaphore_signal(done);
        });
        dispatch_semaphore_wait(done, limit());
        printf("group notify after all 100: %d\n", at_notify);
        dispatch_release(g);
        dispatch_release(done);
    }

    /* 10. Stress: 20000 blocks over the global queues and 4 serial queues. */
    {
        dispatch_group_t g = dispatch_group_create();
        __block long count = 0;
        dispatch_queue_t serials[4];
        static long per_serial[4];
        for (int s = 0; s < 4; s++)
            serials[s] = dispatch_queue_create("org.freemac.stress", NULL);
        for (int i = 0; i < 20000; i++) {
            if (i % 2)
                dispatch_group_async(g, dispatch_get_global_queue(i % 3 ? 0 : DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                                     ^{ __atomic_add_fetch(&count, 1, __ATOMIC_SEQ_CST); });
            else {
                int s = (i / 2) % 4;
                dispatch_group_async(g, serials[s], ^{ per_serial[s]++; }); /* serial: no lock needed */
            }
        }
        long r = dispatch_group_wait(g, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
        printf("stress: wait %ld, global %ld, serial %ld %ld %ld %ld\n", r, count, per_serial[0], per_serial[1],
               per_serial[2], per_serial[3]);
        for (int s = 0; s < 4; s++)
            dispatch_release(serials[s]);
        dispatch_release(g);
    }

    /* 11. The main queue runs on the main thread, sent from a worker and
     * drained by dispatch_main, which never returns. */
    printf("main thread: %d\n", pthread_main_np());
    dispatch_async(global, ^{
        int worker_main = pthread_main_np();
        dispatch_async(dispatch_get_main_queue(), ^{
            printf("main queue block: on the main thread %d (the worker was %d)\n", pthread_main_np(), worker_main);
            exit(0);
        });
    });
    dispatch_main();
}
