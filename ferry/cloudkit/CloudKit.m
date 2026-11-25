/* SPDX-License-Identifier: GPL-3.0-or-later
 * CloudKit with no iCloud account (sdk/include/CloudKit/CloudKit.h),
 * written for freemac from Apple's public CloudKit documentation.
 *
 * Records, identifiers, zones, subscriptions, queries and change tokens
 * are plain objects: they copy, compare, hash and archive. A container
 * reports CKAccountStatusNoAccount, and every request to one of its
 * databases ends with CKErrorNotAuthenticated, answered from a background
 * queue as CloudKit answers. Apps that sync through iCloud, such as
 * Flycut's preferences sync, see what a Mac signed out of iCloud shows
 * them and carry on with their local data. */
#import <CloudKit/CloudKit.h>
#import <dispatch/dispatch.h>
#include <stdlib.h>

NSString *const CKErrorDomain = @"CKErrorDomain";
NSString *const CKPartialErrorsByItemIDKey = @"CKPartialErrors";
NSString *const CKRecordChangedErrorAncestorRecordKey = @"AncestorRecord";
NSString *const CKRecordChangedErrorServerRecordKey = @"ServerRecord";
NSString *const CKRecordChangedErrorClientRecordKey = @"ClientRecord";
NSString *const CKErrorRetryAfterKey = @"CKRetryAfter";
NSString *const CKOwnerDefaultName = @"__defaultOwner__";
NSString *const CKCurrentUserDefaultName = @"__defaultOwner__";
NSString *const CKRecordZoneDefaultName = @"_defaultZone";
NSString *const CKAccountChangedNotification = @"CKAccountChangedNotificationToken";
NSString *const CKRecordTypeUserRecord = @"Users";
NSString *const CKRecordCreationDateKey = @"___createTime";
NSString *const CKRecordModificationDateKey = @"___modTime";
NSString *const CKRecordRecordIDKey = @"___recordID";

static void ck_note(void)
{
    static int said;
    const char *v = getenv("FERRY_VERBOSE");
    if (!said && v && *v) {
        said = 1;
        fprintf(stderr, "ferry: CloudKit: there is no iCloud account on freemac; requests end with "
                        "CKErrorNotAuthenticated\n");
    }
}

static NSError *ck_no_account(void)
{
    ck_note();
    return [NSError errorWithDomain:CKErrorDomain code:CKErrorNotAuthenticated
                           userInfo:@{NSLocalizedDescriptionKey : @"No iCloud account is signed in: freemac has no iCloud."}];
}

/* Answers come later and from elsewhere, as CloudKit's do. */
static void ck_later(void (^work)(void))
{
    dispatch_async(dispatch_get_global_queue(0, 0), work);
}

static BOOL same(id a, id b) { return a == b || [a isEqual:b]; }

@implementation NSString (CKRecordValue)
@end
@implementation NSNumber (CKRecordValue)
@end
@implementation NSArray (CKRecordValue)
@end
@implementation NSDate (CKRecordValue)
@end
@implementation NSData (CKRecordValue)
@end

@implementation CKRecordZoneID
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init { return [self initWithZoneName:CKRecordZoneDefaultName ownerName:CKOwnerDefaultName]; }
- (instancetype)initWithZoneName:(NSString *)zoneName ownerName:(NSString *)ownerName
{
    if ((self = [super init])) {
        _zoneName = [zoneName ?: CKRecordZoneDefaultName copy];
        _ownerName = [ownerName ?: CKOwnerDefaultName copy];
    }
    return self;
}
- (void)dealloc
{
    [_zoneName release];
    [_ownerName release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[CKRecordZoneID class]] && same(_zoneName, [o zoneName]) && same(_ownerName, [o ownerName]);
}
- (NSUInteger)hash { return [_zoneName hash] ^ ([_ownerName hash] << 1); }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_zoneName forKey:@"ZoneName"];
    [c encodeObject:_ownerName forKey:@"OwnerName"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithZoneName:[c decodeObjectOfClass:[NSString class] forKey:@"ZoneName"]
                        ownerName:[c decodeObjectOfClass:[NSString class] forKey:@"OwnerName"]];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecordZoneID: %p; zoneName=%@, ownerName=%@>", self, _zoneName, _ownerName];
}
@end

