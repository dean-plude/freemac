/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSFormatter and NSDateFormatter, written from Apple's
 * public documentation of both classes and from the public Unicode date
 * pattern standard (Unicode Technical Standard #35); no Apple code was used.
 *
 * Dates are written and read with Unicode date patterns ("yyyy-MM-dd
 * HH:mm:ss Z" and the like) or the four standard styles. Every locale gets
 * English (United States) month and day names and styles, and the calendar
 * is always Gregorian (a calendar can be set, but it doesn't change the
 * fields). Time zone names come from a short table of the common zones;
 * others are written as GMT offsets. With relative formatting, a date
 * style's date is "Today", "Yesterday" or "Tomorrow" when it can be, joined
 * to the time with " at ". Built without ARC. */
#import "FInternal.h"
#include <math.h>

/* ---- NSFormatter ---------------------------------------------------------------- */

@implementation NSFormatter
- (id)copyWithZone:(NSZone *)zone { return [[[self class] alloc] init]; }
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (NSString *)stringForObjectValue:(id)obj { return nil; }
- (NSString *)editingStringForObjectValue:(id)obj { return [self stringForObjectValue:obj]; }
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error
{
    if (error)
        *error = @"This formatter doesn't read values.";
    return NO;
}
- (BOOL)isPartialStringValid:(NSString *)partial newEditingString:(NSString **)newString
            errorDescription:(NSString **)error
{
    if (newString)
        *newString = nil;
    return YES;
}
@end

/* ---- patterns -------------------------------------------------------------------- */

/* A pattern is fields (a letter repeated n times) and literal text. */
struct tok {
    unichar ch;   /* the field's letter, or 0 for literal text */
    int n;
    const unichar *lit;
    NSUInteger nlit;
};

/* The tokens of a pattern; *store holds the literal text and is freed with them. */
static struct tok *tokenize(NSString *pattern, NSUInteger *count, unichar **store)
{
    NSUInteger len = [pattern length], k = 0;
    unichar *c = malloc((len + 1) * sizeof *c), *lit = malloc((len + 1) * sizeof *lit);
    [pattern getCharacters:c range:NSMakeRange(0, len)];
    struct tok *t = calloc(len + 1, sizeof *t);
    NSUInteger used = 0;
#define ADD_LIT(ch_)                                                                                                   \
    do {                                                                                                               \
        if (!k || t[k - 1].ch) {                                                                                       \
            t[k].ch = 0;                                                                                               \
            t[k].lit = lit + used;                                                                                     \
            t[k].nlit = 0;                                                                                             \
            k++;                                                                                                       \
        }                                                                                                              \
        lit[used++] = (ch_);                                                                                           \
        t[k - 1].nlit++;                                                                                               \
    } while (0)
    for (NSUInteger i = 0; i < len;) {
        unichar ch = c[i];
        if (ch == '\'') {
            if (i + 1 < len && c[i + 1] == '\'') {
                ADD_LIT('\'');
                i += 2;
                continue;
            }
            for (i++; i < len; i++) {
                if (c[i] == '\'') {
                    if (i + 1 < len && c[i + 1] == '\'') {
                        ADD_LIT('\'');
                        i++;
                        continue;
                    }
                    i++;
                    break;
                }
                ADD_LIT(c[i]);
            }
        } else if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
            NSUInteger j = i;
            while (j < len && c[j] == ch)
                j++;
            t[k].ch = ch;
            t[k].n = (int)(j - i);
            k++;
            i = j;
        } else {
            ADD_LIT(ch);
            i++;
        }
    }
#undef ADD_LIT
    free(c);
    *count = k;
    *store = lit;
    return t;
}

static int64_t fdiv(int64_t a, int64_t b) { return a / b - ((a % b) && ((a < 0) != (b < 0))); }
static int weekday_of(int64_t days) { return (int)(((days + 4) % 7 + 7) % 7); }   /* 0 is Sunday */
static int days_in_month(int64_t y, int m)
{
    static const int dim[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    BOOL leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    return m == 2 && leap ? 29 : dim[m - 1];
}

/* A date taken apart in a time zone. Weeks start on Sunday and the first
 * week of a year is the one that holds 1 January, as in the United States. */
struct parts {
    int64_t year, days, wyear;
    int month, day, hour, minute, second, ms, wday, yday, week, wmonth;
    int32_t off;
    BOOL dst;
    const char *abbr;
};

static void split(NSDate *date, NSTimeZone *tz, struct parts *p)
{
    double msd = [date timeIntervalSince1970] * 1000.0;
    int64_t ms = (int64_t)floor(msd + 0.001);   /* a microsecond of slack for rounding */
    int64_t secs = fdiv(ms, 1000);
    p->ms = (int)(ms - secs * 1000);
    [tz _at:secs offset:&p->off dst:&p->dst abbreviation:&p->abbr];
    int64_t local = secs + p->off;
    p->days = fdiv(local, 86400);
    int64_t sod = local - p->days * 86400;
    p->hour = (int)(sod / 3600);
    p->minute = (int)(sod / 60 % 60);
    p->second = (int)(sod % 60);
    FCivilFromDays(p->days, &p->year, &p->month, &p->day);
    p->wday = weekday_of(p->days);
    int64_t jan1 = FDaysFromCivil(p->year, 1, 1), next = FDaysFromCivil(p->year + 1, 1, 1);
    p->yday = (int)(p->days - jan1) + 1;
    int wn = weekday_of(next);
    if (wn && p->days >= next - wn) {
        p->wyear = p->year + 1;
        p->week = 1;
    } else {
        p->wyear = p->year;
        p->week = (int)((p->days - (jan1 - weekday_of(jan1))) / 7) + 1;
    }
    int64_t first = FDaysFromCivil(p->year, p->month, 1);
    p->wmonth = (int)((p->days - (first - weekday_of(first))) / 7) + 1;
}

/* ---- time zone names --------------------------------------------------------------- */

static const struct metazone {
    const char *zones;                       /* names, each followed by a space */
    const char *std, *dst, *generic;         /* long names */
    const char *sstd, *sdst, *sgeneric;      /* short names, where English (US) has them */
    int std_minutes;                         /* the standard offset */
} metazones[] = {
    {"America/New_York America/Detroit America/Toronto America/Indiana/Indianapolis America/Kentucky/Louisville "
     "US/Eastern EST5EDT ",
     "Eastern Standard Time", "Eastern Daylight Time", "Eastern Time", "EST", "EDT", "ET", -300},
    {"America/Chicago America/Winnipeg America/Indiana/Knox US/Central CST6CDT ", "Central Standard Time",
     "Central Daylight Time", "Central Time", "CST", "CDT", "CT", -360},
    {"America/Denver America/Edmonton America/Boise America/Phoenix US/Mountain US/Arizona MST7MDT ",
     "Mountain Standard Time", "Mountain Daylight Time", "Mountain Time", "MST", "MDT", "MT", -420},
    {"America/Los_Angeles America/Vancouver America/Tijuana US/Pacific PST8PDT ", "Pacific Standard Time",
     "Pacific Daylight Time", "Pacific Time", "PST", "PDT", "PT", -480},
    {"America/Anchorage America/Juneau America/Sitka America/Nome US/Alaska ", "Alaska Standard Time",
     "Alaska Daylight Time", "Alaska Time", "AKST", "AKDT", "AKT", -540},
    {"Pacific/Honolulu US/Hawaii ", "Hawaii-Aleutian Standard Time", "Hawaii-Aleutian Daylight Time",
     "Hawaii-Aleutian Time", "HST", "HDT", "HST", -600},
    {"Europe/London Europe/Belfast GB ", "Greenwich Mean Time", "British Summer Time", "United Kingdom Time", NULL,
     NULL, NULL, 0},
    {"Europe/Dublin ", "Greenwich Mean Time", "Irish Standard Time", "Ireland Time", NULL, NULL, NULL, 0},
    {"Europe/Paris Europe/Berlin Europe/Madrid Europe/Rome Europe/Amsterdam Europe/Brussels Europe/Vienna "
     "Europe/Stockholm Europe/Oslo Europe/Copenhagen Europe/Zurich Europe/Prague Europe/Warsaw Europe/Budapest "
     "Europe/Belgrade Europe/Luxembourg Europe/Monaco CET ",
     "Central European Standard Time", "Central European Summer Time", "Central European Time", NULL, NULL, NULL, 60},
    {"Europe/Athens Europe/Helsinki Europe/Kiev Europe/Kyiv Europe/Bucharest Europe/Sofia Europe/Riga "
     "Europe/Tallinn Europe/Vilnius EET ",
     "Eastern European Standard Time", "Eastern European Summer Time", "Eastern European Time", NULL, NULL, NULL,
     120},
    {"Europe/Lisbon Atlantic/Canary Atlantic/Madeira WET ", "Western European Standard Time",
     "Western European Summer Time", "Western European Time", NULL, NULL, NULL, 0},
    {"Europe/Moscow ", "Moscow Standard Time", "Moscow Summer Time", "Moscow Time", NULL, NULL, NULL, 180},
    {"Asia/Tokyo Japan ", "Japan Standard Time", "Japan Daylight Time", "Japan Time", NULL, NULL, NULL, 540},
    {"Asia/Shanghai Asia/Chongqing PRC ", "China Standard Time", "China Daylight Time", "China Time", NULL, NULL,
     NULL, 480},
    {"Asia/Kolkata Asia/Calcutta ", "India Standard Time", "India Standard Time", "India Standard Time", NULL, NULL,
     NULL, 330},
    {"Australia/Sydney Australia/Melbourne Australia/Canberra Australia/Hobart ", "Australian Eastern Standard Time",
     "Australian Eastern Daylight Time", "Eastern Australia Time", NULL, NULL, NULL, 600},
    {"Pacific/Auckland NZ ", "New Zealand Standard Time", "New Zealand Daylight Time", "New Zealand Time", NULL, NULL,
     NULL, 720},
    {"UTC Etc/UTC Etc/UCT UCT Universal Etc/Universal Zulu Etc/Zulu ", "Coordinated Universal Time",
     "Coordinated Universal Time", "Coordinated Universal Time", "UTC", "UTC", "UTC", 0},
    {"GMT Etc/GMT GMT0 Etc/GMT0 Greenwich Etc/Greenwich ", "Greenwich Mean Time", "Greenwich Mean Time",
     "Greenwich Mean Time", "GMT", "GMT", "GMT", 0},
};

static const struct metazone *metazone_of(NSTimeZone *tz)
{
    const char *name = [[tz name] UTF8String];
    size_t n = name ? strlen(name) : 0;
    if (!n)
        return NULL;
    for (size_t i = 0; i < sizeof metazones / sizeof metazones[0]; i++) {
        for (const char *p = metazones[i].zones; (p = strstr(p, name)); p++)
            if ((p == metazones[i].zones || p[-1] == ' ') && p[n] == ' ')
                return &metazones[i];
    }
    return NULL;
}

static NSString *gmt_name(int32_t off, BOOL lng)
{
    if (!off)
        return @"GMT";
    int a = abs(off), h = a / 3600, m = a / 60 % 60;
    char s = off < 0 ? '-' : '+';
    if (lng)
        return FFormatC("GMT%c%02d:%02d", s, h, m);
    return m ? FFormatC("GMT%c%d:%02d", s, h, m) : FFormatC("GMT%c%d", s, h);
}

/* ISO 8601 offsets: n 1 "+05" or "+0530", 2 and 4 "+0530", 3 and 5 "+05:30"; Z for zero when z. */
static NSString *iso_offset(int32_t off, int n, BOOL z)
{
    if (!off && z)
        return @"Z";
    int a = abs(off), h = a / 3600, m = a / 60 % 60, s = a % 60;
    char sign = off < 0 ? '-' : '+';
    if (n == 1)
        return m ? FFormatC("%c%02d%02d", sign, h, m) : FFormatC("%c%02d", sign, h);
    if (n == 3 || n >= 5)
        return s && n >= 5 ? FFormatC("%c%02d:%02d:%02d", sign, h, m, s) : FFormatC("%c%02d:%02d", sign, h, m);
    return s && n == 4 ? FFormatC("%c%02d%02d%02d", sign, h, m, s) : FFormatC("%c%02d%02d", sign, h, m);
}

static NSString *zone_city(NSTimeZone *tz)
{
    NSString *city = [[[tz name] lastPathComponent] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    return [city length] ? city : gmt_name(0, NO);
}

/* ---- the symbols ---------------------------------------------------------------- */

static NSDictionary *default_symbols(void)
{
    static NSDictionary *d;
    static dispatch_once_t d_once;
    dispatch_once(&d_once, ^{
        NSArray *months = @[
            @"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August", @"September",
            @"October", @"November", @"December"
        ];
        NSArray *smonths =
            @[ @"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec" ];
        NSArray *vsmonths = @[ @"J", @"F", @"M", @"A", @"M", @"J", @"J", @"A", @"S", @"O", @"N", @"D" ];
        NSArray *days = @[ @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" ];
        NSArray *sdays = @[ @"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat" ];
        NSArray *vsdays = @[ @"S", @"M", @"T", @"W", @"T", @"F", @"S" ];
        NSArray *quarters = @[ @"1st quarter", @"2nd quarter", @"3rd quarter", @"4th quarter" ];
        NSArray *squarters = @[ @"Q1", @"Q2", @"Q3", @"Q4" ];
        d = [@{
            @"AM" : @"AM",
            @"PM" : @"PM",
            @"era" : @[ @"BC", @"AD" ],
            @"longEra" : @[ @"Before Christ", @"Anno Domini" ],
            @"month" : months,
            @"shortMonth" : smonths,
            @"veryShortMonth" : vsmonths,
            @"standaloneMonth" : months,
            @"shortStandaloneMonth" : smonths,
            @"veryShortStandaloneMonth" : vsmonths,
            @"weekday" : days,
            @"shortWeekday" : sdays,
            @"veryShortWeekday" : vsdays,
            @"standaloneWeekday" : days,
            @"shortStandaloneWeekday" : sdays,
            @"veryShortStandaloneWeekday" : vsdays,
            @"quarter" : quarters,
            @"shortQuarter" : squarters,
            @"standaloneQuarter" : quarters,
            @"shortStandaloneQuarter" : squarters,
        } retain];
    });
    return d;
}

static NSString *const shortest_days[] = {@"Su", @"Mo", @"Tu", @"We", @"Th", @"Fr", @"Sa"};

static NSDateFormatterBehavior default_behavior = NSDateFormatterBehavior10_4;

/* English (United States) styles */
static NSString *date_style(NSDateFormatterStyle s)
{
    switch (s) {
    case NSDateFormatterShortStyle: return @"M/d/yy";
    case NSDateFormatterMediumStyle: return @"MMM d, y";
    case NSDateFormatterLongStyle: return @"MMMM d, y";
    case NSDateFormatterFullStyle: return @"EEEE, MMMM d, y";
    default: return nil;
    }
}

static NSString *time_style(NSDateFormatterStyle s)
{
    switch (s) {
    case NSDateFormatterShortStyle: return @"h:mm a";
    case NSDateFormatterMediumStyle: return @"h:mm:ss a";
    case NSDateFormatterLongStyle: return @"h:mm:ss a z";
    case NSDateFormatterFullStyle: return @"h:mm:ss a zzzz";
    default: return nil;
    }
}

@implementation NSDateFormatter {
    NSString *_format;
    NSDateFormatterStyle _dateStyle, _timeStyle;
    NSLocale *_locale;
    NSTimeZone *_timeZone;
    NSDate *_defaultDate, *_twoDigitStartDate;
    NSCalendar *_calendar;
    NSMutableDictionary *_symbols;
    BOOL _lenient, _generatesCalendarDates, _relative;
    NSDateFormatterBehavior _behavior;
}

+ (NSDateFormatterBehavior)defaultFormatterBehavior { return default_behavior; }
+ (void)setDefaultFormatterBehavior:(NSDateFormatterBehavior)behavior { default_behavior = behavior; }

- (instancetype)init
{
    if ((self = [super init])) {
        _format = @"";
        _symbols = [[NSMutableDictionary alloc] init];
        _behavior = default_behavior;
    }
    return self;
}

- (void)dealloc
{
    [_format release];
    [_locale release];
    [_timeZone release];
    [_defaultDate release];
    [_twoDigitStartDate release];
    [_calendar release];
    [_symbols release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f->_format release];
    f->_format = [_format copy];
    f->_dateStyle = _dateStyle;
    f->_timeStyle = _timeStyle;
    f->_locale = [_locale retain];
    f->_timeZone = [_timeZone retain];
    f->_defaultDate = [_defaultDate retain];
    f->_twoDigitStartDate = [_twoDigitStartDate retain];
    f->_calendar = [_calendar copy];
    [f->_symbols addEntriesFromDictionary:_symbols];
    f->_lenient = _lenient;
    f->_generatesCalendarDates = _generatesCalendarDates;
    f->_relative = _relative;
    f->_behavior = _behavior;
    return f;
}

+ (NSString *)localizedStringFromDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)dstyle
                            timeStyle:(NSDateFormatterStyle)tstyle
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateStyle:dstyle];
    [f setTimeStyle:tstyle];
    return [f stringFromDate:date];
}

/* ---- properties ---- */

- (void)_restyle
{
    NSString *d = date_style(_dateStyle), *t = time_style(_timeStyle), *f;
    if (d && t)
        f = [NSString stringWithFormat:_dateStyle >= NSDateFormatterLongStyle ? @"%@ 'at' %@" : @"%@, %@", d, t];
    else
        f = d ?: t ?: @"";
    [_format release];
    _format = [f copy];
}

- (NSString *)dateFormat { return _format; }
- (void)setDateFormat:(NSString *)format
{
    format = [format copy];
    [_format release];
    _format = format ?: @"";
}
- (NSDateFormatterStyle)dateStyle { return _dateStyle; }
- (void)setDateStyle:(NSDateFormatterStyle)style
{
    _dateStyle = style;
    [self _restyle];
}
- (NSDateFormatterStyle)timeStyle { return _timeStyle; }
- (void)setTimeStyle:(NSDateFormatterStyle)style
{
    _timeStyle = style;
    [self _restyle];
}
- (NSLocale *)locale { return _locale ?: [NSLocale currentLocale]; }
- (void)setLocale:(NSLocale *)locale
{
    [locale retain];
    [_locale release];
    _locale = locale;
}
- (NSTimeZone *)timeZone { return _timeZone ?: [NSTimeZone defaultTimeZone]; }
- (void)setTimeZone:(NSTimeZone *)zone
{
    [zone retain];
    [_timeZone release];
    _timeZone = zone;
}
- (BOOL)isLenient { return _lenient; }
- (void)setLenient:(BOOL)lenient { _lenient = lenient; }
- (BOOL)generatesCalendarDates { return _generatesCalendarDates; }
- (void)setGeneratesCalendarDates:(BOOL)b { _generatesCalendarDates = b; }
- (NSCalendar *)calendar
{
    if (_calendar)
        return _calendar;
    NSCalendar *c = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
    [c setTimeZone:[self timeZone]];
    [c setLocale:[self locale]];
    return c;
}
- (void)setCalendar:(NSCalendar *)calendar
{
    NSCalendar *c = [calendar copy];
    [_calendar release];
    _calendar = c;
}
- (BOOL)doesRelativeDateFormatting { return _relative; }
- (void)setDoesRelativeDateFormatting:(BOOL)b { _relative = b; }
- (NSDateFormatterBehavior)formatterBehavior { return _behavior; }
- (void)setFormatterBehavior:(NSDateFormatterBehavior)b { _behavior = b; }
- (NSDate *)defaultDate { return _defaultDate; }
- (void)setDefaultDate:(NSDate *)date
{
    date = [date copy];
    [_defaultDate release];
    _defaultDate = date;
}
- (NSDate *)twoDigitStartDate
{
    /* 1 January 1950: two-digit years read as 1950 to 2049 */
    return _twoDigitStartDate ?: [NSDate dateWithTimeIntervalSince1970:-631152000.0];
}
- (void)setTwoDigitStartDate:(NSDate *)date
{
    date = [date copy];
    [_twoDigitStartDate release];
    _twoDigitStartDate = date;
}

- (id)_symbol:(NSString *)key { return [_symbols objectForKey:key] ?: [default_symbols() objectForKey:key]; }
- (void)_setSymbol:(id)value key:(NSString *)key
{
    if (value)
        [_symbols setObject:[[value copy] autorelease] forKey:key];
    else
        [_symbols removeObjectForKey:key];
}

#define SYMBOL(type, getter, setter, K)                                                                              \
    -(type)getter { return [self _symbol:K]; }                                                                      \
    -(void)setter:(type)value { [self _setSymbol:value key:K]; }
SYMBOL(NSString *, AMSymbol, setAMSymbol, @"AM")
SYMBOL(NSString *, PMSymbol, setPMSymbol, @"PM")
SYMBOL(NSArray *, eraSymbols, setEraSymbols, @"era")
SYMBOL(NSArray *, longEraSymbols, setLongEraSymbols, @"longEra")
SYMBOL(NSArray *, monthSymbols, setMonthSymbols, @"month")
SYMBOL(NSArray *, shortMonthSymbols, setShortMonthSymbols, @"shortMonth")
SYMBOL(NSArray *, veryShortMonthSymbols, setVeryShortMonthSymbols, @"veryShortMonth")
SYMBOL(NSArray *, standaloneMonthSymbols, setStandaloneMonthSymbols, @"standaloneMonth")
SYMBOL(NSArray *, shortStandaloneMonthSymbols, setShortStandaloneMonthSymbols, @"shortStandaloneMonth")
SYMBOL(NSArray *, veryShortStandaloneMonthSymbols, setVeryShortStandaloneMonthSymbols, @"veryShortStandaloneMonth")
SYMBOL(NSArray *, weekdaySymbols, setWeekdaySymbols, @"weekday")
SYMBOL(NSArray *, shortWeekdaySymbols, setShortWeekdaySymbols, @"shortWeekday")
SYMBOL(NSArray *, veryShortWeekdaySymbols, setVeryShortWeekdaySymbols, @"veryShortWeekday")
SYMBOL(NSArray *, standaloneWeekdaySymbols, setStandaloneWeekdaySymbols, @"standaloneWeekday")
SYMBOL(NSArray *, shortStandaloneWeekdaySymbols, setShortStandaloneWeekdaySymbols, @"shortStandaloneWeekday")
SYMBOL(NSArray *, veryShortStandaloneWeekdaySymbols, setVeryShortStandaloneWeekdaySymbols,
       @"veryShortStandaloneWeekday")
SYMBOL(NSArray *, quarterSymbols, setQuarterSymbols, @"quarter")
SYMBOL(NSArray *, shortQuarterSymbols, setShortQuarterSymbols, @"shortQuarter")
SYMBOL(NSArray *, standaloneQuarterSymbols, setStandaloneQuarterSymbols, @"standaloneQuarter")
SYMBOL(NSArray *, shortStandaloneQuarterSymbols, setShortStandaloneQuarterSymbols, @"shortStandaloneQuarter")
#undef SYMBOL

/* ---- writing ---- */

static void num(NSMutableString *out, int64_t v, int width)
{
    char buf[32];
    if (v < 0)
        snprintf(buf, sizeof buf, "-%0*lld", width, (long long)-v);
    else
        snprintf(buf, sizeof buf, "%0*lld", width, (long long)v);
    [out appendString:[NSString stringWithUTF8String:buf]];
}

static void pick(NSMutableString *out, NSArray *list, NSUInteger i)
{
    if (i < [list count])
        [out appendString:[list objectAtIndex:i]];
}

- (void)_write:(const struct tok *)t parts:(const struct parts *)p zone:(NSTimeZone *)tz into:(NSMutableString *)out
{
    int n = t->n;
    int64_t eyear = p->year > 0 ? p->year : 1 - p->year;
    const struct metazone *mz;
    switch (t->ch) {
    case 'G':
        if (n == 5) {   /* the first letter alone */
            NSString *e = [[self eraSymbols] objectAtIndex:p->year > 0];
            [out appendString:[e substringToIndex:[e length] ? 1 : 0]];
        } else {
            pick(out, n == 4 ? [self longEraSymbols] : [self eraSymbols], p->year > 0);
        }
        break;
    case 'y': num(out, n == 2 ? eyear % 100 : eyear, n); break;
    case 'Y': num(out, n == 2 ? p->wyear % 100 : p->wyear, n); break;
    case 'u':
    case 'r':
    case 'U': num(out, p->year, n); break;
    case 'Q':
    case 'q': {
        int q = (p->month - 1) / 3;
        if (n <= 2 || n == 5)
            num(out, q + 1, n == 5 ? 1 : n);
        else if (n == 3)
            pick(out, t->ch == 'Q' ? [self shortQuarterSymbols] : [self shortStandaloneQuarterSymbols], q);
        else
            pick(out, t->ch == 'Q' ? [self quarterSymbols] : [self standaloneQuarterSymbols], q);
        break;
    }
    case 'M':
    case 'L': {
        BOOL sa = t->ch == 'L';
        if (n <= 2)
            num(out, p->month, n);
        else if (n == 3)
            pick(out, sa ? [self shortStandaloneMonthSymbols] : [self shortMonthSymbols], p->month - 1);
        else if (n == 4)
            pick(out, sa ? [self standaloneMonthSymbols] : [self monthSymbols], p->month - 1);
        else
            pick(out, sa ? [self veryShortStandaloneMonthSymbols] : [self veryShortMonthSymbols], p->month - 1);
        break;
    }
    case 'w': num(out, p->week, n); break;
    case 'W': num(out, p->wmonth, n); break;
    case 'd': num(out, p->day, n); break;
    case 'D': num(out, p->yday, n); break;
    case 'F': num(out, (p->day - 1) / 7 + 1, n); break;
    case 'g': num(out, p->days + 2440588, n); break;   /* the Julian day number */
    case 'e':
    case 'c':
        if (n <= 2) {
            num(out, p->wday + 1, n);
            break;
        }
        /* fall through */
    case 'E': {
        BOOL sa = t->ch == 'c';
        if (n <= 3)
            pick(out, sa ? [self shortStandaloneWeekdaySymbols] : [self shortWeekdaySymbols], p->wday);
        else if (n == 4)
            pick(out, sa ? [self standaloneWeekdaySymbols] : [self weekdaySymbols], p->wday);
        else if (n == 5)
            pick(out, sa ? [self veryShortStandaloneWeekdaySymbols] : [self veryShortWeekdaySymbols], p->wday);
        else
            [out appendString:shortest_days[p->wday]];
        break;
    }
    case 'a':
    case 'b':
    case 'B': [out appendString:p->hour < 12 ? [self AMSymbol] : [self PMSymbol]]; break;
    case 'h': num(out, p->hour % 12 ? p->hour % 12 : 12, n); break;
    case 'H': num(out, p->hour, n); break;
    case 'K': num(out, p->hour % 12, n); break;
    case 'k': num(out, p->hour ? p->hour : 24, n); break;
    case 'm': num(out, p->minute, n); break;
    case 's': num(out, p->second, n); break;
    case 'S': {   /* milliseconds are all Ferry keeps, as on a Mac */
        char buf[16];
        snprintf(buf, sizeof buf, "%03d", p->ms);
        for (int i = 0; i < n; i++)
            [out appendFormat:@"%c", i < 3 ? buf[i] : '0'];
        break;
    }
    case 'A': num(out, ((p->hour * 60 + p->minute) * 60 + p->second) * 1000LL + p->ms, n); break;
    case 'z':
        mz = metazone_of(tz);
        if (n <= 3) {
            const char *s = mz ? (p->dst ? mz->sdst : mz->sstd) : NULL;
            [out appendString:s ? [NSString stringWithUTF8String:s] : gmt_name(p->off, NO)];
        } else {
            [out appendString:mz ? [NSString stringWithUTF8String:p->dst ? mz->dst : mz->std] : gmt_name(p->off, YES)];
        }
        break;
    case 'v':
        mz = metazone_of(tz);
        if (n == 1)
            [out appendString:mz && mz->sgeneric ? [NSString stringWithUTF8String:mz->sgeneric] : gmt_name(p->off, NO)];
        else
            [out appendString:mz ? [NSString stringWithUTF8String:mz->generic]
                                 : [NSString stringWithFormat:@"%@ Time", zone_city(tz)]];
        break;
    case 'V':
        if (n <= 2)
            [out appendString:[tz name] ?: gmt_name(p->off, YES)];
        else if (n == 3)
            [out appendString:zone_city(tz)];
        else
            [out appendFormat:@"%@ Time", zone_city(tz)];
        break;
    case 'O': [out appendString:gmt_name(p->off, n >= 4)]; break;
    case 'Z':
        if (n <= 3)
            [out appendString:iso_offset(p->off, 2, NO)];
        else if (n == 4)
            [out appendString:gmt_name(p->off, YES)];
        else
            [out appendString:iso_offset(p->off, 5, YES)];
        break;
    case 'X':
    case 'x': [out appendString:iso_offset(p->off, n, t->ch == 'X')]; break;
    default:   /* not a field Ferry knows: kept as it is */
        for (int i = 0; i < n; i++)
            [out appendFormat:@"%C", t->ch];
    }
}

/* The relative name of the day of a date, if it is yesterday, today or tomorrow
 * where the formatter's zone is. */
static NSString *const relative_days[] = {@"Yesterday", @"Today", @"Tomorrow"};

static int64_t local_day(NSDate *date, NSTimeZone *tz)
{
    struct parts p;
    split(date, tz, &p);
    return p.days;
}

- (NSString *)_relativeDay:(NSDate *)date
{
    int64_t diff = local_day(date, [self timeZone]) - local_day([NSDate date], [self timeZone]);
    return diff >= -1 && diff <= 1 ? relative_days[diff + 1] : nil;
}

- (NSString *)stringFromDate:(NSDate *)date
{
    if (!date)
        return nil;
    if (_relative && _dateStyle != NSDateFormatterNoStyle) {
        NSString *day = [self _relativeDay:date];
        if (day) {
            if (_timeStyle == NSDateFormatterNoStyle)
                return day;
            return [NSString stringWithFormat:@"%@ at %@", day, [self _string:date pattern:time_style(_timeStyle)]];
        }
    }
    return [self _string:date pattern:[self dateFormat]];
}

- (NSString *)_string:(NSDate *)date pattern:(NSString *)pattern
{
    if (![pattern length])
        return @"";
    NSTimeZone *tz = [self timeZone];
    struct parts p;
    split(date, tz, &p);
    NSUInteger n;
    unichar *store;
    struct tok *t = tokenize(pattern, &n, &store);
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < n; i++) {
        if (t[i].ch)
            [self _write:&t[i] parts:&p zone:tz into:out];
        else
            [out appendString:[NSString stringWithCharacters:t[i].lit length:t[i].nlit]];
    }
    free(t);
    free(store);
    return [NSString stringWithString:out];
}

