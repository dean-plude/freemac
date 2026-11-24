/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: the model (NSManagedObjectModel, NSEntityDescription
 * and the property descriptions), as Apple's class references describe
 * them, and a reader for the XML source of a model that Xcode keeps in a
 * .xcdatamodeld folder (freemac 1.NEXT, Ferry 0.NEXT). Compiled models
 * (.mom and .momd) aren't read: their format isn't published, so asking
 * for one says so once on stderr and answers nil, as Core Data answers
 * when it finds no model. Our own code; no Apple code was used.
 *
 * Version hashes are Ferry's own: SHA-256 over an entity's name, its
 * parent, and the name, type and options of each persistent property.
 * They tell a store whether the model changed, and are only ever compared
 * with hashes Ferry made. */
#import "CDInternal.h"
#include <CommonCrypto/CommonDigest.h>
#include <stdarg.h>

NSString *const NSDetailedErrorsKey CD_EXPORT = @"NSDetailedErrors";
NSString *const NSValidationObjectErrorKey CD_EXPORT = @"NSValidationErrorObject";
NSString *const NSValidationKeyErrorKey CD_EXPORT = @"NSValidationErrorKey";
NSString *const NSValidationPredicateErrorKey CD_EXPORT = @"NSValidationErrorPredicate";
NSString *const NSValidationValueErrorKey CD_EXPORT = @"NSValidationErrorValue";
NSString *const NSAffectedStoresErrorKey CD_EXPORT = @"NSAffectedStoresErrorKey";
NSString *const NSAffectedObjectsErrorKey CD_EXPORT = @"NSAffectedObjectsErrorKey";
NSString *const NSPersistentStoreSaveConflictsErrorKey CD_EXPORT = @"conflictList";
NSString *const NSSQLiteErrorDomain CD_EXPORT = @"NSSQLiteErrorDomain";

/* ---- helpers ------------------------------------------------------------------------- */

NSError *CDError(NSInteger code, NSString *description, NSDictionary *extra)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (description)
        [info setObject:description forKey:NSLocalizedDescriptionKey];
    if (extra)
        [info addEntriesFromDictionary:extra];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

BOOL CDFail(NSError **out, NSInteger code, NSString *description, NSDictionary *extra)
{
    if (out)
        *out = CDError(code, description, extra);
    return NO;
}

void CDWarnOnce(NSString *key, NSString *message)
{
    static NSMutableSet *said;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (!said)
        said = [[NSMutableSet alloc] init];
    BOOL first = ![said containsObject:key];
    [said addObject:key];
    pthread_mutex_unlock(&lock);
    if (first)
        fprintf(stderr, "%s\n", [message UTF8String]);
}

void CDRaise(NSString *name, NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *reason = [[[NSString alloc] initWithFormat:format arguments:ap] autorelease];
    va_end(ap);
    [[NSException exceptionWithName:name ?: NSInternalInconsistencyException reason:reason userInfo:nil] raise];
    abort();
}

BOOL CDEqual(id a, id b)
{
    if (a == [NSNull null])
        a = nil;
    if (b == [NSNull null])
        b = nil;
    if (a == b)
        return YES;
    if (!a || !b)
        return NO;
    return [a isEqual:b];
}

NSData *CDHash(NSString *s)
{
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    const char *u = [s UTF8String];
    CC_SHA256(u, (CC_LONG)strlen(u), md);
    return [NSData dataWithBytes:md length:sizeof md];
}

void CDCompiledModelUnsupported(NSString *path)
{
    CDWarnOnce(@"compiled-model",
               [NSString stringWithFormat:@"Ferry: Core Data's compiled models (.mom and .momd) aren't supported yet, "
                                          @"so %@ wasn't read. A model built in code, or the model's source "
                                          @"(.xcdatamodeld), works.",
                                          path ?: @"the model"]);
}

/* ---- property descriptions ----------------------------------------------------------- */

@interface NSPropertyDescription () {
@protected
    NSEntityDescription *_entity;   /* not retained: the entity keeps its properties */
    NSString *_name;
    BOOL _optional, _transient, _indexed, _spotlight;
    NSArray *_predicates, *_warnings;
    NSDictionary *_userInfo;
    NSString *_hashModifier, *_renaming;
}
@end

