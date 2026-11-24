/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: NSPersistentStoreDescription and NSPersistentContainer,
 * as Apple's class references describe them (freemac 1.NEXT, Ferry
 * 0.NEXT). Our own code; no Apple code was used.
 *
 * A container made with a name and no model looks in the main bundle for
 * the model's source (<name>.xcdatamodeld or <name>.xcdatamodel), which
 * Ferry reads; a compiled model (<name>.momd or <name>.mom) isn't read, and
 * the container says so once on stderr. Its store is <name>.sqlite in the
 * user's Application Support folder. */
#import "CDInternal.h"

@implementation NSPersistentStoreDescription {
    NSString *_type, *_configuration;
    NSURL *_URL;
    NSMutableDictionary *_options, *_pragmas;
    BOOL _readOnly, _async, _migrate, _infer;
    NSTimeInterval _timeout;
}
+ (instancetype)persistentStoreDescriptionWithURL:(NSURL *)url { return [[[self alloc] initWithURL:url] autorelease]; }
- (instancetype)init { return [self initWithURL:nil]; }
- (instancetype)initWithURL:(NSURL *)url
{
    if ((self = [super init])) {
        _type = [NSSQLiteStoreType copy];
        _URL = [url copy];
        _options = [[NSMutableDictionary alloc] init];
        _pragmas = [[NSMutableDictionary alloc] init];
        _migrate = _infer = YES;
        _timeout = 240;
    }
    return self;
}
- (void)dealloc
{
    [_type release];
    [_configuration release];
    [_URL release];
    [_options release];
    [_pragmas release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSPersistentStoreDescription *c = [[[self class] alloc] initWithURL:_URL];
    [c setType:_type];
    [c setConfiguration:_configuration];
    [c->_options setDictionary:_options];
    [c->_pragmas setDictionary:_pragmas];
    c->_readOnly = _readOnly, c->_async = _async, c->_migrate = _migrate, c->_infer = _infer, c->_timeout = _timeout;
    return c;
}
- (NSString *)type { return _type; }
- (void)setType:(NSString *)type
{
    [_type autorelease];
    _type = [type copy];
}
- (NSString *)configuration { return _configuration; }
- (void)setConfiguration:(NSString *)configuration
{
    [_configuration autorelease];
    _configuration = [configuration copy];
}
- (NSURL *)URL { return _URL; }
- (void)setURL:(NSURL *)url
{
    [_URL autorelease];
    _URL = [url copy];
}
- (NSDictionary *)options { return [[_options copy] autorelease]; }
- (void)setOption:(NSObject *)option forKey:(NSString *)key
{
    if (option)
        [_options setObject:option forKey:key];
    else
        [_options removeObjectForKey:key];
}
- (BOOL)isReadOnly { return _readOnly; }
- (void)setReadOnly:(BOOL)flag { _readOnly = flag; }
- (NSTimeInterval)timeout { return _timeout; }
- (void)setTimeout:(NSTimeInterval)t { _timeout = t; }
- (NSDictionary *)sqlitePragmas { return [[_pragmas copy] autorelease]; }
- (void)setValue:(NSObject *)value forPragmaNamed:(NSString *)name
{
    if (value)
        [_pragmas setObject:value forKey:name];
    else
        [_pragmas removeObjectForKey:name];
}
- (BOOL)shouldAddStoreAsynchronously { return _async; }
- (void)setShouldAddStoreAsynchronously:(BOOL)flag { _async = flag; }
- (BOOL)shouldMigrateStoreAutomatically { return _migrate; }
- (void)setShouldMigrateStoreAutomatically:(BOOL)flag { _migrate = flag; }
- (BOOL)shouldInferMappingModelAutomatically { return _infer; }
- (void)setShouldInferMappingModelAutomatically:(BOOL)flag { _infer = flag; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSPersistentStoreDescription: %p> (type: %@, url: %@)", self, _type,
                                      [_URL absoluteString]];
}
@end

/* The model a container named name uses when it is given none. */
static NSManagedObjectModel *model_named(NSString *name)
{
    NSBundle *bundle = [NSBundle mainBundle];
    for (NSString *ext in @[ @"xcdatamodeld", @"xcdatamodel" ]) {
        NSURL *url = [bundle URLForResource:name withExtension:ext];
        NSManagedObjectModel *m = url ? [NSManagedObjectModel cd_modelFromSourceAtURL:url] : nil;
        if (m)
            return m;
    }
    for (NSString *ext in @[ @"momd", @"mom" ]) {
        NSURL *url = [bundle URLForResource:name withExtension:ext];
        if (url) {
            CDCompiledModelUnsupported([url path]);
            return nil;
        }
    }
    CDWarnOnce([@"containermodel:" stringByAppendingString:name ?: @""],
               [NSString stringWithFormat:@"Ferry: Core Data found no model named %@ for NSPersistentContainer.", name]);
    return nil;
}

@implementation NSPersistentContainer {
    NSString *_name;
    NSManagedObjectModel *_model;
    NSPersistentStoreCoordinator *_coordinator;
    NSManagedObjectContext *_viewContext;
    NSArray *_descriptions;
}

+ (instancetype)persistentContainerWithName:(NSString *)name { return [[[self alloc] initWithName:name] autorelease]; }
+ (instancetype)persistentContainerWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model
{
    return [[[self alloc] initWithName:name managedObjectModel:model] autorelease];
}

+ (NSURL *)defaultDirectoryURL
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dir = [dirs count] ? [dirs objectAtIndex:0]
                                 : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [NSURL fileURLWithPath:dir isDirectory:YES];
}

- (instancetype)initWithName:(NSString *)name { return [self initWithName:name managedObjectModel:model_named(name)]; }

- (instancetype)initWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model
{
    if ((self = [super init])) {
        _name = [name copy];
        _model = [model retain];
        _coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        _viewContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [_viewContext setPersistentStoreCoordinator:_coordinator];
        NSURL *url = [[[self class] defaultDirectoryURL]
            URLByAppendingPathComponent:[(name ?: @"Model") stringByAppendingPathExtension:@"sqlite"]];
        _descriptions = [@[ [NSPersistentStoreDescription persistentStoreDescriptionWithURL:url] ] copy];
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_model release];
    [_viewContext release];
    [_coordinator release];
    [_descriptions release];
    [super dealloc];
}

- (NSString *)name { return _name; }
- (NSManagedObjectModel *)managedObjectModel { return _model; }
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator { return _coordinator; }
- (NSManagedObjectContext *)viewContext { return _viewContext; }
- (NSArray *)persistentStoreDescriptions { return _descriptions; }
- (void)setPersistentStoreDescriptions:(NSArray *)descriptions
{
    [_descriptions autorelease];
    _descriptions = [descriptions copy] ?: [[NSArray alloc] init];
}

- (void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription *, NSError *))block
{
    for (NSPersistentStoreDescription *d in _descriptions) {
        if (!_model) {
            if (block)
                block(d, CDError(NSPersistentStoreOperationError,
                                 [NSString stringWithFormat:@"The container %@ has no model, so no store was loaded.", _name],
                                 nil));
            continue;
        }
        [_coordinator addPersistentStoreWithDescription:d completionHandler:block];
    }
}

- (NSManagedObjectContext *)newBackgroundContext
{
    NSManagedObjectContext *c = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [c setPersistentStoreCoordinator:_coordinator];
    return c;
}

- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *))block
{
    NSManagedObjectContext *c = [[self newBackgroundContext] autorelease];
    void (^b)(NSManagedObjectContext *) = [[block copy] autorelease];
    [c performBlock:^{
        b(c);
    }];
}
@end
