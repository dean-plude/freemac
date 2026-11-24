/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: NSManagedObject and NSManagedObjectID, as Apple's
 * class references and the Core Data Programming Guide describe them
 * (freemac 1.209, Ferry 0.35.0). Our own code; no Apple code was used.
 *
 * An object keeps its values in a dictionary; a fault keeps none until a
 * value is asked for, when its context finds its row. Accessors for
 * properties a class declares @dynamic are made the first time they are
 * used (resolveInstanceMethod:): the getter and setter, object or scalar
 * as the property is declared, primitive<Key> and setPrimitive<Key>:, and
 * the to-many and ordered mutators the guide lists. Modeled keys don't
 * notify automatically; the setters send will/didChangeValueForKey:, and
 * the context records each change there (for its updated set and undo),
 * so that accessors written with the primitive methods count as well.
 * Setting a relationship sets its inverse at once, except while undo or
 * redo replays recorded changes (each side was recorded already).
 *
 * As an extension, an object is equal to its own object ID, so that a
 * predicate such as "self IN %@" with an array of IDs works in memory as it
 * does in a store; hash stays the object's own. */
#import "CDInternal.h"

/* ---- object IDs ------------------------------------------------------------------------ */

@implementation NSManagedObjectID {
    NSEntityDescription *_entity;
    NSPersistentStore *_store;   /* not retained */
    int64_t _pk;
    NSString *_temp;
}
+ (NSManagedObjectID *)cd_temporaryIDForEntity:(NSEntityDescription *)entity
{
    NSManagedObjectID *o = [[[self alloc] init] autorelease];
    o->_entity = [entity retain];
    o->_temp = [[[NSUUID UUID] UUIDString] copy];
    return o;
}
+ (NSManagedObjectID *)cd_IDForEntity:(NSEntityDescription *)entity store:(NSPersistentStore *)store pk:(int64_t)pk
{
    NSManagedObjectID *o = [[[self alloc] init] autorelease];
    o->_entity = [entity retain];
    o->_store = store;
    o->_pk = pk;
    return o;
}
- (void)dealloc
{
    [_entity release];
    [_temp release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSEntityDescription *)entity { return _entity; }
- (NSPersistentStore *)persistentStore { return _store; }
- (BOOL)isTemporaryID { return _temp != nil; }
- (int64_t)cd_pk { return _pk; }
- (NSString *)cd_temporaryName { return _temp; }
- (NSURL *)URIRepresentation
{
    if (_temp)
        return [NSURL URLWithString:[NSString stringWithFormat:@"x-coredata:///%@/t%@", [_entity name], _temp]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"x-coredata://%@/%@/p%lld", [_store identifier],
                                                           [_entity name], (long long)_pk]];
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSManagedObjectID class]])
        return NO;
    NSManagedObjectID *o = other;
    if (_temp || o->_temp)
        return [_temp isEqualToString:o->_temp];
    return _pk == o->_pk && _store == o->_store && [[[_entity cd_root] name] isEqualToString:[[o->_entity cd_root] name]];
}
- (NSUInteger)hash { return _temp ? [_temp hash] : (NSUInteger)_pk ^ ([[_entity name] hash] << 7); }
- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@>", [super description], [[self URIRepresentation] absoluteString]];
}
@end

/* ---- the accessor registry --------------------------------------------------------------- */

typedef enum {
    K_GET, K_SET, K_PGET, K_PSET, K_ADDOBJ, K_REMOBJ, K_ADDSET, K_REMSET, K_INSAT, K_REMAT, K_REPAT, K_INSIDX,
    K_REMIDX
} CDAccessorKind;

static pthread_mutex_t reg_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *sel_keys;         /* selector name -> @[kind, key] */
static NSMutableDictionary *class_sels;       /* class name -> selector names */
static NSMutableDictionary *class_entities;   /* class name -> entities */
static NSMutableSet *registered;              /* entities done (as NSValue) */

static NSString *capitalized(NSString *key)
{
    return [key length] ? [[[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]]
                        : key;
}

/* The getter or setter name a declared property gives (G or S in its attributes). */
static NSString *declared_accessor(Class cls, NSString *key, char which)
{
    objc_property_t p = cls ? class_getProperty(cls, [key UTF8String]) : NULL;
    const char *a = p ? property_getAttributes(p) : NULL;
    for (const char *s = a; s && *s; s++)
        if ((s == a || s[-1] == ',') && *s == which) {
            const char *e = strchr(s, ',');
            return [[[NSString alloc] initWithBytes:s + 1 length:e ? (NSUInteger)(e - s - 1) : strlen(s + 1)
                                           encoding:NSUTF8StringEncoding] autorelease];
        }
    return nil;
}

static void add_sel(NSMutableSet *sels, NSString *name, CDAccessorKind kind, NSString *key)
{
    [sels addObject:name];
    if (![sel_keys objectForKey:name])
        [sel_keys setObject:@[ @(kind), key ] forKey:name];
}

void CDRegisterEntity(NSEntityDescription *entity)
{
    if (!entity)
        return;
    NSString *className = [entity managedObjectClassName];
    Class cls = [entity cd_class];
    pthread_mutex_lock(&reg_lock);
    if (!sel_keys) {
        sel_keys = [[NSMutableDictionary alloc] init];
        class_sels = [[NSMutableDictionary alloc] init];
        class_entities = [[NSMutableDictionary alloc] init];
        registered = [[NSMutableSet alloc] init];
    }
    NSValue *v = [NSValue valueWithPointer:entity];
    if ([registered containsObject:v]) {
        pthread_mutex_unlock(&reg_lock);
        return;
    }
    [registered addObject:v];
    [entity retain];   /* registered entities stay, as their classes do */
    NSString *name = NSStringFromClass(cls);
    if (![className isEqualToString:name])
        className = name;
    NSMutableSet *sels = [class_sels objectForKey:className];
    if (!sels)
        [class_sels setObject:(sels = [NSMutableSet set]) forKey:className];
    NSMutableArray *ents = [class_entities objectForKey:className];
    if (!ents)
        [class_entities setObject:(ents = [NSMutableArray array]) forKey:className];
    [ents addObject:entity];
    for (NSPropertyDescription *p in [entity cd_allProperties]) {
        NSString *key = [p name], *Key = capitalized(key);
        if (![key length])
            continue;
        add_sel(sels, declared_accessor(cls, key, 'G') ?: key, K_GET, key);
        add_sel(sels, declared_accessor(cls, key, 'S') ?: [NSString stringWithFormat:@"set%@:", Key], K_SET, key);
        add_sel(sels, [@"primitive" stringByAppendingString:Key], K_PGET, key);
        add_sel(sels, [NSString stringWithFormat:@"setPrimitive%@:", Key], K_PSET, key);
        if ([p isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)p isToMany]) {
            add_sel(sels, [NSString stringWithFormat:@"add%@Object:", Key], K_ADDOBJ, key);
            add_sel(sels, [NSString stringWithFormat:@"remove%@Object:", Key], K_REMOBJ, key);
            add_sel(sels, [NSString stringWithFormat:@"add%@:", Key], K_ADDSET, key);
            add_sel(sels, [NSString stringWithFormat:@"remove%@:", Key], K_REMSET, key);
            if ([(NSRelationshipDescription *)p isOrdered]) {
                add_sel(sels, [NSString stringWithFormat:@"insertObject:in%@AtIndex:", Key], K_INSAT, key);
                add_sel(sels, [NSString stringWithFormat:@"removeObjectFrom%@AtIndex:", Key], K_REMAT, key);
                add_sel(sels, [NSString stringWithFormat:@"replaceObjectIn%@AtIndex:withObject:", Key], K_REPAT, key);
                add_sel(sels, [NSString stringWithFormat:@"insert%@:atIndexes:", Key], K_INSIDX, key);
                add_sel(sels, [NSString stringWithFormat:@"remove%@AtIndexes:", Key], K_REMIDX, key);
            }
        }
    }
    pthread_mutex_unlock(&reg_lock);
}

