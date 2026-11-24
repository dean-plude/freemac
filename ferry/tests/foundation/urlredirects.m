// SPDX-License-Identifier: GPL-3.0-or-later
// Redirects decided by the delegate, against the test server on 127.0.0.1
// (see urlsession.m): NSURLSession's URLSession:task:willPerformHTTPRedirection:
// newRequest:completionHandler: following, changing and refusing a redirect,
// the methods and bodies each status keeps, currentRequest, and
// NSURLConnection's connection:willSendRequest:redirectResponse:. Built with ARC.
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

static NSString *base;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static NSString *text(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }
// a URL's path and query, without the server's address (its port changes)
static NSString *P(NSURL *u)
{
    if (!u)
        return @"(nil)";
    return u.query ? [NSString stringWithFormat:@"%@?%@", u.path, u.query] : u.path;
}
static void print_lines(const char *what, NSString *s)
{
    for (NSString *line in [s componentsSeparatedByString:@"\n"])
        if (line.length)
            printf("%s: %s\n", what, S(line));
}

typedef NSURLRequest * (^Decide)(NSHTTPURLResponse *, NSURLRequest *);

@interface Redirects : NSObject <NSURLSessionTaskDelegate>
@property (copy) Decide decide;
@property BOOL later; // answer from the run loop, after the delegate method returned
@end
@implementation Redirects
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    printf("  redirect %ld to %s, %s%s\n", (long)response.statusCode, S(P(request.URL)), S(request.HTTPMethod),
           request.HTTPBody.length ? [[@" with " stringByAppendingString:text(request.HTTPBody)] UTF8String] : "");
    printf("  currentRequest before: %s\n", S(P(task.currentRequest.URL)));
    NSURLRequest *answer = self.decide ? self.decide(response, request) : request;
    if (self.later)
        dispatch_async(dispatch_get_main_queue(), ^{
          completionHandler(answer);
        });
    else
        completionHandler(answer);
}
@end

static void fetch(const char *what, NSURLSession *session, NSURLRequest *request)
{
    printf("%s\n", what);
    __block BOOL done = NO;
    __block NSURLSessionDataTask *task;
    task = [session dataTaskWithRequest:request
                      completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                        NSHTTPURLResponse *h = (NSHTTPURLResponse *)r;
                        if (e)
                            printf("  error %ld\n", (long)e.code);
                        else {
                            printf("  status %ld from %s\n", (long)h.statusCode, S(P(h.URL)));
                            print_lines("    body", text(d));
                        }
                        printf("  originalRequest %s, currentRequest %s\n", S(P(task.originalRequest.URL)),
                               S(P(task.currentRequest.URL)));
                        done = YES;
                      }];
    [task resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}

static NSMutableURLRequest *post(NSString *path, NSString *body)
{
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:U(path)];
    r.HTTPMethod = @"POST";
    r.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [r setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
    return r;
}

