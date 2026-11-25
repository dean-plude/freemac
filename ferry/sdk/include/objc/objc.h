/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the basic Objective-C types. Written for freemac from Apple's
 * public documentation; not Apple's header. */
#ifndef _FERRY_OBJC_OBJC_H_
#define _FERRY_OBJC_OBJC_H_
#include <_ferry.h>

#if !__has_feature(objc_arc)
#define __FERRY_OBJC_UNSAFE
#endif

typedef struct objc_class *Class;
struct objc_object { Class isa; };
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
typedef id (*IMP)(id, SEL, ...);
typedef signed char BOOL;      /* Intel Macs: a signed char */
#define YES ((BOOL)1)
#define NO ((BOOL)0)
/* As a Mac's (__DARWIN_NULL): a null pointer of no particular type, so nil
 * can be passed for any pointer, a CF or Carbon reference among them. */
#ifndef nil
#ifdef __cplusplus
#define nil __null
#else
#define nil ((void *)0)
#endif
#endif
#ifndef Nil
#ifdef __cplusplus
#define Nil __null
#else
#define Nil ((void *)0)
#endif
#endif

#if __has_feature(objc_arc)
#define OBJC_ARC_UNAVAILABLE __attribute__((unavailable("not available in automatic reference counting mode")))
#else
#define OBJC_ARC_UNAVAILABLE
#endif
#define OBJC_ROOT_CLASS __attribute__((objc_root_class))
#ifdef __cplusplus
#define OBJC_EXPORT extern "C"
#else
#define OBJC_EXPORT extern
#endif
#define NS_RETURNS_RETAINED __attribute__((ns_returns_retained))
#define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#define NS_REQUIRES_SUPER __attribute__((objc_requires_super))
#define NS_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))
#define NS_UNAVAILABLE __attribute__((unavailable))

__FERRY_BEGIN
const char *sel_getName(SEL sel);
SEL sel_registerName(const char *name);
SEL sel_getUid(const char *name);
BOOL sel_isEqual(SEL a, SEL b);
BOOL sel_isMapped(SEL sel);
const char *object_getClassName(id obj);
__FERRY_END
#endif
