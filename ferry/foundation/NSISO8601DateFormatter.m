/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSISO8601DateFormatter and NSDateComponentsFormatter,
 * written from Apple's public documentation of both classes, from the
 * public ISO 8601 standard (calendar, ordinal and week dates, times and UTC
 * offsets) and from the Unicode CLDR's public English unit names; no Apple
 * code was used.
 *
 * NSISO8601DateFormatter writes exactly the fields its options name and
 * reads only strings in that same shape. Week dates are written as ISO 8601
 * writes them ("2024-W27-4"), and a day without a month or week is an
 * ordinal date ("2024-186"). Fractional seconds are milliseconds, cut, not
 * rounded. NSDateComponentsFormatter writes English (United States) units
 * in the six styles. Built without ARC. */
#import "FInternal.h"
#include <math.h>

static int64_t fdiv64(int64_t a, int64_t b) { return a / b - ((a % b) && ((a < 0) != (b < 0))); }

/* ---- NSISO8601DateFormatter ---------------------------------------------------------------- */

@implementation NSISO8601DateFormatter {
    NSTimeZone *_zone;
    NSISO8601DateFormatOptions _options;
}

+ (NSString *)stringFromDate:(NSDate *)date timeZone:(NSTimeZone *)zone formatOptions:(NSISO8601DateFormatOptions)opts
{
    NSISO8601DateFormatter *f = [[[NSISO8601DateFormatter alloc] init] autorelease];
    [f setTimeZone:zone];
    [f setFormatOptions:opts];
    return [f stringFromDate:date];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _zone = [[NSTimeZone timeZoneForSecondsFromGMT:0] retain];
        _options = NSISO8601DateFormatWithInternetDateTime;
    }
    return self;
}

