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

/* An ioctl's request about one interface, laid out as on a Mac (32 bytes).
 * Ferry answers SIOCGIFMTU; other interface ioctls give ENOTTY, and
 * getifaddrs gives the same facts. */
struct ifreq {
    char ifr_name[IFNAMSIZ];
    union {
        struct sockaddr ifru_addr;
        struct sockaddr ifru_dstaddr;
        struct sockaddr ifru_broadaddr;
        short ifru_flags;
        int ifru_metric;
        int ifru_mtu;
        int ifru_phys;
        int ifru_media;
        int ifru_intval;
        char *ifru_data;
        uint32_t ifru_wake_flags;
        int ifru_cap[2];
    } ifr_ifru;
};
#define ifr_addr ifr_ifru.ifru_addr
#define ifr_dstaddr ifr_ifru.ifru_dstaddr
#define ifr_broadaddr ifr_ifru.ifru_broadaddr
#define ifr_flags ifr_ifru.ifru_flags
#define ifr_metric ifr_ifru.ifru_metric
#define ifr_mtu ifr_ifru.ifru_mtu
#define ifr_phys ifr_ifru.ifru_phys
#define ifr_media ifr_ifru.ifru_media
#define ifr_intval ifr_ifru.ifru_intval
#define ifr_data ifr_ifru.ifru_data
#define ifr_reqcap ifr_ifru.ifru_cap[0]
#define ifr_curcap ifr_ifru.ifru_cap[1]

struct ifconf {
    int ifc_len;
    union {
        char *ifcu_buf;
        struct ifreq *ifcu_req;
    } ifc_ifcu;
};
#define ifc_buf ifc_ifcu.ifcu_buf
#define ifc_req ifc_ifcu.ifcu_req

#define SIOCGIFFLAGS 0xc0206911ul  /* _IOWR('i', 17, struct ifreq) */
#define SIOCGIFMETRIC 0xc0206917ul /* _IOWR('i', 23, struct ifreq) */
#define SIOCGIFMTU 0xc0206933ul    /* _IOWR('i', 51, struct ifreq) */

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
