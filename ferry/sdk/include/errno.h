/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _ERRNO_H_
#define _ERRNO_H_
#include <_ferry.h>
__FERRY_BEGIN
extern int *__error(void);
#define errno (*__error())
__FERRY_END
#define EPERM 1
#define ENOENT 2
#define ESRCH 3
#define EINTR 4
#define EIO 5
#define ENXIO 6
#define E2BIG 7
#define ENOEXEC 8
#define EBADF 9
#define ECHILD 10
#define EDEADLK 11
#define ENOMEM 12
#define EACCES 13
#define EFAULT 14
#define EBUSY 16
#define EEXIST 17
#define EXDEV 18
#define ENODEV 19
#define ENOTDIR 20
#define EISDIR 21
#define EINVAL 22
#define ENFILE 23
#define EMFILE 24
#define ENOTTY 25
#define EFBIG 27
#define ENOSPC 28
#define ESPIPE 29
#define EROFS 30
#define EMLINK 31
#define EPIPE 32
#define EDOM 33
#define ERANGE 34
#define EAGAIN 35
#define EWOULDBLOCK EAGAIN
#define EINPROGRESS 36
#define ENOTSUP 45
#define ETIMEDOUT 60
#define ECONNREFUSED 61
#define ELOOP 62
#define ENAMETOOLONG 63
#define ENOTEMPTY 66
#define ENOSYS 78
#define EOVERFLOW 84
#define EILSEQ 92
#endif
