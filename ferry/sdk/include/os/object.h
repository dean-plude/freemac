/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The OS object types (dispatch's, vouchers'): in Objective-C they are
 * objects, as on a Mac; in C and C++ opaque pointers. */
#ifndef _OS_OBJECT_H_
#define _OS_OBJECT_H_
#include <_ferry.h>
#if defined(__OBJC__) && __has_feature(objc_arc) == 0 && defined(OS_OBJECT_USE_OBJC) && OS_OBJECT_USE_OBJC
#define OS_OBJECT_DECL_CLASS(name) typedef id name##_t
#else
#define OS_OBJECT_DECL_CLASS(name) typedef struct name##_s *name##_t
#endif
/* as on a Mac: 1 in Objective-C, where the objects are objects (and ARC
 * keeps them), 0 in C and C++ (freemac 1.233, VLC) */
#ifndef OS_OBJECT_USE_OBJC
#ifdef __OBJC__
#define OS_OBJECT_USE_OBJC 1
#else
#define OS_OBJECT_USE_OBJC 0
#endif
#endif
#define OS_OBJECT_RETURNS_RETAINED
#define OS_OBJECT_CONSUMED
__FERRY_BEGIN
void *os_retain(void *object);
void os_release(void *object);
__FERRY_END
#endif
