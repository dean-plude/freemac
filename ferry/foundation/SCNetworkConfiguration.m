/* SPDX-License-Identifier: GPL-3.0-or-later
 * SystemConfiguration's network configuration (freemac 1.271, Ferry
 * 0.94.0): the computer's network interfaces and the services on them, as
 * the Stats system monitor lists them, and CFHost's name lookups. Written
 * from Apple's public documentation of SCNetworkConfiguration and CFHost.
 *
 * An interface is one of this system's in /sys/class/net (not the loopback
 * one): its BSD name is the system's name for it ("enp3s0", "wlan0"), a
 * wireless one is IEEE 802.11 and the rest are Ethernet. Each interface has
 * one service, named after it. The preferences are read only, since this
 * system's own network settings aren't changed from here. Built without
 * ARC. */
#import "FInternal.h"
#include <SystemConfiguration/SystemConfiguration.h>
#include <SystemConfiguration/SCNetworkConfiguration.h>
#include <CFNetwork/CFNetwork.h>
#include <netdb.h>
#include <string.h>

const CFStringRef kSCNetworkInterfaceType6to4 = CFSTR("6to4");
const CFStringRef kSCNetworkInterfaceTypeBluetooth = CFSTR("Bluetooth");
const CFStringRef kSCNetworkInterfaceTypeBond = CFSTR("Bond");
const CFStringRef kSCNetworkInterfaceTypeEthernet = CFSTR("Ethernet");
const CFStringRef kSCNetworkInterfaceTypeFireWire = CFSTR("FireWire");
const CFStringRef kSCNetworkInterfaceTypeIEEE80211 = CFSTR("IEEE80211");
const CFStringRef kSCNetworkInterfaceTypeIPSec = CFSTR("IPSec");
const CFStringRef kSCNetworkInterfaceTypeL2TP = CFSTR("L2TP");
const CFStringRef kSCNetworkInterfaceTypeModem = CFSTR("Modem");
const CFStringRef kSCNetworkInterfaceTypePPP = CFSTR("PPP");
const CFStringRef kSCNetworkInterfaceTypeSerial = CFSTR("Serial");
const CFStringRef kSCNetworkInterfaceTypeVLAN = CFSTR("VLAN");
const CFStringRef kSCNetworkInterfaceTypeWWAN = CFSTR("WWAN");
const CFStringRef kSCNetworkInterfaceTypeIPv4 = CFSTR("IPv4");
const CFStringRef kSCPropNetEthernetMediaSubType = CFSTR("MediaSubType");
const CFStringRef kSCPropNetEthernetMediaOptions = CFSTR("MediaOptions");
const CFStringRef kSCPropNetEthernetMTU = CFSTR("MTU");

/* ---- interfaces -------------------------------------------------------------------- */

@interface FNetworkInterface : NSObject {
@public
    NSString *name, *type, *address;
}
@end
@implementation FNetworkInterface
- (void)dealloc
{
    [name release];
    [type release];
    [address release];
    [super dealloc];
}
@end

static NSString *read_line(NSString *path)
{
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray *interfaces(void)
{
    NSString *base = @"/sys/class/net";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *list = [NSMutableArray array];
    NSArray *names = [[fm contentsOfDirectoryAtPath:base error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *n in names) {
        NSString *dir = [base stringByAppendingPathComponent:n];
        /* the loopback interface, and virtual ones (bridges, containers' links) */
        if ([n isEqualToString:@"lo"] || ![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"device"]])
            continue;
        FNetworkInterface *i = [[[FNetworkInterface alloc] init] autorelease];
        i->name = [n copy];
        BOOL wireless = [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"wireless"]] ||
                        [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"phy80211"]];
        i->type = [(NSString *)(wireless ? kSCNetworkInterfaceTypeIEEE80211 : kSCNetworkInterfaceTypeEthernet) copy];
        i->address = [read_line([dir stringByAppendingPathComponent:@"address"]) copy];
        [list addObject:i];
    }
    return list;
}

CFArrayRef SCNetworkInterfaceCopyAll(void) { return (CFArrayRef)[interfaces() copy]; }

