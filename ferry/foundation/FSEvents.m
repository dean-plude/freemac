/* SPDX-License-Identifier: GPL-3.0-or-later
 * FSEvents (freemac 1.222, Ferry 0.46.0), written from Apple's public
 * documentation: streams of the changes in folders and everything inside
 * them, heard through this system's inotify. Each stream has an inotify
 * descriptor of its own, with a watch on each folder it covers (a new folder
 * gets one as it appears), read by a dispatch source on a queue of the
 * stream's own. What it hears waits for the stream's latency, coalesced by
 * path, and is then handed to the callback on the stream's run loop or
 * dispatch queue: by folder ("/path/to/folder/"), or with
 * kFSEventStreamCreateFlagFileEvents by item, with flags saying what
 * happened. Event ids count up from one for the whole program; the history
 * from before a stream started isn't kept, so a stream asked to start in the
 * past gets only the history-done marker. */
#import "FInternal.h"
#include <CoreServices/FSEvents.h>
#include <CoreFoundation/CFSocket.h>
#include <pthread.h>
#include <stdatomic.h>
#include <poll.h>
#include <sys/stat.h>
#include <unistd.h>

/* inotify, which passes straight through to this system (src/passthrough.c),
 * with this system's flag values */
int inotify_init1(int flags);
int inotify_add_watch(int fd, const char *path, uint32_t mask);
int inotify_rm_watch(int fd, int wd);
struct inotify_event {
    int wd;
    uint32_t mask, cookie, len;
    char name[];
};
enum {
    IN_MODIFY = 0x2, IN_ATTRIB = 0x4, IN_MOVED_FROM = 0x40, IN_MOVED_TO = 0x80, IN_CREATE = 0x100,
    IN_DELETE = 0x200, IN_DELETE_SELF = 0x400, IN_MOVE_SELF = 0x800, IN_Q_OVERFLOW = 0x4000, IN_IGNORED = 0x8000,
    IN_DONT_FOLLOW = 0x2000000, IN_ISDIR = 0x40000000, IN_CLOEXEC_LINUX = 02000000, IN_NONBLOCK_LINUX = 04000,
};
#define WATCHED (IN_MODIFY | IN_ATTRIB | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_DELETE_SELF | \
                 IN_MOVE_SELF)

static _Atomic FSEventStreamEventId last_id;

struct __FSEventStream {
    _Atomic int refs;
    FSEventStreamCallback callback;
    FSEventStreamContext context;
    NSArray *roots;                  /* the paths asked for, standardized */
    FSEventStreamCreateFlags flags;
    CFTimeInterval latency;
    FSEventStreamEventId since, latest;
    int fd;
    NSMutableDictionary *watches;    /* watch descriptor -> folder */
    dispatch_queue_t queue;          /* reads and the waiting events */
    dispatch_source_t reader;
    dispatch_source_t timer;         /* the latency's end */
    BOOL started, invalid, flushPending;
    NSMutableArray *paths;           /* the events waiting, in order */
    NSMutableDictionary *pending;    /* path -> flags */
    NSMutableDictionary *inodes;     /* path -> inode, for extended data */
    /* where the callback runs */
    CFRunLoopRef runLoop;
    CFRunLoopSourceRef source;
    dispatch_queue_t target;
    pthread_mutex_t lock;            /* the batch ready for the callback */
    NSMutableArray *readyPaths;
    NSMutableArray *readyFlags;
    NSMutableArray *readyInodes;
};

/* runs work on the stream's queue and waits for it, or at once when already there */
static char queue_key;
static void on_queue(FSEventStreamRef s, dispatch_block_t work)
{
    if (dispatch_get_specific(&queue_key) == s)
        work();
    else
        dispatch_sync(s->queue, work);
}

/* ---- watching ---- */

static NSString *standard(NSString *path)
{
    path = [path stringByStandardizingPath];
    while ([path length] > 1 && [path hasSuffix:@"/"])
        path = [path substringToIndex:[path length] - 1];
    return path;
}

