/* SPDX-License-Identifier: GPL-3.0-or-later
 * Older Foundation classes that Sequel Pro and other apps written for Mac
 * OS X 10.6 to 10.10 still use (freemac 1.226, Ferry 0.50.0):
 * NSCalendarDate, NSScriptExecutionContext and NSConnection. See
 * FoundationOlder.h. Written from Apple's public documentation of them;
 * no Apple code was read. The day arithmetic is the proleptic Gregorian
 * calendar's, counted from 1 January 1970. */
#import "FInternal.h"
#include <math.h>
#include <string.h>

/* ---- the Gregorian calendar ----------------------------------------------------------- */

static long floor_div(long a, long b) { return (a >= 0 ? a : a - b + 1) / b; }

/* days since 1 January 1970 of a date */
static long days_from_civil(long y, long m, long d)
{
    y -= m <= 2;
    long era = floor_div(y, 400);
    long yoe = y - era * 400;
    long doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
    long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

static void civil_from_days(long z, long *y, long *m, long *d)
{
    z += 719468;
    long era = floor_div(z, 146097);
    long doe = z - era * 146097;
    long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    long mp = (5 * doy + 2) / 153;
    *d = doy - (153 * mp + 2) / 5 + 1;
    *m = mp < 10 ? mp + 3 : mp - 9;
    *y = yoe + era * 400 + (*m <= 2);
}

struct fields {
    long year, month, day, hour, minute, second, millisecond, weekday, yearday, days;
};

static NSString *const month_names[] = {@"January", @"February", @"March", @"April", @"May", @"June", @"July",
                                         @"August", @"September", @"October", @"November", @"December"};
static NSString *const day_names[] = {@"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday",
                                       @"Saturday"};

/* ---- calendar dates ----------------------------------------------------------------------- */

@implementation NSCalendarDate {
    NSTimeInterval _t;
    NSTimeZone *_zone;
    NSString *_format;
}

+ (instancetype)calendarDate { return [[[self alloc] init] autorelease]; }

+ (instancetype)dateWithString:(NSString *)description calendarFormat:(NSString *)format
{
    return [[[self alloc] initWithString:description calendarFormat:format] autorelease];
}

+ (instancetype)dateWithString:(NSString *)description calendarFormat:(NSString *)format locale:(id)locale
{
    return [[[self alloc] initWithString:description calendarFormat:format locale:locale] autorelease];
}

+ (instancetype)dateWithYear:(NSInteger)year month:(NSUInteger)month day:(NSUInteger)day hour:(NSUInteger)hour
                      minute:(NSUInteger)minute second:(NSUInteger)second timeZone:(NSTimeZone *)aTimeZone
{
    return [[[self alloc] initWithYear:year month:month day:day hour:hour minute:minute second:second
                              timeZone:aTimeZone] autorelease];
}

- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    if ((self = [super initWithTimeIntervalSinceReferenceDate:secs]))
        _t = secs;
    return self;
}

- (instancetype)init
{
    return [self initWithTimeIntervalSinceReferenceDate:[[NSDate date] timeIntervalSinceReferenceDate]];
}