static FNetworkInterface *as_interface(SCNetworkInterfaceRef i)
{
    return [(id)i isKindOfClass:[FNetworkInterface class]] ? (FNetworkInterface *)i : nil;
}
CFStringRef SCNetworkInterfaceGetBSDName(SCNetworkInterfaceRef i) { return (CFStringRef)as_interface(i)->name; }
CFStringRef SCNetworkInterfaceGetInterfaceType(SCNetworkInterfaceRef i) { return (CFStringRef)as_interface(i)->type; }
CFStringRef SCNetworkInterfaceGetHardwareAddressString(SCNetworkInterfaceRef i)
{
    NSString *a = as_interface(i)->address;
    return [a length] ? (CFStringRef)a : NULL;
}
CFStringRef SCNetworkInterfaceGetLocalizedDisplayName(SCNetworkInterfaceRef i)
{
    FNetworkInterface *f = as_interface(i);
    if (!f)
        return NULL;
    return [f->type isEqualToString:(NSString *)kSCNetworkInterfaceTypeIEEE80211] ? CFSTR("Wi-Fi") : CFSTR("Ethernet");
}
SCNetworkInterfaceRef SCNetworkInterfaceGetInterface(SCNetworkInterfaceRef i) { return NULL; }
CFDictionaryRef SCNetworkInterfaceGetConfiguration(SCNetworkInterfaceRef i) { return NULL; }

/* The link's media: what /sys says of its speed and duplex, as a Mac names
 * them ("1000baseT" with "full-duplex"); an interface that is down has none. */
Boolean SCNetworkInterfaceCopyMediaOptions(SCNetworkInterfaceRef i, CFDictionaryRef *current, CFDictionaryRef *active,
                                           CFArrayRef *available, Boolean filter)
{
    FNetworkInterface *f = as_interface(i);
    if (current)
        *current = NULL;
    if (active)
        *active = NULL;
    if (available)
        *available = NULL;
    if (!f)
        return false;
    NSString *dir = [@"/sys/class/net" stringByAppendingPathComponent:f->name];
    int speed = [read_line([dir stringByAppendingPathComponent:@"speed"]) intValue];
    NSString *duplex = read_line([dir stringByAppendingPathComponent:@"duplex"]);
    if (speed <= 0)
        return false;
    NSString *sub = speed >= 10000 ? @"10GbaseT" : speed >= 2500 ? @"2500Base-T" : speed >= 1000 ? @"1000baseT"
                    : speed >= 100 ? @"100baseTX" : @"10baseT/UTP";
    NSArray *options = [duplex isEqualToString:@"full"] ? @[ @"full-duplex" ] : @[ @"half-duplex" ];
    NSDictionary *media = @{(NSString *)kSCPropNetEthernetMediaSubType : sub,
                            (NSString *)kSCPropNetEthernetMediaOptions : options};
    if (current)
        *current = (CFDictionaryRef)[media copy];
    if (active)
        *active = (CFDictionaryRef)[media copy];
    if (available)
        *available = (CFArrayRef)[@[ media ] copy];
    return true;
}

/* ---- preferences and services ------------------------------------------------------ */

@interface FNetworkPreferences : NSObject
@end
@implementation FNetworkPreferences
@end

SCPreferencesRef SCPreferencesCreate(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID)
{
    return (SCPreferencesRef)[[FNetworkPreferences alloc] init];
}
SCPreferencesRef SCPreferencesCreateWithAuthorization(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID,
                                                      void *authorization)
{
    return SCPreferencesCreate(allocator, name, prefsID);
}
Boolean SCPreferencesLock(SCPreferencesRef prefs, Boolean wait) { return false; }
Boolean SCPreferencesUnlock(SCPreferencesRef prefs) { return true; }
Boolean SCPreferencesCommitChanges(SCPreferencesRef prefs) { return false; }
Boolean SCPreferencesApplyChanges(SCPreferencesRef prefs) { return false; }
CFPropertyListRef SCPreferencesGetValue(SCPreferencesRef prefs, CFStringRef key) { return NULL; }

