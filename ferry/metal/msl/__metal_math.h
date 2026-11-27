/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal Shading Language: the standard library functions (math,
 * common, geometric, relational, integer, pack/unpack, bit casts), as the
 * public MSL specification lists them. Every function works on the scalar
 * and on vectors, one component at a time; the processor's C library does
 * the arithmetic. */
#ifndef __FERRY_METAL_MATH_H
#define __FERRY_METAL_MATH_H
#include "__metal_vector.h"

namespace metal {
using __ferry::enable_if_t;
template<class T> struct __is_fp { static constexpr bool value = __ferry::is_floating<T>::value; };
template<class T> struct __is_int { static constexpr bool value = __ferry::is_scalar<T>::value && !__ferry::is_floating<T>::value; };

/* Applies a scalar function to every component. As in Apple's library, each
 * vector type gets its own (non-template) overload, so a scalar or a swizzle
 * converts to the vector type the way MSL code expects. */
#define __FERRY_L_fp(M, name) M(float2, name) M(float3, name) M(float4, name) M(half2, name) M(half3, name) M(half4, name)
#define __FERRY_L_int(M, name) \
    M(int2, name) M(int3, name) M(int4, name) M(uint2, name) M(uint3, name) M(uint4, name) \
    M(short2, name) M(short3, name) M(short4, name) M(ushort2, name) M(ushort3, name) M(ushort4, name) \
    M(char2, name) M(char3, name) M(char4, name) M(uchar2, name) M(uchar3, name) M(uchar4, name) \
    M(long2, name) M(long3, name) M(long4, name) M(ulong2, name) M(ulong3, name) M(ulong4, name)
#define __FERRY_L_all(M, name) __FERRY_L_fp(M, name) __FERRY_L_int(M, name)
#define __FERRY_V1_(VT, name) \
    inline VT name(VT a) { VT r; for (int i = 0; i < __ncomp<VT>::n; i++) r.c[i] = name(a.c[i]); return r; }
#define __FERRY_V2_(VT, name) \
    inline VT name(VT a, VT b) { VT r; for (int i = 0; i < __ncomp<VT>::n; i++) r.c[i] = name(a.c[i], b.c[i]); return r; }
#define __FERRY_V3_(VT, name) \
    inline VT name(VT a, VT b, VT c) \
    { VT r; for (int i = 0; i < __ncomp<VT>::n; i++) r.c[i] = name(a.c[i], b.c[i], c.c[i]); return r; }
#define __FERRY_V1(name, list) __FERRY_L_##list(__FERRY_V1_, name)
#define __FERRY_V2(name, list) __FERRY_L_##list(__FERRY_V2_, name)
#define __FERRY_V3(name, list) __FERRY_L_##list(__FERRY_V3_, name)

/* One-argument floating-point functions: float through the C library, half
 * by way of float. */
#define __FERRY_F1(name, fexpr) \
    inline float name(float x) { return fexpr; } \
    inline half name(half x) { return half(name(float(x))); } \
    __FERRY_V1(name, fp)
#define __FERRY_F2(name, fexpr) \
    inline float name(float x, float y) { return fexpr; } \
    inline half name(half x, half y) { return half(name(float(x), float(y))); } \
    __FERRY_V2(name, fp)

__FERRY_F1(sin, __builtin_sinf(x)) __FERRY_F1(cos, __builtin_cosf(x)) __FERRY_F1(tan, __builtin_tanf(x))
__FERRY_F1(asin, __builtin_asinf(x)) __FERRY_F1(acos, __builtin_acosf(x)) __FERRY_F1(atan, __builtin_atanf(x))
__FERRY_F1(sinh, __builtin_sinhf(x)) __FERRY_F1(cosh, __builtin_coshf(x)) __FERRY_F1(tanh, __builtin_tanhf(x))
__FERRY_F1(asinh, __builtin_asinhf(x)) __FERRY_F1(acosh, __builtin_acoshf(x)) __FERRY_F1(atanh, __builtin_atanhf(x))
__FERRY_F1(sinpi, __builtin_sinf(x * M_PI_F)) __FERRY_F1(cospi, __builtin_cosf(x * M_PI_F))
__FERRY_F1(tanpi, __builtin_tanf(x * M_PI_F))
__FERRY_F1(exp, __builtin_expf(x)) __FERRY_F1(exp2, __builtin_exp2f(x)) __FERRY_F1(exp10, __builtin_powf(10.0f, x))
__FERRY_F1(log, __builtin_logf(x)) __FERRY_F1(log2, __builtin_log2f(x)) __FERRY_F1(log10, __builtin_log10f(x))
__FERRY_F1(sqrt, __builtin_sqrtf(x)) __FERRY_F1(rsqrt, 1.0f / __builtin_sqrtf(x))
__FERRY_F1(floor, __builtin_floorf(x)) __FERRY_F1(ceil, __builtin_ceilf(x)) __FERRY_F1(trunc, __builtin_truncf(x))
__FERRY_F1(round, __builtin_roundf(x)) __FERRY_F1(rint, __builtin_rintf(x))
__FERRY_F1(fract, __builtin_fminf(x - __builtin_floorf(x), 0x1.fffffep-1f))
__FERRY_F1(fabs, __builtin_fabsf(x)) __FERRY_F1(saturate, __builtin_fminf(__builtin_fmaxf(x, 0.0f), 1.0f))
__FERRY_F1(sign, x > 0.0f ? 1.0f : x < 0.0f ? -1.0f : x)
__FERRY_F1(cbrt, __builtin_cbrtf(x))
__FERRY_F2(pow, __builtin_powf(x, y)) __FERRY_F2(powr, __builtin_powf(x, y)) __FERRY_F2(atan2, __builtin_atan2f(x, y))
__FERRY_F2(fmod, __builtin_fmodf(x, y)) __FERRY_F2(fmin, __builtin_fminf(x, y)) __FERRY_F2(fmax, __builtin_fmaxf(x, y))
__FERRY_F2(fdim, __builtin_fdimf(x, y)) __FERRY_F2(copysign, __builtin_copysignf(x, y))
__FERRY_F2(nextafter, __builtin_nextafterf(x, y)) __FERRY_F2(step, y < x ? 0.0f : 1.0f)
__FERRY_F2(hypot, __builtin_hypotf(x, y))
#undef __FERRY_F1
#undef __FERRY_F2
inline float divide(float x, float y) { return x / y; }
__FERRY_V2(divide, fp)
inline float fma(float a, float b, float c) { return __builtin_fmaf(a, b, c); }
inline half fma(half a, half b, half c) { return half(float(a) * float(b) + float(c)); }
__FERRY_V3(fma, fp)
inline float mad(float a, float b, float c) { return a * b + c; }
inline half mad(half a, half b, half c) { return a * b + c; }
__FERRY_V3(mad, fp)
template<class T, int N, enable_if_t<__is_fp<T>::value, int> = 0> vec<T, N> step(T e, const vec<T, N> &x)
{ return step(vec<T, N>(e), x); }
inline float ldexp(float x, int e) { return __builtin_ldexpf(x, e); }
template<int N> vec<float, N> ldexp(const vec<float, N> &x, const vec<int, N> &e)
{ vec<float, N> r; for (int i = 0; i < N; i++) r.c[i] = ldexp(x.c[i], e.c[i]); return r; }
inline float frexp(float x, thread int &e) { int k; float r = __builtin_frexpf(x, &k); e = k; return r; }
inline float modf(float x, thread float &ip) { float k; float r = __builtin_modff(x, &k); ip = k; return r; }
template<int N> vec<float, N> modf(const vec<float, N> &x, thread vec<float, N> &ip)
{ vec<float, N> r; for (int i = 0; i < N; i++) r.c[i] = modf(x.c[i], ip.c[i]); return r; }

/* min, max, clamp, abs and friends on every scalar type. */
template<class T, enable_if_t<__ferry::is_scalar<T>::value, int> = 0> T min(T a, T b) { return b < a ? b : a; }
template<class T, enable_if_t<__ferry::is_scalar<T>::value, int> = 0> T max(T a, T b) { return a < b ? b : a; }
inline float min(float a, float b) { return __builtin_fminf(a, b); }
inline float max(float a, float b) { return __builtin_fmaxf(a, b); }
template<class T, enable_if_t<__ferry::is_scalar<T>::value, int> = 0> T clamp(T x, T lo, T hi) { return min(max(x, lo), hi); }
__FERRY_V2(min, all) __FERRY_V2(max, all) __FERRY_V3(clamp, all)
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T abs(T x) { return x < 0 ? T(-x) : x; }
inline float abs(float x) { return __builtin_fabsf(x); }
inline half abs(half x) { return half(__builtin_fabsf(float(x))); }
__FERRY_V1(abs, all)
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T absdiff(T a, T b) { return a > b ? T(a - b) : T(b - a); }
__FERRY_V2(absdiff, int)
template<class T, enable_if_t<__is_fp<T>::value, int> = 0> T mix(T a, T b, T t) { return a + (b - a) * t; }
__FERRY_V3(mix, fp)
template<class T, enable_if_t<__is_fp<T>::value, int> = 0> T smoothstep(T e0, T e1, T x)
{ T t = clamp(T((x - e0) / (e1 - e0)), T(0), T(1)); return t * t * (T(3) - T(2) * t); }
__FERRY_V3(smoothstep, fp)
template<class T, int N> vec<T, N> smoothstep(T e0, T e1, const vec<T, N> &x)
{ return smoothstep(vec<T, N>(e0), vec<T, N>(e1), x); }

/* relational */
inline bool isnan(float x) { return __builtin_isnan(x); }
inline bool isinf(float x) { return __builtin_isinf(x); }
inline bool isfinite(float x) { return __builtin_isfinite(x); }
inline bool isnormal(float x) { return __builtin_isnormal(x); }
inline bool signbit(float x) { return __builtin_signbit(x); }
inline bool isnan(half x) { return isnan(float(x)); }
inline bool isinf(half x) { return isinf(float(x)); }
inline bool isfinite(half x) { return isfinite(float(x)); }
inline bool signbit(half x) { return signbit(float(x)); }
#define __FERRY_VREL(name) \
    template<class T, int N, enable_if_t<__is_fp<T>::value, int> = 0> vec<bool, N> name(const vec<T, N> &a) \
    { vec<bool, N> r; for (int i = 0; i < N; i++) r.c[i] = name(a.c[i]); return r; }
__FERRY_VREL(isnan) __FERRY_VREL(isinf) __FERRY_VREL(isfinite) __FERRY_VREL(isnormal) __FERRY_VREL(signbit)
#undef __FERRY_VREL
inline bool all(bool b) { return b; }
inline bool any(bool b) { return b; }
template<class T, int N> bool all(const vec<T, N> &v) { for (int i = 0; i < N; i++) if (!v.c[i]) return false; return true; }
template<class T, int N> bool any(const vec<T, N> &v) { for (int i = 0; i < N; i++) if (v.c[i]) return true; return false; }
template<class T, enable_if_t<__ferry::is_scalar<T>::value, int> = 0> T select(T a, T b, bool c) { return c ? b : a; }
template<class T, int N> vec<T, N> select(const vec<T, N> &a, const vec<T, N> &b, const vec<bool, N> &c)
{ vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = c.c[i] ? b.c[i] : a.c[i]; return r; }
template<class T, int N> vec<T, N> select(const vec<T, N> &a, const vec<T, N> &b, bool c) { return c ? b : a; }

/* geometric */
template<class T, int N> T dot(const vec<T, N> &a, const vec<T, N> &b)
{ T s = T(0); for (int i = 0; i < N; i++) s += a.c[i] * b.c[i]; return s; }
template<class T> vec<T, 3> cross(const vec<T, 3> &a, const vec<T, 3> &b)
{ return vec<T, 3>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }
template<class T, int N> T length_squared(const vec<T, N> &a) { return dot(a, a); }
template<class T, int N> T length(const vec<T, N> &a) { return sqrt(dot(a, a)); }
template<class T, int N> T distance(const vec<T, N> &a, const vec<T, N> &b) { return length(a - b); }
template<class T, int N> T distance_squared(const vec<T, N> &a, const vec<T, N> &b) { return length_squared(a - b); }
template<class T, int N> vec<T, N> normalize(const vec<T, N> &a) { return a * rsqrt(dot(a, a)); }
template<class T, int N> vec<T, N> reflect(const vec<T, N> &i, const vec<T, N> &n) { return i - T(2) * dot(n, i) * n; }
template<class T, int N> vec<T, N> refract(const vec<T, N> &i, const vec<T, N> &n, T eta)
{
    T d = dot(n, i), k = T(1) - eta * eta * (T(1) - d * d);
    if (k < T(0)) return vec<T, N>(T(0));
    return eta * i - (eta * d + sqrt(k)) * n;
}
template<class T, int N> vec<T, N> faceforward(const vec<T, N> &n, const vec<T, N> &i, const vec<T, N> &nref)
{ return dot(nref, i) < T(0) ? n : -n; }
/* a packed vector works in them as the vector it holds */
#define __FERRY_PK1(f) \
    template<class T, int N> auto f(const packed_vec<T, N> &a) { return f(vec<T, N>(a)); }
#define __FERRY_PK2(f) \
    template<class T, int N> auto f(const packed_vec<T, N> &a, const packed_vec<T, N> &b) \
    { return f(vec<T, N>(a), vec<T, N>(b)); } \
    template<class T, int N> auto f(const packed_vec<T, N> &a, const vec<T, N> &b) { return f(vec<T, N>(a), b); } \
    template<class T, int N> auto f(const vec<T, N> &a, const packed_vec<T, N> &b) { return f(a, vec<T, N>(b)); }
__FERRY_PK1(length) __FERRY_PK1(length_squared) __FERRY_PK1(normalize)
__FERRY_PK2(dot) __FERRY_PK2(cross) __FERRY_PK2(distance) __FERRY_PK2(distance_squared) __FERRY_PK2(reflect)
#undef __FERRY_PK1
#undef __FERRY_PK2
template<class T, int N> vec<T, N> refract(const packed_vec<T, N> &i, const packed_vec<T, N> &n, T eta)
{ return refract(vec<T, N>(i), vec<T, N>(n), eta); }
template<class T, int N> vec<T, N> refract(const packed_vec<T, N> &i, const vec<T, N> &n, T eta)
{ return refract(vec<T, N>(i), n, eta); }
template<class T, int N> vec<T, N> refract(const vec<T, N> &i, const packed_vec<T, N> &n, T eta)
{ return refract(i, vec<T, N>(n), eta); }
inline float length(float x) { return __builtin_fabsf(x); }
inline float normalize(float x) { return x < 0.0f ? -1.0f : 1.0f; }
inline float dot(float a, float b) { return a * b; }

/* integer */
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T popcount(T x)
{ return T(__builtin_popcountl((ulong)x & (~0ul >> (64 - 8 * sizeof(T))))); }
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T clz(T x)
{
    ulong v = (ulong)x & (~0ul >> (64 - 8 * sizeof(T)));
    return v ? T(__builtin_clzl(v) - (64 - 8 * sizeof(T))) : T(8 * sizeof(T));
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T ctz(T x)
{
    ulong v = (ulong)x & (~0ul >> (64 - 8 * sizeof(T)));
    return v ? T(__builtin_ctzl(v)) : T(8 * sizeof(T));
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T reverse_bits(T x)
{
    T r = 0;
    for (unsigned i = 0; i < 8 * sizeof(T); i++) r = T((r << 1) | ((x >> i) & 1));
    return r;
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T extract_bits(T x, uint off, uint bits)
{
    if (bits == 0) return T(0);
    if (bits >= 8 * sizeof(T)) return x;
    T v = T(x >> off) & T((T(1) << bits) - 1);
    if (T(-1) < T(0) && (v >> (bits - 1)) & 1) v = T(v | ~T((T(1) << bits) - 1));
    return v;
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T insert_bits(T base, T ins, uint off, uint bits)
{
    if (bits == 0) return base;
    T mask = bits >= 8 * sizeof(T) ? T(~T(0)) : T(((T(1) << bits) - 1) << off);
    return T((base & ~mask) | ((ins << off) & mask));
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T rotate(T x, T n)
{
    unsigned b = 8 * sizeof(T), k = unsigned(n) % b;
    typedef ulong U;
    return k ? T(((U)x << k | ((U)x & (~0ul >> (64 - b))) >> (b - k))) : x;
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T mulhi(T a, T b)
{
    if constexpr (sizeof(T) == 8 && T(-1) < T(0)) {
        return T(((__int128)a * (__int128)b) >> 64);
    } else if constexpr (sizeof(T) == 8) {
        return T(((unsigned __int128)a * (unsigned __int128)b) >> 64);
    } else if constexpr (T(-1) < T(0)) {
        return T(((long)a * (long)b) >> (8 * sizeof(T)));
    } else {
        return T(((ulong)a * (ulong)b) >> (8 * sizeof(T)));
    }
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T mad24(T a, T b, T c) { return a * b + c; }
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T mul24(T a, T b) { return a * b; }
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T hadd(T a, T b) { return T(((long)a + (long)b) >> 1); }
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T addsat(T a, T b)
{
    long r = (long)a + (long)b, lo = T(-1) < T(0) ? -(1l << (8 * sizeof(T) - 1)) : 0;
    long hi = T(-1) < T(0) ? (1l << (8 * sizeof(T) - 1)) - 1 : (long)(T)~T(0);
    return T(r < lo ? lo : r > hi ? hi : r);
}
template<class T, enable_if_t<__is_int<T>::value, int> = 0> T subsat(T a, T b)
{
    long r = (long)a - (long)b, lo = T(-1) < T(0) ? -(1l << (8 * sizeof(T) - 1)) : 0;
    long hi = T(-1) < T(0) ? (1l << (8 * sizeof(T) - 1)) - 1 : (long)(T)~T(0);
    return T(r < lo ? lo : r > hi ? hi : r);
}
__FERRY_V1(popcount, int) __FERRY_V1(clz, int) __FERRY_V1(ctz, int) __FERRY_V1(reverse_bits, int)
__FERRY_V2(rotate, int) __FERRY_V2(mulhi, int) __FERRY_V2(hadd, int) __FERRY_V2(addsat, int)
__FERRY_V2(subsat, int)
template<class T, int N> vec<T, N> extract_bits(const vec<T, N> &x, uint off, uint bits)
{ vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = extract_bits(x.c[i], off, bits); return r; }
template<class T, int N> vec<T, N> insert_bits(const vec<T, N> &b, const vec<T, N> &x, uint off, uint bits)
{ vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = insert_bits(b.c[i], x.c[i], off, bits); return r; }

/* as_type: reinterpret the bits. */
template<class To, class From> To as_type(const From &f)
{
    static_assert(sizeof(To) == sizeof(From), "as_type needs types of the same size");
    return __builtin_bit_cast(To, f);
}

/* pack and unpack (MSL "pack and unpack functions") */
inline float __unorm(uint v, uint bits) { return float(v) / float((1u << bits) - 1); }
inline float __snorm(int v, uint bits) { return max(-1.0f, float(v) / float((1 << (bits - 1)) - 1)); }
inline uint __to_unorm(float f, uint bits) { return uint(rint(saturate(f) * float((1u << bits) - 1))); }
inline uint __to_snorm(float f, uint bits)
{ return uint(int(rint(clamp(f, -1.0f, 1.0f) * float((1 << (bits - 1)) - 1)))) & ((1u << bits) - 1); }
inline float4 unpack_unorm4x8_to_float(uint x)
{ return float4(__unorm(x & 255, 8), __unorm(x >> 8 & 255, 8), __unorm(x >> 16 & 255, 8), __unorm(x >> 24, 8)); }
inline float4 unpack_snorm4x8_to_float(uint x)
{
    return float4(__snorm(char(x), 8), __snorm(char(x >> 8), 8), __snorm(char(x >> 16), 8), __snorm(char(x >> 24), 8));
}
inline float2 unpack_unorm2x16_to_float(uint x) { return float2(__unorm(x & 65535, 16), __unorm(x >> 16, 16)); }
inline float2 unpack_snorm2x16_to_float(uint x) { return float2(__snorm(short(x), 16), __snorm(short(x >> 16), 16)); }
inline half4 unpack_unorm4x8_to_half(uint x) { return half4(unpack_unorm4x8_to_float(x)); }
inline half4 unpack_snorm4x8_to_half(uint x) { return half4(unpack_snorm4x8_to_float(x)); }
inline half2 unpack_unorm2x16_to_half(uint x) { return half2(unpack_unorm2x16_to_float(x)); }
inline half2 unpack_snorm2x16_to_half(uint x) { return half2(unpack_snorm2x16_to_float(x)); }
inline uint pack_float_to_unorm4x8(float4 v)
{ return __to_unorm(v.x, 8) | __to_unorm(v.y, 8) << 8 | __to_unorm(v.z, 8) << 16 | __to_unorm(v.w, 8) << 24; }
inline uint pack_float_to_snorm4x8(float4 v)
{ return __to_snorm(v.x, 8) | __to_snorm(v.y, 8) << 8 | __to_snorm(v.z, 8) << 16 | __to_snorm(v.w, 8) << 24; }
inline uint pack_float_to_unorm2x16(float2 v) { return __to_unorm(v.x, 16) | __to_unorm(v.y, 16) << 16; }
inline uint pack_float_to_snorm2x16(float2 v) { return __to_snorm(v.x, 16) | __to_snorm(v.y, 16) << 16; }
inline uint pack_half_to_unorm4x8(half4 v) { return pack_float_to_unorm4x8(float4(v)); }
inline uint pack_half_to_snorm4x8(half4 v) { return pack_float_to_snorm4x8(float4(v)); }
inline uint pack_half_to_unorm2x16(half2 v) { return pack_float_to_unorm2x16(float2(v)); }
inline uint pack_half_to_snorm2x16(half2 v) { return pack_float_to_snorm2x16(float2(v)); }
inline float4 unpack_unorm10a2_to_float(uint x)
{ return float4(__unorm(x & 1023, 10), __unorm(x >> 10 & 1023, 10), __unorm(x >> 20 & 1023, 10), __unorm(x >> 30, 2)); }
inline uint pack_float_to_unorm10a2(float4 v)
{ return __to_unorm(v.x, 10) | __to_unorm(v.y, 10) << 10 | __to_unorm(v.z, 10) << 20 | __to_unorm(v.w, 2) << 30; }

#undef __FERRY_V1
#undef __FERRY_V2
#undef __FERRY_V3
#undef __FERRY_V1_
#undef __FERRY_V2_
#undef __FERRY_V3_
#undef __FERRY_L_fp
#undef __FERRY_L_int
#undef __FERRY_L_all

/* metal::fast and metal::precise name the same functions here. */
namespace fast {
using metal::sin; using metal::cos; using metal::tan; using metal::asin; using metal::acos; using metal::atan;
using metal::atan2; using metal::sinh; using metal::cosh; using metal::tanh; using metal::exp; using metal::exp2;
using metal::exp10; using metal::log; using metal::log2; using metal::log10; using metal::pow; using metal::powr;
using metal::sqrt; using metal::rsqrt; using metal::floor; using metal::ceil; using metal::round; using metal::trunc;
using metal::fract; using metal::fabs; using metal::fmin; using metal::fmax; using metal::fmod; using metal::sign;
using metal::saturate; using metal::clamp; using metal::min; using metal::max; using metal::divide;
using metal::normalize; using metal::length; using metal::distance; using metal::sinpi; using metal::cospi;
using metal::step; using metal::smoothstep; using metal::mix; using metal::rint; using metal::copysign;
}
namespace precise {
using namespace fast;
}
} // namespace metal
#endif
