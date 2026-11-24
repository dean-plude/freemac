/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Objective-C message dispatch for x86-64 (System V calling
 * convention, which macOS and Linux share).
 *
 *   objc_msgSend(self, _cmd, ...)            self in %rdi, selector in %rsi
 *   objc_msgSend_stret(ret, self, _cmd, ...)  struct results: shifted by one
 *   objc_msgSendSuper(super, _cmd, ...)      super = {receiver, class to search}
 *   objc_msgSendSuper2(super, _cmd, ...)     super = {receiver, current class}
 *
 * The fast path looks the selector up in the class's method cache (an open
 * hash table of {selector, IMP} pairs; see objc-private.h) and jumps to the
 * method with every argument register untouched. %rax is preserved because
 * it carries the vector-register count for variadic methods. A miss saves
 * all argument registers and asks ferry_objc_lookup() in runtime.c.
 */

#define CLS_CACHE 16
#define CLS_MASK  24

/* %r10 = class to search; \sel = selector register. Jumps to \miss with
 * %r10 intact when the selector isn't cached. Other threads may be filling
 * the cache or replacing it with a bigger one meanwhile: the mask is read
 * once, before the table, and a writer stores a new table before its new
 * mask (runtime.c), so the mask read never runs past the table read. */
.macro PROBE sel, miss
    pushq   %rax
    pushq   %rbx
    movq    CLS_MASK(%r10), %rbx
    movq    CLS_CACHE(%r10), %r11
    movq    \sel, %rax
    shlq    $4, %rax
1:  andq    %rbx, %rax
    cmpq    \sel, (%r11,%rax)
    je      2f
    cmpq    $0, (%r11,%rax)
    je      3f
    addq    $16, %rax
    jmp     1b
2:  movq    8(%r11,%rax), %r11
    popq    %rbx
    popq    %rax
    jmp     *%r11
3:  popq    %rbx
    popq    %rax
    jmp     \miss
.endm

/* Save every argument register, call \fn(\a, \b, %r10, \stret), restore
 * them and jump to the IMP it returned. */
.macro SLOW fn, a, b, stret
    pushq   %rbp
    movq    %rsp, %rbp
    subq    $192, %rsp
    movq    %rdi, 0(%rsp)
    movq    %rsi, 8(%rsp)
    movq    %rdx, 16(%rsp)
    movq    %rcx, 24(%rsp)
    movq    %r8, 32(%rsp)
    movq    %r9, 40(%rsp)
    movq    %rax, 48(%rsp)
    movdqa  %xmm0, 64(%rsp)
    movdqa  %xmm1, 80(%rsp)
    movdqa  %xmm2, 96(%rsp)
    movdqa  %xmm3, 112(%rsp)
    movdqa  %xmm4, 128(%rsp)
    movdqa  %xmm5, 144(%rsp)
    movdqa  %xmm6, 160(%rsp)
    movdqa  %xmm7, 176(%rsp)
    movq    \a, %rdi
    movq    \b, %rsi
    movq    %r10, %rdx
    movl    $\stret, %ecx
    call    \fn
    movq    %rax, %r11
    movq    0(%rsp), %rdi
    movq    8(%rsp), %rsi
    movq    16(%rsp), %rdx
    movq    24(%rsp), %rcx
    movq    32(%rsp), %r8
    movq    40(%rsp), %r9
    movq    48(%rsp), %rax
    movdqa  64(%rsp), %xmm0
    movdqa  80(%rsp), %xmm1
    movdqa  96(%rsp), %xmm2
    movdqa  112(%rsp), %xmm3
    movdqa  128(%rsp), %xmm4
    movdqa  144(%rsp), %xmm5
    movdqa  160(%rsp), %xmm6
    movdqa  176(%rsp), %xmm7
    leave
    jmp     *%r11
.endm

.macro FUNC name
    .text
    .globl  \name
    .type   \name, @function
    .p2align 4
\name:
.endm

/* ---- objc_msgSend and friends --------------------------------------------- */

FUNC ferry_objc_msgSend
    testq   %rdi, %rdi
    jz      .Lnil
    movq    (%rdi), %r10
    PROBE   %rsi, .Lslow
.Lslow:
    SLOW    ferry_objc_lookup, %rdi, %rsi, 0
.Lnil:
    xorl    %eax, %eax
    xorl    %edx, %edx
    xorps   %xmm0, %xmm0
    xorps   %xmm1, %xmm1
    ret
    .size ferry_objc_msgSend, .-ferry_objc_msgSend

/* long double results come back on the x87 stack */
FUNC ferry_objc_msgSend_fpret
    testq   %rdi, %rdi
    jz      1f
    jmp     ferry_objc_msgSend
1:  fldz
    xorl    %eax, %eax
    xorl    %edx, %edx
    ret
    .size ferry_objc_msgSend_fpret, .-ferry_objc_msgSend_fpret

