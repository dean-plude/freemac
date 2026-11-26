/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 *
 * IOKit's display services, as a Mac's IOKit/graphics/IOGraphicsLib.h
 * names them (Qt's Cocoa plugin and font database include it). freemac's
 * displays aren't IOKit services, so there is no display to ask: the
 * functions give no information. */
#ifndef _IOKIT_IOGRAPHICSLIB_H
#define _IOKIT_IOGRAPHICSLIB_H
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

#define kIODisplayOnlyPreferredName 0x00000200
#define kDisplayProductName "DisplayProductName"
#define kDisplayVendorID "DisplayVendorID"
#define kDisplayProductID "DisplayProductID"
#define kDisplaySerialNumber "DisplaySerialNumber"

#ifdef __cplusplus
extern "C" {
#endif
CFDictionaryRef IODisplayCreateInfoDictionary(io_service_t framebuffer, IOOptionBits options);
#ifdef __cplusplus
}
#endif
#endif
