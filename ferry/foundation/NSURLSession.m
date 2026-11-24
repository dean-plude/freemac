/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: URL loading. NSURLRequest and NSMutableURLRequest,
 * NSURLResponse and NSHTTPURLResponse, NSURLSession with its configuration
 * and its data, upload and download tasks, NSURLConnection, the
 * NSURLErrorDomain errors, and reading http, https and data URLs into NSData
 * and NSString. Written from Apple's public API documentation and RFCs
 * 9110, 9111, 7616, 7617 and 2397.
 *
 * Each request is seen through by an exchange (FURLExchange, below): it
 * follows redirects itself, asking the delegate about each; answers 401s
 * with HTTP Basic or Digest, asking the delegate or using the URL's or the
 * credential storage's credential; asks about an https server's certificate
 * before connecting; sends and keeps cookies (NSHTTPCookie.m); and answers
 * from, revalidates against and fills the URL cache (NSURLCache.m), as the
 * request's cache policy says.
 *
 * The transfers themselves are done by this system's libcurl (FCurl.h),
 * through its "multi" interface: every transfer of the program shares one
 * multi handle, driven by a network thread of Foundation's own. The thread
 * starts with the first transfer and ends when none is left; it waits on
 * the transfers' sockets and on a pipe that wakes it when a transfer is
 * added, paused, resumed or cancelled. Everything the engine keeps, every
 * exchange (redirects, challenges, cookies and the cache included), and
 * every task's, connection's and session's own state, is guarded by one
 * recursive lock (engine_lock), so tasks may be made, resumed, suspended
 * and cancelled, and a delegate's answers given, from any thread.
 *
 * Completion handlers and delegate messages are never called from inside
 * libcurl, nor with the lock held: each is queued, in order, on the
 * session's delegate queue. That is the queue the program gave (anything
 * that takes addOperationWithBlock:, as NSOperationQueue does) or else a
 * serial operation queue of the session's own, whose work runs on a worker
 * thread, as on a Mac; NSURLConnection's go to its delegate queue or else
 * the main queue. A delegate may answer a question (a redirect, a
 * challenge, a response, what to cache) later and from any thread; the
 * exchange goes on, under the lock, when it does. The synchronous calls
 * (sendSynchronousRequest:..., dataWithContentsOfURL:) block their thread
 * until the network thread has finished the exchange. */
#import "FURLInternal.h"
#include "FCurl.h"
#include <ctype.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

void *ferry_network_symbol(const char *name);                                 /* src/host.c */
int mkstemps(char *template, int suffixlen);

NSString *const NSURLErrorDomain = @"NSURLErrorDomain";
NSString *const NSURLErrorFailingURLErrorKey = @"NSErrorFailingURLKey";
NSString *const NSURLErrorFailingURLStringErrorKey = @"NSErrorFailingURLStringKey";
NSString *const NSErrorFailingURLStringKey = @"NSErrorFailingURLStringKey";
NSString *const NSURLSessionDownloadTaskResumeData = @"NSURLSessionDownloadTaskResumeData";
const int64_t NSURLSessionTransferSizeUnknown = -1;
const float NSURLSessionTaskPriorityDefault = 0.5f;
const float NSURLSessionTaskPriorityLow = 0.25f;
const float NSURLSessionTaskPriorityHigh = 0.75f;

static NSTimeInterval now(void) { return [NSDate timeIntervalSinceReferenceDate]; }

/* ---- errors ---------------------------------------------------------------------------- */

static NSString *url_error_text(NSInteger code)
{
    switch (code) {
    case NSURLErrorCancelled: return @"cancelled";
    case NSURLErrorBadURL: return @"bad URL";
    case NSURLErrorTimedOut: return @"The request timed out.";
    case NSURLErrorUnsupportedURL: return @"unsupported URL";
    case NSURLErrorCannotFindHost: return @"A server with the specified hostname could not be found.";
    case NSURLErrorCannotConnectToHost: return @"Could not connect to the server.";
    case NSURLErrorNetworkConnectionLost: return @"The network connection was lost.";
    case NSURLErrorHTTPTooManyRedirects: return @"too many HTTP redirects";
    case NSURLErrorNotConnectedToInternet: return @"The Internet connection appears to be offline.";
    case NSURLErrorBadServerResponse: return @"The server returned a bad response.";
    case NSURLErrorCannotDecodeContentData: return @"cannot decode content data";
    case NSURLErrorCannotParseResponse: return @"cannot parse response";
    case NSURLErrorFileDoesNotExist: return @"The requested URL was not found on this server.";
    case NSURLErrorDataLengthExceedsMaximum: return @"resource exceeds maximum size";
    case NSURLErrorSecureConnectionFailed:
        return @"An SSL error has occurred and a secure connection to the server cannot be made.";
    case NSURLErrorServerCertificateUntrusted: return @"The certificate for this server is invalid.";
    case NSURLErrorCannotWriteToFile: return @"cannot write to file";
    case NSURLErrorCannotCreateFile: return @"cannot create file";
    case NSURLErrorResourceUnavailable: return @"resource unavailable";
    case NSURLErrorUserCancelledAuthentication: return @"The operation couldn’t be completed. (NSURLErrorDomain error -1012.)";
    case NSURLErrorCannotDecodeRawData: return @"cannot decode raw data";
    default: return @"unknown error";
    }
}

static NSError *url_error(NSInteger code, NSURL *url, NSString *text)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject:text ?: url_error_text(code) forKey:NSLocalizedDescriptionKey];
    if (url) {
        [info setObject:url forKey:NSURLErrorFailingURLErrorKey];
        if ([url absoluteString])
            [info setObject:[url absoluteString] forKey:NSURLErrorFailingURLStringErrorKey];
    }
    return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:info];
}

static NSInteger code_for_curl(CURLcode c)
{
    switch (c) {
    case CURLE_UNSUPPORTED_PROTOCOL: return NSURLErrorUnsupportedURL;
    case CURLE_URL_MALFORMAT: return NSURLErrorBadURL;
    case CURLE_COULDNT_RESOLVE_PROXY:
    case CURLE_COULDNT_RESOLVE_HOST: return NSURLErrorCannotFindHost;
    case CURLE_COULDNT_CONNECT: return NSURLErrorCannotConnectToHost;
    case CURLE_OPERATION_TIMEDOUT: return NSURLErrorTimedOut;
    case CURLE_TOO_MANY_REDIRECTS: return NSURLErrorHTTPTooManyRedirects;
    case CURLE_GOT_NOTHING:
    case CURLE_SEND_ERROR:
    case CURLE_RECV_ERROR:
    case CURLE_PARTIAL_FILE: return NSURLErrorNetworkConnectionLost;
    case CURLE_WEIRD_SERVER_REPLY: return NSURLErrorBadServerResponse;
    case CURLE_SSL_CONNECT_ERROR:
    case CURLE_SSL_CERTPROBLEM:
    case CURLE_SSL_CACERT_BADFILE: return NSURLErrorSecureConnectionFailed;
    case CURLE_PEER_FAILED_VERIFICATION: return NSURLErrorServerCertificateUntrusted;
    case CURLE_BAD_CONTENT_ENCODING: return NSURLErrorCannotDecodeContentData;
    case CURLE_FILE_COULDNT_READ_FILE: return NSURLErrorFileDoesNotExist;
    case CURLE_FILESIZE_EXCEEDED: return NSURLErrorDataLengthExceedsMaximum;
    case CURLE_WRITE_ERROR: return NSURLErrorCannotWriteToFile;
    case CURLE_ABORTED_BY_CALLBACK: return NSURLErrorCancelled;
    default: return NSURLErrorUnknown;
    }
}

/* ---- header fields: looked up without regard to case ------------------------------------ */

static NSString *field_key(NSDictionary *fields, NSString *field)
{
    if (!field)
        return nil;
    if ([fields objectForKey:field])
        return field;
    for (NSString *k in fields)
        if ([k caseInsensitiveCompare:field] == NSOrderedSame)
            return k;
    return nil;
}

static NSString *trimmed(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

/* ---- NSURLRequest ------------------------------------------------------------------------ */

@interface NSURLRequest () {
@package
    NSURL *_url, *_mainDocumentURL;
    NSURLRequestCachePolicy _cachePolicy;
    NSTimeInterval _timeout;
    NSURLRequestNetworkServiceType _serviceType;
    BOOL _cellular, _cookies, _pipelining;
    NSString *_method;
    NSMutableDictionary *_fields;
    NSData *_body;
}
@end

@implementation NSURLRequest
+ (instancetype)requestWithURL:(NSURL *)URL { return [[[self alloc] initWithURL:URL] autorelease]; }
+ (instancetype)requestWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)policy
               timeoutInterval:(NSTimeInterval)timeout
{
    return [[[self alloc] initWithURL:URL cachePolicy:policy timeoutInterval:timeout] autorelease];
}
- (instancetype)init { return [self initWithURL:nil]; }
- (instancetype)initWithURL:(NSURL *)URL
{
    return [self initWithURL:URL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60];
}
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)policy
            timeoutInterval:(NSTimeInterval)timeout
{
    _url = [URL copy];
    _cachePolicy = policy;
    _timeout = timeout;
    _cellular = _cookies = YES;
    _method = @"GET";
    _fields = [[NSMutableDictionary alloc] init];
    return self;
}
- (void)dealloc
{
    [_url release];
    [_mainDocumentURL release];
    [_method release];
    [_fields release];
    [_body release];
    [super dealloc];
}
- (id)_copyAs:(Class)cls
{
    NSURLRequest *r = [[cls alloc] initWithURL:_url cachePolicy:_cachePolicy timeoutInterval:_timeout];
    r->_mainDocumentURL = [_mainDocumentURL copy];
    r->_serviceType = _serviceType;
    r->_cellular = _cellular;
    r->_cookies = _cookies;
    r->_pipelining = _pipelining;
    [r->_method release];
    r->_method = [_method copy];
    [r->_fields setDictionary:_fields];
    r->_body = [_body copy];
    return r;
}
- (id)copyWithZone:(NSZone *)zone
{
    return [self class] == [NSURLRequest class] ? [self retain] : [self _copyAs:[NSURLRequest class]];
}
- (id)mutableCopyWithZone:(NSZone *)zone { return [self _copyAs:[NSMutableURLRequest class]]; }
- (NSURL *)URL { return _url; }
- (NSURLRequestCachePolicy)cachePolicy { return _cachePolicy; }
- (NSTimeInterval)timeoutInterval { return _timeout; }
- (NSURL *)mainDocumentURL { return _mainDocumentURL; }
- (NSURLRequestNetworkServiceType)networkServiceType { return _serviceType; }
- (BOOL)allowsCellularAccess { return _cellular; }
- (NSString *)HTTPMethod { return _method; }
- (NSDictionary *)allHTTPHeaderFields { return [_fields count] ? [[_fields copy] autorelease] : nil; }
- (NSString *)valueForHTTPHeaderField:(NSString *)field
{
    NSString *k = field_key(_fields, field);
    return k ? [_fields objectForKey:k] : nil;
}
- (NSData *)HTTPBody { return _body; }
- (BOOL)HTTPShouldHandleCookies { return _cookies; }
- (BOOL)HTTPShouldUsePipelining { return _pipelining; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSURLRequest class]])
        return NO;
    NSURLRequest *o = other;
    return (_url == o->_url || [_url isEqual:o->_url]) && [_method isEqualToString:o->_method] &&
           [_fields isEqual:o->_fields] && (_body == o->_body || [_body isEqual:o->_body]);
}
- (NSUInteger)hash { return [[_url absoluteString] hash] ^ [_method hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> { URL: %@ }", [self class], self, [_url absoluteString]];
}
@end

@implementation NSMutableURLRequest
- (void)setURL:(NSURL *)URL
{
    URL = [URL copy];
    [_url release];
    _url = URL;
}
- (void)setCachePolicy:(NSURLRequestCachePolicy)p { _cachePolicy = p; }
- (void)setTimeoutInterval:(NSTimeInterval)t { _timeout = t; }
- (void)setMainDocumentURL:(NSURL *)URL
{
    URL = [URL copy];
    [_mainDocumentURL release];
    _mainDocumentURL = URL;
}
- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)t { _serviceType = t; }
- (void)setAllowsCellularAccess:(BOOL)b { _cellular = b; }
- (void)setHTTPMethod:(NSString *)method
{
    method = [method length] ? [method copy] : @"GET";
    [_method release];
    _method = method;
}
- (void)setAllHTTPHeaderFields:(NSDictionary *)fields
{
    [_fields removeAllObjects];
    for (NSString *k in fields) {
        id v = [fields objectForKey:k];
        if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]])
            [self setValue:v forHTTPHeaderField:k];
    }
}
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field
{
    if (!field)
        return;
    NSString *k = field_key(_fields, field);
    if (k)
        [_fields removeObjectForKey:k];
    if (value)
        [_fields setObject:value forKey:k ?: field];
}
- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field
{
    if (!field || !value)
        return;
    NSString *k = field_key(_fields, field);
    NSString *old = k ? [_fields objectForKey:k] : nil;
    [_fields setObject:old ? [NSString stringWithFormat:@"%@,%@", old, value] : value forKey:k ?: field];
}
- (void)setHTTPBody:(NSData *)body
{
    body = [body copy];
    [_body release];
    _body = body;
}
- (void)setHTTPShouldHandleCookies:(BOOL)b { _cookies = b; }
- (void)setHTTPShouldUsePipelining:(BOOL)b { _pipelining = b; }
@end

/* ---- NSURLResponse and NSHTTPURLResponse ---------------------------------------------------- */

@interface NSURLResponse () {
@package
    NSURL *_url;
    NSString *_mime, *_encoding;
    long long _expected;
}
@end

