/* SPDX-License-Identifier: GPL-3.0-or-later
 * EventKit on freemac's own calendar and reminders (sdk/include/EventKit/
 * EventKit.h), written for freemac from Apple's public EventKit
 * documentation (freemac 1.232, Ferry 0.56.0).
 *
 * The store:
 * - Events are the ones Tide keeps in ~/.local/share/freemac/calendar.ics.
 *   Those with no X-FREEMAC-SOURCE line are the "Calendar" calendar of the
 *   "On My Mac" source; those an online account brought (X-FREEMAC-SOURCE:
 *   <account> <collection>) are a calendar of that account's source.
 * - Reminders are Nudge's lists, one iCalendar file of to-dos each in
 *   ~/.local/share/freemac/reminders/, with the list's name and colour in
 *   the file's own lines. With no list there, a "Reminders" list is shown,
 *   written only once something is saved in it, as Nudge does.
 * The files are read again whenever they have changed, and a save reads
 * the file again, changes only the items saved and keeps every line it
 * doesn't use, so Tide's and Nudge's own lines survive. Repeating events
 * are expanded from their RRULE (daily, weekly, monthly and yearly, with
 * BYDAY, BYMONTHDAY, BYMONTH, BYSETPOS, COUNT and UNTIL), less their
 * EXDATEs; a changed date of a series is a component of its own with a
 * RECURRENCE-ID. EKEventStoreChangedNotification is posted after a save
 * and when the files change on disk (looked at every two seconds).
 *
 * Access: as on a Mac, an app asks first. The answer is asked once, with
 * an alert in the app, and kept per app in ~/.config/freemac/
 * calendar-access.json ({"apps": {id: {"name", "events", "reminders"}}}).
 * With no display to ask on, the request is answered NO and nothing is
 * kept. Until access is given the store shows no calendars and saves fail
 * with EKErrorEventStoreNotAuthorized.
 *
 * Not here: birthdays, subscribed calendars, locations with coordinates,
 * invitations (attendees are read, never sent) and new event calendars
 * (Tide has one). */
#import <EventKit/EventKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>

#if !__has_feature(objc_arc)
#error EventKit.m is built with ARC
#endif

NSString *const EKErrorDomain = @"EKErrorDomain";
NSString *const EKEventStoreChangedNotification = @"EKEventStoreChangedNotification";

/* What EventKit calls in AppKit, looked up when used: EventKit doesn't link it. */
@protocol FKColorClass
+ (id)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (id)colorWithCGColor:(CGColorRef)c;
@end
@protocol FKColor
- (id)colorUsingColorSpaceName:(NSString *)name;
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (CGColorRef)CGColor;
@end
@protocol FKAlert
- (void)setMessageText:(NSString *)t;
- (void)setInformativeText:(NSString *)t;
- (id)addButtonWithTitle:(NSString *)t;
- (NSInteger)runModal;
@end
@protocol FKApp
+ (id)sharedApplication;
- (void)activateIgnoringOtherApps:(BOOL)flag;
@end

static NSError *fk_error(EKErrorCode code, NSString *text)
{
    return [NSError errorWithDomain:EKErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : text}];
}

static BOOL fk_fail(NSError **error, EKErrorCode code, NSString *text)
{
    if (error)
        *error = fk_error(code, text);
    return NO;
}

static BOOL fk_same(id a, id b) { return a == b || [a isEqual:b]; }

/* ---- where things are kept --------------------------------------------------------------- */

static NSString *fk_data_home(void)
{
    const char *x = getenv("XDG_DATA_HOME");
    return x && *x ? @(x) : [NSHomeDirectory() stringByAppendingPathComponent:@".local/share"];
}
static NSString *fk_config_home(void)
{
    const char *x = getenv("XDG_CONFIG_HOME");
    return x && *x ? @(x) : [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
}
static NSString *fk_events_path(void) { return [fk_data_home() stringByAppendingPathComponent:@"freemac/calendar.ics"]; }
static NSString *fk_reminders_dir(void) { return [fk_data_home() stringByAppendingPathComponent:@"freemac/reminders"]; }
static NSString *fk_access_path(void)
{
    return [fk_config_home() stringByAppendingPathComponent:@"freemac/calendar-access.json"];
}
static NSString *fk_accounts_path(void) { return [fk_config_home() stringByAppendingPathComponent:@"freemac/accounts.json"]; }

/* ---- iCalendar: lines, properties and components ------------------------------------------ */

@interface FKProp : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *params;    /* @[key, value] pairs, keys upper case */
@property (nonatomic, copy) NSString *value;    /* as written, escapes and all */
@end
@implementation FKProp
- (id)copyWithZone:(NSZone *)zone
{
    FKProp *p = [FKProp new];
    p.name = _name;
    p.params = _params;
    p.value = _value;
    return p;
}
- (NSString *)param:(NSString *)key
{
    for (NSArray *kv in _params)
        if ([kv[0] isEqualToString:key]) {
            NSString *v = kv[1];
            if (v.length >= 2 && [v hasPrefix:@"\""] && [v hasSuffix:@"\""])
                v = [v substringWithRange:NSMakeRange(1, v.length - 2)];
            return v;
        }
    return nil;
}
- (NSString *)line
{
    NSMutableString *s = [NSMutableString stringWithString:_name];
    for (NSArray *kv in _params)
        [s appendFormat:@";%@=%@", kv[0], kv[1]];
    [s appendString:@":"];
    [s appendString:_value ?: @""];
    return s;
}
@end

static NSString *fk_unescape(NSString *v)
{
    if ([v rangeOfString:@"\\"].location == NSNotFound)
        return v;
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < v.length; i++) {
        unichar c = [v characterAtIndex:i];
        if (c == '\\' && i + 1 < v.length) {
            unichar n = [v characterAtIndex:++i];
            [out appendString:(n == 'n' || n == 'N') ? @"\n" : [NSString stringWithCharacters:&n length:1]];
        } else
            [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return out;
}

static NSString *fk_escape(NSString *v)
{
    NSMutableString *s = [v mutableCopy];
    [s replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@";" withString:@"\\;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"," withString:@"\\," options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\r\n" withString:@"\\n" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

@interface FKComp : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<FKProp *> *props;
@property (nonatomic, strong) NSMutableArray<FKComp *> *subs;
@end
@implementation FKComp
- (instancetype)initWithName:(NSString *)name
{
    if ((self = [super init])) {
        _name = [name copy];
        _props = [NSMutableArray array];
        _subs = [NSMutableArray array];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    FKComp *c = [[FKComp alloc] initWithName:_name];
    for (FKProp *p in _props)
        [c.props addObject:[p copy]];
    for (FKComp *s in _subs)
        [c.subs addObject:[s copy]];
    return c;
}
- (FKProp *)prop:(NSString *)name
{
    for (FKProp *p in _props)
        if ([p.name isEqualToString:name])
            return p;
    return nil;
}
- (NSArray<FKProp *> *)allProps:(NSString *)name
{
    NSMutableArray *a = [NSMutableArray array];
    for (FKProp *p in _props)
        if ([p.name isEqualToString:name])
            [a addObject:p];
    return a;
}
- (NSString *)text:(NSString *)name
{
    FKProp *p = [self prop:name];
    return p ? fk_unescape(p.value) : nil;
}
- (void)removeProps:(NSSet *)names
{
    NSIndexSet *gone = [_props indexesOfObjectsPassingTest:^BOOL(FKProp *p, NSUInteger i, BOOL *stop) {
        return [names containsObject:p.name];
    }];
    [_props removeObjectsAtIndexes:gone];
}
- (void)add:(NSString *)name params:(NSArray *)params value:(NSString *)value
{
    FKProp *p = [FKProp new];
    p.name = name;
    p.params = params ?: @[];
    p.value = value;
    [_props addObject:p];
}
- (void)addText:(NSString *)name value:(NSString *)value
{
    if (value.length)
        [self add:name params:nil value:fk_escape(value)];
}
- (void)write:(NSMutableArray *)lines
{
    [lines addObject:[@"BEGIN:" stringByAppendingString:_name]];
    for (FKProp *p in _props)
        [lines addObject:[p line]];
    for (FKComp *s in _subs)
        [s write:lines];
    [lines addObject:[@"END:" stringByAppendingString:_name]];
}
@end

/* A content line split at the first colon outside quotes. */
static FKProp *fk_parse_line(NSString *line)
{
    NSUInteger n = line.length, i = 0;
    BOOL quoted = NO;
    for (; i < n; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == '"')
            quoted = !quoted;
        else if (c == ':' && !quoted)
            break;
    }
    if (i >= n)
        return nil;
    NSString *head = [line substringToIndex:i];
    FKProp *p = [FKProp new];
    p.value = [line substringFromIndex:i + 1];
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger start = 0;
    quoted = NO;
    for (NSUInteger j = 0; j <= head.length; j++) {
        unichar c = j < head.length ? [head characterAtIndex:j] : ';';
        if (c == '"')
            quoted = !quoted;
        else if (c == ';' && !quoted) {
            [parts addObject:[head substringWithRange:NSMakeRange(start, j - start)]];
            start = j + 1;
        }
    }
    p.name = [parts[0] uppercaseString];
    NSMutableArray *params = [NSMutableArray array];
    for (NSUInteger k = 1; k < parts.count; k++) {
        NSRange eq = [parts[k] rangeOfString:@"="];
        if (eq.location == NSNotFound)
            continue;
        [params addObject:@[[[parts[k] substringToIndex:eq.location] uppercaseString], [parts[k] substringFromIndex:eq.location + 1]]];
    }
    p.params = params;
    return p;
}

/* The VCALENDAR in a file's text (nil when it holds none). */
static FKComp *fk_parse(NSString *text)
{
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if (!raw.length)
            continue;
        unichar c = [raw characterAtIndex:0];
        if ((c == ' ' || c == '\t') && lines.count)
            lines[lines.count - 1] = [lines.lastObject stringByAppendingString:[raw substringFromIndex:1]];
        else
            [lines addObject:raw];
    }
    NSMutableArray *stack = [NSMutableArray array];
    FKComp *root = nil;
    for (NSString *l in lines) {
        FKProp *p = fk_parse_line(l);
        if (!p)
            continue;
        if ([p.name isEqualToString:@"BEGIN"]) {
            FKComp *c = [[FKComp alloc] initWithName:[p.value uppercaseString]];
            if (stack.count)
                [[stack.lastObject subs] addObject:c];
            else if (!root)
                root = c;
            [stack addObject:c];
        } else if ([p.name isEqualToString:@"END"]) {
            if (stack.count)
                [stack removeLastObject];
        } else if (stack.count)
            [[stack.lastObject props] addObject:p];
    }
    return [root.name isEqualToString:@"VCALENDAR"] ? root : nil;
}

static NSString *fk_dump(FKComp *cal)
{
    NSMutableArray *lines = [NSMutableArray array];
    [cal write:lines];
    NSMutableString *out = [NSMutableString string];
    for (NSString *line in lines) {
        /* folded at 75 octets, never inside a character */
        NSString *rest = line;
        BOOL first = YES;
        while ([rest lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > (first ? 75 : 74)) {
            NSUInteger cut = first ? 75 : 74;
            while (cut > 1 && [[rest substringToIndex:cut] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > (first ? 75 : 74))
                cut--;
            NSRange r = [rest rangeOfComposedCharacterSequenceAtIndex:cut];
            if (r.location < cut && r.location > 0)
                cut = r.location;
            [out appendString:first ? @"" : @" "];
            [out appendString:[rest substringToIndex:cut]];
            [out appendString:@"\r\n"];
            rest = [rest substringFromIndex:cut];
            first = NO;
        }
        [out appendString:first ? @"" : @" "];
        [out appendString:rest];
        [out appendString:@"\r\n"];
    }
    return out;
}

static FKComp *fk_read(NSString *path)
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d)
        return nil;
    NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]
                      ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    return fk_parse(t);
}

static BOOL fk_write(NSString *path, FKComp *cal, NSError **error)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *temp = [path stringByAppendingString:@".new"];
    NSData *data = [fk_dump(cal) dataUsingEncoding:NSUTF8StringEncoding];
    if (![data writeToFile:temp atomically:NO] || rename(temp.fileSystemRepresentation, path.fileSystemRepresentation) != 0)
        return fk_fail(error, EKErrorInternalFailure, [@"Couldn't write " stringByAppendingString:path]);
    return YES;
}

static FKComp *fk_new_calendar(NSString *product)
{
    FKComp *c = [[FKComp alloc] initWithName:@"VCALENDAR"];
    [c add:@"VERSION" params:nil value:@"2.0"];
    [c add:@"PRODID" params:nil value:product];
    return c;
}

/* ---- dates and times --------------------------------------------------------------------- */

static NSCalendar *fk_calendar(NSTimeZone *zone)
{
    NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    c.timeZone = zone ?: [NSTimeZone localTimeZone];
    return c;
}

static BOOL fk_is_utc(NSTimeZone *z)
{
    return z && z.secondsFromGMT == 0 && ([z.name isEqualToString:@"GMT"] || [z.name isEqualToString:@"UTC"] ||
                                          [z.name isEqualToString:@"Etc/UTC"] || [z.name isEqualToString:@"Etc/GMT"]);
}

static BOOL fk_is_local(NSTimeZone *z) { return !z || [z.name isEqualToString:[NSTimeZone localTimeZone].name]; }

/* One iCalendar DATE or DATE-TIME. *zone is nil for a floating time or a date. */
static NSDate *fk_date_value(NSString *v, NSString *tzid, BOOL *allDay, NSTimeZone **zone)
{
    v = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    const char *s = v.UTF8String;
    int Y, M, D, h = 0, m = 0, sec = 0;
    BOOL dateOnly = strlen(s) == 8;
    if (sscanf(s, "%4d%2d%2d", &Y, &M, &D) != 3)
        return nil;
    if (!dateOnly && sscanf(s + 8, "T%2d%2d%2d", &h, &m, &sec) < 2)
        return nil;
    NSTimeZone *z = nil;
    if (!dateOnly && v.length && [v characterAtIndex:v.length - 1] == 'Z')
        z = [NSTimeZone timeZoneWithName:@"UTC"] ?: [NSTimeZone timeZoneForSecondsFromGMT:0];
    else if (!dateOnly && tzid.length)
        z = [NSTimeZone timeZoneWithName:tzid];
    NSDateComponents *dc = [NSDateComponents new];
    dc.year = Y;
    dc.month = M;
    dc.day = D;
    dc.hour = h;
    dc.minute = m;
    dc.second = sec;
    if (allDay)
        *allDay = dateOnly;
    if (zone)
        *zone = z;
    return [fk_calendar(z) dateFromComponents:dc];
}

static NSDate *fk_prop_date(FKProp *p, BOOL *allDay, NSTimeZone **zone)
{
    if (!p)
        return nil;
    NSString *v = p.value;
    NSRange comma = [v rangeOfString:@","];
    if (comma.location != NSNotFound)
        v = [v substringToIndex:comma.location];
    BOOL day = NO;
    NSDate *d = fk_date_value(v, [p param:@"TZID"], &day, zone);
    if (allDay)
        *allDay = day || [[p param:@"VALUE"] isEqualToString:@"DATE"];
    return d;
}

/* The value and parameters to write a date with. */
static NSString *fk_format_date(NSDate *date, BOOL allDay, NSTimeZone *zone, NSArray **params)
{
    if (allDay) {
        NSDateComponents *c = [fk_calendar(nil) components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                  fromDate:date];
        *params = @[@[@"VALUE", @"DATE"]];
        return [NSString stringWithFormat:@"%04ld%02ld%02ld", (long)c.year, (long)c.month, (long)c.day];
    }
    BOOL utc = fk_is_utc(zone);
    NSTimeZone *z = utc ? zone : fk_is_local(zone) ? nil : zone;
    NSDateComponents *c = [fk_calendar(z) components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                                     NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
                                            fromDate:date];
    *params = (z && !utc) ? @[@[@"TZID", z.name]] : @[];
    return [NSString stringWithFormat:@"%04ld%02ld%02ldT%02ld%02ld%02ld%@", (long)c.year, (long)c.month, (long)c.day,
                                      (long)c.hour, (long)c.minute, (long)c.second, utc ? @"Z" : @""];
}

static NSString *fk_utc_stamp(NSDate *d)
{
    NSArray *p;
    return fk_format_date(d ?: [NSDate date], NO, [NSTimeZone timeZoneForSecondsFromGMT:0], &p);
}

/* An iCalendar DURATION (-PT15M, P1D, P1W) in seconds. */
static NSTimeInterval fk_duration(NSString *t)
{
    double sign = 1, total = 0, n = 0;
    BOOL have = NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c == '-')
            sign = -1;
        else if (c >= '0' && c <= '9') {
            n = n * 10 + (c - '0');
            have = YES;
        } else if (have) {
            double unit = c == 'W' ? 604800 : c == 'D' ? 86400 : c == 'H' ? 3600 : c == 'M' ? 60 : c == 'S' ? 1 : 0;
            total += n * unit;
            n = 0;
            have = NO;
        }
    }
    return sign * total;
}

