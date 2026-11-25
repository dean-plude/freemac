/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libSystem calls that large plugin-based media apps (OBS, VLC) make next
 * (freemac 1.233, Ferry 0.57.0), each written from its Mac man page or
 * Apple's public Mach documentation. Mach semaphores, backtrace and
 * getpwuid_r are in libc_vlc.c.
 *
 * - mach_wait_until(deadline), the deadline in mach_absolute_time's units
 *   (nanoseconds of the monotonic clock here).
 * - posix_spawn(2) and posix_spawnp, with their file actions (open, close,
 *   dup2, inherit, chdir and fchdir) and attributes (flags, signal mask,
 *   default signals, process group), on this system's posix_spawn. As on a
 *   Mac the two types are pointers to storage the init calls allocate.
 *   POSIX_SPAWN_CLOEXEC_DEFAULT closes every descriptor the actions don't
 *   name. A Mac program (a Mach-O file), such as a helper tool in an app's
 *   bundle, is started through Ferry itself, as NSTask starts one.
 * - glob(3), globfree and fnmatch(3) in the Mac's (BSD) layout and flag
 *   numbers; the matching is this system's.
 * - The terminal settings calls, tcgetattr(3), tcsetattr and the rest, with
 *   a Mac's struct termios and BSD's flag, control character and speed
 *   numbers converted to this system's, and posix_openpt for a
 *   pseudo-terminal.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <glob.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"

/* ---- mach_wait_until ---------------------------------------------------------- */

#define KERN_SUCCESS 0

static int mac_mach_wait_until(uint64_t deadline)
{
    struct timespec d = {(time_t)(deadline / 1000000000u), (long)(deadline % 1000000000u)};
    while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &d, NULL) == EINTR)
        ;
    return KERN_SUCCESS;
}

/* ---- posix_spawn ----------------------------------------------------------------- */

#define MAC_POSIX_SPAWN_RESETIDS 0x0001
#define MAC_POSIX_SPAWN_SETPGROUP 0x0002
#define MAC_POSIX_SPAWN_SETSIGDEF 0x0004
#define MAC_POSIX_SPAWN_SETSIGMASK 0x0008
#define MAC_POSIX_SPAWN_SETEXEC 0x0040
#define MAC_POSIX_SPAWN_START_SUSPENDED 0x0080
#define MAC_POSIX_SPAWN_SETSID 0x0400
#define MAC_POSIX_SPAWN_CLOEXEC_DEFAULT 0x4000

enum { A_OPEN, A_CLOSE, A_DUP2, A_INHERIT, A_CHDIR, A_FCHDIR };
struct action {
    int kind, fd, newfd, oflag;
    unsigned mode;
    char *path;
};
struct mac_actions {
    int n, cap;
    struct action *a;
};
struct mac_spawnattr {
    short flags;
    uint32_t sigmask, sigdefault;
    pid_t pgroup;
};

static int spawn_err(int linux_err) { return ferry_errno_to_mac(linux_err); }

static int mac_posix_spawn_file_actions_init(struct mac_actions **fa)
{
    *fa = calloc(1, sizeof **fa);
    return *fa ? 0 : spawn_err(ENOMEM);
}

static int mac_posix_spawn_file_actions_destroy(struct mac_actions **fa)
{
    if (!fa || !*fa)
        return spawn_err(EINVAL);
    for (int i = 0; i < (*fa)->n; i++)
        free((*fa)->a[i].path);
    free((*fa)->a);
    free(*fa);
    *fa = NULL;
    return 0;
}

static int add_action(struct mac_actions **fa, struct action act)
{
    if (!fa || !*fa)
        return spawn_err(EINVAL);
    if (act.fd < 0 || (act.kind == A_DUP2 && act.newfd < 0))
        return spawn_err(EBADF);
    struct mac_actions *m = *fa;
    if (m->n == m->cap) {
        int cap = m->cap ? m->cap * 2 : 8;
        struct action *a = realloc(m->a, cap * sizeof *a);
        if (!a)
            return spawn_err(ENOMEM);
        m->a = a;
        m->cap = cap;
    }
    if (act.path && !(act.path = strdup(act.path)))
        return spawn_err(ENOMEM);
    m->a[m->n++] = act;
    return 0;
}

