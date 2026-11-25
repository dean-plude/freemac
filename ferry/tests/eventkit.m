// SPDX-License-Identifier: GPL-3.0-or-later
// EventKit on freemac's calendar and reminders files (freemac 1.232,
// Ferry 0.56.0): access asked and kept, Tide's events read with their
// repeats, a date left out, a changed date, saves that keep Tide's own
// lines, and Nudge's lists of reminders. Run with a home of its own, no
// display and TZ=Europe/Paris.
#import <Foundation/Foundation.h>
#import <EventKit/EventKit.h>

static NSString *home(NSString *rel) { return [NSHomeDirectory() stringByAppendingPathComponent:rel]; }

static void put(NSString *rel, NSString *text)
{
    NSString *p = home(rel);
    [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [[text stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"] writeToFile:p atomically:YES
                                                                              encoding:NSUTF8StringEncoding error:NULL];
}

static NSString *get(NSString *rel)
{
    NSString *s = [NSString stringWithContentsOfFile:home(rel) encoding:NSUTF8StringEncoding error:NULL];
    return [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
}

static NSDate *at(int y, int m, int d, int h, int min)
{
    NSDateComponents *c = [NSDateComponents new];
    c.year = y;
    c.month = m;
    c.day = d;
    c.hour = h;
    c.minute = min;
    return [[NSCalendar currentCalendar] dateFromComponents:c];
}

static NSString *when(NSDate *d)
{
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"EEE yyyy-MM-dd HH:mm";
    return d ? [f stringFromDate:d] : @"(none)";
}

static void list_events(EKEventStore *store, NSDate *from, NSDate *to)
{
    NSPredicate *p = [store predicateForEventsWithStartDate:from endDate:to calendars:nil];
    for (EKEvent *e in [store eventsMatchingPredicate:p])
        printf("  %s - %s%s %s [%s]%s\n", when(e.startDate).UTF8String, when(e.endDate).UTF8String, e.allDay ? " (all day)" : "",
               e.title.UTF8String, e.calendar.title.UTF8String, e.isDetached ? " (changed)" : "");
}

static NSArray *fetch(EKEventStore *store, NSPredicate *p)
{
    __block NSArray *got = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [store fetchRemindersMatchingPredicate:p completion:^(NSArray *r) {
        got = r;
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return [got sortedArrayUsingComparator:^NSComparisonResult(EKReminder *a, EKReminder *b) { return [a.title compare:b.title]; }];
}

int main(void)
{
    @autoreleasepool {
        put(@".local/share/freemac/calendar.ics",
            @"BEGIN:VCALENDAR\n"
             "VERSION:2.0\n"
             "PRODID:-//freemac//Tide//EN\n"
             "BEGIN:VEVENT\n"
             "UID:standup@freemac\n"
             "SUMMARY:Standup\n"
             "DTSTART:20261123T093000\n"
             "DTEND:20261123T094500\n"
             "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\n"
             "EXDATE:20261127T093000\n"
             "X-TIDE-NOTE:kept as it was\n"
             "BEGIN:VALARM\n"
             "ACTION:DISPLAY\n"
             "DESCRIPTION:Standup\n"
             "TRIGGER:-PT10M\n"
             "END:VALARM\n"
             "END:VEVENT\n"
             "BEGIN:VEVENT\n"
             "UID:standup@freemac\n"
             "RECURRENCE-ID:20261125T093000\n"
             "SUMMARY:Standup (late)\n"
             "DTSTART:20261125T110000\n"
             "DTEND:20261125T111500\n"
             "END:VEVENT\n"
             "BEGIN:VEVENT\n"
             "UID:trip@freemac\n"
             "SUMMARY:Trip to Lyon\\, by train\n"
             "LOCATION:Gare de Lyon\n"
             "DTSTART;VALUE=DATE:20261128\n"
             "DTEND;VALUE=DATE:20261130\n"
             "END:VEVENT\n"
             "BEGIN:VEVENT\n"
             "UID:review@freemac\n"
             "SUMMARY:Review\n"
             "DTSTART:20261124T130000Z\n"
             "DTEND:20261124T140000Z\n"
             "ORGANIZER;CN=Sam Lee:mailto:sam@example.org\n"
             "ATTENDEE;CN=Alex Kim;PARTSTAT=ACCEPTED:mailto:alex@example.org\n"
             "X-FREEMAC-SOURCE:acct1 https://dav.example.org/cal/work/\n"
             "END:VEVENT\n"
             "BEGIN:VEVENT\n"
             "UID:monthly@freemac\n"
             "SUMMARY:Rent\n"
             "DTSTART;VALUE=DATE:20260130\n"
             "DTEND;VALUE=DATE:20260131\n"
             "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=12\n"
             "END:VEVENT\n"
             "END:VCALENDAR\n");
        put(@".local/share/freemac/reminders/home.ics",
            @"BEGIN:VCALENDAR\n"
             "VERSION:2.0\n"
             "PRODID:-//freemac//Nudge//EN\n"
             "X-WR-CALNAME:Home\n"
             "X-FREEMAC-COLOR:green\n"
             "X-FREEMAC-ORDER:0\n"
             "BEGIN:VTODO\n"
             "UID:milk@freemac\n"
             "SUMMARY:Buy milk\n"
             "DUE;VALUE=DATE:20261126\n"
             "PRIORITY:1\n"
             "X-FREEMAC-FLAGGED:1\n"
             "STATUS:NEEDS-ACTION\n"
             "END:VTODO\n"
             "BEGIN:VTODO\n"
             "UID:plants@freemac\n"
             "SUMMARY:Water the plants\n"
             "STATUS:COMPLETED\n"
             "COMPLETED:20261120T080000Z\n"
             "END:VTODO\n"
             "END:VCALENDAR\n");
        put(@".config/freemac/accounts.json", @"[{\"id\": \"acct1\", \"provider\": \"caldav\", \"server\": \"dav.example.org\", "
                                                "\"username\": \"alex@example.org\"}]\n");

        // no answer yet, and no display to ask on
        printf("events: %ld, reminders: %ld\n", (long)[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent],
               (long)[EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder]);
        EKEventStore *store = [EKEventStore new];
        dispatch_semaphore_t asked = dispatch_semaphore_create(0);
        __block BOOL granted = YES;
        [store requestFullAccessToEventsWithCompletion:^(BOOL ok, NSError *error) {
            granted = ok;
            dispatch_semaphore_signal(asked);
        }];
        while (dispatch_semaphore_wait(asked, DISPATCH_TIME_NOW))
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("granted: %d, now: %ld, kept: %s\n", granted, (long)[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent],
               [[NSFileManager defaultManager] fileExistsAtPath:home(@".config/freemac/calendar-access.json")] ? "yes" : "no");
        printf("calendars: %lu\n", (unsigned long)store.calendars.count);
        EKEvent *refused = [EKEvent eventWithEventStore:store];
        refused.startDate = [NSDate date];
        refused.endDate = [NSDate date];
        NSError *error = nil;
        BOOL saved = [store saveEvent:refused span:EKSpanThisEvent error:&error];
        printf("save: %d %s %ld\n", saved, error.domain.UTF8String, (long)error.code);

        // the user's answer, as the alert would keep it
        put(@".config/freemac/calendar-access.json",
            @"{\"apps\": {\"eventkit\": {\"name\": \"eventkit\", \"events\": true, \"reminders\": true}}}\n");
        printf("events: %ld, reminders: %ld\n", (long)[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent],
               (long)[EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder]);
        store = [EKEventStore new];
        for (EKSource *s in [store.sources sortedArrayUsingComparator:^NSComparisonResult(EKSource *a, EKSource *b) {
                 return [a.title compare:b.title];
             }])
            printf("source %s (%ld): %lu calendars\n", s.title.UTF8String, (long)s.sourceType,
                   (unsigned long)[s calendarsForEntityType:EKEntityTypeEvent].count);
        for (EKCalendar *c in store.calendars)
            printf("calendar %s, type %ld, in %s\n", c.title.UTF8String, (long)c.type, c.source.title.UTF8String);
        printf("default: %s\n", store.defaultCalendarForNewEvents.title.UTF8String);

        printf("week of 23 November:\n");
        list_events(store, at(2026, 11, 23, 0, 0), at(2026, 11, 30, 0, 0));
        printf("the rent, first half of 2026:\n");
        list_events(store, at(2026, 1, 1, 0, 0), at(2026, 7, 1, 0, 0));

        EKEvent *standup = [store eventWithIdentifier:@"standup@freemac"];
        EKRecurrenceRule *rule = standup.recurrenceRules.firstObject;
        printf("standup: freq %ld, %lu days, alarm %.0f, note: %s\n", (long)rule.frequency, (unsigned long)rule.daysOfTheWeek.count,
               standup.alarms.firstObject.relativeOffset, standup.hasChanges ? "changed" : "unchanged");
        EKEvent *review = [store eventWithIdentifier:@"review@freemac"];
        printf("review: organizer %s, attendee %s (%ld), me %d, zone %s\n", review.organizer.name.UTF8String,
               review.attendees.firstObject.name.UTF8String, (long)review.attendees.firstObject.participantStatus,
               review.attendees.firstObject.isCurrentUser, review.timeZone.name.UTF8String);

        // a new event, then the Monday after next left out of the standup
        EKEvent *lunch = [EKEvent eventWithEventStore:store];
        lunch.title = @"Lunch; with Robin";
        lunch.calendar = store.defaultCalendarForNewEvents;
        lunch.startDate = at(2026, 11, 26, 12, 30);
        lunch.endDate = at(2026, 11, 26, 13, 30);
        lunch.notes = @"Booked\nfor two";
        [lunch addAlarm:[EKAlarm alarmWithRelativeOffset:-15 * 60]];
        saved = [store saveEvent:lunch span:EKSpanThisEvent error:&error];
        printf("lunch saved: %d, new now: %d, id: %s\n", saved, lunch.isNew, lunch.eventIdentifier ? "yes" : "no");
        NSArray *week2 = [store eventsMatchingPredicate:[store predicateForEventsWithStartDate:at(2026, 11, 30, 0, 0)
                                                                                      endDate:at(2026, 12, 1, 0, 0)
                                                                                    calendars:nil]];
        EKEvent *monday = nil;
        for (EKEvent *e in week2)
            if ([e.title isEqualToString:@"Standup"])
                monday = e;
        printf("removing %s on %s: %d\n", monday.title.UTF8String, when(monday.occurrenceDate).UTF8String,
               [store removeEvent:monday span:EKSpanThisEvent error:&error]);
        printf("week of 30 November:\n");
        list_events(store, at(2026, 11, 30, 0, 0), at(2026, 12, 7, 0, 0));

        // the file as Tide finds it
        NSString *file = get(@".local/share/freemac/calendar.ics");
        for (NSString *want in @[@"X-TIDE-NOTE:kept as it was", @"EXDATE:20261130T093000", @"SUMMARY:Lunch\\; with Robin",
                                 @"DESCRIPTION:Booked\\nfor two", @"DTSTART:20261126T123000", @"TRIGGER:-PT15M",
                                 @"X-FREEMAC-SOURCE:acct1 https://dav.example.org/cal/work/", @"PRODID:-//freemac//Tide//EN"])
            printf("file has %s: %s\n", want.UTF8String, [file containsString:want] ? "yes" : "no");

        // the whole series moved to a later start
        standup.startDate = at(2026, 11, 23, 10, 0);
        standup.endDate = at(2026, 11, 23, 10, 15);
        printf("standup changed: %d\n", standup.hasChanges);
        [store saveEvent:standup span:EKSpanFutureEvents error:NULL];
        printf("Friday 4 December:\n");
        list_events(store, at(2026, 12, 4, 0, 0), at(2026, 12, 5, 0, 0));
        printf("week of 23 November, moved:\n");
        list_events(store, at(2026, 11, 23, 0, 0), at(2026, 11, 28, 0, 0));
        [store removeEvent:lunch span:EKSpanThisEvent error:NULL];
        printf("lunch gone: %s\n", [get(@".local/share/freemac/calendar.ics") containsString:@"Lunch"] ? "no" : "yes");

        // reminders
        for (EKCalendar *c in [store calendarsForEntityType:EKEntityTypeReminder])
            printf("list %s (%s)\n", c.title.UTF8String, c.calendarIdentifier.UTF8String);
        for (EKReminder *r in fetch(store, [store predicateForRemindersInCalendars:nil]))
            printf("  %s, due %ld-%ld, priority %lu, %s\n", r.title.UTF8String, (long)r.dueDateComponents.month,
                   (long)r.dueDateComponents.day, (unsigned long)r.priority, r.completed ? "done" : "to do");
        EKReminder *call = [EKReminder reminderWithEventStore:store];
        call.title = @"Call the plumber";
        call.calendar = store.defaultCalendarForNewReminders;
        NSDateComponents *due = [NSDateComponents new];
        due.year = 2026;
        due.month = 11;
        due.day = 27;
        due.hour = 9;
        due.minute = 0;
        call.dueDateComponents = due;
        printf("call saved: %d\n", [store saveReminder:call commit:YES error:&error]);
        EKReminder *milk = (EKReminder *)[store calendarItemWithIdentifier:@"milk@freemac"];
        milk.completed = YES;
        printf("milk saved: %d\n", [store saveReminder:milk commit:YES error:&error]);
        printf("incomplete, due this week:\n");
        for (EKReminder *r in fetch(store, [store predicateForIncompleteRemindersWithDueDateStarting:at(2026, 11, 23, 0, 0)
                                                                                              ending:at(2026, 11, 30, 0, 0)
                                                                                           calendars:nil]))
            printf("  %s at %02ld:%02ld\n", r.title.UTF8String, (long)r.dueDateComponents.hour, (long)r.dueDateComponents.minute);
        printf("completed: %lu\n",
               (unsigned long)fetch(store, [store predicateForCompletedRemindersWithCompletionDateStarting:nil ending:nil calendars:nil]).count);
        NSString *list = get(@".local/share/freemac/reminders/home.ics");
        for (NSString *want in @[@"X-WR-CALNAME:Home", @"X-FREEMAC-COLOR:green", @"X-FREEMAC-FLAGGED:1", @"DUE:20261127T090000",
                                 @"SUMMARY:Call the plumber"])
            printf("list has %s: %s\n", want.UTF8String, [list containsString:want] ? "yes" : "no");

        // a new list, as Nudge keeps one
        EKCalendar *work = [EKCalendar calendarForEntityType:EKEntityTypeReminder eventStore:store];
        work.title = @"Work";
        printf("work list saved: %d, lists now: %lu\n", [store saveCalendar:work commit:YES error:&error],
               (unsigned long)[store calendarsForEntityType:EKEntityTypeReminder].count);
        EKCalendar *more = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:store];
        more.title = @"More";
        printf("event calendar saved: %d (%ld)\n", [store saveCalendar:more commit:YES error:&error], (long)error.code);

        // a change made by someone else is posted (once the saves' own have been)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        __block int posted = 0;
        [[NSNotificationCenter defaultCenter] addObserverForName:EKEventStoreChangedNotification object:store queue:nil
                                                      usingBlock:^(NSNotification *n) { posted++; }];
        put(@".local/share/freemac/reminders/home.ics", [list stringByAppendingString:@""]);
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:6];
        while (!posted && [until timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        printf("changed outside: %s\n", posted ? "posted" : "not posted");
    }
    return 0;
}
