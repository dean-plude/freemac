/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _FERRY_MACH_TIME_H_
#define _FERRY_MACH_TIME_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef struct { uint32_t numer, denom; } mach_timebase_info_data_t;
uint64_t mach_absolute_time(void);
int mach_timebase_info(mach_timebase_info_data_t *);
__FERRY_END
#endif