- (void)dealloc
{
    [_zone release];
    [_format release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSCalendarDate *c = [[NSCalendarDate allocWithZone:zone] initWithTimeIntervalSinceReferenceDate:_t];
    c->_zone = [_zone retain];
    c->_format = [_format copy];
    return c;
}

- (NSTimeInterval)timeIntervalSinceReferenceDate { return _t; }

- (NSTimeZone *)timeZone { return _zone ?: [NSTimeZone defaultTimeZone]; }
- (void)setTimeZone:(NSTimeZone *)zone
{
    [zone retain];
    [_zone release];
    _zone = zone;
}
- (NSString *)calendarFormat { return _format ?: @"%Y-%m-%d %H:%M:%S %z"; }
- (void)setCalendarFormat:(NSString *)format
{
    format = [format copy];
    [_format release];
    _format = format;
}

/* the UTC time of a wall-clock time in a zone */
static NSTimeInterval from_local(long y, long mo, long d, long h, long mi, double s, NSTimeZone *zone)
{
    double local = (double)days_from_civil(y, mo, d) * 86400.0 + h * 3600.0 + mi * 60.0 + s - NSTimeIntervalSince1970;
    NSTimeInterval t = local;
    for (int i = 0; i < 2; i++)
        t = local - [zone secondsFromGMTForDate:[NSDate dateWithTimeIntervalSinceReferenceDate:t]];
    return t;
}

- (instancetype)initWithYear:(NSInteger)year month:(NSUInteger)month day:(NSUInteger)day hour:(NSUInteger)hour
                      minute:(NSUInteger)minute second:(NSUInteger)second timeZone:(NSTimeZone *)aTimeZone
{
    NSTimeZone *zone = aTimeZone ?: [NSTimeZone defaultTimeZone];
    if ((self = [self initWithTimeIntervalSinceReferenceDate:from_local(year, (long)month, (long)day, (long)hour,
                                                                         (long)minute, (double)second, zone)]))
        [self setTimeZone:aTimeZone];
    return self;
}

- (struct fields)fields
{
    NSTimeZone *zone = [self timeZone];
    double local = _t + [zone secondsFromGMTForDate:self] + NSTimeIntervalSince1970;
    double whole = floor(local);
    long days = (long)floor(whole / 86400.0);
    long secs = (long)(whole - (double)days * 86400.0);
    struct fields f;
    civil_from_days(days, &f.year, &f.month, &f.day);
    f.hour = secs / 3600;
    f.minute = secs / 60 % 60;
    f.second = secs % 60;
    f.millisecond = (long)floor((local - whole) * 1000.0 + 1e-6);
    if (f.millisecond > 999)
        f.millisecond = 999;
    f.weekday = ((days + 4) % 7 + 7) % 7;
    f.yearday = days - days_from_civil(f.year, 1, 1) + 1;
    f.days = days;
    return f;
}

- (NSInteger)yearOfCommonEra { return [self fields].year; }
- (NSInteger)monthOfYear { return [self fields].month; }
- (NSInteger)dayOfMonth { return [self fields].day; }
- (NSInteger)dayOfWeek { return [self fields].weekday; }
- (NSInteger)dayOfYear { return [self fields].yearday; }
- (NSInteger)dayOfCommonEra { return [self fields].days - days_from_civil(1, 1, 1) + 1; }
- (NSInteger)hourOfDay { return [self fields].hour; }
- (NSInteger)minuteOfHour { return [self fields].minute; }
- (NSInteger)secondOfMinute { return [self fields].second; }

/* Months past the end of a shorter month end on its last day, as on a Mac. */
- (NSCalendarDate *)dateByAddingYears:(NSInteger)year months:(NSInteger)month days:(NSInteger)day
                                hours:(NSInteger)hour minutes:(NSInteger)minute seconds:(NSInteger)second
{
    struct fields f = [self fields];
    long m = f.year * 12 + (f.month - 1) + year * 12 + month;
    long y = floor_div(m, 12), mo = m - y * 12 + 1;
    long last = days_from_civil(mo == 12 ? y + 1 : y, mo == 12 ? 1 : mo + 1, 1) - days_from_civil(y, mo, 1);
    long d = f.day > last ? last : f.day;
    long days = days_from_civil(y, mo, d) + day;
    long yy, mm, dd;
    civil_from_days(days, &yy, &mm, &dd);
    NSTimeInterval t = from_local(yy, mm, dd, f.hour, f.minute, f.second + f.millisecond / 1000.0, [self timeZone]);
    t += hour * 3600.0 + minute * 60.0 + second;
    NSCalendarDate *c = [[[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate:t] autorelease];
    [c setTimeZone:_zone];
    [c setCalendarFormat:_format];
    return c;
}

/* The difference counted in whole units from the largest asked for down. */
- (void)years:(NSInteger *)yp months:(NSInteger *)mop days:(NSInteger *)dp hours:(NSInteger *)hp
      minutes:(NSInteger *)mip seconds:(NSInteger *)sp sinceDate:(NSDate *)date
{
    NSCalendarDate *from = [[[NSCalendarDate alloc]
        initWithTimeIntervalSinceReferenceDate:[date timeIntervalSinceReferenceDate]] autorelease];
    [from setTimeZone:[self timeZone]];
    BOOL backwards = [self timeIntervalSinceReferenceDate] < [from timeIntervalSinceReferenceDate];
    NSCalendarDate *a = backwards ? self : from, *b = backwards ? from : self;
    int sign = backwards ? -1 : 1;
    NSInteger months = 0;
    if (yp || mop) {
        struct fields fa = [a fields], fb = [b fields];
        months = (fb.year - fa.year) * 12 + (fb.month - fa.month);
        while (months > 0 &&
               [[a dateByAddingYears:0 months:months days:0 hours:0 minutes:0 seconds:0] timeIntervalSinceReferenceDate] >
                   [b timeIntervalSinceReferenceDate])
            months--;
        a = [a dateByAddingYears:0 months:months days:0 hours:0 minutes:0 seconds:0];
    }
    if (yp) {
        *yp = sign * (months / 12);
        months %= 12;
    }
    if (mop)
        *mop = sign * months;
    else if (yp)
        a = [a dateByAddingYears:0 months:-months days:0 hours:0 minutes:0 seconds:0];
    double rest = [b timeIntervalSinceReferenceDate] - [a timeIntervalSinceReferenceDate];
    if (dp) {
        *dp = sign * (NSInteger)floor(rest / 86400.0);
        rest -= floor(rest / 86400.0) * 86400.0;
    }
    if (hp) {
        *hp = sign * (NSInteger)floor(rest / 3600.0);
        rest -= floor(rest / 3600.0) * 3600.0;
    }
    if (mip) {
        *mip = sign * (NSInteger)floor(rest / 60.0);
        rest -= floor(rest / 60.0) * 60.0;
    }
    if (sp)
        *sp = sign * (NSInteger)floor(rest);
}

static NSString *zone_offset(NSInteger secs)
{
    NSInteger a = secs < 0 ? -secs : secs;
    return [NSString stringWithFormat:@"%c%02ld%02ld", secs < 0 ? '-' : '+', (long)(a / 3600), (long)(a / 60 % 60)];
}

- (NSString *)descriptionWithCalendarFormat:(NSString *)format locale:(id)locale
{
    if (!format)
        format = [self calendarFormat];
    struct fields f = [self fields];
    NSTimeZone *zone = [self timeZone];
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = [format length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [format characterAtIndex:i];
        if (c != '%' || i + 1 >= n) {
            [out appendFormat:@"%C", c];
            continue;
        }
        unichar s = [format characterAtIndex:++i];
        long h12 = f.hour % 12 ? f.hour % 12 : 12;
        switch (s) {
        case '%': [out appendString:@"%"]; break;
        case 'a': [out appendString:[day_names[f.weekday] substringToIndex:3]]; break;
        case 'A': [out appendString:day_names[f.weekday]]; break;
        case 'b': [out appendString:[month_names[f.month - 1] substringToIndex:3]]; break;
        case 'B': [out appendString:month_names[f.month - 1]]; break;
        case 'c': [out appendString:[self descriptionWithCalendarFormat:@"%a %b %d %H:%M:%S %Z %Y" locale:locale]]; break;
        case 'x': [out appendString:[self descriptionWithCalendarFormat:@"%m/%d/%y" locale:locale]]; break;
        case 'X': [out appendString:[self descriptionWithCalendarFormat:@"%H:%M:%S %Z" locale:locale]]; break;
        case 'd': [out appendFormat:@"%02ld", f.day]; break;
        case 'e': [out appendFormat:@"%ld", f.day]; break;
        case 'F': [out appendFormat:@"%03ld", f.millisecond]; break;
        case 'H': [out appendFormat:@"%02ld", f.hour]; break;
        case 'I': [out appendFormat:@"%02ld", h12]; break;
        case 'j': [out appendFormat:@"%03ld", f.yearday]; break;
        case 'm': [out appendFormat:@"%02ld", f.month]; break;
        case 'M': [out appendFormat:@"%02ld", f.minute]; break;
        case 'p': [out appendString:f.hour < 12 ? @"AM" : @"PM"]; break;
        case 'S': [out appendFormat:@"%02ld", f.second]; break;
        case 'w': [out appendFormat:@"%ld", f.weekday]; break;
        case 'y': [out appendFormat:@"%02ld", ((f.year % 100) + 100) % 100]; break;
        case 'Y': [out appendFormat:@"%ld", f.year]; break;
        case 'Z': [out appendString:[zone abbreviationForDate:self] ?: zone_offset([zone secondsFromGMTForDate:self])]; break;
        case 'z': [out appendString:zone_offset([zone secondsFromGMTForDate:self])]; break;
        default: [out appendFormat:@"%%%C", s]; break;
        }
    }
    return out;
}

- (NSString *)descriptionWithCalendarFormat:(NSString *)format
{
    return [self descriptionWithCalendarFormat:format locale:nil];
}
- (NSString *)descriptionWithLocale:(id)locale { return [self descriptionWithCalendarFormat:nil locale:locale]; }
- (NSString *)description { return [self descriptionWithCalendarFormat:nil locale:nil]; }

- (instancetype)initWithString:(NSString *)description
{
    return [self initWithString:description calendarFormat:nil locale:nil];
}

- (instancetype)initWithString:(NSString *)description calendarFormat:(NSString *)format
{
    return [self initWithString:description calendarFormat:format locale:nil];
}

/* digits at *i, at most max of them, into *v */
static BOOL read_number(NSString *s, NSUInteger *i, int max, long *v)
{
    NSUInteger n = [s length], start = *i;
    BOOL negative = NO;
    if (max > 4 && *i < n && ([s characterAtIndex:*i] == '-' || [s characterAtIndex:*i] == '+'))
        negative = [s characterAtIndex:(*i)++] == '-';
    long x = 0;
    int count = 0;
    while (*i < n && count < max && [s characterAtIndex:*i] >= '0' && [s characterAtIndex:*i] <= '9')
        x = x * 10 + ([s characterAtIndex:(*i)++] - '0'), count++;
    if (!count) {
        *i = start;
        return NO;
    }
    *v = negative ? -x : x;
    return YES;
}

/* one of the names (or its first three letters) at *i: its index */
static long read_name(NSString *s, NSUInteger *i, NSString *const *names, int count)
{
    NSString *rest = [s substringFromIndex:*i];
    for (int full = 1; full >= 0; full--)
        for (int k = 0; k < count; k++) {
            NSString *name = full ? names[k] : [names[k] substringToIndex:3];
            if ([rest length] >= [name length] &&
                [[rest substringToIndex:[name length]] caseInsensitiveCompare:name] == NSOrderedSame) {
                *i += [name length];
                return k;
            }
        }
    return -1;
}

- (instancetype)initWithString:(NSString *)description calendarFormat:(NSString *)format locale:(id)locale
{
    if (!description) {
        [self release];
        return nil;
    }
    NSString *fmt = format ?: @"%Y-%m-%d %H:%M:%S %z";
    long year = 2001, month = 1, day = 1, hour = 0, minute = 0, second = 0, ms = 0, yearday = -1;
    BOOL pm = NO, has_pm = NO, twelve = NO;
    NSTimeZone *zone = nil;
    NSUInteger i = 0, n = [description length], fn = [fmt length];
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    BOOL ok = YES;
    for (NSUInteger k = 0; ok && k < fn; k++) {
        unichar c = [fmt characterAtIndex:k];
        if ([space characterIsMember:c]) {
            while (i < n && [space characterIsMember:[description characterAtIndex:i]])
                i++;
            continue;
        }
        if (c != '%' || k + 1 >= fn) {
            ok = i < n && [description characterAtIndex:i] == c;
            i++;
            continue;
        }
        unichar s = [fmt characterAtIndex:++k];
        long v = 0;
        switch (s) {
        case '%': ok = i < n && [description characterAtIndex:i++] == '%'; break;
        case 'Y': ok = read_number(description, &i, 6, &year); break;
        case 'y':
            ok = read_number(description, &i, 2, &v);
            year = v < 70 ? 2000 + v : 1900 + v;   /* as the documentation's two-digit years */
            break;
        case 'm': ok = read_number(description, &i, 2, &month); break;
        case 'd': case 'e': ok = read_number(description, &i, 2, &day); break;
        case 'j': ok = read_number(description, &i, 3, &yearday); break;
        case 'H': ok = read_number(description, &i, 2, &hour); break;
        case 'I': ok = read_number(description, &i, 2, &hour), twelve = YES; break;
        case 'M': ok = read_number(description, &i, 2, &minute); break;
        case 'S': ok = read_number(description, &i, 2, &second); break;
        case 'F': ok = read_number(description, &i, 3, &ms); break;
        case 'w': ok = read_number(description, &i, 1, &v); break;
        case 'B': case 'b':
            v = read_name(description, &i, month_names, 12);
            ok = v >= 0, month = v + 1;
            break;
        case 'A': case 'a': ok = read_name(description, &i, day_names, 7) >= 0; break;
        case 'p': {
            NSString *rest = [[description substringFromIndex:i] uppercaseString];
            ok = [rest hasPrefix:@"AM"] || [rest hasPrefix:@"PM"];
            pm = [rest hasPrefix:@"PM"], has_pm = YES, i += 2;
            break;
        }
        case 'z': {
            unichar sign = i < n ? [description characterAtIndex:i] : 0;
            ok = sign == '+' || sign == '-';
            i++;
            long hhmm = 0;
            NSUInteger at = i;
            ok = ok && read_number(description, &i, 4, &hhmm) && i - at == 4;
            long secs = (hhmm / 100) * 3600 + (hhmm % 100) * 60;
            zone = [NSTimeZone timeZoneForSecondsFromGMT:sign == '-' ? -secs : secs];
            break;
        }
        case 'Z': {
            NSUInteger start = i;
            while (i < n && ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:[description characterAtIndex:i]] ||
                             [description characterAtIndex:i] == '/' || [description characterAtIndex:i] == '_' ||
                             [description characterAtIndex:i] == '+' || [description characterAtIndex:i] == '-'))
                i++;
            NSString *name = [description substringWithRange:NSMakeRange(start, i - start)];
            zone = [NSTimeZone timeZoneWithAbbreviation:name] ?: [NSTimeZone timeZoneWithName:name];
            ok = zone != nil;
            break;
        }
        default: ok = NO; break;
        }
    }
    if (twelve || has_pm) {
        if (hour == 12)
            hour = 0;
        if (pm)
            hour += 12;
    }
    if (yearday > 0) {
        long y, m, d;
        civil_from_days(days_from_civil(year, 1, 1) + yearday - 1, &y, &m, &d);
        month = m, day = d;
    }
    if (!ok || month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
        [self release];
        return nil;
    }
    NSTimeZone *z = zone ?: [NSTimeZone defaultTimeZone];
    if ((self = [self initWithTimeIntervalSinceReferenceDate:from_local(year, month, day, hour, minute,
                                                                         second + ms / 1000.0, z)])) {
        [self setTimeZone:zone];
        [self setCalendarFormat:format];
    }
    return self;
}
@end

