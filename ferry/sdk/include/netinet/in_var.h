/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 *
 * An interface's IPv6 address flags and lifetimes, as a Mac's
 * netinet/in_var.h names them (for Qt's QNetworkInterface). Ferry answers
 * these ioctls with ENOTTY, so a program goes without the flags and
 * lifetimes, which are hints only. */
#ifndef _NETINET_IN_VAR_H_
#define _NETINET_IN_VAR_H_
#include <net/if.h>
#include <netinet/in.h>
#include <sys/types.h>

struct in6_addrlifetime {
    time_t ia6t_expire;
    time_t ia6t_preferred;
    u_int32_t ia6t_vltime;
    u_int32_t ia6t_pltime;
};

struct in6_ifreq {
    char ifr_name[IFNAMSIZ];
    union {
        struct sockaddr_in6 ifru_addr;
        struct sockaddr_in6 ifru_dstaddr;
        int ifru_flags;
        int ifru_flags6;
        int ifru_metric;
        int ifru_intval;
        char *ifru_data;
        struct in6_addrlifetime ifru_lifetime;
        u_int32_t ifru_scope_id[16];
    } ifr_ifru;
};
/* ifr_addr and the rest from net/if.h name the same members here */

#define SIOCGIFAFLAG_IN6 0xc0506949ul     /* _IOWR('i', 73, struct in6_ifreq) */
#define SIOCGIFALIFETIME_IN6 0xc0506951ul /* _IOWR('i', 81, struct in6_ifreq) */

#define IN6_IFF_ANYCAST 0x0001
#define IN6_IFF_TENTATIVE 0x0002
#define IN6_IFF_DUPLICATED 0x0004
#define IN6_IFF_DETACHED 0x0008
#define IN6_IFF_DEPRECATED 0x0010
#define IN6_IFF_NODAD 0x0020
#define IN6_IFF_AUTOCONF 0x0040
#define IN6_IFF_TEMPORARY 0x0080
#define IN6_IFF_DYNAMIC 0x0100
#define IN6_IFF_OPTIMISTIC 0x0200
#define IN6_IFF_SECURED 0x0400
#endif
