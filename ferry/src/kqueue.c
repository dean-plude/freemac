/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * kqueue and kevent, select, pselect and poll, as a Mac program calls them.
 *
 * Linux has no kqueue. A kqueue here is an epoll set, and each event the
 * program registers (a "knote") gets a descriptor of its own for epoll to
 * watch:
 *
 *   EVFILT_READ, EVFILT_WRITE   a duplicate of the descriptor, so a READ and
 *                               a WRITE on one descriptor can be watched
 *                               apart; EV_CLEAR is epoll's edge trigger. A
 *                               regular file is always ready, as on a Mac.
 *   EVFILT_TIMER                a timerfd
 *   EVFILT_SIGNAL               an eventfd that a handler for the signal
 *                               counts into (see "signals" below)
 *   EVFILT_PROC                 a pidfd, which is readable once the process
 *                               has exited (NOTE_EXIT, NOTE_EXITSTATUS)
 *   EVFILT_USER                 an eventfd that NOTE_TRIGGER sets
 *
 * EV_ONESHOT, EV_DISPATCH, EV_RECEIPT and the error events are done here.
 * Because a duplicate keeps the descriptor's file open, close() forgets the
 * descriptor's events first, as closing it does on a Mac.
 *
 * select and poll are Linux's, with the Mac's struct timeval (whose tv_usec
 * is 32 bits) and poll's POLLWRBAND converted; fd_set is laid out the same.
 *
 * Written from the kqueue(2), select(2) and poll(2) reference pages.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <linux/sockios.h>

#include "ferry.h"

#define EVFILT_READ_ (-1)
#define EVFILT_WRITE_ (-2)
#define EVFILT_AIO_ (-3)
#define EVFILT_VNODE_ (-4)
#define EVFILT_PROC_ (-5)
#define EVFILT_SIGNAL_ (-6)
#define EVFILT_TIMER_ (-7)
#define EVFILT_MACHPORT_ (-8)
#define EVFILT_FS_ (-9)
#define EVFILT_USER_ (-10)
#define EVFILT_VM_ (-12)
#define EVFILT_EXCEPT_ (-15)

#define EV_ADD_ 0x0001
#define EV_DELETE_ 0x0002
#define EV_ENABLE_ 0x0004
#define EV_DISABLE_ 0x0008
#define EV_ONESHOT_ 0x0010
#define EV_CLEAR_ 0x0020
#define EV_RECEIPT_ 0x0040
#define EV_DISPATCH_ 0x0080
#define EV_UDATA_SPECIFIC_ 0x0100
#define EV_ERROR_ 0x4000
#define EV_EOF_ 0x8000

#define NOTE_TRIGGER_ 0x01000000u
#define NOTE_FFAND_ 0x40000000u
#define NOTE_FFOR_ 0x80000000u
#define NOTE_FFCOPY_ 0xc0000000u
#define NOTE_FFCTRLMASK_ 0xc0000000u
#define NOTE_FFLAGSMASK_ 0x00ffffffu
#define NOTE_LOWAT_ 0x1u
#define NOTE_EXIT_ 0x80000000u
#define NOTE_EXITSTATUS_ 0x04000000u
#define NOTE_SECONDS_ 0x1u
#define NOTE_USECONDS_ 0x2u
#define NOTE_NSECONDS_ 0x4u
#define NOTE_ABSOLUTE_ 0x8u
#define NOTE_MACHTIME_ 0x100u

#define KEVENT_FLAG_IMMEDIATE_ 0x1u

struct knote {
    struct knote *next;
    uint64_t id; /* epoll's tag for it: knotes are found by id, so a stale event finds nothing */
    struct kevent64_s kev; /* as registered: ident, filter, flags, fflags, data, udata, ext */
    int pfd;               /* what epoll watches, or -1 */
    uint32_t events;
    int enabled, armed;
    int always;            /* a regular file: pfd is an eventfd that stays readable */
    int lsig;              /* EVFILT_SIGNAL: the Linux signal */
    uint32_t ufflags;      /* EVFILT_USER: its flags */
};

struct kq {
    struct kq *next;
    int fd;   /* the program's descriptor */
    int epfd; /* Ferry's own duplicate of it */
    int refs, closed;
    pthread_mutex_t lock;
    struct knote *knotes;
};

static pthread_mutex_t reg_lock = PTHREAD_MUTEX_INITIALIZER;
static struct kq *kqs;
static int fd_knotes; /* READ and WRITE knotes anywhere: close() needs to look only when there are some */
static uint64_t next_id = 1;

