/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): NSRunningApplication and
 * NSWorkspace's running applications, with no display. The current
 * application, then an .app the test makes from its own program and starts
 * with NSTask: found by its bundle identifier and its process, with its
 * name, bundle, program and launch date, then ended with terminate and
 * forceTerminate. Flycut looks for its other copies this way. */
#import <Cocoa/Cocoa.h>
#include <signal.h>
#include <unistd.h>

static NSArray *find(NSString *ident, NSUInteger want)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    NSArray *found;
    while ([(found = [NSRunningApplication runningApplicationsWithBundleIdentifier:ident]) count] < want &&
           [limit timeIntervalSinceNow] > 0)
        usleep(20000);
    return found;
}

static NSTask *start(NSString *program)
{
    NSTask *t = [[NSTask alloc] init];
    [t setLaunchPath:program];
    [t setArguments:@[ @"wait" ]];
    [t launch];
    return t;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "wait")) {
            /* the started app: waits to be ended */
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:30]];
            return 3;
        }
        [NSApplication sharedApplication];
        NSRunningApplication *me = [NSRunningApplication currentApplication];
        printf("current: the same each time %s, our process %s, a name %s, no bundle identifier %s\n",
               me == [NSRunningApplication currentApplication] ? "yes" : "no",
               [me processIdentifier] == getpid() ? "yes" : "no", [[me localizedName] length] ? "yes" : "no",
               [me bundleIdentifier] ? "no" : "yes");
        printf("its program: %s, launched in the last minute: %s, terminated %s, finished launching %s\n",
               [[[me executableURL] lastPathComponent]
                   isEqual:[[[NSProcessInfo processInfo] arguments][0] lastPathComponent]]
                   ? "this one"
                   : [[[me executableURL] path] UTF8String],
               [[me launchDate] timeIntervalSinceNow] > -60 && [[me launchDate] timeIntervalSinceNow] <= 1 ? "yes" : "no",
               [me isTerminated] ? "yes" : "no", [me isFinishedLaunching] ? "yes" : "no");
        printf("by process: %s, process 0: %s\n",
               [NSRunningApplication runningApplicationWithProcessIdentifier:getpid()] == me ? "the current one" : "another",
               [NSRunningApplication runningApplicationWithProcessIdentifier:0] ? "one" : "none");
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        printf("among the workspace's running applications: %s\n", [[ws runningApplications] containsObject:me] ? "yes" : "no");
        printf("frontmost while inactive: %s\n", [ws frontmostApplication] ? "one" : "none");
        [me activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        printf("activated: active %s, frontmost %s\n", [me isActive] ? "yes" : "no",
               [ws frontmostApplication] == me ? "the current one" : "another");
        printf("architecture: 0x%lx\n", (long)[me executableArchitecture]);

        /* an .app made from this program */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                    [NSString stringWithFormat:@"ferry-running-%d", getpid()]];
        NSString *app = [dir stringByAppendingPathComponent:@"Runner.app"];
        NSString *macos = [app stringByAppendingPathComponent:@"Contents/MacOS"];
        [fm removeItemAtPath:dir error:NULL];
        [fm createDirectoryAtPath:macos withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *program = [macos stringByAppendingPathComponent:@"Runner"];
        NSString *me_path = [[[NSProcessInfo processInfo] arguments][0] stringByStandardizingPath];
        if (![me_path isAbsolutePath])
            me_path = [[fm currentDirectoryPath] stringByAppendingPathComponent:me_path];
        BOOL copied = [fm copyItemAtPath:me_path toPath:program error:NULL];
        [@{@"CFBundleIdentifier" : @"org.freemac.test.runner", @"CFBundleName" : @"Runner",
           @"CFBundleExecutable" : @"Runner"} writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"]
                                               atomically:YES];
        printf("the app made: %s\n", copied ? "yes" : "no");
        printf("before it starts: %lu running\n",
               (unsigned long)[[NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.freemac.test.runner"] count]);

        NSTask *t = start(program);
        NSArray *found = find(@"org.freemac.test.runner", 1);
        NSRunningApplication *r = [found firstObject];
        printf("started: %lu found, its process %s, name %s, bundle %s, program %s\n", (unsigned long)[found count],
               [r processIdentifier] == [t processIdentifier] ? "the task's" : "another", [[r localizedName] UTF8String],
               [[[r bundleURL] lastPathComponent] UTF8String], [[[r executableURL] lastPathComponent] UTF8String]);
        printf("launched in the last minute: %s, terminated %s, a regular app %s, not active %s\n",
               [[r launchDate] timeIntervalSinceNow] > -60 ? "yes" : "no", [r isTerminated] ? "yes" : "no",
               [r activationPolicy] == NSApplicationActivationPolicyRegular ? "yes" : "no", [r isActive] ? "no" : "yes");
        NSRunningApplication *byPid = [NSRunningApplication runningApplicationWithProcessIdentifier:[t processIdentifier]];
        printf("by its process: %s, equal %s; in the workspace's list: %s\n", [[byPid bundleIdentifier] UTF8String],
               [byPid isEqual:r] ? "yes" : "no", [[ws runningApplications] containsObject:r] ? "yes" : "no");
        printf("hidden or activated from here: %s\n", [r hide] || [r activateWithOptions:0] ? "yes" : "no");
        printf("terminate: %s\n", [r terminate] ? "sent" : "not sent");
        [t waitUntilExit];
        printf("it ended by signal %d (SIGTERM %s), terminated now %s\n", [t terminationStatus],
               [t terminationStatus] == SIGTERM ? "yes" : "no", [r isTerminated] ? "yes" : "no");

        NSTask *t2 = start(program);
        r = [find(@"org.freemac.test.runner", 1) firstObject];
        printf("again: found %s\n", [r processIdentifier] == [t2 processIdentifier] ? "yes" : "no");
        printf("force terminate: %s\n", [r forceTerminate] ? "sent" : "not sent");
        [t2 waitUntilExit];
        printf("it ended by signal %d (SIGKILL %s)\n", [t2 terminationStatus], [t2 terminationStatus] == SIGKILL ? "yes" : "no");
        printf("after: %lu running\n",
               (unsigned long)[[NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.freemac.test.runner"] count]);
        [fm removeItemAtPath:dir error:NULL];
    }
    return 0;
}
