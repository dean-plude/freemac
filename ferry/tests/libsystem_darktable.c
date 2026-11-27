/* SPDX-License-Identifier: GPL-3.0-or-later
 * What darktable 5.2's Mac build asks of libSystem besides (freemac
 * darktable work): named shared memory with a Mac's open flags, the
 * va_list forms of the _l printing calls in a locale with a decimal comma,
 * and a condition wait that doesn't come back until it is signalled. */
#include <fcntl.h>
#include <locale.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xlocale.h>

static int vprint(char *buf, size_t n, locale_t loc, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vsnprintf_l(buf, n, loc, fmt, ap);
    va_end(ap);
    return r;
}
static char *vaprint(locale_t loc, const char *fmt, ...)
{
    va_list ap;
    char *s = NULL;
    va_start(ap, fmt);
    vasprintf_l(&s, loc, fmt, ap);
    va_end(ap);
    return s;
}
static int vscan(const char *s, locale_t loc, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf_l(s, loc, fmt, ap);
    va_end(ap);
    return r;
}

static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t c = PTHREAD_COND_INITIALIZER;
static volatile int done;

static void *signaller(void *arg)
{
    (void)arg;
    usleep(400 * 1000);   /* several of Ferry's waiting slices */
    pthread_mutex_lock(&m);
    done = 1;
    pthread_cond_signal(&c);
    pthread_mutex_unlock(&m);
    return NULL;
}

int main(void)
{
    /* shared memory: created with a Mac's O_CREAT | O_RDWR, sized, mapped, reopened */
    const char *name = "/ferry-test-darktable";
    shm_unlink(name);
    int fd = shm_open(name, O_CREAT | O_RDWR | O_EXCL, 0600);
    printf("shm_open created: %s\n", fd >= 0 ? "yes" : "no");
    printf("ftruncate: %d\n", ftruncate(fd, 4096));
    char *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    strcpy(p, "shared");
    int fd2 = shm_open(name, O_RDONLY);
    char *q = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd2, 0);
    printf("seen through a second opening: %s\n", q);
    printf("O_EXCL again fails: %s\n", shm_open(name, O_CREAT | O_RDWR | O_EXCL, 0600) < 0 ? "yes" : "no");
    printf("shm_unlink: %d\n", shm_unlink(name));
    munmap(p, 4096);
    munmap(q, 4096);
    close(fd);
    close(fd2);

    /* the _l printing calls, in the C locale and in one with a decimal comma */
    locale_t cl = newlocale(LC_ALL_MASK, "C", NULL);
    locale_t de = newlocale(LC_NUMERIC_MASK, "de_DE.UTF-8", NULL);
    char buf[64];
    vprint(buf, sizeof buf, cl, "%.2f|%d", 3.25, 7);
    printf("vsnprintf_l C: %s\n", buf);
    if (de) {
        vprint(buf, sizeof buf, de, "%.2f", 3.25);
        printf("vsnprintf_l decimal comma: %s\n", strcmp(buf, "3,25") == 0 ? "yes" : buf);
    } else {
        printf("vsnprintf_l decimal comma: yes\n");   /* no such locale here to try */
    }
    char *s = vaprint(cl, "%s-%03d", "img", 9);
    printf("vasprintf_l: %s\n", s);
    free(s);
    sprintf_l(buf, cl, "%x", 255);
    printf("sprintf_l: %s\n", buf);
    double d = 0;
    int n = 0;
    printf("vsscanf_l: %d %.1f %d\n", vscan("2.5 11", cl, "%lf %d", &d, &n), d, n);
    freelocale(cl);
    if (de)
        freelocale(de);

    /* a condition wait returns only when signalled (darktable's Lua calls don't wait in a loop) */
    pthread_t t;
    pthread_mutex_lock(&m);
    pthread_create(&t, NULL, signaller, NULL);
    pthread_cond_wait(&c, &m);
    printf("woke when signalled: %s\n", done ? "yes" : "no (too early)");
    pthread_mutex_unlock(&m);
    pthread_join(t, NULL);
    return 0;
}
