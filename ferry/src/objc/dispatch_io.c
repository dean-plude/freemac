/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Dispatch data objects and dispatch I/O (freemac 1.232, Ferry 0.56.0),
 * written from Apple's public documentation of libdispatch; no Apple code
 * was used. Qt reads and writes files with them on a Mac
 * (QRandomAccessAsyncFile), and so do OBS and VLC through Qt.
 *
 * A data object is an immutable run of bytes, kept here always in one
 * piece: making one from two others copies them into one buffer, so a map
 * is the object itself and an apply sees one region. A Mac may keep the
 * pieces apart; a program can't tell, beyond being called once.
 *
 * A channel has a serial queue of its own: its reads, writes and barriers
 * run on it one after another, in the order they were asked for, doing
 * plain blocking reads and writes on one of dispatch's worker threads.
 * Each read or write reports once, when it is done, with all its data (a
 * Mac may also report parts before that, with done false). A channel made
 * from a path opens the file at its first read or write, and closes it
 * when the channel is closed; one made from a descriptor leaves it open,
 * and its cleanup handler says when the program may close it.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../ferry.h"
#include "objc-private.h"

#define M(sel, types, fn) {sel, types, (IMP)(void (*)(void))(fn)}
/* Handlers get a Mac errno: ECANCELED is 89 there. */
#define MAC_ECANCELED 89

struct block_header {
    Class isa;
    int32_t flags, reserved;
    void (*invoke)(void *, ...);
    void *descriptor;
};
void *_Block_copy(const void *);
void _Block_release(const void *);
extern struct fobjc_class ferry_block_global;

/* dispatch.c's calls, which take its queue objects */
void *dispatch_queue_create(const char *label, void *attr);
void dispatch_async_f(void *queue, void *ctx, void (*fn)(void *));
void *dispatch_get_global_queue(long priority, unsigned long flags);

static struct fobjc_class data_class, data_meta, data_static_class, data_static_meta;
static struct fobjc_class io_class, io_meta;

/* ---- data objects -------------------------------------------------------------- */

enum owner { O_STATIC, O_FREE, O_MUNMAP, O_BLOCK };

struct ddata {
    Class isa;
    void *buf;
    size_t size;
    enum owner owner;
    void *destructor; /* a copied block, for O_BLOCK */
    void *dqueue;     /* where it is called (retained) */
};

/* the empty object, and the two destructors a program names by address */
struct ddata ferry_dispatch_data_empty;
static void destructor_noop(void *b) { (void)b; }
static struct block_header destructor_free_block, destructor_munmap_block;
static void *destructor_free_ptr = &destructor_free_block;
static void *destructor_munmap_ptr = &destructor_munmap_block;

static void call_block_and_release(void *b)
{
    ((void (*)(void *))((struct block_header *)b)->invoke)(b);
    _Block_release(b);
}

static void data_dealloc(struct ddata *self, SEL _cmd)
{
    (void)_cmd;
    switch (self->owner) {
    case O_FREE: free(self->buf); break;
    case O_MUNMAP:
        if (self->buf)
            munmap(self->buf, self->size);
        break;
    case O_BLOCK:
        dispatch_async_f(self->dqueue ? self->dqueue : dispatch_get_global_queue(0, 0), self->destructor,
                         call_block_and_release);
        if (self->dqueue)
            objc_release((id)self->dqueue);
        break;
    case O_STATIC: break;
    }
    object_dispose((id)self);
}

static struct ddata *new_data(void *buf, size_t size, enum owner owner)
{
    if (!size) {
        if (owner == O_FREE)
            free(buf);
        return &ferry_dispatch_data_empty;
    }
    struct ddata *d = (struct ddata *)class_createInstance(&data_class, 0);
    d->buf = buf;
    d->size = size;
    d->owner = owner;
    return d;
}

/* a copy of size bytes, or NULL when memory has run out */
static struct ddata *copy_data(const void *buf, size_t size)
{
    if (!size)
        return &ferry_dispatch_data_empty;
    void *copy = malloc(size);
    if (!copy)
        return NULL;
    memcpy(copy, buf, size);
    return new_data(copy, size, O_FREE);
}