@implementation NSURLResponse
- (instancetype)initWithURL:(NSURL *)URL MIMEType:(NSString *)MIMEType expectedContentLength:(NSInteger)length
           textEncodingName:(NSString *)name
{
    _url = [URL copy];
    _mime = [MIMEType copy];
    _expected = length;
    _encoding = [name copy];
    return self;
}
- (void)dealloc
{
    [_url release];
    [_mime release];
    [_encoding release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSURL *)URL { return _url; }
- (NSString *)MIMEType { return _mime; }
- (long long)expectedContentLength { return _expected; }
- (NSString *)textEncodingName { return _encoding; }
- (NSString *)_dispositionFilename { return nil; }
- (NSString *)suggestedFilename
{
    NSString *name = [self _dispositionFilename];
    if (![name length]) {
        name = [[_url path] lastPathComponent];
        if ([name isEqualToString:@"/"])
            name = nil;
    }
    return [name length] ? name : @"Unknown";
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> { URL: %@ }", [self class], self, [_url absoluteString]];
}
@end

@interface NSHTTPURLResponse () {
    NSInteger _status;
    NSDictionary *_fields;
    NSString *_version;
}
@end

@implementation NSHTTPURLResponse
- (instancetype)initWithURL:(NSURL *)url statusCode:(NSInteger)statusCode HTTPVersion:(NSString *)HTTPVersion
               headerFields:(NSDictionary *)headerFields
{
    NSString *type = nil, *charset = nil;
    long long length = NSURLResponseUnknownLength;
    NSString *k = field_key(headerFields, @"Content-Type");
    if (k) {
        NSArray *parts = [[headerFields objectForKey:k] componentsSeparatedByString:@";"];
        type = [trimmed([parts objectAtIndex:0]) lowercaseString];
        for (NSUInteger i = 1; i < [parts count]; i++) {
            NSString *p = trimmed([parts objectAtIndex:i]);
            if ([[p lowercaseString] hasPrefix:@"charset="]) {
                charset = [p substringFromIndex:8];
                if ([charset hasPrefix:@"\""] && [charset hasSuffix:@"\""] && [charset length] >= 2)
                    charset = [charset substringWithRange:NSMakeRange(1, [charset length] - 2)];
            }
        }
        if (![type length])
            type = nil;
    }
    k = field_key(headerFields, @"Content-Length");
    if (k) {
        const char *s = [[headerFields objectForKey:k] UTF8String];
        char *end;
        long long n = strtoll(s, &end, 10);
        if (end != s && n >= 0)
            length = n;
    }
    if ((self = [super initWithURL:url MIMEType:type expectedContentLength:(NSInteger)length
                  textEncodingName:charset])) {
        _status = statusCode;
        _fields = [headerFields copy] ?: [[NSDictionary alloc] init];
        _version = [HTTPVersion copy];
    }
    return self;
}
- (void)dealloc
{
    [_fields release];
    [_version release];
    [super dealloc];
}
- (NSInteger)statusCode { return _status; }
- (NSDictionary *)allHeaderFields { return _fields; }
- (NSString *)valueForHTTPHeaderField:(NSString *)field
{
    NSString *k = field_key(_fields, field);
    return k ? [_fields objectForKey:k] : nil;
}
- (NSString *)_dispositionFilename
{
    NSString *d = [self valueForHTTPHeaderField:@"Content-Disposition"];
    for (NSString *part in [d componentsSeparatedByString:@";"]) {
        NSString *p = trimmed(part);
        if ([[p lowercaseString] hasPrefix:@"filename="]) {
            NSString *name = [p substringFromIndex:9];
            if ([name hasPrefix:@"\""] && [name hasSuffix:@"\""] && [name length] >= 2)
                name = [name substringWithRange:NSMakeRange(1, [name length] - 2)];
            return [name lastPathComponent];
        }
    }
    return nil;
}
+ (NSString *)localizedStringForStatusCode:(NSInteger)code
{
    switch (code) {
    case 100: return @"continue";
    case 101: return @"switching protocols";
    case 200: return @"no error";
    case 201: return @"created";
    case 202: return @"accepted";
    case 203: return @"non-authoritative information";
    case 204: return @"no content";
    case 205: return @"reset content";
    case 206: return @"partial content";
    case 300: return @"multiple choices";
    case 301: return @"moved permanently";
    case 302: return @"found";
    case 303: return @"see other";
    case 304: return @"not modified";
    case 305: return @"needs proxy";
    case 307: return @"temporarily redirected";
    case 308: return @"permanent redirect";
    case 400: return @"bad request";
    case 401: return @"unauthorized";
    case 402: return @"payment required";
    case 403: return @"forbidden";
    case 404: return @"not found";
    case 405: return @"method not allowed";
    case 406: return @"unacceptable";
    case 407: return @"proxy authentication required";
    case 408: return @"request timed out";
    case 409: return @"conflict";
    case 410: return @"no longer exists";
    case 411: return @"length required";
    case 412: return @"precondition failed";
    case 413: return @"request too large";
    case 414: return @"requested URL too long";
    case 415: return @"unsupported media type";
    case 416: return @"requested range not satisfiable";
    case 417: return @"expectation failed";
    case 429: return @"too many requests";
    case 500: return @"internal server error";
    case 501: return @"unimplemented";
    case 502: return @"bad gateway";
    case 503: return @"service unavailable";
    case 504: return @"gateway timed out";
    case 505: return @"unsupported version";
    }
    switch (code / 100) {
    case 1: return @"informational";
    case 2: return @"success";
    case 3: return @"redirected";
    case 4: return @"client error";
    case 5: return @"server error";
    }
    return @"server error";
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> { URL: %@ } { Status Code: %ld, Headers %@ }", [self class], self,
                                      [_url absoluteString], (long)_status, _fields];
}
@end

/* ---- the transfers, done by libcurl -------------------------------------------------------- */

@class FURLLoad;

/* What a transfer tells whoever started it, always from the program's
 * thread and never with a libcurl call on the stack that it may not
 * repeat: the response once its header fields are in, the body as it
 * comes, the upload's progress, and the end (nil when it went well). */
@protocol FURLLoadClient <NSObject>
- (void)_load:(id)load receivedResponse:(NSURLResponse *)response;
- (void)_load:(id)load receivedBytes:(const void *)bytes length:(size_t)length;
- (void)_load:(id)load sent:(int64_t)sent of:(int64_t)total;
- (void)_load:(id)load finishedWithError:(NSError *)error;
@end

@interface FURLLoad : NSObject {
@public
    CURL *easy;
    struct curl_slist *fields;
    NSURL *url;
    NSData *body;
    id<FURLLoadClient> client;
    NSTimeInterval idle, active_at;
    BOOL file, got_response, done, paused, cancelled;
    NSInteger status;
    NSString *version;
    NSMutableArray *names, *values;
    int64_t received, sent;
    char message[256];
}
@end

@implementation FURLLoad
- (void)dealloc
{
    [url release];
    [body release];
    [version release];
    [names release];
    [values release];
    [super dealloc];
}
@end

static struct ferry_curl C;
static int curl_state; /* 0 not tried, 1 ready, -1 not installed */
static CURLM *multi;
static NSMutableArray *loads; /* the transfers going on */
static struct nsock {
    int fd, what;
} *socks;
static int nsocks, capsocks;
static NSTimeInterval curl_deadline = -1; /* when libcurl wants its timeout action */
static unsigned long events;              /* client messages sent */

/* The engine's lock, recursive because a client's message may cancel or
 * pause its own transfer, and an exchange's answer may start the next;
 * engine_done is broadcast whenever a transfer or a waited-for exchange
 * ends, for the calls that wait for one. */
static pthread_mutex_t engine_lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;
static pthread_cond_t engine_done = PTHREAD_COND_INITIALIZER;
static BOOL net_running;            /* the network thread is up */
static int wake_pipe[2] = {-1, -1}; /* wakes it from its poll */
static volatile int nloads;         /* transfers going on, read without the lock by the main run loop */
#define LOCK_ENGINE() pthread_mutex_lock(&engine_lock)
#define UNLOCK_ENGINE() pthread_mutex_unlock(&engine_lock)

static int on_socket(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp)
{
    int i;
    for (i = 0; i < nsocks && socks[i].fd != s; i++)
        ;
    if (what == CURL_POLL_REMOVE) {
        if (i < nsocks)
            socks[i] = socks[--nsocks];
        return 0;
    }
    if (i == nsocks) {
        if (nsocks == capsocks) {
            capsocks = capsocks ? capsocks * 2 : 8;
            socks = realloc(socks, capsocks * sizeof *socks);
        }
        socks[nsocks++].fd = s;
    }
    socks[i].what = what;
    return 0;
}

static int on_timer(CURLM *m, long timeout_ms, void *userp)
{
    curl_deadline = timeout_ms < 0 ? -1 : now() + timeout_ms / 1000.0;
    return 0;
}

static int engine_prepare(void *ctx, int *timeout_ms, struct pollfd *fds, int max);
static BOOL engine_dispatch(void *ctx, struct pollfd *fds, int count);

/* For the main run loop: while a transfer goes on, its messages may still
 * come, so the loop doesn't end for want of work. It waits on nothing of
 * the engine's: the network thread does that. */
static int idle_prepare(void *ctx, int *timeout_ms, struct pollfd *fds, int max) { return 0; }
static BOOL idle_dispatch(void *ctx, struct pollfd *fds, int count) { return NO; }
static BOOL engine_active(void *ctx) { return __atomic_load_n(&nloads, __ATOMIC_ACQUIRE) > 0; }

/* The network thread: waits on the transfers' sockets and its wake pipe
 * without the lock, then lets libcurl do what is ready with it, until no
 * transfer is left. */
static void *net_main(void *arg)
{
    pthread_setname_np("com.apple.NSURLConnectionLoader");
    LOCK_ENGINE();
    while ([loads count]) {
        @autoreleasepool {
            struct pollfd fds[65];
            int ms = -1;
            int n = engine_prepare(NULL, &ms, fds, 64);
            fds[n].fd = wake_pipe[0];
            fds[n].events = POLLIN;
            fds[n].revents = 0;
            UNLOCK_ENGINE();
            poll(fds, n + 1, ms);
            if (fds[n].revents) {
                char buf[64];
                while (read(wake_pipe[0], buf, sizeof buf) > 0)
                    ;
            }
            LOCK_ENGINE();
            engine_dispatch(NULL, fds, n);
        }
    }
    net_running = NO;
    UNLOCK_ENGINE();
    return NULL;
}

/* Called with the lock held after the transfers changed: starts the
 * network thread, or wakes it to look again. */
static void engine_kick(void)
{
    __atomic_store_n(&nloads, (int)[loads count], __ATOMIC_RELEASE);
    if (!net_running && [loads count]) {
        pthread_t t;
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&t, &a, net_main, NULL) == 0)
            net_running = YES;
        pthread_attr_destroy(&a);
    } else if (net_running) {
        char c = 1;
        (void)!write(wake_pipe[1], &c, 1);
    }
}

/* Called with the lock held. */
static BOOL load_curl(void)
{
    if (curl_state)
        return curl_state > 0;
    curl_state = -1;
#define CALL(field, name) if (!(*(void **)&C.field = ferry_network_symbol(name))) goto missing
    CALL(global_init, "curl_global_init");
    CALL(easy_init, "curl_easy_init");
    CALL(easy_setopt, "curl_easy_setopt");
    CALL(easy_getinfo, "curl_easy_getinfo");
    CALL(easy_pause, "curl_easy_pause");
    CALL(easy_cleanup, "curl_easy_cleanup");
    CALL(easy_strerror, "curl_easy_strerror");
    CALL(slist_append, "curl_slist_append");
    CALL(slist_free_all, "curl_slist_free_all");
    CALL(multi_init, "curl_multi_init");
    CALL(multi_setopt, "curl_multi_setopt");
    CALL(multi_add_handle, "curl_multi_add_handle");
    CALL(multi_remove_handle, "curl_multi_remove_handle");
    CALL(multi_socket_action, "curl_multi_socket_action");
    CALL(multi_info_read, "curl_multi_info_read");
#undef CALL
    if (C.global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK || !(multi = C.multi_init()))
        goto missing;
    C.multi_setopt(multi, CURLMOPT_SOCKETFUNCTION, on_socket);
    C.multi_setopt(multi, CURLMOPT_TIMERFUNCTION, on_timer);
    if (pipe(wake_pipe) < 0)
        goto missing;
    fcntl(wake_pipe[0], F_SETFL, O_NONBLOCK);
    fcntl(wake_pipe[1], F_SETFL, O_NONBLOCK);
    fcntl(wake_pipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(wake_pipe[1], F_SETFD, FD_CLOEXEC);
    loads = [[NSMutableArray alloc] init];
    FRunLoopAddPoller(idle_prepare, idle_dispatch, engine_active, NULL);
    curl_state = 1;
    return YES;
missing:
    fprintf(stderr, "ferry: loading URLs from the network needs libcurl (libcurl4), which isn't installed\n");
    return NO;
}

/* The program's name and version, for the User-Agent field, as a Mac
 * names the app (Ferry's CFNetwork stand-in is named as Ferry). */
static NSString *user_agent(void)
{
    static NSString *agent;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSBundle *b = [NSBundle mainBundle];
      NSString *name = [b objectForInfoDictionaryKey:@"CFBundleName"] ?: [[NSProcessInfo processInfo] processName];
      NSString *version = [b objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";
      agent = [[NSString alloc] initWithFormat:@"%@/%@ Ferry (freemac)", name ?: @"Ferry", version];
    });
    return agent;
}

static NSString *latin1(const char *p, size_t n)
{
    return [[[NSString alloc] initWithBytes:p length:n encoding:NSISOLatin1StringEncoding] autorelease];
}

/* A file's MIME type, from its extension, for file URLs. */
static NSString *mime_for_path(NSString *path)
{
    static const char *const table[][2] = {
        {"txt", "text/plain"},       {"html", "text/html"},       {"htm", "text/html"},
        {"css", "text/css"},         {"js", "text/javascript"},   {"json", "application/json"},
        {"xml", "application/xml"},  {"plist", "application/x-plist"}, {"png", "image/png"},
        {"jpg", "image/jpeg"},       {"jpeg", "image/jpeg"},      {"gif", "image/gif"},
        {"pdf", "application/pdf"},  {"zip", "application/zip"},  {"rtf", "text/rtf"},
        {"svg", "image/svg+xml"},    {"tiff", "image/tiff"},      {"md", "text/markdown"},
    };
    NSString *ext = [[path pathExtension] lowercaseString];
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++)
        if ([ext isEqualToString:[NSString stringWithUTF8String:table[i][0]]])
            return [NSString stringWithUTF8String:table[i][1]];
    return @"application/octet-stream";
}

static NSURLResponse *make_response(FURLLoad *l)
{
    char *effective = NULL;
    NSURL *u = l->url;
    if (C.easy_getinfo(l->easy, CURLINFO_EFFECTIVE_URL, &effective) == CURLE_OK && effective) {
        NSURL *e = [NSURL URLWithString:[NSString stringWithUTF8String:effective]];
        if (e)
            u = e;
    }
    if (l->file) {
        curl_off_t length = -1;
        C.easy_getinfo(l->easy, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &length);
        return [[[NSURLResponse alloc] initWithURL:u MIMEType:mime_for_path([u path])
                             expectedContentLength:(NSInteger)length
                                  textEncodingName:nil] autorelease];
    }
    long code = l->status;
    if (C.easy_getinfo(l->easy, CURLINFO_RESPONSE_CODE, &code) != CURLE_OK || !code)
        code = l->status;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < [l->names count]; i++) {
        NSString *name = [l->names objectAtIndex:i], *value = [l->values objectAtIndex:i];
        NSString *k = field_key(fields, name);
        if (k)
            [fields setObject:[NSString stringWithFormat:@"%@, %@", [fields objectForKey:k], value] forKey:k];
        else
            [fields setObject:value forKey:name];
    }
    return [[[NSHTTPURLResponse alloc] initWithURL:u statusCode:code HTTPVersion:l->version ?: @"HTTP/1.1"
                                      headerFields:fields] autorelease];
}

static void deliver_response(FURLLoad *l)
{
    if (l->got_response)
        return;
    l->got_response = YES;
    events++;
    [l->client _load:l receivedResponse:make_response(l)];
}

static size_t on_header(char *p, size_t size, size_t n, void *userdata)
{
    FURLLoad *l = userdata;
    size_t len = size * n, end = len;
    l->active_at = now();
    while (end > 0 && (p[end - 1] == '\r' || p[end - 1] == '\n'))
        end--;
    if (end >= 5 && !memcmp(p, "HTTP/", 5)) {
        /* a new response: the first, or the next after a redirect or a 100 Continue */
        [l->names removeAllObjects];
        [l->values removeAllObjects];
        size_t sp = 0;
        while (sp < end && p[sp] != ' ')
            sp++;
        [l->version release];
        l->version = [latin1(p, sp) retain];
        l->status = sp < end ? strtol(p + sp + 1, NULL, 10) : 0;
    } else if (end && (p[0] == ' ' || p[0] == '\t') && [l->values count]) {
        NSString *more = trimmed(latin1(p, end));
        NSUInteger last = [l->values count] - 1;
        [l->values replaceObjectAtIndex:last
                             withObject:[NSString stringWithFormat:@"%@ %@", [l->values objectAtIndex:last], more]];
    } else if (end) {
        const char *colon = memchr(p, ':', end);
        if (colon && colon > p) {
            [l->names addObject:trimmed(latin1(p, colon - p))];
            [l->values addObject:trimmed(latin1(colon + 1, p + end - colon - 1))];
        }
    }
    return len;
}

static size_t on_body(char *p, size_t size, size_t n, void *userdata)
{
    FURLLoad *l = userdata;
    size_t len = size * n;
    l->active_at = now();
    deliver_response(l);
    if (l->cancelled)
        return 0;
    l->received += len;
    events++;
    [l->client _load:l receivedBytes:p length:len];
    return l->cancelled ? 0 : len;
}

static int on_progress(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow)
{
    FURLLoad *l = clientp;
    if (ulnow > l->sent) { /* libcurl counts from 0 again at times */
        l->active_at = now();
        l->sent = ulnow;
        events++;
        [l->client _load:l sent:ulnow of:ultotal ? ultotal : (int64_t)[l->body length]];
    }
    return l->cancelled;
}

