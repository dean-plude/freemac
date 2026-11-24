/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_UN_H_
#define _SYS_UN_H_
#include <sys/socket.h>
struct sockaddr_un {
    uint8_t sun_len;
    sa_family_t sun_family;
    char sun_path[104];
};
#define SUN_LEN(su) (sizeof(*(su)) - sizeof((su)->sun_path) + __builtin_strlen((su)->sun_path))
#endif