static void watch_tree(FSEventStreamRef s, NSString *path)
{
    int wd = inotify_add_watch(s->fd, [path fileSystemRepresentation], WATCHED | IN_DONT_FOLLOW);
    if (wd < 0)
        return;
    s->watches[@(wd)] = path;
    BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] || !dir)
        return;
    struct stat st;
    if (lstat([path fileSystemRepresentation], &st) == 0 && S_ISLNK(st.st_mode))
        return;
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL]) {
        NSString *child = [path stringByAppendingPathComponent:name];
        if (lstat([child fileSystemRepresentation], &st) == 0 && S_ISDIR(st.st_mode))
            watch_tree(s, child);
    }
}

static BOOL is_root(FSEventStreamRef s, NSString *path) { return [s->roots containsObject:path]; }

/* notes one change; the caller is on the stream's queue */
static void note(FSEventStreamRef s, NSString *path, FSEventStreamEventFlags flags, BOOL isDir)
{
    BOOL files = (s->flags & kFSEventStreamCreateFlagFileEvents) != 0;
    if (!files) {
        /* by folder: the folder the change is in, with no item flags */
        if (!(flags & (kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMustScanSubDirs |
                       kFSEventStreamEventFlagHistoryDone)))
            path = isDir && is_root(s, path) ? path : [path stringByDeletingLastPathComponent];
        if ([path length] && ![path hasSuffix:@"/"])
            path = [path stringByAppendingString:@"/"];
        flags &= kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped |
                 kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagHistoryDone;
    } else if (flags & 0xFFFFFF00) {
        struct stat st;
        if (isDir)
            flags |= kFSEventStreamEventFlagItemIsDir;
        else if (lstat([path fileSystemRepresentation], &st) == 0 && S_ISLNK(st.st_mode))
            flags |= kFSEventStreamEventFlagItemIsSymlink;
        else
            flags |= kFSEventStreamEventFlagItemIsFile;
        if (lstat([path fileSystemRepresentation], &st) == 0)
            s->inodes[path] = @((unsigned long long)st.st_ino);
    }
    NSNumber *had = s->pending[path];
    if (!had)
        [s->paths addObject:path];
    s->pending[path] = @([had unsignedIntValue] | flags);
}

static void deliver_ready(FSEventStreamRef s);

/* moves what has waited to the batch the callback gets, and has it run
 * where the stream is scheduled, unless the caller runs it itself */
static void hand_over(FSEventStreamRef s, BOOL notify)
{
    s->flushPending = NO;
    if (![s->paths count] || s->invalid)
        return;
    pthread_mutex_lock(&s->lock);
    for (NSString *p in s->paths) {
        [s->readyPaths addObject:p];
        [s->readyFlags addObject:s->pending[p]];
        [s->readyInodes addObject:s->inodes[p] ?: @0];
    }
    pthread_mutex_unlock(&s->lock);
    [s->paths removeAllObjects];
    [s->pending removeAllObjects];
    [s->inodes removeAllObjects];
    if (!notify)
        return;
    if (s->target) {
        FSEventStreamRetain(s);
        dispatch_async(s->target, ^{
            deliver_ready(s);
            FSEventStreamRelease(s);
        });
    } else if (s->source) {
        CFRunLoopSourceSignal(s->source);
        CFRunLoopWakeUp(s->runLoop);
    }
}

