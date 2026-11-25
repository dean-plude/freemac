/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Carbon clock calls of CoreServices' DriverServices
 * (freemac 1.226, Ferry 0.50.0), written from Apple's public documentation
 * of UpTime and AbsoluteToNanoseconds; not Apple's header. An AbsoluteTime
 * is mach_absolute_time's count, which here is nanoseconds, so the
 * conversions keep the number. Sequel Pro times its queries with them.
 * Ferry serves them from Foundation's file. */
#ifndef _FERRY_DRIVERSERVICES_H_
#define _FERRY_DRIVERSERVICES_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef UnsignedWide AbsoluteTime;
typedef UnsignedWide Nanoseconds;
/* A Duration counts milliseconds, or microseconds when it is negative. */
typedef SInt32 Duration;
enum {
    durationMicrosecond = -1,
    durationMillisecond = 1,
    durationSecond = 1000,
    durationMinute = 1000 * 60,
    durationHour = 1000 * 60 * 60,
    durationDay = 1000 * 60 * 60 * 24,
    durationForever = 0x7FFFFFFF,
    durationImmediate = 0,
};

AbsoluteTime UpTime(void);
Nanoseconds AbsoluteToNanoseconds(AbsoluteTime absoluteTime);
Duration AbsoluteToDuration(AbsoluteTime absoluteTime);
AbsoluteTime NanosecondsToAbsolute(Nanoseconds nanoseconds);
AbsoluteTime DurationToAbsolute(Duration duration);
AbsoluteTime AddAbsoluteToAbsolute(AbsoluteTime absoluteTime1, AbsoluteTime absoluteTime2);
AbsoluteTime SubAbsoluteFromAbsolute(AbsoluteTime leftAbsoluteTime, AbsoluteTime rightAbsoluteTime);
AbsoluteTime AddNanosecondsToAbsolute(Nanoseconds nanoseconds, AbsoluteTime absoluteTime);
AbsoluteTime AddDurationToAbsolute(Duration duration, AbsoluteTime absoluteTime);
AbsoluteTime SubNanosecondsFromAbsolute(Nanoseconds nanoseconds, AbsoluteTime absoluteTime);
AbsoluteTime SubDurationFromAbsolute(Duration duration, AbsoluteTime absoluteTime);
Nanoseconds AbsoluteDeltaToNanoseconds(AbsoluteTime leftAbsoluteTime, AbsoluteTime rightAbsoluteTime);
Duration AbsoluteDeltaToDuration(AbsoluteTime leftAbsoluteTime, AbsoluteTime rightAbsoluteTime);
Nanoseconds DurationToNanoseconds(Duration theDuration);
Duration NanosecondsToDuration(Nanoseconds theNanoseconds);
__FERRY_END
#endif
