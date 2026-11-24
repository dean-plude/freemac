/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: the persistent store coordinator, the store base
 * class, and the in-memory and binary stores, as Apple's class
 * references describe them (freemac 1.209, Ferry 0.35.0). Our own code;
 * no Apple code was used.
 *
 * The coordinator hands each fetch to the stores that hold the entity
 * (by their configuration), gives inserted objects their permanent IDs
 * from the first store that holds the entity, and hands each store its
 * part of a save. A save that spans several stores is applied store by
 * store, not as one transaction.
 *
 * A store keeps, in its metadata, the model's version hashes and Ferry's
 * own description of the stored shape of each entity (under the key
 * FerryStoreSchema). With the migration options, a store whose model
 * changed is opened when what changed can be inferred: entities,
 * attributes and relationships added (a new non-optional attribute needs a
 * default value), and ones removed; a changed type can't be.
 *
 * The binary store is the in-memory store written to one file with
 * Ferry's keyed archiver after each save. */
#import "CDInternal.h"

NSString *const NSSQLiteStoreType CD_EXPORT = @"SQLite";
NSString *const NSXMLStoreType CD_EXPORT = @"XML";
NSString *const NSBinaryStoreType CD_EXPORT = @"Binary";
NSString *const NSInMemoryStoreType CD_EXPORT = @"InMemory";
NSString *const NSStoreTypeKey CD_EXPORT = @"NSStoreType";
NSString *const NSStoreUUIDKey CD_EXPORT = @"NSStoreUUID";
NSString *const NSStoreModelVersionHashesKey CD_EXPORT = @"NSStoreModelVersionHashes";
NSString *const NSStoreModelVersionIdentifiersKey CD_EXPORT = @"NSStoreModelVersionIdentifiers";
NSString *const NSPersistentStoreOSCompatibility CD_EXPORT = @"NSPersistentStoreOSCompatibility";
NSString *const NSReadOnlyPersistentStoreOption CD_EXPORT = @"NSReadOnlyPersistentStoreOption";
NSString *const NSPersistentStoreTimeoutOption CD_EXPORT = @"NSPersistentStoreTimeoutOption";
NSString *const NSSQLitePragmasOption CD_EXPORT = @"NSSQLitePragmasOption";
NSString *const NSSQLiteAnalyzeOption CD_EXPORT = @"NSSQLiteAnalyzeOption";
NSString *const NSSQLiteManualVacuumOption CD_EXPORT = @"NSSQLiteManualVacuumOption";
NSString *const NSMigratePersistentStoresAutomaticallyOption CD_EXPORT = @"NSMigratePersistentStoresAutomaticallyOption";
NSString *const NSInferMappingModelAutomaticallyOption CD_EXPORT = @"NSInferMappingModelAutomaticallyOption";
NSString *const NSPersistentHistoryTrackingKey CD_EXPORT = @"NSPersistentHistoryTracking";
NSString *const NSPersistentStoreRemoteChangeNotificationPostOptionKey CD_EXPORT =
    @"NSPersistentStoreRemoteChangeNotificationOptionKey";
NSString *const NSPersistentStoreCoordinatorStoresDidChangeNotification CD_EXPORT =
    @"NSPersistentStoreCoordinatorStoresDidChangeNotification";
NSString *const NSPersistentStoreCoordinatorStoresWillChangeNotification CD_EXPORT =
    @"NSPersistentStoreCoordinatorStoresWillChangeNotification";
NSString *const NSAddedPersistentStoresKey CD_EXPORT = @"added";
NSString *const NSRemovedPersistentStoresKey CD_EXPORT = @"removed";
NSString *const NSUUIDChangedPersistentStoresKey CD_EXPORT = @"changedUUID";

static NSString *const schema_key = @"FerryStoreSchema";

/* ---- conflicts and schema checks ------------------------------------------------------------ */

BOOL CDResolveConflicts(CDChangeSet *set, CDSnapshot * (^current)(NSManagedObjectID *), NSError **error)
{
    NSMutableArray *conflicted = [NSMutableArray array];
    NSMutableDictionary *currentRows = [NSMutableDictionary dictionary];
    for (NSArray *list in @[ set->updated, set->deleted ])
        for (CDChange *c in list) {
            CDSnapshot *cur = current(c->oid);
            if (cur && cur->version == c->version)
                continue;
            if (cur)
                [currentRows setObject:cur forKey:c->oid];
            NSMergeConflict *m = [[[NSMergeConflict alloc] initWithSource:c->object
                                                               newVersion:cur ? (NSUInteger)cur->version : 0
                                                               oldVersion:(NSUInteger)c->version
                                                           cachedSnapshot:c->committed
                                                        persistedSnapshot:cur ? cur->values : nil] autorelease];
            [set->conflicts addObject:m];
            [conflicted addObject:c];
        }
    if (![conflicted count])
        return YES;
    if (set->policy == NSErrorMergePolicyType)
        return CDFail(error, NSManagedObjectMergeError, @"Could not merge changes.",
                      @{NSPersistentStoreSaveConflictsErrorKey : [[set->conflicts copy] autorelease]});
    for (CDChange *c in conflicted) {
        CDSnapshot *cur = [currentRows objectForKey:c->oid];
        BOOL isUpdate = [set->updated containsObject:c];
        if (set->policy != NSOverwriteMergePolicyType)
            [set->refreshIDs addObject:c->oid];
        if (!cur) {
            /* the row is gone: nothing to update or delete */
            [set->updated removeObject:c];
            [set->deleted removeObject:c];
            continue;
        }
        switch (set->policy) {
        case NSRollbackMergePolicyType:
            [set->updated removeObject:c];
            [set->deleted removeObject:c];
            break;
        case NSOverwriteMergePolicyType:
            if (isUpdate && c->allValues) {
                [c->values release];
                c->values = [c->allValues copy];
            }
            break;
        case NSMergeByPropertyStoreTrumpMergePolicyType:
            if (isUpdate) {
                NSMutableDictionary *keep = [NSMutableDictionary dictionary];
                for (NSString *k in c->values)
                    if (CDEqual([cur->values objectForKey:k], [c->committed objectForKey:k]))
                        [keep setObject:[c->values objectForKey:k] forKey:k];
                [c->values release];
                c->values = [keep copy];
            }
            break;
        default:   /* by property, the object's changes win: write them over the stored row */
            break;
        }
    }
    return YES;
}

