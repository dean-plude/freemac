// SPDX-License-Identifier: GPL-3.0-or-later
// Cookies: NSHTTPCookie made from properties and read from Set-Cookie
// fields, the fields made for a request, NSHTTPCookieStorage and its accept
// policy, and sessions that send and keep cookies, against the test server
// on 127.0.0.1 (see urlsession.m). run.sh runs it twice in one home: "first"
// keeps cookies in the shared storage, which saves the lasting ones, and
// "second" finds them there. Built with ARC.
#import <Foundation/Foundation.h>

static NSString *base;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static const char *B(BOOL b) { return b ? "yes" : "no"; }
static NSString *text(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }
static NSString *escaped(NSString *s)
{
    NSMutableString *out = [NSMutableString string];
    for (const unsigned char *p = (const unsigned char *)s.UTF8String; *p; p++)
        if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9'))
            [out appendFormat:@"%c", *p];
        else
            [out appendFormat:@"%%%02X", *p];
    return out;
}
static NSURL *setting(NSArray<NSString *> *fields)
{
    NSMutableString *path = [NSMutableString stringWithString:@"/cookies/set?"];
    for (NSString *f in fields)
        [path appendFormat:@"%@h=%@", [path hasSuffix:@"?"] ? @"" : @"&", escaped(f)];
    return U(path);
}
static void show(NSHTTPCookie *c)
{
    NSTimeInterval left = [c.expiresDate timeIntervalSinceNow];
    NSString *expires = !c.expiresDate        ? @"at the end of the session"
                        : left > 1e8          ? [NSString stringWithFormat:@"%.0f", c.expiresDate.timeIntervalSince1970]
                        : left > 50 && left <= 60 ? @"in a minute"
                        : left <= 0               ? @"already"
                                              : @"soon";
    printf("  %s=%s domain %s path %s, expires %s, session only %s, secure %s, HTTP only %s\n", S(c.name),
           S(c.value), S(c.domain), S(c.path), S(expires), B(c.sessionOnly), B(c.secure), B(c.HTTPOnly));
}
static NSString *names(NSArray<NSHTTPCookie *> *cookies)
{
    NSMutableArray *n = [NSMutableArray array];
    for (NSHTTPCookie *c in cookies)
        [n addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
    return n.count ? [n componentsJoinedByString:@" "] : @"(none)";
}
static NSString *fetch(NSURLSession *s, NSURLRequest *r)
{
    __block NSString *got = nil;
    __block BOOL done = NO;
    [[s dataTaskWithRequest:r
          completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
            got = e ? [NSString stringWithFormat:@"error %ld\n", (long)e.code] : text(d);
            done = YES;
          }] resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    return got;
}
static void echo(const char *what, NSURLSession *s, NSString *path)
{
    NSString *got = fetch(s, [NSURLRequest requestWithURL:U(path)]);
    for (NSString *line in [got componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"cookie="])
            printf("%s: %s\n", what, S(line));
}
// the file the shared storage saves to: ~/.config/ferry/cookies/<the program's name>.plist
static NSArray *saved(void)
{
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".config/ferry/cookies"];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    if (files.count != 1)
        return nil;
    return [NSArray arrayWithContentsOfFile:[dir stringByAppendingPathComponent:files[0]]];
}

static void objects(void)
{
    NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:@{
        NSHTTPCookieName : @"flavour",
        NSHTTPCookieValue : @"oat",
        NSHTTPCookieDomain : @".example.com",
        NSHTTPCookiePath : @"/shop",
        NSHTTPCookieSecure : @"TRUE",
        NSHTTPCookieExpires : [NSDate dateWithTimeIntervalSince1970:2000000000],
        NSHTTPCookieComment : @"a test",
    }];
    printf("from properties:\n");
    show(c);
    printf("  comment %s, version %lu\n", S(c.comment), (unsigned long)c.version);
    printf("  properties: %s\n",
           S([[c.properties.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]));
    printf("without a name: %s\n", B([NSHTTPCookie cookieWithProperties:@{NSHTTPCookieValue : @"x"}] != nil));
    printf("without a domain: %s\n",
           B([NSHTTPCookie cookieWithProperties:@{NSHTTPCookieName : @"x", NSHTTPCookieValue : @"y"}] != nil));
    NSHTTPCookie *o = [NSHTTPCookie cookieWithProperties:@{
        NSHTTPCookieName : @"x",
        NSHTTPCookieValue : @"y",
        NSHTTPCookieOriginURL : [NSURL URLWithString:@"http://www.example.com/a/b"],
    }];
    printf("from an origin URL:\n");
    show(o);

    NSURL *page = [NSURL URLWithString:@"http://www.example.com/dir/page"];
    NSArray *read = [NSHTTPCookie cookiesWithResponseHeaderFields:@{
        @"Set-Cookie" : @"a=1; Path=/; Domain=example.com, b=2; Expires=Wed, 21 Oct 2037 07:28:00 GMT; HttpOnly, "
                        @"c=3; Secure; Max-Age=60, d=4; Domain=other.com, e=5; Max-Age=0, f=\"quoted\"; Path=/x",
        @"Content-Type" : @"text/html"
    }
                                                           forURL:page];
    printf("read from Set-Cookie (%lu):\n", (unsigned long)read.count);
    for (NSHTTPCookie *k in read)
        show(k);
    printf("request fields: %s\n",
           S([NSHTTPCookie requestHeaderFieldsWithCookies:[read subarrayWithRange:NSMakeRange(0, 2)]][@"Cookie"]));
    printf("request fields for none: %lu\n", (unsigned long)[NSHTTPCookie requestHeaderFieldsWithCookies:@[]].count);
}

