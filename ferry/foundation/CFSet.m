/* SPDX-License-Identifier: GPL-3.0-or-later
 * CoreFoundation's sets and bags (freemac 1.220, Ferry 0.44.0), written for
 * freemac from Apple's public documentation of CFSet and CFBag.
 *
 * As in CFMore.m, a CF object is a Foundation object: a set made with the
 * CFType callbacks is an NSSet or NSMutableSet. A set made with other
 * callbacks, or with none (plain pointers, equal only to themselves), is an
 * FCFSet, a subclass of NSMutableSet that keeps its values in a hash table
 * of its own and calls the callbacks to retain, release, compare, hash and
 * describe them; the CF calls work on it, and so do the NS calls that don't
 * treat its values as objects. A bag, which has no Foundation counterpart,
 * is an FCFBag on the same table, each value held with a count: adding a
 * value again counts it again, removing it takes one away, and the bag's
 * count, its values and the applier go through every value as many times
 * as it is held. */
#import "FInternal.h"

#define OBJ(x) ((id)(x))
#define FERRY_TYPE_SET 0x46520015
#define FERRY_TYPE_BAG 0x46520016

static const void *cftype_retain(CFAllocatorRef a, const void *v) { return v ? CFRetain(v) : v; }
static void cftype_release(CFAllocatorRef a, const void *v)
{
    if (v)
        CFRelease(v);
}
static const void *copy_string(CFAllocatorRef a, const void *v) { return [OBJ(v) copy]; }
static Boolean cftype_equal(const void *a, const void *b) { return CFEqual(a, b); }
static CFHashCode cftype_hash(const void *v) { return CFHash(v); }

const CFSetCallBacks kCFTypeSetCallBacks = {0, cftype_retain, cftype_release, CFCopyDescription, cftype_equal,
                                            cftype_hash};
const CFSetCallBacks kCFCopyStringSetCallBacks = {0, copy_string, cftype_release, CFCopyDescription, cftype_equal,
                                                  cftype_hash};
const CFBagCallBacks kCFTypeBagCallBacks = {0, cftype_retain, cftype_release, CFCopyDescription, cftype_equal,
                                            cftype_hash};
const CFBagCallBacks kCFCopyStringBagCallBacks = {0, copy_string, cftype_release, CFCopyDescription, cftype_equal,
                                                  cftype_hash};

CFTypeID CFSetGetTypeID(void) { return FERRY_TYPE_SET; }
CFTypeID CFBagGetTypeID(void) { return FERRY_TYPE_BAG; }
@implementation NSSet (FerryCFType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SET; }
@end

/* ---- the table both keep their values in ---------------------------------------------- */

typedef struct FCFSlot {
    const void *value;
    CFHashCode hash;
    CFIndex count;
    struct FCFSlot *next;
} FCFSlot;

typedef struct {
    CFSetCallBacks cb;
    FCFSlot **buckets;
    NSUInteger nbuckets, n;   /* n: distinct values */
    CFIndex total;            /* every value, as many times as held */
    unsigned long mutations;
} FCFTable;

