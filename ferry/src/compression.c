/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libcompression (freemac 1.271): a Mac's /usr/lib/libcompression.dylib,
 * whose buffer calls (compression_decode_buffer, compression_encode_buffer)
 * apps use for LZFSE, LZ4, zlib and LZMA data. Asset catalogs (Assets.car)
 * keep their pictures LZFSE- or LZVN-compressed, so AppKit's reader uses
 * these calls too, as does the Installer for compressed disk images.
 *
 * The LZFSE and LZVN decoders are written from the description of the
 * formats in the MIT-licensed lzfse_rust crate (Vin Singh Ghataore), a
 * third-party implementation: block headers, the finite-state-entropy
 * tables and their backward bit streams, and LZVN's opcodes. Apple's own
 * lzfse code was not used. LZ4 is decoded from its public block format;
 * zlib (raw deflate, as a Mac's COMPRESSION_ZLIB) and LZMA (the xz
 * format) go to this system's libz and liblzma.
 *
 * Encoding writes LZFSE and LZ4 as stored blocks, which any decoder
 * reads, and zlib and LZMA through this system's libraries.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ferry.h"

#define COMPRESSION_LZ4      0x100
#define COMPRESSION_LZ4_RAW  0x101
#define COMPRESSION_ZLIB     0x205
#define COMPRESSION_LZMA     0x306
#define COMPRESSION_LZFSE    0x801
#define COMPRESSION_LZBITMAP 0x702
#define COMPRESSION_BROTLI   0xB02

static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint64_t rd64(const uint8_t *p) { return rd32(p) | (uint64_t)rd32(p + 4) << 32; }

/* ---- output with LZ matches ------------------------------------------------------ */

struct out {
    uint8_t *p;
    size_t n, cap;
    int full;    /* ran past the caller's buffer: stop, keeping what fits */
};

static int put_bytes(struct out *o, const uint8_t *s, size_t n)
{
    if (n > o->cap - o->n) {
        memcpy(o->p + o->n, s, o->cap - o->n);
        o->n = o->cap;
        o->full = 1;
        return -1;
    }
    memcpy(o->p + o->n, s, n);
    o->n += n;
    return 0;
}

static int put_match(struct out *o, size_t len, size_t dist)
{
    if (!dist || dist > o->n)
        return -2;
    for (size_t i = 0; i < len; i++) {
        if (o->n == o->cap) {
            o->full = 1;
            return -1;
        }
        o->p[o->n] = o->p[o->n - dist];
        o->n++;
    }
    return 0;
}

/* ---- LZFSE ------------------------------------------------------------------------ */

#define L_SYMS 20
#define M_SYMS 20
#define D_SYMS 64
#define U_SYMS 256
#define L_STATES 64
#define M_STATES 64
#define D_STATES 256
#define U_STATES 1024
#define LITERALS_PER_BLOCK 40000

static const uint8_t l_extra[L_SYMS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 5, 8};
static const uint32_t l_base[L_SYMS] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 28, 60};
static const uint8_t m_extra[M_SYMS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 5, 8, 11};
static const uint32_t m_base[M_SYMS] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 24, 56, 312};
static const uint8_t d_extra[D_SYMS] = {
    0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
    8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15};
static const uint32_t d_base[D_SYMS] = {
    0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 28, 36, 44, 52, 60, 76, 92, 108, 124, 156, 188, 220,
    252, 316, 380, 444, 508, 636, 764, 892, 1020, 1276, 1532, 1788, 2044, 2556, 3068, 3580, 4092, 5116,
    6140, 7164, 8188, 10236, 12284, 14332, 16380, 20476, 24572, 28668, 32764, 40956, 49148, 57340, 65532,
    81916, 98300, 114684, 131068, 163836, 196604, 229372};

/* The frequency of each symbol is stored in a variable-length code whose
 * low five bits pick its length and value. */
static const uint8_t w_bits[32] = {2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14,
                                   2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14};
static const int8_t w_value[32] = {0, 2, 1, 4, 0, 3, 1, -1, 0, 2, 1, 5, 0, 3, 1, -1,
                                   0, 2, 1, 6, 0, 3, 1, -1, 0, 2, 1, 7, 0, 3, 1, -1};

struct ventry { uint8_t k, vbits; int16_t delta; uint32_t vbase; };
struct uentry { uint8_t k, sym; int16_t delta; };

