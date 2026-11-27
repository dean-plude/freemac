/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libSystem calls that Audacity's official download makes (freemac 1.263,
 * Ferry 0.86.0), each written from its Mac man page or Apple's public Mach
 * and bootstrap documentation.
 *
 * - Mach ports and exception ports, and the bootstrap server. Crash
 *   reporters (Crashpad, which Audacity starts) make a receive right, check
 *   it in with launchd and catch the task's exceptions there. Ferry has no
 *   Mach IPC, so making a port fails as a Mac's does when it runs out
 *   (KERN_RESOURCE_SHORTAGE), the bootstrap server knows no service, and a
 *   task has no exception ports. A crash reporter then simply doesn't start,
 *   which every one of them allows for.
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
#define KERN_RESOURCE_SHORTAGE 6
#define KERN_INVALID_NAME 15
#define MACH_SEND_INVALID_DEST 0x10000003
#define MACH_RCV_INVALID_NAME 0x10004002
#define MACH_SEND_MSG 0x00000001
#define BOOTSTRAP_NOT_PRIVILEGED 1100
#define BOOTSTRAP_UNKNOWN_SERVICE 1102

/* ---- Mach ports --------------------------------------------------------------------- */

static mac_port_t mac_bootstrap_port = 0; /* MACH_PORT_NULL: there is no launchd to talk to */

static kern_return_t mac_mach_port_allocate(mac_port_t task, int right, mac_port_t *name)
{
    if (name)
        *name = 0;
    return KERN_RESOURCE_SHORTAGE;
}

static kern_return_t mac_mach_port_mod_refs(mac_port_t task, mac_port_t name, int right, int delta)
{
    return name ? KERN_INVALID_NAME : KERN_SUCCESS;
}

static kern_return_t mac_mach_port_insert_member(mac_port_t task, mac_port_t name, mac_port_t set)
{
    return KERN_INVALID_NAME;
}

static kern_return_t mac_mach_port_extract_right(mac_port_t task, mac_port_t name, unsigned type, mac_port_t *out,
                                                 unsigned *out_type)
{
    if (out)
        *out = 0;
    return KERN_INVALID_NAME;
}

static kern_return_t mac_mach_port_request_notification(mac_port_t task, mac_port_t name, int id, unsigned sync,
                                                        mac_port_t notify, unsigned type, mac_port_t *previous)
{
    if (previous)
        *previous = 0;
    return KERN_INVALID_NAME;
}

static kern_return_t mac_mach_port_insert_right(mac_port_t task, mac_port_t name, mac_port_t poly, unsigned type)
{
    return KERN_INVALID_NAME;
}

static kern_return_t mac_mach_port_destroy(mac_port_t task, mac_port_t name) { return name ? KERN_INVALID_NAME : KERN_SUCCESS; }

static kern_return_t mac_mach_msg(void *msg, int option, unsigned send_size, unsigned rcv_size, mac_port_t rcv_name,
                                  unsigned timeout, mac_port_t notify)
{
    return option & MACH_SEND_MSG ? MACH_SEND_INVALID_DEST : MACH_RCV_INVALID_NAME;
}

static void mac_mach_msg_destroy(void *msg) {}

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

/* ---- the bootstrap server ------------------------------------------------------------- */

static kern_return_t mac_bootstrap_look_up(mac_port_t bp, const char *name, mac_port_t *sp)
{
    if (sp)
        *sp = 0;
    return BOOTSTRAP_UNKNOWN_SERVICE;
}

static kern_return_t mac_bootstrap_check_in(mac_port_t bp, const char *name, mac_port_t *sp)
{
    if (sp)
        *sp = 0;
    return BOOTSTRAP_UNKNOWN_SERVICE;
}

static kern_return_t mac_bootstrap_register(mac_port_t bp, const char *name, mac_port_t sp)
{
    return BOOTSTRAP_NOT_PRIVILEGED;
}

static const char *mac_bootstrap_strerror(kern_return_t r)
{
    switch (r) {
    case KERN_SUCCESS: return "Success";
    case BOOTSTRAP_NOT_PRIVILEGED: return "Permission denied";
    case 1101: return "Service name already exists";
    case BOOTSTRAP_UNKNOWN_SERVICE: return "Unknown service name";
    case 1103: return "Service is already active";
    case 1104: return "Bad request";
    case 1105: return "No memory";
    default: return "Unknown error";
    }
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
    {"bootstrap_port", &mac_bootstrap_port},
    {"mach_port_allocate", mac_mach_port_allocate},
    {"mach_port_mod_refs", mac_mach_port_mod_refs},
    {"mach_port_insert_member", mac_mach_port_insert_member},
    {"mach_port_extract_right", mac_mach_port_extract_right},
    {"mach_port_request_notification", mac_mach_port_request_notification},
    {"mach_port_insert_right", mac_mach_port_insert_right},
    {"mach_port_destroy", mac_mach_port_destroy},
    {"mach_msg", mac_mach_msg},
    {"mach_msg_destroy", mac_mach_msg_destroy},
    {"task_get_exception_ports", mac_get_exception_ports},
    {"thread_get_exception_ports", mac_get_exception_ports},
    {"host_get_exception_ports", mac_get_exception_ports},
    {"task_set_exception_ports", mac_set_exception_ports},
    {"thread_set_exception_ports", mac_set_exception_ports},
    {"host_set_exception_ports", mac_set_exception_ports},
    {"task_swap_exception_ports", mac_swap_exception_ports},
    {"thread_swap_exception_ports", mac_swap_exception_ports},
    {"host_swap_exception_ports", mac_swap_exception_ports},
    {"bootstrap_look_up", mac_bootstrap_look_up},
    {"bootstrap_check_in", mac_bootstrap_check_in},
    {"bootstrap_register", mac_bootstrap_register},
    {"bootstrap_strerror", mac_bootstrap_strerror},
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