@implementation NSPropertyDescription
- (instancetype)init
{
    if ((self = [super init]))
        _optional = YES;
    return self;
}
- (void)dealloc
{
    [_name release];
    [_predicates release];
    [_warnings release];
    [_userInfo release];
    [_hashModifier release];
    [_renaming release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSPropertyDescription *c = [[[self class] allocWithZone:zone] init];
    c->_name = [_name copy];
    c->_optional = _optional;
    c->_transient = _transient;
    c->_indexed = _indexed;
    c->_spotlight = _spotlight;
    c->_predicates = [_predicates copy];
    c->_warnings = [_warnings copy];
    c->_userInfo = [_userInfo copy];
    c->_hashModifier = [_hashModifier copy];
    c->_renaming = [_renaming copy];
    return c;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _name = [[coder decodeObjectForKey:@"name"] copy];
        _optional = [coder decodeBoolForKey:@"optional"];
        _transient = [coder decodeBoolForKey:@"transient"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeBool:_optional forKey:@"optional"];
    [coder encodeBool:_transient forKey:@"transient"];
}
- (NSEntityDescription *)entity { return _entity; }
- (void)cd_setEntity:(NSEntityDescription *)entity { _entity = entity; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    [_name autorelease];
    _name = [name copy];
}
- (BOOL)isOptional { return _optional; }
- (void)setOptional:(BOOL)flag { _optional = flag; }
- (BOOL)isTransient { return _transient; }
- (void)setTransient:(BOOL)flag { _transient = flag; }
- (BOOL)isIndexed { return _indexed; }
- (void)setIndexed:(BOOL)flag { _indexed = flag; }
- (BOOL)isIndexedBySpotlight { return _spotlight; }
- (void)setIndexedBySpotlight:(BOOL)flag { _spotlight = flag; }
- (NSArray *)validationPredicates { return _predicates ?: @[]; }
- (NSArray *)validationWarnings { return _warnings ?: @[]; }
- (void)setValidationPredicates:(NSArray *)predicates withValidationWarnings:(NSArray *)warnings
{
    [_predicates autorelease];
    [_warnings autorelease];
    _predicates = [predicates copy];
    _warnings = [warnings copy];
}
- (NSDictionary *)userInfo { return _userInfo; }
- (void)setUserInfo:(NSDictionary *)info
{
    [_userInfo autorelease];
    _userInfo = [info copy];
}
- (NSString *)versionHashModifier { return _hashModifier; }
- (void)setVersionHashModifier:(NSString *)s
{
    [_hashModifier autorelease];
    _hashModifier = [s copy];
}
- (NSString *)renamingIdentifier { return _renaming ?: _name; }
- (void)setRenamingIdentifier:(NSString *)s
{
    [_renaming autorelease];
    _renaming = [s copy];
}
- (NSString *)cd_hashString { return _name; }
- (NSData *)versionHash { return CDHash([self cd_hashString]); }
@end

static NSString *attribute_class_name(NSAttributeType type)
{
    switch (type) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
    case NSBooleanAttributeType: return @"NSNumber";
    case NSDecimalAttributeType: return @"NSDecimalNumber";
    case NSStringAttributeType: return @"NSString";
    case NSDateAttributeType: return @"NSDate";
    case NSBinaryDataAttributeType: return @"NSData";
    case NSUUIDAttributeType: return @"NSUUID";
    case NSURIAttributeType: return @"NSURL";
    case NSObjectIDAttributeType: return @"NSManagedObjectID";
    default: return nil;
    }
}

static BOOL transformer_is_archiving(NSString *name)
{
    return !name || [name isEqualToString:NSKeyedUnarchiveFromDataTransformerName] ||
           [name isEqualToString:NSUnarchiveFromDataTransformerName] ||
           [name isEqualToString:NSSecureUnarchiveFromDataTransformerName];
}

@implementation NSAttributeDescription {
    NSAttributeType _type;
    NSString *_className, *_transformerName;
    id _default;
    BOOL _external, _history, _cloud;
}
- (void)dealloc
{
    [_className release];
    [_transformerName release];
    [_default release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSAttributeDescription *c = [super copyWithZone:zone];
    c->_type = _type;
    c->_className = [_className copy];
    c->_transformerName = [_transformerName copy];
    c->_default = [_default retain];
    c->_external = _external;
    return c;
}
- (NSAttributeType)attributeType { return _type; }
- (void)setAttributeType:(NSAttributeType)type { _type = type; }
- (NSString *)attributeValueClassName { return _className ?: attribute_class_name(_type); }
- (void)setAttributeValueClassName:(NSString *)name
{
    [_className autorelease];
    _className = [name copy];
}
- (id)defaultValue { return _default; }
- (void)setDefaultValue:(id)value
{
    [_default autorelease];
    _default = [value retain];
}
- (NSString *)valueTransformerName { return _transformerName; }
- (void)setValueTransformerName:(NSString *)name
{
    [_transformerName autorelease];
    _transformerName = [name copy];
}
- (BOOL)allowsExternalBinaryDataStorage { return _external; }
- (void)setAllowsExternalBinaryDataStorage:(BOOL)flag { _external = flag; }
- (BOOL)preservesValueInHistoryOnDeletion { return _history; }
- (void)setPreservesValueInHistoryOnDeletion:(BOOL)flag { _history = flag; }
- (BOOL)allowsCloudEncryption { return _cloud; }
- (void)setAllowsCloudEncryption:(BOOL)flag { _cloud = flag; }
- (NSString *)cd_hashString
{
    return [NSString stringWithFormat:@"A|%@|%lu|%d|%@", _name, (unsigned long)_type, _optional, _hashModifier ?: @""];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"(<NSAttributeDescription: %p>), name %@, isOptional %d, isTransient %d, "
                                      @"entity %@, attributeType %lu, attributeValueClassName %@, defaultValue %@",
                                      self, _name, _optional, _transient, [_entity name], (unsigned long)_type,
                                      [self attributeValueClassName], _default];
}
/* The stored form: transformable values become data through the attribute's transformer. */
- (id)cd_storedValue:(id)value
{
    if (_type != NSTransformableAttributeType || !value || value == [NSNull null])
        return value;
    NSValueTransformer *t = [NSValueTransformer valueTransformerForName:_transformerName
                                                                          ?: NSKeyedUnarchiveFromDataTransformerName];
    if (!t) {
        CDWarnOnce([@"transformer:" stringByAppendingString:_transformerName ?: @""],
                   [NSString stringWithFormat:@"Ferry: Core Data found no value transformer named %@", _transformerName]);
        return [value isKindOfClass:[NSData class]] ? value : nil;
    }
    if (transformer_is_archiving(_transformerName))
        return [t reverseTransformedValue:value];
    return [t transformedValue:value];
}
- (id)cd_valueFromStored:(id)stored
{
    if (_type != NSTransformableAttributeType || !stored || stored == [NSNull null])
        return stored;
    NSValueTransformer *t = [NSValueTransformer valueTransformerForName:_transformerName
                                                                          ?: NSKeyedUnarchiveFromDataTransformerName];
    if (!t)
        return stored;
    if (transformer_is_archiving(_transformerName))
        return [t transformedValue:stored];
    return [t reverseTransformedValue:stored];
}
@end

