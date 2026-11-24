/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Network interfaces: names and indexes (if_nametoindex(3)), the Mac's
 * interface flags, and the statistics getifaddrs gives for each link. */
#ifndef _NET_IF_H_
#define _NET_IF_H_
#include <sys/socket.h>
#include <sys/time.h>
__FERRY_BEGIN
#define IF_NAMESIZE 16
#define IFNAMSIZ IF_NAMESIZE

#define IFF_UP 0x1
#define IFF_BROADCAST 0x2
#define IFF_DEBUG 0x4
#define IFF_LOOPBACK 0x8
#define IFF_POINTOPOINT 0x10
#define IFF_NOTRAILERS 0x20
#define IFF_RUNNING 0x40
#define IFF_NOARP 0x80
#define IFF_PROMISC 0x100
#define IFF_ALLMULTI 0x200
#define IFF_OACTIVE 0x400
#define IFF_SIMPLEX 0x800
#define IFF_LINK0 0x1000
#define IFF_LINK1 0x2000
#define IFF_LINK2 0x4000
#define IFF_MULTICAST 0x8000

struct if_nameindex {
    unsigned int if_index;
    char *if_name;
};
unsigned int if_nametoindex(const char *name);
char *if_indextoname(unsigned int index, char *name);
struct if_nameindex *if_nameindex(void);
void if_freenameindex(struct if_nameindex *list);

struct timeval32 { int32_t tv_sec, tv_usec; };
/* what a link's entry in getifaddrs points ifa_data at */
struct if_data {
    unsigned char ifi_type, ifi_typelen, ifi_physical, ifi_addrlen, ifi_hdrlen, ifi_recvquota, ifi_xmitquota,
        ifi_unused1;
    uint32_t ifi_mtu, ifi_metric, ifi_baudrate;
    uint32_t ifi_ipackets, ifi_ierrors, ifi_opackets, ifi_oerrors, ifi_collisions, ifi_ibytes, ifi_obytes,
        ifi_imcasts, ifi_omcasts, ifi_iqdrops, ifi_noproto;
    uint32_t ifi_recvtiming, ifi_xmittiming;
    struct timeval32 ifi_lastchange;
    uint32_t ifi_unused2, ifi_hwassist, ifi_reserved1, ifi_reserved2;
};
__FERRY_END
#endif
