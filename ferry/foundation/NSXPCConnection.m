/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSXPCConnection, NSXPCListener and NSXPCInterface,
 * as Apple's API reference describes them. First (freemac 1.224, Ferry
 * 0.48.0) a connection never reached the other side; since freemac 1.264
 * (Ferry 0.87.0) a connection to a service an app carries in its bundle
 * (Contents/XPCServices/NAME.xpc) works: the service runs as a program of
 * its own under Ferry, the two talk over a socket, and messages, reply
 * blocks and the objects they carry go across, so HandBrake encodes in its
 * helper as it does on a Mac.
 *
 * The wire is our own, since both ends are Ferry: each message is a
 * keyed archive (a dictionary) after its length. A call names its
 * selector and carries its arguments: objects archived, other values as
 * their bytes, and a block as a number the other side calls back with. On
 * the receiving side such a block is one whose invoke function sends its
 * arguments back (FBlockForwardEntry, NSInvocation.m). Our own code; no
 * Apple code was used. Built without ARC. */
#import "FInternal.h"
#include <Foundation/NSXPCConnection.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <spawn.h>
#include <pthread.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>

extern char **environ;
void FBlockForwardEntry(void);
const char *_Block_signature(void *block);

@interface NSInvocation (FerryBlocks)
- (void)_invokeFunction:(void *)function;
@end

struct FBlockLayout {
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    void *descriptor;
};
struct FBlockDesc {
    unsigned long reserved, size;
    void *copy, *dispose;
    const char *signature;
    const char *layout;
};
#define F_BLOCK_HAS_COPY_DISPOSE (1 << 25)
#define F_BLOCK_HAS_SIGNATURE (1 << 30)

static const char *protocol_types(Protocol *p, SEL sel, int depth)
{
    if (!p || depth > 8)
        return NULL;
    for (int required = 1; required >= 0; required--) {
        struct objc_method_description d = protocol_getMethodDescription(p, sel, required, YES);
        if (d.types)
            return d.types;
    }
    unsigned n = 0;
    Protocol **inherited = protocol_copyProtocolList(p, &n);
    const char *found = NULL;
    for (unsigned i = 0; i < n && !found; i++)
        found = protocol_types(inherited[i], sel, depth + 1);
    free(inherited);
    return found;
}

static const char *skip_qualifiers(const char *t)
{
    while (*t && strchr("rnNoORVA", *t))
        t++;
    return t;
}

static pthread_key_t current_key;
static pthread_once_t current_once = PTHREAD_ONCE_INIT;
static void make_current_key(void) { pthread_key_create(&current_key, NULL); }

@interface NSXPCConnection (FerryWire)
- (instancetype)_initWithSocket:(int)fd;
- (void)_sendInvocation:(NSInvocation *)inv handler:(void (^)(NSError *))handler synchronous:(BOOL)sync;
- (void)_sendReply:(NSNumber *)ident invocation:(NSInvocation *)inv;
- (void)_readLoop;
- (void)_startReading;
@end

/* Stands for a reply block of the other side: what calls it sends the
 * arguments back over the connection. */
@interface FXPCReplyBox : NSObject {
@public
    NSXPCConnection *_connection;
    NSNumber *_ident;
}
@end
@implementation FXPCReplyBox
- (void)dealloc
{
    [_connection release];
    [_ident release];
    [super dealloc];
}
- (void)_ferryBlockCalled:(NSInvocation *)inv
{
    [_connection _sendReply:_ident invocation:inv];
}
@end

/* A block with the given signature whose calls go to box. */
static id forwarding_block(FXPCReplyBox *box, const char *signature)
{
    static NSMutableDictionary *descriptors;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    id captured = box;
    void (^literal)(void) = ^{
        (void)captured;
    };
    struct FBlockLayout *b = (struct FBlockLayout *)[literal copy];
    const struct FBlockDesc *orig = (const struct FBlockDesc *)b->descriptor;
    if (!(b->flags & F_BLOCK_HAS_COPY_DISPOSE))
        return [(id)b autorelease];
    NSString *key = [NSString stringWithUTF8String:signature];
    pthread_mutex_lock(&lock);
    if (!descriptors)
        descriptors = [[NSMutableDictionary alloc] init];
    struct FBlockDesc *d = [[descriptors objectForKey:key] pointerValue];
    if (!d) {
        d = calloc(1, sizeof *d);
        d->size = orig->size;
        d->copy = orig->copy;
        d->dispose = orig->dispose;
        d->signature = strdup(signature);
        [descriptors setObject:[NSValue valueWithPointer:d] forKey:key];
    }
    pthread_mutex_unlock(&lock);
    b->descriptor = d;
    b->flags |= F_BLOCK_HAS_SIGNATURE;
    b->invoke = (void *)FBlockForwardEntry;
    return [(id)b autorelease];
}

