/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: the URL cache. NSCachedURLResponse and NSURLCache,
 * with a part in memory (the most recently used responses, up to its
 * memory capacity) and a part on disk (one property list a response, in
 * the cache's folder, the oldest removed past its disk capacity). The
 * shared cache keeps its disk part in ~/.cache/<app id>/URLCache, as a
 * Mac keeps it in ~/Library/Caches/<app id>. Which responses are stored,
 * and when a stored one is used, is decided by the loads themselves
 * (NSURLSession.m). Written from Apple's public API documentation; the
 * files are Ferry's own format. */
#import "FURLInternal.h"
#include <sys/stat.h>
#include <unistd.h>

/* ---- NSCachedURLResponse --------------------------------------------------------------------- */

@interface NSCachedURLResponse () {
    NSURLResponse *_response;
    NSData *_data;
    NSDictionary *_userInfo;
    NSURLCacheStoragePolicy _policy;
    NSDate *_storedAt;
}
@end

@implementation NSCachedURLResponse
- (instancetype)initWithResponse:(NSURLResponse *)response data:(NSData *)data
{
    return [self initWithResponse:response data:data userInfo:nil storagePolicy:NSURLCacheStorageAllowed];
}
- (instancetype)initWithResponse:(NSURLResponse *)response data:(NSData *)data userInfo:(NSDictionary *)userInfo
                   storagePolicy:(NSURLCacheStoragePolicy)storagePolicy
{
    _response = [response retain];
    _data = [data copy] ?: [[NSData alloc] init];
    _userInfo = [userInfo copy];
    _policy = storagePolicy;
    return self;
}
- (void)dealloc
{
    [_response release];
    [_data release];
    [_userInfo release];
    [_storedAt release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSURLResponse *)response { return _response; }
- (NSData *)data { return _data; }
- (NSDictionary *)userInfo { return _userInfo; }
- (NSURLCacheStoragePolicy)storagePolicy { return _policy; }
- (NSDate *)_storedAt { return _storedAt; }
- (void)_setStoredAt:(NSDate *)date
{
    [date retain];
    [_storedAt release];
    _storedAt = date;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSCachedURLResponse: %p> { %@, %lu bytes }", self, [[_response URL] absoluteString],
                                      (unsigned long)[_data length]];
}
@end

/* ---- NSURLCache ------------------------------------------------------------------------------ */

@interface NSURLCache () {
    NSUInteger _memoryCapacity, _diskCapacity, _memoryUsage;
    NSString *_dir;                /* nil: nothing on disk */
    NSMutableDictionary *_memory;  /* key -> NSCachedURLResponse */
    NSMutableArray *_order;        /* keys, the least recently used first */
}
@end

/* The key a request's response is kept under: its URL without the fragment. */
static NSString *key_for(NSURLRequest *request)
{
    NSString *s = [[[request URL] absoluteURL] absoluteString];
    NSRange hash = s ? [s rangeOfString:@"#"] : NSMakeRange(NSNotFound, 0);
    return hash.location == NSNotFound ? s : [s substringToIndex:hash.location];
}

static NSString *file_name(NSString *key)
{
    uint64_t h = 1469598103934665603ULL;
    for (const unsigned char *p = (const unsigned char *)[key UTF8String]; *p; p++)
        h = (h ^ *p) * 1099511628211ULL;
    return [NSString stringWithFormat:@"%016llx.plist", (unsigned long long)h];
}

static NSString *cache_home(void)
{
    return [FUserFolder(NSCachesDirectory) stringByAppendingPathComponent:FURLAppID()];
}

static NSDictionary *encode(NSCachedURLResponse *c, NSString *key)
{
    NSURLResponse *r = [c response];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [d setObject:key forKey:@"Key"];
    [d setObject:[[r URL] absoluteString] ?: key forKey:@"URL"];
    if ([r isKindOfClass:[NSHTTPURLResponse class]]) {
        [d setObject:[NSNumber numberWithInteger:[(NSHTTPURLResponse *)r statusCode]] forKey:@"Status"];
        [d setObject:[(NSHTTPURLResponse *)r allHeaderFields] ?: [NSDictionary dictionary] forKey:@"Headers"];
    } else {
        if ([r MIMEType])
            [d setObject:[r MIMEType] forKey:@"MIMEType"];
        if ([r textEncodingName])
            [d setObject:[r textEncodingName] forKey:@"TextEncodingName"];
        [d setObject:[NSNumber numberWithLongLong:[r expectedContentLength]] forKey:@"ExpectedContentLength"];
    }
    [d setObject:[c data] forKey:@"Data"];
    [d setObject:[c _storedAt] ?: [NSDate date] forKey:@"Stored"];
    [d setObject:[NSNumber numberWithUnsignedInteger:[c storagePolicy]] forKey:@"StoragePolicy"];
    if ([c userInfo])
        [d setObject:[c userInfo] forKey:@"UserInfo"];
    return d;
}

static NSCachedURLResponse *decode(NSDictionary *d)
{
    NSURL *url = [NSURL URLWithString:[d objectForKey:@"URL"]];
    NSData *data = [d objectForKey:@"Data"];
    if (!url || ![data isKindOfClass:[NSData class]])
        return nil;
    NSURLResponse *r;
    if ([d objectForKey:@"Status"])
        r = [[[NSHTTPURLResponse alloc] initWithURL:url statusCode:[[d objectForKey:@"Status"] integerValue]
                                        HTTPVersion:@"HTTP/1.1"
                                       headerFields:[d objectForKey:@"Headers"]] autorelease];
    else
        r = [[[NSURLResponse alloc] initWithURL:url MIMEType:[d objectForKey:@"MIMEType"]
                          expectedContentLength:[[d objectForKey:@"ExpectedContentLength"] integerValue]
                               textEncodingName:[d objectForKey:@"TextEncodingName"]] autorelease];
    NSCachedURLResponse *c =
        [[[NSCachedURLResponse alloc] initWithResponse:r data:data userInfo:[d objectForKey:@"UserInfo"]
                                         storagePolicy:[[d objectForKey:@"StoragePolicy"] unsignedIntegerValue]]
            autorelease];
    [c _setStoredAt:[d objectForKey:@"Stored"]];
    return c;
}

@implementation NSURLCache
static NSURLCache *shared_cache;

+ (NSURLCache *)sharedURLCache
{
    if (!shared_cache)
        shared_cache = [[NSURLCache alloc] initWithMemoryCapacity:512 * 1024 diskCapacity:10 * 1024 * 1024
                                                         diskPath:nil];
    return shared_cache;
}
+ (void)setSharedURLCache:(NSURLCache *)cache
{
    [cache retain];
    [shared_cache release];
    shared_cache = cache;
}
+ (instancetype)_memoryOnlyCache
{
    NSURLCache *c = [[[self alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:0 diskPath:nil] autorelease];
    [c->_dir release];
    c->_dir = nil;
    return c;
}
- (instancetype)init { return [self initWithMemoryCapacity:512 * 1024 diskCapacity:10 * 1024 * 1024 diskPath:nil]; }
- (instancetype)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity
                              diskPath:(NSString *)path
{
    _memoryCapacity = memoryCapacity;
    _diskCapacity = diskCapacity;
    if (![path length])
        path = @"URLCache";
    _dir = [([path isAbsolutePath] ? path : [cache_home() stringByAppendingPathComponent:path]) copy];
    _memory = [[NSMutableDictionary alloc] init];
    _order = [[NSMutableArray alloc] init];
    return self;
}
- (instancetype)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity
                          directoryURL:(NSURL *)directoryURL
{
    return [self initWithMemoryCapacity:memoryCapacity diskCapacity:diskCapacity diskPath:[directoryURL path]];
}
- (void)dealloc
{
    [_dir release];
    [_memory release];
    [_order release];
    [super dealloc];
}

/* ---- the part in memory */

- (void)_forget:(NSString *)key
{
    NSCachedURLResponse *c = [_memory objectForKey:key];
    if (!c)
        return;
    _memoryUsage -= [[c data] length];
    [_memory removeObjectForKey:key];
    [_order removeObject:key];
}
- (void)_trimMemory
{
    while (_memoryUsage > _memoryCapacity && [_order count])
        [self _forget:[_order objectAtIndex:0]];
}
- (void)_remember:(NSCachedURLResponse *)c key:(NSString *)key
{
    [self _forget:key];
    if ([[c data] length] > _memoryCapacity)
        return;
    [_memory setObject:c forKey:key];
    [_order addObject:key];
    _memoryUsage += [[c data] length];
    [self _trimMemory];
}

/* ---- the part on disk */

- (NSArray *)_files
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_dir error:NULL])
        if ([name hasSuffix:@".plist"])
            [out addObject:[_dir stringByAppendingPathComponent:name]];
    return out;
}
static off_t file_size(NSString *path, time_t *mtime)
{
    struct stat st;
    if (stat([path fileSystemRepresentation], &st))
        return -1;
    if (mtime)
        *mtime = st.st_mtime;
    return st.st_size;
}
static NSInteger oldest_first(id a, id b, void *ctx)
{
    time_t ta = 0, tb = 0;
    file_size(a, &ta);
    file_size(b, &tb);
    return ta < tb ? NSOrderedAscending : ta > tb ? NSOrderedDescending : [a compare:b];
}
- (void)_trimDisk
{
    if (!_dir)
        return;
    NSArray *files = [[self _files] sortedArrayUsingFunction:oldest_first context:NULL];
    unsigned long long total = 0;
    for (NSString *f in files)
        total += (unsigned long long)MAX(file_size(f, NULL), 0);
    for (NSString *f in files) {
        if (total <= _diskCapacity)
            break;
        total -= (unsigned long long)MAX(file_size(f, NULL), 0);
        unlink([f fileSystemRepresentation]);
    }
}
- (NSCachedURLResponse *)_read:(NSString *)key
{
    if (!_dir || !_diskCapacity)
        return nil;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[_dir stringByAppendingPathComponent:file_name(key)]];
    if (![[d objectForKey:@"Key"] isEqual:key])
        return nil;
    return decode(d);
}