static int mac_posix_spawn_file_actions_addopen(struct mac_actions **fa, int fd, const char *path, int oflag,
                                                unsigned mode)
{
    return add_action(fa, (struct action){A_OPEN, fd, 0, oflag, mode, (char *)path});
}
static int mac_posix_spawn_file_actions_addclose(struct mac_actions **fa, int fd)
{
    return add_action(fa, (struct action){A_CLOSE, fd, 0, 0, 0, NULL});
}
static int mac_posix_spawn_file_actions_adddup2(struct mac_actions **fa, int fd, int newfd)
{
    return add_action(fa, (struct action){A_DUP2, fd, newfd, 0, 0, NULL});
}
static int mac_posix_spawn_file_actions_addinherit_np(struct mac_actions **fa, int fd)
{
    return add_action(fa, (struct action){A_INHERIT, fd, 0, 0, 0, NULL});
}
static int mac_posix_spawn_file_actions_addchdir_np(struct mac_actions **fa, const char *path)
{
    return add_action(fa, (struct action){A_CHDIR, 0, 0, 0, 0, (char *)path});
}
static int mac_posix_spawn_file_actions_addfchdir_np(struct mac_actions **fa, int fd)
{
    return add_action(fa, (struct action){A_FCHDIR, fd, 0, 0, 0, NULL});
}

static int mac_posix_spawnattr_init(struct mac_spawnattr **attr)
{
    *attr = calloc(1, sizeof **attr);
    return *attr ? 0 : spawn_err(ENOMEM);
}
static int mac_posix_spawnattr_destroy(struct mac_spawnattr **attr)
{
    if (!attr || !*attr)
        return spawn_err(EINVAL);
    free(*attr);
    *attr = NULL;
    return 0;
}
#define ATTR_OR_FAIL(attr) do { if (!(attr) || !*(attr)) return spawn_err(EINVAL); } while (0)
static int mac_posix_spawnattr_setflags(struct mac_spawnattr **attr, short flags)
{
    ATTR_OR_FAIL(attr);
    (*attr)->flags = flags;
    return 0;
}
static int mac_posix_spawnattr_getflags(struct mac_spawnattr *const *attr, short *flags)
{
    ATTR_OR_FAIL(attr);
    *flags = (*attr)->flags;
    return 0;
}
static int mac_posix_spawnattr_setsigmask(struct mac_spawnattr **attr, const uint32_t *set)
{
    ATTR_OR_FAIL(attr);
    (*attr)->sigmask = *set;
    return 0;
}
static int mac_posix_spawnattr_getsigmask(struct mac_spawnattr *const *attr, uint32_t *set)
{
    ATTR_OR_FAIL(attr);
    *set = (*attr)->sigmask;
    return 0;
}
static int mac_posix_spawnattr_setsigdefault(struct mac_spawnattr **attr, const uint32_t *set)
{
    ATTR_OR_FAIL(attr);
    (*attr)->sigdefault = *set;
    return 0;
}
static int mac_posix_spawnattr_getsigdefault(struct mac_spawnattr *const *attr, uint32_t *set)
{
    ATTR_OR_FAIL(attr);
    *set = (*attr)->sigdefault;
    return 0;
}
static int mac_posix_spawnattr_setpgroup(struct mac_spawnattr **attr, pid_t pg)
{
    ATTR_OR_FAIL(attr);
    (*attr)->pgroup = pg;
    return 0;
}
static int mac_posix_spawnattr_getpgroup(struct mac_spawnattr *const *attr, pid_t *pg)
{
    ATTR_OR_FAIL(attr);
    *pg = (*attr)->pgroup;
    return 0;
}
/* which processor type to prefer, and the quality of service: one kind here */
static int mac_posix_spawnattr_setbinpref_np(struct mac_spawnattr **attr, size_t count, int *pref, size_t *done)
{
    ATTR_OR_FAIL(attr);
    if (done)
        *done = count;
    return 0;
}
static int mac_posix_spawnattr_set_qos_class_np(struct mac_spawnattr **attr, unsigned qos)
{
    ATTR_OR_FAIL(attr);
    return 0;
}

