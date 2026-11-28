/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Compiled asset catalogues (freemac 1.271): reads a Mac app's Assets.car,
 * so that apps built with Xcode find their images, colours and data. Apple
 * doesn't publish the format; this follows third-party descriptions of it,
 * chiefly the MIT-licensed car-parser-deepmap2 crate (for the deepmap2
 * picture coding) and what the files themselves show. No Apple code was
 * read or run.
 *
 * A .car file is a "BOMStore": big-endian blocks, named trees among them.
 * FACETKEYS maps each asset's name to its identifier; RENDITIONS maps keys
 * (16-bit attribute values in the order KEYFORMAT gives) to renditions, each
 * a little-endian 'CTSI' header, tagged values and a body: 'CELM' pictures
 * (raw, LZFSE, LZVN or deepmap2-coded, whole or in 'KCBC' bands), 'COLR'
 * colours and 'RAWD' data. Small pictures are often packed into a shared
 * sheet, the rendition carrying only an 'INLK' link to its place there.
 *
 * Plain C, built with AppKit and on its own for tests.
 */
#include "AAssetCar.h"

#include <compression.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_ATTRS 32

/* rendition key attributes */
enum { ATTR_APPEARANCE = 7, ATTR_SCALE = 12, ATTR_IDENTIFIER = 17 };

struct facet {
    char *name;
    uint16_t identifier;
};

struct rendition {
    uint16_t key[MAX_ATTRS];
    const uint8_t *csi;
    uint32_t length;
};

struct atlas {
    int index;    /* the rendition it was decoded from */
    struct acar_bitmap bitmap;
};

struct acar {
    uint8_t *map;
    size_t size;
    uint32_t nblocks, index_offset;
    int nattrs, at_identifier, at_scale, at_appearance;
    uint32_t attrs[MAX_ATTRS];
    struct facet *facets;
    int nfacets;
    struct rendition *renditions;
    int nrenditions;
    uint16_t dark[8];    /* appearance numbers whose names say Dark */
    int ndark;
    struct atlas atlases[8];
    int natlases;
};

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return p[0] << 8 | p[1]; }
static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return p[0] | p[1] << 8; }

/* ---- the BOM store ------------------------------------------------------------------ */

static const uint8_t *block(struct acar *c, uint32_t i, uint32_t *len)
{
    if (i >= c->nblocks)
        return NULL;
    const uint8_t *e = c->map + c->index_offset + 4 + 8 * (size_t)i;
    uint32_t off = be32(e), n = be32(e + 4);
    if ((uint64_t)off + n > c->size)
        return NULL;
    if (len)
        *len = n;
    return c->map + off;
}

static uint32_t named_block(struct acar *c, const char *name)
{
    uint32_t vo = be32(c->map + 24), vl = be32(c->map + 28);
    if ((uint64_t)vo + vl > c->size || vl < 4)
        return 0;
    const uint8_t *p = c->map + vo, *end = p + vl;
    uint32_t count = be32(p);
    p += 4;
    for (uint32_t i = 0; i < count && p + 5 <= end; i++) {
        uint32_t idx = be32(p);
        uint8_t n = p[4];
        if (p + 5 + n > end)
            break;
        if (strlen(name) == n && !memcmp(p + 5, name, n))
            return idx;
        p += 5 + n;
    }
    return 0;
}

typedef void (*tree_fn)(struct acar *, const uint8_t *key, uint32_t klen, const uint8_t *value, uint32_t vlen, void *ctx);

/* Calls fn for each key and value of a named tree, in order. */
static void walk_tree(struct acar *c, const char *name, tree_fn fn, void *ctx)
{
    uint32_t len, idx = named_block(c, name);
    const uint8_t *t = idx ? block(c, idx, &len) : NULL;
    if (!t || len < 21 || memcmp(t, "tree", 4))
        return;
    uint32_t page = be32(t + 8);
    /* down the first branch to the leftmost leaf */
    for (int depth = 0; depth < 32; depth++) {
        const uint8_t *p = block(c, page, &len);
        if (!p || len < 12)
            return;
        if (be16(p))
            break;
        if (len < 16 || !be16(p + 2))
            return;
        page = be32(p + 12);
    }
    /* then along the leaves */
    for (int pages = 0; page && pages < 1000000; pages++) {
        const uint8_t *p = block(c, page, &len);
        if (!p || len < 12 || !be16(p))
            return;
        uint16_t count = be16(p + 2);
        if (12 + 8 * (size_t)count > len)
            return;
        for (uint16_t i = 0; i < count; i++) {
            uint32_t vlen, klen;
            const uint8_t *v = block(c, be32(p + 12 + 8 * i), &vlen), *k = block(c, be32(p + 16 + 8 * i), &klen);
            if (v && k)
                fn(c, k, klen, v, vlen, ctx);
        }
        page = be32(p + 4);
    }
}