static CKRecordZoneID *default_zone_id(void)
{
    static CKRecordZoneID *zone;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ zone = [[CKRecordZoneID alloc] init]; });
    return zone;
}

@implementation CKRecordID
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithRecordName:(NSString *)recordName { return [self initWithRecordName:recordName zoneID:nil]; }
- (instancetype)initWithRecordName:(NSString *)recordName zoneID:(CKRecordZoneID *)zoneID
{
    if ((self = [super init])) {
        _recordName = [recordName ?: [[NSUUID UUID] UUIDString] copy];
        _zoneID = [zoneID ?: default_zone_id() retain];
    }
    return self;
}
- (instancetype)init { return [self initWithRecordName:nil zoneID:nil]; }
- (void)dealloc
{
    [_recordName release];
    [_zoneID release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[CKRecordID class]] && same(_recordName, [o recordName]) && same(_zoneID, [o zoneID]);
}
- (NSUInteger)hash { return [_recordName hash] ^ [_zoneID hash]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_recordName forKey:@"RecordName"];
    [c encodeObject:_zoneID forKey:@"ZoneID"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithRecordName:[c decodeObjectOfClass:[NSString class] forKey:@"RecordName"]
                             zoneID:[c decodeObjectOfClass:[CKRecordZoneID class] forKey:@"ZoneID"]];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecordID: %p; recordName=%@, zoneID=%@:%@>", self, _recordName,
                                      _zoneID.zoneName, _zoneID.ownerName];
}
@end

@implementation CKRecordZone
+ (BOOL)supportsSecureCoding { return YES; }
+ (CKRecordZone *)defaultRecordZone { return [[[self alloc] initWithZoneID:default_zone_id()] autorelease]; }
- (instancetype)initWithZoneName:(NSString *)zoneName
{
    CKRecordZoneID *zid = [[[CKRecordZoneID alloc] initWithZoneName:zoneName ownerName:CKOwnerDefaultName] autorelease];
    return [self initWithZoneID:zid];
}
- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID
{
    if ((self = [super init])) {
        _zoneID = [zoneID ?: default_zone_id() retain];
        _capabilities = [_zoneID isEqual:default_zone_id()]
                            ? 0
                            : CKRecordZoneCapabilityFetchChanges | CKRecordZoneCapabilityAtomic |
                                  CKRecordZoneCapabilitySharing;
    }
    return self;
}
- (void)dealloc
{
    [_zoneID release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[CKRecordZone class]] && same(_zoneID, [o zoneID]); }
- (NSUInteger)hash { return [_zoneID hash]; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:_zoneID forKey:@"ZoneID"]; }
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithZoneID:[c decodeObjectOfClass:[CKRecordZoneID class] forKey:@"ZoneID"]];
}
@end

@implementation CKReference
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithRecordID:(CKRecordID *)recordID action:(CKReferenceAction)action
{
    if ((self = [super init])) {
        _recordID = [recordID copy];
        _referenceAction = action;
    }
    return self;
}
- (void)dealloc
{
    [_recordID release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[CKReference class]] && same(_recordID, [o recordID]) &&
           _referenceAction == [o referenceAction];
}
- (NSUInteger)hash { return [_recordID hash] + _referenceAction; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_recordID forKey:@"RecordID"];
    [c encodeInteger:_referenceAction forKey:@"Action"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithRecordID:[c decodeObjectOfClass:[CKRecordID class] forKey:@"RecordID"]
                           action:[c decodeIntegerForKey:@"Action"]];
}
@end

@implementation CKAsset
- (instancetype)initWithFileURL:(NSURL *)fileURL
{
    if ((self = [super init]))
        _fileURL = [fileURL copy];
    return self;
}
- (void)dealloc
{
    [_fileURL release];
    [super dealloc];
}
@end

