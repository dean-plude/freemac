/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: what the URL loading files share among themselves
 * (NSURLSession.m, NSURLAuth.m, NSHTTPCookie.m, NSURLCache.m). */
#ifndef FERRY_FOUNDATION_URL_INTERNAL_H
#define FERRY_FOUNDATION_URL_INTERNAL_H
#import "FInternal.h"

/* The name the program's own files are kept under: its bundle identifier,
 * or else its process name (as NSUserDefaults names its file). */
NSString *FURLAppID(void);

/* A date in any of the forms HTTP and cookies use (RFC 9110's three and
 * RFC 6265's lenient reading of Expires); nil if it isn't one. */
NSDate *FParseHTTPDate(NSString *text);

/* MD5 (RFC 1321) and its lower-case hexadecimal form. */
void FMD5(const void *data, size_t length, unsigned char digest[16]);
NSString *FMD5Hex(NSString *text);

/* A server's certificate, as a protection space's serverTrust: Ferry has
 * no Security framework, so this only says which server it was. */
@interface FURLServerTrust : NSObject {
@public
    NSString *host;
    NSInteger port;
}
@end

@interface NSURLProtectionSpace (FerryInternal)
- (void)_setServerTrust:(FURLServerTrust *)trust;
@end

@interface NSURLCredential (FerryInternal)
- (BOOL)_isForTrust;
@end

@interface NSURLCredentialStorage (FerryInternal)
+ (instancetype)_privateStorage; /* for an ephemeral session */
/* The credential a load uses unasked: the default one, or else the only one. */
- (NSURLCredential *)_credentialForSpace:(NSURLProtectionSpace *)space;
@end

@interface NSHTTPCookie (FerryInternal)
/* Cookies from Set-Cookie fields' values, one cookie a value. */
+ (NSArray *)_cookiesFromValues:(NSArray *)values forURL:(NSURL *)url;
- (BOOL)_matchesURL:(NSURL *)url;
@end

@interface NSHTTPCookieStorage (FerryInternal)
+ (instancetype)_privateStorage; /* for an ephemeral session: kept in memory only */
- (void)_setCookies:(NSArray *)cookies forURL:(NSURL *)url mainDocumentURL:(NSURL *)main
             policy:(NSHTTPCookieAcceptPolicy)policy;
@end

@interface NSCachedURLResponse (FerryInternal)
- (NSDate *)_storedAt; /* when the response came from the server */
- (void)_setStoredAt:(NSDate *)date;
@end

@interface NSURLCache (FerryInternal)
+ (instancetype)_memoryOnlyCache; /* for an ephemeral session */
@end

#endif
