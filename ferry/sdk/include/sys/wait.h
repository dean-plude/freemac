/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_WAIT_H_
#define _SYS_WAIT_H_
#include <_ferry.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/resource.h>
__FERRY_BEGIN
#define WNOHANG 1
#define WUNTRACED 2
#define WIFEXITED(s) (((s) & 0177) == 0)
#define WEXITSTATUS(s) (((s) >> 8) & 0xff)
#define WIFSIGNALED(s) (((s) & 0177) != 0177 && ((s) & 0177) != 0)
#define WTERMSIG(s) ((s) & 0177)
#define WIFSTOPPED(s) (((s) & 0177) == 0177)
#define WSTOPSIG(s) ((s) >> 8)
/* freemac 1.232, Ferry 0.56.0: what Qt's process launcher waits with */
#define WEXITED 0x04
#define WSTOPPED 0x08
#define WCONTINUED 0x10
#define WNOWAIT 0x20
#define WCOREDUMP(s) ((s) & 0200)
typedef enum { P_ALL, P_PID, P_PGID } idtype_t;
pid_t wait(int *);
pid_t wait3(int *, int, struct rusage *);
pid_t wait4(pid_t, int *, int, struct rusage *);
int waitid(idtype_t, id_t, siginfo_t *, int);
pid_t waitpid(pid_t, int *, int);
__FERRY_END
#endif
