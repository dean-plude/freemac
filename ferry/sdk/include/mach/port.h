/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Mach port names (freemac 1.232, Ferry 0.56.0). Ferry has no Mach ports;
 * programs name the type, and only ever hold MACH_PORT_NULL. */
#ifndef _FERRY_MACH_PORT_H_
#define _FERRY_MACH_PORT_H_
#include <mach/mach.h>
#define MACH_PORT_DEAD ((mach_port_t)~0)
#define MACH_PORT_VALID(name) ((name) != MACH_PORT_NULL && (name) != MACH_PORT_DEAD)
#endif
