/* SPDX-License-Identifier: GPL-3.0-or-later
 * Table views and outline views, with no display: a cell-based table in a
 * scroll view (geometry, its header tiled above the rows, drawing through
 * its data cells), selection by click, shift- and command-click, double
 * click and the arrow keys, with the delegate's say; sorting by clicks on
 * the header; columns resized by dragging the header's dividers and by the
 * table growing; rows inserted and removed; a view-based table making
 * only the views in sight and reusing them; an outline view opening and
 * closing items (by code, by clicks on its chevrons and by the arrow
 * keys) with its rows and items mapped both ways; and a view-based table
 * and an outline view loaded from a nib (Tables.nib, from make_nibs.py). */
#import <Cocoa/Cocoa.h>

static const char *some(id x) { return x ? "some" : "nil"; }
static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p, NSInteger clicks, NSEventModifierFlags flags)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:flags timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:clicks pressure:1];
}
static void click(NSWindow *w, NSView *v, NSPoint p, NSInteger clicks, NSEventModifierFlags flags)
{
    for (NSInteger c = 1; c <= clicks; c++) {
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, p, c, flags)];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, p, c, flags)];
    }
}
static void drag(NSWindow *w, NSView *v, NSPoint from, NSPoint to)
{
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, from, 1, 0)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, v, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), 1, 0)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, v, to, 1, 0)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, to, 1, 0)];
}
static void key(NSWindow *w, unichar c, NSEventModifierFlags flags)
{
    NSString *s = [NSString stringWithFormat:@"%C", c];
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}
static NSString *rows(NSIndexSet *set)
{
    NSMutableArray *a = [NSMutableArray array];
    [set enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [a addObject:[NSString stringWithFormat:@"%lu", (unsigned long)i]]; }];
    return [NSString stringWithFormat:@"{%@}", [a componentsJoinedByString:@","]];
}
static void draw(NSView *v)
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    const char *dir = getenv("FERRY_TABLES_PNG");
    static int n;
    if (dir) {
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithFormat:@"%s/tables-%d.png", dir, ++n] atomically:YES];
    }
}

/* ---- a cell-based table's data source and delegate ---- */

@interface Files : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSMutableArray *files;
@property (strong) NSMutableArray *log;
@property NSInteger refused, displayed;
@property BOOL frozen;
@end
@implementation Files
- (instancetype)init
{
    if ((self = [super init])) {
        _log = [NSMutableArray array];
        _refused = -1;
        NSArray *names = @[ @"notes.txt", @"zebra.png", @"apple.pdf", @"mango.mov", @"kiwi.rtf", @"berry.zip" ];
        NSArray *sizes = @[ @12, @300, @45, @9000, @7, @120 ];
        _files = [NSMutableArray array];
        for (NSUInteger i = 0; i < [names count]; i++)
            [_files addObject:[@{@"name" : names[i], @"size" : sizes[i], @"done" : @(i % 2)} mutableCopy]];
    }
    return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)[_files count]; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return _files[(NSUInteger)row][[c identifier]];
}
- (void)tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    [_log addObject:[NSString stringWithFormat:@"set %@ of row %ld to %@", [c identifier], (long)row, v]];
    _files[(NSUInteger)row][[c identifier]] = v;
}
- (void)tableView:(NSTableView *)tv sortDescriptorsDidChange:(NSArray *)old
{
    NSMutableArray *keys = [NSMutableArray array];
    for (NSSortDescriptor *d in [tv sortDescriptors])
        [keys addObject:[NSString stringWithFormat:@"%@ %s", [d key], [d ascending] ? "up" : "down"]];
    [_log addObject:[NSString stringWithFormat:@"sort by %@ (was %lu)", [keys componentsJoinedByString:@", "],
                                               (unsigned long)[old count]]];
    [_files sortUsingDescriptors:[tv sortDescriptors]];
    [tv reloadData];
}
- (void)tableView:(NSTableView *)tv willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    _displayed++;
}
- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row { return row != _refused; }
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tv { return !_frozen; }
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
    [_log addObject:[@"selection " stringByAppendingString:rows([[n object] selectedRowIndexes])]];
}
- (void)tableView:(NSTableView *)tv mouseDownInHeaderOfTableColumn:(NSTableColumn *)c
{
    [_log addObject:[@"header down " stringByAppendingString:[c identifier]]];
}
- (void)tableView:(NSTableView *)tv didClickTableColumn:(NSTableColumn *)c
{
    [_log addObject:[@"header click " stringByAppendingString:[c identifier]]];
}
- (void)clicked:(NSTableView *)tv
{
    [_log addObject:[NSString stringWithFormat:@"action row %ld column %ld", (long)[tv clickedRow], (long)[tv clickedColumn]]];
}
- (void)doubleClicked:(NSTableView *)tv
{
    [_log addObject:[NSString stringWithFormat:@"double row %ld", (long)[tv clickedRow]]];
}
- (NSString *)names
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *f in _files)
        [a addObject:f[@"name"]];
    return [a componentsJoinedByString:@" "];
}
- (void)dump:(const char *)what
{
    printf("%s: %s\n", what, [[_log componentsJoinedByString:@"; "] UTF8String]);
    [_log removeAllObjects];
}
@end

