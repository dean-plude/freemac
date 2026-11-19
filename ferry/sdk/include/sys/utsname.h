/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_UTSNAME_H_
#define _SYS_UTSNAME_H_
#include <_ferry.h>
__FERRY_BEGIN
struct utsname { char sysname[256], nodename[256], release[256], version[256], machine[256]; };
int uname(struct utsname *);
__FERRY_END
#endif
