/* SPDX-License-Identifier: GPL-3.0-or-later
 * More of CoreFoundation (freemac 1.219, Ferry 0.43.0): arrays and
 * dictionaries with callbacks, the rest of the CFString calls apps make,
 * CFUUID, CFURL, the bundle keys and a few constants. Written for freemac
 * from Apple's public documentation of CFArray, CFDictionary, CFString,
 * CFUUID, CFURL and CFBundle.
 *
 * As in CoreFoundation.m, a CF object is the Foundation object: a CFArray
 * made with the CFType callbacks is an NSMutableArray, a CFUUID an NSUUID,
 * a CFURL an NSURL. An array or dictionary made with other callbacks (or
 * none, holding plain pointers) is an FCFArray or FCFDictionary, subclasses
 * of NSMutableArray and NSMutableDictionary that call the callbacks and hold
 * values that may not be objects: the CF calls work on them, and so do the
 * NS calls that don't treat their values as objects. */
#import "FInternal.h"

#define OBJ(x) ((id)(x))

const double kCFCoreFoundationVersionNumber = 2000.0; /* above every macOS 10 release's number */
CFTypeRef CFMakeCollectable(CFTypeRef cf) { return cf; }

static const void *cftype_retain(CFAllocatorRef a, const void *v) { return v ? CFRetain(v) : v; }
static void cftype_release(CFAllocatorRef a, const void *v)
{
    if (v)
        CFRelease(v);
}
static const void *copy_string(CFAllocatorRef a, const void *v) { return [OBJ(v) copy]; }
static Boolean cftype_equal(const void *a, const void *b) { return CFEqual(a, b); }
static CFHashCode cftype_hash(const void *v) { return CFHash(v); }

const CFArrayCallBacks kCFTypeArrayCallBacks = {0, cftype_retain, cftype_release, CFCopyDescription, cftype_equal};
const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks = {0, cftype_retain, cftype_release, CFCopyDescription,
                                                                cftype_equal, cftype_hash};
const CFDictionaryKeyCallBacks kCFCopyStringDictionaryKeyCallBacks = {0, copy_string, cftype_release,
                                                                      CFCopyDescription, cftype_equal, cftype_hash};
const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks = {0, cftype_retain, cftype_release,
                                                                    CFCopyDescription, cftype_equal};

/* The type identifiers (CFGetTypeID asks _ferryCFTypeID) */
#define FERRY_TYPE_ARRAY 0x46520010
#define FERRY_TYPE_DICTIONARY 0x46520011
#define FERRY_TYPE_STRING 0x46520012
#define FERRY_TYPE_URL 0x46520013
#define FERRY_TYPE_UUID 0x46520014
CFTypeID CFArrayGetTypeID(void) { return FERRY_TYPE_ARRAY; }
CFTypeID CFDictionaryGetTypeID(void) { return FERRY_TYPE_DICTIONARY; }
CFTypeID CFStringGetTypeID(void) { return FERRY_TYPE_STRING; }
CFTypeID CFURLGetTypeID(void) { return FERRY_TYPE_URL; }
CFTypeID CFUUIDGetTypeID(void) { return FERRY_TYPE_UUID; }
@implementation NSArray (FerryCFType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_ARRAY; }
@end
@implementation NSDictionary (FerryCFType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_DICTIONARY; }
@end
@implementation NSString (FerryCFType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_STRING; }
@end
@implementation NSURL (FerryCFType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_URL; }
@end
@implementation NSUUID (FerryCFType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_UUID; }
@end

/* ---- arrays with callbacks --------------------------------------------------------------- */

@interface FCFArray : NSMutableArray {
@public
    const void **_v;
    NSUInteger _n, _cap;
    CFArrayCallBacks _cb;
}
@end

@implementation FCFArray
+ (instancetype)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
- (instancetype)initWithCallBacks:(const CFArrayCallBacks *)cb
{
    if ((self = [super init]) && cb)
        _cb = *cb;
    return self;
}
- (void)dealloc
{
    for (NSUInteger i = 0; i < _n; i++)
        if (_cb.release)
            _cb.release(NULL, _v[i]);
    free(_v);
    [super dealloc];
}
- (NSUInteger)count { return _n; }
- (id)objectAtIndex:(NSUInteger)i
{
    if (i >= _n)
        FRaise(NSRangeException, @"-[__NSCFArray objectAtIndex:]: index %lu beyond bounds [0 .. %ld]",
               (unsigned long)i, (long)_n - 1);
    return (id)_v[i];
}
- (void)insertObject:(id)obj atIndex:(NSUInteger)i
{
    if (i > _n)
        FRaise(NSRangeException, @"-[__NSCFArray insertObject:atIndex:]: index %lu beyond bounds [0 .. %lu]",
               (unsigned long)i, (unsigned long)_n);
    if (_n == _cap)
        _v = realloc(_v, (_cap = _cap ? _cap * 2 : 8) * sizeof(void *));
    memmove(_v + i + 1, _v + i, (_n - i) * sizeof(void *));
    _v[i] = _cb.retain ? _cb.retain(NULL, obj) : (const void *)obj;
    _n++;
}
- (void)removeObjectAtIndex:(NSUInteger)i
{
    if (i >= _n)
        FRaise(NSRangeException, @"-[__NSCFArray removeObjectAtIndex:]: index %lu beyond bounds [0 .. %ld]",
               (unsigned long)i, (long)_n - 1);
    const void *old = _v[i];
    memmove(_v + i, _v + i + 1, (_n - i - 1) * sizeof(void *));
    _n--;
    if (_cb.release)
        _cb.release(NULL, old);
}
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(id)obj
{
    if (i >= _n)
        FRaise(NSRangeException, @"-[__NSCFArray replaceObjectAtIndex:withObject:]: index %lu beyond bounds",
               (unsigned long)i);
    const void *old = _v[i];
    _v[i] = _cb.retain ? _cb.retain(NULL, obj) : (const void *)obj;
    if (_cb.release)
        _cb.release(NULL, old);
}
- (void)addObject:(id)obj { [self insertObject:obj atIndex:_n]; }
- (void)removeLastObject
{
    if (_n)
        [self removeObjectAtIndex:_n - 1];
}
- (void)removeAllObjects
{
    while (_n)
        [self removeObjectAtIndex:_n - 1];
}
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b
{
    if (a >= _n || b >= _n)
        FRaise(NSRangeException, @"-[__NSCFArray exchangeObjectAtIndex:withObjectAtIndex:]: index beyond bounds");
    const void *t = _v[a];
    _v[a] = _v[b];
    _v[b] = t;
}
- (FCFArray *)_ferryCFCopy
{
    FCFArray *c = [[FCFArray alloc] initWithCallBacks:&_cb];
    for (NSUInteger i = 0; i < _n; i++)
        [c insertObject:(id)_v[i] atIndex:i];
    return c;
}
- (id)copyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    if (state->state >= _n)
        return 0;
    state->itemsPtr = (id *)_v + state->state;
    state->mutationsPtr = (unsigned long *)&_v;
    NSUInteger n = _n - state->state;
    state->state = _n;
    return n;
}
@end

