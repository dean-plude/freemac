/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Finding what a Mac program imports.
 *
 *   1. Ferry's own versions (the tables in errno.c, stdio.c, posix.c and here),
 *      for calls whose numbers or data layouts differ between macOS and Linux.
 *   2. A list of C library calls that behave the same on both systems; those
 *      come straight from this system's C library.
 *   3. For Ferry's own drawing frameworks only, the Cairo, Pango and HarfBuzz
 *      calls listed in graphics/host.h (see host.c).
 *   4. Anything else becomes a stub that stops the program with a clear
 *      message if it is ever called. Ferry never guesses.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <malloc.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"
#include "cxx.h"

/* ---- libraries ---------------------------------------------------------------- */

int ferry_library_supported(const char *name)
{
    /* libSystem is macOS's C library; its pieces live under /usr/lib/system. */
    return !strcmp(name, "/usr/lib/libSystem.B.dylib")
        || !strncmp(name, "/usr/lib/system/", 16)
        || !strcmp(name, "/usr/lib/libobjc.A.dylib")
        || !strcmp(name, FERRY_HOST_LIBRARY)
        || ferry_twin_library(name)
        || ferry_cxx_library(name);
}

/* ---- the program's own details ------------------------------------------------- */

static int program_argc;
static char **program_argv;
static char program_path[4096];
extern char **environ;

void ferry_program_started(const char *path, int argc, char **argv)
{
    program_argc = argc;
    program_argv = argv;
    if (!realpath(path, program_path))
        snprintf(program_path, sizeof program_path, "%s", path);
}

static char ***mac_NSGetEnviron(void) { return &environ; }
static int *mac_NSGetArgc(void) { return &program_argc; }
static char ***mac_NSGetArgv(void) { return &program_argv; }
static char **mac_NSGetProgname(void) { return &program_argv[0]; }

static int mac_NSGetExecutablePath(char *buf, uint32_t *size)
{
    size_t need = strlen(program_path) + 1;
    if (need > *size) {
        *size = need;
        return -1;
    }
    memcpy(buf, program_path, need);
    return 0;
}

static const char *mac_getprogname(void)
{
    const char *slash = program_argv && program_argv[0] ? strrchr(program_argv[0], '/') : NULL;
    return slash ? slash + 1 : program_argv && program_argv[0] ? program_argv[0] : "";
}

/* ---- safety checks the compiler adds ---------------------------------------- */

static uintptr_t stack_guard;

__attribute__((constructor)) static void make_guard(void)
{
    if (getrandom(&stack_guard, sizeof stack_guard, 0) != sizeof stack_guard)
        stack_guard = (uintptr_t)&stack_guard ^ (uintptr_t)time(NULL) ^ 0x5f3759df;
    stack_guard &= ~(uintptr_t)0xff; /* a zero byte stops string overruns */
}

static void mac_stack_chk_fail(void)
{
    fputs("ferry: the program overran a buffer on its stack and was stopped\n", stderr);
    abort();
}

static void mac_assert_rtn(const char *func, const char *file, int line, const char *expr)
{
    fflush(stdout);
    if (func)
        fprintf(stderr, "Assertion failed: (%s), function %s, file %s, line %d.\n", expr, func, file, line);
    else
        fprintf(stderr, "Assertion failed: (%s), file %s, line %d.\n", expr, file, line);
    abort();
}

/* ---- timing --------------------------------------------------------------------- */

struct mac_timebase { uint32_t numer, denom; };

