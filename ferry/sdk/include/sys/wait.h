/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_WAIT_H_
#define _SYS_WAIT_H_
#include <_ferry.h>
__FERRY_BEGIN
#define WNOHANG 1
#define WUNTRACED 2
#define WIFEXITED(s) (((s) & 0177) == 0)
#define WEXITSTATUS(s) (((s) >> 8) & 0xff)
#define WIFSIGNALED(s) (((s) & 0177) != 0177 && ((s) & 0177) != 0)
#define WTERMSIG(s) ((s) & 0177)
#define WIFSTOPPED(s) (((s) & 0177) == 0177)
#define WSTOPSIG(s) ((s) >> 8)
pid_t wait(int *);
pid_t waitpid(pid_t, int *, int);
__FERRY_END
#endif
