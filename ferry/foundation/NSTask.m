/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSTask, NSPipe and NSFileHandle.
 *
 * A task is a child process of this system: the program a Mac app names
 * (/bin/sh, /usr/bin/env, /usr/bin/git...) is this system's program of that
 * name, run as it is. A Mac program (a Mach-O file, such as a helper tool
 * inside an app bundle) is run through Ferry itself.
 *
 * Ferry runs a program on one thread, so nothing happens behind the
 * program's back: a child's exit is noticed, and a file handle's background
 * reads and readability handler are served, from the run loop (which waits
 * on the handles' descriptors) and from a small dispatch timer that runs
 * while any task is running, so that dispatch_semaphore_wait and the like,
 * which run dispatch's work but not the run loop, see them too.
 * terminationHandler, NSTaskDidTerminateNotification and the handles'
 * notifications all arrive on that one thread.
 *
 * Written from Apple's public documentation of these classes; no Apple code
 * was used. */
#import "FInternal.h"
#include <dirent.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char ***_NSGetEnviron(void);
void FerryRunLoopAddDescriptor(int fd, void (*callback)(int, void *), void *ctx);
void FerryRunLoopRemoveDescriptor(int fd);

NSString *const NSFileHandleReadCompletionNotification = @"NSFileHandleReadCompletionNotification";
NSString *const NSFileHandleReadToEndOfFileCompletionNotification = @"NSFileHandleReadToEndOfFileCompletionNotification";
NSString *const NSFileHandleConnectionAcceptedNotification = @"NSFileHandleConnectionAcceptedNotification";
NSString *const NSFileHandleDataAvailableNotification = @"NSFileHandleDataAvailableNotification";
NSString *const NSFileHandleNotificationDataItem = @"NSFileHandleNotificationDataItem";
NSString *const NSFileHandleNotificationFileHandleItem = @"NSFileHandleNotificationFileHandleItem";
NSString *const NSFileHandleNotificationMonitorModes = @"NSFileHandleNotificationMonitorModes";
NSString *const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";

#define CHUNK 65536

enum { BG_NONE, BG_READ, BG_READ_TO_END, BG_WAIT };

@interface NSFileHandle () {
@public
    int _fd;
    BOOL _closeOnDealloc, _watched;
    int _background;
    NSMutableData *_collected;
    void (^_readabilityHandler)(NSFileHandle *);
    void (^_writeabilityHandler)(NSFileHandle *);
}
- (void)_serve;
@end

static void start_pump(void);

/* ---- watching descriptors --------------------------------------------------------- */

static NSMutableArray *watched_handles; /* retained while watched */

static void handle_ready(int fd, void *ctx) { [(NSFileHandle *)ctx _serve]; }

static void update_watch(NSFileHandle *h)
{
    BOOL want = h->_fd >= 0 && (h->_background != BG_NONE || h->_readabilityHandler);
    if (want == h->_watched)
        return;
    h->_watched = want;
    if (!watched_handles)
        watched_handles = [[NSMutableArray alloc] init];
    if (want) {
        [watched_handles addObject:h];
        FerryRunLoopAddDescriptor(h->_fd, handle_ready, h);
    } else {
        FerryRunLoopRemoveDescriptor(h->_fd);
        [h retain];
        [watched_handles removeObjectIdenticalTo:h];
        [h autorelease];
    }
}

static BOOL readable_now(int fd)
{
    struct pollfd p = {fd, POLLIN, 0};
    return poll(&p, 1, 0) > 0;
}

static NSError *posix_error(int err)
{
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil];
}

/* ---- NSFileHandle ------------------------------------------------------------------- */

@implementation NSFileHandle

static NSFileHandle *standard_handle(int fd, NSFileHandle **slot)
{
    if (!*slot)
        *slot = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:NO];
    return *slot;
}
+ (NSFileHandle *)fileHandleWithStandardInput
{
    static NSFileHandle *h;
    return standard_handle(0, &h);
}
+ (NSFileHandle *)fileHandleWithStandardOutput
{
    static NSFileHandle *h;
    return standard_handle(1, &h);
}
+ (NSFileHandle *)fileHandleWithStandardError
{
    static NSFileHandle *h;
    return standard_handle(2, &h);
}
+ (NSFileHandle *)fileHandleWithNullDevice
{
    static NSFileHandle *h;
    if (!h) {
        int fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        h = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    }
    return h;
}

