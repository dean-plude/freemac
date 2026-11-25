/* SPDX-License-Identifier: GPL-3.0-or-later
 * The libSystem calls large plugin-based media apps (VLC, OBS) make next
 * (freemac 1.233, Ferry 0.57.0): mach_wait_until, posix_spawn with file
 * actions and attributes (a shell, and this program itself as a Mac
 * child), and glob and fnmatch with the Mac's flags. */
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <glob.h>
#include <mach/mach_time.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static uint64_t now_ns(void) { return mach_absolute_time(); } /* timebase 1/1 under Ferry; checked below */

/* ---- mach_wait_until ---- */
static void waiting(void)
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    printf("timebase %u/%u\n", tb.numer, tb.denom);
    uint64_t deadline = now_ns() + 20000000u;
    mach_wait_until(deadline);
    printf("mach_wait_until: returned at or after the deadline: %s\n", now_ns() >= deadline ? "yes" : "no");
    deadline = now_ns() - 1000;
    mach_wait_until(deadline);
    printf("mach_wait_until a deadline already past: returned\n");
}

/* ---- posix_spawn ---- */
static int wait_for(pid_t pid)
{
    int st = 0;
    if (waitpid(pid, &st, 0) != pid)
        return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}

static void read_all(int fd, const char *what)
{
    char buf[512];
    ssize_t n, len = 0;
    while ((n = read(fd, buf + len, sizeof buf - 1 - len)) > 0)
        len += n;
    buf[len] = 0;
    printf("%s: %s", what, buf);
}

static void spawning(const char *self, const char *dir)
{
    int p[2];
    pipe(p);
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_addclose(&fa, p[0]);
    posix_spawn_file_actions_addclose(&fa, p[1]);
    char *argv[] = {"sh", "-c", "echo from the shell $0; exit 3", NULL};
    pid_t pid;
    int rc = posix_spawn(&pid, "/bin/sh", &fa, NULL, argv, environ);
    close(p[1]);
    read_all(p[0], "posix_spawn /bin/sh, stdout through a pipe");
    close(p[0]);
    printf("  returned %d, exit status %d\n", rc, wait_for(pid));
    posix_spawn_file_actions_destroy(&fa);

    /* posix_spawnp, an open action with the Mac's O_ numbers, chdir */
    char out[1024];
    snprintf(out, sizeof out, "%s/spawned.txt", dir);
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    posix_spawn_file_actions_addchdir_np(&fa, dir);
    char *argv2[] = {"sh", "-c", "case $(pwd) in */ferry-media-*) echo in the folder;; esac; echo written", NULL};
    rc = posix_spawnp(&pid, "sh", &fa, NULL, argv2, environ);
    printf("posix_spawnp sh, stdout opened on a file, in another folder: %d, status %d\n", rc, wait_for(pid));
    posix_spawn_file_actions_destroy(&fa);
    int fd = open(out, O_RDONLY);
    read_all(fd, "  the file");
    close(fd);

    /* POSIX_SPAWN_CLOEXEC_DEFAULT: only what the actions name stays open */
    int keep = open("/dev/null", O_RDONLY), drop = open("/dev/null", O_RDONLY);
    dup2(keep, 20);
    dup2(drop, 21);
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);
    sigset_t mask = 0;
    posix_spawnattr_setsigmask(&attr, &mask);
    short flags = 0;
    posix_spawnattr_getflags(&attr, &flags);
    printf("flags read back: 0x%x\n", flags);
    pipe(p);
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_addinherit_np(&fa, 2);
    posix_spawn_file_actions_addinherit_np(&fa, 20);
    char *argv3[] = {"sh", "-c",
                     "for f in 0 1 2 20 21; do [ -e /proc/$$/fd/$f ] && printf ' %s' $f; done; echo", NULL};
    rc = posix_spawn(&pid, "/bin/sh", &fa, &attr, argv3, environ);
    close(p[1]);
    read_all(p[0], "CLOEXEC_DEFAULT, 1 from dup2 and 2 and 20 inherited, open in the child");
    close(p[0]);
    printf("  returned %d, status %d\n", rc, wait_for(pid));
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&attr);
    close(20);
    close(21);
    close(keep);
    close(drop);

    /* this program itself, a Mac program, as the child */
    pipe(p);
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_addclose(&fa, p[0]);
    posix_spawn_file_actions_addclose(&fa, p[1]);
    char *argv4[] = {(char *)self, "child", "two words", NULL};
    char *envp[] = {"FERRY_SPAWN_TEST=passed", NULL};
    rc = posix_spawn(&pid, self, &fa, NULL, argv4, envp);
    close(p[1]);
    read_all(p[0], "posix_spawn of this Mac program");
    close(p[0]);
    printf("  returned %d, status %d\n", rc, wait_for(pid));
    posix_spawn_file_actions_destroy(&fa);

    char *argv5[] = {"nothing", NULL};
    rc = posix_spawn(&pid, "/no/such/program", NULL, NULL, argv5, environ);
    printf("posix_spawn of a missing file: %d (ENOENT %d)\n", rc, ENOENT);
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
    rc = posix_spawn(&pid, "/bin/true", NULL, &attr, argv5, environ);
    printf("POSIX_SPAWN_SETEXEC: %d (ENOTSUP %d)\n", rc, ENOTSUP);
    posix_spawnattr_destroy(&attr);
}

