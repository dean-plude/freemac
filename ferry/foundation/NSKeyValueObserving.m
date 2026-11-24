/* SPDX-License-Identifier: GPL-3.0-or-later
 * Key-value observing, as Apple's "Key-Value Observing Programming Guide"
 * and the NSKeyValueObserving reference describe it. Observers registered
 * for a key path of an object hear observeValueForKeyPath:ofObject:change:
 * context: when a value along the path changes.
 *
 * Automatic notification works the way the guide describes a Mac doing it:
 * when an object first gets an observer for a key, its class gets a hidden
 * subclass, "NSKVONotifying_<Class>", and the object becomes an instance of
 * it. The subclass's setters (set<Key>: and _set<Key>:) and the indexed
 * to-many mutators (insertObject:in<Key>AtIndex: and the rest) call
 * willChangeValueForKey: and didChangeValueForKey: (or the indexed forms)
 * around the class's own method. -class still answers the original class.
 * A class keeps a key to itself with automaticallyNotifiesObserversForKey:
 * or automaticallyNotifiesObserversOf<Key>. Once made, the subclass stays,
 * even after the last observer goes.
 *
 * Key paths are followed: an observer of "owner.name" hears of a new owner
 * and of the owner's name changing, the observation moving to the new
 * owner as it comes. Dependent keys come from
 * keyPathsForValuesAffectingValueForKey: (by default
 * keyPathsForValuesAffecting<Key>), and may themselves be key paths
 * through to-one relationships.
 *
 * Unordered to-many keys (sets) announce their changes with
 * willChangeValueForKey:withSetMutation:usingObjects: and the did form:
 * a union is an insertion of the objects that weren't there, a minus or an
 * intersect a removal of those that were, and setting the set a
 * replacement (Ferry 0.18.0). The hidden subclass wraps add<Key>Object:,
 * remove<Key>Object:, add<Key>:, remove<Key>: and intersect<Key>: so.
 * Removing an observer that isn't registered raises NSRangeException, as
 * on a Mac.
 *
 * Not done: to-many key paths ("people.name") aren't followed past a plain
 * collection (an object that answers _ferryObservesElements, such as an
 * array controller's arrangedObjects, follows them itself), and a setter
 * whose argument is a struct other than a point, size, rect or range isn't
 * rewritten. Written from Apple's public documentation; no Apple code was
 * used. */
#import "FInternal.h"
#include <os/lock.h>

NSString *const NSKeyValueChangeKindKey = @"kind";
NSString *const NSKeyValueChangeNewKey = @"new";
NSString *const NSKeyValueChangeOldKey = @"old";
NSString *const NSKeyValueChangeIndexesKey = @"indexes";
NSString *const NSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";

static os_unfair_lock kvo_lock = OS_UNFAIR_LOCK_INIT;
#define LOCK() os_unfair_lock_lock(&kvo_lock)
#define UNLOCK() os_unfair_lock_unlock(&kvo_lock)

@class FKVOForwarder, FKVODependency;

/* One registration: an observer of a key path of an object. */
@interface FKVOEntry : NSObject {
@public
    id observer;   /* not retained, as on a Mac */
    id object;     /* the observed object, not retained (it holds us) */
    NSString *keyPath, *firstKey, *rest;
    NSKeyValueObservingOptions options;
    void *context;
    NSMutableArray *olds;          /* old values kept between will and did (NSNull for nil) */
    NSMutableArray *news;          /* a set mutation's new objects, kept the same way */
    FKVOForwarder *forwarder;      /* watches `rest` on `subject` */
    id subject;                    /* the first key's value, retained while watched */
    BOOL removed;
}
@end

/* Watches the rest of an entry's key path on the first key's value, and
 * passes its changes on to the entry. */
@interface FKVOForwarder : NSObject {
@public
    FKVOEntry *entry;   /* not retained: the entry owns us */
}
@end

/* What an observed object keeps: its registrations, and the observers that
 * turn changes of other key paths into changes of a dependent key. Hung on
 * the object as an associated object, so that it goes when the object
 * does. */
@interface FKVOInfo : NSObject {
@public
    id object;
    NSMutableArray *entries;
    NSMutableDictionary *dependencies;   /* key -> FKVODependency */
}
@end

