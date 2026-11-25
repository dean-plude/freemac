/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: version numbers for availability checks, as the public
 * Availability.h names them (freemac 1.221, Ferry 0.45.0). Ferry's SDK
 * describes macOS 14.7, the version Ferry reports at run time, so that is
 * the highest version allowed; the lowest required is the deployment
 * target the compiler was given. The availability attributes themselves
 * mark nothing: everything Ferry declares is there. Written for freemac;
 * not Apple's header. */
#ifndef _FERRY_AVAILABILITY_H_
#define _FERRY_AVAILABILITY_H_

#define __MAC_10_0 1000
#define __MAC_10_1 1010
#define __MAC_10_2 1020
#define __MAC_10_3 1030
#define __MAC_10_4 1040
#define __MAC_10_5 1050
#define __MAC_10_6 1060
#define __MAC_10_7 1070
#define __MAC_10_8 1080
#define __MAC_10_9 1090
#define __MAC_10_10 101000
#define __MAC_10_10_1 101001
#define __MAC_10_10_2 101002
#define __MAC_10_10_3 101003
#define __MAC_10_10_4 101004
#define __MAC_10_10_5 101005
#define __MAC_10_11 101100
#define __MAC_10_11_1 101101
#define __MAC_10_11_2 101102
#define __MAC_10_11_3 101103
#define __MAC_10_11_4 101104
#define __MAC_10_11_5 101105
#define __MAC_10_12 101200
#define __MAC_10_12_1 101201
#define __MAC_10_12_2 101202
#define __MAC_10_12_3 101203
#define __MAC_10_12_4 101204
#define __MAC_10_12_5 101205
#define __MAC_10_13 101300
#define __MAC_10_13_1 101301
#define __MAC_10_13_2 101302
#define __MAC_10_13_3 101303
#define __MAC_10_13_4 101304
#define __MAC_10_13_5 101305
#define __MAC_10_14 101400
#define __MAC_10_14_1 101401
#define __MAC_10_14_2 101402
#define __MAC_10_14_3 101403
#define __MAC_10_14_4 101404
#define __MAC_10_14_5 101405
#define __MAC_10_15 101500
#define __MAC_10_15_1 101501
#define __MAC_10_15_2 101502
#define __MAC_10_15_3 101503
#define __MAC_10_15_4 101504
#define __MAC_10_15_5 101505
#define __MAC_11_0 110000
#define __MAC_11_1 110100
#define __MAC_11_2 110200
#define __MAC_11_3 110300
#define __MAC_11_4 110400
#define __MAC_11_5 110500
#define __MAC_11_6 110600
#define __MAC_11_7 110700
#define __MAC_12_0 120000
#define __MAC_12_1 120100
#define __MAC_12_2 120200
#define __MAC_12_3 120300
#define __MAC_12_4 120400
#define __MAC_12_5 120500
#define __MAC_12_6 120600
#define __MAC_12_7 120700
#define __MAC_13_0 130000
#define __MAC_13_1 130100
#define __MAC_13_2 130200
#define __MAC_13_3 130300
#define __MAC_13_4 130400
#define __MAC_13_5 130500
#define __MAC_13_6 130600
#define __MAC_14_0 140000
#define __MAC_14_1 140100
#define __MAC_14_2 140200
#define __MAC_14_3 140300
#define __MAC_14_4 140400
#define __MAC_14_5 140500
#define __MAC_14_6 140600
#define __MAC_14_7 140700

#ifndef __MAC_OS_X_VERSION_MIN_REQUIRED
#ifdef __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__
#define __MAC_OS_X_VERSION_MIN_REQUIRED __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__
#else
#define __MAC_OS_X_VERSION_MIN_REQUIRED __MAC_10_13
#endif
#endif
#ifndef __MAC_OS_X_VERSION_MAX_ALLOWED
#define __MAC_OS_X_VERSION_MAX_ALLOWED __MAC_14_7
#endif

/* Never a phone, a watch or a television here. */
#define __IPHONE_NA 99999
#define __MAC_NA 9999

#define __OSX_AVAILABLE(v)
#define __OSX_AVAILABLE_STARTING(mac, ios)
#define __OSX_AVAILABLE_BUT_DEPRECATED(macIntro, macDep, iosIntro, iosDep)
#define __OSX_AVAILABLE_BUT_DEPRECATED_MSG(macIntro, macDep, iosIntro, iosDep, msg)
#define __OSX_DEPRECATED(start, dep, msg)
#define __OSX_UNAVAILABLE
#define __IOS_AVAILABLE(v)
#define __IOS_DEPRECATED(start, dep, msg)
#define __IOS_PROHIBITED
#define __IOS_UNAVAILABLE
#define __TVOS_AVAILABLE(v)
#define __TVOS_PROHIBITED
#define __TVOS_UNAVAILABLE
#define __WATCHOS_AVAILABLE(v)
#define __WATCHOS_PROHIBITED
#define __WATCHOS_UNAVAILABLE
#define __API_AVAILABLE(...)
#define __API_UNAVAILABLE(...)
#define __API_DEPRECATED(...)
#define __API_DEPRECATED_WITH_REPLACEMENT(...)
#define __OS_AVAILABILITY(...)

#include <os/availability.h>
#endif
