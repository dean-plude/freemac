/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * CoreMedia's times (freemac 1.233, Ferry 0.57.0): see CoreMedia/CoreMedia.h. */
#include <CoreMedia/CoreMedia.h>
#include <math.h>

const CMTime kCMTimeInvalid = {0, 0, 0, 0};
const CMTime kCMTimeIndefinite = {0, 0, kCMTimeFlags_Valid | kCMTimeFlags_Indefinite, 0};
const CMTime kCMTimePositiveInfinity = {0, 0, kCMTimeFlags_Valid | kCMTimeFlags_PositiveInfinity, 0};
const CMTime kCMTimeNegativeInfinity = {0, 0, kCMTimeFlags_Valid | kCMTimeFlags_NegativeInfinity, 0};
const CMTime kCMTimeZero = {0, 1, kCMTimeFlags_Valid, 0};
const CMTimeRange kCMTimeRangeInvalid = {{0, 0, 0, 0}, {0, 0, 0, 0}};
const CMTimeRange kCMTimeRangeZero = {{0, 1, kCMTimeFlags_Valid, 0}, {0, 1, kCMTimeFlags_Valid, 0}};
const CMTimeMapping kCMTimeMappingInvalid = {{{0, 0, 0, 0}, {0, 0, 0, 0}}, {{0, 0, 0, 0}, {0, 0, 0, 0}}};

CMTime CMTimeMake(int64_t value, int32_t timescale)
{
    if (timescale <= 0)
        return kCMTimeInvalid;
    return (CMTime){value, timescale, kCMTimeFlags_Valid, 0};
}
CMTime CMTimeMakeWithSeconds(double seconds, int32_t scale)
{
    if (isnan(seconds) || scale <= 0)
        return kCMTimeInvalid;
    if (isinf(seconds))
        return seconds > 0 ? kCMTimePositiveInfinity : kCMTimeNegativeInfinity;
    return CMTimeMake((int64_t)llround(seconds * scale), scale);
}
double CMTimeGetSeconds(CMTime t)
{
    if (!CMTIME_IS_VALID(t) || (t.flags & kCMTimeFlags_Indefinite))
        return NAN;
    if (t.flags & kCMTimeFlags_PositiveInfinity)
        return INFINITY;
    if (t.flags & kCMTimeFlags_NegativeInfinity)
        return -INFINITY;
    return (double)t.value / (double)t.timescale;
}
int32_t CMTimeCompare(CMTime a, CMTime b)
{
    double x = CMTimeGetSeconds(a), y = CMTimeGetSeconds(b);
    if (isnan(x) || isnan(y))
        return isnan(x) == isnan(y) ? 0 : isnan(x) ? 1 : -1;
    if (a.timescale == b.timescale && CMTIME_IS_NUMERIC(a) && CMTIME_IS_NUMERIC(b))
        return a.value < b.value ? -1 : a.value > b.value;
    return x < y ? -1 : x > y;
}
static int64_t gcd(int64_t a, int64_t b)
{
    while (b) {
        int64_t t = a % b;
        a = b;
        b = t;
    }
    return a < 0 ? -a : a;
}
static CMTime combine(CMTime a, CMTime b, int sign)
{
    if (!CMTIME_IS_NUMERIC(a) || !CMTIME_IS_NUMERIC(b)) {
        if (CMTIME_IS_INVALID(a) || CMTIME_IS_INVALID(b))
            return kCMTimeInvalid;
        return CMTimeMakeWithSeconds(CMTimeGetSeconds(a) + sign * CMTimeGetSeconds(b), 1);
    }
    if (a.timescale == b.timescale)
        return CMTimeMake(a.value + sign * b.value, a.timescale);
    int64_t l = (int64_t)a.timescale / gcd(a.timescale, b.timescale) * b.timescale;
    if (l > kCMTimeMaxTimescale)
        return CMTimeMakeWithSeconds(CMTimeGetSeconds(a) + sign * CMTimeGetSeconds(b), (a.timescale > b.timescale ? a.timescale : b.timescale));
    return CMTimeMake(a.value * (l / a.timescale) + sign * b.value * (l / b.timescale), (int32_t)l);
}
CMTime CMTimeAdd(CMTime a, CMTime b) { return combine(a, b, 1); }
CMTime CMTimeSubtract(CMTime a, CMTime b) { return combine(a, b, -1); }
/* value * scale / timescale, exactly, rounded as the method says (freemac
 * 1.258); the QuickTime method rounds as the default does */
CMTime CMTimeConvertScale(CMTime t, int32_t scale, CMTimeRoundingMethod method)
{
    if (!CMTIME_IS_NUMERIC(t) || scale <= 0)
        return t;
    if (scale == t.timescale)
        return t;
    __int128 num = (__int128)t.value * scale, den = t.timescale;
    __int128 q = num / den, rem = num % den; /* q rounds toward zero */
    if (rem) {
        int neg = (num < 0) != (den < 0);
        __int128 twice = rem < 0 ? -2 * rem : 2 * rem, d = den < 0 ? -den : den;
        int away = 0;
        switch (method) {
        case kCMTimeRoundingMethod_RoundTowardZero: away = 0; break;
        case kCMTimeRoundingMethod_RoundAwayFromZero: away = 1; break;
        case kCMTimeRoundingMethod_RoundTowardPositiveInfinity: away = !neg; break;
        case kCMTimeRoundingMethod_RoundTowardNegativeInfinity: away = neg; break;
        default: away = twice >= d; break; /* half away from zero */
        }
        if (away)
            q += neg ? -1 : 1;
    }
    if (q > INT64_MAX || q < INT64_MIN)
        return (CMTime){0, 0, kCMTimeFlags_Valid | (q > 0 ? kCMTimeFlags_PositiveInfinity
                                                          : kCMTimeFlags_NegativeInfinity), 0};
    CMTime r = CMTimeMake((int64_t)q, scale);
    r.epoch = t.epoch;
    if (rem)
        r.flags |= kCMTimeFlags_HasBeenRounded;
    return r;
}
CMTimeRange CMTimeRangeMake(CMTime start, CMTime duration) { return (CMTimeRange){start, duration}; }
