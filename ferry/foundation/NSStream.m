/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSStream, NSInputStream and NSOutputStream, which are also CFReadStream
 * and CFWriteStream (one object, as on a Mac), and the socket streams of
 * CFNetwork, served from Foundation's file. Our own code, written from
 * Apple's public API documentation (NSStream, CFReadStream, CFWriteStream,
 * CFStream Socket Additions, the Stream Programming Guide).
 *
 * Streams on data, memory, a buffer, a file, a bound pair (a socket pair)
 * and a TCP connection to a host or a socket the program has. A stream
 * scheduled in a run loop (or given a dispatch queue) tells its delegate
 * and its CF client what happens, on that loop or queue: open completed,
 * bytes available (once for each read), space available (once for each
 * write), the end, an error. Unscheduled, reads and writes block.
 *
 * Connecting (the host looked up, the connection made, TLS) happens on a
 * dispatch worker after open, so open returns at once. TLS
 * (kCFStreamPropertySSLSettings, or NSStreamSocketSecurityLevelKey) is
 * this system's OpenSSL (libssl) through Ferry's crypto lookup, as the
 * Security framework's is; the server's certificates become a SecTrust of
 * Ferry's Security framework (loaded the first time, as Security links
 * Foundation and not the other way round), evaluated against this
 * system's certificate authorities unless the settings say not to
 * validate the chain. Settings take effect only when given before open. */
#import "FInternal.h"
#include <CoreFoundation/CFStream.h>
#include <CFNetwork/CFNetwork.h>
#include <Foundation/NSStream.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <dlfcn.h>
#include <pthread.h>

/* ---- names ----------------------------------------------------------------------------- */

#define CFKEY(name) const CFStringRef name = (CFStringRef)@ #name;
CFKEY(kCFStreamPropertyDataWritten)
CFKEY(kCFStreamPropertyAppendToFile)
CFKEY(kCFStreamPropertyFileCurrentOffset)
CFKEY(kCFStreamPropertySocketNativeHandle)
CFKEY(kCFStreamPropertySocketRemoteHostName)
CFKEY(kCFStreamPropertySocketRemotePortNumber)
CFKEY(kCFStreamPropertyShouldCloseNativeSocket)
CFKEY(kCFStreamPropertySocketSecurityLevel)
CFKEY(kCFStreamSocketSecurityLevelNone)
CFKEY(kCFStreamSocketSecurityLevelSSLv2)
CFKEY(kCFStreamSocketSecurityLevelSSLv3)
CFKEY(kCFStreamSocketSecurityLevelTLSv1)
CFKEY(kCFStreamSocketSecurityLevelNegotiatedSSL)
CFKEY(kCFStreamPropertySSLSettings)
CFKEY(kCFStreamSSLLevel)
CFKEY(kCFStreamSSLPeerName)
CFKEY(kCFStreamSSLValidatesCertificateChain)
CFKEY(kCFStreamSSLCertificates)
CFKEY(kCFStreamSSLIsServer)
CFKEY(kCFStreamPropertySSLPeerTrust)
CFKEY(kCFStreamPropertySSLPeerCertificates)
CFKEY(kCFErrorDomainCFNetwork)
const SInt32 kCFStreamErrorDomainSSL = 3;
const SInt32 kCFStreamErrorDomainNetDB = 12;

/* The Foundation names are the same strings, so either works with either kind of stream. */
NSString *const NSStreamDataWrittenToMemoryStreamKey = @"kCFStreamPropertyDataWritten";
NSString *const NSStreamFileCurrentOffsetKey = @"kCFStreamPropertyFileCurrentOffset";
NSString *const NSStreamSocketSecurityLevelKey = @"kCFStreamPropertySocketSecurityLevel";
NSString *const NSStreamSocketSecurityLevelNone = @"kCFStreamSocketSecurityLevelNone";
NSString *const NSStreamSocketSecurityLevelSSLv2 = @"kCFStreamSocketSecurityLevelSSLv2";
NSString *const NSStreamSocketSecurityLevelSSLv3 = @"kCFStreamSocketSecurityLevelSSLv3";
NSString *const NSStreamSocketSecurityLevelTLSv1 = @"kCFStreamSocketSecurityLevelTLSv1";
NSString *const NSStreamSocketSecurityLevelNegotiatedSSL = @"kCFStreamSocketSecurityLevelNegotiatedSSL";
NSString *const NSStreamSOCKSProxyConfigurationKey = @"kCFStreamPropertySOCKSProxy";
NSString *const NSStreamNetworkServiceType = @"kCFStreamNetworkServiceType";
NSString *const NSStreamSocketSSLErrorDomain = @"NSStreamSocketSSLErrorDomain";
NSString *const NSStreamSOCKSErrorDomain = @"NSStreamSOCKSErrorDomain";

F_EXPORT CFNullRef ferry_null __asm__("_kCFNull");
CFNullRef ferry_null;
__attribute__((constructor)) static void null_init(void) { ferry_null = (CFNullRef)[NSNull null]; }

enum {
    errSSLClosedAbort = -9806,        /* the handshake failed */
    errSSLXCertChainInvalid = -9807,  /* the server's certificates aren't trusted */
};
/* errSecParam (Security.h, which Foundation brings in): asked for what isn't offered (a TLS server) */

/* ---- the common part: status, delegate, CF client, run loops and queues ------------------ */

@interface NSStream () {
@public
    NSStreamStatus _status;
    NSError *_error;
    CFStreamError _cfError;
    id _delegate;
    NSMutableArray *_places; /* [run loop, mode] */
    dispatch_queue_t _queue;
    CFOptionFlags _clientEvents;
    void (*_clientCB)(id stream, CFStreamEventType type, void *info);
    CFStreamClientContext _client;
    NSMutableDictionary *_props;
    BOOL _openPosted, _endPosted, _errorPosted;
    BOOL _signalled; /* bytes or space announced, and not read or written since */
}
- (void)_doOpen;
- (void)_doClose;
- (NSStreamEvent)_readiness;
- (void)_scheduleChanged;
- (void)_didOpen;
- (void)_kick;
- (void)_post:(NSStreamEvent)ev;
- (void)_consumed;
- (void)_atEnd;
- (void)_setQueue:(dispatch_queue_t)q;
- (BOOL)_setClient:(CFOptionFlags)events callback:(void *)cb context:(CFStreamClientContext *)ctx;
@end
/* the socket streams': their descriptor is ready */
@protocol FReady <NSObject>
- (void)_ready;
@end

static BOOL is_live(NSStreamStatus s)
{
    return s == NSStreamStatusOpen || s == NSStreamStatusReading || s == NSStreamStatusWriting;
}

static void set_error(NSStream *s, NSError *e, CFIndex domain, SInt32 code)
{
    @synchronized(s) {
        s->_status = NSStreamStatusError;
        if (!s->_error)
            s->_error = [e retain];
        s->_cfError.domain = domain;
        s->_cfError.error = code;
    }
}

/* An error as a number: positive a POSIX errno, negative an OSStatus of TLS. */
static void fail(NSStream *s, int err)
{
    if (err > 0)
        set_error(s, [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil], kCFStreamErrorDomainPOSIX, err);
    else
        set_error(s, [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil], kCFStreamErrorDomainSSL,
                  err);
    [s _post:NSStreamEventErrorOccurred];
}

@implementation NSStream
- (instancetype)init
{
    self = [super init];
    if (self) {
        _places = [[NSMutableArray alloc] init];
        _props = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)_dropPlaces
{
    NSArray *was;
    @synchronized(self) {
        was = [[_places copy] autorelease];
        [_places removeAllObjects];
    }
    NSMutableArray *seen = [NSMutableArray array];
    for (NSArray *p in was) {
        NSRunLoop *loop = [p objectAtIndex:0];
        if ([seen indexOfObjectIdenticalTo:loop] == NSNotFound) {
            [seen addObject:loop];
            [loop _removeKeepAlive];
        }
    }
}
- (void)dealloc
{
    [self _dropPlaces];
    if (_client.release && _client.info)
        _client.release(_client.info);
    if (_queue)
        dispatch_release(_queue);
    [_places release];
    [_props release];
    [_error release];
    [super dealloc];
}
- (id<NSStreamDelegate>)delegate { return _delegate ?: (id)self; }
- (void)setDelegate:(id<NSStreamDelegate>)delegate { _delegate = delegate == (id)self ? nil : delegate; }
- (NSStreamStatus)streamStatus
{
    @synchronized(self) {
        return _status;
    }
}
- (NSError *)streamError
{
    @synchronized(self) {
        return [[_error retain] autorelease];
    }
}
- (id)propertyForKey:(NSStreamPropertyKey)key
{
    @synchronized(self) {
        return [[[_props objectForKey:key] retain] autorelease];
    }
}
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
    if (!key)
        return NO;
    @synchronized(self) {
        if (property)
            [_props setObject:property forKey:key];
        else
            [_props removeObjectForKey:key];
    }
    return YES;
}