static struct ddata *dispatch_data_create(const void *buffer, size_t size, void *queue, void *destructor)
{
    if (!buffer || !size) {
        if (destructor && destructor != destructor_free_ptr && destructor != destructor_munmap_ptr)
            dispatch_async_f(queue ? queue : dispatch_get_global_queue(0, 0), _Block_copy(destructor),
                             call_block_and_release);
        else if (destructor == destructor_free_ptr)
            free((void *)buffer);
        return &ferry_dispatch_data_empty;
    }
    if (!destructor)
        return copy_data(buffer, size);
    if (destructor == destructor_free_ptr)
        return new_data((void *)buffer, size, O_FREE);
    if (destructor == destructor_munmap_ptr)
        return new_data((void *)buffer, size, O_MUNMAP);
    struct ddata *d = new_data((void *)buffer, size, O_BLOCK);
    d->destructor = _Block_copy(destructor);
    d->dqueue = queue ? objc_retain((id)queue) : NULL;
    return d;
}

static size_t dispatch_data_get_size(struct ddata *d) { return d ? d->size : 0; }

static struct ddata *dispatch_data_create_map(struct ddata *d, const void **buffer_ptr, size_t *size_ptr)
{
    if (!d)
        d = &ferry_dispatch_data_empty;
    if (buffer_ptr)
        *buffer_ptr = d->buf;
    if (size_ptr)
        *size_ptr = d->size;
    return (struct ddata *)objc_retain((id)d);
}

static struct ddata *dispatch_data_create_concat(struct ddata *a, struct ddata *b)
{
    size_t na = a ? a->size : 0, nb = b ? b->size : 0;
    if (!nb)
        return (struct ddata *)objc_retain((id)(a ? a : &ferry_dispatch_data_empty));
    if (!na)
        return (struct ddata *)objc_retain((id)b);
    char *buf = malloc(na + nb);
    if (!buf)
        return NULL;
    memcpy(buf, a->buf, na);
    memcpy(buf + na, b->buf, nb);
    return new_data(buf, na + nb, O_FREE);
}

static struct ddata *dispatch_data_create_subrange(struct ddata *d, size_t offset, size_t length)
{
    if (!d || offset >= d->size || !length)
        return &ferry_dispatch_data_empty;
    if (length > d->size - offset)
        length = d->size - offset;
    if (offset == 0 && length == d->size)
        return (struct ddata *)objc_retain((id)d);
    return copy_data((char *)d->buf + offset, length);
}

/* The one region that holds location: the whole object, which starts at 0. */
static struct ddata *dispatch_data_copy_region(struct ddata *d, size_t location, size_t *offset_ptr)
{
    if (offset_ptr)
        *offset_ptr = 0;
    if (!d || location >= d->size)
        return &ferry_dispatch_data_empty;
    return (struct ddata *)objc_retain((id)d);
}

static bool dispatch_data_apply(struct ddata *d, void *applier)
{
    if (!d || !d->size || !applier)
        return true;
    struct block_header *b = applier;
    return ((bool (*)(void *, struct ddata *, size_t, const void *, size_t))(void (*)(void))b->invoke)(b, d, 0, d->buf, d->size);
}

/* ---- channels ------------------------------------------------------------------ */

struct dio {
    Class isa;
    int fd, type, owns_fd, opened;
    volatile int stopped, closed;
    char *path;
    int oflag;
    mode_t mode;
    int error;            /* why the path couldn't be opened */
    void *queue;          /* the channel's own serial queue */
    void *cleanup;        /* a copied block, called once with an error */
    void *cleanup_queue;  /* retained */
    int cleaned;
};

static void cleanup_call(void *ctx);
struct cleanup_ctx {
    void *block;
    int error;
};

/* Calls the cleanup handler once, on its queue. */
static void run_cleanup(struct dio *c, int error)
{
    if (c->cleaned)
        return;
    c->cleaned = 1;
    if (c->owns_fd && c->opened && c->fd >= 0)
        close(c->fd);
    if (c->owns_fd)
        c->fd = -1;
    if (c->cleanup) {
        struct cleanup_ctx *x = malloc(sizeof *x);
        if (x) {
            x->block = c->cleanup;
            x->error = error;
            dispatch_async_f(c->cleanup_queue ? c->cleanup_queue : dispatch_get_global_queue(0, 0), x,
                             cleanup_call);
        } else
            _Block_release(c->cleanup);
        c->cleanup = NULL;
    }
}

static void cleanup_call(void *ctx)
{
    struct cleanup_ctx *x = ctx;
    struct block_header *b = x->block;
    ((void (*)(void *, int))b->invoke)(b, x->error);
    _Block_release(b);
    free(x);
}

static void io_dealloc(struct dio *self, SEL _cmd)
{
    (void)_cmd;
    run_cleanup(self, 0);
    if (self->cleanup_queue)
        objc_release((id)self->cleanup_queue);
    if (self->queue)
        objc_release((id)self->queue);
    free(self->path);
    object_dispose((id)self);
}

