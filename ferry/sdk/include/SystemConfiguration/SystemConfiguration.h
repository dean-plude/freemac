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
/* the same flags under their older names (SCNetwork.h's) */
typedef SCNetworkReachabilityFlags SCNetworkConnectionFlags;
enum {
    kSCNetworkFlagsTransientConnection = kSCNetworkReachabilityFlagsTransientConnection,
    kSCNetworkFlagsReachable = kSCNetworkReachabilityFlagsReachable,
    kSCNetworkFlagsConnectionRequired = kSCNetworkReachabilityFlagsConnectionRequired,
    kSCNetworkFlagsConnectionAutomatic = kSCNetworkReachabilityFlagsConnectionOnTraffic,
    kSCNetworkFlagsInterventionRequired = kSCNetworkReachabilityFlagsInterventionRequired,
    kSCNetworkFlagsIsLocalAddress = kSCNetworkReachabilityFlagsIsLocalAddress,
    kSCNetworkFlagsIsDirect = kSCNetworkReachabilityFlagsIsDirect,
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
/* the user at the console, which here is the user this program runs as (freemac 1.224) */
CFStringRef SCDynamicStoreCopyConsoleUser(SCDynamicStoreRef store, uid_t *uid, gid_t *gid);
/* The dynamic store (freemac 1.265, foundation/CFElectron.m): the keys apps
 * watch. The proxies are SCDynamicStoreCopyProxies'; other keys have no
 * value, and no change is reported, as the network isn't watched here. */
typedef void (*SCDynamicStoreCallBack)(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info);
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} SCDynamicStoreContext;
CFTypeID SCDynamicStoreGetTypeID(void);
SCDynamicStoreRef SCDynamicStoreCreate(CFAllocatorRef allocator, CFStringRef name, SCDynamicStoreCallBack callout,
                                       SCDynamicStoreContext *context);
SCDynamicStoreRef SCDynamicStoreCreateWithOptions(CFAllocatorRef allocator, CFStringRef name,
                                                  CFDictionaryRef storeOptions, SCDynamicStoreCallBack callout,
                                                  SCDynamicStoreContext *context);
CFStringRef SCDynamicStoreKeyCreateNetworkGlobalEntity(CFAllocatorRef allocator, CFStringRef domain, CFStringRef entity);
CFStringRef SCDynamicStoreKeyCreateNetworkInterfaceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                          CFStringRef ifname, CFStringRef entity);
CFStringRef SCDynamicStoreKeyCreateNetworkServiceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                        CFStringRef serviceID, CFStringRef entity);
CFStringRef SCDynamicStoreKeyCreateProxies(CFAllocatorRef allocator);
CFPropertyListRef SCDynamicStoreCopyValue(SCDynamicStoreRef store, CFStringRef key);
CFDictionaryRef SCDynamicStoreCopyMultiple(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns);
CFArrayRef SCDynamicStoreCopyKeyList(SCDynamicStoreRef store, CFStringRef pattern);
CFDictionaryRef SCDynamicStoreCopyProxies(SCDynamicStoreRef store);
Boolean SCDynamicStoreSetNotificationKeys(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns);
Boolean SCDynamicStoreSetDispatchQueue(SCDynamicStoreRef store, void *queue);
CFRunLoopSourceRef SCDynamicStoreCreateRunLoopSource(CFAllocatorRef allocator, SCDynamicStoreRef store, CFIndex order);
int SCError(void);
CFStringRef SCErrorString(int status);
extern const CFStringRef kSCDynamicStoreDomainState, kSCDynamicStoreDomainSetup, kSCDynamicStoreDomainFile,
    kSCDynamicStoreDomainPlugin, kSCDynamicStoreDomainPrefs;
extern const CFStringRef kSCCompNetwork, kSCCompGlobal, kSCCompService, kSCCompInterface, kSCCompAnyRegex;
extern const CFStringRef kSCEntNetIPv4, kSCEntNetIPv6, kSCEntNetDNS, kSCEntNetProxies, kSCEntNetInterface,
    kSCEntNetLink, kSCEntNetAirPort;
extern const CFStringRef kSCPropNetIPv4Addresses, kSCPropNetIPv6Addresses, kSCPropNetInterfaces,
    kSCPropInterfaceName, kSCPropNetDNSServerAddresses, kSCPropNetDNSSearchDomains, kSCPropNetDNSDomainName,
    kSCDynamicStorePropNetPrimaryInterface, kSCDynamicStorePropNetPrimaryService;
#ifdef __cplusplus
}
#endif
#endif
