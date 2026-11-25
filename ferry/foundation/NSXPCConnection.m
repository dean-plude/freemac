/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSXPCConnection, NSXPCListener and NSXPCInterface,
 * as Apple's API reference describes them (freemac 1.224, Ferry 0.48.0),
 * for a system with no XPC services (see NSXPCConnection.h): a connection
 * never reaches the other side, so its proxies report it invalid, as a
 * Mac's do when the service isn't there. Our own code; no Apple code was
 * used. Built without ARC. */
#import "FInternal.h"
#include <Foundation/NSXPCConnection.h>

@interface NSXPCConnection (FerryDead)
- (void)ferryFail:(void (^)(NSError *))handler now:(BOOL)now;
@end

/* Answers every message the remote interface's protocol names (any other
 * as one taking nothing), and sends none of them anywhere. */
@interface FXPCDeadProxy : NSProxy {
@public
    NSXPCConnection *_connection;
    void (^_handler)(NSError *);
    BOOL _synchronous;
}
@end

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

@implementation FXPCDeadProxy
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
    /* the message goes nowhere; a value it would return is zero */
    NSUInteger size = [[invocation methodSignature] methodReturnLength];
    if (size) {
        void *zero = calloc(1, size);
        [invocation setReturnValue:zero];
        free(zero);
    }
    [_connection ferryFail:_handler now:_synchronous];
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
    BOOL _invalid;
}
- (instancetype)initWithServiceName:(NSString *)serviceName
{
    if ((self = [super init]))
        _serviceName = [serviceName copy];
    return self;
}
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options
{
    return [self initWithServiceName:name];
}
- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint
{
    if ((self = [super init]))
        _endpoint = [endpoint retain];
    return self;
}
- (void)dealloc
{
    [_serviceName release];
    [_endpoint release];
    [_exportedInterface release];
    [_remoteObjectInterface release];
    [_exportedObject release];
    [_interruptionHandler release];
    [_invalidationHandler release];
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
    FXPCDeadProxy *p = [FXPCDeadProxy alloc];
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
/* The proxy's error handler, then (once) the invalidation handler: on the
 * caller's thread for a synchronous proxy, otherwise on another queue, as
 * a Mac calls them. */
- (void)ferryFail:(void (^)(NSError *))handler now:(BOOL)now
{
    void (^invalidated)(void) = nil;
    @synchronized(self) {
        if (!_invalid) {
            _invalid = YES;
            invalidated = [_invalidationHandler retain];
            [_invalidationHandler release];
            _invalidationHandler = nil;
            [_interruptionHandler release];
            _interruptionHandler = nil;
        }
    }
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSXPCConnectionInvalid userInfo:nil];
    void (^run)(void) = ^{
        if (handler)
            handler(error);
        if (invalidated)
            invalidated();
    };
    if (now)
        run();
    else {
        [handler retain];
        [error retain];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            run();
            [handler release];
            [error release];
            [invalidated release];
        });
        return;
    }
    [invalidated release];
}
- (void)resume {}
- (void)suspend {}
- (void)activate {}
- (void)invalidate { [self ferryFail:nil now:NO]; }
- (int)auditSessionIdentifier { return 0; }
- (pid_t)processIdentifier { return 0; }
- (uid_t)effectiveUserIdentifier { return 0; }
- (gid_t)effectiveGroupIdentifier { return 0; }
- (void)setCodeSigningRequirement:(NSString *)requirement {}
+ (NSXPCConnection *)currentConnection { return nil; }
- (void)scheduleSendBarrierBlock:(void (^)(void))block
{
    if (block)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}
@end

@implementation NSXPCListenerEndpoint
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

@implementation NSXPCListener {
    id<NSXPCListenerDelegate> _delegate;
    NSXPCListenerEndpoint *_endpoint;
}
+ (NSXPCListener *)serviceListener
{
    static NSXPCListener *service;
    @synchronized(self) {
        if (!service)
            service = [[NSXPCListener alloc] init];
    }
    return service;
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
- (void)resume {}
- (void)suspend {}
- (void)activate {}
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
