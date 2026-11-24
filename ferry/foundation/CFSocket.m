/* SPDX-License-Identifier: GPL-3.0-or-later
 * Run loop sources and CFSocket, served from Foundation's file as the rest
 * of CoreFoundation is. Our own code, written from Apple's public API
 * documentation of CFRunLoopSource and CFSocket.
 *
 * A source the program makes (version 0) is performed on each run loop it
 * was added to once it is signalled; while added, it keeps that loop
 * running. A CFSocket's source watches the socket's descriptor in the run
 * loops it is added to (NSRunLoop's descriptor sources) and calls the
 * socket's callback on that loop's thread: read, accept (the new socket
 * accepted for it), data (what arrived, read for it; empty at the end),
 * connect (a background connection finished) and write. Version 1 sources
 * (Mach ports) are not offered: there are no Mach ports here. */
#import "FInternal.h"
#include <CoreFoundation/CFSocket.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

void FVerboseOnce(NSString *message)
{
    static NSMutableSet *said;
    const char *v = getenv("FERRY_VERBOSE");
    if (!v || !*v)
        return;
    @synchronized([NSRunLoop class]) {
        if (!said)
            said = [[NSMutableSet alloc] init];
        if ([said containsObject:message])
            return;
        [said addObject:message];
    }
    fprintf(stderr, "ferry: %s\n", [message UTF8String]);
}

/* ---- run loop sources ----------------------------------------------------------------- */

@interface FRunLoopSource : NSObject {
@public
    CFIndex order;
    CFRunLoopSourceContext context;
    BOOL valid, signalled;
    NSMutableArray *places; /* [loop, mode] pairs */
    /* a CFSocket's source: the socket watches its descriptor in each loop */
    id owner;
    void (*added)(id owner, NSRunLoop *loop);
    void (*removed)(id owner, NSRunLoop *loop);
}
@end

static NSUInteger loop_count(FRunLoopSource *s, NSRunLoop *loop)
{
    NSUInteger n = 0;
    for (NSArray *p in s->places)
        n += [p objectAtIndex:0] == loop;
    return n;
}

@implementation FRunLoopSource
- (void)dealloc
{
    [owner release];
    [places release];
    if (context.release && context.info)
        context.release(context.info);
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CFRunLoopSource %p order %ld valid %d>", self, (long)order, valid];
}
- (void)addTo:(NSRunLoop *)loop mode:(NSString *)mode
{
    NSArray *pair = [NSArray arrayWithObjects:loop, mode ?: @"", nil];
    BOOL first;
    @synchronized(self) {
        if (!valid || [places containsObject:pair])
            return;
        first = loop_count(self, loop) == 0;
        [places addObject:pair];
    }
    if (first) {
        if (added)
            added(owner, loop);
        else
            [loop _addKeepAlive];
    }
    if (context.schedule)
        context.schedule(context.info, (CFRunLoopRef)loop, (CFRunLoopMode)mode);
    BOOL pending;
    @synchronized(self) {
        pending = signalled;
    }
    if (pending)
        [self fireOn:loop];
}
- (void)removeFrom:(NSRunLoop *)loop mode:(NSString *)mode
{
    NSArray *pair = [NSArray arrayWithObjects:loop, mode ?: @"", nil];
    BOOL last;
    [loop retain];
    @synchronized(self) {
        NSUInteger i = [places indexOfObject:pair];
        if (i == NSNotFound) {
            [loop release];
            return;
        }
        [places removeObjectAtIndex:i];
        last = loop_count(self, loop) == 0;
    }
    if (context.cancel)
        context.cancel(context.info, (CFRunLoopRef)loop, (CFRunLoopMode)mode);
    if (last) {
        if (removed)
            removed(owner, loop);
        else
            [loop _removeKeepAlive];
    }
    [loop release];
}
- (BOOL)isIn:(NSRunLoop *)loop mode:(NSString *)mode
{
    @synchronized(self) {
        return [places containsObject:[NSArray arrayWithObjects:loop, mode ?: @"", nil]];
    }
}
- (void)invalidate
{
    NSArray *all;
    @synchronized(self) {
        if (!valid)
            return;
        all = [[places copy] autorelease];
    }
    for (NSArray *p in all)
        [self removeFrom:[p objectAtIndex:0] mode:[p objectAtIndex:1]];
    id was;
    @synchronized(self) {
        valid = NO;
        was = owner;
        owner = nil;
    }
    [was release];
}
/* Performs a signalled source on loop, once for one signal. */
- (void)fireOn:(NSRunLoop *)loop
{
    [loop performBlock:^{
      BOOL go;
      @synchronized(self) {
          go = valid && signalled && loop_count(self, loop) > 0;
          if (go)
              signalled = NO;
      }
      if (go && context.perform)
          context.perform(context.info);
    }];
}
- (void)signal
{
    NSMutableArray *loops = [NSMutableArray array];
    @synchronized(self) {
        if (!valid)
            return;
        signalled = YES;
        for (NSArray *p in places)
            if ([loops indexOfObjectIdenticalTo:[p objectAtIndex:0]] == NSNotFound)
                [loops addObject:[p objectAtIndex:0]];
    }
    for (NSRunLoop *loop in loops)
        [self fireOn:loop];
}
@end

