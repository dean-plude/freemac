/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _FERRY_MACH_TIME_H_
#define _FERRY_MACH_TIME_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef struct { uint32_t numer, denom; } mach_timebase_info_data_t;
uint64_t mach_absolute_time(void);
int mach_timebase_info(mach_timebase_info_data_t *);
/* sleeps until mach_absolute_time() reaches the deadline (freemac 1.233) */
int mach_wait_until(uint64_t deadline);
__FERRY_END
#endif
