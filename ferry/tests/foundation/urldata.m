// SPDX-License-Identifier: GPL-3.0-or-later
// data: URLs (RFC 2397), which need no network: NSURLSession data tasks,
// NSURLConnection, and NSData's and NSString's ...ContentsOfURL:. Built with ARC.
#import <Foundation/Foundation.h>

static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static NSString *text(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }

// the bytes as text when they are UTF-8 text, else in hexadecimal
static NSString *shown(NSData *d)
{
    NSString *s = text(d);
    BOOL printable = s.length > 0;
    for (NSUInteger i = 0; i < s.length; i++)
        if ([s characterAtIndex:i] < 0x20 || [s characterAtIndex:i] == 0xfffd)
            printable = NO;
    if (printable)
        return s;
    NSMutableString *hex = [NSMutableString stringWithString:@"hex"];
    for (NSUInteger i = 0; i < d.length; i++)
        [hex appendFormat:@" %02x", ((const unsigned char *)d.bytes)[i]];
    return hex;
}

static void task(NSString *url)
{
    __block BOOL done = NO;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                                   if (e)
                                       printf("%s: error %s %ld\n", S(url), S(e.domain), (long)e.code);
                                   else
                                       printf("%s: \"%s\" (%lu bytes), %s, encoding %s, length %lld, HTTP %s\n",
                                              S(url), S(shown(d)), (unsigned long)d.length, S(r.MIMEType),
                                              S(r.textEncodingName), r.expectedContentLength,
                                              [r isKindOfClass:[NSHTTPURLResponse class]] ? "yes" : "no");
                                   done = YES;
                                 }] resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
}

int main(void)
{
    @autoreleasepool {
        task(@"data:,Hello%2C%20World%21");
        task(@"data:text/plain;base64,SGVsbG8sIEZlcnJ5IQ==");
        task(@"data:text/html;charset=utf-8,%3Cb%3Ecaf%C3%A9%3C%2Fb%3E");
        task(@"data:;charset=iso-8859-1,caf%E9");
        task(@"data:application/octet-stream;base64,AAEC");
        task(@"data:text/plain,with%20a%20fragment#part");
        task(@"data:text/plain;base64,not*base64");
        task(@"data:no-comma");

        NSURL *u = [NSURL URLWithString:@"data:text/plain;charset=utf-8,caf%C3%A9"];
        printf("canHandleRequest: %s\n",
               [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:u]] ? "yes" : "no");
        NSURLResponse *r = nil;
        NSError *e = nil;
        NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:u] returningResponse:&r error:&e];
        printf("NSURLConnection: %s, %s\n", S(text(d)), S(r.MIMEType));
        printf("dataWithContentsOfURL: %s\n", S(text([NSData dataWithContentsOfURL:u])));
        printf("stringWithContentsOfURL:encoding: %s\n",
               S([NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:NULL]));
        NSStringEncoding used = 0;
        NSString *s = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"data:text/plain;charset=iso-8859-1,caf%E9"]
                                           usedEncoding:&used
                                                  error:NULL];
        printf("stringWithContentsOfURL:usedEncoding: %s, Latin-1 %s\n", S(s),
               used == NSISOLatin1StringEncoding ? "yes" : "no");
        d = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"data:no-comma"] options:0 error:&e];
        printf("a bad one: %s, %s %ld, underlying %ld\n", d ? "data" : "nil", S(e.domain), (long)e.code,
               (long)((NSError *)e.userInfo[NSUnderlyingErrorKey]).code);
    }
    return 0;
}
