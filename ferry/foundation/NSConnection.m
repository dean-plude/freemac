/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSConnection, NSDistantObject and NSProtocolChecker
 * (Distributed Objects), written from Apple's public documentation of
 * them. First (freemac 1.226, Ferry 0.50.0) a connection reached only its
 * own program; since freemac 1.NEXT a name registered in one program is
 * reached from another, as MacVim's window app and its Vim processes
 * reach each other.
 *
 * The wire is our own, since both ends are Ferry. A registered name is a
 * local socket of its own (a file in the user's folder of them; one
 * that a program which has gone left behind is taken over), named from
 * the user and a hash of the name. Each program
 * that connects to it gets a connection of its own at both ends, which the
 * two run loops watch. A message is a keyed archive (a dictionary) after
 * its length: a call names the object it is for (0 is the root object),
 * its selector, the method's types and its arguments; a reply carries the
 * result, what out arguments came to, or the exception raised. Objects go
 * by copy (strings, numbers, data, dates, values and collections of them,
 * or anything that can be archived when the method says bycopy) or by
 * reference: a number for the object, which the other side turns into a
 * proxy, and a proxy sent back turns into its object again. While a
 * program waits for a reply it answers the calls that come to it on that
 * connection, so the two can call each other back.
 *
 * Our own code; no Apple code was used. Built without ARC. */
#import "FInternal.h"
#include <objc/runtime.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

NSString *const NSConnectionReplyMode = @"NSConnectionReplyMode";
NSNotificationName const NSConnectionDidDieNotification = @"NSConnectionDidDieNotification";
NSNotificationName const NSConnectionDidInitializeNotification = @"NSConnectionDidInitializeNotification";

static const char *skip_qualifiers(const char *t)
{
    while (*t && strchr("rnNoORV", *t))
        t++;
    return t;
}
static BOOL has_qualifier(const char *t, char q)
{
    for (; *t && strchr("rnNoORV", *t); t++)
        if (*t == q)
            return YES;
    return NO;
}

static const char *protocol_types(Protocol *p, SEL sel, int depth)
{
    if (!p || !sel || depth > 8)
        return NULL;
    for (int required = 1; required >= 0; required--) {
        struct objc_method_description d = protocol_getMethodDescription(p, sel, required, YES);
        if (d.types)
            return d.types;
    }
    unsigned n = 0;
    Protocol *__unsafe_unretained *list = protocol_copyProtocolList(p, &n);
    const char *found = NULL;
    for (unsigned i = 0; i < n && !found; i++)
        found = protocol_types(list[i], sel, depth + 1);
    free(list);
    return found;
}

static NSString *type_string(NSMethodSignature *sig)
{
    NSMutableString *t = [NSMutableString stringWithUTF8String:[sig methodReturnType]];
    for (NSUInteger i = 0; i < [sig numberOfArguments]; i++)
        [t appendFormat:@"%s", [sig getArgumentTypeAtIndex:i]];
    return t;
}

static BOOL write_all(int fd, const void *p, size_t n)
{
    const uint8_t *b = p;
    while (n) {
        ssize_t w = send(fd, b, n, MSG_NOSIGNAL);
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

/* The socket a registered name has: a file in the user's own folder of them
 * (/tmp/ferry-connections-UID), named from a hash of the name. */
static socklen_t name_address(NSString *name, struct sockaddr_un *a)
{
    const char *s = [name UTF8String];
    uint64_t h = 1469598103934665603ull;
    for (; s && *s; s++)
        h = (h ^ (uint8_t)*s) * 1099511628211ull;
    char dir[64];
    snprintf(dir, sizeof dir, "/tmp/ferry-connections-%u", (unsigned)getuid());
    mkdir(dir, 0700);
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    snprintf(a->sun_path, sizeof a->sun_path, "%s/%016llx", dir, (unsigned long long)h);
    a->sun_len = (uint8_t)SUN_LEN(a);
    return (socklen_t)sizeof *a;
}

static int new_socket(void)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd >= 0)
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    return fd;
}

/* A socket listening on the name's address; -1 when another program has the name. */
static int listen_on(NSString *name)
{
    struct sockaddr_un a;
    socklen_t len = name_address(name, &a);
    for (int tries = 0; tries < 2; tries++) {
        int fd = new_socket();
        if (fd < 0)
            return -1;
        if (bind(fd, (struct sockaddr *)&a, len) == 0 && listen(fd, 16) == 0)
            return fd;
        int err = errno;
        close(fd);
        if (err != EADDRINUSE)
            return -1;
        /* a file left by a program that has gone is taken over */
        int probe = new_socket();
        BOOL taken = probe >= 0 && connect(probe, (struct sockaddr *)&a, len) == 0;
        if (probe >= 0)
            close(probe);
        if (taken)
            return -1;
        unlink(a.sun_path);
    }
    return -1;
}

static void stop_listening(NSString *name)
{
    struct sockaddr_un a;
    name_address(name, &a);
    unlink(a.sun_path);
}

/* ---- NSProtocolChecker ----------------------------------------------------------------- */