@implementation NSDate (NSCalendarDateExtras)
- (NSCalendarDate *)dateWithCalendarFormat:(NSString *)format timeZone:(NSTimeZone *)aTimeZone
{
    NSCalendarDate *c = [[[NSCalendarDate alloc]
        initWithTimeIntervalSinceReferenceDate:[self timeIntervalSinceReferenceDate]] autorelease];
    [c setCalendarFormat:format];
    [c setTimeZone:aTimeZone];
    return c;
}
- (NSString *)descriptionWithCalendarFormat:(NSString *)format timeZone:(NSTimeZone *)aTimeZone locale:(id)locale
{
    return [[self dateWithCalendarFormat:nil timeZone:aTimeZone] descriptionWithCalendarFormat:format locale:locale];
}
@end

/* ---- the scripting execution context ------------------------------------------------------ */

@implementation NSScriptExecutionContext {
    id _top, _tested, _range;
}
+ (NSScriptExecutionContext *)sharedScriptExecutionContext
{
    static NSScriptExecutionContext *shared;
    @synchronized(self) {
        if (!shared)
            shared = [[NSScriptExecutionContext alloc] init];
    }
    return shared;
}
- (id)topLevelObject { return _top; }
- (void)setTopLevelObject:(id)o
{
    [o retain];
    [_top release];
    _top = o;
}
- (id)objectBeingTested { return _tested; }
- (void)setObjectBeingTested:(id)o
{
    [o retain];
    [_tested release];
    _tested = o;
}
- (id)rangeContainerObject { return _range; }
- (void)setRangeContainerObject:(id)o
{
    [o retain];
    [_range release];
    _range = o;
}
@end