BOOL CDCheckSchema(NSManagedObjectModel *model, NSDictionary *metadata, NSDictionary *options,
                   NSMutableArray *added, NSError **error)
{
    if (!metadata)
        return YES;
    NSDictionary *hashes = [metadata objectForKey:NSStoreModelVersionHashesKey];
    if ([model isConfiguration:nil compatibleWithStoreMetadata:metadata] &&
        [hashes count] == [[model entities] count])
        return YES;
    BOOL migrate = [[options objectForKey:NSMigratePersistentStoresAutomaticallyOption] boolValue] &&
                   [[options objectForKey:NSInferMappingModelAutomaticallyOption] boolValue];
    if (!migrate)
        return CDFail(error, NSPersistentStoreIncompatibleVersionHashError,
                      @"The model used to open the store is incompatible with the one used to create the store.", nil);
    NSDictionary *old = [metadata objectForKey:schema_key];
    if (![old isKindOfClass:[NSDictionary class]])
        return CDFail(error, NSInferredMappingModelError, @"Can't find the store's model to infer a mapping from.", nil);
    for (NSEntityDescription *e in [model entities]) {
        NSDictionary *oe = [old objectForKey:[e name]];
        if (!oe) {
            [added addObject:@{@"kind" : @"entity", @"entity" : [e name]}];
            continue;
        }
        if (![[oe objectForKey:@"root"] isEqual:[[e cd_root] name]])
            return CDFail(error, NSInferredMappingModelError,
                          [NSString stringWithFormat:@"The entity %@ moved to another parent.", [e name]], nil);
        NSDictionary *oa = [oe objectForKey:@"attributes"], *orl = [oe objectForKey:@"relationships"];
        for (NSAttributeDescription *a in [e cd_persistentAttributes]) {
            NSNumber *t = [oa objectForKey:[a name]];
            if (!t) {
                if (![a isOptional] && ![a defaultValue])
                    return CDFail(error, NSMigrationError,
                                  [NSString stringWithFormat:@"The new attribute %@.%@ is required and has no default "
                                                             @"value.",
                                                             [e name], [a name]],
                                  nil);
                if ([[e superentity] cd_propertyNamed:[a name]] && [[old objectForKey:[[e superentity] name]]
                                                                         [@"attributes"] objectForKey:[a name]])
                    continue;
                [added addObject:@{@"kind" : @"attribute", @"entity" : [e name], @"name" : [a name]}];
            } else if ([t unsignedIntegerValue] != [a attributeType])
                return CDFail(error, NSInferredMappingModelError,
                              [NSString stringWithFormat:@"The attribute %@.%@ changed type.", [e name], [a name]], nil);
        }
        for (NSRelationshipDescription *r in [e cd_persistentRelationships]) {
            NSDictionary *o = [orl objectForKey:[r name]];
            if (!o) {
                [added addObject:@{@"kind" : @"relationship", @"entity" : [e name], @"name" : [r name]}];
                continue;
            }
            if ([[o objectForKey:@"toMany"] boolValue] != [r isToMany] ||
                ![[o objectForKey:@"destination"] isEqual:[[r destinationEntity] name]])
                return CDFail(error, NSInferredMappingModelError,
                              [NSString stringWithFormat:@"The relationship %@.%@ changed.", [e name], [r name]], nil);
        }
    }
    return YES;
}

/* ---- the store base class ------------------------------------------------------------------- */

