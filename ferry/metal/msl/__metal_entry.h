/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal Shading Language: what the wrappers ferry-mslc writes for
 * each vertex, fragment and kernel function use to hand the function its
 * arguments (buffers, textures, samplers, built-in values, the stage_in
 * struct) and to pass its results to Metal.framework as plain floats.
 * Included at the end of a compiled shader library, after the shader's own
 * code. */
#ifndef __FERRY_METAL_ENTRY_H
#define __FERRY_METAL_ENTRY_H
#include "__metal_texture.h"

namespace __ferry_entry {
using namespace metal;
template<class T> using P = __ferry::plain<T>;

/* ---- the components of any value that can pass between stages ----------------- */
template<class T> struct comps {
    typedef T elem;
    static constexpr int n = 1;
    static elem get(const T &v, int) { return v; }
    static void set(T &v, int, elem x) { v = x; }
};
template<class T, int N> struct comps<vec<T, N>> {
    typedef T elem;
    static constexpr int n = N;
    static elem get(const vec<T, N> &v, int i) { return v.c[i]; }
    static void set(vec<T, N> &v, int i, elem x) { v.c[i] = x; }
};
template<class T, int N> struct comps<packed_vec<T, N>> {
    typedef T elem;
    static constexpr int n = N;
    static elem get(const packed_vec<T, N> &v, int i) { return v.c[i]; }
    static void set(packed_vec<T, N> &v, int i, elem x) { v.c[i] = x; }
};
template<class T, int C, int R> struct comps<matrix<T, C, R>> {
    typedef T elem;
    static constexpr int n = C * R;
    static elem get(const matrix<T, C, R> &v, int i) { return v.columns[i / R].c[i % R]; }
    static void set(matrix<T, C, R> &v, int i, elem x) { v.columns[i / R].c[i % R] = x; }
};
template<class T, unsigned long N> struct comps<metal::array<T, N>> {
    typedef typename comps<T>::elem elem;
    static constexpr int n = comps<T>::n * int(N);
    static elem get(const metal::array<T, N> &v, int i) { return comps<T>::get(v[i / comps<T>::n], i % comps<T>::n); }
    static void set(metal::array<T, N> &v, int i, elem x) { comps<T>::set(v[i / comps<T>::n], i % comps<T>::n, x); }
};
template<class T, unsigned long N> struct comps<T[N]> {
    typedef typename comps<T>::elem elem;
    static constexpr int n = comps<T>::n * int(N);
    static elem get(const T (&v)[N], int i) { return comps<T>::get(v[i / comps<T>::n], i % comps<T>::n); }
    static void set(T (&v)[N], int i, elem x) { comps<T>::set(v[i / comps<T>::n], i % comps<T>::n, x); }
};
template<class T> constexpr int ncomp() { return comps<P<T>>::n; }
template<class E> constexpr int kind_of_elem()
{
    if constexpr (__ferry::is_same<E, float>::value) return FERRY_K_FLOAT;
    else if constexpr (__ferry::is_same<E, half>::value) return FERRY_K_HALF;
    else if constexpr (E(-1) < E(0)) return FERRY_K_INT;
    else return FERRY_K_UINT;
}
template<class T> constexpr int kind() { return kind_of_elem<typename comps<P<T>>::elem>(); }

/* A value as floats (integers keep their bits), and back. */
template<class T> void put(float *o, const T &v)
{
    typedef comps<P<T>> C;
    for (int i = 0; i < C::n; i++) {
        typename C::elem e = C::get(v, i);
        if constexpr (kind<T>() >= FERRY_K_INT)
            o[i] = __builtin_bit_cast(float, (int)e);
        else
            o[i] = float(e);
    }
}
template<class T> void get(T &v, const float *s)
{
    typedef comps<P<T>> C;
    for (int i = 0; i < C::n; i++) {
        if constexpr (kind<T>() >= FERRY_K_INT)
            C::set(v, i, typename C::elem(__builtin_bit_cast(int, s[i])));
        else
            C::set(v, i, typename C::elem(s[i]));
    }
}
/* A vertex attribute: Metal.framework converts it to four floats or ints. */
template<class T> void fetch(T &v, const ferry_call *c, int attr)
{
    typedef comps<P<T>> C;
    constexpr int want_int = kind<T>() >= FERRY_K_INT;
    union { float f[4]; int i[4]; } t;
    ferry_fetch_attr(c->fetch_ctx, attr, c->vertex_id, c->instance_id, want_int, &t);
    for (int i = 0; i < C::n && i < 4; i++)
        C::set(v, i, want_int ? typename C::elem(t.i[i]) : typename C::elem(t.f[i]));
}

/* ---- arguments ----------------------------------------------------------------- */
template<class T> struct buffer { static T get(void *p) { return (T)p; } };
template<class T> struct buffer<T &> { static T &get(void *p) { return *(T *)p; } };
template<class T> struct texture {
    static T get(const ferry_call *c, int i)
    {
        T t;
        t.__t = (const struct __ferry_tex *)c->textures[i];
        return t;
    }
};
template<class T, unsigned long N> struct texture<metal::array<T, N>> {
    static metal::array<T, N> get(const ferry_call *c, int i)
    {
        metal::array<T, N> a;
        for (unsigned long k = 0; k < N; k++) a[k] = texture<T>::get(c, i + int(k));
        return a;
    }
};
inline sampler sampler_at(const ferry_call *c, int i)
{
    sampler s;
    if (c->samplers[i]) s.d = *c->samplers[i];
    return s;
}
template<class T> struct samplers {
    static T get(const ferry_call *c, int i) { return sampler_at(c, i); }
};
template<unsigned long N> struct samplers<metal::array<sampler, N>> {
    static metal::array<sampler, N> get(const ferry_call *c, int i)
    {
        metal::array<sampler, N> a;
        for (unsigned long k = 0; k < N; k++) a[k] = sampler_at(c, i + int(k));
        return a;
    }
};
/* A built-in value from up to three unsigned integers (grid positions). */
template<class T> T builtin(const unsigned int *v)
{
    typedef comps<P<T>> C;
    P<T> r;
    for (int i = 0; i < C::n; i++) C::set(r, i, typename C::elem(v[i]));
    return r;
}
template<class T> T builtin1(unsigned int v) { return T(v); }
inline float4 frag_position(const ferry_call *c)
{ return float4(c->position[0], c->position[1], c->position[2], c->position[3]); }
} // namespace __ferry_entry

#endif