static void table_init(FCFTable *t, const CFSetCallBacks *cb)
{
    memset(t, 0, sizeof *t);
    if (cb)
        t->cb = *cb;
    t->nbuckets = 16;
    t->buckets = calloc(t->nbuckets, sizeof(FCFSlot *));
}
static CFHashCode table_hash(FCFTable *t, const void *v) { return t->cb.hash ? t->cb.hash(v) : (CFHashCode)v; }
static FCFSlot **table_find(FCFTable *t, const void *v)
{
    CFHashCode h = table_hash(t, v);
    FCFSlot **p = &t->buckets[h & (t->nbuckets - 1)];
    for (; *p; p = &(*p)->next)
        if ((*p)->hash == h && ((*p)->value == v || (t->cb.equal && t->cb.equal((*p)->value, v))))
            return p;
    return p;
}
static void table_clear(FCFTable *t)
{
    for (NSUInteger b = 0; b < t->nbuckets; b++) {
        for (FCFSlot *s = t->buckets[b], *next; s; s = next) {
            next = s->next;
            if (t->cb.release)
                t->cb.release(NULL, s->value);
            free(s);
        }
        t->buckets[b] = NULL;
    }
    t->n = 0;
    t->total = 0;
    t->mutations++;
}
static void table_free(FCFTable *t)
{
    table_clear(t);
    free(t->buckets);
}
static void table_grow(FCFTable *t)
{
    if (t->n <= t->nbuckets)
        return;
    NSUInteger nb = t->nbuckets * 4;
    FCFSlot **buckets = calloc(nb, sizeof(FCFSlot *));
    for (NSUInteger b = 0; b < t->nbuckets; b++)
        for (FCFSlot *s = t->buckets[b], *next; s; s = next) {
            next = s->next;
            s->next = buckets[s->hash & (nb - 1)];
            buckets[s->hash & (nb - 1)] = s;
        }
    free(t->buckets);
    t->buckets = buckets;
    t->nbuckets = nb;
}
/* how: 0 adds (a set keeps the value it has, a bag counts it again),
 * 1 replaces a value it has, 2 replaces or adds */
static void table_put(FCFTable *t, const void *v, int how, BOOL counts)
{
    FCFSlot **p = table_find(t, v);
    if (*p) {
        if (how == 0) {
            if (counts) {
                (*p)->count++;
                t->total++;
                t->mutations++;
            }
            return;
        }
        const void *old = (*p)->value;
        (*p)->value = t->cb.retain ? t->cb.retain(NULL, v) : v;
        if (t->cb.release)
            t->cb.release(NULL, old);
        t->mutations++;
        return;
    }
    if (how == 1)
        return;
    FCFSlot *s = malloc(sizeof *s);
    s->value = t->cb.retain ? t->cb.retain(NULL, v) : v;
    s->hash = table_hash(t, v);
    s->count = 1;
    s->next = NULL;
    *p = s;
    t->n++;
    t->total++;
    t->mutations++;
    table_grow(t);
}
static void table_remove(FCFTable *t, const void *v, BOOL once)
{
    FCFSlot **p = table_find(t, v), *s = *p;
    if (!s)
        return;
    t->mutations++;
    if (once && s->count > 1) {
        s->count--;
        t->total--;
        return;
    }
    *p = s->next;
    t->n--;
    t->total -= s->count;
    if (t->cb.release)
        t->cb.release(NULL, s->value);
    free(s);
}
/* Each value once, or (counts) as many times as it is held. */
static void table_values(FCFTable *t, const void **out, BOOL counts)
{
    NSUInteger k = 0;
    for (NSUInteger b = 0; b < t->nbuckets; b++)
        for (FCFSlot *s = t->buckets[b]; s; s = s->next)
            for (CFIndex c = counts ? s->count : 1; c > 0; c--)
                out[k++] = s->value;
}
static NSUInteger table_enumerate(FCFTable *t, NSFastEnumerationState *state, id *buffer, NSUInteger len)
{
    /* state->state: the bucket, extra[0]: how far into its chain */
    NSUInteger k = 0;
    state->itemsPtr = buffer;
    state->mutationsPtr = &t->mutations;
    while (k < len && state->state < t->nbuckets) {
        FCFSlot *s = t->buckets[state->state];
        for (unsigned long skip = state->extra[0]; s && skip; skip--)
            s = s->next;
        while (s && k < len) {
            buffer[k++] = (id)s->value;
            state->extra[0]++;
            s = s->next;
        }
        if (!s) {
            state->state++;
            state->extra[0] = 0;
        }
    }
    return k;
}
static NSString *describe_value(FCFTable *t, const void *v)
{
    if (t->cb.copyDescription) {
        CFStringRef d = t->cb.copyDescription(v);
        if (d)
            return [(NSString *)d autorelease];
    }
    return [NSString stringWithFormat:@"<%p>", v];
}
static NSString *describe(id self, FCFTable *t, BOOL counts)
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<%@ %p [%lu]>{", NSStringFromClass([self class]),
                                                           (void *)self, (unsigned long)t->n];
    BOOL first = YES;
    for (NSUInteger b = 0; b < t->nbuckets; b++)
        for (FCFSlot *x = t->buckets[b]; x; x = x->next) {
            [s appendString:first ? @"\n\t" : @",\n\t"];
            [s appendString:describe_value(t, x->value)];
            if (counts && x->count > 1)
                [s appendFormat:@" (%ld)", (long)x->count];
            first = NO;
        }
    [s appendString:first ? @"}" : @"\n}"];
    return s;
}

