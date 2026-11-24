/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: authentication for URL loading. NSURLCredential,
 * NSURLProtectionSpace, NSURLAuthenticationChallenge and
 * NSURLCredentialStorage (kept in memory: Ferry has no keychain), and the
 * MD5 digest that HTTP Digest authentication uses. Written from Apple's
 * public API documentation and RFC 1321; the challenges themselves are
 * made and answered in NSURLSession.m. */
#import "FURLInternal.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

NSString *const NSURLProtectionSpaceHTTP = @"http";
NSString *const NSURLProtectionSpaceHTTPS = @"https";
NSString *const NSURLProtectionSpaceFTP = @"ftp";
NSString *const NSURLProtectionSpaceHTTPProxy = @"http";
NSString *const NSURLProtectionSpaceHTTPSProxy = @"https";
NSString *const NSURLProtectionSpaceFTPProxy = @"ftp";
NSString *const NSURLProtectionSpaceSOCKSProxy = @"SOCKS";
NSString *const NSURLAuthenticationMethodDefault = @"NSURLAuthenticationMethodDefault";
NSString *const NSURLAuthenticationMethodHTTPBasic = @"NSURLAuthenticationMethodHTTPBasic";
NSString *const NSURLAuthenticationMethodHTTPDigest = @"NSURLAuthenticationMethodHTTPDigest";
NSString *const NSURLAuthenticationMethodHTMLForm = @"NSURLAuthenticationMethodHTMLForm";
NSString *const NSURLAuthenticationMethodNTLM = @"NSURLAuthenticationMethodNTLM";
NSString *const NSURLAuthenticationMethodNegotiate = @"NSURLAuthenticationMethodNegotiate";
NSString *const NSURLAuthenticationMethodClientCertificate = @"NSURLAuthenticationMethodClientCertificate";
NSString *const NSURLAuthenticationMethodServerTrust = @"NSURLAuthenticationMethodServerTrust";
NSNotificationName const NSURLCredentialStorageChangedNotification = @"NSURLCredentialStorageChangedNotification";
NSString *const NSURLCredentialStorageRemoveSynchronizableCredentials =
    @"NSURLCredentialStorageRemoveSynchronizableCredentials";

NSString *FURLAppID(void)
{
    return [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName] ?: @"ferry";
}

/* ---- MD5 (RFC 1321) ---------------------------------------------------------------------- */

static uint32_t rotl(uint32_t x, int c) { return (x << c) | (x >> (32 - c)); }

void FMD5(const void *data, size_t length, unsigned char digest[16])
{
    static uint32_t K[64];
    static const int shift[16] = {7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21};
    if (!K[0])
        for (int i = 0; i < 64; i++)
            K[i] = (uint32_t)(fabs(sin(i + 1.0)) * 4294967296.0);
    uint32_t h[4] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476};
    size_t total = ((length + 8) / 64 + 1) * 64;
    unsigned char *msg = calloc(total, 1);
    memcpy(msg, data, length);
    msg[length] = 0x80;
    uint64_t bits = (uint64_t)length * 8;
    for (int i = 0; i < 8; i++)
        msg[total - 8 + i] = (unsigned char)(bits >> (8 * i));
    for (size_t off = 0; off < total; off += 64) {
        uint32_t w[16];
        for (int i = 0; i < 16; i++)
            w[i] = (uint32_t)msg[off + i * 4] | (uint32_t)msg[off + i * 4 + 1] << 8 |
                   (uint32_t)msg[off + i * 4 + 2] << 16 | (uint32_t)msg[off + i * 4 + 3] << 24;
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
        for (int i = 0; i < 64; i++) {
            uint32_t f;
            int g;
            if (i < 16) {
                f = (b & c) | (~b & d);
                g = i;
            } else if (i < 32) {
                f = (d & b) | (~d & c);
                g = (5 * i + 1) % 16;
            } else if (i < 48) {
                f = b ^ c ^ d;
                g = (3 * i + 5) % 16;
            } else {
                f = c ^ (b | ~d);
                g = (7 * i) % 16;
            }
            uint32_t t = d;
            d = c;
            c = b;
            b = b + rotl(a + f + K[i] + w[g], shift[(i / 16) * 4 + i % 4]);
            a = t;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
    }
    free(msg);
    for (int i = 0; i < 16; i++)
        digest[i] = (unsigned char)(h[i / 4] >> (8 * (i % 4)));
}

