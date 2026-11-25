// SPDX-License-Identifier: GPL-3.0-or-later
// NSURLDownload (freemac 1.223, Ferry 0.47.0), which Sparkle's older
// versions save an update with, against the test server on 127.0.0.1 (see
// urlsession.m): the delegate's calls in order, the file named from the
// server's name for it, a destination that may not be overwritten, an
// error from the server's side, and a download that can't be resumed.
#import <Foundation/Foundation.h>

static NSString *base;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }

@interface Saver : NSObject <NSURLDownloadDelegate>
@property (strong) NSMutableArray *events;
@property (copy) NSString *folder, *path;
@property BOOL done, overwrite;
@property NSUInteger received;
@end
@implementation Saver
- (instancetype)init
{
    if ((self = [super init]))
        _events = [NSMutableArray array];
    return self;
}
- (void)downloadDidBegin:(NSURLDownload *)d { [_events addObject:@"began"]; }
- (void)download:(NSURLDownload *)d didReceiveResponse:(NSURLResponse *)r
{
    [_events addObject:[NSString stringWithFormat:@"response %ld", (long)[(NSHTTPURLResponse *)r statusCode]]];
}
- (void)download:(NSURLDownload *)d decideDestinationWithSuggestedFilename:(NSString *)name
{
    [_events addObject:[NSString stringWithFormat:@"suggested \"%@\"", name]];
    [d setDestination:[_folder stringByAppendingPathComponent:name] allowOverwrite:_overwrite];
}
- (void)download:(NSURLDownload *)d didCreateDestination:(NSString *)path
{
    [_events addObject:[NSString stringWithFormat:@"created %@", [path lastPathComponent]]];
    self.path = path;
}
- (void)download:(NSURLDownload *)d didReceiveDataOfLength:(NSUInteger)n { _received += n; }
- (void)downloadDidFinish:(NSURLDownload *)d
{
    [_events addObject:@"finished"];
    _done = YES;
}
- (void)download:(NSURLDownload *)d didFailWithError:(NSError *)e
{
    [_events addObject:[NSString stringWithFormat:@"failed %@ %ld", [e domain], (long)[e code]]];
    _done = YES;
}
@end

static Saver *fetch(NSString *path, NSString *folder, BOOL overwrite)
{
    Saver *s = [Saver new];
    s.folder = folder;
    s.overwrite = overwrite;
    NSURLDownload *d = [[NSURLDownload alloc] initWithRequest:[NSURLRequest requestWithURL:U(path)] delegate:s];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!s.done && [until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    printf("%s: %s\n", [path UTF8String], [[s.events componentsJoinedByString:@", "] UTF8String]);
    (void)d;
    return s;
}

int main(void)
{
    @autoreleasepool {
        base = [NSString stringWithFormat:@"http://%s", getenv("FERRY_TEST_HTTP")];
        NSString *folder = NSTemporaryDirectory();
        Saver *s = fetch(@"/hello", folder, NO);
        printf("  %lu bytes, the file holds \"%s\"\n", (unsigned long)s.received,
               [[[NSString stringWithContentsOfFile:s.path encoding:NSUTF8StringEncoding error:NULL]
                   stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] UTF8String]);
        // the same name again, not to be overwritten: the download goes to another name
        Saver *again = fetch(@"/hello", folder, NO);
        printf("  a second file beside it: %s\n", [again.path isEqualToString:s.path] ? "no" : "yes");
        Saver *over = fetch(@"/hello", folder, YES);
        printf("  overwritten in place: %s\n", [over.path isEqualToString:s.path] ? "yes" : "no");
        fetch(@"/big?n=300000", folder, YES);
        fetch(@"/status/404", folder, YES);
        printf("can resume: %s, from resume data: %s\n",
               [NSURLDownload canResumeDownloadDecodedWithEncodingMIMEType:@"application/zip"] ? "yes" : "no",
               [[NSURLDownload alloc] initWithResumeData:[NSData data] delegate:s path:@"/tmp/x"] ? "yes" : "no");
    }
    return 0;
}
