/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Mac thread-local variables: C's __thread and _Thread_local, and C++'s
 * thread_local.
 *
 * A Mac image that has them carries, in its __DATA segment:
 *
 *   - a template of their first values: __thread_data
 *     (S_THREAD_LOCAL_REGULAR) for those with a value and __thread_bss
 *     (S_THREAD_LOCAL_ZEROFILL) for those that start at zero;
 *   - one descriptor for each variable in __thread_vars
 *     (S_THREAD_LOCAL_VARIABLES): {thunk, key, offset}, where the thunk
 *     is bound to libSystem's _tlv_bootstrap and the offset is the
 *     variable's place in the template, counted from the template's first
 *     section;
 *   - optionally, functions to run when the image is set up
 *     (S_THREAD_LOCAL_INIT_FUNCTION_POINTERS, run by the loader).
 *
 * The compiler reaches a variable by loading its descriptor's address into
 * %rdi and calling the thunk through the descriptor's first word; the
 * thunk returns the variable's address for the calling thread in %rax.
 * clang treats that call as one that changes only %rax, %rdi and the
 * flags: every other general register may hold a live value across it.
 * Ferry's thunk keeps %rdi and the vector registers as well, so code that
 * relies on them is safe too.
 *
 * When an image is loaded, Ferry gives it a key (a small number of its
 * own, 1 to MAX_KEYS) and writes the key and Ferry's thunk into each
 * descriptor. Each thread has an array of its copies, one block per image,
 * indexed by key in this system's own thread-local storage: the thunk's
 * usual path is a compare, two loads and an add, and touches no register
 * but %rax.
 * The first time a thread reaches an image's variables, the thunk saves
 * every register, the vector registers included (with xsave, or fxsave on
 * processors without it), and makes that thread's block: zero, with the
 * __thread_data sections copied in.
 *
 * C++ objects with constructors are set up by the program's own code (the
 * compiler's per-thread guard is a thread-local variable too), and their
 * destructors are registered with _tlv_atexit. They run, last registered
 * first, when the thread ends, and for the thread that calls exit (the
 * main thread when main returns) before the program's static destructors,
 * as the C++ standard asks. A thread's blocks are freed when it ends; the
 * thread that calls exit keeps them, since static destructors may still
 * reach them.
 *
 * Written from the Mach-O format's public description (the section types
 * in the open-source cctools and XNU <mach-o/loader.h>), the System V
 * AMD64 calling convention and the code clang emits for our own test
 * programs; no Apple code was used.
 */
#define _GNU_SOURCE
#include <cpuid.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ferry.h"
#include "macho.h"

/* One of an image's descriptors, as the compiler lays it out. */
struct tlv_descriptor {
    void *(*thunk)(struct tlv_descriptor *);
    unsigned long key;
    unsigned long offset;
};

/* Every image can have one key: as many as the loader keeps images. The
 * first FAST_KEYS have a place in the thread's own storage that the thunk
 * reads directly; it is kept small, since every thread's stack pays for
 * it, and later ones take the slow way each time. */
#define MAX_KEYS 512
#define FAST_KEYS 128
#define MAX_REGULAR 8

/* An image's template, by key (0 is never handed out). */
struct tlv_template {
    const char *path;
    uint64_t size;           /* from the first template section's start to the last one's end */
    uint64_t align;          /* the largest alignment its sections ask for */
    uint64_t lead;           /* the template's start, modulo that alignment */
    int nregular;
    struct { uint64_t offset, size; const uint8_t *data; } regular[MAX_REGULAR];
};
static struct tlv_template templates[MAX_KEYS + 1];
static int nkeys;                 /* the last key handed out, read with acquire */
static pthread_mutex_t key_lock = PTHREAD_MUTEX_INITIALIZER;

/* This thread's block for each key, read by the thunk below as
 * %fs:ferry_tlv_slots@tpoff(,key,8); keys from FAST_KEYS on are in
 * more_slots. Each block holds, just before its first byte, the pointer
 * malloc returned for it. */
__thread void *ferry_tlv_slots[FAST_KEYS];
static __thread void **more_slots;          /* MAX_KEYS + 1 of them, once needed */
static __thread int top_slot;               /* the highest key this thread has a block for */

static void **slot_of(unsigned long key)
{
    if (key < FAST_KEYS)
        return &ferry_tlv_slots[key];
    if (!more_slots && !(more_slots = calloc(MAX_KEYS + 1, sizeof *more_slots)))
        return NULL;
    return &more_slots[key];
}

