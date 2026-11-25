/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* What a Mach message's trailer says of its sender, as Apple's public
 * documentation of audit tokens describes it (freemac 1.224, Ferry
 * 0.48.0): only the type; no Mach messages are sent here. */
#ifndef _FERRY_MACH_MESSAGE_H_
#define _FERRY_MACH_MESSAGE_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef struct {
    unsigned int val[8];
} audit_token_t;
typedef struct {
    unsigned int val[2];
} security_token_t;
__FERRY_END
#endif
