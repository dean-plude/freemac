/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSMapTable, NSHashTable and NSPointerArray (freemac 1.221, Ferry 0.45.0),
 * written for freemac from Apple's public documentation of the three
 * classes and of NSPointerFunctionsOptions.
 *
 * A table is a hash table of chained entries, each in memory of its own so
 * that a weak reference to its key or value stays at one address. A weak
 * slot is the runtime's zeroing weak reference: once its object is gone the
 * entry counts as gone too, and is taken out the next time the table looks
 * at it. An entry keeps the hash its key had when it went in. */
#import "FInternal.h"

/* ---- one slot: how it holds what it is given, and how it compares -------------------- */

static NSUInteger memory_of(NSPointerFunctionsOptions o) { return o & 0xff; }
static NSUInteger personality_of(NSPointerFunctionsOptions o) { return o & 0xff00; }
static BOOL weak_memory(NSPointerFunctionsOptions o)
{
    return memory_of(o) == NSPointerFunctionsWeakMemory || memory_of(o) == NSPointerFunctionsZeroingWeakMemory;
}
static BOOL holds_objects(NSPointerFunctionsOptions o)
{
    NSUInteger p = personality_of(o);
    return memory_of(o) != NSPointerFunctionsOpaqueMemory && memory_of(o) != NSPointerFunctionsMallocMemory &&
           (p == NSPointerFunctionsObjectPersonality || p == NSPointerFunctionsObjectPointerPersonality);
}

static void check_options(NSPointerFunctionsOptions o)
{
    NSUInteger m = memory_of(o), p = personality_of(o);
    if (m == NSPointerFunctionsMallocMemory || m == NSPointerFunctionsMachVirtualMemory ||
        p == NSPointerFunctionsStructPersonality)
        FRaise(NSInvalidArgumentException, @"*** pointer functions options %#lx are not supported here", (unsigned long)o);
}

/* Puts a value in a slot as the options say. */
static void slot_store(void **slot, void *value, NSPointerFunctionsOptions o)
{
    if (weak_memory(o)) {
        objc_storeWeak((id *)slot, (id)value);
        return;
    }
    if (holds_objects(o)) {
        id v = (id)value;
        v = (o & NSPointerFunctionsCopyIn) ? [v copyWithZone:NULL] : [v retain];
        [(id)*slot release];
        *slot = v;
        return;
    }
    *slot = value;
}

/* What a slot holds now, autoreleased if it is a weak object; NULL once it's gone. */
static void *slot_load(void **slot, NSPointerFunctionsOptions o)
{
    if (weak_memory(o))
        return objc_loadWeak((id *)slot);
    return *slot;
}

static void slot_clear(void **slot, NSPointerFunctionsOptions o)
{
    if (weak_memory(o))
        objc_storeWeak((id *)slot, nil);
    else if (holds_objects(o))
        [(id)*slot release];
    *slot = NULL;
}

static NSUInteger hash_of(void *p, NSPointerFunctionsOptions o)
{
    switch (personality_of(o)) {
    case NSPointerFunctionsObjectPersonality: return p ? [(id)p hash] : 0;
    case NSPointerFunctionsCStringPersonality: {
        NSUInteger h = 5381;
        for (const unsigned char *s = p; s && *s; s++)
            h = h * 33 + *s;
        return h;
    }
    default: return (NSUInteger)p >> 4 ^ (NSUInteger)p;
    }
}

static BOOL same(void *a, void *b, NSPointerFunctionsOptions o)
{
    if (a == b)
        return YES;
    if (!a || !b)
        return NO;
    switch (personality_of(o)) {
    case NSPointerFunctionsObjectPersonality: return [(id)a isEqual:(id)b];
    case NSPointerFunctionsCStringPersonality: return strcmp(a, b) == 0;
    default: return NO;
    }
}

static id describe(void *p, NSPointerFunctionsOptions o)
{
    if (holds_objects(o) || weak_memory(o))
        return (id)p;
    if (personality_of(o) == NSPointerFunctionsCStringPersonality)
        return [NSString stringWithUTF8String:p];
    return [NSString stringWithFormat:@"%p", p];
}

/* ---- the table both classes are made on --------------------------------------------- */

struct entry {
    struct entry *next;
    NSUInteger hash;
    void *key, *value;
};

