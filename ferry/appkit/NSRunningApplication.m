/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSRunningApplication and NSWorkspace's list of running
 * applications, written from Apple's public documentation. The current
 * application is this program, described by its main bundle and NSApp.
 * The others are the Ferry programs running for the same user: each
 * process whose program is Ferry itself, read from /proc. Its command
 * line names the Mac program or .app folder it runs (relative to its
 * working directory), and a program inside an .app's Contents/MacOS, or
 * the .app itself, gives the bundle, whose Info.plist gives the
 * identifier and name. Programs this system runs without Ferry aren't
 * listed. Terminating another program sends it SIGTERM, forcing it
 * SIGKILL; it can't be hidden or activated from here. The frontmost
 * application is this one while it is active, and none otherwise, since
 * Ferry can't tell which other program the desktop has in front. Built
 * without ARC. */
#import "AInternal.h"
#include <fcntl.h>
#include <signal.h>

@implementation NSRunningApplication {
    pid_t _pid;
    NSURL *_bundleURL, *_executableURL;
    NSString *_identifier, *_name;
    NSDate *_launched;
    BOOL _current;
}

/* The whole of a /proc file, which reports no size of its own. */
static NSData *read_all(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return nil;
    NSMutableData *d = [NSMutableData data];
    char buf[4096];
    for (ssize_t n; (n = read(fd, buf, sizeof buf)) > 0;)
        [d appendBytes:buf length:(NSUInteger)n];
    close(fd);
    return d;
}
static NSData *proc_file(pid_t pid, const char *what)
{
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/%s", (int)pid, what);
    return read_all(path);
}

static NSString *proc_link(pid_t pid, const char *what)
{
    char path[64], target[4096];
    if (pid)
        snprintf(path, sizeof path, "/proc/%d/%s", (int)pid, what);
    else
        snprintf(path, sizeof path, "/proc/self/%s", what);
    ssize_t n = readlink(path, target, sizeof target - 1);
    if (n <= 0)
        return nil;
    target[n] = 0;
    return [NSString stringWithUTF8String:target];
}

/* When a process started, from its start in clock ticks after boot. */
static NSDate *started(pid_t pid)
{
    NSData *stat = proc_file(pid, "stat");
    NSString *s = stat ? [[[NSString alloc] initWithData:stat encoding:NSUTF8StringEncoding] autorelease] : nil;
    NSRange close = [s rangeOfString:@")" options:NSBackwardsSearch];
    if (close.location == NSNotFound)
        return nil;
    NSArray *fields = [[s substringFromIndex:NSMaxRange(close)]
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *f = [NSMutableArray array];
    for (NSString *x in fields)
        if ([x length])
            [f addObject:x];
    if ([f count] < 20)
        return nil;
    long long ticks = [f[19] longLongValue];   /* the 22nd field, the state being the 3rd */
    NSString *all = [[[NSString alloc] initWithData:read_all("/proc/stat") ?: [NSData data]
                                           encoding:NSUTF8StringEncoding] autorelease];
    long long boot = 0;
    for (NSString *line in [all componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"btime "])
            boot = [[line substringFromIndex:6] longLongValue];
    if (!boot)
        return nil;
    long hz = sysconf(_SC_CLK_TCK);
    if (hz <= 0)
        hz = 100;
    return [NSDate dateWithTimeIntervalSince1970:(double)boot + (double)ticks / hz];
}

static NSString *bundle_name(NSDictionary *info, NSString *fallback)
{
    NSString *n = info[@"CFBundleDisplayName"];
    if (![n isKindOfClass:[NSString class]] || ![n length])
        n = info[@"CFBundleName"];
    return [n isKindOfClass:[NSString class]] && [n length] ? n : fallback;
}

+ (NSRunningApplication *)currentApplication
{
    static NSRunningApplication *me;
    if (!me) {
        me = [[NSRunningApplication alloc] init];
        me->_pid = getpid();
        me->_current = YES;
        NSBundle *b = [NSBundle mainBundle];
        if ([[[b bundlePath] pathExtension] isEqual:@"app"])
            me->_bundleURL = [[b bundleURL] copy];
        NSString *exe = [b executablePath] ?: [[NSProcessInfo processInfo] arguments][0];
        if (exe)
            me->_executableURL = [[NSURL fileURLWithPath:exe] copy];
        me->_identifier = [[b bundleIdentifier] copy];
        me->_name = [bundle_name([b infoDictionary] ?: @{}, [[NSProcessInfo processInfo] processName]) copy];
        me->_launched = [(started(getpid()) ?: [NSDate date]) retain];
    }
    return me;
}

/* Another Ferry program, from its command line; nil for a process that
 * isn't one, or has gone. */
static NSRunningApplication *from_process(pid_t pid, NSString *ferry)
{
    if (pid == getpid())
        return [NSRunningApplication currentApplication];
    NSString *exe = proc_link(pid, "exe");
    if (!exe || !([exe isEqual:ferry] || [[exe lastPathComponent] isEqual:@"ferry"]))
        return nil;
    NSData *line = proc_file(pid, "cmdline");
    NSMutableArray *args = [NSMutableArray array];
    const char *p = [line bytes], *end = p + [line length];
    while (p < end) {
        size_t n = strnlen(p, (size_t)(end - p));
        NSString *a = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
        [args addObject:a ?: @""];
        p += n + 1;
    }
    NSUInteger i = 1;
    for (; i < [args count] && [args[i] hasPrefix:@"-"]; i++)
        if ([args[i] isEqual:@"--"]) {
            i++;
            break;
        }
    if (i >= [args count])
        return nil;
    NSString *program = args[i];
    if (![program isAbsolutePath]) {
        NSString *cwd = proc_link(pid, "cwd");
        if (!cwd)
            return nil;
        program = [cwd stringByAppendingPathComponent:program];
    }
    program = [program stringByStandardizingPath];
    NSString *bundle = nil;
    if ([[program pathExtension] isEqual:@"app"])
        bundle = program;
    else {
        NSArray *parts = [program pathComponents];
        NSUInteger n = [parts count];
        if (n >= 4 && [parts[n - 2] isEqual:@"MacOS"] && [parts[n - 3] isEqual:@"Contents"] &&
            [[parts[n - 4] pathExtension] isEqual:@"app"])
            bundle = [NSString pathWithComponents:[parts subarrayWithRange:NSMakeRange(0, n - 3)]];
    }
    NSRunningApplication *app = [[[NSRunningApplication alloc] init] autorelease];
    app->_pid = pid;
    NSDictionary *info = nil;
    if (bundle) {
        info = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Contents/Info.plist"]];
        app->_bundleURL = [[NSURL fileURLWithPath:bundle isDirectory:YES] copy];
        NSString *exeName = info[@"CFBundleExecutable"];
        if (bundle == program)
            program = [[bundle stringByAppendingPathComponent:@"Contents/MacOS"]
                stringByAppendingPathComponent:[exeName isKindOfClass:[NSString class]]
                                                   ? exeName
                                                   : [[bundle lastPathComponent] stringByDeletingPathExtension]];
        NSString *ident = info[@"CFBundleIdentifier"];
        if ([ident isKindOfClass:[NSString class]])
            app->_identifier = [ident copy];
    }
    app->_executableURL = [[NSURL fileURLWithPath:program] copy];
    NSString *fallback = bundle ? [[bundle lastPathComponent] stringByDeletingPathExtension] : [program lastPathComponent];
    app->_name = [bundle_name(info ?: @{}, fallback) copy];
    app->_launched = [started(pid) retain];
    return app;
}

static NSArray *all_running(void)
{
    NSString *ferry = proc_link(0, "exe");
    NSMutableArray *out = [NSMutableArray arrayWithObject:[NSRunningApplication currentApplication]];
    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/proc" error:NULL];
    NSMutableArray *pids = [NSMutableArray array];
    for (NSString *e in entries) {
        int pid = [e intValue];
        if (pid > 0 && [[NSString stringWithFormat:@"%d", pid] isEqual:e] && pid != getpid())
            [pids addObject:@(pid)];
    }
    [pids sortUsingSelector:@selector(compare:)];
    for (NSNumber *n in pids) {
        NSRunningApplication *a = from_process([n intValue], ferry);
        if (a)
            [out addObject:a];
    }
    return out;
}

+ (instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid
{
    if (pid <= 0)
        return nil;
    return from_process(pid, proc_link(0, "exe"));
}
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSRunningApplication *a in all_running())
        if (identifier && [a->_identifier isEqual:identifier])
            [out addObject:a];
    return out;
}
+ (void)terminateAutomaticallyTerminableApplications {}

