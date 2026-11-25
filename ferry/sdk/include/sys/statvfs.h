/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* A file system's sizes, laid out as a Mac lays them out (freemac 1.NEXT, VLC). */
#ifndef _SYS_STATVFS_H_
#define _SYS_STATVFS_H_
#include <_ferry.h>
#include <sys/types.h>
__FERRY_BEGIN
struct statvfs {
    unsigned long f_bsize, f_frsize;
    fsblkcnt_t f_blocks, f_bfree, f_bavail;
    fsfilcnt_t f_files, f_ffree, f_favail;
    unsigned long f_fsid, f_flag, f_namemax;
};
#define ST_RDONLY 0x1
#define ST_NOSUID 0x2
int statvfs(const char *, struct statvfs *);
int fstatvfs(int, struct statvfs *);
__FERRY_END
#endif