/* Answers every message the remote interface's protocol names (any other
 * as one taking nothing) by sending it to the other side. */
@interface FXPCProxy : NSProxy {
@public
    NSXPCConnection *_connection;
    void (^_handler)(NSError *);
    BOOL _synchronous;
}
@end

@implementation FXPCProxy
- (void)dealloc
{
    [_connection release];
    [_handler release];
    [super dealloc];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    const char *types = protocol_types([[_connection remoteObjectInterface] protocol], sel, 0);
    return [NSMethodSignature signatureWithObjCTypes:types ? types : "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)invocation
{
    NSUInteger size = [[invocation methodSignature] methodReturnLength];
    if (size) {
        void *zero = calloc(1, size);
        [invocation setReturnValue:zero];
        free(zero);
    }
    [_connection _sendInvocation:invocation handler:_handler synchronous:_synchronous];
}
- (BOOL)respondsToSelector:(SEL)sel
{
    return protocol_types([[_connection remoteObjectInterface] protocol], sel, 0) != NULL;
}
- (BOOL)conformsToProtocol:(Protocol *)p
{
    Protocol *mine = [[_connection remoteObjectInterface] protocol];
    return mine && (p == mine || protocol_conformsToProtocol(mine, p));
}
@end

@implementation NSXPCConnection {
    NSString *_serviceName;
    NSXPCListenerEndpoint *_endpoint;
    NSXPCInterface *_exportedInterface, *_remoteObjectInterface;
    id _exportedObject;
    void (^_interruptionHandler)(void);
    void (^_invalidationHandler)(void);
    BOOL _invalid, _resumed, _listenerSide, _reading;
    int _fd;
    pid_t _pid;
    unsigned long long _next;
    NSMutableDictionary *_replies;   /* number -> @[block, error handler or null] */
    NSMutableSet *_done;             /* synchronous calls the other side finished */
    dispatch_queue_t _queue;
    pthread_mutex_t _lock;
    pthread_cond_t _cond;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _fd = -1;
        _replies = [[NSMutableDictionary alloc] init];
        _done = [[NSMutableSet alloc] init];
        _queue = dispatch_queue_create("com.apple.NSXPCConnection.user", NULL);
        pthread_mutex_init(&_lock, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}
- (instancetype)initWithServiceName:(NSString *)serviceName
{
    if ((self = [self init]))
        _serviceName = [serviceName copy];
    return self;
}
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options
{
    return [self initWithServiceName:name];
}
- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint
{
    if ((self = [self init]))
        _endpoint = [endpoint retain];
    return self;
}
- (instancetype)_initWithSocket:(int)fd
{
    if ((self = [self init])) {
        _fd = fd;
        _listenerSide = YES;
    }
    return self;
}
- (void)dealloc
{
    if (_fd >= 0)
        close(_fd);
    [_serviceName release];
    [_endpoint release];
    [_exportedInterface release];
    [_remoteObjectInterface release];
    [_exportedObject release];
    [_interruptionHandler release];
    [_invalidationHandler release];
    [_replies release];
    [_done release];
    if (_queue)
        dispatch_release(_queue);
    pthread_mutex_destroy(&_lock);
    pthread_cond_destroy(&_cond);
    [super dealloc];
}
- (NSString *)serviceName { return _serviceName; }
- (NSXPCListenerEndpoint *)endpoint { return _endpoint; }
- (NSXPCInterface *)exportedInterface { return _exportedInterface; }
- (void)setExportedInterface:(NSXPCInterface *)i
{
    [i retain];
    [_exportedInterface release];
    _exportedInterface = i;
}
- (id)exportedObject { return _exportedObject; }
- (void)setExportedObject:(id)o
{
    [o retain];
    [_exportedObject release];
    _exportedObject = o;
}
- (NSXPCInterface *)remoteObjectInterface { return _remoteObjectInterface; }
- (void)setRemoteObjectInterface:(NSXPCInterface *)i
{
    [i retain];
    [_remoteObjectInterface release];
    _remoteObjectInterface = i;
}
- (void (^)(void))interruptionHandler { return _interruptionHandler; }
- (void)setInterruptionHandler:(void (^)(void))h
{
    h = [h copy];
    [_interruptionHandler release];
    _interruptionHandler = h;
}
- (void (^)(void))invalidationHandler { return _invalidationHandler; }
- (void)setInvalidationHandler:(void (^)(void))h
{
    h = [h copy];
    [_invalidationHandler release];
    _invalidationHandler = h;
}
- (id)proxyWithHandler:(void (^)(NSError *))handler synchronous:(BOOL)synchronous
{
    FXPCProxy *p = [FXPCProxy alloc];
    p->_connection = [self retain];
    p->_handler = [handler copy];
    p->_synchronous = synchronous;
    return [p autorelease];
}
- (id)remoteObjectProxy { return [self proxyWithHandler:nil synchronous:NO]; }
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *))handler
{
    return [self proxyWithHandler:handler synchronous:NO];
}
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *))handler
{
    return [self proxyWithHandler:handler synchronous:YES];
}