@implementation CKRecord {
    NSMutableDictionary *_values;
    NSMutableOrderedSet *_changed;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithRecordType:(CKRecordType)recordType
{
    return [self initWithRecordType:recordType recordID:[[[CKRecordID alloc] init] autorelease]];
}
- (instancetype)initWithRecordType:(CKRecordType)recordType zoneID:(CKRecordZoneID *)zoneID
{
    return [self initWithRecordType:recordType
                           recordID:[[[CKRecordID alloc] initWithRecordName:nil zoneID:zoneID] autorelease]];
}
- (instancetype)initWithRecordType:(CKRecordType)recordType recordID:(CKRecordID *)recordID
{
    if ((self = [super init])) {
        _recordType = [recordType copy];
        _recordID = [recordID ?: [[[CKRecordID alloc] init] autorelease] copy];
        _values = [[NSMutableDictionary alloc] init];
        _changed = [[NSMutableOrderedSet alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_recordType release];
    [_recordID release];
    [_recordChangeTag release];
    [_creatorUserRecordID release];
    [_creationDate release];
    [_lastModifiedUserRecordID release];
    [_modificationDate release];
    [_values release];
    [_changed release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    CKRecord *r = [[CKRecord alloc] initWithRecordType:_recordType recordID:_recordID];
    [r->_values setDictionary:_values];
    [r->_changed unionOrderedSet:_changed];
    r->_recordChangeTag = [_recordChangeTag copy];
    r->_creationDate = [_creationDate copy];
    r->_modificationDate = [_modificationDate copy];
    return r;
}
- (id)objectForKey:(CKRecordFieldKey)key { return [_values objectForKey:key]; }
- (void)setObject:(id)object forKey:(CKRecordFieldKey)key
{
    if (!key)
        return;
    if (object)
        [_values setObject:object forKey:key];
    else
        [_values removeObjectForKey:key];
    [_changed addObject:key];
}
- (id)objectForKeyedSubscript:(CKRecordFieldKey)key { return [self objectForKey:key]; }
- (void)setObject:(id)object forKeyedSubscript:(CKRecordFieldKey)key { [self setObject:object forKey:key]; }
- (id)valueForKey:(NSString *)key { return [_values objectForKey:key] ?: [super valueForKey:key]; }
- (void)setValue:(id)value forKey:(NSString *)key { [self setObject:value forKey:key]; }
- (NSArray *)allKeys { return [_values allKeys]; }
- (NSArray *)changedKeys { return [_changed array]; }
- (void)encodeSystemFieldsWithCoder:(NSCoder *)c
{
    [c encodeObject:_recordType forKey:@"RecordType"];
    [c encodeObject:_recordID forKey:@"RecordID"];
    if (_recordChangeTag)
        [c encodeObject:_recordChangeTag forKey:@"ETag"];
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [self encodeSystemFieldsWithCoder:c];
    [c encodeObject:_values forKey:@"Values"];
    [c encodeObject:[_changed array] forKey:@"ChangedKeys"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    self = [self initWithRecordType:[c decodeObjectOfClass:[NSString class] forKey:@"RecordType"]
                           recordID:[c decodeObjectOfClass:[CKRecordID class] forKey:@"RecordID"]];
    if (self) {
        _recordChangeTag = [[c decodeObjectOfClass:[NSString class] forKey:@"ETag"] copy];
        NSDictionary *values = [c decodeObjectForKey:@"Values"];
        if ([values isKindOfClass:[NSDictionary class]])
            [_values setDictionary:values];
        NSArray *changed = [c decodeObjectForKey:@"ChangedKeys"];
        if ([changed isKindOfClass:[NSArray class]])
            [_changed addObjectsFromArray:changed];
    }
    return self;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CKRecord: %p; recordType=%@, recordID=%@, values=%@>", self, _recordType,
                                      _recordID.recordName, _values];
}
@end

@implementation CKServerChangeToken {
    NSData *_data;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc
{
    [_data release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[CKServerChangeToken class]] && same(_data, ((CKServerChangeToken *)o)->_data);
}
- (NSUInteger)hash { return [_data hash]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    if (_data)
        [c encodeObject:_data forKey:@"Data"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init]))
        _data = [[c decodeObjectOfClass:[NSData class] forKey:@"Data"] copy];
    return self;
}
@end

@implementation CKQueryCursor
+ (BOOL)supportsSecureCoding { return YES; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (void)encodeWithCoder:(NSCoder *)c
{
}
- (instancetype)initWithCoder:(NSCoder *)c { return [super init]; }
@end

@implementation CKNotificationInfo
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc
{
    [_alertBody release];
    [_alertLocalizationKey release];
    [_alertLocalizationArgs release];
    [_title release];
    [_subtitle release];
    [_alertActionLocalizationKey release];
    [_alertLaunchImage release];
    [_soundName release];
    [_desiredKeys release];
    [_category release];
    [_collapseIDKey release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    CKNotificationInfo *n = [[CKNotificationInfo alloc] init];
    n.alertBody = _alertBody;
    n.alertLocalizationKey = _alertLocalizationKey;
    n.alertLocalizationArgs = _alertLocalizationArgs;
    n.title = _title;
    n.subtitle = _subtitle;
    n.alertActionLocalizationKey = _alertActionLocalizationKey;
    n.alertLaunchImage = _alertLaunchImage;
    n.soundName = _soundName;
    n.desiredKeys = _desiredKeys;
    n.shouldBadge = _shouldBadge;
    n.shouldSendContentAvailable = _shouldSendContentAvailable;
    n.shouldSendMutableContent = _shouldSendMutableContent;
    n.category = _category;
    n.collapseIDKey = _collapseIDKey;
    return n;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_alertBody forKey:@"AlertBody"];
    [c encodeObject:_soundName forKey:@"SoundName"];
    [c encodeObject:_desiredKeys forKey:@"DesiredKeys"];
    [c encodeBool:_shouldBadge forKey:@"ShouldBadge"];
    [c encodeBool:_shouldSendContentAvailable forKey:@"ContentAvailable"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        self.alertBody = [c decodeObjectForKey:@"AlertBody"];
        self.soundName = [c decodeObjectForKey:@"SoundName"];
        self.desiredKeys = [c decodeObjectForKey:@"DesiredKeys"];
        _shouldBadge = [c decodeBoolForKey:@"ShouldBadge"];
        _shouldSendContentAvailable = [c decodeBoolForKey:@"ContentAvailable"];
    }
    return self;
}
@end

@implementation CKSubscription {
@protected
    NSString *_ckSubscriptionID;
    CKSubscriptionType _ckType;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)_initWithID:(NSString *)subscriptionID type:(CKSubscriptionType)type
{
    if ((self = [super init])) {
        _ckSubscriptionID = [subscriptionID ?: [[NSUUID UUID] UUIDString] copy];
        _ckType = type;
    }
    return self;
}
- (void)dealloc
{
    [_ckSubscriptionID release];
    [_notificationInfo release];
    [super dealloc];
}
- (NSString *)subscriptionID { return _ckSubscriptionID; }
- (CKSubscriptionType)subscriptionType { return _ckType; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[CKSubscription class]] && same(_ckSubscriptionID, [o subscriptionID]);
}
- (NSUInteger)hash { return [_ckSubscriptionID hash]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_ckSubscriptionID forKey:@"SubscriptionID"];
    [c encodeInteger:_ckType forKey:@"Type"];
    if (_notificationInfo)
        [c encodeObject:_notificationInfo forKey:@"NotificationInfo"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    self = [self _initWithID:[c decodeObjectOfClass:[NSString class] forKey:@"SubscriptionID"]
                        type:[c decodeIntegerForKey:@"Type"]];
    if (self)
        _notificationInfo = [[c decodeObjectOfClass:[CKNotificationInfo class] forKey:@"NotificationInfo"] copy];
    return self;
}
@end

@implementation CKQuerySubscription
- (instancetype)initWithRecordType:(CKRecordType)recordType predicate:(NSPredicate *)predicate
                           options:(CKQuerySubscriptionOptions)options
{
    return [self initWithRecordType:recordType predicate:predicate subscriptionID:nil options:options];
}
- (instancetype)initWithRecordType:(CKRecordType)recordType predicate:(NSPredicate *)predicate
                    subscriptionID:(CKSubscriptionID)subscriptionID
                           options:(CKQuerySubscriptionOptions)options
{
    if ((self = [super _initWithID:subscriptionID type:CKSubscriptionTypeQuery])) {
        _recordType = [recordType copy];
        _predicate = [predicate copy];
        _querySubscriptionOptions = options;
    }
    return self;
}
- (void)dealloc
{
    [_recordType release];
    [_predicate release];
    [_zoneID release];
    [super dealloc];
}
@end

@implementation CKRecordZoneSubscription
- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID { return [self initWithZoneID:zoneID subscriptionID:nil]; }
- (instancetype)initWithZoneID:(CKRecordZoneID *)zoneID subscriptionID:(CKSubscriptionID)subscriptionID
{
    if ((self = [super _initWithID:subscriptionID type:CKSubscriptionTypeRecordZone]))
        _zoneID = [zoneID copy];
    return self;
}
- (void)dealloc
{
    [_zoneID release];
    [_recordType release];
    [super dealloc];
}
@end

@implementation CKDatabaseSubscription
- (instancetype)init { return [self initWithSubscriptionID:nil]; }
- (instancetype)initWithSubscriptionID:(CKSubscriptionID)subscriptionID
{
    return [super _initWithID:subscriptionID type:CKSubscriptionTypeDatabase];
}
- (void)dealloc
{
    [_recordType release];
    [super dealloc];
}
@end

@implementation CKNotification
/* No push service delivers CloudKit notifications here; a dictionary an
 * app hands in still gives its subscription and kind, from the "ck" part
 * CloudKit's documentation describes. */
+ (instancetype)notificationFromRemoteNotificationDictionary:(NSDictionary *)dict
{
    NSDictionary *ck = [dict objectForKey:@"ck"];
    if (![ck isKindOfClass:[NSDictionary class]])
        return nil;
    CKNotification *n = [[[self alloc] init] autorelease];
    n->_containerIdentifier = [[ck objectForKey:@"cid"] copy];
    NSDictionary *part = nil;
    if ((part = [ck objectForKey:@"qry"]))
        n->_notificationType = CKNotificationTypeQuery;
    else if ((part = [ck objectForKey:@"fet"]))
        n->_notificationType = CKNotificationTypeRecordZone;
    else if ((part = [ck objectForKey:@"met"]))
        n->_notificationType = CKNotificationTypeDatabase;
    else
        n->_notificationType = CKNotificationTypeReadNotification;
    if ([part isKindOfClass:[NSDictionary class]])
        n->_subscriptionID = [[part objectForKey:@"sid"] copy];
    return n;
}
- (void)dealloc
{
    [_containerIdentifier release];
    [_subscriptionID release];
    [super dealloc];
}
@end

@implementation CKQuery
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithRecordType:(CKRecordType)recordType predicate:(NSPredicate *)predicate
{
    if ((self = [super init])) {
        _recordType = [recordType copy];
        _predicate = [predicate copy];
    }
    return self;
}
- (void)dealloc
{
    [_recordType release];
    [_predicate release];
    [_sortDescriptors release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    CKQuery *q = [[CKQuery alloc] initWithRecordType:_recordType predicate:_predicate];
    q.sortDescriptors = _sortDescriptors;
    return q;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_recordType forKey:@"RecordType"];
    [c encodeObject:_sortDescriptors forKey:@"SortDescriptors"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    self = [self initWithRecordType:[c decodeObjectForKey:@"RecordType"] predicate:[NSPredicate predicateWithValue:YES]];
    if (self)
        self.sortDescriptors = [c decodeObjectForKey:@"SortDescriptors"];
    return self;
}
@end

@implementation CKOperationConfiguration
- (instancetype)init
{
    if ((self = [super init])) {
        _qualityOfService = NSQualityOfServiceDefault;
        _allowsCellularAccess = YES;
        _timeoutIntervalForRequest = 60;
        _timeoutIntervalForResource = 7 * 24 * 3600;
    }
    return self;
}
- (void)dealloc
{
    [_container release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    CKOperationConfiguration *c = [[CKOperationConfiguration alloc] init];
    c.container = _container;
    c.qualityOfService = _qualityOfService;
    c.allowsCellularAccess = _allowsCellularAccess;
    c.longLived = _longLived;
    c.timeoutIntervalForRequest = _timeoutIntervalForRequest;
    c.timeoutIntervalForResource = _timeoutIntervalForResource;
    return c;
}
@end

static NSOperationQueue *ck_queue(void)
{
    static NSOperationQueue *queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = [[NSOperationQueue alloc] init];
        [queue setName:@"CloudKit"];
    });
    return queue;
}

@implementation CKOperation {
    NSString *_ckOperationID;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _configuration = [[CKOperationConfiguration alloc] init];
        _ckOperationID = [[[NSUUID UUID] UUIDString] copy];
    }
    return self;
}
- (void)dealloc
{
    [_configuration release];
    [_ckOperationID release];
    [_longLivedOperationWasPersistedBlock release];
    [super dealloc];
}
- (NSString *)operationID { return _ckOperationID; }
/* Each kind of operation tells its blocks that it failed. */
- (void)_ferryFail:(NSError *)error
{
}
/* A cancelled operation still tells its blocks, with CKErrorOperationCancelled,
 * though NSOperation runs no main for it. */
- (void)start
{
    if ([self isCancelled] && ![self isFinished] && ![self isExecuting])
        [self _ferryFail:[NSError errorWithDomain:CKErrorDomain code:CKErrorOperationCancelled userInfo:nil]];
    [super start];
}
- (void)main
{
    [self _ferryFail:[self isCancelled] ? [NSError errorWithDomain:CKErrorDomain code:CKErrorOperationCancelled
                                                           userInfo:nil]
                                         : ck_no_account()];
}
@end

@implementation CKDatabaseOperation
- (void)dealloc
{
    [_database release];
    [super dealloc];
}
@end

@implementation CKModifyRecordZonesOperation
- (instancetype)initWithRecordZonesToSave:(NSArray *)save recordZoneIDsToDelete:(NSArray *)del
{
    if ((self = [super init])) {
        _recordZonesToSave = [save copy];
        _recordZoneIDsToDelete = [del copy];
    }
    return self;
}
- (void)dealloc
{
    [_recordZonesToSave release];
    [_recordZoneIDsToDelete release];
    [_modifyRecordZonesCompletionBlock release];
    [super dealloc];
}
- (void)_ferryFail:(NSError *)error
{
    if (_modifyRecordZonesCompletionBlock)
        _modifyRecordZonesCompletionBlock(nil, nil, error);
}
@end

@implementation CKFetchRecordChangesOperation
- (instancetype)initWithRecordZoneID:(CKRecordZoneID *)zoneID previousServerChangeToken:(CKServerChangeToken *)token
{
    if ((self = [super init])) {
        _recordZoneID = [zoneID copy];
        _previousServerChangeToken = [token copy];
    }
    return self;
}
- (void)dealloc
{
    [_recordZoneID release];
    [_previousServerChangeToken release];
    [_desiredKeys release];
    [_recordChangedBlock release];
    [_recordWithIDWasDeletedBlock release];
    [_fetchRecordChangesCompletionBlock release];
    [super dealloc];
}
- (void)_ferryFail:(NSError *)error
{
    if (_fetchRecordChangesCompletionBlock)
        _fetchRecordChangesCompletionBlock(nil, nil, error);
}
@end

@implementation CKModifyRecordsOperation
- (instancetype)initWithRecordsToSave:(NSArray *)records recordIDsToDelete:(NSArray *)recordIDs
{
    if ((self = [super init])) {
        _recordsToSave = [records copy];
        _recordIDsToDelete = [recordIDs copy];
        _atomic = YES;
    }
    return self;
}
- (void)dealloc
{
    [_recordsToSave release];
    [_recordIDsToDelete release];
    [_clientChangeTokenData release];
    [_perRecordProgressBlock release];
    [_perRecordCompletionBlock release];
    [_modifyRecordsCompletionBlock release];
    [super dealloc];
}
- (void)_ferryFail:(NSError *)error
{
    if (_perRecordCompletionBlock)
        for (CKRecord *r in _recordsToSave)
            _perRecordCompletionBlock(r, error);
    if (_modifyRecordsCompletionBlock)
        _modifyRecordsCompletionBlock(nil, nil, error);
}
@end

@implementation CKFetchRecordsOperation
+ (instancetype)fetchCurrentUserRecordOperation { return [[[self alloc] initWithRecordIDs:@[]] autorelease]; }
- (instancetype)initWithRecordIDs:(NSArray *)recordIDs
{
    if ((self = [super init]))
        _recordIDs = [recordIDs copy];
    return self;
}
- (void)dealloc
{
    [_recordIDs release];
    [_desiredKeys release];
    [_perRecordCompletionBlock release];
    [_fetchRecordsCompletionBlock release];
    [super dealloc];
}
- (void)_ferryFail:(NSError *)error
{
    if (_perRecordCompletionBlock)
        for (CKRecordID *r in _recordIDs)
            _perRecordCompletionBlock(nil, r, error);
    if (_fetchRecordsCompletionBlock)
        _fetchRecordsCompletionBlock(nil, error);
}
@end

@implementation CKQueryOperation
- (instancetype)initWithQuery:(CKQuery *)query
{
    if ((self = [super init]))
        _query = [query copy];
    return self;
}
- (instancetype)initWithCursor:(CKQueryCursor *)cursor
{
    if ((self = [super init]))
        _cursor = [cursor copy];
    return self;
}
- (void)dealloc
{
    [_query release];
    [_cursor release];
    [_zoneID release];
    [_desiredKeys release];
    [_recordFetchedBlock release];
    [_queryCompletionBlock release];
    [super dealloc];
}
- (void)_ferryFail:(NSError *)error
{
    if (_queryCompletionBlock)
        _queryCompletionBlock(nil, error);
}
@end

@implementation CKModifySubscriptionsOperation
- (instancetype)initWithSubscriptionsToSave:(NSArray *)save subscriptionIDsToDelete:(NSArray *)del
{
    if ((self = [super init])) {
        _subscriptionsToSave = [save copy];
        _subscriptionIDsToDelete = [del copy];
    }
    return self;
}
- (void)dealloc
{
    [_subscriptionsToSave release];
    [_subscriptionIDsToDelete release];
    [_modifySubscriptionsCompletionBlock release];
    [super dealloc];
}
- (void)_ferryFail:(NSError *)error
{
    if (_modifySubscriptionsCompletionBlock)
        _modifySubscriptionsCompletionBlock(nil, nil, error);
}
@end

@implementation CKDatabase
- (instancetype)_initWithScope:(CKDatabaseScope)scope
{
    if ((self = [super init]))
        _databaseScope = scope;
    return self;
}
- (void)addOperation:(CKDatabaseOperation *)operation
{
    operation.database = self;
    [ck_queue() addOperation:operation];
}
/* A copied block keeps the handler and the error it captures. */
#define FAIL(...)                                                                                                      \
    do {                                                                                                               \
        NSError *e = ck_no_account();                                                                                  \
        if (handler)                                                                                                   \
            ck_later(^{ __VA_ARGS__; });                                                                               \
    } while (0)
- (void)fetchRecordWithID:(CKRecordID *)recordID completionHandler:(void (^)(CKRecord *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)saveRecord:(CKRecord *)record completionHandler:(void (^)(CKRecord *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)deleteRecordWithID:(CKRecordID *)recordID completionHandler:(void (^)(CKRecordID *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)performQuery:(CKQuery *)query inZoneWithID:(CKRecordZoneID *)zoneID
    completionHandler:(void (^)(NSArray<CKRecord *> *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)fetchAllRecordZonesWithCompletionHandler:(void (^)(NSArray<CKRecordZone *> *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)fetchRecordZoneWithID:(CKRecordZoneID *)zoneID completionHandler:(void (^)(CKRecordZone *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)saveRecordZone:(CKRecordZone *)zone completionHandler:(void (^)(CKRecordZone *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)deleteRecordZoneWithID:(CKRecordZoneID *)zoneID completionHandler:(void (^)(CKRecordZoneID *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)fetchSubscriptionWithID:(CKSubscriptionID)subscriptionID
              completionHandler:(void (^)(CKSubscription *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)fetchAllSubscriptionsWithCompletionHandler:(void (^)(NSArray<CKSubscription *> *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)saveSubscription:(CKSubscription *)subscription completionHandler:(void (^)(CKSubscription *, NSError *))handler
{
    FAIL(handler(nil, e));
}
- (void)deleteSubscriptionWithID:(CKSubscriptionID)subscriptionID
               completionHandler:(void (^)(CKSubscriptionID, NSError *))handler
{
    FAIL(handler(nil, e));
}
#undef FAIL
@end

@implementation CKContainer {
    CKDatabase *_private, *_public, *_shared;
}
+ (CKContainer *)defaultContainer
{
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName];
    return [self containerWithIdentifier:[@"iCloud." stringByAppendingString:bundle]];
}
+ (CKContainer *)containerWithIdentifier:(NSString *)identifier
{
    static NSMutableDictionary *containers;
    @synchronized(self) {
        if (!containers)
            containers = [[NSMutableDictionary alloc] init];
        CKContainer *c = [containers objectForKey:identifier];
        if (!c && identifier) {
            c = [[[CKContainer alloc] _initWithIdentifier:identifier] autorelease];
            [containers setObject:c forKey:identifier];
        }
        return c;
    }
}
- (instancetype)_initWithIdentifier:(NSString *)identifier
{
    if ((self = [super init])) {
        _containerIdentifier = [identifier copy];
        _private = [[CKDatabase alloc] _initWithScope:CKDatabaseScopePrivate];
        _public = [[CKDatabase alloc] _initWithScope:CKDatabaseScopePublic];
        _shared = [[CKDatabase alloc] _initWithScope:CKDatabaseScopeShared];
    }
    return self;
}
- (void)dealloc
{
    [_containerIdentifier release];
    [_private release];
    [_public release];
    [_shared release];
    [super dealloc];
}
- (CKDatabase *)privateCloudDatabase { return _private; }
- (CKDatabase *)publicCloudDatabase { return _public; }
- (CKDatabase *)sharedCloudDatabase { return _shared; }
- (CKDatabase *)databaseWithDatabaseScope:(CKDatabaseScope)scope
{
    switch (scope) {
    case CKDatabaseScopePublic: return _public;
    case CKDatabaseScopeShared: return _shared;
    default: return _private;
    }
}
- (void)addOperation:(CKOperation *)operation
{
    if ([operation isKindOfClass:[CKDatabaseOperation class]] && ![(CKDatabaseOperation *)operation database])
        [(CKDatabaseOperation *)operation setDatabase:_private];
    [ck_queue() addOperation:operation];
}
- (void)accountStatusWithCompletionHandler:(void (^)(CKAccountStatus, NSError *))handler
{
    void (^h)(CKAccountStatus, NSError *) = [[handler copy] autorelease];
    if (h)
        ck_later(^{ h(CKAccountStatusNoAccount, nil); });
}
- (void)fetchUserRecordIDWithCompletionHandler:(void (^)(CKRecordID *, NSError *))handler
{
    void (^h)(CKRecordID *, NSError *) = [[handler copy] autorelease];
    NSError *e = ck_no_account();
    if (h)
        ck_later(^{ h(nil, e); });
}
@end
