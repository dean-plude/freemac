/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: NSManagedObjectContext, with merge policies and
 * conflicts, as Apple's class references and the Core Data Programming
 * Guide describe them (freemac 1.209, Ferry 0.35.0). Our own code; no
 * Apple code was used.
 *
 * A context keeps the objects it has registered, by object ID, and the
 * committed values it read for each (its snapshots). Inserted, updated
 * and deleted objects are kept in sets until a save hands them to the
 * parent (the coordinator, or another context). Changes are gathered
 * until processPendingChanges, which posts the objects-did-change
 * notification; it runs at the end of the run-loop turn (or of a
 * performBlock:), and before a fetch or a save.
 *
 * Deleting an object applies its relationships' delete rules at once
 * (cascade and nullify), so that the changes join the same undo group;
 * a Mac applies them at the end of the event. Undo is kept per change:
 * each recorded change registers an action that puts the old value back.
 *
 * Concurrency: a private-queue context has a serial dispatch queue;
 * performBlock: runs there, and performBlockAndWait: runs on the calling
 * thread, holding the context's lock, as a Mac does. A main-queue context
 * runs blocks on the main queue (performBlockAndWait: from another thread
 * waits for the main thread). */
#import "CDInternal.h"

NSString *const NSManagedObjectContextWillSaveNotification CD_EXPORT = @"NSManagingContextWillSaveChangesNotification";
NSString *const NSManagedObjectContextDidSaveNotification CD_EXPORT = @"NSManagingContextDidSaveChangesNotification";
NSString *const NSManagedObjectContextObjectsDidChangeNotification CD_EXPORT =
    @"NSObjectsChangedInManagingContextNotification";
NSString *const NSInsertedObjectsKey CD_EXPORT = @"inserted";
NSString *const NSUpdatedObjectsKey CD_EXPORT = @"updated";
NSString *const NSDeletedObjectsKey CD_EXPORT = @"deleted";
NSString *const NSRefreshedObjectsKey CD_EXPORT = @"refreshed";
NSString *const NSInvalidatedObjectsKey CD_EXPORT = @"invalidated";
NSString *const NSInvalidatedAllObjectsKey CD_EXPORT = @"invalidatedAll";
NSString *const NSInsertedObjectIDsKey CD_EXPORT = @"inserted_objectIDs";
NSString *const NSUpdatedObjectIDsKey CD_EXPORT = @"updated_objectIDs";
NSString *const NSDeletedObjectIDsKey CD_EXPORT = @"deleted_objectIDs";

id NSErrorMergePolicy CD_EXPORT;
id NSMergeByPropertyStoreTrumpMergePolicy CD_EXPORT;
id NSMergeByPropertyObjectTrumpMergePolicy CD_EXPORT;
id NSOverwriteMergePolicy CD_EXPORT;
id NSRollbackMergePolicy CD_EXPORT;

/* ---- snapshots and change sets ------------------------------------------------------------ */

@implementation CDSnapshot
+ (CDSnapshot *)snapshotWithID:(NSManagedObjectID *)oid values:(NSDictionary *)values version:(int64_t)version
{
    CDSnapshot *s = [[[self alloc] init] autorelease];
    s->oid = [oid retain];
    s->values = values ? [values mutableCopy] : [[NSMutableDictionary alloc] init];
    s->version = version;
    return s;
}
- (void)dealloc
{
    [oid release];
    [values release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    return [[CDSnapshot snapshotWithID:oid values:values version:version] retain];
}
@end

@implementation CDChange
- (void)dealloc
{
    [oid release];
    [values release];
    [allValues release];
    [committed release];
    [object release];
    [super dealloc];
}
@end

@implementation CDChangeSet
- (instancetype)init
{
    if ((self = [super init])) {
        inserted = [[NSMutableArray alloc] init];
        updated = [[NSMutableArray alloc] init];
        deleted = [[NSMutableArray alloc] init];
        conflicts = [[NSMutableArray alloc] init];
        refreshIDs = [[NSMutableSet alloc] init];
        versions = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [inserted release];
    [updated release];
    [deleted release];
    [conflicts release];
    [refreshIDs release];
    [versions release];
    [super dealloc];
}
@end

@implementation CDQuery
- (void)dealloc
{
    [request release];
    [entity release];
    [entityNames release];
    [super dealloc];
}
@end

/* ---- merge policies and conflicts ------------------------------------------------------------ */

@implementation NSMergeConflict {
    NSManagedObject *_source;
    NSDictionary *_object, *_cached, *_persisted;
    NSUInteger _new, _old;
}
- (instancetype)initWithSource:(NSManagedObject *)source
                    newVersion:(NSUInteger)newVersion
                    oldVersion:(NSUInteger)oldVersion
                cachedSnapshot:(NSDictionary *)cached
             persistedSnapshot:(NSDictionary *)persisted
{
    if ((self = [super init])) {
        _source = [source retain];
        _new = newVersion;
        _old = oldVersion;
        _cached = [cached copy];
        _persisted = [persisted copy];
        _object = [[source cd_loadedValues] copy];
    }
    return self;
}
- (void)dealloc
{
    [_source release];
    [_object release];
    [_cached release];
    [_persisted release];
    [super dealloc];
}
- (NSManagedObject *)sourceObject { return _source; }
- (NSDictionary *)objectSnapshot { return _object; }
- (NSDictionary *)cachedSnapshot { return _cached; }
- (NSDictionary *)persistedSnapshot { return _persisted; }
- (NSUInteger)newVersionNumber { return _new; }
- (NSUInteger)oldVersionNumber { return _old; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"NSMergeConflict (%p) for %@ with oldVersion = %lu and newVersion = %lu", self,
                                      [_source objectID], (unsigned long)_old, (unsigned long)_new];
}
@end

@implementation NSMergePolicy {
    NSMergePolicyType _type;
}
+ (void)load
{
    NSErrorMergePolicy = [[NSMergePolicy alloc] initWithMergeType:NSErrorMergePolicyType];
    NSMergeByPropertyStoreTrumpMergePolicy =
        [[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyStoreTrumpMergePolicyType];
    NSMergeByPropertyObjectTrumpMergePolicy =
        [[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyObjectTrumpMergePolicyType];
    NSOverwriteMergePolicy = [[NSMergePolicy alloc] initWithMergeType:NSOverwriteMergePolicyType];
    NSRollbackMergePolicy = [[NSMergePolicy alloc] initWithMergeType:NSRollbackMergePolicyType];
}
+ (NSMergePolicy *)errorMergePolicy { return NSErrorMergePolicy; }
+ (NSMergePolicy *)rollbackMergePolicy { return NSRollbackMergePolicy; }
+ (NSMergePolicy *)overwriteMergePolicy { return NSOverwriteMergePolicy; }
+ (NSMergePolicy *)mergeByPropertyObjectTrumpMergePolicy { return NSMergeByPropertyObjectTrumpMergePolicy; }
+ (NSMergePolicy *)mergeByPropertyStoreTrumpMergePolicy { return NSMergeByPropertyStoreTrumpMergePolicy; }
- (instancetype)initWithMergeType:(NSMergePolicyType)type
{
    if ((self = [super init]))
        _type = type;
    return self;
}
- (NSMergePolicyType)mergeType { return _type; }
/* The store settles conflicts by the policy's type as it saves; this only says whether it can. */
- (BOOL)resolveConflicts:(NSArray *)list error:(NSError **)error
{
    if (_type == NSErrorMergePolicyType && [list count])
        return CDFail(error, NSManagedObjectMergeError, @"Could not merge changes.",
                      @{NSPersistentStoreSaveConflictsErrorKey : list});
    return YES;
}
@end

/* ---- the context -------------------------------------------------------------------------- */

static NSMergePolicyType policy_type(id policy)
{
    return [policy respondsToSelector:@selector(mergeType)] ? [policy mergeType] : NSErrorMergePolicyType;
}

/* The context running a block on this thread, for -[NSFetchRequest execute:]. */
static pthread_key_t current_key;
static pthread_once_t current_once = PTHREAD_ONCE_INIT;
static void make_current_key(void) { pthread_key_create(&current_key, NULL); }
NSManagedObjectContext *CDCurrentContext(void)
{
    pthread_once(&current_once, make_current_key);
    return (NSManagedObjectContext *)pthread_getspecific(current_key);
}
static void *enter_context(NSManagedObjectContext *ctx)
{
    pthread_once(&current_once, make_current_key);
    void *was = pthread_getspecific(current_key);
    pthread_setspecific(current_key, ctx);
    return was;
}
static void leave_context(void *was) { pthread_setspecific(current_key, was); }

static BOOL theirs_is_deleted_here(NSManagedObjectContext *self, NSManagedObject *object)
{
    return [object managedObjectContext] == self && [object isDeleted];
}

static NSDictionary *snapshot_values(CDSnapshot *s) { return s ? s->values : nil; }

@implementation NSManagedObjectContext {
    NSPersistentStoreCoordinator *_coordinator;
    NSManagedObjectContext *_parent;
    NSManagedObjectContextConcurrencyType _type;
    dispatch_queue_t _queue;
    pthread_mutex_t _mutex;
    NSUndoManager *_undo;
    NSMutableDictionary *_registered;   /* object ID -> object */
    NSMutableDictionary *_snapshots;    /* object ID -> CDSnapshot */
    NSMutableSet *_inserted, *_updated, *_deleted;
    NSMutableSet *_pInserted, *_pUpdated, *_pDeleted, *_pRefreshed, *_pInvalidated;
    BOOL _scheduled, _processing, _saving, _autoMerge, _propagates, _retains, _deleteInaccessible;
    NSString *_name, *_author;
    NSMutableDictionary *_userInfo;
    id _mergePolicy;
    NSTimeInterval _staleness;
}

- (instancetype)init { return [self initWithConcurrencyType:NSConfinementConcurrencyType]; }

- (instancetype)initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)type
{
    if ((self = [super init])) {
        _type = type;
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_mutex, &attr);
        pthread_mutexattr_destroy(&attr);
        if (type == NSPrivateQueueConcurrencyType)
            _queue = dispatch_queue_create("NSManagedObjectContext", DISPATCH_QUEUE_SERIAL);
        else
            _undo = [[NSUndoManager alloc] init];
        _registered = [[NSMutableDictionary alloc] init];
        _snapshots = [[NSMutableDictionary alloc] init];
        _inserted = [[NSMutableSet alloc] init];
        _updated = [[NSMutableSet alloc] init];
        _deleted = [[NSMutableSet alloc] init];
        _pInserted = [[NSMutableSet alloc] init];
        _pUpdated = [[NSMutableSet alloc] init];
        _pDeleted = [[NSMutableSet alloc] init];
        _pRefreshed = [[NSMutableSet alloc] init];
        _pInvalidated = [[NSMutableSet alloc] init];
        _userInfo = [[NSMutableDictionary alloc] init];
        _mergePolicy = [NSErrorMergePolicy retain];
        _propagates = YES;
        _deleteInaccessible = YES;
        _staleness = -1;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSManagedObject *o in [_registered allValues])
        if ([o managedObjectContext] == self)
            [o cd_setContext:nil];
    [_coordinator release];
    [_parent release];
    if (_queue)
        dispatch_release(_queue);
    pthread_mutex_destroy(&_mutex);
    [_undo release];
    [_registered release];
    [_snapshots release];
    [_inserted release];
    [_updated release];
    [_deleted release];
    [_pInserted release];
    [_pUpdated release];
    [_pDeleted release];
    [_pRefreshed release];
    [_pInvalidated release];
    [_name release];
    [_author release];
    [_userInfo release];
    [_mergePolicy release];
    [super dealloc];
}

- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}