NSString *FMD5Hex(NSString *text)
{
    const char *s = [text UTF8String] ?: "";
    unsigned char d[16];
    FMD5(s, strlen(s), d);
    char hex[33];
    for (int i = 0; i < 16; i++)
        snprintf(hex + 2 * i, 3, "%02x", d[i]);
    return [NSString stringWithUTF8String:hex];
}

/* ---- server trust ------------------------------------------------------------------------- */

@implementation FURLServerTrust
- (void)dealloc
{
    [host release];
    [security release];
    [super dealloc];
}
- (NSString *)_ferryTrustHost { return host; }
- (NSInteger)_ferryTrustPort { return port; }
- (id)_ferrySecurityTrust { return security; }
- (void)_setFerrySecurityTrust:(id)trust
{
    [trust retain];
    [security release];
    security = trust;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<FURLServerTrust %p> { %@:%ld }", self, host, (long)port];
}
@end

/* ---- NSURLCredential ---------------------------------------------------------------------- */

@interface NSURLCredential () {
    NSString *_user, *_password;
    NSURLCredentialPersistence _persistence;
    id _trust;
    SecIdentityRef _identity;
    NSArray *_certificates;
}
@end

@implementation NSURLCredential
+ (NSURLCredential *)credentialWithUser:(NSString *)user password:(NSString *)password
                            persistence:(NSURLCredentialPersistence)persistence
{
    return [[[self alloc] initWithUser:user password:password persistence:persistence] autorelease];
}
- (instancetype)initWithUser:(NSString *)user password:(NSString *)password
                 persistence:(NSURLCredentialPersistence)persistence
{
    _user = [user copy];
    _password = [password copy];
    _persistence = persistence;
    return self;
}
+ (NSURLCredential *)credentialForTrust:(SecTrustRef)trust { return [[[self alloc] initWithTrust:trust] autorelease]; }
- (instancetype)initWithTrust:(SecTrustRef)trust
{
    _trust = [(id)trust retain];
    _persistence = NSURLCredentialPersistenceForSession;
    return self;
}
+ (NSURLCredential *)credentialWithIdentity:(SecIdentityRef)identity certificates:(NSArray *)certArray
                                persistence:(NSURLCredentialPersistence)persistence
{
    return [[[self alloc] initWithIdentity:identity certificates:certArray persistence:persistence] autorelease];
}
- (instancetype)initWithIdentity:(SecIdentityRef)identity certificates:(NSArray *)certArray
                     persistence:(NSURLCredentialPersistence)persistence
{
    _identity = identity;
    _certificates = [certArray copy];
    _persistence = persistence;
    return self;
}
- (void)dealloc
{
    [_user release];
    [_password release];
    [_trust release];
    [_certificates release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)user { return _user; }
- (NSString *)password { return _password; }
- (BOOL)hasPassword { return _password != nil; }
- (NSURLCredentialPersistence)persistence { return _persistence; }
- (SecIdentityRef)identity { return _identity; }
- (NSArray *)certificates { return _certificates; }
- (BOOL)_isForTrust { return _trust != nil; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSURLCredential class]])
        return NO;
    NSURLCredential *o = other;
    return (_user == o->_user || [_user isEqualToString:o->_user]) &&
           (_password == o->_password || [_password isEqualToString:o->_password]) && _trust == o->_trust &&
           _identity == o->_identity;
}
- (NSUInteger)hash { return [_user hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSURLCredential: %p>: %@", self, _user ?: (_trust ? @"(server trust)" : @"")];
}
@end

/* ---- NSURLProtectionSpace ------------------------------------------------------------------- */

@interface NSURLProtectionSpace () {
    NSString *_host, *_protocol, *_realm, *_method, *_proxyType;
    NSInteger _port;
    FURLServerTrust *_trust;
}
@end

/* NSURLAuthenticationMethodDefault means Basic for HTTP. */
static NSString *plain_method(NSString *m)
{
    return !m || [m isEqualToString:NSURLAuthenticationMethodDefault] ? NSURLAuthenticationMethodHTTPBasic : m;
}

@implementation NSURLProtectionSpace
- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port protocol:(NSString *)protocol
                       realm:(NSString *)realm authenticationMethod:(NSString *)authenticationMethod
{
    _host = [host copy];
    _port = port;
    _protocol = [protocol copy];
    _realm = [realm copy];
    _method = [authenticationMethod ?: NSURLAuthenticationMethodDefault copy];
    return self;
}
- (instancetype)initWithProxyHost:(NSString *)host port:(NSInteger)port type:(NSString *)type
                            realm:(NSString *)realm authenticationMethod:(NSString *)authenticationMethod
{
    if ((self = [self initWithHost:host port:port protocol:type realm:realm authenticationMethod:authenticationMethod]))
        _proxyType = [type copy];
    return self;
}
- (void)dealloc
{
    [_host release];
    [_protocol release];
    [_realm release];
    [_method release];
    [_proxyType release];
    [_trust release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)host { return _host; }
- (NSInteger)port { return _port; }
- (NSString *)protocol { return _protocol; }
- (NSString *)realm { return _realm; }
- (NSString *)authenticationMethod { return _method; }
- (BOOL)isProxy { return _proxyType != nil; }
- (NSString *)proxyType { return _proxyType; }
- (BOOL)receivesCredentialSecurely
{
    NSString *m = plain_method(_method);
    return [[_protocol lowercaseString] isEqualToString:@"https"] ||
           !([m isEqualToString:NSURLAuthenticationMethodHTTPBasic] ||
             [m isEqualToString:NSURLAuthenticationMethodHTMLForm]);
}
- (SecTrustRef)serverTrust { return (SecTrustRef)_trust; }
- (NSArray *)distinguishedNames { return nil; }
- (void)_setServerTrust:(FURLServerTrust *)trust
{
    [trust retain];
    [_trust release];
    _trust = trust;
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSURLProtectionSpace class]])
        return NO;
    NSURLProtectionSpace *o = other;
    return [_host caseInsensitiveCompare:o->_host ?: @""] == NSOrderedSame && _port == o->_port &&
           [[_protocol lowercaseString] isEqualToString:[o->_protocol lowercaseString] ?: @""] &&
           (_realm == o->_realm || [_realm isEqualToString:o->_realm]) &&
           [plain_method(_method) isEqualToString:plain_method(o->_method)] &&
           (_proxyType == o->_proxyType || [_proxyType isEqualToString:o->_proxyType]);
}
- (NSUInteger)hash { return [[_host lowercaseString] hash] ^ (NSUInteger)_port; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSURLProtectionSpace: %p>: Host:%@, Server:%@, Auth-Scheme:%@, Realm:%@, "
                                      @"Port:%ld, Proxy:%s, Proxy-Type:%@",
                                      self, _host, _protocol, _method, _realm, (long)_port, _proxyType ? "YES" : "NO",
                                      _proxyType];
}
@end