/* ---- a view-based table's ---- */

@interface Numbers : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property NSInteger made, asked;
@end
@implementation Numbers
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return 50; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    _asked++;
    NSTableCellView *v = [tv makeViewWithIdentifier:@"Number" owner:self];
    if (!v) {
        _made++;
        v = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
        NSTextField *f = [NSTextField labelWithString:@""];
        [f setFrame:NSMakeRect(2, 0, 96, 17)];
        [v addSubview:f];
        [v setTextField:f];
        [v setIdentifier:@"Number"];
    }
    [[v textField] setStringValue:[NSString stringWithFormat:@"%@ %ld", [c identifier], (long)row]];
    return v;
}
@end

/* ---- an outline's ---- */

@interface Node : NSObject
@property (copy) NSString *name;
@property (strong) NSMutableArray *children;   /* nil for a leaf */
@end
@implementation Node
+ (Node *)node:(NSString *)name children:(NSArray *)children
{
    Node *n = [[Node alloc] init];
    n.name = name;
    n.children = children ? [children mutableCopy] : nil;
    return n;
}
- (NSString *)description { return _name; }
@end

@interface Tree : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (strong) NSArray *top;
@property (strong) NSMutableArray *log;
@property BOOL lockLeek;
@end
@implementation Tree
- (instancetype)init
{
    if ((self = [super init])) {
        _log = [NSMutableArray array];
        _lockLeek = YES;
        _top = @[
            [Node node:@"Fruit" children:@[ [Node node:@"Apple" children:nil], [Node node:@"Pear" children:nil] ]],
            [Node node:@"Veg"
                  children:@[ [Node node:@"Kale" children:nil],
                              [Node node:@"Leek" children:@[ [Node node:@"Baby leek" children:nil] ]] ]],
            [Node node:@"Rock" children:nil],
        ];
    }
    return self;
}
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(Node *)item
{
    return (NSInteger)[(item ? item.children : _top) count];
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(Node *)item
{
    return (item ? item.children : _top)[(NSUInteger)i];
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(Node *)item { return item.children != nil; }
- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)c byItem:(Node *)item
{
    return item.name;
}
- (BOOL)outlineView:(NSOutlineView *)ov shouldExpandItem:(Node *)item
{
    return !(_lockLeek && [item.name isEqualToString:@"Leek"]);
}
- (void)outlineViewItemWillExpand:(NSNotification *)n { [_log addObject:[NSString stringWithFormat:@"will open %@", n.userInfo[@"NSObject"]]]; }
- (void)outlineViewItemDidExpand:(NSNotification *)n { [_log addObject:[NSString stringWithFormat:@"opened %@", n.userInfo[@"NSObject"]]]; }
- (void)outlineViewItemWillCollapse:(NSNotification *)n { [_log addObject:[NSString stringWithFormat:@"will close %@", n.userInfo[@"NSObject"]]]; }
- (void)outlineViewItemDidCollapse:(NSNotification *)n { [_log addObject:[NSString stringWithFormat:@"closed %@", n.userInfo[@"NSObject"]]]; }
- (void)outlineViewSelectionDidChange:(NSNotification *)n
{
    [_log addObject:[@"selection " stringByAppendingString:rows([[n object] selectedRowIndexes])]];
}
- (void)dump:(const char *)what
{
    printf("%s: %s\n", what, [[_log componentsJoinedByString:@"; "] UTF8String]);
    [_log removeAllObjects];
}
@end
static void show_rows(const char *what, NSOutlineView *ov)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSInteger r = 0; r < [ov numberOfRows]; r++) {
        Node *n = [ov itemAtRow:r];
        NSString *mark = [ov isExpandable:n] ? ([ov isItemExpanded:n] ? @"v " : @"> ") : @"";
        [a addObject:[NSString stringWithFormat:@"%@%@%@", [@"" stringByPaddingToLength:(NSUInteger)[ov levelForRow:r] * 2
                                                                             withString:@" " startingAtIndex:0],
                                                mark, n.name]];
    }
    printf("%s: %s\n", what, [[a componentsJoinedByString:@" | "] UTF8String]);
}