/* ---- sets with callbacks ------------------------------------------------------------------ */

@interface FCFSet : NSMutableSet {
@public
    FCFTable _t;
}
- (instancetype)initWithCallBacks:(const CFSetCallBacks *)cb;
@end

@implementation FCFSet
+ (instancetype)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
- (instancetype)initWithCallBacks:(const CFSetCallBacks *)cb
{
    table_init(&_t, cb);
    return self;
}
- (instancetype)init { return [self initWithCallBacks:NULL]; }
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count
{
    [self initWithCallBacks:&kCFTypeSetCallBacks];
    for (NSUInteger i = 0; i < count; i++)
        table_put(&_t, objects[i], 0, NO);
    return self;
}
- (void)dealloc
{
    table_free(&_t);
    [super dealloc];
}
- (NSUInteger)count { return _t.n; }
- (id)member:(id)obj
{
    FCFSlot *s = *table_find(&_t, obj);
    return s ? (id)s->value : nil;
}
- (void)addObject:(id)obj { table_put(&_t, obj, 0, NO); }
- (void)removeObject:(id)obj { table_remove(&_t, obj, NO); }
- (void)removeAllObjects { table_clear(&_t); }
- (NSArray *)allObjects
{
    CFArrayCallBacks cb = {0, _t.cb.retain == copy_string ? cftype_retain : _t.cb.retain, _t.cb.release,
                           _t.cb.copyDescription, _t.cb.equal};
    const void **values = malloc((_t.n + 1) * sizeof(void *));
    table_values(&_t, values, NO);
    CFArrayRef a = CFArrayCreate(NULL, values, (CFIndex)_t.n, &cb);
    free(values);
    return [(NSArray *)a autorelease];
}
- (FCFSet *)_ferryCFCopy
{
    FCFSet *c = [[FCFSet alloc] initWithCallBacks:&_t.cb];
    for (NSUInteger b = 0; b < _t.nbuckets; b++)
        for (FCFSlot *s = _t.buckets[b]; s; s = s->next)
            table_put(&c->_t, s->value, 0, NO);
    return c;
}
- (id)copyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    return table_enumerate(&_t, state, buffer, len);
}
- (NSUInteger)hash { return _t.n; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSSet class]] || [other count] != _t.n)
        return NO;
    for (id v in other)
        if (!*table_find(&_t, v))
            return NO;
    return YES;
}
- (NSString *)description { return describe(self, &_t, NO); }
@end

static BOOL is_cftype_set(const CFSetCallBacks *cb)
{
    return cb == &kCFTypeSetCallBacks ||
           (cb && cb->retain == cftype_retain && cb->release == cftype_release && cb->equal == cftype_equal &&
            cb->hash == cftype_hash);
}
static BOOL is_fcf_set(id s) { return [s isKindOfClass:[FCFSet class]]; }

