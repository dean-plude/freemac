/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSMethodSignature, NSInvocation, NSProxy and message
 * forwarding (methodSignatureForSelector: and forwardInvocation:), written
 * from Apple's public documentation of those classes and the Objective-C
 * type encodings, and from the public System V x86-64 ABI (the calling
 * convention a Mac and Linux share); no Apple code was used.
 *
 * A method signature is parsed from the method's type encoding. Each type
 * gets its size and alignment and, as the ABI's classification describes,
 * the class of each of its eightbytes: INTEGER (general registers), SSE
 * (vector registers) or MEMORY (the stack, or for a result the memory the
 * caller passes in a hidden first argument). A long double goes on the
 * stack as an argument and comes back on the x87 stack as a result.
 *
 * Calls go through one frame layout, FFrame below: the six general and
 * eight vector argument registers, the stack arguments, and the result
 * registers. Two small assembly routines move it in and out of the real
 * registers: FInvokeFrame calls a function with a frame's registers and
 * stack (for -invoke, through objc_msgSend so the message is looked up as
 * usual), and FForwardEntry is where the runtime sends a message nothing
 * implements, once forwardingTargetForSelector: has declined: it saves the
 * registers, builds an NSInvocation from them, hands it to
 * forwardInvocation: and returns the invocation's return value in the
 * registers the sender expects. Both carry call frame information, so an
 * exception thrown inside unwinds through them. Built without ARC. */
#import "FInternal.h"
#include <stddef.h>
#include <stdint.h>

void ferry_objc_setForwardHandler(void *fwd, void *fwd_stret);
extern char FMsgSendFp2ret[] __asm__("_objc_msgSend_fp2ret");   /* _Complex long double results */

/* ---- the frame ------------------------------------------------------------------ */

struct FFrame {
    uint64_t gpr[6];          /*   0: rdi rsi rdx rcx r8 r9 */
    uint64_t nsse;            /*  48: rax for a variadic callee: vector registers used */
    uint64_t x87;             /*  56: long doubles in the result (0, 1 or 2) */
    uint8_t xmm[8][16];       /*  64: xmm0-xmm7 */
    uint64_t rax, rdx;        /* 192: the result registers */
    uint8_t rxmm[2][16];      /* 208: xmm0, xmm1 as results */
    uint8_t st[2][16];        /* 240: st0, st1 */
    const uint8_t *stack;     /* 272: the stack arguments (forwarding) */
    uint64_t pad;
} __attribute__((aligned(16)));
_Static_assert(offsetof(struct FFrame, nsse) == 48, "frame");
_Static_assert(offsetof(struct FFrame, x87) == 56, "frame");
_Static_assert(offsetof(struct FFrame, xmm) == 64, "frame");
_Static_assert(offsetof(struct FFrame, rax) == 192, "frame");
_Static_assert(offsetof(struct FFrame, rxmm) == 208, "frame");
_Static_assert(offsetof(struct FFrame, st) == 240, "frame");
_Static_assert(offsetof(struct FFrame, stack) == 272, "frame");
_Static_assert(sizeof(struct FFrame) == 288, "frame");

void FInvokeFrame(struct FFrame *f, void *fn, const uint64_t *stack, size_t words);
void FForwardEntry(void);
void FForwardEntryStret(void);

/* FInvokeFrame(frame, fn, stack, words): copy the stack words, load the
 * argument registers from the frame, call fn, store the result registers
 * (and as many x87 values as frame->x87 says) back into the frame. */
__asm__(
    "    .text\n"
    "    .private_extern _FInvokeFrame\n"
    "    .globl _FInvokeFrame\n"
    "    .p2align 4\n"
    "_FInvokeFrame:\n"
    "    .cfi_startproc\n"
    "    pushq %rbp\n"
    "    .cfi_def_cfa_offset 16\n"
    "    .cfi_offset %rbp, -16\n"
    "    movq %rsp, %rbp\n"
    "    .cfi_def_cfa_register %rbp\n"
    "    pushq %rbx\n"
    "    pushq %r12\n"
    "    .cfi_offset %rbx, -24\n"
    "    .cfi_offset %r12, -32\n"
    "    movq %rdi, %rbx\n"
    "    movq %rsi, %r12\n"
    "    leaq 15(,%rcx,8), %rax\n"
    "    andq $-16, %rax\n"
    "    subq %rax, %rsp\n"
    "    xorl %eax, %eax\n"
    "1:  cmpq %rcx, %rax\n"
    "    jae 2f\n"
    "    movq (%rdx,%rax,8), %r8\n"
    "    movq %r8, (%rsp,%rax,8)\n"
    "    incq %rax\n"
    "    jmp 1b\n"
    "2:  movdqa 64(%rbx), %xmm0\n"
    "    movdqa 80(%rbx), %xmm1\n"
    "    movdqa 96(%rbx), %xmm2\n"
    "    movdqa 112(%rbx), %xmm3\n"
    "    movdqa 128(%rbx), %xmm4\n"
    "    movdqa 144(%rbx), %xmm5\n"
    "    movdqa 160(%rbx), %xmm6\n"
    "    movdqa 176(%rbx), %xmm7\n"
    "    movq 0(%rbx), %rdi\n"
    "    movq 8(%rbx), %rsi\n"
    "    movq 16(%rbx), %rdx\n"
    "    movq 24(%rbx), %rcx\n"
    "    movq 32(%rbx), %r8\n"
    "    movq 40(%rbx), %r9\n"
    "    movq 48(%rbx), %rax\n"
    "    callq *%r12\n"
    "    movq %rax, 192(%rbx)\n"
    "    movq %rdx, 200(%rbx)\n"
    "    movdqa %xmm0, 208(%rbx)\n"
    "    movdqa %xmm1, 224(%rbx)\n"
    "    movq 56(%rbx), %rcx\n"
    "    testq %rcx, %rcx\n"
    "    jz 3f\n"
    "    fstpt 240(%rbx)\n"
    "    cmpq $1, %rcx\n"
    "    je 3f\n"
    "    fstpt 256(%rbx)\n"
    "3:  leaq -16(%rbp), %rsp\n"
    "    popq %r12\n"
    "    popq %rbx\n"
    "    popq %rbp\n"
    "    retq\n"
    "    .cfi_endproc\n");

