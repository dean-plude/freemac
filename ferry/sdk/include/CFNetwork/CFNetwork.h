/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the socket streams' properties of CFNetwork (foundation/NSStream.m:
 * Ferry serves CFNetwork from its Foundation). Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_CFNETWORK_H_
#define _FERRY_CFNETWORK_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
extern const CFStringRef kCFErrorDomainCFNetwork;
extern const SInt32 kCFStreamErrorDomainSSL;
extern const SInt32 kCFStreamErrorDomainNetDB;

extern const CFStringRef kCFStreamPropertyShouldCloseNativeSocket;
extern const CFStringRef kCFStreamPropertySocketSecurityLevel;
extern const CFStringRef kCFStreamSocketSecurityLevelNone;
extern const CFStringRef kCFStreamSocketSecurityLevelSSLv2;
extern const CFStringRef kCFStreamSocketSecurityLevelSSLv3;
extern const CFStringRef kCFStreamSocketSecurityLevelTLSv1;
extern const CFStringRef kCFStreamSocketSecurityLevelNegotiatedSSL;

/* kCFStreamPropertySSLSettings: a dictionary of these */
extern const CFStringRef kCFStreamPropertySSLSettings;
extern const CFStringRef kCFStreamSSLLevel;
extern const CFStringRef kCFStreamSSLPeerName;
extern const CFStringRef kCFStreamSSLValidatesCertificateChain;
extern const CFStringRef kCFStreamSSLCertificates;
extern const CFStringRef kCFStreamSSLIsServer;
/* after the handshake: the server's SecTrustRef */
extern const CFStringRef kCFStreamPropertySSLPeerTrust;
extern const CFStringRef kCFStreamPropertySSLPeerCertificates;

enum {
    kCFHostErrorHostNotFound = 1,
    kCFHostErrorUnknown = 2,
    kCFErrorHTTPConnectionLost = -1005,
};
__FERRY_END
#endif
