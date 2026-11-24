// SPDX-License-Identifier: GPL-3.0-or-later
// NSURLSession against a small HTTP server on 127.0.0.1 (tests/tools/http_server.py,
// started by run.sh, which passes its address in FERRY_TEST_HTTP and an unused
// port in FERRY_TEST_CLOSED_PORT): data tasks with completion handlers waited
// for with a semaphore, a dispatch group and the run loop, requests with
// methods, headers and bodies, responses' status and fields, redirects,
// decoding, errors, cancelling, delegates, uploads and downloads.
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *base, *closedBase;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static void wait_for(dispatch_semaphore_t s) { dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER); }
static void show_error(const char *what, NSError *e)
{
    if (!e) {
        printf("%s: no error\n", what);
        return;
    }
    NSString *failing = e.userInfo[NSURLErrorFailingURLStringErrorKey];
    printf("%s: %s %ld \"%s\"%s\n", what, S(e.domain), (long)e.code, S(e.localizedDescription),
           failing ? " (with the failing URL)" : "");
}
static void print_body(const char *what, NSData *d)
{
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    printf("%s: %s", what, S(s));
    if (![s hasSuffix:@"\n"])
        printf("\n");
}

// One request, waited for: what came back.
typedef struct {
    NSData *data;
    NSHTTPURLResponse *response;
    NSError *error;
} Result;
static Result fetch(NSURLSession *session, NSURLRequest *request)
{
    __block Result r = {nil, nil, nil};
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request
                completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
                  r.data = d;
                  r.response = (NSHTTPURLResponse *)resp;
                  r.error = e;
                  dispatch_semaphore_signal(sem);
                }] resume];
    wait_for(sem);
    return r;
}

