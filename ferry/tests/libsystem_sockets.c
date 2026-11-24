/* Ferry test: BSD sockets with the Mac's structures and numbers, on the
 * loopback addresses only: TCP and UDP over 127.0.0.1 (and ::1 where this
 * system has IPv6), Unix-domain sockets, socket options, control messages,
 * name lookups, interfaces, select and poll. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#define CHECK(x)                                                                                              \
    do {                                                                                                      \
        if (!(x)) {                                                                                           \
            printf("FAILED line %d: %s (errno %d)\n", __LINE__, #x, errno);                                    \
            exit(1);                                                                                          \
        }                                                                                                     \
    } while (0)

static int listener(struct sockaddr_in *at)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    int on = 1;
    CHECK(s >= 0);
    CHECK(setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on) == 0);
    struct sockaddr_in a = {.sin_len = sizeof a, .sin_family = AF_INET, .sin_port = 0};
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(s, (struct sockaddr *)&a, sizeof a) == 0);
    CHECK(listen(s, 4) == 0);
    socklen_t len = sizeof *at;
    memset(at, 0xee, sizeof *at);
    CHECK(getsockname(s, (struct sockaddr *)at, &len) == 0);
    return s;
}

static void layouts(void)
{
    printf("AF_INET %d AF_INET6 %d AF_UNIX %d AF_LINK %d SOL_SOCKET 0x%x\n", AF_INET, AF_INET6, AF_UNIX, AF_LINK,
           SOL_SOCKET);
    printf("sizes: sockaddr %zu in %zu in6 %zu un %zu storage %zu dl %zu\n", sizeof(struct sockaddr),
           sizeof(struct sockaddr_in), sizeof(struct sockaddr_in6), sizeof(struct sockaddr_un),
           sizeof(struct sockaddr_storage), sizeof(struct sockaddr_dl));
    printf("addrinfo %zu: canonname at %zu, addr at %zu; msghdr %zu, cmsghdr %zu, ifaddrs %zu, fd_set %zu\n",
           sizeof(struct addrinfo), offsetof(struct addrinfo, ai_canonname), offsetof(struct addrinfo, ai_addr),
           sizeof(struct msghdr), sizeof(struct cmsghdr), sizeof(struct ifaddrs), sizeof(fd_set));
}

static void tcp4(void)
{
    struct sockaddr_in at;
    int l = listener(&at);
    printf("listener: len %d family %d addr %s port nonzero %d\n", at.sin_len, at.sin_family,
           inet_ntoa(at.sin_addr), at.sin_port != 0);

    int c = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(connect(c, (struct sockaddr *)&at, sizeof at) == 0);
    struct sockaddr_in from, mine, peer;
    socklen_t flen = sizeof from;
    int a = accept(l, (struct sockaddr *)&from, &flen);
    CHECK(a >= 0);
    socklen_t mlen = sizeof mine, plen = sizeof peer;
    CHECK(getsockname(c, (struct sockaddr *)&mine, &mlen) == 0);
    CHECK(getpeername(c, (struct sockaddr *)&peer, &plen) == 0);
    printf("accepted: len %u/%d family %d, matches the client %d, peer is the listener %d\n", flen, from.sin_len,
           from.sin_family, from.sin_port == mine.sin_port && from.sin_addr.s_addr == mine.sin_addr.s_addr,
           peer.sin_port == at.sin_port && plen == sizeof peer);

    /* a short buffer gets the start of the address and the full length */
    unsigned char part[4];
    socklen_t partlen = sizeof part;
    CHECK(getsockname(l, (struct sockaddr *)part, &partlen) == 0);
    printf("short buffer: length %u, first bytes %d %d\n", partlen, part[0], part[1]);

    int v = 0;
    socklen_t vl = sizeof v;
    CHECK(getsockopt(c, SOL_SOCKET, SO_TYPE, &v, &vl) == 0);
    printf("SO_TYPE %d (SOCK_STREAM %d)\n", v, SOCK_STREAM);
    v = 1;
    CHECK(setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &v, sizeof v) == 0);
    v = 0;
    CHECK(getsockopt(c, IPPROTO_TCP, TCP_NODELAY, &v, &vl) == 0);
    printf("TCP_NODELAY %d\n", v != 0);
    v = 1;
    CHECK(setsockopt(c, SOL_SOCKET, SO_KEEPALIVE, &v, sizeof v) == 0);
    v = 30;
    CHECK(setsockopt(c, IPPROTO_TCP, TCP_KEEPALIVE, &v, sizeof v) == 0);
    v = 0;
    CHECK(getsockopt(c, IPPROTO_TCP, TCP_KEEPALIVE, &v, &vl) == 0);
    printf("SO_KEEPALIVE on, TCP_KEEPALIVE %d\n", v);
    CHECK(getsockopt(l, SOL_SOCKET, SO_REUSEADDR, &v, &vl) == 0);
    printf("SO_REUSEADDR %d\n", v != 0);

    CHECK(send(c, "hello", 5, 0) == 5);
    struct pollfd p = {.fd = a, .events = POLLIN};
    CHECK(poll(&p, 1, 2000) == 1);
    CHECK(getsockopt(a, SOL_SOCKET, SO_NREAD, &v, &vl) == 0);
    printf("poll: revents POLLIN %d; SO_NREAD %d\n", (p.revents & POLLIN) != 0, v);
    char buf[64] = {0};
    CHECK(recv(a, buf, 2, MSG_PEEK) == 2);
    printf("peeked %.2s\n", buf);
    CHECK(recv(a, buf, sizeof buf, 0) == 5);
    printf("received %.5s\n", buf);

    /* gathered and scattered */
    struct iovec out[2] = {{"one ", 4}, {"two", 3}};
    struct msghdr m = {.msg_iov = out, .msg_iovlen = 2};
    CHECK(sendmsg(a, &m, 0) == 7);
    char b1[3], b2[8] = {0};
    struct iovec in[2] = {{b1, 3}, {b2, sizeof b2}};
    struct msghdr r = {.msg_iov = in, .msg_iovlen = 2};
    p = (struct pollfd){.fd = c, .events = POLLIN};
    CHECK(poll(&p, 1, 2000) == 1);
    ssize_t got = recvmsg(c, &r, 0);
    printf("recvmsg %zd: %.3s|%.4s flags %d\n", got, b1, b2, r.msg_flags);

    /* timeouts are a Mac struct timeval */
    struct timeval tv = {0, 150000}, back = {0, 0};
    CHECK(setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv) == 0);
    socklen_t tl = sizeof back;
    CHECK(getsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &back, &tl) == 0);
    errno = 0;
    ssize_t n = recv(c, buf, sizeof buf, 0);
    int e0 = errno;
    long us = (long)back.tv_sec * 1000000 + back.tv_usec; /* the kernel may round it to its clock */
    printf("SO_RCVTIMEO about 0.15s %d (len %u): recv %zd errno %d (EAGAIN %d)\n", us >= 140000 && us <= 170000, tl,
           n, e0, EAGAIN);

    /* select with a Mac struct timeval, which it leaves as it was */
    fd_set rs;
    FD_ZERO(&rs);
    FD_SET(c, &rs);
    struct timeval wait = {0, 50000};
    int sel = select(c + 1, &rs, NULL, NULL, &wait);
    printf("select idle: %d, timeout left as %ld.%06d\n", sel, (long)wait.tv_sec, wait.tv_usec);
    CHECK(write(a, "x", 1) == 1);
    FD_ZERO(&rs);
    FD_SET(c, &rs);
    wait = (struct timeval){2, 0};
    sel = select(c + 1, &rs, NULL, NULL, &wait);
    printf("select ready: %d, set %d\n", sel, FD_ISSET(c, &rs));
    CHECK(read(c, buf, 1) == 1);

    /* poll's POLLWRBAND has its own number on a Mac */
    p = (struct pollfd){.fd = c, .events = POLLOUT | POLLWRBAND};
    CHECK(poll(&p, 1, 1000) == 1);
    printf("poll with POLLWRBAND asked too: POLLOUT %d, nothing unknown %d\n", (p.revents & POLLOUT) != 0,
           (p.revents & ~(POLLOUT | POLLWRBAND)) == 0);

    /* end of stream after shutdown */
    CHECK(shutdown(a, SHUT_WR) == 0);
    p = (struct pollfd){.fd = c, .events = POLLIN};
    CHECK(poll(&p, 1, 2000) == 1);
    printf("after shutdown: recv %zd\n", recv(c, buf, sizeof buf, 0));

    /* SO_NOSIGPIPE: writing to a closed peer fails with EPIPE, no signal */
    v = 1;
    CHECK(setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &v, sizeof v) == 0);
    v = 0;
    CHECK(getsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &v, &vl) == 0);
    close(a);
    usleep(50000);
    int e1 = 0, e2 = 0;
    for (int i = 0; i < 20 && !e2; i++) {
        errno = 0;
        if (write(c, "data", 4) < 0)
            e2 = errno;
        else if (send(c, "data", 4, 0) < 0)
            e1 = errno;
        usleep(10000);
    }
    int e3 = e2 ? e2 : e1;
    printf("SO_NOSIGPIPE %d: writing to a closed peer fails with EPIPE or ECONNRESET %d, still running\n", v,
           e3 == EPIPE || e3 == ECONNRESET);
    close(c);

    /* a non-blocking listener: EAGAIN, and the accepted socket stays non-blocking */
    fcntl(l, F_SETFL, fcntl(l, F_GETFL) | O_NONBLOCK);
    errno = 0;
    printf("accept with nobody waiting: %d errno %d\n", accept(l, NULL, NULL), errno);
    c = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(connect(c, (struct sockaddr *)&at, sizeof at) == 0);
    p = (struct pollfd){.fd = l, .events = POLLIN};
    CHECK(poll(&p, 1, 2000) == 1);
    a = accept(l, NULL, NULL);
    CHECK(a >= 0);
    printf("accepted socket non-blocking %d\n", (fcntl(a, F_GETFL) & O_NONBLOCK) != 0);
    close(a);
    close(c);

    /* the same port again without SO_REUSEADDR */
    int d = socket(AF_INET, SOCK_STREAM, 0);
    errno = 0;
    printf("bind to a port in use: %d errno %d (EADDRINUSE %d)\n", bind(d, (struct sockaddr *)&at, sizeof at), errno,
           EADDRINUSE);
    close(d);

    /* connecting to a closed port, blocking and not */
    close(l);
    d = socket(AF_INET, SOCK_STREAM, 0);
    errno = 0;
    printf("connect refused: %d errno %d (ECONNREFUSED %d)\n", connect(d, (struct sockaddr *)&at, sizeof at), errno,
           ECONNREFUSED);
    close(d);
    d = socket(AF_INET, SOCK_STREAM, 0);
    fcntl(d, F_SETFL, O_NONBLOCK);
    int rc = connect(d, (struct sockaddr *)&at, sizeof at);
    int e = errno;
    p = (struct pollfd){.fd = d, .events = POLLOUT};
    poll(&p, 1, 2000);
    v = 0;
    CHECK(getsockopt(d, SOL_SOCKET, SO_ERROR, &v, &vl) == 0);
    printf("non-blocking connect: %d errno %s, then SO_ERROR %d\n", rc,
           rc == 0 ? "-" : e == EINPROGRESS ? "EINPROGRESS" : e == ECONNREFUSED ? "ECONNREFUSED" : "other",
           v ? v : ECONNREFUSED);
    close(d);
}