static id open_handle(Class cls, NSString *path, int flags, NSError **error)
{
    if (!path) {
        FSetError(error, FPosixError(ENOENT, path));
        return nil;
    }
    int fd = open([path fileSystemRepresentation], flags | O_CLOEXEC);
    if (fd < 0) {
        FSetError(error, FPosixError(errno, path));
        return nil;
    }
    return [[[cls alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease];
}
+ (instancetype)fileHandleForReadingAtPath:(NSString *)path { return open_handle(self, path, O_RDONLY, NULL); }
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path { return open_handle(self, path, O_WRONLY, NULL); }
+ (instancetype)fileHandleForUpdatingAtPath:(NSString *)path { return open_handle(self, path, O_RDWR, NULL); }
+ (instancetype)fileHandleForReadingFromURL:(NSURL *)url error:(NSError **)error
{
    return open_handle(self, [url path], O_RDONLY, error);
}
+ (instancetype)fileHandleForWritingToURL:(NSURL *)url error:(NSError **)error
{
    return open_handle(self, [url path], O_WRONLY, error);
}
+ (instancetype)fileHandleForUpdatingURL:(NSURL *)url error:(NSError **)error
{
    return open_handle(self, [url path], O_RDWR, error);
}
- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeopt
{
    if (!(self = [super init]))
        return nil;
    _fd = fd;
    _closeOnDealloc = closeopt;
    return self;
}
- (instancetype)initWithFileDescriptor:(int)fd { return [self initWithFileDescriptor:fd closeOnDealloc:NO]; }
- (instancetype)init { return [self initWithFileDescriptor:-1 closeOnDealloc:NO]; }
- (void)dealloc
{
    if (_closeOnDealloc && _fd >= 0)
        close(_fd);
    [_collected release];
    [_readabilityHandler release];
    [_writeabilityHandler release];
    [super dealloc];
}
- (int)fileDescriptor { return _fd; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSConcreteFileHandle: %p>", self];
}

__attribute__((noreturn)) static void fail(SEL sel, int err)
{
    FRaise(NSFileHandleOperationException, @"*** -[NSConcreteFileHandle %s]: %s", sel_getName(sel), strerror(err));
}

/* One read() of up to n bytes, retried when interrupted; -1 on error. */
static ssize_t read_some(int fd, void *buf, size_t n)
{
    for (;;) {
        ssize_t r = read(fd, buf, n);
        if (r >= 0 || errno != EINTR) {
            if (r < 0 && errno == EAGAIN) {
                struct pollfd p = {fd, POLLIN, 0};
                poll(&p, 1, -1);
                continue;
            }
            return r;
        }
    }
}

/* Reads until length bytes or the end; NO (with errno) on an error. */
static NSMutableData *read_up_to(int fd, NSUInteger length, int *err)
{
    NSMutableData *data = [NSMutableData data];
    char *buf = malloc(CHUNK);
    *err = 0;
    while ([data length] < length) {
        NSUInteger want = length - [data length];
        ssize_t r = read_some(fd, buf, want < CHUNK ? want : CHUNK);
        if (r < 0) {
            *err = errno;
            break;
        }
        if (r == 0)
            break;
        [data appendBytes:buf length:r];
    }
    free(buf);
    return data;
}

- (NSData *)readDataToEndOfFile { return [self readDataOfLength:NSUIntegerMax]; }
- (NSData *)readDataOfLength:(NSUInteger)length
{
    int err;
    NSData *d = read_up_to(_fd, length, &err);
    if (err)
        fail(_cmd, err);
    return d;
}
- (NSData *)readDataToEndOfFileAndReturnError:(NSError **)error
{
    return [self readDataUpToLength:NSUIntegerMax error:error];
}
- (NSData *)readDataUpToLength:(NSUInteger)length error:(NSError **)error
{
    int err;
    NSData *d = read_up_to(_fd, length, &err);
    if (err) {
        FSetError(error, posix_error(err));
        return nil;
    }
    return d;
}
/* A file: the rest of it. A pipe, socket or terminal: what is there now,
 * waiting for some if there is none; empty at the end. */
- (NSData *)availableData
{
    struct stat st;
    if (fstat(_fd, &st) < 0)
        fail(_cmd, errno);
    if (S_ISREG(st.st_mode))
        return [self readDataToEndOfFile];
    char *buf = malloc(CHUNK);
    ssize_t r = read_some(_fd, buf, CHUNK);
    if (r < 0) {
        int err = errno;
        free(buf);
        fail(_cmd, err);
    }
    return [NSData dataWithBytesNoCopy:buf length:r freeWhenDone:YES];
}
static int write_all(int fd, NSData *data)
{
    const char *p = [data bytes];
    NSUInteger left = [data length];
    while (left) {
        ssize_t w = write(fd, p, left);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN) {
                struct pollfd pf = {fd, POLLOUT, 0};
                poll(&pf, 1, -1);
                continue;
            }
            return errno;
        }
        p += w;
        left -= w;
    }
    return 0;
}
- (void)writeData:(NSData *)data
{
    int err = write_all(_fd, data);
    if (err)
        fail(_cmd, err);
}
- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    int err = write_all(_fd, data);
    if (err)
        FSetError(error, posix_error(err));
    return !err;
}

