/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * BSD sockets, name lookups and network interfaces, as a Mac program calls
 * them. The calls are the same on macOS and Linux, but the data is not:
 *
 *   - a Mac socket address starts with a length byte and a one-byte family
 *     (Linux has a two-byte family and no length), AF_INET6 is 30, and a
 *     Unix-domain path holds 104 bytes rather than 108;
 *   - socket option levels and names (SOL_SOCKET is 0xffff, SO_REUSEADDR 4,
 *     TCP_KEEPALIVE is Linux's TCP_KEEPIDLE...), MSG_ flags, error numbers
 *     (SO_ERROR answers one) and the timeouts' struct timeval differ;
 *   - struct msghdr and struct cmsghdr use 32-bit lengths, and control
 *     messages are aligned to four bytes;
 *   - struct addrinfo has ai_canonname before ai_addr, and the AI_, EAI_
 *     and NI_ numbers differ;
 *   - getifaddrs gives each interface an AF_LINK address (sockaddr_dl)
 *     first, with the link's statistics as struct if_data.
 *
 * Each call converts what the program gives to this system's form, calls
 * the real one, and converts the answer back. Mac-only options with no
 * Linux counterpart are done here where they can be (SO_NOSIGPIPE, SO_NREAD,
 * SO_NWRITE, LOCAL_PEERCRED) and accepted with no effect where they are
 * only hints. Written from the socket(2), getsockopt(2), send(2), recv(2),
 * getaddrinfo(3), getnameinfo(3), getifaddrs(3) and ip(4), ip6(4), tcp(4)
 * and unix(4) reference pages.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <linux/if_link.h>
#include <linux/if_packet.h>
#include <linux/sockios.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#include "ferry.h"

/* ---- address families ------------------------------------------------------------ */

#define MAC_AF_UNSPEC 0
#define MAC_AF_UNIX 1
#define MAC_AF_INET 2
#define MAC_AF_LINK 18
#define MAC_AF_INET6 30

int ferry_af_to_linux(int af)
{
    switch (af) {
    case MAC_AF_UNSPEC: return AF_UNSPEC;
    case MAC_AF_UNIX: return AF_UNIX;
    case MAC_AF_INET: return AF_INET;
    case MAC_AF_INET6: return AF_INET6;
    default: return -1;
    }
}

int ferry_af_to_mac(int af)
{
    switch (af) {
    case AF_UNSPEC: return MAC_AF_UNSPEC;
    case AF_UNIX: return MAC_AF_UNIX;
    case AF_INET: return MAC_AF_INET;
    case AF_INET6: return MAC_AF_INET6;
    case AF_PACKET: return MAC_AF_LINK;
    default: return -1;
    }
}

/* ---- socket addresses ------------------------------------------------------------ */

#define MAC_SUN_PATH 104

/* A Mac address, as the program gives it, in this system's form. */
static int addr_in(const void *mac, socklen_t len, struct sockaddr_storage *out, socklen_t *outlen)
{
    const uint8_t *m = mac;
    memset(out, 0, sizeof *out);
    if (!mac || len < 2) {
        errno = EINVAL;
        return -1;
    }
    switch (m[1]) {
    case MAC_AF_INET: {
        if (len < sizeof(struct sockaddr_in)) {
            errno = EINVAL;
            return -1;
        }
        struct sockaddr_in *s = (struct sockaddr_in *)out;
        s->sin_family = AF_INET;
        memcpy(&s->sin_port, m + 2, 2);
        memcpy(&s->sin_addr, m + 4, 4);
        *outlen = sizeof *s;
        return 0;
    }
    case MAC_AF_INET6: {
        if (len < sizeof(struct sockaddr_in6)) {
            errno = EINVAL;
            return -1;
        }
        struct sockaddr_in6 *s = (struct sockaddr_in6 *)out;
        s->sin6_family = AF_INET6;
        memcpy((uint8_t *)s + 2, m + 2, sizeof *s - 2);
        *outlen = sizeof *s;
        return 0;
    }
    case MAC_AF_UNIX: {
        struct sockaddr_un *s = (struct sockaddr_un *)out;
        size_t room = len - 2 > MAC_SUN_PATH ? MAC_SUN_PATH : len - 2;
        size_t plen = strnlen((const char *)m + 2, room);
        s->sun_family = AF_UNIX;
        memcpy(s->sun_path, m + 2, plen);
        *outlen = plen ? (socklen_t)(offsetof(struct sockaddr_un, sun_path) + plen + 1) : sizeof(sa_family_t);
        return 0;
    }
    case MAC_AF_UNSPEC:
        out->ss_family = AF_UNSPEC;
        *outlen = len > sizeof *out ? sizeof *out : len;
        return 0;
    default:
        errno = EAFNOSUPPORT;
        return -1;
    }
}

/* This system's address as a Mac one, into the program's buffer of *maclen
 * bytes (cut short if it is smaller); *maclen becomes the address's size. */
static void addr_out(const struct sockaddr *lnx, socklen_t lnxlen, void *mac, socklen_t *maclen)
{
    if (!mac || !maclen)
        return;
    uint8_t buf[sizeof(struct sockaddr_storage)] = {0};
    socklen_t n;
    if (lnxlen < sizeof(sa_family_t)) { /* no address (a connected stream's recvfrom) */
        *maclen = 0;
        return;
    }
    switch (lnx->sa_family) {
    case AF_INET:
        n = sizeof(struct sockaddr_in);
        memcpy(buf + 2, (const uint8_t *)lnx + 2, n - 2);
        buf[1] = MAC_AF_INET;
        break;
    case AF_INET6:
        n = sizeof(struct sockaddr_in6);
        memcpy(buf + 2, (const uint8_t *)lnx + 2, n - 2);
        buf[1] = MAC_AF_INET6;
        break;
    case AF_UNIX: {
        const struct sockaddr_un *s = (const struct sockaddr_un *)lnx;
        size_t plen = lnxlen > 2 ? strnlen(s->sun_path, lnxlen - 2) : 0;
        if (plen > MAC_SUN_PATH - 1)
            plen = MAC_SUN_PATH - 1;
        memcpy(buf + 2, s->sun_path, plen);
        n = plen ? (socklen_t)(2 + plen + 1) : 16; /* an unnamed socket's address */
        buf[1] = MAC_AF_UNIX;
        break;
    }
    default: {
        n = lnxlen > sizeof buf ? sizeof buf : lnxlen;
        memcpy(buf, lnx, n);
        int af = ferry_af_to_mac(lnx->sa_family);
        buf[1] = (uint8_t)(af >= 0 ? af : lnx->sa_family);
        break;
    }
    }
    buf[0] = (uint8_t)n;
    memcpy(mac, buf, *maclen < n ? *maclen : n);
    *maclen = n;
}

/* ---- SO_NOSIGPIPE ------------------------------------------------------------------
 * Linux has no such option: the descriptors that have it are kept here, and
 * sends and writes on them pass MSG_NOSIGNAL. */

#define NOSIG_MAX (1 << 20)
static uint8_t nosig_bits[NOSIG_MAX / 8];

static void set_nosigpipe(int fd, int on)
{
    if (fd < 0 || fd >= NOSIG_MAX)
        return;
    uint8_t bit = (uint8_t)(1u << (fd & 7));
    if (on)
        __atomic_fetch_or(&nosig_bits[fd >> 3], bit, __ATOMIC_RELAXED);
    else
        __atomic_fetch_and(&nosig_bits[fd >> 3], (uint8_t)~bit, __ATOMIC_RELAXED);
}

int ferry_fd_nosigpipe(int fd)
{
    return fd >= 0 && fd < NOSIG_MAX && (__atomic_load_n(&nosig_bits[fd >> 3], __ATOMIC_RELAXED) >> (fd & 7)) & 1;
}

void ferry_socket_closed(int fd) { set_nosigpipe(fd, 0); }

/* ---- message flags ---------------------------------------------------------------- */

static const struct { int mac, lnx; } msg_bits[] = {
    {0x1, MSG_OOB}, {0x2, MSG_PEEK}, {0x4, MSG_DONTROUTE}, {0x8, MSG_EOR}, {0x10, MSG_TRUNC},
    {0x20, MSG_CTRUNC}, {0x40, MSG_WAITALL}, {0x80, MSG_DONTWAIT}, {0x80000, MSG_NOSIGNAL},
};
#define NMSG (sizeof msg_bits / sizeof msg_bits[0])

static int msg_to_linux(int fd, int mac)
{
    int out = 0;
    for (size_t i = 0; i < NMSG; i++)
        if (mac & msg_bits[i].mac)
            out |= msg_bits[i].lnx;
    return out;
}

static int msg_to_mac(int lnx)
{
    int out = 0;
    for (size_t i = 0; i < NMSG; i++)
        if (lnx & msg_bits[i].lnx)
            out |= msg_bits[i].mac;
    return out;
}

static int send_flags(int fd, int mac)
{
    int f = msg_to_linux(fd, mac);
    if (ferry_fd_nosigpipe(fd))
        f |= MSG_NOSIGNAL;
    return f;
}

/* ---- creating and connecting ------------------------------------------------------- */

static int mac_socket(int domain, int type, int protocol)
{
    int d = ferry_af_to_linux(domain);
    if (d < 0 || d == AF_UNSPEC) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    int fd = socket(d, type, protocol);
    if (fd >= 0)
        set_nosigpipe(fd, 0);
    return fd;
}

static int mac_socketpair(int domain, int type, int protocol, int sv[2])
{
    int d = ferry_af_to_linux(domain);
    if (d < 0 || d == AF_UNSPEC) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    int rc = socketpair(d, type, protocol, sv);
    if (rc == 0) {
        set_nosigpipe(sv[0], 0);
        set_nosigpipe(sv[1], 0);
    }
    return rc;
}

static int mac_bind(int s, const void *addr, socklen_t len)
{
    struct sockaddr_storage a;
    socklen_t alen;
    if (addr_in(addr, len, &a, &alen) < 0)
        return -1;
    return bind(s, (struct sockaddr *)&a, alen);
}

static int mac_connect(int s, const void *addr, socklen_t len)
{
    struct sockaddr_storage a;
    socklen_t alen;
    if (addr_in(addr, len, &a, &alen) < 0)
        return -1;
    return connect(s, (struct sockaddr *)&a, alen);
}

/* As on BSD, an accepted socket keeps the listening one's O_NONBLOCK. */
static int mac_accept(int s, void *addr, socklen_t *len)
{
    struct sockaddr_storage a;
    socklen_t alen = sizeof a;
    int fl = fcntl(s, F_GETFL);
    int fd = accept4(s, (struct sockaddr *)&a, &alen, fl >= 0 && (fl & O_NONBLOCK) ? SOCK_NONBLOCK : 0);
    if (fd < 0)
        return fd;
    set_nosigpipe(fd, 0);
    if (addr && len)
        addr_out((struct sockaddr *)&a, alen, addr, len);
    return fd;
}

static int mac_getsockname(int s, void *addr, socklen_t *len)
{
    struct sockaddr_storage a;
    socklen_t alen = sizeof a;
    int rc = getsockname(s, (struct sockaddr *)&a, &alen);
    if (rc == 0)
        addr_out((struct sockaddr *)&a, alen, addr, len);
    return rc;
}

static int mac_getpeername(int s, void *addr, socklen_t *len)
{
    struct sockaddr_storage a;
    socklen_t alen = sizeof a;
    int rc = getpeername(s, (struct sockaddr *)&a, &alen);
    if (rc == 0)
        addr_out((struct sockaddr *)&a, alen, addr, len);
    return rc;
}

static int mac_getpeereid(int s, uid_t *uid, gid_t *gid)
{
    struct ucred c;
    socklen_t len = sizeof c;
    if (getsockopt(s, SOL_SOCKET, SO_PEERCRED, &c, &len) < 0)
        return -1;
    if (uid)
        *uid = c.uid;
    if (gid)
        *gid = c.gid;
    return 0;
}

/* ---- socket options ---------------------------------------------------------------- */

enum {
    K_RAW,        /* the same value either way (an int, a char, a struct of the same layout) */
    K_TIMEVAL,    /* struct timeval: the Mac's tv_usec is 32 bits */
    K_ERROR,      /* an error number */
    K_NOSIGPIPE,
    K_NREAD,
    K_NWRITE,
    K_BOUNDIF,    /* IP_BOUND_IF, IPV6_BOUND_IF: SO_BINDTOIFINDEX */
    K_DONTFRAG,   /* IP_DONTFRAG: IP_MTU_DISCOVER */
    K_SETIGNORED, /* Linux can't set it: setting is accepted, reading is passed on */
    K_IGNORED,    /* a hint with no Linux counterpart: accepted with no effect, reads as 0 */
};

#define MAC_SOL_SOCKET 0xffff
static const struct sopt { int mlevel, mname, llevel, lname, kind; } opts[] = {
    {MAC_SOL_SOCKET, 0x0001, SOL_SOCKET, SO_DEBUG, K_RAW},
    {MAC_SOL_SOCKET, 0x0002, SOL_SOCKET, SO_ACCEPTCONN, K_RAW},
    {MAC_SOL_SOCKET, 0x0004, SOL_SOCKET, SO_REUSEADDR, K_RAW},
    {MAC_SOL_SOCKET, 0x0008, SOL_SOCKET, SO_KEEPALIVE, K_RAW},
    {MAC_SOL_SOCKET, 0x0010, SOL_SOCKET, SO_DONTROUTE, K_RAW},
    {MAC_SOL_SOCKET, 0x0020, SOL_SOCKET, SO_BROADCAST, K_RAW},
    {MAC_SOL_SOCKET, 0x0040, 0, 0, K_IGNORED},                 /* SO_USELOOPBACK */
    {MAC_SOL_SOCKET, 0x0080, SOL_SOCKET, SO_LINGER, K_RAW},
    {MAC_SOL_SOCKET, 0x1080, SOL_SOCKET, SO_LINGER, K_RAW},    /* SO_LINGER_SEC */
    {MAC_SOL_SOCKET, 0x0100, SOL_SOCKET, SO_OOBINLINE, K_RAW},
    {MAC_SOL_SOCKET, 0x0200, SOL_SOCKET, SO_REUSEPORT, K_RAW},
    {MAC_SOL_SOCKET, 0x0400, SOL_SOCKET, SO_TIMESTAMP, K_RAW},
    {MAC_SOL_SOCKET, 0x1001, SOL_SOCKET, SO_SNDBUF, K_RAW},
    {MAC_SOL_SOCKET, 0x1002, SOL_SOCKET, SO_RCVBUF, K_RAW},
    {MAC_SOL_SOCKET, 0x1003, SOL_SOCKET, SO_SNDLOWAT, K_SETIGNORED},
    {MAC_SOL_SOCKET, 0x1004, SOL_SOCKET, SO_RCVLOWAT, K_RAW},
    {MAC_SOL_SOCKET, 0x1005, SOL_SOCKET, SO_SNDTIMEO, K_TIMEVAL},
    {MAC_SOL_SOCKET, 0x1006, SOL_SOCKET, SO_RCVTIMEO, K_TIMEVAL},
    {MAC_SOL_SOCKET, 0x1007, SOL_SOCKET, SO_ERROR, K_ERROR},
    {MAC_SOL_SOCKET, 0x1008, SOL_SOCKET, SO_TYPE, K_RAW},
    {MAC_SOL_SOCKET, 0x1020, 0, 0, K_NREAD},
    {MAC_SOL_SOCKET, 0x1022, 0, 0, K_NOSIGPIPE},
    {MAC_SOL_SOCKET, 0x1023, 0, 0, K_IGNORED},                 /* SO_NOADDRERR */
    {MAC_SOL_SOCKET, 0x1024, 0, 0, K_NWRITE},
    {MAC_SOL_SOCKET, 0x1082, 0, 0, K_IGNORED},                 /* SO_RANDOMPORT */
    {MAC_SOL_SOCKET, 0x1116, 0, 0, K_IGNORED},                 /* SO_NET_SERVICE_TYPE */
    {IPPROTO_TCP, 0x01, IPPROTO_TCP, TCP_NODELAY, K_RAW},
    {IPPROTO_TCP, 0x02, IPPROTO_TCP, TCP_MAXSEG, K_RAW},
    {IPPROTO_TCP, 0x04, IPPROTO_TCP, TCP_CORK, K_RAW},         /* TCP_NOPUSH */
    {IPPROTO_TCP, 0x08, 0, 0, K_IGNORED},                      /* TCP_NOOPT */
    {IPPROTO_TCP, 0x10, IPPROTO_TCP, TCP_KEEPIDLE, K_RAW},     /* TCP_KEEPALIVE */
    {IPPROTO_TCP, 0x20, 0, 0, K_IGNORED},                      /* TCP_CONNECTIONTIMEOUT */
    {IPPROTO_TCP, 0x101, IPPROTO_TCP, TCP_KEEPINTVL, K_RAW},
    {IPPROTO_TCP, 0x102, IPPROTO_TCP, TCP_KEEPCNT, K_RAW},
    {IPPROTO_TCP, 0x103, 0, 0, K_IGNORED},                     /* TCP_SENDMOREACKS */
    {IPPROTO_TCP, 0x104, 0, 0, K_IGNORED},                     /* TCP_ENABLE_ECN */
    {IPPROTO_TCP, 0x105, IPPROTO_TCP, TCP_FASTOPEN, K_RAW},
    {IPPROTO_TCP, 0x201, IPPROTO_TCP, TCP_NOTSENT_LOWAT, K_RAW},
    {IPPROTO_IP, 1, IPPROTO_IP, IP_OPTIONS, K_RAW},
    {IPPROTO_IP, 2, IPPROTO_IP, IP_HDRINCL, K_RAW},
    {IPPROTO_IP, 3, IPPROTO_IP, IP_TOS, K_RAW},
    {IPPROTO_IP, 4, IPPROTO_IP, IP_TTL, K_RAW},
    {IPPROTO_IP, 5, IPPROTO_IP, IP_RECVOPTS, K_RAW},
    {IPPROTO_IP, 6, IPPROTO_IP, IP_RECVRETOPTS, K_RAW},
    {IPPROTO_IP, 8, IPPROTO_IP, IP_RETOPTS, K_RAW},
    {IPPROTO_IP, 9, IPPROTO_IP, IP_MULTICAST_IF, K_RAW},
    {IPPROTO_IP, 10, IPPROTO_IP, IP_MULTICAST_TTL, K_RAW},
    {IPPROTO_IP, 11, IPPROTO_IP, IP_MULTICAST_LOOP, K_RAW},
    {IPPROTO_IP, 12, IPPROTO_IP, IP_ADD_MEMBERSHIP, K_RAW},
    {IPPROTO_IP, 13, IPPROTO_IP, IP_DROP_MEMBERSHIP, K_RAW},
    {IPPROTO_IP, 24, IPPROTO_IP, IP_RECVTTL, K_RAW},
    {IPPROTO_IP, 25, 0, 0, K_BOUNDIF},
    {IPPROTO_IP, 26, IPPROTO_IP, IP_PKTINFO, K_RAW},
    {IPPROTO_IP, 27, IPPROTO_IP, IP_RECVTOS, K_RAW},
    {IPPROTO_IP, 28, IPPROTO_IP, IP_MTU_DISCOVER, K_DONTFRAG},
    {IPPROTO_IPV6, 4, IPPROTO_IPV6, IPV6_UNICAST_HOPS, K_RAW},
    {IPPROTO_IPV6, 9, IPPROTO_IPV6, IPV6_MULTICAST_IF, K_RAW},
    {IPPROTO_IPV6, 10, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, K_RAW},
    {IPPROTO_IPV6, 11, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, K_RAW},
    {IPPROTO_IPV6, 12, IPPROTO_IPV6, IPV6_ADD_MEMBERSHIP, K_RAW},
    {IPPROTO_IPV6, 13, IPPROTO_IPV6, IPV6_DROP_MEMBERSHIP, K_RAW},
    {IPPROTO_IPV6, 27, IPPROTO_IPV6, IPV6_V6ONLY, K_RAW},
    {IPPROTO_IPV6, 35, IPPROTO_IPV6, IPV6_RECVTCLASS, K_RAW},
    {IPPROTO_IPV6, 36, IPPROTO_IPV6, IPV6_TCLASS, K_RAW},
    {IPPROTO_IPV6, 37, IPPROTO_IPV6, IPV6_RECVHOPLIMIT, K_RAW},
    {IPPROTO_IPV6, 46, IPPROTO_IPV6, IPV6_PKTINFO, K_RAW},
    {IPPROTO_IPV6, 47, IPPROTO_IPV6, IPV6_HOPLIMIT, K_RAW},
    {IPPROTO_IPV6, 61, IPPROTO_IPV6, IPV6_RECVPKTINFO, K_RAW},
    {IPPROTO_IPV6, 62, IPPROTO_IPV6, IPV6_DONTFRAG, K_RAW},
    {IPPROTO_IPV6, 125, 0, 0, K_BOUNDIF},
};

static const struct sopt *find_opt(int level, int name)
{
    for (size_t i = 0; i < sizeof opts / sizeof opts[0]; i++)
        if (opts[i].mlevel == level && opts[i].mname == name)
            return &opts[i];
    return NULL;
}

/* The Mac's struct timeval: a 64-bit tv_sec and a 32-bit tv_usec, padded to 16 bytes. */
struct mac_timeval { long tv_sec; int32_t tv_usec, pad; };

static int is_unix_socket(int s)
{
    int d = 0;
    socklen_t len = sizeof d;
    return getsockopt(s, SOL_SOCKET, SO_DOMAIN, &d, &len) == 0 && d == AF_UNIX;
}

#define MAC_LOCAL_PEERCRED 1
#define MAC_LOCAL_PEERPID 2
#define MAC_LOCAL_PEEREPID 3
struct mac_xucred { uint32_t version, uid; int16_t ngroups; uint32_t groups[16]; };

static int mac_setsockopt(int s, int level, int name, const void *value, socklen_t len)
{
    if (level == 0 && name >= MAC_LOCAL_PEERCRED && name <= MAC_LOCAL_PEEREPID && is_unix_socket(s)) {
        errno = ENOPROTOOPT; /* they can only be read */
        return -1;
    }
    const struct sopt *o = find_opt(level, name);
    if (!o) {
        errno = ENOPROTOOPT;
        return -1;
    }
    int v = value && len >= sizeof(int) ? *(const int *)value : value && len >= 1 ? *(const uint8_t *)value : 0;
    switch (o->kind) {
    case K_RAW:
        return setsockopt(s, o->llevel, o->lname, value, len);
    case K_TIMEVAL: {
        if (!value || len < sizeof(struct mac_timeval)) {
            errno = EINVAL;
            return -1;
        }
        const struct mac_timeval *m = value;
        struct timeval tv = {m->tv_sec, m->tv_usec};
        return setsockopt(s, o->llevel, o->lname, &tv, sizeof tv);
    }
    case K_NOSIGPIPE: {
        int type;
        socklen_t tl = sizeof type;
        if (getsockopt(s, SOL_SOCKET, SO_TYPE, &type, &tl) < 0)
            return -1;
        set_nosigpipe(s, v != 0);
        return 0;
    }
    case K_BOUNDIF:
        return setsockopt(s, SOL_SOCKET, SO_BINDTOIFINDEX, &v, sizeof v);
    case K_DONTFRAG: {
        int pmtu = v ? IP_PMTUDISC_DO : IP_PMTUDISC_DONT;
        return setsockopt(s, IPPROTO_IP, IP_MTU_DISCOVER, &pmtu, sizeof pmtu);
    }
    case K_SETIGNORED:
    case K_IGNORED:
    case K_NREAD:
    case K_NWRITE: {
        int type;
        socklen_t tl = sizeof type;
        if (getsockopt(s, SOL_SOCKET, SO_TYPE, &type, &tl) < 0)
            return -1;
        if (o->kind == K_NREAD || o->kind == K_NWRITE || o->kind == K_ERROR) {
            errno = ENOPROTOOPT;
            return -1;
        }
        return 0;
    }
    default:
        errno = ENOPROTOOPT;
        return -1;
    }
}

static int put_int(void *value, socklen_t *len, int v)
{
    if (!value || !len || *len < sizeof(int)) {
        errno = EINVAL;
        return -1;
    }
    *(int *)value = v;
    *len = sizeof(int);
    return 0;
}

static int mac_getsockopt(int s, int level, int name, void *value, socklen_t *len)
{
    if (level == 0 && name >= MAC_LOCAL_PEERCRED && name <= MAC_LOCAL_PEEREPID && is_unix_socket(s)) {
        struct ucred c;
        socklen_t cl = sizeof c;
        if (getsockopt(s, SOL_SOCKET, SO_PEERCRED, &c, &cl) < 0)
            return -1;
        if (name != MAC_LOCAL_PEERCRED)
            return put_int(value, len, c.pid);
        if (!value || !len || *len < sizeof(struct mac_xucred)) {
            errno = EINVAL;
            return -1;
        }
        struct mac_xucred x = {.version = 0, .uid = c.uid, .ngroups = 1, .groups = {c.gid}};
        memcpy(value, &x, sizeof x);
        *len = sizeof x;
        return 0;
    }
    const struct sopt *o = find_opt(level, name);
    if (!o) {
        errno = ENOPROTOOPT;
        return -1;
    }
    int v = 0;
    socklen_t vl = sizeof v;
    switch (o->kind) {
    case K_RAW:
    case K_SETIGNORED:
        return getsockopt(s, o->llevel, o->lname, value, len);
    case K_TIMEVAL: {
        struct timeval tv;
        socklen_t tl = sizeof tv;
        if (getsockopt(s, o->llevel, o->lname, &tv, &tl) < 0)
            return -1;
        if (!value || !len || *len < sizeof(struct mac_timeval)) {
            errno = EINVAL;
            return -1;
        }
        struct mac_timeval m = {tv.tv_sec, (int32_t)tv.tv_usec, 0};
        memcpy(value, &m, sizeof m);
        *len = sizeof m;
        return 0;
    }
    case K_ERROR:
        if (getsockopt(s, o->llevel, o->lname, &v, &vl) < 0)
            return -1;
        return put_int(value, len, ferry_errno_to_mac(v));
    case K_NOSIGPIPE:
        if (getsockopt(s, SOL_SOCKET, SO_TYPE, &v, &vl) < 0)
            return -1;
        return put_int(value, len, ferry_fd_nosigpipe(s));
    case K_NREAD:
        if (ioctl(s, FIONREAD, &v) < 0) {
            if (errno != EINVAL)
                return -1;
            v = 0; /* a listening socket */
        }
        return put_int(value, len, v);
    case K_NWRITE:
        if (ioctl(s, SIOCOUTQ, &v) < 0)
            return -1;
        return put_int(value, len, v);
    case K_BOUNDIF:
        if (getsockopt(s, SOL_SOCKET, SO_BINDTOIFINDEX, &v, &vl) < 0)
            return -1;
        return put_int(value, len, v);
    case K_DONTFRAG:
        if (getsockopt(s, IPPROTO_IP, IP_MTU_DISCOVER, &v, &vl) < 0)
            return -1;
        return put_int(value, len, v == IP_PMTUDISC_DO);
    case K_IGNORED:
        if (getsockopt(s, SOL_SOCKET, SO_TYPE, &v, &vl) < 0)
            return -1;
        return put_int(value, len, 0);
    default:
        errno = ENOPROTOOPT;
        return -1;
    }
}

/* ---- sending and receiving --------------------------------------------------------- */

static ssize_t mac_send(int s, const void *buf, size_t len, int flags)
{
    return send(s, buf, len, send_flags(s, flags));
}

static ssize_t mac_recv(int s, void *buf, size_t len, int flags) { return recv(s, buf, len, msg_to_linux(s, flags)); }

static ssize_t mac_sendto(int s, const void *buf, size_t len, int flags, const void *to, socklen_t tolen)
{
    struct sockaddr_storage a;
    socklen_t alen = 0;
    if (to && addr_in(to, tolen, &a, &alen) < 0)
        return -1;
    return sendto(s, buf, len, send_flags(s, flags), to ? (struct sockaddr *)&a : NULL, alen);
}

static ssize_t mac_recvfrom(int s, void *buf, size_t len, int flags, void *from, socklen_t *fromlen)
{
    struct sockaddr_storage a;
    socklen_t alen = sizeof a;
    ssize_t n = recvfrom(s, buf, len, msg_to_linux(s, flags), (struct sockaddr *)&a, &alen);
    if (n >= 0 && from && fromlen)
        addr_out((struct sockaddr *)&a, alen, from, fromlen);
    return n;
}

/* Writes and sends on a socket with SO_NOSIGPIPE mustn't raise SIGPIPE. */
static ssize_t mac_write(int fd, const void *buf, size_t n)
{
    if (ferry_fd_nosigpipe(fd)) {
        ssize_t r = send(fd, buf, n, MSG_NOSIGNAL);
        if (r >= 0 || errno != ENOTSOCK)
            return r;
    }
    return write(fd, buf, n);
}

static ssize_t mac_writev(int fd, const struct iovec *iov, int count)
{
    if (ferry_fd_nosigpipe(fd)) {
        struct msghdr m = {.msg_iov = (struct iovec *)iov, .msg_iovlen = count > 0 ? (size_t)count : 0};
        ssize_t r = sendmsg(fd, &m, MSG_NOSIGNAL);
        if (r >= 0 || errno != ENOTSOCK)
            return r;
    }
    return writev(fd, iov, count);
}

/* The Mac's struct msghdr and struct cmsghdr. */
struct mac_msghdr {
    void *name;
    uint32_t namelen;
    struct iovec *iov;
    int iovlen;
    void *control;
    uint32_t controllen;
    int flags;
};
struct mac_cmsghdr { uint32_t len; int level, type; };
#define MAC_ALIGN(n) (((size_t)(n) + 3) & ~(size_t)3)
#define MAC_CMSG_HDR MAC_ALIGN(sizeof(struct mac_cmsghdr))

/* The control messages both systems have: {Mac level, Mac type, level, type, kind}. */
enum { C_SAME, C_TIMEVAL, C_INT_TO_BYTE };
static const struct ctype { int mlevel, mtype, llevel, ltype, kind; } ctypes[] = {
    {MAC_SOL_SOCKET, 1, SOL_SOCKET, SCM_RIGHTS, C_SAME},
    {MAC_SOL_SOCKET, 2, SOL_SOCKET, SCM_TIMESTAMP, C_TIMEVAL},
    {IPPROTO_IP, 26, IPPROTO_IP, IP_PKTINFO, C_SAME},
    {IPPROTO_IP, 24, IPPROTO_IP, IP_TTL, C_INT_TO_BYTE},      /* IP_RECVTTL: a byte on a Mac */
    {IPPROTO_IP, 27, IPPROTO_IP, IP_TOS, C_SAME},             /* IP_RECVTOS */
    {IPPROTO_IPV6, 46, IPPROTO_IPV6, IPV6_PKTINFO, C_SAME},
    {IPPROTO_IPV6, 47, IPPROTO_IPV6, IPV6_HOPLIMIT, C_SAME},
    {IPPROTO_IPV6, 36, IPPROTO_IPV6, IPV6_TCLASS, C_SAME},
};
#define NCTYPES (sizeof ctypes / sizeof ctypes[0])

/* The program's control messages in this system's form; -1 for one Ferry
 * doesn't know. */
static ssize_t control_in(const uint8_t *mac, size_t maclen, uint8_t *out, size_t room)
{
    size_t used = 0;
    for (size_t off = 0; off + sizeof(struct mac_cmsghdr) <= maclen;) {
        const struct mac_cmsghdr *m = (const void *)(mac + off);
        if (m->len < sizeof *m || off + m->len > maclen)
            break;
        size_t dlen = m->len - MAC_CMSG_HDR;
        const uint8_t *data = mac + off + MAC_CMSG_HDR;
        const struct ctype *t = NULL;
        for (size_t i = 0; i < NCTYPES; i++)
            if (ctypes[i].mlevel == m->level && ctypes[i].mtype == m->type)
                t = &ctypes[i];
        if (!t) {
            errno = EINVAL;
            return -1;
        }
        uint8_t tmp[32];
        if (t->kind == C_TIMEVAL && dlen >= sizeof(struct mac_timeval)) {
            const struct mac_timeval *tv = (const void *)data;
            struct timeval lt = {tv->tv_sec, tv->tv_usec};
            memcpy(tmp, &lt, sizeof lt);
            data = tmp;
            dlen = sizeof lt;
        } else if (t->kind == C_INT_TO_BYTE && dlen >= 1) {
            int v = data[0];
            memcpy(tmp, &v, sizeof v);
            data = tmp;
            dlen = sizeof v;
        }
        if (used + CMSG_SPACE(dlen) > room) {
            errno = ENOBUFS;
            return -1;
        }
        struct cmsghdr *c = (struct cmsghdr *)(out + used);
        memset(c, 0, CMSG_SPACE(dlen));
        c->cmsg_len = CMSG_LEN(dlen);
        c->cmsg_level = t->llevel;
        c->cmsg_type = t->ltype;
        memcpy(CMSG_DATA(c), data, dlen);
        used += CMSG_SPACE(dlen);
        off += MAC_ALIGN(m->len);
    }
    return (ssize_t)used;
}

/* Received control messages in the Mac's form; sets *truncated when some
 * didn't fit or weren't understood (descriptors that don't fit are closed). */
static size_t control_out(struct msghdr *lm, uint8_t *mac, size_t room, int *truncated)
{
    size_t used = 0;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(lm); c; c = CMSG_NXTHDR(lm, c)) {
        size_t dlen = c->cmsg_len - CMSG_LEN(0);
        const uint8_t *data = CMSG_DATA(c);
        const struct ctype *t = NULL;
        for (size_t i = 0; i < NCTYPES; i++)
            if (ctypes[i].llevel == c->cmsg_level && ctypes[i].ltype == c->cmsg_type)
                t = &ctypes[i];
        uint8_t tmp[32];
        if (t && t->kind == C_TIMEVAL && dlen >= sizeof(struct timeval)) {
            const struct timeval *tv = (const void *)data;
            struct mac_timeval m = {tv->tv_sec, (int32_t)tv->tv_usec, 0};
            memcpy(tmp, &m, sizeof m);
            data = tmp;
            dlen = sizeof m;
        } else if (t && t->kind == C_INT_TO_BYTE && dlen >= sizeof(int)) {
            tmp[0] = (uint8_t) * (const int *)data;
            data = tmp;
            dlen = 1;
        }
        size_t need = MAC_CMSG_HDR + dlen;
        if (!t || used + need > room) {
            *truncated = 1;
            if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS)
                for (size_t i = 0; i + sizeof(int) <= dlen; i += sizeof(int))
                    close(*(const int *)(data + i));
            continue;
        }
        struct mac_cmsghdr *m = (void *)(mac + used);
        m->len = (uint32_t)need;
        m->level = t->mlevel;
        m->type = t->mtype;
        memcpy(mac + used + MAC_CMSG_HDR, data, dlen);
        size_t space = MAC_ALIGN(need);
        if (space > need && used + space <= room)
            memset(mac + used + need, 0, space - need);
        used += space > room - used ? room - used : space;
    }
    return used;
}