static NSString *fk_format_duration(NSTimeInterval s)
{
    NSString *sign = s < 0 ? @"-" : @"";
    long v = (long)fabs(s);
    if (v == 0)
        return @"PT0S";
    if (v % 86400 == 0)
        return [NSString stringWithFormat:@"%@P%ldD", sign, v / 86400];
    if (v % 60 == 0)
        return [NSString stringWithFormat:@"%@PT%ldM", sign, v / 60];
    return [NSString stringWithFormat:@"%@PT%ldS", sign, v];
}

/* ---- colours ----------------------------------------------------------------------------- */

static NSDictionary *fk_color_names(void)
{
    /* Nudge's list colours (freemac_shell/reminders_store.py) */
    return @{@"blue" : @"#2f7bf5", @"red" : @"#f04d3e", @"orange" : @"#f59a23", @"yellow" : @"#f2c418",
             @"green" : @"#34b85a", @"purple" : @"#a35ee6", @"brown" : @"#a2845e", @"grey" : @"#8e8e93"};
}

static BOOL fk_hex(NSString *hex, CGFloat rgb[3])
{
    unsigned v = 0;
    if (hex.length < 7 || [hex characterAtIndex:0] != '#' || sscanf(hex.UTF8String + 1, "%6x", &v) != 1)
        return NO;
    rgb[0] = ((v >> 16) & 255) / 255.0;
    rgb[1] = ((v >> 8) & 255) / 255.0;
    rgb[2] = (v & 255) / 255.0;
    return YES;
}

/* The name of the list colour nearest a colour, for Nudge's files. */
static NSString *fk_nearest_name(NSString *hex)
{
    CGFloat want[3];
    if (!fk_hex(hex, want))
        return @"blue";
    NSString *best = @"blue";
    CGFloat bestd = 1e9;
    NSDictionary *names = fk_color_names();
    for (NSString *name in [names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        CGFloat c[3];
        fk_hex(names[name], c);
        CGFloat d = (c[0] - want[0]) * (c[0] - want[0]) + (c[1] - want[1]) * (c[1] - want[1]) + (c[2] - want[2]) * (c[2] - want[2]);
        if (d < bestd) {
            bestd = d;
            best = name;
        }
    }
    return best;
}

/* ---- access ------------------------------------------------------------------------------ */

static NSString *fk_app_key(void)
{
    NSString *b = [[NSBundle mainBundle] bundleIdentifier];
    return b.length ? b : [[NSProcessInfo processInfo] processName];
}

static NSString *fk_app_name(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *n = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
    return n.length ? n : [[NSProcessInfo processInfo] processName];
}

static NSString *fk_kind_key(EKEntityType t) { return t == EKEntityTypeReminder ? @"reminders" : @"events"; }

static NSMutableDictionary *fk_access_all(void)
{
    NSData *d = [NSData dataWithContentsOfFile:fk_access_path()];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:NULL] : nil;
    if (![j isKindOfClass:[NSDictionary class]] || ![j[@"apps"] isKindOfClass:[NSDictionary class]])
        j = [@{@"apps" : [NSMutableDictionary dictionary]} mutableCopy];
    return j;
}

static int fk_answer(EKEntityType t)
{
    id entry = fk_access_all()[@"apps"][fk_app_key()];
    id v = [entry isKindOfClass:[NSDictionary class]] ? entry[fk_kind_key(t)] : nil;
    if (![v isKindOfClass:[NSNumber class]])
        return -1;
    return [v boolValue] ? 1 : 0;
}

static void fk_keep_answer(EKEntityType t, BOOL allowed)
{
    NSMutableDictionary *all = fk_access_all();
    NSMutableDictionary *apps = all[@"apps"];
    NSMutableDictionary *entry = [apps[fk_app_key()] isKindOfClass:[NSDictionary class]] ? [apps[fk_app_key()] mutableCopy]
                                                                                         : [NSMutableDictionary dictionary];
    entry[@"name"] = fk_app_name();
    entry[fk_kind_key(t)] = @(allowed);
    apps[fk_app_key()] = entry;
    NSData *d = [NSJSONSerialization dataWithJSONObject:all options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *path = fk_access_path();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [d writeToFile:path atomically:YES];
}

static BOOL fk_allowed(EKEntityType t) { return fk_answer(t) == 1; }

/* Asks the user in the app, on the main thread; YES when they allow it. */
static BOOL fk_ask(EKEntityType t)
{
    const char *wl = getenv("WAYLAND_DISPLAY"), *x = getenv("DISPLAY");
    Class alertClass = objc_getClass("NSAlert");
    Class appClass = objc_getClass("NSApplication");
    if (!alertClass || !appClass || !((wl && *wl) || (x && *x)))
        return NO;
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    BOOL reminders = t == EKEntityTypeReminder;
    NSString *why = reminders ? (info[@"NSRemindersFullAccessUsageDescription"] ?: info[@"NSRemindersUsageDescription"])
                              : (info[@"NSCalendarsFullAccessUsageDescription"] ?: info[@"NSCalendarsUsageDescription"]);
    id<FKAlert> alert = [[alertClass alloc] init];
    [alert setMessageText:[NSString stringWithFormat:reminders ? @"“%@” would like full access to your reminders."
                                                               : @"“%@” would like full access to your calendars.",
                                                     fk_app_name()]];
    NSString *what = reminders ? @"It will be able to see, add, change and delete the reminders in freemac’s Reminders."
                               : @"It will be able to see, add, change and delete the events in freemac’s Calendar.";
    [alert setInformativeText:why.length ? [NSString stringWithFormat:@"%@\n\n%@", why, what] : what];
    [alert addButtonWithTitle:@"Allow Full Access"];
    [alert addButtonWithTitle:@"Don’t Allow"];
    [(id<FKApp>)[(id<FKApp>)appClass sharedApplication] activateIgnoringOtherApps:YES];
    return [alert runModal] == 1000;
}

/* ---- the files' state, to tell when they change -------------------------------------------- */

static NSString *fk_signature(void)
{
    NSMutableString *s = [NSMutableString string];
    struct stat st;
    if (stat(fk_events_path().fileSystemRepresentation, &st) == 0)
        [s appendFormat:@"e%lld.%ld:%lld;", (long long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec, (long long)st.st_size];
    NSString *dir = fk_reminders_dir();
    for (NSString *name in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
             sortedArrayUsingSelector:@selector(compare:)]) {
        if (![name hasSuffix:@".ics"])
            continue;
        if (stat([dir stringByAppendingPathComponent:name].fileSystemRepresentation, &st) == 0)
            [s appendFormat:@"%@%lld.%ld:%lld;", name, (long long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec,
                            (long long)st.st_size];
    }
    return s;
}

/* ---- the objects -------------------------------------------------------------------------- */

@interface EKEventStore ()
- (void)_ensureLoaded;
- (EKSource *)_sourceForMark:(NSString *)mark;
- (void)_changed;
@end

@implementation EKObject
- (BOOL)hasChanges { return NO; }
- (BOOL)isNew { return NO; }
- (void)reset { [self rollback]; }
- (void)rollback {}
- (BOOL)refresh { return YES; }
@end

@implementation EKSource {
@public
    NSString *_identifier, *_title;
    EKSourceType _type;
    __weak EKEventStore *_store;
}
- (NSString *)sourceIdentifier { return _identifier; }
- (EKSourceType)sourceType { return _type; }
- (NSString *)title { return _title; }
- (BOOL)isDelegate { return NO; }
- (NSSet *)calendarsForEntityType:(EKEntityType)t
{
    NSMutableSet *s = [NSMutableSet set];
    for (EKCalendar *c in [_store calendarsForEntityType:t])
        if (c.source == self)
            [s addObject:c];
    return s;
}
- (NSSet *)calendars
{
    NSMutableSet *s = [NSMutableSet setWithSet:[self calendarsForEntityType:EKEntityTypeEvent]];
    [s unionSet:[self calendarsForEntityType:EKEntityTypeReminder]];
    return s;
}
- (NSString *)description { return [NSString stringWithFormat:@"<EKSource %@ \"%@\">", _identifier, _title]; }
@end

@implementation EKCalendar {
@public
    NSString *_identifier;
    EKEntityMask _mask;
    EKCalendarType _ctype;
    NSString *_hex;          /* its colour, #rrggbb */
    NSString *_mark;         /* X-FREEMAC-SOURCE, for an account's calendar */
    NSString *_file;         /* a reminder list's file */
    NSInteger _order;
    BOOL _new;
    __weak EKEventStore *_store;
}
+ (EKCalendar *)calendarWithEventStore:(EKEventStore *)store { return [self calendarForEntityType:EKEntityTypeEvent eventStore:store]; }
+ (EKCalendar *)calendarForEntityType:(EKEntityType)t eventStore:(EKEventStore *)store
{
    EKCalendar *c = [EKCalendar new];
    c->_identifier = [[NSUUID UUID] UUIDString];
    c->_mask = t == EKEntityTypeReminder ? EKEntityMaskReminder : EKEntityMaskEvent;
    c->_ctype = EKCalendarTypeLocal;
    c->_hex = @"#2f7bf5";
    c->_new = YES;
    c->_store = store;
    c.title = @"";
    return c;
}
- (BOOL)isNew { return _new; }
- (NSString *)calendarIdentifier { return _identifier; }
- (EKCalendarType)type { return _ctype; }
- (BOOL)allowsContentModifications { return YES; }
- (BOOL)isSubscribed { return NO; }
- (BOOL)isImmutable { return NO; }
- (EKEntityMask)allowedEntityTypes { return _mask; }
- (EKCalendarEventAvailabilityMask)supportedEventAvailabilities
{
    return _mask & EKEntityMaskEvent ? EKCalendarEventAvailabilityBusy | EKCalendarEventAvailabilityFree : EKCalendarEventAvailabilityNone;
}
- (NSColor *)color
{
    CGFloat rgb[3] = {0.18, 0.48, 0.96};
    fk_hex(_hex, rgb);
    Class c = objc_getClass("NSColor");
    return c ? [(id<FKColorClass>)c colorWithSRGBRed:rgb[0] green:rgb[1] blue:rgb[2] alpha:1] : nil;
}
- (void)setColor:(NSColor *)color
{
    id rgb = [(id<FKColor>)color colorUsingColorSpaceName:@"NSCalibratedRGBColorSpace"] ?: color;
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if ([rgb respondsToSelector:@selector(getRed:green:blue:alpha:)])
        [(id<FKColor>)rgb getRed:&r green:&g blue:&b alpha:&a];
    _hex = [NSString stringWithFormat:@"#%02x%02x%02x", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}
- (CGColorRef)CGColor
{
    CGFloat rgb[3] = {0.18, 0.48, 0.96};
    fk_hex(_hex, rgb);
    CGColorRef c = CGColorCreateSRGB(rgb[0], rgb[1], rgb[2], 1);
    CFAutorelease(c);
    return c;
}
- (void)setCGColor:(CGColorRef)c
{
    const CGFloat *v = c ? CGColorGetComponents(c) : NULL;
    if (v && CGColorGetNumberOfComponents(c) >= 3)
        _hex = [NSString stringWithFormat:@"#%02x%02x%02x", (int)lround(v[0] * 255), (int)lround(v[1] * 255), (int)lround(v[2] * 255)];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<EKCalendar %@ \"%@\" %@>", _identifier, self.title,
                                      _mask & EKEntityMaskReminder ? @"reminders" : @"events"];
}
@end

/* ---- recurrence ---------------------------------------------------------------------------- */

@implementation EKRecurrenceEnd {
    NSDate *_end;
    NSUInteger _count;
}
+ (instancetype)recurrenceEndWithEndDate:(NSDate *)endDate
{
    EKRecurrenceEnd *e = [self new];
    e->_end = [endDate copy];
    return e;
}
+ (instancetype)recurrenceEndWithOccurrenceCount:(NSUInteger)count
{
    EKRecurrenceEnd *e = [self new];
    e->_count = count;
    return e;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSDate *)endDate { return _end; }
- (NSUInteger)occurrenceCount { return _count; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[EKRecurrenceEnd class]] && fk_same(_end, [o endDate]) && _count == [o occurrenceCount];
}
- (NSUInteger)hash { return _count ^ (NSUInteger)_end.timeIntervalSinceReferenceDate; }
@end

@implementation EKRecurrenceDayOfWeek {
    EKWeekday _day;
    NSInteger _week;
}
+ (instancetype)dayOfWeek:(EKWeekday)day { return [[self alloc] initWithDayOfTheWeek:day weekNumber:0]; }
+ (instancetype)dayOfWeek:(EKWeekday)day weekNumber:(NSInteger)week { return [[self alloc] initWithDayOfTheWeek:day weekNumber:week]; }
- (instancetype)initWithDayOfTheWeek:(EKWeekday)day weekNumber:(NSInteger)week
{
    if ((self = [super init])) {
        _day = day;
        _week = week;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (EKWeekday)dayOfTheWeek { return _day; }
- (NSInteger)weekNumber { return _week; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[EKRecurrenceDayOfWeek class]] && [o dayOfTheWeek] == _day && [o weekNumber] == _week;
}
- (NSUInteger)hash { return (NSUInteger)(_day * 100 + _week); }
- (NSString *)description
{
    NSString *day = @[@"", @"SU", @"MO", @"TU", @"WE", @"TH", @"FR", @"SA"][_day];
    return _week ? [NSString stringWithFormat:@"%ld%@", (long)_week, day] : day;
}
@end

static NSArray *fk_days = nil;

@implementation EKRecurrenceRule {
    EKRecurrenceFrequency _freq;
    NSInteger _interval;
    EKWeekday _wkst;
    NSArray *_byDay, *_byMonthDay, *_byMonth, *_byWeekNo, *_byYearDay, *_bySetPos;
}
+ (void)initialize
{
    if (!fk_days)
        fk_days = @[@"", @"SU", @"MO", @"TU", @"WE", @"TH", @"FR", @"SA"];
}
- (instancetype)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type interval:(NSInteger)interval end:(EKRecurrenceEnd *)end
{
    return [self initRecurrenceWithFrequency:type interval:interval daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil
                              weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:end];
}
- (instancetype)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type interval:(NSInteger)interval
                              daysOfTheWeek:(NSArray *)days daysOfTheMonth:(NSArray *)monthDays
                            monthsOfTheYear:(NSArray *)months weeksOfTheYear:(NSArray *)weeks
                              daysOfTheYear:(NSArray *)yearDays setPositions:(NSArray *)positions end:(EKRecurrenceEnd *)end
{
    if ((self = [super init])) {
        _freq = type;
        _interval = interval > 0 ? interval : 1;
        _wkst = EKWeekdayMonday;
        _byDay = days.count ? [days copy] : nil;
        _byMonthDay = monthDays.count ? [monthDays copy] : nil;
        _byMonth = months.count ? [months copy] : nil;
        _byWeekNo = weeks.count ? [weeks copy] : nil;
        _byYearDay = yearDays.count ? [yearDays copy] : nil;
        _bySetPos = positions.count ? [positions copy] : nil;
        _recurrenceEnd = end;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    EKRecurrenceRule *r = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:_freq interval:_interval daysOfTheWeek:_byDay
                                                                daysOfTheMonth:_byMonthDay monthsOfTheYear:_byMonth
                                                                 weeksOfTheYear:_byWeekNo daysOfTheYear:_byYearDay
                                                                  setPositions:_bySetPos end:_recurrenceEnd];
    r->_wkst = _wkst;
    return r;
}
- (NSString *)calendarIdentifier { return NSCalendarIdentifierGregorian; }
- (EKRecurrenceFrequency)frequency { return _freq; }
- (NSInteger)interval { return _interval; }
- (EKWeekday)firstDayOfTheWeek { return _wkst; }
- (NSArray *)daysOfTheWeek { return _byDay; }
- (NSArray *)daysOfTheMonth { return _byMonthDay; }
- (NSArray *)daysOfTheYear { return _byYearDay; }
- (NSArray *)weeksOfTheYear { return _byWeekNo; }
- (NSArray *)monthsOfTheYear { return _byMonth; }
- (NSArray *)setPositions { return _bySetPos; }
- (BOOL)isEqual:(id)o
{
    if (![o isKindOfClass:[EKRecurrenceRule class]])
        return NO;
    EKRecurrenceRule *r = o;
    return _freq == r->_freq && _interval == r->_interval && fk_same(_byDay, r->_byDay) &&
           fk_same(_byMonthDay, r->_byMonthDay) && fk_same(_byMonth, r->_byMonth) && fk_same(_bySetPos, r->_bySetPos) &&
           fk_same(_recurrenceEnd, r->_recurrenceEnd);
}
- (NSUInteger)hash { return (NSUInteger)_freq * 31 + (NSUInteger)_interval; }

static NSArray *fk_numbers(NSString *list)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *s in [list componentsSeparatedByString:@","])
        if (s.length)
            [a addObject:@(s.integerValue)];
    return a;
}