static int clz32(uint32_t v) { return v ? __builtin_clz(v) : 32; }

static int build_v(const uint16_t *w, int nsym, const uint8_t *extra, const uint32_t *base, struct ventry *t, int nstates)
{
    int nclz = clz32(nstates), total = 0;
    for (int i = 0; i < nsym; i++) {
        int f = w[i];
        if (!f)
            continue;
        if (total + f > nstates)
            return -1;
        int k = clz32(f) - nclz;
        int x = ((nstates << 1) >> k) - f;
        for (int j = 0; j < f; j++) {
            struct ventry e = {.vbits = extra[i], .vbase = base[i]};
            if (j < x) {
                e.k = k;
                e.delta = ((f + j) << k) - nstates;
            } else {
                e.k = k - 1;
                e.delta = (j - x) << (k - 1);
            }
            t[total + j] = e;
        }
        total += f;
    }
    for (int i = total; i < nstates; i++)
        t[i] = (struct ventry){0, 0, (int16_t)i, 0};
    return 0;
}

static int build_u(const uint16_t *w, struct uentry *t)
{
    int nstates = U_STATES, nclz = clz32(nstates), total = 0;
    for (int i = 0; i < U_SYMS; i++) {
        int f = w[i];
        if (!f)
            continue;
        if (total + f > nstates)
            return -1;
        int k = clz32(f) - nclz;
        int x = ((nstates << 1) >> k) - f;
        for (int j = 0; j < f; j++) {
            struct uentry e = {.sym = (uint8_t)i};
            if (j < x) {
                e.k = k;
                e.delta = ((f + j) << k) - nstates;
            } else {
                e.k = k - 1;
                e.delta = (j - x) << (k - 1);
            }
            t[total + j] = e;
        }
        total += f;
    }
    for (int i = total; i < nstates; i++)
        t[i] = (struct uentry){0, 0, (int16_t)i};
    return 0;
}

/* A bit stream read backwards from its end: 64 bits at a time, highest
 * first, refilled whole bytes at a time. Bytes before the buffer read as 0. */
struct bits {
    const uint8_t *lo;    /* the stream's own buffer starts here */
    const uint8_t *pos;   /* the 8 bytes now held start here */
    uint64_t acc;
    int nbits;
};

static uint64_t rd64_bounded(const uint8_t *lo, const uint8_t *p)
{
    if (p >= lo)
        return rd64(p);
    uint8_t b[8] = {0};
    for (int i = 0; i < 8; i++)
        if (p + i >= lo)
            b[i] = p[i];
    return rd64(b);
}

static int bits_init(struct bits *b, const uint8_t *lo, const uint8_t *end, int off)
{
    if (off < 0 || off > 7 || end - lo < 8)
        return -1;
    b->lo = lo;
    b->pos = end - 8;
    b->acc = rd64(b->pos);
    b->nbits = 64 - off;
    if (off && b->acc >> b->nbits)
        return -1;
    return 0;
}

static void bits_flush(struct bits *b)
{
    int nbytes = (64 - b->nbits) / 8;
    b->pos -= nbytes;
    b->acc = rd64_bounded(b->lo, b->pos);
    b->nbits += nbytes * 8;
}

static uint32_t bits_pull(struct bits *b, int n)
{
    if (!n)
        return 0;
    b->nbits -= n;
    if (b->nbits < 0)
        return 0;
    return (uint32_t)((b->acc >> b->nbits) & ((1ull << n) - 1));
}

struct fse_tables {
    struct ventry l[L_STATES], m[M_STATES], d[D_STATES];
    struct uentry u[U_STATES];
    uint8_t literals[LITERALS_PER_BLOCK + 64];
};