/* after the latency, unless the stream asked not to wait for a first change */
static void schedule_hand_over(FSEventStreamRef s, BOOL first)
{
    if (s->flushPending)
        return;
    if (first && (s->flags & kFSEventStreamCreateFlagNoDefer)) {
        hand_over(s, YES);
        return;
    }
    s->flushPending = YES;
    dispatch_source_set_timer(s->timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s->latency * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
}

/* reads what inotify has heard; on the stream's queue */
static void read_changes(FSEventStreamRef s)
{
    char buf[65536] __attribute__((aligned(8)));
    ssize_t n = read(s->fd, buf, sizeof buf);
    if (n <= 0)
        return;
    BOOL wasEmpty = [s->paths count] == 0;
    for (char *p = buf; p < buf + n;) {
        struct inotify_event *e = (struct inotify_event *)p;
        p += sizeof *e + e->len;
        if (e->mask & IN_Q_OVERFLOW) {
            for (NSString *root in s->roots)
                note(s, root, kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped, YES);
            continue;
        }
        NSString *folder = s->watches[@(e->wd)];
        if (!folder)
            continue;
        if (e->mask & IN_IGNORED) {
            [s->watches removeObjectForKey:@(e->wd)];
            continue;
        }
        BOOL dir = (e->mask & IN_ISDIR) != 0;
        if (e->mask & (IN_DELETE_SELF | IN_MOVE_SELF)) {
            /* a folder's own end is heard by its parent, except a root's */
            if (is_root(s, folder) && (s->flags & kFSEventStreamCreateFlagWatchRoot))
                note(s, folder, kFSEventStreamEventFlagRootChanged, YES);
            continue;
        }
        NSString *path = e->len && e->name[0] ? [folder stringByAppendingPathComponent:@(e->name)] : folder;
        FSEventStreamEventFlags f = 0;
        if (e->mask & IN_CREATE)
            f |= kFSEventStreamEventFlagItemCreated;
        if (e->mask & IN_DELETE)
            f |= kFSEventStreamEventFlagItemRemoved;
        if (e->mask & IN_MODIFY)
            f |= kFSEventStreamEventFlagItemModified;
        if (e->mask & IN_ATTRIB)
            f |= kFSEventStreamEventFlagItemInodeMetaMod;
        if (e->mask & (IN_MOVED_FROM | IN_MOVED_TO))
            f |= kFSEventStreamEventFlagItemRenamed;
        /* a folder made or moved in is watched too */
        if (dir && (e->mask & (IN_CREATE | IN_MOVED_TO)))
            watch_tree(s, path);
        note(s, path, f, dir && !e->len ? YES : dir);
    }
    if ([s->paths count])
        schedule_hand_over(s, wasEmpty);
}

/* ---- the callback ---- */

static void deliver_ready(FSEventStreamRef s)
{
    pthread_mutex_lock(&s->lock);
    NSArray *paths = [[s->readyPaths copy] autorelease], *flags = [[s->readyFlags copy] autorelease],
            *inodes = [[s->readyInodes copy] autorelease];
    [s->readyPaths removeAllObjects];
    [s->readyFlags removeAllObjects];
    [s->readyInodes removeAllObjects];
    pthread_mutex_unlock(&s->lock);
    size_t n = [paths count];
    if (!n || s->invalid || !s->callback)
        return;
    FSEventStreamEventFlags *f = calloc(n, sizeof *f);
    FSEventStreamEventId *ids = calloc(n, sizeof *ids);
    const char **cpaths = calloc(n, sizeof *cpaths);
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:n];
    for (size_t i = 0; i < n; i++) {
        f[i] = [flags[i] unsignedIntValue];
        ids[i] = ++last_id;
        cpaths[i] = [paths[i] fileSystemRepresentation];
        if (s->flags & kFSEventStreamCreateFlagUseExtendedData)
            [objects addObject:@{@"path" : paths[i], @"fileID" : inodes[i]}];
        else
            [objects addObject:paths[i]];
    }
    s->latest = ids[n - 1];
    void *eventPaths = (s->flags & kFSEventStreamCreateFlagUseCFTypes) ? (void *)objects : (void *)cpaths;
    @autoreleasepool {
        s->callback(s, s->context.info, n, eventPaths, f, ids);
    }
    free(f);
    free(ids);
    free(cpaths);
}

static void perform(void *info) { deliver_ready(info); }

/* ---- the calls ---- */

