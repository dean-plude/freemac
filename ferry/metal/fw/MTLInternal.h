/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework (freemac 1.NEXT): what its parts share. Written
 * from Apple's public Metal documentation; Metal here draws on the
 * processor. Shaders are compiled to ordinary code by ferry-mslc; a draw
 * runs the vertex function for each vertex, clips, rasterizes in 2x2 quads
 * and runs the fragment function for each covered pixel (fibers let the
 * four pixels of a quad trade values for derivatives); a dispatch runs a
 * kernel's threadgroups side by side and the threads of one group on
 * fibers, so threadgroup barriers work. Textures keep their own pixel
 * format in ordinary memory. Built without ARC. */
#ifndef FERRY_MTL_INTERNAL_H
#define FERRY_MTL_INTERNAL_H
#include <stddef.h>
#include <stdint.h>
#include "../msl/ferry_metal_abi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- pixel formats ---------------------------------------------------------------- */
enum {
    FK_NONE, FK_UN8, FK_SN8, FK_UI8, FK_SI8, FK_UN16, FK_SN16, FK_UI16, FK_SI16, FK_F16, FK_UI32, FK_SI32, FK_F32,
    FK_B5G6R5, FK_A1BGR5, FK_ABGR4, FK_BGR5A1, FK_RGB10A2N, FK_RGB10A2U, FK_RG11B10F, FK_RGB9E5, FK_BGR10A2,
    FK_BGR10XR, FK_BGRA10XR, FK_D16, FK_D32F, FK_S8, FK_D24S8, FK_D32FS8, FK_X32S8, FK_X24S8, FK_BC, FK_422,
};
struct mtl_fmt {
    unsigned fmt;           /* MTLPixelFormat */
    unsigned char bpp;      /* bytes per texel (per 4x4 block for BC formats) */
    unsigned char kind;     /* FK_* */
    unsigned char n;        /* components stored */
    unsigned char bgr;      /* stored blue first */
    unsigned char srgb;
    unsigned char is_int;   /* 1 signed, 2 unsigned: read as integers */
    unsigned char depth, stencil;
    const char *name;
};
const struct mtl_fmt *mtl_format(unsigned fmt);
/* One texel to four floats (or four 32-bit integers for integer formats)
 * and back. */
void mtl_texel_load(const struct mtl_fmt *f, const void *p, float out[4]);
void mtl_texel_store(const struct mtl_fmt *f, void *p, const float in[4]);
float mtl_half_to_float(uint16_t h);
uint16_t mtl_float_to_half(float f);

/* ---- textures (what a shader's texture handle points at) -------------------------- */
#define MTL_MAX_LEVELS 16
struct __ferry_tex {
    const struct mtl_fmt *f;
    unsigned type;                  /* MTLTextureType */
    unsigned w, h, d, levels, layers, samples;
    char *base;
    size_t off[MTL_MAX_LEVELS];     /* the level's first layer */
    size_t layer_size[MTL_MAX_LEVELS], img[MTL_MAX_LEVELS], row[MTL_MAX_LEVELS];
    unsigned lw[MTL_MAX_LEVELS], lh[MTL_MAX_LEVELS], ld[MTL_MAX_LEVELS];
    unsigned char swz[4];           /* MTLTextureSwizzle */
    unsigned char identity_swz;
};
static inline char *mtl_texel(const struct __ferry_tex *t, unsigned x, unsigned y, unsigned z, unsigned layer,
                              unsigned lvl)
{
    return t->base + t->off[lvl] + layer * t->layer_size[lvl] + z * t->img[lvl] + y * t->row[lvl] +
           (size_t)x * t->f->bpp;
}
/* Lay out a new texture's levels (the sizes and offsets) and answer how
 * many bytes it needs. */
size_t mtl_tex_layout(struct __ferry_tex *t, size_t bytes_per_row);
/* Read and write a texel with the swizzle and the format's conversion. */
void mtl_tex_fetch(const struct __ferry_tex *t, int x, int y, int z, int layer, int lvl, float out[4]);

/* ---- running shader code: fibers --------------------------------------------------- */
typedef void (*mtl_lane_fn)(void *arg, int lane);
/* Run fn for lanes 0..n-1 of one group, each on a fiber of its own, so that
 * quad exchanges and threadgroup barriers can wait for the others. kind 1
 * is a fragment quad (four lanes), kind 2 a compute threadgroup. */
