/* SPDX-License-Identifier: GPL-3.0-or-later
 * Editing cells in place, with no display: in a cell-based table (a double
 * click, Return on the selected row and editColumn:row:withEvent:select:
 * start it; the data source gets the new value, the delegate is asked
 * whether a cell may be edited and whether editing may end, and hears
 * controlTextDidBeginEditing: and controlTextDidEndEditing: with the
 * NSTextMovement; Tab and Shift-Tab move between editable cells, Escape
 * gives up, a click elsewhere or reloadData ends it), in a view-based
 * table (the cell view's own text field is edited and its action sent) and
 * in an outline view (the value goes back by item). */
#import <Cocoa/Cocoa.h>

static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p, NSInteger clicks)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:clicks pressure:1];
}
static void click(NSWindow *w, NSView *v, NSPoint p, NSInteger clicks)
{
    for (NSInteger c = 1; c <= clicks; c++) {
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, p, c)];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, p, c)];
    }
}
static NSPoint cell(NSTableView *tv, NSInteger column, NSInteger row)
{
    NSRect f = [tv frameOfCellAtColumn:column row:row];
    return NSMakePoint(NSMidX(f), NSMidY(f));
}
static void key(NSWindow *w, unichar c, NSEventModifierFlags flags)
{
    NSString *s = [NSString stringWithFormat:@"%C", c];
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}
static void type(NSWindow *w, NSString *s)
{
    for (NSUInteger i = 0; i < [s length]; i++)
        key(w, [s characterAtIndex:i], 0);
}
static const char *movement(NSNotification *n)
{
    switch ([[[n userInfo] objectForKey:@"NSTextMovement"] integerValue]) {
    case NSTextMovementReturn: return "return";
    case NSTextMovementTab: return "tab";
    case NSTextMovementBacktab: return "backtab";
    case NSTextMovementCancel: return "cancel";
    case NSTextMovementOther: return "other";
    default: return "?";
    }
}
static NSString *responder(NSWindow *w, NSTableView *tv)
{
    id r = [w firstResponder];
    if (r == tv)
        return @"the table";
    if ([r isKindOfClass:[NSTextField class]])
        return [NSString stringWithFormat:@"a text field holding \"%@\"", [r stringValue]];
    return r ? NSStringFromClass([r class]) : @"nothing";
}

/* ---- a cell-based table ---- */

@interface People : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSMutableArray *people;
@property (strong) NSMutableArray *log;
@property BOOL refuseEmpty, reloadOnSet;
@end
@implementation People
- (instancetype)init
{
    if ((self = [super init])) {
        _log = [NSMutableArray array];
        _people = [NSMutableArray array];
        NSArray *names = @[ @"Ada", @"Bob", @"Cy", @"Di" ];
        NSArray *ages = @[ @"36", @"41", @"29", @"52" ];
        for (NSUInteger i = 0; i < [names count]; i++)
            [_people addObject:[@{@"id" : @(i + 1), @"name" : names[i], @"age" : ages[i]} mutableCopy]];
    }
    return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)[_people count]; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return _people[(NSUInteger)row][[c identifier]];
}
- (void)tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    [_log addObject:[NSString stringWithFormat:@"set %@ of row %ld to %@ (%@)", [c identifier], (long)row, v,
                                               [v isKindOfClass:[NSString class]] ? @"a string" : @"not a string"]];
    _people[(NSUInteger)row][[c identifier]] = v;
    if (_reloadOnSet)
        [tv reloadData];
}
- (BOOL)tableView:(NSTableView *)tv shouldEditTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    BOOL ok = !(row == 2 && [[c identifier] isEqualToString:@"age"]);
    [_log addObject:[NSString stringWithFormat:@"may edit %@ of row %ld? %s", [c identifier], (long)row, ok ? "yes" : "no"]];
    return ok;
}
- (BOOL)control:(NSControl *)control textShouldEndEditing:(id)editor
{
    NSTableView *tv = (NSTableView *)control;
    NSTextField *f = (NSTextField *)[[tv window] firstResponder];
    BOOL ok = !(_refuseEmpty && [[f stringValue] length] == 0);
    [_log addObject:[NSString stringWithFormat:@"may end editing? %s (control is the table: %d)", ok ? "yes" : "no",
                                               control == (id)tv && [tv isKindOfClass:[NSTableView class]]]];
    return ok;
}
- (void)controlTextDidBeginEditing:(NSNotification *)n
{
    [_log addObject:[NSString stringWithFormat:@"began editing (object is a table: %d)",
                                               [[n object] isKindOfClass:[NSTableView class]]]];
}
- (void)controlTextDidEndEditing:(NSNotification *)n
{
    NSTableView *tv = [n object];
    [_log addObject:[NSString stringWithFormat:@"ended editing by %s, edited row %ld column %ld", movement(n),
                                               (long)[tv editedRow], (long)[tv editedColumn]]];
}
- (void)doubleClicked:(NSTableView *)tv
{
    [_log addObject:[NSString stringWithFormat:@"double click on row %ld column %ld", (long)[tv clickedRow],
                                               (long)[tv clickedColumn]]];
}
- (void)dump
{
    for (NSString *s in _log)
        printf("  %s\n", [s UTF8String]);
    [_log removeAllObjects];
}
@end