- (void)open
{
    @synchronized(self) {
        if (_status != NSStreamStatusNotOpen)
            return;
        _status = NSStreamStatusOpening;
    }
    [self _doOpen];
}
/* The plain streams open at once. */
- (void)_doOpen
{
    @synchronized(self) {
        if (_status == NSStreamStatusOpening)
            _status = NSStreamStatusOpen;
    }
    [self _didOpen];
}
- (void)_didOpen
{
    NSStreamStatus st = [self streamStatus];
    if (st == NSStreamStatusError)
        [self _post:NSStreamEventErrorOccurred];
    else if (st != NSStreamStatusOpening && st != NSStreamStatusNotOpen)
        [self _post:NSStreamEventOpenCompleted];
    [self _kick];
}
- (void)close
{
    @synchronized(self) {
        if (_status == NSStreamStatusClosed)
            return;
        _status = NSStreamStatusClosed;
    }
    [self _doClose];
    [self _dropPlaces];
}
- (void)_doClose {}

- (BOOL)_scheduled
{
    @synchronized(self) {
        return _queue || [_places count];
    }
}
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode
{
    if (!loop)
        return;
    NSArray *pair = [NSArray arrayWithObjects:loop, mode ?: @"", nil];
    BOOL first = YES;
    @synchronized(self) {
        if (_status == NSStreamStatusClosed || [_places containsObject:pair])
            return;
        for (NSArray *p in _places)
            if ([p objectAtIndex:0] == loop)
                first = NO;
        [_places addObject:pair];
    }
    if (first)
        [loop _addKeepAlive];
    [self _scheduleChanged];
}
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode
{
    if (!loop)
        return;
    NSArray *pair = [NSArray arrayWithObjects:loop, mode ?: @"", nil];
    BOOL last = YES;
    [loop retain];
    @synchronized(self) {
        NSUInteger i = [_places indexOfObject:pair];
        if (i == NSNotFound) {
            [loop release];
            return;
        }
        [_places removeObjectAtIndex:i];
        for (NSArray *p in _places)
            if ([p objectAtIndex:0] == loop)
                last = NO;
    }
    if (last)
        [loop _removeKeepAlive];
    [self _scheduleChanged];
    [loop release];
}
- (void)_setQueue:(dispatch_queue_t)q
{
    @synchronized(self) {
        if (q)
            dispatch_retain(q);
        if (_queue)
            dispatch_release(_queue);
        _queue = q;
    }
    [self _scheduleChanged];
}
/* Newly scheduled: what it missed while not (an open that completed), then what is ready now. */
- (void)_scheduleChanged
{
    NSStreamStatus st = [self streamStatus];
    if (st == NSStreamStatusError)
        [self _post:NSStreamEventErrorOccurred];
    else if (st != NSStreamStatusNotOpen && st != NSStreamStatusOpening && st != NSStreamStatusClosed)
        [self _post:NSStreamEventOpenCompleted];
    @synchronized(self) {
        _signalled = NO;
    }
    [self _kick];
}
- (NSStreamEvent)_readiness { return NSStreamEventNone; }
/* Announces what is ready, if nothing is announced and still unanswered. */
- (void)_kick
{
    @synchronized(self) {
        if (!(_queue || [_places count]) || _signalled || !is_live(_status))
            return;
    }
    NSStreamEvent ev = [self _readiness];
    if (ev == NSStreamEventHasBytesAvailable || ev == NSStreamEventHasSpaceAvailable) {
        @synchronized(self) {
            if (_signalled)
                return;
            _signalled = YES;
        }
    }
    if (ev)
        [self _post:ev];
}
/* After a read or a write: the next announcement may come. */
- (void)_consumed
{
    @synchronized(self) {
        _signalled = NO;
    }
    [self _kick];
}
- (void)_atEnd
{
    @synchronized(self) {
        if (is_live(_status))
            _status = NSStreamStatusAtEnd;
    }
    [self _post:NSStreamEventEndEncountered];
}
- (void)_post:(NSStreamEvent)ev
{
    NSRunLoop *loop = nil;
    dispatch_queue_t q;
    @synchronized(self) {
        q = _queue;
        if (!q && [_places count])
            loop = [[_places objectAtIndex:0] objectAtIndex:0];
        if (!q && !loop)
            return; /* an unscheduled stream sends nothing */
        BOOL *once = ev == NSStreamEventOpenCompleted ? &_openPosted
                     : ev == NSStreamEventEndEncountered ? &_endPosted
                     : ev == NSStreamEventErrorOccurred ? &_errorPosted
                                                         : NULL;
        if (once) {
            if (*once)
                return;
            *once = YES;
        }
    }
    void (^deliver)(void) = ^{
      [self _deliver:ev];
    };
    if (q)
        dispatch_async(q, deliver);
    else
        [loop performBlock:deliver];
}
- (void)_deliver:(NSStreamEvent)ev
{
    id d;
    void (*cb)(id, CFStreamEventType, void *);
    void *info;
    @synchronized(self) {
        if (_status == NSStreamStatusClosed || _status == NSStreamStatusNotOpen || !(_queue || [_places count]))
            return;
        d = [[self delegate] retain];
        cb = (_clientEvents & ev) ? _clientCB : NULL;
        info = _client.info;
    }
    [self retain];
    if ([d respondsToSelector:@selector(stream:handleEvent:)])
        [d stream:self handleEvent:ev];
    if (cb)
        cb(self, (CFStreamEventType)ev, info);
    [self release];
    [d release];
}
- (BOOL)_setClient:(CFOptionFlags)events callback:(void *)cb context:(CFStreamClientContext *)ctx
{
    void *old;
    void (*oldRelease)(void *);
    @synchronized(self) {
        old = _client.info;
        oldRelease = _client.release;
        memset(&_client, 0, sizeof _client);
        _clientCB = cb;
        _clientEvents = cb ? events : 0;
        if (cb && ctx) {
            _client = *ctx;
            if (ctx->retain && ctx->info)
                _client.info = ctx->retain(ctx->info);
        }
    }
    if (oldRelease && old)
        oldRelease(old);
    return YES;
}
@end

/* ---- streams on data, memory, a buffer and files ------------------------------------------ */

@implementation NSInputStream
- (instancetype)initWithData:(NSData *)data
{
    [self release];
    return (id)[[NSClassFromString(@"FDataInputStream") alloc] initWithData:data];
}
- (instancetype)initWithFileAtPath:(NSString *)path
{
    [self release];
    return (id)[[NSClassFromString(@"FFileInputStream") alloc] initWithFileAtPath:path];
}
- (instancetype)initWithURL:(NSURL *)url
{
    if (![url isFileURL]) {
        [self release];
        return nil;
    }
    return [self initWithFileAtPath:[url path]];
}
+ (instancetype)inputStreamWithData:(NSData *)data { return [[[self alloc] initWithData:data] autorelease]; }
+ (instancetype)inputStreamWithFileAtPath:(NSString *)path
{
    return [[[self alloc] initWithFileAtPath:path] autorelease];
}
+ (instancetype)inputStreamWithURL:(NSURL *)url { return [[[self alloc] initWithURL:url] autorelease]; }
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len { return -1; }
- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len { return NO; }
- (BOOL)hasBytesAvailable { return NO; }
@end

@implementation NSOutputStream
- (instancetype)initToMemory
{
    [self release];
    return (id)[[NSClassFromString(@"FMemoryOutputStream") alloc] initToMemory];
}
- (instancetype)initToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity
{
    [self release];
    return (id)[[NSClassFromString(@"FBufferOutputStream") alloc] initToBuffer:buffer capacity:capacity];
}
- (instancetype)initToFileAtPath:(NSString *)path append:(BOOL)shouldAppend
{
    [self release];
    return (id)[[NSClassFromString(@"FFileOutputStream") alloc] initToFileAtPath:path append:shouldAppend];
}
- (instancetype)initWithURL:(NSURL *)url append:(BOOL)shouldAppend
{
    if (![url isFileURL]) {
        [self release];
        return nil;
    }
    return [self initToFileAtPath:[url path] append:shouldAppend];
}
+ (instancetype)outputStreamToMemory { return [[[self alloc] initToMemory] autorelease]; }
+ (instancetype)outputStreamToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity
{
    return [[[self alloc] initToBuffer:buffer capacity:capacity] autorelease];
}
+ (instancetype)outputStreamToFileAtPath:(NSString *)path append:(BOOL)shouldAppend
{
    return [[[self alloc] initToFileAtPath:path append:shouldAppend] autorelease];
}
+ (instancetype)outputStreamWithURL:(NSURL *)url append:(BOOL)shouldAppend
{
    return [[[self alloc] initWithURL:url append:shouldAppend] autorelease];
}
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len { return -1; }
- (BOOL)hasSpaceAvailable { return NO; }
@end

