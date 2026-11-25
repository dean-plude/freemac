/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Core Audio's host time (freemac 1.234, Ferry 0.58.0),
 * written from Apple's public documentation. Host time is
 * mach_absolute_time's clock, which counts nanoseconds under Ferry. Not
 * Apple's header. */
#ifndef _FERRY_COREAUDIO_HOSTTIME_H_
#define _FERRY_COREAUDIO_HOSTTIME_H_
#include <CoreAudioTypes/CoreAudioTypes.h>

#ifdef __cplusplus
extern "C" {
#endif

UInt64 AudioGetCurrentHostTime(void);
Float64 AudioGetHostClockFrequency(void);
UInt32 AudioGetHostClockMinimumTimeDelta(void);
UInt64 AudioConvertHostTimeToNanos(UInt64 inHostTime);
UInt64 AudioConvertNanosToHostTime(UInt64 inNanos);

#ifdef __cplusplus
}
#endif
#endif
