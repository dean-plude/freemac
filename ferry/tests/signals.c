/* Ferry test: signals and child processes use macOS numbers. */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile int got;
static volatile int info_signo;

static void handler(int s) { got = s; }
static void info_handler(int s, siginfo_t *info, void *ctx) { info_signo = info->si_signo; got = s; }

int main(void)
{
    signal(SIGUSR1, handler);
    raise(SIGUSR1);
    printf("SIGUSR1 handler got %d (expect %d)\n", got, SIGUSR1);

    struct sigaction sa = {0};
    sa.sa_sigaction = info_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR2, &sa, NULL);
    kill(getpid(), SIGUSR2);
    printf("SIGUSR2 via siginfo %d/%d\n", got, info_signo);

    struct sigaction old;
    sigaction(SIGUSR1, NULL, &old);
    printf("old handler is ours %d\n", old.sa_handler == handler);

    sigset_t block, was;
    sigemptyset(&block);
    sigaddset(&block, SIGUSR1);
    got = 0;
    sigprocmask(SIG_BLOCK, &block, &was);
    raise(SIGUSR1);
    printf("blocked, got %d\n", got);
    sigprocmask(SIG_SETMASK, &was, NULL);
    printf("unblocked, got %d\n", got);

    pid_t child = fork();
    if (child == 0)
        _exit(7);
    int status;
    waitpid(child, &status, 0);
    printf("child exited=%d code=%d\n", WIFEXITED(status), WEXITSTATUS(status));

    child = fork();
    if (child == 0) {
        pause();
        _exit(0);
    }
    kill(child, SIGTERM);
    waitpid(child, &status, 0);
    printf("child signaled=%d sig=%d\n", WIFSIGNALED(status), WTERMSIG(status));
    return 0;
}