@interface FDataInputStream : NSInputStream {
    NSData *_data;
    NSUInteger _pos;
}
@end
@implementation FDataInputStream
- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (self)
        _data = [data copy] ?: [[NSData alloc] init];
    return self;
}
- (void)dealloc
{
    [_data release];
    [super dealloc];
}
- (NSStreamEvent)_readiness
{
    @synchronized(self) {
        if (_pos < [_data length])
            return NSStreamEventHasBytesAvailable;
        if (is_live(_status))
            _status = NSStreamStatusAtEnd;
    }
    return NSStreamEventEndEncountered;
}
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSUInteger n;
    @synchronized(self) {
        if (_status == NSStreamStatusAtEnd)
            return 0;
        if (!is_live(_status))
            return -1;
        n = MIN(len, [_data length] - _pos);
        memcpy(buffer, (const char *)[_data bytes] + _pos, n);
        _pos += n;
    }
    if (n == 0)
        [self _atEnd];
    else
        [self _consumed];
    return (NSInteger)n;
}
- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
    @synchronized(self) {
        if (!is_live(_status))
            return NO;
        *buffer = (uint8_t *)[_data bytes] + _pos;
        *len = [_data length] - _pos;
    }
    return YES;
}
- (BOOL)_take:(NSUInteger)n
{
    @synchronized(self) {
        _pos += MIN(n, [_data length] - _pos);
    }
    [self _consumed];
    return YES;
}
- (BOOL)hasBytesAvailable
{
    @synchronized(self) {
        return is_live(_status) && _pos < [_data length];
    }
}
@end

/* A file, read or written through its descriptor. */
static int open_file(NSStream *s, NSString *path, int flags)
{
    int fd = path ? open([path fileSystemRepresentation], flags | O_CLOEXEC, 0644) : -1;
    if (fd < 0)
        fail(s, path ? errno : ENOENT);
    return fd;
}

@interface FFileInputStream : NSInputStream {
    NSString *_path;
    int _fd;
}
@end
@implementation FFileInputStream
- (instancetype)initWithFileAtPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _path = [path copy];
        _fd = -1;
    }
    return self;
}
- (void)dealloc
{
    if (_fd >= 0)
        close(_fd);
    [_path release];
    [super dealloc];
}
- (void)_doOpen
{
    _fd = open_file(self, _path, O_RDONLY);
    NSNumber *start = [super propertyForKey:(NSString *)kCFStreamPropertyFileCurrentOffset];
    if (_fd >= 0 && start)
        lseek(_fd, (off_t)[start longLongValue], SEEK_SET);
    [super _doOpen];
}
- (void)_doClose
{
    if (_fd >= 0)
        close(_fd);
    _fd = -1;
}
- (NSStreamEvent)_readiness
{
    struct stat st;
    off_t at = lseek(_fd, 0, SEEK_CUR);
    if (fstat(_fd, &st) == 0 && S_ISREG(st.st_mode) && at >= st.st_size) {
        @synchronized(self) {
            if (is_live(_status))
                _status = NSStreamStatusAtEnd;
        }
        return NSStreamEventEndEncountered;
    }
    return NSStreamEventHasBytesAvailable;
}
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSStreamStatus st = [self streamStatus];
    if (st == NSStreamStatusAtEnd)
        return 0;
    if (!is_live(st))
        return -1;
    ssize_t n;
    do
        n = read(_fd, buffer, len);
    while (n < 0 && errno == EINTR);
    if (n < 0) {
        fail(self, errno);
        return -1;
    }
    if (n == 0 && len)
        [self _atEnd];
    else
        [self _consumed];
    return n;
}
- (BOOL)hasBytesAvailable { return is_live([self streamStatus]); }
- (id)propertyForKey:(NSStreamPropertyKey)key
{
    if ([key isEqual:(NSString *)kCFStreamPropertyFileCurrentOffset] && _fd >= 0)
        return [NSNumber numberWithLongLong:lseek(_fd, 0, SEEK_CUR)];
    return [super propertyForKey:key];
}
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
    if ([key isEqual:(NSString *)kCFStreamPropertyFileCurrentOffset] && _fd >= 0) {
        BOOL ok = lseek(_fd, (off_t)[property longLongValue], SEEK_SET) >= 0;
        [self _consumed];
        return ok;
    }
    return [super setProperty:property forKey:key];
}
@end

@interface FMemoryOutputStream : NSOutputStream {
    NSMutableData *_data;
}
@end
@implementation FMemoryOutputStream
- (instancetype)initToMemory
{
    self = [super init];
    if (self)
        _data = [[NSMutableData alloc] init];
    return self;
}
- (void)dealloc
{
    [_data release];
    [super dealloc];
}
- (NSStreamEvent)_readiness { return NSStreamEventHasSpaceAvailable; }
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    @synchronized(self) {
        if (!is_live(_status))
            return -1;
        [_data appendBytes:buffer length:len];
    }
    [self _consumed];
    return (NSInteger)len;
}
- (BOOL)hasSpaceAvailable { return is_live([self streamStatus]); }
- (id)propertyForKey:(NSStreamPropertyKey)key
{
    if ([key isEqual:(NSString *)kCFStreamPropertyDataWritten]) {
        @synchronized(self) {
            return [[_data copy] autorelease];
        }
    }
    return [super propertyForKey:key];
}
@end

@interface FBufferOutputStream : NSOutputStream {
    uint8_t *_buffer;
    NSUInteger _capacity, _used;
}
@end
@implementation FBufferOutputStream
- (instancetype)initToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity
{
    self = [super init];
    if (self) {
        _buffer = buffer;
        _capacity = capacity;
    }
    return self;
}
- (NSStreamEvent)_readiness
{
    @synchronized(self) {
        if (_used < _capacity)
            return NSStreamEventHasSpaceAvailable;
        if (is_live(_status))
            _status = NSStreamStatusAtEnd;
    }
    return NSStreamEventEndEncountered;
}
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSUInteger n;
    @synchronized(self) {
        if (_status == NSStreamStatusAtEnd)
            return 0;
        if (!is_live(_status))
            return -1;
        n = MIN(len, _capacity - _used);
        memcpy(_buffer + _used, buffer, n);
        _used += n;
    }
    if (n == 0 && len) /* full: the end of a fixed-length stream */
        [self _atEnd];
    else
        [self _consumed];
    return (NSInteger)n;
}
- (BOOL)hasSpaceAvailable
{
    @synchronized(self) {
        return is_live(_status) && _used < _capacity;
    }
}
@end

@interface FFileOutputStream : NSOutputStream {
    NSString *_path;
    BOOL _append;
    int _fd;
}
@end
@implementation FFileOutputStream
- (instancetype)initToFileAtPath:(NSString *)path append:(BOOL)shouldAppend
{
    self = [super init];
    if (self) {
        _path = [path copy];
        _append = shouldAppend;
        _fd = -1;
    }
    return self;
}
- (void)dealloc
{
    if (_fd >= 0)
        close(_fd);
    [_path release];
    [super dealloc];
}
- (void)_doOpen
{
    NSNumber *append = [self propertyForKey:(NSString *)kCFStreamPropertyAppendToFile];
    BOOL a = append ? [append boolValue] : _append;
    _fd = open_file(self, _path, O_WRONLY | O_CREAT | (a ? O_APPEND : O_TRUNC));
    [super _doOpen];
}
- (void)_doClose
{
    if (_fd >= 0)
        close(_fd);
    _fd = -1;
}
- (NSStreamEvent)_readiness { return NSStreamEventHasSpaceAvailable; }
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    if (!is_live([self streamStatus]))
        return -1;
    ssize_t n;
    do
        n = write(_fd, buffer, len);
    while (n < 0 && errno == EINTR);
    if (n < 0) {
        fail(self, errno);
        return -1;
    }
    [self _consumed];
    return n;
}
- (BOOL)hasSpaceAvailable { return is_live([self streamStatus]); }
- (id)propertyForKey:(NSStreamPropertyKey)key
{
    if ([key isEqual:(NSString *)kCFStreamPropertyFileCurrentOffset] && _fd >= 0)
        return [NSNumber numberWithLongLong:lseek(_fd, 0, SEEK_CUR)];
    return [super propertyForKey:key];
}
@end

/* ---- TLS: this system's libssl, from OpenSSL's published API documentation ------------------- */

