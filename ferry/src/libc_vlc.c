/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * What VLC's core (libvlccore) asks of libSystem that Ferry didn't have
 * (freemac 1.232): Mach semaphores, which VLC uses because a Mac has no
 * unnamed POSIX semaphores, written from the Mach reference pages; and a
 * few C library calls whose Mac data or numbers differ from this system's
 * (pathconf, getpwuid_r, sigwait, statvfs, sys_errlist), from the Mac's
 * man pages; and backtrace(3), which follows Mac code's frame pointers.
 * And setjmp and longjmp (freemac 1.238), which FreeType uses.
 *
 * A semaphore is a number standing for a POSIX semaphore of this system;
 * the numbers start well above Ferry's task and host ports.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <iconv.h>
#include <math.h>
#include <pwd.h>
#include <signal.h>
#include <string.h>
#include <sys/statvfs.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "ferry.h"

#define KERN_SUCCESS_ 0
#define KERN_INVALID_ARGUMENT_ 4
#define KERN_RESOURCE_SHORTAGE_ 6
#define KERN_ABORTED_ 14
#define KERN_OPERATION_TIMED_OUT_ 49
#define FIRST_SEMAPHORE 0x5000

static pthread_mutex_t sem_lock = PTHREAD_MUTEX_INITIALIZER;
static sem_t **sems;
static uint32_t sems_count;

static sem_t *sem_for(uint32_t name)
{
    sem_t *s = NULL;
    pthread_mutex_lock(&sem_lock);
    if (name >= FIRST_SEMAPHORE && name - FIRST_SEMAPHORE < sems_count)
        s = sems[name - FIRST_SEMAPHORE];
    pthread_mutex_unlock(&sem_lock);
    return s;
}

static int mac_semaphore_create(uint32_t task, uint32_t *out, int policy, int value)
{
    (void)task;
    (void)policy;
    if (!out || value < 0)
        return KERN_INVALID_ARGUMENT_;
    sem_t *s = malloc(sizeof *s);
    if (!s || sem_init(s, 0, (unsigned)value) != 0) {
        free(s);
        return KERN_RESOURCE_SHORTAGE_;
    }
    pthread_mutex_lock(&sem_lock);
    uint32_t slot = sems_count;
    for (uint32_t i = 0; i < sems_count; i++)
        if (!sems[i]) {
            slot = i;
            break;
        }
    if (slot == sems_count) {
        sem_t **grown = realloc(sems, (sems_count + 16) * sizeof *sems);
        if (!grown) {
            pthread_mutex_unlock(&sem_lock);
            sem_destroy(s);
            free(s);
            return KERN_RESOURCE_SHORTAGE_;
        }
        for (uint32_t i = sems_count; i < sems_count + 16; i++)
            grown[i] = NULL;
        sems = grown;
        sems_count += 16;
    }
    sems[slot] = s;
    pthread_mutex_unlock(&sem_lock);
    *out = FIRST_SEMAPHORE + slot;
    return KERN_SUCCESS_;
}

static int mac_semaphore_destroy(uint32_t task, uint32_t name)
{
    (void)task;
    sem_t *s = NULL;
    pthread_mutex_lock(&sem_lock);
    if (name >= FIRST_SEMAPHORE && name - FIRST_SEMAPHORE < sems_count) {
        s = sems[name - FIRST_SEMAPHORE];
        sems[name - FIRST_SEMAPHORE] = NULL;
    }
    pthread_mutex_unlock(&sem_lock);
    if (!s)
        return KERN_INVALID_ARGUMENT_;
    sem_destroy(s);
    free(s);
    return KERN_SUCCESS_;
}

static int mac_semaphore_signal(uint32_t name)
{
    sem_t *s = sem_for(name);
    if (!s)
        return KERN_INVALID_ARGUMENT_;
    sem_post(s);
    return KERN_SUCCESS_;
}

/* A Mac wakes every thread waiting now; this wakes one. */
static int mac_semaphore_signal_all(uint32_t name)
{
    sem_t *s = sem_for(name);
    if (!s)
        return KERN_INVALID_ARGUMENT_;
    sem_post(s); /* one waiter: POSIX semaphores can't tell how many wait */
    return KERN_SUCCESS_;
}