FSEventStreamRef FSEventStreamCreate(CFAllocatorRef allocator, FSEventStreamCallback callback,
                                     FSEventStreamContext *context, CFArrayRef pathsToWatch,
                                     FSEventStreamEventId sinceWhen, CFTimeInterval latency,
                                     FSEventStreamCreateFlags flags)
{
    if (!callback || ![(NSArray *)pathsToWatch count])
        return NULL;
    FSEventStreamRef s = calloc(1, sizeof *s);
    s->refs = 1;
    s->callback = callback;
    if (context) {
        s->context = *context;
        if (context->retain && context->info)
            s->context.info = (void *)context->retain(context->info);
    }
    NSMutableArray *roots = [NSMutableArray array];
    for (NSString *p in (NSArray *)pathsToWatch)
        [roots addObject:standard(p)];
    s->roots = [roots copy];
    s->flags = flags;
    s->latency = latency > 0 ? latency : 0;
    s->since = sinceWhen;
    s->latest = sinceWhen == kFSEventStreamEventIdSinceNow ? last_id : sinceWhen;
    s->fd = -1;
    s->watches = [[NSMutableDictionary alloc] init];
    s->paths = [[NSMutableArray alloc] init];
    s->pending = [[NSMutableDictionary alloc] init];
    s->inodes = [[NSMutableDictionary alloc] init];
    s->readyPaths = [[NSMutableArray alloc] init];
    s->readyFlags = [[NSMutableArray alloc] init];
    s->readyInodes = [[NSMutableArray alloc] init];
    pthread_mutex_init(&s->lock, NULL);
    s->queue = dispatch_queue_create("ferry.fsevents", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(s->queue, &queue_key, s, NULL);
    return s;
}

FSEventStreamRef FSEventStreamCreateRelativeToDevice(CFAllocatorRef allocator, FSEventStreamCallback callback,
                                                     FSEventStreamContext *context, dev_t device, CFArrayRef paths,
                                                     FSEventStreamEventId sinceWhen, CFTimeInterval latency,
                                                     FSEventStreamCreateFlags flags)
{
    /* the paths are taken from the root of the file system */
    NSMutableArray *absolute = [NSMutableArray array];
    for (NSString *p in (NSArray *)paths)
        [absolute addObject:[p hasPrefix:@"/"] ? p : [@"/" stringByAppendingString:p]];
    return FSEventStreamCreate(allocator, callback, context, (CFArrayRef)absolute, sinceWhen, latency, flags);
}

FSEventStreamEventId FSEventStreamGetLatestEventId(ConstFSEventStreamRef s) { return s ? s->latest : 0; }
dev_t FSEventStreamGetDeviceBeingWatched(ConstFSEventStreamRef s) { return 0; }
CFArrayRef FSEventStreamCopyPathsBeingWatched(ConstFSEventStreamRef s)
{
    return s ? (CFArrayRef)[s->roots copy] : NULL;
}
FSEventStreamEventId FSEventsGetCurrentEventId(void) { return last_id; }
CFUUIDRef FSEventsCopyUUIDForDevice(dev_t dev) { return NULL; }
FSEventStreamEventId FSEventsGetLastEventIdForDeviceBeforeTime(dev_t dev, CFAbsoluteTime time) { return last_id; }
Boolean FSEventsPurgeEventsForDeviceUpToEventId(dev_t dev, FSEventStreamEventId eventId) { return false; }

void FSEventStreamRetain(FSEventStreamRef s)
{
    if (s)
        s->refs++;
}

void FSEventStreamRelease(FSEventStreamRef s)
{
    if (!s || --s->refs > 0)
        return;
    FSEventStreamInvalidate(s);
    if (s->source)
        CFRelease(s->source);
    if (s->target)
        dispatch_release(s->target);
    if (s->context.release && s->context.info)
        s->context.release(s->context.info);
    [s->roots release];
    [s->watches release];
    [s->paths release];
    [s->pending release];
    [s->inodes release];
    [s->readyPaths release];
    [s->readyFlags release];
    [s->readyInodes release];
    pthread_mutex_destroy(&s->lock);
    dispatch_release(s->queue);
    free(s);
}

void FSEventStreamScheduleWithRunLoop(FSEventStreamRef s, CFRunLoopRef runLoop, CFStringRef mode)
{
    if (!s || !runLoop)
        return;
    if (!s->source) {
        CFRunLoopSourceContext c = {0};
        c.info = s;
        c.perform = perform;
        s->source = CFRunLoopSourceCreate(NULL, 0, &c);
    }
    s->runLoop = runLoop;
    CFRunLoopAddSource(runLoop, s->source, mode);
}

void FSEventStreamUnscheduleFromRunLoop(FSEventStreamRef s, CFRunLoopRef runLoop, CFStringRef mode)
{
    if (s && s->source && runLoop)
        CFRunLoopRemoveSource(runLoop, s->source, mode);
}

void FSEventStreamSetDispatchQueue(FSEventStreamRef s, dispatch_queue_t q)
{
    if (!s)
        return;
    if (q)
        dispatch_retain(q);
    if (s->target)
        dispatch_release(s->target);
    s->target = q;
}

Boolean FSEventStreamStart(FSEventStreamRef s)
{
    if (!s || s->invalid || (!s->source && !s->target))
        return false;
    if (s->started)
        return true;
    __block BOOL ok = YES;
    on_queue(s, ^{
        if (s->fd < 0) {
            s->fd = inotify_init1(IN_CLOEXEC_LINUX | IN_NONBLOCK_LINUX);
            if (s->fd < 0) {
                ok = NO;
                return;
            }
            for (NSString *root in s->roots)
                watch_tree(s, root);
            s->reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)s->fd, 0, s->queue);
            dispatch_source_set_event_handler(s->reader, ^{ read_changes(s); });
            int fd = s->fd;
            dispatch_source_set_cancel_handler(s->reader, ^{ close(fd); });
            s->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, s->queue);
            dispatch_source_set_event_handler(s->timer, ^{
                if (s->flushPending)
                    hand_over(s, YES);
            });
            dispatch_resume(s->timer);
        }
        dispatch_resume(s->reader);
        /* no history is kept: a stream asked to start in the past hears that it's done */
        if (s->since != kFSEventStreamEventIdSinceNow) {
            note(s, @"", kFSEventStreamEventFlagHistoryDone, NO);
            s->since = kFSEventStreamEventIdSinceNow;
            hand_over(s, YES);
        }
    });
    s->started = ok;
    return ok;
}

