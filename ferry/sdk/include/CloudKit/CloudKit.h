/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CloudKit with no iCloud account, written from Apple's public
 * CloudKit documentation. freemac has no iCloud, so a container's account
 * status is CKAccountStatusNoAccount, and every request to a database, by
 * its convenience calls or by an operation, ends with CKErrorDomain's
 * CKErrorNotAuthenticated, from a background queue as CloudKit's answers
 * come. Records, record and zone identifiers, zones, subscriptions, queries
 * and change tokens are ordinary objects an app can make, copy, compare and
 * archive. Ferry's own CloudKit.framework. */
#ifndef _FERRY_CLOUDKIT_H_
#define _FERRY_CLOUDKIT_H_
#import <Foundation/Foundation.h>

#define CK_EXTERN extern __attribute__((visibility("default")))

CK_EXTERN NSString *const CKErrorDomain;
CK_EXTERN NSString *const CKPartialErrorsByItemIDKey;
CK_EXTERN NSString *const CKRecordChangedErrorAncestorRecordKey;
CK_EXTERN NSString *const CKRecordChangedErrorServerRecordKey;
CK_EXTERN NSString *const CKRecordChangedErrorClientRecordKey;
CK_EXTERN NSString *const CKErrorRetryAfterKey;
CK_EXTERN NSString *const CKOwnerDefaultName;
CK_EXTERN NSString *const CKCurrentUserDefaultName;
CK_EXTERN NSString *const CKRecordZoneDefaultName;
CK_EXTERN NSString *const CKAccountChangedNotification;
CK_EXTERN NSString *const CKRecordTypeUserRecord;
CK_EXTERN NSString *const CKRecordCreationDateKey;
CK_EXTERN NSString *const CKRecordModificationDateKey;
CK_EXTERN NSString *const CKRecordRecordIDKey;

typedef NS_ENUM(NSInteger, CKErrorCode) {
    CKErrorInternalError = 1, CKErrorPartialFailure = 2, CKErrorNetworkUnavailable = 3, CKErrorNetworkFailure = 4,
    CKErrorBadContainer = 5, CKErrorServiceUnavailable = 6, CKErrorRequestRateLimited = 7,
    CKErrorMissingEntitlement = 8, CKErrorNotAuthenticated = 9, CKErrorPermissionFailure = 10,
    CKErrorUnknownItem = 11, CKErrorInvalidArguments = 12, CKErrorResultsTruncated = 13,
    CKErrorServerRecordChanged = 14, CKErrorServerRejectedRequest = 15, CKErrorAssetFileNotFound = 16,
    CKErrorAssetFileModified = 17, CKErrorIncompatibleVersion = 18, CKErrorConstraintViolation = 19,
    CKErrorOperationCancelled = 20, CKErrorChangeTokenExpired = 21, CKErrorBatchRequestFailed = 22,
    CKErrorZoneBusy = 23, CKErrorBadDatabase = 24, CKErrorQuotaExceeded = 25, CKErrorZoneNotFound = 26,
    CKErrorLimitExceeded = 27, CKErrorUserDeletedZone = 28, CKErrorTooManyParticipants = 29,
    CKErrorAlreadyShared = 30, CKErrorReferenceViolation = 31, CKErrorManagedAccountRestricted = 32,
    CKErrorParticipantMayNeedVerification = 33, CKErrorServerResponseLost = 34, CKErrorAssetNotAvailable = 35,
    CKErrorAccountTemporarilyUnavailable = 36,
};

typedef NS_ENUM(NSInteger, CKAccountStatus) {
    CKAccountStatusCouldNotDetermine = 0,
    CKAccountStatusAvailable = 1,
    CKAccountStatusRestricted = 2,
    CKAccountStatusNoAccount = 3,
    CKAccountStatusTemporarilyUnavailable = 4,
};

typedef NS_ENUM(NSInteger, CKDatabaseScope) {
    CKDatabaseScopePublic = 1,
    CKDatabaseScopePrivate = 2,
    CKDatabaseScopeShared = 3,
};