@interface FKVODependency : NSObject {
@public
    id object;
    NSString *key;
    NSArray *paths;
    NSUInteger count;
    BOOL observing;
}
@end

static char info_key;

static void entry_detach(FKVOEntry *e);
static void dependency_release(id object, NSString *key);

@implementation FKVOEntry
- (void)dealloc
{
    [keyPath release];
    [firstKey release];
    [rest release];
    [olds release];
    [news release];
    [forwarder release];
    [subject release];
    [super dealloc];
}
@end

@implementation FKVOInfo
- (void)dealloc
{
    /* the object is going: its observations of other objects go too */
    for (FKVOEntry *e in entries) {
        e->removed = YES;
        entry_detach(e);
    }
    for (FKVODependency *d in [dependencies allValues])
        d->observing = NO;   /* registered on the object itself, now gone */
    [entries release];
    [dependencies release];
    [super dealloc];
}
@end

static FKVOInfo *info_for(id object, BOOL create)
{
    FKVOInfo *info = objc_getAssociatedObject(object, &info_key);
    if (!info && create) {
        info = [[[FKVOInfo alloc] init] autorelease];
        info->object = object;
        info->entries = [[NSMutableArray alloc] init];
        info->dependencies = [[NSMutableDictionary alloc] init];
        objc_setAssociatedObject(object, &info_key, info, OBJC_ASSOCIATION_RETAIN);
    }
    return info;
}

BOOL FKVOIsObserved(id object)
{
    FKVOInfo *info = objc_getAssociatedObject(object, &info_key);
    return info && [info->entries count];
}

/* The entries watching key on object, copied so observers may change them. */
static NSArray *entries_for(id object, NSString *key)
{
    FKVOInfo *info = objc_getAssociatedObject(object, &info_key);
    if (!info)
        return nil;
    NSMutableArray *out = nil;
    LOCK();
    for (FKVOEntry *e in info->entries)
        if ([e->firstKey isEqualToString:key]) {
            if (!out)
                out = [NSMutableArray array];
            [out addObject:e];
        }
    UNLOCK();
    return out;
}

/* ---- the hidden subclass ------------------------------------------------------------ */

static struct kvo_pair {
    Class original, kvo;
} *kvo_classes;
static size_t kvo_count;
static NSMutableDictionary *mutator_keys;   /* selector name -> key */

static Class original_of(Class kvo)
{
    for (size_t i = 0; i < kvo_count; i++)
        if (kvo_classes[i].kvo == kvo)
            return kvo_classes[i].original;
    return Nil;
}

/* The class whose own method a rewritten method calls: the class the
 * hidden subclass was made for. */
static Class real_class(id self)
{
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        LOCK();
        Class o = original_of(c);
        UNLOCK();
        if (o)
            return o;
    }
    return object_getClass(self);
}

static NSString *mutator_key(SEL sel)
{
    LOCK();
    NSString *k = [[[mutator_keys objectForKey:NSStringFromSelector(sel)] retain] autorelease];
    UNLOCK();
    return k;
}

static Class kvo_class_answer(id self, SEL _cmd) { return real_class(self); }
static void kvo_initialize(id self, SEL _cmd) {}
static BOOL kvo_is_kvo(id self, SEL _cmd) { return YES; }

/* Setters, by the kind of value they take. */
#define ORIGINAL(type) ((type)class_getMethodImplementation(real_class(self), _cmd))
static void set_object(id self, SEL _cmd, id v)
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, id))(self, _cmd, v);
    [self didChangeValueForKey:key];
}
static void set_integer(id self, SEL _cmd, long v)
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, long))(self, _cmd, v);
    [self didChangeValueForKey:key];
}
static void set_float(id self, SEL _cmd, float v)
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, float))(self, _cmd, v);
    [self didChangeValueForKey:key];
}
static void set_double(id self, SEL _cmd, double v)
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, double))(self, _cmd, v);
    [self didChangeValueForKey:key];
}
static void set_pair(id self, SEL _cmd, NSPoint v)   /* points and sizes: two doubles */
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, NSPoint))(self, _cmd, v);
    [self didChangeValueForKey:key];
}
static void set_rect(id self, SEL _cmd, NSRect v)
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, NSRect))(self, _cmd, v);
    [self didChangeValueForKey:key];
}
static void set_range(id self, SEL _cmd, NSRange v)
{
    NSString *key = mutator_key(_cmd);
    [self willChangeValueForKey:key];
    ORIGINAL(void (*)(id, SEL, NSRange))(self, _cmd, v);
    [self didChangeValueForKey:key];
}