+ (instancetype)_ruleFromValue:(NSString *)value
{
    [self class];
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    for (NSString *kv in [value componentsSeparatedByString:@";"]) {
        NSRange eq = [kv rangeOfString:@"="];
        if (eq.location != NSNotFound)
            parts[[[kv substringToIndex:eq.location] uppercaseString]] = [kv substringFromIndex:eq.location + 1];
    }
    NSDictionary *freqs = @{@"DAILY" : @(EKRecurrenceFrequencyDaily), @"WEEKLY" : @(EKRecurrenceFrequencyWeekly),
                            @"MONTHLY" : @(EKRecurrenceFrequencyMonthly), @"YEARLY" : @(EKRecurrenceFrequencyYearly)};
    NSNumber *f = freqs[[parts[@"FREQ"] uppercaseString]];
    if (!f)
        return nil;
    NSMutableArray *days = [NSMutableArray array];
    for (NSString *d0 in [parts[@"BYDAY"] componentsSeparatedByString:@","]) {
        NSString *d = [d0 uppercaseString];
        if (d.length < 2)
            continue;
        NSUInteger wd = [fk_days indexOfObject:[d substringFromIndex:d.length - 2]];
        if (wd == NSNotFound || wd == 0)
            continue;
        [days addObject:[EKRecurrenceDayOfWeek dayOfWeek:(EKWeekday)wd weekNumber:[d substringToIndex:d.length - 2].integerValue]];
    }
    EKRecurrenceEnd *end = nil;
    if (parts[@"COUNT"])
        end = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:(NSUInteger)[parts[@"COUNT"] integerValue]];
    else if (parts[@"UNTIL"]) {
        BOOL allDay = NO;
        NSDate *u = fk_date_value(parts[@"UNTIL"], nil, &allDay, NULL);
        if (u && allDay)
            u = [u dateByAddingTimeInterval:86399];    /* the whole of the last day */
        if (u)
            end = [EKRecurrenceEnd recurrenceEndWithEndDate:u];
    }
    EKRecurrenceRule *r = [[self alloc] initRecurrenceWithFrequency:(EKRecurrenceFrequency)f.integerValue
                                                           interval:[parts[@"INTERVAL"] integerValue]
                                                      daysOfTheWeek:days daysOfTheMonth:fk_numbers(parts[@"BYMONTHDAY"])
                                                    monthsOfTheYear:fk_numbers(parts[@"BYMONTH"])
                                                     weeksOfTheYear:fk_numbers(parts[@"BYWEEKNO"])
                                                      daysOfTheYear:fk_numbers(parts[@"BYYEARDAY"])
                                                       setPositions:fk_numbers(parts[@"BYSETPOS"]) end:end];
    if (parts[@"WKST"]) {
        NSUInteger w = [fk_days indexOfObject:[parts[@"WKST"] uppercaseString]];
        if (w != NSNotFound && w > 0)
            r->_wkst = (EKWeekday)w;
    }
    return r;
}

- (NSString *)_value
{
    NSMutableArray *p = [NSMutableArray arrayWithObject:[@"FREQ=" stringByAppendingString:@[@"DAILY", @"WEEKLY", @"MONTHLY", @"YEARLY"][_freq]]];
    if (_interval > 1)
        [p addObject:[NSString stringWithFormat:@"INTERVAL=%ld", (long)_interval]];
    if (_recurrenceEnd.occurrenceCount)
        [p addObject:[NSString stringWithFormat:@"COUNT=%lu", (unsigned long)_recurrenceEnd.occurrenceCount]];
    else if (_recurrenceEnd.endDate)
        [p addObject:[@"UNTIL=" stringByAppendingString:fk_utc_stamp(_recurrenceEnd.endDate)]];
    if (_byDay.count)
        [p addObject:[@"BYDAY=" stringByAppendingString:[[_byDay valueForKey:@"description"] componentsJoinedByString:@","]]];
    if (_byMonthDay.count)
        [p addObject:[@"BYMONTHDAY=" stringByAppendingString:[_byMonthDay componentsJoinedByString:@","]]];
    if (_byMonth.count)
        [p addObject:[@"BYMONTH=" stringByAppendingString:[_byMonth componentsJoinedByString:@","]]];
    if (_byWeekNo.count)
        [p addObject:[@"BYWEEKNO=" stringByAppendingString:[_byWeekNo componentsJoinedByString:@","]]];
    if (_byYearDay.count)
        [p addObject:[@"BYYEARDAY=" stringByAppendingString:[_byYearDay componentsJoinedByString:@","]]];
    if (_bySetPos.count)
        [p addObject:[@"BYSETPOS=" stringByAppendingString:[_bySetPos componentsJoinedByString:@","]]];
    if (_wkst != EKWeekdayMonday)
        [p addObject:[@"WKST=" stringByAppendingString:fk_days[_wkst]]];
    return [p componentsJoinedByString:@";"];
}
- (NSString *)description { return [@"EKRecurrenceRule RRULE " stringByAppendingString:[self _value]]; }

/* The days of one month that BYMONTHDAY and BYDAY pick, as day numbers. */
static NSArray *fk_month_days(NSCalendar *cal, NSInteger year, NSInteger month, NSArray *byMonthDay, NSArray *byDay,
                              NSInteger fallback)
{
    NSDateComponents *c = [NSDateComponents new];
    c.year = year;
    c.month = month;
    c.day = 1;
    c.hour = 12;
    NSDate *first = [cal dateFromComponents:c];
    NSInteger length = (NSInteger)[cal rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:first].length;
    NSInteger firstWeekday = [cal component:NSCalendarUnitWeekday fromDate:first];    /* 1 is Sunday */
    NSMutableOrderedSet *fromMonthDays = nil, *fromDays = nil;
    if (byMonthDay.count) {
        fromMonthDays = [NSMutableOrderedSet orderedSet];
        for (NSNumber *n in byMonthDay) {
            NSInteger d = n.integerValue < 0 ? length + 1 + n.integerValue : n.integerValue;
            if (d >= 1 && d <= length)
                [fromMonthDays addObject:@(d)];
        }
    }
    if (byDay.count) {
        fromDays = [NSMutableOrderedSet orderedSet];
        for (EKRecurrenceDayOfWeek *w in byDay) {
            NSInteger d1 = 1 + ((NSInteger)w.dayOfTheWeek - firstWeekday + 7) % 7;
            NSMutableArray *all = [NSMutableArray array];
            for (NSInteger d = d1; d <= length; d += 7)
                [all addObject:@(d)];
            if (w.weekNumber == 0 || byMonthDay.count)
                [fromDays addObjectsFromArray:all];
            else {
                NSInteger i = w.weekNumber > 0 ? w.weekNumber - 1 : (NSInteger)all.count + w.weekNumber;
                if (i >= 0 && i < (NSInteger)all.count)
                    [fromDays addObject:all[i]];
            }
        }
    }
    NSMutableOrderedSet *days;
    if (fromMonthDays && fromDays) {
        days = fromMonthDays;
        [days intersectOrderedSet:fromDays];
    } else
        days = fromMonthDays ?: fromDays;
    if (!days) {
        days = [NSMutableOrderedSet orderedSet];
        if (fallback <= length)
            [days addObject:@(fallback)];
    }
    return [days.array sortedArrayUsingSelector:@selector(compare:)];
}

/* The starts of the occurrences of a series that touch [from, to), with
 * their count from the first; at most a hundred thousand steps. */
