/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: URL loading (NSURLRequest, NSURLResponse, NSURLSession,
 * NSURLConnection and the NSURLErrorDomain codes), as far as Ferry's own
 * Foundation provides it. Written for freemac from Apple's public API
 * documentation; not Apple's header. Foundation.h includes this file, and
 * NSURLRequest.h, NSURLResponse.h, NSURLConnection.h and NSURLError.h are
 * other names for it. Implemented in ferry/foundation/NSURLSession.m. */
#ifndef _FERRY_FOUNDATION_NSURLSESSION_H_
#define _FERRY_FOUNDATION_NSURLSESSION_H_
#include <Foundation/Foundation.h>

/* ---- errors ------------------------------------------------------------------------ */

FOUNDATION_EXPORT NSErrorDomain const NSURLErrorDomain;
FOUNDATION_EXPORT NSString *const NSURLErrorFailingURLErrorKey;
FOUNDATION_EXPORT NSString *const NSURLErrorFailingURLStringErrorKey;
FOUNDATION_EXPORT NSString *const NSErrorFailingURLStringKey;
FOUNDATION_EXPORT NSString *const NSURLSessionDownloadTaskResumeData;

enum {
    NSURLErrorUnknown = -1,
    NSURLErrorCancelled = -999,
    NSURLErrorBadURL = -1000,
    NSURLErrorTimedOut = -1001,
    NSURLErrorUnsupportedURL = -1002,
    NSURLErrorCannotFindHost = -1003,
    NSURLErrorCannotConnectToHost = -1004,
    NSURLErrorNetworkConnectionLost = -1005,
    NSURLErrorDNSLookupFailed = -1006,
    NSURLErrorHTTPTooManyRedirects = -1007,
    NSURLErrorResourceUnavailable = -1008,
    NSURLErrorNotConnectedToInternet = -1009,
    NSURLErrorRedirectToNonExistentLocation = -1010,
    NSURLErrorBadServerResponse = -1011,
    NSURLErrorUserCancelledAuthentication = -1012,
    NSURLErrorUserAuthenticationRequired = -1013,
    NSURLErrorZeroByteResource = -1014,
    NSURLErrorCannotDecodeRawData = -1015,
    NSURLErrorCannotDecodeContentData = -1016,
    NSURLErrorCannotParseResponse = -1017,
    NSURLErrorFileDoesNotExist = -1100,
    NSURLErrorFileIsDirectory = -1101,
    NSURLErrorNoPermissionsToReadFile = -1102,
    NSURLErrorDataLengthExceedsMaximum = -1103,
    NSURLErrorSecureConnectionFailed = -1200,
    NSURLErrorServerCertificateHasBadDate = -1201,
    NSURLErrorServerCertificateUntrusted = -1202,
    NSURLErrorServerCertificateHasUnknownRoot = -1203,
    NSURLErrorServerCertificateNotYetValid = -1204,
    NSURLErrorClientCertificateRejected = -1205,
    NSURLErrorClientCertificateRequired = -1206,
    NSURLErrorCannotLoadFromNetwork = -2000,
    NSURLErrorCannotCreateFile = -3000,
    NSURLErrorCannotOpenFile = -3001,
    NSURLErrorCannotCloseFile = -3002,
    NSURLErrorCannotWriteToFile = -3003,
    NSURLErrorCannotRemoveFile = -3004,
    NSURLErrorCannotMoveFile = -3005,
    NSURLErrorDownloadDecodingFailedMidStream = -3006,
    NSURLErrorDownloadDecodingFailedToComplete = -3007,
};