/* ---- concurrency ---- */

- (NSManagedObjectContextConcurrencyType)concurrencyType { return _type; }
- (void)lock { pthread_mutex_lock(&_mutex); }
- (void)unlock { pthread_mutex_unlock(&_mutex); }
- (BOOL)tryLock { return pthread_mutex_trylock(&_mutex) == 0; }

- (void)performBlock:(void (^)(void))block
{
    void (^b)(void) = [[block copy] autorelease];
    dispatch_queue_t q = _type == NSPrivateQueueConcurrencyType ? _queue : dispatch_get_main_queue();
    dispatch_async(q, ^{
        pthread_mutex_lock(&_mutex);
        void *was = enter_context(self);
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        b();
        [self processPendingChanges];
        [pool drain];
        leave_context(was);
        pthread_mutex_unlock(&_mutex);
    });
}

- (void)performBlockAndWait:(void (^)(void))block
{
    if (_type == NSMainQueueConcurrencyType && ![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            pthread_mutex_lock(&_mutex);
            void *was = enter_context(self);
            block();
            leave_context(was);
            pthread_mutex_unlock(&_mutex);
        });
        return;
    }
    pthread_mutex_lock(&_mutex);
    void *was = enter_context(self);
    block();
    leave_context(was);
    pthread_mutex_unlock(&_mutex);
}

- (void)cd_performAndWait:(void (^)(void))block { [self performBlockAndWait:block]; }

/* ---- settings ---- */

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    return _coordinator ?: [_parent persistentStoreCoordinator];
}
- (void)setPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator
{
    if (_parent && coordinator)
        CDRaise(NSInvalidArgumentException, @"Context already has a parent context; it can't have a coordinator too");
    [_coordinator autorelease];
    _coordinator = [coordinator retain];
    CDRegisterModel([coordinator managedObjectModel]);
    if (_autoMerge)
        [self cd_observeParent];
}
- (NSManagedObjectContext *)parentContext { return _parent; }
- (void)setParentContext:(NSManagedObjectContext *)parent
{
    if (_coordinator && parent)
        CDRaise(NSInvalidArgumentException, @"Context already has a coordinator; it can't have a parent context too");
    [_parent autorelease];
    _parent = [parent retain];
    if (_autoMerge)
        [self cd_observeParent];
}
- (id<CDParent>)cd_parent { return _parent ? (id<CDParent>)_parent : (id<CDParent>)_coordinator; }
- (NSPersistentStoreCoordinator *)cd_coordinator { return [self persistentStoreCoordinator]; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    [_name autorelease];
    _name = [name copy];
}
- (NSString *)transactionAuthor { return _author; }
- (void)setTransactionAuthor:(NSString *)a
{
    [_author autorelease];
    _author = [a copy];
}
- (NSUndoManager *)undoManager { return _undo; }
- (void)setUndoManager:(NSUndoManager *)undo
{
    [_undo autorelease];
    _undo = [undo retain];
}
- (NSMutableDictionary *)userInfo { return _userInfo; }
- (id)mergePolicy { return _mergePolicy; }
- (void)setMergePolicy:(id)policy
{
    [_mergePolicy autorelease];
    _mergePolicy = [policy ?: NSErrorMergePolicy retain];
}
- (BOOL)propagatesDeletesAtEndOfEvent { return _propagates; }
- (void)setPropagatesDeletesAtEndOfEvent:(BOOL)flag { _propagates = flag; }
- (BOOL)retainsRegisteredObjects { return _retains; }
- (void)setRetainsRegisteredObjects:(BOOL)flag { _retains = flag; }
- (BOOL)shouldDeleteInaccessibleFaults { return _deleteInaccessible; }
- (void)setShouldDeleteInaccessibleFaults:(BOOL)flag { _deleteInaccessible = flag; }
- (NSTimeInterval)stalenessInterval { return _staleness; }
- (void)setStalenessInterval:(NSTimeInterval)t { _staleness = t; }