/* Takes a transfer out of libcurl, with no more messages to its client. */
static void unload(FURLLoad *l)
{
    if (l->easy) {
        C.multi_remove_handle(multi, l->easy);
        C.easy_cleanup(l->easy);
        l->easy = NULL;
    }
    if (l->fields) {
        C.slist_free_all(l->fields);
        l->fields = NULL;
    }
    l->done = YES;
    [l->client release];
    l->client = nil;
    [loads removeObjectIdenticalTo:l];
    __atomic_store_n(&nloads, (int)[loads count], __ATOMIC_RELEASE);
    pthread_cond_broadcast(&engine_done);
}

static void finish(FURLLoad *l, NSError *error)
{
    if (l->done)
        return;
    [l retain];
    id<FURLLoadClient> client = [(id)l->client retain];
    if (!error)
        deliver_response(l);
    unload(l);
    events++;
    [client _load:l finishedWithError:error];
    [(id)client release];
    [l release];
}

/* A URL as libcurl is given it: without the user name and password,
 * which are answers to challenges (see the exchanges below), never sent
 * unasked, and without the fragment. */
static NSString *wire_url(NSURL *url)
{
    NSString *s = [[url absoluteURL] absoluteString];
    NSRange hash = [s rangeOfString:@"#"];
    if (hash.location != NSNotFound)
        s = [s substringToIndex:hash.location];
    NSRange r = [s rangeOfString:@"://"];
    if (r.location == NSNotFound || ![url user])
        return s;
    NSUInteger start = NSMaxRange(r);
    NSRange end = [[s substringFromIndex:start]
        rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?"]];
    NSUInteger stop = end.location == NSNotFound ? [s length] : start + end.location;
    NSRange at = [s rangeOfString:@"@" options:NSBackwardsSearch range:NSMakeRange(start, stop - start)];
    if (at.location == NSNotFound)
        return s;
    return [[s substringToIndex:start] stringByAppendingString:[s substringFromIndex:at.location + 1]];
}

/* Starts a transfer for a request. Returns nil, with *error set, when the
 * request can't be sent at all (an unsupported or bad URL, or no libcurl);
 * the caller tells its program later, as a Mac does. extra holds the
 * session's own header fields, and added the fields the exchange adds
 * (cookies, credentials, revalidation) unless the request has its own;
 * idle is how long the transfer may wait for data before it times out,
 * total how long it may take in all (0: no limit). body, when not nil,
 * replaces the request's body. insecure leaves the server's certificate
 * unchecked (the delegate accepted it). Redirects aren't followed here:
 * each is a response of its own, for the exchange to decide about. Called
 * with the engine's lock held. */
static FURLLoad *start_load(NSURLRequest *request, NSDictionary *extra, NSDictionary *added, NSTimeInterval idle,
                            NSTimeInterval total, NSData *body, BOOL insecure, id<FURLLoadClient> client,
                            NSError **error)
{
    NSURL *url = [request URL];
    NSString *scheme = [[url scheme] lowercaseString];
    BOOL web = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
    if (!url || !(web || [scheme isEqualToString:@"file"])) {
        *error = url_error(NSURLErrorUnsupportedURL, url, nil);
        return nil;
    }
    if (web && ![[url host] length]) {
        *error = url_error(NSURLErrorBadURL, url, nil);
        return nil;
    }
    if (!load_curl()) {
        *error = url_error(NSURLErrorNotConnectedToInternet, url,
                           @"Ferry needs this system's libcurl to load URLs, and it isn't installed.");
        return nil;
    }
    FURLLoad *l = [[[FURLLoad alloc] init] autorelease];
    l->easy = C.easy_init();
    if (!l->easy) {
        *error = url_error(NSURLErrorUnknown, url, nil);
        return nil;
    }
    l->url = [url retain];
    l->file = !web;
    l->idle = idle > 0 ? idle : 60;
    l->active_at = now();
    l->names = [[NSMutableArray alloc] init];
    l->values = [[NSMutableArray alloc] init];
    l->client = [(id)client retain];
    CURL *e = l->easy;
    C.easy_setopt(e, CURLOPT_URL, [wire_url(url) UTF8String]);
    C.easy_setopt(e, CURLOPT_PROTOCOLS_STR, "http,https,file");
    C.easy_setopt(e, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    C.easy_setopt(e, CURLOPT_NOSIGNAL, 1L);
    C.easy_setopt(e, CURLOPT_PRIVATE, l);
    C.easy_setopt(e, CURLOPT_ERRORBUFFER, l->message);
    C.easy_setopt(e, CURLOPT_WRITEFUNCTION, on_body);
    C.easy_setopt(e, CURLOPT_WRITEDATA, l);
    C.easy_setopt(e, CURLOPT_HEADERFUNCTION, on_header);
    C.easy_setopt(e, CURLOPT_HEADERDATA, l);
    C.easy_setopt(e, CURLOPT_NOPROGRESS, 0L);
    C.easy_setopt(e, CURLOPT_XFERINFOFUNCTION, on_progress);
    C.easy_setopt(e, CURLOPT_XFERINFODATA, l);
    C.easy_setopt(e, CURLOPT_FOLLOWLOCATION, 0L);
    if (insecure) {
        C.easy_setopt(e, CURLOPT_SSL_VERIFYPEER, 0L);
        C.easy_setopt(e, CURLOPT_SSL_VERIFYHOST, 0L);
    }
    C.easy_setopt(e, CURLOPT_ACCEPT_ENCODING, ""); /* every encoding libcurl can decode, decoded */
    C.easy_setopt(e, CURLOPT_CONNECTTIMEOUT_MS, (long)(l->idle * 1000));
    if (total > 0 && total < 1e7)
        C.easy_setopt(e, CURLOPT_TIMEOUT_MS, (long)(total * 1000));

    NSString *method = [[request HTTPMethod] uppercaseString] ?: @"GET";
    NSData *payload = body ?: [request HTTPBody];
    if (web) {
        if ([method isEqualToString:@"HEAD"])
            C.easy_setopt(e, CURLOPT_NOBODY, 1L);
        else if ([method isEqualToString:@"GET"])
            C.easy_setopt(e, CURLOPT_HTTPGET, 1L);
        else {
            if (payload || [method isEqualToString:@"POST"]) {
                l->body = [payload ?: [NSData data] retain];
                C.easy_setopt(e, CURLOPT_POSTFIELDS, [l->body length] ? [l->body bytes] : "");
                C.easy_setopt(e, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)[l->body length]);
            }
            if (![method isEqualToString:@"POST"])
                C.easy_setopt(e, CURLOPT_CUSTOMREQUEST, [[request HTTPMethod] UTF8String]);
        }
        /* the session's fields, then the request's, then the defaults */
        NSMutableDictionary *all = [NSMutableDictionary dictionary];
        NSDictionary *sources[2] = {extra, [request allHTTPHeaderFields]};
        for (int s = 0; s < 2; s++)
            for (id k in sources[s]) {
                id v = [sources[s] objectForKey:k];
                if (![k isKindOfClass:[NSString class]])
                    continue;
                if (![v isKindOfClass:[NSString class]])
                    v = [v description];
                NSString *old = field_key(all, k);
                if (old)
                    [all removeObjectForKey:old];
                [all setObject:v forKey:k];
            }
        for (NSString *k in added)
            if (!field_key(all, k))
                [all setObject:[added objectForKey:k] forKey:k];
        if (!field_key(all, @"User-Agent"))
            [all setObject:user_agent() forKey:@"User-Agent"];
        if (!field_key(all, @"Accept"))
            [all setObject:@"*/*" forKey:@"Accept"];
        NSArray *keys = [[all allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        for (NSString *k in keys) {
            NSString *v = [all objectForKey:k];
            if ([k rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n:"]].location !=
                    NSNotFound ||
                [v rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]].location !=
                    NSNotFound)
                continue;
            NSString *line = [v length] ? [NSString stringWithFormat:@"%@: %@", k, v]
                                        : [NSString stringWithFormat:@"%@;", k];
            l->fields = C.slist_append(l->fields, [line UTF8String]);
        }
        l->fields = C.slist_append(l->fields, "Expect:"); /* no 100 Continue round trip */
        C.easy_setopt(e, CURLOPT_HTTPHEADER, l->fields);
    }
    [loads addObject:l];
    C.multi_add_handle(multi, e);
    engine_kick();
    return l;
}

static void cancel_load(FURLLoad *l)
{
    LOCK_ENGINE();
    if (l && !l->done) {
        l->cancelled = YES;
        [[l retain] autorelease];
        unload(l);
        engine_kick();
    }
    UNLOCK_ENGINE();
}

static void pause_load(FURLLoad *l, BOOL pause)
{
    LOCK_ENGINE();
    if (l && !l->done && l->paused != pause) {
        l->paused = pause;
        l->active_at = now();
        C.easy_pause(l->easy, pause ? CURLPAUSE_ALL : CURLPAUSE_CONT);
        engine_kick();
    }
    UNLOCK_ENGINE();
}

static int engine_prepare(void *ctx, int *timeout_ms, struct pollfd *fds, int max)
{
    int n = 0;
    for (int i = 0; i < nsocks && n < max; i++) {
        fds[n].fd = socks[i].fd;
        fds[n].events = (socks[i].what & CURL_POLL_IN ? POLLIN : 0) | (socks[i].what & CURL_POLL_OUT ? POLLOUT : 0);
        fds[n].revents = 0;
        n++;
    }
    NSTimeInterval t = now(), next = t + 1; /* look again at least every second */
    if (curl_deadline >= 0 && curl_deadline < next)
        next = curl_deadline;
    for (FURLLoad *l in loads)
        if (!l->paused && l->active_at + l->idle < next)
            next = l->active_at + l->idle;
    int ms = next <= t ? 0 : (int)ceil((next - t) * 1000);
    if (*timeout_ms < 0 || ms < *timeout_ms)
        *timeout_ms = ms;
    return n;
}

static BOOL engine_dispatch(void *ctx, struct pollfd *fds, int count)
{
    unsigned long before = events;
    @autoreleasepool {
        int running = 0;
        for (int i = 0; i < count; i++) {
            if (!fds[i].revents)
                continue;
            int mask = (fds[i].revents & (POLLIN | POLLHUP) ? CURL_CSELECT_IN : 0) |
                       (fds[i].revents & POLLOUT ? CURL_CSELECT_OUT : 0) |
                       (fds[i].revents & (POLLERR | POLLNVAL) ? CURL_CSELECT_ERR : 0);
            C.multi_socket_action(multi, fds[i].fd, mask, &running);
        }
        if (curl_deadline >= 0 && now() >= curl_deadline) {
            curl_deadline = -1;
            C.multi_socket_action(multi, CURL_SOCKET_TIMEOUT, 0, &running);
        }
        CURLMsg *m;
        int left;
        while ((m = C.multi_info_read(multi, &left))) {
            if (m->msg != CURLMSG_DONE)
                continue;
            FURLLoad *l = nil;
            for (FURLLoad *x in loads)
                if (x->easy == m->easy_handle)
                    l = x;
            if (!l)
                continue;
            CURLcode result = m->data.result;
            NSError *error = nil;
            if (result != CURLE_OK)
                error = url_error(code_for_curl(result), l->url, nil);
            finish(l, error);
        }
        /* the request's timeout: no data for that long */
        NSTimeInterval t = now();
        NSArray *now_loading = [[loads copy] autorelease];
        for (FURLLoad *l in now_loading)
            if (!l->done && !l->paused && t >= l->active_at + l->idle)
                finish(l, url_error(NSURLErrorTimedOut, l->url, nil));
    }
    return events != before;
}

/* ---- exchanges: one request seen through, from the first transfer to the last -------------- */

/* An exchange is what a task or a connection asks for: a request answered.
 * It may take several transfers: a redirect is followed with a new
 * request, a 401 is answered with a credential and the request sent
 * again, and a stored response may answer without the network at all or
 * be revalidated. Its owner hears what it would of a single transfer (the
 * FURLLoadClient messages: the last response, its body, the end) and is
 * asked the questions a delegate answers: whether to follow a redirect,
 * how to answer a challenge (the server's certificate before connecting
 * to an https server, a 401 after one) and what to store in the cache.
 * The owner may answer later, from its delegate's queue or any other
 * thread; until it does, nothing moves. Every answer takes the engine's
 * lock, as everything else an exchange does runs with it held. Cookies are
 * sent with each request and kept from each response, redirects and
 * challenges included. */

@class FURLExchange;
@protocol FURLExchangeOwner <FURLLoadClient>
@optional
- (void)_exchange:(FURLExchange *)x redirectedBy:(NSHTTPURLResponse *)response to:(NSURLRequest *)request
           answer:(void (^)(NSURLRequest *))answer;
- (BOOL)_exchangeAsksAboutTrust:(FURLExchange *)x;
- (void)_exchange:(FURLExchange *)x challenged:(NSURLAuthenticationChallenge *)challenge
           answer:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))answer;
- (void)_exchange:(FURLExchange *)x willCache:(NSCachedURLResponse *)proposed
           answer:(void (^)(NSCachedURLResponse *))answer;
@end

enum { HOLD_NONE, HOLD_REDIRECT, HOLD_AUTH, HOLD_NOT_MODIFIED };
enum { MAX_REDIRECTS = 16 };

@interface FURLExchange : NSObject <FURLLoadClient> {
@public
    id owner;
    NSURLRequest *request;          /* the request being sent now */
    NSDictionary *extra;            /* the session's own header fields */
    NSTimeInterval idle, total;
    NSData *body;                   /* an upload task's body, in place of the request's */
    NSHTTPCookieStorage *cookies;   /* nil: cookies are neither sent nor kept */
    NSHTTPCookieAcceptPolicy acceptPolicy;
    NSURLCache *cache;              /* nil: nothing is looked up or stored */
    NSURLRequestCachePolicy cachePolicy;
    BOOL mayStore;                  /* the response may be stored (not a download's) */
    NSURLCredentialStorage *credentials; /* nil: none are used unasked, or kept */
    NSInteger cancelCode;           /* the error of a challenge cancelled */

    FURLLoad *load;
    BOOL done, paused;
    int redirects, hold;
    NSURLResponse *held, *delivered; /* a response being decided about; the one given to the owner */
    NSMutableData *heldBody, *keep;  /* its body; the delivered body, for the cache */
    NSCachedURLResponse *cached;     /* a stored response being revalidated */

    NSURLProtectionSpace *space;     /* the protection space credentials are for */
    NSURLCredential *credential;     /* sent with each request into it */
    NSDictionary *digest;            /* the Digest challenge's parameters */
    NSString *pendingMethod, *pendingRealm;
    NSDictionary *pendingParams;
    unsigned nonceCount;
    BOOL sentCredential, triedURLCredential, triedStoredCredential, retriedStale;
    NSInteger failures;
    NSMutableSet *checked, *trusted; /* "host:port" asked about, and accepted by the delegate */
}
- (void)start;
- (void)cancel;
- (void)pause:(BOOL)pause;
@end

static NSString *lower_scheme(NSURL *url) { return [[url scheme] lowercaseString]; }
static BOOL is_http(NSURL *url)
{
    NSString *s = lower_scheme(url);
    return [s isEqualToString:@"http"] || [s isEqualToString:@"https"];
}
static NSInteger port_of(NSURL *url)
{
    if ([url port])
        return [[url port] integerValue];
    return [lower_scheme(url) isEqualToString:@"https"] ? 443 : 80;
}
static NSString *host_port(NSURL *url)
{
    return [NSString stringWithFormat:@"%@:%ld", [[url host] lowercaseString], (long)port_of(url)];
}

/* The request target, as Digest authentication quotes it: the path and query as written. */
static NSString *request_target(NSURL *url)
{
    NSString *s = wire_url(url);
    NSRange r = [s rangeOfString:@"://"];
    if (r.location == NSNotFound)
        return @"/";
    s = [s substringFromIndex:NSMaxRange(r)];
    NSRange slash = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?"]];
    if (slash.location == NSNotFound)
        return @"/";
    s = [s substringFromIndex:slash.location];
    return [s hasPrefix:@"/"] ? s : [@"/" stringByAppendingString:s];
}

/* ---- the parts of header fields: Cache-Control's directives and WWW-Authenticate's challenges */

/* Cache-Control (and Pragma): directive -> value ("" for none), names in lower case. */
static NSDictionary *directives(NSString *field)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *part in [field componentsSeparatedByString:@","]) {
        NSString *p = trimmed(part);
        NSRange eq = [p rangeOfString:@"="];
        NSString *k = [trimmed(eq.location == NSNotFound ? p : [p substringToIndex:eq.location]) lowercaseString];
        NSString *v = eq.location == NSNotFound ? @"" : trimmed([p substringFromIndex:eq.location + 1]);
        if ([v hasPrefix:@"\""] && [v hasSuffix:@"\""] && [v length] >= 2)
            v = [v substringWithRange:NSMakeRange(1, [v length] - 2)];
        if ([k length])
            [d setObject:v forKey:k];
    }
    return d;
}