static struct {
    const void *(*TLS_client_method)(void);
    void *(*SSL_CTX_new)(const void *);
    void (*SSL_CTX_free)(void *);
    void *(*SSL_new)(void *);
    void (*SSL_free)(void *);
    void (*SSL_set_bio)(void *, void *, void *);
    long (*SSL_ctrl)(void *, int, long, void *);
    int (*SSL_connect)(void *);
    int (*SSL_read)(void *, void *, int);
    int (*SSL_write)(void *, const void *, int);
    int (*SSL_get_error)(const void *, int);
    int (*SSL_shutdown)(void *);
    int (*SSL_pending)(const void *);
    void *(*SSL_get_peer_cert_chain)(const void *);
    int (*i2d_X509)(void *, unsigned char **);
    int (*OPENSSL_sk_num)(const void *);
    void *(*OPENSSL_sk_value)(const void *, int);
    int (*BIO_get_new_index)(void);
    void *(*BIO_meth_new)(int, const char *);
    int (*BIO_meth_set_write)(void *, int (*)(void *, const char *, int));
    int (*BIO_meth_set_read)(void *, int (*)(void *, char *, int));
    int (*BIO_meth_set_ctrl)(void *, long (*)(void *, int, long, void *));
    void *(*BIO_new)(const void *);
    void (*BIO_set_data)(void *, void *);
    void *(*BIO_get_data)(void *);
    void (*BIO_set_init)(void *, int);
    void (*BIO_set_flags)(void *, int);
    void (*BIO_clear_flags)(void *, int);
    void (*ERR_clear_error)(void);
} T;
static void *(*ssl_ctx_set_options)(void *, unsigned long); /* returns the options; only its effect matters */
static void *bio_method;

extern void *ferry_crypto_symbol(const char *name);

enum {
    SSL_ERROR_SSL = 1,
    SSL_ERROR_WANT_READ = 2,
    SSL_ERROR_WANT_WRITE = 3,
    SSL_ERROR_SYSCALL = 5,
    SSL_ERROR_ZERO_RETURN = 6,
    SSL_CTRL_SET_TLSEXT_HOSTNAME = 55,
    TLSEXT_NAMETYPE_host_name = 0,
    BIO_TYPE_SOURCE_SINK = 0x0400,
    BIO_FLAGS_READ = 0x01,
    BIO_FLAGS_WRITE = 0x02,
    BIO_FLAGS_RWS = 0x07,
    BIO_FLAGS_SHOULD_RETRY = 0x08,
    BIO_CTRL_FLUSH = 11,
};
#define SSL_OP_IGNORE_UNEXPECTED_EOF 0x80ul /* OpenSSL 3: a peer that closes without close_notify ends the stream */

/* OpenSSL reaches the socket through these, with the program's own send and
 * recv: the socket has SO_NOSIGPIPE, so a closed peer is an error and not
 * a SIGPIPE. */
static int bio_write(void *b, const char *in, int n)
{
    int fd = (int)(intptr_t)T.BIO_get_data(b);
    T.BIO_clear_flags(b, BIO_FLAGS_RWS | BIO_FLAGS_SHOULD_RETRY);
    ssize_t r = send(fd, in, (size_t)n, 0);
    if (r < 0 && (errno == EAGAIN || errno == EINTR))
        T.BIO_set_flags(b, BIO_FLAGS_WRITE | BIO_FLAGS_SHOULD_RETRY);
    return (int)r;
}
static int bio_read(void *b, char *out, int n)
{
    int fd = (int)(intptr_t)T.BIO_get_data(b);
    T.BIO_clear_flags(b, BIO_FLAGS_RWS | BIO_FLAGS_SHOULD_RETRY);
    ssize_t r = recv(fd, out, (size_t)n, 0);
    if (r < 0 && (errno == EAGAIN || errno == EINTR))
        T.BIO_set_flags(b, BIO_FLAGS_READ | BIO_FLAGS_SHOULD_RETRY);
    return (int)r;
}
static long bio_ctrl(void *b, int cmd, long num, void *ptr) { return cmd == BIO_CTRL_FLUSH; }

static BOOL tls_available(void)
{
    static int state; /* 0 not tried, 1 found, -1 missing */
    static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&m);
    if (!state) {
        state = 1;
#define GET(name) if (!(*(void **)&T.name = ferry_crypto_symbol(#name))) state = -1;
        GET(TLS_client_method) GET(SSL_CTX_new) GET(SSL_CTX_free) GET(SSL_new) GET(SSL_free) GET(SSL_set_bio)
        GET(SSL_ctrl) GET(SSL_connect) GET(SSL_read) GET(SSL_write) GET(SSL_get_error) GET(SSL_shutdown)
        GET(SSL_pending) GET(SSL_get_peer_cert_chain) GET(i2d_X509) GET(OPENSSL_sk_num) GET(OPENSSL_sk_value)
        GET(BIO_get_new_index) GET(BIO_meth_new) GET(BIO_meth_set_write) GET(BIO_meth_set_read)
        GET(BIO_meth_set_ctrl) GET(BIO_new) GET(BIO_set_data) GET(BIO_get_data) GET(BIO_set_init) GET(BIO_set_flags)
        GET(BIO_clear_flags) GET(ERR_clear_error)
#undef GET
        if (ferry_crypto_symbol("OPENSSL_version_major")) /* OpenSSL 3 */
            *(void **)&ssl_ctx_set_options = ferry_crypto_symbol("SSL_CTX_set_options");
        if (state > 0) {
            bio_method = T.BIO_meth_new(T.BIO_get_new_index() | BIO_TYPE_SOURCE_SINK, "ferry stream socket");
            if (!bio_method || !T.BIO_meth_set_write(bio_method, bio_write) ||
                !T.BIO_meth_set_read(bio_method, bio_read) || !T.BIO_meth_set_ctrl(bio_method, bio_ctrl))
                state = -1;
        }
        if (state < 0)
            FVerboseOnce(@"this system's OpenSSL (libssl) was not found: streams can't use TLS");
    }
    pthread_mutex_unlock(&m);
    return state > 0;
}

/* The Security framework's trust calls (Security links Foundation, so it is loaded when first needed). */
static struct {
    CFTypeRef (*SecCertificateCreateWithData)(CFAllocatorRef, CFDataRef);
    CFTypeRef (*SecPolicyCreateSSL)(Boolean, CFStringRef);
    int32_t (*SecTrustCreateWithCertificates)(CFTypeRef, CFTypeRef, CFTypeRef *);
    bool (*SecTrustEvaluateWithError)(CFTypeRef, CFErrorRef *);
} S;
static BOOL security_available(void)
{
    static int state;
    static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&m);
    if (!state) {
        void *h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        state = h ? 1 : -1;
#define GET(name) if (h && !(*(void **)&S.name = dlsym(h, #name))) state = -1;
        GET(SecCertificateCreateWithData) GET(SecPolicyCreateSSL) GET(SecTrustCreateWithCertificates)
        GET(SecTrustEvaluateWithError)
#undef GET
        if (state < 0)
            FVerboseOnce(@"the Security framework wasn't found: a TLS stream's server can't be trusted");
    }
    pthread_mutex_unlock(&m);
    return state > 0;
}

/* ---- the socket streams' shared connection ------------------------------------------------- */

@class FSocketInputStream, FSocketOutputStream;

@interface FSocketCore : NSObject {
@public
    pthread_mutex_t m;
    pthread_cond_t c;
    pthread_mutex_t sslLock;
    int fd;
    NSString *host;
    UInt32 port;
    int state; /* 0 not started, 1 connecting, 2 ready, 3 failed */
    BOOL closeNative, closed;
    int err;      /* the failure: errno, an OSStatus, or for a name lookup the EAI code with netdb set */
    BOOL netdb;
    NSDictionary *ssl_settings;
    NSString *level;
    void *ssl, *ctx;
    CFTypeRef trust;
    NSArray *peerCerts;
    FSocketInputStream *input; /* not retained: each stream retains this */
    FSocketOutputStream *output;
}
- (void)streamDone:(NSStream *)s;
@end

@interface FSocketInputStream : NSInputStream {
@public
    FSocketCore *_core;
    pthread_mutex_t _io;
    char _buf[16384];
    size_t _have, _used;
    NSRunLoop *_armedLoop;
    dispatch_source_t _dsrc;
    BOOL _dsrcOn;
}
- (void)_coreReady;
@end
@interface FSocketOutputStream : NSOutputStream {
@public
    FSocketCore *_core;
    NSRunLoop *_armedLoop;
    dispatch_source_t _dsrc;
    BOOL _dsrcOn;
}
- (void)_coreReady;
@end

static int wait_fd(int fd, short events)
{
    struct pollfd p = {fd, events, 0};
    int r;
    do
        r = poll(&p, 1, -1);
    while (r < 0 && errno == EINTR);
    return r;
}

static NSError *core_error(FSocketCore *core, CFStreamError *cf)
{
    if (core->netdb) {
        cf->domain = kCFStreamErrorDomainNetDB;
        cf->error = core->err;
        NSDictionary *info = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:core->err]
                                                         forKey:@"kCFGetAddrInfoFailureKey"];
        return [NSError errorWithDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFHostErrorUnknown userInfo:info];
    }
    if (core->err > 0) {
        cf->domain = kCFStreamErrorDomainPOSIX;
        cf->error = core->err;
        return [NSError errorWithDomain:NSPOSIXErrorDomain code:core->err userInfo:nil];
    }
    cf->domain = kCFStreamErrorDomainSSL;
    cf->error = core->err;
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:core->err userInfo:nil];
}

