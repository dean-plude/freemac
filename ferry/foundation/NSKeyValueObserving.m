/* SPDX-License-Identifier: GPL-3.0-or-later
 * Key-value observing, as Apple's "Key-Value Observing Programming Guide"
 * describes it: observers registered for a key path of an object hear
 * observeValueForKeyPath:ofObject:change:context: when the object says a
 * value changed (willChangeValueForKey: / didChangeValueForKey:), and when
 * the value is set through key-value coding (setValue:forKey:). What Ferry
 * doesn't do yet: a property's own setter, called directly, notifies only
 * if the class calls will/didChange itself (a Mac also rewrites the setter),
 * and dependent keys (keyPathsForValuesAffecting...) aren't followed. A key
 * path's later keys are watched only on the first object. */
#import "FInternal.h"
#include <os/lock.h>

NSString *const NSKeyValueChangeKindKey = @"kind";
NSString *const NSKeyValueChangeNewKey = @"new";
NSString *const NSKeyValueChangeOldKey = @"old";
NSString *const NSKeyValueChangeIndexesKey = @"indexes";
NSString *const NSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";

@interface FKVOEntry : NSObject {
@public
    id observer;   /* not retained, as on a Mac */
    NSString *keyPath, *firstKey;
    NSKeyValueObservingOptions options;
    void *context;
}
@end
@implementation FKVOEntry
- (void)dealloc
{
    [keyPath release];
    [firstKey release];
    [super dealloc];
}
@end

static os_unfair_lock kvo_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary *kvo_entries;   /* object pointer -> NSMutableArray of FKVOEntry */
static NSMutableDictionary *kvo_old;       /* "pointer key" -> stack of old values (or NSNull) */

static NSValue *pointer_key(id object) { return [NSValue valueWithPointer:object]; }

/* Hung on an observed object (as an associated object), so that when the
 * object goes away its registrations go with it, and a new object at the
 * same address doesn't inherit them. */
@interface FKVOSentinel : NSObject {
@public
    void *object;
}
@end
@implementation FKVOSentinel
- (void)dealloc
{
    os_unfair_lock_lock(&kvo_lock);
    [kvo_entries removeObjectForKey:[NSValue valueWithPointer:object]];
    os_unfair_lock_unlock(&kvo_lock);
    [super dealloc];
}
@end
static char sentinel_key;

BOOL FKVOIsObserved(id object)
{
    if (!kvo_entries)
        return NO;
    os_unfair_lock_lock(&kvo_lock);
    BOOL yes = [kvo_entries objectForKey:pointer_key(object)] != nil;
    os_unfair_lock_unlock(&kvo_lock);
    return yes;
}

/* The entries watching key on object, copied so observers may change them. */
static NSArray *entries_for(id object, NSString *key)
{
    if (!kvo_entries)
        return nil;
    NSMutableArray *out = nil;
    os_unfair_lock_lock(&kvo_lock);
    for (FKVOEntry *e in [kvo_entries objectForKey:pointer_key(object)])
        if ([e->firstKey isEqualToString:key]) {
            if (!out)
                out = [NSMutableArray array];
            [out addObject:e];
        }
    os_unfair_lock_unlock(&kvo_lock);
    return out;
}

static void notify(FKVOEntry *e, id object, NSDictionary *change)
{
    [e->observer observeValueForKeyPath:e->keyPath ofObject:object change:change context:e->context];
}

