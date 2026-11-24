/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: URL loading. NSURLRequest and NSMutableURLRequest,
 * NSURLResponse and NSHTTPURLResponse, NSURLSession with its configuration
 * and its data, upload and download tasks, NSURLConnection, the
 * NSURLErrorDomain errors, and reading http and https URLs into NSData and
 * NSString. Written from Apple's public API documentation.
 *
 * The transfers themselves are done by this system's libcurl (FCurl.h),
 * through its "multi" interface: every transfer of the program shares one
 * multi handle, whose sockets are waited on by Foundation's run loop (as a
 * poller, NSRunLoop.m) and by dispatch's waits (dispatch_semaphore_wait,
 * dispatch_group_wait and dispatch_main, through ferry_dispatch_set_io in
 * src/objc/dispatch.c). Ferry runs a Mac program on one thread, so nothing
 * moves while the program neither runs its run loop nor waits on dispatch.
 *
 * Completion handlers and delegate messages are never called from inside
 * libcurl: each is queued, in order, on the session's delegate queue. That
 * is the queue the program gave (anything that takes addOperationWithBlock:,
 * as NSOperationQueue does) or else a serial dispatch queue of the
 * session's own; NSURLConnection's go to its delegate queue or else the
 * main queue. All of them run on the program's one thread, from the run
 * loop or from a dispatch wait. The synchronous calls
 * (sendSynchronousRequest:..., dataWithContentsOfURL:) wait on the network
 * alone, as a Mac's block their thread, and run nothing else meanwhile. */
#import "FInternal.h"
#include "FCurl.h"
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/stat.h>
#include <unistd.h>

void *ferry_network_symbol(const char *name);                                 /* src/host.c */
void ferry_dispatch_set_io(int (*pending)(void), void (*wait)(int timeout_ms)); /* src/objc/dispatch.c */
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
- (void)_load:(FURLLoad *)load receivedResponse:(NSURLResponse *)response;
- (void)_load:(FURLLoad *)load receivedBytes:(const void *)bytes length:(size_t)length;
- (void)_load:(FURLLoad *)load sent:(int64_t)sent of:(int64_t)total;
- (void)_load:(FURLLoad *)load finishedWithError:(NSError *)error;
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
static unsigned long events;              /* client messages sent, so pollers can say they did something */

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
static BOOL engine_active(void *ctx) { return [loads count] > 0; }
static int io_pending(void) { return [loads count] > 0; }

/* Waits for the network for at most timeout_ms (-1: as long as it takes),
 * then lets libcurl do what is ready. */
static void engine_wait(int timeout_ms)
{
    struct pollfd fds[64];
    int ms = timeout_ms;
    int n = engine_prepare(NULL, &ms, fds, 64);
    poll(fds, n, ms);
    engine_dispatch(NULL, fds, n);
}

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
    loads = [[NSMutableArray alloc] init];
    FRunLoopAddPoller(engine_prepare, engine_dispatch, engine_active, NULL);
    ferry_dispatch_set_io(io_pending, engine_wait);
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
    if (!agent) {
        NSBundle *b = [NSBundle mainBundle];
        NSString *name = [b objectForInfoDictionaryKey:@"CFBundleName"] ?: [[NSProcessInfo processInfo] processName];
        NSString *version = [b objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";
        agent = [[NSString alloc] initWithFormat:@"%@/%@ Ferry (freemac)", name ?: @"Ferry", version];
    }
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

/* Starts a transfer for a request. Returns nil, with *error set, when the
 * request can't be sent at all (an unsupported or bad URL, or no libcurl);
 * the caller tells its program later, as a Mac does. extra holds the
 * session's own header fields; idle is how long the transfer may wait for
 * data before it times out, total how long it may take in all (0: no
 * limit). body, when not nil, replaces the request's body. */
static FURLLoad *start_load(NSURLRequest *request, NSDictionary *extra, NSTimeInterval idle, NSTimeInterval total,
                            NSData *body, id<FURLLoadClient> client, NSError **error)
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
    C.easy_setopt(e, CURLOPT_URL, [[url absoluteString] UTF8String]);
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
    C.easy_setopt(e, CURLOPT_FOLLOWLOCATION, 1L);
    C.easy_setopt(e, CURLOPT_MAXREDIRS, 16L);
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
    return l;
}

