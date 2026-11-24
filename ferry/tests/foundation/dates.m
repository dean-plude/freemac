/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSTimeZone, NSLocale and NSDateFormatter: zones from the system's time
 * zone database (offsets, abbreviations, daylight saving time, transitions,
 * the rule for years past the database's list), zones from offsets and
 * abbreviations, the system zone ($TZ is Europe/Paris for this test);
 * locale identifiers; writing dates with Unicode patterns and the standard
 * styles; reading them back, with zones, two-digit years, missing fields,
 * leniency and mistakes; templates; and changed symbols. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static NSDate *at(double t) { return [NSDate dateWithTimeIntervalSince1970:t]; }

static NSDateFormatter *formatter(NSString *format, NSString *zone)
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [f setTimeZone:[NSTimeZone timeZoneWithName:zone]];
    [f setDateFormat:format];
    return f;
}

static NSString *utc(NSDate *d)
{
    if (!d)
        return @"(nil)";
    return [formatter(@"uuuu-MM-dd HH:mm:ss.SSS 'UTC'", @"UTC") stringFromDate:d];
}

static void zone(NSString *name, double t)
{
    NSTimeZone *z = [NSTimeZone timeZoneWithName:name];
    NSDate *d = at(t);
    printf("  %s at %s: %ld %s%s, daylight offset %g\n", [[z name] UTF8String], [utc(d) UTF8String],
           (long)[z secondsFromGMTForDate:d], [[z abbreviationForDate:d] UTF8String],
           [z isDaylightSavingTimeForDate:d] ? " (daylight)" : "", [z daylightSavingTimeOffsetForDate:d]);
}

