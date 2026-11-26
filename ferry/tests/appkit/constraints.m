/* SPDX-License-Identifier: GPL-3.0-or-later
 * Auto Layout (freemac 1.222, Ferry 0.46.0), with no display: pinning to
 * the superview by anchors and by the visual format, standard spacing,
 * centring, fixed sizes, multipliers, inequalities and priorities, intrinsic
 * sizes with hugging and compression resistance, a flipped superview,
 * resizing and changing a constant, fitting sizes, a window's content layout
 * guide, autoresizing views inside a constrained one, deactivating and
 * removing views, layout guides, conflicting required constraints, and the
 * visual format's errors, as Flycut's bezel and MacPass's inspector use them. */
#import <Cocoa/Cocoa.h>

@interface Label : NSView
@property NSSize natural;
@end
@implementation Label
- (NSSize)intrinsicContentSize { return self.natural; }
@end

@interface Flipped : NSView
@end
@implementation Flipped
- (BOOL)isFlipped { return YES; }
@end

@interface Counting : NSView
@property int updates;
@end
@implementation Counting
- (void)updateConstraints
{
    self.updates++;
    [super updateConstraints];
}
@end

static void show(const char *what, NSView *v)
{
    NSRect f = v.frame;
    printf("%s: %.1f,%.1f %.1fx%.1f\n", what, f.origin.x, f.origin.y, f.size.width, f.size.height);
}

static NSView *box(NSRect r)
{
    NSView *v = [[NSView alloc] initWithFrame:r];
    return v;
}