@implementation NSPersistentStore {
@protected
    NSPersistentStoreCoordinator *_coordinator;   /* not retained */
    NSString *_configuration, *_identifier, *_type;
    NSURL *_URL;
    NSDictionary *_options;
    NSMutableDictionary *_metadata;
    BOOL _readOnly;
}
+ (NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error
{
    CDFail(error, NSPersistentStoreInvalidTypeError, @"This store type has no metadata to read.", nil);
    return nil;
}
+ (BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error
{
    return CDFail(error, NSPersistentStoreInvalidTypeError, @"This store type has no metadata to write.", nil);
}
- (instancetype)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                                 configurationName:(NSString *)name
                                               URL:(NSURL *)url
                                           options:(NSDictionary *)options
{
    if ((self = [super init])) {
        _coordinator = root;
        _configuration = [name copy];
        _URL = [url copy];
        _options = [options copy];
        _identifier = [[[NSUUID UUID] UUIDString] copy];
        _readOnly = [[options objectForKey:NSReadOnlyPersistentStoreOption] boolValue];
        _metadata = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_configuration release];
    [_identifier release];
    [_type release];
    [_URL release];
    [_options release];
    [_metadata release];
    [super dealloc];
}
- (BOOL)loadMetadata:(NSError **)error { return YES; }
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator { return _coordinator; }
- (NSPersistentStoreCoordinator *)cd_coordinatorRef { return _coordinator; }
- (NSString *)configurationName { return _configuration ?: @"PF_DEFAULT_CONFIGURATION_NAME"; }
- (NSDictionary *)options { return _options; }
- (NSURL *)URL { return _URL; }
- (void)setURL:(NSURL *)url
{
    [_URL autorelease];
    _URL = [url copy];
}
- (NSString *)identifier { return _identifier; }
- (void)setIdentifier:(NSString *)identifier
{
    [_identifier autorelease];
    _identifier = [identifier copy];
    [_metadata setObject:identifier forKey:NSStoreUUIDKey];
}
- (NSString *)type { return _type; }
- (void)cd_setType:(NSString *)type
{
    [_type autorelease];
    _type = [type copy];
}
- (BOOL)isReadOnly { return _readOnly; }
- (void)setReadOnly:(BOOL)flag { _readOnly = flag; }
- (NSDictionary *)metadata { return [[_metadata copy] autorelease]; }
- (void)setMetadata:(NSDictionary *)metadata
{
    [_metadata autorelease];
    _metadata = [metadata mutableCopy] ?: [[NSMutableDictionary alloc] init];
    [_metadata setObject:_type ?: @"" forKey:NSStoreTypeKey];
    [_metadata setObject:_identifier forKey:NSStoreUUIDKey];
}
- (void)didAddToPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator {}
- (void)willRemoveFromPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator {}

/* The metadata of a store made from (or migrated to) the coordinator's model. */
- (void)cd_stampMetadata
{
    NSManagedObjectModel *model = [_coordinator managedObjectModel];
    [_metadata setObject:_type ?: @"" forKey:NSStoreTypeKey];
    [_metadata setObject:_identifier forKey:NSStoreUUIDKey];
    [_metadata setObject:[model entityVersionHashesByName] ?: @{} forKey:NSStoreModelVersionHashesKey];
    [_metadata setObject:[[model versionIdentifiers] allObjects] ?: @[] forKey:NSStoreModelVersionIdentifiersKey];
    [_metadata setObject:[model cd_schema] ?: @{} forKey:schema_key];
}

/* What a store class that doesn't say otherwise answers. */
- (BOOL)cd_load:(NSError **)error { return YES; }
- (NSArray *)cd_rowsForQuery:(CDQuery *)query limited:(BOOL *)limited { return @[]; }
- (NSUInteger)cd_countForQuery:(CDQuery *)query { return NSNotFound; }
- (CDSnapshot *)cd_rowForID:(NSManagedObjectID *)oid { return nil; }
- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key { return @[]; }
- (BOOL)cd_apply:(CDChangeSet *)changes error:(NSError **)error
{
    return CDFail(error, NSPersistentStoreSaveError, @"This store can't save.", nil);
}
- (int64_t)cd_reservePKs:(NSUInteger)count forEntity:(NSEntityDescription *)root { return 0; }
- (void)cd_writeMetadata {}
- (id)cd_executeRequest:(NSPersistentStoreRequest *)request error:(NSError **)error
{
    CDFail(error, NSPersistentStoreUnsupportedRequestTypeError,
           @"Batch requests are only available with an SQLite store.", nil);
    return nil;
}
- (void)cd_close {}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> (URL: %@)", NSStringFromClass([self class]), self, [_URL absoluteString]];
}
@end

/* ---- the in-memory store ------------------------------------------------------------------- */

@implementation CDInMemoryStore
- (instancetype)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                                 configurationName:(NSString *)name
                                               URL:(NSURL *)url
                                           options:(NSDictionary *)options
{
    if ((self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options])) {
        _rows = [[NSMutableDictionary alloc] init];
        _nextPK = [[NSMutableDictionary alloc] init];
        [self cd_setType:NSInMemoryStoreType];
    }
    return self;
}
- (void)dealloc
{
    [_rows release];
    [_nextPK release];
    [super dealloc];
}
- (BOOL)cd_load:(NSError **)error
{
    [self cd_stampMetadata];
    return YES;
}
- (NSMutableDictionary *)cd_tableFor:(NSEntityDescription *)entity
{
    NSString *root = [[entity cd_root] name];
    NSMutableDictionary *t = [_rows objectForKey:root];
    if (!t)
        [_rows setObject:(t = [NSMutableDictionary dictionary]) forKey:root];
    return t;
}
- (NSArray *)cd_rowsForQuery:(CDQuery *)q limited:(BOOL *)limited
{
    NSMutableDictionary *t = [self cd_tableFor:q->entity];
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *pk in [[t allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        CDSnapshot *s = [t objectForKey:pk];
        if ([q->entityNames containsObject:[[s->oid entity] name]])
            [out addObject:[[s copy] autorelease]];
    }
    if (limited)
        *limited = NO;
    return out;
}
- (NSUInteger)cd_countForQuery:(CDQuery *)q
{
    if ([q->request predicate])
        return NSNotFound;
    NSUInteger n = [[self cd_rowsForQuery:q limited:NULL] count], off = [q->request fetchOffset],
               lim = [q->request fetchLimit];
    n = off >= n ? 0 : n - off;
    return lim && lim < n ? lim : n;
}
- (CDSnapshot *)cd_rowForID:(NSManagedObjectID *)oid
{
    CDSnapshot *s = [[self cd_tableFor:[oid entity]] objectForKey:@([oid cd_pk])];
    return [[s copy] autorelease];
}
- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key
{
    CDSnapshot *s = [[self cd_tableFor:[oid entity]] objectForKey:@([oid cd_pk])];
    id v = [s->values objectForKey:key];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}
- (BOOL)cd_apply:(CDChangeSet *)set error:(NSError **)error
{
    if (_readOnly)
        return CDFail(error, NSPersistentStoreSaveError, @"The store is read-only.", nil);
    if (!CDResolveConflicts(set,
                            ^CDSnapshot *(NSManagedObjectID *oid) {
                                return [[self cd_tableFor:[oid entity]] objectForKey:@([oid cd_pk])];
                            },
                            error))
        return NO;
    for (CDChange *c in set->inserted) {
        NSMutableDictionary *v = [NSMutableDictionary dictionary];
        for (NSString *k in c->values)
            if ([c->values objectForKey:k] != [NSNull null])
                [v setObject:[c->values objectForKey:k] forKey:k];
        [[self cd_tableFor:[c->oid entity]] setObject:[CDSnapshot snapshotWithID:c->oid values:v version:1]
                                               forKey:@([c->oid cd_pk])];
        NSString *root = [[[c->oid entity] cd_root] name];
        if ([[_nextPK objectForKey:root] longLongValue] <= [c->oid cd_pk])
            [_nextPK setObject:@([c->oid cd_pk] + 1) forKey:root];
        [set->versions setObject:@1 forKey:c->oid];
    }
    for (CDChange *c in set->updated) {
        CDSnapshot *s = [[self cd_tableFor:[c->oid entity]] objectForKey:@([c->oid cd_pk])];
        if (!s)
            continue;
        for (NSString *k in c->values) {
            id v = [c->values objectForKey:k];
            if (v == [NSNull null])
                [s->values removeObjectForKey:k];
            else
                [s->values setObject:v forKey:k];
        }
        s->version++;
        [set->versions setObject:@(s->version) forKey:c->oid];
    }
    for (CDChange *c in set->deleted)
        [[self cd_tableFor:[c->oid entity]] removeObjectForKey:@([c->oid cd_pk])];
    return [self cd_didApply:error];
}
- (BOOL)cd_didApply:(NSError **)error { return YES; }
- (int64_t)cd_reservePKs:(NSUInteger)count forEntity:(NSEntityDescription *)root
{
    NSString *name = [[root cd_root] name];
    int64_t first = [[_nextPK objectForKey:name] longLongValue];
    if (first < 1)
        first = 1;
    [_nextPK setObject:@(first + (int64_t)count) forKey:name];
    return first;
}
@end

/* ---- the binary store ---------------------------------------------------------------------- */

static NSString *const id_entity = @"_cdE", *const id_pk = @"_cdP";

@implementation CDBinaryStore
- (instancetype)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                                 configurationName:(NSString *)name
                                               URL:(NSURL *)url
                                           options:(NSDictionary *)options
{
    if ((self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options]))
        [self cd_setType:NSBinaryStoreType];
    return self;
}

