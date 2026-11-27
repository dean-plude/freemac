/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * notify(3), the Darwin notification API, within one process (freemac
 * 1.265), written from Apple's public notify(3) reference page.
 *
 * A program registers for a name in one of five ways (a block on a queue,
 * a flag notify_check reads, a message to a Mach port, the token written
 * to a pipe, or a signal) and notify_post tells every registration for
 * the name. Each name keeps a 64-bit state. Posts from other processes,
 * and the system's own names (the time zone, the network ...), don't
 * arrive here: a program's registrations work and simply hear nothing
 * from outside.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ferry.h"

#define NOTIFY_STATUS_OK 0
#define NOTIFY_STATUS_INVALID_NAME 1
#define NOTIFY_STATUS_INVALID_TOKEN 2
#define NOTIFY_STATUS_INVALID_PORT 3
#define NOTIFY_STATUS_INVALID_FILE 4
#define NOTIFY_STATUS_INVALID_SIGNAL 5
#define NOTIFY_STATUS_INVALID_REQUEST 6
#define NOTIFY_STATUS_FAILED 1000000

#define NOTIFY_REUSE 0x00000001

void dispatch_async_f(void *queue, void *ctx, void (*fn)(void *));
void *_Block_copy(const void *);
void _Block_release(const void *);
void *dispatch_retain(void *);
void dispatch_release(void *);

enum { K_DISPATCH, K_CHECK, K_PORT, K_FD, K_SIGNAL, K_PLAIN };

struct reg {
    struct reg *next;
    int token;
    int kind;
    char *name;
    void *queue, *block;
    uint32_t port;
    int rfd, wfd;
    int sig;
    int checked;   /* K_CHECK: posted since the last notify_check */
    int suspended; /* notify_suspend's count */
    int missed;    /* a post came while suspended */
};

struct state {
    struct state *next;
    char *name;
    uint64_t value;
};

static pthread_mutex_t nlock = PTHREAD_MUTEX_INITIALIZER;
static struct reg *regs;
static struct state *states;
static int next_token = 1;

static struct reg *find(int token)
{
    for (struct reg *r = regs; r; r = r->next)
        if (r->token == token)
            return r;
    return NULL;
}

static struct state *state_for(const char *name, int make)
{
    for (struct state *s = states; s; s = s->next)
        if (!strcmp(s->name, name))
            return s;
    if (!make)
        return NULL;
    struct state *s = calloc(1, sizeof *s);
    if (!s || !(s->name = strdup(name))) {
        free(s);
        return NULL;
    }
    s->next = states;
    states = s;
    return s;
}

struct call {
    void *block;
    int token;
};

static void run_block(void *ctx)
{
    struct call *c = ctx;
    void (*invoke)(void *, int) = *(void (**)(void *, int))((char *)c->block + 16);
    invoke(c->block, c->token);
    _Block_release(c->block);
    free(c);
}

/* Tell one registration; under nlock. */
static void deliver(struct reg *r)
{
    if (r->suspended) {
        r->missed = 1;
        return;
    }
    switch (r->kind) {
    case K_DISPATCH: {
        struct call *c = malloc(sizeof *c);
        if (!c)
            return;
        c->block = _Block_copy(r->block);
        c->token = r->token;
        dispatch_async_f(r->queue, c, run_block);
        break;
    }
    case K_CHECK: r->checked = 1; break;
    case K_PORT: ferry_mach_send_empty(r->port, r->token); break;
    case K_FD: {
        uint32_t t = htonl((uint32_t)r->token);
        ssize_t n = write(r->wfd, &t, sizeof t);
        (void)n;
        break;
    }
    case K_SIGNAL: kill(getpid(), r->sig); break;
    default: break;
    }
}

static struct reg *add(const char *name, int kind, int *out)
{
    if (!name || !out)
        return NULL;
    struct reg *r = calloc(1, sizeof *r);
    if (!r || !(r->name = strdup(name))) {
        free(r);
        return NULL;
    }
    r->kind = kind;
    r->rfd = r->wfd = -1;
    r->token = next_token++;
    r->next = regs;
    regs = r;
    *out = r->token;
    return r;
}

