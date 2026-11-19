/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Error numbers. Linux and macOS agree on 1-34 except EAGAIN/EDEADLK and
 * number everything after that differently. A Mac program reads errno through
 * __error(), which returns a per-thread int holding the Mac number.
 *
 * Library calls set the Linux errno. Each time the program asks for errno we
 * move any new Linux value across and reset the Linux one to 0, so the next
 * failure is seen even when it carries the same number.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "ferry.h"

/* {linux, mac} for every number that differs. */
static const int pairs[][2] = {
    {EAGAIN, 35}, {EDEADLK, 11}, {EINPROGRESS, 36}, {EALREADY, 37}, {ENOTSOCK, 38},
    {EDESTADDRREQ, 39}, {EMSGSIZE, 40}, {EPROTOTYPE, 41}, {ENOPROTOOPT, 42},
    {EPROTONOSUPPORT, 43}, {ESOCKTNOSUPPORT, 44}, {ENOTSUP, 45}, {EPFNOSUPPORT, 46},
    {EAFNOSUPPORT, 47}, {EADDRINUSE, 48}, {EADDRNOTAVAIL, 49}, {ENETDOWN, 50},
    {ENETUNREACH, 51}, {ENETRESET, 52}, {ECONNABORTED, 53}, {ECONNRESET, 54},
    {ENOBUFS, 55}, {EISCONN, 56}, {ENOTCONN, 57}, {ESHUTDOWN, 58}, {ETOOMANYREFS, 59},
    {ETIMEDOUT, 60}, {ECONNREFUSED, 61}, {ELOOP, 62}, {ENAMETOOLONG, 63}, {EHOSTDOWN, 64},
    {EHOSTUNREACH, 65}, {ENOTEMPTY, 66}, {EUSERS, 68}, {EDQUOT, 69}, {ESTALE, 70},
    {EREMOTE, 71}, {ENOLCK, 77}, {ENOSYS, 78}, {EOVERFLOW, 84}, {ECANCELED, 89},
    {EIDRM, 90}, {ENOMSG, 91}, {EILSEQ, 92}, {EBADMSG, 94}, {EMULTIHOP, 95},
    {ENODATA, 96}, {ENOLINK, 97}, {ENOSR, 98}, {ENOSTR, 99}, {EPROTO, 100}, {ETIME, 101},
    {ENOTRECOVERABLE, 104}, {EOWNERDEAD, 105},
};
#define NPAIRS (sizeof pairs / sizeof pairs[0])

int ferry_errno_to_mac(int e)
{
    if (e <= 0)
        return e;
    for (size_t i = 0; i < NPAIRS; i++)
        if (pairs[i][0] == e)
            return pairs[i][1];
    return e <= 34 ? e : 5; /* anything unknown reads as EIO */
}

int ferry_errno_to_linux(int e)
{
    if (e <= 0)
        return e;
    for (size_t i = 0; i < NPAIRS; i++)
        if (pairs[i][1] == e)
            return pairs[i][0];
    return e <= 34 ? e : EIO;
}

static __thread int mac_errno;

void ferry_sync_errno(void)
{
    if (errno) {
        mac_errno = ferry_errno_to_mac(errno);
        errno = 0;
    }
}

int *mac_error(void)
{
    ferry_sync_errno();
    return &mac_errno;
}

char *mac_strerror(int e)
{
    return strerror(ferry_errno_to_linux(e));
}

int mac_strerror_r(int e, char *buf, size_t len)
{
    const char *text = strerror(ferry_errno_to_linux(e));
    if (!buf || !len)
        return 34; /* ERANGE */
    snprintf(buf, len, "%s", text);
    return strlen(text) >= len ? 34 : 0;
}

void mac_perror(const char *prefix)
{
    ferry_sync_errno();
    const char *text = strerror(ferry_errno_to_linux(mac_errno));
    if (prefix && *prefix)
        fprintf(stderr, "%s: %s\n", prefix, text);
    else
        fprintf(stderr, "%s\n", text);
}
