/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: fibers for shader code. The four pixels of a
 * fragment quad and the threads of a compute threadgroup each run on a
 * small stack of their own, switched by hand on one processor thread, so
 * that a derivative or quad function can wait for the quad's other pixels
 * and a threadgroup barrier for the group's other threads. A lane starts
 * only when the one before it finished or waits, and a finished lane gives
 * its stack to the next, so a kernel that never waits uses one stack. */
#include "MTLInternal.h"
#include <stdlib.h>
#include <string.h>

/* ---- the switch ------------------------------------------------------------------------ */
/* mtl_ctx_swap(&save, to): saves the callee-saved registers, the SSE and x87
 * control words and the stack pointer in *save, and continues where "to"
 * was saved. */
__asm__(".text\n"
        ".p2align 4\n"
        "mtl_ctx_swap:\n"
        "  pushq %rbp\n"
        "  pushq %rbx\n"
        "  pushq %r12\n"
        "  pushq %r13\n"
        "  pushq %r14\n"
        "  pushq %r15\n"
        "  subq $8, %rsp\n"
        "  stmxcsr (%rsp)\n"
        "  fnstcw 4(%rsp)\n"
        "  movq %rsp, (%rdi)\n"
        "  movq %rsi, %rsp\n"
        "  ldmxcsr (%rsp)\n"
        "  fldcw 4(%rsp)\n"
        "  addq $8, %rsp\n"
        "  popq %r15\n"
        "  popq %r14\n"
        "  popq %r13\n"
        "  popq %r12\n"
        "  popq %rbx\n"
        "  popq %rbp\n"
        "  retq\n");
void mtl_ctx_swap(void **save, void *to) __asm__("mtl_ctx_swap");

enum { L_NEW, L_READY, L_WAIT, L_DONE };
#define MAX_LANES 1024
#define EX_BYTES 256

struct stack { struct stack *next; size_t size; };
struct group {
    int kind, n, finished;
    int direct;                   /* lanes run in turn on the worker's stack */
    mtl_lane_fn fn;
    void *arg;
    void *sched_sp;
    int cur;
    unsigned char state[MAX_LANES];
    unsigned char discarded[MAX_LANES];
    void *sp[MAX_LANES];
    struct stack *stk[MAX_LANES];
    unsigned round[4];
    unsigned char ex[2][4][EX_BYTES];
};
struct worker {
    struct group *g;              /* the group being run, or NULL */
    struct stack *free_stacks;
    int discard_outside;          /* __ferry_discard with no group (a draw's single fragment) */
    void *tg_ptr[64];
    size_t tg_size[64];
    struct group *gbuf;
    /* the last group's discards, for the writes that follow it */
    unsigned char last_discarded[MAX_LANES];
    int last_n;
};
static __thread struct worker *me;

static struct worker *worker(void)
{
    if (!me) me = calloc(1, sizeof *me);
    return me;
}
static size_t stack_size(void)
{
    static size_t sz;
    if (!sz) {
        const char *e = getenv("FERRY_METAL_STACK_KB");
        size_t kb = e && *e ? (size_t)strtoul(e, NULL, 10) : 512;
        if (kb < 64) kb = 64;
        sz = kb * 1024;
    }
    return sz;
}
static struct stack *get_stack(struct worker *w)
{
    struct stack *s = w->free_stacks;
    if (s) { w->free_stacks = s->next; return s; }
    size_t sz = stack_size();
    void *p = NULL;
    if (posix_memalign(&p, 64, sz)) return NULL;
    s = p;
    s->size = sz;
    return s;
}
static void put_stack(struct worker *w, struct stack *s)
{
    s->next = w->free_stacks;
    w->free_stacks = s;
}

static void lane_entry(void) __attribute__((noreturn, used));
static void lane_entry(void)
{
    for (;;) {
        struct group *g = me->g;
        int lane = g->cur;
        g->fn(g->arg, lane);
        g->state[lane] = L_DONE;
        g->finished++;
        mtl_ctx_swap(&g->sp[lane], g->sched_sp);
        /* reached again only if this stack is restarted for a new lane */
    }
}
static void *fresh_sp(struct stack *s)
{
    uintptr_t top = ((uintptr_t)s + s->size) & ~(uintptr_t)15;
    uint64_t *p = (uint64_t *)top;
    *--p = 0;                              /* lane_entry's (never used) return address */
    *--p = (uint64_t)(uintptr_t)lane_entry;
    for (int i = 0; i < 6; i++) *--p = 0;  /* rbp rbx r12..r15 */
    uint32_t ctl[2];
    __asm__ volatile("stmxcsr %0" : "=m"(ctl[0]));
    __asm__ volatile("fnstcw %0" : "=m"(*(uint16_t *)&ctl[1]));
    ctl[1] &= 0xffff;
    *--p = (uint64_t)ctl[0] | ((uint64_t)ctl[1] << 32);
    return p;
}