static BOOL is_cftype_array(const CFArrayCallBacks *cb)
{
    return cb == &kCFTypeArrayCallBacks ||
           (cb && cb->retain == kCFTypeArrayCallBacks.retain && cb->release == kCFTypeArrayCallBacks.release &&
            cb->equal == kCFTypeArrayCallBacks.equal);
}
static Boolean array_equal(id a, const void *x, const void *y)
{
    if ([a isKindOfClass:[FCFArray class]]) {
        FCFArray *f = a;
        return f->_cb.equal ? f->_cb.equal(x, y) : x == y;
    }
    return x == y || (x && y && CFEqual(x, y));
}

CFArrayRef CFArrayCreate(CFAllocatorRef alloc, const void **values, CFIndex count, const CFArrayCallBacks *cb)
{
    if (is_cftype_array(cb))
        return (CFArrayRef)[[NSArray alloc] initWithObjects:(id *)values count:(NSUInteger)count];
    FCFArray *a = [[FCFArray alloc] initWithCallBacks:cb];
    for (CFIndex i = 0; i < count; i++)
        [a insertObject:(id)values[i] atIndex:(NSUInteger)i];
    return (CFArrayRef)a;
}
CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const CFArrayCallBacks *cb)
{
    if (is_cftype_array(cb))
        return (CFMutableArrayRef)[[NSMutableArray alloc] init];
    return (CFMutableArrayRef)[[FCFArray alloc] initWithCallBacks:cb];
}
CFArrayRef CFArrayCreateCopy(CFAllocatorRef alloc, CFArrayRef array) { return (CFArrayRef)[OBJ(array) copy]; }
CFMutableArrayRef CFArrayCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFArrayRef array)
{
    return (CFMutableArrayRef)[OBJ(array) mutableCopy];
}
CFIndex CFArrayGetCount(CFArrayRef a) { return (CFIndex)[OBJ(a) count]; }
const void *CFArrayGetValueAtIndex(CFArrayRef a, CFIndex i) { return [OBJ(a) objectAtIndex:(NSUInteger)i]; }
void CFArrayAppendValue(CFMutableArrayRef a, const void *value) { [OBJ(a) addObject:OBJ(value)]; }
void CFArrayGetValues(CFArrayRef a, CFRange r, const void **values)
{
    for (CFIndex i = 0; i < r.length; i++)
        values[i] = [OBJ(a) objectAtIndex:(NSUInteger)(r.location + i)];
}
CFIndex CFArrayGetCountOfValue(CFArrayRef a, CFRange r, const void *value)
{
    CFIndex n = 0;
    for (CFIndex i = r.location; i < r.location + r.length; i++)
        if (array_equal(OBJ(a), [OBJ(a) objectAtIndex:(NSUInteger)i], value))
            n++;
    return n;
}
CFIndex CFArrayGetFirstIndexOfValue(CFArrayRef a, CFRange r, const void *value)
{
    for (CFIndex i = r.location; i < r.location + r.length; i++)
        if (array_equal(OBJ(a), [OBJ(a) objectAtIndex:(NSUInteger)i], value))
            return i;
    return kCFNotFound;
}
CFIndex CFArrayGetLastIndexOfValue(CFArrayRef a, CFRange r, const void *value)
{
    for (CFIndex i = r.location + r.length - 1; i >= r.location; i--)
        if (array_equal(OBJ(a), [OBJ(a) objectAtIndex:(NSUInteger)i], value))
            return i;
    return kCFNotFound;
}
Boolean CFArrayContainsValue(CFArrayRef a, CFRange r, const void *value)
{
    return CFArrayGetFirstIndexOfValue(a, r, value) != kCFNotFound;
}
void CFArrayApplyFunction(CFArrayRef a, CFRange r, CFArrayApplierFunction applier, void *context)
{
    for (CFIndex i = r.location; i < r.location + r.length; i++)
        applier([OBJ(a) objectAtIndex:(NSUInteger)i], context);
}
/* Where value is, or where it would go to keep the range sorted. */
CFIndex CFArrayBSearchValues(CFArrayRef a, CFRange r, const void *value, CFComparatorFunction cmp, void *context)
{
    CFIndex lo = r.location, hi = r.location + r.length;
    while (lo < hi) {
        CFIndex mid = lo + (hi - lo) / 2;
        if (cmp([OBJ(a) objectAtIndex:(NSUInteger)mid], value, context) == kCFCompareLessThan)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}
void CFArraySetValueAtIndex(CFMutableArrayRef a, CFIndex i, const void *value)
{
    if ((NSUInteger)i == [OBJ(a) count])
        [OBJ(a) insertObject:OBJ(value) atIndex:(NSUInteger)i];
    else
        [OBJ(a) replaceObjectAtIndex:(NSUInteger)i withObject:OBJ(value)];
}
void CFArrayInsertValueAtIndex(CFMutableArrayRef a, CFIndex i, const void *value)
{
    [OBJ(a) insertObject:OBJ(value) atIndex:(NSUInteger)i];
}
void CFArrayRemoveValueAtIndex(CFMutableArrayRef a, CFIndex i) { [OBJ(a) removeObjectAtIndex:(NSUInteger)i]; }
void CFArrayRemoveAllValues(CFMutableArrayRef a) { [OBJ(a) removeAllObjects]; }
void CFArrayReplaceValues(CFMutableArrayRef a, CFRange r, const void **values, CFIndex n)
{
    for (CFIndex i = 0; i < r.length; i++)
        [OBJ(a) removeObjectAtIndex:(NSUInteger)r.location];
    for (CFIndex i = 0; i < n; i++)
        [OBJ(a) insertObject:OBJ(values[i]) atIndex:(NSUInteger)(r.location + i)];
}
void CFArrayAppendArray(CFMutableArrayRef a, CFArrayRef other, CFRange r)
{
    for (CFIndex i = r.location; i < r.location + r.length; i++)
        [OBJ(a) addObject:[OBJ(other) objectAtIndex:(NSUInteger)i]];
}
void CFArrayExchangeValuesAtIndices(CFMutableArrayRef a, CFIndex i, CFIndex j)
{
    [OBJ(a) exchangeObjectAtIndex:(NSUInteger)i withObjectAtIndex:(NSUInteger)j];
}
/* A stable merge sort of the range by the comparator. */
static void merge_sort(const void **v, const void **tmp, CFIndex n, CFComparatorFunction cmp, void *ctx)
{
    if (n < 2)
        return;
    CFIndex h = n / 2;
    merge_sort(v, tmp, h, cmp, ctx);
    merge_sort(v + h, tmp, n - h, cmp, ctx);
    CFIndex i = 0, j = h, k = 0;
    while (i < h && j < n)
        tmp[k++] = cmp(v[j], v[i], ctx) == kCFCompareLessThan ? v[j++] : v[i++];
    while (i < h)
        tmp[k++] = v[i++];
    while (j < n)
        tmp[k++] = v[j++];
    memcpy(v, tmp, (size_t)n * sizeof(void *));
}
void CFArraySortValues(CFMutableArrayRef a, CFRange r, CFComparatorFunction cmp, void *context)
{
    if (r.length < 2)
        return;
    const void **v = malloc((size_t)r.length * sizeof(void *)), **tmp = malloc((size_t)r.length * sizeof(void *));
    CFArrayGetValues(a, r, v);
    merge_sort(v, tmp, r.length, cmp, context);
    if ([OBJ(a) isKindOfClass:[FCFArray class]]) {
        memcpy(((FCFArray *)OBJ(a))->_v + r.location, v, (size_t)r.length * sizeof(void *));
    } else {
        NSArray *sorted = [[NSArray alloc] initWithObjects:(id *)v count:(NSUInteger)r.length]; /* keeps them alive */
        for (CFIndex i = 0; i < r.length; i++)
            [OBJ(a) replaceObjectAtIndex:(NSUInteger)(r.location + i) withObject:[sorted objectAtIndex:(NSUInteger)i]];
        [sorted release];
    }
    free(v);
    free(tmp);
}

/* ---- dictionaries with callbacks --------------------------------------------------------- */

typedef struct FCFEntry {
    const void *key, *value;
    CFHashCode hash;
    struct FCFEntry *next;
} FCFEntry;

@interface FCFDictionary : NSMutableDictionary {
@public
    FCFEntry **_buckets;
    NSUInteger _nbuckets, _n;
    CFDictionaryKeyCallBacks _kcb;
    CFDictionaryValueCallBacks _vcb;
    unsigned long _mutations;
}
@end

@interface FCFKeyEnumerator : NSEnumerator {
    FCFDictionary *_dict;
    const void **_keys;
    NSUInteger _n, _i;
}
- (instancetype)initWithDictionary:(FCFDictionary *)d;
@end

@implementation FCFDictionary
+ (instancetype)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
/* NSDictionary's -init comes here; the table is made by the callbacks' init. */
- (instancetype)initWithObjects:(const id[])objects forKeys:(const id<NSCopying>[])keys count:(NSUInteger)count
{
    for (NSUInteger i = 0; i < count; i++)
        [self setObject:objects[i] forKey:(id)keys[i]];
    return self;
}
- (instancetype)initWithKeyCallBacks:(const CFDictionaryKeyCallBacks *)kcb
                      valueCallBacks:(const CFDictionaryValueCallBacks *)vcb
{
    if ((self = [super init])) {
        if (kcb)
            _kcb = *kcb;
        if (vcb)
            _vcb = *vcb;
        _nbuckets = 16;
        _buckets = calloc(_nbuckets, sizeof(FCFEntry *));
    }
    return self;
}
static CFHashCode key_hash(FCFDictionary *d, const void *k) { return d->_kcb.hash ? d->_kcb.hash(k) : (CFHashCode)k; }
static BOOL key_equal(FCFDictionary *d, const void *a, const void *b)
{
    return a == b || (d->_kcb.equal && d->_kcb.equal(a, b));
}
static FCFEntry **find_entry(FCFDictionary *d, const void *k)
{
    CFHashCode h = key_hash(d, k);
    FCFEntry **p = &d->_buckets[h & (d->_nbuckets - 1)];
    for (; *p; p = &(*p)->next)
        if ((*p)->hash == h && key_equal(d, (*p)->key, k))
            return p;
    return p;
}
- (void)removeAllObjects
{
    for (NSUInteger b = 0; b < _nbuckets; b++) {
        FCFEntry *e = _buckets[b];
        while (e) {
            FCFEntry *next = e->next;
            if (_kcb.release)
                _kcb.release(NULL, e->key);
            if (_vcb.release)
                _vcb.release(NULL, e->value);
            free(e);
            e = next;
        }
        _buckets[b] = NULL;
    }
    _n = 0;
    _mutations++;
}
- (void)dealloc
{
    [self removeAllObjects];
    free(_buckets);
    [super dealloc];
}
- (NSUInteger)count { return _n; }
- (BOOL)_ferryGetValue:(const void **)value forKey:(const void *)key
{
    FCFEntry *e = *find_entry(self, key);
    if (e && value)
        *value = e->value;
    return e != NULL;
}
- (id)objectForKey:(id)key
{
    FCFEntry *e = *find_entry(self, key);
    return e ? (id)e->value : nil;
}
- (void)setObject:(id)value forKey:(id)key
{
    FCFEntry **p = find_entry(self, key);
    const void *v = _vcb.retain ? _vcb.retain(NULL, value) : (const void *)value;
    if (*p) {
        const void *old = (*p)->value;
        (*p)->value = v;
        if (_vcb.release)
            _vcb.release(NULL, old);
        return;
    }
    FCFEntry *e = malloc(sizeof *e);
    e->key = _kcb.retain ? _kcb.retain(NULL, key) : (const void *)key;
    e->value = v;
    e->hash = key_hash(self, key);
    e->next = NULL;
    *p = e;
    _n++;
    _mutations++;
    if (_n > _nbuckets) {
        NSUInteger nb = _nbuckets * 4;
        FCFEntry **buckets = calloc(nb, sizeof(FCFEntry *));
        for (NSUInteger b = 0; b < _nbuckets; b++)
            for (FCFEntry *x = _buckets[b], *next; x; x = next) {
                next = x->next;
                x->next = buckets[x->hash & (nb - 1)];
                buckets[x->hash & (nb - 1)] = x;
            }
        free(_buckets);
        _buckets = buckets;
        _nbuckets = nb;
    }
}
- (void)removeObjectForKey:(id)key
{
    FCFEntry **p = find_entry(self, key), *e = *p;
    if (!e)
        return;
    *p = e->next;
    _n--;
    _mutations++;
    if (_kcb.release)
        _kcb.release(NULL, e->key);
    if (_vcb.release)
        _vcb.release(NULL, e->value);
    free(e);
}
- (void)_ferryGetKeys:(const void **)keys values:(const void **)values
{
    NSUInteger k = 0;
    for (NSUInteger b = 0; b < _nbuckets; b++)
        for (FCFEntry *e = _buckets[b]; e; e = e->next, k++) {
            if (keys)
                keys[k] = e->key;
            if (values)
                values[k] = e->value;
        }
}
- (NSEnumerator *)keyEnumerator { return [[[FCFKeyEnumerator alloc] initWithDictionary:self] autorelease]; }
static CFArrayCallBacks key_array_callbacks(FCFDictionary *d)
{
    CFArrayCallBacks cb = {0, d->_kcb.retain == copy_string ? cftype_retain : d->_kcb.retain, d->_kcb.release,
                           d->_kcb.copyDescription, d->_kcb.equal};
    return cb;
}
- (NSArray *)allKeys
{
    CFArrayCallBacks cb = key_array_callbacks(self);
    FCFArray *a = [[FCFArray alloc] initWithCallBacks:&cb];
    const void **keys = malloc((_n + 1) * sizeof(void *));
    [self _ferryGetKeys:keys values:NULL];
    for (NSUInteger i = 0; i < _n; i++)
        [a addObject:(id)keys[i]];
    free(keys);
    return [a autorelease];
}
- (NSArray *)allValues
{
    CFArrayCallBacks cb = {0, _vcb.retain, _vcb.release, _vcb.copyDescription, _vcb.equal};
    FCFArray *a = [[FCFArray alloc] initWithCallBacks:&cb];
    const void **values = malloc((_n + 1) * sizeof(void *));
    [self _ferryGetKeys:NULL values:values];
    for (NSUInteger i = 0; i < _n; i++)
        [a addObject:(id)values[i]];
    free(values);
    return [a autorelease];
}
- (FCFDictionary *)_ferryCFCopy
{
    FCFDictionary *c = [[FCFDictionary alloc] initWithKeyCallBacks:&_kcb valueCallBacks:&_vcb];
    for (NSUInteger b = 0; b < _nbuckets; b++)
        for (FCFEntry *e = _buckets[b]; e; e = e->next)
            [c setObject:(id)e->value forKey:(id)e->key];
    return c;
}
- (id)copyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [self _ferryCFCopy]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    /* state->state: the bucket, extra[0]: how far into its chain */
    NSUInteger k = 0;
    state->itemsPtr = buffer;
    state->mutationsPtr = &_mutations;
    while (k < len && state->state < _nbuckets) {
        FCFEntry *e = _buckets[state->state];
        for (unsigned long skip = state->extra[0]; e && skip; skip--)
            e = e->next;
        while (e && k < len) {
            buffer[k++] = (id)e->key;
            state->extra[0]++;
            e = e->next;
        }
        if (!e) {
            state->state++;
            state->extra[0] = 0;
        }
    }
    return k;
}
@end

