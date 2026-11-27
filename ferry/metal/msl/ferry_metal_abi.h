/* SPDX-License-Identifier: GPL-3.0-or-later
 * What a compiled shader and Ferry's Metal.framework agree on: the sampler
 * record and the call context each shader wrapper receives. Shared by the
 * shader library (C++ for OpenCL) and Metal.framework (Objective-C), so it
 * uses only plain C. */
#ifndef FERRY_METAL_ABI_H
#define FERRY_METAL_ABI_H

#ifdef __cplusplus
extern "C" {
#endif

/* One sampler, as MTLSamplerDescriptor or a constexpr sampler sets it. */
struct ferry_sampler {
    unsigned char normalized;  /* 1: coordinates run 0..1 */
    unsigned char s_address, t_address, r_address; /* FERRY_ADDR_* */
    unsigned char mag_filter, min_filter;          /* 0 nearest, 1 linear */
    unsigned char mip_filter;                      /* 0 none, 1 nearest, 2 linear */
    unsigned char compare;                         /* FERRY_CMP_* */
    unsigned char border;                          /* 0 transparent black, 1 opaque black, 2 opaque white */
    unsigned char max_anisotropy;
    unsigned char pad[2];
    float lod_min, lod_max;
};
enum { FERRY_ADDR_CLAMP_TO_EDGE = 0, FERRY_ADDR_MIRROR_CLAMP_TO_EDGE = 1, FERRY_ADDR_REPEAT = 2,
       FERRY_ADDR_MIRRORED_REPEAT = 3, FERRY_ADDR_CLAMP_TO_ZERO = 4, FERRY_ADDR_CLAMP_TO_BORDER = 5 };
enum { FERRY_CMP_NEVER = 0, FERRY_CMP_LESS = 1, FERRY_CMP_EQUAL = 2, FERRY_CMP_LESS_EQUAL = 3,
       FERRY_CMP_GREATER = 4, FERRY_CMP_NOT_EQUAL = 5, FERRY_CMP_GREATER_EQUAL = 6, FERRY_CMP_ALWAYS = 7,
       FERRY_CMP_NONE = 8 };

enum { FERRY_MAX_BUFFERS = 31, FERRY_MAX_TEXTURES = 128, FERRY_MAX_SAMPLERS = 16 };

/* The resources bound for one draw or dispatch, and the built-in values a
 * stage's arguments ask for. */
struct ferry_call {
    void *buffers[FERRY_MAX_BUFFERS];
    const void *textures[FERRY_MAX_TEXTURES];
    const struct ferry_sampler *samplers[FERRY_MAX_SAMPLERS];
    const void *fetch_ctx;          /* vertex fetch, for [[stage_in]] */
    unsigned int vertex_id, instance_id, base_vertex, base_instance;
    unsigned int primitive_id, sample_id, sample_mask_in;
    unsigned int front_facing, render_target_array_index, viewport_array_index, amplification_id;
    float position[4];              /* fragment: window x, y, depth, 1/w */
    float point_coord[2];
    unsigned int grid[8][3];        /* compute: see FERRY_G_* */
    unsigned int stage_in_map[64];  /* fragment input field -> offset into the varyings */
    void *tgmem[16];                /* compute: [[threadgroup(n)]] memory */
};

/* What a stage reads and writes, as the info function of its wrapper
 * lists it (one record per value). */
struct ferry_slot {
#ifdef __OPENCL_CPP_VERSION__
    const __constant char *tag; /* (string literals are constant memory in a shader) */
#else
    const char *tag;   /* [[user(tag)]], or the field's name */
#endif
    int what;          /* FERRY_W_* */
    int index;         /* color(n), attribute(n), clip_distance element... */
    int offset;        /* in floats, into the vertex output or fragment results */
    int ncomp, kind;   /* components; FERRY_K_* */
    int interp;        /* fragment inputs: FERRY_I_* */
};
enum { FERRY_W_VARYING = 0, FERRY_W_POSITION, FERRY_W_POINT_SIZE, FERRY_W_CLIP_DISTANCE, FERRY_W_COLOR,
       FERRY_W_DEPTH, FERRY_W_SAMPLE_MASK, FERRY_W_STENCIL, FERRY_W_ATTRIBUTE, FERRY_W_INPUT,
       FERRY_W_BUILTIN_INPUT };
enum { FERRY_I_PERSPECTIVE = 0, FERRY_I_FLAT = 1, FERRY_I_NO_PERSPECTIVE = 2 };
/* Where a vertex function's results go: position first, then the point
 * size and up to eight clip distances, then the varyings. */
enum { FERRY_VS_POSITION = 0, FERRY_VS_POINT_SIZE = 4, FERRY_VS_CLIP = 5, FERRY_VS_VARYINGS = 16 };
/* A fragment function's results: eight colors of four, then depth, the
 * sample mask and the stencil reference. */
enum { FERRY_FS_DEPTH = 32, FERRY_FS_SAMPLE_MASK = 33, FERRY_FS_STENCIL = 34, FERRY_FS_RESULTS = 36 };
enum { FERRY_G_THREAD_POS = 0, FERRY_G_THREADGROUP_POS, FERRY_G_THREAD_IN_GROUP, FERRY_G_THREADS_PER_GROUP,
       FERRY_G_THREADS_PER_GRID, FERRY_G_THREADGROUPS_PER_GRID, FERRY_G_INDEX_IN_GROUP };

/* Kinds of values that pass between stages and to attachments. */
enum { FERRY_K_FLOAT = 0, FERRY_K_HALF = 1, FERRY_K_INT = 2, FERRY_K_UINT = 3 };

/* Threadgroup memory a kernel declares in its body: the same block for
 * every thread of the group, by the declaration's number. */
void *__ferry_tg_alloc(unsigned long size, unsigned long align, int id);
/* Vertex attributes: Metal.framework fetches and converts one attribute
 * to four floats or four 32-bit integers. */
void ferry_fetch_attr(const void *fetch_ctx, int attr, unsigned int vid, unsigned int iid, int want_int,
                      void *out4);

#ifdef __cplusplus
}
#endif
#endif
