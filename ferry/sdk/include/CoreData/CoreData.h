/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Core Data (coredata/), Ferry's own, written for freemac from
 * Apple's public documentation (the Core Data Programming Guide and the
 * class references); not Apple's header (freemac 1.NEXT, Ferry 0.NEXT).
 *
 * Models are built in code, or read from the XML source of an Xcode
 * model (a .xcdatamodeld or .xcdatamodel folder); compiled .mom and .momd
 * models aren't read. Stores are SQLite (this system's SQLite, in Ferry's
 * own table layout), binary (keyed archives) and in memory. */
#ifndef _FERRY_COREDATA_H_
#define _FERRY_COREDATA_H_
#include <Foundation/Foundation.h>

#define COREDATA_EXTERN extern __attribute__((visibility("default")))

@class NSManagedObjectContext, NSManagedObjectModel, NSEntityDescription, NSPersistentStoreCoordinator,
    NSPersistentStore, NSManagedObject, NSManagedObjectID, NSFetchRequest, NSPropertyDescription,
    NSAttributeDescription, NSRelationshipDescription, NSPersistentStoreDescription, NSMergePolicy;

/* ---- errors (in NSCocoaErrorDomain) ---------------------------------------------------- */

enum {
    NSManagedObjectValidationError = 1550,
    NSManagedObjectConstraintValidationError = 1551,
    NSValidationMultipleErrorsError = 1560,
    NSValidationMissingMandatoryPropertyError = 1570,
    NSValidationRelationshipLacksMinimumCountError = 1580,
    NSValidationRelationshipExceedsMaximumCountError = 1590,
    NSValidationRelationshipDeniedDeleteError = 1600,
    NSValidationNumberTooLargeError = 1610,
    NSValidationNumberTooSmallError = 1620,
    NSValidationDateTooLateError = 1630,
    NSValidationDateTooSoonError = 1640,
    NSValidationInvalidDateError = 1650,
    NSValidationStringTooLongError = 1660,
    NSValidationStringTooShortError = 1670,
    NSValidationStringPatternMatchingError = 1680,
    NSValidationInvalidURIError = 1690,
    NSManagedObjectContextLockingError = 132000,
    NSPersistentStoreCoordinatorLockingError = 132010,
    NSManagedObjectReferentialIntegrityError = 133000,
    NSManagedObjectExternalRelationshipError = 133010,
    NSManagedObjectMergeError = 133020,
    NSManagedObjectConstraintMergeError = 133021,
    NSPersistentStoreInvalidTypeError = 134000,
    NSPersistentStoreTypeMismatchError = 134010,
    NSPersistentStoreIncompatibleSchemaError = 134020,
    NSPersistentStoreSaveError = 134030,
    NSPersistentStoreIncompleteSaveError = 134040,
    NSPersistentStoreSaveConflictsError = 134050,
    NSCoreDataError = 134060,
    NSPersistentStoreOperationError = 134070,
    NSPersistentStoreOpenError = 134080,
    NSPersistentStoreTimeoutError = 134090,
    NSPersistentStoreUnsupportedRequestTypeError = 134091,
    NSPersistentStoreIncompatibleVersionHashError = 134100,
    NSMigrationError = 134110,
    NSMigrationConstraintViolationError = 134111,
    NSMigrationCancelledError = 134120,
    NSMigrationMissingSourceModelError = 134130,
    NSMigrationMissingMappingModelError = 134140,
    NSMigrationManagerSourceStoreError = 134150,
    NSMigrationManagerDestinationStoreError = 134160,
    NSEntityMigrationPolicyError = 134170,
    NSSQLiteError = 134180,
    NSInferredMappingModelError = 134190,
    NSExternalRecordImportError = 134200,
};

COREDATA_EXTERN NSString *const NSDetailedErrorsKey;
COREDATA_EXTERN NSString *const NSValidationObjectErrorKey;
COREDATA_EXTERN NSString *const NSValidationKeyErrorKey;
COREDATA_EXTERN NSString *const NSValidationPredicateErrorKey;
COREDATA_EXTERN NSString *const NSValidationValueErrorKey;
COREDATA_EXTERN NSString *const NSAffectedStoresErrorKey;
COREDATA_EXTERN NSString *const NSAffectedObjectsErrorKey;
COREDATA_EXTERN NSString *const NSPersistentStoreSaveConflictsErrorKey;
COREDATA_EXTERN NSString *const NSSQLiteErrorDomain;

