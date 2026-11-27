/* Mach messages between two processes, as Chromium's browser and helpers
 * use them (freemac 1.266): the child finds its parent's service with
 * bootstrap_look_up, asks it for its ports with a send-once reply right,
 * and gets a receive right (with a message already waiting on it), a send
 * right, a memory entry, a file port and out-of-line memory. A message
 * sent to the receive right after it moved follows it; the child's send
 * right reaches the parent; and when the child ends, the parent's dead-name
 * notification comes. */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/port.h>
#include <servers/bootstrap.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int fileport_makeport(int fd, mach_port_t *port);
int fileport_makefd(mach_port_t port);
extern char **environ;

#define OOL_SIZE (200 * 1024)

typedef struct {
    mach_msg_header_t header;
    int value;
} small_msg;

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t receive, entry, file, back;
    mach_msg_ool_descriptor_t ool;
    int value;
} ports_msg;

static void service_name(char *out, size_t n, int pid) { snprintf(out, n, "org.freemac.test.MachIPC.%d", pid); }

static kern_return_t send_small(mach_port_t to, mach_msg_type_name_t disp, mach_port_t reply,
                                mach_msg_type_name_t rdisp, int id, int value)
{
    small_msg m;
    memset(&m, 0, sizeof m);
    m.header.msgh_bits = MACH_MSGH_BITS(disp, rdisp);
    m.header.msgh_size = sizeof m;
    m.header.msgh_remote_port = to;
    m.header.msgh_local_port = reply;
    m.header.msgh_id = id;
    m.value = value;
    return mach_msg(&m.header, MACH_SEND_MSG, sizeof m, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
}

static unsigned checksum(const unsigned char *p, size_t n)
{
    unsigned h = 2166136261u;
    for (size_t i = 0; i < n; i++)
        h = (h ^ p[i]) * 16777619u;
    return h;
}

static int child(void)
{
    char name[128];
    service_name(name, sizeof name, getppid());
    mach_port_t server = MACH_PORT_NULL;
    kern_return_t k = bootstrap_look_up(bootstrap_port, name, &server);
    if (k != KERN_SUCCESS) {
        fprintf(stderr, "child: look up: %d\n", k);
        return 1;
    }
    mach_port_t reply;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &reply);
    send_small(server, MACH_MSG_TYPE_COPY_SEND, reply, MACH_MSG_TYPE_MAKE_SEND_ONCE, 'mrzv', 1);

    struct {
        ports_msg m;
        mach_msg_audit_trailer_t t;
    } r;
    memset(&r, 0, sizeof r);
    k = mach_msg(&r.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
                 MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT), 0, sizeof r, reply, 10000, MACH_PORT_NULL);
    if (k != KERN_SUCCESS || r.m.header.msgh_id != 'MRZV') {
        fprintf(stderr, "child: reply: %#x\n", k);
        return 1;
    }
    mach_port_t mine = r.m.receive.name, back = r.m.back.name;

    /* the message that waited on the receive right before it moved */
    struct {
        small_msg m;
        mach_msg_trailer_t t;
    } s;
    k = mach_msg(&s.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof s, mine, 10000, MACH_PORT_NULL);
    int early = k == KERN_SUCCESS ? s.m.value : -1;

    /* the memory entry: read the parent's words, write ours */
    mach_vm_address_t addr = 0;
    k = mach_vm_map(mach_task_self(), &addr, 4096, 0, VM_FLAGS_ANYWHERE, r.m.entry.name, 0, 0,
                    VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    int entry_ok = k == KERN_SUCCESS && !strcmp((char *)addr, "from the parent");
    if (k == KERN_SUCCESS)
        strcpy((char *)addr, "from the child");

    /* the file port: a pipe's write end */
    int fd = fileport_makefd(r.m.file.name);
    if (fd >= 0) {
        write(fd, "through the pipe", 16);
        close(fd);
    }
    unsigned sum = checksum(r.m.ool.address, r.m.ool.size);
    int sender_ok = r.t.msgh_audit.val[5] == (unsigned)getppid();

    /* tell the parent, on the send right it gave */
    send_small(back, MACH_MSG_TYPE_COPY_SEND, MACH_PORT_NULL, 0, 600,
               (early == 41) | entry_ok << 1 | (fd >= 0) << 2 | (sum == r.m.value) << 3 | sender_ok << 4);

    /* the message sent after the receive right moved */
    k = mach_msg(&s.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof s, mine, 10000, MACH_PORT_NULL);
    if (k != KERN_SUCCESS || s.m.value != 42) {
        fprintf(stderr, "child: late message: %#x\n", k);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "child"))
        return child();

    char name[128];
    service_name(name, sizeof name, getpid());
    mach_port_t server;
    printf("check in: %d\n", bootstrap_check_in(bootstrap_port, name, &server));

    /* what the child will get */
    mach_port_t moving, back, entry, file;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &moving);
    mach_port_insert_right(mach_task_self(), moving, moving, MACH_MSG_TYPE_MAKE_SEND);
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &back);
    memory_object_size_t size = 4096;
    mach_make_memory_entry_64(mach_task_self(), &size, 0, MAP_MEM_NAMED_CREATE | VM_PROT_READ | VM_PROT_WRITE,
                              &entry, MACH_PORT_NULL);
    mach_vm_address_t addr = 0;
    mach_vm_map(mach_task_self(), &addr, 4096, 0, VM_FLAGS_ANYWHERE, entry, 0, 0, VM_PROT_READ | VM_PROT_WRITE,
                VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    strcpy((char *)addr, "from the parent");
    int fds[2];
    pipe(fds);
    fileport_makeport(fds[1], &file);
    close(fds[1]);
    unsigned char *ool = malloc(OOL_SIZE);
    for (int i = 0; i < OOL_SIZE; i++)
        ool[i] = (unsigned char)(i * 7 + i / 300);

    /* a message waits on the port whose receive right will move */
    send_small(moving, MACH_MSG_TYPE_COPY_SEND, MACH_PORT_NULL, 0, 500, 41);

    char *args[] = {argv[0], "child", NULL};
    pid_t pid;
    printf("spawn: %d\n", posix_spawn(&pid, argv[0], NULL, NULL, args, environ));

    /* the child's request, with its process in the trailer */
    struct {
        small_msg m;
        mach_msg_audit_trailer_t t;
    } q;
    kern_return_t k = mach_msg(&q.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT |
                               MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
                               MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
                               0, sizeof q, server, 10000, MACH_PORT_NULL);
    printf("request: %#x id %s, from the child %d, a send-once reply %d\n", k,
           q.m.header.msgh_id == 'mrzv' ? "mrzv" : "?", q.t.msgh_audit.val[5] == (unsigned)pid,
           MACH_MSGH_BITS_REMOTE(q.m.header.msgh_bits) == MACH_MSG_TYPE_MOVE_SEND_ONCE);

    ports_msg m;
    memset(&m, 0, sizeof m);
    m.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0) | MACH_MSGH_BITS_COMPLEX;
    m.header.msgh_size = sizeof m;
    m.header.msgh_remote_port = q.m.header.msgh_remote_port;
    m.header.msgh_id = 'MRZV';
    m.body.msgh_descriptor_count = 5;
    m.receive = (mach_msg_port_descriptor_t){moving, 0, 0, MACH_MSG_TYPE_MOVE_RECEIVE, MACH_MSG_PORT_DESCRIPTOR};
    m.entry = (mach_msg_port_descriptor_t){entry, 0, 0, MACH_MSG_TYPE_COPY_SEND, MACH_MSG_PORT_DESCRIPTOR};
    m.file = (mach_msg_port_descriptor_t){file, 0, 0, MACH_MSG_TYPE_MOVE_SEND, MACH_MSG_PORT_DESCRIPTOR};
    m.back = (mach_msg_port_descriptor_t){back, 0, 0, MACH_MSG_TYPE_MAKE_SEND, MACH_MSG_PORT_DESCRIPTOR};
    m.ool.address = ool;
    m.ool.size = OOL_SIZE;
    m.ool.copy = MACH_MSG_VIRTUAL_COPY;
    m.ool.type = MACH_MSG_OOL_DESCRIPTOR;
    m.value = (int)checksum(ool, OOL_SIZE);
    printf("reply: %#x\n", mach_msg(&m.header, MACH_SEND_MSG, sizeof m, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL));

    /* the child says what it got */
    struct {
        small_msg m;
        mach_msg_trailer_t t;
    } s;
    k = mach_msg(&s.m.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof s, back, 10000, MACH_PORT_NULL);
    int v = k == KERN_SUCCESS ? s.m.value : 0;
    printf("child got: the waiting message %d, the memory entry %d, the file port %d, the memory %d, "
           "the sender %d\n", v & 1, v >> 1 & 1, v >> 2 & 1, v >> 3 & 1, v >> 4 & 1);
    printf("memory entry now: %s\n", (char *)addr);
    char buf[32] = {0};
    read(fds[0], buf, sizeof buf - 1);
    printf("pipe: %s\n", buf);

    /* a dead-name notification for the moved port, then a message that follows it */
    mach_port_t notify, previous;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &notify);
    printf("request notification: %d\n",
           mach_port_request_notification(mach_task_self(), moving, MACH_NOTIFY_DEAD_NAME, 0, notify,
                                          MACH_MSG_TYPE_MAKE_SEND_ONCE, &previous));
    printf("late message: %d\n", send_small(moving, MACH_MSG_TYPE_COPY_SEND, MACH_PORT_NULL, 0, 501, 42));

    int status = -1;
    waitpid(pid, &status, 0);
    printf("child exit: %d\n", WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    struct {
        mach_dead_name_notification_t n;
        mach_msg_trailer_t t;
    } d;
    k = mach_msg(&d.n.not_header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof d, notify, 10000, MACH_PORT_NULL);
    printf("dead name: %#x id %d, the moved port %d\n", k, d.n.not_header.msgh_id, d.n.not_port == moving);
    mach_port_type_t type = 0;
    mach_port_type(mach_task_self(), moving, &type);
    printf("now a dead name: %d\n", (type & MACH_PORT_TYPE_DEAD_NAME) != 0);
    printf("send to it: %#x\n", send_small(moving, MACH_MSG_TYPE_COPY_SEND, MACH_PORT_NULL, 0, 502, 43));
    return 0;
}