static int mac_semaphore_wait(uint32_t name)
{
    sem_t *s = sem_for(name);
    if (!s)
        return KERN_INVALID_ARGUMENT_;
    while (sem_wait(s) != 0)
        if (errno != EINTR)
            return KERN_ABORTED_;
    return KERN_SUCCESS_;
}

struct mac_mach_timespec { unsigned int tv_sec; int tv_nsec; };

/* The time is how long to wait, not a date. */
static int mac_semaphore_timedwait(uint32_t name, struct mac_mach_timespec wait)
{
    sem_t *s = sem_for(name);
    if (!s)
        return KERN_INVALID_ARGUMENT_;
    struct timespec until;
    clock_gettime(CLOCK_REALTIME, &until);
    until.tv_sec += wait.tv_sec;
    until.tv_nsec += wait.tv_nsec;
    while (until.tv_nsec >= 1000000000L) {
        until.tv_nsec -= 1000000000L;
        until.tv_sec++;
    }
    while (sem_timedwait(s, &until) != 0) {
        if (errno == ETIMEDOUT)
            return KERN_OPERATION_TIMED_OUT_;
        if (errno != EINTR)
            return KERN_ABORTED_;
    }
    return KERN_SUCCESS_;
}

/* ---- pathconf: a Mac numbers _PC_LINK_MAX..._PC_VDISABLE from 1, this system from 0 */

static int pc_to_linux(int name)
{
    if (name >= 1 && name <= 9)
        return name - 1;
    errno = EINVAL;
    return -1;
}

/* A Mac's _PC_CASE_SENSITIVE and _PC_CASE_PRESERVING (Qt's file dialog
 * asks): this system's file systems keep names as written and tell cases
 * apart. */
enum { MAC_PC_CASE_SENSITIVE = 11, MAC_PC_CASE_PRESERVING = 12 };

static long mac_pathconf(const char *path, int name)
{
    if (name == MAC_PC_CASE_SENSITIVE || name == MAC_PC_CASE_PRESERVING) {
        if (access(path, F_OK) < 0) {
            ferry_sync_errno();
            return -1;
        }
        return 1;
    }
    int n = pc_to_linux(name);
    if (n < 0) {
        ferry_sync_errno();
        return -1;
    }
    long r = pathconf(path, n);
    if (r < 0)
        ferry_sync_errno();
    return r;
}

static long mac_fpathconf(int fd, int name)
{
    if (name == MAC_PC_CASE_SENSITIVE || name == MAC_PC_CASE_PRESERVING) {
        if (fcntl(fd, F_GETFD) < 0) {
            ferry_sync_errno();
            return -1;
        }
        return 1;
    }
    int n = pc_to_linux(name);
    if (n < 0) {
        ferry_sync_errno();
        return -1;
    }
    long r = fpathconf(fd, n);
    if (r < 0)
        ferry_sync_errno();
    return r;
}

/* ---- the reentrant user lookups, with a Mac's struct passwd ------------------------ */

struct mac_passwd {
    char *name, *passwd;
    uint32_t uid, gid;
    long change;
    char *class_, *gecos, *dir, *shell;
    long expire;
};

static char empty_class[] = "";

static int to_mac_pw(int r, struct passwd *p, struct passwd *found, struct mac_passwd *out,
                     struct mac_passwd **result)
{
    *result = NULL;
    if (r != 0)
        return ferry_errno_to_mac(r);
    if (!found)
        return 0;
    *out = (struct mac_passwd){.name = p->pw_name, .passwd = p->pw_passwd, .uid = p->pw_uid,
                               .gid = p->pw_gid, .class_ = empty_class, .gecos = p->pw_gecos,
                               .dir = p->pw_dir, .shell = p->pw_shell};
    *result = out;
    return 0;
}

static int mac_getpwuid_r(uint32_t uid, struct mac_passwd *out, char *buf, size_t len,
                          struct mac_passwd **result)
{
    struct passwd p, *found = NULL;
    int r = getpwuid_r(uid, &p, buf, len, &found);
    return to_mac_pw(r, &p, found, out, result);
}

static int mac_getpwnam_r(const char *name, struct mac_passwd *out, char *buf, size_t len,
                          struct mac_passwd **result)
{
    struct passwd p, *found = NULL;
    int r = getpwnam_r(name, &p, buf, len, &found);
    return to_mac_pw(r, &p, found, out, result);
}

