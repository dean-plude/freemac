// SPDX-License-Identifier: GPL-3.0-or-later
// Ferry test: NSNetService and NSNetServiceBrowser without Bonjour. TXT
// records are made and read; publishing, resolving and searching say
// "will" and then fail in the run loop with NSNetServicesUnknownError, as
// they do on a Mac where mDNSResponder can't be reached. Built without ARC.
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface Listener : NSObject <NSNetServiceDelegate, NSNetServiceBrowserDelegate> {
@public
    NSMutableString *log;
    int failures;
}
@end
@implementation Listener
- (void)netServiceWillPublish:(NSNetService *)sender { [log appendString:@" will-publish"]; }
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    [log appendFormat:@" did-not-publish(%@)", [errorDict objectForKey:NSNetServicesErrorCode]];
    failures++;
}
- (void)netServiceWillResolve:(NSNetService *)sender { [log appendString:@" will-resolve"]; }
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    [log appendFormat:@" did-not-resolve(%@)", [errorDict objectForKey:NSNetServicesErrorCode]];
    failures++;
}
- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser { [log appendString:@" will-search"]; }
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary *)errorDict
{
    [log appendFormat:@" did-not-search(%@)", [errorDict objectForKey:NSNetServicesErrorCode]];
    failures++;
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *txt = [NSDictionary dictionaryWithObjectsAndKeys:[@"1" dataUsingEncoding:NSUTF8StringEncoding], @"version",
                                                                   [@"a=b" dataUsingEncoding:NSUTF8StringEncoding], @"path",
                                                                   [NSData data], @"flag", nil];
    NSData *record = [NSNetService dataFromTXTRecordDictionary:txt];
    const unsigned char *p = [record bytes];
    printf("TXT record: %lu bytes, first string %d bytes \"%.*s\"\n", (unsigned long)[record length], p[0], p[0], p + 1);
    NSDictionary *back = [NSNetService dictionaryFromTXTRecordData:record];
    NSArray *keys = [[back allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *k in keys) {
        NSData *v = [back objectForKey:k];
        printf("  %s = \"%.*s\"\n", [k UTF8String], (int)[v length], (const char *)[v bytes]);
    }
    const unsigned char raw[] = {5, 'l', 'o', 'n', 'e', 'k', 3, 'a', '=', '1', 3, 'a', '=', '2', 9, 'b', 'r', 'o', 'k'};
    NSDictionary *odd = [NSNetService dictionaryFromTXTRecordData:[NSData dataWithBytes:raw length:sizeof raw]];
    printf("a lone key, a repeated key, a cut string: %lu keys, lonek empty %d, a \"%.*s\"\n", (unsigned long)[odd count],
           [[odd objectForKey:@"lonek"] length] == 0, (int)[[odd objectForKey:@"a"] length],
           (const char *)[[odd objectForKey:@"a"] bytes]);

    Listener *l = [[Listener alloc] init];
    l->log = [[NSMutableString alloc] init];
    NSNetService *svc = [[NSNetService alloc] initWithDomain:@"local." type:@"_ferry._tcp." name:@"Test" port:4242];
    [svc setDelegate:l];
    printf("service: %s %s %s port %ld, TXT set %d\n", [[svc name] UTF8String], [[svc type] UTF8String],
           [[svc domain] UTF8String], (long)[svc port], [svc setTXTRecordData:record]);
    [svc publish];
    NSNetService *other = [[NSNetService alloc] initWithDomain:@"local." type:@"_ferry._tcp." name:@"Other"];
    [other setDelegate:l];
    [other resolveWithTimeout:1];
    NSNetServiceBrowser *browser = [[NSNetServiceBrowser alloc] init];
    [browser setDelegate:l];
    [browser searchForServicesOfType:@"_ferry._tcp." inDomain:@"local."];
    printf("nothing before the run loop runs: \"%s\"\n", [l->log UTF8String]);
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (l->failures < 3 && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    printf("events:%s\n", [l->log UTF8String]);
    printf("resolved: host %s, %lu addresses\n", [svc hostName] ? "yes" : "none", (unsigned long)[[other addresses] count]);
    [svc stop];
    [browser stop];
    [svc release];
    [other release];
    [browser release];
    [l->log release];
    [l release];
    [pool release];
    return 0;
}