/* The TLS settings in force: nil for none. */
static NSDictionary *tls_wanted(FSocketCore *core)
{
    NSDictionary *s = core->ssl_settings;
    NSString *lv = [s objectForKey:(NSString *)kCFStreamSSLLevel] ?: core->level;
    if (!s && (!lv || [lv isEqual:(NSString *)kCFStreamSocketSecurityLevelNone]))
        return nil;
    if (s && [lv isEqual:(NSString *)kCFStreamSocketSecurityLevelNone])
        return nil;
    return s ?: [NSDictionary dictionary];
}

static BOOL is_address(NSString *name)
{
    unsigned char buf[16];
    const char *s = [name UTF8String];
    return inet_pton(AF_INET, s, buf) == 1 || inet_pton(AF_INET6, s, buf) == 1;
}

/* Runs the client's handshake on the connected socket; 0 or the OSStatus of the failure. */
static int tls_handshake(FSocketCore *core, NSDictionary *settings)
{
    if ([[settings objectForKey:(NSString *)kCFStreamSSLIsServer] boolValue]) {
        FVerboseOnce(@"a TLS server stream (kCFStreamSSLIsServer) isn't offered");
        return errSecParam;
    }
    if ([settings objectForKey:(NSString *)kCFStreamSSLCertificates])
        FVerboseOnce(@"kCFStreamSSLCertificates (a client certificate) is ignored");
    if (!tls_available())
        return errSSLClosedAbort;
    id peer = [settings objectForKey:(NSString *)kCFStreamSSLPeerName];
    NSString *name = [peer isKindOfClass:[NSString class]] ? peer : peer ? nil : core->host;
    id validates = [settings objectForKey:(NSString *)kCFStreamSSLValidatesCertificateChain];
    BOOL validate = validates ? [validates boolValue] : YES;

    core->ctx = T.SSL_CTX_new(T.TLS_client_method());
    if (!core->ctx)
        return errSSLClosedAbort;
    if (ssl_ctx_set_options)
        ssl_ctx_set_options(core->ctx, SSL_OP_IGNORE_UNEXPECTED_EOF);
    core->ssl = T.SSL_new(core->ctx);
    void *bio = core->ssl ? T.BIO_new(bio_method) : NULL;
    if (!bio)
        return errSSLClosedAbort;
    T.BIO_set_data(bio, (void *)(intptr_t)core->fd);
    T.BIO_set_init(bio, 1);
    T.SSL_set_bio(core->ssl, bio, bio);
    if (name && !is_address(name))
        T.SSL_ctrl(core->ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, (void *)[name UTF8String]);
    for (;;) {
        T.ERR_clear_error();
        int r = T.SSL_connect(core->ssl);
        if (r == 1)
            break;
        int e = T.SSL_get_error(core->ssl, r);
        if (e == SSL_ERROR_WANT_READ)
            wait_fd(core->fd, POLLIN);
        else if (e == SSL_ERROR_WANT_WRITE)
            wait_fd(core->fd, POLLOUT);
        else
            return errSSLClosedAbort;
    }
    /* the server's certificates, as a trust */
    void *chain = T.SSL_get_peer_cert_chain(core->ssl);
    NSMutableArray *ders = [NSMutableArray array];
    for (int i = 0; chain && i < T.OPENSSL_sk_num(chain); i++) {
        void *x = T.OPENSSL_sk_value(chain, i);
        int n = T.i2d_X509(x, NULL);
        if (n <= 0)
            continue;
        NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)n];
        unsigned char *p = [d mutableBytes];
        if (T.i2d_X509(x, &p) == n)
            [ders addObject:d];
    }
    if (!security_available())
        return validate ? errSSLXCertChainInvalid : 0;
    NSMutableArray *certs = [NSMutableArray array];
    for (NSData *d in ders) {
        CFTypeRef cert = S.SecCertificateCreateWithData(NULL, (CFDataRef)d);
        if (cert) {
            [certs addObject:(id)cert];
            CFRelease(cert);
        }
    }
    core->peerCerts = [certs copy];
    CFTypeRef policy = S.SecPolicyCreateSSL(true, (CFStringRef)name);
    if ([certs count] && S.SecTrustCreateWithCertificates((CFArrayRef)certs, policy, &core->trust) != 0)
        core->trust = NULL;
    if (policy)
        CFRelease(policy);
    if (validate && !(core->trust && S.SecTrustEvaluateWithError(core->trust, NULL)))
        return errSSLXCertChainInvalid;
    return 0;
}