static void reads(NSDateFormatter *f, NSString *s)
{
    printf("  %-34s %-36s -> %s\n", [[f dateFormat] UTF8String], [[NSString stringWithFormat:@"\"%@\"", s] UTF8String],
           [utc([f dateFromString:s]) UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        printf("time zones\n");
        zone(@"America/New_York", 1704067200);   /* 2024-01-01 */
        zone(@"America/New_York", 1720105509);   /* 2024-07-04 */
        zone(@"America/New_York", 2224108800);   /* 2040-06-24: from the rule after the list */
        zone(@"America/New_York", -5364662400);  /* 1800: local mean time */
        zone(@"Europe/Paris", 1720105509);
        zone(@"Asia/Kolkata", 1720105509);
        zone(@"Australia/Sydney", 1704067200);
        zone(@"Australia/Sydney", 1720105509);
        NSTimeZone *ny = [NSTimeZone timeZoneWithName:@"America/New_York"];
        printf("  next changes in New York after 2024-01-01: %s, after 2039-12-01: %s\n",
               [utc([ny nextDaylightSavingTimeTransitionAfterDate:at(1704067200)]) UTF8String],
               [utc([ny nextDaylightSavingTimeTransitionAfterDate:at(2206310400)]) UTF8String]);
        NSTimeZone *fixed = [NSTimeZone timeZoneForSecondsFromGMT:19800], *gmt = [NSTimeZone timeZoneForSecondsFromGMT:0];
        printf("  from offsets: %s %s %ld, %s %s; out of range: %s\n", [[fixed name] UTF8String],
               [[fixed abbreviation] UTF8String], (long)[fixed secondsFromGMT], [[gmt name] UTF8String],
               [[gmt abbreviation] UTF8String],
               [NSTimeZone timeZoneForSecondsFromGMT:20 * 3600] ? "a zone" : "nil");
        printf("  from abbreviations: PST is %s, CEST is %s, UTC is %s, XYZ is %s\n",
               [[[NSTimeZone timeZoneWithAbbreviation:@"PST"] name] UTF8String],
               [[[NSTimeZone timeZoneWithAbbreviation:@"CEST"] name] UTF8String],
               [[[NSTimeZone timeZoneWithAbbreviation:@"UTC"] name] UTF8String],
               [NSTimeZone timeZoneWithAbbreviation:@"XYZ"] ? "a zone" : "nil");
        printf("  unknown: %s, escaping: %s, equal: %d %d, known names include Europe/Paris: %d\n",
               [NSTimeZone timeZoneWithName:@"Mars/Olympus_Mons"] ? "a zone" : "nil",
               [NSTimeZone timeZoneWithName:@"../../etc/passwd"] ? "a zone" : "nil",
               [ny isEqualToTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"]], [ny isEqual:fixed],
               [[NSTimeZone knownTimeZoneNames] containsObject:@"Europe/Paris"]);
        printf("  system: %s, default: %s\n", [[[NSTimeZone systemTimeZone] name] UTF8String],
               [[[NSTimeZone defaultTimeZone] name] UTF8String]);

        printf("locales\n");
        for (NSString *ident in @[ @"en_US_POSIX", @"en-GB", @"zh_Hant_TW", @"de", @"sr-Latn" ]) {
            NSLocale *l = [NSLocale localeWithLocaleIdentifier:ident];
            printf("  %s: language %s, script %s, country %s, variant %s; canonical %s; metric %d\n",
                   [[l localeIdentifier] UTF8String], [[l languageCode] UTF8String] ?: "-",
                   [[l scriptCode] UTF8String] ?: "-", [[l countryCode] UTF8String] ?: "-",
                   [[l variantCode] UTF8String] ?: "-",
                   [[NSLocale canonicalLocaleIdentifierFromString:ident] UTF8String], [l usesMetricSystem]);
        }
        printf("  current: %s\n", [[[NSLocale currentLocale] localeIdentifier] UTF8String]);

        printf("writing 2024-07-04 19:05:09.123 UTC\n");
        NSDate *when = at(1720119909.123);
        NSString *patterns[] = {
            @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", @"EEE, dd MMM yyyy HH:mm:ss Z", @"EEEE, MMMM d, y G",
            @"h:mm a, 'week' w 'of' Y, 'day' D, F'th' EEEEEE 'in' M", @"yy/M/d hh 'o''clock' a K k",
            @"QQQ QQQQ q LLLL LLL MMMMM EEEEE e c ccc", @"z zzzz v vvvv O OOOO", @"Z ZZZZ ZZZZZ X XX XXX x xxx",
            @"VV VVV VVVV", @"S SS SSS SSSS A", @"''y''", @"GGGG GGGGG u",
        };
        NSString *zones[] = {@"America/New_York", @"Europe/Paris", @"Asia/Kolkata", @"UTC"};
        for (unsigned i = 0; i < sizeof patterns / sizeof patterns[0]; i++) {
            BOOL zonal = [patterns[i] hasPrefix:@"z"] || [patterns[i] hasPrefix:@"Z"] || [patterns[i] hasPrefix:@"VV"];
            for (unsigned k = 0; k < (zonal ? 4 : 1); k++)
                printf("  %-50s %s\n", [patterns[i] UTF8String],
                       [[formatter(patterns[i], zones[k]) stringFromDate:when] UTF8String]);
        }
        printf("  long ago: %s\n", [[formatter(@"y G, u, MMM d", @"UTC") stringFromDate:at(-62167219200)] UTF8String]);
        printf("  week of 2024-12-30: %s\n",
               [[formatter(@"Y-'W'ww-e, y", @"UTC") stringFromDate:at(1735560000)] UTF8String]);
        printf("  in London in winter and summer: %s; %s\n",
               [[formatter(@"z zzzz", @"Europe/London") stringFromDate:at(1704067200)] UTF8String],
               [[formatter(@"z zzzz", @"Europe/London") stringFromDate:when] UTF8String]);

        printf("styles in New York\n");
        NSDateFormatter *styled = [[[NSDateFormatter alloc] init] autorelease];
        [styled setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        [styled setTimeZone:ny];
        const char *names[] = {"none", "short", "medium", "long", "full"};
        for (int d = 0; d <= 4; d++)
            for (int t = 0; t <= 4; t += (d == 0 || t == 0 || d == t) ? 1 : 4) {
                [styled setDateStyle:d];
                [styled setTimeStyle:t];
                printf("  %-6s %-6s %-40s %s\n", names[d], names[t],
                       [[NSString stringWithFormat:@"\"%@\"", [styled dateFormat]] UTF8String],
                       [[styled stringFromDate:when] UTF8String]);
            }
        printf("  localizedStringFromDate (Paris): %s\n",
               [[NSDateFormatter localizedStringFromDate:when dateStyle:NSDateFormatterMediumStyle
                                               timeStyle:NSDateFormatterShortStyle] UTF8String]);
        NSDateFormatter *empty = [[[NSDateFormatter alloc] init] autorelease];
        printf("  with no format: \"%s\"; nil date: %s\n", [[empty stringFromDate:when] UTF8String],
               [empty stringFromDate:nil] ? "a string" : "nil");

        printf("reading\n");
        reads(formatter(@"yyyy-MM-dd'T'HH:mm:ssZZZZZ", @"UTC"), @"2024-07-04T15:05:09-04:00");
        reads(formatter(@"yyyy-MM-dd'T'HH:mm:ssZZZZZ", @"UTC"), @"2024-07-04T19:05:09Z");
        reads(formatter(@"yyyy-MM-dd'T'HH:mm:ss.SSSXXX", @"UTC"), @"2024-07-04T21:05:09.123+02:00");
        reads(formatter(@"EEE, dd MMM yyyy HH:mm:ss Z", @"UTC"), @"Thu, 04 Jul 2024 19:05:09 +0000");
        reads(formatter(@"EEE, dd MMM yyyy HH:mm:ss zzz", @"UTC"), @"thu, 04 jul 2024 12:05:09 PDT");
        reads(formatter(@"MMMM d, y h:mm a zzzz", @"UTC"), @"July 4, 2024 3:05 PM Eastern Daylight Time");
        reads(formatter(@"MMMM d, y h:mm a zzzz", @"UTC"), @"January 4, 2024 3:05 PM Eastern Time");
        reads(formatter(@"yyyy-MM-dd HH:mm O", @"UTC"), @"2024-07-04 19:05 GMT+5:30");
        reads(formatter(@"yyyy-MM-dd HH:mm VV", @"UTC"), @"2024-07-04 21:05 Europe/Paris");
        reads(formatter(@"yyyy-MM-dd HH:mm", @"America/New_York"), @"2024-07-04 15:05");
        reads(formatter(@"yyyy-MM-dd HH:mm", @"America/New_York"), @"2024-01-04 15:05");
        reads(formatter(@"yyyyMMddHHmmss", @"UTC"), @"20240704190509");
        reads(formatter(@"M/d/yy", @"UTC"), @"6/1/45");
        reads(formatter(@"M/d/yy", @"UTC"), @"6/1/62");
        reads(formatter(@"M/d/yy", @"UTC"), @"6/1/1862");
        reads(formatter(@"HH:mm", @"UTC"), @"10:30");
        reads(formatter(@"h:mm a", @"UTC"), @"12:15 am");
        reads(formatter(@"h:mm a", @"UTC"), @"12:15 PM");
        reads(formatter(@"yyyy-DDD", @"UTC"), @"2024-186");
        reads(formatter(@"MMM yyyy", @"UTC"), @"Sep 2024");
        reads(formatter(@"MMM d, yyyy G", @"UTC"), @"Mar 15, 44 BC");
        reads(formatter(@"yyyy-MM-dd", @"UTC"), @"2024-02-30");
        reads(formatter(@"yyyy-MM-dd", @"UTC"), @"2024-13-01");
        reads(formatter(@"yyyy-MM-dd", @"UTC"), @"2024-07-04 ");
        reads(formatter(@"yyyy-MM-dd", @"UTC"), @"2024/07/04");
        reads(formatter(@"yyyy-MM-dd", @"UTC"), @"");
        reads(formatter(@"MMM d", @"UTC"), @"Smarch 4");
        NSDateFormatter *lenient = formatter(@"yyyy-MM-dd HH:mm", @"UTC");
        [lenient setLenient:YES];
        reads(lenient, @"2024-02-30 25:00");
        reads(lenient, @" 2024-07-04 19:05 ");
        NSDateFormatter *iso = formatter(@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", @"Asia/Kolkata");
        NSString *s = [iso stringFromDate:when];
        printf("  round trip: %s -> %s\n", [s UTF8String], [utc([iso dateFromString:s]) UTF8String]);
        NSDateFormatter *withDefault = formatter(@"HH:mm", @"UTC");
        [withDefault setDefaultDate:at(1720119909)];
        reads(withDefault, @"08:15");
        NSDateFormatter *start = formatter(@"yy-MM-dd", @"UTC");
        [start setTwoDigitStartDate:at(946684800)];   /* 2000 */
        reads(start, @"99-01-02");
        id obj = nil;
        NSRange r = NSMakeRange(6, 21);
        NSError *err = nil;
        BOOL ok = [formatter(@"yyyy-MM-dd", @"UTC") getObjectValue:&obj forString:@"Date: 2024-07-04, a Thursday"
                                                              range:&r
                                                              error:&err];
        printf("  part of a string: %d %s, range {%lu, %lu}\n", ok, [utc(obj) UTF8String], (unsigned long)r.location,
               (unsigned long)r.length);
        ok = [formatter(@"yyyy-MM-dd", @"UTC") getObjectValue:&obj forString:@"nope" range:NULL error:&err];
        printf("  a mistake: %d, %s %ld: %s\n", ok, [[err domain] UTF8String], (long)[err code],
               [[err localizedDescription] UTF8String]);

        printf("templates\n");
        for (NSString *t in @[ @"yMMMd", @"yMMMMd", @"yMd", @"MMMd", @"jm", @"Hm", @"jms", @"yMMMMEEEEd", @"MMMMy",
                               @"yMMMdjm", @"yMMMMdjmz", @"EEE", @"ms", @"MMdd" ])
            printf("  %-12s %s\n", [t UTF8String],
                   [[NSDateFormatter dateFormatFromTemplate:t options:0
                                                     locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]]
                       UTF8String]);
        [styled setLocalizedDateFormatFromTemplate:@"yMMMd"];
        printf("  set from yMMMd: %s -> %s\n", [[styled dateFormat] UTF8String], [[styled stringFromDate:when] UTF8String]);

        printf("symbols\n");
        NSDateFormatter *custom = formatter(@"EEEE d MMMM y, a", @"UTC");
        [custom setMonthSymbols:@[
            @"janvier", @"février", @"mars", @"avril", @"mai", @"juin", @"juillet", @"août", @"septembre", @"octobre",
            @"novembre", @"décembre"
        ]];
        [custom setWeekdaySymbols:@[ @"dimanche", @"lundi", @"mardi", @"mercredi", @"jeudi", @"vendredi", @"samedi" ]];
        [custom setPMSymbol:@"de l'après-midi"];
        printf("  %s\n", [[custom stringFromDate:when] UTF8String]);
        reads(custom, @"jeudi 4 juillet 2024, de l'après-midi");
        NSDateFormatter *copy = [[custom copy] autorelease];
        [custom setMonthSymbols:nil];
        printf("  the copy keeps them: %s; the first goes back: %s\n", [[copy stringFromDate:when] UTF8String],
               [[custom stringFromDate:when] UTF8String]);
        printf("  defaults: %s %s %s / %s %s / %s %s\n", [[[custom shortMonthSymbols] objectAtIndex:8] UTF8String],
               [[[custom veryShortWeekdaySymbols] objectAtIndex:0] UTF8String],
               [[[custom quarterSymbols] objectAtIndex:1] UTF8String], [[custom AMSymbol] UTF8String],
               [[[custom eraSymbols] objectAtIndex:1] UTF8String],
               [[[custom longEraSymbols] objectAtIndex:0] UTF8String], [custom isLenient] ? "lenient" : "strict");
    }
    return 0;
}
