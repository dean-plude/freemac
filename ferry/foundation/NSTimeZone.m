/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSTimeZone and NSLocale, the parts date formatting
 * needs, written from Apple's public documentation of both classes; no
 * Apple code was used.
 *
 * A named time zone is read from this system's time zone database
 * (/usr/share/zoneinfo, or $TZDIR), in the TZif format its documentation
 * (tzfile(5), RFC 8536) describes: the times of each change of offset,
 * with the offset, abbreviation and daylight saving flag after it, and a
 * POSIX TZ rule for the years after the last listed change. The system's
 * zone is $TZ, else the one /etc/localtime names. A zone made from an offset
 * has that offset always.
 *
 * NSLocale knows identifiers and their parts only: Ferry formats everything
 * in English (United States), whatever the locale. The current locale comes
 * from the AppleLocale default or the usual LC_ALL, LC_MESSAGES and LANG.
 * Built without ARC. */
#import "FInternal.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

NSNotificationName const NSSystemTimeZoneDidChangeNotification = @"NSSystemTimeZoneDidChangeNotification";

/* ---- the calendar ------------------------------------------------------------------- */

/* Days since 1 January 1970 of a date in the proleptic Gregorian calendar. */
int64_t FDaysFromCivil(int64_t y, int m, int d)
{
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    int64_t yoe = y - era * 400;
    int64_t doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

void FCivilFromDays(int64_t z, int64_t *y, int *m, int *d)
{
    z += 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    int64_t doe = z - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64_t mp = (5 * doy + 2) / 153;
    *d = (int)(doy - (153 * mp + 2) / 5 + 1);
    *m = (int)(mp < 10 ? mp + 3 : mp - 9);
    *y = yoe + era * 400 + (*m <= 2);
}

static int64_t floor_div(int64_t a, int64_t b) { return a / b - ((a % b) && ((a < 0) != (b < 0))); }

static BOOL leap_year(int64_t y) { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0; }

/* ---- POSIX TZ rules ------------------------------------------------------------------------ */

struct rule_date {
    char kind;          /* 'J' (1-365, no 29 February), 'n' (0-365), 'M' (month, week, day) */
    int a, b, c;
    int32_t time;       /* seconds after local midnight */
};

struct tzrule {
    char std[16], dst[16];
    int32_t std_off, dst_off;   /* seconds east of UTC */
    BOOL has_dst;
    struct rule_date start, end;
};

static const char *rule_name(const char *p, char *out)
{
    size_t n = 0;
    if (*p == '<') {
        p++;
        while (*p && *p != '>') {
            if (n < 15)
                out[n++] = *p;
            p++;
        }
        if (*p != '>')
            return NULL;
        p++;
    } else {
        while ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) {
            if (n < 15)
                out[n++] = *p;
            p++;
        }
    }
    out[n] = 0;
    return n >= 3 ? p : NULL;
}

static const char *rule_time(const char *p, int32_t *out)
{
    int sign = 1;
    if (*p == '+' || *p == '-')
        sign = *p++ == '-' ? -1 : 1;
    if (*p < '0' || *p > '9')
        return NULL;
    long h = strtol(p, (char **)&p, 10), m = 0, s = 0;
    if (*p == ':') {
        m = strtol(p + 1, (char **)&p, 10);
        if (*p == ':')
            s = strtol(p + 1, (char **)&p, 10);
    }
    *out = (int32_t)(sign * (h * 3600 + m * 60 + s));
    return p;
}

static const char *rule_date(const char *p, struct rule_date *d)
{
    if (*p == 'M') {
        d->kind = 'M';
        d->a = (int)strtol(p + 1, (char **)&p, 10);
        if (*p != '.')
            return NULL;
        d->b = (int)strtol(p + 1, (char **)&p, 10);
        if (*p != '.')
            return NULL;
        d->c = (int)strtol(p + 1, (char **)&p, 10);
    } else if (*p == 'J') {
        d->kind = 'J';
        d->a = (int)strtol(p + 1, (char **)&p, 10);
    } else if (*p >= '0' && *p <= '9') {
        d->kind = 'n';
        d->a = (int)strtol(p, (char **)&p, 10);
    } else {
        return NULL;
    }
    d->time = 7200;
    if (*p == '/')
        p = rule_time(p + 1, &d->time);
    return p;
}