static int is_fd_filter(int f)
{
    return f == EVFILT_READ_ || f == EVFILT_WRITE_ || f == EVFILT_VNODE_ || f == EVFILT_EXCEPT_;
}

/* ---- signals ---------------------------------------------------------------------
 * A Mac kqueue sees every attempt to deliver a watched signal, even one the
 * program ignores (libdispatch's signal sources rely on that). While any
 * knote watches a signal, Ferry's handler is installed for it: it counts
 * the signal into each knote's eventfd, then does what the program asked
 * for the signal (its handler, nothing for SIG_IGN, the default action for
 * SIG_DFL). posix.c's sigaction goes through ferry_sigaction, which keeps
 * the program's choice here meanwhile. */

#define SIGW_MAX 32
static pthread_mutex_t sig_lock = PTHREAD_MUTEX_INITIALIZER;
static int sig_fds[65][SIGW_MAX]; /* eventfd + 1; 0 for none */
static int sig_watchers[65];
static struct sigaction sig_prog[65];
static int sig_busy;

static void default_action(int s)
{
    if (s == SIGCHLD || s == SIGURG || s == SIGWINCH || s == SIGCONT)
        return;
    struct sigaction dfl = {.sa_handler = SIG_DFL}, mine;
    sigaction(s, &dfl, &mine);
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, s);
    raise(s);
    pthread_sigmask(SIG_UNBLOCK, &set, NULL); /* ends the process, or stops it until SIGCONT */
    pthread_sigmask(SIG_BLOCK, &set, NULL);
    sigaction(s, &mine, NULL);
}

static void watch_handler(int s, siginfo_t *info, void *ctx)
{
    int saved = errno;
    __atomic_add_fetch(&sig_busy, 1, __ATOMIC_SEQ_CST);
    for (int i = 0; i < SIGW_MAX; i++) {
        int f = __atomic_load_n(&sig_fds[s][i], __ATOMIC_SEQ_CST);
        if (f > 0) {
            uint64_t one = 1;
            ssize_t r = write(f - 1, &one, sizeof one);
            (void)r;
        }
    }
    __atomic_sub_fetch(&sig_busy, 1, __ATOMIC_SEQ_CST);
    struct sigaction *p = &sig_prog[s];
    if (p->sa_flags & SA_SIGINFO)
        p->sa_sigaction(s, info, ctx);
    else if (p->sa_handler == SIG_DFL)
        default_action(s);
    else if (p->sa_handler != SIG_IGN)
        p->sa_handler(s);
    errno = saved;
}

static int watch_signal(int s, int efd)
{
    if (s <= 0 || s >= 65 || s == SIGKILL || s == SIGSTOP)
        return EINVAL;
    pthread_mutex_lock(&sig_lock);
    int slot = -1;
    for (int i = 0; i < SIGW_MAX && slot < 0; i++)
        if (!sig_fds[s][i])
            slot = i;
    if (slot < 0) {
        pthread_mutex_unlock(&sig_lock);
        return ENOMEM;
    }
    if (sig_watchers[s] == 0) {
        struct sigaction w = {.sa_sigaction = watch_handler, .sa_flags = SA_SIGINFO | SA_RESTART | SA_ONSTACK};
        if (sigaction(s, NULL, &sig_prog[s]) < 0 || (w.sa_mask = sig_prog[s].sa_mask, sigaction(s, &w, NULL) < 0)) {
            int e = errno;
            pthread_mutex_unlock(&sig_lock);
            return e;
        }
    }
    sig_watchers[s]++;
    __atomic_store_n(&sig_fds[s][slot], efd + 1, __ATOMIC_SEQ_CST);
    pthread_mutex_unlock(&sig_lock);
    return 0;
}

static void unwatch_signal(int s, int efd)
{
    pthread_mutex_lock(&sig_lock);
    for (int i = 0; i < SIGW_MAX; i++)
        if (sig_fds[s][i] == efd + 1) {
            __atomic_store_n(&sig_fds[s][i], 0, __ATOMIC_SEQ_CST);
            if (--sig_watchers[s] == 0)
                sigaction(s, &sig_prog[s], NULL);
            break;
        }
    while (__atomic_load_n(&sig_busy, __ATOMIC_SEQ_CST)) /* a handler may still be writing to efd */
        sched_yield();
    pthread_mutex_unlock(&sig_lock);
}

