/* SPDX-License-Identifier: GPL-3.0-or-later
 * Of rules at one priority that the layout breaks, Auto Layout keeps the
 * one broken furthest first (freemac 1.251, Ferry 0.74.0), with no display.
 * A Mac's solver keeps the total error down, so of two minimum widths at
 * one priority, 50 and 100, a view comes out 100 wide, which keeps both,
 * whichever was made first; and with a maximum of 90 as well, which can't
 * hold with 100, it comes out from 90 to 100, 10 points short of one rule,
 * where holding the first one made (50) left it 50 short of another. */
#import <Cocoa/Cocoa.h>

@interface Flipped : NSView
@end
@implementation Flipped
- (BOOL)isFlipped { return YES; }
@end

static NSLayoutConstraint *at(NSLayoutConstraint *c, NSLayoutPriority p)
{
    c.priority = p;
    return c;
}

static double width_with(double first, double second, double most)
{
    Flipped *box = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    NSView *v = [[NSView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:box.topAnchor constant:10],
        [v.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:10],
        [v.heightAnchor constraintEqualToConstant:20],
        at([v.widthAnchor constraintEqualToConstant:0], 250),
        at([v.widthAnchor constraintGreaterThanOrEqualToConstant:first], 500),
        at([v.widthAnchor constraintGreaterThanOrEqualToConstant:second], 500),
        at([v.widthAnchor constraintLessThanOrEqualToConstant:most], 500),
    ]];
    [box layoutSubtreeIfNeeded];
    return v.frame.size.width;
}

static double height_in_row(void)
{
    /* sliders in a row, each at least its own height, all as tall as the
     * first: the tallest minimum decides (an equalizer's bands) */
    Flipped *box = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)];
    NSMutableArray *views = [NSMutableArray array], *rules = [NSMutableArray array];
    double mins[] = {40, 120, 80};
    for (int i = 0; i < 3; i++) {
        NSView *v = [[NSView alloc] init];
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:v];
        [rules addObjectsFromArray:@[
            [v.topAnchor constraintEqualToAnchor:box.topAnchor constant:10],
            [v.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:10 + 30 * i],
            [v.widthAnchor constraintEqualToConstant:20],
            at([v.heightAnchor constraintEqualToConstant:0], 250),
            at([v.heightAnchor constraintGreaterThanOrEqualToConstant:mins[i]], 500),
        ]];
        if (i)
            [rules addObject:[v.heightAnchor constraintEqualToAnchor:((NSView *)views[0]).heightAnchor]];
        [views addObject:v];
    }
    [NSLayoutConstraint activateConstraints:rules];
    [box layoutSubtreeIfNeeded];
    return ((NSView *)views[2]).frame.size.height;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("at least 50, then at least 100: %.0f wide\n", width_with(50, 100, 1000));
        printf("at least 100, then at least 50: %.0f wide\n", width_with(100, 50, 1000));
        /* the three can't all hold: the least broken is the width between
         * 90 and 100, 10 short of one of them; holding 50 first left it 50
         * short of 100 */
        double w = width_with(50, 100, 90);
        printf("at least 50, at least 100, at most 90: %.0f wide, from 90 to 100: %d\n", w, w >= 90 && w <= 100);
        printf("three sliders as tall as the first, at least 40, 120, 80: %.0f tall\n", height_in_row());
    }
    return 0;
}
