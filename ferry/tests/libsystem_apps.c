/* SPDX-License-Identifier: GPL-3.0-or-later
 * The C library calls Sparkle and the apps make that this round added
 * (freemac 1.223, Ferry 0.47.0): fts(3) walking a tree in order, with
 * fts_set skipping a folder; statfs(2) and fstatfs(2) in the Mac's layout;
 * asl(3) messages filtered by level and written to a file of the
 * program's; os_log with its privacy annotations, and debug messages
 * dropped; O_SYMLINK opening a link itself, and fchown on what it opened;
 * the wait macros from <stdlib.h> alone; <mach/machine.h>'s CPU types and
 * <sys/errno.h>; and <strings.h>, as hoedown includes it. Its files are in
 * TMPDIR. */
#include <asl.h>
#include <fcntl.h>
#include <fts.h>
#include <mach/machine.h>
#include <os/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/errno.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

static char base[1024];

static void make(const char *rel, int dir)
{
    char p[1200];
    snprintf(p, sizeof p, "%s/%s", base, rel);
    if (dir)
        mkdir(p, 0755);
    else {
        FILE *f = fopen(p, "w");
        fputs(rel, f);
        fclose(f);
    }
}

static int by_name(const FTSENT **a, const FTSENT **b) { return strcmp((*a)->fts_name, (*b)->fts_name); }

static const char *kind(int info)
{
    switch (info) {
    case FTS_D: return "dir";
    case FTS_DP: return "dir (after)";
    case FTS_F: return "file";
    case FTS_SL: return "link";
    default: return "other";
    }
}

int main(void)
{
    const char *tmp = getenv("TMPDIR");
    snprintf(base, sizeof base, "%s/tree", tmp ? tmp : "/tmp");
    mkdir(base, 0755);
    make("b", 1);
    make("b/two.txt", 0);
    make("a.txt", 0);
    make("c", 1);
    make("c/skipped.txt", 0);
    char link[1200];
    snprintf(link, sizeof link, "%s/link", base);
    symlink("a.txt", link);

    /* fts: in name order, with c skipped, and each entry's own stat */
    char *paths[] = {base, NULL};
    FTS *f = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR, by_name);
    printf("fts_open: %s\n", f ? "yes" : "no");
    FTSENT *e;
    while ((e = fts_read(f))) {
        if (e->fts_info == FTS_D && !strcmp(e->fts_name, "c"))
            fts_set(f, e, FTS_SKIP);
        printf("  level %d %s %s", (int)e->fts_level, kind(e->fts_info), e->fts_level ? e->fts_name : "(root)");
        if (e->fts_info == FTS_F)
            printf(" %lld bytes", (long long)e->fts_statp->st_size);
        printf("\n");
    }
    printf("fts_close: %d\n", fts_close(f));

    /* statfs and fstatfs */
    struct statfs s, fs;
    int rc = statfs(base, &s);
    int fd = open(base, O_RDONLY);
    int frc = fstatfs(fd, &fs);
    close(fd);
    printf("statfs: %d, block size set %s, blocks %s, type named %s, mounted on a path %s, same from fstatfs %s\n", rc,
           s.f_bsize > 0 ? "yes" : "no", s.f_blocks > 0 ? "yes" : "no", s.f_fstypename[0] ? "yes" : "no",
           s.f_mntonname[0] == '/' ? "yes" : "no",
           frc == 0 && !strcmp(s.f_mntonname, fs.f_mntonname) && !strcmp(s.f_fstypename, fs.f_fstypename) ? "yes" : "no");
    errno = 0;
    printf("statfs of a missing path: %d ENOENT %s\n", statfs("/nonexistent/ferry", &s), errno == ENOENT ? "yes" : "no");

    /* asl: to a file of the program's, filtered up to warnings */
    char logpath[1200];
    snprintf(logpath, sizeof logpath, "%s/asl.log", base);
    int logfd = open(logpath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    aslclient c = asl_open("AppsTest", "com.example", 0);
    printf("asl_add_log_file: %d\n", asl_add_log_file(c, logfd));
    asl_set_filter(c, ASL_FILTER_MASK_UPTO(ASL_LEVEL_WARNING));
    asl_log(c, NULL, ASL_LEVEL_ERR, "an error %d", 42);
    asl_log(c, NULL, ASL_LEVEL_DEBUG, "dropped by the filter");
    aslmsg m = asl_new(ASL_TYPE_MSG);
    asl_set(m, ASL_KEY_MSG, "sent as a message");
    asl_set(m, ASL_KEY_LEVEL, "4");
    printf("asl_get: \"%s\"\n", asl_get(m, ASL_KEY_MSG));
    asl_send(c, m);
    asl_free(m);
    asl_close(c);
    close(logfd);
    FILE *lf = fopen(logpath, "r");
    char line[512];
    while (fgets(line, sizeof line, lf)) {
        char *rest = strchr(line, ']');
        printf("  log: AppsTest[pid%s", rest ? rest : line);
    }
    fclose(lf);

    /* os_log, mirrored to standard error (here, the output) */
    fflush(stdout);
    int saved = dup(2);
    dup2(1, 2);
    setenv("OS_ACTIVITY_DT_MODE", "1", 1);
    os_log_t log = os_log_create("com.example.apps", "test");
    printf("debug enabled: %s, info enabled: %s\n", os_log_type_enabled(log, OS_LOG_TYPE_DEBUG) ? "yes" : "no",
           os_log_type_enabled(log, OS_LOG_TYPE_INFO) ? "yes" : "no");
    fflush(stdout);
    os_log(log, "public %{public}s, private %{private}d", "seen", 7);
    os_log_debug(log, "a debug message, dropped");
    os_log_error(OS_LOG_DEFAULT, "an error to the default log: %s", "ok");
    fflush(stderr);
    dup2(saved, 2);
    close(saved);

    /* O_SYMLINK opens the link itself */
    int lfd = open(link, O_RDONLY | O_SYMLINK);
    struct stat st;
    fstat(lfd, &st);
    printf("O_SYMLINK: opened %s, a link %s, fchown to itself %d\n", lfd >= 0 ? "yes" : "no",
           S_ISLNK(st.st_mode) ? "yes" : "no", fchown(lfd, getuid(), getgid()));
    close(lfd);

    /* the wait macros from <stdlib.h> */
    int status = system("exit 3");
    printf("system: exited %s, status %d\n", WIFEXITED(status) ? "yes" : "no", WEXITSTATUS(status));

    printf("CPU_TYPE_X86_64 %#x, CPU_TYPE_ARM64 %#x, CPU_SUBTYPE_X86_64_ALL %d\n", CPU_TYPE_X86_64, CPU_TYPE_ARM64,
           CPU_SUBTYPE_X86_64_ALL);
    printf("ENOATTR %d\n", ENOATTR);
    printf("strings.h: strcasecmp %d, ffs(8) %d, rindex \"%s\"\n", strcasecmp("Hoedown", "HOEDOWN"), ffs(8),
           rindex("a/b/c", '/'));
    return 0;
}