void CDRegisterModel(NSManagedObjectModel *model)
{
    for (NSEntityDescription *e in [model entities])
        CDRegisterEntity(e);
}

NSEntityDescription *CDEntityForClass(Class cls)
{
    pthread_mutex_lock(&reg_lock);
    NSArray *ents = [[[class_entities objectForKey:NSStringFromClass(cls)] retain] autorelease];
    pthread_mutex_unlock(&reg_lock);
    return [ents lastObject];
}

/* The accessor a selector stands for in this class or one above it. */
static NSArray *accessor_for(Class cls, NSString *selName, Class *owner)
{
    NSArray *found = nil;
    pthread_mutex_lock(&reg_lock);
    for (Class c = cls; c && !found; c = class_getSuperclass(c))
        if ([[class_sels objectForKey:NSStringFromClass(c)] containsObject:selName]) {
            found = [[[sel_keys objectForKey:selName] retain] autorelease];
            if (owner)
                *owner = c;
        }
    pthread_mutex_unlock(&reg_lock);
    return found;
}

static NSString *key_for(SEL sel)
{
    pthread_mutex_lock(&reg_lock);
    NSString *k = [[[[sel_keys objectForKey:NSStringFromSelector(sel)] objectAtIndex:1] retain] autorelease];
    pthread_mutex_unlock(&reg_lock);
    return k;
}

/* ---- NSManagedObject ----------------------------------------------------------------------- */

@interface NSManagedObject ()
- (id)cd_get:(NSString *)key;
- (void)cd_set:(id)value forKey:(NSString *)key;
- (id)cd_primitive:(NSString *)key;
- (void)cd_setPrimitive:(id)value forKey:(NSString *)key;
- (void)cd_toMany:(NSString *)key add:(NSArray *)adds remove:(NSArray *)removes;
- (void)cd_toMany:(NSString *)key replaceWith:(id)collection;
- (void)cd_fire;
@end

/* What mutableSetValueForKey: and mutableOrderedSetValueForKey: answer for a modeled
 * to-many relationship: changes go through the object, so that they are recorded. */
@interface CDMutableSetProxy : NSMutableSet {
    NSManagedObject *_object;
    NSString *_key;
}
- (id)cd_initWithObject:(NSManagedObject *)object key:(NSString *)key;
@end

@interface CDMutableOrderedSetProxy : NSMutableOrderedSet {
    NSManagedObject *_object;
    NSString *_key;
}
- (id)cd_initWithObject:(NSManagedObject *)object key:(NSString *)key;
@end

/* The accessors themselves. */
static id acc_get(NSManagedObject *self, SEL _cmd) { return [self cd_get:key_for(_cmd)]; }
static void acc_set(NSManagedObject *self, SEL _cmd, id v) { [self cd_set:v forKey:key_for(_cmd)]; }
static id acc_pget(NSManagedObject *self, SEL _cmd) { return [self cd_primitive:key_for(_cmd)]; }
static void acc_pset(NSManagedObject *self, SEL _cmd, id v) { [self cd_setPrimitive:v forKey:key_for(_cmd)]; }
static void acc_addobj(NSManagedObject *self, SEL _cmd, id o)
{
    if (o)
        [self cd_toMany:key_for(_cmd) add:@[ o ] remove:nil];
}
static void acc_remobj(NSManagedObject *self, SEL _cmd, id o)
{
    if (o)
        [self cd_toMany:key_for(_cmd) add:nil remove:@[ o ]];
}
static NSArray *as_array(id c)
{
    if ([c isKindOfClass:[NSSet class]])
        return [c allObjects];
    if ([c isKindOfClass:[NSOrderedSet class]])
        return [c array];
    return [c isKindOfClass:[NSArray class]] ? c : @[];
}
static void acc_addset(NSManagedObject *self, SEL _cmd, id s) { [self cd_toMany:key_for(_cmd) add:as_array(s) remove:nil]; }
static void acc_remset(NSManagedObject *self, SEL _cmd, id s) { [self cd_toMany:key_for(_cmd) add:nil remove:as_array(s)]; }
static NSMutableOrderedSet *ordered_copy(NSManagedObject *self, NSString *key)
{
    id cur = [self cd_get:key];
    return cur ? [[cur mutableCopy] autorelease] : [NSMutableOrderedSet orderedSet];
}
static void acc_insat(NSManagedObject *self, SEL _cmd, id o, NSUInteger i)
{
    NSString *key = key_for(_cmd);
    NSMutableOrderedSet *m = ordered_copy(self, key);
    [m insertObject:o atIndex:i];
    [self cd_toMany:key replaceWith:m];
}
static void acc_remat(NSManagedObject *self, SEL _cmd, NSUInteger i)
{
    NSString *key = key_for(_cmd);
    NSMutableOrderedSet *m = ordered_copy(self, key);
    [m removeObjectAtIndex:i];
    [self cd_toMany:key replaceWith:m];
}
static void acc_repat(NSManagedObject *self, SEL _cmd, NSUInteger i, id o)
{
    NSString *key = key_for(_cmd);
    NSMutableOrderedSet *m = ordered_copy(self, key);
    [m replaceObjectAtIndex:i withObject:o];
    [self cd_toMany:key replaceWith:m];
}
static void acc_insidx(NSManagedObject *self, SEL _cmd, NSArray *objs, NSIndexSet *idx)
{
    NSString *key = key_for(_cmd);
    NSMutableOrderedSet *m = ordered_copy(self, key);
    [m insertObjects:objs atIndexes:idx];
    [self cd_toMany:key replaceWith:m];
}
static void acc_remidx(NSManagedObject *self, SEL _cmd, NSIndexSet *idx)
{
    NSString *key = key_for(_cmd);
    NSMutableOrderedSet *m = ordered_copy(self, key);
    [m removeObjectsAtIndexes:idx];
    [self cd_toMany:key replaceWith:m];
}

/* Scalar getters and setters, for properties declared with a C type. */
static id scalar_value(NSManagedObject *self, SEL _cmd) { return [self cd_get:key_for(_cmd)]; }
#define SCALAR(type, name, conv)                                                                                      \
    static type get_##name(NSManagedObject *self, SEL _cmd)                                                          \
    {                                                                                                                \
        id v = scalar_value(self, _cmd);                                                                             \
        return [v respondsToSelector:@selector(conv)] ? (type)[v conv] : (type)0;                                    \
    }                                                                                                                \
    static void set_##name(NSManagedObject *self, SEL _cmd, type x) { [self cd_set:@(x) forKey:key_for(_cmd)]; }
SCALAR(char, c, charValue)
SCALAR(unsigned char, C, unsignedCharValue)
SCALAR(bool, B, boolValue)
SCALAR(short, s, shortValue)
SCALAR(unsigned short, S, unsignedShortValue)
SCALAR(int, i, intValue)
SCALAR(unsigned int, I, unsignedIntValue)
SCALAR(long long, q, longLongValue)
SCALAR(unsigned long long, Q, unsignedLongLongValue)
SCALAR(float, f, floatValue)
/* A double may stand for a date, as seconds since the reference date. */
static double get_d(NSManagedObject *self, SEL _cmd)
{
    id v = scalar_value(self, _cmd);
    if ([v isKindOfClass:[NSDate class]])
        return [v timeIntervalSinceReferenceDate];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}