static uint32_t mac_notify_post(const char *name)
{
    if (!name)
        return NOTIFY_STATUS_INVALID_NAME;
    pthread_mutex_lock(&nlock);
    for (struct reg *r = regs; r; r = r->next)
        if (!strcmp(r->name, name))
            deliver(r);
    pthread_mutex_unlock(&nlock);
    return NOTIFY_STATUS_OK;
}

static uint32_t mac_notify_register_dispatch(const char *name, int *out, void *queue, void *handler)
{
    if (!queue || !handler)
        return NOTIFY_STATUS_INVALID_REQUEST;
    pthread_mutex_lock(&nlock);
    struct reg *r = add(name, K_DISPATCH, out);
    if (r) {
        r->queue = dispatch_retain(queue);
        r->block = _Block_copy(handler);
    }
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : name ? NOTIFY_STATUS_FAILED : NOTIFY_STATUS_INVALID_NAME;
}

static uint32_t mac_notify_register_check(const char *name, int *out)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = add(name, K_CHECK, out);
    if (r)
        r->checked = 1; /* the first notify_check says yes */
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : name ? NOTIFY_STATUS_FAILED : NOTIFY_STATUS_INVALID_NAME;
}

static uint32_t mac_notify_register_plain(const char *name, int *out)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = add(name, K_PLAIN, out);
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : name ? NOTIFY_STATUS_FAILED : NOTIFY_STATUS_INVALID_NAME;
}

static uint32_t mac_notify_register_signal(const char *name, int sig, int *out)
{
    int lsig = ferry_signal_to_linux(sig);
    if (!lsig)
        return NOTIFY_STATUS_INVALID_SIGNAL;
    pthread_mutex_lock(&nlock);
    struct reg *r = add(name, K_SIGNAL, out);
    if (r)
        r->sig = lsig;
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : name ? NOTIFY_STATUS_FAILED : NOTIFY_STATUS_INVALID_NAME;
}

static uint32_t mac_notify_register_mach_port(const char *name, uint32_t *port, int flags, int *out)
{
    if (!port)
        return NOTIFY_STATUS_INVALID_PORT;
    uint32_t p;
    if (flags & NOTIFY_REUSE) {
        if (!ferry_mach_is_receive(*port))
            return NOTIFY_STATUS_INVALID_PORT;
        p = *port;
    } else {
        p = ferry_mach_new_receive();
        if (!p)
            return NOTIFY_STATUS_FAILED;
    }
    pthread_mutex_lock(&nlock);
    struct reg *r = add(name, K_PORT, out);
    if (r)
        r->port = p;
    pthread_mutex_unlock(&nlock);
    if (!r)
        return name ? NOTIFY_STATUS_FAILED : NOTIFY_STATUS_INVALID_NAME;
    *port = p;
    return NOTIFY_STATUS_OK;
}

static uint32_t mac_notify_register_file_descriptor(const char *name, int *fd, int flags, int *out)
{
    if (!fd)
        return NOTIFY_STATUS_INVALID_FILE;
    pthread_mutex_lock(&nlock);
    int rfd = -1, wfd = -1;
    if (flags & NOTIFY_REUSE) {
        for (struct reg *r = regs; r; r = r->next)
            if (r->kind == K_FD && r->rfd == *fd) {
                rfd = r->rfd;
                wfd = r->wfd;
                break;
            }
        if (rfd < 0) {
            pthread_mutex_unlock(&nlock);
            return NOTIFY_STATUS_INVALID_FILE;
        }
    } else {
        int p[2];
        if (pipe2(p, O_CLOEXEC) < 0) {
            pthread_mutex_unlock(&nlock);
            return NOTIFY_STATUS_FAILED;
        }
        fcntl(p[1], F_SETFL, O_NONBLOCK);
        rfd = p[0];
        wfd = p[1];
    }
    struct reg *r = add(name, K_FD, out);
    if (r) {
        r->rfd = rfd;
        r->wfd = wfd;
        *fd = rfd;
    }
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : name ? NOTIFY_STATUS_FAILED : NOTIFY_STATUS_INVALID_NAME;
}