static ssize_t mac_sendmsg(int s, const struct mac_msghdr *mm, int flags)
{
    if (!mm) {
        errno = EFAULT;
        return -1;
    }
    struct sockaddr_storage a;
    socklen_t alen = 0;
    if (mm->name && mm->namelen && addr_in(mm->name, mm->namelen, &a, &alen) < 0)
        return -1;
    size_t room = mm->controllen * 2 + 64;
    uint8_t *control = mm->controllen ? calloc(1, room) : NULL;
    ssize_t clen = 0;
    if (control && (clen = control_in(mm->control, mm->controllen, control, room)) < 0) {
        free(control);
        return -1;
    }
    struct msghdr lm = {.msg_name = alen ? &a : NULL, .msg_namelen = alen, .msg_iov = mm->iov,
                        .msg_iovlen = mm->iovlen > 0 ? (size_t)mm->iovlen : 0,
                        .msg_control = clen ? control : NULL, .msg_controllen = (size_t)clen};
    ssize_t n = sendmsg(s, &lm, send_flags(s, flags));
    free(control);
    return n;
}

static ssize_t mac_recvmsg(int s, struct mac_msghdr *mm, int flags)
{
    if (!mm) {
        errno = EFAULT;
        return -1;
    }
    struct sockaddr_storage a;
    size_t room = mm->controllen ? mm->controllen * 2 + 64 : 0;
    uint8_t *control = room ? calloc(1, room) : NULL;
    struct msghdr lm = {.msg_name = mm->name ? &a : NULL, .msg_namelen = mm->name ? sizeof a : 0,
                        .msg_iov = mm->iov, .msg_iovlen = mm->iovlen > 0 ? (size_t)mm->iovlen : 0,
                        .msg_control = control, .msg_controllen = room};
    ssize_t n = recvmsg(s, &lm, msg_to_linux(s, flags));
    if (n < 0) {
        free(control);
        return n;
    }
    if (mm->name)
        addr_out((struct sockaddr *)&a, lm.msg_namelen, mm->name, &mm->namelen);
    int truncated = 0;
    size_t clen = control ? control_out(&lm, mm->control, mm->controllen, &truncated) : 0;
    mm->controllen = (uint32_t)clen;
    mm->flags = msg_to_mac(lm.msg_flags) | (truncated ? 0x20 /* MSG_CTRUNC */ : 0);
    free(control);
    return n;
}

