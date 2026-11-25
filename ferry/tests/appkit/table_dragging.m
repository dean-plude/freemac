/* SPDX-License-Identifier: GPL-3.0-or-later
 * Dragging rows of tables and items of outlines, and dropping on them, as
 * MacPass and Sequel Pro do (freemac 1.220, Ferry 0.44.0): a drag begins
 * a few points from the press, carries the selection or the pressed row,
 * goes on the drag pasteboard through pasteboardWriterForRow: (or
 * writeItems:toPasteboard:), and is offered to the table under the pointer,
 * which proposes a row (or an item and child index) for validateDrop: to
 * take or change with setDropRow:dropOperation: (setDropItem:
 * dropChildIndex:), shows it, and hands the drop to acceptDrop:. Also a
 * press on a selected row of several, verticalMotionCanBeginDrag, Option
 * for a copy, the source's operation mask, a drag into another window, and
 * a view's own dragging session and older dragImage: drag. With no
 * display: the events are sent to the windows as GTK's would be. */
#import <Cocoa/Cocoa.h>

static NSString *const kRowType = @"org.example.row";

static NSString *op_name(NSDragOperation op)
{
    if (op == NSDragOperationNone)
        return @"none";
    if (op == NSDragOperationEvery)
        return @"every";
    NSMutableArray *names = [NSMutableArray array];
    if (op & NSDragOperationCopy) [names addObject:@"copy"];
    if (op & NSDragOperationLink) [names addObject:@"link"];
    if (op & NSDragOperationGeneric) [names addObject:@"generic"];
    if (op & NSDragOperationPrivate) [names addObject:@"private"];
    if (op & NSDragOperationMove) [names addObject:@"move"];
    if (op & NSDragOperationDelete) [names addObject:@"delete"];
    return [names componentsJoinedByString:@"+"];
}

static NSString *rows_text(NSIndexSet *rows)
{
    NSMutableArray *a = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [a addObject:@(i).stringValue]; }];
    return [a count] ? [a componentsJoinedByString:@","] : @"-";
}

static NSString *source_name(id<NSDraggingInfo> info)
{
    id s = [info draggingSource];
    if (!s)
        return @"none";
    if ([s isKindOfClass:[NSOutlineView class]])
        return @"the outline";
    if ([s isKindOfClass:[NSTableView class]])
        return [(NSTableView *)s tag] == 2 ? @"the second table" : @"the table";
    return NSStringFromClass([s class]);
}

/* ---- a table's data source: MacPass's way, with pasteboard writers ---- */

@interface Rows : NSObject <NSTableViewDataSource>
@property (strong) NSMutableArray *names;
@property NSInteger retargetRow;              /* -2: leave the proposal */
@property NSTableViewDropOperation retargetOp;
@property BOOL refuse;
@end
@implementation Rows
- (instancetype)init
{
    if ((self = [super init])) {
        _names = [@[ @"alpha", @"beta", @"gamma", @"delta", @"epsilon" ] mutableCopy];
        _retargetRow = -2;
    }
    return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)[_names count]; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return _names[(NSUInteger)row];
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)t pasteboardWriterForRow:(NSInteger)row
{
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:_names[(NSUInteger)row] forType:kRowType];
    [item setString:_names[(NSUInteger)row] forType:NSPasteboardTypeString];
    return item;
}
- (void)tableView:(NSTableView *)t draggingSession:(NSDraggingSession *)session
    willBeginAtPoint:(NSPoint)p forRowIndexes:(NSIndexSet *)rows
{
    printf("  drag begins with rows %s\n", [rows_text(rows) UTF8String]);
}
- (void)tableView:(NSTableView *)t draggingSession:(NSDraggingSession *)session
     endedAtPoint:(NSPoint)p operation:(NSDragOperation)op
{
    printf("  drag ended: %s\n", [op_name(op) UTF8String]);
}
- (NSDragOperation)tableView:(NSTableView *)t validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)op
{
    NSDragOperation mask = [info draggingSourceOperationMask];
    printf("  validate: row %ld %s, from %s, mask %s\n", (long)row, op == NSTableViewDropOn ? "on" : "above",
           [source_name(info) UTF8String], [op_name(mask) UTF8String]);
    if (_refuse)
        return NSDragOperationNone;
    if (_retargetRow != -2)
        [t setDropRow:_retargetRow dropOperation:_retargetOp];
    return mask & NSDragOperationMove ? NSDragOperationMove : mask & NSDragOperationCopy;
}
- (BOOL)tableView:(NSTableView *)t acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op
{
    NSArray *got = [[info draggingPasteboard] readObjectsForClasses:@[ [NSString class] ] options:nil];
    printf("  accept: row %ld %s, \"%s\"\n", (long)row, op == NSTableViewDropOn ? "on" : "above",
           [[got componentsJoinedByString:@", "] UTF8String]);
    return YES;
}
@end

