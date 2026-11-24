/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_SELECT_H_
#define _SYS_SELECT_H_
#include <_ferry.h>
#include <sys/time.h>
#include <signal.h>
__FERRY_BEGIN
#ifndef FD_SETSIZE
#define FD_SETSIZE 1024
#endif
typedef struct fd_set { int32_t fds_bits[(FD_SETSIZE + 31) / 32]; } fd_set;
/* checks that a descriptor fits in a set (newer Mac headers' FD_SET calls it) */
int __darwin_check_fd_set_overflow(int, const void *, int);
#define FD_SET(n, p) ((void)((p)->fds_bits[(unsigned long)(n) / 32] |= (int32_t)(1u << ((unsigned long)(n) % 32))))
#define FD_CLR(n, p) ((void)((p)->fds_bits[(unsigned long)(n) / 32] &= ~(int32_t)(1u << ((unsigned long)(n) % 32))))
#define FD_ISSET(n, p) (((p)->fds_bits[(unsigned long)(n) / 32] & (int32_t)(1u << ((unsigned long)(n) % 32))) != 0)
#define FD_ZERO(p) __builtin_memset((p), 0, sizeof(*(p)))
#define FD_COPY(f, t) __builtin_memcpy((t), (f), sizeof(*(f)))
int select(int, fd_set *, fd_set *, fd_set *, struct timeval *);
int pselect(int, fd_set *, fd_set *, fd_set *, const struct timespec *, const sigset_t *);
__FERRY_END
#endif
