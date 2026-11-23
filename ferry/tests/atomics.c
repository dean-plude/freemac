/* SPDX-License-Identifier: GPL-3.0-or-later
 * libkern's atomics and spin locks and os_unfair_lock, which older and
 * newer apps use for their own locking, from dispatch_apply's iterations
 * (Ferry runs a program on one thread, so this checks the calls' results,
 * not contention). Also
 * a program that sends its stderr to a file it can't open (Gas Mask does):
 * Ferry's own messages must still reach the terminal. */
#include <libkern/OSAtomic.h>
#include <os/lock.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

static OSSpinLock spin = OS_SPINLOCK_INIT;
static os_unfair_lock unfair = OS_UNFAIR_LOCK_INIT;
static long counted, counted2;
static volatile int32_t atomic32;
static volatile int64_t atomic64;

static void work(void *arg, size_t which)
{
    (void)which;
    for (int i = 0; i < 100000; i++) {
        OSSpinLockLock(&spin);
        counted++;
        OSSpinLockUnlock(&spin);
        os_unfair_lock_lock(&unfair);
        counted2++;
        os_unfair_lock_unlock(&unfair);
        OSAtomicIncrement32Barrier(&atomic32);
        OSAtomicAdd64(2, &atomic64);
    }
    (void)arg;
}

int main(void)
{
    dispatch_apply_f(4, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), NULL, work);
    printf("spin lock: %ld, unfair lock: %ld, atomic32: %d, atomic64: %lld\n", counted, counted2, atomic32,
           (long long)atomic64);
    printf("try on a held lock: %d\n", (OSSpinLockLock(&spin), OSSpinLockTry(&spin)));
    OSSpinLockUnlock(&spin);
    printf("try on a free lock: %d\n", OSSpinLockTry(&spin));
    int32_t v = 5;
    printf("swap 5->6: %d, then 5->7: %d, now %d\n", OSAtomicCompareAndSwap32(5, 6, &v),
           OSAtomicCompareAndSwap32(5, 7, &v), v);
    void *p = NULL;
    OSAtomicCompareAndSwapPtrBarrier(NULL, &v, &p);
    printf("pointer swapped: %d\n", p == &v);
    uint8_t bits[2] = {0, 0};
    printf("test and set bit 9: was %d, byte %#x\n", OSAtomicTestAndSet(9, bits), bits[1]);
    uint32_t mask = 0xf0;
    printf("or: %#x, and orig: %#x, now %#x\n", OSAtomicOr32(0x0f, &mask), OSAtomicAnd32Orig(0x3c, &mask), mask);
    fflush(stdout);
    if (!freopen("/no/such/folder/log.txt", "a", stderr))
        printf("freopen of stderr failed, as it should\n");
    fflush(stdout);
    fprintf(stderr, "stderr still works\n");
    return 0;
}
