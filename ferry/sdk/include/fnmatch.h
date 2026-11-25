/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * fnmatch(3) with the Mac's flag numbers, from its man page (freemac
 * 1.233, Ferry 0.57.0). */
#ifndef _FNMATCH_H_
#define _FNMATCH_H_
#include <_ferry.h>
__FERRY_BEGIN
#define FNM_NOMATCH 1
#define FNM_NOESCAPE 0x01
#define FNM_PATHNAME 0x02
#define FNM_PERIOD 0x04
#define FNM_LEADING_DIR 0x08
#define FNM_CASEFOLD 0x10
#define FNM_IGNORECASE FNM_CASEFOLD
#define FNM_FILE_NAME FNM_PATHNAME
int fnmatch(const char *, const char *, int);
__FERRY_END
#endif