- (BOOL)automaticallyMergesChangesFromParent { return _autoMerge; }
- (void)setAutomaticallyMergesChangesFromParent:(BOOL)flag
{
    if (flag == _autoMerge)
        return;
    _autoMerge = flag;
    if (flag)
        [self cd_observeParent];
    else
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSManagedObjectContextDidSaveNotification
                                                      object:nil];
}

- (void)cd_observeParent
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
    [nc addObserver:self
           selector:@selector(cd_otherContextDidSave:)
               name:NSManagedObjectContextDidSaveNotification
             object:_parent];
}

static NSArray *ids_of(id collection)
{
    NSMutableArray *ids = [NSMutableArray array];
    for (id o in collection) {
        if ([o isKindOfClass:[NSManagedObject class]])
            [ids addObject:[o objectID]];
        else if ([o isKindOfClass:[NSManagedObjectID class]])
            [ids addObject:o];
    }
    return ids;
}

/* A save this context should take in: its parent context's, or, when its parent is the
 * coordinator, another context's that saved straight to the same coordinator. */
- (void)cd_otherContextDidSave:(NSNotification *)note
{
    NSManagedObjectContext *other = [note object];
    if (other == self)
        return;
    if (!_parent && ([other parentContext] || [other persistentStoreCoordinator] != _coordinator))
        return;
    NSDictionary *info = [note userInfo];
    NSArray *ins = ids_of([info objectForKey:NSInsertedObjectsKey]);
    NSArray *upd = ids_of([info objectForKey:NSUpdatedObjectsKey]);
    NSArray *del = ids_of([info objectForKey:NSDeletedObjectsKey]);
    [self performBlock:^{
        [self cd_mergeInserted:ins updated:upd deleted:del];
    }];
}

/* ---- registered objects ---- */

- (void)cd_rekey:(NSManagedObject *)o to:(NSManagedObjectID *)oid
{
    NSManagedObjectID *old = [[[o objectID] retain] autorelease];
    if ([old isEqual:oid])
        return;
    [o retain];
    [_registered removeObjectForKey:old];
    CDSnapshot *s = [[[_snapshots objectForKey:old] retain] autorelease];
    [_snapshots removeObjectForKey:old];
    [o cd_setObjectID:oid];
    [_registered setObject:o forKey:oid];
    if (s) {
        [s->oid autorelease];
        s->oid = [oid retain];
        [_snapshots setObject:s forKey:oid];
    }
    [o release];
}

- (NSManagedObject *)cd_registered:(NSManagedObjectID *)oid
{
    if (!oid)
        return nil;
    NSManagedObject *o = [_registered objectForKey:oid];
    if (o)
        return o;
    NSPersistentStoreCoordinator *c = [self persistentStoreCoordinator];
    if ([oid isTemporaryID]) {
        NSManagedObjectID *perm = [c cd_permanentIDForTemporaryID:oid];
        return perm ? [_registered objectForKey:perm] : nil;
    }
    NSManagedObjectID *temp = [c cd_temporaryIDForPermanentID:oid];
    if (temp && (o = [_registered objectForKey:temp]))
        [self cd_rekey:o to:oid];
    return o;
}

- (NSManagedObject *)objectRegisteredForID:(NSManagedObjectID *)oid { return [self cd_registered:oid]; }

- (NSManagedObject *)objectWithID:(NSManagedObjectID *)oid
{
    if (!oid)
        CDRaise(NSInvalidArgumentException, @"-objectWithID: needs an object ID");
    NSManagedObject *o = [self cd_registered:oid];
    if (o)
        return o;
    o = [NSManagedObject cd_faultWithEntity:[oid entity] objectID:oid context:self];
    [_registered setObject:o forKey:oid];
    return o;
}

- (CDSnapshot *)cd_parentSnapshot:(NSManagedObjectID *)oid
{
    CDSnapshot *s = [[[[self cd_parent] cd_snapshotForID:oid] copy] autorelease];
    if (s)
        [_snapshots setObject:s forKey:oid];
    return s;
}

- (NSManagedObject *)existingObjectWithID:(NSManagedObjectID *)oid error:(NSError **)error
{
    NSManagedObject *o = [self cd_registered:oid];
    if (o && ![o isFault])
        return o;
    if (o && [o isInserted])
        return o;
    CDSnapshot *s = [_snapshots objectForKey:oid] ?: [self cd_parentSnapshot:oid];
    if (!s) {
        CDFail(error, NSManagedObjectReferentialIntegrityError, @"The object isn't in the store.",
               @{NSAffectedObjectsErrorKey : @[ oid ]});
        return nil;
    }
    o = [self objectWithID:oid];
    [o willAccessValueForKey:nil];
    return o;
}

- (CDSnapshot *)cd_snapshotForObject:(NSManagedObject *)object
{
    NSManagedObjectID *oid = [object objectID];
    CDSnapshot *s = [_snapshots objectForKey:oid];
    if (s)
        return s;
    if ([object isInserted])
        return [CDSnapshot snapshotWithID:oid values:nil version:0];
    s = [self cd_parentSnapshot:oid];
    if (!s && _deleteInaccessible) {
        /* gone from the store: the object reads as deleted, with no values */
        [object cd_setDeletedFlag:YES];
        return [CDSnapshot snapshotWithID:oid values:nil version:0];
    }
    return s;
}

- (NSDictionary *)cd_committedValuesForObject:(NSManagedObject *)object
{
    return snapshot_values([_snapshots objectForKey:[object objectID]]) ?: @{};
}

- (NSArray *)cd_relatedIDsForObject:(NSManagedObject *)object key:(NSString *)key
{
    id known = [snapshot_values([_snapshots objectForKey:[object objectID]]) objectForKey:key];
    if ([known isKindOfClass:[NSArray class]])
        return known;
    return [[self cd_parent] cd_relatedIDsForID:[object objectID] key:key] ?: @[];
}

- (void)cd_noteLoadedIDs:(NSArray *)ids forObject:(NSManagedObject *)object key:(NSString *)key
{
    CDSnapshot *s = [_snapshots objectForKey:[object objectID]];
    if (s && ![s->values objectForKey:key])
        [s->values setObject:ids forKey:key];
}

- (NSSet *)registeredObjects { return [NSSet setWithArray:[_registered allValues]]; }
- (NSSet *)insertedObjects { return [[_inserted copy] autorelease]; }
- (NSSet *)deletedObjects { return [[_deleted copy] autorelease]; }
- (NSSet *)updatedObjects
{
    NSMutableSet *s = [NSMutableSet set];
    for (NSManagedObject *o in _updated)
        if (![o isInserted] && ![o isDeleted] && ([o hasPersistentChangedValues] || [o cd_hasTransientChanges]))
            [s addObject:o];
    return s;
}
- (BOOL)hasChanges { return [_inserted count] || [_deleted count] || [[self updatedObjects] count]; }