void mtl_run_lanes(int kind, int n, mtl_lane_fn fn, void *arg)
{
    struct worker *w = worker();
    if (n <= 0) return;
    if (n > MAX_LANES) n = MAX_LANES;
    int direct = (kind & MTL_LANES_NO_WAIT) != 0;
    kind &= ~MTL_LANES_NO_WAIT;
    if (!w->gbuf) w->gbuf = malloc(sizeof(struct group));
    struct group *g = w->gbuf, *outer = w->g;
    if (outer) g = malloc(sizeof *g); /* (not expected: lanes inside lanes) */
    g->kind = kind;
    g->direct = direct;
    g->n = n;
    g->finished = 0;
    g->fn = fn;
    g->arg = arg;
    memset(g->state, L_NEW, (size_t)n);
    memset(g->discarded, 0, (size_t)n);
    memset(g->round, 0, sizeof g->round);
    w->g = g;
    if (direct) {
        for (int i = 0; i < n; i++) {
            g->cur = i;
            fn(arg, i);
            g->state[i] = L_DONE;
        }
        g->finished = n;
    }
    while (g->finished < g->n) {
        int waiting = 0;
        for (int i = 0; i < n; i++) {
            if (g->state[i] == L_NEW) {
                struct stack *s = NULL;
                /* a finished lane's stack is free for the next */
                s = get_stack(w);
                if (!s) { g->state[i] = L_DONE; g->finished++; continue; }
                g->stk[i] = s;
                g->sp[i] = fresh_sp(s);
                g->state[i] = L_READY;
            }
            if (g->state[i] == L_READY) {
                g->cur = i;
                mtl_ctx_swap(&g->sched_sp, g->sp[i]);
                if (g->state[i] == L_DONE) put_stack(w, g->stk[i]);
            }
            if (g->state[i] == L_WAIT) waiting++;
        }
        if (waiting && waiting == g->n - g->finished) {
            for (int i = 0; i < n; i++)
                if (g->state[i] == L_WAIT) g->state[i] = L_READY;
        }
    }
    w->g = outer;
    if (!outer) {
        memcpy(w->last_discarded, g->discarded, (size_t)n);
        w->last_n = n;
    }
    if (outer) free(g);
}

int mtl_lane_discarded(int lane)
{
    struct worker *w = worker();
    if (!w->g) {
        if (w->discard_outside) { w->discard_outside = 0; return 1; }
        return lane >= 0 && lane < w->last_n ? w->last_discarded[lane] : 0;
    }
    return lane >= 0 && lane < w->g->n ? w->g->discarded[lane] : 0;
}

/* Wait for the group's other lanes. */
static void wait_here(struct group *g)
{
    int lane = g->cur;
    g->state[lane] = L_WAIT;
    mtl_ctx_swap(&g->sp[lane], g->sched_sp);
    g->cur = lane; /* (the scheduler set it already) */
}

/* ---- what shaders call ----------------------------------------------------------------- */
void __ferry_quad_exchange(const void *val, int bytes, void *all4)
{
    struct worker *w = me;
    struct group *g = w ? w->g : NULL;
    if (bytes > EX_BYTES) bytes = EX_BYTES;
    if (bytes < 0) bytes = 0;
    if (!g || g->kind != 1 || g->direct) {
        for (int i = 0; i < 4; i++) memcpy((char *)all4 + (size_t)i * (size_t)bytes, val, (size_t)bytes);
        return;
    }
    int lane = g->cur;
    unsigned r = g->round[lane]++ & 1;
    memcpy(g->ex[r][lane], val, (size_t)bytes);
    wait_here(g);
    for (int i = 0; i < 4; i++) {
        /* a lane that already finished keeps its last value; one not in the
         * quad at all gives this lane's own */
        const void *src = i < g->n ? g->ex[r][i] : val;
        memcpy((char *)all4 + (size_t)i * (size_t)bytes, src, (size_t)bytes);
    }
}
int __ferry_quad_lane(void)
{
    struct group *g = me ? me->g : NULL;
    return g && g->kind == 1 ? g->cur : 0;
}
void __ferry_discard(void)
{
    struct worker *w = worker();
    if (w->g) w->g->discarded[w->g->cur] = 1;
    else w->discard_outside = 1;
}
void __ferry_barrier(int flags)
{
    struct group *g = me ? me->g : NULL;
    (void)flags;
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
    if (!g || g->kind != 2 || g->n == 1 || g->direct) return;
    wait_here(g);
}

/* Threadgroup memory a kernel declares in its body: one block per
 * declaration for the whole group. */
void mtl_tg_reset(void)
{
    struct worker *w = worker();
    for (int i = 0; i < 64; i++)
        if (w->tg_ptr[i]) memset(w->tg_ptr[i], 0, w->tg_size[i]);
}
void *__ferry_tg_alloc(unsigned long size, unsigned long align, int id)
{
    struct worker *w = worker();
    if (id < 0 || id >= 64) id = 63;
    if (!w->tg_ptr[id] || w->tg_size[id] < size) {
        free(w->tg_ptr[id]);
        void *p = NULL;
        if (align < 16) align = 16;
        if (posix_memalign(&p, align, size ? size : 16)) return NULL;
        memset(p, 0, size);
        w->tg_ptr[id] = p;
        w->tg_size[id] = size;
    }
    return w->tg_ptr[id];
}