@implementation NSProtocolChecker {
    NSObject *_target;
    Protocol *_protocol;
}
+ (instancetype)protocolCheckerWithTarget:(NSObject *)target protocol:(Protocol *)protocol
{
    return [[[self alloc] initWithTarget:target protocol:protocol] autorelease];
}
- (instancetype)initWithTarget:(NSObject *)target protocol:(Protocol *)protocol
{
    _target = [target retain];
    _protocol = protocol;
    return self;
}
- (void)dealloc
{
    [_target release];
    [super dealloc];
}
- (Protocol *)protocol { return _protocol; }
- (NSObject *)target { return _target; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    const char *types = protocol_types(_protocol, sel, 0);
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}
- (void)forwardInvocation:(NSInvocation *)inv
{
    if (!protocol_types(_protocol, [inv selector], 0))
        [NSException raise:NSInvalidArgumentException
                    format:@"%s isn't in the protocol %s", sel_getName([inv selector]), protocol_getName(_protocol)];
    [inv invokeWithTarget:_target];
}
- (BOOL)respondsToSelector:(SEL)sel
{
    return protocol_types(_protocol, sel, 0) && [_target respondsToSelector:sel];
}
- (BOOL)conformsToProtocol:(Protocol *)p { return p == _protocol || protocol_conformsToProtocol(_protocol, p); }
@end

/* ---- the connection ------------------------------------------------------------------- */

@interface NSConnection (FerryLink)
- (void)_forward:(NSInvocation *)inv to:(NSNumber *)ident protocol:(Protocol *)proto;
- (const char *)_typesFor:(SEL)sel of:(NSNumber *)ident;
- (void)_forgetProxy:(NSNumber *)ident;
@end

@implementation NSDistantObject {
@public
    NSConnection *_connection;
    NSNumber *_ident; /* the object's number at the other end */
    id _local;        /* or, for one of ours, the object */
    Protocol *_protocol;
    NSMutableDictionary *_signatures;
}
+ (id)proxyWithTarget:(id)target connection:(NSConnection *)connection
{
    return [[[self alloc] initWithTarget:target connection:connection] autorelease];
}
+ (id)proxyWithLocal:(id)target connection:(NSConnection *)connection
{
    return [[[self alloc] initWithLocal:target connection:connection] autorelease];
}
- (instancetype)initWithTarget:(id)target connection:(NSConnection *)connection
{
    _connection = [connection retain];
    _ident = [target isKindOfClass:[NSNumber class]] ? [target retain] : [@0 retain];
    return self;
}
- (instancetype)initWithLocal:(id)target connection:(NSConnection *)connection
{
    _connection = [connection retain];
    _local = [target retain];
    return self;
}
- (void)dealloc
{
    if (_ident)
        [_connection _forgetProxy:_ident];
    [_connection release];
    [_ident release];
    [_local release];
    [_signatures release];
    [super dealloc];
}
- (NSConnection *)connectionForProxy { return _connection; }
- (void)setProtocolForProxy:(Protocol *)proto { _protocol = proto; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    if (_local)
        return [_local methodSignatureForSelector:sel];
    const char *types = protocol_types(_protocol, sel, 0);
    if (types)
        return [NSMethodSignature signatureWithObjCTypes:types];
    NSString *key = NSStringFromSelector(sel);
    NSMethodSignature *sig = [_signatures objectForKey:key];
    if (sig)
        return sig;
    types = [_connection _typesFor:sel of:_ident];
    if (!types)
        [NSException raise:NSInvalidArgumentException
                    format:@"the object at the other end doesn't answer %s", sel_getName(sel)];
    sig = [NSMethodSignature signatureWithObjCTypes:types];
    if (!_signatures)
        _signatures = [[NSMutableDictionary alloc] init];
    [_signatures setObject:sig forKey:key];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)inv
{
    if (_local)
        [inv invokeWithTarget:_local];
    else
        [_connection _forward:inv to:_ident protocol:_protocol];
}
- (BOOL)respondsToSelector:(SEL)sel
{
    if (_local)
        return [_local respondsToSelector:sel];
    if (protocol_types(_protocol, sel, 0))
        return YES;
    @try {
        return [self methodSignatureForSelector:sel] != nil;
    } @catch (id e) {
        return NO;
    }
}
- (BOOL)conformsToProtocol:(Protocol *)p
{
    if (_local)
        return [_local conformsToProtocol:p];
    return _protocol && (p == _protocol || protocol_conformsToProtocol(_protocol, p));
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSDistantObject %p object %@ connection %p>", self, _ident, _connection];
}
@end

