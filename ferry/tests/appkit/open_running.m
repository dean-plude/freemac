/* SPDX-License-Identifier: GPL-3.0-or-later
 * Opening files in the copy of an app that's already running (freemac
 * 1.NEXT): the app listens on $XDG_RUNTIME_DIR/ferry/<bundle id>.open, and
 * freemac-mac-app sends it the files a double-click or a drop on its Dock
 * icon names, or nothing, to bring it to the front. Here the app sends its
 * own requests from another thread, as the desktop would from outside, and
 * prints what its delegate is given. Run in OpenApp.app (its bundle
 * identifier names the socket), with XDG_RUNTIME_DIR a folder of the test's. */
#import <Cocoa/Cocoa.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static NSString *socket_path(void)
{
    return [NSString stringWithFormat:@"%s/ferry/org.freemac.ferry.openapp.open", getenv("XDG_RUNTIME_DIR")];
}

/* One request: connect, send the lines, close the sending side, read the
 * answer. */
static NSString *ask(NSString *lines)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_len = sizeof addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [socket_path() fileSystemRepresentation], sizeof addr.sun_path - 1);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        if (fd >= 0)
            close(fd);
        return @"(no connection)";
    }
    const char *bytes = [lines UTF8String];
    (void)!write(fd, bytes, strlen(bytes));
    shutdown(fd, SHUT_WR);
    char answer[16] = {0};
    ssize_t n = read(fd, answer, sizeof answer - 1);
    close(fd);
    return n > 0 ? [[NSString stringWithUTF8String:answer]
                       stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                 : @"(no answer)";
}

@interface Delegate : NSObject <NSApplicationDelegate>
@end

@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    printf("listening: %s\n", access([socket_path() fileSystemRepresentation], F_OK) == 0 ? "yes" : "no");
    fflush(stdout);
    NSString *dir = [[[NSFileManager defaultManager] currentDirectoryPath] stringByStandardizingPath];
    NSString *files = [NSString stringWithFormat:@"%@/Second.txt\n%@/First.txt\nRelative.txt\n%@/Missing.txt\n",
                                                 dir, dir, dir];
    [NSThread detachNewThreadWithBlock:^{
        NSString *a = ask(@"");
        NSString *b = ask(files);
        dispatch_async(dispatch_get_main_queue(), ^{
            printf("answers: %s, %s\n", [a UTF8String], [b UTF8String]);
            fflush(stdout);
        });
    }];
    [NSTimer scheduledTimerWithTimeInterval:10 repeats:NO block:^(NSTimer *t) {
        printf("timed out\n");
        [NSApp terminate:nil];
    }];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible
{
    printf("reopen, visible windows: %s\n", visible ? "yes" : "no");
    fflush(stdout);
    return NO;
}

- (void)application:(NSApplication *)app openFiles:(NSArray *)files
{
    printf("open %lu:", (unsigned long)[files count]);
    for (NSString *f in files)
        printf(" %s", [[f lastPathComponent] UTF8String]);
    printf("\n");
    fflush(stdout);
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Delegate *d = [Delegate new];
        [NSApp setDelegate:d];
        [NSApp run];
    }
    return 0;
}
