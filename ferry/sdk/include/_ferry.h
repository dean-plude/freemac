/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the basic types of the macOS C interface on Intel (LP64).
 * Written for freemac from the public interface; not Apple's headers. */
#ifndef _FERRY_H_
#define _FERRY_H_
#include <stddef.h>
#include <stdint.h>
/* Every Mac header brings in the BSD shorthands (freemac 1.221, Ferry 0.45.0). */
#include <sys/cdefs.h>
#ifdef __cplusplus
#define __FERRY_BEGIN extern "C" {
#define __FERRY_END }
#else
#define __FERRY_BEGIN
#define __FERRY_END
#endif
/* CoreFoundation's calls are "audited" for ARC, as on a Mac: ARC knows by
 * their names which return a retained object, and lets an object be cast
 * to a CF type without __bridge as one of their arguments (freemac 1.223,
 * Ferry 0.47.0). No #include may come between the two. */
#if defined(__has_feature) && __has_feature(arc_cf_code_audited)
#define CF_IMPLICIT_BRIDGING_ENABLED _Pragma("clang arc_cf_code_audited begin")
#define CF_IMPLICIT_BRIDGING_DISABLED _Pragma("clang arc_cf_code_audited end")
#else
#define CF_IMPLICIT_BRIDGING_ENABLED
#define CF_IMPLICIT_BRIDGING_DISABLED
#endif
/* Calls whose Intel symbol carries the 64-bit-inode variant suffix. */
#define __FERRY_INODE64(name) __asm("_" #name "$INODE64")
typedef uint32_t __uint32_t;
/* the rest of a Mac's <sys/_types.h> fixed-width names (freemac 1.232) */
typedef int8_t __int8_t;
typedef uint8_t __uint8_t;
typedef int16_t __int16_t;
typedef uint16_t __uint16_t;
typedef int32_t __int32_t;
typedef int64_t __int64_t;
typedef uint64_t __uint64_t;
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