/* ---- connections ---------------------------------------------------------------------- */

NSString *const NSConnectionReplyMode = @"NSConnectionReplyMode";
NSNotificationName const NSConnectionDidDieNotification = @"NSConnectionDidDieNotification";
NSNotificationName const NSConnectionDidInitializeNotification = @"NSConnectionDidInitializeNotification";

@implementation NSConnection {
    id _root, _delegate;
    NSConnection *_peer;   /* for a connection to a registered name, the one registered */
    NSMutableArray *_modes, *_names;
    NSTimeInterval _requestTimeout, _replyTimeout;
    BOOL _invalid, _independent, _threads;
}

static NSMutableDictionary *registered(void)
{
    static NSMutableDictionary *names;
    if (!names)
        names = [[NSMutableDictionary alloc] init];
    return names;
}

static NSMutableArray *live(void)
{
    static NSMutableArray *all;
    if (!all)
        all = [[NSMutableArray alloc] init];
    return all;
}

+ (instancetype)defaultConnection
{
    static NSConnection *main;
    @synchronized(self) {
        if (!main)
            main = [[NSConnection alloc] init];
    }
    return main;
}

+ (NSArray *)allConnections
{
    @synchronized(self) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSValue *v in live())
            [a addObject:[v nonretainedObjectValue]];
        return a;
    }
}

