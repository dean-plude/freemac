/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Mach ports and messages within one process (freemac 1.265), written from
 * Apple's public Mach documentation (the mach_port_* and mach_msg reference
 * pages, "Kernel Programming Guide: Mach Overview") and the Mach 3 kernel
 * interface and principles books.
 *
 * Chromium, and with it every Electron app, carries all of its own
 * messages on Mach ports: its message loops wait on a port set in a
 * kqueue, its threads post to each other through ports, and its services
 * check in with the bootstrap server. Here a port is an object of
 * Ferry's own:
 *
 *  - The task has one name space. A name is an index and a generation, as
 *    on a Mac (0x1103, 0x2203 ...), above every thread and task port name
 *    Ferry hands out. A name holds a receive right, send rights (counted
 *    in user references), a send-once right, a port set or a dead name.
 *  - A port keeps its queue of messages. A message's rights travel with it
 *    (moved, copied or made, as each disposition says) and come out as
 *    names in the receiver's space; out-of-line memory is copied into fresh
 *    pages, as on a Mac. The trailer asked for (up to the audit token and
 *    the port's context) follows the message.
 *  - Destroying a receive right turns every send right to it into a dead
 *    name, and sends the dead-name notifications asked for; the last send
 *    right going away sends the no-senders notification. Destroying a
 *    message with a send-once right in it sends the send-once notification.
 *  - Port sets: receiving on a set takes a message from any of its ports.
 *  - Each port and port set has an eventfd that is readable while messages
 *    wait, so kqueue's EVFILT_MACHPORT and dispatch's mach_recv sources
 *    can wait on it with everything else.
 *  - The bootstrap server: a service a program checks in is looked up by
 *    the same program. Services in other processes aren't found yet.
 *
 * A sender waits while a queue holds as many messages as its limit, as on
 * a Mac (MACH_SEND_TIMEOUT gives up with MACH_SEND_TIMED_OUT); a send-once
 * right and the kernel's own notifications always get through.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"

typedef uint32_t mac_port_t;
typedef int kern_return_t;

#define KERN_SUCCESS 0
#define KERN_INVALID_ADDRESS 1
#define KERN_INVALID_ARGUMENT 4
#define KERN_FAILURE 5
#define KERN_RESOURCE_SHORTAGE 6
#define KERN_NOT_RECEIVER 7
#define KERN_ALREADY_IN_SET 11
#define KERN_NOT_IN_SET 12
#define KERN_NAME_EXISTS 13
#define KERN_INVALID_NAME 15
#define KERN_INVALID_TASK 16
#define KERN_INVALID_RIGHT 17
#define KERN_INVALID_VALUE 18
#define KERN_UREFS_OVERFLOW 19
#define KERN_INVALID_CAPABILITY 20
#define KERN_RIGHT_EXISTS 21

#define MACH_PORT_NULL 0u
#define MACH_PORT_DEAD 0xffffffffu

#define MACH_PORT_RIGHT_SEND 0
#define MACH_PORT_RIGHT_RECEIVE 1
#define MACH_PORT_RIGHT_SEND_ONCE 2
#define MACH_PORT_RIGHT_PORT_SET 3
#define MACH_PORT_RIGHT_DEAD_NAME 4

#define T_SEND (1u << 16)
#define T_RECEIVE (1u << 17)
#define T_SEND_ONCE (1u << 18)
#define T_PORT_SET (1u << 19)
#define T_DEAD_NAME (1u << 20)
#define T_DNREQUEST 0x80000000u

#define MOVE_RECEIVE 16
#define MOVE_SEND 17
#define MOVE_SEND_ONCE 18
#define COPY_SEND 19
#define MAKE_SEND 20
#define MAKE_SEND_ONCE 21
#define COPY_RECEIVE 22
#define DISPOSE_RECEIVE 24
#define DISPOSE_SEND 25
#define DISPOSE_SEND_ONCE 26

#define MACH_MSGH_BITS_COMPLEX 0x80000000u

#define MACH_SEND_MSG 0x1
#define MACH_RCV_MSG 0x2
#define MACH_RCV_LARGE 0x4
#define MACH_SEND_TIMEOUT 0x10
#define MACH_RCV_TIMEOUT 0x100

#define MACH_SEND_MSG_TOO_SMALL 0x10000008
#define MACH_SEND_TIMED_OUT 0x10000004
#define MACH_SEND_INVALID_DATA 0x10000002
#define MACH_SEND_INVALID_DEST 0x10000003
#define MACH_SEND_INVALID_REPLY 0x10000009
#define MACH_SEND_INVALID_RIGHT 0x1000000a
#define MACH_SEND_INVALID_MEMORY 0x1000000c
#define MACH_SEND_INVALID_TYPE 0x1000000f
#define MACH_SEND_INVALID_HEADER 0x10000010
#define MACH_RCV_INVALID_NAME 0x10004002
#define MACH_RCV_TIMED_OUT 0x10004003
#define MACH_RCV_TOO_LARGE 0x10004004
#define MACH_RCV_PORT_DIED 0x10004009
#define MACH_RCV_PORT_CHANGED 0x10004006

#define MACH_NOTIFY_PORT_DELETED 65
#define MACH_NOTIFY_SEND_POSSIBLE 66
#define MACH_NOTIFY_PORT_DESTROYED 69
#define MACH_NOTIFY_NO_SENDERS 70
#define MACH_NOTIFY_SEND_ONCE 71
#define MACH_NOTIFY_DEAD_NAME 72

#define MACH_MSG_PORT_DESCRIPTOR 0
#define MACH_MSG_OOL_DESCRIPTOR 1
#define MACH_MSG_OOL_PORTS_DESCRIPTOR 2
#define MACH_MSG_OOL_VOLATILE_DESCRIPTOR 3
#define MACH_MSG_GUARDED_PORT_DESCRIPTOR 4

#define MACH_PORT_LIMITS_INFO 1
#define MACH_PORT_RECEIVE_STATUS 2
#define MACH_PORT_DNREQUESTS_SIZE 3
#define MACH_PORT_QLIMIT_DEFAULT 5
#define MACH_PORT_QLIMIT_MAX 1024

#define MPO_CONTEXT_AS_GUARD 0x01
#define MPO_QLIMIT 0x02
#define MPO_INSERT_SEND_RIGHT 0x10

#define BOOTSTRAP_NOT_PRIVILEGED 1100
#define BOOTSTRAP_NAME_IN_USE 1101
#define BOOTSTRAP_UNKNOWN_SERVICE 1102
#define BOOTSTRAP_SERVICE_ACTIVE 1103

/* the task port and the host port (sysctl.c), and the bootstrap port */
#define TASK_PORT 0x103u
#define HOST_PORT 0x203u
#define BOOTSTRAP_PORT 0x303u

struct mach_header_ {
    uint32_t bits, size;
    mac_port_t remote, local, voucher;
    int32_t id;
};

/* ---- ports ------------------------------------------------------------------------ */

struct kmsg;

struct port {
    int refs;            /* names, rights in transit and the set's membership hold it */
    int dead;            /* its receive right is gone */
    int is_set;
    int in_space;        /* its receive right has a name (0: in transit, or dead) */
    mac_port_t name;     /* the name holding its send and receive rights here, or 0 */
    struct kmsg *head, *tail;
    unsigned count, qlimit, seqno;
    unsigned srights, sorights, mscount;
    uint64_t context;
    struct port *set;                 /* the set it belongs to */
    struct port **members;            /* a set's ports */
    unsigned nmembers, cmembers;
    struct port *ns_notify;           /* a send-once right for its no-senders notification */
    unsigned ns_sync;
    int efd, efd_on;                  /* readable while messages wait (a set: in any member) */
    int dead_efd;                     /* readable once it is dead, made when first asked for */
    int kfd;                          /* a memory entry: the shared memory it names, or -1 */
    uint64_t koff, ksize;
    int kprot;
};

struct right {
    struct port *p;
    uint8_t type; /* MOVE_RECEIVE, MOVE_SEND or MOVE_SEND_ONCE */
};

struct kdesc {
    unsigned offset; /* in the body */
    int kind;
    struct right r;           /* a port */
    void *mem;                /* out-of-line memory: a copy */
    size_t mem_size;
    struct right *ports;      /* out-of-line ports */
    unsigned nports;
};

struct kmsg {
    struct kmsg *next;
    uint32_t complex;
    uint32_t size;     /* msgh_size */
    int32_t id;
    uint8_t dest_type; /* MOVE_SEND or MOVE_SEND_ONCE */
    struct right reply;
    unsigned char *body; /* what follows the header */
    unsigned ndesc;
    struct kdesc *desc;
};

struct entry {
    struct port *p;
    uint32_t type;       /* T_ bits */
    uint32_t urefs;      /* send rights or dead-name references */
    uint8_t gen;
    struct port *dn_notify; /* a send-once right for its dead-name notification */
};

static pthread_mutex_t mach_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t mcond = PTHREAD_COND_INITIALIZER;
static struct entry *table;
static unsigned table_len, table_cap;
static unsigned free_hint;

/* Names start above every number Ferry gives a thread, a clock or the
 * task: 0x4000003, 0x4000103 ... */
#define NAME_BASE 0x40000u

static mac_port_t name_of(unsigned i) { return ((NAME_BASE + i) << 8) | table[i].gen; }

static struct entry *entry_of(mac_port_t name)
{
    if (name == MACH_PORT_NULL || name == MACH_PORT_DEAD)
        return NULL;
    unsigned hi = name >> 8;
    if (hi < NAME_BASE)
        return NULL;
    unsigned i = hi - NAME_BASE;
    if (i >= table_len || !table[i].type || table[i].gen != (name & 0xff))
        return NULL;
    return &table[i];
}

/* The entry new_name just gave out, before it holds anything. */
static struct entry *fresh_entry(mac_port_t name)
{
    if (name == MACH_PORT_NULL)
        return NULL;
    return &table[(name >> 8) - NAME_BASE];
}

static int is_ours(mac_port_t name) { return (name >> 8) >= NAME_BASE && name != MACH_PORT_DEAD; }

static mac_port_t new_name(void)
{
    for (unsigned n = 0; n < table_len; n++) {
        unsigned i = (free_hint + n) % table_len;
        if (!table[i].type) {
            free_hint = i + 1;
            table[i].gen = (uint8_t)(table[i].gen + 4);
            if (!table[i].gen)
                table[i].gen = 3;
            return name_of(i);
        }
    }
    if (table_len == table_cap) {
        unsigned cap = table_cap ? table_cap * 2 : 256;
        if (cap > 0xffffffu - NAME_BASE)
            return MACH_PORT_NULL;
        struct entry *t = realloc(table, cap * sizeof *t);
        if (!t)
            return MACH_PORT_NULL;
        memset(t + table_cap, 0, (cap - table_cap) * sizeof *t);
        table = t;
        table_cap = cap;
    }
    unsigned i = table_len++;
    table[i].gen = 3;
    return name_of(i);
}

static void efd_update(struct port *p);

static struct port *port_new(int is_set)
{
    struct port *p = calloc(1, sizeof *p);
    if (!p)
        return NULL;
    p->is_set = is_set;
    p->qlimit = MACH_PORT_QLIMIT_DEFAULT;
    p->efd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    p->dead_efd = -1;
    p->kfd = -1;
    return p;
}

static void port_ref(struct port *p) { p->refs++; }

static void port_unref(struct port *p)
{
    if (--p->refs > 0)
        return;
    if (p->efd >= 0)
        close(p->efd);
    if (p->dead_efd >= 0)
        close(p->dead_efd);
    if (p->kfd >= 0)
        close(p->kfd);
    free(p->members);
    free(p);
}

/* the eventfd says whether messages wait */
static void efd_set(struct port *p, int on)
{
    if (p->efd < 0 || p->efd_on == on)
        return;
    uint64_t v = 1;
    if (on) {
        if (write(p->efd, &v, sizeof v) < 0)
            return;
    } else if (read(p->efd, &v, sizeof v) < 0) {
        return;
    }
    p->efd_on = on;
}

static void efd_update(struct port *p)
{
    if (p->is_set) {
        int any = 0;
        for (unsigned i = 0; i < p->nmembers && !any; i++)
            any = p->members[i]->count > 0;
        efd_set(p, any);
        return;
    }
    efd_set(p, p->count > 0);
    if (p->set)
        efd_update(p->set);
}

static void set_remove(struct port *p)
{
    struct port *s = p->set;
    if (!s)
        return;
    for (unsigned i = 0; i < s->nmembers; i++)
        if (s->members[i] == p) {
            s->members[i] = s->members[--s->nmembers];
            break;
        }
    p->set = NULL;
    efd_update(s);
    port_unref(s);
}

static int set_add(struct port *p, struct port *s)
{
    if (s->nmembers == s->cmembers) {
        unsigned c = s->cmembers ? s->cmembers * 2 : 8;
        struct port **m = realloc(s->members, c * sizeof *m);
        if (!m)
            return KERN_RESOURCE_SHORTAGE;
        s->members = m;
        s->cmembers = c;
    }
    s->members[s->nmembers++] = p;
    p->set = s;
    port_ref(s);
    efd_update(s);
    return KERN_SUCCESS;
}

/* ---- messages the kernel sends: notifications ------------------------------------- */

static void enqueue(struct port *p, struct kmsg *m);
static void destroy_right(struct right r);

static struct kmsg *notice(struct port *to, int32_t id, size_t body_len)
{
    struct kmsg *m = calloc(1, sizeof *m);
    if (!m)
        return NULL;
    m->size = (uint32_t)(sizeof(struct mach_header_) + body_len);
    m->id = id;
    m->dest_type = MOVE_SEND_ONCE;
    m->body = calloc(1, body_len ? body_len : 1);
    (void)to;
    return m;
}

/* Use up a send-once right on a notification: NDR, then a 32-bit value. */
static void send_notice(struct port *to, int32_t id, uint32_t value, int has_value)
{
    to->sorights--;
    if (to->dead) {
        port_unref(to);
        return;
    }
    struct kmsg *m = notice(to, id, has_value ? 12 : 0);
    if (!m) {
        port_unref(to);
        return;
    }
    if (has_value) {
        static const unsigned char ndr[8] = {0, 0, 0, 0, 0, 0, 0, 0}; /* NDR_record: little-endian, IEEE */
        memcpy(m->body, ndr, 8);
        m->body[4] = 1; /* int_rep: little-endian */
        memcpy(m->body + 8, &value, 4);
    }
    enqueue(to, m);
    port_unref(to); /* the right was used up; the message's place in the queue keeps the port */
}

static void no_senders_check(struct port *p)
{
    if (p->srights || !p->ns_notify || p->dead || p->mscount < p->ns_sync)
        return;
    struct port *to = p->ns_notify;
    p->ns_notify = NULL;
    send_notice(to, MACH_NOTIFY_NO_SENDERS, p->mscount, 1);
}

/* ---- rights ---------------------------------------------------------------------- */

static void destroy_kmsg(struct kmsg *m);

static void receive_destroyed(struct port *p);

static void drop_send(struct port *p)
{
    if (p->srights)
        p->srights--;
    no_senders_check(p);
}

/* A right in transit that nobody will receive. */
static void destroy_right(struct right r)
{
    if (!r.p)
        return;
    switch (r.type) {
    case MOVE_RECEIVE:
        receive_destroyed(r.p);
        break;
    case MOVE_SEND:
        drop_send(r.p);
        break;
    case MOVE_SEND_ONCE:
        r.p->sorights--;
        if (!r.p->dead) {
            /* an unused send-once right tells its port it went away */
            r.p->sorights++;
            port_ref(r.p);
            send_notice(r.p, MACH_NOTIFY_SEND_ONCE, 0, 0);
        }
        break;
    }
    port_unref(r.p);
}

/* The receive right is gone: the queue is thrown away, send rights become
 * dead names and their dead-name notifications go out. */
static void receive_destroyed(struct port *p)
{
    if (p->dead)
        return;
    p->dead = 1;
    p->in_space = 0;
    set_remove(p);
    while (p->head) {
        struct kmsg *m = p->head;
        p->head = m->next;
        p->count--;
        destroy_kmsg(m);
    }
    p->tail = NULL;
    efd_set(p, 0);
    if (p->dead_efd >= 0) {
        uint64_t v = 1;
        if (write(p->dead_efd, &v, sizeof v) < 0)
            v = 0;
    }
    if (p->ns_notify) {
        struct port *n = p->ns_notify;
        p->ns_notify = NULL;
        destroy_right((struct right){n, MOVE_SEND_ONCE});
    }
    for (unsigned i = 0; i < table_len; i++) {
        struct entry *e = &table[i];
        if (e->p != p || !(e->type & (T_SEND | T_SEND_ONCE)))
            continue;
        uint32_t urefs = e->type & T_SEND ? e->urefs : 1;
        e->type = T_DEAD_NAME;
        e->urefs = urefs;
        if (p->name == name_of(i))
            p->name = 0;
        e->p = NULL;
        if (e->dn_notify) {
            struct port *n = e->dn_notify;
            e->dn_notify = NULL;
            send_notice(n, MACH_NOTIFY_DEAD_NAME, name_of(i), 1);
        }
        port_unref(p);
    }
    pthread_cond_broadcast(&mcond);
}

static void free_entry(struct entry *e)
{
    if (e->dn_notify) {
        struct port *n = e->dn_notify;
        e->dn_notify = NULL;
        destroy_right((struct right){n, MOVE_SEND_ONCE});
    }
    e->type = 0;
    e->urefs = 0;
    e->p = NULL;
}

/* Take a right out of the space, as a disposition says; the right comes
 * back holding a reference to its port. */
static kern_return_t copyin(mac_port_t name, int disp, struct right *out, int is_dest)
{
    out->p = NULL;
    out->type = 0;
    if (name == MACH_PORT_NULL || name == MACH_PORT_DEAD)
        return KERN_SUCCESS;
    struct entry *e = entry_of(name);
    if (!e)
        return KERN_INVALID_NAME;
    if (e->type & T_DEAD_NAME)
        return KERN_INVALID_CAPABILITY;
    struct port *p = e->p;
    switch (disp) {
    case MAKE_SEND:
        if (!(e->type & T_RECEIVE))
            return KERN_INVALID_RIGHT;
        p->mscount++;
        p->srights++;
        port_ref(p);
        *out = (struct right){p, MOVE_SEND};
        return KERN_SUCCESS;
    case MAKE_SEND_ONCE:
        if (!(e->type & T_RECEIVE))
            return KERN_INVALID_RIGHT;
        p->sorights++;
        port_ref(p);
        *out = (struct right){p, MOVE_SEND_ONCE};
        return KERN_SUCCESS;
    case COPY_SEND:
        if (!(e->type & T_SEND))
            return KERN_INVALID_RIGHT;
        if (p->dead)
            return KERN_INVALID_CAPABILITY;
        p->srights++;
        port_ref(p);
        *out = (struct right){p, MOVE_SEND};
        return KERN_SUCCESS;
    case MOVE_SEND:
        if (!(e->type & T_SEND))
            return KERN_INVALID_RIGHT;
        port_ref(p);
        *out = (struct right){p, MOVE_SEND};
        if (--e->urefs == 0) {
            e->type &= ~T_SEND;
            if (!(e->type & T_RECEIVE)) {
                p->name = 0;
                free_entry(e);
                port_unref(p);
            }
        } else {
            p->srights++; /* the name keeps one, the message has another */
        }
        return KERN_SUCCESS;
    case MOVE_SEND_ONCE:
        if (!(e->type & T_SEND_ONCE))
            return KERN_INVALID_RIGHT;
        *out = (struct right){p, MOVE_SEND_ONCE}; /* the name's reference goes with it */
        free_entry(e);
        return KERN_SUCCESS;
    case MOVE_RECEIVE:
        if (!(e->type & T_RECEIVE) || is_dest)
            return KERN_INVALID_RIGHT;
        set_remove(p);
        p->in_space = 0;
        port_ref(p);
        *out = (struct right){p, MOVE_RECEIVE};
        e->type &= ~T_RECEIVE;
        if (!(e->type & T_SEND)) {
            p->name = 0;
            free_entry(e);
            port_unref(p);
        }
        return KERN_SUCCESS;
    default:
        return KERN_INVALID_VALUE;
    }
}

/* Give a right a name in the space; the right's reference goes to the name. */
static mac_port_t copyout(struct right r)
{
    struct port *p = r.p;
    if (!p)
        return MACH_PORT_NULL;
    if (p->dead && r.type != MOVE_RECEIVE) {
        if (r.type == MOVE_SEND)
            drop_send(p);
        else
            p->sorights--;
        port_unref(p);
        return MACH_PORT_DEAD;
    }
    if (r.type == MOVE_SEND_ONCE) {
        mac_port_t n = new_name();
        struct entry *e = fresh_entry(n);
        if (!e) {
            destroy_right(r);
            return MACH_PORT_NULL;
        }
        e->p = p;
        e->type = T_SEND_ONCE;
        e->urefs = 1;
        return n;
    }
    struct entry *e = p->name ? entry_of(p->name) : NULL;
    if (e) {
        if (r.type == MOVE_SEND) {
            if (e->type & T_SEND) {
                e->urefs++;
                p->srights--; /* merged with the name's own */
            } else {
                e->type |= T_SEND;
                e->urefs = 1;
            }
        } else {
            e->type |= T_RECEIVE;
            p->in_space = 1;
        }
        port_unref(p);
        return p->name;
    }
    mac_port_t n = new_name();
    e = fresh_entry(n);
    if (!e) {
        destroy_right(r);
        return MACH_PORT_NULL;
    }
    e->p = p;
    if (r.type == MOVE_SEND) {
        e->type = T_SEND;
        e->urefs = 1;
    } else {
        e->type = T_RECEIVE;
        p->in_space = 1;
    }
    p->name = n;
    return n;
}

/* ---- the message queue ------------------------------------------------------------- */

static void destroy_kmsg(struct kmsg *m)
{
    destroy_right(m->reply);
    for (unsigned i = 0; i < m->ndesc; i++) {
        struct kdesc *d = &m->desc[i];
        destroy_right(d->r);
        free(d->mem);
        for (unsigned j = 0; j < d->nports; j++)
            destroy_right(d->ports[j]);
        free(d->ports);
    }
    free(m->desc);
    free(m->body);
    free(m);
}

static void enqueue(struct port *p, struct kmsg *m)
{
    port_ref(p);
    m->next = NULL;
    if (p->tail)
        p->tail->next = m;
    else
        p->head = m;
    p->tail = m;
    p->count++;
    efd_update(p);
    pthread_cond_broadcast(&mcond);
}

static struct kmsg *dequeue(struct port *p)
{
    struct kmsg *m = p->head;
    if (!m)
        return NULL;
    p->head = m->next;
    if (!p->head)
        p->tail = NULL;
    p->count--;
    p->seqno++;
    efd_update(p);
    pthread_cond_broadcast(&mcond); /* a sender may wait for room */
    port_unref(p);
    return m;
}

static unsigned trailer_size(int option)
{
    switch ((option >> 24) & 0xf) {
    case 0: return 8;
    case 1: return 12;
    case 2: return 20;
    case 3: return 52;
    case 4: return 60;
    default: return 68;
    }
}

/* ---- sending ------------------------------------------------------------------- */

static unsigned desc_size(int kind) { return kind == MACH_MSG_PORT_DESCRIPTOR ? 12 : 16; }

static void deadline_after(struct timespec *ts, unsigned ms);

/* The kernel takes a message's size from send_size and ignores msgh_size
 * (Chromium's WaitableEvent sends an empty message whose msgh_size is
 * wrong). A sender waits while the queue is at its limit, up to its
 * timeout with MACH_SEND_TIMEOUT. */
static kern_return_t send_locked(struct mach_header_ *h, int option, unsigned send_size, unsigned timeout)
{
    if (send_size < sizeof *h)
        return MACH_SEND_MSG_TOO_SMALL;
    send_size &= ~3u;
    int rdisp = h->bits & 0x1f, ldisp = (h->bits >> 8) & 0x1f;

    /* the destination, and room in its queue */
    struct timespec until;
    if (option & MACH_SEND_TIMEOUT)
        deadline_after(&until, timeout);
    for (;;) {
        struct entry *de = entry_of(h->remote);
        if (!de || (de->type & T_DEAD_NAME) || !de->p || de->p->dead || de->p->is_set)
            return MACH_SEND_INVALID_DEST;
        struct port *dp = de->p;
        /* a send-once right always gets through, as on a Mac */
        if (!dp->qlimit || dp->count < dp->qlimit || rdisp == MOVE_SEND_ONCE || rdisp == MAKE_SEND_ONCE)
            break;
        if ((option & MACH_SEND_TIMEOUT) && timeout == 0)
            return MACH_SEND_TIMED_OUT;
        if (option & MACH_SEND_TIMEOUT) {
            if (pthread_cond_timedwait(&mcond, &mach_lock, &until) == ETIMEDOUT) {
                struct entry *now = entry_of(h->remote);
                if (now && now->p && !now->p->dead && now->p->count >= now->p->qlimit)
                    return MACH_SEND_TIMED_OUT;
            }
        } else {
            pthread_cond_wait(&mcond, &mach_lock);
        }
    }

    struct kmsg *m = calloc(1, sizeof *m);
    if (!m)
        return KERN_RESOURCE_SHORTAGE;
    m->size = send_size;
    m->id = h->id;
    m->complex = h->bits & MACH_MSGH_BITS_COMPLEX;
    size_t body_len = send_size - sizeof *h;
    m->body = malloc(body_len ? body_len : 1);
    if (!m->body) {
        free(m);
        return KERN_RESOURCE_SHORTAGE;
    }
    memcpy(m->body, h + 1, body_len);

    struct right dest;
    if (copyin(h->remote, rdisp, &dest, 1) != KERN_SUCCESS) {
        free(m->body);
        free(m);
        return MACH_SEND_INVALID_DEST;
    }
    m->dest_type = dest.type;
    if (copyin(h->local, ldisp, &m->reply, 0) != KERN_SUCCESS) {
        destroy_right(dest);
        free(m->body);
        free(m);
        return MACH_SEND_INVALID_REPLY;
    }

    /* the descriptors */
    kern_return_t err = KERN_SUCCESS;
    if (m->complex) {
        if (body_len < 4) {
            err = MACH_SEND_MSG_TOO_SMALL;
            goto fail;
        }
        uint32_t n;
        memcpy(&n, m->body, 4);
        m->desc = calloc(n ? n : 1, sizeof *m->desc);
        if (!m->desc) {
            err = KERN_RESOURCE_SHORTAGE;
            goto fail;
        }
        unsigned off = 4;
        for (uint32_t i = 0; i < n; i++) {
            if (off + 12 > body_len) {
                err = MACH_SEND_MSG_TOO_SMALL;
                goto fail;
            }
            unsigned char *d = m->body + off;
            int kind = d[11];
            if (kind > MACH_MSG_GUARDED_PORT_DESCRIPTOR || off + desc_size(kind) > body_len) {
                err = MACH_SEND_INVALID_TYPE;
                goto fail;
            }
            struct kdesc *k = &m->desc[m->ndesc++];
            k->offset = off;
            k->kind = kind;
            if (kind == MACH_MSG_PORT_DESCRIPTOR || kind == MACH_MSG_GUARDED_PORT_DESCRIPTOR) {
                mac_port_t name;
                memcpy(&name, d + (kind == MACH_MSG_PORT_DESCRIPTOR ? 0 : 12), 4);
                if (copyin(name, d[10], &k->r, 0) != KERN_SUCCESS) {
                    err = MACH_SEND_INVALID_RIGHT;
                    goto fail;
                }
            } else if (kind == MACH_MSG_OOL_DESCRIPTOR || kind == MACH_MSG_OOL_VOLATILE_DESCRIPTOR) {
                void *addr;
                uint32_t size;
                memcpy(&addr, d, 8);
                memcpy(&size, d + 12, 4);
                k->mem_size = size;
                if (size) {
                    k->mem = malloc(size);
                    if (!k->mem) {
                        err = MACH_SEND_INVALID_MEMORY;
                        goto fail;
                    }
                    memcpy(k->mem, addr, size);
                    /* deallocate: the sender's pages go, when they are whole pages */
                    long page = sysconf(_SC_PAGESIZE);
                    if (d[8] && !((uintptr_t)addr & (uintptr_t)(page - 1)))
                        munmap(addr, size);
                }
            } else { /* out-of-line ports */
                void *addr;
                uint32_t count;
                memcpy(&addr, d, 8);
                memcpy(&count, d + 12, 4);
                k->nports = 0;
                k->ports = calloc(count ? count : 1, sizeof *k->ports);
                if (!k->ports) {
                    err = KERN_RESOURCE_SHORTAGE;
                    goto fail;
                }
                mac_port_t *names = addr;
                for (uint32_t j = 0; j < count; j++) {
                    if (copyin(names[j], d[10], &k->ports[j], 0) != KERN_SUCCESS) {
                        err = MACH_SEND_INVALID_RIGHT;
                        goto fail;
                    }
                    k->nports = j + 1;
                }
                long page = sysconf(_SC_PAGESIZE);
                if (d[8] && count && !((uintptr_t)addr & (uintptr_t)(page - 1)))
                    munmap(addr, count * sizeof(mac_port_t));
            }
            off += desc_size(kind);
        }
    }
    if (dest.p->dead) {
        destroy_right(dest);
        destroy_kmsg(m);
        return MACH_SEND_INVALID_DEST;
    }
    enqueue(dest.p, m);
    if (dest.type == MOVE_SEND)
        drop_send(dest.p);
    else
        dest.p->sorights--;
    port_unref(dest.p);
    return KERN_SUCCESS;
fail:
    destroy_right(dest);
    destroy_kmsg(m);
    return err;
}

/* ---- receiving ------------------------------------------------------------------- */

/* The port to take a message from: the port, or a member of the set with one. */
static struct port *ready_port(struct port *p)
{
    if (!p->is_set)
        return p->head ? p : NULL;
    for (unsigned i = 0; i < p->nmembers; i++)
        if (p->members[i]->head)
            return p->members[i];
    return NULL;
}

static kern_return_t copyout_msg(struct port *from, struct kmsg *m, struct mach_header_ *h, int option)
{
    h->bits = (m->complex ? MACH_MSGH_BITS_COMPLEX : 0) | ((uint32_t)m->dest_type << 8) |
              (m->reply.p ? (m->reply.type == MOVE_SEND_ONCE ? MOVE_SEND_ONCE : MOVE_SEND) : 0);
    h->size = m->size;
    h->id = m->id;
    h->voucher = 0;
    h->local = from->name;
    h->remote = copyout(m->reply);
    m->reply.p = NULL;
    unsigned char *body = (unsigned char *)(h + 1);
    memcpy(body, m->body, m->size - sizeof *h);
    for (unsigned i = 0; i < m->ndesc; i++) {
        struct kdesc *k = &m->desc[i];
        unsigned char *d = body + k->offset;
        if (k->kind == MACH_MSG_PORT_DESCRIPTOR || k->kind == MACH_MSG_GUARDED_PORT_DESCRIPTOR) {
            uint8_t type = k->r.p ? k->r.type : 0;
            mac_port_t n = copyout(k->r);
            k->r.p = NULL;
            if (k->kind == MACH_MSG_GUARDED_PORT_DESCRIPTOR) {
                memset(d, 0, 12);
                memcpy(d + 12, &n, 4);
            } else {
                memcpy(d, &n, 4);
                memset(d + 4, 0, 6);
            }
            d[10] = type;
        } else if (k->kind == MACH_MSG_OOL_DESCRIPTOR || k->kind == MACH_MSG_OOL_VOLATILE_DESCRIPTOR) {
            void *addr = NULL;
            if (k->mem_size) {
                addr = mmap(NULL, k->mem_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
                if (addr == MAP_FAILED)
                    addr = NULL;
                else
                    memcpy(addr, k->mem, k->mem_size);
            }
            memcpy(d, &addr, 8);
            d[8] = 0;     /* deallocate */
            d[9] = 1;     /* MACH_MSG_VIRTUAL_COPY */
            uint32_t size = (uint32_t)k->mem_size;
            memcpy(d + 12, &size, 4);
        } else {
            mac_port_t *names = NULL;
            uint8_t type = 0;
            if (k->nports) {
                names = mmap(NULL, k->nports * sizeof *names, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS,
                             -1, 0);
                if (names == MAP_FAILED)
                    names = NULL;
            }
            for (unsigned j = 0; j < k->nports; j++) {
                if (k->ports[j].p)
                    type = k->ports[j].type;
                mac_port_t n = copyout(k->ports[j]);
                k->ports[j].p = NULL;
                if (names)
                    names[j] = n;
            }
            memcpy(d, &names, 8);
            d[8] = 0;
            d[9] = 1;
            d[10] = type;
            uint32_t count = k->nports;
            memcpy(d + 12, &count, 4);
        }
    }
    /* the trailer */
    unsigned tsize = trailer_size(option);
    unsigned char t[68];
    memset(t, 0, sizeof t);
    uint32_t v = 0;
    memcpy(t, &v, 4);
    v = tsize;
    memcpy(t + 4, &v, 4);
    v = from->seqno - 1;
    memcpy(t + 8, &v, 4);
    uint32_t uid = (uint32_t)getuid(), gid = (uint32_t)getgid(), pid = (uint32_t)getpid();
    memcpy(t + 12, &uid, 4); /* the sender's security token */
    memcpy(t + 16, &gid, 4);
    uint32_t audit[8] = {uid, uid, gid, uid, gid, pid, pid, 1};
    memcpy(t + 20, audit, 32);
    memcpy(t + 52, &from->context, 8);
    memcpy((unsigned char *)h + m->size, t, tsize);
    m->ndesc = 0; /* every right and copy went to the receiver */
    destroy_kmsg(m);
    return KERN_SUCCESS;
}

static void deadline_after(struct timespec *ts, unsigned ms)
{
    clock_gettime(CLOCK_REALTIME, ts);
    ts->tv_sec += ms / 1000;
    ts->tv_nsec += (long)(ms % 1000) * 1000000L;
    if (ts->tv_nsec >= 1000000000L) {
        ts->tv_sec++;
        ts->tv_nsec -= 1000000000L;
    }
}

static kern_return_t receive_locked(struct mach_header_ *h, int option, unsigned rcv_size, mac_port_t rcv_name,
                                    unsigned timeout)
{
    struct entry *e = entry_of(rcv_name);
    if (!e || !(e->type & (T_RECEIVE | T_PORT_SET)))
        return MACH_RCV_INVALID_NAME;
    struct port *p = e->p;
    port_ref(p);
    struct timespec until;
    if (option & MACH_RCV_TIMEOUT)
        deadline_after(&until, timeout);
    kern_return_t r;
    for (;;) {
        if (p->dead || (!p->is_set && !p->in_space)) {
            r = MACH_RCV_PORT_DIED;
            break;
        }
        struct port *from = ready_port(p);
        if (from) {
            struct kmsg *m = from->head;
            unsigned need = m->size + trailer_size(option);
            if (need > rcv_size) {
                if (option & MACH_RCV_LARGE) {
                    if (rcv_size >= sizeof *h)
                        h->size = need;
                    r = MACH_RCV_TOO_LARGE;
                    break;
                }
                dequeue(from);
                if (rcv_size >= sizeof *h)
                    h->size = need;
                destroy_kmsg(m);
                r = MACH_RCV_TOO_LARGE;
                break;
            }
            port_ref(from);
            dequeue(from);
            r = copyout_msg(from, m, h, option);
            port_unref(from);
            break;
        }
        if ((option & MACH_RCV_TIMEOUT) && timeout == 0) {
            r = MACH_RCV_TIMED_OUT;
            break;
        }
        if (option & MACH_RCV_TIMEOUT) {
            if (pthread_cond_timedwait(&mcond, &mach_lock, &until) == ETIMEDOUT && !ready_port(p)) {
                r = MACH_RCV_TIMED_OUT;
                break;
            }
        } else {
            pthread_cond_wait(&mcond, &mach_lock);
        }
        /* the name may have changed while waiting */
        struct entry *now = entry_of(rcv_name);
        if (!now || now->p != p) {
            r = p->is_set ? MACH_RCV_PORT_CHANGED : MACH_RCV_PORT_DIED;
            break;
        }
    }
    port_unref(p);
    return r;
}

static kern_return_t mac_mach_msg_overwrite(void *msg, int option, unsigned send_size, unsigned rcv_size,
                                            mac_port_t rcv_name, unsigned timeout, mac_port_t notify,
                                            void *rcv_msg, unsigned rcv_limit)
{
    (void)notify;
    (void)rcv_limit;
    kern_return_t r = KERN_SUCCESS;
    pthread_mutex_lock(&mach_lock);
    if (option & MACH_SEND_MSG)
        r = send_locked(msg, option, send_size, timeout);
    if (r == KERN_SUCCESS && (option & MACH_RCV_MSG))
        r = receive_locked(rcv_msg ? rcv_msg : msg, option, rcv_size, rcv_name, timeout);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_msg(void *msg, int option, unsigned send_size, unsigned rcv_size, mac_port_t rcv_name,
                                  unsigned timeout, mac_port_t notify)
{
    return mac_mach_msg_overwrite(msg, option, send_size, rcv_size, rcv_name, timeout, notify, NULL, 0);
}

static kern_return_t mac_mach_msg_send(void *msg)
{
    struct mach_header_ *h = msg;
    return mac_mach_msg(msg, MACH_SEND_MSG, h->size, 0, 0, 0, 0);
}

static kern_return_t mac_mach_msg_receive(void *msg)
{
    struct mach_header_ *h = msg;
    return mac_mach_msg(msg, MACH_RCV_MSG, 0, h->size, h->local, 0, 0);
}

/* ---- the space ---------------------------------------------------------------------- */

static kern_return_t dealloc_locked(mac_port_t name);

/* A received message's rights and memory, given back. */
static void mac_mach_msg_destroy(void *msg)
{
    struct mach_header_ *h = msg;
    pthread_mutex_lock(&mach_lock);
    if (h->remote)
        dealloc_locked(h->remote);
    if (h->bits & MACH_MSGH_BITS_COMPLEX) {
        unsigned char *body = (unsigned char *)(h + 1);
        uint32_t n;
        memcpy(&n, body, 4);
        unsigned off = 4;
        for (uint32_t i = 0; i < n && off + 12 <= h->size - sizeof *h; i++) {
            unsigned char *d = body + off;
            int kind = d[11];
            if (kind == MACH_MSG_PORT_DESCRIPTOR || kind == MACH_MSG_GUARDED_PORT_DESCRIPTOR) {
                mac_port_t name;
                memcpy(&name, d + (kind == MACH_MSG_PORT_DESCRIPTOR ? 0 : 12), 4);
                struct entry *e = entry_of(name);
                if (e && d[10] == MOVE_RECEIVE && (e->type & T_RECEIVE)) {
                    struct port *p = e->p;
                    port_ref(p);
                    receive_destroyed(p);
                    e = entry_of(name);
                    if (e && e->p == p && !(e->type & T_SEND)) {
                        p->name = 0;
                        free_entry(e);
                        port_unref(p);
                    } else if (e && e->p == p) {
                        e->type &= ~T_RECEIVE;
                    }
                    port_unref(p);
                } else if (e) {
                    dealloc_locked(name);
                }
            } else if (kind == MACH_MSG_OOL_DESCRIPTOR || kind == MACH_MSG_OOL_VOLATILE_DESCRIPTOR) {
                void *addr;
                uint32_t size;
                memcpy(&addr, d, 8);
                memcpy(&size, d + 12, 4);
                if (addr && size)
                    munmap(addr, size);
            } else if (kind == MACH_MSG_OOL_PORTS_DESCRIPTOR) {
                mac_port_t *names;
                uint32_t count;
                memcpy(&names, d, 8);
                memcpy(&count, d + 12, 4);
                for (uint32_t j = 0; names && j < count; j++)
                    if (names[j])
                        dealloc_locked(names[j]);
                if (names && count)
                    munmap(names, count * sizeof *names);
            }
            off += desc_size(kind);
        }
    }
    pthread_mutex_unlock(&mach_lock);
}

static kern_return_t allocate_locked(int right, mac_port_t *name)
{
    if (right != MACH_PORT_RIGHT_RECEIVE && right != MACH_PORT_RIGHT_PORT_SET && right != MACH_PORT_RIGHT_DEAD_NAME)
        return KERN_INVALID_VALUE;
    mac_port_t n = new_name();
    struct entry *e = fresh_entry(n);
    if (!e)
        return KERN_RESOURCE_SHORTAGE;
    if (right == MACH_PORT_RIGHT_DEAD_NAME) {
        e->type = T_DEAD_NAME;
        e->urefs = 1;
        *name = n;
        return KERN_SUCCESS;
    }
    struct port *p = port_new(right == MACH_PORT_RIGHT_PORT_SET);
    if (!p) {
        e->type = 0;
        return KERN_RESOURCE_SHORTAGE;
    }
    p->refs = 1;
    p->name = n;
    p->in_space = !p->is_set;
    e->p = p;
    e->type = p->is_set ? T_PORT_SET : T_RECEIVE;
    *name = n;
    return KERN_SUCCESS;
}

static kern_return_t mac_mach_port_allocate(mac_port_t task, int right, mac_port_t *name)
{
    if (!name)
        return KERN_INVALID_ARGUMENT;
    *name = MACH_PORT_NULL;
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = allocate_locked(right, name);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

struct mac_port_options {
    uint32_t flags;
    uint32_t qlimit;
    uint64_t reserved[2];
};

static kern_return_t mac_mach_port_construct(mac_port_t task, struct mac_port_options *options, uint64_t context,
                                             mac_port_t *name)
{
    if (!name || !options)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = allocate_locked(MACH_PORT_RIGHT_RECEIVE, name);
    if (r == KERN_SUCCESS) {
        struct entry *e = entry_of(*name);
        e->p->context = context;
        if (options->flags & MPO_QLIMIT)
            e->p->qlimit = options->qlimit > MACH_PORT_QLIMIT_MAX ? MACH_PORT_QLIMIT_MAX : options->qlimit;
        if (options->flags & MPO_INSERT_SEND_RIGHT) {
            e->type |= T_SEND;
            e->urefs = 1;
            e->p->srights++;
            e->p->mscount++;
        }
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_reply_port(void)
{
    mac_port_t n = MACH_PORT_NULL;
    mac_mach_port_allocate(TASK_PORT, MACH_PORT_RIGHT_RECEIVE, &n);
    return (kern_return_t)n;
}

static kern_return_t mod_refs_locked(mac_port_t name, int right, int delta);

static kern_return_t dealloc_locked(mac_port_t name)
{
    struct entry *e = entry_of(name);
    if (!e)
        return is_ours(name) ? KERN_INVALID_NAME : KERN_SUCCESS;
    if (e->type & T_SEND_ONCE) {
        struct port *p = e->p;
        free_entry(e);
        destroy_right((struct right){p, MOVE_SEND_ONCE});
        return KERN_SUCCESS;
    }
    if (e->type & T_SEND)
        return mod_refs_locked(name, MACH_PORT_RIGHT_SEND, -1);
    if (e->type & T_DEAD_NAME)
        return mod_refs_locked(name, MACH_PORT_RIGHT_DEAD_NAME, -1);
    return KERN_INVALID_RIGHT;
}

static void destroy_set(struct entry *e)
{
    struct port *s = e->p;
    while (s->nmembers)
        set_remove(s->members[0]);
    s->dead = 1;
    efd_set(s, 0);
    free_entry(e);
    pthread_cond_broadcast(&mcond);
    port_unref(s);
}

static kern_return_t mod_refs_locked(mac_port_t name, int right, int delta)
{
    struct entry *e = entry_of(name);
    if (!e)
        return KERN_INVALID_NAME;
    struct port *p = e->p;
    switch (right) {
    case MACH_PORT_RIGHT_SEND:
        if (e->type & T_DEAD_NAME) /* a send right that died: its references are the dead name's */
            return mod_refs_locked(name, MACH_PORT_RIGHT_DEAD_NAME, delta);
        if (!(e->type & T_SEND))
            return delta == 0 ? KERN_SUCCESS : KERN_INVALID_RIGHT;
        if (delta < 0 && (uint32_t)-delta > e->urefs)
            return KERN_INVALID_VALUE;
        e->urefs += (uint32_t)delta;
        if (e->urefs == 0) {
            e->type &= ~T_SEND;
            if (!(e->type & T_RECEIVE)) {
                p->name = 0;
                free_entry(e);
                drop_send(p);
                port_unref(p);
            } else {
                drop_send(p);
            }
        }
        return KERN_SUCCESS;
    case MACH_PORT_RIGHT_RECEIVE:
        if (!(e->type & T_RECEIVE))
            return delta == 0 ? KERN_SUCCESS : KERN_INVALID_RIGHT;
        if (delta == 0)
            return KERN_SUCCESS;
        if (delta != -1)
            return KERN_INVALID_VALUE;
        port_ref(p);
        e->type &= ~T_RECEIVE;
        if (e->type & T_SEND) {
            /* the name's send rights die with it */
            receive_destroyed(p);
        } else {
            p->name = 0;
            free_entry(e);
            receive_destroyed(p);
            port_unref(p);
        }
        port_unref(p);
        return KERN_SUCCESS;
    case MACH_PORT_RIGHT_SEND_ONCE:
        if (!(e->type & T_SEND_ONCE))
            return delta == 0 ? KERN_SUCCESS : KERN_INVALID_RIGHT;
        if (delta == 0)
            return KERN_SUCCESS;
        if (delta != -1)
            return KERN_INVALID_VALUE;
        return dealloc_locked(name);
    case MACH_PORT_RIGHT_PORT_SET:
        if (!(e->type & T_PORT_SET))
            return delta == 0 ? KERN_SUCCESS : KERN_INVALID_RIGHT;
        if (delta == 0)
            return KERN_SUCCESS;
        if (delta != -1)
            return KERN_INVALID_VALUE;
        destroy_set(e);
        return KERN_SUCCESS;
    case MACH_PORT_RIGHT_DEAD_NAME:
        if (!(e->type & T_DEAD_NAME))
            return delta == 0 ? KERN_SUCCESS : KERN_INVALID_RIGHT;
        if (delta < 0 && (uint32_t)-delta > e->urefs)
            return KERN_INVALID_VALUE;
        e->urefs += (uint32_t)delta;
        if (!e->urefs)
            free_entry(e);
        return KERN_SUCCESS;
    default:
        return KERN_INVALID_VALUE;
    }
}

static kern_return_t mac_mach_port_mod_refs(mac_port_t task, mac_port_t name, int right, int delta)
{
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = mod_refs_locked(name, right, delta);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* Names Ferry hands out for threads, clocks and the task are always fine
 * to let go of. */
static kern_return_t mac_mach_port_deallocate(mac_port_t task, mac_port_t name)
{
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = dealloc_locked(name);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_destroy(mac_port_t task, mac_port_t name)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e) {
        r = is_ours(name) ? KERN_INVALID_NAME : KERN_SUCCESS;
    } else if (e->type & T_PORT_SET) {
        destroy_set(e);
    } else if (e->type & T_DEAD_NAME) {
        free_entry(e);
    } else if (e->type & T_SEND_ONCE) {
        dealloc_locked(name);
    } else {
        struct port *p = e->p;
        port_ref(p);
        int had_send = (e->type & T_SEND) != 0, had_receive = (e->type & T_RECEIVE) != 0;
        p->name = 0;
        free_entry(e);
        if (had_send)
            drop_send(p);
        if (had_receive)
            receive_destroyed(p);
        port_unref(p); /* the name's */
        port_unref(p);
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_destruct(mac_port_t task, mac_port_t name, int srdelta, uint64_t guard)
{
    (void)guard;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e || !(e->type & T_RECEIVE)) {
        r = e ? KERN_INVALID_RIGHT : KERN_INVALID_NAME;
    } else {
        if (srdelta)
            r = mod_refs_locked(name, MACH_PORT_RIGHT_SEND, srdelta);
        if (r == KERN_SUCCESS)
            r = mod_refs_locked(name, MACH_PORT_RIGHT_RECEIVE, -1);
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_insert_right(mac_port_t task, mac_port_t name, mac_port_t poly, unsigned type)
{
    pthread_mutex_lock(&mach_lock);
    kern_return_t r;
    struct right rt;
    if (name != poly) { /* a right under a second name isn't done here */
        r = KERN_NAME_EXISTS;
    } else if ((r = copyin(poly, (int)type, &rt, 0)) == KERN_SUCCESS) {
        if (rt.type == MOVE_SEND_ONCE) {
            /* a send-once right can't share the receive right's name */
            destroy_right(rt);
            r = KERN_RIGHT_EXISTS;
        } else {
            copyout(rt);
        }
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_extract_right(mac_port_t task, mac_port_t name, unsigned type, mac_port_t *out,
                                                 unsigned *out_type)
{
    if (!out || !out_type)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    struct right rt;
    kern_return_t r = copyin(name, (int)type, &rt, 0);
    if (r == KERN_SUCCESS) {
        *out_type = rt.type;
        *out = copyout(rt);
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_type(mac_port_t task, mac_port_t name, uint32_t *type)
{
    if (!type)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else
        *type = e->type | (e->dn_notify ? T_DNREQUEST : 0);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_get_refs(mac_port_t task, mac_port_t name, int right, uint32_t *refs)
{
    if (!refs)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    *refs = 0;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (right == MACH_PORT_RIGHT_SEND)
        *refs = e->type & T_SEND ? e->urefs : 0;
    else if (right == MACH_PORT_RIGHT_RECEIVE)
        *refs = (e->type & T_RECEIVE) != 0;
    else if (right == MACH_PORT_RIGHT_SEND_ONCE)
        *refs = (e->type & T_SEND_ONCE) != 0;
    else if (right == MACH_PORT_RIGHT_PORT_SET)
        *refs = (e->type & T_PORT_SET) != 0;
    else if (right == MACH_PORT_RIGHT_DEAD_NAME)
        *refs = e->type & T_DEAD_NAME ? e->urefs : 0;
    else
        r = KERN_INVALID_VALUE;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_move_member(mac_port_t task, mac_port_t member, mac_port_t after)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *m = entry_of(member), *s = after ? entry_of(after) : NULL;
    kern_return_t r = KERN_SUCCESS;
    if (!m || (after && !s))
        r = KERN_INVALID_NAME;
    else if (!(m->type & T_RECEIVE) || (s && !(s->type & T_PORT_SET)))
        r = KERN_INVALID_RIGHT;
    else {
        set_remove(m->p);
        if (s)
            r = set_add(m->p, s->p);
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_insert_member(mac_port_t task, mac_port_t name, mac_port_t pset)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *m = entry_of(name), *s = entry_of(pset);
    kern_return_t r = KERN_SUCCESS;
    if (!m || !s)
        r = KERN_INVALID_NAME;
    else if (!(m->type & T_RECEIVE) || !(s->type & T_PORT_SET))
        r = KERN_INVALID_RIGHT;
    else if (m->p->set == s->p)
        r = KERN_ALREADY_IN_SET;
    else {
        set_remove(m->p); /* a port is in one set here */
        r = set_add(m->p, s->p);
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_extract_member(mac_port_t task, mac_port_t name, mac_port_t pset)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *m = entry_of(name), *s = entry_of(pset);
    kern_return_t r = KERN_SUCCESS;
    if (!m || !s)
        r = KERN_INVALID_NAME;
    else if (!(m->type & T_RECEIVE) || !(s->type & T_PORT_SET))
        r = KERN_INVALID_RIGHT;
    else if (m->p->set != s->p)
        r = KERN_NOT_IN_SET;
    else
        set_remove(m->p);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_request_notification(mac_port_t task, mac_port_t name, int id, unsigned sync,
                                                        mac_port_t notify, unsigned type, mac_port_t *previous)
{
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = KERN_SUCCESS;
    struct entry *e = entry_of(name);
    if (previous)
        *previous = MACH_PORT_NULL;
    if (!e) {
        r = KERN_INVALID_NAME;
        goto out;
    }
    struct right n = {0};
    if (notify && (r = copyin(notify, (int)type, &n, 0)) != KERN_SUCCESS)
        goto out;
    if (n.p && n.type != MOVE_SEND_ONCE) {
        destroy_right(n);
        r = KERN_INVALID_CAPABILITY;
        goto out;
    }
    struct port *old = NULL;
    switch (id) {
    case MACH_NOTIFY_NO_SENDERS:
        if (!(e->type & T_RECEIVE)) {
            destroy_right(n);
            r = KERN_INVALID_RIGHT;
            goto out;
        }
        old = e->p->ns_notify;
        e->p->ns_notify = n.p;
        e->p->ns_sync = sync;
        if (n.p)
            no_senders_check(e->p);
        break;
    case MACH_NOTIFY_DEAD_NAME:
        if (e->type & T_DEAD_NAME) {
            /* already dead: the notification goes at once */
            if (n.p)
                send_notice(n.p, MACH_NOTIFY_DEAD_NAME, name, 1);
            goto out;
        }
        if (!(e->type & (T_SEND | T_SEND_ONCE))) {
            destroy_right(n);
            r = KERN_INVALID_RIGHT;
            goto out;
        }
        old = e->dn_notify;
        e->dn_notify = n.p;
        break;
    case MACH_NOTIFY_PORT_DESTROYED:
    case MACH_NOTIFY_SEND_POSSIBLE:
        /* never sent: a port's receive right is destroyed outright, and
         * send-possible isn't tracked */
        if (n.p)
            destroy_right(n);
        break;
    default:
        destroy_right(n);
        r = KERN_INVALID_VALUE;
        goto out;
    }
    if (old) {
        if (previous)
            *previous = copyout((struct right){old, MOVE_SEND_ONCE});
        else
            destroy_right((struct right){old, MOVE_SEND_ONCE});
    }
out:
    pthread_mutex_unlock(&mach_lock);
    return r;
}

struct mac_port_status {
    mac_port_t pset;
    uint32_t seqno, mscount, qlimit, msgcount, sorights, srights, pdrequest, nsrequest, flags;
};

static kern_return_t mac_mach_port_get_attributes(mac_port_t task, mac_port_t name, int flavor, int *info,
                                                  unsigned *count)
{
    if (!info || !count)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (!(e->type & T_RECEIVE) && flavor != MACH_PORT_DNREQUESTS_SIZE)
        r = KERN_INVALID_RIGHT;
    else if (flavor == MACH_PORT_LIMITS_INFO && *count >= 1) {
        info[0] = (int)e->p->qlimit;
        *count = 1;
    } else if (flavor == MACH_PORT_RECEIVE_STATUS && *count >= 10) {
        struct port *p = e->p;
        struct mac_port_status st = {p->set ? p->set->name : 0, p->seqno, p->mscount, p->qlimit, p->count,
                                     p->sorights, p->srights > 0, 0, p->ns_notify != NULL, 0};
        if (p->set) {
            st.pset = 0;
            for (unsigned i = 0; i < table_len; i++)
                if (table[i].p == p->set && (table[i].type & T_PORT_SET))
                    st.pset = name_of(i);
        }
        memcpy(info, &st, sizeof st);
        *count = 10;
    } else if (flavor == MACH_PORT_DNREQUESTS_SIZE && *count >= 1) {
        info[0] = 0;
        *count = 1;
    } else if (*count >= 1) {
        info[0] = 0; /* TEMPOWNER, IMPORTANCE_RECEIVER and the rest: none */
        *count = 1;
    } else {
        r = KERN_INVALID_VALUE;
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_set_attributes(mac_port_t task, mac_port_t name, int flavor, int *info,
                                                  unsigned count)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (!(e->type & T_RECEIVE))
        r = KERN_INVALID_RIGHT;
    else if (flavor == MACH_PORT_LIMITS_INFO && info && count >= 1)
        e->p->qlimit = (unsigned)info[0] > MACH_PORT_QLIMIT_MAX ? MACH_PORT_QLIMIT_MAX : (unsigned)info[0];
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_set_context(mac_port_t task, mac_port_t name, uint64_t context)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (!(e->type & T_RECEIVE))
        r = KERN_INVALID_RIGHT;
    else
        e->p->context = context;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_get_context(mac_port_t task, mac_port_t name, uint64_t *context)
{
    if (!context)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (!(e->type & T_RECEIVE))
        r = KERN_INVALID_RIGHT;
    else
        *context = e->p->context;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* guards are taken note of and never fire */
static kern_return_t mac_mach_port_guard(mac_port_t task, mac_port_t name, uint64_t guard, int strict)
{
    return mac_mach_port_set_context(task, name, guard);
}
static kern_return_t mac_mach_port_unguard(mac_port_t task, mac_port_t name, uint64_t guard)
{
    (void)guard;
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = entry_of(name) ? KERN_SUCCESS : KERN_INVALID_NAME;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_set_mscount(mac_port_t task, mac_port_t name, unsigned mscount)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (!(e->type & T_RECEIVE))
        r = KERN_INVALID_RIGHT;
    else
        e->p->mscount = mscount;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_port_get_srights(mac_port_t task, mac_port_t name, unsigned *srights)
{
    if (!srights)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_SUCCESS;
    if (!e)
        r = KERN_INVALID_NAME;
    else if (!(e->type & T_RECEIVE))
        r = KERN_INVALID_RIGHT;
    else
        *srights = e->p->srights;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* The ports a task's name space holds: names and types, in fresh memory. */
static kern_return_t mac_mach_port_names(mac_port_t task, mac_port_t **names, unsigned *ncount, uint32_t **types,
                                         unsigned *tcount)
{
    if (!names || !ncount || !types || !tcount)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    unsigned n = 0;
    for (unsigned i = 0; i < table_len; i++)
        n += table[i].type != 0;
    size_t bytes = (n ? n : 1) * sizeof(uint32_t);
    mac_port_t *nm = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    uint32_t *ty = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    kern_return_t r = KERN_SUCCESS;
    if (nm == MAP_FAILED || ty == MAP_FAILED) {
        r = KERN_RESOURCE_SHORTAGE;
    } else {
        unsigned k = 0;
        for (unsigned i = 0; i < table_len; i++)
            if (table[i].type) {
                nm[k] = name_of(i);
                ty[k++] = table[i].type;
            }
        *names = nm;
        *types = ty;
        *ncount = *tcount = n;
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* MIG's reply ports: one receive right for each thread, kept */
static __thread mac_port_t mig_reply;
static mac_port_t mac_mig_get_reply_port(void)
{
    if (!mig_reply)
        mig_reply = (mac_port_t)mac_mach_reply_port();
    return mig_reply;
}
static void mac_mig_dealloc_reply_port(mac_port_t port)
{
    if (mig_reply) {
        mac_mach_port_mod_refs(TASK_PORT, mig_reply, MACH_PORT_RIGHT_RECEIVE, -1);
        mig_reply = 0;
    }
    (void)port;
}
static void mac_mig_put_reply_port(mac_port_t port) { (void)port; }

static __thread mac_port_t special_reply;
static mac_port_t mac_thread_get_special_reply_port(void)
{
    if (special_reply) {
        pthread_mutex_lock(&mach_lock);
        struct entry *e = entry_of(special_reply);
        int ok = e && (e->type & T_RECEIVE);
        pthread_mutex_unlock(&mach_lock);
        if (ok)
            return special_reply;
    }
    special_reply = (mac_port_t)mac_mach_reply_port();
    return special_reply;
}

/* ---- the bootstrap server ------------------------------------------------------------ */

struct service {
    struct service *next;
    char name[128];
    struct port *p; /* the receive right's port; the list holds a reference */
};
static struct service *services;

static mac_port_t mac_bootstrap_port = BOOTSTRAP_PORT;

static struct service *service_named(const char *name)
{
    for (struct service *s = services; s; s = s->next)
        if (!strcmp(s->name, name))
            return s;
    return NULL;
}

/* A service whose port died is forgotten. */
static void services_sweep(void)
{
    for (struct service **s = &services; *s;) {
        if ((*s)->p->dead) {
            struct service *gone = *s;
            *s = gone->next;
            port_unref(gone->p);
            free(gone);
        } else {
            s = &(*s)->next;
        }
    }
}

static kern_return_t mac_bootstrap_check_in(mac_port_t bp, const char *name, mac_port_t *sp)
{
    if (!sp || !name)
        return KERN_INVALID_ARGUMENT;
    *sp = MACH_PORT_NULL;
    if (strlen(name) >= sizeof services->name)
        return BOOTSTRAP_UNKNOWN_SERVICE;
    pthread_mutex_lock(&mach_lock);
    services_sweep();
    kern_return_t r;
    if (service_named(name)) {
        r = BOOTSTRAP_SERVICE_ACTIVE;
    } else if ((r = allocate_locked(MACH_PORT_RIGHT_RECEIVE, sp)) == KERN_SUCCESS) {
        struct service *s = calloc(1, sizeof *s);
        if (s) {
            strcpy(s->name, name);
            s->p = entry_of(*sp)->p;
            port_ref(s->p);
            s->next = services;
            services = s;
        }
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_bootstrap_look_up(mac_port_t bp, const char *name, mac_port_t *sp)
{
    if (!sp || !name)
        return KERN_INVALID_ARGUMENT;
    *sp = MACH_PORT_NULL;
    pthread_mutex_lock(&mach_lock);
    services_sweep();
    struct service *s = service_named(name);
    kern_return_t r = BOOTSTRAP_UNKNOWN_SERVICE;
    if (s) {
        s->p->srights++;
        s->p->mscount++;
        port_ref(s->p);
        *sp = copyout((struct right){s->p, MOVE_SEND});
        r = KERN_SUCCESS;
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_bootstrap_look_up2(mac_port_t bp, const char *name, mac_port_t *sp, int pid, uint64_t flags)
{
    (void)pid;
    (void)flags;
    return mac_bootstrap_look_up(bp, name, sp);
}

/* bootstrap_register: a send right to a port of the program's, under a name */
static kern_return_t mac_bootstrap_register(mac_port_t bp, const char *name, mac_port_t sp)
{
    if (!name)
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&mach_lock);
    services_sweep();
    struct entry *e = entry_of(sp);
    kern_return_t r = KERN_SUCCESS;
    if (service_named(name))
        r = BOOTSTRAP_NAME_IN_USE;
    else if (!e || !e->p || e->p->is_set)
        r = BOOTSTRAP_NOT_PRIVILEGED;
    else {
        struct service *s = calloc(1, sizeof *s);
        if (!s || strlen(name) >= sizeof s->name) {
            free(s);
            r = BOOTSTRAP_NOT_PRIVILEGED;
        } else {
            strcpy(s->name, name);
            s->p = e->p;
            port_ref(s->p);
            s->next = services;
            services = s;
        }
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static const char *mac_bootstrap_strerror(kern_return_t r)
{
    switch (r) {
    case KERN_SUCCESS: return "Success";
    case BOOTSTRAP_NOT_PRIVILEGED: return "Permission denied";
    case BOOTSTRAP_NAME_IN_USE: return "Service name already exists";
    case BOOTSTRAP_UNKNOWN_SERVICE: return "Unknown service name";
    case BOOTSTRAP_SERVICE_ACTIVE: return "Service is already active";
    case 1104: return "Bad request";
    case 1105: return "No children";
    case 1106: return "Not enough memory";
    default: return "(unknown)";
    }
}

/* task_get_special_port: the bootstrap port; the others aren't there */
#define TASK_BOOTSTRAP_PORT 4
static kern_return_t mac_task_get_special_port(mac_port_t task, int which, mac_port_t *port)
{
    if (!port)
        return KERN_INVALID_ARGUMENT;
    *port = which == TASK_BOOTSTRAP_PORT ? BOOTSTRAP_PORT : MACH_PORT_NULL;
    return KERN_SUCCESS;
}
static kern_return_t mac_task_set_special_port(mac_port_t task, int which, mac_port_t port)
{
    if (which == TASK_BOOTSTRAP_PORT)
        mac_bootstrap_port = port;
    return KERN_SUCCESS;
}

/* ---- for kqueue and dispatch ------------------------------------------------------------ */

/* A descriptor readable while a message waits on the port or port set
 * (or, with dead, once the send right's port is dead); -1 for a name that
 * holds neither. The caller closes it. */
int ferry_mach_port_fd(uint32_t name, int dead)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    int fd = -1;
    if (dead && e && (e->type & (T_SEND | T_SEND_ONCE))) {
        struct port *p = e->p;
        if (p->dead_efd < 0)
            p->dead_efd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
        if (p->dead_efd >= 0)
            fd = fcntl(p->dead_efd, F_DUPFD_CLOEXEC, 0);
    } else if (dead && e && (e->type & T_DEAD_NAME)) {
        fd = eventfd(1, EFD_NONBLOCK | EFD_CLOEXEC);
    } else if (!dead && e && (e->type & (T_RECEIVE | T_PORT_SET)) && e->p->efd >= 0) {
        fd = fcntl(e->p->efd, F_DUPFD_CLOEXEC, 0);
    }
    pthread_mutex_unlock(&mach_lock);
    return fd;
}

/* The size of the first message waiting (with no trailer), or 0, and the
 * name of the port it waits on. */
unsigned ferry_mach_port_pending(uint32_t name, uint32_t *member)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    struct port *from = e && (e->type & (T_RECEIVE | T_PORT_SET)) ? ready_port(e->p) : NULL;
    unsigned n = from ? from->head->size : 0;
    if (member)
        *member = from ? from->name : 0;
    pthread_mutex_unlock(&mach_lock);
    return n;
}

/* kevent's EVFILT_MACHPORT with MACH_RCV_MSG: the message, received into
 * the buffer the event names; the result as mach_msg's. */
int ferry_mach_receive(uint32_t name, void *buf, unsigned size, int option)
{
    return mac_mach_msg(buf, (option & ~(MACH_SEND_MSG | MACH_RCV_TIMEOUT)) | MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                        size, name, 0, 0);
}

/* An empty message with this id to a port the program holds the receive
 * right for (notify(3)'s Mach port registrations). */
int ferry_mach_send_empty(uint32_t port, int32_t id)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(port);
    int r = MACH_SEND_INVALID_DEST;
    if (e && e->p && !e->p->dead && !e->p->is_set) {
        struct kmsg *m = calloc(1, sizeof *m);
        if (m) {
            m->size = sizeof(struct mach_header_);
            m->id = id;
            m->dest_type = MOVE_SEND;
            m->body = calloc(1, 1);
            enqueue(e->p, m);
            r = KERN_SUCCESS;
        }
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* A new receive right, for the program (notify(3)'s ports). */
uint32_t ferry_mach_new_receive(void)
{
    mac_port_t n = MACH_PORT_NULL;
    mac_mach_port_allocate(TASK_PORT, MACH_PORT_RIGHT_RECEIVE, &n);
    return n;
}

/* Whether the program holds a receive right under this name. */
int ferry_mach_is_receive(uint32_t name)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    int r = e && (e->type & T_RECEIVE);
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* ---- memory entries ------------------------------------------------------------------ */

/* A memory entry is a send right naming some shared memory, which
 * mach_vm_map maps (Chromium shares memory this way). Here the memory is a
 * memfd, and the port holds it; it goes when the last send right does.
 * Memory mapped from an entry is remembered, so that an entry can also be
 * made for it by address (as Chromium does to make a read-only copy). */

#define KERN_NO_SPACE 3
#define KERN_PROTECTION_FAILURE 2
#define MAC_VM_PROT_READ 1
#define MAC_VM_PROT_WRITE 2
#define MAC_VM_PROT_EXECUTE 4
#define MAC_MAP_MEM_ONLY 0x010000
#define MAC_MAP_MEM_NAMED_CREATE 0x020000
#define MAC_MAP_MEM_NAMED_REUSE 0x080000
#define MAC_MAP_MEM_VM_COPY 0x200000
#define MAC_MAP_MEM_VM_SHARE 0x400000
#define MAC_VM_FLAGS_ANYWHERE 0x1
#define MAC_VM_FLAGS_OVERWRITE 0x4000
#define MAC_TASK_SELF 0x103u

struct mapped {
    uintptr_t addr;
    size_t len;
    int fd;
    uint64_t off;
};
static struct mapped *maps;
static unsigned nmaps, cmaps;

static size_t page_round(uint64_t n)
{
    size_t pg = (size_t)getpagesize();
    return (size_t)((n + pg - 1) & ~(uint64_t)(pg - 1));
}

static int prot_to_linux(int p)
{
    return (p & MAC_VM_PROT_READ ? PROT_READ : 0) | (p & MAC_VM_PROT_WRITE ? PROT_WRITE : 0)
        | (p & MAC_VM_PROT_EXECUTE ? PROT_EXEC : 0);
}

/* forgets memory mapped from entries in [addr, addr+len) (vm_deallocate) */
void ferry_mach_unmapped(uintptr_t addr, size_t len)
{
    pthread_mutex_lock(&mach_lock);
    for (unsigned i = 0; i < nmaps;) {
        struct mapped *m = &maps[i];
        if (m->addr < addr + len && addr < m->addr + m->len) {
            close(m->fd);
            maps[i] = maps[--nmaps];
        } else {
            i++;
        }
    }
    pthread_mutex_unlock(&mach_lock);
}

static void remember_mapping_locked(uintptr_t addr, size_t len, int fd, uint64_t off)
{
    if (nmaps == cmaps) {
        unsigned c = cmaps ? cmaps * 2 : 16;
        struct mapped *n = realloc(maps, c * sizeof *n);
        if (!n)
            return;
        maps = n;
        cmaps = c;
    }
    int d = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (d < 0)
        return;
    maps[nmaps++] = (struct mapped){addr, len, d, off};
}

static struct port *entry_port_locked(mac_port_t name)
{
    struct entry *e = entry_of(name);
    return e && (e->type & T_SEND) && e->p && e->p->kfd >= 0 && e->p->kprot >= 0 ? e->p : NULL;
}

static kern_return_t new_entry_locked(int fd, uint64_t off, uint64_t size, int prot, mac_port_t *out)
{
    struct port *p = port_new(0);
    if (!p)
        return KERN_RESOURCE_SHORTAGE;
    p->kfd = fd;
    p->koff = off;
    p->ksize = size;
    p->kprot = prot;
    p->refs = 1;
    p->srights = 1;
    p->mscount = 1;
    *out = copyout((struct right){p, MOVE_SEND});
    return *out ? KERN_SUCCESS : KERN_RESOURCE_SHORTAGE;
}

static kern_return_t mac_mach_make_memory_entry_64(mac_port_t task, uint64_t *size, uint64_t offset, int permission,
                                                   mac_port_t *handle, mac_port_t parent)
{
    if (!size || !handle)
        return KERN_INVALID_ARGUMENT;
    (void)task;
    int prot = permission & (MAC_VM_PROT_READ | MAC_VM_PROT_WRITE | MAC_VM_PROT_EXECUTE);
    uint64_t want = page_round(*size);
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = KERN_INVALID_ARGUMENT;
    if (permission & MAC_MAP_MEM_NAMED_CREATE) {
        int fd = memfd_create("ferry-memory-entry", MFD_CLOEXEC);
        if (fd < 0 || ftruncate(fd, (off_t)want) < 0) {
            if (fd >= 0)
                close(fd);
            r = KERN_RESOURCE_SHORTAGE;
        } else if ((r = new_entry_locked(fd, 0, want, prot, handle)) != KERN_SUCCESS) {
            close(fd);
        }
    } else if (parent) {
        struct port *pp = entry_port_locked(parent);
        if (pp && offset + want <= pp->ksize && (prot & ~pp->kprot) == 0) {
            int fd = fcntl(pp->kfd, F_DUPFD_CLOEXEC, 0);
            if (fd >= 0 && (r = new_entry_locked(fd, pp->koff + offset, want, prot, handle)) != KERN_SUCCESS)
                close(fd);
        }
    } else {
        /* memory mapped earlier from an entry, by its address */
        for (unsigned i = 0; i < nmaps; i++) {
            struct mapped *m = &maps[i];
            if (offset >= m->addr && offset + want <= m->addr + m->len) {
                int fd = fcntl(m->fd, F_DUPFD_CLOEXEC, 0);
                if (fd >= 0
                    && (r = new_entry_locked(fd, m->off + (offset - m->addr), want, prot, handle)) != KERN_SUCCESS)
                    close(fd);
                break;
            }
        }
    }
    if (r == KERN_SUCCESS)
        *size = want;
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_make_memory_entry(mac_port_t task, uint32_t *size, uint32_t offset, int permission,
                                                mac_port_t *handle, mac_port_t parent)
{
    if (!size)
        return KERN_INVALID_ARGUMENT;
    uint64_t s64 = *size;
    kern_return_t r = mac_mach_make_memory_entry_64(task, &s64, offset, permission, handle, parent);
    *size = (uint32_t)s64;
    return r;
}

/* Maps an entry (or fresh zeroed memory when the object is null), aligned
 * to the mask's bits. */
static kern_return_t mac_mach_vm_map(mac_port_t task, uint64_t *addr, uint64_t size, uint64_t mask, int flags,
                                     mac_port_t object, uint64_t offset, int copy, int cur, int max, int inherit)
{
    (void)max;
    (void)inherit;
    if (task != MAC_TASK_SELF || !addr || !size)
        return KERN_INVALID_ARGUMENT;
    size_t len = page_round(size);
    int fd = -1;
    uint64_t off = 0;
    pthread_mutex_lock(&mach_lock);
    if (object) {
        struct port *p = entry_port_locked(object);
        /* asking for more access than the entry gives is refused as a
         * wrong right, as on a Mac: Chromium tells a read-only region
         * from a writable one by trying to map it writable */
        if (!p || offset + len > p->ksize) {
            pthread_mutex_unlock(&mach_lock);
            return KERN_INVALID_ARGUMENT;
        }
        if (cur & ~p->kprot & (MAC_VM_PROT_READ | MAC_VM_PROT_WRITE)) {
            pthread_mutex_unlock(&mach_lock);
            return KERN_INVALID_RIGHT;
        }
        fd = p->kfd;
        off = p->koff + offset;
    }
    int lprot = prot_to_linux(cur);
    int share = fd >= 0 && !copy ? MAP_SHARED : MAP_PRIVATE;
    int anon = fd < 0 ? MAP_ANONYMOUS : 0;
    void *at;
    if (!(flags & MAC_VM_FLAGS_ANYWHERE)) {
        int fixed = flags & MAC_VM_FLAGS_OVERWRITE ? MAP_FIXED : MAP_FIXED_NOREPLACE;
        at = mmap((void *)(uintptr_t)*addr, len, lprot, share | anon | fixed, fd, (off_t)off);
    } else {
        size_t align = (size_t)mask + 1;
        if (align <= (size_t)getpagesize() || (align & (align - 1))) {
            at = mmap(NULL, len, lprot, share | anon, fd, (off_t)off);
        } else {
            /* reserve extra, then map at the aligned place in it */
            void *res = mmap(NULL, len + align, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
            at = MAP_FAILED;
            if (res != MAP_FAILED) {
                uintptr_t a = ((uintptr_t)res + align - 1) & ~(uintptr_t)(align - 1);
                at = mmap((void *)a, len, lprot, share | anon | MAP_FIXED, fd, (off_t)off);
                if ((uintptr_t)res < a)
                    munmap(res, a - (uintptr_t)res);
                uintptr_t end = (uintptr_t)res + len + align;
                if (a + len < end)
                    munmap((void *)(a + len), end - (a + len));
            }
        }
    }
    kern_return_t r = KERN_NO_SPACE;
    if (at != MAP_FAILED) {
        *addr = (uint64_t)(uintptr_t)at;
        if (fd >= 0 && share == MAP_SHARED)
            remember_mapping_locked((uintptr_t)at, len, fd, off);
        r = KERN_SUCCESS;
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

static kern_return_t mac_mach_vm_allocate(mac_port_t task, uint64_t *addr, uint64_t size, int flags)
{
    return mac_mach_vm_map(task, addr, size, 0, flags, MACH_PORT_NULL, 0, 0, MAC_VM_PROT_READ | MAC_VM_PROT_WRITE,
                           7, 1);
}

static kern_return_t mac_mach_vm_deallocate(mac_port_t task, uint64_t addr, uint64_t size)
{
    if (task != MAC_TASK_SELF)
        return KERN_INVALID_ARGUMENT;
    if (!size)
        return KERN_SUCCESS;
    uintptr_t pg = (uintptr_t)getpagesize() - 1, a = (uintptr_t)addr & ~pg;
    size_t len = page_round(size + ((uintptr_t)addr & pg));
    ferry_mach_unmapped(a, len);
    munmap((void *)a, len);
    return KERN_SUCCESS;
}

static kern_return_t mac_mach_vm_protect(mac_port_t task, uint64_t addr, uint64_t size, int set_max, int prot)
{
    if (task != MAC_TASK_SELF)
        return KERN_INVALID_ARGUMENT;
    if (set_max)
        return KERN_SUCCESS; /* this system has no separate most-allowed protection */
    uintptr_t pg = (uintptr_t)getpagesize() - 1, a = (uintptr_t)addr & ~pg;
    return mprotect((void *)a, page_round(size + ((uintptr_t)addr & pg)), prot_to_linux(prot)) == 0
        ? KERN_SUCCESS : KERN_PROTECTION_FAILURE;
}

/* Purgeable memory is never purged here: it reads as kept (nonvolatile). */
static kern_return_t mac_mach_vm_purgable_control(mac_port_t task, uint64_t addr, int control, int *state)
{
    (void)task;
    (void)addr;
    (void)control;
    if (state)
        *state = 0;
    return KERN_SUCCESS;
}

/* A copy of memory in this task, in fresh pages the caller frees. */
static kern_return_t mac_mach_vm_read(mac_port_t task, uint64_t addr, uint64_t size, uintptr_t *data, uint32_t *count)
{
    if (task != MAC_TASK_SELF || !data || !count)
        return KERN_INVALID_ARGUMENT;
    void *p = mmap(NULL, page_round(size), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return KERN_RESOURCE_SHORTAGE;
    memcpy(p, (void *)(uintptr_t)addr, (size_t)size);
    *data = (uintptr_t)p;
    *count = (uint32_t)size;
    return KERN_SUCCESS;
}

static kern_return_t mac_mach_vm_read_overwrite(mac_port_t task, uint64_t addr, uint64_t size, uint64_t to,
                                                uint64_t *outsize)
{
    if (task != MAC_TASK_SELF)
        return KERN_INVALID_ARGUMENT;
    memmove((void *)(uintptr_t)to, (void *)(uintptr_t)addr, (size_t)size);
    if (outsize)
        *outsize = size;
    return KERN_SUCCESS;
}

/* A file port carries a file descriptor in a message: the port holds a
 * copy of the descriptor, and fileport_makefd makes another from it. */
static int mac_fileport_makeport(int fd, mac_port_t *port)
{
    if (!port)
        return EINVAL;
    int d = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (d < 0)
        return -1;
    pthread_mutex_lock(&mach_lock);
    kern_return_t r = new_entry_locked(d, 0, 0, -1, port);
    pthread_mutex_unlock(&mach_lock);
    if (r != KERN_SUCCESS) {
        close(d);
        errno = ENOMEM;
        return -1;
    }
    return 0;
}

static int mac_fileport_makefd(mac_port_t port)
{
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(port);
    int fd = -1;
    if (e && (e->type & T_SEND) && e->p && e->p->kfd >= 0 && e->p->kprot < 0)
        fd = fcntl(e->p->kfd, F_DUPFD_CLOEXEC, 0);
    pthread_mutex_unlock(&mach_lock);
    if (fd < 0)
        errno = EINVAL;
    return fd;
}

/* What the next message on a port is, without receiving it. */
static kern_return_t mac_mach_port_peek(mac_port_t task, mac_port_t name, int trailer_type, uint32_t *seqno,
                                        uint32_t *size, int32_t *id, char *trailer, uint32_t *trailer_size)
{
    (void)task;
    (void)trailer_type;
    pthread_mutex_lock(&mach_lock);
    struct entry *e = entry_of(name);
    kern_return_t r = KERN_INVALID_RIGHT;
    if (e && (e->type & T_RECEIVE) && e->p) {
        struct kmsg *m = e->p->head;
        r = KERN_FAILURE;
        if (m && (!seqno || !*seqno || *seqno == e->p->seqno)) {
            if (seqno)
                *seqno = e->p->seqno;
            if (size)
                *size = m->size;
            if (id)
                *id = m->id;
            if (trailer && trailer_size && *trailer_size >= 8) {
                memset(trailer, 0, *trailer_size);
                uint32_t t[2] = {0, 8};
                memcpy(trailer, t, sizeof t);
                *trailer_size = 8;
            }
            r = KERN_SUCCESS;
        }
    }
    pthread_mutex_unlock(&mach_lock);
    return r;
}

/* for tests: whether a name is a memory entry, and its size */
uint64_t ferry_mach_entry_size(uint32_t name)
{
    pthread_mutex_lock(&mach_lock);
    struct port *p = entry_port_locked(name);
    uint64_t n = p ? p->ksize : 0;
    pthread_mutex_unlock(&mach_lock);
    return n;
}

const struct ferry_symbol ferry_mach_symbols[] = {
    {"fileport_makeport", mac_fileport_makeport},
    {"fileport_makefd", mac_fileport_makefd},
    {"mach_port_peek", mac_mach_port_peek},
    {"mach_make_memory_entry_64", mac_mach_make_memory_entry_64},
    {"mach_make_memory_entry", mac_mach_make_memory_entry},
    {"mach_vm_map", mac_mach_vm_map},
    {"vm_map", mac_mach_vm_map},
    {"mach_vm_allocate", mac_mach_vm_allocate},
    {"mach_vm_deallocate", mac_mach_vm_deallocate},
    {"mach_vm_protect", mac_mach_vm_protect},
    {"vm_protect", mac_mach_vm_protect},
    {"mach_vm_purgable_control", mac_mach_vm_purgable_control},
    {"vm_purgable_control", mac_mach_vm_purgable_control},
    {"mach_vm_read", mac_mach_vm_read},
    {"vm_read", mac_mach_vm_read},
    {"mach_vm_read_overwrite", mac_mach_vm_read_overwrite},
    {"vm_read_overwrite", mac_mach_vm_read_overwrite},
    {"bootstrap_port", &mac_bootstrap_port},
    {"mach_port_allocate", mac_mach_port_allocate},
    {"mach_port_construct", mac_mach_port_construct},
    {"mach_port_destruct", mac_mach_port_destruct},
    {"mach_port_deallocate", mac_mach_port_deallocate},
    {"mach_port_destroy", mac_mach_port_destroy},
    {"mach_port_mod_refs", mac_mach_port_mod_refs},
    {"mach_port_get_refs", mac_mach_port_get_refs},
    {"mach_port_insert_right", mac_mach_port_insert_right},
    {"mach_port_extract_right", mac_mach_port_extract_right},
    {"mach_port_type", mac_mach_port_type},
    {"mach_port_names", mac_mach_port_names},
    {"mach_port_move_member", mac_mach_port_move_member},
    {"mach_port_insert_member", mac_mach_port_insert_member},
    {"mach_port_extract_member", mac_mach_port_extract_member},
    {"mach_port_request_notification", mac_mach_port_request_notification},
    {"mach_port_get_attributes", mac_mach_port_get_attributes},
    {"mach_port_set_attributes", mac_mach_port_set_attributes},
    {"mach_port_set_context", mac_mach_port_set_context},
    {"mach_port_get_context", mac_mach_port_get_context},
    {"mach_port_guard", mac_mach_port_guard},
    {"mach_port_unguard", mac_mach_port_unguard},
    {"mach_port_set_mscount", mac_mach_port_set_mscount},
    {"mach_port_get_srights", mac_mach_port_get_srights},
    {"mach_reply_port", mac_mach_reply_port},
    {"thread_get_special_reply_port", mac_thread_get_special_reply_port},
    {"mig_get_reply_port", mac_mig_get_reply_port},
    {"mig_dealloc_reply_port", mac_mig_dealloc_reply_port},
    {"mig_put_reply_port", mac_mig_put_reply_port},
    {"mach_msg", mac_mach_msg},
    {"mach_msg_overwrite", mac_mach_msg_overwrite},
    {"mach_msg_send", mac_mach_msg_send},
    {"mach_msg_receive", mac_mach_msg_receive},
    {"mach_msg_destroy", mac_mach_msg_destroy},
    {"bootstrap_check_in", mac_bootstrap_check_in},
    {"bootstrap_look_up", mac_bootstrap_look_up},
    {"bootstrap_look_up2", mac_bootstrap_look_up2},
    {"bootstrap_register", mac_bootstrap_register},
    {"bootstrap_strerror", mac_bootstrap_strerror},
    {"task_get_special_port", mac_task_get_special_port},
    {"task_set_special_port", mac_task_set_special_port},
    {NULL, NULL},
};
