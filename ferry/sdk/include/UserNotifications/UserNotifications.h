/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: UserNotifications (appkit/UNUserNotificationCenter.m, served
 * from Ferry's AppKit file). Written for freemac from Apple's public API
 * documentation; not Apple's header. Notifications are shown by the
 * desktop's notification server, over the freedesktop.org
 * org.freedesktop.Notifications interface. */
#ifndef _FERRY_USERNOTIFICATIONS_H_
#define _FERRY_USERNOTIFICATIONS_H_
#import <Foundation/Foundation.h>

@class UNNotification, UNNotificationCategory, UNNotificationRequest, UNNotificationResponse;
@class UNNotificationSettings, UNNotificationSound, UNNotificationTrigger, UNUserNotificationCenter;

FOUNDATION_EXPORT NSErrorDomain const UNErrorDomain;
typedef NS_ENUM(NSInteger, UNErrorCode) {
    UNErrorCodeNotificationsNotAllowed = 1,
    UNErrorCodeAttachmentInvalidURL = 100,
    UNErrorCodeAttachmentUnrecognizedType = 101,
    UNErrorCodeAttachmentInvalidFileSize = 102,
    UNErrorCodeAttachmentNotInDataStore = 103,
    UNErrorCodeAttachmentMoveIntoDataStoreFailed = 104,
    UNErrorCodeAttachmentCorrupt = 105,
    UNErrorCodeNotificationInvalidNoDate = 1400,
    UNErrorCodeNotificationInvalidNoContent = 1401,
    UNErrorCodeContentProvidingObjectNotAllowed = 1500,
    UNErrorCodeContentProvidingInvalid = 1501,
    UNErrorCodeBadgeInputInvalid = 1600,
};

typedef NS_OPTIONS(NSUInteger, UNAuthorizationOptions) {
    UNAuthorizationOptionNone = 0,
    UNAuthorizationOptionBadge = 1 << 0,
    UNAuthorizationOptionSound = 1 << 1,
    UNAuthorizationOptionAlert = 1 << 2,
    UNAuthorizationOptionCarPlay = 1 << 3,
    UNAuthorizationOptionCriticalAlert = 1 << 4,
    UNAuthorizationOptionProvidesAppNotificationSettings = 1 << 5,
    UNAuthorizationOptionProvisional = 1 << 6,
};
typedef NS_ENUM(NSInteger, UNAuthorizationStatus) {
    UNAuthorizationStatusNotDetermined = 0,
    UNAuthorizationStatusDenied,
    UNAuthorizationStatusAuthorized,
    UNAuthorizationStatusProvisional,
    UNAuthorizationStatusEphemeral,
};
typedef NS_ENUM(NSInteger, UNNotificationSetting) {
    UNNotificationSettingNotSupported = 0,
    UNNotificationSettingDisabled,
    UNNotificationSettingEnabled,
};
typedef NS_ENUM(NSInteger, UNAlertStyle) {
    UNAlertStyleNone = 0,
    UNAlertStyleBanner,
    UNAlertStyleAlert,
};
typedef NS_ENUM(NSInteger, UNShowPreviewsSetting) {
    UNShowPreviewsSettingAlways = 0,
    UNShowPreviewsSettingWhenAuthenticated,
    UNShowPreviewsSettingNever,
};
typedef NS_OPTIONS(NSUInteger, UNNotificationPresentationOptions) {
    UNNotificationPresentationOptionNone = 0,
    UNNotificationPresentationOptionBadge = 1 << 0,
    UNNotificationPresentationOptionSound = 1 << 1,
    UNNotificationPresentationOptionAlert = 1 << 2,
    UNNotificationPresentationOptionList = 1 << 3,
    UNNotificationPresentationOptionBanner = 1 << 4,
};
typedef NS_OPTIONS(NSUInteger, UNNotificationActionOptions) {
    UNNotificationActionOptionNone = 0,
    UNNotificationActionOptionAuthenticationRequired = 1 << 0,
    UNNotificationActionOptionDestructive = 1 << 1,
    UNNotificationActionOptionForeground = 1 << 2,
};
typedef NS_OPTIONS(NSUInteger, UNNotificationCategoryOptions) {
    UNNotificationCategoryOptionNone = 0,
    UNNotificationCategoryOptionCustomDismissAction = 1 << 0,
    UNNotificationCategoryOptionAllowInCarPlay = 1 << 1,
    UNNotificationCategoryOptionHiddenPreviewsShowTitle = 1 << 2,
    UNNotificationCategoryOptionHiddenPreviewsShowSubtitle = 1 << 3,
    UNNotificationCategoryOptionAllowAnnouncement = 1 << 4,
};
typedef NS_ENUM(NSUInteger, UNNotificationInterruptionLevel) {
    UNNotificationInterruptionLevelPassive = 0,
    UNNotificationInterruptionLevelActive = 1,
    UNNotificationInterruptionLevelTimeSensitive = 2,
    UNNotificationInterruptionLevelCritical = 3,
};

/* The identifiers a response carries for a click on the notification itself
 * and for its dismissal. */
FOUNDATION_EXPORT NSString *const UNNotificationDefaultActionIdentifier;
FOUNDATION_EXPORT NSString *const UNNotificationDismissActionIdentifier;

typedef NSString *UNNotificationSoundName;

@interface UNNotificationSound : NSObject <NSCopying, NSSecureCoding>
@property (class, readonly, copy) UNNotificationSound *defaultSound;
@property (class, readonly, copy) UNNotificationSound *defaultCriticalSound;
+ (UNNotificationSound *)defaultCriticalSoundWithAudioVolume:(float)volume;
+ (instancetype FERRY_SWIFT_NONNULL)soundNamed:(UNNotificationSoundName)name;
+ (instancetype FERRY_SWIFT_NONNULL)criticalSoundNamed:(UNNotificationSoundName)name;
+ (instancetype FERRY_SWIFT_NONNULL)criticalSoundNamed:(UNNotificationSoundName)name withAudioVolume:(float)volume;
@end

/* Kept with the content; not shown. */
@interface UNNotificationAttachment : NSObject <NSCopying, NSSecureCoding>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSURL *URL;
@property (readonly, copy) NSString *type;
+ (instancetype)attachmentWithIdentifier:(NSString *)identifier URL:(NSURL *)URL options:(NSDictionary *)options
                                   error:(NSError **)error;
@end

@interface UNNotificationContent : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>
@property (readonly, copy) NSString *title;
@property (readonly, copy) NSString *subtitle;
@property (readonly, copy) NSString *body;
@property (readonly, copy) NSNumber *badge;
@property (readonly, copy) UNNotificationSound *sound;
@property (readonly, copy) NSString *launchImageName;
@property (readonly, copy) NSDictionary *userInfo;
@property (readonly, copy) NSArray<UNNotificationAttachment *> *attachments;
@property (readonly, copy) NSString *categoryIdentifier;
@property (readonly, copy) NSString *threadIdentifier;
@property (readonly, copy) NSString *targetContentIdentifier;
@property (readonly, copy) NSString *summaryArgument;
@property (readonly) NSUInteger summaryArgumentCount;
@property (readonly) UNNotificationInterruptionLevel interruptionLevel;
@property (readonly) double relevanceScore;
@property (readonly, copy) NSString *filterCriteria;
@end

@interface UNMutableNotificationContent : UNNotificationContent
@property (copy) NSString *title;
@property (copy) NSString *subtitle;
@property (copy) NSString *body;
@property (copy) NSNumber *badge;
@property (copy) UNNotificationSound *sound;
@property (copy) NSString *launchImageName;
@property (copy) NSDictionary *userInfo;
@property (copy) NSArray<UNNotificationAttachment *> *attachments;
@property (copy) NSString *categoryIdentifier;
@property (copy) NSString *threadIdentifier;
@property (copy) NSString *targetContentIdentifier;
@property (copy) NSString *summaryArgument;
@property NSUInteger summaryArgumentCount;
@property UNNotificationInterruptionLevel interruptionLevel;
@property double relevanceScore;
@property (copy) NSString *filterCriteria;
@end

@interface UNNotificationTrigger : NSObject <NSCopying, NSSecureCoding>
@property (readonly) BOOL repeats;
@end
@interface UNPushNotificationTrigger : UNNotificationTrigger
@end
@interface UNTimeIntervalNotificationTrigger : UNNotificationTrigger
@property (readonly) NSTimeInterval timeInterval;
+ (instancetype FERRY_SWIFT_NONNULL)triggerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats;
- (NSDate *)nextTriggerDate;
@end
@interface UNCalendarNotificationTrigger : UNNotificationTrigger
@property (readonly, copy) NSDateComponents *dateComponents;
+ (instancetype FERRY_SWIFT_NONNULL)triggerWithDateMatchingComponents:(NSDateComponents *)dateComponents repeats:(BOOL)repeats;
- (NSDate *)nextTriggerDate;
@end

@interface UNNotificationRequest : NSObject <NSCopying, NSSecureCoding>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) UNNotificationContent *content;
@property (readonly, copy) UNNotificationTrigger *trigger;
+ (instancetype FERRY_SWIFT_NONNULL)requestWithIdentifier:(NSString *)identifier content:(UNNotificationContent *)content
                              trigger:(UNNotificationTrigger *)trigger;
