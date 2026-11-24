// SPDX-License-Identifier: GPL-3.0-or-later
// The older ways of loading URLs, against the test server on 127.0.0.1
// (see urlsession.m): NSURLConnection's synchronous and asynchronous calls
// and its delegate, NSData's and NSString's ...ContentsOfURL: for http
// URLs, and requests and responses made by hand. Built without ARC.
#import <Foundation/Foundation.h>

static NSString *base, *closedBase;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static void show_error(const char *what, NSError *e)
{
    if (!e) {
        printf("%s: no error\n", what);
        return;
    }
    printf("%s: %s %ld \"%s\"\n", what, S([e domain]), (long)[e code], S([e localizedDescription]));
}
static NSString *text(NSData *d)
{
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
}

@interface Watcher : NSObject {
@public
    NSMutableArray *events;
    NSMutableData *body;
    BOOL done;
}
@end
@implementation Watcher
- (instancetype)init
{
    self = [super init];
    events = [[NSMutableArray alloc] init];
    body = [[NSMutableData alloc] init];
    return self;
}
- (void)dealloc
{
    [events release];
    [body release];
    [super dealloc];
}
- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r
{
    [events addObject:[NSString stringWithFormat:@"response %ld", (long)[(NSHTTPURLResponse *)r statusCode]]];
}
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)d
{
    if (![[events lastObject] isEqualToString:@"data"])
        [events addObject:@"data"];
    [body appendData:d];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)c
{
    [events addObject:@"finished"];
    done = YES;
}
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)e
{
    [events addObject:[NSString stringWithFormat:@"failed %ld", (long)[e code]]];
    done = YES;
}
- (void)run
{
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}
@end

static void synchronous(void)
{
    NSURLResponse *r = nil;
    NSError *e = nil;
    NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/hello")]
                                      returningResponse:&r
                                                  error:&e];
    printf("synchronous: status %ld, %s", (long)[(NSHTTPURLResponse *)r statusCode], S(text(d)));
    show_error("synchronous", e);
    r = nil;
    d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/status/404")]
                              returningResponse:&r
                                          error:&e];
    printf("synchronous 404: status %ld, %s", (long)[(NSHTTPURLResponse *)r statusCode], S(text(d)));
    d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:closedBase]]
                              returningResponse:&r
                                          error:&e];
    printf("synchronous, closed port: data %s, ", d ? "kept" : "nil");
    show_error("error", e);
}

static void asynchronous(void)
{
    __block BOOL done = NO;
    __block int order = 0;
    // the main operation queue, when this Foundation has one
    id queue = [NSClassFromString(@"NSOperationQueue") performSelector:@selector(mainQueue)];
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:U(@"/redirect")]
                                       queue:queue
                           completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
                             printf("asynchronous: after the call returned %s, status %ld at %s, %s",
                                    order ? "yes" : "no", (long)[(NSHTTPURLResponse *)r statusCode],
                                    S([[r URL] path]), S(text(d)));
                             show_error("asynchronous", e);
                             done = YES;
                           }];
    order = 1;
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    done = NO;
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http:///"]]
                                       queue:queue
                           completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
                             printf("asynchronous, bad URL: response %s, data %s, ", r ? "kept" : "nil",
                                    d ? "kept" : "nil");
                             show_error("error", e);
                             done = YES;
                           }];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}

static void delegate(void)
{
    Watcher *w = [[[Watcher alloc] init] autorelease];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    [req setHTTPMethod:@"PATCH"];
    [req setHTTPBody:[@"x=1&y=2" dataUsingEncoding:NSUTF8StringEncoding]];
    [NSURLConnection connectionWithRequest:req delegate:w];
    [w run];
    printf("delegate: %s\n%s", S([w->events componentsJoinedByString:@", "]), S(text(w->body)));

    w = [[[Watcher alloc] init] autorelease];
    NSURLConnection *c = [[[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:closedBase]]
                                                          delegate:w
                                                  startImmediately:NO] autorelease];
    printf("not started: %s\n", [w->events count] ? "something happened" : "nothing yet");
    [c start];
    [w run];
    printf("delegate, closed port: %s\n", S([w->events componentsJoinedByString:@", "]));

    // cancelled: the delegate hears nothing more
    w = [[[Watcher alloc] init] autorelease];
    c = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:U(@"/slow?ms=500")] delegate:w];
    [c cancel];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
    printf("cancelled: %s\n", [w->events count] ? S([w->events componentsJoinedByString:@", "]) : "nothing");
    printf("can handle: http %d, file %d, other %d\n",
           [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:U(@"/")]],
           [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:@"/tmp"]]],
           [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"x-y://z"]]]);
}