static void set_d(NSManagedObject *self, SEL _cmd, double x)
{
    NSString *key = key_for(_cmd);
    NSAttributeDescription *a = (id)[[self entity] cd_propertyNamed:key];
    if ([a isKindOfClass:[NSAttributeDescription class]] && [a attributeType] == NSDateAttributeType)
        [self cd_set:[NSDate dateWithTimeIntervalSinceReferenceDate:x] forKey:key];
    else
        [self cd_set:@(x) forKey:key];
}

static const void *our_imps[] = {
    (void *)acc_get,   (void *)acc_set,    (void *)acc_pget,   (void *)acc_pset,   (void *)acc_addobj,
    (void *)acc_remobj, (void *)acc_addset, (void *)acc_remset, (void *)acc_insat,  (void *)acc_remat,
    (void *)acc_repat, (void *)acc_insidx, (void *)acc_remidx, (void *)get_c,      (void *)set_c,
    (void *)get_C,     (void *)set_C,      (void *)get_B,      (void *)set_B,      (void *)get_s,
    (void *)set_s,     (void *)get_S,      (void *)set_S,      (void *)get_i,      (void *)set_i,
    (void *)get_I,     (void *)set_I,      (void *)get_q,      (void *)set_q,      (void *)get_Q,
    (void *)set_Q,     (void *)get_f,      (void *)set_f,      (void *)get_d,      (void *)set_d,
};

static BOOL is_our_imp(IMP imp)
{
    for (size_t i = 0; i < sizeof our_imps / sizeof *our_imps; i++)
        if ((const void *)imp == our_imps[i])
            return YES;
    return NO;
}

/* A class's own accessor (not one made here) for a selector. */
static BOOL has_custom_accessor(Class cls, NSString *selName)
{
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(selName));
    return m && !is_our_imp(method_getImplementation(m));
}

/* The type a declared property has (the first letter of its type encoding), or '@'. */
static char declared_type(Class cls, NSString *key)
{
    objc_property_t p = class_getProperty(cls, [key UTF8String]);
    const char *a = p ? property_getAttributes(p) : NULL;
    return a && a[0] == 'T' && a[1] ? a[1] : '@';
}

@implementation NSManagedObject {
    NSEntityDescription *_entity;
    NSManagedObjectContext *_context;   /* not retained: the context keeps its objects */
    NSManagedObjectID *_oid;
    NSMutableDictionary *_values;
    NSMutableArray *_changeStack;       /* @[key, old value] from willChange..., for didChange... */
    NSMutableSet *_transientChanged;
    BOOL _fault, _deletedFlag, _insertedFlag, _firing;
    int _quiet;                         /* will/didChange... only notify observers */
}

+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    NSString *name = NSStringFromSelector(sel);
    Class owner = Nil;
    NSArray *acc = accessor_for(self, name, &owner);
    if (!acc)
        return [super resolveInstanceMethod:sel];
    CDAccessorKind kind = (CDAccessorKind)[[acc objectAtIndex:0] intValue];
    NSString *key = [acc objectAtIndex:1];
    IMP imp = NULL;
    const char *types = "@@:";
    char t = declared_type(owner, key);
    switch (kind) {
    case K_GET:
    case K_SET: {
        BOOL get = kind == K_GET;
        switch (t) {
#define T(ch, n, enc)                                                                                                 \
    case ch:                                                                                                          \
        imp = get ? (IMP)get_##n : (IMP)set_##n;                                                                      \
        types = get ? enc "@:" : "v@:" enc;                                                                           \
        break;
            T('c', c, "c")
            T('C', C, "C")
            T('B', B, "B")
            T('s', s, "s")
            T('S', S, "S")
            T('i', i, "i")
            T('I', I, "I")
            T('l', i, "i")
            T('L', I, "I")
            T('q', q, "q")
            T('Q', Q, "Q")
            T('f', f, "f")
            T('d', d, "d")
#undef T
        default:
            imp = get ? (IMP)acc_get : (IMP)acc_set;
            types = get ? "@@:" : "v@:@";
        }
        break;
    }
    case K_PGET: imp = (IMP)acc_pget, types = "@@:"; break;
    case K_PSET: imp = (IMP)acc_pset, types = "v@:@"; break;
    case K_ADDOBJ: imp = (IMP)acc_addobj, types = "v@:@"; break;
    case K_REMOBJ: imp = (IMP)acc_remobj, types = "v@:@"; break;
    case K_ADDSET: imp = (IMP)acc_addset, types = "v@:@"; break;
    case K_REMSET: imp = (IMP)acc_remset, types = "v@:@"; break;
    case K_INSAT: imp = (IMP)acc_insat, types = "v@:@Q"; break;
    case K_REMAT: imp = (IMP)acc_remat, types = "v@:Q"; break;
    case K_REPAT: imp = (IMP)acc_repat, types = "v@:Q@"; break;
    case K_INSIDX: imp = (IMP)acc_insidx, types = "v@:@@"; break;
    case K_REMIDX: imp = (IMP)acc_remidx, types = "v@:@"; break;
    }
    class_addMethod(owner, sel, imp, types);
    return YES;
}

/* Modeled keys announce their own changes (the setters send the notifications). */
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    for (Class c = self; c; c = class_getSuperclass(c)) {
        pthread_mutex_lock(&reg_lock);
        NSArray *ents = [[[class_entities objectForKey:NSStringFromClass(c)] retain] autorelease];
        pthread_mutex_unlock(&reg_lock);
        for (NSEntityDescription *e in ents)
            if ([e cd_propertyNamed:key])
                return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}

+ (BOOL)contextShouldIgnoreUnmodeledPropertyChanges { return YES; }
+ (NSEntityDescription *)entity { return CDEntityForClass(self); }
+ (NSFetchRequest *)fetchRequest
{
    NSEntityDescription *e = [self entity];
    NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:[e name] ?: NSStringFromClass(self)];
    if (e)
        [r setEntity:e];
    return r;
}

+ (id)cd_faultWithEntity:(NSEntityDescription *)entity objectID:(NSManagedObjectID *)oid
                 context:(NSManagedObjectContext *)context
{
    CDRegisterEntity(entity);
    NSManagedObject *o = [[[entity cd_class] alloc] cd_initWithEntity:entity];
    o->_oid = [oid retain];
    o->_context = context;
    o->_fault = YES;
    return [o autorelease];
}

