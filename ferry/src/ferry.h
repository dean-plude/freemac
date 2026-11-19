/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef FERRY_H
#define FERRY_H

#include <stddef.h>

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
void ferry_seal_stubs(void);
void ferry_program_started(const char *path, int argc, char **argv);

/* Symbol tables provided by each shim file, each ending with {NULL, NULL}. */
extern const struct ferry_symbol ferry_core_symbols[];
extern const struct ferry_symbol ferry_stdio_symbols[];
extern const struct ferry_symbol ferry_posix_symbols[];
extern const char *const ferry_passthrough[];

/* errno.c */
int ferry_errno_to_mac(int linux_errno);
int ferry_errno_to_linux(int mac_errno);
void ferry_sync_errno(void);

/* posix.c */
int ferry_signal_to_linux(int mac_signal);
int ferry_signal_to_mac(int linux_signal);

#endif