@implementation NSRelationshipDescription {
    NSEntityDescription *_destination;      /* not retained: the model keeps its entities */
    NSRelationshipDescription *_inverse;    /* not retained */
    NSString *_destinationName, *_inverseName;   /* from a model's source, until the model resolves them */
    NSUInteger _min, _max;
    NSDeleteRule _rule;
    BOOL _ordered;
}
- (instancetype)init
{
    if ((self = [super init]))
        _rule = NSNullifyDeleteRule;
    return self;
}
- (void)dealloc
{
    [_destinationName release];
    [_inverseName release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSRelationshipDescription *c = [super copyWithZone:zone];
    c->_destination = _destination;
    c->_inverse = _inverse;
    c->_min = _min;
    c->_max = _max;
    c->_rule = _rule;
    c->_ordered = _ordered;
    return c;
}
- (NSEntityDescription *)destinationEntity { return _destination; }
- (void)setDestinationEntity:(NSEntityDescription *)entity { _destination = entity; }
- (NSRelationshipDescription *)inverseRelationship { return _inverse; }
- (void)setInverseRelationship:(NSRelationshipDescription *)inverse { _inverse = inverse; }
- (NSUInteger)minCount { return _min; }
- (void)setMinCount:(NSUInteger)n { _min = n; }
- (NSUInteger)maxCount { return _max; }
- (void)setMaxCount:(NSUInteger)n { _max = n; }
- (NSDeleteRule)deleteRule { return _rule; }
- (void)setDeleteRule:(NSDeleteRule)rule { _rule = rule; }
/* A maximum of 1 makes a to-one relationship; any other (0 is no limit) a to-many one. */
- (BOOL)isToMany { return _max != 1; }
- (BOOL)isOrdered { return _ordered; }
- (void)setOrdered:(BOOL)flag { _ordered = flag; }
- (void)cd_setDestinationName:(NSString *)dest inverseName:(NSString *)inverse
{
    [_destinationName autorelease];
    [_inverseName autorelease];
    _destinationName = [dest copy];
    _inverseName = [inverse copy];
}
- (void)cd_resolveInModel:(NSDictionary *)entities
{
    if (_destinationName)
        _destination = [entities objectForKey:_destinationName];
    if (_inverseName && _destination)
        _inverse = [[_destination relationshipsByName] objectForKey:_inverseName];
}
- (NSString *)cd_hashString
{
    return [NSString stringWithFormat:@"R|%@|%@|%d|%d|%d|%@", _name, [_destination name], [self isToMany], _ordered,
                                      _optional, _hashModifier ?: @""];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"(<NSRelationshipDescription: %p>), name %@, isOptional %d, isTransient %d, "
                                      @"entity %@, destination entity %@, inverse relationship %@, minCount %lu, "
                                      @"maxCount %lu, isOrdered %d, deleteRule %lu",
                                      self, _name, _optional, _transient, [_entity name], [_destination name],
                                      [_inverse name], (unsigned long)_min, (unsigned long)_max, _ordered,
                                      (unsigned long)_rule];
}
@end

/* ---- entities ---------------------------------------------------------------------------- */

static id key_lookup(NSDictionary *d, NSString *name) { return name ? [d objectForKey:name] : nil; }

