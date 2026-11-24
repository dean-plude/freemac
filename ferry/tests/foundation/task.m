/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSTask running this system's programs (/bin/sh, /bin/echo,
 * /bin/cat) and a Mac program (this test itself, through Ferry), NSPipe,
 * and NSFileHandle on pipes and files, with its background reads served by
 * the run loop and by dispatch's waits. */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <unistd.h>

static NSString *text(NSData *d) { return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease]; }

static NSTask *task(NSString *path, NSArray *args)
{
    NSTask *t = [[[NSTask alloc] init] autorelease];
    [t setLaunchPath:path];
    [t setArguments:args];
    return t;
}

static NSString *run(NSTask *t)
{
    NSPipe *out = [NSPipe pipe];
    [t setStandardOutput:out];
    [t launch];
    NSData *d = [[out fileHandleForReading] readDataToEndOfFile];
    [t waitUntilExit];
    return text(d);
}

@interface Watcher : NSObject {
@public
    NSMutableString *log;
}
@end
@implementation Watcher
- (void)read:(NSNotification *)n
{
    NSData *d = [[n userInfo] objectForKey:NSFileHandleNotificationDataItem];
    [log appendFormat:@"[read %lu]", (unsigned long)[d length]];
    if ([d length])
        [[n object] readInBackgroundAndNotify];
}
- (void)toEnd:(NSNotification *)n
{
    [log appendFormat:@"[to end: %@]", text([[n userInfo] objectForKey:NSFileHandleNotificationDataItem])];
}
- (void)available:(NSNotification *)n
{
    [log appendFormat:@"[available: %@]", text([[n object] availableData])];
}
- (void)ended:(NSNotification *)n { [log appendFormat:@"[terminated %d]", [[n object] terminationStatus]]; }
@end

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "child")) {
        printf("the Mac child got %s and %s\n", argv[2], getenv("FERRY_TASK_TEST") ?: "(none)");
        return 7;
    }
    @autoreleasepool {
        /* programs, arguments, exit status */
        NSTask *t = task(@"/bin/echo", @[ @"hello", @"from echo" ]);
        printf("before launch: pid %d, running %d\n", [t processIdentifier], [t isRunning]);
        printf("echo: %s", [run(t) UTF8String]);
        printf("status %d, reason %ld, running %d, has a pid %d\n", [t terminationStatus], (long)[t terminationReason],
               [t isRunning], [t processIdentifier] > 0);
        t = task(@"/bin/sh", @[ @"-c", @"exit 3" ]);
        [t launch];
        [t waitUntilExit];
        printf("exit 3: status %d, reason %ld\n", [t terminationStatus], (long)[t terminationReason]);
        t = task(@"/bin/sh", @[ @"-c", @"kill -TERM $$" ]);
        [t launch];
        [t waitUntilExit];
        printf("killed: status %d, reason %s\n", [t terminationStatus],
               [t terminationReason] == NSTaskTerminationReasonUncaughtSignal ? "uncaught signal" : "exit");

        /* environment and folder */
        t = task(@"/bin/sh", @[ @"-c", @"echo \"$FOO-$BAR\"; pwd" ]);
        [t setEnvironment:@{ @"FOO" : @"foo", @"BAR" : @"bar" }];
        [t setCurrentDirectoryPath:@"/"];
        printf("environment and folder: %s", [[run(t) stringByReplacingOccurrencesOfString:@"\n" withString:@" | "] UTF8String]);
        printf("\n");
        setenv("FERRY_TASK_TEST", "inherited", 1);
        t = task(@"/bin/sh", @[ @"-c", @"echo $FERRY_TASK_TEST" ]);
        printf("inherited environment: %s", [run(t) UTF8String]);

        /* standard input through a pipe; standard error to its own pipe */
        t = task(@"/bin/cat", nil);
        NSPipe *in = [NSPipe pipe], *out = [NSPipe pipe];
        [t setStandardInput:in];
        [t setStandardOutput:out];
        [t launch];
        [[in fileHandleForWriting] writeData:[@"through cat\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [[in fileHandleForWriting] closeFile];
        printf("cat: %s", [text([[out fileHandleForReading] readDataToEndOfFile]) UTF8String]);
        [t waitUntilExit];
        t = task(@"/bin/sh", @[ @"-c", @"echo to stderr >&2; echo to stdout" ]);
        NSPipe *err = [NSPipe pipe];
        [t setStandardError:err];
        printf("stdout: %s", [run(t) UTF8String]);
        printf("stderr: %s", [text([[err fileHandleForReading] readDataToEndOfFile]) UTF8String]);
        t = task(@"/bin/echo", @[ @"into the null device" ]);
        [t setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        [t launch];
        [t waitUntilExit];
        printf("null device: status %d\n", [t terminationStatus]);

        /* a program that waits: still running, then terminated */
        t = task(@"/bin/sh", @[ @"-c", @"read line; echo got $line" ]);
        in = [NSPipe pipe];
        [t setStandardInput:in];
        [t setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        [t launch];
        printf("waiting: running %d\n", [t isRunning]);
        @try {
            [t terminationStatus];
        } @catch (NSException *e) {
            printf("terminationStatus too early: %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        }
        @try {
            [t launch];
        } @catch (NSException *e) {
            printf("launched twice: %s\n", [[e reason] UTF8String]);
        }
        [t terminate];
        [t waitUntilExit];
        printf("terminated: status %d, reason %ld\n", [t terminationStatus], (long)[t terminationReason]);

        /* what can't be launched */
        t = task(@"/no/such/program", nil);
        NSError *error = nil;
        BOOL ok = [t launchAndReturnError:&error];
        printf("missing program: %d, %s %ld, path %s\n", ok, [[error domain] UTF8String], (long)[error code],
               [[[error userInfo] objectForKey:NSFilePathErrorKey] UTF8String]);
        @try {
            [task(@"/no/such/program", nil) launch];
        } @catch (NSException *e) {
            printf("launch: %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        }
        t = task(@"/bin/sh", @[ @"-c", @"true" ]);
        [t setCurrentDirectoryPath:@"/no/such/folder"];
        printf("missing folder: %d\n", [t launchAndReturnError:NULL]);
        @try {
            [task(@"/bin/sh", nil) terminate];
        } @catch (NSException *e) {
            printf("terminate before launch: %s\n", [[e reason] UTF8String]);
        }

        /* the termination handler, the notification and a readability
         * handler, from the run loop */
        Watcher *w = [[[Watcher alloc] init] autorelease];
        w->log = [NSMutableString string];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:w selector:@selector(ended:) name:NSTaskDidTerminateNotification object:nil];
        t = task(@"/bin/sh", @[ @"-c", @"echo one; echo two; exit 5" ]);
        out = [NSPipe pipe];
        [t setStandardOutput:out];
        NSMutableData *collected = [NSMutableData data];
        __block BOOL eof = NO, done = NO;
        [[out fileHandleForReading] setReadabilityHandler:^(NSFileHandle *h) {
          NSData *d = [h availableData];
          if ([d length] == 0) {
              eof = YES;
              [h setReadabilityHandler:nil];
          } else
              [collected appendData:d];
        }];
        [t setTerminationHandler:^(NSTask *task) {
          done = YES;
          printf("termination handler: status %d\n", [task terminationStatus]);
        }];
        [t launch];
        while (!(eof && done))
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        printf("readability handler collected: %s", [text(collected) UTF8String]);
        printf("log: %s\n", [w->log UTF8String]);
        [nc removeObserver:w name:NSTaskDidTerminateNotification object:nil];

        /* background reads, notified through the run loop */
        [w->log setString:@""];
        [nc addObserver:w selector:@selector(read:) name:NSFileHandleReadCompletionNotification object:nil];
        [nc addObserver:w selector:@selector(toEnd:) name:NSFileHandleReadToEndOfFileCompletionNotification object:nil];
        [nc addObserver:w selector:@selector(available:) name:NSFileHandleDataAvailableNotification object:nil];
        NSPipe *p = [NSPipe pipe];
        [[p fileHandleForReading] readInBackgroundAndNotify];
        [[p fileHandleForWriting] writeData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        [[p fileHandleForWriting] closeFile];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        p = [NSPipe pipe];
        [[p fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
        [[p fileHandleForWriting] writeData:[@"all " dataUsingEncoding:NSUTF8StringEncoding]];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [[p fileHandleForWriting] writeData:[@"of it" dataUsingEncoding:NSUTF8StringEncoding]];
        [[p fileHandleForWriting] closeFile];
        while ([w->log rangeOfString:@"to end"].location == NSNotFound)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        p = [NSPipe pipe];
        [[p fileHandleForReading] waitForDataInBackgroundAndNotify];
        [[p fileHandleForWriting] writeData:[@"ready" dataUsingEncoding:NSUTF8StringEncoding]];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        printf("background: %s\n", [w->log UTF8String]);
        [nc removeObserver:w];

        /* a dispatch semaphore wait sees the exit too */
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block int seen = -1;
        NSTask *quick = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]
                                                   arguments:@[ @"-c", @"exit 9" ]
                                                       error:NULL
                                          terminationHandler:^(NSTask *task) {
                                            seen = [task terminationStatus];
                                            dispatch_semaphore_signal(sem);
                                          }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        printf("semaphore: handler saw %d, task %s\n", seen, quick ? "made" : "nil");
        t = [NSTask launchedTaskWithLaunchPath:@"/bin/sh" arguments:@[ @"-c", @"exit 0" ]];
        [t waitUntilExit];
        printf("launchedTaskWithLaunchPath: status %d\n", [t terminationStatus]);

        /* a Mac program: run through Ferry */
        t = task([[[NSProcessInfo processInfo] arguments] objectAtIndex:0], @[ @"child", @"an argument" ]);
        printf("%s", [run(t) UTF8String]);
        printf("the Mac child exited %d\n", [t terminationStatus]);

        /* file handles on files */
        NSString *path = [NSString stringWithFormat:@"/tmp/ferry-task-test-%d", getpid()];
        printf("missing file: %s\n", [NSFileHandle fileHandleForReadingAtPath:path] ? "a handle" : "nil");
        NSError *ferr = nil;
        [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:path] error:&ferr];
        printf("missing file by URL: %s %ld\n", [[ferr domain] UTF8String], (long)[ferr code]);
        [@"0123456789" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        NSFileHandle *f = [NSFileHandle fileHandleForUpdatingAtPath:path];
        printf("read 4: %s, offset %llu\n", [text([f readDataOfLength:4]) UTF8String], [f offsetInFile]);
        printf("available: %s\n", [text([f availableData]) UTF8String]);
        [f seekToFileOffset:2];
        [f writeData:[@"ab" dataUsingEncoding:NSUTF8StringEncoding]];
        printf("end at %llu\n", [f seekToEndOfFile]);
        [f writeData:[@"!" dataUsingEncoding:NSUTF8StringEncoding]];
        [f truncateFileAtOffset:8];
        [f synchronizeFile];
        [f closeFile];
        printf("file now: %s\n", [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] UTF8String]);
        @try {
            [f readDataToEndOfFile];
        } @catch (NSException *e) {
            printf("read after close: %s\n", [[e name] UTF8String]);
        }
        f = [NSFileHandle fileHandleForReadingAtPath:path];
        unsigned long long off = 0;
        printf("seek with error: %d", [f seekToEndReturningOffset:&off error:NULL]);
        printf(" at %llu, read past end: %lu bytes\n", off, (unsigned long)[[f readDataToEndOfFile] length]);
        printf("closed: %d\n", [f closeAndReturnError:NULL]);
        unlink([path fileSystemRepresentation]);

        fflush(stdout);
        [[NSFileHandle fileHandleWithStandardOutput]
            writeData:[@"written to the standard output handle\n" dataUsingEncoding:NSUTF8StringEncoding]];
        printf("standard handles: %d %d %d\n", [[NSFileHandle fileHandleWithStandardInput] fileDescriptor],
               [[NSFileHandle fileHandleWithStandardOutput] fileDescriptor],
               [[NSFileHandle fileHandleWithStandardError] fileDescriptor]);
    }
    return 0;
}