- (NSString *)stringForObjectValue:(id)obj
{
    return [obj isKindOfClass:[NSDate class]] ? [self stringFromDate:obj] : nil;
}

/* ---- reading ---- */

static BOOL numeric_field(const struct tok *t)
{
    switch (t->ch) {
    case 'y': case 'Y': case 'u': case 'r': case 'U': case 'd': case 'D': case 'F': case 'g': case 'h': case 'H':
    case 'k': case 'K': case 'm': case 's': case 'S': case 'A': case 'w': case 'W':
        return YES;
    case 'M': case 'L': case 'Q': case 'q': case 'e': case 'c':
        return t->n <= 2;
    default:
        return NO;
    }
}

static BOOL is_space(unichar c) { return c == ' ' || c == '\t' || c == 0xa0 || c == 0x202f || c == 0x2009; }

struct got {
    int64_t year, uyear, wyear;
    int yy_digits, month, day, yday, hour24, hour12, minute, second, week, wday, ampm, era;
    double frac;
    BOOL has_year, has_uyear, has_wyear, has_month, has_day, has_yday, has_hour24, has_hour12, has_minute,
        has_second, has_week, has_wday, has_off;
    int32_t off;
    NSTimeZone *zone;
};

/* Whether s has word at pos, ignoring case. */
static BOOL at_ignoring_case(NSString *s, NSUInteger pos, NSString *word)
{
    NSUInteger len = [s length], wl = [word length];
    if (!wl || pos + wl > len)
        return NO;
    return [s rangeOfString:word options:NSCaseInsensitiveSearch | NSAnchoredSearch range:NSMakeRange(pos, len - pos)]
               .location == pos;
}