@end

@interface UNNotification : NSObject <NSCopying, NSSecureCoding>
@property (readonly, copy) NSDate *date;
@property (readonly, copy) UNNotificationRequest *request;
@end

@interface UNNotificationAction : NSObject <NSCopying, NSSecureCoding>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *title;
@property (readonly) UNNotificationActionOptions options;
+ (instancetype FERRY_SWIFT_NONNULL)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options;
@end
@interface UNTextInputNotificationAction : UNNotificationAction
@property (readonly, copy) NSString *textInputButtonTitle;
@property (readonly, copy) NSString *textInputPlaceholder;
+ (instancetype FERRY_SWIFT_NONNULL)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options
                textInputButtonTitle:(NSString *)textInputButtonTitle
                textInputPlaceholder:(NSString *)textInputPlaceholder;
@end

@interface UNNotificationCategory : NSObject <NSCopying, NSSecureCoding>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSArray<UNNotificationAction *> *actions;
@property (readonly, copy) NSArray<NSString *> *intentIdentifiers;
@property (readonly) UNNotificationCategoryOptions options;
@property (readonly, copy) NSString *hiddenPreviewsBodyPlaceholder;
@property (readonly, copy) NSString *categorySummaryFormat;
+ (instancetype FERRY_SWIFT_NONNULL)categoryWithIdentifier:(NSString *)identifier actions:(NSArray<UNNotificationAction *> *)actions
                     intentIdentifiers:(NSArray<NSString *> *)intentIdentifiers
                               options:(UNNotificationCategoryOptions)options;
