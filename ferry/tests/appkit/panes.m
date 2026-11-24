/* SPDX-License-Identifier: GPL-3.0-or-later
 * Split views and tab views, with no display: dividers laid out, moved,
 * dragged and held to a delegate's limits, a subview collapsing, a window
 * growing given to the pane with the lowest holding priority, positions
 * kept under an autosave name; tabs added, selected by code, by click and
 * by the keyboard, removed, and asked of the delegate; and both loaded
 * from a nib in the NIBArchive form (Panes.nib, from make_nibs.py). */
#import <Cocoa/Cocoa.h>

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p, NSInteger clicks)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:clicks pressure:1];
}

@interface PanesOwner : NSObject <NSSplitViewDelegate, NSTabViewDelegate>
@property (strong) NSView *view;
@property (strong) NSSplitView *split;
@property (strong) NSTabView *tabs;
@property (strong) NSMutableArray *log;
@property BOOL refuse, collapsible;
@end
@implementation PanesOwner
- (instancetype)init
{
    if ((self = [super init]))
        _log = [NSMutableArray array];
    return self;
}
- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return p + 60; }
- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return p - 80; }
- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)v
{
    return _collapsible && v == [[sv subviews] firstObject];
}
- (void)splitViewDidResizeSubviews:(NSNotification *)n { [_log addObject:@"resized"]; }
- (BOOL)tabView:(NSTabView *)tv shouldSelectTabViewItem:(NSTabViewItem *)item
{
    [_log addObject:[@"should " stringByAppendingString:[item label]]];
    return !_refuse;
}
- (void)tabView:(NSTabView *)tv willSelectTabViewItem:(NSTabViewItem *)item
{
    [_log addObject:[@"will " stringByAppendingString:[item label]]];
}
- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item
{
    [_log addObject:[@"did " stringByAppendingString:[item label]]];
}
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tv { [_log addObject:@"count"]; }
- (void)dump:(const char *)what
{
    printf("%s: %s\n", what, [[_log componentsJoinedByString:@", "] UTF8String]);
    [_log removeAllObjects];
}
@end