- (instancetype)cd_initWithEntity:(NSEntityDescription *)entity
{
    if ((self = [super init])) {
        _entity = [entity retain];
        _values = [[NSMutableDictionary alloc] init];
        _changeStack = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)cd_setDefaults
{
    for (NSPropertyDescription *p in [_entity cd_allProperties])
        if ([p isKindOfClass:[NSAttributeDescription class]] && [(NSAttributeDescription *)p defaultValue])
            [_values setObject:[(NSAttributeDescription *)p defaultValue] forKey:[p name]];
}

- (id)initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context
{
    if (!entity) {
        [self release];
        CDRaise(NSInvalidArgumentException, @"An NSManagedObject of class '%@' must have a valid NSEntityDescription.",
                NSStringFromClass([self class]));
    }
    if ([entity isAbstract]) {
        [self release];
        CDRaise(NSInternalInconsistencyException, @"Cannot create objects from abstract entity (%@)", [entity name]);
    }
    CDRegisterEntity(entity);
    if ((self = [self cd_initWithEntity:entity])) {
        _oid = [[NSManagedObjectID cd_temporaryIDForEntity:entity] retain];
        [self cd_setDefaults];
        if (context)
            [context insertObject:self];
    }
    return self;
}

- (instancetype)initWithContext:(NSManagedObjectContext *)context
{
    NSEntityDescription *found = nil;
    for (NSEntityDescription *e in [[[context persistentStoreCoordinator] managedObjectModel] entities])
        if ([e cd_class] == [self class]) {
            if (found)
                CDRaise(NSInternalInconsistencyException,
                        @"Multiple entities claim the class '%@'; use initWithEntity:insertIntoManagedObjectContext:",
                        NSStringFromClass([self class]));
            found = e;
        }
    return [self initWithEntity:found ?: [[self class] entity] insertIntoManagedObjectContext:context];
}

- (instancetype)init
{
    NSEntityDescription *e = [[self class] entity];
    if (!e) {
        [self release];
        CDRaise(NSInternalInconsistencyException, @"Failed to call designated initializer on NSManagedObject class '%@'",
                NSStringFromClass([self class]));
    }
    return [self initWithEntity:e insertIntoManagedObjectContext:nil];
}

- (void)dealloc
{
    [_entity release];
    [_oid release];
    [_values release];
    [_changeStack release];
    [_transientChanged release];
    [super dealloc];
}

- (NSManagedObjectContext *)managedObjectContext { return _context; }
- (NSEntityDescription *)entity { return _entity; }
- (NSManagedObjectID *)objectID { return _oid; }
- (void)cd_setObjectID:(NSManagedObjectID *)oid
{
    [_oid autorelease];
    _oid = [oid retain];
}
- (void)cd_setContext:(NSManagedObjectContext *)context { _context = context; }
- (void)cd_setDeletedFlag:(BOOL)flag { _deletedFlag = flag; }
- (void)cd_setInsertedFlag:(BOOL)flag { _insertedFlag = flag; }
- (BOOL)isInserted { return _insertedFlag; }
- (BOOL)isDeleted { return _deletedFlag; }
- (BOOL)isUpdated { return _context && [[_context updatedObjects] containsObject:self]; }
- (BOOL)isFault { return _fault; }
- (BOOL)cd_isFaultOrNil { return _fault; }
- (NSUInteger)faultingState { return _fault ? 1 : 0; }
- (BOOL)hasChanges { return _insertedFlag || _deletedFlag || [self isUpdated]; }
- (BOOL)hasPersistentChangedValues { return [[self cd_changedStorableValues] count] > 0; }
- (BOOL)hasFaultForRelationshipNamed:(NSString *)key
{
    if (_fault)
        return YES;
    return [_values objectForKey:key] == nil &&
           [[_entity cd_propertyNamed:key] isKindOfClass:[NSRelationshipDescription class]] &&
           [(NSRelationshipDescription *)[_entity cd_propertyNamed:key] isToMany];
}
- (NSArray *)objectIDsForRelationshipNamed:(NSString *)key
{
    id v = [self cd_primitive:key];
    if ([v isKindOfClass:[NSManagedObject class]])
        return @[ [v objectID] ];
    return [as_array(v) valueForKey:@"objectID"];
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    return [other isKindOfClass:[NSManagedObjectID class]] && [_oid isEqual:other];
}

/* ---- the life of an object ---- */

- (void)awakeFromFetch {}
- (void)awakeFromInsert {}
- (void)awakeFromSnapshotEvents:(NSSnapshotEventType)flags {}
- (void)prepareForDeletion {}
- (void)willSave {}
- (void)didSave {}
- (void)willTurnIntoFault {}
- (void)didTurnIntoFault {}

- (void)cd_fire
{
    if (!_fault || _firing)
        return;
    if (!_context) {
        _fault = NO;
        return;
    }
    _firing = YES;
    CDSnapshot *s = [_context cd_snapshotForObject:self];
    _firing = NO;
    if (!s)
        CDRaise(NSObjectInaccessibleException, @"CoreData could not fulfill a fault for '%@'", _oid);
    [self cd_fillFromSnapshot:s];
    [self awakeFromFetch];
}

- (void)cd_fillFromSnapshot:(CDSnapshot *)s
{
    _fault = NO;
    [_values removeAllObjects];
    for (NSPropertyDescription *p in [_entity cd_allProperties]) {
        NSString *key = [p name];
        if ([p isTransient]) {
            if ([p isKindOfClass:[NSAttributeDescription class]] && [(NSAttributeDescription *)p defaultValue])
                [_values setObject:[(NSAttributeDescription *)p defaultValue] forKey:key];
            continue;
        }
        id v = [s->values objectForKey:key];
        if (!v || v == [NSNull null])
            continue;
        if ([p isKindOfClass:[NSAttributeDescription class]])
            [_values setObject:v forKey:key];
        else if ([(NSRelationshipDescription *)p isToMany]) {
            NSMutableArray *objs = [NSMutableArray array];
            for (NSManagedObjectID *oid in v)
                [objs addObject:[_context objectWithID:oid]];
            [_values setObject:[(NSRelationshipDescription *)p isOrdered] ? (id)[NSOrderedSet orderedSetWithArray:objs]
                                                                           : (id)[NSSet setWithArray:objs]
                        forKey:key];
        } else
            [_values setObject:[_context objectWithID:v] forKey:key];
    }
}

- (void)cd_turnIntoFault
{
    if (_fault)
        return;
    [self willTurnIntoFault];
    [_values removeAllObjects];
    [_transientChanged removeAllObjects];
    _fault = YES;
    [self didTurnIntoFault];
}

/* ---- values ---- */

- (NSPropertyDescription *)cd_property:(NSString *)key { return [_entity cd_propertyNamed:key]; }

- (void)willAccessValueForKey:(NSString *)key
{
    if (_fault)
        [self cd_fire];
}
- (void)didAccessValueForKey:(NSString *)key {}

- (id)cd_primitive:(NSString *)key
{
    [self cd_fire];
    id v = [_values objectForKey:key];
    if (v)
        return v;
    NSRelationshipDescription *r = (id)[self cd_property:key];
    if (![r isKindOfClass:[NSRelationshipDescription class]] || ![r isToMany])
        return nil;
    /* A to-many relationship is read when first used. */
    NSMutableArray *objs = [NSMutableArray array];
    NSArray *ids = nil;
    if (_context && !_insertedFlag)
        ids = [_context cd_relatedIDsForObject:self key:key];
    for (NSManagedObjectID *oid in ids) {
        NSManagedObject *o = [_context objectWithID:oid];
        if (o)
            [objs addObject:o];
    }
    v = [r isOrdered] ? (id)[NSOrderedSet orderedSetWithArray:objs] : (id)[NSSet setWithArray:objs];
    [_values setObject:v forKey:key];
    if (_context && ids)
        [_context cd_noteLoadedIDs:ids forObject:self key:key];
    return v;
}

- (void)cd_setPrimitive:(id)value forKey:(NSString *)key
{
    [self cd_fire];
    NSRelationshipDescription *r = (id)[self cd_property:key];
    if ([r isKindOfClass:[NSRelationshipDescription class]] && [r isToMany] && value) {
        if ([r isOrdered] && ![value isKindOfClass:[NSOrderedSet class]])
            value = [NSOrderedSet orderedSetWithArray:as_array(value)];
        else if (![r isOrdered] && ![value isKindOfClass:[NSSet class]])
            value = [NSSet setWithArray:as_array(value)];
        else
            value = [[value copy] autorelease];
    }
    if (value && value != [NSNull null])
        [_values setObject:value forKey:key];
    else if ([r isKindOfClass:[NSRelationshipDescription class]] && [r isToMany])
        [_values setObject:[r isOrdered] ? (id)[NSOrderedSet orderedSet] : (id)[NSSet set] forKey:key];
    else
        [_values removeObjectForKey:key];
}

- (id)primitiveValueForKey:(NSString *)key
{
    if (![self cd_property:key])
        return [super valueForKey:key];
    return [self cd_primitive:key];
}

- (void)setPrimitiveValue:(id)value forKey:(NSString *)key
{
    if (![self cd_property:key]) {
        [super setValue:value forKey:key];
        return;
    }
    [self cd_setPrimitive:value forKey:key];
}

- (id)cd_get:(NSString *)key
{
    [self willAccessValueForKey:key];
    id v = [[[self cd_primitive:key] retain] autorelease];
    [self didAccessValueForKey:key];
    return v;
}

- (id)valueForKey:(NSString *)key
{
    if (![self cd_property:key] || has_custom_accessor([self class], key))
        return [super valueForKey:key];
    return [self cd_get:key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
    if (![self cd_property:key] ||
        has_custom_accessor([self class], [NSString stringWithFormat:@"set%@:", capitalized(key)]))
        [super setValue:value forKey:key];
    else
        [self cd_set:value forKey:key];
}

- (void)cd_checkRelated:(id)object key:(NSString *)key
{
    if (!object)
        return;
    if (![object isKindOfClass:[NSManagedObject class]])
        CDRaise(NSInvalidArgumentException,
                @"Unacceptable type of value for to-one relationship: property = \"%@\"; desired type = %@; given type = "
                @"%@",
                key, [[[(NSRelationshipDescription *)[self cd_property:key] destinationEntity] name] description],
                NSStringFromClass([object class]));
    NSManagedObjectContext *theirs = [object managedObjectContext];
    if (_context && theirs && theirs != _context)
        CDRaise(NSInvalidArgumentException,
                @"Illegal attempt to establish a relationship '%@' between objects in different contexts", key);
}

/* Sets a value the way an accessor does: notifications, and the inverse kept. */
- (void)cd_set:(id)value forKey:(NSString *)key
{
    if (value == [NSNull null])
        value = nil;
    NSPropertyDescription *p = [self cd_property:key];
    if ([p isKindOfClass:[NSRelationshipDescription class]]) {
        NSRelationshipDescription *r = (id)p;
        if ([r isToMany]) {
            [self cd_toMany:key replaceWith:value];
            return;
        }
        [self cd_checkRelated:value key:key];
        NSManagedObject *old = [[[self cd_primitive:key] retain] autorelease];
        if (old == value)
            return;
        [self willChangeValueForKey:key];
        [self cd_setPrimitive:value forKey:key];
        if ([_context cd_maintainsInverses] || !_context)
            [self cd_fixInverseOf:r old:old new:value];
        [self didChangeValueForKey:key];
        return;
    }
    [self willChangeValueForKey:key];
    [self cd_setPrimitive:value forKey:key];
    [self didChangeValueForKey:key];
}

/* The other side of a relationship, set without touching this side again. */
- (void)cd_inverseSetToOne:(NSString *)key value:(NSManagedObject *)value
{
    if ([self cd_primitive:key] == value)
        return;
    [self willChangeValueForKey:key];
    [self cd_setPrimitive:value forKey:key];
    [self didChangeValueForKey:key];
}

- (void)cd_inverseToMany:(NSString *)key add:(NSManagedObject *)add remove:(NSManagedObject *)remove
{
    id cur = [self cd_primitive:key];
    if (add && [cur containsObject:add])
        add = nil;
    if (remove && ![cur containsObject:remove])
        remove = nil;
    if (!add && !remove)
        return;
    NSSet *objs = [NSSet setWithObject:add ?: remove];
    BOOL ordered = [cur isKindOfClass:[NSOrderedSet class]];
    if (ordered)
        [self willChangeValueForKey:key];
    else
        [self willChangeValueForKey:key
                    withSetMutation:add ? NSKeyValueUnionSetMutation : NSKeyValueMinusSetMutation
                       usingObjects:objs];
    id m = [[cur mutableCopy] autorelease];
    if (add)
        [m addObject:add];
    else
        [m removeObject:remove];
    [self cd_setPrimitive:m forKey:key];
    if (ordered)
        [self didChangeValueForKey:key];
    else
        [self didChangeValueForKey:key
                   withSetMutation:add ? NSKeyValueUnionSetMutation : NSKeyValueMinusSetMutation
                      usingObjects:objs];
}

/* After self.r changed from old to new: the inverse on both. */
- (void)cd_fixInverseOf:(NSRelationshipDescription *)r old:(NSManagedObject *)old new:(NSManagedObject *)new
{
    NSRelationshipDescription *inv = [r inverseRelationship];
    if (!inv)
        return;
    NSString *ik = [inv name];
    if (old) {
        if ([inv isToMany])
            [old cd_inverseToMany:ik add:nil remove:self];
        else if ([old cd_primitive:ik] == self)
            [old cd_inverseSetToOne:ik value:nil];
    }
    if (new) {
        if ([inv isToMany])
            [new cd_inverseToMany:ik add:self remove:nil];
        else {
            NSManagedObject *partner = [new cd_primitive:ik];
            if (partner && partner != self) {
                /* one-to-one: the new partner's old partner lets go */
                if ([r isToMany])
                    [partner cd_inverseToMany:[r name] add:nil remove:new];
                else
                    [partner cd_inverseSetToOne:[r name] value:nil];
            }
            [new cd_inverseSetToOne:ik value:self];
        }
    }
}

- (void)cd_toMany:(NSString *)key add:(NSArray *)adds remove:(NSArray *)removes
{
    NSRelationshipDescription *r = (id)[self cd_property:key];
    id cur = [self cd_primitive:key];
    NSMutableArray *added = [NSMutableArray array], *removed = [NSMutableArray array];
    for (id o in adds) {
        [self cd_checkRelated:o key:key];
        if (![cur containsObject:o] && ![added containsObject:o])
            [added addObject:o];
    }
    for (id o in removes)
        if ([cur containsObject:o] && ![removed containsObject:o])
            [removed addObject:o];
    if (![added count] && ![removed count])
        return;
    BOOL ordered = [r isOrdered];
    NSKeyValueSetMutationKind kind = [removed count] ? NSKeyValueMinusSetMutation : NSKeyValueUnionSetMutation;
    BOOL setting = ordered || ([added count] && [removed count]);
    NSSet *changed = [NSSet setWithArray:[added count] ? added : removed];
    if (setting)
        [self willChangeValueForKey:key];
    else
        [self willChangeValueForKey:key withSetMutation:kind usingObjects:changed];
    id m = [[cur mutableCopy] autorelease];
    for (id o in removed)
        [m removeObject:o];
    for (id o in added)
        [m addObject:o];
    [self cd_setPrimitive:m forKey:key];
    if ([_context cd_maintainsInverses] || !_context) {
        for (NSManagedObject *o in removed)
            [self cd_fixToManyInverseOf:r object:o added:NO];
        for (NSManagedObject *o in added)
            [self cd_fixToManyInverseOf:r object:o added:YES];
    }
    if (setting)
        [self didChangeValueForKey:key];
    else
        [self didChangeValueForKey:key withSetMutation:kind usingObjects:changed];
}

- (void)cd_toMany:(NSString *)key replaceWith:(id)collection
{
    NSRelationshipDescription *r = (id)[self cd_property:key];
    NSArray *want = as_array(collection);
    id cur = [self cd_primitive:key];
    NSMutableArray *removes = [NSMutableArray array];
    for (id o in as_array(cur))
        if (![want containsObject:o])
            [removes addObject:o];
    if (![r isOrdered]) {
        [self cd_toMany:key add:want remove:removes];
        return;
    }
    /* ordered: the new order, with inverses for what came and went */
    NSMutableArray *adds = [NSMutableArray array];
    for (id o in want) {
        [self cd_checkRelated:o key:key];
        if (![cur containsObject:o])
            [adds addObject:o];
    }
    NSOrderedSet *next = [NSOrderedSet orderedSetWithArray:want];
    if ([next isEqual:cur])
        return;
    [self willChangeValueForKey:key];
    [self cd_setPrimitive:next forKey:key];
    if ([_context cd_maintainsInverses] || !_context) {
        for (NSManagedObject *o in removes)
            [self cd_fixToManyInverseOf:r object:o added:NO];
        for (NSManagedObject *o in adds)
            [self cd_fixToManyInverseOf:r object:o added:YES];
    }
    [self didChangeValueForKey:key];
}

/* After o was added to or removed from self.r (a to-many relationship). */
- (void)cd_fixToManyInverseOf:(NSRelationshipDescription *)r object:(NSManagedObject *)o added:(BOOL)added
{
    NSRelationshipDescription *inv = [r inverseRelationship];
    if (!inv)
        return;
    NSString *ik = [inv name];
    if ([inv isToMany]) {
        if (added)
            [o cd_inverseToMany:ik add:self remove:nil];
        else
            [o cd_inverseToMany:ik add:nil remove:self];
        return;
    }
    if (!added) {
        if ([o cd_primitive:ik] == self)
            [o cd_inverseSetToOne:ik value:nil];
        return;
    }
    NSManagedObject *prev = [o cd_primitive:ik];
    if (prev && prev != self)
        [prev cd_inverseToMany:[r name] add:nil remove:o];
    [o cd_inverseSetToOne:ik value:self];
}

/* What undo and a parent's merge use: a value set with notifications, nothing more. */
- (void)cd_restoreValue:(id)value forKey:(NSString *)key
{
    if (value == [NSNull null])
        value = nil;
    [self willChangeValueForKey:key];
    [self cd_setPrimitive:value forKey:key];
    [self didChangeValueForKey:key];
}

- (void)cd_applyStoredValue:(id)value forKey:(NSString *)key
{
    NSPropertyDescription *p = [self cd_property:key];
    if (value == [NSNull null])
        value = nil;
    if ([p isKindOfClass:[NSRelationshipDescription class]]) {
        if ([(NSRelationshipDescription *)p isToMany]) {
            NSMutableArray *objs = [NSMutableArray array];
            for (NSManagedObjectID *oid in value)
                [objs addObject:[_context objectWithID:oid]];
            value = objs;
        } else if (value)
            value = [_context objectWithID:value];
    }
    [self cd_restoreValue:value forKey:key];
}

/* ---- change notifications: the context records changes here ---- */

- (BOOL)cd_records:(NSString *)key { return !_quiet && [self cd_property:key] != nil; }

- (void)cd_pushOld:(NSString *)key
{
    [self cd_fire];
    id old = [_values objectForKey:key];
    NSPropertyDescription *p = [self cd_property:key];
    if (!old && [p isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)p isToMany])
        old = [self cd_primitive:key];
    [_changeStack addObject:@[ key, old ?: [NSNull null] ]];
}

- (void)cd_popOld:(NSString *)key
{
    for (NSInteger i = (NSInteger)[_changeStack count] - 1; i >= 0; i--) {
        NSArray *e = [_changeStack objectAtIndex:(NSUInteger)i];
        if (![[e objectAtIndex:0] isEqualToString:key])
            continue;
        id old = [[[e objectAtIndex:1] retain] autorelease];
        [_changeStack removeObjectAtIndex:(NSUInteger)i];
        if (old == [NSNull null])
            old = nil;
        id now = [_values objectForKey:key];
        if (CDEqual(old, now))
            return;
        if ([[self cd_property:key] isTransient]) {
            if (!_transientChanged)
                _transientChanged = [[NSMutableSet alloc] init];
            [_transientChanged addObject:key];
        }
        [_context cd_object:self didChangeKey:key from:old];
        return;
    }
}

- (void)willChangeValueForKey:(NSString *)key
{
    if ([self cd_records:key])
        [self cd_pushOld:key];
    [super willChangeValueForKey:key];
}
- (void)didChangeValueForKey:(NSString *)key
{
    if ([self cd_records:key])
        [self cd_popOld:key];
    [super didChangeValueForKey:key];
}
- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)m usingObjects:(NSSet *)objs
{
    if ([self cd_records:key])
        [self cd_pushOld:key];
    [super willChangeValueForKey:key withSetMutation:m usingObjects:objs];
}
- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)m usingObjects:(NSSet *)objs
{
    if ([self cd_records:key])
        [self cd_popOld:key];
    [super didChangeValueForKey:key withSetMutation:m usingObjects:objs];
}
- (void)willChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    if ([self cd_records:key])
        [self cd_pushOld:key];
    [super willChange:kind valuesAtIndexes:indexes forKey:key];
}
- (void)didChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    if ([self cd_records:key])
        [self cd_popOld:key];
    [super didChange:kind valuesAtIndexes:indexes forKey:key];
}

