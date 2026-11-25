/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Mach semaphores (freemac 1.232, Ferry 0.56.0), from the Mach reference
 * pages for semaphore_create and its calls. Qt's QMutex waits on them on a
 * Mac. Served by Ferry with a counter, a lock and a condition. */
#ifndef _FERRY_MACH_SEMAPHORE_H_
#define _FERRY_MACH_SEMAPHORE_H_
#include <mach/mach.h>
__FERRY_BEGIN
typedef mach_port_t semaphore_t;
typedef int sync_policy_t;
typedef int clock_res_t;
typedef struct mach_timespec {
    unsigned int tv_sec;
    clock_res_t tv_nsec;
} mach_timespec_t;
#define SYNC_POLICY_FIFO 0x0
#define SYNC_POLICY_FIXED_PRIORITY 0x1
#define SYNC_POLICY_REVERSED 0x2
#define SYNC_POLICY_LIFO (SYNC_POLICY_FIFO | SYNC_POLICY_REVERSED)
kern_return_t semaphore_create(task_t task, semaphore_t *semaphore, int policy, int value);
kern_return_t semaphore_destroy(task_t task, semaphore_t semaphore);
kern_return_t semaphore_signal(semaphore_t semaphore);
kern_return_t semaphore_signal_all(semaphore_t semaphore);
kern_return_t semaphore_wait(semaphore_t semaphore);
kern_return_t semaphore_timedwait(semaphore_t semaphore, mach_timespec_t wait_time);
__FERRY_END
#endif
