/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * basename(3) and dirname(3) as the Mac has them: the path is left alone
 * and the answer is kept in storage of the call's own, one per thread;
 * the _r forms write into the caller's buffer of MAXPATHLEN bytes
 * (freemac 1.221, Ferry 0.45.0; src/libc_more.c). */
#ifndef _FERRY_LIBGEN_H_
#define _FERRY_LIBGEN_H_
#include <_ferry.h>
__FERRY_BEGIN
char *basename(char *path);
char *basename_r(const char *path, char *bname);
char *dirname(char *path);
char *dirname_r(const char *path, char *dname);
__FERRY_END
#endif