/* ---- the model --------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSAttributeType) {
    NSUndefinedAttributeType = 0,
    NSInteger16AttributeType = 100,
    NSInteger32AttributeType = 200,
    NSInteger64AttributeType = 300,
    NSDecimalAttributeType = 400,
    NSDoubleAttributeType = 500,
    NSFloatAttributeType = 600,
    NSStringAttributeType = 700,
    NSBooleanAttributeType = 800,
    NSDateAttributeType = 900,
    NSBinaryDataAttributeType = 1000,
    NSUUIDAttributeType = 1100,
    NSURIAttributeType = 1200,
    NSTransformableAttributeType = 1800,
    NSObjectIDAttributeType = 2000,
};

typedef NS_ENUM(NSUInteger, NSDeleteRule) {
    NSNoActionDeleteRule = 0,
    NSNullifyDeleteRule = 1,
    NSCascadeDeleteRule = 2,
    NSDenyDeleteRule = 3,
};

@interface NSManagedObjectModel : NSObject <NSCoding, NSCopying, NSFastEnumeration>
+ (NSManagedObjectModel *)mergedModelFromBundles:(NSArray<NSBundle *> *)bundles;
+ (NSManagedObjectModel *)mergedModelFromBundles:(NSArray<NSBundle *> *)bundles
                                 forStoreMetadata:(NSDictionary<NSString *, id> *)metadata;
+ (NSManagedObjectModel *)modelByMergingModels:(NSArray<NSManagedObjectModel *> *)models;
+ (NSManagedObjectModel *)modelByMergingModels:(NSArray<NSManagedObjectModel *> *)models
                              forStoreMetadata:(NSDictionary<NSString *, id> *)metadata;
- (instancetype)init;
- (instancetype)initWithContentsOfURL:(NSURL *)url;
@property (readonly, copy) NSDictionary<NSString *, NSEntityDescription *> *entitiesByName;
@property (strong) NSArray<NSEntityDescription *> *entities;
@property (readonly, strong) NSArray<NSString *> *configurations;
- (NSArray<NSEntityDescription *> *)entitiesForConfiguration:(NSString *)configuration;
- (void)setEntities:(NSArray<NSEntityDescription *> *)entities forConfiguration:(NSString *)configuration;
- (void)setFetchRequestTemplate:(NSFetchRequest *)fetchRequestTemplate forName:(NSString *)name;
- (NSFetchRequest *)fetchRequestTemplateForName:(NSString *)name;
- (NSFetchRequest *)fetchRequestFromTemplateWithName:(NSString *)name
                               substitutionVariables:(NSDictionary<NSString *, id> *)variables;
@property (readonly, copy) NSDictionary<NSString *, NSFetchRequest *> *fetchRequestTemplatesByName;
@property (strong) NSDictionary<NSString *, NSString *> *localizationDictionary;
@property (copy) NSSet *versionIdentifiers;
- (BOOL)isConfiguration:(NSString *)configuration compatibleWithStoreMetadata:(NSDictionary<NSString *, id> *)metadata;
@property (readonly, copy) NSDictionary<NSString *, NSData *> *entityVersionHashesByName;
@end

@interface NSEntityDescription : NSObject <NSCoding, NSCopying, NSFastEnumeration>
+ (NSEntityDescription *)entityForName:(NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)context;
+ (__kindof NSManagedObject *)insertNewObjectForEntityForName:(NSString *)entityName
                                       inManagedObjectContext:(NSManagedObjectContext *)context;
@property (readonly, assign) NSManagedObjectModel *managedObjectModel;
@property (copy) NSString *managedObjectClassName;
@property (copy) NSString *name;
@property (getter=isAbstract) BOOL abstract;
@property (readonly, copy) NSDictionary<NSString *, NSEntityDescription *> *subentitiesByName;
@property (strong) NSArray<NSEntityDescription *> *subentities;
@property (readonly, assign) NSEntityDescription *superentity;
@property (readonly, copy) NSDictionary<NSString *, __kindof NSPropertyDescription *> *propertiesByName;
@property (strong) NSArray<__kindof NSPropertyDescription *> *properties;
@property (strong) NSDictionary *userInfo;
@property (readonly, copy) NSDictionary<NSString *, NSAttributeDescription *> *attributesByName;
@property (readonly, copy) NSDictionary<NSString *, NSRelationshipDescription *> *relationshipsByName;
- (NSArray<NSRelationshipDescription *> *)relationshipsWithDestinationEntity:(NSEntityDescription *)entity;
- (BOOL)isKindOfEntity:(NSEntityDescription *)entity;
@property (readonly, copy) NSData *versionHash;
@property (copy) NSString *versionHashModifier;
@property (copy) NSString *renamingIdentifier;
@property (strong) NSArray<NSArray *> *uniquenessConstraints;
@property (strong) NSArray *indexes;
@end

@interface NSPropertyDescription : NSObject <NSCoding, NSCopying>
@property (readonly, assign) NSEntityDescription *entity;
@property (copy) NSString *name;
@property (getter=isOptional) BOOL optional;
@property (getter=isTransient) BOOL transient;
@property (readonly, strong) NSArray<NSPredicate *> *validationPredicates;
@property (readonly, strong) NSArray *validationWarnings;
- (void)setValidationPredicates:(NSArray<NSPredicate *> *)validationPredicates
         withValidationWarnings:(NSArray<NSString *> *)validationWarnings;
@property (strong) NSDictionary *userInfo;
@property (getter=isIndexed) BOOL indexed;
@property (getter=isIndexedBySpotlight) BOOL indexedBySpotlight;
@property (readonly, copy) NSData *versionHash;
@property (copy) NSString *versionHashModifier;
@property (copy) NSString *renamingIdentifier;
@end

@interface NSAttributeDescription : NSPropertyDescription
@property NSAttributeType attributeType;
@property (copy) NSString *attributeValueClassName;
@property (retain) id defaultValue;
@property (copy) NSString *valueTransformerName;
@property BOOL allowsExternalBinaryDataStorage;
@property BOOL preservesValueInHistoryOnDeletion;
@property BOOL allowsCloudEncryption;
@end

@interface NSRelationshipDescription : NSPropertyDescription
@property (assign) NSEntityDescription *destinationEntity;
@property (assign) NSRelationshipDescription *inverseRelationship;
@property NSUInteger maxCount;
@property NSUInteger minCount;
@property NSDeleteRule deleteRule;
@property (readonly, getter=isToMany) BOOL toMany;
@property (getter=isOrdered) BOOL ordered;
@end

/* ---- object IDs and objects --------------------------------------------------------- */