/* ---- requests ---------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSURLRequestCachePolicy) {
    NSURLRequestUseProtocolCachePolicy = 0,
    NSURLRequestReloadIgnoringLocalCacheData = 1,
    NSURLRequestReloadIgnoringLocalAndRemoteCacheData = 4,
    NSURLRequestReloadIgnoringCacheData = 1,
    NSURLRequestReturnCacheDataElseLoad = 2,
    NSURLRequestReturnCacheDataDontLoad = 3,
    NSURLRequestReloadRevalidatingCacheData = 5,
};
typedef NS_ENUM(NSUInteger, NSURLRequestNetworkServiceType) {
    NSURLNetworkServiceTypeDefault = 0,
    NSURLNetworkServiceTypeBackground = 3,
};

@interface NSURLRequest : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)requestWithURL:(NSURL *)URL;
+ (instancetype)requestWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)policy
               timeoutInterval:(NSTimeInterval)timeout;
- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)policy
            timeoutInterval:(NSTimeInterval)timeout;
@property (readonly, copy) NSURL *URL;
@property (readonly) NSURLRequestCachePolicy cachePolicy;
@property (readonly) NSTimeInterval timeoutInterval;
@property (readonly, copy) NSURL *mainDocumentURL;
@property (readonly) NSURLRequestNetworkServiceType networkServiceType;
@property (readonly) BOOL allowsCellularAccess;
@property (readonly, copy) NSString *HTTPMethod;
@property (readonly, copy) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;
- (NSString *)valueForHTTPHeaderField:(NSString *)field;
@property (readonly, copy) NSData *HTTPBody;
@property (readonly) BOOL HTTPShouldHandleCookies;
@property (readonly) BOOL HTTPShouldUsePipelining;
@end

@interface NSMutableURLRequest : NSURLRequest
@property (copy) NSURL *URL;
@property NSURLRequestCachePolicy cachePolicy;
@property NSTimeInterval timeoutInterval;
@property (copy) NSURL *mainDocumentURL;
@property NSURLRequestNetworkServiceType networkServiceType;
@property BOOL allowsCellularAccess;
@property (copy) NSString *HTTPMethod;
@property (copy) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field;
- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field;
@property (copy) NSData *HTTPBody;
@property BOOL HTTPShouldHandleCookies;
@property BOOL HTTPShouldUsePipelining;
@end

/* ---- responses --------------------------------------------------------------------- */

#define NSURLResponseUnknownLength ((long long)-1)

@interface NSURLResponse : NSObject <NSCopying>
- (instancetype)initWithURL:(NSURL *)URL MIMEType:(NSString *)MIMEType expectedContentLength:(NSInteger)length
           textEncodingName:(NSString *)name;
@property (readonly, copy) NSURL *URL;
@property (readonly, copy) NSString *MIMEType;
@property (readonly) long long expectedContentLength;
@property (readonly, copy) NSString *textEncodingName;
@property (readonly, copy) NSString *suggestedFilename;
@end

@interface NSHTTPURLResponse : NSURLResponse
- (instancetype)initWithURL:(NSURL *)url statusCode:(NSInteger)statusCode HTTPVersion:(NSString *)HTTPVersion
               headerFields:(NSDictionary<NSString *, NSString *> *)headerFields;
@property (readonly) NSInteger statusCode;
@property (readonly, copy) NSDictionary *allHeaderFields;
- (NSString *)valueForHTTPHeaderField:(NSString *)field;
+ (NSString *)localizedStringForStatusCode:(NSInteger)statusCode;
@end

/* ---- sessions ---------------------------------------------------------------------- */

@class NSURLSession, NSURLSessionTask, NSURLSessionDataTask, NSURLSessionDownloadTask;

FOUNDATION_EXPORT const int64_t NSURLSessionTransferSizeUnknown;

typedef NS_ENUM(NSInteger, NSURLSessionTaskState) {
    NSURLSessionTaskStateRunning = 0,
    NSURLSessionTaskStateSuspended = 1,
    NSURLSessionTaskStateCanceling = 2,
    NSURLSessionTaskStateCompleted = 3,
};
typedef NS_ENUM(NSInteger, NSURLSessionResponseDisposition) {
    NSURLSessionResponseCancel = 0,
    NSURLSessionResponseAllow = 1,
    NSURLSessionResponseBecomeDownload = 2,
    NSURLSessionResponseBecomeStream = 3,
};
FOUNDATION_EXPORT const float NSURLSessionTaskPriorityDefault;
FOUNDATION_EXPORT const float NSURLSessionTaskPriorityLow;
FOUNDATION_EXPORT const float NSURLSessionTaskPriorityHigh;

@interface NSURLSessionConfiguration : NSObject <NSCopying>
@property (class, readonly, strong) NSURLSessionConfiguration *defaultSessionConfiguration;
@property (class, readonly, strong) NSURLSessionConfiguration *ephemeralSessionConfiguration;
+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier;
@property (readonly, copy) NSString *identifier;
@property NSURLRequestCachePolicy requestCachePolicy;
@property NSTimeInterval timeoutIntervalForRequest;
@property NSTimeInterval timeoutIntervalForResource;
@property NSURLRequestNetworkServiceType networkServiceType;
@property BOOL allowsCellularAccess;
@property BOOL waitsForConnectivity;
@property BOOL HTTPShouldUsePipelining;
@property BOOL HTTPShouldSetCookies;
@property NSInteger HTTPMaximumConnectionsPerHost;
@property (copy) NSDictionary *HTTPAdditionalHeaders;
@property (copy) NSDictionary *connectionProxyDictionary;
@property (copy) NSString *sharedContainerIdentifier;
@property BOOL sessionSendsLaunchEvents;
@property (getter=isDiscretionary) BOOL discretionary;
@end