/* The longest of the strings in the lists found at pos, ignoring case; its index in *which. */
static NSUInteger match(NSString *s, NSUInteger pos, NSArray *const *lists, int nlists, NSUInteger *which)
{
    NSUInteger best = 0, len = [s length];
    for (int l = 0; l < nlists; l++) {
        NSArray *list = lists[l];
        for (NSUInteger i = 0; i < [list count]; i++) {
            NSString *c = [list objectAtIndex:i];
            NSUInteger cl = [c length];
            if (cl > best && pos + cl <= len &&
                at_ignoring_case(s, pos, c)) {
                best = cl;
                *which = i;
            }
        }
    }
    return best;
}

static NSUInteger digits_at(const unichar *c, NSUInteger len, NSUInteger pos, NSUInteger max, int64_t *v)
{
    NSUInteger k = 0;
    int64_t x = 0;
    while (pos + k < len && k < max && c[pos + k] >= '0' && c[pos + k] <= '9' && x < INT64_MAX / 10)
        x = x * 10 + (c[pos + k++] - '0');
    *v = x;
    return k;
}

/* A time zone at pos: GMT or UTC with an offset, an ISO 8601 offset, Z, or a
 * name from the table, long or short. Returns the characters used. */
static NSUInteger read_zone(NSString *s, const unichar *c, NSUInteger len, NSUInteger pos, struct got *g)
{
    NSUInteger p = pos;
    BOOL prefix = NO;
    for (int k = 0; k < 3; k++) {
        NSString *pre = k == 0 ? @"GMT" : k == 1 ? @"UTC" : @"UT";
        if (p + [pre length] <= len &&
            at_ignoring_case(s, p, pre)) {
            p += [pre length];
            prefix = YES;
            break;
        }
    }
    if (p < len && (c[p] == '+' || c[p] == '-' || c[p] == 0x2212)) {
        int sign = c[p] == '+' ? 1 : -1;
        NSUInteger q = p + 1;
        int64_t h, m = 0;
        NSUInteger nd = digits_at(c, len, q, 2, &h);
        if (nd) {
            q += nd;
            if (q < len && c[q] == ':') {
                int64_t mm;
                if (digits_at(c, len, q + 1, 2, &mm) == 2) {
                    m = mm;
                    q += 3;
                }
            } else if (nd == 2) {
                int64_t mm;
                if (digits_at(c, len, q, 2, &mm) == 2) {
                    m = mm;
                    q += 2;
                }
            }
            if (h <= 23 && m <= 59) {
                g->has_off = YES;
                g->off = (int32_t)(sign * (h * 3600 + m * 60));
                return q - pos;
            }
        }
    }
    if (prefix) {
        g->has_off = YES;
        g->off = 0;
        return p - pos;
    }
    if (p < len && (c[p] == 'Z' || c[p] == 'z') && (p + 1 >= len || !isalpha(c[p + 1] < 128 ? c[p + 1] : 'a'))) {
        g->has_off = YES;
        g->off = 0;
        return 1;
    }
    NSUInteger best = 0;
    for (size_t i = 0; i < sizeof metazones / sizeof metazones[0]; i++) {
        const struct metazone *mz = &metazones[i];
        const char *names[] = {mz->std, mz->dst, mz->generic, mz->sstd, mz->sdst, mz->sgeneric};
        for (int k = 0; k < 6; k++) {
            if (!names[k])
                continue;
            NSString *nm = [NSString stringWithUTF8String:names[k]];
            NSUInteger nl = [nm length];
            if (nl <= best || pos + nl > len ||
                !at_ignoring_case(s, pos, nm))
                continue;
            best = nl;
            BOOL generic = k == 2 || k == 5, dst = k == 1 || k == 4;
            if (generic || !strcmp(mz->std, mz->dst)) {   /* the zone itself decides */
                char first[64];
                const char *sp = strchr(mz->zones, ' ');
                snprintf(first, sizeof first, "%.*s", (int)(sp - mz->zones), mz->zones);
                g->zone = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:first]];
                g->has_off = g->zone == nil;
                g->off = mz->std_minutes * 60;
            } else {
                g->zone = nil;
                g->has_off = YES;
                g->off = (mz->std_minutes + (dst ? 60 : 0)) * 60;
            }
        }
    }
    if (best)
        return best;
    /* a zone's name, such as Europe/Paris */
    NSUInteger q = pos;
    while (q < len && c[q] < 128 && (isalnum(c[q]) || c[q] == '/' || c[q] == '_' || c[q] == '-' || c[q] == '+'))
        q++;
    if (q > pos) {
        NSTimeZone *z = [NSTimeZone timeZoneWithName:[s substringWithRange:NSMakeRange(pos, q - pos)]];
        if (z) {
            g->zone = z;
            g->has_off = NO;
            return q - pos;
        }
    }
    return 0;
}

