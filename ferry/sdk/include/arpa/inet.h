/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _ARPA_INET_H_
#define _ARPA_INET_H_
#include <netinet/in.h>
__FERRY_BEGIN
int inet_pton(int af, const char *src, void *dst);
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);
in_addr_t inet_addr(const char *cp);
int inet_aton(const char *cp, struct in_addr *addr);
char *inet_ntoa(struct in_addr in);
in_addr_t inet_network(const char *cp);
__FERRY_END
#endif