struct table {
    struct entry **buckets;
    NSUInteger nbuckets, count;
    NSPointerFunctionsOptions keys, values;
    unsigned long mutations;
};

static void table_init(struct table *t, NSPointerFunctionsOptions keys, NSPointerFunctionsOptions values,
                       NSUInteger capacity)
{
    check_options(keys);
    if (values != (NSPointerFunctionsOptions)-1) /* a hash table's entries have no values */
        check_options(values);
    t->keys = keys;
    t->values = values;
    t->nbuckets = 16;
    while (t->nbuckets < capacity)
        t->nbuckets *= 2;
    t->buckets = calloc(t->nbuckets, sizeof *t->buckets);
    t->count = 0;
}

static BOOL entry_dead(struct table *t, struct entry *e)
{
    if (weak_memory(t->keys) && !slot_load(&e->key, t->keys))
        return YES;
    return t->values != (NSPointerFunctionsOptions)-1 && weak_memory(t->values) && !slot_load(&e->value, t->values);
}

static void entry_free(struct table *t, struct entry *e)
{
    slot_clear(&e->key, t->keys);
    if (t->values != (NSPointerFunctionsOptions)-1)
        slot_clear(&e->value, t->values);
    free(e);
    t->count--;
    t->mutations++;
}

/* Takes the entries whose weak key or value has gone out of the table. */
static void table_prune(struct table *t)
{
    if (!weak_memory(t->keys) && (t->values == (NSPointerFunctionsOptions)-1 || !weak_memory(t->values)))
        return;
    for (NSUInteger i = 0; i < t->nbuckets; i++)
        for (struct entry **p = &t->buckets[i]; *p;) {
            struct entry *e = *p;
            if (entry_dead(t, e)) {
                *p = e->next;
                entry_free(t, e);
            } else {
                p = &e->next;
            }
        }
}

static struct entry **table_find(struct table *t, void *key, NSUInteger h)
{
    for (struct entry **p = &t->buckets[h & (t->nbuckets - 1)]; *p;) {
        struct entry *e = *p;
        if (entry_dead(t, e)) {
            *p = e->next;
            entry_free(t, e);
            continue;
        }
        if (e->hash == h && same(slot_load(&e->key, t->keys), key, t->keys))
            return p;
        p = &e->next;
    }
    return NULL;
}

static void table_grow(struct table *t)
{
    NSUInteger n = t->nbuckets * 2;
    struct entry **b = calloc(n, sizeof *b);
    for (NSUInteger i = 0; i < t->nbuckets; i++)
        for (struct entry *e = t->buckets[i], *next; e; e = next) {
            next = e->next;
            e->next = b[e->hash & (n - 1)];
            b[e->hash & (n - 1)] = e;
        }
    free(t->buckets);
    t->buckets = b;
    t->nbuckets = n;
}

static void table_set(struct table *t, void *key, void *value)
{
    NSUInteger h = hash_of(key, t->keys);
    struct entry **p = table_find(t, key, h);
    if (p) {
        if (t->values != (NSPointerFunctionsOptions)-1)
            slot_store(&(*p)->value, value, t->values);
        t->mutations++;
        return;
    }
    if (t->count >= t->nbuckets)
        table_grow(t);
    struct entry *e = calloc(1, sizeof *e);
    e->hash = h;
    slot_store(&e->key, key, t->keys);
    if (t->values != (NSPointerFunctionsOptions)-1)
        slot_store(&e->value, value, t->values);
    e->next = t->buckets[h & (t->nbuckets - 1)];
    t->buckets[h & (t->nbuckets - 1)] = e;
    t->count++;
    t->mutations++;
}

static void table_remove(struct table *t, void *key)
{
    struct entry **p = table_find(t, key, hash_of(key, t->keys));
    if (p) {
        struct entry *e = *p;
        *p = e->next;
        entry_free(t, e);
    }
}

static void table_clear(struct table *t)
{
    for (NSUInteger i = 0; i < t->nbuckets; i++) {
        for (struct entry *e = t->buckets[i], *next; e; e = next) {
            next = e->next;
            entry_free(t, e);
        }
        t->buckets[i] = NULL;
    }
}