@implementation FCFKeyEnumerator
- (instancetype)initWithDictionary:(FCFDictionary *)d
{
    if ((self = [super init])) {
        _dict = [d retain];
        _n = d->_n;
        _keys = malloc((_n + 1) * sizeof(void *));
        [d _ferryGetKeys:_keys values:NULL];
    }
    return self;
}
- (void)dealloc
{
    free(_keys);
    [_dict release];
    [super dealloc];
}
- (id)nextObject { return _i < _n ? (id)_keys[_i++] : nil; }
- (NSArray *)allObjects
{
    NSMutableArray *a = [NSMutableArray array];
    while (_i < _n)
        [a addObject:(id)_keys[_i++]];
    return a;
}
@end

static BOOL is_cftype_dictionary(const CFDictionaryKeyCallBacks *k, const CFDictionaryValueCallBacks *v)
{
    BOOL key = k == &kCFTypeDictionaryKeyCallBacks || k == &kCFCopyStringDictionaryKeyCallBacks ||
               (k && (k->retain == cftype_retain || k->retain == copy_string) && k->release == cftype_release &&
                k->equal == cftype_equal && k->hash == cftype_hash);
    BOOL value = v == &kCFTypeDictionaryValueCallBacks ||
                 (v && v->retain == cftype_retain && v->release == cftype_release);
    return key && value;
}
static BOOL is_fcf(id d) { return [d isKindOfClass:[FCFDictionary class]]; }

