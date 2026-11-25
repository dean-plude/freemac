/* SPDX-License-Identifier: GPL-3.0-or-later
 * What VLC's core asks of libSystem (freemac 1.NEXT): Mach semaphores,
 * pathconf with a Mac's numbers, the reentrant user lookups, sigpending and
 * sigwait with a Mac's signal sets, statvfs in a Mac's layout, strnstr,
 * sys_errlist by a Mac's numbers, tsearch, nrand48, swab and timespec_get. */
#include <errno.h>
#include <execinfo.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/semaphore.h>
#include <math.h>
#include <pthread.h>
#include <pwd.h>
#include <search.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/statvfs.h>
#include <time.h>
#include <unistd.h>

static semaphore_t sem;
static int woke;

static void *waiter(void *arg)
{
    (void)arg;
    semaphore_wait(sem);
    woke = 1;
    return NULL;
}

static int cmp(const void *a, const void *b) { return strcmp(a, b); }

int main(void)
{
    /* semaphores */
    printf("create %d\n", semaphore_create(mach_task_self(), &sem, SYNC_POLICY_FIFO, 0));
    mach_timespec_t t = {0, 20000000};
    printf("timedwait on 0: %d\n", semaphore_timedwait(sem, t));
    pthread_t th;
    pthread_create(&th, NULL, waiter, NULL);
    printf("signal %d\n", semaphore_signal(sem));
    pthread_join(th, NULL);
    printf("woke %d\n", woke);
    semaphore_signal(sem);
    printf("timedwait on 1: %d\n", semaphore_timedwait(sem, t));
    printf("destroy %d, again %d\n", semaphore_destroy(mach_task_self(), sem),
           semaphore_destroy(mach_task_self(), sem) != KERN_SUCCESS);

    /* pathconf */
    printf("name max %ld, path max %ld\n", pathconf("/", _PC_NAME_MAX), pathconf("/", _PC_PATH_MAX));
    errno = 0;
    printf("bad name %ld %d\n", pathconf("/", 99), errno == EINVAL);

    /* getpwuid_r */
    struct passwd pw, *found = NULL;
    char buf[4096];
    int r = getpwuid_r(0, &pw, buf, sizeof buf, &found);
    printf("root %d %s uid %u dir %s\n", r, found ? pw.pw_name : "-", found ? pw.pw_uid : 99,
           found ? pw.pw_dir : "-");
    r = getpwnam_r("no such user here", &pw, buf, sizeof buf, &found);
    printf("nobody %d %d\n", r, found == NULL);

    /* a Mac's signal set: SIGUSR1 is 30, SIGUSR2 31 */
    sigset_t set, pend;
    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    sigprocmask(SIG_BLOCK, &set, NULL);
    kill(getpid(), SIGUSR1);
    sigpending(&pend);
    printf("pending usr1 %d usr2 %d\n", sigismember(&pend, SIGUSR1), sigismember(&pend, SIGUSR2));
    int sig = 0;
    printf("sigwait %d sig %d\n", sigwait(&set, &sig), sig);

    /* statvfs */
    struct statvfs v;
    printf("statvfs %d, sizes %d, namemax %lu\n", statvfs("/", &v),
           v.f_frsize > 0 && v.f_blocks > 0 && v.f_bavail <= v.f_blocks, v.f_namemax);

    /* strings and errors */
    printf("strnstr %s %s\n", strnstr("Ferry plays VLC", "VLC", 15) ? "found" : "no",
           strnstr("Ferry plays VLC", "VLC", 13) ? "found" : "no");
    printf("errors %d: %s / %s\n", sys_nerr > 100, sys_errlist[ENOENT], sys_errlist[ETIMEDOUT]);

    /* trees, random numbers, swab, time */
    void *root = NULL;
    tsearch("b", &root, cmp);
    tsearch("a", &root, cmp);
    printf("tfind %s %s\n", tfind("a", &root, cmp) ? "a" : "-", tfind("z", &root, cmp) ? "z" : "-");
    unsigned short x[3] = {1, 2, 3};
    long n1 = nrand48(x);
    unsigned short y[3] = {1, 2, 3};
    printf("nrand48 same %d\n", n1 == nrand48(y));
    char s[4] = "abcd", d[4];
    swab(s, d, 4);
    printf("swab %.4s\n", d);
    struct timespec ts;
    printf("timespec_get %d\n", timespec_get(&ts, TIME_UTC) == TIME_UTC && ts.tv_sec > 1700000000);
    void *frames[8];
    printf("backtrace %d\n", backtrace(frames, 8) > 0);
    printf("SSIZE_MAX %d\n", SSIZE_MAX == LONG_MAX);
    return 0;
}