static void sigset_from_mac(uint32_t mac, sigset_t *set)
{
    sigemptyset(set);
    for (int i = 1; i < 32; i++)
        if ((mac & (1u << (i - 1))) && ferry_signal_to_linux(i))
            sigaddset(set, ferry_signal_to_linux(i));
}

static int is_mach_o(const char *path)
{
    unsigned char m[4];
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    ssize_t n = read(fd, m, 4);
    close(fd);
    if (n != 4)
        return 0;
    uint32_t le = m[0] | m[1] << 8 | m[2] << 16 | (uint32_t)m[3] << 24;
    uint32_t be = (uint32_t)m[0] << 24 | m[1] << 16 | m[2] << 8 | m[3];
    return le == 0xfeedfacfu || be == 0xcafebabeu;
}

/* PATH searched as execvp searches it, for posix_spawnp's Mac programs */
static int search_path(const char *file, char *out, size_t size)
{
    const char *path = getenv("PATH");
    if (!path)
        path = "/usr/bin:/bin";
    while (*path) {
        const char *colon = strchr(path, ':');
        size_t len = colon ? (size_t)(colon - path) : strlen(path);
        snprintf(out, size, "%.*s%s%s", (int)len, path, len ? "/" : "", file);
        if (access(out, X_OK) == 0)
            return 1;
        if (!colon)
            break;
        path = colon + 1;
    }
    return 0;
}

static int spawn(pid_t *pid, const char *file, int search, struct mac_actions *const *mfa,
                 struct mac_spawnattr *const *mattr, char *const argv[], char *const envp[])
{
    struct mac_spawnattr none = {0};
    const struct mac_spawnattr *ma = mattr && *mattr ? *mattr : &none;
    if (ma->flags & (MAC_POSIX_SPAWN_SETEXEC | MAC_POSIX_SPAWN_START_SUSPENDED))
        return spawn_err(ENOTSUP);
    char found[PATH_MAX];
    const char *path = file;
    if (search && !strchr(file, '/') && search_path(file, found, sizeof found))
        path = found;

    /* a Mac program runs through Ferry: ferry -- PROGRAM ARGS... */
    char self[PATH_MAX];
    char **mac_argv = NULL;
    const char *exe = path;
    if (strchr(path, '/') && is_mach_o(path)) {
        ssize_t n = readlink("/proc/self/exe", self, sizeof self - 1);
        if (n <= 0)
            return spawn_err(ENOEXEC);
        self[n] = 0;
        int argc = 0;
        while (argv && argv[argc])
            argc++;
        mac_argv = calloc(argc + 4, sizeof *mac_argv);
        if (!mac_argv)
            return spawn_err(ENOMEM);
        mac_argv[0] = "ferry";
        mac_argv[1] = "--";
        mac_argv[2] = (char *)path;
        for (int i = 1; i < argc; i++)
            mac_argv[i + 2] = argv[i];
        exe = self;
        search = 0;
    }

