/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* System V shared memory (freemac 1.232, Ferry 0.56.0), in a Mac's
 * layout, written from the POSIX description of <sys/shm.h>. A segment's
 * description is translated from this system's (src/posix.c). */
#ifndef _SYS_SHM_H_
#define _SYS_SHM_H_
#include <_ferry.h>
#include <sys/ipc.h>
#include <stddef.h>
__FERRY_BEGIN

typedef unsigned short shmatt_t;
#define SHM_RDONLY 010000
#define SHM_RND 020000
#define SHMLBA 4096

#pragma pack(push, 4)
struct shmid_ds {
    struct ipc_perm shm_perm;
    size_t shm_segsz;   /* its size in bytes */
    pid_t shm_lpid;     /* the last to attach or detach */
    pid_t shm_cpid;     /* its creator */
    shmatt_t shm_nattch; /* how many have it attached */
    time_t shm_atime;
    time_t shm_dtime;
    time_t shm_ctime;
    void *shm_internal;
};
#pragma pack(pop)

int shmget(key_t key, size_t size, int shmflg);
void *shmat(int shmid, const void *shmaddr, int shmflg);
int shmdt(const void *shmaddr);
int shmctl(int shmid, int cmd, struct shmid_ds *buf);

__FERRY_END
#endif