CFSetRef CFSetCreate(CFAllocatorRef alloc, const void **values, CFIndex count, const CFSetCallBacks *cb)
{
    if (is_cftype_set(cb))
        return (CFSetRef)[[NSSet alloc] initWithObjects:(const id *)values count:(NSUInteger)count];
    FCFSet *s = [[FCFSet alloc] initWithCallBacks:cb];
    for (CFIndex i = 0; i < count; i++)
        table_put(&s->_t, values[i], 0, NO);
    return (CFSetRef)s;
}
CFMutableSetRef CFSetCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const CFSetCallBacks *cb)
{
    if (is_cftype_set(cb))
        return (CFMutableSetRef)[[NSMutableSet alloc] init];
    return (CFMutableSetRef)[[FCFSet alloc] initWithCallBacks:cb];
}
CFSetRef CFSetCreateCopy(CFAllocatorRef alloc, CFSetRef set) { return (CFSetRef)[OBJ(set) copy]; }
CFMutableSetRef CFSetCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFSetRef set)
{
    return (CFMutableSetRef)[OBJ(set) mutableCopy];
}
CFIndex CFSetGetCount(CFSetRef set) { return (CFIndex)[OBJ(set) count]; }
Boolean CFSetGetValueIfPresent(CFSetRef set, const void *candidate, const void **value)
{
    id found;
    if (is_fcf_set(OBJ(set))) {
        FCFSlot *s = *table_find(&((FCFSet *)OBJ(set))->_t, candidate);
        if (!s)
            return false;
        found = (id)s->value;
    } else {
        found = candidate ? [OBJ(set) member:OBJ(candidate)] : nil;
        if (!found)
            return false;
    }
    if (value)
        *value = found;
    return true;
}
Boolean CFSetContainsValue(CFSetRef set, const void *value) { return CFSetGetValueIfPresent(set, value, NULL); }
CFIndex CFSetGetCountOfValue(CFSetRef set, const void *value) { return CFSetContainsValue(set, value) ? 1 : 0; }
const void *CFSetGetValue(CFSetRef set, const void *value)
{
    const void *v = NULL;
    return CFSetGetValueIfPresent(set, value, &v) ? v : NULL;
}
void CFSetGetValues(CFSetRef set, const void **values)
{
    if (is_fcf_set(OBJ(set))) {
        table_values(&((FCFSet *)OBJ(set))->_t, values, NO);
        return;
    }
    NSUInteger k = 0;
    for (id v in OBJ(set))
        values[k++] = v;
}
void CFSetApplyFunction(CFSetRef set, CFSetApplierFunction applier, void *context)
{
    CFIndex n = CFSetGetCount(set);
    const void **values = malloc((size_t)(n + 1) * sizeof(void *));
    CFSetGetValues(set, values);
    for (CFIndex i = 0; i < n; i++)
        applier(values[i], context);
    free(values);
}
static void set_put(CFMutableSetRef set, const void *value, int how)
{
    if (is_fcf_set(OBJ(set))) {
        table_put(&((FCFSet *)OBJ(set))->_t, value, how, NO);
        return;
    }
    if (!value)
        return;
    BOOL has = [OBJ(set) member:OBJ(value)] != nil;
    if (has && how == 0)
        return;
    if (!has && how == 1)
        return;
    id keep = [OBJ(value) retain];
    if (has)
        [OBJ(set) removeObject:keep];
    [OBJ(set) addObject:keep];
    [keep release];
}
void CFSetAddValue(CFMutableSetRef set, const void *value) { set_put(set, value, 0); }
void CFSetReplaceValue(CFMutableSetRef set, const void *value) { set_put(set, value, 1); }
void CFSetSetValue(CFMutableSetRef set, const void *value) { set_put(set, value, 2); }
void CFSetRemoveValue(CFMutableSetRef set, const void *value)
{
    if (is_fcf_set(OBJ(set)))
        table_remove(&((FCFSet *)OBJ(set))->_t, value, NO);
    else if (value)
        [OBJ(set) removeObject:OBJ(value)];
}
void CFSetRemoveAllValues(CFMutableSetRef set) { [OBJ(set) removeAllObjects]; }

/* ---- bags ------------------------------------------------------------------------------- */

@interface FCFBag : NSObject <NSCopying, NSMutableCopying> {
@public
    FCFTable _t;
}
- (instancetype)initWithCallBacks:(const CFBagCallBacks *)cb;
@end