static void add_facet(struct acar *c, const uint8_t *k, uint32_t klen, const uint8_t *v, uint32_t vlen, void *ctx)
{
    if (vlen < 6)
        return;
    uint16_t n = le16(v + 4);
    for (uint16_t i = 0; i < n && 10 + 4 * (size_t)i <= vlen; i++)
        if (le16(v + 6 + 4 * i) == ATTR_IDENTIFIER) {
            struct facet *f = realloc(c->facets, (c->nfacets + 1) * sizeof *f);
            if (!f)
                return;
            c->facets = f;
            f[c->nfacets].name = strndup((const char *)k, klen);
            f[c->nfacets].identifier = le16(v + 8 + 4 * i);
            c->nfacets++;
            return;
        }
}

static void add_rendition(struct acar *c, const uint8_t *k, uint32_t klen, const uint8_t *v, uint32_t vlen, void *ctx)
{
    if (klen < 2 * (uint32_t)c->nattrs || vlen < 184 || memcmp(v, "ISTC", 4))
        return;
    struct rendition *r = realloc(c->renditions, (c->nrenditions + 1) * sizeof *r);
    if (!r)
        return;
    c->renditions = r;
    r += c->nrenditions++;
    memset(r->key, 0, sizeof r->key);
    for (int i = 0; i < c->nattrs; i++)
        r->key[i] = le16(k + 2 * i);
    r->csi = v;
    r->length = vlen;
}

static void add_appearance(struct acar *c, const uint8_t *k, uint32_t klen, const uint8_t *v, uint32_t vlen, void *ctx)
{
    if (vlen >= 2 && c->ndark < 8 && memmem(k, klen, "Dark", 4))
        c->dark[c->ndark++] = le16(v);
}

struct acar *acar_open(const char *path)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return NULL;
    struct stat st;
    if (fstat(fd, &st) || st.st_size < 32) {
        close(fd);
        return NULL;
    }
    void *map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED)
        return NULL;
    struct acar *c = calloc(1, sizeof *c);
    if (!c) {
        munmap(map, (size_t)st.st_size);
        return NULL;
    }
    c->map = map;
    c->size = (size_t)st.st_size;
    if (memcmp(c->map, "BOMStore", 8))
        goto bad;
    c->index_offset = be32(c->map + 16);
    if ((uint64_t)c->index_offset + 4 > c->size)
        goto bad;
    c->nblocks = be32(c->map + c->index_offset);
    if ((uint64_t)c->index_offset + 4 + 8 * (uint64_t)c->nblocks > c->size)
        goto bad;
    uint32_t len, idx = named_block(c, "KEYFORMAT");
    const uint8_t *kf = idx ? block(c, idx, &len) : NULL;
    if (!kf || len < 12)
        goto bad;
    c->nattrs = le32(kf + 8);
    if (c->nattrs > MAX_ATTRS || 12 + 4 * (uint32_t)c->nattrs > len)
        goto bad;
    c->at_identifier = c->at_scale = c->at_appearance = -1;
    for (int i = 0; i < c->nattrs; i++) {
        c->attrs[i] = le32(kf + 12 + 4 * i);
        if (c->attrs[i] == ATTR_IDENTIFIER)
            c->at_identifier = i;
        else if (c->attrs[i] == ATTR_SCALE)
            c->at_scale = i;
        else if (c->attrs[i] == ATTR_APPEARANCE)
            c->at_appearance = i;
    }
    if (c->at_identifier < 0)
        goto bad;
    walk_tree(c, "FACETKEYS", add_facet, NULL);
    walk_tree(c, "RENDITIONS", add_rendition, NULL);
    walk_tree(c, "APPEARANCEKEYS", add_appearance, NULL);
    return c;
bad:
    acar_close(c);
    return NULL;
}

void acar_close(struct acar *c)
{
    if (!c)
        return;
    for (int i = 0; i < c->nfacets; i++)
        free(c->facets[i].name);
    free(c->facets);
    free(c->renditions);
    for (int i = 0; i < c->natlases; i++)
        free(c->atlases[i].bitmap.rgba);
    if (c->map)
        munmap(c->map, c->size);
    free(c);
}

/* ---- renditions -------------------------------------------------------------------- */