+ (NSDictionary *)cd_archiveAtURL:(NSURL *)url
{
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data)
        return nil;
    id root = nil;
    @try {
        root = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    } @catch (NSException *e) {
        root = nil;
    }
    return [root isKindOfClass:[NSDictionary class]] && [root objectForKey:@"metadata"] ? root : nil;
}

+ (NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error
{
    NSDictionary *a = [self cd_archiveAtURL:url];
    if (!a)
        CDFail(error, NSPersistentStoreInvalidTypeError, @"The file isn't a binary store.", nil);
    return [a objectForKey:@"metadata"];
}

+ (BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error
{
    NSMutableDictionary *a = [[[self cd_archiveAtURL:url] mutableCopy] autorelease];
    if (!a)
        return CDFail(error, NSPersistentStoreInvalidTypeError, @"The file isn't a binary store.", nil);
    [a setObject:metadata forKey:@"metadata"];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:a];
    if (![data writeToURL:url atomically:YES])
        return CDFail(error, NSPersistentStoreSaveError, @"The store's file couldn't be written.", nil);
    return YES;
}

/* Values as the file keeps them: object IDs as small dictionaries, transformable values as data. */
- (id)cd_encode:(id)v property:(NSPropertyDescription *)p
{
    if ([p isKindOfClass:[NSAttributeDescription class]])
        return [(NSAttributeDescription *)p cd_storedValue:v];
    if ([v isKindOfClass:[NSManagedObjectID class]])
        return @{id_entity : [[v entity] name], id_pk : @([v cd_pk])};
    if ([v isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSManagedObjectID *oid in v)
            [a addObject:@{id_entity : [[oid entity] name], id_pk : @([oid cd_pk])}];
        return a;
    }
    return v;
}

- (id)cd_decode:(id)v property:(NSPropertyDescription *)p entities:(NSDictionary *)entities
{
    if ([p isKindOfClass:[NSAttributeDescription class]])
        return [(NSAttributeDescription *)p cd_valueFromStored:v];
    NSManagedObjectID * (^one)(NSDictionary *) = ^NSManagedObjectID *(NSDictionary *d) {
        NSEntityDescription *e = [entities objectForKey:[d objectForKey:id_entity]];
        return e ? [NSManagedObjectID cd_IDForEntity:e store:self pk:[[d objectForKey:id_pk] longLongValue]] : nil;
    };
    if ([v isKindOfClass:[NSDictionary class]])
        return one(v);
    if ([v isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSDictionary *d in v) {
            NSManagedObjectID *oid = one(d);
            if (oid)
                [a addObject:oid];
        }
        return a;
    }
    return nil;
}

- (BOOL)cd_load:(NSError **)error
{
    NSDictionary *a = [CDBinaryStore cd_archiveAtURL:_URL];
    if (!a) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[_URL path]])
            return CDFail(error, NSPersistentStoreInvalidTypeError, @"The file isn't a binary store.", nil);
        [self cd_stampMetadata];
        return _readOnly ? YES : [self cd_didApply:error];
    }
    NSDictionary *meta = [a objectForKey:@"metadata"];
    NSMutableArray *added = [NSMutableArray array];
    NSManagedObjectModel *model = [_coordinator managedObjectModel];
    if (!CDCheckSchema(model, meta, _options, added, error))
        return NO;
    [_metadata release];
    _metadata = [meta mutableCopy];
    if ([meta objectForKey:NSStoreUUIDKey]) {
        [_identifier release];
        _identifier = [[meta objectForKey:NSStoreUUIDKey] copy];
    }
    NSDictionary *entities = [model entitiesByName];
    [_nextPK setDictionary:[a objectForKey:@"next"] ?: @{}];
    for (NSDictionary *row in [a objectForKey:@"rows"]) {
        NSEntityDescription *e = [entities objectForKey:[row objectForKey:@"e"]];
        if (!e)
            continue;   /* an entity the model no longer has */
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        NSDictionary *stored = [row objectForKey:@"d"];
        for (NSString *k in stored) {
            NSPropertyDescription *p = [e cd_propertyNamed:k];
            if (!p || [p isTransient])
                continue;   /* a property the model no longer has */
            id v = [self cd_decode:[stored objectForKey:k] property:p entities:entities];
            if (v)
                [values setObject:v forKey:k];
        }
        for (NSAttributeDescription *at in [e cd_persistentAttributes])
            if (![values objectForKey:[at name]] && [at defaultValue] && ![stored objectForKey:[at name]] &&
                [added count])
                [values setObject:[at defaultValue] forKey:[at name]];
        NSManagedObjectID *oid = [NSManagedObjectID cd_IDForEntity:e store:self pk:[[row objectForKey:@"p"] longLongValue]];
        [[self cd_tableFor:e] setObject:[CDSnapshot snapshotWithID:oid
                                                            values:values
                                                           version:[[row objectForKey:@"v"] longLongValue]]
                                 forKey:@([oid cd_pk])];
    }
    if ([added count] || ![model isConfiguration:nil compatibleWithStoreMetadata:meta]) {
        [self cd_stampMetadata];
        if (!_readOnly && ![self cd_didApply:error])
            return NO;
    }
    return YES;
}