@implementation NSConnection {
    id _root, _delegate;
    NSConnection *_peer;   /* for a connection to a name registered in this program, the one registered */
    NSConnection *_parent; /* for one another program made to our name, the connection registered */
    NSMutableArray *_modes, *_names, *_children;
    NSTimeInterval _requestTimeout, _replyTimeout;
    BOOL _invalid, _independent, _threads;
    int _fd, _listen;                /* the socket to the other program; the one listening */
    NSRunLoop *_loop;                /* the run loop watching them */
    NSMutableDictionary *_exported;  /* number -> our object sent by reference */
    NSMutableDictionary *_numbers;   /* our object (pointer) -> its number */
    NSMutableDictionary *_proxies;   /* number -> proxy (not retained) for an object of theirs */
    NSMutableDictionary *_replies;   /* sequence -> a reply that came while waiting for another */
    unsigned long long _next, _seq;
    NSMachPort *_port;
    NSString *_listenName;
    pthread_mutex_t _wlock;
    unsigned _calls, _sent;
}

static NSMutableDictionary *registered(void)
{
    static NSMutableDictionary *names;
    if (!names)
        names = [[NSMutableDictionary alloc] init];
    return names;
}

static NSMutableArray *live(void)
{
    static NSMutableArray *all;
    if (!all)
        all = [[NSMutableArray alloc] init];
    return all;
}

static void link_ready(int fd, short revents, void *ctx);
static void listen_ready(int fd, short revents, void *ctx);

+ (instancetype)defaultConnection
{
    static NSConnection *main;
    @synchronized(self) {
        if (!main)
            main = [[NSConnection alloc] init];
    }
    return main;
}

+ (NSArray *)allConnections
{
    @synchronized(self) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSValue *v in live())
            [a addObject:[v nonretainedObjectValue]];
        return a;
    }
}

- (instancetype)init
{
    if ((self = [super init])) {
        _modes = [[NSMutableArray alloc] initWithObjects:NSDefaultRunLoopMode, nil];
        _names = [[NSMutableArray alloc] init];
        _requestTimeout = _replyTimeout = 1e10;
        _fd = _listen = -1;
        pthread_mutex_init(&_wlock, NULL);
        @synchronized([NSConnection class]) {
            [live() addObject:[NSValue valueWithNonretainedObject:self]];
        }
    }
    return self;
}

- (instancetype)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort { return [self init]; }

/* A connection to another program over a connected socket, watched by the current run loop. */
- (instancetype)_initWithSocket:(int)fd
{
    if ((self = [self init])) {
        _fd = fd;
        _exported = [[NSMutableDictionary alloc] init];
        _numbers = [[NSMutableDictionary alloc] init];
        _proxies = [[NSMutableDictionary alloc] init];
        _replies = [[NSMutableDictionary alloc] init];
        _port = [[NSMachPort alloc] init];
        int big = 1 << 20;
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &big, sizeof big);
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
        _loop = [[NSRunLoop currentRunLoop] retain];
        [_loop _addDescriptor:fd events:POLLIN handler:link_ready context:self];
    }
    return self;
}

+ (instancetype)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
{
    if ([hostName length] && ![hostName isEqualToString:@"localhost"] && ![hostName isEqualToString:@"*"])
        return nil;
    if (!name)
        return nil;
    NSConnection *peer;
    @synchronized(self) {
        peer = [[registered() objectForKey:name] retain];
    }
    if (peer) {
        NSConnection *c = [[[NSConnection alloc] init] autorelease];
        c->_peer = peer;
        return c;
    }
    int fd = new_socket();
    if (fd < 0)
        return nil;
    struct sockaddr_un a;
    socklen_t len = name_address(name, &a);
    if (connect(fd, (struct sockaddr *)&a, len) != 0) {
        close(fd);
        FVerboseOnce([NSString stringWithFormat:@"no program has registered the connection name %@", name]);
        return nil;
    }
    return [[[NSConnection alloc] _initWithSocket:fd] autorelease];
}

+ (instancetype)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
                            usingNameServer:(NSPortNameServer *)server
{
    return [self connectionWithRegisteredName:name host:hostName];
}

+ (id)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
{
    return [[self connectionWithRegisteredName:name host:hostName] rootProxy];
}

+ (id)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
                              usingNameServer:(NSPortNameServer *)server
{
    return [self rootProxyForConnectionWithRegisteredName:name host:hostName];
}

+ (instancetype)serviceConnectionWithName:(NSString *)name rootObject:(id)root
{
    NSConnection *c = [[[NSConnection alloc] init] autorelease];
    [c setRootObject:root];
    return [c registerName:name] ? c : nil;
}

+ (id)currentConversation { return nil; }

- (void)dealloc
{
    [self invalidate];
    @synchronized([NSConnection class]) {
        NSUInteger i = 0;
        for (NSValue *v in live()) {
            if ([v nonretainedObjectValue] == self)
                break;
            i++;
        }
        if (i < [live() count])
            [live() removeObjectAtIndex:i];
    }
    [_root release];
    [_peer release];
    [_modes release];
    [_names release];
    [_children release];
    [_exported release];
    [_numbers release];
    [_proxies release];
    [_replies release];
    [_port release];
    [_listenName release];
    [_loop release];
    pthread_mutex_destroy(&_wlock);
    [super dealloc];
}