struct csi {
    uint32_t width, height, scale, format, layout, bytes_per_row;
    const uint8_t *link;    /* an 'INLK' value */
    uint32_t link_length;
    const uint8_t *uti;
    uint32_t uti_length;
    const uint8_t *body;
    uint32_t body_length;
};

#define FOURCC(a, b, c, d) ((uint32_t)(a) << 24 | (b) << 16 | (c) << 8 | (d))

static int read_csi(const struct rendition *r, struct csi *s)
{
    const uint8_t *v = r->csi;
    memset(s, 0, sizeof *s);
    s->width = le32(v + 12);
    s->height = le32(v + 16);
    s->scale = le32(v + 20);
    s->format = le32(v + 24);
    s->layout = le16(v + 36);
    uint32_t tlv = le32(v + 168);
    if (184 + (uint64_t)tlv > r->length)
        return -1;
    for (uint32_t p = 0; p + 8 <= tlv;) {
        uint32_t tag = le32(v + 184 + p), n = le32(v + 188 + p);
        const uint8_t *val = v + 192 + p;
        if (p + 8 + (uint64_t)n > tlv)
            break;
        if (tag == 1007 && n >= 4)
            s->bytes_per_row = le32(val);
        else if (tag == 1010 && n >= 4 && !memcmp(val, "KLNI", 4))
            s->link = val, s->link_length = n;
        else if (tag == 1005 && n >= 8)
            s->uti = val + 8, s->uti_length = n - 8;
        p += 8 + n;
    }
    s->body = v + 184 + tlv;
    s->body_length = r->length - 184 - tlv;
    return 0;
}

static int identifier_for(struct acar *c, const char *name)
{
    for (int i = 0; i < c->nfacets; i++)
        if (!strcmp(c->facets[i].name, name))
            return c->facets[i].identifier;
    return -1;
}

static int is_dark(struct acar *c, const struct rendition *r)
{
    if (c->at_appearance < 0)
        return 0;
    for (int i = 0; i < c->ndark; i++)
        if (r->key[c->at_appearance] == c->dark[i])
            return 1;
    return 0;
}

/* The renditions of an asset, light ones first, then dark ones if there are
 * no light ones. Returns how many indices went into out. */
static int renditions_for(struct acar *c, const char *name, int *out, int max)
{
    int id = name ? identifier_for(c, name) : -1, n = 0;
    if (id < 0)
        return 0;
    for (int pass = 0; pass < 2 && !n; pass++)
        for (int i = 0; i < c->nrenditions && n < max; i++)
            if (c->renditions[i].key[c->at_identifier] == id && is_dark(c, &c->renditions[i]) == pass)
                out[n++] = i;
    return n;
}

/* ---- decompression ------------------------------------------------------------------ */

/* Decompresses LZFSE (or a bare LZVN stream, given the size it makes) into
 * a new buffer of up to cap bytes. */
static uint8_t *inflate_lz(const uint8_t *src, size_t n, size_t cap, size_t lzvn_size, size_t *out_len)
{
    uint8_t *dst = malloc(cap ? cap : 1);
    if (!dst)
        return NULL;
    size_t got = 0;
    if (n >= 4 && !memcmp(src, "bvx", 3)) {
        got = compression_decode_buffer(dst, cap, src, n, NULL, COMPRESSION_LZFSE);
    } else if (lzvn_size) {
        /* a bare LZVN stream: give it an LZFSE block header ('bvxn') */
        uint8_t *wrapped = malloc(n + 16);
        if (wrapped) {
            uint32_t h[3] = {0x6E787662, (uint32_t)lzvn_size, (uint32_t)n}, end = 0x24787662;
            memcpy(wrapped, h, 12);
            memcpy(wrapped + 12, src, n);
            memcpy(wrapped + 12 + n, &end, 4);
            got = compression_decode_buffer(dst, cap, wrapped, n + 16, NULL, COMPRESSION_LZFSE);
            free(wrapped);
        }
    }
    if (!got) {
        free(dst);
        return NULL;
    }
    *out_len = got;
    return dst;
}

/* ---- deepmap2 ----------------------------------------------------------------------- */

struct dmp2 {
    int type, version, format, width, height, palette_size, palette_type;
    const uint8_t *palette, *payload;
    size_t payload_length;
};

