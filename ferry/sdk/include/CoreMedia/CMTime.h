/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia's times (freemac 1.233, Ferry 0.57.0;
 * appkit/CoreMedia.m, served from Ferry's AppKit file). Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_CMTIME_H_
#define _FERRY_CMTIME_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef int64_t CMTimeValue;
typedef int32_t CMTimeScale;
typedef int64_t CMTimeEpoch;
typedef uint32_t CMTimeFlags;
enum {
    kCMTimeFlags_Valid = 1UL << 0, kCMTimeFlags_HasBeenRounded = 1UL << 1,
    kCMTimeFlags_PositiveInfinity = 1UL << 2, kCMTimeFlags_NegativeInfinity = 1UL << 3,
    kCMTimeFlags_Indefinite = 1UL << 4,
};
#define kCMTimeMaxTimescale 0x7fffffffL
typedef struct {
    CMTimeValue value;
    CMTimeScale timescale;
    CMTimeFlags flags;
    CMTimeEpoch epoch;
} CMTime;
typedef struct {
    CMTime start;
    CMTime duration;
} CMTimeRange;
extern const CMTime kCMTimeInvalid;
extern const CMTime kCMTimeIndefinite;
extern const CMTime kCMTimePositiveInfinity;
extern const CMTime kCMTimeNegativeInfinity;
extern const CMTime kCMTimeZero;
CMTime CMTimeMake(int64_t value, int32_t timescale);
CMTime CMTimeMakeWithSeconds(double seconds, int32_t preferredTimescale);
double CMTimeGetSeconds(CMTime time);
int32_t CMTimeCompare(CMTime time1, CMTime time2);
CMTime CMTimeAdd(CMTime lhs, CMTime rhs);
CMTime CMTimeSubtract(CMTime lhs, CMTime rhs);
CMTime CMTimeConvertScale(CMTime time, int32_t newTimescale, uint32_t method);
CMTimeRange CMTimeRangeMake(CMTime start, CMTime duration);
#define CMTIME_IS_VALID(t) (((t).flags & kCMTimeFlags_Valid) != 0)
#define CMTIME_IS_INVALID(t) (!CMTIME_IS_VALID(t))
#define CMTIME_IS_INDEFINITE(t) (CMTIME_IS_VALID(t) && ((t).flags & kCMTimeFlags_Indefinite) != 0)
#define CMTIME_IS_NUMERIC(t) \
    (((t).flags & (kCMTimeFlags_Valid | kCMTimeFlags_PositiveInfinity | kCMTimeFlags_NegativeInfinity | \
                   kCMTimeFlags_Indefinite)) == kCMTimeFlags_Valid)
/* more of a time's arithmetic (freemac 1.238, Ferry 0.62.0; appkit/CMSampleBuffer.m) */
CMTime CMTimeMakeWithEpoch(int64_t value, int32_t timescale, int64_t epoch);
CMTime CMTimeMultiply(CMTime time, int32_t multiplier);
CMTime CMTimeMultiplyByFloat64(CMTime time, double multiplier);
CMTime CMTimeMultiplyByRatio(CMTime time, int32_t multiplier, int32_t divisor);
CMTime CMTimeMinimum(CMTime time1, CMTime time2);
CMTime CMTimeMaximum(CMTime time1, CMTime time2);
CMTime CMTimeAbsoluteValue(CMTime time);
__FERRY_END
#endif
