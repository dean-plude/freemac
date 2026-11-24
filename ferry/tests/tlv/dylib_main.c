/* SPDX-License-Identifier: GPL-3.0-or-later
 * Thread-local variables in a Mac library the program links (built by
 * run.sh into build/tlv_lib): the program reaches the library's own
 * variables directly, through the library's exported names, and through
 * the library's calls, and each thread sees one copy of each, started
 * from the library's template, beside the program's own variables. */
#include <pthread.h>
#include <stdio.h>
#include <string.h>

extern __thread int lib_counter;
extern __thread char lib_tag[16];
int lib_bump(void);
int *lib_counter_address(void);
long lib_add(long n);

__thread int own = 3;

#define THREADS 6

struct result { int index, same, fresh, counted; long added; };

static void *worker(void *arg)
{
    struct result *r = arg;
    r->fresh = lib_counter == 7 && !strcmp(lib_tag, "library") && own == 3;
    r->same = &lib_counter == lib_counter_address();
    for (int i = 0; i < 1000 * r->index; i++)
        lib_bump();
    for (int i = 0; i < 100; i++)
        lib_add(r->index);
    own = -r->index;
    r->counted = lib_counter == 7 + 1000 * r->index && own == -r->index;
    r->added = lib_add(0);
    return NULL;
}

int main(void)
{
    printf("main thread: lib_counter %d, lib_tag %s, own %d\n", lib_counter, lib_tag, own);
    printf("the same variable directly and through the library: %s\n",
           &lib_counter == lib_counter_address() ? "yes" : "no");
    lib_bump();
    lib_bump();
    printf("after two calls on the main thread: %d (read directly)\n", lib_counter);
    pthread_t t[THREADS];
    struct result r[THREADS];
    for (int i = 0; i < THREADS; i++) {
        memset(&r[i], 0, sizeof r[i]);
        r[i].index = i + 1;
        pthread_create(&t[i], NULL, worker, &r[i]);
    }
    int same = 0, fresh = 0, counted = 0, added = 0;
    for (int i = 0; i < THREADS; i++) {
        pthread_join(t[i], NULL);
        same += r[i].same;
        fresh += r[i].fresh;
        counted += r[i].counted;
        added += r[i].added == 100L * r[i].index;
    }
    printf("%d threads: from the template %d, one copy each %d, counted on their own %d, sums right %d\n", THREADS,
           fresh, same, counted, added);
    printf("main thread still: lib_counter %d, own %d, hidden sum %ld\n", lib_counter, own, lib_add(0));
    return 0;
}
