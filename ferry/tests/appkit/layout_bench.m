/* SPDX-License-Identifier: GPL-3.0-or-later
 * Auto Layout on a big window (freemac 1.237, Ferry 0.61.0), with no
 * display: a window the size of Itsycal's or VLC's, some three hundred views
 * and over a thousand rows for the solver on each axis. A toolbar and a
 * sidebar in stack views, a month grid of equal cells, a list of event rows
 * with labels that hug, resist compression and give way to one another,
 * inequalities and wishes at mixed priorities. Prints every frame after the
 * window first lays out, after it grows, and after a constant and an
 * intrinsic size change, so the solver's answers are checked; the time each
 * step took goes to stderr. */
#import <Cocoa/Cocoa.h>
#include <time.h>

@interface Label : NSView
@property NSSize natural;
@end
@implementation Label
- (NSSize)intrinsicContentSize { return self.natural; }
@end

static NSMutableArray *all_views;

static double now_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static id named(id v, NSString *name)
{
    [v setIdentifier:name];
    [all_views addObject:v];
    return v;
}

static NSView *plain(NSView *parent, NSString *name)
{
    NSView *v = named([[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)], name);
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:v];
    return v;
}

static Label *label(NSView *parent, NSString *name, CGFloat w, CGFloat h)
{
    Label *l = named([[Label alloc] initWithFrame:NSZeroRect], name);
    l.natural = NSMakeSize(w, h);
    l.translatesAutoresizingMaskIntoConstraints = NO;
    if (parent)
        [parent addSubview:l];
    return l;
}

static NSLayoutConstraint *at(NSLayoutConstraint *c, NSLayoutPriority p)
{
    c.priority = p;
    return c;
}