static void udp4(void)
{
    int s = socket(AF_INET, SOCK_DGRAM, 0), t = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in a = {.sin_len = sizeof a, .sin_family = AF_INET};
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(s, (struct sockaddr *)&a, sizeof a) == 0);
    socklen_t len = sizeof a;
    CHECK(getsockname(s, (struct sockaddr *)&a, &len) == 0);
    int on = 1;
    CHECK(setsockopt(s, IPPROTO_IP, IP_RECVTTL, &on, sizeof on) == 0);
    CHECK(setsockopt(s, IPPROTO_IP, IP_PKTINFO, &on, sizeof on) == 0);
    CHECK(sendto(t, "ping", 4, 0, (struct sockaddr *)&a, sizeof a) == 4);
    char buf[16] = {0};
    struct sockaddr_in from;
    char control[256];
    struct iovec io = {buf, sizeof buf};
    struct msghdr m = {.msg_name = &from, .msg_namelen = sizeof from, .msg_iov = &io, .msg_iovlen = 1,
                       .msg_control = control, .msg_controllen = sizeof control};
    ssize_t n = recvmsg(s, &m, 0);
    printf("udp: %zd bytes %.4s from family %d len %u\n", n, buf, from.sin_family, m.msg_namelen);
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&m); c; c = CMSG_NXTHDR(&m, c)) {
        if (c->cmsg_level == IPPROTO_IP && c->cmsg_type == IP_RECVTTL)
            printf("  IP_RECVTTL: length %u, ttl %d\n", c->cmsg_len, *(unsigned char *)CMSG_DATA(c));
        else if (c->cmsg_level == IPPROTO_IP && c->cmsg_type == IP_PKTINFO) {
            struct in_pktinfo *pi = (struct in_pktinfo *)CMSG_DATA(c);
            printf("  IP_PKTINFO: length %u, to %s\n", c->cmsg_len, inet_ntoa(pi->ipi_addr));
        } else
            printf("  control level %d type %d\n", c->cmsg_level, c->cmsg_type);
    }
    /* recvfrom fills in the sender */
    CHECK(sendto(t, "pong", 4, 0, (struct sockaddr *)&a, sizeof a) == 4);
    len = sizeof from;
    memset(&from, 0, sizeof from);
    n = recvfrom(s, buf, sizeof buf, 0, (struct sockaddr *)&from, &len);
    printf("recvfrom %zd %.4s: len %u/%d family %d %s\n", n, buf, len, from.sin_len, from.sin_family,
           inet_ntoa(from.sin_addr));
    close(s);
    close(t);
}

