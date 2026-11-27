/* Mach ports and messages in one process: rights, a message with a port,
 * out-of-line memory and a trailer, port sets, notifications, the
 * bootstrap server, kevent's EVFILT_MACHPORT and dispatch's mach_recv and
 * mach_send sources (freemac 1.265). */
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <mach/port.h>
#include <pthread.h>
#include <servers/bootstrap.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <unistd.h>

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t port;
    mach_msg_ool_descriptor_t ool;
    int value;
} big_msg;

typedef struct {
    mach_msg_header_t header;
    int value;
} small_msg;

static mach_port_t make_port(void)
{
    mach_port_t p = MACH_PORT_NULL;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &p);
    return p;
}

static kern_return_t send_small(mach_port_t to, int value, mach_msg_type_name_t disp)
{
    small_msg m;
    memset(&m, 0, sizeof m);
    m.header.msgh_bits = MACH_MSGH_BITS(disp, 0);
    m.header.msgh_size = sizeof m;
    m.header.msgh_remote_port = to;
    m.header.msgh_id = 100 + value;
    m.value = value;
    return mach_msg(&m.header, MACH_SEND_MSG, sizeof m, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
}

static int receive_small(mach_port_t on, unsigned timeout)
{
    struct {
        small_msg m;
        mach_msg_trailer_t t;
    } r;
    kern_return_t k = mach_msg(&r.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof r, on, timeout, MACH_PORT_NULL);
    return k == KERN_SUCCESS ? r.m.value : -(int)(k & 0xffff);
}

static void *later_sender(void *arg)
{
    usleep(50000);
    send_small((mach_port_t)(uintptr_t)arg, 7, MACH_MSG_TYPE_COPY_SEND);
    return NULL;
}

int main(void)
{
    task_t self = mach_task_self();

    /* a receive right, and a send right made from it */
    mach_port_t a = make_port();
    mach_port_type_t type = 0;
    mach_port_type(self, a, &type);
    printf("allocated: %s, receive %s\n", MACH_PORT_VALID(a) ? "yes" : "no",
           type == MACH_PORT_TYPE_RECEIVE ? "only" : "and more");
    kern_return_t k = mach_port_insert_right(self, a, a, MACH_MSG_TYPE_MAKE_SEND);
    mach_port_urefs_t refs = 0;
    mach_port_get_refs(self, a, MACH_PORT_RIGHT_SEND, &refs);
    mach_port_type(self, a, &type);
    printf("insert send: %d, send refs %u, send and receive %s\n", k, refs,
           type == MACH_PORT_TYPE_SEND_RECEIVE ? "yes" : "no");

    /* construct with a send right and a context */
    mach_port_options_t opts = {.flags = MPO_INSERT_SEND_RIGHT | MPO_QLIMIT, .mpl = {.mpl_qlimit = 16}};
    mach_port_t c = MACH_PORT_NULL;
    k = mach_port_construct(self, &opts, 0x1234, &c);
    mach_port_context_t ctx = 0;
    mach_port_get_context(self, c, &ctx);
    mach_port_limits_t lim = {0};
    mach_msg_type_number_t cnt = MACH_PORT_LIMITS_INFO_COUNT;
    mach_port_get_attributes(self, c, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&lim, &cnt);
    mach_port_type(self, c, &type);
    printf("construct: %d, context %llx, qlimit %u, send and receive %s\n", k, (unsigned long long)ctx,
           lim.mpl_qlimit, type == MACH_PORT_TYPE_SEND_RECEIVE ? "yes" : "no");

    /* a plain message, in order */
    send_small(a, 1, MACH_MSG_TYPE_COPY_SEND);
    send_small(a, 2, MACH_MSG_TYPE_MAKE_SEND);
    mach_port_status_t st;
    cnt = MACH_PORT_RECEIVE_STATUS_COUNT;
    mach_port_get_attributes(self, a, MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&st, &cnt);
    printf("queued: %u\n", st.mps_msgcount);
    int first = receive_small(a, 0), second = receive_small(a, 0);
    printf("received %d then %d, then %s\n", first, second, receive_small(a, 0) == -0x4003 ? "timed out" : "?");

    /* a message that arrives while waiting */
    pthread_t t;
    pthread_create(&t, NULL, later_sender, (void *)(uintptr_t)a);
    printf("waited for: %d\n", receive_small(a, 5000));
    pthread_join(t, NULL);

    /* a complex message: a send right to b, out-of-line memory, the audit trailer */
    mach_port_t b = make_port();
    static char text[] = "out of line words";
    big_msg m;
    memset(&m, 0, sizeof m);
    m.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE) | MACH_MSGH_BITS_COMPLEX;
    m.header.msgh_size = sizeof m;
    m.header.msgh_remote_port = a;
    m.header.msgh_local_port = b;
    m.header.msgh_id = 500;
    m.body.msgh_descriptor_count = 2;
    m.port.name = b;
    m.port.disposition = MACH_MSG_TYPE_MAKE_SEND;
    m.port.type = MACH_MSG_PORT_DESCRIPTOR;
    m.ool.address = text;
    m.ool.size = sizeof text;
    m.ool.copy = MACH_MSG_VIRTUAL_COPY;
    m.ool.type = MACH_MSG_OOL_DESCRIPTOR;
    m.value = 42;
    k = mach_msg(&m.header, MACH_SEND_MSG, sizeof m, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    printf("complex send: %d\n", k);
    struct {
        big_msg m;
        mach_msg_audit_trailer_t t;
    } r;
    memset(&r, 0, sizeof r);
    k = mach_msg(&r.m.header, MACH_RCV_MSG | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
                                  MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
                 0, sizeof r, a, 0, MACH_PORT_NULL);
    printf("complex receive: %d, id %d, value %d\n", k, r.m.header.msgh_id, r.m.value);
    printf("reply is send-once: %s, port is b: %s, disposition send: %s\n",
           MACH_MSGH_BITS_REMOTE(r.m.header.msgh_bits) == MACH_MSG_TYPE_MOVE_SEND_ONCE ? "yes" : "no",
           r.m.port.name == b ? "yes" : "no", r.m.port.disposition == MACH_MSG_TYPE_MOVE_SEND ? "yes" : "no");
    printf("out of line: \"%s\", a copy: %s\n", (char *)r.m.ool.address, r.m.ool.address != text ? "yes" : "no");
    printf("trailer: %u bytes, pid %s\n", r.t.msgh_trailer_size,
           r.t.msgh_audit.val[5] == (unsigned)getpid() ? "ours" : "wrong");
    mach_port_get_refs(self, b, MACH_PORT_RIGHT_SEND, &refs);
    printf("b's send refs now %u\n", refs);

    /* answer on the send-once reply right */
    small_msg reply;
    memset(&reply, 0, sizeof reply);
    reply.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
    reply.header.msgh_size = sizeof reply;
    reply.header.msgh_remote_port = r.m.header.msgh_remote_port;
    reply.value = 9;
    k = mach_msg(&reply.header, MACH_SEND_MSG, sizeof reply, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    printf("reply: %d, b got %d\n", k, receive_small(b, 0));
    vm_deallocate(self, (vm_address_t)r.m.ool.address, r.m.ool.size);

    /* a port set */
    mach_port_t set = MACH_PORT_NULL;
    mach_port_allocate(self, MACH_PORT_RIGHT_PORT_SET, &set);
    mach_port_t p1 = make_port(), p2 = make_port();
    mach_port_insert_member(self, p1, set);
    mach_port_insert_member(self, p2, set);
    mach_port_insert_right(self, p2, p2, MACH_MSG_TYPE_MAKE_SEND);
    send_small(p2, 3, MACH_MSG_TYPE_COPY_SEND);
    struct {
        small_msg m;
        mach_msg_trailer_t t;
    } rs;
    k = mach_msg(&rs.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof rs, set, 0, MACH_PORT_NULL);
    printf("from the set: %d, value %d, on p2 %s\n", k, rs.m.value, rs.m.header.msgh_local_port == p2 ? "yes" : "no");
    printf("extract twice: %d\n", mach_port_extract_member(self, p1, set) == KERN_SUCCESS &&
                                      mach_port_extract_member(self, p1, set) == KERN_NOT_IN_SET);

    /* too large, and MACH_RCV_LARGE */
    send_small(p2, 4, MACH_MSG_TYPE_COPY_SEND);
    mach_msg_header_t tiny;
    k = mach_msg(&tiny, MACH_RCV_MSG | MACH_RCV_LARGE | MACH_RCV_TIMEOUT, 0, sizeof tiny, p2, 0, MACH_PORT_NULL);
    printf("too large: %s, needs %u, still there %d\n", k == MACH_RCV_TOO_LARGE ? "yes" : "no", tiny.msgh_size,
           receive_small(p2, 0));

    /* the no-senders notification */
    mach_port_t ns = make_port(), watched = make_port();
    mach_port_t prev = MACH_PORT_NULL;
    mach_port_insert_right(self, watched, watched, MACH_MSG_TYPE_MAKE_SEND);
    k = mach_port_request_notification(self, watched, MACH_NOTIFY_NO_SENDERS, 0, ns, MACH_MSG_TYPE_MAKE_SEND_ONCE,
                                       &prev);
    mach_port_deallocate(self, watched);
    struct {
        mach_no_senders_notification_t n;
        mach_msg_trailer_t pad;
    } nsr;
    k = mach_msg(&nsr.n.not_header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof nsr, ns, 0, MACH_PORT_NULL);
    printf("no senders: %d, id %d\n", k, nsr.n.not_header.msgh_id);

    /* the dead-name notification, and a dead name */
    mach_port_t dn = make_port(), victim = make_port();
    mach_port_insert_right(self, victim, victim, MACH_MSG_TYPE_MAKE_SEND);
    mach_port_t holder = MACH_PORT_NULL;
    mach_msg_type_name_t holder_type = 0;
    mach_port_extract_right(self, victim, MACH_MSG_TYPE_COPY_SEND, &holder, &holder_type);
    mach_port_t sender_name = holder; /* the same name: a send right merges with the receive right's */
    k = mach_port_request_notification(self, victim, MACH_NOTIFY_DEAD_NAME, 0, dn, MACH_MSG_TYPE_MAKE_SEND_ONCE,
                                       &prev);
    printf("dead-name request: %d, same name %s\n", k, sender_name == victim ? "yes" : "no");
    mach_port_mod_refs(self, victim, MACH_PORT_RIGHT_RECEIVE, -1);
    mach_port_type(self, victim, &type);
    struct {
        mach_dead_name_notification_t n;
        mach_msg_trailer_t pad;
    } dnr;
    k = mach_msg(&dnr.n.not_header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof dnr, dn, 0, MACH_PORT_NULL);
    printf("dead name: %s, notified %d, id %d, for it %s\n", type & MACH_PORT_TYPE_DEAD_NAME ? "yes" : "no", k,
           dnr.n.not_header.msgh_id, dnr.n.not_port == victim ? "yes" : "no");
    printf("send to it: %s\n", send_small(victim, 1, MACH_MSG_TYPE_COPY_SEND) == MACH_SEND_INVALID_DEST ? "invalid" : "?");
    mach_port_deallocate(self, victim);
    mach_port_deallocate(self, victim);
    printf("gone: %s\n", mach_port_type(self, victim, &type) == KERN_INVALID_NAME ? "yes" : "no");

    /* the bootstrap server */
    mach_port_t service = MACH_PORT_NULL, found = MACH_PORT_NULL;
    k = bootstrap_check_in(bootstrap_port, "org.freemac.test", &service);
    kern_return_t k2 = bootstrap_look_up(bootstrap_port, "org.freemac.test", &found);
    printf("check in %d, look up %d\n", k, k2);
    send_small(found, 5, MACH_MSG_TYPE_COPY_SEND);
    printf("through the service: %d\n", receive_small(service, 0));
    printf("unknown: %s\n", bootstrap_strerror(bootstrap_look_up(bootstrap_port, "nobody", &found)));

    /* kevent: EVFILT_MACHPORT, and receiving with it */
    int kq = kqueue();
    mach_port_t kp = make_port();
    mach_port_insert_right(self, kp, kp, MACH_MSG_TYPE_MAKE_SEND);
    struct {
        small_msg m;
        mach_msg_max_trailer_t t;
    } kbuf;
    struct kevent64_s ch;
    EV_SET64(&ch, kp, EVFILT_MACHPORT, EV_ADD, MACH_RCV_MSG, 0, 0, (uint64_t)(uintptr_t)&kbuf, sizeof kbuf);
    kevent64(kq, &ch, 1, NULL, 0, 0, NULL);
    struct timespec zero = {0, 0};
    struct kevent64_s ev;
    printf("nothing yet: %d\n", kevent64(kq, NULL, 0, &ev, 1, 0, &zero));
    send_small(kp, 6, MACH_MSG_TYPE_COPY_SEND);
    int n = kevent64(kq, NULL, 0, &ev, 1, 0, &zero);
    printf("kevent: %d, result %u, value %d, size %llu\n", n, ev.fflags, kbuf.m.value, (unsigned long long)ev.ext[1]);
    printf("then empty: %d\n", kevent64(kq, NULL, 0, &ev, 1, 0, &zero));

    /* dispatch: a mach_recv source, and a mach_send source for a dead port */
    mach_port_t dp = make_port();
    mach_port_insert_right(self, dp, dp, MACH_MSG_TYPE_MAKE_SEND);
    dispatch_queue_t q = dispatch_queue_create("mach", NULL);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block int got = 0;
    dispatch_source_t rs_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, dp, 0, q);
    dispatch_source_set_event_handler(rs_, ^{
        int v = receive_small(dp, 0);
        if (v > 0) {
            got += v;
            if (got == 30)
                dispatch_semaphore_signal(done);
        }
    });
    dispatch_resume(rs_);
    send_small(dp, 10, MACH_MSG_TYPE_COPY_SEND);
    send_small(dp, 20, MACH_MSG_TYPE_COPY_SEND);
    long w = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    printf("mach_recv source: %s, got %d\n", w == 0 ? "fired" : "timed out", got);
    dispatch_source_cancel(rs_);

    mach_port_t sp = make_port();
    mach_port_insert_right(self, sp, sp, MACH_MSG_TYPE_MAKE_SEND);
    mach_port_t sp_send = MACH_PORT_NULL;
    mach_msg_type_name_t sp_type;
    mach_port_extract_right(self, sp, MACH_MSG_TYPE_COPY_SEND, &sp_send, &sp_type);
    __block unsigned long dead_data = 0;
    dispatch_source_t ss = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_SEND, sp, DISPATCH_MACH_SEND_DEAD, q);
    dispatch_source_set_event_handler(ss, ^{
        dead_data = dispatch_source_get_data(ss);
        dispatch_semaphore_signal(done);
    });
    dispatch_resume(ss);
    mach_port_mod_refs(self, sp, MACH_PORT_RIGHT_RECEIVE, -1);
    w = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    printf("mach_send source: %s, data %lu\n", w == 0 ? "fired" : "timed out", dead_data);
    dispatch_source_cancel(ss);

    /* memory entries: one memory, mapped twice, and a read-only entry made
     * from a mapping, which refuses to be mapped writable (freemac 1.265) */
    memory_object_size_t esize = 100;
    mach_port_t entry = MACH_PORT_NULL;
    kern_return_t ek = mach_make_memory_entry_64(self, &esize, 0, MAP_MEM_NAMED_CREATE | VM_PROT_READ | VM_PROT_WRITE,
                                                 &entry, MACH_PORT_NULL);
    printf("memory entry: %d, size rounded to a page: %s\n", ek, esize == (memory_object_size_t)getpagesize() ? "yes" : "no");
    mach_vm_address_t m1 = 0, m2 = 0;
    ek = mach_vm_map(self, &m1, esize, 0, VM_FLAGS_ANYWHERE, entry, 0, 0, VM_PROT_READ | VM_PROT_WRITE,
                     VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    kern_return_t ek2 = mach_vm_map(self, &m2, esize, 0xffff, VM_FLAGS_ANYWHERE, entry, 0, 0,
                                    VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    strcpy((char *)(uintptr_t)m1, "shared");
    printf("mapped twice: %d %d, second aligned: %s, sees the first's write: %s\n", ek, ek2,
           (m2 & 0xffff) == 0 ? "yes" : "no", strcmp((char *)(uintptr_t)m2, "shared") == 0 ? "yes" : "no");
    mach_port_t ro = MACH_PORT_NULL;
    memory_object_size_t rsize = esize;
    ek = mach_make_memory_entry_64(self, &rsize, (memory_object_offset_t)m1, VM_PROT_READ, &ro, MACH_PORT_NULL);
    mach_vm_address_t m3 = 0;
    kern_return_t rw = mach_vm_map(self, &m3, rsize, 0, VM_FLAGS_ANYWHERE, ro, 0, 0, VM_PROT_READ | VM_PROT_WRITE,
                                   VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    kern_return_t rd = mach_vm_map(self, &m3, rsize, 0, VM_FLAGS_ANYWHERE, ro, 0, 0, VM_PROT_READ, VM_PROT_READ,
                                   VM_INHERIT_NONE);
    printf("read-only entry: %d, writable map refused: %s, read map: %d, reads: %s\n", ek,
           rw == KERN_INVALID_RIGHT ? "yes" : "no", rd, strcmp((char *)(uintptr_t)m3, "shared") == 0 ? "yes" : "no");
    printf("unmap: %d %d %d\n", mach_vm_deallocate(self, m1, esize), mach_vm_deallocate(self, m2, esize),
           mach_vm_deallocate(self, m3, rsize));
    printf("entries released: %d %d\n", mach_port_deallocate(self, entry), mach_port_deallocate(self, ro));

    /* MIG's reply port stays the thread's */
    printf("mig reply port kept: %s\n", mig_get_reply_port() == mig_get_reply_port() ? "yes" : "no");
    printf("deallocate a task port: %d\n", mach_port_deallocate(self, self));
    return 0;
}
