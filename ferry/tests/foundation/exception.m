/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: an exception nobody catches ends the program with the
 * message a Mac prints (Ferry can't unwind Mac stack frames yet, so @catch
 * isn't available). */
#import <Foundation/Foundation.h>

int main(void)
{
    @autoreleasepool {
        NSArray *a = @[@1, @2];
        printf("about to read past the end\n");
        fflush(stdout);
        id x = [a objectAtIndex:5];
        printf("not reached %p\n", (void *)x);
    }
    return 0;
}