/* ---- an outline's data source: Sequel Pro's way, writing items itself ---- */

@interface Tree : NSObject <NSOutlineViewDataSource>
@property (strong) NSDictionary *children;
@property (strong) id retargetItem;
@property NSInteger retargetIndex;            /* -2: leave the proposal */
@end
@implementation Tree
- (instancetype)init
{
    if ((self = [super init])) {
        _children = @{ @"" : @[ @"Fruit", @"Veg" ], @"Fruit" : @[ @"apple", @"pear" ], @"Veg" : @[ @"leek" ] };
        _retargetIndex = -2;
    }
    return self;
}
- (NSArray *)kids:(id)item { return _children[item ?: @""] ?: @[]; }
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(id)item { return (NSInteger)[[self kids:item] count]; }
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)i ofItem:(id)item { return [self kids:item][(NSUInteger)i]; }
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(id)item { return [[self kids:item] count] > 0; }
- (id)outlineView:(NSOutlineView *)o objectValueForTableColumn:(NSTableColumn *)c byItem:(id)item { return item; }
- (BOOL)outlineView:(NSOutlineView *)o writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pb
{
    [pb declareTypes:@[ kRowType ] owner:nil];
    [pb setString:[items componentsJoinedByString:@","] forType:kRowType];
    return YES;
}
- (void)outlineView:(NSOutlineView *)o draggingSession:(NSDraggingSession *)s willBeginAtPoint:(NSPoint)p
           forItems:(NSArray *)items
{
    printf("  drag begins with items %s\n", [[items componentsJoinedByString:@","] UTF8String]);
}
- (void)outlineView:(NSOutlineView *)o draggingSession:(NSDraggingSession *)s endedAtPoint:(NSPoint)p
          operation:(NSDragOperation)op
{
    printf("  drag ended: %s\n", [op_name(op) UTF8String]);
}
- (NSDragOperation)outlineView:(NSOutlineView *)o validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item
            proposedChildIndex:(NSInteger)index
{
    printf("  validate: item %s, child %ld, from %s\n", item ? [item UTF8String] : "(top)", (long)index,
           [source_name(info) UTF8String]);
    if (_retargetIndex != -2)
        [o setDropItem:_retargetItem dropChildIndex:_retargetIndex];
    return NSDragOperationMove;
}
- (BOOL)outlineView:(NSOutlineView *)o acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    printf("  accept: item %s, child %ld, \"%s\"\n", item ? [item UTF8String] : "(top)", (long)index,
           [[[info draggingPasteboard] stringForType:kRowType] UTF8String]);
    return YES;
}
@end

/* ---- a plain view that takes drops, in another window ---- */

@interface Well : NSView
@end
@implementation Well
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info
{
    printf("  the well: entered from %s, mask %s\n", [source_name(info) UTF8String],
           [op_name([info draggingSourceOperationMask]) UTF8String]);
    return NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)info { printf("  the well: exited\n"); }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    printf("  the well: dropped \"%s\"\n", [[[info draggingPasteboard] stringForType:NSPasteboardTypeString] UTF8String]);
    return YES;
}
@end

/* ---- a view's own drags ---- */