/* Tells observers every loaded key may have changed, around block (a refresh). */
- (void)cd_notifyAllAround:(void (^)(void))block
{
    NSArray *keys = [_values allKeys];
    _quiet++;
    for (NSString *k in keys)
        [self willChangeValueForKey:k];
    block();
    for (NSString *k in [keys reverseObjectEnumerator])
        [self didChangeValueForKey:k];
    _quiet--;
}

/* ---- to-many proxies ---- */

- (NSMutableSet *)mutableSetValueForKey:(NSString *)key
{
    NSRelationshipDescription *r = (id)[self cd_property:key];
    if (![r isKindOfClass:[NSRelationshipDescription class]] || ![r isToMany] || [r isOrdered] ||
        has_custom_accessor([self class], [NSString stringWithFormat:@"add%@Object:", capitalized(key)]))
        return [super mutableSetValueForKey:key];
    return [[[CDMutableSetProxy alloc] cd_initWithObject:self key:key] autorelease];
}

- (NSMutableOrderedSet *)mutableOrderedSetValueForKey:(NSString *)key
{
    NSRelationshipDescription *r = (id)[self cd_property:key];
    if (![r isKindOfClass:[NSRelationshipDescription class]] || ![r isOrdered])
        return [super mutableOrderedSetValueForKey:key];
    return [[[CDMutableOrderedSetProxy alloc] cd_initWithObject:self key:key] autorelease];
}

