/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Blocks (closures) for Mac programs, following clang's published block ABI
 * ("Block Implementation Specification", clang/docs/Block-ABI-Apple.rst).
 * On a Mac these calls live in libSystem; blocks are also Objective-C
 * objects, so heap blocks are runtime objects of class __NSMallocBlock__ and
 * objc_retain/objc_release work on them.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#include "../ferry.h"
#include "objc-private.h"

/* Block flags from the ABI document; BLOCK_NEEDS_FREE is the runtime's. */
#define BLOCK_NEEDS_FREE (1 << 24)
#define BLOCK_HAS_COPY_DISPOSE (1 << 25)
#define BLOCK_HAS_CTOR (1 << 26)
#define BLOCK_IS_GLOBAL (1 << 28)
#define BLOCK_HAS_STRET (1 << 29)
#define BLOCK_HAS_SIGNATURE (1 << 30)

/* _Block_object_assign / _Block_object_dispose flags */
#define FIELD_IS_OBJECT 3
#define FIELD_IS_BLOCK 7
#define FIELD_IS_BYREF 8
#define FIELD_IS_WEAK 16
#define BYREF_CALLER 128

struct block_descriptor {
    unsigned long reserved, size;
    /* then copy and dispose helpers if BLOCK_HAS_COPY_DISPOSE, then the
     * signature if BLOCK_HAS_SIGNATURE */
    void *rest[];
};

struct block {
    Class isa;
    int32_t flags, reserved;
    void (*invoke)(void *, ...);
    struct block_descriptor *descriptor;
};

typedef void (*copy_helper)(void *dst, const void *src);
typedef void (*dispose_helper)(const void *);

/* __block variables */
struct byref {
    void *isa;
    struct byref *forwarding;
    int32_t flags;
    uint32_t size;
    void (*keep)(struct byref *dst, struct byref *src);
    void (*destroy)(struct byref *);
};
#define BYREF_HAS_COPY_DISPOSE (1 << 25)
#define BYREF_ON_HEAP (1 << 24)          /* the runtime's own mark */
struct byref_head { uintptr_t refs, reserved; };

/* The block classes; the program's blocks point at these directly
 * (_NSConcreteStackBlock and friends). */
struct fobjc_class ferry_block_NSBlock, ferry_meta_NSBlock;
struct fobjc_class ferry_block_stack, ferry_meta_stack;
struct fobjc_class ferry_block_global, ferry_meta_global;
struct fobjc_class ferry_block_malloc, ferry_meta_malloc;
struct fobjc_class ferry_block_weak_variable;
void *ferry_block_auto[32];
void *ferry_block_finalizing[32];

static int is_heap(const struct block *b)
{
    return b->isa == &ferry_block_malloc || (b->flags & BLOCK_NEEDS_FREE);
}

void *_Block_copy(const void *arg)
{
    const struct block *b = arg;
    if (!b)
        return NULL;
    if (is_heap(b))
        return objc_retain((id)b);
    if (b->isa == &ferry_block_global || (b->flags & BLOCK_IS_GLOBAL))
        return (void *)b;
    struct block *copy = (struct block *)ferry_objc_alloc_sized(&ferry_block_malloc, b->descriptor->size);
    memmove(copy, b, b->descriptor->size);
    copy->isa = &ferry_block_malloc;
    copy->flags = (b->flags & ~0xffff) | BLOCK_NEEDS_FREE;
    if (b->flags & BLOCK_HAS_COPY_DISPOSE)
        FN(copy_helper, b->descriptor->rest[0])(copy, b);
    return copy;
}

void _Block_release(const void *arg)
{
    const struct block *b = arg;
    if (b && is_heap(b))
        objc_release((id)b);
}

static struct byref *byref_copy(struct byref *src)
{
    src = src->forwarding;
    if (src->flags & BYREF_ON_HEAP) {
        __atomic_fetch_add(&((struct byref_head *)src - 1)->refs, 1, __ATOMIC_RELAXED);
        return src;
    }
    struct byref_head *h = calloc(1, sizeof *h + src->size);
    struct byref *copy = (struct byref *)(h + 1);
    h->refs = 2;    /* one for the heap copy, one for the stack variable's owner */
    memcpy(copy, src, src->size);
    copy->forwarding = copy;
    copy->flags |= BYREF_ON_HEAP;
    src->forwarding = copy;
    if (src->flags & BYREF_HAS_COPY_DISPOSE)
        copy->keep(copy, src);
    return copy;
}