int ferry_sigaction(int s, const struct sigaction *act, struct sigaction *old)
{
    if (s > 0 && s < 65) {
        pthread_mutex_lock(&sig_lock);
        if (sig_watchers[s] > 0) {
            if (old)
                *old = sig_prog[s];
            if (act)
                sig_prog[s] = *act;
            pthread_mutex_unlock(&sig_lock);
            return 0;
        }
        pthread_mutex_unlock(&sig_lock);
    }
    return sigaction(s, act, old);
}

/* ---- knotes ---------------------------------------------------------------------- */

static void arm(struct kq *kq, struct knote *kn)
{
    if (kn->pfd < 0 || !kn->enabled || kn->armed)
        return;
    struct epoll_event e = {.events = kn->events, .data.u64 = kn->id};
    if (epoll_ctl(kq->epfd, EPOLL_CTL_ADD, kn->pfd, &e) == 0)
        kn->armed = 1;
}

static void disarm(struct kq *kq, struct knote *kn)
{
    if (!kn->armed)
        return;
    epoll_ctl(kq->epfd, EPOLL_CTL_DEL, kn->pfd, NULL);
    kn->armed = 0;
}

static void drain(int fd)
{
    uint64_t v;
    ssize_t r = read(fd, &v, sizeof v);
    (void)r;
}

static void free_knote(struct kq *kq, struct knote *kn)
{
    if (kq)
        disarm(kq, kn);
    if (kn->kev.filter == EVFILT_SIGNAL_ && kn->pfd >= 0)
        unwatch_signal(kn->lsig, kn->pfd);
    if (kn->pfd >= 0)
        close(kn->pfd);
    if (is_fd_filter(kn->kev.filter))
        __atomic_sub_fetch(&fd_knotes, 1, __ATOMIC_SEQ_CST);
    free(kn);
}

static void unlink_knote(struct kq *kq, struct knote *kn)
{
    for (struct knote **p = &kq->knotes; *p; p = &(*p)->next)
        if (*p == kn) {
            *p = kn->next;
            break;
        }
    free_knote(kq, kn);
}

static int64_t timer_ns(const struct knote *kn)
{
    int64_t v = kn->kev.data;
    uint32_t f = kn->kev.fflags;
    if (f & NOTE_SECONDS_)
        return v * 1000000000ll;
    if (f & NOTE_USECONDS_)
        return v * 1000ll;
    if (f & (NOTE_NSECONDS_ | NOTE_MACHTIME_)) /* mach_absolute_time counts nanoseconds here */
        return v;
    return v * 1000000ll;
}

static int timer_set(struct knote *kn)
{
    int64_t ns = timer_ns(kn);
    struct itimerspec it = {0};
    int flags = 0;
    if (ns <= 0)
        ns = 1; /* a zero interval fires straight away */
    it.it_value.tv_sec = ns / 1000000000ll;
    it.it_value.tv_nsec = ns % 1000000000ll;
    if (kn->kev.fflags & NOTE_ABSOLUTE_)
        flags = TFD_TIMER_ABSTIME;
    else if (!(kn->kev.flags & EV_ONESHOT_))
        it.it_interval = it.it_value;
    return timerfd_settime(kn->pfd, flags, &it, NULL) < 0 ? errno : 0;
}

static void user_fflags(struct knote *kn, uint32_t f)
{
    uint32_t v = f & NOTE_FFLAGSMASK_;
    switch (f & NOTE_FFCTRLMASK_) {
    case NOTE_FFAND_: kn->ufflags &= v; break;
    case NOTE_FFOR_: kn->ufflags |= v; break;
    case NOTE_FFCOPY_: kn->ufflags = v; break;
    default: break;
    }
    if (f & NOTE_TRIGGER_) {
        uint64_t one = 1;
        ssize_t r = write(kn->pfd, &one, sizeof one);
        (void)r;
    }
}

static int fd_events(const struct knote *kn)
{
    uint32_t e = kn->kev.filter == EVFILT_READ_ ? EPOLLIN | EPOLLRDHUP : EPOLLOUT;
    if (kn->always)
        e = EPOLLIN;
    return (int)(e | (kn->kev.flags & EV_CLEAR_ ? EPOLLET : 0));
}

static int pidfd_open_(pid_t pid) { return (int)syscall(SYS_pidfd_open, pid, 0); }

static unsigned once_notes;

