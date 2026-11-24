/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSCalendar and NSDateComponents, written from Apple's
 * public documentation of both classes, the public Unicode standard for
 * calendars and weeks (Unicode Technical Standard #35, with the first day of
 * the week and the minimal days in the first week from the Unicode CLDR's
 * public week data) and ISO 8601; no Apple code was used.
 *
 * Two calendars: the Gregorian one (proleptic, so dates before 15 October
 * 1582 stay Gregorian where a Mac switches to the Julian calendar) and the
 * ISO 8601 one, which is the Gregorian calendar with weeks starting on Monday
 * and the first week of a year the one holding its first Thursday. Dates are
 * taken apart in the calendar's time zone (NSTimeZone.m). A wall-clock time
 * that happens twice, when the clocks go back, is the first of the two; one
 * that doesn't happen, when they go forward, moves forward by the jump.
 * Built without ARC. */
#import "FInternal.h"
#include <math.h>

NSCalendarIdentifier const NSCalendarIdentifierGregorian = @"gregorian";
NSCalendarIdentifier const NSCalendarIdentifierISO8601 = @"iso8601";
NSCalendarIdentifier const NSCalendarIdentifierBuddhist = @"buddhist";
NSCalendarIdentifier const NSCalendarIdentifierChinese = @"chinese";
NSCalendarIdentifier const NSCalendarIdentifierCoptic = @"coptic";
NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteMihret = @"ethiopic";
NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteAlem = @"ethiopic-amete-alem";
NSCalendarIdentifier const NSCalendarIdentifierHebrew = @"hebrew";
NSCalendarIdentifier const NSCalendarIdentifierIndian = @"indian";
NSCalendarIdentifier const NSCalendarIdentifierIslamic = @"islamic";
NSCalendarIdentifier const NSCalendarIdentifierIslamicCivil = @"islamic-civil";
NSCalendarIdentifier const NSCalendarIdentifierIslamicTabular = @"islamic-tbla";
NSCalendarIdentifier const NSCalendarIdentifierIslamicUmmAlQura = @"islamic-umalqura";
NSCalendarIdentifier const NSCalendarIdentifierJapanese = @"japanese";
NSCalendarIdentifier const NSCalendarIdentifierPersian = @"persian";
NSCalendarIdentifier const NSCalendarIdentifierRepublicOfChina = @"roc";
NSString *const NSGregorianCalendar = @"gregorian";
NSString *const NSISO8601Calendar = @"iso8601";
NSNotificationName const NSCalendarDayChangedNotification = @"NSCalendarDayChangedNotification";

#define UNDEF NSIntegerMax
#define NBITS 17

/* ---- arithmetic on days ---------------------------------------------------------------- */

static int64_t fdiv(int64_t a, int64_t b) { return a / b - ((a % b) && ((a < 0) != (b < 0))); }
static int64_t fmod64(int64_t a, int64_t b) { return a - fdiv(a, b) * b; }
static int weekday_of(int64_t days) { return (int)fmod64(days + 4, 7) + 1; } /* 1 is Sunday */
static BOOL leap_year(int64_t y) { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0; }
static int days_in_month(int64_t y, int m)
{
    static const int dim[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return m == 2 && leap_year(y) ? 29 : dim[m - 1];
}

/* The day number of year/month/day, with months and days out of range carried over. */
static int64_t civil(int64_t y, int64_t m, int64_t d)
{
    y += fdiv(m - 1, 12);
    m = fmod64(m - 1, 12) + 1;
    return FDaysFromCivil(y, (int)m, 1) + d - 1;
}

/* The first day of week 1 of a year: the first week, starting on the first
 * weekday, with at least `min` days in the year. */
static int64_t week1(int64_t y, int first, int min)
{
    int64_t jan1 = FDaysFromCivil(y, 1, 1);
    int before = (weekday_of(jan1) - first + 7) % 7;
    int64_t start = jan1 - before;
    return 7 - before >= min ? start : start + 7;
}

/* ---- a time taken apart ------------------------------------------------------------------ */

struct fields {
    int64_t days, sod, ns;   /* local day number, seconds into the day, nanoseconds */
    int64_t year, eyear, wyear;
    int era, month, day, hour, minute, second, weekday, ordinal, quarter, yday, week, wmonth, dim;
};

static void fill_day(struct fields *p, int64_t days, int first, int min)
{
    p->days = days;
    FCivilFromDays(days, &p->year, &p->month, &p->day);
    p->era = p->year > 0;
    p->eyear = p->year > 0 ? p->year : 1 - p->year;
    p->weekday = weekday_of(days);
    p->ordinal = (p->day - 1) / 7 + 1;
    p->quarter = (p->month - 1) / 3 + 1;
    p->yday = (int)(days - FDaysFromCivil(p->year, 1, 1)) + 1;
    p->dim = days_in_month(p->year, p->month);
    int64_t s = week1(p->year, first, min);
    p->wyear = p->year;
    if (days < s) {
        p->wyear = p->year - 1;
        s = week1(p->wyear, first, min);
    } else {
        int64_t next = week1(p->year + 1, first, min);
        if (days >= next) {
            p->wyear = p->year + 1;
            s = next;
        }
    }
    p->week = (int)((days - s) / 7) + 1;
    int64_t one = days - p->day + 1;
    int before = (weekday_of(one) - first + 7) % 7;
    p->wmonth = (int)fdiv(days - (one - before), 7) + (7 - before >= min ? 1 : 0);
}

static int32_t offset_at(NSTimeZone *tz, int64_t t)
{
    int32_t off;
    BOOL dst;
    const char *abbr;
    [tz _at:t offset:&off dst:&dst abbreviation:&abbr];
    return off;
}

static void split_time(double t, NSTimeZone *tz, int first, int min, struct fields *p)
{
    double s = floor(t);
    int64_t secs = (int64_t)s, ns = lround((t - s) * 1e9);
    if (ns >= 1000000000) {
        secs++;
        ns = 0;
    }
    int64_t local = secs + offset_at(tz, secs);
    fill_day(p, fdiv(local, 86400), first, min);
    p->sod = local - p->days * 86400;
    p->ns = ns;
    p->hour = (int)(p->sod / 3600);
    p->minute = (int)(p->sod / 60 % 60);
    p->second = (int)(p->sod % 60);
}

int FLocalToUTC(NSTimeZone *tz, int64_t local, BOOL later, int gap, int64_t *out)
{
    int32_t before = offset_at(tz, local - 86400), after = offset_at(tz, local + 86400);
    int64_t t1 = local - before, t2 = local - after;
    BOOL v1 = offset_at(tz, t1) == before, v2 = offset_at(tz, t2) == after;
    if (v1 && v2) {
        *out = later ? (t1 > t2 ? t1 : t2) : (t1 < t2 ? t1 : t2);
        return 0;
    }
    if (v1 || v2) {
        *out = v1 ? t1 : t2;
        return 0;
    }
    if (before >= after) {   /* two changes close together: the plain answer */
        *out = local - offset_at(tz, local - offset_at(tz, local));
        return 0;
    }
    if (gap == 1) {   /* the moment the clocks jump */
        int64_t lo = t2, hi = t1;
        while (hi - lo > 1) {
            int64_t mid = lo + (hi - lo) / 2;
            if (offset_at(tz, mid) == after)
                hi = mid;
            else
                lo = mid;
        }
        *out = hi;
    } else {
        *out = gap == 2 ? t2 : t1;
    }
    return 1;
}

/* ---- NSDateComponents ---------------------------------------------------------------------- */

static int unit_bit(NSCalendarUnit u) { return u ? __builtin_ctzl(u) : 0; }

@implementation NSDateComponents {
    NSInteger _v[NBITS];
    NSCalendar *_calendar;
    NSTimeZone *_timeZone;
    BOOL _leap;
}

static NSInteger *values(NSDateComponents *c) { return c->_v; }

- (instancetype)init
{
    /* copied from a table: a filling loop would become memset_pattern16, which Ferry's libc lacks */
    static const NSInteger undefined[NBITS] = {[0 ... NBITS - 1] = UNDEF};
    if ((self = [super init]))
        memcpy(_v, undefined, sizeof _v);
    return self;
}

- (void)dealloc
{
    [_calendar release];
    [_timeZone release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSDateComponents *c = [[NSDateComponents alloc] init];
    memcpy(c->_v, _v, sizeof _v);
    c->_calendar = [_calendar copy];
    c->_timeZone = [_timeZone retain];
    c->_leap = _leap;
    return c;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSDateComponents class]])
        return NO;
    NSDateComponents *o = other;
    return !memcmp(_v, o->_v, sizeof _v) && _leap == o->_leap &&
           (_calendar == o->_calendar || [_calendar isEqual:o->_calendar]) &&
           (_timeZone == o->_timeZone || [_timeZone isEqual:o->_timeZone]);
}

