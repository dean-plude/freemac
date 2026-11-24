/* SPDX-License-Identifier: GPL-3.0-or-later
 * Thread-local variables from plain C: __thread and _Thread_local with and
 * without first values, an array, a pointer to a global, a variable
 * aligned to 64 bytes and a static one, each thread starting from the
 * template and keeping its own copy while eight threads change theirs at
 * once; the thunk keeping every register the compiler may rely on
 * (checked from assembly, on a thread's first use and after it); a
 * set-up function in the image's thread-local init section run once;
 * dispatch's worker threads each with their own copy; and each thread's
 * storage freed when it ends. Each part prints a fixed line. */
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define THREADS 8
#define ROUNDS 20000

static int global_target = 42;

__thread int counter = 5;
_Thread_local long total;
__thread char name[32] = "template";
_Thread_local double ratio = 0.25;
_Alignas(64) __thread char aligned_buf[64];
__thread int *pointer = &global_target;
static __thread int hidden = 9;
__thread int set_by_init;

static void on_alarm(int sig)
{
    (void)sig;
    static const char msg[] = "tlv_threads: timed out\n";
    write(2, msg, sizeof msg - 1);
    _exit(3);
}

/* ---- each thread its own copy ------------------------------------------------ */

struct result {
    int index, started_right, aligned, kept;
    long total;
    void *addresses[3];
};

static pthread_mutex_t start_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t start_cond = PTHREAD_COND_INITIALIZER;
static int ready, go;

static void *worker(void *arg)
{
    struct result *r = arg;
    r->started_right = counter == 5 && total == 0 && !strcmp(name, "template") && ratio == 0.25 &&
                       *pointer == 42 && hidden == 9 && set_by_init == 0;
    r->aligned = ((unsigned long)aligned_buf & 63) == 0;
    r->addresses[0] = &counter;
    r->addresses[1] = &total;
    r->addresses[2] = name;
    /* all at once */
    pthread_mutex_lock(&start_lock);
    ready++;
    pthread_cond_broadcast(&start_cond);
    while (!go)
        pthread_cond_wait(&start_cond, &start_lock);
    pthread_mutex_unlock(&start_lock);
    snprintf(name, sizeof name, "thread %d", r->index);
    counter = r->index;
    ratio = r->index * 2.0;
    hidden = r->index * 3;
    for (int i = 0; i < ROUNDS; i++) {
        total += i % 7;
        aligned_buf[i % 64]++;
        if (i % 1000 == 0)
            sched_yield();
    }
    char want[32];
    snprintf(want, sizeof want, "thread %d", r->index);
    r->kept = counter == r->index && ratio == r->index * 2.0 && hidden == r->index * 3 && !strcmp(name, want);
    r->total = total;
    return NULL;
}

static void own_copies(void)
{
    pthread_t t[THREADS];
    struct result r[THREADS];
    for (int i = 0; i < THREADS; i++) {
        memset(&r[i], 0, sizeof r[i]);
        r[i].index = i + 1;
        pthread_create(&t[i], NULL, worker, &r[i]);
    }
    pthread_mutex_lock(&start_lock);
    while (ready < THREADS)
        pthread_cond_wait(&start_cond, &start_lock);
    go = 1;
    pthread_cond_broadcast(&start_cond);
    pthread_mutex_unlock(&start_lock);
    for (int i = 0; i < THREADS; i++)
        pthread_join(t[i], NULL);
    long expected = 0;
    for (int i = 0; i < ROUNDS; i++)
        expected += i % 7;
    int started = 0, aligned = 0, kept = 0, totals = 0, distinct = 1;
    for (int i = 0; i < THREADS; i++) {
        started += r[i].started_right;
        aligned += r[i].aligned;
        kept += r[i].kept;
        totals += r[i].total == expected;
        for (int k = 0; k < 3; k++) {
            if (r[i].addresses[k] == (k == 0 ? (void *)&counter : k == 1 ? (void *)&total : (void *)name))
                distinct = 0;
            for (int j = 0; j < i; j++)
                if (r[j].addresses[k] == r[i].addresses[k])
                    distinct = 0;
        }
    }
    printf("%d threads started from the template: %d\n", THREADS, started);
    printf("aligned to 64 bytes: %d, kept their own values: %d, totals right: %d\n", aligned, kept, totals);
    printf("addresses differ from thread to thread: %s\n", distinct ? "yes" : "no");
    printf("main thread: counter %d, total %ld, name %s, ratio %g, hidden %d, *pointer %d\n", counter, total, name,
           ratio, hidden, *pointer);
}

/* ---- the thunk keeps the registers ------------------------------------------- */

__thread long probe_var = 77;

struct regs {
    long addr;
    unsigned long gpr[12];  /* rcx rdx rsi r8 r9 r10 r11 rbx r13 r14 r15, then r12 */
    unsigned long xmm[32];
};

