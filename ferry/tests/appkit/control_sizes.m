/* SPDX-License-Identifier: GPL-3.0-or-later
 * Small and mini controls are the size Interface Builder gives them (freemac
 * 1.NEXT): a push button 28 high when small and 16 when mini, a round rect
 * button 19, or 17 when small or mini, and a pop-up 25, 22 when small and 15
 * when mini, each as wide as its title and a margin. VLC's mini Reset buttons
 * had a regular button's 60 by 32 and slipped out of the panels they sit in. */
#import <Cocoa/Cocoa.h>

static const char *names[] = {"regular", "small", "mini"};

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (int size = 0; size < 3; size++) {
            NSButton *push = [NSButton buttonWithTitle:@"Cancel" target:nil action:NULL];
            [push setControlSize:(NSControlSize)size];
            NSSize title = [[push attributedTitle] size];
            NSSize ps = [push intrinsicContentSize];
            NSButton *rr = [NSButton buttonWithTitle:@"Reset" target:nil action:NULL];
            [rr setBezelStyle:NSBezelStyleRoundRect];
            [rr setControlSize:(NSControlSize)size];
            NSSize rt = [[rr attributedTitle] size], rs = [rr intrinsicContentSize];
            NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            [pop addItemsWithTitles:@[ @"Gradient", @"Wave" ]];
            [pop setControlSize:(NSControlSize)size];
            NSSize pops = [pop intrinsicContentSize];
            printf("%s: push %.0f high, round rect %.0f high, %s; pop-up %.0f high\n", names[size], ps.height, rs.height,
                   rs.width >= ceil(rt.width) + 10 && rs.width <= ceil(rt.width) + 20 ? "a title and a margin wide" : "wrong width",
                   pops.height);
            if (size > 0)
                printf("  push %s\n", ps.width >= ceil(title.width) + 15 && ps.width <= ceil(title.width) + 30
                                                ? "a title and a margin wide" : "wrong width");
        }
    }
    return 0;
}