/* ---- the error handlers ---- */

static NSError *xpc_error(NSInteger code)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:nil];
}

/* A proxy's error handler: on the caller's thread for a synchronous proxy,
 * otherwise on the connection's queue, as a Mac calls them. */
- (void)_fail:(void (^)(NSError *))handler code:(NSInteger)code now:(BOOL)now
{
    if (!handler)
        return;
    NSError *error = xpc_error(code);
    if (now) {
        handler(error);
        return;
    }
    handler = [handler copy];
    [error retain];
    dispatch_async(_queue, ^{
        handler(error);
        [handler release];
        [error release];
    });
}

/* ---- finding and starting the service ---- */

static NSString *bundle_identifier(NSString *bundle)
{
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if (!info)
        info = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]];
    id ident = [info objectForKey:@"CFBundleIdentifier"];
    return [ident isKindOfClass:[NSString class]] ? ident : nil;
}

static NSString *service_in(NSString *folder, NSString *name)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *named = [folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"xpc"]];
    if ([fm fileExistsAtPath:named] && [bundle_identifier(named) isEqualToString:name])
        return named;
    for (NSString *entry in [fm contentsOfDirectoryAtPath:folder error:NULL]) {
        if (![[entry pathExtension] isEqualToString:@"xpc"])
            continue;
        NSString *path = [folder stringByAppendingPathComponent:entry];
        if ([bundle_identifier(path) isEqualToString:name])
            return path;
    }
    return [fm fileExistsAtPath:named] ? named : nil;
}

/* The NAME.xpc bundle of a service: in the app's Contents/XPCServices, or
 * in one of its frameworks' XPCServices. */
static NSString *find_service(NSString *name)
{
    if (!name)
        return nil;
    NSString *app = [[NSBundle mainBundle] bundlePath];
    NSString *found = service_in([app stringByAppendingPathComponent:@"Contents/XPCServices"], name);
    if (found)
        return found;
    for (NSBundle *framework in [NSBundle allFrameworks]) {
        NSString *path = [framework bundlePath];
        found = service_in([path stringByAppendingPathComponent:@"Versions/Current/XPCServices"], name);
        if (!found)
            found = service_in([path stringByAppendingPathComponent:@"XPCServices"], name);
        if (found)
            return found;
    }
    NSString *frameworks = [app stringByAppendingPathComponent:@"Contents/Frameworks"];
    for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworks error:NULL]) {
        if (![[entry pathExtension] isEqualToString:@"framework"])
            continue;
        found = service_in([[frameworks stringByAppendingPathComponent:entry]
                               stringByAppendingPathComponent:@"Versions/Current/XPCServices"], name);
        if (found)
            return found;
    }
    return nil;
}

static void *reap(void *arg)
{
    pid_t pid = (pid_t)(intptr_t)arg;
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
        ;
    return NULL;
}

