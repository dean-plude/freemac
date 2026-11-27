/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSCache and NSProgress.
 *
 * NSCache keeps its keys without copying them and lets objects go, least
 * recently used first, once its count or total cost limit is passed,
 * telling its delegate before each one goes (and before an object is
 * removed or replaced). Ferry has no memory-pressure signal for it, so
 * only the limits evict.
 *
 * NSProgress keeps a tree: a child counts for a portion (its pending unit
 * count) of its parent's total, the parent's fractionCompleted includes
 * the children's, and a finished child's portion is added to the parent's
 * completedUnitCount. A progress made while another is current (after
 * becomeCurrentWithPendingUnitCount:) becomes its child. fractionCompleted,
 * completedUnitCount, totalUnitCount, localizedDescription and the rest
 * are observable with key-value observing, up the tree.
 *
 * Written from Apple's public documentation; no Apple code was used. */
#import "FInternal.h"

/* ---- NSCache ------------------------------------------------------------------- */

/* A key as the cache holds it: retained, not copied. */
@interface FCacheKey : NSObject <NSCopying> {
@public
    id _key;
}
@end
@implementation FCacheKey
- (void)dealloc
{
    [_key release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)hash { return [_key hash]; }
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[FCacheKey class]] && [_key isEqual:((FCacheKey *)other)->_key]; }
@end

@interface FCacheEntry : NSObject {
@public
    id _key, _object;
    NSUInteger _cost;
    FCacheEntry *_newer, *_older; /* the use order, not retained */
}
@end
@implementation FCacheEntry
- (void)dealloc
{
    [_key release];
    [_object release];
    [super dealloc];
}
@end

@implementation NSCache {
    NSMutableDictionary *_entries; /* FCacheKey -> FCacheEntry */
    FCacheEntry *_newest, *_oldest;
    NSUInteger _totalCost, _costLimit, _countLimit;
    BOOL _evictsDiscarded;
    NSString *_name;
    id _delegate;
}
- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _entries = [[NSMutableDictionary alloc] init];
    _evictsDiscarded = YES;
    _name = @"";
    return self;
}
- (void)dealloc
{
    [_entries release];
    [_name release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"<NSCache: %p>", self]; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    name = [name copy] ?: @"";
    [_name release];
    _name = name;
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSUInteger)totalCostLimit { return _costLimit; }
- (void)setTotalCostLimit:(NSUInteger)limit
{
    _costLimit = limit;
    [self _trim];
}
- (NSUInteger)countLimit { return _countLimit; }
- (void)setCountLimit:(NSUInteger)limit
{
    _countLimit = limit;
    [self _trim];
}
- (BOOL)evictsObjectsWithDiscardedContent { return _evictsDiscarded; }
- (void)setEvictsObjectsWithDiscardedContent:(BOOL)flag { _evictsDiscarded = flag; }

static FCacheKey *wrap(id key)
{
    FCacheKey *k = [[[FCacheKey alloc] init] autorelease];
    k->_key = [key retain];
    return k;
}
- (void)_unlink:(FCacheEntry *)e
{
    if (e->_newer)
        e->_newer->_older = e->_older;
    else
        _newest = e->_older;
    if (e->_older)
        e->_older->_newer = e->_newer;
    else
        _oldest = e->_newer;
    e->_newer = e->_older = nil;
}
- (void)_makeNewest:(FCacheEntry *)e
{
    e->_older = _newest;
    e->_newer = nil;
    if (_newest)
        _newest->_newer = e;
    _newest = e;
    if (!_oldest)
        _oldest = e;
}
/* Takes an entry out, telling the delegate first. */
- (void)_remove:(FCacheEntry *)e tell:(BOOL)tell
{
    [[e retain] autorelease];
    if (tell && [_delegate respondsToSelector:@selector(cache:willEvictObject:)])
        [_delegate cache:self willEvictObject:e->_object];
    [self _unlink:e];
    _totalCost -= e->_cost;
    [_entries removeObjectForKey:wrap(e->_key)];
}
- (void)_trim
{
    while (_oldest && ((_countLimit && [_entries count] > _countLimit) || (_costLimit && _totalCost > _costLimit)))
        [self _remove:_oldest tell:YES];
}

