/* SPDX-License-Identifier: GPL-3.0-or-later
 * Shader code in the style SPIRV-Cross writes for MoltenVK (Godot's Vulkan
 * renderer): spvUnsafeArray with both device and constant overloads, which
 * are one member here, simd_vote::vote_t, sign on integer vectors, the indirect-argument structs and
 * <simd/simd.h>. */
#include <simd/simd.h>
using namespace metal;
template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    thread T& operator [] (size_t pos) thread { return elements[pos]; }
    constexpr const thread T& operator [] (size_t pos) const thread { return elements[pos]; }
    device T& operator [] (size_t pos) device { return elements[pos]; }
    constexpr const device T& operator [] (size_t pos) const device { return elements[pos]; }
    constexpr const constant T& operator [] (size_t pos) const constant { return elements[pos]; }
    threadgroup T& operator [] (size_t pos) threadgroup { return elements[pos]; }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup { return elements[pos]; }
};
kernel void k(device MTLDispatchThreadgroupsIndirectArguments *ia [[buffer(1)]], device uint4 *o [[buffer(0)]], uint gid [[thread_position_in_grid]]) {
    simd_vote vote = simd_ballot(gid == 0);
    spvUnsafeArray<float3, 2> a = spvUnsafeArray<float3, 2>({ float3(1.0), float3(2.0) });
    ia->threadgroupsPerGrid[0] = 1;
    int3 s = -sign(int3(int(gid) - 1, 0, 5));
    o[gid] = uint4(as_type<uint2>((simd_vote::vote_t)vote), uint(a[1].x), uint(s.z + 1));
}