static BOOL parse_rule(const char *p, struct tzrule *r)
{
    memset(r, 0, sizeof *r);
    int32_t west;
    if (!(p = rule_name(p, r->std)) || !(p = rule_time(p, &west)))
        return NO;
    r->std_off = -west;
    if (!*p)
        return YES;
    if (!(p = rule_name(p, r->dst)))
        return NO;
    r->has_dst = YES;
    r->dst_off = r->std_off + 3600;
    if (*p && *p != ',') {
        if (!(p = rule_time(p, &west)))
            return NO;
        r->dst_off = -west;
    }
    if (*p != ',') {   /* no rule given: the United States' current one */
        r->start = (struct rule_date){'M', 3, 2, 0, 7200};
        r->end = (struct rule_date){'M', 11, 1, 0, 7200};
        return YES;
    }
    if (!(p = rule_date(p + 1, &r->start)) || *p != ',' || !(p = rule_date(p + 1, &r->end)))
        return NO;
    return YES;
}

/* The local day (days since 1970) a rule date falls on in year y. */
static int64_t rule_day(const struct rule_date *d, int64_t y)
{
    int64_t jan1 = FDaysFromCivil(y, 1, 1);
    if (d->kind == 'J')
        return jan1 + d->a - 1 + (leap_year(y) && d->a >= 60);
    if (d->kind == 'n')
        return jan1 + d->a;
    int64_t first = FDaysFromCivil(y, d->a, 1);
    int wd = (int)((first + 4) % 7 + 7) % 7;   /* 1 January 1970 was a Thursday */
    int64_t day = first + (d->c - wd + 7) % 7 + (d->b - 1) * 7;
    int dim = d->a == 2 ? (leap_year(y) ? 29 : 28) : (d->a == 4 || d->a == 6 || d->a == 9 || d->a == 11) ? 30 : 31;
    while (day >= first + dim)
        day -= 7;
    return day;
}

/* The offset, flag and abbreviation the rule gives at UTC time t. */
static void rule_at(const struct tzrule *r, int64_t t, int32_t *off, BOOL *dst, const char **abbr)
{
    *off = r->std_off;
    *dst = NO;
    *abbr = r->std;
    if (!r->has_dst)
        return;
    int64_t y;
    int m, d;
    FCivilFromDays(floor_div(t + r->std_off, 86400), &y, &m, &d);
    int64_t start = rule_day(&r->start, y) * 86400 + r->start.time - r->std_off;
    int64_t end = rule_day(&r->end, y) * 86400 + r->end.time - r->dst_off;
    BOOL in = start < end ? (t >= start && t < end) : (t >= start || t < end);
    if (in) {
        *off = r->dst_off;
        *dst = YES;
        *abbr = r->dst;
    }
}

/* ---- NSTimeZone -------------------------------------------------------------------------- */

struct tztype {
    int32_t off;
    BOOL dst;
    char abbr[16];
};

static NSString *zone_dir(void)
{
    const char *d = getenv("TZDIR");
    return [NSString stringWithUTF8String:d && *d ? d : "/usr/share/zoneinfo"];
}

static uint64_t be(const uint8_t *p, int n)
{
    uint64_t v = 0;
    for (int i = 0; i < n; i++)
        v = v << 8 | p[i];
    return v;
}

@implementation NSTimeZone {
    NSString *_name;
    NSData *_data;
    int64_t *_times;
    uint8_t *_which;
    size_t _ntimes;
    struct tztype *_types;
    size_t _ntypes;
    struct tzrule _rule;
    BOOL _hasRule;
}

static NSTimeZone *default_zone, *system_zone;

