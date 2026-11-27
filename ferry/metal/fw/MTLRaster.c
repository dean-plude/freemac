/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: drawing and compute on the processor. A draw
 * fetches and shades its vertices, assembles points, lines and triangles,
 * clips them in clip space, maps them to the viewport and rasterizes them
 * in 2x2 quads with the top-left fill rule. The target is cut into tiles
 * that are drawn side by side, each tile taking the primitives in order, so
 * blending and depth keep Metal's order. Fragments get perspective-correct
 * inputs, then the depth and stencil tests, blending and the write mask. A
 * dispatch runs its threadgroups side by side. Written from Apple's public
 * Metal documentation. */
#include "MTLInternal.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define MAXV (FERRY_VS_VARYINGS + 256)
#define FSOUT (FERRY_FS_RESULTS + 32)
#define TILE 64

static dispatch_queue_t workers(void)
{
    return dispatch_get_global_queue(0, 0);
}

/* ---- vertex attributes --------------------------------------------------------------- */
struct fetch_ctx {
    const struct mtl_vdesc *vd;
    void *const *buffers;
    unsigned base_instance;
};
enum { VT_U8, VT_S8, VT_U16, VT_S16, VT_F16, VT_F32, VT_S32, VT_U32, VT_I1010102, VT_U1010102, VT_BGRA8, VT_RG11B10,
       VT_RGB9E5 };
struct vfmt { unsigned char n, type, norm; };
static const struct vfmt vfmts[56] = {
    [1] = {2, VT_U8, 0}, [2] = {3, VT_U8, 0}, [3] = {4, VT_U8, 0},
    [4] = {2, VT_S8, 0}, [5] = {3, VT_S8, 0}, [6] = {4, VT_S8, 0},
    [7] = {2, VT_U8, 1}, [8] = {3, VT_U8, 1}, [9] = {4, VT_U8, 1},
    [10] = {2, VT_S8, 1}, [11] = {3, VT_S8, 1}, [12] = {4, VT_S8, 1},
    [13] = {2, VT_U16, 0}, [14] = {3, VT_U16, 0}, [15] = {4, VT_U16, 0},
    [16] = {2, VT_S16, 0}, [17] = {3, VT_S16, 0}, [18] = {4, VT_S16, 0},
    [19] = {2, VT_U16, 1}, [20] = {3, VT_U16, 1}, [21] = {4, VT_U16, 1},
    [22] = {2, VT_S16, 1}, [23] = {3, VT_S16, 1}, [24] = {4, VT_S16, 1},
    [25] = {2, VT_F16, 0}, [26] = {3, VT_F16, 0}, [27] = {4, VT_F16, 0},
    [28] = {1, VT_F32, 0}, [29] = {2, VT_F32, 0}, [30] = {3, VT_F32, 0}, [31] = {4, VT_F32, 0},
    [32] = {1, VT_S32, 0}, [33] = {2, VT_S32, 0}, [34] = {3, VT_S32, 0}, [35] = {4, VT_S32, 0},
    [36] = {1, VT_U32, 0}, [37] = {2, VT_U32, 0}, [38] = {3, VT_U32, 0}, [39] = {4, VT_U32, 0},
    [40] = {4, VT_I1010102, 1}, [41] = {4, VT_U1010102, 1}, [42] = {4, VT_BGRA8, 1},
    [45] = {1, VT_U8, 0}, [46] = {1, VT_S8, 0}, [47] = {1, VT_U8, 1}, [48] = {1, VT_S8, 1},
    [49] = {1, VT_U16, 0}, [50] = {1, VT_S16, 0}, [51] = {1, VT_U16, 1}, [52] = {1, VT_S16, 1},
    [53] = {1, VT_F16, 0}, [54] = {3, VT_RG11B10, 0}, [55] = {3, VT_RGB9E5, 0},
};

void ferry_fetch_attr(const void *ctxp, int attr, unsigned int vid, unsigned int iid, int want_int, void *out4)
{
    const struct fetch_ctx *fc = ctxp;
    float f[4] = {0, 0, 0, 1};
    int32_t iv[4] = {0, 0, 0, 1};
    int isint = 0;
    if (!fc || attr < 0 || attr >= 31 || !(fc->vd->nattr_used & (1u << attr))) goto done;
    const struct mtl_vattr *a = &fc->vd->attr[attr];
    if (a->buffer >= 31 || a->format >= 56 || !vfmts[a->format].n) goto done;
    const struct mtl_vlayout *l = &fc->vd->layout[a->buffer];
    const unsigned char *base = fc->buffers[a->buffer];
    if (!base) goto done;
    size_t index;
    switch (l->step) {
    case 0: index = 0; break;                                                   /* constant */
    case 2: index = fc->base_instance + (iid - fc->base_instance) / (l->rate ? l->rate : 1); break;
    default: index = vid; break;
    }
    const unsigned char *p = base + index * l->stride + a->offset;
    const struct vfmt *vf = &vfmts[a->format];
    int n = vf->n;
    switch (vf->type) {
    case VT_U8: for (int i = 0; i < n; i++) { iv[i] = p[i]; f[i] = vf->norm ? p[i] / 255.0f : p[i]; } break;
    case VT_S8: for (int i = 0; i < n; i++) {
            int v = (signed char)p[i];
            iv[i] = v;
            f[i] = vf->norm ? fmaxf(v / 127.0f, -1) : (float)v;
        }
        break;
    case VT_U16: for (int i = 0; i < n; i++) {
            uint16_t v;
            memcpy(&v, p + 2 * i, 2);
            iv[i] = v;
            f[i] = vf->norm ? v / 65535.0f : v;
        }
        break;
    case VT_S16: for (int i = 0; i < n; i++) {
            int16_t v;
            memcpy(&v, p + 2 * i, 2);
            iv[i] = v;
            f[i] = vf->norm ? fmaxf(v / 32767.0f, -1) : (float)v;
        }
        break;
    case VT_F16: for (int i = 0; i < n; i++) {
            uint16_t v;
            memcpy(&v, p + 2 * i, 2);
            f[i] = mtl_half_to_float(v);
            iv[i] = (int32_t)f[i];
        }
        break;
    case VT_F32: memcpy(f, p, 4 * (size_t)n); for (int i = 0; i < n; i++) iv[i] = (int32_t)f[i]; break;
    case VT_S32: case VT_U32:
        memcpy(iv, p, 4 * (size_t)n);
        for (int i = 0; i < n; i++) f[i] = vf->type == VT_S32 ? (float)iv[i] : (float)(uint32_t)iv[i];
        isint = 1;
        break;
    case VT_I1010102: {
        uint32_t w;
        memcpy(&w, p, 4);
        int c[4] = {(int)(w << 22) >> 22, (int)(w << 12) >> 22, (int)(w << 2) >> 22, (int)w >> 30};
        for (int i = 0; i < 3; i++) f[i] = fmaxf(c[i] / 511.0f, -1);
        f[3] = fmaxf((float)c[3], -1);
        break;
    }
    case VT_U1010102: {
        uint32_t w;
        memcpy(&w, p, 4);
        f[0] = (w & 1023) / 1023.0f; f[1] = ((w >> 10) & 1023) / 1023.0f; f[2] = ((w >> 20) & 1023) / 1023.0f;
        f[3] = (w >> 30) / 3.0f;
        break;
    }
    case VT_BGRA8: f[0] = p[2] / 255.0f; f[1] = p[1] / 255.0f; f[2] = p[0] / 255.0f; f[3] = p[3] / 255.0f; break;
    case VT_RG11B10: case VT_RGB9E5: {
        struct mtl_fmt tf = {0, 4, (unsigned char)(vf->type == VT_RG11B10 ? FK_RG11B10F : FK_RGB9E5), 3, 0, 0, 0, 0, 0, ""};
        mtl_texel_load(&tf, p, f);
        break;
    }
    }
    (void)isint;
done:
    if (want_int) memcpy(out4, iv, 16);
    else memcpy(out4, f, 16);
}

