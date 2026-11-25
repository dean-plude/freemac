/* Ferry test: kqueue's EVFILT_VNODE and O_EVTONLY, as a file watcher
 * (Gas Mask's VDKQueue) uses them: a file's writes, growth, attributes,
 * links, rename and deletion, a directory's entries, a level-triggered
 * knote, the changes a knote didn't ask for, close removing the knote, and
 * a dispatch vnode source. Its files go in $TMPDIR. */
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(x)                                                                                              \
    do {                                                                                                      \
        if (!(x)) {                                                                                           \
            printf("FAILED line %d: %s (errno %d)\n", __LINE__, #x, errno);                                    \
            exit(1);                                                                                          \
        }                                                                                                     \
    } while (0)

#define ALL (NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME | NOTE_REVOKE)

static int kq;
static char dir[512];

static const char *names(unsigned f)
{
    static char buf[128];
    buf[0] = 0;
    static const struct { unsigned bit; const char *name; } all[] = {
        {NOTE_DELETE, "DELETE"}, {NOTE_WRITE, "WRITE"}, {NOTE_EXTEND, "EXTEND"}, {NOTE_ATTRIB, "ATTRIB"},
        {NOTE_LINK, "LINK"}, {NOTE_RENAME, "RENAME"}, {NOTE_REVOKE, "REVOKE"},
    };
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++)
        if (f & all[i].bit) {
            if (buf[0])
                strcat(buf, "|");
            strcat(buf, all[i].name);
        }
    return buf[0] ? buf : "none";
}

static int watch(int fd, unsigned fflags, int flags)
{
    struct kevent k;
    EV_SET(&k, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | flags, fflags, 0, (void *)(intptr_t)fd);
    return kevent(kq, &k, 1, NULL, 0, NULL);
}

/* What the kqueue reports now ("none" when nothing). */
static const char *seen(int fd, long ms)
{
    struct kevent ev;
    struct timespec t = {ms / 1000, (ms % 1000) * 1000000};
    memset(&ev, 0, sizeof ev);
    int n = kevent(kq, NULL, 0, &ev, 1, &t);
    if (n <= 0)
        return "none";
    if ((int)ev.ident != fd || ev.filter != EVFILT_VNODE || ev.udata != (void *)(intptr_t)fd)
        return "the wrong knote";
    return names(ev.fflags);
}

static void path(char *out, const char *name) { snprintf(out, 512, "%s/%s", dir, name); }

