/* SPDX-License-Identifier: GPL-3.0-or-later
 * A Mac program started through one of this system's tools that run
 * another program (freemac 1.NEXT, Shotcut): Shotcut starts its encoder,
 * a Mac program in its bundle, as "nice -n 3 .../melt ...". Here nice,
 * nohup and env, run by posix_spawnp or the exec family, start this test's
 * own Mach-O, which says what it was given. */
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int run(const char *how, char *const av[], int use_exec)
{
    fflush(stdout);
    pid_t pid;
    if (use_exec) {
        pid = fork();
        if (pid == 0) {
            execvp(av[0], av);
            _exit(99);
        }
    } else if (posix_spawnp(&pid, av[0], NULL, NULL, av, environ) != 0) {
        printf("%s: not started\n", how);
        return -1;
    }
    int status = 0;
    waitpid(pid, &status, 0);
    printf("%s: exited %d\n", how, WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    return 0;
}

int main(int argc, char **argv, char **envp, char **apple)
{
    (void)envp;
    if (argc > 1 && !strcmp(argv[1], "child")) {
        const char *v = getenv("WRAPPED");
        printf("  the Mac program ran with %s, %s, WRAPPED=%s\n", argc > 2 ? argv[2] : "-", argc > 3 ? argv[3] : "-",
               v ? v : "-");
        return 7;
    }
    const char *self = apple[0] + strlen("executable_path=");

    char *nice_av[] = {"nice", "-n", "3", (char *)self, "child", "one", "two", NULL};
    run("nice -n 3, spawned", nice_av, 0);
    run("nice -n 3, exec", nice_av, 1);
    char *nohup_av[] = {"nohup", (char *)self, "child", "three", NULL};
    run("nohup, exec", nohup_av, 1);
    char *env_av[] = {"env", "-u", "NOTHING", "WRAPPED=yes", (char *)self, "child", "four", NULL};
    run("env with a variable, spawned", env_av, 0);
    /* a program of this system behind nice is left as it is */
    char *sh_av[] = {"nice", "-n", "3", "/bin/sh", "-c", "exit 5", NULL};
    run("nice with a program of this system", sh_av, 0);
    return 0;
}
