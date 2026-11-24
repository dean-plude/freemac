/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * A process's program path and name, from the libproc reference. */
#ifndef _LIBPROC_H_
#define _LIBPROC_H_
#include <_ferry.h>
__FERRY_BEGIN
#define PROC_PIDPATHINFO_SIZE 1024
#define PROC_PIDPATHINFO_MAXSIZE (4 * 1024)
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int proc_name(int pid, void *buffer, uint32_t buffersize);
__FERRY_END
#endif