- (instancetype)init
{
    if ((self = [super init])) {
        _modes = [[NSMutableArray alloc] initWithObjects:NSDefaultRunLoopMode, nil];
        _names = [[NSMutableArray alloc] init];
        _requestTimeout = _replyTimeout = 1e10;
        @synchronized([NSConnection class]) {
            [live() addObject:[NSValue valueWithNonretainedObject:self]];
        }
    }
    return self;
}

- (instancetype)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort { return [self init]; }

+ (instancetype)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
{
    if ([hostName length] && ![hostName isEqualToString:@"localhost"] && ![hostName isEqualToString:@"*"])
        return nil;
    NSConnection *peer;
    @synchronized(self) {
        peer = name ? [[registered() objectForKey:name] retain] : nil;
    }
    if (!peer)
        return nil;
    NSConnection *c = [[[NSConnection alloc] init] autorelease];
    c->_peer = peer;
    return c;
}

+ (instancetype)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
                            usingNameServer:(NSPortNameServer *)server
{
    return [self connectionWithRegisteredName:name host:hostName];
}

+ (id)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
{
    return [[self connectionWithRegisteredName:name host:hostName] rootProxy];
}

+ (id)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
                              usingNameServer:(NSPortNameServer *)server
{
    return [self rootProxyForConnectionWithRegisteredName:name host:hostName];
}