/* ---- the calls */

- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    NSString *key = key_for(request);
    if (!key)
        return nil;
    NSCachedURLResponse *c = [_memory objectForKey:key];
    if (c) {
        [[c retain] autorelease];
        [_order removeObject:key];
        [_order addObject:key];
        return c;
    }
    c = [self _read:key];
    if (c && [c storagePolicy] == NSURLCacheStorageAllowed)
        [self _remember:c key:key];
    return c;
}
- (void)storeCachedResponse:(NSCachedURLResponse *)c forRequest:(NSURLRequest *)request
{
    NSString *key = key_for(request);
    if (!c || !key || [c storagePolicy] == NSURLCacheStorageNotAllowed)
        return;
    if (![c _storedAt])
        [c _setStoredAt:[NSDate date]];
    [self _remember:c key:key];
    NSString *file = _dir ? [_dir stringByAppendingPathComponent:file_name(key)] : nil;
    if (file)
        unlink([file fileSystemRepresentation]);
    if (!file || [c storagePolicy] != NSURLCacheStorageAllowed || [[c data] length] > _diskCapacity)
        return;
    [[NSFileManager defaultManager] createDirectoryAtPath:_dir withIntermediateDirectories:YES attributes:nil
                                                    error:NULL];
    NSDictionary *d = encode(c, key);
    if (![d writeToFile:file atomically:YES] && [c userInfo]) {
        /* user information that can't be written is kept in memory only */
        NSMutableDictionary *m = [[d mutableCopy] autorelease];
        [m removeObjectForKey:@"UserInfo"];
        [m writeToFile:file atomically:YES];
    }
    [self _trimDisk];
}
- (void)removeCachedResponseForRequest:(NSURLRequest *)request
{
    NSString *key = key_for(request);
    if (!key)
        return;
    [self _forget:key];
    if (_dir)
        unlink([[_dir stringByAppendingPathComponent:file_name(key)] fileSystemRepresentation]);
}
- (void)removeAllCachedResponses
{
    [_memory removeAllObjects];
    [_order removeAllObjects];
    _memoryUsage = 0;
    if (_dir)
        for (NSString *f in [self _files])
            unlink([f fileSystemRepresentation]);
}
- (void)removeCachedResponsesSinceDate:(NSDate *)date
{
    for (NSString *key in [[_order copy] autorelease])
        if ([[[_memory objectForKey:key] _storedAt] compare:date] != NSOrderedAscending)
            [self _forget:key];
    if (_dir)
        for (NSString *f in [self _files]) {
            NSDate *stored = [[NSDictionary dictionaryWithContentsOfFile:f] objectForKey:@"Stored"];
            if (!stored || [stored compare:date] != NSOrderedAscending)
                unlink([f fileSystemRepresentation]);
        }
}
- (NSUInteger)memoryCapacity { return _memoryCapacity; }
- (void)setMemoryCapacity:(NSUInteger)n
{
    _memoryCapacity = n;
    [self _trimMemory];
}
- (NSUInteger)diskCapacity { return _diskCapacity; }
- (void)setDiskCapacity:(NSUInteger)n
{
    _diskCapacity = n;
    [self _trimDisk];
}
- (NSUInteger)currentMemoryUsage { return _memoryUsage; }
- (NSUInteger)currentDiskUsage
{
    unsigned long long total = 0;
    if (_dir)
        for (NSString *f in [self _files])
            total += (unsigned long long)MAX(file_size(f, NULL), 0);
    return (NSUInteger)total;
}
- (void)storeCachedResponse:(NSCachedURLResponse *)c forDataTask:(NSURLSessionDataTask *)task
{
    [self storeCachedResponse:c forRequest:[task currentRequest]];
}
- (void)getCachedResponseForDataTask:(NSURLSessionDataTask *)task
                   completionHandler:(void (^)(NSCachedURLResponse *))completionHandler
{
    if (completionHandler)
        completionHandler([self cachedResponseForRequest:[task currentRequest]]);
}
- (void)removeCachedResponseForDataTask:(NSURLSessionDataTask *)task
{
    [self removeCachedResponseForRequest:[task currentRequest]];
}
@end
