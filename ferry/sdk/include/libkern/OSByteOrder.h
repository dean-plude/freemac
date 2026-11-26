/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Byte order (freemac 1.238, for VLC's Core Text fonts). Ferry runs on
 * x86-64, which is little-endian, as Apple's documentation for these calls
 * describes. */
#ifndef _FERRY_LIBKERN_OSBYTEORDER_H_
#define _FERRY_LIBKERN_OSBYTEORDER_H_
#include <stdint.h>

enum { OSUnknownByteOrder, OSLittleEndian, OSBigEndian };
static inline int32_t OSHostByteOrder(void) { return OSLittleEndian; }

#define OSSwapInt16(x) ((uint16_t)__builtin_bswap16((uint16_t)(x)))
#define OSSwapInt32(x) ((uint32_t)__builtin_bswap32((uint32_t)(x)))
#define OSSwapInt64(x) ((uint64_t)__builtin_bswap64((uint64_t)(x)))
#define OSSwapConstInt16(x) OSSwapInt16(x)
#define OSSwapConstInt32(x) OSSwapInt32(x)
#define OSSwapConstInt64(x) OSSwapInt64(x)

#define OSSwapHostToBigInt16(x) OSSwapInt16(x)
#define OSSwapHostToBigInt32(x) OSSwapInt32(x)
#define OSSwapHostToBigInt64(x) OSSwapInt64(x)
#define OSSwapBigToHostInt16(x) OSSwapInt16(x)
#define OSSwapBigToHostInt32(x) OSSwapInt32(x)
#define OSSwapBigToHostInt64(x) OSSwapInt64(x)
#define OSSwapHostToLittleInt16(x) ((uint16_t)(x))
#define OSSwapHostToLittleInt32(x) ((uint32_t)(x))
#define OSSwapHostToLittleInt64(x) ((uint64_t)(x))
#define OSSwapLittleToHostInt16(x) ((uint16_t)(x))
#define OSSwapLittleToHostInt32(x) ((uint32_t)(x))
#define OSSwapLittleToHostInt64(x) ((uint64_t)(x))
#define OSSwapHostToBigConstInt16(x) OSSwapInt16(x)
#define OSSwapHostToBigConstInt32(x) OSSwapInt32(x)
#define OSSwapHostToBigConstInt64(x) OSSwapInt64(x)
#define OSSwapBigToHostConstInt16(x) OSSwapInt16(x)
#define OSSwapBigToHostConstInt32(x) OSSwapInt32(x)
#define OSSwapBigToHostConstInt64(x) OSSwapInt64(x)
#define OSSwapHostToLittleConstInt16(x) ((uint16_t)(x))
#define OSSwapHostToLittleConstInt32(x) ((uint32_t)(x))
#define OSSwapHostToLittleConstInt64(x) ((uint64_t)(x))
#define OSSwapLittleToHostConstInt16(x) ((uint16_t)(x))
#define OSSwapLittleToHostConstInt32(x) ((uint32_t)(x))
#define OSSwapLittleToHostConstInt64(x) ((uint64_t)(x))

static inline uint16_t _OSRead16(const volatile void *b, uintptr_t o)
{ uint16_t v; __builtin_memcpy(&v, (const char *)b + o, 2); return v; }
static inline uint32_t _OSRead32(const volatile void *b, uintptr_t o)
{ uint32_t v; __builtin_memcpy(&v, (const char *)b + o, 4); return v; }
static inline uint64_t _OSRead64(const volatile void *b, uintptr_t o)
{ uint64_t v; __builtin_memcpy(&v, (const char *)b + o, 8); return v; }
static inline void _OSWrite16(volatile void *b, uintptr_t o, uint16_t v)
{ __builtin_memcpy((char *)b + o, &v, 2); }
static inline void _OSWrite32(volatile void *b, uintptr_t o, uint32_t v)
{ __builtin_memcpy((char *)b + o, &v, 4); }
static inline void _OSWrite64(volatile void *b, uintptr_t o, uint64_t v)
{ __builtin_memcpy((char *)b + o, &v, 8); }

#define OSReadBigInt16(b, o) OSSwapInt16(_OSRead16((b), (o)))
#define OSReadBigInt32(b, o) OSSwapInt32(_OSRead32((b), (o)))
#define OSReadBigInt64(b, o) OSSwapInt64(_OSRead64((b), (o)))
#define OSReadLittleInt16(b, o) _OSRead16((b), (o))
#define OSReadLittleInt32(b, o) _OSRead32((b), (o))
#define OSReadLittleInt64(b, o) _OSRead64((b), (o))
#define OSWriteBigInt16(b, o, v) _OSWrite16((b), (o), OSSwapInt16(v))
#define OSWriteBigInt32(b, o, v) _OSWrite32((b), (o), OSSwapInt32(v))
#define OSWriteBigInt64(b, o, v) _OSWrite64((b), (o), OSSwapInt64(v))
#define OSWriteLittleInt16(b, o, v) _OSWrite16((b), (o), (uint16_t)(v))
#define OSWriteLittleInt32(b, o, v) _OSWrite32((b), (o), (uint32_t)(v))
#define OSWriteLittleInt64(b, o, v) _OSWrite64((b), (o), (uint64_t)(v))
#endif