/* _Complex long double: two x87 values */
FUNC ferry_objc_msgSend_fp2ret
    testq   %rdi, %rdi
    jz      1f
    jmp     ferry_objc_msgSend
1:  fldz
    fldz
    xorl    %eax, %eax
    xorl    %edx, %edx
    ret
    .size ferry_objc_msgSend_fp2ret, .-ferry_objc_msgSend_fp2ret

FUNC ferry_objc_msgSend_stret
    testq   %rsi, %rsi
    jz      .Lnil_stret
    movq    (%rsi), %r10
    PROBE   %rdx, .Lslow_stret
.Lslow_stret:
    SLOW    ferry_objc_lookup, %rsi, %rdx, 1
.Lnil_stret:
    movq    %rdi, %rax
    ret
    .size ferry_objc_msgSend_stret, .-ferry_objc_msgSend_stret

/* struct objc_super { id receiver; Class cls; } */
FUNC ferry_objc_msgSendSuper
    movq    8(%rdi), %r10
    movq    (%rdi), %rdi
    PROBE   %rsi, .Lslow
    .size ferry_objc_msgSendSuper, .-ferry_objc_msgSendSuper

FUNC ferry_objc_msgSendSuper2
    movq    8(%rdi), %r10
    movq    8(%r10), %r10           /* start at the current class's superclass */
    movq    (%rdi), %rdi
    PROBE   %rsi, .Lslow
    .size ferry_objc_msgSendSuper2, .-ferry_objc_msgSendSuper2

FUNC ferry_objc_msgSendSuper_stret
    movq    8(%rsi), %r10
    movq    (%rsi), %rsi
    PROBE   %rdx, .Lslow_stret
    .size ferry_objc_msgSendSuper_stret, .-ferry_objc_msgSendSuper_stret

FUNC ferry_objc_msgSendSuper2_stret
    movq    8(%rsi), %r10
    movq    8(%r10), %r10
    movq    (%rsi), %rsi
    PROBE   %rdx, .Lslow_stret
    .size ferry_objc_msgSendSuper2_stret, .-ferry_objc_msgSendSuper2_stret

/* ---- forwarding ---------------------------------------------------------------
 * The IMP for a selector nothing implements. ferry_objc_forward() finds
 * another receiver (forwardingTargetForSelector:) or stops the program;
 * the message is then sent again to the new receiver. */

/* Message references (__objc_msgrefs), from compilers of the Mac OS X 10.5
 * and 10.6 era: a call goes through {function, selector} pairs, with the
 * pair's address where the selector would be. The loader registers each
 * pair's selector, so these only fetch it and send as usual. */
.macro FIXUP name, reg, target
FUNC \name
    movq    8(\reg), \reg
    jmp     \target
    .size \name, .-\name
.endm
FIXUP ferry_objc_msgSend_fixup, %rsi, ferry_objc_msgSend
FIXUP ferry_objc_msgSend_fpret_fixup, %rsi, ferry_objc_msgSend_fpret
FIXUP ferry_objc_msgSend_fp2ret_fixup, %rsi, ferry_objc_msgSend_fp2ret
FIXUP ferry_objc_msgSend_stret_fixup, %rdx, ferry_objc_msgSend_stret
FIXUP ferry_objc_msgSendSuper2_fixup, %rsi, ferry_objc_msgSendSuper2
FIXUP ferry_objc_msgSendSuper2_stret_fixup, %rdx, ferry_objc_msgSendSuper2_stret

FUNC ferry_objc_msgForward
    xorl    %r10d, %r10d
    SLOW    ferry_objc_forward_target, %rdi, %rsi, 0
    .size ferry_objc_msgForward, .-ferry_objc_msgForward

FUNC ferry_objc_msgForward_stret
    xorl    %r10d, %r10d
    SLOW    ferry_objc_forward_target, %rsi, %rdx, 1
    .size ferry_objc_msgForward_stret, .-ferry_objc_msgForward_stret

/* Continue a forwarded send: ferry_objc_forward_target returns the address
 * of one of these after storing the new receiver in ferry_objc_fwd_target. */
FUNC ferry_objc_resend
    movq    %fs:0, %r11
    movq    ferry_objc_fwd_target@gottpoff(%rip), %r10
    movq    (%r11,%r10), %rdi
    jmp     ferry_objc_msgSend
    .size ferry_objc_resend, .-ferry_objc_resend

FUNC ferry_objc_resend_stret
    movq    %fs:0, %r11
    movq    ferry_objc_fwd_target@gottpoff(%rip), %r10
    movq    (%r11,%r10), %rsi
    jmp     ferry_objc_msgSend_stret
    .size ferry_objc_resend_stret, .-ferry_objc_resend_stret

    .section .note.GNU-stack,"",@progbits