/* The indexed to-many mutators. */
static void insert_one(id self, SEL _cmd, id obj, NSUInteger i)
{
    NSString *key = mutator_key(_cmd);
    NSIndexSet *at = [NSIndexSet indexSetWithIndex:i];
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:at forKey:key];
    ORIGINAL(void (*)(id, SEL, id, NSUInteger))(self, _cmd, obj, i);
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:at forKey:key];
}
static void remove_one(id self, SEL _cmd, NSUInteger i)
{
    NSString *key = mutator_key(_cmd);
    NSIndexSet *at = [NSIndexSet indexSetWithIndex:i];
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:at forKey:key];
    ORIGINAL(void (*)(id, SEL, NSUInteger))(self, _cmd, i);
    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:at forKey:key];
}
static void replace_one(id self, SEL _cmd, NSUInteger i, id obj)
{
    NSString *key = mutator_key(_cmd);
    NSIndexSet *at = [NSIndexSet indexSetWithIndex:i];
    [self willChange:NSKeyValueChangeReplacement valuesAtIndexes:at forKey:key];
    ORIGINAL(void (*)(id, SEL, NSUInteger, id))(self, _cmd, i, obj);
    [self didChange:NSKeyValueChangeReplacement valuesAtIndexes:at forKey:key];
}
static void insert_many(id self, SEL _cmd, NSArray *objs, NSIndexSet *at)
{
    NSString *key = mutator_key(_cmd);
    at = [[at copy] autorelease];
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:at forKey:key];
    ORIGINAL(void (*)(id, SEL, NSArray *, NSIndexSet *))(self, _cmd, objs, at);
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:at forKey:key];
}
static void remove_many(id self, SEL _cmd, NSIndexSet *at)
{
    NSString *key = mutator_key(_cmd);
    at = [[at copy] autorelease];
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:at forKey:key];
    ORIGINAL(void (*)(id, SEL, NSIndexSet *))(self, _cmd, at);
    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:at forKey:key];
}
static void replace_many(id self, SEL _cmd, NSIndexSet *at, NSArray *objs)
{
    NSString *key = mutator_key(_cmd);
    at = [[at copy] autorelease];
    [self willChange:NSKeyValueChangeReplacement valuesAtIndexes:at forKey:key];
    ORIGINAL(void (*)(id, SEL, NSIndexSet *, NSArray *))(self, _cmd, at, objs);
    [self didChange:NSKeyValueChangeReplacement valuesAtIndexes:at forKey:key];
}

/* The unordered to-many mutators: one object, or a set of them. */
static void set_union_one(id self, SEL _cmd, id obj)
{
    NSString *key = mutator_key(_cmd);
    NSSet *objs = obj ? [NSSet setWithObject:obj] : [NSSet set];
    [self willChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:objs];
    ORIGINAL(void (*)(id, SEL, id))(self, _cmd, obj);
    [self didChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:objs];
}
static void set_minus_one(id self, SEL _cmd, id obj)
{
    NSString *key = mutator_key(_cmd);
    NSSet *objs = obj ? [NSSet setWithObject:obj] : [NSSet set];
    [self willChangeValueForKey:key withSetMutation:NSKeyValueMinusSetMutation usingObjects:objs];
    ORIGINAL(void (*)(id, SEL, id))(self, _cmd, obj);
    [self didChangeValueForKey:key withSetMutation:NSKeyValueMinusSetMutation usingObjects:objs];
}
#define SET_MANY(fn, kind)                                                       \
    static void fn(id self, SEL _cmd, NSSet *objs)                               \
    {                                                                            \
        NSString *key = mutator_key(_cmd);                                       \
        objs = [[objs copy] autorelease] ?: [NSSet set];                         \
        [self willChangeValueForKey:key withSetMutation:kind usingObjects:objs]; \
        ORIGINAL(void (*)(id, SEL, NSSet *))(self, _cmd, objs);                  \
        [self didChangeValueForKey:key withSetMutation:kind usingObjects:objs];  \
    }
