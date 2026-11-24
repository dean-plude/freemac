// SPDX-License-Identifier: GPL-3.0-or-later
// Authentication, against the test server on 127.0.0.1 (see urlsession.m):
// NSURLCredential, NSURLProtectionSpace, NSURLCredentialStorage, HTTP Basic
// and Digest challenges answered by a session's task delegate (each
// disposition), by default handling (the URL's user and password, the
// storage's credential), and by NSURLConnection's delegate, both its newer
// and its older methods. Built with ARC.
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

static NSString *base, *host;
static NSInteger port;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static NSString *text(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }
static const char *B(BOOL b) { return b ? "yes" : "no"; }
static void run_until(BOOL *done)
{
    while (!*done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}
static void show_challenge(NSURLAuthenticationChallenge *c)
{
    NSURLProtectionSpace *s = c.protectionSpace;
    printf("  challenge: %s, realm %s, %s, on the test server: %s, failures %ld, proposed %s, failure response %ld\n",
           S(s.authenticationMethod), S(s.realm), S(s.protocol),
           B([s.host isEqualToString:host] && s.port == port), (long)c.previousFailureCount,
           S(c.proposedCredential.user), (long)((NSHTTPURLResponse *)c.failureResponse).statusCode);
}

static void objects(void)
{
    NSURLCredential *c = [NSURLCredential credentialWithUser:@"ann" password:@"pw"
                                                 persistence:NSURLCredentialPersistenceForSession];
    printf("credential: %s/%s, has password %s, persistence %ld\n", S(c.user), S(c.password), B(c.hasPassword),
           (long)c.persistence);
    printf("equal to the same: %s, to another password: %s\n",
           B([c isEqual:[NSURLCredential credentialWithUser:@"ann" password:@"pw"
                                                 persistence:NSURLCredentialPersistenceForSession]]),
           B([c isEqual:[NSURLCredential credentialWithUser:@"ann" password:@"no"
                                                 persistence:NSURLCredentialPersistenceForSession]]));
    NSURLProtectionSpace *s = [[NSURLProtectionSpace alloc] initWithHost:@"example.com" port:443
                                                                protocol:NSURLProtectionSpaceHTTPS
                                                                   realm:@"Users"
                                                    authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    printf("space: %s:%ld %s realm %s %s, proxy %s, secure %s\n", S(s.host), (long)s.port, S(s.protocol), S(s.realm),
           S(s.authenticationMethod), B(s.isProxy), B(s.receivesCredentialSecurely));
    NSURLProtectionSpace *same = [[NSURLProtectionSpace alloc] initWithHost:@"EXAMPLE.com" port:443
                                                                   protocol:NSURLProtectionSpaceHTTPS
                                                                      realm:@"Users"
                                                       authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLProtectionSpace *other = [[NSURLProtectionSpace alloc] initWithHost:@"example.com" port:443
                                                                    protocol:NSURLProtectionSpaceHTTPS
                                                                       realm:@"Admins"
                                                        authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    printf("same space: %s, other realm: %s\n", B([s isEqual:same]), B([s isEqual:other]));
    NSURLProtectionSpace *proxy = [[NSURLProtectionSpace alloc] initWithProxyHost:@"proxy" port:3128
                                                                             type:NSURLProtectionSpaceHTTPProxy
                                                                            realm:nil
                                                             authenticationMethod:NSURLAuthenticationMethodDefault];
    printf("proxy space: proxy %s, type %s\n", B(proxy.isProxy), S(proxy.proxyType));

    NSURL *u = [NSURL URLWithString:@"http://ann%40home:p%3Aw@example.com/x"];
    printf("URL user %s, password %s\n", S(u.user), S(u.password));

    // the storage
    NSURLCredentialStorage *st = [NSURLCredentialStorage sharedCredentialStorage];
    __block int changes = 0;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSURLCredentialStorageChangedNotification
                                                                 object:nil
                                                                  queue:nil
                                                             usingBlock:^(NSNotification *n) {
                                                               changes++;
                                                             }];
    [st setCredential:c forProtectionSpace:s];
    [st setCredential:[NSURLCredential credentialWithUser:@"bob" password:@"x"
                                              persistence:NSURLCredentialPersistencePermanent]
        forProtectionSpace:s];
    [st setCredential:[NSURLCredential credentialWithUser:@"eve" password:@"x"
                                              persistence:NSURLCredentialPersistenceNone]
        forProtectionSpace:s];
    NSArray *users = [[[st credentialsForProtectionSpace:same] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    printf("stored for the space: %s\n", S([users componentsJoinedByString:@" "]));
    printf("default: %s\n", S([st defaultCredentialForProtectionSpace:s].user));
    [st setDefaultCredential:[NSURLCredential credentialWithUser:@"bob" password:@"x"
                                                     persistence:NSURLCredentialPersistencePermanent]
          forProtectionSpace:s];
    printf("default now: %s\n", S([st defaultCredentialForProtectionSpace:s].user));
    printf("spaces: %lu\n", (unsigned long)st.allCredentials.count);
    [st removeCredential:c forProtectionSpace:s];
    users = [[[st credentialsForProtectionSpace:s] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    printf("after removing ann: %s\n", S([users componentsJoinedByString:@" "]));
    [st removeCredential:[st defaultCredentialForProtectionSpace:s] forProtectionSpace:s];
    printf("after removing bob: %lu spaces, default %s\n", (unsigned long)st.allCredentials.count,
           S([st defaultCredentialForProtectionSpace:s].user));
    printf("changes posted: %s\n", B(changes >= 4));
    [[NSNotificationCenter defaultCenter] removeObserver:token];
}

// ---- sessions

typedef void (^Answer)(NSURLSessionAuthChallengeDisposition, NSURLCredential *);
typedef void (^Decide)(NSURLAuthenticationChallenge *, Answer);

@interface Asker : NSObject <NSURLSessionTaskDelegate>
@property (copy) Decide decide;
@end
@implementation Asker
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(Answer)completionHandler
{
    show_challenge(challenge);
    self.decide(challenge, completionHandler);
}
@end

// only the session-level method: not asked for a password
@interface SessionAsker : NSObject <NSURLSessionDelegate>
@end
@implementation SessionAsker
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(Answer)completionHandler
{
    printf("  session-level challenge: %s\n", S(challenge.protectionSpace.authenticationMethod));
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}
@end

static void fetch(const char *what, NSURLSession *session, NSURL *url)
{
    printf("%s\n", what);
    __block BOOL done = NO;
    [[session dataTaskWithURL:url
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
              if (e)
                  printf("  error %s %ld\n", S(e.domain), (long)e.code);
              else
                  printf("  status %ld: %s", (long)((NSHTTPURLResponse *)r).statusCode, S(text(d)));
              done = YES;
            }] resume];
    run_until(&done);
}

static NSURLSession *session_with(id delegate)
{
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
    return [NSURLSession sessionWithConfiguration:c delegate:delegate delegateQueue:[NSOperationQueue mainQueue]];
}

static void sessions(void)
{
    NSURLSession *plain = session_with(nil);
    fetch("Basic, no delegate, no credential", plain, U(@"/basic?user=ann&pass=pw"));
    NSString *withUser = [base stringByReplacingOccurrencesOfString:@"http://" withString:@"http://ann:pw@"];
    fetch("Basic, the URL's user and password", plain,
          [NSURL URLWithString:[withUser stringByAppendingString:@"/basic?user=ann&pass=pw"]]);
    withUser = [base stringByReplacingOccurrencesOfString:@"http://" withString:@"http://ann:wrong@"];
    fetch("Basic, a wrong password in the URL", plain,
          [NSURL URLWithString:[withUser stringByAppendingString:@"/basic?user=ann&pass=pw"]]);

    Asker *a = [Asker new];
    NSURLSession *s = session_with(a);
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengeUseCredential,
             [NSURLCredential credentialWithUser:@"ann" password:@"pw" persistence:NSURLCredentialPersistenceNone]);
    };
    fetch("Basic, answered by the delegate", s, U(@"/basic?user=ann&pass=pw"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      // answered later, from the run loop
      dispatch_async(dispatch_get_main_queue(), ^{
        answer(NSURLSessionAuthChallengeUseCredential,
               [NSURLCredential credentialWithUser:@"ann" password:@"pw" persistence:NSURLCredentialPersistenceNone]);
      });
    };
    fetch("Basic, answered later", s, U(@"/basic?user=ann&pass=pw"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      if (c.previousFailureCount == 0)
          answer(NSURLSessionAuthChallengeUseCredential,
                 [NSURLCredential credentialWithUser:@"ann" password:@"wrong"
                                         persistence:NSURLCredentialPersistenceNone]);
      else
          answer(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    };
    fetch("Basic, a wrong password, then cancelled", s, U(@"/basic?user=ann&pass=pw"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengeUseCredential, nil);
    };
    fetch("Basic, no credential given", s, U(@"/basic?user=ann&pass=pw"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengeRejectProtectionSpace, nil);
    };
    fetch("Basic, the protection space rejected", s, U(@"/basic?user=ann&pass=pw"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    };
    fetch("Basic, default handling, nothing stored", s, U(@"/basic?user=ann&pass=pw"));

    // a credential kept for the session is used by default handling afterwards
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengeUseCredential,
             [NSURLCredential credentialWithUser:@"kim" password:@"kept"
                                     persistence:NSURLCredentialPersistenceForSession]);
    };
    fetch("Basic, a credential kept for the session", s, U(@"/basic?user=kim&pass=kept"));
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:host port:port
                                                                    protocol:NSURLProtectionSpaceHTTP
                                                                       realm:@"ferry"
                                                        authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    printf("  stored: %s\n", S([[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space]
                                   .user));
    fetch("Basic, the stored credential, no delegate", plain, U(@"/basic?user=kim&pass=kept"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    };
    fetch("Basic, the stored credential, proposed to the delegate", s, U(@"/basic?user=kim&pass=kept"));
    [[NSURLCredentialStorage sharedCredentialStorage]
        removeCredential:[[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space]
      forProtectionSpace:space];

    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      answer(NSURLSessionAuthChallengeUseCredential,
             [NSURLCredential credentialWithUser:@"bob" password:@"secret"
                                     persistence:NSURLCredentialPersistenceNone]);
    };
    fetch("Digest, answered by the delegate", s, U(@"/digest?user=bob&pass=secret"));
    a.decide = ^(NSURLAuthenticationChallenge *c, Answer answer) {
      if (c.previousFailureCount == 0)
          answer(NSURLSessionAuthChallengeUseCredential,
                 [NSURLCredential credentialWithUser:@"bob" password:@"wrong"
                                         persistence:NSURLCredentialPersistenceNone]);
      else
          answer(NSURLSessionAuthChallengeUseCredential,
                 [NSURLCredential credentialWithUser:@"bob" password:@"secret"
                                         persistence:NSURLCredentialPersistenceNone]);
    };
    fetch("Digest, a wrong password, then the right one", s, U(@"/digest?user=bob&pass=secret"));

    NSURLSession *onlySession = session_with([SessionAsker new]);
    fetch("Basic, a delegate with only the session-level method", onlySession, U(@"/basic?user=ann&pass=pw"));

    // an ephemeral session's credentials stay in it
    NSURLSessionConfiguration *ec = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    printf("ephemeral storage is the shared one: %s\n",
           B(ec.URLCredentialStorage == [NSURLCredentialStorage sharedCredentialStorage]));
    printf("default storage is the shared one: %s\n",
           B([NSURLSessionConfiguration defaultSessionConfiguration].URLCredentialStorage ==
             [NSURLCredentialStorage sharedCredentialStorage]));
    [s finishTasksAndInvalidate];
    [plain finishTasksAndInvalidate];
    [onlySession finishTasksAndInvalidate];
}

// ---- NSURLConnection

@interface Signer : NSObject <NSURLConnectionDataDelegate>
@property int mode; // 0 use, 1 cancel, 2 continue without, 3 default
@property BOOL done;
@end
@implementation Signer
- (void)connection:(NSURLConnection *)c willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)ch
{
    show_challenge(ch);
    switch (self.mode) {
    case 0:
        [ch.sender useCredential:[NSURLCredential credentialWithUser:@"ann" password:@"pw"
                                                         persistence:NSURLCredentialPersistenceNone]
            forAuthenticationChallenge:ch];
        break;
    case 1: [ch.sender cancelAuthenticationChallenge:ch]; break;
    case 2: [ch.sender continueWithoutCredentialForAuthenticationChallenge:ch]; break;
    default: [ch.sender performDefaultHandlingForAuthenticationChallenge:ch]; break;
    }
}
- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response
{
    printf("  response %ld\n", (long)((NSHTTPURLResponse *)response).statusCode);
}
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data { printf("  data: %s", S(text(data))); }
- (void)connectionDidFinishLoading:(NSURLConnection *)c
{
    printf("  finished\n");
    self.done = YES;
}
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error
{
    printf("  failed %s %ld\n", S(error.domain), (long)error.code);
    self.done = YES;
}
@end

// the older pair of methods
@interface OldSigner : NSObject <NSURLConnectionDataDelegate>
@property BOOL done;
@end
@implementation OldSigner
- (BOOL)connection:(NSURLConnection *)c canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)space
{
    printf("  can authenticate against %s: yes\n", S(space.authenticationMethod));
    return YES;
}
- (void)connection:(NSURLConnection *)c didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)ch
{
    show_challenge(ch);
    [ch.sender useCredential:[NSURLCredential credentialWithUser:@"bob" password:@"secret"
                                                     persistence:NSURLCredentialPersistenceNone]
        forAuthenticationChallenge:ch];
}
- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)c { return NO; }
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

static void connections(void)
{
    const char *names[] = {"connection, a credential", "connection, cancelled", "connection, without a credential",
                           "connection, default handling"};
    for (int mode = 0; mode < 4; mode++) {
        printf("%s\n", names[mode]);
        Signer *s = [Signer new];
        s.mode = mode;
        [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:U(@"/basic?user=ann&pass=pw")] delegate:s];
        while (!s.done)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    }
    printf("connection, the older methods, Digest\n");
    OldSigner *o = [OldSigner new];
    [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:U(@"/digest?user=bob&pass=secret")] delegate:o];
    while (!o.done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];

    NSURLResponse *r = nil;
    NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/basic?user=ann&pass=pw")]
                                      returningResponse:&r
                                                  error:NULL];
    printf("synchronous, no credential: %ld %s", (long)((NSHTTPURLResponse *)r).statusCode, S(text(d)));
    NSString *withUser = [base stringByReplacingOccurrencesOfString:@"http://" withString:@"http://ann:pw@"];
    printf("contents with the URL's user: %s",
           S([NSString stringWithContentsOfURL:[NSURL URLWithString:[withUser stringByAppendingString:
                                                                                  @"/basic?user=ann&pass=pw"]]
                                      encoding:NSUTF8StringEncoding
                                         error:NULL]));
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
        NSURL *b = [NSURL URLWithString:base];
        host = b.host;
        port = b.port.integerValue;
        objects();
        sessions();
        connections();
    }
    return 0;
}
