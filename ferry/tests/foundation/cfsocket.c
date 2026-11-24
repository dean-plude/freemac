/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: run loop sources and CFSocket from plain C, on 127.0.0.1. A
 * version 0 source signalled on this thread and from another; a listening
 * socket whose accept callback hands over each connection; a background
 * connect and data callbacks both ways, to the end of the stream; datagrams
 * with their sender's address; a read callback that waits to be enabled
 * again; a write callback once; a refused connection; and what invalidating
 * does. */
#include <CoreFoundation/CoreFoundation.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int performed, scheduled, cancelled, done;
static pthread_t main_thread;
static int performed_on_main;

static void src_schedule(void *info, CFRunLoopRef rl, CFRunLoopMode mode) { scheduled++; }
static void src_cancel(void *info, CFRunLoopRef rl, CFRunLoopMode mode) { cancelled++; }
static void src_perform(void *info)
{
    performed++;
    performed_on_main = pthread_equal(pthread_self(), main_thread);
}

static void run_until(int *flag, double seconds)
{
    CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + seconds;
    while (!*flag && CFAbsoluteTimeGetCurrent() < limit)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
}

static void *signal_later(void *arg)
{
    usleep(50000);
    CFRunLoopSourceSignal((CFRunLoopSourceRef)arg);
    CFRunLoopWakeUp(CFRunLoopGetMain());
    return NULL;
}

static void sources(void)
{
    CFRunLoopSourceContext ctx = {0};
    ctx.schedule = src_schedule;
    ctx.cancel = src_cancel;
    ctx.perform = src_perform;
    CFRunLoopSourceRef src = CFRunLoopSourceCreate(NULL, 0, &ctx);
    CFRunLoopRef rl = CFRunLoopGetCurrent();
    CFRunLoopAddSource(rl, src, kCFRunLoopDefaultMode);
    printf("source added: scheduled %d, contained %d\n", scheduled, CFRunLoopContainsSource(rl, src, kCFRunLoopDefaultMode));
    SInt32 r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
    printf("not signalled: run result %d (timed out), performed %d\n", (int)r, performed);
    CFRunLoopSourceSignal(src);
    r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, true);
    printf("signalled: run result %d (handled a source), performed %d\n", (int)r, performed);
    pthread_t t;
    pthread_create(&t, NULL, signal_later, src);
    int target = 2;
    CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + 5;
    while (performed < target && CFAbsoluteTimeGetCurrent() < limit)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
    pthread_join(t, NULL);
    printf("signalled from another thread: performed %d, on this thread %d\n", performed, performed_on_main);
    CFRunLoopRemoveSource(rl, src, kCFRunLoopDefaultMode);
    printf("removed: cancelled %d, contained %d\n", cancelled, CFRunLoopContainsSource(rl, src, kCFRunLoopDefaultMode));
    CFRunLoopSourceInvalidate(src);
    printf("invalidated: valid %d\n", CFRunLoopSourceIsValid(src));
    CFRelease(src);
}

/* ---- a TCP echo through CFSockets ---- */

static CFSocketRef server_conn;
static int accepted, server_got_end, client_connected = -1, client_got_echo;
static char echo[64];

static void conn_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    CFDataRef d = data;
    if (CFDataGetLength(d) == 0) {
        printf("server: the client closed (empty data)\n");
        server_got_end = 1;
        CFSocketInvalidate(s);
        CFRelease(s);
        server_conn = NULL;
        return;
    }
    char up[64] = {0};
    CFIndex n = CFDataGetLength(d) < 63 ? CFDataGetLength(d) : 63;
    for (CFIndex i = 0; i < n; i++)
        up[i] = (char)(CFDataGetBytePtr(d)[i] & ~0x20);
    printf("server: got \"%.*s\" from the peer at %s\n", (int)n, CFDataGetBytePtr(d),
           address && ((const struct sockaddr *)CFDataGetBytePtr(address))->sa_family == AF_INET ? "an IPv4 address"
                                                                                                 : "?");
    CFDataRef reply = CFDataCreate(NULL, (const UInt8 *)up, n);
    printf("server: send %d\n", (int)CFSocketSendData(s, NULL, reply, 2));
    CFRelease(reply);
}

static void listen_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    CFSocketNativeHandle h = *(const CFSocketNativeHandle *)data;
    accepted++;
    const struct sockaddr_in *peer = (const struct sockaddr_in *)CFDataGetBytePtr(address);
    char ip[32];
    inet_ntop(AF_INET, &peer->sin_addr, ip, sizeof ip);
    printf("listener: accept callback, a new socket %d, from %s, address length %ld, info %s\n", h >= 0, ip,
           (long)CFDataGetLength(address), (const char *)info);
    server_conn = CFSocketCreateWithNative(NULL, h, kCFSocketDataCallBack, conn_cb, NULL);
    CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(NULL, server_conn, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
    CFRelease(src);
}

