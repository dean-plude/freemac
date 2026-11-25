/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * CFNetworkCopySystemProxySettings (freemac 1.NEXT, for VLC), written from
 * Apple's public CFProxySupport documentation. A Mac keeps its proxies in
 * System Settings; this system keeps them in http_proxy, https_proxy and
 * no_proxy, so those are what a Mac program is told.
 */
#import <Foundation/Foundation.h>
#include <CFNetwork/CFNetwork.h>
#include <stdlib.h>
#include <string.h>

#define CFKEY(name) const CFStringRef name = (CFStringRef)@ #name;
CFKEY(kCFNetworkProxiesHTTPEnable)
CFKEY(kCFNetworkProxiesHTTPProxy)
CFKEY(kCFNetworkProxiesHTTPPort)
CFKEY(kCFNetworkProxiesHTTPSEnable)
CFKEY(kCFNetworkProxiesHTTPSProxy)
CFKEY(kCFNetworkProxiesHTTPSPort)
CFKEY(kCFNetworkProxiesExceptionsList)
CFKEY(kCFNetworkProxiesProxyAutoConfigEnable)
CFKEY(kCFNetworkProxiesProxyAutoConfigURLString)

/* "http://user:pass@host:port/" gives host and port. */
static void add_proxy(NSMutableDictionary *d, const char *lower, const char *upper,
                      CFStringRef enable, CFStringRef host_key, CFStringRef port_key, int def_port)
{
    const char *v = getenv(lower);
    if (!v || !*v)
        v = getenv(upper);
    if (!v || !*v)
        return;
    const char *p = strstr(v, "://");
    p = p ? p + 3 : v;
    const char *at = strchr(p, '@');
    if (at)
        p = at + 1;
    size_t n = strcspn(p, ":/");
    if (n == 0)
        return;
    NSString *host = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
    int port = def_port;
    if (p[n] == ':')
        port = atoi(p + n + 1);
    d[(id)host_key] = host;
    d[(id)port_key] = @(port);
    d[(id)enable] = @1;
}

CFDictionaryRef CFNetworkCopySystemProxySettings(void)
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    add_proxy(d, "http_proxy", "HTTP_PROXY", kCFNetworkProxiesHTTPEnable,
              kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort, 80);
    add_proxy(d, "https_proxy", "HTTPS_PROXY", kCFNetworkProxiesHTTPSEnable,
              kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort, 443);
    const char *no = getenv("no_proxy");
    if (!no)
        no = getenv("NO_PROXY");
    if (no && *no) {
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *s in [@(no) componentsSeparatedByString:@","]) {
            NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length)
                [list addObject:t];
        }
        d[(id)kCFNetworkProxiesExceptionsList] = list;
    }
    if (!d[(id)kCFNetworkProxiesHTTPEnable])
        d[(id)kCFNetworkProxiesHTTPEnable] = @0;
    return (CFDictionaryRef)d;
}
