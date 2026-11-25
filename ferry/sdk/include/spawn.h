/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * posix_spawn (freemac 1.232, Ferry 0.56.0), from POSIX's <spawn.h> with a
 * Mac's flag numbers. On a Mac both attribute types are a pointer to
 * something the calls make; so they are here. POSIX_SPAWN_SETEXEC and
 * POSIX_SPAWN_START_SUSPENDED are a Mac's own and aren't served (EINVAL). */
#ifndef _FERRY_SPAWN_H_
#define _FERRY_SPAWN_H_
#include <_ferry.h>
#include <signal.h>
#include <sched.h>
__FERRY_BEGIN
typedef void *posix_spawnattr_t;
typedef void *posix_spawn_file_actions_t;
#define POSIX_SPAWN_RESETIDS 0x0001
#define POSIX_SPAWN_SETPGROUP 0x0002
#define POSIX_SPAWN_SETSIGDEF 0x0004
#define POSIX_SPAWN_SETSIGMASK 0x0008
#define POSIX_SPAWN_SETEXEC 0x0040
#define POSIX_SPAWN_START_SUSPENDED 0x0080
#define POSIX_SPAWN_SETSID 0x0400
#define POSIX_SPAWN_CLOEXEC_DEFAULT 0x4000
int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);
int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);
int posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions);
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *file_actions, int fd, const char *path, int oflag,
                                     mode_t mode);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int fd, int newfd);
int posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *file_actions, int fd);
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *file_actions, const char *path);
int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *file_actions, int fd);
int posix_spawnattr_init(posix_spawnattr_t *attr);
int posix_spawnattr_destroy(posix_spawnattr_t *attr);
int posix_spawnattr_getflags(const posix_spawnattr_t *attr, short *flags);
int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags);
int posix_spawnattr_getpgroup(const posix_spawnattr_t *attr, pid_t *pgroup);
int posix_spawnattr_setpgroup(posix_spawnattr_t *attr, pid_t pgroup);
int posix_spawnattr_getsigdefault(const posix_spawnattr_t *attr, sigset_t *sigdefault);
int posix_spawnattr_setsigdefault(posix_spawnattr_t *attr, const sigset_t *sigdefault);
int posix_spawnattr_getsigmask(const posix_spawnattr_t *attr, sigset_t *sigmask);
int posix_spawnattr_setsigmask(posix_spawnattr_t *attr, const sigset_t *sigmask);
__FERRY_END
#endif
