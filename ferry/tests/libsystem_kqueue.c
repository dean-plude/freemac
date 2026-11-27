/* Ferry test: kqueue and kevent with the Mac's filters, flags and
 * structures: descriptors (pipes, sockets, files), timers, signals, a
 * child's exit and user events, the change list's errors and receipts,
 * EV_ONESHOT, EV_DISPATCH and EV_CLEAR, and a kevent woken from another
 * thread. */
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x)                                                                                              \
    do {                                                                                                      \
        if (!(x)) {                                                                                           \
            printf("FAILED line %d: %s (errno %d)\n", __LINE__, #x, errno);                                    \
            exit(1);                                                                                          \
        }                                                                                                     \
    } while (0)

static const struct timespec zero = {0, 0};
static int kq;

static int change(uintptr_t ident, int filter, int flags, unsigned fflags, intptr_t data, void *udata)
{
    struct kevent k;
    EV_SET(&k, ident, filter, flags, fflags, data, udata);
    return kevent(kq, &k, 1, NULL, 0, NULL);
}

static int poll_one(struct kevent *out, long ms)
{
    struct timespec t = {ms / 1000, (ms % 1000) * 1000000};
    memset(out, 0, sizeof *out);
    return kevent(kq, NULL, 0, out, 1, &t);
}

static void descriptors(void)
{
    int p[2];
    CHECK(pipe(p) == 0);
    static int tag;
    CHECK(change(p[0], EVFILT_READ, EV_ADD, 0, 0, &tag) == 0);
    struct kevent ev;
    printf("empty pipe: %d events\n", kevent(kq, NULL, 0, &ev, 1, &zero));
    CHECK(write(p[1], "abc", 3) == 3);
    int n = poll_one(&ev, 1000);
    printf("pipe READ: %d event, ident ok %d filter %d data %ld udata ok %d eof %d\n", n, ev.ident == (uintptr_t)p[0],
           ev.filter, (long)ev.data, ev.udata == &tag, (ev.flags & EV_EOF) != 0);
    n = poll_one(&ev, 0);
    printf("level-triggered: again %d\n", n);
    char buf[8];
    CHECK(read(p[0], buf, 3) == 3);
    printf("after reading it: %d\n", poll_one(&ev, 0));

    /* EV_CLEAR: once per change */
    CHECK(change(p[0], EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, &tag) == 0);
    CHECK(write(p[1], "x", 1) == 1);
    int first = poll_one(&ev, 1000), second = poll_one(&ev, 0);
    CHECK(write(p[1], "y", 1) == 1);
    int third = poll_one(&ev, 1000);
    printf("EV_CLEAR: %d, then %d, after more data %d (data %ld)\n", first, second, third, (long)ev.data);

    /* the other end closed */
    close(p[1]);
    n = poll_one(&ev, 1000);
    printf("writer closed: %d event, EV_EOF %d data %ld\n", n, (ev.flags & EV_EOF) != 0, (long)ev.data);

    /* closing a descriptor removes its events */
    close(p[0]);
    errno = 0;
    printf("after close, EV_DELETE: %d errno %d (ENOENT %d)\n", change(p[0], EVFILT_READ, EV_DELETE, 0, 0, NULL), errno,
           ENOENT);

    /* a socket's WRITE says how much room there is */
    int sv[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0);
    CHECK(change(sv[0], EVFILT_WRITE, EV_ADD, 0, 0, NULL) == 0);
    CHECK(change(sv[0], EVFILT_READ, EV_ADD, 0, 0, NULL) == 0);
    n = poll_one(&ev, 1000);
    printf("socket WRITE: %d event, filter %d, room %d\n", n, ev.filter, ev.data > 0);
    CHECK(write(sv[1], "hello", 5) == 5);
    struct kevent two[4];
    struct timespec sec = {1, 0};
    n = kevent(kq, NULL, 0, two, 4, &sec);
    int r = 0, w = 0;
    for (int i = 0; i < n; i++) {
        if (two[i].filter == EVFILT_READ)
            r = (int)two[i].data;
        if (two[i].filter == EVFILT_WRITE)
            w = 1;
    }
    printf("READ and WRITE on one socket: %d events, read data %d, write %d\n", n, r, w);
    close(sv[1]);
    n = poll_one(&ev, 1000);
    printf("peer closed: EV_EOF %d\n", (ev.flags & EV_EOF) != 0);
    close(sv[0]);

    /* a regular file is always readable: data is what's left */
    char path[64];
    snprintf(path, sizeof path, "/tmp/ferry-kq-%d", (int)getpid());
    int f = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    CHECK(f >= 0);
    CHECK(write(f, "0123456789", 10) == 10);
    lseek(f, 4, SEEK_SET);
    CHECK(change(f, EVFILT_READ, EV_ADD, 0, 0, NULL) == 0);
    n = poll_one(&ev, 0);
    printf("file READ: %d event, data %ld\n", n, (long)ev.data);
    close(f);
    unlink(path);
}

static void changes(void)
{
    int p[2];
    CHECK(pipe(p) == 0);
    struct kevent in[3], out[3];
    EV_SET(&in[0], p[0], EVFILT_READ, EV_ADD | EV_RECEIPT, 0, 0, NULL);
    EV_SET(&in[1], 9999, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&in[2], p[1], EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
    int n = kevent(kq, in, 3, out, 3, NULL);
    printf("change list: %d results\n", n);
    for (int i = 0; i < n; i++)
        printf("  ident ok %d EV_ERROR %d data %ld\n", out[i].ident == in[i].ident, (out[i].flags & EV_ERROR) != 0,
               (long)out[i].data);
    errno = 0;
    printf("an error with no room: %d errno %d (EBADF %d)\n", kevent(kq, &in[1], 1, NULL, 0, NULL), errno, EBADF);
    errno = 0;
    printf("an unknown filter: %d errno %d\n", change(1, -99, EV_ADD, 0, 0, NULL), errno);

    /* EV_ONESHOT goes after one event */
    CHECK(write(p[1], "a", 1) == 1);
    CHECK(change(p[0], EVFILT_READ, EV_ADD | EV_ONESHOT, 0, 0, NULL) == 0);
    struct kevent ev;
    int a = poll_one(&ev, 1000), b = poll_one(&ev, 0);
    errno = 0;
    int gone = change(p[0], EVFILT_READ, EV_DELETE, 0, 0, NULL);
    printf("EV_ONESHOT: %d then %d, then deleting: %d errno %d\n", a, b, gone, errno);

    /* EV_DISPATCH is disabled after one, until enabled again */
    CHECK(change(p[0], EVFILT_READ, EV_ADD | EV_DISPATCH, 0, 0, NULL) == 0);
    a = poll_one(&ev, 1000);
    b = poll_one(&ev, 0);
    CHECK(change(p[0], EVFILT_READ, EV_ENABLE, 0, 0, NULL) == 0);
    int c = poll_one(&ev, 1000);
    printf("EV_DISPATCH: %d then %d, enabled again %d\n", a, b, c);
    CHECK(change(p[0], EVFILT_READ, EV_DISABLE, 0, 0, NULL) == 0);
    printf("EV_DISABLE: %d\n", poll_one(&ev, 0));
    CHECK(change(p[0], EVFILT_READ, EV_DELETE, 0, 0, NULL) == 0);
    close(p[0]);
    close(p[1]);
}

static long elapsed_ms(struct timespec *since)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - since->tv_sec) * 1000 + (now.tv_nsec - since->tv_nsec) / 1000000;
}

