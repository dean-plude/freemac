/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* A thread's call stack (freemac 1.232, Ferry 0.56.0), as Apple's public
 * backtrace(3) page describes it. The calls are this system's own, which
 * take the same arguments. */
#ifndef _EXECINFO_H_
#define _EXECINFO_H_
#include <_ferry.h>
__FERRY_BEGIN
int backtrace(void **array, int size);
char **backtrace_symbols(void *const *array, int size);
void backtrace_symbols_fd(void *const *array, int size, int fd);
__FERRY_END
#endif