- (unsigned long long)offsetInFile
{
    off_t o = lseek(_fd, 0, SEEK_CUR);
    if (o < 0)
        fail(_cmd, errno);
    return o;
}
- (unsigned long long)seekToEndOfFile
{
    off_t o = lseek(_fd, 0, SEEK_END);
    if (o < 0)
        fail(_cmd, errno);
    return o;
}
- (void)seekToFileOffset:(unsigned long long)offset
{
    if (lseek(_fd, (off_t)offset, SEEK_SET) < 0)
        fail(_cmd, errno);
}
- (void)truncateFileAtOffset:(unsigned long long)offset
{
    if (ftruncate(_fd, (off_t)offset) < 0 || lseek(_fd, (off_t)offset, SEEK_SET) < 0)
        fail(_cmd, errno);
}
- (void)synchronizeFile
{
    if (fsync(_fd) < 0 && errno != EINVAL)
        fail(_cmd, errno);
}
- (void)closeFile
{
    if (_fd < 0)
        return;
    [_readabilityHandler release];
    _readabilityHandler = nil;
    _background = BG_NONE;
    update_watch(self);
    close(_fd);
    _fd = -1;
}
static BOOL answer(int rc, NSError **error)
{
    if (rc < 0)
        FSetError(error, posix_error(errno));
    return rc >= 0;
}
- (BOOL)getOffset:(unsigned long long *)offset error:(NSError **)error
{
    off_t o = lseek(_fd, 0, SEEK_CUR);
    if (o >= 0 && offset)
        *offset = o;
    return answer(o < 0 ? -1 : 0, error);
}
- (BOOL)seekToEndReturningOffset:(unsigned long long *)offset error:(NSError **)error
{
    off_t o = lseek(_fd, 0, SEEK_END);
    if (o >= 0 && offset)
        *offset = o;
    return answer(o < 0 ? -1 : 0, error);
}
- (BOOL)seekToOffset:(unsigned long long)offset error:(NSError **)error
{
    return answer(lseek(_fd, (off_t)offset, SEEK_SET) < 0 ? -1 : 0, error);
}
- (BOOL)truncateAtOffset:(unsigned long long)offset error:(NSError **)error
{
    return answer(ftruncate(_fd, (off_t)offset) < 0 || lseek(_fd, (off_t)offset, SEEK_SET) < 0 ? -1 : 0, error);
}
- (BOOL)synchronizeAndReturnError:(NSError **)error
{
    return answer(fsync(_fd) < 0 && errno != EINVAL ? -1 : 0, error);
}
- (BOOL)closeAndReturnError:(NSError **)error
{
    if (_fd < 0) {
        FSetError(error, posix_error(EBADF));
        return NO;
    }
    [self closeFile];
    return YES;
}