- (void)dealloc
{
    [_zone release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
    [f setTimeZone:_zone];
    f->_options = _options;
    return f;
}

- (NSTimeZone *)timeZone { return _zone; }
- (void)setTimeZone:(NSTimeZone *)zone
{
    NSTimeZone *z = [zone ?: [NSTimeZone timeZoneForSecondsFromGMT:0] retain];
    [_zone release];
    _zone = z;
}
- (NSISO8601DateFormatOptions)formatOptions { return _options; }
- (void)setFormatOptions:(NSISO8601DateFormatOptions)opts { _options = opts; }

static BOOL has(NSISO8601DateFormatOptions o, NSISO8601DateFormatOptions f) { return (o & f) == f; }

/* the ISO 8601 week: weeks start on Monday, week 1 holds the year's first Thursday */
static int64_t iso_week1(int64_t year)
{
    int64_t jan4 = FDaysFromCivil(year, 1, 4);
    int wd = (int)((jan4 % 7 + 7 + 3) % 7);   /* 0 = Monday (1 January 1970 was a Thursday) */
    return jan4 - wd;
}

static int iso_weekday(int64_t days) { return (int)((days % 7 + 7 + 3) % 7) + 1; }   /* 1 = Monday */

static void append_year(NSMutableString *out, int64_t y)
{
    if (y >= 0 && y <= 9999)
        [out appendFormat:@"%04lld", (long long)y];
    else
        [out appendFormat:@"%c%04lld", y < 0 ? '-' : '+', (long long)(y < 0 ? -y : y)];
}

- (NSString *)stringFromDate:(NSDate *)date
{
    if (!date)
        return nil;
    NSISO8601DateFormatOptions o = _options;
    double t = [date timeIntervalSince1970];
    int64_t ms = (int64_t)floor(t * 1000.0 + 1e-6), secs = fdiv64(ms, 1000);
    int32_t off = 0;
    BOOL dst;
    const char *abbr;
    [_zone _at:secs offset:&off dst:&dst abbreviation:&abbr];
    int64_t local = secs + off, days = fdiv64(local, 86400), sod = local - days * 86400;
    int64_t y;
    int m, d;
    FCivilFromDays(days, &y, &m, &d);
    NSMutableString *out = [NSMutableString string];
    NSString *dash = has(o, NSISO8601DateFormatWithDashSeparatorInDate) ? @"-" : @"";
    BOOL dated = (o & (NSISO8601DateFormatWithYear | NSISO8601DateFormatWithMonth | NSISO8601DateFormatWithWeekOfYear |
                       NSISO8601DateFormatWithDay)) != 0;
    if (has(o, NSISO8601DateFormatWithWeekOfYear)) {
        int64_t wy = y;
        if (days >= iso_week1(y + 1))
            wy = y + 1;
        else if (days < iso_week1(y))
            wy = y - 1;
        int week = (int)((days - iso_week1(wy)) / 7) + 1;
        if (has(o, NSISO8601DateFormatWithYear))
            append_year(out, wy);
        if ([out length])
            [out appendString:dash];
        [out appendFormat:@"W%02d", week];
        if (has(o, NSISO8601DateFormatWithDay))
            [out appendFormat:@"%@%d", dash, iso_weekday(days)];
    } else {
        if (has(o, NSISO8601DateFormatWithYear))
            append_year(out, y);
        if (has(o, NSISO8601DateFormatWithMonth)) {
            if ([out length])
                [out appendString:dash];
            [out appendFormat:@"%02d", m];
        }
        if (has(o, NSISO8601DateFormatWithDay)) {
            if ([out length])
                [out appendString:dash];
            if (has(o, NSISO8601DateFormatWithMonth))
                [out appendFormat:@"%02d", d];
            else   /* an ordinal date */
                [out appendFormat:@"%03d", (int)(days - FDaysFromCivil(y, 1, 1) + 1)];
        }
    }
    if (has(o, NSISO8601DateFormatWithTime)) {
        if (dated)
            [out appendString:has(o, NSISO8601DateFormatWithSpaceBetweenDateAndTime) ? @" " : @"T"];
        NSString *colon = has(o, NSISO8601DateFormatWithColonSeparatorInTime) ? @":" : @"";
        [out appendFormat:@"%02d%@%02d%@%02d", (int)(sod / 3600), colon, (int)(sod / 60 % 60), colon, (int)(sod % 60)];
        if (has(o, NSISO8601DateFormatWithFractionalSeconds))
            [out appendFormat:@".%03d", (int)(ms - secs * 1000)];
    }
    if (has(o, NSISO8601DateFormatWithTimeZone)) {
        if (!off) {
            [out appendString:@"Z"];
        } else {
            int a = off < 0 ? -off : off;
            [out appendFormat:@"%c%02d%@%02d", off < 0 ? '-' : '+', a / 3600,
                              has(o, NSISO8601DateFormatWithColonSeparatorInTimeZone) ? @":" : @"", a / 60 % 60];
            if (a % 60)
                [out appendFormat:@"%@%02d", has(o, NSISO8601DateFormatWithColonSeparatorInTimeZone) ? @":" : @"",
                                  a % 60];
        }
    }
    return out;
}

- (NSString *)stringForObjectValue:(id)obj
{
    return [obj isKindOfClass:[NSDate class]] ? [self stringFromDate:obj] : nil;
}

static BOOL digits(const char *s, size_t *p, int n, int64_t *v)
{
    int64_t x = 0;
    for (int i = 0; i < n; i++) {
        char c = s[*p + i];
        if (c < '0' || c > '9')
            return NO;
        x = x * 10 + (c - '0');
    }
    *p += n;
    *v = x;
    return YES;
}

static BOOL literal(const char *s, size_t *p, const char *lit)
{
    size_t n = strlen(lit);
    if (strncmp(s + *p, lit, n))
        return NO;
    *p += n;
    return YES;
}

- (NSDate *)dateFromString:(NSString *)string
{
    if (!string)
        return nil;
    NSISO8601DateFormatOptions o = _options;
    const char *s = [string UTF8String];
    size_t p = 0;
    const char *dash = has(o, NSISO8601DateFormatWithDashSeparatorInDate) ? "-" : "";
    const char *colon = has(o, NSISO8601DateFormatWithColonSeparatorInTime) ? ":" : "";
    int64_t y = 2000, month = 1, day = 1, week = 0, wday = 1, yday = 0, h = 0, mi = 0, sec = 0;
    double frac = 0;
    BOOL dated = NO, byWeek = has(o, NSISO8601DateFormatWithWeekOfYear), byYday = NO;
#define SEP()                                                                                                          \
    do {                                                                                                               \
        if (dated && !literal(s, &p, dash))                                                                            \
            return nil;                                                                                                \
    } while (0)
    if (has(o, NSISO8601DateFormatWithYear)) {
        int sign = 1;
        if (s[p] == '+' || s[p] == '-') {   /* a year past 9999 or before 0 */
            sign = s[p] == '-' ? -1 : 1;
            p++;
        }
        BOOL signed_ = p > 0;
        if (!digits(s, &p, 4, &y))
            return nil;
        /* more digits only after a sign, and only where a dash ends the year */
        while (signed_ && *dash && s[p] >= '0' && s[p] <= '9' && y < 100000000)
            y = y * 10 + (s[p++] - '0');
        y *= sign;
        dated = YES;
    }
    if (byWeek) {
        SEP();
        if (!literal(s, &p, "W") || !digits(s, &p, 2, &week) || week < 1 || week > 53)
            return nil;
        dated = YES;
        if (has(o, NSISO8601DateFormatWithDay)) {
            SEP();
            if (!digits(s, &p, 1, &wday) || wday < 1 || wday > 7)
                return nil;
        }
    } else {
        if (has(o, NSISO8601DateFormatWithMonth)) {
            SEP();
            if (!digits(s, &p, 2, &month) || month < 1 || month > 12)
                return nil;
            dated = YES;
        }
        if (has(o, NSISO8601DateFormatWithDay)) {
            SEP();
            if (has(o, NSISO8601DateFormatWithMonth)) {
                if (!digits(s, &p, 2, &day) || day < 1 || day > 31)
                    return nil;
            } else {
                if (!digits(s, &p, 3, &yday) || yday < 1 || yday > 366)
                    return nil;
                byYday = YES;
            }
            dated = YES;
        }
    }
#undef SEP
    if (has(o, NSISO8601DateFormatWithTime)) {
        if (dated && !literal(s, &p, has(o, NSISO8601DateFormatWithSpaceBetweenDateAndTime) ? " " : "T"))
            return nil;
        if (!digits(s, &p, 2, &h) || !literal(s, &p, colon) || !digits(s, &p, 2, &mi) || !literal(s, &p, colon) ||
            !digits(s, &p, 2, &sec) || h > 24 || mi > 59 || sec > 60)
            return nil;
        if (has(o, NSISO8601DateFormatWithFractionalSeconds)) {
            if (s[p] != '.' && s[p] != ',')
                return nil;
            p++;
            double scale = 0.1;
            if (s[p] < '0' || s[p] > '9')
                return nil;
            while (s[p] >= '0' && s[p] <= '9') {
                frac += (s[p++] - '0') * scale;
                scale /= 10;
            }
        }
    }
    int64_t off = 0;
    BOOL zoned = NO;
    if (has(o, NSISO8601DateFormatWithTimeZone)) {
        if (s[p] == 'Z') {
            p++;
        } else if (s[p] == '+' || s[p] == '-') {
            int sign = s[p++] == '-' ? -1 : 1;
            int64_t zh, zm = 0;
            if (!digits(s, &p, 2, &zh))
                return nil;
            if (s[p] == ':')
                p++;
            if (s[p] >= '0' && s[p] <= '9' && !digits(s, &p, 2, &zm))
                return nil;
            if (zh > 18 || zm > 59)
                return nil;
            off = sign * (zh * 3600 + zm * 60);
        } else {
            return nil;
        }
        zoned = YES;
    }
    if (s[p])
        return nil;
    int64_t days;
    if (byWeek)
        days = iso_week1(y) + (week - 1) * 7 + (wday - 1);
    else if (byYday)
        days = FDaysFromCivil(y, 1, 1) + yday - 1;
    else
        days = FDaysFromCivil(y, (int)month, (int)day);
    int64_t local = days * 86400 + h * 3600 + mi * 60 + sec, t;
    if (zoned)
        t = local - off;
    else
        FLocalToUTC(_zone, local, NO, 0, &t);
    return [NSDate dateWithTimeIntervalSince1970:(double)t + frac];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error
{
    NSDate *d = [self dateFromString:string];
    if (!d) {
        if (error)
            *error = @"Invalid date";
        return NO;
    }
    if (obj)
        *obj = d;
    return YES;
}
@end

/* ---- NSDateComponentsFormatter -------------------------------------------------------------- */

static const struct unit_name {
    NSCalendarUnit unit;
    const char *abbr, *brief, *shortOne, *shortMany, *one, *many;
} unit_names[] = {
    {NSCalendarUnitYear, "y", "yr", "yr", "yrs", "year", "years"},
    {NSCalendarUnitMonth, "mo", "mth", "mth", "mths", "month", "months"},
    {NSCalendarUnitWeekOfMonth, "w", "wk", "wk", "wks", "week", "weeks"},
    {NSCalendarUnitDay, "d", "d", "day", "days", "day", "days"},
    {NSCalendarUnitHour, "h", "hr", "hr", "hr", "hour", "hours"},
    {NSCalendarUnitMinute, "m", "min", "min", "min", "minute", "minutes"},
    {NSCalendarUnitSecond, "s", "sec", "sec", "sec", "second", "seconds"},
};
#define NUNITS (sizeof unit_names / sizeof unit_names[0])

@implementation NSDateComponentsFormatter {
    NSDateComponentsFormatterUnitsStyle _style;
    NSCalendarUnit _allowed;
    NSDateComponentsFormatterZeroFormattingBehavior _zeros;
    NSCalendar *_calendar;
    NSDate *_reference;
    BOOL _fractional, _collapses, _approximate, _remaining;
    NSInteger _maxUnits;
}

+ (NSString *)localizedStringFromDateComponents:(NSDateComponents *)comps
                                     unitsStyle:(NSDateComponentsFormatterUnitsStyle)style
{
    NSDateComponentsFormatter *f = [[[NSDateComponentsFormatter alloc] init] autorelease];
    [f setUnitsStyle:style];
    return [f stringFromDateComponents:comps];
}

- (instancetype)init
{
    if ((self = [super init]))
        _zeros = NSDateComponentsFormatterZeroFormattingBehaviorDefault;
    return self;
}

- (void)dealloc
{
    [_calendar release];
    [_reference release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSDateComponentsFormatter *f = [[NSDateComponentsFormatter alloc] init];
    f->_style = _style;
    f->_allowed = _allowed;
    f->_zeros = _zeros;
    f->_calendar = [_calendar copy];
    f->_reference = [_reference copy];
    f->_fractional = _fractional;
    f->_collapses = _collapses;
    f->_approximate = _approximate;
    f->_remaining = _remaining;
    f->_maxUnits = _maxUnits;
    return f;
}

- (NSDateComponentsFormatterUnitsStyle)unitsStyle { return _style; }
- (void)setUnitsStyle:(NSDateComponentsFormatterUnitsStyle)s { _style = s; }
- (NSCalendarUnit)allowedUnits { return _allowed; }
- (void)setAllowedUnits:(NSCalendarUnit)u
{
    NSCalendarUnit ok = 0;
    for (size_t i = 0; i < NUNITS; i++)
        ok |= unit_names[i].unit;
    if (u & ~ok)
        FRaise(NSInvalidArgumentException, @"Specifying units other than years, months, weeks, days, hours, minutes "
                                            @"and seconds is not allowed");
    _allowed = u;
}
- (NSDateComponentsFormatterZeroFormattingBehavior)zeroFormattingBehavior { return _zeros; }
- (void)setZeroFormattingBehavior:(NSDateComponentsFormatterZeroFormattingBehavior)z { _zeros = z; }
- (NSCalendar *)calendar { return _calendar ?: [NSCalendar currentCalendar]; }
- (void)setCalendar:(NSCalendar *)c
{
    NSCalendar *n = [c copy];
    [_calendar release];
    _calendar = n;
}
- (NSDate *)referenceDate { return _reference; }
- (void)setReferenceDate:(NSDate *)d
{
    NSDate *n = [d copy];
    [_reference release];
    _reference = n;
}
- (BOOL)allowsFractionalUnits { return _fractional; }
- (void)setAllowsFractionalUnits:(BOOL)b { _fractional = b; }
- (NSInteger)maximumUnitCount { return _maxUnits; }
- (void)setMaximumUnitCount:(NSInteger)n { _maxUnits = n; }
- (BOOL)collapsesLargestUnit { return _collapses; }
- (void)setCollapsesLargestUnit:(BOOL)b { _collapses = b; }
- (BOOL)includesApproximationPhrase { return _approximate; }
- (void)setIncludesApproximationPhrase:(BOOL)b { _approximate = b; }
- (BOOL)includesTimeRemainingPhrase { return _remaining; }
- (void)setIncludesTimeRemainingPhrase:(BOOL)b { _remaining = b; }

- (NSCalendarUnit)_units
{
    if (_allowed)
        return _allowed;
    /* the documented default; positional times show hours, minutes and seconds */
    return NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth | NSCalendarUnitDay |
           NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
}

static NSString *unit_text(const struct unit_name *u, double value, NSDateComponentsFormatterUnitsStyle style,
                           NSString *number)
{
    BOOL one = value == 1 || value == -1;
    switch (style) {
    case NSDateComponentsFormatterUnitsStyleAbbreviated:
        return [NSString stringWithFormat:@"%@%s", number, u->abbr];
    case NSDateComponentsFormatterUnitsStyleBrief:
        return [NSString stringWithFormat:@"%@%s", number, u->brief];
    case NSDateComponentsFormatterUnitsStyleShort:
        return [NSString stringWithFormat:@"%@ %s", number, one ? u->shortOne : u->shortMany];
    default:
        return [NSString stringWithFormat:@"%@ %s", number, one ? u->one : u->many];
    }
}

/* Writes values (one for each of unit_names, NAN where not allowed). */
- (NSString *)_write:(double *)vals negative:(BOOL)neg
{
    NSDateComponentsFormatterZeroFormattingBehavior z = _zeros;
    BOOL positional = _style == NSDateComponentsFormatterUnitsStylePositional;
    if (z & NSDateComponentsFormatterZeroFormattingBehaviorDefault)
        z = positional ? NSDateComponentsFormatterZeroFormattingBehaviorDropLeading
                       : NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
    int first = -1, last = -1, nonzeroFirst = -1, nonzeroLast = -1;
    for (int i = 0; i < (int)NUNITS; i++) {
        if (isnan(vals[i]))
            continue;
        if (first < 0)
            first = i;
        last = i;
        if (vals[i] != 0) {
            if (nonzeroFirst < 0)
                nonzeroFirst = i;
            nonzeroLast = i;
        }
    }
    if (first < 0)
        return nil;
    BOOL keep[NUNITS] = {NO};
    for (int i = first; i <= last; i++) {
        if (isnan(vals[i]))
            continue;
        BOOL zero = vals[i] == 0;
        keep[i] = YES;
        if (zero && nonzeroFirst < 0) {
            keep[i] = NO;
        } else if (zero) {
            if (i < nonzeroFirst && (z & NSDateComponentsFormatterZeroFormattingBehaviorDropLeading))
                keep[i] = NO;
            if (i > nonzeroFirst && i < nonzeroLast && (z & NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle))
                keep[i] = NO;
            if (i > nonzeroLast && (z & NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing))
                keep[i] = NO;
        }
    }
    if (nonzeroFirst < 0) {   /* nothing at all: the smallest unit, as zero */
        keep[last] = YES;
        if (positional && last > first)   /* "0:00" */
            for (int i = last - 1; i >= first; i--)
                if (!isnan(vals[i])) {
                    keep[i] = YES;
                    break;
                }
    } else if (positional && nonzeroFirst == last && last > first) {
        for (int i = last - 1; i >= first; i--)   /* "0:05", not "5" */
            if (!isnan(vals[i])) {
                keep[i] = YES;
                break;
            }
    }
    if (_maxUnits > 0) {
        NSInteger count = 0;
        for (int i = 0; i < (int)NUNITS; i++)
            if (keep[i] && ++count > _maxUnits)
                keep[i] = NO;
    }
    NSNumberFormatter *nf = [[[NSNumberFormatter alloc] init] autorelease];
    [nf setNumberStyle:_style == NSDateComponentsFormatterUnitsStyleSpellOut ? NSNumberFormatterSpellOutStyle
                                                                               : NSNumberFormatterDecimalStyle];
    [nf setMaximumFractionDigits:_fractional ? 2 : 0];
    [nf setRoundingMode:NSNumberFormatterRoundDown];
    NSMutableString *out = [NSMutableString string];
    if (neg)
        [out appendString:@"-"];
    BOOL started = NO;
    for (int i = 0; i < (int)NUNITS; i++) {
        if (!keep[i])
            continue;
        double v = fabs(vals[i]);
        if (positional) {
            BOOL pad = started || (_zeros & NSDateComponentsFormatterZeroFormattingBehaviorPad);
            BOOL clock = unit_names[i].unit == NSCalendarUnitMinute || unit_names[i].unit == NSCalendarUnitSecond ||
                         unit_names[i].unit == NSCalendarUnitHour;
            if (started)
                [out appendString:clock ? @":" : @" "];
            NSString *n = [nf stringFromNumber:[NSNumber numberWithDouble:v]];
            if (pad && clock && v < 10)
                n = [@"0" stringByAppendingString:n];
            if (clock)
                [out appendString:n];
            else
                [out appendString:unit_text(&unit_names[i], v, NSDateComponentsFormatterUnitsStyleAbbreviated, n)];
        } else {
            if (started)
                [out appendString:_style == NSDateComponentsFormatterUnitsStyleAbbreviated ||
                                          _style == NSDateComponentsFormatterUnitsStyleBrief
                                      ? @" "
                                      : @", "];
            [out appendString:unit_text(&unit_names[i], v, _style,
                                        [nf stringFromNumber:[NSNumber numberWithDouble:v]])];
        }
        started = YES;
    }
    NSString *s = out;
    if (_approximate)
        s = [@"About " stringByAppendingString:s];
    if (_remaining)
        s = [s stringByAppendingString:@" remaining"];
    return s;
}

/* Splits whole seconds among the allowed units; the largest one gets the
 * rest. Months and years are counted on the calendar from the reference
 * date (or now). */
- (NSString *)_fromDate:(NSDate *)start toDate:(NSDate *)end
{
    NSCalendarUnit units = [self _units];
    double vals[NUNITS];
    NSTimeInterval total = [end timeIntervalSinceDate:start];
    BOOL neg = total < 0;
    if (neg) {
        NSDate *t = start;
        start = end;
        end = t;
    }
    NSCalendarUnit calendarUnits = units & (NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth |
                                            NSCalendarUnitDay);
    double rest = fabs(total);
    NSDateComponents *c = nil;
    if (calendarUnits & (NSCalendarUnitYear | NSCalendarUnitMonth)) {
        c = [[self calendar] components:calendarUnits fromDate:start toDate:end options:0];
        NSDate *after = [[self calendar] dateByAddingComponents:c toDate:start options:0];
        rest = [end timeIntervalSinceDate:after];
    }
    static const double seconds[] = {0, 0, 7 * 86400, 86400, 3600, 60, 1};
    int smallest = -1;
    for (int i = 0; i < (int)NUNITS; i++)
        if (units & unit_names[i].unit)
            smallest = i;
    for (int i = 0; i < (int)NUNITS; i++) {
        vals[i] = NAN;
        if (!(units & unit_names[i].unit))
            continue;
        if (c && (unit_names[i].unit & calendarUnits)) {
            vals[i] = (double)[c valueForComponent:unit_names[i].unit];
            continue;
        }
        if (unit_names[i].unit == NSCalendarUnitYear)   /* without a calendar count: 365 days */
            vals[i] = floor(rest / (365 * 86400.0)), rest -= vals[i] * 365 * 86400.0;
        else if (unit_names[i].unit == NSCalendarUnitMonth)
            vals[i] = floor(rest / (30 * 86400.0)), rest -= vals[i] * 30 * 86400.0;
        else if (i == smallest && _fractional)
            vals[i] = rest / seconds[i], rest = 0;
        else
            vals[i] = floor(rest / seconds[i] + 1e-9), rest -= vals[i] * seconds[i];
    }
    return [self _write:vals negative:neg];
}

- (NSString *)stringFromTimeInterval:(NSTimeInterval)interval
{
    if (isnan(interval) || isinf(interval))
        return nil;
    NSDate *start = _reference ?: [NSDate date];
    return [self _fromDate:start toDate:[start dateByAddingTimeInterval:interval]];
}

- (NSString *)stringFromDate:(NSDate *)start toDate:(NSDate *)end
{
    if (!start || !end)
        return nil;
    return [self _fromDate:start toDate:end];
}

- (NSString *)stringFromDateComponents:(NSDateComponents *)comps
{
    if (!comps)
        return nil;
    NSDate *start = _reference ?: [NSDate date];
    NSDate *end = [[self calendar] dateByAddingComponents:comps toDate:start options:0];
    return [self _fromDate:start toDate:end];
}

- (NSString *)stringForObjectValue:(id)obj
{
    if ([obj isKindOfClass:[NSNumber class]])
        return [self stringFromTimeInterval:[obj doubleValue]];
    if ([obj isKindOfClass:[NSDateComponents class]])
        return [self stringFromDateComponents:obj];
    return nil;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error
{
    if (error)
        *error = @"NSDateComponentsFormatter does not read strings";
    return NO;
}
@end