/* ---- vertices -------------------------------------------------------------------------- */
struct vshade {
    const struct mtl_draw_state *st;
    struct fetch_ctx fc;
    const unsigned *vids;   /* vertex ids to shade */
    unsigned n, iid;
    float *out;             /* n * vsize floats */
    int vsize;
};
#define VCHUNK 64
static void vshade_chunk(void *arg, size_t ci)
{
    const struct vshade *v = arg;
    const struct mtl_draw_state *st = v->st;
    struct ferry_call c;
    memset(&c, 0, sizeof c);
    memcpy(c.buffers, st->vb.buffers, sizeof c.buffers);
    memcpy(c.textures, st->vb.textures, sizeof c.textures);
    memcpy(c.samplers, st->vb.samplers, sizeof c.samplers);
    c.fetch_ctx = &v->fc;
    c.instance_id = v->iid;
    c.base_instance = v->fc.base_instance;
    unsigned lo = (unsigned)ci * VCHUNK, hi = lo + VCHUNK < v->n ? lo + VCHUNK : v->n;
    for (unsigned i = lo; i < hi; i++) {
        float *o = v->out + (size_t)i * (size_t)v->vsize;
        memset(o, 0, sizeof(float) * (size_t)v->vsize);
        o[FERRY_VS_POSITION + 3] = 1;
        o[FERRY_VS_POINT_SIZE] = 1;
        c.vertex_id = v->vids[i];
        st->p->vs->vs(&c, o);
    }
}

/* ---- primitives in window space -------------------------------------------------------- */
enum { PT_TRI, PT_POINT };
struct prim {
    int type;
    size_t v[3];            /* offsets of the window-space vertices in the arena */
    int front;
    unsigned prim_id;
    int bx0, by0, bx1, by1; /* pixel bounds, inclusive */
    float pc[3];            /* points: centre x, y and size */
    float zbias;
    int64_t A[3], B[3], C[3];
    int topleft[3];
    double inv_area;
    int line;
    unsigned layer, viewport;   /* what the provoking vertex chose */
    float zlo, zhi;             /* that viewport's depth range */
};
struct primlist {
    struct prim *p;
    size_t n, cap;
    float *arena;
    size_t used, acap;
    int vsize;
};
static size_t arena_put(struct primlist *L, const float *v)
{
    if (L->used + (size_t)L->vsize > L->acap) {
        L->acap = L->acap ? L->acap * 2 : 65536;
        while (L->used + (size_t)L->vsize > L->acap) L->acap *= 2;
        L->arena = realloc(L->arena, L->acap * sizeof(float));
    }
    memcpy(L->arena + L->used, v, sizeof(float) * (size_t)L->vsize);
    size_t at = L->used;
    L->used += (size_t)L->vsize;
    return at;
}
static struct prim *prim_new(struct primlist *L)
{
    if (L->n == L->cap) {
        L->cap = L->cap ? L->cap * 2 : 1024;
        L->p = realloc(L->p, L->cap * sizeof(struct prim));
    }
    struct prim *p = &L->p[L->n++];
    memset(p, 0, sizeof *p);
    return p;
}

struct setup {
    const struct mtl_target *rt;
    const struct mtl_draw_state *st;
    const struct mtl_rpipe *p;
    int vsize, nvary;
    double vx, vy, vw, vh, zn, zf;
    int sx0, sy0, sx1, sy1;         /* scissor and target bounds, exclusive ends */
    float rbias;                    /* the depth format's smallest step */
    struct primlist L;
    unsigned layer, viewport;       /* of the primitive being set up */
};

/* The viewport and layer a primitive's provoking vertex chose; the
 * viewport's transform is used from here on. */
static void pick_viewport(struct setup *S, const float *prov)
{
    S->layer = S->p->writes_layer ? __builtin_bit_cast(unsigned, prov[FERRY_VS_LAYER]) : 0;
    unsigned vi = S->p->writes_viewport ? __builtin_bit_cast(unsigned, prov[FERRY_VS_VIEWPORT]) : 0;
    if (vi >= S->st->nvp) vi = 0;
    S->viewport = vi;
    const double *v = vi ? S->st->vpx[vi - 1] : S->st->vp;
    S->vx = v[0]; S->vy = v[1]; S->vw = v[2]; S->vh = v[3]; S->zn = v[4]; S->zf = v[5];
}

/* Clip-space vertex to window space: x, y, z, 1/w and the varyings ready
 * for screen-space interpolation (perspective ones divided by w). */
static void to_window(const struct setup *S, const float *cv, float *wv)
{
    float w = cv[3], iw = w != 0 ? 1.0f / w : 0;
    memcpy(wv, cv, sizeof(float) * (size_t)S->vsize);
    double nx = cv[0] * iw, ny = cv[1] * iw, nz = cv[2] * iw;
    wv[0] = (float)(S->vx + (nx + 1) * 0.5 * S->vw);
    wv[1] = (float)(S->vy + (1 - ny) * 0.5 * S->vh);
    wv[2] = (float)(S->zn + nz * (S->zf - S->zn));
    wv[3] = iw;
    for (int i = 0; i < S->nvary; i++)
        if (S->p->interp[i] == FERRY_I_PERSPECTIVE) wv[FERRY_VS_VARYINGS + i] *= iw;
}

static int clip_plane_count(const struct setup *S)
{
    return (S->st->clip_mode == 1 ? 4 : 6) + S->p->nclip + 1;
}
/* Signed distance to clip plane k; inside when >= 0. */
static float plane_dist(const struct setup *S, const float *v, int k)
{
    int base = S->st->clip_mode == 1 ? 4 : 6;
    switch (k) {
    case 0: return v[3] + v[0];
    case 1: return v[3] - v[0];
    case 2: return v[3] + v[1];
    case 3: return v[3] - v[1];
    }
    if (S->st->clip_mode != 1) {
        if (k == 4) return v[2];
        if (k == 5) return v[3] - v[2];
    }
    if (k < base + S->p->nclip) return v[FERRY_VS_CLIP + (k - base)];
    return v[3] - 1e-6f; /* w > 0 */
}