static FRunLoopSource *new_source(CFIndex order, const CFRunLoopSourceContext *context)
{
    FRunLoopSource *s = [[FRunLoopSource alloc] init];
    s->order = order;
    s->valid = YES;
    s->places = [[NSMutableArray alloc] init];
    if (context) {
        s->context = *context;
        if (context->retain && context->info)
            s->context.info = (void *)context->retain(context->info);
    }
    return s;
}

#define SRC(x) ((FRunLoopSource *)(x))

CFTypeID CFRunLoopSourceGetTypeID(void) { return 0x46520001; }
CFRunLoopSourceRef CFRunLoopSourceCreate(CFAllocatorRef allocator, CFIndex order, CFRunLoopSourceContext *context)
{
    if (!context || context->version != 0) {
        FVerboseOnce(@"CFRunLoopSourceCreate: only version 0 sources are offered (no Mach ports here)");
        return NULL;
    }
    return (CFRunLoopSourceRef)new_source(order, context);
}
CFIndex CFRunLoopSourceGetOrder(CFRunLoopSourceRef source) { return SRC(source)->order; }
void CFRunLoopSourceGetContext(CFRunLoopSourceRef source, CFRunLoopSourceContext *context)
{
    if (context)
        *context = SRC(source)->context;
}
void CFRunLoopSourceSignal(CFRunLoopSourceRef source) { [SRC(source) signal]; }
void CFRunLoopSourceInvalidate(CFRunLoopSourceRef source) { [SRC(source) invalidate]; }
Boolean CFRunLoopSourceIsValid(CFRunLoopSourceRef source)
{
    @synchronized(SRC(source)) {
        return SRC(source)->valid;
    }
}
void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFRunLoopMode mode)
{
    if (rl && source)
        [SRC(source) addTo:(NSRunLoop *)rl mode:(NSString *)mode];
}
void CFRunLoopRemoveSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFRunLoopMode mode)
{
    if (rl && source)
        [SRC(source) removeFrom:(NSRunLoop *)rl mode:(NSString *)mode];
}
Boolean CFRunLoopContainsSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFRunLoopMode mode)
{
    return rl && source && [SRC(source) isIn:(NSRunLoop *)rl mode:(NSString *)mode];
}

/* ---- CFSocket ---------------------------------------------------------------------------- */

@interface FSocket : NSObject {
@public
    int fd;
    CFOptionFlags types, flags;
    BOOL readOn, writeOn, connectOn; /* the callbacks now enabled */
    BOOL connecting, valid;
    CFSocketCallBack callout;
    CFSocketContext context;
    FRunLoopSource *source;
    NSMutableArray *loops; /* the run loops its source is in */
}
@end

/* The valid CFSocket of each descriptor: CFSocketCreateWithNative gives it back. */
static FSocket **by_fd;
static int by_fd_size;
static os_unfair_lock by_fd_lock = OS_UNFAIR_LOCK_INIT;

