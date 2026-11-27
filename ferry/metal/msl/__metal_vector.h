/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal Shading Language: vectors and matrices (MSL specification,
 * sections on vector and matrix data types). A vector's components are real
 * members (.x .y .z .w and .r .g .b .a), so they can be bound to references;
 * longer swizzles are properties (gen-swizzles.py). */
#ifndef __FERRY_METAL_VECTOR_H
#define __FERRY_METAL_VECTOR_H
#include "__metal_core.h"

namespace metal {
template<class T, int N> struct vec;
template<class T, int N> struct __vstore;

#define __FERRY_SWG(name, n, ...) \
    vec<T, n> __g_##name() const { return vec<T, n>(__VA_ARGS__); }
#define __FERRY_SWS(name, n, ...) \
    void __s_##name(vec<T, n> __v) { __VA_ARGS__ }

template<class T> struct __vstore<T, 1> {
    union { T c[1]; struct { T x; }; struct { T r; }; };
};
template<class T> struct __vstore<T, 2> {
    union { T c[2]; struct { T x, y; }; struct { T r, g; }; };
#include "__metal_swizzle_2.h"
};
template<class T> struct __vstore<T, 3> {
    union { T c[3]; struct { T x, y, z; }; struct { T r, g, b; }; };
#include "__metal_swizzle_3.h"
};
template<class T> struct __vstore<T, 4> {
    union { T c[4]; struct { T x, y, z, w; }; struct { T r, g, b, a; }; };
#include "__metal_swizzle_4.h"
};
#undef __FERRY_SWG
#undef __FERRY_SWS

template<class T> struct __ncomp { static constexpr int n = 1; };
template<class T, int N> struct __ncomp<vec<T, N>> { static constexpr int n = N; };
template<class T> struct __comps { static constexpr int n = __ncomp<__ferry::plain<T>>::n; };

template<class T, int N> struct alignas(sizeof(T) * (N == 3 ? 4 : N)) vec : __vstore<T, N> {
    typedef T value_type;
    vec() = default;
    vec(const vec &) = default;
    vec &operator=(const vec &) = default;
    vec(T s) { for (int i = 0; i < N; i++) this->c[i] = s; }
    template<class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value && !__ferry::is_same<__ferry::plain<U>, T>::value, int> = 0>
    explicit vec(U s) { for (int i = 0; i < N; i++) this->c[i] = T(s); }
    template<class U, __ferry::enable_if_t<!__ferry::is_same<U, T>::value, int> = 0>
    explicit vec(const vec<U, N> &o) { for (int i = 0; i < N; i++) this->c[i] = T(o.c[i]); }
    template<class A, class B, class... R,
             __ferry::enable_if_t<(__comps<A>::n + __comps<B>::n + (0 + ... + __comps<R>::n)) == N, int> = 0>
    vec(const A &a, const B &b, const R &...r)
    {
        int i = 0;
        __put(i, a);
        __put(i, b);
        (__put(i, r), ...);
    }
    template<class U> void __put(int &i, const U &s)
    {
        typedef __ferry::plain<U> P;
        if constexpr (__ncomp<P>::n > 1) {
            for (int k = 0; k < __ncomp<P>::n; k++) this->c[i++] = T(s.c[k]);
        } else {
            this->c[i++] = T(s);
        }
    }
    T &operator[](int i) { return this->c[i]; }
    const T &operator[](int i) const { return this->c[i]; }
};

/* packed_floatN and friends: the same components without the padding. */
template<class T, int N> struct packed_vec : __vstore<T, N> {
    packed_vec() = default;
    packed_vec(const vec<T, N> &v) { for (int i = 0; i < N; i++) this->c[i] = v.c[i]; }
    template<class A, class... R, __ferry::enable_if_t<(__comps<A>::n + (0 + ... + __comps<R>::n)) == N, int> = 0>
    packed_vec(const A &a, const R &...r) { *this = vec<T, N>(a, r...); }
    operator vec<T, N>() const { vec<T, N> v; for (int i = 0; i < N; i++) v.c[i] = this->c[i]; return v; }
    T &operator[](int i) { return this->c[i]; }
    const T &operator[](int i) const { return this->c[i]; }
};
template<class T, int N> struct __ncomp<packed_vec<T, N>> { static constexpr int n = N; };

/* ---- operators ---------------------------------------------------------------- */
#define __FERRY_VBIN(op) \
    template<class T, int N> vec<T, N> operator op(const vec<T, N> &a, const vec<T, N> &b) \
    { vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = T(a.c[i] op b.c[i]); return r; } \
    template<class T, int N, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0> \
    vec<T, N> operator op(const vec<T, N> &a, U b) \
    { vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = T(a.c[i] op T(b)); return r; } \
    template<class T, int N, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0> \
    vec<T, N> operator op(U a, const vec<T, N> &b) \
    { vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = T(T(a) op b.c[i]); return r; } \
    template<class T, int N, class X> vec<T, N> &operator op##=(vec<T, N> &a, const X &b) \
    { a = a op b; return a; }
__FERRY_VBIN(+) __FERRY_VBIN(-) __FERRY_VBIN(*) __FERRY_VBIN(/) __FERRY_VBIN(%)
__FERRY_VBIN(&) __FERRY_VBIN(|) __FERRY_VBIN(^) __FERRY_VBIN(<<) __FERRY_VBIN(>>)
#undef __FERRY_VBIN
/* % on floating-point vectors is fmod in MSL's GLSL-derived code; C++ has none. */
template<int N> vec<float, N> operator%(const vec<float, N> &a, const vec<float, N> &b)
{ vec<float, N> r; for (int i = 0; i < N; i++) r.c[i] = __builtin_fmodf(a.c[i], b.c[i]); return r; }

#define __FERRY_VCMP(op) \
    template<class T, int N> vec<bool, N> operator op(const vec<T, N> &a, const vec<T, N> &b) \
    { vec<bool, N> r; for (int i = 0; i < N; i++) r.c[i] = a.c[i] op b.c[i]; return r; } \
    template<class T, int N, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0> \
    vec<bool, N> operator op(const vec<T, N> &a, U b) \
    { vec<bool, N> r; for (int i = 0; i < N; i++) r.c[i] = a.c[i] op T(b); return r; } \
    template<class T, int N, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0> \
    vec<bool, N> operator op(U a, const vec<T, N> &b) \
    { vec<bool, N> r; for (int i = 0; i < N; i++) r.c[i] = T(a) op b.c[i]; return r; }
__FERRY_VCMP(==) __FERRY_VCMP(!=) __FERRY_VCMP(<) __FERRY_VCMP(>) __FERRY_VCMP(<=) __FERRY_VCMP(>=)
__FERRY_VCMP(&&) __FERRY_VCMP(||)
#undef __FERRY_VCMP

template<class T, int N> vec<T, N> operator-(const vec<T, N> &a)
{ vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = T(-a.c[i]); return r; }
template<class T, int N> vec<T, N> operator+(const vec<T, N> &a) { return a; }
template<class T, int N> vec<T, N> operator~(const vec<T, N> &a)
{ vec<T, N> r; for (int i = 0; i < N; i++) r.c[i] = T(~a.c[i]); return r; }
template<class T, int N> vec<bool, N> operator!(const vec<T, N> &a)
{ vec<bool, N> r; for (int i = 0; i < N; i++) r.c[i] = !a.c[i]; return r; }
template<class T, int N> vec<T, N> &operator++(vec<T, N> &a) { for (int i = 0; i < N; i++) ++a.c[i]; return a; }
template<class T, int N> vec<T, N> &operator--(vec<T, N> &a) { for (int i = 0; i < N; i++) --a.c[i]; return a; }
template<class T, int N> vec<T, N> operator++(vec<T, N> &a, int) { vec<T, N> o = a; ++a; return o; }
template<class T, int N> vec<T, N> operator--(vec<T, N> &a, int) { vec<T, N> o = a; --a; return o; }

/* ---- matrices (column-major: floatCxR has C columns of R rows) ----------------- */
template<class T, int C, int R> struct matrix {
    vec<T, R> columns[C];
    matrix() = default;
    matrix(const matrix &) = default;
    matrix &operator=(const matrix &) = default;
    explicit matrix(T s)
    {
        for (int c = 0; c < C; c++)
            for (int r = 0; r < R; r++) columns[c].c[r] = c == r ? s : T(0);
    }
    template<class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value && !__ferry::is_same<__ferry::plain<U>, T>::value, int> = 0>
    explicit matrix(U s) : matrix(T(s)) {}
    template<class... V, __ferry::enable_if_t<sizeof...(V) == C && (... && __ferry::is_same<__ferry::plain<V>, vec<T, R>>::value), int> = 0>
    matrix(const V &...cols)
    {
        int i = 0;
        ((columns[i++] = cols), ...);
    }
    template<class... S, __ferry::enable_if_t<sizeof...(S) == C * R && C * R != C && (... && __ferry::is_scalar<S>::value), int> = 0>
    matrix(const S &...s)
    {
        T v[C * R] = {T(s)...};
        for (int c = 0; c < C; c++)
            for (int r = 0; r < R; r++) columns[c].c[r] = v[c * R + r];
    }
    template<class U, __ferry::enable_if_t<!__ferry::is_same<U, T>::value, int> = 0>
    explicit matrix(const matrix<U, C, R> &o)
    {
        for (int c = 0; c < C; c++) columns[c] = vec<T, R>(o.columns[c]);
    }
    vec<T, R> &operator[](int i) { return columns[i]; }
    const vec<T, R> &operator[](int i) const { return columns[i]; }
};
template<class T, int C, int R> struct __ncomp<matrix<T, C, R>> { static constexpr int n = C * R; };

template<class T, int C, int R> vec<T, R> operator*(const matrix<T, C, R> &m, const vec<T, C> &v)
{
    vec<T, R> r(T(0));
    for (int c = 0; c < C; c++) r = r + m.columns[c] * v.c[c];
    return r;
}
template<class T, int C, int R> vec<T, C> operator*(const vec<T, R> &v, const matrix<T, C, R> &m)
{
    vec<T, C> r;
    for (int c = 0; c < C; c++) {
        T s = T(0);
        for (int k = 0; k < R; k++) s += v.c[k] * m.columns[c].c[k];
        r.c[c] = s;
    }
    return r;
}
template<class T, int C, int K, int R> matrix<T, C, R> operator*(const matrix<T, K, R> &a, const matrix<T, C, K> &b)
{
    matrix<T, C, R> r;
    for (int c = 0; c < C; c++) r.columns[c] = a * b.columns[c];
    return r;
}
template<class T, int C, int R, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0>
matrix<T, C, R> operator*(const matrix<T, C, R> &m, U s)
{ matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = m.columns[c] * T(s); return r; }
template<class T, int C, int R, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0>
matrix<T, C, R> operator*(U s, const matrix<T, C, R> &m) { return m * s; }
template<class T, int C, int R, class U, __ferry::enable_if_t<__ferry::is_scalar<U>::value, int> = 0>
matrix<T, C, R> operator/(const matrix<T, C, R> &m, U s)
{ matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = m.columns[c] / T(s); return r; }
template<class T, int C, int R> matrix<T, C, R> operator+(const matrix<T, C, R> &a, const matrix<T, C, R> &b)
{ matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = a.columns[c] + b.columns[c]; return r; }
template<class T, int C, int R> matrix<T, C, R> operator-(const matrix<T, C, R> &a, const matrix<T, C, R> &b)
{ matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = a.columns[c] - b.columns[c]; return r; }
template<class T, int C, int R> matrix<T, C, R> operator-(const matrix<T, C, R> &a)
{ matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = -a.columns[c]; return r; }
template<class T, int C, int R, class X> matrix<T, C, R> &operator*=(matrix<T, C, R> &a, const X &b) { a = a * b; return a; }
template<class T, int C, int R, class X> matrix<T, C, R> &operator/=(matrix<T, C, R> &a, const X &b) { a = a / b; return a; }
template<class T, int C, int R> matrix<T, C, R> &operator+=(matrix<T, C, R> &a, const matrix<T, C, R> &b) { a = a + b; return a; }
template<class T, int C, int R> matrix<T, C, R> &operator-=(matrix<T, C, R> &a, const matrix<T, C, R> &b) { a = a - b; return a; }
template<class T, int C, int R> bool operator==(const matrix<T, C, R> &a, const matrix<T, C, R> &b)
{
    for (int c = 0; c < C; c++)
        for (int r = 0; r < R; r++)
            if (a.columns[c].c[r] != b.columns[c].c[r]) return false;
    return true;
}
template<class T, int C, int R> bool operator!=(const matrix<T, C, R> &a, const matrix<T, C, R> &b) { return !(a == b); }

template<class T, int C, int R> matrix<T, R, C> transpose(const matrix<T, C, R> &m)
{
    matrix<T, R, C> r;
    for (int c = 0; c < C; c++)
        for (int k = 0; k < R; k++) r.columns[k].c[c] = m.columns[c].c[k];
    return r;
}
template<class T> T determinant(const matrix<T, 2, 2> &m)
{ return m[0][0] * m[1][1] - m[1][0] * m[0][1]; }
template<class T> T determinant(const matrix<T, 3, 3> &m)
{
    return m[0][0] * (m[1][1] * m[2][2] - m[2][1] * m[1][2]) - m[1][0] * (m[0][1] * m[2][2] - m[2][1] * m[0][2]) +
           m[2][0] * (m[0][1] * m[1][2] - m[1][1] * m[0][2]);
}
template<class T> T determinant(const matrix<T, 4, 4> &m)
{
    T s0 = m[0][0] * m[1][1] - m[1][0] * m[0][1], s1 = m[0][0] * m[1][2] - m[1][0] * m[0][2];
    T s2 = m[0][0] * m[1][3] - m[1][0] * m[0][3], s3 = m[0][1] * m[1][2] - m[1][1] * m[0][2];
    T s4 = m[0][1] * m[1][3] - m[1][1] * m[0][3], s5 = m[0][2] * m[1][3] - m[1][2] * m[0][3];
    T c5 = m[2][2] * m[3][3] - m[3][2] * m[2][3], c4 = m[2][1] * m[3][3] - m[3][1] * m[2][3];
    T c3 = m[2][1] * m[3][2] - m[3][1] * m[2][2], c2 = m[2][0] * m[3][3] - m[3][0] * m[2][3];
    T c1 = m[2][0] * m[3][2] - m[3][0] * m[2][2], c0 = m[2][0] * m[3][1] - m[3][0] * m[2][1];
    return s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0;
}
} // namespace metal

