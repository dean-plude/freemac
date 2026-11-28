/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry SDK: <compression.h>, the buffer calls of a Mac's libcompression
 * (link with -lcompression). Written from Apple's public documentation.
 */
#ifndef FERRY_COMPRESSION_H
#define FERRY_COMPRESSION_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    COMPRESSION_LZ4 = 0x100,
    COMPRESSION_ZLIB = 0x205,
    COMPRESSION_LZMA = 0x306,
    COMPRESSION_LZ4_RAW = 0x101,
    COMPRESSION_BROTLI = 0xB02,
    COMPRESSION_LZFSE = 0x801,
    COMPRESSION_LZBITMAP = 0x702,
} compression_algorithm;

size_t compression_encode_scratch_buffer_size(compression_algorithm algorithm);
size_t compression_encode_buffer(uint8_t *dst_buffer, size_t dst_size, const uint8_t *src_buffer, size_t src_size,
                                 void *scratch_buffer, compression_algorithm algorithm);
size_t compression_decode_scratch_buffer_size(compression_algorithm algorithm);
size_t compression_decode_buffer(uint8_t *dst_buffer, size_t dst_size, const uint8_t *src_buffer, size_t src_size,
                                 void *scratch_buffer, compression_algorithm algorithm);

#ifdef __cplusplus
}
#endif
#endif