static void timers(void)
{
    struct kevent ev;
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    CHECK(change(1, EVFILT_TIMER, EV_ADD | EV_ONESHOT, 0, 50, (void *)0x51) == 0);
    int n = poll_one(&ev, 2000);
    long ms = elapsed_ms(&start);
    printf("50 ms timer: %d event after 45-1000 ms %d, data %ld udata %p\n", n, ms >= 45 && ms < 1000, (long)ev.data,
           ev.udata);
    printf("one-shot: then %d\n", poll_one(&ev, 100));

    CHECK(change(2, EVFILT_TIMER, EV_ADD, NOTE_USECONDS, 20000, NULL) == 0);
    usleep(110000);
    n = poll_one(&ev, 1000);
    printf("20 ms repeating timer after 110 ms: %d event, counted 3 or more %d\n", n, ev.data >= 3);
    n = poll_one(&ev, 1000);
    printf("and again: %d, data %ld\n", n, (long)ev.data);
    CHECK(change(2, EVFILT_TIMER, EV_DELETE, 0, 0, NULL) == 0);

    CHECK(change(3, EVFILT_TIMER, EV_ADD | EV_ONESHOT, NOTE_SECONDS | NOTE_ABSOLUTE, time(NULL) - 5, NULL) == 0);
    n = poll_one(&ev, 1000);
    printf("absolute time in the past: %d event, ident %lu\n", n, (unsigned long)ev.ident);

    CHECK(change(4, EVFILT_TIMER, EV_ADD, NOTE_NSECONDS, 30000000, NULL) == 0);
    CHECK(change(4, EVFILT_TIMER, EV_DISABLE, 0, 0, NULL) == 0);
    printf("disabled timer: %d\n", poll_one(&ev, 100));
    CHECK(change(4, EVFILT_TIMER, EV_DELETE, 0, 0, NULL) == 0);
}