typedef NS_OPTIONS(NSUInteger, CKQuerySubscriptionOptions) {
    CKQuerySubscriptionOptionsFiresOnRecordCreation = 1 << 0,
    CKQuerySubscriptionOptionsFiresOnRecordUpdate = 1 << 1,
    CKQuerySubscriptionOptionsFiresOnRecordDeletion = 1 << 2,
    CKQuerySubscriptionOptionsFiresOnce = 1 << 3,
};

typedef NS_ENUM(NSInteger, CKSubscriptionType) {
    CKSubscriptionTypeQuery = 1,
    CKSubscriptionTypeRecordZone = 2,
    CKSubscriptionTypeDatabase = 3,
};

typedef NS_ENUM(NSInteger, CKNotificationType) {
    CKNotificationTypeQuery = 1,
    CKNotificationTypeRecordZone = 2,
    CKNotificationTypeReadNotification = 3,
    CKNotificationTypeDatabase = 4,
};

typedef NS_OPTIONS(NSUInteger, CKRecordZoneCapabilities) {
    CKRecordZoneCapabilityFetchChanges = 1 << 0,
    CKRecordZoneCapabilityAtomic = 1 << 1,
    CKRecordZoneCapabilitySharing = 1 << 2,
};

typedef NS_ENUM(NSInteger, CKRecordSavePolicy) {
    CKRecordSaveIfServerRecordUnchanged = 0,
    CKRecordSaveChangedKeys = 1,
    CKRecordSaveAllKeys = 2,
};

typedef NS_ENUM(NSUInteger, CKReferenceAction) {
    CKReferenceActionNone = 0,
    CKReferenceActionDeleteSelf = 1,
};

typedef NSString *CKRecordType;
typedef NSString *CKRecordFieldKey;
typedef NSString *CKSubscriptionID;

@protocol CKRecordValue <NSObject>
@end
@interface NSString (CKRecordValue) <CKRecordValue>
@end
@interface NSNumber (CKRecordValue) <CKRecordValue>
@end
@interface NSArray (CKRecordValue) <CKRecordValue>
@end
@interface NSDate (CKRecordValue) <CKRecordValue>
@end
@interface NSData (CKRecordValue) <CKRecordValue>
@end

@interface CKRecordZoneID : NSObject <NSSecureCoding, NSCopying>
- (instancetype)initWithZoneName:(NSString *)zoneName ownerName:(NSString *)ownerName;
@property (readonly, copy) NSString *zoneName;
@property (readonly, copy) NSString *ownerName;
@end

@interface CKRecordID : NSObject <NSSecureCoding, NSCopying>
- (instancetype)initWithRecordName:(NSString *)recordName;
- (instancetype)initWithRecordName:(NSString *)recordName zoneID:(CKRecordZoneID *)zoneID;
@property (readonly, copy) NSString *recordName;
@property (readonly, strong) CKRecordZoneID *zoneID;
@end

@interface CKRecordZone : NSObject <NSSecureCoding, NSCopying>
+ (CKRecordZone *)defaultRecordZone;
- (instancetype)initWithZoneName:(NSString *)zoneName;
- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID;
@property (readonly, strong) CKRecordZoneID *zoneID;
@property (readonly) CKRecordZoneCapabilities capabilities;
@end

@interface CKReference : NSObject <NSSecureCoding, NSCopying, CKRecordValue>
- (instancetype)initWithRecordID:(CKRecordID *)recordID action:(CKReferenceAction)action;
@property (readonly, copy) CKRecordID *recordID;
@property (readonly) CKReferenceAction referenceAction;
@end

@interface CKAsset : NSObject <CKRecordValue>
- (instancetype)initWithFileURL:(NSURL *)fileURL;
@property (readonly, copy) NSURL *fileURL;
@end

