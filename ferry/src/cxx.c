/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * C++ programs. A Mac program written in C++ links /usr/lib/libc++.1.dylib
 * and /usr/lib/libc++abi.dylib: LLVM's open-source libc++ and libc++abi,
 * which Linux has too. Both follow the Itanium C++ ABI on 64-bit Intel and
 * put the library in the same std::__1 inline namespace, so a C++ name a
 * Mac program imports is, without Mach-O's leading underscore, the name of
 * the same call in this system's libc++.so.1 and libc++abi.so.1. Ferry
 * opens those (and the LLVM libunwind they use) the first time a program
 * that links them is loaded, so programs that don't never load them and
 * Ferry still starts on a system without them.
 *
 * What differs is corrected:
 *
 *   - Exceptions. This system's libc++abi throws and catches, and its
 *     unwinder walks the stack. It finds Linux code's unwind tables itself;
 *     for each Mac image Ferry writes the DWARF call frame information the
 *     unwinder reads (cxx_unwind.c), from the image's compact unwind table,
 *     naming the image's own personality routine and LSDA. A C++ exception
 *     thrown by Mac code or by libc++ itself then passes through Mac and
 *     Linux frames alike, running destructors, as on a Mac. Objective-C
 *     exceptions take the same road once libc++ is open (objc/exception.c).
 *   - Data that holds a pthread type, whose Mac layout differs from
 *     Linux's: std::mutex, std::condition_variable, std::thread and the
 *     classes built on them (cxx_threads.c).
 *   - Error numbers in std::error_code and the stream positions holding a
 *     Mac mbstate_t (cxx_threads.c).
 *
 * Written from the Itanium C++ ABI specification and the public
 * documentation of the libraries; this system's libc++ is only loaded and
 * called, never copied.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "cxx.h"
#include "ferry.h"

int ferry_cxx_active;
struct ferry_cxx_unwinder ferry_cxx_unwind;

static void *cxx_handle, *abi_handle, *unwind_handle;
static int cxx_tried;

/* The Mac install names, and the libraries serving them. */
static const char *const mac_names[] = {
    "/usr/lib/libc++.1.dylib", "/usr/lib/libc++.dylib", "/usr/lib/libc++abi.dylib", NULL,
};

static void (*add_dynamic_fde)(const void *fde);   /* LLVM libunwind */
static void (*register_frame)(const void *fde);    /* the same, under the name libgcc also has */

static void add_fde(const void *fde)
{
    if (add_dynamic_fde)
        add_dynamic_fde(fde);
    else if (register_frame)
        register_frame(fde);
}

/* Images whose unwind information the unwinder has been given. */
static uint64_t *described;
static int ndescribed, described_cap;
static pthread_mutex_t describe_lock = PTHREAD_MUTEX_INITIALIZER;

static void describe(uint64_t header)
{
    pthread_mutex_lock(&describe_lock);
    for (int i = 0; i < ndescribed; i++)
        if (described[i] == header) {
            pthread_mutex_unlock(&describe_lock);
            return;
        }
    if (ndescribed == described_cap) {
        described_cap = described_cap ? described_cap * 2 : 16;
        described = realloc(described, (size_t)described_cap * sizeof *described);
    }
    described[ndescribed++] = header;
    int n = ferry_cxx_describe_image(header, add_fde);
    pthread_mutex_unlock(&describe_lock);
    if (ferry_verbose)
        fprintf(stderr, "ferry: described %d functions of the image at %#lx to the C++ unwinder\n", n,
                (unsigned long)header);
}

void ferry_cxx_image_loaded(struct image *im)
{
    if (ferry_cxx_active && im)
        describe((uint64_t)ferry_image_header(im));
}

void *ferry_cxx_symbol(const char *name)
{
    if (!cxx_handle || !name)
        return NULL;
    void *addr = dlsym(cxx_handle, name);
    if (!addr && abi_handle)
        addr = dlsym(abi_handle, name);
    return addr;
}

#define NEED(field, name)                                                                                      \
    do {                                                                                                       \
        *(void **)&ferry_cxx_unwind.field = dlsym(unwind_handle ? unwind_handle : cxx_handle, name);           \
        if (!ferry_cxx_unwind.field)                                                                           \
            *(void **)&ferry_cxx_unwind.field = dlsym(cxx_handle, name);                                       \
        if (!ferry_cxx_unwind.field)                                                                           \
            missing = name;                                                                                    \
    } while (0)