/* WWW-Authenticate's challenges (RFC 9110, 11.6.1): an array of
 * [scheme, parameters], the scheme in lower case. */
static NSArray *challenges_in(NSString *field)
{
    NSMutableArray *out = [NSMutableArray array];
    const char *s = [field UTF8String];
    size_t i = 0, n = s ? strlen(s) : 0;
    NSMutableDictionary *params = nil;
    while (i < n) {
        while (i < n && (s[i] == ' ' || s[i] == '\t' || s[i] == ','))
            i++;
        size_t t = i;
        while (i < n && s[i] != ' ' && s[i] != '\t' && s[i] != ',' && s[i] != '=')
            i++;
        if (i == t)
            break;
        NSString *token = [[[NSString alloc] initWithBytes:s + t length:i - t encoding:NSUTF8StringEncoding] autorelease];
        size_t j = i;
        while (j < n && (s[j] == ' ' || s[j] == '\t'))
            j++;
        if (j < n && s[j] == '=' && params) {
            /* a parameter of the challenge being read */
            i = j + 1;
            while (i < n && (s[i] == ' ' || s[i] == '\t'))
                i++;
            NSMutableString *value = [NSMutableString string];
            if (i < n && s[i] == '"') {
                i++;
                size_t v = i;
                NSMutableData *raw = [NSMutableData data];
                while (i < n && s[i] != '"') {
                    if (s[i] == '\\' && i + 1 < n)
                        i++;
                    [raw appendBytes:s + i length:1];
                    i++;
                }
                (void)v;
                i++;
                [value appendString:[[[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] autorelease]
                                        ?: @""];
            } else {
                size_t v = i;
                while (i < n && s[i] != ',' && s[i] != ' ' && s[i] != '\t')
                    i++;
                [value appendString:[[[NSString alloc] initWithBytes:s + v length:i - v
                                                            encoding:NSUTF8StringEncoding] autorelease]];
            }
            [params setObject:value forKey:[token lowercaseString]];
        } else if (j < n && s[j] == '=' && !params) {
            break; /* not a challenge */
        } else {
            params = [NSMutableDictionary dictionary];
            [out addObject:[NSArray arrayWithObjects:[token lowercaseString], params, nil]];
            /* token68 (Basic realm-less forms) is skipped */
        }
    }
    return out;
}

static NSString *base64(NSString *text)
{
    return [[text dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

/* ---- freshness (RFC 9111, 4.2) */

static NSTimeInterval freshness_lifetime(NSHTTPURLResponse *r, NSDate *stored)
{
    NSDictionary *cc = directives([r valueForHTTPHeaderField:@"Cache-Control"]);
    if ([cc objectForKey:@"no-cache"])
        return 0;
    NSString *max = [cc objectForKey:@"max-age"];
    if (max)
        return [max doubleValue];
    NSDate *date = FParseHTTPDate([r valueForHTTPHeaderField:@"Date"]) ?: stored;
    NSString *expires = [r valueForHTTPHeaderField:@"Expires"];
    if (expires) {
        NSDate *e = FParseHTTPDate(expires);
        return e ? MAX([e timeIntervalSinceDate:date], 0) : 0;
    }
    NSDate *modified = FParseHTTPDate([r valueForHTTPHeaderField:@"Last-Modified"]);
    if (modified)
        return MAX([date timeIntervalSinceDate:modified], 0) / 10; /* the usual heuristic: a tenth of its age */
    return 0;
}

static BOOL is_fresh(NSCachedURLResponse *c, NSURLRequest *request)
{
    NSHTTPURLResponse *r = (NSHTTPURLResponse *)[c response];
    if (![r isKindOfClass:[NSHTTPURLResponse class]])
        return YES;
    NSDictionary *rcc = directives([request valueForHTTPHeaderField:@"Cache-Control"]);
    if ([rcc objectForKey:@"no-cache"] || [[rcc objectForKey:@"max-age"] isEqualToString:@"0"] ||
        [directives([request valueForHTTPHeaderField:@"Pragma"]) objectForKey:@"no-cache"])
        return NO;
    NSDate *stored = [c _storedAt] ?: [NSDate distantPast];
    NSTimeInterval age = -[stored timeIntervalSinceNow] + [[r valueForHTTPHeaderField:@"Age"] doubleValue];
    return age < freshness_lifetime(r, stored);
}

static BOOL has_validators(NSCachedURLResponse *c)
{
    NSHTTPURLResponse *r = (NSHTTPURLResponse *)[c response];
    return [r isKindOfClass:[NSHTTPURLResponse class]] &&
           ([r valueForHTTPHeaderField:@"ETag"] || [r valueForHTTPHeaderField:@"Last-Modified"]);
}

/* ---- data URLs (RFC 2397) */

static NSData *percent_decoded_bytes(NSString *s)
{
    const char *in = [s UTF8String];
    size_t n = strlen(in);
    NSMutableData *out = [NSMutableData dataWithCapacity:n];
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)in[i];
        if (c == '%' && i + 2 < n + 0 && isxdigit((unsigned char)in[i + 1]) && isxdigit((unsigned char)in[i + 2])) {
            char hex[3] = {in[i + 1], in[i + 2], 0};
            c = (unsigned char)strtol(hex, NULL, 16);
            i += 2;
        }
        [out appendBytes:&c length:1];
    }
    return out;
}

@implementation FURLExchange
- (void)dealloc
{
    [owner release];
    [request release];
    [extra release];
    [body release];
    [cookies release];
    [cache release];
    [credentials release];
    [load release];
    [held release];
    [delivered release];
    [heldBody release];
    [keep release];
    [cached release];
    [space release];
    [credential release];
    [digest release];
    [pendingMethod release];
    [pendingRealm release];
    [pendingParams release];
    [checked release];
    [trusted release];
    [super dealloc];
}

- (void)start
{
    LOCK_ENGINE();
    [[self retain] autorelease];
    if (!checked) {
        checked = [[NSMutableSet alloc] init];
        trusted = [[NSMutableSet alloc] init];
    }
    [self _begin];
    UNLOCK_ENGINE();
}

- (void)cancel
{
    LOCK_ENGINE();
    if (!done) {
        done = YES;
        [[self retain] autorelease];
        cancel_load(load);
        [load release];
        load = nil;
        [owner autorelease];
        owner = nil;
    }
    UNLOCK_ENGINE();
}

- (void)pause:(BOOL)p
{
    LOCK_ENGINE();
    paused = p;
    pause_load(load, p);
    UNLOCK_ENGINE();
}

/* ---- the end, and what the owner hears */

- (void)_finish:(NSError *)error
{
    if (done)
        return;
    done = YES;
    [[self retain] autorelease];
    id o = [owner autorelease];
    owner = nil;
    [o _load:self finishedWithError:error];
}

- (void)_give:(NSURLResponse *)response data:(NSData *)data
{
    [delivered release];
    delivered = [response retain];
    [owner _load:self receivedResponse:response];
    if ([data length] && !done)
        [owner _load:self receivedBytes:[data bytes] length:[data length]];
}

/* A stored response, as the answer. */
- (void)_serve:(NSCachedURLResponse *)c
{
    [self _give:[c response] data:[c data]];
    [self _finish:nil];
}

/* The response held back, given as it is after all: a redirect not
 * followed or a challenge not answered. */
- (void)_giveHeld
{
    NSURLResponse *r = [[held retain] autorelease];
    NSData *d = [[heldBody retain] autorelease];
    [held release];
    held = nil;
    [heldBody release];
    heldBody = nil;
    hold = HOLD_NONE;
    [self _give:r data:d];
    [self _finish:nil];
}

/* ---- sending */

- (void)_begin
{
    if (done)
        return;
    NSURL *url = [request URL];
    if ([lower_scheme(url) isEqualToString:@"data"]) {
        [self _loadData];
        return;
    }
    [cached release];
    cached = nil;
    BOOL get = [[[request HTTPMethod] uppercaseString] isEqualToString:@"GET"];
    if (is_http(url) && get) {
        NSURLRequestCachePolicy p = cachePolicy;
        BOOL look = p == NSURLRequestUseProtocolCachePolicy || p == NSURLRequestReturnCacheDataElseLoad ||
                    p == NSURLRequestReturnCacheDataDontLoad || p == NSURLRequestReloadRevalidatingCacheData;
        NSCachedURLResponse *c = look ? [cache cachedResponseForRequest:request] : nil;
        if (p == NSURLRequestReturnCacheDataDontLoad) {
            if (c)
                [self _serve:c];
            else
                [self _finish:url_error(NSURLErrorResourceUnavailable, url, @"resource unavailable")];
            return;
        }
        if (c && (p == NSURLRequestReturnCacheDataElseLoad ||
                  (p == NSURLRequestUseProtocolCachePolicy && is_fresh(c, request)))) {
            [self _serve:c];
            return;
        }
        if (c && has_validators(c))
            cached = [c retain];
    } else if (cachePolicy == NSURLRequestReturnCacheDataDontLoad && is_http(url)) {
        [self _finish:url_error(NSURLErrorResourceUnavailable, url, @"resource unavailable")];
        return;
    }
    if ([lower_scheme(url) isEqualToString:@"https"] && [url host] && ![checked containsObject:host_port(url)] &&
        [owner respondsToSelector:@selector(_exchangeAsksAboutTrust:)] && [owner _exchangeAsksAboutTrust:self]) {
        [self _askAboutTrust];
        return;
    }
    [self _send];
}

/* Before connecting to an https server, the delegate may judge its
 * certificate. Default handling leaves that to libcurl, which checks it
 * against this system's certificate authorities. */
- (void)_askAboutTrust
{
    NSURL *url = [request URL];
    NSString *hp = host_port(url);
    [checked addObject:hp];
    NSURLProtectionSpace *s = [[[NSURLProtectionSpace alloc] initWithHost:[url host]
                                                                     port:port_of(url)
                                                                 protocol:NSURLProtectionSpaceHTTPS
                                                                    realm:nil
                                                     authenticationMethod:NSURLAuthenticationMethodServerTrust]
        autorelease];
    FURLServerTrust *trust = [[[FURLServerTrust alloc] init] autorelease];
    trust->host = [[url host] copy];
    trust->port = port_of(url);
    [s _setServerTrust:trust];
    NSURLAuthenticationChallenge *c = [[[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:s
                                                                                  proposedCredential:nil
                                                                                previousFailureCount:0
                                                                                     failureResponse:nil
                                                                                               error:nil
                                                                                              sender:nil] autorelease];
    [owner _exchange:self
          challenged:c
              answer:^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *cred) {
                LOCK_ENGINE();
                if (done) {
                } else if (disposition == NSURLSessionAuthChallengeCancelAuthenticationChallenge) {
                    [self _finish:url_error(cancelCode, [request URL], nil)];
                } else {
                    if (disposition == NSURLSessionAuthChallengeUseCredential && [cred _isForTrust])
                        [trusted addObject:hp];
                    [self _send];
                }
                UNLOCK_ENGINE();
              }];
}

- (NSString *)_authorizationFor:(NSURL *)url
{
    if (!credential || !space || ![credential user] || [[space host] caseInsensitiveCompare:[url host] ?: @""] ||
        [space port] != port_of(url) || ![[space protocol] isEqualToString:lower_scheme(url)])
        return nil;
    NSString *user = [credential user], *password = [credential password] ?: @"";
    if (![[space authenticationMethod] isEqualToString:NSURLAuthenticationMethodHTTPDigest])
        return [@"Basic " stringByAppendingString:base64([NSString stringWithFormat:@"%@:%@", user, password])];
    NSString *realm = [digest objectForKey:@"realm"] ?: @"", *nonce = [digest objectForKey:@"nonce"] ?: @"";
    NSString *algorithm = [digest objectForKey:@"algorithm"], *opaque = [digest objectForKey:@"opaque"];
    NSString *qop = nil;
    for (NSString *q in [[digest objectForKey:@"qop"] componentsSeparatedByString:@","])
        if ([trimmed(q) caseInsensitiveCompare:@"auth"] == NSOrderedSame)
            qop = @"auth";
    NSString *uri = request_target(url);
    NSString *nc = [NSString stringWithFormat:@"%08x", ++nonceCount];
    NSString *cnonce = [FMD5Hex([NSString stringWithFormat:@"%f %p %u", now(), self, nonceCount]) substringToIndex:16];
    NSString *ha1 = FMD5Hex([NSString stringWithFormat:@"%@:%@:%@", user, realm, password]);
    if (algorithm && [algorithm caseInsensitiveCompare:@"MD5-sess"] == NSOrderedSame)
        ha1 = FMD5Hex([NSString stringWithFormat:@"%@:%@:%@", ha1, nonce, cnonce]);
    NSString *ha2 = FMD5Hex([NSString stringWithFormat:@"%@:%@", [[request HTTPMethod] uppercaseString], uri]);
    NSString *response =
        qop ? FMD5Hex([NSString stringWithFormat:@"%@:%@:%@:%@:%@:%@", ha1, nonce, nc, cnonce, qop, ha2])
            : FMD5Hex([NSString stringWithFormat:@"%@:%@:%@", ha1, nonce, ha2]);
    NSMutableString *h = [NSMutableString stringWithFormat:@"Digest username=\"%@\", realm=\"%@\", nonce=\"%@\", "
                                                           @"uri=\"%@\", response=\"%@\"",
                                                           user, realm, nonce, uri, response];
    if (algorithm)
        [h appendFormat:@", algorithm=%@", algorithm];
    if (opaque)
        [h appendFormat:@", opaque=\"%@\"", opaque];
    if (qop)
        [h appendFormat:@", qop=%@, nc=%@, cnonce=\"%@\"", qop, nc, cnonce];
    return h;
}

- (void)_send
{
    if (done)
        return;
    NSURL *url = [request URL];
    NSMutableDictionary *added = [NSMutableDictionary dictionary];
    if (cookies && is_http(url)) {
        NSArray *list = [cookies cookiesForURL:url];
        if ([list count])
            [added addEntriesFromDictionary:[NSHTTPCookie requestHeaderFieldsWithCookies:list]];
    }
    NSString *auth = is_http(url) ? [self _authorizationFor:url] : nil;
    sentCredential = auth != nil;
    if (auth)
        [added setObject:auth forKey:@"Authorization"];
    if (cached) {
        NSHTTPURLResponse *r = (NSHTTPURLResponse *)[cached response];
        if ([r valueForHTTPHeaderField:@"ETag"])
            [added setObject:[r valueForHTTPHeaderField:@"ETag"] forKey:@"If-None-Match"];
        if ([r valueForHTTPHeaderField:@"Last-Modified"])
            [added setObject:[r valueForHTTPHeaderField:@"Last-Modified"] forKey:@"If-Modified-Since"];
    }
    hold = HOLD_NONE;
    [held release];
    held = nil;
    [heldBody release];
    heldBody = nil;
    [keep release];
    keep = nil;
    NSError *e = nil;
    BOOL insecure = is_http(url) && [url host] && [trusted containsObject:host_port(url)];
    FURLLoad *l = start_load(request, extra, added, idle, total, body, insecure, self, &e);
    if (!l) {
        [self _finish:e];
        return;
    }
    [load release];
    load = [l retain];
    if (paused)
        pause_load(l, YES);
}

/* ---- what the transfer says */

- (void)_load:(id)l receivedResponse:(NSURLResponse *)response
{
    if (l != load || done)
        return;
    NSHTTPURLResponse *h = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    NSURL *url = [request URL];
    FURLLoad *fl = l;
    if (h && cookies) {
        NSMutableArray *values = [NSMutableArray array];
        for (NSUInteger i = 0; i < [fl->names count]; i++)
            if ([[fl->names objectAtIndex:i] caseInsensitiveCompare:@"Set-Cookie"] == NSOrderedSame)
                [values addObject:[fl->values objectAtIndex:i]];
        if ([values count])
            [cookies _setCookies:[NSHTTPCookie _cookiesFromValues:values forURL:url]
                          forURL:url
                 mainDocumentURL:[request mainDocumentURL]
                          policy:acceptPolicy];
    }
    NSInteger status = [h statusCode];
    hold = HOLD_NONE;
    if (h && (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) &&
        [h valueForHTTPHeaderField:@"Location"])
        hold = HOLD_REDIRECT;
    else if (h && status == 401 && [self _readChallenge:h])
        hold = HOLD_AUTH;
    else if (h && status == 304 && cached)
        hold = HOLD_NOT_MODIFIED;
    if (hold != HOLD_NONE) {
        [held release];
        held = [response retain];
        [heldBody release];
        heldBody = [[NSMutableData alloc] init];
        return;
    }
    NSString *method = [[request HTTPMethod] uppercaseString];
    if (mayStore && cache && h && status >= 200 && status < 300 && status != 206 && [method isEqualToString:@"GET"] &&
        ![directives([h valueForHTTPHeaderField:@"Cache-Control"]) objectForKey:@"no-store"] &&
        ![directives([request valueForHTTPHeaderField:@"Cache-Control"]) objectForKey:@"no-store"])
        keep = [[NSMutableData alloc] init];
    [self _give:response data:nil];
}

- (void)_load:(id)l receivedBytes:(const void *)bytes length:(size_t)length
{
    if (l != load || done)
        return;
    if (hold != HOLD_NONE) {
        [heldBody appendBytes:bytes length:length];
        return;
    }
    if (keep) {
        /* a response much larger than the cache isn't stored (Apple's documentation: about a twentieth) */
        NSUInteger limit = MAX([cache diskCapacity], [cache memoryCapacity]) / 20;
        if ([keep length] + length > limit) {
            [keep release];
            keep = nil;
        } else
            [keep appendBytes:bytes length:length];
    }
    [owner _load:self receivedBytes:bytes length:length];
}

- (void)_load:(id)l sent:(int64_t)sent of:(int64_t)all
{
    if (l == load && !done)
        [owner _load:self sent:sent of:all];
}

- (void)_load:(id)l finishedWithError:(NSError *)error
{
    if (l != load || done)
        return;
    [[self retain] autorelease];
    [load autorelease];
    load = nil;
    if (error) {
        [self _finish:error];
        return;
    }
    switch (hold) {
    case HOLD_REDIRECT: [self _redirect]; return;
    case HOLD_AUTH: [self _challenge]; return;
    case HOLD_NOT_MODIFIED: [self _notModified]; return;
    }
    if (keep && delivered) {
        NSCachedURLResponse *c = [[[NSCachedURLResponse alloc] initWithResponse:delivered data:keep] autorelease];
        [c _setStoredAt:[NSDate date]];
        NSURLRequest *r = [[request retain] autorelease];
        NSURLCache *store = [[cache retain] autorelease];
        void (^then)(NSCachedURLResponse *) = ^(NSCachedURLResponse *answer) {
          LOCK_ENGINE();
          if (!done) {
              if (answer) {
                  if (![answer _storedAt])
                      [answer _setStoredAt:[NSDate date]];
                  [store storeCachedResponse:answer forRequest:r];
              }
              [self _finish:nil];
          }
          UNLOCK_ENGINE();
        };
        if ([owner respondsToSelector:@selector(_exchange:willCache:answer:)])
            [owner _exchange:self willCache:c answer:then];
        else
            then(c);
        return;
    }
    [self _finish:nil];
}

/* ---- redirects */

- (void)_redirect
{
    NSHTTPURLResponse *r = (NSHTTPURLResponse *)held;
    NSURL *target = [[NSURL URLWithString:[r valueForHTTPHeaderField:@"Location"] relativeToURL:[request URL]]
        absoluteURL];
    if (!target || !is_http(target) || ![[target host] length]) {
        [self _giveHeld]; /* a Location that can't be followed: the redirect is the answer */
        return;
    }
    if (++redirects > MAX_REDIRECTS) {
        [self _finish:url_error(NSURLErrorHTTPTooManyRedirects, [request URL], nil)];
        return;
    }
    NSMutableURLRequest *next = [[request mutableCopy] autorelease];
    [next setURL:target];
    NSString *method = [[request HTTPMethod] uppercaseString];
    NSInteger status = [r statusCode];
    if ((status == 303 && ![method isEqualToString:@"HEAD"]) ||
        ((status == 301 || status == 302) && [method isEqualToString:@"POST"])) {
        /* RFC 9110, 15.4: a 303, and a POST moved by a 301 or 302, become a GET without a body */
        [next setHTTPMethod:@"GET"];
        [next setHTTPBody:nil];
        [next setValue:nil forHTTPHeaderField:@"Content-Type"];
        [next setValue:nil forHTTPHeaderField:@"Content-Length"];
        [body release];
        body = nil;
    }
    if ([[[request mainDocumentURL] absoluteString] isEqualToString:[[request URL] absoluteString]])
        [next setMainDocumentURL:target];
    void (^answer)(NSURLRequest *) = ^(NSURLRequest *chosen) {
      LOCK_ENGINE();
      if (done) {
      } else if (!chosen) {
          [self _giveHeld];
      } else {
          [request release];
          request = [chosen copy];
          [self _begin];
      }
      UNLOCK_ENGINE();
    };
    if ([owner respondsToSelector:@selector(_exchange:redirectedBy:to:answer:)])
        [owner _exchange:self redirectedBy:r to:next answer:answer];
    else
        answer(next);
}

/* ---- authentication: HTTP Basic and Digest (RFC 7617, RFC 7616) */

/* Reads the challenge of a 401 into the pending fields; NO if there is
 * none that Ferry can answer. Digest (MD5) is taken before Basic. */
- (BOOL)_readChallenge:(NSHTTPURLResponse *)r
{
    FURLLoad *fl = load;
    NSArray *found = nil, *basic = nil, *dig = nil;
    for (NSUInteger i = 0; i < [fl->names count]; i++)
        if ([[fl->names objectAtIndex:i] caseInsensitiveCompare:@"WWW-Authenticate"] == NSOrderedSame)
            for (NSArray *c in challenges_in([fl->values objectAtIndex:i])) {
                NSString *scheme = [c objectAtIndex:0];
                NSString *alg = [[c objectAtIndex:1] objectForKey:@"algorithm"];
                if ([scheme isEqualToString:@"digest"] && !dig &&
                    (!alg || [alg caseInsensitiveCompare:@"MD5"] == NSOrderedSame ||
                     [alg caseInsensitiveCompare:@"MD5-sess"] == NSOrderedSame))
                    dig = c;
                else if ([scheme isEqualToString:@"basic"] && !basic)
                    basic = c;
            }
    found = dig ?: basic;
    if (!found)
        return NO;
    [pendingMethod release];
    pendingMethod = [(found == dig ? NSURLAuthenticationMethodHTTPDigest : NSURLAuthenticationMethodHTTPBasic) retain];
    [pendingParams release];
    pendingParams = [[found objectAtIndex:1] copy];
    [pendingRealm release];
    pendingRealm = [[pendingParams objectForKey:@"realm"] copy];
    return YES;
}

- (void)_useCredential:(NSURLCredential *)c
{
    if (credentials && [c persistence] != NSURLCredentialPersistenceNone) {
        [credentials setCredential:c forProtectionSpace:space];
        if (![credentials defaultCredentialForProtectionSpace:space])
            [credentials setDefaultCredential:c forProtectionSpace:space];
    }
    [c retain];
    [credential release];
    credential = c;
    [self _begin];
}

/* The credential default handling uses: the URL's own user and password,
 * then the storage's, each tried once. */
- (NSURLCredential *)_defaultCredential
{
    NSURL *url = [request URL];
    if (!triedURLCredential) {
        triedURLCredential = YES;
        if ([[url user] length])
            return [NSURLCredential credentialWithUser:[url user] password:[url password] ?: @""
                                           persistence:NSURLCredentialPersistenceNone];
    }
    if (!triedStoredCredential) {
        triedStoredCredential = YES;
        NSURLCredential *c = [credentials _credentialForSpace:space];
        if (c && ![c isEqual:credential])
            return c;
    }
    return nil;
}

- (void)_challenge
{
    NSURL *url = [request URL];
    NSURLProtectionSpace *s = [[[NSURLProtectionSpace alloc] initWithHost:[url host]
                                                                     port:port_of(url)
                                                                 protocol:lower_scheme(url)
                                                                    realm:pendingRealm
                                                     authenticationMethod:pendingMethod] autorelease];
    BOOL same = space && [space isEqual:s];
    /* a stale Digest nonce is answered again with the same credential, unasked */
    if (same && sentCredential && !retriedStale && [pendingMethod isEqualToString:NSURLAuthenticationMethodHTTPDigest] &&
        [[[pendingParams objectForKey:@"stale"] lowercaseString] isEqualToString:@"true"]) {
        retriedStale = YES;
        [digest release];
        digest = [pendingParams retain];
        nonceCount = 0;
        [self _begin];
        return;
    }
    if (same && sentCredential)
        failures++;
    else if (!same)
        failures = 0;
    [space release];
    space = [s retain];
    [digest release];
    digest = [pendingParams retain];
    nonceCount = 0;
    NSURLCredential *proposed = failures && credential ? credential : nil;
    if (!proposed && !triedURLCredential && [[url user] length])
        proposed = [NSURLCredential credentialWithUser:[url user] password:[url password] ?: @""
                                           persistence:NSURLCredentialPersistenceNone];
    if (!proposed)
        proposed = [credentials _credentialForSpace:s];
    NSURLAuthenticationChallenge *c = [[[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:s
                                                                                  proposedCredential:proposed
                                                                                previousFailureCount:failures
                                                                                     failureResponse:held
                                                                                               error:nil
                                                                                              sender:nil] autorelease];
    void (^answer)(NSURLSessionAuthChallengeDisposition, NSURLCredential *) =
        ^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *cred) {
          LOCK_ENGINE();
          if (!done)
              switch (disposition) {
              case NSURLSessionAuthChallengeUseCredential:
                  if ([cred user])
                      [self _useCredential:cred];
                  else
                      [self _giveHeld];
                  break;
              case NSURLSessionAuthChallengeCancelAuthenticationChallenge:
                  [self _finish:url_error(cancelCode, [request URL], nil)];
                  break;
              case NSURLSessionAuthChallengePerformDefaultHandling: {
                  NSURLCredential *d = [self _defaultCredential];
                  if (d)
                      [self _useCredential:d];
                  else
                      [self _giveHeld];
                  break;
              }
              default: /* rejecting the only protection space there is */
                  [self _giveHeld];
                  break;
              }
          UNLOCK_ENGINE();
        };
    if ([owner respondsToSelector:@selector(_exchange:challenged:answer:)])
        [owner _exchange:self challenged:c answer:answer];
    else
        answer(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

/* ---- revalidation: a 304 answers with the stored response, its fields brought up to date */

- (void)_notModified
{
    NSHTTPURLResponse *old = (NSHTTPURLResponse *)[cached response], *fresh = (NSHTTPURLResponse *)held;
    NSMutableDictionary *fields = [[[old allHeaderFields] mutableCopy] autorelease];
    NSDictionary *newer = [fresh allHeaderFields];
    for (NSString *k in newer) {
        if ([k caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame ||
            [k caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame ||
            [k caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame)
            continue;
        NSString *existing = field_key(fields, k);
        if (existing)
            [fields removeObjectForKey:existing];
        [fields setObject:[newer objectForKey:k] forKey:k];
    }
    NSHTTPURLResponse *r = [[[NSHTTPURLResponse alloc] initWithURL:[old URL] statusCode:[old statusCode]
                                                        HTTPVersion:@"HTTP/1.1"
                                                       headerFields:fields] autorelease];
    NSCachedURLResponse *c = [[[NSCachedURLResponse alloc] initWithResponse:r data:[cached data]
                                                                   userInfo:[cached userInfo]
                                                              storagePolicy:[cached storagePolicy]] autorelease];
    [c _setStoredAt:[NSDate date]];
    if (mayStore)
        [cache storeCachedResponse:c forRequest:request];
    [held release];
    held = nil;
    hold = HOLD_NONE;
    [self _serve:c];
}

/* ---- data URLs */

- (void)_loadData
{
    NSURL *url = [request URL];
    NSString *s = [url absoluteString];
    NSRange hash = [s rangeOfString:@"#"];
    if (hash.location != NSNotFound)
        s = [s substringToIndex:hash.location];
    s = [s substringFromIndex:5]; /* "data:" */
    NSRange comma = [s rangeOfString:@","];
    if (comma.location == NSNotFound) {
        [self _finish:url_error(NSURLErrorBadURL, url, nil)];
        return;
    }
    NSArray *meta = [[s substringToIndex:comma.location] componentsSeparatedByString:@";"];
    NSString *payload = [s substringFromIndex:comma.location + 1];
    NSString *type = [trimmed([meta objectAtIndex:0]) lowercaseString], *charset = nil;
    BOOL b64 = NO;
    for (NSUInteger i = 1; i < [meta count]; i++) {
        NSString *p = trimmed([meta objectAtIndex:i]);
        if ([p caseInsensitiveCompare:@"base64"] == NSOrderedSame && i == [meta count] - 1)
            b64 = YES;
        else if ([[p lowercaseString] hasPrefix:@"charset="])
            charset = [p substringFromIndex:8];
    }
    if (![type length]) {
        type = @"text/plain";
        if (!charset)
            charset = @"US-ASCII";
    }
    NSData *data = percent_decoded_bytes(payload);
    if (b64) {
        NSString *text = [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
        text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            componentsJoinedByString:@""];
        data = text ? [[[NSData alloc] initWithBase64EncodedString:text options:0] autorelease] : nil;
        if (!data) {
            [self _finish:url_error(NSURLErrorCannotDecodeRawData, url, @"cannot decode raw data")];
            return;
        }
    }
    NSURLResponse *r = [[[NSURLResponse alloc] initWithURL:url MIMEType:type
                                     expectedContentLength:(NSInteger)[data length]
                                          textEncodingName:charset] autorelease];
    [self _give:r data:data];
    [self _finish:nil];
}
@end

/* An exchange with what the shared objects give: the shared cookie
 * storage, URL cache and credential storage (NSURLConnection and the
 * ...ContentsOfURL: calls). A session sets its own. */
static FURLExchange *new_exchange(NSURLRequest *request, id owner)
{
    FURLExchange *x = [[[FURLExchange alloc] init] autorelease];
    x->owner = [owner retain];
    x->request = [request copy] ?: [[NSURLRequest alloc] initWithURL:nil];
    x->idle = [request timeoutInterval];
    BOOL web = is_http([request URL]);
    if (web && [request HTTPShouldHandleCookies]) {
        x->cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] retain];
        x->acceptPolicy = [x->cookies cookieAcceptPolicy];
    }
    if (web) {
        x->cache = [[NSURLCache sharedURLCache] retain];
        x->credentials = [[NSURLCredentialStorage sharedCredentialStorage] retain];
    }
    x->cachePolicy = [request cachePolicy];
    x->mayStore = YES;
    x->cancelCode = NSURLErrorCancelled;
    return x;
}

/* ---- a client that gathers everything, for the calls that wait or answer once ------------- */

@interface FURLGather : NSObject <FURLLoadClient> {
@public
    NSURLResponse *response;
    NSMutableData *data;
    NSError *error;
    BOOL done;
    void (^then)(FURLGather *);
}
@end

@implementation FURLGather
- (instancetype)init
{
    data = [[NSMutableData alloc] init];
    return self;
}
- (void)dealloc
{
    [response release];
    [data release];
    [error release];
    [then release];
    [super dealloc];
}
- (void)_load:(id)load receivedResponse:(NSURLResponse *)r
{
    [response release];
    response = [r retain];
    [data setLength:0];
}
- (void)_load:(id)load receivedBytes:(const void *)bytes length:(size_t)length
{
    [data appendBytes:bytes length:length];
}
- (void)_load:(id)load sent:(int64_t)sent of:(int64_t)total {}
- (void)_load:(id)load finishedWithError:(NSError *)e
{
    error = [e retain];
    done = YES;
    pthread_cond_broadcast(&engine_done); /* for load_and_wait */
    if (then)
        then(self);
}
@end

/* Loads a URL and waits for it: the body, or nil with *error. */
static NSData *load_and_wait(NSURLRequest *request, NSURLResponse **response, NSError **error)
{
    FURLGather *g = [[[FURLGather alloc] init] autorelease];
    FURLExchange *x = [new_exchange(request, g) retain];
    LOCK_ENGINE();
    [x start];
    while (!g->done)
        pthread_cond_wait(&engine_done, &engine_lock);
    UNLOCK_ENGINE();
    [x release];
    if (response)
        *response = [[g->response retain] autorelease];
    if (g->error) {
        FSetError(error, [[g->error retain] autorelease]);
        return nil;
    }
    return [[g->data copy] autorelease];
}

/* Something that runs blocks for a delegate or a completion handler: an
 * NSOperationQueue (or anything else that takes addOperationWithBlock:),
 * or else a dispatch queue. */
static void run_on(id opqueue, dispatch_queue_t queue, void (^block)(void))
{
    if (opqueue && [opqueue respondsToSelector:@selector(addOperationWithBlock:)])
        ((void (*)(id, SEL, id))objc_msgSend)(opqueue, @selector(addOperationWithBlock:), block);
    else
        dispatch_async(queue ?: dispatch_get_main_queue(), block);
}

/* ---- NSURLSessionConfiguration ------------------------------------------------------------ */

@interface NSURLSessionConfiguration () {
@package
    NSString *_identifier, *_container;
    NSURLRequestCachePolicy _cachePolicy;
    NSTimeInterval _requestTimeout, _resourceTimeout;
    NSURLRequestNetworkServiceType _serviceType;
    BOOL _cellular, _waits, _pipelining, _cookies, _launch, _discretionary;
    NSInteger _perHost;
    NSDictionary *_headers, *_proxy;
    NSHTTPCookieAcceptPolicy _acceptPolicy;
    /* the stores a session uses; until one is set (nil included), the shared one */
    NSHTTPCookieStorage *_cookieStorage;
    NSURLCache *_urlCache;
    NSURLCredentialStorage *_credentialStorage;
    BOOL _ownCookieStorage, _ownCache, _ownCredentialStorage;
}
@end

@implementation NSURLSessionConfiguration
+ (NSURLSessionConfiguration *)defaultSessionConfiguration { return [[[self alloc] init] autorelease]; }
/* An ephemeral session keeps cookies, credentials and responses in memory
 * of its own, and none of them outlives it. */
+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration
{
    NSURLSessionConfiguration *c = [[[self alloc] init] autorelease];
    c->_cookieStorage = [[NSHTTPCookieStorage _privateStorage] retain];
    c->_urlCache = [[NSURLCache _memoryOnlyCache] retain];
    c->_credentialStorage = [[NSURLCredentialStorage _privateStorage] retain];
    c->_ownCookieStorage = c->_ownCache = c->_ownCredentialStorage = YES;
    return c;
}
+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier
{
    NSURLSessionConfiguration *c = [[[self alloc] init] autorelease];
    c->_identifier = [identifier copy];
    return c;
}
- (instancetype)init
{
    _requestTimeout = 60;
    _resourceTimeout = 7 * 24 * 3600;
    _cellular = _cookies = YES;
    _perHost = 6;
    _acceptPolicy = NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain;
    return self;
}
- (void)dealloc
{
    [_identifier release];
    [_container release];
    [_headers release];
    [_proxy release];
    [_cookieStorage release];
    [_urlCache release];
    [_credentialStorage release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSURLSessionConfiguration *c = [[NSURLSessionConfiguration alloc] init];
    c->_identifier = [_identifier copy];
    c->_container = [_container copy];
    c->_cachePolicy = _cachePolicy;
    c->_requestTimeout = _requestTimeout;
    c->_resourceTimeout = _resourceTimeout;
    c->_serviceType = _serviceType;
    c->_cellular = _cellular;
    c->_waits = _waits;
    c->_pipelining = _pipelining;
    c->_cookies = _cookies;
    c->_launch = _launch;
    c->_discretionary = _discretionary;
    c->_perHost = _perHost;
    c->_headers = [_headers copy];
    c->_proxy = [_proxy copy];
    c->_acceptPolicy = _acceptPolicy;
    c->_cookieStorage = [_cookieStorage retain];
    c->_urlCache = [_urlCache retain];
    c->_credentialStorage = [_credentialStorage retain];
    c->_ownCookieStorage = _ownCookieStorage;
    c->_ownCache = _ownCache;
    c->_ownCredentialStorage = _ownCredentialStorage;
    return c;
}
- (NSHTTPCookieAcceptPolicy)HTTPCookieAcceptPolicy { return _acceptPolicy; }
- (void)setHTTPCookieAcceptPolicy:(NSHTTPCookieAcceptPolicy)p { _acceptPolicy = p; }
- (NSHTTPCookieStorage *)HTTPCookieStorage
{
    return _ownCookieStorage ? _cookieStorage : [NSHTTPCookieStorage sharedHTTPCookieStorage];
}
- (void)setHTTPCookieStorage:(NSHTTPCookieStorage *)s
{
    [s retain];
    [_cookieStorage release];
    _cookieStorage = s;
    _ownCookieStorage = YES;
}
- (NSURLCache *)URLCache { return _ownCache ? _urlCache : [NSURLCache sharedURLCache]; }
- (void)setURLCache:(NSURLCache *)cache
{
    [cache retain];
    [_urlCache release];
    _urlCache = cache;
    _ownCache = YES;
}
- (NSURLCredentialStorage *)URLCredentialStorage
{
    return _ownCredentialStorage ? _credentialStorage : [NSURLCredentialStorage sharedCredentialStorage];
}
- (void)setURLCredentialStorage:(NSURLCredentialStorage *)s
{
    [s retain];
    [_credentialStorage release];
    _credentialStorage = s;
    _ownCredentialStorage = YES;
}
- (NSString *)identifier { return _identifier; }
- (NSURLRequestCachePolicy)requestCachePolicy { return _cachePolicy; }
- (void)setRequestCachePolicy:(NSURLRequestCachePolicy)p { _cachePolicy = p; }
- (NSTimeInterval)timeoutIntervalForRequest { return _requestTimeout; }
- (void)setTimeoutIntervalForRequest:(NSTimeInterval)t { _requestTimeout = t; }
- (NSTimeInterval)timeoutIntervalForResource { return _resourceTimeout; }
- (void)setTimeoutIntervalForResource:(NSTimeInterval)t { _resourceTimeout = t; }
- (NSURLRequestNetworkServiceType)networkServiceType { return _serviceType; }
- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)t { _serviceType = t; }
- (BOOL)allowsCellularAccess { return _cellular; }
- (void)setAllowsCellularAccess:(BOOL)b { _cellular = b; }
- (BOOL)waitsForConnectivity { return _waits; }
- (void)setWaitsForConnectivity:(BOOL)b { _waits = b; }
- (BOOL)HTTPShouldUsePipelining { return _pipelining; }
- (void)setHTTPShouldUsePipelining:(BOOL)b { _pipelining = b; }
- (BOOL)HTTPShouldSetCookies { return _cookies; }
- (void)setHTTPShouldSetCookies:(BOOL)b { _cookies = b; }
- (NSInteger)HTTPMaximumConnectionsPerHost { return _perHost; }
- (void)setHTTPMaximumConnectionsPerHost:(NSInteger)n { _perHost = n; }
- (NSDictionary *)HTTPAdditionalHeaders { return _headers; }
- (void)setHTTPAdditionalHeaders:(NSDictionary *)h
{
    h = [h copy];
    [_headers release];
    _headers = h;
}
- (NSDictionary *)connectionProxyDictionary { return _proxy; }
- (void)setConnectionProxyDictionary:(NSDictionary *)d
{
    d = [d copy];
    [_proxy release];
    _proxy = d;
}
- (NSString *)sharedContainerIdentifier { return _container; }
- (void)setSharedContainerIdentifier:(NSString *)s
{
    s = [s copy];
    [_container release];
    _container = s;
}
- (BOOL)sessionSendsLaunchEvents { return _launch; }
- (void)setSessionSendsLaunchEvents:(BOOL)b { _launch = b; }
- (BOOL)isDiscretionary { return _discretionary; }
- (void)setDiscretionary:(BOOL)b { _discretionary = b; }
@end

/* ---- NSURLSession and its tasks --------------------------------------------------------- */

enum { KIND_DATA, KIND_UPLOAD, KIND_DOWNLOAD };

@interface NSURLSession () {
@package
    NSURLSessionConfiguration *_config;
    id _delegate;
    id _opqueue;
    dispatch_queue_t _queue;
    NSMutableArray *_tasks;
    NSUInteger _nextID;
    BOOL _shared, _invalid, _told;
    NSString *_description;
}
- (instancetype)_initWithConfiguration:(NSURLSessionConfiguration *)c delegate:(id)delegate queue:(id)queue;
- (void)_deliver:(void (^)(void))block;
- (void)_taskEnded:(NSURLSessionTask *)task;
@end

@interface NSURLSessionTask () <FURLExchangeOwner> {
@package
    NSURLSession *_session;
    NSUInteger _id;
    NSURLRequest *_original;
    NSURLResponse *_response;
    NSURLSessionTaskState _state;
    NSError *_error;
    int64_t _received, _sent, _expectSend, _expectReceive;
    NSString *_description;
    float _priority;
    id _delegate;
    int _kind;
    id _handler;          /* the completion handler, if any */
    NSData *_upload;      /* an upload task's body */
    NSMutableData *_data; /* the body, for a data task's completion handler */
    FURLExchange *_exchange; /* the request seen through */
    NSURLRequest *_current; /* the request sent last, redirects followed */
    BOOL _started, _ended;
    BOOL _awaiting;       /* the delegate hasn't said yet whether to go on after the response */
    NSMutableArray *_held; /* messages that wait for it to */
    int _fd;              /* a download's file */
    NSString *_path;
    BOOL _writeFailed;
}
- (id)_hearer;
- (void)_post:(void (^)(void))block;
- (void)_answered:(NSURLSessionResponseDisposition)disposition;
- (void)_openFile;
- (void)_endWithError:(NSError *)error;
- (void)_resumeLocked;
- (void)_suspendLocked;
- (void)_cancelLocked;
- (void)_answeredLocked:(NSURLSessionResponseDisposition)disposition;
@end

@implementation NSURLSessionTask
- (instancetype)init
{
    _state = NSURLSessionTaskStateSuspended;
    _priority = NSURLSessionTaskPriorityDefault;
    _expectSend = _expectReceive = NSURLSessionTransferSizeUnknown;
    _fd = -1;
    return self;
}
- (void)dealloc
{
    if (_fd >= 0)
        close(_fd);
    if (_path)
        unlink([_path fileSystemRepresentation]);
    [_session release];
    [_original release];
    [_response release];
    [_error release];
    [_description release];
    [_delegate release];
    [_handler release];
    [_upload release];
    [_data release];
    [_exchange release];
    [_current release];
    [_held release];
    [_path release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)taskIdentifier { return _id; }
- (NSURLRequest *)originalRequest { return _original; }
- (NSURLRequest *)currentRequest { return _current ?: _original; }
- (NSURLResponse *)response { return _response; }
- (NSURLSessionTaskState)state { return _state; }
- (NSError *)error { return _error; }
- (int64_t)countOfBytesReceived { return _received; }
- (int64_t)countOfBytesSent { return _sent; }
- (int64_t)countOfBytesExpectedToSend { return _expectSend; }
- (int64_t)countOfBytesExpectedToReceive { return _expectReceive; }
- (NSString *)taskDescription { return _description; }
- (void)setTaskDescription:(NSString *)d
{
    d = [d copy];
    [_description release];
    _description = d;
}
- (float)priority { return _priority; }
- (void)setPriority:(float)p { _priority = p; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d
{
    [d retain];
    [_delegate release];
    _delegate = d;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p>{ taskIdentifier: %lu } { %@ }", [self class], self,
                                      (unsigned long)_id,
                                      _state == NSURLSessionTaskStateRunning     ? @"running"
                                      : _state == NSURLSessionTaskStateSuspended ? @"suspended"
                                      : _state == NSURLSessionTaskStateCanceling ? @"canceling"
                                                                                 : @"completed"];
}

/* The delegate that hears about this task: its own, or its session's. */
- (id)_hearer { return _delegate ?: _session->_delegate; }

/* Queues a message on the session's delegate queue, in order, unless the
 * delegate is still deciding about the response. */
- (void)_post:(void (^)(void))block
{
    if (_awaiting) {
        id copy = [block copy];
        [_held addObject:copy];
        [copy release];
    } else
        [_session _deliver:block];
}

- (void)resume
{
    LOCK_ENGINE();
    [self _resumeLocked];
    UNLOCK_ENGINE();
}
- (void)suspend
{
    LOCK_ENGINE();
    [self _suspendLocked];
    UNLOCK_ENGINE();
}
- (void)cancel
{
    LOCK_ENGINE();
    [self _cancelLocked];
    UNLOCK_ENGINE();
}
- (void)_resumeLocked
{
    if (_ended || _state == NSURLSessionTaskStateCanceling || _state == NSURLSessionTaskStateCompleted)
        return;
    if (_started) {
        if (_state == NSURLSessionTaskStateSuspended) {
            _state = NSURLSessionTaskStateRunning;
            [_exchange pause:NO];
        }
        return;
    }
    _started = YES;
    _state = NSURLSessionTaskStateRunning;
    NSURLSessionConfiguration *c = _session->_config;
    NSTimeInterval idle = [_original timeoutInterval];
    if (idle == 60 || idle <= 0)
        idle = c->_requestTimeout;
    if (_upload)
        _expectSend = [_upload length];
    else if ([_original HTTPBody])
        _expectSend = [[_original HTTPBody] length];
    FURLExchange *x = [[FURLExchange alloc] init];
    x->owner = [self retain];
    x->request = [_original copy] ?: [[NSURLRequest alloc] initWithURL:nil];
    x->extra = [c->_headers copy];
    x->idle = idle;
    x->total = c->_resourceTimeout;
    x->body = [_upload retain];
    NSURL *url = [_original URL];
    BOOL web = is_http(url);
    if (web && c->_cookies && [_original HTTPShouldHandleCookies]) {
        x->cookies = [[c HTTPCookieStorage] retain];
        x->acceptPolicy = c->_acceptPolicy;
    }
    if (web) {
        x->cache = [[c URLCache] retain];
        x->credentials = [[c URLCredentialStorage] retain];
    }
    x->cachePolicy = [_original cachePolicy] == NSURLRequestUseProtocolCachePolicy ? c->_cachePolicy
                                                                                    : [_original cachePolicy];
    x->mayStore = _kind != KIND_DOWNLOAD;
    x->cancelCode = NSURLErrorCancelled;
    _exchange = x;
    [x start];
}
- (void)_suspendLocked
{
    if (_state != NSURLSessionTaskStateRunning)
        return;
    _state = NSURLSessionTaskStateSuspended;
    [_exchange pause:YES];
}
- (void)_cancelLocked
{
    if (_ended || _state == NSURLSessionTaskStateCanceling || _state == NSURLSessionTaskStateCompleted)
        return;
    _state = NSURLSessionTaskStateCanceling;
    [_exchange cancel];
    _awaiting = NO;
    [_held removeAllObjects];
    [self _endWithError:url_error(NSURLErrorCancelled, [[self currentRequest] URL], nil)];
}

/* ---- what the exchange asks: the delegate's answers */

- (void)_exchange:(FURLExchange *)x redirectedBy:(NSHTTPURLResponse *)response to:(NSURLRequest *)request
           answer:(void (^)(NSURLRequest *))answer
{
    id d = [self _hearer];
    void (^go)(NSURLRequest *) = ^(NSURLRequest *chosen) {
      LOCK_ENGINE();
      if (chosen) {
          [chosen retain];
          [_current release];
          _current = chosen;
      }
      answer(chosen);
      UNLOCK_ENGINE();
    };
    if (![d respondsToSelector:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]) {
        go(request);
        return;
    }
    NSURLSession *s = _session;
    __block BOOL answered = NO;
    void (^once)(NSURLRequest *) = [[go copy] autorelease];
    [self _post:^{
      [d URLSession:s
                                task:self
          willPerformHTTPRedirection:response
                          newRequest:request
                   completionHandler:^(NSURLRequest *chosen) {
                     LOCK_ENGINE();
                     BOOL first = !answered;
                     answered = YES;
                     if (first)
                         once(chosen);
                     UNLOCK_ENGINE();
                   }];
    }];
}

- (BOOL)_exchangeAsksAboutTrust:(FURLExchange *)x
{
    return [_session->_delegate respondsToSelector:@selector(URLSession:didReceiveChallenge:completionHandler:)] ||
           [[self _hearer] respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)];
}

/* A server's certificate is asked about at the session's level first (as
 * other challenges for the whole session are), and else at the task's; a
 * password only at the task's. */
- (void)_exchange:(FURLExchange *)x challenged:(NSURLAuthenticationChallenge *)challenge
           answer:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))answer
{
    NSURLSession *s = _session;
    id sd = s->_delegate, d = [self _hearer];
    BOOL trust = [[[challenge protectionSpace] authenticationMethod]
        isEqualToString:NSURLAuthenticationMethodServerTrust];
    __block BOOL answered = NO;
    void (^once)(NSURLSessionAuthChallengeDisposition, NSURLCredential *) =
        [[^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
          LOCK_ENGINE();
          BOOL first = !answered;
          answered = YES;
          if (first)
              answer(disposition, credential);
          UNLOCK_ENGINE();
        } copy] autorelease];
    if (trust && [sd respondsToSelector:@selector(URLSession:didReceiveChallenge:completionHandler:)])
        [self _post:^{
          [sd URLSession:s didReceiveChallenge:challenge completionHandler:once];
        }];
    else if ([d respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)])
        [self _post:^{
          [d URLSession:s task:self didReceiveChallenge:challenge completionHandler:once];
        }];
    else
        answer(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)_exchange:(FURLExchange *)x willCache:(NSCachedURLResponse *)proposed
           answer:(void (^)(NSCachedURLResponse *))answer
{
    id d = [self _hearer];
    if (_handler || _kind == KIND_DOWNLOAD ||
        ![d respondsToSelector:@selector(URLSession:dataTask:willCacheResponse:completionHandler:)]) {
        answer(proposed);
        return;
    }
    NSURLSession *s = _session;
    __block BOOL answered = NO;
    void (^then)(NSCachedURLResponse *) = [[answer copy] autorelease];
    [self _post:^{
      [d URLSession:s
                   dataTask:(NSURLSessionDataTask *)self
          willCacheResponse:proposed
          completionHandler:^(NSCachedURLResponse *chosen) {
            LOCK_ENGINE();
            BOOL first = !answered;
            answered = YES;
            if (first)
                then(chosen);
            UNLOCK_ENGINE();
          }];
    }];
}

/* ---- what the transfer says */

- (void)_load:(id)load receivedResponse:(NSURLResponse *)response
{
    [_response release];
    _response = [response retain];
    _expectReceive = [response expectedContentLength];
    if (_kind == KIND_DOWNLOAD) {
        [self _openFile];
        return;
    }
    id d = [self _hearer];
    if (_handler || ![d respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)])
        return;
    NSURLSession *s = _session;
    __block BOOL answered = NO;
    _awaiting = YES;
    [_session _deliver:^{
      [d URLSession:s
                   dataTask:(NSURLSessionDataTask *)self
         didReceiveResponse:response
          completionHandler:^(NSURLSessionResponseDisposition disposition) {
            LOCK_ENGINE();
            BOOL first = !answered;
            answered = YES;
            if (first)
                [self _answeredLocked:disposition];
            UNLOCK_ENGINE();
          }];
    }];
}
- (void)_answered:(NSURLSessionResponseDisposition)disposition
{
    LOCK_ENGINE();
    [self _answeredLocked:disposition];
    UNLOCK_ENGINE();
}
- (void)_answeredLocked:(NSURLSessionResponseDisposition)disposition
{
    if (!_awaiting)
        return;
    _awaiting = NO;
    if (disposition == NSURLSessionResponseCancel) {
        [_held removeAllObjects];
        _ended = NO;
        _state = NSURLSessionTaskStateRunning;
        [self _cancelLocked];
        return;
    }
    NSArray *held = [_held copy];
    [_held removeAllObjects];
    for (id b in held)
        [_session _deliver:b];
    [held release];
}
- (void)_openFile
{
    if (_fd >= 0 || _writeFailed)
        return;
    NSString *dir = NSTemporaryDirectory();
    char *tmpl = strdup([[dir stringByAppendingPathComponent:@"CFNetworkDownload_XXXXXX.tmp"] fileSystemRepresentation]);
    _fd = mkstemps(tmpl, 4);
    if (_fd >= 0)
        _path = [[NSString alloc] initWithUTF8String:tmpl];
    else
        _writeFailed = YES;
    free(tmpl);
}
- (void)_load:(id)load receivedBytes:(const void *)bytes length:(size_t)length
{
    _received += length;
    if (_kind == KIND_DOWNLOAD) {
        [self _openFile];
        const char *p = bytes;
        size_t left = length;
        while (left && _fd >= 0) {
            ssize_t n = write(_fd, p, left);
            if (n <= 0) {
                _writeFailed = YES;
                break;
            }
            p += n;
            left -= n;
        }
        id d = [self _hearer];
        if (!_handler && [d respondsToSelector:@selector(URLSession:
                                                     downloadTask:didWriteData:totalBytesWritten:
                                                         totalBytesExpectedToWrite:)]) {
            NSURLSession *s = _session;
            int64_t total = _received, expect = _expectReceive;
            [self _post:^{
              [d URLSession:s
                               downloadTask:(NSURLSessionDownloadTask *)self
                               didWriteData:(int64_t)length
                          totalBytesWritten:total
                  totalBytesExpectedToWrite:expect];
            }];
        }
        return;
    }
    if (_handler) {
        [_data appendBytes:bytes length:length];
        return;
    }
    id d = [self _hearer];
    if ([d respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        NSURLSession *s = _session;
        NSData *chunk = [NSData dataWithBytes:bytes length:length];
        [self _post:^{
          [d URLSession:s dataTask:(NSURLSessionDataTask *)self didReceiveData:chunk];
        }];
    }
}
- (void)_load:(id)load sent:(int64_t)sent of:(int64_t)total
{
    int64_t step = sent - _sent;
    _sent = sent;
    id d = [self _hearer];
    if (step > 0 &&
        [d respondsToSelector:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)]) {
        NSURLSession *s = _session;
        [self _post:^{
          [d URLSession:s task:self didSendBodyData:step totalBytesSent:sent totalBytesExpectedToSend:total];
        }];
    }
}
- (void)_load:(id)load finishedWithError:(NSError *)error
{
    if (!error && _writeFailed)
        error = url_error(NSURLErrorCannotWriteToFile, [_original URL], nil);
    [self _endWithError:error];
}

/* The last message: the completion handler, or the delegate's. */
- (void)_endWithError:(NSError *)error
{
    if (_ended)
        return;
    _ended = YES;
    [_error release];
    _error = [error retain];
    [_exchange autorelease];
    _exchange = nil;
    if (_kind == KIND_DOWNLOAD && !error)
        [self _openFile];
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
    NSURLSession *s = _session;
    id d = [self _hearer];
    NSURLResponse *response = _response;
    [self _post:^{
      LOCK_ENGINE();
      _state = NSURLSessionTaskStateCompleted;
      UNLOCK_ENGINE();
      NSURL *location = !error && _path ? [NSURL fileURLWithPath:_path] : nil;
      if (_handler) {
          if (_kind == KIND_DOWNLOAD)
              ((void (^)(NSURL *, NSURLResponse *, NSError *))_handler)(location, response, error);
          else
              ((void (^)(NSData *, NSURLResponse *, NSError *))_handler)(error ? nil : [[_data copy] autorelease],
                                                                         response, error);
      } else {
          if (_kind == KIND_DOWNLOAD && location &&
              [d respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)])
              [d URLSession:s downloadTask:(NSURLSessionDownloadTask *)self didFinishDownloadingToURL:location];
          if ([d respondsToSelector:@selector(URLSession:task:didCompleteWithError:)])
              [d URLSession:s task:self didCompleteWithError:error];
      }
      if (_path) {
          unlink([_path fileSystemRepresentation]);
          [_path release];
          _path = nil;
      }
      [_handler release];
      _handler = nil;
      [s _taskEnded:self];
    }];
}
@end