static void tri_setup(struct setup *S, const float *w0, const float *w1, const float *w2, unsigned prim_id, int line,
                      int forced_front)
{
    float area_w = (w1[0] - w0[0]) * (w2[1] - w0[1]) - (w1[1] - w0[1]) * (w2[0] - w0[0]);
    if (!(area_w != 0) || area_w != area_w) return;
    int front;
    if (forced_front >= 0) front = forced_front;
    else {
        float ccw = -area_w; /* counter-clockwise as seen, with y up */
        front = S->st->winding == 1 ? ccw > 0 : ccw < 0;
        if (S->st->cull == 1 && front) return;
        if (S->st->cull == 2 && !front) return;
    }
    struct prim *p = prim_new(&S->L);
    p->type = PT_TRI;
    p->zlo = (float)fmin(S->zn, S->zf);
    p->zhi = (float)fmax(S->zn, S->zf);
    p->front = front;
    p->layer = S->layer;
    p->viewport = S->viewport;
    p->prim_id = prim_id;
    p->line = line;
    p->v[0] = arena_put(&S->L, w0);
    p->v[1] = arena_put(&S->L, w1);
    p->v[2] = arena_put(&S->L, w2);
    const float *w[3] = {w0, w1, w2};
    int64_t X[3], Y[3];
    float minx = 1e30f, miny = 1e30f, maxx = -1e30f, maxy = -1e30f;
    for (int i = 0; i < 3; i++) {
        X[i] = (int64_t)llrintf(w[i][0] * 256.0f);
        Y[i] = (int64_t)llrintf(w[i][1] * 256.0f);
        minx = fminf(minx, w[i][0]); maxx = fmaxf(maxx, w[i][0]);
        miny = fminf(miny, w[i][1]); maxy = fmaxf(maxy, w[i][1]);
    }
    int64_t sum = (X[1] - X[0]) * (Y[2] - Y[0]) - (Y[1] - Y[0]) * (X[2] - X[0]);
    int64_t sgn = sum < 0 ? -1 : 1;
    if (sum == 0) { S->L.n--; return; }
    for (int i = 0; i < 3; i++) {
        int a = (i + 1) % 3, b = (i + 2) % 3;
        int64_t dx = X[b] - X[a], dy = Y[b] - Y[a];
        p->A[i] = -dy * sgn;
        p->B[i] = dx * sgn;
        p->C[i] = -(p->A[i] * X[a] + p->B[i] * Y[a]);
        int64_t ex = dx * sgn, ey = dy * sgn;
        p->topleft[i] = (ey == 0 && ex > 0) || ey < 0;
    }
    p->inv_area = 1.0 / (double)(sum * sgn);
    p->bx0 = (int)floorf(minx);
    p->by0 = (int)floorf(miny);
    p->bx1 = (int)ceilf(maxx);
    p->by1 = (int)ceilf(maxy);
    if (p->bx0 < S->sx0) p->bx0 = S->sx0;
    if (p->by0 < S->sy0) p->by0 = S->sy0;
    if (p->bx1 > S->sx1 - 1) p->bx1 = S->sx1 - 1;
    if (p->by1 > S->sy1 - 1) p->by1 = S->sy1 - 1;
    if (p->bx0 > p->bx1 || p->by0 > p->by1) { S->L.n--; return; }
    /* depth bias: constant plus slope */
    if (S->st->depth_bias != 0 || S->st->slope != 0) {
        double ia = 1.0 / area_w;
        double dzdx = ((w1[2] - w0[2]) * (w2[1] - w0[1]) - (w2[2] - w0[2]) * (w1[1] - w0[1])) * ia;
        double dzdy = ((w2[2] - w0[2]) * (w1[0] - w0[0]) - (w1[2] - w0[2]) * (w2[0] - w0[0])) * ia;
        double m = fmax(fabs(dzdx), fabs(dzdy));
        double b = S->st->depth_bias * S->rbias + S->st->slope * m;
        if (S->st->bias_clamp > 0 && b > S->st->bias_clamp) b = S->st->bias_clamp;
        if (S->st->bias_clamp < 0 && b < S->st->bias_clamp) b = S->st->bias_clamp;
        p->zbias = (float)b;
    }
}

static void lerpv(const struct setup *S, const float *a, const float *b, float t, float *o)
{
    for (int i = 0; i < S->vsize; i++) o[i] = a[i] + (b[i] - a[i]) * t;
}
static void fix_flat(const struct setup *S, float *v, const float *prov)
{
    for (int i = 0; i < S->nvary; i++)
        if (S->p->interp[i] == FERRY_I_FLAT)
            v[FERRY_VS_VARYINGS + i] = prov[FERRY_VS_VARYINGS + i];
}

static void emit_tri_clipped(struct setup *S, const float *a, const float *b, const float *c, unsigned prim_id)
{
    pick_viewport(S, a);
    int np = clip_plane_count(S);
    int all_in = 1;
    const float *in3[3] = {a, b, c};
    for (int k = 0; k < np && all_in; k++)
        for (int i = 0; i < 3; i++)
            if (!(plane_dist(S, in3[i], k) >= 0)) { all_in = 0; break; }
    float wv[3][MAXV];
    if (all_in) {
        to_window(S, a, wv[0]);
        to_window(S, b, wv[1]);
        to_window(S, c, wv[2]);
        tri_setup(S, wv[0], wv[1], wv[2], prim_id, 0, -1);
        return;
    }
    /* Sutherland-Hodgman */
    enum { MAXP = 24 };
    static __thread float (*buf)[2][MAXP][MAXV];
    if (!buf) buf = malloc(sizeof *buf);
    float (*cur)[MAXV] = (*buf)[0], (*nxt)[MAXV] = (*buf)[1];
    int n = 3;
    memcpy(cur[0], a, sizeof(float) * (size_t)S->vsize);
    memcpy(cur[1], b, sizeof(float) * (size_t)S->vsize);
    memcpy(cur[2], c, sizeof(float) * (size_t)S->vsize);
    for (int k = 0; k < np && n >= 3; k++) {
        int m = 0;
        for (int i = 0; i < n; i++) {
            const float *p = cur[i], *q = cur[(i + 1) % n];
            float dp = plane_dist(S, p, k), dq = plane_dist(S, q, k);
            if (dp >= 0 && m < MAXP) memcpy(nxt[m++], p, sizeof(float) * (size_t)S->vsize);
            if ((dp >= 0) != (dq >= 0) && m < MAXP) {
                float t = dp / (dp - dq);
                lerpv(S, p, q, t, nxt[m]);
                fix_flat(S, nxt[m], a);
                m++;
            }
        }
        float (*t)[MAXV] = cur;
        cur = nxt;
        nxt = t;
        n = m;
    }
    if (n < 3) return;
    /* keep the provoking (first) vertex's flat values */
    for (int i = 0; i < n; i++) fix_flat(S, cur[i], a);
    to_window(S, cur[0], wv[0]);
    for (int i = 1; i + 1 < n; i++) {
        to_window(S, cur[i], wv[1]);
        to_window(S, cur[i + 1], wv[2]);
        tri_setup(S, wv[0], wv[1], wv[2], prim_id, 0, -1);
    }
}

/* A line, one pixel wide: clipped, then drawn as a thin quad of two
 * triangles widened across its major axis. */
