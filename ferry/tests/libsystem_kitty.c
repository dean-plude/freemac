/* SPDX-License-Identifier: GPL-3.0-or-later
 * What kitty, a terminal, and its helper kitten, a Go program, ask of
 * libSystem (freemac 1.269): main's argv, environment and apple strings one
 * after the other, as Go's runtime reads them; a signal handler's Mac
 * machine context, whose registers it can read and change; sigaltstack in
 * a Mac's layout; faccessat and fchmodat with a Mac's AT_ numbers; an XPC
 * date; /usr/bin/login started as a terminal starts a shell; and a Mac
 * app's hex-named terminfo folders made readable to this system's
 * programs. */
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { void *sp; size_t size; int flags; } mac_stack_t;
int sigaltstack(const mac_stack_t *, mac_stack_t *);
int faccessat(int, const char *, int, int);
int fchmodat(int, const char *, mode_t, int);
void *xpc_date_create_from_current(void);
void *xpc_date_create(int64_t);
int64_t xpc_date_get_value(void *);
void xpc_release(void *);
int execv(const char *, char *const[]);

struct mc64 { uint16_t trapno, cpu; uint32_t err; uint64_t faultvaddr; uint64_t r[21]; };
struct uctx { int32_t onstack; uint32_t sigmask; mac_stack_t stack; void *link; uint64_t mcsize; struct mc64 *mc; };

static volatile int got;
static volatile uint64_t seen_rip, seen_rsp;
static void on_usr1(int sig, siginfo_t *info, void *ctx)
{
    struct uctx *uc = ctx;
    got = sig;
    if (uc && uc->mc) {
        seen_rip = uc->mc->r[16];
        seen_rsp = uc->mc->r[7];
    }
}

static int line_of(const char *path, char *out, size_t n)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    out[0] = 0;
    if (!fgets(out, (int)n, f))
        out[0] = 0;
    fclose(f);
    out[strcspn(out, "\n")] = 0;
    return 0;
}

int main(int argc, char **argv, char **envp, char **apple)
{
    /* argv, envp and apple lie one after the other */
    printf("envp follows argv: %s\n", envp == argv + argc + 1 ? "yes" : "no");
    int n = 0;
    while (envp[n])
        n++;
    printf("apple follows envp: %s\n", apple == envp + n + 1 ? "yes" : "no");
    printf("executable_path given: %s\n", apple[0] && !strncmp(apple[0], "executable_path=", 16) ? "yes" : "no");

    /* a handler with SA_SIGINFO gets a Mac machine context */
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_usr1;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGUSR1, &sa, NULL);
    raise(SIGUSR1);
    printf("handler ran: %s, with registers: %s\n", got == SIGUSR1 ? "yes" : "no",
           seen_rip && seen_rsp ? "yes" : "no");

    /* sigaltstack: none at first, then the one set */
    mac_stack_t old, ss = {malloc(65536), 65536, 0};
    int r1 = sigaltstack(NULL, &old);
    int r2 = sigaltstack(&ss, NULL);
    mac_stack_t now;
    sigaltstack(NULL, &now);
    printf("alt stack: first disabled %s, then set %s\n", r1 == 0 && (old.flags & 4) ? "yes" : "no",
           r2 == 0 && now.sp == ss.sp && now.size == 65536 && !(now.flags & 4) ? "yes" : "no");

    /* faccessat and fchmodat with the Mac's AT_FDCWD (-2) */
    char path[] = "/tmp/ferry-kitty-XXXXXX";
    int fd = mkstemp(path);
    close(fd);
    printf("faccessat: %d, missing: %d\n", faccessat(-2, path, R_OK, 0),
           faccessat(-2, "/nonexistent/x", R_OK, 0) < 0 && errno == ENOENT ? -1 : 0);
    struct stat st;
    fchmodat(-2, path, 0640, 0);
    stat(path, &st);
    printf("fchmodat: %o\n", st.st_mode & 0777);
    unlink(path);

    /* an XPC date */
    void *d = xpc_date_create(1234567890123LL);
    void *now_d = xpc_date_create_from_current();
    printf("xpc date: %lld, current after 2020: %s\n", (long long)xpc_date_get_value(d),
           xpc_date_get_value(now_d) > 1577836800LL * 1000000000LL ? "yes" : "no");
    xpc_release(d);
    xpc_release(now_d);

    /* login -f -l -p USER PROGRAM ARGS, as kitty starts its shell */
    struct passwd *pw = getpwuid(getuid());
    char out[] = "/tmp/ferry-login-XXXXXX";
    close(mkstemp(out));
    char cmd[512];
    snprintf(cmd, sizeof cmd, "echo \"$USER $KEEP\" > %s", out);
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        setenv("KEEP", "kept", 1);
        char *av[] = {"login", "-f", "-l", "-p", pw->pw_name, "/bin/sh", "-c", cmd, NULL};
        execv("/usr/bin/login", av);
        _exit(99);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    char line[256];
    line_of(out, line, sizeof line);
    char want[256];
    snprintf(want, sizeof want, "%s kept", pw->pw_name);
    printf("login ran the program: %s, environment kept: %s\n",
           WIFEXITED(status) && WEXITSTATUS(status) == 0 ? "yes" : "no", !strcmp(line, want) ? "yes" : "no");

    /* someone else's account is refused */
    fflush(stdout);
    pid = fork();
    if (pid == 0) {
        char *av[] = {"login", "-f", "nobody-ferry-test", "/bin/true", NULL};
        execv("/usr/bin/login", av);
        _exit(errno == EPERM ? 3 : 4);
    }
    waitpid(pid, &status, 0);
    printf("another user refused: %s\n", WIFEXITED(status) && WEXITSTATUS(status) == 3 ? "yes" : "no");

    /* a Mac app's terminfo ("78/xterm-test") reaches this system's programs */
    char ti[] = "/tmp/ferry-terminfo-XXXXXX";
    mkdtemp(ti);
    char sub[300], entry[340];
    snprintf(sub, sizeof sub, "%s/78", ti);
    mkdir(sub, 0755);
    snprintf(entry, sizeof entry, "%s/xterm-test", sub);
    FILE *f = fopen(entry, "w");
    fputs("entry\n", f);
    fclose(f);
    snprintf(cmd, sizeof cmd, "cat \"$TERMINFO/x/xterm-test\" > %s", out);
    fflush(stdout);
    pid = fork();
    if (pid == 0) {
        setenv("TERMINFO", ti, 1);
        char *av[] = {"sh", "-c", cmd, NULL};
        execv("/bin/sh", av);
        _exit(99);
    }
    waitpid(pid, &status, 0);
    line_of(out, line, sizeof line);
    printf("terminfo entry found by letter: %s\n", !strcmp(line, "entry") ? "yes" : "no");
    unlink(entry);
    rmdir(sub);
    rmdir(ti);
    unlink(out);
    return 0;
}
