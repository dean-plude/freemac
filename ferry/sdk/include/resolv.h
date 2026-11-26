/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * <resolv.h> for Mac programs (freemac 1.232, Ferry 0.56.0): the resolver's
 * configuration file and res_init, as the res_init(3) man page describes
 * them. A Mac resolves names through its own system service; the state
 * structure and the res_n* calls are left out. */
#ifndef _FERRY_RESOLV_H
#define _FERRY_RESOLV_H
#include <sys/types.h>
#include <netinet/in.h>
#include <_ferry.h>
__FERRY_BEGIN
#define _PATH_RESCONF "/etc/resolv.conf"
int res_init(void);
__FERRY_END
#endif