/* Reads TZif data (version 1, or the 64-bit part of versions 2 and later). */
- (BOOL)_readData:(NSData *)data
{
    const uint8_t *b = [data bytes], *end = b + [data length];
    if ([data length] < 44 || memcmp(b, "TZif", 4))
        return NO;
    int version = b[4] ? b[4] - '0' : 1;
    int width = 4;
    const uint8_t *h = b;
    for (int pass = 0; pass < 2; pass++) {
        if (end - h < 44)
            return NO;
        uint64_t isut = be(h + 20, 4), isstd = be(h + 24, 4), leap = be(h + 28, 4), ntime = be(h + 32, 4),
                 ntype = be(h + 36, 4), nchar = be(h + 40, 4);
        const uint8_t *p = h + 44;
        size_t size = ntime * width + ntime + ntype * 6 + nchar + leap * (width + 4) + isstd + isut;
        if ((uint64_t)(end - p) < size || ntype == 0 || ntype > 256)
            return NO;
        if (pass == 0 && version >= 2) {
            h = p + size;
            width = 8;
            continue;
        }
        free(_times);
        free(_which);
        free(_types);
        _ntimes = ntime;
        _ntypes = ntype;
        _times = calloc(ntime + 1, sizeof *_times);
        _which = calloc(ntime + 1, 1);
        _types = calloc(ntype, sizeof *_types);
        for (size_t i = 0; i < ntime; i++)
            _times[i] = width == 8 ? (int64_t)be(p + i * 8, 8) : (int64_t)(int32_t)be(p + i * 4, 4);
        p += ntime * width;
        for (size_t i = 0; i < ntime; i++)
            _which[i] = p[i] < ntype ? p[i] : 0;
        p += ntime;
        const uint8_t *chars = p + ntype * 6;
        for (size_t i = 0; i < ntype; i++) {
            _types[i].off = (int32_t)be(p + i * 6, 4);
            _types[i].dst = p[i * 6 + 4] != 0;
            size_t ai = p[i * 6 + 5];
            if (ai < nchar)
                strncpy(_types[i].abbr, (const char *)chars + ai, sizeof _types[i].abbr - 1);
        }
        p += size - ntime * width - ntime;
        if (version >= 2 && p < end && *p == '\n') {
            const uint8_t *nl = memchr(p + 1, '\n', (size_t)(end - p - 1));
            if (nl) {
                char *footer = strndup((const char *)p + 1, (size_t)(nl - p - 1));
                _hasRule = *footer && parse_rule(footer, &_rule);
                free(footer);
            }
        }
        return YES;
    }
    return NO;
}

- (instancetype)_initWithName:(NSString *)name data:(NSData *)data
{
    if (!(self = [super init]))
        return nil;
    if (![self _readData:data]) {
        [self release];
        return nil;
    }
    _name = [name copy];
    _data = [data copy];
    return self;
}