/* ---- in the background ---- */

- (void (^)(NSFileHandle *))readabilityHandler { return _readabilityHandler; }
- (void)setReadabilityHandler:(void (^)(NSFileHandle *))handler
{
    id copy = [handler copy];
    [_readabilityHandler release];
    _readabilityHandler = copy;
    update_watch(self);
}
/* Kept; Ferry's run loop waits only for descriptors to become readable, so
 * it is called once, when set, and after each write the program makes
 * through the handle isn't followed. */
- (void (^)(NSFileHandle *))writeabilityHandler { return _writeabilityHandler; }
- (void)setWriteabilityHandler:(void (^)(NSFileHandle *))handler
{
    id copy = [handler copy];
    [_writeabilityHandler release];
    _writeabilityHandler = copy;
    if (copy) {
        [self retain];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (self->_writeabilityHandler && self->_fd >= 0)
              self->_writeabilityHandler(self);
          [self release];
        });
    }
}
- (void)startBackground:(int)kind
{
    if (_background != BG_NONE)
        FRaise(NSFileHandleOperationException, @"*** -[NSConcreteFileHandle %s]: already reading in the background",
               sel_getName(_cmd));
    if (_fd < 0)
        fail(_cmd, EBADF);
    _background = kind;
    if (kind == BG_READ_TO_END) {
        [_collected release];
        _collected = [[NSMutableData alloc] init];
    }
    update_watch(self);
}
- (void)readInBackgroundAndNotify { [self startBackground:BG_READ]; }
- (void)readInBackgroundAndNotifyForModes:(NSArray *)modes { [self startBackground:BG_READ]; }
- (void)readToEndOfFileInBackgroundAndNotify { [self startBackground:BG_READ_TO_END]; }
- (void)readToEndOfFileInBackgroundAndNotifyForModes:(NSArray *)modes { [self startBackground:BG_READ_TO_END]; }
- (void)waitForDataInBackgroundAndNotify { [self startBackground:BG_WAIT]; }
- (void)waitForDataInBackgroundAndNotifyForModes:(NSArray *)modes { [self startBackground:BG_WAIT]; }

- (void)post:(NSString *)name data:(NSData *)data
{
    NSDictionary *info = data ? [NSDictionary dictionaryWithObject:data forKey:NSFileHandleNotificationDataItem] : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:info];
}

/* The descriptor is (or may be) readable: serve what waits on it. */
- (void)_serve
{
    if (_fd < 0 || !readable_now(_fd))
        return;
    [self retain];
    int kind = _background;
    if (kind == BG_READ || kind == BG_WAIT) {
        _background = BG_NONE;
        update_watch(self);
        if (kind == BG_READ) {
            char *buf = malloc(CHUNK);
            ssize_t r = read_some(_fd, buf, CHUNK);
            NSData *d = [NSData dataWithBytesNoCopy:buf length:r > 0 ? r : 0 freeWhenDone:YES];
            [self post:NSFileHandleReadCompletionNotification data:d];
        } else {
            [self post:NSFileHandleDataAvailableNotification data:nil];
        }
    } else if (kind == BG_READ_TO_END) {
        char *buf = malloc(CHUNK);
        ssize_t r = read_some(_fd, buf, CHUNK);
        if (r > 0)
            [_collected appendBytes:buf length:r];
        free(buf);
        if (r <= 0) {
            NSData *all = [_collected autorelease];
            _collected = nil;
            _background = BG_NONE;
            update_watch(self);
            [self post:NSFileHandleReadToEndOfFileCompletionNotification data:all];
        }
    } else if (_readabilityHandler) {
        void (^h)(NSFileHandle *) = [_readabilityHandler retain];
        @autoreleasepool {
            h(self);
        }
        [h release];
    }
    [self release];
}
@end