/* The knote's own descriptor; an error number if it can't be watched. */
static int knote_setup(struct kq *kq, struct knote *kn)
{
    struct kevent64_s *k = &kn->kev;
    kn->pfd = -1;
    switch (k->filter) {
    case EVFILT_READ_:
    case EVFILT_WRITE_: {
        struct stat st;
        if (k->ident > INT32_MAX || fstat((int)k->ident, &st) < 0)
            return EBADF;
        kn->pfd = fcntl((int)k->ident, F_DUPFD_CLOEXEC, 0);
        if (kn->pfd < 0)
            return errno;
        kn->events = (uint32_t)fd_events(kn);
        struct epoll_event e = {.events = kn->events, .data.u64 = kn->id};
        if (epoll_ctl(kq->epfd, EPOLL_CTL_ADD, kn->pfd, &e) < 0) {
            if (errno != EPERM)
                return errno;
            /* a regular file or directory: always ready */
            close(kn->pfd);
            kn->always = 1;
            kn->pfd = eventfd(1, EFD_NONBLOCK | EFD_CLOEXEC);
            if (kn->pfd < 0)
                return errno;
            kn->events = (uint32_t)fd_events(kn);
            return 0;
        }
        epoll_ctl(kq->epfd, EPOLL_CTL_DEL, kn->pfd, NULL);
        if (k->filter == EVFILT_READ_ && (k->fflags & NOTE_LOWAT_) && S_ISSOCK(st.st_mode) && k->data > 0) {
            int low = (int)k->data;
            setsockopt((int)k->ident, SOL_SOCKET, SO_RCVLOWAT, &low, sizeof low);
        }
        return 0;
    }
    case EVFILT_TIMER_:
        kn->pfd = timerfd_create(k->fflags & NOTE_ABSOLUTE_ ? CLOCK_REALTIME : CLOCK_MONOTONIC,
                                 TFD_NONBLOCK | TFD_CLOEXEC);
        if (kn->pfd < 0)
            return errno;
        kn->events = EPOLLIN;
        return timer_set(kn);
    case EVFILT_SIGNAL_: {
        kn->lsig = ferry_signal_to_linux((int)k->ident);
        if (!kn->lsig || k->ident >= 32)
            return EINVAL;
        int efd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
        if (efd < 0)
            return errno;
        int e = watch_signal(kn->lsig, efd);
        if (e) {
            close(efd);
            return e;
        }
        kn->pfd = efd;
        kn->events = EPOLLIN;
        return 0;
    }
    case EVFILT_PROC_:
        if (k->ident == 0 || k->ident > INT32_MAX)
            return ESRCH;
        kn->pfd = pidfd_open_((pid_t)k->ident);
        if (kn->pfd < 0)
            return errno == ENOSYS ? ENOTSUP : ESRCH;
        kn->events = EPOLLIN;
        return 0;
    case EVFILT_USER_:
        kn->pfd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
        if (kn->pfd < 0)
            return errno;
        kn->events = EPOLLIN;
        user_fflags(kn, k->fflags);
        return 0;
    case EVFILT_VNODE_:
    case EVFILT_EXCEPT_:
    case EVFILT_FS_:
    case EVFILT_VM_:
    case EVFILT_MACHPORT_: {
        static const char *const names[] = {"VNODE", "EXCEPT", "FS", "VM", "MACHPORT"};
        int which = k->filter == EVFILT_VNODE_ ? 0 : k->filter == EVFILT_EXCEPT_ ? 1 : k->filter == EVFILT_FS_ ? 2
                  : k->filter == EVFILT_VM_ ? 3 : 4;
        if (!(__atomic_fetch_or(&once_notes, 1u << which, __ATOMIC_RELAXED) & (1u << which)))
            fprintf(stderr, "ferry: kevent's EVFILT_%s isn't supported yet; its events won't fire\n", names[which]);
        return 0;
    }
    default:
        return EINVAL;
    }
}

static struct knote *find_knote(struct kq *kq, uint64_t ident, int16_t filter)
{
    for (struct knote *kn = kq->knotes; kn; kn = kn->next)
        if (kn->kev.ident == ident && kn->kev.filter == filter)
            return kn;
    return NULL;
}