- (instancetype)_initWithOffset:(NSInteger)seconds
{
    if (!(self = [super init]))
        return nil;
    _ntypes = 1;
    _types = calloc(1, sizeof *_types);
    _types[0].off = (int32_t)seconds;
    long a = labs((long)seconds);
    if (seconds == 0) {
        strcpy(_types[0].abbr, "GMT");
        _name = @"GMT";
    } else {
        if (a % 3600)
            snprintf(_types[0].abbr, sizeof _types[0].abbr, "GMT%c%ld:%02ld", seconds < 0 ? '-' : '+', a / 3600,
                     a / 60 % 60);
        else
            snprintf(_types[0].abbr, sizeof _types[0].abbr, "GMT%c%ld", seconds < 0 ? '-' : '+', a / 3600);
        _name = [[NSString alloc] initWithFormat:@"GMT%c%02ld%02ld", seconds < 0 ? '-' : '+', a / 3600, a / 60 % 60];
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name
{
    if (!name || ![name length] || [name hasPrefix:@"/"] || [name rangeOfString:@".."].location != NSNotFound) {
        [self release];
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:[zone_dir() stringByAppendingPathComponent:name]];
    if (!data) {
        [self release];
        return nil;
    }
    return [self _initWithName:name data:data];
}

- (instancetype)initWithName:(NSString *)name data:(NSData *)data
{
    if (!data)
        return [self initWithName:name];
    return [self _initWithName:name data:data];
}

+ (instancetype)timeZoneWithName:(NSString *)name
{
    return [[[self alloc] initWithName:name] autorelease];
}

+ (instancetype)timeZoneWithName:(NSString *)name data:(NSData *)data
{
    return [[[self alloc] initWithName:name data:data] autorelease];
}

+ (instancetype)timeZoneForSecondsFromGMT:(NSInteger)seconds
{
    if (seconds < -18 * 3600 || seconds > 18 * 3600)
        return nil;
    return [[[self alloc] _initWithOffset:seconds] autorelease];
}

+ (NSDictionary *)abbreviationDictionary
{
    static NSDictionary *d;
    if (!d)
        d = [@{
            @"GMT" : @"GMT", @"UTC" : @"UTC", @"BST" : @"Europe/London", @"WET" : @"Europe/Lisbon",
            @"WEST" : @"Europe/Lisbon", @"CET" : @"Europe/Paris", @"CEST" : @"Europe/Paris",
            @"EET" : @"Europe/Athens", @"EEST" : @"Europe/Athens", @"MSK" : @"Europe/Moscow",
            @"IST" : @"Asia/Kolkata", @"SGT" : @"Asia/Singapore", @"HKT" : @"Asia/Hong_Kong",
            @"JST" : @"Asia/Tokyo", @"KST" : @"Asia/Seoul", @"EST" : @"America/New_York",
            @"EDT" : @"America/New_York", @"CST" : @"America/Chicago", @"CDT" : @"America/Chicago",
            @"MST" : @"America/Denver", @"MDT" : @"America/Denver", @"PST" : @"America/Los_Angeles",
            @"PDT" : @"America/Los_Angeles", @"AKST" : @"America/Juneau", @"AKDT" : @"America/Juneau",
            @"HST" : @"Pacific/Honolulu", @"NZST" : @"Pacific/Auckland", @"NZDT" : @"Pacific/Auckland",
            @"AEST" : @"Australia/Sydney", @"AEDT" : @"Australia/Sydney",
        } retain];
    return d;
}

+ (instancetype)timeZoneWithAbbreviation:(NSString *)abbr
{
    if ([abbr isEqualToString:@"GMT"] || [abbr isEqualToString:@"UTC"])
        return [self timeZoneForSecondsFromGMT:0];
    NSString *name = [[self abbreviationDictionary] objectForKey:abbr];
    return name ? [self timeZoneWithName:name] : nil;
}

+ (NSArray *)knownTimeZoneNames
{
    NSMutableArray *names = [NSMutableArray array];
    NSString *tab = [NSString stringWithContentsOfFile:[zone_dir() stringByAppendingPathComponent:@"zone.tab"]
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    for (NSString *line in [tab componentsSeparatedByString:@"\n"]) {
        if (![line length] || [line hasPrefix:@"#"])
            continue;
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if ([f count] >= 3)
            [names addObject:[f objectAtIndex:2]];
    }
    [names addObject:@"GMT"];
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSTimeZone *)systemTimeZone
{
    if (system_zone)
        return system_zone;
    NSTimeZone *z = nil;
    const char *tz = getenv("TZ");
    if (tz && *tz) {
        if (*tz == ':')
            tz++;
        if (*tz == '/')
            z = [[NSTimeZone alloc] _initWithName:[[NSString stringWithUTF8String:tz] lastPathComponent]
                                              data:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:tz]]];
        else
            z = [[NSTimeZone alloc] initWithName:[NSString stringWithUTF8String:tz]];
        if (!z) {   /* a bare POSIX rule, such as EST5EDT */
            struct tzrule r;
            if (parse_rule(tz, &r)) {
                z = [[NSTimeZone alloc] _initWithOffset:r.std_off];
                z->_rule = r;
                z->_hasRule = r.has_dst;
                [z->_name release];
                z->_name = [[NSString alloc] initWithUTF8String:tz];
                strncpy(z->_types[0].abbr, r.std, sizeof z->_types[0].abbr - 1);
            }
        }
    }
    if (!z) {
        char target[1024];
        ssize_t n = readlink("/etc/localtime", target, sizeof target - 1);
        NSString *name = nil;
        if (n > 0) {
            target[n] = 0;
            char *p = strstr(target, "zoneinfo/");
            if (p)
                name = [NSString stringWithUTF8String:p + 9];
        }
        if (!name) {
            NSString *etc = [NSString stringWithContentsOfFile:@"/etc/timezone" encoding:NSUTF8StringEncoding error:NULL];
            etc = [etc stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([etc length])
                name = etc;
        }
        NSData *data = [NSData dataWithContentsOfFile:@"/etc/localtime"];
        if (data)
            z = [[NSTimeZone alloc] _initWithName:name ?: @"Local" data:data];
        else if (name)
            z = [[NSTimeZone alloc] initWithName:name];
    }
    if (!z)
        z = [[NSTimeZone alloc] _initWithOffset:0];
    system_zone = z;
    return system_zone;
}

+ (void)resetSystemTimeZone
{
    [system_zone release];
    system_zone = nil;
}

+ (NSTimeZone *)defaultTimeZone { return default_zone ?: [self systemTimeZone]; }
+ (void)setDefaultTimeZone:(NSTimeZone *)zone
{
    [zone retain];
    [default_zone release];
    default_zone = zone;
}
+ (NSTimeZone *)localTimeZone { return [self defaultTimeZone]; }

- (void)dealloc
{
    [_name release];
    [_data release];
    free(_times);
    free(_which);
    free(_types);
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (NSString *)name { return _name; }
- (NSData *)data { return _data ?: [NSData data]; }

/* The offset, flag and abbreviation in effect at UTC time t (seconds since 1970). */
- (void)_at:(int64_t)t offset:(int32_t *)off dst:(BOOL *)dst abbreviation:(const char **)abbr
{
    if (_ntimes && t >= _times[_ntimes - 1] && _hasRule) {
        rule_at(&_rule, t, off, dst, abbr);
        return;
    }
    if (!_ntimes && _hasRule) {
        rule_at(&_rule, t, off, dst, abbr);
        return;
    }
    const struct tztype *ty = NULL;
    if (!_ntimes || t < _times[0]) {
        /* before the first change: the first standard time type */
        for (size_t i = 0; i < _ntypes && !ty; i++)
            if (!_types[i].dst)
                ty = &_types[i];
        if (!ty)
            ty = &_types[0];
    } else {
        size_t lo = 0, hi = _ntimes;   /* the last change at or before t */
        while (hi - lo > 1) {
            size_t mid = (lo + hi) / 2;
            if (_times[mid] <= t)
                lo = mid;
            else
                hi = mid;
        }
        ty = &_types[_which[lo]];
    }
    *off = ty->off;
    *dst = ty->dst;
    *abbr = ty->abbr;
}

static int64_t unix_time(NSDate *date)
{
    return (int64_t)floor([(date ?: [NSDate date]) timeIntervalSince1970]);
}

- (NSInteger)secondsFromGMTForDate:(NSDate *)date
{
    int32_t off;
    BOOL dst;
    const char *abbr;
    [self _at:unix_time(date) offset:&off dst:&dst abbreviation:&abbr];
    return off;
}

- (NSString *)abbreviationForDate:(NSDate *)date
{
    int32_t off;
    BOOL dst;
    const char *abbr;
    [self _at:unix_time(date) offset:&off dst:&dst abbreviation:&abbr];
    /* numeric abbreviations ("+03", "-0430") read as GMT offsets, as on a Mac */
    if (!*abbr || *abbr == '+' || *abbr == '-') {
        long a = labs((long)off);
        if (!off)
            return @"GMT";
        return a % 3600 ? [NSString stringWithFormat:@"GMT%c%ld:%02ld", off < 0 ? '-' : '+', a / 3600, a / 60 % 60]
                        : [NSString stringWithFormat:@"GMT%c%ld", off < 0 ? '-' : '+', a / 3600];
    }
    return [NSString stringWithUTF8String:abbr];
}

- (BOOL)isDaylightSavingTimeForDate:(NSDate *)date
{
    int32_t off;
    BOOL dst;
    const char *abbr;
    [self _at:unix_time(date) offset:&off dst:&dst abbreviation:&abbr];
    return dst;
}

- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)date
{
    int64_t t = unix_time(date);
    int32_t off, soff;
    BOOL dst;
    const char *abbr;
    [self _at:t offset:&off dst:&dst abbreviation:&abbr];
    if (!dst)
        return 0;
    if (_hasRule && (!_ntimes || t >= _times[_ntimes - 1]))
        return _rule.dst_off - _rule.std_off;
    /* against the standard time in effect before it */
    for (int64_t back = t; back > t - 366LL * 86400 * 2; back -= 86400 * 7) {
        [self _at:back offset:&soff dst:&dst abbreviation:&abbr];
        if (!dst)
            return off - soff;
    }
    return 3600;
}

- (NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)date
{
    int64_t t = unix_time(date);
    for (size_t i = 0; i < _ntimes; i++)
        if (_times[i] > t)
            return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)_times[i]];
    if (!_hasRule || !_rule.has_dst)
        return nil;
    int64_t y;
    int m, d;
    FCivilFromDays(floor_div(t, 86400), &y, &m, &d);
    int64_t best = INT64_MAX;
    for (int64_t yy = y - 1; yy <= y + 1; yy++) {
        int64_t s = rule_day(&_rule.start, yy) * 86400 + _rule.start.time - _rule.std_off;
        int64_t e = rule_day(&_rule.end, yy) * 86400 + _rule.end.time - _rule.dst_off;
        if (s > t && s < best)
            best = s;
        if (e > t && e < best)
            best = e;
    }
    return best == INT64_MAX ? nil : [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)best];
}