static void storage_first(void)
{
    NSHTTPCookieStorage *st = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    printf("shared storage: %lu cookies, policy %ld\n", (unsigned long)st.cookies.count, (long)st.cookieAcceptPolicy);
    __block int changes = 0;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSHTTPCookieManagerCookiesChangedNotification
                                                                 object:nil
                                                                  queue:nil
                                                             usingBlock:^(NSNotification *n) {
                                                               changes++;
                                                             }];
    NSURL *page = [NSURL URLWithString:@"http://www.example.com/dir/page"];
    NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:@{
        @"Set-Cookie" : @"keep=yes; Path=/; Domain=example.com; Expires=Wed, 21 Oct 2037 07:28:00 GMT, temp=1; "
                        @"Path=/dir, deep=2; Path=/dir/page, safe=3; Secure"
    }
                                                              forURL:page];
    [st setCookies:cookies forURL:page mainDocumentURL:nil];
    printf("for /dir/page: %s\n", S(names([st cookiesForURL:page])));
    printf("for /other: %s\n", S(names([st cookiesForURL:[NSURL URLWithString:@"http://www.example.com/other"]])));
    printf("over https: %s\n", S(names([st cookiesForURL:[NSURL URLWithString:@"https://www.example.com/dir/x"]])));
    printf("for another subdomain: %s\n",
           S(names([st cookiesForURL:[NSURL URLWithString:@"http://shop.example.com/"]])));
    printf("for another site: %s\n", S(names([st cookiesForURL:[NSURL URLWithString:@"http://example.org/"]])));
    // the same name, domain and path replaces
    [st setCookie:[NSHTTPCookie cookieWithProperties:@{
            NSHTTPCookieName : @"temp",
            NSHTTPCookieValue : @"2",
            NSHTTPCookieDomain : @"www.example.com",
            NSHTTPCookiePath : @"/dir"
        }]];
    printf("replaced: %s\n", S(names([st cookiesForURL:page])));
    NSHTTPCookie *deep = nil;
    for (NSHTTPCookie *k in st.cookies)
        if ([k.name isEqualToString:@"deep"])
            deep = k;
    [st deleteCookie:deep];
    printf("deleted deep: %s\n", S(names([st cookiesForURL:page])));
    NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
    printf("sorted by name: %s\n", S(names([st sortedCookiesUsingDescriptors:@[ byName ]])));

    // the accept policy
    NSArray *more = [NSHTTPCookie cookiesWithResponseHeaderFields:@{@"Set-Cookie" : @"late=1"} forURL:page];
    st.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    [st setCookies:more forURL:page mainDocumentURL:nil];
    printf("policy never: %s\n", S(names([st cookiesForURL:page])));
    st.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain;
    [st setCookies:more forURL:page mainDocumentURL:[NSURL URLWithString:@"http://example.org/"]];
    printf("from another main document's site: %s\n", S(names([st cookiesForURL:page])));
    [st setCookies:more forURL:page mainDocumentURL:[NSURL URLWithString:@"http://example.com/"]];
    printf("from the main document's site: %s\n", S(names([st cookiesForURL:page])));
    printf("changes posted: %s\n", B(changes > 0));
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    printf("saved: %s\n", S([[[saved() valueForKey:@"Name"] sortedArrayUsingSelector:@selector(compare:)]
                               componentsJoinedByString:@" "]));
}

