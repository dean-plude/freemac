/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_TYPES_H_
#define _SYS_TYPES_H_
#include <_ferry.h>
/* The BSD names for sized and unsigned types (freemac 1.221, Ferry 0.45.0). */
typedef unsigned char u_char;
typedef unsigned short u_short;
typedef unsigned int u_int;
typedef unsigned long u_long;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef uint8_t u_int8_t;
typedef uint16_t u_int16_t;
typedef uint32_t u_int32_t;
typedef uint64_t u_int64_t;
typedef int64_t quad_t;
typedef uint64_t u_quad_t;
typedef quad_t *qaddr_t;
typedef char *caddr_t;
typedef int32_t daddr_t;
typedef uint32_t fixpt_t;
typedef uint32_t id_t;
typedef int32_t key_t;
typedef int64_t register_t;
typedef int32_t segsz_t;
typedef int32_t swblk_t;
typedef int errno_t;
typedef unsigned int fsblkcnt_t;
typedef unsigned int fsfilcnt_t;
#include <sys/_pthread_types.h>
#include <machine/endian.h>
#endif