static void client_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    if (type == kCFSocketConnectCallBack) {
        client_connected = data ? *(const SInt32 *)data : 0;
        printf("client: connect callback, %s\n", data ? "failed" : "connected");
        CFDataRef hello = CFDataCreate(NULL, (const UInt8 *)"ferry", 5);
        CFSocketSendData(s, NULL, hello, 2);
        CFRelease(hello);
    } else if (type == kCFSocketDataCallBack) {
        CFIndex n = CFDataGetLength((CFDataRef)data);
        snprintf(echo, sizeof echo, "%.*s", (int)n, CFDataGetBytePtr((CFDataRef)data));
        printf("client: data callback \"%s\"\n", echo);
        client_got_echo = 1;
    }
}

static void tcp(void)
{
    static char info[] = "listener info";
    CFSocketContext ctx = {0, info, NULL, NULL, NULL};
    CFSocketRef listener = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, listen_cb, &ctx);
    struct sockaddr_in sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_len = sizeof sin;
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CFDataRef any = CFDataCreate(NULL, (const UInt8 *)&sin, sizeof sin);
    printf("listener: set address %d\n", (int)CFSocketSetAddress(listener, any));
    CFRelease(any);
    CFDataRef bound = CFSocketCopyAddress(listener);
    const struct sockaddr_in *b = (const struct sockaddr_in *)CFDataGetBytePtr(bound);
    printf("listener: bound length %ld, sin_len %d, family %d, port set %d, flags %lu\n", (long)CFDataGetLength(bound),
           b->sin_len, b->sin_family, b->sin_port != 0, (unsigned long)CFSocketGetSocketFlags(listener));
    CFSocketContext got;
    CFSocketGetContext(listener, &got);
    printf("listener: context info kept %d\n", got.info == info);
    CFRunLoopSourceRef ls = CFSocketCreateRunLoopSource(NULL, listener, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), ls, kCFRunLoopDefaultMode);

    CFSocketRef client = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                        kCFSocketConnectCallBack | kCFSocketDataCallBack, client_cb, NULL);
    CFRunLoopSourceRef cs = CFSocketCreateRunLoopSource(NULL, client, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), cs, kCFRunLoopDefaultMode);
    printf("client: connect in the background %d\n", (int)CFSocketConnectToAddress(client, bound, -1));
    run_until(&client_got_echo, 5);
    CFDataRef peer = CFSocketCopyPeerAddress(client);
    printf("client: echo \"%s\", accepted %d, peer address is the listener's %d\n", echo, accepted, CFEqual(peer, bound));
    CFRelease(peer);
    printf("client: the same CFSocket for its descriptor %d\n",
           CFSocketCreateWithNative(NULL, CFSocketGetNative(client), 0, NULL, NULL) == client);
    CFRelease(client); /* the one just made again */

    int fd = CFSocketGetNative(client);
    CFSocketInvalidate(client);
    printf("client invalidated: valid %d, native %d, descriptor closed %d\n", CFSocketIsValid(client),
           CFSocketGetNative(client), fcntl(fd, F_GETFL) < 0 && errno == EBADF);
    run_until(&server_got_end, 5);
    CFRelease(client);
    CFRunLoopSourceInvalidate(cs);
    CFRelease(cs);

    /* connected by signature, waiting */
    CFSocketSignature sig = {PF_INET, SOCK_STREAM, IPPROTO_TCP, bound};
    CFSocketRef waited = CFSocketCreateConnectedToSocketSignature(NULL, &sig, kCFSocketNoCallBack, NULL, NULL, 2);
    printf("connected by signature: %d\n", waited && CFSocketIsValid(waited));
    int before = accepted;
    CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + 5;
    while (accepted == before && CFAbsoluteTimeGetCurrent() < limit)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
    printf("accepted %d connections\n", accepted);
    CFSocketInvalidate(waited);
    CFRelease(waited);
    CFSocketInvalidate(server_conn);
    CFRelease(server_conn);
    CFSocketInvalidate(listener);
    printf("listener invalidated: its source valid %d\n", CFRunLoopSourceIsValid(ls));
    CFRelease(ls);
    CFRelease(listener);
    CFRelease(bound);
}

/* ---- refused ---- */

static void refused_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    printf("refused: connect callback, error %d (ECONNREFUSED %d)\n", data ? (int)*(const SInt32 *)data : 0,
           data && *(const SInt32 *)data == ECONNREFUSED);
    done = 1;
}