@implementation FSocketCore
- (instancetype)init
{
    self = [super init];
    if (self) {
        pthread_mutex_init(&m, NULL);
        pthread_cond_init(&c, NULL);
        pthread_mutex_init(&sslLock, NULL);
        fd = -1;
    }
    return self;
}
- (void)shutDown
{
    pthread_mutex_lock(&m);
    if (closed || state == 1) { /* a connection still being made is closed when it finishes */
        closed = YES;
        pthread_mutex_unlock(&m);
        return;
    }
    closed = YES;
    pthread_mutex_unlock(&m);
    if (ssl) {
        pthread_mutex_lock(&sslLock);
        T.ERR_clear_error();
        T.SSL_shutdown(ssl); /* close_notify, without waiting for the server's */
        T.SSL_free(ssl);
        ssl = NULL;
        pthread_mutex_unlock(&sslLock);
    }
    if (ctx)
        T.SSL_CTX_free(ctx);
    ctx = NULL;
    if (fd >= 0 && closeNative)
        close(fd);
}
- (void)dealloc
{
    [self shutDown];
    if (trust)
        CFRelease(trust);
    [peerCerts release];
    [host release];
    [ssl_settings release];
    [level release];
    pthread_mutex_destroy(&m);
    pthread_cond_destroy(&c);
    pthread_mutex_destroy(&sslLock);
    [super dealloc];
}
/* On a dispatch worker: looks the host up, connects, runs the TLS handshake. */
- (void)connect
{
    int failure = 0;
    BOOL lookup = NO;
    if (fd < 0) {
        struct addrinfo hints, *list = NULL;
        memset(&hints, 0, sizeof hints);
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_flags = AI_ADDRCONFIG;
        char service[16];
        snprintf(service, sizeof service, "%u", (unsigned)port);
        int g = getaddrinfo([host UTF8String], service, &hints, &list);
        if (g) {
            failure = g;
            lookup = YES;
        }
        for (struct addrinfo *a = list; a && fd < 0; a = a->ai_next) {
            int s = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
            if (s < 0) {
                failure = errno;
                continue;
            }
            int on = 1;
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
            int r;
            do
                r = connect(s, a->ai_addr, a->ai_addrlen);
            while (r < 0 && errno == EINTR);
            if (r == 0) {
                fd = s;
                failure = 0;
            } else {
                failure = errno;
                close(s);
            }
        }
        if (list)
            freeaddrinfo(list);
    } else {
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    }
    if (fd >= 0) {
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        NSDictionary *settings = tls_wanted(self);
        if (!failure && settings) {
            @autoreleasepool {
                failure = tls_handshake(self, settings);
            }
        }
    }
    pthread_mutex_lock(&m);
    state = failure || fd < 0 ? 3 : 2;
    err = failure ? failure : fd < 0 ? ECONNREFUSED : 0;
    netdb = lookup && failure;
    BOOL wasClosed = closed;
    FSocketInputStream *in = [input retain];
    FSocketOutputStream *out = [output retain];
    pthread_cond_broadcast(&c);
    pthread_mutex_unlock(&m);
    if (wasClosed) {
        closed = NO;
        [self shutDown];
    }
    [in _coreReady];
    [out _coreReady];
    [in release];
    [out release];
}
- (void)startFor:(id)stream
{
    pthread_mutex_lock(&m);
    int st = state;
    if (!st)
        state = 1;
    pthread_mutex_unlock(&m);
    if (!st) {
        [self retain];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          @autoreleasepool {
              [self connect];
          }
          [self release];
        });
    } else if (st >= 2)
        [stream _coreReady];
}
/* Waits until connecting is over: YES when connected. */
- (BOOL)waitReady
{
    pthread_mutex_lock(&m);
    while (state == 1)
        pthread_cond_wait(&c, &m);
    BOOL ok = state == 2;
    pthread_mutex_unlock(&m);
    return ok;
}
- (void)streamDone:(NSStream *)s
{
    BOOL last;
    pthread_mutex_lock(&m);
    if ((id)s == (id)input)
        input = nil;
    if ((id)s == (id)output)
        output = nil;
    last = !input && !output;
    pthread_mutex_unlock(&m);
    if (last)
        [self shutDown];
}
/* >0 bytes, 0 the end, -1 an error (*e), -2 wait to read, -3 wait to write */
- (ssize_t)recv:(void *)buf length:(size_t)len error:(int *)e
{
    if (ssl) {
        pthread_mutex_lock(&sslLock);
        if (!ssl) {
            pthread_mutex_unlock(&sslLock);
            *e = EBADF;
            return -1;
        }
        T.ERR_clear_error();
        int r = T.SSL_read(ssl, buf, (int)MIN(len, (size_t)INT_MAX));
        int code = r > 0 ? 0 : T.SSL_get_error(ssl, r);
        int saved = errno;
        pthread_mutex_unlock(&sslLock);
        if (r > 0)
            return r;
        switch (code) {
        case SSL_ERROR_ZERO_RETURN: return 0;
        case SSL_ERROR_WANT_READ: return -2;
        case SSL_ERROR_WANT_WRITE: return -3;
        case SSL_ERROR_SYSCALL:
            if (r == 0 || !saved)
                return 0;
            *e = saved;
            return -1;
        default: *e = errSSLClosedAbort; return -1;
        }
    }
    for (;;) {
        ssize_t r = recv(fd, buf, len, 0);
        if (r >= 0)
            return r;
        if (errno == EINTR)
            continue;
        if (errno == EAGAIN)
            return -2;
        *e = errno;
        return -1;
    }
}
- (ssize_t)send:(const void *)buf length:(size_t)len error:(int *)e
{
    if (ssl) {
        if (!len)
            return 0;
        pthread_mutex_lock(&sslLock);
        if (!ssl) {
            pthread_mutex_unlock(&sslLock);
            *e = EBADF;
            return -1;
        }
        T.ERR_clear_error();
        int r = T.SSL_write(ssl, buf, (int)MIN(len, (size_t)INT_MAX));
        int code = r > 0 ? 0 : T.SSL_get_error(ssl, r);
        int saved = errno;
        pthread_mutex_unlock(&sslLock);
        if (r > 0)
            return r;
        if (code == SSL_ERROR_WANT_WRITE)
            return -3;
        if (code == SSL_ERROR_WANT_READ)
            return -2;
        *e = code == SSL_ERROR_SYSCALL && saved ? saved : errSSLClosedAbort;
        return -1;
    }
    for (;;) {
        ssize_t r = send(fd, buf, len, 0);
        if (r >= 0)
            return r;
        if (errno == EINTR)
            continue;
        if (errno == EAGAIN)
            return -3;
        *e = errno;
        return -1;
    }
}
- (BOOL)pending
{
    if (!ssl)
        return NO;
    pthread_mutex_lock(&sslLock);
    BOOL p = ssl && T.SSL_pending(ssl) > 0;
    pthread_mutex_unlock(&sslLock);
    return p;
}
/* What a socket stream answers for a property; nil for one it doesn't hold. */
- (id)property:(NSString *)key
{
    if ([key isEqual:(NSString *)kCFStreamPropertySocketNativeHandle]) {
        if (fd < 0)
            return nil;
        int h = fd;
        return [NSData dataWithBytes:&h length:sizeof h];
    }
    if ([key isEqual:(NSString *)kCFStreamPropertySocketRemoteHostName])
        return host;
    if ([key isEqual:(NSString *)kCFStreamPropertySocketRemotePortNumber])
        return host ? [NSNumber numberWithUnsignedInt:port] : nil;
    if ([key isEqual:(NSString *)kCFStreamPropertyShouldCloseNativeSocket])
        return closeNative ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    if ([key isEqual:(NSString *)kCFStreamPropertySSLSettings])
        return ssl_settings;
    if ([key isEqual:(NSString *)kCFStreamPropertySocketSecurityLevel])
        return level ?: [ssl_settings objectForKey:(NSString *)kCFStreamSSLLevel];
    if ([key isEqual:(NSString *)kCFStreamPropertySSLPeerTrust])
        return (id)trust;
    if ([key isEqual:(NSString *)kCFStreamPropertySSLPeerCertificates])
        return peerCerts;
    return nil;
}
/* YES when it is one of the socket's; *ok says whether it was taken. */
- (BOOL)setProperty:(id)value forKey:(NSString *)key ok:(BOOL *)ok
{
    BOOL tls = [key isEqual:(NSString *)kCFStreamPropertySSLSettings] ||
               [key isEqual:(NSString *)kCFStreamPropertySocketSecurityLevel];
    if (!tls && ![key isEqual:(NSString *)kCFStreamPropertyShouldCloseNativeSocket])
        return NO;
    pthread_mutex_lock(&m);
    if ([key isEqual:(NSString *)kCFStreamPropertyShouldCloseNativeSocket]) {
        closeNative = [value boolValue];
        *ok = YES;
    } else if (state != 0) {
        /* only before the connection is made: an upgrade of an open stream isn't offered */
        *ok = NO;
    } else if ([key isEqual:(NSString *)kCFStreamPropertySSLSettings]) {
        [ssl_settings release];
        ssl_settings = [value isKindOfClass:[NSDictionary class]] ? [value copy] : nil;
        *ok = YES;
    } else {
        [level release];
        level = [value isKindOfClass:[NSString class]] ? [value copy] : nil;
        *ok = YES;
    }
    pthread_mutex_unlock(&m);
    if (tls && !*ok)
        FVerboseOnce(@"TLS settings given to an open socket stream are ignored (give them before open)");
    return YES;
}
@end

/* What the two socket streams share: opening, the watch on the descriptor in
 * the loop or queue the events go to, closing. */
static void socket_ready(int fd, short revents, void *ctx);

static void stream_arm(NSStream *s, FSocketCore *core, NSRunLoop **armedLoop, dispatch_source_t *dsrc, BOOL *dsrcOn,
                       BOOL input, short events)
{
    NSRunLoop *loop = nil;
    dispatch_queue_t q;
    @synchronized(s) {
        q = s->_queue;
        if (!q && [s->_places count] && s->_status != NSStreamStatusClosed)
            loop = [[s->_places objectAtIndex:0] objectAtIndex:0];
    }
    if (*armedLoop && *armedLoop != loop) {
        [*armedLoop _removeDescriptor:core->fd context:s];
        [*armedLoop release];
        *armedLoop = nil;
    }
    if (loop) {
        [loop _addDescriptor:core->fd events:events handler:socket_ready context:s];
        if (!*armedLoop)
            *armedLoop = [loop retain];
    }
    if (q && !*dsrc && events) {
        __block NSStream *weak = s; /* not retained: the stream cancels its source when it goes */
        int fd = core->fd;
        *dsrc = dispatch_source_create(input ? DISPATCH_SOURCE_TYPE_READ : DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)fd, 0,
                                       q);
        dispatch_source_set_event_handler(*dsrc, ^{
          socket_ready(fd, input ? POLLIN : POLLOUT, weak);
        });
        *dsrcOn = NO;
    }
    if (*dsrc) {
        BOOL want = q && events;
        if (want && !*dsrcOn)
            dispatch_resume(*dsrc);
        else if (!want && *dsrcOn)
            dispatch_suspend(*dsrc);
        *dsrcOn = want;
    }
}

static void stream_disarm(NSStream *s, FSocketCore *core, NSRunLoop **armedLoop, dispatch_source_t *dsrc, BOOL *dsrcOn)
{
    if (*armedLoop) {
        [*armedLoop _removeDescriptor:core->fd context:s];
        [*armedLoop release];
        *armedLoop = nil;
    }
    if (*dsrc) {
        dispatch_source_cancel(*dsrc);
        if (!*dsrcOn)
            dispatch_resume(*dsrc);
        dispatch_release(*dsrc);
        *dsrc = NULL;
        *dsrcOn = NO;
    }
}

static void core_ready(NSStream *s, FSocketCore *core)
{
    @synchronized(s) {
        if (s->_status != NSStreamStatusOpening)
            return;
        if (core->state == 2)
            s->_status = NSStreamStatusOpen;
        else {
            s->_status = NSStreamStatusError;
            s->_error = [core_error(core, &s->_cfError) retain];
        }
    }
    [s _didOpen];
}

/* Before a read or a write: an opening stream waits for its connection. */
static NSStreamStatus wait_open(NSStream *s, FSocketCore *core)
{
    if ([s streamStatus] == NSStreamStatusOpening) {
        [core waitReady];
        core_ready(s, core);
    }
    return [s streamStatus];
}

