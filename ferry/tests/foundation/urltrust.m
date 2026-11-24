// SPDX-License-Identifier: GPL-3.0-or-later
// A server's certificate as a challenge (NSURLAuthenticationMethodServerTrust),
// against the test server's TLS port on 127.0.0.1, whose certificate run.sh
// made itself, so this system doesn't trust it: default handling leaves the
// check to libcurl and fails; a delegate that accepts it, at the session's
// level or the task's, or through NSURLConnection, gets the page. Built with ARC.
#import <Foundation/Foundation.h>

static NSString *base;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static NSString *text(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }
typedef void (^Answer)(NSURLSessionAuthChallengeDisposition, NSURLCredential *);

static void show(const char *level, NSURLAuthenticationChallenge *c)
{
    NSURLProtectionSpace *s = c.protectionSpace;
    printf("  %s challenge: %s, %s, host %s, a trust %s, realm %s\n", level, S(s.authenticationMethod), S(s.protocol),
           S(s.host), s.serverTrust ? "yes" : "no", S(s.realm));
}

@interface Judge : NSObject <NSURLSessionTaskDelegate>
@property NSURLSessionAuthChallengeDisposition answer;
@end
@implementation Judge
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(Answer)completionHandler
{
    show("session", challenge);
    if (self.answer == NSURLSessionAuthChallengeUseCredential)
        completionHandler(self.answer, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    else
        completionHandler(self.answer, nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(Answer)completionHandler
{
    show("task", challenge);
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic])
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialWithUser:@"ann" password:@"pw"
                                                  persistence:NSURLCredentialPersistenceNone]);
    else
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}
@end

// only the task-level method
@interface TaskJudge : NSObject <NSURLSessionTaskDelegate>
@end
@implementation TaskJudge
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(Answer)completionHandler
{
    show("task", challenge);
    completionHandler(NSURLSessionAuthChallengeUseCredential,
                      [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
}
@end

static void fetch(const char *what, NSURLSession *s, NSString *path)
{
    printf("%s\n", what);
    __block BOOL done = NO;
    [[s dataTaskWithURL:U(path)
      completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e)
            printf("  error %s %ld\n", S(e.domain), (long)e.code);
        else
            printf("  status %ld: %s", (long)((NSHTTPURLResponse *)r).statusCode, S(text(d)));
        done = YES;
      }] resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}

@interface Trusting : NSObject <NSURLConnectionDataDelegate>
@property BOOL done;
@end
@implementation Trusting
- (void)connection:(NSURLConnection *)c willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)ch
{
    show("connection", ch);
    [ch.sender useCredential:[NSURLCredential credentialForTrust:ch.protectionSpace.serverTrust]
        forAuthenticationChallenge:ch];
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

int main(void)
{
    @autoreleasepool {
        const char *server = getenv("FERRY_TEST_HTTPS");
        if (!server || !*server) {
            printf("FERRY_TEST_HTTPS isn't set\n");
            return 1;
        }
        base = [NSString stringWithFormat:@"https://%s", server];
        NSURLSessionConfiguration *conf = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        fetch("no delegate", [NSURLSession sessionWithConfiguration:conf], @"/hello");
        Judge *j = [Judge new];
        NSURLSession *s = [NSURLSession sessionWithConfiguration:conf delegate:j
                                                   delegateQueue:[NSOperationQueue mainQueue]];
        j.answer = NSURLSessionAuthChallengePerformDefaultHandling;
        fetch("default handling", s, @"/hello");
        j.answer = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        fetch("cancelled", s, @"/hello");
        j.answer = NSURLSessionAuthChallengeUseCredential;
        fetch("accepted", s, @"/hello");
        fetch("accepted, then a password", s, @"/basic?user=ann&pass=pw");
        NSURLSession *t = [NSURLSession sessionWithConfiguration:conf delegate:[TaskJudge new]
                                                   delegateQueue:[NSOperationQueue mainQueue]];
        fetch("accepted at the task's level", t, @"/hello");
        printf("connection, accepted\n");
        Trusting *c = [Trusting new];
        [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:U(@"/hello")] delegate:c];
        while (!c.done)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        NSError *e = nil;
        NSData *d = [NSData dataWithContentsOfURL:U(@"/hello") options:0 error:&e];
        printf("dataWithContentsOfURL: %s, underlying %ld\n", d ? "data" : "nil",
               (long)((NSError *)e.userInfo[NSUnderlyingErrorKey]).code);
    }
    return 0;
}
