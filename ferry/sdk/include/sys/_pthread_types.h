/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The POSIX thread types, with the macOS sizes. On a Mac <sys/types.h>
 * brings them in, and programs rely on it (freemac 1.221, Ferry 0.45.0). */
#ifndef _FERRY_SYS_PTHREAD_TYPES_H_
#define _FERRY_SYS_PTHREAD_TYPES_H_
struct _ferry_pthread;
typedef struct _ferry_pthread *pthread_t;
typedef unsigned long pthread_key_t;
typedef struct { long __sig; char __opaque[56]; } pthread_attr_t;
typedef struct { long __sig; char __opaque[56]; } pthread_mutex_t;
typedef struct { long __sig; char __opaque[8]; } pthread_mutexattr_t;
typedef struct { long __sig; char __opaque[40]; } pthread_cond_t;
typedef struct { long __sig; char __opaque[8]; } pthread_condattr_t;
typedef struct { long __sig; char __opaque[192]; } pthread_rwlock_t;
typedef struct { long __sig; char __opaque[16]; } pthread_rwlockattr_t;
typedef struct { long __sig; char __opaque[8]; } pthread_once_t;
#endif