- (id)rootObject { return _root ? _root : [_parent rootObject]; }
- (void)setRootObject:(id)root
{
    [root retain];
    [_root release];
    _root = root;
}
- (id)rootProxy
{
    if (_peer)
        return [_peer isValid] ? [_peer rootObject] : nil;
    if (_fd < 0 || _invalid)
        return nil;
    return [self _decodeObject:@{@"l" : @0}];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSTimeInterval)requestTimeout { return _requestTimeout; }
- (void)setRequestTimeout:(NSTimeInterval)t { _requestTimeout = t; }
- (NSTimeInterval)replyTimeout { return _replyTimeout; }
- (void)setReplyTimeout:(NSTimeInterval)t { _replyTimeout = t; }
- (BOOL)independentConversationQueueing { return _independent; }
- (void)setIndependentConversationQueueing:(BOOL)flag { _independent = flag; }
- (BOOL)isValid { return !_invalid; }
- (NSArray *)requestModes { return [[_modes copy] autorelease]; }
- (NSArray *)remoteObjects
{
    if (_fd < 0)
        return [self rootProxy] ? @[ [self rootProxy] ] : @[];
    NSMutableArray *a = [NSMutableArray array];
    for (NSValue *v in [_proxies allValues])
        [a addObject:[v nonretainedObjectValue]];
    return a;
}
- (NSArray *)localObjects
{
    NSMutableArray *a = [NSMutableArray arrayWithArray:[_exported allValues]];
    if ([self rootObject])
        [a insertObject:[self rootObject] atIndex:0];
    return a;
}
- (NSPort *)receivePort { return _port; }
- (NSPort *)sendPort { return _port; }

/* NO when the name is another connection's, here or in another program. */
- (BOOL)registerName:(NSString *)name
{
    if (_invalid)
        return NO;
    @synchronized([NSConnection class]) {
        if (!name) {
            for (NSString *n in _names)
                [registered() removeObjectForKey:n];
            [_names removeAllObjects];
            if (_listen >= 0) {
                [_loop _removeDescriptor:_listen context:self];
                close(_listen);
                stop_listening(_listenName);
                _listen = -1;
            }
            return YES;
        }
        NSConnection *other = [registered() objectForKey:name];
        if (other && other != self)
            return NO;
        if (!other) {
            /* one name a connection listens on: the newest */
            int fd = listen_on(name);
            if (fd < 0)
                return NO;
            if (_listen >= 0) {
                [_loop _removeDescriptor:_listen context:self];
                close(_listen);
                stop_listening(_listenName);
            }
            _listen = fd;
            [_listenName release];
            _listenName = [name copy];
            if (!_loop)
                _loop = [[NSRunLoop currentRunLoop] retain];
            [_loop _addDescriptor:fd events:POLLIN handler:listen_ready context:self];
        }
        [registered() setObject:self forKey:name];
        if (![_names containsObject:name])
            [_names addObject:name];
    }
    return YES;
}

- (BOOL)registerName:(NSString *)name withNameServer:(NSPortNameServer *)server { return [self registerName:name]; }
- (void)addRequestMode:(NSString *)mode
{
    if (mode && ![_modes containsObject:mode])
        [_modes addObject:mode];
}
- (void)removeRequestMode:(NSString *)mode { [_modes removeObject:mode]; }
/* Messages from another program are answered on the run loop the connection was made on. */
- (void)addRunLoop:(NSRunLoop *)runloop {}
- (void)removeRunLoop:(NSRunLoop *)runloop {}
- (void)runInNewThread {}
- (void)enableMultipleThreads { _threads = YES; }
- (BOOL)multipleThreadsEnabled { return _threads; }

- (void)invalidate
{
    if (_invalid)
        return;
    _invalid = YES;
    [[self retain] autorelease];
    @synchronized([NSConnection class]) {
        for (NSString *n in _names)
            if ([registered() objectForKey:n] == self)
                [registered() removeObjectForKey:n];
        [_names removeAllObjects];
    }
    if (_listen >= 0) {
        [_loop _removeDescriptor:_listen context:self];
        close(_listen);
        stop_listening(_listenName);
        _listen = -1;
    }
    if (_fd >= 0) {
        [_loop _removeDescriptor:_fd context:self];
        shutdown(_fd, SHUT_RDWR);
        close(_fd);
        _fd = -1;
    }
    NSArray *children = [[_children copy] autorelease];
    for (NSConnection *c in children)
        [c invalidate];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSConnectionDidDieNotification object:self];
    if (_parent) {
        [_parent->_children removeObjectIdenticalTo:self];
        _parent = nil;
    }
    [_exported removeAllObjects];
    [_numbers removeAllObjects];
}

- (NSDictionary *)statistics
{
    return @{@"NSConnectionRepliesReceived" : @(_sent), @"NSConnectionRequestsReceived" : @(_calls)};
}

/* ---- another program connected to our name -------------------------------------------- */

