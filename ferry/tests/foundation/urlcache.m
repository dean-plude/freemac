// SPDX-License-Identifier: GPL-3.0-or-later
// NSURLCache and the request cache policies, against the test server on
// 127.0.0.1 (see urlsession.m): storing and reading responses by hand, in
// memory and on disk; Cache-Control max-age and no-store, Expires, ETag and
// Last-Modified revalidation (the server counts the requests it gets and
// the 304s it sends, at /hits); each NSURLRequestCachePolicy; the size rule;
// the delegate's willCacheResponse:. run.sh runs it twice in one home:
// "first" fills a cache on disk and the shared cache, "second" reads them
// back without the network. Built with ARC.
#import <Foundation/Foundation.h>

static NSString *base;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static const char *B(BOOL b) { return b ? "yes" : "no"; }
static NSString *text(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }
static NSString *chomp(NSString *s) { return [s hasSuffix:@"\n"] ? [s substringToIndex:s.length - 1] : s; }

static NSString *hits(NSString *path)
{
    NSString *q = [path stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    q = [q stringByReplacingOccurrencesOfString:@"?" withString:@"%3F"];
    q = [q stringByReplacingOccurrencesOfString:@"=" withString:@"%3D"];
    NSURLRequest *r = [NSURLRequest requestWithURL:U([@"/hits?u=" stringByAppendingString:q])
                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                   timeoutInterval:10];
    return chomp(text([NSURLConnection sendSynchronousRequest:r returningResponse:NULL error:NULL]));
}

static NSString *fetch_request(NSURLSession *s, NSURLRequest *r, NSHTTPURLResponse **response)
{
    __block NSString *got = nil;
    __block NSHTTPURLResponse *resp = nil;
    __block BOOL done = NO;
    [[s dataTaskWithRequest:r
          completionHandler:^(NSData *d, NSURLResponse *rr, NSError *e) {
            got = e ? [NSString stringWithFormat:@"error %ld", (long)e.code] : chomp(text(d));
            resp = (NSHTTPURLResponse *)rr;
            done = YES;
          }] resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    if (response)
        *response = resp;
    return got;
}
static void get(const char *what, NSURLSession *s, NSString *path, NSURLRequestCachePolicy policy)
{
    NSURLRequest *r = [NSURLRequest requestWithURL:U(path) cachePolicy:policy timeoutInterval:10];
    NSHTTPURLResponse *h = nil;
    NSString *got = fetch_request(s, r, &h);
    printf("%s: %s", what, S(got));
    if (h)
        printf(" (status %ld%s)", (long)h.statusCode,
               [h valueForHTTPHeaderField:@"X-Revalidated"] ? ", with a 304's fields" : "");
    printf("; server: %s\n", S(hits(path)));
}
static NSHTTPURLResponse *response_for(NSString *path, NSDictionary *fields)
{
    return [[NSHTTPURLResponse alloc] initWithURL:U(path) statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:fields];
}

static void by_hand(void)
{
    NSURLCache *c = [[NSURLCache alloc] initWithMemoryCapacity:100000 diskCapacity:1000000 diskPath:@"by-hand"];
    printf("capacities: %lu in memory, %lu on disk, used %lu\n", (unsigned long)c.memoryCapacity,
           (unsigned long)c.diskCapacity, (unsigned long)c.currentMemoryUsage);
    NSURLRequest *r = [NSURLRequest requestWithURL:U(@"/made/up")];
    NSCachedURLResponse *made = [[NSCachedURLResponse alloc]
        initWithResponse:response_for(@"/made/up", @{@"Content-Type" : @"text/plain", @"X-Note" : @"kept"})
                    data:[@"by hand" dataUsingEncoding:NSUTF8StringEncoding]
                userInfo:@{@"note" : @"user info"}
           storagePolicy:NSURLCacheStorageAllowed];
    [c storeCachedResponse:made forRequest:r];
    NSCachedURLResponse *back = [c cachedResponseForRequest:r];
    printf("stored: %s, field %s, user info %s, policy %lu, memory used %lu\n", S(text(back.data)),
           S([(NSHTTPURLResponse *)back.response valueForHTTPHeaderField:@"X-Note"]), S(back.userInfo[@"note"]),
           (unsigned long)back.storagePolicy, (unsigned long)c.currentMemoryUsage);
    printf("with a fragment: %s\n",
           B([c cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/made/up#part")]] != nil));
    printf("on disk: %s\n", B(c.currentDiskUsage > 0));
    NSURLRequest *m = [NSURLRequest requestWithURL:U(@"/memory/only")];
    [c storeCachedResponse:[[NSCachedURLResponse alloc] initWithResponse:response_for(@"/memory/only", @{})
                                                                    data:[NSData dataWithBytes:"m" length:1]
                                                                userInfo:nil
                                                           storagePolicy:NSURLCacheStorageAllowedInMemoryOnly]
                forRequest:m];
    NSURLCache *again = [[NSURLCache alloc] initWithMemoryCapacity:100000 diskCapacity:1000000 diskPath:@"by-hand"];
    printf("another cache on the same files: %s from disk, memory-only one %s\n",
           S(text([again cachedResponseForRequest:r].data)), B([again cachedResponseForRequest:m] != nil));
    printf("first cache, memory-only one: %s\n", B([c cachedResponseForRequest:m] != nil));
    [c removeCachedResponseForRequest:r];
    printf("removed: %s, from the other: %s\n", B([c cachedResponseForRequest:r] == nil),
           B([again cachedResponseForRequest:r] == nil));
    [c storeCachedResponse:made forRequest:r];
    [c removeAllCachedResponses];
    printf("all removed: %s, memory used %lu, disk used %lu\n", B([c cachedResponseForRequest:m] == nil),
           (unsigned long)c.currentMemoryUsage, (unsigned long)c.currentDiskUsage);
    [c storeCachedResponse:[[NSCachedURLResponse alloc] initWithResponse:response_for(@"/x", @{})
                                                                    data:[NSData dataWithBytes:"x" length:1]
                                                                userInfo:nil
                                                           storagePolicy:NSURLCacheStorageNotAllowed]
                forRequest:[NSURLRequest requestWithURL:U(@"/x")]];
    printf("not allowed: stored %s\n", B([c cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/x")]] != nil));
    NSCachedURLResponse *plain = [[NSCachedURLResponse alloc] initWithResponse:response_for(@"/y", @{})
                                                                          data:[NSData data]];
    printf("default storage policy: %lu\n", (unsigned long)plain.storagePolicy);
}

@interface Keeper : NSObject <NSURLSessionDataDelegate>
@property int mode; // 0 keep what is proposed, 1 refuse, 2 memory only
@property BOOL done;
@property NSMutableData *body;
@end
@implementation Keeper
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data
{
    [self.body appendData:data];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    willCacheResponse:(NSCachedURLResponse *)proposed
    completionHandler:(void (^)(NSCachedURLResponse *))completionHandler
{
    printf("  willCacheResponse: %s, policy %lu\n", S(chomp(text(proposed.data))), (unsigned long)proposed.storagePolicy);
    if (self.mode == 1)
        completionHandler(nil);
    else if (self.mode == 2)
        completionHandler([[NSCachedURLResponse alloc] initWithResponse:proposed.response
                                                                   data:[@"changed" dataUsingEncoding:NSUTF8StringEncoding]
                                                               userInfo:nil
                                                          storagePolicy:NSURLCacheStorageAllowedInMemoryOnly]);
    else
        completionHandler(proposed);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    printf("  completed: %s\n", S(chomp(text(self.body))));
    self.done = YES;
}
@end

static void sessions(void)
{
    NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:1000000 diskCapacity:10000000 diskPath:@"session"];
    conf.URLCache = cache;
    printf("default configuration's cache is the shared one: %s, policy %lu\n",
           B([NSURLSessionConfiguration defaultSessionConfiguration].URLCache == [NSURLCache sharedURLCache]),
           (unsigned long)conf.requestCachePolicy);
    printf("ephemeral configuration's cache is the shared one: %s\n",
           B([NSURLSessionConfiguration ephemeralSessionConfiguration].URLCache == [NSURLCache sharedURLCache]));
    NSURLSession *s = [NSURLSession sessionWithConfiguration:conf];
    NSURLRequestCachePolicy p = NSURLRequestUseProtocolCachePolicy;
    get("max-age, first", s, @"/cache/maxage?key=a", p);
    get("max-age, again", s, @"/cache/maxage?key=a", p);
    NSCachedURLResponse *kept = [cache cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/cache/maxage?key=a")]];
    printf("in the cache: %s, Cache-Control %s\n", S(chomp(text(kept.data))),
           S([(NSHTTPURLResponse *)kept.response valueForHTTPHeaderField:@"Cache-Control"]));
    get("max-age=0, first", s, @"/cache/maxage?age=0&key=b", p);
    get("max-age=0, again", s, @"/cache/maxage?age=0&key=b", p);
    get("Expires, first", s, @"/cache/expires?key=f", p);
    get("Expires, again", s, @"/cache/expires?key=f", p);
    get("ETag, first", s, @"/cache/etag?key=c", p);
    get("ETag, again", s, @"/cache/etag?key=c", p);
    get("Last-Modified, first", s, @"/cache/lastmod?key=d", p);
    get("Last-Modified, again", s, @"/cache/lastmod?key=d", p);
    get("no-store, first", s, @"/cache/nostore?key=e", p);
    get("no-store, again", s, @"/cache/nostore?key=e", p);
    printf("no-store in the cache: %s\n",
           B([cache cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/cache/nostore?key=e")]] != nil));

    // the request's own policy
    get("reload ignoring the cache", s, @"/cache/maxage?key=a", NSURLRequestReloadIgnoringLocalCacheData);
    get("then the protocol's policy", s, @"/cache/maxage?key=a", p);
    get("cache else load, stale ETag entry", s, @"/cache/etag?key=c", NSURLRequestReturnCacheDataElseLoad);
    get("cache else load, nothing stored", s, @"/cache/maxage?key=h", NSURLRequestReturnCacheDataElseLoad);
    get("cache, don't load, stored", s, @"/cache/maxage?key=h", NSURLRequestReturnCacheDataDontLoad);
    get("cache, don't load, nothing stored", s, @"/cache/maxage?key=never", NSURLRequestReturnCacheDataDontLoad);
    get("reload, revalidating", s, @"/cache/etag?key=c", NSURLRequestReloadRevalidatingCacheData);
    NSMutableURLRequest *nocache = [NSMutableURLRequest requestWithURL:U(@"/cache/maxage?key=a")];
    [nocache setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    printf("request's Cache-Control no-cache: %s; server: %s\n", S(fetch_request(s, nocache, NULL)),
           S(hits(@"/cache/maxage?key=a")));
    NSMutableURLRequest *post = [NSMutableURLRequest requestWithURL:U(@"/cache/maxage?key=p")];
    post.HTTPMethod = @"POST";
    fetch_request(s, post, NULL);
    printf("POST stored: %s\n", B([cache cachedResponseForRequest:post] != nil));

    // the configuration's policy, for requests that leave it to the protocol
    NSURLSessionConfiguration *conf2 = [conf copy];
    conf2.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
    NSURLSession *s2 = [NSURLSession sessionWithConfiguration:conf2];
    get("configuration's cache else load", s2, @"/cache/etag?key=c", p);
    conf2.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *s3 = [NSURLSession sessionWithConfiguration:conf2];
    get("configuration's reload", s3, @"/cache/maxage?key=a", p);

    // a response too large for the cache isn't kept: more than a twentieth of it
    NSURLSessionConfiguration *small = [NSURLSessionConfiguration defaultSessionConfiguration];
    small.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:100000 diskCapacity:0 diskPath:@"small"];
    NSURLSession *ss = [NSURLSession sessionWithConfiguration:small];
    fetch_request(ss, [NSURLRequest requestWithURL:U(@"/cache/big?n=4000")], NULL);
    fetch_request(ss, [NSURLRequest requestWithURL:U(@"/cache/big?n=6000")], NULL);
    printf("4000 bytes of 100000 kept: %s, 6000 kept: %s\n",
           B([small.URLCache cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/cache/big?n=4000")]] != nil),
           B([small.URLCache cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/cache/big?n=6000")]] != nil));

    // no cache at all
    NSURLSessionConfiguration *none = [NSURLSessionConfiguration defaultSessionConfiguration];
    none.URLCache = nil;
    NSURLSession *sn = [NSURLSession sessionWithConfiguration:none];
    get("no cache, first", sn, @"/cache/maxage?key=n", p);
    get("no cache, again", sn, @"/cache/maxage?key=n", p);

    // the delegate decides what is kept
    const char *modes[] = {"kept as proposed", "refused", "changed, in memory only"};
    for (int mode = 0; mode < 3; mode++) {
        Keeper *k = [Keeper new];
        k.mode = mode;
        k.body = [NSMutableData data];
        NSURLSession *ds = [NSURLSession sessionWithConfiguration:conf delegate:k
                                                    delegateQueue:[NSOperationQueue mainQueue]];
        NSString *path = [NSString stringWithFormat:@"/cache/maxage?key=delegate%d", mode];
        printf("delegate, %s\n", modes[mode]);
        [[ds dataTaskWithURL:U(path)] resume];
        while (!k.done)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        NSCachedURLResponse *c = [cache cachedResponseForRequest:[NSURLRequest requestWithURL:U(path)]];
        printf("  in the cache: %s, policy %lu\n", S(chomp(text(c.data))), (unsigned long)c.storagePolicy);
        [ds finishTasksAndInvalidate];
    }

    // a download isn't kept
    __block BOOL done = NO;
    [[s downloadTaskWithURL:U(@"/cache/maxage?key=download")
          completionHandler:^(NSURL *location, NSURLResponse *r, NSError *e) {
            done = YES;
          }] resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    printf("download kept: %s\n",
           B([cache cachedResponseForRequest:[NSURLRequest requestWithURL:U(@"/cache/maxage?key=download")]] != nil));

    // the shared cache, through the older calls
    NSData *d = [NSData dataWithContentsOfURL:U(@"/cache/maxage?key=shared")];
    d = [NSData dataWithContentsOfURL:U(@"/cache/maxage?key=shared")];
    printf("dataWithContentsOfURL twice: %s; server: %s\n", S(chomp(text(d))), S(hits(@"/cache/maxage?key=shared")));
    NSURLResponse *r = nil;
    d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/cache/maxage?key=shared")]
                              returningResponse:&r
                                          error:NULL];
    printf("NSURLConnection: %s; server: %s\n", S(chomp(text(d))), S(hits(@"/cache/maxage?key=shared")));
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".cache"];
    NSUInteger files = 0;
    for (NSString *f in [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:dir error:NULL])
        if ([f hasSuffix:@".plist"] && [[f stringByDeletingLastPathComponent] hasSuffix:@"/URLCache"])
            files++;
    printf("the shared cache's files in ~/.cache/<program>/URLCache: %lu\n", (unsigned long)files);
}

static void second(void)
{
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:1000000 diskCapacity:10000000 diskPath:@"session"];
    NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
    conf.URLCache = cache;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:conf];
    get("second run, from disk", s, @"/cache/maxage?key=a", NSURLRequestReturnCacheDataDontLoad);
    get("second run, ETag from disk, revalidated", s, @"/cache/etag?key=c", NSURLRequestUseProtocolCachePolicy);
    get("second run, the memory-only one", s, @"/cache/maxage?key=delegate2", NSURLRequestReturnCacheDataDontLoad);
    get("second run, the shared cache", [NSURLSession sharedSession], @"/cache/maxage?key=shared",
        NSURLRequestReturnCacheDataDontLoad);
    [cache removeAllCachedResponses];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    printf("removed: disk used %lu and %lu\n", (unsigned long)cache.currentDiskUsage,
           (unsigned long)[NSURLCache sharedURLCache].currentDiskUsage);
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
        by_hand();
        sessions();
    }
    return 0;
}
