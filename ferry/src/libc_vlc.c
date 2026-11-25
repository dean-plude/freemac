/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * What VLC's core (libvlccore) asks of libSystem that Ferry didn't have
 * (freemac 1.NEXT): Mach semaphores, which VLC uses because a Mac has no
 * unnamed POSIX semaphores, written from the Mach reference pages; and a
 * few C library calls whose Mac data or numbers differ from this system's
 * (pathconf, getpwuid_r, sigwait, statvfs, sys_errlist), from the Mac's
 * man pages.
 *
 * A semaphore is a number standing for a POSIX semaphore of this system;
 * the numbers start well above Ferry's task and host ports.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <math.h>
#include <pwd.h>
#include <signal.h>
#include <string.h>
#include <sys/statvfs.h>
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

static long mac_pathconf(const char *path, int name)
{
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

const struct ferry_symbol ferry_libc_vlc_symbols[] = {
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
    {"__exp10", mac_exp10},
    {"mach_error_string", mac_mach_error_string},
    {"mach_error", mac_mach_error},
    {"__exp10f", mac_exp10f},
    {"sys_errlist", (void *)mac_sys_errlist},
    {"sys_nerr", (void *)&mac_sys_nerr},
    {NULL, NULL},
};