static void show_all(const char *step)
{
    printf("-- %s\n", step);
    for (NSView *v in all_views) {
        NSRect f = v.frame;
        printf("%s: %.1f,%.1f %.1fx%.1f\n", [v.identifier UTF8String], f.origin.x, f.origin.y, f.size.width,
               f.size.height);
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        all_views = [NSMutableArray array];
        NSMutableArray *cs = [NSMutableArray array];

        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 640, 480)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:NO];
        NSView *content = w.contentView;

        /* a toolbar: a row of buttons in a stack view */
        NSStackView *toolbar = named([[NSStackView alloc] initWithFrame:NSZeroRect], @"toolbar");
        toolbar.translatesAutoresizingMaskIntoConstraints = NO;
        toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        toolbar.spacing = 6;
        [content addSubview:toolbar];
        for (int i = 0; i < 6; i++)
            [toolbar addArrangedSubview:label(nil, [NSString stringWithFormat:@"tool%d", i], 24 + 4 * i, 22)];
        [cs addObjectsFromArray:@[
            [toolbar.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
            [toolbar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
            [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-8],
        ]];
        Label *search = label(content, @"search", 120, 22);
        [search setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cs addObjectsFromArray:@[
            [search.leadingAnchor constraintGreaterThanOrEqualToAnchor:toolbar.trailingAnchor constant:12],
            [search.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
            [search.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
            at([search.widthAnchor constraintEqualToConstant:220], 400),
        ]];

        /* a sidebar: rows of a name and a count in a stack view */
        NSView *sidebar = plain(content, @"sidebar");
        [cs addObjectsFromArray:@[
            [sidebar.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],
            [sidebar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [sidebar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
            [sidebar.widthAnchor constraintGreaterThanOrEqualToConstant:150],
            at([sidebar.widthAnchor constraintLessThanOrEqualToConstant:260], 900),
            at([sidebar.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.3], 250),
        ]];
        NSLayoutConstraint *sidebarWish = cs.lastObject;
        NSStackView *sources = named([[NSStackView alloc] initWithFrame:NSZeroRect], @"sources");
        sources.translatesAutoresizingMaskIntoConstraints = NO;
        sources.orientation = NSUserInterfaceLayoutOrientationVertical;
        sources.alignment = NSLayoutAttributeLeading;
        sources.spacing = 2;
        [sidebar addSubview:sources];
        [cs addObjectsFromArray:@[
            [sources.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:4],
            [sources.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:6],
            [sources.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-6],
        ]];
        for (int i = 0; i < 12; i++) {
            NSView *row = named([[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 20)],
                                [NSString stringWithFormat:@"source%d", i]);
            row.translatesAutoresizingMaskIntoConstraints = NO;
            Label *name = label(row, [NSString stringWithFormat:@"source%d.name", i], 60 + 7 * (i % 5), 17);
            Label *count = label(row, [NSString stringWithFormat:@"source%d.count", i], 18 + 4 * (i % 3), 17);
            [count setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [name setContentCompressionResistancePriority:500 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [cs addObjectsFromArray:@[
                [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:4],
                [name.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [count.leadingAnchor constraintGreaterThanOrEqualToAnchor:name.trailingAnchor constant:6],
                [count.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-4],
                [count.firstBaselineAnchor constraintEqualToAnchor:name.firstBaselineAnchor],
                [row.heightAnchor constraintEqualToConstant:20],
                [row.widthAnchor constraintGreaterThanOrEqualToConstant:120],
            ]];
            [sources addArrangedSubview:row];
        }

        /* the month: a title between two arrows, the weekdays and a grid of 6 x 7 days */
        NSView *month = plain(content, @"month");
        [cs addObjectsFromArray:@[
            [month.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],
            [month.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:8],
            [month.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        ]];
        Label *prev = label(month, @"month.prev", 16, 16), *next = label(month, @"month.next", 16, 16);
        Label *title = label(month, @"month.title", 110, 20);
        [title setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cs addObjectsFromArray:@[
            [prev.leadingAnchor constraintEqualToAnchor:month.leadingAnchor],
            [prev.topAnchor constraintEqualToAnchor:month.topAnchor constant:2],
            [next.trailingAnchor constraintEqualToAnchor:month.trailingAnchor],
            [next.centerYAnchor constraintEqualToAnchor:prev.centerYAnchor],
            [title.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:4],
            [title.trailingAnchor constraintEqualToAnchor:next.leadingAnchor constant:-4],
            [title.centerYAnchor constraintEqualToAnchor:prev.centerYAnchor],
        ]];
        NSView *firstCell = nil, *above[7] = {nil};
        NSView *lastRowCell = nil;
        for (int d = 0; d < 7; d++) {
            Label *day = label(month, [NSString stringWithFormat:@"weekday%d", d], 14 + (d % 2), 14);
            [cs addObject:[day.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6]];
            above[d] = day;
        }
        for (int r = 0; r < 6; r++) {
            NSView *left = nil;
            for (int d = 0; d < 7; d++) {
                NSView *cell = plain(month, [NSString stringWithFormat:@"cell%d.%d", r, d]);
                Label *num = label(cell, [NSString stringWithFormat:@"cell%d.%d.day", r, d], 12 + 4 * ((r * 7 + d) > 9),
                                   14);
                NSView *dot = plain(cell, [NSString stringWithFormat:@"cell%d.%d.dot", r, d]);
                [cs addObjectsFromArray:@[
                    [num.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
                    [num.topAnchor constraintGreaterThanOrEqualToAnchor:cell.topAnchor constant:2],
                    at([num.topAnchor constraintEqualToAnchor:cell.topAnchor constant:4], 600),
                    [num.leadingAnchor constraintGreaterThanOrEqualToAnchor:cell.leadingAnchor],
                    [dot.widthAnchor constraintEqualToConstant:4],
                    [dot.heightAnchor constraintEqualToAnchor:dot.widthAnchor],
                    [dot.centerXAnchor constraintEqualToAnchor:num.centerXAnchor],
                    [dot.topAnchor constraintGreaterThanOrEqualToAnchor:num.bottomAnchor constant:1],
                    [dot.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-2],
                    [cell.topAnchor constraintEqualToAnchor:above[d].bottomAnchor constant:r ? 2 : 4],
                ]];
                if (r == 0)
                    [cs addObject:[above[d].centerXAnchor constraintEqualToAnchor:cell.centerXAnchor]];
                if (firstCell) {
                    [cs addObject:[cell.widthAnchor constraintEqualToAnchor:firstCell.widthAnchor]];
                    [cs addObject:[cell.heightAnchor constraintEqualToAnchor:firstCell.heightAnchor]];
                } else {
                    firstCell = cell;
                    [cs addObjectsFromArray:@[
                        [cell.heightAnchor constraintGreaterThanOrEqualToConstant:24],
                        at([cell.heightAnchor constraintEqualToAnchor:cell.widthAnchor multiplier:0.8], 500),
                    ]];
                }
                if (left)
                    [cs addObject:[cell.leadingAnchor constraintEqualToAnchor:left.trailingAnchor constant:2]];
                else
                    [cs addObject:[cell.leadingAnchor constraintEqualToAnchor:month.leadingAnchor]];
                left = cell;
                above[d] = cell;
                lastRowCell = cell;
            }
            [cs addObject:[left.trailingAnchor constraintEqualToAnchor:month.trailingAnchor]];
        }
        [cs addObject:[month.bottomAnchor constraintEqualToAnchor:lastRowCell.bottomAnchor constant:4]];

        /* the events below the month: rows of a colour, a title over a place, a time */
        NSView *events = plain(content, @"events");
        [cs addObjectsFromArray:@[
            [events.topAnchor constraintEqualToAnchor:month.bottomAnchor constant:6],
            [events.leadingAnchor constraintEqualToAnchor:month.leadingAnchor],
            [events.trailingAnchor constraintEqualToAnchor:month.trailingAnchor],
            [events.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-24],
        ]];
        NSView *prevRow = nil;
        for (int i = 0; i < 12; i++) {
            NSView *row = plain(events, [NSString stringWithFormat:@"event%d", i]);
            NSView *bar = plain(row, [NSString stringWithFormat:@"event%d.bar", i]);
            Label *what = label(row, [NSString stringWithFormat:@"event%d.title", i], 80 + 13 * (i % 7), 16);
            Label *where = label(row, [NSString stringWithFormat:@"event%d.place", i], 50 + 17 * (i % 5), 13);
            Label *when = label(row, [NSString stringWithFormat:@"event%d.time", i], 44, 13);
            [when setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [when setContentCompressionResistancePriority:760 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [what setContentCompressionResistancePriority:740 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [where setContentCompressionResistancePriority:300 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [cs addObjectsFromArray:@[
                [row.leadingAnchor constraintEqualToAnchor:events.leadingAnchor],
                [row.trailingAnchor constraintEqualToAnchor:events.trailingAnchor],
                prevRow ? [row.topAnchor constraintEqualToAnchor:prevRow.bottomAnchor constant:2]
                        : [row.topAnchor constraintEqualToAnchor:events.topAnchor],
                [bar.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:2],
                [bar.widthAnchor constraintEqualToConstant:3],
                [bar.topAnchor constraintEqualToAnchor:row.topAnchor constant:2],
                [bar.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-2],
                [what.leadingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:6],
                [what.topAnchor constraintEqualToAnchor:row.topAnchor constant:3],
                [what.trailingAnchor constraintLessThanOrEqualToAnchor:when.leadingAnchor constant:-8],
                [where.leadingAnchor constraintEqualToAnchor:what.leadingAnchor],
                [where.topAnchor constraintEqualToAnchor:what.bottomAnchor constant:1],
                [where.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-4],
                [when.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-4],
                [when.firstBaselineAnchor constraintEqualToAnchor:what.firstBaselineAnchor],
                [row.bottomAnchor constraintGreaterThanOrEqualToAnchor:where.bottomAnchor constant:3],
                at([row.heightAnchor constraintEqualToConstant:30], 600),
            ]];
            if (i % 3 == 0)
                [cs addObject:at([where.widthAnchor constraintLessThanOrEqualToAnchor:what.widthAnchor], 450)];
            prevRow = row;
        }
        [cs addObject:at([events.bottomAnchor constraintEqualToAnchor:prevRow.bottomAnchor], 700)];

        /* a status line along the bottom, no wider than half the window */
        Label *status = label(content, @"status", 400, 14);
        [status setContentCompressionResistancePriority:650 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cs addObjectsFromArray:@[
            [status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
            [status.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-5],
            at([status.widthAnchor constraintLessThanOrEqualToAnchor:content.widthAnchor multiplier:0.5], 700),
        ]];
        [NSLayoutConstraint activateConstraints:cs];
        fprintf(stderr, "layout_bench: %lu views, %lu constraints\n", (unsigned long)all_views.count,
                (unsigned long)cs.count);

        double t0 = now_ms(), t = t0;
        [w displayIfNeeded];
        fprintf(stderr, "layout_bench: first layout %.1f ms\n", now_ms() - t);
        show_all("first layout");

        t = now_ms();
        [w setContentSize:NSMakeSize(900, 1200)];
        [w layoutIfNeeded];
        fprintf(stderr, "layout_bench: grown %.1f ms\n", now_ms() - t);
        show_all("grown");

        t = now_ms();
        sidebarWish.active = NO;
        Label *longTitle = nil;
        for (NSView *v in all_views)
            if ([v.identifier isEqualToString:@"event4.title"])
                longTitle = (Label *)v;
        longTitle.natural = NSMakeSize(900, 16);
        [longTitle invalidateIntrinsicContentSize];
        [w layoutIfNeeded];
        fprintf(stderr, "layout_bench: changed %.1f ms\n", now_ms() - t);
        show_all("changed");

        t = now_ms();
        [w setContentSize:NSMakeSize(520, 700)];
        [w layoutIfNeeded];
        fprintf(stderr, "layout_bench: shrunk %.1f ms\n", now_ms() - t);
        show_all("shrunk");
        printf("window content %.0fx%.0f\n", w.contentView.frame.size.width, w.contentView.frame.size.height);
        fprintf(stderr, "layout_bench: total %.1f ms\n", now_ms() - t0);
    }
    return 0;
}
