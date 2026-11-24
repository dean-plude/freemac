/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Scheduling, as described in POSIX and macOS's public sched.h man pages. */
#ifndef _SCHED_H_
#define _SCHED_H_
#include <_ferry.h>
__FERRY_BEGIN
struct sched_param { int sched_priority; char __opaque[4]; };
#define SCHED_OTHER 1
#define SCHED_FIFO 4
#define SCHED_RR 2
int sched_yield(void);
int sched_get_priority_min(int);
int sched_get_priority_max(int);
__FERRY_END
#endif