static void socket_ready(int fd, short revents, void *ctx);

@implementation FSocket
- (void)dealloc
{
    [source release];
    [loops release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"<CFSocket %p fd %d valid %d>", self, fd, valid]; }
/* What its descriptor is watched for in each loop, from the callbacks enabled now. */
- (void)update
{
    short events = 0;
    NSArray *now;
    @synchronized(self) {
        if (!valid)
            return;
        if (readOn && (types & 3))
            events |= POLLIN;
        if (connecting || (writeOn && (types & kCFSocketWriteCallBack)))
            events |= POLLOUT;
        now = [[loops copy] autorelease];
    }
    for (NSRunLoop *loop in now)
        [loop _addDescriptor:fd events:events handler:socket_ready context:self];
}
@end

static void socket_added(id owner, NSRunLoop *loop)
{
    FSocket *s = owner;
    @synchronized(s) {
        [s->loops addObject:loop];
    }
    [s update];
}
static void socket_removed(id owner, NSRunLoop *loop)
{
    FSocket *s = owner;
    @synchronized(s) {
        [s->loops removeObjectIdenticalTo:loop];
    }
    [loop _removeDescriptor:s->fd context:s];
}

static void call(FSocket *s, CFSocketCallBackType type, CFDataRef address, const void *data)
{
    if (s->callout && s->valid)
        s->callout((CFSocketRef)s, type, address, data, s->context.info);
}

static BOOL reenables(FSocket *s, CFOptionFlags type) { return (s->flags & type) == type; }

static void read_side(FSocket *s)
{
    CFOptionFlags type = s->types & 3;
    struct sockaddr_storage from;
    socklen_t len = sizeof from;
    if (type == kCFSocketReadCallBack) {
        if (!reenables(s, type))
            s->readOn = NO;
        call(s, type, NULL, NULL);
    } else if (type == kCFSocketAcceptCallBack) {
        int c = accept(s->fd, (struct sockaddr *)&from, &len);
        if (c < 0)
            return; /* gone again, or an error: nothing to hand over */
        if (!reenables(s, type))
            s->readOn = NO;
        NSData *address = [NSData dataWithBytes:&from length:len];
        CFSocketNativeHandle h = c;
        call(s, type, (CFDataRef)address, &h);
    } else {
        int avail = 0;
        if (ioctl(s->fd, FIONREAD, &avail) < 0 || avail <= 0)
            avail = 2048;
        if (avail > 65536)
            avail = 65536;
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)avail];
        ssize_t n = recvfrom(s->fd, [data mutableBytes], (size_t)avail, 0, (struct sockaddr *)&from, &len);
        if (n < 0 && (errno == EAGAIN || errno == EINTR))
            return;
        [data setLength:n > 0 ? (NSUInteger)n : 0];
        NSData *address = nil;
        if (n >= 0 && len > 0 && len <= sizeof from && from.ss_len)
            address = [NSData dataWithBytes:&from length:len];
        else {
            len = sizeof from;
            if (getpeername(s->fd, (struct sockaddr *)&from, &len) == 0)
                address = [NSData dataWithBytes:&from length:len];
        }
        /* the end (or an error): empty data, and no more data callbacks */
        if (n <= 0 || !reenables(s, type))
            s->readOn = NO;
        call(s, type, (CFDataRef)address, data);
    }
}

static void socket_ready(int fd, short revents, void *ctx)
{
    FSocket *s = [(FSocket *)ctx retain];
    if (s->connecting && (revents & (POLLOUT | POLLERR | POLLHUP))) {
        int err = 0;
        socklen_t len = sizeof err;
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len);
        s->connecting = NO;
        if (s->connectOn && (s->types & kCFSocketConnectCallBack)) {
            s->connectOn = NO; /* once */
            SInt32 e = err;
            call(s, kCFSocketConnectCallBack, NULL, err ? &e : NULL);
        }
        if (err)
            revents = 0;
    }
    if (s->valid && s->readOn && (s->types & 3) && (revents & (POLLIN | POLLHUP | POLLERR)))
        read_side(s);
    if (s->valid && !s->connecting && s->writeOn && (s->types & kCFSocketWriteCallBack) &&
        (revents & (POLLOUT | POLLHUP | POLLERR))) {
        if (!reenables(s, kCFSocketWriteCallBack))
            s->writeOn = NO;
        call(s, kCFSocketWriteCallBack, NULL, NULL);
    }
    [s update];
    [s release];
}

