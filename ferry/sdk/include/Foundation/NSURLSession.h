/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: URL loading (NSURLRequest, NSURLResponse, NSURLSession,
 * NSURLConnection, the NSURLErrorDomain codes, credentials and
 * authentication challenges, cookies and the URL cache), as far as Ferry's own
 * Foundation provides it. Written for freemac from Apple's public API
 * documentation; not Apple's header. Foundation.h includes this file, and
 * NSURLRequest.h, NSURLResponse.h, NSURLConnection.h, NSURLError.h,
 * NSURLCredential.h, NSURLCredentialStorage.h, NSURLProtectionSpace.h,
 * NSURLAuthenticationChallenge.h, NSHTTPCookie.h, NSHTTPCookieStorage.h
 * and NSURLCache.h are other names for it. Implemented in
 * ferry/foundation/NSURLSession.m, NSURLAuth.m, NSHTTPCookie.m and
 * NSURLCache.m. */
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

/* ---- authentication: credentials, protection spaces and challenges ---------------- */

@class NSURLSessionTask, NSURLAuthenticationChallenge;

/* The Security framework's trust and identity objects. Ferry has no
 * Security framework: a protection space's serverTrust is an object of
 * Ferry's own that only NSURLCredential's credentialForTrust: reads. */
#ifndef _FERRY_SECURITY_TYPES_
#define _FERRY_SECURITY_TYPES_
typedef struct __SecTrust *SecTrustRef;
typedef struct __SecIdentity *SecIdentityRef;
#endif

FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceHTTP;
FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceHTTPS;
FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceFTP;
FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceHTTPProxy;
FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceHTTPSProxy;
FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceFTPProxy;
FOUNDATION_EXPORT NSString *const NSURLProtectionSpaceSOCKSProxy;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodDefault;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodHTTPBasic;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodHTTPDigest;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodHTMLForm;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodNTLM;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodNegotiate;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodClientCertificate;
FOUNDATION_EXPORT NSString *const NSURLAuthenticationMethodServerTrust;

typedef NS_ENUM(NSUInteger, NSURLCredentialPersistence) {
    NSURLCredentialPersistenceNone = 0,
    NSURLCredentialPersistenceForSession = 1,
    NSURLCredentialPersistencePermanent = 2,
    NSURLCredentialPersistenceSynchronizable = 3,
};

@interface NSURLCredential : NSObject <NSCopying>
+ (NSURLCredential *)credentialWithUser:(NSString *)user password:(NSString *)password
                            persistence:(NSURLCredentialPersistence)persistence;
- (instancetype)initWithUser:(NSString *)user password:(NSString *)password
                 persistence:(NSURLCredentialPersistence)persistence;
+ (NSURLCredential *)credentialForTrust:(SecTrustRef)trust;
- (instancetype)initWithTrust:(SecTrustRef)trust;
+ (NSURLCredential *)credentialWithIdentity:(SecIdentityRef)identity certificates:(NSArray *)certArray
                                persistence:(NSURLCredentialPersistence)persistence;
- (instancetype)initWithIdentity:(SecIdentityRef)identity certificates:(NSArray *)certArray
                     persistence:(NSURLCredentialPersistence)persistence;
@property (readonly, copy) NSString *user;
@property (readonly, copy) NSString *password;
@property (readonly) BOOL hasPassword;
@property (readonly) NSURLCredentialPersistence persistence;
@property (readonly) SecIdentityRef identity;
@property (readonly, copy) NSArray *certificates;
@end

@interface NSURLProtectionSpace : NSObject <NSCopying>
- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port protocol:(NSString *)protocol
                       realm:(NSString *)realm authenticationMethod:(NSString *)authenticationMethod;
- (instancetype)initWithProxyHost:(NSString *)host port:(NSInteger)port type:(NSString *)type
                            realm:(NSString *)realm authenticationMethod:(NSString *)authenticationMethod;
@property (readonly, copy) NSString *host;
@property (readonly) NSInteger port;
@property (readonly, copy) NSString *protocol;
@property (readonly, copy) NSString *realm;
@property (readonly, copy) NSString *authenticationMethod;
@property (readonly) BOOL isProxy;
@property (readonly, copy) NSString *proxyType;
@property (readonly) BOOL receivesCredentialSecurely;
@property (readonly) SecTrustRef serverTrust;
@property (readonly, copy) NSArray<NSData *> *distinguishedNames;
@end

@protocol NSURLAuthenticationChallengeSender <NSObject>
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
@optional
- (void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)rejectProtectionSpaceAndContinueWithChallenge:(NSURLAuthenticationChallenge *)challenge;
@end

@interface NSURLAuthenticationChallenge : NSObject
- (instancetype)initWithProtectionSpace:(NSURLProtectionSpace *)space
                     proposedCredential:(NSURLCredential *)credential
                   previousFailureCount:(NSInteger)previousFailureCount
                        failureResponse:(NSURLResponse *)response
                                  error:(NSError *)error
                                 sender:(id<NSURLAuthenticationChallengeSender>)sender;