/* ---- a view-based table ---- */

@interface Notes : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (strong) NSMutableArray *notes;
@property (strong) NSMutableArray *log;
@property (weak) NSTableView *table;
@end
@implementation Notes
- (instancetype)init
{
    if ((self = [super init])) {
        _log = [NSMutableArray array];
        _notes = [@[ @"milk", @"eggs", @"tea" ] mutableCopy];
    }
    return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)[_notes count]; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    NSTableCellView *v = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
    if ([[c identifier] isEqualToString:@"note"]) {
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
        [f setBezeled:NO];
        [f setDrawsBackground:NO];
        [f setStringValue:_notes[(NSUInteger)row]];
        [f setTarget:self];
        [f setAction:@selector(noteEdited:)];
        [f setDelegate:self];
        [v addSubview:f];
        [v setTextField:f];
    } else {
        NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"#%ld", (long)row + 1]];
        [v addSubview:label];
        [v setTextField:label];
    }
    return v;
}
- (void)noteEdited:(NSTextField *)f
{
    NSInteger row = [_table rowForView:f];
    [_log addObject:[NSString stringWithFormat:@"action: row %ld is now \"%@\"", (long)row, [f stringValue]]];
    if (row >= 0)
        _notes[(NSUInteger)row] = [f stringValue];
}
- (void)controlTextDidEndEditing:(NSNotification *)n
{
    [_log addObject:[NSString stringWithFormat:@"the field ended editing by %s (object is the field: %d)", movement(n),
                                               [[n object] isKindOfClass:[NSTextField class]]]];
}
- (void)dump
{
    for (NSString *s in _log)
        printf("  %s\n", [s UTF8String]);
    [_log removeAllObjects];
}
@end

/* ---- an outline view ---- */

