/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* libkern's atomic operations and spin locks, as documented in Apple's
 * public OSAtomic.h man pages. Deprecated there in favour of C11 atomics. */
#ifndef _OSATOMIC_H_
#define _OSATOMIC_H_
#include <_ferry.h>
#include <stdbool.h>
__FERRY_BEGIN
typedef int32_t OSSpinLock;
#define OS_SPINLOCK_INIT 0
void OSSpinLockLock(volatile OSSpinLock *lock);
bool OSSpinLockTry(volatile OSSpinLock *lock);
void OSSpinLockUnlock(volatile OSSpinLock *lock);
void OSMemoryBarrier(void);
int32_t OSAtomicAdd32(int32_t amount, volatile int32_t *value);
int32_t OSAtomicAdd32Barrier(int32_t amount, volatile int32_t *value);
int64_t OSAtomicAdd64(int64_t amount, volatile int64_t *value);
int64_t OSAtomicAdd64Barrier(int64_t amount, volatile int64_t *value);
int32_t OSAtomicIncrement32(volatile int32_t *value);
int32_t OSAtomicIncrement32Barrier(volatile int32_t *value);
int32_t OSAtomicDecrement32(volatile int32_t *value);
int32_t OSAtomicDecrement32Barrier(volatile int32_t *value);
int64_t OSAtomicIncrement64(volatile int64_t *value);
int64_t OSAtomicIncrement64Barrier(volatile int64_t *value);
int64_t OSAtomicDecrement64(volatile int64_t *value);
int64_t OSAtomicDecrement64Barrier(volatile int64_t *value);
int32_t OSAtomicOr32(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicOr32Barrier(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicAnd32(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicAnd32Barrier(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicOr32Orig(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicOr32OrigBarrier(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicAnd32Orig(uint32_t mask, volatile uint32_t *value);
int32_t OSAtomicAnd32OrigBarrier(uint32_t mask, volatile uint32_t *value);
bool OSAtomicCompareAndSwap32(int32_t oldValue, int32_t newValue, volatile int32_t *value);
bool OSAtomicCompareAndSwap32Barrier(int32_t oldValue, int32_t newValue, volatile int32_t *value);
bool OSAtomicCompareAndSwap64(int64_t oldValue, int64_t newValue, volatile int64_t *value);
bool OSAtomicCompareAndSwap64Barrier(int64_t oldValue, int64_t newValue, volatile int64_t *value);
bool OSAtomicCompareAndSwapInt(int oldValue, int newValue, volatile int *value);
bool OSAtomicCompareAndSwapIntBarrier(int oldValue, int newValue, volatile int *value);
bool OSAtomicCompareAndSwapLong(long oldValue, long newValue, volatile long *value);
bool OSAtomicCompareAndSwapLongBarrier(long oldValue, long newValue, volatile long *value);
bool OSAtomicCompareAndSwapPtr(void *oldValue, void *newValue, void *volatile *value);
bool OSAtomicCompareAndSwapPtrBarrier(void *oldValue, void *newValue, void *volatile *value);
bool OSAtomicTestAndSet(uint32_t n, volatile void *address);
bool OSAtomicTestAndSetBarrier(uint32_t n, volatile void *address);
bool OSAtomicTestAndClear(uint32_t n, volatile void *address);
bool OSAtomicTestAndClearBarrier(uint32_t n, volatile void *address);
__FERRY_END
#endif