@interface FNetworkService : NSObject {
@public
    FNetworkInterface *interface;
}
@end
@implementation FNetworkService
- (void)dealloc
{
    [interface release];
    [super dealloc];
}
@end

CFArrayRef SCNetworkServiceCopyAll(SCPreferencesRef prefs)
{
    NSMutableArray *list = [NSMutableArray array];
    for (FNetworkInterface *i in interfaces()) {
        FNetworkService *s = [[[FNetworkService alloc] init] autorelease];
        s->interface = [i retain];
        [list addObject:s];
    }
    return (CFArrayRef)[list copy];
}

static FNetworkService *as_service(SCNetworkServiceRef s)
{
    return [(id)s isKindOfClass:[FNetworkService class]] ? (FNetworkService *)s : nil;
}
SCNetworkInterfaceRef SCNetworkServiceGetInterface(SCNetworkServiceRef s)
{
    return (SCNetworkInterfaceRef)as_service(s)->interface;
}
/* the same identifier each time for the same interface */
CFStringRef SCNetworkServiceGetServiceID(SCNetworkServiceRef s)
{
    FNetworkService *f = as_service(s);
    if (!f)
        return NULL;
    NSString *id = [NSString stringWithFormat:@"FERRY-NET-%@", [f->interface->name uppercaseString]];
    return (CFStringRef)id;
}
CFStringRef SCNetworkServiceGetName(SCNetworkServiceRef s)
{
    FNetworkService *f = as_service(s);
    return f ? SCNetworkInterfaceGetLocalizedDisplayName((SCNetworkInterfaceRef)f->interface) : NULL;
}
Boolean SCNetworkServiceGetEnabled(SCNetworkServiceRef s) { return as_service(s) != nil; }

/* ---- CFHost: a name's addresses ---------------------------------------------------- *
 * Resolved when asked, on the calling thread, with this system's resolver;
 * a host with a client callback is answered the same way, at once. */

@interface FHost : NSObject {
@public
    NSString *name;
    NSArray *addresses;
}
@end
@implementation FHost
- (void)dealloc
{
    [name release];
    [addresses release];
    [super dealloc];
}
@end

CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname)
{
    FHost *h = [[FHost alloc] init];
    h->name = [(NSString *)hostname copy];
    return (CFHostRef)h;
}

static FHost *as_host(CFHostRef h) { return [(id)h isKindOfClass:[FHost class]] ? (FHost *)h : nil; }

Boolean CFHostStartInfoResolution(CFHostRef host, CFHostInfoType info, CFStreamError *error)
{
    FHost *h = as_host(host);
    if (error)
        memset(error, 0, sizeof *error);
    if (!h || ![h->name length] || info != kCFHostAddresses) {
        if (error) {
            error->domain = kCFStreamErrorDomainNetDB;
            error->error = EAI_NONAME;
        }
        return false;
    }
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_socktype = SOCK_STREAM;
    int rc = getaddrinfo([h->name UTF8String], NULL, &hints, &res);
    if (rc != 0) {
        if (error) {
            error->domain = kCFStreamErrorDomainNetDB;
            error->error = rc;
        }
        return false;
    }
    NSMutableArray *list = [NSMutableArray array];
    for (struct addrinfo *a = res; a; a = a->ai_next)
        [list addObject:[NSData dataWithBytes:a->ai_addr length:a->ai_addrlen]];
    freeaddrinfo(res);
    [h->addresses release];
    h->addresses = [list copy];
    return true;
}
CFArrayRef CFHostGetAddressing(CFHostRef host, Boolean *hasBeenResolved)
{
    FHost *h = as_host(host);
    if (hasBeenResolved)
        *hasBeenResolved = h && h->addresses;
    return h ? (CFArrayRef)h->addresses : NULL;
}
CFArrayRef CFHostGetNames(CFHostRef host, Boolean *hasBeenResolved)
{
    FHost *h = as_host(host);
    if (hasBeenResolved)
        *hasBeenResolved = h != nil;
    return h ? (CFArrayRef)[NSArray arrayWithObject:h->name] : NULL;
}
void CFHostCancelInfoResolution(CFHostRef host, CFHostInfoType info) {}