static void emit_line(struct setup *S, const float *a, const float *b, unsigned prim_id)
{
    pick_viewport(S, a);
    float t0 = 0, t1 = 1;
    int np = clip_plane_count(S);
    for (int k = 0; k < np; k++) {
        float da = plane_dist(S, a, k), db = plane_dist(S, b, k);
        if (da < 0 && db < 0) return;
        if (da < 0) t0 = fmaxf(t0, da / (da - db));
        else if (db < 0) t1 = fminf(t1, da / (da - db));
    }
    if (t0 > t1) return;
    float ca[MAXV], cb[MAXV], wa[MAXV], wb[MAXV];
    lerpv(S, a, b, t0, ca);
    lerpv(S, a, b, t1, cb);
    fix_flat(S, ca, a);
    fix_flat(S, cb, a);
    to_window(S, ca, wa);
    to_window(S, cb, wb);
    float dx = wb[0] - wa[0], dy = wb[1] - wa[1];
    float q[4][MAXV];
    memcpy(q[0], wa, sizeof(float) * (size_t)S->vsize);
    memcpy(q[1], wa, sizeof(float) * (size_t)S->vsize);
    memcpy(q[2], wb, sizeof(float) * (size_t)S->vsize);
    memcpy(q[3], wb, sizeof(float) * (size_t)S->vsize);
    if (fabsf(dx) >= fabsf(dy)) {
        q[0][1] -= 0.5f; q[1][1] += 0.5f; q[2][1] += 0.5f; q[3][1] -= 0.5f;
    } else {
        q[0][0] -= 0.5f; q[1][0] += 0.5f; q[2][0] += 0.5f; q[3][0] -= 0.5f;
    }
    tri_setup(S, q[0], q[1], q[2], prim_id, 1, 1);
    tri_setup(S, q[0], q[2], q[3], prim_id, 1, 1);
}

static void emit_point(struct setup *S, const float *a, unsigned prim_id)
{
    pick_viewport(S, a);
    for (int k = 0; k < clip_plane_count(S); k++)
        if (!(plane_dist(S, a, k) >= 0)) return;
    float w[MAXV];
    to_window(S, a, w);
    float size = S->p->has_point_size ? a[FERRY_VS_POINT_SIZE] : 1;
    if (!(size > 0)) size = 1;
    if (size > 511) size = 511;
    struct prim *p = prim_new(&S->L);
    p->type = PT_POINT;
    p->zlo = (float)fmin(S->zn, S->zf);
    p->zhi = (float)fmax(S->zn, S->zf);
    p->front = 1;
    p->layer = S->layer;
    p->viewport = S->viewport;
    p->prim_id = prim_id;
    p->v[0] = arena_put(&S->L, w);
    p->pc[0] = w[0];
    p->pc[1] = w[1];
    p->pc[2] = size;
    float h = size * 0.5f;
    p->bx0 = (int)floorf(w[0] - h + 0.5f);
    p->by0 = (int)floorf(w[1] - h + 0.5f);
    p->bx1 = (int)ceilf(w[0] + h - 0.5f);
    p->by1 = (int)ceilf(w[1] + h - 0.5f);
    if (p->bx0 < S->sx0) p->bx0 = S->sx0;
    if (p->by0 < S->sy0) p->by0 = S->sy0;
    if (p->bx1 > S->sx1 - 1) p->bx1 = S->sx1 - 1;
    if (p->by1 > S->sy1 - 1) p->by1 = S->sy1 - 1;
    if (p->bx0 > p->bx1 || p->by0 > p->by1) S->L.n--;
}

/* ---- fragments ---------------------------------------------------------------------------- */
struct tile {
    const struct setup *S;
    struct ferry_call c;
    float in[4][MAXV];
    float out[4][FSOUT];
    int px[4], py[4];
    float pos[4][4];
    float pcoord[4][2];
    unsigned front, prim_id, layer, viewport;
    float zlo, zhi;                 /* the primitive's viewport's depth range */
    uint64_t visible;
};
static void frag_lane(void *arg, int lane)
{
    struct tile *T = arg;
    struct ferry_call *c = &T->c;
    memcpy(c->position, T->pos[lane], sizeof c->position);
    c->point_coord[0] = T->pcoord[lane][0];
    c->point_coord[1] = T->pcoord[lane][1];
    c->front_facing = T->front;
    c->primitive_id = T->prim_id;
    c->render_target_array_index = T->layer;
    c->viewport_array_index = T->viewport;
    c->sample_mask_in = 1;
    T->out[lane][FERRY_FS_SAMPLE_MASK] = __builtin_bit_cast(float, 0xffffffffu);
    T->S->p->fs->fs(c, T->in[lane], T->out[lane]);
}

static inline int stencil_byte(const struct mtl_fmt *f)
{
    switch (f->kind) {
    case FK_S8: return 0;
    case FK_D24S8: case FK_X24S8: return 3;
    case FK_D32FS8: case FK_X32S8: return 4;
    }
    return -1;
}
static inline unsigned char *att_texel(const struct mtl_attachment *a, int x, int y)
{
    const struct __ferry_tex *t = a->tex;
    unsigned z = 0, layer = a->slice;
    if (t->type == 7) { z = a->slice; layer = 0; }
    return (unsigned char *)mtl_texel(t, (unsigned)x, (unsigned)y, z, layer, a->level);
}
static int cmp(int f, float a, float b)
{
    switch (f) {
    case 0: return 0;
    case 1: return a < b;
    case 2: return a == b;
    case 3: return a <= b;
    case 4: return a > b;
    case 5: return a != b;
    case 6: return a >= b;
    default: return 1;
    }
}
static int cmpu(int f, uint32_t a, uint32_t b)
{
    switch (f) {
    case 0: return 0;
    case 1: return a < b;
    case 2: return a == b;
    case 3: return a <= b;
    case 4: return a > b;
    case 5: return a != b;
    case 6: return a >= b;
    default: return 1;
    }
}
static uint32_t stencil_op(int op, uint32_t s, uint32_t ref)
{
    switch (op) {
    case 1: return 0;
    case 2: return ref & 0xff;
    case 3: return s < 255 ? s + 1 : 255;
    case 4: return s > 0 ? s - 1 : 0;
    case 5: return ~s & 0xff;
    case 6: return (s + 1) & 0xff;
    case 7: return (s - 1) & 0xff;
    default: return s;
    }
}
static float blend_factor(int f, int ch, const float *s, const float *s1, const float *d, const float *bc)
{
    switch (f) {
    case 0: return 0;
    case 1: return 1;
    case 2: return s[ch];
    case 3: return 1 - s[ch];
    case 4: return s[3];
    case 5: return 1 - s[3];
    case 6: return d[ch];
    case 7: return 1 - d[ch];
    case 8: return d[3];
    case 9: return 1 - d[3];
    case 10: return ch == 3 ? 1 : fminf(s[3], 1 - d[3]);
    case 11: return bc[ch];
    case 12: return 1 - bc[ch];
    case 13: return bc[3];
    case 14: return 1 - bc[3];
    case 15: return s1[ch];
    case 16: return 1 - s1[ch];
    case 17: return s1[3];
    case 18: return 1 - s1[3];
    }
    return 1;
}
static float blend_op(int op, float a, float b)
{
    switch (op) {
    case 1: return a - b;
    case 2: return b - a;
    case 3: return fminf(a, b);
    case 4: return fmaxf(a, b);
    default: return a + b;
    }
}