/* Starts the service with the other end of a socket, under the lock. */
- (BOOL)_launch
{
    NSString *bundle = find_service(_serviceName);
    NSString *exe = bundle ? [[NSBundle bundleWithPath:bundle] executablePath] : nil;
    if (!exe) {
        FVerboseOnce([NSString stringWithFormat:@"XPC service %@ isn't in this app", _serviceName]);
        return NO;
    }
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0)
        return NO;
    fcntl(sv[0], F_SETFD, FD_CLOEXEC);
    signal(SIGPIPE, SIG_IGN);
    size_t n = 0;
    while (environ && environ[n])
        n++;
    char **envp = calloc(n + 2, sizeof *envp);
    size_t k = 0;
    for (size_t i = 0; i < n; i++)
        if (strncmp(environ[i], "FERRY_XPC_FD=", 13))
            envp[k++] = environ[i];
    char fdvar[32];
    snprintf(fdvar, sizeof fdvar, "FERRY_XPC_FD=%d", sv[1]);
    envp[k++] = fdvar;
    envp[k] = NULL;
    const char *path = [exe fileSystemRepresentation];
    char *argv[] = {(char *)path, NULL};
    pid_t pid = 0;
    int err = posix_spawn(&pid, path, NULL, NULL, argv, envp);
    free(envp);
    close(sv[1]);
    if (err) {
        close(sv[0]);
        FVerboseOnce([NSString stringWithFormat:@"XPC service %@ couldn't be started (%s)", _serviceName, strerror(err)]);
        return NO;
    }
    _pid = pid;
    _fd = sv[0];
    pthread_t t;
    if (!pthread_create(&t, NULL, reap, (void *)(intptr_t)pid))
        pthread_detach(t);
    [self _startReading];
    return YES;
}

/* ---- the wire ---- */

static BOOL write_all(int fd, const void *p, size_t n)
{
    const uint8_t *b = p;
    while (n) {
        ssize_t w = write(fd, b, n);
        if (w < 0 && errno == EINTR)
            continue;
        if (w <= 0)
            return NO;
        b += w;
        n -= (size_t)w;
    }
    return YES;
}

static BOOL read_all(int fd, void *p, size_t n)
{
    uint8_t *b = p;
    while (n) {
        ssize_t r = read(fd, b, n);
        if (r < 0 && errno == EINTR)
            continue;
        if (r <= 0)
            return NO;
        b += r;
        n -= (size_t)r;
    }
    return YES;
}

/* Under the lock. */
- (BOOL)_write:(NSDictionary *)message
{
    NSData *data = nil;
    @try {
        data = [NSKeyedArchiver archivedDataWithRootObject:message requiringSecureCoding:NO error:NULL];
    } @catch (id e) {
        data = nil;
    }
    if (!data) {
        FVerboseOnce(@"an XPC message couldn't be archived");
        return NO;
    }
    if (_fd < 0)
        return NO;
    uint32_t len = (uint32_t)[data length];
    return write_all(_fd, &len, 4) && write_all(_fd, [data bytes], len);
}

/* An argument as it goes across: @{n: nothing}, @{o: object}, @{b: number,
 * s: signature} for a block, @{c: class name}, @{l: selector name} or
 * @{d: the value's bytes}. Under the lock. */
- (id)_encodeArgument:(NSInvocation *)inv index:(NSUInteger)i handler:(void (^)(NSError *))handler
                 replies:(NSMutableArray *)replies
{
    const char *type = skip_qualifiers([[inv methodSignature] getArgumentTypeAtIndex:i]);
    if (type[0] == '@') {
        id value = nil;
        [inv getArgument:&value atIndex:i];
        if (!value)
            return @{@"n" : @YES};
        if (type[1] == '?') {
            NSNumber *ident = [NSNumber numberWithUnsignedLongLong:++_next];
            const char *sig = _Block_signature(value);
            id block = [[value copy] autorelease];
            [_replies setObject:@[ block, handler ? (id)[[handler copy] autorelease] : (id)[NSNull null] ]
                         forKey:ident];
            [replies addObject:ident];
            return @{@"b" : ident, @"s" : [NSString stringWithUTF8String:sig ? sig : "v8@?0"]};
        }
        return @{@"o" : value};
    }
    if (type[0] == '#') {
        Class c = Nil;
        [inv getArgument:&c atIndex:i];
        return c ? @{@"c" : NSStringFromClass(c)} : @{@"n" : @YES};
    }
    if (type[0] == ':') {
        SEL s = NULL;
        [inv getArgument:&s atIndex:i];
        return s ? @{@"l" : NSStringFromSelector(s)} : @{@"n" : @YES};
    }
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    void *buf = calloc(1, size ? size : 1);
    if (type[0] != '^' && type[0] != '*')
        [inv getArgument:buf atIndex:i];
    NSData *d = [NSData dataWithBytes:buf length:size];
    free(buf);
    return @{@"d" : d};
}

