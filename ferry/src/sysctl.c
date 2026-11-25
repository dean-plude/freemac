/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * What a Mac program asks about the system: sysctl, sysctlbyname and
 * sysctlnametomib for the names apps read, proc_pidpath and proc_name, and
 * the Mach calls for memory figures (host_statistics64, host_info,
 * host_page_size, task_info). Written from Apple's public documentation
 * (the sysctl(3) and sysctl(8) man pages, the Mach and libproc reference
 * pages), not from Apple's code.
 *
 * The version names answer from the numbers in ferry.h (sysversion.c), as
 * uname and NSProcessInfo do; the machine names answer from this machine:
 * its processors, memory, caches and boot time, read from Linux. hw.model
 * is the Intel Mac model Ferry presents (ferry.h).
 *
 * The calling rules are the documented ones: a NULL buffer asks for the
 * size; a buffer too small gets what fits and ENOMEM; an unknown name is
 * ENOENT; nothing can be set (EPERM). A number the Mac keeps in 64 bits may
 * also be read into exactly 4 bytes when its value fits, as programs do
 * with hw.pagesize and the cache sizes.
 */
#define _GNU_SOURCE
#include <cpuid.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <linux/futex.h>
#include <sys/syscall.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"

extern char **environ;

/* ---- the values ---------------------------------------------------------------- */

enum { T_NODE, T_STRING, T_INT, T_QUAD, T_OPAQUE };

struct value {
    int type;
    size_t size;
    union {
        char s[2048];
        int32_t i;
        int64_t q;
        unsigned char raw[2048];
    } u;
};

static int set_string(struct value *v, const char *s)
{
    v->type = T_STRING;
    snprintf(v->u.s, sizeof v->u.s, "%s", s);
    v->size = strlen(v->u.s) + 1;
    return 0;
}

static int set_int(struct value *v, long i)
{
    v->type = T_INT;
    v->u.i = (int32_t)i;
    v->size = 4;
    return 0;
}

static int set_quad(struct value *v, int64_t q)
{
    v->type = T_QUAD;
    v->u.q = q;
    v->size = 8;
    return 0;
}

static int read_text(const char *path, char *buf, size_t size)
{
    FILE *f = fopen(path, "re");
    if (!f)
        return -1;
    size_t n = fread(buf, 1, size - 1, f);
    fclose(f);
    buf[n] = 0;
    return (int)n;
}

/* ---- processors ------------------------------------------------------------- */

static long logical_online(void) { return sysconf(_SC_NPROCESSORS_ONLN); }
static long logical_configured(void) { return sysconf(_SC_NPROCESSORS_CONF); }

/* Physical cores: the distinct (package, core) pairs of the online
 * processors. */
static long physical_cores(void)
{
    static long cached;
    if (cached)
        return cached;
    long n = 0, max = logical_configured();
    int seen[1024][2];
    for (long cpu = 0; cpu < max && cpu < 4096; cpu++) {
        char path[128], text[32];
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%ld/topology/core_id", cpu);
        if (read_text(path, text, sizeof text) <= 0)
            continue;
        int core = atoi(text), package = 0;
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%ld/topology/physical_package_id", cpu);
        if (read_text(path, text, sizeof text) > 0)
            package = atoi(text);
        int known = 0;
        for (long k = 0; k < n && !known; k++)
            known = seen[k][0] == package && seen[k][1] == core;
        if (!known && n < 1024) {
            seen[n][0] = package;
            seen[n][1] = core;
            n++;
        }
    }
    cached = n > 0 ? n : logical_online();
    return cached;
}

/* The processor's own name for itself (CPUID's brand string), without the
 * spaces some processors pad it with. */
static void brand_string(char *out, size_t size)
{
    unsigned regs[12] = {0}, max = __get_cpuid_max(0x80000000, NULL);
    if (max < 0x80000004) {
        snprintf(out, size, "Unknown x86-64 processor");
        return;
    }
    for (unsigned i = 0; i < 3; i++)
        __get_cpuid(0x80000002 + i, &regs[i * 4], &regs[i * 4 + 1], &regs[i * 4 + 2], &regs[i * 4 + 3]);
    char text[49];
    memcpy(text, regs, 48);
    text[48] = 0;
    char *s = text;
    while (*s == ' ')
        s++;
    size_t n = strlen(s);
    while (n && s[n - 1] == ' ')
        s[--n] = 0;
    snprintf(out, size, "%s", s);
}

static void vendor_string(char *out, size_t size)
{
    unsigned a, b, c, d;
    char text[13] = "";
    if (__get_cpuid(0, &a, &b, &c, &d)) {
        memcpy(text, &b, 4);
        memcpy(text + 4, &d, 4);
        memcpy(text + 8, &c, 4);
        text[12] = 0;
    }
    snprintf(out, size, "%s", text);
}

/* hw.optional: the instruction set extensions the processor has and the
 * system lets programs use (AVX needs the system to save its registers). */
enum { F_MMX, F_SSE, F_SSE2, F_SSE3, F_SSSE3, F_SSE41, F_SSE42, F_AES, F_AVX, F_AVX2, F_FMA, F_F16C, F_BMI1,
       F_BMI2, F_RDRAND, F_AVX512F, F_AVX512CD, F_AVX512DQ, F_AVX512BW, F_AVX512VL };

static int has_feature(int which)
{
    unsigned a = 0, b = 0, c = 0, d = 0, b7 = 0, c7 = 0, d7 = 0;
    __get_cpuid(1, &a, &b, &c, &d);
    if (__get_cpuid_max(0, NULL) >= 7)
        __cpuid_count(7, 0, a, b7, c7, d7);
    unsigned long long xcr0 = 0;
    if (c & (1u << 27)) { /* OSXSAVE */
        unsigned lo, hi;
        __asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
        xcr0 = (unsigned long long)hi << 32 | lo;
    }
    int avx_os = (xcr0 & 6) == 6, avx512_os = (xcr0 & 0xe6) == 0xe6;
    switch (which) {
    case F_MMX: return (d >> 23) & 1;
    case F_SSE: return (d >> 25) & 1;
    case F_SSE2: return (d >> 26) & 1;
    case F_SSE3: return c & 1;
    case F_SSSE3: return (c >> 9) & 1;
    case F_SSE41: return (c >> 19) & 1;
    case F_SSE42: return (c >> 20) & 1;
    case F_AES: return (c >> 25) & 1;
    case F_AVX: return avx_os && ((c >> 28) & 1);
    case F_FMA: return avx_os && ((c >> 12) & 1);
    case F_F16C: return avx_os && ((c >> 29) & 1);
    case F_RDRAND: return (c >> 30) & 1;
    case F_AVX2: return avx_os && ((b7 >> 5) & 1);
    case F_BMI1: return (b7 >> 3) & 1;
    case F_BMI2: return (b7 >> 8) & 1;
    case F_AVX512F: return avx512_os && ((b7 >> 16) & 1);
    case F_AVX512DQ: return avx512_os && ((b7 >> 17) & 1);
    case F_AVX512CD: return avx512_os && ((b7 >> 28) & 1);
    case F_AVX512BW: return avx512_os && ((b7 >> 30) & 1);
    case F_AVX512VL: return avx512_os && ((b7 >> 31) & 1);
    }
    return 0;
}

/* ---- memory and time ----------------------------------------------------------- */

static int64_t memory_size(void) { return (int64_t)sysconf(_SC_PHYS_PAGES) * sysconf(_SC_PAGESIZE); }

static long cache_size(int name, long fallback)
{
    long v = sysconf(name);
    return v > 0 ? v : fallback;
}