@implementation FSocketInputStream
- (instancetype)initWithCore:(FSocketCore *)core
{
    self = [super init];
    if (self) {
        _core = [core retain];
        pthread_mutex_init(&_io, NULL);
    }
    return self;
}
- (void)dealloc
{
    stream_disarm(self, _core, &_armedLoop, &_dsrc, &_dsrcOn);
    [_core streamDone:self];
    [_core release];
    pthread_mutex_destroy(&_io);
    [super dealloc];
}
- (void)_doOpen { [_core startFor:self]; }
- (void)_coreReady { core_ready(self, _core); }
- (void)_doClose
{
    stream_disarm(self, _core, &_armedLoop, &_dsrc, &_dsrcOn);
    [_core streamDone:self];
}
- (void)_arm:(short)events { stream_arm(self, _core, &_armedLoop, &_dsrc, &_dsrcOn, YES, events); }
- (void)_scheduleChanged
{
    if (_core->state == 2 && [self streamStatus] != NSStreamStatusClosed)
        [self _arm:0];
    [super _scheduleChanged];
}
- (NSStreamEvent)_readiness
{
    pthread_mutex_lock(&_io);
    BOOL have = _have > _used;
    pthread_mutex_unlock(&_io);
    if (have || [_core pending])
        return NSStreamEventHasBytesAvailable;
    [self _arm:POLLIN];
    return NSStreamEventNone;
}
/* The descriptor is ready: read what came, then say so. */
- (void)_ready
{
    if (!is_live([self streamStatus]))
        return;
    [self _arm:0];
    int e = 0;
    ssize_t r = 0;
    pthread_mutex_lock(&_io);
    if (_have > _used)
        r = 1;
    else {
        r = [_core recv:_buf length:sizeof _buf error:&e];
        if (r > 0) {
            _have = (size_t)r;
            _used = 0;
        }
    }
    pthread_mutex_unlock(&_io);
    if (r > 0)
        [self _kick];
    else if (r == 0)
        [self _atEnd];
    else if (r == -2)
        [self _arm:POLLIN];
    else if (r == -3)
        [self _arm:POLLOUT];
    else
        fail(self, e);
}
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSStreamStatus st = wait_open(self, _core);
    if (st == NSStreamStatusAtEnd)
        return 0;
    if (!is_live(st))
        return -1;
    for (;;) {
        int e = 0;
        ssize_t r;
        pthread_mutex_lock(&_io);
        if (_have > _used) {
            r = (ssize_t)MIN(len, _have - _used);
            memcpy(buffer, _buf + _used, (size_t)r);
            _used += (size_t)r;
        } else
            r = [_core recv:buffer length:len error:&e];
        pthread_mutex_unlock(&_io);
        if (r > 0) {
            [self _consumed];
            return r;
        }
        if (r == 0) {
            if (len)
                [self _atEnd];
            return 0;
        }
        if (r == -2 || r == -3) {
            wait_fd(_core->fd, r == -2 ? POLLIN : POLLOUT);
            if (!is_live([self streamStatus]))
                return -1;
            continue;
        }
        fail(self, e);
        return -1;
    }
}
- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len { return NO; }
- (BOOL)hasBytesAvailable
{
    NSStreamStatus st = [self streamStatus];
    if (st == NSStreamStatusOpening || st == NSStreamStatusNotOpen)
        return NO;
    if (!is_live(st))
        return NO;
    pthread_mutex_lock(&_io);
    BOOL have = _have > _used;
    pthread_mutex_unlock(&_io);
    if (have || [_core pending])
        return YES;
    struct pollfd p = {_core->fd, POLLIN, 0};
    return poll(&p, 1, 0) > 0;
}
- (id)propertyForKey:(NSStreamPropertyKey)key { return [_core property:key] ?: [super propertyForKey:key]; }
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
    BOOL ok = NO;
    return [_core setProperty:property forKey:key ok:&ok] ? ok : [super setProperty:property forKey:key];
}
@end

@implementation FSocketOutputStream
- (instancetype)initWithCore:(FSocketCore *)core
{
    self = [super init];
    if (self)
        _core = [core retain];
    return self;
}
- (void)dealloc
{
    stream_disarm(self, _core, &_armedLoop, &_dsrc, &_dsrcOn);
    [_core streamDone:self];
    [_core release];
    [super dealloc];
}
- (void)_doOpen { [_core startFor:self]; }
- (void)_coreReady { core_ready(self, _core); }
- (void)_doClose
{
    stream_disarm(self, _core, &_armedLoop, &_dsrc, &_dsrcOn);
    [_core streamDone:self];
}
- (void)_arm:(short)events { stream_arm(self, _core, &_armedLoop, &_dsrc, &_dsrcOn, NO, events); }
- (void)_scheduleChanged
{
    if (_core->state == 2 && [self streamStatus] != NSStreamStatusClosed)
        [self _arm:0];
    [super _scheduleChanged];
}
- (NSStreamEvent)_readiness
{
    struct pollfd p = {_core->fd, POLLOUT, 0};
    if (poll(&p, 1, 0) > 0 && (p.revents & POLLOUT))
        return NSStreamEventHasSpaceAvailable;
    [self _arm:POLLOUT];
    return NSStreamEventNone;
}
- (void)_ready
{
    if (!is_live([self streamStatus]))
        return;
    [self _arm:0];
    [self _kick];
}
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSStreamStatus st = wait_open(self, _core);
    if (!is_live(st))
        return -1;
    for (;;) {
        int e = 0;
        ssize_t r = [_core send:buffer length:len error:&e];
        if (r >= 0) {
            [self _consumed];
            return r;
        }
        if (r == -2 || r == -3) {
            wait_fd(_core->fd, r == -2 ? POLLIN : POLLOUT);
            if (!is_live([self streamStatus]))
                return -1;
            continue;
        }
        fail(self, e);
        return -1;
    }
}
- (BOOL)hasSpaceAvailable
{
    if (!is_live([self streamStatus]))
        return NO;
    struct pollfd p = {_core->fd, POLLOUT, 0};
    return poll(&p, 1, 0) > 0 && (p.revents & POLLOUT);
}
- (id)propertyForKey:(NSStreamPropertyKey)key { return [_core property:key] ?: [super propertyForKey:key]; }
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
    BOOL ok = NO;
    return [_core setProperty:property forKey:key ok:&ok] ? ok : [super setProperty:property forKey:key];
}
@end

static void socket_ready(int fd, short revents, void *ctx)
{
    id<FReady> s = [(id)ctx retain];
    [s _ready];
    [s release];
}

/* ---- making socket streams ----------------------------------------------------------------- */

static void make_pair(FSocketCore *core, CFReadStreamRef *readStream, CFWriteStreamRef *writeStream)
{
    if (readStream) {
        FSocketInputStream *in = [[FSocketInputStream alloc] initWithCore:core];
        core->input = in;
        *readStream = (CFReadStreamRef)in;
    }
    if (writeStream) {
        FSocketOutputStream *out = [[FSocketOutputStream alloc] initWithCore:core];
        core->output = out;
        *writeStream = (CFWriteStreamRef)out;
    }
    [core release];
}

void CFStreamCreatePairWithSocketToHost(CFAllocatorRef alloc, CFStringRef host, UInt32 port, CFReadStreamRef *readStream,
                                        CFWriteStreamRef *writeStream)
{
    FSocketCore *core = [[FSocketCore alloc] init];
    core->host = [(NSString *)host copy];
    core->port = port;
    core->closeNative = YES;
    make_pair(core, readStream, writeStream);
}

void CFStreamCreatePairWithSocket(CFAllocatorRef alloc, CFSocketNativeHandle sock, CFReadStreamRef *readStream,
                                  CFWriteStreamRef *writeStream)
{
    FSocketCore *core = [[FSocketCore alloc] init];
    core->fd = sock;
    core->closeNative = NO; /* the program's own socket, unless kCFStreamPropertyShouldCloseNativeSocket says */
    make_pair(core, readStream, writeStream);
}

void CFStreamCreateBoundPair(CFAllocatorRef alloc, CFReadStreamRef *readStream, CFWriteStreamRef *writeStream,
                             CFIndex transferBufferSize)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
        if (readStream)
            *readStream = NULL;
        if (writeStream)
            *writeStream = NULL;
        return;
    }
    int size = transferBufferSize > 0 && transferBufferSize < INT_MAX ? (int)transferBufferSize : 4096;
    setsockopt(sv[1], SOL_SOCKET, SO_SNDBUF, &size, sizeof size);
    setsockopt(sv[0], SOL_SOCKET, SO_RCVBUF, &size, sizeof size);
    FSocketCore *rc = [[FSocketCore alloc] init], *wc = [[FSocketCore alloc] init];
    rc->fd = sv[0];
    wc->fd = sv[1];
    rc->closeNative = wc->closeNative = YES;
    make_pair(rc, readStream, NULL);
    make_pair(wc, NULL, writeStream);
}

@implementation NSStream (NSSocketStreamCreationExtensions)
+ (void)getStreamsToHostWithName:(NSString *)hostname
                            port:(NSInteger)port
                     inputStream:(NSInputStream **)inputStream
                    outputStream:(NSOutputStream **)outputStream
{
    CFReadStreamRef r = NULL;
    CFWriteStreamRef w = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)hostname, (UInt32)port, inputStream ? &r : NULL,
                                       outputStream ? &w : NULL);
    if (inputStream)
        *inputStream = [(NSInputStream *)r autorelease];
    if (outputStream)
        *outputStream = [(NSOutputStream *)w autorelease];
}
@end

@implementation NSStream (NSStreamBoundPairCreationExtensions)
+ (void)getBoundStreamsWithBufferSize:(NSUInteger)bufferSize
                          inputStream:(NSInputStream **)inputStream
                         outputStream:(NSOutputStream **)outputStream
{
    CFReadStreamRef r = NULL;
    CFWriteStreamRef w = NULL;
    CFStreamCreateBoundPair(NULL, inputStream ? &r : NULL, outputStream ? &w : NULL, (CFIndex)bufferSize);
    if (inputStream)
        *inputStream = [(NSInputStream *)r autorelease];
    if (outputStream)
        *outputStream = [(NSOutputStream *)w autorelease];
}
@end