- (NSUInteger)hash
{
    NSUInteger h = 0;
    for (int i = 0; i < NBITS; i++)
        h = h * 31 + (NSUInteger)_v[i];
    return h;
}

- (NSCalendar *)calendar { return _calendar; }
- (void)setCalendar:(NSCalendar *)c
{
    c = [c copy];
    [_calendar release];
    _calendar = c;
}
- (NSTimeZone *)timeZone { return _timeZone; }
- (void)setTimeZone:(NSTimeZone *)z
{
    [z retain];
    [_timeZone release];
    _timeZone = z;
}

#define COMPONENT(get, set, unit)                                                                                      \
    -(NSInteger)get { return _v[unit_bit(unit)]; }                                                                     \
    -(void)set:(NSInteger)v { _v[unit_bit(unit)] = v; }
COMPONENT(era, setEra, NSCalendarUnitEra)
COMPONENT(year, setYear, NSCalendarUnitYear)
COMPONENT(month, setMonth, NSCalendarUnitMonth)
COMPONENT(day, setDay, NSCalendarUnitDay)
COMPONENT(hour, setHour, NSCalendarUnitHour)
COMPONENT(minute, setMinute, NSCalendarUnitMinute)
COMPONENT(second, setSecond, NSCalendarUnitSecond)
COMPONENT(nanosecond, setNanosecond, NSCalendarUnitNanosecond)
COMPONENT(weekday, setWeekday, NSCalendarUnitWeekday)
COMPONENT(weekdayOrdinal, setWeekdayOrdinal, NSCalendarUnitWeekdayOrdinal)
COMPONENT(quarter, setQuarter, NSCalendarUnitQuarter)
COMPONENT(weekOfMonth, setWeekOfMonth, NSCalendarUnitWeekOfMonth)
COMPONENT(weekOfYear, setWeekOfYear, NSCalendarUnitWeekOfYear)
COMPONENT(yearForWeekOfYear, setYearForWeekOfYear, NSCalendarUnitYearForWeekOfYear)
COMPONENT(dayOfYear, setDayOfYear, NSCalendarUnitDayOfYear)
COMPONENT(week, setWeek, NSWeekCalendarUnit)
#undef COMPONENT

- (BOOL)isLeapMonth { return _leap; }
- (void)setLeapMonth:(BOOL)b { _leap = b; }

static BOOL one_unit(NSCalendarUnit u) { return u && !(u & (u - 1)) && unit_bit(u) < NBITS && unit_bit(u) > 0; }

- (void)setValue:(NSInteger)value forComponent:(NSCalendarUnit)unit
{
    if (one_unit(unit))
        _v[unit_bit(unit)] = value;
    else if (unit == NSCalendarUnitCalendar || unit == NSCalendarUnitTimeZone)
        ; /* not numbers */
}

- (NSInteger)valueForComponent:(NSCalendarUnit)unit { return one_unit(unit) ? _v[unit_bit(unit)] : UNDEF; }

- (NSDate *)date
{
    if (!_calendar)
        return nil;
    return [_calendar dateFromComponents:self];
}

- (BOOL)isValidDateInCalendar:(NSCalendar *)cal
{
    if (!cal)
        return NO;
    NSDate *d = [cal dateFromComponents:self];
    if (!d)
        return NO;
    NSCalendarUnit units = 0;
    for (int i = 1; i < NBITS; i++)
        if (_v[i] != UNDEF)
            units |= 1UL << i;
    NSCalendar *in = cal;
    if (_timeZone) {
        in = [[cal copy] autorelease];
        [in setTimeZone:_timeZone];
    }
    NSDateComponents *back = [in components:units fromDate:d];
    for (int i = 1; i < NBITS; i++)
        if (_v[i] != UNDEF && back->_v[i] != _v[i])
            return NO;
    return YES;
}

- (BOOL)isValidDate { return [self isValidDateInCalendar:_calendar]; }

- (NSString *)description
{
    static const char *const names[NBITS] = {NULL,          "era",        "year",        "month",
                                             "day",         "hour",       "minute",      "second",
                                             "week",        "weekday",    "weekdayOrdinal", "quarter",
                                             "weekOfMonth", "weekOfYear", "yearForWeekOfYear", "nanosecond",
                                             "dayOfYear"};
    NSMutableString *s = [NSMutableString stringWithFormat:@"<%s: %p> {", object_getClassName(self), self];
    if (_calendar)
        [s appendFormat:@"\n    calendar: %@", [_calendar calendarIdentifier]];
    if (_timeZone)
        [s appendFormat:@"\n    timeZone: %@", [_timeZone name]];
    for (int i = 1; i < NBITS; i++)
        if (_v[i] != UNDEF)
            [s appendFormat:@"\n    %s: %ld", names[i], (long)_v[i]];
    if (_leap)
        [s appendString:@"\n    leapMonth: 1"];
    [s appendString:@" }"];
    return s;
}
@end

/* ---- NSCalendar ---------------------------------------------------------------------------- */

/* From the Unicode CLDR's week data: where weeks start on Sunday, Saturday
 * or Friday (Monday elsewhere), and where the first week of a year needs
 * four days in it (one elsewhere). */
static const char sunday_first[] = "AG AS BD BR BS BT BW BZ CA CN CO DM DO ET GT GU HK HN ID IL IN JM JP KE KH KR LA "
                                   "MH MM MO MT MX MZ NI NP PA PE PH PK PR PT PY SA SG SV TH TT TW UM US VE VI WS YE "
                                   "ZA ZW ";
static const char saturday_first[] = "AE AF BH DJ DZ EG IQ IR JO KW LY OM QA SD SY ";
static const char friday_first[] = "MV ";
static const char four_days[] = "AD AN AT AX BE BG CH CZ DE DK EE ES FI FJ FO FR GB GF GG GI GP GR HU IE IM IS IT JE "
                                "LI LT LU MC MQ NL NO PL PT RE RU SE SJ SK SM VA ";

static BOOL listed(const char *list, NSString *country)
{
    if ([country length] != 2)
        return NO;
    char key[4] = {(char)[country characterAtIndex:0], (char)[country characterAtIndex:1], ' ', 0};
    for (const char *p = list; *p; p += 3)
        if (!strncmp(p, key, 3))
            return YES;
    return NO;
}

static NSString *region_of(NSLocale *l)
{
    NSString *c = [l countryCode];
    if (c)
        return c;
    NSString *lang = [l languageCode];
    return !lang || [lang isEqualToString:@"en"] ? @"US" : nil;   /* English is likely American */
}

@implementation NSCalendar {
    NSString *_ident;
    NSLocale *_locale;
    NSTimeZone *_tz;
    NSUInteger _first, _min;
    BOOL _firstSet, _minSet;
}

+ (NSCalendar *)currentCalendar
{
    NSString *ident = [[NSLocale currentLocale] calendarIdentifier];
    NSCalendar *c = [[[NSCalendar alloc] initWithCalendarIdentifier:ident] autorelease];
    if (!c)
        c = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
    return c;
}

+ (NSCalendar *)autoupdatingCurrentCalendar { return [self currentCalendar]; }

+ (NSCalendar *)calendarWithIdentifier:(NSCalendarIdentifier)ident
{
    return [[[self alloc] initWithCalendarIdentifier:ident] autorelease];
}

- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)ident
{
    if (![ident isEqualToString:NSCalendarIdentifierGregorian] && ![ident isEqualToString:NSCalendarIdentifierISO8601]) {
        [self release];
        return nil;
    }
    if ((self = [super init])) {
        _ident = [ident copy];
        _locale = [[NSLocale currentLocale] retain];
        _tz = [[NSTimeZone defaultTimeZone] retain];
        [self _weeksFromLocale];
    }
    return self;
}