/* ---- NSPipe ------------------------------------------------------------------------- */

@implementation NSPipe {
    NSFileHandle *_read, *_write;
}
+ (NSPipe *)pipe { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    int fds[2];
    if (pipe(fds) < 0) {
        [self release];
        return nil;
    }
    fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    _read = [[NSFileHandle alloc] initWithFileDescriptor:fds[0] closeOnDealloc:YES];
    _write = [[NSFileHandle alloc] initWithFileDescriptor:fds[1] closeOnDealloc:YES];
    return self;
}
- (void)dealloc
{
    [_read release];
    [_write release];
    [super dealloc];
}
- (NSFileHandle *)fileHandleForReading { return _read; }
- (NSFileHandle *)fileHandleForWriting { return _write; }
@end

/* ---- NSTask ------------------------------------------------------------------------- */

@interface NSTask () {
@public
    NSURL *_url;
    NSArray *_arguments;
    NSDictionary *_environment;
    NSString *_directory;
    id _stdin, _stdout, _stderr;
    pid_t _pid;
    BOOL _launched, _running;
    int _status, _suspends;
    NSTaskTerminationReason _reason;
    void (^_terminationHandler)(NSTask *);
    NSInteger _qos;
}
@end

static NSMutableArray *running_tasks; /* retained while running */

/* Notes an exited child; YES if it had. */
static BOOL reap(NSTask *t)
{
    if (!t->_running)
        return NO;
    int st = 0;
    pid_t r = waitpid(t->_pid, &st, WNOHANG);
    if (r == 0 || (r < 0 && errno == EINTR))
        return NO;
    t->_running = NO;
    if (r < 0) { /* reaped by someone else: its status is lost */
        t->_status = 0;
        t->_reason = NSTaskTerminationReasonExit;
    } else if (WIFSIGNALED(st)) {
        t->_status = WTERMSIG(st);
        t->_reason = NSTaskTerminationReasonUncaughtSignal;
    } else {
        t->_status = WEXITSTATUS(st);
        t->_reason = NSTaskTerminationReasonExit;
    }
    [t retain];
    [running_tasks removeObjectIdenticalTo:t];
    void (^h)(NSTask *) = [t->_terminationHandler retain];
    @autoreleasepool {
        if (h)
            h(t);
        [[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification object:t];
    }
    [h release];
    [t autorelease];
    return YES;
}

/* While tasks run: look for their exits, and serve watched handles, on
 * dispatch's main queue, every few milliseconds (sooner after something
 * happened). */
static BOOL pump_armed;
static unsigned pump_ms = 1;

static void pump(void *ctx)
{
    pump_armed = NO;
    BOOL happened = NO;
    @autoreleasepool {
        NSArray *handles = [[watched_handles copy] autorelease];
        for (NSFileHandle *h in handles)
            if (h->_watched && h->_fd >= 0 && readable_now(h->_fd)) {
                [h _serve];
                happened = YES;
            }
        NSArray *tasks = [[running_tasks copy] autorelease];
        for (NSTask *t in tasks)
            happened |= reap(t);
    }
    pump_ms = happened ? 1 : pump_ms * 2 > 25 ? 25 : pump_ms * 2;
    if ([running_tasks count])
        start_pump();
}

static void start_pump(void)
{
    if (pump_armed)
        return;
    pump_armed = YES;
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)pump_ms * NSEC_PER_MSEC), dispatch_get_main_queue(),
                     NULL, pump);
}

@implementation NSTask
- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _qos = -1;
    return self;
}
- (void)dealloc
{
    [_url release];
    [_arguments release];
    [_environment release];
    [_directory release];
    [_stdin release];
    [_stdout release];
    [_stderr release];
    [_terminationHandler release];
    [super dealloc];
}

#define COPY_SETTER(name, ivar)                                                                                        \
    -(void)name : (id)value                                                                                            \
    {                                                                                                                  \
        id copy = [value copy];                                                                                        \
        [ivar release];                                                                                                \
        ivar = copy;                                                                                                   \
    }
