/* Ferry test: files and folders through stdio and POSIX calls. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int cmp(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

int main(void)
{
    char dir[] = "/tmp/ferry-files-XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    if (chdir(dir) < 0) { perror("chdir"); return 1; }

    FILE *f = fopen("notes.txt", "w");
    fprintf(f, "first line\nsecond line\nthird\n");
    fclose(f);

    struct stat st;
    if (stat("notes.txt", &st) < 0) { perror("stat"); return 1; }
    printf("size=%lld regular=%d dir=%d\n", (long long)st.st_size, S_ISREG(st.st_mode), S_ISDIR(st.st_mode));

    f = fopen("notes.txt", "r");
    char line[64];
    int n = 0;
    while (fgets(line, sizeof line, f))
        n++;
    printf("lines=%d eof=%d\n", n, feof(f) != 0);
    rewind(f);
    char *buf = NULL;
    size_t cap = 0;
    ssize_t len = getline(&buf, &cap, f);
    printf("getline=%zd '%.*s'\n", len, (int)len - 1, buf);
    size_t ln;
    char *rest = fgetln(f, &ln);
    printf("fgetln=%zu '%.*s'\n", ln, (int)ln - 1, rest);
    fseek(f, 0, SEEK_END);
    printf("ftell=%ld\n", ftell(f));
    fclose(f);
    free(buf);

    int fd = open("raw.bin", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror("open"); return 1; }
    write(fd, "abcdef", 6);
    close(fd);
    fd = open("raw.bin", O_RDONLY);
    char raw[8] = {0};
    printf("read=%zd '%s'\n", read(fd, raw, sizeof raw - 1), raw);
    struct stat fst;
    fstat(fd, &fst);
    printf("fstat size=%lld flags_ok=%d\n", (long long)fst.st_size, (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY);
    close(fd);

    fd = open("raw.bin", O_WRONLY | O_APPEND);
    write(fd, "gh", 2);
    printf("append flag kept=%d\n", (fcntl(fd, F_GETFL) & O_APPEND) != 0);
    close(fd);
    stat("raw.bin", &st);
    printf("after append=%lld\n", (long long)st.st_size);

    mkdir("sub", 0755);
    symlink("notes.txt", "link");
    struct stat lst;
    lstat("link", &lst);
    printf("lstat link=%d\n", S_ISLNK(lst.st_mode));

    DIR *d = opendir(".");
    char *names[16];
    int count = 0;
    struct dirent *e;
    while ((e = readdir(d)) && count < 16)
        if (e->d_name[0] != '.')
            names[count++] = strdup(e->d_name);
    closedir(d);
    qsort(names, count, sizeof names[0], cmp);
    printf("entries:");
    for (int i = 0; i < count; i++) {
        printf(" %s", names[i]);
        free(names[i]);
    }
    printf("\n");

    errno = 0;
    printf("missing=%s errno=%d\n", fopen("nope.txt", "r") ? "found" : "NULL", errno);
    printf("access=%d\n", access("notes.txt", R_OK));

    unlink("notes.txt");
    unlink("raw.bin");
    unlink("link");
    rmdir("sub");
    chdir("/");
    printf("cleanup=%d\n", rmdir(dir));
    return 0;
}