/* ---- changes ---- */

- (BOOL)cd_maintainsInverses { return !(_undo && ([_undo isUndoing] || [_undo isRedoing])); }

- (void)cd_registerUndo:(void (^)(void))block
{
    if (!_undo || ![_undo isUndoRegistrationEnabled])
        return;
    void (^b)(void) = [[block copy] autorelease];
    [_undo registerUndoWithTarget:self
                          handler:^(id target) {
                              b();
                          }];
}

- (void)cd_scheduleProcessing
{
    if (_scheduled)
        return;
    _scheduled = YES;
    if (_type == NSPrivateQueueConcurrencyType)
        dispatch_async(_queue, ^{
            pthread_mutex_lock(&_mutex);
            [self processPendingChanges];
            pthread_mutex_unlock(&_mutex);
        });
    else if (_type == NSMainQueueConcurrencyType && ![NSThread isMainThread])
        dispatch_async(dispatch_get_main_queue(), ^{
            [self processPendingChanges];
        });
    else
        [self performSelector:@selector(processPendingChanges) withObject:nil afterDelay:0];
}

- (void)cd_object:(NSManagedObject *)object didChangeKey:(NSString *)key from:(id)old
{
    if (![object isDeleted]) {
        if (![object isInserted])
            [_updated addObject:object];
        if (![_pInserted containsObject:object])
            [_pUpdated addObject:object];
    }
    id was = [[old retain] autorelease];
    [self cd_registerUndo:^{
        [object cd_restoreValue:was forKey:key];
    }];
    [self cd_scheduleProcessing];
}

- (void)insertObject:(NSManagedObject *)object
{
    if (!object)
        CDRaise(NSInvalidArgumentException, @"-insertObject: needs an object");
    NSManagedObjectContext *theirs = [object managedObjectContext];
    if (theirs == self && ![object isDeleted])
        return;
    if (theirs && theirs != self)
        CDRaise(NSInvalidArgumentException,
                @"An NSManagedObject may only be in (or observed by) a single NSManagedObjectContext.");
    [self cd_insert:object awake:YES];
}

- (void)cd_insert:(NSManagedObject *)object awake:(BOOL)awake
{
    if (theirs_is_deleted_here(self, object)) {
        [self cd_undelete:object];
        return;
    }
    [object cd_setContext:self];
    [object cd_setInsertedFlag:YES];
    [object cd_setDeletedFlag:NO];
    [_registered setObject:object forKey:[object objectID]];
    [_inserted addObject:object];
    [_pInserted addObject:object];
    [_pDeleted removeObject:object];
    [self cd_registerUndo:^{
        [self cd_uninsert:object];
    }];
    if (awake)
        [object awakeFromInsert];
    [self cd_scheduleProcessing];
}

/* Undoing an insertion: the object leaves the context. */
- (void)cd_uninsert:(NSManagedObject *)object
{
    [object retain];
    [_inserted removeObject:object];
    [_updated removeObject:object];
    if ([_pInserted containsObject:object])
        [_pInserted removeObject:object];
    else
        [_pDeleted addObject:object];
    [_pUpdated removeObject:object];
    [_registered removeObjectForKey:[object objectID]];
    [object cd_setInsertedFlag:NO];
    [object cd_setContext:nil];
    [self cd_registerUndo:^{
        [self cd_insert:object awake:NO];
    }];
    [self cd_scheduleProcessing];
    [object release];
}

- (void)deleteObject:(NSManagedObject *)object
{
    if (!object)
        CDRaise(NSInvalidArgumentException, @"-deleteObject: needs an object");
    NSManagedObjectContext *theirs = [object managedObjectContext];
    if (!theirs)
        return;
    if (theirs != self)
        CDRaise(NSInvalidArgumentException, @"An NSManagedObject may only be deleted in its own context.");
    if ([object isDeleted])
        return;
    BOOL wasInserted = [object isInserted];
    [object prepareForDeletion];
    [object cd_setDeletedFlag:YES];
    if (wasInserted) {
        [_inserted removeObject:object];
        [object cd_setInsertedFlag:NO];
    } else
        [_deleted addObject:object];
    if ([_pInserted containsObject:object])
        [_pInserted removeObject:object];
    else
        [_pDeleted addObject:object];
    [_pUpdated removeObject:object];
    [self cd_registerUndo:^{
        [self cd_undelete:object wasInserted:wasInserted];
    }];
    if ([self cd_maintainsInverses])
        [self cd_propagateDeletionOf:object];
    [self cd_scheduleProcessing];
}

- (void)cd_undelete:(NSManagedObject *)object { [self cd_undelete:object wasInserted:NO]; }

- (void)cd_undelete:(NSManagedObject *)object wasInserted:(BOOL)wasInserted
{
    [object cd_setDeletedFlag:NO];
    [_deleted removeObject:object];
    if (wasInserted) {
        [object cd_setInsertedFlag:YES];
        [_inserted addObject:object];
    }
    if ([_pDeleted containsObject:object])
        [_pDeleted removeObject:object];
    else
        [_pInserted addObject:object];
    [self cd_registerUndo:^{
        [self deleteObject:object];
    }];
    [self cd_scheduleProcessing];
}

/* The delete rules: cascade deletes the destinations, nullify takes the object out of
 * their inverse; deny is checked when saving, and no action does nothing. */
- (void)cd_propagateDeletionOf:(NSManagedObject *)object
{
    for (NSPropertyDescription *p in [[object entity] cd_allProperties]) {
        if (![p isKindOfClass:[NSRelationshipDescription class]])
            continue;
        NSRelationshipDescription *r = (id)p;
        NSDeleteRule rule = [r deleteRule];
        if (rule != NSCascadeDeleteRule && rule != NSNullifyDeleteRule)
            continue;
        id v = [object primitiveValueForKey:[r name]];
        NSArray *dests = [r isToMany] ? ([v isKindOfClass:[NSOrderedSet class]] ? [v array] : [v allObjects])
                                      : (v ? @[ v ] : @[]);
        for (NSManagedObject *d in dests) {
            if (rule == NSCascadeDeleteRule) {
                if (![d isDeleted])
                    [self deleteObject:d];
                continue;
            }
            NSRelationshipDescription *inv = [r inverseRelationship];
            if (!inv || [d isDeleted])
                continue;
            if ([inv isToMany]) {
                id cur = [d primitiveValueForKey:[inv name]];
                if (![cur containsObject:object])
                    continue;
                id m = [[cur mutableCopy] autorelease];
                [m removeObject:object];
                [d cd_restoreValue:m forKey:[inv name]];
            } else if ([d primitiveValueForKey:[inv name]] == object)
                [d cd_restoreValue:nil forKey:[inv name]];
        }
    }
}

- (void)processPendingChanges
{
    if (_processing)
        return;
    _processing = YES;
    _scheduled = NO;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSMutableSet *upd = [[_pUpdated mutableCopy] autorelease];
    [upd minusSet:_pInserted];
    [upd minusSet:_pDeleted];
    if ([_pInserted count])
        [info setObject:[[_pInserted copy] autorelease] forKey:NSInsertedObjectsKey];
    if ([upd count])
        [info setObject:[[upd copy] autorelease] forKey:NSUpdatedObjectsKey];
    if ([_pDeleted count])
        [info setObject:[[_pDeleted copy] autorelease] forKey:NSDeletedObjectsKey];
    if ([_pRefreshed count])
        [info setObject:[[_pRefreshed copy] autorelease] forKey:NSRefreshedObjectsKey];
    if ([_pInvalidated count])
        [info setObject:[[_pInvalidated copy] autorelease] forKey:NSInvalidatedObjectsKey];
    [_pInserted removeAllObjects];
    [_pUpdated removeAllObjects];
    [_pDeleted removeAllObjects];
    [_pRefreshed removeAllObjects];
    [_pInvalidated removeAllObjects];
    if ([info count])
        [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextObjectsDidChangeNotification
                                                            object:self
                                                          userInfo:info];
    _processing = NO;
}