static FSocket *existing(int fd)
{
    FSocket *s = nil;
    os_unfair_lock_lock(&by_fd_lock);
    if (fd >= 0 && fd < by_fd_size && by_fd[fd] && by_fd[fd]->valid)
        s = [by_fd[fd] retain];
    os_unfair_lock_unlock(&by_fd_lock);
    return s;
}

static FSocket *new_socket(int fd, CFOptionFlags types, CFSocketCallBack callout, const CFSocketContext *context)
{
    FSocket *s = existing(fd);
    if (s)
        return s; /* "the existing CFSocket object is returned", its callback unchanged */
    s = [[FSocket alloc] init];
    s->fd = fd;
    s->types = types;
    /* by default the read, accept and data callbacks come back by themselves, the write one doesn't */
    s->flags = kCFSocketAutomaticallyReenableDataCallBack | kCFSocketCloseOnInvalidate;
    s->readOn = s->writeOn = s->connectOn = YES;
    s->valid = YES;
    s->callout = callout;
    s->loops = [[NSMutableArray alloc] init];
    if (context) {
        s->context = *context;
        if (context->retain && context->info)
            s->context.info = (void *)context->retain(context->info);
    }
    os_unfair_lock_lock(&by_fd_lock);
    if (fd >= by_fd_size) {
        int n = fd + 64;
        by_fd = realloc(by_fd, n * sizeof *by_fd);
        memset(by_fd + by_fd_size, 0, (n - by_fd_size) * sizeof *by_fd);
        by_fd_size = n;
    }
    by_fd[fd] = s;
    os_unfair_lock_unlock(&by_fd_lock);
    return s;
}

#define SOCK(x) ((FSocket *)(x))

CFTypeID CFSocketGetTypeID(void) { return 0x46520002; }

CFSocketRef CFSocketCreateWithNative(CFAllocatorRef allocator, CFSocketNativeHandle sock, CFOptionFlags callBackTypes,
                                     CFSocketCallBack callout, const CFSocketContext *context)
{
    if (sock < 0 || fcntl(sock, F_GETFL) < 0)
        return NULL;
    return (CFSocketRef)new_socket(sock, callBackTypes, callout, context);
}

CFSocketRef CFSocketCreate(CFAllocatorRef allocator, SInt32 protocolFamily, SInt32 socketType, SInt32 protocol,
                           CFOptionFlags callBackTypes, CFSocketCallBack callout, const CFSocketContext *context)
{
    if (protocolFamily <= 0)
        protocolFamily = PF_INET;
    if (socketType <= 0)
        socketType = SOCK_STREAM;
    if (protocol <= 0 && protocolFamily != PF_UNIX)
        protocol = socketType == SOCK_STREAM ? IPPROTO_TCP : socketType == SOCK_DGRAM ? IPPROTO_UDP : 0;
    int fd = socket(protocolFamily, socketType, protocolFamily == PF_UNIX ? 0 : protocol);
    if (fd < 0)
        return NULL;
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    return (CFSocketRef)new_socket(fd, callBackTypes, callout, context);
}

CFSocketError CFSocketSetAddress(CFSocketRef s, CFDataRef address)
{
    if (!s || !address || !SOCK(s)->valid)
        return kCFSocketError;
    int fd = SOCK(s)->fd, on = 1, type = 0;
    socklen_t len = sizeof type;
    getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &len);
    const struct sockaddr *sa = [(NSData *)address bytes];
    if (sa->sa_family != AF_UNIX)
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
    if (bind(fd, sa, (socklen_t)[(NSData *)address length]) < 0)
        return kCFSocketError;
    if (type == SOCK_STREAM && listen(fd, 256) < 0)
        return kCFSocketError;
    return kCFSocketSuccess;
}