static void tcp6(void)
{
    int s = socket(AF_INET6, SOCK_STREAM, 0);
    if (s < 0 && errno == EAFNOSUPPORT) {
        printf("ipv6 loopback: not available on this system\n");
        return;
    }
    CHECK(s >= 0);
    int v = 1;
    socklen_t vl = sizeof v;
    CHECK(setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &v, sizeof v) == 0);
    v = 0;
    CHECK(getsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &v, &vl) == 0);
    struct sockaddr_in6 a = {.sin6_len = sizeof a, .sin6_family = AF_INET6, .sin6_addr = in6addr_loopback};
    CHECK(bind(s, (struct sockaddr *)&a, sizeof a) == 0);
    CHECK(listen(s, 1) == 0);
    socklen_t len = sizeof a;
    CHECK(getsockname(s, (struct sockaddr *)&a, &len) == 0);
    int c = socket(AF_INET6, SOCK_STREAM, 0);
    CHECK(connect(c, (struct sockaddr *)&a, sizeof a) == 0);
    struct sockaddr_in6 peer;
    len = sizeof peer;
    int d = accept(s, (struct sockaddr *)&peer, &len);
    CHECK(d >= 0);
    char text[INET6_ADDRSTRLEN];
    printf("ipv6 loopback: v6only %d, peer len %u/%d family %d %s\n", v, len, peer.sin6_len, peer.sin6_family,
           inet_ntop(AF_INET6, &peer.sin6_addr, text, sizeof text));
    close(d);
    close(c);
    close(s);
}