/* FForwardEntry and FForwardEntryStret: save the argument registers in a
 * frame on the stack, with a pointer to the sender's stack arguments, call
 * FForward(frame, hidden) and return what it left in the frame's result
 * registers, pushing the x87 values it counts. */
#define FORWARD_ENTRY(name, hidden)                                              \
    "    .text\n"                                                               \
    "    .private_extern _" name "\n"                                           \
    "    .globl _" name "\n"                                                    \
    "    .p2align 4\n"                                                          \
    "_" name ":\n"                                                              \
    "    .cfi_startproc\n"                                                      \
    "    pushq %rbp\n"                                                          \
    "    .cfi_def_cfa_offset 16\n"                                              \
    "    .cfi_offset %rbp, -16\n"                                               \
    "    movq %rsp, %rbp\n"                                                     \
    "    .cfi_def_cfa_register %rbp\n"                                          \
    "    subq $288, %rsp\n"                                                     \
    "    movq %rdi, 0(%rsp)\n"                                                  \
    "    movq %rsi, 8(%rsp)\n"                                                  \
    "    movq %rdx, 16(%rsp)\n"                                                 \
    "    movq %rcx, 24(%rsp)\n"                                                 \
    "    movq %r8, 32(%rsp)\n"                                                  \
    "    movq %r9, 40(%rsp)\n"                                                  \
    "    movq %rax, 48(%rsp)\n"                                                 \
    "    movdqa %xmm0, 64(%rsp)\n"                                              \
    "    movdqa %xmm1, 80(%rsp)\n"                                              \
    "    movdqa %xmm2, 96(%rsp)\n"                                              \
    "    movdqa %xmm3, 112(%rsp)\n"                                             \
    "    movdqa %xmm4, 128(%rsp)\n"                                             \
    "    movdqa %xmm5, 144(%rsp)\n"                                             \
    "    movdqa %xmm6, 160(%rsp)\n"                                             \
    "    movdqa %xmm7, 176(%rsp)\n"                                             \
    "    leaq 16(%rbp), %rax\n"                                                 \
    "    movq %rax, 272(%rsp)\n"                                                \
    "    movq %rsp, %rdi\n"                                                     \
    "    movl $" #hidden ", %esi\n"                                             \
    "    callq _FForward\n"                                                     \
    "    testl %eax, %eax\n"                                                    \
    "    jz 1f\n"                                                               \
    "    cmpl $1, %eax\n"                                                       \
    "    je 2f\n"                                                               \
    "    fldt 256(%rsp)\n"                                                      \
    "2:  fldt 240(%rsp)\n"                                                      \
    "1:  movq 192(%rsp), %rax\n"                                                \
    "    movq 200(%rsp), %rdx\n"                                                \
    "    movdqa 208(%rsp), %xmm0\n"                                             \
    "    movdqa 224(%rsp), %xmm1\n"                                             \
    "    leave\n"                                                               \
    "    retq\n"                                                                \
    "    .cfi_endproc\n"
__asm__(FORWARD_ENTRY("FForwardEntry", 0) FORWARD_ENTRY("FForwardEntryStret", 1));

/* ---- type encodings --------------------------------------------------------------- */

enum { K_NONE = 0, K_INT = 1, K_SSE = 2 };

/* How a value is classified for the calling convention. */
struct FClass {
    uint8_t eb[2];   /* the class of each eightbyte */
    uint8_t mem;     /* MEMORY: too big, unaligned, or holds a long double */
    uint8_t x87;     /* is a long double (or holds one) */
};

static void leaf(struct FClass *L, size_t off, size_t size, int kind)
{
    if (!L)
        return;
    if (kind == K_NONE) {   /* a long double */
        L->x87 = 1;
        L->mem = 1;
        return;
    }
    if (size && off % size)
        L->mem = 1;
    size_t e = off / 8;
    if (e >= 2 || (off + size - 1) / 8 != e) {
        L->mem = 1;
        return;
    }
    L->eb[e] = (kind == K_INT || L->eb[e] == K_INT) ? K_INT : K_SSE;
}

static const char *skip_qualifiers(const char *t)
{
    while (*t && strchr("rnNoORVA", *t))
        t++;
    return t;
}

static const char *skip_quoted(const char *t)
{
    if (*t != '"')
        return t;
    t++;
    while (*t && *t != '"')
        t++;
    return *t ? t + 1 : t;
}

