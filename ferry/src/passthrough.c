/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * C library calls that take the same arguments, use the same numbers and
 * lay out their data the same way on macOS and Linux (both follow the
 * System V AMD64 calling convention), so a Mac program can use this
 * system's own. Anything not here and not in Ferry's own tables stops the
 * program with a message instead of risking a silent mismatch.
 */
#include <stddef.h>

const char *const ferry_passthrough[] = {
    /* memory */
    "malloc", "calloc", "realloc", "reallocf", "free", "posix_memalign", "aligned_alloc",
    "valloc", "memalign",
    /* strings */
    "memcpy", "memmove", "memset", "memcmp", "memchr", "memrchr", "memccpy", "memmem",
    "bzero", "bcopy", "bcmp", "explicit_bzero", "strlen", "strnlen", "strcpy", "strncpy",
    "stpcpy", "stpncpy", "strcat", "strncat", "strcmp", "strncmp", "strcoll", "strxfrm",
    "strchr", "strrchr", "strstr", "strcasestr", "strdup", "strndup", "strspn", "strcspn",
    "strpbrk", "strtok", "strtok_r", "strsep", "strcasecmp", "strncasecmp", "strlcpy",
    "strlcat", "index", "rindex", "ffs", "ffsl", "ffsll",
    "__memcpy_chk", "__memmove_chk", "__memset_chk", "__strcpy_chk", "__strncpy_chk",
    "__strcat_chk", "__strncat_chk", "__stpcpy_chk", "__sprintf_chk", "__snprintf_chk",
    "__vsprintf_chk", "__vsnprintf_chk",
    /* numbers and conversions */
    "atoi", "atol", "atoll", "atof", "strtol", "strtoul", "strtoll", "strtoull", "strtoimax",
    "strtoumax", "strtod", "strtof", "strtold", "abs", "labs", "llabs", "div", "ldiv", "lldiv",
    "rand", "srand", "rand_r", "random", "srandom", "drand48", "erand48", "lrand48", "mrand48",
    "srand48", "arc4random", "arc4random_buf", "arc4random_uniform", "getentropy",
    "qsort", "qsort_r", "bsearch", "lsearch", "lfind",
    /* formatted text that doesn't involve a FILE */
    "printf", "vprintf", "sprintf", "vsprintf", "snprintf", "vsnprintf", "asprintf",
    "vasprintf", "dprintf", "vdprintf", "sscanf", "vsscanf", "scanf", "vscanf",
    "puts", "putchar", "getchar", "putchar_unlocked", "getchar_unlocked", "remove", "rename",
    /* character classes as functions */
    "isalnum", "isalpha", "isblank", "iscntrl", "isdigit", "isgraph", "islower", "isprint",
    "ispunct", "isspace", "isupper", "isxdigit", "isascii", "tolower", "toupper", "toascii",
    "digittoint",
    /* environment and process */
    "getenv", "setenv", "unsetenv", "putenv", "exit", "_exit", "_Exit", "abort", "atexit",
    "system", "getpid", "getppid", "getuid", "geteuid", "getgid", "getegid", "setuid",
    "setgid", "seteuid", "setegid", "getpgrp", "setpgid", "setsid", "getsid", "getlogin",
    "fork", "execv", "execvp", "execve", "execl", "execlp", "alarm", "pause", "sleep",
    "usleep", "nanosleep", "getgroups", "umask", "nice",
    /* files */
    "read", "write", "pread", "pwrite", "readv", "writev", "close", "lseek", "dup", "dup2",
    "pipe", "fsync", "fdatasync", "ftruncate", "truncate", "unlink", "rmdir", "mkdir",
    "chdir", "fchdir", "getcwd", "chmod", "fchmod", "chown", "lchown",
    "link", "symlink", "readlink", "isatty", "ttyname", "mkstemp", "mkstemps", "mkdtemp",
    "mktemp", "utimes", "futimes", "select", "poll", "gethostname", "getpagesize",
    "getdtablesize", "flock",
    /* folders' changes, for FSEvents (foundation/FSEvents.m) */
    "inotify_init1", "inotify_add_watch", "inotify_rm_watch",
    /* memory maps (mmap itself is converted) */
    "munmap", "mprotect", "msync", "madvise", "mlock", "munlock",
    /* time */
    "time", "difftime", "mktime", "timegm", "localtime", "localtime_r", "gmtime", "gmtime_r",
    "asctime", "asctime_r", "ctime", "ctime_r", "strftime", "strptime", "gettimeofday",
    "clock", "tzset", "getrusage",
    /* maths */
    "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh", "asinh",
    "acosh", "atanh", "exp", "exp2", "expm1", "log", "log2", "log10", "log1p", "pow", "sqrt",
    "cbrt", "hypot", "floor", "ceil", "round", "trunc", "rint", "nearbyint", "lround",
    "llround", "lrint", "fabs", "fmod", "remainder", "fmin", "fmax", "fdim", "fma", "frexp",
    "ldexp", "modf", "scalbn", "copysign", "nextafter", "erf", "erfc", "tgamma", "lgamma",
    "sinf", "cosf", "tanf", "atanf", "atan2f", "expf", "logf", "log2f", "log10f", "powf",
    "sqrtf", "floorf", "ceilf", "roundf", "truncf", "fabsf", "fmodf", "fminf", "fmaxf",
    "hypotf",
    /* long double maths: the same 80-bit format on both systems (freemac 1.221, Ferry 0.45.0) */
    "sqrtl", "fabsl", "floorl", "ceill", "fmodl", "powl", "roundl", "truncl", "fminl", "fmaxl", "ldexpl",
    "frexpl", "expl", "exp2l", "logl", "log10l", "log2l", "sinl", "cosl", "tanl", "atan2l", "modfl", "copysignl",
    "imaxabs", "imaxdiv",
    /* getopt's variables (getopt itself is converted) */
    "optarg", "optind", "opterr", "optopt",
    NULL,
};
