/* Dispatch with Foundation and ARC (M6): a serial queue's work runs on a
 * worker thread, blocks it sends to the main queue run on the main run
 * loop, timers and dispatch_after wake it, and ARC retains and releases
 * dispatch objects like any other object. */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

@interface Worker : NSObject
@property (strong) dispatch_queue_t queue;
@property NSInteger done;
@end
@implementation Worker
- (void)dealloc { printf("worker released\n"); }
@end

int main(void)
{
    @autoreleasepool {
        __weak dispatch_queue_t weakQueue;
        @autoreleasepool {
            Worker *w = [Worker new];
            w.queue = dispatch_queue_create("worker", DISPATCH_QUEUE_SERIAL);
            weakQueue = w.queue;
            dispatch_async(w.queue, ^{
                w.done++;
                BOOL off = ![NSThread isMainThread];
                dispatch_async(dispatch_get_main_queue(), ^{
                    printf("back on the main queue: done %ld, worked off the main thread %d, now on it %d\n",
                           (long)w.done, off, [NSThread isMainThread]);
                });
            });
            printf("queued\n");
        }
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("the queue was released with its worker: %s\n", weakQueue == nil ? "yes" : "no");

        NSDate *start = [NSDate date];
        __block BOOL fired = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            fired = YES;
            CFRunLoopStop(CFRunLoopGetMain());
        });
        CFRunLoopRun();
        double took = -[start timeIntervalSinceNow];
        printf("dispatch_after fired: %s, after at least 0.1 s: %s\n", fired ? "yes" : "no", took >= 0.099 ? "yes" : "no");

        /* NSObject's performSelector paths and dispatch share the loop. */
        __block NSMutableArray *order = [NSMutableArray array];
        dispatch_async(dispatch_get_main_queue(), ^{ [order addObject:@"dispatch"]; });
        [[NSRunLoop mainRunLoop] performBlock:^{ [order addObject:@"runloop"]; }];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        printf("both ran: %s\n", [[order componentsJoinedByString:@","] UTF8String]);
    }
    return 0;
}