/* ---- CFReadStream and CFWriteStream ---------------------------------------------------------- */

#define RS(x) ((NSInputStream *)(x))
#define WS(x) ((NSOutputStream *)(x))

CFTypeID CFReadStreamGetTypeID(void) { return 0x46520003; }
CFTypeID CFWriteStreamGetTypeID(void) { return 0x46520004; }

CFReadStreamRef CFReadStreamCreateWithBytesNoCopy(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex length,
                                                  CFAllocatorRef bytesDeallocator)
{
    NSData *d = [NSData dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:NO];
    return (CFReadStreamRef)[[NSInputStream alloc] initWithData:d];
}
CFReadStreamRef CFReadStreamCreateWithData(CFAllocatorRef alloc, CFDataRef data)
{
    return (CFReadStreamRef)[[NSInputStream alloc] initWithData:(NSData *)data];
}
CFReadStreamRef CFReadStreamCreateWithFile(CFAllocatorRef alloc, CFURLRef fileURL)
{
    return (CFReadStreamRef)[[NSInputStream alloc] initWithURL:(NSURL *)fileURL];
}
CFWriteStreamRef CFWriteStreamCreateWithBuffer(CFAllocatorRef alloc, UInt8 *buffer, CFIndex bufferCapacity)
{
    return (CFWriteStreamRef)[[NSOutputStream alloc] initToBuffer:buffer capacity:(NSUInteger)bufferCapacity];
}
CFWriteStreamRef CFWriteStreamCreateWithAllocatedBuffers(CFAllocatorRef alloc, CFAllocatorRef bufferAllocator)
{
    return (CFWriteStreamRef)[[NSOutputStream alloc] initToMemory];
}
CFWriteStreamRef CFWriteStreamCreateWithFile(CFAllocatorRef alloc, CFURLRef fileURL)
{
    return (CFWriteStreamRef)[[NSOutputStream alloc] initWithURL:(NSURL *)fileURL append:NO];
}

CFStreamStatus CFReadStreamGetStatus(CFReadStreamRef stream) { return (CFStreamStatus)[RS(stream) streamStatus]; }
CFStreamStatus CFWriteStreamGetStatus(CFWriteStreamRef stream) { return (CFStreamStatus)[WS(stream) streamStatus]; }
CFErrorRef CFReadStreamCopyError(CFReadStreamRef stream) { return (CFErrorRef)[[RS(stream) streamError] retain]; }
CFErrorRef CFWriteStreamCopyError(CFWriteStreamRef stream) { return (CFErrorRef)[[WS(stream) streamError] retain]; }
static CFStreamError stream_error(NSStream *s)
{
    CFStreamError e = {0, 0};
    @synchronized(s) {
        e = s->_cfError;
    }
    if (!e.domain) {
        NSError *ns = [s streamError];
        if (ns) {
            e.domain = [[ns domain] isEqual:NSPOSIXErrorDomain]       ? kCFStreamErrorDomainPOSIX
                       : [[ns domain] isEqual:NSOSStatusErrorDomain] ? kCFStreamErrorDomainMacOSStatus
                                                                     : kCFStreamErrorDomainCustom;
            e.error = (SInt32)[ns code];
        }
    }
    return e;
}
CFStreamError CFReadStreamGetError(CFReadStreamRef stream) { return stream_error(RS(stream)); }
CFStreamError CFWriteStreamGetError(CFWriteStreamRef stream) { return stream_error(WS(stream)); }
Boolean CFReadStreamOpen(CFReadStreamRef stream)
{
    if ([RS(stream) streamStatus] != NSStreamStatusNotOpen)
        return false;
    [RS(stream) open];
    return [RS(stream) streamStatus] != NSStreamStatusError;
}
Boolean CFWriteStreamOpen(CFWriteStreamRef stream)
{
    if ([WS(stream) streamStatus] != NSStreamStatusNotOpen)
        return false;
    [WS(stream) open];
    return [WS(stream) streamStatus] != NSStreamStatusError;
}
void CFReadStreamClose(CFReadStreamRef stream) { [RS(stream) close]; }
void CFWriteStreamClose(CFWriteStreamRef stream) { [WS(stream) close]; }
Boolean CFReadStreamHasBytesAvailable(CFReadStreamRef stream) { return [RS(stream) hasBytesAvailable]; }
CFIndex CFReadStreamRead(CFReadStreamRef stream, UInt8 *buffer, CFIndex bufferLength)
{
    return (CFIndex)[RS(stream) read:buffer maxLength:(NSUInteger)(bufferLength > 0 ? bufferLength : 0)];
}
/* Only a stream on bytes in memory has a buffer to lend; what it lends is read. */
const UInt8 *CFReadStreamGetBuffer(CFReadStreamRef stream, CFIndex maxBytesToRead, CFIndex *numBytesRead)
{
    uint8_t *p = NULL;
    NSUInteger n = 0;
    if ([RS(stream) isKindOfClass:[FDataInputStream class]] && [RS(stream) getBuffer:&p length:&n]) {
        if (maxBytesToRead > 0 && n > (NSUInteger)maxBytesToRead)
            n = (NSUInteger)maxBytesToRead;
        [(FDataInputStream *)stream _take:n];
        if (numBytesRead)
            *numBytesRead = (CFIndex)n;
        return p;
    }
    if (numBytesRead)
        *numBytesRead = 0;
    return NULL;
}
Boolean CFWriteStreamCanAcceptBytes(CFWriteStreamRef stream) { return [WS(stream) hasSpaceAvailable]; }
CFIndex CFWriteStreamWrite(CFWriteStreamRef stream, const UInt8 *buffer, CFIndex bufferLength)
{
    return (CFIndex)[WS(stream) write:buffer maxLength:(NSUInteger)(bufferLength > 0 ? bufferLength : 0)];
}
CFTypeRef CFReadStreamCopyProperty(CFReadStreamRef stream, CFStreamPropertyKey propertyName)
{
    return [[RS(stream) propertyForKey:(NSString *)propertyName] retain];
}
CFTypeRef CFWriteStreamCopyProperty(CFWriteStreamRef stream, CFStreamPropertyKey propertyName)
{
    return [[WS(stream) propertyForKey:(NSString *)propertyName] retain];
}
Boolean CFReadStreamSetProperty(CFReadStreamRef stream, CFStreamPropertyKey propertyName, CFTypeRef propertyValue)
{
    return [RS(stream) setProperty:(id)propertyValue forKey:(NSString *)propertyName];
}
Boolean CFWriteStreamSetProperty(CFWriteStreamRef stream, CFStreamPropertyKey propertyName, CFTypeRef propertyValue)
{
    return [WS(stream) setProperty:(id)propertyValue forKey:(NSString *)propertyName];
}
Boolean CFReadStreamSetClient(CFReadStreamRef stream, CFOptionFlags streamEvents, CFReadStreamClientCallBack clientCB,
                              CFStreamClientContext *clientContext)
{
    return [RS(stream) _setClient:streamEvents callback:(void *)clientCB context:clientContext];
}
Boolean CFWriteStreamSetClient(CFWriteStreamRef stream, CFOptionFlags streamEvents,
                               CFWriteStreamClientCallBack clientCB, CFStreamClientContext *clientContext)
{
    return [WS(stream) _setClient:streamEvents callback:(void *)clientCB context:clientContext];
}
void CFReadStreamScheduleWithRunLoop(CFReadStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode)
{
    [RS(stream) scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)runLoopMode];
}
void CFWriteStreamScheduleWithRunLoop(CFWriteStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode)
{
    [WS(stream) scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)runLoopMode];
}
void CFReadStreamUnscheduleFromRunLoop(CFReadStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode)
{
    [RS(stream) removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)runLoopMode];
}
void CFWriteStreamUnscheduleFromRunLoop(CFWriteStreamRef stream, CFRunLoopRef runLoop, CFRunLoopMode runLoopMode)
{
    [WS(stream) removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)runLoopMode];
}
void CFReadStreamSetDispatchQueue(CFReadStreamRef stream, dispatch_queue_t q) { [RS(stream) _setQueue:q]; }
void CFWriteStreamSetDispatchQueue(CFWriteStreamRef stream, dispatch_queue_t q) { [WS(stream) _setQueue:q]; }
dispatch_queue_t CFReadStreamCopyDispatchQueue(CFReadStreamRef stream)
{
    @synchronized(RS(stream)) {
        dispatch_queue_t q = RS(stream)->_queue;
        if (q)
            dispatch_retain(q);
        return q;
    }
}
dispatch_queue_t CFWriteStreamCopyDispatchQueue(CFWriteStreamRef stream)
{
    @synchronized(WS(stream)) {
        dispatch_queue_t q = WS(stream)->_queue;
        if (q)
            dispatch_retain(q);
        return q;
    }
}