/* Destructors registered on this thread, run last first. */
struct terminator { void (*fn)(void *); void *obj; };
static __thread struct terminator *terms;
static __thread size_t nterms, terms_cap;

/* How the thunk keeps the vector registers while it makes a block. */
uint32_t ferry_tlv_xsave_mask;    /* the state components xsave keeps; 0: fxsave */
uint64_t ferry_tlv_state_size = 576;

__attribute__((constructor)) static void find_state_size(void)
{
    unsigned a, b, c, d;
    if (!__get_cpuid(1, &a, &b, &c, &d) || !(c & (1u << 27)))
        return;     /* no OSXSAVE: fxsave keeps x87 and SSE */
    uint32_t lo, hi;
    __asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
    (void)hi;
    /* x87, SSE, AVX and AVX-512's three parts: the registers code can hold
     * values in. Larger, newer states (AMX) are left alone. */
    uint32_t mask = lo & 0xe7;
    uint64_t size = 576;   /* the legacy area and the xsave header */
    for (unsigned i = 2; i < 8; i++) {
        if (!(mask & (1u << i)))
            continue;
        __cpuid_count(0xd, i, a, b, c, d);
        if ((uint64_t)a + b > size)
            size = (uint64_t)a + b;
    }
    ferry_tlv_state_size = (size + 63) & ~(uint64_t)63;
    ferry_tlv_xsave_mask = mask;
}

/* ---- the thunk --------------------------------------------------------------- */

#define STRING(x) STRING_OF(x)
#define STRING_OF(x) #x

void *ferry_tlv_bootstrap(struct tlv_descriptor *d);
void *ferry_tlv_slow(struct tlv_descriptor *d);

__asm__(".text\n"
        ".globl ferry_tlv_bootstrap\n"
        ".type ferry_tlv_bootstrap, @function\n"
        "ferry_tlv_bootstrap:\n"
        "    .cfi_startproc\n"
        "    movq 8(%rdi), %rax\n"                              /* the image's key */
        "    cmpq $" STRING(FAST_KEYS) ", %rax\n"
        "    jae 1f\n"
        "    movq %fs:ferry_tlv_slots@tpoff(,%rax,8), %rax\n"   /* this thread's block */
        "    testq %rax, %rax\n"
        "    jz 1f\n"
        "    addq 16(%rdi), %rax\n"                             /* the variable in it */
        "    ret\n"
        /* No block yet: keep everything but %rax and make one. */
        "1:  pushq %rbp\n"
        "    .cfi_adjust_cfa_offset 8\n"
        "    .cfi_offset %rbp, -16\n"
        "    movq %rsp, %rbp\n"
        "    .cfi_def_cfa_register %rbp\n"
        "    pushq %rdi\n"
        "    pushq %rsi\n"
        "    pushq %rdx\n"
        "    pushq %rcx\n"
        "    pushq %r8\n"
        "    pushq %r9\n"
        "    pushq %r10\n"
        "    pushq %r11\n"
        "    subq $8, %rsp\n"                                   /* -72(%rbp): the answer */
        "    subq ferry_tlv_state_size(%rip), %rsp\n"
        "    andq $-64, %rsp\n"
        "    movl ferry_tlv_xsave_mask(%rip), %eax\n"
        "    testl %eax, %eax\n"
        "    jz 2f\n"
        "    xorl %edx, %edx\n"
        "    movq %rdx, 512(%rsp)\n"                            /* the xsave header starts at zero */
        "    movq %rdx, 520(%rsp)\n"
        "    movq %rdx, 528(%rsp)\n"
        "    movq %rdx, 536(%rsp)\n"
        "    movq %rdx, 544(%rsp)\n"
        "    movq %rdx, 552(%rsp)\n"
        "    movq %rdx, 560(%rsp)\n"
        "    movq %rdx, 568(%rsp)\n"
        "    xsave (%rsp)\n"
        "    jmp 3f\n"
        "2:  fxsave (%rsp)\n"
        "3:  movq -8(%rbp), %rdi\n"
        "    call ferry_tlv_slow\n"
        "    movq %rax, -72(%rbp)\n"
        "    movl ferry_tlv_xsave_mask(%rip), %eax\n"
        "    testl %eax, %eax\n"
        "    jz 4f\n"
        "    xorl %edx, %edx\n"
        "    xrstor (%rsp)\n"
        "    jmp 5f\n"
        "4:  fxrstor (%rsp)\n"
        "5:  movq -72(%rbp), %rax\n"
        "    leaq -64(%rbp), %rsp\n"
        "    popq %r11\n"
        "    popq %r10\n"
        "    popq %r9\n"
        "    popq %r8\n"
        "    popq %rcx\n"
        "    popq %rdx\n"
        "    popq %rsi\n"
        "    popq %rdi\n"
        "    popq %rbp\n"
        "    .cfi_def_cfa %rsp, 8\n"
        "    ret\n"
        "    .cfi_endproc\n"
        ".size ferry_tlv_bootstrap, .-ferry_tlv_bootstrap\n");

