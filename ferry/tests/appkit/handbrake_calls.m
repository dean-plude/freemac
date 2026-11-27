/* SPDX-License-Identifier: GPL-3.0-or-later
 * What HandBrake 1.9's windows ask of AppKit and Foundation (freemac 1.264,
 * Ferry 0.87.0): a combo button, a toolbar item group of segments, a
 * toolbar item's possible labels and hiding, a window's subtitle and title
 * bar line, the symbols its toolbar draws, a published NSProgress, and the
 * Mac's regex_t layout from C. */
#import <Cocoa/Cocoa.h>
#include <regex.h>

@interface Target : NSObject
@property int clicks;
@end
@implementation Target
- (void)go:(id)sender { self.clicks++; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Target *t = [Target new];

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"When Done"];
        [menu addItemWithTitle:@"Do Nothing" action:NULL keyEquivalent:@""];
        [menu addItemWithTitle:@"Sleep" action:NULL keyEquivalent:@""];
        NSComboButton *b = [NSComboButton comboButtonWithTitle:@"Add To Queue" menu:menu target:t action:@selector(go:)];
        printf("combo button: %s, menu items %ld, style %ld\n", b.title.UTF8String, (long)b.menu.numberOfItems,
               (long)b.style);
        b.style = NSComboButtonStyleUnified;
        [b performClick:nil];
        printf("click sends the action: %s, size fits: %s\n", t.clicks == 1 ? "yes" : "no",
               b.intrinsicContentSize.width > 40 ? "yes" : "no");

        NSToolbarItemGroup *g = [NSToolbarItemGroup groupWithItemIdentifier:@"view"
                                                                     titles:@[ @"Encodes", @"Log" ]
                                                              selectionMode:NSToolbarItemGroupSelectionModeSelectOne
                                                                     labels:@[ @"Encodes", @"Log" ]
                                                                     target:t
                                                                     action:@selector(go:)];
        printf("group: %ld subitems, a segmented control: %s\n", (long)g.subitems.count,
               [g.view isKindOfClass:[NSSegmentedControl class]] ? "yes" : "no");
        g.selectedIndex = 1;
        printf("selected: %ld, second selected: %s\n", (long)g.selectedIndex, [g isSelectedAtIndex:1] ? "yes" : "no");

        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:@"start"];
        item.possibleLabels = [NSSet setWithObjects:@"Start", @"Start Encoding", nil];
        item.hidden = YES;
        printf("possible labels: %lu, hidden: %s\n", (unsigned long)item.possibleLabels.count,
               item.hidden ? "yes" : "no");

        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        w.title = @"Queue";
        w.subtitle = @"2 jobs pending";
        w.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
        printf("subtitle: %s, separator: %ld\n", w.subtitle.UTF8String, (long)w.titlebarSeparatorStyle);

        const char *names[] = {"sidebar.right", "stop.circle", "play.fill", "info.circle", NULL};
        for (int i = 0; names[i]; i++) {
            NSImage *im = [NSImage imageWithSystemSymbolName:@(names[i]) accessibilityDescription:nil];
            printf("symbol %s: %s\n", names[i], im && im.size.width > 0 ? "drawn" : "missing");
        }

        NSProgress *p = [NSProgress progressWithTotalUnitCount:10];
        [p publish];
        p.completedUnitCount = 4;
        [p unpublish];
        id sub = [NSProgress addSubscriberForFileURL:[NSURL fileURLWithPath:@"/tmp"]
                               withPublishingHandler:^NSProgress *(NSProgress *q) { return nil; }];
        [NSProgress removeSubscriber:sub];
        printf("published progress: %.1f, old: %s\n", p.fractionCompleted, p.isOld ? "yes" : "no");

        regex_t re;
        regmatch_t m[2];
        int err = regcomp(&re, "([0-9]+)x([0-9]+)", REG_EXTENDED);
        printf("regex: compiled %s, groups %zu\n", err ? "no" : "yes", (size_t)re.re_nsub);
        err = regexec(&re, "size 640x360", 2, m, 0);
        printf("match: %s at %d to %d\n", err ? "no" : "yes", (int)m[0].rm_so, (int)m[0].rm_eo);
        char msg[64];
        regerror(regexec(&re, "none", 0, NULL, 0), &re, msg, sizeof msg);
        printf("no match says: %s\n", msg[0] ? "something" : "nothing");
        regfree(&re);
    }
    return 0;
}