static void sessions_first(void)
{
    NSURLSession *shared = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    printf("default configuration's storage is the shared one: %s, its policy %ld\n",
           B(shared.configuration.HTTPCookieStorage == [NSHTTPCookieStorage sharedHTTPCookieStorage]),
           (long)shared.configuration.HTTPCookieAcceptPolicy);
    echo("before", shared, @"/cookies/echo");
    fetch(shared, [NSURLRequest requestWithURL:setting(@[ @"sid=abc; Path=/", @"lasting=1; Max-Age=3600; Path=/" ])]);
    echo("after Set-Cookie", shared, @"/cookies/echo");
    fetch(shared, [NSURLRequest requestWithURL:setting(@[ @"narrow=1; Path=/cookies/echo" ])]);
    echo("with a narrower path", shared, @"/cookies/echo");
    echo("elsewhere", shared, @"/cookies/other");
    fetch(shared, [NSURLRequest requestWithURL:setting(@[ @"narrow=gone; Max-Age=0; Path=/cookies/echo" ])]);
    echo("expired by the server", shared, @"/cookies/echo");
    NSMutableURLRequest *without = [NSMutableURLRequest requestWithURL:U(@"/cookies/echo")];
    without.HTTPShouldHandleCookies = NO;
    printf("request without cookies: %s", S(fetch(shared, without)));
    NSMutableURLRequest *own = [NSMutableURLRequest requestWithURL:U(@"/cookies/echo")];
    [own setValue:@"mine=1" forHTTPHeaderField:@"Cookie"];
    printf("request with its own Cookie field: %s", S(fetch(shared, own)));
    // a cookie set by a redirect is sent to where it leads
    NSString *got = fetch(shared, [NSURLRequest requestWithURL:U(@"/cookies/redirect?v=7")]);
    for (NSString *line in [got componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"cookie="])
            printf("after a redirect that set one: %s\n", S(line));
    printf("dataWithContentsOfURL: %s", S(text([NSData dataWithContentsOfURL:U(@"/cookies/echo")])));
    NSURLResponse *r = nil;
    printf("NSURLConnection: %s",
           S(text([NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/cookies/echo")]
                                        returningResponse:&r
                                                    error:NULL])));

    // a configuration that neither sends nor keeps them
    NSURLSessionConfiguration *off = [NSURLSessionConfiguration defaultSessionConfiguration];
    off.HTTPShouldSetCookies = NO;
    NSURLSession *offSession = [NSURLSession sessionWithConfiguration:off];
    echo("HTTPShouldSetCookies off", offSession, @"/cookies/echo");
    fetch(offSession, [NSURLRequest requestWithURL:setting(@[ @"unwanted=1; Path=/" ])]);
    echo("and kept none", shared, @"/cookies/echo");
    NSURLSessionConfiguration *never = [NSURLSessionConfiguration defaultSessionConfiguration];
    never.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    NSURLSession *neverSession = [NSURLSession sessionWithConfiguration:never];
    fetch(neverSession, [NSURLRequest requestWithURL:setting(@[ @"refused=1; Path=/" ])]);
    echo("policy never: still sends", neverSession, @"/cookies/echo");
    NSURLSessionConfiguration *none = [NSURLSessionConfiguration defaultSessionConfiguration];
    none.HTTPCookieStorage = nil;
    echo("no storage", [NSURLSession sessionWithConfiguration:none], @"/cookies/echo");

    // an ephemeral session has cookies of its own
    NSURLSession *eph = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    echo("ephemeral, before", eph, @"/cookies/echo");
    fetch(eph, [NSURLRequest requestWithURL:setting(@[ @"private=1; Path=/; Max-Age=3600" ])]);
    echo("ephemeral, after", eph, @"/cookies/echo");
    echo("the shared storage didn't get it", shared, @"/cookies/echo");
    printf("ephemeral storage: %s\n", S(names(eph.configuration.HTTPCookieStorage.cookies)));
    printf("saved: %s\n", S([[[saved() valueForKey:@"Name"] sortedArrayUsingSelector:@selector(compare:)]
                               componentsJoinedByString:@" "]));
}

static void second(void)
{
    NSHTTPCookieStorage *st = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    printf("second run, read back: %s\n",
           S(names([st sortedCookiesUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                                                      ascending:YES] ]])));
    for (NSHTTPCookie *c in [st cookiesForURL:[NSURL URLWithString:@"http://www.example.com/"]])
        show(c);
    NSURLSession *shared = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    echo("sent again", shared, @"/cookies/echo");
    for (NSHTTPCookie *c in st.cookies)
        [st deleteCookie:c];
    printf("all deleted: %lu left, saved file %s\n", (unsigned long)st.cookies.count, B(saved() != nil));
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        const char *server = getenv("FERRY_TEST_HTTP");
        if (!server) {
            printf("FERRY_TEST_HTTP isn't set\n");
            return 1;
        }
        base = [NSString stringWithFormat:@"http://%s", server];
        if (argc > 1 && !strcmp(argv[1], "second")) {
            second();
            return 0;
        }
        objects();
        storage_first();
        sessions_first();
    }
    return 0;
}