@protocol NSFetchRequestResult <NSObject>
@end
@interface NSNumber (NSFetchRequestResult) <NSFetchRequestResult>
@end
@interface NSDictionary (NSFetchRequestResult) <NSFetchRequestResult>
@end

@interface NSManagedObjectID : NSObject <NSCopying, NSFetchRequestResult>
@property (readonly, strong) NSEntityDescription *entity;
@property (readonly, weak) NSPersistentStore *persistentStore;
@property (readonly, getter=isTemporaryID) BOOL temporaryID;
- (NSURL *)URIRepresentation;
@end

typedef NS_OPTIONS(NSUInteger, NSSnapshotEventType) {
    NSSnapshotEventUndoInsertion = 1 << 1,
    NSSnapshotEventUndoDeletion = 1 << 2,
    NSSnapshotEventUndoUpdate = 1 << 3,
    NSSnapshotEventRollback = 1 << 4,
    NSSnapshotEventRefresh = 1 << 5,
    NSSnapshotEventMergePolicy = 1 << 6,
};

/* A record of an entity. Properties declared @dynamic in a subclass get
 * accessors made when they are first used: getters and setters (objects
 * or scalars, as the property is declared), primitive<Key> and
 * setPrimitive<Key>:, and the to-many add<Key>Object:, remove<Key>Object:,
 * add<Key>:, remove<Key>: and, for ordered relationships, the indexed ones. */
@interface NSManagedObject : NSObject <NSFetchRequestResult>
+ (BOOL)contextShouldIgnoreUnmodeledPropertyChanges;
+ (NSEntityDescription *)entity;
+ (NSFetchRequest *)fetchRequest;
- (__kindof NSManagedObject *)initWithEntity:(NSEntityDescription *)entity
              insertIntoManagedObjectContext:(NSManagedObjectContext *)context;
