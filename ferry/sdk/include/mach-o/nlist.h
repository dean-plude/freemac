/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Symbol table entries of a Mach-O file, as the Mach-O file format
 * describes them. */
#ifndef _MACH_O_NLIST_H_
#define _MACH_O_NLIST_H_
#include <_ferry.h>
#include <stdint.h>
__FERRY_BEGIN
struct nlist {
    union { uint32_t n_strx; } n_un;
    uint8_t n_type, n_sect;
    int16_t n_desc;
    uint32_t n_value;
};
struct nlist_64 {
    union { uint32_t n_strx; } n_un;
    uint8_t n_type, n_sect;
    uint16_t n_desc;
    uint64_t n_value;
};
#define N_STAB 0xe0
#define N_PEXT 0x10
#define N_TYPE 0x0e
#define N_EXT 0x01
#define N_UNDF 0x0
#define N_ABS 0x2
#define N_SECT 0xe
#define N_PBUD 0xc
#define N_INDR 0xa
#define NO_SECT 0
#define MAX_SECT 255
#define N_WEAK_REF 0x0040
#define N_WEAK_DEF 0x0080
#define N_NO_DEAD_STRIP 0x0020
__FERRY_END
#endif