static struct dio *new_channel(int type, void *queue, void *cleanup)
{
    if (type != 0 && type != 1)
        return NULL;
    struct dio *c = (struct dio *)class_createInstance(&io_class, 0);
    c->type = type;
    c->fd = -1;
    c->queue = dispatch_queue_create("com.apple.libdispatch-io.channelq", NULL);
    c->cleanup = cleanup ? _Block_copy(cleanup) : NULL;
    c->cleanup_queue = queue ? objc_retain((id)queue) : NULL;
    return c;
}

static struct dio *dispatch_io_create(unsigned long type, int fd, void *queue, void *cleanup)
{
    if (fd < 0)
        return NULL;
    struct dio *c = new_channel((int)type, queue, cleanup);
    if (c) {
        c->fd = fd;
        c->opened = 1;
    }
    return c;
}

static struct dio *dispatch_io_create_with_path(unsigned long type, const char *path, int oflag, mode_t mode,
                                                void *queue, void *cleanup)
{
    if (!path || path[0] != '/')
        return NULL;
    struct dio *c = new_channel((int)type, queue, cleanup);
    if (c) {
        c->path = strdup(path);
        /* the Mac's open flags are translated when the file is opened */
        c->oflag = oflag;
        c->mode = mode;
        c->owns_fd = 1;
    }
    return c;
}

static struct dio *dispatch_io_create_with_io(unsigned long type, struct dio *other, void *queue, void *cleanup)
{
    if (!other)
        return NULL;
    if (other->path)
        return dispatch_io_create_with_path(type, other->path, other->oflag, other->mode, queue, cleanup);
    return dispatch_io_create(type, other->fd, queue, cleanup);
}

/* Opens a path channel's file, on its queue, the first time it's needed. */
static int channel_fd(struct dio *c)
{
    if (c->opened)
        return c->fd;
    c->opened = 1;
    c->fd = open(c->path, ferry_open_flags_from_mac(c->oflag) | O_CLOEXEC, c->mode);
    if (c->fd < 0)
        c->error = ferry_errno_to_mac(errno);
    return c->fd;
}

static int dispatch_io_get_descriptor(struct dio *c) { return c ? c->fd : -1; }
static void dispatch_io_set_high_water(struct dio *c, size_t n) { (void)c, (void)n; }
static void dispatch_io_set_low_water(struct dio *c, size_t n) { (void)c, (void)n; }
static void dispatch_io_set_interval(struct dio *c, uint64_t i, unsigned long f) { (void)c, (void)i, (void)f; }

/* Waits until a descriptor that isn't blocking can be read or written. */
static void wait_fd(int fd, short events)
{
    struct pollfd p = {fd, events, 0};
    while (poll(&p, 1, -1) < 0 && errno == EINTR)
        ;
}

/* Reads up to length bytes (all of the file, for SIZE_MAX) into a new data
 * object, at offset when it isn't -1. */
static int read_all(int fd, off_t offset, size_t length, struct ddata **out)
{
    size_t cap = length < 65536 ? (length ? length : 1) : 65536, got = 0;
    char *buf = malloc(cap);
    int err = 0;
    if (!buf)
        return ENOMEM;
    while (got < length) {
        if (got == cap) {
            size_t ncap = cap * 2 < length ? cap * 2 : length;
            char *nb = realloc(buf, ncap);
            if (!nb) {
                err = ENOMEM;
                break;
            }
            buf = nb;
            cap = ncap;
        }
        ssize_t n = offset >= 0 ? pread(fd, buf + got, cap - got, offset + (off_t)got) : read(fd, buf + got, cap - got);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN) {
                wait_fd(fd, POLLIN);
                continue;
            }
            err = ferry_errno_to_mac(errno);
            break;
        }
        if (n == 0)
            break;
        got += (size_t)n;
    }
    *out = new_data(buf, got, O_FREE); /* frees buf when nothing was read */
    return err;
}

/* Writes all of d, at offset when it isn't -1; what wasn't written goes in *rest. */
static int write_all(int fd, off_t offset, struct ddata *d, struct ddata **rest)
{
    size_t done = 0, size = d ? d->size : 0;
    int err = 0;
    while (done < size) {
        ssize_t n = offset >= 0 ? pwrite(fd, (char *)d->buf + done, size - done, offset + (off_t)done)
                                : write(fd, (char *)d->buf + done, size - done);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN) {
                wait_fd(fd, POLLOUT);
                continue;
            }
            err = ferry_errno_to_mac(errno);
            break;
        }
        done += (size_t)n;
    }
    *rest = err ? dispatch_data_create_subrange(d, done, size - done) : NULL;
    return err;
}