/* ---- undo ---- */

- (void)undo { [_undo undo]; }
- (void)redo { [_undo redo]; }

- (void)rollback
{
    [self processPendingChanges];
    [_undo removeAllActions];
    for (NSManagedObject *o in [[_inserted copy] autorelease]) {
        [_registered removeObjectForKey:[o objectID]];
        [o cd_setInsertedFlag:NO];
        [o cd_setContext:nil];
        [_pInvalidated addObject:o];
    }
    NSMutableSet *revert = [NSMutableSet setWithSet:_updated];
    [revert unionSet:_deleted];
    for (NSManagedObject *o in revert) {
        if ([o managedObjectContext] != self)
            continue;
        [o cd_setDeletedFlag:NO];
        [o cd_notifyAllAround:^{
            [o cd_turnIntoFault];
        }];
        [_pRefreshed addObject:o];
    }
    [_inserted removeAllObjects];
    [_updated removeAllObjects];
    [_deleted removeAllObjects];
    [self processPendingChanges];
}

- (void)reset
{
    [_undo removeAllActions];
    NSArray *ids = [_registered allKeys];
    for (NSManagedObject *o in [_registered allValues]) {
        [o cd_turnIntoFault];
        [o cd_setInsertedFlag:NO];
        [o cd_setDeletedFlag:NO];
        [o cd_setContext:nil];
    }
    [_registered removeAllObjects];
    [_snapshots removeAllObjects];
    [_inserted removeAllObjects];
    [_updated removeAllObjects];
    [_deleted removeAllObjects];
    [_pInserted removeAllObjects];
    [_pUpdated removeAllObjects];
    [_pDeleted removeAllObjects];
    [_pRefreshed removeAllObjects];
    [_pInvalidated removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextObjectsDidChangeNotification
                                                        object:self
                                                      userInfo:@{NSInvalidatedAllObjectsKey : ids}];
}

- (void)refreshObject:(NSManagedObject *)object mergeChanges:(BOOL)flag
{
    if ([object managedObjectContext] != self || [object isInserted])
        return;
    NSManagedObjectID *oid = [object objectID];
    if ([object isFault]) {
        [_snapshots removeObjectForKey:oid];
        return;
    }
    if (!flag) {
        [object cd_notifyAllAround:^{
            [_snapshots removeObjectForKey:oid];
            [object cd_turnIntoFault];
        }];
        [_updated removeObject:object];
        [_pRefreshed addObject:object];
        [self cd_scheduleProcessing];
        return;
    }
    NSDictionary *changes = [object cd_changedStorableValues];
    CDSnapshot *fresh = [[[[self cd_parent] cd_snapshotForID:oid] copy] autorelease];
    if (!fresh)
        return;
    /* merging keeps the transient values too */
    NSMutableDictionary *transients = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *p in [[object entity] cd_allProperties])
        if ([p isTransient] && [object primitiveValueForKey:[p name]])
            [transients setObject:[object primitiveValueForKey:[p name]] forKey:[p name]];
    [object cd_notifyAllAround:^{
        [_snapshots setObject:fresh forKey:oid];
        [object cd_turnIntoFault];
        [object cd_fillFromSnapshot:fresh];
        for (NSString *k in transients)
            [object setPrimitiveValue:[transients objectForKey:k] forKey:k];
        for (NSString *k in changes) {
            id v = [changes objectForKey:k];
            NSRelationshipDescription *r = (id)[[object entity] cd_propertyNamed:k];
            if (v == [NSNull null])
                v = nil;
            else if ([r isKindOfClass:[NSRelationshipDescription class]]) {
                if ([r isToMany]) {
                    NSMutableArray *objs = [NSMutableArray array];
                    for (NSManagedObjectID *x in v)
                        [objs addObject:[self objectWithID:x]];
                    v = objs;
                } else
                    v = [self objectWithID:v];
            }
            [object setPrimitiveValue:v forKey:k];
        }
    }];
    if (![changes count])
        [_updated removeObject:object];
    [_pRefreshed addObject:object];
    [self cd_scheduleProcessing];
}

- (void)refreshAllObjects
{
    for (NSManagedObject *o in [_registered allValues])
        [self refreshObject:o mergeChanges:YES];
}

- (void)detectConflictsForObject:(NSManagedObject *)object
{
    if (object && ![object isInserted])
        [_updated addObject:object];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
}

- (void)assignObject:(id)object toPersistentStore:(NSPersistentStore *)store
{
    NSManagedObject *o = object;
    if (![o isInserted] || ![[o objectID] isTemporaryID])
        return;
    int64_t pk = [store cd_reservePKs:1 forEntity:[[o entity] cd_root]];
    [self cd_rekey:o to:[NSManagedObjectID cd_IDForEntity:[o entity] store:store pk:pk]];
}

/* ---- fetching ---- */

- (NSEntityDescription *)cd_entityForRequest:(NSFetchRequest *)request
{
    NSEntityDescription *e = [request entity];
    if (!e && [request entityName])
        e = [[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName]
            objectForKey:[request entityName]];
    if (!e)
        CDRaise(NSInvalidArgumentException, @"executeFetchRequest:error: A fetch request must have an entity.");
    return e;
}

- (BOOL)cd_hasPendingChangesFor:(NSArray *)names
{
    for (NSSet *set in @[ _inserted, _updated, _deleted ])
        for (NSManagedObject *o in set)
            if ([names containsObject:[[o entity] name]])
                return YES;
    return NO;
}