/* ---- names and addresses ----------------------------------------------------------- */

static int mac_inet_pton(int af, const char *src, void *dst)
{
    int a = ferry_af_to_linux(af);
    if (a != AF_INET && a != AF_INET6) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    return inet_pton(a, src, dst);
}

static const char *mac_inet_ntop(int af, const void *src, char *dst, socklen_t size)
{
    int a = ferry_af_to_linux(af);
    if (a != AF_INET && a != AF_INET6) {
        errno = EAFNOSUPPORT;
        return NULL;
    }
    return inet_ntop(a, src, dst, size);
}

/* getaddrinfo's answers in the Mac's struct addrinfo, each in one block
 * with its address and canonical name. */
struct mac_addrinfo {
    int flags, family, socktype, protocol;
    uint32_t addrlen;
    char *canonname;
    void *addr;
    struct mac_addrinfo *next;
};

static const struct { int mac, lnx; } ai_bits[] = {
    {0x1, AI_PASSIVE}, {0x2, AI_CANONNAME}, {0x4, AI_NUMERICHOST}, {0x1000, AI_NUMERICSERV},
    {0x100, AI_ALL}, {0x200, AI_V4MAPPED}, {0x400, AI_ADDRCONFIG}, {0x800, AI_V4MAPPED},
};

