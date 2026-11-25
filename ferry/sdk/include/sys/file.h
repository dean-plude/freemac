/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * flock (freemac 1.232, Ferry 0.56.0), as BSD's <sys/file.h> declares it;
 * the lock numbers are the same on this system. Qt's QLockFile uses it. */
#ifndef _FERRY_SYS_FILE_H_
#define _FERRY_SYS_FILE_H_
#include <_ferry.h>
#include <fcntl.h>
#include <unistd.h>
__FERRY_BEGIN
#define LOCK_SH 0x01
#define LOCK_EX 0x02
#define LOCK_NB 0x04
#define LOCK_UN 0x08
int flock(int fd, int operation);
__FERRY_END
#endif