@implementation NSObject (NSKeyValueObserverRegistration)
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options context:(void *)context
{
    if (!observer || !keyPath)
        return;
    FKVOEntry *e = [[[FKVOEntry alloc] init] autorelease];
    e->observer = observer;
    e->keyPath = [keyPath copy];
    NSRange dot = [keyPath rangeOfString:@"."];
    e->firstKey = [(dot.location == NSNotFound ? keyPath : [keyPath substringToIndex:dot.location]) copy];
    e->options = options;
    e->context = context;
    os_unfair_lock_lock(&kvo_lock);
    if (!kvo_entries)
        kvo_entries = [[NSMutableDictionary alloc] init];
    NSMutableArray *list = [kvo_entries objectForKey:pointer_key(self)];
    if (!list) {
        list = [NSMutableArray array];
        [kvo_entries setObject:list forKey:pointer_key(self)];
    }
    [list addObject:e];
    os_unfair_lock_unlock(&kvo_lock);
    if (!objc_getAssociatedObject(self, &sentinel_key)) {
        FKVOSentinel *sentinel = [[[FKVOSentinel alloc] init] autorelease];
        sentinel->object = self;
        objc_setAssociatedObject(self, &sentinel_key, sentinel, OBJC_ASSOCIATION_RETAIN);
    }
    if (options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting)
                                                                         forKey:NSKeyValueChangeKindKey];
        if (options & NSKeyValueObservingOptionNew)
            [change setObject:[self valueForKeyPath:keyPath] ?: [NSNull null] forKey:NSKeyValueChangeNewKey];
        notify(e, self, change);
    }
}
- (void)_ferryRemoveObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath any:(BOOL)any context:(void *)context
{
    os_unfair_lock_lock(&kvo_lock);
    NSMutableArray *list = [kvo_entries objectForKey:pointer_key(self)];
    /* the most recent matching registration, as on a Mac */
    for (NSInteger i = (NSInteger)[list count] - 1; i >= 0; i--) {
        FKVOEntry *e = [list objectAtIndex:(NSUInteger)i];
        if (e->observer == observer && [e->keyPath isEqualToString:keyPath] && (any || e->context == context)) {
            [list removeObjectAtIndex:(NSUInteger)i];
            break;
        }
    }
    if (list && ![list count])
        [kvo_entries removeObjectForKey:pointer_key(self)];
    os_unfair_lock_unlock(&kvo_lock);
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    [self _ferryRemoveObserver:observer forKeyPath:keyPath any:YES context:NULL];
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context
{
    [self _ferryRemoveObserver:observer forKeyPath:keyPath any:NO context:context];
}
@end

@implementation NSObject (NSKeyValueObserving)
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    /* A Mac raises here, for an observer that didn't handle its own
     * registration; Ferry lets it pass. */
}
- (void)willChangeValueForKey:(NSString *)key
{
    NSArray *entries = entries_for(self, key);
    if (![entries count])
        return;
    id old = nil;
    BOOL wantOld = NO;
    for (FKVOEntry *e in entries)
        wantOld |= (e->options & NSKeyValueObservingOptionOld) != 0;
    if (wantOld)
        old = [self valueForKey:key];
    NSString *k = [NSString stringWithFormat:@"%p.%@", self, key];
    os_unfair_lock_lock(&kvo_lock);
    if (!kvo_old)
        kvo_old = [[NSMutableDictionary alloc] init];
    NSMutableArray *stack = [kvo_old objectForKey:k];
    if (!stack) {
        stack = [NSMutableArray array];
        [kvo_old setObject:stack forKey:k];
    }
    [stack addObject:old ?: [NSNull null]];
    os_unfair_lock_unlock(&kvo_lock);
    for (FKVOEntry *e in entries)
        if (e->options & NSKeyValueObservingOptionPrior) {
            NSMutableDictionary *change = [NSMutableDictionary dictionary];
            [change setObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
            [change setObject:@YES forKey:NSKeyValueChangeNotificationIsPriorKey];
            if (e->options & NSKeyValueObservingOptionOld)
                [change setObject:old ?: [NSNull null] forKey:NSKeyValueChangeOldKey];
            notify(e, self, change);
        }
}
- (void)didChangeValueForKey:(NSString *)key
{
    NSArray *entries = entries_for(self, key);
    id old = nil;
    NSString *k = [NSString stringWithFormat:@"%p.%@", self, key];
    os_unfair_lock_lock(&kvo_lock);
    NSMutableArray *stack = [kvo_old objectForKey:k];
    if ([stack count]) {
        old = [[[stack lastObject] retain] autorelease];
        [stack removeLastObject];
        if (![stack count])
            [kvo_old removeObjectForKey:k];
    }
    os_unfair_lock_unlock(&kvo_lock);
    for (FKVOEntry *e in entries) {
        NSMutableDictionary *change = [NSMutableDictionary dictionary];
        [change setObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        if (e->options & NSKeyValueObservingOptionNew)
            [change setObject:[self valueForKeyPath:e->keyPath] ?: [NSNull null] forKey:NSKeyValueChangeNewKey];
        if ((e->options & NSKeyValueObservingOptionOld) && [e->keyPath isEqualToString:key])
            [change setObject:old ?: [NSNull null] forKey:NSKeyValueChangeOldKey];
        notify(e, self, change);
    }
}
- (void)willChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    [self willChangeValueForKey:key];
}
- (void)didChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    [self didChangeValueForKey:key];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return YES; }
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key { return [NSSet set]; }
- (void *)observationInfo { return NULL; }
- (void)setObservationInfo:(void *)info {}
@end
