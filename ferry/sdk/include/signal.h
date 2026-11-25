/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SIGNAL_H_
#define _SIGNAL_H_
#include <_ferry.h>
__FERRY_BEGIN
#define SIGHUP 1
#define SIGINT 2
#define SIGQUIT 3
#define SIGILL 4
#define SIGTRAP 5
#define SIGABRT 6
#define SIGFPE 8
#define SIGKILL 9
#define SIGBUS 10
#define SIGSEGV 11
#define SIGSYS 12
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGURG 16
#define SIGSTOP 17
#define SIGTSTP 18
#define SIGCONT 19
#define SIGCHLD 20
#define SIGTTIN 21
#define SIGTTOU 22
#define SIGIO 23
#define SIGWINCH 28
#define SIGINFO 29
#define SIGUSR1 30
#define SIGUSR2 31
#define NSIG 32
typedef void (*sig_t)(int);
typedef int sig_atomic_t;
#define SIG_DFL ((sig_t)0)
#define SIG_IGN ((sig_t)1)
#define SIG_ERR ((sig_t)-1)
#define SIG_BLOCK 1
#define SIG_UNBLOCK 2
#define SIG_SETMASK 3
#define SA_ONSTACK 0x0001
#define SA_RESTART 0x0002
#define SA_RESETHAND 0x0004
#define SA_NOCLDSTOP 0x0008
#define SA_NODEFER 0x0010
#define SA_NOCLDWAIT 0x0020
#define SA_SIGINFO 0x0040
typedef struct {
    int si_signo, si_errno, si_code;
    pid_t si_pid;
    uid_t si_uid;
    int si_status;
    void *si_addr;
    uint64_t si_value;
    long si_band;
    unsigned long __pad[7];
} siginfo_t;
struct sigaction {
    union { void (*__sa_handler)(int); void (*__sa_sigaction)(int, siginfo_t *, void *); } __sigaction_u;
    sigset_t sa_mask;
    int sa_flags;
};
#define sa_handler __sigaction_u.__sa_handler
#define sa_sigaction __sigaction_u.__sa_sigaction
sig_t signal(int, sig_t);
int sigaction(int, const struct sigaction *, struct sigaction *);
int sigemptyset(sigset_t *);
int sigfillset(sigset_t *);
int sigaddset(sigset_t *, int);
int sigdelset(sigset_t *, int);
int sigismember(const sigset_t *, int);
int sigprocmask(int, const sigset_t *, sigset_t *);
/* freemac 1.NEXT (VLC) */
int sigwait(const sigset_t *, int *);
int sigpending(sigset_t *);
int sigsuspend(const sigset_t *);
int kill(pid_t, int);
int killpg(pid_t, int);
int raise(int);
__FERRY_END
#endif