- (instancetype)init { return [self initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; }

- (void)_weeksFromLocale
{
    BOOL iso = [_ident isEqualToString:NSCalendarIdentifierISO8601];
    NSString *r = region_of(_locale);
    if (!_firstSet)
        _first = iso ? 2 : listed(sunday_first, r) ? 1 : listed(saturday_first, r) ? 7 : listed(friday_first, r) ? 6 : 2;
    if (!_minSet)
        _min = iso || listed(four_days, r) ? 4 : 1;
}

- (void)dealloc
{
    [_ident release];
    [_locale release];
    [_tz release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:_ident];
    [c setLocale:_locale];
    [c setTimeZone:_tz];
    c->_first = _first;
    c->_min = _min;
    c->_firstSet = _firstSet;
    c->_minSet = _minSet;
    return c;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSCalendar class]])
        return NO;
    NSCalendar *o = other;
    return [_ident isEqualToString:o->_ident] && [_tz isEqual:o->_tz] && [_locale isEqual:o->_locale] &&
           _first == o->_first && _min == o->_min;
}
- (NSUInteger)hash { return [_ident hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s: %p> %@ (%@, %@)", object_getClassName(self), self, _ident,
                                      [_locale localeIdentifier], [_tz name]];
}

- (NSCalendarIdentifier)calendarIdentifier { return _ident; }
- (NSLocale *)locale { return _locale; }
- (void)setLocale:(NSLocale *)l
{
    l = [(l ?: [NSLocale currentLocale]) retain];
    [_locale release];
    _locale = l;
    [self _weeksFromLocale];
}
- (NSTimeZone *)timeZone { return _tz; }
- (void)setTimeZone:(NSTimeZone *)z
{
    z = [(z ?: [NSTimeZone defaultTimeZone]) retain];
    [_tz release];
    _tz = z;
}
- (NSUInteger)firstWeekday { return _first; }
- (void)setFirstWeekday:(NSUInteger)d
{
    if (d >= 1 && d <= 7) {
        _first = d;
        _firstSet = YES;
    }
}
- (NSUInteger)minimumDaysInFirstWeek { return _min; }
- (void)setMinimumDaysInFirstWeek:(NSUInteger)d
{
    if (d >= 1 && d <= 7) {
        _min = d;
        _minSet = YES;
    }
}

/* ---- symbols, English (United States) like the date formatter's ---- */

static NSDateFormatter *symbols(void)
{
    static NSDateFormatter *f;
    if (!f)
        f = [[NSDateFormatter alloc] init];
    return f;
}
- (NSArray *)eraSymbols { return [symbols() eraSymbols]; }
- (NSArray *)longEraSymbols { return [symbols() longEraSymbols]; }
- (NSArray *)monthSymbols { return [symbols() monthSymbols]; }
- (NSArray *)shortMonthSymbols { return [symbols() shortMonthSymbols]; }
- (NSArray *)veryShortMonthSymbols { return [symbols() veryShortMonthSymbols]; }
- (NSArray *)standaloneMonthSymbols { return [symbols() standaloneMonthSymbols]; }
- (NSArray *)shortStandaloneMonthSymbols { return [symbols() shortStandaloneMonthSymbols]; }
- (NSArray *)veryShortStandaloneMonthSymbols { return [symbols() veryShortStandaloneMonthSymbols]; }
- (NSArray *)weekdaySymbols { return [symbols() weekdaySymbols]; }
- (NSArray *)shortWeekdaySymbols { return [symbols() shortWeekdaySymbols]; }
- (NSArray *)veryShortWeekdaySymbols { return [symbols() veryShortWeekdaySymbols]; }
- (NSArray *)standaloneWeekdaySymbols { return [symbols() standaloneWeekdaySymbols]; }
- (NSArray *)shortStandaloneWeekdaySymbols { return [symbols() shortStandaloneWeekdaySymbols]; }
- (NSArray *)veryShortStandaloneWeekdaySymbols { return [symbols() veryShortStandaloneWeekdaySymbols]; }
- (NSArray *)quarterSymbols { return [symbols() quarterSymbols]; }
- (NSArray *)shortQuarterSymbols { return [symbols() shortQuarterSymbols]; }
- (NSArray *)standaloneQuarterSymbols { return [symbols() standaloneQuarterSymbols]; }
- (NSArray *)shortStandaloneQuarterSymbols { return [symbols() shortStandaloneQuarterSymbols]; }
- (NSString *)AMSymbol { return [symbols() AMSymbol]; }
- (NSString *)PMSymbol { return [symbols() PMSymbol]; }

/* ---- taking dates apart ---- */

- (void)_split:(NSDate *)date zone:(NSTimeZone *)tz into:(struct fields *)p
{
    split_time([date timeIntervalSince1970], tz ?: _tz, (int)_first, (int)_min, p);
}

- (void)_day:(int64_t)days into:(struct fields *)p { fill_day(p, days, (int)_first, (int)_min); }

/* The instant of a local wall-clock time, with the usual answers for times
 * that happen twice or not at all. */
- (double)_utc:(int64_t)local zone:(NSTimeZone *)tz
{
    int64_t t;
    FLocalToUTC(tz ?: _tz, local, NO, 0, &t);
    return (double)t;
}

- (NSDateComponents *)_components:(NSCalendarUnit)units of:(const struct fields *)p zone:(NSTimeZone *)tz
{
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    NSInteger *v = values(c);
#define SET(u, x)                                                                                                      \
    if (units & (u))                                                                                                   \
        v[unit_bit(u)] = (NSInteger)(x);
    SET(NSCalendarUnitEra, p->era)
    SET(NSCalendarUnitYear, p->eyear)
    SET(NSCalendarUnitMonth, p->month)
    SET(NSCalendarUnitDay, p->day)
    SET(NSCalendarUnitHour, p->hour)
    SET(NSCalendarUnitMinute, p->minute)
    SET(NSCalendarUnitSecond, p->second)
    SET(NSCalendarUnitNanosecond, p->ns)
    SET(NSCalendarUnitWeekday, p->weekday)
    SET(NSCalendarUnitWeekdayOrdinal, p->ordinal)
    SET(NSCalendarUnitQuarter, p->quarter)
    SET(NSCalendarUnitWeekOfMonth, p->wmonth)
    SET(NSCalendarUnitWeekOfYear, p->week)
    SET(NSWeekCalendarUnit, p->week)
    SET(NSCalendarUnitYearForWeekOfYear, p->wyear)
    SET(NSCalendarUnitDayOfYear, p->yday)
#undef SET
    if (units & NSCalendarUnitCalendar)
        [c setCalendar:self];
    if (units & NSCalendarUnitTimeZone)
        [c setTimeZone:tz];
    return c;
}

- (NSDateComponents *)components:(NSCalendarUnit)units fromDate:(NSDate *)date
{
    if (!date)
        return nil;
    struct fields p;
    [self _split:date zone:_tz into:&p];
    return [self _components:units of:&p zone:_tz];
}

- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date
{
    return [[self components:unit fromDate:date] valueForComponent:unit];
}

- (NSDateComponents *)componentsInTimeZone:(NSTimeZone *)zone fromDate:(NSDate *)date
{
    if (!date)
        return nil;
    struct fields p;
    [self _split:date zone:zone into:&p];
    NSCalendar *c = [[self copy] autorelease];
    [c setTimeZone:zone ?: _tz];
    return [c _components:(1UL << NBITS) - 2 | NSCalendarUnitCalendar | NSCalendarUnitTimeZone of:&p
                     zone:zone ?: _tz];
}

- (void)getEra:(NSInteger *)era year:(NSInteger *)year month:(NSInteger *)month day:(NSInteger *)day
      fromDate:(NSDate *)date
{
    struct fields p;
    [self _split:date zone:_tz into:&p];
    if (era)
        *era = p.era;
    if (year)
        *year = (NSInteger)p.eyear;
    if (month)
        *month = p.month;
    if (day)
        *day = p.day;
}

- (void)getEra:(NSInteger *)era yearForWeekOfYear:(NSInteger *)year weekOfYear:(NSInteger *)week
       weekday:(NSInteger *)weekday fromDate:(NSDate *)date
{
    struct fields p;
    [self _split:date zone:_tz into:&p];
    if (era)
        *era = p.era;
    if (year)
        *year = (NSInteger)p.wyear;
    if (week)
        *week = p.week;
    if (weekday)
        *weekday = p.weekday;
}

- (void)getHour:(NSInteger *)hour minute:(NSInteger *)minute second:(NSInteger *)second
     nanosecond:(NSInteger *)ns fromDate:(NSDate *)date
{
    struct fields p;
    [self _split:date zone:_tz into:&p];
    if (hour)
        *hour = p.hour;
    if (minute)
        *minute = p.minute;
    if (second)
        *second = p.second;
    if (ns)
        *ns = (NSInteger)p.ns;
}