@interface CKRecord : NSObject <NSSecureCoding, NSCopying>
- (instancetype)initWithRecordType:(CKRecordType)recordType;
- (instancetype)initWithRecordType:(CKRecordType)recordType recordID:(CKRecordID *)recordID;
- (instancetype)initWithRecordType:(CKRecordType)recordType zoneID:(CKRecordZoneID *)zoneID;
@property (readonly, copy) CKRecordType recordType;
@property (readonly, copy) CKRecordID *recordID;
@property (readonly, copy) NSString *recordChangeTag;
@property (readonly, copy) CKRecordID *creatorUserRecordID;
@property (readonly, copy) NSDate *creationDate;
@property (readonly, copy) CKRecordID *lastModifiedUserRecordID;
@property (readonly, copy) NSDate *modificationDate;
- (id)objectForKey:(CKRecordFieldKey)key;
- (void)setObject:(id)object forKey:(CKRecordFieldKey)key;
- (id)objectForKeyedSubscript:(CKRecordFieldKey)key;
- (void)setObject:(id)object forKeyedSubscript:(CKRecordFieldKey)key;
- (NSArray<CKRecordFieldKey> *)allKeys;
- (NSArray<CKRecordFieldKey> *)changedKeys;
- (void)encodeSystemFieldsWithCoder:(NSCoder *)coder;
@end

@interface CKServerChangeToken : NSObject <NSCopying, NSSecureCoding>
@end

@interface CKNotificationInfo : NSObject <NSSecureCoding, NSCopying>
@property (copy) NSString *alertBody;
@property (copy) NSString *alertLocalizationKey;
@property (copy) NSArray<NSString *> *alertLocalizationArgs;
@property (copy) NSString *title;
@property (copy) NSString *subtitle;
@property (copy) NSString *alertActionLocalizationKey;
@property (copy) NSString *alertLaunchImage;
@property (copy) NSString *soundName;
@property (copy) NSArray<CKRecordFieldKey> *desiredKeys;
@property BOOL shouldBadge;
@property BOOL shouldSendContentAvailable;
@property BOOL shouldSendMutableContent;
@property (copy) NSString *category;
@property (copy) NSString *collapseIDKey;
@end

@interface CKSubscription : NSObject <NSSecureCoding, NSCopying>
@property (readonly, copy) CKSubscriptionID subscriptionID;
@property (readonly) CKSubscriptionType subscriptionType;
@property (copy) CKNotificationInfo *notificationInfo;
@end

@interface CKQuerySubscription : CKSubscription
- (instancetype)initWithRecordType:(CKRecordType)recordType predicate:(NSPredicate *)predicate
                           options:(CKQuerySubscriptionOptions)querySubscriptionOptions;
- (instancetype)initWithRecordType:(CKRecordType)recordType predicate:(NSPredicate *)predicate
                    subscriptionID:(CKSubscriptionID)subscriptionID
                           options:(CKQuerySubscriptionOptions)querySubscriptionOptions;
@property (readonly, copy) CKRecordType recordType;
@property (readonly, copy) NSPredicate *predicate;
@property (copy) CKRecordZoneID *zoneID;
@property (readonly) CKQuerySubscriptionOptions querySubscriptionOptions;
@end

@interface CKRecordZoneSubscription : CKSubscription
- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID;
- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID subscriptionID:(CKSubscriptionID)subscriptionID;
@property (readonly, copy) CKRecordZoneID *zoneID;
@property (copy) CKRecordType recordType;
@end

@interface CKDatabaseSubscription : CKSubscription
- (instancetype)initWithSubscriptionID:(CKSubscriptionID)subscriptionID;
@property (copy) CKRecordType recordType;
@end

@interface CKNotification : NSObject
+ (instancetype)notificationFromRemoteNotificationDictionary:(NSDictionary *)notificationDictionary;
@property (readonly) CKNotificationType notificationType;
@property (readonly, copy) NSString *containerIdentifier;
@property (readonly, copy) CKSubscriptionID subscriptionID;
@property (readonly) BOOL isPruned;
@end

@interface CKQuery : NSObject <NSSecureCoding, NSCopying>
- (instancetype)initWithRecordType:(CKRecordType)recordType predicate:(NSPredicate *)predicate;
@property (readonly, copy) CKRecordType recordType;
@property (readonly, copy) NSPredicate *predicate;
@property (copy) NSArray<NSSortDescriptor *> *sortDescriptors;
@end

@class CKDatabase;

