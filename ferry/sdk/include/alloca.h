/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * alloca.h (freemac 1.226, Ferry 0.50.0): memory on the caller's stack,
 * which the compiler makes itself. A Mac's stdlib.h includes it, so
 * RegexKitLite (Sequel Pro, Gas Mask) calls alloca having included only
 * stdlib.h. */
#ifndef _ALLOCA_H_
#define _ALLOCA_H_
#include <_ferry.h>
__FERRY_BEGIN
void *alloca(size_t);
__FERRY_END
#define alloca(size) __builtin_alloca(size)
#endif
