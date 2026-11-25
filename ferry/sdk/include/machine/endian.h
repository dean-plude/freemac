/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The byte order of an Intel Mac, under the BSD names for it. */
#ifndef _MACHINE_ENDIAN_H_
#define _MACHINE_ENDIAN_H_
#define __DARWIN_LITTLE_ENDIAN 1234
#define __DARWIN_BIG_ENDIAN 4321
#define __DARWIN_PDP_ENDIAN 3412
#define __DARWIN_BYTE_ORDER __DARWIN_LITTLE_ENDIAN
#define LITTLE_ENDIAN __DARWIN_LITTLE_ENDIAN
#define BIG_ENDIAN __DARWIN_BIG_ENDIAN
#define PDP_ENDIAN __DARWIN_PDP_ENDIAN
#define BYTE_ORDER __DARWIN_BYTE_ORDER
#endif
