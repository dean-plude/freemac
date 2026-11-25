/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the system's proxy settings (freemac 1.NEXT, for VLC), from
 * Apple's public CFProxySupport documentation; not Apple's header. Ferry
 * reads them from this system's http_proxy, https_proxy and no_proxy
 * (foundation/CFProxySupport.m). */
#ifndef _FERRY_CFPROXYSUPPORT_H_
#define _FERRY_CFPROXYSUPPORT_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
CFDictionaryRef CFNetworkCopySystemProxySettings(void);

extern const CFStringRef kCFNetworkProxiesHTTPEnable;
extern const CFStringRef kCFNetworkProxiesHTTPProxy;
extern const CFStringRef kCFNetworkProxiesHTTPPort;
extern const CFStringRef kCFNetworkProxiesHTTPSEnable;
extern const CFStringRef kCFNetworkProxiesHTTPSProxy;
extern const CFStringRef kCFNetworkProxiesHTTPSPort;
extern const CFStringRef kCFNetworkProxiesExceptionsList;
extern const CFStringRef kCFNetworkProxiesProxyAutoConfigEnable;
extern const CFStringRef kCFNetworkProxiesProxyAutoConfigURLString;
__FERRY_END
#endif