/* ---- NSURLAuthenticationChallenge ----------------------------------------------------------- */

@interface NSURLAuthenticationChallenge () {
    NSURLProtectionSpace *_space;
    NSURLCredential *_proposed;
    NSInteger _failures;
    NSURLResponse *_response;
    NSError *_error;
    id _sender;
}
@end

@implementation NSURLAuthenticationChallenge
- (instancetype)initWithProtectionSpace:(NSURLProtectionSpace *)space
                     proposedCredential:(NSURLCredential *)credential
                   previousFailureCount:(NSInteger)previousFailureCount
                        failureResponse:(NSURLResponse *)response
                                  error:(NSError *)error
                                 sender:(id<NSURLAuthenticationChallengeSender>)sender
{
    _space = [space copy];
    _proposed = [credential copy];
    _failures = previousFailureCount;
    _response = [response copy];
    _error = [error copy];
    _sender = [(id)sender retain];
    return self;
}
- (instancetype)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
                                         sender:(id<NSURLAuthenticationChallengeSender>)sender
{
    return [self initWithProtectionSpace:c->_space
                      proposedCredential:c->_proposed
                    previousFailureCount:c->_failures
                         failureResponse:c->_response
                                   error:c->_error
                                  sender:sender];
}
- (void)dealloc
{
    [_space release];
    [_proposed release];
    [_response release];
    [_error release];
    [_sender release];
    [super dealloc];
}
- (NSURLProtectionSpace *)protectionSpace { return _space; }
- (NSURLCredential *)proposedCredential { return _proposed; }
- (NSInteger)previousFailureCount { return _failures; }
- (NSURLResponse *)failureResponse { return _response; }
- (NSError *)error { return _error; }
- (id<NSURLAuthenticationChallengeSender>)sender { return _sender; }
@end