static uint64_t mac_absolute_time(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static int mac_timebase_info(struct mac_timebase *info)
{
    info->numer = 1;
    info->denom = 1; /* mach_absolute_time counts nanoseconds here */
    return 0;
}

/* clang turns sin(x) and cos(x) of the same x into one call on a Mac; both
 * systems return the pair of results in xmm0 and xmm1. */
struct mac_sincos { double s, c; };
struct mac_sincosf { float s, c; };
static struct mac_sincos mac_sincos_stret(double x) { return (struct mac_sincos){sin(x), cos(x)}; }
static struct mac_sincosf mac_sincosf_stret(float x) { return (struct mac_sincosf){sinf(x), cosf(x)}; }

static size_t mac_malloc_size(const void *p) { return p ? malloc_usable_size((void *)p) : 0; }

/* ---- character classes ----------------------------------------------------------
 * Mac headers test ASCII characters against a table in _DefaultRuneLocale and
 * call __maskrune for the rest. The bit values are the BSD _CTYPE_ ones. */

#define CT_A 0x00000100u /* alpha */
#define CT_C 0x00000200u /* control */
#define CT_D 0x00000400u /* digit */
#define CT_G 0x00000800u /* graph */
#define CT_L 0x00001000u /* lower */
#define CT_P 0x00002000u /* punct */
#define CT_S 0x00004000u /* space */
#define CT_U 0x00008000u /* upper */
#define CT_X 0x00010000u /* hex digit */
#define CT_B 0x00020000u /* blank */
#define CT_R 0x00040000u /* print */

struct mac_rune_locale {
    char magic[8];
    char encoding[32];
    void *sgetrune, *sputrune;
    int32_t invalid_rune;
    uint32_t runetype[256];
    int32_t maplower[256];
    int32_t mapupper[256];
    uint8_t rest[256]; /* range tables and variable data we leave empty */
};
_Static_assert(__builtin_offsetof(struct mac_rune_locale, runetype) == 60, "runetype offset");

static struct mac_rune_locale default_rune = {.magic = "RuneMagA", .encoding = "NONE", .invalid_rune = 0xfffd};

static uint32_t classify(int c)
{
    uint32_t t = 0;
    if (c < 0 || c > 127)
        return 0;
    if (c < 32 || c == 127)
        t |= CT_C;
    if (c == ' ' || c == '\t')
        t |= CT_B;
    if (c == ' ' || (c >= '\t' && c <= '\r'))
        t |= CT_S;
    if (c >= 32 && c < 127)
        t |= CT_R;
    if (c > 32 && c < 127)
        t |= CT_G;
    if (c >= '0' && c <= '9')
        t |= CT_D | CT_X | (uint32_t)(c - '0');
    if (c >= 'a' && c <= 'z')
        t |= CT_A | CT_L;
    if (c >= 'A' && c <= 'Z')
        t |= CT_A | CT_U;
    if ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))
        t |= CT_X;
    if ((t & CT_G) && !(t & (CT_A | CT_D)))
        t |= CT_P;
    return t;
}

