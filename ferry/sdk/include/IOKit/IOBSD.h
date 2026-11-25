/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Matching an I/O Kit object by its BSD device name (freemac 1.NEXT, Ferry
 * 0.NEXT). Declared with the rest in IOKitLib.h. Not Apple's header. */
#ifndef _FERRY_IOKIT_IOBSD_H_
#define _FERRY_IOKIT_IOBSD_H_
#include <IOKit/IOKitLib.h>
#define kIOBSDNameKey "BSD Name"
#define kIOBSDMajorKey "BSD Major"
#define kIOBSDMinorKey "BSD Minor"
#define kIOBSDUnitKey "BSD Unit"
#endif
