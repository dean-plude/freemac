/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* System V interprocess communication (freemac 1.232, Ferry 0.56.0), in a
 * Mac's layout, written from the POSIX description of <sys/ipc.h>. Ferry
 * hands the calls to this system's own, translating what differs. Qt's
 * QSharedMemory and QSystemSemaphore use them. */
#ifndef _SYS_IPC_H_
#define _SYS_IPC_H_
#include <_ferry.h>
#include <sys/types.h>
__FERRY_BEGIN

struct ipc_perm {
    uid_t uid;    /* the owner's */
    gid_t gid;
    uid_t cuid;   /* the creator's */
    gid_t cgid;
    mode_t mode;  /* the permission bits */
    unsigned short _seq;
    key_t _key;
};

#define IPC_CREAT 001000
#define IPC_EXCL 002000
#define IPC_NOWAIT 004000
#define IPC_PRIVATE ((key_t)0)
#define IPC_RMID 0
#define IPC_SET 1
#define IPC_STAT 2

key_t ftok(const char *path, int id);

__FERRY_END
#endif