static void open_cxx(void)
{
    const char *path = getenv("FERRY_LIBCXX");
    if (!path || !*path)
        path = "libc++.so.1";
    /* Some other library already in the program's global scope (GNU
     * libstdc++, through a library opened with RTLD_GLOBAL) would take
     * libc++abi's place for the names both have: say so if it happens. */
    if (dlsym(RTLD_DEFAULT, "__cxa_throw") && ferry_verbose)
        fprintf(stderr, "ferry: another C++ runtime is already loaded; C++ exceptions may not work\n");
    cxx_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!cxx_handle) {
        fflush(stdout);
        fprintf(stderr,
                "ferry: this program is written in C++ and needs this system's libc++ and libc++abi "
                "(packages libc++1 and libc++abi1), which aren't installed (%s)\n",
                dlerror());
        _exit(127);
    }
    abi_handle = dlopen("libc++abi.so.1", RTLD_NOW | RTLD_LOCAL | RTLD_NOLOAD);
    unwind_handle = dlopen("libunwind.so.1", RTLD_NOW | RTLD_LOCAL | RTLD_NOLOAD);
    const char *missing = NULL;
    NEED(raise, "_Unwind_RaiseException");
    NEED(resume, "_Unwind_Resume");
    NEED(delete_exception, "_Unwind_DeleteException");
    NEED(get_lsda, "_Unwind_GetLanguageSpecificData");
    NEED(get_region_start, "_Unwind_GetRegionStart");
    NEED(get_ip, "_Unwind_GetIP");
    NEED(set_ip, "_Unwind_SetIP");
    NEED(set_gr, "_Unwind_SetGR");
    *(void **)&ferry_cxx_unwind.begin_catch = dlsym(cxx_handle, "__cxa_begin_catch");
    *(void **)&ferry_cxx_unwind.end_catch = dlsym(cxx_handle, "__cxa_end_catch");
    *(void **)&ferry_cxx_unwind.terminate = dlsym(cxx_handle, "_ZSt9terminatev");
    *(void **)&ferry_cxx_unwind.gxx_personality = dlsym(cxx_handle, "__gxx_personality_v0");
    if (!ferry_cxx_unwind.begin_catch || !ferry_cxx_unwind.end_catch || !ferry_cxx_unwind.terminate ||
        !ferry_cxx_unwind.gxx_personality)
        missing = "__cxa_begin_catch";
    *(void **)&add_dynamic_fde = dlsym(unwind_handle ? unwind_handle : cxx_handle, "__unw_add_dynamic_fde");
    *(void **)&register_frame = dlsym(unwind_handle ? unwind_handle : cxx_handle, "__register_frame");
    if (missing || (!add_dynamic_fde && !register_frame)) {
        fflush(stdout);
        fprintf(stderr, "ferry: this system's libc++ lacks %s, which Ferry needs to run C++ programs\n",
                missing ? missing : "__unw_add_dynamic_fde");
        _exit(127);
    }
    ferry_cxx_threads_init();
    ferry_objc_exceptions_to_host();
    ferry_cxx_active = 1;
    if (ferry_verbose)
        fprintf(stderr, "ferry: opened this system's libc++ for the program's C++\n");
    /* the images loaded so far (their code is mapped, which is all this needs) */
    for (int i = 0; i < ferry_image_count(); i++)
        describe((uint64_t)ferry_image_header(ferry_image_at(i)));
}

int ferry_cxx_library(const char *install_name)
{
    for (int i = 0; mac_names[i]; i++)
        if (!strcmp(install_name, mac_names[i])) {
            if (!cxx_tried) {
                cxx_tried = 1;
                open_cxx();
            }
            return 1;
        }
    return 0;
}

/* The names this system's libc++ and libc++abi serve: mangled C++ names
 * and the C++ ABI's own calls. Never C library calls, which its handle
 * would also find (in its dependencies) and which Ferry converts itself. */
static int is_cxx_name(const char *name)
{
    return !strncmp(name, "_Z", 2) || !strncmp(name, "__cxa_", 6) || !strcmp(name, "__gxx_personality_v0") ||
           !strcmp(name, "__dynamic_cast");
}

void *ferry_cxx_lookup(const char *name)
{
    if (!ferry_cxx_active || !is_cxx_name(name))
        return NULL;
    for (const struct ferry_symbol *s = ferry_cxx_overrides; s->name; s++)
        if (!strcmp(s->name, name))
            return s->addr;
    void *table = ferry_cxx_layout_table(name);
    if (table)
        return table;
    /* __cxa_atexit and the like are the C library's, under the same names;
     * __cxa_thread_atexit is Ferry's, with the thread-local variables (tlv.c) */
    if (!strcmp(name, "__cxa_atexit") || !strcmp(name, "__cxa_finalize") || !strcmp(name, "__cxa_thread_atexit"))
        return NULL;
    return ferry_cxx_symbol(name);
}