- (NSArray<NSDate *> *)_startsFrom:(NSDate *)dtstart zone:(NSTimeZone *)zone length:(NSTimeInterval)length
                              from:(NSDate *)from to:(NSDate *)to
{
    NSCalendar *cal = fk_calendar(zone);
    cal.firstWeekday = (NSUInteger)_wkst;
    NSDateComponents *s = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour |
                                          NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitWeekday
                                 fromDate:dtstart];
    NSUInteger count = _recurrenceEnd.occurrenceCount;
    NSDate *until = _recurrenceEnd.endDate;
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger made = 0;
    NSInteger n0 = 0;
    if (!count && from) {
        /* skip the periods that end before the range */
        double unit = _freq == EKRecurrenceFrequencyDaily ? 86400 : _freq == EKRecurrenceFrequencyWeekly ? 604800
                      : _freq == EKRecurrenceFrequencyMonthly ? 86400 * 28.0 : 86400 * 365.0;
        double gap = [from timeIntervalSinceDate:dtstart] - length;
        n0 = MAX(0, (NSInteger)floor(gap / (unit * _interval)) - 2);
        if (_freq == EKRecurrenceFrequencyMonthly)
            n0 = MAX(0, (NSInteger)floor(gap / (86400 * 31.0 * _interval)) - 2);
        if (_freq == EKRecurrenceFrequencyYearly)
            n0 = MAX(0, (NSInteger)floor(gap / (86400 * 366.0 * _interval)) - 2);
    }
    /* the start of dtstart's week, for weekly rules */
    NSDate *weekStart = nil;
    [cal rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&weekStart interval:NULL forDate:dtstart];
    for (NSInteger n = n0; n < n0 + 100000; n++) {
        NSMutableArray *days = [NSMutableArray array];    /* NSDateComponents of the period's days */
        NSDate *periodStart = nil;
        NSDateComponents *step = [NSDateComponents new];
        if (_freq == EKRecurrenceFrequencyDaily) {
            NSDateComponents *d = [NSDateComponents new];
            d.year = s.year;
            d.month = s.month;
            d.day = s.day + n * _interval;
            d.hour = 12;
            NSDate *day = [cal dateFromComponents:d];
            periodStart = [cal startOfDayForDate:day];
            NSDateComponents *dc = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitWeekday fromDate:day];
            BOOL ok = YES;
            if (_byMonth.count && ![_byMonth containsObject:@(dc.month)])
                ok = NO;
            if (ok && _byMonthDay.count && ![fk_month_days(cal, dc.year, dc.month, _byMonthDay, nil, 0) containsObject:@(dc.day)])
                ok = NO;
            if (ok && _byDay.count && ![[_byDay valueForKey:@"dayOfTheWeek"] containsObject:@(dc.weekday)])
                ok = NO;
            if (ok)
                [days addObject:dc];
        } else if (_freq == EKRecurrenceFrequencyWeekly) {
            step.day = 7 * n * _interval;
            periodStart = [cal dateByAddingComponents:step toDate:weekStart options:0];
            NSArray *wds = _byDay.count ? [_byDay valueForKey:@"dayOfTheWeek"] : @[@(s.weekday)];
            for (NSInteger i = 0; i < 7; i++) {
                NSDateComponents *off = [NSDateComponents new];
                off.day = i;
                off.hour = 12;
                NSDate *day = [cal dateByAddingComponents:off toDate:periodStart options:0];
                NSDateComponents *dc = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitWeekday
                                              fromDate:day];
                if (![wds containsObject:@(dc.weekday)])
                    continue;
                if (_byMonth.count && ![_byMonth containsObject:@(dc.month)])
                    continue;
                [days addObject:dc];
            }
        } else if (_freq == EKRecurrenceFrequencyMonthly) {
            NSInteger m0 = s.year * 12 + (s.month - 1) + n * _interval;
            NSInteger year = m0 / 12, month = m0 % 12 + 1;
            NSDateComponents *pc = [NSDateComponents new];
            pc.year = year;
            pc.month = month;
            pc.day = 1;
            periodStart = [cal dateFromComponents:pc];
            if (!_byMonth.count || [_byMonth containsObject:@(month)])
                for (NSNumber *d in fk_month_days(cal, year, month, _byMonthDay, _byDay, s.day)) {
                    NSDateComponents *dc = [NSDateComponents new];
                    dc.year = year;
                    dc.month = month;
                    dc.day = d.integerValue;
                    [days addObject:dc];
                }
        } else {
            NSInteger year = s.year + n * _interval;
            NSDateComponents *pc = [NSDateComponents new];
            pc.year = year;
            pc.month = 1;
            pc.day = 1;
            periodStart = [cal dateFromComponents:pc];
            if (_byYearDay.count && !_byMonth.count) {
                NSInteger length = [cal rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitYear forDate:periodStart].length;
                for (NSNumber *yd in _byYearDay) {
                    NSInteger d = yd.integerValue < 0 ? length + 1 + yd.integerValue : yd.integerValue;
                    NSDateComponents *off = [NSDateComponents new];
                    off.day = d - 1;
                    off.hour = 12;
                    NSDate *day = [cal dateByAddingComponents:off toDate:periodStart options:0];
                    [days addObject:[cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day]];
                }
            } else {
                NSArray *months = _byMonth.count ? _byMonth : @[@(s.month)];
                BOOL byDayInYear = _byDay.count && !_byMonth.count && !_byMonthDay.count;
                if (byDayInYear) {
                    /* the nth weekday of the year */
                    NSInteger length = [cal rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitYear forDate:periodStart].length;
                    NSInteger wd1 = [cal component:NSCalendarUnitWeekday fromDate:periodStart];
                    for (EKRecurrenceDayOfWeek *w in _byDay) {
                        NSMutableArray *all = [NSMutableArray array];
                        for (NSInteger d = 1 + ((NSInteger)w.dayOfTheWeek - wd1 + 7) % 7; d <= length; d += 7)
                            [all addObject:@(d)];
                        NSArray *pick = all;
                        if (w.weekNumber) {
                            NSInteger i = w.weekNumber > 0 ? w.weekNumber - 1 : (NSInteger)all.count + w.weekNumber;
                            pick = i >= 0 && i < (NSInteger)all.count ? @[all[i]] : @[];
                        }
                        for (NSNumber *yd in pick) {
                            NSDateComponents *off = [NSDateComponents new];
                            off.day = yd.integerValue - 1;
                            off.hour = 12;
                            NSDate *day = [cal dateByAddingComponents:off toDate:periodStart options:0];
                            [days addObject:[cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day]];
                        }
                    }
                } else
                    for (NSNumber *m in months)
                        for (NSNumber *d in fk_month_days(cal, year, m.integerValue, _byMonthDay, _byDay, s.day)) {
                            NSDateComponents *dc = [NSDateComponents new];
                            dc.year = year;
                            dc.month = m.integerValue;
                            dc.day = d.integerValue;
                            [days addObject:dc];
                        }
            }
        }
        if (to && [periodStart compare:to] != NSOrderedAscending && !count)
            break;
        if (until && [periodStart compare:until] == NSOrderedDescending)
            break;
        /* the period's starts, at dtstart's time of day */
        NSMutableArray *starts = [NSMutableArray array];
        for (NSDateComponents *dc in days) {
            NSDateComponents *t = [NSDateComponents new];
            t.year = dc.year;
            t.month = dc.month;
            t.day = dc.day;
            t.hour = s.hour;
            t.minute = s.minute;
            t.second = s.second;
            NSDate *d = [cal dateFromComponents:t];
            if (d)
                [starts addObject:d];
        }
        [starts sortUsingSelector:@selector(compare:)];
        if (_bySetPos.count && starts.count) {
            NSMutableArray *picked = [NSMutableArray array];
            for (NSNumber *p in _bySetPos) {
                NSInteger i = p.integerValue > 0 ? p.integerValue - 1 : (NSInteger)starts.count + p.integerValue;
                if (i >= 0 && i < (NSInteger)starts.count && ![picked containsObject:starts[i]])
                    [picked addObject:starts[i]];
            }
            starts = [[picked sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
        }
        for (NSDate *d in starts) {
            if ([d compare:dtstart] == NSOrderedAscending)
                continue;
            if (until && [d compare:until] == NSOrderedDescending)
                return out;
            made++;
            if (count && made > count)
                return out;
            if (to && [d compare:to] != NSOrderedAscending)
                return out;
            NSDate *end = [d dateByAddingTimeInterval:length];
            if (!from || [end compare:from] == NSOrderedDescending || (length == 0 && [d compare:from] != NSOrderedAscending))
                [out addObject:d];
        }
    }
    return out;
}
@end

/* ---- locations, alarms and people ---------------------------------------------------------- */

@implementation EKStructuredLocation
+ (instancetype)locationWithTitle:(NSString *)title
{
    EKStructuredLocation *l = [self new];
    l.title = title;
    return l;
}
- (id)copyWithZone:(NSZone *)zone
{
    EKStructuredLocation *l = [EKStructuredLocation locationWithTitle:_title];
    l.geoLocation = _geoLocation;
    l.radius = _radius;
    return l;
}
@end

@implementation EKAlarm {
@public
    FKComp *_comp;    /* as read, for what isn't kept here */
}
+ (EKAlarm *)alarmWithAbsoluteDate:(NSDate *)date
{
    EKAlarm *a = [self new];
    a.absoluteDate = date;
    return a;
}
+ (EKAlarm *)alarmWithRelativeOffset:(NSTimeInterval)offset
{
    EKAlarm *a = [self new];
    a.relativeOffset = offset;
    return a;
}
- (id)copyWithZone:(NSZone *)zone
{
    EKAlarm *a = [EKAlarm new];
    a.relativeOffset = _relativeOffset;
    a.absoluteDate = _absoluteDate;
    a.structuredLocation = _structuredLocation;
    a.proximity = _proximity;
    a.emailAddress = _emailAddress;
    a.soundName = _soundName;
    a.url = _url;
    a->_comp = [_comp copy];
    return a;
}
- (EKAlarmType)type
{
    if (_emailAddress)
        return EKAlarmTypeEmail;
    if (_soundName)
        return EKAlarmTypeAudio;
    return EKAlarmTypeDisplay;
}
- (BOOL)isEqual:(id)o
{
    if (![o isKindOfClass:[EKAlarm class]])
        return NO;
    EKAlarm *a = o;
    return _relativeOffset == a.relativeOffset && fk_same(_absoluteDate, a.absoluteDate);
}
- (NSUInteger)hash { return (NSUInteger)_relativeOffset; }
+ (EKAlarm *)_alarmFrom:(FKComp *)c
{
    FKProp *t = [c prop:@"TRIGGER"];
    if (!t)
        return nil;
    EKAlarm *a = [EKAlarm new];
    a->_comp = c;
    if ([[t param:@"VALUE"] isEqualToString:@"DATE-TIME"])
        a.absoluteDate = fk_prop_date(t, NULL, NULL);
    else
        a.relativeOffset = fk_duration(t.value);
    NSString *action = [[c text:@"ACTION"] uppercaseString];
    if ([action isEqualToString:@"AUDIO"])
        a.soundName = [c text:@"ATTACH"] ?: @"Basso";
    if ([action isEqualToString:@"EMAIL"])
        a.emailAddress = [[c text:@"ATTENDEE"] stringByReplacingOccurrencesOfString:@"mailto:" withString:@""];
    return a;
}
- (FKComp *)_compWithTitle:(NSString *)title
{
    FKComp *c = [_comp copy] ?: [[FKComp alloc] initWithName:@"VALARM"];
    [c removeProps:[NSSet setWithObjects:@"TRIGGER", @"ACTION", nil]];
    if (!_comp)
        [c addText:@"DESCRIPTION" value:title.length ? title : @"Reminder"];
    [c add:@"ACTION" params:nil value:_soundName ? @"AUDIO" : _emailAddress ? @"EMAIL" : @"DISPLAY"];
    if (_absoluteDate)
        [c add:@"TRIGGER" params:@[@[@"VALUE", @"DATE-TIME"]] value:fk_utc_stamp(_absoluteDate)];
    else
        [c add:@"TRIGGER" params:nil value:fk_format_duration(_relativeOffset)];
    return c;
}
@end

@implementation EKParticipant {
@public
    NSURL *_url;
    NSString *_name;
    EKParticipantStatus _status;
    EKParticipantRole _role;
    EKParticipantType _ptype;
    BOOL _me;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSURL *)URL { return _url; }
- (NSString *)name { return _name; }
- (EKParticipantStatus)participantStatus { return _status; }
- (EKParticipantRole)participantRole { return _role; }
- (EKParticipantType)participantType { return _ptype; }
- (BOOL)isCurrentUser { return _me; }
- (NSPredicate *)contactPredicate { return [NSPredicate predicateWithValue:NO]; }
+ (EKParticipant *)_from:(FKProp *)p me:(NSSet *)myAddresses
{
    EKParticipant *e = [EKParticipant new];
    e->_url = [NSURL URLWithString:p.value];
    e->_name = [p param:@"CN"];
    NSDictionary *st = @{@"NEEDS-ACTION" : @(EKParticipantStatusPending), @"ACCEPTED" : @(EKParticipantStatusAccepted),
                         @"DECLINED" : @(EKParticipantStatusDeclined), @"TENTATIVE" : @(EKParticipantStatusTentative),
                         @"DELEGATED" : @(EKParticipantStatusDelegated), @"COMPLETED" : @(EKParticipantStatusCompleted),
                         @"IN-PROCESS" : @(EKParticipantStatusInProcess)};
    e->_status = [st[[[p param:@"PARTSTAT"] uppercaseString] ?: @"NEEDS-ACTION"] integerValue];
    NSDictionary *roles = @{@"REQ-PARTICIPANT" : @(EKParticipantRoleRequired), @"OPT-PARTICIPANT" : @(EKParticipantRoleOptional),
                            @"CHAIR" : @(EKParticipantRoleChair), @"NON-PARTICIPANT" : @(EKParticipantRoleNonParticipant)};
    e->_role = [roles[[[p param:@"ROLE"] uppercaseString] ?: @"REQ-PARTICIPANT"] integerValue];
    NSDictionary *types = @{@"INDIVIDUAL" : @(EKParticipantTypePerson), @"ROOM" : @(EKParticipantTypeRoom),
                            @"RESOURCE" : @(EKParticipantTypeResource), @"GROUP" : @(EKParticipantTypeGroup)};
    e->_ptype = [types[[[p param:@"CUTYPE"] uppercaseString] ?: @"INDIVIDUAL"] integerValue];
    NSString *addr = [[p.value lowercaseString] stringByReplacingOccurrencesOfString:@"mailto:" withString:@""];
    e->_me = [myAddresses containsObject:addr];
    return e;
}
- (NSString *)description { return [NSString stringWithFormat:@"<EKParticipant %@ %@>", _name, _url]; }
@end

/* ---- items ------------------------------------------------------------------------------- */