#define RETAIN_SETTER(name, ivar)                                                                                      \
    -(void)name : (id)value                                                                                            \
    {                                                                                                                  \
        [value retain];                                                                                                \
        [ivar release];                                                                                                \
        ivar = value;                                                                                                  \
    }
- (NSURL *)executableURL { return _url; }
COPY_SETTER(setExecutableURL, _url)
- (NSString *)launchPath { return [_url path]; }
- (void)setLaunchPath:(NSString *)path { [self setExecutableURL:path ? [NSURL fileURLWithPath:path] : nil]; }
- (NSArray *)arguments { return _arguments; }
COPY_SETTER(setArguments, _arguments)
- (NSDictionary *)environment { return _environment; }
COPY_SETTER(setEnvironment, _environment)
- (NSString *)currentDirectoryPath
{
    if (_directory)
        return _directory;
    return [[NSFileManager defaultManager] currentDirectoryPath];
}
COPY_SETTER(setCurrentDirectoryPath, _directory)
- (NSURL *)currentDirectoryURL { return [NSURL fileURLWithPath:[self currentDirectoryPath] isDirectory:YES]; }
- (void)setCurrentDirectoryURL:(NSURL *)url { [self setCurrentDirectoryPath:[url path]]; }
- (id)standardInput { return _stdin; }
RETAIN_SETTER(setStandardInput, _stdin)
- (id)standardOutput { return _stdout; }
RETAIN_SETTER(setStandardOutput, _stdout)
- (id)standardError { return _stderr; }
RETAIN_SETTER(setStandardError, _stderr)
- (void (^)(NSTask *))terminationHandler { return _terminationHandler; }
- (void)setTerminationHandler:(void (^)(NSTask *))handler
{
    id copy = [handler copy];
    [_terminationHandler release];
    _terminationHandler = copy;
}
- (NSInteger)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSInteger)q { _qos = q; }

/* The descriptor a standard stream should become in the child, or -1 to
 * keep the parent's. */
static int child_fd(id io, BOOL input)
{
    if ([io isKindOfClass:[NSPipe class]])
        io = input ? [io fileHandleForReading] : [io fileHandleForWriting];
    if ([io isKindOfClass:[NSFileHandle class]])
        return [(NSFileHandle *)io fileDescriptor];
    return -1;
}

static BOOL is_mach_o(const char *path)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return NO;
    unsigned char m[4];
    ssize_t r = read(fd, m, 4);
    close(fd);
    if (r != 4)
        return NO;
    uint32_t le = m[0] | m[1] << 8 | m[2] << 16 | (uint32_t)m[3] << 24;
    return le == 0xfeedfacf || le == 0xfeedface || le == 0xbebafeca; /* 64-bit, 32-bit, universal */
}

static NSError *launch_error(NSInteger code, NSString *path, int err)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (path)
        [info setObject:path forKey:NSFilePathErrorKey];
    if (err)
        [info setObject:posix_error(err) forKey:NSUnderlyingErrorKey];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

