/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Internet addresses as a Mac lays them out (with sin_len and sin6_len),
 * and the Mac's numbers for the IP and IPv6 socket options. Written from
 * the ip(4), ip6(4) and inet6(4) reference pages and RFC 3493 and 3542. */
#ifndef _NETINET_IN_H_
#define _NETINET_IN_H_
#include <sys/socket.h>
__FERRY_BEGIN
typedef uint32_t in_addr_t;
typedef uint16_t in_port_t;

#define IPPROTO_IP 0
#define IPPROTO_ICMP 1
#define IPPROTO_TCP 6
#define IPPROTO_UDP 17
#define IPPROTO_IPV6 41
#define IPPROTO_ICMPV6 58
#define IPPROTO_RAW 255

struct in_addr { in_addr_t s_addr; };
struct sockaddr_in {
    uint8_t sin_len;
    sa_family_t sin_family;
    in_port_t sin_port;
    struct in_addr sin_addr;
    char sin_zero[8];
};
#define INADDR_ANY ((in_addr_t)0x00000000)
#define INADDR_BROADCAST ((in_addr_t)0xffffffff)
#define INADDR_LOOPBACK ((in_addr_t)0x7f000001)
#define INADDR_NONE ((in_addr_t)0xffffffff)
#define IN_LOOPBACKNET 127
#define INET_ADDRSTRLEN 16
#define INET6_ADDRSTRLEN 46

struct in6_addr {
    union {
        uint8_t __u6_addr8[16];
        uint16_t __u6_addr16[8];
        uint32_t __u6_addr32[4];
    } __u6_addr;
};
#define s6_addr __u6_addr.__u6_addr8
#define s6_addr16 __u6_addr.__u6_addr16
#define s6_addr32 __u6_addr.__u6_addr32
struct sockaddr_in6 {
    uint8_t sin6_len;
    sa_family_t sin6_family;
    in_port_t sin6_port;
    uint32_t sin6_flowinfo;
    struct in6_addr sin6_addr;
    uint32_t sin6_scope_id;
};
extern const struct in6_addr in6addr_any, in6addr_loopback;
#define IN6ADDR_ANY_INIT {{{0}}}
#define IN6ADDR_LOOPBACK_INIT {{{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}}}
#define IN6_IS_ADDR_UNSPECIFIED(a) \
    ((a)->s6_addr32[0] == 0 && (a)->s6_addr32[1] == 0 && (a)->s6_addr32[2] == 0 && (a)->s6_addr32[3] == 0)
#define IN6_IS_ADDR_LOOPBACK(a) \
    ((a)->s6_addr32[0] == 0 && (a)->s6_addr32[1] == 0 && (a)->s6_addr32[2] == 0 && (a)->s6_addr32[3] == ntohl(1))
#define IN6_IS_ADDR_V4MAPPED(a) \
    ((a)->s6_addr32[0] == 0 && (a)->s6_addr32[1] == 0 && (a)->s6_addr32[2] == ntohl(0x0000ffff))
#define IN6_IS_ADDR_LINKLOCAL(a) ((a)->s6_addr[0] == 0xfe && ((a)->s6_addr[1] & 0xc0) == 0x80)
#define IN6_IS_ADDR_MULTICAST(a) ((a)->s6_addr[0] == 0xff)

struct ip_mreq { struct in_addr imr_multiaddr, imr_interface; };
struct ipv6_mreq { struct in6_addr ipv6mr_multiaddr; unsigned int ipv6mr_interface; };
struct in_pktinfo { unsigned int ipi_ifindex; struct in_addr ipi_spec_dst, ipi_addr; };
struct in6_pktinfo { struct in6_addr ipi6_addr; unsigned int ipi6_ifindex; };

#define IP_OPTIONS 1
#define IP_HDRINCL 2
#define IP_TOS 3
#define IP_TTL 4
#define IP_RECVOPTS 5
#define IP_RECVRETOPTS 6
#define IP_RECVDSTADDR 7
#define IP_RETOPTS 8
#define IP_MULTICAST_IF 9
#define IP_MULTICAST_TTL 10
#define IP_MULTICAST_LOOP 11
#define IP_ADD_MEMBERSHIP 12
#define IP_DROP_MEMBERSHIP 13
#define IP_RECVIF 20
#define IP_RECVTTL 24
#define IP_BOUND_IF 25
#define IP_PKTINFO 26
#define IP_RECVTOS 27
#define IP_DONTFRAG 28

#define IPV6_UNICAST_HOPS 4
#define IPV6_MULTICAST_IF 9
#define IPV6_MULTICAST_HOPS 10
#define IPV6_MULTICAST_LOOP 11
#define IPV6_JOIN_GROUP 12
#define IPV6_LEAVE_GROUP 13
#define IPV6_V6ONLY 27
#define IPV6_RECVTCLASS 35
#define IPV6_TCLASS 36
#define IPV6_RECVHOPLIMIT 37
#define IPV6_RECVPKTINFO 61
#define IPV6_PKTINFO 46
#define IPV6_HOPLIMIT 47
#define IPV6_DONTFRAG 62
#define IPV6_BOUND_IF 125

/* network byte order (big-endian) on a little-endian Intel Mac */
#define htons(x) ((uint16_t)__builtin_bswap16((uint16_t)(x)))
#define ntohs(x) ((uint16_t)__builtin_bswap16((uint16_t)(x)))
#define htonl(x) ((uint32_t)__builtin_bswap32((uint32_t)(x)))
#define ntohl(x) ((uint32_t)__builtin_bswap32((uint32_t)(x)))
__FERRY_END
#endif
