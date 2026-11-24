/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The register work of Ferry's exception unwinder (exception.c), for
 * x86-64. The entry points a Mac program calls to throw, rethrow or carry
 * on unwinding save the caller's registers, as they are at the call, into
 * a block on the stack (struct uctx: DWARF register numbers, 16 is the
 * return address), and hand that block to C. ferry_unwind_jump loads such
 * a block and jumps into a landing pad.
 *
 * Once a program has brought in C++ (src/cxx.c), every exception is unwound
 * by this system's unwinder instead, which reads the caller's frame itself:
 * the entry points then jump straight to the calls set in the three
 * pointers named below, leaving the stack as the program left it.
 */

.macro CAPTURE name, target, host
    .globl  \name
    .type   \name, @function
\name:
    movq    \host(%rip), %r11       /* once a program uses C++, this system's unwinder (exception.c) */
    testq   %r11, %r11
    jz      1f
    jmp     *%r11
1:
    movq    %rsp, %rax              /* (%rax) is the return address */
    subq    $152, %rsp              /* 17 registers, keeping %rsp 16-byte aligned for the call */
    movq    %rbx, 24(%rsp)
    movq    %rbp, 48(%rsp)
    movq    %r12, 96(%rsp)
    movq    %r13, 104(%rsp)
    movq    %r14, 112(%rsp)
    movq    %r15, 120(%rsp)
    leaq    8(%rax), %rcx           /* the caller's %rsp once the call has returned */
    movq    %rcx, 56(%rsp)
    movq    (%rax), %rcx
    movq    %rcx, 128(%rsp)
    movq    %rsp, %rsi              /* %rdi: the program's own argument */
    call    \target
    ud2
    .size   \name, . - \name
.endm

    .text
CAPTURE ferry_objc_exception_throw, ferry_throw_with, ferry_objc_throw_host
CAPTURE ferry_objc_exception_rethrow, ferry_rethrow_with, ferry_objc_rethrow_host
CAPTURE ferry_unwind_resume, ferry_resume_with, ferry_unwind_resume_host

    .globl  ferry_unwind_jump
    .type   ferry_unwind_jump, @function
ferry_unwind_jump:
    movq    0(%rdi), %rax
    movq    8(%rdi), %rdx
    movq    24(%rdi), %rbx
    movq    48(%rdi), %rbp
    movq    96(%rdi), %r12
    movq    104(%rdi), %r13
    movq    112(%rdi), %r14
    movq    120(%rdi), %r15
    movq    128(%rdi), %rcx
    movq    56(%rdi), %rsp
    jmp     *%rcx
    .size   ferry_unwind_jump, . - ferry_unwind_jump

    .section .note.GNU-stack, "", @progbits