    posix_spawn_file_actions_t fa;
    posix_spawnattr_t attr;
    posix_spawn_file_actions_init(&fa);
    posix_spawnattr_init(&attr);
    int rc = 0;
    int kept[1024], nkept = 0;
    for (int i = 0; mfa && *mfa && i < (*mfa)->n && rc == 0; i++) {
        const struct action *a = &(*mfa)->a[i];
        switch (a->kind) {
        case A_OPEN:
            rc = posix_spawn_file_actions_addopen(&fa, a->fd, a->path, ferry_open_flags_to_linux(a->oflag), a->mode);
            break;
        case A_CLOSE: rc = posix_spawn_file_actions_addclose(&fa, a->fd); break;
        case A_DUP2: rc = posix_spawn_file_actions_adddup2(&fa, a->fd, a->newfd); break;
        case A_CHDIR: rc = posix_spawn_file_actions_addchdir_np(&fa, a->path); break;
        case A_FCHDIR: rc = posix_spawn_file_actions_addfchdir_np(&fa, a->fd); break;
        case A_INHERIT: break;
        }
        int target = a->kind == A_DUP2 ? a->newfd : a->kind == A_OPEN || a->kind == A_INHERIT ? a->fd : -1;
        if (target >= 0 && nkept < 1024)
            kept[nkept++] = target;
    }
    if (rc == 0 && (ma->flags & MAC_POSIX_SPAWN_CLOEXEC_DEFAULT)) {
        /* every descriptor open now that no action names, closed last */
        DIR *d = opendir("/proc/self/fd");
        int own = d ? dirfd(d) : -1;
        struct dirent *e;
        while (d && (e = readdir(d)) && rc == 0) {
            if (e->d_name[0] == '.')
                continue;
            int fd = atoi(e->d_name), keep = fd == own;
            for (int k = 0; k < nkept && !keep; k++)
                keep = kept[k] == fd;
            if (!keep)
                rc = posix_spawn_file_actions_addclose(&fa, fd);
        }
        if (d)
            closedir(d);
    }
    short flags = 0;
    if (ma->flags & MAC_POSIX_SPAWN_RESETIDS)
        flags |= POSIX_SPAWN_RESETIDS;
    if (ma->flags & MAC_POSIX_SPAWN_SETPGROUP) {
        flags |= POSIX_SPAWN_SETPGROUP;
        posix_spawnattr_setpgroup(&attr, ma->pgroup);
    }
    if (ma->flags & MAC_POSIX_SPAWN_SETSIGDEF) {
        sigset_t s;
        sigset_from_mac(ma->sigdefault, &s);
        flags |= POSIX_SPAWN_SETSIGDEF;
        posix_spawnattr_setsigdefault(&attr, &s);
    }
    if (ma->flags & MAC_POSIX_SPAWN_SETSIGMASK) {
        sigset_t s;
        sigset_from_mac(ma->sigmask, &s);
        flags |= POSIX_SPAWN_SETSIGMASK;
        posix_spawnattr_setsigmask(&attr, &s);
    }
    if (ma->flags & MAC_POSIX_SPAWN_SETSID)
        flags |= POSIX_SPAWN_SETSID;
    posix_spawnattr_setflags(&attr, flags);
    if (rc == 0) {
        char *const *av = mac_argv ? mac_argv : argv;
        fflush(NULL); /* what the program printed but hasn't written yet isn't the child's */
        rc = search ? posix_spawnp(pid, exe, &fa, &attr, av, envp) : posix_spawn(pid, exe, &fa, &attr, av, envp);
    }
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&attr);
    free(mac_argv);
    return rc ? spawn_err(rc) : 0;
}

static int mac_posix_spawn(pid_t *pid, const char *path, struct mac_actions *const *fa,
                           struct mac_spawnattr *const *attr, char *const argv[], char *const envp[])
{
    return spawn(pid, path, 0, fa, attr, argv, envp);
}

static int mac_posix_spawnp(pid_t *pid, const char *file, struct mac_actions *const *fa,
                            struct mac_spawnattr *const *attr, char *const argv[], char *const envp[])
{
    return spawn(pid, file, 1, fa, attr, argv, envp);
}

/* ---- glob and fnmatch -------------------------------------------------------------- */

struct mac_glob {
    size_t gl_pathc;
    int gl_matchc;
    size_t gl_offs;
    int gl_flags;
    char **gl_pathv;
    int (*gl_errfunc)(const char *, int);
    void (*gl_closedir)(void *);
    void *(*gl_readdir)(void *);
    void *(*gl_opendir)(const char *);
    int (*gl_lstat)(const char *, void *);
    int (*gl_stat)(const char *, void *);
};

#define MAC_GLOB_APPEND 0x0001
#define MAC_GLOB_DOOFFS 0x0002
#define MAC_GLOB_ERR 0x0004
#define MAC_GLOB_MARK 0x0008
#define MAC_GLOB_NOCHECK 0x0010
#define MAC_GLOB_NOSORT 0x0020
#define MAC_GLOB_BRACE 0x0080
#define MAC_GLOB_MAGCHAR 0x0100
#define MAC_GLOB_NOMAGIC 0x0200
#define MAC_GLOB_TILDE 0x0800
#define MAC_GLOB_NOESCAPE 0x2000

static __thread int (*glob_errfunc)(const char *, int);
static int glob_err_trampoline(const char *path, int err) { return glob_errfunc(path, ferry_errno_to_mac(err)); }