- (BOOL)_decodeArgument:(NSDictionary *)arg into:(NSInvocation *)inv index:(NSUInteger)i
{
    const char *type = skip_qualifiers([[inv methodSignature] getArgumentTypeAtIndex:i]);
    if (![arg isKindOfClass:[NSDictionary class]])
        return NO;
    id v;
    if ((v = [arg objectForKey:@"o"])) {
        [inv setArgument:&v atIndex:i];
    } else if ((v = [arg objectForKey:@"b"])) {
        FXPCReplyBox *box = [[FXPCReplyBox alloc] init];
        box->_connection = [self retain];
        box->_ident = [v retain];
        id block = forwarding_block(box, [[arg objectForKey:@"s"] UTF8String]);
        [box release];
        [inv setArgument:&block atIndex:i];
    } else if ((v = [arg objectForKey:@"c"])) {
        Class c = NSClassFromString(v);
        [inv setArgument:&c atIndex:i];
    } else if ((v = [arg objectForKey:@"l"])) {
        SEL s = NSSelectorFromString(v);
        [inv setArgument:&s atIndex:i];
    } else if ((v = [arg objectForKey:@"d"])) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(type, &size, NULL);
        if ([v length] != size)
            return NO;
        [inv setArgument:(void *)[v bytes] atIndex:i];
    } else {
        void *zero = calloc(1, 64);
        [inv setArgument:zero atIndex:i];
        free(zero);
    }
    return YES;
}

static NSString *type_string(NSMethodSignature *sig)
{
    NSMutableString *t = [NSMutableString stringWithUTF8String:[sig methodReturnType]];
    for (NSUInteger i = 0; i < [sig numberOfArguments]; i++)
        [t appendFormat:@"%s", [sig getArgumentTypeAtIndex:i]];
    return t;
}

/* Called by a proxy. */
- (void)_sendInvocation:(NSInvocation *)inv handler:(void (^)(NSError *))handler synchronous:(BOOL)sync
{
    NSMethodSignature *sig = [inv methodSignature];
    pthread_mutex_lock(&_lock);
    if (_invalid || (_fd < 0 && (_listenerSide || ![self _launch]))) {
        BOOL was = _invalid;
        pthread_mutex_unlock(&_lock);
        [self _fail:handler code:NSXPCConnectionInvalid now:sync];
        /* a service that can't be found or started makes the connection
         * invalid, as on a Mac: its invalidation handler runs once */
        if (!was)
            [self invalidate];
        return;
    }
    NSMutableArray *args = [NSMutableArray array];
    NSMutableArray *replies = [NSMutableArray array];
    for (NSUInteger i = 2; i < [sig numberOfArguments]; i++)
        [args addObject:[self _encodeArgument:inv index:i handler:handler replies:replies]];
    NSNumber *seq = [NSNumber numberWithUnsignedLongLong:++_next];
    NSDictionary *message = @{
        @"k" : @"call",
        @"q" : seq,
        @"sel" : NSStringFromSelector([inv selector]),
        @"t" : type_string(sig),
        @"a" : args,
        @"w" : [NSNumber numberWithBool:sync],
    };
    BOOL sent = [self _write:message];
    if (!sent) {
        [_replies removeObjectsForKeys:replies];
        pthread_mutex_unlock(&_lock);
        [self _fail:handler code:NSXPCConnectionInterrupted now:sync];
        return;
    }
    if (sync) {
        /* until the other side has run it and answered its reply blocks */
        for (;;) {
            BOOL pending = ![_done containsObject:seq] && _fd >= 0;
            for (NSNumber *r in replies)
                if ([_replies objectForKey:r])
                    pending = YES;
            if (!pending || _fd < 0)
                break;
            pthread_cond_wait(&_cond, &_lock);
        }
        [_done removeObject:seq];
    }
    pthread_mutex_unlock(&_lock);
}