@implementation NSEntityDescription {
    NSManagedObjectModel *_model;   /* not retained */
    NSEntityDescription *_super;    /* not retained: the parent keeps its subentities */
    NSString *_name, *_className, *_hashModifier, *_renaming;
    BOOL _abstract;
    NSArray *_subentities, *_properties, *_constraints, *_indexes;
    NSDictionary *_userInfo;
    NSDictionary *_byName;   /* every property by name, made when first asked */
}
+ (NSEntityDescription *)entityForName:(NSString *)name inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSManagedObjectModel *model = [[context persistentStoreCoordinator] managedObjectModel];
    if (!model)
        CDRaise(NSInternalInconsistencyException,
                @"+entityForName: could not locate an NSManagedObjectModel for entity name '%@'", name);
    return [[model entitiesByName] objectForKey:name];
}
+ (id)insertNewObjectForEntityForName:(NSString *)name inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSEntityDescription *e = [self entityForName:name inManagedObjectContext:context];
    if (!e)
        CDRaise(NSInternalInconsistencyException,
                @"+entityForName: could not locate an entity named '%@' in this model.", name);
    return [[[[e cd_class] alloc] initWithEntity:e insertIntoManagedObjectContext:context] autorelease];
}
- (void)dealloc
{
    for (NSEntityDescription *s in _subentities)
        [s cd_setSuperentity:nil];
    for (NSPropertyDescription *p in _properties)
        [p cd_setEntity:nil];
    [_name release];
    [_className release];
    [_hashModifier release];
    [_renaming release];
    [_subentities release];
    [_properties release];
    [_constraints release];
    [_indexes release];
    [_userInfo release];
    [_byName release];
    [super dealloc];
}
/* Forgets the properties by name, here and below, when the properties change. */
- (void)cd_invalidate
{
    @synchronized(self) {
        [_byName release];
        _byName = nil;
    }
    for (NSEntityDescription *s in _subentities)
        [s cd_invalidate];
}
- (NSPropertyDescription *)cd_propertyNamed:(NSString *)name
{
    NSDictionary *d;
    @synchronized(self) {
        if (!_byName) {
            NSMutableDictionary *m = [NSMutableDictionary dictionary];
            for (NSPropertyDescription *p in [self cd_allProperties])
                [m setObject:p forKey:[p name]];
            _byName = [m copy];
        }
        d = [[_byName retain] autorelease];
    }
    return key_lookup(d, name);
}
- (id)copyWithZone:(NSZone *)zone
{
    NSEntityDescription *c = [[NSEntityDescription allocWithZone:zone] init];
    [c setName:_name];
    [c setManagedObjectClassName:_className];
    [c setAbstract:_abstract];
    NSMutableArray *props = [NSMutableArray array];
    for (NSPropertyDescription *p in _properties)
        [props addObject:[[p copy] autorelease]];
    [c setProperties:props];
    [c setUserInfo:_userInfo];
    return c;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _name = [[coder decodeObjectForKey:@"name"] copy];
        _className = [[coder decodeObjectForKey:@"className"] copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_className forKey:@"className"];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    return [[self cd_allProperties] countByEnumeratingWithState:state objects:buffer count:len];
}
- (NSManagedObjectModel *)managedObjectModel { return _model; }
- (void)cd_setModel:(NSManagedObjectModel *)model { _model = model; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name
{
    [_name autorelease];
    _name = [name copy];
}
- (NSString *)managedObjectClassName { return _className ?: @"NSManagedObject"; }
- (void)setManagedObjectClassName:(NSString *)name
{
    [_className autorelease];
    _className = [name copy];
}
- (Class)cd_class
{
    Class c = _className ? NSClassFromString(_className) : Nil;
    if (_className && !c)
        CDWarnOnce([@"class:" stringByAppendingString:_className],
                   [NSString stringWithFormat:@"Ferry: Core Data found no class named %@ for the entity %@, so its "
                                              @"objects are NSManagedObjects",
                                              _className, _name]);
    return c ?: [NSManagedObject class];
}
- (BOOL)isAbstract { return _abstract; }
- (void)setAbstract:(BOOL)flag { _abstract = flag; }
- (NSArray *)subentities { return _subentities ?: @[]; }
- (void)setSubentities:(NSArray *)subentities
{
    for (NSEntityDescription *s in _subentities)
        [s cd_setSuperentity:nil];
    [_subentities autorelease];
    _subentities = [subentities copy];
    for (NSEntityDescription *s in _subentities)
        [s cd_setSuperentity:self];
}
- (NSDictionary *)subentitiesByName
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSEntityDescription *s in _subentities)
        [d setObject:s forKey:[s name]];
    return d;
}
- (NSEntityDescription *)superentity { return _super; }
- (void)cd_setSuperentity:(NSEntityDescription *)entity
{
    _super = entity;
    [self cd_invalidate];
}
- (NSEntityDescription *)cd_root
{
    NSEntityDescription *e = self;
    while (e->_super)
        e = e->_super;
    return e;
}
- (NSArray *)cd_selfAndSubentityNames
{
    NSMutableArray *names = [NSMutableArray arrayWithObject:_name];
    for (NSEntityDescription *s in _subentities)
        [names addObjectsFromArray:[s cd_selfAndSubentityNames]];
    return names;
}
- (BOOL)isKindOfEntity:(NSEntityDescription *)entity
{
    for (NSEntityDescription *e = self; e; e = e->_super)
        if (e == entity || [e->_name isEqualToString:[entity name]])
            return YES;
    return NO;
}
- (NSArray *)properties { return _properties ?: @[]; }
- (void)setProperties:(NSArray *)properties
{
    for (NSPropertyDescription *p in _properties)
        [p cd_setEntity:nil];
    [_properties autorelease];
    _properties = [properties copy];
    for (NSPropertyDescription *p in _properties)
        [p cd_setEntity:self];
    [self cd_invalidate];
}
- (NSArray *)cd_allProperties
{
    NSMutableArray *all = [NSMutableArray array];
    if (_super)
        [all addObjectsFromArray:[_super cd_allProperties]];
    [all addObjectsFromArray:[self properties]];
    return all;
}
- (NSDictionary *)propertiesByName
{
    [self cd_propertyNamed:@""];
    @synchronized(self) {
        return [[_byName retain] autorelease];
    }
}
- (NSDictionary *)attributesByName
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *p in [self cd_allProperties])
        if ([p isKindOfClass:[NSAttributeDescription class]])
            [d setObject:p forKey:[p name]];
    return d;
}
- (NSDictionary *)relationshipsByName
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *p in [self cd_allProperties])
        if ([p isKindOfClass:[NSRelationshipDescription class]])
            [d setObject:p forKey:[p name]];
    return d;
}
- (NSArray *)cd_persistentAttributes
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSPropertyDescription *p in [self cd_allProperties])
        if ([p isKindOfClass:[NSAttributeDescription class]] && ![p isTransient])
            [a addObject:p];
    return a;
}
- (NSArray *)cd_persistentRelationships
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSPropertyDescription *p in [self cd_allProperties])
        if ([p isKindOfClass:[NSRelationshipDescription class]] && ![p isTransient])
            [a addObject:p];
    return a;
}
- (NSArray *)relationshipsWithDestinationEntity:(NSEntityDescription *)entity
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSRelationshipDescription *r in [[self relationshipsByName] allValues])
        if ([r destinationEntity] == entity)
            [a addObject:r];
    return a;
}
- (NSDictionary *)userInfo { return _userInfo; }
- (void)setUserInfo:(NSDictionary *)info
{
    [_userInfo autorelease];
    _userInfo = [info copy];
}
- (NSString *)versionHashModifier { return _hashModifier; }
- (void)setVersionHashModifier:(NSString *)s
{
    [_hashModifier autorelease];
    _hashModifier = [s copy];
}
- (NSString *)renamingIdentifier { return _renaming ?: _name; }
- (void)setRenamingIdentifier:(NSString *)s
{
    [_renaming autorelease];
    _renaming = [s copy];
}
- (NSArray *)uniquenessConstraints { return _constraints ?: @[]; }
- (void)setUniquenessConstraints:(NSArray *)c
{
    [_constraints autorelease];
    _constraints = [c copy];
}
- (NSArray *)indexes { return _indexes ?: @[]; }
- (void)setIndexes:(NSArray *)i
{
    [_indexes autorelease];
    _indexes = [i copy];
}
- (NSData *)versionHash
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSPropertyDescription *p in [self cd_allProperties])
        if (![p isTransient])
            [parts addObject:[(id)p cd_hashString]];
    [parts sortUsingSelector:@selector(compare:)];
    NSString *s = [NSString stringWithFormat:@"E|%@|%@|%d|%@|%@", _name, [_super name] ?: @"", _abstract,
                                             _hashModifier ?: @"", [parts componentsJoinedByString:@";"]];
    return CDHash(s);
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"(<NSEntityDescription: %p>) name %@, managedObjectClassName %@, "
                                      @"superentity %@, properties %@",
                                      self, _name, [self managedObjectClassName], [_super name],
                                      [[self propertiesByName] allKeys]];
}
@end