static int read_dmp2(const uint8_t *p, size_t n, struct dmp2 *d)
{
    if (n < 12 || memcmp(p, "dmp2", 4))
        return -1;
    memset(d, 0, sizeof *d);
    d->type = p[4];
    d->version = p[5];
    d->format = p[7];
    d->width = le16(p + 8);
    d->height = le16(p + 10);
    size_t h = 12;
    if (d->type == 4) {
        if (n < 16)
            return -1;
        d->palette_size = le16(p + 12);
        d->palette_type = le16(p + 14);
        d->palette = p + 16;
        h = 16 + 4 * (size_t)d->palette_size;
        if (h > n)
            return -1;
    }
    if (d->format < 1 || d->format > 4 || !d->width || !d->height)
        return -1;
    d->payload = p + h;
    d->payload_length = n - h;
    return 0;
}

/* The payload may be cut into chunks, each led by its size. */
static int split_chunks(const uint8_t *p, size_t n, const uint8_t **chunk, size_t *size, int max)
{
    int count = 0;
    size_t i = 0;
    while (i + 4 <= n) {
        uint32_t s = le32(p + i);
        i += 4;
        if (!s || i + s > n || count == max)
            return 0;
        chunk[count] = p + i;
        size[count++] = s;
        i += s;
    }
    return i == n ? count : 0;
}


/* Undoes a row's predictor (samples in groups of three). */
static void unpredict(int kind, int16_t *row, const int16_t *prev, int count)
{
    int i;
    switch (kind) {
    case 1: /* Paeth: pick left or up for each pixel by its first sample */
        for (i = 0; i < 3 && i < count; i++)
            row[i] = (int16_t)(row[i] + (prev ? prev[i] : 0));
        for (i = 3; i < count; i += 3) {
            int left = row[i - 3], up = prev ? prev[i] : 0, up_left = prev ? prev[i - 3] : 0;
            int use_left = abs(up - up_left) <= abs(left - up_left);
            for (int k = 0; k < 3 && i + k < count; k++)
                row[i + k] = (int16_t)(row[i + k] + (use_left ? row[i + k - 3] : prev ? prev[i + k] : 0));
        }
        break;
    case 2: /* Left */
        for (i = 3; i < count; i++)
            row[i] = (int16_t)(row[i] + row[i - 3]);
        break;
    case 3: /* Up */
        if (prev)
            for (i = 0; i < count; i++)
                row[i] = (int16_t)(row[i] + prev[i]);
        break;
    case 4: /* Mean of left and up */
        for (i = 0; i < 3 && i < count; i++)
            row[i] = (int16_t)(row[i] + (prev ? prev[i] : 0));
        for (i = 3; i < count; i++)
            row[i] = (int16_t)(row[i] + (row[i - 3] + (prev ? prev[i] : 0) + 1) / 2);
        break;
    }
}

static uint8_t clamp8(int v) { return v < 0 ? 0 : v > 255 ? 255 : (uint8_t)v; }

/* Decodes rows of the Default coding (an alpha plane, a predictor per row,
 * then each sample's high and low bytes, zigzag-signed) into BGRA. */
static int dmp2_default_rows(const struct dmp2 *d, const uint8_t *src, size_t n, uint8_t *bgra, int max_rows)
{
    int w = d->width, alpha = d->format == 2 || d->format == 4, color = d->format >= 3;
    int comps = color ? 3 : 1;
    size_t stride = (alpha ? w : 0) + 1 + (size_t)w * comps * 2;
    int rows = (int)(n / stride);
    if (!rows)
        return -1;
    if (rows > max_rows)
        rows = max_rows;
    int total = (int)(n / stride);
    const uint8_t *ap = src, *pred = src + (alpha ? (size_t)w * total : 0);
    const uint8_t *hi = pred + total, *lo = hi + (size_t)w * comps * total;
    int16_t *prev = NULL, *row = malloc(sizeof(int16_t) * 3 * w), *last = malloc(sizeof(int16_t) * 3 * w);
    if (!row || !last) {
        free(row);
        free(last);
        return -1;
    }
    int scale = d->version ? 1 : 0;
    for (int y = 0; y < rows; y++) {
        for (int x = 0; x < w; x++)
            for (int k = 0; k < 3; k++) {
                int v = 0;
                if (k < comps) {
                    size_t at = ((size_t)y * w + x) * comps + k;
                    unsigned u = lo[at] | hi[at] << 8;
                    v = (u & 1) ? -(int)(u >> 1) : (int)(u >> 1);
                }
                row[3 * x + k] = (int16_t)v;
            }
        unpredict(pred[y], row, prev, 3 * w);
        uint8_t *out = bgra + (size_t)y * w * 4;
        for (int x = 0; x < w; x++) {
            int Y = row[3 * x], a = alpha ? ap[(size_t)y * w + x] : 255;
            if (color) {
                int co = row[3 * x + 1] * (1 << scale), cg = row[3 * x + 2] * (1 << scale);
                /* YCoCg; the first chroma runs towards blue here, so the
                 * sample that YCoCg calls red is the picture's blue */
                int t = Y - cg / 2;
                out[4 * x + 0] = clamp8(t + co - co / 2);
                out[4 * x + 1] = clamp8(t + cg);
                out[4 * x + 2] = clamp8(t - co / 2);
            } else
                out[4 * x] = out[4 * x + 1] = out[4 * x + 2] = (uint8_t)Y;
            out[4 * x + 3] = (uint8_t)a;
        }
        memcpy(last, row, sizeof(int16_t) * 3 * w);
        prev = last;
    }
    free(row);
    free(last);
    return rows;
}