/* ---- putting dates together ---- */

#define DEF(v, u) ((v)[unit_bit(u)] != UNDEF)
#define GET(v, u, dflt) (DEF(v, u) ? (int64_t)(v)[unit_bit(u)] : (int64_t)(dflt))

/* The first day of week `w` of week-based year `wy`, plus the weekday. */
- (int64_t)_dayOfWeek:(int64_t)w year:(int64_t)wy weekday:(int64_t)wd
{
    return week1(wy, (int)_first, (int)_min) + (w - 1) * 7 + fmod64(wd - (int64_t)_first, 7);
}

- (NSDate *)dateFromComponents:(NSDateComponents *)comps
{
    if (!comps)
        return nil;
    const NSInteger *v = values(comps);
    for (int i = 1; i < NBITS; i++)
        if (v[i] != UNDEF && (v[i] > 100000000000LL || v[i] < -100000000000LL))
            return nil;   /* too far to count in seconds */
    int64_t first = (int64_t)_first, days;
    int64_t woy = DEF(v, NSCalendarUnitWeekOfYear) ? v[unit_bit(NSCalendarUnitWeekOfYear)]
                                                    : GET(v, NSWeekCalendarUnit, UNDEF);
    BOOL dateless = !DEF(v, NSCalendarUnitMonth) && !DEF(v, NSCalendarUnitDay) && !DEF(v, NSCalendarUnitDayOfYear);
    int64_t year = GET(v, NSCalendarUnitYear, 1);
    if (GET(v, NSCalendarUnitEra, 1) == 0)
        year = 1 - year;
    int64_t wd = GET(v, NSCalendarUnitWeekday, first);
    if (dateless && DEF(v, NSCalendarUnitYearForWeekOfYear) && (woy != UNDEF || !DEF(v, NSCalendarUnitYear))) {
        days = [self _dayOfWeek:woy != UNDEF ? woy : 1 year:v[unit_bit(NSCalendarUnitYearForWeekOfYear)] weekday:wd];
    } else if (DEF(v, NSCalendarUnitMonth) || DEF(v, NSCalendarUnitDay)) {
        int64_t month = GET(v, NSCalendarUnitMonth, 1);
        int64_t one = civil(year, month, 1);
        if (DEF(v, NSCalendarUnitDay)) {
            days = one + v[unit_bit(NSCalendarUnitDay)] - 1;
        } else if (DEF(v, NSCalendarUnitWeekday) && DEF(v, NSCalendarUnitWeekdayOrdinal)) {
            int64_t ord = v[unit_bit(NSCalendarUnitWeekdayOrdinal)];
            if (ord < 0) {   /* counted from the end of the month */
                int64_t y2 = year + fdiv(month - 1, 12);
                int m2 = (int)fmod64(month - 1, 12) + 1;
                int64_t last = one + days_in_month(y2, m2) - 1;
                days = last - fmod64(weekday_of(last) - wd, 7) + (ord + 1) * 7;
            } else {
                days = one + fmod64(wd - weekday_of(one), 7) + (ord - 1) * 7;
            }
        } else if (DEF(v, NSCalendarUnitWeekOfMonth)) {
            int before = (weekday_of(one) - (int)first + 7) % 7;
            int64_t w = v[unit_bit(NSCalendarUnitWeekOfMonth)] - (7 - before >= (int)_min ? 1 : 0);
            days = one - before + w * 7 + fmod64(wd - first, 7);
        } else {
            days = one;
        }
    } else if (DEF(v, NSCalendarUnitDayOfYear)) {
        days = civil(year, 1, 1) + v[unit_bit(NSCalendarUnitDayOfYear)] - 1;
    } else if (woy != UNDEF) {
        days = [self _dayOfWeek:woy year:year weekday:wd];
    } else if (DEF(v, NSCalendarUnitWeekday) && DEF(v, NSCalendarUnitWeekdayOrdinal)) {
        int64_t one = civil(year, 1, 1);
        days = one + fmod64(wd - weekday_of(one), 7) + (v[unit_bit(NSCalendarUnitWeekdayOrdinal)] - 1) * 7;
    } else {
        days = civil(year, 1, 1);
    }
    int64_t local = days * 86400 + GET(v, NSCalendarUnitHour, 0) * 3600 + GET(v, NSCalendarUnitMinute, 0) * 60 +
                    GET(v, NSCalendarUnitSecond, 0);
    double t = [self _utc:local zone:[comps timeZone]];
    return [NSDate dateWithTimeIntervalSince1970:t + (double)GET(v, NSCalendarUnitNanosecond, 0) / 1e9];
}

- (NSDate *)dateWithEra:(NSInteger)era year:(NSInteger)year month:(NSInteger)month day:(NSInteger)day
                   hour:(NSInteger)hour minute:(NSInteger)minute second:(NSInteger)second
             nanosecond:(NSInteger)ns
{
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setEra:era];
    [c setYear:year];
    [c setMonth:month];
    [c setDay:day];
    [c setHour:hour];
    [c setMinute:minute];
    [c setSecond:second];
    [c setNanosecond:ns];
    return [self dateFromComponents:c];
}

- (NSDate *)dateWithEra:(NSInteger)era yearForWeekOfYear:(NSInteger)year weekOfYear:(NSInteger)week
                weekday:(NSInteger)weekday hour:(NSInteger)hour minute:(NSInteger)minute
                 second:(NSInteger)second nanosecond:(NSInteger)ns
{
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setEra:era];
    [c setYearForWeekOfYear:year];
    [c setWeekOfYear:week];
    [c setWeekday:weekday];
    [c setHour:hour];
    [c setMinute:minute];
    [c setSecond:second];
    [c setNanosecond:ns];
    return [self dateFromComponents:c];
}

/* ---- arithmetic ---- */

/* t moved by months and days on the wall clock, the day kept within the month. */
- (double)_add:(double)t months:(int64_t)months days:(int64_t)days
{
    if (!months && !days)
        return t;
    struct fields p;
    split_time(t, _tz, (int)_first, (int)_min, &p);
    int64_t total = p.year * 12 + (p.month - 1) + months, y = fdiv(total, 12);
    int m = (int)fmod64(total, 12) + 1, d = p.day;
    if (d > days_in_month(y, m))
        d = days_in_month(y, m);
    int64_t local = (FDaysFromCivil(y, m, d) + days) * 86400 + p.sod;
    return [self _utc:local zone:_tz] + (double)p.ns / 1e9;
}

- (NSDate *)dateByAddingComponents:(NSDateComponents *)comps toDate:(NSDate *)date options:(NSCalendarOptions)opts
{
    if (!comps || !date)
        return nil;
    const NSInteger *v = values(comps);
    for (int i = 1; i < NBITS; i++)
        if (v[i] != UNDEF && (v[i] > 100000000000LL || v[i] < -100000000000LL))
            return nil;
    double t = [date timeIntervalSince1970];
    int64_t years = GET(v, NSCalendarUnitYear, 0) + GET(v, NSCalendarUnitYearForWeekOfYear, 0);
    int64_t months = GET(v, NSCalendarUnitMonth, 0) + 3 * GET(v, NSCalendarUnitQuarter, 0);
    int64_t days = GET(v, NSCalendarUnitDay, 0) + GET(v, NSCalendarUnitWeekday, 0) + GET(v, NSCalendarUnitDayOfYear, 0) +
                   7 * (GET(v, NSCalendarUnitWeekOfYear, 0) + GET(v, NSCalendarUnitWeekOfMonth, 0) +
                        GET(v, NSWeekCalendarUnit, 0) + GET(v, NSCalendarUnitWeekdayOrdinal, 0));
    int64_t hours = GET(v, NSCalendarUnitHour, 0), minutes = GET(v, NSCalendarUnitMinute, 0);
    int64_t seconds = GET(v, NSCalendarUnitSecond, 0), ns = GET(v, NSCalendarUnitNanosecond, 0);
    int64_t eras = GET(v, NSCalendarUnitEra, 0);
    struct fields p;
    split_time(t, _tz, (int)_first, (int)_min, &p);
    if (eras) {   /* the same year of the other era */
        int e = eras > 0 ? 1 : 0;
        if (e != p.era)
            years += e ? 2 * p.eyear - 1 : 1 - 2 * p.eyear;
    }
    if (opts & NSCalendarWrapComponents) {
        /* each unit turns within the next larger one */
        int64_t y = p.year + years;
        int m = (int)fmod64(p.month - 1 + months, 12) + 1;
        int dim = days_in_month(y, m), d = p.day > dim ? dim : p.day;
        d = (int)fmod64(d - 1 + days, dim) + 1;
        int64_t h = fmod64(p.hour + hours, 24), mi = fmod64(p.minute + minutes, 60);
        int64_t s = fmod64(p.second + seconds, 60), n = fmod64(p.ns + ns, 1000000000);
        int64_t local = FDaysFromCivil(y, m, d) * 86400 + h * 3600 + mi * 60 + s;
        if (!years && !months && !days && !hours && !minutes && !seconds && !ns)
            return [[date retain] autorelease];
        return [NSDate dateWithTimeIntervalSince1970:[self _utc:local zone:_tz] + (double)n / 1e9];
    }
    t = [self _add:t months:years * 12 + months days:days];
    t += (double)(hours * 3600 + minutes * 60 + seconds) + (double)ns / 1e9;
    return [NSDate dateWithTimeIntervalSince1970:t];
}

- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)value toDate:(NSDate *)date
                     options:(NSCalendarOptions)opts
{
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setValue:value forComponent:unit];
    return [self dateByAddingComponents:c toDate:date options:opts];
}

/* The difference, from the largest unit asked for down: each unit is the
 * most whole ones that fit, and the rest goes to the smaller units. */
- (NSDateComponents *)components:(NSCalendarUnit)units fromDate:(NSDate *)start toDate:(NSDate *)end
                         options:(NSCalendarOptions)opts
{
    if (!start || !end)
        return nil;
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    NSInteger *v = values(c);
    double cur = [start timeIntervalSince1970], to = [end timeIntervalSince1970];
    if (units & NSCalendarUnitEra) {
        struct fields a, b;
        split_time(cur, _tz, (int)_first, (int)_min, &a);
        split_time(to, _tz, (int)_first, (int)_min, &b);
        v[unit_bit(NSCalendarUnitEra)] = b.era - a.era;
    }
    static const struct {
        NSCalendarUnit units;
        int64_t months, days;
        double length;
    } groups[] = {
        {NSCalendarUnitYear | NSCalendarUnitYearForWeekOfYear, 12, 0, 365.2425 * 86400},
        {NSCalendarUnitQuarter, 3, 0, 91.310625 * 86400},
        {NSCalendarUnitMonth, 1, 0, 30.436875 * 86400},
        {NSCalendarUnitWeekOfYear | NSCalendarUnitWeekOfMonth | NSWeekCalendarUnit | NSCalendarUnitWeekdayOrdinal, 0, 7,
         7 * 86400},
        {NSCalendarUnitDay | NSCalendarUnitWeekday | NSCalendarUnitDayOfYear, 0, 1, 86400},
    };
    for (unsigned g = 0; g < sizeof groups / sizeof groups[0]; g++) {
        NSCalendarUnit asked = units & groups[g].units;
        if (!asked)
            continue;
        int64_t n = (int64_t)((to - cur) / groups[g].length), mo = groups[g].months, dd = groups[g].days;
#define AT(k) [self _add:cur months:mo * (k) days:dd * (k)]
        if (to >= cur) {
            if (n < 0)
                n = 0;
            while (AT(n + 1) <= to)
                n++;
            while (n > 0 && AT(n) > to)
                n--;
        } else {
            if (n > 0)
                n = 0;
            while (AT(n - 1) >= to)
                n--;
            while (n < 0 && AT(n) < to)
                n++;
        }
        cur = AT(n);
#undef AT
        BOOL firstOne = YES;
        for (int i = 1; i < NBITS; i++)
            if (asked & (1UL << i)) {
                v[i] = firstOne ? (NSInteger)n : 0;
                firstOne = NO;
            }
    }
    double rest = to - cur;
    static const struct {
        NSCalendarUnit unit;
        double length;
    } times[] = {{NSCalendarUnitHour, 3600}, {NSCalendarUnitMinute, 60}, {NSCalendarUnitSecond, 1}};
    for (unsigned i = 0; i < 3; i++)
        if (units & times[i].unit) {
            int64_t n = (int64_t)(rest / times[i].length);
            if (fabs(rest - (double)(n + (rest < 0 ? -1 : 1)) * times[i].length) < 1e-7)
                n += rest < 0 ? -1 : 1;   /* a whole unit short only by rounding */
            v[unit_bit(times[i].unit)] = (NSInteger)n;
            rest -= (double)n * times[i].length;
        }
    if (units & NSCalendarUnitNanosecond)
        v[unit_bit(NSCalendarUnitNanosecond)] = (NSInteger)lround(rest * 1e9);
    if (units & NSCalendarUnitCalendar)
        [c setCalendar:self];
    if (units & NSCalendarUnitTimeZone)
        [c setTimeZone:_tz];
    return c;
}

- (NSDateComponents *)components:(NSCalendarUnit)units fromDateComponents:(NSDateComponents *)start
                toDateComponents:(NSDateComponents *)end
                         options:(NSCalendarOptions)opts
{
    NSDate *a = [self dateFromComponents:start], *b = [self dateFromComponents:end];
    if (!a || !b)
        return nil;
    return [self components:units fromDate:a toDate:b options:opts];
}

/* ---- units of time ---- */

/* The local wall-clock start and end of the unit holding t (days and
 * larger), or NO. */
- (BOOL)_unit:(NSCalendarUnit)unit at:(double)t start:(int64_t *)from end:(int64_t *)to
{
    struct fields p;
    split_time(t, _tz, (int)_first, (int)_min, &p);
    int64_t a, b;
    switch (unit) {
    case NSCalendarUnitEra:
        if (p.era) {
            a = FDaysFromCivil(1, 1, 1);
            b = FDaysFromCivil(144684, 1, 1);
        } else {
            a = FDaysFromCivil(-144683, 1, 1);
            b = FDaysFromCivil(1, 1, 1);
        }
        break;
    case NSCalendarUnitYear:
        a = FDaysFromCivil(p.year, 1, 1);
        b = FDaysFromCivil(p.year + 1, 1, 1);
        break;
    case NSCalendarUnitYearForWeekOfYear:
        a = week1(p.wyear, (int)_first, (int)_min);
        b = week1(p.wyear + 1, (int)_first, (int)_min);
        break;
    case NSCalendarUnitQuarter:
        a = civil(p.year, (p.quarter - 1) * 3 + 1, 1);
        b = civil(p.year, p.quarter * 3 + 1, 1);
        break;
    case NSCalendarUnitMonth:
        a = civil(p.year, p.month, 1);
        b = civil(p.year, p.month + 1, 1);
        break;
    case NSCalendarUnitWeekOfYear:
    case NSCalendarUnitWeekOfMonth:
    case NSWeekCalendarUnit:
        a = p.days - (p.weekday - (int)_first + 7) % 7;
        b = a + 7;
        break;
    case NSCalendarUnitDay:
    case NSCalendarUnitWeekday:
    case NSCalendarUnitDayOfYear:
    case NSCalendarUnitWeekdayOrdinal:
        a = p.days;
        b = a + 1;
        break;
    default:
        return NO;
    }
    *from = a * 86400;
    *to = b * 86400;
    return YES;
}

static double elapsed_length(NSCalendarUnit unit)
{
    switch (unit) {
    case NSCalendarUnitHour: return 3600;
    case NSCalendarUnitMinute: return 60;
    case NSCalendarUnitSecond: return 1;
    case NSCalendarUnitNanosecond: return 1e-9;
    default: return 0;
    }
}

- (BOOL)rangeOfUnit:(NSCalendarUnit)unit startDate:(NSDate **)start interval:(NSTimeInterval *)interval
            forDate:(NSDate *)date
{
    if (!date)
        return NO;
    double t = [date timeIntervalSince1970], s, e;
    double len = elapsed_length(unit);
    if (len >= 1) {   /* hours, minutes and seconds, as the wall clock shows them */
        int64_t secs = (int64_t)floor(t), local = secs + offset_at(_tz, secs);
        s = (double)(secs - fmod64(local, (int64_t)len));
        e = s + len;
    } else if (len) {
        s = t;
        e = t + len;
    } else {
        int64_t a, b;
        if (![self _unit:unit at:t start:&a end:&b])
            return NO;
        s = [self _utc:a zone:_tz];
        e = [self _utc:b zone:_tz];
    }
    if (start)
        *start = [NSDate dateWithTimeIntervalSince1970:s];
    if (interval)
        *interval = e - s;
    return YES;
}