- (instancetype)initWithContext:(NSManagedObjectContext *)moc;
@property (readonly, assign) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong) NSEntityDescription *entity;
@property (readonly, strong) NSManagedObjectID *objectID;
@property (readonly, getter=isInserted) BOOL inserted;
@property (readonly, getter=isUpdated) BOOL updated;
@property (readonly, getter=isDeleted) BOOL deleted;
@property (readonly) BOOL hasChanges;
@property (readonly) BOOL hasPersistentChangedValues;
@property (readonly, getter=isFault) BOOL fault;
- (BOOL)hasFaultForRelationshipNamed:(NSString *)key;
- (NSArray<NSManagedObjectID *> *)objectIDsForRelationshipNamed:(NSString *)key;
@property (readonly) NSUInteger faultingState;
- (void)willAccessValueForKey:(NSString *)key;
- (void)didAccessValueForKey:(NSString *)key;
- (void)awakeFromFetch;
- (void)awakeFromInsert;
- (void)awakeFromSnapshotEvents:(NSSnapshotEventType)flags;
- (void)prepareForDeletion;
- (void)willSave;
- (void)didSave;
- (void)willTurnIntoFault;
- (void)didTurnIntoFault;
- (id)valueForKey:(NSString *)key;
- (void)setValue:(id)value forKey:(NSString *)key;
- (id)primitiveValueForKey:(NSString *)key;
- (void)setPrimitiveValue:(id)value forKey:(NSString *)key;
- (NSDictionary<NSString *, id> *)committedValuesForKeys:(NSArray<NSString *> *)keys;
- (NSDictionary<NSString *, id> *)changedValues;
- (NSDictionary<NSString *, id> *)changedValuesForCurrentEvent;
- (BOOL)validateValue:(id *)value forKey:(NSString *)key error:(NSError **)error;
- (BOOL)validateForDelete:(NSError **)error;
- (BOOL)validateForInsert:(NSError **)error;
- (BOOL)validateForUpdate:(NSError **)error;
- (NSMutableSet *)mutableSetValueForKey:(NSString *)key;
- (NSMutableOrderedSet *)mutableOrderedSetValueForKey:(NSString *)key;
@end

/* ---- fetching ------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSPersistentStoreRequestType) {
    NSFetchRequestType = 1,
    NSSaveRequestType = 2,
    NSBatchInsertRequestType = 5,
    NSBatchUpdateRequestType = 6,
    NSBatchDeleteRequestType = 7,
};

@interface NSPersistentStoreRequest : NSObject <NSCopying>
@property (strong) NSArray<NSPersistentStore *> *affectedStores;
@property (readonly) NSPersistentStoreRequestType requestType;
@end

typedef NS_OPTIONS(NSUInteger, NSFetchRequestResultType) {
    NSManagedObjectResultType = 0x00,
    NSManagedObjectIDResultType = 0x01,
    NSDictionaryResultType = 0x02,
    NSCountResultType = 0x04,
};

@interface NSFetchRequest<__covariant ResultType : id<NSFetchRequestResult>> : NSPersistentStoreRequest <NSCoding>
+ (instancetype)fetchRequestWithEntityName:(NSString *)entityName;
- (instancetype)init;
- (instancetype)initWithEntityName:(NSString *)entityName;
- (NSArray<ResultType> *)execute:(NSError **)error;
@property (strong) NSEntityDescription *entity;
@property (readonly, strong) NSString *entityName;
@property (strong) NSPredicate *predicate;
@property (strong) NSArray<NSSortDescriptor *> *sortDescriptors;
@property NSUInteger fetchLimit;
@property NSUInteger fetchOffset;
@property NSUInteger fetchBatchSize;
@property NSFetchRequestResultType resultType;
@property BOOL includesSubentities;
@property BOOL includesPropertyValues;
@property BOOL returnsObjectsAsFaults;
@property BOOL includesPendingChanges;
@property BOOL returnsDistinctResults;
@property BOOL shouldRefreshRefetchedObjects;
@property (copy) NSArray<NSString *> *relationshipKeyPathsForPrefetching;
@property (copy) NSArray *propertiesToFetch;
@property (copy) NSArray *propertiesToGroupBy;
@property (strong) NSPredicate *havingPredicate;
@end

@interface NSPersistentStoreResult : NSObject
@end
@interface NSPersistentStoreAsynchronousResult : NSPersistentStoreResult
@end

typedef NS_ENUM(NSUInteger, NSBatchDeleteRequestResultType) {
    NSBatchDeleteResultTypeStatusOnly = 0x0,
    NSBatchDeleteResultTypeObjectIDs = 0x1,
    NSBatchDeleteResultTypeCount = 0x2,
};
typedef NS_ENUM(NSUInteger, NSBatchUpdateRequestResultType) {
    NSStatusOnlyResultType = 0x0,
    NSUpdatedObjectIDsResultType = 0x1,
    NSUpdatedObjectsCountResultType = 0x2,
};

@interface NSBatchDeleteResult : NSPersistentStoreResult
@property (readonly, strong) id result;
@property (readonly) NSBatchDeleteRequestResultType resultType;
@end
@interface NSBatchUpdateResult : NSPersistentStoreResult
@property (readonly, strong) id result;
@property (readonly) NSBatchUpdateRequestResultType resultType;
@end

/* Deletes and updates rows of an SQLite store directly: the objects in
 * contexts aren't changed (merge the IDs into contexts with
 * NSManagedObjectContext's mergeChangesFromRemoteContextSave:intoContexts:).
 * A batch delete applies the relationships' delete rules to the rows (deny
 * refuses, cascade deletes the related rows too, nullify clears the
 * inverse) and runs no validation. */