/* Raw samples (BGRA, BGR, grey and alpha, or grey) into BGRA. */
static void raw_rows(int format, const uint8_t *src, uint8_t *bgra, size_t pixels)
{
    for (size_t i = 0; i < pixels; i++) {
        uint8_t *o = bgra + 4 * i;
        switch (format) {
        case 1: o[0] = o[1] = o[2] = src[i], o[3] = 255; break;
        case 2: o[0] = o[1] = o[2] = src[2 * i], o[3] = src[2 * i + 1]; break;
        case 3: o[0] = src[3 * i], o[1] = src[3 * i + 1], o[2] = src[3 * i + 2], o[3] = 255; break;
        default: memcpy(o, src + 4 * i, 4); break;
        }
    }
}

/* Decodes a deepmap2 picture into BGRA rows of width*4 bytes. */
static uint8_t *dmp2_decode(const uint8_t *p, size_t n, int *width, int *height)
{
    struct dmp2 d;
    if (read_dmp2(p, n, &d))
        return NULL;
    int w = d.width, h = d.height;
    size_t pixels = (size_t)w * h;
    uint8_t *bgra = calloc(pixels, 4);
    if (!bgra)
        return NULL;
    const uint8_t *chunk[4096];
    size_t size[4096];
    int nchunks = split_chunks(d.payload, d.payload_length, chunk, size, 4096);
    if (!nchunks) {
        chunk[0] = d.payload;
        size[0] = d.payload_length;
        nchunks = 1;
    }
    int bpp = d.format == 4 ? 4 : d.format;
    int y = 0;
    if (d.type == 2) {
        size_t stride = ((d.format == 2 || d.format == 4) ? w : 0) + 1 + (size_t)w * (d.format >= 3 ? 3 : 1) * 2;
        for (int i = 0; i < nchunks && y < h; i++) {
            size_t got;
            uint8_t *raw = inflate_lz(chunk[i], size[i], stride * h + 64, 0, &got);
            if (!raw)
                goto bad;
            int rows = dmp2_default_rows(&d, raw, got, bgra + (size_t)y * w * 4, h - y);
            free(raw);
            if (rows <= 0)
                goto bad;
            y += rows;
        }
    } else if (d.type == 1 || d.type == 3) {
        for (int i = 0; i < nchunks && y < h; i++) {
            size_t got, want = (size_t)w * (h - y) * bpp;
            uint8_t *raw;
            if (d.type == 1) {
                raw = malloc(size[i]);
                if (raw)
                    memcpy(raw, chunk[i], got = size[i]);
            } else
                raw = inflate_lz(chunk[i], size[i], want, want, &got);
            if (!raw)
                goto bad;
            int rows = (int)(got / ((size_t)w * bpp));
            if (rows > h - y)
                rows = h - y;
            raw_rows(d.format, raw, bgra + (size_t)y * w * 4, (size_t)rows * w);
            free(raw);
            if (rows <= 0)
                goto bad;
            y += rows;
        }
    } else if (d.type == 4) {
        size_t want = d.palette_type == 3 ? 2 * pixels : pixels;
        uint8_t *planes = malloc(want);
        size_t have = 0;
        if (!planes)
            goto bad;
        for (int i = 0; i < nchunks && have < want; i++) {
            size_t got;
            uint8_t *raw = inflate_lz(chunk[i], size[i], want - have, want - have, &got);
            if (!raw) {
                free(planes);
                goto bad;
            }
            memcpy(planes + have, raw, got);
            have += got;
            free(raw);
        }
        if (have < want) {
            free(planes);
            goto bad;
        }
        const uint8_t *alpha = d.palette_type == 3 ? planes : NULL, *index = alpha ? planes + pixels : planes;
        for (size_t i = 0; i < pixels; i++) {
            uint32_t e = index[i] < d.palette_size ? le32(d.palette + 4 * index[i]) : 0;
            uint8_t *o = bgra + 4 * i;
            o[0] = e & 0xFF, o[1] = e >> 8 & 0xFF, o[2] = e >> 16 & 0xFF, o[3] = alpha ? alpha[i] : e >> 24;
        }
        free(planes);
        y = h;
    }
    if (y < h)
        goto bad;
    *width = w;
    *height = h;
    return bgra;
bad:
    free(bgra);
    return NULL;
}

