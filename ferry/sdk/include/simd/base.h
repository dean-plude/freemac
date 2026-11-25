/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The base of the Mac's simd library, which programs bring in only for its
 * markers (OBS's sse-intrin.h, freemac OBS work): how simd's small inline
 * functions are declared, and whether the compiler can build them. Written
 * from the simd documentation; not Apple's header. Ferry has none of
 * simd's vector types or functions yet. */
#ifndef _FERRY_SIMD_BASE_H_
#define _FERRY_SIMD_BASE_H_
#if defined(__clang__) && __has_attribute(__overloadable__) && __has_attribute(__ext_vector_type__)
#define SIMD_COMPILER_HAS_REQUIRED_FEATURES 1
#else
#define SIMD_COMPILER_HAS_REQUIRED_FEATURES 0
#endif
#define SIMD_LIBRARY_VERSION 0
#define __SIMD_INLINE__ __attribute__((__always_inline__))
#define __SIMD_ATTRIBUTES__ __attribute__((__always_inline__, __nodebug__))
#define __SIMD_OVERLOAD__ __attribute__((__overloadable__))
#define SIMD_CPPFUNC __SIMD_ATTRIBUTES__ inline
#define SIMD_CFUNC __SIMD_ATTRIBUTES__ __SIMD_OVERLOAD__ static inline
#define SIMD_INLINE __SIMD_INLINE__ static inline
#define SIMD_NOINLINE __attribute__((__noinline__)) __SIMD_OVERLOAD__
#define SIMD_OVERLOAD __SIMD_OVERLOAD__
#endif