/* When the machine started, in seconds since 1970: Linux's "btime". */
static time_t boot_time(void)
{
    static time_t cached;
    if (cached)
        return cached;
    char text[8192];
    if (read_text("/proc/stat", text, sizeof text) > 0) {
        char *p = strstr(text, "\nbtime ");
        if (p)
            cached = (time_t)strtoll(p + 7, NULL, 10);
    }
    if (!cached) {
        struct timespec now, up;
        clock_gettime(CLOCK_REALTIME, &now);
        clock_gettime(CLOCK_BOOTTIME, &up);
        cached = now.tv_sec - up.tv_sec;
    }
    return cached;
}

struct mac_timeval { int64_t tv_sec; int32_t tv_usec; int32_t pad_; };

/* ---- one process (KERN_PROC_PID): struct kinfo_proc ------------------------------
 * The layout of the 64-bit struct kinfo_proc (struct extern_proc then
 * struct eproc, 648 bytes), with the documented fields programs read:
 * p_pid, p_flag (P_TRACED: a debugger is attached), p_stat, p_comm, the
 * start time, e_ppid, e_pgid, the terminal and the user and group ids. */

struct mac_extern_proc {
    union {
        struct { uint64_t forw, back; } st1;
        struct mac_timeval starttime;
    } p_un;
    uint64_t p_vmspace, p_sigacts;
    int32_t p_flag;
    char p_stat;
    int32_t p_pid, p_oppid, p_dupfd;
    uint64_t user_stack, exit_thread;
    int32_t p_debugger, sigwait;
    uint32_t p_estcpu;
    int32_t p_cpticks;
    uint32_t p_pctcpu;
    uint64_t p_wchan, p_wmesg;
    uint32_t p_swtime, p_slptime;
    struct mac_timeval p_realtimer[2], p_rtime;
    uint64_t p_uticks, p_sticks, p_iticks;
    int32_t p_traceflag;
    uint64_t p_tracep;
    int32_t p_siglist;
    uint64_t p_textvp;
    int32_t p_holdcnt;
    uint32_t p_sigmask, p_sigignore, p_sigcatch;
    uint8_t p_priority, p_usrpri;
    char p_nice;
    char p_comm[17];
    uint64_t p_pgrp, p_addr;
    uint16_t p_xstat, p_acflag;
    uint64_t p_ru;
};

struct mac_eproc {
    uint64_t e_paddr, e_sess;
    struct {
        char pc_lock[72];
        uint64_t pc_ucred;
        uint32_t p_ruid, p_svuid, p_rgid, p_svgid;
        int32_t p_refcnt;
    } e_pcred;
    struct {
        int32_t cr_ref;
        uint32_t cr_uid;
        int16_t cr_ngroups;
        uint32_t cr_groups[16];
    } e_ucred;
    struct {
        int32_t dummy;
        uint64_t dummy2;
        int32_t dummy3[5];
        uint64_t dummy4[3];
    } e_vm;
    int32_t e_ppid, e_pgid;
    int16_t e_jobc;
    int32_t e_tdev, e_tpgid;
    uint64_t e_tsess;
    char e_wmesg[8];
    int32_t e_xsize;
    int16_t e_xrssize, e_xccount, e_xswrss;
    int32_t e_flag;
    char e_login[12];
    int32_t e_spare[4];
};

struct mac_kinfo_proc {
    struct mac_extern_proc kp_proc;
    struct mac_eproc kp_eproc;
};

_Static_assert(sizeof(struct mac_extern_proc) == 296, "extern_proc");
_Static_assert(sizeof(struct mac_eproc) == 352, "eproc");
_Static_assert(sizeof(struct mac_kinfo_proc) == 648, "kinfo_proc");
_Static_assert(__builtin_offsetof(struct mac_extern_proc, p_flag) == 32, "p_flag");
_Static_assert(__builtin_offsetof(struct mac_extern_proc, p_pid) == 40, "p_pid");
_Static_assert(__builtin_offsetof(struct mac_extern_proc, p_comm) == 243, "p_comm");
_Static_assert(__builtin_offsetof(struct mac_eproc, e_ucred) == 120, "e_ucred");
_Static_assert(__builtin_offsetof(struct mac_eproc, e_ppid) == 264, "e_ppid");

#define MAC_P_LP64 0x4
#define MAC_P_TRACED 0x800
#define MAC_SRUN 2
#define MAC_SSLEEP 3
#define MAC_SSTOP 4
#define MAC_SZOMB 5
#define MAC_EPROC_CTTY 0x1
#define MAC_EPROC_SLEADER 0x2

/* Fills in a process from /proc; 0 if there is no such process. */
static int process_info(pid_t pid, struct mac_kinfo_proc *k)
{
    char path[64], stat[1024], status[4096];
    memset(k, 0, sizeof *k);
    snprintf(path, sizeof path, "/proc/%d/stat", (int)pid);
    if (read_text(path, stat, sizeof stat) <= 0)
        return 0;
    snprintf(path, sizeof path, "/proc/%d/status", (int)pid);
    if (read_text(path, status, sizeof status) <= 0)
        status[0] = 0;
    /* "pid (name) state ppid pgrp session tty_nr tpgid flags ...": the name
     * may hold spaces and parentheses, so the fields start after the last ')' */
    char *open = strchr(stat, '('), *close = strrchr(stat, ')');
    if (!open || !close || close < open)
        return 0;
    char comm[64];
    snprintf(comm, sizeof comm, "%.*s", (int)(close - open - 1), open + 1);
    char state = 0;
    long fields[64] = {0};
    int nf = 0;
    char *p = close + 1;
    while (*p == ' ')
        p++;
    state = *p++;
    while (*p && nf < 64) {
        while (*p == ' ')
            p++;
        if (!*p)
            break;
        fields[nf++] = strtol(p, &p, 10);
    }
    /* after the state: ppid pgrp session tty_nr tpgid flags minflt cminflt
     * majflt cmajflt utime stime cutime cstime priority nice threads
     * itrealvalue starttime */
    long ppid = fields[0], pgrp = fields[1], session = fields[2], tty = fields[3], tpgid = fields[4];
    long nice = fields[15];
    unsigned long long start_ticks = (unsigned long long)fields[18];
    unsigned ruid = 0, euid = 0, suid = 0, rgid = 0, egid = 0, sgid = 0;
    long tracer = 0;
    char *u = strstr(status, "\nUid:"), *g = strstr(status, "\nGid:"), *t = strstr(status, "\nTracerPid:");
    if (u)
        sscanf(u + 5, "%u %u %u", &ruid, &euid, &suid);
    if (g)
        sscanf(g + 5, "%u %u %u", &rgid, &egid, &sgid);
    if (t)
        tracer = strtol(t + 11, NULL, 10);

    struct mac_extern_proc *kp = &k->kp_proc;
    struct mac_eproc *ep = &k->kp_eproc;
    long hz = sysconf(_SC_CLK_TCK);
    if (hz <= 0)
        hz = 100;
    kp->p_un.starttime.tv_sec = boot_time() + (int64_t)(start_ticks / (unsigned long long)hz);
    kp->p_un.starttime.tv_usec = (int32_t)((start_ticks % (unsigned long long)hz) * 1000000ull / (unsigned long long)hz);
    kp->p_flag = MAC_P_LP64 | (tracer ? MAC_P_TRACED : 0);
    kp->p_stat = state == 'R' ? MAC_SRUN : state == 'T' || state == 't' ? MAC_SSTOP
                 : state == 'Z' || state == 'X' ? MAC_SZOMB : MAC_SSLEEP;
    if (pid == getpid())
        kp->p_stat = MAC_SRUN;
    kp->p_pid = pid;
    kp->p_nice = (char)nice;
    /* This process's name is the Mac program's, not Ferry's. */
    const char *name = comm;
    if (pid == getpid() && ferry_program_path()[0]) {
        const char *slash = strrchr(ferry_program_path(), '/');
        name = slash ? slash + 1 : ferry_program_path();
    }
    snprintf(kp->p_comm, sizeof kp->p_comm, "%s", name);
    ep->e_pcred.p_ruid = ruid;
    ep->e_pcred.p_svuid = suid;
    ep->e_pcred.p_rgid = rgid;
    ep->e_pcred.p_svgid = sgid;
    ep->e_ucred.cr_ref = 1;
    ep->e_ucred.cr_uid = euid;
    ep->e_ucred.cr_ngroups = 1;
    ep->e_ucred.cr_groups[0] = egid;
    if (pid == getpid()) {
        gid_t groups[16];
        int n = getgroups(16, groups);
        for (int i = 0; i < n && i < 15; i++)
            ep->e_ucred.cr_groups[1 + i] = groups[i];
        if (n > 0)
            ep->e_ucred.cr_ngroups = (int16_t)(1 + (n < 15 ? n : 15));
    }
    ep->e_ppid = (int32_t)ppid;
    ep->e_pgid = (int32_t)pgrp;
    ep->e_tpgid = (int32_t)tpgid;
    if (tty) {
        unsigned major = ((unsigned)tty >> 8) & 0xfff, minor = ((unsigned)tty & 0xff) | (((unsigned)tty >> 12) & 0xfff00);
        ep->e_tdev = (int32_t)(major << 24 | (minor & 0xffffff));
        ep->e_flag |= MAC_EPROC_CTTY;
    } else
        ep->e_tdev = -1; /* NODEV */
    if (session == pid)
        ep->e_flag |= MAC_EPROC_SLEADER;
    return 1;
}