static int lzfse_block_v2(const uint8_t *s, size_t avail, struct out *o, struct fse_tables *t, size_t *used)
{
    if (avail < 32)
        return -1;
    uint32_t n_raw = rd32(s + 4);
    uint64_t p0 = rd64(s + 8), p1 = rd64(s + 16), p2 = rd64(s + 24);
    uint32_t n_lit = p0 & 0xFFFFF, lit_bytes = (p0 >> 20) & 0xFFFFF, n_lmd = (p0 >> 40) & 0xFFFFF;
    int lit_bits = 7 - (int)((p0 >> 60) & 7);
    uint16_t lit_state[4] = {p1 & 0x3FF, (p1 >> 10) & 0x3FF, (p1 >> 20) & 0x3FF, (p1 >> 30) & 0x3FF};
    uint32_t lmd_bytes = (p1 >> 40) & 0xFFFFF;
    int lmd_bits = 7 - (int)((p1 >> 60) & 7);
    uint32_t header_size = p2 & 0xFFFFFFFF;
    uint16_t lmd_state[3] = {(p2 >> 32) & 0x3FF, (p2 >> 42) & 0x3FF, (p2 >> 52) & 0x3FF};
    if (n_lit > LITERALS_PER_BLOCK || n_lit % 4 || header_size < 32 || lmd_bytes < 8 ||
        lit_state[0] >= U_STATES || lmd_state[0] >= L_STATES || lmd_state[1] >= M_STATES || lmd_state[2] >= D_STATES ||
        (uint64_t)header_size + lit_bytes + lmd_bytes > avail)
        return -1;
    /* the frequencies, L, M, D and the literals in turn, packed from bit 0 */
    uint16_t w[L_SYMS + M_SYMS + D_SYMS + U_SYMS];
    const uint8_t *wp = s + 32, *we = s + header_size;
    uint64_t acc = 0;
    int accbits = 0;
    for (int i = 0; i < (int)(sizeof w / sizeof *w); i++) {
        while (wp < we && accbits <= 24) {
            acc |= (uint64_t)*wp++ << accbits;
            accbits += 8;
        }
        int idx = acc & 31, nb = w_bits[idx];
        w[i] = nb == 8 ? 8 + ((acc >> 4) & 0xF) : nb == 14 ? 24 + ((acc >> 4) & 0x3FF) : w_value[idx];
        acc >>= nb;
        accbits -= nb;
    }
    if (accbits < 0)
        return -1;
    if (build_v(w, L_SYMS, l_extra, l_base, t->l, L_STATES) || build_v(w + L_SYMS, M_SYMS, m_extra, m_base, t->m, M_STATES) ||
        build_v(w + L_SYMS + M_SYMS, D_SYMS, d_extra, d_base, t->d, D_STATES) || build_u(w + L_SYMS + M_SYMS + D_SYMS, t->u))
        return -1;

    /* literals: four interleaved states, each 10 bits or fewer */
    const uint8_t *lit_end = s + header_size + lit_bytes;
    struct bits b;
    if (bits_init(&b, s, lit_end, lit_bits))
        return -1;
    uint32_t st[4] = {lit_state[0], lit_state[1], lit_state[2], lit_state[3]};
    for (uint32_t i = 0; i < n_lit; i += 4) {
        for (int j = 0; j < 4; j++) {
            struct uentry e = t->u[st[j]];
            t->literals[i + j] = e.sym;
            st[j] = bits_pull(&b, e.k) + e.delta;
            if (st[j] >= U_STATES)
                return -1;
        }
        bits_flush(&b);
    }

    /* the literal, match and distance triples */
    const uint8_t *lmd_end = lit_end + lmd_bytes;
    if (bits_init(&b, lit_end, lmd_end, lmd_bits))
        return -1;
    uint32_t ls = lmd_state[0], ms = lmd_state[1], ds = lmd_state[2], dist = 0, li = 0;
    size_t start = o->n;
    for (uint32_t n = 0; n < n_lmd; n++) {
        struct ventry e = t->l[ls];
        ls = bits_pull(&b, e.k) + e.delta;
        uint32_t L = e.vbase + bits_pull(&b, e.vbits);
        e = t->m[ms];
        ms = bits_pull(&b, e.k) + e.delta;
        uint32_t M = e.vbase + bits_pull(&b, e.vbits);
        e = t->d[ds];
        ds = bits_pull(&b, e.k) + e.delta;
        uint32_t D = e.vbase + bits_pull(&b, e.vbits);
        bits_flush(&b);
        if (ls >= L_STATES || ms >= M_STATES || ds >= D_STATES || li + L > n_lit)
            return -1;
        if (D)
            dist = D;
        if (put_bytes(o, t->literals + li, L))
            return o->full ? 1 : -1;
        li += L;
        if (M) {
            int r = put_match(o, M, dist);
            if (r)
                return r == -1 ? 1 : -1;
        }
    }
    if (o->n - start != n_raw)
        return -1;
    *used = header_size + lit_bytes + lmd_bytes;
    return 0;
}

