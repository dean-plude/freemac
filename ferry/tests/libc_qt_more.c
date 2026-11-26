/* More of what Qt's core asks of a Mac's C library and Mach (freemac 1.232,
 * Ferry 0.56.0): Mach semaphores and address waits (QMutex), vm_remap (QResource),
 * posix_spawn, nl_langinfo, a terminal's settings, flock (QLockFile),
 * times, tzname and copyfile (QFile::copy). */
#include <copyfile.h>
#include <errno.h>
#include <fcntl.h>
#include <langinfo.h>
#include <locale.h>
#include <mach/mach.h>
#include <mach/semaphore.h>
#include <mach/vm_map.h>
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/times.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
static semaphore_t sem;
static int woke;

static void *waiter(void *arg)
{
    (void)arg;
    if (semaphore_wait(sem) == KERN_SUCCESS)
        __atomic_add_fetch(&woke, 1, __ATOMIC_SEQ_CST);
    return NULL;
}

/* the Darwin kernel's address waits, declared as Qt does (xnu's sys/ulock.h) */
extern int __ulock_wait2(uint32_t operation, void *addr, uint64_t value, uint64_t timeout_ns, uint64_t value2);
extern int __ulock_wake(uint32_t operation, void *addr, uint64_t wake_value);
extern int csr_get_active_config(uint32_t *config);
static _Atomic uint32_t word;
static void *ulock_waker(void *arg)
{
    (void)arg;
    usleep(20000);
    word = 1;
    __ulock_wake(0x01000001, (void *)&word, 0);
    return NULL;
}

