/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * CoreMedia's times (freemac 1.NEXT, Ferry 0.NEXT): see CoreMedia/CoreMedia.h. */
#include <CoreMedia/CoreMedia.h>
#include <math.h>

const CMTime kCMTimeInvalid = {0, 0, 0, 0};
const CMTime kCMTimeIndefinite = {0, 0, kCMTimeFlags_Valid | kCMTimeFlags_Indefinite, 0};
const CMTime kCMTimePositiveInfinity = {0, 0, kCMTimeFlags_Valid | kCMTimeFlags_PositiveInfinity, 0};
const CMTime kCMTimeNegativeInfinity = {0, 0, kCMTimeFlags_Valid | kCMTimeFlags_NegativeInfinity, 0};
const CMTime kCMTimeZero = {0, 1, kCMTimeFlags_Valid, 0};

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
CMTime CMTimeConvertScale(CMTime t, int32_t scale, uint32_t method)
{
    if (!CMTIME_IS_NUMERIC(t) || scale <= 0)
        return t;
    CMTime r = CMTimeMakeWithSeconds(CMTimeGetSeconds(t), scale);
    if ((int64_t)r.value * t.timescale != t.value * (int64_t)scale)
        r.flags |= kCMTimeFlags_HasBeenRounded;
    return r;
}
CMTimeRange CMTimeRangeMake(CMTime start, CMTime duration) { return (CMTimeRange){start, duration}; }
