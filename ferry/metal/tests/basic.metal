#include <metal_stdlib>
using namespace metal;
struct VIn { float3 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; };
struct VOut { float4 position [[position]]; float2 uv; float3 col [[user(colour)]]; uint id [[flat]]; };
struct Uni { float4x4 mvp; float4 tint; };
constant bool use_tint [[function_constant(0)]];
constant float scale [[function_constant(1)]];
vertex VOut vs_main(VIn in [[stage_in]], constant Uni &u [[buffer(1)]], uint vid [[vertex_id]]) {
  VOut o; o.position = u.mvp * float4(in.pos * scale, 1.0); o.uv = in.uv; o.col = float3(1,0,0); o.id = vid; return o;
}
fragment float4 fs_main(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]], constant Uni &u [[buffer(0)]]) {
  float4 c = tex.sample(s, in.uv) * float4(in.col, 1);
  if (is_function_constant_defined(use_tint) && use_tint) c *= u.tint;
  return c;
}
kernel void add(device float *a [[buffer(0)]], device const float *b [[buffer(1)]], uint gid [[thread_position_in_grid]], uint lid [[thread_index_in_threadgroup]]) {
  threadgroup float tmp[64];
  tmp[lid % 64] = b[gid];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  a[gid] += tmp[lid % 64];
}
