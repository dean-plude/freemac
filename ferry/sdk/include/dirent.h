/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _DIRENT_H_
#define _DIRENT_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef struct __ferry_dir DIR;
struct dirent {
    uint64_t d_ino, d_seekoff;
    uint16_t d_reclen, d_namlen;
    uint8_t d_type;
    char d_name[1024];
};
#define DT_UNKNOWN 0
#define DT_FIFO 1
#define DT_CHR 2
#define DT_DIR 4
#define DT_BLK 6
#define DT_REG 8
#define DT_LNK 10
#define DT_SOCK 12
DIR *opendir(const char *) __FERRY_INODE64(opendir);
DIR *fdopendir(int) __FERRY_INODE64(fdopendir);
struct dirent *readdir(DIR *) __FERRY_INODE64(readdir);
void rewinddir(DIR *) __FERRY_INODE64(rewinddir);
long telldir(DIR *) __FERRY_INODE64(telldir);
void seekdir(DIR *, long) __FERRY_INODE64(seekdir);
int closedir(DIR *);
int dirfd(DIR *);
__FERRY_END
#endif
