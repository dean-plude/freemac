// SPDX-License-Identifier: GPL-3.0-or-later
// Ferry test: NSStream and CFStream. Streams on data, memory, a buffer and
// a file; a delegate's events in the run loop; a bound pair; TCP streams to
// an echo server on 127.0.0.1 (a delegate in the run loop, a CF client on a
// dispatch queue, and blocking use); a refused connection; a program's own
// socket; and TLS to run.sh's test server, whose certificate this system
// doesn't trust: refused by default, read when the chain isn't validated,
// and its trust given to the program. Built without ARC.
#import <Foundation/Foundation.h>
#include <CFNetwork/CFNetwork.h>
#include <Security/Security.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>

static void run_until(BOOL *flag, NSTimeInterval seconds)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!*flag && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

static NSString *text(NSData *d) { return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease]; }

/* ---- streams on memory and files ---- */

static void plain(void)
{
    NSInputStream *in = [NSInputStream inputStreamWithData:[@"abcdefghij" dataUsingEncoding:NSUTF8StringEncoding]];
    uint8_t buf[64];
    printf("data stream: status %lu", (unsigned long)[in streamStatus]);
    [in open];
    printf(", open %lu, has bytes %d", (unsigned long)[in streamStatus], [in hasBytesAvailable]);
    NSInteger n = [in read:buf maxLength:4];
    printf(", read %ld \"%.*s\"", (long)n, (int)n, buf);
    n = [in read:buf maxLength:sizeof buf];
    printf(", then %ld \"%.*s\"", (long)n, (int)n, buf);
    n = [in read:buf maxLength:sizeof buf];
    printf(", then %ld, status %lu (at end)\n", (long)n, (unsigned long)[in streamStatus]);
    [in close];
    printf("closed: status %lu, read %ld\n", (unsigned long)[in streamStatus], (long)[in read:buf maxLength:1]);

    CFReadStreamRef cr = CFReadStreamCreateWithBytesNoCopy(NULL, (const UInt8 *)"0123456789", 10, kCFAllocatorNull);
    CFReadStreamOpen(cr);
    CFIndex got = 0;
    const UInt8 *p = CFReadStreamGetBuffer(cr, 3, &got);
    printf("CF bytes stream: buffer \"%.*s\" (%ld)", (int)got, p, (long)got);
    got = CFReadStreamRead(cr, buf, sizeof buf);
    printf(", then read \"%.*s\"\n", (int)got, buf);
    CFRelease(cr);

    NSOutputStream *mem = [NSOutputStream outputStreamToMemory];
    [mem open];
    [mem write:(const uint8_t *)"hello " maxLength:6];
    [mem write:(const uint8_t *)"memory" maxLength:6];
    NSData *written = [mem propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    printf("memory stream: \"%s\", has space %d\n", [text(written) UTF8String], [mem hasSpaceAvailable]);
    [mem close];

    uint8_t small[4];
    NSOutputStream *fixed = [NSOutputStream outputStreamToBuffer:small capacity:sizeof small];
    [fixed open];
    NSInteger a = [fixed write:(const uint8_t *)"abcdef" maxLength:6];
    NSInteger b = [fixed write:(const uint8_t *)"g" maxLength:1];
    printf("buffer stream: wrote %ld then %ld, \"%.4s\", status %lu (at end)\n", (long)a, (long)b, small,
           (unsigned long)[fixed streamStatus]);

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ferry-streams-%d", getpid()]];
    NSOutputStream *fo = [NSOutputStream outputStreamToFileAtPath:path append:NO];
    [fo open];
    [fo write:(const uint8_t *)"line one\n" maxLength:9];
    [fo close];
    fo = [NSOutputStream outputStreamToFileAtPath:path append:YES];
    [fo open];
    [fo write:(const uint8_t *)"line two\n" maxLength:9];
    [fo close];
    NSInputStream *fi = [NSInputStream inputStreamWithFileAtPath:path];
    [fi setProperty:[NSNumber numberWithInt:5] forKey:NSStreamFileCurrentOffsetKey];
    [fi open];
    n = [fi read:buf maxLength:sizeof buf];
    printf("file stream from offset 5: \"%.*s\", offset now %d\n", (int)n - 1, buf,
           [[fi propertyForKey:NSStreamFileCurrentOffsetKey] intValue]);
    [fi close];
    unlink([path fileSystemRepresentation]);
    NSInputStream *missing = [NSInputStream inputStreamWithFileAtPath:path];
    [missing open];
    printf("a missing file: status %lu, %s %ld\n", (unsigned long)[missing streamStatus],
           [[[missing streamError] domain] UTF8String], (long)[[missing streamError] code]);
}

/* ---- a delegate's events ---- */

@interface Reader : NSObject <NSStreamDelegate> {
@public
    NSMutableString *log;
    NSMutableData *got;
    NSUInteger chunk;
    BOOL done;
}
@end
@implementation Reader
- (instancetype)init
{
    self = [super init];
    log = [[NSMutableString alloc] init];
    got = [[NSMutableData alloc] init];
    chunk = 4;
    return self;
}
- (void)dealloc
{
    [log release];
    [got release];
    [super dealloc];
}
- (void)stream:(NSStream *)s handleEvent:(NSStreamEvent)ev
{
    switch (ev) {
    case NSStreamEventOpenCompleted: [log appendString:@" open"]; break;
    case NSStreamEventHasBytesAvailable: {
        uint8_t buf[64];
        NSInteger n = [(NSInputStream *)s read:buf maxLength:chunk];
        if (n > 0)
            [got appendBytes:buf length:(NSUInteger)n];
        [log appendFormat:@" bytes(%ld)", (long)n];
        break;
    }
    case NSStreamEventEndEncountered:
        [log appendString:@" end"];
        [s close];
        [s removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        done = YES;
        break;
    case NSStreamEventErrorOccurred:
        [log appendFormat:@" error(%@ %ld)", [[s streamError] domain], (long)[[s streamError] code]];
        [s close];
        done = YES;
        break;
    default: [log appendFormat:@" %lu", (unsigned long)ev];
    }
}
@end

static void delegated(void)
{
    NSInputStream *in = [NSInputStream inputStreamWithData:[@"0123456789" dataUsingEncoding:NSUTF8StringEncoding]];
    Reader *r = [[Reader alloc] init];
    printf("a stream is its own delegate: %d\n", [in delegate] == (id)in);
    [in setDelegate:r];
    [in scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [in open];
    printf("nothing before the run loop runs: \"%s\"\n", [r->log UTF8String]);
    run_until(&r->done, 5);
    printf("data stream events:%s, read \"%s\"\n", [r->log UTF8String], [text(r->got) UTF8String]);
    [r release];
}

/* ---- a bound pair ---- */

@interface Writer : NSObject <NSStreamDelegate> {
@public
    NSData *data;
    NSUInteger sent;
    int spaces;
}
@end
@implementation Writer
- (void)stream:(NSStream *)s handleEvent:(NSStreamEvent)ev
{
    if (ev == NSStreamEventHasSpaceAvailable) {
        spaces++;
        if (sent < [data length]) {
            NSInteger n = [(NSOutputStream *)s write:(const uint8_t *)[data bytes] + sent
                                           maxLength:MIN((NSUInteger)7, [data length] - sent)];
            if (n > 0)
                sent += (NSUInteger)n;
        }
        if (sent == [data length]) {
            [s close];
            [s removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        }
    }
}
@end

static void bound(void)
{
    NSInputStream *in = nil;
    NSOutputStream *out = nil;
    [NSStream getBoundStreamsWithBufferSize:16 inputStream:&in outputStream:&out];
    Reader *r = [[Reader alloc] init];
    r->chunk = 64;
    Writer *w = [[Writer alloc] init];
    w->data = [@"the quick brown fox jumps over the lazy dog" dataUsingEncoding:NSUTF8StringEncoding];
    [in setDelegate:r];
    [out setDelegate:w];
    [in scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [out scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [in open];
    [out open];
    run_until(&r->done, 5);
    printf("bound pair: read \"%s\", written in pieces %d, the reader ended %d\n", [text(r->got) UTF8String],
           w->spaces >= 7, r->done);
    [r release];
    [w release];
}

/* ---- an echo server on 127.0.0.1: what each connection sends, in capitals, until "bye" ---- */

static int echo_port, connections;

static void *echo_server(void *arg)
{
    int ls = (int)(intptr_t)arg;
    for (;;) {
        int c = accept(ls, NULL, NULL);
        if (c < 0)
            return NULL;
        __atomic_add_fetch(&connections, 1, __ATOMIC_SEQ_CST);
        char buf[256];
        ssize_t n;
        size_t have = 0;
        char seen[512] = {0};
        while ((n = read(c, buf, sizeof buf)) > 0) {
            for (ssize_t i = 0; i < n; i++)
                buf[i] = (char)(buf[i] >= 'a' && buf[i] <= 'z' ? buf[i] - 32 : buf[i]);
            write(c, buf, (size_t)n);
            if (have + (size_t)n < sizeof seen - 1) {
                memcpy(seen + have, buf, (size_t)n);
                have += (size_t)n;
            }
            if (strstr(seen, "BYE\n"))
                break;
        }
        close(c);
    }
}

static void start_server(void)
{
    int ls = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sin;
    socklen_t len = sizeof sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_len = sizeof sin;
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(ls, (struct sockaddr *)&sin, sizeof sin);
    listen(ls, 8);
    getsockname(ls, (struct sockaddr *)&sin, &len);
    echo_port = ntohs(sin.sin_port);
    pthread_t t;
    pthread_create(&t, NULL, echo_server, (void *)(intptr_t)ls);
    pthread_detach(t);
}

@interface Talker : NSObject <NSStreamDelegate> {
@public
    NSInputStream *in;
    NSOutputStream *out;
    NSData *say;
    NSMutableData *heard;
    BOOL inOpen, outOpen, said, ended, failed;
    int bytesEvents;
    NSError *error;
}
@end
@implementation Talker
- (void)stream:(NSStream *)s handleEvent:(NSStreamEvent)ev
{
    switch (ev) {
    case NSStreamEventOpenCompleted:
        if (s == in)
            inOpen = YES;
        else
            outOpen = YES;
        break;
    case NSStreamEventHasSpaceAvailable:
        if (!said) {
            said = YES;
            [out write:[say bytes] maxLength:[say length]];
        }
        break;
    case NSStreamEventHasBytesAvailable: {
        uint8_t buf[256];
        NSInteger n = [in read:buf maxLength:sizeof buf];
        if (n > 0)
            [heard appendBytes:buf length:(NSUInteger)n];
        bytesEvents++;
        break;
    }
    case NSStreamEventEndEncountered: ended = YES; break;
    case NSStreamEventErrorOccurred:
        failed = YES;
        error = [[s streamError] retain];
        break;
    default: break;
    }
}
@end

static Talker *talk(NSString *host, int port, NSString *say, NSString *level)
{
    Talker *t = [[[Talker alloc] init] autorelease];
    NSInputStream *in = nil;
    NSOutputStream *out = nil;
    [NSStream getStreamsToHostWithName:host port:port inputStream:&in outputStream:&out];
    t->in = [in retain];
    t->out = [out retain];
    t->say = [[say dataUsingEncoding:NSUTF8StringEncoding] retain];
    t->heard = [[NSMutableData alloc] init];
    [in setDelegate:t];
    [out setDelegate:t];
    if (level) /* before open: TLS settings are given before the connection is made */
        [in setProperty:level forKey:NSStreamSocketSecurityLevelKey];
    [in scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [out scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [in open];
    [out open];
    return t;
}

static void finish(Talker *t)
{
    [t->in close];
    [t->out close];
    [t->in release];
    [t->out release];
    [t->say release];
    [t->heard release];
    [t->error release];
}

static void tcp_delegate(void)
{
    Talker *t = talk(@"127.0.0.1", echo_port, @"hello\nbye\n", nil);
    /* the connection is made on another thread: opening, or open already */
    NSStreamStatus is = [t->in streamStatus], os = [t->out streamStatus];
    printf("socket streams opened: opening or open %d %d\n", is == NSStreamStatusOpening || is == NSStreamStatusOpen,
           os == NSStreamStatusOpening || os == NSStreamStatusOpen);
    BOOL stop = NO;
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!stop && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        stop = t->ended || t->failed;
    }
    NSData *native = [t->in propertyForKey:(NSString *)kCFStreamPropertySocketNativeHandle];
    printf("delegate: both opened %d %d, heard \"%s\" in %d bytes events or more, the end %d, error %d\n", t->inOpen,
           t->outOpen, [[text(t->heard) stringByReplacingOccurrencesOfString:@"\n" withString:@"|"] UTF8String],
           t->bytesEvents >= 1, t->ended, t->failed);
    printf("properties: host %s, port is the server's %d, native handle %lu bytes, status %lu (at end)\n",
           [[t->in propertyForKey:(NSString *)kCFStreamPropertySocketRemoteHostName] UTF8String],
           [[t->out propertyForKey:(NSString *)kCFStreamPropertySocketRemotePortNumber] intValue] == echo_port,
           (unsigned long)[native length], (unsigned long)[t->in streamStatus]);
    finish(t);
}

/* the CF client API, on a dispatch queue */
static CFReadStreamRef q_in;
static CFWriteStreamRef q_out;
static NSMutableData *q_heard;
static dispatch_semaphore_t q_done;
static int q_on_queue = 1, q_events;
static int q_key;

static void q_read(CFReadStreamRef s, CFStreamEventType type, void *info)
{
    if (dispatch_get_specific(&q_key) != &q_key)
        q_on_queue = 0;
    q_events |= (int)type;
    if (type == kCFStreamEventHasBytesAvailable) {
        UInt8 buf[256];
        CFIndex n = CFReadStreamRead(s, buf, sizeof buf);
        if (n > 0)
            [q_heard appendBytes:buf length:(NSUInteger)n];
    } else if (type == kCFStreamEventEndEncountered || type == kCFStreamEventErrorOccurred)
        dispatch_semaphore_signal(q_done);
}

static void q_write(CFWriteStreamRef s, CFStreamEventType type, void *info)
{
    static int said;
    if (type == kCFStreamEventCanAcceptBytes && !said) {
        said = 1;
        CFWriteStreamWrite(s, (const UInt8 *)info, (CFIndex)strlen(info));
    }
}

static void tcp_queue(void)
{
    q_heard = [[NSMutableData alloc] init];
    q_done = dispatch_semaphore_create(0);
    dispatch_queue_t q = dispatch_queue_create("streams", NULL);
    dispatch_queue_set_specific(q, &q_key, &q_key, NULL);
    CFStreamCreatePairWithSocketToHost(NULL, CFSTR("127.0.0.1"), (UInt32)echo_port, &q_in, &q_out);
    CFStreamClientContext ctx = {0, "queue\nbye\n", NULL, NULL, NULL};
    CFOptionFlags all = kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventCanAcceptBytes |
                        kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered;
    printf("CF clients set %d %d\n", CFReadStreamSetClient(q_in, all, q_read, &ctx),
           CFWriteStreamSetClient(q_out, all, q_write, &ctx));
    CFReadStreamSetDispatchQueue(q_in, q);
    CFWriteStreamSetDispatchQueue(q_out, q);
    dispatch_queue_t back = CFReadStreamCopyDispatchQueue(q_in);
    printf("its queue back %d\n", back == q);
    dispatch_release(back);
    printf("opened %d %d\n", CFReadStreamOpen(q_in), CFWriteStreamOpen(q_out));
    long w = dispatch_semaphore_wait(q_done, dispatch_time(DISPATCH_TIME_NOW, 10000000000ll));
    printf("dispatch queue: waited %ld, heard \"%s\", events open %d bytes %d end %d, all on its queue %d\n", w,
           [[text(q_heard) stringByReplacingOccurrencesOfString:@"\n" withString:@"|"] UTF8String],
           (q_events & kCFStreamEventOpenCompleted) != 0, (q_events & kCFStreamEventHasBytesAvailable) != 0,
           (q_events & kCFStreamEventEndEncountered) != 0, q_on_queue);
    CFReadStreamSetDispatchQueue(q_in, NULL);
    CFWriteStreamSetDispatchQueue(q_out, NULL);
    CFReadStreamClose(q_in);
    CFWriteStreamClose(q_out);
    printf("closed: status %ld\n", (long)CFReadStreamGetStatus(q_in));
    CFRelease(q_in);
    CFRelease(q_out);
    dispatch_release(q);
    [q_heard release];
}

/* blocking, not scheduled */
static NSString *read_all(NSInputStream *in)
{
    NSMutableData *d = [NSMutableData data];
    uint8_t buf[512];
    NSInteger n;
    while ((n = [in read:buf maxLength:sizeof buf]) > 0)
        [d appendBytes:buf length:(NSUInteger)n];
    return n < 0 ? [NSString stringWithFormat:@"(error %ld)", (long)[[in streamError] code]] : text(d);
}

static void tcp_blocking(void)
{
    NSInputStream *in = nil;
    NSOutputStream *out = nil;
    [NSStream getStreamsToHostWithName:@"localhost" port:echo_port inputStream:&in outputStream:&out];
    [in open];
    [out open];
    NSInteger n = [out write:(const uint8_t *)"blocking\nbye\n" maxLength:13];
    NSString *s = read_all(in);
    printf("blocking: wrote %ld, read \"%s\", status %lu\n", (long)n,
           [[s stringByReplacingOccurrencesOfString:@"\n" withString:@"|"] UTF8String], (unsigned long)[in streamStatus]);
    [in close];
    [out close];
}

static void refused(void)
{
    int tmp = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sin;
    socklen_t len = sizeof sin;
    memset(&sin, 0, sizeof sin);
    sin.sin_len = sizeof sin;
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(tmp, (struct sockaddr *)&sin, sizeof sin);
    getsockname(tmp, (struct sockaddr *)&sin, &len);
    close(tmp);
    Talker *t = talk(@"127.0.0.1", ntohs(sin.sin_port), @"nobody\n", nil);
    run_until(&t->failed, 10);
    CFStreamError e = CFReadStreamGetError((CFReadStreamRef)t->in);
    printf("refused: error event %d, %s %ld, CF error domain %ld code %d, status %lu, opened %d\n", t->failed,
           [[t->error domain] UTF8String], (long)[t->error code], (long)e.domain, (int)e.error,
           (unsigned long)[t->in streamStatus], t->inOpen);
    printf("refused, blocking: write %ld\n", (long)[t->out write:(const uint8_t *)"x" maxLength:1]);
    finish(t);
}

static void native(void)
{
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    CFReadStreamRef r;
    CFWriteStreamRef w;
    CFStreamCreatePairWithSocket(NULL, sv[0], &r, &w);
    CFReadStreamOpen(r);
    CFWriteStreamOpen(w);
    CFIndex n = CFWriteStreamWrite(w, (const UInt8 *)"native", 6);
    char buf[16] = {0};
    read(sv[1], buf, sizeof buf - 1);
    write(sv[1], "back", 4);
    UInt8 in[16] = {0};
    CFIndex m = CFReadStreamRead(r, in, sizeof in - 1);
    CFDataRef h = CFReadStreamCopyProperty(r, kCFStreamPropertySocketNativeHandle);
    int fd = -1;
    memcpy(&fd, CFDataGetBytePtr(h), sizeof fd);
    CFRelease(h);
    CFReadStreamClose(r);
    CFWriteStreamClose(w);
    CFRelease(r);
    CFRelease(w);
    printf("a socket of the program's: wrote %ld \"%s\", read %ld \"%s\", handle the same %d, still open %d\n", (long)n,
           buf, (long)m, in, fd == sv[0], fcntl(sv[0], F_GETFL) >= 0);
    close(sv[0]);
    close(sv[1]);
}

/* ---- TLS ---- */

static void tls(void)
{
    const char *where = getenv("FERRY_TEST_HTTPS"), *certPath = getenv("FERRY_TEST_TLS_CERT");
    if (!where || !*where || !certPath) {
        printf("TLS: no test server\n");
        return;
    }
    int port = atoi(strchr(where, ':') + 1);

    /* by default the chain is checked, against this system's authorities */
    Talker *t = talk(@"127.0.0.1", port, @"", NSStreamSocketSecurityLevelNegotiatedSSL);
    printf("TLS level set: %s\n", [[t->out propertyForKey:NSStreamSocketSecurityLevelKey] UTF8String]);
    run_until(&t->failed, 10);
    printf("TLS, untrusted server: error event %d, %s %ld, opened %d\n", t->failed,
           [[t->error domain] UTF8String], (long)[t->error code], t->inOpen);
    finish(t);

    /* not validated: the connection is made; the program checks the trust itself */
    CFReadStreamRef r;
    CFWriteStreamRef w;
    CFStreamCreatePairWithSocketToHost(NULL, CFSTR("127.0.0.1"), (UInt32)port, &r, &w);
    NSDictionary *settings = [NSDictionary dictionaryWithObject:(id)kCFBooleanFalse
                                                         forKey:(NSString *)kCFStreamSSLValidatesCertificateChain];
    printf("SSL settings taken %d\n", CFWriteStreamSetProperty(w, kCFStreamPropertySSLSettings, (CFDictionaryRef)settings));
    CFReadStreamOpen(r);
    CFWriteStreamOpen(w);
    const char *req = "GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
    CFIndex n = CFWriteStreamWrite(w, (const UInt8 *)req, (CFIndex)strlen(req));
    NSString *reply = read_all((NSInputStream *)r);
    NSArray *lines = [reply componentsSeparatedByString:@"\r\n"];
    printf("TLS, not validated: wrote %d, status line \"%s\", body \"%s\"\n", n == (CFIndex)strlen(req),
           [[lines objectAtIndex:0] UTF8String],
           [[[lines lastObject] stringByReplacingOccurrencesOfString:@"\n" withString:@""] UTF8String]);
    SecTrustRef trust = (SecTrustRef)CFReadStreamCopyProperty(r, kCFStreamPropertySSLPeerTrust);
    NSData *der = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:certPath]];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (CFDataRef)der);
    printf("its trust: %ld certificate, the server's file %d", (long)(trust ? SecTrustGetCertificateCount(trust) : -1),
           trust && CFEqual(SecTrustGetCertificateAtIndex(trust, 0), cert));
    if (trust) {
        printf(", trusted as is %d", SecTrustEvaluateWithError(trust, NULL));
        SecTrustSetAnchorCertificates(trust, (CFArrayRef)[NSArray arrayWithObject:(id)cert]);
        printf(", with it as the anchor %d", SecTrustEvaluateWithError(trust, NULL));
        CFRelease(trust);
    }
    printf("\n");
    CFRelease(cert);
    CFReadStreamClose(r);
    CFWriteStreamClose(w);
    printf("TLS settings after open taken %d\n",
           CFWriteStreamSetProperty(w, kCFStreamPropertySSLSettings, (CFDictionaryRef)settings));
    CFRelease(r);
    CFRelease(w);
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    setvbuf(stdout, NULL, _IONBF, 0);
    plain();
    delegated();
    bound();
    start_server();
    tcp_delegate();
    tcp_queue();
    tcp_blocking();
    printf("the echo server saw %d connections\n", __atomic_load_n(&connections, __ATOMIC_SEQ_CST));
    refused();
    native();
    tls();
    [pool release];
    return 0;
}
