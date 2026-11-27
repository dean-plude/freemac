/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libSystem calls that Electron apps (Chromium and Node.js built for a Mac)
 * make at start, from Apple's public documentation and man pages of each
 * (freemac 1.265, Ferry 0.88.0; first seen in Obsidian):
 *
 * - The app sandbox (sandbox_check, sandbox_init and its parameters,
 *   sandbox extensions): a Ferry program is never sandboxed this way, so
 *   a check says it isn't, and asking to sandbox a process is refused, as
 *   Chromium's own sandbox expects when the system has none (it then runs
 *   without one, as it does when started with --no-sandbox).
 * - Threads by their Mach port, which here is the thread's id: thread_info
 *   (basic and identifier information, from /proc), thread_switch (a
 *   yield). Suspending another thread, or reading its registers, isn't
 *   possible from inside a Linux process, so those calls fail cleanly
 *   (Chromium's stack sampler then does nothing).
 * - The task: task_self_trap, pid_for_task, task_policy (accepted, with no
 *   effect), task_threads (the threads Ferry knows of).
 * - The processors' load (host_processor_info), from /proc/stat.
 * - Signposts (os_signpost) are off: nothing records them.
 * - Code signing status (csops): unsigned, valid, as an app runs here.
 * - Guarded file descriptors (guarded_close_np, change_fdguard_np): the
 *   descriptor without its guard.
 * - abort_report_np,
 *   __atomic_load and its kin for sizes the compiler doesn't inline,
 *   posix_spawnattr_set_csm_np, NDR_record (MIG's data representation),
 *   and mach_vm_region_recurse (no submaps; ends the walk).
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"

#define KERN_SUCCESS 0
#define KERN_INVALID_ADDRESS 1
#define KERN_INVALID_ARGUMENT 4
#define KERN_FAILURE 5
#define KERN_RESOURCE_SHORTAGE 6
#define KERN_NOT_SUPPORTED 46
#define MAC_TASK_PORT 0x103u

/* ---- the sandbox --------------------------------------------------------------------- */

static int mac_sandbox_check(int pid, const char *operation, int type, ...)
{
    (void)pid;
    (void)type;
    /* with no operation, "is the process sandboxed": no. Any operation is allowed. */
    (void)operation;
    return 0;
}

static int mac_sandbox_init(const char *profile, uint64_t flags, char **error)
{
    (void)profile;
    (void)flags;
    if (error)
        *error = strdup("the app sandbox isn't available on this system");
    errno = ENOSYS;
    return -1;
}

static int mac_sandbox_init_with_parameters(const char *profile, uint64_t flags, const char *const params[],
                                            char **error)
{
    (void)params;
    return mac_sandbox_init(profile, flags, error);
}

static void mac_sandbox_free_error(char *error) { free(error); }

/* parameters are kept so that they can be freed; nothing reads them */
struct sandbox_params { int unused; };
static void *mac_sandbox_create_params(void) { return calloc(1, sizeof(struct sandbox_params)); }
static int mac_sandbox_set_param(void *params, const char *key, const char *value)
{
    (void)key;
    (void)value;
    return params ? 0 : -1;
}
static void mac_sandbox_free_params(void *params) { free(params); }

static void *mac_sandbox_compile_string(const char *profile, void *params, char **error)
{
    (void)profile;
    (void)params;
    if (error)
        *error = strdup("the app sandbox isn't available on this system");
    return NULL;
}
static void *mac_sandbox_compile_file(const char *path, void *params, char **error)
{
    return mac_sandbox_compile_string(path, params, error);
}
static void mac_sandbox_free_profile(void *profile) { (void)profile; }
static int mac_sandbox_apply(void *profile) { (void)profile; errno = ENOSYS; return -1; }

/* An extension grants a sandboxed process a file; with no sandbox there is
 * nothing to grant, and a token for it is refused. */
static char *mac_sandbox_extension_issue_file(const char *class_, const char *path, uint32_t flags, ...)
{
    (void)class_;
    (void)path;
    (void)flags;
    return NULL;
}
static int64_t mac_sandbox_extension_consume(const char *token)
{
    (void)token;
    errno = ENOSYS;
    return -1;
}
static int mac_sandbox_extension_release(int64_t handle) { (void)handle; return 0; }

static int mac___sandbox_ms(const char *policy, int call, void *arg)
{
    (void)policy;
    (void)call;
    (void)arg;
    errno = ENOSYS;
    return -1;
}

/* ---- threads and the task ------------------------------------------------------------ */

static unsigned mac_task_self_trap(void) { return MAC_TASK_PORT; }

static int mac_pid_for_task(unsigned task, int *pid)
{
    if (task != MAC_TASK_PORT || !pid)
        return KERN_FAILURE;
    *pid = getpid();
    return KERN_SUCCESS;
}

static int mac_task_policy_set(unsigned task, int flavor, int *info, unsigned count)
{
    (void)flavor;
    (void)info;
    (void)count;
    return task == MAC_TASK_PORT ? KERN_SUCCESS : KERN_INVALID_ARGUMENT;
}

static int mac_task_policy_get(unsigned task, int flavor, int *info, unsigned *count, int *get_default)
{
    (void)flavor;
    if (task != MAC_TASK_PORT || !count)
        return KERN_INVALID_ARGUMENT;
    if (info)
        memset(info, 0, *count * sizeof *info);
    if (get_default)
        *get_default = 1;
    return KERN_SUCCESS;
}

/* The process's threads, by their ids (their Mach ports here), in memory
 * the caller gives back with vm_deallocate. */
static int mac_task_threads(unsigned task, unsigned **list, unsigned *count)
{
    if (task != MAC_TASK_PORT || !list || !count)
        return KERN_INVALID_ARGUMENT;
    DIR *d = opendir("/proc/self/task");
    if (!d)
        return KERN_FAILURE;
    unsigned n = 0, cap = 256;
    unsigned *ids = mmap(NULL, cap * sizeof *ids, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (ids == MAP_FAILED) {
        closedir(d);
        return KERN_RESOURCE_SHORTAGE;
    }
    for (struct dirent *e; (e = readdir(d)) && n < cap;)
        if (e->d_name[0] >= '0' && e->d_name[0] <= '9')
            ids[n++] = (unsigned)atoi(e->d_name);
    closedir(d);
    *list = ids;
    *count = n;
    return KERN_SUCCESS;
}

#define MAC_THREAD_BASIC_INFO 3
#define MAC_THREAD_IDENTIFIER_INFO 4
#define MAC_TH_STATE_RUNNING 1
#define MAC_TH_STATE_WAITING 3

/* user and system time, and whether it runs, from /proc */
static int thread_stat(unsigned tid, char *state, unsigned long *utime, unsigned long *stime)
{
    char path[64], buf[1024];
    snprintf(path, sizeof path, "/proc/self/task/%u/stat", tid);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0)
        return -1;
    buf[n] = 0;
    char *p = strrchr(buf, ')');
    if (!p || sscanf(p + 2, "%c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %lu %lu", state, utime, stime) != 3)
        return -1;
    return 0;
}

static int mac_thread_info(unsigned thread, int flavor, int32_t *info, uint32_t *count)
{
    if (!info || !count)
        return KERN_INVALID_ARGUMENT;
    if (flavor == MAC_THREAD_BASIC_INFO) {
        if (*count < 10)
            return KERN_INVALID_ARGUMENT;
        char state;
        unsigned long ut, st;
        if (thread_stat(thread, &state, &ut, &st) < 0)
            return KERN_INVALID_ARGUMENT;
        long hz = sysconf(_SC_CLK_TCK);
        if (hz <= 0)
            hz = 100;
        memset(info, 0, 10 * sizeof *info);
        info[0] = (int32_t)(ut / hz);
        info[1] = (int32_t)(ut % hz * 1000000 / hz);
        info[2] = (int32_t)(st / hz);
        info[3] = (int32_t)(st % hz * 1000000 / hz);
        info[4] = 0; /* cpu_usage */
        info[5] = 1; /* POLICY_TIMESHARE */
        info[6] = state == 'R' ? MAC_TH_STATE_RUNNING : MAC_TH_STATE_WAITING;
        *count = 10;
        return KERN_SUCCESS;
    }
    if (flavor == MAC_THREAD_IDENTIFIER_INFO) {
        if (*count < 6)
            return KERN_INVALID_ARGUMENT;
        uint64_t v[3] = {thread, thread, 0};
        memcpy(info, v, sizeof v);
        *count = 6;
        return KERN_SUCCESS;
    }
    return KERN_INVALID_ARGUMENT;
}

static int mac_thread_switch(unsigned thread, int option, unsigned ms)
{
    (void)thread;
    if (option == 2 /* SWITCH_OPTION_WAIT */ && ms)
        usleep(ms * 1000);
    else
        sched_yield();
    return KERN_SUCCESS;
}

/* A Linux process can't stop one of its own threads from outside it, nor
 * read a running thread's registers. */
static int mac_thread_suspend(unsigned thread) { (void)thread; return KERN_NOT_SUPPORTED; }
static int mac_thread_resume(unsigned thread) { (void)thread; return KERN_NOT_SUPPORTED; }
static int mac_thread_get_state(unsigned thread, int flavor, void *state, unsigned *count)
{
    (void)thread;
    (void)flavor;
    (void)state;
    (void)count;
    return KERN_NOT_SUPPORTED;
}

/* The frame pointer chain: the caller's frame and its return address. */
static uintptr_t mac_pthread_stack_frame_decode_np(uintptr_t frame, uintptr_t *ret)
{
    uintptr_t *f = (uintptr_t *)frame;
    if (ret)
        *ret = f[1];
    return f[0];
}

/* ---- the processors ------------------------------------------------------------------ */

#define MAC_PROCESSOR_CPU_LOAD_INFO 2

/* Each processor's ticks in user, system, idle and nice time. */
static int mac_host_processor_info(unsigned host, int flavor, unsigned *ncpu, uint32_t **info, uint32_t *count)
{
    (void)host;
    if (flavor != MAC_PROCESSOR_CPU_LOAD_INFO || !ncpu || !info || !count)
        return KERN_INVALID_ARGUMENT;
    FILE *f = fopen("/proc/stat", "re");
    if (!f)
        return KERN_FAILURE;
    unsigned cap = 1024, n = 0;
    uint32_t *out = mmap(NULL, cap * 4 * sizeof *out, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (out == MAP_FAILED) {
        fclose(f);
        return KERN_RESOURCE_SHORTAGE;
    }
    char line[512];
    while (fgets(line, sizeof line, f) && n < cap) {
        unsigned long long user, nice, sys, idle, iowait = 0;
        if (strncmp(line, "cpu", 3) || line[3] < '0' || line[3] > '9')
            continue;
        if (sscanf(line, "cpu%*u %llu %llu %llu %llu %llu", &user, &nice, &sys, &idle, &iowait) < 4)
            continue;
        out[n * 4 + 0] = (uint32_t)user;
        out[n * 4 + 1] = (uint32_t)sys;
        out[n * 4 + 2] = (uint32_t)(idle + iowait);
        out[n * 4 + 3] = (uint32_t)nice;
        n++;
    }
    fclose(f);
    *ncpu = n;
    *info = out;
    *count = n * 4;
    return KERN_SUCCESS;
}

/* ---- signposts ------------------------------------------------------------------------ */

static int mac_os_signpost_enabled(void *log) { (void)log; return 0; }
static void mac__os_signpost_emit_with_name_impl(void *dso, void *log, int type, uint64_t id, const char *name,
                                                 const char *format, uint8_t *buf, uint32_t size)
{
    (void)dso; (void)log; (void)type; (void)id; (void)name; (void)format; (void)buf; (void)size;
}
static uint64_t mac_os_signpost_id_generate(void *log)
{
    static uint64_t next = 1;
    (void)log;
    return __atomic_add_fetch(&next, 1, __ATOMIC_RELAXED);
}
static uint64_t mac_os_signpost_id_make_with_pointer(void *log, const void *ptr)
{
    (void)log;
    return (uint64_t)(uintptr_t)ptr;
}

/* ---- code signing, file descriptors and the rest ------------------------------------- */

#define MAC_CS_OPS_STATUS 0
#define MAC_CS_VALID 0x1

static int mac_csops(int pid, unsigned ops, void *buf, size_t size)
{
    (void)pid;
    if (buf && size)
        memset(buf, 0, size);
    if (ops == MAC_CS_OPS_STATUS && buf && size >= sizeof(uint32_t)) {
        uint32_t flags = MAC_CS_VALID;
        memcpy(buf, &flags, sizeof flags);
    }
    return 0;
}

static int mac_csops_audittoken(int pid, unsigned ops, void *buf, size_t size, void *token)
{
    (void)token;
    return mac_csops(pid, ops, buf, size);
}

static int mac_guarded_close_np(int fd, const uint64_t *guard)
{
    (void)guard;
    return close(fd);
}

static int mac_change_fdguard_np(int fd, const uint64_t *guard, unsigned flags, const uint64_t *nguard,
                                 unsigned nflags, int *fdflags)
{
    (void)guard; (void)flags; (void)nguard; (void)nflags;
    if (fdflags)
        *fdflags = fcntl(fd, F_GETFD);
    return fcntl(fd, F_GETFD) < 0 ? -1 : 0;
}

static void mac_abort_report_np(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vfprintf(stderr, format, ap);
    va_end(ap);
    fputc('\n', stderr);
    abort();
}

/* Atomic loads and stores of sizes the compiler doesn't do itself, under
 * one lock. */
static pthread_mutex_t atomic_lock = PTHREAD_MUTEX_INITIALIZER;
static void mac___atomic_load(size_t size, const void *src, void *dst, int order)
{
    (void)order;
    pthread_mutex_lock(&atomic_lock);
    memcpy(dst, src, size);
    pthread_mutex_unlock(&atomic_lock);
}
static void mac___atomic_store(size_t size, void *dst, const void *src, int order)
{
    (void)order;
    pthread_mutex_lock(&atomic_lock);
    memcpy(dst, src, size);
    pthread_mutex_unlock(&atomic_lock);
}
static void mac___atomic_exchange(size_t size, void *ptr, const void *val, void *old, int order)
{
    (void)order;
    pthread_mutex_lock(&atomic_lock);
    memcpy(old, ptr, size);
    memcpy(ptr, val, size);
    pthread_mutex_unlock(&atomic_lock);
}
static int mac___atomic_compare_exchange(size_t size, void *ptr, void *expected, const void *desired, int s, int f)
{
    (void)s;
    (void)f;
    pthread_mutex_lock(&atomic_lock);
    int same = !memcmp(ptr, expected, size);
    if (same)
        memcpy(ptr, desired, size);
    else
        memcpy(expected, ptr, size);
    pthread_mutex_unlock(&atomic_lock);
    return same;
}

static int mac_posix_spawnattr_set_csm_np(void *attr, uint32_t flags)
{
    (void)attr;
    (void)flags;
    return 0;
}

/* MIG's data representation record: integers little-endian, characters
 * ASCII, floating point IEEE. */
static const uint8_t mac_NDR_record[8] = {0, 0, 0, 0, 1, 0, 0, 0};

/* No memory region holds a submap here, so walking them recursively ends
 * where a plain walk would (mach_vm_region in sysctl.c lists them). */
static int mac_mach_vm_region_recurse(unsigned task, uint64_t *addr, uint64_t *size, uint32_t *depth, int32_t *info,
                                      uint32_t *count)
{
    (void)task; (void)addr; (void)size; (void)depth; (void)info; (void)count;
    return KERN_INVALID_ADDRESS;
}

const struct ferry_symbol ferry_libc_electron_symbols[] = {
    {"sandbox_check", mac_sandbox_check},
    {"sandbox_check_by_audit_token", mac_sandbox_check},
    {"sandbox_init", mac_sandbox_init},
    {"sandbox_init_with_parameters", mac_sandbox_init_with_parameters},
    {"sandbox_free_error", mac_sandbox_free_error},
    {"sandbox_create_params", mac_sandbox_create_params},
    {"sandbox_set_param", mac_sandbox_set_param},
    {"sandbox_free_params", mac_sandbox_free_params},
    {"sandbox_compile_string", mac_sandbox_compile_string},
    {"sandbox_compile_file", mac_sandbox_compile_file},
    {"sandbox_free_profile", mac_sandbox_free_profile},
    {"sandbox_apply", mac_sandbox_apply},
    {"sandbox_extension_issue_file", mac_sandbox_extension_issue_file},
    {"sandbox_extension_consume", mac_sandbox_extension_consume},
    {"sandbox_extension_release", mac_sandbox_extension_release},
    {"__sandbox_ms", mac___sandbox_ms},
    {"task_self_trap", mac_task_self_trap},
    {"pid_for_task", mac_pid_for_task},
    {"task_policy_set", mac_task_policy_set},
    {"task_policy_get", mac_task_policy_get},
    {"task_threads", mac_task_threads},
    {"thread_info", mac_thread_info},
    {"thread_switch", mac_thread_switch},
    {"thread_suspend", mac_thread_suspend},
    {"thread_resume", mac_thread_resume},
    {"thread_get_state", mac_thread_get_state},
    {"pthread_stack_frame_decode_np", mac_pthread_stack_frame_decode_np},
    {"host_processor_info", mac_host_processor_info},
    {"os_signpost_enabled", mac_os_signpost_enabled},
    {"_os_signpost_emit_with_name_impl", mac__os_signpost_emit_with_name_impl},
    {"os_signpost_id_generate", mac_os_signpost_id_generate},
    {"os_signpost_id_make_with_pointer", mac_os_signpost_id_make_with_pointer},
    {"csops", mac_csops},
    {"csops_audittoken", mac_csops_audittoken},
    {"guarded_close_np", mac_guarded_close_np},
    {"change_fdguard_np", mac_change_fdguard_np},
    {"abort_report_np", mac_abort_report_np},
    {"__atomic_load", mac___atomic_load},
    {"__atomic_store", mac___atomic_store},
    {"__atomic_exchange", mac___atomic_exchange},
    {"__atomic_compare_exchange", mac___atomic_compare_exchange},
    {"posix_spawnattr_set_csm_np", mac_posix_spawnattr_set_csm_np},
    {"NDR_record", (void *)mac_NDR_record},
    {"mach_vm_region_recurse", mac_mach_vm_region_recurse},
    {NULL, NULL},
};