- (NSDate *)startOfDayForDate:(NSDate *)date
{
    NSDate *s = nil;
    [self rangeOfUnit:NSCalendarUnitDay startDate:&s interval:NULL forDate:date];
    return s;
}

- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)unit
{
    switch (unit) {
    case NSCalendarUnitEra: return NSMakeRange(0, 2);
    case NSCalendarUnitYear: case NSCalendarUnitYearForWeekOfYear: return NSMakeRange(1, 140742);
    case NSCalendarUnitMonth: return NSMakeRange(1, 12);
    case NSCalendarUnitDay: return NSMakeRange(1, 28);
    case NSCalendarUnitHour: return NSMakeRange(0, 24);
    case NSCalendarUnitMinute: case NSCalendarUnitSecond: return NSMakeRange(0, 60);
    case NSCalendarUnitNanosecond: return NSMakeRange(0, 1000000000);
    case NSCalendarUnitWeekday: return NSMakeRange(1, 7);
    case NSCalendarUnitWeekdayOrdinal: return NSMakeRange(1, 4);
    case NSCalendarUnitQuarter: return NSMakeRange(1, 4);
    case NSCalendarUnitWeekOfMonth: return _min == 1 ? NSMakeRange(1, 4) : NSMakeRange(0, 5);
    case NSCalendarUnitWeekOfYear: case NSWeekCalendarUnit: return NSMakeRange(1, 52);
    case NSCalendarUnitDayOfYear: return NSMakeRange(1, 365);
    default: return NSMakeRange(NSNotFound, NSNotFound);
    }
}

- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)unit
{
    switch (unit) {
    case NSCalendarUnitYear: case NSCalendarUnitYearForWeekOfYear: return NSMakeRange(1, 144683);
    case NSCalendarUnitDay: return NSMakeRange(1, 31);
    case NSCalendarUnitWeekdayOrdinal: return NSMakeRange(1, 5);
    case NSCalendarUnitWeekOfMonth: return _min == 1 ? NSMakeRange(1, 6) : NSMakeRange(0, 6);
    case NSCalendarUnitWeekOfYear: case NSWeekCalendarUnit: return NSMakeRange(1, 53);
    case NSCalendarUnitDayOfYear: return NSMakeRange(1, 366);
    default: return [self minimumRangeOfUnit:unit];
    }
}

static int rank_of(NSCalendarUnit u)
{
    switch (u) {
    case NSCalendarUnitEra: return 9;
    case NSCalendarUnitYear: case NSCalendarUnitYearForWeekOfYear: return 8;
    case NSCalendarUnitQuarter: return 7;
    case NSCalendarUnitMonth: return 6;
    case NSCalendarUnitWeekOfYear: case NSCalendarUnitWeekOfMonth: case NSWeekCalendarUnit: return 5;
    case NSCalendarUnitDay: case NSCalendarUnitWeekday: case NSCalendarUnitDayOfYear: return 4;
    case NSCalendarUnitWeekdayOrdinal: return 4;
    case NSCalendarUnitHour: return 3;
    case NSCalendarUnitMinute: return 2;
    case NSCalendarUnitSecond: return 1;
    case NSCalendarUnitNanosecond: return 0;
    default: return -1;
    }
}

/* The values `smaller` takes within the `larger` unit holding the date. */
- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date
{
    NSRange none = NSMakeRange(NSNotFound, NSNotFound);
    int rs = rank_of(smaller), rl = rank_of(larger);
    if (!date || rs < 0 || rl < 0 || rs >= rl)
        return none;
    struct fields p, q;
    [self _split:date zone:_tz into:&p];
    BOOL weekly = rank_of(larger) == 5;
    switch (smaller) {
    case NSCalendarUnitHour: return NSMakeRange(0, 24);
    case NSCalendarUnitMinute: return NSMakeRange(0, 60);
    case NSCalendarUnitSecond: return NSMakeRange(0, 60);
    case NSCalendarUnitNanosecond: return NSMakeRange(0, 1000000000);
    case NSCalendarUnitWeekday:
        if (weekly)
            return NSMakeRange(1, 7);
        /* fall through: the days of the month or year */
    case NSCalendarUnitDay:
        if (weekly) {   /* the days of this week that are in its month */
            int64_t a = p.days - (p.weekday - (int)_first + 7) % 7, b = a + 6;
            int64_t one = p.days - p.day + 1, last = one + p.dim - 1;
            if (a < one)
                a = one;
            if (b > last)
                b = last;
            return NSMakeRange((NSUInteger)(a - one + 1), (NSUInteger)(b - a + 1));
        }
        if (larger == NSCalendarUnitMonth)
            return NSMakeRange(1, p.dim);
        if (larger == NSCalendarUnitQuarter) {
            int64_t a = civil(p.year, (p.quarter - 1) * 3 + 1, 1), b = civil(p.year, p.quarter * 3 + 1, 1);
            return NSMakeRange(1, (NSUInteger)(b - a));
        }
        if (larger == NSCalendarUnitYear)
            return NSMakeRange(1, leap_year(p.year) ? 366 : 365);
        return none;
    case NSCalendarUnitDayOfYear:
        return larger == NSCalendarUnitYear ? NSMakeRange(1, leap_year(p.year) ? 366 : 365) : none;
    case NSCalendarUnitWeekdayOrdinal:
        if (larger == NSCalendarUnitMonth)
            return NSMakeRange(1, (p.dim - 1) / 7 + 1);
        return none;
    case NSCalendarUnitWeekOfMonth:
    case NSCalendarUnitWeekOfYear:
    case NSWeekCalendarUnit:
        if (larger == NSCalendarUnitMonth) {
            [self _day:p.days - p.day + 1 into:&q];
            int lo = q.wmonth;
            [self _day:p.days - p.day + p.dim into:&q];
            return NSMakeRange(lo, q.wmonth - lo + 1);
        }
        if (larger == NSCalendarUnitYear) {   /* the weeks of the week-based year of that number */
            int64_t a = week1(p.year, (int)_first, (int)_min), b = week1(p.year + 1, (int)_first, (int)_min);
            return NSMakeRange(1, (NSUInteger)((b - a) / 7));
        }
        if (larger == NSCalendarUnitYearForWeekOfYear) {
            int64_t a = week1(p.wyear, (int)_first, (int)_min), b = week1(p.wyear + 1, (int)_first, (int)_min);
            return NSMakeRange(1, (NSUInteger)((b - a) / 7));
        }
        return none;
    case NSCalendarUnitMonth:
        if (larger == NSCalendarUnitQuarter)
            return NSMakeRange((p.quarter - 1) * 3 + 1, 3);
        return larger == NSCalendarUnitYear || larger == NSCalendarUnitEra ? NSMakeRange(1, 12) : none;
    case NSCalendarUnitQuarter:
        return larger == NSCalendarUnitYear || larger == NSCalendarUnitEra ? NSMakeRange(1, 4) : none;
    case NSCalendarUnitYear:
        return larger == NSCalendarUnitEra ? NSMakeRange(1, p.era ? 144683 : 144684) : none;
    default:
        return none;
    }
}

/* Which `smaller` the date falls in, counted from 1, within the `larger` unit. */
- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date
{
    int rs = rank_of(smaller), rl = rank_of(larger);
    if (!date || rs < 0 || rl < 0 || rs >= rl)
        return NSNotFound;
    double t = [date timeIntervalSince1970];
    struct fields p;
    [self _split:date zone:_tz into:&p];
    if (smaller == NSCalendarUnitWeekdayOrdinal)
        return larger == NSCalendarUnitMonth ? (NSUInteger)p.ordinal : NSNotFound;
    if (smaller == NSCalendarUnitYear || smaller == NSCalendarUnitYearForWeekOfYear)
        return (NSUInteger)p.eyear;
    NSDate *s = nil;
    if (![self rangeOfUnit:larger startDate:&s interval:NULL forDate:date])
        return NSNotFound;
    struct fields q;
    [self _split:s zone:_tz into:&q];
    switch (rs) {
    case 7: return (NSUInteger)((p.year - q.year) * 4 + (p.quarter - q.quarter) + 1);
    case 6: return (NSUInteger)((p.year - q.year) * 12 + (p.month - q.month) + 1);
    case 5: {   /* weeks counted from the one holding the start of the larger unit */
        int64_t ws = q.days - (q.weekday - (int)_first + 7) % 7;
        return (NSUInteger)((p.days - ws) / 7 + 1);
    }
    case 4: return (NSUInteger)(p.days - q.days + 1);
    default: return (NSUInteger)floor((t - [s timeIntervalSince1970]) / elapsed_length(smaller)) + 1;
    }
}