static uint32_t mac_notify_check(int token, int *check)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = find(token);
    uint32_t s = NOTIFY_STATUS_INVALID_TOKEN;
    if (r) {
        if (check)
            *check = r->checked;
        r->checked = 0;
        s = NOTIFY_STATUS_OK;
    }
    pthread_mutex_unlock(&nlock);
    return s;
}

static uint32_t mac_notify_cancel(int token)
{
    pthread_mutex_lock(&nlock);
    struct reg **pp = &regs, *r = NULL;
    for (; *pp; pp = &(*pp)->next)
        if ((*pp)->token == token) {
            r = *pp;
            *pp = r->next;
            break;
        }
    if (r && r->kind == K_FD) {
        int shared = 0;
        for (struct reg *o = regs; o; o = o->next)
            shared |= o->kind == K_FD && o->wfd == r->wfd;
        if (!shared) {
            close(r->wfd); /* the program closes its read end */
        }
    }
    pthread_mutex_unlock(&nlock);
    if (!r)
        return NOTIFY_STATUS_INVALID_TOKEN;
    if (r->block)
        _Block_release(r->block);
    if (r->queue)
        dispatch_release(r->queue);
    free(r->name);
    free(r);
    return NOTIFY_STATUS_OK;
}

static uint32_t mac_notify_suspend(int token)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = find(token);
    if (r)
        r->suspended++;
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : NOTIFY_STATUS_INVALID_TOKEN;
}

static uint32_t mac_notify_resume(int token)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = find(token);
    if (r && r->suspended && !--r->suspended && r->missed) {
        r->missed = 0;
        deliver(r); /* the posts it missed come as one */
    }
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : NOTIFY_STATUS_INVALID_TOKEN;
}

static uint32_t mac_notify_get_state(int token, uint64_t *state)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = find(token);
    if (r && state) {
        struct state *s = state_for(r->name, 0);
        *state = s ? s->value : 0;
    }
    pthread_mutex_unlock(&nlock);
    return r ? NOTIFY_STATUS_OK : NOTIFY_STATUS_INVALID_TOKEN;
}

static uint32_t mac_notify_set_state(int token, uint64_t state)
{
    pthread_mutex_lock(&nlock);
    struct reg *r = find(token);
    struct state *s = r ? state_for(r->name, 1) : NULL;
    if (s)
        s->value = state;
    pthread_mutex_unlock(&nlock);
    return r ? (s ? NOTIFY_STATUS_OK : NOTIFY_STATUS_FAILED) : NOTIFY_STATUS_INVALID_TOKEN;
}

static int mac_notify_is_valid_token(int token)
{
    pthread_mutex_lock(&nlock);
    int ok = find(token) != NULL;
    pthread_mutex_unlock(&nlock);
    return ok;
}

/* notify_monitor_file: no files are watched for names here */
static uint32_t mac_notify_monitor_file(int token, const char *path, int flags)
{
    (void)path;
    (void)flags;
    return mac_notify_is_valid_token(token) ? NOTIFY_STATUS_OK : NOTIFY_STATUS_INVALID_TOKEN;
}

const struct ferry_symbol ferry_notify_symbols[] = {
    {"notify_post", mac_notify_post},
    {"notify_register_dispatch", mac_notify_register_dispatch},
    {"notify_register_check", mac_notify_register_check},
    {"notify_register_plain", mac_notify_register_plain},
    {"notify_register_signal", mac_notify_register_signal},
    {"notify_register_mach_port", mac_notify_register_mach_port},
    {"notify_register_file_descriptor", mac_notify_register_file_descriptor},
    {"notify_check", mac_notify_check},
    {"notify_cancel", mac_notify_cancel},
    {"notify_suspend", mac_notify_suspend},
    {"notify_resume", mac_notify_resume},
    {"notify_get_state", mac_notify_get_state},
    {"notify_set_state", mac_notify_set_state},
    {"notify_is_valid_token", mac_notify_is_valid_token},
    {"notify_monitor_file", mac_notify_monitor_file},
    {NULL, NULL},
};
