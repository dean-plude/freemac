/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _TIME_H_
#define _TIME_H_
#include <_ferry.h>
__FERRY_BEGIN
struct timespec { time_t tv_sec; long tv_nsec; };
struct tm {
    int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst;
    long tm_gmtoff;
    char *tm_zone;
};
#define CLOCKS_PER_SEC 1000000
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC_RAW 4
#define CLOCK_MONOTONIC 6
#define CLOCK_UPTIME_RAW 8
#define CLOCK_PROCESS_CPUTIME_ID 12
#define CLOCK_THREAD_CPUTIME_ID 16
time_t time(time_t *);
double difftime(time_t, time_t);
time_t mktime(struct tm *);
time_t timegm(struct tm *);
struct tm *localtime(const time_t *);
struct tm *localtime_r(const time_t *, struct tm *);
struct tm *gmtime(const time_t *);
struct tm *gmtime_r(const time_t *, struct tm *);
char *asctime(const struct tm *);
char *ctime(const time_t *);
size_t strftime(char *, size_t, const char *, const struct tm *);
char *strptime(const char *, const char *, struct tm *);
clock_t clock(void);
int nanosleep(const struct timespec *, struct timespec *);
int clock_gettime(clockid_t, struct timespec *);
int clock_getres(clockid_t, struct timespec *);
uint64_t clock_gettime_nsec_np(clockid_t);
void tzset(void);
/* what tzset sets (freemac 1.232, Ferry 0.56.0) */
extern char *tzname[2];
extern long timezone;
extern int daylight;
__FERRY_END
#endif