/* ---- the model ---------------------------------------------------------------------------- */

@implementation NSManagedObjectModel {
    NSArray *_entities;
    NSMutableDictionary *_configurations;   /* name -> array of entities */
    NSMutableDictionary *_templates;
    NSDictionary *_localization;
    NSSet *_versionIdentifiers;
}
+ (NSArray *)cd_modelURLsInBundle:(NSBundle *)bundle compiled:(NSMutableArray *)compiled
{
    NSMutableArray *sources = [NSMutableArray array];
    NSString *dir = [bundle resourcePath] ?: [bundle bundlePath];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *n in [names sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *ext = [n pathExtension];
        NSString *path = [dir stringByAppendingPathComponent:n];
        if ([ext isEqualToString:@"xcdatamodeld"] || [ext isEqualToString:@"xcdatamodel"])
            [sources addObject:[NSURL fileURLWithPath:path]];
        else if ([ext isEqualToString:@"mom"] || [ext isEqualToString:@"momd"])
            [compiled addObject:path];
    }
    return sources;
}
+ (NSManagedObjectModel *)mergedModelFromBundles:(NSArray *)bundles
{
    NSMutableArray *models = [NSMutableArray array], *compiled = [NSMutableArray array];
    for (NSBundle *b in bundles ?: @[ [NSBundle mainBundle] ])
        for (NSURL *u in [self cd_modelURLsInBundle:b compiled:compiled]) {
            NSManagedObjectModel *m = [self cd_modelFromSourceAtURL:u];
            if (m)
                [models addObject:m];
        }
    if (![models count]) {
        if ([compiled count])
            CDCompiledModelUnsupported([compiled objectAtIndex:0]);
        return nil;
    }
    return [self modelByMergingModels:models];
}
+ (NSManagedObjectModel *)mergedModelFromBundles:(NSArray *)bundles forStoreMetadata:(NSDictionary *)metadata
{
    NSManagedObjectModel *m = [self mergedModelFromBundles:bundles];
    return [m isConfiguration:nil compatibleWithStoreMetadata:metadata] ? m : nil;
}
+ (NSManagedObjectModel *)modelByMergingModels:(NSArray *)models
{
    if (![models count])
        return nil;
    if ([models count] == 1)
        return [[[models objectAtIndex:0] retain] autorelease];
    NSManagedObjectModel *m = [[[NSManagedObjectModel alloc] init] autorelease];
    NSMutableArray *all = [NSMutableArray array];
    for (NSManagedObjectModel *x in models)
        for (NSEntityDescription *e in [x entities]) {
            if ([[m entitiesByName] objectForKey:[e name]] || [[all valueForKey:@"name"] containsObject:[e name]])
                CDRaise(NSInvalidArgumentException, @"Can't merge models with two different entities named '%@'",
                        [e name]);
            [all addObject:e];
        }
    /* The entities stay the originals' (their relationships point at each other). */
    [m->_entities release];
    m->_entities = [all copy];
    for (NSEntityDescription *e in all)
        [e cd_setModel:m];
    return m;
}
+ (NSManagedObjectModel *)modelByMergingModels:(NSArray *)models forStoreMetadata:(NSDictionary *)metadata
{
    NSManagedObjectModel *m = [self modelByMergingModels:models];
    return [m isConfiguration:nil compatibleWithStoreMetadata:metadata] ? m : nil;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _entities = [[NSArray alloc] init];
        _configurations = [[NSMutableDictionary alloc] init];
        _templates = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url
{
    NSString *ext = [[url path] pathExtension];
    if ([ext isEqualToString:@"mom"] || [ext isEqualToString:@"momd"] || [ext isEqualToString:@"omo"]) {
        CDCompiledModelUnsupported([url path]);
        [self release];
        return nil;
    }
    NSManagedObjectModel *m = [NSManagedObjectModel cd_modelFromSourceAtURL:url];
    [self release];
    return [m retain];
}
- (void)dealloc
{
    for (NSEntityDescription *e in _entities)
        if ([e managedObjectModel] == self)
            [e cd_setModel:nil];
    [_entities release];
    [_configurations release];
    [_templates release];
    [_localization release];
    [_versionIdentifiers release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    return [_entities countByEnumeratingWithState:state objects:buffer count:len];
}
- (NSArray *)entities { return _entities; }
- (void)setEntities:(NSArray *)entities
{
    for (NSEntityDescription *e in _entities)
        if ([e managedObjectModel] == self)
            [e cd_setModel:nil];
    [_entities autorelease];
    _entities = [entities copy] ?: [[NSArray alloc] init];
    for (NSEntityDescription *e in _entities)
        [e cd_setModel:self];
}
- (NSDictionary *)entitiesByName
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSEntityDescription *e in _entities)
        [d setObject:e forKey:[e name]];
    return d;
}
- (NSArray *)configurations { return [_configurations allKeys]; }
- (NSArray *)entitiesForConfiguration:(NSString *)configuration
{
    if (!configuration || [configuration isEqualToString:@"PF_DEFAULT_CONFIGURATION_NAME"] ||
        [configuration isEqualToString:@"Default"])
        return _entities;
    return [_configurations objectForKey:configuration];
}
- (void)setEntities:(NSArray *)entities forConfiguration:(NSString *)configuration
{
    [_configurations setObject:[[entities copy] autorelease] forKey:configuration];
}
- (void)setFetchRequestTemplate:(NSFetchRequest *)request forName:(NSString *)name
{
    if (request)
        [_templates setObject:request forKey:name];
    else
        [_templates removeObjectForKey:name];
}
- (NSFetchRequest *)fetchRequestTemplateForName:(NSString *)name { return [_templates objectForKey:name]; }
- (NSFetchRequest *)fetchRequestFromTemplateWithName:(NSString *)name substitutionVariables:(NSDictionary *)variables
{
    NSFetchRequest *t = [_templates objectForKey:name];
    if (!t)
        return nil;
    NSFetchRequest *r = [[t copy] autorelease];
    if ([r predicate])
        [r setPredicate:[[r predicate] predicateWithSubstitutionVariables:variables ?: @{}]];
    return r;
}
- (NSDictionary *)fetchRequestTemplatesByName { return [[_templates copy] autorelease]; }
- (NSDictionary *)localizationDictionary { return _localization; }
- (void)setLocalizationDictionary:(NSDictionary *)d
{
    [_localization autorelease];
    _localization = [d copy];
}
- (NSSet *)versionIdentifiers { return _versionIdentifiers ?: [NSSet set]; }
- (void)setVersionIdentifiers:(NSSet *)s
{
    [_versionIdentifiers autorelease];
    _versionIdentifiers = [s copy];
}
- (NSDictionary *)entityVersionHashesByName
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSEntityDescription *e in _entities)
        [d setObject:[e versionHash] forKey:[e name]];
    return d;
}
- (BOOL)isConfiguration:(NSString *)configuration compatibleWithStoreMetadata:(NSDictionary *)metadata
{
    NSDictionary *stored = [metadata objectForKey:NSStoreModelVersionHashesKey];
    if (![stored isKindOfClass:[NSDictionary class]])
        return NO;
    for (NSEntityDescription *e in [self entitiesForConfiguration:configuration])
        if (![[stored objectForKey:[e name]] isEqual:[e versionHash]])
            return NO;
    return YES;
}
- (NSDictionary *)cd_schema
{
    NSMutableDictionary *schema = [NSMutableDictionary dictionary];
    for (NSEntityDescription *e in _entities) {
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary], *rels = [NSMutableDictionary dictionary];
        for (NSAttributeDescription *a in [e cd_persistentAttributes])
            [attrs setObject:@([a attributeType]) forKey:[a name]];
        for (NSRelationshipDescription *r in [e cd_persistentRelationships])
            [rels setObject:@{
                @"destination" : [[r destinationEntity] name] ?: @"",
                @"toMany" : @([r isToMany]),
                @"ordered" : @([r isOrdered])
            }
                     forKey:[r name]];
        [schema setObject:@{
            @"attributes" : attrs,
            @"relationships" : rels,
            @"root" : [[e cd_root] name],
        }
                   forKey:[e name]];
    }
    return schema;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"(<NSManagedObjectModel: %p>) entities %@", self, [_entities valueForKey:@"name"]];
}

