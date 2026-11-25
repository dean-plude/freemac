/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: EventKit, written from Apple's public EventKit documentation
 * (freemac 1.232, Ferry 0.56.0). The store is freemac's own: the events
 * Tide keeps in ~/.local/share/freemac/calendar.ics and the reminder lists
 * Nudge keeps in ~/.local/share/freemac/reminders/, standard iCalendar
 * files, so what a Mac app adds shows in freemac's Calendar and Reminders
 * and the other way round. Access is asked for once per app and kept in
 * ~/.config/freemac/calendar-access.json, as a Mac asks. Ferry's own
 * EventKit.framework (eventkit/EventKit.m). */
#ifndef _FERRY_EVENTKIT_H_
#define _FERRY_EVENTKIT_H_
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define EK_EXTERN extern __attribute__((visibility("default")))

@class NSColor, EKEventStore, EKSource, EKCalendar, EKCalendarItem, EKEvent, EKReminder, EKAlarm,
    EKRecurrenceRule, EKRecurrenceEnd, EKRecurrenceDayOfWeek, EKParticipant, EKStructuredLocation;

/* ---- types ------------------------------------------------------------------ */

typedef NS_ENUM(NSInteger, EKAuthorizationStatus) {
    EKAuthorizationStatusNotDetermined = 0,
    EKAuthorizationStatusRestricted = 1,
    EKAuthorizationStatusDenied = 2,
    EKAuthorizationStatusFullAccess = 3,
    EKAuthorizationStatusWriteOnly = 4,
    EKAuthorizationStatusAuthorized = EKAuthorizationStatusFullAccess,
};

typedef NS_ENUM(NSInteger, EKWeekday) {
    EKWeekdaySunday = 1, EKWeekdayMonday, EKWeekdayTuesday, EKWeekdayWednesday,
    EKWeekdayThursday, EKWeekdayFriday, EKWeekdaySaturday,
    EKSunday = EKWeekdaySunday, EKMonday = EKWeekdayMonday, EKTuesday = EKWeekdayTuesday,
    EKWednesday = EKWeekdayWednesday, EKThursday = EKWeekdayThursday, EKFriday = EKWeekdayFriday,
    EKSaturday = EKWeekdaySaturday,
};

typedef NS_ENUM(NSInteger, EKRecurrenceFrequency) {
    EKRecurrenceFrequencyDaily, EKRecurrenceFrequencyWeekly, EKRecurrenceFrequencyMonthly,
    EKRecurrenceFrequencyYearly,
};

typedef NS_ENUM(NSInteger, EKParticipantType) {
    EKParticipantTypeUnknown, EKParticipantTypePerson, EKParticipantTypeRoom, EKParticipantTypeResource,
    EKParticipantTypeGroup,
};

typedef NS_ENUM(NSInteger, EKParticipantRole) {
    EKParticipantRoleUnknown, EKParticipantRoleRequired, EKParticipantRoleOptional, EKParticipantRoleChair,
    EKParticipantRoleNonParticipant,
};

typedef NS_ENUM(NSInteger, EKParticipantScheduleStatus) {
    EKParticipantScheduleStatusNone, EKParticipantScheduleStatusPending, EKParticipantScheduleStatusSent,
    EKParticipantScheduleStatusDelivered, EKParticipantScheduleStatusRecipientNotRecognized,
    EKParticipantScheduleStatusNoPrivileges, EKParticipantScheduleStatusDeliveryFailed,
    EKParticipantScheduleStatusCannotDeliver, EKParticipantScheduleStatusRecipientNotAllowed,
};

typedef NS_ENUM(NSInteger, EKParticipantStatus) {
    EKParticipantStatusUnknown, EKParticipantStatusPending, EKParticipantStatusAccepted,
    EKParticipantStatusDeclined, EKParticipantStatusTentative, EKParticipantStatusDelegated,
    EKParticipantStatusCompleted, EKParticipantStatusInProcess,
};

typedef NS_ENUM(NSInteger, EKCalendarType) {
    EKCalendarTypeLocal, EKCalendarTypeCalDAV, EKCalendarTypeExchange, EKCalendarTypeSubscription,
    EKCalendarTypeBirthday,
};

