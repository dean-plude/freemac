/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's OpenGL framework: the OpenGL calls themselves (freemac 1.235,
 * Ferry 0.59.0).
 *
 * An OpenGL call is the same on a Mac and on Linux, and both use the System
 * V calling convention, so each call a program makes is passed to this
 * system's OpenGL as it stands, registers and stack untouched, as Ferry's
 * JavaScriptCore does with its C API. Each forwarder loads its entry and
 * jumps to GLDispatch, which jumps on to the entry's function while every
 * thread's current context is bound to it (GLInternal.h); otherwise, and
 * the first time a call is made, it goes through GLSlow, which binds this
 * thread's context, looks the call up and stores it in the entry. A call
 * this system's OpenGL lacks does nothing (and returns 0) after a warning.
 *
 * Apple's own extensions that Mesa doesn't have are answered here: vertex
 * array objects (as the core ones), fences (by finishing), and the hints
 * about texture and vertex ranges, purgeable objects and flushing (ignored,
 * as they change no result). Built without ARC. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "GLInternal.h"

struct GLEntry {
    void *function; /* GLSlow until the call is looked up */
    const char *name;
};

__attribute__((visibility("hidden"))) void GLSlow(void);
__attribute__((visibility("hidden"))) void GLDispatch(void);

static int missing_call(void) { return 0; }

/* ---- Apple's extensions ------------------------------------------------------------ */

typedef void (*fn_sizei_uintp)(GLsizei, GLuint *);
typedef void (*fn_sizei_cuintp)(GLsizei, const GLuint *);
typedef void (*fn_uint)(GLuint);
typedef GLboolean (*fn_isuint)(GLuint);
static void gl_flush(void)
{
    if (ferry_gl.Flush)
        ferry_gl.Flush();
}
static void gl_finish(void)
{
    if (ferry_gl.Finish)
        ferry_gl.Finish();
}

static void *host_call(void **slot, const char *name)
{
    void *p = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    if (!p) {
        p = ferry_gl_symbol(name);
        if (!p)
            p = (void *)missing_call;
        __atomic_store_n(slot, p, __ATOMIC_RELEASE);
    }
    return p;
}
#define HOST(type, name)                                                                                     \
    ({                                                                                                       \
        static void *slot;                                                                                   \
        (type) host_call(&slot, name);                                                                       \
    })

static void apple_GenVertexArrays(GLsizei n, GLuint *a) { HOST(fn_sizei_uintp, "glGenVertexArrays")(n, a); }
static void apple_DeleteVertexArrays(GLsizei n, const GLuint *a)
{
    HOST(fn_sizei_cuintp, "glDeleteVertexArrays")(n, a);
}
static void apple_BindVertexArray(GLuint a) { HOST(fn_uint, "glBindVertexArray")(a); }
static GLboolean apple_IsVertexArray(GLuint a) { return HOST(fn_isuint, "glIsVertexArray")(a); }

/* fences: one counter of names, each done once OpenGL has finished */
static GLuint fence_next;
static void apple_GenFences(GLsizei n, GLuint *f)
{
    for (GLsizei i = 0; i < n; i++)
        f[i] = __atomic_add_fetch(&fence_next, 1, __ATOMIC_ACQ_REL);
}
static void apple_DeleteFences(GLsizei n, const GLuint *f) {}
static GLboolean apple_IsFence(GLuint f) { return f && f <= __atomic_load_n(&fence_next, __ATOMIC_ACQUIRE); }
static void apple_SetFence(GLuint f) { gl_flush(); }
static GLboolean apple_TestFence(GLuint f)
{
    gl_finish();
    return 1;
}
static void apple_FinishFence(GLuint f) { gl_finish(); }
static GLboolean apple_TestObject(GLenum object, GLuint name)
{
    gl_finish();
    return 1;
}
static void apple_FinishObject(GLenum object, GLint name) { gl_finish(); }

static void apple_TextureRange(GLenum target, GLsizei length, const void *pointer) {}
static void apple_VertexArrayRange(GLsizei length, void *pointer) {}
static void apple_FlushVertexArrayRange(GLsizei length, void *pointer) {}
static void apple_VertexArrayParameteri(GLenum pname, GLint param) {}
static void apple_BufferParameteri(GLenum target, GLenum pname, GLint param) {}
static void apple_FlushMappedBufferRange(GLenum target, GLintptr offset, GLsizeiptr size) {}
#define FGL_RETAINED_APPLE 0x8A1B
static GLenum apple_ObjectPurgeable(GLenum type, GLuint name, GLenum option) { return FGL_RETAINED_APPLE; }
static GLenum apple_ObjectUnpurgeable(GLenum type, GLuint name, GLenum option) { return FGL_RETAINED_APPLE; }
static void apple_GetObjectParameteriv(GLenum type, GLuint name, GLenum pname, GLint *v)
{
    if (v)
        *v = FGL_RETAINED_APPLE;
}
static void apple_FlushRender(void) { gl_flush(); }
static void apple_FinishRender(void) { gl_finish(); }
static void apple_Swap(void) { CGLFlushDrawable(CGLGetCurrentContext()); }