@interface CKOperationConfiguration : NSObject <NSCopying>
@property (copy) NSString *container;
@property NSQualityOfService qualityOfService;
@property BOOL allowsCellularAccess;
@property BOOL longLived;
@property NSTimeInterval timeoutIntervalForRequest;
@property NSTimeInterval timeoutIntervalForResource;
@end

@interface CKOperation : NSOperation
@property (copy) CKOperationConfiguration *configuration;
@property (readonly, copy) NSString *operationID;
@property (copy) void (^longLivedOperationWasPersistedBlock)(void);
@end

@interface CKDatabaseOperation : CKOperation
@property (strong) CKDatabase *database;
@end

@interface CKModifyRecordZonesOperation : CKDatabaseOperation
- (instancetype)initWithRecordZonesToSave:(NSArray<CKRecordZone *> *)recordZonesToSave
                    recordZoneIDsToDelete:(NSArray<CKRecordZoneID *> *)recordZoneIDsToDelete;
@property (copy) NSArray<CKRecordZone *> *recordZonesToSave;
@property (copy) NSArray<CKRecordZoneID *> *recordZoneIDsToDelete;
@property (copy) void (^modifyRecordZonesCompletionBlock)(NSArray<CKRecordZone *> *savedRecordZones,
                                                          NSArray<CKRecordZoneID *> *deletedRecordZoneIDs,
                                                          NSError *operationError);
@end

@interface CKFetchRecordChangesOperation : CKDatabaseOperation
- (instancetype)initWithRecordZoneID:(CKRecordZoneID *)recordZoneID
           previousServerChangeToken:(CKServerChangeToken *)previousServerChangeToken;
@property (copy) CKRecordZoneID *recordZoneID;
@property (copy) CKServerChangeToken *previousServerChangeToken;
@property NSUInteger resultsLimit;
@property (copy) NSArray<CKRecordFieldKey> *desiredKeys;
@property (copy) void (^recordChangedBlock)(CKRecord *record);
@property (copy) void (^recordWithIDWasDeletedBlock)(CKRecordID *recordID);
@property (readonly) BOOL moreComing;
@property (copy) void (^fetchRecordChangesCompletionBlock)(CKServerChangeToken *serverChangeToken,
                                                           NSData *clientChangeTokenData, NSError *operationError);
@end

@interface CKModifyRecordsOperation : CKDatabaseOperation
- (instancetype)initWithRecordsToSave:(NSArray<CKRecord *> *)records recordIDsToDelete:(NSArray<CKRecordID *> *)recordIDs;
@property (copy) NSArray<CKRecord *> *recordsToSave;
@property (copy) NSArray<CKRecordID *> *recordIDsToDelete;
@property CKRecordSavePolicy savePolicy;
@property (copy) NSData *clientChangeTokenData;
@property BOOL atomic;
@property (copy) void (^perRecordProgressBlock)(CKRecord *record, double progress);
@property (copy) void (^perRecordCompletionBlock)(CKRecord *record, NSError *error);
@property (copy) void (^modifyRecordsCompletionBlock)(NSArray<CKRecord *> *savedRecords,
                                                      NSArray<CKRecordID *> *deletedRecordIDs, NSError *operationError);
@end

@interface CKFetchRecordsOperation : CKDatabaseOperation
- (instancetype)initWithRecordIDs:(NSArray<CKRecordID *> *)recordIDs;
+ (instancetype)fetchCurrentUserRecordOperation;
@property (copy) NSArray<CKRecordID *> *recordIDs;
@property (copy) NSArray<CKRecordFieldKey> *desiredKeys;
@property (copy) void (^perRecordCompletionBlock)(CKRecord *record, CKRecordID *recordID, NSError *error);
@property (copy) void (^fetchRecordsCompletionBlock)(NSDictionary<CKRecordID *, CKRecord *> *recordsByRecordID,
                                                     NSError *operationError);
@end

@interface CKQueryCursor : NSObject <NSCopying, NSSecureCoding>
@end