/* ---- signal sets: a Mac's is 32 bits, bit s-1 for signal s ------------------------- */

static void sigs_to_linux(uint32_t mac, sigset_t *set)
{
    sigemptyset(set);
    for (int i = 1; i < 32; i++)
        if ((mac & (1u << (i - 1))) && ferry_signal_to_linux(i))
            sigaddset(set, ferry_signal_to_linux(i));
}

static uint32_t sigs_to_mac(const sigset_t *set)
{
    uint32_t out = 0;
    for (int i = 1; i < 32; i++) {
        int l = ferry_signal_to_linux(i);
        if (l && sigismember(set, l) == 1)
            out |= 1u << (i - 1);
    }
    return out;
}

static int mac_sigwait(const uint32_t *set, int *sig)
{
    sigset_t s;
    int got;
    sigs_to_linux(*set, &s);
    int r = sigwait(&s, &got);
    if (r != 0)
        return ferry_errno_to_mac(r);
    *sig = ferry_signal_to_mac(got);
    return 0;
}

static int mac_sigpending(uint32_t *set)
{
    sigset_t s;
    if (sigpending(&s) != 0) {
        ferry_sync_errno();
        return -1;
    }
    *set = sigs_to_mac(&s);
    return 0;
}

static int mac_sigsuspend(const uint32_t *set)
{
    sigset_t s;
    sigs_to_linux(*set, &s);
    int r = sigsuspend(&s);
    ferry_sync_errno();
    return r;
}

/* ---- setjmp and longjmp, in a Mac's jmp_buf (freemac 1.238) -------------------------
 *
 * A Mac's jmp_buf is 37 ints (148 bytes) and its sigjmp_buf 38, smaller than
 * this system's, so Mac code can't use glibc's. What's inside is libSystem's
 * own business; Ferry keeps, in order: the return address, the stack pointer
 * the caller had before the call, rbp, rbx, r12 to r15, MXCSR and the x87
 * control word (4 bytes each), whether the signal mask was kept, and the
 * Mac's 32-bit signal mask. setjmp and longjmp keep and restore the mask, as
 * BSD's do; _setjmp and _longjmp don't; sigsetjmp keeps it when asked to,
 * and siglongjmp (or longjmp) restores it when it was kept. Only the signals
 * a Mac has are changed back, so Ferry's own stay as they are. */

enum { JB_KEPT = 72, JB_MASK = 76 };

__attribute__((used)) static void jmp_keep_mask(char *buf)
{
    sigset_t s;
    pthread_sigmask(SIG_BLOCK, NULL, &s);
    uint32_t mac = sigs_to_mac(&s);
    memcpy(buf + JB_MASK, &mac, 4);
}

__attribute__((used)) static void jmp_restore_mask(const char *buf)
{
    int32_t kept;
    uint32_t mac;
    memcpy(&kept, buf + JB_KEPT, 4);
    if (!kept)
        return;
    memcpy(&mac, buf + JB_MASK, 4);
    sigset_t block, unblock;
    sigs_to_linux(mac, &block);
    sigs_to_linux(~mac, &unblock);
    pthread_sigmask(SIG_BLOCK, &block, NULL);
    pthread_sigmask(SIG_UNBLOCK, &unblock, NULL);
}