/* ---- the XML source of a model ---------------------------------------------------------
 * A .xcdatamodeld folder holds one .xcdatamodel folder per version (and a
 * .xccurrentversion property list naming the current one); each holds a
 * file named contents, an XML document with a <model> element of
 * <entity> elements, each of <attribute> and <relationship> elements whose
 * XML attributes name the property's settings. */

static NSString *xml_attr(NSXMLElement *el, NSString *name) { return [[el attributeForName:name] stringValue]; }
static BOOL xml_bool(NSXMLElement *el, NSString *name, BOOL fallback)
{
    NSString *v = xml_attr(el, name);
    return v ? [v isEqualToString:@"YES"] : fallback;
}

static NSAttributeType attribute_type_named(NSString *s)
{
    static NSDictionary *types;
    if (!types)
        types = [@{
            @"Undefined" : @(NSUndefinedAttributeType),
            @"Integer 16" : @(NSInteger16AttributeType),
            @"Integer 32" : @(NSInteger32AttributeType),
            @"Integer 64" : @(NSInteger64AttributeType),
            @"Decimal" : @(NSDecimalAttributeType),
            @"Double" : @(NSDoubleAttributeType),
            @"Float" : @(NSFloatAttributeType),
            @"String" : @(NSStringAttributeType),
            @"Boolean" : @(NSBooleanAttributeType),
            @"Date" : @(NSDateAttributeType),
            @"Binary" : @(NSBinaryDataAttributeType),
            @"UUID" : @(NSUUIDAttributeType),
            @"URI" : @(NSURIAttributeType),
            @"Transformable" : @(NSTransformableAttributeType),
            @"ObjectID" : @(NSObjectIDAttributeType),
        } retain];
    NSNumber *n = [types objectForKey:s];
    return n ? [n unsignedIntegerValue] : NSUndefinedAttributeType;
}