@interface Source : NSObject <NSDraggingSource>
@end
@implementation Source
- (NSDragOperation)draggingSession:(NSDraggingSession *)s sourceOperationMaskForDraggingContext:(NSDraggingContext)c
{
    printf("  source asked, within the app %d\n", c == NSDraggingContextWithinApplication);
    return NSDragOperationCopy;
}
- (void)draggingSession:(NSDraggingSession *)s willBeginAtPoint:(NSPoint)p
{
    printf("  source: begins, pasteboard has \"%s\"\n",
           [[[s draggingPasteboard] stringForType:NSPasteboardTypeString] UTF8String]);
}
- (void)draggingSession:(NSDraggingSession *)s endedAtPoint:(NSPoint)p operation:(NSDragOperation)op
{
    printf("  source: ended %s\n", [op_name(op) UTF8String]);
}
@end

@interface OldSource : NSObject
@end
@implementation OldSource
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local { return local ? NSDragOperationGeneric | NSDragOperationCopy : 0; }
- (void)draggedImage:(NSImage *)image beganAt:(NSPoint)p { printf("  old source: began\n"); }
- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)p operation:(NSDragOperation)op
{
    printf("  old source: ended %s\n", [op_name(op) UTF8String]);
}
@end

/* ---- the events ---- */

@interface Clicks : NSObject
@property NSInteger count;
- (void)clicked:(id)sender;
@end
@implementation Clicks
- (void)clicked:(id)sender { _count++; }
@end

static NSWindow *win_a;

static void send(NSEventType type, NSWindow *w, NSPoint p, NSEventModifierFlags flags)
{
    [w sendEvent:[NSEvent mouseEventWithType:type location:p modifierFlags:flags timestamp:0
                                 windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1
                                     pressure:type == NSEventTypeLeftMouseUp ? 0 : 1]];
}

/* A point in the window: a fraction of the way down a row of the table. */
static NSPoint at_row(NSTableView *t, NSInteger row, CGFloat down)
{
    NSRect r = [t rectOfRow:row];
    NSPoint p = NSMakePoint(NSMidX(r), NSMinY(r) + r.size.height * down);
    return [t convertPoint:p toView:nil];
}

