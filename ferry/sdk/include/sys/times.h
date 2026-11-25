/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * times (freemac 1.232, Ferry 0.56.0), from POSIX's <sys/times.h>: a
 * process's own and its children's processor time, in clock ticks. */
#ifndef _FERRY_SYS_TIMES_H_
#define _FERRY_SYS_TIMES_H_
#include <_ferry.h>
__FERRY_BEGIN
struct tms {
    clock_t tms_utime;
    clock_t tms_stime;
    clock_t tms_cutime;
    clock_t tms_cstime;
};
clock_t times(struct tms *buffer);
__FERRY_END
#endif
