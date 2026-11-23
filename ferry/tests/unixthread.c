/* SPDX-License-Identifier: GPL-3.0-or-later
 * A program in the start-up format of Mac OS X 10.7 and earlier
 * (LC_UNIXTHREAD). run.sh links it as usual, then tools/unixthread.py
 * swaps its LC_MAIN for a thread command starting at old_start below,
 * which does what the compilers' crt1 start routine of that era did: take
 * argc, argv and the environment from the stack the kernel built, call
 * main, and exit with its result. */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    const char *v = getenv("FERRY_TEST_VALUE");
    printf("started from the thread command: argc %d, argv[1] %s, FERRY_TEST_VALUE %s\n", argc,
           argc > 1 ? argv[1] : "-", v ? v : "unset");
    return 3;
}

__asm__(".globl _old_start\n"
        "_old_start:\n"
        "    pushq $0\n"
        "    movq %rsp, %rbp\n"
        "    andq $-16, %rsp\n"
        "    movq 8(%rbp), %rdi\n"      /* argc */
        "    leaq 16(%rbp), %rsi\n"     /* argv */
        "    leal 1(%rdi), %edx\n"
        "    shll $3, %edx\n"
        "    addq %rsi, %rdx\n"         /* envp, after argv's NULL */
        "    call _main\n"
        "    movl %eax, %edi\n"
        "    call _exit\n"
        "    hlt\n");