/* The first version's header keeps every field whole and the frequencies
 * as 16-bit numbers; it is rare, but read for completeness. */
static int lzfse_block_v1(const uint8_t *s, size_t avail, struct out *o, struct fse_tables *t, size_t *used)
{
    const size_t hdr = 0x32, wbytes = (L_SYMS + M_SYMS + D_SYMS + U_SYMS) * 2 + 2;
    if (avail < hdr + wbytes)
        return -1;
    /* Rebuild it as a version 2 block in memory and decode that. */
    uint32_t n_raw = rd32(s + 4), n_lit = rd32(s + 12), n_lmd = rd32(s + 16), lit_bytes = rd32(s + 20), lmd_bytes = rd32(s + 24);
    int lit_bits = -(int32_t)rd32(s + 28), lmd_bits = -(int32_t)rd32(s + 40);
    uint16_t ls[4] = {s[32] | s[33] << 8, s[34] | s[35] << 8, s[36] | s[37] << 8, s[38] | s[39] << 8};
    uint16_t ms[3] = {s[44] | s[45] << 8, s[46] | s[47] << 8, s[48] | s[49] << 8};
    if (lit_bits < 0 || lit_bits > 7 || lmd_bits < 0 || lmd_bits > 7 || hdr + wbytes + (uint64_t)lit_bytes + lmd_bytes > avail)
        return -1;
    /* encode the frequencies the version 2 way */
    uint8_t *v2 = malloc(32 + 1048 + lit_bytes + lmd_bytes);
    if (!v2)
        return -1;
    size_t wn = 0;
    uint64_t acc = 0;
    int accbits = 0;
    for (int i = 0; i < L_SYMS + M_SYMS + D_SYMS + U_SYMS; i++) {
        unsigned f = s[hdr + 2 * i] | s[hdr + 2 * i + 1] << 8, code, nb;
        if (f < 8) {
            static const uint8_t c[8] = {0, 2, 1, 5, 3, 11, 19, 27}, n[8] = {2, 2, 3, 3, 5, 5, 5, 5};
            code = c[f], nb = n[f];
        } else if (f < 24)
            code = ((f - 8) << 4) + 7, nb = 8;
        else
            code = ((f - 24) << 4) + 15, nb = 14;
        acc |= (uint64_t)code << accbits;
        accbits += nb;
        while (accbits >= 8) {
            v2[32 + wn++] = acc & 0xFF;
            acc >>= 8;
            accbits -= 8;
        }
    }
    if (accbits)
        v2[32 + wn++] = acc & 0xFF;
    uint32_t header_size = 32 + wn;
    uint64_t p0 = n_lit | (uint64_t)lit_bytes << 20 | (uint64_t)n_lmd << 40 | (uint64_t)(7 - lit_bits) << 60;
    uint64_t p1 = ls[0] | (uint64_t)ls[1] << 10 | (uint64_t)ls[2] << 20 | (uint64_t)ls[3] << 30 | (uint64_t)lmd_bytes << 40 |
                  (uint64_t)(7 - lmd_bits) << 60;
    uint64_t p2 = header_size | (uint64_t)ms[0] << 32 | (uint64_t)ms[1] << 42 | (uint64_t)ms[2] << 52;
    memcpy(v2, s, 4);
    memcpy(v2 + 4, &n_raw, 4);
    memcpy(v2 + 8, &p0, 8);
    memcpy(v2 + 16, &p1, 8);
    memcpy(v2 + 24, &p2, 8);
    memcpy(v2 + header_size, s + hdr + wbytes, lit_bytes + lmd_bytes);
    size_t u2;
    int r = lzfse_block_v2(v2, header_size + lit_bytes + lmd_bytes, o, t, &u2);
    free(v2);
    *used = hdr + wbytes + lit_bytes + lmd_bytes;
    return r;
}

/* LZVN: byte opcodes that carry up to three literals, a match length and
 * a distance, or reuse the previous distance. */