@interface CKQueryOperation : CKDatabaseOperation
- (instancetype)initWithQuery:(CKQuery *)query;
- (instancetype)initWithCursor:(CKQueryCursor *)cursor;
@property (copy) CKQuery *query;
@property (copy) CKQueryCursor *cursor;
@property (copy) CKRecordZoneID *zoneID;
@property NSUInteger resultsLimit;
@property (copy) NSArray<CKRecordFieldKey> *desiredKeys;
@property (copy) void (^recordFetchedBlock)(CKRecord *record);
@property (copy) void (^queryCompletionBlock)(CKQueryCursor *cursor, NSError *operationError);
@end

@interface CKModifySubscriptionsOperation : CKDatabaseOperation
- (instancetype)initWithSubscriptionsToSave:(NSArray<CKSubscription *> *)subscriptionsToSave
                    subscriptionIDsToDelete:(NSArray<CKSubscriptionID> *)subscriptionIDsToDelete;
@property (copy) NSArray<CKSubscription *> *subscriptionsToSave;
@property (copy) NSArray<CKSubscriptionID> *subscriptionIDsToDelete;
@property (copy) void (^modifySubscriptionsCompletionBlock)(NSArray<CKSubscription *> *savedSubscriptions,
                                                            NSArray<CKSubscriptionID> *deletedSubscriptionIDs,
                                                            NSError *operationError);
@end

@interface CKDatabase : NSObject
@property (readonly) CKDatabaseScope databaseScope;
- (void)addOperation:(CKDatabaseOperation *)operation;
- (void)fetchRecordWithID:(CKRecordID *)recordID completionHandler:(void (^)(CKRecord *record, NSError *error))handler;
- (void)saveRecord:(CKRecord *)record completionHandler:(void (^)(CKRecord *record, NSError *error))handler;
- (void)deleteRecordWithID:(CKRecordID *)recordID
         completionHandler:(void (^)(CKRecordID *recordID, NSError *error))handler;
- (void)performQuery:(CKQuery *)query inZoneWithID:(CKRecordZoneID *)zoneID
    completionHandler:(void (^)(NSArray<CKRecord *> *results, NSError *error))handler;
- (void)fetchAllRecordZonesWithCompletionHandler:(void (^)(NSArray<CKRecordZone *> *zones, NSError *error))handler;
- (void)fetchRecordZoneWithID:(CKRecordZoneID *)zoneID
            completionHandler:(void (^)(CKRecordZone *zone, NSError *error))handler;
- (void)saveRecordZone:(CKRecordZone *)zone completionHandler:(void (^)(CKRecordZone *zone, NSError *error))handler;
- (void)deleteRecordZoneWithID:(CKRecordZoneID *)zoneID
             completionHandler:(void (^)(CKRecordZoneID *zoneID, NSError *error))handler;
- (void)fetchSubscriptionWithID:(CKSubscriptionID)subscriptionID
              completionHandler:(void (^)(CKSubscription *subscription, NSError *error))handler;
- (void)fetchAllSubscriptionsWithCompletionHandler:(void (^)(NSArray<CKSubscription *> *subscriptions,
                                                             NSError *error))handler;
- (void)saveSubscription:(CKSubscription *)subscription
       completionHandler:(void (^)(CKSubscription *subscription, NSError *error))handler;
- (void)deleteSubscriptionWithID:(CKSubscriptionID)subscriptionID
               completionHandler:(void (^)(CKSubscriptionID subscriptionID, NSError *error))handler;
@end

@interface CKContainer : NSObject
+ (CKContainer *)defaultContainer;
+ (CKContainer *)containerWithIdentifier:(NSString *)containerIdentifier;
@property (readonly, copy) NSString *containerIdentifier;
@property (readonly, strong) CKDatabase *privateCloudDatabase;
@property (readonly, strong) CKDatabase *publicCloudDatabase;
@property (readonly, strong) CKDatabase *sharedCloudDatabase;
- (CKDatabase *)databaseWithDatabaseScope:(CKDatabaseScope)databaseScope;
- (void)addOperation:(CKOperation *)operation;
- (void)accountStatusWithCompletionHandler:(void (^)(CKAccountStatus accountStatus, NSError *error))handler;
- (void)fetchUserRecordIDWithCompletionHandler:(void (^)(CKRecordID *recordID, NSError *error))handler;
@end

#endif