static const char *skip_angles(const char *t)
{
    if (*t != '<')
        return t;
    int depth = 0;
    for (; *t; t++) {
        if (*t == '<')
            depth++;
        else if (*t == '>' && --depth == 0)
            return t + 1;
    }
    return t;
}

static size_t round_up(size_t n, size_t a) { return a ? (n + a - 1) / a * a : n; }

/* Reads one type at t: its size and alignment, and (when L is given) the
 * classes of its scalar parts placed at byte offset base. Returns the end of
 * the type, or NULL when the encoding can't be read. */
static const char *walk(const char *t, size_t base, size_t *size, size_t *align, struct FClass *L, int depth)
{
    if (depth > 64)
        return NULL;
    t = skip_qualifiers(t);
    size_t s = 0, a = 1;
    int kind = K_INT;
    switch (*t) {
    case 'c': case 'C': case 'B': s = 1; break;
    case 's': case 'S': s = 2; break;
    case 'i': case 'I': case 'l': case 'L': s = 4; break;
    case 'q': case 'Q': s = 8; break;
    case 'f': s = 4; kind = K_SSE; break;
    case 'd': s = 8; kind = K_SSE; break;
    case 'D': s = 16; kind = K_NONE; break;
    case '#': case ':': case '*': case '?': s = 8; break;
    case 'v':
        *size = 0;
        *align = 1;
        return t + 1;
    case '@':
        t++;
        if (*t == '?') {
            t = skip_angles(t + 1);
        } else if (*t == '"') {
            t = skip_quoted(t);
        }
        *size = *align = 8;
        leaf(L, base, 8, K_INT);
        return t;
    case '^': {
        t++;
        if (*t == '?') {
            t++;
        } else {
            size_t ps, pa;
            t = walk(t, 0, &ps, &pa, NULL, depth + 1);
            if (!t)
                return NULL;
        }
        *size = *align = 8;
        leaf(L, base, 8, K_INT);
        return t;
    }
    case 'j': {   /* _Complex: two of the element type */
        size_t es, ea;
        const char *end = walk(t + 1, base, &es, &ea, L, depth + 1);
        if (!end || !walk(t + 1, base + es, &es, &ea, L, depth + 1))
            return NULL;
        *size = es * 2;
        *align = ea;
        return end;
    }
    case '[': {
        char *end;
        unsigned long n = strtoul(t + 1, &end, 10);
        size_t es, ea;
        const char *after = walk(end, base, &es, &ea, NULL, depth + 1);
        if (!after || *after != ']')
            return NULL;
        if (L) {
            if (n * es > 16)
                L->mem = 1;
            else
                for (unsigned long i = 0; i < n; i++)
                    walk(end, base + i * es, &es, &ea, L, depth + 1);
        }
        *size = n * es;
        *align = ea;
        return after + 1;
    }
    case '{': case '(': {
        char close = *t == '{' ? '}' : ')';
        int is_union = *t == '(';
        t++;
        while (*t && *t != '=' && *t != close) {
            if (*t == '<')
                t = skip_angles(t);
            else
                t++;
        }
        size_t off = 0, max_align = 1, max_size = 0;
        size_t bits = 0;     /* a run of bit fields, packed from off */
        if (*t == '=') {
            t++;
            while (*t && *t != close) {
                if (*t == '"') {
                    t = skip_quoted(t);
                    continue;
                }
                if (*t == 'b') {
                    char *end;
                    bits += strtoul(t + 1, &end, 10);
                    t = end;
                    continue;
                }
                if (bits) {
                    size_t n = (bits + 7) / 8;
                    for (size_t i = 0; i < n; i++)
                        leaf(L, base + off + i, 1, K_INT);
                    off += n;
                    max_size = n > max_size ? n : max_size;
                    bits = 0;
                }
                size_t fs, fa;
                const char *end = walk(t, 0, &fs, &fa, NULL, depth + 1);
                if (!end)
                    return NULL;
                size_t foff = is_union ? 0 : round_up(off, fa);
                if (L)
                    walk(t, base + foff, &fs, &fa, L, depth + 1);
                off = foff + fs;
                if (fa > max_align)
                    max_align = fa;
                if (fs > max_size)
                    max_size = fs;
                t = end;
            }
            if (bits) {
                size_t n = (bits + 7) / 8;
                for (size_t i = 0; i < n; i++)
                    leaf(L, base + off + i, 1, K_INT);
                off += n;
                max_size = n > max_size ? n : max_size;
                if (max_align < 4)
                    max_align = 4;
            }
        }
        if (*t != close)
            return NULL;
        *size = round_up(is_union ? max_size : off, max_align);
        *align = max_align;
        if (L && *size > 16)
            L->mem = 1;
        return t + 1;
    }
    case 'b': {
        char *end;
        unsigned long n = strtoul(t + 1, &end, 10);
        *size = (n + 7) / 8;
        *align = 1;
        for (size_t i = 0; i < *size; i++)
            leaf(L, base + i, 1, K_INT);
        return end;
    }
    default:
        return NULL;
    }
    a = s;
    *size = s;
    *align = a;
    leaf(L, base, s, kind);
    return t + 1;
}

