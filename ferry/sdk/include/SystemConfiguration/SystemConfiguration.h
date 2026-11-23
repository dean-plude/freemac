/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The parts of SystemConfiguration Ferry has, as Apple's public
 * documentation describes them: network reachability (which Ferry always
 * answers as reachable, and never reports a change of) and the computer's
 * names. Served from Ferry's Foundation file. */
#ifndef _SYSTEMCONFIGURATION_H_
#define _SYSTEMCONFIGURATION_H_
#include <CoreFoundation/CoreFoundation.h>
#ifdef __cplusplus
extern "C" {
#endif
struct sockaddr;
typedef const struct __SCNetworkReachability *SCNetworkReachabilityRef;
typedef const struct __SCDynamicStore *SCDynamicStoreRef;
typedef CF_OPTIONS(uint32_t, SCNetworkReachabilityFlags) {
    kSCNetworkReachabilityFlagsTransientConnection = 1 << 0,
    kSCNetworkReachabilityFlagsReachable = 1 << 1,
    kSCNetworkReachabilityFlagsConnectionRequired = 1 << 2,
    kSCNetworkReachabilityFlagsConnectionOnTraffic = 1 << 3,
    kSCNetworkReachabilityFlagsInterventionRequired = 1 << 4,
    kSCNetworkReachabilityFlagsConnectionOnDemand = 1 << 5,
    kSCNetworkReachabilityFlagsIsLocalAddress = 1 << 16,
    kSCNetworkReachabilityFlagsIsDirect = 1 << 17,
};
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} SCNetworkReachabilityContext;
typedef void (*SCNetworkReachabilityCallBack)(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags,
                                              void *info);
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(CFAllocatorRef allocator, const struct sockaddr *address);
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddressPair(CFAllocatorRef allocator,
                                                                    const struct sockaddr *local,
                                                                    const struct sockaddr *remote);
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithName(CFAllocatorRef allocator, const char *nodename);
Boolean SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags);
Boolean SCNetworkReachabilitySetCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityCallBack callout,
                                         SCNetworkReachabilityContext *context);
Boolean SCNetworkReachabilityScheduleWithRunLoop(SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
                                                 CFStringRef runLoopMode);
Boolean SCNetworkReachabilityUnscheduleFromRunLoop(SCNetworkReachabilityRef target, CFRunLoopRef runLoop,
                                                   CFStringRef runLoopMode);
Boolean SCNetworkReachabilitySetDispatchQueue(SCNetworkReachabilityRef target, void *queue);
CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store, CFStringEncoding *nameEncoding);
CFStringRef SCDynamicStoreCopyLocalHostName(SCDynamicStoreRef store);
#ifdef __cplusplus
}
#endif
#endif
