/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal Shading Language, core (freemac 1.NEXT). Written from Apple's
 * public "Metal Shading Language Specification". A shader is compiled by
 * clang as C++ for OpenCL for the computer's own processor: MSL's address
 * spaces are OpenCL's (device and constant are __global, threadgroup is
 * __local, thread is the default), and the vector, matrix, texture and
 * sampler types are the classes below. Included by <metal_stdlib>. */
#ifndef __FERRY_METAL_CORE_H
#define __FERRY_METAL_CORE_H

#pragma OPENCL EXTENSION __cl_clang_function_pointers : enable
#pragma OPENCL EXTENSION __cl_clang_variadic_functions : enable
#pragma OPENCL EXTENSION __cl_clang_bitfields : enable
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#pragma clang diagnostic ignored "-Wgnu-anonymous-struct"
#pragma clang diagnostic ignored "-Wnested-anon-types"
#pragma clang diagnostic ignored "-Wunknown-attributes"
#pragma clang diagnostic ignored "-Wkeyword-macro"

/* ---- MSL's address spaces and OpenCL's keywords ------------------------------
 * device and constant memory are both OpenCL's __global (a constant reference
 * must be copyable into private memory, which __constant forbids), threadgroup
 * memory is __local and thread memory is private. OpenCL words that are plain
 * names in MSL are renamed so a shader can use them. */
#define device __global
#define constant __global
#define threadgroup __local
#define threadgroup_imageblock __local
#define thread
#define ray_data
#define object_data
#define local __ferry_kw_local
#define global __ferry_kw_global
#define generic __ferry_kw_generic
#define read_only __ferry_kw_read_only
#define write_only __ferry_kw_write_only
#define read_write __ferry_kw_read_write
#define pipe __ferry_kw_pipe
#define kernel __ferry_kw_kernel
#define sampler_t __ferry_kw_sampler_t
#define event_t __ferry_kw_event_t
#define queue_t __ferry_kw_queue_t
#define reserve_id_t __ferry_kw_reserve_id_t
#define clk_event_t __ferry_kw_clk_event_t
#define ndrange_t __ferry_kw_ndrange_t
#define atomic_int __ferry_atomic_int
#define atomic_uint __ferry_atomic_uint
#define atomic_long __ferry_atomic_long
#define atomic_ulong __ferry_atomic_ulong
#define atomic_float __ferry_atomic_float
#define atomic_double __ferry_atomic_double
#define atomic_flag __ferry_atomic_flag
#define atomic_intptr_t __ferry_atomic_intptr_t
#define atomic_uintptr_t __ferry_atomic_uintptr_t
#define atomic_size_t __ferry_atomic_size_t
#define atomic_ptrdiff_t __ferry_atomic_ptrdiff_t

/* ---- scalar types ---------------------------------------------------------- */
typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef int int32_t;
typedef unsigned int uint32_t;
typedef long int64_t;
typedef unsigned long uint64_t;
/* MSL has the C sizes too (MoltenVK's own shaders use size_t) */
typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define HUGE_VALF __builtin_huge_valf()
#define MAXFLOAT 3.40282347e+38f
#define FLT_MAX 3.40282347e+38f
#define FLT_MIN 1.17549435e-38f
#define FLT_EPSILON 1.1920929e-7f
#define HALF_MAX ((half)65504.0f)
#define INT_MAX 2147483647
#define INT_MIN (-2147483647 - 1)
#define UINT_MAX 0xffffffffu
#define M_PI_F 3.14159265358979323846f
#define M_PI_2_F 1.57079632679489661923f
#define M_PI_4_F 0.78539816339744830962f
#define M_1_PI_F 0.31830988618379067154f
#define M_2_PI_F 0.63661977236758134308f
#define M_2_SQRTPI_F 1.12837916709551257390f
#define M_SQRT2_F 1.41421356237309504880f
#define M_SQRT1_2_F 0.70710678118654752440f
#define M_E_F 2.71828182845904523536f
#define M_LOG2E_F 1.44269504088896340736f
#define M_LOG10E_F 0.43429448190325182765f
#define M_LN2_F 0.69314718055994530942f
#define M_LN10_F 2.30258509299404568402f
#define M_PI_H ((half)M_PI_F)