static volatile sig_atomic_t handled;
static void on_usr2(int s) { handled++; }

static void signals(void)
{
    struct kevent ev;
    signal(SIGUSR1, SIG_IGN);
    CHECK(change(SIGUSR1, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL) == 0);
    raise(SIGUSR1);
    kill(getpid(), SIGUSR1);
    int n = poll_one(&ev, 1000);
    printf("ignored SIGUSR1 sent twice: %d event, ident %lu data %ld\n", n, (unsigned long)ev.ident, (long)ev.data);
    printf("then %d\n", poll_one(&ev, 0));
    void *was = (void *)signal(SIGUSR1, SIG_IGN);
    printf("the program's disposition is still SIG_IGN %d\n", was == (void *)SIG_IGN);
    CHECK(change(SIGUSR1, EVFILT_SIGNAL, EV_DELETE, 0, 0, NULL) == 0);
    raise(SIGUSR1);
    printf("deleted, SIGUSR1 still ignored: alive\n");

    /* a handler the program sets while the kqueue watches still runs */
    CHECK(change(SIGUSR2, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL) == 0);
    signal(SIGUSR2, on_usr2);
    raise(SIGUSR2);
    n = poll_one(&ev, 1000);
    printf("SIGUSR2 with a handler: handler ran %d, event %d data %ld\n", (int)handled, n, (long)ev.data);
    CHECK(change(SIGUSR2, EVFILT_SIGNAL, EV_DELETE, 0, 0, NULL) == 0);
    raise(SIGUSR2);
    printf("deleted: the handler alone %d\n", (int)handled);
    signal(SIGUSR2, SIG_DFL);
    errno = 0;
    printf("SIGKILL can't be watched: %d errno %d\n", change(SIGKILL, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL), errno);
}

static void processes(void)
{
    struct kevent ev;
    int go[2];
    CHECK(pipe(go) == 0);
    pid_t child = fork();
    if (child == 0) {
        char c;
        read(go[0], &c, 1);
        _exit(7);
    }
    CHECK(change(child, EVFILT_PROC, EV_ADD, NOTE_EXIT | NOTE_EXITSTATUS, 0, NULL) == 0);
    printf("child running: %d events\n", poll_one(&ev, 0));
    CHECK(write(go[1], "g", 1) == 1);
    int n = poll_one(&ev, 5000);
    printf("child exited: %d event, ident ok %d NOTE_EXIT %d NOTE_EXITSTATUS %d status %d, EV_EOF %d\n", n,
           ev.ident == (uintptr_t)child, (ev.fflags & NOTE_EXIT) != 0, (ev.fflags & NOTE_EXITSTATUS) != 0,
           WIFEXITED((int)ev.data) ? WEXITSTATUS((int)ev.data) : -1, (ev.flags & EV_EOF) != 0);
    errno = 0;
    printf("the event is gone: %d errno %d\n", change(child, EVFILT_PROC, EV_DELETE, 0, 0, NULL), errno);
    int status = 0;
    printf("waitpid still reaps it: %d status %d\n", waitpid(child, &status, 0) == child, WEXITSTATUS(status));
    close(go[0]);
    close(go[1]);
    errno = 0;
    printf("no such process: %d errno %d (ESRCH %d)\n", change(child, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL), errno,
           ESRCH);
}