- (void)_accept
{
    int fd = accept(_listen, NULL, NULL);
    if (fd < 0)
        return;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    NSConnection *child = [[NSConnection alloc] _initWithSocket:fd];
    child->_parent = self;
    [child->_modes setArray:_modes];
    child->_requestTimeout = _requestTimeout;
    child->_replyTimeout = _replyTimeout;
    if ([_delegate respondsToSelector:@selector(connection:shouldMakeNewConnection:)] &&
        ![_delegate connection:self shouldMakeNewConnection:child]) {
        child->_parent = nil;
        [child invalidate];
        [child release];
        return;
    }
    if (!_children)
        _children = [[NSMutableArray alloc] init];
    [_children addObject:child];
    [child release];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSConnectionDidInitializeNotification object:child];
}

static void listen_ready(int fd, short revents, void *ctx)
{
    NSConnection *c = [(NSConnection *)ctx retain];
    @autoreleasepool {
        [c _accept];
    }
    [c release];
}

/* ---- values as they go across ---------------------------------------------------------- */

static BOOL is_value(id v)
{
    static Class kinds[8];
    if (!kinds[0]) {
        kinds[1] = [NSNumber class];
        kinds[2] = [NSData class];
        kinds[3] = [NSDate class];
        kinds[4] = [NSNull class];
        kinds[5] = [NSValue class];
        kinds[6] = [NSURL class];
        kinds[0] = [NSString class];
    }
    for (int i = 0; i < 7; i++)
        if ([v isKindOfClass:kinds[i]])
            return YES;
    return NO;
}

/* Collections go by copy too when everything in them can. */
static BOOL copies_whole(id v)
{
    if (is_value(v))
        return YES;
    if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSSet class]]) {
        for (id o in v)
            if (!copies_whole(o))
                return NO;
        return YES;
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        for (id k in v)
            if (!copies_whole(k) || !copies_whole([v objectForKey:k]))
                return NO;
        return YES;
    }
    return NO;
}

/* An object as it goes across: @{n} for nil, @{o: the object} by copy,
 * @{l: number} for one of ours by reference, @{r: number} for one of the
 * other side's, or @{A: [...]} / @{D: [keys], V: [values]} for a
 * collection holding objects that go by reference. */
- (id)_encodeObject:(id)v bycopy:(BOOL)bycopy
{
    if (!v)
        return @{@"n" : @YES};
    if ([v isProxy] && object_getClass(v) == [NSDistantObject class]) {
        NSDistantObject *p = v;
        if (p->_connection == self && p->_ident)
            return @{@"r" : p->_ident};
        if (p->_local)
            v = p->_local;
    } else if (![v isProxy]) {
        if (copies_whole(v))
            return @{@"o" : v};
        if (bycopy && [v conformsToProtocol:@protocol(NSCoding)])
            return @{@"o" : v};
        if ([v isKindOfClass:[NSArray class]]) {
            NSMutableArray *a = [NSMutableArray array];
            for (id o in v)
                [a addObject:[self _encodeObject:o bycopy:bycopy]];
            return @{@"A" : a};
        }
        if ([v isKindOfClass:[NSDictionary class]]) {
            NSMutableArray *k = [NSMutableArray array], *o = [NSMutableArray array];
            for (id key in v) {
                [k addObject:[self _encodeObject:key bycopy:bycopy]];
                [o addObject:[self _encodeObject:[v objectForKey:key] bycopy:bycopy]];
            }
            return @{@"D" : k, @"V" : o};
        }
    }
    NSValue *key = [NSValue valueWithPointer:v];
    NSNumber *ident = [_numbers objectForKey:key];
    if (!ident) {
        ident = [NSNumber numberWithUnsignedLongLong:++_next];
        [_numbers setObject:ident forKey:key];
        [_exported setObject:v forKey:ident];
    }
    return @{@"l" : ident};
}

- (id)_decodeObject:(id)e
{
    if (![e isKindOfClass:[NSDictionary class]])
        return nil;
    id v;
    if ((v = [e objectForKey:@"o"]))
        return v;
    if ((v = [e objectForKey:@"l"])) {
        NSDistantObject *p = [[_proxies objectForKey:v] nonretainedObjectValue];
        if (p)
            return [[p retain] autorelease];
        p = [[[NSDistantObject alloc] initWithTarget:v connection:self] autorelease];
        [_proxies setObject:[NSValue valueWithNonretainedObject:p] forKey:v];
        return p;
    }
    if ((v = [e objectForKey:@"r"]))
        return [v unsignedLongLongValue] == 0 ? [self rootObject] : [_exported objectForKey:v];
    if ((v = [e objectForKey:@"A"])) {
        NSMutableArray *a = [NSMutableArray array];
        for (id o in v) {
            id d = [self _decodeObject:o];
            [a addObject:d ? d : [NSNull null]];
        }
        return a;
    }
    if ((v = [e objectForKey:@"D"])) {
        NSArray *vals = [e objectForKey:@"V"];
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < [v count] && i < [vals count]; i++) {
            id k = [self _decodeObject:[v objectAtIndex:i]], o = [self _decodeObject:[vals objectAtIndex:i]];
            if (k && o)
                [d setObject:o forKey:k];
        }
        return d;
    }
    return nil;
}

- (void)_forgetProxy:(NSNumber *)ident { [_proxies removeObjectForKey:ident]; }