@protocol NSURLSessionDelegate <NSObject>
@optional
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error;
@end

@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@optional
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
@end

@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
@end

@protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didFinishDownloadingToURL:(NSURL *)location;
@optional
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
                 didWriteData:(int64_t)bytesWritten
            totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
@end

@interface NSURLSessionTask : NSObject <NSCopying>
@property (readonly) NSUInteger taskIdentifier;
@property (readonly, copy) NSURLRequest *originalRequest;
@property (readonly, copy) NSURLRequest *currentRequest;
@property (readonly, copy) NSURLResponse *response;
@property (readonly) NSURLSessionTaskState state;
@property (readonly, copy) NSError *error;
@property (readonly) int64_t countOfBytesReceived;
@property (readonly) int64_t countOfBytesSent;
@property (readonly) int64_t countOfBytesExpectedToSend;
@property (readonly) int64_t countOfBytesExpectedToReceive;
@property (copy) NSString *taskDescription;
@property float priority;
@property (retain) id<NSURLSessionTaskDelegate> delegate;
- (void)cancel;
- (void)suspend;
- (void)resume;
@end

@interface NSURLSessionDataTask : NSURLSessionTask
@end
@interface NSURLSessionUploadTask : NSURLSessionDataTask
@end
@interface NSURLSessionDownloadTask : NSURLSessionTask
- (void)cancelByProducingResumeData:(void (^)(NSData *resumeData))completionHandler;
@end

@interface NSURLSession : NSObject
@property (class, readonly, strong) NSURLSession *sharedSession;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                  delegate:(id<NSURLSessionDelegate>)delegate
                             delegateQueue:(NSOperationQueue *)queue;
@property (readonly, retain) NSOperationQueue *delegateQueue;
@property (readonly, retain) id<NSURLSessionDelegate> delegate;
@property (readonly, copy) NSURLSessionConfiguration *configuration;
@property (copy) NSString *sessionDescription;
- (void)finishTasksAndInvalidate;
- (void)invalidateAndCancel;
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler;

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response,
                                                        NSError *error))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response,
                                                    NSError *error))completionHandler;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response,
                                                            NSError *error))completionHandler;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response,
                                                            NSError *error))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url;
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *location, NSURLResponse *response,
                                                                NSError *error))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL *location, NSURLResponse *response,
                                                            NSError *error))completionHandler;
@end

/* ---- NSURLConnection (deprecated on a Mac, still used by older apps) ---------------- */

@class NSURLConnection;

@protocol NSURLConnectionDelegate <NSObject>
@optional
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
@end

@protocol NSURLConnectionDataDelegate <NSURLConnectionDelegate>
@optional
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten
     totalBytesWritten:(NSInteger)totalBytesWritten
    totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
@end

@interface NSURLConnection : NSObject
+ (BOOL)canHandleRequest:(NSURLRequest *)request;
+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate;
- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate;
- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)start;
@property (readonly, copy) NSURLRequest *originalRequest;
@property (readonly, copy) NSURLRequest *currentRequest;
- (void)start;
- (void)cancel;
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode;
- (void)unscheduleFromRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode;
- (void)setDelegateQueue:(NSOperationQueue *)queue;
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response
                             error:(NSError **)error;
+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *response, NSData *data, NSError *connectionError))handler;
@end

/* ---- reading URLs into data and strings -------------------------------------------- */

/* The options (NSDataReadingOptions on a Mac) make no difference to a URL
 * read from the network. */
@interface NSData (NSURLLoading)
+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error;
- (instancetype)initWithContentsOfURL:(NSURL *)url;
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error;
@end

@interface NSString (NSURLLoading)
+ (instancetype)stringWithContentsOfURL:(NSURL *)url usedEncoding:(NSStringEncoding *)enc error:(NSError **)error;
- (instancetype)initWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding)enc error:(NSError **)error;
- (instancetype)initWithContentsOfURL:(NSURL *)url usedEncoding:(NSStringEncoding *)enc error:(NSError **)error;
@end

#endif