/* ---- comparing days ---- */

- (BOOL)isDate:(NSDate *)a inSameDayAsDate:(NSDate *)b
{
    if (!a || !b)
        return NO;
    struct fields p, q;
    [self _split:a zone:_tz into:&p];
    [self _split:b zone:_tz into:&q];
    return p.days == q.days;
}

- (int64_t)_dayOf:(NSDate *)d
{
    struct fields p;
    [self _split:d zone:_tz into:&p];
    return p.days;
}
- (BOOL)isDateInToday:(NSDate *)d { return d && [self _dayOf:d] == [self _dayOf:[NSDate date]]; }
- (BOOL)isDateInYesterday:(NSDate *)d { return d && [self _dayOf:d] == [self _dayOf:[NSDate date]] - 1; }
- (BOOL)isDateInTomorrow:(NSDate *)d { return d && [self _dayOf:d] == [self _dayOf:[NSDate date]] + 1; }
- (BOOL)isDateInWeekend:(NSDate *)d
{
    if (!d)
        return NO;
    int w = weekday_of([self _dayOf:d]);
    return w == 1 || w == 7;
}

- (BOOL)rangeOfWeekendStartDate:(NSDate **)start interval:(NSTimeInterval *)interval containingDate:(NSDate *)date
{
    if (![self isDateInWeekend:date])
        return NO;
    int64_t days = [self _dayOf:date];
    int64_t sat = days - (weekday_of(days) == 1 ? 1 : 0);
    double s = [self _utc:sat * 86400 zone:_tz], e = [self _utc:(sat + 2) * 86400 zone:_tz];
    if (start)
        *start = [NSDate dateWithTimeIntervalSince1970:s];
    if (interval)
        *interval = e - s;
    return YES;
}

- (BOOL)nextWeekendStartDate:(NSDate **)start interval:(NSTimeInterval *)interval options:(NSCalendarOptions)opts
                   afterDate:(NSDate *)date
{
    if (!date)
        return NO;
    int64_t days = [self _dayOf:date];
    int64_t sat = days + (7 - weekday_of(days)) % 7;   /* this week's Saturday */
    if (opts & NSCalendarSearchBackwards) {
        if (sat >= days - (weekday_of(days) == 1 ? 1 : 0))
            sat -= 7;
        if (weekday_of(days) == 1 || weekday_of(days) == 7)
            sat = days - (weekday_of(days) == 1 ? 1 : 0) - 7;
    } else if (weekday_of(days) == 7 || weekday_of(days) == 1) {
        sat = days - (weekday_of(days) == 1 ? 1 : 0) + 7;
    }
    double s = [self _utc:sat * 86400 zone:_tz], e = [self _utc:(sat + 2) * 86400 zone:_tz];
    if (start)
        *start = [NSDate dateWithTimeIntervalSince1970:s];
    if (interval)
        *interval = e - s;
    return YES;
}

- (NSComparisonResult)compareDate:(NSDate *)a toDate:(NSDate *)b toUnitGranularity:(NSCalendarUnit)unit
{
    NSDate *sa = nil, *sb = nil;
    if (unit == NSCalendarUnitNanosecond || ![self rangeOfUnit:unit startDate:&sa interval:NULL forDate:a] ||
        ![self rangeOfUnit:unit startDate:&sb interval:NULL forDate:b])
        return [a compare:b];
    return [sa compare:sb];
}

- (BOOL)isDate:(NSDate *)a equalToDate:(NSDate *)b toUnitGranularity:(NSCalendarUnit)unit
{
    return [self compareDate:a toDate:b toUnitGranularity:unit] == NSOrderedSame;
}

/* ---- matching ---- */

static BOOL day_matches(const NSInteger *v, const struct fields *p, BOOL ignoreDay)
{
#define NOT(u, x) (DEF(v, u) && v[unit_bit(u)] != (NSInteger)(x))
    if (NOT(NSCalendarUnitEra, p->era) || NOT(NSCalendarUnitYear, p->eyear) || NOT(NSCalendarUnitMonth, p->month) ||
        NOT(NSCalendarUnitWeekday, p->weekday) || NOT(NSCalendarUnitQuarter, p->quarter) ||
        NOT(NSCalendarUnitWeekOfMonth, p->wmonth) || NOT(NSCalendarUnitWeekOfYear, p->week) ||
        NOT(NSWeekCalendarUnit, p->week) || NOT(NSCalendarUnitYearForWeekOfYear, p->wyear) ||
        NOT(NSCalendarUnitDayOfYear, p->yday))
        return NO;
    if (!ignoreDay && NOT(NSCalendarUnitDay, p->day))
        return NO;
    if (DEF(v, NSCalendarUnitWeekdayOrdinal)) {
        NSInteger o = v[unit_bit(NSCalendarUnitWeekdayOrdinal)];
        if (o != p->ordinal && o != -((p->dim - p->day) / 7 + 1))
            return NO;
    }
#undef NOT
    return YES;
}

- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)comps
{
    if (!date || !comps)
        return NO;
    const NSInteger *v = values(comps);
    struct fields p;
    [self _split:date zone:_tz into:&p];
    if (!day_matches(v, &p, NO))
        return NO;
    return !((DEF(v, NSCalendarUnitHour) && v[unit_bit(NSCalendarUnitHour)] != p.hour) ||
             (DEF(v, NSCalendarUnitMinute) && v[unit_bit(NSCalendarUnitMinute)] != p.minute) ||
             (DEF(v, NSCalendarUnitSecond) && v[unit_bit(NSCalendarUnitSecond)] != p.second) ||
             (DEF(v, NSCalendarUnitNanosecond) && v[unit_bit(NSCalendarUnitNanosecond)] != p.ns));
}

/* The first time on local day `days`, in the search's order, matching the
 * time components and after (or before) `from`; gaps in the wall clock are
 * handled as the options say. NO when there is none. */
static BOOL time_on_day(NSCalendar *cal, NSTimeZone *tz, int64_t days, const NSInteger *v, NSCalendarOptions opts,
                        double from, BOOL backwards, BOOL midnightOnly, double *out)
{
    BOOL hh = DEF(v, NSCalendarUnitHour), hm = DEF(v, NSCalendarUnitMinute), hs = DEF(v, NSCalendarUnitSecond),
         hn = DEF(v, NSCalendarUnitNanosecond);
    int64_t h0 = 0, h1 = 0, m0 = 0, m1 = 0, s0 = 0, s1 = 0;
    if (!midnightOnly) {
        if (hh)
            h0 = h1 = v[unit_bit(NSCalendarUnitHour)];
        else if (hm || hs || hn)
            h1 = 23;
        if (hm)
            m0 = m1 = v[unit_bit(NSCalendarUnitMinute)];
        else if (hs || hn)
            m1 = 59;
        if (hs)
            s0 = s1 = v[unit_bit(NSCalendarUnitSecond)];
        else if (hn)
            s1 = 59;
    }
    if (h0 < 0 || h1 > 23 || m0 < 0 || m1 > 59 || s0 < 0 || s1 > 59)
        return NO;
    double ns = hn && !midnightOnly ? (double)v[unit_bit(NSCalendarUnitNanosecond)] / 1e9 : 0;
    int gap = (opts & NSCalendarMatchNextTime) ? 1 : (opts & NSCalendarMatchPreviousTimePreservingSmallerUnits) ? 2 : 0;
    int64_t n = (h1 - h0 + 1) * (m1 - m0 + 1) * (s1 - s0 + 1);
    for (int64_t k = 0; k < n; k++) {
        int64_t i = backwards ? n - 1 - k : k;
        int64_t s = s0 + i % (s1 - s0 + 1), m = m0 + i / (s1 - s0 + 1) % (m1 - m0 + 1);
        int64_t h = h0 + i / ((s1 - s0 + 1) * (m1 - m0 + 1));
        int64_t local = days * 86400 + h * 3600 + m * 60 + s, t, t2;
        if (FLocalToUTC(tz, local, NO, gap, &t)) {
            if (opts & NSCalendarMatchStrictly)
                continue;
            if (gap == 1)
                ns = 0;
            t2 = t;
        } else {
            FLocalToUTC(tz, local, YES, 0, &t2);
            if (opts & NSCalendarMatchLast)
                t = t2;
        }
        double c1 = (double)t + ns, c2 = (double)t2 + ns;
        if (backwards ? c1 < from : c1 > from) {
            *out = c1;
            return YES;
        }
        if (!(opts & NSCalendarMatchLast) && !backwards && c2 > from) {   /* the second time round */
            *out = c2;
            return YES;
        }
    }
    return NO;
}