/* waits for what inotify already has */
static void drain(FSEventStreamRef s)
{
    struct pollfd p = {s->fd, POLLIN, 0};
    while (s->fd >= 0 && poll(&p, 1, 0) > 0 && (p.revents & POLLIN))
        read_changes(s);
}

FSEventStreamEventId FSEventStreamFlushAsync(FSEventStreamRef s)
{
    if (!s || !s->started)
        return s ? s->latest : 0;
    on_queue(s, ^{
        drain(s);
        hand_over(s, YES);
    });
    return last_id + (FSEventStreamEventId)[s->readyPaths count];
}

void FSEventStreamFlushSync(FSEventStreamRef s)
{
    if (!s || !s->started)
        return;
    on_queue(s, ^{
        drain(s);
        hand_over(s, NO);
    });
    /* the callback runs before this returns */
    deliver_ready(s);
}

void FSEventStreamStop(FSEventStreamRef s)
{
    if (!s || !s->started)
        return;
    on_queue(s, ^{
        dispatch_suspend(s->reader);
        s->flushPending = NO;
        [s->paths removeAllObjects];
        [s->pending removeAllObjects];
    });
    s->started = NO;
}

void FSEventStreamInvalidate(FSEventStreamRef s)
{
    if (!s || s->invalid)
        return;
    if (s->started)
        FSEventStreamStop(s);
    s->invalid = YES;
    if (s->source)
        CFRunLoopSourceInvalidate(s->source);
    if (s->reader) {
        /* a suspended source is resumed to be cancelled */
        dispatch_source_cancel(s->reader);
        dispatch_resume(s->reader);
        dispatch_release(s->reader);
        s->reader = NULL;
        s->fd = -1;
        dispatch_source_cancel(s->timer);
        dispatch_release(s->timer);
        s->timer = NULL;
    }
}

CFStringRef FSEventStreamCopyDescription(ConstFSEventStreamRef s)
{
    if (!s)
        return NULL;
    NSString *d = [NSString stringWithFormat:@"FSEventStreamRef@%p: paths = %@, latency = %g, flags = 0x%x, "
                                             @"latestEventId = %llu",
                                             s, [s->roots componentsJoinedByString:@", "], s->latency,
                                             (unsigned)s->flags, (unsigned long long)s->latest];
    return (CFStringRef)[d copy];
}

void FSEventStreamShow(ConstFSEventStreamRef s)
{
    CFStringRef d = FSEventStreamCopyDescription(s);
    if (d) {
        fprintf(stderr, "%s\n", [(NSString *)d UTF8String]);
        CFRelease(d);
    }
}

Boolean FSEventStreamSetExclusionPaths(FSEventStreamRef s, CFArrayRef paths) { return s != NULL; }