static void save(NSView *v, const char *name)
{
    const char *dir = getenv("FERRY_PANES_PNG");
    if (!dir)
        return;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[NSString stringWithFormat:@"%s/%s.png", dir, name] atomically:YES];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSSplitView Subview Frames PanesSplit"];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        PanesOwner *owner = [[PanesOwner alloc] init];

        /* ---- a split view built in code ---- */
        NSSplitView *sv = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
        [sv setVertical:YES];
        [sv setDividerStyle:NSSplitViewDividerStyleThin];
        [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 200)];
        NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [sv addSubview:a];
        [sv addSubview:b];
        [[w contentView] addSubview:sv];
        [sv adjustSubviews];
        printf("flipped %d, divider %.0f, arranged %lu\n", [sv isFlipped], [sv dividerThickness],
               (unsigned long)[[sv arrangedSubviews] count]);
        rect("left", [a frame]);
        rect("right", [b frame]);
        printf("divider at %.0f, can go %.0f to %.0f\n", [sv positionOfDividerAtIndex:0],
               [sv minPossiblePositionOfDividerAtIndex:0], [sv maxPossiblePositionOfDividerAtIndex:0]);
        [sv setPosition:150 ofDividerAtIndex:0];
        rect("moved: left", [a frame]);
        rect("moved: right", [b frame]);
        [sv setPosition:1000 ofDividerAtIndex:0];
        printf("kept inside: %.0f\n", [sv positionOfDividerAtIndex:0]);
        [sv setPosition:150 ofDividerAtIndex:0];

        /* growing: the lowest holding priority takes it (the left pane here) */
        [sv setHoldingPriority:260 forSubviewAtIndex:1];
        [w setContentSize:NSMakeSize(500, 200)];
        rect("window wider: left", [a frame]);
        rect("window wider: right", [b frame]);
        [sv setHoldingPriority:250 forSubviewAtIndex:1];
        [w setContentSize:NSMakeSize(400, 200)];
        rect("narrower, equal priorities: left", [a frame]);
        rect("narrower, equal priorities: right", [b frame]);

        /* dragging the divider, held to the delegate's limits */
        [sv setDelegate:owner];
        [sv setPosition:150 ofDividerAtIndex:0];
        [owner.log removeAllObjects];
        CGFloat at = [sv positionOfDividerAtIndex:0];
        printf("hit on the divider is the split view: %d\n", [[w contentView] hitTest:NSMakePoint(at + 1, 50)] == sv);
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, sv, NSMakePoint(at, 50), 1)];
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, sv, NSMakePoint(at + 40, 50), 1)];
        printf("dragged to %.0f\n", [sv positionOfDividerAtIndex:0]);
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, sv, NSMakePoint(30, 50), 1)];
        printf("held at the delegate's minimum: %.0f\n", [sv positionOfDividerAtIndex:0]);
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, sv, NSMakePoint(390, 50), 1)];
        printf("held at the delegate's maximum: %.0f\n", [sv positionOfDividerAtIndex:0]);
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, sv, NSMakePoint(390, 50), 1)];
        owner.collapsible = YES;
        at = [sv positionOfDividerAtIndex:0];
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, sv, NSMakePoint(at, 50), 1)];
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, sv, NSMakePoint(10, 50), 1)];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, sv, NSMakePoint(10, 50), 1)];
        printf("dragged past halfway: left collapsed %d, hidden %d\n", [sv isSubviewCollapsed:a], [a isHidden]);
        rect("right takes the room", [b frame]);
        [sv setPosition:120 ofDividerAtIndex:0];
        printf("opened again: collapsed %d, left width %.0f\n", [sv isSubviewCollapsed:a], [a frame].size.width);
        [owner dump:"delegate heard"];

        /* horizontal dividers, thick */
        [sv setVertical:NO];
        [sv setDividerStyle:NSSplitViewDividerStyleThick];
        [sv adjustSubviews];
        rect("stacked: top", [a frame]);
        rect("stacked: bottom", [b frame]);
        [sv removeFromSuperview];

        /* ---- a tab view built in code ---- */
        NSTabView *tv = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [tv setDelegate:owner];
        printf("no tabs: selected %d, count %ld\n", [tv selectedTabViewItem] != nil, (long)[tv numberOfTabViewItems]);
        NSArray *labels = @[ @"Look", @"Sound", @"Keys" ];
        for (NSString *label in labels) {
            NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:[label lowercaseString]];
            [item setLabel:label];
            [item setView:[[NSView alloc] initWithFrame:NSZeroRect]];
            [tv addTabViewItem:item];
        }
        [[w contentView] addSubview:tv];
        printf("three tabs, first selected: %s\n", [[[tv selectedTabViewItem] label] UTF8String]);
        rect("content rect", [tv contentRect]);
        rect("its view fills it", [[[tv selectedTabViewItem] view] frame]);
        printf("its view is shown: %d, the others aren't: %d\n",
               [[[tv tabViewItemAtIndex:0] view] superview] == tv, [[[tv tabViewItemAtIndex:1] view] superview] == nil);
        [owner dump:"delegate heard"];
        [tv selectTabViewItemWithIdentifier:@"keys"];
        printf("by identifier: %s (index %ld)\n", [[[tv selectedTabViewItem] label] UTF8String],
               (long)[tv indexOfTabViewItem:[tv selectedTabViewItem]]);
        [owner dump:"delegate heard"];
        owner.refuse = YES;
        [tv selectFirstTabViewItem:nil];
        printf("refused: still %s\n", [[[tv selectedTabViewItem] label] UTF8String]);
        owner.refuse = NO;
        [owner dump:"delegate heard"];
        /* clicking a tab */
        NSTabViewItem *sound = [tv tabViewItemAtIndex:1];
        NSPoint middle = NSZeroPoint;
        for (CGFloat x = 0; x < 300; x++)
            if ([tv tabViewItemAtPoint:NSMakePoint(x, 12)] == sound) {
                middle = NSMakePoint(x + 10, 12);
                break;
            }
        printf("tab at the top edge: %d\n", middle.x > 0);
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, tv, middle, 1)];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, tv, middle, 1)];
        printf("clicked: %s, tab state %lu\n", [[[tv selectedTabViewItem] label] UTF8String],
               (unsigned long)[sound tabState]);
        [owner dump:"delegate heard"];
        [tv selectNextTabViewItem:nil];
        [tv selectNextTabViewItem:nil];
        printf("next twice: %s\n", [[[tv selectedTabViewItem] label] UTF8String]);
        save(tv, "tabs");
        [tv removeTabViewItem:[tv selectedTabViewItem]];
        printf("removed the selected one: now %s, %ld left\n", [[[tv selectedTabViewItem] label] UTF8String],
               (long)[tv numberOfTabViewItems]);
        [owner dump:"delegate heard"];
        [tv setTabViewType:NSNoTabsNoBorder];
        rect("no tabs, no border: content", [tv contentRect]);
        [tv setTabPosition:NSTabPositionBottom];
        printf("bottom tabs: type %lu\n", (unsigned long)[tv tabViewType]);
        @try {
            [tv tabViewItemAtIndex:7];
        } @catch (NSException *x) {
            printf("past the end: %s\n", [[x name] UTF8String]);
        }
        [tv removeFromSuperview];

        /* ---- both from a nib ---- */
        NSString *path = [NSString stringWithFormat:@"%s/Panes.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        PanesOwner *po = [[PanesOwner alloc] init];
        NSArray *top = nil;
        printf("nib loaded: %d\n", [nib instantiateWithOwner:po topLevelObjects:&top]);
        printf("classes: %s, %s\n", [NSStringFromClass([po.split class]) UTF8String],
               [NSStringFromClass([po.tabs class]) UTF8String]);
        printf("split: vertical %d, thin %d, autosave %s, delegate set %d\n", [po.split isVertical],
               [po.split dividerStyle] == NSSplitViewDividerStyleThin, [[po.split autosaveName] UTF8String],
               [po.split delegate] == (id)po);
        printf("split divider at %.0f\n", [po.split positionOfDividerAtIndex:0]);
        printf("tabs: %ld, selected %s, truncates %d, delegate set %d\n", (long)[po.tabs numberOfTabViewItems],
               [[[po.tabs selectedTabViewItem] identifier] UTF8String], [po.tabs allowsTruncatedLabels],
               [po.tabs delegate] == (id)po);
        NSView *shown = [[po.tabs selectedTabViewItem] view];
        printf("one subview, the selected tab's: %d %d\n", (int)[[po.tabs subviews] count],
               [[po.tabs subviews] firstObject] == shown);
        printf("its label: %s\n", [[(NSTextField *)[[shown subviews] firstObject] stringValue] UTF8String]);
        [po.tabs selectTabViewItemAtIndex:0];
        NSView *general = [[po.tabs selectedTabViewItem] view];
        printf("first tab: %s, in place of the other %d\n", [[(NSTextField *)[[general subviews] firstObject] stringValue] UTF8String],
               [[po.tabs subviews] count] == 1 && [shown superview] == nil);
        [po dump:"nib's delegate heard"];
        /* the split view's place is kept under its autosave name */
        NSWindow *w2 = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 200) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
        [w2 setContentView:po.view];
        at = [po.split positionOfDividerAtIndex:0];
        [w2 sendEvent:mouse(NSEventTypeLeftMouseDown, w2, po.split, NSMakePoint(at, 100), 1)];
        [w2 sendEvent:mouse(NSEventTypeLeftMouseDragged, w2, po.split, NSMakePoint(170, 100), 1)];
        [w2 sendEvent:mouse(NSEventTypeLeftMouseUp, w2, po.split, NSMakePoint(170, 100), 1)];
        NSArray *kept = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NSSplitView Subview Frames PanesSplit"];
        printf("kept: %s\n", [[kept componentsJoinedByString:@" | "] UTF8String]);
        save(po.view, "nib");
        NSSplitView *again = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 320, 200)];
        [again setVertical:YES];
        [again setDividerStyle:NSSplitViewDividerStyleThin];
        [again addSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 200)]];
        [again addSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 270, 200)]];
        [again setAutosaveName:@"PanesSplit"];
        printf("restored at %.0f\n", [again positionOfDividerAtIndex:0]);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSSplitView Subview Frames PanesSplit"];
    }
    return 0;
}