/* The depth and stencil tests and the color writes of one fragment. */
static int fragment_out(struct tile *T, int lane, float z, int shaded)
{
    const struct setup *S = T->S;
    const struct mtl_draw_state *st = S->st;
    const struct mtl_target *rt = S->rt;
    const struct mtl_rpipe *p = S->p;
    int x = T->px[lane], y = T->py[lane];
    const float *o = T->out[lane];
    if (shaded) {
        if (mtl_lane_discarded(lane)) return 0;
        if (p->writes_mask && !(__builtin_bit_cast(uint32_t, o[FERRY_FS_SAMPLE_MASK]) & 1)) return 0;
        if (p->alpha_to_coverage && p->color_kind[0] >= 0 && o[3] < 0.5f) return 0;
        if (p->writes_depth) z = o[FERRY_FS_DEPTH];
    }
    if (z < T->zlo) z = T->zlo;
    if (z > T->zhi) z = T->zhi;
    const struct mtl_dsstate *ds = st->ds;
    const struct mtl_stencil_face *sf = ds ? (T->front ? &ds->front : &ds->back) : NULL;
    uint32_t ref = T->front ? st->stencil_ref_front : st->stencil_ref_back;
    if (shaded && p->writes_stencil) ref = __builtin_bit_cast(uint32_t, o[FERRY_FS_STENCIL]) & 0xff;
    unsigned char *sp = NULL;
    uint32_t sval = 0;
    int sb = -1;
    if (ds && ds->stencil_enabled && rt->stencil.tex) {
        sb = stencil_byte(rt->stencil.tex->f);
        if (sb >= 0) {
            sp = att_texel(&rt->stencil, x, y) + sb;
            sval = *sp;
        }
    }
    if (sp) {
        if (!cmpu(sf->func, ref & sf->read_mask, sval & sf->read_mask)) {
            uint32_t nv = stencil_op(sf->fail, sval, ref);
            *sp = (unsigned char)((sval & ~sf->write_mask) | (nv & sf->write_mask));
            return 0;
        }
    }
    if (ds && rt->depth.tex && rt->depth.tex->f->depth) {
        unsigned char *dp = att_texel(&rt->depth, x, y);
        float dv[4];
        mtl_texel_load(rt->depth.tex->f, dp, dv);
        if (!cmp(ds->depth_func, z, dv[0])) {
            if (sp) {
                uint32_t nv = stencil_op(sf->zfail, sval, ref);
                *sp = (unsigned char)((sval & ~sf->write_mask) | (nv & sf->write_mask));
            }
            return 0;
        }
        if (ds->depth_write) {
            float w4[4] = {z, 0, 0, 0};
            mtl_texel_store(rt->depth.tex->f, dp, w4);
        }
    }
    if (sp) {
        uint32_t nv = stencil_op(sf->pass, sval, ref);
        *sp = (unsigned char)((sval & ~sf->write_mask) | (nv & sf->write_mask));
    }
    T->visible++;
    if (!shaded) return 1;
    for (int i = 0; i < 8; i++) {
        const struct mtl_attachment *a = &rt->color[i];
        if (!a->tex || p->color_kind[i] < 0) continue;
        const struct mtl_blend *b = &p->blend[i];
        if (!b->write_mask) continue;
        const struct mtl_fmt *f = a->tex->f;
        unsigned char *cp = att_texel(a, x, y);
        float s[4], d[4], r[4];
        memcpy(s, o + 4 * i, 16);
        if (f->is_int) {
            if (b->write_mask != 15) {
                mtl_texel_load(f, cp, d);
                static const int bit[4] = {8, 4, 2, 1};
                for (int k = 0; k < 4; k++) if (!(b->write_mask & bit[k])) s[k] = d[k];
            }
            mtl_texel_store(f, cp, s);
            continue;
        }
        int need_dst = b->enabled || b->write_mask != 15;
        if (need_dst) mtl_texel_load(f, cp, d);
        if (b->enabled) {
            const float *s1 = o + FERRY_FS_RESULTS;
            int clamp01 = !(f->kind == FK_F16 || f->kind == FK_F32 || f->kind == FK_RG11B10F || f->kind == FK_RGB9E5 ||
                            f->kind == FK_BGR10XR || f->kind == FK_BGRA10XR);
            if (clamp01)
                for (int k = 0; k < 4; k++) s[k] = fminf(fmaxf(s[k], f->kind == FK_SN8 || f->kind == FK_SN16 ? -1 : 0), 1);
            for (int k = 0; k < 4; k++) {
                int sfac = k < 3 ? b->src_rgb : b->src_a, dfac = k < 3 ? b->dst_rgb : b->dst_a;
                int op = k < 3 ? b->op_rgb : b->op_a;
                float fs = blend_factor(sfac, k, s, s1, d, st->blend_color);
                float fd = blend_factor(dfac, k, s, s1, d, st->blend_color);
                if (op == 3 || op == 4) r[k] = blend_op(op, s[k], d[k]);
                else r[k] = blend_op(op, s[k] * fs, d[k] * fd);
            }
        } else memcpy(r, s, 16);
        if (b->write_mask != 15) {
            static const int bit[4] = {8, 4, 2, 1};
            for (int k = 0; k < 4; k++) if (!(b->write_mask & bit[k])) r[k] = d[k];
        }
        mtl_texel_store(f, cp, r);
    }
    return 1;
}

struct raster {
    struct setup *S;
    int tiles_x, tiles_y;
    uint64_t visible;
};

static void interp_lane(struct tile *T, const struct prim *pr, int lane, double b0, double b1, double b2)
{
    const struct setup *S = T->S;
    const float *v0 = S->L.arena + pr->v[0], *v1 = S->L.arena + pr->v[1], *v2 = S->L.arena + pr->v[2];
    float *in = T->in[lane];
    double iw = b0 * v0[3] + b1 * v1[3] + b2 * v2[3];
    double rw = iw != 0 ? 1.0 / iw : 0;
    float z = (float)(b0 * v0[2] + b1 * v1[2] + b2 * v2[2]) + pr->zbias;
    T->pos[lane][0] = (float)T->px[lane] + 0.5f;
    T->pos[lane][1] = (float)T->py[lane] + 0.5f;
    T->pos[lane][2] = z;
    T->pos[lane][3] = (float)iw;
    for (int i = 0; i < S->nvary; i++) {
        int k = FERRY_VS_VARYINGS + i;
        switch (S->p->interp[i]) {
        case FERRY_I_FLAT: in[k] = v0[k]; break;
        case FERRY_I_NO_PERSPECTIVE: in[k] = (float)(b0 * v0[k] + b1 * v1[k] + b2 * v2[k]); break;
        default: in[k] = (float)((b0 * v0[k] + b1 * v1[k] + b2 * v2[k]) * rw); break;
        }
    }
}