/* KERN_PROCARGS2 for this process: argc, the program's path, then its
 * arguments and environment, each ending in a zero byte. */
static size_t process_arguments(unsigned char *out, size_t size)
{
    int argc;
    char **argv;
    ferry_program_args(&argc, &argv);
    size_t n = 0;
#define PUT(src, len)                                  \
    do {                                               \
        size_t l_ = (len);                             \
        if (n + l_ > size)                             \
            return 0;                                  \
        memcpy(out + n, (src), l_);                    \
        n += l_;                                       \
    } while (0)
    int32_t count = argc;
    PUT(&count, 4);
    PUT(ferry_program_path(), strlen(ferry_program_path()) + 1);
    static const char zeros[8];
    PUT(zeros, (8 - n % 8) % 8);
    for (int i = 0; i < argc; i++)
        PUT(argv[i], strlen(argv[i]) + 1);
    for (char **e = environ; e && *e; e++)
        PUT(*e, strlen(*e) + 1);
#undef PUT
    return n;
}

/* ---- the names -------------------------------------------------------------------- */

#define CTL_SYSCTL 0
#define CTL_KERN 1
#define CTL_HW 6
#define CTL_MACHDEP 7
#define KERN_PROC 14
#define KERN_PROC_PID 1
#define KERN_PROCARGS2 49
#define AUTO 100 /* names with no fixed number get one from here up */

static int get_ostype(struct value *v) { return set_string(v, "Darwin"); }
static int get_osrelease(struct value *v) { return set_string(v, FERRY_DARWIN_RELEASE); }
static int get_osversion(struct value *v) { return set_string(v, FERRY_MACOS_BUILD); }
static int get_osproductversion(struct value *v) { return set_string(v, FERRY_MACOS_VERSION); }
static int get_version(struct value *v) { return set_string(v, ferry_kernel_version()); }
static int get_argmax(struct value *v) { return set_int(v, sysconf(_SC_ARG_MAX)); }
static int get_maxfilesperproc(struct value *v)
{
    struct rlimit r;
    return set_int(v, getrlimit(RLIMIT_NOFILE, &r) == 0 && r.rlim_max < INT32_MAX ? (long)r.rlim_max : 10240);
}
static int get_hostname(struct value *v)
{
    char name[256] = "";
    gethostname(name, sizeof name - 1);
    return set_string(v, name);
}
static int get_boottime(struct value *v)
{
    struct mac_timeval tv = {boot_time(), 0, 0};
    v->type = T_OPAQUE;
    memcpy(v->u.raw, &tv, sizeof tv);
    v->size = sizeof tv;
    return 0;
}
static int get_machine(struct value *v) { return set_string(v, "x86_64"); }
static int get_model(struct value *v) { return set_string(v, FERRY_MAC_MODEL); }
static int get_ncpu(struct value *v) { return set_int(v, logical_configured()); }
static int get_activecpu(struct value *v) { return set_int(v, logical_online()); }
static int get_physicalcpu(struct value *v) { return set_int(v, physical_cores()); }
static int get_byteorder(struct value *v) { return set_int(v, 1234); }
static int get_memsize(struct value *v) { return set_quad(v, memory_size()); }
static int get_pagesize(struct value *v) { return set_quad(v, sysconf(_SC_PAGESIZE)); }
static int get_cacheline(struct value *v) { return set_quad(v, cache_size(_SC_LEVEL1_DCACHE_LINESIZE, 64)); }
static int get_l1i(struct value *v) { return set_quad(v, cache_size(_SC_LEVEL1_ICACHE_SIZE, 32768)); }
static int get_l1d(struct value *v) { return set_quad(v, cache_size(_SC_LEVEL1_DCACHE_SIZE, 32768)); }
static int get_l2(struct value *v) { return set_quad(v, cache_size(_SC_LEVEL2_CACHE_SIZE, 262144)); }
static int get_l3(struct value *v)
{
    long l3 = sysconf(_SC_LEVEL3_CACHE_SIZE);
    return l3 > 0 ? set_quad(v, l3) : ENOENT;
}
static int get_cpufrequency(struct value *v)
{
    char text[64];
    if (read_text("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq", text, sizeof text) <= 0)
        return ENOENT;
    return set_quad(v, strtoll(text, NULL, 10) * 1000); /* kHz */
}
static int get_one(struct value *v) { return set_int(v, 1); }
static int get_zero(struct value *v) { return set_int(v, 0); }
static int get_brand(struct value *v)
{
    char s[64];
    brand_string(s, sizeof s);
    return set_string(v, s);
}
static int get_vendor(struct value *v)
{
    char s[16];
    vendor_string(s, sizeof s);
    return set_string(v, s);
}

#define FEATURE(name, flag)                                         \
    static int get_##name(struct value *v) { return set_int(v, has_feature(flag)); }
FEATURE(mmx, F_MMX)
FEATURE(sse, F_SSE)
FEATURE(sse2, F_SSE2)
FEATURE(sse3, F_SSE3)
FEATURE(ssse3, F_SSSE3)
FEATURE(sse4_1, F_SSE41)
FEATURE(sse4_2, F_SSE42)
FEATURE(aes, F_AES)
FEATURE(avx1_0, F_AVX)
FEATURE(avx2_0, F_AVX2)
FEATURE(fma, F_FMA)
FEATURE(f16c, F_F16C)
FEATURE(bmi1, F_BMI1)
FEATURE(bmi2, F_BMI2)
FEATURE(rdrand, F_RDRAND)
FEATURE(avx512f, F_AVX512F)
FEATURE(avx512cd, F_AVX512CD)
FEATURE(avx512dq, F_AVX512DQ)
FEATURE(avx512bw, F_AVX512BW)
FEATURE(avx512vl, F_AVX512VL)

struct entry {
    const char *name;
    int mib[3];
    int depth;
    int (*get)(struct value *);      /* NULL: a node, which holds others */
};

/* The numbered names have the numbers in the Mac's sysctl.h (CTL_KERN,
 * KERN_OSTYPE...); the others are given numbers from AUTO up, as a Mac
 * gives them numbers of its own when it starts. */