- (id)objectForKey:(id)key
{
    if (!key)
        return nil;
    FCacheEntry *e = [_entries objectForKey:wrap(key)];
    if (!e)
        return nil;
    if (_evictsDiscarded && [e->_object conformsToProtocol:@protocol(NSDiscardableContent)] &&
        [e->_object isContentDiscarded]) {
        [self _remove:e tell:YES];
        return nil;
    }
    [self _unlink:e];
    [self _makeNewest:e];
    return [[e->_object retain] autorelease];
}
- (void)setObject:(id)obj forKey:(id)key { [self setObject:obj forKey:key cost:0]; }
- (void)setObject:(id)obj forKey:(id)key cost:(NSUInteger)cost
{
    if (!obj) {
        [self removeObjectForKey:key];
        return;
    }
    if (!key)
        FRaise(NSInvalidArgumentException, @"*** -[NSCache setObject:forKey:cost:]: attempt to insert value with nil key");
    FCacheEntry *old = [_entries objectForKey:wrap(key)];
    if (old && old->_object != obj)
        [self _remove:old tell:YES];
    else if (old)
        [self _remove:old tell:NO];
    FCacheEntry *e = [[FCacheEntry alloc] init];
    e->_key = [key retain];
    e->_object = [obj retain];
    e->_cost = cost;
    [_entries setObject:e forKey:wrap(key)];
    [e release];
    [self _makeNewest:e];
    _totalCost += cost;
    [self _trim];
}
- (void)removeObjectForKey:(id)key
{
    if (!key)
        return;
    FCacheEntry *e = [_entries objectForKey:wrap(key)];
    if (e)
        [self _remove:e tell:YES];
}
- (void)removeAllObjects
{
    while (_oldest)
        [self _remove:_oldest tell:YES];
}
@end

/* ---- NSProgress ---------------------------------------------------------------- */

NSString *const NSProgressKindFile = @"NSProgressKindFile";
NSString *const NSProgressEstimatedTimeRemainingKey = @"NSProgressEstimatedTimeRemainingKey";
NSString *const NSProgressThroughputKey = @"NSProgressThroughputKey";
NSString *const NSProgressFileOperationKindKey = @"NSProgressFileOperationKindKey";
NSString *const NSProgressFileURLKey = @"NSProgressFileURLKey";
NSString *const NSProgressFileTotalCountKey = @"NSProgressFileTotalCountKey";
NSString *const NSProgressFileCompletedCountKey = @"NSProgressFileCompletedCountKey";

/* Each thread's current progress objects, innermost last, as on a Mac,
 * where the current progress belongs to a thread. */
static pthread_key_t stack_key;
static void free_stack(void *stack) { [(NSMutableArray *)stack release]; }
static NSMutableArray *current_stack(BOOL make)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      pthread_key_create(&stack_key, free_stack);
    });
    NSMutableArray *stack = pthread_getspecific(stack_key);
    if (!stack && make) {
        stack = [[NSMutableArray alloc] init];
        pthread_setspecific(stack_key, stack);
    }
    return stack;
}

@interface NSProgress () {
@public
    NSProgress *_parent;          /* not retained: the parent holds its children */
    NSMutableArray *_children;
    NSMutableArray *_portions;    /* NSNumber per child: its share of this one's total */
    int64_t _total, _completed;
    int64_t _pending;             /* while current: the share the next child gets */
    BOOL _pendingUsed;
    NSString *_description, *_additional;
    BOOL _cancellable, _pausable, _cancelled, _paused;
    void (^_onCancel)(void), (^_onPause)(void), (^_onResume)(void);
    NSMutableDictionary *_userInfo;
    NSString *_kind;
}
@end

