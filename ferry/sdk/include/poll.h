/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _POLL_H_
#define _POLL_H_
#include <_ferry.h>
__FERRY_BEGIN
struct pollfd {
    int fd;
    short events, revents;
};
typedef unsigned int nfds_t;
#define POLLIN 0x0001
#define POLLPRI 0x0002
#define POLLOUT 0x0004
#define POLLRDNORM 0x0040
#define POLLWRNORM POLLOUT
#define POLLRDBAND 0x0080
#define POLLWRBAND 0x0100
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
__FERRY_END
#endif
