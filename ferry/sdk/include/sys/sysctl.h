/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The system's settings by name or number, from the sysctl(3) man page.
 * struct kinfo_proc is laid out as the 64-bit Intel interface has it (648
 * bytes); its documented fields are named, the rest are placeholders. */
#ifndef _SYS_SYSCTL_H_
#define _SYS_SYSCTL_H_
#include <_ferry.h>
#include <sys/time.h>
#include <mach/machine.h>
__FERRY_BEGIN
#define CTL_MAXNAME 12
#define CTL_UNSPEC 0
#define CTL_KERN 1
#define CTL_VM 2
#define CTL_VFS 3
#define CTL_NET 4
#define CTL_DEBUG 5
#define CTL_HW 6
#define CTL_MACHDEP 7
#define CTL_USER 8

#define KERN_OSTYPE 1
#define KERN_OSRELEASE 2
#define KERN_VERSION 4
#define KERN_ARGMAX 8
#define KERN_HOSTNAME 10
#define KERN_PROC 14
#define KERN_BOOTTIME 21
#define KERN_MAXFILESPERPROC 29
#define KERN_PROCARGS2 49
#define KERN_OSVERSION 65

#define KERN_PROC_ALL 0
#define KERN_PROC_PID 1
#define KERN_PROC_PGRP 2
#define KERN_PROC_TTY 3
#define KERN_PROC_UID 4
#define KERN_PROC_RUID 5

#define HW_MACHINE 1
#define HW_MODEL 2
#define HW_NCPU 3
#define HW_BYTEORDER 4
#define HW_PAGESIZE 7
#define HW_CACHELINE 16
#define HW_L1ICACHESIZE 17
#define HW_L1DCACHESIZE 18
#define HW_L2CACHESIZE 20
#define HW_L3CACHESIZE 22
#define HW_MEMSIZE 24
#define HW_AVAILCPU 25

/* p_flag and p_stat */
#define P_LP64 0x00000004
#define P_TRACED 0x00000800
#define SIDL 1
#define SRUN 2
#define SSLEEP 3
#define SSTOP 4
#define SZOMB 5
#define EPROC_CTTY 0x01
#define EPROC_SLEADER 0x02
#define MAXCOMLEN 16
#define WMESGLEN 7
#define COMAPAT_MAXLOGNAME 12
#define NGROUPS 16

struct extern_proc {
    union {
        struct { void *__p_forw, *__p_back; } p_st1;
        struct timeval __p_starttime;
    } p_un;
#define p_starttime p_un.__p_starttime
    void *p_vmspace;
    void *p_sigacts;
    int p_flag;
    char p_stat;
    pid_t p_pid;
    pid_t p_oppid;
    int p_dupfd;
    char *user_stack;
    void *exit_thread;
    int p_debugger;
    int sigwait;
    unsigned int p_estcpu;
    int p_cpticks;
    uint32_t p_pctcpu;
    void *p_wchan;
    char *p_wmesg;
    unsigned int p_swtime;
    unsigned int p_slptime;
    struct timeval p_realtimer[2];
    struct timeval p_rtime;
    uint64_t p_uticks, p_sticks, p_iticks;
    int p_traceflag;
    void *p_tracep;
    int p_siglist;
    void *p_textvp;
    int p_holdcnt;
    sigset_t p_sigmask, p_sigignore, p_sigcatch;
    unsigned char p_priority, p_usrpri;
    char p_nice;
    char p_comm[MAXCOMLEN + 1];
    void *p_pgrp;
    void *p_addr;
    unsigned short p_xstat, p_acflag;
    void *p_ru;
};

struct _pcred {
    char pc_lock[72];
    void *pc_ucred;
    uid_t p_ruid, p_svuid;
    gid_t p_rgid, p_svgid;
    int p_refcnt;
};

struct _ucred {
    int32_t cr_ref;
    uid_t cr_uid;
    short cr_ngroups;
    gid_t cr_groups[NGROUPS];
};

struct eproc {
    void *e_paddr;
    void *e_sess;
    struct _pcred e_pcred;
    struct _ucred e_ucred;
    struct { int32_t __dummy; char *__dummy2; int32_t __dummy3[5]; char *__dummy4[3]; } e_vm;
    pid_t e_ppid;
    pid_t e_pgid;
    short e_jobc;
    dev_t e_tdev;
    pid_t e_tpgid;
    void *e_tsess;
    char e_wmesg[WMESGLEN + 1];
    int32_t e_xsize;
    short e_xrssize, e_xccount, e_xswrss;
    int32_t e_flag;
    char e_login[COMAPAT_MAXLOGNAME];
    int32_t e_spare[4];
};

struct kinfo_proc {
    struct extern_proc kp_proc;
    struct eproc kp_eproc;
};

int sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int sysctlnametomib(const char *name, int *mibp, size_t *sizep);
__FERRY_END
#endif