@implementation NSURLSessionDataTask
@end
@implementation NSURLSessionUploadTask
@end
@implementation NSURLSessionDownloadTask
- (void)cancelByProducingResumeData:(void (^)(NSData *resumeData))completionHandler
{
    [self cancel];
    if (completionHandler) {
        id handler = [completionHandler copy];
        [_session _deliver:^{
          ((void (^)(NSData *))handler)(nil);
          [handler release];
        }];
    }
}
@end

static NSMutableArray *live_sessions; /* kept until invalidated, as a Mac keeps them */

@implementation NSURLSession
+ (NSURLSession *)sharedSession
{
    static NSURLSession *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      shared = [[NSURLSession alloc] _initWithConfiguration:nil delegate:nil queue:nil];
      shared->_shared = YES;
    });
    return shared;
}
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
{
    return [self sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];
}
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                  delegate:(id)delegate
                             delegateQueue:(NSOperationQueue *)queue
{
    NSURLSession *s = [[self alloc] _initWithConfiguration:configuration delegate:delegate queue:queue];
    LOCK_ENGINE();
    if (!live_sessions)
        live_sessions = [[NSMutableArray alloc] init];
    [live_sessions addObject:s];
    UNLOCK_ENGINE();
    return [s autorelease];
}
- (instancetype)_initWithConfiguration:(NSURLSessionConfiguration *)c delegate:(id)delegate queue:(id)queue
{
    _config = c ? [c copy] : [[NSURLSessionConfiguration alloc] init];
    _delegate = [delegate retain];
    if (queue) {
        _opqueue = [queue retain];
    } else {
        /* As on a Mac: with no queue given, the session makes a serial
         * operation queue of its own for its delegate and handlers. */
        NSOperationQueue *own = [[NSOperationQueue alloc] init];
        own.maxConcurrentOperationCount = 1;
        _opqueue = own;
    }
    _queue = dispatch_queue_create("NSURLSession delegate queue", NULL);
    _tasks = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc
{
    [_config release];
    [_delegate release];
    [_opqueue release];
    dispatch_release(_queue);
    [_tasks release];
    [_description release];
    [super dealloc];
}
- (NSOperationQueue *)delegateQueue { return _opqueue; }
- (id)delegate { return _delegate; }
- (NSURLSessionConfiguration *)configuration { return [[_config copy] autorelease]; }
- (NSString *)sessionDescription { return _description; }
- (void)setSessionDescription:(NSString *)d
{
    d = [d copy];
    [_description release];
    _description = d;
}
- (void)_deliver:(void (^)(void))block { run_on(_opqueue, _queue, block); }

- (id)_task:(Class)cls kind:(int)kind request:(NSURLRequest *)request upload:(NSData *)upload handler:(id)handler
{
    if (_invalid)
        FRaise(NSGenericException, @"Task created in a session that has been invalidated");
    NSURLSessionTask *t = [[[cls alloc] init] autorelease];
    LOCK_ENGINE();
    t->_session = [self retain];
    t->_id = ++_nextID;
    t->_kind = kind;
    t->_original = [request copy];
    if (!t->_original)
        t->_original = [[NSURLRequest alloc] initWithURL:nil];
    t->_upload = [upload copy];
    t->_handler = [handler copy];
    t->_data = [[NSMutableData alloc] init];
    t->_held = [[NSMutableArray alloc] init];
    [_tasks addObject:t];
    UNLOCK_ENGINE();
    return t;
}
static NSURLRequest *request_for(NSURL *url) { return url ? [NSURLRequest requestWithURL:url] : nil; }

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
{
    return [self _task:[NSURLSessionDataTask class] kind:KIND_DATA request:request upload:nil handler:nil];
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url { return [self dataTaskWithRequest:request_for(url)]; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler
{
    return [self _task:[NSURLSessionDataTask class] kind:KIND_DATA request:request upload:nil handler:handler];
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler
{
    return [self dataTaskWithRequest:request_for(url) completionHandler:handler];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData
{
    return [self uploadTaskWithRequest:request fromData:bodyData completionHandler:nil];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL
{
    return [self uploadTaskWithRequest:request fromFile:fileURL completionHandler:nil];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler
{
    return [self _task:[NSURLSessionUploadTask class]
                  kind:KIND_UPLOAD
               request:request
                upload:bodyData ?: [NSData data]
               handler:handler];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler
{
    NSData *body = [fileURL isFileURL] ? [NSData dataWithContentsOfFile:[fileURL path]] : nil;
    NSURLSessionUploadTask *t = [self uploadTaskWithRequest:request fromData:body completionHandler:handler];
    if (!body) {
        LOCK_ENGINE();
        t->_started = YES;
        t->_state = NSURLSessionTaskStateRunning;
        [t _endWithError:url_error(NSURLErrorFileDoesNotExist, fileURL, nil)];
        UNLOCK_ENGINE();
    }
    return t;
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
{
    return [self _task:[NSURLSessionDownloadTask class] kind:KIND_DOWNLOAD request:request upload:nil handler:nil];
}
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
{
    return [self downloadTaskWithRequest:request_for(url)];
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))handler
{
    return [self _task:[NSURLSessionDownloadTask class]
                  kind:KIND_DOWNLOAD
               request:request
                upload:nil
               handler:handler];
}
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))handler
{
    return [self downloadTaskWithRequest:request_for(url) completionHandler:handler];
}

- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *))handler
{
    NSMutableArray *open = [NSMutableArray array];
    LOCK_ENGINE();
    for (NSURLSessionTask *t in _tasks)
        if (!t->_ended)
            [open addObject:t];
    UNLOCK_ENGINE();
    id copy = [handler copy];
    [self _deliver:^{
      ((void (^)(NSArray *))copy)(open);
      [copy release];
    }];
}

/* When an invalidated session has nothing left going on, its delegate
 * hears so and is let go. */
- (void)_checkInvalid
{
    if (!_invalid || _told)
        return;
    for (NSURLSessionTask *t in _tasks)
        if (t->_started)
            return;
    _told = YES;
    id d = _delegate;
    [self _deliver:^{
      if ([d respondsToSelector:@selector(URLSession:didBecomeInvalidWithError:)])
          [d URLSession:self didBecomeInvalidWithError:nil];
      [_delegate release];
      _delegate = nil;
      LOCK_ENGINE();
      [live_sessions removeObjectIdenticalTo:self];
      UNLOCK_ENGINE();
    }];
}
- (void)_taskEnded:(NSURLSessionTask *)task
{
    [[task retain] autorelease];
    LOCK_ENGINE();
    [_tasks removeObjectIdenticalTo:task];
    [self _checkInvalid];
    UNLOCK_ENGINE();
}
- (void)finishTasksAndInvalidate
{
    LOCK_ENGINE();
    if (!_shared && !_invalid) {
        _invalid = YES;
        [self _checkInvalid];
    }
    UNLOCK_ENGINE();
}
- (void)invalidateAndCancel
{
    LOCK_ENGINE();
    if (!_shared && !_invalid) {
        _invalid = YES;
        NSArray *now_open = [[_tasks copy] autorelease];
        for (NSURLSessionTask *t in now_open)
            [t cancel];
        [self _checkInvalid];
    }
    UNLOCK_ENGINE();
}
@end

/* ---- NSURLConnection ------------------------------------------------------------------------ */

/* The sender of a connection's challenges: each of its messages is an
 * answer, as a session's disposition is. */
@interface FURLChallengeSender : NSObject <NSURLAuthenticationChallengeSender> {
@public
    void (^answer)(NSURLSessionAuthChallengeDisposition, NSURLCredential *);
}
@end

@implementation FURLChallengeSender
- (void)dealloc
{
    [answer release];
    [super dealloc];
}
- (void)_answer:(NSURLSessionAuthChallengeDisposition)d credential:(NSURLCredential *)c
{
    LOCK_ENGINE();
    void (^a)(NSURLSessionAuthChallengeDisposition, NSURLCredential *) = [answer autorelease];
    answer = nil;
    if (a)
        a(d, c);
    UNLOCK_ENGINE();
}
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
{
    [self _answer:NSURLSessionAuthChallengeUseCredential credential:credential];
}
- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
{
    [self _answer:NSURLSessionAuthChallengeUseCredential credential:nil];
}
- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
{
    [self _answer:NSURLSessionAuthChallengeCancelAuthenticationChallenge credential:nil];
}
- (void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
{
    [self _answer:NSURLSessionAuthChallengePerformDefaultHandling credential:nil];
}
- (void)rejectProtectionSpaceAndContinueWithChallenge:(NSURLAuthenticationChallenge *)c
{
    [self _answer:NSURLSessionAuthChallengeRejectProtectionSpace credential:nil];
}
@end

@interface NSURLConnection () <FURLExchangeOwner> {
    NSURLRequest *_request, *_current;
    id _delegate;
    id _opqueue;
    FURLExchange *_exchange;
    BOOL _started, _over;
}
@end

@implementation NSURLConnection
+ (BOOL)canHandleRequest:(NSURLRequest *)request
{
    NSString *scheme = [[[request URL] scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"file"] ||
           [scheme isEqualToString:@"data"];
}
+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    return [[[self alloc] initWithRequest:request delegate:delegate] autorelease];
}
- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    return [self initWithRequest:request delegate:delegate startImmediately:YES];
}
- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)start
{
    _request = [request copy];
    _delegate = [delegate retain]; /* held until the connection ends, as on a Mac */
    if (start)
        [self start];
    return self;
}
- (void)dealloc
{
    [_request release];
    [_delegate release];
    [_opqueue release];
    [_exchange release];
    [_current release];
    [super dealloc];
}
- (NSURLRequest *)originalRequest { return _request; }
- (NSURLRequest *)currentRequest { return _current ?: _request; }
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode {}
- (void)unscheduleFromRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode {}
- (void)setDelegateQueue:(NSOperationQueue *)queue
{
    [queue retain];
    [_opqueue release];
    _opqueue = queue;
}
- (void)_tell:(void (^)(void))block
{
    [self retain];
    run_on(_opqueue, NULL, ^{
      block();
      [self release];
    });
}
/* The delegate sees the request first (connection:willSendRequest:
 * redirectResponse: with no response) and may change it, or refuse it
 * with nil, which ends the connection without another message. */
- (void)start
{
    LOCK_ENGINE();
    BOOL first = !_started;
    _started = YES;
    id d = _delegate;
    if (!first) {
    } else if ([d respondsToSelector:@selector(connection:willSendRequest:redirectResponse:)])
        [self _tell:^{
          if (_over)
              return;
          NSURLRequest *r = [d connection:self willSendRequest:_request redirectResponse:nil];
          if (!r) {
              [self cancel];
              return;
          }
          [self _send:r];
        }];
    else
        [self _send:_request];
    UNLOCK_ENGINE();
}
- (void)_send:(NSURLRequest *)request
{
    LOCK_ENGINE();
    if (_over) {
        UNLOCK_ENGINE();
        return;
    }
    if (request != _request) {
        [_current release];
        _current = [request copy];
    }
    FURLExchange *x = [new_exchange(request, self) retain];
    x->cancelCode = NSURLErrorUserCancelledAuthentication;
    id d = _delegate;
    if ([d respondsToSelector:@selector(connectionShouldUseCredentialStorage:)] &&
        ![d connectionShouldUseCredentialStorage:self]) {
        [x->credentials release];
        x->credentials = nil;
    }
    _exchange = x;
    [x start];
    UNLOCK_ENGINE();
}
- (void)cancel
{
    LOCK_ENGINE();
    if (!_over) {
        _over = YES;
        [_exchange cancel];
        [_delegate autorelease];
        _delegate = nil;
    }
    UNLOCK_ENGINE();
}

/* ---- what the exchange asks: the delegate's answers */

- (void)_exchange:(FURLExchange *)x redirectedBy:(NSHTTPURLResponse *)response to:(NSURLRequest *)request
           answer:(void (^)(NSURLRequest *))answer
{
    id d = _delegate;
    void (^go)(NSURLRequest *) = [[^(NSURLRequest *chosen) {
      LOCK_ENGINE();
      if (chosen) {
          [chosen retain];
          [_current release];
          _current = chosen;
      }
      answer(chosen);
      UNLOCK_ENGINE();
    } copy] autorelease];
    if (![d respondsToSelector:@selector(connection:willSendRequest:redirectResponse:)]) {
        go(request);
        return;
    }
    [self _tell:^{
      if (!_over)
          go([d connection:self willSendRequest:request redirectResponse:response]);
    }];
}

- (BOOL)_exchangeAsksAboutTrust:(FURLExchange *)x
{
    id d = _delegate;
    return [d respondsToSelector:@selector(connection:willSendRequestForAuthenticationChallenge:)] ||
           ([d respondsToSelector:@selector(connection:canAuthenticateAgainstProtectionSpace:)] &&
            [d respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)]);
}

/* connection:willSendRequestForAuthenticationChallenge: is asked if the
 * delegate has it; else the older pair, connection:
 * canAuthenticateAgainstProtectionSpace: (which, unimplemented, means yes
 * to anything but a server's certificate or a client's) and connection:
 * didReceiveAuthenticationChallenge:; else default handling. */
- (void)_exchange:(FURLExchange *)x challenged:(NSURLAuthenticationChallenge *)challenge
           answer:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))answer
{
    id d = _delegate;
    FURLChallengeSender *sender = [[[FURLChallengeSender alloc] init] autorelease];
    sender->answer = [answer copy];
    NSURLAuthenticationChallenge *c = [[[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge
                                                                                                      sender:sender]
        autorelease];
    if ([d respondsToSelector:@selector(connection:willSendRequestForAuthenticationChallenge:)]) {
        [self _tell:^{
          if (!_over)
              [d connection:self willSendRequestForAuthenticationChallenge:c];
        }];
        return;
    }
    if ([d respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)]) {
        [self _tell:^{
          if (_over)
              return;
          NSURLProtectionSpace *space = [c protectionSpace];
          NSString *m = [space authenticationMethod];
          BOOL can = [d respondsToSelector:@selector(connection:canAuthenticateAgainstProtectionSpace:)]
                         ? [d connection:self canAuthenticateAgainstProtectionSpace:space]
                         : !([m isEqualToString:NSURLAuthenticationMethodServerTrust] ||
                             [m isEqualToString:NSURLAuthenticationMethodClientCertificate]);
          if (can)
              [d connection:self didReceiveAuthenticationChallenge:c];
          else
              [sender performDefaultHandlingForAuthenticationChallenge:c];
        }];
        return;
    }
    [sender performDefaultHandlingForAuthenticationChallenge:c];
}

