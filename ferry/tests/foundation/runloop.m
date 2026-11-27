/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: NSRunLoop, NSTimer, delayed performs, notifications,
 * descriptor sources, and CoreFoundation calls on Foundation objects. */
#import <Foundation/Foundation.h>
#include <unistd.h>

void FerryRunLoopAddDescriptor(int fd, void (*callback)(int, void *), void *ctx);
void FerryRunLoopRemoveDescriptor(int fd);

@interface Ticker : NSObject {
@public
    int ticks;
}
@end

@implementation Ticker
- (void)tick:(NSTimer *)timer
{
    ticks++;
    printf("tick %d (%s)\n", ticks, [[timer userInfo] UTF8String]);
    if (ticks == 3)
        [timer invalidate];
}
- (void)later:(id)arg { printf("performed later with %s\n", [arg UTF8String]); }
- (void)noticed:(NSNotification *)note
{
    printf("observer got %s from %s, info %s\n", [[note name] UTF8String], [[[note object] description] UTF8String],
           [[[note userInfo] objectForKey:@"k"] UTF8String]);
}
@end

static int watched_gone;
@interface Watched : NSObject
@end
@implementation Watched
- (void)dealloc
{
    watched_gone = 1;
    [super dealloc];
}
@end

static void readable(int fd, void *ctx)
{
    char buf[32];
    ssize_t n = read(fd, buf, sizeof buf - 1);
    buf[n > 0 ? n : 0] = 0;
    printf("descriptor %s said \"%s\"\n", (const char *)ctx, buf);
    FerryRunLoopRemoveDescriptor(fd);
}

int main(void)
{
    @autoreleasepool {
        NSRunLoop *loop = [NSRunLoop currentRunLoop];
        printf("same loop %d\n", loop == [NSRunLoop mainRunLoop]);
        printf("empty loop returns at once: %d\n", [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);

        Ticker *t = [[[Ticker alloc] init] autorelease];
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.01 target:t selector:@selector(tick:)
                                                        userInfo:@"info" repeats:YES];
        printf("timer valid %d interval %.2f\n", [timer isValid], [timer timeInterval]);
        __block int order = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *tm) {
          printf("block timer fired, step %d\n", ++order);
        }];
        [t performSelector:@selector(later:) withObject:@"an argument" afterDelay:0.025];
        /* cancelled before they come due: never performed */
        [t performSelector:@selector(later:) withObject:@"a cancelled argument" afterDelay:0.02];
        [t performSelector:@selector(later:) withObject:@"another cancelled one" afterDelay:0.02];
        [NSObject cancelPreviousPerformRequestsWithTarget:t selector:@selector(later:)
                                                   object:@"a cancelled argument"];
        [t performSelector:@selector(later:) withObject:@"kept" afterDelay:0.1];
        [NSObject cancelPreviousPerformRequestsWithTarget:t selector:@selector(later:)
                                                   object:@"another cancelled one"];
        [loop performBlock:^{
          printf("queued block ran first, step %d\n", ++order);
        }];
        NSDate *start = [NSDate date];
        [loop run]; /* returns once no timers or sources remain */
        NSTimeInterval took = -[start timeIntervalSinceNow];
        printf("run returned after the work; ticks %d, took between 0.4 and 3 seconds: %d\n", t->ticks,
               took > 0.4 && took < 3);
        printf("timer valid after invalidate %d\n", [timer isValid]);

        /* a file descriptor as an input source */
        int fds[2];
        pipe(fds);
        FerryRunLoopAddDescriptor(fds[0], readable, "pipe");
        write(fds[1], "ping", 4);
        [loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        close(fds[0]);
        close(fds[1]);

        /* CFRunLoop on the same loop */
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
          printf("CFRunLoopPerformBlock ran\n");
        });
        printf("CFRunLoopRunInMode handled %d\n", CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, true) ==
                                                       kCFRunLoopRunHandledSource);
        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *tm) {
          printf("stopping the loop\n");
          CFRunLoopStop(CFRunLoopGetCurrent());
        }];
        [NSTimer scheduledTimerWithTimeInterval:30 repeats:NO block:^(NSTimer *tm) {
          printf("never fires\n");
        }];
        CFRunLoopRun();
        printf("CFRunLoopRun returned after stop\n");

        /* notifications */
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:t selector:@selector(noticed:) name:@"Changed" object:nil];
        id token = [nc addObserverForName:@"Changed" object:@"sender" queue:nil usingBlock:^(NSNotification *note) {
          printf("block observer got %s\n", [[note name] UTF8String]);
        }];
        [nc postNotificationName:@"Changed" object:@"sender" userInfo:@{@"k": @"v"}];
        [nc postNotificationName:@"Changed" object:@"other"];
        [nc postNotificationName:@"Unrelated" object:nil];
        [nc removeObserver:token];
        [nc removeObserver:t];
        [nc postNotificationName:@"Changed" object:@"sender"];
        printf("after removal: nothing above\n");
        /* a posted notification doesn't keep its object in the pool (1.259) */
        Watched *w = [[Watched alloc] init];
        [nc postNotificationName:@"Changed" object:w];
        [w release];
        printf("object let go right after posting %d\n", watched_gone);
        NSNotification *made_note = [[NSNotification alloc] initWithName:@"Made" object:nil userInfo:@{@"k": @"v"}];
        printf("initWithName %s %s\n", [[made_note name] UTF8String], [made_note.userInfo[@"k"] UTF8String]);
        [made_note release];

        /* toll-free bridging: CF calls on Foundation objects and back */
        CFStringRef cs = (CFStringRef)@"bridged";
        printf("CFStringGetLength %ld, prefix %d\n", (long)CFStringGetLength(cs), CFStringHasPrefix(cs, CFSTR("bri")));
        CFMutableDictionaryRef cd = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                              &kCFTypeDictionaryValueCallBacks);
        int v = 99;
        CFNumberRef num = CFNumberCreate(NULL, kCFNumberIntType, &v);
        CFDictionarySetValue(cd, CFSTR("answer"), num);
        CFRelease(num);
        NSDictionary *nd = (NSDictionary *)cd;
        printf("NSDictionary sees %s, count %lu\n", [[nd[@"answer"] description] UTF8String], (unsigned long)[nd count]);
        CFRelease(cd);
        char buf[32];
        CFStringGetCString((CFStringRef)[NSString stringWithFormat:@"n=%d", 5], buf, sizeof buf, kCFStringEncodingUTF8);
        printf("CFStringGetCString %s\n", buf);
        NSNumber *yes = @YES;
        printf("kCFBooleanTrue is @YES %d, value %d\n", (id)kCFBooleanTrue == yes, CFBooleanGetValue(kCFBooleanTrue));
        CFStringRef made = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@-%d"), @"cf", 7);
        printf("CFStringCreateWithFormat %s, equal %d\n", [(NSString *)made UTF8String],
               CFEqual(made, (CFStringRef)@"cf-7"));
        CFRelease(made);
        printf("absolute time positive %d\n", CFAbsoluteTimeGetCurrent() > 0);
    }
    return 0;
}
