/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: IOKit's result codes (freemac 1.223, Ferry 0.47.0), as
 * Apple's public IOKit documentation numbers them. */
#ifndef _FERRY_IOKIT_IORETURN_H_
#define _FERRY_IOKIT_IORETURN_H_
#include <_ferry.h>
typedef int IOReturn;
#define kIOReturnSuccess 0
#define kIOReturnError ((IOReturn)0xe00002bc)
#define kIOReturnNoMemory ((IOReturn)0xe00002bd)
#define kIOReturnNoResources ((IOReturn)0xe00002be)
#define kIOReturnBadArgument ((IOReturn)0xe00002c2)
#define kIOReturnUnsupported ((IOReturn)0xe00002c7)
#define kIOReturnNotPrivileged ((IOReturn)0xe00002c1)
#define kIOReturnNotFound ((IOReturn)0xe00002f0)
#define kIOReturnNoDevice ((IOReturn)0xe00002c0)
#define kIOReturnNotPermitted ((IOReturn)0xe00002e2)
#define kIOReturnBusy ((IOReturn)0xe00002d5)
#define kIOReturnTimeout ((IOReturn)0xe00002d6)
#define kIOReturnNotReady ((IOReturn)0xe00002d8)
#define kIOReturnCannotLock ((IOReturn)0xe00002cc)
#define kIOReturnExclusiveAccess ((IOReturn)0xe00002c5)
#endif
