/* SPDX-License-Identifier: GPL-3.0-or-later
 * Objective-C's __thread variables with NSThread: threads started with a
 * target and selector, with a block, detached and in the background each
 * see the variables' first values and keep their own, one leaves with
 * +[NSThread exit], and destructors registered for each thread with
 * _tlv_atexit run as it ends. Lines are printed by the main thread only,
 * in a fixed order; an alarm makes a hang fail. */
#import <Foundation/Foundation.h>
#include <signal.h>
#include <unistd.h>

void _tlv_atexit(void (*fn)(void *), void *obj);

static void on_alarm(int sig)
{
    static const char msg[] = "tlv_objc: timed out\n";
    write(2, msg, sizeof msg - 1);
    _exit(3);
}

__thread int calls;
__thread __unsafe_unretained NSString *label = nil;
static __thread NSInteger depth = 2;
_Thread_local double scale = 1.5;

static NSCondition *finished_lock;
static int finished, ended;
static NSMutableArray *reports;

static void thread_ended(void *obj)
{
    (void)obj;
    __atomic_add_fetch(&ended, 1, __ATOMIC_ACQ_REL);
}

@interface Job : NSObject
- (void)run:(NSNumber *)n;
@end

@implementation Job
- (void)run:(NSNumber *)number
{
    int n = number.intValue;
    BOOL fresh = calls == 0 && label == nil && depth == 2 && scale == 1.5;
    NSString *mine = [NSString stringWithFormat:@"job %d", n];
    label = mine;
    _tlv_atexit(thread_ended, NULL);
    for (int i = 0; i < n * 1000; i++) {
        calls++;
        depth += 2;
    }
    scale *= n;
    BOOL kept = calls == n * 1000 && depth == 2 + 2 * n * 1000 && [label isEqualToString:mine] && scale == 1.5 * n;
    [finished_lock lock];
    [reports addObject:[NSString stringWithFormat:@"%@: fresh %s, kept %s, on the main thread %s", label,
                                                  fresh ? "yes" : "no", kept ? "yes" : "no",
                                                  [NSThread isMainThread] ? "yes" : "no"]];
    finished++;
    [finished_lock signal];
    [finished_lock unlock];
    if (n == 3)
        [NSThread exit]; /* the thread ends here, its destructors still run */
}
@end

int main(void)
{
    signal(SIGALRM, on_alarm);
    alarm(30);
    @autoreleasepool {
        finished_lock = [[NSCondition alloc] init];
        reports = [NSMutableArray array];
        Job *job = [[Job alloc] init];
        calls = 42;
        label = @"main";
        NSMutableArray *threads = [NSMutableArray array];
        for (int i = 1; i <= 4; i++) {
            NSThread *t = [[NSThread alloc] initWithTarget:job selector:@selector(run:) object:@(i)];
            [threads addObject:t];
            [t start];
        }
        NSThread *b = [[NSThread alloc] initWithBlock:^{
            [job run:@5];
        }];
        [b start];
        [NSThread detachNewThreadSelector:@selector(run:) toTarget:job withObject:@6];
        [NSThread detachNewThreadWithBlock:^{
            [job run:@7];
        }];
        [job performSelectorInBackground:@selector(run:) withObject:@8];
        [finished_lock lock];
        while (finished < 8)
            [finished_lock wait];
        [finished_lock unlock];
        /* the reports came in any order */
        [reports sortUsingSelector:@selector(compare:)];
        for (NSString *r in reports)
            printf("%s\n", r.UTF8String);
        for (int i = 0; i < 500 && __atomic_load_n(&ended, __ATOMIC_ACQUIRE) < 8; i++)
            usleep(10000);
        printf("destructors run as the threads ended: %d\n", __atomic_load_n(&ended, __ATOMIC_ACQUIRE));
        printf("main thread kept its own: calls %d, label %s, depth %ld, scale %g\n", calls, label.UTF8String,
               (long)depth, scale);
    }
    return 0;
}