- (BOOL)cd_didApply:(NSError **)error
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *root in _rows)
        for (NSNumber *pk in [[[_rows objectForKey:root] allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            CDSnapshot *s = [[_rows objectForKey:root] objectForKey:pk];
            NSEntityDescription *e = [s->oid entity];
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (NSString *k in s->values) {
                id v = [self cd_encode:[s->values objectForKey:k] property:[e cd_propertyNamed:k]];
                if (v)
                    [d setObject:v forKey:k];
            }
            [rows addObject:@{@"e" : [e name], @"p" : pk, @"v" : @(s->version), @"d" : d}];
        }
    NSDictionary *a = @{@"metadata" : _metadata, @"next" : _nextPK, @"rows" : rows};
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:a];
    [[NSFileManager defaultManager] createDirectoryAtPath:[[_URL path] stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    if (!data || ![data writeToURL:_URL atomically:YES])
        return CDFail(error, NSPersistentStoreSaveError,
                      [NSString stringWithFormat:@"The store's file %@ couldn't be written.", [_URL path]], nil);
    return YES;
}

- (int64_t)cd_reservePKs:(NSUInteger)count forEntity:(NSEntityDescription *)root
{
    return [super cd_reservePKs:count forEntity:root];
}

- (void)cd_writeMetadata
{
    if (!_readOnly)
        [self cd_didApply:NULL];
}
@end

/* ---- the coordinator ------------------------------------------------------------------------- */

static NSMutableDictionary *store_types(void)
{
    static NSMutableDictionary *types;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (!types)
        types = [@{
            NSSQLiteStoreType : [CDSQLiteStore class],
            NSBinaryStoreType : [CDBinaryStore class],
            NSInMemoryStoreType : [CDInMemoryStore class],
        } mutableCopy];
    pthread_mutex_unlock(&lock);
    return types;
}

@implementation NSPersistentStoreCoordinator {
    NSManagedObjectModel *_model;
    NSMutableArray *_stores;
    pthread_mutex_t _mutex;
    NSMutableDictionary *_tempToPerm;   /* temporary name -> permanent ID */
    NSMutableDictionary *_permToTemp;   /* permanent ID -> temporary ID */
    NSString *_name;
}

+ (NSDictionary *)registeredStoreTypes { return [[store_types() copy] autorelease]; }
+ (void)registerStoreClass:(Class)cls forStoreType:(NSString *)type
{
    if (!cls) {
        [store_types() removeObjectForKey:type];
        return;
    }
    CDWarnOnce([@"storeclass:" stringByAppendingString:type ?: @""],
               [NSString stringWithFormat:@"Ferry: Core Data store classes of an app's own (%@) aren't supported yet.",
                                          NSStringFromClass(cls)]);
}

- (instancetype)initWithManagedObjectModel:(NSManagedObjectModel *)model
{
    if ((self = [super init])) {
        _model = [model retain];
        _stores = [[NSMutableArray alloc] init];
        _tempToPerm = [[NSMutableDictionary alloc] init];
        _permToTemp = [[NSMutableDictionary alloc] init];
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_mutex, &attr);
        pthread_mutexattr_destroy(&attr);
        CDRegisterModel(model);
    }
    return self;
}

- (void)dealloc
{
    for (NSPersistentStore *s in _stores)
        [s cd_close];
    [_model release];
    [_stores release];
    [_tempToPerm release];
    [_permToTemp release];
    [_name release];
    pthread_mutex_destroy(&_mutex);
    [super dealloc];
}

- (void)cd_lock { pthread_mutex_lock(&_mutex); }
- (void)cd_unlock { pthread_mutex_unlock(&_mutex); }
- (void)lock { pthread_mutex_lock(&_mutex); }
- (void)unlock { pthread_mutex_unlock(&_mutex); }
- (BOOL)tryLock { return pthread_mutex_trylock(&_mutex) == 0; }
- (void)performBlock:(void (^)(void))block
{
    void (^b)(void) = [[block copy] autorelease];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        pthread_mutex_lock(&_mutex);
        b();
        pthread_mutex_unlock(&_mutex);
    });
}
- (void)performBlockAndWait:(void (^)(void))block
{
    pthread_mutex_lock(&_mutex);
    block();
    pthread_mutex_unlock(&_mutex);
}

- (NSManagedObjectModel *)managedObjectModel { return _model; }
- (NSPersistentStoreCoordinator *)cd_coordinator { return self; }
- (NSArray *)persistentStores
{
    [self cd_lock];
    NSArray *a = [[_stores copy] autorelease];
    [self cd_unlock];
    return a;
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    [_name autorelease];
    _name = [name copy];
}

- (NSPersistentStore *)persistentStoreForURL:(NSURL *)url
{
    for (NSPersistentStore *s in [self persistentStores])
        if ([s URL] && [[[[s URL] path] stringByStandardizingPath] isEqual:[[url path] stringByStandardizingPath]])
            return s;
    return nil;
}
- (NSURL *)URLForPersistentStore:(NSPersistentStore *)store { return [store URL]; }
- (BOOL)setURL:(NSURL *)url forPersistentStore:(NSPersistentStore *)store
{
    [store setURL:url];
    return YES;
}
- (NSPersistentStore *)cd_storeWithIdentifier:(NSString *)identifier
{
    for (NSPersistentStore *s in [self persistentStores])
        if ([[s identifier] isEqualToString:identifier])
            return s;
    return nil;
}

- (id)addPersistentStoreWithType:(NSString *)type
                   configuration:(NSString *)configuration
                             URL:(NSURL *)url
                         options:(NSDictionary *)options
                           error:(NSError **)error
{
    Class cls = [store_types() objectForKey:type ?: @""];
    if (!cls) {
        CDFail(error, NSPersistentStoreInvalidTypeError,
               [NSString stringWithFormat:@"Unknown store type %@.", type], nil);
        return nil;
    }
    if (url && [self persistentStoreForURL:url]) {
        CDFail(error, NSPersistentStoreOpenError, @"Can't add the same store twice.", nil);
        return nil;
    }
    if (![type isEqualToString:NSInMemoryStoreType] && ![url isFileURL]) {
        CDFail(error, NSPersistentStoreOpenError, @"The store needs a file URL.", nil);
        return nil;
    }
    NSPersistentStore *store = [[[cls alloc] initWithPersistentStoreCoordinator:self
                                                              configurationName:configuration
                                                                            URL:url
                                                                        options:options] autorelease];
    [self cd_lock];
    BOOL ok = [store cd_load:error];
    if (ok)
        [_stores addObject:store];
    [self cd_unlock];
    if (!ok)
        return nil;
    [store didAddToPersistentStoreCoordinator:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPersistentStoreCoordinatorStoresDidChangeNotification
                                                        object:self
                                                      userInfo:@{NSAddedPersistentStoresKey : @[ store ]}];
    return store;
}