CFDictionaryRef CFDictionaryCreate(CFAllocatorRef alloc, const void **keys, const void **values, CFIndex count,
                                   const CFDictionaryKeyCallBacks *kcb, const CFDictionaryValueCallBacks *vcb)
{
    if (is_cftype_dictionary(kcb, vcb))
        return (CFDictionaryRef)[[NSDictionary alloc] initWithObjects:(id *)values
                                                              forKeys:(const id<NSCopying> *)keys
                                                                count:(NSUInteger)count];
    FCFDictionary *d = [[FCFDictionary alloc] initWithKeyCallBacks:kcb valueCallBacks:vcb];
    for (CFIndex i = 0; i < count; i++)
        [d setObject:(id)values[i] forKey:(id)keys[i]];
    return (CFDictionaryRef)d;
}
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef alloc, CFIndex capacity,
                                                 const CFDictionaryKeyCallBacks *kcb,
                                                 const CFDictionaryValueCallBacks *vcb)
{
    if (is_cftype_dictionary(kcb, vcb))
        return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] init];
    return (CFMutableDictionaryRef)[[FCFDictionary alloc] initWithKeyCallBacks:kcb valueCallBacks:vcb];
}
CFDictionaryRef CFDictionaryCreateCopy(CFAllocatorRef alloc, CFDictionaryRef d)
{
    return (CFDictionaryRef)[OBJ(d) copy];
}
CFMutableDictionaryRef CFDictionaryCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFDictionaryRef d)
{
    return (CFMutableDictionaryRef)[OBJ(d) mutableCopy];
}
CFIndex CFDictionaryGetCount(CFDictionaryRef d) { return (CFIndex)[OBJ(d) count]; }
Boolean CFDictionaryGetValueIfPresent(CFDictionaryRef d, const void *key, const void **value)
{
    if (is_fcf(OBJ(d)))
        return [(FCFDictionary *)OBJ(d) _ferryGetValue:value forKey:key];
    id v = key ? [OBJ(d) objectForKey:OBJ(key)] : nil;
    if (v && value)
        *value = v;
    return v != nil;
}
const void *CFDictionaryGetValue(CFDictionaryRef d, const void *key)
{
    const void *v = NULL;
    return CFDictionaryGetValueIfPresent(d, key, &v) ? v : NULL;
}
Boolean CFDictionaryContainsKey(CFDictionaryRef d, const void *key) { return CFDictionaryGetValueIfPresent(d, key, NULL); }
CFIndex CFDictionaryGetCountOfKey(CFDictionaryRef d, const void *key) { return CFDictionaryContainsKey(d, key) ? 1 : 0; }
void CFDictionaryGetKeysAndValues(CFDictionaryRef d, const void **keys, const void **values)
{
    if (is_fcf(OBJ(d))) {
        [(FCFDictionary *)OBJ(d) _ferryGetKeys:keys values:values];
        return;
    }
    NSUInteger k = 0;
    for (id key in OBJ(d)) {
        if (keys)
            keys[k] = key;
        if (values)
            values[k] = [OBJ(d) objectForKey:key];
        k++;
    }
}
static void with_pairs(CFDictionaryRef d, void (^each)(const void *key, const void *value))
{
    NSUInteger n = [OBJ(d) count];
    const void **keys = malloc((n + 1) * sizeof(void *)), **values = malloc((n + 1) * sizeof(void *));
    CFDictionaryGetKeysAndValues(d, keys, values);
    for (NSUInteger i = 0; i < n; i++)
        each(keys[i], values[i]);
    free(keys);
    free(values);
}
static Boolean value_equal(CFDictionaryRef d, const void *a, const void *b)
{
    if (is_fcf(OBJ(d))) {
        FCFDictionary *f = OBJ(d);
        return a == b || (f->_vcb.equal && f->_vcb.equal(a, b));
    }
    return a == b || (a && b && CFEqual(a, b));
}
CFIndex CFDictionaryGetCountOfValue(CFDictionaryRef d, const void *value)
{
    __block CFIndex n = 0;
    with_pairs(d, ^(const void *k, const void *v) {
        if (value_equal(d, v, value))
            n++;
    });
    return n;
}
Boolean CFDictionaryContainsValue(CFDictionaryRef d, const void *value) { return CFDictionaryGetCountOfValue(d, value) > 0; }
void CFDictionaryApplyFunction(CFDictionaryRef d, CFDictionaryApplierFunction applier, void *context)
{
    with_pairs(d, ^(const void *k, const void *v) {
        applier(k, v, context);
    });
}
void CFDictionarySetValue(CFMutableDictionaryRef d, const void *key, const void *value)
{
    if (!value && !is_fcf(OBJ(d)))
        [OBJ(d) removeObjectForKey:OBJ(key)];
    else
        [OBJ(d) setObject:OBJ(value) forKey:OBJ(key)];
}
void CFDictionaryAddValue(CFMutableDictionaryRef d, const void *key, const void *value)
{
    if (!CFDictionaryContainsKey(d, key))
        CFDictionarySetValue(d, key, value);
}
void CFDictionaryReplaceValue(CFMutableDictionaryRef d, const void *key, const void *value)
{
    if (CFDictionaryContainsKey(d, key))
        CFDictionarySetValue(d, key, value);
}
void CFDictionaryRemoveValue(CFMutableDictionaryRef d, const void *key) { [OBJ(d) removeObjectForKey:OBJ(key)]; }
void CFDictionaryRemoveAllValues(CFMutableDictionaryRef d) { [OBJ(d) removeAllObjects]; }