/* Called by a forwarding block, on whatever thread called it. */
- (void)_sendReply:(NSNumber *)ident invocation:(NSInvocation *)inv
{
    pthread_mutex_lock(&_lock);
    if (_fd >= 0 && !_invalid) {
        NSMutableArray *args = [NSMutableArray array];
        NSMutableArray *replies = [NSMutableArray array];
        for (NSUInteger i = 1; i < [[inv methodSignature] numberOfArguments]; i++)
            [args addObject:[self _encodeArgument:inv index:i handler:nil replies:replies]];
        [self _write:@{@"k" : @"reply", @"i" : ident, @"a" : args}];
    }
    pthread_mutex_unlock(&_lock);
}

/* A call from the other side, on the connection's queue. */
- (void)_perform:(NSDictionary *)message
{
    SEL sel = NSSelectorFromString([message objectForKey:@"sel"]);
    NSArray *args = [message objectForKey:@"a"];
    const char *types = protocol_types([_exportedInterface protocol], sel, 0);
    if (!types)
        types = [[message objectForKey:@"t"] UTF8String];
    id target = _exportedObject;
    NSMethodSignature *sig = types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
    if (target && sig && [sig numberOfArguments] == [args count] + 2 && [target respondsToSelector:sel]) {
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        BOOL ok = YES;
        for (NSUInteger i = 0; i < [args count] && ok; i++)
            ok = [self _decodeArgument:[args objectAtIndex:i] into:inv index:i + 2];
        if (ok) {
            [inv retainArguments];
            pthread_setspecific(current_key, self);
            @try {
                [inv invokeWithTarget:target];
            } @catch (id e) {
                NSLog(@"XPC: the exported object raised %@ in %s", e, sel_getName(sel));
            }
            pthread_setspecific(current_key, NULL);
        }
    } else if (target) {
        FVerboseOnce([NSString stringWithFormat:@"XPC: %@ doesn't take %s", [target class], sel_getName(sel)]);
    }
    if ([[message objectForKey:@"w"] boolValue]) {
        pthread_mutex_lock(&_lock);
        if (_fd >= 0)
            [self _write:@{@"k" : @"done", @"q" : [message objectForKey:@"q"]}];
        pthread_mutex_unlock(&_lock);
    }
}

/* The other side called one of our reply blocks; on the connection's queue. */
- (void)_reply:(NSDictionary *)message
{
    NSNumber *ident = [message objectForKey:@"i"];
    pthread_mutex_lock(&_lock);
    NSArray *entry = [[[_replies objectForKey:ident] retain] autorelease];
    [_replies removeObjectForKey:ident];
    pthread_cond_broadcast(&_cond);
    pthread_mutex_unlock(&_lock);
    if (!entry)
        return;
    id block = [entry objectAtIndex:0];
    const char *types = _Block_signature(block);
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:types ? types : "v8@?0"];
    NSArray *args = [message objectForKey:@"a"];
    if ([sig numberOfArguments] != [args count] + 1)
        return;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setArgument:&block atIndex:0];
    for (NSUInteger i = 0; i < [args count]; i++)
        if (![self _decodeArgument:[args objectAtIndex:i] into:inv index:i + 1])
            return;
    [inv retainArguments];
    pthread_setspecific(current_key, self);
    [inv _invokeFunction:((struct FBlockLayout *)block)->invoke];
    pthread_setspecific(current_key, NULL);
}