static NSView *child(NSView *parent)
{
    NSView *v = box(NSMakeRect(1, 2, 3, 4));
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:v];
    return v;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* pinned on every side by anchors, as Flycut's rounded text field pins its background */
        NSView *root = box(NSMakeRect(0, 0, 400, 300));
        NSView *a = child(root);
        printf("translates by default: %d, after: %d\n", (int)[box(NSZeroRect) translatesAutoresizingMaskIntoConstraints],
               (int)a.translatesAutoresizingMaskIntoConstraints);
        [NSLayoutConstraint activateConstraints:@[
            [a.topAnchor constraintEqualToAnchor:root.topAnchor constant:10],
            [a.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],
            [a.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:30],
            [a.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-40],
        ]];
        printf("installed on the superview: %lu, active %d\n", (unsigned long)root.constraints.count,
               (int)[root.constraints[0] isActive]);
        [root layoutSubtreeIfNeeded];
        show("pinned", a);

        /* the superview grows: the view follows */
        [root setFrameSize:NSMakeSize(500, 400)];
        [root layoutSubtreeIfNeeded];
        show("after the superview grew", a);

        /* centred with a fixed size, as Flycut's bezel centres its counter */
        NSView *b = child(root);
        [NSLayoutConstraint activateConstraints:@[
            [b.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
            [b.centerYAnchor constraintEqualToAnchor:root.centerYAnchor constant:10],
            [b.widthAnchor constraintEqualToConstant:100],
            [b.heightAnchor constraintEqualToConstant:30],
        ]];
        [root layoutSubtreeIfNeeded];
        show("centred", b);

        /* the visual format, as MacPass lays out its inspector */
        NSView *root2 = box(NSMakeRect(0, 0, 300, 200));
        NSView *left = child(root2), *right = child(root2), *below = child(root2);
        NSDictionary *views = NSDictionaryOfVariableBindings(left, right, below);
        NSArray *h = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[left(==80)]-[right]-|" options:0
                                                             metrics:nil views:views];
        NSArray *v = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-pad-[left(40)]-(>=10)-[below(==20@750)]|"
                                                             options:0 metrics:@{@"pad" : @12} views:views];
        NSArray *h2 = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[below]|" options:0 metrics:nil views:views];
        NSArray *align = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[left]-0-[right]" options:0 metrics:nil views:views];
        printf("format constraints: %lu %lu %lu %lu\n", (unsigned long)h.count, (unsigned long)v.count,
               (unsigned long)h2.count, (unsigned long)align.count);
        [root2 addConstraints:h];
        [root2 addConstraints:v];
        [root2 addConstraints:h2];
        [root2 addConstraint:[NSLayoutConstraint constraintWithItem:right attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual toItem:left
                                                          attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        [root2 addConstraint:[NSLayoutConstraint constraintWithItem:right attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual toItem:left
                                                          attribute:NSLayoutAttributeHeight multiplier:0.5 constant:0]];
        [root2 layoutSubtreeIfNeeded];
        show("left", left);
        show("right", right);
        show("below", below);

        /* priorities: a wish that breaks a required limit gives way */
        NSView *root3 = box(NSMakeRect(0, 0, 400, 100));
        NSView *c = child(root3);
        NSLayoutConstraint *wish = [c.widthAnchor constraintEqualToConstant:300];
        wish.priority = NSLayoutPriorityDefaultLow;
        NSLayoutConstraint *strong = [c.widthAnchor constraintGreaterThanOrEqualToConstant:250];
        strong.priority = NSLayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            wish, strong, [c.widthAnchor constraintLessThanOrEqualToConstant:200],
            [c.leftAnchor constraintEqualToAnchor:root3.leftAnchor], [c.topAnchor constraintEqualToAnchor:root3.topAnchor],
            [c.heightAnchor constraintEqualToAnchor:root3.heightAnchor multiplier:0.5],
        ]];
        [root3 layoutSubtreeIfNeeded];
        show("limited", c);
        wish.constant = 150;
        [root3 layoutSubtreeIfNeeded];
        show("a smaller wish, outweighed", c);
        strong.active = NO;
        [root3 layoutSubtreeIfNeeded];
        show("without the strong one", c);
        /* a constant size is installed on the view itself, the rest on the superview */
        printf("deactivated: %d, on the view %lu, on the superview %lu\n", (int)strong.active,
               (unsigned long)c.constraints.count, (unsigned long)root3.constraints.count);

        /* intrinsic sizes: hugging gives way to pinning, compression resistance to a required width */
        NSView *root4 = box(NSMakeRect(0, 0, 300, 100));
        Label *l1 = [[Label alloc] initWithFrame:NSZeroRect], *l2 = [[Label alloc] initWithFrame:NSZeroRect];
        l1.natural = NSMakeSize(120, 22);
        l2.natural = NSMakeSize(90, 17);
        for (Label *l in @[ l1, l2 ]) {
            l.translatesAutoresizingMaskIntoConstraints = NO;
            [root4 addSubview:l];
        }
        [root4 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[l1]" options:0 metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(l1)]];
        [root4 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[l2]-10-|"
                                                                      options:0 metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(l2)]];
        [root4 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-5-[l1]-[l2]"
                                                                      options:NSLayoutFormatAlignAllLeading
                                                                      metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(l1, l2)]];
        [root4 layoutSubtreeIfNeeded];
        show("label at its own size", l1);
        show("label stretched", l2);
        NSLayoutConstraint *narrow = [l1.widthAnchor constraintEqualToConstant:60];
        narrow.active = YES;
        [root4 layoutSubtreeIfNeeded];
        show("label squeezed by a required width", l1);
        narrow.active = NO;
        l1.natural = NSMakeSize(140, 22);
        [l1 invalidateIntrinsicContentSize];
        [root4 layoutSubtreeIfNeeded];
        show("label after its size changed", l1);

        /* a flipped superview measures from the top */
        Flipped *root5 = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        NSView *d = child(root5);
        [root5 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-15-[d(==50)]" options:0 metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(d)]];
        [root5 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[d(==40)]-25-|" options:0 metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(d)]];
        [root5 layoutSubtreeIfNeeded];
        show("in a flipped view", d);

        /* nested: a view inside a constrained view, and an autoresizing view inside that */
        NSView *inner = child(d);
        [NSLayoutConstraint activateConstraints:@[
            [inner.leadingAnchor constraintEqualToAnchor:d.leadingAnchor constant:5],
            [inner.trailingAnchor constraintEqualToAnchor:d.trailingAnchor constant:-5],
            [inner.topAnchor constraintEqualToAnchor:d.topAnchor constant:5],
            [inner.heightAnchor constraintEqualToConstant:10],
        ]];
        [root5 layoutSubtreeIfNeeded];
        show("inner", inner);
        NSView *springs = box(NSMakeRect(0, 0, 30, 10));
        springs.autoresizingMask = NSViewWidthSizable;
        [inner addSubview:springs];
        [root5 removeConstraints:root5.constraints];
        [root5 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[d]|" options:0 metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(d)]];
        [root5 addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[d]|" options:0 metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(d)]];
        [root5 layoutSubtreeIfNeeded];
        show("filling", d);
        show("inner after", inner);
        show("autoresizing view inside", springs);

        /* the smallest size a view's own constraints allow */
        NSView *card = box(NSMakeRect(0, 0, 500, 500));
        Label *t = [[Label alloc] initWithFrame:NSZeroRect];
        t.natural = NSMakeSize(64, 18);
        t.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:t];
        [card addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-12-[t]-12-|" options:0 metrics:nil
                                                                       views:NSDictionaryOfVariableBindings(t)]];
        [card addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-8-[t]-8-|" options:0 metrics:nil
                                                                       views:NSDictionaryOfVariableBindings(t)]];
        NSSize fit = card.fittingSize;
        printf("fitting size %.1fx%.1f, frame kept %.0fx%.0f\n", fit.width, fit.height, card.frame.size.width,
               card.frame.size.height);

        /* a window: its content layout guide, and layout when it displays */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 320, 240)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:NO];
        NSView *top = child(w.contentView);
        NSLayoutGuide *guide = w.contentLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [top.topAnchor constraintEqualToAnchor:[guide topAnchor]],
            [top.leadingAnchor constraintEqualToAnchor:[guide leadingAnchor]],
            [top.widthAnchor constraintEqualToAnchor:[guide widthAnchor] multiplier:0.25],
            [top.heightAnchor constraintEqualToConstant:24],
        ]];
        [w displayIfNeeded];
        show("under the window's top", top);
        printf("guide: %s, owned by the content view %d\n", [NSStringFromRect(guide.frame) UTF8String],
               (int)(guide.owningView == w.contentView));
        [w setContentSize:NSMakeSize(400, 300)];
        [w layoutIfNeeded];
        show("after the window grew", top);

        /* a guide of the app's own between two views */
        NSView *root6 = box(NSMakeRect(0, 0, 300, 50));
        NSView *p = child(root6), *q = child(root6);
        NSLayoutGuide *gap = [[NSLayoutGuide alloc] init];
        [root6 addLayoutGuide:gap];
        [NSLayoutConstraint activateConstraints:@[
            [p.leadingAnchor constraintEqualToAnchor:root6.leadingAnchor], [p.widthAnchor constraintEqualToConstant:50],
            [gap.leadingAnchor constraintEqualToAnchor:p.trailingAnchor], [gap.widthAnchor constraintEqualToConstant:70],
            [q.leadingAnchor constraintEqualToAnchor:gap.trailingAnchor],
            [q.trailingAnchor constraintEqualToAnchor:root6.trailingAnchor],
            [p.topAnchor constraintEqualToAnchor:root6.topAnchor], [q.topAnchor constraintEqualToAnchor:p.topAnchor],
            [p.heightAnchor constraintEqualToConstant:10], [q.heightAnchor constraintEqualToAnchor:p.heightAnchor],
            [gap.topAnchor constraintEqualToAnchor:root6.topAnchor], [gap.heightAnchor constraintEqualToConstant:1],
        ]];
        [root6 layoutSubtreeIfNeeded];
        show("before the guide", p);
        show("after the guide", q);
        printf("guide frame %s, guides %lu\n", [NSStringFromRect(gap.frame) UTF8String],
               (unsigned long)root6.layoutGuides.count);

        /* taking a view out takes its constraints with it */
        NSUInteger before = root6.constraints.count;
        [q removeFromSuperview];
        printf("constraints before %lu, after removing a view %lu\n", (unsigned long)before,
               (unsigned long)root6.constraints.count);

        /* required constraints that can't all hold: the later one is left out */
        NSView *root7 = box(NSMakeRect(0, 0, 100, 100));
        NSView *e = child(root7);
        [NSLayoutConstraint activateConstraints:@[
            [e.widthAnchor constraintEqualToConstant:40], [e.widthAnchor constraintEqualToConstant:60],
            [e.leftAnchor constraintEqualToAnchor:root7.leftAnchor], [e.topAnchor constraintEqualToAnchor:root7.topAnchor],
            [e.heightAnchor constraintEqualToConstant:5],
        ]];
        [root7 layoutSubtreeIfNeeded];
        show("conflict", e);

        /* updating constraints before layout */
        Counting *cv = [[Counting alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [root7 addSubview:cv];
        cv.needsUpdateConstraints = YES;
        [root7 layoutSubtreeIfNeeded];
        printf("updateConstraints ran %d, needs it now %d\n", cv.updates, (int)cv.needsUpdateConstraints);

        /* what a constraint says about itself */
        NSLayoutConstraint *described = [NSLayoutConstraint constraintWithItem:e attribute:NSLayoutAttributeWidth
                                                                     relatedBy:NSLayoutRelationLessThanOrEqual
                                                                        toItem:root7 attribute:NSLayoutAttributeWidth
                                                                    multiplier:0.5 constant:-4];
        described.identifier = @"half";
        described.priority = 600;
        e.identifier = @"e";
        root7.identifier = @"root";
        NSString *desc = described.description;
        NSRange r = [desc rangeOfString:@"'half'"];
        printf("%s\n", [[desc substringFromIndex:r.location] UTF8String]);
        printf("anchors: %s %s, first %s\n", [e.widthAnchor.name UTF8String],
               [NSStringFromClass([e.centerYAnchor class]) UTF8String],
               [NSStringFromClass([described.firstAnchor class]) UTF8String]);

        /* an aspect ratio: a width against a height, the height set by the
         * superview (an icon in a sidebar's row, as VLC's), and a height
         * against a width */
        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        NSView *icon = [[NSView alloc] init], *label = [[NSView alloc] init], *wide = [[NSView alloc] init];
        for (NSView *v in @[ icon, label, wide ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [row addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [NSLayoutConstraint constraintWithItem:icon attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
                                            toItem:icon attribute:NSLayoutAttributeHeight multiplier:14.0 / 15 constant:0],
            [icon.topAnchor constraintEqualToAnchor:row.topAnchor constant:2],
            [row.bottomAnchor constraintEqualToAnchor:icon.bottomAnchor constant:2],
            [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:3],
            [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:7],
            [label.topAnchor constraintEqualToAnchor:row.topAnchor], [label.heightAnchor constraintEqualToConstant:16],
            [label.widthAnchor constraintEqualToConstant:50],
            [wide.widthAnchor constraintEqualToConstant:32], [wide.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [wide.topAnchor constraintEqualToAnchor:row.topAnchor],
            [wide.heightAnchor constraintEqualToAnchor:wide.widthAnchor multiplier:0.5 constant:1],
        ]];
        [row layoutSubtreeIfNeeded];
        printf("aspect: icon %s, label at %g, wide %s\n", [NSStringFromRect(icon.frame) UTF8String], label.frame.origin.x,
               [NSStringFromSize(wide.frame.size) UTF8String]);
        @try {
            [NSLayoutConstraint constraintWithItem:icon attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
                                            toItem:row attribute:NSLayoutAttributeTop multiplier:1 constant:0];
            printf("width against top: made\n");
        } @catch (NSException *x) {
            printf("width against top: %s\n", [x.name UTF8String]);
        }

        /* the visual format's mistakes */
        for (NSString *bad in @[ @"H:|-[missing]-|", @"H:|-[left", @"V:[left]-(>=x)-[right]" ]) {
            @try {
                [NSLayoutConstraint constraintsWithVisualFormat:bad options:0 metrics:nil views:views];
                printf("%s: parsed\n", [bad UTF8String]);
            } @catch (NSException *x) {
                printf("%s: %s, %s\n", [bad UTF8String], [x.name UTF8String],
                       [x.reason hasPrefix:@"Unable to parse constraint format"] ? "unable to parse" : "?");
            }
        }
    }
    return 0;
}