@interface NSBatchDeleteRequest : NSPersistentStoreRequest
- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetch;
- (instancetype)initWithObjectIDs:(NSArray<NSManagedObjectID *> *)objects;
@property NSBatchDeleteRequestResultType resultType;
@property (readonly, copy) NSFetchRequest *fetchRequest;
@end

@interface NSBatchUpdateRequest : NSPersistentStoreRequest
+ (instancetype)batchUpdateRequestWithEntityName:(NSString *)entityName;
- (instancetype)initWithEntityName:(NSString *)entityName;
- (instancetype)initWithEntity:(NSEntityDescription *)entity;
@property (readonly, copy) NSString *entityName;
@property (readonly, strong) NSEntityDescription *entity;
@property (strong) NSPredicate *predicate;
@property BOOL includesSubentities;
@property NSBatchUpdateRequestResultType resultType;
@property (copy) NSDictionary *propertiesToUpdate;
@end

/* ---- stores ------------------------------------------------------------------------- */

COREDATA_EXTERN NSString *const NSSQLiteStoreType;
COREDATA_EXTERN NSString *const NSXMLStoreType;
COREDATA_EXTERN NSString *const NSBinaryStoreType;
COREDATA_EXTERN NSString *const NSInMemoryStoreType;
COREDATA_EXTERN NSString *const NSStoreTypeKey;
COREDATA_EXTERN NSString *const NSStoreUUIDKey;
COREDATA_EXTERN NSString *const NSStoreModelVersionHashesKey;
COREDATA_EXTERN NSString *const NSStoreModelVersionIdentifiersKey;
COREDATA_EXTERN NSString *const NSPersistentStoreOSCompatibility;
COREDATA_EXTERN NSString *const NSReadOnlyPersistentStoreOption;
COREDATA_EXTERN NSString *const NSPersistentStoreTimeoutOption;
COREDATA_EXTERN NSString *const NSSQLitePragmasOption;
COREDATA_EXTERN NSString *const NSSQLiteAnalyzeOption;
COREDATA_EXTERN NSString *const NSSQLiteManualVacuumOption;
COREDATA_EXTERN NSString *const NSMigratePersistentStoresAutomaticallyOption;
COREDATA_EXTERN NSString *const NSInferMappingModelAutomaticallyOption;
COREDATA_EXTERN NSString *const NSPersistentHistoryTrackingKey;
COREDATA_EXTERN NSString *const NSPersistentStoreRemoteChangeNotificationPostOptionKey;
COREDATA_EXTERN NSString *const NSPersistentStoreCoordinatorStoresDidChangeNotification;
COREDATA_EXTERN NSString *const NSPersistentStoreCoordinatorStoresWillChangeNotification;
COREDATA_EXTERN NSString *const NSAddedPersistentStoresKey;
COREDATA_EXTERN NSString *const NSRemovedPersistentStoresKey;
COREDATA_EXTERN NSString *const NSUUIDChangedPersistentStoresKey;

