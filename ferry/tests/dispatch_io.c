/* Dispatch data objects and dispatch I/O (freemac 1.232, Ferry 0.56.0),
 * as Qt's QRandomAccessAsyncFile uses them on a Mac: data made, joined,
 * cut and walked; a file written and read back through a channel at
 * offsets, a channel closed with its cleanup handler, and dispatch_read on
 * a pipe. */
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static dispatch_semaphore_t done;
static void wait_done(void) { dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER); }

int main(void)
{
    done = dispatch_semaphore_create(0);
    dispatch_queue_t q = dispatch_queue_create("test", NULL);

    dispatch_data_t a = dispatch_data_create("Hello, ", 7, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    char *owned = strdup("world");
    dispatch_data_t b = dispatch_data_create(owned, 5, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
    dispatch_data_t ab = dispatch_data_create_concat(a, b);
    printf("sizes %zu %zu %zu, empty %zu\n", dispatch_data_get_size(a), dispatch_data_get_size(b),
           dispatch_data_get_size(ab), dispatch_data_get_size(dispatch_data_empty));
    const void *buf;
    size_t size;
    dispatch_data_t map = dispatch_data_create_map(ab, &buf, &size);
    printf("map \"%.*s\"\n", (int)size, (const char *)buf);
    dispatch_data_t sub = dispatch_data_create_subrange(ab, 7, 100);
    __block size_t regions = 0, total = 0;
    dispatch_data_apply(sub, ^bool(dispatch_data_t r, size_t off, const void *p, size_t n) {
      regions++;
      total += n;
      printf("region at %zu: \"%.*s\"\n", off, (int)n, (const char *)p);
      return true;
    });
    printf("regions %zu, bytes %zu\n", regions, total);
    __block int destroyed = 0;
    char stack[4] = "abc";
    dispatch_data_t custom = dispatch_data_create(stack, 3, q, ^{
      destroyed = 1;
      dispatch_semaphore_signal(done);
    });
    dispatch_release(custom);
    wait_done();
    printf("custom destructor ran %d\n", destroyed);

    char path[] = "/tmp/ferry_dispatch_io_XXXXXX";
    int fd = mkstemp(path);
    close(fd);
    __block int cleaned = -1;
    dispatch_io_t ch = dispatch_io_create_with_path(DISPATCH_IO_RANDOM, path, O_RDWR, 0600, q, ^(int error) {
      cleaned = error;
      dispatch_semaphore_signal(done);
    });
    dispatch_io_write(ch, 0, ab, q, ^(bool d, dispatch_data_t rest, int error) {
      printf("write done %d error %d rest %d\n", d, error, rest == NULL);
      dispatch_semaphore_signal(done);
    });
    wait_done();
    dispatch_io_read(ch, 7, 5, q, ^(bool d, dispatch_data_t data, int error) {
      const void *p;
      size_t n;
      dispatch_data_t m = dispatch_data_create_map(data, &p, &n);
      printf("read at 7: done %d error %d \"%.*s\"\n", d, error, (int)n, (const char *)p);
      dispatch_release(m);
      dispatch_semaphore_signal(done);
    });
    wait_done();
    dispatch_io_read(ch, 0, SIZE_MAX, q, ^(bool d, dispatch_data_t data, int error) {
      printf("read all: %zu bytes\n", dispatch_data_get_size(data));
      dispatch_semaphore_signal(done);
    });
    wait_done();
    __block int barrier = 0;
    dispatch_io_barrier(ch, ^{ barrier = 1; });
    dispatch_io_close(ch, 0);
    wait_done();
    printf("barrier %d, cleanup error %d\n", barrier, cleaned);
    dispatch_io_read(ch, 0, 1, q, ^(bool d, dispatch_data_t data, int error) {
      printf("read after close: error is ECANCELED %d\n", error == 89);
      dispatch_semaphore_signal(done);
    });
    wait_done();
    dispatch_release(ch);
    unlink(path);

    int p[2];
    pipe(p);
    write(p[1], "pipe!", 5);
    close(p[1]);
    dispatch_read(p[0], 100, q, ^(dispatch_data_t data, int error) {
      printf("dispatch_read %zu bytes error %d\n", dispatch_data_get_size(data), error);
      dispatch_semaphore_signal(done);
    });
    wait_done();
    close(p[0]);
    dispatch_release(map);
    dispatch_release(sub);
    dispatch_release(ab);
    dispatch_release(a);
    dispatch_release(b);
    return 0;
}
