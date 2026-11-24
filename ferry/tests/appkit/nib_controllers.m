/* SPDX-License-Identifier: GPL-3.0-or-later
 * Controllers loaded from a nib (Ferry 0.20.0), with no display. The nib
 * is written here, in the program, with Ferry's own keyed archiver: an
 * NSIBObjectData laid out the way compiled nibs are described publicly,
 * holding an array controller, a tree controller, an object controller and
 * a dictionary controller with their settings, a window with a cell-based
 * table whose columns are bound to the array controller, a view-based
 * table and a view-based outline view whose cell view prototypes (nibs of
 * their own, inside the table's) hold controls bound to the cell view's
 * "objectValue.key", and text fields bound to the controllers' selections,
 * all tied together by binding connectors and outlets; nothing is bound
 * in code. Then: the settings read back, the bindings the connectors made,
 * the rows, a click selecting through the controller, a field edited and
 * the model, the table and the cell views following, cell views' controls
 * edited in place and clicked (written back two-way), the model changed
 * under them, add: and remove: through the controller, the outline's cell
 * views (the nodes' objects) edited, the object controller's prepared
 * content, and the dictionary controller's pairs. */
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static const char *str(id v) { return v ? [[v description] UTF8String] : "nil"; }
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

/* ---- writing a nib with NSKeyedArchiver ------------------------------------------------- */

/* A boolean, archived with encodeBool:forKey:. */
@interface NibFlag : NSObject {
@public
    BOOL on;
}
@end
@implementation NibFlag
@end
static NibFlag *B(BOOL on)
{
    NibFlag *f = [[NibFlag alloc] init];
    f->on = on;
    return f;
}
static NSValue *R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return [NSValue valueWithRect:NSMakeRect(x, y, w, h)]; }

/* An object of a nib: a class name and its keys in order. Numbers are
 * archived as integers or doubles, rects with encodeRect:forKey:, the rest
 * as objects. Each class name gets a class of its own here whose archived
 * name is that name. */
