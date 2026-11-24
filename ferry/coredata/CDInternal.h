/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: shared internals (freemac 1.NEXT, Ferry 0.NEXT). Our
 * own code, written from Apple's public documentation of Core Data (the
 * Core Data Programming Guide and the class references); built as a
 * Mach-O library with ferry-cc, without ARC. No Apple code was used, and
 * nothing of Apple's stores or compiled models was looked into: the SQLite
 * store keeps Ferry's own tables.
 *
 * How the pieces fit. A context keeps its objects; what it hasn't loaded
 * it asks its parent for, and a save hands its changes to the parent. The
 * parent is either the coordinator, which asks its stores, or another
 * context; both answer the CDParent protocol below. What a parent hands
 * back is a CDSnapshot: an object's committed values, with to-one
 * relationships as object IDs and to-many ones as arrays of object IDs
 * (left out when the store would have to look them up; the context asks
 * for them when they are first used).
 *
 * A fetch takes the candidates a parent gives (the SQLite store narrows
 * them with the part of the predicate it can put in SQL), adds the
 * context's own inserted and changed objects, and then evaluates the
 * predicate, sorts and applies the offset and limit in memory, so that
 * what the store couldn't do is done here, and pending changes count. */
#ifndef FERRY_COREDATA_INTERNAL_H
#define FERRY_COREDATA_INTERNAL_H
#include <Foundation/Foundation.h>
#include <CoreData/CoreData.h>
#include <pthread.h>

#define CD_EXPORT __attribute__((visibility("default")))

/* ---- helpers (NSManagedObjectModel.m) ------------------------------------------------- */

/* An error in NSCocoaErrorDomain, autoreleased; extra adds to its userInfo. */
NSError *CDError(NSInteger code, NSString *description, NSDictionary *extra);
/* Sets *out to CDError(...) when out isn't NULL; answers NO. */
BOOL CDFail(NSError **out, NSInteger code, NSString *description, NSDictionary *extra);
/* Writes a line to stderr the first time it is asked with this key. */
void CDWarnOnce(NSString *key, NSString *message);
/* Raises NSInternalInconsistencyException (or name) with the message. */
void CDRaise(NSString *name, NSString *format, ...) __attribute__((noreturn));
/* Values compared as Core Data compares them: nil and NSNull alike. */
BOOL CDEqual(id a, id b);
/* SHA-256 of a string, as NSData. */
NSData *CDHash(NSString *s);
/* The compiled-model message, once per process. */
void CDCompiledModelUnsupported(NSString *path);

/* ---- the model ---------------------------------------------------------------------- */

@interface NSEntityDescription (CDInternal)
- (NSEntityDescription *)cd_root;
/* A property by name, inherited ones included (cached). */
- (NSPropertyDescription *)cd_propertyNamed:(NSString *)name;
/* The names of the entity and every entity below it. */
- (NSArray *)cd_selfAndSubentityNames;
- (Class)cd_class;
- (void)cd_setModel:(NSManagedObjectModel *)model;
- (void)cd_setSuperentity:(NSEntityDescription *)entity;
/* Every attribute and relationship, inherited ones first (an array of NSPropertyDescription). */
- (NSArray *)cd_allProperties;
/* Names with the given storage, for the stores. */
- (NSArray *)cd_persistentAttributes;
- (NSArray *)cd_persistentRelationships;
@end

@interface NSPropertyDescription (CDInternal)
- (void)cd_setEntity:(NSEntityDescription *)entity;
@end

@interface NSAttributeDescription (CDInternal)
/* The stored form of a value and back (transformable attributes through their transformer). */
- (id)cd_storedValue:(id)value;
- (id)cd_valueFromStored:(id)stored;
@end

@interface NSManagedObjectModel (CDInternal)
/* Reads the XML source of a model (a .xcdatamodeld or .xcdatamodel folder, or its contents file). */
+ (NSManagedObjectModel *)cd_modelFromSourceAtURL:(NSURL *)url;
/* Ferry's own description of the stored shape of each entity, kept in a store's metadata
 * to tell which changes a lightweight migration can make. */
- (NSDictionary *)cd_schema;
@end

/* The dynamic accessors (NSManagedObject.m): makes the model's properties known for
 * the entity's class, so that @dynamic accessors are made when first used. */
void CDRegisterEntity(NSEntityDescription *entity);
void CDRegisterModel(NSManagedObjectModel *model);
/* The entity a class stands for, when one model's entity names it. */
NSEntityDescription *CDEntityForClass(Class cls);

/* ---- rows ------------------------------------------------------------------------------- */

@interface CDSnapshot : NSObject {
@public
    NSManagedObjectID *oid;
    NSMutableDictionary *values;   /* attributes, to-ones as IDs (absent: nil), to-manys as arrays of IDs */
    int64_t version;
}
+ (CDSnapshot *)snapshotWithID:(NSManagedObjectID *)oid values:(NSDictionary *)values version:(int64_t)version;
@end