static int mac_glob(const char *pattern, int flags, int (*errfunc)(const char *, int), struct mac_glob *g)
{
    static const struct { int mac, lnx; } bits[] = {
        {MAC_GLOB_ERR, GLOB_ERR},       {MAC_GLOB_MARK, GLOB_MARK},       {MAC_GLOB_NOCHECK, GLOB_NOCHECK},
        {MAC_GLOB_NOSORT, GLOB_NOSORT}, {MAC_GLOB_BRACE, GLOB_BRACE},     {MAC_GLOB_NOMAGIC, GLOB_NOMAGIC},
        {MAC_GLOB_TILDE, GLOB_TILDE},   {MAC_GLOB_NOESCAPE, GLOB_NOESCAPE},
    };
    int lf = 0;
    for (size_t i = 0; i < sizeof bits / sizeof *bits; i++)
        if (flags & bits[i].mac)
            lf |= bits[i].lnx;
    glob_errfunc = errfunc;
    glob_t lg;
    memset(&lg, 0, sizeof lg);
    int rc = glob(pattern, lf, errfunc ? glob_err_trampoline : NULL, &lg);
    size_t offs = flags & MAC_GLOB_DOOFFS ? g->gl_offs : 0;
    size_t old = flags & MAC_GLOB_APPEND && g->gl_pathv ? g->gl_pathc : 0;
    if (!(flags & MAC_GLOB_APPEND) || !g->gl_pathv) {
        g->gl_pathv = NULL;
        g->gl_pathc = 0;
    }
    size_t add = rc == 0 ? lg.gl_pathc : 0;
    char **v = realloc(g->gl_pathv, (offs + old + add + 1) * sizeof *v);
    if (!v) {
        globfree(&lg);
        return -1; /* GLOB_NOSPACE */
    }
    if (!old)
        for (size_t i = 0; i < offs; i++)
            v[i] = NULL;
    for (size_t i = 0; i < add; i++)
        v[offs + old + i] = strdup(lg.gl_pathv[i]);
    v[offs + old + add] = NULL;
    g->gl_pathv = v;
    g->gl_pathc = old + add;
    g->gl_matchc = (int)add;
    g->gl_flags = (flags & ~MAC_GLOB_MAGCHAR) | (lg.gl_flags & GLOB_MAGCHAR ? MAC_GLOB_MAGCHAR : 0);
    globfree(&lg);
    switch (rc) {
    case 0: return 0;
    case GLOB_NOSPACE: return -1;
    case GLOB_ABORTED: return -2;
    case GLOB_NOMATCH: return -3;
    default: return -4; /* GLOB_NOSYS */
    }
}

static void mac_globfree(struct mac_glob *g)
{
    if (!g->gl_pathv)
        return;
    size_t offs = g->gl_flags & MAC_GLOB_DOOFFS ? g->gl_offs : 0;
    for (size_t i = 0; i < g->gl_pathc; i++)
        free(g->gl_pathv[offs + i]);
    free(g->gl_pathv);
    g->gl_pathv = NULL;
    g->gl_pathc = 0;
}

static int mac_fnmatch(const char *pattern, const char *string, int flags)
{
    int lf = (flags & 0x01 ? FNM_NOESCAPE : 0) | (flags & 0x02 ? FNM_PATHNAME : 0) | (flags & 0x04 ? FNM_PERIOD : 0) |
             (flags & 0x08 ? FNM_LEADING_DIR : 0) | (flags & 0x10 ? FNM_CASEFOLD : 0);
    return fnmatch(pattern, string, lf) == 0 ? 0 : 1; /* FNM_NOMATCH */
}

/* ---- termios ------------------------------------------------------------------------- */

/* A Mac's struct termios: four unsigned long flag words, 20 control
 * characters in BSD's order, and the speeds as baud rates. */
#define MAC_NCCS 20
struct mac_termios {
    unsigned long c_iflag, c_oflag, c_cflag, c_lflag;
    unsigned char c_cc[MAC_NCCS];
    unsigned long c_ispeed, c_ospeed;
};