@interface NibObj : NSObject <NSCoding> {
@public
    NSString *cls;
    NSMutableArray *pairs;
}
- (void)set:(NSString *)key to:(id)value;
@end
@implementation NibObj
- (Class)classForKeyedArchiver
{
    static NSMutableDictionary *made;
    if (!made)
        made = [NSMutableDictionary dictionary];
    Class c = [[made objectForKey:cls] pointerValue];
    if (!c) {
        c = objc_allocateClassPair([NSObject class], [[@"FerryNibAs" stringByAppendingString:cls] UTF8String], 0);
        objc_registerClassPair(c);
        [NSKeyedArchiver setClassName:cls forClass:c];
        [made setObject:[NSValue valueWithPointer:(__bridge void *)c] forKey:cls];
    }
    return c;
}
- (void)set:(NSString *)key to:(id)value { [pairs addObject:@[ key, value ]]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    for (NSArray *p in pairs) {
        NSString *k = p[0];
        id v = p[1];
        if ([v isKindOfClass:[NibFlag class]])
            [c encodeBool:((NibFlag *)v)->on forKey:k];
        else if ([v isKindOfClass:[NSNumber class]] && (*[v objCType] == 'd' || *[v objCType] == 'f'))
            [c encodeDouble:[v doubleValue] forKey:k];
        else if ([v isKindOfClass:[NSNumber class]])
            [c encodeInt64:[v longLongValue] forKey:k];
        else if ([v isKindOfClass:[NSValue class]])
            [c encodeRect:[v rectValue] forKey:k];
        else
            [c encodeObject:v forKey:k];
    }
}
- (instancetype)initWithCoder:(NSCoder *)c { return nil; }
@end
static NibObj *O(NSString *cls, NSArray *kv)
{
    NibObj *o = [[NibObj alloc] init];
    o->cls = cls;
    o->pairs = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < [kv count]; i += 2)
        [o set:kv[i] to:kv[i + 1]];
    return o;
}
static NibObj *custom(NSString *name) { return O(@"NSCustomObject", @[ @"NSClassName", name ]); }
static NibObj *outlet(NibObj *src, NibObj *dst, NSString *label)
{
    return O(@"NSNibOutletConnector", @[ @"NSSource", src, @"NSDestination", dst, @"NSLabel", label ]);
}
static NibObj *binding(NibObj *src, NibObj *dst, NSString *name, NSString *path, NSDictionary *options)
{
    NibObj *b = O(@"NSNibBindingConnector",
                  @[ @"NSSource", src, @"NSDestination", dst, @"NSLabel", [NSString stringWithFormat:@"%@: %@", name, path],
                     @"NSBinding", name, @"NSKeyPath", path, @"NSNibBindingConnectorVersion", @2 ]);
    if (options)
        [b set:@"NSOptions" to:options];
    return b;
}
static NibObj *text_cell(NSString *contents, BOOL editable)
{
    return O(@"NSTextFieldCell", @[ @"NSContents", contents, @"NSCellFlags", @(0x04000000 | (editable ? 0x10000000 : 0)),
                                     @"NSCellFlags2", @0 ]);
}
static NibObj *field(NSValue *frame, BOOL editable)
{
    return O(@"NSTextField", @[ @"NSFrame", frame, @"NSvFlags", @256, @"NSCell", text_cell(@"", editable),
                                 @"NSEnabled", B(YES) ]);
}
static NibObj *check_box(NSValue *frame, NSString *title)
{
    NibObj *cell = O(@"NSButtonCell", @[ @"NSContents", title, @"NSCellFlags", @0x04000000, @"NSCellFlags2", @0,
                                          @"NSButtonFlags", @0x04000000, @"NSButtonFlags2", @2, @"NSAuxButtonType", @3 ]);
    return O(@"NSButton", @[ @"NSFrame", frame, @"NSvFlags", @256, @"NSCell", cell, @"NSEnabled", B(YES) ]);
}
static NibObj *column(NibObj *table, NSString *ident, double width, BOOL editable)
{
    return O(@"NSTableColumn", @[ @"NSIdentifier", ident, @"NSWidth", @(width), @"NSMinWidth", @20.0, @"NSMaxWidth", @1000.0,
                                   @"NSHeaderCell", O(@"NSTableHeaderCell", @[ @"NSContents", ident ]),
                                   @"NSDataCell", text_cell(@"Text Cell", YES), @"NSResizingMask", @3,
                                   @"NSIsEditable", B(editable), @"NSTableView", table ]);
}
/* A nib's bytes: its table of contents (each object with its parent) and
 * its connectors, under "IB.objectdata". */
static NSData *nib_data(NibObj *root, NSArray *objectsAndParents, NSArray *connections)
{
    NSMutableArray *objects = [NSMutableArray array], *parents = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < [objectsAndParents count]; i += 2) {
        [objects addObject:objectsAndParents[i]];
        [parents addObject:objectsAndParents[i + 1]];
    }
    NibObj *data = O(@"NSIBObjectData", @[ @"NSRoot", root, @"NSObjectsKeys", objects, @"NSObjectsValues", parents,
                                            @"NSConnections", connections, @"NSNextOid", @([objects count] + 1) ]);
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    [a encodeObject:data forKey:@"IB.objectdata"];
    return [a encodedData];
}
/* A cell view prototype: an NSTableCellView named ident with a text field
 * (its textField outlet) bound to objectValue.textKey, and, with checkKey,
 * a check box bound to objectValue.checkKey. */
