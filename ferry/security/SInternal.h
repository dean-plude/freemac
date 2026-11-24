/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: shared internals. Our own code, written from
 * Apple's public API documentation of Security; built as a Mach-O library
 * with ferry-cc, without ARC. Every Security object is an Objective-C
 * object here, so CFRetain, CFRelease and CFEqual work on them as on any
 * CF object in Ferry.
 *
 * Certificates are checked by this system's OpenSSL (libcrypto), reached
 * through ferry_crypto_symbol() the first time one is needed, as
 * Foundation reaches libcurl; libcrypto's calls are declared here from its
 * published API documentation (the Mac build can't include Linux
 * headers). */
#ifndef FERRY_SECURITY_INTERNAL_H
#define FERRY_SECURITY_INTERNAL_H
#include <Foundation/Foundation.h>
#include <Security/Security.h>
#include <CommonCrypto/CommonCrypto.h>

#define S_EXPORT __attribute__((visibility("default")))

/* Says what Ferry decided, once per message, when FERRY_VERBOSE is set. */
void SVerboseOnce(NSString *message);
/* An error in NSOSStatusErrorDomain with our message for the status (retained, for out parameters). */
NSError *SCopyError(OSStatus status, NSString *detail);
BOOL SIsTrue(id value);   /* a CFBoolean or a number that is non-zero */

/* src/host.c and src/servercerts.c, in libSystem */
void *ferry_crypto_symbol(const char *name);
int ferry_server_certificates(const char *host, int port, int timeout_ms,
                              void (*each)(void *ctx, const unsigned char *der, size_t len), void *ctx);

/* ---- keychain items (SecItem.m) ------------------------------------------------------ */

/* A reference to a stored item (SecKeychainItemRef, and kSecReturnRef's answer). */
@interface SItem : NSObject {
@public
    NSString *uuid;
    NSString *itemClass;
}
@end

/* ---- certificates and trust (SecTrust.m) ------------------------------------------------ */

@interface SCertificate : NSObject {
@public
    NSData *der;
}
@end

@interface SPolicy : NSObject {
@public
    BOOL ssl, server;
    NSString *host;
}
@end

@interface STrust : NSObject {
@public
    NSArray *certificates;     /* SCertificate, the leaf first */
    NSArray *policies;
    NSArray *anchors;          /* nil: the system's */
    BOOL anchorsOnly;
    NSDate *verifyDate;
    NSString *fetchHost;       /* a server's, read when first needed */
    NSInteger fetchPort;
    BOOL fetched, evaluated, trusted;
    SecTrustResultType result;
    NSArray *chain;
    NSError *error;
}
@end

/* What Foundation's NSURLProtectionSpace serverTrust answers (FURLServerTrust). */
@interface NSObject (FerryServerTrust)
- (NSString *)_ferryTrustHost;
- (NSInteger)_ferryTrustPort;
- (id)_ferrySecurityTrust;
- (void)_setFerrySecurityTrust:(id)trust;
@end

/* ---- code signing (SecCode.m) ------------------------------------------------------------ */

@interface SCode : NSObject {
@public
    NSString *path;     /* the bundle or the file */
    BOOL dynamic;       /* a SecCodeRef rather than a SecStaticCodeRef */
    BOOL isSelf;        /* the running program's own code */
}
@end

@interface SRequirement : NSObject {
@public
    NSString *text;
}
@end

#endif
