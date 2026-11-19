/* Ferry test: error numbers arrive with their macOS values. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void)
{
    errno = 0;
    open("/nonexistent/file", O_RDONLY);
    printf("ENOENT=%d match=%d\n", errno, errno == ENOENT);

    mkdir("/tmp", 0755);
    printf("EEXIST=%d match=%d\n", errno, errno == EEXIST);

    write(9999, "x", 1);
    printf("EBADF=%d match=%d\n", errno, errno == EBADF);

    int p[2];
    pipe(p);
    fcntl(p[0], F_SETFL, O_NONBLOCK);
    char c;
    errno = 0;
    read(p[0], &c, 1);
    printf("EAGAIN=%d match=%d\n", errno, errno == EAGAIN);
    printf("text=%s\n", strerror(EAGAIN));

    errno = 0;
    open("/tmp", O_RDONLY | O_DIRECTORY);
    printf("still zero after success=%d\n", errno);

    rmdir("/");
    printf("busy or permission=%d\n", errno == EBUSY || errno == EACCES || errno == EPERM);
    errno = 0;
    char longname[400];
    memset(longname, 'a', sizeof longname - 1);
    longname[sizeof longname - 1] = 0;
    open(longname, O_RDONLY);
    printf("ENAMETOOLONG=%d match=%d\n", errno, errno == ENAMETOOLONG);
    return 0;
}
