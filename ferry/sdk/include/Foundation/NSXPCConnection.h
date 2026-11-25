/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSXPCConnection and its interfaces (foundation/NSXPCConnection.m,
 * freemac 1.224, Ferry 0.48.0). Written for freemac from Apple's public
 * API documentation; not Apple's header.
 *
 * There are no XPC services on this system, so a connection to a service,
 * a Mach service or a listener's endpoint never connects: as on a Mac when
 * the service isn't there, the first message sent through its proxy calls
 * the proxy's error handler with NSXPCConnectionInvalid, then the
 * connection's invalidation handler, and the message itself goes nowhere.
 * A listener takes no connections. Programs that look for their XPC
 * services (Sparkle's installer and downloader) and do the work themselves
 * when there are none work as they do without them. */
#ifndef _FERRY_FOUNDATION_NSXPCCONNECTION_H_
#define _FERRY_FOUNDATION_NSXPCCONNECTION_H_
#include <Foundation/Foundation.h>
#include <mach/message.h>

@class NSXPCConnection, NSXPCListener, NSXPCInterface, NSXPCListenerEndpoint;

/* the errors a connection reports, in NSCocoaErrorDomain */
enum {
    NSXPCConnectionInterrupted = 4097,
    NSXPCConnectionInvalid = 4099,
    NSXPCConnectionReplyInvalid = 4101,
    NSXPCConnectionCodeSigningRequirementFailure = 4102,
};

@protocol NSXPCProxyCreating
- (id)remoteObjectProxy;
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@optional
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@end

typedef NS_OPTIONS(NSUInteger, NSXPCConnectionOptions) { NSXPCConnectionPrivileged = 1 << 12 };

@interface NSXPCConnection : NSObject <NSXPCProxyCreating>
- (instancetype)initWithServiceName:(NSString *)serviceName;
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options;
- (instancetype FERRY_SWIFT_NONNULL)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint;
@property (readonly, copy) NSString *serviceName;
@property (readonly, retain) NSXPCListenerEndpoint *endpoint;
@property (retain) NSXPCInterface *exportedInterface;
@property (retain) id exportedObject;
@property (retain) NSXPCInterface *remoteObjectInterface;
@property (readonly, retain) id remoteObjectProxy;
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@property (copy) void (^interruptionHandler)(void);
@property (copy) void (^invalidationHandler)(void);
- (void)resume;
- (void)suspend;
- (void)activate;
- (void)invalidate;
/* the other side's identity, which is none here (0) */
@property (readonly) int auditSessionIdentifier;
@property (readonly) pid_t processIdentifier;
@property (readonly) uid_t effectiveUserIdentifier;
@property (readonly) gid_t effectiveGroupIdentifier;
/* taken; there is never another side to check */
- (void)setCodeSigningRequirement:(NSString *)requirement;
@property (class, readonly, strong) NSXPCConnection *currentConnection;
- (void)scheduleSendBarrierBlock:(void (^)(void))block;
@end

@protocol NSXPCListenerDelegate <NSObject>
@optional
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection;
@end

@interface NSXPCListener : NSObject
+ (NSXPCListener *)serviceListener;
+ (NSXPCListener *)anonymousListener;
- (instancetype)initWithMachServiceName:(NSString *)name;
@property (assign) id<NSXPCListenerDelegate> delegate;
@property (readonly, retain) NSXPCListenerEndpoint *endpoint;
- (void)resume;
- (void)suspend;
- (void)activate;
- (void)invalidate;
@end

@interface NSXPCListenerEndpoint : NSObject <NSSecureCoding>
@end

/* The protocol a side offers, and the classes each argument may hold. */
@interface NSXPCInterface : NSObject
+ (NSXPCInterface *)interfaceWithProtocol:(Protocol *)protocol;
@property (assign) Protocol *protocol;
- (void)setClasses:(NSSet<Class> *)classes forSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (NSSet<Class> *)classesForSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (void)setInterface:(NSXPCInterface *)ifc forSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (NSXPCInterface *)interfaceForSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
@end

#endif