/* Properties an item writes itself; any other is kept as it was read. */
static NSSet *fk_event_known(void)
{
    return [NSSet setWithObjects:@"UID", @"DTSTAMP", @"LAST-MODIFIED", @"DTSTART", @"DTEND", @"DURATION", @"SUMMARY",
                                 @"LOCATION", @"DESCRIPTION", @"URL", @"RRULE", @"EXDATE", @"RECURRENCE-ID", @"TRANSP", nil];
}
static NSSet *fk_todo_known(void)
{
    return [NSSet setWithObjects:@"UID", @"DTSTAMP", @"LAST-MODIFIED", @"SUMMARY", @"DESCRIPTION", @"URL", @"DUE",
                                 @"DTSTART", @"STATUS", @"COMPLETED", @"PRIORITY", @"RRULE", nil];
}

@implementation EKCalendarItem {
@public
    __weak EKEventStore *_store;
    NSString *_uid;
    FKComp *_comp;             /* as read; nil for a new item */
    NSString *_loaded;         /* what it would write as read, to tell changes */
    NSMutableArray *_alarmsM, *_rulesM;
    NSArray *_people;
    NSDate *_created, *_modified;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _alarmsM = [NSMutableArray array];
        _rulesM = [NSMutableArray array];
        _timeZone = [NSTimeZone localTimeZone];
    }
    return self;
}
- (NSString *)UUID { return _uid; }
- (NSString *)calendarItemIdentifier { return _uid; }
- (NSString *)calendarItemExternalIdentifier { return _uid; }
- (NSDate *)lastModifiedDate { return _modified; }
- (NSDate *)creationDate { return _created; }
- (BOOL)hasAlarms { return _alarmsM.count > 0; }
- (BOOL)hasRecurrenceRules { return _rulesM.count > 0; }
- (BOOL)hasAttendees { return _people.count > 0; }
- (BOOL)hasNotes { return self.notes.length > 0; }
- (NSArray *)attendees { return _people.count ? _people : nil; }
- (NSArray *)alarms { return _alarmsM.count ? [_alarmsM copy] : nil; }
- (void)setAlarms:(NSArray *)alarms { _alarmsM = [NSMutableArray arrayWithArray:alarms ?: @[]]; }
- (void)addAlarm:(EKAlarm *)alarm
{
    if (alarm)
        [_alarmsM addObject:alarm];
}
- (void)removeAlarm:(EKAlarm *)alarm { [_alarmsM removeObject:alarm]; }
- (NSArray *)recurrenceRules { return _rulesM.count ? [_rulesM copy] : nil; }
- (void)setRecurrenceRules:(NSArray *)rules { _rulesM = [NSMutableArray arrayWithArray:rules ?: @[]]; }
- (void)addRecurrenceRule:(EKRecurrenceRule *)rule
{
    if (rule)
        [_rulesM addObject:rule];
}
- (void)removeRecurrenceRule:(EKRecurrenceRule *)rule { [_rulesM removeObject:rule]; }
- (BOOL)isNew { return _comp == nil; }
- (FKComp *)_component { return nil; }
- (BOOL)hasChanges { return !_comp || ![[self _fingerprint] isEqualToString:_loaded]; }
- (NSString *)_fingerprint
{
    FKComp *c = [self _component];
    [c removeProps:[NSSet setWithObjects:@"DTSTAMP", @"LAST-MODIFIED", nil]];
    NSMutableArray *lines = [NSMutableArray array];
    [c write:lines];
    return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:self.calendar.calendarIdentifier ?: @""];
}
- (void)_readCommon:(FKComp *)c
{
    _comp = c;
    _uid = [c text:@"UID"] ?: [[NSUUID UUID] UUIDString];
    self.title = [c text:@"SUMMARY"] ?: @"";
    self.location = [c text:@"LOCATION"];
    self.notes = [c text:@"DESCRIPTION"];
    NSString *u = [c text:@"URL"];
    self.URL = u.length ? [NSURL URLWithString:u] : nil;
    _created = fk_prop_date([c prop:@"CREATED"], NULL, NULL);
    _modified = fk_prop_date([c prop:@"LAST-MODIFIED"], NULL, NULL) ?: fk_prop_date([c prop:@"DTSTAMP"], NULL, NULL);
    _alarmsM = [NSMutableArray array];
    for (FKComp *s in c.subs)
        if ([s.name isEqualToString:@"VALARM"]) {
            EKAlarm *a = [EKAlarm _alarmFrom:s];
            if (a)
                [_alarmsM addObject:a];
        }
    _rulesM = [NSMutableArray array];
    for (FKProp *p in [c allProps:@"RRULE"]) {
        EKRecurrenceRule *r = [EKRecurrenceRule _ruleFromValue:p.value];
        if (r)
            [_rulesM addObject:r];
    }
}
- (void)_writeCommon:(FKComp *)c known:(NSSet *)known
{
    [c removeProps:known];
    NSMutableArray *subs = [NSMutableArray array];
    for (FKComp *s in c.subs)
        if (![s.name isEqualToString:@"VALARM"])
            [subs addObject:s];
    c.subs = subs;
    [c.props insertObject:[FKProp new] atIndex:0];
    [c.props removeObjectAtIndex:0];
    NSMutableArray *front = [NSMutableArray array];
    FKComp *f = [[FKComp alloc] initWithName:c.name];
    [f add:@"UID" params:nil value:_uid];
    [f add:@"DTSTAMP" params:nil value:fk_utc_stamp(nil)];
    [front addObjectsFromArray:f.props];
    [c.props insertObjects:front atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, front.count)]];
    [c addText:@"SUMMARY" value:self.title.length ? self.title : @""];
    if (!self.title.length)
        [c add:@"SUMMARY" params:nil value:@""];
    [c addText:@"LOCATION" value:self.location];
    [c addText:@"DESCRIPTION" value:self.notes];
    if (self.URL)
        [c add:@"URL" params:nil value:self.URL.absoluteString];
    for (EKRecurrenceRule *r in _rulesM)
        [c add:@"RRULE" params:nil value:[r _value]];
    for (EKAlarm *a in _alarmsM)
        [c.subs addObject:[a _compWithTitle:self.title]];
}
- (void)rollback
{
    if (_comp)
        [self _read:_comp];
}
- (void)_read:(FKComp *)c {}
- (BOOL)refresh
{
    EKCalendarItem *now = [_store calendarItemWithIdentifier:_uid];
    if (!now)
        return NO;
    if (!self.hasChanges)
        [self _read:now->_comp];
    return YES;
}
@end

@implementation EKEvent {
@public
    NSDate *_occurrence;        /* for an occurrence of a series: its date in the series */
    EKEvent *_master;           /* and the series it is part of */
    NSDate *_recurrenceID;      /* for a changed date of a series, read from its component */
    NSMutableArray *_exdates;
    EKParticipant *_organizer;
    EKEventStatus _status;
}
+ (EKEvent *)eventWithEventStore:(EKEventStore *)store
{
    EKEvent *e = [EKEvent new];
    e->_store = store;
    e->_uid = [[[NSUUID UUID] UUIDString] stringByAppendingString:@"@freemac"];
    e->_exdates = [NSMutableArray array];
    e.title = @"";
    e.availability = EKEventAvailabilityBusy;
    return e;
}
- (NSString *)eventIdentifier { return _comp || _master ? _uid : nil; }
- (EKParticipant *)organizer { return _organizer; }
/* No header names it: the user's own answer to an invitation, for apps
 * that read it by key (Itsycal shows a tentative event so; freemac 1.232).
 * Unknown when the user isn't among the attendees. */
- (EKParticipantStatus)participationStatus
{
    for (EKParticipant *p in self.attendees)
        if (p.isCurrentUser)
            return p.participantStatus;
    return EKParticipantStatusUnknown;
}
- (EKEventStatus)status { return _status; }
- (BOOL)isDetached { return _recurrenceID != nil; }
- (NSDate *)occurrenceDate { return _occurrence ?: _recurrenceID ?: self.startDate; }
- (NSString *)birthdayContactIdentifier { return nil; }
- (NSInteger)birthdayPersonID { return -1; }
- (NSString *)birthdayPersonUniqueID { return nil; }
- (NSComparisonResult)compareStartDateWithEvent:(EKEvent *)other { return [self.startDate compare:other.startDate]; }
- (EKStructuredLocation *)structuredLocation
{
    return self.location.length ? [EKStructuredLocation locationWithTitle:self.location] : nil;
}
- (void)setStructuredLocation:(EKStructuredLocation *)l { self.location = l.title; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<EKEvent \"%@\" %@ - %@%@>", self.title, self.startDate, self.endDate, self.allDay ? @" all day" : @""];
}
- (void)_read:(FKComp *)c
{
    [self _readCommon:c];
    BOOL allDay = NO;
    NSTimeZone *zone = nil;
    NSDate *start = fk_prop_date([c prop:@"DTSTART"], &allDay, &zone);
    BOOL endDay = NO;
    NSDate *end = fk_prop_date([c prop:@"DTEND"], &endDay, NULL);
    if (!end) {
        FKProp *d = [c prop:@"DURATION"];
        end = d ? [start dateByAddingTimeInterval:fk_duration(d.value)] : [start dateByAddingTimeInterval:allDay ? 86400 : 0];
    }
    if ([end compare:start] == NSOrderedAscending)
        end = start;
    /* an all-day event ends at the last second of its last day, as on a Mac */
    if (allDay && [end compare:start] == NSOrderedDescending)
        end = [end dateByAddingTimeInterval:-1];
    self.allDay = allDay;
    self.startDate = start;
    self.endDate = end;
    self.timeZone = allDay || !zone ? (allDay ? nil : [NSTimeZone localTimeZone]) : zone;
    NSString *transp = [[c text:@"TRANSP"] uppercaseString];
    self.availability = [transp isEqualToString:@"TRANSPARENT"] ? EKEventAvailabilityFree : EKEventAvailabilityBusy;
    NSString *st = [[c text:@"STATUS"] uppercaseString];
    _status = [st isEqualToString:@"CONFIRMED"] ? EKEventStatusConfirmed : [st isEqualToString:@"TENTATIVE"] ? EKEventStatusTentative
              : [st isEqualToString:@"CANCELLED"] ? EKEventStatusCanceled : EKEventStatusNone;
    _recurrenceID = fk_prop_date([c prop:@"RECURRENCE-ID"], NULL, NULL);
    _exdates = [NSMutableArray array];
    for (FKProp *p in [c allProps:@"EXDATE"])
        for (NSString *v in [p.value componentsSeparatedByString:@","]) {
            NSDate *d = fk_date_value(v, [p param:@"TZID"], NULL, NULL);
            if (d)
                [_exdates addObject:d];
        }
    NSSet *me = [_store valueForKey:@"_myAddresses"];
    NSMutableArray *people = [NSMutableArray array];
    for (FKProp *p in [c allProps:@"ATTENDEE"])
        [people addObject:[EKParticipant _from:p me:me]];
    _people = people;
    FKProp *org = [c prop:@"ORGANIZER"];
    _organizer = org ? [EKParticipant _from:org me:me] : nil;
    _loaded = [self _fingerprint];
}
- (FKComp *)_component
{
    FKComp *c = [_comp copy] ?: [[FKComp alloc] initWithName:@"VEVENT"];
    [self _writeCommon:c known:fk_event_known()];
    NSArray *params;
    NSString *v = fk_format_date(self.startDate ?: [NSDate date], self.allDay, self.timeZone, &params);
    [c add:@"DTSTART" params:params value:v];
    NSDate *end = self.endDate ?: self.startDate ?: [NSDate date];
    if (self.allDay) {
        /* to midnight after the last day */
        NSCalendar *cal = fk_calendar(nil);
        NSDate *last = [cal startOfDayForDate:end];
        if ([last compare:[cal startOfDayForDate:self.startDate ?: end]] != NSOrderedDescending ||
            [end compare:last] == NSOrderedDescending)
            end = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:last options:0];
        else
            end = last;
    }
    v = fk_format_date(end, self.allDay, self.timeZone, &params);
    [c add:@"DTEND" params:params value:v];
    if (_recurrenceID) {
        v = fk_format_date(_recurrenceID, self.allDay, self.timeZone, &params);
        [c add:@"RECURRENCE-ID" params:params value:v];
    }
    for (NSDate *x in _exdates) {
        v = fk_format_date(x, self.allDay, self.timeZone, &params);
        [c add:@"EXDATE" params:params value:v];
    }
    if (self.availability == EKEventAvailabilityFree)
        [c add:@"TRANSP" params:nil value:@"TRANSPARENT"];
    return c;
}
/* A copy of this series at one of its dates. */
- (EKEvent *)_occurrenceAt:(NSDate *)start
{
    EKEvent *o = [EKEvent new];
    o->_store = _store;
    [o _read:_comp];
    o.calendar = self.calendar;
    NSTimeInterval length = [self.endDate timeIntervalSinceDate:self.startDate];
    o.startDate = start;
    o.endDate = [start dateByAddingTimeInterval:length];
    o->_occurrence = start;
    o->_master = self;
    o->_loaded = [o _fingerprint];
    return o;
}
@end

@implementation EKReminder {
@public
    NSString *_listID;
}
+ (EKReminder *)reminderWithEventStore:(EKEventStore *)store
{
    EKReminder *r = [EKReminder new];
    r->_store = store;
    r->_uid = [[[NSUUID UUID] UUIDString] stringByAppendingString:@"@freemac"];
    r.title = @"";
    r.timeZone = nil;
    return r;
}
- (NSString *)description { return [NSString stringWithFormat:@"<EKReminder \"%@\"%@>", self.title, self.completed ? @" done" : @""]; }
- (void)setCompleted:(BOOL)completed
{
    _completed = completed;
    if (completed && !_completionDate)
        _completionDate = [NSDate date];
    if (!completed)
        _completionDate = nil;
}
- (void)setCompletionDate:(NSDate *)date
{
    _completionDate = [date copy];
    _completed = date != nil;
}

