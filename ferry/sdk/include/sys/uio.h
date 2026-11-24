/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_UIO_H_
#define _SYS_UIO_H_
#include <_ferry.h>
__FERRY_BEGIN
struct iovec { void *iov_base; size_t iov_len; };
ssize_t readv(int, const struct iovec *, int);
ssize_t writev(int, const struct iovec *, int);
__FERRY_END
#endif
