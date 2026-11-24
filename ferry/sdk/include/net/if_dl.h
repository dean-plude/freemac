/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * A link-level address (AF_LINK), as getifaddrs gives one for each
 * interface: its index, type, name and hardware address. */
#ifndef _NET_IF_DL_H_
#define _NET_IF_DL_H_
#include <sys/socket.h>
struct sockaddr_dl {
    uint8_t sdl_len;
    sa_family_t sdl_family;
    uint16_t sdl_index;
    uint8_t sdl_type;
    uint8_t sdl_nlen;   /* the name's length, at the start of sdl_data */
    uint8_t sdl_alen;   /* the address's, after it */
    uint8_t sdl_slen;
    char sdl_data[12];
};
#define LLADDR(s) ((char *)((s)->sdl_data + (s)->sdl_nlen))
#endif