static NSDateComponents *fk_components(FKProp *p)
{
    if (!p)
        return nil;
    BOOL allDay = NO;
    NSTimeZone *zone = nil;
    NSDate *d = fk_prop_date(p, &allDay, &zone);
    if (!d)
        return nil;
    NSCalendar *cal = fk_calendar(allDay ? nil : zone);
    NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
    if (!allDay)
        units |= NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    NSDateComponents *c = [cal components:units fromDate:d];
    c.calendar = fk_calendar(nil);
    if (!allDay)
        c.timeZone = zone ?: [NSTimeZone localTimeZone];
    return c;
}

static void fk_add_components(FKComp *c, NSString *name, NSDateComponents *dc)
{
    if (!dc || dc.year == NSDateComponentUndefined)
        return;
    BOOL timed = dc.hour != NSDateComponentUndefined;
    if (!timed) {
        [c add:name params:@[@[@"VALUE", @"DATE"]]
            value:[NSString stringWithFormat:@"%04ld%02ld%02ld", (long)dc.year, (long)dc.month, (long)dc.day]];
        return;
    }
    NSCalendar *cal = fk_calendar(dc.timeZone);
    NSDateComponents *t = [dc copy];
    t.calendar = nil;
    t.timeZone = nil;
    NSDate *d = [cal dateFromComponents:t];
    NSArray *params;
    NSString *v = fk_format_date(d, NO, dc.timeZone ?: [NSTimeZone localTimeZone], &params);
    [c add:name params:params value:v];
}

- (void)_read:(FKComp *)c
{
    [self _readCommon:c];
    self.timeZone = nil;
    self.dueDateComponents = fk_components([c prop:@"DUE"]);
    self.startDateComponents = fk_components([c prop:@"DTSTART"]);
    NSDate *done = fk_prop_date([c prop:@"COMPLETED"], NULL, NULL);
    BOOL completed = [[[c text:@"STATUS"] uppercaseString] isEqualToString:@"COMPLETED"] || done;
    _completed = completed;
    _completionDate = completed ? (done ?: _modified ?: [NSDate date]) : nil;
    NSInteger pr = [[c text:@"PRIORITY"] integerValue];
    self.priority = pr <= 0 ? 0 : pr <= 4 ? 1 : pr == 5 ? 5 : 9;
    _loaded = [self _fingerprint];
}
- (FKComp *)_component
{
    FKComp *c = [_comp copy] ?: [[FKComp alloc] initWithName:@"VTODO"];
    [self _writeCommon:c known:fk_todo_known()];
    fk_add_components(c, @"DTSTART", self.startDateComponents);
    fk_add_components(c, @"DUE", self.dueDateComponents);
    if (self.completed) {
        [c add:@"STATUS" params:nil value:@"COMPLETED"];
        NSArray *params;
        [c add:@"COMPLETED" params:nil value:fk_format_date(self.completionDate ?: [NSDate date], NO, nil, &params)];
    } else
        [c add:@"STATUS" params:nil value:@"NEEDS-ACTION"];
    if (self.priority)
        [c add:@"PRIORITY" params:nil value:[NSString stringWithFormat:@"%lu", (unsigned long)self.priority]];
    return c;
}
@end

/* ---- predicates ---------------------------------------------------------------------------- */

enum { FK_EVENTS, FK_REMINDERS, FK_INCOMPLETE, FK_COMPLETED };

@interface FKPredicate : NSPredicate
@property (nonatomic) int kind;
@property (nonatomic, copy) NSDate *start, *end;
@property (nonatomic, copy) NSArray *calendars;
@end
@implementation FKPredicate
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)predicateFormat
{
    static const char *kinds[] = {"events", "reminders", "incomplete reminders", "completed reminders"};
    return [NSString stringWithFormat:@"EventKit %s from %@ to %@ in %lu calendars", kinds[_kind], _start, _end,
                                      (unsigned long)_calendars.count];
}
- (BOOL)_inCalendar:(EKCalendar *)cal
{
    if (!_calendars)
        return YES;
    for (EKCalendar *c in _calendars)
        if ([c.calendarIdentifier isEqualToString:cal.calendarIdentifier])
            return YES;
    return NO;
}
- (BOOL)evaluateWithObject:(id)o
{
    if (_kind == FK_EVENTS) {
        if (![o isKindOfClass:[EKEvent class]] || ![self _inCalendar:[(EKCalendarItem *)o calendar]])
            return NO;
        EKEvent *e = o;
        return [e.startDate compare:_end] == NSOrderedAscending &&
               ([e.endDate compare:_start] == NSOrderedDescending ||
                ([e.endDate isEqual:e.startDate] && [e.startDate compare:_start] != NSOrderedAscending));
    }
    if (![o isKindOfClass:[EKReminder class]] || ![self _inCalendar:[(EKCalendarItem *)o calendar]])
        return NO;
    EKReminder *r = o;
    if (_kind == FK_REMINDERS)
        return YES;
    if (_kind == FK_COMPLETED) {
        if (!r.completed)
            return NO;
        NSDate *d = r.completionDate;
        return (!_start || (d && [d compare:_start] != NSOrderedAscending)) && (!_end || (d && [d compare:_end] == NSOrderedAscending));
    }
    if (r.completed)
        return NO;
    if (!_start && !_end)
        return YES;
    NSDateComponents *dc = r.dueDateComponents;
    if (!dc)
        return NO;
    NSDateComponents *t = [dc copy];
    t.calendar = nil;
    t.timeZone = nil;
    NSDate *due = [fk_calendar(dc.timeZone) dateFromComponents:t];
    return (!_start || [due compare:_start] != NSOrderedAscending) && (!_end || [due compare:_end] == NSOrderedAscending);
}
- (BOOL)evaluateWithObject:(id)o substitutionVariables:(NSDictionary *)b { return [self evaluateWithObject:o]; }
@end

/* ---- the store ----------------------------------------------------------------------------- */

static NSHashTable *fk_stores;
static dispatch_source_t fk_timer;
static NSString *fk_seen;    /* the files' signature last seen by the watch */

static void fk_post_changed(EKEventStore *except)
{
    NSArray *stores;
    @synchronized([EKEventStore class]) {
        stores = fk_stores.allObjects;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (EKEventStore *s in stores)
            if (s != except)
                [[NSNotificationCenter defaultCenter] postNotificationName:EKEventStoreChangedNotification object:s];
        if (except)
            [[NSNotificationCenter defaultCenter] postNotificationName:EKEventStoreChangedNotification object:except];
    });
}

static void fk_watch(void)
{
    if (fk_timer)
        return;
    fk_seen = fk_signature();
    fk_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_timer(fk_timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
    dispatch_source_set_event_handler(fk_timer, ^{
        NSString *now = fk_signature();
        BOOL changed = NO;
        @synchronized([EKEventStore class]) {
            if (![now isEqualToString:fk_seen]) {
                fk_seen = now;
                changed = YES;
            }
        }
        if (changed)
            fk_post_changed(nil);
    });
    dispatch_resume(fk_timer);
}

@implementation EKEventStore {
    NSString *_ident;
    NSString *_loadedSignature;
    NSMutableArray<EKSource *> *_sourcesM;
    NSMutableArray<EKCalendar *> *_calendarsM;
    NSMutableArray<EKEvent *> *_eventsM;           /* each VEVENT read: series, single events and changed dates */
    NSMutableArray<EKReminder *> *_remindersM;
    NSMutableArray *_pending;                      /* changes not yet committed: blocks taking an NSError ** */
    NSSet *_myAddresses;
}

+ (EKAuthorizationStatus)authorizationStatusForEntityType:(EKEntityType)t
{
    int a = fk_answer(t);
    return a < 0 ? EKAuthorizationStatusNotDetermined : a ? EKAuthorizationStatusFullAccess : EKAuthorizationStatusDenied;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _ident = [[NSUUID UUID] UUIDString];
        _pending = [NSMutableArray array];
        @synchronized([EKEventStore class]) {
            if (!fk_stores)
                fk_stores = [NSHashTable weakObjectsHashTable];
            [fk_stores addObject:self];
            fk_watch();
        }
    }
    return self;
}
- (instancetype)initWithAccessToEntityTypes:(EKEntityMask)entityTypes { return [self init]; }
- (instancetype)initWithSources:(NSArray *)sources { return [self init]; }
- (NSString *)eventStoreIdentifier { return _ident; }
- (NSSet *)_myAddresses { return _myAddresses ?: [NSSet set]; }

- (void)_request:(EKEntityType)t completion:(EKEventStoreRequestAccessCompletionHandler)completion
{
    int a = fk_answer(t);
    if (a >= 0) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if (completion)
                completion(a == 1, nil);
        });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        int now = fk_answer(t);
        BOOL granted;
        if (now >= 0)
            granted = now == 1;
        else {
            const char *wl = getenv("WAYLAND_DISPLAY"), *x = getenv("DISPLAY");
            BOOL canAsk = objc_getClass("NSAlert") && ((wl && *wl) || (x && *x));
            granted = fk_ask(t);
            if (canAsk)
                fk_keep_answer(t, granted);
            else {
                const char *v = getenv("FERRY_VERBOSE");
                if (v && *v)
                    fprintf(stderr, "ferry: EventKit: no display to ask on whether %s may use the %s; not allowed\n",
                            fk_app_name().UTF8String, t == EKEntityTypeReminder ? "reminders" : "calendars");
            }
        }
        @synchronized(self) {
            self->_loadedSignature = nil;
        }
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if (completion)
                completion(granted, nil);
        });
    });
}
- (void)requestAccessToEntityType:(EKEntityType)t completion:(EKEventStoreRequestAccessCompletionHandler)completion
{
    [self _request:t completion:completion];
}
- (void)requestFullAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)completion
{
    [self _request:EKEntityTypeEvent completion:completion];
}
- (void)requestWriteOnlyAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)completion
{
    [self _request:EKEntityTypeEvent completion:completion];
}
- (void)requestFullAccessToRemindersWithCompletion:(EKEventStoreRequestAccessCompletionHandler)completion
{
    [self _request:EKEntityTypeReminder completion:completion];
}

/* ---- loading ---- */

- (EKSource *)_source:(NSString *)ident title:(NSString *)title type:(EKSourceType)type
{
    for (EKSource *s in _sourcesM)
        if ([s->_identifier isEqualToString:ident])
            return s;
    EKSource *s = [EKSource new];
    s->_identifier = ident;
    s->_title = title;
    s->_type = type;
    s->_store = self;
    [_sourcesM addObject:s];
    return s;
}

/* An online account's source, by the account named in X-FREEMAC-SOURCE. */
- (EKSource *)_sourceForMark:(NSString *)mark
{
    if (!mark.length)
        return [self _source:@"freemac-local" title:@"On My Mac" type:EKSourceTypeLocal];
    NSString *account = [mark componentsSeparatedByString:@" "].firstObject;
    NSString *title = @"Online Account";
    NSData *d = [NSData dataWithContentsOfFile:fk_accounts_path()];
    id list = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if ([list isKindOfClass:[NSArray class]])
        for (id a in list)
            if ([a isKindOfClass:[NSDictionary class]] && [a[@"id"] isEqual:account]) {
                NSString *user = a[@"username"], *server = a[@"server"];
                title = [user isKindOfClass:[NSString class]] && user.length ? user
                        : [server isKindOfClass:[NSString class]] && server.length ? server : title;
            }
    return [self _source:[@"freemac-account-" stringByAppendingString:account] title:title type:EKSourceTypeCalDAV];
}

- (EKCalendar *)_calendarWithID:(NSString *)ident
{
    for (EKCalendar *c in _calendarsM)
        if ([c->_identifier isEqualToString:ident])
            return c;
    return nil;
}

/* The events' calendar for an X-FREEMAC-SOURCE mark (none: Tide's own). */
- (EKCalendar *)_eventCalendarForMark:(NSString *)mark
{
    NSString *ident = mark.length ? [@"freemac-events " stringByAppendingString:mark] : @"freemac-calendar";
    EKCalendar *c = [self _calendarWithID:ident];
    if (c)
        return c;
    c = [EKCalendar new];
    c->_identifier = ident;
    c->_mask = EKEntityMaskEvent;
    c->_mark = mark;
    c->_ctype = mark.length ? EKCalendarTypeCalDAV : EKCalendarTypeLocal;
    c->_hex = @"#2f7bf5";
    c->_store = self;
    if (mark.length) {
        NSString *url = [mark substringFromIndex:MIN(mark.length, [mark rangeOfString:@" "].location + 1)];
        NSString *last = [[url stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] lastPathComponent];
        c.title = [last stringByRemovingPercentEncoding] ?: last ?: @"Calendar";
        NSArray *hexes = fk_color_names().allValues;
        c->_hex = hexes[(NSUInteger)labs((long)mark.hash) % hexes.count];
    } else
        c.title = @"Calendar";
    c.source = [self _sourceForMark:mark];
    [_calendarsM addObject:c];
    return c;
}