@interface NSPersistentStore : NSObject
+ (NSDictionary<NSString *, id> *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error;
+ (BOOL)setMetadata:(NSDictionary<NSString *, id> *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error;
- (instancetype)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                                 configurationName:(NSString *)name
                                               URL:(NSURL *)url
                                           options:(NSDictionary *)options;
- (BOOL)loadMetadata:(NSError **)error;
@property (readonly, weak) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, copy) NSString *configurationName;
@property (readonly, strong) NSDictionary *options;
@property (strong) NSURL *URL;
@property (copy) NSString *identifier;
@property (readonly, copy) NSString *type;
@property (getter=isReadOnly) BOOL readOnly;
@property (strong) NSDictionary<NSString *, id> *metadata;
- (void)didAddToPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator;
- (void)willRemoveFromPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator;
@end

/* What a container (or loadPersistentStores) adds: the store's type, file
 * and options. */
@interface NSPersistentStoreDescription : NSObject <NSCopying>
+ (instancetype)persistentStoreDescriptionWithURL:(NSURL *)URL;
- (instancetype)init;
- (instancetype)initWithURL:(NSURL *)url;
@property (copy) NSString *type;
@property (copy) NSString *configuration;
@property (copy) NSURL *URL;
@property (readonly, copy) NSDictionary<NSString *, NSObject *> *options;
- (void)setOption:(NSObject *)option forKey:(NSString *)key;
@property (getter=isReadOnly) BOOL readOnly;
@property NSTimeInterval timeout;
@property (readonly, copy) NSDictionary<NSString *, NSObject *> *sqlitePragmas;
- (void)setValue:(NSObject *)value forPragmaNamed:(NSString *)name;
@property BOOL shouldAddStoreAsynchronously;
@property BOOL shouldMigrateStoreAutomatically;
@property BOOL shouldInferMappingModelAutomatically;
@end

@interface NSPersistentStoreCoordinator : NSObject
- (instancetype)initWithManagedObjectModel:(NSManagedObjectModel *)model;
@property (readonly, strong) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong) NSArray<__kindof NSPersistentStore *> *persistentStores;
@property (copy) NSString *name;
- (NSPersistentStore *)persistentStoreForURL:(NSURL *)URL;
- (NSURL *)URLForPersistentStore:(NSPersistentStore *)store;
- (BOOL)setURL:(NSURL *)url forPersistentStore:(NSPersistentStore *)store;
- (__kindof NSPersistentStore *)addPersistentStoreWithType:(NSString *)storeType
                                             configuration:(NSString *)configuration
                                                       URL:(NSURL *)storeURL
                                                   options:(NSDictionary *)options
                                                     error:(NSError **)error;
- (void)addPersistentStoreWithDescription:(NSPersistentStoreDescription *)storeDescription
                        completionHandler:(void (^)(NSPersistentStoreDescription *, NSError *))block;
- (BOOL)removePersistentStore:(NSPersistentStore *)store error:(NSError **)error;
- (void)setMetadata:(NSDictionary<NSString *, id> *)metadata forPersistentStore:(NSPersistentStore *)store;
- (NSDictionary<NSString *, id> *)metadataForPersistentStore:(NSPersistentStore *)store;
- (NSManagedObjectID *)managedObjectIDForURIRepresentation:(NSURL *)url;
- (id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context
               error:(NSError **)error;
+ (NSDictionary<NSString *, id> *)registeredStoreTypes;
+ (void)registerStoreClass:(Class)storeClass forStoreType:(NSString *)storeType;
+ (NSDictionary<NSString *, id> *)metadataForPersistentStoreOfType:(NSString *)storeType
                                                               URL:(NSURL *)url
                                                           options:(NSDictionary *)options
                                                             error:(NSError **)error;
+ (BOOL)setMetadata:(NSDictionary<NSString *, id> *)metadata
    forPersistentStoreOfType:(NSString *)storeType
                         URL:(NSURL *)url
                     options:(NSDictionary *)options
                       error:(NSError **)error;
- (NSPersistentStore *)migratePersistentStore:(NSPersistentStore *)store
                                        toURL:(NSURL *)URL
                                      options:(NSDictionary *)options
                                     withType:(NSString *)storeType
                                        error:(NSError **)error;
- (BOOL)destroyPersistentStoreAtURL:(NSURL *)url withType:(NSString *)storeType options:(NSDictionary *)options
                              error:(NSError **)error;
- (void)performBlock:(void (^)(void))block;
- (void)performBlockAndWait:(void (^)(void))block;
- (void)lock;
- (void)unlock;
- (BOOL)tryLock;
@end

/* ---- contexts ------------------------------------------------------------------------ */

COREDATA_EXTERN NSString *const NSManagedObjectContextWillSaveNotification;
COREDATA_EXTERN NSString *const NSManagedObjectContextDidSaveNotification;
COREDATA_EXTERN NSString *const NSManagedObjectContextObjectsDidChangeNotification;
COREDATA_EXTERN NSString *const NSInsertedObjectsKey;
COREDATA_EXTERN NSString *const NSUpdatedObjectsKey;
COREDATA_EXTERN NSString *const NSDeletedObjectsKey;
COREDATA_EXTERN NSString *const NSRefreshedObjectsKey;
COREDATA_EXTERN NSString *const NSInvalidatedObjectsKey;
COREDATA_EXTERN NSString *const NSInvalidatedAllObjectsKey;
COREDATA_EXTERN NSString *const NSInsertedObjectIDsKey;
COREDATA_EXTERN NSString *const NSUpdatedObjectIDsKey;
COREDATA_EXTERN NSString *const NSDeletedObjectIDsKey;

/* The merge policies, as objects (Apple's globals and class properties). */
COREDATA_EXTERN id NSErrorMergePolicy;
COREDATA_EXTERN id NSMergeByPropertyStoreTrumpMergePolicy;
COREDATA_EXTERN id NSMergeByPropertyObjectTrumpMergePolicy;
COREDATA_EXTERN id NSOverwriteMergePolicy;
COREDATA_EXTERN id NSRollbackMergePolicy;

typedef NS_ENUM(NSUInteger, NSManagedObjectContextConcurrencyType) {
    NSConfinementConcurrencyType = 0x00,
    NSPrivateQueueConcurrencyType = 0x01,
    NSMainQueueConcurrencyType = 0x02,
};

@interface NSManagedObjectContext : NSObject <NSCoding, NSLocking>
- (instancetype)init;
- (instancetype)initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)ct;
+ (void)mergeChangesFromRemoteContextSave:(NSDictionary *)changeNotificationData
                             intoContexts:(NSArray<NSManagedObjectContext *> *)contexts;
