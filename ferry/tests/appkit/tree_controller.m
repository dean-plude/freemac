/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSTreeController, NSTreeNode, NSIndexPath and NSDictionaryController
 * (Ferry 0.19.0), with no display. Index paths; tree nodes on their own
 * (children through mutableChildNodes, parents, index paths, sorting);
 * a tree controller over objects with children, leaf and count key paths,
 * its arranged tree of nodes, the selection by index paths and
 * "selection.key", sorting level by level, the model changing its children,
 * inserting, removing and moving, the add:, insert:, addChild:,
 * insertChild: and remove: actions on the run loop's next turn, the
 * contentArray and selectionIndexPaths bindings, and dictionaries as
 * objects. Then an outline view bound to a tree controller: its items, its
 * rows opened and closed, the selection both ways, sorting by a click on a
 * column's title, a cell edited in place written back, a child added
 * through the controller, and no edits taken when the controller isn't
 * editable. Then a table's per-row editable and enabled column bindings,
 * and a dictionary controller. */
#import <Cocoa/Cocoa.h>

static const char *str(id v) { return v ? [[v description] UTF8String] : "nil"; }
static NSString *path(NSIndexPath *p)
{
    if (!p)
        return @"nil";
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < [p length]; i++)
        [a addObject:[NSString stringWithFormat:@"%lu", (unsigned long)[p indexAtPosition:i]]];
    return [NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@"."]];
}
static NSString *paths(NSArray *ps)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSIndexPath *p in ps)
        [a addObject:path(p)];
    return [NSString stringWithFormat:@"{%@}", [a componentsJoinedByString:@","]];
}
static NSIndexPath *P(NSUInteger a, NSInteger b, NSInteger c)
{
    NSUInteger i[3] = {a, (NSUInteger)b, (NSUInteger)c};
    return [NSIndexPath indexPathWithIndexes:i length:b < 0 ? 1 : c < 0 ? 2 : 3];
}
static NSString *rows(NSIndexSet *set)
{
    NSMutableArray *a = [NSMutableArray array];
    [set enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [a addObject:[NSString stringWithFormat:@"%lu", (unsigned long)i]]; }];
    return [NSString stringWithFormat:@"{%@}", [a componentsJoinedByString:@","]];
}
static void turn(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }

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
static void key(NSWindow *w, unichar c)
{
    NSString *s = [NSString stringWithFormat:@"%C", c];
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}
static void type(NSWindow *w, NSString *s)
{
    for (NSUInteger i = 0; i < [s length]; i++)
        key(w, [s characterAtIndex:i]);
}

/* A folder (or a file, with no children) that logs what is done to its children. */
@interface Item : NSObject
@property (copy) NSString *name;
@property NSInteger size;
@property BOOL file;
@property BOOL locked;
@property (strong) NSMutableArray *children;
@end
static NSMutableArray *calls;
@implementation Item
+ (instancetype)folder:(NSString *)n size:(NSInteger)s children:(NSArray *)kids
{
    Item *i = [[Item alloc] init];
    i.name = n;
    i.size = s;
    i.children = [NSMutableArray arrayWithArray:kids];
    return i;
}
+ (instancetype)file:(NSString *)n size:(NSInteger)s
{
    Item *i = [[Item alloc] init];
    i.name = n;
    i.size = s;
    i.file = YES;
    return i;
}
- (instancetype)init
{
    if ((self = [super init]))
        _name = @"untitled";
    return self;
}
- (NSUInteger)countOfChildren { return [_children count]; }
- (id)objectInChildrenAtIndex:(NSUInteger)i { return _children[i]; }
- (void)insertObject:(id)o inChildrenAtIndex:(NSUInteger)i
{
    [calls addObject:[NSString stringWithFormat:@"%@: insert %@ at %lu", _name, [o name], (unsigned long)i]];
    if (!_children)
        _children = [NSMutableArray array];
    [_children insertObject:o atIndex:i];
}
- (void)removeObjectFromChildrenAtIndex:(NSUInteger)i
{
    [calls addObject:[NSString stringWithFormat:@"%@: remove %@ at %lu", _name, [_children[i] name], (unsigned long)i]];
    [_children removeObjectAtIndex:i];
}
- (NSUInteger)kidCount { return [_children count]; }
- (NSString *)description { return _name; }
@end

/* Owns the top-level items, with indexed accessors, and a picked selection. */
@interface Disk : NSObject
@property (strong) NSMutableArray *items;
@property (strong) NSArray *picked;
@property (strong) NSDictionary *settings;
@end
@implementation Disk
- (instancetype)init
{
    if ((self = [super init]))
        _items = [NSMutableArray array];
    return self;
}
- (NSUInteger)countOfItems { return [_items count]; }
- (id)objectInItemsAtIndex:(NSUInteger)i { return _items[i]; }
- (void)insertObject:(id)o inItemsAtIndex:(NSUInteger)i
{
    [calls addObject:[NSString stringWithFormat:@"disk: insert %@ at %lu", [o valueForKey:@"name"], (unsigned long)i]];
    [_items insertObject:o atIndex:i];
}
- (void)removeObjectFromItemsAtIndex:(NSUInteger)i
{
    [calls addObject:[NSString stringWithFormat:@"disk: remove %@ at %lu", [_items[i] valueForKey:@"name"], (unsigned long)i]];
    [_items removeObjectAtIndex:i];
}
@end