/* One entry of the change list; 0 or an error number. */
static int apply_change(struct kq *kq, const struct kevent64_s *c)
{
    struct knote *kn = find_knote(kq, c->ident, c->filter);
    if (c->flags & EV_DELETE_) {
        if (!kn)
            return ENOENT;
        unlink_knote(kq, kn);
        return 0;
    }
    if (c->flags & EV_ADD_) {
        if (!kn) {
            kn = calloc(1, sizeof *kn);
            if (!kn)
                return ENOMEM;
            kn->id = __atomic_fetch_add(&next_id, 1, __ATOMIC_RELAXED);
            kn->kev = *c;
            kn->kev.flags &= EV_ONESHOT_ | EV_CLEAR_ | EV_DISPATCH_ | EV_UDATA_SPECIFIC_;
            int e = knote_setup(kq, kn);
            if (e) {
                if (kn->pfd >= 0)
                    close(kn->pfd);
                free(kn);
                return e;
            }
            if (is_fd_filter(c->filter))
                __atomic_add_fetch(&fd_knotes, 1, __ATOMIC_SEQ_CST);
            kn->next = kq->knotes;
            kq->knotes = kn;
            kn->enabled = !(c->flags & EV_DISABLE_);
            arm(kq, kn);
            return 0;
        }
        /* adding it again changes it, and enables it */
        uint16_t keep = c->flags & (EV_ONESHOT_ | EV_CLEAR_ | EV_DISPATCH_ | EV_UDATA_SPECIFIC_);
        int was_clear = kn->kev.flags & EV_CLEAR_;
        kn->kev.flags = keep;
        kn->kev.udata = c->udata;
        kn->kev.ext[0] = c->ext[0];
        kn->kev.ext[1] = c->ext[1];
        if (c->filter == EVFILT_USER_) {
            kn->kev.data = c->data;
            user_fflags(kn, c->fflags);
        } else {
            kn->kev.fflags = c->fflags;
            kn->kev.data = c->data;
        }
        if (c->filter == EVFILT_TIMER_) {
            drain(kn->pfd);
            int e = timer_set(kn);
            if (e)
                return e;
        }
        if (is_fd_filter(c->filter) && kn->pfd >= 0 && was_clear != (keep & EV_CLEAR_)) {
            disarm(kq, kn);
            kn->events = (uint32_t)fd_events(kn);
        }
        kn->enabled = !(c->flags & EV_DISABLE_);
        if (kn->enabled)
            arm(kq, kn);
        else
            disarm(kq, kn);
        return 0;
    }
    if (!kn)
        return ENOENT;
    if (c->filter == EVFILT_USER_)
        user_fflags(kn, c->fflags);
    if (c->flags & EV_ENABLE_) {
        kn->enabled = 1;
        arm(kq, kn);
    }
    if (c->flags & EV_DISABLE_) {
        kn->enabled = 0;
        disarm(kq, kn);
    }
    return 0;
}

/* A child's exit as the Mac's wait status. */
static int64_t exit_status(int pidfd)
{
    siginfo_t si;
    memset(&si, 0, sizeof si);
    if (waitid((idtype_t)3 /* P_PIDFD */, (id_t)pidfd, &si, WEXITED | WNOWAIT | WNOHANG) < 0 || !si.si_pid)
        return 0;
    switch (si.si_code) {
    case CLD_EXITED: return (si.si_status & 0xff) << 8;
    case CLD_KILLED: return ferry_signal_to_mac(si.si_status);
    case CLD_DUMPED: return ferry_signal_to_mac(si.si_status) | 0x80;
    default: return 0;
    }
}

static int sock_error(int fd)
{
    int e = 0;
    socklen_t len = sizeof e;
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &e, &len) < 0)
        return 0;
    return ferry_errno_to_mac(e);
}