SET_MANY(set_union_many, NSKeyValueUnionSetMutation)
SET_MANY(set_minus_many, NSKeyValueMinusSetMutation)
SET_MANY(set_intersect_many, NSKeyValueIntersectSetMutation)

/* The rewritten setter for a setter taking this type, or NULL. */
static IMP setter_for_type(const char *t)
{
    while (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'R' || *t == 'V')
        t++;   /* qualifiers: const, in, out... */
    switch (*t) {
    case '@':
    case '#': return (IMP)set_object;
    case 'c': case 'C': case 'B': case 's': case 'S': case 'i': case 'I':
    case 'l': case 'L': case 'q': case 'Q': case '*': case '^': case ':': return (IMP)set_integer;
    case 'f': return (IMP)set_float;
    case 'd': return (IMP)set_double;
    case '{':
        if (!strncmp(t, "{CGPoint=", 9) || !strncmp(t, "{CGSize=", 8) || !strncmp(t, "{_NSPoint=", 10) ||
            !strncmp(t, "{_NSSize=", 9))
            return (IMP)set_pair;
        if (!strncmp(t, "{CGRect=", 8) || !strncmp(t, "{_NSRect=", 9))
            return (IMP)set_rect;
        if (!strncmp(t, "{_NSRange=", 10))
            return (IMP)set_range;
        return NULL;
    }
    return NULL;
}

/* The hidden subclass for an object's class, made the first time. */
static Class kvo_class_for(Class original)
{
    LOCK();
    for (size_t i = 0; i < kvo_count; i++)
        if (kvo_classes[i].original == original || kvo_classes[i].kvo == original) {
            Class k = kvo_classes[i].kvo;
            UNLOCK();
            return k;
        }
    UNLOCK();
    char name[512];
    snprintf(name, sizeof name, "NSKVONotifying_%s", class_getName(original));
    Class kvo = objc_getClass(name);
    if (!kvo) {
        kvo = objc_allocateClassPair(original, name, 0);
        if (!kvo)
            return Nil;
        class_addMethod(kvo, @selector(class), (IMP)kvo_class_answer, "#16@0:8");
        class_addMethod(kvo, sel_registerName("_isKVOA"), (IMP)kvo_is_kvo, "c16@0:8");
        /* the original class's +initialize has run already; it isn't run again */
        class_addMethod(object_getClass(kvo), @selector(initialize), (IMP)kvo_initialize, "v16@0:8");
        objc_registerClassPair(kvo);
    }
    LOCK();
    kvo_classes = realloc(kvo_classes, (kvo_count + 1) * sizeof *kvo_classes);
    kvo_classes[kvo_count++] = (struct kvo_pair){original, kvo};
    UNLOCK();
    return kvo;
}

static void add_mutator(Class kvo, Class original, NSString *name, NSString *key, IMP imp)
{
    SEL sel = NSSelectorFromString(name);
    Method m = class_getInstanceMethod(original, sel);
    if (!m || !imp)
        return;
    LOCK();
    if (!mutator_keys)
        mutator_keys = [[NSMutableDictionary alloc] init];
    if (![mutator_keys objectForKey:name])
        [mutator_keys setObject:key forKey:name];
    UNLOCK();
    class_addMethod(kvo, sel, imp, method_getTypeEncoding(m));   /* does nothing if already there */
}