+ (instancetype FERRY_SWIFT_NONNULL)categoryWithIdentifier:(NSString *)identifier actions:(NSArray<UNNotificationAction *> *)actions
                     intentIdentifiers:(NSArray<NSString *> *)intentIdentifiers
         hiddenPreviewsBodyPlaceholder:(NSString *)hiddenPreviewsBodyPlaceholder
                               options:(UNNotificationCategoryOptions)options;
+ (instancetype FERRY_SWIFT_NONNULL)categoryWithIdentifier:(NSString *)identifier actions:(NSArray<UNNotificationAction *> *)actions
                     intentIdentifiers:(NSArray<NSString *> *)intentIdentifiers
         hiddenPreviewsBodyPlaceholder:(NSString *)hiddenPreviewsBodyPlaceholder
                 categorySummaryFormat:(NSString *)categorySummaryFormat
                               options:(UNNotificationCategoryOptions)options;
@end

@interface UNNotificationResponse : NSObject <NSCopying, NSSecureCoding>
@property (readonly, copy) UNNotification *notification;
@property (readonly, copy) NSString *actionIdentifier;
@end
@interface UNTextInputNotificationResponse : UNNotificationResponse
@property (readonly, copy) NSString *userText;
@end

@interface UNNotificationSettings : NSObject <NSCopying, NSSecureCoding>
@property (readonly) UNAuthorizationStatus authorizationStatus;
@property (readonly) UNNotificationSetting soundSetting;
@property (readonly) UNNotificationSetting badgeSetting;
@property (readonly) UNNotificationSetting alertSetting;
@property (readonly) UNNotificationSetting notificationCenterSetting;
@property (readonly) UNNotificationSetting lockScreenSetting;
@property (readonly) UNNotificationSetting carPlaySetting;
@property (readonly) UNNotificationSetting announcementSetting;
@property (readonly) UNNotificationSetting criticalAlertSetting;
@property (readonly) UNNotificationSetting timeSensitiveSetting;
@property (readonly) UNNotificationSetting scheduledDeliverySetting;
@property (readonly) UNNotificationSetting directMessagesSetting;
@property (readonly) UNAlertStyle alertStyle;
@property (readonly) UNShowPreviewsSetting showPreviewsSetting;
@property (readonly) BOOL providesAppNotificationSettings;
@end

@protocol UNUserNotificationCenterDelegate <NSObject>
@optional
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler;
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler;
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    openSettingsForNotification:(UNNotification *)notification;
@end

@interface UNUserNotificationCenter : NSObject
/* Kept without being retained, as a weak reference would be. */
@property (assign) id<UNUserNotificationCenterDelegate> delegate;
@property (readonly) BOOL supportsContentExtensions;
+ (UNUserNotificationCenter * FERRY_SWIFT_NONNULL)currentNotificationCenter;
- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                      completionHandler:(void (^)(BOOL granted, NSError *error))completionHandler;
- (void)setNotificationCategories:(NSSet<UNNotificationCategory *> *)categories;
- (void)getNotificationCategoriesWithCompletionHandler:(void (^)(NSSet<UNNotificationCategory *> *categories))handler;
- (void)getNotificationSettingsWithCompletionHandler:(void (^)(UNNotificationSettings *settings))completionHandler;
- (void)addNotificationRequest:(UNNotificationRequest *)request
         withCompletionHandler:(void (^)(NSError *error))completionHandler;
- (void)getPendingNotificationRequestsWithCompletionHandler:(void (^)(NSArray<UNNotificationRequest *> *requests))
                                                                completionHandler;
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removeAllPendingNotificationRequests;
- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *notifications))
                                                           completionHandler;
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removeAllDeliveredNotifications;
- (void)setBadgeCount:(NSInteger)newBadgeCount withCompletionHandler:(void (^)(NSError *error))completionHandler;
@end

#endif