int mac_setjmp(void *buf), mac__setjmp(void *buf), mac_sigsetjmp(void *buf, int keep);
void mac_longjmp(void *buf, int value), mac__longjmp(void *buf, int value);
__asm__(".text\n"
        "mac_setjmp:\n"
        "    movl $1, %esi\n"
        "    jmp mac_sigsetjmp\n"
        "mac__setjmp:\n"
        "    xorl %esi, %esi\n"
        "mac_sigsetjmp:\n"
        "    movq (%rsp), %rax\n"
        "    movq %rax, 0(%rdi)\n"
        "    leaq 8(%rsp), %rax\n"
        "    movq %rax, 8(%rdi)\n"
        "    movq %rbp, 16(%rdi)\n"
        "    movq %rbx, 24(%rdi)\n"
        "    movq %r12, 32(%rdi)\n"
        "    movq %r13, 40(%rdi)\n"
        "    movq %r14, 48(%rdi)\n"
        "    movq %r15, 56(%rdi)\n"
        "    stmxcsr 64(%rdi)\n"
        "    fnstcw 68(%rdi)\n"
        "    movl %esi, 72(%rdi)\n"
        "    testl %esi, %esi\n"
        "    jz 1f\n"
        "    subq $8, %rsp\n"
        "    call jmp_keep_mask\n"
        "    addq $8, %rsp\n"
        "1:  xorl %eax, %eax\n"
        "    ret\n"
        "mac_longjmp:\n"
        "    pushq %rdi\n"
        "    pushq %rsi\n"
        "    subq $8, %rsp\n"
        "    call jmp_restore_mask\n"
        "    addq $8, %rsp\n"
        "    popq %rsi\n"
        "    popq %rdi\n"
        "mac__longjmp:\n"
        "    movl %esi, %eax\n"
        "    testl %eax, %eax\n"
        "    jnz 2f\n"
        "    incl %eax\n"
        "2:  movq 16(%rdi), %rbp\n"
        "    movq 24(%rdi), %rbx\n"
        "    movq 32(%rdi), %r12\n"
        "    movq 40(%rdi), %r13\n"
        "    movq 48(%rdi), %r14\n"
        "    movq 56(%rdi), %r15\n"
        "    ldmxcsr 64(%rdi)\n"
        "    fnclex\n"
        "    fldcw 68(%rdi)\n"
        "    movq 8(%rdi), %rsp\n"
        "    jmpq *0(%rdi)\n");

/* Called when a longjmp would go to a frame that has gone; a Mac's prints
 * and aborts, and so does this. */
static void mac_longjmperror(void)
{
    fputs("longjmp botch.\n", stderr);
    abort();
}

/* ---- statvfs, in a Mac's layout (its counts are 32 bits, so big disks are scaled) - */

struct mac_statvfs {
    unsigned long bsize, frsize;
    uint32_t blocks, bfree, bavail, files, ffree, favail;
    unsigned long fsid, flag, namemax;
};

static uint32_t clamp32(unsigned long long v) { return v > UINT32_MAX ? UINT32_MAX : (uint32_t)v; }

static void to_mac_statvfs(const struct statvfs *v, struct mac_statvfs *m)
{
    unsigned long long frsize = v->f_frsize ? v->f_frsize : v->f_bsize;
    unsigned long long blocks = v->f_blocks, bfree = v->f_bfree, bavail = v->f_bavail;
    /* Keep the sizes true by counting in bigger blocks when the count won't fit. */
    while (blocks > UINT32_MAX) {
        blocks /= 2;
        bfree /= 2;
        bavail /= 2;
        frsize *= 2;
    }
    *m = (struct mac_statvfs){.bsize = v->f_bsize, .frsize = frsize, .blocks = (uint32_t)blocks,
                              .bfree = (uint32_t)bfree, .bavail = (uint32_t)bavail,
                              .files = clamp32(v->f_files), .ffree = clamp32(v->f_ffree),
                              .favail = clamp32(v->f_favail), .fsid = v->f_fsid,
                              .flag = v->f_flag & (ST_RDONLY | ST_NOSUID),
                              .namemax = v->f_namemax};
}

static int mac_statvfs(const char *path, struct mac_statvfs *m)
{
    struct statvfs v;
    if (statvfs(path, &v) != 0) {
        ferry_sync_errno();
        return -1;
    }
    to_mac_statvfs(&v, m);
    return 0;
}

static int mac_fstatvfs(int fd, struct mac_statvfs *m)
{
    struct statvfs v;
    if (fstatvfs(fd, &v) != 0) {
        ferry_sync_errno();
        return -1;
    }
    to_mac_statvfs(&v, m);
    return 0;
}

/* ---- strnstr: find little in the first len bytes of big (a BSD call) -------------- */

static char *mac_strnstr(const char *big, const char *little, size_t len)
{
    size_t n = strlen(little);
    if (n == 0)
        return (char *)big;
    for (size_t i = 0; i + n <= len && big[i]; i++)
        if (big[i] == little[0] && strncmp(big + i, little, n) == 0)
            return (char *)big + i;
    return NULL;
}

/* ---- the error messages by a Mac's numbers, as the old sys_errlist array ---------- */

#define MAC_ELAST 106
static const char *mac_sys_errlist[MAC_ELAST + 1];
static const int mac_sys_nerr = MAC_ELAST + 1;