@implementation FCFBag
- (instancetype)initWithCallBacks:(const CFBagCallBacks *)cb
{
    if ((self = [super init]))
        table_init(&_t, (const CFSetCallBacks *)cb);
    return self;
}
- (void)dealloc
{
    table_free(&_t);
    [super dealloc];
}
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_BAG; }
- (FCFBag *)_ferryCFCopy
{
    FCFBag *c = [[FCFBag alloc] initWithCallBacks:(const CFBagCallBacks *)&_t.cb];
    for (NSUInteger b = 0; b < _t.nbuckets; b++)
        for (FCFSlot *s = _t.buckets[b]; s; s = s->next)
            for (CFIndex k = 0; k < s->count; k++)
                table_put(&c->_t, s->value, 0, YES);
    return c;
}
- (id)copyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (NSUInteger)hash { return (NSUInteger)_t.total; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[FCFBag class]])
        return NO;
    FCFBag *o = other;
    if (o->_t.n != _t.n || o->_t.total != _t.total)
        return NO;
    for (NSUInteger b = 0; b < _t.nbuckets; b++)
        for (FCFSlot *s = _t.buckets[b]; s; s = s->next) {
            FCFSlot *t = *table_find(&o->_t, s->value);
            if (!t || t->count != s->count)
                return NO;
        }
    return YES;
}
- (NSString *)description { return describe(self, &_t, YES); }
@end

#define BAG(b) (&((FCFBag *)OBJ(b))->_t)

CFBagRef CFBagCreate(CFAllocatorRef alloc, const void **values, CFIndex count, const CFBagCallBacks *cb)
{
    FCFBag *b = [[FCFBag alloc] initWithCallBacks:cb];
    for (CFIndex i = 0; i < count; i++)
        table_put(&b->_t, values[i], 0, YES);
    return (CFBagRef)b;
}
CFMutableBagRef CFBagCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const CFBagCallBacks *cb)
{
    return (CFMutableBagRef)[[FCFBag alloc] initWithCallBacks:cb];
}
CFBagRef CFBagCreateCopy(CFAllocatorRef alloc, CFBagRef bag) { return (CFBagRef)[OBJ(bag) copy]; }
CFMutableBagRef CFBagCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFBagRef bag)
{
    return (CFMutableBagRef)[OBJ(bag) mutableCopy];
}
CFIndex CFBagGetCount(CFBagRef bag) { return BAG(bag)->total; }
CFIndex CFBagGetCountOfValue(CFBagRef bag, const void *value)
{
    FCFSlot *s = *table_find(BAG(bag), value);
    return s ? s->count : 0;
}
Boolean CFBagContainsValue(CFBagRef bag, const void *value) { return *table_find(BAG(bag), value) != NULL; }
Boolean CFBagGetValueIfPresent(CFBagRef bag, const void *candidate, const void **value)
{
    FCFSlot *s = *table_find(BAG(bag), candidate);
    if (s && value)
        *value = s->value;
    return s != NULL;
}
const void *CFBagGetValue(CFBagRef bag, const void *value)
{
    const void *v = NULL;
    return CFBagGetValueIfPresent(bag, value, &v) ? v : NULL;
}
void CFBagGetValues(CFBagRef bag, const void **values) { table_values(BAG(bag), values, YES); }
void CFBagApplyFunction(CFBagRef bag, CFBagApplierFunction applier, void *context)
{
    CFIndex n = BAG(bag)->total;
    const void **values = malloc((size_t)(n + 1) * sizeof(void *));
    table_values(BAG(bag), values, YES);
    for (CFIndex i = 0; i < n; i++)
        applier(values[i], context);
    free(values);
}
void CFBagAddValue(CFMutableBagRef bag, const void *value) { table_put(BAG(bag), value, 0, YES); }
void CFBagReplaceValue(CFMutableBagRef bag, const void *value) { table_put(BAG(bag), value, 1, YES); }
void CFBagSetValue(CFMutableBagRef bag, const void *value) { table_put(BAG(bag), value, 2, YES); }
void CFBagRemoveValue(CFMutableBagRef bag, const void *value) { table_remove(BAG(bag), value, YES); }
void CFBagRemoveAllValues(CFMutableBagRef bag) { table_clear(BAG(bag)); }