+ (instancetype)serviceConnectionWithName:(NSString *)name rootObject:(id)root
{
    NSConnection *c = [[[NSConnection alloc] init] autorelease];
    [c setRootObject:root];
    return [c registerName:name] ? c : nil;
}

+ (id)currentConversation { return nil; }

- (void)dealloc
{
    [self invalidate];
    @synchronized([NSConnection class]) {
        NSUInteger i = 0;
        for (NSValue *v in live()) {
            if ([v nonretainedObjectValue] == self)
                break;
            i++;
        }
        if (i < [live() count])
            [live() removeObjectAtIndex:i];
    }
    [_root release];
    [_peer release];
    [_modes release];
    [_names release];
    [super dealloc];
}

- (id)rootObject { return _root; }
- (void)setRootObject:(id)root
{
    [root retain];
    [_root release];
    _root = root;
}
- (id)rootProxy { return _peer && ![_peer isValid] ? nil : [_peer rootObject]; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSTimeInterval)requestTimeout { return _requestTimeout; }
- (void)setRequestTimeout:(NSTimeInterval)t { _requestTimeout = t; }
- (NSTimeInterval)replyTimeout { return _replyTimeout; }
- (void)setReplyTimeout:(NSTimeInterval)t { _replyTimeout = t; }
- (BOOL)independentConversationQueueing { return _independent; }
- (void)setIndependentConversationQueueing:(BOOL)flag { _independent = flag; }
- (BOOL)isValid { return !_invalid; }
- (NSArray *)requestModes { return [[_modes copy] autorelease]; }
- (NSArray *)remoteObjects { return [self rootProxy] ? @[ [self rootProxy] ] : @[]; }
- (NSArray *)localObjects { return _root ? @[ _root ] : @[]; }
- (NSPort *)receivePort { return nil; }
- (NSPort *)sendPort { return nil; }

