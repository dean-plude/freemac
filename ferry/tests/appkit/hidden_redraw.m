/* SPDX-License-Identifier: GPL-3.0-or-later
 * A view marked for drawing inside a hidden view isn't drawn, so the mark
 * must not keep the window drawing itself again and again (the Installer
 * redrew without end once its licence box was ticked and then hidden). */
#import <Cocoa/Cocoa.h>

@interface Probe : NSView
@property int draws;
@end
@implementation Probe
- (void)drawRect:(NSRect)r { self.draws++; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        Probe *shown = [[Probe alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(60, 0, 100, 100)];
        Probe *inside = [[Probe alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        [box addSubview:inside];
        [[w contentView] addSubview:shown];
        [[w contentView] addSubview:box];
        [w display];
        printf("first drawing: shown %d, inside %d\n", shown.draws, inside.draws);
        [box setHidden:YES];
        [w displayIfNeeded];
        [inside setNeedsDisplay:YES];
        int before = shown.draws;
        for (int i = 0; i < 5; i++)
            [w displayIfNeeded];
        printf("hidden and marked, five more turns: window drew %d more times, inside %d\n", shown.draws - before,
               inside.draws - 1);
        [box setHidden:NO];
        before = inside.draws;
        [w displayIfNeeded];
        printf("shown again: inside drew %d more time\n", inside.draws - before);
        before = shown.draws;
        [w displayIfNeeded];
        printf("then settled: window drew %d more times\n", shown.draws - before);
    }
    return 0;
}