- (void)addPersistentStoreWithDescription:(NSPersistentStoreDescription *)d
                        completionHandler:(void (^)(NSPersistentStoreDescription *, NSError *))block
{
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:[d options] ?: @{}];
    [options setObject:@([d shouldMigrateStoreAutomatically]) forKey:NSMigratePersistentStoresAutomaticallyOption];
    [options setObject:@([d shouldInferMappingModelAutomatically]) forKey:NSInferMappingModelAutomaticallyOption];
    if ([d isReadOnly])
        [options setObject:@YES forKey:NSReadOnlyPersistentStoreOption];
    if ([[d sqlitePragmas] count])
        [options setObject:[d sqlitePragmas] forKey:NSSQLitePragmasOption];
    [options setObject:@([d timeout]) forKey:NSPersistentStoreTimeoutOption];
    void (^add)(void) = ^{
        NSError *err = nil;
        if ([[d URL] isFileURL])
            [[NSFileManager defaultManager] createDirectoryAtPath:[[[d URL] path] stringByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:NULL];
        [self addPersistentStoreWithType:[d type]
                           configuration:[d configuration]
                                     URL:[d URL]
                                 options:options
                                   error:&err];
        if (block)
            block(d, err);
    };
    if ([d shouldAddStoreAsynchronously])
        dispatch_async(dispatch_get_global_queue(0, 0), [[add copy] autorelease]);
    else
        add();
}

- (BOOL)removePersistentStore:(NSPersistentStore *)store error:(NSError **)error
{
    [self cd_lock];
    BOOL there = [_stores containsObject:store];
    [store retain];
    if (there) {
        [store willRemoveFromPersistentStoreCoordinator:self];
        [store cd_close];
        [_stores removeObject:store];
    }
    [self cd_unlock];
    if (there)
        [[NSNotificationCenter defaultCenter]
            postNotificationName:NSPersistentStoreCoordinatorStoresDidChangeNotification
                          object:self
                        userInfo:@{NSRemovedPersistentStoresKey : @[ store ]}];
    [store autorelease];
    if (!there)
        return CDFail(error, NSPersistentStoreOperationError, @"The store isn't one of the coordinator's.", nil);
    return YES;
}

- (NSDictionary *)metadataForPersistentStore:(NSPersistentStore *)store { return [store metadata]; }
- (void)setMetadata:(NSDictionary *)metadata forPersistentStore:(NSPersistentStore *)store
{
    [self cd_lock];
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:metadata ?: @{}];
    NSDictionary *old = [store metadata];
    for (NSString *k in @[ NSStoreModelVersionHashesKey, schema_key, NSStoreModelVersionIdentifiersKey ])
        if (![m objectForKey:k] && [old objectForKey:k])
            [m setObject:[old objectForKey:k] forKey:k];
    [store setMetadata:m];
    [store cd_writeMetadata];
    [self cd_unlock];
}

static Class store_class_for_file(NSString *type, NSURL *url)
{
    if (type)
        return [store_types() objectForKey:type];
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:[url path]];
    NSData *head = [h readDataOfLength:16];
    [h closeFile];
    if ([head length] == 16 && memcmp([head bytes], "SQLite format 3", 16) == 0)
        return [CDSQLiteStore class];
    return [CDBinaryStore class];
}

+ (NSDictionary *)metadataForPersistentStoreOfType:(NSString *)type
                                               URL:(NSURL *)url
                                           options:(NSDictionary *)options
                                             error:(NSError **)error
{
    Class cls = store_class_for_file(type, url);
    if (!cls) {
        CDFail(error, NSPersistentStoreInvalidTypeError, @"Unknown store type.", nil);
        return nil;
    }
    return [cls metadataForPersistentStoreWithURL:url error:error];
}

+ (BOOL)setMetadata:(NSDictionary *)metadata
    forPersistentStoreOfType:(NSString *)type
                         URL:(NSURL *)url
                     options:(NSDictionary *)options
                       error:(NSError **)error
{
    Class cls = store_class_for_file(type, url);
    if (!cls)
        return CDFail(error, NSPersistentStoreInvalidTypeError, @"Unknown store type.", nil);
    return [cls setMetadata:metadata forPersistentStoreWithURL:url error:error];
}

- (BOOL)destroyPersistentStoreAtURL:(NSURL *)url withType:(NSString *)type options:(NSDictionary *)options
                              error:(NSError **)error
{
    NSPersistentStore *open = [self persistentStoreForURL:url];
    if (open)
        [self removePersistentStore:open error:NULL];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[ @"", @"-wal", @"-shm", @"-journal" ])
        [fm removeItemAtPath:[[url path] stringByAppendingString:suffix] error:NULL];
    return YES;
}

/* Copies every row into a new store, then puts it in the old one's place. */
- (NSPersistentStore *)migratePersistentStore:(NSPersistentStore *)store
                                        toURL:(NSURL *)url
                                      options:(NSDictionary *)options
                                     withType:(NSString *)type
                                        error:(NSError **)error
{
    Class cls = [store_types() objectForKey:type ?: @""];
    if (!cls) {
        CDFail(error, NSPersistentStoreInvalidTypeError, @"Unknown store type.", nil);
        return nil;
    }
    [self cd_lock];
    NSPersistentStore *next = [[[cls alloc] initWithPersistentStoreCoordinator:self
                                                             configurationName:[store configurationName]
                                                                           URL:url
                                                                       options:options] autorelease];
    if (![next cd_load:error]) {
        [self cd_unlock];
        return nil;
    }
    CDChangeSet *set = [[[CDChangeSet alloc] init] autorelease];
    set->policy = NSOverwriteMergePolicyType;
    for (NSEntityDescription *e in [_model entities]) {
        if ([e superentity])
            continue;
        CDQuery *q = [[[CDQuery alloc] init] autorelease];
        q->entity = [e retain];
        q->entityNames = [[e cd_selfAndSubentityNames] retain];
        q->request = [[NSFetchRequest alloc] initWithEntityName:[e name]];
        for (CDSnapshot *s in [store cd_rowsForQuery:q limited:NULL]) {
            NSEntityDescription *se = [s->oid entity];
            NSMutableDictionary *v = [NSMutableDictionary dictionaryWithDictionary:s->values];
            for (NSRelationshipDescription *r in [se cd_persistentRelationships])
                if ([r isToMany] && ![v objectForKey:[r name]])
                    [v setObject:[store cd_relatedIDsForID:s->oid key:[r name]] forKey:[r name]];
            /* the same keys, in the new store */
            NSMutableDictionary *moved = [NSMutableDictionary dictionary];
            for (NSString *k in v) {
                id x = [v objectForKey:k];
                if ([x isKindOfClass:[NSManagedObjectID class]])
                    x = [NSManagedObjectID cd_IDForEntity:[x entity] store:next pk:[x cd_pk]];
                else if ([[se cd_propertyNamed:k] isKindOfClass:[NSRelationshipDescription class]]) {
                    NSMutableArray *a = [NSMutableArray array];
                    for (NSManagedObjectID *oid in x)
                        [a addObject:[NSManagedObjectID cd_IDForEntity:[oid entity] store:next pk:[oid cd_pk]]];
                    x = a;
                }
                [moved setObject:x forKey:k];
            }
            CDChange *c = [[[CDChange alloc] init] autorelease];
            c->oid = [[NSManagedObjectID cd_IDForEntity:se store:next pk:[s->oid cd_pk]] retain];
            c->values = [moved copy];
            [set->inserted addObject:c];
        }
    }
    BOOL ok = [next cd_apply:set error:error];
    if (ok) {
        [store cd_close];
        [_stores replaceObjectAtIndex:[_stores indexOfObject:store] withObject:next];
    }
    [self cd_unlock];
    return ok ? next : nil;
}