static int lzvn_run(const uint8_t *s, size_t n, struct out *o, size_t *used)
{
    size_t i = 0, dist = 0;
    while (i < n) {
        uint8_t b0 = s[i];
        size_t L = 0, M = 0, len;
        long D = -1;
        if (b0 == 0x06) {    /* end of stream: the opcode and seven zero bytes */
            *used = i + 8 <= n ? i + 8 : n;
            return 0;
        }
        if (b0 == 0x0E || b0 == 0x16) {
            i++;
            continue;
        }
        if (b0 == 0x1E || b0 == 0x26 || b0 == 0x2E || b0 == 0x36 || b0 == 0x3E || (b0 >= 0x70 && b0 <= 0x7F) ||
            (b0 >= 0xD0 && b0 <= 0xDF))
            return -1;
        uint8_t b1 = i + 1 < n ? s[i + 1] : 0, b2 = i + 2 < n ? s[i + 2] : 0;
        if (b0 >= 0xE0 && b0 <= 0xEF) {
            if (b0 == 0xE0)
                L = b1 + 16, len = 2;
            else
                L = b0 & 0xF, len = 1;
        } else if (b0 >= 0xF0) {
            if (b0 == 0xF0)
                M = b1 + 16, len = 2;
            else
                M = b0 & 0xF, len = 1;
        } else if (b0 >= 0xA0 && b0 <= 0xBF) {
            M = (((b0 & 7) << 2) | (b1 & 3)) + 3;
            L = (b0 >> 3) & 3;
            D = (b1 >> 2) | b2 << 6;
            len = 3;
        } else if ((b0 & 7) == 7) {
            M = ((b0 >> 3) & 7) + 3;
            L = (b0 >> 6) & 3;
            D = b1 | b2 << 8;
            len = 3;
        } else if ((b0 & 7) == 6) {
            M = ((b0 >> 3) & 7) + 3;
            L = (b0 >> 6) & 3;
            len = 1;
        } else {
            M = ((b0 >> 3) & 7) + 3;
            L = (b0 >> 6) & 3;
            D = (b0 & 7) << 8 | b1;
            len = 2;
        }
        if (i + len + L > n)
            return -1;
        i += len;
        if (L && put_bytes(o, s + i, L))
            return 1;
        i += L;
        if (D >= 0)
            dist = D;
        if (M) {
            int r = put_match(o, M, dist);
            if (r)
                return r == -1 ? 1 : -1;
        }
    }
    return -1;
}

/* A whole LZFSE stream: blocks until 'bvx$'. Returns the bytes written, or
 * 0 on damaged input, as compression_decode_buffer does. */
static size_t lzfse_decode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n)
{
    struct out o = {dst, 0, cap, 0};
    struct fse_tables *t = NULL;
    size_t i = 0;
    while (i + 4 <= n) {
        uint32_t magic = rd32(src + i);
        size_t used = 0;
        int r;
        if (magic == 0x24787662) {    /* bvx$ */
            free(t);
            return o.n;
        } else if (magic == 0x2D787662) {    /* bvx- */
            if (i + 8 > n)
                break;
            uint32_t raw = rd32(src + i + 4);
            if (i + 8 + raw > n)
                break;
            r = put_bytes(&o, src + i + 8, raw) ? 1 : 0;
            used = 8 + raw;
        } else if (magic == 0x6E787662) {    /* bvxn */
            if (i + 12 > n)
                break;
            uint32_t raw = rd32(src + i + 4), pay = rd32(src + i + 8);
            if (i + 12 + pay > n)
                break;
            size_t before = o.n, u;
            r = lzvn_run(src + i + 12, pay, &o, &u);
            if (!r && o.n - before != raw)
                r = -1;
            used = 12 + pay;
        } else if (magic == 0x32787662 || magic == 0x31787662) {    /* bvx2, bvx1 */
            if (!t && !(t = malloc(sizeof *t)))
                break;
            r = magic == 0x32787662 ? lzfse_block_v2(src + i, n - i, &o, t, &used) : lzfse_block_v1(src + i, n - i, &o, t, &used);
        } else
            break;
        if (r > 0) {    /* the caller's buffer is full: what fits is the answer */
            free(t);
            return o.n;
        }
        if (r < 0)
            break;
        i += used;
    }
    free(t);
    /* No end marker: a stream cut short still gives what it held, as a
     * Mac's decoder does when the caller's buffer fills first. */
    return o.full ? o.n : 0;
}

/* ---- LZ4 -------------------------------------------------------------------------- */