typedef NS_OPTIONS(NSUInteger, EKCalendarEventAvailabilityMask) {
    EKCalendarEventAvailabilityNone = 0,
    EKCalendarEventAvailabilityBusy = 1 << 0,
    EKCalendarEventAvailabilityFree = 1 << 1,
    EKCalendarEventAvailabilityTentative = 1 << 2,
    EKCalendarEventAvailabilityUnavailable = 1 << 3,
};

typedef NS_ENUM(NSInteger, EKSourceType) {
    EKSourceTypeLocal, EKSourceTypeExchange, EKSourceTypeCalDAV, EKSourceTypeMobileMe, EKSourceTypeSubscribed,
    EKSourceTypeBirthdays,
};

typedef NS_ENUM(NSUInteger, EKEntityType) {
    EKEntityTypeEvent,
    EKEntityTypeReminder,
};

typedef NS_OPTIONS(NSUInteger, EKEntityMask) {
    EKEntityMaskEvent = 1 << EKEntityTypeEvent,
    EKEntityMaskReminder = 1 << EKEntityTypeReminder,
};

typedef NS_ENUM(NSInteger, EKAlarmProximity) {
    EKAlarmProximityNone, EKAlarmProximityEnter, EKAlarmProximityLeave,
};

typedef NS_ENUM(NSInteger, EKAlarmType) {
    EKAlarmTypeDisplay, EKAlarmTypeAudio, EKAlarmTypeProcedure, EKAlarmTypeEmail,
};

typedef NS_ENUM(NSUInteger, EKReminderPriority) {
    EKReminderPriorityNone = 0, EKReminderPriorityHigh = 1, EKReminderPriorityMedium = 5, EKReminderPriorityLow = 9,
};

typedef NS_ENUM(NSInteger, EKSpan) {
    EKSpanThisEvent,
    EKSpanFutureEvents,
};

typedef NS_ENUM(NSInteger, EKEventAvailability) {
    EKEventAvailabilityNotSupported = -1,
    EKEventAvailabilityBusy = 0,
    EKEventAvailabilityFree,
    EKEventAvailabilityTentative,
    EKEventAvailabilityUnavailable,
};

typedef NS_ENUM(NSInteger, EKEventStatus) {
    EKEventStatusNone = 0, EKEventStatusConfirmed, EKEventStatusTentative, EKEventStatusCanceled,
};

EK_EXTERN NSString *const EKErrorDomain;

typedef NS_ENUM(NSInteger, EKErrorCode) {
    EKErrorEventNotMutable = 0,
    EKErrorNoCalendar,
    EKErrorNoStartDate,
    EKErrorNoEndDate,
    EKErrorDatesInverted,
    EKErrorInternalFailure,
    EKErrorCalendarReadOnly,
    EKErrorDurationGreaterThanRecurrence,
    EKErrorAlarmGreaterThanRecurrence,
    EKErrorStartDateTooFarInFuture,
    EKErrorStartDateCollidesWithOtherOccurrence,
    EKErrorObjectBelongsToDifferentStore,
    EKErrorInvitesCannotBeMoved,
    EKErrorInvalidSpan,
    EKErrorCalendarHasNoSource,
    EKErrorCalendarSourceCannotBeModified,
    EKErrorCalendarIsImmutable,
    EKErrorSourceDoesNotAllowCalendarAddDelete,
    EKErrorRecurringReminderRequiresDueDate,
    EKErrorStructuredLocationsNotSupported,
    EKErrorReminderLocationsNotSupported,
    EKErrorAlarmProximityNotSupported,
    EKErrorCalendarDoesNotAllowEvents,
    EKErrorCalendarDoesNotAllowReminders,
    EKErrorSourceDoesNotAllowReminders,
    EKErrorSourceDoesNotAllowEvents,
    EKErrorPriorityIsInvalid,
    EKErrorInvalidEntityType,
    EKErrorProcedureAlarmsNotMutable,
    EKErrorEventStoreNotAuthorized,
    EKErrorOSNotSupported,
    EKErrorInvalidInviteReplyCalendar,
    EKErrorNotificationsCollectionFlagNotSet,
    EKErrorSourceMismatch,
    EKErrorNotificationCollectionMismatch,
    EKErrorNotificationSavedWithoutCollection,
    EKErrorReminderAlarmContainsEmailOrUrl,
    EKErrorLast,
};