/* Reads s from *pos with the pattern; YES if every field matched. */
- (BOOL)_read:(NSString *)s at:(NSUInteger *)pos into:(struct got *)g
{
    NSUInteger len = [s length], p = *pos, n;
    unichar *c = malloc((len + 1) * sizeof *c), *store;
    [s getCharacters:c range:NSMakeRange(0, len)];
    struct tok *t = tokenize([self dateFormat], &n, &store);
    BOOL ok = n > 0;
    for (NSUInteger i = 0; ok && i < n; i++) {
        const struct tok *k = &t[i];
        if (!k->ch) {
            for (NSUInteger j = 0; ok && j < k->nlit; j++) {
                unichar lc = k->lit[j];
                if (is_space(lc)) {
                    while (p < len && is_space(c[p]))
                        p++;
                } else if (p < len && (c[p] == lc || (_lenient && lc < 128 && c[p] < 128 && tolower(c[p]) == tolower(lc)))) {
                    p++;
                } else {
                    ok = NO;
                }
            }
            continue;
        }
        if (_lenient)
            while (p < len && is_space(c[p]))
                p++;
        if (numeric_field(k)) {
            BOOL abut = i + 1 < n && t[i + 1].ch && numeric_field(&t[i + 1]);
            NSUInteger max = abut ? (NSUInteger)k->n : 10;
            if (abut && k->ch == 'y' && k->n != 2 && k->n < 4)
                max = 4;
            int sign = 1;
            if ((k->ch == 'u' || k->ch == 'r') && p < len && c[p] == '-') {
                sign = -1;
                p++;
            }
            int64_t v;
            NSUInteger nd = digits_at(c, len, p, k->ch == 'S' ? (abut ? max : 9) : max, &v);
            if (!nd) {
                ok = NO;
                break;
            }
            p += nd;
            if (k->ch == 'S')
                while (!abut && p < len && c[p] >= '0' && c[p] <= '9')
                    p++;   /* digits past nanoseconds count for nothing */
            v *= sign;
            switch (k->ch) {
            case 'y': g->year = v, g->has_year = YES, g->yy_digits = k->n <= 2 && nd == 2; break;
            case 'Y': g->wyear = v, g->has_wyear = YES; break;
            case 'u': case 'r': case 'U': g->uyear = v, g->has_uyear = YES; break;
            case 'M': case 'L': g->month = (int)v, g->has_month = YES; break;
            case 'Q': case 'q': if (!g->has_month) g->month = (int)(v - 1) * 3 + 1; break;
            case 'd': g->day = (int)v, g->has_day = YES; break;
            case 'D': g->yday = (int)v, g->has_yday = YES; break;
            case 'w': g->week = (int)v, g->has_week = YES; break;
            case 'e': case 'c': g->wday = (int)(v - 1), g->has_wday = YES; break;
            case 'H': g->hour24 = (int)v, g->has_hour24 = YES; break;
            case 'k': g->hour24 = v == 24 ? 0 : (int)v, g->has_hour24 = YES; if (v == 0) ok = _lenient; break;
            case 'h': g->hour12 = (int)v, g->has_hour12 = YES; if (v == 0 || v > 12) ok = _lenient; break;
            case 'K': g->hour12 = (int)v, g->has_hour12 = YES; if (v > 11) ok = _lenient; break;
            case 'm': g->minute = (int)v, g->has_minute = YES; break;
            case 's': g->second = (int)v, g->has_second = YES; break;
            case 'S': {
                double scale = 1;
                for (NSUInteger z = 0; z < nd; z++)
                    scale *= 10;
                g->frac = (double)v / scale;
                break;
            }
            case 'A':
                g->hour24 = (int)(v / 3600000), g->minute = (int)(v / 60000 % 60), g->second = (int)(v / 1000 % 60);
                g->frac = (double)(v % 1000) / 1000.0;
                g->has_hour24 = g->has_minute = g->has_second = YES;
                break;
            default: break;   /* F, W, g: read and not used */
            }
            continue;
        }
        NSUInteger which = 0, used = 0;
        switch (k->ch) {
        case 'G': {
            NSArray *lists[] = {[self longEraSymbols], [self eraSymbols]};
            used = match(s, p, lists, 2, &which);
            g->era = (int)which;
            break;
        }
        case 'M':
        case 'L': {
            NSArray *lists[] = {[self monthSymbols], [self shortMonthSymbols], [self standaloneMonthSymbols],
                                [self shortStandaloneMonthSymbols], [self veryShortMonthSymbols]};
            used = match(s, p, lists, k->n == 5 ? 5 : 4, &which);
            g->month = (int)which + 1;
            g->has_month = YES;
            break;
        }
        case 'E':
        case 'e':
        case 'c': {
            NSArray *shortest = [NSArray arrayWithObjects:shortest_days count:7];
            NSArray *lists[] = {[self weekdaySymbols], [self shortWeekdaySymbols], [self standaloneWeekdaySymbols],
                                [self shortStandaloneWeekdaySymbols], shortest, [self veryShortWeekdaySymbols]};
            used = match(s, p, lists, k->n == 5 ? 6 : 5, &which);
            g->wday = (int)which;
            g->has_wday = YES;
            break;
        }
        case 'Q':
        case 'q': {
            NSArray *lists[] = {[self quarterSymbols], [self shortQuarterSymbols]};
            used = match(s, p, lists, 2, &which);
            if (!g->has_month)
                g->month = (int)which * 3 + 1;
            break;
        }
        case 'a':
        case 'b':
        case 'B': {
            NSArray *lists[] = {@[ [self AMSymbol], [self PMSymbol] ]};
            used = match(s, p, lists, 1, &which);
            g->ampm = (int)which;
            break;
        }
        case 'z':
        case 'Z':
        case 'O':
        case 'v':
        case 'V':
        case 'X':
        case 'x': used = read_zone(s, c, len, p, g); break;
        default: {   /* a letter Ferry doesn't know matches itself, as it was written */
            NSUInteger j = 0;
            while (j < (NSUInteger)k->n && p + j < len && c[p + j] == k->ch)
                j++;
            used = j == (NSUInteger)k->n ? j : 0;
        }
        }
        if (!used)
            ok = NO;
        p += used;
    }
    free(t);
    free(store);
    free(c);
    *pos = p;
    return ok;
}