F_EXPORT const char *NSGetSizeAndAlignment(const char *typePtr, NSUInteger *sizep, NSUInteger *alignp)
{
    size_t s = 0, a = 1;
    const char *end = typePtr ? walk(typePtr, 0, &s, &a, NULL, 0) : NULL;
    if (!end)
        FRaise(NSInvalidArgumentException, @"NSGetSizeAndAlignment(): unsupported type encoding spec '%s'",
               typePtr ? typePtr : "(null)");
    if (sizep)
        *sizep = s;
    if (alignp)
        *alignp = a;
    while (*end == '+' || *end == '-' || (*end >= '0' && *end <= '9'))
        end++;
    return end;
}

/* One argument or the result, as the signature knows it. */
struct FArg {
    char *type;          /* the encoding, without offsets */
    char code;           /* its first character after qualifiers */
    BOOL block;          /* @? */
    size_t size, align;
    struct FClass cls;
    size_t slot;         /* offset in an invocation's argument buffer */
};

static NSUInteger arg_words(const struct FArg *a) { return (a->size + 7) / 8; }

/* A result that comes back on the x87 stack: 1 for a long double, 2 for a
 * _Complex long double. (A struct holding one comes back in memory here.) */
static int x87_values(const struct FArg *r)
{
    if (r->code == 'D')
        return 1;
    if (r->code == 'j' && r->cls.x87)
        return 2;
    return 0;
}

/* Does the value go in registers? (Otherwise the stack, or memory for a
 * result.) */
static BOOL in_registers(const struct FArg *a) { return a->size && a->size <= 16 && !a->cls.mem; }

/* Where one argument lives in a call: registers for each eightbyte (0-5
 * general, 16-23 vector) or a byte offset in the stack arguments. */
struct FPlace {
    int8_t reg[2];
    int32_t stack;
};

/* ---- NSMethodSignature -------------------------------------------------------------- */

@implementation NSMethodSignature {
    char *_types;
    struct FArg *_args;      /* the result first, then the arguments */
    NSUInteger _count;       /* arguments */
    NSUInteger _bufSize;     /* an invocation's argument buffer */
    BOOL _oneway;
}

static void free_args(struct FArg *args, NSUInteger n)
{
    for (NSUInteger i = 0; args && i < n; i++)
        free(args[i].type);
    free(args);
}

+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types
{
    if (!types)
        FRaise(NSInvalidArgumentException, @"+[NSMethodSignature signatureWithObjCTypes:]: type signature is NULL");
    NSUInteger cap = 8, n = 0;
    struct FArg *args = calloc(cap, sizeof *args);
    BOOL oneway = NO;
    const char *t = types;
    while (*t) {
        const char *start = t;
        const char *q = skip_qualifiers(t);
        if (n == 0 && memchr(start, 'V', (size_t)(q - start)))
            oneway = YES;
        struct FArg a;
        memset(&a, 0, sizeof a);
        const char *end = walk(t, 0, &a.size, &a.align, &a.cls, 0);
        if (!end) {
            free_args(args, n);
            FRaise(NSInvalidArgumentException, @"+[NSMethodSignature signatureWithObjCTypes:]: unsupported type "
                                               @"encoding spec '%s'", types);
        }
        a.code = *q;
        a.block = q[0] == '@' && q[1] == '?';
        a.type = strndup(start, (size_t)(end - start));
        if (n == cap) {
            cap *= 2;
            args = realloc(args, cap * sizeof *args);
        }
        args[n++] = a;
        t = end;
        while (*t == '+' || *t == '-' || (*t >= '0' && *t <= '9'))
            t++;
    }
    if (n < 1) {
        free_args(args, n);
        FRaise(NSInvalidArgumentException, @"+[NSMethodSignature signatureWithObjCTypes:]: empty type signature");
    }
    NSMethodSignature *sig = [[[self alloc] init] autorelease];
    sig->_types = strdup(types);
    sig->_args = args;
    sig->_count = n - 1;
    sig->_oneway = oneway;
    size_t off = 0;
    for (NSUInteger i = 1; i < n; i++) {
        args[i].slot = off;
        off += round_up(args[i].size ? args[i].size : 1, 16);
    }
    sig->_bufSize = off;
    return sig;
}

- (void)dealloc
{
    free(_types);
    free_args(_args, _count + 1);
    [super dealloc];
}

- (NSUInteger)numberOfArguments { return _count; }

- (const char *)getArgumentTypeAtIndex:(NSUInteger)idx
{
    if (idx >= _count)
        FRaise(NSInvalidArgumentException, @"-[NSMethodSignature getArgumentTypeAtIndex:]: index (%lu) out of "
                                           @"bounds [0, %ld]", (unsigned long)idx, (long)_count - 1);
    return _args[idx + 1].type;
}

- (const char *)methodReturnType { return _args[0].type; }
- (NSUInteger)methodReturnLength { return _args[0].size; }
- (BOOL)isOneway { return _oneway; }

/* Ferry's own measure: the register area of a call plus its stack arguments. */
- (NSUInteger)frameLength
{
    struct FPlace *p = calloc(_count ? _count : 1, sizeof *p);
    size_t stack = [self _placeArguments:p hidden:[self _returnsInMemory] sse:NULL];
    free(p);
    return 192 + stack;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSMethodSignature class]])
        return NO;
    NSMethodSignature *o = other;
    if (o->_count != _count)
        return NO;
    for (NSUInteger i = 0; i <= _count; i++)
        if (strcmp(_args[i].type, o->_args[i].type))
            return NO;
    return YES;
}