namespace __ferry {
template<bool B, class T = void> struct enable_if {};
template<class T> struct enable_if<true, T> { typedef T type; };
template<bool B, class T = void> using enable_if_t = typename enable_if<B, T>::type;
template<class A, class B> struct is_same { static constexpr bool value = false; };
template<class A> struct is_same<A, A> { static constexpr bool value = true; };
template<class T> struct remove_cv { typedef T type; };
template<class T> struct remove_cv<const T> { typedef T type; };
template<class T> struct remove_cv<volatile T> { typedef T type; };
template<class T> struct remove_cv<const volatile T> { typedef T type; };
template<class T> struct remove_reference { typedef T type; };
template<class T> struct remove_reference<T &> { typedef T type; };
template<class T> struct remove_reference<T &&> { typedef T type; };
template<class T> struct remove_addrspace { typedef T type; };
template<class T> struct remove_addrspace<__global T> { typedef T type; };
template<class T> struct remove_addrspace<__local T> { typedef T type; };
template<class T> struct remove_addrspace<__private T> { typedef T type; };
template<class T> struct remove_addrspace<__constant T> { typedef T type; };
template<class T> struct remove_addrspace<__generic T> { typedef T type; };
template<class T> using plain = typename remove_cv<typename remove_addrspace<typename remove_reference<T>::type>::type>::type;
template<class T> struct is_scalar_ { static constexpr bool value = false; };
#define __FERRY_SCALAR(t) template<> struct is_scalar_<t> { static constexpr bool value = true; };
__FERRY_SCALAR(bool) __FERRY_SCALAR(char) __FERRY_SCALAR(signed char) __FERRY_SCALAR(unsigned char)
__FERRY_SCALAR(short) __FERRY_SCALAR(unsigned short) __FERRY_SCALAR(int) __FERRY_SCALAR(unsigned int)
__FERRY_SCALAR(long) __FERRY_SCALAR(unsigned long) 
__FERRY_SCALAR(half) __FERRY_SCALAR(float) __FERRY_SCALAR(double)
template<class T> struct is_scalar { static constexpr bool value = is_scalar_<plain<T>>::value; };
template<class T> struct is_floating_ { static constexpr bool value = false; };
template<> struct is_floating_<half> { static constexpr bool value = true; };
template<> struct is_floating_<float> { static constexpr bool value = true; };
template<> struct is_floating_<double> { static constexpr bool value = true; };
template<class T> struct is_floating { static constexpr bool value = is_floating_<plain<T>>::value; };
template<class T> T &&declval();
}

/* The runtime's side, in Metal.framework. A compiled shader library links
 * against Metal.framework, so these resolve when the library is loaded. */
struct __ferry_tex;
extern "C" {
void __ferry_tex_read_f(const struct __ferry_tex *, int x, int y, int z, int lod, int sample, float *out);
void __ferry_tex_read_i(const struct __ferry_tex *, int x, int y, int z, int lod, int sample, unsigned int *out);
void __ferry_tex_write_f(const struct __ferry_tex *, int x, int y, int z, int lod, const float *in);
void __ferry_tex_write_i(const struct __ferry_tex *, int x, int y, int z, int lod, const unsigned int *in);
/* mode: 0 implicit lod (from the quad), 1 explicit lod, 2 bias, 3 gradient */
void __ferry_tex_sample(const struct __ferry_tex *, const void *sampler, const float *coord, int ncoord, int layer,
                        int mode, float lodval, const float *grad, const int *offset, int is_int, float *out);
float __ferry_tex_sample_compare(const struct __ferry_tex *, const void *sampler, const float *coord, int ncoord,
                                 int layer, float ref, int mode, float lodval, const int *offset);
void __ferry_tex_gather(const struct __ferry_tex *, const void *sampler, const float *coord, int ncoord, int layer,
                        const int *offset, int component, int is_int, float *out);
unsigned int __ferry_tex_size(const struct __ferry_tex *, int what, int lod);
unsigned int __ferry_tex_atomic(const struct __ferry_tex *, int x, int y, int z, int op, unsigned int v, unsigned int cmp);
void __ferry_quad_exchange(const void *val, int bytes, void *all4);
int __ferry_quad_lane(void);
void __ferry_discard(void);
void __ferry_barrier(int flags);
void __ferry_print(const char *);
}

#endif