- (NSInteger)secondsFromGMT { return [self secondsFromGMTForDate:[NSDate date]]; }
- (NSString *)abbreviation { return [self abbreviationForDate:[NSDate date]]; }
- (BOOL)isDaylightSavingTime { return [self isDaylightSavingTimeForDate:[NSDate date]]; }
- (NSTimeInterval)daylightSavingTimeOffset { return [self daylightSavingTimeOffsetForDate:[NSDate date]]; }
- (NSDate *)nextDaylightSavingTimeTransition { return [self nextDaylightSavingTimeTransitionAfterDate:[NSDate date]]; }

- (BOOL)isEqualToTimeZone:(NSTimeZone *)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSTimeZone class]] || ![_name isEqualToString:[other name]])
        return NO;
    if (!_data && !other->_data)
        return _types[0].off == other->_types[0].off;
    return [[self data] isEqual:[other data]];
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[NSTimeZone class]] && [self isEqualToTimeZone:other]; }
- (NSUInteger)hash { return [_name hash]; }

- (NSString *)description
{
    NSDate *now = [NSDate date];
    return [NSString stringWithFormat:@"%@ (%@) offset %ld%@", _name, [self abbreviationForDate:now],
                                      (long)[self secondsFromGMTForDate:now],
                                      [self isDaylightSavingTimeForDate:now] ? @" (Daylight)" : @""];
}
@end