struct flag_pair { unsigned long mac; tcflag_t lnx; };
static const struct flag_pair iflags[] = {
    {0x1, IGNBRK}, {0x2, BRKINT}, {0x4, IGNPAR}, {0x8, PARMRK}, {0x10, INPCK}, {0x20, ISTRIP}, {0x40, INLCR},
    {0x80, IGNCR}, {0x100, ICRNL}, {0x200, IXON}, {0x400, IXOFF}, {0x800, IXANY}, {0x2000, IMAXBEL},
    {0x4000, IUTF8},
};
static const struct flag_pair oflags[] = {
    {0x1, OPOST}, {0x2, ONLCR}, {0x4, XTABS}, {0x10, OCRNL}, {0x20, ONOCR}, {0x40, ONLRET},
};
static const struct flag_pair cflags[] = {
    {0x400, CSTOPB}, {0x800, CREAD}, {0x1000, PARENB}, {0x2000, PARODD}, {0x4000, HUPCL}, {0x8000, CLOCAL},
    {0x30000, CRTSCTS},
};
static const struct flag_pair lflags[] = {
    {0x1, ECHOKE}, {0x2, ECHOE}, {0x4, ECHOK}, {0x8, ECHO}, {0x10, ECHONL}, {0x20, ECHOPRT}, {0x40, ECHOCTL},
    {0x80, ISIG}, {0x100, ICANON}, {0x400, IEXTEN}, {0x800, EXTPROC}, {0x400000, TOSTOP},
    {0x800000, FLUSHO}, {0x20000000, PENDIN}, {0x80000000ul, NOFLSH},
};
/* the Mac's index of each of this system's control characters */
static const struct { int mac, lnx; } ccs[] = {
    {0, VEOF}, {1, VEOL}, {2, VEOL2}, {3, VERASE}, {4, VWERASE}, {5, VKILL}, {6, VREPRINT}, {8, VINTR},
    {9, VQUIT}, {10, VSUSP}, {12, VSTART}, {13, VSTOP}, {14, VLNEXT}, {15, VDISCARD}, {16, VMIN}, {17, VTIME},
};
static const struct { unsigned long baud; speed_t code; } speeds[] = {
    {0, B0}, {50, B50}, {75, B75}, {110, B110}, {134, B134}, {150, B150}, {200, B200}, {300, B300},
    {600, B600}, {1200, B1200}, {1800, B1800}, {2400, B2400}, {4800, B4800}, {9600, B9600},
    {19200, B19200}, {38400, B38400}, {57600, B57600}, {115200, B115200}, {230400, B230400},
};
#define COUNT(a) (sizeof (a) / sizeof *(a))

static tcflag_t flags_to_linux(unsigned long mac, const struct flag_pair *t, size_t n)
{
    tcflag_t out = 0;
    for (size_t i = 0; i < n; i++)
        if ((mac & t[i].mac) == t[i].mac)
            out |= t[i].lnx;
    return out;
}
static unsigned long flags_to_mac(tcflag_t lnx, const struct flag_pair *t, size_t n)
{
    unsigned long out = 0;
    for (size_t i = 0; i < n; i++)
        if ((lnx & t[i].lnx) == t[i].lnx)
            out |= t[i].mac;
    return out;
}
static unsigned long speed_to_mac(speed_t code)
{
    for (size_t i = 0; i < COUNT(speeds); i++)
        if (speeds[i].code == code)
            return speeds[i].baud;
    return 9600;
}
static speed_t speed_to_linux(unsigned long baud)
{
    for (size_t i = 0; i < COUNT(speeds); i++)
        if (speeds[i].baud == baud)
            return speeds[i].code;
    return (speed_t)-1;
}

static void termios_to_mac(const struct termios *l, struct mac_termios *m)
{
    memset(m, 0, sizeof *m);
    m->c_iflag = flags_to_mac(l->c_iflag, iflags, COUNT(iflags));
    m->c_oflag = flags_to_mac(l->c_oflag, oflags, COUNT(oflags));
    m->c_cflag = flags_to_mac(l->c_cflag, cflags, COUNT(cflags)) | ((l->c_cflag & CSIZE) / CS6 * 0x100);
    m->c_lflag = flags_to_mac(l->c_lflag, lflags, COUNT(lflags));
    for (size_t i = 0; i < MAC_NCCS; i++)
        m->c_cc[i] = 0xff; /* _POSIX_VDISABLE: what this system doesn't have */
    for (size_t i = 0; i < COUNT(ccs); i++)
        m->c_cc[ccs[i].mac] = l->c_cc[ccs[i].lnx];
    m->c_ispeed = speed_to_mac(cfgetispeed(l));
    m->c_ospeed = speed_to_mac(cfgetospeed(l));
}

