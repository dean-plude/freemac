/* SPDX-License-Identifier: GPL-3.0-or-later
 * FSEvents (freemac 1.222, Ferry 0.46.0): a stream on a folder, by item
 * and by folder, hearing files made, written, renamed, changed and removed,
 * in the folder and in a folder made inside it; the paths as C strings, as
 * CFStrings and as dictionaries with the file's inode; the history-done
 * marker for a stream started in the past; the root's own move with
 * kFSEventStreamCreateFlagWatchRoot; delivery on a run loop and on a
 * dispatch queue after the latency; and the event ids counting up. Run in a
 * home of its own, with TMPDIR there. Flushing makes each batch's contents
 * certain; the latency tests wait for one batch. */
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *root;
static NSMutableArray *heard;
static FSEventStreamEventId lastId;
static BOOL idsUp = YES;

static NSString *flag_names(FSEventStreamEventFlags f)
{
    static const struct {
        FSEventStreamEventFlags flag;
        const char *name;
    } names[] = {
        {kFSEventStreamEventFlagMustScanSubDirs, "MustScanSubDirs"},
        {kFSEventStreamEventFlagHistoryDone, "HistoryDone"},
        {kFSEventStreamEventFlagRootChanged, "RootChanged"},
        {kFSEventStreamEventFlagItemCreated, "Created"},
        {kFSEventStreamEventFlagItemRemoved, "Removed"},
        {kFSEventStreamEventFlagItemInodeMetaMod, "InodeMetaMod"},
        {kFSEventStreamEventFlagItemRenamed, "Renamed"},
        {kFSEventStreamEventFlagItemModified, "Modified"},
        {kFSEventStreamEventFlagItemIsFile, "IsFile"},
        {kFSEventStreamEventFlagItemIsDir, "IsDir"},
        {kFSEventStreamEventFlagItemIsSymlink, "IsSymlink"},
    };
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < sizeof names / sizeof *names; i++)
        if (f & names[i].flag)
            [out addObject:@(names[i].name)];
    return [out count] ? [out componentsJoinedByString:@"|"] : @"None";
}

static NSString *relative(NSString *path)
{
    if ([path hasPrefix:root])
        return [@"<root>" stringByAppendingString:[path substringFromIndex:[root length]]];
    return [path length] ? path : @"\"\"";
}

static void heard_one(NSString *path, FSEventStreamEventFlags flags, FSEventStreamEventId eventId)
{
    if (eventId <= lastId)
        idsUp = NO;
    lastId = eventId;
    [heard addObject:[NSString stringWithFormat:@"%@ %@", relative(path), flag_names(flags)]];
}

static void callback(ConstFSEventStreamRef stream, void *info, size_t n, void *paths,
                     const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[])
{
    for (size_t i = 0; i < n; i++)
        heard_one(@(((const char **)paths)[i]), flags[i], ids[i]);
}

static void callback_cf(ConstFSEventStreamRef stream, void *info, size_t n, void *paths,
                        const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[])
{
    NSArray *list = (__bridge NSArray *)paths;
    for (size_t i = 0; i < n; i++)
        heard_one(list[i], flags[i], ids[i]);
}

static void callback_extended(ConstFSEventStreamRef stream, void *info, size_t n, void *paths,
                              const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[])
{
    NSArray *list = (__bridge NSArray *)paths;
    for (size_t i = 0; i < n; i++) {
        NSDictionary *d = list[i];
        NSString *path = d[(__bridge NSString *)kFSEventStreamEventExtendedDataPathKey];
        unsigned long long inode = [d[(__bridge NSString *)kFSEventStreamEventExtendedFileIDKey] unsignedLongLongValue];
        struct stat st;
        BOOL same = stat([path fileSystemRepresentation], &st) == 0 && st.st_ino == inode;
        heard_one([NSString stringWithFormat:@"%@ (inode %s)", path, same ? "right" : "wrong"], flags[i], ids[i]);
    }
}

static int releases;
static const void *retain_info(const void *info) { return info; }
static void release_info(const void *info) { releases++; }

static void show(const char *what)
{
    printf("%s:\n", what);
    for (NSString *line in heard)
        printf("  %s\n", [line UTF8String]);
    [heard removeAllObjects];
}

static void write_file(NSString *path, const char *text)
{
    int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    write(fd, text, strlen(text));
    close(fd);
}

static FSEventStreamRef make(FSEventStreamCallback cb, NSArray *paths, FSEventStreamEventId since, double latency,
                             FSEventStreamCreateFlags flags)
{
    FSEventStreamContext context = {0, (void *)"info", retain_info, release_info, NULL};
    return FSEventStreamCreate(NULL, cb, &context, (__bridge CFArrayRef)paths, since, latency, flags);
}