#define MAC_EAI_ADDRFAMILY 1
#define MAC_EAI_AGAIN 2
#define MAC_EAI_BADFLAGS 3
#define MAC_EAI_FAIL 4
#define MAC_EAI_FAMILY 5
#define MAC_EAI_MEMORY 6
#define MAC_EAI_NONAME 8
#define MAC_EAI_SERVICE 9
#define MAC_EAI_SOCKTYPE 10
#define MAC_EAI_SYSTEM 11
#define MAC_EAI_OVERFLOW 14

static int eai_to_mac(int e)
{
    switch (e) {
    case 0: return 0;
    case EAI_BADFLAGS: return MAC_EAI_BADFLAGS;
    case EAI_NONAME: return MAC_EAI_NONAME;
    case EAI_AGAIN: return MAC_EAI_AGAIN;
    case EAI_FAIL: return MAC_EAI_FAIL;
    case EAI_NODATA: return MAC_EAI_NONAME; /* RFC 3493 has no EAI_NODATA, nor does a Mac's getaddrinfo answer it */
    case EAI_FAMILY: return MAC_EAI_FAMILY;
    case EAI_SOCKTYPE: return MAC_EAI_SOCKTYPE;
    case EAI_SERVICE: return MAC_EAI_SERVICE;
    case EAI_ADDRFAMILY: return MAC_EAI_ADDRFAMILY;
    case EAI_MEMORY: return MAC_EAI_MEMORY;
    case EAI_SYSTEM: return MAC_EAI_SYSTEM;
    case EAI_OVERFLOW: return MAC_EAI_OVERFLOW;
    default: return MAC_EAI_FAIL;
    }
}