static void unix_sockets(void)
{
    char path[100];
    snprintf(path, sizeof path, "/tmp/ferry-sock-%d", (int)getpid());
    unlink(path);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    strcpy(a.sun_path, path);
    a.sun_len = (unsigned char)SUN_LEN(&a);
    CHECK(bind(s, (struct sockaddr *)&a, SUN_LEN(&a)) == 0);
    CHECK(listen(s, 1) == 0);
    struct sockaddr_un back;
    socklen_t len = sizeof back;
    CHECK(getsockname(s, (struct sockaddr *)&back, &len) == 0);
    printf("unix: bound, name family %d path matches %d, sun_len counts the path %d\n", back.sun_family,
           strcmp(back.sun_path, path) == 0, back.sun_len >= 2 + strlen(path));
    int c = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECK(connect(c, (struct sockaddr *)&a, SUN_LEN(&a)) == 0);
    int d = accept(s, NULL, NULL);
    CHECK(d >= 0);
    pid_t pid = 0;
    socklen_t pl = sizeof pid;
    CHECK(getsockopt(c, SOL_LOCAL, LOCAL_PEERPID, &pid, &pl) == 0);
    uid_t uid;
    gid_t gid;
    CHECK(getpeereid(d, &uid, &gid) == 0);
    struct xucred cred;
    socklen_t cl = sizeof cred;
    CHECK(getsockopt(c, SOL_LOCAL, LOCAL_PEERCRED, &cred, &cl) == 0);
    printf("unix: LOCAL_PEERPID is us %d, getpeereid uid matches %d, xucred uid matches %d groups %d\n",
           pid == getpid(), uid == getuid(), cred.cr_uid == getuid(), cred.cr_ngroups);
    close(c);
    close(d);
    close(s);
    unlink(path);

    /* a descriptor passed across a socket pair */
    int pair[2], pipefd[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    CHECK(pipe(pipefd) == 0);
    union {
        char buf[CMSG_SPACE(sizeof(int))];
        struct cmsghdr align;
    } u;
    memset(&u, 0, sizeof u);
    struct iovec io = {"F", 1};
    struct msghdr m = {.msg_iov = &io, .msg_iovlen = 1, .msg_control = u.buf, .msg_controllen = sizeof u.buf};
    struct cmsghdr *cm = CMSG_FIRSTHDR(&m);
    cm->cmsg_level = SOL_SOCKET;
    cm->cmsg_type = SCM_RIGHTS;
    cm->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(cm), &pipefd[1], sizeof(int));
    CHECK(sendmsg(pair[0], &m, 0) == 1);
    close(pipefd[1]);
    char one;
    union {
        char buf[CMSG_SPACE(sizeof(int))];
        struct cmsghdr align;
    } r;
    struct iovec rio = {&one, 1};
    struct msghdr rm = {.msg_iov = &rio, .msg_iovlen = 1, .msg_control = r.buf, .msg_controllen = sizeof r.buf};
    CHECK(recvmsg(pair[1], &rm, 0) == 1);
    struct cmsghdr *rc = CMSG_FIRSTHDR(&rm);
    int passed = -1;
    if (rc && rc->cmsg_level == SOL_SOCKET && rc->cmsg_type == SCM_RIGHTS)
        memcpy(&passed, CMSG_DATA(rc), sizeof passed);
    printf("SCM_RIGHTS: controllen %u, cmsg_len %u, got a descriptor %d\n", rm.msg_controllen, rc ? rc->cmsg_len : 0,
           passed >= 0);
    CHECK(write(passed, "via", 3) == 3);
    char got[4] = {0};
    CHECK(read(pipefd[0], got, 3) == 3);
    printf("wrote through it: %s\n", got);
    close(passed);
    close(pipefd[0]);
    close(pair[0]);
    close(pair[1]);

    /* datagram pair */
    CHECK(socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) == 0);
    CHECK(send(pair[0], "abc", 3, 0) == 3);
    char dg[2];
    struct iovec dio = {dg, sizeof dg};
    struct msghdr dm = {.msg_iov = &dio, .msg_iovlen = 1};
    ssize_t dn = recvmsg(pair[1], &dm, 0);
    printf("datagram cut short: %zd, MSG_TRUNC %d\n", dn, (dm.msg_flags & MSG_TRUNC) != 0);
    close(pair[0]);
    close(pair[1]);
}

