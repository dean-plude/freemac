/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The bootstrap server's calls, from Apple's public bootstrap(3) reference
 * (freemac 1.265, Ferry 0.88.0): a service a program checks in is looked
 * up by the same program. */
#ifndef _FERRY_SERVERS_BOOTSTRAP_H_
#define _FERRY_SERVERS_BOOTSTRAP_H_
#include <mach/port.h>
__FERRY_BEGIN
typedef char name_t[128];
extern mach_port_t bootstrap_port;
#define BOOTSTRAP_SUCCESS 0
#define BOOTSTRAP_NOT_PRIVILEGED 1100
#define BOOTSTRAP_NAME_IN_USE 1101
#define BOOTSTRAP_UNKNOWN_SERVICE 1102
#define BOOTSTRAP_SERVICE_ACTIVE 1103
#define BOOTSTRAP_BAD_COUNT 1104
#define BOOTSTRAP_NO_MEMORY 1105
#define BOOTSTRAP_NO_CHILDREN 1106
kern_return_t bootstrap_check_in(mach_port_t bp, const name_t service_name, mach_port_t *sp);
kern_return_t bootstrap_look_up(mach_port_t bp, const name_t service_name, mach_port_t *sp);
kern_return_t bootstrap_register(mach_port_t bp, const name_t service_name, mach_port_t sp);
const char *bootstrap_strerror(kern_return_t r);
kern_return_t task_get_special_port(task_t task, int which, mach_port_t *port);
kern_return_t task_set_special_port(task_t task, int which, mach_port_t port);
#define TASK_BOOTSTRAP_PORT 4
__FERRY_END
#endif