/* What a ready knote reports; 0 if nothing after all. */
static int knote_event(struct knote *kn, uint32_t rev, struct kevent64_s *out)
{
    *out = kn->kev;
    out->flags = kn->kev.flags & (EV_ONESHOT_ | EV_CLEAR_ | EV_DISPATCH_ | EV_UDATA_SPECIFIC_);
    out->fflags = 0;
    out->data = 0;
    int fd = (int)kn->kev.ident;
    switch (kn->kev.filter) {
    case EVFILT_READ_: {
        if (kn->always) {
            struct stat st;
            off_t at = lseek(fd, 0, SEEK_CUR);
            out->data = fstat(fd, &st) == 0 && at >= 0 ? st.st_size - at : 0;
            if (kn->kev.flags & EV_CLEAR_)
                drain(kn->pfd);
            break;
        }
        int listening = 0, n = 0;
        socklen_t len = sizeof listening;
        if (getsockopt(fd, SOL_SOCKET, SO_ACCEPTCONN, &listening, &len) == 0 && listening)
            n = 1; /* Linux doesn't say how many connections wait */
        else if (ioctl(fd, FIONREAD, &n) < 0)
            n = 0;
        out->data = n;
        if (rev & (EPOLLRDHUP | EPOLLHUP | EPOLLERR)) {
            out->flags |= EV_EOF_;
            out->fflags = (uint32_t)sock_error(fd);
        }
        break;
    }
    case EVFILT_WRITE_: {
        if (kn->always) {
            if (kn->kev.flags & EV_CLEAR_)
                drain(kn->pfd);
            break;
        }
        int size = 0, used = 0;
        socklen_t len = sizeof size;
        if (getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, &len) == 0) {
            if (ioctl(fd, SIOCOUTQ, &used) < 0)
                used = 0;
            out->data = size > used ? size - used : 0;
        } else if ((size = fcntl(fd, F_GETPIPE_SZ)) > 0) {
            if (ioctl(fd, FIONREAD, &used) < 0)
                used = 0;
            out->data = size > used ? size - used : 0;
        }
        if (rev & (EPOLLHUP | EPOLLERR)) {
            out->flags |= EV_EOF_;
            out->fflags = (uint32_t)sock_error(fd);
        }
        break;
    }
    case EVFILT_TIMER_:
    case EVFILT_SIGNAL_: {
        uint64_t count;
        if (read(kn->pfd, &count, sizeof count) != sizeof count || !count)
            return 0;
        out->data = (int64_t)count;
        break;
    }
    case EVFILT_PROC_:
        out->fflags = kn->kev.fflags & NOTE_EXIT_;
        if (kn->kev.fflags & NOTE_EXITSTATUS_) {
            out->fflags |= NOTE_EXITSTATUS_;
            out->data = exit_status(kn->pfd);
        }
        out->flags |= EV_EOF_ | EV_ONESHOT_;
        break;
    case EVFILT_USER_:
        out->fflags = kn->ufflags;
        out->data = kn->kev.data;
        if (kn->kev.flags & EV_CLEAR_) {
            drain(kn->pfd);
            kn->ufflags = 0;
        }
        break;
    default:
        return 0;
    }
    return 1;
}

/* ---- the kqueue itself ----------------------------------------------------------- */

static void kq_release(struct kq *kq)
{
    if (__atomic_sub_fetch(&kq->refs, 1, __ATOMIC_SEQ_CST))
        return;
    while (kq->knotes) {
        struct knote *kn = kq->knotes;
        kq->knotes = kn->next;
        free_knote(NULL, kn);
    }
    close(kq->epfd);
    pthread_mutex_destroy(&kq->lock);
    free(kq);
}

static struct kq *kq_get(int fd)
{
    pthread_mutex_lock(&reg_lock);
    struct kq *kq = kqs;
    while (kq && kq->fd != fd)
        kq = kq->next;
    if (kq)
        __atomic_add_fetch(&kq->refs, 1, __ATOMIC_SEQ_CST);
    pthread_mutex_unlock(&reg_lock);
    return kq;
}

int ferry_kqueue(void)
{
    struct kq *kq = calloc(1, sizeof *kq);
    if (!kq) {
        errno = ENOMEM;
        return -1;
    }
    kq->fd = epoll_create1(EPOLL_CLOEXEC);
    if (kq->fd < 0) {
        free(kq);
        return -1;
    }
    kq->epfd = fcntl(kq->fd, F_DUPFD_CLOEXEC, 0);
    if (kq->epfd < 0) {
        int e = errno;
        close(kq->fd);
        free(kq);
        errno = e;
        return -1;
    }
    /* A Mac kqueue isn't passed on to a program this one starts. */
    pthread_mutex_init(&kq->lock, NULL);
    kq->refs = 1;
    pthread_mutex_lock(&reg_lock);
    kq->next = kqs;
    kqs = kq;
    pthread_mutex_unlock(&reg_lock);
    return kq->fd;
}

static int64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000000000ll + t.tv_nsec;
}

static int wait_events(int epfd, struct epoll_event *evs, int max, int64_t timeout_ns)
{
    struct timespec ts, *tp = NULL;
    if (timeout_ns >= 0) {
        ts.tv_sec = timeout_ns / 1000000000ll;
        ts.tv_nsec = timeout_ns % 1000000000ll;
        tp = &ts;
    }
    long n = syscall(SYS_epoll_pwait2, epfd, evs, max, tp, NULL, (size_t)8);
    if (n < 0 && errno == ENOSYS) {
        int ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
        n = epoll_wait(epfd, evs, max, ms);
    }
    return (int)n;
}

