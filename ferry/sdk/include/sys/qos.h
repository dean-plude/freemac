/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Quality-of-service classes, as listed in macOS's public documentation. */
#ifndef _SYS_QOS_H_
#define _SYS_QOS_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef unsigned int qos_class_t;
#define QOS_CLASS_USER_INTERACTIVE 0x21
#define QOS_CLASS_USER_INITIATED 0x19
#define QOS_CLASS_DEFAULT 0x15
#define QOS_CLASS_UTILITY 0x11
#define QOS_CLASS_BACKGROUND 0x09
#define QOS_CLASS_UNSPECIFIED 0x00
#define QOS_MIN_RELATIVE_PRIORITY (-15)
qos_class_t qos_class_self(void);
qos_class_t qos_class_main(void);
__FERRY_END
#endif
