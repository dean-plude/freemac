/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSURLComponents and NSURLQueryItem (freemac 1.225, Ferry
 * 0.49.0), a URL taken apart and put together again (RFC 3986). Written for
 * freemac from Apple's public API documentation; not Apple's header.
 * Implemented in foundation/NSURLComponents.m. */
#ifndef _FERRY_FOUNDATION_NSURLCOMPONENTS_H_
#define _FERRY_FOUNDATION_NSURLCOMPONENTS_H_
#include <Foundation/Foundation.h>

@interface NSURLQueryItem : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)queryItemWithName:(NSString *)name value:(NSString *)value;
- (instancetype)initWithName:(NSString *)name value:(NSString *)value;
@property (readonly) NSString *name;
@property (readonly) NSString *value;
@end

@interface NSURLComponents : NSObject <NSCopying>
+ (instancetype)componentsWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve;
+ (instancetype)componentsWithString:(NSString *)string;
- (instancetype)init;
- (instancetype)initWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve;
- (instancetype)initWithString:(NSString *)string;
@property (readonly, copy) NSURL *URL;
- (NSURL *)URLRelativeToURL:(NSURL *)baseURL;
@property (readonly, copy) NSString *string;
/* decoded */
@property (copy) NSString *scheme;
@property (copy) NSString *user;
@property (copy) NSString *password;
@property (copy) NSString *host;
@property (copy) NSNumber *port;
@property (copy) NSString *path;
@property (copy) NSString *query;
@property (copy) NSString *fragment;
/* as they are written in the URL */
@property (copy) NSString *percentEncodedUser;
@property (copy) NSString *percentEncodedPassword;
@property (copy) NSString *percentEncodedHost;
@property (copy) NSString *percentEncodedPath;
@property (copy) NSString *percentEncodedQuery;
@property (copy) NSString *percentEncodedFragment;
@property (copy) NSArray<NSURLQueryItem *> *queryItems;
@property (copy) NSArray<NSURLQueryItem *> *percentEncodedQueryItems;
/* where each part is in string, or {NSNotFound, 0} */
@property (readonly) NSRange rangeOfScheme;
@property (readonly) NSRange rangeOfUser;
@property (readonly) NSRange rangeOfPassword;
@property (readonly) NSRange rangeOfHost;
@property (readonly) NSRange rangeOfPort;
@property (readonly) NSRange rangeOfPath;
@property (readonly) NSRange rangeOfQuery;
@property (readonly) NSRange rangeOfFragment;
@end

#endif
