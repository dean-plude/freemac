/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A server's certificates, for Ferry's Security framework. When a program's
 * URL session is asked to judge an https server (a challenge of the kind
 * NSURLAuthenticationMethodServerTrust) and looks at the server's trust
 * object, the Security framework needs the certificates the server
 * presents. Foundation asks before it connects, so they are fetched here:
 * a TLS handshake with this system's libssl (looked up through
 * ferry_crypto_symbol, so programs that never do this don't load it),
 * after which the connection is closed without sending anything. Nothing
 * is checked here; the Security framework checks what comes back.
 *
 * The connection is made directly, never through a proxy, and gives up
 * after timeout_ms. OpenSSL's calls are written from its public API
 * documentation.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <time.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <unistd.h>

#include "ferry.h"

typedef void SSL_CTX;
typedef void SSL;
typedef void SSL_METHOD;
typedef void X509;
typedef void STACK;

static int connect_with_timeout(const char *host, int port, int timeout_ms)
{
    char service[16];
    snprintf(service, sizeof service, "%d", port);
    struct addrinfo hints = {.ai_socktype = SOCK_STREAM}, *list = NULL;
    if (getaddrinfo(host, service, &hints, &list) != 0)
        return -1;
    int fd = -1;
    for (struct addrinfo *a = list; a && fd < 0; a = a->ai_next) {
        fd = socket(a->ai_family, a->ai_socktype | SOCK_CLOEXEC | SOCK_NONBLOCK, a->ai_protocol);
        if (fd < 0)
            continue;
        if (connect(fd, a->ai_addr, a->ai_addrlen) == 0)
            break;
        if (errno == EINPROGRESS) {
            struct pollfd p = {.fd = fd, .events = POLLOUT};
            int err = 0;
            socklen_t len = sizeof err;
            if (poll(&p, 1, timeout_ms) == 1 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && !err)
                break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(list);
    if (fd >= 0) {
        /* blocking again, for libssl, with the time limit on each read and write */
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
        struct timeval tv = {timeout_ms / 1000, (timeout_ms % 1000) * 1000};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    }
    return fd;
}

/* Calls `each` with every certificate the server sent (DER, its own first),
 * and returns how many, or -1 if there was no handshake. */
int ferry_server_certificates(const char *host, int port, int timeout_ms,
                              void (*each)(void *ctx, const unsigned char *der, size_t len), void *ctx)
{
    static struct {
        int loaded, ok;
        const SSL_METHOD *(*client_method)(void);
        SSL_CTX *(*ctx_new)(const SSL_METHOD *);
        void (*ctx_free)(SSL_CTX *);
        SSL *(*ssl_new)(SSL_CTX *);
        void (*ssl_free)(SSL *);
        int (*set_fd)(SSL *, int);
        long (*ctrl)(SSL *, int, long, void *);
        int (*connect)(SSL *);
        STACK *(*peer_chain)(const SSL *);
        int (*shutdown)(SSL *);
        int (*sk_num)(const STACK *);
        void *(*sk_value)(const STACK *, int);
        int (*i2d)(X509 *, unsigned char **);
        void (*free_mem)(void *, const char *, int);
    } S;
    static pthread_mutex_t load_lock = PTHREAD_MUTEX_INITIALIZER; /* the first threads to ask wait for the loading */
    pthread_mutex_lock(&load_lock);
    if (!S.loaded) {
        S.loaded = 1;
#define GET(field, name) (*(void **)&S.field = ferry_crypto_symbol(name))
        S.ok = GET(client_method, "TLS_client_method") && GET(ctx_new, "SSL_CTX_new") &&
               GET(ctx_free, "SSL_CTX_free") && GET(ssl_new, "SSL_new") && GET(ssl_free, "SSL_free") &&
               GET(set_fd, "SSL_set_fd") && GET(ctrl, "SSL_ctrl") && GET(connect, "SSL_connect") &&
               GET(peer_chain, "SSL_get_peer_cert_chain") && GET(shutdown, "SSL_shutdown") &&
               GET(sk_num, "OPENSSL_sk_num") && GET(sk_value, "OPENSSL_sk_value") && GET(i2d, "i2d_X509") &&
               GET(free_mem, "CRYPTO_free");
#undef GET
    }
    pthread_mutex_unlock(&load_lock);
    if (!S.ok || !host || !*host || port <= 0 || port > 65535 || !each)
        return -1;
    int fd = connect_with_timeout(host, port, timeout_ms > 0 ? timeout_ms : 10000);
    if (fd < 0)
        return -1;
    /* a server that hangs up mid-handshake mustn't stop the program with SIGPIPE */
    sigset_t pipe_only, before, pending;
    sigemptyset(&pipe_only);
    sigaddset(&pipe_only, SIGPIPE);
    sigpending(&pending);
    int was_pending = sigismember(&pending, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &pipe_only, &before);
    int count = -1;
    SSL_CTX *sctx = S.ctx_new(S.client_method());
    SSL *ssl = sctx ? S.ssl_new(sctx) : NULL;
    if (ssl && S.set_fd(ssl, fd) == 1) {
        /* the server's name, unless it is an address (SSL_set_tlsext_host_name) */
        unsigned char addr[16];
        if (inet_pton(AF_INET, host, addr) != 1 && inet_pton(AF_INET6, host, addr) != 1)
            S.ctrl(ssl, 55 /* SSL_CTRL_SET_TLSEXT_HOSTNAME */, 0 /* TLSEXT_NAMETYPE_host_name */, (void *)host);
        if (S.connect(ssl) == 1) {
            STACK *chain = S.peer_chain(ssl);
            count = 0;
            for (int i = 0; chain && i < S.sk_num(chain); i++) {
                unsigned char *der = NULL;
                int len = S.i2d(S.sk_value(chain, i), &der);
                if (len > 0 && der) {
                    each(ctx, der, (size_t)len);
                    count++;
                }
                if (der)
                    S.free_mem(der, __FILE__, __LINE__);
            }
            S.shutdown(ssl);
        }
    }
    if (ssl)
        S.ssl_free(ssl);
    if (sctx)
        S.ctx_free(sctx);
    close(fd);
    sigpending(&pending);
    if (!was_pending && sigismember(&pending, SIGPIPE)) {
        struct timespec none = {0, 0};
        sigtimedwait(&pipe_only, NULL, &none);
    }
    pthread_sigmask(SIG_SETMASK, &before, NULL);
    return count;
}