@implementation NSProgress

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    static NSSet *manual;
    static dispatch_once_t manual_once;
    dispatch_once(&manual_once, ^{
        manual = [[NSSet setWithObjects:@"totalUnitCount", @"completedUnitCount", @"fractionCompleted",
                                                @"cancelled", @"paused", @"finished", @"indeterminate", nil] retain];
    });
    return [manual containsObject:key] ? NO : [super automaticallyNotifiesObserversForKey:key];
}
+ (NSSet *)keyPathsForValuesAffectingLocalizedDescription
{
    return [NSSet setWithObjects:@"fractionCompleted", @"kind", nil];
}
+ (NSSet *)keyPathsForValuesAffectingLocalizedAdditionalDescription
{
    return [NSSet setWithObjects:@"completedUnitCount", @"totalUnitCount", @"fractionCompleted", nil];
}

+ (NSProgress *)currentProgress { return [current_stack(NO) lastObject]; }
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)n
{
    NSProgress *p = [[[self alloc] initWithParent:[self currentProgress] userInfo:nil] autorelease];
    [p setTotalUnitCount:n];
    return p;
}
+ (NSProgress *)discreteProgressWithTotalUnitCount:(int64_t)n
{
    NSProgress *p = [[[self alloc] initWithParent:nil userInfo:nil] autorelease];
    [p setTotalUnitCount:n];
    return p;
}
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)n parent:(NSProgress *)parent pendingUnitCount:(int64_t)portion
{
    NSProgress *p = [[[self alloc] initWithParent:nil userInfo:nil] autorelease];
    [p setTotalUnitCount:n];
    [parent addChild:p withPendingUnitCount:portion];
    return p;
}
- (instancetype)init { return [self initWithParent:nil userInfo:nil]; }
- (instancetype)initWithParent:(NSProgress *)parent userInfo:(NSDictionary *)userInfo
{
    if (!(self = [super init]))
        return nil;
    _children = [[NSMutableArray alloc] init];
    _portions = [[NSMutableArray alloc] init];
    _userInfo = userInfo ? [userInfo mutableCopy] : [[NSMutableDictionary alloc] init];
    _cancellable = YES;
    if (parent) {
        if (parent != [NSProgress currentProgress])
            FRaise(NSInvalidArgumentException, @"The parent passed to -[NSProgress initWithParent:userInfo:] must be "
                                               @"nil or the current progress");
        if (!parent->_pendingUsed) {
            parent->_pendingUsed = YES;
            [parent addChild:self withPendingUnitCount:parent->_pending];
        }
    }
    return self;
}
- (void)dealloc
{
    for (NSProgress *c in _children)
        c->_parent = nil;
    [_children release];
    [_portions release];
    [_description release];
    [_additional release];
    [_onCancel release];
    [_onPause release];
    [_onResume release];
    [_userInfo release];
    [_kind release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSProgress: %p> : Parent: %p / Fraction completed: %.4f / Completed: %lld of "
                                      @"%lld",
                                      self, _parent, [self fractionCompleted], (long long)_completed,
                                      (long long)_total];
}

/* fractionCompleted changes here and in every ancestor at once */
static void will_change_fraction(NSProgress *p, NSString *also)
{
    if (also)
        [p willChangeValueForKey:also];
    for (NSProgress *q = p; q; q = q->_parent)
        [q willChangeValueForKey:@"fractionCompleted"];
}
static void did_change_fraction(NSProgress *p, NSString *also)
{
    NSMutableArray *chain = [NSMutableArray array];
    for (NSProgress *q = p; q; q = q->_parent)
        [chain addObject:q];
    for (NSProgress *q in [chain reverseObjectEnumerator])
        [q didChangeValueForKey:@"fractionCompleted"];
    if (also)
        [p didChangeValueForKey:also];
}

- (BOOL)isFinished { return _total > 0 ? _completed >= _total : (_total == 0 && _completed > 0); }

