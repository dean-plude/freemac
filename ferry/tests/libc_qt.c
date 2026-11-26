/* What Qt's core asks of a Mac's C library and CoreServices (freemac 1.232,
 * Ferry 0.56.0): setjmp and longjmp (libpng and FreeType report errors with
 * them), waiting for a child with wait4 and waitid (Qt's process
 * launcher), the group database, and UCCompareText's sorting (QCollator). */
#include <CoreServices/CoreServices.h>
#include <grp.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static jmp_buf jb;
static sigjmp_buf sjb;

static void deep(int n)
{
    if (n == 0)
        longjmp(jb, 42);
    deep(n - 1);
}

static int cmp(UCCollateOptions o, const char *a, const char *b)
{
    UniChar x[64], y[64];
    int nx = 0, ny = 0;
    for (; a[nx]; nx++)
        x[nx] = (unsigned char)a[nx];
    for (; b[ny]; ny++)
        y[ny] = (unsigned char)b[ny];
    LocaleRef loc;
    CollatorRef c;
    LocaleRefFromLocaleString("en-US", &loc);
    UCCreateCollator(loc, 0, o, &c);
    Boolean eq;
    SInt32 order;
    UCCompareText(c, x, nx, y, ny, &eq, &order);
    UCDisposeCollator(&c);
    return eq ? 0 : order;
}

int main(void)
{
    volatile int kept = 7;
    int r = setjmp(jb);
    if (r == 0) {
        kept = 8;
        deep(20);
    }
    printf("setjmp came back %d, local %d\n", r, kept);

    r = _setjmp(jb);
    if (r == 0)
        _longjmp(jb, 0);
    printf("_longjmp with 0 gives %d\n", r);

    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    if (sigsetjmp(sjb, 1) == 0) {
        sigprocmask(SIG_BLOCK, &set, NULL);
        siglongjmp(sjb, 1);
    }
    sigprocmask(SIG_BLOCK, NULL, &set);
    printf("siglongjmp put the mask back %d\n", !sigismember(&set, SIGUSR1));

    pid_t p = fork();
    if (p == 0)
        _exit(3);
    siginfo_t info = {0};
    int w = waitid(P_PID, p, &info, WEXITED | WNOWAIT);
    printf("waitid %d pid %d code exited %d status %d\n", w, info.si_pid == p, info.si_code == CLD_EXITED,
           info.si_status);
    int st = 0;
    struct rusage ru;
    pid_t q = wait4(p, &st, 0, &ru);
    printf("wait4 %d exited %d code %d\n", q == p, WIFEXITED(st), WEXITSTATUS(st));

    p = fork();
    if (p == 0) {
        pause();
        _exit(0);
    }
    kill(p, SIGTERM);
    memset(&info, 0, sizeof info);
    waitid(P_PID, p, &info, WEXITED);
    printf("killed child code %d signal SIGTERM %d\n", info.si_code == CLD_KILLED, info.si_status == SIGTERM);

    struct group *g = getgrgid(getgid());
    printf("group found %d same id %d\n", g != NULL, g && g->gr_gid == getgid());

    printf("apple<Banana %d, Banana<cherry %d\n", cmp(0, "apple", "Banana") < 0, cmp(0, "Banana", "cherry") < 0);
    printf("file2<file10 as numbers %d, as text %d\n", cmp(kUCCollateDigitsAsNumberMask, "file2", "file10") < 0,
           cmp(0, "file2", "file10") > 0);
    printf("case: a<A %d, same when ignored %d\n", cmp(0, "a", "A") < 0, cmp(kUCCollateCaseInsensitiveMask, "a", "A") == 0);

    UniChar t[] = {'O', 'B', 'S'};
    LocaleRef loc;
    CollatorRef c;
    LocaleRefFromLocaleString("en", &loc);
    UCCreateCollator(loc, 0, 0, &c);
    UCCollationValue k[2];
    ItemCount n = 0;
    OSStatus s1 = UCGetCollationKey(c, t, 3, 2, &n, k);
    UCCollationValue big[32];
    OSStatus s2 = UCGetCollationKey(c, t, 3, 32, &n, big);
    printf("key too small %d, then fits %d\n", s1 == kUCOutputBufferTooSmall, s2 == noErr && n > 3);
    UCDisposeCollator(&c);
    return 0;
}