/* NO when the name is another connection's. */
- (BOOL)registerName:(NSString *)name
{
    if (_invalid)
        return NO;
    @synchronized([NSConnection class]) {
        if (!name) {
            for (NSString *n in _names)
                [registered() removeObjectForKey:n];
            [_names removeAllObjects];
            return YES;
        }
        NSConnection *other = [registered() objectForKey:name];
        if (other && other != self)
            return NO;
        [registered() setObject:self forKey:name];
        if (![_names containsObject:name])
            [_names addObject:name];
    }
    return YES;
}

- (BOOL)registerName:(NSString *)name withNameServer:(NSPortNameServer *)server { return [self registerName:name]; }
- (void)addRequestMode:(NSString *)mode
{
    if (mode && ![_modes containsObject:mode])
        [_modes addObject:mode];
}
- (void)removeRequestMode:(NSString *)mode { [_modes removeObject:mode]; }
/* Messages to the root object are sent directly, on the sender's thread. */
- (void)addRunLoop:(NSRunLoop *)runloop {}
- (void)removeRunLoop:(NSRunLoop *)runloop {}
- (void)runInNewThread {}
- (void)enableMultipleThreads { _threads = YES; }
- (BOOL)multipleThreadsEnabled { return _threads; }

- (void)invalidate
{
    if (_invalid)
        return;
    _invalid = YES;
    @synchronized([NSConnection class]) {
        for (NSString *n in _names)
            if ([registered() objectForKey:n] == self)
                [registered() removeObjectForKey:n];
        [_names removeAllObjects];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NSConnectionDidDieNotification object:self];
}

- (NSDictionary *)statistics { return @{}; }
@end
