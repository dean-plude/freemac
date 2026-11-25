/* SPDX-License-Identifier: GPL-3.0-or-later
 * backtrace(3), backtrace_symbols and backtrace_symbols_fd from Mac code
 * three calls deep, on the main thread and on another (freemac 1.233,
 * Ferry 0.57.0): every frame comes back, each named by its image and
 * symbol, in a Mac's format. */
#include <execinfo.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* "N  image  0xADDRESS symbol + offset", as a Mac prints it */
static void show(const char *line, int i)
{
    int n = -1;
    char image[256], symbol[256];
    unsigned long long addr = 0, offset = 0;
    int got = sscanf(line, "%d %255s 0x%llx %255s + %llu", &n, image, &addr, symbol, &offset);
    printf("  %d: %s %s, numbered %s, an address %s, an offset %s\n", i, got == 5 ? image : "?", got == 5 ? symbol : "?",
           n == i ? "right" : "wrong", addr ? "given" : "missing", got == 5 && offset > 0 ? "given" : "missing");
}

static __attribute__((noinline)) void level3(const char *where, const char *top)
{
    void *frames[64];
    int n = backtrace(frames, 64);
    char **names = backtrace_symbols(frames, n);
    printf("%s: at least 4 frames: %s\n", where, n >= 4 ? "yes" : "no");
    for (int i = 0; i < 4 && i < n; i++)
        show(names[i], i);
    free(names);

    int p[2];
    if (pipe(p) != 0)
        return;
    backtrace_symbols_fd(frames, 4, p[1]);
    close(p[1]);
    char buf[4096];
    ssize_t len = read(p[0], buf, sizeof buf - 1);
    close(p[0]);
    buf[len > 0 ? len : 0] = 0;
    int lines = 0;
    for (char *c = buf; *c; c++)
        lines += *c == '\n';
    printf("  backtrace_symbols_fd: %d lines, level2 then level1 then %s: %s\n", lines, top,
           strstr(buf, "level2") && strstr(buf, "level1") && strstr(buf, top) &&
                   strstr(buf, "level2") < strstr(buf, "level1") && strstr(buf, "level1") < strstr(buf, top)
               ? "yes"
               : "no");
}
static __attribute__((noinline)) void level2(const char *where, const char *top)
{
    level3(where, top);
    __asm__ volatile("");
}
static __attribute__((noinline)) void level1(const char *where, const char *top)
{
    level2(where, top);
    __asm__ volatile("");
}

static void *thread_main(void *arg)
{
    level1("another thread", "thread_main");
    return NULL;
}

int main(void)
{
    level1("the main thread", "main");
    pthread_t t;
    pthread_create(&t, NULL, thread_main, NULL);
    pthread_join(t, NULL);
    void *none[1];
    printf("backtrace into no room: %d, backtrace_symbols of none: %s\n", backtrace(none, 0),
           backtrace_symbols(none, 0) ? "a list" : "NULL");
    return 0;
}