- (NSDate *)_dateFrom:(struct got *)g
{
    NSTimeZone *tz = [self timeZone];
    struct parts d;
    if (_defaultDate) {
        split(_defaultDate, g->zone ?: tz, &d);
    } else {   /* fields not in the string come from 1 January 2000, midnight */
        memset(&d, 0, sizeof d);
        d.year = 2000;
        d.month = d.day = 1;
    }
    int64_t year = d.year;
    if (g->has_uyear) {
        year = g->uyear;
    } else if (g->has_year) {
        year = g->year;
        if (g->yy_digits) {   /* the first year ending in those digits from the two-digit start on */
            struct parts st;
            split([self twoDigitStartDate], tz, &st);
            year += fdiv(st.year, 100) * 100;
            if (year < st.year)
                year += 100;
        }
        if (g->era == 0)
            year = 1 - year;
    } else if (g->has_wyear) {
        year = g->wyear;
    }
    int month = g->has_month || g->month ? g->month : d.month, day = g->has_day ? g->day : d.day;
    BOOL by_yday = !g->has_month && !g->month && !g->has_day && g->has_yday;
    if (by_yday) {
        month = 1;
        day = 1;
    } else if (!g->has_month && !g->month && !g->has_day && (g->has_week || (g->has_wyear && g->has_wday))) {
        month = 1;
        day = 1;
    } else if (!g->has_day && (g->has_month || g->month)) {
        day = 1;
    }
    int hour = g->has_hour24 ? g->hour24 : g->has_hour12 ? g->hour12 % 12 : (g->has_minute || g->has_second) ? 0 : d.hour;
    if (!g->has_hour24 && g->ampm == 1 && hour < 12)
        hour += 12;
    int minute = g->has_minute ? g->minute : (g->has_hour24 || g->has_hour12) ? 0 : d.minute;
    int second = g->has_second ? g->second : (g->has_hour24 || g->has_hour12 || g->has_minute) ? 0 : d.second;
    if (!_lenient) {
        if (month < 1 || month > 12 || day < 1 || day > days_in_month(year, month) || hour > 23 || minute > 59 ||
            second > 59)
            return nil;
        if (g->has_yday && (g->yday < 1 || g->yday > (days_in_month(year, 2) == 29 ? 366 : 365)))
            return nil;
    }
    year += fdiv(month - 1, 12);
    month = (int)((month - 1) - fdiv(month - 1, 12) * 12) + 1;
    int64_t days = FDaysFromCivil(year, month, 1) + (by_yday ? g->yday : day) - 1;
    if (!g->has_month && !g->month && !g->has_day && !g->has_yday && (g->has_week || (g->has_wyear && g->has_wday))) {
        int64_t jan1 = FDaysFromCivil(year, 1, 1);
        days = jan1 - weekday_of(jan1) + (int64_t)((g->has_week ? g->week : 1) - 1) * 7 + (g->has_wday ? g->wday : 0);
    }
    int64_t local = days * 86400 + hour * 3600 + minute * 60 + second, t;
    if (g->has_off) {
        t = local - g->off;
    } else {
        NSTimeZone *z = g->zone ?: tz;
        int32_t off;
        BOOL dst;
        const char *abbr;
        [z _at:local offset:&off dst:&dst abbreviation:&abbr];
        t = local - off;
        [z _at:t offset:&off dst:&dst abbreviation:&abbr];
        t = local - off;
    }
    return [NSDate dateWithTimeIntervalSince1970:(double)t + g->frac];
}

