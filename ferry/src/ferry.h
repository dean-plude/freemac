/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef FERRY_H
#define FERRY_H

#include <stddef.h>
#include <stdint.h>

/* One function or variable a Mac program can import. Names are written the
 * way C code spells them, without the leading underscore Mach-O adds. */
struct ferry_symbol {
    const char *name;
    void *addr;
};

extern int ferry_verbose;

/* loader.c */
int ferry_run(const char *path, int argc, char **argv, char **envp);

/* lookup.c */
int ferry_library_supported(const char *install_name);
void *ferry_lookup(const char *name);
void *ferry_missing_stub(const char *raw_name);

/* Where a loaded image's unwind tables are, for the exception unwinder. */
struct ferry_unwind_sections {
    const char *path;
    uint64_t base;                  /* the image's Mach-O header */
    const uint8_t *unwind_info, *eh_frame;
    size_t unwind_size, eh_size;
};
int ferry_find_unwind(uint64_t pc, struct ferry_unwind_sections *out);
extern const struct ferry_ehtype { const void *vtable; const char *name; void *cls; } ferry_ehtype_missing;
void ferry_seal_stubs(void);
void ferry_program_started(const char *path, int argc, char **argv);

/* Symbol tables provided by each shim file, each ending with {NULL, NULL}. */
extern const struct ferry_symbol ferry_core_symbols[];
extern const struct ferry_symbol ferry_stdio_symbols[];
extern const struct ferry_symbol ferry_posix_symbols[];
extern const char *const ferry_passthrough[];
extern const struct ferry_symbol ferry_blocks_symbols[];   /* libSystem's blocks */
extern const struct ferry_symbol ferry_dispatch_symbols[]; /* libSystem's libdispatch */
extern const struct ferry_symbol ferry_objc_symbols[];     /* libobjc.A.dylib */

/* host.c: this system's drawing libraries, for Ferry's own frameworks */
#define FERRY_HOST_LIBRARY "/usr/lib/ferry/libFerryHost.dylib"
extern const char *const ferry_host_names[];
void *ferry_host_lookup(const char *name);

/* errno.c */
int ferry_errno_to_mac(int linux_errno);
int ferry_errno_to_linux(int mac_errno);
void ferry_sync_errno(void);

/* posix.c */
int ferry_signal_to_linux(int mac_signal);
int ferry_signal_to_mac(int linux_signal);

#endif