static const struct entry entries[] = {
    {"sysctl", {CTL_SYSCTL}, 1, NULL},
    {"sysctl.proc_translated", {CTL_SYSCTL, AUTO}, 2, get_zero},
    {"kern", {CTL_KERN}, 1, NULL},
    {"kern.ostype", {CTL_KERN, 1}, 2, get_ostype},
    {"kern.osrelease", {CTL_KERN, 2}, 2, get_osrelease},
    {"kern.version", {CTL_KERN, 4}, 2, get_version},
    {"kern.argmax", {CTL_KERN, 8}, 2, get_argmax},
    {"kern.hostname", {CTL_KERN, 10}, 2, get_hostname},
    {"kern.proc", {CTL_KERN, KERN_PROC}, 2, NULL},
    {"kern.proc.pid", {CTL_KERN, KERN_PROC, KERN_PROC_PID}, 3, NULL},
    {"kern.boottime", {CTL_KERN, 21}, 2, get_boottime},
    {"kern.maxfilesperproc", {CTL_KERN, 29}, 2, get_maxfilesperproc},
    {"kern.procargs2", {CTL_KERN, KERN_PROCARGS2}, 2, NULL},
    {"kern.osversion", {CTL_KERN, 65}, 2, get_osversion},
    {"kern.osproductversion", {CTL_KERN, AUTO}, 2, get_osproductversion},
    {"hw", {CTL_HW}, 1, NULL},
    {"hw.machine", {CTL_HW, 1}, 2, get_machine},
    {"hw.model", {CTL_HW, 2}, 2, get_model},
    {"hw.ncpu", {CTL_HW, 3}, 2, get_ncpu},
    {"hw.byteorder", {CTL_HW, 4}, 2, get_byteorder},
    {"hw.pagesize", {CTL_HW, 7}, 2, get_pagesize},
    {"hw.cachelinesize", {CTL_HW, 16}, 2, get_cacheline},
    {"hw.l1icachesize", {CTL_HW, 17}, 2, get_l1i},
    {"hw.l1dcachesize", {CTL_HW, 18}, 2, get_l1d},
    {"hw.l2cachesize", {CTL_HW, 20}, 2, get_l2},
    {"hw.l3cachesize", {CTL_HW, 22}, 2, get_l3},
    {"hw.memsize", {CTL_HW, 24}, 2, get_memsize},
    {"hw.activecpu", {CTL_HW, 25}, 2, get_activecpu},
    {"hw.physicalcpu", {CTL_HW, AUTO}, 2, get_physicalcpu},
    {"hw.physicalcpu_max", {CTL_HW, AUTO + 1}, 2, get_physicalcpu},
    {"hw.logicalcpu", {CTL_HW, AUTO + 2}, 2, get_activecpu},
    {"hw.logicalcpu_max", {CTL_HW, AUTO + 3}, 2, get_ncpu},
    {"hw.cpufrequency", {CTL_HW, AUTO + 4}, 2, get_cpufrequency},
    {"hw.cpufrequency_max", {CTL_HW, AUTO + 5}, 2, get_cpufrequency},
    {"hw.cpu64bit_capable", {CTL_HW, AUTO + 6}, 2, get_one},
    {"hw.optional", {CTL_HW, AUTO + 7}, 2, NULL},
    {"hw.optional.floatingpoint", {CTL_HW, AUTO + 7, 1}, 3, get_one},
    {"hw.optional.x86_64", {CTL_HW, AUTO + 7, 2}, 3, get_one},
    {"hw.optional.mmx", {CTL_HW, AUTO + 7, 3}, 3, get_mmx},
    {"hw.optional.sse", {CTL_HW, AUTO + 7, 4}, 3, get_sse},
    {"hw.optional.sse2", {CTL_HW, AUTO + 7, 5}, 3, get_sse2},
    {"hw.optional.sse3", {CTL_HW, AUTO + 7, 6}, 3, get_sse3},
    {"hw.optional.supplementalsse3", {CTL_HW, AUTO + 7, 7}, 3, get_ssse3},
    {"hw.optional.sse4_1", {CTL_HW, AUTO + 7, 8}, 3, get_sse4_1},
    {"hw.optional.sse4_2", {CTL_HW, AUTO + 7, 9}, 3, get_sse4_2},
    {"hw.optional.aes", {CTL_HW, AUTO + 7, 10}, 3, get_aes},
    {"hw.optional.avx1_0", {CTL_HW, AUTO + 7, 11}, 3, get_avx1_0},
    {"hw.optional.avx2_0", {CTL_HW, AUTO + 7, 12}, 3, get_avx2_0},
    {"hw.optional.fma", {CTL_HW, AUTO + 7, 13}, 3, get_fma},
    {"hw.optional.f16c", {CTL_HW, AUTO + 7, 14}, 3, get_f16c},
    {"hw.optional.bmi1", {CTL_HW, AUTO + 7, 15}, 3, get_bmi1},
    {"hw.optional.bmi2", {CTL_HW, AUTO + 7, 16}, 3, get_bmi2},
    {"hw.optional.rdrand", {CTL_HW, AUTO + 7, 17}, 3, get_rdrand},
    {"hw.optional.avx512f", {CTL_HW, AUTO + 7, 18}, 3, get_avx512f},
    {"hw.optional.avx512cd", {CTL_HW, AUTO + 7, 19}, 3, get_avx512cd},
    {"hw.optional.avx512dq", {CTL_HW, AUTO + 7, 20}, 3, get_avx512dq},
    {"hw.optional.avx512bw", {CTL_HW, AUTO + 7, 21}, 3, get_avx512bw},
    {"hw.optional.avx512vl", {CTL_HW, AUTO + 7, 22}, 3, get_avx512vl},
    {"machdep", {CTL_MACHDEP}, 1, NULL},
    {"machdep.cpu", {CTL_MACHDEP, AUTO}, 2, NULL},
    {"machdep.cpu.brand_string", {CTL_MACHDEP, AUTO, 1}, 3, get_brand},
    {"machdep.cpu.vendor", {CTL_MACHDEP, AUTO, 2}, 3, get_vendor},
    {"machdep.cpu.core_count", {CTL_MACHDEP, AUTO, 3}, 3, get_physicalcpu},
    {"machdep.cpu.thread_count", {CTL_MACHDEP, AUTO, 4}, 3, get_ncpu},
    {NULL, {0}, 0, NULL},
};

static const struct entry *by_mib(const int *mib, unsigned len)
{
    for (const struct entry *e = entries; e->name; e++) {
        if ((unsigned)e->depth != len)
            continue;
        int same = 1;
        for (int i = 0; i < e->depth && same; i++)
            same = e->mib[i] == mib[i];
        if (same)
            return e;
    }
    return NULL;
}

static const struct entry *by_name(const char *name)
{
    if (!name)
        return NULL;
    for (const struct entry *e = entries; e->name; e++)
        if (!strcmp(e->name, name))
            return e;
    return NULL;
}

/* Copies a value out by the documented rules; 0 or an errno. */
static int copy_out(const void *data, size_t size, void *old, size_t *oldlen)
{
    if (!oldlen)
        return 0;
    if (!old) {
        *oldlen = size;
        return 0;
    }
    if (*oldlen < size) {
        memcpy(old, data, *oldlen);
        return ENOMEM;
    }
    memcpy(old, data, size);
    *oldlen = size;
    return 0;
}

static int read_value(const struct entry *e, void *old, size_t *oldlen)
{
    struct value v;
    memset(&v, 0, sizeof v);
    int rc = e->get(&v);
    if (rc)
        return rc;
    /* a 64-bit number read into exactly 4 bytes, when it fits */
    if (v.type == T_QUAD && old && oldlen && *oldlen == 4 && v.u.q >= INT32_MIN && v.u.q <= UINT32_MAX) {
        uint32_t small = (uint32_t)v.u.q;
        memcpy(old, &small, 4);
        return 0;
    }
    return copy_out(v.u.raw, v.size, old, oldlen);
}

