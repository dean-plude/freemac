/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSNetService and NSNetServiceBrowser (Bonjour). Our own code, written
 * from Apple's public API documentation of NSNetService,
 * NSNetServiceBrowser and their delegates, and RFC 6763 for TXT records.
 *
 * Ferry has no multicast DNS of its own and doesn't talk to this system's
 * (Avahi) yet: publishing, resolving and searching start as on a Mac (the
 * "will" message first) and then fail, in the run loop the object is
 * scheduled in, with NSNetServicesErrorCode NSNetServicesUnknownError in
 * the error dictionary, so a program goes its no-Bonjour way. TXT records
 * are made and read in full, and a service made with a host's addresses
 * is not needed for anything else here. */
#import "FInternal.h"
#include <Foundation/NSNetServices.h>

NSString *const NSNetServicesErrorCode = @"NSNetServicesErrorCode";
NSString *const NSNetServicesErrorDomain = @"NSNetServicesErrorDomain";

static NSDictionary *unavailable(void)
{
    FVerboseOnce(@"Bonjour (NSNetService, NSNetServiceBrowser) isn't offered yet: publishing, resolving and "
                 @"searching report NSNetServicesUnknownError");
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:NSNetServicesUnknownError],
                                                      NSNetServicesErrorCode, [NSNumber numberWithInteger:10],
                                                      NSNetServicesErrorDomain, nil];
}

/* Where the delegate hears: the run loops it was scheduled in, by default the one current when made. */
static NSRunLoop *first_loop(NSMutableArray *places)
{
    @synchronized(places) {
        return [places count] ? [[places objectAtIndex:0] objectAtIndex:0] : nil;
    }
}
static void place(NSMutableArray *places, NSRunLoop *loop, NSString *mode, BOOL add)
{
    if (!loop)
        return;
    NSArray *pair = [NSArray arrayWithObjects:loop, mode ?: @"", nil];
    @synchronized(places) {
        if (add && ![places containsObject:pair])
            [places addObject:pair];
        else if (!add)
            [places removeObject:pair];
    }
}

@implementation NSNetService {
    NSString *_domain, *_type, *_name;
    NSInteger _port;
    NSData *_txt;
    NSMutableArray *_places;
    id _delegate;
    BOOL _includesPeerToPeer;
    BOOL _busy;
}
@synthesize delegate = _delegate, includesPeerToPeer = _includesPeerToPeer, name = _name, type = _type,
            domain = _domain, port = _port;
- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(int)port
{
    self = [super init];
    if (self) {
        _domain = [domain copy] ?: @"";
        _type = [type copy] ?: @"";
        _name = [name copy] ?: @"";
        _port = port;
        _places = [[NSMutableArray alloc] init];
        place(_places, [NSRunLoop currentRunLoop], NSDefaultRunLoopMode, YES);
    }
    return self;
}
- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name
{
    self = [self initWithDomain:domain type:type name:name port:-1];
    return self;
}
- (void)dealloc
{
    [_domain release];
    [_type release];
    [_name release];
    [_txt release];
    [_places release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSNetService %p> %@.%@%@ %ld", self, _domain, _type, _name, (long)_port];
}
- (NSString *)hostName { return nil; }
- (NSArray *)addresses { return nil; }
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode { place(_places, loop, mode, YES); }
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode { place(_places, loop, mode, NO); }
/* "will", then the failure, on the delegate's loop */
- (void)_start:(SEL)will fail:(SEL)fail
{
    NSRunLoop *loop = first_loop(_places);
    if (!loop)
        return;
    if (_busy) {
        NSDictionary *e = [NSDictionary
            dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:NSNetServicesActivityInProgress],
                                         NSNetServicesErrorCode, [NSNumber numberWithInteger:10],
                                         NSNetServicesErrorDomain, nil];
        [loop performBlock:^{
          if ([_delegate respondsToSelector:fail])
              ((void (*)(id, SEL, id, id))objc_msgSend)(_delegate, fail, self, e);
        }];
        return;
    }
    _busy = YES;
    [loop performBlock:^{
      if ([_delegate respondsToSelector:will])
          ((void (*)(id, SEL, id))objc_msgSend)(_delegate, will, self);
      _busy = NO;
      if ([_delegate respondsToSelector:fail])
          ((void (*)(id, SEL, id, id))objc_msgSend)(_delegate, fail, self, unavailable());
    }];
}
- (void)publish { [self publishWithOptions:0]; }
- (void)publishWithOptions:(NSNetServiceOptions)options
{
    [self _start:@selector(netServiceWillPublish:) fail:@selector(netService:didNotPublish:)];
}
- (void)resolve { [self resolveWithTimeout:5]; }
- (void)resolveWithTimeout:(NSTimeInterval)timeout
{
    [self _start:@selector(netServiceWillResolve:) fail:@selector(netService:didNotResolve:)];
}
- (void)stop {}
- (void)startMonitoring {}
- (void)stopMonitoring {}
- (BOOL)getInputStream:(NSInputStream **)inputStream outputStream:(NSOutputStream **)outputStream
{
    if (inputStream)
        *inputStream = nil;
    if (outputStream)
        *outputStream = nil;
    return NO;
}
- (NSData *)TXTRecordData { return _txt; }
- (BOOL)setTXTRecordData:(NSData *)recordData
{
    id wasTxt = _txt;
    _txt = [recordData copy];
    [wasTxt release];
    return YES;
}