/* ---- strings ----------------------------------------------------------------------------- */

static NSStringCompareOptions ns_options(CFStringCompareFlags f)
{
    return (NSStringCompareOptions)(f & ~(CFOptionFlags)kCFCompareNonliteral & ~(CFOptionFlags)kCFCompareLocalized);
}
static CFRange cf_range(NSRange r)
{
    return r.location == NSNotFound ? CFRangeMake(kCFNotFound, 0) : CFRangeMake((CFIndex)r.location, (CFIndex)r.length);
}
static NSRange ns_range(CFRange r) { return NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length); }

/* Ferry copies the characters: the buffer may be reused as soon as this returns. */
CFStringRef CFStringCreateWithCharactersNoCopy(CFAllocatorRef alloc, const UniChar *chars, CFIndex n,
                                               CFAllocatorRef deallocator)
{
    return (CFStringRef)[[NSString alloc] initWithCharacters:chars length:(NSUInteger)n];
}
CFStringRef CFStringCreateWithSubstring(CFAllocatorRef alloc, CFStringRef s, CFRange r)
{
    return (CFStringRef)[[OBJ(s) substringWithRange:ns_range(r)] copy];
}
CFStringRef CFStringCreateWithFormatAndArguments(CFAllocatorRef alloc, CFDictionaryRef options, CFStringRef format,
                                                 va_list args)
{
    return (CFStringRef)[FFormat((NSString *)format, args) copy];
}
CFMutableStringRef CFStringCreateMutableCopy(CFAllocatorRef alloc, CFIndex maxLength, CFStringRef s)
{
    return (CFMutableStringRef)[OBJ(s) mutableCopy];
}
CFMutableStringRef CFStringCreateMutableWithExternalCharactersNoCopy(CFAllocatorRef alloc, UniChar *chars,
                                                                     CFIndex n, CFIndex capacity,
                                                                     CFAllocatorRef externalAllocator)
{
    NSMutableString *m = [[NSMutableString alloc] init];
    if (chars && n)
        [m setString:FStringFromChars(chars, (NSUInteger)n)];
    return (CFMutableStringRef)m;
}
void CFStringSetExternalCharactersNoCopy(CFMutableStringRef s, UniChar *chars, CFIndex n, CFIndex capacity)
{
    [OBJ(s) setString:chars ? FStringFromChars(chars, (NSUInteger)n) : @""];
}
void CFStringAppendCharacters(CFMutableStringRef s, const UniChar *chars, CFIndex n)
{
    [OBJ(s) appendString:FStringFromChars(chars, (NSUInteger)n)];
}
void CFStringAppendFormatAndArguments(CFMutableStringRef s, CFDictionaryRef options, CFStringRef format, va_list args)
{
    [OBJ(s) appendString:FFormat((NSString *)format, args)];
}
void CFStringAppendFormat(CFMutableStringRef s, CFDictionaryRef options, CFStringRef format, ...)
{
    va_list ap;
    va_start(ap, format);
    CFStringAppendFormatAndArguments(s, options, format, ap);
    va_end(ap);
}
void CFStringInsert(CFMutableStringRef s, CFIndex i, CFStringRef inserted)
{
    [OBJ(s) insertString:OBJ(inserted) atIndex:(NSUInteger)i];
}
void CFStringDelete(CFMutableStringRef s, CFRange r) { [OBJ(s) deleteCharactersInRange:ns_range(r)]; }
void CFStringReplace(CFMutableStringRef s, CFRange r, CFStringRef replacement)
{
    [OBJ(s) replaceCharactersInRange:ns_range(r) withString:OBJ(replacement)];
}
void CFStringReplaceAll(CFMutableStringRef s, CFStringRef replacement) { [OBJ(s) setString:OBJ(replacement)]; }
CFIndex CFStringFindAndReplace(CFMutableStringRef s, CFStringRef find, CFStringRef replacement, CFRange r,
                               CFStringCompareFlags opts)
{
    return (CFIndex)[OBJ(s) replaceOccurrencesOfString:OBJ(find) withString:OBJ(replacement)
                                               options:ns_options(opts) range:ns_range(r)];
}
CFRange CFStringFind(CFStringRef s, CFStringRef find, CFStringCompareFlags opts)
{
    return cf_range([OBJ(s) rangeOfString:OBJ(find) options:ns_options(opts)]);
}
Boolean CFStringFindWithOptions(CFStringRef s, CFStringRef find, CFRange r, CFStringCompareFlags opts, CFRange *result)
{
    NSRange f = [OBJ(s) rangeOfString:OBJ(find) options:ns_options(opts) range:ns_range(r)];
    if (f.location == NSNotFound)
        return false;
    if (result)
        *result = cf_range(f);
    return true;
}
CFComparisonResult CFStringCompareWithOptions(CFStringRef a, CFStringRef b, CFRange r, CFStringCompareFlags opts)
{
    return (CFComparisonResult)[[OBJ(a) substringWithRange:ns_range(r)] compare:OBJ(b) options:ns_options(opts)];
}
void CFStringUppercase(CFMutableStringRef s, const void *locale) { [OBJ(s) setString:[OBJ(s) uppercaseString]]; }
void CFStringLowercase(CFMutableStringRef s, const void *locale) { [OBJ(s) setString:[OBJ(s) lowercaseString]]; }
void CFStringCapitalize(CFMutableStringRef s, const void *locale) { [OBJ(s) setString:[OBJ(s) capitalizedString]]; }
void CFStringTrimWhitespace(CFMutableStringRef s)
{
    [OBJ(s) setString:[OBJ(s) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}
void CFStringTrim(CFMutableStringRef s, CFStringRef trim)
{
    NSString *t = OBJ(trim);
    NSUInteger tl = [t length];
    if (!tl)
        return;
    while ([OBJ(s) hasPrefix:t])
        [OBJ(s) deleteCharactersInRange:NSMakeRange(0, tl)];
    while ([OBJ(s) hasSuffix:t])
        [OBJ(s) deleteCharactersInRange:NSMakeRange([OBJ(s) length] - tl, tl)];
}
CFArrayRef CFStringCreateArrayBySeparatingStrings(CFAllocatorRef alloc, CFStringRef s, CFStringRef separator)
{
    return (CFArrayRef)[[OBJ(s) componentsSeparatedByString:OBJ(separator)] copy];
}
CFStringRef CFStringCreateByCombiningStrings(CFAllocatorRef alloc, CFArrayRef array, CFStringRef separator)
{
    return (CFStringRef)[[OBJ(array) componentsJoinedByString:OBJ(separator)] copy];
}
Boolean CFStringGetFileSystemRepresentation(CFStringRef s, char *buffer, CFIndex max)
{
    const char *p = [OBJ(s) fileSystemRepresentation];
    size_t n = strlen(p);
    if ((CFIndex)n + 1 > max)
        return false;
    memcpy(buffer, p, n + 1);
    return true;
}
CFIndex CFStringGetMaximumSizeOfFileSystemRepresentation(CFStringRef s) { return (CFIndex)[OBJ(s) length] * 3 + 1; }

/* ---- UUIDs ------------------------------------------------------------------------------- */

CFUUIDRef CFUUIDCreate(CFAllocatorRef alloc) { return (CFUUIDRef)[[NSUUID alloc] init]; }
CFUUIDRef CFUUIDCreateFromUUIDBytes(CFAllocatorRef alloc, CFUUIDBytes bytes)
{
    return (CFUUIDRef)[[NSUUID alloc] initWithUUIDBytes:(const unsigned char *)&bytes];
}
CFUUIDRef CFUUIDCreateWithBytes(CFAllocatorRef alloc, UInt8 b0, UInt8 b1, UInt8 b2, UInt8 b3, UInt8 b4, UInt8 b5,
                                UInt8 b6, UInt8 b7, UInt8 b8, UInt8 b9, UInt8 b10, UInt8 b11, UInt8 b12, UInt8 b13,
                                UInt8 b14, UInt8 b15)
{
    CFUUIDBytes b = {b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15};
    return CFUUIDCreateFromUUIDBytes(alloc, b);
}
/* The same object for the same bytes, kept for the life of the program. */
CFUUIDRef CFUUIDGetConstantUUIDWithBytes(CFAllocatorRef alloc, UInt8 b0, UInt8 b1, UInt8 b2, UInt8 b3, UInt8 b4,
                                         UInt8 b5, UInt8 b6, UInt8 b7, UInt8 b8, UInt8 b9, UInt8 b10, UInt8 b11,
                                         UInt8 b12, UInt8 b13, UInt8 b14, UInt8 b15)
{
    static NSMutableDictionary *constants;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    CFUUIDRef u = CFUUIDCreateWithBytes(alloc, b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15);
    os_unfair_lock_lock(&lock);
    if (!constants)
        constants = [[NSMutableDictionary alloc] init];
    NSUUID *kept = [constants objectForKey:OBJ(u)];
    if (!kept) {
        kept = OBJ(u);
        [constants setObject:kept forKey:kept];
    }
    os_unfair_lock_unlock(&lock);
    CFRelease(u);
    return (CFUUIDRef)kept;
}
CFUUIDRef CFUUIDCreateFromString(CFAllocatorRef alloc, CFStringRef s)
{
    return (CFUUIDRef)[[NSUUID alloc] initWithUUIDString:OBJ(s)];
}
CFStringRef CFUUIDCreateString(CFAllocatorRef alloc, CFUUIDRef uuid) { return (CFStringRef)[[OBJ(uuid) UUIDString] copy]; }
CFUUIDBytes CFUUIDGetUUIDBytes(CFUUIDRef uuid)
{
    CFUUIDBytes b;
    [OBJ(uuid) getUUIDBytes:(unsigned char *)&b];
    return b;
}

/* ---- URLs -------------------------------------------------------------------------------- */

static NSString *posix_path(CFStringRef path, CFURLPathStyle style)
{
    NSString *p = OBJ(path);
    if (style == kCFURLWindowsPathStyle)
        return [p stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if (style == kCFURLHFSPathStyle) {
        /* "Volume:folder:file": the volume is the root here */
        NSRange colon = [p rangeOfString:@":"];
        NSString *rest = colon.location == NSNotFound ? @"" : [p substringFromIndex:colon.location + 1];
        return [@"/" stringByAppendingString:[rest stringByReplacingOccurrencesOfString:@":" withString:@"/"]];
    }
    return p;
}
CFURLRef CFURLCreateWithString(CFAllocatorRef alloc, CFStringRef s, CFURLRef base)
{
    return (CFURLRef)[[NSURL alloc] initWithString:OBJ(s) relativeToURL:OBJ(base)];
}
CFURLRef CFURLCreateWithBytes(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex length, CFStringEncoding encoding,
                              CFURLRef base)
{
    CFStringRef s = CFStringCreateWithBytes(alloc, bytes, length, encoding, false);
    if (!s)
        return NULL;
    CFURLRef u = CFURLCreateWithString(alloc, s, base);
    CFRelease(s);
    return u;
}
CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef alloc, CFStringRef path, CFURLPathStyle style, Boolean isDir)
{
    return (CFURLRef)[[NSURL fileURLWithPath:posix_path(path, style) isDirectory:isDir] retain];
}
CFURLRef CFURLCreateFromFileSystemRepresentation(CFAllocatorRef alloc, const UInt8 *buffer, CFIndex len, Boolean isDir)
{
    NSString *p = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:(const char *)buffer
                                                                              length:(NSUInteger)len];
    return (CFURLRef)[[NSURL fileURLWithPath:p isDirectory:isDir] retain];
}
CFURLRef CFURLCopyAbsoluteURL(CFURLRef u) { return (CFURLRef)[[OBJ(u) absoluteURL] retain]; }
CFStringRef CFURLGetString(CFURLRef u) { return (CFStringRef)[OBJ(u) relativeString]; }
CFURLRef CFURLGetBaseURL(CFURLRef u) { return (CFURLRef)[OBJ(u) baseURL]; }
CFStringRef CFURLCopyFileSystemPath(CFURLRef u, CFURLPathStyle style)
{
    NSString *p = [OBJ(u) path];
    if (style == kCFURLWindowsPathStyle)
        p = [p stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
    else if (style == kCFURLHFSPathStyle && [p hasPrefix:@"/"]) {
        /* "Volume:folder:file", the one volume being the root, named Ferry here;
         * a colon in a name is a slash in HFS terms. */
        NSMutableArray *parts = [NSMutableArray arrayWithObject:@"Ferry"];
        for (NSString *c in [p componentsSeparatedByString:@"/"])
            if ([c length])
                [parts addObject:[c stringByReplacingOccurrencesOfString:@":" withString:@"/"]];
        p = [parts componentsJoinedByString:@":"];
        if ([parts count] == 1)
            p = @"Ferry:";
    }
    return (CFStringRef)[p copy];
}
Boolean CFURLGetFileSystemRepresentation(CFURLRef u, Boolean resolveAgainstBase, UInt8 *buffer, CFIndex max)
{
    NSString *p = resolveAgainstBase ? [[OBJ(u) absoluteURL] path] : [OBJ(u) path];
    return p && CFStringGetFileSystemRepresentation((CFStringRef)p, (char *)buffer, max);
}
CFStringRef CFURLCopyScheme(CFURLRef u) { return (CFStringRef)[[OBJ(u) scheme] copy]; }
CFStringRef CFURLCopyHostName(CFURLRef u) { return (CFStringRef)[[OBJ(u) host] copy]; }
SInt32 CFURLGetPortNumber(CFURLRef u)
{
    NSNumber *p = [(NSURL *)OBJ(u) port];
    return p ? (SInt32)[p intValue] : -1;
}
CFStringRef CFURLCopyPath(CFURLRef u) { return (CFStringRef)[[OBJ(u) path] copy]; }
CFStringRef CFURLCopyQueryString(CFURLRef u, CFStringRef leave) { return (CFStringRef)[[OBJ(u) query] copy]; }
CFStringRef CFURLCopyFragment(CFURLRef u, CFStringRef leave) { return (CFStringRef)[[OBJ(u) fragment] copy]; }
CFStringRef CFURLCopyLastPathComponent(CFURLRef u) { return (CFStringRef)[[OBJ(u) lastPathComponent] copy]; }
CFStringRef CFURLCopyPathExtension(CFURLRef u)
{
    NSString *e = [OBJ(u) pathExtension];
    return [e length] ? (CFStringRef)[e copy] : NULL;
}
Boolean CFURLHasDirectoryPath(CFURLRef u) { return [OBJ(u) hasDirectoryPath]; }
CFURLRef CFURLCreateCopyAppendingPathComponent(CFAllocatorRef alloc, CFURLRef u, CFStringRef component, Boolean isDir)
{
    return (CFURLRef)[[OBJ(u) URLByAppendingPathComponent:OBJ(component) isDirectory:isDir] retain];
}
CFURLRef CFURLCreateCopyDeletingLastPathComponent(CFAllocatorRef alloc, CFURLRef u)
{
    return (CFURLRef)[[OBJ(u) URLByDeletingLastPathComponent] retain];
}
CFURLRef CFURLCreateCopyAppendingPathExtension(CFAllocatorRef alloc, CFURLRef u, CFStringRef ext)
{
    return (CFURLRef)[[OBJ(u) URLByAppendingPathExtension:OBJ(ext)] retain];
}
CFURLRef CFURLCreateCopyDeletingPathExtension(CFAllocatorRef alloc, CFURLRef u)
{
    return (CFURLRef)[[OBJ(u) URLByDeletingPathExtension] retain];
}
Boolean CFURLResourceIsReachable(CFURLRef u, CFErrorRef *error)
{
    return [OBJ(u) checkResourceIsReachableAndReturnError:(NSError **)error];
}
Boolean CFURLCopyResourcePropertyForKey(CFURLRef u, CFStringRef key, void *valuePtr, CFErrorRef *error)
{
    id value = nil;
    if (![OBJ(u) getResourceValue:&value forKey:OBJ(key) error:(NSError **)error])
        return false;
    if (valuePtr)
        *(CFTypeRef *)valuePtr = value ? CFRetain(value) : NULL;
    return true;
}
/* CFURLGetFSRef is in FSRefs.m (freemac 1.221, Ferry 0.45.0). */

/* ---- bundles ----------------------------------------------------------------------------- */

const CFStringRef kCFBundleInfoDictionaryVersionKey = (CFStringRef)@"CFBundleInfoDictionaryVersion";
const CFStringRef kCFBundleExecutableKey = (CFStringRef)@"CFBundleExecutable";
const CFStringRef kCFBundleIdentifierKey = (CFStringRef)@"CFBundleIdentifier";
const CFStringRef kCFBundleVersionKey = (CFStringRef)@"CFBundleVersion";
const CFStringRef kCFBundleDevelopmentRegionKey = (CFStringRef)@"CFBundleDevelopmentRegion";
const CFStringRef kCFBundleNameKey = (CFStringRef)@"CFBundleName";
const CFStringRef kCFBundleLocalizationsKey = (CFStringRef)@"CFBundleLocalizations";

CFURLRef CFBundleCopyResourceURL(CFBundleRef bundle, CFStringRef name, CFStringRef type, CFStringRef subdir)
{
    return (CFURLRef)[[OBJ(bundle) URLForResource:OBJ(name) withExtension:OBJ(type) subdirectory:OBJ(subdir)] retain];
}
CFStringRef CFBundleCopyLocalizedString(CFBundleRef bundle, CFStringRef key, CFStringRef value, CFStringRef table)
{
    return (CFStringRef)[[OBJ(bundle) localizedStringForKey:OBJ(key) value:OBJ(value) table:OBJ(table)] copy];
}