/* A default or limit written as a string, in the attribute's type. */
static id value_from_string(NSString *s, NSAttributeType type)
{
    if (!s)
        return nil;
    switch (type) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType: return @([s longLongValue]);
    case NSDecimalAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType: return @([s doubleValue]);
    case NSBooleanAttributeType: return @([s isEqualToString:@"YES"] || [s boolValue]);
    case NSStringAttributeType: return s;
    case NSDateAttributeType: return [NSDate dateWithTimeIntervalSinceReferenceDate:[s doubleValue]];
    case NSUUIDAttributeType: return [[[NSUUID alloc] initWithUUIDString:s] autorelease];
    case NSURIAttributeType: return [NSURL URLWithString:s];
    default: return nil;
    }
}

static NSAttributeDescription *read_attribute(NSXMLElement *el)
{
    NSAttributeDescription *a = [[[NSAttributeDescription alloc] init] autorelease];
    [a setName:xml_attr(el, @"name")];
    [a setOptional:xml_bool(el, @"optional", NO)];
    [a setTransient:xml_bool(el, @"transient", NO)];
    [a setIndexed:xml_bool(el, @"indexed", NO)];
    NSAttributeType type = attribute_type_named(xml_attr(el, @"attributeType"));
    [a setAttributeType:type];
    if (xml_attr(el, @"customClassName"))
        [a setAttributeValueClassName:xml_attr(el, @"customClassName")];
    if (xml_attr(el, @"valueTransformerName"))
        [a setValueTransformerName:xml_attr(el, @"valueTransformerName")];
    [a setAllowsExternalBinaryDataStorage:xml_bool(el, @"allowsExternalBinaryDataStorage", NO)];
    [a setDefaultValue:value_from_string(xml_attr(el, @"defaultValueString"), type)];
    if ([xml_attr(el, @"defaultDateTimeInterval") length])
        [a setDefaultValue:[NSDate dateWithTimeIntervalSinceReferenceDate:[xml_attr(el, @"defaultDateTimeInterval")
                                                                                   doubleValue]]];
    /* The model editor's limits, as the validation predicates they stand for. */
    NSMutableArray *preds = [NSMutableArray array], *warnings = [NSMutableArray array];
    BOOL text = type == NSStringAttributeType;
    NSString *min = xml_attr(el, @"minValueString"), *max = xml_attr(el, @"maxValueString");
    if ([min length]) {
        [preds addObject:text ? [NSPredicate predicateWithFormat:@"length >= %lld", [min longLongValue]]
                              : [NSPredicate predicateWithFormat:@"SELF >= %@", value_from_string(min, type)]];
        [warnings addObject:text ? @"NSValidationStringTooShortError" : @"NSValidationNumberTooSmallError"];
    }
    if ([max length]) {
        [preds addObject:text ? [NSPredicate predicateWithFormat:@"length <= %lld", [max longLongValue]]
                              : [NSPredicate predicateWithFormat:@"SELF <= %@", value_from_string(max, type)]];
        [warnings addObject:text ? @"NSValidationStringTooLongError" : @"NSValidationNumberTooLargeError"];
    }
    NSString *regex = xml_attr(el, @"regularExpressionString");
    if ([regex length]) {
        [preds addObject:[NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex]];
        [warnings addObject:@"NSValidationStringPatternMatchingError"];
    }
    if ([preds count])
        [a setValidationPredicates:preds withValidationWarnings:warnings];
    return a;
}

static NSDeleteRule delete_rule_named(NSString *s)
{
    if ([s isEqualToString:@"Cascade"])
        return NSCascadeDeleteRule;
    if ([s isEqualToString:@"Deny"])
        return NSDenyDeleteRule;
    if ([s isEqualToString:@"No Action"])
        return NSNoActionDeleteRule;
    return NSNullifyDeleteRule;
}