/* sysctl {0, 3}: a name's numbers, the way sysctlnametomib asks for them. */
static int name_to_oid(const void *new, size_t newlen, void *old, size_t *oldlen)
{
    char name[256];
    if (!new || newlen == 0 || newlen >= sizeof name)
        return ENOENT;
    memcpy(name, new, newlen);
    name[newlen] = 0;
    const struct entry *e = by_name(name);
    if (!e)
        return ENOENT;
    return copy_out(e->mib, (size_t)e->depth * sizeof(int), old, oldlen);
}

static int do_sysctl(const int *mib, unsigned len, void *old, size_t *oldlen, const void *new, size_t newlen)
{
    if (!mib || len < 2 || len > 12)
        return EINVAL;
    if (mib[0] == CTL_SYSCTL && mib[1] == 3)
        return name_to_oid(new, newlen, old, oldlen);
    if (mib[0] == CTL_KERN && mib[1] == KERN_PROC) {
        /* only KERN_PROC_PID; listing processes (KERN_PROC_ALL, by user...) isn't served */
        if (len != 4 || mib[2] != KERN_PROC_PID)
            return len >= 3 && mib[2] != KERN_PROC_PID && mib[2] >= 0 && mib[2] <= 7 ? ENOTSUP : EINVAL;
        if (new)
            return EPERM;
        struct mac_kinfo_proc k;
        if (!process_info(mib[3], &k)) {
            if (oldlen)
                *oldlen = 0; /* no such process: nothing, and no error */
            return 0;
        }
        return copy_out(&k, sizeof k, old, oldlen);
    }
    if (mib[0] == CTL_KERN && mib[1] == KERN_PROCARGS2) {
        if (len != 3)
            return EINVAL;
        if (mib[2] != getpid())
            return EINVAL; /* only this process's own */
        static unsigned char args[1 << 18];
        size_t n = process_arguments(args, sizeof args);
        return n ? copy_out(args, n, old, oldlen) : ENOMEM;
    }
    const struct entry *e = by_mib(mib, len);
    if (!e)
        return ENOENT;
    if (!e->get)
        return EISDIR;
    if (new)
        return EPERM;
    return read_value(e, old, oldlen);
}

static int mac_sysctl(int *mib, unsigned len, void *old, size_t *oldlen, void *new, size_t newlen)
{
    int rc = do_sysctl(mib, len, old, oldlen, new, newlen);
    if (rc) {
        errno = rc;
        return -1;
    }
    return 0;
}

static int mac_sysctlbyname(const char *name, void *old, size_t *oldlen, void *new, size_t newlen)
{
    const struct entry *e = by_name(name);
    if (!e) {
        errno = ENOENT;
        return -1;
    }
    return mac_sysctl((int *)e->mib, (unsigned)e->depth, old, oldlen, new, newlen);
}

static int mac_sysctlnametomib(const char *name, int *mib, size_t *count)
{
    const struct entry *e = by_name(name);
    if (!e) {
        errno = ENOENT;
        return -1;
    }
    if (!count) {
        errno = EINVAL;
        return -1;
    }
    if (*count < (size_t)e->depth) {
        errno = ENOMEM;
        return -1;
    }
    if (mib)
        memcpy(mib, e->mib, (size_t)e->depth * sizeof(int));
    *count = (size_t)e->depth;
    return 0;
}

/* ---- libproc ---------------------------------------------------------------------- */

#define PROC_PIDPATHINFO_SIZE 1024 /* MAXPATHLEN */

/* The program a process runs, with links resolved. This one's is the Mac
 * program, not Ferry. */
static int mac_proc_pidpath(int pid, void *buffer, uint32_t size)
{
    char path[PATH_MAX];
    if (!buffer || size < PROC_PIDPATHINFO_SIZE) {
        errno = EINVAL;
        return 0;
    }
    if (pid == getpid() && ferry_program_path()[0]) {
        if (!realpath(ferry_program_path(), path))
            snprintf(path, sizeof path, "%s", ferry_program_path());
    } else {
        char link[64];
        snprintf(link, sizeof link, "/proc/%d/exe", pid);
        ssize_t n = readlink(link, path, sizeof path - 1);
        if (n < 0) {
            if (errno == ENOENT)
                errno = ESRCH;
            return 0;
        }
        path[n] = 0;
    }
    size_t len = strlen(path);
    if (len >= size) {
        errno = ENOMEM;
        return 0;
    }
    memcpy(buffer, path, len + 1);
    return (int)len;
}

/* A process's name, as Activity Monitor shows it. */
static int mac_proc_name(int pid, void *buffer, uint32_t size)
{
    char name[64];
    if (!buffer || !size) {
        errno = EINVAL;
        return 0;
    }
    if (pid == getpid() && ferry_program_path()[0]) {
        const char *slash = strrchr(ferry_program_path(), '/');
        snprintf(name, sizeof name, "%.32s", slash ? slash + 1 : ferry_program_path());
    } else {
        char path[64];
        snprintf(path, sizeof path, "/proc/%d/comm", pid);
        if (read_text(path, name, sizeof name) <= 0) {
            errno = ESRCH;
            return 0;
        }
        name[strcspn(name, "\n")] = 0;
    }
    snprintf(buffer, size, "%s", name);
    return (int)strlen(buffer);
}

/* ---- Mach: memory and processor figures ------------------------------------------------
 * Programs ask for the memory figures through the host port and their own
 * task port. Ferry hands out fixed numbers for those ports; only the
 * calls below accept them. Linux's /proc/meminfo answers: free, active and
 * inactive pages as Linux counts them, wired as the kernel's own memory
 * and memory that can't be paged out, file-backed and anonymous pages as
 * external and internal. */

typedef uint32_t mac_port_t;
#define MAC_HOST_PORT 0x203u
#define MAC_TASK_PORT 0x103u
#define KERN_SUCCESS 0
#define KERN_INVALID_ARGUMENT 4
#define KERN_FAILURE 5
#define HOST_BASIC_INFO 1
#define HOST_VM_INFO 2
#define HOST_CPU_LOAD_INFO 3
#define HOST_VM_INFO64 4
#define MACH_TASK_BASIC_INFO 20

static mac_port_t mach_task_self_ = MAC_TASK_PORT;

static mac_port_t mac_mach_host_self(void) { return MAC_HOST_PORT; }
static mac_port_t mac_mach_task_self(void) { return MAC_TASK_PORT; }
static int mac_mach_port_deallocate(mac_port_t task, mac_port_t name) { return KERN_SUCCESS; }

static int mac_host_page_size(mac_port_t host, uintptr_t *size)
{
    if (host != MAC_HOST_PORT || !size)
        return KERN_INVALID_ARGUMENT;
    *size = (uintptr_t)sysconf(_SC_PAGESIZE);
    return KERN_SUCCESS;
}

struct meminfo { unsigned long long total, free, active, inactive, active_file, inactive_file, active_anon,
                 inactive_anon, unevictable, kernel_stack, page_tables, sunreclaim; };

