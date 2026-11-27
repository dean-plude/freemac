/* SPDX-License-Identifier: GPL-3.0-or-later
 * Shader code in the style Blender generates: no #include <metal_stdlib>,
 * "typedef struct { ... } Name;" results, ?: mixing locals with results,
 * a member array passed to an array parameter, packed vectors in arithmetic,
 * std-style type traits and a buffer index from a function constant. */
using namespace metal;
constant int base_index [[function_constant(0)]];

struct Uniforms { packed_float3 tint; float scale; };

template<class U, int S> using vec_or_scalar = typename metal::conditional<S == 1, U, vec<U, S>>::type;
template<class T, metal::enable_if_t<metal::is_integral_v<T>> * = nullptr> T twice(T v) { return v * 2; }

float4 sum3(float4 o[3]) { return o[0] + o[1] + o[2]; }

class Impl {
public:
    float4 offs[3];
    typedef struct {
        float4 pos [[position]];
        float2 uv;
    } VertexOut;
    float4 total() { return sum3(offs); }
};

vertex Impl::VertexOut vs_main(uint vid [[vertex_id]],
                               constant Uniforms *u [[buffer(base_index + 1)]]) {
    Impl::VertexOut o;
    float2 p = float2(float(vid & 1u), float(vid >> 1));
    o.pos = float4(p * u->scale, 0.0f, 1.0f);
    o.uv = p;
    return o;
}

fragment float4 fs_main(Impl::VertexOut in [[stage_in]], constant Uniforms *u [[buffer(base_index)]]) {
    Impl impl;
    for (int i = 0; i < 3; i++) impl.offs[i] = float4(in.uv, 0.0f, 1.0f);
    float3 n = float3(in.uv, 1.0f);
    float3 c = in.uv.x > 0.5f ? n : -n;
    c = in.uv.y > 0.5f ? normalize(c) : float3(0.0f, 0.0f, 1.0f);
    c = in.uv.x > 0.25f ? u->tint : c;
    c *= u->tint;
    c = c + u->tint * 0.5f;
    vec_or_scalar<float, 1> s = 1.0f;
    vec_or_scalar<float, 3> v = c;
    return float4(v * s, float(twice(1))) + impl.total();
}
