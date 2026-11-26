/* SPDX-License-Identifier: GPL-3.0-or-later
 * Auto Layout lines up alignment rects, not frames (freemac 1.250, Ferry
 * 0.73.0), with no display. A regular rounded push button is a 32-point
 * frame round a 22-point bezel, its alignment rect, so a nib's spacing to
 * and between buttons is to their bezels (VLC's Open dialog spaces its
 * Browse button this way); an app's own view with insets is placed by its
 * alignment rect too, its intrinsic size taken as the alignment rect's. */
#import <Cocoa/Cocoa.h>

@interface Flipped : NSView
@end
@implementation Flipped
- (BOOL)isFlipped { return YES; }
@end

@interface Inset : NSView
@end
@implementation Inset
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(2, 3, 4, 5); }
- (NSSize)intrinsicContentSize { return NSMakeSize(40, 20); }
@end

static void show(const char *what, NSView *v)
{
    NSRect f = v.frame, a = [v alignmentRectForFrame:f];
    printf("%s: frame %.0f,%.0f %.0fx%.0f; alignment %.0f,%.0f %.0fx%.0f\n", what, f.origin.x, f.origin.y,
           f.size.width, f.size.height, a.origin.x, a.origin.y, a.size.width, a.size.height);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Flipped *box = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        NSView *top = [[NSView alloc] init];
        NSButton *one = [NSButton buttonWithTitle:@"Browse…" target:nil action:nil];
        NSButton *two = [NSButton buttonWithTitle:@"OK" target:nil action:nil];
        Inset *mine = [[Inset alloc] init];
        for (NSView *v in @[ top, one, two, mine ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [box addSubview:v];
        }
        NSEdgeInsets e = [one alignmentRectInsets];
        printf("push button insets: top %.0f left %.0f bottom %.0f right %.0f\n", e.top, e.left, e.bottom, e.right);
        [NSLayoutConstraint activateConstraints:@[
            [top.topAnchor constraintEqualToAnchor:box.topAnchor constant:20],
            [top.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:20],
            [top.widthAnchor constraintEqualToConstant:100], [top.heightAnchor constraintEqualToConstant:17],
            [one.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
            [one.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:20],
            [two.topAnchor constraintEqualToAnchor:one.bottomAnchor constant:12],
            [two.leadingAnchor constraintEqualToAnchor:one.leadingAnchor],
            [two.widthAnchor constraintEqualToAnchor:one.widthAnchor],
            [mine.topAnchor constraintEqualToAnchor:two.bottomAnchor constant:10],
            [mine.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:20],
        ]];
        [box layoutSubtreeIfNeeded];
        show("label", top);
        show("first button", one);
        show("second button", two);
        show("own view", mine);
        printf("first button's bezel 8 below the label: %d; buttons' bezels 12 apart: %d\n",
               NSMinY(one.frame) + 5 == NSMaxY(top.frame) + 8, NSMinY(two.frame) + 5 == NSMaxY(one.frame) - 5 + 12);
        printf("frames as a nib has them: %d\n", one.frame.size.height == 32 && two.frame.size.height == 32);
    }
    return 0;
}