static void cancel_load(FURLLoad *l)
{
    if (!l || l->done)
        return;
    l->cancelled = YES;
    [[l retain] autorelease];
    unload(l);
}

static void pause_load(FURLLoad *l, BOOL pause)
{
    if (!l || l->done || l->paused == pause)
        return;
    l->paused = pause;
    l->active_at = now();
    C.easy_pause(l->easy, pause ? CURLPAUSE_ALL : CURLPAUSE_CONT);
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

static void run_until_done(FURLLoad *l)
{
    [l retain];
    while (!l->done)
        engine_wait(-1);
    [l release];
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
- (void)_load:(FURLLoad *)load receivedResponse:(NSURLResponse *)r { response = [r retain]; }
- (void)_load:(FURLLoad *)load receivedBytes:(const void *)bytes length:(size_t)length
{
    [data appendBytes:bytes length:length];
}
- (void)_load:(FURLLoad *)load sent:(int64_t)sent of:(int64_t)total {}
- (void)_load:(FURLLoad *)load finishedWithError:(NSError *)e
{
    error = [e retain];
    done = YES;
    if (then)
        then(self);
}
@end

/* Loads a URL and waits for it: the body, or nil with *error. */
static NSData *load_and_wait(NSURLRequest *request, NSURLResponse **response, NSError **error)
{
    FURLGather *g = [[[FURLGather alloc] init] autorelease];
    NSError *e = nil;
    FURLLoad *l = start_load(request, nil, [request timeoutInterval], 0, nil, g, &e);
    if (l)
        run_until_done(l);
    else
        g->error = [e retain];
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
}
@end

@implementation NSURLSessionConfiguration
+ (NSURLSessionConfiguration *)defaultSessionConfiguration { return [[[self alloc] init] autorelease]; }
+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration { return [[[self alloc] init] autorelease]; }
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
    return self;
}
- (void)dealloc
{
    [_identifier release];
    [_container release];
    [_headers release];
    [_proxy release];
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
    return c;
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

@interface NSURLSessionTask () <FURLLoadClient> {
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
    FURLLoad *_load;
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
    [_load release];
    [_held release];
    [_path release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)taskIdentifier { return _id; }
- (NSURLRequest *)originalRequest { return _original; }
- (NSURLRequest *)currentRequest { return _original; }
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
    if (_ended || _state == NSURLSessionTaskStateCanceling || _state == NSURLSessionTaskStateCompleted)
        return;
    if (_started) {
        if (_state == NSURLSessionTaskStateSuspended) {
            _state = NSURLSessionTaskStateRunning;
            pause_load(_load, NO);
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
    NSError *e = nil;
    _load = [start_load(_original, c->_headers, idle, c->_resourceTimeout, _upload, self, &e) retain];
    if (!_load)
        [self _endWithError:e];
}
- (void)suspend
{
    if (_state != NSURLSessionTaskStateRunning)
        return;
    _state = NSURLSessionTaskStateSuspended;
    pause_load(_load, YES);
}
- (void)cancel
{
    if (_ended || _state == NSURLSessionTaskStateCanceling || _state == NSURLSessionTaskStateCompleted)
        return;
    _state = NSURLSessionTaskStateCanceling;
    cancel_load(_load);
    _awaiting = NO;
    [_held removeAllObjects];
    [self _endWithError:url_error(NSURLErrorCancelled, [_original URL], nil)];
}

/* ---- what the transfer says */

- (void)_load:(FURLLoad *)load receivedResponse:(NSURLResponse *)response
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
            if (answered)
                return;
            answered = YES;
            [self _answered:disposition];
          }];
    }];
}
- (void)_answered:(NSURLSessionResponseDisposition)disposition
{
    if (!_awaiting)
        return;
    _awaiting = NO;
    if (disposition == NSURLSessionResponseCancel) {
        [_held removeAllObjects];
        _ended = NO;
        _state = NSURLSessionTaskStateRunning;
        [self cancel];
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
- (void)_load:(FURLLoad *)load receivedBytes:(const void *)bytes length:(size_t)length
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
- (void)_load:(FURLLoad *)load sent:(int64_t)sent of:(int64_t)total
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
- (void)_load:(FURLLoad *)load finishedWithError:(NSError *)error
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
    [_load release];
    _load = nil;
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
      _state = NSURLSessionTaskStateCompleted;
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
    if (!shared) {
        shared = [[NSURLSession alloc] _initWithConfiguration:nil delegate:nil queue:nil];
        shared->_shared = YES;
    }
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
    if (!live_sessions)
        live_sessions = [[NSMutableArray alloc] init];
    [live_sessions addObject:s];
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
        t->_started = YES;
        t->_state = NSURLSessionTaskStateRunning;
        [t _endWithError:url_error(NSURLErrorFileDoesNotExist, fileURL, nil)];
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
    for (NSURLSessionTask *t in _tasks)
        if (!t->_ended)
            [open addObject:t];
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
      [live_sessions removeObjectIdenticalTo:self];
    }];
}
- (void)_taskEnded:(NSURLSessionTask *)task
{
    [[task retain] autorelease];
    [_tasks removeObjectIdenticalTo:task];
    [self _checkInvalid];
}
- (void)finishTasksAndInvalidate
{
    if (_shared || _invalid)
        return;
    _invalid = YES;
    [self _checkInvalid];
}
- (void)invalidateAndCancel
{
    if (_shared || _invalid)
        return;
    _invalid = YES;
    NSArray *now_open = [[_tasks copy] autorelease];
    for (NSURLSessionTask *t in now_open)
        [t cancel];
    [self _checkInvalid];
}
@end