static NSRelationshipDescription *read_relationship(NSXMLElement *el)
{
    NSRelationshipDescription *r = [[[NSRelationshipDescription alloc] init] autorelease];
    [r setName:xml_attr(el, @"name")];
    [r setOptional:xml_bool(el, @"optional", NO)];
    [r setTransient:xml_bool(el, @"transient", NO)];
    BOOL toMany = xml_bool(el, @"toMany", NO);
    NSString *max = xml_attr(el, @"maxCount"), *min = xml_attr(el, @"minCount");
    [r setMaxCount:toMany ? (NSUInteger)[max longLongValue] : 1];
    if (toMany && [r maxCount] == 1)
        [r setMaxCount:0];
    [r setMinCount:(NSUInteger)[min longLongValue]];
    [r setOrdered:xml_bool(el, @"ordered", NO)];
    [r setDeleteRule:delete_rule_named(xml_attr(el, @"deletionRule"))];
    [(id)r cd_setDestinationName:xml_attr(el, @"destinationEntity") inverseName:xml_attr(el, @"inverseName")];
    return r;
}

+ (NSManagedObjectModel *)cd_modelFromSourceAtURL:(NSURL *)url
{
    NSString *path = [url path];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([[path pathExtension] isEqualToString:@"xcdatamodeld"]) {
        NSDictionary *current =
            [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@".xccurrentversion"]];
        NSString *name = [current objectForKey:@"_XCCurrentVersionName"];
        if (!name)
            for (NSString *n in [[fm contentsOfDirectoryAtPath:path error:NULL]
                     sortedArrayUsingSelector:@selector(compare:)])
                if ([[n pathExtension] isEqualToString:@"xcdatamodel"])
                    name = n;
        if (!name)
            return nil;
        path = [path stringByAppendingPathComponent:name];
    }
    if ([[path pathExtension] isEqualToString:@"xcdatamodel"])
        path = [path stringByAppendingPathComponent:@"contents"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data)
        return nil;
    NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithData:data options:0 error:NULL] autorelease];
    NSXMLElement *root = [doc rootElement];
    if (![[root name] isEqualToString:@"model"])
        return nil;

    NSMutableArray *entities = [NSMutableArray array];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary], *parents = [NSMutableDictionary dictionary];
    for (NSXMLElement *el in [root elementsForName:@"entity"]) {
        NSEntityDescription *e = [[[NSEntityDescription alloc] init] autorelease];
        [e setName:xml_attr(el, @"name")];
        if (xml_attr(el, @"representedClassName"))
            [e setManagedObjectClassName:xml_attr(el, @"representedClassName")];
        [e setAbstract:xml_bool(el, @"isAbstract", NO)];
        NSMutableArray *props = [NSMutableArray array];
        for (NSXMLElement *p in [el children]) {
            if (![p isKindOfClass:[NSXMLElement class]])
                continue;
            if ([[p name] isEqualToString:@"attribute"])
                [props addObject:read_attribute(p)];
            else if ([[p name] isEqualToString:@"relationship"])
                [props addObject:read_relationship(p)];
        }
        NSMutableArray *constraints = [NSMutableArray array];
        for (NSXMLElement *u in [el elementsForName:@"uniquenessConstraints"])
            for (NSXMLElement *c in [u elementsForName:@"uniquenessConstraint"]) {
                NSMutableArray *names = [NSMutableArray array];
                for (NSXMLElement *k in [c elementsForName:@"constraint"])
                    if (xml_attr(k, @"value"))
                        [names addObject:xml_attr(k, @"value")];
                [constraints addObject:names];
            }
        if ([constraints count])
            [e setUniquenessConstraints:constraints];
        [e setProperties:props];
        if (xml_attr(el, @"parentEntity"))
            [parents setObject:xml_attr(el, @"parentEntity") forKey:[e name]];
        [entities addObject:e];
        if ([e name])
            [byName setObject:e forKey:[e name]];
    }
    for (NSEntityDescription *e in entities) {
        NSMutableArray *subs = [NSMutableArray array];
        for (NSEntityDescription *s in entities)
            if ([[parents objectForKey:[s name]] isEqualToString:[e name]])
                [subs addObject:s];
        if ([subs count])
            [e setSubentities:subs];
    }
    for (NSEntityDescription *e in entities)
        for (NSPropertyDescription *p in [e properties])
            if ([p isKindOfClass:[NSRelationshipDescription class]])
                [(id)p cd_resolveInModel:byName];

    NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
    [model setEntities:entities];
    for (NSXMLElement *c in [root elementsForName:@"configuration"]) {
        NSMutableArray *members = [NSMutableArray array];
        for (NSXMLElement *m in [c elementsForName:@"memberEntity"])
            if ([byName objectForKey:xml_attr(m, @"name")])
                [members addObject:[byName objectForKey:xml_attr(m, @"name")]];
        if (xml_attr(c, @"name"))
            [model setEntities:members forConfiguration:xml_attr(c, @"name")];
    }
    for (NSXMLElement *f in [root elementsForName:@"fetchRequest"]) {
        NSString *entity = xml_attr(f, @"entity"), *pred = xml_attr(f, @"predicateString");
        if (!xml_attr(f, @"name") || ![byName objectForKey:entity])
            continue;
        NSFetchRequest *r = [NSFetchRequest fetchRequestWithEntityName:entity];
        [r setEntity:[byName objectForKey:entity]];
        if ([pred length])
            [r setPredicate:[NSPredicate predicateWithFormat:pred]];
        [model setFetchRequestTemplate:r forName:xml_attr(f, @"name")];
    }
    return model;
}
@end
