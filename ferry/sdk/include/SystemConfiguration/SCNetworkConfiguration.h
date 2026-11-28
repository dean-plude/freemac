/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The network configuration: interfaces, services and the preferences that
 * hold them (freemac 1.271), written from Apple's public documentation;
 * not Apple's header. Implemented in foundation/SCNetworkConfiguration.m. */
#ifndef _FERRY_SCNETWORKCONFIGURATION_H_
#define _FERRY_SCNETWORKCONFIGURATION_H_
#include <CoreFoundation/CoreFoundation.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef const struct __SCNetworkInterface *SCNetworkInterfaceRef;
typedef const struct __SCNetworkService *SCNetworkServiceRef;
typedef const struct __SCPreferences *SCPreferencesRef;

extern const CFStringRef kSCNetworkInterfaceType6to4, kSCNetworkInterfaceTypeBluetooth, kSCNetworkInterfaceTypeBond,
    kSCNetworkInterfaceTypeEthernet, kSCNetworkInterfaceTypeFireWire, kSCNetworkInterfaceTypeIEEE80211,
    kSCNetworkInterfaceTypeIPSec, kSCNetworkInterfaceTypeL2TP, kSCNetworkInterfaceTypeModem,
    kSCNetworkInterfaceTypePPP, kSCNetworkInterfaceTypeSerial, kSCNetworkInterfaceTypeVLAN,
    kSCNetworkInterfaceTypeWWAN, kSCNetworkInterfaceTypeIPv4;
extern const CFStringRef kSCPropNetEthernetMediaSubType, kSCPropNetEthernetMediaOptions, kSCPropNetEthernetMTU;

CFArrayRef SCNetworkInterfaceCopyAll(void);
CFStringRef SCNetworkInterfaceGetBSDName(SCNetworkInterfaceRef interface);
CFStringRef SCNetworkInterfaceGetInterfaceType(SCNetworkInterfaceRef interface);
CFStringRef SCNetworkInterfaceGetHardwareAddressString(SCNetworkInterfaceRef interface);
CFStringRef SCNetworkInterfaceGetLocalizedDisplayName(SCNetworkInterfaceRef interface);
SCNetworkInterfaceRef SCNetworkInterfaceGetInterface(SCNetworkInterfaceRef interface);
CFDictionaryRef SCNetworkInterfaceGetConfiguration(SCNetworkInterfaceRef interface);
Boolean SCNetworkInterfaceCopyMediaOptions(SCNetworkInterfaceRef interface, CFDictionaryRef *current,
                                           CFDictionaryRef *active, CFArrayRef *available, Boolean filter);

SCPreferencesRef SCPreferencesCreate(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
SCPreferencesRef SCPreferencesCreateWithAuthorization(CFAllocatorRef allocator, CFStringRef name,
                                                      CFStringRef prefsID, void *authorization);
Boolean SCPreferencesLock(SCPreferencesRef prefs, Boolean wait);
Boolean SCPreferencesUnlock(SCPreferencesRef prefs);
Boolean SCPreferencesCommitChanges(SCPreferencesRef prefs);
Boolean SCPreferencesApplyChanges(SCPreferencesRef prefs);
CFPropertyListRef SCPreferencesGetValue(SCPreferencesRef prefs, CFStringRef key);

CFArrayRef SCNetworkServiceCopyAll(SCPreferencesRef prefs);
SCNetworkInterfaceRef SCNetworkServiceGetInterface(SCNetworkServiceRef service);
CFStringRef SCNetworkServiceGetServiceID(SCNetworkServiceRef service);
CFStringRef SCNetworkServiceGetName(SCNetworkServiceRef service);
Boolean SCNetworkServiceGetEnabled(SCNetworkServiceRef service);

#ifdef __cplusplus
}
#endif
#endif
