/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _IFADDRS_H_
#define _IFADDRS_H_
#include <sys/socket.h>
__FERRY_BEGIN
struct ifaddrs {
    struct ifaddrs *ifa_next;
    char *ifa_name;
    unsigned int ifa_flags;
    struct sockaddr *ifa_addr;
    struct sockaddr *ifa_netmask;
    struct sockaddr *ifa_dstaddr;
    void *ifa_data;
};
#define ifa_broadaddr ifa_dstaddr
int getifaddrs(struct ifaddrs **list);
void freeifaddrs(struct ifaddrs *list);
__FERRY_END
#endif