static void contents(void)
{
    NSData *d = [NSData dataWithContentsOfURL:U(@"/hello")];
    printf("NSData: %s", S(text(d)));
    NSError *e = nil;
    d = [NSData dataWithContentsOfURL:[NSURL URLWithString:closedBase] options:0 error:&e];
    printf("NSData, closed port: data %s, ", d ? "kept" : "nil");
    show_error("error", e);
    show_error("underlying", [[e userInfo] objectForKey:NSUnderlyingErrorKey]);
    d = [[[NSData alloc] initWithContentsOfURL:U(@"/big?n=1000")] autorelease];
    printf("NSData init: %lu bytes\n", (unsigned long)[d length]);
    NSString *s = [NSString stringWithContentsOfURL:U(@"/hello") encoding:NSUTF8StringEncoding error:&e];
    printf("NSString: %s", S(s));
    NSStringEncoding used = 0;
    s = [NSString stringWithContentsOfURL:U(@"/latin1") usedEncoding:&used error:&e];
    printf("NSString, used encoding %lu: %s (%lu characters)\n", (unsigned long)used,
           S([s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]),
           (unsigned long)[s length]);
    s = [[[NSString alloc] initWithContentsOfURL:U(@"/echo") encoding:NSUTF8StringEncoding error:&e] autorelease];
    printf("NSString init: %s\n", S([[s componentsSeparatedByString:@"\n"] objectAtIndex:0]));
}

static void by_hand(void)
{
    NSURLRequest *r = [NSURLRequest requestWithURL:U(@"/a")];
    printf("request: method %s, timeout %g, cache policy %lu, fields %s, body %s, cookies %d\n", S([r HTTPMethod]),
           [r timeoutInterval], (unsigned long)[r cachePolicy], [r allHTTPHeaderFields] ? "some" : "none",
           [r HTTPBody] ? "some" : "none", [r HTTPShouldHandleCookies]);
    NSMutableURLRequest *m = [[r mutableCopy] autorelease];
    [m setValue:@"one" forHTTPHeaderField:@"X-Thing"];
    [m addValue:@"two" forHTTPHeaderField:@"x-thing"];
    [m setValue:@"keep" forHTTPHeaderField:@"Accept"];
    [m setValue:nil forHTTPHeaderField:@"accept"];
    [m setTimeoutInterval:5];
    NSURLRequest *copy = [[m copy] autorelease];
    [m setValue:@"changed" forHTTPHeaderField:@"X-Thing"];
    printf("request: X-THING %s, in the copy %s, fields %lu, copy mutable %d, equal %d\n",
           S([m valueForHTTPHeaderField:@"X-THING"]), S([copy valueForHTTPHeaderField:@"x-thing"]),
           (unsigned long)[[m allHTTPHeaderFields] count], [copy isKindOfClass:[NSMutableURLRequest class]],
           [copy isEqual:m]);
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:@"text/html; charset=\"ISO-8859-1\"",
                                                                      @"content-type", @"321", @"Content-Length",
                                                                      @"inline; filename=\"report.html\"",
                                                                      @"Content-Disposition", nil];
    NSHTTPURLResponse *h = [[[NSHTTPURLResponse alloc] initWithURL:U(@"/report")
                                                        statusCode:201
                                                       HTTPVersion:@"HTTP/1.1"
                                                      headerFields:fields] autorelease];
    printf("response: %ld (%s), MIME %s, encoding %s, length %lld, name %s, Content-Type %s\n",
           (long)[h statusCode], S([NSHTTPURLResponse localizedStringForStatusCode:[h statusCode]]), S([h MIMEType]),
           S([h textEncodingName]), [h expectedContentLength], S([h suggestedFilename]),
           S([h valueForHTTPHeaderField:@"CONTENT-TYPE"]));
    NSURLResponse *plain = [[[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://example.invalid/"]
                                                      MIMEType:@"text/plain"
                                         expectedContentLength:-1
                                              textEncodingName:nil] autorelease];
    printf("plain response: name %s, length %lld; status texts: %s, %s, %s\n", S([plain suggestedFilename]),
           [plain expectedContentLength], S([NSHTTPURLResponse localizedStringForStatusCode:500]),
           S([NSHTTPURLResponse localizedStringForStatusCode:299]),
           S([NSHTTPURLResponse localizedStringForStatusCode:418]));
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const char *server = getenv("FERRY_TEST_HTTP"), *closed = getenv("FERRY_TEST_CLOSED_PORT");
    if (!server || !closed) {
        printf("FERRY_TEST_HTTP and FERRY_TEST_CLOSED_PORT aren't set\n");
        return 1;
    }
    base = [[NSString alloc] initWithFormat:@"http://%s", server];
    closedBase = [[NSString alloc] initWithFormat:@"http://127.0.0.1:%s/", closed];
    synchronous();
    asynchronous();
    delegate();
    contents();
    by_hand();
    printf("done\n");
    [pool release];
    return 0;
}