static void dump_calls(void)
{
    for (NSString *c in calls)
        printf("  model: %s\n", [c UTF8String]);
    if (![calls count])
        printf("  model: nothing\n");
    [calls removeAllObjects];
}

@interface Watcher : NSObject
@property (strong) NSMutableArray *heard;
@end
@implementation Watcher
- (instancetype)init
{
    if ((self = [super init]))
        _heard = [NSMutableArray array];
    return self;
}
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    id v = [object valueForKeyPath:kp];
    NSString *s;
    if ([kp isEqualToString:@"selectionIndexPaths"])
        s = paths(v);
    else if ([kp isEqualToString:@"childNodes"])
        s = [[v valueForKey:@"representedObject"] componentsJoinedByString:@","];
    else if ([v isKindOfClass:[NSArray class]])
        s = [v componentsJoinedByString:@","];
    else
        s = [v description];
    [_heard addObject:[NSString stringWithFormat:@"%@ = %@", kp, s]];
}
- (void)dump:(const char *)what
{
    printf("%s:\n", what);
    for (NSString *s in _heard)
        printf("  heard %s\n", [s UTF8String]);
    if (![_heard count])
        printf("  heard nothing\n");
    [_heard removeAllObjects];
}
@end

static void tree_lines(NSArray *nodes, int depth, NSMutableString *out)
{
    for (NSTreeNode *n in nodes) {
        [out appendFormat:@"%*s%@%@ %@\n", 4 + depth * 2, "", [[n representedObject] valueForKey:@"name"], [n isLeaf] ? @"" : @"/",
                          path([n indexPath])];
        tree_lines([n childNodes], depth + 1, out);
    }
}
static void tree(const char *what, NSTreeController *tc)
{
    NSMutableString *s = [NSMutableString string];
    tree_lines([[tc arrangedObjects] childNodes], 0, s);
    printf("%s: selection %s, selection.name %s\n%s", what, [paths([tc selectionIndexPaths]) UTF8String],
           str([tc valueForKeyPath:@"selection.name"]), [s UTF8String]);
}
static void outline(const char *what, NSOutlineView *ov)
{
    printf("%s: %ld rows, selected %s\n", what, (long)[ov numberOfRows], [rows([ov selectedRowIndexes]) UTF8String]);
    for (NSInteger r = 0; r < [ov numberOfRows]; r++) {
        id item = [ov itemAtRow:r];
        printf("  row %ld: level %ld %s%s", (long)r, (long)[ov levelForRow:r],
               [ov isExpandable:item] ? ([ov isItemExpanded:item] ? "v " : "> ") : "  ",
               [item isKindOfClass:[NSTreeNode class]] ? "" : "(not a node) ");
        for (NSInteger c = 0; c < [ov numberOfColumns]; c++)
            printf(" [%s]", [[[ov preparedCellAtColumn:c row:r] stringValue] UTF8String]);
        printf("\n");
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        calls = [NSMutableArray array];

        /* ---- index paths ---- */
        NSIndexPath *ip = [[NSIndexPath indexPathWithIndex:1] indexPathByAddingIndex:4];
        printf("index path %s: length %lu, at 1 %lu, at 5 %s, removing last %s, empty length %lu\n",
               [path(ip) UTF8String], (unsigned long)[ip length], (unsigned long)[ip indexAtPosition:1],
               [ip indexAtPosition:5] == NSNotFound ? "NSNotFound" : "?", [path([ip indexPathByRemovingLastIndex]) UTF8String],
               (unsigned long)[[[NSIndexPath alloc] init] length]);
        printf("  equal %d, hash equal %d, compare [1.4]/[1] %ld, [1]/[1.4] %ld, [0.9]/[1] %ld, copy is itself %d\n",
               [ip isEqual:P(1, 4, -1)], [ip hash] == [P(1, 4, -1) hash], (long)[ip compare:P(1, -1, -1)],
               (long)[P(1, -1, -1) compare:ip], (long)[P(0, 9, -1) compare:P(1, -1, -1)], [ip copy] == ip);
        NSUInteger buf[2] = {0, 0};
        [ip getIndexes:buf range:NSMakeRange(0, 2)];
        printf("  indexes %lu %lu; description starts %s; item %ld section %ld\n", (unsigned long)buf[0],
               (unsigned long)buf[1], [[[ip description] substringToIndex:13] UTF8String], (long)[ip item], (long)[ip section]);
        printf("  description ends %s\n", [[[ip description] substringFromIndex:[[ip description] rangeOfString:@">"].location]
                                              UTF8String]);
        NSArray *sortedPaths = [@[ P(1, 0, -1), P(0, -1, -1), P(1, -1, -1), P(0, 2, 1) ] sortedArrayUsingSelector:@selector(compare:)];
        printf("  sorted %s\n", [paths(sortedPaths) UTF8String]);

        /* ---- tree nodes on their own ---- */
        NSTreeNode *top = [NSTreeNode treeNodeWithRepresentedObject:@"top"];
        NSTreeNode *b = [NSTreeNode treeNodeWithRepresentedObject:@"b"], *a = [NSTreeNode treeNodeWithRepresentedObject:@"a"];
        NSTreeNode *c = [NSTreeNode treeNodeWithRepresentedObject:@"c"];
        Watcher *nw = [[Watcher alloc] init];
        [top addObserver:nw forKeyPath:@"childNodes" options:0 context:NULL];
        [[top mutableChildNodes] addObject:b];
        [[top mutableChildNodes] addObject:a];
        [[b mutableChildNodes] addObject:c];
        printf("nodes: top leaf %d, b leaf %d, c leaf %d; c's parent %s, path %s, top's path %s\n", [top isLeaf], [b isLeaf],
               [c isLeaf], str([[c parentNode] representedObject]), [path([c indexPath]) UTF8String],
               [path([top indexPath]) UTF8String]);
        printf("  at [0.0] %s, at [1] %s, at [2] %s\n", str([[top descendantNodeAtIndexPath:P(0, 0, -1)] representedObject]),
               str([[top descendantNodeAtIndexPath:P(1, -1, -1)] representedObject]),
               str([top descendantNodeAtIndexPath:P(2, -1, -1)]));
        [top sortWithSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"representedObject" ascending:YES] ]
                         recursively:YES];
        printf("  sorted: %s; b now at %s\n", [[[[top childNodes] valueForKey:@"representedObject"] componentsJoinedByString:@","] UTF8String],
               [path([b indexPath]) UTF8String]);
        [[a mutableChildNodes] addObject:c];
        printf("  c moved under a: b has %lu, a has %lu, c's parent %s\n", (unsigned long)[[b childNodes] count],
               (unsigned long)[[a childNodes] count], str([[c parentNode] representedObject]));
        [[top mutableChildNodes] removeObject:b];
        printf("  b removed: its parent %s, top has %lu\n", str([b parentNode]), (unsigned long)[[top childNodes] count]);
        [nw dump:"observing top's childNodes"];
        [top removeObserver:nw forKeyPath:@"childNodes"];

        /* ---- a tree controller ---- */
        Item *docs = [Item folder:@"Docs" size:0 children:@[ [Item file:@"todo" size:3], [Item file:@"notes" size:12] ]];
        Item *pics = [Item folder:@"Pics" size:0 children:@[ [Item folder:@"Trip" size:0 children:@[ [Item file:@"beach" size:900] ]],
                                                                 [Item file:@"cat" size:400] ]];
        Item *readme = [Item file:@"readme" size:1];
        Item *empty = [Item folder:@"Empty" size:0 children:@[]];
        NSTreeController *tc = [[NSTreeController alloc] init];
        printf("defaults: children %s, count %s, leaf %s, avoids empty %d, preserves %d, selects inserted %d, always "
               "multiple %d, object class %s\n",
               str([tc childrenKeyPath]), str([tc countKeyPath]), str([tc leafKeyPath]), [tc avoidsEmptySelection],
               [tc preservesSelection], [tc selectsInsertedObjects], [tc alwaysUsesMultipleValuesMarker],
               [NSStringFromClass([tc objectClass]) UTF8String]);
        printf("  exposes %s\n", [[[tc exposedBindings] componentsJoinedByString:@","] UTF8String]);
        [tc setChildrenKeyPath:@"children"];
        Watcher *w = [[Watcher alloc] init];
        [tc addObserver:w forKeyPath:@"selectionIndexPaths" options:0 context:NULL];
        [tc addObserver:w forKeyPath:@"selection.name" options:0 context:NULL];
        [tc addObserver:w forKeyPath:@"arrangedObjects.name" options:0 context:NULL];
        [tc setContent:[NSMutableArray arrayWithObjects:docs, pics, readme, empty, nil]];
        tree("content (no leaf key path: no children is a leaf)", tc);
        [w dump:"set content"];
        NSTreeNode *docsNode = [[tc arrangedObjects] descendantNodeAtIndexPath:P(0, -1, -1)];
        printf("arrangedObjects: %lu top-level, [1.0.0] %s, [9] %s; a node of %s, parent of [0.1] is %s\n",
               (unsigned long)[[[tc arrangedObjects] childNodes] count],
               str([[[tc arrangedObjects] descendantNodeAtIndexPath:P(1, 0, 0)] representedObject]),
               str([[tc arrangedObjects] descendantNodeAtIndexPath:P(9, -1, -1)]),
               [NSStringFromClass([docsNode class]) UTF8String],
               str([[[[tc arrangedObjects] descendantNodeAtIndexPath:P(0, 1, -1)] parentNode] representedObject]));
        [tc setLeafKeyPath:@"file"];
        tree("leaf key path \"file\" (Empty can open)", tc);
        printf("  same node for Docs after arranging again: %d\n",
               [[tc arrangedObjects] descendantNodeAtIndexPath:P(0, -1, -1)] == docsNode);
        [tc setLeafKeyPath:nil];
        [tc setCountKeyPath:@"kidCount"];
        printf("count key path: Empty leaf %d, Docs leaf %d, can add child %d\n",
               [[[tc arrangedObjects] descendantNodeAtIndexPath:P(3, -1, -1)] isLeaf],
               [[[tc arrangedObjects] descendantNodeAtIndexPath:P(0, -1, -1)] isLeaf], [tc canAddChild]);
        [tc setCountKeyPath:nil];
        [tc setLeafKeyPath:@"file"];
        [w dump:"key paths changed"];

        /* the selection */
        [tc setSelectionIndexPath:P(1, 0, 0)];
        tree("selected [1.0.0]", tc);
        printf("  selectedObjects %s, selectedNodes' objects %s, selectionIndexPath %s\n",
               [[[tc selectedObjects] componentsJoinedByString:@","] UTF8String],
               [[[[tc selectedNodes] valueForKey:@"representedObject"] componentsJoinedByString:@","] UTF8String],
               [path([tc selectionIndexPath]) UTF8String]);
        [tc addSelectionIndexPaths:@[ P(0, 1, -1), P(7, -1, -1) ]];
        printf("added [0.1] and [7] (no such node): %s, selection.name %s, selection.size %s\n",
               [paths([tc selectionIndexPaths]) UTF8String], str([tc valueForKeyPath:@"selection.name"]),
               str([tc valueForKeyPath:@"selection.size"]));
        [tc setValue:@"same" forKeyPath:@"selection.name"];
        printf("  set selection.name: %s\n", [[[tc selectedObjects] componentsJoinedByString:@","] UTF8String]);
        [w dump:"selecting and setting through the selection"];
        [(Item *)[tc selectedObjects][0] setName:@"notes"];
        [(Item *)[tc selectedObjects][1] setName:@"beach"];
        [tc removeSelectionIndexPaths:@[ P(0, 1, -1) ]];
        printf("removed [0.1] from the selection: %s; can remove %d, can add child %d, can insert child %d\n",
               [paths([tc selectionIndexPaths]) UTF8String], [tc canRemove], [tc canAddChild], [tc canInsertChild]);
        [tc setSelectionIndexPath:P(1, -1, -1)];
        printf("Pics selected: can add child %d, can insert child %d, can add %d, can insert %d\n", [tc canAddChild],
               [tc canInsertChild], [tc canAdd], [tc canInsert]);
        [w dump:"names put back"];

        /* sorting, level by level, keeping the selection */
        [tc setSelectionIndexPath:P(0, 0, -1)];
        [tc setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
        tree("sorted by name (todo stays selected)", tc);
        [w dump:"sorted"];
        [tc setPreservesSelection:NO];
        [tc setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"size" ascending:NO] ]];
        tree("by size, descending, not preserving ([0.1] is a leaf's child now: the first)", tc);
        [tc setPreservesSelection:YES];
        [tc setSortDescriptors:nil];
        [w dump:"sorted again"];

        /* the model changes its children */
        [tc setSelectionIndexPath:P(1, 1, -1)];
        [[docs mutableArrayValueForKey:@"children"] addObject:[Item file:@"plan" size:5]];
        dump_calls();
        tree("Docs got plan (from the model)", tc);
        [[pics mutableArrayValueForKey:@"children"] removeObjectAtIndex:0];
        dump_calls();
        tree("Pics lost Trip (cat stays selected)", tc);
        [w dump:"the model changed"];
        pics.children = [NSMutableArray arrayWithObjects:[Item file:@"dog" size:200], nil];
        tree("Pics given new children (cat gone: the first is selected)", tc);
        docs.name = @"Documents";
        [w dump:"Pics replaced, Docs renamed"];
        docs.name = @"Docs";

        /* inserting, removing and moving */
        Item *zip = [Item file:@"zip" size:77];
        [tc insertObject:zip atArrangedObjectIndexPath:P(0, 1, -1)];
        dump_calls();
        tree("inserted zip at [0.1]", tc);
        [tc insertObject:[Item file:@"top" size:2] atArrangedObjectIndexPath:P(0, -1, -1)];
        tree("inserted top at [0]", tc);
        [tc removeObjectAtArrangedObjectIndexPath:P(1, 1, -1)];
        dump_calls();
        tree("removed zip (selected): the one now there", tc);
        [tc removeObjectsAtArrangedObjectIndexPaths:@[ P(2, -1, -1), P(2, 0, -1) ]];
        tree("removed Pics and its dog: the one now there", tc);
        @try {
            [tc insertObject:zip atArrangedObjectIndexPath:P(9, 0, -1)];
        } @catch (NSException *e) {
            printf("inserting under [9]: %s\n", [[e name] UTF8String]);
        }
        NSTreeNode *readmeNode = [[tc arrangedObjects] descendantNodeAtIndexPath:P(2, -1, -1)];
        [tc moveNode:readmeNode toIndexPath:P(1, 0, -1)];
        dump_calls();
        tree("moved readme to [1.0]", tc);
        [w dump:"inserting, removing and moving"];

        /* the actions */
        [tc setObjectClass:[Item class]];
        [tc setSelectionIndexPath:P(1, 1, -1)];
        [tc add:nil];
        printf("add: %lu children of Docs before the turn,", (unsigned long)[docs.children count]);
        turn();
        printf(" %lu after\n", (unsigned long)[docs.children count]);
        dump_calls();
        tree("add: after the selected node's last sibling", tc);
        [tc insert:nil];
        turn();
        dump_calls();
        tree("insert: where the selected node is", tc);
        [tc setSelectionIndexPath:P(1, -1, -1)];
        [tc addChild:nil];
        turn();
        [tc insertChild:nil];
        turn();
        dump_calls();
        tree("addChild: on Docs, then insertChild: on the new one", tc);
        [tc setSelectionIndexPath:P(1, 2, -1)];
        printf("on a file: can add child %d\n", [tc canAddChild]);
        [tc addChild:nil];
        turn();
        printf("  addChild: on a file did nothing: Docs has %lu\n", (unsigned long)[docs.children count]);
        [tc remove:nil];
        turn();
        dump_calls();
        tree("remove:", tc);
        [tc setSelectionIndexPaths:@[]];
        [tc add:nil];
        turn();
        tree("add: with nothing selected: at the top", tc);
        [tc setEditable:NO];
        printf("not editable: can add %d, insert %d, add child %d, remove %d\n", [tc canAdd], [tc canInsert], [tc canAddChild],
               [tc canRemove]);
        [tc setEditable:YES];
        [w dump:"the actions"];
        [tc removeObserver:w forKeyPath:@"selectionIndexPaths"];
        [tc removeObserver:w forKeyPath:@"selection.name"];
        [tc removeObserver:w forKeyPath:@"arrangedObjects.name"];

        /* ---- bound content and selection ---- */
        Disk *disk = [[Disk alloc] init];
        [disk.items addObjectsFromArray:@[ docs, readme ]];
        NSTreeController *bc = [[NSTreeController alloc] init];
        [bc setChildrenKeyPath:@"children"];
        [bc setLeafKeyPath:@"file"];
        [bc setObjectClass:[Item class]];
        [bc bind:NSContentArrayBinding toObject:disk withKeyPath:@"items" options:nil];
        [bc bind:NSSelectionIndexPathsBinding toObject:disk withKeyPath:@"picked" options:nil];
        tree("bound to the disk", bc);
        printf("  disk picked %s\n", [paths(disk.picked) UTF8String]);
        [bc insertObject:[Item file:@"new" size:0] atArrangedObjectIndexPath:P(1, -1, -1)];
        dump_calls();
        printf("inserted at [1]: disk has %s, picked %s\n", [[disk.items componentsJoinedByString:@","] UTF8String],
               [paths(disk.picked) UTF8String]);
        [bc removeObjectAtArrangedObjectIndexPath:P(1, -1, -1)];
        dump_calls();
        [[disk mutableArrayValueForKey:@"items"] insertObject:pics atIndex:0];
        dump_calls();
        tree("the disk added Pics at the top", bc);
        disk.picked = @[ P(0, 0, -1) ];
        tree("the disk picked [0.0]", bc);
        [bc unbind:NSSelectionIndexPathsBinding];
        [bc unbind:NSContentArrayBinding];

        /* ---- dictionaries ---- */
        NSTreeController *dc = [[NSTreeController alloc] init];
        [dc setChildrenKeyPath:@"children"];
        [dc setContent:[NSMutableArray arrayWithObject:[NSMutableDictionary dictionaryWithDictionary:@{@"name" : @"root"}]]];
        tree("a dictionary", dc);
        [dc addChild:nil];
        turn();
        [dc setValue:@"kid" forKeyPath:@"selection.name"];
        tree("addChild: on it (a new dictionary, its children set)", dc);
        printf("  root's children: %s, class of the new one %s\n",
               [[[[[dc content][0] objectForKey:@"children"] valueForKey:@"name"] componentsJoinedByString:@","] UTF8String],
               [[dc selectedObjects][0] isKindOfClass:[NSMutableDictionary class]] ? "a mutable dictionary" : "?");

        /* ---- an outline view bound to a tree controller ---- */
        Item *music = [Item folder:@"Music" size:0 children:@[ [Item file:@"song" size:30], [Item file:@"aria" size:60] ]];
        Item *films = [Item folder:@"Films" size:0 children:@[ [Item folder:@"Old" size:0 children:@[ [Item file:@"reel" size:700] ]] ]];
        Item *memo = [Item file:@"memo" size:4];
        NSTreeController *otc = [[NSTreeController alloc] initWithContent:[NSMutableArray arrayWithObjects:music, films, memo, nil]];
        [otc setChildrenKeyPath:@"children"];
        [otc setLeafKeyPath:@"file"];
        [otc setObjectClass:[Item class]];
        [otc rearrangeObjects];

        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        [win makeKeyAndOrderFront:nil];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 360, 260)];
        NSOutlineView *ov = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 340, 100)];
        NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [nameCol setTitle:@"Name"];
        [nameCol setWidth:160];
        NSTableColumn *sizeCol = [[NSTableColumn alloc] initWithIdentifier:@"size"];
        [sizeCol setTitle:@"Size"];
        [sizeCol setWidth:60];
        [ov addTableColumn:nameCol];
        [ov addTableColumn:sizeCol];
        [ov setOutlineTableColumn:nameCol];
        [ov setAllowsMultipleSelection:YES];
        [scroll setDocumentView:ov];
        [[win contentView] addSubview:scroll];
        [nameCol bind:NSValueBinding toObject:otc withKeyPath:@"arrangedObjects.name" options:nil];
        [sizeCol bind:NSValueBinding toObject:otc withKeyPath:@"arrangedObjects.size" options:nil];
        printf("outline bound to: content %s, selectionIndexPaths %s, selectionIndexes %s, sortDescriptors %s; exposes %s\n",
               str([[ov infoForBinding:NSContentBinding] objectForKey:NSObservedKeyPathKey]),
               str([[ov infoForBinding:NSSelectionIndexPathsBinding] objectForKey:NSObservedKeyPathKey]),
               str([[ov infoForBinding:NSSelectionIndexesBinding] objectForKey:NSObservedKeyPathKey]),
               str([[ov infoForBinding:NSSortDescriptorsBinding] objectForKey:NSObservedKeyPathKey]),
               [[[ov exposedBindings] componentsJoinedByString:@","] UTF8String]);
        outline("bound", ov);
        printf("  item 0 is the controller's node %d; its object %s\n",
               [ov itemAtRow:0] == [[otc arrangedObjects] descendantNodeAtIndexPath:P(0, -1, -1)],
               str([[ov itemAtRow:0] representedObject]));
        [ov expandItem:[ov itemAtRow:1]];
        outline("Films opened", ov);
        NSRect chevron = [ov frameOfOutlineCellAtRow:0];
        click(win, ov, NSMakePoint(NSMidX(chevron), NSMidY(chevron)), 1, 0);
        outline("Music's chevron clicked", ov);

        click(win, ov, NSMakePoint(120, NSMidY([ov rectOfRow:2])), 1, 0);
        printf("clicked row 2: controller %s, selection.name %s\n", [paths([otc selectionIndexPaths]) UTF8String],
               str([otc valueForKeyPath:@"selection.name"]));
        click(win, ov, NSMakePoint(120, NSMidY([ov rectOfRow:4])), 1, NSEventModifierFlagCommand);
        printf("command-clicked row 4: controller %s\n", [paths([otc selectionIndexPaths]) UTF8String]);
        [otc setSelectionIndexPath:P(1, 0, 0)];
        outline("controller selected [1.0.0] (Old opened to show it)", ov);
        [ov collapseItem:[ov itemAtRow:3]];
        printf("Films closed: controller %s, outline %s\n", [paths([otc selectionIndexPaths]) UTF8String],
               [rows([ov selectedRowIndexes]) UTF8String]);
        [ov expandItem:[ov itemAtRow:3] expandChildren:YES];
        music.name = @"Tunes";
        outline("Films opened again, Music renamed Tunes by the model", ov);
        music.name = @"Music";

        NSTableHeaderView *header = [ov headerView];
        click(win, header, NSMakePoint(NSMidX([header headerRectOfColumn:0]), 14), 1, 0);
        printf("clicked Name's title: controller sorts by %s\n", str([[[otc sortDescriptors] firstObject] key]));
        outline("sorted by name (open items stay open)", ov);
        click(win, header, NSMakePoint(NSMidX([header headerRectOfColumn:1]), 14), 1, 0);
        printf("clicked Size's title: first %s\n", str([[[otc sortDescriptors] firstObject] key]));
        outline("sorted by size", ov);
        [otc setSortDescriptors:@[]];

        /* a cell edited in place */
        [otc setSelectionIndexPath:P(0, 1, -1)];
        NSInteger songRow = [ov selectedRow];
        NSRect f = [ov frameOfCellAtColumn:0 row:songRow];
        click(win, ov, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        printf("double click on aria's name: edited row %ld\n", (long)[ov editedRow]);
        type(win, @"opera");
        key(win, '\r');
        printf("typed opera, Return: %s, %s\n", [[music.children[0] name] UTF8String], [[music.children[1] name] UTF8String]);
        f = [ov frameOfCellAtColumn:1 row:songRow];
        click(win, ov, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"5");
        key(win, '\r');
        printf("size edited: %s (a number: %d)\n", str(@([(Item *)music.children[1] size])),
               [[music.children[1] valueForKey:@"size"] isKindOfClass:[NSNumber class]]);

        /* not editable: no edits start, none are written */
        [otc setEditable:NO];
        click(win, ov, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        printf("controller not editable: double click edits row %ld\n", (long)[ov editedRow]);
        [otc setEditable:YES];
        f = [ov frameOfCellAtColumn:0 row:songRow];
        click(win, ov, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"x");
        [otc setEditable:NO];
        key(win, '\r');
        printf("made not editable while editing, Return: name %s, editing ended %d\n", [[music.children[1] name] UTF8String],
               [ov editedRow] == -1);
        [otc setEditable:YES];
        outline("after editing", ov);

        /* children through the controller */
        [otc setSelectionIndexPath:P(2, -1, -1)];
        printf("memo selected: can add child %d\n", [otc canAddChild]);
        [otc setSelectionIndexPath:P(1, 0, -1)];
        [ov collapseItem:[ov itemAtRow:[ov selectedRow]]];
        [otc addChild:nil];
        turn();
        [otc setValue:@"film" forKeyPath:@"selection.name"];
        outline("addChild: on Old (shown, selected)", ov);
        [otc remove:nil];
        turn();
        outline("remove:", ov);
        [otc insertObject:[Item file:@"late" size:9] atArrangedObjectIndexPath:P(3, -1, -1)];
        outline("late inserted at the end", ov);
        [otc setContent:nil];
        outline("no content", ov);
        [nameCol unbind:NSValueBinding];
        [sizeCol unbind:NSValueBinding];
        [ov unbind:NSContentBinding];
        [ov unbind:NSSelectionIndexPathsBinding];
        [ov unbind:NSSortDescriptorsBinding];
        printf("unbound: %ld rows\n", (long)[ov numberOfRows]);
        [scroll removeFromSuperview];

        /* ---- per-row editable and enabled bindings on a table ---- */
        Item *one = [Item file:@"one" size:1], *two = [Item file:@"two" size:2], *three = [Item file:@"three" size:3];
        two.locked = YES;
        NSArrayController *ac = [[NSArrayController alloc] initWithContent:[NSMutableArray arrayWithObjects:one, two, three, nil]];
        NSScrollView *scroll2 = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 360, 260)];
        NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 340, 100)];
        NSTableColumn *tName = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [tName setWidth:120];
        NSTableColumn *tFile = [[NSTableColumn alloc] initWithIdentifier:@"file"];
        [tFile setWidth:60];
        NSButtonCell *check = [[NSButtonCell alloc] init];
        [check setButtonType:NSButtonTypeSwitch];
        [tFile setDataCell:check];
        [tv addTableColumn:tName];
        [tv addTableColumn:tFile];
        [scroll2 setDocumentView:tv];
        [[win contentView] addSubview:scroll2];
        [tName bind:NSValueBinding toObject:ac withKeyPath:@"arrangedObjects.name" options:nil];
        [tName bind:NSEditableBinding toObject:ac withKeyPath:@"arrangedObjects.locked"
            options:@{NSValueTransformerNameBindingOption : NSNegateBooleanTransformerName}];
        [tFile bind:NSValueBinding toObject:ac withKeyPath:@"arrangedObjects.file" options:nil];
        [tFile bind:NSEnabledBinding toObject:ac withKeyPath:@"arrangedObjects.size" options:nil];
        one.size = 0;
        printf("per row: file cells enabled %d %d %d\n", [[tv preparedCellAtColumn:1 row:0] isEnabled],
               [[tv preparedCellAtColumn:1 row:1] isEnabled], [[tv preparedCellAtColumn:1 row:2] isEnabled]);
        [ac setSelectionIndex:1];
        f = [tv frameOfCellAtColumn:0 row:1];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        printf("double click on two (locked): edited row %ld\n", (long)[tv editedRow]);
        two.locked = NO;
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"deux");
        key(win, '\r');
        printf("unlocked, edited: %s\n", [two.name UTF8String]);
        f = [tv frameOfCellAtColumn:1 row:0];
        [ac setSelectionIndex:0];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 1, 0);
        printf("clicked one's check box (disabled: size 0): file %d (unchanged)\n", one.file);
        f = [tv frameOfCellAtColumn:1 row:2];
        [ac setSelectionIndex:2];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 1, 0);
        printf("clicked three's check box: file %d\n", three.file);
        [ac setEditable:NO];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 1, 0);
        printf("controller not editable, clicked again: file %d\n", three.file);
        f = [tv frameOfCellAtColumn:0 row:2];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        printf("double click on three's name: edited row %ld\n", (long)[tv editedRow]);
        [ac setEditable:YES];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"trois");
        [ac setEditable:NO];
        key(win, '\r');
        printf("made not editable while editing, Return: %s\n", [three.name UTF8String]);
        [ac setEditable:YES];
        NSTableColumn *tName2 = [[NSTableColumn alloc] initWithIdentifier:@"name2"];
        [tv addTableColumn:tName2];
        [tv moveColumn:2 toColumn:0];
        [tName2 bind:NSValueBinding toObject:ac withKeyPath:@"arrangedObjects.name"
             options:@{NSConditionallySetsEditableBindingOption : @NO}];
        [ac setEditable:NO];
        f = [tv frameOfCellAtColumn:0 row:2];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"drei");
        key(win, '\r');
        printf("NSConditionallySetsEditable NO, controller not editable: %s\n", [three.name UTF8String]);
        [ac setEditable:YES];
        [tName unbind:NSValueBinding];
        [tName unbind:NSEditableBinding];
        [tName2 unbind:NSValueBinding];
        [tFile unbind:NSValueBinding];
        [tFile unbind:NSEnabledBinding];
        [tv unbind:NSContentBinding];
        [tv unbind:NSSelectionIndexesBinding];
        [tv unbind:NSSortDescriptorsBinding];

        /* ---- a dictionary controller ---- */
        disk.settings = @{@"color" : @"blue", @"size" : @12, @"secret" : @"x"};
        NSDictionaryController *dic = [[NSDictionaryController alloc] init];
        printf("dictionary controller: initial key %s, value %s; exposes %s\n", str([dic initialKey]), str([dic initialValue]),
               [[[dic exposedBindings] componentsJoinedByString:@","] UTF8String]);
        [dic setExcludedKeys:@[ @"secret" ]];
        [dic setIncludedKeys:@[ @"name" ]];
        [dic setLocalizedKeyDictionary:@{@"color" : @"Colour"}];
        [dic bind:NSContentDictionaryBinding toObject:disk withKeyPath:@"settings" options:nil];
        NSArray *pairs = [dic arrangedObjects];
        for (id<NSDictionaryControllerKeyValuePair> p in pairs)
            printf("  pair %s = %s, localized %s, explicitly included %d\n", [[p key] UTF8String], str([p value]),
                   [[p localizedKey] UTF8String], [p isExplicitlyIncluded]);
        printf("  selection.key %s, arrangedObjects.key %s\n", str([dic valueForKeyPath:@"selection.key"]),
               [[[dic valueForKeyPath:@"arrangedObjects.key"] componentsJoinedByString:@","] UTF8String]);
        Watcher *dw = [[Watcher alloc] init];
        [disk addObserver:dw forKeyPath:@"settings" options:0 context:NULL];
        [pairs[0] setValue:@"red"];
        printf("color set to red: settings color %s, secret kept %s\n", str(disk.settings[@"color"]), str(disk.settings[@"secret"]));
        [pairs[2] setKey:@"points"];
        printf("size renamed points: settings %s\n",
               [[[[disk.settings allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","] UTF8String]);
        [dic add:nil];
        turn();
        [dic add:nil];
        turn();
        printf("add: twice: keys %s, the new values %s and %s\n",
               [[[[disk.settings allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","] UTF8String],
               str(disk.settings[@"key"]), str(disk.settings[@"key1"]));
        [dic setSelectedObjects:@[ [dic arrangedObjects][0] ]];
        printf("  selected %s\n", str([dic valueForKeyPath:@"selection.key"]));
        [dic remove:nil];
        turn();
        printf("remove: keys %s\n",
               [[[[disk.settings allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","] UTF8String]);
        disk.settings = @{@"only" : @1};
        printf("the disk's settings replaced: pairs %s\n",
               [[[dic valueForKeyPath:@"arrangedObjects.key"] componentsJoinedByString:@","] UTF8String]);
        [dw dump:"the disk's settings"];
        [disk removeObserver:dw forKeyPath:@"settings"];
        [dic unbind:NSContentDictionaryBinding];
        NSMutableDictionary *own = [NSMutableDictionary dictionaryWithObject:@"v" forKey:@"k"];
        NSDictionaryController *dic2 = [[NSDictionaryController alloc] initWithContent:own];
        [[dic2 arrangedObjects][0] setValue:@"w"];
        [dic2 setInitialKey:@"k"];
        id<NSDictionaryControllerKeyValuePair> fresh = [dic2 newObject];
        [dic2 addObject:fresh];
        printf("unbound, mutable: changed in place %s, content is it %d, new key %s\n", str(own[@"k"]), [dic2 content] == own,
               [[fresh key] UTF8String]);
    }
    return 0;
}
