/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* System V semaphores (freemac 1.232, Ferry 0.56.0), in a Mac's layout,
 * written from the POSIX description of <sys/sem.h>. A Mac numbers
 * semctl's commands its own way; Ferry translates them (src/posix.c). */
#ifndef _SYS_SEM_H_
#define _SYS_SEM_H_
#include <_ferry.h>
#include <sys/ipc.h>
__FERRY_BEGIN

#pragma pack(push, 4)
struct semid_ds {
    struct ipc_perm sem_perm;
    int32_t sem_base;
    unsigned short sem_nsems; /* how many semaphores the set has */
    time_t sem_otime;         /* the last semop */
    int32_t sem_pad1;
    time_t sem_ctime;
    int32_t sem_pad2;
    int32_t sem_pad3[4];
};
#pragma pack(pop)

struct sembuf {
    unsigned short sem_num;
    short sem_op;
    short sem_flg;
};

/* a program declares union semun itself, as POSIX says */
#define GETNCNT 3
#define GETPID 4
#define GETVAL 5
#define GETALL 6
#define GETZCNT 7
#define SETVAL 8
#define SETALL 9
#define SEM_UNDO 010000

int semget(key_t key, int nsems, int semflg);
int semop(int semid, struct sembuf *sops, size_t nsops);
int semctl(int semid, int semnum, int cmd, ...);

__FERRY_END
#endif
