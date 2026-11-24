/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Unwind tables of Mac images, for this system's C++ unwinder (src/cxx.c).
 *
 * The unwinder that throws C++ exceptions (LLVM's libunwind) reads DWARF
 * call frame information: a CIE and an FDE for each function, as in a
 * Linux program's .eh_frame. A Mac image describes most of its functions
 * in its compact unwind table instead ("__unwind_info", one 32-bit
 * encoding per function) and only the rest in "__eh_frame". This file
 * writes, for every function the compact table describes, the FDE that
 * says the same thing, and hands it to the unwinder with the FDEs the
 * image's own __eh_frame holds. The unwinder then walks Mac frames as it
 * walks Linux ones, calling each function's own personality routine with
 * its LSDA.
 *
 * The rules come from the public descriptions of the formats: the compact
 * encoding as LLVM's compact_unwind_encoding.h and Apple's Mach-O
 * documentation describe it (and as Ferry's own unwinder, objc/exception.c,
 * reads it), DWARF call frames from the DWARF standard and the Linux
 * Standard Base. A compact encoding describes a function at its call
 * sites, after its prologue, which is where an exception passes, so each
 * FDE gives one rule for the whole function.
 */
#include <stdlib.h>
#include <string.h>

#include "cxx.h"
#include "ferry.h"

static uint32_t u32(const uint8_t *p)
{
    uint32_t v;
    memcpy(&v, p, 4);
    return v;
}
static uint16_t u16(const uint8_t *p)
{
    uint16_t v;
    memcpy(&v, p, 2);
    return v;
}

enum {
    HAS_LSDA = 0x40000000, PERSONALITY_MASK = 0x30000000, MODE_MASK = 0x0f000000,
    MODE_RBP_FRAME = 0x01000000, MODE_STACK_IMMD = 0x02000000, MODE_STACK_IND = 0x03000000,
    MODE_DWARF = 0x04000000,
};

/* compact register numbers 1-6 as DWARF numbers them */
static const uint8_t dwarf_reg[7] = {0, 3, 12, 13, 14, 15, 6};

/* the frameless encodings number their saved registers as a permutation */
static void decode_permutation(uint32_t perm, int count, int regs[6])
{
    static const int base[7][6] = {
        {0}, {1}, {5, 1}, {20, 4, 1}, {60, 12, 3, 1}, {120, 24, 6, 2, 1}, {120, 24, 6, 2, 1, 1},
    };
    int digit[6] = {0}, used[7] = {0};
    for (int i = 0; i < count; i++) {
        digit[i] = (int)(perm / (uint32_t)base[count][i]);
        perm -= (uint32_t)(digit[i] * base[count][i]);
    }
    for (int i = 0; i < count; i++)
        for (int r = 1, k = 0; r <= 6; r++)
            if (!used[r]) {
                if (k++ == digit[i]) {
                    regs[i] = r;
                    used[r] = 1;
                    break;
                }
            }
}

/* ---- writing CIEs and FDEs ------------------------------------------------------- */

struct out {
    uint8_t *buf;
    size_t len, cap;
};

static void put(struct out *o, const void *p, size_t n)
{
    if (o->len + n > o->cap) {
        o->cap = (o->len + n) * 2 + 256;
        o->buf = realloc(o->buf, o->cap);
    }
    memcpy(o->buf + o->len, p, n);
    o->len += n;
}
static void put8(struct out *o, uint8_t v) { put(o, &v, 1); }
static void put32(struct out *o, uint32_t v) { put(o, &v, 4); }
static void put64(struct out *o, uint64_t v) { put(o, &v, 8); }
static void uleb(struct out *o, uint64_t v)
{
    do {
        uint8_t b = v & 0x7f;
        v >>= 7;
        put8(o, (uint8_t)(b | (v ? 0x80 : 0)));
    } while (v);
}
static void pad8(struct out *o)
{
    while (o->len % 8)
        put8(o, 0);   /* DW_CFA_nop */
}
static void patch32(struct out *o, size_t at, uint32_t v) { memcpy(o->buf + at, &v, 4); }

/* A CIE: return address at CFA-8, CFA = %rsp+8 on entry; with a
 * personality (the address of the image's pointer to it) and LSDAs when
 * personality_slot isn't 0. Pointers are absolute. */
static size_t write_cie(struct out *o, uint64_t personality_slot)
{
    size_t at = o->len;
    put32(o, 0);                          /* length, patched */
    put32(o, 0);                          /* CIE id */
    put8(o, 1);                           /* version */
    const char *aug = personality_slot ? "zPLR" : "zR";
    put(o, aug, strlen(aug) + 1);
    uleb(o, 1);                           /* code alignment */
    put8(o, 0x78);                        /* data alignment -8 (sleb) */
    put8(o, 16);                          /* return address register */
    if (personality_slot) {
        uleb(o, 1 + 8 + 1 + 1);
        put8(o, 0x80);                    /* DW_EH_PE_indirect | absptr */
        put64(o, personality_slot);
        put8(o, 0x00);                    /* LSDA: absptr */
        put8(o, 0x00);                    /* FDE pointers: absptr */
    } else {
        uleb(o, 1);
        put8(o, 0x00);
    }
    put8(o, 0x0c), put8(o, 7), put8(o, 8); /* def_cfa %rsp+8 */
    put8(o, 0x80 | 16), put8(o, 1);        /* return address at CFA-8 */
    pad8(o);
    patch32(o, at, (uint32_t)(o->len - at - 4));
    return at;
}

/* An FDE for the function [start, end) with encoding enc. */
static int write_fde(struct out *o, size_t cie_at, int with_personality, uint64_t start, uint64_t end,
                     uint64_t lsda, uint32_t enc)
{
    struct out ins = {0};
    switch (enc & MODE_MASK) {
    case MODE_RBP_FRAME: {
        uint32_t off = (enc >> 16) & 0xff, regs = enc & 0x7fff;
        put8(&ins, 0x0c), put8(&ins, 6), put8(&ins, 16);   /* def_cfa %rbp+16 */
        put8(&ins, 0x80 | 6), put8(&ins, 2);               /* %rbp at CFA-16 */
        for (int i = 0; i < 5; i++) {
            unsigned r = (regs >> (3 * i)) & 7;
            if (r >= 1 && r <= 6 && (int)(2 + off) - i > 0)
                put8(&ins, (uint8_t)(0x80 | dwarf_reg[r])), uleb(&ins, (uint64_t)(2 + off - (uint32_t)i));
        }
        break;
    }
    case MODE_STACK_IMMD:
    case MODE_STACK_IND: {
        uint64_t size = (enc >> 16) & 0xff;
        if ((enc & MODE_MASK) == MODE_STACK_IND)
            size = u32((const uint8_t *)(start + size)) + ((enc >> 13) & 7) * 8;
        else
            size *= 8;
        int count = (int)((enc >> 10) & 7), regs[6] = {0};
        if (count > 6 || size < 8)
            return 0;
        decode_permutation(enc & 0x3ff, count, regs);
        put8(&ins, 0x0e), uleb(&ins, size);                /* def_cfa_offset */
        for (int i = 0; i < count; i++)
            if (regs[i] >= 1 && regs[i] <= 6)
                put8(&ins, (uint8_t)(0x80 | dwarf_reg[regs[i]])), uleb(&ins, (uint64_t)(1 + count - i));
        break;
    }
    default:
        return 0;
    }
    size_t at = o->len;
    put32(o, 0);
    put32(o, (uint32_t)(o->len - cie_at));                 /* back to the CIE */
    put64(o, start);
    put64(o, end - start);
    if (with_personality) {
        uleb(o, 8);
        put64(o, lsda);
    } else {
        uleb(o, 0);
    }
    put(o, ins.buf, ins.len);
    free(ins.buf);
    pad8(o);
    patch32(o, at, (uint32_t)(o->len - at - 4));
    return 1;
}

/* ---- reading the compact table ------------------------------------------------- */

int ferry_cxx_describe_image(uint64_t header, void (*add_fde)(const void *fde))
{
    struct ferry_unwind_sections s;
    if (!ferry_find_unwind(header, &s))
        return 0;
    int count = 0;
    /* the image's own DWARF descriptions, as they are (their pointers are
     * relative to where they sit, so they hold wherever the image is) */
    if (s.eh_frame) {
        const uint8_t *p = s.eh_frame, *end = s.eh_frame + s.eh_size;
        while (p + 8 <= end) {
            uint32_t len = u32(p);
            if (len == 0 || len == 0xffffffff || p + 4 + len > end)
                break;
            if (u32(p + 4)) {
                add_fde(p);
                count++;
            }
            p += 4 + len;
        }
    }
    const uint8_t *ui = s.unwind_info;
    if (!ui || s.unwind_size < 28 || u32(ui) != 1)
        return count;
    uint32_t common_off = u32(ui + 4), ncommon = u32(ui + 8);
    uint32_t pers_off = u32(ui + 12), npers = u32(ui + 16);
    uint32_t index_off = u32(ui + 20), nindex = u32(ui + 24);
    if (npers > 3)
        npers = 3;
    struct out o = {0};
    size_t cie[4];
    cie[0] = write_cie(&o, 0);
    for (uint32_t i = 0; i < npers; i++)
        cie[i + 1] = write_cie(&o, s.base + u32(ui + pers_off + i * 4));
    size_t first_fde = o.len;
    const uint8_t *idx = ui + index_off;
    for (uint32_t k = 0; k + 1 < nindex; k++) {
        const uint8_t *e = idx + k * 12;
        uint32_t first_fn = u32(e), page_off = u32(e + 4), lsda_off = u32(e + 8);
        uint32_t next_fn = u32(e + 12), next_lsda = u32(e + 20);
        if (!page_off)
            continue;
        const uint8_t *page = ui + page_off;
        uint32_t kind = u32(page);
        uint16_t eoff = u16(page + 4), n = u16(page + 6);
        const uint8_t *ents = page + eoff;
        for (int i = 0; i < n; i++) {
            uint32_t fn, fn_end, enc = 0;
            if (kind == 2) {
                fn = u32(ents + i * 8);
                enc = u32(ents + i * 8 + 4);
                fn_end = i + 1 < n ? u32(ents + (i + 1) * 8) : next_fn;
            } else if (kind == 3) {
                uint16_t encs_off = u16(page + 8), nencs = u16(page + 10);
                uint32_t ent = u32(ents + i * 4);
                fn = first_fn + (ent & 0xffffff);
                fn_end = i + 1 < n ? first_fn + (u32(ents + (i + 1) * 4) & 0xffffff) : next_fn;
                uint32_t ei = ent >> 24;
                if (ei < ncommon)
                    enc = u32(ui + common_off + ei * 4);
                else if (ei - ncommon < nencs)
                    enc = u32(page + encs_off + (ei - ncommon) * 4);
            } else {
                break;
            }
            uint32_t mode = enc & MODE_MASK;
            if (!enc || mode == MODE_DWARF || fn_end <= fn)
                continue;
            uint32_t pi = (enc & PERSONALITY_MASK) >> 28;
            if (pi > npers)
                pi = 0;
            uint64_t lsda = 0;
            if (enc & HAS_LSDA)
                for (uint32_t q = lsda_off; q + 8 <= next_lsda; q += 8)
                    if (u32(ui + q) == fn) {
                        lsda = s.base + u32(ui + q + 4);
                        break;
                    }
            if (write_fde(&o, cie[pi], pi != 0, s.base + fn, s.base + fn_end, lsda, enc))
                count++;
        }
    }
    put32(&o, 0);   /* the end of the section */
    /* the unwinder keeps pointers into these for as long as the image is loaded */
    for (size_t p = first_fde; p + 8 <= o.len;) {
        uint32_t len = u32(o.buf + p);
        if (!len)
            break;
        add_fde(o.buf + p);
        p += 4 + len;
    }
    return count;
}