static NibObj *cell_view_nib(NSString *ident, NSString *textKey, NSString *checkKey)
{
    NibObj *owner = custom(@"NSObject"), *first = custom(@"FirstResponder");
    NibObj *f = field(R(2, 2, 150, 16), YES);
    NSMutableArray *subviews = [NSMutableArray arrayWithObject:f];
    NibObj *check = checkKey ? check_box(R(160, 2, 60, 16), @"Read") : nil;
    if (check)
        [subviews addObject:check];
    NibObj *cell = O(@"NSTableCellView", @[ @"NSFrame", R(0, 0, 230, 20), @"NSvFlags", @256, @"NSSubviews", subviews,
                                             @"NSIdentifier", ident ]);
    NSMutableArray *conns = [NSMutableArray arrayWithObjects:outlet(cell, f, @"textField"),
                                            binding(f, cell, @"value", [@"objectValue." stringByAppendingString:textKey], nil), nil];
    NSMutableArray *pairs = [NSMutableArray arrayWithObjects:owner, owner, first, owner, cell, owner, f, cell, nil];
    if (check) {
        [conns addObject:binding(check, cell, @"value", [@"objectValue." stringByAppendingString:checkKey], nil)];
        [pairs addObjectsFromArray:@[ check, cell ]];
    }
    NSData *bytes = nib_data(owner, pairs, conns);
    return O(@"NSNib", @[ @"NSNibFileData", bytes ]);
}

/* ---- the model ---------------------------------------------------------------------------- */

@interface Book : NSObject
@property (copy) NSString *title;
@property NSInteger pages;
@property BOOL read;
@end
@implementation Book
+ (instancetype)title:(NSString *)t pages:(NSInteger)p
{
    Book *b = [[Book alloc] init];
    b.title = t;
    b.pages = p;
    return b;
}
- (instancetype)init
{
    if ((self = [super init]))
        _title = @"untitled";
    return self;
}
- (NSString *)description { return [NSString stringWithFormat:@"%@ (%ld%s)", _title, (long)_pages, _read ? ", read" : ""]; }
@end

@interface Node : NSObject
@property (copy) NSString *name;
@property (strong) NSMutableArray *children;
@property BOOL leaf;
@end
@implementation Node
+ (instancetype)name:(NSString *)n children:(NSArray *)kids
{
    Node *x = [[Node alloc] init];
    x.name = n;
    x.children = kids ? [NSMutableArray arrayWithArray:kids] : nil;
    x.leaf = kids == nil;
    return x;
}
@end

/* File's Owner: the model, and outlets to what the nib makes. */
@interface LibraryOwner : NSObject
@property (strong) NSMutableArray *books;
@property (strong) NSArray *sorting;
@property (strong) NSMutableArray *shelves;
@property (strong) NSDictionary *settings;
@property (strong) NSArrayController *booksController;
@property (strong) NSTreeController *shelvesController;
@property (strong) NSObjectController *notesController;
@property (strong) NSDictionaryController *settingsController;
@property (strong) NSWindow *window;
@property (strong) NSTableView *table;
@property (strong) NSTableView *cards;
@property (strong) NSOutlineView *outline;
@property (strong) NSTextField *titleField;
@property (strong) NSTextField *noteField;
@end
@implementation LibraryOwner
@end