/* ---- NSURLConnection ------------------------------------------------------------------------ */

@interface NSURLConnection () <FURLLoadClient> {
    NSURLRequest *_request;
    id _delegate;
    id _opqueue;
    FURLLoad *_load;
    BOOL _started, _over;
}
@end

@implementation NSURLConnection
+ (BOOL)canHandleRequest:(NSURLRequest *)request
{
    NSString *scheme = [[[request URL] scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"file"];
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
    [_load release];
    [super dealloc];
}
- (NSURLRequest *)originalRequest { return _request; }
- (NSURLRequest *)currentRequest { return _request; }
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
- (void)start
{
    if (_started)
        return;
    _started = YES;
    NSError *e = nil;
    _load = [start_load(_request, nil, [_request timeoutInterval], 0, nil, self, &e) retain];
    if (!_load)
        [self _load:nil finishedWithError:e];
}
- (void)cancel
{
    if (_over)
        return;
    _over = YES;
    cancel_load(_load);
    [_delegate autorelease];
    _delegate = nil;
}
- (void)_load:(FURLLoad *)load receivedResponse:(NSURLResponse *)response
{
    id d = _delegate;
    if ([d respondsToSelector:@selector(connection:didReceiveResponse:)])
        [self _tell:^{
          if (!_over)
              [d connection:self didReceiveResponse:response];
        }];
}
- (void)_load:(FURLLoad *)load receivedBytes:(const void *)bytes length:(size_t)length
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
- (void)_load:(FURLLoad *)load sent:(int64_t)sent of:(int64_t)total
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
- (void)_load:(FURLLoad *)load finishedWithError:(NSError *)error
{
    id d = [_delegate retain];
    [self _tell:^{
      if (!_over) {
          _over = YES;
          if (error) {
              if ([d respondsToSelector:@selector(connection:didFailWithError:)])
                  [d connection:self didFailWithError:error];
          } else if ([d respondsToSelector:@selector(connectionDidFinishLoading:)])
              [d connectionDidFinishLoading:self];
          [_delegate release];
          _delegate = nil;
      }
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
    NSError *e = nil;
    if (!start_load(request, nil, [request timeoutInterval], 0, nil, g, &e)) {
        [g retain];
        dispatch_async(dispatch_get_main_queue(), ^{
          [g _load:nil finishedWithError:e];
          [g release];
        });
    }
}
@end

/* ---- reading URLs into data and strings ---------------------------------------------------- */

static BOOL is_web(NSURL *url)
{
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

/* For dataWithContentsOfURL: and the like: the body of an http or https
 * URL (whatever the status), or nil with a Cocoa error that holds the URL
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
        [info setObject:[NSString stringWithFormat:@"The file “%@” couldn’t be opened.",
                                                   [name length] && ![name isEqualToString:@"/"] ? name : [url host]]
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