static void read_meminfo(struct meminfo *m)
{
    memset(m, 0, sizeof *m);
    char text[8192];
    if (read_text("/proc/meminfo", text, sizeof text) <= 0)
        return;
    static const struct { const char *key; size_t off; } keys[] = {
        {"MemTotal:", offsetof(struct meminfo, total)},
        {"MemFree:", offsetof(struct meminfo, free)},
        {"Active:", offsetof(struct meminfo, active)},
        {"Inactive:", offsetof(struct meminfo, inactive)},
        {"Active(file):", offsetof(struct meminfo, active_file)},
        {"Inactive(file):", offsetof(struct meminfo, inactive_file)},
        {"Active(anon):", offsetof(struct meminfo, active_anon)},
        {"Inactive(anon):", offsetof(struct meminfo, inactive_anon)},
        {"Unevictable:", offsetof(struct meminfo, unevictable)},
        {"KernelStack:", offsetof(struct meminfo, kernel_stack)},
        {"PageTables:", offsetof(struct meminfo, page_tables)},
        {"SUnreclaim:", offsetof(struct meminfo, sunreclaim)},
    };
    for (char *line = text; line && *line;) {
        for (size_t k = 0; k < sizeof keys / sizeof keys[0]; k++)
            if (!strncmp(line, keys[k].key, strlen(keys[k].key)))
                *(unsigned long long *)((char *)m + keys[k].off) = strtoull(line + strlen(keys[k].key), NULL, 10);
        line = strchr(line, '\n');
        if (line)
            line++;
    }
}

static unsigned long long vmstat(const char *key)
{
    char text[16384];
    if (read_text("/proc/vmstat", text, sizeof text) <= 0)
        return 0;
    size_t n = strlen(key);
    for (char *line = text; line && *line;) {
        if (!strncmp(line, key, n) && line[n] == ' ')
            return strtoull(line + n + 1, NULL, 10);
        line = strchr(line, '\n');
        if (line)
            line++;
    }
    return 0;
}

struct mac_vm_statistics64 {
    uint32_t free_count, active_count, inactive_count, wire_count;
    uint64_t zero_fill_count, reactivations, pageins, pageouts, faults, cow_faults, lookups, hits, purges;
    uint32_t purgeable_count, speculative_count;
    uint64_t decompressions, compressions, swapins, swapouts;
    uint32_t compressor_page_count, throttled_count, external_page_count, internal_page_count;
    uint64_t total_uncompressed_pages_in_compressor;
} __attribute__((aligned(8)));
_Static_assert(sizeof(struct mac_vm_statistics64) == 152, "vm_statistics64");

struct mac_vm_statistics {
    uint32_t free_count, active_count, inactive_count, wire_count, zero_fill_count, reactivations, pageins,
        pageouts, faults, cow_faults, lookups, hits, purgeable_count, purges, speculative_count;
};

struct mac_host_basic_info {
    int32_t max_cpus, avail_cpus;
    uint32_t memory_size;
    int32_t cpu_type, cpu_subtype, cpu_threadtype;
    int32_t physical_cpu, physical_cpu_max, logical_cpu, logical_cpu_max;
    uint64_t max_mem;
} __attribute__((packed, aligned(4)));
_Static_assert(sizeof(struct mac_host_basic_info) == 48, "host_basic_info");

static void vm_figures(struct mac_vm_statistics64 *s)
{
    struct meminfo m;
    read_meminfo(&m);
    unsigned long long kb_per_page = (unsigned long long)sysconf(_SC_PAGESIZE) / 1024;
    if (!kb_per_page)
        kb_per_page = 4;
    memset(s, 0, sizeof *s);
    s->free_count = (uint32_t)(m.free / kb_per_page);
    s->active_count = (uint32_t)(m.active / kb_per_page);
    s->inactive_count = (uint32_t)(m.inactive / kb_per_page);
    s->wire_count = (uint32_t)((m.unevictable + m.kernel_stack + m.page_tables + m.sunreclaim) / kb_per_page);
    s->external_page_count = (uint32_t)((m.active_file + m.inactive_file) / kb_per_page);
    s->internal_page_count = (uint32_t)((m.active_anon + m.inactive_anon) / kb_per_page);
    s->faults = vmstat("pgfault");
    s->pageins = vmstat("pgmajfault");
    s->pageouts = vmstat("pswpout");
    s->swapins = vmstat("pswpin");
    s->swapouts = vmstat("pswpout");
}

static int mac_host_statistics64(mac_port_t host, int flavor, int32_t *info, uint32_t *count)
{
    if (host != MAC_HOST_PORT || !info || !count)
        return KERN_INVALID_ARGUMENT;
    if (flavor == HOST_VM_INFO64) {
        uint32_t need = sizeof(struct mac_vm_statistics64) / 4;
        if (*count < need)
            return KERN_FAILURE;
        struct mac_vm_statistics64 s;
        vm_figures(&s);
        memcpy(info, &s, sizeof s);
        *count = need;
        return KERN_SUCCESS;
    }
    return KERN_INVALID_ARGUMENT;
}

static int mac_host_statistics(mac_port_t host, int flavor, int32_t *info, uint32_t *count)
{
    if (host != MAC_HOST_PORT || !info || !count)
        return KERN_INVALID_ARGUMENT;
    if (flavor == HOST_VM_INFO) {
        uint32_t need = sizeof(struct mac_vm_statistics) / 4;
        if (*count < need)
            return KERN_FAILURE;
        struct mac_vm_statistics64 s;
        vm_figures(&s);
        struct mac_vm_statistics o = {s.free_count, s.active_count, s.inactive_count, s.wire_count,
                                      (uint32_t)s.zero_fill_count, (uint32_t)s.reactivations, (uint32_t)s.pageins,
                                      (uint32_t)s.pageouts, (uint32_t)s.faults, (uint32_t)s.cow_faults,
                                      (uint32_t)s.lookups, (uint32_t)s.hits, s.purgeable_count, (uint32_t)s.purges,
                                      s.speculative_count};
        memcpy(info, &o, sizeof o);
        *count = need;
        return KERN_SUCCESS;
    }
    if (flavor == HOST_CPU_LOAD_INFO) {
        /* user, system, idle and nice ticks of all processors together */
        if (*count < 4)
            return KERN_FAILURE;
        char text[512];
        unsigned long long user = 0, nice = 0, sys = 0, idle = 0;
        if (read_text("/proc/stat", text, sizeof text) > 0)
            sscanf(text, "cpu %llu %llu %llu %llu", &user, &nice, &sys, &idle);
        uint32_t ticks[4] = {(uint32_t)user, (uint32_t)sys, (uint32_t)idle, (uint32_t)nice};
        memcpy(info, ticks, sizeof ticks);
        *count = 4;
        return KERN_SUCCESS;
    }
    if (flavor == HOST_VM_INFO64)
        return mac_host_statistics64(host, flavor, info, count);
    return KERN_INVALID_ARGUMENT;
}

static int mac_host_info(mac_port_t host, int flavor, int32_t *info, uint32_t *count)
{
    if (host != MAC_HOST_PORT || !info || !count || flavor != HOST_BASIC_INFO)
        return KERN_INVALID_ARGUMENT;
    uint32_t need = sizeof(struct mac_host_basic_info) / 4;
    if (*count < need)
        return KERN_FAILURE;
    int64_t mem = memory_size();
    struct mac_host_basic_info b = {
        (int32_t)logical_configured(), (int32_t)logical_online(), (uint32_t)(mem > UINT32_MAX ? 0x80000000u : mem),
        0x01000007 /* CPU_TYPE_X86_64 */, 8 /* CPU_SUBTYPE_X86_64_H */, 0, (int32_t)physical_cores(),
        (int32_t)physical_cores(), (int32_t)logical_online(), (int32_t)logical_configured(), (uint64_t)mem};
    memcpy(info, &b, sizeof b);
    *count = need;
    return KERN_SUCCESS;
}

/* MACH_TASK_BASIC_INFO for the program's own task: its size, how much is
 * in memory (now and at most), and the processor time it has used. */
struct mac_task_basic_info {
    uint64_t virtual_size, resident_size, resident_size_max;
    int32_t user_seconds, user_microseconds, system_seconds, system_microseconds;
    int32_t policy, suspend_count;
} __attribute__((packed, aligned(4)));
_Static_assert(sizeof(struct mac_task_basic_info) == 48, "mach_task_basic_info");