- (void)_load
{
    _sourcesM = [NSMutableArray array];
    _calendarsM = [NSMutableArray array];
    _eventsM = [NSMutableArray array];
    _remindersM = [NSMutableArray array];
    NSMutableSet *mine = [NSMutableSet set];
    NSData *d = [NSData dataWithContentsOfFile:fk_accounts_path()];
    id list = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if ([list isKindOfClass:[NSArray class]])
        for (id a in list)
            if ([a isKindOfClass:[NSDictionary class]] && [a[@"username"] isKindOfClass:[NSString class]])
                [mine addObject:[a[@"username"] lowercaseString]];
    _myAddresses = mine;
    _loadedSignature = fk_signature();
    if (fk_allowed(EKEntityTypeEvent)) {
        [self _eventCalendarForMark:nil];
        FKComp *cal = fk_read(fk_events_path());
        for (FKComp *c in cal.subs) {
            if (![c.name isEqualToString:@"VEVENT"] || ![c prop:@"DTSTART"])
                continue;
            EKEvent *e = [EKEvent new];
            e->_store = self;
            [e _read:c];
            e.calendar = [self _eventCalendarForMark:[c text:@"X-FREEMAC-SOURCE"]];
            e->_loaded = [e _fingerprint];
            [_eventsM addObject:e];
        }
    }
    if (fk_allowed(EKEntityTypeReminder)) {
        NSString *dir = fk_reminders_dir();
        for (NSString *name in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
                 sortedArrayUsingSelector:@selector(compare:)]) {
            if (![name hasSuffix:@".ics"])
                continue;
            NSString *path = [dir stringByAppendingPathComponent:name];
            FKComp *file = fk_read(path);
            if (!file)
                continue;
            EKCalendar *list = [EKCalendar new];
            list->_identifier = [name stringByDeletingPathExtension];
            list->_mask = EKEntityMaskReminder;
            list->_file = path;
            list->_store = self;
            list.title = [file text:@"X-WR-CALNAME"] ?: @"Reminders";
            NSString *color = [[file text:@"X-FREEMAC-COLOR"] lowercaseString];
            list->_hex = fk_color_names()[color] ?: ([color hasPrefix:@"#"] ? color : @"#2f7bf5");
            list->_order = [[file text:@"X-FREEMAC-ORDER"] integerValue];
            NSString *mark = [file text:@"X-FREEMAC-SOURCE"];
            list->_mark = mark;
            list->_ctype = mark.length ? EKCalendarTypeCalDAV : EKCalendarTypeLocal;
            list.source = [self _sourceForMark:mark];
            [_calendarsM addObject:list];
            for (FKComp *c in file.subs) {
                if (![c.name isEqualToString:@"VTODO"])
                    continue;
                EKReminder *r = [EKReminder new];
                r->_store = self;
                [r _read:c];
                r.calendar = list;
                r->_listID = list->_identifier;
                r->_loaded = [r _fingerprint];
                [_remindersM addObject:r];
            }
        }
        if (![self calendarsForEntityTypeLoaded:EKEntityTypeReminder].count) {
            /* Nudge's empty list, written once something is saved in it */
            EKCalendar *list = [EKCalendar new];
            list->_identifier = @"reminders";
            list->_mask = EKEntityMaskReminder;
            list->_file = [dir stringByAppendingPathComponent:@"reminders.ics"];
            list->_hex = @"#2f7bf5";
            list->_store = self;
            list.title = @"Reminders";
            list.source = [self _sourceForMark:nil];
            [_calendarsM addObject:list];
        }
    }
}

- (void)_ensureLoaded
{
    @synchronized(self) {
        if (!_loadedSignature || ![fk_signature() isEqualToString:_loadedSignature])
            [self _load];
    }
}

- (NSArray *)calendarsForEntityTypeLoaded:(EKEntityType)t
{
    EKEntityMask m = t == EKEntityTypeReminder ? EKEntityMaskReminder : EKEntityMaskEvent;
    NSMutableArray *a = [NSMutableArray array];
    for (EKCalendar *c in _calendarsM)
        if (c->_mask & m)
            [a addObject:c];
    if (t == EKEntityTypeReminder)
        [a sortUsingComparator:^NSComparisonResult(EKCalendar *x, EKCalendar *y) {
            if (x->_order != y->_order)
                return x->_order < y->_order ? NSOrderedAscending : NSOrderedDescending;
            return [x.title localizedCaseInsensitiveCompare:y.title];
        }];
    return a;
}

- (void)reset
{
    @synchronized(self) {
        [_pending removeAllObjects];
        _loadedSignature = nil;
    }
}
- (void)refreshSourcesIfNecessary { [self _ensureLoaded]; }

- (NSArray *)sources
{
    [self _ensureLoaded];
    @synchronized(self) {
        if (!_sourcesM.count)
            [self _sourceForMark:nil];
        return [_sourcesM copy];
    }
}
- (NSArray *)delegateSources { return @[]; }
- (EKSource *)sourceWithIdentifier:(NSString *)identifier
{
    for (EKSource *s in self.sources)
        if ([s.sourceIdentifier isEqualToString:identifier])
            return s;
    return nil;
}
- (NSArray *)calendars { return [self calendarsForEntityType:EKEntityTypeEvent]; }
- (NSArray *)calendarsForEntityType:(EKEntityType)t
{
    [self _ensureLoaded];
    @synchronized(self) {
        return [self calendarsForEntityTypeLoaded:t];
    }
}
- (EKCalendar *)defaultCalendarForNewEvents
{
    [self _ensureLoaded];
    @synchronized(self) {
        return fk_allowed(EKEntityTypeEvent) ? [self _calendarWithID:@"freemac-calendar"] : nil;
    }
}
- (EKCalendar *)defaultCalendarForNewReminders { return [self calendarsForEntityType:EKEntityTypeReminder].firstObject; }
- (EKCalendar *)calendarWithIdentifier:(NSString *)identifier
{
    [self _ensureLoaded];
    @synchronized(self) {
        return [self _calendarWithID:identifier];
    }
}

/* ---- changes: each applied to the file read again --------------------------------------- */

- (BOOL)_apply:(BOOL (^)(NSError **))change commit:(BOOL)commit error:(NSError **)error
{
    @synchronized(self) {
        [_pending addObject:change];
    }
    return commit ? [self commit:error] : YES;
}

- (BOOL)commit:(NSError **)error
{
    NSArray *changes;
    @synchronized(self) {
        changes = [_pending copy];
        [_pending removeAllObjects];
    }
    if (!changes.count)
        return YES;
    BOOL ok = YES;
    @synchronized([EKEventStore class]) {
        for (BOOL (^change)(NSError **) in changes)
            if (!change(error)) {
                ok = NO;
                break;
            }
        fk_seen = fk_signature();
    }
    @synchronized(self) {
        _loadedSignature = nil;
    }
    fk_post_changed(self);
    return ok;
}

/* Reads the events' file, lets block change its components, writes it. */
static BOOL fk_edit_events(NSError **error, void (^block)(NSMutableArray<FKComp *> *events))
{
    FKComp *cal = fk_read(fk_events_path()) ?: fk_new_calendar(@"-//freemac//Tide//EN");
    if (![cal prop:@"CALSCALE"] && ![cal prop:@"X-WR-CALNAME"])
        [cal add:@"CALSCALE" params:nil value:@"GREGORIAN"];
    block(cal.subs);
    return fk_write(fk_events_path(), cal, error);
}

static NSUInteger fk_index_of(NSArray<FKComp *> *comps, NSString *uid, NSDate *rid)
{
    for (NSUInteger i = 0; i < comps.count; i++) {
        FKComp *c = comps[i];
        if (![[c text:@"UID"] isEqualToString:uid])
            continue;
        NSDate *r = fk_prop_date([c prop:@"RECURRENCE-ID"], NULL, NULL);
        if (rid ? (r && fabs([r timeIntervalSinceDate:rid]) < 1) : !r)
            return i;
    }
    return NSNotFound;
}

static void fk_mark(FKComp *c, NSString *mark)
{
    [c removeProps:[NSSet setWithObject:@"X-FREEMAC-SOURCE"]];
    if (mark.length)
        [c add:@"X-FREEMAC-SOURCE" params:nil value:mark];
}

/* A series saved over the one in the file: the dates left out in the file
 * are kept, even those left out since it was read, and when its start moved, the dates left out and the
 * changed dates move with it, so that they still name its occurrences. */
static void fk_keep_series_dates(NSMutableArray<FKComp *> *events, FKComp *old, FKComp *now, NSString *uid)
{
    BOOL allDay = NO;
    NSTimeZone *zone = nil;
    NSDate *was = fk_prop_date([old prop:@"DTSTART"], NULL, NULL);
    NSDate *is = fk_prop_date([now prop:@"DTSTART"], &allDay, &zone);
    NSTimeInterval delta = was && is ? [is timeIntervalSinceDate:was] : 0;
    NSMutableArray *dates = [NSMutableArray array];
    /* the file's, as the item can't leave dates out itself */
    for (FKProp *p in [old allProps:@"EXDATE"])
        for (NSString *v in [p.value componentsSeparatedByString:@","]) {
            NSDate *d = fk_date_value(v, [p param:@"TZID"], NULL, NULL);
            if (d)
                [dates addObject:[d dateByAddingTimeInterval:delta]];
        }
    NSTimeZone *z = allDay ? nil : zone ?: [NSTimeZone localTimeZone];
    [now removeProps:[NSSet setWithObject:@"EXDATE"]];
    for (NSDate *d in dates) {
        NSArray *params;
        NSString *v = fk_format_date(d, allDay, z, &params);
        [now add:@"EXDATE" params:params value:v];
    }
    if (delta == 0)
        return;
    for (FKComp *c in events) {
        FKProp *rid = [c prop:@"RECURRENCE-ID"];
        if (!rid || ![[c text:@"UID"] isEqualToString:uid])
            continue;
        NSDate *d = [fk_prop_date(rid, NULL, NULL) dateByAddingTimeInterval:delta];
        [c removeProps:[NSSet setWithObject:@"RECURRENCE-ID"]];
        NSArray *params;
        NSString *v = fk_format_date(d, allDay, z, &params);
        [c add:@"RECURRENCE-ID" params:params value:v];
    }
}

- (BOOL)saveEvent:(EKEvent *)event span:(EKSpan)span error:(NSError **)error
{
    return [self saveEvent:event span:span commit:YES error:error];
}
- (BOOL)saveEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error
{
    if (!fk_allowed(EKEntityTypeEvent))
        return fk_fail(error, EKErrorEventStoreNotAuthorized, @"This app hasn't been allowed to use the calendar.");
    if (!event.calendar)
        return fk_fail(error, EKErrorNoCalendar, @"No calendar has been set.");
    if (!(event.calendar->_mask & EKEntityMaskEvent))
        return fk_fail(error, EKErrorCalendarDoesNotAllowEvents, @"That calendar doesn't hold events.");
    if (!event.startDate)
        return fk_fail(error, EKErrorNoStartDate, @"No start date has been set.");
    if (!event.endDate)
        return fk_fail(error, EKErrorNoEndDate, @"No end date has been set.");
    if ([event.endDate compare:event.startDate] == NSOrderedAscending)
        return fk_fail(error, EKErrorDatesInverted, @"The start date must be before the end date.");
    EKEvent *master = event->_master;
    NSString *mark = event.calendar->_mark;
    NSDate *occurrence = event->_occurrence;
    FKComp *comp = [event _component];
    fk_mark(comp, mark);
    NSString *uid = event->_uid;
    BOOL ok = [self _apply:^BOOL(NSError **err) {
        return fk_edit_events(err, ^(NSMutableArray<FKComp *> *events) {
            if (master && occurrence && span == EKSpanThisEvent) {
                /* a changed date of the series: a component of its own */
                FKComp *own = [comp copy];
                [own removeProps:[NSSet setWithObjects:@"RRULE", @"EXDATE", @"RECURRENCE-ID", nil]];
                NSArray *params;
                NSString *v = fk_format_date(occurrence, master.allDay, master.timeZone, &params);
                [own add:@"RECURRENCE-ID" params:params value:v];
                NSUInteger i = fk_index_of(events, uid, occurrence);
                if (i != NSNotFound)
                    events[i] = own;
                else
                    [events addObject:own];
            } else if (master && occurrence && span == EKSpanFutureEvents &&
                       [occurrence compare:master.startDate] == NSOrderedDescending) {
                /* the series ends before this date, and a new one starts at it */
                NSUInteger i = fk_index_of(events, uid, nil);
                if (i != NSNotFound) {
                    FKComp *old = events[i];
                    NSMutableArray *rules = [NSMutableArray array];
                    for (FKProp *p in [old allProps:@"RRULE"]) {
                        EKRecurrenceRule *r = [EKRecurrenceRule _ruleFromValue:p.value];
                        r.recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:[occurrence dateByAddingTimeInterval:-1]];
                        [rules addObject:[r _value]];
                    }
                    [old removeProps:[NSSet setWithObject:@"RRULE"]];
                    for (NSString *r in rules)
                        [old add:@"RRULE" params:nil value:r];
                }
                FKComp *next = [comp copy];
                [next removeProps:[NSSet setWithObjects:@"UID", @"RECURRENCE-ID", nil]];
                [next.props insertObject:[FKProp new] atIndex:0];
                FKProp *u = next.props[0];
                u.name = @"UID";
                u.params = @[];
                u.value = [[[NSUUID UUID] UUIDString] stringByAppendingString:@"@freemac"];
                [events addObject:next];
            } else {
                NSUInteger i = fk_index_of(events, uid, event->_recurrenceID);
                if (i != NSNotFound && !event->_recurrenceID)
                    fk_keep_series_dates(events, events[i], comp, uid);
                if (i != NSNotFound)
                    events[i] = comp;
                else
                    [events addObject:comp];
            }
        });
    } commit:commit error:error];
    if (ok && commit && !master) {
        event->_comp = comp;
        event->_loaded = [event _fingerprint];
    }
    return ok;
}

