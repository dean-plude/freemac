/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The byte order of an Intel Mac, under the BSD names for it, and the
 * network byte order calls, which a Mac's <sys/types.h> brings in through
 * this header (VLC's videotoolbox module uses htonl with no other include;
 * freemac 1.NEXT). */
#ifndef _MACHINE_ENDIAN_H_
#define _MACHINE_ENDIAN_H_
#include <_ferry.h>
#define __DARWIN_LITTLE_ENDIAN 1234
#define __DARWIN_BIG_ENDIAN 4321
#define __DARWIN_PDP_ENDIAN 3412
#define __DARWIN_BYTE_ORDER __DARWIN_LITTLE_ENDIAN
#define LITTLE_ENDIAN __DARWIN_LITTLE_ENDIAN
#define BIG_ENDIAN __DARWIN_BIG_ENDIAN
#define PDP_ENDIAN __DARWIN_PDP_ENDIAN
#define BYTE_ORDER __DARWIN_BYTE_ORDER

/* network byte order (big-endian) on a little-endian Intel Mac */
#define htons(x) ((__uint16_t)__builtin_bswap16((__uint16_t)(x)))
#define ntohs(x) ((__uint16_t)__builtin_bswap16((__uint16_t)(x)))
#define htonl(x) ((__uint32_t)__builtin_bswap32((__uint32_t)(x)))
#define ntohl(x) ((__uint32_t)__builtin_bswap32((__uint32_t)(x)))
#endif