static void raster_tile(void *arg, size_t ti)
{
    struct raster *R = arg;
    struct setup *S = R->S;
    const struct mtl_draw_state *st = S->st;
    const struct mtl_rpipe *p = S->p;
    int tx = (int)(ti % (size_t)R->tiles_x), ty = (int)(ti / (size_t)R->tiles_x);
    int x0 = S->sx0 + tx * TILE, y0 = S->sy0 + ty * TILE;
    /* quads are aligned to even pixels */
    int qx0 = x0 & ~1, qy0 = y0 & ~1;
    int x1 = x0 + TILE - 1, y1 = y0 + TILE - 1;
    if (x1 > S->sx1 - 1) x1 = S->sx1 - 1;
    if (y1 > S->sy1 - 1) y1 = S->sy1 - 1;
    struct tile *T = malloc(sizeof *T);
    if (!T) return;
    T->S = S;
    T->visible = 0;
    memset(&T->c, 0, sizeof T->c);
    memcpy(T->c.buffers, st->fb.buffers, sizeof T->c.buffers);
    memcpy(T->c.textures, st->fb.textures, sizeof T->c.textures);
    memcpy(T->c.samplers, st->fb.samplers, sizeof T->c.samplers);
    for (int i = 0; i < 64; i++) T->c.stage_in_map[i] = (unsigned)p->stage_in_map[i];
    int early = !p->writes_depth && !(st->ds && st->ds->stencil_enabled);
    for (size_t pi = 0; pi < S->L.n; pi++) {
        const struct prim *pr = &S->L.p[pi];
        int bx0 = pr->bx0 > x0 ? pr->bx0 : x0, by0 = pr->by0 > y0 ? pr->by0 : y0;
        int bx1 = pr->bx1 < x1 ? pr->bx1 : x1, by1 = pr->by1 < y1 ? pr->by1 : y1;
        if (bx0 > bx1 || by0 > by1) continue;
        T->front = (unsigned)pr->front;
        T->prim_id = pr->prim_id;
        T->layer = pr->layer;
        T->viewport = pr->viewport;
        T->zlo = pr->zlo;
        T->zhi = pr->zhi;
        int sx = bx0 & ~1, sy = by0 & ~1;
        if (sx < qx0) sx = qx0;
        if (sy < qy0) sy = qy0;
        for (int qy = sy; qy <= by1; qy += 2)
            for (int qx = sx; qx <= bx1; qx += 2) {
                int cover = 0;
                double bc[4][3];
                for (int l = 0; l < 4; l++) {
                    int x = qx + (l & 1), y = qy + (l >> 1);
                    T->px[l] = x;
                    T->py[l] = y;
                    if (pr->type == PT_POINT) {
                        float cx = pr->pc[0], cy = pr->pc[1], s = pr->pc[2];
                        float fx = (float)x + 0.5f, fy = (float)y + 0.5f;
                        T->pcoord[l][0] = (fx - cx) / s + 0.5f;
                        T->pcoord[l][1] = (fy - cy) / s + 0.5f;
                        int in = T->pcoord[l][0] >= 0 && T->pcoord[l][0] < 1 && T->pcoord[l][1] >= 0 &&
                                 T->pcoord[l][1] < 1;
                        bc[l][0] = 1; bc[l][1] = bc[l][2] = 0;
                        if (in && x >= bx0 && x <= bx1 && y >= by0 && y <= by1) cover |= 1 << l;
                        continue;
                    }
                    T->pcoord[l][0] = T->pcoord[l][1] = 0;
                    int64_t px = (int64_t)x * 256 + 128, py = (int64_t)y * 256 + 128;
                    int64_t e[3];
                    int in = 1;
                    for (int k = 0; k < 3; k++) {
                        e[k] = pr->A[k] * px + pr->B[k] * py + pr->C[k];
                        if (e[k] < 0 || (e[k] == 0 && !pr->topleft[k])) in = 0;
                    }
                    for (int k = 0; k < 3; k++) bc[l][k] = (double)e[k] * pr->inv_area;
                    if (in && x >= bx0 && x <= bx1 && y >= by0 && y <= by1) cover |= 1 << l;
                }
                if (!cover) continue;
                for (int l = 0; l < 4; l++) {
                    if (pr->type == PT_POINT) {
                        const float *v0 = S->L.arena + pr->v[0];
                        memcpy(T->in[l] + FERRY_VS_VARYINGS, v0 + FERRY_VS_VARYINGS, sizeof(float) * (size_t)S->nvary);
                        for (int i = 0; i < S->nvary; i++)
                            if (p->interp[i] == FERRY_I_PERSPECTIVE) T->in[l][FERRY_VS_VARYINGS + i] /= v0[3] ? v0[3] : 1;
                        T->pos[l][0] = (float)T->px[l] + 0.5f;
                        T->pos[l][1] = (float)T->py[l] + 0.5f;
                        T->pos[l][2] = v0[2];
                        T->pos[l][3] = v0[3];
                    } else
                        interp_lane(T, pr, l, bc[l][0], bc[l][1], bc[l][2]);
                }
                if (early && st->ds && S->rt->depth.tex && S->rt->depth.tex->f->depth) {
                    for (int l = 0; l < 4; l++) {
                        if (!(cover & (1 << l))) continue;
                        float dv[4], z = T->pos[l][2];
                        if (z < T->zlo) z = T->zlo;
                        if (z > T->zhi) z = T->zhi;
                        mtl_texel_load(S->rt->depth.tex->f, att_texel(&S->rt->depth, T->px[l], T->py[l]), dv);
                        if (!cmp(st->ds->depth_func, z, dv[0])) cover &= ~(1 << l);
                    }
                    if (!cover) continue;
                }
                int shaded = p->fs != NULL;
                if (shaded) mtl_run_lanes(1, 4, frag_lane, T);
                for (int l = 0; l < 4; l++)
                    if (cover & (1 << l)) fragment_out(T, l, T->pos[l][2], shaded);
            }
    }
    if (T->visible) __atomic_fetch_add(&R->visible, T->visible, __ATOMIC_RELAXED);
    free(T);
}

static float depth_step(const struct mtl_target *rt)
{
    if (!rt->depth.tex) return 1.0f / 16777216.0f;
    switch (rt->depth.tex->f->kind) {
    case FK_D16: return 1.0f / 65536.0f;
    case FK_D24S8: return 1.0f / 16777216.0f;
    default: return 1.0f / 8388608.0f;
    }
}

/* ---- a draw ------------------------------------------------------------------------------- */
static unsigned index_at(const struct mtl_draw *d, unsigned i)
{
    if (d->index_size == 2) return ((const uint16_t *)d->indices)[i];
    return ((const uint32_t *)d->indices)[i];
}