static void refused(void)
{
    int tmp = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sin;
    socklen_t len = sizeof sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_len = sizeof sin;
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(tmp, (struct sockaddr *)&sin, sizeof sin);
    getsockname(tmp, (struct sockaddr *)&sin, &len);
    close(tmp); /* nobody listens there now */
    CFSocketRef s = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketConnectCallBack, refused_cb, NULL);
    CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(NULL, s, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
    CFDataRef to = CFDataCreate(NULL, (const UInt8 *)&sin, sizeof sin);
    CFSocketConnectToAddress(s, to, -1);
    done = 0;
    run_until(&done, 5);
    CFSocketRef s2 = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
    printf("refused, waiting: %d (kCFSocketError)\n", (int)CFSocketConnectToAddress(s2, to, 2));
    CFSocketInvalidate(s2);
    CFRelease(s2);
    CFRelease(to);
    CFSocketInvalidate(s);
    CFRelease(src);
    CFRelease(s);
}

/* ---- datagrams, a read callback enabled again by hand, a write callback ---- */

static int udp_calls, read_calls, write_calls;

static void udp_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    const struct sockaddr_in *from = (const struct sockaddr_in *)CFDataGetBytePtr(address);
    printf("datagram: \"%.*s\" from port %s\n", (int)CFDataGetLength((CFDataRef)data), CFDataGetBytePtr((CFDataRef)data),
           ntohs(from->sin_port) == *(const int *)info ? "of the sender" : "?");
    udp_calls++;
}

static void read_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    read_calls++;
}

static void write_cb(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    write_calls++;
}

static void datagrams(void)
{
    static int sender_port;
    CFSocketContext ctx = {0, &sender_port, NULL, NULL, NULL};
    CFSocketRef rx = CFSocketCreate(NULL, PF_INET, SOCK_DGRAM, IPPROTO_UDP, kCFSocketDataCallBack, udp_cb, &ctx);
    CFSocketRef tx = CFSocketCreate(NULL, PF_INET, SOCK_DGRAM, IPPROTO_UDP, kCFSocketNoCallBack, NULL, NULL);
    struct sockaddr_in sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_len = sizeof sin;
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CFDataRef lo = CFDataCreate(NULL, (const UInt8 *)&sin, sizeof sin);
    CFSocketSetAddress(rx, lo);
    CFSocketSetAddress(tx, lo);
    CFRelease(lo);
    CFDataRef rxa = CFSocketCopyAddress(rx), txa = CFSocketCopyAddress(tx);
    sender_port = ntohs(((const struct sockaddr_in *)CFDataGetBytePtr(txa))->sin_port);
    CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(NULL, rx, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
    CFDataRef one = CFDataCreate(NULL, (const UInt8 *)"one", 3), two = CFDataCreate(NULL, (const UInt8 *)"two", 3);
    printf("sent %d %d\n", (int)CFSocketSendData(tx, rxa, one, 1), (int)CFSocketSendData(tx, rxa, two, 1));
    CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + 5;
    while (udp_calls < 2 && CFAbsoluteTimeGetCurrent() < limit)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
    CFRelease(one);
    CFRelease(two);
    CFSocketInvalidate(rx);
    CFRelease(src);
    CFRelease(rx);

    /* a read callback without automatic re-enabling: once, until enabled again */
    int p[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, p);
    CFSocketRef r = CFSocketCreateWithNative(NULL, p[0], kCFSocketReadCallBack, read_cb, NULL);
    CFSocketSetSocketFlags(r, CFSocketGetSocketFlags(r) & ~kCFSocketAutomaticallyReenableReadCallBack);
    CFRunLoopSourceRef rs = CFSocketCreateRunLoopSource(NULL, r, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rs, kCFRunLoopDefaultMode);
    write(p[1], "x", 1);
    for (int i = 0; i < 5; i++)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    printf("read callback: %d call while the byte waits unread\n", read_calls);
    CFSocketEnableCallBacks(r, kCFSocketReadCallBack);
    for (int i = 0; i < 5 && read_calls < 2; i++)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    printf("enabled again: %d calls\n", read_calls);
    CFSocketInvalidate(r);
    CFRelease(rs);
    CFRelease(r);

    /* a write callback: once by default */
    CFSocketRef w = CFSocketCreateWithNative(NULL, p[1], kCFSocketWriteCallBack, write_cb, NULL);
    CFRunLoopSourceRef ws = CFSocketCreateRunLoopSource(NULL, w, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), ws, kCFRunLoopDefaultMode);
    for (int i = 0; i < 5; i++)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    printf("write callback: %d call\n", write_calls);
    CFSocketInvalidate(w);
    CFRelease(ws);
    CFRelease(w);
    CFSocketInvalidate(tx);
    CFRelease(tx);
    CFRelease(rxa);
    CFRelease(txa);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    main_thread = pthread_self();
    sources();
    tcp();
    refused();
    datagrams();
    printf("CFRunLoopRunInMode with nothing left: %d (finished)\n",
           (int)CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false));
    return 0;
}