/* The other side went away (or we let go of it). */
- (void)_closed
{
    pthread_mutex_lock(&_lock);
    if (_fd >= 0)
        close(_fd);
    _fd = -1;
    _reading = NO;
    NSArray *pending = [[_replies allValues] retain];
    [_replies removeAllObjects];
    BOOL invalid = _invalid;
    void (^interrupted)(void) = invalid ? nil : [[_interruptionHandler copy] autorelease];
    void (^invalidated)(void) = nil;
    if (_listenerSide && !invalid) {
        _invalid = YES;
        invalidated = [_invalidationHandler autorelease];
        _invalidationHandler = nil;
    }
    pthread_cond_broadcast(&_cond);
    pthread_mutex_unlock(&_lock);
    NSMutableArray *told = [NSMutableArray array];
    for (NSArray *entry in pending) {
        id handler = [entry objectAtIndex:1];
        if (handler == [NSNull null] || [told indexOfObjectIdenticalTo:handler] != NSNotFound)
            continue;
        [told addObject:handler];
        [self _fail:handler code:invalid ? NSXPCConnectionInvalid : NSXPCConnectionInterrupted now:NO];
    }
    [pending release];
    BOOL service = _listenerSide;
    [self retain];
    dispatch_async(_queue, ^{
        if (service) {
            /* a service whose app went away ends, as on a Mac */
            if (invalidated)
                invalidated();
            exit(0);
        }
        if (interrupted)
            interrupted();
        [self release];
    });
}

static void *reader(void *arg)
{
    NSXPCConnection *c = arg;
    [c _readLoop];
    [c release];
    return NULL;
}

- (void)_readLoop
{
    int fd = _fd;
    for (;;) {
        uint32_t len = 0;
        if (fd < 0 || !read_all(fd, &len, 4))
            break;
        void *buf = malloc(len ? len : 1);
        if (!buf || !read_all(fd, buf, len)) {
            free(buf);
            break;
        }
        @autoreleasepool {
            NSData *data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:YES];
            NSDictionary *message = nil;
            @try {
                message = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            } @catch (id e) {
                NSLog(@"XPC: a message couldn't be read: %@", e);
            }
            if (![message isKindOfClass:[NSDictionary class]])
                continue;
            NSString *kind = [message objectForKey:@"k"];
            if ([kind isEqualToString:@"done"]) {
                pthread_mutex_lock(&_lock);
                [_done addObject:[message objectForKey:@"q"]];
                pthread_cond_broadcast(&_cond);
                pthread_mutex_unlock(&_lock);
            } else if ([kind isEqualToString:@"call"] || [kind isEqualToString:@"reply"]) {
                BOOL call = [kind isEqualToString:@"call"];
                [message retain];
                [self retain];
                dispatch_async(_queue, ^{
                    @autoreleasepool {
                        if (call)
                            [self _perform:message];
                        else
                            [self _reply:message];
                    }
                    [message release];
                    [self release];
                });
            }
        }
        pthread_mutex_lock(&_lock);
        BOOL same = _fd == fd;
        pthread_mutex_unlock(&_lock);
        if (!same)
            return;
    }
    pthread_mutex_lock(&_lock);
    BOOL same = _fd == fd;
    pthread_mutex_unlock(&_lock);
    if (same)
        [self _closed];
}

/* Under the lock (or before anyone else can see the connection). */
- (void)_startReading
{
    if (_reading || _fd < 0)
        return;
    _reading = YES;
    pthread_once(&current_once, make_current_key);
    pthread_t t;
    [self retain];
    if (pthread_create(&t, NULL, reader, self)) {
        _reading = NO;
        [self release];
        return;
    }
    pthread_detach(t);
}

- (void)resume
{
    pthread_once(&current_once, make_current_key);
    pthread_mutex_lock(&_lock);
    _resumed = YES;
    if (_listenerSide)
        [self _startReading];
    pthread_mutex_unlock(&_lock);
}
- (void)suspend {}
- (void)activate { [self resume]; }
- (void)invalidate
{
    pthread_mutex_lock(&_lock);
    if (_invalid) {
        pthread_mutex_unlock(&_lock);
        return;
    }
    _invalid = YES;
    void (^invalidated)(void) = [_invalidationHandler autorelease];
    _invalidationHandler = nil;
    [_interruptionHandler release];
    _interruptionHandler = nil;
    if (_fd >= 0)
        shutdown(_fd, SHUT_RDWR);
    else if (!_reading) {
        /* nothing to wait for: answer the replies still waiting now */
        [_replies removeAllObjects];
    }
    pthread_cond_broadcast(&_cond);
    pthread_mutex_unlock(&_lock);
    if (invalidated) {
        [invalidated retain];
        dispatch_async(_queue, ^{
            invalidated();
            [invalidated release];
        });
    }
}
- (int)auditSessionIdentifier { return 0; }
- (pid_t)processIdentifier { return _listenerSide ? getppid() : _pid; }
- (uid_t)effectiveUserIdentifier { return getuid(); }
- (gid_t)effectiveGroupIdentifier { return getgid(); }
- (void)setCodeSigningRequirement:(NSString *)requirement {}
+ (NSXPCConnection *)currentConnection
{
    pthread_once(&current_once, make_current_key);
    return pthread_getspecific(current_key);
}
- (void)scheduleSendBarrierBlock:(void (^)(void))block
{
    if (block)
        dispatch_async(_queue, block);
}
@end