static void show_indicator(NSTableView *t)
{
    for (NSView *v in [t subviews])
        if ([NSStringFromClass([v class]) isEqual:@"ATableDropIndicator"]) {
            NSRect f = [v frame];
            printf("  shown at %.0f,%.0f %.0fx%.0f\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
            return;
        }
    printf("  nothing shown\n");
}

/* Press at from, move a little, then through each point, and let go at the last. */
static void drag(NSWindow *w, NSPoint from, NSArray *through, NSEventModifierFlags flags, NSTableView *watch)
{
    send(NSEventTypeLeftMouseDown, w, from, 0);
    send(NSEventTypeLeftMouseDragged, w, NSMakePoint(from.x + 1, from.y), flags);
    for (NSUInteger i = 0; i < [through count]; i++) {
        NSPoint p = [through[i] pointValue];
        send(NSEventTypeLeftMouseDragged, w, p, flags);
        if (watch && i + 1 == [through count])
            show_indicator(watch);
    }
    send(NSEventTypeLeftMouseUp, w, [[through lastObject] pointValue], flags);
}

static NSTableView *make_table(NSRect frame, id ds, NSInteger tag)
{
    NSTableView *t = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [c setWidth:frame.size.width - 10];
    [t addTableColumn:c];
    [t setHeaderView:nil];
    [t setTag:tag];
    [t setDataSource:ds];
    [t setAllowsMultipleSelection:YES];
    [t registerForDraggedTypes:@[ kRowType ]];
    [t reloadData];
    return t;
}

#define P(x, y) [NSValue valueWithPoint:NSMakePoint(x, y)]
#define AT(t, row, down) [NSValue valueWithPoint:at_row(t, row, down)]

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        win_a = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled
                                              backing:NSBackingStoreBuffered defer:NO];
        Rows *rows = [[Rows alloc] init];
        NSTableView *t = make_table(NSMakeRect(0, 0, 300, 200), rows, 1);
        Clicks *clicks = [[Clicks alloc] init];
        [t setTarget:clicks];
        [t setAction:@selector(clicked:)];
        [[win_a contentView] addSubview:t];
        [win_a makeKeyAndOrderFront:nil];
        printf("defaults: local %s, other apps %s, vertical motion %d\n",
               [op_name([t draggingSourceOperationMaskForLocal:YES]) UTF8String],
               [op_name([t draggingSourceOperationMaskForLocal:NO]) UTF8String], [t verticalMotionCanBeginDrag]);

        printf("drag row 1 to row 3's top:\n");
        drag(win_a, at_row(t, 1, 0.5), @[ AT(t, 3, 0.1) ], 0, t);
        printf("  selected %s, clicks %ld, shown after %d\n", [rows_text([t selectedRowIndexes]) UTF8String],
               (long)clicks.count, [[t subviews] count] > 0 &&
               [NSStringFromClass([[[t subviews] lastObject] class]) isEqual:@"ATableDropIndicator"]);

        printf("onto row 2, moved to below it:\n");
        rows.retargetRow = 3;
        rows.retargetOp = NSTableViewDropAbove;
        drag(win_a, at_row(t, 0, 0.5), @[ AT(t, 1, 0.5), AT(t, 2, 0.5) ], 0, t);
        rows.retargetRow = -2;

        printf("onto the whole table:\n");
        rows.retargetRow = -1;
        rows.retargetOp = NSTableViewDropOn;
        drag(win_a, at_row(t, 0, 0.5), @[ AT(t, 4, 0.9) ], 0, t);
        rows.retargetRow = -2;

        printf("a click on a selected row of two:\n");
        [t selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)] byExtendingSelection:NO];
        send(NSEventTypeLeftMouseDown, win_a, at_row(t, 2, 0.5), 0);
        printf("  pressed: %s\n", [rows_text([t selectedRowIndexes]) UTF8String]);
        send(NSEventTypeLeftMouseUp, win_a, at_row(t, 2, 0.5), 0);
        printf("  let go: %s\n", [rows_text([t selectedRowIndexes]) UTF8String]);

        printf("both dragged, with Option, below the last row:\n");
        [t selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)] byExtendingSelection:NO];
        drag(win_a, at_row(t, 2, 0.5), @[ AT(t, 4, 0.95) ], NSEventModifierFlagOption, t);
        printf("  selected %s\n", [rows_text([t selectedRowIndexes]) UTF8String]);

        printf("refused:\n");
        rows.refuse = YES;
        drag(win_a, at_row(t, 0, 0.5), @[ AT(t, 3, 0.5) ], 0, t);
        rows.refuse = NO;

        printf("nothing the source allows:\n");
        [t setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
        drag(win_a, at_row(t, 0, 0.5), @[ AT(t, 3, 0.5) ], 0, nil);
        [t setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];

        printf("straight down with verticalMotionCanBeginDrag off:\n");
        [t setVerticalMotionCanBeginDrag:NO];
        NSPoint down = at_row(t, 1, 0.5);
        drag(win_a, down, @[ P(down.x, down.y - 40) ], 0, nil);
        printf("  selected %s\n", [rows_text([t selectedRowIndexes]) UTF8String]);
        printf("and sideways:\n");
        drag(win_a, down, @[ P(down.x + 30, down.y), AT(t, 4, 0.5) ], 0, nil);
        [t setVerticalMotionCanBeginDrag:YES];

        /* another window: a second table, and a well */
        NSWindow *win_b = [[NSWindow alloc] initWithContentRect:NSMakeRect(500, 100, 300, 300)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered defer:NO];
        Rows *other = [[Rows alloc] init];
        other.names = [@[ @"one", @"two" ] mutableCopy];
        NSTableView *t2 = make_table(NSMakeRect(0, 150, 300, 150), other, 2);
        [[win_b contentView] addSubview:t2];
        Well *well = [[Well alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
        [well registerForDraggedTypes:@[ NSPasteboardTypeString ]];
        [[win_b contentView] addSubview:well];
        [win_b orderFront:nil];
        NSPoint t2row = at_row(t2, 1, 0.5);   /* in win_b; as win_a sees it: */
        NSPoint t2_from_a = NSMakePoint(t2row.x + 400, t2row.y);
        printf("into the other window's table:\n");
        drag(win_a, at_row(t, 4, 0.5), @[ P(250, 100), P(t2_from_a.x, t2_from_a.y) ], 0, t2);
        printf("into the other window's well, by way of its table:\n");
        drag(win_a, at_row(t, 3, 0.5), @[ P(t2_from_a.x, t2_from_a.y), P(t2_from_a.x, 50) ], 0, nil);
        printf("out of every window:\n");
        drag(win_a, at_row(t, 3, 0.5), @[ P(t2_from_a.x, 50), P(-500, -500) ], 0, nil);

        /* an outline */
        NSWindow *win_c = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 400, 300, 200)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered defer:NO];
        Tree *tree = [[Tree alloc] init];
        NSOutlineView *o = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        NSTableColumn *oc = [[NSTableColumn alloc] initWithIdentifier:@"item"];
        [oc setWidth:280];
        [o addTableColumn:oc];
        [o setOutlineTableColumn:oc];
        [o setHeaderView:nil];
        [o setDataSource:tree];
        [o registerForDraggedTypes:@[ kRowType ]];
        [o reloadData];
        [o expandItem:@"Fruit"];
        [o setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
        [[win_c contentView] addSubview:o];
        [win_c orderFront:nil];
        printf("outline rows %ld\n", (long)[o numberOfRows]);
        printf("pear onto Veg:\n");
        drag(win_c, at_row(o, 2, 0.5), @[ AT(o, 3, 0.5) ], 0, o);
        printf("pear before apple:\n");
        drag(win_c, at_row(o, 2, 0.5), @[ AT(o, 1, 0.1) ], 0, o);
        printf("pear below Fruit, which is open:\n");
        drag(win_c, at_row(o, 2, 0.5), @[ AT(o, 0, 0.9) ], 0, o);
        printf("apple below Veg, which is closed:\n");
        drag(win_c, at_row(o, 1, 0.5), @[ AT(o, 3, 0.9) ], 0, o);
        printf("onto Veg, moved to the end of Fruit (MacPass's way):\n");
        tree.retargetItem = @"Fruit";
        tree.retargetIndex = 2;
        drag(win_c, at_row(o, 1, 0.5), @[ AT(o, 3, 0.5) ], 0, o);
        printf("onto Veg, moved between Veg's own children:\n");
        tree.retargetItem = @"Veg";
        tree.retargetIndex = 0;
        drag(win_c, at_row(o, 1, 0.5), @[ AT(o, 3, 0.5) ], 0, o);
        tree.retargetIndex = -2;

        /* a view's own dragging session, and the older way */
        printf("a dragging session from a view, onto the table:\n");
        Source *source = [[Source alloc] init];
        NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:@"dragged text"];
        NSPoint start = NSMakePoint(5, 5);
        NSEvent *e = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:start modifierFlags:0
                                       timestamp:0 windowNumber:[win_a windowNumber] context:nil eventNumber:0
                                      clickCount:1 pressure:1];
        [t registerForDraggedTypes:@[ kRowType, NSPasteboardTypeString ]];
        NSDraggingSession *session = [[win_a contentView] beginDraggingSessionWithItems:@[ item ] event:e
                                                                                  source:source];
        printf("  session: sequence above 0 %d, location %.0f,%.0f\n", [session draggingSequenceNumber] > 0,
               [session draggingLocation].x, [session draggingLocation].y);
        send(NSEventTypeLeftMouseDragged, win_a, at_row(t, 1, 0.5), 0);
        send(NSEventTypeLeftMouseUp, win_a, at_row(t, 1, 0.5), 0);
        printf("the older way, onto the well:\n");
        OldSource *old = [[OldSource alloc] init];
        NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
        [pb clearContents];
        [pb setString:@"old text" forType:NSPasteboardTypeString];
        [[win_a contentView] dragImage:nil at:start offset:NSZeroSize event:e pasteboard:pb source:old slideBack:YES];
        send(NSEventTypeLeftMouseDragged, win_a, P(t2_from_a.x, 50).pointValue, 0);
        send(NSEventTypeLeftMouseUp, win_a, P(t2_from_a.x, 50).pointValue, 0);
        printf("the table's clicks: %ld\n", (long)clicks.count);
    }
    return 0;
}