/* "Today at 3:05 PM" read as the date of today written in the date style. */
- (NSString *)_unrelative:(NSString *)string
{
    if (!_relative || _dateStyle == NSDateFormatterNoStyle || !string)
        return string;
    for (int i = 0; i < 3; i++) {
        NSString *word = relative_days[i];
        NSUInteger n = [word length];
        if ([string length] < n || [[string substringToIndex:n] caseInsensitiveCompare:word] != NSOrderedSame)
            continue;
        NSString *rest = [string substringFromIndex:n];
        NSDate *day = [[self calendar] dateByAddingUnit:NSCalendarUnitDay value:i - 1 toDate:[NSDate date] options:0];
        NSString *date = [self _string:day pattern:date_style(_dateStyle)];
        if (_timeStyle == NSDateFormatterNoStyle)
            return [date stringByAppendingString:rest];
        NSString *join = _dateStyle >= NSDateFormatterLongStyle ? @" at " : @", ";
        if ([rest hasPrefix:@" at "])
            rest = [rest substringFromIndex:4];
        else if ([rest hasPrefix:@", "])
            rest = [rest substringFromIndex:2];
        else
            return string;
        return [NSString stringWithFormat:@"%@%@%@", date, join, rest];
    }
    return string;
}

- (NSDate *)dateFromString:(NSString *)string
{
    string = [self _unrelative:string];
    if (!string || ![[self dateFormat] length])
        return nil;
    struct got g;
    memset(&g, 0, sizeof g);
    g.ampm = g.era = -1;
    NSUInteger pos = 0, len = [string length];
    if (![self _read:string at:&pos into:&g])
        return nil;
    if (_lenient)
        while (pos < len && is_space([string characterAtIndex:pos]))
            pos++;
    if (pos != len)
        return nil;
    return [self _dateFrom:&g];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)range error:(NSError **)error
{
    NSRange r = range ? *range : NSMakeRange(0, [string length]);
    NSString *sub = [string substringWithRange:r], *plain = [self _unrelative:sub];
    BOOL relative = plain != sub;
    struct got g;
    memset(&g, 0, sizeof g);
    g.ampm = g.era = -1;
    NSUInteger pos = 0;
    NSDate *date = nil;
    if ([[self dateFormat] length] && [self _read:plain at:&pos into:&g])
        date = [self _dateFrom:&g];
    if (!date) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:2048
                                     userInfo:@{
                                         NSLocalizedDescriptionKey : [NSString
                                             stringWithFormat:@"The value “%@” is invalid.", sub]
                                     }];
        return NO;
    }
    if (range)
        *range = NSMakeRange(r.location, relative ? r.length : pos);   /* a relative day is read whole */
    if (obj)
        *obj = date;
    return YES;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error
{
    NSDate *d = [self dateFromString:string];
    if (!d) {
        if (error)
            *error = @"Error";
        return NO;
    }
    if (obj)
        *obj = d;
    return YES;
}