/* ---- pictures ---------------------------------------------------------------------- */

/* Puts BGRA (or grey and alpha) rows, premultiplied, into RGBA rows. */
static void to_rgba(const uint8_t *src, size_t src_stride, int bytes_per_pixel, uint8_t *dst, int w, int h)
{
    for (int y = 0; y < h; y++) {
        const uint8_t *s = src + (size_t)y * src_stride;
        uint8_t *o = dst + (size_t)y * w * 4;
        for (int x = 0; x < w; x++, o += 4)
            if (bytes_per_pixel == 2) {
                o[0] = o[1] = o[2] = s[2 * x];
                o[3] = s[2 * x + 1];
            } else {
                o[0] = s[4 * x + 2];
                o[1] = s[4 * x + 1];
                o[2] = s[4 * x];
                o[3] = s[4 * x + 3];
            }
    }
}

/* A 'CELM' body's pixels as BGRA (or grey and alpha) rows. */
static uint8_t *celm_pixels(const struct csi *s, size_t *stride, int *bpp, int *w, int *h)
{
    const uint8_t *b = s->body;
    if (s->body_length < 16 || memcmp(b, "MLEC", 4))
        return NULL;
    uint32_t version = le32(b + 4), compression = le32(b + 8);
    *bpp = s->format == FOURCC('G', 'A', '8', ' ') ? 2 : 4;
    *w = s->width;
    *h = s->height;
    *stride = s->bytes_per_row ? s->bytes_per_row : (size_t)s->width * *bpp;
    if (*stride < (size_t)*w * *bpp)
        return NULL;
    size_t total = *stride * s->height;

    /* the bands: one whole picture, or 'KCBC' bands of rows */
    const uint8_t *band[256];
    uint32_t band_len[256], band_rows[256];
    int nbands = 0;
    if (version == 0) {
        uint32_t n = le32(b + 12);
        if (16 + (uint64_t)n > s->body_length)
            return NULL;
        band[0] = b + 16, band_len[0] = n, band_rows[0] = s->height, nbands = 1;
    } else {
        uint32_t count = le32(b + 12);
        size_t p = 16;
        for (uint32_t i = 0; i < count && i < 256; i++) {
            if (p + 20 > s->body_length || memcmp(b + p, "KCBC", 4))
                return NULL;
            uint32_t rows = le32(b + p + 12), n = le32(b + p + 16);
            if (p + 20 + (uint64_t)n > s->body_length)
                return NULL;
            band[nbands] = b + p + 20, band_len[nbands] = n, band_rows[nbands++] = rows;
            p += 20 + n;
        }
    }
    if (compression == 11 && nbands == 1) {
        /* deepmap2: its header sits a little way in */
        const uint8_t *d = memmem(band[0], band_len[0] < 64 ? band_len[0] : 64, "dmp2", 4);
        if (!d)
            return NULL;
        int dw, dh;
        uint8_t *out = dmp2_decode(d, band_len[0] - (d - band[0]), &dw, &dh);
        if (out) {
            *w = dw, *h = dh, *stride = (size_t)dw * 4, *bpp = 4;
            if (s->format == FOURCC('G', 'A', '8', ' ')) {
                /* back to grey and alpha */
                for (size_t i = 0; i < (size_t)dw * dh; i++)
                    out[2 * i] = out[4 * i], out[2 * i + 1] = out[4 * i + 3];
                *stride = (size_t)dw * 2, *bpp = 2;
            }
        }
        return out;
    }
    uint8_t *out = calloc(total ? total : 1, 1);
    size_t at = 0;
    if (!out)
        return NULL;
    for (int i = 0; i < nbands && at < total; i++) {
        size_t want = (size_t)band_rows[i] * *stride, got = 0;
        if (want > total - at)
            want = total - at;
        uint8_t *raw = NULL;
        switch (compression) {
        case 0:
            got = band_len[i] < want ? band_len[i] : want;
            memcpy(out + at, band[i], got);
            break;
        case 3: case 4:
            raw = inflate_lz(band[i], band_len[i], want, want, &got);
            break;
        case 2:
            got = compression_decode_buffer(out + at, want, band[i] + 2, band_len[i] > 2 ? band_len[i] - 2 : 0, NULL,
                                            COMPRESSION_ZLIB);
            break;
        case 11: {
            const uint8_t *d = memmem(band[i], band_len[i] < 64 ? band_len[i] : 64, "dmp2", 4);
            int dw, dh;
            uint8_t *px = d ? dmp2_decode(d, band_len[i] - (d - band[i]), &dw, &dh) : NULL;
            if (px) {
                for (int y = 0; y < dh && at + (size_t)(y + 1) * *stride <= total; y++)
                    memcpy(out + at + (size_t)y * *stride, px + (size_t)y * dw * 4, (size_t)(dw < *w ? dw : *w) * 4);
                got = (size_t)dh * *stride;
                free(px);
            }
            break;
        }
        }
        if (raw) {
            memcpy(out + at, raw, got);
            free(raw);
        }
        if (!got) {
            free(out);
            return NULL;
        }
        at += got;
    }
    return out;
}