static void byref_release(struct byref *b)
{
    b = b->forwarding;
    if (!(b->flags & BYREF_ON_HEAP))
        return;
    struct byref_head *h = (struct byref_head *)b - 1;
    if (__atomic_sub_fetch(&h->refs, 1, __ATOMIC_ACQ_REL) == 0) {
        if (b->flags & BYREF_HAS_COPY_DISPOSE)
            b->destroy(b);
        free(h);
    }
}

void _Block_object_assign(void *dest, const void *object, int flags)
{
    void **slot = dest;
    if (flags & BYREF_CALLER) {
        /* From a __block variable's helpers: objects and blocks held there
         * are not retained outside ARC, so just copy the pointer. */
        if ((flags & FIELD_IS_BYREF) == FIELD_IS_BYREF)
            *slot = byref_copy((struct byref *)object);
        else
            *slot = (void *)object;
        return;
    }
    if ((flags & FIELD_IS_BYREF) == FIELD_IS_BYREF)
        *slot = byref_copy((struct byref *)object);
    else if ((flags & FIELD_IS_BLOCK) == FIELD_IS_BLOCK)
        *slot = _Block_copy(object);
    else if ((flags & FIELD_IS_OBJECT) == FIELD_IS_OBJECT)
        *slot = objc_retain((id)object);
    else
        *slot = (void *)object;
}

void _Block_object_dispose(const void *object, int flags)
{
    if (flags & BYREF_CALLER) {
        if ((flags & FIELD_IS_BYREF) == FIELD_IS_BYREF)
            byref_release((struct byref *)object);
        return;
    }
    if ((flags & FIELD_IS_BYREF) == FIELD_IS_BYREF)
        byref_release((struct byref *)object);
    else if ((flags & FIELD_IS_BLOCK) == FIELD_IS_BLOCK)
        _Block_release(object);
    else if ((flags & FIELD_IS_OBJECT) == FIELD_IS_OBJECT)
        objc_release((id)object);
}

size_t Block_size(void *arg)
{
    return arg ? ((struct block *)arg)->descriptor->size : 0;
}

int _Block_has_signature(void *arg)
{
    return arg && (((struct block *)arg)->flags & BLOCK_HAS_SIGNATURE);
}

const char *_Block_signature(void *arg)
{
    struct block *b = arg;
    if (!_Block_has_signature(b))
        return NULL;
    int i = (b->flags & BLOCK_HAS_COPY_DISPOSE) ? 2 : 0;
    return b->descriptor->rest[i];
}

int _Block_use_stret(void *arg)
{
    struct block *b = arg;
    return b && (b->flags & BLOCK_HAS_SIGNATURE) && (b->flags & BLOCK_HAS_STRET);
}

int _Block_isDeallocating(const void *arg) { (void)arg; return 0; }
int _Block_tryRetain(const void *arg) { _Block_copy(arg); return 1; }

/* ---- block objects -------------------------------------------------------- */

static id b_copy(id self, SEL _cmd) { (void)_cmd; return _Block_copy(self); }
static id b_copyWithZone(id self, SEL _cmd, void *z) { (void)_cmd; (void)z; return _Block_copy(self); }
static void b_invoke(id self, SEL _cmd) { (void)_cmd; ((struct block *)self)->invoke(self); }
static id b_self(id self, SEL _cmd) { (void)_cmd; return self; }

static void malloc_dealloc(id self, SEL _cmd)
{
    (void)_cmd;
    struct block *b = (struct block *)self;
    if (b->flags & BLOCK_HAS_COPY_DISPOSE)
        FN(dispose_helper, b->descriptor->rest[1])(b);
    object_dispose(self);
}

#define M(sel, types, fn) {sel, types, (IMP)(void (*)(void))(fn)}

/* ---- imp_implementationWithBlock ---------------------------------------------
 * An IMP that calls a block with the receiver as its first argument: a small
 * piece of code that moves self into the second argument register, puts the
 * block in the first and jumps to the block's invoke function. */

struct tramp_page { uint8_t *code; size_t used; };
static struct tramp_page tramp;
#define TRAMP_SIZE 16
struct tramp_rec { void *imp; void *block; struct tramp_rec *next; };
static struct tramp_rec *tramps;