/* ---- the end of a thread ----------------------------------------------------- */

static pthread_key_t exit_key;
static pthread_once_t exit_once = PTHREAD_ONCE_INIT;

static void run_terminators(void)
{
    /* a destructor may reach another variable and register more */
    while (nterms) {
        struct terminator t = terms[--nterms];
        t.fn(t.obj);
    }
}

static void free_blocks(void)
{
    for (int k = 1; k <= top_slot; k++) {
        void **slot = k < FAST_KEYS ? &ferry_tlv_slots[k] : more_slots ? &more_slots[k] : NULL;
        if (slot && *slot) {
            free(((void **)*slot)[-1]);
            *slot = NULL;
        }
    }
    free(more_slots);
    more_slots = NULL;
    top_slot = 0;
}

/* This system's thread-specific data destructor: it runs when any thread
 * ends (Ferry's pthreads, NSThread, dispatch's workers), and again if a
 * later destructor makes a block or registers one. */
static void thread_ended(void *unused)
{
    (void)unused;
    run_terminators();
    free(terms);
    terms = NULL;
    terms_cap = 0;
    free_blocks();
}

static void make_exit_key(void)
{
    if (pthread_key_create(&exit_key, thread_ended)) {
        fputs("ferry: can't set up thread-local variables\n", stderr);
        _exit(126);
    }
}

/* Whatever a thread holds is let go when it ends. */
static void arm_exit(void)
{
    pthread_once(&exit_once, make_exit_key);
    if (!pthread_getspecific(exit_key))
        pthread_setspecific(exit_key, (void *)1);
}

/* For exit, and when main returns: the calling thread's destructors. */
void ferry_tlv_exit(void)
{
    run_terminators();
}

void *ferry_tlv_address(void *descriptor)
{
    struct tlv_descriptor *d = descriptor;
    return d->thunk(d);
}

/* ---- making a thread's block ------------------------------------------------- */

void *ferry_tlv_slow(struct tlv_descriptor *d)
{
    unsigned long key = d->key;
    void **slot;
    if (key == 0 || key > (unsigned long)__atomic_load_n(&nkeys, __ATOMIC_ACQUIRE)) {
        fflush(stdout);
        fprintf(stderr, "ferry: a thread-local variable at %p belongs to no image Ferry loaded\n", (void *)d);
        _exit(126);
    }
    const struct tlv_template *t = &templates[key];
    if (!(slot = slot_of(key))) {
        fflush(stdout);
        fputs("ferry: out of memory for a thread's thread-local variables\n", stderr);
        _exit(126);
    }
    if (!*slot) {
        uint64_t align = t->align < 16 ? 16 : t->align;
        uint8_t *raw = malloc(t->size + align + 16);
        if (!raw) {
            fflush(stdout);
            fputs("ferry: out of memory for a thread's thread-local variables\n", stderr);
            _exit(126);
        }
        /* placed as the template is, modulo its alignment, with room for
         * raw just before it */
        uint8_t *p = raw + 16;
        uint8_t *base = p + ((t->lead - (uintptr_t)p) & (align - 1));
        ((void **)base)[-1] = raw;
        memset(base, 0, t->size);
        for (int i = 0; i < t->nregular; i++)
            memcpy(base + t->regular[i].offset, t->regular[i].data, t->regular[i].size);
        *slot = base;
        if ((int)key > top_slot)
            top_slot = (int)key;
        arm_exit();
    }
    return (uint8_t *)*slot + d->offset;
}

/* ---- images ------------------------------------------------------------------ */