- (void)dealloc
{
    [_bundleURL release];
    [_executableURL release];
    [_identifier release];
    [_name release];
    [_launched release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSRunningApplication class]] && ((NSRunningApplication *)other)->_pid == _pid;
}
- (NSUInteger)hash { return (NSUInteger)_pid; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSRunningApplication: %p (%@ - %d)>", self, _identifier ?: _name, (int)_pid];
}

- (pid_t)processIdentifier { return _pid; }
- (NSString *)bundleIdentifier { return _identifier; }
- (NSString *)localizedName { return _name; }
- (NSURL *)bundleURL { return _bundleURL; }
- (NSURL *)executableURL { return _executableURL; }
- (NSDate *)launchDate { return _launched; }
- (NSInteger)executableArchitecture { return 0x01000007; /* NSBundleExecutableArchitectureX86_64 */ }
- (NSImage *)icon
{
    NSString *path = [(_bundleURL ?: _executableURL) path];
    return path ? [[NSWorkspace sharedWorkspace] iconForFile:path] : nil;
}
- (BOOL)isTerminated
{
    if (_current)
        return NO;
    return kill(_pid, 0) != 0 && errno == ESRCH;
}
- (BOOL)isFinishedLaunching { return YES; }
- (BOOL)isHidden { return NO; }
- (BOOL)isActive { return _current && [NSApp isActive]; }
- (BOOL)ownsMenuBar { return [self isActive]; }
- (NSApplicationActivationPolicy)activationPolicy
{
    if (_current)
        return NSApp ? [NSApp activationPolicy] : NSApplicationActivationPolicyProhibited;
    return _bundleURL ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyProhibited;
}

- (BOOL)hide
{
    if (!_current || !NSApp)
        return NO;
    [NSApp hide:nil];
    return YES;
}
- (BOOL)unhide
{
    if (!_current || !NSApp)
        return NO;
    [NSApp unhide:nil];
    return YES;
}
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options
{
    if (!_current || !NSApp)
        return NO;
    [NSApp activateIgnoringOtherApps:(options & NSApplicationActivateIgnoringOtherApps) != 0];
    return YES;
}
- (BOOL)terminate
{
    if (_current) {
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0];
        return NSApp != nil;
    }
    return kill(_pid, SIGTERM) == 0;
}
- (BOOL)forceTerminate
{
    if (_current)
        return NO;
    return kill(_pid, SIGKILL) == 0;
}
@end

@implementation NSWorkspace (NSRunningApplications)
- (NSArray *)runningApplications { return all_running(); }
- (NSRunningApplication *)frontmostApplication
{
    return [NSApp isActive] ? [NSRunningApplication currentApplication] : nil;
}
- (NSRunningApplication *)menuBarOwningApplication { return [self frontmostApplication]; }
@end
