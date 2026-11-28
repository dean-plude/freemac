/* SPDX-License-Identifier: GPL-3.0-or-later
 * The unwinder's C calls on a Mac program's own frames: _Unwind_Backtrace
 * walks them, and _Unwind_GetIP and _Unwind_GetCFA read each frame's context,
 * as LuaJIT's error handling does in Neovim (freemac 1.NEXT). */
#include <stdint.h>
#include <stdio.h>

struct _Unwind_Context;
typedef int (*trace_fn)(struct _Unwind_Context *, void *);
int _Unwind_Backtrace(trace_fn, void *);
uintptr_t _Unwind_GetIP(struct _Unwind_Context *);
uintptr_t _Unwind_GetCFA(struct _Unwind_Context *);

struct walk {
    int frames, in_inner, in_outer, cfa_rises;
    uintptr_t last_cfa;
};

__attribute__((noinline)) static void inner(struct walk *w);
__attribute__((noinline)) static void outer(struct walk *w);

static int step(struct _Unwind_Context *ctx, void *arg)
{
    struct walk *w = arg;
    uintptr_t ip = _Unwind_GetIP(ctx), cfa = _Unwind_GetCFA(ctx);
    if (ip > (uintptr_t)inner && ip < (uintptr_t)inner + 200)
        w->in_inner = 1;
    if (ip > (uintptr_t)outer && ip < (uintptr_t)outer + 200)
        w->in_outer = 1;
    if (w->frames > 0 && cfa > w->last_cfa)
        w->cfa_rises++;
    w->last_cfa = cfa;
    return ++w->frames < 8 ? 0 : 9; /* _URC_NO_REASON, then stop */
}

__attribute__((noinline)) static void inner(struct walk *w)
{
    _Unwind_Backtrace(step, w);
    __asm__ volatile("");
}
__attribute__((noinline)) static void outer(struct walk *w)
{
    inner(w);
    __asm__ volatile("");
}

int main(void)
{
    struct walk w = {0};
    outer(&w);
    printf("frames walked: %d\n", w.frames >= 3);
    printf("through inner and outer: %d %d\n", w.in_inner, w.in_outer);
    printf("each frame's CFA above the last: %d\n", w.cfa_rises >= 2);
    return 0;
}