/* One object's part of a save. */
@interface CDChange : NSObject {
@public
    NSManagedObjectID *oid;
    NSDictionary *values;      /* inserted: every value; updated: the changed keys (NSNull for nil) */
    NSDictionary *allValues;   /* updated: every loaded value (for the overwrite policy) */
    NSDictionary *committed;   /* updated and deleted: the values when last read (for conflicts) */
    int64_t version;           /* updated and deleted: the version when last read */
    NSManagedObject *object;   /* in the saving context */
}
@end

@interface CDChangeSet : NSObject {
@public
    NSMutableArray *inserted, *updated, *deleted;   /* CDChange */
    NSMergePolicyType policy;
    NSMutableArray *conflicts;                        /* NSMergeConflict, filled by the store */
    NSMutableSet *refreshIDs;                         /* objects whose stored values won, to refresh */
    NSMutableDictionary *versions;                    /* object ID -> the version written */
}
@end

/* What a fetch asks of a parent. */
@interface CDQuery : NSObject {
@public
    NSFetchRequest *request;
    NSEntityDescription *entity;
    NSArray *entityNames;   /* the entity and, when the request includes them, its subentities */
    BOOL storeLimit;        /* the parent may apply the offset and limit itself */
    BOOL exact;             /* set by the parent: what it answered matches the predicate exactly, by stored values */
}
@end

@protocol CDParent <NSObject>
/* The candidates for a fetch; *limited says the offset and limit were applied. */
- (NSArray *)cd_snapshotsForQuery:(CDQuery *)query limited:(BOOL *)limited error:(NSError **)error;
/* The exact number of matches, or NSNotFound when it can only be found by fetching. */
- (NSUInteger)cd_countForQuery:(CDQuery *)query;
- (CDSnapshot *)cd_snapshotForID:(NSManagedObjectID *)oid;
- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key;
- (BOOL)cd_saveChanges:(CDChangeSet *)changes error:(NSError **)error;
- (NSPersistentStoreCoordinator *)cd_coordinator;
@end

/* ---- object IDs ------------------------------------------------------------------------- */

@interface NSManagedObjectID (CDInternal)
+ (NSManagedObjectID *)cd_temporaryIDForEntity:(NSEntityDescription *)entity;
+ (NSManagedObjectID *)cd_IDForEntity:(NSEntityDescription *)entity store:(NSPersistentStore *)store pk:(int64_t)pk;
- (int64_t)cd_pk;
- (NSString *)cd_temporaryName;
@end

/* ---- objects (NSManagedObject.m) ------------------------------------------------------- */

@interface NSManagedObject (CDInternal)
+ (id)cd_faultWithEntity:(NSEntityDescription *)entity objectID:(NSManagedObjectID *)oid
                 context:(NSManagedObjectContext *)context;
- (void)cd_setObjectID:(NSManagedObjectID *)oid;
- (void)cd_setContext:(NSManagedObjectContext *)context;
- (void)cd_setDeletedFlag:(BOOL)flag;
- (void)cd_setInsertedFlag:(BOOL)flag;
- (void)cd_turnIntoFault;
/* Fills a fault from a snapshot (no notifications). */
- (void)cd_fillFromSnapshot:(CDSnapshot *)snapshot;
/* The loaded values, as a parent or store keeps them (to-ones and to-manys as IDs). */
- (NSDictionary *)cd_storableValuesForKeys:(NSArray *)keys;
- (NSDictionary *)cd_loadedValues;
/* Persistent values that differ from the committed snapshot, in stored form (IDs). */
- (NSDictionary *)cd_changedStorableValues;
- (BOOL)cd_hasTransientChanges;
- (void)cd_clearTransientChanges;
/* Sets a value as a parent context does when a child saves (notifications, no inverses). */
- (void)cd_applyStoredValue:(id)value forKey:(NSString *)key;
/* Restores a value as undo does (notifications, no inverses). */
- (void)cd_restoreValue:(id)value forKey:(NSString *)key;
- (BOOL)cd_isFaultOrNil;
/* Tells observers each loaded key may have changed, around block (a refresh). */
- (void)cd_notifyAllAround:(void (^)(void))block;
@end

/* ---- contexts (NSManagedObjectContext.m) ------------------------------------------------- */

@interface NSManagedObjectContext (CDInternal) <CDParent>
- (void)cd_object:(NSManagedObject *)object didChangeKey:(NSString *)key from:(id)old;
- (CDSnapshot *)cd_snapshotForObject:(NSManagedObject *)object;
- (NSArray *)cd_relatedIDsForObject:(NSManagedObject *)object key:(NSString *)key;
/* Records to-many IDs loaded for an object in its committed snapshot. */
- (void)cd_noteLoadedIDs:(NSArray *)ids forObject:(NSManagedObject *)object key:(NSString *)key;
- (BOOL)cd_maintainsInverses;
- (NSDictionary *)cd_committedValuesForObject:(NSManagedObject *)object;
/* Runs block on the context's queue and waits; answers the block's work. */
- (void)cd_performAndWait:(void (^)(void))block;
@end