static int wait_for(int fd, short events, CFTimeInterval timeout)
{
    struct pollfd p = {fd, events, 0};
    int ms = timeout > 0 ? (int)(timeout * 1000 + 0.5) : -1;
    int r;
    do
        r = poll(&p, 1, ms);
    while (r < 0 && errno == EINTR);
    return r;
}

CFSocketError CFSocketConnectToAddress(CFSocketRef s, CFDataRef address, CFTimeInterval timeout)
{
    if (!s || !address || !SOCK(s)->valid)
        return kCFSocketError;
    FSocket *so = SOCK(s);
    int fl = fcntl(so->fd, F_GETFL);
    fcntl(so->fd, F_SETFL, fl | O_NONBLOCK);
    int r = connect(so->fd, [(NSData *)address bytes], (socklen_t)[(NSData *)address length]);
    if (r < 0 && errno != EINPROGRESS) {
        fcntl(so->fd, F_SETFL, fl);
        return kCFSocketError;
    }
    if (timeout < 0) {
        /* in the background: the connect callback says how it went */
        so->connecting = YES;
        [so update];
        return kCFSocketSuccess;
    }
    if (r < 0) {
        int ready = wait_for(so->fd, POLLOUT, timeout);
        if (ready == 0) {
            fcntl(so->fd, F_SETFL, fl);
            return kCFSocketTimeout;
        }
        int err = 0;
        socklen_t len = sizeof err;
        getsockopt(so->fd, SOL_SOCKET, SO_ERROR, &err, &len);
        if (ready < 0 || err) {
            fcntl(so->fd, F_SETFL, fl);
            errno = err;
            return kCFSocketError;
        }
    }
    fcntl(so->fd, F_SETFL, fl);
    return kCFSocketSuccess;
}

CFSocketRef CFSocketCreateWithSocketSignature(CFAllocatorRef allocator, const CFSocketSignature *signature,
                                              CFOptionFlags callBackTypes, CFSocketCallBack callout,
                                              const CFSocketContext *context)
{
    CFSocketRef s = CFSocketCreate(allocator, signature->protocolFamily, signature->socketType, signature->protocol,
                                   callBackTypes, callout, context);
    if (s && signature->address && CFSocketSetAddress(s, signature->address) != kCFSocketSuccess) {
        CFSocketInvalidate(s);
        CFRelease(s);
        return NULL;
    }
    return s;
}

CFSocketRef CFSocketCreateConnectedToSocketSignature(CFAllocatorRef allocator, const CFSocketSignature *signature,
                                                     CFOptionFlags callBackTypes, CFSocketCallBack callout,
                                                     const CFSocketContext *context, CFTimeInterval timeout)
{
    CFSocketRef s = CFSocketCreate(allocator, signature->protocolFamily, signature->socketType, signature->protocol,
                                   callBackTypes, callout, context);
    if (s && signature->address && CFSocketConnectToAddress(s, signature->address, timeout) != kCFSocketSuccess) {
        CFSocketInvalidate(s);
        CFRelease(s);
        return NULL;
    }
    return s;
}

CFSocketError CFSocketSendData(CFSocketRef s, CFDataRef address, CFDataRef data, CFTimeInterval timeout)
{
    if (!s || !SOCK(s)->valid)
        return kCFSocketError;
    int fd = SOCK(s)->fd;
    const char *p = data ? [(NSData *)data bytes] : "";
    size_t left = data ? [(NSData *)data length] : 0;
    CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + timeout;
    do {
        if (timeout > 0) {
            CFTimeInterval rest = limit - CFAbsoluteTimeGetCurrent();
            if (rest <= 0 || wait_for(fd, POLLOUT, rest) == 0)
                return kCFSocketTimeout;
        }
        ssize_t n = address ? sendto(fd, p, left, 0, [(NSData *)address bytes], (socklen_t)[(NSData *)address length])
                            : send(fd, p, left, 0);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN && timeout <= 0) {
                wait_for(fd, POLLOUT, -1);
                continue;
            }
            if (errno != EAGAIN)
                return kCFSocketError;
            continue;
        }
        p += n;
        left -= (size_t)n;
    } while (left > 0);
    return kCFSocketSuccess;
}

