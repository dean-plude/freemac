/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Call stacks as text, as a Mac's backtrace(3) page describes them
 * (freemac 1.NEXT, VLC). Served from this system's C library. */
#ifndef _FERRY_EXECINFO_H_
#define _FERRY_EXECINFO_H_
#include <_ferry.h>
__FERRY_BEGIN
int backtrace(void **, int);
char **backtrace_symbols(void *const *, int);
void backtrace_symbols_fd(void *const *, int, int);
__FERRY_END
#endif
