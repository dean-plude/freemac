/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_TIME_H_
#define _SYS_TIME_H_
#include <_ferry.h>
#include <time.h>
__FERRY_BEGIN
struct timeval { time_t tv_sec; suseconds_t tv_usec; };
struct timezone { int tz_minuteswest, tz_dsttime; };
int gettimeofday(struct timeval *, void *);
/* freemac 1.224 */
/* braces, as on a Mac, where callers may leave out the semicolon */
#define TIMEVAL_TO_TIMESPEC(tv, ts) { (ts)->tv_sec = (tv)->tv_sec; (ts)->tv_nsec = (tv)->tv_usec * 1000; }
#define TIMESPEC_TO_TIMEVAL(tv, ts) \
    { (tv)->tv_sec = (ts)->tv_sec; (tv)->tv_usec = (suseconds_t)((ts)->tv_nsec / 1000); }
int utimes(const char *, const struct timeval[2]);
int futimes(int, const struct timeval[2]);
int lutimes(const char *, const struct timeval[2]);
__FERRY_END
/* fd_set and select(), which a Mac's <sys/time.h> gives too (libcurl's
   headers count on it) */
#include <sys/select.h>
#endif