static void rasterize(struct setup *S, const struct mtl_draw_state *st)
{
    if (!S->L.n) return;
    struct raster R = {S, 0, 0, 0};
    int w = S->sx1 - S->sx0, h = S->sy1 - S->sy0;
    if (w <= 0 || h <= 0) return;
    R.tiles_x = (w + TILE - 1) / TILE;
    R.tiles_y = (h + TILE - 1) / TILE;
    size_t nt = (size_t)R.tiles_x * (size_t)R.tiles_y;
    if (nt == 1 || S->L.n < 4) for (size_t i = 0; i < nt; i++) raster_tile(&R, i);
    else dispatch_apply_f(nt, workers(), &R, raster_tile);
    if (st->vis_counter && st->vis_mode) {
        if (st->vis_mode == 1) { if (R.visible) *st->vis_counter = 1; }
        else *st->vis_counter += R.visible;
    }
    S->L.n = 0;
    S->L.used = 0;
}

void mtl_execute_draw(const struct mtl_target *rt, const struct mtl_draw_state *st, const struct mtl_draw *d)
{
    const struct mtl_rpipe *p = st->p;
    if (!p || !p->vs || !p->vs->vs || !d->count || !d->instances) return;
    struct setup S;
    memset(&S, 0, sizeof S);
    S.rt = rt;
    S.st = st;
    S.p = p;
    S.vsize = p->vsize < FERRY_VS_VARYINGS ? FERRY_VS_VARYINGS : p->vsize;
    if (S.vsize > MAXV) S.vsize = MAXV;
    S.nvary = S.vsize - FERRY_VS_VARYINGS;
    S.L.vsize = S.vsize;
    S.vx = st->vp[0]; S.vy = st->vp[1]; S.vw = st->vp[2]; S.vh = st->vp[3]; S.zn = st->vp[4]; S.zf = st->vp[5];
    S.sx0 = st->scissor[0];
    S.sy0 = st->scissor[1];
    S.sx1 = st->scissor[0] + st->scissor[2];
    S.sy1 = st->scissor[1] + st->scissor[3];
    if (S.sx0 < 0) S.sx0 = 0;
    if (S.sy0 < 0) S.sy0 = 0;
    if (S.sx1 > (int)rt->width) S.sx1 = (int)rt->width;
    if (S.sy1 > (int)rt->height) S.sy1 = (int)rt->height;
    S.rbias = depth_step(rt);

    /* which vertices to shade, and where each element's result is */
    unsigned n = d->count;
    unsigned *slot = malloc(sizeof(unsigned) * n);
    unsigned *vids;
    unsigned nshade;
    const unsigned RESTART = 0xffffffffu;
    int strip = d->prim == 2 || d->prim == 4;
    if (!d->indices) {
        nshade = n;
        vids = malloc(sizeof(unsigned) * n);
        for (unsigned i = 0; i < n; i++) { vids[i] = d->first + i; slot[i] = i; }
    } else {
        unsigned restart_val = d->index_size == 2 ? 0xffffu : 0xffffffffu;
        unsigned mn = 0xffffffffu, mx = 0;
        for (unsigned i = 0; i < n; i++) {
            unsigned ix = index_at(d, d->first + i);
            if (ix == restart_val) continue;
            if (ix < mn) mn = ix;
            if (ix > mx) mx = ix;
        }
        if (mn > mx) { free(slot); return; }
        if ((uint64_t)(mx - mn) + 1 <= (uint64_t)n * 2 + 1024) {
            nshade = mx - mn + 1;
            vids = malloc(sizeof(unsigned) * nshade);
            for (unsigned i = 0; i < nshade; i++) vids[i] = (unsigned)((int)(mn + i) + d->base_vertex);
            for (unsigned i = 0; i < n; i++) {
                unsigned ix = index_at(d, d->first + i);
                slot[i] = ix == restart_val ? RESTART : ix - mn;
            }
        } else {
            nshade = n;
            vids = malloc(sizeof(unsigned) * n);
            for (unsigned i = 0; i < n; i++) {
                unsigned ix = index_at(d, d->first + i);
                vids[i] = (unsigned)((int)ix + d->base_vertex);
                slot[i] = ix == restart_val ? RESTART : i;
            }
        }
    }
    (void)strip;
    float *vout = malloc(sizeof(float) * (size_t)nshade * (size_t)S.vsize);
    if (!vout || !vids) { free(vout); free(vids); free(slot); return; }
    /* buffer strides set when binding (Metal 3's attributeStride:) over the pipeline's */
    struct mtl_vdesc vd_dyn;
    const struct mtl_vdesc *vd = &p->vd;
    if (st->vstride_set) {
        vd_dyn = p->vd;
        for (int b = 0; b < 31; b++)
            if (st->vstride_set & (1u << b)) vd_dyn.layout[b].stride = st->vstride[b];
        vd = &vd_dyn;
    }
    struct vshade V = {st, {vd, st->vb.buffers, d->base_instance}, vids, nshade, 0, vout, S.vsize};
    size_t nchunks = (nshade + VCHUNK - 1) / VCHUNK;
    int fill_lines = st->fill == 1;
    for (unsigned inst = 0; inst < d->instances; inst++) {
        V.iid = d->base_instance + inst;
        if (nchunks > 1) dispatch_apply_f(nchunks, workers(), &V, vshade_chunk);
        else vshade_chunk(&V, 0);
        if (!p->raster_enabled) continue;
#define VERT(i) (vout + (size_t)slot[i] * (size_t)S.vsize)
        unsigned pid = 0;
        switch (d->prim) {
        case 0: /* points */
            for (unsigned i = 0; i < n; i++, pid++)
                if (slot[i] != RESTART) emit_point(&S, VERT(i), pid);
            break;
        case 1: /* lines */
            for (unsigned i = 0; i + 1 < n; i += 2, pid++)
                if (slot[i] != RESTART && slot[i + 1] != RESTART) emit_line(&S, VERT(i), VERT(i + 1), pid);
            break;
        case 2: { /* line strip */
            unsigned run = 0;
            for (unsigned i = 0; i < n; i++) {
                if (slot[i] == RESTART) { run = 0; continue; }
                if (run++ > 0) emit_line(&S, VERT(i - 1), VERT(i), pid++);
            }
            break;
        }
        case 3: /* triangles */
            for (unsigned i = 0; i + 2 < n; i += 3, pid++) {
                if (slot[i] == RESTART || slot[i + 1] == RESTART || slot[i + 2] == RESTART) continue;
                if (fill_lines) {
                    emit_line(&S, VERT(i), VERT(i + 1), pid);
                    emit_line(&S, VERT(i + 1), VERT(i + 2), pid);
                    emit_line(&S, VERT(i + 2), VERT(i), pid);
                } else
                    emit_tri_clipped(&S, VERT(i), VERT(i + 1), VERT(i + 2), pid);
            }
            break;
        case 4: { /* triangle strip */
            unsigned run = 0;
            for (unsigned i = 0; i < n; i++) {
                if (slot[i] == RESTART) { run = 0; continue; }
                run++;
                if (run < 3) continue;
                const float *a = VERT(i - 2), *b = VERT(i - 1), *c = VERT(i);
                /* every other triangle is reversed to keep the winding */
                if (!(run & 1)) { const float *t = a; a = b; b = t; }
                if (fill_lines) {
                    emit_line(&S, a, b, pid);
                    emit_line(&S, b, c, pid);
                    emit_line(&S, c, a, pid);
                } else
                    emit_tri_clipped(&S, a, b, c, pid);
                pid++;
            }
            break;
        }
        }
#undef VERT
        if (S.L.used > ((size_t)16 << 20)) rasterize(&S, st);
    }
    rasterize(&S, st);
    free(S.L.p);
    free(S.L.arena);
    free(vout);
    free(vids);
    free(slot);
}