static const unsigned long gpr_expected[11] = {
    0x0123456789abcdefUL, 0x1122334455667788UL, 0x8877665544332211UL, 0x0f0e0d0c0b0a0908UL,
    0x9999888877776666UL, 0xa5a5a5a55a5a5a5aUL, 0xdeadbeefcafef00dUL, 0x0badc0ffee0ddf00UL,
    0x1357924680aceb0dUL, 0x2468ace013579bdfUL, 0x7777000077770000UL,
};

__attribute__((used)) static unsigned long probe_pattern[32];

void probe(struct regs *out);
__asm__(".text\n"
        ".p2align 4\n"
        "_probe:\n"
        "    pushq %rbp\n"
        "    movq %rsp, %rbp\n"
        "    pushq %rbx\n"
        "    pushq %r12\n"
        "    pushq %r13\n"
        "    pushq %r14\n"
        "    pushq %r15\n"
        "    subq $8, %rsp\n"
        "    movq %rdi, %r12\n"
        "    leaq _probe_pattern(%rip), %rax\n"
        "    movdqu 0(%rax), %xmm0\n"
        "    movdqu 16(%rax), %xmm1\n"
        "    movdqu 32(%rax), %xmm2\n"
        "    movdqu 48(%rax), %xmm3\n"
        "    movdqu 64(%rax), %xmm4\n"
        "    movdqu 80(%rax), %xmm5\n"
        "    movdqu 96(%rax), %xmm6\n"
        "    movdqu 112(%rax), %xmm7\n"
        "    movdqu 128(%rax), %xmm8\n"
        "    movdqu 144(%rax), %xmm9\n"
        "    movdqu 160(%rax), %xmm10\n"
        "    movdqu 176(%rax), %xmm11\n"
        "    movdqu 192(%rax), %xmm12\n"
        "    movdqu 208(%rax), %xmm13\n"
        "    movdqu 224(%rax), %xmm14\n"
        "    movdqu 240(%rax), %xmm15\n"
        "    movabsq $0x0123456789abcdef, %rcx\n"
        "    movabsq $0x1122334455667788, %rdx\n"
        "    movabsq $0x8877665544332211, %rsi\n"
        "    movabsq $0x0f0e0d0c0b0a0908, %r8\n"
        "    movabsq $0x9999888877776666, %r9\n"
        "    movabsq $0xa5a5a5a55a5a5a5a, %r10\n"
        "    movabsq $0xdeadbeefcafef00d, %r11\n"
        "    movabsq $0x0badc0ffee0ddf00, %rbx\n"
        "    movabsq $0x1357924680aceb0d, %r13\n"
        "    movabsq $0x2468ace013579bdf, %r14\n"
        "    movabsq $0x7777000077770000, %r15\n"
        "    movq _probe_var@TLVP(%rip), %rdi\n"
        "    callq *(%rdi)\n"
        "    movq %rax, 0(%r12)\n"
        "    movq %rcx, 8(%r12)\n"
        "    movq %rdx, 16(%r12)\n"
        "    movq %rsi, 24(%r12)\n"
        "    movq %r8, 32(%r12)\n"
        "    movq %r9, 40(%r12)\n"
        "    movq %r10, 48(%r12)\n"
        "    movq %r11, 56(%r12)\n"
        "    movq %rbx, 64(%r12)\n"
        "    movq %r13, 72(%r12)\n"
        "    movq %r14, 80(%r12)\n"
        "    movq %r15, 88(%r12)\n"
        "    movq %r12, 96(%r12)\n"
        "    movdqu %xmm0, 104(%r12)\n"
        "    movdqu %xmm1, 120(%r12)\n"
        "    movdqu %xmm2, 136(%r12)\n"
        "    movdqu %xmm3, 152(%r12)\n"
        "    movdqu %xmm4, 168(%r12)\n"
        "    movdqu %xmm5, 184(%r12)\n"
        "    movdqu %xmm6, 200(%r12)\n"
        "    movdqu %xmm7, 216(%r12)\n"
        "    movdqu %xmm8, 232(%r12)\n"
        "    movdqu %xmm9, 248(%r12)\n"
        "    movdqu %xmm10, 264(%r12)\n"
        "    movdqu %xmm11, 280(%r12)\n"
        "    movdqu %xmm12, 296(%r12)\n"
        "    movdqu %xmm13, 312(%r12)\n"
        "    movdqu %xmm14, 328(%r12)\n"
        "    movdqu %xmm15, 344(%r12)\n"
        "    addq $8, %rsp\n"
        "    popq %r15\n"
        "    popq %r14\n"
        "    popq %r13\n"
        "    popq %r12\n"
        "    popq %rbx\n"
        "    popq %rbp\n"
        "    ret\n");

/* 1 if every register came back as it went in and the address is this
 * thread's probe_var. */