/* ---- glob and fnmatch ---- */
static void globbing(const char *dir)
{
    char path[1024];
    const char *names[] = {"a.txt", "b.txt", "c.log", ".hidden.txt"};
    for (int i = 0; i < 4; i++) {
        snprintf(path, sizeof path, "%s/%s", dir, names[i]);
        close(open(path, O_WRONLY | O_CREAT, 0644));
    }
    snprintf(path, sizeof path, "%s/sub", dir);
    mkdir(path, 0755);
    if (chdir(dir) != 0)
        return;

    glob_t g;
    memset(&g, 0, sizeof g);
    int rc = glob("*.txt", 0, NULL, &g);
    printf("glob *.txt: %d, %zu:", rc, g.gl_pathc);
    for (size_t i = 0; i < g.gl_pathc; i++)
        printf(" %s", g.gl_pathv[i]);
    printf(", MAGCHAR %s\n", g.gl_flags & GLOB_MAGCHAR ? "set" : "unset");
    rc = glob("*.log", GLOB_APPEND, NULL, &g);
    printf("GLOB_APPEND *.log: %d, %zu, matchc %d, last %s\n", rc, g.gl_pathc, g.gl_matchc, g.gl_pathv[g.gl_pathc - 1]);
    globfree(&g);

    memset(&g, 0, sizeof g);
    rc = glob("*", GLOB_MARK, NULL, &g);
    printf("glob * with GLOB_MARK: %d:", rc);
    for (size_t i = 0; i < g.gl_pathc; i++)
        printf(" %s", g.gl_pathv[i]);
    printf("\n");
    globfree(&g);

    memset(&g, 0, sizeof g);
    g.gl_offs = 2;
    rc = glob("{a,c}.*", GLOB_DOOFFS | GLOB_BRACE, NULL, &g);
    printf("GLOB_DOOFFS 2, GLOB_BRACE {a,c}.*: %d: %s %s %s %s %s\n", rc, g.gl_pathv[0] ? "?" : "NULL",
           g.gl_pathv[1] ? "?" : "NULL", g.gl_pathv[2], g.gl_pathv[3], g.gl_pathv[4] ? "?" : "NULL");
    globfree(&g);

    memset(&g, 0, sizeof g);
    rc = glob("*.png", 0, NULL, &g);
    printf("no match: %d (GLOB_NOMATCH %d), %zu\n", rc, GLOB_NOMATCH, g.gl_pathc);
    globfree(&g);
    memset(&g, 0, sizeof g);
    rc = glob("*.png", GLOB_NOCHECK, NULL, &g);
    printf("GLOB_NOCHECK: %d, %s\n", rc, g.gl_pathv[0]);
    globfree(&g);

    printf("fnmatch *.c x.c: %d\n", fnmatch("*.c", "x.c", 0));
    printf("fnmatch *.c x.h: %d (FNM_NOMATCH %d)\n", fnmatch("*.c", "x.h", 0), FNM_NOMATCH);
    printf("fnmatch * a/b, FNM_PATHNAME: %d, without: %d\n", fnmatch("*", "a/b", FNM_PATHNAME), fnmatch("*", "a/b", 0));
    printf("fnmatch * .x, FNM_PERIOD: %d, without: %d\n", fnmatch("*", ".x", FNM_PERIOD), fnmatch("*", ".x", 0));
    printf("fnmatch *.TXT a.txt, FNM_CASEFOLD: %d\n", fnmatch("*.TXT", "a.txt", FNM_CASEFOLD));
    printf("fnmatch \\\\* \\\\x, FNM_NOESCAPE: %d, without: %d\n", fnmatch("\\*", "\\x", FNM_NOESCAPE),
           fnmatch("\\*", "\\x", 0));
    printf("fnmatch a a/b/c, FNM_LEADING_DIR: %d\n", fnmatch("a", "a/b/c", FNM_LEADING_DIR));
}

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "child")) {
        printf("the child: argc %d, argv[2] \"%s\", FERRY_SPAWN_TEST=%s\n", argc, argv[2],
               getenv("FERRY_SPAWN_TEST") ? getenv("FERRY_SPAWN_TEST") : "(unset)");
        return 7;
    }
    char dir[] = "/tmp/ferry-media-XXXXXX";
    if (!mkdtemp(dir))
        return 1;
    waiting();
    spawning(argv[0], dir);
    globbing(dir);
    char cmd[1100];
    snprintf(cmd, sizeof cmd, "rm -rf %s", dir);
    return system(cmd);
}