/* ---- what the context and the stores read ---- */

static id storable(NSPropertyDescription *p, id v)
{
    if (!v)
        return [NSNull null];
    if (![p isKindOfClass:[NSRelationshipDescription class]])
        return v;
    if ([(NSRelationshipDescription *)p isToMany])
        return [as_array(v) valueForKey:@"objectID"];
    return [v objectID];
}

- (NSDictionary *)cd_storableValuesForKeys:(NSArray *)keys
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in keys) {
        NSPropertyDescription *p = [self cd_property:k];
        if (!p || [p isTransient])
            continue;
        id v = [_values objectForKey:k];
        if (!v && [p isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)p isToMany]) {
            if (!_insertedFlag)
                continue;   /* never loaded, so unchanged */
            v = [self cd_primitive:k];
        }
        [d setObject:storable(p, v) forKey:k];
    }
    return d;
}

- (NSDictionary *)cd_loadedValues
{
    if (_fault)
        return @{};
    NSMutableArray *keys = [NSMutableArray array];
    for (NSPropertyDescription *p in [_entity cd_allProperties])
        if (![p isTransient])
            [keys addObject:[p name]];
    return [self cd_storableValuesForKeys:keys];
}

/* Unordered to-manys compare as sets of IDs. */
static BOOL same_stored(id a, id b)
{
    if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]])
        return [[NSSet setWithArray:a] isEqual:[NSSet setWithArray:b]];
    return CDEqual(a, b);
}

- (NSDictionary *)cd_changedStorableValues
{
    if (_fault)
        return @{};
    NSDictionary *now = [self cd_loadedValues];
    if (_insertedFlag || !_context)
        return now;
    NSDictionary *committed = [_context cd_committedValuesForObject:self];
    NSMutableDictionary *changed = [NSMutableDictionary dictionary];
    for (NSString *k in now) {
        id was = [committed objectForKey:k], is = [now objectForKey:k];
        NSRelationshipDescription *r = (id)[self cd_property:k];
        BOOL ordered = [r isKindOfClass:[NSRelationshipDescription class]] && [r isOrdered];
        if (!was && [r isKindOfClass:[NSRelationshipDescription class]] && [r isToMany])
            was = @[];
        if (ordered ? !CDEqual(was, is) : !same_stored(was, is))
            [changed setObject:is forKey:k];
    }
    return changed;
}

