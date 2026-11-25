/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* flock and its operations: the same numbers on both systems (freemac 1.232, VLC). */
#ifndef _SYS_FILE_H_
#define _SYS_FILE_H_
#include <_ferry.h>
#include <fcntl.h>
#include <unistd.h>
__FERRY_BEGIN
#define LOCK_SH 0x01
#define LOCK_EX 0x02
#define LOCK_NB 0x04
#define LOCK_UN 0x08
int flock(int, int);
__FERRY_END
#endif