int main(void)
{
    kern_return_t k = semaphore_create(mach_task_self(), &sem, SYNC_POLICY_FIFO, 0);
    printf("semaphore made %d\n", k == KERN_SUCCESS && sem != 0);
    mach_timespec_t ts = {0, 20 * 1000 * 1000};
    printf("timed wait on 0 times out %d\n", semaphore_timedwait(sem, ts) == KERN_OPERATION_TIMED_OUT);
    semaphore_signal(sem);
    printf("signalled, then taken %d\n", semaphore_timedwait(sem, ts) == KERN_SUCCESS);
    pthread_t t[3];
    for (int i = 0; i < 3; i++)
        pthread_create(&t[i], NULL, waiter, NULL);
    /* signal_all wakes those waiting now, so go on until all three have woken */
    for (int i = 0; i < 2000 && __atomic_load_n(&woke, __ATOMIC_SEQ_CST) < 3; i++) {
        semaphore_signal_all(sem);
        usleep(1000);
    }
    for (int i = 0; i < 3; i++)
        pthread_join(t[i], NULL);
    printf("signal_all woke %d\n", woke);
    printf("none left after signal_all %d\n", semaphore_timedwait(sem, ts) == KERN_OPERATION_TIMED_OUT);
    printf("destroyed %d, then unknown %d\n", semaphore_destroy(mach_task_self(), sem) == KERN_SUCCESS,
           semaphore_signal(sem) == KERN_INVALID_ARGUMENT);

    size_t page = (size_t)getpagesize();
    char *src = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    strcpy(src, "resource");
    mprotect(src, page, PROT_READ);
    vm_address_t addr = 0;
    vm_prot_t cur = VM_PROT_READ | VM_PROT_WRITE, max = VM_PROT_ALL;
    k = vm_remap(mach_task_self(), &addr, page, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)src, 1, &cur,
                 &max, VM_INHERIT_DEFAULT);
    char *copy = (char *)addr;
    copy[0] = 'R';
    printf("vm_remap %d copy \"%s\" original \"%s\" writable %d\n", k == KERN_SUCCESS, copy, src,
           (max & VM_PROT_WRITE) != 0);
    munmap(copy, page);
    vm_address_t a = 0;
    printf("vm_allocate %d zeroed %d\n", vm_allocate(mach_task_self(), &a, page, VM_FLAGS_ANYWHERE) == KERN_SUCCESS,
           ((char *)a)[100] == 0);
    vm_deallocate(mach_task_self(), a, page);

    int p[2];
    pipe(p);
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_addclose(&fa, p[0]);
    posix_spawnattr_t at;
    posix_spawnattr_init(&at);
    sigset_t none;
    sigemptyset(&none);
    posix_spawnattr_setsigmask(&at, &none);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT);
    short fl = 0;
    posix_spawnattr_getflags(&at, &fl);
    printf("flags kept %d\n", fl == (POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT));
    char *argv[] = {"sh", "-c", "echo spawned; ls /proc/self/fd | wc -l", NULL};
    pid_t pid;
    int r = posix_spawnp(&pid, "sh", &fa, &at, argv, environ);
    close(p[1]);
    char buf[64] = {0};
    size_t got = 0;
    ssize_t n;
    while ((n = read(p[0], buf + got, sizeof buf - 1 - got)) > 0)
        got += (size_t)n;
    close(p[0]);
    int st;
    waitpid(pid, &st, 0);
    int fds = 0;
    char *nl = strchr(buf, '\n');
    if (nl)
        fds = atoi(nl + 1);
    printf("posix_spawnp %d exited %d said \"%.*s\", few descriptors %d\n", r, WEXITSTATUS(st),
           nl ? (int)(nl - buf) : 0, buf, fds > 0 && fds <= 4);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_SETEXEC);
    printf("SETEXEC refused %d\n", posix_spawn(&pid, "/bin/true", NULL, &at, argv, environ) != 0);
    printf("missing program %d\n", posix_spawn(&pid, "/no/such/program", NULL, NULL, argv, environ) == ENOENT);
    posix_spawnattr_destroy(&at);
    posix_spawn_file_actions_destroy(&fa);

    setlocale(LC_ALL, "C");
    printf("CODESET \"%s\" DAY_1 \"%s\" ABMON_12 \"%s\" RADIXCHAR \"%s\" D_MD_ORDER \"%s\"\n", nl_langinfo(CODESET),
           nl_langinfo(DAY_1), nl_langinfo(ABMON_12), nl_langinfo(RADIXCHAR), nl_langinfo(D_MD_ORDER));

    struct termios tio;
    memset(&tio, 0x55, sizeof tio);
    errno = 0;
    printf("struct termios %zu bytes, not a terminal %d\n", sizeof tio,
           tcgetattr(p[0] = open("/dev/null", O_RDONLY), &tio) == -1 && errno == ENOTTY);
    close(p[0]);
    cfmakeraw(&tio);
    cfsetspeed(&tio, B115200);
    printf("raw: no echo %d, not canonical %d, 8 bits %d, VMIN %d, speed %lu\n", !(tio.c_lflag & ECHO),
           !(tio.c_lflag & ICANON), (tio.c_cflag & CSIZE) == CS8, tio.c_cc[VMIN], (unsigned long)cfgetospeed(&tio));

    char path[] = "/tmp/ferry_flock_XXXXXX";
    int f1 = mkstemp(path), f2 = open(path, O_RDWR);
    printf("flock: first %d, second blocked %d, after unlock %d\n", flock(f1, LOCK_EX | LOCK_NB),
           flock(f2, LOCK_EX | LOCK_NB) == -1 && errno == EWOULDBLOCK, (flock(f1, LOCK_UN), flock(f2, LOCK_EX | LOCK_NB)));
    close(f1);
    close(f2);
    unlink(path);

    char dir[] = "/tmp/ferry_copyfile_XXXXXX";
    mkdtemp(dir);
    char pa[256], pb[256], pc[256];
    snprintf(pa, sizeof pa, "%s/a", dir);
    snprintf(pb, sizeof pb, "%s/b", dir);
    snprintf(pc, sizeof pc, "%s/c", dir);
    int fa_ = open(pa, O_WRONLY | O_CREAT, 0640);
    write(fa_, "copied data", 11);
    close(fa_);
    int s1 = open(pa, O_RDONLY), d1 = open(pb, O_WRONLY | O_CREAT, 0600);
    int fr = fcopyfile(s1, d1, NULL, COPYFILE_DATA | COPYFILE_STAT);
    close(s1);
    close(d1);
    struct stat sb;
    stat(pb, &sb);
    char got2[32] = {0};
    int r2 = open(pb, O_RDONLY);
    read(r2, got2, sizeof got2 - 1);
    close(r2);
    printf("fcopyfile %d \"%s\" mode %o\n", fr, got2, sb.st_mode & 0777);
    printf("copyfile EXCL onto it refused %d\n", copyfile(pa, pb, NULL, COPYFILE_ALL | COPYFILE_EXCL) == -1 && errno == EEXIST);
    printf("copyfile MOVE %d, original gone %d\n", copyfile(pb, pc, NULL, COPYFILE_ALL | COPYFILE_MOVE),
           access(pb, F_OK) == -1);
    unlink(pa);
    unlink(pc);
    rmdir(dir);

    struct tms tm;
    clock_t c = times(&tm);
    printf("times %d\n", c != (clock_t)-1);
    setenv("TZ", "Europe/Paris", 1);
    tzset();
    printf("tzname \"%s\" \"%s\", daylight %d, timezone %ld\n", tzname[0], tzname[1], daylight, timezone);
    {
        word = 5;
        int changed = __ulock_wait2(0x01000001, (void *)&word, 4, 0, 0);
        int timed = __ulock_wait2(0x01000001, (void *)&word, 5, 10000000, 0);
        int nobody = __ulock_wake(0x01000001, (void *)&word, 0);
        word = 0;
        pthread_t t;
        pthread_create(&t, NULL, ulock_waker, NULL);
        while (word == 0)
            __ulock_wait2(0x01000001, (void *)&word, 0, 0, 0);
        pthread_join(t, NULL);
        uint64_t big = 0x100000000ull;
        int wide = __ulock_wait2(0x01000005, &big, 0, 0, 0);
        uint32_t csr = 7;
        int c = csr_get_active_config(&csr);
        printf("ulock: changed %d, timed out %d, no waiter %d, woken %d, 64-bit compare %d, csr %d %u\n", changed,
               timed == -ETIMEDOUT, nobody == -ENOENT, word == 1, wide, c, csr);
    }
    return 0;
}
