/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSISO8601DateFormatter (each format option, zones, week and ordinal
 * dates, reading strings back and refusing ones in another shape), relative
 * date formatting in NSDateFormatter ("Today", "Yesterday", "Tomorrow"),
 * NSDateFormatter's calendar, and NSDateComponentsFormatter's styles and
 * zero behaviours. $TZ is Europe/Paris for this test. */
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
    [f setDateFormat:@"uuuu-MM-dd HH:mm:ss.SSS 'UTC'"];
    return [f stringFromDate:d];
}

static void writes(const char *what, NSISO8601DateFormatOptions o, NSTimeZone *z, NSDate *d)
{
    printf("  %-34s %s\n", what, [[NSISO8601DateFormatter stringFromDate:d timeZone:z formatOptions:o] UTF8String]);
}

static void reads(NSISO8601DateFormatter *f, NSString *s)
{
    printf("    \"%s\" -> %s\n", [s UTF8String], [utc([f dateFromString:s]) UTF8String]);
}

static void interval(NSDateComponentsFormatter *f, double t)
{
    NSString *s = [f stringFromTimeInterval:t];
    printf("    %g -> \"%s\"\n", t, s ? [s UTF8String] : "(nil)");
}

int main(void)
{
    @autoreleasepool {
        NSDate *july = at(1720105509.789);   /* 2024-07-04 15:05:09.789 UTC */
        NSTimeZone *gmt = [NSTimeZone timeZoneForSecondsFromGMT:0];
        NSTimeZone *paris = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
        NSTimeZone *ny = [NSTimeZone timeZoneWithName:@"America/New_York"];
        NSTimeZone *kolkata = [NSTimeZone timeZoneWithName:@"Asia/Kolkata"];

        printf("writing\n");
        NSISO8601DateFormatter *plain = [[[NSISO8601DateFormatter alloc] init] autorelease];
        printf("  defaults: options %#lx, zone %s: %s\n", (unsigned long)[plain formatOptions],
               [[[plain timeZone] name] UTF8String], [[plain stringFromDate:july] UTF8String]);
        writes("internet date and time, Paris", NSISO8601DateFormatWithInternetDateTime, paris, july);
        writes("internet date and time, New York", NSISO8601DateFormatWithInternetDateTime, ny, july);
        writes("internet date and time, Kolkata", NSISO8601DateFormatWithInternetDateTime, kolkata, july);
        writes("with fractional seconds",
               NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds, gmt, july);
        writes("no colon in the zone", NSISO8601DateFormatWithInternetDateTime &
                                           ~NSISO8601DateFormatWithColonSeparatorInTimeZone, ny, july);
        writes("basic format", NSISO8601DateFormatWithYear | NSISO8601DateFormatWithMonth | NSISO8601DateFormatWithDay |
                                   NSISO8601DateFormatWithTime | NSISO8601DateFormatWithTimeZone, paris, july);
        writes("space between date and time",
               NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithSpaceBetweenDateAndTime, gmt, july);
        writes("full date", NSISO8601DateFormatWithFullDate, gmt, july);
        writes("full time", NSISO8601DateFormatWithFullTime, ny, july);
        writes("time only", NSISO8601DateFormatWithTime | NSISO8601DateFormatWithColonSeparatorInTime, gmt, july);
        writes("year and month", NSISO8601DateFormatWithYear | NSISO8601DateFormatWithMonth |
                                     NSISO8601DateFormatWithDashSeparatorInDate, gmt, july);
        writes("ordinal date", NSISO8601DateFormatWithYear | NSISO8601DateFormatWithDay |
                                   NSISO8601DateFormatWithDashSeparatorInDate, gmt, july);
        NSISO8601DateFormatOptions week = NSISO8601DateFormatWithYear | NSISO8601DateFormatWithWeekOfYear |
                                          NSISO8601DateFormatWithDay | NSISO8601DateFormatWithDashSeparatorInDate;
        writes("week date", week, gmt, july);
        writes("week date, 29 December 2024", week, gmt, at(1735430400));
        writes("week date, 30 December 2024", week, gmt, at(1735516800));
        writes("week date, 1 January 2021", week, gmt, at(1609459200));
        writes("week date, basic", week & ~NSISO8601DateFormatWithDashSeparatorInDate, gmt, july);
        writes("before 1970", NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds,
               gmt, at(-1e9 - 0.25));
        writes("no options", 0, gmt, july);
        printf("  nil date: %s\n", [plain stringFromDate:nil] ? "a string" : "(nil)");

        printf("reading\n");
        printf("  internet date and time\n");
        reads(plain, @"2024-07-04T15:05:09Z");
        reads(plain, @"2024-07-04T17:05:09+02:00");
        reads(plain, @"2024-07-04T10:05:09-0500");
        reads(plain, @"2024-07-04T20:35:09+05:30");
        reads(plain, @"2024-07-04T15:05:09.789Z");
        reads(plain, @"2024-07-04 15:05:09Z");
        reads(plain, @"2024-07-04T15:05:09");
        reads(plain, @"2024-07-04");
        reads(plain, @"20240704T150509Z");
        reads(plain, @"2024-13-04T15:05:09Z");
        reads(plain, @"2024-07-04T15:05:09Zjunk");
        NSISO8601DateFormatter *frac = [[[NSISO8601DateFormatter alloc] init] autorelease];
        [frac setFormatOptions:NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds];
        printf("  with fractional seconds\n");
        reads(frac, @"2024-07-04T15:05:09.789Z");
        reads(frac, @"2024-07-04T15:05:09.5Z");
        reads(frac, @"2024-07-04T15:05:09Z");
        NSISO8601DateFormatter *local = [[[NSISO8601DateFormatter alloc] init] autorelease];
        [local setFormatOptions:NSISO8601DateFormatWithFullDate | NSISO8601DateFormatWithTime |
                                NSISO8601DateFormatWithColonSeparatorInTime];
        [local setTimeZone:ny];
        printf("  no zone in the string, read in New York\n");
        reads(local, @"2024-07-04T11:05:09");
        reads(local, @"2024-01-15T08:00:00");
        reads(local, @"2024-07-04T11:05:09Z");
        NSISO8601DateFormatter *wk = [[[NSISO8601DateFormatter alloc] init] autorelease];
        [wk setFormatOptions:week];
        printf("  week dates\n");
        reads(wk, @"2024-W27-4");
        reads(wk, @"2020-W53-5");
        reads(wk, @"2025-W01-1");
        NSISO8601DateFormatter *ord = [[[NSISO8601DateFormatter alloc] init] autorelease];
        [ord setFormatOptions:NSISO8601DateFormatWithYear | NSISO8601DateFormatWithDay |
                              NSISO8601DateFormatWithDashSeparatorInDate];
        printf("  ordinal dates\n");
        reads(ord, @"2024-186");
        reads(ord, @"2024-060");
        NSISO8601DateFormatter *timeOnly = [[[NSISO8601DateFormatter alloc] init] autorelease];
        [timeOnly setFormatOptions:NSISO8601DateFormatWithFullTime];
        printf("  a time alone\n");
        reads(timeOnly, @"12:30:00Z");
        NSISO8601DateFormatter *copy = [[plain copy] autorelease];
        printf("  a copy: %s\n", [[copy stringFromDate:july] UTF8String]);
        NSString *round = [frac stringFromDate:july];
        printf("  round trip: %s -> %s\n", [round UTF8String], [utc([frac dateFromString:round]) UTF8String]);

        printf("relative dates\n");
        NSDateFormatter *rel = [[[NSDateFormatter alloc] init] autorelease];
        [rel setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        [rel setTimeZone:ny];
        NSCalendar *cal = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
        [cal setTimeZone:ny];
        NSDate *today = [cal startOfDayForDate:[NSDate date]];
        NSDate *noon = [cal dateBySettingHour:12 minute:0 second:0 ofDate:today options:0];
        NSDate *yesterday = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:noon options:0];
        NSDate *tomorrow = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:noon options:0];
        NSDate *later = [cal dateByAddingUnit:NSCalendarUnitDay value:3 toDate:noon options:0];
        [rel setDoesRelativeDateFormatting:YES];
        [rel setDateStyle:NSDateFormatterMediumStyle];
        printf("  medium date: %s, %s, %s, %s\n", [[rel stringFromDate:yesterday] UTF8String],
               [[rel stringFromDate:noon] UTF8String], [[rel stringFromDate:tomorrow] UTF8String],
               [[rel stringFromDate:later] isEqualToString:[NSDateFormatter localizedStringFromDate:later
                                                                                          dateStyle:NSDateFormatterMediumStyle
                                                                                          timeStyle:NSDateFormatterNoStyle]]
                   ? "(a date three days on, as usual)"
                   : "(a date three days on, changed)");
        printf("  first second of today: %s, last second of yesterday: %s\n",
               [[rel stringFromDate:[today dateByAddingTimeInterval:1]] UTF8String],
               [[rel stringFromDate:[today dateByAddingTimeInterval:-1]] UTF8String]);
        [rel setTimeStyle:NSDateFormatterShortStyle];
        printf("  with a short time: %s, %s\n", [[rel stringFromDate:noon] UTF8String],
               [[rel stringFromDate:tomorrow] UTF8String]);
        printf("  read back: %s\n",
               [[rel dateFromString:@"Yesterday at 12:00 PM"] isEqualToDate:yesterday] ? "yesterday at noon" : "no");
        printf("  read back, any case: %s\n",
               [[rel dateFromString:@"tomorrow at 12:00 PM"] isEqualToDate:tomorrow] ? "tomorrow at noon" : "no");
        [rel setDateStyle:NSDateFormatterNoStyle];
        printf("  no date style: %s\n", [[rel stringFromDate:noon] UTF8String]);
        [rel setDateStyle:NSDateFormatterFullStyle];
        [rel setTimeStyle:NSDateFormatterNoStyle];
        printf("  full date: %s; read back: %s\n", [[rel stringFromDate:noon] UTF8String],
               [[rel dateFromString:@"Today"] isEqualToDate:today] ? "the start of today" : "no");
        [rel setDoesRelativeDateFormatting:NO];
        printf("  not relative: %s\n", [[rel stringFromDate:noon] isEqualToString:@"Today"] ? "Today" : "a full date");
        printf("  calendar: %s; set to ISO 8601: ", [[[rel calendar] calendarIdentifier] UTF8String]);
        [rel setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601]];
        printf("%s\n", [[[rel calendar] calendarIdentifier] UTF8String]);

        printf("components formatter\n");
        NSDateComponentsFormatter *dcf = [[[NSDateComponentsFormatter alloc] init] autorelease];
        [dcf setReferenceDate:at(1704067200)];   /* 1 January 2024 */
        [dcf setAllowedUnits:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond];
        const struct {
            const char *name;
            NSDateComponentsFormatterUnitsStyle style;
        } styles[] = {{"positional", NSDateComponentsFormatterUnitsStylePositional},
                      {"abbreviated", NSDateComponentsFormatterUnitsStyleAbbreviated},
                      {"short", NSDateComponentsFormatterUnitsStyleShort},
                      {"full", NSDateComponentsFormatterUnitsStyleFull},
                      {"spell-out", NSDateComponentsFormatterUnitsStyleSpellOut},
                      {"brief", NSDateComponentsFormatterUnitsStyleBrief}};
        double times[] = {34890, 3723, 63, 3, 0, 3600, 86400 + 61};
        for (size_t i = 0; i < sizeof styles / sizeof styles[0]; i++) {
            [dcf setUnitsStyle:styles[i].style];
            printf("  %s\n", styles[i].name);
            for (size_t j = 0; j < sizeof times / sizeof times[0]; j++)
                interval(dcf, times[j]);
        }
        [dcf setUnitsStyle:NSDateComponentsFormatterUnitsStylePositional];
        [dcf setZeroFormattingBehavior:NSDateComponentsFormatterZeroFormattingBehaviorPad];
        printf("  positional, padded\n");
        interval(dcf, 63);
        interval(dcf, 3723);
        [dcf setZeroFormattingBehavior:NSDateComponentsFormatterZeroFormattingBehaviorNone];
        printf("  positional, no zeros dropped\n");
        interval(dcf, 63);
        [dcf setUnitsStyle:NSDateComponentsFormatterUnitsStyleAbbreviated];
        printf("  abbreviated, no zeros dropped\n");
        interval(dcf, 3603);
        [dcf setZeroFormattingBehavior:NSDateComponentsFormatterZeroFormattingBehaviorDefault];
        [dcf setAllowedUnits:NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute];
        printf("  days, hours and minutes\n");
        interval(dcf, 200000);
        interval(dcf, -5400);
        [dcf setMaximumUnitCount:1];
        printf("  one unit at most\n");
        interval(dcf, 200000);
        [dcf setMaximumUnitCount:0];
        [dcf setAllowedUnits:NSCalendarUnitHour];
        [dcf setAllowsFractionalUnits:YES];
        printf("  fractional hours\n");
        interval(dcf, 5400);
        [dcf setAllowsFractionalUnits:NO];
        [dcf setAllowedUnits:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay];
        [dcf setUnitsStyle:NSDateComponentsFormatterUnitsStyleFull];
        [dcf setCalendar:[[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease]];
        [[dcf calendar] setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
        printf("  years, months and days from 1 January 2024\n");
        interval(dcf, 86400 * 400.0);
        printf("    between two dates: %s\n", [[dcf stringFromDate:at(1704067200) toDate:at(1709251200)] UTF8String]);
        NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
        [c setMonth:14];
        [c setDay:3];
        printf("    components (14 months, 3 days): %s\n", [[dcf stringFromDateComponents:c] UTF8String]);
        [dcf setIncludesApproximationPhrase:YES];
        [dcf setIncludesTimeRemainingPhrase:YES];
        printf("    with phrases: %s\n", [[dcf stringFromDateComponents:c] UTF8String]);
        printf("  class method: %s\n",
               [[NSDateComponentsFormatter localizedStringFromDateComponents:c
                                                                  unitsStyle:NSDateComponentsFormatterUnitsStyleShort]
                   UTF8String] ? "a string" : "(nil)");
        @try {
            [dcf setAllowedUnits:NSCalendarUnitEra];
            printf("  era allowed\n");
        } @catch (NSException *e) {
            printf("  era refused: %s\n", [[e name] UTF8String]);
        }
    }
    return 0;
}
