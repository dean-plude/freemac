/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* POSIX named semaphores, as sem_open(2) describes them (freemac 1.227,
 * for Swift's Darwin overlay). On a Mac a semaphore is an int. */
#ifndef _SEMAPHORE_H_
#define _SEMAPHORE_H_
#include <_ferry.h>
#include <sys/types.h>
__FERRY_BEGIN
typedef int sem_t;
#define SEM_FAILED ((sem_t *)-1)
sem_t *sem_open(const char *, int, ...);
int sem_close(sem_t *);
int sem_unlink(const char *);
int sem_wait(sem_t *);
int sem_trywait(sem_t *);
int sem_post(sem_t *);
__FERRY_END
#endif