static int probe_once(void)
{
    struct regs r;
    memset(&r, 0, sizeof r);
    probe(&r);
    int ok = r.addr == (long)&probe_var && *(long *)r.addr == 77 && r.gpr[11] == (unsigned long)&r;
    for (int i = 0; i < 11; i++)
        ok &= r.gpr[i] == gpr_expected[i];
    for (int i = 0; i < 32; i++)
        ok &= r.xmm[i] == probe_pattern[i];
    return ok;
}

static void *probe_thread(void *arg)
{
    int *ok = arg;
    ok[0] = probe_once(); /* the thread's first thread-local variable: the slow way */
    ok[1] = probe_once(); /* and the quick way */
    return NULL;
}

static void registers(void)
{
    for (int i = 0; i < 32; i++)
        probe_pattern[i] = 0x0101010101010101UL * (unsigned long)(i + 1) ^ 0x8000000000000001UL;
    int ok[2] = {0, 0};
    pthread_t t;
    pthread_create(&t, NULL, probe_thread, ok);
    pthread_join(t, NULL);
    printf("registers kept on a thread's first use: %s, after it: %s, on the main thread: %s\n",
           ok[0] ? "yes" : "no", ok[1] ? "yes" : "no", probe_once() ? "yes" : "no");
}

/* ---- the image's thread-local set-up functions -------------------------------- */

static int init_ran;

static void tlv_setup(void)
{
    init_ran++;
    set_by_init = 1;
}

__attribute__((used, section("__DATA,__thread_init,thread_local_init_function_pointers")))
static void (*const tlv_setups[])(void) = {tlv_setup};

static void *read_set_by_init(void *arg)
{
    *(int *)arg = set_by_init;
    return NULL;
}

static void setup_functions(void)
{
    int other = -1;
    pthread_t t;
    pthread_create(&t, NULL, read_set_by_init, &other);
    pthread_join(t, NULL);
    printf("set-up functions ran %d time(s); main thread %d, another thread %d\n", init_ran, set_by_init, other);
}

/* ---- dispatch's worker threads -------------------------------------------------- */

#define ITERATIONS 64

static __thread int per_worker;

static void dispatch_workers(void)
{
    static pthread_t who[ITERATIONS];
    static int *where[ITERATIONS];
    static int seen_count[ITERATIONS];
    dispatch_apply(ITERATIONS, dispatch_get_global_queue(0, 0), ^(size_t i) {
        per_worker++;
        who[i] = pthread_self();
        where[i] = &per_worker;
        seen_count[i] = per_worker;
        usleep(200);
    });
    /* the same thread always reached the same copy, and another thread another one */
    int consistent = 1, threads = 0, sum = 0;
    for (int i = 0; i < ITERATIONS; i++) {
        int first = 1, highest = 0;
        for (int j = 0; j < ITERATIONS; j++) {
            if (pthread_equal(who[i], who[j]) != (where[i] == where[j]))
                consistent = 0;
            if (pthread_equal(who[i], who[j])) {
                if (j < i)
                    first = 0;
                if (seen_count[j] > highest)
                    highest = seen_count[j];
            }
        }
        if (first) {
            threads++;
            sum += highest;
        }
    }
    printf("dispatch_apply: %d iterations counted on their workers' own copies: %s; one copy a thread: %s\n",
           sum, sum == ITERATIONS ? "yes" : "no", consistent ? "yes" : "no");
}

/* ---- storage freed when a thread ends ------------------------------------------ */

#define BIG (4 << 20)
#define ROUND_TRIPS 32

static __thread char big[BIG];

static void *fill_big(void *arg)
{
    memset(big, (int)(long)arg, BIG);
    if ((long)arg % 2)
        pthread_exit(NULL); /* the other way to end */
    return NULL;
}

static long resident_bytes(void)
{
    FILE *f = fopen("/proc/self/statm", "r");
    long size = 0, resident = 0;
    if (!f)
        return -1;
    if (fscanf(f, "%ld %ld", &size, &resident) != 2)
        resident = -1;
    fclose(f);
    return resident < 0 ? -1 : resident * getpagesize();
}

static void storage_freed(void)
{
    long before = resident_bytes();
    for (long i = 1; i <= ROUND_TRIPS; i++) {
        pthread_t t;
        pthread_create(&t, NULL, fill_big, (void *)i);
        pthread_join(t, NULL);
    }
    long after = resident_bytes();
    /* kept, the copies would be 128 MB */
    if (before < 0 || after < 0)
        printf("storage freed: can't tell here\n");
    else
        printf("%d threads with 4 MB each, storage freed: %s\n", ROUND_TRIPS,
               after - before < 48L * 1024 * 1024 ? "yes" : "no");
}

int main(void)
{
    signal(SIGALRM, on_alarm);
    alarm(30);
    setup_functions();
    own_copies();
    registers();
    dispatch_workers();
    storage_freed();
    return 0;
}
