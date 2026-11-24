/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSArrayController (Ferry 0.18.0), with no display: content given and
 * bound (contentArray, through the owner's indexed accessors, and a set),
 * arrangedObjects sorted and filtered, the selection by indexes and by
 * objects, "selection.key" with the multiple-values, no-selection and
 * not-applicable markers, writing through the selection, the selection
 * options (avoidsEmptySelection, preservesSelection,
 * selectsInsertedObjects, clearsFilterPredicateOnInsertion), adding,
 * inserting and removing (the actions on the run loop's next turn),
 * automatic rearranging, observing "arrangedObjects.key", and the
 * selectionIndexes binding. Then a table whose columns are bound to
 * "arrangedObjects.key": its rows and cells, the selection both ways,
 * sorting by clicks on the column titles, a cell edited in place written
 * back to its object, and rows added and removed through the controller. */
#import <Cocoa/Cocoa.h>

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

@interface Person : NSObject
@property (copy) NSString *name;
@property NSInteger age;
@property (copy) NSString *nick;
@end
@implementation Person
+ (instancetype)name:(NSString *)n age:(NSInteger)a
{
    Person *p = [[Person alloc] init];
    p.name = n;
    p.age = a;
    return p;
}
- (NSString *)description { return _name; }
@end

/* Owns its people, with indexed accessors, and a picked selection. */
@interface Library : NSObject
@property (strong) NSMutableArray *people;
@property (strong) NSIndexSet *picked;
@property (strong) NSMutableArray *calls;
@end
@implementation Library
- (instancetype)init
{
    if ((self = [super init])) {
        _people = [NSMutableArray array];
        _calls = [NSMutableArray array];
    }
    return self;
}
- (NSUInteger)countOfPeople { return [_people count]; }
- (id)objectInPeopleAtIndex:(NSUInteger)i { return _people[i]; }
- (void)insertObject:(id)o inPeopleAtIndex:(NSUInteger)i
{
    [_calls addObject:[NSString stringWithFormat:@"insert %@ at %lu", o, (unsigned long)i]];
    [_people insertObject:o atIndex:i];
}
- (void)removeObjectFromPeopleAtIndex:(NSUInteger)i
{
    [_calls addObject:[NSString stringWithFormat:@"remove %@ at %lu", _people[i], (unsigned long)i]];
    [_people removeObjectAtIndex:i];
}
- (void)dump
{
    for (NSString *c in _calls)
        printf("  library: %s\n", [c UTF8String]);
    [_calls removeAllObjects];
}
@end

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
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    id v = [object valueForKeyPath:path];
    [_heard addObject:[NSString stringWithFormat:@"%@ = %@", path,
                                                 [v isKindOfClass:[NSArray class]] ? [v componentsJoinedByString:@","]
                                                 : [v isKindOfClass:[NSIndexSet class]] ? rows(v)
                                                                                        : [v description]]];
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

static void show(const char *what, NSArrayController *ac)
{
    printf("%s: arranged %s, selection %s (index %ld), selection.name %s\n", what,
           [[[ac arrangedObjects] componentsJoinedByString:@","] UTF8String], [rows([ac selectionIndexes]) UTF8String],
           [ac selectionIndex] == NSNotFound ? -1L : (long)[ac selectionIndex],
           str([ac valueForKeyPath:@"selection.name"]));
}

static void table(const char *what, NSTableView *tv)
{
    printf("%s: %ld rows, selected %s\n", what, (long)[tv numberOfRows], [rows([tv selectedRowIndexes]) UTF8String]);
    for (NSInteger r = 0; r < [tv numberOfRows]; r++) {
        printf("  row %ld:", (long)r);
        for (NSInteger c = 0; c < [tv numberOfColumns]; c++)
            printf(" [%s]", [[[tv preparedCellAtColumn:c row:r] stringValue] UTF8String]);
        printf("\n");
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Person *ann = [Person name:@"Ann" age:40], *bob = [Person name:@"Bob" age:25], *cy = [Person name:@"Cy" age:33];

        /* ---- an empty controller ---- */
        NSArrayController *ac = [[NSArrayController alloc] init];
        printf("defaults: avoids empty %d, preserves %d, selects inserted %d, clears filter %d, rearranges %d, "
               "always multiple %d\n",
               [ac avoidsEmptySelection], [ac preservesSelection], [ac selectsInsertedObjects],
               [ac clearsFilterPredicateOnInsertion], [ac automaticallyRearrangesObjects],
               [ac alwaysUsesMultipleValuesMarker]);
        printf("empty: %lu arranged, can add %d, can insert %d, can remove %d, selection.name %s, exposes %s\n",
               (unsigned long)[[ac arrangedObjects] count], [ac canAdd], [ac canInsert], [ac canRemove],
               str([ac valueForKeyPath:@"selection.name"]),
               [[[ac exposedBindings] componentsJoinedByString:@","] UTF8String]);

        /* ---- content ---- */
        Watcher *w = [[Watcher alloc] init];
        [ac addObserver:w forKeyPath:@"selectionIndexes" options:0 context:NULL];
        [ac addObserver:w forKeyPath:@"arrangedObjects.name" options:0 context:NULL];
        [ac addObserver:w forKeyPath:@"selection.name" options:0 context:NULL];
        [ac addObserver:w forKeyPath:@"arrangedObjects.@count" options:0 context:NULL];
        [ac setContent:[NSMutableArray arrayWithObjects:ann, bob, cy, nil]];
        show("content", ac);
        [w dump:"set content"];
        bob.name = @"Bobby";
        [w dump:"Bob renamed (arranged, not selected)"];
        ann.name = @"Anne";
        [w dump:"Ann renamed (arranged and selected)"];
        printf("arrangedObjects.age %s, .@count %s, .@sum.age %s, selectedObjects %s, canRemove %d\n",
               [[[ac valueForKeyPath:@"arrangedObjects.age"] componentsJoinedByString:@","] UTF8String],
               str([ac valueForKeyPath:@"arrangedObjects.@count"]), str([ac valueForKeyPath:@"arrangedObjects.@sum.age"]),
               [[[ac selectedObjects] componentsJoinedByString:@","] UTF8String], [ac canRemove]);

        /* ---- the selection ---- */
        BOOL changed = [ac setSelectionIndexes:[NSIndexSet indexSetWithIndex:0]];
        printf("select {0} again: changed %d\n", changed);
        [ac addSelectionIndexes:[NSIndexSet indexSetWithIndex:2]];
        show("ann and cy", ac);
        [w dump:"selection changed"];
        printf("  selection.age %s, selection.nothing %s, same again %d\n", str([ac valueForKeyPath:@"selection.age"]),
               str([ac valueForKeyPath:@"selection.nothing"]), [ac addSelectionIndexes:[NSIndexSet indexSetWithIndex:2]]);
        cy.age = 40;
        printf("  ages agree: selection.age %s\n", str([ac valueForKeyPath:@"selection.age"]));
        [ac setAlwaysUsesMultipleValuesMarker:YES];
        printf("  always the marker: selection.age %s\n", str([ac valueForKeyPath:@"selection.age"]));
        [ac setAlwaysUsesMultipleValuesMarker:NO];
        [ac setValue:@"Twin" forKeyPath:@"selection.name"];
        printf("  set selection.name: %s and %s\n", [ann.name UTF8String], [cy.name UTF8String]);
        [w dump:"set through the selection"];
        ann.name = @"Ann";
        cy.name = @"Cy";
        cy.age = 33;
        [w dump:"names put back"];
        [ac setSelectedObjects:@[ bob ]];
        show("selected Bob by object", ac);
        [ac removeSelectedObjects:@[ bob ]];
        show("deselected Bob", ac);
        [ac setSelectionIndex:0];
        [ac selectNext:nil];
        printf("select next: %s, can select next %d, previous %d\n", [rows([ac selectionIndexes]) UTF8String],
               [ac canSelectNext], [ac canSelectPrevious]);
        [ac selectNext:nil];
        [ac selectNext:nil];
        [ac selectPrevious:nil];
        printf("next twice, previous: %s\n", [rows([ac selectionIndexes]) UTF8String]);
        [w dump:"moving the selection"];

        /* ---- arranging ---- */
        [ac setSelectionIndex:0];
        [ac setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO] ]];
        show("sorted by name, descending (Ann stays selected)", ac);
        [w dump:"sorted"];
        [ac setPreservesSelection:NO];
        [ac setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ]];
        show("by age, not preserving (index 2 stays)", ac);
        [ac setPreservesSelection:YES];
        [ac setSelectedObjects:@[ bob ]];
        [ac setFilterPredicate:[NSPredicate predicateWithFormat:@"age > 30"]];
        show("filtered to age > 30 (Bob gone, so the first)", ac);
        [ac setFilterPredicate:nil];
        show("filter off", ac);
        printf("content %s (unchanged order)\n", [[[ac content] componentsJoinedByString:@","] UTF8String]);
        [w dump:"filtering"];

        /* ---- adding, inserting and removing ---- */
        Person *dee = [Person name:@"Dee" age:20];
        [ac setFilterPredicate:[NSPredicate predicateWithFormat:@"age > 30"]];
        [ac addObject:dee];
        show("added Dee (filter cleared, at the end, selected)", ac);
        printf("  filter %s\n", str([ac filterPredicate]));
        [ac rearrangeObjects];
        show("rearranged", ac);
        Person *eve = [Person name:@"Eve" age:50];
        [ac insertObject:eve atArrangedObjectIndex:1];
        show("inserted Eve at 1", ac);
        printf("  content %s\n", [[[ac content] componentsJoinedByString:@","] UTF8String]);
        [ac setSelectsInsertedObjects:NO];
        [ac addObjects:@[ [Person name:@"Fay" age:61], [Person name:@"Gus" age:19] ]];
        show("added Fay and Gus, not selecting them", ac);
        [ac setSelectsInsertedObjects:YES];
        [ac removeObjectAtArrangedObjectIndex:1];
        show("removed Eve (selected): the next one", ac);
        [ac setSelectionIndex:[[ac arrangedObjects] count] - 1];
        [ac removeObjects:@[ [ac arrangedObjects][[[ac arrangedObjects] count] - 1] ]];
        show("removed the last (selected): the new last", ac);
        [ac setAvoidsEmptySelection:NO];
        [ac remove:nil];
        show("remove: (not yet)", ac);
        turn();
        show("remove: (next turn), not avoiding an empty selection", ac);
        [ac setAvoidsEmptySelection:YES];
        [w dump:"adding and removing"];
        [ac add:nil];
        printf("add: %lu arranged before the turn,", (unsigned long)[[ac arrangedObjects] count]);
        turn();
        printf(" %lu after; the new one a %s, selected %s\n", (unsigned long)[[ac arrangedObjects] count],
               [[ac selectedObjects][0] isKindOfClass:[NSMutableDictionary class]] ? "mutable dictionary" : "?",
               [rows([ac selectionIndexes]) UTF8String]);
        [ac remove:nil];
        turn();
        [ac setSelectionIndex:1];
        [ac setObjectClass:[Person class]];
        [ac insert:nil];
        turn();
        [(Person *)ac.selectedObjects[0] setName:@"Hal"];
        show("insert: at the selection", ac);
        [ac setEditable:NO];
        printf("not editable: can add %d, can insert %d, can remove %d\n", [ac canAdd], [ac canInsert], [ac canRemove]);
        [ac setEditable:YES];
        [w dump:"the actions"];

        /* ---- automatic rearranging ---- */
        [ac setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
        [ac setAutomaticallyRearrangesObjects:YES];
        [ac setFilterPredicate:[NSPredicate predicateWithFormat:@"age < 60 AND nick == nil"]];
        printf("rearrangement key paths: %s\n", [[[ac automaticRearrangementKeyPaths] componentsJoinedByString:@","] UTF8String]);
        show("rearranging by itself", ac);
        bob.name = @"Zed";
        show("Bob renamed Zed", ac);
        cy.nick = @"C";
        show("Cy given a nick (filtered out)", ac);
        cy.nick = nil;
        bob.name = @"Bob";
        [ac setAutomaticallyRearrangesObjects:NO];
        [ac setFilterPredicate:nil];
        bob.name = @"Aaron";
        show("no longer rearranging, Bob renamed Aaron", ac);
        bob.name = @"Bob";
        [ac rearrangeObjects];
        [w dump:"rearranging"];
        [ac removeObserver:w forKeyPath:@"selectionIndexes"];
        [ac removeObserver:w forKeyPath:@"arrangedObjects.name"];
        [ac removeObserver:w forKeyPath:@"selection.name"];
        [ac removeObserver:w forKeyPath:@"arrangedObjects.@count"];

        /* ---- a set as content ---- */
        NSArrayController *sc = [[NSArrayController alloc] initWithContent:[NSSet setWithObjects:ann, bob, cy, nil]];
        [sc setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ]];
        show("a set, sorted by age", sc);
        [sc addObject:dee];
        printf("  added to the set: content a set %d of %lu\n", [[sc content] isKindOfClass:[NSSet class]],
               (unsigned long)[[sc content] count]);

        /* ---- bound content and selection ---- */
        Library *lib = [[Library alloc] init];
        [lib.people addObjectsFromArray:@[ ann, bob, cy ]];
        NSArrayController *bc = [[NSArrayController alloc] init];
        [bc bind:NSContentArrayBinding toObject:lib withKeyPath:@"people" options:nil];
        [bc bind:NSSelectionIndexesBinding toObject:lib withKeyPath:@"picked" options:nil];
        show("bound to the library", bc);
        printf("  library picked %s\n", [rows(lib.picked) UTF8String]);
        [bc addObject:dee];
        [lib dump];
        show("added Dee through the controller", bc);
        printf("  library has %s, picked %s\n", [[lib.people componentsJoinedByString:@","] UTF8String],
               [rows(lib.picked) UTF8String]);
        [bc insertObject:eve atArrangedObjectIndex:0];
        [lib dump];
        [bc removeObjectAtArrangedObjectIndex:2];
        [lib dump];
        show("inserted Eve at 0, removed the third", bc);
        printf("  library has %s\n", [[lib.people componentsJoinedByString:@","] UTF8String]);
        [[lib mutableArrayValueForKey:@"people"] addObject:[Person name:@"Ike" age:3]];
        [lib dump];
        show("the library added Ike", bc);
        lib.picked = [NSIndexSet indexSetWithIndex:1];
        show("the library picked 1", bc);
        lib.people = [NSMutableArray arrayWithObjects:cy, bob, nil];
        show("the library's people replaced", bc);
        printf("  info: %s\n", [[[bc infoForBinding:NSContentArrayBinding] objectForKey:NSObservedKeyPathKey] UTF8String]);
        [bc unbind:NSSelectionIndexesBinding];
        [bc unbind:NSContentArrayBinding];

        /* ---- a table bound to a controller ---- */
        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        [win makeKeyAndOrderFront:nil];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 360, 260)];
        NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 340, 100)];
        NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [nameCol setTitle:@"Name"];
        [nameCol setWidth:120];
        NSTableColumn *ageCol = [[NSTableColumn alloc] initWithIdentifier:@"age"];
        [ageCol setTitle:@"Age"];
        [ageCol setWidth:60];
        NSTableColumn *nickCol = [[NSTableColumn alloc] initWithIdentifier:@"nick"];
        [nickCol setTitle:@"Nick"];
        [nickCol setWidth:80];
        [tv addTableColumn:nameCol];
        [tv addTableColumn:ageCol];
        [tv addTableColumn:nickCol];
        [tv setAllowsMultipleSelection:YES];
        [scroll setDocumentView:tv];
        [[win contentView] addSubview:scroll];

        NSArrayController *people = [[NSArrayController alloc] initWithContent:[NSMutableArray arrayWithObjects:cy, ann, bob, nil]];
        [people setObjectClass:[Person class]];
        [nameCol bind:NSValueBinding toObject:people withKeyPath:@"arrangedObjects.name" options:nil];
        [ageCol bind:NSValueBinding toObject:people withKeyPath:@"arrangedObjects.age" options:nil];
        [nickCol bind:NSValueBinding toObject:people withKeyPath:@"arrangedObjects.nick"
              options:@{NSNullPlaceholderBindingOption : @"(none)", NSCreatesSortDescriptorBindingOption : @NO}];
        [nickCol bind:NSHeaderTitleBinding toObject:people withKeyPath:@"arrangedObjects.@count" options:nil];
        printf("table bound to: content %s, selectionIndexes %s, sortDescriptors %s\n",
               [[[tv infoForBinding:NSContentBinding] objectForKey:NSObservedKeyPathKey] UTF8String],
               [[[tv infoForBinding:NSSelectionIndexesBinding] objectForKey:NSObservedKeyPathKey] UTF8String],
               [[[tv infoForBinding:NSSortDescriptorsBinding] objectForKey:NSObservedKeyPathKey] UTF8String]);
        printf("sort prototypes: %s, %s, %s; nick column titled %s; exposes %s\n",
               str([[nameCol sortDescriptorPrototype] key]), str([[ageCol sortDescriptorPrototype] key]),
               str([nickCol sortDescriptorPrototype]), [[nickCol title] UTF8String],
               [[[nameCol exposedBindings] componentsJoinedByString:@","] UTF8String]);
        table("bound", tv);

        click(win, tv, NSMakePoint(20, NSMidY([tv rectOfRow:2])), 1, 0);
        printf("clicked row 2: controller %s, selection.name %s\n", [rows([people selectionIndexes]) UTF8String],
               str([people valueForKeyPath:@"selection.name"]));
        click(win, tv, NSMakePoint(20, NSMidY([tv rectOfRow:0])), 1, NSEventModifierFlagCommand);
        printf("command-clicked row 0: controller %s, selection.name %s\n", [rows([people selectionIndexes]) UTF8String],
               str([people valueForKeyPath:@"selection.name"]));
        [people setSelectionIndex:1];
        printf("controller selected 1: table %s\n", [rows([tv selectedRowIndexes]) UTF8String]);
        ann.name = @"Annie";
        ann.nick = @"A";
        table("Ann renamed and given a nick", tv);
        ann.name = @"Ann";
        ann.nick = nil;

        NSTableHeaderView *header = [tv headerView];
        click(win, header, NSMakePoint(NSMidX([header headerRectOfColumn:0]), 14), 1, 0);
        printf("clicked Name's title: controller sorts by %s\n", [[[people sortDescriptors] description] UTF8String]);
        table("sorted by name", tv);
        click(win, header, NSMakePoint(NSMidX([header headerRectOfColumn:0]), 14), 1, 0);
        table("clicked again: descending", tv);
        click(win, header, NSMakePoint(NSMidX([header headerRectOfColumn:1]), 14), 1, 0);
        printf("clicked Age's title: %lu descriptors, first %s\n", (unsigned long)[[people sortDescriptors] count],
               str([[[people sortDescriptors] firstObject] key]));
        table("sorted by age", tv);
        click(win, header, NSMakePoint(NSMidX([header headerRectOfColumn:2]), 14), 1, 0);
        printf("clicked Nick's title (no prototype): first still %s\n", str([[[people sortDescriptors] firstObject] key]));
        [people setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
        printf("the controller sorted by name: the table's descriptors %s\n", str([[[tv sortDescriptors] firstObject] key]));

        /* a cell edited in place */
        [people setSelectionIndex:1];
        NSRect f = [tv frameOfCellAtColumn:0 row:1];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        printf("double click on row 1's name: edited row %ld column %ld\n", (long)[tv editedRow], (long)[tv editedColumn]);
        type(win, @"Bea");
        key(win, '\r');
        printf("typed Bea, Return: %s, %s, %s; edited row %ld\n", [ann.name UTF8String], [bob.name UTF8String],
               [cy.name UTF8String], (long)[tv editedRow]);
        table("edited", tv);
        f = [tv frameOfCellAtColumn:2 row:1];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"Bee");
        key(win, '\r');
        printf("nick edited: %s\n", str([[people selectedObjects][0] nick]));

        /* rows through the controller */
        [people addObject:[Person name:@"Jo" age:8]];
        table("Jo added", tv);
        [people remove:nil];
        turn();
        table("remove: Jo", tv);
        printf("nick column titled %s\n", [[nickCol title] UTF8String]);
        [people setContent:nil];
        table("no content", tv);
        printf("selection.name %s\n", str([people valueForKeyPath:@"selection.name"]));
        [nameCol unbind:NSValueBinding];
        [ageCol unbind:NSValueBinding];
        [nickCol unbind:NSValueBinding];
        [nickCol unbind:NSHeaderTitleBinding];
        [tv unbind:NSContentBinding];
        [tv unbind:NSSelectionIndexesBinding];
        [tv unbind:NSSortDescriptorsBinding];
        printf("unbound: %ld rows\n", (long)[tv numberOfRows]);
    }
    return 0;
}
