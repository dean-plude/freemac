/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the socket streams' properties of CFNetwork (foundation/NSStream.m:
 * Ferry serves CFNetwork from its Foundation). Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_CFNETWORK_H_
#define _FERRY_CFNETWORK_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CFNetwork/CFProxySupport.h>

__FERRY_BEGIN
extern const CFStringRef kCFErrorDomainCFNetwork;
extern const SInt32 kCFStreamErrorDomainSSL;
extern const SInt32 kCFStreamErrorDomainNetDB;

/* ---- CFHost: a name's addresses (freemac 1.271) ---- */
typedef struct __CFHost *CFHostRef;
typedef enum { kCFHostAddresses = 0, kCFHostNames = 1, kCFHostReachability = 2 } CFHostInfoType;
CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname);
Boolean CFHostStartInfoResolution(CFHostRef theHost, CFHostInfoType info, CFStreamError *error);
CFArrayRef CFHostGetAddressing(CFHostRef theHost, Boolean *hasBeenResolved);
CFArrayRef CFHostGetNames(CFHostRef theHost, Boolean *hasBeenResolved);
void CFHostCancelInfoResolution(CFHostRef theHost, CFHostInfoType info);

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
/* ---- proxies (freemac 1.232): this system's settings have none, so every
 * URL goes direct; a proxy auto-configuration script answers the same ---- */
extern const CFStringRef kCFNetworkProxiesHTTPEnable;
extern const CFStringRef kCFNetworkProxiesHTTPPort;
extern const CFStringRef kCFNetworkProxiesHTTPProxy;
extern const CFStringRef kCFNetworkProxiesHTTPSEnable;
extern const CFStringRef kCFNetworkProxiesHTTPSPort;
extern const CFStringRef kCFNetworkProxiesHTTPSProxy;
extern const CFStringRef kCFNetworkProxiesFTPEnable;
extern const CFStringRef kCFNetworkProxiesFTPPort;
extern const CFStringRef kCFNetworkProxiesFTPProxy;
extern const CFStringRef kCFNetworkProxiesSOCKSEnable;
extern const CFStringRef kCFNetworkProxiesSOCKSPort;
extern const CFStringRef kCFNetworkProxiesSOCKSProxy;
extern const CFStringRef kCFNetworkProxiesProxyAutoConfigEnable;
extern const CFStringRef kCFNetworkProxiesProxyAutoConfigURLString;
extern const CFStringRef kCFNetworkProxiesExceptionsList;
extern const CFStringRef kCFNetworkProxiesExcludeSimpleHostnames;
extern const CFStringRef kCFProxyTypeKey;
extern const CFStringRef kCFProxyHostNameKey;
extern const CFStringRef kCFProxyPortNumberKey;
extern const CFStringRef kCFProxyUsernameKey;
extern const CFStringRef kCFProxyPasswordKey;
extern const CFStringRef kCFProxyAutoConfigurationURLKey;
extern const CFStringRef kCFProxyTypeNone;
extern const CFStringRef kCFProxyTypeHTTP;
extern const CFStringRef kCFProxyTypeHTTPS;
extern const CFStringRef kCFProxyTypeFTP;
extern const CFStringRef kCFProxyTypeSOCKS;
extern const CFStringRef kCFProxyTypeAutoConfigurationURL;
typedef void (*CFProxyAutoConfigurationResultCallback)(void *client, CFArrayRef proxyList, CFErrorRef error);
CFDictionaryRef CFNetworkCopySystemProxySettings(void);
CFArrayRef CFNetworkCopyProxiesForURL(CFURLRef url, CFDictionaryRef proxySettings);
CFRunLoopSourceRef CFNetworkExecuteProxyAutoConfigurationURL(CFURLRef proxyAutoConfigURL, CFURLRef targetURL,
                                                            CFProxyAutoConfigurationResultCallback cb,
                                                            CFStreamClientContext *clientContext);
__FERRY_END
#endif
