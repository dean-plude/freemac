/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_MMAN_H_
#define _SYS_MMAN_H_
#include <_ferry.h>
__FERRY_BEGIN
#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define PROT_EXEC 4
#define MAP_SHARED 0x0001
#define MAP_PRIVATE 0x0002
#define MAP_FIXED 0x0010
#define MAP_NORESERVE 0x0040
#define MAP_ANON 0x1000
#define MAP_ANONYMOUS MAP_ANON
#define MAP_FAILED ((void *)-1)
void *mmap(void *, size_t, int, int, int, off_t);
int munmap(void *, size_t);
int mprotect(void *, size_t, int);
/* freemac 1.232 (VLC): advice on how memory will be used */
#define MADV_NORMAL 0
#define MADV_RANDOM 1
#define MADV_SEQUENTIAL 2
#define MADV_WILLNEED 3
#define MADV_DONTNEED 4
#define POSIX_MADV_NORMAL 0
#define POSIX_MADV_RANDOM 1
#define POSIX_MADV_SEQUENTIAL 2
#define POSIX_MADV_WILLNEED 3
#define POSIX_MADV_DONTNEED 4
int madvise(void *, size_t, int);
int posix_madvise(void *, size_t, int);
int mlock(const void *, size_t);
int munlock(const void *, size_t);
__FERRY_END
#endif