static int lz4_block(const uint8_t *s, size_t n, struct out *o)
{
    size_t i = 0;
    while (i < n) {
        uint8_t tok = s[i++];
        size_t L = tok >> 4;
        if (L == 15) {
            uint8_t b;
            do {
                if (i >= n)
                    return -1;
                b = s[i++];
                L += b;
            } while (b == 255);
        }
        if (i + L > n)
            return -1;
        if (put_bytes(o, s + i, L))
            return 1;
        i += L;
        if (i >= n)
            return 0;    /* the last sequence has literals only */
        if (i + 2 > n)
            return -1;
        size_t D = s[i] | s[i + 1] << 8;
        i += 2;
        size_t M = tok & 15;
        if (M == 15) {
            uint8_t b;
            do {
                if (i >= n)
                    return -1;
                b = s[i++];
                M += b;
            } while (b == 255);
        }
        int r = put_match(o, M + 4, D);
        if (r)
            return r == -1 ? 1 : -1;
    }
    return 0;
}

/* A Mac's LZ4 stream: 'bv41' blocks (raw size, payload size, an LZ4 block),
 * 'bv4-' stored blocks, and 'bv4$' at the end. */
static size_t lz4_decode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n)
{
    struct out o = {dst, 0, cap, 0};
    size_t i = 0;
    while (i + 4 <= n) {
        uint32_t magic = rd32(src + i);
        int r;
        if (magic == 0x24347662)    /* bv4$ */
            return o.n;
        if (magic == 0x2D347662) {    /* bv4- */
            if (i + 8 > n)
                break;
            uint32_t raw = rd32(src + i + 4);
            if (i + 8 + raw > n)
                break;
            r = put_bytes(&o, src + i + 8, raw) ? 1 : 0;
            i += 8 + raw;
        } else if (magic == 0x31347662) {    /* bv41 */
            if (i + 12 > n)
                break;
            uint32_t pay = rd32(src + i + 8);
            if (i + 12 + pay > n)
                break;
            r = lz4_block(src + i + 12, pay, &o);
            i += 12 + pay;
        } else
            break;
        if (r > 0)
            return o.n;
        if (r < 0)
            break;
    }
    return o.full ? o.n : 0;
}

/* ---- zlib and LZMA, through this system's libraries ------------------------------ */

typedef struct {
    const uint8_t *next_in;
    unsigned avail_in;
    unsigned long total_in;
    uint8_t *next_out;
    unsigned avail_out;
    unsigned long total_out;
    const char *msg;
    void *state, *zalloc, *zfree, *opaque;
    int data_type;
    unsigned long adler, reserved;
} z_stream_l;

static void *libz(const char *name)
{
    static void *h;
    if (!h)
        h = dlopen("libz.so.1", RTLD_NOW | RTLD_LOCAL);
    return h ? dlsym(h, name) : NULL;
}

static size_t zlib_code(int encode, uint8_t *dst, size_t cap, const uint8_t *src, size_t n)
{
    int (*init)(z_stream_l *, ...) = NULL;
    int (*step)(z_stream_l *, int) = libz(encode ? "deflate" : "inflate");
    int (*end)(z_stream_l *) = libz(encode ? "deflateEnd" : "inflateEnd");
    const char *(*ver)(void) = libz("zlibVersion");
    if (!step || !end || !ver)
        return 0;
    z_stream_l z;
    memset(&z, 0, sizeof z);
    int r;
    if (encode) {
        int (*di)(z_stream_l *, int, int, int, int, int, const char *, int) = libz("deflateInit2_");
        r = di ? di(&z, 5, 8, -15, 8, 0, ver(), (int)sizeof z) : -1;
    } else {
        int (*ii)(z_stream_l *, int, const char *, int) = libz("inflateInit2_");
        r = ii ? ii(&z, -15, ver(), (int)sizeof z) : -1;
    }
    (void)init;
    if (r)
        return 0;
    z.next_in = src;
    z.avail_in = n;
    z.next_out = dst;
    z.avail_out = cap;
    r = step(&z, 4 /* Z_FINISH */);
    size_t out = z.total_out;
    end(&z);
    if (encode)
        return r == 1 /* Z_STREAM_END */ ? out : 0;
    return r == 1 || (r == 0 || r == -5) ? out : 0;
}

static void *liblzma(const char *name)
{
    static void *h;
    if (!h)
        h = dlopen("liblzma.so.5", RTLD_NOW | RTLD_LOCAL);
    return h ? dlsym(h, name) : NULL;
}