static int key_matches_link(struct acar *c, const struct rendition *r, const uint8_t *tokens, size_t n)
{
    uint16_t want[MAX_ATTRS] = {0};
    for (size_t i = 0; i + 4 <= n; i += 4) {
        uint16_t attr = le16(tokens + i), value = le16(tokens + i + 2);
        if (!attr)
            break;
        for (int k = 0; k < c->nattrs; k++)
            if (c->attrs[k] == attr)
                want[k] = value;
    }
    for (int k = 0; k < c->nattrs; k++)
        if (r->key[k] != want[k])
            return 0;
    return 1;
}

static int decode_rendition(struct acar *c, int index, struct acar_bitmap *out, int depth);

/* A picture packed into a shared sheet: decode the sheet once and cut it out. */
static int decode_link(struct acar *c, const struct csi *s, struct acar_bitmap *out, int depth)
{
    const uint8_t *l = s->link;
    if (s->link_length < 34 || depth > 1)
        return -1;
    uint32_t x = le32(l + 8), y = le32(l + 12), w = le32(l + 16), h = le32(l + 20);
    /* then the sheet's layout (16 bits) and its key: a 32-bit length and
     * (attribute, value) pairs of 16 bits each, ending with a zero pair */
    const uint8_t *tokens = l + 30;
    size_t ntok = le32(l + 26);
    if (30 + ntok > s->link_length)
        ntok = s->link_length - 30;
    int target = -1;
    for (int i = 0; i < c->nrenditions && target < 0; i++)
        if (key_matches_link(c, &c->renditions[i], tokens, ntok))
            target = i;
    if (target < 0)
        return -1;
    struct acar_bitmap *sheet = NULL;
    for (int i = 0; i < c->natlases; i++)
        if (c->atlases[i].index == target)
            sheet = &c->atlases[i].bitmap;
    if (!sheet) {
        struct acar_bitmap b;
        if (decode_rendition(c, target, &b, depth + 1))
            return -1;
        if (c->natlases == 8) {
            free(c->atlases[0].bitmap.rgba);
            memmove(c->atlases, c->atlases + 1, 7 * sizeof *c->atlases);
            c->natlases--;
        }
        c->atlases[c->natlases].index = target;
        c->atlases[c->natlases].bitmap = b;
        sheet = &c->atlases[c->natlases++].bitmap;
    }
    if (!w || !h || x + w > (uint32_t)sheet->width || y + h > (uint32_t)sheet->height)
        return -1;
    out->width = w;
    out->height = h;
    out->scale = s->scale >= 100 ? s->scale / 100 : 1;
    out->rgba = malloc((size_t)w * h * 4);
    if (!out->rgba)
        return -1;
    for (uint32_t r = 0; r < h; r++)
        memcpy(out->rgba + (size_t)r * w * 4, sheet->rgba + ((size_t)(y + r) * sheet->width + x) * 4, (size_t)w * 4);
    return 0;
}

static int decode_rendition(struct acar *c, int index, struct acar_bitmap *out, int depth)
{
    struct csi s;
    if (read_csi(&c->renditions[index], &s))
        return -1;
    if (s.link)
        return decode_link(c, &s, out, depth);
    if (s.format != FOURCC('A', 'R', 'G', 'B') && s.format != FOURCC('G', 'A', '8', ' '))
        return -1;
    size_t stride;
    int bpp, w, h;
    uint8_t *px = celm_pixels(&s, &stride, &bpp, &w, &h);
    if (!px)
        return -1;
    out->width = w;
    out->height = h;
    out->scale = s.scale >= 100 ? s.scale / 100 : 1;
    out->rgba = malloc((size_t)w * h * 4 + 1);
    if (out->rgba)
        to_rgba(px, stride, bpp, out->rgba, w, h);
    free(px);
    return out->rgba ? 0 : -1;
}