static int termios_to_linux(const struct mac_termios *m, struct termios *l)
{
    memset(l, 0, sizeof *l);
    l->c_iflag = flags_to_linux(m->c_iflag, iflags, COUNT(iflags));
    l->c_oflag = flags_to_linux(m->c_oflag, oflags, COUNT(oflags));
    l->c_cflag = flags_to_linux(m->c_cflag, cflags, COUNT(cflags)) | ((m->c_cflag & 0x300) / 0x100 * CS6);
    l->c_lflag = flags_to_linux(m->c_lflag, lflags, COUNT(lflags));
    for (size_t i = 0; i < COUNT(ccs); i++)
        l->c_cc[ccs[i].lnx] = m->c_cc[ccs[i].mac];
    speed_t in = speed_to_linux(m->c_ispeed), out = speed_to_linux(m->c_ospeed);
    if (in == (speed_t)-1 || out == (speed_t)-1)
        return -1;
    cfsetispeed(l, in);
    cfsetospeed(l, out);
    return 0;
}

static int mac_tcgetattr(int fd, struct mac_termios *m)
{
    struct termios l;
    if (tcgetattr(fd, &l) < 0)
        return -1;
    termios_to_mac(&l, m);
    return 0;
}

static int mac_tcsetattr(int fd, int action, const struct mac_termios *m)
{
    struct termios l, now;
    /* TCSASOFT: leave the hardware settings (c_cflag and the speeds) alone */
    int soft = action & 0x10;
    action &= ~0x10;
    if (action < 0 || action > 2 || termios_to_linux(m, &l) < 0) {
        errno = EINVAL;
        return -1;
    }
    if (soft && tcgetattr(fd, &now) == 0) {
        l.c_cflag = now.c_cflag;
        cfsetispeed(&l, cfgetispeed(&now));
        cfsetospeed(&l, cfgetospeed(&now));
    }
    /* this system's own control characters that a Mac's struct can't hold */
    if (tcgetattr(fd, &now) == 0) {
        l.c_line = now.c_line;
        l.c_cc[VSWTC] = now.c_cc[VSWTC];
    }
    return tcsetattr(fd, action == 0 ? TCSANOW : action == 1 ? TCSADRAIN : TCSAFLUSH, &l);
}

/* the same settings cfmakeraw(3) gives on a Mac */
static void mac_cfmakeraw(struct mac_termios *m)
{
    m->c_iflag &= ~(0x1ul | 0x2 | 0x8 | 0x20 | 0x40 | 0x80 | 0x100 | 0x200 | 0x2000);
    m->c_iflag |= 0x4; /* IGNPAR */
    m->c_oflag &= ~0x1ul;
    m->c_lflag &= ~(0x8ul | 0x10 | 0x100 | 0x80 | 0x400 | 0x20 | 0x40 | 0x1 | 0x2 | 0x4);
    m->c_cflag &= ~(0x300ul | 0x1000);
    m->c_cflag |= 0x300 | 0x800; /* CS8, CREAD */
    m->c_cc[16] = 1; /* VMIN */
    m->c_cc[17] = 0; /* VTIME */
}

static unsigned long mac_cfgetispeed(const struct mac_termios *m) { return m->c_ispeed; }
static unsigned long mac_cfgetospeed(const struct mac_termios *m) { return m->c_ospeed; }
static int set_speed(unsigned long *field, unsigned long baud)
{
    if (speed_to_linux(baud) == (speed_t)-1) {
        errno = EINVAL;
        return -1;
    }
    *field = baud;
    return 0;
}
static int mac_cfsetispeed(struct mac_termios *m, unsigned long baud) { return set_speed(&m->c_ispeed, baud); }
static int mac_cfsetospeed(struct mac_termios *m, unsigned long baud) { return set_speed(&m->c_ospeed, baud); }
static int mac_cfsetspeed(struct mac_termios *m, unsigned long baud)
{
    return set_speed(&m->c_ispeed, baud) < 0 ? -1 : set_speed(&m->c_ospeed, baud);
}