- (NSUInteger)hash
{
    NSUInteger h = _count;
    for (NSUInteger i = 0; i <= _count; i++)
        for (const char *c = _args[i].type; *c; c++)
            h = h * 31 + (unsigned char)*c;
    return h;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSMethodSignature: %p> %s", self, _types];
}

- (NSString *)debugDescription
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<NSMethodSignature: %p>\n    number of arguments = %lu\n"
                                                           @"    frame size = %lu\n    is special struct return? %@\n"
                                                           @"    return value: type encoding (%c) '%s'\n",
                                                           self, (unsigned long)_count, (unsigned long)[self frameLength],
                                                           [self _returnsInMemory] ? @"YES" : @"NO", _args[0].code,
                                                           _args[0].type];
    for (NSUInteger i = 1; i <= _count; i++)
        [s appendFormat:@"    argument %lu: type encoding (%c) '%s', size %lu\n", (unsigned long)(i - 1), _args[i].code,
                        _args[i].type, (unsigned long)_args[i].size];
    return s;
}

/* ---- for NSInvocation ---- */

- (const struct FArg *)_arg:(NSUInteger)i { return &_args[i + 1]; }
- (const struct FArg *)_result { return &_args[0]; }
- (NSUInteger)_bufferSize { return _bufSize; }

/* The result comes back in memory the caller provides (objc_msgSend_stret). */
- (BOOL)_returnsInMemory
{
    const struct FArg *r = &_args[0];
    return r->size && !x87_values(r) && !in_registers(r);
}

/* Assigns registers and stack slots to the arguments, as the ABI does in
 * order: an argument whose eightbytes don't all fit in the registers left
 * goes on the stack whole. hidden: the first general register holds the
 * result's address. Returns the bytes of stack arguments. */
- (size_t)_placeArguments:(struct FPlace *)out hidden:(BOOL)hidden sse:(unsigned *)nsse
{
    int gp = hidden ? 1 : 0, vec = 0;
    size_t stack = 0;
    for (NSUInteger i = 0; i < _count; i++) {
        const struct FArg *a = &_args[i + 1];
        struct FPlace *p = &out[i];
        p->reg[0] = p->reg[1] = -1;
        p->stack = -1;
        if (!a->size)
            continue;
        if (in_registers(a)) {
            NSUInteger n = arg_words(a);
            int ni = 0, ns = 0;
            for (NSUInteger e = 0; e < n; e++) {
                if (a->cls.eb[e] == K_SSE)
                    ns++;
                else
                    ni++;
            }
            if (gp + ni <= 6 && vec + ns <= 8) {
                for (NSUInteger e = 0; e < n; e++)
                    p->reg[e] = a->cls.eb[e] == K_SSE ? (int8_t)(16 + vec++) : (int8_t)gp++;
                continue;
            }
        }
        size_t al = a->align > 8 ? a->align : 8;
        stack = round_up(stack, al);
        p->stack = (int32_t)stack;
        stack += round_up(a->size, 8);
    }
    if (nsse)
        *nsse = (unsigned)vec;
    return stack;
}
@end

/* ---- NSInvocation --------------------------------------------------------------------- */

/* A scalar small integer widened to 64 bits as the registers carry it. */
static uint64_t widen(const struct FArg *a, const void *p)
{
    switch (a->code) {
    case 'c': return (uint64_t)(int64_t)*(const int8_t *)p;
    case 'C': case 'B': return *(const uint8_t *)p;
    case 's': return (uint64_t)(int64_t)*(const int16_t *)p;
    case 'S': return *(const uint16_t *)p;
    case 'i': case 'l': return (uint64_t)(int64_t)*(const int32_t *)p;
    case 'I': case 'L': return *(const uint32_t *)p;
    default: {
        uint64_t v = 0;
        memcpy(&v, p, a->size < 8 ? a->size : 8);
        return v;
    }
    }
}

static BOOL is_object(const struct FArg *a) { return a->code == '@'; }

