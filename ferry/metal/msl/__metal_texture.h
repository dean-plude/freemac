/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal Shading Language: samplers, textures, derivatives, fragment
 * discard, barriers, SIMD-group and quad functions, atomics and the small
 * helper types (array, numeric_limits), from the public MSL specification.
 * A texture is a handle to Metal.framework's record of it; reads, writes and
 * sampling call into Metal.framework. */
#ifndef __FERRY_METAL_TEXTURE_H
#define __FERRY_METAL_TEXTURE_H
#include "__metal_math.h"
#include "ferry_metal_abi.h"

namespace metal {

/* ---- derivatives: the 2x2 quad a fragment belongs to ---------------------------- */
template<class T> T __quad_all(const T &v, int &lane, T (&all)[4])
{
    __ferry_quad_exchange(&v, (int)sizeof(T), all);
    lane = __ferry_quad_lane();
    return v;
}
template<class T> T dfdx(T v)
{
    T all[4];
    int lane;
    __quad_all(v, lane, all);
    return all[lane | 1] - all[lane & 2];
}
template<class T> T dfdy(T v)
{
    T all[4];
    int lane;
    __quad_all(v, lane, all);
    return all[lane | 2] - all[lane & 1];
}
template<class T> T fwidth(T v) { return abs(dfdx(v)) + abs(dfdy(v)); }
inline void discard_fragment() { __ferry_discard(); }

/* ---- barriers ------------------------------------------------------------------- */
enum class mem_flags { mem_none = 0, mem_device = 1, mem_threadgroup = 2, mem_texture = 4, mem_threadgroup_imageblock = 8,
                       mem_object_data = 16 };
inline mem_flags operator|(mem_flags a, mem_flags b) { return mem_flags(int(a) | int(b)); }
inline void threadgroup_barrier(mem_flags f) { __ferry_barrier(int(f)); }
inline void simdgroup_barrier(mem_flags) {}
inline void atomic_thread_fence(mem_flags, int = 0, int = 0) { __atomic_thread_fence(__ATOMIC_SEQ_CST); }

/* ---- SIMD groups are one thread wide here; quads are a fragment's 2x2 quad ------- */
template<class T> T simd_broadcast(T v, ushort) { return v; }
template<class T> T simd_broadcast_first(T v) { return v; }
template<class T> T simd_shuffle(T v, ushort) { return v; }
template<class T> T simd_shuffle_xor(T v, ushort) { return v; }
template<class T> T simd_shuffle_up(T v, ushort) { return v; }
template<class T> T simd_shuffle_down(T v, ushort) { return v; }
template<class T> T simd_shuffle_rotate_up(T v, ushort) { return v; }
template<class T> T simd_shuffle_rotate_down(T v, ushort) { return v; }
template<class T> T simd_sum(T v) { return v; }
template<class T> T simd_product(T v) { return v; }
template<class T> T simd_min(T v) { return v; }
template<class T> T simd_max(T v) { return v; }
template<class T> T simd_and(T v) { return v; }
template<class T> T simd_or(T v) { return v; }
template<class T> T simd_xor(T v) { return v; }
template<class T> T simd_prefix_inclusive_sum(T v) { return v; }
template<class T> T simd_prefix_exclusive_sum(T v) { return T(0); }
template<class T> T simd_prefix_inclusive_product(T v) { return v; }
template<class T> T simd_prefix_exclusive_product(T) { return T(1); }
struct simd_vote {
    ulong v;
    explicit simd_vote(ulong x = 0) : v(x) {}
    bool all() const { return v != 0; }
    bool any() const { return v != 0; }
    explicit operator ulong() const { return v; }
};
inline simd_vote simd_ballot(bool b) { return simd_vote(b ? 1 : 0); }
inline simd_vote simd_active_threads_mask() { return simd_vote(1); }
inline bool simd_all(bool b) { return b; }
inline bool simd_any(bool b) { return b; }
inline bool simd_is_first() { return true; }
inline bool simd_is_helper_thread() { return false; }
template<class T> T quad_broadcast(T v, ushort lane)
{
    T all[4];
    int me;
    __quad_all(v, me, all);
    return all[lane & 3];
}
template<class T> T quad_shuffle(T v, ushort lane) { return quad_broadcast(v, lane); }
template<class T> T quad_shuffle_xor(T v, ushort m)
{
    T all[4];
    int me;
    __quad_all(v, me, all);
    return all[(me ^ m) & 3];
}
template<class T> T quad_sum(T v)
{
    T all[4];
    int me;
    __quad_all(v, me, all);
    return all[0] + all[1] + all[2] + all[3];
}
template<class T> T quad_min(T v)
{
    T all[4];
    int me;
    __quad_all(v, me, all);
    return min(min(all[0], all[1]), min(all[2], all[3]));
}
template<class T> T quad_max(T v)
{
    T all[4];
    int me;
    __quad_all(v, me, all);
    return max(max(all[0], all[1]), max(all[2], all[3]));
}
inline bool quad_any(bool b) { return quad_max(int(b)) != 0; }
inline bool quad_all(bool b) { return quad_min(int(b)) != 0; }

/* ---- atomics --------------------------------------------------------------------- */
enum memory_order { memory_order_relaxed = __ATOMIC_RELAXED, memory_order_acquire = __ATOMIC_ACQUIRE,
                    memory_order_release = __ATOMIC_RELEASE, memory_order_acq_rel = __ATOMIC_ACQ_REL,
                    memory_order_seq_cst = __ATOMIC_SEQ_CST };
template<class T> struct atomic { T __v; };
template<class T> using _atomic = atomic<T>;
typedef atomic<int> atomic_int;
typedef atomic<uint> atomic_uint;
typedef atomic<bool> atomic_bool;
typedef atomic<float> atomic_float;
typedef atomic<ulong> atomic_ulong;
#define __FERRY_AT(T) volatile atomic<T> *o
template<class T> T atomic_load_explicit(const volatile atomic<T> *o, memory_order m)
{ return __atomic_load_n(&o->__v, __ATOMIC_SEQ_CST); }
template<class T, class U> void atomic_store_explicit(__FERRY_AT(T), U v, memory_order m)
{ __atomic_store_n(&o->__v, T(v), __ATOMIC_SEQ_CST); }
template<class T, class U> T atomic_exchange_explicit(__FERRY_AT(T), U v, memory_order m)
{ return __atomic_exchange_n(&o->__v, T(v), __ATOMIC_SEQ_CST); }
template<class T, class U> bool atomic_compare_exchange_weak_explicit(__FERRY_AT(T), thread T *expected, U desired,
                                                                     memory_order, memory_order)
{
    T e = *expected;
    bool ok = __atomic_compare_exchange_n(&o->__v, &e, T(desired), false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    *expected = e;
    return ok;
}
template<class T, class U> bool atomic_compare_exchange_strong_explicit(__FERRY_AT(T), thread T *expected,
                                                                       U desired, memory_order a, memory_order b)
{ return atomic_compare_exchange_weak_explicit(o, expected, desired, a, b); }
#define __FERRY_ATOP(name, builtin) \
    template<class T, class U> T atomic_fetch_##name##_explicit(__FERRY_AT(T), U v, memory_order) \
    { return builtin(&o->__v, T(v), __ATOMIC_SEQ_CST); }
__FERRY_ATOP(add, __atomic_fetch_add) __FERRY_ATOP(sub, __atomic_fetch_sub) __FERRY_ATOP(and, __atomic_fetch_and)
__FERRY_ATOP(or, __atomic_fetch_or) __FERRY_ATOP(xor, __atomic_fetch_xor)
__FERRY_ATOP(min, __atomic_fetch_min) __FERRY_ATOP(max, __atomic_fetch_max)
#undef __FERRY_ATOP
/* Floating-point add, by compare and swap. */
template<class U> float atomic_fetch_add_explicit(volatile atomic<float> *o, U v, memory_order)
{
    volatile uint *p = (volatile uint *)&o->__v;
    uint old = __atomic_load_n(p, __ATOMIC_SEQ_CST);
    while (!__atomic_compare_exchange_n(p, &old, as_type<uint>(as_type<float>(old) + float(v)), true,
                                        __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
    }
    return as_type<float>(old);
}
template<class U> float atomic_fetch_sub_explicit(volatile atomic<float> *o, U v, memory_order m)
{ return atomic_fetch_add_explicit(o, -float(v), m); }
template<class U> float atomic_exchange_explicit(volatile atomic<float> *o, U v, memory_order)
{ return as_type<float>(__atomic_exchange_n((volatile uint *)&o->__v, as_type<uint>(float(v)), __ATOMIC_SEQ_CST)); }
inline float atomic_load_explicit(const volatile atomic<float> *o, memory_order)
{ return as_type<float>(__atomic_load_n((const volatile uint *)&o->__v, __ATOMIC_SEQ_CST)); }
template<class U> void atomic_store_explicit(volatile atomic<float> *o, U v, memory_order)
{ __atomic_store_n((volatile uint *)&o->__v, as_type<uint>(float(v)), __ATOMIC_SEQ_CST); }
#undef __FERRY_AT

/* ---- samplers -------------------------------------------------------------------- */
enum class coord { normalized = 1, pixel = 0 };
enum class address { clamp_to_edge = FERRY_ADDR_CLAMP_TO_EDGE, mirrored_clamp_to_edge = FERRY_ADDR_MIRROR_CLAMP_TO_EDGE,
                     repeat = FERRY_ADDR_REPEAT, mirrored_repeat = FERRY_ADDR_MIRRORED_REPEAT,
                     clamp_to_zero = FERRY_ADDR_CLAMP_TO_ZERO, clamp_to_border = FERRY_ADDR_CLAMP_TO_BORDER };
enum class filter { nearest = 0, linear = 1, bicubic = 1 };
enum class mip_filter { none = 0, nearest = 1, linear = 2 };
enum class compare_func { none = FERRY_CMP_NONE, never = FERRY_CMP_NEVER, less = FERRY_CMP_LESS,
                          less_equal = FERRY_CMP_LESS_EQUAL, greater = FERRY_CMP_GREATER,
                          greater_equal = FERRY_CMP_GREATER_EQUAL, equal = FERRY_CMP_EQUAL,
                          not_equal = FERRY_CMP_NOT_EQUAL, always = FERRY_CMP_ALWAYS };
enum class border_color { transparent_black = 0, opaque_black = 1, opaque_white = 2 };
struct s_address { address a; constexpr s_address(address x) : a(x) {} };
struct t_address { address a; constexpr t_address(address x) : a(x) {} };
struct r_address { address a; constexpr r_address(address x) : a(x) {} };
struct mag_filter { filter f; constexpr mag_filter(filter x) : f(x) {} };
struct min_filter { filter f; constexpr min_filter(filter x) : f(x) {} };
struct max_anisotropy { int n; constexpr max_anisotropy(int x) : n(x) {} };
struct lod_clamp { float lo, hi; constexpr lod_clamp(float a, float b) : lo(a), hi(b) {} };

struct sampler {
    ferry_sampler d;
    constexpr sampler() : d{1, 0, 0, 0, 0, 0, 0, FERRY_CMP_NONE, 0, 1, {0, 0}, 0.0f, 1000.0f} {}
    template<class... A> constexpr sampler(A... a) : sampler() { (__set(a), ...); }
    constexpr void __set(coord c) { d.normalized = (unsigned char)c; }
    constexpr void __set(address a) { d.s_address = d.t_address = d.r_address = (unsigned char)a; }
    constexpr void __set(s_address a) { d.s_address = (unsigned char)a.a; }
    constexpr void __set(t_address a) { d.t_address = (unsigned char)a.a; }
    constexpr void __set(r_address a) { d.r_address = (unsigned char)a.a; }
    constexpr void __set(filter f) { d.mag_filter = d.min_filter = (unsigned char)f; }
    constexpr void __set(mag_filter f) { d.mag_filter = (unsigned char)f.f; }
    constexpr void __set(min_filter f) { d.min_filter = (unsigned char)f.f; }
    constexpr void __set(mip_filter f) { d.mip_filter = (unsigned char)f; }
    constexpr void __set(compare_func f) { d.compare = (unsigned char)f; }
    constexpr void __set(border_color b) { d.border = (unsigned char)b; }
    constexpr void __set(max_anisotropy a) { d.max_anisotropy = (unsigned char)a.n; }
    constexpr void __set(lod_clamp l) { d.lod_min = l.lo; d.lod_max = l.hi; }
};

/* ---- textures -------------------------------------------------------------------- */
enum class access { sample = 0, read = 1, write = 2, read_write = 3 };
struct level { float lod; level(float l) : lod(l) {} };
struct bias { float value; bias(float b) : value(b) {} };
struct min_lod_clamp { float lod; min_lod_clamp(float l) : lod(l) {} };
struct gradient2d { float2 dx, dy; gradient2d(float2 a, float2 b) : dx(a), dy(b) {} };
struct gradient3d { float3 dx, dy; gradient3d(float3 a, float3 b) : dx(a), dy(b) {} };
struct gradientcube { float3 dx, dy; gradientcube(float3 a, float3 b) : dx(a), dy(b) {} };
enum class component { x = 0, y = 1, z = 2, w = 3 };

/* The trailing arguments of sample(), sample_compare() and gather(), sorted
 * by type: an integer is the array layer, a float the comparison value, an
 * int vector the texel offset, and level/bias/gradient choose the lod. */
struct __sargs {
    int layer = 0, mode = 0, comp = 0;
    float lod = 0, ref = 0;
    float g[6] = {0, 0, 0, 0, 0, 0};
    int off[3] = {0, 0, 0};
    void put(level l) { mode = 1; lod = l.lod; }
    void put(bias b) { mode = 2; lod = b.value; }
    void put(min_lod_clamp) {}
    void put(gradient2d d) { mode = 3; g[0] = d.dx.x; g[1] = d.dx.y; g[3] = d.dy.x; g[4] = d.dy.y; }
    void put(gradient3d d)
    {
        mode = 3;
        g[0] = d.dx.x; g[1] = d.dx.y; g[2] = d.dx.z;
        g[3] = d.dy.x; g[4] = d.dy.y; g[5] = d.dy.z;
    }
    void put(gradientcube d) { put(gradient3d(d.dx, d.dy)); }
    void put(component c) { comp = int(c); }
    void put(float r) { ref = r; }
    void put(half r) { ref = float(r); }
    void put(int l) { layer = l; }
    void put(uint l) { layer = int(l); }
    void put(short l) { layer = l; }
    void put(ushort l) { layer = l; }
    template<int N> void put(const vec<int, N> &o) { for (int i = 0; i < N && i < 3; i++) off[i] = o.c[i]; }
};

template<class T> struct __texel_kind { static constexpr int is_int = 0; };
template<> struct __texel_kind<int> { static constexpr int is_int = 1; };
template<> struct __texel_kind<uint> { static constexpr int is_int = 2; };
template<> struct __texel_kind<short> { static constexpr int is_int = 1; };
template<> struct __texel_kind<ushort> { static constexpr int is_int = 2; };

/* What every texture shape shares: the handle and the calls into
 * Metal.framework. C is how many coordinates sample() takes. */
template<class T, int C> struct __texbase {
    const struct __ferry_tex *__t;
    typedef vec<T, 4> texel;
    typedef vec<float, C> fcoord;
    static texel __out(const float *f)
    {
        texel r;
        if constexpr (__texel_kind<T>::is_int) {
            for (int i = 0; i < 4; i++) r.c[i] = T(__builtin_bit_cast(int, f[i]));
        } else {
            for (int i = 0; i < 4; i++) r.c[i] = T(f[i]);
        }
        return r;
    }
    texel __read(int x, int y, int z, int lod, int smp) const
    {
        if constexpr (__texel_kind<T>::is_int) {
            uint o[4];
            __ferry_tex_read_i(__t, x, y, z, lod, smp, o);
            texel r;
            for (int i = 0; i < 4; i++) r.c[i] = T(o[i]);
            return r;
        } else {
            float o[4];
            __ferry_tex_read_f(__t, x, y, z, lod, smp, o);
            return __out(o);
        }
    }
    void __write(const texel &v, int x, int y, int z, int lod) const
    {
        if constexpr (__texel_kind<T>::is_int) {
            uint i4[4] = {uint(v.c[0]), uint(v.c[1]), uint(v.c[2]), uint(v.c[3])};
            __ferry_tex_write_i(__t, x, y, z, lod, i4);
        } else {
            float f4[4] = {float(v.c[0]), float(v.c[1]), float(v.c[2]), float(v.c[3])};
            __ferry_tex_write_f(__t, x, y, z, lod, f4);
        }
    }
    /* Implicit lod (and bias) take the quad's derivatives of the coordinates. */
    void __grads(const fcoord &c, __sargs &a) const
    {
        if (a.mode == 0 || a.mode == 2) {
            fcoord dx = dfdx(c), dy = dfdy(c);
            for (int i = 0; i < C; i++) {
                a.g[i] = dx.c[i];
                a.g[3 + i] = dy.c[i];
            }
        }
    }
    template<class... O> texel sample(sampler s, fcoord c, O... o) const
    {
        __sargs a;
        (a.put(o), ...);
        __grads(c, a);
        float cc[3] = {0, 0, 0}, out[4];
        for (int i = 0; i < C; i++) cc[i] = c.c[i];
        __ferry_tex_sample(__t, &s.d, cc, C, a.layer, a.mode, a.lod, a.g, a.off, __texel_kind<T>::is_int, out);
        return __out(out);
    }
    template<class... O> texel gather(sampler s, fcoord c, O... o) const
    {
        __sargs a;
        (a.put(o), ...);
        float cc[3] = {0, 0, 0}, out[4];
        for (int i = 0; i < C; i++) cc[i] = c.c[i];
        __ferry_tex_gather(__t, &s.d, cc, C, a.layer, a.off, a.comp, __texel_kind<T>::is_int, out);
        return __out(out);
    }
    uint get_width(uint lod = 0) const { return __ferry_tex_size(__t, 0, int(lod)); }
    uint get_height(uint lod = 0) const { return __ferry_tex_size(__t, 1, int(lod)); }
    uint get_depth(uint lod = 0) const { return __ferry_tex_size(__t, 2, int(lod)); }
    uint get_array_size() const { return __ferry_tex_size(__t, 3, 0); }
    uint get_num_mip_levels() const { return __ferry_tex_size(__t, 4, 0); }
    uint get_num_samples() const { return __ferry_tex_size(__t, 5, 0); }
    void fence() const {}
    bool is_null() const { return __t == 0; }
};

/* Integer coordinates in any of the widths MSL allows. */
template<class V> struct __icoord { static constexpr bool value = false; };
template<int N> struct __icoord<vec<uint, N>> { static constexpr bool value = true; };
template<int N> struct __icoord<vec<int, N>> { static constexpr bool value = true; };
template<int N> struct __icoord<vec<ushort, N>> { static constexpr bool value = true; };
template<int N> struct __icoord<vec<short, N>> { static constexpr bool value = true; };
#define __FERRY_IC(K) template<class P, enable_if_t<__icoord<__ferry::plain<P>>::value && __ncomp<__ferry::plain<P>>::n == K, int> = 0>
#define __FERRY_IS template<class P, enable_if_t<__is_int<P>::value, int> = 0>

template<class T, access A = access::sample> struct texture1d : __texbase<T, 1> {
    typedef vec<T, 4> texel;
    texel sample(sampler s, float c) const { return __texbase<T, 1>::sample(s, vec<float, 1>(c), level(0)); }
    __FERRY_IS texel read(P p, uint lod = 0) const { return this->__read(int(p), 0, 0, int(lod), 0); }
    __FERRY_IS void write(texel v, P p, uint lod = 0) const { this->__write(v, int(p), 0, 0, int(lod)); }
};
template<class T, access A = access::sample> struct texture1d_array : __texbase<T, 1> {
    typedef vec<T, 4> texel;
    texel sample(sampler s, float c, uint layer) const
    { return __texbase<T, 1>::sample(s, vec<float, 1>(c), layer, level(0)); }
    __FERRY_IS texel read(P p, uint layer, uint lod = 0) const { return this->__read(int(p), int(layer), 0, int(lod), 0); }
    __FERRY_IS void write(texel v, P p, uint layer, uint lod = 0) const { this->__write(v, int(p), int(layer), 0, int(lod)); }
};
template<class T, access A = access::sample> struct texture2d : __texbase<T, 2> {
    typedef vec<T, 4> texel;
    __FERRY_IC(2) texel read(P p, uint lod = 0) const { return this->__read(int(p.x), int(p.y), 0, int(lod), 0); }
    __FERRY_IC(2) void write(texel v, P p, uint lod = 0) const { this->__write(v, int(p.x), int(p.y), 0, int(lod)); }
};
template<class T, access A = access::sample> struct texture2d_array : __texbase<T, 2> {
    typedef vec<T, 4> texel;
    __FERRY_IC(2) texel read(P p, uint layer, uint lod = 0) const
    { return this->__read(int(p.x), int(p.y), int(layer), int(lod), 0); }
    __FERRY_IC(2) void write(texel v, P p, uint layer, uint lod = 0) const
    { this->__write(v, int(p.x), int(p.y), int(layer), int(lod)); }
};
template<class T, access A = access::sample> struct texture3d : __texbase<T, 3> {
    typedef vec<T, 4> texel;
    __FERRY_IC(3) texel read(P p, uint lod = 0) const { return this->__read(int(p.x), int(p.y), int(p.z), int(lod), 0); }
    __FERRY_IC(3) void write(texel v, P p, uint lod = 0) const { this->__write(v, int(p.x), int(p.y), int(p.z), int(lod)); }
};
template<class T, access A = access::sample> struct texturecube : __texbase<T, 3> {
    typedef vec<T, 4> texel;
    __FERRY_IC(2) texel read(P p, uint face, uint lod = 0) const
    { return this->__read(int(p.x), int(p.y), int(face), int(lod), 0); }
    __FERRY_IC(2) void write(texel v, P p, uint face, uint lod = 0) const
    { this->__write(v, int(p.x), int(p.y), int(face), int(lod)); }
};
template<class T, access A = access::sample> struct texturecube_array : __texbase<T, 3> {
    typedef vec<T, 4> texel;
    __FERRY_IC(2) texel read(P p, uint face, uint layer, uint lod = 0) const
    { return this->__read(int(p.x), int(p.y), int(layer * 6 + face), int(lod), 0); }
    __FERRY_IC(2) void write(texel v, P p, uint face, uint layer, uint lod = 0) const
    { this->__write(v, int(p.x), int(p.y), int(layer * 6 + face), int(lod)); }
};
template<class T, access A = access::read> struct texture2d_ms : __texbase<T, 2> {
    typedef vec<T, 4> texel;
    __FERRY_IC(2) texel read(P p, uint smp) const { return this->__read(int(p.x), int(p.y), 0, 0, int(smp)); }
};
template<class T, access A = access::read> struct texture2d_ms_array : __texbase<T, 2> {
    typedef vec<T, 4> texel;
    __FERRY_IC(2) texel read(P p, uint layer, uint smp) const { return this->__read(int(p.x), int(p.y), int(layer), 0, int(smp)); }
};
template<class T, access A = access::read> struct texture_buffer : __texbase<T, 1> {
    typedef vec<T, 4> texel;
    __FERRY_IS texel read(P p) const { return this->__read(int(p), 0, 0, 0, 0); }
    __FERRY_IS void write(texel v, P p) const { this->__write(v, int(p), 0, 0, 0); }
};

/* Depth textures: one float per texel; sample_compare does the comparison. */
template<class T, int C> struct __depthbase : __texbase<T, C> {
    typedef vec<float, C> fcoord;
    template<class... O> T sample(sampler s, fcoord c, O... o) const { return __texbase<T, C>::sample(s, c, o...).x; }
    template<class... O> T sample_compare(sampler s, fcoord c, O... o) const
    {
        __sargs a;
        (a.put(o), ...);
        float cc[3] = {0, 0, 0};
        for (int i = 0; i < C; i++) cc[i] = c.c[i];
        return T(__ferry_tex_sample_compare(this->__t, &s.d, cc, C, a.layer, a.ref, a.mode, a.lod, a.off));
    }
    template<class... O> vec<T, 4> gather_compare(sampler s, fcoord c, O... o) const
    { return vec<T, 4>(sample_compare(s, c, o...)); }
    T __d(int x, int y, int z, int lod, int smp) const { return this->__read(x, y, z, lod, smp).x; }
};
template<class T, access A = access::sample> struct depth2d : __depthbase<T, 2> {
    __FERRY_IC(2) T read(P p, uint lod = 0) const { return this->__d(int(p.x), int(p.y), 0, int(lod), 0); }
};
template<class T, access A = access::sample> struct depth2d_array : __depthbase<T, 2> {
    __FERRY_IC(2) T read(P p, uint layer, uint lod = 0) const { return this->__d(int(p.x), int(p.y), int(layer), int(lod), 0); }
};
template<class T, access A = access::sample> struct depthcube : __depthbase<T, 3> {
    __FERRY_IC(2) T read(P p, uint face, uint lod = 0) const { return this->__d(int(p.x), int(p.y), int(face), int(lod), 0); }
};
template<class T, access A = access::sample> struct depthcube_array : __depthbase<T, 3> {
    __FERRY_IC(2) T read(P p, uint face, uint layer, uint lod = 0) const
    { return this->__d(int(p.x), int(p.y), int(layer * 6 + face), int(lod), 0); }
};
template<class T, access A = access::read> struct depth2d_ms : __depthbase<T, 2> {
    __FERRY_IC(2) T read(P p, uint smp) const { return this->__d(int(p.x), int(p.y), 0, 0, int(smp)); }
};
template<class T, access A = access::read> struct depth2d_ms_array : __depthbase<T, 2> {
    __FERRY_IC(2) T read(P p, uint layer, uint smp) const { return this->__d(int(p.x), int(p.y), int(layer), 0, int(smp)); }
};
#undef __FERRY_IC
#undef __FERRY_IS

/* ---- small helper types -------------------------------------------------------- */
template<class T, unsigned long N> struct array {
    T __a[N ? N : 1];
    T &operator[](unsigned long i) { return __a[i]; }
    const T &operator[](unsigned long i) const { return __a[i]; }
    constexpr unsigned long size() const { return N; }
};
template<class T> struct numeric_limits;
template<> struct numeric_limits<float> {
    static constexpr float max() { return FLT_MAX; }
    static constexpr float min() { return FLT_MIN; }
    static constexpr float lowest() { return -FLT_MAX; }
    static constexpr float infinity() { return __builtin_inff(); }
    static constexpr float quiet_NaN() { return __builtin_nanf(""); }
    static constexpr float epsilon() { return FLT_EPSILON; }
};
template<> struct numeric_limits<half> {
    static constexpr half max() { return HALF_MAX; }
    static constexpr half lowest() { return -HALF_MAX; }
    static constexpr half infinity() { return (half)__builtin_inff(); }
};
template<> struct numeric_limits<int> {
    static constexpr int max() { return INT_MAX; }
    static constexpr int min() { return INT_MIN; }
    static constexpr int lowest() { return INT_MIN; }
};
template<> struct numeric_limits<uint> {
    static constexpr uint max() { return UINT_MAX; }
    static constexpr uint min() { return 0; }
    static constexpr uint lowest() { return 0; }
};
using __ferry::enable_if;
using __ferry::is_same;
template<class T> using remove_cv_t = typename __ferry::remove_cv<T>::type;
template<class T> using remove_reference_t = typename __ferry::remove_reference<T>::type;
template<class T> struct is_floating_point { static constexpr bool value = __ferry::is_floating<T>::value; };
template<class T> struct is_scalar { static constexpr bool value = __ferry::is_scalar<T>::value; };
template<class T> struct is_vector { static constexpr bool value = false; };
template<class T, int N> struct is_vector<vec<T, N>> { static constexpr bool value = true; };
template<class T> struct vec_elements { static constexpr int value = 1; };
template<class T, int N> struct vec_elements<vec<T, N>> { static constexpr int value = N; };
} // namespace metal

#endif

/* What the wrappers ferry-mslc writes use (after the guard, so it sees all of the above). */
#include "__metal_entry.h"
