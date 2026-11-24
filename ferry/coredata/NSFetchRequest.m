/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: fetch requests and the batch requests, as Apple's
 * class references describe them (freemac 1.NEXT, Ferry 0.NEXT). Our own
 * code; no Apple code was used.
 *
 * fetchBatchSize and relationshipKeyPathsForPrefetching are kept and
 * answered but change nothing: a fetch gives the whole array, and related
 * objects are read when first used. A dictionary fetch's
 * propertiesToFetch takes property names and descriptions; there are no
 * expression descriptions (Ferry has no NSExpression yet), so
 * propertiesToGroupBy and havingPredicate are kept and not used. */
#import "CDInternal.h"

@implementation NSNumber (NSFetchRequestResult)
@end
@implementation NSDictionary (NSFetchRequestResult)
@end

@implementation NSPersistentStoreRequest {
@protected
    NSArray *_affectedStores;
}
- (void)dealloc
{
    [_affectedStores release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSPersistentStoreRequest *c = [[[self class] allocWithZone:zone] init];
    c->_affectedStores = [_affectedStores copy];
    return c;
}
- (NSArray *)affectedStores { return _affectedStores; }
- (void)setAffectedStores:(NSArray *)stores
{
    [_affectedStores autorelease];
    _affectedStores = [stores copy];
}
- (NSPersistentStoreRequestType)requestType { return NSFetchRequestType; }
@end

@implementation NSFetchRequest {
    NSEntityDescription *_entity;
    NSString *_entityName;
    NSPredicate *_predicate;
    NSArray *_sorts, *_prefetch, *_toFetch, *_groupBy;
    NSPredicate *_having;
    NSUInteger _limit, _offset, _batch;
    NSFetchRequestResultType _resultType;
    BOOL _subentities, _propertyValues, _faults, _pending, _distinct, _refresh;
}
+ (instancetype)fetchRequestWithEntityName:(NSString *)name { return [[[self alloc] initWithEntityName:name] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        _subentities = YES;
        _propertyValues = YES;
        _faults = YES;
        _pending = YES;
    }
    return self;
}
- (instancetype)initWithEntityName:(NSString *)name
{
    if ((self = [self init]))
        _entityName = [name copy];
    return self;
}
- (void)dealloc
{
    [_entity release];
    [_entityName release];
    [_predicate release];
    [_sorts release];
    [_prefetch release];
    [_toFetch release];
    [_groupBy release];
    [_having release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSFetchRequest *c = [super copyWithZone:zone];
    c->_entity = [_entity retain];
    c->_entityName = [_entityName copy];
    c->_predicate = [_predicate retain];
    c->_sorts = [_sorts copy];
    c->_prefetch = [_prefetch copy];
    c->_toFetch = [_toFetch copy];
    c->_groupBy = [_groupBy copy];
    c->_having = [_having retain];
    c->_limit = _limit;
    c->_offset = _offset;
    c->_batch = _batch;
    c->_resultType = _resultType;
    c->_subentities = _subentities;
    c->_propertyValues = _propertyValues;
    c->_faults = _faults;
    c->_pending = _pending;
    c->_distinct = _distinct;
    c->_refresh = _refresh;
    return c;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _entityName = [[coder decodeObjectForKey:@"entityName"] copy];
        _predicate = [[coder decodeObjectForKey:@"predicate"] retain];
        _sorts = [[coder decodeObjectForKey:@"sortDescriptors"] copy];
        _limit = (NSUInteger)[coder decodeIntegerForKey:@"fetchLimit"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self entityName] forKey:@"entityName"];
    [coder encodeObject:_predicate forKey:@"predicate"];
    [coder encodeObject:_sorts forKey:@"sortDescriptors"];
    [coder encodeInteger:(NSInteger)_limit forKey:@"fetchLimit"];
}
- (NSPersistentStoreRequestType)requestType { return NSFetchRequestType; }
- (NSArray *)execute:(NSError **)error
{
    NSManagedObjectContext *ctx = CDCurrentContext();
    if (!ctx)
        CDRaise(NSInternalInconsistencyException,
                @"-execute: can only be used inside a context's performBlock: or performBlockAndWait:");
    return [ctx executeFetchRequest:self error:error];
}
- (NSEntityDescription *)entity { return _entity; }
- (void)setEntity:(NSEntityDescription *)entity
{
    [_entity autorelease];
    _entity = [entity retain];
    if (entity) {
        [_entityName autorelease];
        _entityName = [[entity name] copy];
    }
}
- (NSString *)entityName { return _entityName ?: [_entity name]; }
- (NSPredicate *)predicate { return _predicate; }
- (void)setPredicate:(NSPredicate *)p
{
    [_predicate autorelease];
    _predicate = [p retain];
}
- (NSArray *)sortDescriptors { return _sorts; }
- (void)setSortDescriptors:(NSArray *)s
{
    [_sorts autorelease];
    _sorts = [s copy];
}
- (NSUInteger)fetchLimit { return _limit; }
- (void)setFetchLimit:(NSUInteger)n { _limit = n; }
- (NSUInteger)fetchOffset { return _offset; }
- (void)setFetchOffset:(NSUInteger)n { _offset = n; }
- (NSUInteger)fetchBatchSize { return _batch; }
- (void)setFetchBatchSize:(NSUInteger)n { _batch = n; }
- (NSFetchRequestResultType)resultType { return _resultType; }
- (void)setResultType:(NSFetchRequestResultType)t { _resultType = t; }
- (BOOL)includesSubentities { return _subentities; }
- (void)setIncludesSubentities:(BOOL)f { _subentities = f; }
- (BOOL)includesPropertyValues { return _propertyValues; }
- (void)setIncludesPropertyValues:(BOOL)f { _propertyValues = f; }
- (BOOL)returnsObjectsAsFaults { return _faults; }
- (void)setReturnsObjectsAsFaults:(BOOL)f { _faults = f; }
- (BOOL)includesPendingChanges { return _pending; }
- (void)setIncludesPendingChanges:(BOOL)f { _pending = f; }
- (BOOL)returnsDistinctResults { return _distinct; }
- (void)setReturnsDistinctResults:(BOOL)f { _distinct = f; }
- (BOOL)shouldRefreshRefetchedObjects { return _refresh; }
- (void)setShouldRefreshRefetchedObjects:(BOOL)f { _refresh = f; }
- (NSArray *)relationshipKeyPathsForPrefetching { return _prefetch; }
- (void)setRelationshipKeyPathsForPrefetching:(NSArray *)a
{
    [_prefetch autorelease];
    _prefetch = [a copy];
}
- (NSArray *)propertiesToFetch { return _toFetch; }
- (void)setPropertiesToFetch:(NSArray *)a
{
    [_toFetch autorelease];
    _toFetch = [a copy];
}
- (NSArray *)propertiesToGroupBy { return _groupBy; }
- (void)setPropertiesToGroupBy:(NSArray *)a
{
    [_groupBy autorelease];
    _groupBy = [a copy];
}
- (NSPredicate *)havingPredicate { return _having; }
- (void)setHavingPredicate:(NSPredicate *)p
{
    [_having autorelease];
    _having = [p retain];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSFetchRequest: %p> (entity: %@; predicate: (%@); sortDescriptors: (%@); "
                                      @"type: %lu)",
                                      self, [self entityName], [_predicate predicateFormat], _sorts,
                                      (unsigned long)_resultType];
}
@end

NSArray *CDFilterSortLimit(NSArray *objects, NSFetchRequest *request, BOOL limited)
{
    NSArray *a = objects;
    if ([request predicate])
        a = [a filteredArrayUsingPredicate:[request predicate]];
    if ([[request sortDescriptors] count])
        a = [a sortedArrayUsingDescriptors:[request sortDescriptors]];
    if (limited)
        return a;
    NSUInteger n = [a count], off = [request fetchOffset], lim = [request fetchLimit];
    if (off >= n)
        return off ? @[] : a;
    NSUInteger len = n - off;
    if (lim && lim < len)
        len = lim;
    return (off == 0 && len == n) ? a : [a subarrayWithRange:NSMakeRange(off, len)];
}

/* ---- results ---------------------------------------------------------------------------- */

@implementation NSPersistentStoreResult
@end
@implementation NSPersistentStoreAsynchronousResult
@end

@implementation NSBatchDeleteResult {
@public
    id _result;
    NSBatchDeleteRequestResultType _type;
}
- (void)dealloc
{
    [_result release];
    [super dealloc];
}
- (id)result { return _result; }
- (NSBatchDeleteRequestResultType)resultType { return _type; }
@end

@implementation NSBatchUpdateResult {
@public
    id _result;
    NSBatchUpdateRequestResultType _type;
}
- (void)dealloc
{
    [_result release];
    [super dealloc];
}
- (id)result { return _result; }
- (NSBatchUpdateRequestResultType)resultType { return _type; }
@end

id CDBatchDeleteResult(id result, NSBatchDeleteRequestResultType type)
{
    NSBatchDeleteResult *r = [[[NSBatchDeleteResult alloc] init] autorelease];
    r->_result = [result retain];
    r->_type = type;
    return r;
}

id CDBatchUpdateResult(id result, NSBatchUpdateRequestResultType type)
{
    NSBatchUpdateResult *r = [[[NSBatchUpdateResult alloc] init] autorelease];
    r->_result = [result retain];
    r->_type = type;
    return r;
}

/* ---- batch requests ------------------------------------------------------------------------ */

@implementation NSBatchDeleteRequest {
    NSFetchRequest *_fetch;
    NSArray *_ids;
    NSBatchDeleteRequestResultType _type;
}
- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetch
{
    if ((self = [super init]))
        _fetch = [fetch copy];
    return self;
}
- (instancetype)initWithObjectIDs:(NSArray *)objects
{
    if ((self = [super init])) {
        _ids = [objects copy];
        NSEntityDescription *e = [[objects firstObject] entity];
        _fetch = [[NSFetchRequest alloc] initWithEntityName:[e name]];
        [_fetch setEntity:e];
        [_fetch setPredicate:[NSPredicate predicateWithFormat:@"self IN %@", objects]];
    }
    return self;
}
- (void)dealloc
{
    [_fetch release];
    [_ids release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSBatchDeleteRequest *c = [super copyWithZone:zone];
    c->_fetch = [_fetch copy];
    c->_ids = [_ids copy];
    c->_type = _type;
    return c;
}
- (NSPersistentStoreRequestType)requestType { return NSBatchDeleteRequestType; }
- (NSFetchRequest *)fetchRequest { return [[_fetch copy] autorelease]; }
- (NSArray *)cd_objectIDs { return _ids; }
- (NSBatchDeleteRequestResultType)resultType { return _type; }
- (void)setResultType:(NSBatchDeleteRequestResultType)t { _type = t; }
@end

@implementation NSBatchUpdateRequest {
    NSString *_entityName;
    NSEntityDescription *_entity;
    NSPredicate *_predicate;
    NSDictionary *_values;
    BOOL _subentities;
    NSBatchUpdateRequestResultType _type;
}
+ (instancetype)batchUpdateRequestWithEntityName:(NSString *)name
{
    return [[[self alloc] initWithEntityName:name] autorelease];
}
- (instancetype)initWithEntityName:(NSString *)name
{
    if ((self = [super init])) {
        _entityName = [name copy];
        _subentities = YES;
    }
    return self;
}
- (instancetype)initWithEntity:(NSEntityDescription *)entity
{
    if ((self = [self initWithEntityName:[entity name]]))
        _entity = [entity retain];
    return self;
}
- (void)dealloc
{
    [_entityName release];
    [_entity release];
    [_predicate release];
    [_values release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSBatchUpdateRequest *c = [super copyWithZone:zone];
    c->_entityName = [_entityName copy];
    c->_entity = [_entity retain];
    c->_predicate = [_predicate retain];
    c->_values = [_values copy];
    c->_subentities = _subentities;
    c->_type = _type;
    return c;
}
- (NSPersistentStoreRequestType)requestType { return NSBatchUpdateRequestType; }
- (NSString *)entityName { return _entityName; }
- (NSEntityDescription *)entity { return _entity; }
- (NSPredicate *)predicate { return _predicate; }
- (void)setPredicate:(NSPredicate *)p
{
    [_predicate autorelease];
    _predicate = [p retain];
}
- (BOOL)includesSubentities { return _subentities; }
- (void)setIncludesSubentities:(BOOL)f { _subentities = f; }
- (NSBatchUpdateRequestResultType)resultType { return _type; }
- (void)setResultType:(NSBatchUpdateRequestResultType)t { _type = t; }
- (NSDictionary *)propertiesToUpdate { return _values; }
- (void)setPropertiesToUpdate:(NSDictionary *)d
{
    [_values autorelease];
    _values = [d copy];
}
@end
