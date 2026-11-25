/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's JavaScriptCore: the C API (freemac 1.222, Ferry 0.46.0).
 *
 * Every call of the C API except the two CFString ones goes to this
 * system's JavaScriptCore (libjavascriptcoregtk-4.1), which has the same C
 * API: the Mac program and the Linux library both use the System V calling
 * convention, so a call can be passed on as it stands, registers and
 * stack untouched. Each forwarder below is two instructions: it loads its
 * entry's address and jumps to the entry's function. That starts as
 * JSCResolve, which saves the argument registers, looks the call up by
 * name through ferry_jsc_symbol() (src/host.c), stores what it found in the
 * entry and jumps there with the registers restored, so the library is
 * opened the first time a program makes a call, and each later call goes
 * straight through. A system without the library ends the program with a
 * message saying so, as Ferry's WebKit does without WebKitGTK. Built
 * without ARC. */
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <stdio.h>
#include <stdlib.h>

void *ferry_jsc_symbol(const char *name);

struct JSCEntry {
    void *function; /* JSCResolve until the call is looked up */
    const char *name;
};

__attribute__((visibility("hidden"))) void JSCResolve(void);

/* Called by JSCResolve with the entry's address; gives back the function. */
__attribute__((visibility("hidden"), used)) void *JSCLookup(struct JSCEntry *e)
{
    void *p = ferry_jsc_symbol(e->name);
    if (!p) {
        fflush(stdout);
        fprintf(stderr, "ferry: this program runs JavaScript with JavaScriptCore, and this system's "
                        "JavaScriptCore (libjavascriptcoregtk-4.1) %s\n",
                ferry_jsc_symbol("JSGlobalContextCreate") ? "lacks a call it makes" : "isn't installed");
        fprintf(stderr, "ferry: the call was %s\n", e->name);
        exit(127);
    }
    __atomic_store_n(&e->function, p, __ATOMIC_RELEASE);
    return p;
}

/* r11 holds the entry. The frame keeps the six argument registers, rax (the
 * vector-register count of a variadic call), r11 and the eight vector
 * argument registers; the push of rbp leaves the stack 16-byte aligned for
 * the call, and 192 bytes keep it so. */
__asm__("\t.text\n"
        "\t.private_extern _JSCResolve\n"
        "\t.p2align 4\n"
        "_JSCResolve:\n"
        "\tpushq %rbp\n"
        "\tmovq %rsp, %rbp\n"
        "\tsubq $192, %rsp\n"
        "\tmovq %rdi, 0(%rsp)\n"
        "\tmovq %rsi, 8(%rsp)\n"
        "\tmovq %rdx, 16(%rsp)\n"
        "\tmovq %rcx, 24(%rsp)\n"
        "\tmovq %r8, 32(%rsp)\n"
        "\tmovq %r9, 40(%rsp)\n"
        "\tmovq %rax, 48(%rsp)\n"
        "\tmovq %r11, 56(%rsp)\n"
        "\tmovdqu %xmm0, 64(%rsp)\n"
        "\tmovdqu %xmm1, 80(%rsp)\n"
        "\tmovdqu %xmm2, 96(%rsp)\n"
        "\tmovdqu %xmm3, 112(%rsp)\n"
        "\tmovdqu %xmm4, 128(%rsp)\n"
        "\tmovdqu %xmm5, 144(%rsp)\n"
        "\tmovdqu %xmm6, 160(%rsp)\n"
        "\tmovdqu %xmm7, 176(%rsp)\n"
        "\tmovq %r11, %rdi\n"
        "\tcallq _JSCLookup\n"
        "\tmovq %rax, %r11\n"
        "\tmovq 0(%rsp), %rdi\n"
        "\tmovq 8(%rsp), %rsi\n"
        "\tmovq 16(%rsp), %rdx\n"
        "\tmovq 24(%rsp), %rcx\n"
        "\tmovq 32(%rsp), %r8\n"
        "\tmovq 40(%rsp), %r9\n"
        "\tmovq 48(%rsp), %rax\n"
        "\tmovdqu 64(%rsp), %xmm0\n"
        "\tmovdqu 80(%rsp), %xmm1\n"
        "\tmovdqu 96(%rsp), %xmm2\n"
        "\tmovdqu 112(%rsp), %xmm3\n"
        "\tmovdqu 128(%rsp), %xmm4\n"
        "\tmovdqu 144(%rsp), %xmm5\n"
        "\tmovdqu 160(%rsp), %xmm6\n"
        "\tmovdqu 176(%rsp), %xmm7\n"
        "\tleave\n"
        "\tjmpq *%r11\n");

#define X(name)                                                                                             \
    __attribute__((visibility("hidden"))) struct JSCEntry JSCEntry_##name = {(void *)JSCResolve, #name};    \
    __asm__("\t.text\n"                                                                                     \
            "\t.globl _" #name "\n"                                                                         \
            "\t.p2align 4\n"                                                                                \
            "_" #name ":\n"                                                                                 \
            "\tleaq _JSCEntry_" #name "(%rip), %r11\n"                                                      \
            "\tjmpq *(%r11)\n");
#include "JSCNames.h"
#undef X

/* All zero, as the C API's documentation gives it. */
const JSClassDefinition kJSClassDefinitionEmpty = {0};

JSStringRef JSStringCreateWithCFString(CFStringRef string)
{
    CFIndex n = string ? CFStringGetLength(string) : 0;
    JSChar small[256];
    JSChar *chars = n <= 256 ? small : malloc((size_t)n * sizeof(JSChar));
    if (n)
        CFStringGetCharacters(string, CFRangeMake(0, n), (UniChar *)chars);
    JSStringRef s = JSStringCreateWithCharacters(chars, (size_t)n);
    if (chars != small)
        free(chars);
    return s;
}

CFStringRef JSStringCopyCFString(CFAllocatorRef allocator, JSStringRef string)
{
    if (!string)
        return NULL;
    return CFStringCreateWithCharacters(allocator, (const UniChar *)JSStringGetCharactersPtr(string),
                                        (CFIndex)JSStringGetLength(string));
}
