/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Objective-C exceptions: @throw, @try/@catch/@finally, and the
 * stack unwinder they need for Mac (Mach-O) code.
 *
 * A Mac compiler describes how to unwind each function in two tables of
 * the image: "__unwind_info" (Apple's compact unwind format, one 32-bit
 * encoding per function) and "__eh_frame" (DWARF call frame information,
 * for the functions the compact form can't describe). Functions with
 * @catch or cleanups also name a personality routine and point at a
 * "language-specific data area" (LSDA, the call-site, action and type
 * tables of the Itanium C++ ABI's exception handling). All three are
 * public formats: the compact encoding as described in LLVM's
 * compact_unwind_encoding.h and Apple's mach-o documentation, DWARF call
 * frames in the DWARF standard and the Linux Standard Base, the LSDA and
 * the two-phase unwinding protocol in the Itanium C++ ABI. This file is
 * written from those descriptions; no Apple or LLVM code was used.
 *
 * Throwing captures the thrower's registers (unwind.S), searches up the
 * stack for a frame whose @catch matches (phase 1), then walks the stack
 * again running cleanups (@finally, ARC releases) on the way, and jumps
 * into the handler (phase 2). Only Mac frames can be unwound: if the walk
 * reaches code that isn't in a Mach-O image (a callback from this system's
 * libraries, say) before a handler, the exception is uncaught, and the
 * program ends as a Mac program does, through the uncaught-exception
 * handler. The exceptions being caught are kept per thread: each thread
 * unwinds only its own stack.
 *
 * A program that uses C++ (src/cxx.c) brings in this system's C++ runtime
 * and its unwinder, which then unwinds every exception, Objective-C ones
 * too, through Mac and Linux frames alike: @throw raises the exception
 * through it, and the Objective-C personality routine below answers for
 * each frame from its LSDA, as the Itanium C++ ABI lays down. A C++
 * exception passing an Objective-C frame is left to the C++ personality
 * where the frame catches nothing Objective-C; @catch (...) and catch (...)
 * catch either kind.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../cxx.h"
#include "../ferry.h"
#include "objc-private.h"

/* ---- registers ---------------------------------------------------------------- */

/* Numbered as DWARF numbers them for x86-64; 16 is the return address. */
enum { R_RAX = 0, R_RDX = 1, R_RCX = 2, R_RBX = 3, R_RSI = 4, R_RDI = 5, R_RBP = 6, R_RSP = 7, R_R12 = 12,
       R_R13 = 13, R_R14 = 14, R_R15 = 15, R_RIP = 16, NREGS = 17 };
struct uctx { uint64_t r[NREGS]; };

/* unwind.S */
__attribute__((noreturn)) void ferry_unwind_jump(const struct uctx *c);

/* ---- the exception object ------------------------------------------------------- */

/* What the landing pads receive in %rax and hand back to objc_begin_catch
 * and _Unwind_Resume. Laid out like the Itanium ABI's _Unwind_Exception
 * header, then Ferry's own fields. */
struct exc {
    uint64_t exception_class;
    void (*cleanup)(int, struct exc *);
    uint64_t private1, private2;
    id obj;
    uint64_t handler_sp;     /* the frame phase 1 chose */
    struct exc *next_caught;
};
#define FERRY_EXC_CLASS 0x464552524f424a43ull   /* "FERROBJC" */

static __thread struct exc *caught;   /* exceptions whose @catch is running, innermost first */

/* ---- @catch types ------------------------------------------------------------------ */

/* A @catch (Foo *e) names Foo's "EH type": {objc_ehtype_vtable + 2, "Foo",
 * Foo's class}. @catch (id e) names OBJC_EHTYPE_id, whose class is nil.
 *
 * Once a program uses C++, this system's C++ personality reads the catch
 * clauses of a frame a C++ exception passes, Objective-C ones included, and
 * asks each clause's type whether it takes the exception through the type's
 * vtable, as for a std::type_info. So past the two words before it, the
 * vtable here answers as a type that takes nothing: in LLVM's libc++abi the
 * slots are two destructors, two empty hooks, can_catch, two searches for
 * dynamic_cast and a base-class check, and each of them here does nothing
 * and returns 0 (can_catch's false). */
static long ehtype_nothing(void)
{
    return 0;
}
const void *objc_ehtype_vtable[10] = {
    NULL, NULL, (void *)ehtype_nothing, (void *)ehtype_nothing, (void *)ehtype_nothing, (void *)ehtype_nothing,
    (void *)ehtype_nothing, (void *)ehtype_nothing, (void *)ehtype_nothing, (void *)ehtype_nothing,
};
const struct ferry_ehtype OBJC_EHTYPE_id = {&objc_ehtype_vtable[2], "id", NULL};
const struct ferry_ehtype ferry_ehtype_missing = {&objc_ehtype_vtable[2], "(missing)", NULL};

/* foreign: a C++ exception, which only a catch-all catches */
static int catches(const struct ferry_ehtype *t, id obj, int foreign)
{
    if (!t)
        return 1;   /* catch-all: @catch (...) or C++ catch (...) */
    if (foreign)
        return 0;
    if (t->vtable != &objc_ehtype_vtable[2] || t == &ferry_ehtype_missing)
        return 0;   /* a C++ type, or a class Ferry left out */
    if (!t->cls)
        return 1;   /* id */
    for (Class c = obj ? object_getClass(obj) : NULL; c; c = c->superclass)
        if (c == (Class)t->cls)
            return 1;
    return 0;
}

/* ---- reading the tables ---------------------------------------------------------- */

static uint64_t uleb(const uint8_t **p)
{
    uint64_t v = 0;
    int shift = 0;
    uint8_t b;
    do {
        b = *(*p)++;
        if (shift < 64)
            v |= (uint64_t)(b & 0x7f) << shift;
        shift += 7;
    } while (b & 0x80);
    return v;
}

static int64_t sleb(const uint8_t **p)
{
    int64_t v = 0;
    int shift = 0;
    uint8_t b;
    do {
        b = *(*p)++;
        if (shift < 64)
            v |= (int64_t)(b & 0x7f) << shift;
        shift += 7;
    } while (b & 0x80);
    if (shift < 64 && (b & 0x40))
        v |= -((int64_t)1 << shift);
    return v;
}

/* DWARF pointer encodings (DW_EH_PE_*) */
enum { PE_OMIT = 0xff, PE_ABSPTR = 0, PE_ULEB = 1, PE_UDATA2 = 2, PE_UDATA4 = 3, PE_UDATA8 = 4, PE_SLEB = 9,
       PE_SDATA2 = 0xa, PE_SDATA4 = 0xb, PE_SDATA8 = 0xc, PE_PCREL = 0x10, PE_INDIRECT = 0x80 };

static uint64_t read_ptr(const uint8_t **p, uint8_t enc)
{
    const uint8_t *start = *p;
    uint64_t v = 0;
    if (enc == PE_OMIT)
        return 0;
    switch (enc & 0x0f) {
    case PE_ABSPTR: case PE_UDATA8: case PE_SDATA8: memcpy(&v, *p, 8); *p += 8; break;
    case PE_ULEB: v = uleb(p); break;
    case PE_SLEB: v = (uint64_t)sleb(p); break;
    case PE_UDATA2: { uint16_t x; memcpy(&x, *p, 2); v = x; *p += 2; break; }
    case PE_SDATA2: { int16_t x; memcpy(&x, *p, 2); v = (uint64_t)(int64_t)x; *p += 2; break; }
    case PE_UDATA4: { uint32_t x; memcpy(&x, *p, 4); v = x; *p += 4; break; }
    case PE_SDATA4: { int32_t x; memcpy(&x, *p, 4); v = (uint64_t)(int64_t)x; *p += 4; break; }
    default: return 0;
    }
    if (v && (enc & 0x70) == PE_PCREL)
        v += (uint64_t)start;
    if (v && (enc & PE_INDIRECT))
        v = *(const uint64_t *)v;
    return v;
}

static size_t ptr_size(uint8_t enc)
{
    switch (enc & 0x0f) {
    case PE_UDATA2: case PE_SDATA2: return 2;
    case PE_UDATA4: case PE_SDATA4: return 4;
    default: return 8;
    }
}

/* ---- finding a function's unwind information -------------------------------------- */

struct finfo {
    uint64_t start, end;          /* the function */
    uint64_t personality, lsda;
    uint32_t encoding;            /* compact; 0 with an FDE */
    const uint8_t *fde;           /* DWARF, or NULL */
    const uint8_t *eh_frame;
    size_t eh_size;
};

enum {
    UNWIND_HAS_LSDA = 0x40000000, UNWIND_PERSONALITY_MASK = 0x30000000, UNWIND_MODE_MASK = 0x0f000000,
    MODE_RBP_FRAME = 0x01000000, MODE_STACK_IMMD = 0x02000000, MODE_STACK_IND = 0x03000000,
    MODE_DWARF = 0x04000000,
};

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

/* Parses the CIE and FDE at fde; fills in what the FDE says about the
 * function, and where its instructions are. */
struct cie {
    uint64_t code_align;
    int64_t data_align;
    uint64_t ra_reg;
    uint8_t fde_enc, lsda_enc;
    uint64_t personality;
    const uint8_t *insns, *insns_end;
};

static int parse_fde(const uint8_t *fde, struct cie *cie, struct finfo *fi, const uint8_t **insns,
                     const uint8_t **insns_end)
{
    uint32_t len = u32(fde);
    if (len == 0 || len == 0xffffffff)
        return 0;
    const uint8_t *p = fde + 4;
    uint32_t cie_off = u32(p);
    if (!cie_off)
        return 0;   /* that's a CIE */
    const uint8_t *c = p - cie_off;
    uint32_t clen = u32(c);
    const uint8_t *cend = c + 4 + clen, *q = c + 8;
    uint8_t version = *q++;
    const char *aug = (const char *)q;
    q += strlen(aug) + 1;
    memset(cie, 0, sizeof *cie);
    cie->fde_enc = PE_ABSPTR;
    cie->lsda_enc = PE_OMIT;
    cie->code_align = uleb(&q);
    cie->data_align = sleb(&q);
    cie->ra_reg = version == 1 ? *q++ : uleb(&q);
    if (aug[0] == 'z') {
        uint64_t alen = uleb(&q);
        const uint8_t *aend = q + alen;
        for (const char *a = aug + 1; *a; a++) {
            if (*a == 'P') {
                uint8_t enc = *q++;
                cie->personality = read_ptr(&q, enc);
            } else if (*a == 'L') {
                cie->lsda_enc = *q++;
            } else if (*a == 'R') {
                cie->fde_enc = *q++;
            }
        }
        q = aend;
    }
    cie->insns = q;
    cie->insns_end = cend;
    p += 4;
    fi->start = read_ptr(&p, cie->fde_enc);
    fi->end = fi->start + read_ptr(&p, cie->fde_enc & 0x0f);
    if (aug[0] == 'z') {
        uint64_t alen = uleb(&p);
        const uint8_t *aend = p + alen;
        if (cie->lsda_enc != PE_OMIT)
            fi->lsda = read_ptr(&p, cie->lsda_enc);
        p = aend;
    }
    fi->personality = cie->personality;
    *insns = p;
    *insns_end = fde + 4 + len;
    return 1;
}

/* The FDE covering pc, by reading the whole __eh_frame section. */
static const uint8_t *find_fde(const uint8_t *eh, size_t size, uint64_t pc)
{
    const uint8_t *p = eh, *end = eh + size;
    while (p + 8 <= end) {
        uint32_t len = u32(p);
        if (len == 0 || len == 0xffffffff)
            break;
        if (u32(p + 4)) {
            struct cie cie;
            struct finfo fi = {0};
            const uint8_t *a, *b;
            if (parse_fde(p, &cie, &fi, &a, &b) && pc >= fi.start && pc < fi.end)
                return p;
        }
        p += 4 + len;
    }
    return NULL;
}

static int lookup(uint64_t pc, struct finfo *fi)
{
    struct ferry_unwind_sections s;
    memset(fi, 0, sizeof *fi);
    if (!ferry_find_unwind(pc, &s))
        return 0;
    fi->eh_frame = s.eh_frame;
    fi->eh_size = s.eh_size;
    const uint8_t *ui = s.unwind_info;
    if (ui && s.unwind_size >= 28 && u32(ui) == 1) {
        uint32_t common_off = u32(ui + 4), ncommon = u32(ui + 8);
        uint32_t pers_off = u32(ui + 12), npers = u32(ui + 16);
        uint32_t index_off = u32(ui + 20), nindex = u32(ui + 24);
        uint32_t target = (uint32_t)(pc - s.base);
        /* first level: the last entry starting at or before pc (the final
         * entry only marks the end) */
        const uint8_t *idx = ui + index_off;
        int lo = 0, hi = (int)nindex - 2, found = -1;
        while (lo <= hi) {
            int mid = (lo + hi) / 2;
            if (u32(idx + mid * 12) <= target) {
                found = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        if (found >= 0) {
            const uint8_t *e = idx + found * 12;
            uint32_t first_fn = u32(e), page_off = u32(e + 4), lsda_off = u32(e + 8);
            uint32_t next_fn = u32(e + 12), next_lsda = u32(e + 20);
            const uint8_t *page = ui + page_off;
            uint32_t kind = page_off ? u32(page) : 0;
            uint32_t fn = 0, fn_end = next_fn, enc = 0;
            int have = 0;
            if (kind == 2) { /* regular: {function offset, encoding} pairs */
                uint16_t eoff = u16(page + 4), n = u16(page + 6);
                const uint8_t *ents = page + eoff;
                for (int i = n - 1; i >= 0; i--)
                    if (u32(ents + i * 8) <= target) {
                        fn = u32(ents + i * 8);
                        enc = u32(ents + i * 8 + 4);
                        fn_end = i + 1 < n ? u32(ents + (i + 1) * 8) : next_fn;
                        have = 1;
                        break;
                    }
            } else if (kind == 3) { /* compressed: 24-bit offset from the first function, 8-bit encoding index */
                uint16_t eoff = u16(page + 4), n = u16(page + 6);
                uint16_t encs_off = u16(page + 8), nencs = u16(page + 10);
                const uint8_t *ents = page + eoff;
                for (int i = n - 1; i >= 0; i--) {
                    uint32_t ent = u32(ents + i * 4);
                    if (first_fn + (ent & 0xffffff) <= target) {
                        fn = first_fn + (ent & 0xffffff);
                        fn_end = i + 1 < n ? first_fn + (u32(ents + (i + 1) * 4) & 0xffffff) : next_fn;
                        uint32_t ei = ent >> 24;
                        if (ei < ncommon)
                            enc = u32(ui + common_off + ei * 4);
                        else if (ei - ncommon < nencs)
                            enc = u32(page + encs_off + (ei - ncommon) * 4);
                        have = 1;
                        break;
                    }
                }
            }
            if (have && enc) {
                fi->start = s.base + fn;
                fi->end = s.base + fn_end;
                fi->encoding = enc;
                uint32_t pi = (enc & UNWIND_PERSONALITY_MASK) >> 28;
                if (pi && pi <= npers)
                    fi->personality = *(const uint64_t *)(s.base + u32(ui + pers_off + (pi - 1) * 4));
                if (enc & UNWIND_HAS_LSDA) {
                    /* {function offset, LSDA offset} pairs, sorted */
                    for (uint32_t o = lsda_off; o + 8 <= next_lsda; o += 8)
                        if (u32(ui + o) == fn) {
                            fi->lsda = s.base + u32(ui + o + 4);
                            break;
                        }
                }
                if ((enc & UNWIND_MODE_MASK) == MODE_DWARF) {
                    fi->fde = s.eh_frame ? s.eh_frame + (enc & 0xffffff) : NULL;
                    if (fi->fde) {
                        struct cie cie;
                        const uint8_t *a, *b;
                        struct finfo f2 = {0};
                        if (parse_fde(fi->fde, &cie, &f2, &a, &b)) {
                            fi->start = f2.start;
                            fi->end = f2.end;
                            fi->personality = f2.personality;
                            fi->lsda = f2.lsda;
                        }
                    }
                }
                return 1;
            }
        }
    }
    /* not in the compact table: look for DWARF information */
    if (s.eh_frame) {
        const uint8_t *fde = find_fde(s.eh_frame, s.eh_size, pc);
        if (fde) {
            struct cie cie;
            const uint8_t *a, *b;
            if (parse_fde(fde, &cie, fi, &a, &b)) {
                fi->fde = fde;
                fi->encoding = MODE_DWARF;
                return 1;
            }
        }
    }
    return 0;
}

/* ---- stepping to the caller ------------------------------------------------------- */

static uint64_t *compact_reg(struct uctx *c, unsigned n)
{
    static const int map[7] = {-1, R_RBX, R_R12, R_R13, R_R14, R_R15, R_RBP};
    return n >= 1 && n <= 6 ? &c->r[map[n]] : NULL;
}

/* Undoes the factorial-number-system numbering of the frameless encodings'
 * saved registers: perm picks, in turn, one of the registers not yet used. */
static void decode_permutation(uint32_t perm, int count, int regs[6])
{
    int digit[6] = {0};
    static const int base[7][6] = {
        {0}, {1}, {5, 1}, {20, 4, 1}, {60, 12, 3, 1}, {120, 24, 6, 2, 1}, {120, 24, 6, 2, 1, 1},
    };
    for (int i = 0; i < count; i++) {
        digit[i] = (int)(perm / (uint32_t)base[count][i]);
        perm -= (uint32_t)(digit[i] * base[count][i]);
    }
    int used[7] = {0};
    for (int i = 0; i < count; i++) {
        int k = 0;
        for (int r = 1; r <= 6; r++)
            if (!used[r]) {
                if (k == digit[i]) {
                    regs[i] = r;
                    used[r] = 1;
                    break;
                }
                k++;
            }
    }
}

/* DWARF call frame rules */
enum { RULE_SAME, RULE_UNDEF, RULE_OFFSET, RULE_REG };
struct rules {
    int cfa_reg;
    int64_t cfa_off;
    struct { int how; int64_t val; } reg[NREGS];
};

static int run_cfa(const uint8_t *p, const uint8_t *end, const struct cie *cie, uint64_t loc, uint64_t pc,
                   struct rules *r, const struct rules *initial)
{
    struct rules stack[8];
    int depth = 0;
    while (p < end && loc <= pc) {
        uint8_t op = *p++;
        uint64_t a, b;
        switch (op & 0xc0) {
        case 0x40: loc += (op & 0x3f) * cie->code_align; continue;
        case 0x80:
            a = op & 0x3f;
            b = uleb(&p);
            if (a < NREGS)
                r->reg[a].how = RULE_OFFSET, r->reg[a].val = (int64_t)b * cie->data_align;
            continue;
        case 0xc0:
            a = op & 0x3f;
            if (a < NREGS && initial)
                r->reg[a] = initial->reg[a];
            continue;
        }
        switch (op) {
        case 0x00: break;                                           /* nop */
        case 0x01: loc = read_ptr(&p, cie->fde_enc); break;         /* set_loc */
        case 0x02: loc += *p++ * cie->code_align; break;
        case 0x03: loc += u16(p) * cie->code_align; p += 2; break;
        case 0x04: loc += u32(p) * cie->code_align; p += 4; break;
        case 0x05:                                                  /* offset_extended */
            a = uleb(&p), b = uleb(&p);
            if (a < NREGS)
                r->reg[a].how = RULE_OFFSET, r->reg[a].val = (int64_t)b * cie->data_align;
            break;
        case 0x06: a = uleb(&p); if (a < NREGS && initial) r->reg[a] = initial->reg[a]; break;
        case 0x07: a = uleb(&p); if (a < NREGS) r->reg[a].how = RULE_UNDEF; break;
        case 0x08: a = uleb(&p); if (a < NREGS) r->reg[a].how = RULE_SAME; break;
        case 0x09:
            a = uleb(&p), b = uleb(&p);
            if (a < NREGS)
                r->reg[a].how = RULE_REG, r->reg[a].val = (int64_t)b;
            break;
        case 0x0a: if (depth < 8) stack[depth++] = *r; break;      /* remember_state */
        case 0x0b:                                                  /* restore_state */
            if (depth) {
                int cr = r->cfa_reg;
                int64_t co = r->cfa_off;
                *r = stack[--depth];
                r->cfa_reg = cr, r->cfa_off = co;
            }
            break;
        case 0x0c: r->cfa_reg = (int)uleb(&p); r->cfa_off = (int64_t)uleb(&p); break;
        case 0x0d: r->cfa_reg = (int)uleb(&p); break;
        case 0x0e: r->cfa_off = (int64_t)uleb(&p); break;
        case 0x11:                                                  /* offset_extended_sf */
            a = uleb(&p);
            {
                int64_t off = sleb(&p) * cie->data_align;
                if (a < NREGS)
                    r->reg[a].how = RULE_OFFSET, r->reg[a].val = off;
            }
            break;
        case 0x12: r->cfa_reg = (int)uleb(&p); r->cfa_off = sleb(&p) * cie->data_align; break;
        case 0x13: r->cfa_off = sleb(&p) * cie->data_align; break;
        case 0x2e: uleb(&p); break;                                 /* GNU_args_size */
        default:
            return 0;   /* expressions and the rest: not described here */
        }
    }
    return 1;
}

static int step_dwarf(struct uctx *c, const struct finfo *fi, uint64_t pc)
{
    struct cie cie;
    struct finfo f = {0};
    const uint8_t *insns, *insns_end;
    if (!fi->fde || !parse_fde(fi->fde, &cie, &f, &insns, &insns_end))
        return 0;
    struct rules r;
    memset(&r, 0, sizeof r);
    if (!run_cfa(cie.insns, cie.insns_end, &cie, f.start, (uint64_t)-1, &r, NULL))
        return 0;
    struct rules initial = r;
    if (!run_cfa(insns, insns_end, &cie, f.start, pc, &r, &initial))
        return 0;
    if (r.cfa_reg < 0 || r.cfa_reg >= NREGS)
        return 0;
    uint64_t cfa = c->r[r.cfa_reg] + (uint64_t)r.cfa_off;
    struct uctx n = *c;
    for (int i = 0; i < NREGS; i++) {
        if (r.reg[i].how == RULE_OFFSET)
            n.r[i] = *(const uint64_t *)(cfa + (uint64_t)r.reg[i].val);
        else if (r.reg[i].how == RULE_REG && r.reg[i].val < NREGS)
            n.r[i] = c->r[r.reg[i].val];
    }
    if (cie.ra_reg != R_RIP || r.reg[R_RIP].how != RULE_OFFSET)
        return 0;
    n.r[R_RSP] = cfa;
    *c = n;
    return 1;
}

static int step(struct uctx *c, const struct finfo *fi, uint64_t pc)
{
    uint32_t enc = fi->encoding;
    switch (enc & UNWIND_MODE_MASK) {
    case MODE_RBP_FRAME: {
        uint64_t rbp = c->r[R_RBP];
        uint64_t saved = rbp - ((enc >> 16) & 0xff) * 8;
        uint32_t regs = enc & 0x7fff;
        for (int i = 0; i < 5; i++, saved += 8) {
            uint64_t *reg = compact_reg(c, (regs >> (3 * i)) & 7);
            if (reg)
                *reg = *(const uint64_t *)saved;
        }
        c->r[R_RIP] = *(const uint64_t *)(rbp + 8);
        c->r[R_RSP] = rbp + 16;
        c->r[R_RBP] = *(const uint64_t *)rbp;
        return 1;
    }
    case MODE_STACK_IMMD:
    case MODE_STACK_IND: {
        uint64_t size = (enc >> 16) & 0xff;
        if ((enc & UNWIND_MODE_MASK) == MODE_STACK_IND)
            size = u32((const uint8_t *)(fi->start + size)) + ((enc >> 13) & 7) * 8;
        else
            size *= 8;
        int count = (int)((enc >> 10) & 7), regs[6] = {0};
        if (count > 6)
            return 0;
        decode_permutation(enc & 0x3ff, count, regs);
        uint64_t rsp = c->r[R_RSP];
        uint64_t saved = rsp + size - 8 - (uint64_t)count * 8;
        for (int i = 0; i < count; i++, saved += 8) {
            uint64_t *reg = compact_reg(c, (unsigned)regs[i]);
            if (reg)
                *reg = *(const uint64_t *)saved;
        }
        c->r[R_RIP] = *(const uint64_t *)(rsp + size - 8);
        c->r[R_RSP] = rsp + size;
        return 1;
    }
    case MODE_DWARF:
        return step_dwarf(c, fi, pc);
    default:
        return 0;
    }
}

/* ---- the personality: reading a function's LSDA ---------------------------------- */

enum { ACT_NONE, ACT_CLEANUP, ACT_CATCH };

/* What the function at fi does for an exception passing the call at pc:
 * nothing, a cleanup, or a @catch that matches (with its selector). */
static int scan_lsda(const struct finfo *fi, uint64_t pc, id obj, int foreign, uint64_t *lp, int64_t *selector)
{
    if (!fi->lsda)
        return ACT_NONE;
    const uint8_t *p = (const uint8_t *)fi->lsda;
    uint8_t lpstart_enc = *p++;
    uint64_t lpstart = lpstart_enc != PE_OMIT ? read_ptr(&p, lpstart_enc) : fi->start;
    uint8_t ttype_enc = *p++;
    const uint8_t *ttype_base = NULL;
    if (ttype_enc != PE_OMIT) {
        uint64_t off = uleb(&p);
        ttype_base = p + off;
    }
    uint8_t cs_enc = *p++;
    uint64_t cs_len = uleb(&p);
    const uint8_t *cs = p, *cs_end = p + cs_len, *actions = cs_end;
    while (cs < cs_end) {
        uint64_t start = read_ptr(&cs, cs_enc), len = read_ptr(&cs, cs_enc), pad = read_ptr(&cs, cs_enc);
        uint64_t action = uleb(&cs);
        if (pc < fi->start + start)
            break;   /* the table is sorted */
        if (pc >= fi->start + start + len)
            continue;
        if (!pad)
            return ACT_NONE;
        *lp = lpstart + pad;
        if (!action) {
            *selector = 0;
            return ACT_CLEANUP;
        }
        int cleanup = 0;
        const uint8_t *a = actions + action - 1;
        for (;;) {
            const uint8_t *here = a;
            int64_t filter = sleb(&a);
            const uint8_t *next_at = a;
            int64_t next = sleb(&a);
            if (filter > 0 && ttype_base) {
                const uint8_t *tp = ttype_base - filter * (int64_t)ptr_size(ttype_enc);
                const struct ferry_ehtype *t = (const struct ferry_ehtype *)read_ptr(&tp, ttype_enc);
                if (catches(t, obj, foreign)) {
                    *selector = filter;
                    return ACT_CATCH;
                }
            } else if (filter == 0) {
                cleanup = 1;
            }
            (void)here;
            if (!next)
                break;
            a = next_at + next;
        }
        *selector = 0;
        return cleanup ? ACT_CLEANUP : ACT_NONE;
    }
    return ACT_NONE;
}

/* The routine the compiler names for Objective-C (and Objective-C++) code.
 * Ferry's own unwinder reads the LSDA itself; this system's unwinder, in
 * use once a program uses C++, calls this for each frame. */
int ferry_objc_personality(int version, int actions, uint64_t cls, void *exc, void *ctx)
{
    if (!ferry_cxx_active || version != 1)
        return FERRY_URC_FATAL_PHASE1_ERROR;
    struct _Unwind_Context *c = ctx;
    struct finfo fi = {0};
    fi.lsda = ferry_cxx_unwind.get_lsda(c);
    if (!fi.lsda)
        return FERRY_URC_CONTINUE_UNWIND;
    fi.start = ferry_cxx_unwind.get_region_start(c);
    uint64_t pc = ferry_cxx_unwind.get_ip(c) - 1;
    /* a C++ exception: the C++ rules, under which an Objective-C clause
     * takes nothing (see objc_ehtype_vtable) and catch (...) takes it */
    if (cls != FERRY_EXC_CLASS)
        return ferry_cxx_unwind.gxx_personality(version, actions, cls, exc, c);
    uint64_t lp = 0;
    int64_t sel = 0;
    int what = scan_lsda(&fi, pc, ((struct exc *)exc)->obj, 0, &lp, &sel);
    if (actions & FERRY_UA_SEARCH_PHASE)
        return what == ACT_CATCH && !(actions & FERRY_UA_FORCE_UNWIND) ? FERRY_URC_HANDLER_FOUND
                                                                        : FERRY_URC_CONTINUE_UNWIND;
    if (what == ACT_NONE)
        return FERRY_URC_CONTINUE_UNWIND;
    if (what == ACT_CATCH && !(actions & FERRY_UA_HANDLER_FRAME))
        sel = 0;   /* not the frame the search chose: its cleanups only */
    ferry_cxx_unwind.set_gr(c, 0, (uintptr_t)exc);
    ferry_cxx_unwind.set_gr(c, 1, (uintptr_t)sel);
    ferry_cxx_unwind.set_ip(c, lp);
    return FERRY_URC_INSTALL_CONTEXT;
}

/* ---- throwing ------------------------------------------------------------------------- */

static void (*uncaught_handler)(id);

void (*objc_setUncaughtExceptionHandler(void (*handler)(id)))(id)
{
    void (*old)(id) = uncaught_handler;
    uncaught_handler = handler;
    return old;
}

static id (*preprocessor)(id);
id (*objc_setExceptionPreprocessor(id (*fn)(id)))(id)
{
    id (*old)(id) = preprocessor;
    preprocessor = fn;
    return old;
}

__attribute__((noreturn)) static void uncaught(struct exc *e)
{
    if (uncaught_handler)
        uncaught_handler(e->obj);
    fflush(stdout);
    fprintf(stderr, "ferry: the program ended on an Objective-C exception (%s) that nothing caught\n",
            e->obj ? object_getClassName(e->obj) : "nil");
    abort();
}

static int known_personality(uint64_t p)
{
    return p == (uint64_t)ferry_objc_personality;
}

/* Phase 2, from the frame in c: runs cleanups and jumps to the handler. */
__attribute__((noreturn)) static void unwind_to_handler(struct exc *e, struct uctx c)
{
    for (int depth = 0; depth < 100000; depth++) {
        uint64_t pc = c.r[R_RIP] - 1;
        struct finfo fi;
        if (!lookup(pc, &fi))
            break;
        if (fi.lsda && known_personality(fi.personality)) {
            uint64_t lp = 0;
            int64_t sel = 0;
            int what = scan_lsda(&fi, pc, e->obj, 0, &lp, &sel);
            int handler_frame = c.r[R_RSP] == e->handler_sp;
            if (what == ACT_CATCH && !handler_frame)
                what = ACT_CLEANUP, sel = 0;
            if (what != ACT_NONE) {
                c.r[R_RAX] = (uint64_t)e;
                c.r[R_RDX] = (uint64_t)sel;
                c.r[R_RIP] = lp;
                ferry_unwind_jump(&c);
            }
        }
        if (!step(&c, &fi, pc))
            break;
    }
    /* the handler phase 1 found has gone */
    uncaught(e);
}

__attribute__((noreturn)) static void raise_from(struct exc *e, const struct uctx *start)
{
    struct uctx c = *start;
    for (int depth = 0; depth < 100000; depth++) {
        uint64_t pc = c.r[R_RIP] - 1;
        struct finfo fi;
        if (!lookup(pc, &fi))
            break;
        if (fi.lsda && fi.personality && !known_personality(fi.personality) && ferry_verbose)
            fprintf(stderr, "ferry: a function at %#lx uses an exception personality Ferry doesn't know\n",
                    (unsigned long)fi.start);
        if (fi.lsda && known_personality(fi.personality)) {
            uint64_t lp;
            int64_t sel;
            if (scan_lsda(&fi, pc, e->obj, 0, &lp, &sel) == ACT_CATCH) {
                e->handler_sp = c.r[R_RSP];
                unwind_to_handler(e, *start);
            }
        }
        if (!step(&c, &fi, pc))
            break;
    }
    uncaught(e);
}

static struct exc *new_exception(id obj)
{
    struct exc *e = calloc(1, sizeof *e);
    e->exception_class = FERRY_EXC_CLASS;
    e->obj = obj;
    return e;
}

/* ---- throwing through this system's unwinder, once a program uses C++ ---- */

void *ferry_objc_throw_host, *ferry_objc_rethrow_host, *ferry_unwind_resume_host;   /* unwind.S */
static void (*cxa_rethrow)(void);

/* what the unwinder calls once nothing needs the exception (a C++ catch
 * (...) of an Objective-C exception ends) */
static void exc_cleanup(int reason, struct exc *e)
{
    (void)reason;
    objc_release(e->obj);
    free(e);
}

__attribute__((noreturn)) static void raise_host(id obj)
{
    struct exc *e = new_exception(obj);
    e->cleanup = exc_cleanup;
    ferry_cxx_unwind.raise(e);
    /* the end of the stack, or a frame the unwinder couldn't read, before a handler */
    uncaught(e);
}

__attribute__((noreturn)) static void throw_host(id obj)
{
    if (preprocessor)
        obj = preprocessor(obj);
    objc_retain(obj);
    raise_host(obj);
}

__attribute__((noreturn)) static void rethrow_host(void)
{
    if (caught && caught->exception_class != FERRY_EXC_CLASS && cxa_rethrow) {
        cxa_rethrow();   /* a C++ exception, caught by @catch (...) */
        abort();
    }
    if (!caught) {
        fflush(stdout);
        fputs("ferry: the program re-threw an exception outside any @catch\n", stderr);
        abort();
    }
    id obj = caught->obj;
    objc_retain(obj);
    raise_host(obj);
}

void ferry_objc_exceptions_to_host(void)
{
    *(void **)&cxa_rethrow = ferry_cxx_symbol("__cxa_rethrow");
    ferry_objc_throw_host = (void *)throw_host;
    ferry_objc_rethrow_host = (void *)rethrow_host;
    ferry_unwind_resume_host = (void *)ferry_cxx_unwind.resume;
}

/* unwind.S calls these with the thrower's registers. */
__attribute__((noreturn)) void ferry_throw_with(id obj, const struct uctx *c)
{
    if (preprocessor)
        obj = preprocessor(obj);
    objc_retain(obj);
    raise_from(new_exception(obj), c);
}

__attribute__((noreturn)) void ferry_rethrow_with(void *unused, const struct uctx *c)
{
    (void)unused;
    if (!caught) {
        fflush(stdout);
        fputs("ferry: the program re-threw an exception outside any @catch\n", stderr);
        abort();
    }
    id obj = caught->obj;
    objc_retain(obj);
    raise_from(new_exception(obj), c);
}

__attribute__((noreturn)) void ferry_resume_with(struct exc *e, const struct uctx *c)
{
    if (!e || e->exception_class != FERRY_EXC_CLASS) {
        fflush(stdout);
        fputs("ferry: the program resumed unwinding an exception Ferry didn't throw\n", stderr);
        abort();
    }
    unwind_to_handler(e, *c);
}

/* ---- catching ---------------------------------------------------------------------------- */

id objc_begin_catch(void *exc)
{
    struct exc *e = exc;
    if (e && e->exception_class != FERRY_EXC_CLASS && ferry_cxx_active) {
        /* a C++ exception in @catch (...): the C++ runtime keeps it, and a
         * mark here says so until the @catch ends */
        struct exc *mark = calloc(1, sizeof *mark);
        ferry_cxx_unwind.begin_catch(exc);
        mark->next_caught = caught;
        caught = mark;
        return nil;
    }
    if (!e || e->exception_class != FERRY_EXC_CLASS)
        return nil;
    e->next_caught = caught;
    caught = e;
    return e->obj;
}

void objc_end_catch(void)
{
    struct exc *e = caught;
    if (!e)
        return;
    caught = e->next_caught;
    if (e->exception_class != FERRY_EXC_CLASS) {
        free(e);
        ferry_cxx_unwind.end_catch();
        return;
    }
    objc_autorelease(e->obj);   /* the @catch body may still be using it */
    free(e);
}

void objc_terminate(void)
{
    fflush(stdout);
    fputs("ferry: the program called objc_terminate\n", stderr);
    abort();
}