static int mac_task_info(mac_port_t task, int flavor, int32_t *info, uint32_t *count)
{
    if (task != MAC_TASK_PORT || !info || !count || flavor != MACH_TASK_BASIC_INFO)
        return KERN_INVALID_ARGUMENT;
    uint32_t need = sizeof(struct mac_task_basic_info) / 4;
    if (*count < need)
        return KERN_FAILURE;
    struct mac_task_basic_info t;
    memset(&t, 0, sizeof t);
    char text[256];
    unsigned long long pages = 0, resident = 0;
    if (read_text("/proc/self/statm", text, sizeof text) > 0)
        sscanf(text, "%llu %llu", &pages, &resident);
    long page = sysconf(_SC_PAGESIZE);
    t.virtual_size = pages * (unsigned long long)page;
    t.resident_size = resident * (unsigned long long)page;
    struct rusage r;
    if (getrusage(RUSAGE_SELF, &r) == 0) {
        t.resident_size_max = (uint64_t)r.ru_maxrss * 1024;
        t.user_seconds = (int32_t)r.ru_utime.tv_sec;
        t.user_microseconds = (int32_t)r.ru_utime.tv_usec;
        t.system_seconds = (int32_t)r.ru_stime.tv_sec;
        t.system_microseconds = (int32_t)r.ru_stime.tv_usec;
    }
    if (t.resident_size_max < t.resident_size)
        t.resident_size_max = t.resident_size;
    memcpy(info, &t, sizeof t);
    *count = need;
    return KERN_SUCCESS;
}


/* ---- Mach semaphores (freemac 1.232, Ferry 0.56.0) -------------------------------
 * semaphore_create and its calls, from the Mach reference pages. A
 * semaphore's name is a port number, so each is kept in a table and named
 * 0x10000 plus its place there. semaphore_timedwait's time is how long to
 * wait, not a time of day. */
#define MAC_KERN_NO_SPACE 3
#define MAC_KERN_INVALID_ARGUMENT 4
#define MAC_KERN_RESOURCE_SHORTAGE 6
#define MAC_KERN_OPERATION_TIMED_OUT 49
#define SEM_BASE 0x10000u

struct mach_sem {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    long count;
    unsigned long wake_all; /* bumped by semaphore_signal_all */
    long waiters;
};

static pthread_mutex_t sem_table_lock = PTHREAD_MUTEX_INITIALIZER;
static struct mach_sem **sem_table;
static size_t sem_table_size;

static struct mach_sem *sem_find(mac_port_t name)
{
    struct mach_sem *s = NULL;
    pthread_mutex_lock(&sem_table_lock);
    if (name >= SEM_BASE && name - SEM_BASE < sem_table_size)
        s = sem_table[name - SEM_BASE];
    pthread_mutex_unlock(&sem_table_lock);
    return s;
}

static int mac_semaphore_create(mac_port_t task, mac_port_t *out, int policy, int value)
{
    (void)task;
    (void)policy;
    if (!out || value < 0)
        return MAC_KERN_INVALID_ARGUMENT;
    struct mach_sem *s = calloc(1, sizeof *s);
    if (!s)
        return MAC_KERN_RESOURCE_SHORTAGE;
    pthread_mutex_init(&s->lock, NULL);
    pthread_condattr_t ca;
    pthread_condattr_init(&ca);
    pthread_condattr_setclock(&ca, CLOCK_MONOTONIC);
    pthread_cond_init(&s->cond, &ca);
    pthread_condattr_destroy(&ca);
    s->count = value;
    pthread_mutex_lock(&sem_table_lock);
    size_t i = 0;
    while (i < sem_table_size && sem_table[i])
        i++;
    if (i == sem_table_size) {
        size_t n = sem_table_size ? sem_table_size * 2 : 64;
        struct mach_sem **t = n < 0xffff0000u ? realloc(sem_table, n * sizeof *t) : NULL;
        if (!t) {
            pthread_mutex_unlock(&sem_table_lock);
            free(s);
            return MAC_KERN_NO_SPACE;
        }
        memset(t + sem_table_size, 0, (n - sem_table_size) * sizeof *t);
        sem_table = t;
        sem_table_size = n;
    }
    sem_table[i] = s;
    pthread_mutex_unlock(&sem_table_lock);
    *out = SEM_BASE + (mac_port_t)i;
    return 0;
}

static int mac_semaphore_destroy(mac_port_t task, mac_port_t name)
{
    (void)task;
    struct mach_sem *s = NULL;
    pthread_mutex_lock(&sem_table_lock);
    if (name >= SEM_BASE && name - SEM_BASE < sem_table_size) {
        s = sem_table[name - SEM_BASE];
        sem_table[name - SEM_BASE] = NULL;
    }
    pthread_mutex_unlock(&sem_table_lock);
    if (!s)
        return MAC_KERN_INVALID_ARGUMENT;
    pthread_cond_destroy(&s->cond);
    pthread_mutex_destroy(&s->lock);
    free(s);
    return 0;
}

static int mac_semaphore_signal(mac_port_t name)
{
    struct mach_sem *s = sem_find(name);
    if (!s)
        return MAC_KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&s->lock);
    s->count++;
    pthread_cond_signal(&s->cond);
    pthread_mutex_unlock(&s->lock);
    return 0;
}

/* Wakes every thread waiting now; the count doesn't grow when none waits. */
static int mac_semaphore_signal_all(mac_port_t name)
{
    struct mach_sem *s = sem_find(name);
    if (!s)
        return MAC_KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&s->lock);
    if (s->waiters) {
        s->wake_all++;
        pthread_cond_broadcast(&s->cond);
    }
    pthread_mutex_unlock(&s->lock);
    return 0;
}

static int sem_wait_until(mac_port_t name, const struct timespec *deadline)
{
    struct mach_sem *s = sem_find(name);
    if (!s)
        return MAC_KERN_INVALID_ARGUMENT;
    int r = 0;
    pthread_mutex_lock(&s->lock);
    unsigned long round = s->wake_all;
    s->waiters++;
    while (s->count == 0 && s->wake_all == round) {
        int e = deadline ? pthread_cond_timedwait(&s->cond, &s->lock, deadline) : pthread_cond_wait(&s->cond, &s->lock);
        if (e == ETIMEDOUT) {
            r = MAC_KERN_OPERATION_TIMED_OUT;
            break;
        }
    }
    if (!r && s->wake_all == round)
        s->count--;
    s->waiters--;
    pthread_mutex_unlock(&s->lock);
    return r;
}

static int mac_semaphore_wait(mac_port_t name) { return sem_wait_until(name, NULL); }

struct mac_mach_timespec {
    unsigned int tv_sec;
    int tv_nsec;
};

static int mac_semaphore_timedwait(mac_port_t name, struct mac_mach_timespec wait)
{
    if (wait.tv_nsec < 0 || wait.tv_nsec >= 1000000000)
        return MAC_KERN_INVALID_ARGUMENT;
    struct timespec d;
    clock_gettime(CLOCK_MONOTONIC, &d);
    d.tv_sec += wait.tv_sec;
    d.tv_nsec += wait.tv_nsec;
    if (d.tv_nsec >= 1000000000) {
        d.tv_sec++;
        d.tv_nsec -= 1000000000;
    }
    return sem_wait_until(name, &d);
}

/* ---- the task's own memory: vm_allocate, vm_deallocate, vm_remap ----------------- */
#define MAC_VM_PROT_READ 1
#define MAC_VM_PROT_WRITE 2
#define MAC_VM_PROT_EXECUTE 4
#define MAC_VM_FLAGS_ANYWHERE 1

