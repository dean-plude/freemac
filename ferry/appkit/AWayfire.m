/* SPDX-License-Identifier: GPL-3.0-or-later
 * Wayfire's IPC socket (freemac 1.215, Ferry 0.41.0). Wayland lets no app
 * see another app's keys or move another app's windows, but on freemac the
 * compositor is freemac's own Wayfire, which answers on a socket: its
 * ipc-rules plugin lists windows and displays and moves windows
 * (window-rules/...), and Strata, freemac's plugin, registers global
 * shortcuts (strata/hotkeys/...). Carbon.m's hotkeys and Accessibility
 * calls and NSScreen go through here. The shell's wfipc.py is the same
 * client in Python.
 *
 * A message either way is a 4-byte little-endian length and a JSON object;
 * a request is {"method": ..., "data": {...}}. The socket is
 * $FERRY_WAYFIRE_SOCKET when that is set (the tests' stand-in Wayfire; an
 * empty value means none), and otherwise, in a Wayland session only, the
 * one freemac's session names ($WAYFIRE_SOCKET, then
 * $XDG_RUNTIME_DIR/wayfire.socket, then /tmp/wayfire-$WAYLAND_DISPLAY.socket).
 *
 * Hotkey presses come back as datagrams on a socket of the program's own,
 * $XDG_RUNTIME_DIR/ferry/hotkeys-<pid>.sock, read on the main run loop. */
#import "AInternal.h"
#import "AWayfire.h"
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>

static pthread_mutex_t ipc_lock = PTHREAD_MUTEX_INITIALIZER;
static int request_fd = -1;
static BOOL said_unreachable;

NSString *AWayfireSocketPath(void)
{
    const char *forced = getenv("FERRY_WAYFIRE_SOCKET");
    if (forced)
        return *forced ? @(forced) : nil;
    const char *display = getenv("WAYLAND_DISPLAY");
    if (!display || !*display)
        return nil;
    const char *named = getenv("WAYFIRE_SOCKET");
    if (named && *named)
        return @(named);
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    struct stat st;
    if (runtime && *runtime) {
        NSString *path = [NSString stringWithFormat:@"%s/wayfire.socket", runtime];
        if (stat([path fileSystemRepresentation], &st) == 0)
            return path;
    }
    NSString *path = [NSString stringWithFormat:@"/tmp/wayfire-%s.socket", display];
    return stat([path fileSystemRepresentation], &st) == 0 ? path : nil;
}

static int connect_socket(NSString *path)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    const char *p = [path fileSystemRepresentation];
    if (strlen(p) >= sizeof addr.sun_path)
        return -1;
    addr.sun_len = sizeof addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, p, sizeof addr.sun_path - 1);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/* Waits at most two seconds for each part, so a stuck compositor can't
 * hang the app for ever. */
static BOOL wait_for(int fd, short events)
{
    struct pollfd p = {fd, events, 0};
    int r;
    do
        r = poll(&p, 1, 2000);
    while (r < 0 && errno == EINTR);
    return r > 0 && !(p.revents & (POLLERR | POLLNVAL)) && (p.revents & (events | POLLHUP));
}

static BOOL send_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len) {
        if (!wait_for(fd, POLLOUT))
            return NO;
        ssize_t n = send(fd, p, len, 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return NO;
        p += n;
        len -= (size_t)n;
    }
    return YES;
}