- (instancetype)initWithAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                                         sender:(id<NSURLAuthenticationChallengeSender>)sender;
@property (readonly, copy) NSURLProtectionSpace *protectionSpace;
@property (readonly, copy) NSURLCredential *proposedCredential;
@property (readonly) NSInteger previousFailureCount;
@property (readonly, copy) NSURLResponse *failureResponse;
@property (readonly, copy) NSError *error;
@property (readonly, retain) id<NSURLAuthenticationChallengeSender> sender;
@end

/* Kept in memory for as long as the program runs: Ferry has no keychain,
 * so permanent and synchronizable credentials last no longer than
 * credentials for the session. */
FOUNDATION_EXPORT NSNotificationName const NSURLCredentialStorageChangedNotification;
FOUNDATION_EXPORT NSString *const NSURLCredentialStorageRemoveSynchronizableCredentials;

@interface NSURLCredentialStorage : NSObject
@property (class, readonly, strong) NSURLCredentialStorage *sharedCredentialStorage;
- (NSDictionary<NSString *, NSURLCredential *> *)credentialsForProtectionSpace:(NSURLProtectionSpace *)space;
@property (readonly, copy)
    NSDictionary<NSURLProtectionSpace *, NSDictionary<NSString *, NSURLCredential *> *> *allCredentials;
- (void)setCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space;
- (void)removeCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space;
- (void)removeCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                 options:(NSDictionary<NSString *, id> *)options;
- (NSURLCredential *)defaultCredentialForProtectionSpace:(NSURLProtectionSpace *)space;
- (void)setDefaultCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space;
- (void)getCredentialsForProtectionSpace:(NSURLProtectionSpace *)space task:(NSURLSessionTask *)task
                       completionHandler:(void (^)(NSDictionary<NSString *, NSURLCredential *> *credentials))handler;
- (void)setCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                 task:(NSURLSessionTask *)task;
- (void)removeCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                 options:(NSDictionary<NSString *, id> *)options task:(NSURLSessionTask *)task;
- (void)getDefaultCredentialForProtectionSpace:(NSURLProtectionSpace *)space task:(NSURLSessionTask *)task
                             completionHandler:(void (^)(NSURLCredential *credential))handler;
- (void)setDefaultCredential:(NSURLCredential *)credential forProtectionSpace:(NSURLProtectionSpace *)space
                        task:(NSURLSessionTask *)task;
@end

/* ---- cookies ------------------------------------------------------------------------ */

typedef NSString *NSHTTPCookiePropertyKey;
typedef NSString *NSHTTPCookieStringPolicy;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieName;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieValue;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieOriginURL;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieVersion;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieDomain;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookiePath;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieSecure;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieExpires;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieComment;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieCommentURL;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieDiscard;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieMaximumAge;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookiePort;
FOUNDATION_EXPORT NSHTTPCookiePropertyKey const NSHTTPCookieSameSitePolicy;
FOUNDATION_EXPORT NSHTTPCookieStringPolicy const NSHTTPCookieSameSiteLax;
FOUNDATION_EXPORT NSHTTPCookieStringPolicy const NSHTTPCookieSameSiteStrict;

@interface NSHTTPCookie : NSObject
+ (NSHTTPCookie *)cookieWithProperties:(NSDictionary<NSHTTPCookiePropertyKey, id> *)properties;
- (instancetype)initWithProperties:(NSDictionary<NSHTTPCookiePropertyKey, id> *)properties;
+ (NSArray<NSHTTPCookie *> *)cookiesWithResponseHeaderFields:(NSDictionary<NSString *, NSString *> *)headerFields
                                                      forURL:(NSURL *)URL;
+ (NSDictionary<NSString *, NSString *> *)requestHeaderFieldsWithCookies:(NSArray<NSHTTPCookie *> *)cookies;
@property (readonly, copy) NSDictionary<NSHTTPCookiePropertyKey, id> *properties;
@property (readonly) NSUInteger version;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *value;
@property (readonly, copy) NSDate *expiresDate;
@property (readonly, getter=isSessionOnly) BOOL sessionOnly;
@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *path;
@property (readonly, getter=isSecure) BOOL secure;
@property (readonly, getter=isHTTPOnly) BOOL HTTPOnly;
@property (readonly, copy) NSString *comment;
@property (readonly, copy) NSURL *commentURL;
@property (readonly, copy) NSArray<NSNumber *> *portList;
@property (readonly, copy) NSHTTPCookieStringPolicy sameSitePolicy;
@end

typedef NS_ENUM(NSUInteger, NSHTTPCookieAcceptPolicy) {
    NSHTTPCookieAcceptPolicyAlways = 0,
    NSHTTPCookieAcceptPolicyNever = 1,
    NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain = 2,
};
FOUNDATION_EXPORT NSNotificationName const NSHTTPCookieManagerAcceptPolicyChangedNotification;
FOUNDATION_EXPORT NSNotificationName const NSHTTPCookieManagerCookiesChangedNotification;

