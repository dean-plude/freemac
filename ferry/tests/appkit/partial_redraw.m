/* SPDX-License-Identifier: GPL-3.0-or-later
 * A window draws again only the part its views marked, as on a Mac: a
 * meter asking for its bar doesn't redraw the whole window (Audacity's
 * playhead and clock stood still while every view repainted, freemac 1.263).
 * Also lockFocus outside drawRect:, and sorting subviews. */
#import <Cocoa/Cocoa.h>

@interface Probe : NSView
@property int draws;
@property NSRect last;
@end
@implementation Probe
- (void)drawRect:(NSRect)r
{
    self.draws++;
    self.last = r;
}
@end

static NSComparisonResult by_tag(id a, id b, void *ctx)
{
    NSInteger x = [(NSView *)a frame].origin.x, y = [(NSView *)b frame].origin.x;
    return x < y ? NSOrderedDescending : x > y ? NSOrderedAscending : NSOrderedSame;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        Probe *root = [[Probe alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [w setContentView:root];
        Probe *left = [[Probe alloc] initWithFrame:NSMakeRect(10, 10, 50, 50)];
        Probe *right = [[Probe alloc] initWithFrame:NSMakeRect(200, 100, 80, 80)];
        [root addSubview:left];
        [root addSubview:right];
        [w display];
        printf("first drawing: root %d, left %d, right %d\n", root.draws, left.draws, right.draws);

        [right setNeedsDisplayInRect:NSMakeRect(10, 10, 20, 20)];
        [w displayIfNeeded];
        printf("right marked a corner: root %d, left %d, right %d\n", root.draws, left.draws, right.draws);
        NSRect r = right.last;
        printf("right asked to draw a small part: %s\n", r.size.width <= 24 && r.size.height <= 24 ? "yes" : "no");
        NSRect rr = root.last;
        printf("root drew only around it: %s\n",
               NSContainsRect(NSMakeRect(205, 105, 30, 30), rr) && rr.size.width < 40 ? "yes" : "no");

        [left setNeedsDisplay:YES];
        [right setNeedsDisplay:YES];
        [w displayIfNeeded];
        printf("both marked: left %d, right %d\n", left.draws, right.draws);

        [w displayIfNeeded];
        printf("then settled: left %d, right %d\n", left.draws, right.draws);

        [w setViewsNeedDisplay:YES];
        [w displayIfNeeded];
        printf("window marked: root %d, left %d, right %d\n", root.draws, left.draws, right.draws);

        /* lockFocus: drawing outside drawRect: lands in the window */
        BOOL can = [left lockFocusIfCanDraw];
        printf("lockFocusIfCanDraw: %s, focus view is left: %s\n", can ? "yes" : "no",
               [NSView focusView] == left ? "yes" : "no");
        if (can) {
            [[NSColor redColor] setFill];
            NSRectFill(NSMakeRect(0, 0, 10, 10));
            [left unlockFocus];
        }
        printf("after unlockFocus, focus view: %s\n", [NSView focusView] ? "some" : "none");

        /* sortSubviewsUsingFunction:context: */
        [root sortSubviewsUsingFunction:by_tag context:NULL];
        printf("sorted: first subview is %s\n", [[root subviews] firstObject] == right ? "right" : "left");
    }
    return 0;
}