static CFDataRef copy_name(CFSocketRef s, int peer)
{
    if (!s || !SOCK(s)->valid)
        return NULL;
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    int r = peer ? getpeername(SOCK(s)->fd, (struct sockaddr *)&ss, &len)
                 : getsockname(SOCK(s)->fd, (struct sockaddr *)&ss, &len);
    return r == 0 ? (CFDataRef)[[NSData alloc] initWithBytes:&ss length:len] : NULL;
}
CFDataRef CFSocketCopyAddress(CFSocketRef s) { return copy_name(s, 0); }
CFDataRef CFSocketCopyPeerAddress(CFSocketRef s) { return copy_name(s, 1); }
CFSocketNativeHandle CFSocketGetNative(CFSocketRef s) { return s && SOCK(s)->valid ? SOCK(s)->fd : -1; }
void CFSocketGetContext(CFSocketRef s, CFSocketContext *context)
{
    if (s && context)
        *context = SOCK(s)->context;
}
CFOptionFlags CFSocketGetSocketFlags(CFSocketRef s) { return s ? SOCK(s)->flags : 0; }
void CFSocketSetSocketFlags(CFSocketRef s, CFOptionFlags flags)
{
    if (s)
        SOCK(s)->flags = flags;
}
void CFSocketEnableCallBacks(CFSocketRef s, CFOptionFlags callBackTypes)
{
    if (!s)
        return;
    FSocket *so = SOCK(s);
    if (callBackTypes & 3)
        so->readOn = YES;
    if (callBackTypes & kCFSocketWriteCallBack)
        so->writeOn = YES;
    if (callBackTypes & kCFSocketConnectCallBack)
        so->connectOn = YES;
    [so update];
}
void CFSocketDisableCallBacks(CFSocketRef s, CFOptionFlags callBackTypes)
{
    if (!s)
        return;
    FSocket *so = SOCK(s);
    if (callBackTypes & 3)
        so->readOn = NO;
    if (callBackTypes & kCFSocketWriteCallBack)
        so->writeOn = NO;
    if (callBackTypes & kCFSocketConnectCallBack)
        so->connectOn = NO;
    [so update];
}

void CFSocketInvalidate(CFSocketRef s)
{
    if (!s)
        return;
    FSocket *so = [SOCK(s) retain];
    NSArray *was;
    @synchronized(so) {
        if (!so->valid) {
            [so release];
            return;
        }
        was = [[so->loops copy] autorelease];
        so->valid = NO;
        [so->loops removeAllObjects];
    }
    for (NSRunLoop *loop in was)
        [loop _removeDescriptor:so->fd context:so];
    [so->source invalidate];
    os_unfair_lock_lock(&by_fd_lock);
    if (so->fd < by_fd_size && by_fd[so->fd] == so)
        by_fd[so->fd] = nil;
    os_unfair_lock_unlock(&by_fd_lock);
    if (so->flags & kCFSocketCloseOnInvalidate)
        close(so->fd);
    if (so->context.release && so->context.info)
        so->context.release(so->context.info);
    so->context.info = NULL;
    [so release];
}
Boolean CFSocketIsValid(CFSocketRef s) { return s && SOCK(s)->valid; }

CFRunLoopSourceRef CFSocketCreateRunLoopSource(CFAllocatorRef allocator, CFSocketRef s, CFIndex order)
{
    if (!s || !SOCK(s)->valid)
        return NULL;
    FSocket *so = SOCK(s);
    @synchronized(so) {
        if (!so->source) {
            so->source = new_source(order, NULL);
            /* the source keeps the socket until either is invalidated, as the run loop needs it */
            so->source->owner = [so retain];
            so->source->added = socket_added;
            so->source->removed = socket_removed;
        }
        return (CFRunLoopSourceRef)[so->source retain];
    }
}