__attribute__((constructor)) static void make_runes(void)
{
    for (int c = 0; c < 256; c++) {
        default_rune.runetype[c] = classify(c);
        default_rune.maplower[c] = (c >= 'A' && c <= 'Z') ? c + 32 : c;
        default_rune.mapupper[c] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
}

static struct mac_rune_locale *current_rune = &default_rune;

static uint32_t mac_maskrune(int32_t c, unsigned long mask)
{
    return (c >= 0 && c < 256 ? default_rune.runetype[c] : 0) & mask;
}
static int32_t mac_tolower(int32_t c) { return c >= 0 && c < 256 ? default_rune.maplower[c] : c; }
static int32_t mac_toupper(int32_t c) { return c >= 0 && c < 256 ? default_rune.mapupper[c] : c; }

/* ---- tables ------------------------------------------------------------------- */

void ferry_unwind_resume(void *exception); /* objc/unwind.S */

int *mac_error(void);
char *mac_strerror(int);
int mac_strerror_r(int, char *, size_t);
void mac_perror(const char *);

const struct ferry_symbol ferry_core_symbols[] = {
    {"__error", mac_error},
    {"strerror", mac_strerror},
    {"strerror_r", mac_strerror_r},
    {"perror", mac_perror},
    {"_NSGetEnviron", mac_NSGetEnviron},
    {"_NSGetArgc", mac_NSGetArgc},
    {"_NSGetArgv", mac_NSGetArgv},
    {"_NSGetProgname", mac_NSGetProgname},
    {"_NSGetExecutablePath", mac_NSGetExecutablePath},
    {"getprogname", mac_getprogname},
    {"__stack_chk_guard", &stack_guard},
    {"__stack_chk_fail", mac_stack_chk_fail},
    {"__assert_rtn", mac_assert_rtn},
    {"mach_absolute_time", mac_absolute_time},
    {"mach_continuous_time", mac_absolute_time},
    {"mach_timebase_info", mac_timebase_info},
    {"malloc_size", mac_malloc_size},
    {"_DefaultRuneLocale", &default_rune},
    {"_CurrentRuneLocale", &current_rune},
    {"__maskrune", mac_maskrune},
    {"__tolower", mac_tolower},
    {"__toupper", mac_toupper},
    {"_Unwind_Resume", ferry_unwind_resume},
    /* clang lowers memset(p, 0, n) to this name on a Mac */
    {"__bzero", bzero},
    /* not a symbol of this system's C library (it wraps __cxa_atexit) */
    {"atexit", atexit},
    {"__sincos_stret", mac_sincos_stret},
    {"__sincosf_stret", mac_sincosf_stret},
    /* Ferry's Foundation reaches ICU and libxml2 through this (src/host.c) */
    {"ferry_twin_symbol", ferry_twin_symbol},
    /* Ferry's own: this system's libcurl, for Foundation (host.c) */
    {"ferry_network_symbol", ferry_network_symbol},
    /* Ferry's own: this system's OpenSSL, for the Security framework (host.c) */
    {"ferry_crypto_symbol", ferry_crypto_symbol},
    {"ferry_server_certificates", ferry_server_certificates},
    /* Ferry's own: the macOS version it presents, for Foundation (sysversion.c) */
    {"ferry_macos_version", ferry_macos_version},
    /* Ferry's own: this system's GIO, for distributed notifications (host.c) */
    {"ferry_bus_symbol", ferry_bus_symbol},
    {NULL, NULL},
};

static const struct ferry_symbol *const tables[] = {
    ferry_core_symbols, ferry_stdio_symbols, ferry_posix_symbols, ferry_pthread_symbols, ferry_blocks_symbols,
    ferry_dispatch_symbols, ferry_objc_symbols, ferry_commoncrypto_symbols, ferry_sysversion_symbols,
    ferry_sysctl_symbols, ferry_attrlist_symbols, ferry_dyld_symbols, ferry_wchar_symbols,
    ferry_tlv_symbols, ferry_socket_symbols, ferry_kqueue_symbols,
};

static void *find_own(const char *name)
{
    for (size_t t = 0; t < sizeof tables / sizeof tables[0]; t++)
        for (const struct ferry_symbol *s = tables[t]; s->name; s++)
            if (!strcmp(s->name, name))
                return s->addr;
    return NULL;
}

static void *find_passthrough(const char *name)
{
    for (const char *const *p = ferry_passthrough; *p; p++)
        if (!strcmp(*p, name))
            return dlsym(RTLD_DEFAULT, name);
    return NULL;
}

void *ferry_lookup(const char *name)
{
    /* C++ names, once a program has brought in libc++ (cxx.c): ahead of
     * libobjc's own personality routine for C++ */
    void *addr = ferry_cxx_active ? ferry_cxx_lookup(name) : NULL;
    if (addr)
        return addr;
    addr = find_own(name);
    if (addr)
        return addr;
    /* Variant suffixes such as "$UNIX2003" or "$INODE64": Ferry lists the
     * variants whose data layout matters by their full name, so for the rest
     * the plain call is the right one. */
    char base[256];
    snprintf(base, sizeof base, "%s", name);
    char *dollar = strchr(base, '$');
    if (dollar) {
        *dollar = 0;
        if ((addr = find_own(base)))
            return addr;
    }
    if ((addr = find_passthrough(base)))
        return addr;
    if ((addr = ferry_host_lookup(base)))
        return addr;
    return ferry_twin_lookup(base);
}

/* For dlsym: what a Mac's libSystem and libobjc would answer, and the Linux
 * twins a program linked (host.c). Not the drawing libraries Ferry's own
 * frameworks reach through libFerryHost, which no Mac has. */
void *ferry_lookup_libsystem(const char *name)
{
    void *addr = find_own(name);
    if (addr)
        return addr;
    char base[256];
    snprintf(base, sizeof base, "%s", name);
    char *dollar = strchr(base, '$');
    if (dollar) {
        *dollar = 0;
        if ((addr = find_own(base)))
            return addr;
    }
    if ((addr = find_passthrough(base)))
        return addr;
    return ferry_twin_lookup(base);
}

/* For dladdr: the name under which Ferry's tables serve an address. */
const char *ferry_symbol_name(const void *addr)
{
    if (!addr)
        return NULL;
    for (size_t t = 0; t < sizeof tables / sizeof tables[0]; t++)
        for (const struct ferry_symbol *s = tables[t]; s->name; s++)
            if (s->addr == addr)
                return s->name;
    /* the calls passed through to this system's C library, some of which
     * (strlen, memcpy...) the C library picks a version of at run time */
    for (const char *const *p = ferry_passthrough; *p; p++)
        if (dlsym(RTLD_DEFAULT, *p) == addr)
            return *p;
    return NULL;
}

const char *ferry_program_path(void) { return program_path; }

void ferry_program_args(int *argc, char ***argv)
{
    *argc = program_argc;
    *argv = program_argv;
}

/* ---- stubs for what Ferry doesn't have ---------------------------------------- */

#define STUB_SIZE 22
#define STUB_PAGES 16

/* Stubs are written into an area that is sealed (made executable, no longer
 * writable) once the program is loaded. A library loaded later with dlopen
 * gets a fresh area for its own, sealed in turn: code may be running in the
 * old one. */
static uint8_t *stub_area;
static size_t stub_used;
static int stub_sealed;

static void unsupported(const char *raw_name)
{
    fflush(stdout);
    const char *name = raw_name[0] == '_' ? raw_name + 1 : raw_name;
    if (!strcmp(name, "dyld_stub_binder"))
        fprintf(stderr, "ferry: the program tried to bind a symbol lazily, which Ferry does ahead of time\n");
    else
        fprintf(stderr, "ferry: this program uses %s, which Ferry doesn't support yet\n", name);
    _exit(127);
}

void *ferry_missing_stub(const char *raw_name)
{
    if (!stub_area || stub_sealed) {
        stub_area = mmap(NULL, STUB_PAGES * 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (stub_area == MAP_FAILED) {
            perror("ferry: mmap");
            exit(126);
        }
        stub_used = 0;
        stub_sealed = 0;
    }
    if (stub_used + STUB_SIZE > STUB_PAGES * 4096) {
        fputs("ferry: the program imports too many unsupported calls\n", stderr);
        exit(126);
    }
    char *saved = strdup(raw_name);
    uint8_t *p = stub_area + stub_used;
    stub_used += STUB_SIZE;
    uint64_t arg = (uint64_t)saved, fn = (uint64_t)unsupported;
    p[0] = 0x48; p[1] = 0xbf; memcpy(p + 2, &arg, 8);   /* mov rdi, name */
    p[10] = 0x48; p[11] = 0xb8; memcpy(p + 12, &fn, 8); /* mov rax, unsupported */
    p[20] = 0xff; p[21] = 0xe0;                         /* jmp rax */
    return p;
}

void ferry_seal_stubs(void)
{
    if (!stub_area || stub_sealed)
        return;
    if (mprotect(stub_area, STUB_PAGES * 4096, PROT_READ | PROT_EXEC) < 0) {
        perror("ferry: mprotect");
        exit(126);
    }
    stub_sealed = 1;
}
