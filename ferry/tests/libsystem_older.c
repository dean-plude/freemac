/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Sequel Pro, its SPMySQL framework and MariaDB Connector/C call from
 * libSystem besides (freemac 1.226, Ferry 0.50.0): pthread cleanup
 * handlers and deferred cancellation, memset_pattern4/8/16, bzip2's FILE
 * calls, C99 complex numbers, alloca, and the headers they include
 * (memory.h, netinet/ip.h, zconf.h); and a query of the system log,
 * which finds nothing here. */
#include <alloca.h>
#include <asl.h>
#include <bzlib.h>
#include <complex.h>
#include <memory.h>
#include <netinet/in_systm.h>
#include <netinet/ip.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <zconf.h>

static int cleaned[4];
static void cleanup(void *p) { cleaned[(long)p]++; }

/* a pop with 1 runs its handler; one with 0 doesn't */
static void *popper(void *arg)
{
    pthread_cleanup_push(cleanup, (void *)0);
    pthread_cleanup_push(cleanup, (void *)1);
    pthread_cleanup_pop(0);
    pthread_cleanup_pop(1);
    return arg;
}

/* pthread_exit runs the handlers still pushed, newest first */
static int order[2], ordered;
static void first(void *p) { order[ordered++] = 1; }
static void second(void *p) { order[ordered++] = 2; }
static void *exiter(void *arg)
{
    pthread_cleanup_push(first, NULL);
    pthread_cleanup_push(second, NULL);
    pthread_exit((void *)7);
    pthread_cleanup_pop(0);
    pthread_cleanup_pop(0);
    return NULL;
}

/* cancelled at pthread_testcancel, once cancellation is enabled again */
static volatile int marked, reached;
static void *cancellee(void *arg)
{
    int old = -1;
    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old);
    printf("  state was enabled: %d\n", old == PTHREAD_CANCEL_ENABLE);
    pthread_cleanup_push(cleanup, (void *)2);
    while (!marked)
        usleep(1000);
    pthread_testcancel();   /* disabled: goes on */
    reached = 1;
    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
    pthread_testcancel();
    reached = 2;            /* not reached */
    pthread_cleanup_pop(0);
    return NULL;
}

int main(void)
{
    printf("cleanup handlers:\n");
    pthread_t t;
    void *result = NULL;
    pthread_create(&t, NULL, popper, (void *)5);
    pthread_join(t, &result);
    printf("  popped: %d %d, result %ld\n", cleaned[0], cleaned[1], (long)result);
    pthread_create(&t, NULL, exiter, NULL);
    pthread_join(t, &result);
    printf("  on exit: %d then %d, result %ld\n", order[0], order[1], (long)result);

    printf("cancellation:\n");
    pthread_create(&t, NULL, cancellee, NULL);
    printf("  cancel: %d\n", pthread_cancel(t));
    marked = 1;
    pthread_join(t, &result);
    printf("  canceled: %d, reached %d, handler %d\n", result == PTHREAD_CANCELED, reached, cleaned[2]);

    printf("memset_pattern:\n");
    unsigned char b[21];
    memset_pattern4(b, "abcd", 10);
    printf("  4: %.10s\n", (char *)b);
    memset_pattern8(b, "01234567", 11);
    printf("  8: %.11s\n", (char *)b);
    memset_pattern16(b, "ABCDEFGHIJKLMNOP", 21);
    printf("  16: %.21s\n", (char *)b);

    printf("bzip2 through a FILE:\n");
    FILE *f = tmpfile();
    int bzerr = 0;
    BZFILE *w = BZ2_bzWriteOpen(&bzerr, f, 9, 0, 0);
    char text[] = "Sequel Pro's exports are compressed with bzip2. Sequel Pro's exports are compressed.";
    BZ2_bzWrite(&bzerr, w, text, (int)strlen(text));
    unsigned in = 0, out = 0;
    BZ2_bzWriteClose(&bzerr, w, 0, &in, &out);
    printf("  wrote: %d, %u bytes in, compressed %s\n", bzerr, in, out > 0 ? "yes" : "no");
    rewind(f);
    BZFILE *r = BZ2_bzReadOpen(&bzerr, f, 0, 0, NULL, 0);
    char back[200] = {0};
    int n = BZ2_bzRead(&bzerr, r, back, sizeof back - 1);
    printf("  read: %d bytes, end %d, same %d\n", n, bzerr == BZ_STREAM_END, !strcmp(back, text));
    BZ2_bzReadClose(&bzerr, r);
    fclose(f);

    printf("complex numbers:\n");
    double complex z = 3.0 + 4.0 * I;
    printf("  |3+4i| = %g, conj %g%+gi\n", cabs(z), creal(conj(z)), cimag(conj(z)));
    double complex e = cexp(I * 3.14159265358979323846);
    printf("  e^(i pi) = %.3f%+.3fi\n", creal(e), cimag(e) + 0.0);
    float complex s = csqrtf(-4.0f);
    printf("  sqrt(-4) = %g%+gi\n", crealf(s), cimagf(s));

    printf("alloca and headers:\n");
    char *a = alloca(16);
    memcpy(a, "on the stack", 13);
    printf("  %s\n", a);
    struct ip header;
    memset(&header, 0, sizeof header);
    header.ip_v = 4;
    header.ip_hl = 5;
    header.ip_tos = IPTOS_LOWDELAY;
    printf("  ip header %zu bytes, version %d, tos 0x%x\n", sizeof header, header.ip_v, header.ip_tos);
    uLong ul = 1;
    Bytef byte = 2;
    printf("  zconf: %zu %zu\n", sizeof ul, sizeof byte);

    printf("log query:\n");
    aslmsg q = asl_new(ASL_TYPE_QUERY);
    printf("  set: %d\n", asl_set_query(q, ASL_KEY_SENDER, "Sequel Pro", ASL_QUERY_OP_EQUAL));
    aslresponse found = asl_search(NULL, q);
    printf("  results: %s\n", asl_next(found) ? "some" : "none");
    aslresponse_free(found);
    asl_free(q);
    return 0;
}