static const char *mac_gai_strerror(int e)
{
    static const char *const text[] = {
        "Success",
        "Address family for hostname not supported",
        "Temporary failure in name resolution",
        "Invalid value for ai_flags",
        "Non-recoverable failure in name resolution",
        "ai_family not supported",
        "Memory allocation failure",
        "No address associated with hostname",
        "nodename nor servname provided, or not known",
        "servname not supported for ai_socktype",
        "ai_socktype not supported",
        "System error",
        "Invalid value for hints",
        "Resolved protocol is unknown",
        "Argument buffer overflow",
    };
    return e >= 0 && e < (int)(sizeof text / sizeof text[0]) ? text[e] : "Unknown error";
}

static void mac_freeaddrinfo(struct mac_addrinfo *ai)
{
    while (ai) {
        struct mac_addrinfo *next = ai->next;
        free(ai);
        ai = next;
    }
}

static int mac_getaddrinfo(const char *node, const char *service, const struct mac_addrinfo *mh,
                           struct mac_addrinfo **res)
{
    if (!res)
        return MAC_EAI_FAIL;
    *res = NULL;
    struct addrinfo h = {0};
    if (mh) {
        int known = 0;
        for (size_t i = 0; i < sizeof ai_bits / sizeof ai_bits[0]; i++) {
            known |= ai_bits[i].mac;
            if (mh->flags & ai_bits[i].mac)
                h.ai_flags |= ai_bits[i].lnx;
        }
        if (mh->flags & ~known)
            return MAC_EAI_BADFLAGS;
        h.ai_family = ferry_af_to_linux(mh->family);
        if (h.ai_family < 0 || h.ai_family == AF_UNIX)
            return MAC_EAI_FAMILY;
        h.ai_socktype = mh->socktype;
        h.ai_protocol = mh->protocol;
    }
    struct addrinfo *list = NULL;
    int rc = getaddrinfo(node, service, mh ? &h : NULL, &list);
    /* A Mac counts the loopback address as configured: on a machine with
     * nothing else, AI_ADDRCONFIG still finds localhost. */
    if (rc && rc != EAI_SYSTEM && rc != EAI_MEMORY && (h.ai_flags & AI_ADDRCONFIG)) {
        h.ai_flags &= ~AI_ADDRCONFIG;
        rc = getaddrinfo(node, service, &h, &list);
    }
    if (rc)
        return eai_to_mac(rc);
    struct mac_addrinfo **tail = res;
    for (struct addrinfo *a = list; a; a = a->ai_next) {
        /* with no socket type asked for, a Mac answers for streams and datagrams only */
        if (a->ai_socktype == SOCK_RAW && (!mh || !mh->socktype))
            continue;
        size_t clen = a->ai_canonname ? strlen(a->ai_canonname) + 1 : 0;
        struct mac_addrinfo *m = calloc(1, sizeof *m + sizeof(struct sockaddr_storage) + clen);
        if (!m) {
            freeaddrinfo(list);
            mac_freeaddrinfo(*res);
            *res = NULL;
            return MAC_EAI_MEMORY;
        }
        m->flags = mh ? mh->flags : 0;
        m->family = ferry_af_to_mac(a->ai_family);
        m->socktype = a->ai_socktype;
        m->protocol = a->ai_protocol;
        m->addr = m + 1;
        socklen_t alen = sizeof(struct sockaddr_storage);
        addr_out(a->ai_addr, a->ai_addrlen, m->addr, &alen);
        m->addrlen = alen;
        if (clen) {
            m->canonname = (char *)m->addr + sizeof(struct sockaddr_storage);
            memcpy(m->canonname, a->ai_canonname, clen);
        }
        *tail = m;
        tail = &m->next;
    }
    freeaddrinfo(list);
    return *res ? 0 : MAC_EAI_NONAME;
}

