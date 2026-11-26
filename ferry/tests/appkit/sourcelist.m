// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * A source list, as VLC's sidebar is one: a view-based outline view whose
 * top items are headings (group rows). A heading in Interface Builder's
 * colour for one is drawn grey, and opens and closes with the Show or Hide
 * button at its right, there while the mouse is over it. Original freemac
 * code, run without a display.
 */
#import <Cocoa/Cocoa.h>

static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
}
static void click(NSWindow *w, NSView *v, NSPoint p)
{
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, p)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, p)];
}

@interface Sidebar : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (strong) NSDictionary *children;
@property (strong) NSArray *top;
@end
@implementation Sidebar
- (instancetype)init
{
    if ((self = [super init])) {
        _top = @[ @"LIBRARY", @"MY COMPUTER" ];
        _children = @{ @"LIBRARY" : @[ @"Playlist", @"Media Library" ], @"MY COMPUTER" : @[ @"My Videos", @"My Music" ] };
    }
    return self;
}
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    return (NSInteger)[(item ? _children[item] : _top) count];
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(id)item
{
    return (item ? _children[item] : _top)[(NSUInteger)i];
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item { return _children[item] != nil; }
- (BOOL)outlineView:(NSOutlineView *)ov isGroupItem:(id)item { return [_top containsObject:item]; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)c item:(id)item
{
    NSTableCellView *v = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
    NSTextField *tf = [NSTextField labelWithString:item];
    tf.textColor = [_top containsObject:item] ? [NSColor headerColor] : [NSColor controlTextColor];
    [v addSubview:tf];
    v.textField = tf;
    return v;
}
@end

static const char *grey(NSColor *c)
{
    return [c isEqual:[NSColor secondaryLabelColor]] ? "grey" : [c isEqual:[NSColor headerColor]] ? "header colour" : "its own colour";
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 300) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        NSOutlineView *ov = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 240, 300)];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        col.width = 230;
        [ov addTableColumn:col];
        ov.outlineTableColumn = col;
        ov.headerView = nil;
        ov.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
        Sidebar *s = [[Sidebar alloc] init];
        ov.dataSource = s;
        ov.delegate = s;
        [w.contentView addSubview:ov];
        [ov reloadData];
        [ov expandItem:@"LIBRARY"];
        printf("rows %ld\n", (long)ov.numberOfRows);
        for (NSInteger r = 0; r < ov.numberOfRows; r++) {
            NSTableCellView *v = [ov viewAtColumn:0 row:r makeIfNecessary:YES];
            printf("  %s: %s\n", [[ov itemAtRow:r] UTF8String], grey(v.textField.textColor));
        }
        NSRect hide = [ov frameOfOutlineCellAtRow:3];
        printf("Show button at the heading's right: %s; on a row that isn't a heading: %s\n",
               hide.size.width > 0 && NSMaxX(hide) > 200 && NSMaxX(hide) <= 240 ? "yes" : "no",
               NSIsEmptyRect([ov frameOfOutlineCellAtRow:1]) ? "none" : "one");
        click(w, ov, NSMakePoint(NSMidX(hide), NSMidY(hide)));
        printf("after Show: rows %ld, %s open %s\n", (long)ov.numberOfRows, [[ov itemAtRow:3] UTF8String],
               [ov isItemExpanded:@"MY COMPUTER"] ? "yes" : "no");
        hide = [ov frameOfOutlineCellAtRow:0];
        click(w, ov, NSMakePoint(NSMidX(hide), NSMidY(hide)));
        printf("after Hide on LIBRARY: rows %ld, selected %ld\n", (long)ov.numberOfRows, (long)ov.selectedRow);
        click(w, ov, NSMakePoint(30, NSMidY([ov rectOfRow:0])));
        printf("a click on a heading's words: rows %ld\n", (long)ov.numberOfRows);
    }
    return 0;
}
