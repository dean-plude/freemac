/* What code built for an Intel Mac reads straight from the system
 * (freemac 1.232, Ferry 0.56.0): the thread's own block through the gs
 * register, whose first slot is the thread (Qt's QThread::currentThreadId),
 * and the commpage at 0x7fffffe00000 with the processor's features (Qt's
 * check for AVX-512). */
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void *self_slot(void)
{
    void *p;
    __asm__("mov %%gs:0, %0" : "=r"(p));
    return p;
}

static void *other(void *arg)
{
    (void)arg;
    return (void *)(uintptr_t)(self_slot() == (void *)pthread_self());
}

int main(void)
{
    printf("main thread's slot is itself %d\n", self_slot() == (void *)pthread_self());
    pthread_t t;
    void *same;
    pthread_create(&t, NULL, other, NULL);
    pthread_join(t, &same);
    printf("another thread's slot is itself %d\n", same != NULL);
    __block int queued = 0;
    dispatch_sync(dispatch_get_global_queue(0, 0), ^{ queued = self_slot() == (void *)pthread_self(); });
    printf("a dispatch worker's slot is itself %d\n", queued);

    const unsigned char *page = (const unsigned char *)0x7fffffe00000ull;
    uint64_t caps;
    memcpy(&caps, page + 0x10, 8);
    printf("commpage \"%s\", 64-bit %d, SSE2 %d, processors %d\n", (const char *)page, (caps & 0x200) != 0,
           (caps & 0x4) != 0, page[0x22] > 0 && page[0x22] == ((caps >> 16) & 0xff));
    return 0;
}