/* Posted (on the main thread) when the store changes outside the program,
 * or another of its stores saves. */
EK_EXTERN NSString *const EKEventStoreChangedNotification;

typedef void (^EKEventStoreRequestAccessCompletionHandler)(BOOL granted, NSError *error);
typedef void (^EKEventSearchCallback)(EKEvent *event, BOOL *stop);

/* ---- objects ---------------------------------------------------------------- */

@interface EKObject : NSObject
@property (nonatomic, readonly) BOOL hasChanges;
- (BOOL)isNew;
- (void)reset;
- (void)rollback;
- (BOOL)refresh;
@end

@interface EKSource : EKObject
@property (nonatomic, readonly) NSString *sourceIdentifier;
@property (nonatomic, readonly) EKSourceType sourceType;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSSet<EKCalendar *> *calendars;
@property (nonatomic, readonly) BOOL isDelegate;
- (NSSet<EKCalendar *> *)calendarsForEntityType:(EKEntityType)entityType;
@end

@interface EKCalendar : EKObject
+ (EKCalendar *)calendarWithEventStore:(EKEventStore *)eventStore;
+ (EKCalendar *)calendarForEntityType:(EKEntityType)entityType eventStore:(EKEventStore *)eventStore;
@property (nonatomic, strong) EKSource *source;
@property (nonatomic, readonly) NSString *calendarIdentifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) EKCalendarType type;
@property (nonatomic, readonly) BOOL allowsContentModifications;
@property (nonatomic, readonly, getter=isSubscribed) BOOL subscribed;
@property (nonatomic, readonly, getter=isImmutable) BOOL immutable;
@property (nonatomic, copy) NSColor *color;
@property (nonatomic) CGColorRef CGColor;
@property (nonatomic, readonly) EKCalendarEventAvailabilityMask supportedEventAvailabilities;
@property (nonatomic, readonly) EKEntityMask allowedEntityTypes;
@end

@interface EKRecurrenceEnd : NSObject <NSCopying>
+ (instancetype)recurrenceEndWithEndDate:(NSDate *)endDate;
+ (instancetype)recurrenceEndWithOccurrenceCount:(NSUInteger)occurrenceCount;
@property (nonatomic, readonly) NSDate *endDate;
@property (nonatomic, readonly) NSUInteger occurrenceCount;
@end

@interface EKRecurrenceDayOfWeek : NSObject <NSCopying>
+ (instancetype)dayOfWeek:(EKWeekday)dayOfTheWeek;
+ (instancetype)dayOfWeek:(EKWeekday)dayOfTheWeek weekNumber:(NSInteger)weekNumber;
- (instancetype)initWithDayOfTheWeek:(EKWeekday)dayOfTheWeek weekNumber:(NSInteger)weekNumber;
@property (nonatomic, readonly) EKWeekday dayOfTheWeek;
@property (nonatomic, readonly) NSInteger weekNumber;
@end

@interface EKRecurrenceRule : EKObject <NSCopying>
- (instancetype)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type interval:(NSInteger)interval
                                        end:(EKRecurrenceEnd *)end;
- (instancetype)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type interval:(NSInteger)interval
                              daysOfTheWeek:(NSArray<EKRecurrenceDayOfWeek *> *)days
                             daysOfTheMonth:(NSArray<NSNumber *> *)monthDays
                            monthsOfTheYear:(NSArray<NSNumber *> *)months
                             weeksOfTheYear:(NSArray<NSNumber *> *)weeksOfTheYear
                              daysOfTheYear:(NSArray<NSNumber *> *)daysOfTheYear
                               setPositions:(NSArray<NSNumber *> *)setPositions
                                        end:(EKRecurrenceEnd *)end;