/* ---- NSLocale ---------------------------------------------------------------------------- */

NSLocaleKey const NSLocaleIdentifier = @"locale:id";
NSLocaleKey const NSLocaleLanguageCode = @"locale:language code";
NSLocaleKey const NSLocaleCountryCode = @"locale:country code";
NSLocaleKey const NSLocaleScriptCode = @"locale:script code";
NSLocaleKey const NSLocaleVariantCode = @"locale:variant code";
NSLocaleKey const NSLocaleDecimalSeparator = @"locale:decimal separator";
NSLocaleKey const NSLocaleGroupingSeparator = @"locale:grouping separator";
NSLocaleKey const NSLocaleUsesMetricSystem = @"locale:uses metric";
NSNotificationName const NSCurrentLocaleDidChangeNotification = @"kCFLocaleCurrentLocaleDidChangeNotification";

static BOOL all_in(NSString *s, BOOL upper, NSUInteger min, NSUInteger max)
{
    NSUInteger n = [s length];
    if (n < min || n > max)
        return NO;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (!(upper ? (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') : (c >= 'a' && c <= 'z')))
            return NO;
    }
    return YES;
}

@implementation NSLocale {
    NSString *_id;
    NSDictionary *_parts;
}

/* language[_Script][_COUNTRY][_VARIANT], from either "_" or "-"; any "@..." keywords are dropped. */
+ (NSDictionary *)componentsFromLocaleIdentifier:(NSString *)string
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSString *s = [[string componentsSeparatedByString:@"@"] objectAtIndex:0];
    s = [s stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSArray *f = [s componentsSeparatedByString:@"_"];
    NSUInteger i = 0;
    if ([f count] && [[f objectAtIndex:0] length])
        [d setObject:[[f objectAtIndex:i] lowercaseString] forKey:NSLocaleLanguageCode];
    i++;
    if (i < [f count] && [[f objectAtIndex:i] length] == 4) {
        NSString *sc = [f objectAtIndex:i++];
        [d setObject:[[[sc substringToIndex:1] uppercaseString] stringByAppendingString:[[sc substringFromIndex:1]
                                                                                            lowercaseString]]
              forKey:NSLocaleScriptCode];
    }
    if (i < [f count] && all_in([[f objectAtIndex:i] uppercaseString], YES, 2, 3))
        [d setObject:[[f objectAtIndex:i++] uppercaseString] forKey:NSLocaleCountryCode];
    if (i < [f count] && [[f objectAtIndex:i] length])
        [d setObject:[[f objectAtIndex:i] uppercaseString] forKey:NSLocaleVariantCode];
    return d;
}

+ (NSString *)canonicalLocaleIdentifierFromString:(NSString *)string
{
    NSDictionary *d = [self componentsFromLocaleIdentifier:string];
    NSMutableString *s = [NSMutableString stringWithString:[d objectForKey:NSLocaleLanguageCode] ?: @""];
    for (NSString *k in @[ NSLocaleScriptCode, NSLocaleCountryCode, NSLocaleVariantCode ]) {
        if ([d objectForKey:k]) {
            [s appendString:@"_"];
            [s appendString:[d objectForKey:k]];
        }
    }
    return s;
}

+ (instancetype)localeWithLocaleIdentifier:(NSString *)ident
{
    return [[[self alloc] initWithLocaleIdentifier:ident] autorelease];
}

- (instancetype)initWithLocaleIdentifier:(NSString *)string
{
    if ((self = [super init])) {
        _id = [(string ?: @"") copy];
        _parts = [[NSLocale componentsFromLocaleIdentifier:_id] retain];
    }
    return self;
}

- (instancetype)init { return [self initWithLocaleIdentifier:@""]; }

- (void)dealloc
{
    [_id release];
    [_parts release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

+ (NSLocale *)currentLocale
{
    static NSLocale *current;
    if (!current) {
        NSString *ident = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleLocale"];
        if (![ident length]) {
            const char *vars[] = {"LC_ALL", "LC_MESSAGES", "LANG"};
            for (int i = 0; i < 3 && !ident; i++) {
                const char *v = getenv(vars[i]);
                if (v && *v && strcmp(v, "C") && strcmp(v, "POSIX") && strncmp(v, "C.", 2))
                    ident = [[[NSString stringWithUTF8String:v] componentsSeparatedByString:@"."] objectAtIndex:0];
            }
        }
        current = [[NSLocale alloc] initWithLocaleIdentifier:[ident length] ? ident : @"en_US"];
    }
    return current;
}

+ (NSLocale *)autoupdatingCurrentLocale { return [self currentLocale]; }

+ (NSLocale *)systemLocale
{
    static NSLocale *sys;
    if (!sys)
        sys = [[NSLocale alloc] initWithLocaleIdentifier:@""];
    return sys;
}

+ (NSArray *)preferredLanguages
{
    NSLocale *c = [self currentLocale];
    NSString *lang = [c languageCode] ?: @"en";
    NSString *country = [c countryCode];
    return @[ country ? [NSString stringWithFormat:@"%@-%@", lang, country] : lang ];
}

+ (NSArray *)availableLocaleIdentifiers
{
    return @[ @"en", @"en_US", @"en_US_POSIX", @"en_GB" ];
}

+ (NSArray *)ISOLanguageCodes { return @[ @"en" ]; }

- (id)objectForKey:(NSLocaleKey)key
{
    if ([key isEqualToString:NSLocaleIdentifier])
        return _id;
    if ([key isEqualToString:NSLocaleDecimalSeparator])
        return [self decimalSeparator];
    if ([key isEqualToString:NSLocaleGroupingSeparator])
        return [self groupingSeparator];
    if ([key isEqualToString:NSLocaleUsesMetricSystem])
        return [NSNumber numberWithBool:[self usesMetricSystem]];
    return [_parts objectForKey:key];
}

- (NSString *)displayNameForKey:(NSLocaleKey)key value:(id)value
{
    if ([key isEqualToString:NSLocaleIdentifier] || [key isEqualToString:NSLocaleLanguageCode]) {
        NSString *lang = [[NSLocale componentsFromLocaleIdentifier:value] objectForKey:NSLocaleLanguageCode];
        if ([lang isEqualToString:@"en"])
            return @"English";
    }
    return nil;
}

- (NSString *)localeIdentifier { return _id; }
- (NSString *)languageCode { return [_parts objectForKey:NSLocaleLanguageCode]; }
- (NSString *)countryCode { return [_parts objectForKey:NSLocaleCountryCode]; }
- (NSString *)regionCode { return [self countryCode]; }
- (NSString *)scriptCode { return [_parts objectForKey:NSLocaleScriptCode]; }
- (NSString *)variantCode { return [_parts objectForKey:NSLocaleVariantCode]; }
- (NSString *)decimalSeparator { return @"."; }
- (NSString *)groupingSeparator { return @","; }
- (BOOL)usesMetricSystem
{
    NSString *c = [self countryCode];
    return !(c && ([c isEqualToString:@"US"] || [c isEqualToString:@"LR"] || [c isEqualToString:@"MM"]));
}
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[NSLocale class]] && [_id isEqualToString:[other localeIdentifier]]);
}
- (NSUInteger)hash { return [_id hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ (fixed)", _id];
}
@end