static void file(void)
{
    char a[512], b[512], c[512];
    path(a, "hosts");
    path(b, "hosts-link");
    path(c, "hosts-renamed");
    int w = open(a, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    CHECK(w >= 0);
    CHECK(write(w, "127.0.0.1 localhost\n", 20) == 20);
    int fd = open(a, O_EVTONLY);
    printf("O_EVTONLY open: %s\n", fd >= 0 ? "ok" : strerror(errno));
    CHECK(fd >= 0);
    printf("O_EVTONLY can't write: %d\n", write(fd, "x", 1) < 0);
    CHECK(watch(fd, ALL, EV_CLEAR) == 0);
    printf("nothing yet: %s\n", seen(fd, 0));
    CHECK(write(w, "::1 localhost\n", 14) == 14);
    printf("appended: %s\n", seen(fd, 1000));
    printf("cleared: %s\n", seen(fd, 0));
    CHECK(pwrite(w, "#", 1, 0) == 1);
    printf("overwritten: %s\n", seen(fd, 1000));
    CHECK(chmod(a, 0600) == 0);
    printf("chmod: %s\n", seen(fd, 1000));
    CHECK(link(a, b) == 0);
    printf("linked: %s\n", seen(fd, 1000));
    CHECK(unlink(b) == 0);
    printf("one link removed: %s\n", seen(fd, 1000));
    CHECK(rename(a, c) == 0);
    printf("renamed: %s\n", seen(fd, 1000));
    CHECK(write(w, "x", 1) == 1);
    printf("written after the rename: %s\n", seen(fd, 1000));
    CHECK(unlink(c) == 0);
    printf("deleted: %s\n", seen(fd, 1000));
    close(w);
    close(fd);
    printf("after close: %s\n", seen(fd, 0));
}

/* An editor's save: a new file renamed over the watched one. */
static void replaced(void)
{
    char a[512], tmp[512];
    path(a, "replaced");
    path(tmp, "replaced.tmp");
    int w = open(a, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    CHECK(w >= 0);
    close(w);
    int fd = open(a, O_EVTONLY);
    CHECK(fd >= 0 && watch(fd, ALL, EV_CLEAR) == 0);
    w = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    CHECK(w >= 0 && write(w, "new", 3) == 3);
    close(w);
    CHECK(rename(tmp, a) == 0);
    printf("replaced by a rename: %s\n", seen(fd, 1000));
    close(fd);
    unlink(a);
}

static void level(void)
{
    char a[512];
    path(a, "level");
    int w = open(a, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    CHECK(w >= 0);
    int fd = open(a, O_EVTONLY);
    CHECK(fd >= 0 && watch(fd, NOTE_WRITE, 0) == 0);
    CHECK(write(w, "abc", 3) == 3);
    printf("level-triggered: %s\n", seen(fd, 1000));
    printf("  and again: %s\n", seen(fd, 0));
    CHECK(watch(fd, NOTE_DELETE, EV_CLEAR) == 0);
    printf("added again for DELETE only: %s\n", seen(fd, 0));
    CHECK(write(w, "def", 3) == 3);
    printf("written, not asked for: %s\n", seen(fd, 100));
    struct kevent k;
    EV_SET(&k, fd, EVFILT_VNODE, EV_DELETE, 0, 0, NULL);
    printf("deleted knote: %d\n", kevent(kq, &k, 1, NULL, 0, NULL));
    close(w);
    close(fd);
    unlink(a);
}

static void directory(void)
{
    char d[512], f[512], sub[512];
    path(d, "folder");
    CHECK(mkdir(d, 0755) == 0);
    snprintf(f, sizeof f, "%s/entry", d);
    snprintf(sub, sizeof sub, "%s/sub", d);
    int fd = open(d, O_EVTONLY);
    CHECK(fd >= 0 && watch(fd, ALL, EV_CLEAR) == 0);
    int w = open(f, O_WRONLY | O_CREAT, 0644);
    CHECK(w >= 0);
    printf("directory, file created: %s\n", seen(fd, 1000));
    CHECK(write(w, "x", 1) == 1);
    printf("directory, its file written: %s\n", seen(fd, 0));
    close(w);
    CHECK(mkdir(sub, 0755) == 0);
    printf("directory, subdirectory made: %s\n", seen(fd, 1000));
    CHECK(rmdir(sub) == 0 && unlink(f) == 0);
    printf("directory, both removed: %s\n", seen(fd, 1000));
    close(fd);
    CHECK(rmdir(d) == 0);
}

static void errors(void)
{
    struct kevent k;
    EV_SET(&k, 9999, EVFILT_VNODE, EV_ADD, NOTE_WRITE, 0, NULL);
    errno = 0;
    printf("a closed descriptor: %d errno %s\n", kevent(kq, &k, 1, NULL, 0, NULL), errno == EBADF ? "EBADF" : "?");
    char a[512];
    path(a, "secret");
    int w = open(a, O_WRONLY | O_CREAT | O_TRUNC, 0000);
    CHECK(w >= 0);
    close(w);
    int fd = open(a, O_EVTONLY);
    printf("O_EVTONLY of a file it can't read: %s\n", fd >= 0 ? "ok" : strerror(errno));
    if (fd >= 0) {
        CHECK(watch(fd, ALL, EV_CLEAR) == 0);
        CHECK(chmod(a, 0644) == 0);
        printf("  its chmod: %s\n", seen(fd, 1000));
        close(fd);
    }
    unlink(a);
}

static void source(void)
{
    char a[512];
    path(a, "dispatch");
    int w = open(a, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    CHECK(w >= 0);
    int fd = open(a, O_EVTONLY);
    CHECK(fd >= 0);
    dispatch_queue_t q = dispatch_queue_create("vnode", NULL);
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
                                                 DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE, q);
    CHECK(s != NULL);
    dispatch_semaphore_t got = dispatch_semaphore_create(0), done = dispatch_semaphore_create(0);
    __block unsigned long data = 0;
    dispatch_source_set_event_handler(s, ^{
        data = dispatch_source_get_data(s);
        dispatch_semaphore_signal(got);
    });
    dispatch_source_set_cancel_handler(s, ^{
        close(fd);
        dispatch_semaphore_signal(done);
    });
    printf("source mask: %s\n", names((unsigned)dispatch_source_get_mask(s)));
    dispatch_resume(s);
    usleep(100000);
    CHECK(write(w, "abc", 3) == 3);
    long late = dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 2000000000ll));
    printf("dispatch source, written: %s%s\n", late ? "timed out, " : "", names((unsigned)data));
    CHECK(unlink(a) == 0);
    late = dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 2000000000ll));
    printf("dispatch source, deleted: %s%s\n", late ? "timed out, " : "", names((unsigned)data));
    dispatch_source_cancel(s);
    printf("cancelled: %ld\n", dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2000000000ll)));
    close(w);
}

int main(void)
{
    const char *tmp = getenv("TMPDIR");
    snprintf(dir, sizeof dir, "%s/vnodeXXXXXX", tmp && *tmp ? tmp : "/tmp");
    CHECK(mkdtemp(dir) != NULL);
    kq = kqueue();
    CHECK(kq >= 0);
    file();
    replaced();
    level();
    directory();
    errors();
    source();
    close(kq);
    CHECK(rmdir(dir) == 0);
    printf("done\n");
    return 0;
}