- (void)_exchange:(FURLExchange *)x willCache:(NSCachedURLResponse *)proposed
           answer:(void (^)(NSCachedURLResponse *))answer
{
    id d = _delegate;
    if (![d respondsToSelector:@selector(connection:willCacheResponse:)]) {
        answer(proposed);
        return;
    }
    void (^then)(NSCachedURLResponse *) = [[answer copy] autorelease];
    [self _tell:^{
      if (!_over)
          then([d connection:self willCacheResponse:proposed]);
    }];
}
- (void)_load:(id)load receivedResponse:(NSURLResponse *)response
{
    id d = _delegate;
    if ([d respondsToSelector:@selector(connection:didReceiveResponse:)])
        [self _tell:^{
          if (!_over)
              [d connection:self didReceiveResponse:response];
        }];
}
- (void)_load:(id)load receivedBytes:(const void *)bytes length:(size_t)length
{
    id d = _delegate;
    if ([d respondsToSelector:@selector(connection:didReceiveData:)]) {
        NSData *chunk = [NSData dataWithBytes:bytes length:length];
        [self _tell:^{
          if (!_over)
              [d connection:self didReceiveData:chunk];
        }];
    }
}
- (void)_load:(id)load sent:(int64_t)sent of:(int64_t)total
{
    id d = _delegate;
    if ([d respondsToSelector:@selector(connection:didSendBodyData:totalBytesWritten:totalBytesExpectedToWrite:)])
        [self _tell:^{
          if (!_over)
              [d connection:self
                            didSendBodyData:(NSInteger)sent
                          totalBytesWritten:(NSInteger)sent
                  totalBytesExpectedToWrite:(NSInteger)total];
        }];
}
- (void)_load:(id)load finishedWithError:(NSError *)error
{
    id d = [_delegate retain];
    [self _tell:^{
      LOCK_ENGINE();
      BOOL tell = !_over;
      id held = nil;
      if (tell) {
          _over = YES;
          held = _delegate; /* let go once it has heard */
          _delegate = nil;
      }
      UNLOCK_ENGINE();
      if (tell) {
          if (error) {
              if ([d respondsToSelector:@selector(connection:didFailWithError:)])
                  [d connection:self didFailWithError:error];
          } else if ([d respondsToSelector:@selector(connectionDidFinishLoading:)])
              [d connectionDidFinishLoading:self];
      }
      [held release];
      [d release];
    }];
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response
                             error:(NSError **)error
{
    return load_and_wait(request, response, error);
}
+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler
{
    FURLGather *g = [[[FURLGather alloc] init] autorelease];
    id q = [queue retain];
    id h = [handler copy];
    g->then = [^(FURLGather *done) {
      NSURLResponse *r = done->response;
      NSData *data = done->error ? nil : [[done->data copy] autorelease];
      NSError *e = done->error;
      run_on(q, NULL, ^{
        if (h)
            ((void (^)(NSURLResponse *, NSData *, NSError *))h)(r, data, e);
      });
      [h release];
      [q release];
    } copy];
    [new_exchange(request, g) start];
}
@end

/* ---- reading URLs into data and strings ---------------------------------------------------- */

static BOOL is_web(NSURL *url)
{
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"data"];
}

