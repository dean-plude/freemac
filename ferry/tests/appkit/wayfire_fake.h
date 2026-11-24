/* SPDX-License-Identifier: GPL-3.0-or-later
 * For the tests run against tests/tools/fake_wayfire.py (freemac 1.215,
 * Ferry 0.41.0): one call to the stand-in Wayfire at $FERRY_WAYFIRE_SOCKET,
 * as the user's side of things (pressing a key, reading what was done). */
#import <Foundation/Foundation.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static BOOL fake_io(int fd, void *buf, size_t n, BOOL out)
{
    char *p = buf;
    while (n) {
        ssize_t r = out ? write(fd, p, n) : read(fd, p, n);
        if (r <= 0)
            return NO;
        p += r;
        n -= (size_t)r;
    }
    return YES;
}

static id fake_call(NSString *method, NSDictionary *data)
{
    const char *path = getenv("FERRY_WAYFIRE_SOCKET");
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    strncpy(a.sun_path, path ? path : "", sizeof a.sun_path - 1);
    if (fd < 0 || connect(fd, (struct sockaddr *)&a, sizeof a) < 0) {
        if (fd >= 0)
            close(fd);
        return nil;
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"method" : method, @"data" : data ?: @{}}
                                                   options:0 error:NULL];
    uint32_t n = (uint32_t)[body length];
    id reply = nil;
    if (fake_io(fd, &n, 4, YES) && fake_io(fd, (void *)[body bytes], [body length], YES) && fake_io(fd, &n, 4, NO)) {
        NSMutableData *got = [NSMutableData dataWithLength:n];
        if (fake_io(fd, [got mutableBytes], n, NO))
            reply = [NSJSONSerialization JSONObjectWithData:got options:0 error:NULL];
    }
    close(fd);
    return reply;
}

/* Runs the run loop until *flag changes, for at most a few seconds. */
static void wait_for(volatile int *flag, int from)
{
    for (int i = 0; i < 100 && *flag == from; i++)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
}