static void sessions(void)
{
    Redirects *d = [Redirects new];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                    delegate:d
                                               delegateQueue:[NSOperationQueue mainQueue]];
    fetch("followed", s, [NSURLRequest requestWithURL:U(@"/redirect-to?code=302&to=/hello")]);
    fetch("two in a row", s,
          [NSURLRequest requestWithURL:U(@"/redirect-to?code=301&to=/redirect-to%3Fcode%3D307%26to%3D/hello")]);
    d.later = YES;
    fetch("followed, answered later", s, [NSURLRequest requestWithURL:U(@"/redirect-to?code=302&to=/hello")]);
    d.later = NO;
    d.decide = ^NSURLRequest *(NSHTTPURLResponse *r, NSURLRequest *next) {
      NSMutableURLRequest *m = [next mutableCopy];
      m.URL = U(@"/headers");
      [m setValue:@"text/x-changed" forHTTPHeaderField:@"Content-Type"];
      return m;
    };
    fetch("changed by the delegate", s, [NSURLRequest requestWithURL:U(@"/redirect-to?code=302&to=/hello")]);
    d.decide = ^NSURLRequest *(NSHTTPURLResponse *r, NSURLRequest *next) {
      return nil;
    };
    fetch("refused", s, [NSURLRequest requestWithURL:U(@"/redirect-to?code=302&to=/hello")]);
    d.decide = nil;
    // what each status does to a POST (RFC 9110, 15.4)
    fetch("POST, 301", s, post(@"/redirect-to?code=301&to=/headers", @"abc"));
    fetch("POST, 302", s, post(@"/redirect-to?code=302&to=/headers", @"abc"));
    fetch("POST, 303", s, post(@"/redirect-to?code=303&to=/headers", @"abc"));
    fetch("POST, 307", s, post(@"/redirect-to?code=307&to=/headers", @"abc"));
    fetch("POST, 308", s, post(@"/redirect-to?code=308&to=/headers", @"abc"));
    NSMutableURLRequest *put = post(@"/redirect-to?code=303&to=/headers", @"abc");
    put.HTTPMethod = @"PUT";
    fetch("PUT, 303", s, put);
    fetch("relative Location", s, [NSURLRequest requestWithURL:U(@"/redirect-to?code=302&to=hello")]);
    [s finishTasksAndInvalidate];

    // no delegate method: followed, as before
    NSURLSession *plain = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    fetch("no delegate", plain, [NSURLRequest requestWithURL:U(@"/redirect-to?code=307&to=/hello")]);
    [plain finishTasksAndInvalidate];
}

// ---- NSURLConnection

@interface Hops : NSObject <NSURLConnectionDataDelegate>
@property BOOL refuse, refuseFirst, done;
@end
@implementation Hops
- (NSURLRequest *)connection:(NSURLConnection *)c willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response
{
    if (!response) {
        printf("  willSendRequest %s, no redirect response\n", S(P(request.URL)));
        if (self.refuseFirst) {
            self.done = YES;
            return nil;
        }
        return request;
    }
    printf("  willSendRequest %s, after %ld\n", S(P(request.URL)), (long)((NSHTTPURLResponse *)response).statusCode);
    return self.refuse ? nil : request;
}
- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response
{
    printf("  response %ld, currentRequest %s\n", (long)((NSHTTPURLResponse *)response).statusCode,
           S(P(c.currentRequest.URL)));
}
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data { printf("  data: %s", S(text(data))); }
- (void)connectionDidFinishLoading:(NSURLConnection *)c
{
    printf("  finished\n");
    self.done = YES;
}
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error
{
    printf("  failed %ld\n", (long)error.code);
    self.done = YES;
}
@end

static void connect(const char *what, Hops *h, NSString *path)
{
    printf("%s\n", what);
    NSURLConnection *c = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:U(path)] delegate:h];
    while (!h.done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    printf("  originalRequest %s\n", S(P(c.originalRequest.URL)));
}

static void connections(void)
{
    connect("connection, followed", [Hops new], @"/redirect-to?code=302&to=/hello");
    Hops *h = [Hops new];
    h.refuse = YES;
    connect("connection, refused", h, @"/redirect-to?code=302&to=/hello");
    h = [Hops new];
    h.refuseFirst = YES;
    connect("connection, the first request refused", h, @"/hello");
    // run a little more: nothing else comes for it
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];

    NSURLResponse *r = nil;
    NSError *e = nil;
    NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/redirect-to?code=303&to=/hello")]
                                      returningResponse:&r
                                                  error:&e];
    printf("synchronous: %ld from %s: %s", (long)((NSHTTPURLResponse *)r).statusCode, S(P(r.URL)), S(text(d)));
    print_lines("contents", [NSString stringWithContentsOfURL:U(@"/redirect-to?code=307&to=/hello")
                                                     encoding:NSUTF8StringEncoding
                                                        error:NULL]);
}

int main(void)
{
    @autoreleasepool {
        const char *server = getenv("FERRY_TEST_HTTP");
        if (!server) {
            printf("FERRY_TEST_HTTP isn't set\n");
            return 1;
        }
        base = [NSString stringWithFormat:@"http://%s", server];
        sessions();
        connections();
    }
    return 0;
}