- (NSPersistentStore *)cd_storeForEntity:(NSEntityDescription *)entity
{
    for (NSPersistentStore *s in [self persistentStores]) {
        NSArray *ents = [_model entitiesForConfiguration:[s configurationName]];
        for (NSEntityDescription *e in ents)
            if ([[e name] isEqualToString:[entity name]])
                return s;
    }
    return nil;
}

- (NSManagedObjectID *)managedObjectIDForURIRepresentation:(NSURL *)url
{
    if (![[url scheme] isEqualToString:@"x-coredata"])
        return nil;
    NSArray *parts = [[url path] pathComponents];   /* "/", entity, "p<pk>" */
    if ([parts count] < 3)
        return nil;
    NSEntityDescription *e = [[_model entitiesByName] objectForKey:[parts objectAtIndex:1]];
    NSString *last = [parts objectAtIndex:2];
    NSPersistentStore *store = [self cd_storeWithIdentifier:[url host]];
    if (!e || !store || ![last hasPrefix:@"p"])
        return nil;
    return [NSManagedObjectID cd_IDForEntity:e store:store pk:[[last substringFromIndex:1] longLongValue]];
}

- (NSManagedObjectID *)cd_permanentIDForTemporaryID:(NSManagedObjectID *)oid
{
    [self cd_lock];
    NSManagedObjectID *p = [[[_tempToPerm objectForKey:[oid cd_temporaryName] ?: @""] retain] autorelease];
    [self cd_unlock];
    return p;
}

- (NSManagedObjectID *)cd_temporaryIDForPermanentID:(NSManagedObjectID *)oid
{
    [self cd_lock];
    NSManagedObjectID *t = [[[_permToTemp objectForKey:oid] retain] autorelease];
    [self cd_unlock];
    return t;
}

- (NSArray *)cd_permanentIDsForTemporaryIDs:(NSArray *)ids error:(NSError **)error
{
    NSMutableArray *out = [NSMutableArray array];
    [self cd_lock];
    for (NSManagedObjectID *t in ids) {
        NSManagedObjectID *known = [_tempToPerm objectForKey:[t cd_temporaryName] ?: @""];
        if (known || ![t isTemporaryID]) {
            [out addObject:known ?: t];
            continue;
        }
        NSPersistentStore *store = [self cd_storeForEntity:[t entity]];
        if (!store) {
            [self cd_unlock];
            CDFail(error, NSCoreDataError,
                   [_stores count] ? [NSString stringWithFormat:@"No store holds the entity %@.", [[t entity] name]]
                                   : @"This NSPersistentStoreCoordinator has no persistent stores.",
                   nil);
            return nil;
        }
        int64_t pk = [store cd_reservePKs:1 forEntity:[[t entity] cd_root]];
        NSManagedObjectID *p = [NSManagedObjectID cd_IDForEntity:[t entity] store:store pk:pk];
        [_tempToPerm setObject:p forKey:[t cd_temporaryName]];
        [_permToTemp setObject:t forKey:p];
        [out addObject:p];
    }
    [self cd_unlock];
    return out;
}

/* ---- the coordinator as a context's parent ---- */

- (NSArray *)cd_storesForQuery:(CDQuery *)q
{
    NSMutableArray *out = [NSMutableArray array];
    NSArray *affected = [q->request affectedStores];
    for (NSPersistentStore *s in _stores) {
        if (affected && ![affected containsObject:s])
            continue;
        for (NSEntityDescription *e in [_model entitiesForConfiguration:[s configurationName]])
            if ([[e name] isEqualToString:[q->entity name]]) {
                [out addObject:s];
                break;
            }
    }
    return out;
}

- (NSArray *)cd_snapshotsForQuery:(CDQuery *)q limited:(BOOL *)limited error:(NSError **)error
{
    [self cd_lock];
    NSArray *stores = [self cd_storesForQuery:q];
    NSMutableArray *out = [NSMutableArray array];
    BOOL lim = NO;
    q->exact = NO;
    if ([stores count] == 1)
        [out addObjectsFromArray:[[stores objectAtIndex:0] cd_rowsForQuery:q limited:&lim]];
    else {
        BOOL was = q->storeLimit;
        q->storeLimit = NO;
        for (NSPersistentStore *s in stores)
            [out addObjectsFromArray:[s cd_rowsForQuery:q limited:NULL]];
        q->storeLimit = was;
        q->exact = NO;
    }
    [self cd_unlock];
    if (limited)
        *limited = lim;
    return out;
}

- (NSUInteger)cd_countForQuery:(CDQuery *)q
{
    [self cd_lock];
    NSArray *stores = [self cd_storesForQuery:q];
    NSUInteger n = [stores count] == 1 ? [[stores objectAtIndex:0] cd_countForQuery:q] : [stores count] ? NSNotFound : 0;
    [self cd_unlock];
    return n;
}

- (CDSnapshot *)cd_snapshotForID:(NSManagedObjectID *)oid
{
    if ([oid isTemporaryID]) {
        oid = [self cd_permanentIDForTemporaryID:oid];
        if (!oid)
            return nil;
    }
    [self cd_lock];
    NSPersistentStore *s = [oid persistentStore];
    CDSnapshot *row = [_stores containsObject:s] ? [s cd_rowForID:oid] : nil;
    [self cd_unlock];
    return row;
}

- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key
{
    if ([oid isTemporaryID]) {
        oid = [self cd_permanentIDForTemporaryID:oid];
        if (!oid)
            return @[];
    }
    [self cd_lock];
    NSPersistentStore *s = [oid persistentStore];
    NSArray *ids = [_stores containsObject:s] ? [s cd_relatedIDsForID:oid key:key] : @[];
    [self cd_unlock];
    return ids;
}

- (BOOL)cd_saveChanges:(CDChangeSet *)set error:(NSError **)error
{
    [self cd_lock];
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    CDChangeSet * (^part)(NSManagedObjectID *) = ^CDChangeSet *(NSManagedObjectID *oid) {
        NSPersistentStore *s = [oid persistentStore];
        NSValue *k = [NSValue valueWithPointer:s];
        CDChangeSet *p = [parts objectForKey:k];
        if (!p) {
            p = [[[CDChangeSet alloc] init] autorelease];
            p->policy = set->policy;
            [parts setObject:p forKey:k];
            [order addObject:k];
        }
        return p;
    };
    for (CDChange *c in set->inserted)
        [part(c->oid)->inserted addObject:c];
    for (CDChange *c in set->updated)
        [part(c->oid)->updated addObject:c];
    for (CDChange *c in set->deleted)
        [part(c->oid)->deleted addObject:c];
    BOOL ok = YES;
    for (NSValue *k in order) {
        NSPersistentStore *s = [k pointerValue];
        CDChangeSet *p = [parts objectForKey:k];
        if (![_stores containsObject:s]) {
            ok = CDFail(error, NSPersistentStoreSaveError, @"An object's store was removed from the coordinator.", nil);
            break;
        }
        ok = [s cd_apply:p error:error];
        [set->conflicts addObjectsFromArray:p->conflicts];
        [set->refreshIDs unionSet:p->refreshIDs];
        [set->versions addEntriesFromDictionary:p->versions];
        if (!ok)
            break;
        /* what a merge policy dropped isn't saved */
        for (CDChange *c in [[set->updated copy] autorelease])
            if ([p->conflicts count] && [part(c->oid) isEqual:p] && ![p->updated containsObject:c])
                [set->updated removeObject:c];
    }
    [self cd_unlock];
    return ok;
}

/* The batch requests: the rows they act on are found with a fetch in the
 * asking context (without its unsaved changes), so that the predicate means
 * what it does there; then each SQLite store changes its own rows. */
- (id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context
               error:(NSError **)error
{
    if ([request isKindOfClass:[NSFetchRequest class]])
        return [context executeFetchRequest:(NSFetchRequest *)request error:error];
    BOOL isDelete = [request isKindOfClass:[NSBatchDeleteRequest class]];
    if (!isDelete && ![request isKindOfClass:[NSBatchUpdateRequest class]]) {
        CDFail(error, NSPersistentStoreUnsupportedRequestTypeError,
               [NSString stringWithFormat:@"Ferry's Core Data can't run a %@.", NSStringFromClass([request class])], nil);
        return nil;
    }
    NSArray *stores = [request affectedStores] ?: [self persistentStores];
    if (![stores count]) {
        CDFail(error, NSCoreDataError, @"This NSPersistentStoreCoordinator has no persistent stores.", nil);
        return nil;
    }
    for (NSPersistentStore *s in stores)
        if (![s isKindOfClass:[CDSQLiteStore class]]) {
            CDFail(error, NSPersistentStoreUnsupportedRequestTypeError,
                   @"Batch requests are only available with an SQLite store.", nil);
            return nil;
        }
    NSArray *ids = isDelete ? [(NSBatchDeleteRequest *)request cd_objectIDs] : nil;
    if (!ids) {
        NSFetchRequest *f;
        if (isDelete)
            f = [(NSBatchDeleteRequest *)request fetchRequest];
        else {
            NSBatchUpdateRequest *u = (NSBatchUpdateRequest *)request;
            f = [NSFetchRequest fetchRequestWithEntityName:[u entityName]];
            if ([u entity])
                [f setEntity:[u entity]];
            [f setPredicate:[u predicate]];
            [f setIncludesSubentities:[u includesSubentities]];
        }
        [f setResultType:NSManagedObjectIDResultType];
        [f setIncludesPendingChanges:NO];
        [f setAffectedStores:stores];
        NSManagedObjectContext *ctx = context;
        if (!ctx) {
            ctx = [[[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType] autorelease];
            [ctx setUndoManager:nil];
            [ctx setPersistentStoreCoordinator:self];
        }
        __block NSArray *found = nil;
        __block NSError *ferr = nil;
        [ctx cd_performAndWait:^{
            found = [[ctx executeFetchRequest:f error:&ferr] retain];
            [ferr retain];
        }];
        [found autorelease];
        [ferr autorelease];
        if (!found) {
            if (error)
                *error = ferr;
            return nil;
        }
        ids = found;
    }
    NSMutableArray *done = [NSMutableArray array];
    [self cd_lock];
    for (NSPersistentStore *s in stores) {
        NSMutableArray *mine = [NSMutableArray array];
        for (NSManagedObjectID *oid in ids)
            if ([oid persistentStore] == s)
                [mine addObject:oid];
        NSArray *r = isDelete ? [(CDSQLiteStore *)s cd_batchDeleteIDs:mine error:error]
                              : [(CDSQLiteStore *)s cd_batchUpdateIDs:mine
                                                               values:[(NSBatchUpdateRequest *)request propertiesToUpdate]
                                                                error:error];
        if (!r) {
            [self cd_unlock];
            return nil;
        }
        [done addObjectsFromArray:r];
    }
    [self cd_unlock];
    if (isDelete) {
        NSBatchDeleteRequestResultType t = [(NSBatchDeleteRequest *)request resultType];
        return CDBatchDeleteResult(t == NSBatchDeleteResultTypeObjectIDs ? (id)done
                                   : t == NSBatchDeleteResultTypeCount  ? (id)@([done count])
                                                                        : (id)@YES,
                                   t);
    }
    NSBatchUpdateRequestResultType t = [(NSBatchUpdateRequest *)request resultType];
    return CDBatchUpdateResult(t == NSUpdatedObjectIDsResultType       ? (id)done
                               : t == NSUpdatedObjectsCountResultType ? (id)@([done count])
                                                                      : (id)@YES,
                               t);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSPersistentStoreCoordinator: %p> (%lu stores)", self,
                                      (unsigned long)[_stores count]];
}
@end
