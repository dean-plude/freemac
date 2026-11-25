/* SPDX-License-Identifier: GPL-3.0-or-later
 * libplugcore.dylib for the plugins test: see core.h. */
#include "core.h"
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static struct { const char *name; core_work_fn work; } modules[16];
static int nmodules;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t started = PTHREAD_COND_INITIALIZER;
static int waiting, go;
static int next_item, items_total;
static long totals_now[16];

int core_register(const char *module, core_work_fn work)
{
    pthread_mutex_lock(&lock);
    int i = nmodules < 16 ? nmodules++ : -1;
    if (i >= 0) {
        modules[i].name = module;
        modules[i].work = work;
    }
    pthread_mutex_unlock(&lock);
    return i;
}

int core_count(void) { return nmodules; }
const char *core_module_name(int i) { return i >= 0 && i < nmodules ? modules[i].name : NULL; }
/* One plugin defines a call of this name too; the others, linked against
 * this library, bind to this one through the two-level namespace. */
const char *core_whoami(void) { return "core"; }

int core_log(const char *format, ...)
{
    char line[256];
    va_list ap;
    va_start(ap, format);
    int n = vsnprintf(line, sizeof line, format, ap);
    va_end(ap);
    pthread_mutex_lock(&lock);
    printf("  [core] %s\n", line);
    pthread_mutex_unlock(&lock);
    return n;
}

/* Workers wait until all of them have started, then take items one at a time. */
static void *worker(void *arg)
{
    long mine[16] = {0};
    pthread_mutex_lock(&lock);
    waiting++;
    pthread_cond_broadcast(&started);
    while (!go)
        pthread_cond_wait(&started, &lock);
    for (;;) {
        int item = next_item < items_total ? next_item++ : -1;
        pthread_mutex_unlock(&lock);
        if (item < 0)
            break;
        for (int m = 0; m < nmodules; m++)
            mine[m] += modules[m].work(item);
        pthread_mutex_lock(&lock);
    }
    pthread_mutex_lock(&lock);
    for (int m = 0; m < nmodules; m++)
        totals_now[m] += mine[m];
    pthread_mutex_unlock(&lock);
    return arg;
}

int core_run(int threads, int items, long *totals)
{
    pthread_t t[16];
    if (threads > 16)
        threads = 16;
    memset(totals_now, 0, sizeof totals_now);
    waiting = go = next_item = 0;
    items_total = items;
    int made = 0;
    for (int i = 0; i < threads; i++)
        if (pthread_create(&t[made], NULL, worker, NULL) == 0)
            made++;
    pthread_mutex_lock(&lock);
    while (waiting < made)
        pthread_cond_wait(&started, &lock);
    go = 1;
    pthread_cond_broadcast(&started);
    pthread_mutex_unlock(&lock);
    for (int i = 0; i < made; i++)
        pthread_join(t[i], NULL);
    for (int m = 0; m < nmodules; m++)
        totals[m] = totals_now[m];
    return made;
}
