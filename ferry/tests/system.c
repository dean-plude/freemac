/* Ferry test: clocks, system information, getopt, locale, assert. */
#include <assert.h>
#include <ctype.h>
#include <getopt.h>
#include <locale.h>
#include <mach/mach_time.h>
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    usleep(2000);
    clock_gettime(CLOCK_MONOTONIC, &b);
    long ms = (b.tv_sec - a.tv_sec) * 1000 + (b.tv_nsec - a.tv_nsec) / 1000000;
    printf("monotonic moved >=2ms %d\n", ms >= 2);
    uint64_t t0 = mach_absolute_time();
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    printf("mach time ok %d\n", mach_absolute_time() > t0 && tb.denom > 0);
    struct timeval tv;
    gettimeofday(&tv, NULL);
    printf("gettimeofday sane %d\n", tv.tv_sec > 1700000000 && tv.tv_usec < 1000000);

    struct utsname u;
    uname(&u);
    printf("sysname=%s machine=%s\n", u.sysname, u.machine);
    printf("pagesize=%ld cpus>0 %d\n", sysconf(_SC_PAGESIZE), sysconf(_SC_NPROCESSORS_ONLN) > 0);
    struct rlimit rl;
    printf("rlimit ok %d\n", getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur > 0);
    struct passwd *pw = getpwuid(getuid());
    printf("passwd ok %d\n", pw && pw->pw_name && pw->pw_dir);
    printf("locale %s\n", setlocale(LC_ALL, "C") ? "set" : "failed");

    time_t when = 86400 * 365;
    struct tm tm;
    gmtime_r(&when, &tm);
    char date[32];
    strftime(date, sizeof date, "%Y-%m-%d %H:%M", &tm);
    printf("strftime %s\n", date);

    printf("ctype %d%d%d%d\n", isdigit('7') != 0, isalpha('q') != 0, isspace('x') != 0, toupper('m'));

    int opt, aflag = 0;
    const char *bval = "";
    while ((opt = getopt(argc, argv, "ab:")) != -1) {
        if (opt == 'a') aflag = 1;
        else if (opt == 'b') bval = optarg;
    }
    printf("getopt a=%d b=%s rest=%s\n", aflag, bval, optind < argc ? argv[optind] : "-");

    assert(1 + 1 == 2);
    printf("assert passed\n");
    return 0;
}