/* A value of a type at p: @{n}, an object's form, @{c: class}, @{s: selector},
 * @{z: a C string's bytes} or @{d: its bytes}. */
- (id)_encodeValue:(const void *)p type:(const char *)full
{
    const char *t = skip_qualifiers(full);
    switch (t[0]) {
    case '@':
        return [self _encodeObject:*(id *)p bycopy:has_qualifier(full, 'O')];
    case '#': {
        Class c = *(Class *)p;
        return c ? @{@"c" : NSStringFromClass(c)} : @{@"n" : @YES};
    }
    case ':': {
        SEL s = *(SEL *)p;
        return s ? @{@"s" : NSStringFromSelector(s)} : @{@"n" : @YES};
    }
    case '*': {
        const char *s = *(const char **)p;
        return s ? @{@"z" : [NSData dataWithBytes:s length:strlen(s) + 1]} : @{@"n" : @YES};
    }
    default: {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(t, &size, NULL);
        return @{@"d" : [NSData dataWithBytes:p length:size]};
    }
    }
}

/* Into p, which holds a value of the type; NO when it doesn't fit. */
- (BOOL)_decodeValue:(id)e into:(void *)p type:(const char *)full
{
    const char *t = skip_qualifiers(full);
    NSUInteger size = 0;
    NSGetSizeAndAlignment(t, &size, NULL);
    if (![e isKindOfClass:[NSDictionary class]] || [e objectForKey:@"n"]) {
        memset(p, 0, size);
        return YES;
    }
    id v;
    switch (t[0]) {
    case '@':
        *(id *)p = [self _decodeObject:e];
        return YES;
    case '#':
        *(Class *)p = NSClassFromString([e objectForKey:@"c"]);
        return YES;
    case ':':
        *(SEL *)p = NSSelectorFromString([e objectForKey:@"s"]);
        return YES;
    case '*':
        v = [e objectForKey:@"z"];
        *(const char **)p = [v bytes];
        return YES;
    default:
        v = [e objectForKey:@"d"];
        if (![v isKindOfClass:[NSData class]] || [v length] != size)
            return NO;
        memcpy(p, [v bytes], size);
        return YES;
    }
}

/* Whether an argument of this type is a pointer whose value goes across. */
static BOOL by_pointer(const char *full)
{
    const char *t = skip_qualifiers(full);
    return t[0] == '^' && t[1] && t[1] != 'v' && t[1] != '?';
}

/* ---- the wire ------------------------------------------------------------------------ */

- (BOOL)_send:(NSDictionary *)message
{
    NSData *data = nil;
    @try {
        data = [NSKeyedArchiver archivedDataWithRootObject:message requiringSecureCoding:NO error:NULL];
    } @catch (id e) {
        data = nil;
    }
    if (!data) {
        FVerboseOnce([NSString stringWithFormat:@"a Distributed Objects message (%@) couldn't be archived",
                                                [message objectForKey:@"s"]]);
        return NO;
    }
    pthread_mutex_lock(&_wlock);
    uint32_t len = (uint32_t)[data length];
    BOOL ok = _fd >= 0 && write_all(_fd, &len, 4) && write_all(_fd, [data bytes], len);
    pthread_mutex_unlock(&_wlock);
    return ok;
}