@implementation NSXPCListenerEndpoint
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

static NSXPCListener *service_listener;

@implementation NSXPCListener {
    id<NSXPCListenerDelegate> _delegate;
    NSXPCListenerEndpoint *_endpoint;
}
+ (NSXPCListener *)serviceListener
{
    @synchronized(self) {
        if (!service_listener)
            service_listener = [[NSXPCListener alloc] init];
    }
    return service_listener;
}
+ (NSXPCListener *)anonymousListener { return [[[NSXPCListener alloc] init] autorelease]; }
- (instancetype)initWithMachServiceName:(NSString *)name { return [self init]; }
- (void)dealloc
{
    [_endpoint release];
    [super dealloc];
}
- (id<NSXPCListenerDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSXPCListenerDelegate>)d { _delegate = d; }
- (NSXPCListenerEndpoint *)endpoint
{
    @synchronized(self) {
        if (!_endpoint)
            _endpoint = [[NSXPCListenerEndpoint alloc] init];
    }
    return _endpoint;
}
/* A service's listener: the app that started this program gave it one end
 * of a socket (FERRY_XPC_FD). Its delegate takes the connection, and this
 * never returns, as on a Mac. */
- (void)resume
{
    if (self != service_listener)
        return;
    const char *fdvar = getenv("FERRY_XPC_FD");
    if (!fdvar) {
        FVerboseOnce(@"this XPC service was started by itself, with no app to serve");
        return;
    }
    int fd = atoi(fdvar);
    unsetenv("FERRY_XPC_FD");
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    signal(SIGPIPE, SIG_IGN);
    NSXPCConnection *c = [[NSXPCConnection alloc] _initWithSocket:fd];
    BOOL accepted = NO;
    if ([_delegate respondsToSelector:@selector(listener:shouldAcceptNewConnection:)])
        accepted = [_delegate listener:self shouldAcceptNewConnection:c];
    if (!accepted)
        exit(0);
    dispatch_main();
}
- (void)suspend {}
- (void)activate { [self resume]; }
- (void)invalidate {}
@end

@implementation NSXPCInterface {
    Protocol *_protocol;
    NSMutableDictionary *_classes, *_interfaces;
}
+ (NSXPCInterface *)interfaceWithProtocol:(Protocol *)protocol
{
    NSXPCInterface *i = [[[NSXPCInterface alloc] init] autorelease];
    i->_protocol = protocol;
    return i;
}
- (void)dealloc
{
    [_classes release];
    [_interfaces release];
    [super dealloc];
}
- (Protocol *)protocol { return _protocol; }
- (void)setProtocol:(Protocol *)p { _protocol = p; }
static NSString *slot(SEL sel, NSUInteger arg, BOOL ofReply)
{
    return [NSString stringWithFormat:@"%s %lu %d", sel_getName(sel), (unsigned long)arg, ofReply];
}
- (void)setClasses:(NSSet *)classes forSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
    if (!_classes)
        _classes = [[NSMutableDictionary alloc] init];
    [_classes setObject:[[classes copy] autorelease] forKey:slot(sel, arg, ofReply)];
}
- (NSSet *)classesForSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
    return [_classes objectForKey:slot(sel, arg, ofReply)] ?: [NSSet set];
}
- (void)setInterface:(NSXPCInterface *)ifc forSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
    if (!_interfaces)
        _interfaces = [[NSMutableDictionary alloc] init];
    if (ifc)
        [_interfaces setObject:ifc forKey:slot(sel, arg, ofReply)];
}
- (NSXPCInterface *)interfaceForSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
    return [_interfaces objectForKey:slot(sel, arg, ofReply)];
}
@end