- (void)performBlock:(void (^)(void))block;
- (void)performBlockAndWait:(void (^)(void))block;
@property (strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (strong) NSManagedObjectContext *parentContext;
@property (copy) NSString *name;
@property (strong) NSUndoManager *undoManager;
@property (readonly) BOOL hasChanges;
@property (readonly, strong) NSMutableDictionary *userInfo;
@property (readonly) NSManagedObjectContextConcurrencyType concurrencyType;
- (NSManagedObject *)objectRegisteredForID:(NSManagedObjectID *)objectID;
- (NSManagedObject *)objectWithID:(NSManagedObjectID *)objectID;
- (NSManagedObject *)existingObjectWithID:(NSManagedObjectID *)objectID error:(NSError **)error;
- (NSArray *)executeFetchRequest:(NSFetchRequest *)request error:(NSError **)error;
- (NSUInteger)countForFetchRequest:(NSFetchRequest *)request error:(NSError **)error;
- (NSPersistentStoreResult *)executeRequest:(NSPersistentStoreRequest *)request error:(NSError **)error;
- (void)insertObject:(NSManagedObject *)object;
- (void)deleteObject:(NSManagedObject *)object;
- (void)refreshObject:(NSManagedObject *)object mergeChanges:(BOOL)flag;
- (void)detectConflictsForObject:(NSManagedObject *)object;
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context;
- (void)processPendingChanges;
- (void)assignObject:(id)object toPersistentStore:(NSPersistentStore *)store;
@property (readonly, strong) NSSet<__kindof NSManagedObject *> *insertedObjects;
@property (readonly, strong) NSSet<__kindof NSManagedObject *> *updatedObjects;
@property (readonly, strong) NSSet<__kindof NSManagedObject *> *deletedObjects;
@property (readonly, strong) NSSet<__kindof NSManagedObject *> *registeredObjects;
- (void)undo;
- (void)redo;
- (void)reset;
- (void)rollback;
- (BOOL)save:(NSError **)error;
- (void)refreshAllObjects;
- (void)lock;
- (void)unlock;
- (BOOL)tryLock;
@property BOOL propagatesDeletesAtEndOfEvent;
@property BOOL retainsRegisteredObjects;
@property BOOL shouldDeleteInaccessibleFaults;
@property NSTimeInterval stalenessInterval;
@property (strong) id mergePolicy;
- (BOOL)obtainPermanentIDsForObjects:(NSArray<NSManagedObject *> *)objects error:(NSError **)error;
- (void)mergeChangesFromContextDidSaveNotification:(NSNotification *)notification;
@property BOOL automaticallyMergesChangesFromParent;
@property (copy) NSString *transactionAuthor;
@end

typedef NS_ENUM(NSUInteger, NSMergePolicyType) {
    NSErrorMergePolicyType = 0x00,
    NSMergeByPropertyStoreTrumpMergePolicyType = 0x01,
    NSMergeByPropertyObjectTrumpMergePolicyType = 0x02,
    NSOverwriteMergePolicyType = 0x03,
    NSRollbackMergePolicyType = 0x04,
};

/* One object whose row changed in the store after the context read it. */
@interface NSMergeConflict : NSObject
- (instancetype)initWithSource:(NSManagedObject *)srcObject
                    newVersion:(NSUInteger)newvers
                    oldVersion:(NSUInteger)oldvers
                cachedSnapshot:(NSDictionary *)cachesnap
             persistedSnapshot:(NSDictionary *)persnap;
@property (readonly, retain) NSManagedObject *sourceObject;
@property (readonly, retain) NSDictionary *objectSnapshot;
@property (readonly, retain) NSDictionary *cachedSnapshot;
@property (readonly, retain) NSDictionary *persistedSnapshot;
@property (readonly) NSUInteger newVersionNumber;
@property (readonly) NSUInteger oldVersionNumber;
@end

@interface NSMergePolicy : NSObject
@property (class, readonly, strong) NSMergePolicy *errorMergePolicy;
@property (class, readonly, strong) NSMergePolicy *rollbackMergePolicy;
@property (class, readonly, strong) NSMergePolicy *overwriteMergePolicy;
@property (class, readonly, strong) NSMergePolicy *mergeByPropertyObjectTrumpMergePolicy;
@property (class, readonly, strong) NSMergePolicy *mergeByPropertyStoreTrumpMergePolicy;
- (instancetype)initWithMergeType:(NSMergePolicyType)ty;
@property (readonly) NSMergePolicyType mergeType;
- (BOOL)resolveConflicts:(NSArray *)list error:(NSError **)error;
@end

/* ---- fetched results controllers --------------------------------------------------- */

@protocol NSFetchedResultsSectionInfo
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *indexTitle;
@property (nonatomic, readonly) NSUInteger numberOfObjects;
@property (nonatomic, readonly) NSArray *objects;
@end

typedef NS_ENUM(NSUInteger, NSFetchedResultsChangeType) {
    NSFetchedResultsChangeInsert = 1,
    NSFetchedResultsChangeDelete = 2,
    NSFetchedResultsChangeMove = 3,
    NSFetchedResultsChangeUpdate = 4,
};

@class NSFetchedResultsController;
@protocol NSFetchedResultsControllerDelegate <NSObject>
@optional
- (void)controller:(NSFetchedResultsController *)controller
    didChangeObject:(id)anObject
        atIndexPath:(NSIndexPath *)indexPath
      forChangeType:(NSFetchedResultsChangeType)type
       newIndexPath:(NSIndexPath *)newIndexPath;
- (void)controller:(NSFetchedResultsController *)controller
    didChangeSection:(id<NSFetchedResultsSectionInfo>)sectionInfo
             atIndex:(NSUInteger)sectionIndex
       forChangeType:(NSFetchedResultsChangeType)type;
- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller;
- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller;
- (NSString *)controller:(NSFetchedResultsController *)controller sectionIndexTitleForSectionName:(NSString *)sectionName;
@end

/* The results of a fetch, in sections, kept up to date as the context
 * changes while it has a delegate. The cache name is accepted; nothing is
 * cached on disk. */
@interface NSFetchedResultsController<ResultType : id<NSFetchRequestResult>> : NSObject
- (instancetype)initWithFetchRequest:(NSFetchRequest<ResultType> *)fetchRequest
                managedObjectContext:(NSManagedObjectContext *)context
                  sectionNameKeyPath:(NSString *)sectionNameKeyPath
                           cacheName:(NSString *)name;
- (BOOL)performFetch:(NSError **)error;
@property (readonly, strong) NSFetchRequest<ResultType> *fetchRequest;
@property (readonly, strong) NSManagedObjectContext *managedObjectContext;
@property (readonly, copy) NSString *sectionNameKeyPath;
@property (readonly, copy) NSString *cacheName;
@property (weak) id<NSFetchedResultsControllerDelegate> delegate;
+ (void)deleteCacheWithName:(NSString *)name;
@property (readonly, copy) NSArray<ResultType> *fetchedObjects;
- (ResultType)objectAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForObject:(ResultType)object;
- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName;
@property (readonly, copy) NSArray<NSString *> *sectionIndexTitles;
@property (readonly, copy) NSArray<id<NSFetchedResultsSectionInfo>> *sections;
- (NSInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)sectionIndex;
@end

/* ---- the persistent container ----------------------------------------------------------- */

@interface NSPersistentContainer : NSObject
+ (instancetype)persistentContainerWithName:(NSString *)name;
+ (instancetype)persistentContainerWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model;
+ (NSURL *)defaultDirectoryURL;
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model;
@property (copy, readonly) NSString *name;
@property (strong, readonly) NSManagedObjectContext *viewContext;
@property (strong, readonly) NSManagedObjectModel *managedObjectModel;
@property (strong, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (copy) NSArray<NSPersistentStoreDescription *> *persistentStoreDescriptions;
- (void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription *, NSError *))block;
- (NSManagedObjectContext *)newBackgroundContext;
- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *))block;
@end

#endif
