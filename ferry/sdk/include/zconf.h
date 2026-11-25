/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: zlib's configuration names, the types and macros zlib's
 * manual writes its calls with, written for freemac from that manual
 * (freemac 1.226, Ferry 0.50.0); not zlib's own header. zlib.h includes
 * it, as zlib's does, and so does the copy of zlib.h that an app such as
 * Sequel Pro keeps with its sources. */
#ifndef _FERRY_ZCONF_H_
#define _FERRY_ZCONF_H_
#include <_ferry.h>
#include <sys/types.h>

#define MAX_MEM_LEVEL 9
#define MAX_WBITS 15
#define ZEXTERN extern
#define ZEXPORT
#define ZEXPORTVA
#define OF(args) args
#define FAR

typedef unsigned char Byte;
typedef unsigned int uInt;
typedef unsigned long uLong;
typedef Byte Bytef;
typedef char charf;
typedef int intf;
typedef uInt uIntf;
typedef uLong uLongf;
typedef void const *voidpc;
typedef void *voidpf;
typedef void *voidp;
typedef off_t z_off_t;
typedef off_t z_off64_t;
typedef size_t z_size_t;
typedef unsigned int z_crc_t;

#endif
