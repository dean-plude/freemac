/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The Mac's TCP socket options (tcp(4)). */
#ifndef _NETINET_TCP_H_
#define _NETINET_TCP_H_
#define TCP_NODELAY 0x01
#define TCP_MAXSEG 0x02
#define TCP_NOPUSH 0x04
#define TCP_NOOPT 0x08
#define TCP_KEEPALIVE 0x10
#define TCP_CONNECTIONTIMEOUT 0x20
#define TCP_RXT_CONNDROPTIME 0x80
#define TCP_RXT_FINDROP 0x100
#define TCP_KEEPINTVL 0x101
#define TCP_KEEPCNT 0x102
#define TCP_SENDMOREACKS 0x103
#define TCP_ENABLE_ECN 0x104
#define TCP_FASTOPEN 0x105
#define TCP_CONNECTION_INFO 0x106
#define TCP_NOTSENT_LOWAT 0x201
#endif