@interface Listener : NSObject <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
@property NSMutableArray<NSString *> *events;
@property NSMutableData *body;
@property BOOL done, invalid;
@property NSURLSessionResponseDisposition answer;
@property int64_t written, expected;
@property long long fileSize;
@end
@implementation Listener
- (instancetype)init
{
    self = [super init];
    _events = [NSMutableArray array];
    _body = [NSMutableData data];
    _answer = NSURLSessionResponseAllow;
    return self;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    [_events addObject:[NSString stringWithFormat:@"response %ld", (long)((NSHTTPURLResponse *)response).statusCode]];
    // answered later, from the run loop: the data must wait for it
    NSURLSessionResponseDisposition answer = _answer;
    [[NSRunLoop mainRunLoop] performBlock:^{
      completionHandler(answer);
    }];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data
{
    if (![_events.lastObject isEqualToString:@"data"])
        [_events addObject:@"data"];
    [_body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)sent
    totalBytesSent:(int64_t)total totalBytesExpectedToSend:(int64_t)expected
{
    if (total == expected)
        [_events addObject:[NSString stringWithFormat:@"sent %lld of %lld", total, expected]];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
                 didWriteData:(int64_t)bytesWritten
            totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    _written = totalBytesWritten;
    _expected = totalBytesExpectedToWrite;
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
    didFinishDownloadingToURL:(NSURL *)location
{
    struct stat st;
    _fileSize = stat(location.fileSystemRepresentation, &st) == 0 ? st.st_size : -1;
    [_events addObject:[NSString stringWithFormat:@"downloaded %lld bytes", _fileSize]];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    [_events addObject:error ? [NSString stringWithFormat:@"complete with error %ld", (long)error.code]
                             : @"complete"];
    _done = YES;
}
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
    [_events addObject:@"session invalid"];
    _invalid = YES;
}
- (void)runUntilDone
{
    while (!_done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}
@end

static void shared_session(void)
{
    __block int order = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSURLSessionDataTask *task;
    task = [[NSURLSession sharedSession]
        dataTaskWithURL:U(@"/hello")
      completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *h = (NSHTTPURLResponse *)r;
        printf("hello: called after resume returned %s, task completed %s\n", order ? "yes" : "no",
               task.state == NSURLSessionTaskStateCompleted ? "yes" : "no");
        printf("hello: %s, status %ld, MIME %s, encoding %s, expected length %lld, path %s\n",
               S(NSStringFromClass([r class])), (long)h.statusCode, S(h.MIMEType), S(h.textEncodingName),
               h.expectedContentLength, S(h.URL.path));
        printf("hello: X-Ferry-Test %s, x-ferry-test %s, Content-Length field %s, suggested name %s\n",
               S(h.allHeaderFields[@"X-Ferry-Test"]), S([h valueForHTTPHeaderField:@"x-ferry-test"]),
               S([h valueForHTTPHeaderField:@"content-length"]), S(h.suggestedFilename));
        print_body("hello: body", d);
        show_error("hello", e);
        dispatch_semaphore_signal(sem);
      }];
    printf("task: state %ld before resume, identifier set %s\n", (long)task.state,
           task.taskIdentifier > 0 ? "yes" : "no");
    [task resume];
    order = 1;
    printf("task: state %ld after resume\n", (long)task.state);
    wait_for(sem);
    printf("task: state %ld at the end, %lld bytes received, response %s\n", (long)task.state,
           task.countOfBytesReceived, task.response ? "kept" : "missing");
}

static void requests(void)
{
    NSURLSession *s = [NSURLSession sharedSession];
    NSMutableURLRequest *post = [NSMutableURLRequest requestWithURL:U(@"/echo?x=1")];
    post.HTTPMethod = @"POST";
    [post setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [post setValue:@"first" forHTTPHeaderField:@"X-Custom"];
    [post setValue:@"second" forHTTPHeaderField:@"x-custom"]; // replaces, whatever the case
    post.HTTPBody = [@"{\"a\":1}" dataUsingEncoding:NSUTF8StringEncoding];
    Result r = fetch(s, post);
    print_body("POST", r.data);

    NSMutableURLRequest *put = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    put.HTTPMethod = @"PUT";
    put.HTTPBody = [@"new contents" dataUsingEncoding:NSUTF8StringEncoding];
    [put setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
    print_body("PUT", fetch(s, put).data);

    NSMutableURLRequest *del = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    del.HTTPMethod = @"DELETE";
    [del setValue:@"text/plain" forHTTPHeaderField:@"Accept"];
    print_body("DELETE", fetch(s, del).data);

    NSMutableURLRequest *head = [NSMutableURLRequest requestWithURL:U(@"/hello")];
    head.HTTPMethod = @"HEAD";
    r = fetch(s, head);
    printf("HEAD: status %ld, %lu bytes of body, expected length %lld\n", (long)r.response.statusCode,
           (unsigned long)r.data.length, r.response.expectedContentLength);

    r = fetch(s, [NSURLRequest requestWithURL:U(@"/status/404")]);
    printf("404: status %ld (%s), ", (long)r.response.statusCode,
           S([NSHTTPURLResponse localizedStringForStatusCode:r.response.statusCode]));
    show_error("an error", r.error);
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/status/204")]);
    printf("204: status %ld, %lu bytes, data %s\n", (long)r.response.statusCode, (unsigned long)r.data.length,
           r.data ? "empty, not nil" : "nil");
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/redirect")]);
    printf("redirect: status %ld, ended at %s, ", (long)r.response.statusCode, S(r.response.URL.path));
    print_body("body", r.data);
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/gzip")]);
    printf("gzip: Content-Encoding %s, ", S([r.response valueForHTTPHeaderField:@"Content-Encoding"]));
    print_body("decoded", r.data);
}

static void errors(void)
{
    NSURLSession *s = [NSURLSession sharedSession];
    show_error("closed port", fetch(s, [NSURLRequest requestWithURL:[NSURL URLWithString:closedBase]]).error);
    NSURLRequest *slow = [NSURLRequest requestWithURL:U(@"/slow?ms=3000")
                                          cachePolicy:NSURLRequestUseProtocolCachePolicy
                                      timeoutInterval:0.5];
    show_error("slow server", fetch(s, slow).error);
    NSURLRequest *stall = [NSURLRequest requestWithURL:U(@"/stall")
                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                       timeoutInterval:0.5];
    Result r = fetch(s, stall);
    show_error("stalled body", r.error);
    printf("stalled body: response %s, data %s\n", r.response ? "kept" : "nil", r.data ? "kept" : "nil");
    show_error("no host", fetch(s, [NSURLRequest requestWithURL:[NSURL URLWithString:@"http:///nohost"]]).error);
    show_error("other scheme", fetch(s, [NSURLRequest requestWithURL:[NSURL URLWithString:@"ferry-test://x/y"]]).error);
    show_error("no URL", fetch(s, [NSURLRequest requestWithURL:nil]).error);
    show_error("redirect loop", fetch(s, [NSURLRequest requestWithURL:U(@"/loop")]).error);
    show_error("server hung up", fetch(s, [NSURLRequest requestWithURL:U(@"/close")]).error);
}

static void cancelling(void)
{
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSURLSessionDataTask *task;
    task = [[NSURLSession sharedSession] dataTaskWithURL:U(@"/slow?ms=2000")
                                       completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                                         show_error("cancelled", e);
                                         printf("cancelled: data %s, state %ld in the handler\n",
                                                d ? "kept" : "nil", (long)task.state);
                                         dispatch_semaphore_signal(sem);
                                       }];
    [task resume];
    [task cancel];
    /* Canceling until the handler is about to run, on the session's queue,
     * which may be at once now that it runs on a thread of its own. */
    NSURLSessionTaskState after = task.state;
    printf("cancelled: after cancel %s\n",
           after == NSURLSessionTaskStateCanceling || after == NSURLSessionTaskStateCompleted
               ? "canceling (or completed already)"
               : "still running");
    wait_for(sem);
    // cancelled before it was ever resumed
    NSURLSessionDataTask *never = [[NSURLSession sharedSession]
        dataTaskWithURL:U(@"/hello")
      completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        show_error("never resumed", e);
        dispatch_semaphore_signal(sem);
      }];
    [never cancel];
    wait_for(sem);
}

static void together(void)
{
    // three at once, waited for with a dispatch group
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray *lines = [NSMutableArray arrayWithObjects:@"", @"", @"", nil];
    NSArray *paths = @[ @"/slow?ms=300", @"/hello", @"/status/500" ];
    for (NSUInteger i = 0; i < 3; i++) {
        dispatch_group_enter(group);
        [[[NSURLSession sharedSession]
              dataTaskWithURL:U(paths[i])
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
              lines[i] = [NSString stringWithFormat:@"%@ -> %ld, %lu bytes", paths[i],
                                                    (long)((NSHTTPURLResponse *)r).statusCode,
                                                    (unsigned long)d.length];
              dispatch_group_leave(group);
            }] resume];
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    for (NSString *l in lines)
        printf("together: %s\n", S(l));
}

static void delegates(void)
{
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
    printf("configuration: request timeout %g, resource timeout %g days, %ld connections a host\n",
           c.timeoutIntervalForRequest, c.timeoutIntervalForResource / 86400, (long)c.HTTPMaximumConnectionsPerHost);
    c.HTTPAdditionalHeaders = @{@"X-Session" : @"from the session", @"X-Both" : @"session"};
    c.timeoutIntervalForRequest = 30;
    Listener *l = [Listener new];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:c delegate:l delegateQueue:nil];
    c.timeoutIntervalForRequest = 5; // the session keeps its own copy
    printf("session: timeout %g, delegate kept %s, configuration headers %lu\n",
           s.configuration.timeoutIntervalForRequest, s.delegate == l ? "yes" : "no",
           (unsigned long)s.configuration.HTTPAdditionalHeaders.count);
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    [req setValue:@"request" forHTTPHeaderField:@"X-Both"];
    [[s dataTaskWithRequest:req] resume];
    [l runUntilDone];
    printf("delegate: %s\n", S([l.events componentsJoinedByString:@", "]));
    print_body("delegate body", l.body);

    // the delegate says no to the response
    l.done = NO;
    [l.events removeAllObjects];
    l.answer = NSURLSessionResponseCancel;
    [l.body setLength:0];
    [[s dataTaskWithURL:U(@"/hello")] resume];
    [l runUntilDone];
    printf("refused: %s, %lu bytes\n", S([l.events componentsJoinedByString:@", "]), (unsigned long)l.body.length);

    // an upload, with its progress
    l.done = NO;
    l.answer = NSURLSessionResponseAllow;
    [l.events removeAllObjects];
    [l.body setLength:0];
    NSMutableURLRequest *up = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    up.HTTPMethod = @"POST";
    NSURLSessionUploadTask *t = [s uploadTaskWithRequest:up
                                                fromData:[@"uploaded words" dataUsingEncoding:NSUTF8StringEncoding]];
    [t resume];
    [l runUntilDone];
    printf("upload: %s; the task sent %lld of %lld\n", S([l.events componentsJoinedByString:@", "]), t.countOfBytesSent,
           t.countOfBytesExpectedToSend);
    print_body("upload body", l.body);

    // a download through the delegate
    l.done = NO;
    [l.events removeAllObjects];
    [[s downloadTaskWithURL:U(@"/big?n=100000")] resume];
    [l runUntilDone];
    printf("download: %s, written %lld of %lld\n", S([l.events componentsJoinedByString:@", "]), l.written,
           l.expected);

    l.done = NO;
    [l.events removeAllObjects];
    [s finishTasksAndInvalidate];
    while (!l.invalid)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    printf("invalidated: %s, delegate let go %s\n", S([l.events componentsJoinedByString:@", "]),
           s.delegate ? "no" : "yes");
    @try {
        [s dataTaskWithURL:U(@"/hello")];
        printf("a task from an invalidated session: allowed\n");
    } @catch (NSException *e) {
        printf("a task from an invalidated session: %s\n", S(e.name));
    }
}

static void downloads(void)
{
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *path;
    [[[NSURLSession sharedSession]
        downloadTaskWithURL:U(@"/big?n=100000")
          completionHandler:^(NSURL *location, NSURLResponse *r, NSError *e) {
            path = location.path;
            NSData *d = [NSData dataWithContentsOfURL:location];
            const unsigned char *b = d.bytes;
            unsigned long sum = 0;
            for (NSUInteger i = 0; i < d.length; i++)
                sum += b[i];
            printf("download: a file URL %s, named %s..., %lu bytes, sum %lu, suggested name %s\n",
                   location.isFileURL ? "yes" : "no",
                   S([location.lastPathComponent substringToIndex:18]), (unsigned long)d.length, sum,
                   S(r.suggestedFilename));
            show_error("download", e);
            dispatch_semaphore_signal(sem);
          }] resume];
    wait_for(sem);
    printf("download: the file is gone after the handler %s\n", access(path.fileSystemRepresentation, F_OK) ? "yes" : "no");

    NSMutableURLRequest *put = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    put.HTTPMethod = @"PUT";
    [[[NSURLSession sharedSession] uploadTaskWithRequest:put
                                                fromData:[@"a body" dataUsingEncoding:NSUTF8StringEncoding]
                                       completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                                         print_body("upload with a handler", d);
                                         dispatch_semaphore_signal(sem);
                                       }] resume];
    wait_for(sem);
}

int main(void)
{
    @autoreleasepool {
        const char *server = getenv("FERRY_TEST_HTTP"), *closed = getenv("FERRY_TEST_CLOSED_PORT");
        if (!server || !closed) {
            printf("FERRY_TEST_HTTP and FERRY_TEST_CLOSED_PORT aren't set\n");
            return 1;
        }
        base = [NSString stringWithFormat:@"http://%s", server];
        closedBase = [NSString stringWithFormat:@"http://127.0.0.1:%s/", closed];
        shared_session();
        requests();
        errors();
        cancelling();
        together();
        delegates();
        downloads();
        // the last one ends the program from its handler, under dispatch_main
        [[[NSURLSession sharedSession] dataTaskWithURL:U(@"/slow?ms=100")
                                     completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                                       printf("dispatch_main: %s", S([[NSString alloc] initWithData:d
                                                                       encoding:NSUTF8StringEncoding]));
                                       printf("done\n");
                                       exit(0);
                                     }] resume];
        dispatch_main();
    }
}
