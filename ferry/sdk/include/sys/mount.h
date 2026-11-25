/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* A file system's sizes and flags, as statfs(2) describes them (freemac
 * 1.223, Ferry 0.47.0), in the 64-bit-inode layout of a Mac for Intel. The
 * mount point and the kind of file system come from this system's table of
 * mounts. */
#ifndef _SYS_MOUNT_H_
#define _SYS_MOUNT_H_
#include <_ferry.h>
#include <sys/types.h>
__FERRY_BEGIN

#ifndef _FERRY_FSID_T
#define _FERRY_FSID_T
typedef struct fsid { int32_t val[2]; } fsid_t;
#endif

#define MFSNAMELEN 15
#define MFSTYPENAMELEN 16
#define MAXPATHLEN_MOUNT 1024

struct statfs {
    uint32_t f_bsize;  /* the block size the counts are in */
    int32_t f_iosize;  /* the best size to read and write in */
    uint64_t f_blocks; /* blocks in all */
    uint64_t f_bfree;  /* free */
    uint64_t f_bavail; /* free to an ordinary user */
    uint64_t f_files;  /* file nodes in all */
    uint64_t f_ffree;  /* free file nodes */
    fsid_t f_fsid;
    uid_t f_owner;
    uint32_t f_type;
    uint32_t f_flags; /* MNT_ flags */
    uint32_t f_fssubtype;
    char f_fstypename[MFSTYPENAMELEN];
    char f_mntonname[MAXPATHLEN_MOUNT];
    char f_mntfromname[MAXPATHLEN_MOUNT];
    uint32_t f_flags_ext;
    uint32_t f_reserved[7];
};

#define MNT_RDONLY 0x00000001
#define MNT_SYNCHRONOUS 0x00000002
#define MNT_NOEXEC 0x00000004
#define MNT_NOSUID 0x00000008
#define MNT_NODEV 0x00000010
#define MNT_LOCAL 0x00001000
#define MNT_QUOTA 0x00002000
#define MNT_ROOTFS 0x00004000
#define MNT_NOATIME 0x10000000

#define MNT_WAIT 1
#define MNT_NOWAIT 2

int statfs(const char *path, struct statfs *buf) __FERRY_INODE64(statfs);
int fstatfs(int fd, struct statfs *buf) __FERRY_INODE64(fstatfs);

__FERRY_END
#endif
