/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSNetService and NSNetServiceBrowser (foundation/NSNetServices.m).
 * Written for freemac from Apple's public API documentation; not Apple's
 * header. */
#ifndef _FERRY_FOUNDATION_NSNETSERVICES_H_
#define _FERRY_FOUNDATION_NSNETSERVICES_H_
#include <Foundation/Foundation.h>
#include <Foundation/NSStream.h>

FOUNDATION_EXPORT NSString *const NSNetServicesErrorCode;
FOUNDATION_EXPORT NSErrorDomain const NSNetServicesErrorDomain;

typedef NS_ENUM(NSInteger, NSNetServicesError) {
    NSNetServicesUnknownError = -72000,
    NSNetServicesCollisionError = -72001,
    NSNetServicesNotFoundError = -72002,
    NSNetServicesActivityInProgress = -72003,
    NSNetServicesBadArgumentError = -72004,
    NSNetServicesCancelledError = -72005,
    NSNetServicesInvalidError = -72006,
    NSNetServicesTimeoutError = -72007,
    NSNetServicesMissingRequiredConfigurationError = -72008,
};
typedef NS_OPTIONS(NSUInteger, NSNetServiceOptions) {
    NSNetServiceNoAutoRename = 1UL << 0,
    NSNetServiceListenForConnections = 1UL << 1,
};

@class NSNetService, NSNetServiceBrowser;

@protocol NSNetServiceDelegate <NSObject>
@optional
- (void)netServiceWillPublish:(NSNetService *)sender;
- (void)netServiceDidPublish:(NSNetService *)sender;
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)errorDict;
- (void)netServiceWillResolve:(NSNetService *)sender;
- (void)netServiceDidResolveAddress:(NSNetService *)sender;
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary<NSString *, NSNumber *> *)errorDict;
- (void)netServiceDidStop:(NSNetService *)sender;
- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data;
- (void)netService:(NSNetService *)sender
    didAcceptConnectionWithInputStream:(NSInputStream *)inputStream
                          outputStream:(NSOutputStream *)outputStream;
@end

@protocol NSNetServiceBrowserDelegate <NSObject>
@optional
- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser;
- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser;
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *, NSNumber *> *)errorDict;
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
            didFindDomain:(NSString *)domainString
               moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
          didRemoveDomain:(NSString *)domainString
               moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)service
               moreComing:(BOOL)moreComing;
@end

@interface NSNetService : NSObject
- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(int)port;
- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name;
@property (assign) id<NSNetServiceDelegate> delegate;
@property BOOL includesPeerToPeer;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *type;
@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *hostName;
@property (readonly, copy) NSArray<NSData *> *addresses;
@property (readonly) NSInteger port;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
- (void)publish;
- (void)publishWithOptions:(NSNetServiceOptions)options;
- (void)resolve;
- (void)resolveWithTimeout:(NSTimeInterval)timeout;
- (void)stop;
- (void)startMonitoring;
- (void)stopMonitoring;
- (BOOL)getInputStream:(NSInputStream **)inputStream outputStream:(NSOutputStream **)outputStream;
- (NSData *)TXTRecordData;
- (BOOL)setTXTRecordData:(NSData *)recordData;
+ (NSDictionary<NSString *, NSData *> *)dictionaryFromTXTRecordData:(NSData *)txtData;
+ (NSData *)dataFromTXTRecordDictionary:(NSDictionary<NSString *, NSData *> *)txtDictionary;
@end

@interface NSNetServiceBrowser : NSObject
- (instancetype FERRY_SWIFT_NONNULL)init;
@property (assign) id<NSNetServiceBrowserDelegate> delegate;
@property BOOL includesPeerToPeer;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
- (void)searchForBrowsableDomains;
- (void)searchForRegistrationDomains;
- (void)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domainString;
- (void)stop;
@end
#endif
