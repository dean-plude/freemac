/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the BSD compiler shorthands Mac programs take for granted
 * (__unused, __BEGIN_DECLS, __printflike and so on), from the documented
 * behaviour of each (freemac 1.221, Ferry 0.45.0). Written for freemac;
 * not Apple's header. */
#ifndef _FERRY_SYS_CDEFS_H_
#define _FERRY_SYS_CDEFS_H_
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#define __P(protos) protos
#define __CONCAT(x, y) x##y
#define __STRING(x) #x
#define __unused __attribute__((__unused__))
#define __used __attribute__((__used__))
#define __dead2 __attribute__((__noreturn__))
#define __pure2 __attribute__((__const__))
#define __deprecated __attribute__((__deprecated__))
#define __deprecated_msg(m) __attribute__((__deprecated__(m)))
#define __unavailable __attribute__((__unavailable__))
#define __printflike(f, a) __attribute__((__format__(__printf__, f, a)))
#define __scanflike(f, a) __attribute__((__format__(__scanf__, f, a)))
#define __printf0like(f, a) __attribute__((__format__(__printf0__, f, a)))
#define __aligned(x) __attribute__((__aligned__(x)))
#define __packed __attribute__((__packed__))
#define __section(x) __attribute__((__section__(x)))
#define __weak_import __attribute__((__weak_import__))
#define __header_always_inline static __inline__ __attribute__((__always_inline__))
#define __DARWIN_ALIAS(sym)
#define __DARWIN_64_BIT_INO_T 1
#define __DARWIN_UNIX03 1
#define __DARWIN_C_LEVEL 900000L
#define __DARWIN_C_FULL 900000L
#define __DARWIN_NULL ((void *)0)
#endif