/* The library's nib. */
static NSData *library_nib(void)
{
    NibObj *owner = custom(@"LibraryOwner"), *first = custom(@"FirstResponder"), *app = custom(@"NSApplication");

    NibObj *books = O(@"NSArrayController",
                      @[ @"NSObjectClassName", @"Book", @"NSEditable", B(YES), @"NSAutomaticallyPreparesContent", B(NO),
                         @"NSDeclaredKeys", @[ @"title", @"pages", @"read" ], @"NSAvoidsEmptySelection", B(NO),
                         @"NSPreservesSelection", B(YES), @"NSSelectsInsertedObjects", B(YES),
                         @"NSClearsFilterPredicateOnInsertion", B(NO), @"NSAutomaticallyRearrangesObjects", B(YES),
                         @"NSAlwaysUsesMultipleValuesMarker", B(YES) ]);
    NibObj *shelves = O(@"NSTreeController",
                        @[ @"NSObjectClassName", @"Node", @"NSEditable", B(YES), @"NSTreeContentChildrenKey", @"children",
                           @"NSTreeContentLeafKey", @"leaf", @"NSAvoidsEmptySelection", B(NO),
                           @"NSPreservesSelection", B(NO), @"NSSelectsInsertedObjects", B(NO) ]);
    NibObj *notes = O(@"NSObjectController", @[ @"NSObjectClassName", @"NSMutableDictionary", @"NSEditable", B(YES),
                                                 @"NSAutomaticallyPreparesContent", B(YES), @"NSEntityName", @"Note",
                                                 @"NSDeclaredKeys", @[ @"note" ] ]);
    NibObj *settings = O(@"NSDictionaryController",
                         @[ @"NSEditable", B(YES), @"NSInitialKey", @"setting", @"NSInitialValue", @"on",
                            @"NSExcludedKeys", @[ @"secret" ], @"NSIncludedKeys", @[ @"theme" ],
                            @"NSLocalizedKeyDictionary", @{ @"theme" : @"Theme", @"font" : @"Font" } ]);

    /* the window: a cell-based table, a view-based one, a view-based outline and two fields */
    NibObj *content = O(@"NSView", @[ @"NSFrame", R(0, 0, 600, 500), @"NSvFlags", @274 ]);
    NibObj *window = O(@"NSWindowTemplate", @[ @"NSWindowStyleMask", @15, @"NSWindowBacking", @2,
                                                @"NSWindowRect", R(100, 100, 600, 500), @"NSWindowTitle", @"Library",
                                                @"NSWindowClass", @"NSWindow", @"NSWindowView", content ]);
    NibObj *table = O(@"NSTableView", @[ @"NSFrame", R(10, 300, 280, 180), @"NSvFlags", @256, @"NSRowHeight", @20.0,
                                          @"NSIntercellSpacingWidth", @3.0, @"NSIntercellSpacingHeight", @2.0,
                                          @"NSTvFlags", @(0x40000000 | 0x10000000 | 0x08000000), @"NSEnabled", B(YES) ]);
    NibObj *titleCol = column(table, @"title", 180, YES), *pagesCol = column(table, @"pages", 60, YES);
    [table set:@"NSTableColumns" to:@[ titleCol, pagesCol ]];

    NibObj *cards = O(@"NSTableView", @[ @"NSFrame", R(300, 300, 290, 180), @"NSvFlags", @256, @"NSRowHeight", @20.0,
                                          @"NSIntercellSpacingWidth", @3.0, @"NSIntercellSpacingHeight", @2.0,
                                          @"NSTvFlags", @(0x40000000 | 0x10000000), @"NSEnabled", B(YES),
                                          @"NSTableViewArchivedReusableViewsKey",
                                          @{ @"card" : cell_view_nib(@"card", @"title", @"read") } ]);
    NibObj *cardCol = column(cards, @"card", 260, YES);
    [cards set:@"NSTableColumns" to:@[ cardCol ]];

    NibObj *outline = O(@"NSOutlineView", @[ @"NSFrame", R(10, 60, 280, 200), @"NSvFlags", @256, @"NSRowHeight", @20.0,
                                              @"NSIntercellSpacingWidth", @3.0, @"NSIntercellSpacingHeight", @2.0,
                                              @"NSTvFlags", @(0x40000000 | 0x10000000), @"NSEnabled", B(YES),
                                              @"NSOutlineViewIndentationPerLevelKey", @16.0,
                                              @"NSTableViewArchivedReusableViewsKey",
                                              @{ @"name" : cell_view_nib(@"name", @"name", nil) } ]);
    NibObj *nameCol = column(outline, @"name", 250, YES);
    [outline set:@"NSTableColumns" to:@[ nameCol ]];
    [outline set:@"NSOutlineViewOutlineTableColumnKey" to:nameCol];

    NibObj *titleField = field(R(300, 260, 200, 22), YES), *noteField = field(R(300, 230, 200, 22), YES);
    [content set:@"NSSubviews" to:@[ table, cards, outline, titleField, noteField ]];

    NSDictionary *none = @{NSNullPlaceholderBindingOption : @"No note"};
    NSArray *conns = @[
        outlet(owner, books, @"booksController"), outlet(owner, shelves, @"shelvesController"),
        outlet(owner, notes, @"notesController"), outlet(owner, settings, @"settingsController"),
        outlet(owner, window, @"window"), outlet(owner, table, @"table"), outlet(owner, cards, @"cards"),
        outlet(owner, outline, @"outline"), outlet(owner, titleField, @"titleField"),
        outlet(owner, noteField, @"noteField"),
        /* the controllers' content and sorting from File's Owner */
        binding(books, owner, @"contentArray", @"books", nil),
        binding(books, owner, @"sortDescriptors", @"sorting", nil),
        binding(shelves, owner, @"contentArray", @"shelves", nil),
        binding(settings, owner, @"contentDictionary", @"settings", nil),
        /* a cell-based table through its columns */
        binding(titleCol, books, @"value", @"arrangedObjects.title", nil),
        binding(pagesCol, books, @"value", @"arrangedObjects.pages", nil),
        /* a view-based table and outline through their content */
        binding(cards, books, @"content", @"arrangedObjects", nil),
        binding(cards, books, @"selectionIndexes", @"selectionIndexes", nil),
        binding(outline, shelves, @"content", @"arrangedObjects", nil),
        binding(outline, shelves, @"selectionIndexPaths", @"selectionIndexPaths", nil),
        /* fields */
        binding(titleField, books, @"value", @"selection.title", nil),
        binding(noteField, notes, @"value", @"selection.note", none),
    ];
    NSArray *pairs = @[
        owner, owner, first, owner, app, owner, books, owner, shelves, owner, notes, owner, settings, owner, window,
        owner, content, window, table, content, titleCol, table, pagesCol, table, cards, content, cardCol, cards, outline,
        content, nameCol, outline, titleField, content, noteField, content
    ];
    return nib_data(owner, pairs, conns);
}

