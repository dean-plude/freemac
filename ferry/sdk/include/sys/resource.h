/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_RESOURCE_H_
#define _SYS_RESOURCE_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef uint64_t rlim_t;
struct rlimit { rlim_t rlim_cur, rlim_max; };
#define RLIM_INFINITY (((rlim_t)1 << 63) - 1)
#define RLIMIT_CPU 0
#define RLIMIT_FSIZE 1
#define RLIMIT_DATA 2
#define RLIMIT_STACK 3
#define RLIMIT_CORE 4
#define RLIMIT_AS 5
#define RLIMIT_NPROC 7
#define RLIMIT_NOFILE 8
int getrlimit(int, struct rlimit *);
int setrlimit(int, const struct rlimit *);
__FERRY_END
#endif
