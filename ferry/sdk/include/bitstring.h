/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Bit strings, the BSD macros of bitstring(3), written from the man page
 * (freemac 1.221, Ferry 0.45.0). Bit 0 is the low bit of the first byte. */
#ifndef _FERRY_BITSTRING_H_
#define _FERRY_BITSTRING_H_
#include <stdlib.h>
typedef unsigned char bitstr_t;

#define _bit_byte(bit) ((bit) >> 3)
#define _bit_mask(bit) (1 << ((bit) & 0x7))
#define bitstr_size(nbits) (((nbits) + 7) >> 3)
#define bit_alloc(nbits) (bitstr_t *)calloc((size_t)bitstr_size(nbits), sizeof(bitstr_t))
#define bit_decl(name, nbits) ((name)[bitstr_size(nbits)])
#define bit_test(name, bit) ((name)[_bit_byte(bit)] & _bit_mask(bit))
#define bit_set(name, bit) ((name)[_bit_byte(bit)] |= _bit_mask(bit))
#define bit_clear(name, bit) ((name)[_bit_byte(bit)] &= ~_bit_mask(bit))
#define bit_nclear(name, start, stop)                                       \
    do {                                                                    \
        bitstr_t *_name = (name);                                           \
        for (int _b = (start); _b <= (int)(stop); _b++)                     \
            bit_clear(_name, _b);                                           \
    } while (0)
#define bit_nset(name, start, stop)                                         \
    do {                                                                    \
        bitstr_t *_name = (name);                                           \
        for (int _b = (start); _b <= (int)(stop); _b++)                     \
            bit_set(_name, _b);                                             \
    } while (0)
#define bit_ffc(name, nbits, value)                                         \
    do {                                                                    \
        bitstr_t *_name = (name);                                           \
        int _b, _n = (nbits);                                               \
        *(value) = -1;                                                      \
        for (_b = 0; _b < _n; _b++)                                         \
            if (!bit_test(_name, _b)) {                                     \
                *(value) = _b;                                              \
                break;                                                      \
            }                                                               \
    } while (0)
#define bit_ffs(name, nbits, value)                                         \
    do {                                                                    \
        bitstr_t *_name = (name);                                           \
        int _b, _n = (nbits);                                               \
        *(value) = -1;                                                      \
        for (_b = 0; _b < _n; _b++)                                         \
            if (bit_test(_name, _b)) {                                      \
                *(value) = _b;                                              \
                break;                                                      \
            }                                                               \
    } while (0)
#endif
