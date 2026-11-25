/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * netinet/ip.h (freemac 1.226, Ferry 0.50.0): the IPv4 header and the
 * type-of-service values for IP_TOS, as BSD has them (ip(4)). MariaDB
 * Connector/C, Sequel Pro's MySQL library, sets IPTOS_THROUGHPUT. */
#ifndef _NETINET_IP_H_
#define _NETINET_IP_H_
#include <_ferry.h>
#include <netinet/in.h>
#include <netinet/in_systm.h>

#define IPVERSION 4

struct ip {
    unsigned int ip_hl:4, ip_v:4;
    uint8_t ip_tos;
    uint16_t ip_len;
    uint16_t ip_id;
    uint16_t ip_off;
    uint8_t ip_ttl;
    uint8_t ip_p;
    uint16_t ip_sum;
    struct in_addr ip_src, ip_dst;
} __attribute__((packed, aligned(4)));

#define IP_RF 0x8000
#define IP_DF 0x4000
#define IP_MF 0x2000
#define IP_OFFMASK 0x1fff
#define IP_MAXPACKET 65535

#define IPTOS_LOWDELAY 0x10
#define IPTOS_THROUGHPUT 0x08
#define IPTOS_RELIABILITY 0x04
#define IPTOS_MINCOST 0x02

#define IPTOS_PREC_NETCONTROL 0xe0
#define IPTOS_PREC_INTERNETCONTROL 0xc0
#define IPTOS_PREC_CRITIC_ECP 0xa0
#define IPTOS_PREC_FLASHOVERRIDE 0x80
#define IPTOS_PREC_FLASH 0x60
#define IPTOS_PREC_IMMEDIATE 0x40
#define IPTOS_PREC_PRIORITY 0x20
#define IPTOS_PREC_ROUTINE 0x00

#define MAXTTL 255
#define IPDEFTTL 64
#endif