- (NSArray *)cd_objectsForRequest:(NSFetchRequest *)request error:(NSError **)error
{
    NSEntityDescription *entity = [self cd_entityForRequest:request];
    if (![[request entity] isEqual:entity])
        [request setEntity:entity];
    NSArray *names = [request includesSubentities] ? [entity cd_selfAndSubentityNames] : @[ [entity name] ];
    BOOL pendingHere = [request includesPendingChanges] && [self cd_hasPendingChangesFor:names];
    CDQuery *q = [[[CDQuery alloc] init] autorelease];
    q->request = [request retain];
    q->entity = [entity retain];
    q->entityNames = [names retain];
    q->storeLimit = !pendingHere;
    BOOL limited = NO;
    id<CDParent> parent = [self cd_parent];
    if (!parent)
        CDRaise(NSInternalInconsistencyException, @"This context has no coordinator and no parent context");
    NSArray *snaps = [parent cd_snapshotsForQuery:q limited:&limited error:error];
    if (!snaps)
        return nil;
    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    BOOL exact = q->exact;
    for (CDSnapshot *s in snaps) {
        NSManagedObject *o = [self cd_registered:s->oid];
        if (!o) {
            o = [NSManagedObject cd_faultWithEntity:[s->oid entity] objectID:s->oid context:self];
            [_registered setObject:o forKey:s->oid];
            [_snapshots setObject:[[s copy] autorelease] forKey:s->oid];
        } else if ([o isFault])
            [_snapshots setObject:[[s copy] autorelease] forKey:[o objectID]];
        else if ([request shouldRefreshRefetchedObjects]) {
            [_snapshots setObject:[[s copy] autorelease] forKey:[o objectID]];
            [self refreshObject:o mergeChanges:YES];
        }
        if ([request includesPendingChanges] && [o isDeleted])
            continue;
        if ([seen containsObject:[NSValue valueWithPointer:o]])
            continue;
        [seen addObject:[NSValue valueWithPointer:o]];
        [candidates addObject:o];
    }
    NSSet *fromParent = [[seen copy] autorelease];
    if ([request includesPendingChanges])
        for (NSSet *set in @[ _inserted, _updated ])
            for (NSManagedObject *o in set) {
                if ([o isDeleted] || ![names containsObject:[[o entity] name]] ||
                    [seen containsObject:[NSValue valueWithPointer:o]])
                    continue;
                [seen addObject:[NSValue valueWithPointer:o]];
                [candidates addObject:o];
            }
    NSMutableArray *wereFaults = [NSMutableArray array];
    for (NSManagedObject *o in candidates)
        if ([o isFault])
            [wereFaults addObject:o];
    NSFetchRequest *sortOnly = request;
    if ([request predicate] && (![request includesPendingChanges] || exact)) {
        /* What the store matched exactly needs no second look, unless it changed here;
         * without pending changes, the predicate is put to an object's stored values. */
        NSPredicate *p = [request predicate];
        BOOL pending = [request includesPendingChanges];
        NSMutableArray *kept = [NSMutableArray array];
        for (NSManagedObject *o in candidates) {
            if (exact && [fromParent containsObject:[NSValue valueWithPointer:o]] && (!pending || ![o hasChanges])) {
                [kept addObject:o];
                continue;
            }
            CDSnapshot *snap = !pending && [o hasChanges] ? [_snapshots objectForKey:[o objectID]] : nil;
            id subject = o;
            if (snap) {
                NSMutableDictionary *d = [NSMutableDictionary dictionary];
                for (NSString *k in snap->values) {
                    id v = [snap->values objectForKey:k];
                    if ([v isKindOfClass:[NSManagedObjectID class]])
                        v = [self objectWithID:v];
                    else if ([v isKindOfClass:[NSArray class]]) {
                        NSMutableArray *objs = [NSMutableArray array];
                        for (id x in v)
                            [objs addObject:[x isKindOfClass:[NSManagedObjectID class]] ? [self objectWithID:x] : x];
                        v = [NSSet setWithArray:objs];
                    }
                    [d setObject:v forKey:k];
                }
                subject = d;
            }
            if ([p evaluateWithObject:subject])
                [kept addObject:o];
        }
        candidates = kept;
        sortOnly = [[request copy] autorelease];
        [sortOnly setPredicate:nil];
    }
    NSArray *results = CDFilterSortLimit(candidates, sortOnly, limited);
    if ([request returnsObjectsAsFaults] || [request resultType] != NSManagedObjectResultType) {
        for (NSManagedObject *o in wereFaults)
            if (![o isFault] && ![o hasChanges])
                [o cd_turnIntoFault];
    } else
        for (NSManagedObject *o in results)
            [o willAccessValueForKey:nil];
    return results;
}

static NSArray *dictionary_results(NSArray *objects, NSFetchRequest *request, NSEntityDescription *entity)
{
    NSMutableArray *props = [NSMutableArray array];
    for (id p in [request propertiesToFetch] ?: [entity cd_persistentAttributes]) {
        NSPropertyDescription *d = [p isKindOfClass:[NSString class]] ? [entity cd_propertyNamed:p] : p;
        if ([d isKindOfClass:[NSPropertyDescription class]])
            [props addObject:d];
    }
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *distinct = [NSMutableSet set];
    for (NSManagedObject *o in objects) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (NSPropertyDescription *p in props) {
            id v = [o valueForKey:[p name]];
            if ([v isKindOfClass:[NSManagedObject class]])
                v = [v objectID];
            else if ([v isKindOfClass:[NSSet class]] || [v isKindOfClass:[NSOrderedSet class]])
                continue;
            if (v)
                [d setObject:v forKey:[p name]];
        }
        if ([request returnsDistinctResults]) {
            if ([distinct containsObject:d])
                continue;
            [distinct addObject:d];
        }
        [out addObject:d];
    }
    return out;
}

- (NSArray *)executeFetchRequest:(NSFetchRequest *)request error:(NSError **)error
{
    if (!request)
        CDRaise(NSInvalidArgumentException, @"executeFetchRequest:error: needs a fetch request");
    [self processPendingChanges];
    BOOL dictionaries = [request resultType] == NSDictionaryResultType;
    NSFetchRequest *all = request;
    if (dictionaries && CDGroupsResults(request)) {   /* the groups are sorted and limited, not the objects */
        all = [[request copy] autorelease];
        [all setSortDescriptors:nil];
        [all setFetchOffset:0];
        [all setFetchLimit:0];
    }
    NSArray *objects = [self cd_objectsForRequest:all error:error];
    if (!objects)
        return nil;
    if (dictionaries && CDFetchesExpressions(request))
        return CDExpressionResults(objects, request, [self cd_entityForRequest:request]);
    switch ([request resultType]) {
    case NSManagedObjectIDResultType: return [objects valueForKey:@"objectID"];
    case NSDictionaryResultType: return dictionary_results(objects, request, [self cd_entityForRequest:request]);
    case NSCountResultType: return @[ @([objects count]) ];
    default: return objects;
    }
}

- (NSUInteger)countForFetchRequest:(NSFetchRequest *)request error:(NSError **)error
{
    [self processPendingChanges];
    NSEntityDescription *entity = [self cd_entityForRequest:request];
    NSArray *names = [request includesSubentities] ? [entity cd_selfAndSubentityNames] : @[ [entity name] ];
    if (!([request includesPendingChanges] && [self cd_hasPendingChangesFor:names])) {
        CDQuery *q = [[[CDQuery alloc] init] autorelease];
        q->request = [request retain];
        q->entity = [entity retain];
        q->entityNames = [names retain];
        q->storeLimit = YES;
        NSUInteger n = [[self cd_parent] cd_countForQuery:q];
        if (n != NSNotFound)
            return n;
    }
    NSArray *objects = [self cd_objectsForRequest:request error:error];
    return objects ? [objects count] : NSNotFound;
}

- (NSPersistentStoreResult *)executeRequest:(NSPersistentStoreRequest *)request error:(NSError **)error
{
    if ([request isKindOfClass:[NSFetchRequest class]]) {
        CDFail(error, NSPersistentStoreUnsupportedRequestTypeError,
               @"Use executeFetchRequest:error: for fetch requests.", nil);
        return nil;
    }
    __block id result = nil;
    [self cd_performAndWait:^{
        result = [[[self persistentStoreCoordinator] executeRequest:request withContext:self error:error] retain];
    }];
    return [result autorelease];
}

/* ---- saving ---- */

- (BOOL)obtainPermanentIDsForObjects:(NSArray *)objects error:(NSError **)error
{
    NSMutableArray *temps = [NSMutableArray array];
    for (NSManagedObject *o in objects)
        if ([[o objectID] isTemporaryID])
            [temps addObject:o];
    if (![temps count])
        return YES;
    NSArray *ids = [[self persistentStoreCoordinator] cd_permanentIDsForTemporaryIDs:[temps valueForKey:@"objectID"]
                                                                                error:error];
    if (!ids)
        return NO;
    for (NSUInteger i = 0; i < [temps count]; i++)
        [self cd_rekey:[temps objectAtIndex:i] to:[ids objectAtIndex:i]];
    return YES;
}

