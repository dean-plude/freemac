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
void *ferry_lookup_libsystem(const char *name); /* Ferry's own and the passthrough calls, for dlsym */
const char *ferry_symbol_name(const void *addr); /* the name a table gives an address, for dladdr */
void *ferry_missing_stub(const char *raw_name);
const char *ferry_program_path(void);           /* the Mac program's real path */
void ferry_program_args(int *argc, char ***argv);

/* loader.c: the Mach-O images loaded, for dlopen, dlsym, dladdr and the
 * _dyld_ calls (dyld.c). Images are never unloaded. */
struct image;
int ferry_image_count(void);
struct image *ferry_image_at(int index);
struct image *ferry_main_image(void);
struct image *ferry_image_containing(const void *addr);
const char *ferry_image_path(struct image *im);
void *ferry_image_header(struct image *im);
intptr_t ferry_image_slide(struct image *im);
int ferry_image_is_bundle(struct image *im);
void *ferry_image_symbol(struct image *im, const char *macho_name); /* what it exports */
int ferry_image_dependencies(struct image *im, struct image **out, int max, int *builtin);
const char *ferry_image_nearest(struct image *im, const void *addr, void **symbol_addr);
void *ferry_image_first_class(struct image *im); /* its first Objective-C class Ferry kept */
/* Loads a library or bundle while the program runs (path already expanded
 * by ferry_image_resolve); NULL with the reason in err if it can't be. */
struct image *ferry_image_load(const char *path, char *err, size_t errsize);
int ferry_image_resolve(struct image *caller, const char *name, char *out, size_t size);
int ferry_find_system_framework(const char *install_name, char *out, size_t size);

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
extern const struct ferry_symbol ferry_pthread_symbols[];  /* libSystem's pthreads and locks */
int ferry_pthread_live_threads(void);   /* threads the program started, still running */
int ferry_pthread_is_main(void);
extern const char *const ferry_passthrough[];
extern const struct ferry_symbol ferry_blocks_symbols[];   /* libSystem's blocks */
extern const struct ferry_symbol ferry_dispatch_symbols[]; /* libSystem's libdispatch */
extern const struct ferry_symbol ferry_objc_symbols[];     /* libobjc.A.dylib */

/* host.c: this system's drawing libraries, for Ferry's own frameworks */
#define FERRY_HOST_LIBRARY "/usr/lib/ferry/libFerryHost.dylib"
extern const char *const ferry_host_names[];
void *ferry_host_lookup(const char *name);
int ferry_twin_library(const char *install_name);   /* zlib and the like: this system's copy */
void *ferry_twin_lookup(const char *name);
void *ferry_twin_symbol(const char *install_name, const char *name); /* lazily, for Foundation */
void *ferry_network_symbol(const char *name);       /* libcurl, for Foundation's URL loading */
void *ferry_crypto_symbol(const char *name);        /* OpenSSL, for CommonCrypto and Security */

/* servercerts.c: the certificates an https server presents, for Security */
int ferry_server_certificates(const char *host, int port, int timeout_ms,
                              void (*each)(void *ctx, const unsigned char *der, size_t len), void *ctx);

/* commoncrypto.c: libSystem's CommonCrypto */
extern const struct ferry_symbol ferry_commoncrypto_symbols[];

/* sysversion.c: the macOS version Ferry presents, the same in uname, the
 * Mac's version file, NSProcessInfo and Gestalt. Darwin 23 is macOS 14. */
#define FERRY_MACOS_VERSION "14.7"
#define FERRY_MACOS_BUILD "23H124"
#define FERRY_DARWIN_RELEASE "23.6.0"
/* The Intel Mac model Ferry presents (hw.model): a 2018 Mac mini, which
 * macOS 14 supports. */
#define FERRY_MAC_MODEL "Macmini8,1"
struct stat;
const char *ferry_macos_version(const char **build);
const char *ferry_kernel_version(void);   /* uname's version and kern.version */
uint32_t ferry_macos_version_packed(void); /* 14.7.0 as 0x000e0700, as dyld writes versions */
extern const struct ferry_symbol ferry_sysversion_symbols[]; /* the availability checks */

/* sysctl.c: sysctl, the proc_ calls and the Mach host and task figures */
extern const struct ferry_symbol ferry_sysctl_symbols[];
/* attrlist.c: getattrlist */
extern const struct ferry_symbol ferry_attrlist_symbols[];
/* dyld.c: dlopen and the rest of <dlfcn.h>, and the _dyld_ image calls */
extern const struct ferry_symbol ferry_dyld_symbols[];
extern const struct ferry_symbol ferry_wchar_symbols[]; /* wchar.c: wide characters, xlocale, __cxa_atexit */
/* tlv.c: thread-local variables (_tlv_bootstrap, _tlv_atexit) */
extern const struct ferry_symbol ferry_tlv_symbols[];
struct ferry_tlv_section { uint8_t *addr; uint64_t size; uint32_t type, align; };
int ferry_tlv_image_loaded(const char *path, const struct ferry_tlv_section *s, int n); /* -1: too many */
void ferry_tlv_exit(void);   /* the calling thread's thread-local destructors, as exit runs them */
void *ferry_tlv_address(void *descriptor); /* the calling thread's copy of a variable, for dlsym */
int ferry_is_virtual(const char *path);                    /* /System/Library/CoreServices/SystemVersion.plist */
int ferry_virtual_open(const char *path, int linux_flags); /* -1 and errno if it can't be */
int ferry_virtual_stat(const char *path, struct stat *s);  /* 1 if it was one of Ferry's files */

/* errno.c */
int ferry_errno_to_mac(int linux_errno);
int ferry_errno_to_linux(int mac_errno);
void ferry_sync_errno(void);

/* posix.c */
int ferry_signal_to_linux(int mac_signal);
int ferry_signal_to_mac(int linux_signal);

#endif
