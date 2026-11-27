/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Mach ports and messages, within a process and between processes (freemac 1.265, 1.266), written from
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
 *    it and by other programs.
 *  - Messages go to ports in other processes too, with their rights and
 *    memory (see "ports across processes" below).
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
    /* across processes (freemac 1.266): a port another process can name has
     * a key, the process it was made in and a number; rpid is the process
     * its receive right is in when that isn't this one (a port standing for
     * another process's, or one whose receive right went to another), and
     * holders are the processes told of a port whose receive right is here */
    int rpid, kpid;
    uint32_t kid;
    struct port *knext;
    int *holders;
    unsigned nholders, cholders;
    /* a port whose receive right went to another process stays, holding a
     * reference of its own, to pass on what is still sent to it by its old
     * key (a message can be on its way when the right moves), until that
     * process says the port died or the right comes back */
    int forwarding;
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
    int from_pid; /* the process that sent it, when another one */
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

static void key_remove(struct port *p);

static void port_unref(struct port *p)
{
    if (--p->refs > 0)
        return;
    if (p->kid)
        key_remove(p);
    free(p->holders);
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
static void holders_told_dead(struct port *p);

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
    if (!p->rpid && p->kid)
        holders_told_dead(p);
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
    if (p->forwarding) {
        p->forwarding = 0;
        port_unref(p); /* the caller holds a reference of its own */
    }
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
/* The task's own port, as a right in a message (Chromium's helpers send
 * theirs to the browser): a port of its own that nobody receives on, and
 * that dies with the process, so a send right to it in another process
 * becomes a dead name when this one ends (freemac 1.266). */
static struct port *task_object;

static kern_return_t copyin(mac_port_t name, int disp, struct right *out, int is_dest)
{
    out->p = NULL;
    out->type = 0;
    if (name == MACH_PORT_NULL || name == MACH_PORT_DEAD)
        return KERN_SUCCESS;
    if (name == TASK_PORT && !is_dest && (disp == MOVE_SEND || disp == COPY_SEND)) {
        if (!task_object && (task_object = port_new(0)))
            task_object->refs = 1; /* the task's own, for good */
        if (!task_object)
            return KERN_RESOURCE_SHORTAGE;
        task_object->srights++;
        port_ref(task_object);
        *out = (struct right){task_object, MOVE_SEND};
        return KERN_SUCCESS;
    }
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

static void remote_send(struct port *p, struct kmsg *m);
static int trace_level(void);

/* A message for a port whose receive right is in another process goes there. */
static void enqueue(struct port *p, struct kmsg *m)
{
    if (p->rpid) {
        remote_send(p, m);
        return;
    }
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
        if ((option & MACH_SEND_TIMEOUT) && timeout == 0) {
            if (trace_level() >= 1)
                fprintf(stderr, "ferry-mach %d: queue full (id %#x to %#x): %u of %u, rpid %d, key %d/%u\n", getpid(), h->id, h->remote, dp->count,
                        dp->qlimit, dp->rpid, dp->kpid, dp->kid);
            return MACH_SEND_TIMED_OUT;
        }
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
                    if (getenv("FERRY_MACH_TRACE"))
                        fprintf(stderr, "ferry-mach %d: message %#x: right %#x (disposition %d) isn't valid\n",
                                getpid(), h->id, name, d[10]);
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
    uint32_t uid = (uint32_t)getuid(), gid = (uint32_t)getgid();
    uint32_t pid = (uint32_t)(m->from_pid ? m->from_pid : getpid());
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
    if (option & MACH_SEND_MSG) {
        r = send_locked(msg, option, send_size, timeout);
        if (r != KERN_SUCCESS && trace_level() >= 1)
            fprintf(stderr, "ferry-mach %d: a send to %#x failed: %#x\n", getpid(),
                    ((struct mach_header_ *)msg)->remote, r);
    }
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
    if (r && getenv("FERRY_MACH_TRACE"))
        fprintf(stderr, "ferry-mach %d: deallocate %#x: %d\n", getpid(), name, r);
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

/* ---- ports across processes ------------------------------------------------------ */

/* On a Mac the kernel carries a message to a port in any task, with its
 * rights, memory and file ports, and a receive right can itself move to
 * another task. Chromium needs this between its browser and helper
 * processes: a helper finds the browser's rendezvous service with
 * bootstrap_look_up, gets its first ports from it, and then talks over Mojo
 * channels built on those ports (freemac 1.266).
 *
 * Here each process that names ports to others has a datagram socket of its
 * own, in a folder only its user can open, named by its process id. A port
 * another process can name has a key (the process it was made in, and a
 * number). A process holding a send right to a port whose receive right is
 * elsewhere has a port standing for it, with the process to send to, and a
 * message to it is written out (its rights by key, its out-of-line memory
 * copied, memory entries and file ports as file descriptors) and sent to
 * that process, which takes it in as if it had been sent there. A receive
 * right that moves leaves a port behind that passes messages on, and the
 * messages already waiting follow it.
 *
 * When a receive right is destroyed, the processes told of the port hear
 * so, and their send rights become dead names (with their dead-name
 * notifications). When a process ends, every port whose receive right was
 * in it dies the same way: each process watches the processes it sends to.
 * The bootstrap server's services are files in the same folder, so a
 * service checked in by one program is found by another. */

#include <poll.h>
#include <signal.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>

#define W_MSG 0x48434d46u  /* 'FMCH' a message */
#define W_BIG 0x47424d46u  /* 'FMBG' a large message, in a memory file */
#define W_DEAD 0x44444d46u /* 'FMDD' a port's receive right was destroyed */
#define W_HOLD 0x4c484d46u /* 'FMHL' a process holds a send right to a port */
#define W_MAXFD 250
#define W_INLINE (48u * 1024)

enum { WK_NONE, WK_PORT, WK_FD, WK_DEAD };

struct w_hdr {
    uint32_t magic, len;
    int32_t pid;
    uint32_t nfds;
    int32_t dkpid;
    uint32_t dkid;
    uint32_t complex, size;
    int32_t id;
    uint32_t dest_type, body_len, ndesc;
};

struct w_right {
    int32_t kpid;
    uint32_t kid;
    int32_t route; /* where its receive right is */
    uint8_t type, kind;
    uint16_t pad;
    int32_t fd;
    uint64_t koff, ksize;
    int32_t kprot;
    uint32_t qlimit;
    uint64_t context;
    uint32_t nholders; /* a receive right: the processes told of it, which follow */
    uint32_t pad2;
};

struct w_note {
    uint32_t magic, len;
    int32_t pid;
    uint32_t nfds;
    int32_t kpid;
    uint32_t kid;
    int32_t holder;
    uint32_t pad;
};

static int net_state; /* 0 not yet, 1 up, -1 can't */
static int net_sock = -1, net_epoll = -1;
static char net_dir[96];
static int my_pid;
static uint32_t next_kid;

/* the keys of ports other processes can name */
#define KBUCKETS 512
static struct port *kbucket[KBUCKETS];

static unsigned khash(int pid, uint32_t kid) { return ((unsigned)pid * 2654435761u ^ kid * 40503u) % KBUCKETS; }

static struct port *key_find(int pid, uint32_t kid)
{
    for (struct port *p = kbucket[khash(pid, kid)]; p; p = p->knext)
        if (p->kpid == pid && p->kid == kid)
            return p;
    return NULL;
}

static void key_insert(struct port *p)
{
    unsigned h = khash(p->kpid, p->kid);
    p->knext = kbucket[h];
    kbucket[h] = p;
}

static void key_remove(struct port *p)
{
    for (struct port **q = &kbucket[khash(p->kpid, p->kid)]; *q; q = &(*q)->knext)
        if (*q == p) {
            *q = p->knext;
            break;
        }
    p->kid = 0;
    p->knext = NULL;
}

static void key_assign(struct port *p)
{
    if (p->kid)
        return;
    p->kpid = my_pid;
    p->kid = ++next_kid;
    key_insert(p);
}

static void holder_add(struct port *p, int pid)
{
    if (pid == my_pid || pid <= 0)
        return;
    for (unsigned i = 0; i < p->nholders; i++)
        if (p->holders[i] == pid)
            return;
    if (p->nholders == p->cholders) {
        unsigned c = p->cholders ? p->cholders * 2 : 4;
        int *h = realloc(p->holders, c * sizeof *h);
        if (!h)
            return;
        p->holders = h;
        p->cholders = c;
    }
    p->holders[p->nholders++] = pid;
}

static int pid_alive(int pid) { return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM); }

/* ---- the folder, the socket and its two threads ---- */

static int private_dir(const char *path)
{
    if (mkdir(path, 0700) < 0 && errno != EEXIST)
        return -1;
    struct stat st;
    return lstat(path, &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == getuid() && !(st.st_mode & 077) ? 0 : -1;
}

static int mach_folder(void)
{
    if (net_dir[0])
        return 0;
    char d[sizeof net_dir];
    const char *x = getenv("XDG_RUNTIME_DIR");
    struct stat st;
    if (x && *x && strlen(x) < 48 && stat(x, &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == getuid())
        snprintf(d, sizeof d, "%s/ferry-mach", x);
    else
        snprintf(d, sizeof d, "/tmp/ferry-mach-%u", (unsigned)getuid());
    if (private_dir(d) < 0)
        return -1;
    char svc[sizeof d + 8];
    snprintf(svc, sizeof svc, "%s/svc", d);
    if (private_dir(svc) < 0)
        return -1;
    memcpy(net_dir, d, sizeof d);
    return 0;
}

static void sock_path(struct sockaddr_un *a, int pid)
{
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    snprintf(a->sun_path, sizeof a->sun_path, "%s/%d.sock", net_dir, pid);
}

struct outmsg {
    struct outmsg *next;
    int to;
    unsigned char *buf;
    size_t len;
    int fds[W_MAXFD];
    unsigned nfds;
};
static pthread_mutex_t out_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t out_cond = PTHREAD_COND_INITIALIZER;
static struct outmsg *out_head, *out_tail;

static void out_push(struct outmsg *o)
{
    pthread_mutex_lock(&out_lock);
    o->next = NULL;
    if (out_tail)
        out_tail->next = o;
    else
        out_head = o;
    out_tail = o;
    pthread_cond_signal(&out_cond);
    pthread_mutex_unlock(&out_lock);
}

static void out_free(struct outmsg *o)
{
    for (unsigned i = 0; i < o->nfds; i++)
        close(o->fds[i]);
    free(o->buf);
    free(o);
}

static int send_datagram(int to, const void *buf, size_t len, const int *fds, unsigned nfds)
{
    struct sockaddr_un a;
    sock_path(&a, to);
    struct iovec iov = {(void *)buf, len};
    union {
        char b[CMSG_SPACE(sizeof(int) * (W_MAXFD + 1))];
        struct cmsghdr align;
    } c;
    struct msghdr mh = {.msg_name = &a, .msg_namelen = sizeof a, .msg_iov = &iov, .msg_iovlen = 1};
    if (nfds) {
        mh.msg_control = c.b;
        mh.msg_controllen = CMSG_SPACE(sizeof(int) * nfds);
        struct cmsghdr *cm = CMSG_FIRSTHDR(&mh);
        cm->cmsg_level = SOL_SOCKET;
        cm->cmsg_type = SCM_RIGHTS;
        cm->cmsg_len = CMSG_LEN(sizeof(int) * nfds);
        memcpy(CMSG_DATA(cm), fds, sizeof(int) * nfds);
    }
    for (;;) {
        if (sendmsg(net_sock, &mh, MSG_NOSIGNAL) >= 0)
            return 0;
        if (errno != EINTR)
            return -errno;
    }
}

static void peer_died(int pid);

static void *sender_main(void *arg)
{
    (void)arg;
    for (;;) {
        pthread_mutex_lock(&out_lock);
        while (!out_head)
            pthread_cond_wait(&out_cond, &out_lock);
        struct outmsg *o = out_head;
        out_head = o->next;
        if (!out_head)
            out_tail = NULL;
        pthread_mutex_unlock(&out_lock);
        int r = o->len <= W_INLINE ? send_datagram(o->to, o->buf, o->len, o->fds, o->nfds) : -EMSGSIZE;
        if (r == -EMSGSIZE || r == -ENOBUFS) {
            /* a large message goes in a memory file, sent ahead of its own descriptors */
            int mfd = memfd_create("ferry-mach-message", MFD_CLOEXEC);
            r = -ENOMEM;
            if (mfd >= 0 && write(mfd, o->buf, o->len) == (ssize_t)o->len) {
                struct w_note n = {W_BIG, (uint32_t)o->len, my_pid, o->nfds + 1, 0, 0, 0, 0};
                int fds[W_MAXFD + 1];
                fds[0] = mfd;
                memcpy(fds + 1, o->fds, o->nfds * sizeof(int));
                r = send_datagram(o->to, &n, sizeof n, fds, o->nfds + 1);
            }
            if (mfd >= 0)
                close(mfd);
        }
        if (r == -ENOENT || r == -ECONNREFUSED || r == -ENOTDIR) {
            pthread_mutex_lock(&mach_lock);
            peer_died(o->to);
            pthread_mutex_unlock(&mach_lock);
        } else if (r < 0 && ferry_verbose) {
            fprintf(stderr, "ferry: a Mach message to process %d wasn't sent (%s)\n", o->to, strerror(-r));
        }
        out_free(o);
    }
    return NULL;
}

/* the processes watched: when one ends, the ports whose receive rights were in it die */
struct watched {
    int pid, fd;
};
static struct watched *watch;
static unsigned nwatch, cwatch;

static void watch_pid(int pid)
{
    if (pid == my_pid || pid <= 0 || net_epoll < 0)
        return;
    for (unsigned i = 0; i < nwatch; i++)
        if (watch[i].pid == pid)
            return;
    int fd = (int)syscall(SYS_pidfd_open, pid, 0);
    if (fd < 0)
        return;
    if (nwatch == cwatch) {
        unsigned c = cwatch ? cwatch * 2 : 16;
        struct watched *w = realloc(watch, c * sizeof *w);
        if (!w) {
            close(fd);
            return;
        }
        watch = w;
        cwatch = c;
    }
    watch[nwatch++] = (struct watched){pid, fd};
    struct epoll_event ev = {.events = EPOLLIN, .data.u64 = (uint64_t)(unsigned)pid};
    epoll_ctl(net_epoll, EPOLL_CTL_ADD, fd, &ev);
}

static void unwatch_pid(int pid)
{
    for (unsigned i = 0; i < nwatch; i++)
        if (watch[i].pid == pid) {
            epoll_ctl(net_epoll, EPOLL_CTL_DEL, watch[i].fd, NULL);
            close(watch[i].fd);
            watch[i] = watch[--nwatch];
            return;
        }
}

/* Every port whose receive right was in a process that ended dies. */
static void peer_died(int pid)
{
    unwatch_pid(pid);
    struct port **gone = NULL;
    unsigned n = 0, cap = 0;
    for (unsigned b = 0; b < KBUCKETS; b++)
        for (struct port *p = kbucket[b]; p; p = p->knext)
            if (p->rpid == pid && !p->dead) {
                if (n == cap) {
                    cap = cap ? cap * 2 : 16;
                    struct port **g = realloc(gone, cap * sizeof *g);
                    if (!g)
                        break;
                    gone = g;
                }
                port_ref(p);
                gone[n++] = p;
            }
    for (unsigned i = 0; i < n; i++) {
        receive_destroyed(gone[i]);
        port_unref(gone[i]);
    }
    free(gone);
}

static void deliver_locked(const unsigned char *buf, size_t len, int *fds, unsigned nfds);

static void *receiver_main(void *arg)
{
    (void)arg;
    size_t cap = W_INLINE + 4096;
    unsigned char *buf = malloc(cap);
    for (;;) {
        struct epoll_event ev[16];
        int n = epoll_wait(net_epoll, ev, 16, -1);
        for (int i = 0; i < n; i++) {
            if (ev[i].data.u64 != 0) {
                pthread_mutex_lock(&mach_lock);
                peer_died((int)ev[i].data.u64);
                pthread_mutex_unlock(&mach_lock);
                continue;
            }
            for (;;) {
                union {
                    char b[CMSG_SPACE(sizeof(int) * (W_MAXFD + 1))];
                    struct cmsghdr align;
                } c;
                struct iovec iov = {buf, cap};
                struct msghdr mh = {.msg_iov = &iov, .msg_iovlen = 1, .msg_control = c.b, .msg_controllen = sizeof c.b};
                ssize_t got = recvmsg(net_sock, &mh, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
                if (got < 0)
                    break;
                int fds[W_MAXFD + 1];
                unsigned nfds = 0;
                for (struct cmsghdr *cm = CMSG_FIRSTHDR(&mh); cm; cm = CMSG_NXTHDR(&mh, cm))
                    if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS) {
                        unsigned k = (unsigned)((cm->cmsg_len - CMSG_LEN(0)) / sizeof(int));
                        if (nfds + k > W_MAXFD + 1)
                            k = W_MAXFD + 1 - nfds;
                        memcpy(fds + nfds, CMSG_DATA(cm), k * sizeof(int));
                        nfds += k;
                    }
                uint32_t magic = 0;
                if (got >= 4)
                    memcpy(&magic, buf, 4);
                if (magic == W_BIG && got >= (ssize_t)sizeof(struct w_note) && nfds >= 1) {
                    struct w_note note;
                    memcpy(&note, buf, sizeof note);
                    unsigned char *big = malloc(note.len ? note.len : 1);
                    if (big && pread(fds[0], big, note.len, 0) == (ssize_t)note.len) {
                        close(fds[0]);
                        pthread_mutex_lock(&mach_lock);
                        deliver_locked(big, note.len, fds + 1, nfds - 1);
                        pthread_mutex_unlock(&mach_lock);
                    } else {
                        for (unsigned k = 0; k < nfds; k++)
                            close(fds[k]);
                    }
                    free(big);
                } else {
                    pthread_mutex_lock(&mach_lock);
                    deliver_locked(buf, (size_t)got, fds, nfds);
                    pthread_mutex_unlock(&mach_lock);
                }
            }
        }
    }
    return NULL;
}

static void net_down(void)
{
    if (net_state != 1)
        return;
    struct sockaddr_un a;
    sock_path(&a, my_pid);
    unlink(a.sun_path);
}

/* Brings this process's socket up, the first time another process may need
 * to reach it. */
static int net_up(void)
{
    if (net_state)
        return net_state > 0 ? 0 : -1;
    net_state = -1;
    my_pid = getpid();
    if (mach_folder() < 0)
        return -1;
    int s = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (s < 0)
        return -1;
    struct sockaddr_un a;
    sock_path(&a, my_pid);
    unlink(a.sun_path); /* left by an earlier process with this id */
    if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) {
        close(s);
        return -1;
    }
    int big = 4 << 20;
    setsockopt(s, SOL_SOCKET, SO_SNDBUF, &big, sizeof big);
    setsockopt(s, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
    net_epoll = epoll_create1(EPOLL_CLOEXEC);
    struct epoll_event ev = {.events = EPOLLIN, .data.u64 = 0};
    if (net_epoll < 0 || epoll_ctl(net_epoll, EPOLL_CTL_ADD, s, &ev) < 0) {
        close(s);
        unlink(a.sun_path);
        return -1;
    }
    net_sock = s;
    /* the threads take no signals meant for the program */
    sigset_t all, old;
    sigfillset(&all);
    pthread_sigmask(SIG_SETMASK, &all, &old);
    pthread_t t1, t2;
    int ok = pthread_create(&t1, NULL, receiver_main, NULL) == 0 && pthread_create(&t2, NULL, sender_main, NULL) == 0;
    pthread_sigmask(SIG_SETMASK, &old, NULL);
    if (!ok) {
        close(s);
        unlink(a.sun_path);
        return -1;
    }
    pthread_detach(t1);
    pthread_detach(t2);
    net_state = 1;
    atexit(net_down);
    return 0;
}

static void note_send(uint32_t magic, int to, struct port *p, int holder)
{
    struct outmsg *o = calloc(1, sizeof *o);
    struct w_note *n = calloc(1, sizeof *n);
    if (!o || !n) {
        free(o);
        free(n);
        return;
    }
    *n = (struct w_note){magic, sizeof *n, my_pid, 0, p->kpid, p->kid, holder, 0};
    o->to = to;
    o->buf = (unsigned char *)n;
    o->len = sizeof *n;
    out_push(o);
}

static void holders_told_dead(struct port *p)
{
    for (unsigned i = 0; i < p->nholders; i++)
        note_send(W_DEAD, p->holders[i], p, 0);
    p->nholders = 0;
}

/* ---- writing a message out ---- */

struct wbuf {
    unsigned char *b;
    size_t len, cap;
    int fds[W_MAXFD];
    unsigned nfds;
    int err;
};

static void wput(struct wbuf *w, const void *data, size_t n)
{
    if (w->err)
        return;
    if (w->len + n > w->cap) {
        size_t c = w->cap ? w->cap : 512;
        while (c < w->len + n)
            c *= 2;
        unsigned char *b = realloc(w->b, c);
        if (!b) {
            w->err = 1;
            return;
        }
        w->b = b;
        w->cap = c;
    }
    memcpy(w->b + w->len, data, n);
    w->len += n;
}

/* ports whose receive rights just left, whose waiting messages follow */
static struct port **moving;
static unsigned nmoving, cmoving;

/* A right in a message to process `to`; the right is used up. */
static void put_right(struct wbuf *w, struct right r, int to)
{
    struct w_right wr;
    memset(&wr, 0, sizeof wr);
    wr.fd = -1;
    struct port *p = r.p;
    if (!p) {
        wput(w, &wr, sizeof wr);
        return;
    }
    wr.type = r.type;
    if (p->kfd >= 0) {
        int d = w->nfds < W_MAXFD ? fcntl(p->kfd, F_DUPFD_CLOEXEC, 0) : -1;
        if (d < 0) {
            w->err = 1;
        } else {
            wr.kind = WK_FD;
            wr.fd = (int32_t)w->nfds;
            w->fds[w->nfds++] = d;
            wr.koff = p->koff;
            wr.ksize = p->ksize;
            wr.kprot = p->kprot;
        }
        destroy_right(r);
        wput(w, &wr, sizeof wr);
        return;
    }
    if (p->dead) {
        wr.kind = WK_DEAD;
        destroy_right(r);
        wput(w, &wr, sizeof wr);
        return;
    }
    wr.kind = WK_PORT;
    if (p->rpid) {
        /* a send right to a port elsewhere: it goes on by key */
        wr.kpid = p->kpid;
        wr.kid = p->kid;
        wr.route = p->rpid;
        if (r.type == MOVE_SEND)
            drop_send(p);
        else
            p->sorights--;
        port_unref(p);
        wput(w, &wr, sizeof wr);
        return;
    }
    key_assign(p);
    wr.kpid = p->kpid;
    wr.kid = p->kid;
    wr.route = my_pid;
    if (r.type == MOVE_RECEIVE) {
        /* the receive right goes: this port passes messages on to it */
        wr.qlimit = p->qlimit;
        wr.context = p->context;
        unsigned nh = 0;
        for (unsigned i = 0; i < p->nholders; i++)
            nh += p->holders[i] != to;
        wr.nholders = nh + 1;
        wput(w, &wr, sizeof wr);
        int32_t self = my_pid;
        wput(w, &self, 4);
        for (unsigned i = 0; i < p->nholders; i++)
            if (p->holders[i] != to) {
                int32_t h = p->holders[i];
                wput(w, &h, 4);
            }
        p->nholders = 0;
        p->rpid = to;
        if (!p->forwarding) {
            p->forwarding = 1;
            port_ref(p);
        }
        watch_pid(to);
        if (nmoving == cmoving) {
            unsigned c = cmoving ? cmoving * 2 : 8;
            struct port **m = realloc(moving, c * sizeof *m);
            if (m) {
                moving = m;
                cmoving = c;
            }
        }
        if (nmoving < cmoving)
            moving[nmoving++] = p; /* keeps the right's reference */
        else
            port_unref(p);
        return;
    }
    /* a send or send-once right to a port here: the other process holds it now,
     * and is told when the port dies */
    holder_add(p, to);
    port_unref(p);
    wput(w, &wr, sizeof wr);
}

static int sending_out;

/* FERRY_MACH_TRACE=2: every message between processes, sent and delivered */
static int trace_level(void)
{
    static int level = -1;
    if (level < 0) {
        const char *t = getenv("FERRY_MACH_TRACE");
        level = t ? atoi(t) : 0;
    }
    return level;
}

static void remote_send(struct port *p, struct kmsg *m)
{
    int to = p->rpid;
    if (trace_level() >= 2)
        fprintf(stderr, "ferry-mach %d: send to %d: id %#x, %u bytes, %u descriptors\n", getpid(), to, m->id, m->size,
                m->ndesc);
    if (net_up() < 0) {
        destroy_kmsg(m);
        return;
    }
    struct wbuf w;
    memset(&w, 0, sizeof w);
    struct w_hdr h = {W_MSG, 0, my_pid, 0, p->kpid, p->kid, m->complex, m->size, m->id, m->dest_type,
                      m->size - (uint32_t)sizeof(struct mach_header_), m->ndesc};
    wput(&w, &h, sizeof h);
    put_right(&w, m->reply, to);
    m->reply.p = NULL;
    wput(&w, m->body, h.body_len);
    for (unsigned i = 0; i < m->ndesc; i++) {
        struct kdesc *k = &m->desc[i];
        uint32_t hd[2] = {k->offset, (uint32_t)k->kind};
        wput(&w, hd, sizeof hd);
        if (k->kind == MACH_MSG_PORT_DESCRIPTOR || k->kind == MACH_MSG_GUARDED_PORT_DESCRIPTOR) {
            put_right(&w, k->r, to);
            k->r.p = NULL;
        } else if (k->kind == MACH_MSG_OOL_DESCRIPTOR || k->kind == MACH_MSG_OOL_VOLATILE_DESCRIPTOR) {
            uint64_t n = k->mem_size;
            wput(&w, &n, 8);
            if (n)
                wput(&w, k->mem, n);
        } else {
            uint32_t n = k->nports;
            wput(&w, &n, 4);
            for (unsigned j = 0; j < k->nports; j++) {
                put_right(&w, k->ports[j], to);
                k->ports[j].p = NULL;
            }
        }
    }
    destroy_kmsg(m);
    if (w.err) {
        for (unsigned i = 0; i < w.nfds; i++)
            close(w.fds[i]);
        free(w.b);
    } else {
        struct outmsg *o = calloc(1, sizeof *o);
        if (!o) {
            for (unsigned i = 0; i < w.nfds; i++)
                close(w.fds[i]);
            free(w.b);
        } else {
            h.len = (uint32_t)w.len;
            h.nfds = w.nfds;
            memcpy(w.b, &h, sizeof h);
            o->to = to;
            o->buf = w.b;
            o->len = w.len;
            memcpy(o->fds, w.fds, w.nfds * sizeof(int));
            o->nfds = w.nfds;
            out_push(o);
        }
    }
    /* the messages waiting on a port whose receive right left follow it, in order */
    if (sending_out)
        return;
    sending_out = 1;
    while (nmoving) {
        struct port *q = moving[--nmoving];
        while (q->head) {
            struct kmsg *km = q->head;
            q->head = km->next;
            if (!q->head)
                q->tail = NULL;
            q->count--;
            enqueue(q, km);
            port_unref(q); /* the queue's reference */
        }
        efd_update(q);
        pthread_cond_broadcast(&mcond);
        port_unref(q);
    }
    sending_out = 0;
}

/* ---- taking a message in ---- */

struct rbuf {
    const unsigned char *b;
    size_t len, off;
    int *fds;
    unsigned nfds;
    int err;
};

static int rget(struct rbuf *r, void *out, size_t n)
{
    if (r->err || r->off + n > r->len) {
        r->err = 1;
        memset(out, 0, n);
        return -1;
    }
    memcpy(out, r->b + r->off, n);
    r->off += n;
    return 0;
}

static struct right dead_right(uint8_t type)
{
    struct port *p = port_new(0);
    if (!p)
        return (struct right){NULL, 0};
    p->dead = 1;
    p->refs = 1;
    if (type == MOVE_SEND_ONCE)
        p->sorights = 1;
    else
        p->srights = 1;
    return (struct right){p, type == MOVE_SEND_ONCE ? MOVE_SEND_ONCE : MOVE_SEND};
}

static struct right get_right(struct rbuf *rb, int from)
{
    struct w_right wr;
    if (rget(rb, &wr, sizeof wr) < 0)
        return (struct right){NULL, 0};
    int holders[64];
    unsigned nh = 0;
    for (uint32_t i = 0; i < wr.nholders; i++) {
        int32_t h;
        if (rget(rb, &h, 4) < 0)
            return (struct right){NULL, 0};
        if (nh < 64)
            holders[nh++] = h;
    }
    switch (wr.kind) {
    case WK_FD: {
        if (wr.fd < 0 || (unsigned)wr.fd >= rb->nfds || rb->fds[wr.fd] < 0)
            return dead_right(wr.type);
        struct port *p = port_new(0);
        if (!p)
            return (struct right){NULL, 0};
        p->kfd = rb->fds[wr.fd];
        rb->fds[wr.fd] = -1;
        p->koff = wr.koff;
        p->ksize = wr.ksize;
        p->kprot = wr.kprot;
        p->refs = 1;
        p->srights = 1;
        p->mscount = 1;
        return (struct right){p, MOVE_SEND};
    }
    case WK_DEAD:
        return dead_right(wr.type);
    case WK_PORT:
        break;
    default:
        return (struct right){NULL, 0};
    }
    struct port *p = key_find(wr.kpid, wr.kid);
    if (wr.type == MOVE_RECEIVE) {
        if (p && (p->dead || !p->rpid)) {
            key_remove(p); /* a dead stand-in, whose names are dead names already */
            p = NULL;
        }
        if (p) {
            p->rpid = 0;
            if (p->forwarding) {
                p->forwarding = 0;
                p->refs--; /* the right coming back holds it now (the caller's reference follows) */
            }
        } else {
            p = port_new(0);
            if (!p)
                return (struct right){NULL, 0};
            p->kpid = wr.kpid;
            p->kid = wr.kid;
            key_insert(p);
        }
        p->qlimit = wr.qlimit;
        p->context = wr.context;
        for (unsigned i = 0; i < nh; i++)
            holder_add(p, holders[i]);
        holder_add(p, from);
        port_ref(p);
        return (struct right){p, MOVE_RECEIVE};
    }
    if (!p) {
        if (wr.route == my_pid || !pid_alive(wr.route))
            return dead_right(wr.type);
        p = port_new(0);
        if (!p)
            return (struct right){NULL, 0};
        p->kpid = wr.kpid;
        p->kid = wr.kid;
        p->rpid = wr.route;
        key_insert(p);
        watch_pid(wr.route);
        if (wr.route != from)
            note_send(W_HOLD, wr.route, p, my_pid);
    }
    if (p->dead || p->rpid) {
        if (wr.type == MOVE_SEND_ONCE)
            p->sorights++;
        else {
            p->srights++;
            p->mscount++;
        }
    }
    port_ref(p);
    return (struct right){p, wr.type == MOVE_SEND_ONCE ? MOVE_SEND_ONCE : MOVE_SEND};
}

static void deliver_locked(const unsigned char *buf, size_t len, int *fds, unsigned nfds)
{
    struct rbuf rb = {buf, len, 0, fds, nfds, 0};
    uint32_t magic = 0;
    if (len >= 4)
        memcpy(&magic, buf, 4);
    if (magic == W_DEAD || magic == W_HOLD) {
        struct w_note n;
        if (rget(&rb, &n, sizeof n) == 0) {
            struct port *p = key_find(n.kpid, n.kid);
            if (p && magic == W_DEAD && p->rpid) {
                port_ref(p);
                receive_destroyed(p);
                port_unref(p);
            } else if (p && magic == W_HOLD) {
                if (p->rpid)
                    note_send(W_HOLD, p->rpid, p, n.holder);
                else if (!p->dead)
                    holder_add(p, n.holder);
                else
                    note_send(W_DEAD, n.holder, p, 0);
            }
        }
        goto done;
    }
    if (magic != W_MSG)
        goto done;
    struct w_hdr h;
    rget(&rb, &h, sizeof h);
    struct kmsg *m = calloc(1, sizeof *m);
    if (!m)
        goto done;
    m->from_pid = h.pid;
    m->complex = h.complex;
    m->size = h.size;
    m->id = h.id;
    m->dest_type = (uint8_t)h.dest_type;
    m->reply = get_right(&rb, h.pid);
    m->body = malloc(h.body_len ? h.body_len : 1);
    if (!m->body || h.body_len != h.size - sizeof(struct mach_header_)) {
        destroy_kmsg(m);
        goto done;
    }
    rget(&rb, m->body, h.body_len);
    if (h.ndesc) {
        m->desc = calloc(h.ndesc, sizeof *m->desc);
        if (!m->desc || h.ndesc > h.body_len / 12) {
            destroy_kmsg(m);
            goto done;
        }
    }
    for (uint32_t i = 0; i < h.ndesc && !rb.err; i++) {
        struct kdesc *k = &m->desc[m->ndesc++];
        uint32_t hd[2];
        rget(&rb, hd, sizeof hd);
        k->offset = hd[0];
        k->kind = (int)hd[1];
        if (k->offset + desc_size(k->kind) > h.body_len) {
            rb.err = 1;
            break;
        }
        if (k->kind == MACH_MSG_PORT_DESCRIPTOR || k->kind == MACH_MSG_GUARDED_PORT_DESCRIPTOR) {
            k->r = get_right(&rb, h.pid);
        } else if (k->kind == MACH_MSG_OOL_DESCRIPTOR || k->kind == MACH_MSG_OOL_VOLATILE_DESCRIPTOR) {
            uint64_t n;
            rget(&rb, &n, 8);
            if (n > rb.len - rb.off) {
                rb.err = 1;
                break;
            }
            k->mem_size = (size_t)n;
            if (n) {
                k->mem = malloc((size_t)n);
                if (!k->mem) {
                    rb.err = 1;
                    break;
                }
                rget(&rb, k->mem, (size_t)n);
            }
        } else {
            uint32_t n;
            rget(&rb, &n, 4);
            if (n > (rb.len - rb.off) / sizeof(struct w_right)) {
                rb.err = 1;
                break;
            }
            k->ports = calloc(n ? n : 1, sizeof *k->ports);
            if (!k->ports) {
                rb.err = 1;
                break;
            }
            for (uint32_t j = 0; j < n; j++)
                k->ports[k->nports++] = get_right(&rb, h.pid);
        }
    }
    struct port *dp = key_find(h.dkpid, h.dkid);
    if (trace_level() >= 2)
        fprintf(stderr, "ferry-mach %d: from %d: to %d/%u: id %#x, %u bytes%s\n", getpid(), h.pid, h.dkpid, h.dkid, h.id,
                h.size, rb.err ? ", unreadable" : !dp ? ", no such port" : dp->dead ? ", port gone" : "");
    if (rb.err || !dp || dp->dead) {
        /* a port made here that is gone: the sender is told, so that its
         * rights become dead names, as a send to a dead port fails on a Mac */
        if (!rb.err && h.dkpid == my_pid && (!dp || !dp->rpid)) {
            struct port gone;
            memset(&gone, 0, sizeof gone);
            gone.kpid = h.dkpid;
            gone.kid = h.dkid;
            note_send(W_DEAD, h.pid, &gone, 0);
        }
        destroy_kmsg(m);
        goto done;
    }
    if (!dp->rpid && m->dest_type == MOVE_SEND_ONCE && dp->sorights)
        dp->sorights--; /* the sender's send-once right is used up */
    enqueue(dp, m);
done:
    for (unsigned i = 0; i < nfds; i++)
        if (fds[i] >= 0)
            close(fds[i]);
}

/* ---- the bootstrap server's services, as files ---- */

static void service_file(char *out, size_t n, const char *name)
{
    int k = snprintf(out, n, "%s/svc/", net_dir);
    for (const unsigned char *c = (const unsigned char *)name; *c && k + 4 < (int)n; c++) {
        if (*c == '/' || *c == '%' || *c < 0x20)
            k += snprintf(out + k, n - (size_t)k, "%%%02X", *c);
        else
            out[k++] = (char)*c;
    }
    out[k] = 0;
}

/* The service another process checked in, if it is still running: its key
 * and where its receive right is. */
static int service_read(const char *name, int *kpid, uint32_t *kid, int *route)
{
    if (mach_folder() < 0)
        return -1;
    char path[512];
    service_file(path, sizeof path, name);
    FILE *f = fopen(path, "re");
    if (!f)
        return -1;
    int ok = fscanf(f, "%d %u %d", kpid, kid, route) == 3;
    fclose(f);
    if (!ok || !pid_alive(*route)) {
        unlink(path);
        return -1;
    }
    return 0;
}

static void service_written(const char *name, struct port *p)
{
    if (net_up() < 0)
        return;
    int route = my_pid;
    if (p->rpid)
        route = p->rpid;
    else
        key_assign(p);
    char path[512], tmp[540];
    service_file(path, sizeof path, name);
    snprintf(tmp, sizeof tmp, "%s.%d", path, my_pid);
    FILE *f = fopen(tmp, "we");
    if (!f)
        return;
    fprintf(f, "%d %u %d\n", p->kpid, p->kid, route);
    if (fclose(f) == 0)
        rename(tmp, path);
    else
        unlink(tmp);
}

/* A send right to another process's service. */
static struct port *service_import(int kpid, uint32_t kid, int route)
{
    if (net_up() < 0 || route == my_pid)
        return NULL;
    struct port *p = key_find(kpid, kid);
    if (p && (p->dead || !p->rpid))
        return p->dead ? NULL : p;
    if (!p) {
        p = port_new(0);
        if (!p)
            return NULL;
        p->kpid = kpid;
        p->kid = kid;
        p->rpid = route;
        key_insert(p);
        watch_pid(route);
        note_send(W_HOLD, route, p, my_pid);
    }
    return p;
}

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
    int kpid, route;
    uint32_t kid;
    if (service_named(name) || (service_read(name, &kpid, &kid, &route) == 0 && route != getpid())) {
        r = BOOTSTRAP_SERVICE_ACTIVE;
    } else if ((r = allocate_locked(MACH_PORT_RIGHT_RECEIVE, sp)) == KERN_SUCCESS) {
        struct service *s = calloc(1, sizeof *s);
        if (s) {
            strcpy(s->name, name);
            s->p = entry_of(*sp)->p;
            port_ref(s->p);
            s->next = services;
            services = s;
            service_written(name, s->p); /* found by other programs too */
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
    struct port *p = s ? s->p : NULL;
    int kpid, route;
    uint32_t kid;
    if (!p && service_read(name, &kpid, &kid, &route) == 0)
        p = service_import(kpid, kid, route); /* another program's */
    if (p) {
        p->srights++;
        p->mscount++;
        port_ref(p);
        *sp = copyout((struct right){p, MOVE_SEND});
        r = *sp ? KERN_SUCCESS : KERN_RESOURCE_SHORTAGE;
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
            service_written(name, s->p);
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
