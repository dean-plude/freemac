/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Wayfire's IPC socket (AWayfire.m), for global hotkeys,
 * other apps' windows (Carbon.m) and the displays (NSScreen), (freemac
 * 1.215, Ferry 0.41.0). */
#ifndef FERRY_APPKIT_WAYFIRE_H
#define FERRY_APPKIT_WAYFIRE_H
#import <Foundation/Foundation.h>

/* The socket's path, or nil when there is no Wayfire to ask. */
NSString *AWayfireSocketPath(void);
BOOL AWayfireAvailable(void);
/* One request and its parsed answer (a dictionary or an array), or nil when
 * Wayfire can't be reached. Any thread. */
id AWayfireCall(NSString *method, NSDictionary *data);
/* The error in an answer ("No such method found!" when the plugin that
 * has the method isn't loaded), or nil when there is none. */
NSString *AWayfireError(id reply);
/* The displays, the main one first: dictionaries with "id", "name",
 * "frame" and "work" (NSValues holding NSRects in Wayfire's layout, whose
 * origin is at the top left and whose y runs down). nil without Wayfire. */
NSArray *AWayfireOutputs(void);
/* The program's own socket for hotkey presses, made the first time and read
 * on the main run loop; handler is called there with each press's tag. */
typedef void (*AWayfireHotkeyHandler)(int64_t tag);
NSString *AWayfireHotkeySocket(AWayfireHotkeyHandler handler);
#endif
