/* SPDX-License-Identifier: GPL-3.0-or-later
 * An exception the app raises in its event loop (here from a timer) and
 * doesn't catch: as on a Mac, NSApplication reports it and carries on (M7). */
#import <Cocoa/Cocoa.h>

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        __block int fired = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *t) {
            fired++;
            printf("timer %d\n", fired);
            if (fired < 3)
                [NSException raise:NSInternalInconsistencyException format:@"timer %d went wrong", fired];
            [t invalidate];
            [NSApp stop:nil];
        }];
        [NSApp run];
        printf("run returned after %d timers\n", fired);
    }
    return 0;
}