static NSError *combined_error(NSArray *errors)
{
    if ([errors count] == 1)
        return [errors objectAtIndex:0];
    NSMutableArray *flat = [NSMutableArray array];
    for (NSError *e in errors) {
        if ([e code] == NSValidationMultipleErrorsError && [[e userInfo] objectForKey:NSDetailedErrorsKey])
            [flat addObjectsFromArray:[[e userInfo] objectForKey:NSDetailedErrorsKey]];
        else
            [flat addObject:e];
    }
    return CDError(NSValidationMultipleErrorsError, @"Multiple validation errors occurred.", @{NSDetailedErrorsKey : flat});
}

- (BOOL)save:(NSError **)error
{
    id<CDParent> parent = [self cd_parent];
    if (!parent)
        CDRaise(NSInternalInconsistencyException, @"This context has no coordinator and no parent context");
    if (_saving)
        CDRaise(NSInternalInconsistencyException, @"Recursive call to save: attempted");
    [self processPendingChanges];
    if (![self hasChanges])
        return YES;
    _saving = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextWillSaveNotification
                                                        object:self];
    NSMutableSet *all = [NSMutableSet setWithSet:_inserted];
    [all unionSet:[self updatedObjects]];
    [all unionSet:_deleted];
    for (NSManagedObject *o in all)
        [o willSave];
    [self processPendingChanges];

    NSArray *inserted = [_inserted allObjects], *updated = [[self updatedObjects] allObjects],
            *deleted = [_deleted allObjects];
    NSMutableArray *errors = [NSMutableArray array];
    for (NSManagedObject *o in inserted) {
        NSError *e = nil;
        if (![o validateForInsert:&e])
            [errors addObject:e ?: CDError(NSManagedObjectValidationError, nil, nil)];
    }
    for (NSManagedObject *o in updated) {
        NSError *e = nil;
        if (![o validateForUpdate:&e])
            [errors addObject:e ?: CDError(NSManagedObjectValidationError, nil, nil)];
    }
    for (NSManagedObject *o in deleted) {
        NSError *e = nil;
        if (![o validateForDelete:&e])
            [errors addObject:e ?: CDError(NSManagedObjectValidationError, nil, nil)];
    }
    if ([errors count]) {
        _saving = NO;
        if (error)
            *error = combined_error(errors);
        return NO;
    }
    if (!_parent && ![self obtainPermanentIDsForObjects:inserted error:error]) {
        _saving = NO;
        return NO;
    }

    CDChangeSet *set = [[[CDChangeSet alloc] init] autorelease];
    set->policy = policy_type(_mergePolicy);
    for (NSManagedObject *o in inserted) {
        CDChange *c = [[[CDChange alloc] init] autorelease];
        c->oid = [[o objectID] retain];
        c->values = [[o cd_loadedValues] retain];
        c->object = [o retain];
        [set->inserted addObject:c];
    }
    for (NSManagedObject *o in updated) {
        CDSnapshot *s = [_snapshots objectForKey:[o objectID]];
        CDChange *c = [[[CDChange alloc] init] autorelease];
        c->oid = [[o objectID] retain];
        c->values = [[o cd_changedStorableValues] retain];
        c->allValues = [[o cd_loadedValues] retain];
        c->committed = [s->values copy];
        c->version = s ? s->version : 0;
        c->object = [o retain];
        [set->updated addObject:c];
    }
    for (NSManagedObject *o in deleted) {
        CDSnapshot *s = [_snapshots objectForKey:[o objectID]];
        CDChange *c = [[[CDChange alloc] init] autorelease];
        c->oid = [[o objectID] retain];
        c->committed = [s->values copy];
        c->version = s ? s->version : 0;
        c->object = [o retain];
        [set->deleted addObject:c];
    }
    BOOL ok = [parent cd_saveChanges:set error:error];
    if (!ok) {
        _saving = NO;
        return NO;
    }

    /* what was saved is now what is committed */
    for (CDChange *c in set->inserted) {
        NSNumber *v = [set->versions objectForKey:c->oid];
        [_snapshots setObject:[CDSnapshot snapshotWithID:c->oid values:c->values version:v ? [v longLongValue] : 1]
                       forKey:c->oid];
        [c->object cd_setInsertedFlag:NO];
    }
    for (CDChange *c in set->updated) {
        CDSnapshot *s = [_snapshots objectForKey:c->oid];
        if (!s) {
            s = [CDSnapshot snapshotWithID:c->oid values:nil version:0];
            [_snapshots setObject:s forKey:c->oid];
        }
        [s->values addEntriesFromDictionary:c->values];
        NSNumber *v = [set->versions objectForKey:c->oid];
        if (v)
            s->version = [v longLongValue];
    }
    for (NSManagedObjectID *oid in set->refreshIDs) {
        NSManagedObject *o = [_registered objectForKey:oid];
        [_snapshots removeObjectForKey:oid];
        if (o)
            [o cd_notifyAllAround:^{
                [o cd_turnIntoFault];
            }];
    }
    for (NSManagedObject *o in deleted) {
        [_registered removeObjectForKey:[o objectID]];
        [_snapshots removeObjectForKey:[o objectID]];
        [o cd_setDeletedFlag:NO];
        [o cd_turnIntoFault];
        [o cd_setContext:nil];
    }
    for (NSManagedObject *o in all)
        [o cd_clearTransientChanges];
    [_inserted removeAllObjects];
    [_updated removeAllObjects];
    [_deleted removeAllObjects];
    for (NSManagedObject *o in inserted)
        [o didSave];
    for (NSManagedObject *o in updated)
        [o didSave];
    for (NSManagedObject *o in deleted)
        [o didSave];
    _saving = NO;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if ([inserted count])
        [info setObject:[NSSet setWithArray:inserted] forKey:NSInsertedObjectsKey];
    if ([updated count])
        [info setObject:[NSSet setWithArray:updated] forKey:NSUpdatedObjectsKey];
    if ([deleted count])
        [info setObject:[NSSet setWithArray:deleted] forKey:NSDeletedObjectsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextDidSaveNotification
                                                        object:self
                                                      userInfo:info];
    return YES;
}

/* ---- merging ---- */

- (void)cd_mergeInserted:(NSArray *)ins updated:(NSArray *)upd deleted:(NSArray *)del
{
    [self processPendingChanges];
    NSMutableSet *inserted = [NSMutableSet set], *refreshed = [NSMutableSet set], *deleted = [NSMutableSet set];
    for (NSManagedObjectID *oid in del) {
        NSManagedObject *o = [self cd_registered:oid];
        if (!o)
            continue;
        [o retain];
        [_snapshots removeObjectForKey:[o objectID]];
        [_registered removeObjectForKey:[o objectID]];
        [_inserted removeObject:o];
        [_updated removeObject:o];
        [_deleted removeObject:o];
        [o cd_turnIntoFault];
        [o cd_setContext:nil];
        [deleted addObject:o];
        [o release];
    }
    for (NSManagedObjectID *oid in upd) {
        NSManagedObject *o = [self cd_registered:oid];
        if (!o)
            continue;
        if ([o isFault])
            [_snapshots removeObjectForKey:[o objectID]];
        else
            [self refreshObject:o mergeChanges:YES];
        [refreshed addObject:o];
    }
    for (NSManagedObjectID *oid in ins) {
        NSManagedObject *o = [self objectWithID:oid];
        if (o && ![o isDeleted])
            [inserted addObject:o];
    }
    [_pRefreshed removeAllObjects];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if ([inserted count])
        [info setObject:inserted forKey:NSInsertedObjectsKey];
    if ([refreshed count])
        [info setObject:refreshed forKey:NSRefreshedObjectsKey];
    if ([deleted count])
        [info setObject:deleted forKey:NSDeletedObjectsKey];
    if ([info count])
        [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextObjectsDidChangeNotification
                                                            object:self
                                                          userInfo:info];
}

