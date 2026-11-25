/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * setjmp and longjmp for Mac programs (freemac 1.232, Ferry 0.56.0). A
 * Mac's jmp_buf is 37 ints (148 bytes) and its sigjmp_buf 38, smaller than
 * the one this system's C library fills, so a Mac program can't use the
 * system's own. This one keeps what the System V AMD64 convention says a
 * call must preserve (rbx, rbp, r12 to r15, the stack pointer and the
 * return address), the SSE and x87 control words, and, for setjmp and
 * sigsetjmp(env, 1), the thread's signal mask:
 *
 *   0 rbx  8 rbp  16 r12  24 r13  32 r14  40 r15  48 rsp  56 return address
 *   64 mxcsr  68 x87 control word  72 whether the mask was kept  80 the mask
 *
 * libpng and FreeType, which Qt brings, report errors this way.
 */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include "ferry.h"

__attribute__((visibility("hidden"), used)) int ferry_setjmp_keep_mask(char *env, int keep);
__attribute__((visibility("hidden"), noreturn)) void ferry_longjmp_regs(char *env, int value);
int ferry_mac_setjmp(char *env);
int ferry_mac__setjmp(char *env);
int ferry_mac_sigsetjmp(char *env, int keep);

#define SAVE_REGS                    \
    "    movq %rbx, 0(%rdi)\n"       \
    "    movq %rbp, 8(%rdi)\n"       \
    "    movq %r12, 16(%rdi)\n"      \
    "    movq %r13, 24(%rdi)\n"      \
    "    movq %r14, 32(%rdi)\n"      \
    "    movq %r15, 40(%rdi)\n"      \
    "    leaq 8(%rsp), %rax\n"       \
    "    movq %rax, 48(%rdi)\n"      \
    "    movq (%rsp), %rax\n"        \
    "    movq %rax, 56(%rdi)\n"      \
    "    stmxcsr 64(%rdi)\n"         \
    "    fnstcw 68(%rdi)\n"

__asm__(
    ".text\n"
    ".globl ferry_mac_setjmp\n"
    ".type ferry_mac_setjmp, @function\n"
    "ferry_mac_setjmp:\n"
    SAVE_REGS
    "    movl $1, %esi\n"
    "    jmp ferry_setjmp_keep_mask\n"
    ".size ferry_mac_setjmp, .-ferry_mac_setjmp\n"

    ".globl ferry_mac_sigsetjmp\n"
    ".type ferry_mac_sigsetjmp, @function\n"
    "ferry_mac_sigsetjmp:\n"
    SAVE_REGS
    "    jmp ferry_setjmp_keep_mask\n"
    ".size ferry_mac_sigsetjmp, .-ferry_mac_sigsetjmp\n"

    ".globl ferry_mac__setjmp\n"
    ".type ferry_mac__setjmp, @function\n"
    "ferry_mac__setjmp:\n"
    SAVE_REGS
    "    movl $0, 72(%rdi)\n"
    "    xorl %eax, %eax\n"
    "    ret\n"
    ".size ferry_mac__setjmp, .-ferry_mac__setjmp\n"

    ".globl ferry_longjmp_regs\n"
    ".hidden ferry_longjmp_regs\n"
    ".type ferry_longjmp_regs, @function\n"
    "ferry_longjmp_regs:\n"
    "    movq 0(%rdi), %rbx\n"
    "    movq 8(%rdi), %rbp\n"
    "    movq 16(%rdi), %r12\n"
    "    movq 24(%rdi), %r13\n"
    "    movq 32(%rdi), %r14\n"
    "    movq 40(%rdi), %r15\n"
    "    ldmxcsr 64(%rdi)\n"
    "    fldcw 68(%rdi)\n"
    "    movl %esi, %eax\n"
    "    testl %eax, %eax\n"
    "    jnz 1f\n"
    "    movl $1, %eax\n"
    "1:  movq 48(%rdi), %rsp\n"
    "    jmpq *56(%rdi)\n"
    ".size ferry_longjmp_regs, .-ferry_longjmp_regs\n");

/* setjmp's second half: it returns 0 straight to setjmp's caller. */
int ferry_setjmp_keep_mask(char *env, int keep)
{
    int flag = keep != 0;
    memcpy(env + 72, &flag, sizeof flag);
    if (flag) {
        sigset_t set;
        sigemptyset(&set);
        pthread_sigmask(SIG_BLOCK, NULL, &set);
        uint64_t bits = 0;
        for (int s = 1; s <= 64; s++)
            if (sigismember(&set, s) == 1)
                bits |= 1ull << (s - 1);
        memcpy(env + 80, &bits, sizeof bits);
    }
    return 0;
}

static void mac_longjmp(char *env, int value)
{
    int flag;
    memcpy(&flag, env + 72, sizeof flag);
    if (flag) {
        uint64_t bits;
        memcpy(&bits, env + 80, sizeof bits);
        sigset_t set;
        sigemptyset(&set);
        for (int s = 1; s <= 64; s++)
            if (bits & (1ull << (s - 1)))
                sigaddset(&set, s);
        pthread_sigmask(SIG_SETMASK, &set, NULL);
    }
    ferry_longjmp_regs(env, value);
}

static void mac__longjmp(char *env, int value) { ferry_longjmp_regs(env, value); }

/* What a Mac calls when a longjmp's buffer is no good; Ferry doesn't check. */
static void mac_longjmperror(void)
{
    fputs("longjmp botch.\n", stderr);
    abort();
}

const struct ferry_symbol ferry_setjmp_symbols[] = {
    {"setjmp", ferry_mac_setjmp},
    {"_setjmp", ferry_mac__setjmp},
    {"sigsetjmp", ferry_mac_sigsetjmp},
    {"longjmp", mac_longjmp},
    {"_longjmp", mac__longjmp},
    {"siglongjmp", mac_longjmp},
    {"longjmperror", mac_longjmperror},
    {NULL, NULL},
};