static void show_table(const char *what, NSTableView *t)
{
    printf("%s:", what);
    for (NSInteger r = 0; r < [t numberOfRows]; r++) {
        printf(" [");
        for (NSInteger c = 0; c < [t numberOfColumns]; c++)
            printf("%s%s", c ? "|" : "", [[[t preparedCellAtColumn:c row:r] stringValue] UTF8String]);
        printf("]");
    }
    printf(" selected %s\n", [rows([t selectedRowIndexes]) UTF8String]);
}
static void show_cards(const char *what, NSTableView *t)
{
    printf("%s:", what);
    for (NSInteger r = 0; r < [t numberOfRows]; r++) {
        NSTableCellView *v = [t viewAtColumn:0 row:r makeIfNecessary:NO];
        NSButton *check = [[v subviews] count] > 1 ? [v subviews][1] : nil;
        printf(" [%s %s%s]", [NSStringFromClass([v class]) UTF8String], [[[v textField] stringValue] UTF8String],
               check ? ([check state] ? " x" : " -") : "");
    }
    printf(" selected %s\n", [rows([t selectedRowIndexes]) UTF8String]);
}
static void show_outline(const char *what, NSOutlineView *o)
{
    printf("%s:", what);
    for (NSInteger r = 0; r < [o numberOfRows]; r++) {
        NSTableCellView *v = [o viewAtColumn:0 row:r makeIfNecessary:NO];
        printf(" [%ld %s%s]", (long)[o levelForRow:r], [[[v textField] stringValue] UTF8String],
               [[v objectValue] isKindOfClass:[Node class]] ? "" : " (not a Node)");
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        LibraryOwner *owner = [[LibraryOwner alloc] init];
        Book *dune = [Book title:@"Dune" pages:412], *emma = [Book title:@"Emma" pages:320],
             *alice = [Book title:@"Alice" pages:96];
        alice.read = YES;
        owner.books = [NSMutableArray arrayWithObjects:dune, emma, alice, nil];
        owner.sorting = @[ [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES] ];
        Node *poems = [Node name:@"Poems" children:@[ [Node name:@"Odes" children:nil], [Node name:@"Sonnets" children:nil] ]];
        owner.shelves = [NSMutableArray arrayWithObjects:poems, [Node name:@"Plays" children:@[]], nil];
        owner.settings = @{@"font" : @"Serif", @"secret" : @"xyzzy"};

        NSData *bytes = library_nib();
        NSNib *nib = [[NSNib alloc] initWithNibData:bytes bundle:nil];
        NSArray *top = nil;
        BOOL loaded = [nib instantiateWithOwner:owner topLevelObjects:&top];
        NSMutableArray *names = [NSMutableArray array];
        for (id o in top)
            [names addObject:NSStringFromClass([o class])];
        [names sortUsingSelector:@selector(compare:)];
        printf("nib (keyed archive %d) loaded %d: %s\n",
               [[[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(0, 8)] encoding:NSASCIIStringEncoding]
                   isEqualToString:@"bplist00"],
               loaded, [[names componentsJoinedByString:@", "] UTF8String]);

        /* ---- the controllers' settings ---- */
        NSArrayController *bc = owner.booksController;
        printf("books: %s of %s, editable %d, prepares %d, avoids empty %d, preserves %d, selects inserted %d, "
               "clears filter %d, rearranges %d, always multiple %d, declared keys %s\n",
               [NSStringFromClass([bc class]) UTF8String], [NSStringFromClass([bc objectClass]) UTF8String],
               [bc isEditable], [bc automaticallyPreparesContent], [bc avoidsEmptySelection], [bc preservesSelection],
               [bc selectsInsertedObjects], [bc clearsFilterPredicateOnInsertion], [bc automaticallyRearrangesObjects],
               [bc alwaysUsesMultipleValuesMarker],
               [[[bc performSelector:@selector(_ferryDeclaredKeys)] componentsJoinedByString:@","] UTF8String]);
        NSTreeController *tc = owner.shelvesController;
        printf("shelves: %s of %s, children %s, leaf %s, count %s, avoids empty %d, preserves %d, selects inserted %d\n",
               [NSStringFromClass([tc class]) UTF8String], [NSStringFromClass([tc objectClass]) UTF8String],
               str([tc childrenKeyPath]), str([tc leafKeyPath]), str([tc countKeyPath]), [tc avoidsEmptySelection],
               [tc preservesSelection], [tc selectsInsertedObjects]);
        NSObjectController *nc = owner.notesController;
        printf("notes: %s, entity %s, content prepared at awakeFromNib: %s %s\n", [NSStringFromClass([nc class]) UTF8String],
               str([nc entityName]), [[nc content] isKindOfClass:[NSMutableDictionary class]] ? "a mutable dictionary" : "?",
               str([nc content]));
        NSDictionaryController *dc = owner.settingsController;
        printf("settings: initial %s = %s, included %s, excluded %s, localized %s\n", str([dc initialKey]),
               str([dc initialValue]), [[[dc includedKeys] componentsJoinedByString:@","] UTF8String],
               [[[dc excludedKeys] componentsJoinedByString:@","] UTF8String],
               str([[dc localizedKeyDictionary] objectForKey:@"theme"]));

        /* ---- what the connectors bound ---- */
        NSTableView *table = owner.table, *cards = owner.cards;
        NSOutlineView *outline = owner.outline;
        printf("books bound to %s.%s; table's content %s, selectionIndexes %s, sortDescriptors %s (made by its columns)\n",
               [NSStringFromClass([[[bc infoForBinding:NSContentArrayBinding] objectForKey:NSObservedObjectKey] class]) UTF8String],
               str([[bc infoForBinding:NSContentArrayBinding] objectForKey:NSObservedKeyPathKey]),
               str([[table infoForBinding:NSContentBinding] objectForKey:NSObservedKeyPathKey]),
               str([[table infoForBinding:NSSelectionIndexesBinding] objectForKey:NSObservedKeyPathKey]),
               str([[table infoForBinding:NSSortDescriptorsBinding] objectForKey:NSObservedKeyPathKey]));
        printf("delegates: table %s, cards %s, outline %s; data sources %s %s %s\n", str([table delegate]), str([cards delegate]),
               str([outline delegate]), str([table dataSource]), str([cards dataSource]), str([outline dataSource]));

        NSWindow *win = owner.window;
        [win makeKeyAndOrderFront:nil];
        show_table("cell-based table, sorted by title", table);
        show_cards("view-based table", cards);
        NSTableCellView *cv = [cards viewAtColumn:0 row:0 makeIfNecessary:NO];
        printf("row 0's cell view: identifier %s, objectValue is the book %d, text field editable %d\n",
               str([cv identifier]), [cv objectValue] == alice, [[cv textField] isEditable]);
        printf("title field: \"%s\" (placeholder %s), editable %d\n", [[owner.titleField stringValue] UTF8String],
               str([owner.titleField placeholderString]), [owner.titleField isEditable]);

        /* ---- the selection ---- */
        click(win, table, NSMakePoint(40, NSMidY([table rectOfRow:1])), 1, 0);
        printf("clicked Dune: controller %s, title field \"%s\", editable %d\n", [rows([bc selectionIndexes]) UTF8String],
               [[owner.titleField stringValue] UTF8String], [owner.titleField isEditable]);
        show_cards("  view-based table", cards);
        click(win, table, NSMakePoint(40, NSMidY([table rectOfRow:2])), 1, NSEventModifierFlagCommand);
        printf("command-clicked Emma: title field placeholder %s (always multiple), editable %d\n",
               str([owner.titleField placeholderString]), [owner.titleField isEditable]);
        [bc setSelectionIndex:1];

        /* ---- a field bound to the selection ---- */
        [win makeFirstResponder:owner.titleField];
        type(win, @"Arrakis");
        key(win, '\r');
        printf("typed Arrakis in the title field: model %s; rearranged:\n", str(dune));
        show_table("  table", table);
        show_cards("  cards", cards);

        /* ---- a cell view's controls, edited in place ---- */
        NSInteger row = [[bc arrangedObjects] indexOfObject:emma];
        NSTableCellView *emmaView = [cards viewAtColumn:0 row:row makeIfNecessary:NO];
        [cards selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        NSRect tf = [[emmaView textField] convertRect:[[emmaView textField] bounds] toView:cards];
        click(win, cards, NSMakePoint(NSMidX(tf), NSMidY(tf)), 2, 0);
        printf("double click on Emma's card: editing %d\n", [win firstResponder] == (id)[emmaView textField]);
        type(win, @"Persuasion");
        key(win, '\r');
        /* the rows were sorted again, and a cell view may now show another row: look it up again */
        row = [[bc arrangedObjects] indexOfObject:emma];
        emmaView = [cards viewAtColumn:0 row:row makeIfNecessary:NO];
        printf("typed Persuasion, Return: model %s, row %ld's cell view %s\n", str(emma), (long)row,
               [[[emmaView textField] stringValue] UTF8String]);
        NSButton *check = (NSButton *)[emmaView subviews][1];
        NSRect cf = [check convertRect:[check bounds] toView:cards];
        click(win, cards, NSMakePoint(NSMidX(cf), NSMidY(cf)), 1, 0);
        printf("clicked its check box: model %s\n", str(emma));
        show_table("  table", table);
        show_cards("  cards", cards);

        /* ---- the model changed under the views ---- */
        alice.title = @"Through the Looking-Glass";
        alice.read = NO;
        NSTableCellView *aliceView = [cards viewAtColumn:0 row:(NSInteger)[[bc arrangedObjects] indexOfObject:alice]
                                         makeIfNecessary:NO];
        printf("model changed: Alice's card \"%s\", check %ld\n", [[[aliceView textField] stringValue] UTF8String],
               (long)[(NSButton *)[aliceView subviews][1] state]);
        show_table("  table", table);

        /* ---- adding and removing through the controller ---- */
        [bc add:nil];
        turn();
        printf("add: %lu books in the owner, the new one %s (a Book %d), selected %s\n", (unsigned long)[owner.books count],
               str([owner.books lastObject]), [[owner.books lastObject] isKindOfClass:[Book class]],
               [rows([bc selectionIndexes]) UTF8String]);
        show_cards("  cards", cards);
        [bc remove:nil];
        turn();
        printf("remove: %lu books\n", (unsigned long)[owner.books count]);
        show_cards("  cards", cards);

        /* ---- the outline's cell views ---- */
        show_outline("outline", outline);
        [outline expandItem:[outline itemAtRow:0]];
        show_outline("Poems opened", outline);
        NSTableCellView *odes = [outline viewAtColumn:0 row:1 makeIfNecessary:NO];
        printf("row 1's objectValue: %s\n", str([[odes objectValue] name]));
        [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        printf("selected in the outline: controller %s\n", str([[tc selectedObjects].firstObject name]));
        tf = [[odes textField] convertRect:[[odes textField] bounds] toView:outline];
        click(win, outline, NSMakePoint(NSMidX(tf), NSMidY(tf)), 2, 0);
        type(win, @"Elegies");
        key(win, '\r');
        printf("edited in place: model %s\n", str(((Node *)poems.children[0]).name));
        ((Node *)poems.children[1]).name = @"Haiku";
        show_outline("model renamed Sonnets", outline);
        [tc setSelectionIndexPath:[NSIndexPath indexPathWithIndex:1]];
        [tc addChild:nil];
        turn();
        printf("addChild: on Plays: %lu children, a Node %d\n", (unsigned long)[[owner.shelves[1] children] count],
               [[[owner.shelves[1] children] firstObject] isKindOfClass:[Node class]]);
        [outline expandItem:[outline itemAtRow:3]];
        show_outline("  Plays opened", outline);

        /* ---- the object controller's prepared content ---- */
        printf("note field: placeholder %s\n", str([owner.noteField placeholderString]));
        [win makeFirstResponder:owner.noteField];
        type(win, @"lent to Kim");
        key(win, '\r');
        printf("typed a note: content %s\n", str([[nc content] objectForKey:@"note"]));

        /* ---- the dictionary controller ---- */
        NSMutableArray *pairs = [NSMutableArray array];
        for (id p in [dc arrangedObjects])
            [pairs addObject:[NSString stringWithFormat:@"%@(%@)=%@", [p key], [p localizedKey], [p value] ?: @"nil"]];
        printf("settings pairs: %s\n", [[pairs componentsJoinedByString:@" "] UTF8String]);
        [dc setSelectionIndex:0];
        [dc setValue:@"Sans" forKeyPath:@"selection.value"];
        printf("font set through the selection: owner's settings %s %s, secret kept %s\n",
               str([owner.settings objectForKey:@"font"]), [owner.settings isKindOfClass:[NSDictionary class]] ? "(new dictionary)" : "",
               str([owner.settings objectForKey:@"secret"]));
        [dc add:nil];
        turn();
        printf("add: owner's settings has %s = %s\n", str([[owner.settings allKeys] containsObject:@"setting"] ? @"setting" : nil),
               str([owner.settings objectForKey:@"setting"]));
        [win orderOut:nil];
    }
    return 0;
}
