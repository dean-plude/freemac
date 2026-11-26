/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* uuid(3)'s types (freemac 1.223, Ferry 0.47.0), which a Mac's Foundation
 * brings in through NSUUID.h: a UUID as its 16 bytes, and room for its
 * 36-character string. Written from the uuid(3) man page; not Apple's
 * header. Its functions came later (freemac OBS work), for OBS, which
 * names its settings files and crash logs with new UUIDs. */
#ifndef _FERRY_UUID_UUID_H_
#define _FERRY_UUID_UUID_H_
typedef unsigned char uuid_t[16];
typedef char uuid_string_t[37];
#define UUID_DEFINE(name, u0, u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15)               \
    static const uuid_t name __attribute__((unused)) = {u0, u1, u2,  u3,  u4,  u5,  u6,  u7,                   \
                                                        u8, u9, u10, u11, u12, u13, u14, u15}
#include <_ferry.h>
__FERRY_BEGIN
void uuid_clear(uuid_t uu);
int uuid_compare(const uuid_t uu1, const uuid_t uu2);
void uuid_copy(uuid_t dst, const uuid_t src);
void uuid_generate(uuid_t out);
void uuid_generate_random(uuid_t out);
void uuid_generate_time(uuid_t out);
int uuid_is_null(const uuid_t uu);
int uuid_parse(const uuid_string_t in, uuid_t uu);
void uuid_unparse(const uuid_t uu, uuid_string_t out);
void uuid_unparse_lower(const uuid_t uu, uuid_string_t out);
void uuid_unparse_upper(const uuid_t uu, uuid_string_t out);
__FERRY_END
#endif