enum op_kind { OP_READ, OP_WRITE, OP_BARRIER, OP_CLOSE };

struct op {
    enum op_kind kind;
    struct dio *c;        /* retained */
    off_t offset;
    size_t length;
    struct ddata *data;   /* to write (retained) */
    void *handler;        /* a copied block */
    void *hqueue;         /* retained */
    /* the answer, on the handler's queue */
    bool done;
    struct ddata *result;
    int error;
};

static void op_free(struct op *o)
{
    if (o->data)
        objc_release((id)o->data);
    if (o->result)
        objc_release((id)o->result);
    if (o->handler)
        _Block_release(o->handler);
    if (o->hqueue)
        objc_release((id)o->hqueue);
    if (o->c)
        objc_release((id)o->c);
    free(o);
}

/* Calls an I/O handler, (done, data, error), on its queue. */
static void op_report(void *ctx)
{
    struct op *o = ctx;
    struct block_header *b = o->handler;
    if (b)
        ((void (*)(void *, bool, struct ddata *, int))b->invoke)(b, o->done, o->result, o->error);
    op_free(o);
}

static void op_run(void *ctx)
{
    struct op *o = ctx;
    struct dio *c = o->c;
    switch (o->kind) {
    case OP_BARRIER: {
        struct block_header *b = o->handler;
        ((void (*)(void *))b->invoke)(b);
        op_free(o);
        return;
    }
    case OP_CLOSE:
        c->closed = 1;
        run_cleanup(c, c->stopped ? MAC_ECANCELED : c->error);
        op_free(o);
        return;
    case OP_READ:
    case OP_WRITE: break;
    }
    o->done = true;
    int fd = (c->stopped || c->cleaned) ? -1 : channel_fd(c);
    if (c->stopped || c->cleaned)
        o->error = MAC_ECANCELED;
    else if (fd < 0)
        o->error = c->error ? c->error : EBADF;
    else if (o->kind == OP_READ)
        o->error = read_all(fd, c->type == 1 ? o->offset : -1, o->length, &o->result);
    else
        o->error = write_all(fd, c->type == 1 ? o->offset : -1, o->data, &o->result);
    if (o->kind == OP_READ && !o->result)
        o->result = (struct ddata *)objc_retain((id)&ferry_dispatch_data_empty);
    dispatch_async_f(o->hqueue ? o->hqueue : dispatch_get_global_queue(0, 0), o, op_report);
}

static void queue_op(struct dio *c, enum op_kind kind, off_t offset, size_t length, struct ddata *data, void *queue,
                     void *handler)
{
    if (!c)
        return;
    struct op *o = calloc(1, sizeof *o);
    if (!o)
        return;
    o->kind = kind;
    o->c = (struct dio *)objc_retain((id)c);
    o->offset = offset;
    o->length = length;
    o->data = data ? (struct ddata *)objc_retain((id)data) : NULL;
    o->handler = handler ? _Block_copy(handler) : NULL;
    o->hqueue = queue ? objc_retain((id)queue) : NULL;
    if (c->closed && (kind == OP_READ || kind == OP_WRITE)) {
        /* a channel that was closed takes no more work */
        o->done = true;
        o->error = MAC_ECANCELED;
        dispatch_async_f(o->hqueue ? o->hqueue : dispatch_get_global_queue(0, 0), o, op_report);
        return;
    }
    dispatch_async_f(c->queue, o, op_run);
}

static void dispatch_io_read(struct dio *c, off_t offset, size_t length, void *queue, void *handler)
{
    queue_op(c, OP_READ, offset, length, NULL, queue, handler);
}

static void dispatch_io_write(struct dio *c, off_t offset, struct ddata *data, void *queue, void *handler)
{
    queue_op(c, OP_WRITE, offset, 0, data, queue, handler);
}

static void dispatch_io_barrier(struct dio *c, void *barrier)
{
    if (barrier)
        queue_op(c, OP_BARRIER, 0, 0, NULL, NULL, barrier);
}

static void dispatch_io_close(struct dio *c, unsigned long flags)
{
    if (!c || c->closed)
        return;
    if (flags & 1) /* DISPATCH_IO_STOP: what is waiting is cancelled */
        c->stopped = 1;
    c->closed = 1;
    queue_op(c, OP_CLOSE, 0, 0, NULL, NULL, NULL);
}