int main(void)
{
    @autoreleasepool {
        heard = [NSMutableArray array];
        root = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"watched"] stringByStandardizingPath];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        mkdir([root fileSystemRepresentation], 0755);
        write_file([root stringByAppendingPathComponent:@"old.txt"], "old");
        FSEventStreamEventId first = FSEventsGetCurrentEventId();

        /* by item, flushed */
        FSEventStreamRef s = make(callback, @[ root ], kFSEventStreamEventIdSinceNow, 30,
                                  kFSEventStreamCreateFlagFileEvents);
        printf("not started without a run loop or queue: %d\n", FSEventStreamStart(s));
        FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        printf("started: %d\n", FSEventStreamStart(s));
        NSArray *watched = CFBridgingRelease(FSEventStreamCopyPathsBeingWatched(s));
        printf("watching: %s\n", [relative(watched[0]) UTF8String]);
        write_file([root stringByAppendingPathComponent:@"a.txt"], "hello");
        mkdir([[root stringByAppendingPathComponent:@"sub"] fileSystemRepresentation], 0755);
        FSEventStreamFlushSync(s);
        show("a file and a folder made");
        write_file([root stringByAppendingPathComponent:@"sub/b.txt"], "inside");
        rename([[root stringByAppendingPathComponent:@"a.txt"] fileSystemRepresentation],
               [[root stringByAppendingPathComponent:@"c.txt"] fileSystemRepresentation]);
        chmod([[root stringByAppendingPathComponent:@"old.txt"] fileSystemRepresentation], 0600);
        symlink("c.txt", [[root stringByAppendingPathComponent:@"link"] fileSystemRepresentation]);
        FSEventStreamFlushSync(s);
        show("inside the new folder, a rename, a mode and a link");
        unlink([[root stringByAppendingPathComponent:@"sub/b.txt"] fileSystemRepresentation]);
        rmdir([[root stringByAppendingPathComponent:@"sub"] fileSystemRepresentation]);
        int fd = open([[root stringByAppendingPathComponent:@"c.txt"] fileSystemRepresentation], O_WRONLY | O_APPEND);
        write(fd, " again", 6);
        write(fd, " and again", 10);
        close(fd);
        FSEventStreamFlushSync(s);
        show("removed, and written twice (one event)");
        FSEventStreamFlushSync(s);
        show("nothing more");
        FSEventStreamStop(s);
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);
        printf("context released: %d\n", releases);

        /* by folder, with CFStrings, after the latency on the run loop */
        s = make(callback_cf, @[ root ], kFSEventStreamEventIdSinceNow, 1, kFSEventStreamCreateFlagUseCFTypes);
        FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        FSEventStreamStart(s);
        mkdir([[root stringByAppendingPathComponent:@"deep"] fileSystemRepresentation], 0755);
        FSEventStreamFlushSync(s);
        write_file([root stringByAppendingPathComponent:@"deep/d.txt"], "d");
        write_file([root stringByAppendingPathComponent:@"e.txt"], "e");
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([heard count] < 3 && [until timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, true);
        [heard sortUsingSelector:@selector(compare:)];
        show("by folder, on the run loop");
        FSEventStreamStop(s);
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);

        /* extended data on a dispatch queue */
        s = make(callback_extended, @[ root ], kFSEventStreamEventIdSinceNow, 0.5,
                 kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes |
                     kFSEventStreamCreateFlagUseExtendedData);
        dispatch_queue_t q = dispatch_queue_create("test.fsevents", DISPATCH_QUEUE_SERIAL);
        FSEventStreamSetDispatchQueue(s, q);
        FSEventStreamStart(s);
        write_file([root stringByAppendingPathComponent:@"f.txt"], "f");
        __block NSUInteger got = 0;
        for (int i = 0; i < 100 && !got; i++) {
            usleep(100000);
            dispatch_sync(q, ^{
                got = [heard count];
            });
        }
        for (NSUInteger i = 0; i < [heard count]; i++)
            heard[i] = [heard[i] stringByReplacingOccurrencesOfString:root withString:@"<root>"];
        show("extended data, on a queue");
        FSEventStreamStop(s);
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);

        /* started in the past: only history-done, as no history is kept */
        s = make(callback, @[ root ], first, 0.05, kFSEventStreamCreateFlagNone);
        FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        FSEventStreamStart(s);
        until = [NSDate dateWithTimeIntervalSinceNow:10];
        while (![heard count] && [until timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, true);
        show("since an earlier id");
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);

        /* the root moved */
        NSString *moved = [root stringByAppendingString:@"-moved"];
        [[NSFileManager defaultManager] removeItemAtPath:moved error:NULL];
        s = make(callback, @[ root ], kFSEventStreamEventIdSinceNow, 30, kFSEventStreamCreateFlagWatchRoot);
        FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        FSEventStreamStart(s);
        rename([root fileSystemRepresentation], [moved fileSystemRepresentation]);
        FSEventStreamFlushSync(s);
        show("the root moved");
        FSEventStreamEventId latest = FSEventStreamGetLatestEventId(s);
        FSEventStreamInvalidate(s);
        FSEventStreamRelease(s);

        printf("ids count up: %d, latest is the current one: %d, after the first: %d\n", idsUp,
               latest == FSEventsGetCurrentEventId(), latest > first);
        printf("no stream without paths: %d\n",
               FSEventStreamCreate(NULL, callback, NULL, (__bridge CFArrayRef) @[], kFSEventStreamEventIdSinceNow,
                                   1, 0) == NULL);
        [[NSFileManager defaultManager] removeItemAtPath:moved error:NULL];
    }
    return 0;
}
