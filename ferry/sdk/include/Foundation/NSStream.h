/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSStream, NSInputStream and NSOutputStream (foundation/NSStream.m),
 * the same objects as CFReadStream and CFWriteStream. Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSSTREAM_H_
#define _FERRY_FOUNDATION_NSSTREAM_H_
#include <Foundation/Foundation.h>

typedef NSString *NSStreamPropertyKey;

typedef NS_ENUM(NSUInteger, NSStreamStatus) {
    NSStreamStatusNotOpen = 0,
    NSStreamStatusOpening = 1,
    NSStreamStatusOpen = 2,
    NSStreamStatusReading = 3,
    NSStreamStatusWriting = 4,
    NSStreamStatusAtEnd = 5,
    NSStreamStatusClosed = 6,
    NSStreamStatusError = 7,
};
typedef NS_OPTIONS(NSUInteger, NSStreamEvent) {
    NSStreamEventNone = 0,
    NSStreamEventOpenCompleted = 1 << 0,
    NSStreamEventHasBytesAvailable = 1 << 1,
    NSStreamEventHasSpaceAvailable = 1 << 2,
    NSStreamEventErrorOccurred = 1 << 3,
    NSStreamEventEndEncountered = 1 << 4,
};

@class NSStream, NSInputStream, NSOutputStream;
@protocol NSStreamDelegate <NSObject>
@optional
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end

@interface NSStream : NSObject
- (void)open;
- (void)close;
@property (assign) id<NSStreamDelegate> delegate;
- (id)propertyForKey:(NSStreamPropertyKey)key;
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
@property (readonly) NSStreamStatus streamStatus;
@property (readonly, copy) NSError *streamError;
@end

@interface NSInputStream : NSStream
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len;
- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len;
@property (readonly) BOOL hasBytesAvailable;
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithFileAtPath:(NSString *)path;
+ (instancetype)inputStreamWithData:(NSData *)data;
+ (instancetype)inputStreamWithFileAtPath:(NSString *)path;
+ (instancetype)inputStreamWithURL:(NSURL *)url;
@end

@interface NSOutputStream : NSStream
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len;
@property (readonly) BOOL hasSpaceAvailable;
- (instancetype)initToMemory;
- (instancetype)initToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity;
- (instancetype)initWithURL:(NSURL *)url append:(BOOL)shouldAppend;
- (instancetype)initToFileAtPath:(NSString *)path append:(BOOL)shouldAppend;
+ (instancetype)outputStreamToMemory;
+ (instancetype)outputStreamToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity;
+ (instancetype)outputStreamToFileAtPath:(NSString *)path append:(BOOL)shouldAppend;
+ (instancetype)outputStreamWithURL:(NSURL *)url append:(BOOL)shouldAppend;
@end

@interface NSStream (NSSocketStreamCreationExtensions)
+ (void)getStreamsToHostWithName:(NSString *)hostname
                            port:(NSInteger)port
                     inputStream:(NSInputStream **)inputStream
                    outputStream:(NSOutputStream **)outputStream;
@end

@interface NSStream (NSStreamBoundPairCreationExtensions)
+ (void)getBoundStreamsWithBufferSize:(NSUInteger)bufferSize
                          inputStream:(NSInputStream **)inputStream
                         outputStream:(NSOutputStream **)outputStream;
@end

FOUNDATION_EXPORT NSStreamPropertyKey const NSStreamSocketSecurityLevelKey;
typedef NSString *NSStreamSocketSecurityLevel;
FOUNDATION_EXPORT NSStreamSocketSecurityLevel const NSStreamSocketSecurityLevelNone;
FOUNDATION_EXPORT NSStreamSocketSecurityLevel const NSStreamSocketSecurityLevelSSLv2;
FOUNDATION_EXPORT NSStreamSocketSecurityLevel const NSStreamSocketSecurityLevelSSLv3;
FOUNDATION_EXPORT NSStreamSocketSecurityLevel const NSStreamSocketSecurityLevelTLSv1;
FOUNDATION_EXPORT NSStreamSocketSecurityLevel const NSStreamSocketSecurityLevelNegotiatedSSL;
FOUNDATION_EXPORT NSStreamPropertyKey const NSStreamSOCKSProxyConfigurationKey;
FOUNDATION_EXPORT NSStreamPropertyKey const NSStreamDataWrittenToMemoryStreamKey;
FOUNDATION_EXPORT NSStreamPropertyKey const NSStreamFileCurrentOffsetKey;
FOUNDATION_EXPORT NSStreamPropertyKey const NSStreamNetworkServiceType;
FOUNDATION_EXPORT NSErrorDomain const NSStreamSocketSSLErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSStreamSOCKSErrorDomain;
#endif