static int mac_vm_allocate(mac_port_t task, uintptr_t *addr, uintptr_t size, int flags)
{
    if (task != MAC_TASK_PORT || !addr)
        return MAC_KERN_INVALID_ARGUMENT;
    void *want = (flags & MAC_VM_FLAGS_ANYWHERE) ? NULL : (void *)*addr;
    void *p = mmap(want, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | (want ? MAP_FIXED_NOREPLACE : 0),
                   -1, 0);
    if (p == MAP_FAILED)
        return MAC_KERN_NO_SPACE;
    *addr = (uintptr_t)p;
    return 0;
}

static int mac_vm_deallocate(mac_port_t task, uintptr_t addr, uintptr_t size)
{
    if (task != MAC_TASK_PORT)
        return MAC_KERN_INVALID_ARGUMENT;
    if (size)
        munmap((void *)(addr & ~(uintptr_t)(getpagesize() - 1)), size + (addr & (uintptr_t)(getpagesize() - 1)));
    return 0;
}

/* Only a copy, into fresh memory anywhere: the new pages hold what the old
 * ones held and may be read and written. */
static int mac_vm_remap(mac_port_t task, uintptr_t *addr, uintptr_t size, uintptr_t mask, int flags,
                        mac_port_t src_task, uintptr_t src, unsigned int copy, int *cur, int *max,
                        unsigned int inherit)
{
    (void)mask;
    (void)inherit;
    if (task != MAC_TASK_PORT || src_task != MAC_TASK_PORT || !addr || !copy || !(flags & MAC_VM_FLAGS_ANYWHERE))
        return MAC_KERN_INVALID_ARGUMENT;
    uintptr_t page = (uintptr_t)getpagesize();
    uintptr_t start = src & ~(page - 1), len = ((src + size + page - 1) & ~(page - 1)) - start;
    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return MAC_KERN_NO_SPACE;
    memcpy(p, (void *)start, len);
    *addr = (uintptr_t)p + (src - start);
    if (cur)
        *cur = MAC_VM_PROT_READ | MAC_VM_PROT_WRITE;
    if (max)
        *max = MAC_VM_PROT_READ | MAC_VM_PROT_WRITE | MAC_VM_PROT_EXECUTE;
    return 0;
}

/* ---- waiting on an address: __ulock_wait, __ulock_wait2, __ulock_wake ---------- */
/* The Darwin kernel's address waits, as its published sys/ulock.h (part of
 * the open-source xnu) describes them: Qt's QMutex and QSemaphore wait this
 * way on a Mac. A wait sleeps while the 32- or 64-bit word at addr still
 * holds value; a wake rouses one waiter, or all with ULF_WAKE_ALL. Here
 * each is a Linux futex on the word (for a 64-bit word, on its low half,
 * after checking the whole word, which callers loop around anyway). With
 * ULF_NO_ERRNO an error comes back as minus a Mac errno, otherwise as -1
 * with errno set. Only waits within one process are served. */
#define MAC_UL_COMPARE_AND_WAIT 1
#define MAC_UL_UNFAIR_LOCK 2
#define MAC_UL_COMPARE_AND_WAIT_SHARED 3
#define MAC_UL_COMPARE_AND_WAIT64 5
#define MAC_UL_COMPARE_AND_WAIT64_SHARED 6
#define MAC_ULF_WAKE_ALL 0x100
#define MAC_ULF_NO_ERRNO 0x01000000

static int ulock_fail(uint32_t op, int err)
{
    if (op & MAC_ULF_NO_ERRNO)
        return -ferry_errno_to_mac(err);
    errno = err;
    return -1;
}

static int ulock_is_64(uint32_t op)
{
    uint32_t kind = op & 0xff;
    return kind == MAC_UL_COMPARE_AND_WAIT64 || kind == MAC_UL_COMPARE_AND_WAIT64_SHARED;
}

static int mac_ulock_wait2(uint32_t op, void *addr, uint64_t value, uint64_t timeout_ns, uint64_t value2)
{
    (void)value2;
    uint32_t kind = op & 0xff;
    if (!addr || ((uintptr_t)addr & 3) || kind == 0 || kind > MAC_UL_COMPARE_AND_WAIT64_SHARED)
        return ulock_fail(op, EINVAL);
    uint32_t low = (uint32_t)value;
    if (ulock_is_64(op)) {
        if (__atomic_load_n((uint64_t *)addr, __ATOMIC_SEQ_CST) != value)
            return 0;
    } else if (__atomic_load_n((uint32_t *)addr, __ATOMIC_SEQ_CST) != low)
        return 0;
    struct timespec ts, *tp = NULL;
    if (timeout_ns) {
        ts.tv_sec = (time_t)(timeout_ns / 1000000000u);
        ts.tv_nsec = (long)(timeout_ns % 1000000000u);
        tp = &ts;
    }
    long r = syscall(SYS_futex, (uint32_t *)addr, FUTEX_WAIT_PRIVATE, low, tp, NULL, 0);
    if (r == 0 || errno == EAGAIN)
        return 0;
    return ulock_fail(op, errno);
}

static int mac_ulock_wait(uint32_t op, void *addr, uint64_t value, uint32_t timeout_us)
{
    return mac_ulock_wait2(op, addr, value, (uint64_t)timeout_us * 1000u, 0);
}

static int mac_ulock_wake(uint32_t op, void *addr, uint64_t wake_value)
{
    (void)wake_value;
    if (!addr || ((uintptr_t)addr & 3))
        return ulock_fail(op, EINVAL);
    int n = (op & MAC_ULF_WAKE_ALL) ? INT_MAX : 1;
    long r = syscall(SYS_futex, (uint32_t *)addr, FUTEX_WAKE_PRIVATE, n, NULL, NULL, 0);
    if (r < 0)
        return ulock_fail(op, errno);
    /* no one was waiting: the kernel's answer is ENOENT */
    return r == 0 ? ulock_fail(op, ENOENT) : 0;
}

/* System Integrity Protection's settings: none are on under Ferry. */
static int mac_csr_get_active_config(uint32_t *config)
{
    if (config)
        *config = 0;
    return 0;
}

static int mac_csr_check(uint32_t mask)
{
    (void)mask;
    return 0;
}

const struct ferry_symbol ferry_sysctl_symbols[] = {
    {"__ulock_wait", mac_ulock_wait},
    {"__ulock_wait2", mac_ulock_wait2},
    {"__ulock_wake", mac_ulock_wake},
    {"csr_get_active_config", mac_csr_get_active_config},
    {"csr_check", mac_csr_check},
    {"semaphore_create", mac_semaphore_create},
    {"semaphore_destroy", mac_semaphore_destroy},
    {"semaphore_signal", mac_semaphore_signal},
    {"semaphore_signal_all", mac_semaphore_signal_all},
    {"semaphore_wait", mac_semaphore_wait},
    {"semaphore_timedwait", mac_semaphore_timedwait},
    {"vm_allocate", mac_vm_allocate},
    {"vm_deallocate", mac_vm_deallocate},
    {"vm_remap", mac_vm_remap},
    {"sysctl", mac_sysctl},
    {"sysctlbyname", mac_sysctlbyname},
    {"sysctlnametomib", mac_sysctlnametomib},
    {"proc_pidpath", mac_proc_pidpath},
    {"proc_name", mac_proc_name},
    {"mach_host_self", mac_mach_host_self},
    {"mach_task_self", mac_mach_task_self},
    {"mach_task_self_", &mach_task_self_},
    {"mach_port_deallocate", mac_mach_port_deallocate},
    {"host_page_size", mac_host_page_size},
    {"host_statistics", mac_host_statistics},
    {"host_statistics64", mac_host_statistics64},
    {"host_info", mac_host_info},
    {"task_info", mac_task_info},
    {NULL, NULL},
};
