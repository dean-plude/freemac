/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the runtime's export and availability markers. Written for
 * freemac from Apple's public documentation; not Apple's header. */
#ifndef _FERRY_OBJC_OBJC_API_H_
#define _FERRY_OBJC_OBJC_API_H_
#include <objc/objc.h>
#include <Availability.h>
#ifndef OBJC_EXTERN
#ifdef __cplusplus
#define OBJC_EXTERN extern "C"
#else
#define OBJC_EXTERN extern
#endif
#endif
#ifndef OBJC_EXPORT
#define OBJC_EXPORT OBJC_EXTERN
#endif
#ifndef OBJC_IMPORT
#define OBJC_IMPORT OBJC_EXTERN
#endif
#define OBJC_VISIBLE __attribute__((visibility("default")))
#define OBJC_AVAILABLE(x, i, t, w, b)
#define OBJC_OSX_AVAILABLE_OTHERS_UNAVAILABLE(x)
#define OBJC_OSX_DEPRECATED_OTHERS_UNAVAILABLE(a, b, m)
#define OBJC_ISA_AVAILABILITY
#define OBJC_SWIFT_UNAVAILABLE(m)
#define OBJC_UNAVAILABLE(m)
#define OBJC_DEPRECATED(m)
#define OBJC_INLINE __inline
#define OBJC_NOESCAPE __attribute__((noescape))
#define OBJC_RETURNS_RETAINED __attribute__((ns_returns_retained))
#define OBJC_HIDE_64
#endif