@implementation NSInvocation {
    NSMethodSignature *_sig;
    uint8_t *_args;
    uint8_t *_ret;
    size_t _retCap;
    BOOL _retained;
    BOOL _retSet;
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig
{
    if (!sig)
        FRaise(NSInvalidArgumentException, @"+[NSInvocation invocationWithMethodSignature:]: method signature "
                                           @"argument cannot be nil");
    NSInvocation *inv = [[[self alloc] init] autorelease];
    inv->_sig = [sig retain];
    size_t n = [sig _bufferSize];
    if (posix_memalign((void **)&inv->_args, 16, n ? n : 16))
        abort();
    memset(inv->_args, 0, n ? n : 16);
    size_t r = [sig _result]->size;
    inv->_retCap = round_up(r > 32 ? r : 32, 16);
    if (posix_memalign((void **)&inv->_ret, 16, inv->_retCap))
        abort();
    memset(inv->_ret, 0, inv->_retCap);
    return inv;
}

- (void)_releaseArgument:(NSUInteger)i
{
    const struct FArg *a = [_sig _arg:i];
    void *p = _args + a->slot;
    if (is_object(a))
        [*(id *)p release];
    else if (a->code == '*')
        free(*(char **)p);
}

- (void)_retainArgument:(NSUInteger)i
{
    const struct FArg *a = [_sig _arg:i];
    void *p = _args + a->slot;
    if (a->block)
        *(id *)p = [*(id *)p copy];
    else if (is_object(a))
        [*(id *)p retain];
    else if (a->code == '*' && *(char **)p)
        *(char **)p = strdup(*(char **)p);
}

- (void)_retainResult:(BOOL)retain
{
    const struct FArg *r = [_sig _result];
    if (!_retSet || !is_object(r))
        return;
    if (retain)
        *(id *)_ret = r->block ? [*(id *)_ret copy] : [*(id *)_ret retain];
    else
        [*(id *)_ret release];
}

- (void)dealloc
{
    if (_retained) {
        for (NSUInteger i = 0; i < [_sig numberOfArguments]; i++)
            [self _releaseArgument:i];
        [self _retainResult:NO];
    }
    free(_args);
    free(_ret);
    [_sig release];
    [super dealloc];
}

- (NSMethodSignature *)methodSignature { return _sig; }
- (BOOL)argumentsRetained { return _retained; }

- (void)retainArguments
{
    if (_retained)
        return;
    _retained = YES;
    for (NSUInteger i = 0; i < [_sig numberOfArguments]; i++)
        [self _retainArgument:i];
    [self _retainResult:YES];
}

- (void)_checkIndex:(NSInteger)idx for:(SEL)cmd
{
    if (idx < 0 || (NSUInteger)idx >= [_sig numberOfArguments])
        FRaise(NSInvalidArgumentException, @"-[NSInvocation %s]: index (%ld) out of bounds [-1, %ld]", sel_getName(cmd),
               (long)idx, (long)[_sig numberOfArguments] - 1);
}

- (void)getArgument:(void *)buffer atIndex:(NSInteger)idx
{
    if (idx == -1) {
        [self getReturnValue:buffer];
        return;
    }
    [self _checkIndex:idx for:_cmd];
    const struct FArg *a = [_sig _arg:(NSUInteger)idx];
    memcpy(buffer, _args + a->slot, a->size);
}

- (void)setArgument:(void *)buffer atIndex:(NSInteger)idx
{
    if (idx == -1) {
        [self setReturnValue:buffer];
        return;
    }
    [self _checkIndex:idx for:_cmd];
    const struct FArg *a = [_sig _arg:(NSUInteger)idx];
    if (_retained)
        [self _releaseArgument:(NSUInteger)idx];
    memcpy(_args + a->slot, buffer, a->size);
    if (_retained)
        [self _retainArgument:(NSUInteger)idx];
}

- (id)target
{
    id t = nil;
    if ([_sig numberOfArguments] > 0)
        memcpy(&t, _args + [_sig _arg:0]->slot, sizeof t);
    return t;
}
- (void)setTarget:(id)target { [self setArgument:&target atIndex:0]; }

- (SEL)selector
{
    SEL s = NULL;
    if ([_sig numberOfArguments] > 1)
        memcpy(&s, _args + [_sig _arg:1]->slot, sizeof s);
    return s;
}
- (void)setSelector:(SEL)selector { [self setArgument:&selector atIndex:1]; }

- (void)getReturnValue:(void *)buffer
{
    memcpy(buffer, _ret, [_sig _result]->size);
}

- (void)setReturnValue:(void *)buffer
{
    if (_retained)
        [self _retainResult:NO];
    memcpy(_ret, buffer, [_sig _result]->size);
    _retSet = YES;
    if (_retained)
        [self _retainResult:YES];
}

- (void)invoke { [self invokeWithTarget:[self target]]; }

- (void)invokeWithTarget:(id)target
{
    if ([_sig numberOfArguments] < 2)
        FRaise(NSInvalidArgumentException, @"-[NSInvocation invokeWithTarget:]: the method signature has no "
                                           @"target and selector");
    if (target != [self target])
        [self setTarget:target];
    [self _invokeFunction:NULL];
}

/* Ferry's own: makes the call with function in place of objc_msgSend, with
 * the arguments as they stand, the first in the first argument register. A
 * block's invocation (its signature from _Block_signature) passes the block
 * there and the block's invoke function here; JavaScriptCore's ObjC layer
 * calls blocks this way (javascriptcore/JSValue.m). NULL sends the message. */
- (void)_invokeFunction:(void *)function
{
    const struct FArg *r = [_sig _result];
    BOOL hidden = [_sig _returnsInMemory];
    NSUInteger n = [_sig numberOfArguments];
    struct FPlace places[n ? n : 1];
    unsigned nsse = 0;
    size_t stackBytes = [_sig _placeArguments:places hidden:hidden sse:&nsse];
    uint64_t stack[stackBytes / 8 + 1];
    memset(stack, 0, sizeof stack);
    struct FFrame f;
    memset(&f, 0, sizeof f);
    if (hidden)
        f.gpr[0] = (uint64_t)(uintptr_t)_ret;
    for (NSUInteger i = 0; i < n; i++) {
        const struct FArg *a = [_sig _arg:i];
        const uint8_t *p = _args + a->slot;
        if (places[i].stack >= 0) {
            uint8_t *dst = (uint8_t *)stack + places[i].stack;
            if (a->size < 8 && a->code != '{' && a->code != '(' && a->code != '[') {
                uint64_t v = widen(a, p);
                memcpy(dst, &v, 8);
            } else {
                memcpy(dst, p, a->size);
            }
            continue;
        }
        NSUInteger words = arg_words(a);
        for (NSUInteger e = 0; e < words; e++) {
            int reg = places[i].reg[e];
            if (reg < 0)
                continue;
            size_t len = a->size - e * 8 < 8 ? a->size - e * 8 : 8;
            if (reg >= 16) {
                memcpy(f.xmm[reg - 16], p + e * 8, len);
            } else if (words == 1 && a->code != '{' && a->code != '(' && a->code != '[') {
                f.gpr[reg] = widen(a, p);
            } else {
                memcpy(&f.gpr[reg], p + e * 8, len);
            }
        }
    }
    f.nsse = nsse;
    f.x87 = (uint64_t)x87_values(r);
    if (_retained)
        [self _retainResult:NO];
    _retSet = NO;
    memset(_ret, 0, _retCap);
    void *fn = function      ? function
               : hidden      ? (void *)objc_msgSend_stret
               : f.x87 == 2 ? (void *)FMsgSendFp2ret
               : f.x87      ? (void *)objc_msgSend_fpret
                            : (void *)objc_msgSend;
    FInvokeFrame(&f, fn, stack, stackBytes / 8);
    if (!hidden && r->size) {
        if (f.x87) {
            /* the x87 80-bit values, stored in 16-byte slots as C keeps long double */
            memcpy(_ret, f.st[0], 16);
            if (f.x87 == 2)
                memcpy(_ret + 16, f.st[1], 16);
        } else {
            unsigned gi = 0, si = 0;
            for (NSUInteger e = 0; e < arg_words(r); e++) {
                size_t len = r->size - e * 8 < 8 ? r->size - e * 8 : 8;
                if (r->cls.eb[e] == K_SSE)
                    memcpy(_ret + e * 8, f.rxmm[si++], len);
                else
                    memcpy(_ret + e * 8, gi++ ? &f.rdx : &f.rax, len);
            }
        }
    }
    _retSet = YES;
    if (_retained)
        [self _retainResult:YES];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSInvocation: %p>", self];
}

/* ---- forwarding ---- */

/* An invocation holding the arguments of a call caught in frame f. */
+ (NSInvocation *)_invocationWithSignature:(NSMethodSignature *)sig frame:(const struct FFrame *)f hidden:(BOOL)hidden
{
    NSInvocation *inv = [self invocationWithMethodSignature:sig];
    NSUInteger n = [sig numberOfArguments];
    struct FPlace places[n ? n : 1];
    [sig _placeArguments:places hidden:hidden sse:NULL];
    for (NSUInteger i = 0; i < n; i++) {
        const struct FArg *a = [sig _arg:i];
        uint8_t *p = inv->_args + a->slot;
        if (places[i].stack >= 0) {
            memcpy(p, f->stack + places[i].stack, a->size);
            continue;
        }
        for (NSUInteger e = 0; e < arg_words(a); e++) {
            int reg = places[i].reg[e];
            if (reg < 0)
                continue;
            size_t len = a->size - e * 8 < 8 ? a->size - e * 8 : 8;
            memcpy(p + e * 8, reg >= 16 ? (const void *)f->xmm[reg - 16] : (const void *)&f->gpr[reg], len);
        }
    }
    return inv;
}

/* Puts the return value where the sender of the forwarded message expects
 * it. Returns the number of x87 values to push. */
- (int)_storeResultInFrame:(struct FFrame *)f hidden:(BOOL)hidden
{
    const struct FArg *r = [_sig _result];
    f->rax = f->rdx = 0;
    memset(f->rxmm, 0, sizeof f->rxmm);
    if (hidden) {
        void *dst = (void *)(uintptr_t)f->gpr[0];
        if (dst && r->size)
            memcpy(dst, _ret, r->size);
        f->rax = f->gpr[0];
        return 0;
    }
    if (!r->size)
        return 0;
    int x87 = x87_values(r);
    if (x87) {
        memcpy(f->st[0], _ret, 16);
        if (x87 == 2)
            memcpy(f->st[1], _ret + 16, 16);
        return x87;
    }
    unsigned gi = 0, si = 0;
    NSUInteger words = arg_words(r);
    for (NSUInteger e = 0; e < words; e++) {
        size_t len = r->size - e * 8 < 8 ? r->size - e * 8 : 8;
        if (r->cls.eb[e] == K_SSE) {
            memcpy(f->rxmm[si++], _ret + e * 8, len);
        } else {
            uint64_t *dst = gi++ ? &f->rdx : &f->rax;
            if (words == 1 && r->code != '{' && r->code != '(' && r->code != '[')
                *dst = widen(r, _ret);
            else
                memcpy(dst, _ret + e * 8, len);
        }
    }
    return 0;
}
@end

/* Called by FForwardEntry with the registers of a message nothing
 * implements. hidden: it was sent with objc_msgSend_stret. */
__attribute__((used)) int FForward(struct FFrame *f, int hidden)
{
    id self = (id)(uintptr_t)f->gpr[hidden ? 1 : 0];
    SEL sel = (SEL)(uintptr_t)f->gpr[hidden ? 2 : 1];
    Class cls = object_getClass(self);
    NSMethodSignature *sig = nil;
    if (sel != @selector(methodSignatureForSelector:) &&
        class_respondsToSelector(cls, @selector(methodSignatureForSelector:)))
        sig = [self methodSignatureForSelector:sel];
    if (!sig || !class_respondsToSelector(cls, @selector(forwardInvocation:))) {
        [self doesNotRecognizeSelector:sel];
        fflush(stdout);
        fprintf(stderr, "ferry: doesNotRecognizeSelector: returned for %s\n", sel_getName(sel));
        abort();
    }
    if ((BOOL)hidden != [sig _returnsInMemory]) {
        fflush(stdout);
        fprintf(stderr, "ferry: -[%s %s] was sent with %s, but its method signature's result (%s) %s\n",
                class_getName(cls), sel_getName(sel), hidden ? "objc_msgSend_stret" : "objc_msgSend",
                [sig methodReturnType], hidden ? "comes back in registers" : "comes back in memory");
        if (!hidden)
            abort();   /* there is no memory to put it in */
    }
    NSInvocation *inv = [NSInvocation _invocationWithSignature:sig frame:f hidden:(BOOL)hidden];
    [self forwardInvocation:inv];
    return [inv _storeResultInFrame:f hidden:(BOOL)hidden];
}

__attribute__((constructor)) static void forwarding_init(void)
{
    ferry_objc_setForwardHandler((void *)FForwardEntry, (void *)FForwardEntryStret);
}

/* ---- NSObject's side ---------------------------------------------------------------- */

@implementation NSObject (NSForwarding)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    Method m = sel ? class_getInstanceMethod(object_getClass(self), sel) : NULL;
    const char *types = m ? method_getTypeEncoding(m) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}