/* ---- templates ---- */

/* The English (United States) pattern for a template's fields: their order,
 * punctuation and spelling, from which fields and widths it asks for. */
+ (NSString *)dateFormatFromTemplate:(NSString *)tmpl options:(NSUInteger)opts locale:(NSLocale *)locale
{
    int cnt[128] = {0};
    NSUInteger n = [tmpl length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [tmpl characterAtIndex:i];
        if (c == '\'') {   /* quoted text has no place in a template */
            while (++i < n && [tmpl characterAtIndex:i] != '\'')
                ;
            continue;
        }
        if (c < 128 && isalpha(c))
            cnt[c]++;
    }
    int y = cnt['y'] + cnt['Y'] + cnt['u'], M = cnt['M'] + cnt['L'], d = cnt['d'], E = cnt['E'] + cnt['c'] + cnt['e'];
    int h12 = cnt['j'] + cnt['h'] + cnt['K'], h24 = cnt['H'] + cnt['k'], m = cnt['m'], s = cnt['s'];
    NSString *ys = y == 2 ? @"yy" : @"y", *Es = E >= 4 ? @"EEEE" : @"EEE", *ds = d >= 2 ? @"dd" : @"d";
    NSMutableString *date = [NSMutableString string], *time = [NSMutableString string];
    if (E && (M || d))
        [date appendFormat:@"%@, ", Es];
    if (M >= 3) {
        [date appendString:M == 3 ? @"MMM" : M == 4 ? @"MMMM" : @"MMMMM"];
        if (d)
            [date appendFormat:@" %@", ds];
        if (y)
            [date appendFormat:d ? @", %@" : @" %@", ys];
    } else if (M || d) {
        NSMutableArray *f = [NSMutableArray array];
        if (M)
            [f addObject:M == 2 ? @"MM" : @"M"];
        if (d)
            [f addObject:ds];
        if (y)
            [f addObject:ys];
        [date appendString:[f componentsJoinedByString:@"/"]];
    } else if (cnt['Q']) {
        [date appendString:cnt['Q'] >= 4 ? @"QQQQ" : @"QQQ"];
        if (y)
            [date appendFormat:@" %@", ys];
    } else if (y && E) {
        [date appendFormat:@"%@ %@", Es, ys];
    } else if (y) {
        [date appendString:ys];
    } else if (E) {
        [date appendString:Es];
    }
    if (cnt['G'] && y)
        [date appendString:@" G"];
    BOOL twelve = h12 || (cnt['a'] && !h24);
    if (twelve || h24) {
        [time appendString:twelve ? (cnt['K'] ? @"K" : @"h") : (cnt['k'] ? @"kk" : @"HH")];
        if (m)
            [time appendString:@":mm"];
        if (s)
            [time appendString:@":ss"];
        if (twelve)
            [time appendString:@" a"];
    } else if (m) {
        [time appendString:s ? @"mm:ss" : @"mm"];
    } else if (s) {
        [time appendString:@"ss"];
    }
    if ([time length] && cnt['z'])
        [time appendString:cnt['z'] >= 4 ? @" zzzz" : @" z"];
    else if ([time length] && cnt['v'])
        [time appendString:cnt['v'] >= 4 ? @" vvvv" : @" v"];
    if ([date length] && [time length])
        return [NSString stringWithFormat:M >= 4 ? @"%@ 'at' %@" : @"%@, %@", date, time];
    if ([date length] || [time length])
        return [date length] ? [NSString stringWithString:date] : [NSString stringWithString:time];
    return nil;
}