void mtl_run_lanes(int kind, int n, mtl_lane_fn fn, void *arg);
/* For the fragment wrappers: the lane is discarded. */
int mtl_lane_discarded(int lane);
/* Threadgroup memory of the group being run (reset for each group). */
void mtl_tg_reset(void);

/* ---- draws and dispatches ---------------------------------------------------------- */
struct mtl_vattr { unsigned format, offset, buffer; };
struct mtl_vlayout { unsigned stride, step, rate; };
struct mtl_vdesc {
    struct mtl_vattr attr[31];
    struct mtl_vlayout layout[31];
    unsigned nattr_used;            /* bit mask of attributes set */
};
/* A compiled function: its entry points in the loaded library. */
struct mtl_slots { int n; struct ferry_slot s[96]; };
struct mtl_fn {
    int stage;                      /* 1 vertex, 2 fragment, 3 kernel */
    void (*vs)(const struct ferry_call *, float *);
    void (*fs)(const struct ferry_call *, const float *, float *);
    void (*cs)(const struct ferry_call *);
    struct mtl_slots slots;
    unsigned max_threads;
};
struct mtl_blend {
    unsigned char enabled, write_mask;
    unsigned char src_rgb, dst_rgb, op_rgb, src_a, dst_a, op_a;
};
struct mtl_rpipe {
    const struct mtl_fn *vs, *fs;
    struct mtl_vdesc vd;
    int vsize;                      /* floats a vertex's results take */
    int nvary;                      /* floats of varyings, from FERRY_VS_VARYINGS */
    unsigned char interp[256];      /* per varying float: FERRY_I_* */
    int stage_in_map[64];
    int writes_depth, writes_mask, writes_stencil, has_point_size, nclip;
    unsigned color_formats[8];
    struct mtl_blend blend[8];
    int color_kind[8];              /* the fragment's result kind for each color, -1 none */
    unsigned depth_format, stencil_format;
    int alpha_to_coverage, raster_enabled;
};
struct mtl_stencil_face {
    unsigned char func, fail, zfail, pass;
    uint32_t read_mask, write_mask;
};
struct mtl_dsstate {
    unsigned char depth_func, depth_write;
    struct mtl_stencil_face front, back;
    int stencil_enabled;
};
/* The state a draw was recorded with. */
struct mtl_bindings {
    void *buffers[FERRY_MAX_BUFFERS];
    const void *textures[FERRY_MAX_TEXTURES];
    const struct ferry_sampler *samplers[FERRY_MAX_SAMPLERS];
};
struct mtl_attachment {
    struct __ferry_tex *tex;
    unsigned level, slice, plane;
};
struct mtl_draw_state {
    const struct mtl_rpipe *p;
    const struct mtl_dsstate *ds;
    struct mtl_bindings vb, fb;
    double vp[6];
    int scissor[4];
    unsigned cull, winding, fill, clip_mode;
    float depth_bias, slope, bias_clamp;
    uint32_t stencil_ref_front, stencil_ref_back;
    float blend_color[4];
    unsigned vis_mode;
    uint64_t *vis_counter;
};
struct mtl_target {
    struct mtl_attachment color[8];
    struct mtl_attachment depth, stencil;
    unsigned width, height;
};
struct mtl_draw {
    unsigned prim;                  /* MTLPrimitiveType */
    unsigned first, count, instances, base_instance;
    int base_vertex;
    const void *indices;            /* NULL: not indexed */
    unsigned index_size;            /* 2 or 4 */
};
void mtl_execute_draw(const struct mtl_target *rt, const struct mtl_draw_state *st, const struct mtl_draw *d);
void mtl_clear_attachment(const struct mtl_attachment *a, const double rgba[4], int what, double depth,
                          uint32_t stencil);
struct mtl_dispatch {
    const struct mtl_fn *fn;
    struct mtl_bindings b;
    size_t tglen[16];
    unsigned groups[3], tpg[3], grid[3];
    int nonuniform;
};
void mtl_execute_dispatch(const struct mtl_dispatch *d);

/* ---- logging -------------------------------------------------------------------------- */
void mtl_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
extern int mtl_verbose;

#ifdef __cplusplus
}
#endif
#endif
