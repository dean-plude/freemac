/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The HID Manager's type and its options (freemac OBS work), written from
 * Apple's public IOKit HID documentation; not Apple's header. Ferry finds
 * no HID devices, so only the types are here (see IOHIDDevice.h). */
#ifndef _FERRY_IOKIT_IOHIDMANAGER_H_
#define _FERRY_IOKIT_IOHIDMANAGER_H_
#include <IOKit/hid/IOHIDDevice.h>

__FERRY_BEGIN
typedef struct __IOHIDManager *IOHIDManagerRef;
enum {
    kIOHIDManagerOptionNone = 0x0,
    kIOHIDManagerOptionUsePersistentProperties = 0x1,
    kIOHIDManagerOptionDoNotLoadProperties = 0x2,
    kIOHIDManagerOptionDoNotSaveProperties = 0x4,
};
typedef uint32_t IOHIDManagerOptions;
__FERRY_END
#endif
