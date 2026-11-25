/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Extended attributes with the Mac's calls, from the getxattr(2) family
 * of man pages (freemac 1.221, Ferry 0.45.0). Ferry keeps a Mac name
 * such as com.apple.FinderInfo as the user.com.apple.FinderInfo
 * attribute of this system, the namespace an ordinary program may write,
 * and lists only those (src/libc_more.c). The position argument is for
 * resource forks, which this system doesn't have: it must be 0. */
#ifndef _FERRY_SYS_XATTR_H_
#define _FERRY_SYS_XATTR_H_
#include <_ferry.h>
__FERRY_BEGIN
#define XATTR_NOFOLLOW 0x0001
#define XATTR_CREATE 0x0002
#define XATTR_REPLACE 0x0004
#define XATTR_NOSECURITY 0x0008
#define XATTR_NODEFAULT 0x0010
#define XATTR_SHOWCOMPRESSION 0x0020
#define XATTR_MAXNAMELEN 127
#define XATTR_FINDERINFO_NAME "com.apple.FinderInfo"
#define XATTR_RESOURCEFORK_NAME "com.apple.ResourceFork"

ssize_t getxattr(const char *path, const char *name, void *value, size_t size, uint32_t position, int options);
ssize_t fgetxattr(int fd, const char *name, void *value, size_t size, uint32_t position, int options);
int setxattr(const char *path, const char *name, const void *value, size_t size, uint32_t position, int options);
int fsetxattr(int fd, const char *name, const void *value, size_t size, uint32_t position, int options);
int removexattr(const char *path, const char *name, int options);
int fremovexattr(int fd, const char *name, int options);
ssize_t listxattr(const char *path, char *namebuf, size_t size, int options);
ssize_t flistxattr(int fd, char *namebuf, size_t size, int options);
__FERRY_END
#endif