/* The live keys (or values), as objects, for enumerating. */
static NSArray *table_list(struct table *t, BOOL values)
{
    table_prune(t);
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:t->count];
    for (NSUInteger i = 0; i < t->nbuckets; i++)
        for (struct entry *e = t->buckets[i]; e; e = e->next) {
            void *p = values ? slot_load(&e->value, t->values) : slot_load(&e->key, t->keys);
            id o = describe(p, values ? t->values : t->keys);
            if (o)
                [a addObject:o];
        }
    return a;
}

/* ---- NSMapTable ----------------------------------------------------------------------- */

@implementation NSMapTable {
    struct table _t;
}

- (instancetype)initWithKeyOptions:(NSPointerFunctionsOptions)keyOptions
                      valueOptions:(NSPointerFunctionsOptions)valueOptions
                          capacity:(NSUInteger)initialCapacity
{
    if ((self = [super init]))
        table_init(&_t, keyOptions, valueOptions, initialCapacity);
    return self;
}
- (instancetype)init
{
    return [self initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory
                           capacity:0];
}
- (void)dealloc
{
    table_clear(&_t);
    free(_t.buckets);
    [super dealloc];
}
+ (NSMapTable *)mapTableWithKeyOptions:(NSPointerFunctionsOptions)keyOptions
                          valueOptions:(NSPointerFunctionsOptions)valueOptions
{
    return [[[self alloc] initWithKeyOptions:keyOptions valueOptions:valueOptions capacity:0] autorelease];
}
+ (NSMapTable *)strongToStrongObjectsMapTable
{
    return [self mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory];
}
+ (NSMapTable *)weakToStrongObjectsMapTable
{
    return [self mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsStrongMemory];
}
+ (NSMapTable *)strongToWeakObjectsMapTable
{
    return [self mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory];
}
+ (NSMapTable *)weakToWeakObjectsMapTable
{
    return [self mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsWeakMemory];
}
+ (id)mapTableWithStrongToStrongObjects { return [self strongToStrongObjectsMapTable]; }
+ (id)mapTableWithWeakToStrongObjects { return [self weakToStrongObjectsMapTable]; }
+ (id)mapTableWithStrongToWeakObjects { return [self strongToWeakObjectsMapTable]; }
+ (id)mapTableWithWeakToWeakObjects { return [self weakToWeakObjectsMapTable]; }

- (id)objectForKey:(id)aKey
{
    if (!aKey)
        return nil;
    struct entry **p = table_find(&_t, aKey, hash_of(aKey, _t.keys));
    return p ? (id)slot_load(&(*p)->value, _t.values) : nil;
}
- (void)setObject:(id)anObject forKey:(id)aKey
{
    if (!aKey)
        FRaise(NSInvalidArgumentException, @"*** -[NSMapTable setObject:forKey:]: key is nil");
    if (!anObject)
        table_remove(&_t, aKey);
    else
        table_set(&_t, aKey, anObject);
}
- (void)removeObjectForKey:(id)aKey
{
    if (aKey)
        table_remove(&_t, aKey);
}
- (void)removeAllObjects { table_clear(&_t); }
- (NSUInteger)count
{
    table_prune(&_t);
    return _t.count;
}
- (NSEnumerator *)keyEnumerator { return [table_list(&_t, NO) objectEnumerator]; }
- (NSEnumerator *)objectEnumerator { return [table_list(&_t, YES) objectEnumerator]; }
- (NSDictionary *)dictionaryRepresentation
{
    table_prune(&_t);
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:_t.count];
    for (NSUInteger i = 0; i < _t.nbuckets; i++)
        for (struct entry *e = _t.buckets[i]; e; e = e->next) {
            id k = describe(slot_load(&e->key, _t.keys), _t.keys), v = describe(slot_load(&e->value, _t.values), _t.values);
            if (k && v)
                [d setObject:v forKey:k];
        }
    return d;
}
- (id)copyWithZone:(NSZone *)zone
{
    NSMapTable *m = [[NSMapTable alloc] initWithKeyOptions:_t.keys valueOptions:_t.values capacity:_t.count];
    for (NSUInteger i = 0; i < _t.nbuckets; i++)
        for (struct entry *e = _t.buckets[i]; e; e = e->next)
            if (!entry_dead(&_t, e))
                table_set(&m->_t, slot_load(&e->key, _t.keys), slot_load(&e->value, _t.values));
    return m;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained *)buffer
                                    count:(NSUInteger)len
{
    /* a list of the keys made when the enumeration starts, kept in extra[0] */
    if (state->state == 0)
        state->extra[0] = (unsigned long)table_list(&_t, NO);
    return [(NSArray *)state->extra[0] countByEnumeratingWithState:state objects:buffer count:len];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"NSMapTable %@", [self dictionaryRepresentation]];
}
@end

