/* SPDX-License-Identifier: GPL-3.0-or-later
 * Thread-local variables in a Mac library opened with dlopen while the
 * program runs (built by run.sh into build/tlv_plug): a thread started
 * before the library was opened, new threads and the main thread each get
 * their own copies; dlsym of a thread-local variable gives the calling
 * thread's; destructors registered with _tlv_atexit run when each thread
 * ends, the last registered first, and for the main thread when main
 * returns, before the program's atexit functions. */
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void _tlv_atexit(void (*fn)(void *), void *obj);

struct log { char text[64]; };

static int (*plug_next)(void);
static const char *(*plug_note)(const char *);
static void (*plug_watch)(struct log *);
static void *plug;

__thread int own = 11;

/* ---- a thread from before the library was opened ------------------------------ */

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static int opened;
static struct log early_log;
static int early_ok;

static void *early(void *arg)
{
    (void)arg;
    own = 12; /* this thread already has thread-local storage */
    pthread_mutex_lock(&lock);
    while (!opened)
        pthread_cond_wait(&cond, &lock);
    pthread_mutex_unlock(&lock);
    int a = plug_next(), b = plug_next();
    plug_watch(&early_log);
    early_ok = a == 101 && b == 102 && own == 12 && !strcmp(plug_note("early"), "early/102");
    return NULL;
}

/* ---- threads after it ------------------------------------------------------------ */

#define THREADS 4

struct result { struct log log; int ok; int *where; };

static void *later(void *arg)
{
    struct result *r = arg;
    int *mine = dlsym(plug, "plug_value");
    int first = mine ? *mine : -1;
    plug_next();
    plug_next();
    plug_next();
    r->where = mine;
    r->ok = first == 100 && mine && *mine == 103 && own == 11;
    plug_watch(&r->log);
    return NULL;
}

/* ---- the main thread at exit ----------------------------------------------------- */

static struct log main_log;

static void print_main_log(void *obj)
{
    printf("main thread's destructors at exit:%s\n", ((struct log *)obj)->text);
}

static void static_end(void) { printf("then the atexit function\n"); }

int main(void)
{
    atexit(static_end);
    pthread_t e;
    pthread_create(&e, NULL, early, NULL);

    plug = dlopen("@rpath/libtlvplug.dylib", RTLD_NOW);
    if (!plug) {
        printf("dlopen: %s\n", dlerror());
        return 1;
    }
    plug_next = (int (*)(void))dlsym(plug, "plug_next");
    plug_note = (const char *(*)(const char *))dlsym(plug, "plug_note");
    plug_watch = (void (*)(struct log *))dlsym(plug, "plug_watch");
    printf("dlopen: ok, calls found: %s\n", plug_next && plug_note && plug_watch ? "yes" : "no");

    int next = plug_next();
    printf("main thread: plug_next() %d, plug_note %s\n", next, plug_note("main"));
    int *main_value = dlsym(plug, "plug_value");
    printf("dlsym(\"plug_value\") on the main thread reads %d\n", main_value ? *main_value : -1);
    if (main_value)
        *main_value = 500;
    printf("written through it, plug_next() gives %d\n", plug_next());

    pthread_mutex_lock(&lock);
    opened = 1;
    pthread_cond_broadcast(&cond);
    pthread_mutex_unlock(&lock);
    pthread_join(e, NULL);
    printf("thread started before dlopen: %s, its destructors:%s\n", early_ok ? "ok" : "wrong", early_log.text);

    pthread_t t[THREADS];
    struct result r[THREADS];
    memset(r, 0, sizeof r);
    for (int i = 0; i < THREADS; i++)
        pthread_create(&t[i], NULL, later, &r[i]);
    int ok = 0, logs = 0, distinct = 1;
    for (int i = 0; i < THREADS; i++) {
        pthread_join(t[i], NULL);
        ok += r[i].ok;
        logs += !strcmp(r[i].log.text, " second(103) first");
        if (r[i].where == main_value)
            distinct = 0;
    }
    printf("%d threads after it: right values %d, destructors in order %d, dlsym gave each its own: %s\n", THREADS,
           ok, logs, distinct ? "yes" : "no");

    /* the main thread's destructors run when main returns */
    _tlv_atexit(print_main_log, &main_log);
    plug_watch(&main_log);
    printf("main returns\n");
    return 0;
}