- (void)setLocalizedDateFormatFromTemplate:(NSString *)tmpl
{
    NSString *f = [NSDateFormatter dateFormatFromTemplate:tmpl options:0 locale:[self locale]];
    if (f)
        [self setDateFormat:f];
}

/* A nib's date formatter keeps its settings in "NS.attributes", named as
 * the properties are; older ones have their format in "NS.format". */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [self init]))
        return nil;
    NSDictionary *attrs = [coder decodeObjectForKey:@"NS.attributes"];
    if ([attrs isKindOfClass:[NSDictionary class]] && [attrs count]) {
        FApplyFormatterAttributes(self, attrs, @[ @"formatterBehavior", @"dateStyle", @"timeStyle" ]);
        return self;
    }
    NSString *format = [coder decodeObjectForKey:@"NS.format"];
    if ([format isKindOfClass:[NSString class]])
        [self setDateFormat:format];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    [attrs setObject:@([self formatterBehavior]) forKey:@"formatterBehavior"];
    [attrs setObject:@([self dateStyle]) forKey:@"dateStyle"];
    [attrs setObject:@([self timeStyle]) forKey:@"timeStyle"];
    if ([self dateFormat])
        [attrs setObject:[self dateFormat] forKey:@"dateFormat"];
    [attrs setObject:@([self isLenient]) forKey:@"lenient"];
    [coder encodeObject:attrs forKey:@"NS.attributes"];
}
@end
