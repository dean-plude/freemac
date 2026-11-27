/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry Metal)
 * <simd/simd.h> in a shader: the same vector and matrix types as the
 * metal namespace's, under the simd namespace too, as SPIRV-Cross's and
 * MoltenVK's shaders include it (freemac Godot work). */
#ifndef __FERRY_MSL_SIMD_H
#define __FERRY_MSL_SIMD_H
#include <metal_stdlib>
namespace simd {
using namespace metal;
}
#endif
