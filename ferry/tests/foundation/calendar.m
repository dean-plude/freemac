/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSCalendar and NSDateComponents: splitting dates into components in a time
 * zone and building them back (week-based years, weekday ordinals, days of
 * the year), adding components with and without wrapping, the differences
 * between two dates, starts of days and other units across daylight saving
 * changes, ranges and ordinals of units, weeks in the Gregorian and ISO 8601
 * calendars, today and the weekend, comparing to a unit, and finding the next
 * date that matches components. $TZ is Europe/Paris for this test. Every date
 * is fixed, except those built from the start of today. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static NSDate *at(double t) { return [NSDate dateWithTimeIntervalSince1970:t]; }

static NSString *utc(NSDate *d)
{
    if (!d)
        return @"(nil)";
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [f setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [f setDateFormat:@"uuuu-MM-dd HH:mm:ss 'UTC'"];
    return [f stringFromDate:d];
}

static NSCalendar *gregorian(NSString *zone)
{
    NSCalendar *c = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
    [c setTimeZone:[NSTimeZone timeZoneWithName:zone]];
    [c setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    return c;
}

static void show(const char *what, NSDateComponents *c)
{
    printf("  %s:", what);
    const struct {
        const char *name;
        NSCalendarUnit unit;
    } units[] = {{"era", NSCalendarUnitEra},
                 {"year", NSCalendarUnitYear},
                 {"quarter", NSCalendarUnitQuarter},
                 {"month", NSCalendarUnitMonth},
                 {"day", NSCalendarUnitDay},
                 {"hour", NSCalendarUnitHour},
                 {"minute", NSCalendarUnitMinute},
                 {"second", NSCalendarUnitSecond},
                 {"nanosecond", NSCalendarUnitNanosecond},
                 {"weekday", NSCalendarUnitWeekday},
                 {"ordinal", NSCalendarUnitWeekdayOrdinal},
                 {"weekOfMonth", NSCalendarUnitWeekOfMonth},
                 {"weekOfYear", NSCalendarUnitWeekOfYear},
                 {"yearForWeekOfYear", NSCalendarUnitYearForWeekOfYear},
                 {"dayOfYear", NSCalendarUnitDayOfYear}};
    for (size_t i = 0; i < sizeof units / sizeof units[0]; i++) {
        NSInteger v = [c valueForComponent:units[i].unit];
        if (v != NSDateComponentUndefined)
            printf(" %s %ld", units[i].name, (long)v);
    }
    if ([c timeZone])
        printf(" zone %s", [[[c timeZone] name] UTF8String]);
    printf("\n");
}

static void range(NSCalendar *c, NSCalendarUnit small, NSCalendarUnit large, NSDate *d, const char *what)
{
    NSRange r = [c rangeOfUnit:small inUnit:large forDate:d];
    printf("  %s: %ld..%ld (ordinality %ld)\n", what, (long)r.location, (long)(r.location + r.length - 1),
           (long)[c ordinalityOfUnit:small inUnit:large forDate:d]);
}

static void unit_span(NSCalendar *c, NSCalendarUnit unit, NSDate *d, const char *what)
{
    NSDate *start = nil;
    NSTimeInterval len = 0;
    BOOL ok = [c rangeOfUnit:unit startDate:&start interval:&len forDate:d];
    printf("  %s: %s from %s for %gs\n", what, ok ? "yes" : "no", [utc(start) UTF8String], len);
}

int main(void)
{
    @autoreleasepool {
        NSCalendarUnit all = NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitQuarter | NSCalendarUnitMonth |
                             NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond |
                             NSCalendarUnitNanosecond | NSCalendarUnitWeekday | NSCalendarUnitWeekdayOrdinal |
                             NSCalendarUnitWeekOfMonth | NSCalendarUnitWeekOfYear |
                             NSCalendarUnitYearForWeekOfYear | NSCalendarUnitDayOfYear;
        NSCalendar *ny = gregorian(@"America/New_York");
        NSCalendar *paris = gregorian(@"Europe/Paris");
        NSCalendar *iso = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierISO8601] autorelease];
        [iso setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];

        printf("calendars\n");
        printf("  identifiers: %s, %s\n", [[ny calendarIdentifier] UTF8String], [[iso calendarIdentifier] UTF8String]);
        printf("  first weekday %ld, minimum days in first week %ld (en_US)\n", (long)[ny firstWeekday],
               (long)[ny minimumDaysInFirstWeek]);
        printf("  first weekday %ld, minimum days in first week %ld (ISO 8601)\n", (long)[iso firstWeekday],
               (long)[iso minimumDaysInFirstWeek]);
        NSCalendar *gb = gregorian(@"UTC");
        [gb setLocale:[NSLocale localeWithLocaleIdentifier:@"en_GB"]];
        printf("  first weekday %ld, minimum days in first week %ld (en_GB)\n", (long)[gb firstWeekday],
               (long)[gb minimumDaysInFirstWeek]);
        printf("  unknown identifier: %s\n",
               [[NSCalendar calendarWithIdentifier:@"klingon"] description] ? "a calendar" : "(nil)");
        NSCalendar *current = [NSCalendar currentCalendar];
        printf("  current: %s in %s\n", [[current calendarIdentifier] UTF8String],
               [[[current timeZone] name] UTF8String]);
        printf("  month symbols: %s ... %s, weekdays %s ... %s\n", [[[ny monthSymbols] objectAtIndex:0] UTF8String],
               [[[ny shortMonthSymbols] lastObject] UTF8String], [[[ny weekdaySymbols] objectAtIndex:0] UTF8String],
               [[[ny veryShortWeekdaySymbols] lastObject] UTF8String]);

        printf("components\n");
        NSDate *july = at(1720105509.25);   /* 2024-07-04 15:05:09.25 UTC */
        show("New York", [ny components:all fromDate:july]);
        show("Paris", [paris components:all fromDate:july]);
        show("in Tokyo", [ny componentsInTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Tokyo"] fromDate:july]);
        NSDate *newYear = at(1735689600);   /* 2025-01-01 00:00 UTC */
        show("1 January 2025, UTC (week 1 of 2025)", [gregorian(@"UTC") components:all fromDate:newYear]);
        show("29 December 2024, ISO 8601 (week 52 of 2024)",
             [iso components:NSCalendarUnitWeekOfYear | NSCalendarUnitYearForWeekOfYear | NSCalendarUnitWeekday
                    fromDate:at(1735430400)]);
        show("30 December 2024, ISO 8601 (week 1 of 2025)",
             [iso components:NSCalendarUnitWeekOfYear | NSCalendarUnitYearForWeekOfYear | NSCalendarUnitWeekday
                    fromDate:at(1735516800)]);
        show("1 January 2021, ISO 8601 (week 53 of 2020)",
             [iso components:NSCalendarUnitWeekOfYear | NSCalendarUnitYearForWeekOfYear fromDate:at(1609459200)]);
        show("before 1970", [gregorian(@"UTC") components:all fromDate:at(-1e9)]);
        show("1 BC", [gregorian(@"UTC") components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth |
                                                    NSCalendarUnitDay
                                          fromDate:at(-62135596800.0 - 86400)]);
        printf("  hour: %ld, weekday of 4 July 2024: %ld\n", (long)[ny component:NSCalendarUnitHour fromDate:july],
               (long)[ny component:NSCalendarUnitWeekday fromDate:july]);
        NSInteger era, year, month, day, hour, minute, second, nano;
        [ny getEra:&era year:&year month:&month day:&day fromDate:july];
        [ny getHour:&hour minute:&minute second:&second nanosecond:&nano fromDate:july];
        printf("  getters: era %ld %04ld-%02ld-%02ld %02ld:%02ld:%02ld + %ldns\n", (long)era, (long)year, (long)month,
               (long)day, (long)hour, (long)minute, (long)second, (long)nano);

        printf("dates from components\n");
        NSDateComponents *dc = [[[NSDateComponents alloc] init] autorelease];
        [dc setYear:2024];
        [dc setMonth:3];
        [dc setDay:10];
        [dc setHour:2];
        [dc setMinute:30];
        printf("  2024-03-10 02:30 in New York (skipped): %s\n", [utc([ny dateFromComponents:dc]) UTF8String]);
        [dc setMonth:11];
        [dc setDay:3];
        [dc setHour:1];
        printf("  2024-11-03 01:30 in New York (repeated): %s\n", [utc([ny dateFromComponents:dc]) UTF8String]);
        [dc setMonth:2];
        [dc setDay:30];
        [dc setHour:12];
        printf("  2024-02-30 12:30 (carries): %s\n", [utc([ny dateFromComponents:dc]) UTF8String]);
        [dc setMonth:14];
        [dc setDay:1];
        printf("  month 14 of 2024: %s\n", [utc([ny dateFromComponents:dc]) UTF8String]);
        [dc setTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Tokyo"]];
        printf("  with the components' own zone (Tokyo): %s\n", [utc([ny dateFromComponents:dc]) UTF8String]);
        NSDateComponents *wk = [[[NSDateComponents alloc] init] autorelease];
        [wk setYearForWeekOfYear:2025];
        [wk setWeekOfYear:1];
        [wk setWeekday:2];
        printf("  Monday of ISO week 1 of 2025: %s\n", [utc([iso dateFromComponents:wk]) UTF8String]);
        NSDateComponents *th = [[[NSDateComponents alloc] init] autorelease];
        [th setYear:2024];
        [th setMonth:11];
        [th setWeekday:5];
        [th setWeekdayOrdinal:4];
        printf("  fourth Thursday of November 2024: %s\n", [utc([gregorian(@"UTC") dateFromComponents:th]) UTF8String]);
        [th setMonth:5];
        [th setWeekday:2];
        [th setWeekdayOrdinal:-1];
        printf("  last Monday of May 2024: %s\n", [utc([gregorian(@"UTC") dateFromComponents:th]) UTF8String]);
        NSDateComponents *doy = [[[NSDateComponents alloc] init] autorelease];
        [doy setYear:2024];
        [doy setDayOfYear:60];
        printf("  day 60 of 2024: %s\n", [utc([gregorian(@"UTC") dateFromComponents:doy]) UTF8String]);
        printf("  nothing set: %s\n",
               [utc([gregorian(@"UTC") dateFromComponents:[[[NSDateComponents alloc] init] autorelease]]) UTF8String]);
        printf("  date with era 1, 2000-02-29 13:14:15: %s\n",
               [utc([gregorian(@"UTC") dateWithEra:1 year:2000 month:2 day:29 hour:13 minute:14 second:15 nanosecond:0])
                   UTF8String]);
        printf("  date of ISO week 53 of 2020, Friday: %s\n",
               [utc([iso dateWithEra:1 yearForWeekOfYear:2020 weekOfYear:53 weekday:6 hour:0 minute:0 second:0
                          nanosecond:0]) UTF8String]);

        printf("components objects\n");
        NSDateComponents *a = [[[NSDateComponents alloc] init] autorelease];
        [a setYear:2024];
        [a setMonth:2];
        [a setDay:29];
        NSDateComponents *b = [[a copy] autorelease];
        printf("  copy equal: %s, after a change: ", [a isEqual:b] ? "yes" : "no");
        [b setDay:30];
        printf("%s\n", [a isEqual:b] ? "yes" : "no");
        printf("  undefined: %s, isLeapMonth %s\n", [a hour] == NSDateComponentUndefined ? "yes" : "no",
               [a isLeapMonth] ? "yes" : "no");
        [a setCalendar:gregorian(@"UTC")];
        printf("  date: %s, valid %s; 30 February valid: ", [utc([a date]) UTF8String],
               [a isValidDateInCalendar:gregorian(@"UTC")] ? "yes" : "no");
        printf("%s\n", [b isValidDateInCalendar:gregorian(@"UTC")] ? "yes" : "no");
        [a setValue:7 forComponent:NSCalendarUnitHour];
        printf("  set by unit: hour %ld\n", (long)[a valueForComponent:NSCalendarUnitHour]);

        printf("adding\n");
        NSDate *jan31 = at(1706702400);   /* 2024-01-31 12:00 UTC */
        NSCalendar *u = gregorian(@"UTC");
        NSDateComponents *oneMonth = [[[NSDateComponents alloc] init] autorelease];
        [oneMonth setMonth:1];
        printf("  31 January 2024 + 1 month: %s\n", [utc([u dateByAddingComponents:oneMonth toDate:jan31 options:0])
                                                          UTF8String]);
        [oneMonth setMonth:13];
        printf("  + 13 months: %s\n", [utc([u dateByAddingComponents:oneMonth toDate:jan31 options:0]) UTF8String]);
        NSDate *feb29 = at(1709208000);   /* 2024-02-29 12:00 UTC */
        printf("  29 February 2024 + 1 year: %s, - 4 years: %s\n",
               [utc([u dateByAddingUnit:NSCalendarUnitYear value:1 toDate:feb29 options:0]) UTF8String],
               [utc([u dateByAddingUnit:NSCalendarUnitYear value:-4 toDate:feb29 options:0]) UTF8String]);
        printf("  + 1 day, + 2 weeks, + 1 quarter: %s, %s, %s\n",
               [utc([u dateByAddingUnit:NSCalendarUnitDay value:1 toDate:feb29 options:0]) UTF8String],
               [utc([u dateByAddingUnit:NSCalendarUnitWeekOfYear value:2 toDate:feb29 options:0]) UTF8String],
               [utc([u dateByAddingUnit:NSCalendarUnitQuarter value:1 toDate:feb29 options:0]) UTF8String]);
        NSDate *eve = at(1710014400);   /* 2024-03-09 15:00 New York, before the clocks go forward */
        printf("  New York, 9 March 15:00 + 1 day: %s; + 24 hours: %s\n",
               [utc([ny dateByAddingUnit:NSCalendarUnitDay value:1 toDate:eve options:0]) UTF8String],
               [utc([ny dateByAddingUnit:NSCalendarUnitHour value:24 toDate:eve options:0]) UTF8String]);
        NSDateComponents *mix = [[[NSDateComponents alloc] init] autorelease];
        [mix setDay:-1];
        [mix setHour:3];
        [mix setMinute:-90];
        printf("  - 1 day + 3 hours - 90 minutes: %s\n", [utc([u dateByAddingComponents:mix toDate:feb29 options:0])
                                                                 UTF8String]);
        NSDateComponents *wrap = [[[NSDateComponents alloc] init] autorelease];
        [wrap setHour:13];
        printf("  12:00 + 13 hours, wrapping: %s\n",
               [utc([u dateByAddingComponents:wrap toDate:feb29 options:NSCalendarWrapComponents]) UTF8String]);
        [wrap setHour:0];
        [wrap setDay:1];
        printf("  29 February + 1 day, wrapping: %s\n",
               [utc([u dateByAddingComponents:wrap toDate:feb29 options:NSCalendarWrapComponents]) UTF8String]);
        [wrap setDay:0];
        [wrap setMonth:11];
        printf("  February + 11 months, wrapping: %s\n",
               [utc([u dateByAddingComponents:wrap toDate:feb29 options:NSCalendarWrapComponents]) UTF8String]);

        printf("differences\n");
        NSDate *d1 = at(1704067200);    /* 2024-01-01 00:00 UTC */
        NSDate *d2 = at(1735734645);    /* 2025-01-01 12:30:45 UTC */
        show("2024-01-01 to 2025-01-01 12:30:45",
             [u components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour |
                           NSCalendarUnitMinute | NSCalendarUnitSecond
                  fromDate:d1
                    toDate:d2
                   options:0]);
        show("in days", [u components:NSCalendarUnitDay fromDate:d1 toDate:d2 options:0]);
        show("in weeks and days", [u components:NSCalendarUnitWeekOfYear | NSCalendarUnitDay fromDate:d1 toDate:d2
                                        options:0]);
        show("backwards", [u components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:d2 toDate:d1 options:0]);
        show("31 January to 29 February",
             [u components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:jan31 toDate:feb29 options:0]);
        show("in hours", [u components:NSCalendarUnitHour fromDate:d1 toDate:d2 options:0]);
        show("across the change in New York",
             [ny components:NSCalendarUnitDay | NSCalendarUnitHour
                   fromDate:eve
                     toDate:[ny dateByAddingUnit:NSCalendarUnitDay value:1 toDate:eve options:0]
                    options:0]);
        NSDateComponents *from = [[[NSDateComponents alloc] init] autorelease];
        [from setYear:2020];
        [from setMonth:5];
        [from setDay:15];
        NSDateComponents *to = [[[NSDateComponents alloc] init] autorelease];
        [to setYear:2024];
        [to setMonth:3];
        [to setDay:1];
        show("from components to components", [u components:NSCalendarUnitYear | NSCalendarUnitMonth |
                                                            NSCalendarUnitDay
                                              fromDateComponents:from
                                                toDateComponents:to
                                                         options:0]);

        printf("starts and ranges\n");
        printf("  start of 10 March 2024 in New York: %s\n",
               [utc([ny startOfDayForDate:at(1710090000)]) UTF8String]);
        NSCalendar *havana = gregorian(@"America/Havana");   /* the clocks went forward at midnight */
        printf("  start of 10 March 2024 in Havana: %s\n",
               [utc([havana startOfDayForDate:at(1710090000)]) UTF8String]);
        unit_span(ny, NSCalendarUnitDay, at(1710090000), "the day of 10 March 2024 in New York");
        unit_span(ny, NSCalendarUnitDay, at(1730653200), "the day of 3 November 2024 in New York");
        unit_span(u, NSCalendarUnitMonth, feb29, "February 2024");
        unit_span(u, NSCalendarUnitYear, feb29, "2024");
        unit_span(u, NSCalendarUnitWeekOfYear, feb29, "the week of 29 February 2024 (en_US)");
        unit_span(iso, NSCalendarUnitWeekOfYear, feb29, "the week of 29 February 2024 (ISO 8601)");
        unit_span(u, NSCalendarUnitHour, at(1709210096), "the hour");
        range(u, NSCalendarUnitDay, NSCalendarUnitMonth, feb29, "days in February 2024");
        range(u, NSCalendarUnitDay, NSCalendarUnitMonth, at(1675166400), "days in January 2023");
        range(u, NSCalendarUnitDay, NSCalendarUnitYear, feb29, "days in 2024");
        range(u, NSCalendarUnitMonth, NSCalendarUnitYear, feb29, "months in the year");
        range(u, NSCalendarUnitHour, NSCalendarUnitDay, feb29, "hours in the day");
        range(u, NSCalendarUnitWeekday, NSCalendarUnitWeekOfYear, feb29, "weekdays in the week");
        range(u, NSCalendarUnitWeekOfMonth, NSCalendarUnitMonth, feb29, "weeks in February 2024");
        range(u, NSCalendarUnitWeekOfYear, NSCalendarUnitYear, feb29, "weeks in 2024 (en_US)");
        range(iso, NSCalendarUnitWeekOfYear, NSCalendarUnitYear, at(1593561600), "weeks in 2020 (ISO 8601, 1 July)");
        range(iso, NSCalendarUnitWeekOfYear, NSCalendarUnitYearForWeekOfYear, at(1609459200),
              "weeks in week-based year 2020 (ISO 8601, 1 January 2021)");
        range(u, NSCalendarUnitQuarter, NSCalendarUnitYear, feb29, "quarters");
        NSRange r = [u minimumRangeOfUnit:NSCalendarUnitDay];
        NSRange m = [u maximumRangeOfUnit:NSCalendarUnitDay];
        printf("  day ranges: minimum %ld..%ld, maximum %ld..%ld\n", (long)r.location, (long)NSMaxRange(r) - 1,
               (long)m.location, (long)NSMaxRange(m) - 1);
        m = [u maximumRangeOfUnit:NSCalendarUnitWeekOfYear];
        printf("  weeks of the year at most: %ld..%ld\n", (long)m.location, (long)NSMaxRange(m) - 1);

        printf("days\n");
        NSDate *today = [u startOfDayForDate:[NSDate date]];
        NSCalendar *here = [NSCalendar currentCalendar];
        NSDate *localToday = [here startOfDayForDate:[NSDate date]];
        printf("  today: %s, yesterday: %s, tomorrow: %s\n",
               [here isDateInToday:[localToday dateByAddingTimeInterval:1]] ? "yes" : "no",
               [here isDateInYesterday:[localToday dateByAddingTimeInterval:-1]] ? "yes" : "no",
               [here isDateInTomorrow:[localToday dateByAddingTimeInterval:86400 * 1.5]] ? "yes" : "no");
        printf("  yesterday is today: %s\n", [here isDateInToday:[localToday dateByAddingTimeInterval:-1]] ? "yes" : "no");
        (void)today;
        printf("  same day: %s; across midnight: %s\n",
               [u isDate:feb29 inSameDayAsDate:[feb29 dateByAddingTimeInterval:3600]] ? "yes" : "no",
               [u isDate:feb29 inSameDayAsDate:[feb29 dateByAddingTimeInterval:43200]] ? "yes" : "no");
        NSDate *sat = at(1709381000);   /* Saturday 2 March 2024 */
        printf("  Saturday weekend: %s, Thursday weekend: %s\n", [u isDateInWeekend:sat] ? "yes" : "no",
               [u isDateInWeekend:feb29] ? "yes" : "no");
        NSDate *ws = nil;
        NSTimeInterval wl = 0;
        BOOL found = [u rangeOfWeekendStartDate:&ws interval:&wl containingDate:sat];
        printf("  the weekend: %s from %s for %gs\n", found ? "yes" : "no", [utc(ws) UTF8String], wl);
        found = [u nextWeekendStartDate:&ws interval:&wl options:0 afterDate:feb29];
        printf("  next weekend: %s from %s for %gs\n", found ? "yes" : "no", [utc(ws) UTF8String], wl);
        printf("  compare to the month: %ld, to the day: %ld; equal to the year: %s\n",
               (long)[u compareDate:feb29 toDate:jan31 toUnitGranularity:NSCalendarUnitMonth],
               (long)[u compareDate:feb29 toDate:[feb29 dateByAddingTimeInterval:-3600]
                    toUnitGranularity:NSCalendarUnitDay],
               [u isDate:feb29 equalToDate:jan31 toUnitGranularity:NSCalendarUnitYear] ? "yes" : "no");

        printf("matching\n");
        NSDateComponents *nine = [[[NSDateComponents alloc] init] autorelease];
        [nine setHour:9];
        printf("  next 09:00 after 29 February 12:00: %s\n",
               [utc([u nextDateAfterDate:feb29 matchingComponents:nine options:NSCalendarMatchNextTime]) UTF8String]);
        printf("  previous 09:00: %s\n",
               [utc([u nextDateAfterDate:feb29
                       matchingComponents:nine
                                  options:NSCalendarMatchNextTime | NSCalendarSearchBackwards]) UTF8String]);
        NSDateComponents *the31st = [[[NSDateComponents alloc] init] autorelease];
        [the31st setDay:31];
        printf("  next 31st: %s\n", [utc([u nextDateAfterDate:feb29 matchingComponents:the31st
                                                       options:NSCalendarMatchStrictly]) UTF8String]);
        NSDateComponents *leap = [[[NSDateComponents alloc] init] autorelease];
        [leap setMonth:2];
        [leap setDay:29];
        printf("  next 29 February: %s\n", [utc([u nextDateAfterDate:feb29 matchingComponents:leap
                                                         options:NSCalendarMatchStrictly]) UTF8String]);
        printf("  next 29 February, previous time preserved: %s\n",
               [utc([u nextDateAfterDate:feb29 matchingComponents:leap
                                 options:NSCalendarMatchPreviousTimePreservingSmallerUnits]) UTF8String]);
        NSDateComponents *fri13 = [[[NSDateComponents alloc] init] autorelease];
        [fri13 setDay:13];
        [fri13 setWeekday:6];
        printf("  next Friday the 13th: %s\n", [utc([u nextDateAfterDate:feb29 matchingComponents:fri13
                                                             options:NSCalendarMatchStrictly]) UTF8String]);
        NSDateComponents *skipped = [[[NSDateComponents alloc] init] autorelease];
        [skipped setHour:2];
        [skipped setMinute:30];
        printf("  next 02:30 in New York after 9 March: %s (next time), %s (preserving smaller units)\n",
               [utc([ny nextDateAfterDate:eve matchingComponents:skipped options:NSCalendarMatchNextTime])
                   UTF8String],
               [utc([ny nextDateAfterDate:eve matchingComponents:skipped
                                  options:NSCalendarMatchNextTimePreservingSmallerUnits]) UTF8String]);
        printf("  matches: %s, %s\n", [u date:feb29 matchesComponents:leap] ? "yes" : "no",
               [u date:jan31 matchesComponents:leap] ? "yes" : "no");
        __block int count = 0;
        NSDateComponents *first = [[[NSDateComponents alloc] init] autorelease];
        [first setDay:1];
        printf("  the first days of months after 29 February 2024:");
        [u enumerateDatesStartingAfterDate:feb29
                        matchingComponents:first
                                   options:NSCalendarMatchStrictly
                                usingBlock:^(NSDate *d, BOOL exact, BOOL *stop) {
                                    printf(" %s", [[utc(d) substringToIndex:10] UTF8String]);
                                    if (++count == 4)
                                        *stop = YES;
                                }];
        printf("\n");
        printf("  set hour 18:15:00: %s\n", [utc([u dateBySettingHour:18 minute:15 second:0 ofDate:feb29
                                                             options:NSCalendarMatchNextTime]) UTF8String]);
        printf("  set the day to 15: %s\n", [utc([u dateBySettingUnit:NSCalendarUnitDay value:15 ofDate:feb29
                                                             options:NSCalendarMatchNextTime]) UTF8String]);
        printf("  set the month to 6: %s\n", [utc([u dateBySettingUnit:NSCalendarUnitMonth value:6 ofDate:feb29
                                                              options:NSCalendarMatchNextTime]) UTF8String]);
        printf("  set the year to 2030: %s, to 2000: %s\n",
               [utc([u dateBySettingUnit:NSCalendarUnitYear value:2030 ofDate:feb29 options:0]) UTF8String],
               [utc([u dateBySettingUnit:NSCalendarUnitYear value:2000 ofDate:feb29 options:0]) UTF8String]);
    }
    return 0;
}
