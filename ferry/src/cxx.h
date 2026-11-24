/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * C++ programs (src/cxx.c, src/cxx_unwind.c, src/cxx_threads.c): a Mac's
 * libc++ and libc++abi served by this system's LLVM libc++, libc++abi and
 * libunwind, opened only when a program links them.
 */
#ifndef FERRY_CXX_H
#define FERRY_CXX_H

#include <stddef.h>
#include <stdint.h>

#include "ferry.h"

struct image;

/* Set once this system's libc++ is open: from then on exceptions, C++ and
 * Objective-C alike, are unwound by its unwinder. */
extern int ferry_cxx_active;

int ferry_cxx_library(const char *install_name); /* libc++.1.dylib, libc++abi.dylib: opens them */
void *ferry_cxx_lookup(const char *name);       /* a C++ name a program imports, or NULL */
void ferry_cxx_image_loaded(struct image *im);  /* its unwind tables, for the unwinder */
void *ferry_cxx_symbol(const char *name);       /* this system's libc++ (and libc++abi), by name */

/* The unwinder's calls (the Itanium C++ ABI's level 1), from this
 * system's libunwind; valid while ferry_cxx_active. */
struct _Unwind_Context;
struct ferry_cxx_unwinder {
    int (*raise)(void *exception);
    void (*resume)(void *exception);
    void (*delete_exception)(void *exception);
    uintptr_t (*get_lsda)(struct _Unwind_Context *);
    uintptr_t (*get_region_start)(struct _Unwind_Context *);
    uintptr_t (*get_ip)(struct _Unwind_Context *);
    void (*set_ip)(struct _Unwind_Context *, uintptr_t);
    void (*set_gr)(struct _Unwind_Context *, int, uintptr_t);
    void *(*begin_catch)(void *exception);
    void (*end_catch)(void);
    void (*terminate)(void);
    int (*gxx_personality)(int, int, uint64_t, void *, struct _Unwind_Context *);
};
extern struct ferry_cxx_unwinder ferry_cxx_unwind;

/* Unwinding codes and actions, as the Itanium C++ ABI numbers them. */
enum {
    FERRY_URC_FOREIGN_EXCEPTION_CAUGHT = 1, FERRY_URC_FATAL_PHASE1_ERROR = 3, FERRY_URC_END_OF_STACK = 5,
    FERRY_URC_HANDLER_FOUND = 6, FERRY_URC_INSTALL_CONTEXT = 7, FERRY_URC_CONTINUE_UNWIND = 8,
};
enum { FERRY_UA_SEARCH_PHASE = 1, FERRY_UA_CLEANUP_PHASE = 2, FERRY_UA_HANDLER_FRAME = 4, FERRY_UA_FORCE_UNWIND = 8 };

/* cxx_unwind.c: DWARF call frame information for every function of a Mac
 * image (from its compact unwind table and its __eh_frame), handed to
 * the unwinder one FDE at a time. */
int ferry_cxx_describe_image(uint64_t header, void (*add_fde)(const void *fde));

/* cxx_threads.c: the pieces of the C++ library whose data layout holds a
 * Mac pthread type, and the other ABI differences Ferry corrects. */
extern const struct ferry_symbol ferry_cxx_overrides[];
void ferry_cxx_threads_init(void);
void *ferry_cxx_layout_table(const char *name);   /* a virtual table in the Mac's layout, or NULL */

/* objc/exception.c: from now on, Objective-C exceptions through this
 * system's unwinder too */
void ferry_objc_exceptions_to_host(void);

#endif