/* A finished child's portion moves into this one's completed units. */
- (void)_childFinished:(NSProgress *)child
{
    NSUInteger i = [_children indexOfObjectIdenticalTo:child];
    if (i == NSNotFound)
        return;
    int64_t portion = [[_portions objectAtIndex:i] longLongValue];
    [[child retain] autorelease];
    will_change_fraction(self, @"completedUnitCount");
    child->_parent = nil;
    [_children removeObjectAtIndex:i];
    [_portions removeObjectAtIndex:i];
    BOOL wasFinished = [self isFinished];
    _completed += portion;
    did_change_fraction(self, @"completedUnitCount");
    if (!wasFinished && [self isFinished])
        [_parent _childFinished:self];
}
- (void)_set:(int64_t *)field to:(int64_t)v key:(NSString *)key
{
    if (*field == v)
        return;
    BOOL wasFinished = [self isFinished];
    [self willChangeValueForKey:@"finished"];
    [self willChangeValueForKey:@"indeterminate"];
    will_change_fraction(self, key);
    *field = v;
    did_change_fraction(self, key);
    [self didChangeValueForKey:@"indeterminate"];
    [self didChangeValueForKey:@"finished"];
    if (!wasFinished && [self isFinished])
        [_parent _childFinished:self];
}
- (int64_t)totalUnitCount { return _total; }
- (void)setTotalUnitCount:(int64_t)n { [self _set:&_total to:n key:@"totalUnitCount"]; }
- (int64_t)completedUnitCount { return _completed; }
- (void)setCompletedUnitCount:(int64_t)n { [self _set:&_completed to:n key:@"completedUnitCount"]; }
- (BOOL)isIndeterminate { return _total < 0 || _completed < 0; }
- (double)fractionCompleted
{
    if (_total <= 0)
        return _total == 0 && _completed > 0 ? 1.0 : 0.0;
    double done = _completed > 0 ? (double)_completed : 0;
    for (NSUInteger i = 0; i < [_children count]; i++) {
        double f = [[_children objectAtIndex:i] fractionCompleted];
        done += (f > 1 ? 1 : f) * (double)[[_portions objectAtIndex:i] longLongValue];
    }
    return done / (double)_total;
}

- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)portion
{
    if (!child)
        return;
    if (child->_parent)
        FRaise(NSInvalidArgumentException, @"*** -[NSProgress addChild:withPendingUnitCount:]: the child already has "
                                           @"a parent");
    will_change_fraction(self, nil);
    child->_parent = self;
    [_children addObject:child];
    [_portions addObject:[NSNumber numberWithLongLong:portion]];
    did_change_fraction(self, nil);
    if ([child isFinished])
        [self _childFinished:child];
    if (_cancelled)
        [child cancel];
    if (_paused)
        [child pause];
}
- (void)becomeCurrentWithPendingUnitCount:(int64_t)n
{
    _pending = n;
    _pendingUsed = NO;
    [current_stack(YES) addObject:self];
}
- (void)resignCurrent
{
    if ([current_stack(NO) lastObject] != self)
        FRaise(NSInternalInconsistencyException, @"*** -[NSProgress resignCurrent]: this progress is not the "
                                                 @"current progress");
    [[self retain] autorelease];
    [current_stack(NO) removeLastObject];
    /* no child came to do the pending work: count it as done */
    if (!_pendingUsed && _pending)
        [self setCompletedUnitCount:_completed + _pending];
    _pending = 0;
    _pendingUsed = NO;
}
- (void)performAsCurrentWithPendingUnitCount:(int64_t)n usingBlock:(void (^)(void))work
{
    [self becomeCurrentWithPendingUnitCount:n];
    @try {
        work();
    } @finally {
        [self resignCurrent];
    }
}

- (NSString *)localizedDescription
{
    if (_description)
        return _description;
    if ([self isIndeterminate])
        return @"";
    return [NSString stringWithFormat:@"%ld%% completed", lround([self fractionCompleted] * 100)];
}
- (void)setLocalizedDescription:(NSString *)s
{
    s = [s copy];
    [_description release];
    _description = s;
}
- (NSString *)localizedAdditionalDescription
{
    if (_additional)
        return _additional;
    if (_total <= 0 || _completed < 0)
        return @"";
    return [NSString stringWithFormat:@"%lld of %lld", (long long)_completed, (long long)_total];
}
- (void)setLocalizedAdditionalDescription:(NSString *)s
{
    s = [s copy];
    [_additional release];
    _additional = s;
}

