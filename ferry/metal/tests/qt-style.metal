/* SPDX-License-Identifier: GPL-3.0-or-later
 * Shader code as Qt's Metal backend and Shotcut's own shaders write it
 * (freemac 1.NEXT): the <simd/vector_types.h> names (vector_float4,
 * simd_float4, matrix_float4x4), a matrix built from braced columns, and a
 * sampler whose address modes and filters are set one by one
 * (s_address::clamp_to_edge, mag_filter::linear). */
#include <metal_stdlib>
using namespace metal;

struct Uniforms { matrix_float4x4 mvp; vector_float4 tint; simd_float2 size; };
struct VOut { float4 pos [[position]]; float2 uv; };

static_assert(sizeof(vector_float4) == 16 && sizeof(simd_float3x3) == sizeof(float3x3), "simd names are Metal's types");

constexpr sampler linear_clamp(coord::normalized, s_address::clamp_to_edge, t_address::repeat,
                               mag_filter::linear, min_filter::nearest);
static_assert(linear_clamp.d.s_address == (unsigned char)address::clamp_to_edge
              && linear_clamp.d.t_address == (unsigned char)address::repeat
              && linear_clamp.d.mag_filter == (unsigned char)filter::linear
              && linear_clamp.d.min_filter == (unsigned char)filter::nearest, "one coordinate, one direction");

vertex VOut vs_main(uint vid [[vertex_id]], constant Uniforms &u [[buffer(0)]], const device simd_packed_float2 *pts [[buffer(1)]])
{
    VOut o;
    o.pos = u.mvp * float4(float2(pts[vid]), 0.0, 1.0);
    o.uv = float2(pts[vid]) / u.size;
    return o;
}

fragment float4 fs_main(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant Uniforms &u [[buffer(0)]])
{
    /* BT.709 to RGB, its columns written as braced lists */
    const float3x3 yuv = float3x3({1.0, 1.0, 1.0}, {0.0, -0.1873, 1.8556}, {1.5748, -0.4681, 0.0});
    float3 c = yuv * (tex.sample(linear_clamp, in.uv).xyz - float3(0.0, 0.5, 0.5));
    return float4(c, 1.0) * u.tint;
}

kernel void k(device float *o [[buffer(0)]], uint gid [[thread_position_in_grid]])
{
    float2x2 m = float2x2({1.0, 2.0}, {3.0, 4.0});
    float4x4 id = matrix_float4x4({1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1});
    o[gid] = m[1][0] + id[3][3];
}