- (void)mergeChangesFromContextDidSaveNotification:(NSNotification *)note
{
    NSDictionary *info = [note userInfo];
    NSMutableArray *ins = [NSMutableArray arrayWithArray:ids_of([info objectForKey:NSInsertedObjectsKey])];
    NSMutableArray *upd = [NSMutableArray arrayWithArray:ids_of([info objectForKey:NSUpdatedObjectsKey])];
    NSMutableArray *del = [NSMutableArray arrayWithArray:ids_of([info objectForKey:NSDeletedObjectsKey])];
    [ins addObjectsFromArray:ids_of([info objectForKey:NSInsertedObjectIDsKey])];
    [upd addObjectsFromArray:ids_of([info objectForKey:NSUpdatedObjectIDsKey])];
    [del addObjectsFromArray:ids_of([info objectForKey:NSDeletedObjectIDsKey])];
    [self cd_performAndWait:^{
        [self cd_mergeInserted:ins updated:upd deleted:del];
    }];
}

+ (void)mergeChangesFromRemoteContextSave:(NSDictionary *)data intoContexts:(NSArray *)contexts
{
    for (NSManagedObjectContext *ctx in contexts) {
        NSPersistentStoreCoordinator *c = [ctx persistentStoreCoordinator];
        NSArray * (^ids)(NSArray *) = ^NSArray *(NSArray *keys) {
            NSMutableArray *out = [NSMutableArray array];
            for (NSString *k in keys)
                for (id x in [data objectForKey:k]) {
                    if ([x isKindOfClass:[NSURL class]]) {
                        NSManagedObjectID *oid = [c managedObjectIDForURIRepresentation:x];
                        if (oid)
                            [out addObject:oid];
                    } else
                        [out addObjectsFromArray:ids_of(@[ x ])];
                }
            return out;
        };
        NSArray *ins = ids(@[ NSInsertedObjectsKey, NSInsertedObjectIDsKey ]);
        NSArray *upd = ids(@[ NSUpdatedObjectsKey, NSUpdatedObjectIDsKey ]);
        NSArray *del = ids(@[ NSDeletedObjectsKey, NSDeletedObjectIDsKey ]);
        [ctx performBlockAndWait:^{
            [ctx cd_mergeInserted:ins updated:upd deleted:del];
        }];
    }
}

/* ---- serving a child context ---- */

- (NSArray *)cd_snapshotsForQuery:(CDQuery *)q limited:(BOOL *)limited error:(NSError **)error
{
    __block NSMutableArray *out = nil;
    __block NSError *err = nil;
    [self cd_performAndWait:^{
        NSFetchRequest *r = [[q->request copy] autorelease];
        [r setResultType:NSManagedObjectResultType];
        [r setIncludesPendingChanges:YES];
        [r setReturnsObjectsAsFaults:YES];
        if (!q->storeLimit) {
            [r setFetchLimit:0];
            [r setFetchOffset:0];
        }
        NSArray *objs = [self executeFetchRequest:r error:&err];
        if (!objs)
            return;
        out = [[NSMutableArray alloc] init];
        for (NSManagedObject *o in objs) {
            [o willAccessValueForKey:nil];
            CDSnapshot *s = [_snapshots objectForKey:[o objectID]];
            [out addObject:[CDSnapshot snapshotWithID:[o objectID]
                                               values:[o cd_loadedValues]
                                              version:s ? s->version : 0]];
        }
        [err retain];
    }];
    if (limited)
        *limited = q->storeLimit;
    q->exact = out != nil;   /* this context evaluated the whole predicate */
    if (!out && error)
        *error = [err autorelease];
    else
        [err release];
    return [out autorelease];
}

- (NSUInteger)cd_countForQuery:(CDQuery *)query { return NSNotFound; }

- (CDSnapshot *)cd_snapshotForID:(NSManagedObjectID *)oid
{
    __block CDSnapshot *out = nil;
    [self cd_performAndWait:^{
        NSManagedObject *o = [self cd_registered:oid];
        if (o) {
            if ([o isDeleted])
                return;
            @try {
                [o willAccessValueForKey:nil];
            } @catch (NSException *e) {
                return;
            }
            if ([o isDeleted])
                return;
            CDSnapshot *s = [_snapshots objectForKey:[o objectID]];
            out = [[CDSnapshot snapshotWithID:oid values:[o cd_loadedValues] version:s ? s->version : 0] retain];
            return;
        }
        out = [[[self cd_parent] cd_snapshotForID:oid] copy];
    }];
    return [out autorelease];
}

- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key
{
    __block NSArray *out = nil;
    [self cd_performAndWait:^{
        NSManagedObject *o = [self cd_registered:oid];
        if (o) {
            id v = [o primitiveValueForKey:key];
            NSMutableArray *ids = [NSMutableArray array];
            for (NSManagedObject *x in ([v isKindOfClass:[NSOrderedSet class]] ? [v array] : [v allObjects]))
                if (![x isDeleted])
                    [ids addObject:[x objectID]];
            out = [ids retain];
            return;
        }
        out = [[[self cd_parent] cd_relatedIDsForID:oid key:key] retain];
    }];
    return [out autorelease];
}

/* A child's save: its changes become this context's own (not undoable here). */
- (BOOL)cd_saveChanges:(CDChangeSet *)set error:(NSError **)error
{
    [self cd_performAndWait:^{
        [_undo disableUndoRegistration];
        NSMutableArray *made = [NSMutableArray array];
        for (CDChange *c in set->inserted) {
            NSManagedObject *o = [self cd_registered:c->oid];
            if (!o) {
                o = [NSManagedObject cd_faultWithEntity:[c->oid entity] objectID:c->oid context:self];
                [_registered setObject:o forKey:c->oid];
            }
            [o cd_fillFromSnapshot:[CDSnapshot snapshotWithID:c->oid values:nil version:0]];
            [o cd_setInsertedFlag:YES];
            [o cd_setDeletedFlag:NO];
            [_inserted addObject:o];
            [_pInserted addObject:o];
            [made addObject:o];
        }
        for (NSUInteger i = 0; i < [made count]; i++) {
            CDChange *c = [set->inserted objectAtIndex:i];
            NSManagedObject *o = [made objectAtIndex:i];
            for (NSString *k in c->values)
                [o cd_applyStoredValue:[c->values objectForKey:k] forKey:k];
        }
        for (CDChange *c in set->updated) {
            NSManagedObject *o = [self objectWithID:c->oid];
            for (NSString *k in c->values)
                [o cd_applyStoredValue:[c->values objectForKey:k] forKey:k];
        }
        for (CDChange *c in set->deleted) {
            NSManagedObject *o = [self objectWithID:c->oid];
            if (![o isDeleted])
                [self deleteObject:o];
        }
        [_undo enableUndoRegistration];
        [self cd_scheduleProcessing];
    }];
    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSManagedObjectContext: %p>%@", self,
                                      _name ? [NSString stringWithFormat:@" (%@)", _name] : @""];
}
@end