/* Makes the object's setters for key announce their changes. */
static void notify_automatically(id object, NSString *key)
{
    if (![key length] || object_isClass(object))
        return;   /* a class object keeps its own class */
    Class current = object_getClass(object);
    LOCK();
    Class known = original_of(current);
    UNLOCK();
    Class original = known ?: current;
    if (![original automaticallyNotifiesObserversForKey:key])
        return;
    Class kvo = kvo_class_for(original);
    if (!kvo)
        return;
    NSString *Key = [[[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]];
    for (NSString *prefix in @[ @"set", @"_set" ]) {
        NSString *name = [NSString stringWithFormat:@"%@%@:", prefix, Key];
        Method m = class_getInstanceMethod(original, NSSelectorFromString(name));
        if (m && method_getNumberOfArguments(m) == 3) {
            char t[256];
            method_getArgumentType(m, 2, t, sizeof t);
            add_mutator(kvo, original, name, key, setter_for_type(t));
        }
    }
    add_mutator(kvo, original, [NSString stringWithFormat:@"insertObject:in%@AtIndex:", Key], key, (IMP)insert_one);
    add_mutator(kvo, original, [NSString stringWithFormat:@"removeObjectFrom%@AtIndex:", Key], key, (IMP)remove_one);
    add_mutator(kvo, original, [NSString stringWithFormat:@"replaceObjectIn%@AtIndex:withObject:", Key], key,
                (IMP)replace_one);
    add_mutator(kvo, original, [NSString stringWithFormat:@"insert%@:atIndexes:", Key], key, (IMP)insert_many);
    add_mutator(kvo, original, [NSString stringWithFormat:@"remove%@AtIndexes:", Key], key, (IMP)remove_many);
    add_mutator(kvo, original, [NSString stringWithFormat:@"replace%@AtIndexes:with%@:", Key, Key], key,
                (IMP)replace_many);
    add_mutator(kvo, original, [NSString stringWithFormat:@"add%@Object:", Key], key, (IMP)set_union_one);
    add_mutator(kvo, original, [NSString stringWithFormat:@"remove%@Object:", Key], key, (IMP)set_minus_one);
    add_mutator(kvo, original, [NSString stringWithFormat:@"add%@:", Key], key, (IMP)set_union_many);
    add_mutator(kvo, original, [NSString stringWithFormat:@"remove%@:", Key], key, (IMP)set_minus_many);
    add_mutator(kvo, original, [NSString stringWithFormat:@"intersect%@:", Key], key, (IMP)set_intersect_many);
    if (!known)
        object_setClass(object, kvo);
}

/* ---- notifying -------------------------------------------------------------------------- */

static void notify(FKVOEntry *e, NSDictionary *change)
{
    if (!e->removed)
        [e->observer observeValueForKeyPath:e->keyPath ofObject:e->object change:change context:e->context];
}

static id or_null(id v) { return v ?: [NSNull null]; }

/* The value a collection change is about: the objects at the indexes. */
static id values_at(FKVOEntry *e, NSIndexSet *indexes)
{
    id all = [e->object valueForKey:e->firstKey];
    if (![all respondsToSelector:@selector(objectsAtIndexes:)])
        return nil;
    NSUInteger n = [all count];
    if ([indexes count] && [indexes lastIndex] >= n)
        return nil;
    return [all objectsAtIndexes:indexes];
}

/* Watches the rest of the key path on the first key's current value. */
static void entry_attach(FKVOEntry *e)
{
    if (!e->rest || e->removed)
        return;
    id subject = [e->object valueForKey:e->firstKey];
    if (!subject)
        return;
    if (([subject isKindOfClass:[NSArray class]] || [subject isKindOfClass:[NSSet class]]) &&
        ![subject respondsToSelector:@selector(_ferryObservesElements)])
        return;   /* to-many key paths aren't followed through a plain collection */
    if (!e->forwarder) {
        e->forwarder = [[FKVOForwarder alloc] init];
        e->forwarder->entry = e;
    }
    e->subject = [subject retain];
    [subject addObserver:e->forwarder forKeyPath:e->rest options:NSKeyValueObservingOptionPrior context:NULL];
}
static void entry_detach(FKVOEntry *e)
{
    if (!e->subject)
        return;
    id subject = e->subject;
    e->subject = nil;
    [subject removeObserver:e->forwarder forKeyPath:e->rest];
    [subject release];
}

/* Before a change: the old value is kept and the prior notification sent.
 * `first` says it is the first key that changes (not something along the
 * rest of the path), so the rest is watched on its new value after. */
static void entry_will(FKVOEntry *e, NSKeyValueChange kind, NSIndexSet *indexes, BOOL first)
{
    if (e->removed)
        return;
    if (e->rest || !first)
        kind = NSKeyValueChangeSetting, indexes = nil;
    id old = nil;
    if (e->options & NSKeyValueObservingOptionOld) {
        if (kind == NSKeyValueChangeSetting)
            old = [e->object valueForKeyPath:e->keyPath];
        else if (kind != NSKeyValueChangeInsertion)
            old = values_at(e, indexes);
    }
    if (!e->olds)
        e->olds = [[NSMutableArray alloc] init];
    [e->olds addObject:or_null(old)];
    if (first)
        entry_detach(e);
    if (e->options & NSKeyValueObservingOptionPrior) {
        NSMutableDictionary *change = [NSMutableDictionary dictionary];
        [change setObject:@(kind) forKey:NSKeyValueChangeKindKey];
        [change setObject:@YES forKey:NSKeyValueChangeNotificationIsPriorKey];
        if (indexes)
            [change setObject:indexes forKey:NSKeyValueChangeIndexesKey];
        if ((e->options & NSKeyValueObservingOptionOld) && (old || kind == NSKeyValueChangeSetting))
            [change setObject:or_null(old) forKey:NSKeyValueChangeOldKey];
        notify(e, change);
    }
}

static void entry_did(FKVOEntry *e, NSKeyValueChange kind, NSIndexSet *indexes, BOOL first)
{
    if (e->removed)
        return;
    if (e->rest || !first)
        kind = NSKeyValueChangeSetting, indexes = nil;
    id old = nil;
    BOOL hadOld = [e->olds count] > 0;
    if (hadOld) {
        old = [[[e->olds lastObject] retain] autorelease];
        [e->olds removeLastObject];
    }
    if (first) {
        entry_detach(e);
        entry_attach(e);
    }
    NSMutableDictionary *change = [NSMutableDictionary dictionary];
    [change setObject:@(kind) forKey:NSKeyValueChangeKindKey];
    if (indexes)
        [change setObject:indexes forKey:NSKeyValueChangeIndexesKey];
    if (e->options & NSKeyValueObservingOptionNew) {
        id v = nil;
        if (kind == NSKeyValueChangeSetting)
            v = or_null([e->object valueForKeyPath:e->keyPath]);
        else if (kind != NSKeyValueChangeRemoval)
            v = values_at(e, indexes);
        if (v)
            [change setObject:v forKey:NSKeyValueChangeNewKey];
    }
    if ((e->options & NSKeyValueObservingOptionOld) && hadOld &&
        (kind == NSKeyValueChangeSetting || old != [NSNull null]))
        [change setObject:old forKey:NSKeyValueChangeOldKey];
    notify(e, change);
}

/* A set mutation: what it adds and removes, worked out against the set as
 * it is before the change. */
static NSKeyValueChange set_change_kind(NSKeyValueSetMutationKind m)
{
    switch (m) {
    case NSKeyValueUnionSetMutation: return NSKeyValueChangeInsertion;
    case NSKeyValueMinusSetMutation:
    case NSKeyValueIntersectSetMutation: return NSKeyValueChangeRemoval;
    default: return NSKeyValueChangeReplacement;
    }
}
static void set_change_parts(id current, NSKeyValueSetMutationKind m, NSSet *objs, NSSet **added, NSSet **removed)
{
    NSMutableSet *add = [NSMutableSet set], *rem = [NSMutableSet set];
    BOOL isSet = [current isKindOfClass:[NSSet class]];
    switch (m) {
    case NSKeyValueUnionSetMutation:
        for (id o in objs)
            if (!isSet || ![current containsObject:o])
                [add addObject:o];
        break;
    case NSKeyValueMinusSetMutation:
        for (id o in objs)
            if (isSet && [current containsObject:o])
                [rem addObject:o];
        break;
    case NSKeyValueIntersectSetMutation:
        if (isSet)
            for (id o in current)
                if (![objs containsObject:o])
                    [rem addObject:o];
        break;
    default:
        if (isSet)
            for (id o in current)
                if (![objs containsObject:o])
                    [rem addObject:o];
        for (id o in objs)
            if (!isSet || ![current containsObject:o])
                [add addObject:o];
        break;
    }
    *added = add;
    *removed = rem;
}

static void entry_will_set(FKVOEntry *e, NSKeyValueSetMutationKind m, NSSet *objs)
{
    if (e->removed)
        return;
    if (e->rest) {
        entry_will(e, NSKeyValueChangeSetting, nil, YES);
        return;
    }
    NSKeyValueChange kind = set_change_kind(m);
    NSSet *added, *removed;
    set_change_parts([e->object valueForKey:e->firstKey], m, objs, &added, &removed);
    if (!e->olds)
        e->olds = [[NSMutableArray alloc] init];
    if (!e->news)
        e->news = [[NSMutableArray alloc] init];
    [e->olds addObject:removed];
    [e->news addObject:added];
    if (e->options & NSKeyValueObservingOptionPrior) {
        NSMutableDictionary *change = [NSMutableDictionary dictionary];
        [change setObject:@(kind) forKey:NSKeyValueChangeKindKey];
        [change setObject:@YES forKey:NSKeyValueChangeNotificationIsPriorKey];
        if ((e->options & NSKeyValueObservingOptionOld) && kind != NSKeyValueChangeInsertion)
            [change setObject:removed forKey:NSKeyValueChangeOldKey];
        notify(e, change);
    }
}

static void entry_did_set(FKVOEntry *e, NSKeyValueSetMutationKind m, NSSet *objs)
{
    if (e->removed)
        return;
    if (e->rest) {
        entry_did(e, NSKeyValueChangeSetting, nil, YES);
        return;
    }
    NSKeyValueChange kind = set_change_kind(m);
    NSSet *added = nil, *removed = nil;
    if ([e->olds count] && [e->news count]) {
        removed = [[[e->olds lastObject] retain] autorelease];
        added = [[[e->news lastObject] retain] autorelease];
        [e->olds removeLastObject];
        [e->news removeLastObject];
    }
    NSMutableDictionary *change = [NSMutableDictionary dictionary];
    [change setObject:@(kind) forKey:NSKeyValueChangeKindKey];
    if ((e->options & NSKeyValueObservingOptionOld) && removed && kind != NSKeyValueChangeInsertion)
        [change setObject:removed forKey:NSKeyValueChangeOldKey];
    if ((e->options & NSKeyValueObservingOptionNew) && added && kind != NSKeyValueChangeRemoval)
        [change setObject:added forKey:NSKeyValueChangeNewKey];
    notify(e, change);
}

@implementation FKVOForwarder
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    FKVOEntry *e = [[entry retain] autorelease];
    if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue])
        entry_will(e, NSKeyValueChangeSetting, nil, NO);
    else
        entry_did(e, NSKeyValueChangeSetting, nil, NO);
}
@end