@property (nonatomic, readonly) NSString *calendarIdentifier;
@property (nonatomic, copy) EKRecurrenceEnd *recurrenceEnd;
@property (nonatomic, readonly) EKRecurrenceFrequency frequency;
@property (nonatomic, readonly) NSInteger interval;
@property (nonatomic, readonly) EKWeekday firstDayOfTheWeek;
@property (nonatomic, readonly) NSArray<EKRecurrenceDayOfWeek *> *daysOfTheWeek;
@property (nonatomic, readonly) NSArray<NSNumber *> *daysOfTheMonth;
@property (nonatomic, readonly) NSArray<NSNumber *> *daysOfTheYear;
@property (nonatomic, readonly) NSArray<NSNumber *> *weeksOfTheYear;
@property (nonatomic, readonly) NSArray<NSNumber *> *monthsOfTheYear;
@property (nonatomic, readonly) NSArray<NSNumber *> *setPositions;
@end

@interface EKStructuredLocation : EKObject <NSCopying>
+ (instancetype)locationWithTitle:(NSString *)title;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) id geoLocation;    /* a CLLocation on a Mac; never set here */
@property (nonatomic) double radius;
@end

@interface EKAlarm : EKObject <NSCopying>
+ (EKAlarm *)alarmWithAbsoluteDate:(NSDate *)date;
+ (EKAlarm *)alarmWithRelativeOffset:(NSTimeInterval)offset;
@property (nonatomic) NSTimeInterval relativeOffset;
@property (nonatomic, copy) NSDate *absoluteDate;
@property (nonatomic, copy) EKStructuredLocation *structuredLocation;
@property (nonatomic) EKAlarmProximity proximity;
@property (nonatomic, readonly) EKAlarmType type;
@property (nonatomic, copy) NSString *emailAddress;
@property (nonatomic, copy) NSString *soundName;
@property (nonatomic, copy) NSURL *url;
@end

@interface EKParticipant : EKObject <NSCopying>
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) EKParticipantStatus participantStatus;
@property (nonatomic, readonly) EKParticipantRole participantRole;
@property (nonatomic, readonly) EKParticipantType participantType;
@property (nonatomic, readonly, getter=isCurrentUser) BOOL currentUser;
@property (nonatomic, readonly) NSPredicate *contactPredicate;
@end

@interface EKCalendarItem : EKObject
@property (nonatomic, readonly) NSString *UUID;
@property (nonatomic, strong) EKCalendar *calendar;
@property (nonatomic, readonly) NSString *calendarItemIdentifier;
@property (nonatomic, readonly) NSString *calendarItemExternalIdentifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, copy) NSString *notes;
@property (nonatomic, copy) NSURL *URL;
@property (nonatomic, readonly) NSDate *lastModifiedDate;
@property (nonatomic, readonly) NSDate *creationDate;
@property (nonatomic, copy) NSTimeZone *timeZone;
@property (nonatomic, readonly) BOOL hasAlarms;
@property (nonatomic, readonly) BOOL hasRecurrenceRules;
@property (nonatomic, readonly) BOOL hasAttendees;
@property (nonatomic, readonly) BOOL hasNotes;
@property (nonatomic, readonly) NSArray<EKParticipant *> *attendees;
@property (nonatomic, copy) NSArray<EKAlarm *> *alarms;
- (void)addAlarm:(EKAlarm *)alarm;
- (void)removeAlarm:(EKAlarm *)alarm;
@property (nonatomic, copy) NSArray<EKRecurrenceRule *> *recurrenceRules;
- (void)addRecurrenceRule:(EKRecurrenceRule *)rule;
- (void)removeRecurrenceRule:(EKRecurrenceRule *)rule;
@end

@interface EKEvent : EKCalendarItem
+ (EKEvent *)eventWithEventStore:(EKEventStore *)eventStore;
@property (nonatomic, readonly) NSString *eventIdentifier;
@property (nonatomic, getter=isAllDay) BOOL allDay;
@property (nonatomic, copy) NSDate *startDate;
@property (nonatomic, copy) NSDate *endDate;
@property (nonatomic, copy) EKStructuredLocation *structuredLocation;
- (NSComparisonResult)compareStartDateWithEvent:(EKEvent *)other;
@property (nonatomic, readonly) EKParticipant *organizer;
@property (nonatomic) EKEventAvailability availability;
@property (nonatomic, readonly) EKEventStatus status;
@property (nonatomic, readonly) BOOL isDetached;
@property (nonatomic, readonly) NSDate *occurrenceDate;
@property (nonatomic, readonly) NSString *birthdayContactIdentifier;
@property (nonatomic, readonly) NSInteger birthdayPersonID;
@property (nonatomic, readonly) NSString *birthdayPersonUniqueID;
@end