int ferry_kevent64(int kqfd, const struct kevent64_s *changes, int nchanges, struct kevent64_s *events,
                   int nevents, unsigned int flags, const struct timespec *timeout)
{
    if (nchanges < 0 || nevents < 0) {
        errno = EINVAL;
        return -1;
    }
    struct kq *kq = kq_get(kqfd);
    if (!kq) {
        errno = EBADF;
        return -1;
    }
    int nout = 0;
    pthread_mutex_lock(&kq->lock);
    for (int i = 0; i < nchanges; i++) {
        int e = apply_change(kq, &changes[i]);
        if (e || (changes[i].flags & EV_RECEIPT_)) {
            if (nout < nevents) {
                events[nout] = changes[i];
                events[nout].flags = EV_ERROR_;
                events[nout].data = ferry_errno_to_mac(e);
                nout++;
            } else if (e) {
                pthread_mutex_unlock(&kq->lock);
                kq_release(kq);
                errno = e;
                return -1;
            }
        }
    }
    pthread_mutex_unlock(&kq->lock);
    if (nout || nevents == 0) {
        kq_release(kq);
        return nout;
    }
    int64_t limit = -1;
    if (flags & KEVENT_FLAG_IMMEDIATE_)
        limit = 0;
    else if (timeout) {
        if (timeout->tv_sec < 0 || timeout->tv_nsec < 0 || timeout->tv_nsec >= 1000000000l) {
            kq_release(kq);
            errno = EINVAL;
            return -1;
        }
        limit = timeout->tv_sec > INT64_MAX / 1000000000ll - 1 ? INT64_MAX / 2
              : timeout->tv_sec * 1000000000ll + timeout->tv_nsec;
    }
    int64_t deadline = limit >= 0 ? now_ns() + limit : -1;
    struct epoll_event evs[64];
    for (;;) {
        int64_t left = deadline < 0 ? -1 : deadline - now_ns();
        if (left < 0 && deadline >= 0)
            left = 0;
        int n = wait_events(kq->epfd, evs, nevents < 64 ? nevents : 64, left);
        if (n < 0) {
            int e = errno;
            kq_release(kq);
            errno = e;
            return -1;
        }
        pthread_mutex_lock(&kq->lock);
        for (int i = 0; i < n && nout < nevents; i++) {
            struct knote *kn = kq->knotes;
            while (kn && kn->id != evs[i].data.u64)
                kn = kn->next;
            if (!kn || !kn->armed)
                continue; /* deleted or disabled since */
            if (!knote_event(kn, evs[i].events, &events[nout]))
                continue;
            nout++;
            if (events[nout - 1].flags & EV_ONESHOT_)
                unlink_knote(kq, kn);
            else if (kn->kev.flags & EV_DISPATCH_) {
                kn->enabled = 0;
                disarm(kq, kn);
            }
        }
        pthread_mutex_unlock(&kq->lock);
        if (nout || n == 0 || (deadline >= 0 && now_ns() >= deadline))
            break;
    }
    kq_release(kq);
    return nout;
}

/* The Mac's struct kevent: the same fields at native width. */
struct mac_kevent {
    uintptr_t ident;
    int16_t filter;
    uint16_t flags;
    uint32_t fflags;
    intptr_t data;
    void *udata;
};

static int mac_kevent(int kq, const struct mac_kevent *changes, int nchanges, struct mac_kevent *events, int nevents,
                      const struct timespec *timeout)
{
    if (nchanges < 0 || nevents < 0) {
        errno = EINVAL;
        return -1;
    }
    struct kevent64_s small_in[16], small_out[16];
    struct kevent64_s *in = nchanges <= 16 ? small_in : calloc((size_t)nchanges, sizeof *in);
    struct kevent64_s *out = nevents <= 16 ? small_out : calloc((size_t)nevents, sizeof *out);
    if (!in || !out) {
        if (in != small_in)
            free(in);
        if (out != small_out)
            free(out);
        errno = ENOMEM;
        return -1;
    }
    for (int i = 0; i < nchanges; i++)
        in[i] = (struct kevent64_s){.ident = changes[i].ident, .filter = changes[i].filter,
                                    .flags = changes[i].flags, .fflags = changes[i].fflags,
                                    .data = changes[i].data, .udata = (uint64_t)(uintptr_t)changes[i].udata};
    int n = ferry_kevent64(kq, in, nchanges, out, nevents, 0, timeout);
    for (int i = 0; i < n; i++)
        events[i] = (struct mac_kevent){.ident = (uintptr_t)out[i].ident, .filter = out[i].filter,
                                        .flags = out[i].flags, .fflags = out[i].fflags,
                                        .data = (intptr_t)out[i].data, .udata = (void *)(uintptr_t)out[i].udata};
    if (in != small_in)
        free(in);
    if (out != small_out)
        free(out);
    return n;
}