/* ---- the coordinator and stores (NSPersistentStoreCoordinator.m) ---------------------------- */

@interface NSPersistentStoreCoordinator (CDInternal) <CDParent>
- (void)cd_lock;
- (void)cd_unlock;
/* Gives the objects permanent IDs (the IDs in order; temporary ones replaced). */
- (NSArray *)cd_permanentIDsForTemporaryIDs:(NSArray *)ids error:(NSError **)error;
/* The permanent ID a temporary one was given, or the other way. */
- (NSManagedObjectID *)cd_permanentIDForTemporaryID:(NSManagedObjectID *)oid;
- (NSManagedObjectID *)cd_temporaryIDForPermanentID:(NSManagedObjectID *)oid;
- (NSPersistentStore *)cd_storeForEntity:(NSEntityDescription *)entity;
- (NSPersistentStore *)cd_storeWithIdentifier:(NSString *)identifier;
@end

/* What every store class gives (in-memory and binary in NSPersistentStoreCoordinator.m,
 * SQLite in CDSQLiteStore.m). Called with the coordinator locked. */
@interface NSPersistentStore (CDStore)
- (BOOL)cd_load:(NSError **)error;
- (NSArray *)cd_rowsForQuery:(CDQuery *)query limited:(BOOL *)limited;
- (NSUInteger)cd_countForQuery:(CDQuery *)query;
- (CDSnapshot *)cd_rowForID:(NSManagedObjectID *)oid;
- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key;
- (BOOL)cd_apply:(CDChangeSet *)changes error:(NSError **)error;
- (int64_t)cd_reservePKs:(NSUInteger)count forEntity:(NSEntityDescription *)root;
- (void)cd_writeMetadata;
- (id)cd_executeRequest:(NSPersistentStoreRequest *)request error:(NSError **)error;
- (void)cd_close;
- (void)cd_setType:(NSString *)type;
- (NSPersistentStoreCoordinator *)cd_coordinatorRef;
/* Puts the coordinator's model's version hashes and schema in the metadata. */
- (void)cd_stampMetadata;
@end

/* Settles conflicts by the change set's policy: the store gives each updated or
 * deleted object's current row and version (nil when it is gone). Answers NO, with
 * the merge error, under NSErrorMergePolicy. */
BOOL CDResolveConflicts(CDChangeSet *changes, CDSnapshot * (^current)(NSManagedObjectID *oid), NSError **error);

/* The in-memory store, which the binary store extends. */
@interface CDInMemoryStore : NSPersistentStore {
@public
    NSMutableDictionary *_rows;   /* root entity name -> (pk -> CDSnapshot) */
    NSMutableDictionary *_nextPK; /* root entity name -> NSNumber */
}
@end

@interface CDBinaryStore : CDInMemoryStore
@end

@interface CDSQLiteStore : NSPersistentStore
/* The batch requests, given the IDs of the rows they act on (in this store): answer the
 * IDs deleted (cascades included) or updated, or nil with the error. */
- (NSArray *)cd_batchDeleteIDs:(NSArray *)ids error:(NSError **)error;
- (NSArray *)cd_batchUpdateIDs:(NSArray *)ids values:(NSDictionary *)values error:(NSError **)error;
@end

/* Settles whether the store's model matches, migrating what a lightweight migration can.
 * oldSchema is the metadata's, nil for a new store. Fills added and removed with
 * attribute descriptions (entity.attribute names) for the store to act on. */
BOOL CDCheckSchema(NSManagedObjectModel *model, NSDictionary *metadata, NSDictionary *options,
                   NSMutableArray *added, NSError **error);

/* ---- fetching (NSFetchRequest.m) ----------------------------------------------------------- */

/* The context whose performBlock: or performBlockAndWait: is running on this thread. */
NSManagedObjectContext *CDCurrentContext(void);
/* Batch results (NSFetchRequest.m). */
id CDBatchDeleteResult(id result, NSBatchDeleteRequestResultType type);
id CDBatchUpdateResult(id result, NSBatchUpdateRequestResultType type);
@interface NSBatchDeleteRequest (CDInternal)
- (NSArray *)cd_objectIDs;
@end

/* The in-memory part of a fetch: predicate, sort, offset and limit. */
NSArray *CDFilterSortLimit(NSArray *objects, NSFetchRequest *request, BOOL limited);

/* A predicate's SQL (CDSQLiteStore.m). */
@interface NSPredicate (CDStructure)
- (id)_ferryStructure;
@end

#endif
