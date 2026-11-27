/* SPDX-License-Identifier: GPL-3.0-or-later
 * An app talking to its own XPC service (freemac 1.264, Ferry 0.87.0), as
 * HandBrake hands its encodes to HandBrakeXPCService: the service starts
 * when the first message goes, gets objects and replies with blocks, waits
 * for a synchronous proxy, reports errors through the error handler, and
 * starts again after it quits. */
#import <Foundation/Foundation.h>
#import "proto.h"

int main(void)
{
    @autoreleasepool {
        NSXPCConnection *c = [[NSXPCConnection alloc] initWithServiceName:@"org.freemac.ferry.echo"];
        c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(Echo)];
        __block int interrupted = 0;
        c.interruptionHandler = ^{ interrupted++; };
        [c resume];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);

        id<Echo> proxy = [c remoteObjectProxyWithErrorHandler:^(NSError *e) {
            printf("error: %ld\n", (long)e.code);
            dispatch_semaphore_signal(done);
        }];
        [proxy shout:@"hello" times:3 reply:^(NSString *s, NSInteger pid) {
            printf("reply: %s, from another process: %s\n", s.UTF8String, pid != getpid() ? "yes" : "no");
            dispatch_semaphore_signal(done);
        }];
        long waited = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
        printf("answered: %s\n", waited ? "no" : "yes");

        NSDictionary *job = @{@"name" : @"movie", @"tracks" : @[ @1, @2, @3 ], @"length" : @6.5};
        [proxy describe:job reply:^(NSDictionary *d) {
            printf("dictionary back: %s, sum %ld\n", [d[@"name"] UTF8String], (long)[d[@"sum"] integerValue]);
            dispatch_semaphore_signal(done);
        }];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));

        id<Echo> sync = [c synchronousRemoteObjectProxyWithErrorHandler:^(NSError *e) {
            printf("sync error: %ld\n", (long)e.code);
        }];
        __block NSString *got = nil;
        [sync shout:@"now" times:2 reply:^(NSString *s, NSInteger pid) { got = [s copy]; }];
        printf("synchronous: %s\n", got ? got.UTF8String : "(nothing yet)");

        /* the service quits; the error handler hears, then the
         * interruption handler; the next message starts it again */
        [proxy quit];
        [proxy shout:@"lost" times:1 reply:^(NSString *s, NSInteger pid) { dispatch_semaphore_signal(done); }];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
        usleep(200000);
        printf("interrupted: %s\n", interrupted ? "yes" : "no");
        [proxy shout:@"again" times:1 reply:^(NSString *s, NSInteger pid) {
            printf("after it quit: %s\n", s.UTF8String);
            dispatch_semaphore_signal(done);
        }];
        waited = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
        printf("started again: %s\n", waited ? "no" : "yes");
        [c invalidate];

        NSXPCConnection *none = [[NSXPCConnection alloc] initWithServiceName:@"org.freemac.ferry.nothing"];
        none.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(Echo)];
        [none resume];
        [[none remoteObjectProxyWithErrorHandler:^(NSError *e) {
            printf("a service that isn't there: error %ld\n", (long)e.code);
            dispatch_semaphore_signal(done);
        }] quit];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
        [none invalidate];
    }
    return 0;
}