IMP imp_implementationWithBlock(id block)
{
    struct block *b = _Block_copy(block);
    if (!b)
        return NULL;
    LOCK();
    if (!tramp.code || tramp.used + TRAMP_SIZE > 4096) {
        tramp.code = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        tramp.used = 0;
    }
    uint8_t *p = tramp.code + tramp.used;
    tramp.used += TRAMP_SIZE;
    mprotect(tramp.code, 4096, PROT_READ | PROT_WRITE);
    uint64_t addr = (uint64_t)b;
    if (_Block_use_stret(b)) {
        p[0] = 0x48; p[1] = 0x89; p[2] = 0xf2;              /* mov %rsi,%rdx */
        p[3] = 0x48; p[4] = 0xbe; memcpy(p + 5, &addr, 8);  /* movabs $block,%rsi */
        p[13] = 0xff; p[14] = 0x66; p[15] = 0x10;           /* jmp *16(%rsi) */
    } else {
        p[0] = 0x48; p[1] = 0x89; p[2] = 0xfe;              /* mov %rdi,%rsi */
        p[3] = 0x48; p[4] = 0xbf; memcpy(p + 5, &addr, 8);  /* movabs $block,%rdi */
        p[13] = 0xff; p[14] = 0x67; p[15] = 0x10;           /* jmp *16(%rdi) */
    }
    mprotect(tramp.code, 4096, PROT_READ | PROT_EXEC);
    struct tramp_rec *r = malloc(sizeof *r);
    r->imp = p;
    r->block = b;
    r->next = tramps;
    tramps = r;
    UNLOCK();
    return (IMP)p;
}

id imp_getBlock(IMP imp)
{
    id block = nil;
    LOCK();
    for (struct tramp_rec *r = tramps; r; r = r->next)
        if (r->imp == (void *)imp)
            block = r->block;
    UNLOCK();
    return block;
}

BOOL imp_removeBlock(IMP imp)
{
    struct tramp_rec **pp, *found = NULL;
    LOCK();
    for (pp = &tramps; *pp; pp = &(*pp)->next)
        if ((*pp)->imp == (void *)imp) {
            found = *pp;
            *pp = found->next;
            break;
        }
    UNLOCK();
    if (!found)
        return NO;
    _Block_release(found->block);
    free(found);   /* the code slot itself isn't reused */
    return YES;
}

/* ---- setup ------------------------------------------------------------------ */

void ferry_blocks_init(void)
{
    static const struct fmethod nsblock[] = {
        M("copy", "@16@0:8", b_copy),
        M("copyWithZone:", "@24@0:8^v16", b_copyWithZone),
        M("invoke", "v16@0:8", b_invoke),
    };
    static const struct fmethod malloc_m[] = {
        M("dealloc", "v16@0:8", malloc_dealloc),
    };
    struct fmethod st[8];
    unsigned n = ferry_static_rr_count;
    memcpy(st, ferry_static_rr_methods, n * sizeof st[0]);
    ferry_objc_make_class(&ferry_block_NSBlock, &ferry_meta_NSBlock, &ferry_class_NSObject, "NSBlock",
                          sizeof(struct block), nsblock, 3, NULL, 0, 0);
    ferry_objc_make_class(&ferry_block_stack, &ferry_meta_stack, &ferry_block_NSBlock, "__NSStackBlock__",
                          sizeof(struct block), st, n, NULL, 0, RT_STATIC_INSTANCES);
    st[n] = (struct fmethod)M("copy", "@16@0:8", b_self);
    st[n + 1] = (struct fmethod)M("copyWithZone:", "@24@0:8^v16", b_self);
    ferry_objc_make_class(&ferry_block_global, &ferry_meta_global, &ferry_block_NSBlock, "__NSGlobalBlock__",
                          sizeof(struct block), st, n + 2, NULL, 0, RT_STATIC_INSTANCES);
    ferry_objc_make_class(&ferry_block_malloc, &ferry_meta_malloc, &ferry_block_NSBlock, "__NSMallocBlock__",
                          sizeof(struct block), malloc_m, 1, NULL, 0, 0);
}

/* What libSystem exports for blocks. */
const struct ferry_symbol ferry_blocks_symbols[] = {
    {"_NSConcreteStackBlock", &ferry_block_stack},
    {"_NSConcreteGlobalBlock", &ferry_block_global},
    {"_NSConcreteMallocBlock", &ferry_block_malloc},
    {"_NSConcreteAutoBlock", ferry_block_auto},
    {"_NSConcreteFinalizingBlock", ferry_block_finalizing},
    {"_NSConcreteWeakBlockVariable", &ferry_block_weak_variable},
    {"_Block_copy", _Block_copy},
    {"_Block_release", _Block_release},
    {"_Block_object_assign", _Block_object_assign},
    {"_Block_object_dispose", _Block_object_dispose},
    {"Block_size", Block_size},
    {"_Block_has_signature", _Block_has_signature},
    {"_Block_signature", _Block_signature},
    {"_Block_use_stret", _Block_use_stret},
    {"_Block_isDeallocating", _Block_isDeallocating},
    {"_Block_tryRetain", _Block_tryRetain},
    {NULL, NULL},
};