- (BOOL)cd_hasTransientChanges { return [_transientChanged count] > 0; }
- (void)cd_clearTransientChanges { [_transientChanged removeAllObjects]; }

/* ---- public reading of changes ---- */

static id public_value(NSManagedObject *self, NSPropertyDescription *p, id stored)
{
    if (stored == [NSNull null])
        return [NSNull null];
    if (![p isKindOfClass:[NSRelationshipDescription class]])
        return stored;
    NSManagedObjectContext *c = [self managedObjectContext];
    if ([(NSRelationshipDescription *)p isToMany]) {
        NSMutableArray *objs = [NSMutableArray array];
        for (NSManagedObjectID *oid in stored)
            [objs addObject:[c objectWithID:oid]];
        return [(NSRelationshipDescription *)p isOrdered] ? (id)[NSOrderedSet orderedSetWithArray:objs]
                                                           : (id)[NSSet setWithArray:objs];
    }
    return [c objectWithID:stored];
}

- (NSDictionary *)changedValues
{
    NSDictionary *changed = [self cd_changedStorableValues];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in changed)
        [d setObject:public_value(self, [self cd_property:k], [changed objectForKey:k]) forKey:k];
    return d;
}

- (NSDictionary *)changedValuesForCurrentEvent { return [self changedValues]; }

- (NSDictionary *)committedValuesForKeys:(NSArray *)keys
{
    NSDictionary *committed = _context && !_insertedFlag ? [_context cd_committedValuesForObject:self] : @{};
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *p in [_entity cd_allProperties]) {
        if ([p isTransient] || (keys && ![keys containsObject:[p name]]))
            continue;
        id v = [committed objectForKey:[p name]];
        if (!v && [p isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)p isToMany] &&
            !_insertedFlag && _context)
            v = [_context cd_relatedIDsForObject:self key:[p name]];
        [d setObject:v ? public_value(self, p, v) : [NSNull null] forKey:[p name]];
    }
    return d;
}

/* ---- validation ---- */

static NSError *validation_error(NSInteger code, NSManagedObject *object, NSString *key, id value,
                                 NSPredicate *predicate, NSString *what)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject:object forKey:NSValidationObjectErrorKey];
    if (key)
        [info setObject:key forKey:NSValidationKeyErrorKey];
    if (value)
        [info setObject:value forKey:NSValidationValueErrorKey];
    if (predicate)
        [info setObject:predicate forKey:NSValidationPredicateErrorKey];
    return CDError(code, what, info);
}

/* The error a failed validation predicate stands for, by its warning or its form. */
static NSInteger predicate_error_code(NSPredicate *pred, NSString *warning, id value)
{
    static NSDictionary *named;
    if (!named)
        named = [@{
            @"NSValidationNumberTooLargeError" : @(NSValidationNumberTooLargeError),
            @"NSValidationNumberTooSmallError" : @(NSValidationNumberTooSmallError),
            @"NSValidationDateTooLateError" : @(NSValidationDateTooLateError),
            @"NSValidationDateTooSoonError" : @(NSValidationDateTooSoonError),
            @"NSValidationStringTooLongError" : @(NSValidationStringTooLongError),
            @"NSValidationStringTooShortError" : @(NSValidationStringTooShortError),
            @"NSValidationStringPatternMatchingError" : @(NSValidationStringPatternMatchingError),
        } retain];
    if ([warning isKindOfClass:[NSString class]] && [named objectForKey:warning]) {
        NSInteger code = [[named objectForKey:warning] integerValue];
        if ([value isKindOfClass:[NSDate class]] && code == NSValidationNumberTooLargeError)
            code = NSValidationDateTooLateError;
        if ([value isKindOfClass:[NSDate class]] && code == NSValidationNumberTooSmallError)
            code = NSValidationDateTooSoonError;
        return code;
    }
    NSString *f = [pred predicateFormat];
    BOOL upper = [f rangeOfString:@"<"].location != NSNotFound, lower = [f rangeOfString:@">"].location != NSNotFound;
    BOOL length = [f rangeOfString:@"length"].location != NSNotFound;
    if ([f rangeOfString:@"MATCHES"].location != NSNotFound)
        return NSValidationStringPatternMatchingError;
    if ([value isKindOfClass:[NSString class]] && length && upper)
        return NSValidationStringTooLongError;
    if ([value isKindOfClass:[NSString class]] && length && lower)
        return NSValidationStringTooShortError;
    if ([value isKindOfClass:[NSDate class]] && upper)
        return NSValidationDateTooLateError;
    if ([value isKindOfClass:[NSDate class]] && lower)
        return NSValidationDateTooSoonError;
    if ([value isKindOfClass:[NSNumber class]] && upper)
        return NSValidationNumberTooLargeError;
    if ([value isKindOfClass:[NSNumber class]] && lower)
        return NSValidationNumberTooSmallError;
    return NSManagedObjectValidationError;
}

- (BOOL)validateValue:(id *)value forKey:(NSString *)key error:(NSError **)error
{
    NSPropertyDescription *p = [self cd_property:key];
    if (!p)
        return [super validateValue:value forKey:key error:error];
    id v = value ? *value : nil;
    if (v == [NSNull null])
        v = nil;
    if ([p isKindOfClass:[NSRelationshipDescription class]]) {
        NSRelationshipDescription *r = (id)p;
        if ([r isToMany]) {
            NSUInteger n = [as_array(v) count];
            if (n == 0 && ![r isOptional] && [r minCount] == 0) {
                /* a mandatory to-many needs at least one object */
                if (error)
                    *error = validation_error(NSValidationRelationshipLacksMinimumCountError, self, key, v, nil,
                                              [NSString stringWithFormat:@"%@ needs at least one object.", key]);
                return NO;
            }
            if ((n > 0 || ![r isOptional]) && n < [r minCount]) {
                if (error)
                    *error = validation_error(NSValidationRelationshipLacksMinimumCountError, self, key, v, nil,
                                              [NSString stringWithFormat:@"%@ has too few objects.", key]);
                return NO;
            }
            if ([r maxCount] > 0 && n > [r maxCount]) {
                if (error)
                    *error = validation_error(NSValidationRelationshipExceedsMaximumCountError, self, key, v, nil,
                                              [NSString stringWithFormat:@"%@ has too many objects.", key]);
                return NO;
            }
        } else if (!v && ![r isOptional]) {
            if (error)
                *error = validation_error(NSValidationMissingMandatoryPropertyError, self, key, nil, nil,
                                          [NSString stringWithFormat:@"%@ is a required value.", key]);
            return NO;
        }
    } else {
        if (!v && ![p isOptional]) {
            if (error)
                *error = validation_error(NSValidationMissingMandatoryPropertyError, self, key, nil, nil,
                                          [NSString stringWithFormat:@"%@ is a required value.", key]);
            return NO;
        }
        if (v) {
            NSArray *preds = [p validationPredicates], *warnings = [p validationWarnings];
            for (NSUInteger i = 0; i < [preds count]; i++) {
                NSPredicate *pred = [preds objectAtIndex:i];
                if ([pred evaluateWithObject:v])
                    continue;
                NSString *w = i < [warnings count] ? [warnings objectAtIndex:i] : nil;
                NSInteger code = predicate_error_code(pred, w, v);
                if (error)
                    *error = validation_error(code, self, key, v, pred,
                                              [NSString stringWithFormat:@"The value of %@ is not valid.", key]);
                return NO;
            }
        }
    }
    /* then the class's own validate<Key>:error:, if it has one */
    return [super validateValue:value forKey:key error:error];
}