- (BOOL)launchAndReturnError:(NSError **)error
{
    if (_launched)
        FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask launchAndReturnError:]: task already launched");
    NSString *path = [_url path];
    if (!path || access([path fileSystemRepresentation], X_OK) < 0) {
        int err = path ? errno : ENOENT;
        FSetError(error, launch_error(err == ENOENT || err == ENOTDIR ? NSFileNoSuchFileError
                                                                     : NSFileReadNoPermissionError,
                                      path, err));
        return NO;
    }
    struct stat st;
    if (stat([path fileSystemRepresentation], &st) == 0 && S_ISDIR(st.st_mode)) {
        FSetError(error, launch_error(NSFileReadNoPermissionError, path, EACCES));
        return NO;
    }
    BOOL isDir = NO;
    if (_directory && !([[NSFileManager defaultManager] fileExistsAtPath:_directory isDirectory:&isDir] && isDir)) {
        FSetError(error, launch_error(NSFileNoSuchFileError, _directory, ENOENT));
        return NO;
    }

    /* Everything the child needs, made before the fork. */
    BOOL mac = is_mach_o([path fileSystemRepresentation]);
    NSUInteger nargs = [_arguments count];
    char **argv = calloc(nargs + 4, sizeof *argv);
    int a = 0;
    if (mac) {
        argv[a++] = strdup("ferry");
        argv[a++] = strdup("--");
    }
    argv[a++] = strdup([path fileSystemRepresentation]);
    for (NSString *s in _arguments)
        argv[a++] = strdup([[s description] UTF8String]);
    char **envp, **made_env = NULL;
    if (_environment) {
        made_env = calloc([_environment count] + 1, sizeof *made_env);
        int e = 0;
        for (NSString *k in _environment)
            made_env[e++] = strdup([[NSString stringWithFormat:@"%@=%@", k, [_environment objectForKey:k]] UTF8String]);
        envp = made_env;
    } else {
        envp = *_NSGetEnviron();
    }
    const char *exe = mac ? "/proc/self/exe" : argv[0];
    char *dir = _directory ? strdup([_directory fileSystemRepresentation]) : NULL;
    int src[3] = {child_fd(_stdin, YES), child_fd(_stdout, NO), child_fd(_stderr, NO)};
    int report[2];
    if (pipe(report) == 0) {
        fcntl(report[0], F_SETFD, FD_CLOEXEC);
        fcntl(report[1], F_SETFD, FD_CLOEXEC);
    } else {
        report[0] = report[1] = -1;
    }

    fflush(NULL); /* what the program printed but hasn't written yet isn't the child's to write */
    pid_t pid = fork();
    if (pid == 0) {
        int tmp[3];
        for (int i = 0; i < 3; i++)
            tmp[i] = src[i] >= 0 ? fcntl(src[i], F_DUPFD, 3) : -1;
        for (int i = 0; i < 3; i++)
            if (tmp[i] >= 0)
                dup2(tmp[i], i);
        for (int i = 0; i < 3; i++)
            fcntl(i, F_SETFD, 0);
        sigset_t none;
        sigemptyset(&none);
        sigprocmask(SIG_SETMASK, &none, NULL);
        signal(SIGPIPE, SIG_DFL);
        if (dir && chdir(dir) < 0) {
            int err = errno;
            if (report[1] >= 0)
                write(report[1], &err, sizeof err);
            _exit(127);
        }
        /* everything but the three streams and the report pipe (which
         * closes itself when the program starts) */
        int fds[1024], n = 0;
        DIR *d = opendir("/proc/self/fd");
        if (d) {
            int own = dirfd(d);
            struct dirent *e;
            while ((e = readdir(d)) && n < 1024) {
                int fd = atoi(e->d_name);
                if (fd >= 3 && fd != own && fd != report[1] && e->d_name[0] != '.')
                    fds[n++] = fd;
            }
            closedir(d);
            for (int i = 0; i < n; i++)
                close(fds[i]);
        } else {
            for (int fd = 3; fd < 1024; fd++)
                if (fd != report[1])
                    close(fd);
        }
        execve(exe, argv, envp);
        int err = errno;
        if (report[1] >= 0)
            write(report[1], &err, sizeof err);
        _exit(127);
    }
    int child_err = 0;
    if (pid > 0 && report[1] >= 0) {
        close(report[1]);
        ssize_t r;
        do
            r = read(report[0], &child_err, sizeof child_err);
        while (r < 0 && errno == EINTR);
        if (r != sizeof child_err)
            child_err = 0;
    } else if (report[1] >= 0) {
        close(report[1]);
    }
    if (report[0] >= 0)
        close(report[0]);
    int fork_err = pid < 0 ? errno : 0;
    for (int i = 0; argv[i]; i++)
        free(argv[i]);
    free(argv);
    if (made_env) {
        for (int i = 0; made_env[i]; i++)
            free(made_env[i]);
        free(made_env);
    }
    free(dir);
    if (fork_err) {
        FSetError(error, launch_error(NSFileReadUnknownError, path, fork_err));
        return NO;
    }
    if (child_err) {
        int st;
        while (waitpid(pid, &st, 0) < 0 && errno == EINTR)
            ;
        FSetError(error, launch_error(child_err == ENOENT || child_err == ENOTDIR ? NSFileNoSuchFileError
                                                                                 : NSFileReadNoPermissionError,
                                      path, child_err));
        return NO;
    }

    /* The child has its ends of the pipes now; the parent's copies would
     * keep a reader from ever seeing the end. */
    if ([_stdin isKindOfClass:[NSPipe class]])
        [[_stdin fileHandleForReading] closeFile];
    if ([_stdout isKindOfClass:[NSPipe class]])
        [[_stdout fileHandleForWriting] closeFile];
    if ([_stderr isKindOfClass:[NSPipe class]])
        [[_stderr fileHandleForWriting] closeFile];

    _pid = pid;
    _launched = YES;
    _running = YES;
    if (!running_tasks)
        running_tasks = [[NSMutableArray alloc] init];
    [running_tasks addObject:self];
    pump_ms = 1;
    start_pump();
    return YES;
}
- (void)launch
{
    if (_launched)
        FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask launch]: task already launched");
    NSError *err = nil;
    if (![self launchAndReturnError:&err]) {
        if (_directory && [[err userInfo] objectForKey:NSFilePathErrorKey] == _directory)
            FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask launch]: working directory doesn't exist.");
        FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask launch]: launch path not accessible");
    }
}
static void must_have_launched(NSTask *t, SEL sel)
{
    if (!t->_launched)
        FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask %s]: task not launched", sel_getName(sel));
}
- (void)interrupt
{
    must_have_launched(self, _cmd);
    if (_running)
        kill(_pid, SIGINT);
}
- (void)terminate
{
    must_have_launched(self, _cmd);
    if (_running)
        kill(_pid, SIGTERM);
}
- (BOOL)suspend
{
    must_have_launched(self, _cmd);
    if (!_running)
        return NO;
    if (_suspends++ == 0 && kill(_pid, SIGSTOP) < 0) {
        _suspends--;
        return NO;
    }
    return YES;
}
- (BOOL)resume
{
    must_have_launched(self, _cmd);
    if (!_running || _suspends == 0)
        return NO;
    if (--_suspends == 0 && kill(_pid, SIGCONT) < 0)
        return NO;
    return YES;
}
/* Runs the run loop (and so dispatch's work) until the child has exited. */
- (void)waitUntilExit
{
    if (!_launched)
        return;
    [self retain];
    while (_running) {
        if (reap(self))
            break;
        @autoreleasepool {
            if (![[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                          beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]])
                usleep(1000);
        }
    }
    [self release];
}
- (int)processIdentifier { return _pid; }
- (BOOL)isRunning
{
    if (_running)
        reap(self);
    return _running;
}
- (int)terminationStatus
{
    must_have_launched(self, _cmd);
    if (_running)
        reap(self);
    if (_running)
        FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask terminationStatus]: task still running");
    return _status;
}
- (NSTaskTerminationReason)terminationReason
{
    must_have_launched(self, _cmd);
    if (_running)
        reap(self);
    if (_running)
        FRaise(NSInvalidArgumentException, @"*** -[NSConcreteTask terminationReason]: task still running");
    return _reason;
}
+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments
{
    NSTask *t = [[[self alloc] init] autorelease];
    [t setLaunchPath:path];
    [t setArguments:arguments];
    [t launch];
    return t;
}
+ (NSTask *)launchedTaskWithExecutableURL:(NSURL *)url arguments:(NSArray *)arguments error:(NSError **)error
                       terminationHandler:(void (^)(NSTask *))handler
{
    NSTask *t = [[[self alloc] init] autorelease];
    [t setExecutableURL:url];
    [t setArguments:arguments];
    [t setTerminationHandler:handler];
    return [t launchAndReturnError:error] ? t : nil;
}
@end
