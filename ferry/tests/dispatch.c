/* Grand Central Dispatch from plain C (M6): queues run on the one thread,
 * in order, and dispatch_main runs them for ever. */
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
    dispatch_sync(q, ^{ printf("sync runs at once (order %d)\n", order++); });
    printf("after sync\n");

    /* A group of work, waited for. */
    dispatch_group_t g = dispatch_group_create();
    for (int i = 0; i < 3; i++)
        dispatch_group_async(g, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            printf("group item %d\n", i);
        });
    dispatch_group_notify(g, q, ^{ printf("group notify\n"); });
    printf("group wait: %ld\n", dispatch_group_wait(g, DISPATCH_TIME_FOREVER));

    /* A semaphore signalled from queued work. */
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(q, ^{ printf("signalling\n"); dispatch_semaphore_signal(sem); });
    printf("semaphore wait: %ld\n", dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER));
    printf("semaphore timeout: %ld\n", dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)));

    /* A suspended queue holds its work until resumed. */
    dispatch_queue_t held = dispatch_queue_create("held", NULL);
    dispatch_suspend(held);
    dispatch_async(held, ^{ printf("held work ran\n"); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), q, ^{
        printf("resuming the held queue\n");
        dispatch_resume(held);
    });

    __block size_t sum = 0;
    dispatch_apply(4, q, ^(size_t i) { sum += i; });
    printf("apply sum %zu\n", sum);

    static int key;
    dispatch_queue_set_specific(q, &key, "value", NULL);
    dispatch_sync(q, ^{ printf("specific: %s\n", (char *)dispatch_get_specific(&key)); });

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