- (NSDate *)nextDateAfterDate:(NSDate *)date matchingComponents:(NSDateComponents *)comps
                      options:(NSCalendarOptions)opts
{
    NSCalendarOptions match = opts & (NSCalendarMatchStrictly | NSCalendarMatchNextTime |
                                      NSCalendarMatchNextTimePreservingSmallerUnits |
                                      NSCalendarMatchPreviousTimePreservingSmallerUnits);
    if (!match || (match & (match - 1)))
        FRaise(NSInvalidArgumentException,
               @"-[NSCalendar nextDateAfterDate:matchingComponents:options:]: the options need exactly one of "
               @"NSCalendarMatchStrictly, NSCalendarMatchNextTime, NSCalendarMatchNextTimePreservingSmallerUnits and "
               @"NSCalendarMatchPreviousTimePreservingSmallerUnits");
    if (!date || !comps)
        return nil;
    const NSInteger *v = values(comps);
    BOOL any = NO;
    for (int i = 1; i < NBITS; i++)
        any |= v[i] != UNDEF;
    if (!any)
        return nil;
    BOOL back = (opts & NSCalendarSearchBackwards) != 0;
    double from = [date timeIntervalSince1970], out;
    struct fields p;
    [self _split:date zone:_tz into:&p];
    int64_t days = p.days;
    BOOL plainDay = DEF(v, NSCalendarUnitDay) && !DEF(v, NSCalendarUnitWeekday) &&
                    !DEF(v, NSCalendarUnitWeekdayOrdinal) && !DEF(v, NSCalendarUnitDayOfYear) &&
                    !DEF(v, NSCalendarUnitWeekOfMonth) && !DEF(v, NSCalendarUnitWeekOfYear) &&
                    !DEF(v, NSWeekCalendarUnit);
    int64_t wantYear = UNDEF;
    if (DEF(v, NSCalendarUnitYear))
        wantYear = GET(v, NSCalendarUnitEra, 1) == 0 ? 1 - v[unit_bit(NSCalendarUnitYear)] : v[unit_bit(NSCalendarUnitYear)];
    for (int iter = 0; iter < 600000; iter++) {
        [self _day:days into:&p];
        if (wantYear != UNDEF && p.year != wantYear) {   /* straight to the year asked for */
            if (back ? wantYear > p.year : wantYear < p.year)
                return nil;
            days = back ? FDaysFromCivil(wantYear, 12, 31) : FDaysFromCivil(wantYear, 1, 1);
            continue;
        }
        if (DEF(v, NSCalendarUnitMonth) && p.month != v[unit_bit(NSCalendarUnitMonth)]) {   /* or the month */
            days = back ? days - p.day : days - p.day + 1 + p.dim;
            continue;
        }
        if (day_matches(v, &p, NO)) {
            if (time_on_day(self, _tz, days, v, opts, from, back, NO, &out))
                return [NSDate dateWithTimeIntervalSince1970:out];
        } else if (plainDay && !(opts & NSCalendarMatchStrictly) && p.day == p.dim &&
                   v[unit_bit(NSCalendarUnitDay)] > p.dim && day_matches(v, &p, YES)) {
            /* the day asked for isn't in this month: the last day, or the next one */
            BOOL prev = (opts & NSCalendarMatchPreviousTimePreservingSmallerUnits) != 0;
            BOOL midnight = (opts & NSCalendarMatchNextTime) != 0;
            if (time_on_day(self, _tz, prev ? days : days + 1, v, opts, from, back, midnight, &out))
                return [NSDate dateWithTimeIntervalSince1970:out];
        }
        days += back ? -1 : 1;
    }
    return nil;
}

- (NSDate *)nextDateAfterDate:(NSDate *)date matchingUnit:(NSCalendarUnit)unit value:(NSInteger)value
                      options:(NSCalendarOptions)opts
{
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setValue:value forComponent:unit];
    return [self nextDateAfterDate:date matchingComponents:c options:opts];
}

- (NSDate *)nextDateAfterDate:(NSDate *)date matchingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s
                      options:(NSCalendarOptions)opts
{
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    if (h != UNDEF && h >= 0)
        [c setHour:h];
    if (m != UNDEF && m >= 0)
        [c setMinute:m];
    if (s != UNDEF && s >= 0)
        [c setSecond:s];
    return [self nextDateAfterDate:date matchingComponents:c options:opts];
}

- (void)enumerateDatesStartingAfterDate:(NSDate *)start matchingComponents:(NSDateComponents *)comps
                                options:(NSCalendarOptions)opts
                             usingBlock:(void (^)(NSDate *, BOOL, BOOL *))block
{
    NSDate *d = start;
    BOOL stop = NO;
    while (!stop) {
        NSDate *next = [self nextDateAfterDate:d matchingComponents:comps options:opts];
        if (!next || [next isEqualToDate:d])
            break;
        block(next, [self date:next matchesComponents:comps], &stop);
        d = next;
    }
}

/* ---- setting one unit ---- */

- (NSDate *)dateBySettingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s ofDate:(NSDate *)date
                      options:(NSCalendarOptions)opts
{
    if (!date || h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59)
        return nil;
    struct fields p;
    [self _split:date zone:_tz into:&p];
    int64_t t;
    int gap = (opts & NSCalendarMatchNextTime) ? 1 : (opts & NSCalendarMatchPreviousTimePreservingSmallerUnits) ? 2 : 0;
    if (FLocalToUTC(_tz, p.days * 86400 + h * 3600 + m * 60 + s, (opts & NSCalendarMatchLast) != 0, gap, &t) &&
        (opts & NSCalendarMatchStrictly))
        return nil;
    return [NSDate dateWithTimeIntervalSince1970:(double)t];
}

/* The unit set within the next larger one, the smaller units kept; a day
 * that doesn't exist becomes the next one that does. */
/* Apple documents this as finding the next date at which the unit has the
 * value, keeping the smaller units where it can ("if no such time exists,
 * the next available time is returned"); so a year already past gives nil. */
- (NSDate *)dateBySettingUnit:(NSCalendarUnit)unit value:(NSInteger)value ofDate:(NSDate *)date
                      options:(NSCalendarOptions)opts
{
    if (!date)
        return nil;
    if ([self component:unit fromDate:date] == value)
        return [[date retain] autorelease];
    if (unit == NSCalendarUnitNanosecond) {
        double t = floor([date timeIntervalSince1970]);
        return [NSDate dateWithTimeIntervalSince1970:t + (double)value / 1e9];
    }
    NSCalendarUnit keep = 0;
    switch (unit) {
    case NSCalendarUnitEra:
    case NSCalendarUnitYear:
        keep = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute |
               NSCalendarUnitSecond;
        break;
    case NSCalendarUnitMonth:
        keep = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
        break;
    case NSCalendarUnitHour:
        keep = NSCalendarUnitMinute | NSCalendarUnitSecond;
        break;
    case NSCalendarUnitMinute:
        keep = NSCalendarUnitSecond;
        break;
    case NSCalendarUnitSecond:
        break;
    default:   /* days, weekdays, weeks: the time of day stays */
        keep = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
        break;
    }
    NSDateComponents *c = keep ? [self components:keep fromDate:date] : [[[NSDateComponents alloc] init] autorelease];
    [c setValue:value forComponent:unit];
    NSCalendarOptions o = opts;
    if (!(o & (NSCalendarMatchStrictly | NSCalendarMatchNextTime | NSCalendarMatchNextTimePreservingSmallerUnits |
               NSCalendarMatchPreviousTimePreservingSmallerUnits)))
        o |= NSCalendarMatchNextTime;
    return [self nextDateAfterDate:date matchingComponents:c options:o];
}
@end
