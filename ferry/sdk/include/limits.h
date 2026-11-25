/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The compiler's own limits.h, and with it the system limits a Mac's
 * limits.h gives through sys/syslimits.h (freemac 1.221, Ferry 0.45.0). */
#ifndef _FERRY_LIMITS_H_
#define _FERRY_LIMITS_H_
#include_next <limits.h>
#include <sys/syslimits.h>
/* freemac 1.NEXT, as a Mac's machine/limits.h gives them (VLC) */
#ifndef SSIZE_MAX
#define SSIZE_MAX LONG_MAX
#endif
#ifndef SIZE_T_MAX
#define SIZE_T_MAX __SIZE_MAX__
#endif
#endif