@interface Places : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (strong) NSMutableDictionary *tree;
@property (strong) NSMutableArray *log;
@end
@implementation Places
- (instancetype)init
{
    if ((self = [super init])) {
        _log = [NSMutableArray array];
        _tree = [@{@"Europe" : [@[ @"Paris", @"Rome" ] mutableCopy]} mutableCopy];
    }
    return self;
}
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    return item ? (NSInteger)[_tree[item] count] : 1;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(id)item
{
    return item ? _tree[item][(NSUInteger)i] : @"Europe";
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item { return _tree[item] != nil; }
- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)c byItem:(id)item { return item; }
- (void)outlineView:(NSOutlineView *)ov setObjectValue:(id)v forTableColumn:(NSTableColumn *)c byItem:(id)item
{
    [_log addObject:[NSString stringWithFormat:@"set item %@ to %@", item, v]];
}
- (BOOL)outlineView:(NSOutlineView *)ov shouldEditTableColumn:(NSTableColumn *)c item:(id)item
{
    BOOL ok = _tree[item] == nil;
    [_log addObject:[NSString stringWithFormat:@"may edit item %@? %s", item, ok ? "yes" : "no"]];
    return ok;
}
- (void)dump
{
    for (NSString *s in _log)
        printf("  %s\n", [s UTF8String]);
    [_log removeAllObjects];
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 300) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];

        /* ---- a cell-based table ---- */
        People *people = [[People alloc] init];
        NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(10, 10, 300, 120)];
        for (NSString *ident in @[ @"id", @"name", @"age" ]) {
            NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:ident];
            [c setWidth:90];
            [c setEditable:![ident isEqualToString:@"id"]];
            [tv addTableColumn:c];
        }
        [tv setDataSource:people];
        [tv setDelegate:people];
        [tv setTarget:people];
        [tv setDoubleAction:@selector(doubleClicked:)];
        [[w contentView] addSubview:tv];
        printf("cell-based: edited row %ld column %ld\n", (long)[tv editedRow], (long)[tv editedColumn]);

        click(w, tv, cell(tv, 1, 0), 2);
        printf("double click on Ada: edited row %ld column %ld, first responder %s, in the table %d\n",
               (long)[tv editedRow], (long)[tv editedColumn], [responder(w, tv) UTF8String],
               [(NSView *)[w firstResponder] superview] == tv);
        NSRect ef = [(NSView *)[w firstResponder] frame], cf = [tv frameOfCellAtColumn:1 row:0];
        printf("  the field lies over the cell: %d\n", NSEqualRects(ef, cf));
        NSBitmapImageRep *rep = [tv bitmapImageRepForCachingDisplayInRect:[tv bounds]];
        [tv cacheDisplayInRect:[tv bounds] toBitmapImageRep:rep];   /* drawn with the field over the cell */
        [people dump];
        type(w, @"Ann");
        key(w, '\r', 0);
        printf("typed Ann, Return: edited row %ld, first responder %s, name %s\n", (long)[tv editedRow],
               [responder(w, tv) UTF8String], [people.people[0][@"name"] UTF8String]);
        [people dump];

        key(w, '\r', 0);
        printf("Return on the row: edited row %ld column %ld, first responder %s\n", (long)[tv editedRow],
               (long)[tv editedColumn], [responder(w, tv) UTF8String]);
        key(w, '\t', 0);
        printf("Tab: edited row %ld column %ld, first responder %s\n", (long)[tv editedRow], (long)[tv editedColumn],
               [responder(w, tv) UTF8String]);
        type(w, @"37");
        key(w, '\t', 0);
        printf("typed 37, Tab: edited row %ld column %ld, selected row %ld, first responder %s\n", (long)[tv editedRow],
               (long)[tv editedColumn], (long)[tv selectedRow], [responder(w, tv) UTF8String]);
        key(w, '\t', NSEventModifierFlagShift);
        printf("Shift-Tab: edited row %ld column %ld, selected row %ld\n", (long)[tv editedRow], (long)[tv editedColumn],
               (long)[tv selectedRow]);
        type(w, @"99");
        key(w, 0x1b, 0);
        printf("typed 99, Escape: edited row %ld, age %s, first responder %s\n", (long)[tv editedRow],
               [people.people[0][@"age"] UTF8String], [responder(w, tv) UTF8String]);
        [people dump];

        /* cells that aren't edited */
        click(w, tv, cell(tv, 2, 2), 2);
        printf("double click on an age the delegate keeps: edited row %ld\n", (long)[tv editedRow]);
        click(w, tv, cell(tv, 0, 3), 2);
        printf("double click on a column that isn't editable: edited row %ld\n", (long)[tv editedRow]);
        [people dump];

        /* the delegate keeps the editing going */
        click(w, tv, cell(tv, 1, 1), 2);
        people.refuseEmpty = YES;
        key(w, NSDeleteCharacter, 0);
        key(w, '\r', 0);
        printf("emptied, Return: edited row %ld column %ld, first responder %s\n", (long)[tv editedRow],
               (long)[tv editedColumn], [responder(w, tv) UTF8String]);
        type(w, @"Bo");
        key(w, '\r', 0);
        printf("typed Bo, Return: edited row %ld, name %s\n", (long)[tv editedRow], [people.people[1][@"name"] UTF8String]);
        people.refuseEmpty = NO;
        [people dump];

        /* by code */
        @try {
            [tv editColumn:1 row:3 withEvent:nil select:YES];
            printf("editing a row that isn't selected: no exception\n");
        } @catch (NSException *e) {
            printf("editing a row that isn't selected: %s\n", [[e name] UTF8String]);
        }
        [tv editColumn:1 row:1 withEvent:nil select:NO];
        type(w, @"!");
        printf("editColumn:1 row:1 select:NO, typed !: field holds %s\n", [[(NSTextField *)[w firstResponder] stringValue] UTF8String]);
        click(w, tv, cell(tv, 0, 3), 1);
        printf("clicked row 3: edited row %ld, name %s, selected row %ld\n", (long)[tv editedRow],
               [people.people[1][@"name"] UTF8String], (long)[tv selectedRow]);
        [people dump];
        [tv editColumn:2 row:3 withEvent:nil select:YES];
        type(w, @"60");
        [tv reloadData];
        printf("reloadData while editing: edited row %ld, age %s, first responder %s\n", (long)[tv editedRow],
               [people.people[3][@"age"] UTF8String], [responder(w, tv) UTF8String]);
        [tv editColumn:2 row:3 withEvent:nil select:YES];
        type(w, @"61");
        key(w, '\t', 0);
        printf("Tab from the last cell: edited row %ld, age %s, first responder %s\n", (long)[tv editedRow],
               [people.people[3][@"age"] UTF8String], [responder(w, tv) UTF8String]);
        people.reloadOnSet = YES;
        key(w, '\r', 0);
        type(w, @"Dot");
        key(w, '\r', 0);
        printf("a data source that reloads as it takes the value: edited row %ld, name %s\n", (long)[tv editedRow],
               [people.people[3][@"name"] UTF8String]);
        people.reloadOnSet = NO;
        [tv editColumn:1 row:3 withEvent:nil select:YES];
        printf("abortEditing: %d, then %d; edited row %ld\n", [tv abortEditing], [tv abortEditing], (long)[tv editedRow]);
        [people dump];
        [tv removeFromSuperview];

        /* ---- a view-based table ---- */
        Notes *notes = [[Notes alloc] init];
        NSTableView *vt = [[NSTableView alloc] initWithFrame:NSMakeRect(10, 10, 300, 120)];
        notes.table = vt;
        for (NSString *ident in @[ @"number", @"note" ]) {
            NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:ident];
            [c setWidth:120];
            [vt addTableColumn:c];
        }
        [vt setDataSource:notes];
        [vt setDelegate:notes];
        [[w contentView] addSubview:vt];
        NSTextField *field1 = [[vt viewAtColumn:1 row:1 makeIfNecessary:NO] textField];
        printf("view-based: a click on the note field goes to %s\n",
               [vt hitTest:[[vt superview] convertPoint:cell(vt, 1, 1) fromView:vt]] == vt ? "the table" : "the field");
        click(w, vt, cell(vt, 1, 1), 2);
        printf("double click on eggs: edited row %ld column %ld, first responder is the cell's field %d\n",
               (long)[vt editedRow], (long)[vt editedColumn], [w firstResponder] == field1);
        printf("  and a click on it now goes to %s\n",
               [vt hitTest:[[vt superview] convertPoint:cell(vt, 1, 1) fromView:vt]] == field1 ? "the field" : "the table");
        type(w, @"ham");
        key(w, '\r', 0);
        printf("typed ham, Return: edited row %ld, field %s, first responder %s\n", (long)[vt editedRow],
               [[field1 stringValue] UTF8String], [responder(w, vt) UTF8String]);
        [notes dump];
        key(w, '\r', 0);
        type(w, @"jam");
        key(w, 0x1b, 0);
        printf("Return, typed jam, Escape: field %s, edited row %ld\n", [[field1 stringValue] UTF8String], (long)[vt editedRow]);
        [notes dump];
        key(w, '\r', 0);
        key(w, '\t', 0);
        printf("Return, Tab: edited row %ld column %ld, selected row %ld, first responder %s\n", (long)[vt editedRow],
               (long)[vt editedColumn], (long)[vt selectedRow], [responder(w, vt) UTF8String]);
        key(w, '\t', NSEventModifierFlagShift);
        printf("Shift-Tab: edited row %ld, selected row %ld\n", (long)[vt editedRow], (long)[vt selectedRow]);
        key(w, 0x1b, 0);
        [notes dump];
        [vt removeFromSuperview];

        /* ---- an outline view ---- */
        Places *places = [[Places alloc] init];
        NSOutlineView *ov = [[NSOutlineView alloc] initWithFrame:NSMakeRect(10, 10, 300, 120)];
        NSTableColumn *place = [[NSTableColumn alloc] initWithIdentifier:@"place"];
        [place setWidth:200];
        [ov addTableColumn:place];
        [ov setOutlineTableColumn:place];
        [ov setDataSource:places];
        [ov setDelegate:places];
        [[w contentView] addSubview:ov];
        [ov expandItem:@"Europe"];
        click(w, ov, cell(ov, 0, 0), 2);
        printf("outline: double click on Europe: edited row %ld\n", (long)[ov editedRow]);
        click(w, ov, cell(ov, 0, 2), 2);
        printf("double click on Rome: edited row %ld, first responder %s\n", (long)[ov editedRow],
               [responder(w, ov) UTF8String]);
        type(w, @"Roma");
        key(w, '\r', 0);
        printf("typed Roma, Return: edited row %ld\n", (long)[ov editedRow]);
        [places dump];
    }
    return 0;
}