/* For dataWithContentsOfURL: and the like: the body of an http, https or
 * data URL (whatever the status), or nil with a Cocoa error that holds the URL
 * error as its underlying error, as a Mac reports it. */
NSData *FDataWithContentsOfNetworkURL(NSURL *url, NSString **charset, NSError **error)
{
    NSURLResponse *response = nil;
    NSError *e = nil;
    NSData *d = load_and_wait([NSURLRequest requestWithURL:url], &response, &e);
    if (!d) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        if (url)
            [info setObject:url forKey:NSURLErrorKey];
        if (e)
            [info setObject:e forKey:NSUnderlyingErrorKey];
        NSString *name = [[url path] lastPathComponent];
        if (![name length] || [name isEqualToString:@"/"])
            name = [url host] ?: [url absoluteString];
        [info setObject:[NSString stringWithFormat:@"The file “%@” couldn’t be opened.", name]
                 forKey:NSLocalizedDescriptionKey];
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:info]);
        return nil;
    }
    if (charset)
        *charset = [response textEncodingName];
    return d;
}

@implementation NSData (NSURLLoading)
+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error
{
    if ([url isFileURL])
        return [self dataWithContentsOfFile:[url path] options:options error:error];
    if (!is_web(url)) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError
                                         userInfo:url ? [NSDictionary dictionaryWithObject:url forKey:NSURLErrorKey]
                                                      : nil]);
        return nil;
    }
    NSData *d = FDataWithContentsOfNetworkURL(url, NULL, error);
    return d ? [self dataWithData:d] : nil;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url { return [self initWithContentsOfURL:url options:0 error:NULL]; }
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error
{
    NSData *d = [NSData dataWithContentsOfURL:url options:options error:error];
    if (!d) {
        [self release];
        return nil;
    }
    return [self initWithData:d];
}
@end