- (BOOL)removeEvent:(EKEvent *)event span:(EKSpan)span error:(NSError **)error
{
    return [self removeEvent:event span:span commit:YES error:error];
}
- (BOOL)removeEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error
{
    if (!fk_allowed(EKEntityTypeEvent))
        return fk_fail(error, EKErrorEventStoreNotAuthorized, @"This app hasn't been allowed to use the calendar.");
    if (!event->_comp && !event->_master)
        return YES;    /* never saved */
    NSString *uid = event->_uid;
    NSDate *occurrence = event->_occurrence ?: event->_recurrenceID;
    BOOL series = event->_master != nil || event->_recurrenceID != nil || event.hasRecurrenceRules;
    BOOL first = !event->_master || [occurrence compare:event->_master.startDate] != NSOrderedDescending;
    EKEvent *master = event->_master;
    return [self _apply:^BOOL(NSError **err) {
        return fk_edit_events(err, ^(NSMutableArray<FKComp *> *events) {
            NSUInteger mi = fk_index_of(events, uid, nil);
            if (!series || (span == EKSpanFutureEvents && first && !event->_recurrenceID)) {
                /* the whole event, with its changed dates */
                NSIndexSet *gone = [events indexesOfObjectsPassingTest:^BOOL(FKComp *c, NSUInteger i, BOOL *stop) {
                    return [[c text:@"UID"] isEqualToString:uid];
                }];
                [events removeObjectsAtIndexes:gone];
                return;
            }
            if (span == EKSpanFutureEvents && mi != NSNotFound) {
                FKComp *m = events[mi];
                NSMutableArray *rules = [NSMutableArray array];
                for (FKProp *p in [m allProps:@"RRULE"]) {
                    EKRecurrenceRule *r = [EKRecurrenceRule _ruleFromValue:p.value];
                    r.recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:[occurrence dateByAddingTimeInterval:-1]];
                    [rules addObject:[r _value]];
                }
                [m removeProps:[NSSet setWithObject:@"RRULE"]];
                for (NSString *r in rules)
                    [m add:@"RRULE" params:nil value:r];
                NSIndexSet *gone = [events indexesOfObjectsPassingTest:^BOOL(FKComp *c, NSUInteger i, BOOL *stop) {
                    NSDate *rid = fk_prop_date([c prop:@"RECURRENCE-ID"], NULL, NULL);
                    return [[c text:@"UID"] isEqualToString:uid] && rid && [rid compare:occurrence] != NSOrderedAscending;
                }];
                [events removeObjectsAtIndexes:gone];
                return;
            }
            /* this date only: left out of the series */
            NSUInteger di = fk_index_of(events, uid, occurrence);
            if (di != NSNotFound) {
                [events removeObjectAtIndex:di];
                mi = fk_index_of(events, uid, nil);
            }
            if (mi != NSNotFound) {
                FKComp *m = events[mi];
                BOOL allDay = NO;
                NSTimeZone *zone = nil;
                fk_prop_date([m prop:@"DTSTART"], &allDay, &zone);
                NSArray *params;
                NSString *v = fk_format_date(occurrence, allDay, master ? master.timeZone : zone ?: [NSTimeZone localTimeZone], &params);
                [m add:@"EXDATE" params:params value:v];
            }
        });
    } commit:commit error:error];
}

- (EKEvent *)eventWithIdentifier:(NSString *)identifier
{
    [self _ensureLoaded];
    @synchronized(self) {
        for (EKEvent *e in _eventsM)
            if ([e->_uid isEqualToString:identifier] && !e->_recurrenceID)
                return e;
        for (EKEvent *e in _eventsM)
            if ([e->_uid isEqualToString:identifier])
                return e;
    }
    return nil;
}
- (EKCalendarItem *)calendarItemWithIdentifier:(NSString *)identifier
{
    EKCalendarItem *e = [self eventWithIdentifier:identifier];
    if (e)
        return e;
    @synchronized(self) {
        for (EKReminder *r in _remindersM)
            if ([r->_uid isEqualToString:identifier])
                return r;
    }
    return nil;
}
- (NSArray *)calendarItemsWithExternalIdentifier:(NSString *)external
{
    [self _ensureLoaded];
    NSMutableArray *a = [NSMutableArray array];
    @synchronized(self) {
        for (EKEvent *e in _eventsM)
            if ([e->_uid isEqualToString:external])
                [a addObject:e];
        for (EKReminder *r in _remindersM)
            if ([r->_uid isEqualToString:external])
                [a addObject:r];
    }
    return a;
}

- (NSPredicate *)predicateForEventsWithStartDate:(NSDate *)start endDate:(NSDate *)end calendars:(NSArray *)calendars
{
    FKPredicate *p = [FKPredicate new];
    p.kind = FK_EVENTS;
    p.start = start;
    p.end = end;
    p.calendars = calendars;
    return p;
}

- (NSArray *)eventsMatchingPredicate:(NSPredicate *)predicate
{
    if (![predicate isKindOfClass:[FKPredicate class]] || [(FKPredicate *)predicate kind] != FK_EVENTS)
        return @[];
    FKPredicate *p = (FKPredicate *)predicate;
    [self _ensureLoaded];
    NSMutableArray *found = [NSMutableArray array];
    @synchronized(self) {
        for (EKEvent *e in _eventsM) {
            if (![p _inCalendar:e.calendar])
                continue;
            if (e->_recurrenceID || !e.hasRecurrenceRules) {
                if ([p evaluateWithObject:e])
                    [found addObject:e];
                continue;
            }
            /* a series: its dates in the range, less those left out or changed */
            NSMutableArray *skip = [NSMutableArray arrayWithArray:e->_exdates];
            for (EKEvent *d in _eventsM)
                if (d->_recurrenceID && [d->_uid isEqualToString:e->_uid])
                    [skip addObject:d->_recurrenceID];
            NSTimeInterval length = [e.endDate timeIntervalSinceDate:e.startDate];
            NSMutableOrderedSet *starts = [NSMutableOrderedSet orderedSet];
            for (EKRecurrenceRule *r in e->_rulesM)
                [starts addObjectsFromArray:[r _startsFrom:e.startDate zone:e.allDay ? nil : e.timeZone length:length
                                                      from:p.start to:p.end]];
            for (NSDate *s in [starts.array sortedArrayUsingSelector:@selector(compare:)]) {
                BOOL skipped = NO;
                for (NSDate *x in skip)
                    if (fabs([x timeIntervalSinceDate:s]) < 1)
                        skipped = YES;
                if (!skipped)
                    [found addObject:[e _occurrenceAt:s]];
            }
        }
    }
    [found sortUsingComparator:^NSComparisonResult(EKEvent *a, EKEvent *b) { return [a compareStartDateWithEvent:b]; }];
    return found;
}

- (void)enumerateEventsMatchingPredicate:(NSPredicate *)predicate usingBlock:(EKEventSearchCallback)block
{
    BOOL stop = NO;
    for (EKEvent *e in [self eventsMatchingPredicate:predicate]) {
        block(e, &stop);
        if (stop)
            break;
    }
}

/* ---- reminders ---- */

- (FKPredicate *)_reminders:(int)kind from:(NSDate *)s to:(NSDate *)e calendars:(NSArray *)calendars
{
    FKPredicate *p = [FKPredicate new];
    p.kind = kind;
    p.start = s;
    p.end = e;
    p.calendars = calendars;
    return p;
}
- (NSPredicate *)predicateForRemindersInCalendars:(NSArray *)calendars
{
    return [self _reminders:FK_REMINDERS from:nil to:nil calendars:calendars];
}
- (NSPredicate *)predicateForIncompleteRemindersWithDueDateStarting:(NSDate *)s ending:(NSDate *)e calendars:(NSArray *)calendars
{
    return [self _reminders:FK_INCOMPLETE from:s to:e calendars:calendars];
}
- (NSPredicate *)predicateForCompletedRemindersWithCompletionDateStarting:(NSDate *)s ending:(NSDate *)e calendars:(NSArray *)calendars
{
    return [self _reminders:FK_COMPLETED from:s to:e calendars:calendars];
}
- (id)fetchRemindersMatchingPredicate:(NSPredicate *)predicate completion:(void (^)(NSArray<EKReminder *> *))completion
{
    NSObject *token = [NSObject new];
    __weak NSObject *weakToken = token;
    NSMutableArray *found = [NSMutableArray array];
    if ([predicate isKindOfClass:[FKPredicate class]] && [(FKPredicate *)predicate kind] != FK_EVENTS) {
        [self _ensureLoaded];
        @synchronized(self) {
            for (EKReminder *r in _remindersM)
                if ([predicate evaluateWithObject:r])
                    [found addObject:r];
        }
    }
    NSMutableSet *cancelled = objc_getAssociatedObject(self, @selector(cancelFetchRequest:));
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL gone = NO;
        @synchronized(self) {
            gone = weakToken && [cancelled containsObject:[NSValue valueWithNonretainedObject:weakToken]];
        }
        if (completion && !gone)
            completion(found);
    });
    return token;
}
- (void)cancelFetchRequest:(id)fetchIdentifier
{
    @synchronized(self) {
        NSMutableSet *cancelled = objc_getAssociatedObject(self, @selector(cancelFetchRequest:));
        if (!cancelled) {
            cancelled = [NSMutableSet set];
            objc_setAssociatedObject(self, @selector(cancelFetchRequest:), cancelled, OBJC_ASSOCIATION_RETAIN);
        }
        if (fetchIdentifier)
            [cancelled addObject:[NSValue valueWithNonretainedObject:fetchIdentifier]];
    }
}

static BOOL fk_edit_list(EKCalendar *list, NSError **error, void (^block)(FKComp *file))
{
    FKComp *file = fk_read(list->_file);
    if (!file) {
        file = fk_new_calendar(@"-//freemac//Nudge//EN");
        [file add:@"X-WR-CALNAME" params:nil value:fk_escape(list.title ?: @"Reminders")];
        [file add:@"X-FREEMAC-COLOR" params:nil value:fk_nearest_name(list->_hex)];
        [file add:@"X-FREEMAC-ORDER" params:nil value:[NSString stringWithFormat:@"%ld", (long)list->_order]];
        if (list->_mark.length)
            [file add:@"X-FREEMAC-SOURCE" params:nil value:list->_mark];
    }
    block(file);
    return fk_write(list->_file, file, error);
}

- (BOOL)saveReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error
{
    if (!fk_allowed(EKEntityTypeReminder))
        return fk_fail(error, EKErrorEventStoreNotAuthorized, @"This app hasn't been allowed to use the reminders.");
    EKCalendar *list = reminder.calendar;
    if (!list)
        return fk_fail(error, EKErrorNoCalendar, @"No list has been set.");
    if (!(list->_mask & EKEntityMaskReminder) || !list->_file)
        return fk_fail(error, EKErrorCalendarDoesNotAllowReminders, @"That calendar doesn't hold reminders.");
    if (reminder.hasRecurrenceRules && !reminder.dueDateComponents)
        return fk_fail(error, EKErrorRecurringReminderRequiresDueDate, @"A repeating reminder needs a due date.");
    FKComp *comp = [reminder _component];
    NSString *uid = reminder->_uid;
    NSString *oldList = reminder->_listID;
    EKCalendar *was = oldList && ![oldList isEqualToString:list->_identifier] ? [self calendarWithIdentifier:oldList] : nil;
    BOOL ok = [self _apply:^BOOL(NSError **err) {
        if (was && was->_file && !fk_edit_list(was, err, ^(FKComp *file) {
                [file.subs removeObjectsAtIndexes:[file.subs indexesOfObjectsPassingTest:^BOOL(FKComp *c, NSUInteger i, BOOL *stop) {
                    return [[c text:@"UID"] isEqualToString:uid];
                }]];
            }))
            return NO;
        return fk_edit_list(list, err, ^(FKComp *file) {
            NSUInteger i = fk_index_of(file.subs, uid, nil);
            if (i != NSNotFound)
                file.subs[i] = comp;
            else
                [file.subs addObject:comp];
        });
    } commit:commit error:error];
    if (ok && commit) {
        reminder->_comp = comp;
        reminder->_listID = list->_identifier;
        reminder->_loaded = [reminder _fingerprint];
    }
    return ok;
}

- (BOOL)removeReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error
{
    if (!fk_allowed(EKEntityTypeReminder))
        return fk_fail(error, EKErrorEventStoreNotAuthorized, @"This app hasn't been allowed to use the reminders.");
    EKCalendar *list = reminder.calendar;
    if (!list->_file || !reminder->_comp)
        return YES;
    NSString *uid = reminder->_uid;
    return [self _apply:^BOOL(NSError **err) {
        return fk_edit_list(list, err, ^(FKComp *file) {
            [file.subs removeObjectsAtIndexes:[file.subs indexesOfObjectsPassingTest:^BOOL(FKComp *c, NSUInteger i, BOOL *stop) {
                return [[c text:@"UID"] isEqualToString:uid];
            }]];
        });
    } commit:commit error:error];
}

/* ---- calendars ---- */

- (BOOL)saveCalendar:(EKCalendar *)calendar commit:(BOOL)commit error:(NSError **)error
{
    BOOL reminders = (calendar->_mask & EKEntityMaskReminder) != 0;
    if (!fk_allowed(reminders ? EKEntityTypeReminder : EKEntityTypeEvent))
        return fk_fail(error, EKErrorEventStoreNotAuthorized, @"This app hasn't been allowed to use the calendar.");
    if (!reminders) {
        if (calendar->_new)
            return fk_fail(error, EKErrorSourceDoesNotAllowCalendarAddDelete,
                           @"freemac's Calendar keeps one calendar on this computer; new calendars come from online accounts.");
        return YES;    /* its name and colour are its source's */
    }
    if (calendar->_new && !calendar->_file) {
        NSString *ident = [[[NSUUID UUID] UUIDString] substringToIndex:12].lowercaseString;
        ident = [ident stringByReplacingOccurrencesOfString:@"-" withString:@""];
        calendar->_identifier = ident;
        calendar->_file = [fk_reminders_dir() stringByAppendingPathComponent:[ident stringByAppendingPathExtension:@"ics"]];
        calendar->_order = (NSInteger)[self calendarsForEntityType:EKEntityTypeReminder].count;
    }
    NSString *title = calendar.title ?: @"Reminders";
    NSString *color = fk_nearest_name(calendar->_hex);
    BOOL ok = [self _apply:^BOOL(NSError **err) {
        return fk_edit_list(calendar, err, ^(FKComp *file) {
            [file removeProps:[NSSet setWithObjects:@"X-WR-CALNAME", @"X-FREEMAC-COLOR", nil]];
            [file add:@"X-WR-CALNAME" params:nil value:fk_escape(title)];
            [file add:@"X-FREEMAC-COLOR" params:nil value:color];
        });
    } commit:commit error:error];
    if (ok)
        calendar->_new = NO;
    return ok;
}

- (BOOL)removeCalendar:(EKCalendar *)calendar commit:(BOOL)commit error:(NSError **)error
{
    if (!(calendar->_mask & EKEntityMaskReminder) || !calendar->_file)
        return fk_fail(error, EKErrorSourceDoesNotAllowCalendarAddDelete, @"This calendar can't be removed here.");
    NSString *path = calendar->_file;
    return [self _apply:^BOOL(NSError **err) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return YES;
    } commit:commit error:error];
}

- (void)_changed { fk_post_changed(self); }

- (void)dealloc
{
    @synchronized([EKEventStore class]) {
        [fk_stores removeObject:self];
    }
}
@end