__attribute__((constructor)) static void fill_errlist(void)
{
    mac_sys_errlist[0] = "Undefined error: 0";
    for (int i = 1; i <= MAC_ELAST; i++) {
        int l = ferry_errno_to_linux(i);
        mac_sys_errlist[i] = l ? strerror(l) : "Unknown error";
    }
}

/* ---- the Mac's libm names for 10 to the power x --------------------------------- */

static double mac_exp10(double x) { return exp10(x); }
static float mac_exp10f(float x) { return exp10f(x); }

/* ---- Mach error text: KERN_SUCCESS and the kernel's common numbers ------------- */

static char *mac_mach_error_string(int e)
{
    switch (e) {
    case 0: return "(os/kern) successful";
    case 1: return "(os/kern) invalid address";
    case 2: return "(os/kern) protection failure";
    case 3: return "(os/kern) no space available";
    case 4: return "(os/kern) invalid argument";
    case 5: return "(os/kern) failure";
    case 6: return "(os/kern) resource shortage";
    case 14: return "(os/kern) operation aborted";
    case 49: return "(os/kern) operation timed out";
    default: return "(os/kern) unknown error code";
    }
}

static void mac_mach_error(const char *what, int e)
{
    fprintf(stderr, "%s %s (0x%x)\n", what ? what : "", mac_mach_error_string(e), (unsigned)e);
}

/* ---- backtrace: the frame pointers Mac code keeps, followed up this thread's stack, and
 * each address named by the Mac image and symbol it is in, in a Mac's format
 * (freemac 1.233, Ferry 0.57.0). This system's backtrace reads unwind tables,
 * which Mac code loaded by Ferry doesn't register, and found only Ferry's own
 * frame. The walk ends where a frame of Ferry's own, built without frame
 * pointers, breaks the chain. */

static int mac_backtrace(void **out, int size)
{
    pthread_attr_t a;
    void *lo = NULL;
    size_t len = 0;
    if (pthread_getattr_np(pthread_self(), &a) == 0) {
        pthread_attr_getstack(&a, &lo, &len);
        pthread_attr_destroy(&a);
    }
    uintptr_t low = (uintptr_t)lo, high = low + len;
    uintptr_t *fp = __builtin_frame_address(0);
    int n = 0;
    while (n < size && fp && (uintptr_t)fp >= low && (uintptr_t)fp + 16 <= high && !((uintptr_t)fp & 7)) {
        void *ret = (void *)fp[1];
        if (!ret)
            break;
        out[n++] = ret;
        uintptr_t *next = (uintptr_t *)fp[0];
        if (next <= fp)
            break;
        fp = next;
    }
    return n;
}

static int describe(void *addr, int i, char *buf, size_t size)
{
    struct image *im = ferry_image_containing(addr);
    const char *file = "libsystem", *name = NULL;
    void *start = NULL;
    if (im) {
        file = ferry_image_path(im);
        name = ferry_image_nearest(im, addr, &start);
    }
    const char *leaf = file && strrchr(file, '/') ? strrchr(file, '/') + 1 : file ? file : "???";
    if (name && name[0] == '_')
        name++;
    if (name && start)
        return snprintf(buf, size, "%-4d%-35s 0x%016llx %s + %llu", i, leaf, (unsigned long long)(uintptr_t)addr,
                        name, (unsigned long long)((uintptr_t)addr - (uintptr_t)start));
    return snprintf(buf, size, "%-4d%-35s 0x%016llx 0x%llx + 0", i, leaf, (unsigned long long)(uintptr_t)addr,
                    (unsigned long long)(uintptr_t)addr);
}

/* one block: the pointers, then the strings, freed with one free() */
static char **mac_backtrace_symbols(void *const *addrs, int n)
{
    if (n <= 0)
        return NULL;
    size_t total = n * sizeof(char *);
    char line[1024];
    for (int i = 0; i < n; i++)
        total += describe(addrs[i], i, line, sizeof line) + 1;
    char **out = malloc(total);
    if (!out)
        return NULL;
    char *p = (char *)(out + n), *end = (char *)out + total;
    for (int i = 0; i < n; i++) {
        out[i] = p;
        p += describe(addrs[i], i, p, end - p) + 1;
    }
    return out;
}