/* The type names, as MSL spells them. */
#define __FERRY_VNAMES(t, n) \
    typedef metal::vec<t, 2> n##2; typedef metal::vec<t, 3> n##3; typedef metal::vec<t, 4> n##4; \
    typedef metal::packed_vec<t, 2> packed_##n##2; typedef metal::packed_vec<t, 3> packed_##n##3; \
    typedef metal::packed_vec<t, 4> packed_##n##4;
__FERRY_VNAMES(float, float) __FERRY_VNAMES(half, half) __FERRY_VNAMES(int, int) __FERRY_VNAMES(uint, uint)
__FERRY_VNAMES(short, short) __FERRY_VNAMES(ushort, ushort) __FERRY_VNAMES(char, char) __FERRY_VNAMES(uchar, uchar)
__FERRY_VNAMES(bool, bool) __FERRY_VNAMES(long, long) __FERRY_VNAMES(ulong, ulong)
#undef __FERRY_VNAMES
#define __FERRY_MNAMES(t) \
    typedef metal::matrix<t, 2, 2> t##2x2; typedef metal::matrix<t, 2, 3> t##2x3; typedef metal::matrix<t, 2, 4> t##2x4; \
    typedef metal::matrix<t, 3, 2> t##3x2; typedef metal::matrix<t, 3, 3> t##3x3; typedef metal::matrix<t, 3, 4> t##3x4; \
    typedef metal::matrix<t, 4, 2> t##4x2; typedef metal::matrix<t, 4, 3> t##4x3; typedef metal::matrix<t, 4, 4> t##4x4;
__FERRY_MNAMES(float) __FERRY_MNAMES(half)
#undef __FERRY_MNAMES
namespace metal {
using ::float2; using ::float3; using ::float4; using ::half2; using ::half3; using ::half4;
using ::int2; using ::int3; using ::int4; using ::uint2; using ::uint3; using ::uint4;
using ::bool2; using ::bool3; using ::bool4;
using ::float2x2; using ::float3x3; using ::float4x4;
}

#endif