static void names(void)
{
    struct addrinfo hints = {.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV, .ai_family = AF_UNSPEC,
                             .ai_socktype = SOCK_STREAM};
    struct addrinfo *res;
    int rc = getaddrinfo("127.0.0.1", "8080", &hints, &res);
    CHECK(rc == 0);
    struct sockaddr_in *sin = (struct sockaddr_in *)res->ai_addr;
    printf("getaddrinfo 127.0.0.1: family %d socktype %d protocol %d addrlen %u, sin_len %d port %d, next %d\n",
           res->ai_family, res->ai_socktype, res->ai_protocol, res->ai_addrlen, sin->sin_len, ntohs(sin->sin_port),
           res->ai_next != NULL);
    char host[NI_MAXHOST], serv[NI_MAXSERV];
    rc = getnameinfo(res->ai_addr, res->ai_addrlen, host, sizeof host, serv, sizeof serv,
                     NI_NUMERICHOST | NI_NUMERICSERV);
    printf("getnameinfo: %d %s %s\n", rc, host, serv);
    freeaddrinfo(res);

    hints = (struct addrinfo){.ai_flags = AI_NUMERICHOST, .ai_family = AF_INET6};
    rc = getaddrinfo("::1", "443", &hints, &res);
    CHECK(rc == 0);
    struct sockaddr_in6 *s6 = (struct sockaddr_in6 *)res->ai_addr;
    printf("getaddrinfo ::1: family %d addrlen %u sin6_len %d port %d, loopback %d\n", res->ai_family,
           res->ai_addrlen, s6->sin6_len, ntohs(s6->sin6_port), IN6_IS_ADDR_LOOPBACK(&s6->sin6_addr));
    freeaddrinfo(res);

    hints = (struct addrinfo){.ai_flags = AI_CANONNAME, .ai_family = AF_INET, .ai_socktype = SOCK_STREAM};
    rc = getaddrinfo("localhost", "http", &hints, &res);
    CHECK(rc == 0);
    sin = (struct sockaddr_in *)res->ai_addr;
    printf("getaddrinfo localhost http: %s port %d, canonical name %s\n", inet_ntoa(sin->sin_addr),
           ntohs(sin->sin_port), res->ai_canonname ? res->ai_canonname : "(none)");
    freeaddrinfo(res);

    hints = (struct addrinfo){.ai_flags = AI_NUMERICHOST};
    rc = getaddrinfo("not-a-number", NULL, &hints, &res);
    printf("getaddrinfo numeric failure: %d (EAI_NONAME %d) \"%s\"\n", rc, EAI_NONAME, gai_strerror(rc));
    hints = (struct addrinfo){.ai_family = 99};
    printf("bad family: %d (EAI_FAMILY %d) \"%s\"\n", getaddrinfo("127.0.0.1", NULL, &hints, &res), EAI_FAMILY,
           gai_strerror(EAI_FAMILY));

    unsigned char six[16];
    char text[INET6_ADDRSTRLEN];
    printf("inet_pton AF_INET6: %d, back %s\n", inet_pton(AF_INET6, "::ffff:1.2.3.4", six),
           inet_ntop(AF_INET6, six, text, sizeof text));
    struct in_addr four;
    printf("inet_pton AF_INET: %d %08x, inet_aton %d\n", inet_pton(AF_INET, "10.0.0.1", &four), ntohl(four.s_addr),
           inet_aton("192.168.1.2", &four));
    errno = 0;
    printf("inet_pton unknown family: %d errno %d (EAFNOSUPPORT %d)\n", inet_pton(12345, "1.2.3.4", six), errno,
           EAFNOSUPPORT);
    struct hostent *h = gethostbyname("127.0.0.1");
    printf("gethostbyname: type %d length %d first %s\n", h ? h->h_addrtype : -1, h ? h->h_length : -1,
           h ? inet_ntoa(*(struct in_addr *)h->h_addr_list[0]) : "-");
}

