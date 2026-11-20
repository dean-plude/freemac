/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: basic Objective-C integer types. Written for freemac from
 * Apple's public documentation; not Apple's header. */
#ifndef _FERRY_OBJC_NSOBJCRUNTIME_H_
#define _FERRY_OBJC_NSOBJCRUNTIME_H_
#include <_ferry.h>
typedef long NSInteger;
typedef unsigned long NSUInteger;
#define NSIntegerMax __LONG_MAX__
#define NSIntegerMin (-__LONG_MAX__ - 1L)
#define NSUIntegerMax (__LONG_MAX__ * 2UL + 1UL)
#ifndef MIN
#define MIN(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a < _b ? _a : _b; })
#endif
#ifndef MAX
#define MAX(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a > _b ? _a : _b; })
#endif
#ifndef ABS
#define ABS(a) ({ __typeof__(a) _a = (a); _a < 0 ? -_a : _a; })
#endif
#endif
