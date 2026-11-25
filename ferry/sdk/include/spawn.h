/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * posix_spawn(2) and its file actions and attributes, as the Mac's man
 * pages give them (freemac 1.233, Ferry 0.57.0). On a Mac both types are
 * pointers to storage the init calls allocate. */
#ifndef _SPAWN_H_
#define _SPAWN_H_
#include <_ferry.h>
#include <sys/types.h>
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

int posix_spawn(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *,
                char *const[], char *const[]);
int posix_spawnp(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *,
                 char *const[], char *const[]);

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *, int, const char *, int, mode_t);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);
int posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *, int);
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *, const char *);
int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *, int);

int posix_spawnattr_init(posix_spawnattr_t *);
int posix_spawnattr_destroy(posix_spawnattr_t *);
int posix_spawnattr_setflags(posix_spawnattr_t *, short);
int posix_spawnattr_getflags(const posix_spawnattr_t *, short *);
int posix_spawnattr_setsigmask(posix_spawnattr_t *, const sigset_t *);
int posix_spawnattr_getsigmask(const posix_spawnattr_t *, sigset_t *);
int posix_spawnattr_setsigdefault(posix_spawnattr_t *, const sigset_t *);
int posix_spawnattr_getsigdefault(const posix_spawnattr_t *, sigset_t *);
int posix_spawnattr_setpgroup(posix_spawnattr_t *, pid_t);
int posix_spawnattr_getpgroup(const posix_spawnattr_t *, pid_t *);
int posix_spawnattr_setbinpref_np(posix_spawnattr_t *, size_t, int *, size_t *);
__FERRY_END
#endif
