/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * BSD sockets as a Mac lays them out: every address starts with its length
 * and a one-byte family, and the option levels, option names and flags are
 * the Mac's numbers; Ferry converts them to this system's. Written from the
 * socket(2), getsockopt(2), send(2) and recv(2) reference pages. */
#ifndef _SYS_SOCKET_H_
#define _SYS_SOCKET_H_
#include <_ferry.h>
#include <sys/uio.h>
__FERRY_BEGIN
typedef uint32_t socklen_t;
typedef uint8_t sa_family_t;

#define SOCK_STREAM 1
#define SOCK_DGRAM 2
#define SOCK_RAW 3
#define SOCK_RDM 4
#define SOCK_SEQPACKET 5

#define AF_UNSPEC 0
#define AF_UNIX 1
#define AF_LOCAL AF_UNIX
#define AF_INET 2
#define AF_ROUTE 17
#define AF_LINK 18
#define AF_INET6 30
#define AF_SYSTEM 32
#define AF_MAX 41
#define PF_UNSPEC AF_UNSPEC
#define PF_UNIX AF_UNIX
#define PF_LOCAL AF_LOCAL
#define PF_INET AF_INET
#define PF_ROUTE AF_ROUTE
#define PF_LINK AF_LINK
#define PF_INET6 AF_INET6

#define SOL_SOCKET 0xffff
#define SO_DEBUG 0x0001
#define SO_ACCEPTCONN 0x0002
#define SO_REUSEADDR 0x0004
#define SO_KEEPALIVE 0x0008
#define SO_DONTROUTE 0x0010
#define SO_BROADCAST 0x0020
#define SO_USELOOPBACK 0x0040
#define SO_LINGER 0x0080
#define SO_OOBINLINE 0x0100
#define SO_REUSEPORT 0x0200
#define SO_TIMESTAMP 0x0400
#define SO_TIMESTAMP_MONOTONIC 0x0800
#define SO_SNDBUF 0x1001
#define SO_RCVBUF 0x1002
#define SO_SNDLOWAT 0x1003
#define SO_RCVLOWAT 0x1004
#define SO_SNDTIMEO 0x1005
#define SO_RCVTIMEO 0x1006
#define SO_ERROR 0x1007
#define SO_TYPE 0x1008
#define SO_NREAD 0x1020
#define SO_NKE 0x1021
#define SO_NOSIGPIPE 0x1022
#define SO_NOADDRERR 0x1023
#define SO_NWRITE 0x1024
#define SO_REUSESHAREUID 0x1025
#define SO_LINGER_SEC 0x1080
#define SO_RANDOMPORT 0x1082
#define SO_NP_EXTENSIONS 0x1083
#define SO_NUMRCVPKT 0x1112
#define SO_NET_SERVICE_TYPE 0x1116

#define SOL_LOCAL 0
#define LOCAL_PEERCRED 0x001
#define LOCAL_PEERPID 0x002
#define LOCAL_PEEREPID 0x003
#define XUCRED_VERSION 0
struct xucred {
    unsigned int cr_version;
    uid_t cr_uid;
    short cr_ngroups;
    gid_t cr_groups[16];
};

#define SOMAXCONN 128

#define MSG_OOB 0x1
#define MSG_PEEK 0x2
#define MSG_DONTROUTE 0x4
#define MSG_EOR 0x8
#define MSG_TRUNC 0x10
#define MSG_CTRUNC 0x20
#define MSG_WAITALL 0x40
#define MSG_DONTWAIT 0x80
#define MSG_EOF 0x100
#define MSG_NOSIGNAL 0x80000

#define SHUT_RD 0
#define SHUT_WR 1
#define SHUT_RDWR 2

#define SCM_RIGHTS 0x01
#define SCM_TIMESTAMP 0x02
#define SCM_CREDS 0x03
#define SCM_TIMESTAMP_MONOTONIC 0x04

struct sockaddr {
    uint8_t sa_len;
    sa_family_t sa_family;
    char sa_data[14];
};
#define _SS_MAXSIZE 128
struct sockaddr_storage {
    uint8_t ss_len;
    sa_family_t ss_family;
    char __ss_pad1[6];
    int64_t __ss_align;
    char __ss_pad2[112];
};
struct linger { int l_onoff, l_linger; };
struct msghdr {
    void *msg_name;
    socklen_t msg_namelen;
    struct iovec *msg_iov;
    int msg_iovlen;
    void *msg_control;
    socklen_t msg_controllen;
    int msg_flags;
};
struct cmsghdr {
    socklen_t cmsg_len;
    int cmsg_level;
    int cmsg_type;
};
/* control messages are aligned to four bytes */
#define __FERRY_ALIGN32(p) (((size_t)(p) + 3) & ~(size_t)3)
#define CMSG_DATA(c) ((unsigned char *)(c) + __FERRY_ALIGN32(sizeof(struct cmsghdr)))
#define CMSG_SPACE(l) (__FERRY_ALIGN32(sizeof(struct cmsghdr)) + __FERRY_ALIGN32(l))
#define CMSG_LEN(l) (__FERRY_ALIGN32(sizeof(struct cmsghdr)) + (l))
#define CMSG_FIRSTHDR(m) \
    ((m)->msg_controllen >= sizeof(struct cmsghdr) ? (struct cmsghdr *)(m)->msg_control : (struct cmsghdr *)0)
#define CMSG_NXTHDR(m, c)                                                                                       \
    ((c) == 0 ? CMSG_FIRSTHDR(m)                                                                                \
     : (unsigned char *)(c) + __FERRY_ALIGN32((c)->cmsg_len) + __FERRY_ALIGN32(sizeof(struct cmsghdr)) >      \
             (unsigned char *)(m)->msg_control + (m)->msg_controllen                                            \
         ? (struct cmsghdr *)0                                                                                  \
         : (struct cmsghdr *)(void *)((unsigned char *)(c) + __FERRY_ALIGN32((c)->cmsg_len)))

int socket(int domain, int type, int protocol);
int socketpair(int domain, int type, int protocol, int sv[2]);
int bind(int s, const struct sockaddr *addr, socklen_t len);
int connect(int s, const struct sockaddr *addr, socklen_t len);
int listen(int s, int backlog);
int accept(int s, struct sockaddr *addr, socklen_t *len);
int getsockname(int s, struct sockaddr *addr, socklen_t *len);
int getpeername(int s, struct sockaddr *addr, socklen_t *len);
int setsockopt(int s, int level, int name, const void *value, socklen_t len);
int getsockopt(int s, int level, int name, void *value, socklen_t *len);
ssize_t send(int s, const void *buf, size_t len, int flags);
ssize_t recv(int s, void *buf, size_t len, int flags);
ssize_t sendto(int s, const void *buf, size_t len, int flags, const struct sockaddr *to, socklen_t tolen);
ssize_t recvfrom(int s, void *buf, size_t len, int flags, struct sockaddr *from, socklen_t *fromlen);
ssize_t sendmsg(int s, const struct msghdr *msg, int flags);
ssize_t recvmsg(int s, struct msghdr *msg, int flags);
int shutdown(int s, int how);
int getpeereid(int s, uid_t *uid, gid_t *gid);
__FERRY_END
#endif