+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)sel
{
    Method m = sel ? class_getInstanceMethod((Class)self, sel) : NULL;
    const char *types = m ? method_getTypeEncoding(m) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    [self doesNotRecognizeSelector:[invocation selector]];
}
@end

/* ---- NSProxy ---------------------------------------------------------------------- */

/* NSProxy is a root class of its own. Its reference counting is NSObject's
 * (the runtime keeps the count in front of every object it allocates). The
 * NSObject protocol's questions about the object's kind (isKindOfClass:,
 * respondsToSelector:, conformsToProtocol: and the like) are not answered
 * here, so they are forwarded to whatever the proxy stands for. */
static IMP root_imp(SEL sel) { return class_getMethodImplementation([NSObject class], sel); }

@implementation NSProxy
+ (void)load {}
+ (void)initialize {}
+ (id)alloc { return [self allocWithZone:NULL]; }
+ (id)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
+ (Class)class { return self; }
+ (Class)superclass { return class_getSuperclass(self); }
+ (BOOL)respondsToSelector:(SEL)sel { return sel && class_respondsToSelector(object_getClass(self), sel); }
+ (BOOL)instancesRespondToSelector:(SEL)sel { return sel && class_respondsToSelector(self, sel); }
+ (BOOL)resolveClassMethod:(SEL)sel { return NO; }
+ (BOOL)resolveInstanceMethod:(SEL)sel { return NO; }
+ (BOOL)isSubclassOfClass:(Class)cls
{
    for (Class c = self; c; c = class_getSuperclass(c))
        if (c == cls)
            return YES;
    return NO;
}
+ (id)retain { return self; }
+ (oneway void)release {}
+ (id)autorelease { return self; }
+ (NSUInteger)retainCount { return NSUIntegerMax; }
+ (NSString *)description { return [NSString stringWithUTF8String:class_getName(self)]; }
+ (NSUInteger)hash { return (NSUInteger)self; }
+ (BOOL)isEqual:(id)other { return self == other; }
+ (id)self { return self; }
+ (BOOL)isProxy { return NO; }
+ (IMP)instanceMethodForSelector:(SEL)sel { return class_getMethodImplementation(self, sel); }