/* ---- dispatch_read and dispatch_write ------------------------------------------- */

struct simple {
    int fd, write;
    size_t length;
    struct ddata *data, *result;
    void *handler, *queue;
    int error;
};

static void simple_report(void *ctx)
{
    struct simple *s = ctx;
    struct block_header *b = s->handler;
    ((void (*)(void *, struct ddata *, int))b->invoke)(b, s->result, s->error);
    _Block_release(b);
    if (s->result)
        objc_release((id)s->result);
    if (s->data)
        objc_release((id)s->data);
    if (s->queue)
        objc_release((id)s->queue);
    free(s);
}

static void simple_run(void *ctx)
{
    struct simple *s = ctx;
    if (s->write)
        s->error = write_all(s->fd, -1, s->data, &s->result);
    else {
        s->error = read_all(s->fd, -1, s->length, &s->result);
        if (!s->result)
            s->result = (struct ddata *)objc_retain((id)&ferry_dispatch_data_empty);
    }
    dispatch_async_f(s->queue ? s->queue : dispatch_get_global_queue(0, 0), s, simple_report);
}

static void start_simple(int fd, int write, size_t length, struct ddata *data, void *queue, void *handler)
{
    if (!handler)
        return;
    struct simple *s = calloc(1, sizeof *s);
    if (!s)
        return;
    s->fd = fd;
    s->write = write;
    s->length = length;
    s->data = data ? (struct ddata *)objc_retain((id)data) : NULL;
    s->handler = _Block_copy(handler);
    s->queue = queue ? objc_retain((id)queue) : NULL;
    dispatch_async_f(dispatch_get_global_queue(0, 0), s, simple_run);
}

static void dispatch_read(int fd, size_t length, void *queue, void *handler)
{
    start_simple(fd, 0, length, NULL, queue, handler);
}

static void dispatch_write(int fd, struct ddata *data, void *queue, void *handler)
{
    start_simple(fd, 1, 0, data, queue, handler);
}

/* ---- setup ------------------------------------------------------------------ */

void ferry_dispatch_io_init(void)
{
    static const struct fmethod data_methods[] = {M("dealloc", "v16@0:8", data_dealloc)};
    static const struct fmethod io_methods[] = {M("dealloc", "v16@0:8", io_dealloc)};
    ferry_objc_make_class(&data_class, &data_meta, &ferry_class_NSObject, "OS_dispatch_data", sizeof(struct ddata),
                          data_methods, 1, NULL, 0, 0);
    ferry_objc_make_class(&data_static_class, &data_static_meta, &ferry_class_NSObject, "OS_dispatch_data_empty",
                          sizeof(struct ddata), ferry_static_rr_methods, ferry_static_rr_count, NULL, 0,
                          RT_STATIC_INSTANCES);
    ferry_objc_make_class(&io_class, &io_meta, &ferry_class_NSObject, "OS_dispatch_io", sizeof(struct dio),
                          io_methods, 1, NULL, 0, 0);
    ferry_dispatch_data_empty.isa = &data_static_class;
    ferry_dispatch_data_empty.owner = O_STATIC;
    destructor_free_block.isa = &ferry_block_global;
    destructor_free_block.flags = 1 << 28; /* BLOCK_IS_GLOBAL */
    destructor_free_block.invoke = (void (*)(void *, ...))destructor_noop;
    destructor_munmap_block = destructor_free_block;
}

#define F(name) {#name, (void *)name}
const struct ferry_symbol ferry_dispatch_io_symbols[] = {
    {"_dispatch_data_empty", &ferry_dispatch_data_empty},
    {"_dispatch_data_destructor_free", &destructor_free_ptr},
    {"_dispatch_data_destructor_munmap", &destructor_munmap_ptr},
    F(dispatch_data_create), F(dispatch_data_get_size), F(dispatch_data_create_map), F(dispatch_data_create_concat),
    F(dispatch_data_create_subrange), F(dispatch_data_copy_region), F(dispatch_data_apply),
    F(dispatch_io_create), F(dispatch_io_create_with_path), F(dispatch_io_create_with_io), F(dispatch_io_read),
    F(dispatch_io_write), F(dispatch_io_barrier), F(dispatch_io_close), F(dispatch_io_get_descriptor),
    F(dispatch_io_set_high_water), F(dispatch_io_set_low_water), F(dispatch_io_set_interval), F(dispatch_read),
    F(dispatch_write),
    {NULL, NULL},
};