@interface EKReminder : EKCalendarItem
+ (EKReminder *)reminderWithEventStore:(EKEventStore *)eventStore;
@property (nonatomic, copy) NSDateComponents *startDateComponents;
@property (nonatomic, copy) NSDateComponents *dueDateComponents;
@property (nonatomic, getter=isCompleted) BOOL completed;
@property (nonatomic, copy) NSDate *completionDate;
@property (nonatomic) NSUInteger priority;
@end

@interface EKEventStore : NSObject
+ (EKAuthorizationStatus)authorizationStatusForEntityType:(EKEntityType)entityType;
- (instancetype)init;
- (instancetype)initWithAccessToEntityTypes:(EKEntityMask)entityTypes;
- (instancetype)initWithSources:(NSArray<EKSource *> *)sources;
- (void)requestAccessToEntityType:(EKEntityType)entityType completion:(EKEventStoreRequestAccessCompletionHandler)completion;
- (void)requestFullAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)completion;
- (void)requestWriteOnlyAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)completion;
- (void)requestFullAccessToRemindersWithCompletion:(EKEventStoreRequestAccessCompletionHandler)completion;
@property (nonatomic, readonly) NSString *eventStoreIdentifier;
@property (nonatomic, readonly) NSArray<EKSource *> *delegateSources;
@property (nonatomic, readonly) NSArray<EKSource *> *sources;
- (EKSource *)sourceWithIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSArray<EKCalendar *> *calendars;
- (NSArray<EKCalendar *> *)calendarsForEntityType:(EKEntityType)entityType;
@property (nonatomic, readonly) EKCalendar *defaultCalendarForNewEvents;
- (EKCalendar *)defaultCalendarForNewReminders;
- (EKCalendar *)calendarWithIdentifier:(NSString *)identifier;
- (BOOL)saveCalendar:(EKCalendar *)calendar commit:(BOOL)commit error:(NSError **)error;
- (BOOL)removeCalendar:(EKCalendar *)calendar commit:(BOOL)commit error:(NSError **)error;
- (EKCalendarItem *)calendarItemWithIdentifier:(NSString *)identifier;
- (NSArray<EKCalendarItem *> *)calendarItemsWithExternalIdentifier:(NSString *)externalIdentifier;
- (BOOL)saveEvent:(EKEvent *)event span:(EKSpan)span error:(NSError **)error;
- (BOOL)removeEvent:(EKEvent *)event span:(EKSpan)span error:(NSError **)error;
- (BOOL)saveEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error;
- (BOOL)removeEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error;
- (EKEvent *)eventWithIdentifier:(NSString *)identifier;
- (NSArray<EKEvent *> *)eventsMatchingPredicate:(NSPredicate *)predicate;
- (void)enumerateEventsMatchingPredicate:(NSPredicate *)predicate usingBlock:(EKEventSearchCallback)block;
- (NSPredicate *)predicateForEventsWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate
                                       calendars:(NSArray<EKCalendar *> *)calendars;
- (BOOL)saveReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error;
- (BOOL)removeReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error;
- (id)fetchRemindersMatchingPredicate:(NSPredicate *)predicate completion:(void (^)(NSArray<EKReminder *> *reminders))completion;
- (void)cancelFetchRequest:(id)fetchIdentifier;
- (NSPredicate *)predicateForRemindersInCalendars:(NSArray<EKCalendar *> *)calendars;
- (NSPredicate *)predicateForIncompleteRemindersWithDueDateStarting:(NSDate *)startDate ending:(NSDate *)endDate
                                                          calendars:(NSArray<EKCalendar *> *)calendars;
- (NSPredicate *)predicateForCompletedRemindersWithCompletionDateStarting:(NSDate *)startDate ending:(NSDate *)endDate
                                                                calendars:(NSArray<EKCalendar *> *)calendars;
- (BOOL)commit:(NSError **)error;
- (void)reset;
- (void)refreshSourcesIfNecessary;
@end

#endif
