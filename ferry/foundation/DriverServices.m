/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * CoreServices' Carbon clock calls (freemac 1.226, Ferry 0.50.0): UpTime
 * and the conversions between AbsoluteTime, Nanoseconds and Duration. An
 * AbsoluteTime is mach_absolute_time's count, which under Ferry is
 * nanoseconds (mach_timebase_info answers 1/1), so the conversion to
 * nanoseconds keeps the number. Sequel Pro and its SPMySQL time queries
 * and keep-alive pings with them.
 */
#include <CoreServices/CoreServices.h>
#include <mach/mach_time.h>

static UInt64 wide(UnsignedWide w) { return ((UInt64)w.hi << 32) | w.lo; }
static UnsignedWide unwide(UInt64 v)
{
    UnsignedWide w = {(uint32_t)v, (uint32_t)(v >> 32)};
    return w;
}

/* A Duration in nanoseconds: milliseconds when positive, microseconds when
 * negative; durationForever is the largest count. */
static UInt64 duration_ns(Duration d)
{
    if (d == durationForever)
        return UINT64_MAX;
    if (d >= 0)
        return (UInt64)d * 1000000ull;
    return (UInt64)(-(int64_t)d) * 1000ull;
}

static Duration ns_duration(UInt64 ns)
{
    /* milliseconds when it fits, otherwise forever; microseconds for less
     * than a millisecond, as a Mac answers */
    if (ns >= 1000000ull) {
        UInt64 ms = ns / 1000000ull;
        return ms >= (UInt64)durationForever ? durationForever : (Duration)ms;
    }
    return -(Duration)(ns / 1000ull);
}

AbsoluteTime UpTime(void) { return unwide(mach_absolute_time()); }
Nanoseconds AbsoluteToNanoseconds(AbsoluteTime t) { return t; }
Duration AbsoluteToDuration(AbsoluteTime t) { return ns_duration(wide(t)); }
AbsoluteTime NanosecondsToAbsolute(Nanoseconds ns) { return ns; }
AbsoluteTime DurationToAbsolute(Duration d) { return unwide(duration_ns(d)); }
AbsoluteTime AddAbsoluteToAbsolute(AbsoluteTime a, AbsoluteTime b) { return unwide(wide(a) + wide(b)); }
AbsoluteTime SubAbsoluteFromAbsolute(AbsoluteTime a, AbsoluteTime b)
{
    return unwide(wide(a) > wide(b) ? wide(a) - wide(b) : 0);
}
AbsoluteTime AddNanosecondsToAbsolute(Nanoseconds ns, AbsoluteTime t) { return unwide(wide(t) + wide(ns)); }
AbsoluteTime AddDurationToAbsolute(Duration d, AbsoluteTime t) { return unwide(wide(t) + duration_ns(d)); }
AbsoluteTime SubNanosecondsFromAbsolute(Nanoseconds ns, AbsoluteTime t)
{
    return unwide(wide(t) > wide(ns) ? wide(t) - wide(ns) : 0);
}
AbsoluteTime SubDurationFromAbsolute(Duration d, AbsoluteTime t)
{
    UInt64 n = duration_ns(d);
    return unwide(wide(t) > n ? wide(t) - n : 0);
}
/* the time between the two, whichever comes first */
static UInt64 delta(AbsoluteTime a, AbsoluteTime b) { return wide(a) > wide(b) ? wide(a) - wide(b) : wide(b) - wide(a); }
Nanoseconds AbsoluteDeltaToNanoseconds(AbsoluteTime left, AbsoluteTime right) { return unwide(delta(left, right)); }
Duration AbsoluteDeltaToDuration(AbsoluteTime left, AbsoluteTime right) { return ns_duration(delta(left, right)); }
Nanoseconds DurationToNanoseconds(Duration d) { return unwide(duration_ns(d)); }
Duration NanosecondsToDuration(Nanoseconds ns) { return ns_duration(wide(ns)); }