int acar_image(struct acar *c, const char *name, struct acar_bitmap *out, int max)
{
    int idx[64], n = c ? renditions_for(c, name, idx, 64) : 0, count = 0;
    for (int i = 0; i < n && count < max; i++) {
        struct csi s;
        if (read_csi(&c->renditions[idx[i]], &s) || !s.width || !s.height)
            continue;
        int dup = 0;
        for (int k = 0; k < count; k++)
            if ((uint32_t)out[k].width == s.width && (uint32_t)out[k].height == s.height &&
                out[k].scale == (int)(s.scale >= 100 ? s.scale / 100 : 1))
                dup = 1;
        if (!dup && !decode_rendition(c, idx[i], &out[count], 0))
            count++;
    }
    return count;
}

/* A 'RAWD' body's bytes, decompressed if need be. */
static uint8_t *rawd_bytes(const struct csi *s, size_t *length)
{
    const uint8_t *b = s->body;
    if (s->body_length < 12 || memcmp(b, "DWAR", 4))
        return NULL;
    uint32_t flags = le32(b + 4), n = le32(b + 8);
    if (12 + (uint64_t)n > s->body_length)
        return NULL;
    b += 12;
    if (n >= 4 && !memcmp(b, "bvx", 3) && (flags & 1)) {
        for (size_t cap = (size_t)n * 8 + 4096; cap < ((size_t)1 << 31); cap *= 4) {
            size_t got;
            uint8_t *out = inflate_lz(b, n, cap, 0, &got);
            if (!out)
                return NULL;
            if (got < cap) {
                *length = got;
                return out;
            }
            free(out);
        }
        return NULL;
    }
    uint8_t *out = malloc(n ? n : 1);
    if (out) {
        memcpy(out, b, n);
        *length = n;
    }
    return out;
}

uint8_t *acar_vector(struct acar *c, const char *name, size_t *length)
{
    int idx[64], n = c ? renditions_for(c, name, idx, 64) : 0;
    for (int i = 0; i < n; i++) {
        struct csi s;
        if (read_csi(&c->renditions[idx[i]], &s))
            continue;
        if (s.format == FOURCC('S', 'V', 'G', ' ') || s.format == FOURCC('P', 'D', 'F', ' ')) {
            uint8_t *bytes = rawd_bytes(&s, length);
            if (bytes)
                return bytes;
        }
    }
    return NULL;
}

int acar_color(struct acar *c, const char *name, double rgba[4])
{
    int idx[64], n = c ? renditions_for(c, name, idx, 64) : 0;
    for (int i = 0; i < n; i++) {
        struct csi s;
        if (read_csi(&c->renditions[idx[i]], &s) || s.body_length < 16 || memcmp(s.body, "RLOC", 4))
            continue;
        uint32_t count = le32(s.body + 12);
        if (count < 1 || count > 5 || 16 + 8 * (uint64_t)count > s.body_length)
            continue;
        double v[5];
        memcpy(v, s.body + 16, 8 * count);
        if (count <= 2) {    /* grey and alpha */
            rgba[0] = rgba[1] = rgba[2] = v[0];
            rgba[3] = count == 2 ? v[1] : 1;
        } else {
            rgba[0] = v[0], rgba[1] = v[1], rgba[2] = v[2];
            rgba[3] = count >= 4 ? v[3] : 1;
        }
        return 1;
    }
    return 0;
}

uint8_t *acar_data(struct acar *c, const char *name, size_t *length, char *uti, size_t uti_size)
{
    int idx[64], n = c ? renditions_for(c, name, idx, 64) : 0;
    for (int i = 0; i < n; i++) {
        struct csi s;
        if (read_csi(&c->renditions[idx[i]], &s) || s.format != FOURCC('D', 'A', 'T', 'A'))
            continue;
        uint8_t *bytes = rawd_bytes(&s, length);
        if (!bytes)
            continue;
        if (uti && uti_size) {
            size_t k = 0;
            for (; s.uti && k < s.uti_length && k + 1 < uti_size && s.uti[k]; k++)
                uti[k] = (char)s.uti[k];
            uti[k] = 0;
        }
        return bytes;
    }
    return NULL;
}
