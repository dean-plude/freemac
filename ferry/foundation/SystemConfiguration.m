/* SPDX-License-Identifier: GPL-3.0-or-later
 * The parts of SystemConfiguration apps call most, served from Foundation's
 * file: network reachability, which apps check before they go online, and
 * the computer's names. Ferry doesn't watch the network: every address is
 * answered as reachable, and no change is ever reported (a Mac reports
 * changes only, so a callback that never comes is the steady state). */
#import "FInternal.h"
#include <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>

@interface FReachability : NSObject {
@public
    SCNetworkReachabilityCallBack callout;
    SCNetworkReachabilityContext context;
}
@end
@implementation FReachability
- (void)dealloc
{
    if (context.release && context.info)
        context.release(context.info);
    [super dealloc];
}
@end

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(CFAllocatorRef allocator, const struct sockaddr *address)
{
    return (SCNetworkReachabilityRef)[[FReachability alloc] init];
}
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddressPair(CFAllocatorRef allocator, const struct sockaddr *local,
                                                                    const struct sockaddr *remote)
{
    return (SCNetworkReachabilityRef)[[FReachability alloc] init];
}
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithName(CFAllocatorRef allocator, const char *nodename)
{
    return nodename ? (SCNetworkReachabilityRef)[[FReachability alloc] init] : NULL;
}
Boolean SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags)
{
    if (!target || !flags)
        return false;
    *flags = kSCNetworkReachabilityFlagsReachable;
    return true;
}
Boolean SCNetworkReachabilitySetCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityCallBack callout,
                                         SCNetworkReachabilityContext *context)
{
    FReachability *r = (FReachability *)target;
    if (!r)
        return false;
    if (r->context.release && r->context.info)
        r->context.release(r->context.info);
    r->callout = callout;
    memset(&r->context, 0, sizeof r->context);
    if (context) {
        r->context = *context;
        if (context->retain && context->info)
            r->context.info = (void *)context->retain(context->info);
    }
    return true;
}
Boolean SCNetworkReachabilityScheduleWithRunLoop(SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
                                                 CFStringRef runLoopMode)
{
    return target != NULL;
}
Boolean SCNetworkReachabilityUnscheduleFromRunLoop(SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
                                                   CFStringRef runLoopMode)
{
    return target != NULL;
}
Boolean SCNetworkReachabilitySetDispatchQueue(SCNetworkReachabilityRef target, void *queue)
{
    return target != NULL;
}

CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store, CFStringEncoding *nameEncoding)
{
    if (nameEncoding)
        *nameEncoding = kCFStringEncodingUTF8;
    return (CFStringRef)[[[NSProcessInfo processInfo] hostName] copy];
}
CFStringRef SCDynamicStoreCopyConsoleUser(SCDynamicStoreRef store, uid_t *uid, gid_t *gid)
{
    if (uid)
        *uid = getuid();
    if (gid)
        *gid = getgid();
    return (CFStringRef)[NSUserName() copy];
}
CFStringRef SCDynamicStoreCopyLocalHostName(SCDynamicStoreRef store)
{
    NSString *name = [[NSProcessInfo processInfo] hostName];
    NSRange dot = [name rangeOfString:@"."];
    return (CFStringRef)[(dot.location == NSNotFound ? name : [name substringToIndex:dot.location]) copy];
}

/* The proxies the system is set to use (freemac 1.263, for Audacity's
 * network code): those the environment names (http_proxy, https_proxy),
 * as freemac's network settings set them, in SystemConfiguration's keys. */
CFDictionaryRef SCDynamicStoreCopyProxies(SCDynamicStoreRef store)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    struct { const char *env; NSString *enable, *host, *port; } kinds[] = {
        {"http_proxy", @"HTTPEnable", @"HTTPProxy", @"HTTPPort"},
        {"https_proxy", @"HTTPSEnable", @"HTTPSProxy", @"HTTPSPort"},
    };
    for (size_t i = 0; i < 2; i++) {
        const char *v = getenv(kinds[i].env);
        if (!v || !*v)
            continue;
        NSURL *u = [NSURL URLWithString:[NSString stringWithUTF8String:v]];
        if (!u.host)
            continue;
        d[kinds[i].enable] = @1;
        d[kinds[i].host] = u.host;
        d[kinds[i].port] = u.port ? u.port : @80;
    }
    return (CFDictionaryRef)[d copy];
}