static void interfaces(void)
{
    struct ifaddrs *list;
    CHECK(getifaddrs(&list) == 0);
    const char *loop = NULL;
    int link_first = 0, saw_link = 0, saw_inet = 0;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!(i->ifa_flags & IFF_LOOPBACK) || !i->ifa_addr)
            continue;
        if (!loop) {
            loop = i->ifa_name;
            link_first = i->ifa_addr->sa_family == AF_LINK;
        }
        if (strcmp(i->ifa_name, loop))
            continue;
        if (i->ifa_addr->sa_family == AF_LINK) {
            struct sockaddr_dl *dl = (struct sockaddr_dl *)i->ifa_addr;
            struct if_data *d = i->ifa_data;
            saw_link = 1;
            printf("loopback link: len %d type IFT_LOOP %d nlen matches %d alen %d index matches %d, if_data mtu "
                   "nonzero %d\n",
                   dl->sdl_len, dl->sdl_type == IFT_LOOP, dl->sdl_nlen == strlen(loop), dl->sdl_alen,
                   dl->sdl_index == if_nametoindex(loop), d && d->ifi_mtu > 0);
            printf("loopback flags: up %d loopback %d running %d\n", (i->ifa_flags & IFF_UP) != 0,
                   (i->ifa_flags & IFF_LOOPBACK) != 0, (i->ifa_flags & IFF_RUNNING) != 0);
        } else if (i->ifa_addr->sa_family == AF_INET && !saw_inet) {
            struct sockaddr_in *a = (struct sockaddr_in *)i->ifa_addr, *m = (struct sockaddr_in *)i->ifa_netmask;
            saw_inet = 1;
            printf("loopback inet: len %d %s", a->sin_len, inet_ntoa(a->sin_addr));
            printf(" netmask %s\n", inet_ntoa(m->sin_addr));
        }
    }
    printf("loopback's link address comes first %d, link %d inet %d\n", link_first, saw_link, saw_inet);
    char name[IF_NAMESIZE];
    printf("if_indextoname round trip %d\n",
           loop && if_indextoname(if_nametoindex(loop), name) && strcmp(name, loop) == 0);
    freeifaddrs(list);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    layouts();
    tcp4();
    udp4();
    tcp6();
    unix_sockets();
    names();
    interfaces();
    return 0;
}
