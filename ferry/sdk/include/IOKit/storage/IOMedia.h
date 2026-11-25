/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The IOMedia class's name, which matching and IOObjectConformsTo take
 * (freemac 1.233, Ferry 0.57.0). Ferry has no I/O Kit registry, so no
 * object is one. Not Apple's header. */
#ifndef _FERRY_IOKIT_IOMEDIA_H_
#define _FERRY_IOKIT_IOMEDIA_H_
#include <IOKit/IOKitLib.h>
#define kIOMediaClass "IOMedia"
#define kIOMediaContentKey "Content"
#define kIOMediaEjectableKey "Ejectable"
#define kIOMediaRemovableKey "Removable"
#define kIOMediaSizeKey "Size"
#define kIOMediaWholeKey "Whole"
#define kIOMediaWritableKey "Writable"
#endif
