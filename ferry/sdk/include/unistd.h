/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _UNISTD_H_
#define _UNISTD_H_
#include <_ferry.h>
/* A Mac's unistd.h declares select, with struct timeval and fd_set
 * (freemac 1.226, Ferry 0.50.0; MariaDB Connector/C). */
#include <sys/select.h>
__FERRY_BEGIN
/* the POSIX edition a Mac's libc follows, as its <sys/unistd.h> says */
#define _POSIX_VERSION 200112L
#define _POSIX2_VERSION 200112L
#define _POSIX_THREADS 200112L
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define _SC_ARG_MAX 1
#define _SC_CHILD_MAX 2
#define _SC_CLK_TCK 3
#define _SC_OPEN_MAX 5
#define _SC_PAGESIZE 29
#define _SC_PAGE_SIZE _SC_PAGESIZE
#define _SC_NPROCESSORS_CONF 57
#define _SC_NPROCESSORS_ONLN 58
#define _SC_PHYS_PAGES 200
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
ssize_t pread(int, void *, size_t, off_t);
ssize_t pwrite(int, const void *, size_t, off_t);
int close(int);
off_t lseek(int, off_t, int);
int dup(int);
int dup2(int, int);
int pipe(int[2]);
int fsync(int);
int ftruncate(int, off_t);
int truncate(const char *, off_t);
int unlink(const char *);
int rmdir(const char *);
int chdir(const char *);
char *getcwd(char *, size_t);
int access(const char *, int);
int link(const char *, const char *);
int symlink(const char *, const char *);
ssize_t readlink(const char *, char *, size_t);
int isatty(int);
/* freemac 1.226, Ferry 0.50.0: Sequel Pro's logger */
char *getlogin(void);
char *ttyname(int);
pid_t getpid(void);
pid_t getppid(void);
uid_t getuid(void);
uid_t geteuid(void);
gid_t getgid(void);
gid_t getegid(void);
/* freemac 1.232: VLC's rootwrap */
int setuid(uid_t);
int setgid(gid_t);
int seteuid(uid_t);
int setegid(gid_t);
pid_t setsid(void);
pid_t getsid(pid_t);
int setpgid(pid_t, pid_t);
pid_t getpgrp(void);
pid_t fork(void);
int execv(const char *, char *const[]);
int execl(const char *, const char *, ...);
int execlp(const char *, const char *, ...);
int execvp(const char *, char *const[]);
int execve(const char *, char *const[], char *const[]);
void _exit(int) __attribute__((noreturn));
unsigned sleep(unsigned);
int usleep(useconds_t);
unsigned alarm(unsigned);
int pause(void);
long sysconf(int);
/* freemac 1.232: pathconf, with a Mac's numbers (VLC) */
#define _PC_LINK_MAX 1
#define _PC_MAX_CANON 2
#define _PC_MAX_INPUT 3
#define _PC_NAME_MAX 4
#define _PC_PATH_MAX 5
#define _PC_PIPE_BUF 6
#define _PC_CHOWN_RESTRICTED 7
#define _PC_NO_TRUNC 8
#define _PC_VDISABLE 9
#define _PC_CASE_SENSITIVE 11 /* 1 on this system's file systems */
#define _PC_CASE_PRESERVING 12
long pathconf(const char *, int);
long fpathconf(int, int);
void swab(const void *, void *, ssize_t);
int getpagesize(void);
int gethostname(char *, size_t);
int chown(const char *, uid_t, gid_t);
int fchown(int, uid_t, gid_t);
int lchown(const char *, uid_t, gid_t);
extern char *optarg;
extern int optind, opterr, optopt, optreset;
int getopt(int, char *const[], const char *);
/* who a process runs as, its group and session, and a little more
 * (freemac 1.232, Ferry 0.56.0); vfork is served as fork */
int setuid(uid_t);
int setgid(gid_t);
int seteuid(uid_t);
int setegid(gid_t);
pid_t getpgrp(void);
int setpgid(pid_t, pid_t);
pid_t setsid(void);
pid_t getsid(pid_t);
int getgroups(int, gid_t[]);
int nice(int);
int fchdir(int);
int fdatasync(int);
int getdtablesize(void);
pid_t vfork(void);
int unlinkat(int, const char *, int);
int execl(const char *, const char *, ...);
int execlp(const char *, const char *, ...);
__FERRY_END
#endif