static const struct {
    const char *name;
    void *function;
} apple_calls[] = {
    {"glGenVertexArraysAPPLE", (void *)apple_GenVertexArrays},
    {"glDeleteVertexArraysAPPLE", (void *)apple_DeleteVertexArrays},
    {"glBindVertexArrayAPPLE", (void *)apple_BindVertexArray},
    {"glIsVertexArrayAPPLE", (void *)apple_IsVertexArray},
    {"glGenFencesAPPLE", (void *)apple_GenFences},
    {"glDeleteFencesAPPLE", (void *)apple_DeleteFences},
    {"glIsFenceAPPLE", (void *)apple_IsFence},
    {"glSetFenceAPPLE", (void *)apple_SetFence},
    {"glTestFenceAPPLE", (void *)apple_TestFence},
    {"glFinishFenceAPPLE", (void *)apple_FinishFence},
    {"glTestObjectAPPLE", (void *)apple_TestObject},
    {"glFinishObjectAPPLE", (void *)apple_FinishObject},
    {"glTextureRangeAPPLE", (void *)apple_TextureRange},
    {"glVertexArrayRangeAPPLE", (void *)apple_VertexArrayRange},
    {"glFlushVertexArrayRangeAPPLE", (void *)apple_FlushVertexArrayRange},
    {"glVertexArrayParameteriAPPLE", (void *)apple_VertexArrayParameteri},
    {"glBufferParameteriAPPLE", (void *)apple_BufferParameteri},
    {"glFlushMappedBufferRangeAPPLE", (void *)apple_FlushMappedBufferRange},
    {"glObjectPurgeableAPPLE", (void *)apple_ObjectPurgeable},
    {"glObjectUnpurgeableAPPLE", (void *)apple_ObjectUnpurgeable},
    {"glGetObjectParameterivAPPLE", (void *)apple_GetObjectParameteriv},
    {"glFlushRenderAPPLE", (void *)apple_FlushRender},
    {"glFinishRenderAPPLE", (void *)apple_FinishRender},
    {"glSwapAPPLE", (void *)apple_Swap},
};

/* ---- looking a call up --------------------------------------------------------------- */

static void *resolve(const char *name)
{
    FerryGLOpen();
    for (size_t i = 0; i < sizeof apple_calls / sizeof *apple_calls; i++)
        if (!strcmp(apple_calls[i].name, name))
            return apple_calls[i].function;
    void *p = ferry_gl_symbol(name);
    if (p)
        return p;
    fflush(stdout);
    if (!ferry_gl_symbol("glGetString"))
        fprintf(stderr, "ferry: this program calls %s, and this system's OpenGL (libOpenGL.so.0 or libGL.so.1) "
                        "isn't installed; the call does nothing\n",
                name);
    else
        fprintf(stderr, "ferry: this system's OpenGL has no %s; the call does nothing\n", name);
    return (void *)missing_call;
}

/* Called by GLSlow with the entry's address; gives back the function. */
__attribute__((visibility("hidden"), used)) void *GLLookup(struct GLEntry *e)
{
    if (__atomic_load_n(&ferry_gl_pending, __ATOMIC_ACQUIRE))
        FerryGLBindCurrent();
    void *p = __atomic_load_n(&e->function, __ATOMIC_ACQUIRE);
    if (p == (void *)GLSlow) {
        p = resolve(e->name);
        __atomic_store_n(&e->function, p, __ATOMIC_RELEASE);
    }
    return p;
}

/* r11 holds the entry. GLDispatch goes straight to the call while no
 * thread is waiting to bind its context. GLSlow's frame keeps the six
 * argument registers, rax (a variadic call's vector-register count), r11
 * and the eight vector argument registers; the push of rbp leaves the
 * stack 16-byte aligned for the call, and 192 bytes keep it so. */
__asm__("\t.text\n"
        "\t.private_extern _GLDispatch\n"
        "\t.p2align 4\n"
        "_GLDispatch:\n"
        "\tcmpl $0, _ferry_gl_pending(%rip)\n"
        "\tjne _GLSlow\n"
        "\tjmpq *(%r11)\n"
        "\t.private_extern _GLSlow\n"
        "\t.p2align 4\n"
        "_GLSlow:\n"
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
        "\tcallq _GLLookup\n"
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
    __attribute__((visibility("hidden"))) struct GLEntry GLEntry_##name = {(void *)GLSlow, #name};          \
    __asm__("\t.text\n"                                                                                     \
            "\t.globl _" #name "\n"                                                                         \
            "\t.p2align 3\n"                                                                                \
            "_" #name ":\n"                                                                                 \
            "\tleaq _GLEntry_" #name "(%rip), %r11\n"                                                       \
            "\tjmp _GLDispatch\n");
#include "GLNames.h"
#undef X
