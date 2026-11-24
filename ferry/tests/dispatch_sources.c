/* Ferry test: libdispatch's read, write, signal and process sources on real
 * descriptors, signals and a child process, with their handlers on the
 * sources' queues; suspending and resuming; cancel handlers; and a read
 * source on the main queue served by dispatch_main. */
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <pthread.h>
#include <unistd.h>

#define SECONDS(n) dispatch_time(DISPATCH_TIME_NOW, (int64_t)(n) * 1000000000ll)

static void reads(void)
{
    int p[2];
    pipe(p);
    int rfd = p[0], wfd = p[1];
    fcntl(rfd, F_SETFL, O_NONBLOCK);
    dispatch_queue_t q = dispatch_queue_create("reads", NULL);
    dispatch_semaphore_t got = dispatch_semaphore_create(0), done = dispatch_semaphore_create(0);
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, rfd, 0, q);
    __block int calls = 0, on_queue = 1;
    static char text[64];
    __block size_t have = 0;
    __block unsigned long first_data = 0;
    static int qkey;
    dispatch_queue_set_specific(q, &qkey, &qkey, NULL);
    dispatch_source_set_event_handler(s, ^{
        unsigned long avail = dispatch_source_get_data(s);
        if (!calls++)
            first_data = avail;
        if (dispatch_get_specific(&qkey) != &qkey)
            on_queue = 0;
        ssize_t n = read(rfd, text + have, sizeof text - 1 - have);
        if (n > 0) {
            have += (size_t)n;
            dispatch_semaphore_signal(got);
        } else if (n == 0) {
            dispatch_source_cancel(s);
        }
    });
    dispatch_source_set_cancel_handler(s, ^{
        close(rfd);
        dispatch_semaphore_signal(done);
    });
    printf("read source: handle matches %d mask %lu\n", dispatch_source_get_handle(s) == (uintptr_t)rfd,
           dispatch_source_get_mask(s));
    dispatch_resume(s);
    usleep(50000);
    printf("nothing to read: %d calls\n", calls);
    write(wfd, "abc", 3);
    long w = dispatch_semaphore_wait(got, SECONDS(5));
    printf("after a write: waited %ld, data %lu, read \"%s\", on its queue %d\n", w, first_data, text, on_queue);

    /* suspended, it holds the event until resumed */
    dispatch_suspend(s);
    write(wfd, "def", 3);
    usleep(100000);
    printf("suspended: text still \"%s\"\n", text);
    dispatch_resume(s);
    w = dispatch_semaphore_wait(got, SECONDS(5));
    printf("resumed: waited %ld, read \"%s\"\n", w, text);

    close(wfd);
    w = dispatch_semaphore_wait(done, SECONDS(5));
    printf("writer closed: the handler saw the end and cancelled, cancel handler ran %ld, testcancel %ld\n", w,
           dispatch_source_testcancel(s));
    dispatch_release(s);
    dispatch_release(q);
}

static void writes(void)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    int mine = sv[0];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, mine, 0, q);
    __block unsigned long room = 0;
    dispatch_source_set_event_handler(s, ^{
        room = dispatch_source_get_data(s);
        write(mine, "ping", 4);
        dispatch_source_cancel(s);
    });
    dispatch_source_set_cancel_handler(s, ^{
        dispatch_semaphore_signal(done);
    });
    dispatch_resume(s);
    long w = dispatch_semaphore_wait(done, SECONDS(5));
    char buf[8] = {0};
    read(sv[1], buf, 4);
    printf("write source: waited %ld, room reported %d, peer read \"%s\"\n", w, room > 0, buf);
    dispatch_release(s);
    close(sv[0]);
    close(sv[1]);
}

static void signals(void)
{
    signal(SIGUSR1, SIG_IGN);
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    dispatch_queue_t q = dispatch_queue_create("signals", NULL);
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, q);
    __block unsigned long total = 0;
    dispatch_source_set_event_handler(s, ^{
        total += dispatch_source_get_data(s);
        if (total >= 3)
            dispatch_semaphore_signal(got);
    });
    dispatch_resume(s);
    raise(SIGUSR1);
    kill(getpid(), SIGUSR1);
    raise(SIGUSR1);
    long w = dispatch_semaphore_wait(got, SECONDS(5));
    printf("signal source: waited %ld, counted %lu SIGUSR1, handle %lu\n", w, total,
           (unsigned long)dispatch_source_get_handle(s));
    dispatch_source_cancel(s);
    dispatch_release(s);
    raise(SIGUSR1);
    printf("cancelled, SIGUSR1 still ignored: alive\n");
    printf("a source for signal 0: %s\n", dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, 0, 0, q) ? "made" : "NULL");
    dispatch_release(q);
}

static void processes(void)
{
    int go[2];
    pipe(go);
    pid_t child = fork();
    if (child == 0) {
        char c;
        read(go[0], &c, 1);
        _exit(5);
    }
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)child, DISPATCH_PROC_EXIT,
                                                 dispatch_get_global_queue(0, 0));
    __block unsigned long flags = 0;
    dispatch_source_set_event_handler(s, ^{
        flags = dispatch_source_get_data(s);
        dispatch_semaphore_signal(got);
    });
    dispatch_resume(s);
    usleep(50000);
    printf("process source: nothing while it runs %d\n", flags == 0);
    write(go[1], "g", 1);
    long w = dispatch_semaphore_wait(got, SECONDS(5));
    int status = 0;
    waitpid(child, &status, 0);
    printf("child exited: waited %ld, DISPATCH_PROC_EXIT %d, exit status %d\n", w, (flags & DISPATCH_PROC_EXIT) != 0,
           WEXITSTATUS(status));
    dispatch_source_cancel(s);
    dispatch_release(s);
    close(go[0]);
    close(go[1]);
}

static int main_pipe[2];

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    reads();
    writes();
    signals();
    processes();

    /* a read source on the main queue: dispatch_main runs its handler */
    pipe(main_pipe);
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, main_pipe[0], 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(s, ^{
        char buf[16] = {0};
        read(main_pipe[0], buf, sizeof buf - 1);
        printf("main queue read source: \"%s\" on the main thread %d\n", buf, pthread_main_np());
        exit(0);
    });
    dispatch_resume(s);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50000000), dispatch_get_global_queue(0, 0), ^{
        write(main_pipe[1], "later", 5);
    });
    dispatch_main();
}