static int mac_getnameinfo(const void *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv,
                           socklen_t servlen, int flags)
{
    struct sockaddr_storage a;
    socklen_t alen;
    if (!sa || addr_in(sa, salen, &a, &alen) < 0 || (a.ss_family != AF_INET && a.ss_family != AF_INET6))
        return MAC_EAI_FAMILY;
    int f = (flags & 0x1 ? NI_NOFQDN : 0) | (flags & 0x2 ? NI_NUMERICHOST : 0) | (flags & 0x4 ? NI_NAMEREQD : 0)
          | (flags & 0x8 ? NI_NUMERICSERV : 0) | (flags & 0x10 ? NI_DGRAM : 0);
    return eai_to_mac(getnameinfo((struct sockaddr *)&a, alen, host, hostlen, serv, servlen, f));
}

/* gethostbyname and friends: the same structure, with the Mac's family
 * number; h_errno is a plain variable on a Mac. */
static int mac_h_errno;
static __thread struct hostent host_copy;

static struct hostent *host_out(struct hostent *h)
{
    mac_h_errno = h_errno;
    if (!h)
        return NULL;
    host_copy = *h;
    host_copy.h_addrtype = ferry_af_to_mac(h->h_addrtype);
    return &host_copy;
}

static struct hostent *mac_gethostbyname(const char *name) { return host_out(gethostbyname(name)); }

