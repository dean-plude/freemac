/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Mach's boolean type and TRUE and FALSE, which a Mac program gets through
 * Foundation and Core Foundation (freemac 1.221, Ferry 0.45.0). */
#ifndef _FERRY_MACH_BOOLEAN_H_
#define _FERRY_MACH_BOOLEAN_H_
typedef unsigned int boolean_t;
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif
#endif
