/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Mach semaphores, as the Mach reference pages describe them
 * (semaphore_create, semaphore_signal, semaphore_wait and the rest), which
 * VLC's threads count on because a Mac has no unnamed POSIX semaphores
 * (freemac 1.NEXT). Ferry serves them from src/libc_vlc.c. */
#ifndef _FERRY_MACH_SEMAPHORE_H_
#define _FERRY_MACH_SEMAPHORE_H_
#include <mach/mach.h>
#include <mach/sync_policy.h>
__FERRY_BEGIN
typedef mach_port_t semaphore_t;
typedef struct mach_timespec { unsigned int tv_sec; int tv_nsec; } mach_timespec_t;
#define KERN_OPERATION_TIMED_OUT 49
#define KERN_ABORTED 14
#define KERN_TERMINATED 37
#define SEMAPHORE_NULL ((semaphore_t)0)
kern_return_t semaphore_create(task_t task, semaphore_t *semaphore, int policy, int value);
kern_return_t semaphore_destroy(task_t task, semaphore_t semaphore);
kern_return_t semaphore_signal(semaphore_t semaphore);
kern_return_t semaphore_signal_all(semaphore_t semaphore);
kern_return_t semaphore_wait(semaphore_t semaphore);
kern_return_t semaphore_timedwait(semaphore_t semaphore, mach_timespec_t wait_time);
__FERRY_END
#endif