/* ---- dependent keys --------------------------------------------------------------------- */

@implementation FKVODependency
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)o change:(NSDictionary *)change context:(void *)context
{
    if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue])
        [object willChangeValueForKey:key];
    else
        [object didChangeValueForKey:key];
}
- (void)dealloc
{
    [key release];
    [paths release];
    [super dealloc];
}
@end

static int dependency_depth;

/* An observer of key needs the key paths that affect it watched too: once
 * for all of key's observers. */
static void dependency_retain(id object, NSString *key)
{
    NSSet *affecting = [[object class] keyPathsForValuesAffectingValueForKey:key];
    if (![affecting count] || dependency_depth > 16)
        return;
    FKVOInfo *info = info_for(object, YES);
    LOCK();
    FKVODependency *d = [info->dependencies objectForKey:key];
    if (d) {
        d->count++;
        UNLOCK();
        return;
    }
    d = [[[FKVODependency alloc] init] autorelease];
    d->object = object;
    d->key = [key copy];
    d->count = 1;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *p in affecting)
        if (![p isEqualToString:key])
            [paths addObject:p];
    d->paths = [paths copy];
    [info->dependencies setObject:d forKey:key];
    UNLOCK();
    dependency_depth++;
    for (NSString *p in d->paths)
        [object addObserver:d forKeyPath:p options:NSKeyValueObservingOptionPrior context:NULL];
    d->observing = YES;
    dependency_depth--;
}