static struct hostent *mac_gethostbyname2(const char *name, int af)
{
    int a = ferry_af_to_linux(af);
    if (a != AF_INET && a != AF_INET6) {
        errno = EAFNOSUPPORT;
        mac_h_errno = NO_RECOVERY;
        return NULL;
    }
    return host_out(gethostbyname2(name, a));
}

static struct hostent *mac_gethostbyaddr(const void *addr, socklen_t len, int type)
{
    int a = ferry_af_to_linux(type);
    if (a != AF_INET && a != AF_INET6) {
        errno = EAFNOSUPPORT;
        mac_h_errno = NO_RECOVERY;
        return NULL;
    }
    return host_out(gethostbyaddr(addr, len, a));
}

/* ---- interfaces --------------------------------------------------------------------- */

struct mac_ifaddrs {
    struct mac_ifaddrs *next;
    char *name;
    unsigned int flags;
    void *addr, *netmask, *dstaddr;
    void *data;
};

struct mac_sockaddr_dl {
    uint8_t len, family;
    uint16_t index;
    uint8_t type, nlen, alen, slen;
    char data[12];
};

struct mac_if_data {
    uint8_t type, typelen, physical, addrlen, hdrlen, recvquota, xmitquota, unused1;
    uint32_t mtu, metric, baudrate;
    uint32_t ipackets, ierrors, opackets, oerrors, collisions, ibytes, obytes, imcasts, omcasts, iqdrops, noproto;
    uint32_t recvtiming, xmittiming;
    int32_t lastchange_sec, lastchange_usec;
    uint32_t unused2, hwassist, reserved1, reserved2;
};
_Static_assert(sizeof(struct mac_if_data) == 96, "struct if_data");

struct ifnode {
    struct mac_ifaddrs ifa;
    char name[IF_NAMESIZE];
    uint8_t addr[sizeof(struct sockaddr_storage)], mask[sizeof(struct sockaddr_storage)],
        dst[sizeof(struct sockaddr_storage)];
    struct mac_if_data data;
};

static unsigned int ifflags_to_mac(unsigned int f)
{
    return (f & 0x3ff) | (f & IFF_MULTICAST ? 0x8000 : 0);
}

static void *sockaddr_copy(const struct sockaddr *s, uint8_t *buf)
{
    if (!s)
        return NULL;
    socklen_t len = sizeof(struct sockaddr_storage);
    socklen_t have = s->sa_family == AF_INET ? sizeof(struct sockaddr_in)
                   : s->sa_family == AF_INET6 ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_storage);
    addr_out(s, have, buf, &len);
    return buf;
}

