/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libSystem calls that Audacity's official download makes (freemac 1.263,
 * Ferry 0.86.0), each written from its Mac man page or Apple's public Mach
 * and bootstrap documentation.
 *
 * - Exception ports: a task has none, and none can be set. Crash
 *   reporters (Crashpad, which Audacity starts) then don't catch crashes,
 *   which every one of them allows for. Mach ports themselves are in mach.c.
 * - thread_policy_set: accepted; this system's scheduler decides.
 * - audit_token_to_pid: the process id kept in an audit token.
 * - confstr(3) with the Mac's names, including the per-user folders
 *   (_CS_DARWIN_USER_DIR and its temporary and cache folders).
 * - gethostuuid(2), from /etc/machine-id; srandomdev(3); fsctl(2), which
 *   no file system here supports; utime(3); the checked strlcpy and strlcat
 *   that fortified Mac code calls.
 * - ___chkstk_darwin, the stack probe that Xcode's compilers call before a
 *   function makes a large stack frame (Qt, FFmpeg, x264 in OBS's download):
 *   it touches each page from the stack pointer down by the size in %rax,
 *   keeping every register, so the frame never skips the guard page.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>

#include "ferry.h"

typedef uint32_t mac_port_t;
typedef int kern_return_t;

#define KERN_SUCCESS 0
#define KERN_INVALID_ARGUMENT 4
#define KERN_FAILURE 5

/* ---- exception ports: none, and none can be set ---------------------------------------- */

static kern_return_t mac_get_exception_ports(mac_port_t target, unsigned mask, unsigned *masks, unsigned *count,
                                             mac_port_t *ports, int *behaviors, int *flavors)
{
    if (count)
        *count = 0;
    return KERN_SUCCESS;
}

static kern_return_t mac_set_exception_ports(mac_port_t target, unsigned mask, mac_port_t port, int behavior,
                                             int flavor)
{
    return port ? KERN_FAILURE : KERN_SUCCESS;
}

static kern_return_t mac_swap_exception_ports(mac_port_t target, unsigned mask, mac_port_t port, int behavior,
                                              int flavor, unsigned *masks, unsigned *count, mac_port_t *ports,
                                              int *behaviors, int *flavors)
{
    if (count)
        *count = 0;
    return port ? KERN_FAILURE : KERN_SUCCESS;
}

/* ---- threads and processes -------------------------------------------------------------- */

static kern_return_t mac_thread_policy_set(mac_port_t thread, int flavor, int *info, unsigned count)
{
    return KERN_SUCCESS;
}

static kern_return_t mac_thread_policy_get(mac_port_t thread, int flavor, int *info, unsigned *count, int *dflt)
{
    if (dflt)
        *dflt = 1;
    if (info && count)
        memset(info, 0, *count * sizeof *info);
    return KERN_SUCCESS;
}

/* audit_token_t is eight 32-bit words, passed by value; the fifth word is the
 * user id and the sixth the process id (the token's documented layout) */
typedef struct { uint32_t val[8]; } mac_audit_token;

static pid_t mac_audit_token_to_pid(mac_audit_token t) { return (pid_t)t.val[5]; }
static uid_t mac_audit_token_to_euid(mac_audit_token t) { return (uid_t)t.val[1]; }
static uid_t mac_audit_token_to_ruid(mac_audit_token t) { return (uid_t)t.val[3]; }

/* ---- confstr ---------------------------------------------------------------------------- */

#define MAC_CS_PATH 1
#define MAC_CS_DARWIN_USER_DIR 65536
#define MAC_CS_DARWIN_USER_TEMP_DIR 65537
#define MAC_CS_DARWIN_USER_CACHE_DIR 65538

static size_t give(const char *value, char *buf, size_t len)
{
    size_t n = strlen(value) + 1;
    if (buf && len) {
        size_t k = n < len ? n : len;
        memcpy(buf, value, k - 1);
        buf[k - 1] = 0;
    }
    return n;
}

static void with_slash(char *out, size_t size, const char *dir)
{
    size_t n = strlen(dir);
    snprintf(out, size, "%s%s", dir, n && dir[n - 1] == '/' ? "" : "/");
}

static size_t mac_confstr(int name, char *buf, size_t len)
{
    char path[4096];
    const char *home = getenv("HOME");
    switch (name) {
    case MAC_CS_PATH:
        return give("/usr/bin:/bin:/usr/sbin:/sbin", buf, len);
    case MAC_CS_DARWIN_USER_DIR:
    case MAC_CS_DARWIN_USER_TEMP_DIR: {
        const char *tmp = getenv("TMPDIR");
        with_slash(path, sizeof path, tmp && *tmp ? tmp : "/tmp");
        return give(path, buf, len);
    }
    case MAC_CS_DARWIN_USER_CACHE_DIR: {
        const char *xdg = getenv("XDG_CACHE_HOME");
        if (xdg && *xdg)
            with_slash(path, sizeof path, xdg);
        else
            snprintf(path, sizeof path, "%s/.cache/", home && *home ? home : "/tmp");
        return give(path, buf, len);
    }
    default:
        errno = EINVAL;
        return 0;
    }
}

/* ---- host id, random seeds, file system control ------------------------------------------ */

static int mac_gethostuuid(unsigned char id[16], const struct timespec *wait)
{
    char hex[64] = {0};
    int fd = open("/etc/machine-id", O_RDONLY | O_CLOEXEC);
    ssize_t n = fd >= 0 ? read(fd, hex, sizeof hex - 1) : -1;
    if (fd >= 0)
        close(fd);
    if (n >= 32) {
        for (int i = 0; i < 16; i++) {
            unsigned v;
            if (sscanf(hex + 2 * i, "%2x", &v) != 1)
                goto random;
            id[i] = (unsigned char)v;
        }
        return 0;
    }
random:
    /* no machine id: one that stays the same for this boot */
    fd = open("/proc/sys/kernel/random/boot_id", O_RDONLY | O_CLOEXEC);
    n = fd >= 0 ? read(fd, hex, sizeof hex - 1) : -1;
    if (fd >= 0)
        close(fd);
    memset(id, 0, 16);
    for (int i = 0, j = 0; n > 0 && hex[i] && j < 16; i++) {
        unsigned v;
        if (hex[i] == '-' || hex[i] == '\n')
            continue;
        if (sscanf(hex + i, "%2x", &v) != 1)
            break;
        id[j++] = (unsigned char)v;
        i++;
    }
    return 0;
}

static void mac_srandomdev(void)
{
    unsigned seed;
    if (getrandom(&seed, sizeof seed, 0) != sizeof seed)
        seed = (unsigned)time(NULL) ^ (unsigned)getpid();
    srandom(seed);
}

static int mac_fsctl(const char *path, unsigned long request, void *data, unsigned options)
{
    errno = ENOTSUP;
    return -1;
}

static int mac_ffsctl(int fd, unsigned long request, void *data, unsigned options)
{
    errno = ENOTSUP;
    return -1;
}

/* struct utimbuf is two time_t on both systems */
static int mac_utime(const char *path, const struct utimbuf *times) { return utime(path, times); }

/* ---- checked string copies ---------------------------------------------------------------- */

static size_t copy_bounded(char *dst, const char *src, size_t size)
{
    size_t n = strlen(src);
    if (size) {
        size_t k = n < size - 1 ? n : size - 1;
        memcpy(dst, src, k);
        dst[k] = 0;
    }
    return n;
}

static void overflow(const char *what)
{
    fprintf(stderr, "ferry: the program's %s would write past its buffer\n", what);
    abort();
}

static size_t mac___strlcpy_chk(char *dst, const char *src, size_t size, size_t dstlen)
{
    if (size > dstlen)
        overflow("strlcpy");
    return copy_bounded(dst, src, size);
}

static size_t mac___strlcat_chk(char *dst, const char *src, size_t size, size_t dstlen)
{
    if (size > dstlen)
        overflow("strlcat");
    size_t have = strnlen(dst, size);
    if (have == size)
        return size + strlen(src);
    return have + copy_bounded(dst + have, src, size - have);
}

void mac_chkstk_darwin(void);
__asm__(".text\n"
        "mac_chkstk_darwin:\n"
        "    pushq %rcx\n"
        "    pushq %rax\n"
        "    leaq 24(%rsp), %rcx\n"      /* the caller's stack pointer */
        "1:  cmpq $0x1000, %rax\n"
        "    jb 2f\n"
        "    subq $0x1000, %rcx\n"
        "    orq $0, (%rcx)\n"
        "    subq $0x1000, %rax\n"
        "    jmp 1b\n"
        "2:  subq %rax, %rcx\n"
        "    orq $0, (%rcx)\n"
        "    popq %rax\n"
        "    popq %rcx\n"
        "    ret\n");

const struct ferry_symbol ferry_libc_audacity_symbols[] = {
    {"___chkstk_darwin", mac_chkstk_darwin},
    {"task_get_exception_ports", mac_get_exception_ports},
    {"thread_get_exception_ports", mac_get_exception_ports},
    {"host_get_exception_ports", mac_get_exception_ports},
    {"task_set_exception_ports", mac_set_exception_ports},
    {"thread_set_exception_ports", mac_set_exception_ports},
    {"host_set_exception_ports", mac_set_exception_ports},
    {"task_swap_exception_ports", mac_swap_exception_ports},
    {"thread_swap_exception_ports", mac_swap_exception_ports},
    {"host_swap_exception_ports", mac_swap_exception_ports},
    {"thread_policy_set", mac_thread_policy_set},
    {"thread_policy_get", mac_thread_policy_get},
    {"audit_token_to_pid", mac_audit_token_to_pid},
    {"audit_token_to_euid", mac_audit_token_to_euid},
    {"audit_token_to_ruid", mac_audit_token_to_ruid},
    {"confstr", mac_confstr},
    {"gethostuuid", mac_gethostuuid},
    {"srandomdev", mac_srandomdev},
    {"fsctl", mac_fsctl},
    {"ffsctl", mac_ffsctl},
    {"utime", mac_utime},
    {"tmpnam", tmpnam},
    {"__strlcpy_chk", mac___strlcpy_chk},
    {"__strlcat_chk", mac___strlcat_chk},
    {NULL, NULL},
};