static void dependency_release(id object, NSString *key)
{
    FKVOInfo *info = objc_getAssociatedObject(object, &info_key);
    if (!info)
        return;
    LOCK();
    FKVODependency *d = [[[info->dependencies objectForKey:key] retain] autorelease];
    if (!d || --d->count > 0) {
        UNLOCK();
        return;
    }
    [info->dependencies removeObjectForKey:key];
    UNLOCK();
    if (d->observing)
        for (NSString *p in d->paths)
            [object removeObserver:d forKeyPath:p];
    d->observing = NO;
}

/* ---- registration ----------------------------------------------------------------------- */

@implementation NSObject (NSKeyValueObserverRegistration)
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options context:(void *)context
{
    if (!observer || !keyPath)
        return;
    FKVOEntry *e = [[[FKVOEntry alloc] init] autorelease];
    e->observer = observer;
    e->object = self;
    e->keyPath = [keyPath copy];
    NSRange dot = [keyPath rangeOfString:@"."];
    e->firstKey = [(dot.location == NSNotFound ? keyPath : [keyPath substringToIndex:dot.location]) copy];
    if (dot.location != NSNotFound)
        e->rest = [[keyPath substringFromIndex:dot.location + 1] copy];
    e->options = options;
    e->context = context;
    FKVOInfo *info = info_for(self, YES);
    LOCK();
    [info->entries addObject:e];
    UNLOCK();
    notify_automatically(self, e->firstKey);
    dependency_retain(self, e->firstKey);
    entry_attach(e);
    if (options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting)
                                                                         forKey:NSKeyValueChangeKindKey];
        if (options & NSKeyValueObservingOptionNew)
            [change setObject:or_null([self valueForKeyPath:keyPath]) forKey:NSKeyValueChangeNewKey];
        notify(e, change);
    }
}
- (void)_ferryRemoveObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath any:(BOOL)any context:(void *)context
{
    FKVOInfo *info = objc_getAssociatedObject(self, &info_key);
    FKVOEntry *found = nil;
    LOCK();
    /* the most recent matching registration, as on a Mac */
    for (NSInteger i = info ? (NSInteger)[info->entries count] - 1 : -1; i >= 0; i--) {
        FKVOEntry *e = [info->entries objectAtIndex:(NSUInteger)i];
        if (e->observer == observer && [e->keyPath isEqualToString:keyPath] && (any || e->context == context)) {
            found = [[e retain] autorelease];
            found->removed = YES;
            [info->entries removeObjectAtIndex:(NSUInteger)i];
            break;
        }
    }
    UNLOCK();
    if (!found)
        FRaise(NSRangeException, @"Cannot remove an observer <%@ %p> for the key path \"%@\" from <%@ %p> because it "
                                 @"is not registered as an observer.",
               [observer class], observer, keyPath, [self class], self);
    entry_detach(found);
    dependency_release(self, found->firstKey);
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

/* ---- announcing changes ----------------------------------------------------------------- */

@implementation NSObject (NSKeyValueObserving)
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    /* A Mac raises here, for an observer that didn't handle its own
     * registration; Ferry lets it pass. */
}
- (void)willChangeValueForKey:(NSString *)key
{
    for (FKVOEntry *e in entries_for(self, key))
        entry_will(e, NSKeyValueChangeSetting, nil, YES);
}
- (void)didChangeValueForKey:(NSString *)key
{
    for (FKVOEntry *e in entries_for(self, key))
        entry_did(e, NSKeyValueChangeSetting, nil, YES);
}
- (void)willChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    for (FKVOEntry *e in entries_for(self, key))
        entry_will(e, kind, indexes, YES);
}
- (void)didChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    for (FKVOEntry *e in entries_for(self, key))
        entry_did(e, kind, indexes, YES);
}
- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutation
                 usingObjects:(NSSet *)objects
{
    for (FKVOEntry *e in entries_for(self, key))
        entry_will_set(e, mutation, objects);
}
- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutation
                usingObjects:(NSSet *)objects
{
    for (FKVOEntry *e in entries_for(self, key))
        entry_did_set(e, mutation, objects);
}

/* automaticallyNotifiesObserversOf<Key>, if the class has it; else YES. */
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key length]) {
        NSString *name = [NSString stringWithFormat:@"automaticallyNotifiesObserversOf%@%@",
                                                    [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        SEL sel = NSSelectorFromString(name);
        if ([self respondsToSelector:sel])
            return ((BOOL (*)(id, SEL))objc_msgSend)(self, sel);
    }
    return YES;
}
/* keyPathsForValuesAffecting<Key>, if the class has it; else none. */
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    if ([key length]) {
        NSString *name = [NSString stringWithFormat:@"keyPathsForValuesAffecting%@%@",
                                                    [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        SEL sel = NSSelectorFromString(name);
        if ([self respondsToSelector:sel]) {
            id set = ((id (*)(id, SEL))objc_msgSend)(self, sel);
            if ([set isKindOfClass:[NSSet class]])
                return set;
        }
    }
    return [NSSet set];
}
- (void *)observationInfo { return objc_getAssociatedObject(self, &info_key); }
- (void)setObservationInfo:(void *)info {}
@end
