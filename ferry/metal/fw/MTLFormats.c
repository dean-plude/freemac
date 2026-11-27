/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: pixel formats (from the MTLPixelFormat
 * reference), texel conversions, texture layout and what a compiled shader
 * calls to read, write and sample textures. Filtering follows the Metal
 * Shading Language specification's description of samplers. */
#include "MTLInternal.h"
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>

int mtl_verbose = -1;
void mtl_log(const char *fmt, ...)
{
    if (mtl_verbose < 0) {
        const char *v = getenv("FERRY_METAL_VERBOSE");
        mtl_verbose = v && *v && *v != '0';
    }
    va_list ap;
    va_start(ap, fmt);
    fputs("Metal: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

/* ---- the formats ------------------------------------------------------------------- */
#define F(v, b, k, n, bgr, srgb, isint, dep, st, nm) {v, b, k, n, bgr, srgb, isint, dep, st, nm}
static const struct mtl_fmt formats[] = {
    F(1, 1, FK_UN8, 1, 0, 0, 0, 0, 0, "A8Unorm"),
    F(10, 1, FK_UN8, 1, 0, 0, 0, 0, 0, "R8Unorm"), F(11, 1, FK_UN8, 1, 0, 1, 0, 0, 0, "R8Unorm_sRGB"),
    F(12, 1, FK_SN8, 1, 0, 0, 0, 0, 0, "R8Snorm"), F(13, 1, FK_UI8, 1, 0, 0, 2, 0, 0, "R8Uint"),
    F(14, 1, FK_SI8, 1, 0, 0, 1, 0, 0, "R8Sint"),
    F(20, 2, FK_UN16, 1, 0, 0, 0, 0, 0, "R16Unorm"), F(22, 2, FK_SN16, 1, 0, 0, 0, 0, 0, "R16Snorm"),
    F(23, 2, FK_UI16, 1, 0, 0, 2, 0, 0, "R16Uint"), F(24, 2, FK_SI16, 1, 0, 0, 1, 0, 0, "R16Sint"),
    F(25, 2, FK_F16, 1, 0, 0, 0, 0, 0, "R16Float"),
    F(30, 2, FK_UN8, 2, 0, 0, 0, 0, 0, "RG8Unorm"), F(31, 2, FK_UN8, 2, 0, 1, 0, 0, 0, "RG8Unorm_sRGB"),
    F(32, 2, FK_SN8, 2, 0, 0, 0, 0, 0, "RG8Snorm"), F(33, 2, FK_UI8, 2, 0, 0, 2, 0, 0, "RG8Uint"),
    F(34, 2, FK_SI8, 2, 0, 0, 1, 0, 0, "RG8Sint"),
    F(40, 2, FK_B5G6R5, 3, 0, 0, 0, 0, 0, "B5G6R5Unorm"), F(41, 2, FK_A1BGR5, 4, 0, 0, 0, 0, 0, "A1BGR5Unorm"),
    F(42, 2, FK_ABGR4, 4, 0, 0, 0, 0, 0, "ABGR4Unorm"), F(43, 2, FK_BGR5A1, 4, 0, 0, 0, 0, 0, "BGR5A1Unorm"),
    F(53, 4, FK_UI32, 1, 0, 0, 2, 0, 0, "R32Uint"), F(54, 4, FK_SI32, 1, 0, 0, 1, 0, 0, "R32Sint"),
    F(55, 4, FK_F32, 1, 0, 0, 0, 0, 0, "R32Float"),
    F(60, 4, FK_UN16, 2, 0, 0, 0, 0, 0, "RG16Unorm"), F(62, 4, FK_SN16, 2, 0, 0, 0, 0, 0, "RG16Snorm"),
    F(63, 4, FK_UI16, 2, 0, 0, 2, 0, 0, "RG16Uint"), F(64, 4, FK_SI16, 2, 0, 0, 1, 0, 0, "RG16Sint"),
    F(65, 4, FK_F16, 2, 0, 0, 0, 0, 0, "RG16Float"),
    F(70, 4, FK_UN8, 4, 0, 0, 0, 0, 0, "RGBA8Unorm"), F(71, 4, FK_UN8, 4, 0, 1, 0, 0, 0, "RGBA8Unorm_sRGB"),
    F(72, 4, FK_SN8, 4, 0, 0, 0, 0, 0, "RGBA8Snorm"), F(73, 4, FK_UI8, 4, 0, 0, 2, 0, 0, "RGBA8Uint"),
    F(74, 4, FK_SI8, 4, 0, 0, 1, 0, 0, "RGBA8Sint"),
    F(80, 4, FK_UN8, 4, 1, 0, 0, 0, 0, "BGRA8Unorm"), F(81, 4, FK_UN8, 4, 1, 1, 0, 0, 0, "BGRA8Unorm_sRGB"),
    F(90, 4, FK_RGB10A2N, 4, 0, 0, 0, 0, 0, "RGB10A2Unorm"), F(91, 4, FK_RGB10A2U, 4, 0, 0, 2, 0, 0, "RGB10A2Uint"),
    F(92, 4, FK_RG11B10F, 3, 0, 0, 0, 0, 0, "RG11B10Float"), F(93, 4, FK_RGB9E5, 3, 0, 0, 0, 0, 0, "RGB9E5Float"),
    F(94, 4, FK_BGR10A2, 4, 0, 0, 0, 0, 0, "BGR10A2Unorm"),
    F(103, 8, FK_UI32, 2, 0, 0, 2, 0, 0, "RG32Uint"), F(104, 8, FK_SI32, 2, 0, 0, 1, 0, 0, "RG32Sint"),
    F(105, 8, FK_F32, 2, 0, 0, 0, 0, 0, "RG32Float"),
    F(110, 8, FK_UN16, 4, 0, 0, 0, 0, 0, "RGBA16Unorm"), F(112, 8, FK_SN16, 4, 0, 0, 0, 0, 0, "RGBA16Snorm"),
    F(113, 8, FK_UI16, 4, 0, 0, 2, 0, 0, "RGBA16Uint"), F(114, 8, FK_SI16, 4, 0, 0, 1, 0, 0, "RGBA16Sint"),
    F(115, 8, FK_F16, 4, 0, 0, 0, 0, 0, "RGBA16Float"),
    F(552, 8, FK_BGRA10XR, 4, 1, 0, 0, 0, 0, "BGRA10_XR"), F(553, 8, FK_BGRA10XR, 4, 1, 1, 0, 0, 0, "BGRA10_XR_sRGB"),
    F(554, 4, FK_BGR10XR, 3, 1, 0, 0, 0, 0, "BGR10_XR"), F(555, 4, FK_BGR10XR, 3, 1, 1, 0, 0, 0, "BGR10_XR_sRGB"),
    F(123, 16, FK_UI32, 4, 0, 0, 2, 0, 0, "RGBA32Uint"), F(124, 16, FK_SI32, 4, 0, 0, 1, 0, 0, "RGBA32Sint"),
    F(125, 16, FK_F32, 4, 0, 0, 0, 0, 0, "RGBA32Float"),
    F(130, 8, FK_BC, 4, 0, 0, 0, 0, 0, "BC1_RGBA"), F(131, 8, FK_BC, 4, 0, 1, 0, 0, 0, "BC1_RGBA_sRGB"),
    F(132, 16, FK_BC, 4, 0, 0, 0, 0, 0, "BC2_RGBA"), F(133, 16, FK_BC, 4, 0, 1, 0, 0, 0, "BC2_RGBA_sRGB"),
    F(134, 16, FK_BC, 4, 0, 0, 0, 0, 0, "BC3_RGBA"), F(135, 16, FK_BC, 4, 0, 1, 0, 0, 0, "BC3_RGBA_sRGB"),
    F(140, 8, FK_BC, 1, 0, 0, 0, 0, 0, "BC4_RUnorm"), F(141, 8, FK_BC, 1, 0, 0, 0, 0, 0, "BC4_RSnorm"),
    F(142, 16, FK_BC, 2, 0, 0, 0, 0, 0, "BC5_RGUnorm"), F(143, 16, FK_BC, 2, 0, 0, 0, 0, 0, "BC5_RGSnorm"),
    F(150, 16, FK_BC, 3, 0, 0, 0, 0, 0, "BC6H_RGBFloat"), F(151, 16, FK_BC, 3, 0, 0, 0, 0, 0, "BC6H_RGBUfloat"),
    F(152, 16, FK_BC, 4, 0, 0, 0, 0, 0, "BC7_RGBAUnorm"), F(153, 16, FK_BC, 4, 0, 1, 0, 0, 0, "BC7_RGBAUnorm_sRGB"),
    F(240, 4, FK_422, 3, 0, 0, 0, 0, 0, "GBGR422"), F(241, 4, FK_422, 3, 0, 0, 0, 0, 0, "BGRG422"),
    F(250, 2, FK_D16, 1, 0, 0, 0, 1, 0, "Depth16Unorm"), F(252, 4, FK_D32F, 1, 0, 0, 0, 1, 0, "Depth32Float"),
    F(253, 1, FK_S8, 1, 0, 0, 2, 0, 1, "Stencil8"), F(255, 4, FK_D24S8, 1, 0, 0, 0, 1, 1, "Depth24Unorm_Stencil8"),
    F(260, 8, FK_D32FS8, 1, 0, 0, 0, 1, 1, "Depth32Float_Stencil8"),
    F(261, 8, FK_X32S8, 1, 0, 0, 2, 0, 1, "X32_Stencil8"), F(262, 4, FK_X24S8, 1, 0, 0, 2, 0, 1, "X24_Stencil8"),
};
#undef F

const struct mtl_fmt *mtl_format(unsigned fmt)
{
    static const struct mtl_fmt *by[600];
    static int ready;
    if (!ready) {
        for (size_t i = 0; i < sizeof formats / sizeof *formats; i++) by[formats[i].fmt] = &formats[i];
        ready = 1;
    }
    return fmt < 600 ? by[fmt] : NULL;
}

/* ---- conversions -------------------------------------------------------------------- */
float mtl_half_to_float(uint16_t h)
{
    uint32_t s = (uint32_t)(h & 0x8000) << 16, e = (h >> 10) & 0x1f, m = h & 0x3ff, u;
    if (e == 0) {
        if (!m) u = s;
        else {
            e = 1;
            while (!(m & 0x400)) { m <<= 1; e--; }
            m &= 0x3ff;
            u = s | ((e + 112) << 23) | (m << 13);
        }
    } else if (e == 31) u = s | 0x7f800000 | (m << 13);
    else u = s | ((e + 112) << 23) | (m << 13);
    float f;
    memcpy(&f, &u, 4);
    return f;
}
uint16_t mtl_float_to_half(float f)
{
    uint32_t u;
    memcpy(&u, &f, 4);
    uint32_t s = (u >> 16) & 0x8000;
    int e = (int)((u >> 23) & 0xff) - 127 + 15;
    uint32_t m = u & 0x7fffff;
    if (((u >> 23) & 0xff) == 0xff) return (uint16_t)(s | 0x7c00 | (m ? 0x200 : 0));
    if (e >= 31) return (uint16_t)(s | 0x7c00);
    if (e <= 0) {
        if (e < -10) return (uint16_t)s;
        m |= 0x800000;
        int sh = 14 - e;
        uint32_t r = m >> sh, rem = m & ((1u << sh) - 1), half = 1u << (sh - 1);
        if (rem > half || (rem == half && (r & 1))) r++;
        return (uint16_t)(s | r);
    }
    uint32_t r = (uint32_t)(e << 10) | (m >> 13), rem = m & 0x1fff;
    if (rem > 0x1000 || (rem == 0x1000 && (r & 1))) r++;
    return (uint16_t)(s | r);
}
static float uf_bits(uint32_t v, int mbits) /* the unsigned small floats of RG11B10 */
{
    uint32_t e = v >> mbits, m = v & ((1u << mbits) - 1);
    if (e == 31) return m ? NAN : INFINITY;
    if (e == 0) return ldexpf((float)m, -14 - mbits);
    return ldexpf(1.0f + (float)m / (float)(1 << mbits), (int)e - 15);
}
static uint32_t uf_make(float f, int mbits)
{
    if (!(f > 0)) return 0;
    if (f >= 65024.0f) return (31u << mbits) - 1;
    int e;
    float m = frexpf(f, &e); /* f = m * 2^e, m in [0.5, 1) */
    int be = e - 1 + 15;
    if (be <= 0) return (uint32_t)lrintf(ldexpf(f, 14 + mbits)) & ((1u << mbits) - 1);
    uint32_t mm = (uint32_t)lrintf((m * 2.0f - 1.0f) * (float)(1 << mbits));
    if (mm >> mbits) { mm = 0; be++; }
    if (be >= 31) return (31u << mbits) - 1;
    return ((uint32_t)be << mbits) | mm;
}
static inline float srgb_to_lin(float c)
{ return c <= 0.04045f ? c / 12.92f : powf((c + 0.055f) / 1.055f, 2.4f); }
static inline float lin_to_srgb(float c)
{
    if (!(c > 0)) return 0;
    if (c >= 1) return 1;
    return c <= 0.0031308f ? c * 12.92f : 1.055f * powf(c, 1.0f / 2.4f) - 0.055f;
}
static inline float clampf(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }
static inline uint32_t unorm(float v, uint32_t max) { return (uint32_t)lrintf(clampf(v != v ? 0 : v, 0, 1) * (float)max); }
static inline int32_t snorm(float v, int32_t max) { return (int32_t)lrintf(clampf(v != v ? 0 : v, -1, 1) * (float)max); }
static inline float fbits(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static inline uint32_t ubits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }

void mtl_texel_load(const struct mtl_fmt *f, const void *p, float out[4])
{
    const unsigned char *b = p;
    float v[4] = {0, 0, 0, 1};
    uint32_t w;
    int n = f->n;
    if (f->is_int) v[3] = fbits(1);
    switch (f->kind) {
    case FK_UN8: for (int i = 0; i < n; i++) v[i] = b[i] * (1.0f / 255); break;
    case FK_SN8: for (int i = 0; i < n; i++) v[i] = fmaxf((signed char)b[i] / 127.0f, -1); break;
    case FK_UI8: for (int i = 0; i < n; i++) v[i] = fbits(b[i]); break;
    case FK_SI8: for (int i = 0; i < n; i++) v[i] = fbits((uint32_t)(int32_t)(signed char)b[i]); break;
    case FK_UN16: for (int i = 0; i < n; i++) v[i] = ((const uint16_t *)p)[i] * (1.0f / 65535); break;
    case FK_SN16: for (int i = 0; i < n; i++) v[i] = fmaxf(((const int16_t *)p)[i] / 32767.0f, -1); break;
    case FK_UI16: for (int i = 0; i < n; i++) v[i] = fbits(((const uint16_t *)p)[i]); break;
    case FK_SI16: for (int i = 0; i < n; i++) v[i] = fbits((uint32_t)(int32_t)((const int16_t *)p)[i]); break;
    case FK_F16: for (int i = 0; i < n; i++) v[i] = mtl_half_to_float(((const uint16_t *)p)[i]); break;
    case FK_UI32: case FK_SI32: case FK_F32: memcpy(v, p, 4 * (size_t)n); break;
    case FK_B5G6R5: w = *(const uint16_t *)p;
        v[2] = (w >> 11) / 31.0f; v[1] = ((w >> 5) & 63) / 63.0f; v[0] = (w & 31) / 31.0f; break;
    case FK_A1BGR5: w = *(const uint16_t *)p;
        v[3] = (float)(w >> 15); v[2] = ((w >> 10) & 31) / 31.0f; v[1] = ((w >> 5) & 31) / 31.0f; v[0] = (w & 31) / 31.0f; break;
    case FK_ABGR4: w = *(const uint16_t *)p;
        v[3] = (w >> 12) / 15.0f; v[2] = ((w >> 8) & 15) / 15.0f; v[1] = ((w >> 4) & 15) / 15.0f; v[0] = (w & 15) / 15.0f; break;
    case FK_BGR5A1: w = *(const uint16_t *)p;
        v[2] = (w >> 11) / 31.0f; v[1] = ((w >> 6) & 31) / 31.0f; v[0] = ((w >> 1) & 31) / 31.0f; v[3] = (float)(w & 1); break;
    case FK_RGB10A2N: case FK_BGR10A2: w = *(const uint32_t *)p;
        v[0] = (w & 1023) / 1023.0f; v[1] = ((w >> 10) & 1023) / 1023.0f; v[2] = ((w >> 20) & 1023) / 1023.0f;
        v[3] = (w >> 30) / 3.0f;
        if (f->kind == FK_BGR10A2) { float t = v[0]; v[0] = v[2]; v[2] = t; }
        break;
    case FK_RGB10A2U: w = *(const uint32_t *)p;
        v[0] = fbits(w & 1023); v[1] = fbits((w >> 10) & 1023); v[2] = fbits((w >> 20) & 1023); v[3] = fbits(w >> 30); break;
    case FK_RG11B10F: w = *(const uint32_t *)p;
        v[0] = uf_bits(w & 0x7ff, 6); v[1] = uf_bits((w >> 11) & 0x7ff, 6); v[2] = uf_bits(w >> 22, 5); break;
    case FK_RGB9E5: {
        w = *(const uint32_t *)p;
        float sc = ldexpf(1.0f, (int)(w >> 27) - 15 - 9);
        v[0] = (w & 511) * sc; v[1] = ((w >> 9) & 511) * sc; v[2] = ((w >> 18) & 511) * sc;
        break;
    }
    case FK_BGR10XR: w = *(const uint32_t *)p;
        v[2] = (((w >> 20) & 1023) - 384.0f) / 510.0f; v[1] = (((w >> 10) & 1023) - 384.0f) / 510.0f;
        v[0] = ((w & 1023) - 384.0f) / 510.0f;
        { float t = v[0]; v[0] = v[2]; v[2] = t; }
        break;
    case FK_BGRA10XR:
        for (int i = 0; i < 4; i++) v[i] = ((((const uint16_t *)p)[i] >> 6) - 384.0f) / 510.0f;
        break;
    case FK_D16: v[0] = *(const uint16_t *)p / 65535.0f; break;
    case FK_D32F: case FK_D32FS8: memcpy(v, p, 4); v[1] = v[2] = 0; break;
    case FK_D24S8: v[0] = (*(const uint32_t *)p & 0xffffff) / 16777215.0f; break;
    case FK_S8: v[0] = fbits(b[0]); break;
    case FK_X32S8: v[0] = fbits(b[4]); break;
    case FK_X24S8: v[0] = fbits(b[3]); break;
    default: v[0] = 1; v[1] = 0; v[2] = 1; v[3] = 1; break; /* not readable here yet: magenta */
    }
    if (f->bgr && f->kind != FK_BGR10XR) { float t = v[0]; v[0] = v[2]; v[2] = t; }
    if (f->srgb) for (int i = 0; i < 3; i++) v[i] = srgb_to_lin(v[i]);
    if (f->fmt == 1) { v[3] = v[0]; v[0] = v[1] = v[2] = 0; }
    memcpy(out, v, 16);
}

void mtl_texel_store(const struct mtl_fmt *f, void *p, const float in[4])
{
    unsigned char *b = p;
    float v[4] = {in[0], in[1], in[2], in[3]};
    uint32_t w;
    int n = f->n;
    if (f->fmt == 1) v[0] = v[3];
    if (f->srgb) for (int i = 0; i < 3; i++) v[i] = lin_to_srgb(v[i]);
    if (f->bgr && f->kind != FK_BGR10XR) { float t = v[0]; v[0] = v[2]; v[2] = t; }
    switch (f->kind) {
    case FK_UN8: for (int i = 0; i < n; i++) b[i] = (unsigned char)unorm(v[i], 255); break;
    case FK_SN8: for (int i = 0; i < n; i++) b[i] = (unsigned char)(signed char)snorm(v[i], 127); break;
    case FK_UI8: case FK_SI8: for (int i = 0; i < n; i++) b[i] = (unsigned char)ubits(v[i]); break;
    case FK_UN16: for (int i = 0; i < n; i++) ((uint16_t *)p)[i] = (uint16_t)unorm(v[i], 65535); break;
    case FK_SN16: for (int i = 0; i < n; i++) ((int16_t *)p)[i] = (int16_t)snorm(v[i], 32767); break;
    case FK_UI16: case FK_SI16: for (int i = 0; i < n; i++) ((uint16_t *)p)[i] = (uint16_t)ubits(v[i]); break;
    case FK_F16: for (int i = 0; i < n; i++) ((uint16_t *)p)[i] = mtl_float_to_half(v[i]); break;
    case FK_UI32: case FK_SI32: case FK_F32: memcpy(p, v, 4 * (size_t)n); break;
    case FK_B5G6R5:
        *(uint16_t *)p = (uint16_t)((unorm(v[2], 31) << 11) | (unorm(v[1], 63) << 5) | unorm(v[0], 31)); break;
    case FK_A1BGR5:
        *(uint16_t *)p = (uint16_t)((unorm(v[3], 1) << 15) | (unorm(v[2], 31) << 10) | (unorm(v[1], 31) << 5) |
                                    unorm(v[0], 31)); break;
    case FK_ABGR4:
        *(uint16_t *)p = (uint16_t)((unorm(v[3], 15) << 12) | (unorm(v[2], 15) << 8) | (unorm(v[1], 15) << 4) |
                                    unorm(v[0], 15)); break;
    case FK_BGR5A1:
        *(uint16_t *)p = (uint16_t)((unorm(v[2], 31) << 11) | (unorm(v[1], 31) << 6) | (unorm(v[0], 31) << 1) |
                                    unorm(v[3], 1)); break;
    case FK_RGB10A2N: case FK_BGR10A2:
        if (f->kind == FK_BGR10A2) { float t = v[0]; v[0] = v[2]; v[2] = t; }
        *(uint32_t *)p = unorm(v[0], 1023) | (unorm(v[1], 1023) << 10) | (unorm(v[2], 1023) << 20) | (unorm(v[3], 3) << 30);
        break;
    case FK_RGB10A2U:
        *(uint32_t *)p = (ubits(v[0]) & 1023) | ((ubits(v[1]) & 1023) << 10) | ((ubits(v[2]) & 1023) << 20) |
                         (ubits(v[3]) << 30);
        break;
    case FK_RG11B10F: *(uint32_t *)p = uf_make(v[0], 6) | (uf_make(v[1], 6) << 11) | (uf_make(v[2], 5) << 22); break;
    case FK_RGB9E5: {
        float mx = fmaxf(fmaxf(v[0], v[1]), v[2]);
        if (!(mx > 0)) { *(uint32_t *)p = 0; break; }
        int e;
        frexpf(mx, &e);
        int be = e + 15;
        if (be < 0) be = 0;
        if (be > 31) be = 31;
        float sc = ldexpf(1.0f, -(be - 15 - 9));
        uint32_t r = (uint32_t)clampf(rintf(v[0] * sc), 0, 511), g = (uint32_t)clampf(rintf(v[1] * sc), 0, 511),
                 bl = (uint32_t)clampf(rintf(v[2] * sc), 0, 511);
        *(uint32_t *)p = r | (g << 9) | (bl << 18) | ((uint32_t)be << 27);
        break;
    }
    case FK_BGR10XR:
        w = (uint32_t)clampf(rintf(v[2] * 510 + 384), 0, 1023) | ((uint32_t)clampf(rintf(v[1] * 510 + 384), 0, 1023) << 10) |
            ((uint32_t)clampf(rintf(v[0] * 510 + 384), 0, 1023) << 20);
        *(uint32_t *)p = w;
        break;
    case FK_BGRA10XR:
        for (int i = 0; i < 4; i++) ((uint16_t *)p)[i] = (uint16_t)((uint32_t)clampf(rintf(v[i] * 510 + 384), 0, 1023) << 6);
        break;
    case FK_D16: *(uint16_t *)p = (uint16_t)unorm(v[0], 65535); break;
    case FK_D32F: case FK_D32FS8: memcpy(p, v, 4); break;
    case FK_D24S8: w = *(uint32_t *)p; *(uint32_t *)p = (w & 0xff000000u) | unorm(v[0], 0xffffff); break;
    case FK_S8: b[0] = (unsigned char)ubits(v[0]); break;
    case FK_X32S8: b[4] = (unsigned char)ubits(v[0]); break;
    case FK_X24S8: b[3] = (unsigned char)ubits(v[0]); break;
    default: break;
    }
}

/* ---- texture layout ---------------------------------------------------------------- */
size_t mtl_tex_layout(struct __ferry_tex *t, size_t bytes_per_row)
{
    size_t total = 0;
    int bc = t->f && t->f->kind == FK_BC;
    if (t->levels > MTL_MAX_LEVELS) t->levels = MTL_MAX_LEVELS;
    for (unsigned l = 0; l < t->levels; l++) {
        unsigned w = t->w >> l, h = t->h >> l, d = t->d >> l;
        if (!w) w = 1;
        if (!h) h = 1;
        if (!d) d = 1;
        if (t->type == 0 || t->type == 1 || t->type == 9) h = 1; /* 1D, 1D array, buffer */
        if (t->type != 7) d = 1;
        t->lw[l] = w; t->lh[l] = h; t->ld[l] = d;
        size_t row = bc ? (size_t)((w + 3) / 4) * t->f->bpp : (size_t)w * t->f->bpp;
        if (l == 0 && bytes_per_row) row = bytes_per_row;
        size_t rows = bc ? (h + 3) / 4 : h;
        t->row[l] = row;
        t->img[l] = row * rows;
        t->layer_size[l] = t->img[l] * d;
        t->off[l] = total;
        total += (t->layer_size[l] * t->layers + 15) & ~(size_t)15;
    }
    return total;
}

static void apply_swizzle(const struct __ferry_tex *t, float v[4])
{
    if (t->identity_swz) return;
    float s[4], one = t->f->is_int ? fbits(1) : 1.0f;
    memcpy(s, v, 16);
    for (int i = 0; i < 4; i++) {
        switch (t->swz[i]) {
        case 0: v[i] = 0; break;
        case 1: v[i] = one; break;
        default: v[i] = s[(t->swz[i] - 2) & 3]; break;
        }
    }
}

void mtl_tex_fetch(const struct __ferry_tex *t, int x, int y, int z, int layer, int lvl, float out[4])
{
    if (lvl < 0) lvl = 0;
    if ((unsigned)lvl >= t->levels) lvl = (int)t->levels - 1;
    if (x < 0 || y < 0 || z < 0 || layer < 0 || (unsigned)x >= t->lw[lvl] || (unsigned)y >= t->lh[lvl] ||
        (unsigned)z >= t->ld[lvl] || (unsigned)layer >= t->layers) {
        out[0] = out[1] = out[2] = out[3] = 0;
        return;
    }
    mtl_texel_load(t->f, mtl_texel(t, (unsigned)x, (unsigned)y, (unsigned)z, (unsigned)layer, (unsigned)lvl), out);
    apply_swizzle(t, out);
}

/* x, y, z as a read passes them: the layer is y for a 1D array and z for 2D
 * arrays and cubes. */
static void split_coords(const struct __ferry_tex *t, int *x, int *y, int *z, int *layer)
{
    *layer = 0;
    switch (t->type) {
    case 1: *layer = *y; *y = 0; *z = 0; break;            /* 1D array */
    case 3: case 5: case 6: case 8: *layer = *z; *z = 0; break; /* 2D array, cube, cube array, 2D MS array */
    default: break;
    }
}

/* ---- what shaders call --------------------------------------------------------------- */
void __ferry_tex_read_f(const struct __ferry_tex *t, int x, int y, int z, int lod, int sample, float *out)
{
    if (!t) { out[0] = out[1] = out[2] = out[3] = 0; return; }
    int layer;
    split_coords(t, &x, &y, &z, &layer);
    mtl_tex_fetch(t, x, y, z, layer, lod, out);
}
void __ferry_tex_read_i(const struct __ferry_tex *t, int x, int y, int z, int lod, int sample, unsigned int *out)
{ __ferry_tex_read_f(t, x, y, z, lod, sample, (float *)out); }

static void tex_write(const struct __ferry_tex *t, int x, int y, int z, int lod, const float *in)
{
    if (!t) return;
    int layer;
    split_coords(t, &x, &y, &z, &layer);
    if (lod < 0 || (unsigned)lod >= t->levels || x < 0 || y < 0 || z < 0 || layer < 0 ||
        (unsigned)x >= t->lw[lod] || (unsigned)y >= t->lh[lod] || (unsigned)z >= t->ld[lod] ||
        (unsigned)layer >= t->layers)
        return;
    mtl_texel_store(t->f, mtl_texel(t, (unsigned)x, (unsigned)y, (unsigned)z, (unsigned)layer, (unsigned)lod), in);
}
void __ferry_tex_write_f(const struct __ferry_tex *t, int x, int y, int z, int lod, const float *in)
{ tex_write(t, x, y, z, lod, in); }
void __ferry_tex_write_i(const struct __ferry_tex *t, int x, int y, int z, int lod, const unsigned int *in)
{ tex_write(t, x, y, z, lod, (const float *)in); }

unsigned int __ferry_tex_size(const struct __ferry_tex *t, int what, int lod)
{
    if (!t) return 0;
    if (lod < 0 || (unsigned)lod >= t->levels) lod = 0;
    switch (what) {
    case 0: return t->lw[lod];
    case 1: return t->lh[lod];
    case 2: return t->ld[lod];
    case 3: return (t->type == 5 || t->type == 6) ? t->layers / 6 : t->layers;
    case 4: return t->levels;
    case 5: return t->samples;
    }
    return 0;
}

unsigned int __ferry_tex_atomic(const struct __ferry_tex *t, int x, int y, int z, int op, unsigned int v, unsigned int cmp)
{
    if (!t) return 0;
    int layer;
    split_coords(t, &x, &y, &z, &layer);
    if (x < 0 || y < 0 || (unsigned)x >= t->lw[0] || (unsigned)y >= t->lh[0] || (unsigned)layer >= t->layers) return 0;
    unsigned int *p = (unsigned int *)mtl_texel(t, (unsigned)x, (unsigned)y, (unsigned)z, (unsigned)layer, 0);
    switch (op) {
    case 0: return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST);
    case 1: return __atomic_fetch_and(p, v, __ATOMIC_SEQ_CST);
    case 2: return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST);
    case 3: return __atomic_fetch_xor(p, v, __ATOMIC_SEQ_CST);
    case 4: { unsigned o = __atomic_load_n(p, __ATOMIC_SEQ_CST);
              while (v < o && !__atomic_compare_exchange_n(p, &o, v, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
              return o; }
    case 5: { unsigned o = __atomic_load_n(p, __ATOMIC_SEQ_CST);
              while (v > o && !__atomic_compare_exchange_n(p, &o, v, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
              return o; }
    case 6: return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST);
    case 7: { unsigned o = cmp; __atomic_compare_exchange_n(p, &o, v, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); return o; }
    case 8: { int o = __atomic_load_n((int *)p, __ATOMIC_SEQ_CST);   /* signed min and max */
              while ((int)v < o && !__atomic_compare_exchange_n((int *)p, &o, (int)v, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
              return (unsigned)o; }
    case 9: { int o = __atomic_load_n((int *)p, __ATOMIC_SEQ_CST);
              while ((int)v > o && !__atomic_compare_exchange_n((int *)p, &o, (int)v, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
              return (unsigned)o; }
    }
    return 0;
}

/* ---- sampling -------------------------------------------------------------------------- */
static int address(int i, int n, int mode, int *outside)
{
    switch (mode) {
    case FERRY_ADDR_REPEAT: i %= n; if (i < 0) i += n; return i;
    case FERRY_ADDR_MIRRORED_REPEAT: {
        int p = 2 * n;
        i %= p;
        if (i < 0) i += p;
        return i < n ? i : p - 1 - i;
    }
    case FERRY_ADDR_MIRROR_CLAMP_TO_EDGE:
        if (i < 0) i = -1 - i;
        return i >= n ? n - 1 : i;
    case FERRY_ADDR_CLAMP_TO_ZERO: case FERRY_ADDR_CLAMP_TO_BORDER:
        if (i < 0 || i >= n) { *outside = 1; return 0; }
        return i;
    default: return i < 0 ? 0 : i >= n ? n - 1 : i;
    }
}
static void border(const struct ferry_sampler *s, int is_int, float out[4])
{
    float one = is_int ? fbits(1) : 1.0f;
    if (s->s_address == FERRY_ADDR_CLAMP_TO_ZERO || s->border == 0) { out[0] = out[1] = out[2] = out[3] = 0; return; }
    out[0] = out[1] = out[2] = s->border == 2 ? one : 0;
    out[3] = one;
}
/* One texel at integer coordinates with the sampler's addressing. */
static void texel_at(const struct __ferry_tex *t, const struct ferry_sampler *s, int lvl, int x, int y, int z, int layer,
                     int is_int, float out[4])
{
    int outside = 0;
    x = address(x, (int)t->lw[lvl], s->s_address, &outside);
    y = address(y, (int)t->lh[lvl], s->t_address, &outside);
    z = address(z, (int)t->ld[lvl], s->r_address, &outside);
    if (outside) { border(s, is_int, out); return; }
    mtl_texel_load(t->f, mtl_texel(t, (unsigned)x, (unsigned)y, (unsigned)z, (unsigned)layer, (unsigned)lvl), out);
    apply_swizzle(t, out);
}
static void sample_level(const struct __ferry_tex *t, const struct ferry_sampler *s, int lvl, const float *u, int dims,
                         int layer, const int *off, int linear, int is_int, float out[4])
{
    float c[3] = {0, 0, 0};
    int sz[3] = {(int)t->lw[lvl], (int)t->lh[lvl], (int)t->ld[lvl]};
    for (int i = 0; i < dims; i++) c[i] = u[i] * (float)sz[i] + (off ? (float)off[i] : 0);
    if (!linear || is_int || t->f->is_int) {
        int x = (int)floorf(c[0]), y = dims > 1 ? (int)floorf(c[1]) : 0, z = dims > 2 ? (int)floorf(c[2]) : 0;
        texel_at(t, s, lvl, x, y, z, layer, is_int, out);
        return;
    }
    float f[3] = {0, 0, 0};
    int i0[3] = {0, 0, 0};
    for (int i = 0; i < dims; i++) {
        float p = c[i] - 0.5f;
        float fl = floorf(p);
        i0[i] = (int)fl;
        f[i] = p - fl;
    }
    float acc[4] = {0, 0, 0, 0};
    int nz = dims > 2 ? 2 : 1, ny = dims > 1 ? 2 : 1;
    for (int dz = 0; dz < nz; dz++)
        for (int dy = 0; dy < ny; dy++)
            for (int dx = 0; dx < 2; dx++) {
                float wgt = (dx ? f[0] : 1 - f[0]) * (dims > 1 ? (dy ? f[1] : 1 - f[1]) : 1) *
                            (dims > 2 ? (dz ? f[2] : 1 - f[2]) : 1);
                if (wgt == 0) continue;
                float tx[4];
                texel_at(t, s, lvl, i0[0] + dx, i0[1] + dy, i0[2] + dz, layer, is_int, tx);
                for (int k = 0; k < 4; k++) acc[k] += wgt * tx[k];
            }
    memcpy(out, acc, 16);
}
/* A cube direction to a face and its 0..1 coordinates (the faces in Metal's
 * order: +x, -x, +y, -y, +z, -z). */
static int cube_face(const float *d, float uv[2], float *ma_out)
{
    float ax = fabsf(d[0]), ay = fabsf(d[1]), az = fabsf(d[2]), ma, sc, tc;
    int face;
    if (ax >= ay && ax >= az) {
        ma = ax;
        if (d[0] >= 0) { face = 0; sc = -d[2]; tc = -d[1]; }
        else { face = 1; sc = d[2]; tc = -d[1]; }
    } else if (ay >= az) {
        ma = ay;
        if (d[1] >= 0) { face = 2; sc = d[0]; tc = d[2]; }
        else { face = 3; sc = d[0]; tc = -d[2]; }
    } else {
        ma = az;
        if (d[2] >= 0) { face = 4; sc = d[0]; tc = -d[1]; }
        else { face = 5; sc = -d[0]; tc = -d[1]; }
    }
    if (ma == 0) ma = 1;
    uv[0] = (sc / ma + 1) * 0.5f;
    uv[1] = (tc / ma + 1) * 0.5f;
    *ma_out = ma;
    return face;
}
static int tex_dims(const struct __ferry_tex *t)
{
    switch (t->type) {
    case 0: case 1: case 9: return 1;
    case 7: return 3;
    default: return 2;
    }
}

void __ferry_tex_sample(const struct __ferry_tex *t, const void *sampler, const float *coord, int ncoord, int layer,
                        int mode, float lodval, const float *grad, const int *offset, int is_int, float *out)
{
    if (!t) { out[0] = out[1] = out[2] = out[3] = 0; return; }
    const struct ferry_sampler *s = sampler;
    int dims = tex_dims(t), cube = t->type == 5 || t->type == 6;
    float u[3] = {coord[0], ncoord > 1 ? coord[1] : 0, ncoord > 2 ? coord[2] : 0};
    float g[6] = {0, 0, 0, 0, 0, 0};
    if (grad) memcpy(g, grad, sizeof g);
    float scale = 1;
    if (cube) {
        float ma;
        int face = cube_face(u, u, &ma);
        layer = layer * 6 + face;
        scale = 0.5f / ma;
        dims = 2;
    }
    if (layer < 0) layer = 0;
    if ((unsigned)layer >= t->layers) layer = (int)t->layers - 1;
    if (!s->normalized && !cube) {
        for (int i = 0; i < dims; i++) {
            int sz = i == 0 ? (int)t->lw[0] : i == 1 ? (int)t->lh[0] : (int)t->ld[0];
            u[i] /= (float)sz;
        }
        mode = 1;
        lodval = 0;
    }
    float lod;
    if (mode == 1) lod = lodval;
    else {
        float rx = 0, ry = 0;
        for (int i = 0; i < dims; i++) {
            float sz = (float)(i == 0 ? t->lw[0] : i == 1 ? t->lh[0] : t->ld[0]) * scale;
            rx += (g[i] * sz) * (g[i] * sz);
            ry += (g[3 + i] * sz) * (g[3 + i] * sz);
        }
        float rho = sqrtf(fmaxf(rx, ry));
        lod = rho > 0 ? log2f(rho) : -1000.0f;
        if (mode == 2) lod += lodval;
    }
    lod = clampf(lod, s->lod_min, s->lod_max);
    int linear;
    float lvl;
    if (lod <= 0) { linear = s->mag_filter; lvl = 0; }
    else { linear = s->min_filter; lvl = lod; }
    float maxl = (float)(t->levels - 1);
    if (s->mip_filter == 0 || t->levels == 1) {
        sample_level(t, s, 0, u, dims, layer, offset, linear, is_int, out);
        return;
    }
    if (lvl > maxl) lvl = maxl;
    if (s->mip_filter == 1) {
        sample_level(t, s, (int)floorf(lvl + 0.5f), u, dims, layer, offset, linear, is_int, out);
        return;
    }
    int l0 = (int)floorf(lvl), l1 = l0 + 1 > (int)maxl ? (int)maxl : l0 + 1;
    float fr = lvl - (float)l0;
    sample_level(t, s, l0, u, dims, layer, offset, linear, is_int, out);
    if (fr > 0 && l1 != l0) {
        float b[4];
        sample_level(t, s, l1, u, dims, layer, offset, linear, is_int, b);
        for (int k = 0; k < 4; k++) out[k] = out[k] * (1 - fr) + b[k] * fr;
    }
}

static int compare(int func, float ref, float v)
{
    switch (func) {
    case FERRY_CMP_NEVER: return 0;
    case FERRY_CMP_LESS: return ref < v;
    case FERRY_CMP_EQUAL: return ref == v;
    case FERRY_CMP_LESS_EQUAL: return ref <= v;
    case FERRY_CMP_GREATER: return ref > v;
    case FERRY_CMP_NOT_EQUAL: return ref != v;
    case FERRY_CMP_GREATER_EQUAL: return ref >= v;
    case FERRY_CMP_ALWAYS: return 1;
    default: return ref <= v;
    }
}
float __ferry_tex_sample_compare(const struct __ferry_tex *t, const void *sampler, const float *coord, int ncoord,
                                 int layer, float ref, int mode, float lodval, const int *offset)
{
    if (!t) return 0;
    const struct ferry_sampler *s = sampler;
    int cube = t->type == 5 || t->type == 6;
    float u[3] = {coord[0], ncoord > 1 ? coord[1] : 0, ncoord > 2 ? coord[2] : 0}, ma;
    if (cube) layer = layer * 6 + cube_face(u, u, &ma);
    if (layer < 0) layer = 0;
    if ((unsigned)layer >= t->layers) layer = (int)t->layers - 1;
    if (!s->normalized) { u[0] /= (float)t->lw[0]; u[1] /= (float)t->lh[0]; }
    int lvl = mode == 1 ? (int)clampf(lodval, 0, (float)(t->levels - 1)) : 0;
    float c[2] = {u[0] * (float)t->lw[lvl] + (offset ? (float)offset[0] : 0),
                  u[1] * (float)t->lh[lvl] + (offset ? (float)offset[1] : 0)};
    if (!s->min_filter && !s->mag_filter) {
        float tx[4];
        texel_at(t, s, lvl, (int)floorf(c[0]), (int)floorf(c[1]), 0, layer, 0, tx);
        return (float)compare(s->compare, ref, tx[0]);
    }
    float px = c[0] - 0.5f, py = c[1] - 0.5f, fx = px - floorf(px), fy = py - floorf(py);
    int x0 = (int)floorf(px), y0 = (int)floorf(py);
    float acc = 0;
    for (int dy = 0; dy < 2; dy++)
        for (int dx = 0; dx < 2; dx++) {
            float tx[4];
            texel_at(t, s, lvl, x0 + dx, y0 + dy, 0, layer, 0, tx);
            acc += (dx ? fx : 1 - fx) * (dy ? fy : 1 - fy) * (float)compare(s->compare, ref, tx[0]);
        }
    return acc;
}

void __ferry_tex_gather(const struct __ferry_tex *t, const void *sampler, const float *coord, int ncoord, int layer,
                        const int *offset, int component, int is_int, float *out)
{
    if (!t) { out[0] = out[1] = out[2] = out[3] = 0; return; }
    const struct ferry_sampler *s = sampler;
    int cube = t->type == 5 || t->type == 6;
    float u[3] = {coord[0], ncoord > 1 ? coord[1] : 0, ncoord > 2 ? coord[2] : 0}, ma;
    if (cube) layer = layer * 6 + cube_face(u, u, &ma);
    if (layer < 0) layer = 0;
    if ((unsigned)layer >= t->layers) layer = (int)t->layers - 1;
    if (!s->normalized) { u[0] /= (float)t->lw[0]; u[1] /= (float)t->lh[0]; }
    float px = u[0] * (float)t->lw[0] - 0.5f + (offset ? (float)offset[0] : 0);
    float py = u[1] * (float)t->lh[0] - 0.5f + (offset ? (float)offset[1] : 0);
    int x0 = (int)floorf(px), y0 = (int)floorf(py);
    static const int ox[4] = {0, 1, 1, 0}, oy[4] = {1, 1, 0, 0};
    for (int i = 0; i < 4; i++) {
        float tx[4];
        texel_at(t, s, 0, x0 + ox[i], y0 + oy[i], 0, layer, is_int, tx);
        out[i] = tx[component & 3];
    }
}

void __ferry_print(const char *s) { fprintf(stderr, "%s", s); }
