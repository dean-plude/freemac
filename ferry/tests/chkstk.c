/* SPDX-License-Identifier: GPL-3.0-or-later
 * ___chkstk_darwin, the stack probe Xcode's compilers call before a large
 * stack frame (Qt and FFmpeg in OBS's download): it keeps every register,
 * %rax included, and the frame it probed for can be used (freemac 1.263). */
#include <stdio.h>
#include <string.h>

void ___chkstk_darwin(void);

static int use(int n)
{
    volatile char big[n];
    memset((char *)big, 1, n);
    return big[n - 1] + big[0];
}

int main(void)
{
    unsigned long sizes[] = {16, 4096, 70000, 1 << 20};
    for (int i = 0; i < 4; i++) {
        unsigned long out, rcx = 77, rcx_out;
        __asm__ volatile("movq %2, %%rax\n\tmovq %3, %%rcx\n\tcall ____chkstk_darwin\n\tmovq %%rax, %0\n\tmovq %%rcx, %1"
                         : "=r"(out), "=r"(rcx_out)
                         : "r"(sizes[i]), "r"(rcx)
                         : "rax", "rcx", "memory");
        printf("probe %lu bytes: rax kept %s, rcx kept %s\n", sizes[i], out == sizes[i] ? "yes" : "no",
               rcx_out == rcx ? "yes" : "no");
    }
    printf("a frame of 300000 bytes: %d\n", use(300000));
    return 0;
}
