/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ServiceManagement's login-item call (freemac 1.219, Ferry
 * 0.43.0). Written for freemac from Apple's public documentation of
 * SMLoginItemSetEnabled; not Apple's header. The helper is the app in the
 * main bundle's Contents/Library/LoginItems whose CFBundleIdentifier is the
 * one given; turning it on writes a freedesktop autostart entry,
 * $XDG_CONFIG_HOME/autostart/ferry-login-IDENTIFIER.desktop, that runs
 * "ferry HELPER.app", and turning it off removes that entry. Launchd jobs
 * (SMJobBless, SMJobSubmit) aren't here. Served from Foundation's file. */
#ifndef _FERRY_SERVICEMANAGEMENT_H_
#define _FERRY_SERVICEMANAGEMENT_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
Boolean SMLoginItemSetEnabled(CFStringRef identifier, Boolean enabled);
__FERRY_END
#endif