static NSStringEncoding encoding_named(NSString *charset)
{
    NSString *c = [charset lowercaseString];
    if (!c)
        return 0;
    if ([c isEqualToString:@"utf-8"] || [c isEqualToString:@"utf8"])
        return NSUTF8StringEncoding;
    if ([c isEqualToString:@"iso-8859-1"] || [c isEqualToString:@"latin1"] || [c isEqualToString:@"iso8859-1"])
        return NSISOLatin1StringEncoding;
    if ([c isEqualToString:@"us-ascii"] || [c isEqualToString:@"ascii"])
        return NSASCIIStringEncoding;
    if ([c isEqualToString:@"utf-16"])
        return NSUTF16StringEncoding;
    if ([c isEqualToString:@"windows-1252"] || [c isEqualToString:@"cp1252"])
        return NSISOLatin1StringEncoding; /* close enough: Ferry has no CP-1252 */
    return 0;
}

/* For +[NSString stringWithContentsOfURL:...]: a network URL's text in the
 * encoding given, or (enc 0) the one the server named, else UTF-8. */
NSString *FStringWithContentsOfNetworkURL(NSURL *url, NSStringEncoding enc, NSStringEncoding *used, NSError **error)
{
    NSString *charset = nil;
    NSData *d = FDataWithContentsOfNetworkURL(url, &charset, error);
    if (!d)
        return nil;
    NSStringEncoding e = enc ?: encoding_named(charset);
    const unsigned char *b = [d bytes];
    if (!e && [d length] >= 2 && ((b[0] == 0xff && b[1] == 0xfe) || (b[0] == 0xfe && b[1] == 0xff)))
        e = NSUTF16StringEncoding;
    if (!e)
        e = NSUTF8StringEncoding;
    NSString *s = [[[NSString alloc] initWithData:d encoding:e] autorelease];
    if (!s) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:enc ? 261 : 264 /* inapplicable, unknown encoding */
                                         userInfo:[NSDictionary dictionaryWithObject:url forKey:NSURLErrorKey]]);
        return nil;
    }
    if (used)
        *used = e;
    return s;
}

@implementation NSString (NSURLLoading)
+ (instancetype)stringWithContentsOfURL:(NSURL *)url usedEncoding:(NSStringEncoding *)enc error:(NSError **)error
{
    if (is_web(url)) {
        NSString *s = FStringWithContentsOfNetworkURL(url, 0, enc, error);
        return s ? [self stringWithString:s] : nil;
    }
    return [self stringWithContentsOfFile:[url path] usedEncoding:enc error:error];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding)enc error:(NSError **)error
{
    NSString *s = [NSString stringWithContentsOfURL:url encoding:enc error:error];
    if (!s) {
        [self release];
        return nil;
    }
    return [self initWithString:s];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url usedEncoding:(NSStringEncoding *)enc error:(NSError **)error
{
    NSString *s = [NSString stringWithContentsOfURL:url usedEncoding:enc error:error];
    if (!s) {
        [self release];
        return nil;
    }
    return [self initWithString:s];
}
@end