/* RFC 6763 section 6: strings of up to 255 bytes, each "key=value" or a lone "key". */
+ (NSDictionary *)dictionaryFromTXTRecordData:(NSData *)txtData
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    const unsigned char *p = [txtData bytes];
    NSUInteger len = [txtData length], i = 0;
    while (i < len) {
        NSUInteger n = p[i++];
        if (n > len - i)
            break;
        const unsigned char *s = p + i, *eq = memchr(s, '=', n);
        NSUInteger klen = eq ? (NSUInteger)(eq - s) : n;
        NSString *key = klen ? [[[NSString alloc] initWithBytes:s length:klen encoding:NSUTF8StringEncoding] autorelease]
                             : nil;
        /* the first of a key counts (RFC 6763 6.4); a lone key has no value */
        if (key && ![d objectForKey:key])
            [d setObject:eq ? [NSData dataWithBytes:eq + 1 length:n - klen - 1] : [NSData data] forKey:key];
        i += n;
    }
    return d;
}
+ (NSData *)dataFromTXTRecordDictionary:(NSDictionary *)txtDictionary
{
    NSMutableData *out = [NSMutableData data];
    for (NSString *key in [[txtDictionary allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        id value = [txtDictionary objectForKey:key];
        NSData *v = [value isKindOfClass:[NSData class]]   ? value
                    : [value isKindOfClass:[NSString class]] ? [value dataUsingEncoding:NSUTF8StringEncoding]
                                                             : nil;
        if (![key isKindOfClass:[NSString class]])
            return nil;
        NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger n = [k length] + (v ? 1 + [v length] : 0);
        if (![k length] || n > 255)
            return nil;
        unsigned char b = (unsigned char)n;
        [out appendBytes:&b length:1];
        [out appendData:k];
        if (v) {
            [out appendBytes:"=" length:1];
            [out appendData:v];
        }
    }
    return out;
}
@end

@implementation NSNetServiceBrowser {
    NSMutableArray *_places;
    id _delegate;
    BOOL _includesPeerToPeer;
}
@synthesize delegate = _delegate, includesPeerToPeer = _includesPeerToPeer;
- (instancetype)init
{
    self = [super init];
    if (self) {
        _places = [[NSMutableArray alloc] init];
        place(_places, [NSRunLoop currentRunLoop], NSDefaultRunLoopMode, YES);
    }
    return self;
}
- (void)dealloc
{
    [_places release];
    [super dealloc];
}
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode { place(_places, loop, mode, YES); }
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode { place(_places, loop, mode, NO); }
- (void)_search
{
    NSRunLoop *loop = first_loop(_places);
    [loop performBlock:^{
      if ([_delegate respondsToSelector:@selector(netServiceBrowserWillSearch:)])
          [_delegate netServiceBrowserWillSearch:self];
      if ([_delegate respondsToSelector:@selector(netServiceBrowser:didNotSearch:)])
          [_delegate netServiceBrowser:self didNotSearch:unavailable()];
    }];
}
- (void)searchForBrowsableDomains { [self _search]; }
- (void)searchForRegistrationDomains { [self _search]; }
- (void)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domainString { [self _search]; }
- (void)stop {}
@end