/* ---- clears ------------------------------------------------------------------------------- */
void mtl_clear_attachment(const struct mtl_attachment *a, const double rgba[4], int what, double depth, uint32_t stencil)
{
    const struct __ferry_tex *t = a->tex;
    if (!t || a->level >= t->levels) return;
    unsigned w = t->lw[a->level], h = t->lh[a->level];
    const struct mtl_fmt *f = t->f;
    unsigned char texel[16];
    float v[4] = {0, 0, 0, 0};
    if (what == 0) {
        for (int i = 0; i < 4; i++) v[i] = (float)rgba[i];
        if (f->is_int)
            for (int i = 0; i < 4; i++) {
                int32_t iv = (int32_t)rgba[i];
                memcpy(&v[i], &iv, 4);
            }
    } else if (what == 1) v[0] = (float)depth;
    if (what == 2) {
        int sb = stencil_byte(f);
        if (sb < 0) return;
        for (unsigned y = 0; y < h; y++)
            for (unsigned x = 0; x < w; x++) att_texel(a, (int)x, (int)y)[sb] = (unsigned char)stencil;
        return;
    }
    if (what == 1 && !f->depth) return;
    /* build one texel, then copy it along the first row and the row down */
    memset(texel, 0, sizeof texel);
    if (what == 1 && f->stencil) {
        /* keep the stencil bytes: write texel by texel */
        for (unsigned y = 0; y < h; y++)
            for (unsigned x = 0; x < w; x++) mtl_texel_store(f, att_texel(a, (int)x, (int)y), v);
        return;
    }
    mtl_texel_store(f, texel, v);
    unsigned bpp = f->bpp;
    unsigned char *row0 = att_texel(a, 0, 0);
    for (unsigned x = 0; x < w; x++) memcpy(row0 + (size_t)x * bpp, texel, bpp);
    for (unsigned y = 1; y < h; y++) memcpy(att_texel(a, 0, (int)y), row0, (size_t)w * bpp);
}

/* ---- compute ------------------------------------------------------------------------------- */
struct cgroup {
    const struct mtl_dispatch *d;
    struct ferry_call *c;
    unsigned g[3], tpg[3];
};
static void cs_lane(void *arg, int lane)
{
    struct cgroup *G = arg;
    struct ferry_call *c = G->c;
    unsigned tx = (unsigned)lane % G->tpg[0], ty = ((unsigned)lane / G->tpg[0]) % G->tpg[1],
             tz = (unsigned)lane / (G->tpg[0] * G->tpg[1]);
    const struct mtl_dispatch *d = G->d;
    c->grid[FERRY_G_THREAD_IN_GROUP][0] = tx;
    c->grid[FERRY_G_THREAD_IN_GROUP][1] = ty;
    c->grid[FERRY_G_THREAD_IN_GROUP][2] = tz;
    c->grid[FERRY_G_THREAD_POS][0] = G->g[0] * d->tpg[0] + tx;
    c->grid[FERRY_G_THREAD_POS][1] = G->g[1] * d->tpg[1] + ty;
    c->grid[FERRY_G_THREAD_POS][2] = G->g[2] * d->tpg[2] + tz;
    c->grid[FERRY_G_INDEX_IN_GROUP][0] = (unsigned)lane;
    d->fn->cs(c);
}
struct cjob {
    const struct mtl_dispatch *d;
    struct ferry_call tmpl;
    size_t ngroups;
};
static void cs_group(void *arg, size_t gi)
{
    struct cjob *J = arg;
    const struct mtl_dispatch *d = J->d;
    struct ferry_call *c = malloc(sizeof *c);
    if (!c) return;
    memcpy(c, &J->tmpl, sizeof *c);
    struct cgroup G;
    G.d = d;
    G.c = c;
    G.g[0] = (unsigned)(gi % d->groups[0]);
    G.g[1] = (unsigned)((gi / d->groups[0]) % d->groups[1]);
    G.g[2] = (unsigned)(gi / ((size_t)d->groups[0] * d->groups[1]));
    for (int k = 0; k < 3; k++) {
        G.tpg[k] = d->tpg[k];
        if (d->nonuniform) {
            unsigned start = G.g[k] * d->tpg[k];
            if (start + G.tpg[k] > d->grid[k]) G.tpg[k] = d->grid[k] > start ? d->grid[k] - start : 0;
        }
        c->grid[FERRY_G_THREADGROUP_POS][k] = G.g[k];
        c->grid[FERRY_G_THREADS_PER_GROUP][k] = G.tpg[k];
    }
    unsigned nthreads = G.tpg[0] * G.tpg[1] * G.tpg[2];
    c->grid[FERRY_G_INDEX_IN_GROUP][1] = nthreads;
    /* threadgroup memory set with setThreadgroupMemoryLength */
    static __thread void *tgbuf[16];
    static __thread size_t tgcap[16];
    for (int i = 0; i < 16; i++) {
        if (!d->tglen[i]) { c->tgmem[i] = NULL; continue; }
        if (tgcap[i] < d->tglen[i]) {
            free(tgbuf[i]);
            void *p = NULL;
            if (posix_memalign(&p, 64, d->tglen[i])) p = NULL;
            tgbuf[i] = p;
            tgcap[i] = p ? d->tglen[i] : 0;
        }
        if (tgbuf[i]) memset(tgbuf[i], 0, d->tglen[i]);
        c->tgmem[i] = tgbuf[i];
    }
    mtl_tg_reset();
    if (nthreads) mtl_run_lanes(2, (int)nthreads, cs_lane, &G);
    free(c);
}

void mtl_execute_dispatch(const struct mtl_dispatch *d)
{
    if (!d->fn || !d->fn->cs) return;
    if (!d->groups[0] || !d->groups[1] || !d->groups[2] || !d->tpg[0] || !d->tpg[1] || !d->tpg[2]) return;
    struct cjob *J = calloc(1, sizeof *J);
    if (!J) return;
    J->d = d;
    memcpy(J->tmpl.buffers, d->b.buffers, sizeof J->tmpl.buffers);
    memcpy(J->tmpl.textures, d->b.textures, sizeof J->tmpl.textures);
    memcpy(J->tmpl.samplers, d->b.samplers, sizeof J->tmpl.samplers);
    for (int k = 0; k < 3; k++) {
        J->tmpl.grid[FERRY_G_THREADS_PER_GRID][k] = d->nonuniform ? d->grid[k] : d->groups[k] * d->tpg[k];
        J->tmpl.grid[FERRY_G_THREADGROUPS_PER_GRID][k] = d->groups[k];
    }
    J->ngroups = (size_t)d->groups[0] * d->groups[1] * d->groups[2];
    if (J->ngroups == 1) cs_group(J, 0);
    else dispatch_apply_f(J->ngroups, workers(), J, cs_group);
    free(J);
}