/* The shared storage is kept in memory, and its cookies that outlive the
 * session are saved in ~/.config/ferry/cookies/<app id>.plist. */
@interface NSHTTPCookieStorage : NSObject
@property (class, readonly, strong) NSHTTPCookieStorage *sharedHTTPCookieStorage;
+ (NSHTTPCookieStorage *)sharedCookieStorageForGroupContainerIdentifier:(NSString *)identifier;
@property (readonly, copy) NSArray<NSHTTPCookie *> *cookies;
- (void)setCookie:(NSHTTPCookie *)cookie;
- (void)deleteCookie:(NSHTTPCookie *)cookie;
- (void)removeCookiesSinceDate:(NSDate *)date;
- (NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)URL;
- (void)setCookies:(NSArray<NSHTTPCookie *> *)cookies forURL:(NSURL *)URL mainDocumentURL:(NSURL *)mainDocumentURL;
@property NSHTTPCookieAcceptPolicy cookieAcceptPolicy;
- (NSArray<NSHTTPCookie *> *)sortedCookiesUsingDescriptors:(NSArray *)sortOrder;
- (void)storeCookies:(NSArray<NSHTTPCookie *> *)cookies forTask:(NSURLSessionTask *)task;
- (void)getCookiesForTask:(NSURLSessionTask *)task
        completionHandler:(void (^)(NSArray<NSHTTPCookie *> *cookies))completionHandler;
@end

/* ---- the URL cache ------------------------------------------------------------------ */

typedef NS_ENUM(NSUInteger, NSURLCacheStoragePolicy) {
    NSURLCacheStorageAllowed = 0,
    NSURLCacheStorageAllowedInMemoryOnly = 1,
    NSURLCacheStorageNotAllowed = 2,
};

@interface NSCachedURLResponse : NSObject <NSCopying>
- (instancetype)initWithResponse:(NSURLResponse *)response data:(NSData *)data;
- (instancetype)initWithResponse:(NSURLResponse *)response data:(NSData *)data userInfo:(NSDictionary *)userInfo
                   storagePolicy:(NSURLCacheStoragePolicy)storagePolicy;
@property (readonly, copy) NSURLResponse *response;
@property (readonly, copy) NSData *data;
@property (readonly, copy) NSDictionary *userInfo;
@property (readonly) NSURLCacheStoragePolicy storagePolicy;
@end

@class NSURLSessionDataTask;

/* The shared cache keeps its disk part in ~/.cache/<app id>/URLCache. */
@interface NSURLCache : NSObject
@property (class, strong) NSURLCache *sharedURLCache;
- (instancetype)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity
                              diskPath:(NSString *)path;
- (instancetype)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity
                          directoryURL:(NSURL *)directoryURL;
- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request;
- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request;
- (void)removeCachedResponseForRequest:(NSURLRequest *)request;
- (void)removeAllCachedResponses;
- (void)removeCachedResponsesSinceDate:(NSDate *)date;
@property NSUInteger memoryCapacity;
@property NSUInteger diskCapacity;
@property (readonly) NSUInteger currentMemoryUsage;
@property (readonly) NSUInteger currentDiskUsage;
- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forDataTask:(NSURLSessionDataTask *)dataTask;
- (void)getCachedResponseForDataTask:(NSURLSessionDataTask *)dataTask
                   completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler;
- (void)removeCachedResponseForDataTask:(NSURLSessionDataTask *)dataTask;
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
typedef NS_ENUM(NSInteger, NSURLSessionAuthChallengeDisposition) {
    NSURLSessionAuthChallengeUseCredential = 0,
    NSURLSessionAuthChallengePerformDefaultHandling = 1,
    NSURLSessionAuthChallengeCancelAuthenticationChallenge = 2,
    NSURLSessionAuthChallengeRejectProtectionSpace = 3,
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
@property NSHTTPCookieAcceptPolicy HTTPCookieAcceptPolicy;
@property (retain) NSHTTPCookieStorage *HTTPCookieStorage;
@property (retain) NSURLCredentialStorage *URLCredentialStorage;
@property (retain) NSURLCache *URLCache;
@property BOOL sessionSendsLaunchEvents;
@property (getter=isDiscretionary) BOOL discretionary;
@end

@protocol NSURLSessionDelegate <NSObject>
@optional
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error;
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                NSURLCredential *credential))completionHandler;
@end

@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@optional
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:(void (^)(NSURLRequest *request))completionHandler;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                  NSURLCredential *credential))completionHandler;
@end

@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    willCacheResponse:(NSCachedURLResponse *)proposedResponse
    completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler;
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
- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection;
- (void)connection:(NSURLConnection *)connection
    willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (BOOL)connection:(NSURLConnection *)connection
    canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace;
- (void)connection:(NSURLConnection *)connection
    didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)connection:(NSURLConnection *)connection
    didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
@end

@protocol NSURLConnectionDataDelegate <NSURLConnectionDelegate>
@optional
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response;
- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse;
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