- (void)dealloc { object_dispose(self); }
- (void)finalize {}
- (id)retain { return ((id (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (oneway void)release { ((void (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (id)autorelease { return ((id (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (NSUInteger)retainCount { return ((NSUInteger (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (BOOL)_tryRetain { return ((BOOL (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (BOOL)_isDeallocating { return ((BOOL (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (BOOL)allowsWeakReference { return YES; }
- (BOOL)retainWeakReference { return ((BOOL (*)(id, SEL))root_imp(_cmd))(self, _cmd); }
- (NSZone *)zone { return NULL; }
- (Class)class { return object_getClass(self); }
- (Class)superclass { return class_getSuperclass(object_getClass(self)); }
- (id)self { return self; }
- (BOOL)isProxy { return YES; }
- (NSUInteger)hash { return (NSUInteger)self; }
- (BOOL)isEqual:(id)other { return self == other; }
- (id)performSelector:(SEL)sel { return ((id (*)(id, SEL))objc_msgSend)(self, sel); }
- (id)performSelector:(SEL)sel withObject:(id)a { return ((id (*)(id, SEL, id))objc_msgSend)(self, sel, a); }
- (id)performSelector:(SEL)sel withObject:(id)a withObject:(id)b
{
    return ((id (*)(id, SEL, id, id))objc_msgSend)(self, sel, a, b);
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s: %p>", class_getName(object_getClass(self)), self];
}
- (NSString *)debugDescription { return [self description]; }
- (void)doesNotRecognizeSelector:(SEL)sel { ((void (*)(id, SEL, SEL))root_imp(_cmd))(self, _cmd, sel); }

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    FRaise(NSInvalidArgumentException, @"-[NSProxy methodSignatureForSelector:] called!");
}
- (void)forwardInvocation:(NSInvocation *)invocation
{
    FRaise(NSInvalidArgumentException, @"-[NSProxy forwardInvocation:] called!");
}
@end
