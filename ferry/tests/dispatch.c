/* Grand Central Dispatch from plain C (M6): a serial queue runs its work
 * in order on worker threads, groups and semaphores wait across threads,
 * and dispatch_main runs the main queue for ever. What runs on other
 * threads records what it saw, and the main thread prints it, so the output
 * keeps one order. */
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>

static int counter;
static void add(void *ctx) { counter += (int)(long)ctx; printf("add %ld -> %d\n", (long)ctx, counter); }

int main(void)
{
    dispatch_queue_t q = dispatch_queue_create("org.freemac.test", DISPATCH_QUEUE_SERIAL);
    printf("label: %s\n", dispatch_queue_get_label(q));
    printf("main label: %s\n", dispatch_queue_get_label(dispatch_get_main_queue()));

    static dispatch_once_t once;
    for (int i = 0; i < 3; i++)
        dispatch_once(&once, ^{ printf("once\n"); });

    __block int order = 0;
    dispatch_async(q, ^{ printf("async 1 (order %d)\n", order++); });
    dispatch_async_f(q, (void *)5, add);
    dispatch_sync(q, ^{ printf("sync runs after them (order %d)\n", order++); });
    printf("after sync\n");

    /* A group of work on the global queue, waited for. */
    dispatch_group_t g = dispatch_group_create();
    __block int items = 0;
    for (int i = 0; i < 3; i++)
        dispatch_group_async(g, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            __atomic_fetch_or(&items, 1 << i, __ATOMIC_SEQ_CST);
        });
    dispatch_semaphore_t notified = dispatch_semaphore_create(0);
    dispatch_group_notify(g, q, ^{ dispatch_semaphore_signal(notified); });
    long gw = dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    printf("group wait: %ld, items done 0x%x\n", gw, __atomic_load_n(&items, __ATOMIC_SEQ_CST));
    printf("group notify: %ld\n", dispatch_semaphore_wait(notified, DISPATCH_TIME_FOREVER));

    /* A semaphore signalled from queued work. */
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(q, ^{ printf("signalling\n"); dispatch_semaphore_signal(sem); });
    printf("semaphore wait: %ld\n", dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER));
    printf("semaphore timeout: %ld\n", dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)));

    __block size_t sum = 0;
    dispatch_apply(4, q, ^(size_t i) { sum += i; });
    printf("apply sum %zu\n", sum);

    static int key;
    dispatch_queue_set_specific(q, &key, "value", NULL);
    dispatch_sync(q, ^{ printf("specific: %s\n", (char *)dispatch_get_specific(&key)); });

    /* A suspended queue holds its work until resumed. */
    dispatch_queue_t held = dispatch_queue_create("held", NULL);
    dispatch_suspend(held);
    dispatch_semaphore_t ran = dispatch_semaphore_create(0);
    dispatch_async(held, ^{ printf("held work ran\n"); dispatch_semaphore_signal(ran); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), q, ^{
        printf("resuming the held queue\n");
        dispatch_resume(held);
    });
    printf("held for 20 ms: %ld\n", dispatch_semaphore_wait(ran, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)));
    dispatch_semaphore_wait(ran, DISPATCH_TIME_FOREVER);

    /* A repeating timer, stopped after three firings; then the program ends. */
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    __block int ticks = 0;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), 10 * NSEC_PER_MSEC, 0);
    dispatch_source_set_event_handler(timer, ^{
        printf("tick %d\n", ++ticks);
        if (ticks == 3)
            dispatch_source_cancel(timer);
    });
    dispatch_source_set_cancel_handler(timer, ^{
        printf("timer cancelled; counter %d\n", counter);
        fflush(stdout);
        exit(0);
    });
    dispatch_resume(timer);
    dispatch_release(q);
    dispatch_main();
}
