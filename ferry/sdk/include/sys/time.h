/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_TIME_H_
#define _SYS_TIME_H_
#include <_ferry.h>
#include <time.h>
__FERRY_BEGIN
struct timeval { time_t tv_sec; suseconds_t tv_usec; };
struct timezone { int tz_minuteswest, tz_dsttime; };
int gettimeofday(struct timeval *, void *);
__FERRY_END
#endif