/* ---- NSURLCredentialStorage ----------------------------------------------------------------- */

@interface NSURLCredentialStorage () {
    NSMutableDictionary *_all;      /* space -> user -> credential */
    NSMutableDictionary *_defaults; /* space -> credential */
}
@end

@implementation NSURLCredentialStorage
+ (NSURLCredentialStorage *)sharedCredentialStorage
{
    static NSURLCredentialStorage *shared;
    if (!shared)
        shared = [[self alloc] init];
    return shared;
}
+ (instancetype)_privateStorage { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    _all = [[NSMutableDictionary alloc] init];
    _defaults = [[NSMutableDictionary alloc] init];
    return self;
}
- (void)dealloc
{
    [_all release];
    [_defaults release];
    [super dealloc];
}
- (void)_changed
{
    [[NSNotificationCenter defaultCenter] postNotificationName:NSURLCredentialStorageChangedNotification object:self];
}
- (NSDictionary *)credentialsForProtectionSpace:(NSURLProtectionSpace *)space
{
    NSDictionary *d = space ? [_all objectForKey:space] : nil;
    return [d count] ? [[d copy] autorelease] : nil;
}
- (NSDictionary *)allCredentials
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id space in _all)
        if ([[_all objectForKey:space] count])
            [out setObject:[[[_all objectForKey:space] copy] autorelease] forKey:space];
    return out;
}
- (void)setCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
{
    /* A credential that keeps for no time at all isn't kept. */
    if (!credential || !space || [credential persistence] == NSURLCredentialPersistenceNone)
        return;
    NSMutableDictionary *d = [_all objectForKey:space];
    if (!d) {
        d = [NSMutableDictionary dictionary];
        [_all setObject:d forKey:space];
    }
    [d setObject:credential forKey:[credential user] ?: @""];
    [self _changed];
}
- (void)removeCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
{
    [self removeCredential:credential forProtectionSpace:space options:nil];
}
- (void)removeCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                 options:(NSDictionary *)options
{
    if (!credential || !space)
        return;
    NSMutableDictionary *d = [_all objectForKey:space];
    NSString *user = [credential user] ?: @"";
    if (![d objectForKey:user])
        return;
    [d removeObjectForKey:user];
    if ([[_defaults objectForKey:space] isEqual:credential])
        [_defaults removeObjectForKey:space];
    [self _changed];
}
- (NSURLCredential *)defaultCredentialForProtectionSpace:(NSURLProtectionSpace *)space
{
    return space ? [_defaults objectForKey:space] : nil;
}
- (void)setDefaultCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
{
    if (!credential || !space || [credential persistence] == NSURLCredentialPersistenceNone)
        return;
    [self setCredential:credential forProtectionSpace:space];
    [_defaults setObject:credential forKey:space];
}
- (NSURLCredential *)_credentialForSpace:(NSURLProtectionSpace *)space
{
    NSURLCredential *c = [self defaultCredentialForProtectionSpace:space];
    if (c)
        return c;
    NSDictionary *d = [_all objectForKey:space];
    return [d count] == 1 ? [[d allValues] lastObject] : nil;
}
- (void)getCredentialsForProtectionSpace:(NSURLProtectionSpace *)space task:(NSURLSessionTask *)task
                       completionHandler:(void (^)(NSDictionary<NSString *, NSURLCredential *> *))handler
{
    if (handler)
        handler([self credentialsForProtectionSpace:space]);
}
- (void)setCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                 task:(NSURLSessionTask *)task
{
    [self setCredential:credential forProtectionSpace:space];
}
- (void)removeCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                 options:(NSDictionary *)options task:(NSURLSessionTask *)task
{
    [self removeCredential:credential forProtectionSpace:space options:options];
}
- (void)getDefaultCredentialForProtectionSpace:(NSURLProtectionSpace *)space task:(NSURLSessionTask *)task
                             completionHandler:(void (^)(NSURLCredential *))handler
{
    if (handler)
        handler([self defaultCredentialForProtectionSpace:space]);
}
- (void)setDefaultCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                        task:(NSURLSessionTask *)task
{
    [self setDefaultCredential:credential forProtectionSpace:space];
}
@end