/* ---- NSHashTable ---------------------------------------------------------------------- */

@implementation NSHashTable {
    struct table _t;
}

- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options capacity:(NSUInteger)initialCapacity
{
    if ((self = [super init]))
        table_init(&_t, options, (NSPointerFunctionsOptions)-1, initialCapacity);
    return self;
}
- (instancetype)init { return [self initWithOptions:NSPointerFunctionsStrongMemory capacity:0]; }
- (void)dealloc
{
    table_clear(&_t);
    free(_t.buckets);
    [super dealloc];
}
+ (NSHashTable *)hashTableWithOptions:(NSPointerFunctionsOptions)options
{
    return [[[self alloc] initWithOptions:options capacity:0] autorelease];
}
+ (NSHashTable *)weakObjectsHashTable { return [self hashTableWithOptions:NSPointerFunctionsWeakMemory]; }
+ (id)hashTableWithWeakObjects { return [self weakObjectsHashTable]; }

- (NSUInteger)count
{
    table_prune(&_t);
    return _t.count;
}
- (id)member:(id)object
{
    if (!object)
        return nil;
    struct entry **p = table_find(&_t, object, hash_of(object, _t.keys));
    return p ? (id)slot_load(&(*p)->key, _t.keys) : nil;
}
- (BOOL)containsObject:(id)anObject { return [self member:anObject] != nil; }
- (void)addObject:(id)object
{
    if (object && ![self member:object])
        table_set(&_t, object, NULL);
}
- (void)removeObject:(id)object
{
    if (object)
        table_remove(&_t, object);
}
- (void)removeAllObjects { table_clear(&_t); }
- (NSArray *)allObjects { return table_list(&_t, NO); }
- (id)anyObject { return [[self allObjects] firstObject]; }
- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }
- (NSSet *)setRepresentation { return [NSSet setWithArray:[self allObjects]]; }
- (BOOL)intersectsHashTable:(NSHashTable *)other
{
    for (id o in [self allObjects])
        if ([other containsObject:o])
            return YES;
    return NO;
}
- (BOOL)isSubsetOfHashTable:(NSHashTable *)other
{
    for (id o in [self allObjects])
        if (![other containsObject:o])
            return NO;
    return YES;
}
- (BOOL)isEqualToHashTable:(NSHashTable *)other
{
    return [self count] == [other count] && [self isSubsetOfHashTable:other];
}
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[NSHashTable class]] && [self isEqualToHashTable:other]);
}
- (NSUInteger)hash { return [self count]; }
- (void)unionHashTable:(NSHashTable *)other
{
    for (id o in [other allObjects])
        [self addObject:o];
}
- (void)minusHashTable:(NSHashTable *)other
{
    for (id o in [other allObjects])
        [self removeObject:o];
}
- (void)intersectHashTable:(NSHashTable *)other
{
    for (id o in [self allObjects])
        if (![other containsObject:o])
            [self removeObject:o];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSHashTable *h = [[NSHashTable alloc] initWithOptions:_t.keys capacity:_t.count];
    for (id o in [self allObjects])
        [h addObject:o];
    return h;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained *)buffer
                                    count:(NSUInteger)len
{
    if (state->state == 0)
        state->extra[0] = (unsigned long)[self allObjects];
    return [(NSArray *)state->extra[0] countByEnumeratingWithState:state objects:buffer count:len];
}
- (NSString *)description { return [NSString stringWithFormat:@"NSHashTable %@", [self allObjects]]; }
@end

/* ---- NSPointerArray ---------------------------------------------------------------------- */

/* Each element in memory of its own, for the same reason as a table's entries. */
@implementation NSPointerArray {
    void ***_cells;
    NSUInteger _count, _cap;
    NSPointerFunctionsOptions _options;
}

- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options
{
    check_options(options);
    if ((self = [super init]))
        _options = options;
    return self;
}
- (instancetype)init { return [self initWithOptions:NSPointerFunctionsStrongMemory]; }
- (void)dealloc
{
    for (NSUInteger i = 0; i < _count; i++) {
        slot_clear(_cells[i], _options);
        free(_cells[i]);
    }
    free(_cells);
    [super dealloc];
}
+ (NSPointerArray *)pointerArrayWithOptions:(NSPointerFunctionsOptions)options
{
    return [[[self alloc] initWithOptions:options] autorelease];
}
+ (NSPointerArray *)strongObjectsPointerArray { return [self pointerArrayWithOptions:NSPointerFunctionsStrongMemory]; }
+ (NSPointerArray *)weakObjectsPointerArray { return [self pointerArrayWithOptions:NSPointerFunctionsWeakMemory]; }
+ (id)pointerArrayWithStrongObjects { return [self strongObjectsPointerArray]; }
+ (id)pointerArrayWithWeakObjects { return [self weakObjectsPointerArray]; }

static void check_index(NSPointerArray *self, NSUInteger index, NSUInteger count, SEL cmd)
{
    if (index >= count)
        FRaise(NSRangeException, @"*** -[NSPointerArray %s]: index (%lu) beyond bounds (%lu)", sel_getName(cmd),
               (unsigned long)index, (unsigned long)count);
}

- (NSUInteger)count { return _count; }
- (void)setCount:(NSUInteger)count
{
    while (_count > count) {
        _count--;
        slot_clear(_cells[_count], _options);
        free(_cells[_count]);
    }
    while (_count < count)
        [self addPointer:NULL];
}
- (void *)pointerAtIndex:(NSUInteger)index
{
    check_index(self, index, _count, _cmd);
    return slot_load(_cells[index], _options);
}
- (void)insertPointer:(void *)item atIndex:(NSUInteger)index
{
    check_index(self, index, _count + 1, _cmd);
    if (_count == _cap) {
        _cap = _cap ? _cap * 2 : 8;
        _cells = realloc(_cells, _cap * sizeof *_cells);
    }
    memmove(_cells + index + 1, _cells + index, (_count - index) * sizeof *_cells);
    _cells[index] = calloc(1, sizeof(void *));
    _count++;
    slot_store(_cells[index], item, _options);
}
- (void)addPointer:(void *)pointer { [self insertPointer:pointer atIndex:_count]; }
- (void)removePointerAtIndex:(NSUInteger)index
{
    check_index(self, index, _count, _cmd);
    slot_clear(_cells[index], _options);
    free(_cells[index]);
    memmove(_cells + index, _cells + index + 1, (_count - index - 1) * sizeof *_cells);
    _count--;
}
- (void)replacePointerAtIndex:(NSUInteger)index withPointer:(void *)item
{
    check_index(self, index, _count, _cmd);
    slot_store(_cells[index], item, _options);
}
/* Takes out the NULL elements, those of gone weak objects included. */
- (void)compact
{
    for (NSUInteger i = _count; i > 0; i--)
        if (!slot_load(_cells[i - 1], _options))
            [self removePointerAtIndex:i - 1];
}
- (NSArray *)allObjects
{
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:_count];
    for (NSUInteger i = 0; i < _count; i++) {
        void *p = slot_load(_cells[i], _options);
        if (p)
            [a addObject:describe(p, _options)];
    }
    return a;
}
- (id)copyWithZone:(NSZone *)zone
{
    NSPointerArray *c = [[NSPointerArray alloc] initWithOptions:_options];
    for (NSUInteger i = 0; i < _count; i++)
        [c addPointer:slot_load(_cells[i], _options)];
    return c;
}
/* NULL elements are enumerated as nil, as on a Mac. */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained *)buffer
                                    count:(NSUInteger)len
{
    NSUInteger n = 0;
    while (state->state < _count && n < len)
        buffer[n++] = (id)slot_load(_cells[state->state++], _options);
    state->itemsPtr = buffer;
    state->mutationsPtr = (unsigned long *)&_count;
    return n;
}
- (NSString *)description { return [NSString stringWithFormat:@"NSPointerArray %@", [self allObjects]]; }
@end