- (BOOL)isCancellable { return _cancellable; }
- (void)setCancellable:(BOOL)flag { _cancellable = flag; }
- (BOOL)isPausable { return _pausable; }
- (void)setPausable:(BOOL)flag { _pausable = flag; }
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isPaused { return _paused; }
#define BLOCK_PROPERTY(get, set, ivar)                                                                                 \
    -(void (^)(void))get { return [[ivar retain] autorelease]; }                                                       \
    -(void)set:(void (^)(void))block                                                                                   \
    {                                                                                                                  \
        block = [block copy];                                                                                          \
        [ivar release];                                                                                                \
        ivar = block;                                                                                                  \
    }
BLOCK_PROPERTY(cancellationHandler, setCancellationHandler, _onCancel)
BLOCK_PROPERTY(pausingHandler, setPausingHandler, _onPause)
BLOCK_PROPERTY(resumingHandler, setResumingHandler, _onResume)
#undef BLOCK_PROPERTY

- (void)cancel
{
    if (_cancelled)
        return;
    [self willChangeValueForKey:@"cancelled"];
    _cancelled = YES;
    [self didChangeValueForKey:@"cancelled"];
    if (_onCancel)
        _onCancel();
    for (NSProgress *c in [[_children copy] autorelease])
        [c cancel];
}
- (void)pause
{
    if (_paused)
        return;
    [self willChangeValueForKey:@"paused"];
    _paused = YES;
    [self didChangeValueForKey:@"paused"];
    if (_onPause)
        _onPause();
    for (NSProgress *c in [[_children copy] autorelease])
        [c pause];
}
- (void)resume
{
    if (!_paused)
        return;
    [self willChangeValueForKey:@"paused"];
    _paused = NO;
    [self didChangeValueForKey:@"paused"];
    if (_onResume)
        _onResume();
    for (NSProgress *c in [[_children copy] autorelease])
        [c resume];
}

- (NSDictionary *)userInfo { return [[_userInfo copy] autorelease]; }
- (void)setUserInfoObject:(id)obj forKey:(NSString *)key
{
    [self willChangeValueForKey:@"userInfo"];
    if (obj)
        [_userInfo setObject:obj forKey:key];
    else
        [_userInfo removeObjectForKey:key];
    [self didChangeValueForKey:@"userInfo"];
}
- (NSString *)kind { return _kind; }
- (void)setKind:(NSString *)kind
{
    kind = [kind copy];
    [_kind release];
    _kind = kind;
}
#define INFO_PROPERTY(type, get, set, key)                                                                             \
    -(type)get { return [_userInfo objectForKey:key]; }                                                                \
    -(void)set:(type)v { [self setUserInfoObject:v forKey:key]; }
INFO_PROPERTY(NSNumber *, estimatedTimeRemaining, setEstimatedTimeRemaining, NSProgressEstimatedTimeRemainingKey)
INFO_PROPERTY(NSNumber *, throughput, setThroughput, NSProgressThroughputKey)
INFO_PROPERTY(NSString *, fileOperationKind, setFileOperationKind, NSProgressFileOperationKindKey)
INFO_PROPERTY(NSURL *, fileURL, setFileURL, NSProgressFileURLKey)
INFO_PROPERTY(NSNumber *, fileTotalCount, setFileTotalCount, NSProgressFileTotalCountKey)
INFO_PROPERTY(NSNumber *, fileCompletedCount, setFileCompletedCount, NSProgressFileCompletedCountKey)
#undef INFO_PROPERTY

/* Publishing a progress shows it to other programs (the Finder draws a
 * bar on the file it names). Nothing on freemac subscribes yet, so these
 * keep it to this program. */
- (void)publish {}
- (void)unpublish {}
+ (id)addSubscriberForFileURL:(NSURL *)url withPublishingHandler:(id)handler
{
    return [[[NSObject alloc] init] autorelease];
}
+ (void)removeSubscriber:(id)subscriber {}
- (BOOL)isOld { return NO; }
@end