static void mac_backtrace_symbols_fd(void *const *addrs, int n, int fd)
{
    char line[1024];
    for (int i = 0; i < n; i++) {
        int len = describe(addrs[i], i, line, sizeof line - 1);
        if (len > (int)sizeof line - 2)
            len = sizeof line - 2;
        line[len++] = '\n';
        if (write(fd, line, len) < 0)
            break;
    }
}


/* ---- iconv (freemac 1.238; VLC's subtitle decoder) ----------------------------
 * A Mac's /usr/lib/libiconv.2.dylib is GNU libiconv. glibc has the same three
 * calls, with the same iconv_t (a pointer, -1 on failure), the same
 * character set names for everything VLC asks for (UTF-8, CP1252, UTF-16LE,
 * WCHAR_T, ISO-8859-x...) and a 4-byte wchar_t, as a Mac has. errno comes
 * back in the Mac's numbers (EILSEQ, E2BIG, EINVAL) as for any other call.
 * GNU libiconv's own names (libiconv_open and so on) are the same calls. */
static iconv_t mac_iconv_open(const char *to, const char *from) { return iconv_open(to, from); }
static size_t mac_iconv(iconv_t cd, char **in, size_t *inleft, char **out, size_t *outleft)
{
    return iconv(cd, in, inleft, out, outleft);
}
static int mac_iconv_close(iconv_t cd) { return iconv_close(cd); }
/* iconvctl: only "is this conversion trivial" has an answer here; the other
 * requests (transliteration and discarding on the fly) aren't offered. */
static int mac_iconvctl(iconv_t cd, int request, void *arg)
{
    (void)cd;
    if (request == 0 && arg) { /* ICONV_TRIVIALP */
        *(int *)arg = 0;
        return 0;
    }
    ferry_set_mac_errno(22); /* EINVAL */
    return -1;
}
static const char *mac_locale_charset(void) { return "UTF-8"; }
static const int mac_libiconv_version = 0x010b; /* 1.11, as a Mac's */

const struct ferry_symbol ferry_libc_vlc_symbols[] = {
    {"iconv_open", mac_iconv_open},
    {"iconv", mac_iconv},
    {"iconv_close", mac_iconv_close},
    {"iconvctl", mac_iconvctl},
    {"libiconv_open", mac_iconv_open},
    {"libiconv", mac_iconv},
    {"libiconv_close", mac_iconv_close},
    {"libiconvctl", mac_iconvctl},
    {"locale_charset", mac_locale_charset},
    {"_libiconv_version", (void *)&mac_libiconv_version},
    {"backtrace", mac_backtrace},
    {"backtrace_symbols", mac_backtrace_symbols},
    {"backtrace_symbols_fd", mac_backtrace_symbols_fd},
    {"semaphore_create", mac_semaphore_create},
    {"semaphore_destroy", mac_semaphore_destroy},
    {"semaphore_signal", mac_semaphore_signal},
    {"semaphore_signal_all", mac_semaphore_signal_all},
    {"semaphore_wait", mac_semaphore_wait},
    {"semaphore_timedwait", mac_semaphore_timedwait},
    {"pathconf", mac_pathconf},
    {"fpathconf", mac_fpathconf},
    {"getpwuid_r", mac_getpwuid_r},
    {"getpwnam_r", mac_getpwnam_r},
    {"sigwait", mac_sigwait},
    {"sigpending", mac_sigpending},
    {"sigsuspend", mac_sigsuspend},
    {"statvfs", mac_statvfs},
    {"fstatvfs", mac_fstatvfs},
    {"strnstr", mac_strnstr},
    {"setjmp", mac_setjmp},
    {"_setjmp", mac__setjmp},
    {"sigsetjmp", mac_sigsetjmp},
    {"longjmp", mac_longjmp},
    {"_longjmp", mac__longjmp},
    {"siglongjmp", mac_longjmp},
    {"longjmperror", mac_longjmperror},
    {"__exp10", mac_exp10},
    {"mach_error_string", mac_mach_error_string},
    {"mach_error", mac_mach_error},
    {"__exp10f", mac_exp10f},
    {"sys_errlist", (void *)mac_sys_errlist},
    {"sys_nerr", (void *)&mac_sys_nerr},
    {NULL, NULL},
};
