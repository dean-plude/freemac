/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the basic types of the macOS C interface on Intel (LP64).
 * Written for freemac from the public interface; not Apple's headers. */
#ifndef _FERRY_H_
#define _FERRY_H_
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#define __FERRY_BEGIN extern "C" {
#define __FERRY_END }
#else
#define __FERRY_BEGIN
#define __FERRY_END
#endif
/* Calls whose Intel symbol carries the 64-bit-inode variant suffix. */
#define __FERRY_INODE64(name) __asm("_" #name "$INODE64")
typedef long ssize_t;
typedef int64_t off_t;
typedef uint16_t mode_t;
typedef int32_t pid_t;
typedef uint32_t uid_t;
typedef uint32_t gid_t;
typedef int32_t dev_t;
typedef uint64_t ino_t;
typedef uint16_t nlink_t;
typedef int32_t blksize_t;
typedef int64_t blkcnt_t;
typedef long time_t;
typedef int32_t suseconds_t;
typedef uint32_t useconds_t;
typedef unsigned long clock_t;
typedef uint32_t sigset_t;
typedef int64_t fpos_t;
typedef int clockid_t;
#endif