int ferry_tlv_image_loaded(const char *path, const struct ferry_tlv_section *s, int n)
{
    uint64_t start = UINT64_MAX, end = 0, align = 1;
    int ndesc = 0, nregular = 0;
    for (int i = 0; i < n; i++) {
        if (s[i].type == S_THREAD_LOCAL_VARIABLES)
            ndesc += (int)(s[i].size / sizeof(struct tlv_descriptor));
        if (s[i].type != S_THREAD_LOCAL_REGULAR && s[i].type != S_THREAD_LOCAL_ZEROFILL)
            continue;
        uint64_t a = (uint64_t)s[i].addr;
        if (a < start)
            start = a;
        if (a + s[i].size > end)
            end = a + s[i].size;
        uint64_t al = s[i].align < 12 ? (uint64_t)1 << s[i].align : 4096;
        if (al > align)
            align = al;
        nregular += s[i].type == S_THREAD_LOCAL_REGULAR;
    }
    if (!ndesc)
        return 0;
    if (start == UINT64_MAX)
        start = end = 0;
    if (nregular > MAX_REGULAR) {
        fprintf(stderr, "ferry: %s has too many thread-local data sections\n", path);
        return -1;
    }
    pthread_mutex_lock(&key_lock);
    if (nkeys == MAX_KEYS) {
        pthread_mutex_unlock(&key_lock);
        fprintf(stderr, "ferry: too many libraries with thread-local variables\n");
        return -1;
    }
    unsigned long key = (unsigned long)nkeys + 1;
    struct tlv_template *t = &templates[key];
    memset(t, 0, sizeof *t);
    t->path = path;
    t->size = end - start;
    t->align = align;
    t->lead = start & (align < 16 ? 15 : align - 1);
    for (int i = 0; i < n; i++)
        if (s[i].type == S_THREAD_LOCAL_REGULAR && s[i].size) {
            t->regular[t->nregular].offset = (uint64_t)s[i].addr - start;
            t->regular[t->nregular].size = s[i].size;
            t->regular[t->nregular].data = s[i].addr;
            t->nregular++;
        }
    for (int i = 0; i < n; i++) {
        if (s[i].type != S_THREAD_LOCAL_VARIABLES)
            continue;
        struct tlv_descriptor *d = (void *)s[i].addr;
        for (uint64_t k = 0; k < s[i].size / sizeof *d; k++) {
            d[k].thunk = ferry_tlv_bootstrap;
            d[k].key = key;
        }
    }
    __atomic_store_n(&nkeys, (int)key, __ATOMIC_RELEASE);
    pthread_mutex_unlock(&key_lock);
    if (ferry_verbose)
        fprintf(stderr, "ferry: %d thread-local variable%s in %s (%lu bytes a thread)\n", ndesc,
                ndesc == 1 ? "" : "s", path, (unsigned long)t->size);
    return 0;
}

/* ---- libSystem's calls ------------------------------------------------------- */

static void mac_tlv_atexit(void (*fn)(void *), void *obj)
{
    if (nterms == terms_cap) {
        size_t cap = terms_cap ? terms_cap * 2 : 16;
        struct terminator *n = realloc(terms, cap * sizeof *n);
        if (!n) {
            fflush(stdout);
            fputs("ferry: out of memory for a thread's destructors\n", stderr);
            _exit(126);
        }
        terms = n;
        terms_cap = cap;
    }
    terms[nterms].fn = fn;
    terms[nterms].obj = obj;
    nterms++;
    arm_exit();
}

/* The C++ ABI's spelling, which a Mac program may import too. */
static int mac_cxa_thread_atexit(void (*fn)(void *), void *obj, void *dso)
{
    (void)dso;
    mac_tlv_atexit(fn, obj);
    return 0;
}

/* exit runs the calling thread's thread-local destructors before the
 * static ones (__cxa_atexit's, run by this system's exit). */
__attribute__((noreturn)) static void mac_exit(int status)
{
    ferry_tlv_exit();
    exit(status);
}

const struct ferry_symbol ferry_tlv_symbols[] = {
    {"_tlv_bootstrap", (void *)ferry_tlv_bootstrap},
    {"_tlv_atexit", (void *)mac_tlv_atexit},
    {"_tlv_exit", (void *)ferry_tlv_exit},
    {"__cxa_thread_atexit", (void *)mac_cxa_thread_atexit},
    {"exit", (void *)mac_exit},
    {NULL, NULL},
};