/* One message, once the socket is readable; nil at its end. */
- (NSDictionary *)_receive
{
    uint32_t len = 0;
    if (_fd < 0 || !read_all(_fd, &len, 4) || len > (1u << 30))
        return nil;
    NSMutableData *data = [NSMutableData dataWithLength:len];
    if (!read_all(_fd, [data mutableBytes], len))
        return nil;
    id m = nil;
    @try {
        NSKeyedUnarchiver *u = [[[NSKeyedUnarchiver alloc] initForReadingFromData:data error:NULL] autorelease];
        [u setRequiresSecureCoding:NO];
        m = [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    } @catch (id e) {
        m = nil;
    }
    return [m isKindOfClass:[NSDictionary class]] ? m : @{};
}

/* Handles one message; NO when the connection is over. */
- (BOOL)_handleOne
{
    NSDictionary *m = [self _receive];
    if (!m) {
        [self invalidate];
        return NO;
    }
    NSString *t = [m objectForKey:@"t"];
    if ([t isEqualToString:@"r"]) {
        id q = [m objectForKey:@"q"];
        if (q)
            [_replies setObject:m forKey:q];
    } else if ([t isEqualToString:@"c"]) {
        [self _perform:m];
    }
    return YES;
}

static void link_ready(int fd, short revents, void *ctx)
{
    NSConnection *c = [(NSConnection *)ctx retain];
    @autoreleasepool {
        if (revents & (POLLIN | POLLHUP | POLLERR))
            [c _handleOne];
    }
    [c release];
}

/* Waits for the reply to a call, answering the calls that come meanwhile. */
- (NSDictionary *)_waitFor:(NSNumber *)seq
{
    double limit = _replyTimeout > 0 && _replyTimeout < 1e9 ? _replyTimeout : -1;
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (;;) {
        NSDictionary *r = [_replies objectForKey:seq];
        if (r) {
            [[r retain] autorelease];
            [_replies removeObjectForKey:seq];
            return r;
        }
        if (_fd < 0 || _invalid)
            [NSException raise:NSInvalidReceivePortException
                        format:@"the connection went away while waiting for a reply"];
        int ms = -1;
        if (limit >= 0) {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            double gone = (now.tv_sec - start.tv_sec) + (now.tv_nsec - start.tv_nsec) / 1e9;
            if (gone >= limit)
                [NSException raise:NSPortTimeoutException format:@"no reply came in %g seconds", limit];
            ms = (int)((limit - gone) * 1000) + 1;
        }
        struct pollfd p = {_fd, POLLIN, 0};
        int n = poll(&p, 1, ms);
        if (n < 0 && errno == EINTR)
            continue;
        if (n > 0) {
            @autoreleasepool {
                [self _handleOne];
            }
        }
    }
}

/* ---- calls going out ------------------------------------------------------------------- */

- (const char *)_typesFor:(SEL)sel of:(NSNumber *)ident
{
    if (_fd < 0 || _invalid)
        [NSException raise:NSInvalidSendPortException format:@"the connection is no longer valid"];
    NSNumber *seq = [NSNumber numberWithUnsignedLongLong:++_seq];
    if (![self _send:@{@"t" : @"c", @"q" : seq, @"o" : ident, @"s" : NSStringFromSelector(sel), @"k" : @YES,
                       @"w" : @YES}])
        [NSException raise:NSInvalidSendPortException format:@"the message couldn't be sent"];
    NSDictionary *r = [self _waitFor:seq];
    NSString *types = [r objectForKey:@"v"];
    return [types isKindOfClass:[NSString class]] ? [types UTF8String] : NULL;
}

- (void)_forward:(NSInvocation *)inv to:(NSNumber *)ident protocol:(Protocol *)proto
{
    if (_fd < 0 || _invalid)
        [NSException raise:NSInvalidSendPortException format:@"the connection is no longer valid"];
    NSMethodSignature *sig = [inv methodSignature];
    NSUInteger count = [sig numberOfArguments];
    NSMutableArray *args = [NSMutableArray array];
    for (NSUInteger i = 2; i < count; i++) {
        const char *type = [sig getArgumentTypeAtIndex:i];
        NSUInteger size = 0;
        NSGetSizeAndAlignment(skip_qualifiers(type), &size, NULL);
        void *buf = calloc(1, size > 16 ? size : 16);
        [inv getArgument:buf atIndex:i];
        if (by_pointer(type)) {
            void *ptr = *(void **)buf;
            if (!ptr || has_qualifier(type, 'o'))
                [args addObject:@{@"n" : @YES}];
            else {
                char inner[256];
                snprintf(inner, sizeof inner, "%s%s", has_qualifier(type, 'O') ? "O" : "", skip_qualifiers(type) + 1);
                [args addObject:[self _encodeValue:ptr type:inner]];
            }
        } else {
            [args addObject:[self _encodeValue:buf type:type]];
        }
        free(buf);
    }
    BOOL oneway = [sig isOneway];
    NSNumber *seq = [NSNumber numberWithUnsignedLongLong:++_seq];
    NSDictionary *call = @{
        @"t" : @"c",
        @"q" : seq,
        @"o" : ident,
        @"s" : NSStringFromSelector([inv selector]),
        @"y" : type_string(sig),
        @"a" : args,
        @"w" : @(!oneway)
    };
    _sent++;
    if (![self _send:call]) {
        [self invalidate];
        [NSException raise:NSInvalidSendPortException format:@"the message couldn't be sent"];
    }
    if (oneway)
        return;
    NSDictionary *r = [self _waitFor:seq];
    NSString *exc = [r objectForKey:@"e"];
    if (exc)
        [[NSException exceptionWithName:exc reason:[r objectForKey:@"m"] userInfo:nil] raise];
    const char *rtype = [sig methodReturnType];
    if (skip_qualifiers(rtype)[0] != 'v') {
        NSUInteger size = [sig methodReturnLength];
        void *buf = calloc(1, size > 16 ? size : 16);
        if ([self _decodeValue:[r objectForKey:@"v"] into:buf type:rtype])
            [inv setReturnValue:buf];
        free(buf);
    }
    NSDictionary *outs = [r objectForKey:@"x"];
    for (NSString *k in outs) {
        NSUInteger i = (NSUInteger)[k integerValue];
        if (i < 2 || i >= count)
            continue;
        const char *type = [sig getArgumentTypeAtIndex:i];
        if (!by_pointer(type))
            continue;
        void *ptr = NULL;
        [inv getArgument:&ptr atIndex:i];
        if (ptr)
            [self _decodeValue:[outs objectForKey:k] into:ptr type:skip_qualifiers(type) + 1];
    }
}

/* ---- calls coming in ------------------------------------------------------------------- */

- (void)_perform:(NSDictionary *)m
{
    _calls++;
    NSNumber *seq = [m objectForKey:@"q"];
    NSNumber *ident = [m objectForKey:@"o"];
    BOOL wants = [[m objectForKey:@"w"] boolValue];
    SEL sel = NSSelectorFromString([m objectForKey:@"s"]);
    id target = [ident unsignedLongLongValue] == 0 ? [self rootObject] : [_exported objectForKey:ident];
    NSMutableDictionary *reply = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"r", @"t", seq, @"q", nil];
    if ([[m objectForKey:@"k"] boolValue]) {
        /* the types of a method, for a proxy with no protocol */
        NSMethodSignature *sig = nil;
        @try {
            sig = [target methodSignatureForSelector:sel];
        } @catch (id e) {
            sig = nil;
        }
        if (sig)
            [reply setObject:type_string(sig) forKey:@"v"];
        [self _send:reply];
        return;
    }
    NSMutableArray *buffers = [NSMutableArray array];
    @try {
        if (!target)
            [NSException raise:NSInvalidArgumentException format:@"no object %@ on this connection", ident];
        if ([target isProxy] && object_getClass(target) == [NSProtocolChecker class]) {
            NSProtocolChecker *checker = target;
            if (!protocol_types([checker protocol], sel, 0))
                [NSException raise:NSInvalidArgumentException format:@"%s isn't in the protocol %s",
                                                                       sel_getName(sel),
                                                                       protocol_getName([checker protocol])];
            target = [checker target];
        }
        NSString *types = [m objectForKey:@"y"];
        NSMethodSignature *sig = [types isKindOfClass:[NSString class]]
                                     ? [NSMethodSignature signatureWithObjCTypes:[types UTF8String]]
                                     : [target methodSignatureForSelector:sel];
        if (!sig)
            [NSException raise:NSInvalidArgumentException format:@"%s isn't a method here", sel_getName(sel)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        NSArray *args = [m objectForKey:@"a"];
        NSUInteger count = [sig numberOfArguments];
        for (NSUInteger i = 2; i < count; i++) {
            id e = i - 2 < [args count] ? [args objectAtIndex:i - 2] : nil;
            const char *type = [sig getArgumentTypeAtIndex:i];
            if (by_pointer(type)) {
                const char *inner = skip_qualifiers(type) + 1;
                NSUInteger size = 0;
                NSGetSizeAndAlignment(inner, &size, NULL);
                NSMutableData *box = [NSMutableData dataWithLength:size > 16 ? size : 16];
                [buffers addObject:box];
                [self _decodeValue:e into:[box mutableBytes] type:inner];
                void *ptr = [box mutableBytes];
                [inv setArgument:&ptr atIndex:i];
                continue;
            }
            NSUInteger size = 0;
            NSGetSizeAndAlignment(skip_qualifiers(type), &size, NULL);
            void *buf = calloc(1, size > 16 ? size : 16);
            if (![self _decodeValue:e into:buf type:type]) {
                free(buf);
                [NSException raise:NSInvalidArgumentException format:@"argument %lu of %s doesn't fit",
                                                                       (unsigned long)i, sel_getName(sel)];
            }
            [inv setArgument:buf atIndex:i];
            free(buf);
        }
        [inv retainArguments];
        [inv invokeWithTarget:target];
        if (!wants)
            return;
        const char *rtype = [sig methodReturnType];
        if (skip_qualifiers(rtype)[0] != 'v') {
            NSUInteger size = [sig methodReturnLength];
            void *buf = calloc(1, size > 16 ? size : 16);
            [inv getReturnValue:buf];
            [reply setObject:[self _encodeValue:buf type:rtype] forKey:@"v"];
            free(buf);
        }
        NSMutableDictionary *outs = [NSMutableDictionary dictionary];
        NSUInteger b = 0;
        for (NSUInteger i = 2; i < count; i++) {
            const char *type = [sig getArgumentTypeAtIndex:i];
            if (!by_pointer(type))
                continue;
            NSMutableData *box = [buffers objectAtIndex:b++];
            if (has_qualifier(type, 'n'))
                continue;
            char inner[256];
            snprintf(inner, sizeof inner, "%s%s", has_qualifier(type, 'O') ? "O" : "", skip_qualifiers(type) + 1);
            [outs setObject:[self _encodeValue:[box mutableBytes] type:inner]
                     forKey:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
        }
        if ([outs count])
            [reply setObject:outs forKey:@"x"];
    } @catch (NSException *e) {
        if (!wants) {
            FVerboseOnce([NSString stringWithFormat:@"a oneway Distributed Objects message %s raised %@: %@",
                                                    sel_getName(sel), [e name], [e reason]]);
            return;
        }
        [reply setObject:[e name] ? [e name] : NSGenericException forKey:@"e"];
        if ([e reason])
            [reply setObject:[e reason] forKey:@"m"];
    }
    if (![self _send:reply]) {
        /* a result that can't be archived goes back as an exception */
        NSDictionary *fail = @{
            @"t" : @"r",
            @"q" : seq,
            @"e" : NSInvalidArgumentException,
            @"m" : [NSString stringWithFormat:@"the result of %s couldn't be sent", sel_getName(sel)]
        };
        [self _send:fail];
    }
}
@end