/* ---- the nib's owner ---- */

@interface TablesOwner : Tree <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSView *view;
@property (strong) NSTableView *table;
@property (strong) NSOutlineView *outline;
@end
@implementation TablesOwner
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return 3; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    if (![[c identifier] isEqualToString:@"name"])
        return nil;
    NSTableCellView *v = [tv makeViewWithIdentifier:@"NameCell" owner:self];
    [[v textField] setStringValue:[NSString stringWithFormat:@"item %ld", (long)row]];
    return v;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 300) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];

        /* ---- a cell-based table in a scroll view ---- */
        Files *files = [[Files alloc] init];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 320, 200)];
        [scroll setHasVerticalScroller:YES];
        NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
        NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [name setTitle:@"Name"];
        [name setWidth:120];
        [name setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
        [name setEditable:NO]; /* so that a double click sends the double action (editing is in editing.m) */
        NSTableColumn *size = [[NSTableColumn alloc] initWithIdentifier:@"size"];
        [size setTitle:@"Size"];
        [size setWidth:80];
        [size setMinWidth:40];
        [size setMaxWidth:200];
        [size setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:@"size" ascending:YES]];
        NSTableColumn *done = [[NSTableColumn alloc] initWithIdentifier:@"done"];
        [done setTitle:@"Done"];
        [done setWidth:40];
        NSButtonCell *check = [[NSButtonCell alloc] initTextCell:@""];
        [check setButtonType:NSButtonTypeSwitch];
        [done setDataCell:check];
        [tv addTableColumn:name];
        [tv addTableColumn:size];
        [tv addTableColumn:done];
        [tv setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
        [tv setAllowsMultipleSelection:YES];
        [tv setUsesAlternatingRowBackgroundColors:YES];
        [tv setGridStyleMask:NSTableViewSolidVerticalGridLineMask];
        [tv setDataSource:files];
        [tv setDelegate:files];
        [tv setTarget:files];
        [tv setAction:@selector(clicked:)];
        [tv setDoubleAction:@selector(doubleClicked:)];
        [scroll setDocumentView:tv];
        [[w contentView] addSubview:scroll];

        printf("rows %ld, columns %ld, row height %.0f, spacing %.0fx%.0f, flipped %d\n", (long)[tv numberOfRows],
               (long)[tv numberOfColumns], [tv rowHeight], [tv intercellSpacing].width, [tv intercellSpacing].height,
               [tv isFlipped]);
        printf("size column %ld, column 'done' titled %s, missing %ld\n", (long)[tv columnWithIdentifier:@"size"],
               [[[tv tableColumnWithIdentifier:@"done"] title] UTF8String], (long)[tv columnWithIdentifier:@"nope"]);
        rect("header", [[tv headerView] frame]);
        rect("header clip", [[[tv headerView] superview] frame]);
        rect("content clip", [[scroll contentView] frame]);
        rect("table", [tv frame]);
        printf("widths after fitting the clip: %.0f %.0f %.0f\n", [name width], [size width], [done width]);
        rect("row 2", [tv rectOfRow:2]);
        rect("column 1", [tv rectOfColumn:1]);
        rect("cell 1,2", [tv frameOfCellAtColumn:1 row:2]);
        printf("row at y=40: %ld, at y=500: %ld; column at x=130: %ld, at x=-5: %ld\n",
               (long)[tv rowAtPoint:NSMakePoint(5, 40)], (long)[tv rowAtPoint:NSMakePoint(5, 500)],
               (long)[tv columnAtPoint:NSMakePoint(130, 5)], (long)[tv columnAtPoint:NSMakePoint(-5, 5)]);
        NSRange shown = [tv rowsInRect:NSMakeRect(0, 30, 10, 30)];
        printf("rows in y 30..60: %lu+%lu\n", (unsigned long)shown.location, (unsigned long)shown.length);
        printf("prepared cell 0,1: %s (%s); check cell 2,1 state %ld\n",
               [[[tv preparedCellAtColumn:0 row:1] stringValue] UTF8String],
               [NSStringFromClass([[tv preparedCellAtColumn:0 row:1] class]) UTF8String],
               (long)[[tv preparedCellAtColumn:2 row:1] state]);
        files.displayed = 0;
        draw([w contentView]);
        printf("drawn: cells displayed %s\n", files.displayed >= 18 ? "all" : "too few");

        /* ---- selection ---- */
        NSPoint row1 = NSMakePoint(20, NSMidY([tv rectOfRow:1]));
        click(w, tv, row1, 1, 0);
        printf("first responder is the table: %d\n", [w firstResponder] == tv);
        printf("click row 1: selected %ld %s, clicked %ld,%ld\n", (long)[tv selectedRow],
               [rows([tv selectedRowIndexes]) UTF8String], (long)[tv clickedRow], (long)[tv clickedColumn]);
        [files dump:"  log"];
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:3])), 1, NSEventModifierFlagShift);
        printf("shift-click row 3: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:2])), 1, NSEventModifierFlagCommand);
        printf("command-click row 2: %s, selected row %ld\n", [rows([tv selectedRowIndexes]) UTF8String],
               (long)[tv selectedRow]);
        [files dump:"  log"];
        files.refused = 4;
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:4])), 1, 0);
        printf("click refused row 4: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        key(w, NSDownArrowFunctionKey, 0);
        printf("down: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        key(w, NSDownArrowFunctionKey, 0);
        printf("down past the refused row: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        key(w, NSUpArrowFunctionKey, NSEventModifierFlagShift);
        key(w, NSUpArrowFunctionKey, NSEventModifierFlagShift);
        printf("shift-up twice: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        [files dump:"  log"];
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:1])), 2, 0);
        printf("double click: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        [files dump:"  log"];
        files.frozen = YES;
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:5])), 1, 0);
        key(w, NSUpArrowFunctionKey, 0);
        printf("while the delegate says no: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        files.frozen = NO;
        files.refused = -1;
        [files.log removeAllObjects];
        [tv selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)] byExtendingSelection:NO];
        [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:5] byExtendingSelection:YES];
        printf("by code: %s, row 5 selected %d\n", [rows([tv selectedRowIndexes]) UTF8String], [tv isRowSelected:5]);
        [tv deselectRow:2];
        [tv setAllowsEmptySelection:NO];
        [tv deselectAll:nil];
        printf("no empty selection: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        [tv setAllowsEmptySelection:YES];
        [tv deselectAll:nil];
        printf("deselected: %s, selected row %ld\n", [rows([tv selectedRowIndexes]) UTF8String], (long)[tv selectedRow]);
        [files dump:"  log"];
        [tv setAllowsMultipleSelection:NO];
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:1])), 1, 0);
        click(w, tv, NSMakePoint(20, NSMidY([tv rectOfRow:3])), 1, NSEventModifierFlagShift);
        printf("single selection, shift-click: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        [tv setAllowsMultipleSelection:YES];
        click(w, tv, NSMakePoint(5, [tv rectOfRow:5].origin.y + 60), 1, 0);
        printf("click below the rows: %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        [files.log removeAllObjects];

        /* a check box column */
        NSRect checkCell = [tv frameOfCellAtColumn:2 row:0];
        click(w, tv, NSMakePoint(NSMidX(checkCell), NSMidY(checkCell)), 1, 0);
        printf("check box row 0 now %ld\n", (long)[[tv preparedCellAtColumn:2 row:0] state]);
        [files dump:"  log"];

        /* ---- sorting from the header ---- */
        NSTableHeaderView *header = [tv headerView];
        NSRect nameHeader = [header headerRectOfColumn:0], sizeHeader = [header headerRectOfColumn:1];
        rect("name header", nameHeader);
        click(w, header, NSMakePoint(NSMidX(nameHeader), 14), 1, 0);
        printf("sorted: %s\n", [[files names] UTF8String]);
        [files dump:"  log"];
        click(w, header, NSMakePoint(NSMidX(nameHeader), 14), 1, 0);
        printf("again: %s\n", [[files names] UTF8String]);
        click(w, header, NSMakePoint(NSMidX(sizeHeader), 14), 1, 0);
        printf("by size: %s\n", [[files names] UTF8String]);
        [files dump:"  log"];
        printf("sort descriptors: %lu, first %s %s\n", (unsigned long)[[tv sortDescriptors] count],
               [[[[tv sortDescriptors] firstObject] key] UTF8String],
               [[[tv sortDescriptors] firstObject] ascending] ? "ascending" : "descending");
        click(w, header, NSMakePoint(NSMidX([header headerRectOfColumn:2]), 14), 1, 0);
        printf("a column with no prototype: %lu descriptors\n", (unsigned long)[[tv sortDescriptors] count]);
        [files dump:"  log"];
        draw([w contentView]);

        /* ---- resizing columns ---- */
        printf("widths: %.0f %.0f %.0f\n", [name width], [size width], [done width]);
        CGFloat divider = NSMaxX([header headerRectOfColumn:0]) - 1;
        drag(w, header, NSMakePoint(divider, 14), NSMakePoint(divider + 30, 14));
        printf("divider dragged 30 right, last column only: %.0f %.0f %.0f, table %.0f wide\n", [name width],
               [size width], [done width], [tv frame].size.width);
        [files.log removeAllObjects];
        [tv setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
        divider = NSMaxX([header headerRectOfColumn:1]) - 1;
        drag(w, header, NSMakePoint(divider, 14), NSMakePoint(divider + 300, 14));
        printf("dragged past the size column's maximum, no autoresizing: %.0f %.0f %.0f, table %.0f wide\n",
               [name width], [size width], [done width], [tv frame].size.width);
        [size setWidth:80];
        [tv setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
        [scroll setFrameSize:NSMakeSize(380, 200)];
        printf("scroll view wider, uniform: %.0f %.0f %.0f, sum %.0f, clip %.0f\n", [name width], [size width],
               [done width], [name width] + [size width] + [done width] + 9, [[scroll contentView] frame].size.width);
        [done setHidden:YES];
        [tv sizeLastColumnToFit];
        printf("done hidden, last column sized to fit: size %.0f, column 2 %.0f wide\n", [size width],
               [tv rectOfColumn:2].size.width);
        [done setHidden:NO];
        [tv setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
        [tv sizeLastColumnToFit];

        /* ---- rows changing ---- */
        [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
        [files.log removeAllObjects];
        [files.files insertObject:[@{@"name" : @"new.txt", @"size" : @1, @"done" : @0} mutableCopy] atIndex:0];
        [tv beginUpdates];
        [tv insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:0] withAnimation:NSTableViewAnimationSlideDown];
        [tv endUpdates];
        printf("inserted at 0: rows %ld, selection %s\n", (long)[tv numberOfRows], [rows([tv selectedRowIndexes]) UTF8String]);
        [files.files removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
        [tv removeRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withAnimation:NSTableViewAnimationEffectFade];
        printf("removed 0 and 1: rows %ld, selection %s\n", (long)[tv numberOfRows], [rows([tv selectedRowIndexes]) UTF8String]);
        [files dump:"  log"];
        [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
        [files.log removeAllObjects];
        [files.files removeLastObject];
        [tv noteNumberOfRowsChanged];
        printf("last row gone: rows %ld, selection %s\n", (long)[tv numberOfRows], [rows([tv selectedRowIndexes]) UTF8String]);
        [files dump:"  log"];
        for (int i = 0; i < 30; i++)
            [files.files addObject:[@{@"name" : [NSString stringWithFormat:@"more%02d", i], @"size" : @(i), @"done" : @0} mutableCopy]];
        [tv reloadData];
        [tv scrollRowToVisible:30];
        NSRect visible = [tv visibleRect];
        printf("scrolled to row 30: rows %ld to %ld in sight, table %.0f tall\n",
               (long)[tv rowAtPoint:NSMakePoint(5, NSMinY(visible))],
               (long)[tv rowAtPoint:NSMakePoint(5, NSMaxY(visible) - 1)], [tv frame].size.height);
        [tv scrollRowToVisible:0];
        printf("back to the top: clip at %.0f\n", [[scroll contentView] bounds].origin.y);

        /* ---- a view-based table ---- */
        Numbers *numbers = [[Numbers alloc] init];
        NSScrollView *scroll2 = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
        NSTableView *vt = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        [vt addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"a"]];
        [vt addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"b"]];
        [vt setHeaderView:nil];
        [vt setDelegate:numbers];
        [vt setDataSource:numbers];
        [scroll2 setDocumentView:vt];
        [[w contentView] addSubview:scroll2];
        printf("view based: header %s, clip %.0f tall\n", some([vt headerView]), [[scroll2 contentView] frame].size.height);
        __block NSInteger available = 0;
        [vt enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rv, NSInteger row) { available++; }];
        printf("row views %ld, cell views asked %ld, made %ld\n", (long)available, (long)numbers.asked, (long)numbers.made);
        NSTableCellView *cv = [vt viewAtColumn:1 row:2 makeIfNecessary:NO];
        printf("view at 1,2: %s \"%s\", row %ld, column %ld, row view %s\n", [NSStringFromClass([cv class]) UTF8String],
               [[[cv textField] stringValue] UTF8String], (long)[vt rowForView:[cv textField]], (long)[vt columnForView:cv],
               [NSStringFromClass([[cv superview] class]) UTF8String]);
        rect("its frame", [cv frame]);
        rect("row view 2", [[vt rowViewAtRow:2 makeIfNecessary:NO] frame]);
        printf("row 40 before scrolling: %s\n", some([vt viewAtColumn:0 row:40 makeIfNecessary:NO]));
        [vt scrollRowToVisible:40];
        available = 0;
        [vt enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rv, NSInteger row) { available++; }];
        cv = [vt viewAtColumn:0 row:40 makeIfNecessary:NO];
        printf("scrolled to 40: \"%s\", row views %ld, asked %ld, made %ld (the rest reused)\n",
               [[[cv textField] stringValue] UTF8String], (long)available, (long)numbers.asked, (long)numbers.made);
        printf("row 2 now: %s\n", some([vt viewAtColumn:0 row:2 makeIfNecessary:NO]));
        cv = [vt viewAtColumn:0 row:2 makeIfNecessary:YES];
        printf("made for row 2: \"%s\"\n", [[[cv textField] stringValue] UTF8String]);
        [w makeFirstResponder:vt];
        [vt selectRowIndexes:[NSIndexSet indexSetWithIndex:40] byExtendingSelection:NO];
        NSTableRowView *rv = [vt rowViewAtRow:40 makeIfNecessary:NO];
        cv = [vt viewAtColumn:0 row:40 makeIfNecessary:NO];
        printf("row 40 selected: row view selected %d, emphasized %d, cell view style %ld, label style %ld\n",
               [rv isSelected], [rv isEmphasized], (long)[cv backgroundStyle], (long)[[[cv textField] cell] backgroundStyle]);
        printf("row 39's row view knows: next selected %d, previous %d; row 41 has none: %s\n",
               [[vt rowViewAtRow:39 makeIfNecessary:NO] isNextRowSelected],
               [[vt rowViewAtRow:39 makeIfNecessary:NO] isPreviousRowSelected], some([vt rowViewAtRow:41 makeIfNecessary:NO]));
        click(w, vt, NSMakePoint(50, NSMidY([vt rectOfRow:39])), 1, 0);
        printf("clicked the label in row 39: %s\n", [rows([vt selectedRowIndexes]) UTF8String]);
        NSInteger asked = numbers.asked;
        [vt reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:39] columnIndexes:[NSIndexSet indexSetWithIndex:1]];
        printf("reloaded one cell: asked %ld more\n", (long)(numbers.asked - asked));
        draw(scroll2);

        /* ---- an outline view ---- */
        Tree *tree = [[Tree alloc] init];
        NSScrollView *scroll3 = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 220, 200)];
        NSOutlineView *ov = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 220, 200)];
        NSTableColumn *treeColumn = [[NSTableColumn alloc] initWithIdentifier:@"tree"];
        [ov addTableColumn:treeColumn];
        [ov setOutlineTableColumn:treeColumn];
        [ov setIndentationPerLevel:14];
        [ov setAllowsMultipleSelection:YES];
        [ov setDelegate:tree];
        [ov setDataSource:tree];
        [scroll3 setDocumentView:ov];
        [[w contentView] addSubview:scroll3];
        Node *fruit = tree.top[0], *veg = tree.top[1], *rock = tree.top[2];
        Node *pear = fruit.children[1], *kale = veg.children[0], *leek = veg.children[1];
        show_rows("outline", ov);
        printf("expandable: fruit %d, rock %d; fruit open %d\n", [ov isExpandable:fruit], [ov isExpandable:rock],
               [ov isItemExpanded:fruit]);
        [ov expandItem:fruit];
        show_rows("fruit opened", ov);
        [tree dump:"  log"];
        printf("pear: row %ld, level %ld, parent %s, child index %ld; row 1 is %s\n", (long)[ov rowForItem:pear],
               (long)[ov levelForItem:pear], [[[ov parentForItem:pear] name] UTF8String], (long)[ov childIndexForItem:pear],
               [[[ov itemAtRow:1] name] UTF8String]);
        printf("fruit's parent %s, level %ld; rock's row %ld\n", some([ov parentForItem:fruit]),
               (long)[ov levelForItem:fruit], (long)[ov rowForItem:rock]);
        rect("cell of pear", [ov frameOfCellAtColumn:0 row:[ov rowForItem:pear]]);
        rect("cell of fruit", [ov frameOfCellAtColumn:0 row:0]);
        rect("fruit's chevron", [ov frameOfOutlineCellAtRow:0]);
        rect("pear's chevron (none)", [ov frameOfOutlineCellAtRow:[ov rowForItem:pear]]);
        [ov expandItem:veg expandChildren:YES];
        show_rows("veg opened with its children (leek refused)", ov);
        [tree dump:"  log"];
        tree.lockLeek = NO;
        [ov expandItem:leek];
        show_rows("leek opened", ov);
        printf("baby leek: level %ld, parent %s\n", (long)[ov levelForItem:leek.children[0]],
               [[[ov parentForItem:leek.children[0]] name] UTF8String]);
        [tree.log removeAllObjects];
        [ov selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[ov rowForItem:kale]] byExtendingSelection:NO];
        [tree dump:"  selecting kale"];
        [ov collapseItem:fruit];
        printf("fruit closed: kale at row %ld, selection %s\n", (long)[ov rowForItem:kale],
               [rows([ov selectedRowIndexes]) UTF8String]);
        [tree dump:"  log"];
        [ov collapseItem:veg];
        show_rows("veg closed", ov);
        printf("kale hidden: row %ld, selection %s, leek still open %d\n", (long)[ov rowForItem:kale],
               [rows([ov selectedRowIndexes]) UTF8String], [ov isItemExpanded:leek]);
        [tree dump:"  log"];

        /* by the keyboard and the chevrons */
        [w makeFirstResponder:ov];
        [ov selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [tree.log removeAllObjects];
        key(w, NSRightArrowFunctionKey, 0);
        show_rows("right arrow on fruit", ov);
        key(w, NSDownArrowFunctionKey, 0);
        printf("down: %s\n", [[[ov itemAtRow:[ov selectedRow]] name] UTF8String]);
        key(w, NSLeftArrowFunctionKey, 0);
        printf("left on a leaf: selected %s\n", [[[ov itemAtRow:[ov selectedRow]] name] UTF8String]);
        key(w, NSLeftArrowFunctionKey, 0);
        show_rows("left on fruit", ov);
        [tree dump:"  log"];
        NSInteger vegRow = [ov rowForItem:veg];
        NSRect chevron = [ov frameOfOutlineCellAtRow:vegRow];
        click(w, ov, NSMakePoint(NSMidX(chevron), NSMidY(chevron)), 1, 0);
        show_rows("chevron clicked", ov);
        printf("selection after the chevron click: %s\n", [rows([ov selectedRowIndexes]) UTF8String]);
        click(w, ov, NSMakePoint(NSMidX(chevron), NSMidY(chevron)), 1, 0);
        show_rows("clicked again", ov);
        [tree dump:"  log"];
        [ov expandItem:fruit];
        [fruit.children addObject:[Node node:@"Plum" children:nil]];
        [ov reloadItem:fruit reloadChildren:YES];
        show_rows("plum added", ov);
        [ov expandItem:nil expandChildren:YES];
        show_rows("everything opened", ov);
        [ov collapseItem:nil collapseChildren:YES];
        show_rows("everything closed", ov);
        [ov expandItem:fruit];
        [ov reloadData];
        show_rows("reloaded, fruit kept open", ov);
        draw(scroll3);

        /* ---- from a nib ---- */
        NSString *path = [NSString stringWithFormat:@"%s/Tables.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        TablesOwner *owner = [[TablesOwner alloc] init];
        NSArray *top = nil;
        printf("nib loaded: %d\n", [nib instantiateWithOwner:owner topLevelObjects:&top]);
        NSTableView *nt = owner.table;
        printf("classes: %s, %s; data source and delegate set %d\n", [NSStringFromClass([nt class]) UTF8String],
               [NSStringFromClass([owner.outline class]) UTF8String],
               [nt dataSource] == (id)owner && [nt delegate] == (id)owner);
        for (NSTableColumn *c in [nt tableColumns])
            printf("column %s \"%s\": width %.0f (%.0f to %.0f), resizing %lu, editable %d, hidden %d, sorts by %s, table %d\n",
                   [[c identifier] UTF8String], [[c title] UTF8String], [c width], [c minWidth], [c maxWidth],
                   (unsigned long)[c resizingMask], [c isEditable], [c isHidden],
                   [[[c sortDescriptorPrototype] key] UTF8String], [c tableView] == nt);
        printf("row height %.0f, spacing %.0fx%.0f, multiple %d, empty %d, alternating %d, resizing %d, "
               "autoresizing %lu, type select %d\n",
               [nt rowHeight], [nt intercellSpacing].width, [nt intercellSpacing].height, [nt allowsMultipleSelection],
               [nt allowsEmptySelection], [nt usesAlternatingRowBackgroundColors], [nt allowsColumnResizing],
               (unsigned long)[nt columnAutoresizingStyle], [nt allowsTypeSelect]);
        printf("header %s for the table %d, corner %s\n", [NSStringFromClass([[nt headerView] class]) UTF8String],
               [[nt headerView] tableView] == nt, [NSStringFromClass([[nt cornerView] class]) UTF8String]);
        rect("header clip", [[[nt headerView] superview] frame]);
        rect("content clip", [[[nt enclosingScrollView] contentView] frame]);
        printf("prototypes: %s\n", [[[[nt registeredNibsByIdentifier] allKeys] componentsJoinedByString:@","] UTF8String]);
        NSTableCellView *proto = [nt makeViewWithIdentifier:@"NameCell" owner:owner];
        printf("made from the prototype: %s \"%s\", identifier %s, text field %s\n",
               [NSStringFromClass([proto class]) UTF8String], [[[proto textField] stringValue] UTF8String],
               [[proto identifier] UTF8String], [NSStringFromClass([[proto textField] class]) UTF8String]);
        printf("unknown identifier: %s\n", some([nt makeViewWithIdentifier:@"Nope" owner:owner]));
        [[w contentView] addSubview:owner.view];
        NSTableCellView *shown0 = [nt viewAtColumn:0 row:1 makeIfNecessary:YES];
        printf("row 1: \"%s\"; size column view %s\n", [[[shown0 textField] stringValue] UTF8String],
               some([nt viewAtColumn:1 row:1 makeIfNecessary:YES]));
        printf("widths, uniform in a %.0f clip: %.0f %.0f\n", [[[nt enclosingScrollView] contentView] frame].size.width,
               [[nt tableColumns][0] width], [[nt tableColumns][1] width]);
        NSOutlineView *no = owner.outline;
        printf("outline: indentation %.0f, outline column %s, rows %ld\n", [no indentationPerLevel],
               [[[no outlineTableColumn] identifier] UTF8String], (long)[no numberOfRows]);
        [no expandItem:[no itemAtRow:1]];
        show_rows("nib outline, veg opened", no);
        draw(owner.view);
    }
    return 0;
}