/* A link's address as a Mac's sockaddr_dl, and its figures as if_data. */
static void link_entry(struct ifnode *n, const struct ifaddrs *l)
{
    const struct sockaddr_ll *ll = (const void *)l->ifa_addr;
    struct mac_sockaddr_dl *dl = (void *)n->addr;
    size_t nlen = strlen(l->ifa_name);
    int loop = ll->sll_hatype == ARPHRD_LOOPBACK;
    int alen = loop ? 0 : ll->sll_halen > 8 ? 8 : ll->sll_halen;
    dl->family = MAC_AF_LINK;
    dl->index = (uint16_t)ll->sll_ifindex;
    dl->type = ll->sll_hatype == ARPHRD_ETHER ? 0x6 : loop ? 0x18 : ll->sll_hatype == ARPHRD_PPP ? 0x17 : 0x1;
    dl->nlen = (uint8_t)nlen;
    dl->alen = (uint8_t)alen;
    memcpy(dl->data, l->ifa_name, nlen);
    memcpy(dl->data + nlen, ll->sll_addr, alen);
    size_t len = 8 + nlen + alen;
    dl->len = (uint8_t)(len < 20 ? 20 : len);
    n->ifa.addr = dl;
    struct mac_if_data *d = &n->data;
    d->type = dl->type;
    d->addrlen = (uint8_t)alen;
    d->hdrlen = dl->type == 0x6 ? 14 : 0;
    int s = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (s >= 0) {
        struct ifreq r = {0};
        snprintf(r.ifr_name, sizeof r.ifr_name, "%s", l->ifa_name);
        if (ioctl(s, SIOCGIFMTU, &r) == 0)
            d->mtu = (uint32_t)r.ifr_mtu;
        close(s);
    }
    const struct rtnl_link_stats *st = l->ifa_data;
    if (st) {
        d->ipackets = st->rx_packets;
        d->ierrors = st->rx_errors;
        d->opackets = st->tx_packets;
        d->oerrors = st->tx_errors;
        d->collisions = st->collisions;
        d->ibytes = st->rx_bytes;
        d->obytes = st->tx_bytes;
        d->imcasts = st->multicast;
        d->iqdrops = st->rx_dropped;
    }
    n->ifa.data = d;
}

static void mac_freeifaddrs(struct mac_ifaddrs *list)
{
    while (list) {
        struct mac_ifaddrs *next = list->next;
        free(list);
        list = next;
    }
}

/* As on a Mac, each interface's link comes first, then its addresses. */
static int mac_getifaddrs(struct mac_ifaddrs **out)
{
    struct ifaddrs *list;
    if (!out) {
        errno = EINVAL;
        return -1;
    }
    *out = NULL;
    if (getifaddrs(&list) < 0)
        return -1;
    int count = 0;
    for (struct ifaddrs *l = list; l; l = l->ifa_next)
        count++;
    struct ifaddrs **order = calloc(count ? count : 1, sizeof *order);
    char *taken = calloc(count ? count : 1, 1);
    if (!order || !taken) {
        free(order);
        free(taken);
        freeifaddrs(list);
        errno = ENOMEM;
        return -1;
    }
    int n = 0, i = 0;
    struct ifaddrs **all = calloc(count ? count : 1, sizeof *all);
    for (struct ifaddrs *l = list; l; l = l->ifa_next)
        all[i++] = l;
    for (i = 0; i < count; i++) {
        if (!all[i]->ifa_addr || all[i]->ifa_addr->sa_family != AF_PACKET || taken[i])
            continue;
        taken[i] = 1;
        order[n++] = all[i];
        for (int fam = 0; fam < 2; fam++)
            for (int j = 0; j < count; j++)
                if (!taken[j] && all[j]->ifa_addr && !strcmp(all[j]->ifa_name, all[i]->ifa_name) &&
                    all[j]->ifa_addr->sa_family == (fam ? AF_INET6 : AF_INET)) {
                    taken[j] = 1;
                    order[n++] = all[j];
                }
    }
    for (i = 0; i < count; i++)
        if (!taken[i] && all[i]->ifa_addr &&
            (all[i]->ifa_addr->sa_family == AF_INET || all[i]->ifa_addr->sa_family == AF_INET6))
            order[n++] = all[i];
    struct mac_ifaddrs **tail = out;
    for (i = 0; i < n; i++) {
        struct ifaddrs *l = order[i];
        struct ifnode *node = calloc(1, sizeof *node);
        if (!node)
            break;
        snprintf(node->name, sizeof node->name, "%s", l->ifa_name);
        node->ifa.name = node->name;
        node->ifa.flags = ifflags_to_mac(l->ifa_flags);
        if (l->ifa_addr->sa_family == AF_PACKET) {
            link_entry(node, l);
        } else {
            node->ifa.addr = sockaddr_copy(l->ifa_addr, node->addr);
            node->ifa.netmask = sockaddr_copy(l->ifa_netmask, node->mask);
            if (l->ifa_flags & (IFF_BROADCAST | IFF_POINTOPOINT))
                node->ifa.dstaddr = sockaddr_copy(l->ifa_ifu.ifu_broadaddr, node->dst);
        }
        *tail = &node->ifa;
        tail = &node->ifa.next;
    }
    free(all);
    free(order);
    free(taken);
    freeifaddrs(list);
    return 0;
}

/* ---- helpers ------------------------------------------------------------------------ */

/* Newer Mac headers' FD_SET and FD_ISSET check the descriptor fits the set. */
static int mac_check_fd_set_overflow(int fd, const void *set, int unlimited)
{
    (void)set;
    return fd >= 0 && (unlimited || fd < 1024);
}

const struct ferry_symbol ferry_socket_symbols[] = {
    {"socket", mac_socket},
    {"socketpair", mac_socketpair},
    {"bind", mac_bind},
    {"connect", mac_connect},
    {"listen", listen},
    {"accept", mac_accept},
    {"getsockname", mac_getsockname},
    {"getpeername", mac_getpeername},
    {"getpeereid", mac_getpeereid},
    {"setsockopt", mac_setsockopt},
    {"getsockopt", mac_getsockopt},
    {"send", mac_send},
    {"recv", mac_recv},
    {"sendto", mac_sendto},
    {"recvfrom", mac_recvfrom},
    {"sendmsg", mac_sendmsg},
    {"recvmsg", mac_recvmsg},
    {"shutdown", shutdown},
    {"sockatmark", sockatmark},
    {"write", mac_write},
    {"writev", mac_writev},
    {"inet_pton", mac_inet_pton},
    {"inet_ntop", mac_inet_ntop},
    {"inet_addr", inet_addr},
    {"inet_aton", inet_aton},
    {"inet_ntoa", inet_ntoa},
    {"inet_network", inet_network},
    {"in6addr_any", (void *)&in6addr_any},
    {"in6addr_loopback", (void *)&in6addr_loopback},
    {"getaddrinfo", mac_getaddrinfo},
    {"freeaddrinfo", mac_freeaddrinfo},
    {"gai_strerror", mac_gai_strerror},
    {"getnameinfo", mac_getnameinfo},
    {"gethostbyname", mac_gethostbyname},
    {"gethostbyname2", mac_gethostbyname2},
    {"gethostbyaddr", mac_gethostbyaddr},
    {"h_errno", &mac_h_errno},
    {"hstrerror", hstrerror},
    {"herror", herror},
    {"getservbyname", getservbyname},
    {"getservbyport", getservbyport},
    {"getprotobyname", getprotobyname},
    {"getprotobynumber", getprotobynumber},
    {"if_nametoindex", if_nametoindex},
    {"if_indextoname", if_indextoname},
    {"if_nameindex", if_nameindex},
    {"if_freenameindex", if_freenameindex},
    {"getifaddrs", mac_getifaddrs},
    {"freeifaddrs", mac_freeifaddrs},
    {"__darwin_check_fd_set_overflow", mac_check_fd_set_overflow},
    {NULL, NULL},
};