static size_t lzma_code(int encode, uint8_t *dst, size_t cap, const uint8_t *src, size_t n)
{
    size_t in_pos = 0, out_pos = 0;
    if (encode) {
        int (*enc)(uint32_t, int, const void *, const uint8_t *, size_t, uint8_t *, size_t *, size_t) =
            liblzma("lzma_easy_buffer_encode");
        return enc && !enc(6, 4 /* CRC64 */, NULL, src, n, dst, &out_pos, cap) ? out_pos : 0;
    }
    uint64_t memlimit = UINT64_MAX;
    int (*dec)(uint64_t *, uint32_t, const void *, const uint8_t *, size_t *, size_t, uint8_t *, size_t *, size_t) =
        liblzma("lzma_stream_buffer_decode");
    if (!dec)
        return 0;
    int r = dec(&memlimit, 0, NULL, src, &in_pos, n, dst, &out_pos, cap);
    return r == 0 || r == 10 /* LZMA_BUF_ERROR: dst full */ ? out_pos : 0;
}

/* ---- the calls --------------------------------------------------------------------- */

size_t ferry_compression_decode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n, int algorithm)
{
    if (!dst || !src || !cap)
        return 0;
    switch (algorithm) {
    case COMPRESSION_LZFSE:
        return lzfse_decode(dst, cap, src, n);
    case COMPRESSION_LZ4:
        return lz4_decode(dst, cap, src, n);
    case COMPRESSION_LZ4_RAW: {
        struct out o = {dst, 0, cap, 0};
        int r = lz4_block(src, n, &o);
        return r >= 0 ? o.n : 0;
    }
    case COMPRESSION_ZLIB:
        return zlib_code(0, dst, cap, src, n);
    case COMPRESSION_LZMA:
        return lzma_code(0, dst, cap, src, n);
    }
    return 0;
}

/* LZVN alone, without a block header (as asset catalogs keep it). */
size_t ferry_lzvn_decode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n)
{
    struct out o = {dst, 0, cap, 0};
    size_t used;
    int r = lzvn_run(src, n, &o, &used);
    return r >= 0 ? o.n : 0;
}

static size_t compression_decode_buffer(uint8_t *dst, size_t cap, const uint8_t *src, size_t n, void *scratch, int algorithm)
{
    return ferry_compression_decode(dst, cap, src, n, algorithm);
}

static size_t stored_blocks(uint8_t *dst, size_t cap, const uint8_t *src, size_t n, uint32_t block, uint32_t end)
{
    size_t o = 0;
    for (size_t i = 0; i < n || (!n && !o);) {
        size_t part = n - i < 0x100000 ? n - i : 0x100000;
        if (o + 8 + part > cap)
            return 0;
        memcpy(dst + o, &block, 4);
        uint32_t p = part;
        memcpy(dst + o + 4, &p, 4);
        memcpy(dst + o + 8, src + i, part);
        o += 8 + part;
        i += part;
        if (!n)
            break;
    }
    if (o + 4 > cap)
        return 0;
    memcpy(dst + o, &end, 4);
    return o + 4;
}

static size_t compression_encode_buffer(uint8_t *dst, size_t cap, const uint8_t *src, size_t n, void *scratch, int algorithm)
{
    if (!dst)
        return 0;
    switch (algorithm) {
    case COMPRESSION_LZFSE:
        return stored_blocks(dst, cap, src, n, 0x2D787662, 0x24787662);
    case COMPRESSION_LZ4:
        return stored_blocks(dst, cap, src, n, 0x2D347662, 0x24347662);
    case COMPRESSION_ZLIB:
        return zlib_code(1, dst, cap, src, n);
    case COMPRESSION_LZMA:
        return lzma_code(1, dst, cap, src, n);
    }
    return 0;
}

static size_t compression_encode_scratch_buffer_size(int algorithm) { return 1; }
static size_t compression_decode_scratch_buffer_size(int algorithm) { return 1; }

const struct ferry_symbol ferry_compression_symbols[] = {
    {"compression_decode_buffer", compression_decode_buffer},
    {"compression_encode_buffer", compression_encode_buffer},
    {"compression_encode_scratch_buffer_size", compression_encode_scratch_buffer_size},
    {"compression_decode_scratch_buffer_size", compression_decode_scratch_buffer_size},
    {NULL, NULL},
};