static int mac_kevent64(int kq, const struct kevent64_s *changes, int nchanges, struct kevent64_s *events,
                        int nevents, unsigned int flags, const struct timespec *timeout)
{
    return ferry_kevent64(kq, changes, nchanges, events, nevents, flags, timeout);
}

/* ---- close ---------------------------------------------------------------------- */

/* Closing a descriptor removes its events from every kqueue, and closing
 * a kqueue ends it. */
static int mac_close(int fd)
{
    ferry_socket_closed(fd);
    struct kq *gone = NULL;
    pthread_mutex_lock(&reg_lock);
    for (struct kq **p = &kqs; *p; p = &(*p)->next)
        if ((*p)->fd == fd) {
            gone = *p;
            *p = gone->next;
            break;
        }
    if (__atomic_load_n(&fd_knotes, __ATOMIC_SEQ_CST) > 0)
        for (struct kq *kq = kqs; kq; kq = kq->next) {
            pthread_mutex_lock(&kq->lock);
            for (struct knote **p = &kq->knotes; *p;) {
                struct knote *kn = *p;
                if (is_fd_filter(kn->kev.filter) && kn->kev.ident == (uint64_t)fd) {
                    *p = kn->next;
                    free_knote(kq, kn);
                } else {
                    p = &kn->next;
                }
            }
            pthread_mutex_unlock(&kq->lock);
        }
    pthread_mutex_unlock(&reg_lock);
    int rc = close(fd);
    if (gone)
        kq_release(gone);
    return rc;
}

/* ---- select and poll ------------------------------------------------------------ */

struct mac_timeval { long tv_sec; int32_t tv_usec, pad; };

/* The Mac's fd_set is 1024 bits laid out as Linux's; only the timeout
 * differs, and a Mac's select leaves it as it was. */
static int mac_select(int n, fd_set *r, fd_set *w, fd_set *e, const struct mac_timeval *tv)
{
    struct timeval t, *tp = NULL;
    if (tv) {
        if (tv->tv_sec < 0 || tv->tv_usec < 0 || tv->tv_usec >= 1000000) {
            errno = EINVAL;
            return -1;
        }
        t.tv_sec = tv->tv_sec;
        t.tv_usec = tv->tv_usec;
        tp = &t;
    }
    return select(n, r, w, e, tp);
}

static int mac_pselect(int n, fd_set *r, fd_set *w, fd_set *e, const struct timespec *ts, const uint32_t *mask)
{
    sigset_t set;
    if (mask) {
        sigemptyset(&set);
        for (int i = 1; i < 32; i++)
            if ((*mask & (1u << (i - 1))) && ferry_signal_to_linux(i))
                sigaddset(&set, ferry_signal_to_linux(i));
    }
    return pselect(n, r, w, e, ts, mask ? &set : NULL);
}

/* poll's bits match up to POLLRDBAND; above it the Mac's POLLWRBAND is 0x100. */
#define MAC_POLLWRBAND 0x100
static int mac_poll(struct pollfd *fds, unsigned int n, int timeout) /* the Mac's nfds_t is 32 bits */
{
    int convert = 0;
    for (unsigned int i = 0; i < n && !convert; i++)
        convert = (fds[i].events & ~0xff) != 0;
    if (!convert)
        return poll(fds, n, timeout);
    short *saved = malloc(n * sizeof *saved);
    if (!saved) {
        errno = ENOMEM;
        return -1;
    }
    for (unsigned int i = 0; i < n; i++) {
        saved[i] = fds[i].events;
        fds[i].events = (short)((fds[i].events & 0xff) | (fds[i].events & MAC_POLLWRBAND ? POLLWRBAND : 0));
    }
    int rc = poll(fds, n, timeout);
    for (unsigned int i = 0; i < n; i++) {
        fds[i].events = saved[i];
        if (rc > 0)
            fds[i].revents = (short)((fds[i].revents & 0xff) | (fds[i].revents & POLLWRBAND ? MAC_POLLWRBAND : 0));
    }
    free(saved);
    return rc;
}

const struct ferry_symbol ferry_kqueue_symbols[] = {
    {"kqueue", ferry_kqueue},
    {"kevent", mac_kevent},
    {"kevent64", mac_kevent64},
    {"close", mac_close},
    {"select", mac_select},
    {"pselect", mac_pselect},
    {"poll", mac_poll},
    {NULL, NULL},
};
