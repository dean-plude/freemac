/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The BSD system parameters a Mac's sys/param.h gives, with its values
 * (freemac 1.221, Ferry 0.45.0). */
#ifndef _FERRY_SYS_PARAM_H_
#define _FERRY_SYS_PARAM_H_
#include <sys/types.h>
#include <limits.h>
#define MAXPATHLEN PATH_MAX
#define MAXSYMLINKS 32
#define MAXHOSTNAMELEN 256
#define MAXCOMLEN 16
#define MAXLOGNAME 255
#define MAXBSIZE (1024 * 1024)
#define NOFILE 256
#define NOGROUP 65535
#define NBBY 8
#define DEV_BSIZE 512
#define CMASK 022
#define BYTE_ORDER __BYTE_ORDER__
#define LITTLE_ENDIAN __ORDER_LITTLE_ENDIAN__
#define BIG_ENDIAN __ORDER_BIG_ENDIAN__
#define PDP_ENDIAN __ORDER_PDP_ENDIAN__
#ifndef MIN
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#endif
#define howmany(x, y) ((((x) % (y)) == 0) ? ((x) / (y)) : (((x) / (y)) + 1))
#define roundup(x, y) ((((x) + ((y) - 1)) / (y)) * (y))
#define powerof2(x) ((((x) - 1) & (x)) == 0)
#define setbit(a, i) (((unsigned char *)(a))[(i) / NBBY] |= 1 << ((i) % NBBY))
#define clrbit(a, i) (((unsigned char *)(a))[(i) / NBBY] &= ~(1 << ((i) % NBBY)))
#define isset(a, i) (((const unsigned char *)(a))[(i) / NBBY] & (1 << ((i) % NBBY)))
#define isclr(a, i) ((((const unsigned char *)(a))[(i) / NBBY] & (1 << ((i) % NBBY))) == 0)
#endif