static void *trigger_later(void *arg)
{
    usleep(100000);
    struct kevent k;
    EV_SET(&k, 42, EVFILT_USER, 0, NOTE_TRIGGER | NOTE_FFOR | 0x10, 0, NULL);
    kevent(kq, &k, 1, NULL, 0, NULL);
    return NULL;
}

static void user_events(void)
{
    struct kevent ev;
    int a0;
    CHECK(change(42, EVFILT_USER, EV_ADD | EV_CLEAR, NOTE_FFCOPY | 0x3, 0, NULL) == 0);
    printf("user event, not triggered: %d\n", poll_one(&ev, 0));
    CHECK(change(42, EVFILT_USER, 0, NOTE_TRIGGER | NOTE_FFAND | 0x1, 0, NULL) == 0);
    int n = poll_one(&ev, 1000);
    printf("triggered: %d event, fflags 0x%x\n", n, ev.fflags);
    printf("EV_CLEAR: then %d\n", poll_one(&ev, 0));

    pthread_t t;
    pthread_create(&t, NULL, trigger_later, NULL);
    n = poll_one(&ev, 5000);
    pthread_join(t, NULL);
    printf("triggered from another thread while waiting: %d event, fflags 0x%x\n", n, ev.fflags);
    /* a trigger that adds the event again keeps the EV_CLEAR it was first
     * added with: Rust's mio wakes its thread this way, and spun when the
     * trigger lost it (freemac 1.268) */
    CHECK(change(42, EVFILT_USER, EV_ADD, NOTE_TRIGGER, 0, NULL) == 0);
    a0 = poll_one(&ev, 1000);
    printf("triggered by adding again: %d event, EV_CLEAR kept: then %d\n", a0, poll_one(&ev, 0));
    CHECK(change(42, EVFILT_USER, EV_DELETE, 0, 0, NULL) == 0);

    CHECK(change(43, EVFILT_USER, EV_ADD, 0, 0, NULL) == 0);
    CHECK(change(43, EVFILT_USER, 0, NOTE_TRIGGER, 0, NULL) == 0);
    int a = poll_one(&ev, 1000), b = poll_one(&ev, 0);
    printf("without EV_CLEAR it stays triggered: %d %d\n", a, b);
    CHECK(change(43, EVFILT_USER, EV_DELETE, 0, 0, NULL) == 0);

    /* kevent64 carries 64-bit user data and the two ext words */
    struct kevent64_s k64, out64;
    EV_SET64(&k64, 44, EVFILT_USER, EV_ADD | EV_ONESHOT, NOTE_TRIGGER, 0, 0x123456789abcdefull, 11, 22);
    CHECK(kevent64(kq, &k64, 1, NULL, 0, 0, NULL) == 0);
    n = kevent64(kq, NULL, 0, &out64, 1, KEVENT_FLAG_IMMEDIATE, NULL);
    printf("kevent64: %d event, udata %llx ext %llu %llu\n", n, (unsigned long long)out64.udata,
           (unsigned long long)out64.ext[0], (unsigned long long)out64.ext[1]);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("struct kevent %zu bytes, struct kevent64_s %zu\n", sizeof(struct kevent), sizeof(struct kevent64_s));
    kq = kqueue();
    CHECK(kq >= 0);
    descriptors();
    changes();
    timers();
    signals();
    processes();
    user_events();
    printf("closing the kqueue: %d\n", close(kq));
    errno = 0;
    printf("kevent on it after: %d errno %d\n", kevent(kq, NULL, 0, NULL, 0, &zero), errno);
    return 0;
}