- (BOOL)cd_validateAll:(NSError **)error
{
    NSMutableArray *errors = [NSMutableArray array];
    for (NSPropertyDescription *p in [_entity cd_allProperties]) {
        if ([p isTransient])
            continue;
        id v = [self cd_primitive:[p name]];
        NSError *e = nil;
        if (![self validateValue:&v forKey:[p name] error:&e])
            [errors addObject:e ?: CDError(NSManagedObjectValidationError, nil, nil)];
    }
    if (![errors count])
        return YES;
    if (error) {
        if ([errors count] == 1)
            *error = [errors objectAtIndex:0];
        else
            *error = CDError(NSValidationMultipleErrorsError, @"Multiple validation errors occurred.",
                             @{NSDetailedErrorsKey : errors});
    }
    return NO;
}

- (BOOL)validateForInsert:(NSError **)error { return [self cd_validateAll:error]; }
- (BOOL)validateForUpdate:(NSError **)error { return [self cd_validateAll:error]; }
- (BOOL)validateForDelete:(NSError **)error
{
    for (NSPropertyDescription *p in [_entity cd_allProperties]) {
        if (![p isKindOfClass:[NSRelationshipDescription class]] ||
            [(NSRelationshipDescription *)p deleteRule] != NSDenyDeleteRule)
            continue;
        id v = [self cd_primitive:[p name]];
        BOOL some = [(NSRelationshipDescription *)p isToMany] ? [as_array(v) count] > 0 : v != nil;
        if (some) {
            if (error)
                *error = validation_error(NSValidationRelationshipDeniedDeleteError, self, [p name], v, nil,
                                          [NSString stringWithFormat:@"%@ is not empty, so the object can't be deleted.",
                                                                     [p name]]);
            return NO;
        }
    }
    return YES;
}

- (NSString *)description
{
    NSString *data;
    if (_fault)
        data = @"<fault>";
    else {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSPropertyDescription *p in [_entity cd_allProperties]) {
            id v = [_values objectForKey:[p name]];
            NSString *s;
            if ([v isKindOfClass:[NSManagedObject class]])
                s = [[[v objectID] URIRepresentation] absoluteString];
            else if ([v isKindOfClass:[NSSet class]] || [v isKindOfClass:[NSOrderedSet class]])
                s = [NSString stringWithFormat:@"(%lu objects)", (unsigned long)[v count]];
            else if (!v && [p isKindOfClass:[NSRelationshipDescription class]] &&
                     [(NSRelationshipDescription *)p isToMany])
                s = @"<relationship fault>";
            else
                s = v ? [v description] : @"nil";
            [parts addObject:[NSString stringWithFormat:@"%@ = %@", [p name], s]];
        }
        data = [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@"; "]];
    }
    return [NSString stringWithFormat:@"<%@: %p> (entity: %@; id: %@; data: %@)", NSStringFromClass([self class]), self,
                                      [_entity name], [[_oid URIRepresentation] absoluteString], data];
}
@end

/* ---- the to-many proxies ---------------------------------------------------------------- */


@implementation CDMutableSetProxy
- (id)cd_initWithObject:(NSManagedObject *)object key:(NSString *)key
{
    if ((self = [super init])) {
        _object = [object retain];
        _key = [key copy];
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [_key release];
    [super dealloc];
}
/* The proxy holds nothing of its own: what the cluster's initializers would fill is the object's. */
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count { return self; }
- (instancetype)initWithCapacity:(NSUInteger)n { return self; }
- (id)copyWithZone:(NSZone *)zone { return [[NSSet setWithSet:[self cd_current]] retain]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableSet setWithSet:[self cd_current]] retain]; }
- (NSSet *)cd_current { return [_object cd_get:_key] ?: [NSSet set]; }
- (NSUInteger)count { return [[self cd_current] count]; }
- (id)member:(id)obj { return [[self cd_current] member:obj]; }
- (NSEnumerator *)objectEnumerator { return [[self cd_current] objectEnumerator]; }
- (NSArray *)allObjects { return [[self cd_current] allObjects]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    return [[self cd_current] countByEnumeratingWithState:state objects:buffer count:len];
}
- (void)addObject:(id)obj
{
    if (obj)
        [_object cd_toMany:_key add:@[ obj ] remove:nil];
}
- (void)removeObject:(id)obj
{
    if (obj)
        [_object cd_toMany:_key add:nil remove:@[ obj ]];
}
- (void)addObjectsFromArray:(NSArray *)array { [_object cd_toMany:_key add:array remove:nil]; }
- (void)unionSet:(NSSet *)other { [_object cd_toMany:_key add:[other allObjects] remove:nil]; }
- (void)minusSet:(NSSet *)other { [_object cd_toMany:_key add:nil remove:[other allObjects]]; }
- (void)removeAllObjects { [_object cd_toMany:_key add:nil remove:[[self cd_current] allObjects]]; }
- (void)setSet:(NSSet *)other { [_object cd_toMany:_key replaceWith:other]; }
- (void)intersectSet:(NSSet *)other
{
    NSMutableArray *gone = [NSMutableArray array];
    for (id o in [self cd_current])
        if (![other containsObject:o])
            [gone addObject:o];
    [_object cd_toMany:_key add:nil remove:gone];
}
@end


@implementation CDMutableOrderedSetProxy
- (id)cd_initWithObject:(NSManagedObject *)object key:(NSString *)key
{
    if ((self = [super init])) {
        _object = [object retain];
        _key = [key copy];
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [_key release];
    [super dealloc];
}
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count { return self; }
- (instancetype)initWithCapacity:(NSUInteger)n { return self; }
- (id)copyWithZone:(NSZone *)zone { return [[NSOrderedSet alloc] initWithOrderedSet:[self cd_current]]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableOrderedSet alloc] initWithOrderedSet:[self cd_current]]; }
- (NSOrderedSet *)cd_current { return [_object cd_get:_key] ?: [NSOrderedSet orderedSet]; }
- (NSUInteger)count { return [[self cd_current] count]; }
- (id)objectAtIndex:(NSUInteger)idx { return [[self cd_current] objectAtIndex:idx]; }
- (NSUInteger)indexOfObject:(id)object { return [[self cd_current] indexOfObject:object]; }
- (NSMutableOrderedSet *)cd_copy { return [[[self cd_current] mutableCopy] autorelease]; }
- (void)insertObject:(id)object atIndex:(NSUInteger)idx
{
    NSMutableOrderedSet *m = [self cd_copy];
    [m insertObject:object atIndex:idx];
    [_object cd_toMany:_key replaceWith:m];
}
- (void)removeObjectAtIndex:(NSUInteger)idx
{
    NSMutableOrderedSet *m = [self cd_copy];
    [m removeObjectAtIndex:idx];
    [_object cd_toMany:_key replaceWith:m];
}
- (void)replaceObjectAtIndex:(NSUInteger)idx withObject:(id)object
{
    NSMutableOrderedSet *m = [self cd_copy];
    [m replaceObjectAtIndex:idx withObject:object];
    [_object cd_toMany:_key replaceWith:m];
}
- (void)addObject:(id)object
{
    NSMutableOrderedSet *m = [self cd_copy];
    [m addObject:object];
    [_object cd_toMany:_key replaceWith:m];
}
- (void)removeObject:(id)object
{
    NSMutableOrderedSet *m = [self cd_copy];
    [m removeObject:object];
    [_object cd_toMany:_key replaceWith:m];
}
- (void)removeAllObjects { [_object cd_toMany:_key replaceWith:@[]]; }
@end
