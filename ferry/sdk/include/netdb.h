/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Name lookups (getaddrinfo(3), getnameinfo(3), gethostbyname(3)) with the
 * Mac's structure layouts (ai_canonname comes before ai_addr) and numbers. */
#ifndef _NETDB_H_
#define _NETDB_H_
#include <sys/socket.h>
#include <netinet/in.h>
__FERRY_BEGIN
struct addrinfo {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    socklen_t ai_addrlen;
    char *ai_canonname;
    struct sockaddr *ai_addr;
    struct addrinfo *ai_next;
};
struct hostent {
    char *h_name;
    char **h_aliases;
    int h_addrtype;
    int h_length;
    char **h_addr_list;
};
#define h_addr h_addr_list[0]
struct servent {
    char *s_name;
    char **s_aliases;
    int s_port;
    char *s_proto;
};
struct protoent {
    char *p_name;
    char **p_aliases;
    int p_proto;
};

#define AI_PASSIVE 0x00000001
#define AI_CANONNAME 0x00000002
#define AI_NUMERICHOST 0x00000004
#define AI_NUMERICSERV 0x00001000
#define AI_ALL 0x00000100
#define AI_V4MAPPED_CFG 0x00000200
#define AI_ADDRCONFIG 0x00000400
#define AI_V4MAPPED 0x00000800
#define AI_DEFAULT (AI_V4MAPPED_CFG | AI_ADDRCONFIG)

#define EAI_ADDRFAMILY 1
#define EAI_AGAIN 2
#define EAI_BADFLAGS 3
#define EAI_FAIL 4
#define EAI_FAMILY 5
#define EAI_MEMORY 6
#define EAI_NODATA 7
#define EAI_NONAME 8
#define EAI_SERVICE 9
#define EAI_SOCKTYPE 10
#define EAI_SYSTEM 11
#define EAI_BADHINTS 12
#define EAI_PROTOCOL 13
#define EAI_OVERFLOW 14

#define NI_MAXHOST 1025
#define NI_MAXSERV 32
#define NI_NOFQDN 0x00000001
#define NI_NUMERICHOST 0x00000002
#define NI_NAMEREQD 0x00000004
#define NI_NUMERICSERV 0x00000008
#define NI_DGRAM 0x00000010
#define NI_WITHSCOPEID 0x00000020
#define NI_NUMERICSCOPE 0x00000100

#define HOST_NOT_FOUND 1
#define TRY_AGAIN 2
#define NO_RECOVERY 3
#define NO_DATA 4
#define NO_ADDRESS NO_DATA
extern int h_errno;

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *ai);
const char *gai_strerror(int code);
int getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv,
                socklen_t servlen, int flags);
struct hostent *gethostbyname(const char *name);
struct hostent *gethostbyname2(const char *name, int af);
struct hostent *gethostbyaddr(const void *addr, socklen_t len, int type);
const char *hstrerror(int err);
void herror(const char *s);
struct servent *getservbyname(const char *name, const char *proto);
struct servent *getservbyport(int port, const char *proto);
struct protoent *getprotobyname(const char *name);
struct protoent *getprotobynumber(int proto);
__FERRY_END
#endif