static BOOL recv_all(int fd, void *buf, size_t len)
{
    char *p = buf;
    while (len) {
        if (!wait_for(fd, POLLIN))
            return NO;
        ssize_t n = recv(fd, p, len, 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return NO;
        p += n;
        len -= (size_t)n;
    }
    return YES;
}

static id exchange(int fd, NSData *request)
{
    uint32_t len = (uint32_t)[request length];
    unsigned char head[4] = {len & 0xff, (len >> 8) & 0xff, (len >> 16) & 0xff, len >> 24};
    if (!send_all(fd, head, 4) || !send_all(fd, [request bytes], len) || !recv_all(fd, head, 4))
        return nil;
    len = head[0] | (head[1] << 8) | (head[2] << 16) | ((uint32_t)head[3] << 24);
    if (len > (64u << 20))
        return nil;
    NSMutableData *body = [NSMutableData dataWithLength:len];
    if (!recv_all(fd, [body mutableBytes], len))
        return nil;
    id reply = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    return reply ?: [NSNull null];
}

BOOL AWayfireAvailable(void) { return AWayfireSocketPath() != nil; }

id AWayfireCall(NSString *method, NSDictionary *data)
{
    NSString *path = AWayfireSocketPath();
    if (!path)
        return nil;
    NSData *request = [NSJSONSerialization dataWithJSONObject:@{@"method" : method, @"data" : data ?: @{}}
                                                      options:0
                                                        error:NULL];
    if (!request)
        return nil;
    id reply = nil;
    BOOL connected = NO;
    pthread_mutex_lock(&ipc_lock);
    /* a connection that went stale (Wayfire restarted) is made again once;
     * a socket nobody listens on is no Wayfire, and says nothing */
    for (int attempt = 0; attempt < 2 && !reply; attempt++) {
        if (request_fd < 0)
            request_fd = connect_socket(path);
        if (request_fd < 0)
            break;
        connected = YES;
        reply = exchange(request_fd, request);
        if (!reply) {
            close(request_fd);
            request_fd = -1;
        }
    }
    if (!reply && connected && !said_unreachable) {
        said_unreachable = YES;
        fflush(stdout);
        fprintf(stderr, "AppKit (Ferry): the compositor's IPC socket (%s) doesn't answer\n",
                [path fileSystemRepresentation]);
    }
    pthread_mutex_unlock(&ipc_lock);
    return [reply isKindOfClass:[NSNull class]] ? nil : reply;
}

NSString *AWayfireError(id reply)
{
    if (![reply isKindOfClass:[NSDictionary class]])
        return reply ? nil : @"no answer";
    id e = reply[@"error"];
    return [e isKindOfClass:[NSString class]] ? e : nil;
}

/* ---- displays ---------------------------------------------------------------- */

static NSRect rect_of(id j)
{
    if (![j isKindOfClass:[NSDictionary class]])
        return NSZeroRect;
    return NSMakeRect([j[@"x"] doubleValue], [j[@"y"] doubleValue], [j[@"width"] doubleValue],
                      [j[@"height"] doubleValue]);
}

/* The main display's connector name, as Dials keeps it in shell.json. */
static NSString *chosen_main(void)
{
    const char *config = getenv("XDG_CONFIG_HOME");
    NSString *base = config && *config ? @(config) : [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    NSData *d = [NSData dataWithContentsOfFile:[base stringByAppendingPathComponent:@"freemac/shell.json"]];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    id name = [j isKindOfClass:[NSDictionary class]] ? j[@"main_display"] : nil;
    return [name isKindOfClass:[NSString class]] ? name : nil;
}

static BOOL built_in(NSString *name)
{
    return [name hasPrefix:@"eDP"] || [name hasPrefix:@"LVDS"] || [name hasPrefix:@"DSI"];
}

NSArray *AWayfireOutputs(void)
{
    id list = AWayfireCall(@"window-rules/list-outputs", nil);
    if (![list isKindOfClass:[NSArray class]])
        return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (id o in list) {
        if (![o isKindOfClass:[NSDictionary class]] || !o[@"id"])
            continue;
        NSRect frame = rect_of(o[@"geometry"]);
        if (frame.size.width <= 0 || frame.size.height <= 0)
            continue;
        NSRect work = o[@"workarea"] ? rect_of(o[@"workarea"]) : NSMakeRect(0, 0, frame.size.width, frame.size.height);
        work.origin.x += frame.origin.x;        /* the work area is the output's own */
        work.origin.y += frame.origin.y;
        NSString *name = [o[@"name"] isKindOfClass:[NSString class]] ? o[@"name"] : @"";
        [out addObject:@{
            @"id" : o[@"id"],
            @"name" : name,
            @"frame" : [NSValue valueWithRect:frame],
            @"work" : [NSValue valueWithRect:work],
        }];
    }
    /* the main display first, as a Mac lists the one with the menu bar first */
    NSString *chosen = chosen_main();
    NSUInteger main = NSNotFound;
    for (NSUInteger i = 0; i < [out count] && main == NSNotFound; i++)
        if (chosen && [out[i][@"name"] isEqual:chosen])
            main = i;
    for (NSUInteger i = 0; i < [out count] && main == NSNotFound; i++)
        if (built_in(out[i][@"name"]))
            main = i;
    if (main != NSNotFound && main) {
        id first = [out[main] retain];
        [out removeObjectAtIndex:main];
        [out insertObject:first atIndex:0];
        [first release];
    }
    return [out count] ? out : nil;
}

/* ---- hotkey presses ----------------------------------------------------------- */

static AWayfireHotkeyHandler hotkey_handler;
static NSString *hotkey_path;
static CFSocketRef hotkey_socket;

static void remove_hotkey_socket(void)
{
    if (hotkey_path)
        unlink([hotkey_path fileSystemRepresentation]);
}

static void hotkey_readable(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    int fd = CFSocketGetNative(s);
    char buf[512];
    ssize_t n;
    while ((n = recv(fd, buf, sizeof buf, MSG_DONTWAIT)) > 0) {
        @autoreleasepool {
            id j = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buf length:(NSUInteger)n]
                                                   options:0
                                                     error:NULL];
            if ([j isKindOfClass:[NSDictionary class]] && [j[@"event"] isEqual:@"hotkey"] && j[@"tag"] &&
                hotkey_handler)
                A_REPORTING(hotkey_handler([j[@"tag"] longLongValue]);)
        }
    }
}

NSString *AWayfireHotkeySocket(AWayfireHotkeyHandler handler)
{
    hotkey_handler = handler;
    if (hotkey_path)
        return hotkey_path;
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (!runtime || !*runtime)
        return nil;
    NSString *dir = [NSString stringWithFormat:@"%s/ferry", runtime];
    mkdir([dir fileSystemRepresentation], 0700);
    NSString *path = [dir stringByAppendingFormat:@"/hotkeys-%d.sock", (int)getpid()];
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    if (strlen([path fileSystemRepresentation]) >= sizeof addr.sun_path)
        return nil;
    addr.sun_len = sizeof addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [path fileSystemRepresentation], sizeof addr.sun_path - 1);
    int fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0)
        return nil;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    unlink(addr.sun_path);
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        close(fd);
        return nil;
    }
    hotkey_socket = CFSocketCreateWithNative(NULL, fd, kCFSocketReadCallBack, hotkey_readable, NULL);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, hotkey_socket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    hotkey_path = [path copy];
    atexit(remove_hotkey_socket);
    return hotkey_path;
}
