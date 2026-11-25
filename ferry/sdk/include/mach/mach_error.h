/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The text for a Mach error number (freemac 1.NEXT, VLC). */
#ifndef _FERRY_MACH_ERROR_H_
#define _FERRY_MACH_ERROR_H_
#include <mach/mach.h>
__FERRY_BEGIN
typedef kern_return_t mach_error_t;
char *mach_error_string(mach_error_t);
void mach_error(const char *, mach_error_t);
__FERRY_END
#endif
