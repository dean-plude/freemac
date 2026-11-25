/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.NEXT): setjmp and longjmp in a Mac's jmp_buf, which
 * FreeType uses to leave a rasteriser that runs out of room (VLC draws its
 * subtitles with FreeType). longjmp comes back from setjmp a second time with
 * the value given (1 for 0), with local variables kept in registers back as
 * they were at setjmp; setjmp and longjmp put the signal mask back, _setjmp
 * and _longjmp leave it, and sigsetjmp keeps it only when asked. */
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

static jmp_buf jb;
static sigjmp_buf sjb;

static void deep(int n, int value)
{
    char room[256];
    memset(room, n, sizeof room);
    if (n == 0)
        longjmp(jb, value);
    deep(n - 1, value + room[3] - room[3]);
}

static int blocked(int sig)
{
    sigset_t s;
    sigprocmask(SIG_BLOCK, NULL, &s);
    return sigismember(&s, sig);
}

static void block(int sig, int on)
{
    sigset_t s;
    sigemptyset(&s);
    sigaddset(&s, sig);
    sigprocmask(on ? SIG_BLOCK : SIG_UNBLOCK, &s, NULL);
}

int main(void)
{
    printf("jmp_buf is %zu bytes, sigjmp_buf %zu\n", sizeof(jmp_buf), sizeof(sigjmp_buf));

    volatile int rounds = 0;
    register long kept = 42;
    int r = setjmp(jb);
    rounds++;
    if (r == 0)
        deep(20, 7);
    printf("setjmp came back with %d after %d rounds, kept %ld\n", r, rounds, kept);

    rounds = 0;
    r = setjmp(jb);
    rounds++;
    if (r == 0)
        longjmp(jb, 0);
    printf("longjmp with 0 gives %d\n", r);

    block(SIGUSR1, 0);
    if (setjmp(jb) == 0) {
        block(SIGUSR1, 1);
        longjmp(jb, 1);
    }
    printf("setjmp puts the mask back: %d\n", !blocked(SIGUSR1));

    if (_setjmp(jb) == 0) {
        block(SIGUSR1, 1);
        _longjmp(jb, 1);
    }
    printf("_setjmp leaves it: %d\n", blocked(SIGUSR1));
    block(SIGUSR1, 0);

    if (sigsetjmp(sjb, 1) == 0) {
        block(SIGUSR2, 1);
        siglongjmp(sjb, 3);
    }
    printf("sigsetjmp(1) puts it back: %d\n", !blocked(SIGUSR2));
    if (sigsetjmp(sjb, 0) == 0) {
        block(SIGUSR2, 1);
        siglongjmp(sjb, 3);
    }
    printf("sigsetjmp(0) leaves it: %d\n", blocked(SIGUSR2));
    return 0;
}
