/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia's host time clock (freemac 1.238, Ferry 0.62.0;
 * appkit/CMSampleBuffer.m). Written for freemac from Apple's public API
 * documentation; not Apple's header. The host time clock counts
 * mach_absolute_time, which is nanoseconds under Ferry; other clocks and
 * timebases aren't here. */
#ifndef _FERRY_CMSYNC_H_
#define _FERRY_CMSYNC_H_
#include <CoreMedia/CMTime.h>

__FERRY_BEGIN
typedef struct OpaqueCMClock *CMClockRef;
typedef const struct OpaqueCMClock *CMClockOrTimebaseRef;
enum { kCMClockError_MissingRequiredParameter = -12745, kCMClockError_InvalidParameter = -12746 };
CFTypeID CMClockGetTypeID(void);
CMClockRef CMClockGetHostTimeClock(void);
CMTime CMClockGetTime(CMClockRef clock);
CMTime CMClockMakeHostTimeFromSystemUnits(uint64_t hostTime);
uint64_t CMClockConvertHostTimeToSystemUnits(CMTime hostTime);
__FERRY_END
#endif