/* a Mac numbers the queues and flow actions from 1, this system from 0 */
static int mac_tcflush(int fd, int which)
{
    if (which < 1 || which > 3) {
        errno = EINVAL;
        return -1;
    }
    return tcflush(fd, which == 1 ? TCIFLUSH : which == 2 ? TCOFLUSH : TCIOFLUSH);
}
static int mac_tcflow(int fd, int action)
{
    static const int to[] = {0, TCOOFF, TCOON, TCIOFF, TCION};
    if (action < 1 || action > 4) {
        errno = EINVAL;
        return -1;
    }
    return tcflow(fd, to[action]);
}

/* a pseudo-terminal's controlling side, opened with the Mac's O_ flags */
static int mac_posix_openpt(int flags) { return posix_openpt(ferry_open_flags_to_linux(flags)); }

const struct ferry_symbol ferry_libc_apps_symbols[] = {
    {"posix_openpt", mac_posix_openpt},
    /* the same on both systems */
    {"grantpt", grantpt},
    {"unlockpt", unlockpt},
    {"ptsname", ptsname},
    {"tcgetattr", mac_tcgetattr},
    {"tcsetattr", mac_tcsetattr},
    {"cfmakeraw", mac_cfmakeraw},
    {"cfgetispeed", mac_cfgetispeed},
    {"cfgetospeed", mac_cfgetospeed},
    {"cfsetispeed", mac_cfsetispeed},
    {"cfsetospeed", mac_cfsetospeed},
    {"cfsetspeed", mac_cfsetspeed},
    {"tcflush", mac_tcflush},
    {"tcflow", mac_tcflow},
    /* the same on both systems */
    {"tcdrain", tcdrain},
    {"tcsendbreak", tcsendbreak},
    {"tcgetpgrp", tcgetpgrp},
    {"tcsetpgrp", tcsetpgrp},
    {"tcgetsid", tcgetsid},
    {"mach_wait_until", mac_mach_wait_until},
    {"posix_spawn", mac_posix_spawn},
    {"posix_spawnp", mac_posix_spawnp},
    {"posix_spawn_file_actions_init", mac_posix_spawn_file_actions_init},
    {"posix_spawn_file_actions_destroy", mac_posix_spawn_file_actions_destroy},
    {"posix_spawn_file_actions_addopen", mac_posix_spawn_file_actions_addopen},
    {"posix_spawn_file_actions_addclose", mac_posix_spawn_file_actions_addclose},
    {"posix_spawn_file_actions_adddup2", mac_posix_spawn_file_actions_adddup2},
    {"posix_spawn_file_actions_addinherit_np", mac_posix_spawn_file_actions_addinherit_np},
    {"posix_spawn_file_actions_addchdir_np", mac_posix_spawn_file_actions_addchdir_np},
    {"posix_spawn_file_actions_addfchdir_np", mac_posix_spawn_file_actions_addfchdir_np},
    {"posix_spawnattr_init", mac_posix_spawnattr_init},
    {"posix_spawnattr_destroy", mac_posix_spawnattr_destroy},
    {"posix_spawnattr_setflags", mac_posix_spawnattr_setflags},
    {"posix_spawnattr_getflags", mac_posix_spawnattr_getflags},
    {"posix_spawnattr_setsigmask", mac_posix_spawnattr_setsigmask},
    {"posix_spawnattr_getsigmask", mac_posix_spawnattr_getsigmask},
    {"posix_spawnattr_setsigdefault", mac_posix_spawnattr_setsigdefault},
    {"posix_spawnattr_getsigdefault", mac_posix_spawnattr_getsigdefault},
    {"posix_spawnattr_setpgroup", mac_posix_spawnattr_setpgroup},
    {"posix_spawnattr_getpgroup", mac_posix_spawnattr_getpgroup},
    {"posix_spawnattr_setbinpref_np", mac_posix_spawnattr_setbinpref_np},
    {"posix_spawnattr_set_qos_class_np", mac_posix_spawnattr_set_qos_class_np},
    {"glob", mac_glob},
    {"globfree", mac_globfree},
    {"fnmatch", mac_fnmatch},
    {NULL, NULL},
};
