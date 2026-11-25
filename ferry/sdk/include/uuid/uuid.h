/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* uuid(3)'s types (freemac 1.223, Ferry 0.47.0), which a Mac's Foundation
 * brings in through NSUUID.h: a UUID as its 16 bytes, and room for its
 * 36-character string. Written from the uuid(3) man page; not Apple's
 * header. The functions aren't here: a program goes through NSUUID's
 * initWithUUIDBytes: and getUUIDBytes:, as KeePassKit does. */
#ifndef _FERRY_UUID_UUID_H_
#define _FERRY_UUID_UUID_H_
typedef unsigned char uuid_t[16];
typedef char uuid_string_t[37];
#define UUID_DEFINE(name, u0, u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15)               \
    static const uuid_t name __attribute__((unused)) = {u0, u1, u2,  u3,  u4,  u5,  u6,  u7,                   \
                                                        u8, u9, u10, u11, u12, u13, u14, u15}
#endif
