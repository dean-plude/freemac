/* SPDX-License-Identifier: GPL-3.0-or-later
 * Validation and conditions through bindings (Ferry 0.20.0), with no
 * display. NSValidatesImmediately: a value typed into a bound field is put
 * to the model's validate<Key>:error: (through validateValue:forKeyPath:
 * error:, and through an object controller's and an array controller's
 * selection) before it is written; a refused value isn't written, the
 * error is presented (the application's delegate sees it and the alert is
 * answered by FERRY_ALERT_ANSWER) and the field shows the model's value
 * again; a value the model changes is written changed, and shown. The same
 * for a cell-based table's column and a control in a view-based table's
 * cell view. NSRaisesForNotApplicableKeys, on and off. Conditions: a bound
 * check box disabled and a bound field made uneditable with no selection,
 * with a controller that isn't editable (followed as it changes), with
 * multiple values when NSAllowsEditingMultipleValuesSelection is off, an
 * enabled binding taken together with them, the two NSConditionallySets
 * options set by hand, and what the views were given back when unbound.
 * Then the array controller's content options: NSDeletesObjectsOnRemove,
 * NSSelectsAllWhenSettingContent and NSHandlesContentAsCompoundValue (into
 * an owner's immutable array and into the user defaults). */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

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
/* Types s into a field, replacing what it shows, and ends with Return. */
static void enter(NSWindow *w, NSTextField *f, NSString *s)
{
    [w makeFirstResponder:f];
    type(w, s);
    key(w, '\r');
}

/* ---- the model ---------------------------------------------------------------------------- */

static int checks;   /* validate<Key>:error: calls */

@interface Person : NSObject
@property (copy) NSString *name;
@property (strong) NSNumber *age;
@property BOOL member;
@end
@implementation Person
+ (instancetype)name:(NSString *)n age:(NSInteger)a
{
    Person *p = [[Person alloc] init];
    p.name = n;
    p.age = @(a);
    return p;
}
/* An age is a whole number from 0; past 130 it is taken as 130. */
- (BOOL)validateAge:(id *)value error:(NSError **)error
{
    checks++;
    id v = *value;
    NSInteger n = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : -1;
    if (!v || n < 0 || ([v isKindOfClass:[NSString class]] && ![[NSString stringWithFormat:@"%ld", (long)n] isEqualToString:v])) {
        if (error)
            *error = [NSError errorWithDomain:@"People" code:1
                                     userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"“%@” isn't an age.", v]}];
        return NO;
    }
    *value = @(n > 130 ? 130 : n);
    return YES;
}
/* A name has no spaces around it, and isn't empty. */
- (BOOL)validateName:(id *)value error:(NSError **)error
{
    checks++;
    NSString *s = [*value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![s length]) {
        if (error)
            *error = [NSError errorWithDomain:@"People" code:2 userInfo:@{NSLocalizedDescriptionKey : @"A name is needed."}];
        return NO;
    }
    *value = s;
    return YES;
}
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@", _name, _age]; }
@end

/* Sees each error before it is shown. */
@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation AppDelegate
- (NSError *)application:(NSApplication *)app willPresentError:(NSError *)error
{
    printf("  presented: %s (%s %ld)\n", [[error localizedDescription] UTF8String], [[error domain] UTF8String],
           (long)[error code]);
    return error;
}
@end

/* A stand-in for a managed object context: notes what it is told to delete. */
@interface Context : NSObject
@property (strong) NSMutableArray *deleted;
@end
@implementation Context
- (void)deleteObject:(id)o { [_deleted addObject:[o name]]; }
@end
@interface Managed : NSObject
@property (copy) NSString *name;
@property (weak) Context *managedObjectContext;
@end
@implementation Managed
@end

/* An owner whose list is an immutable array, set whole. */
@interface Owner : NSObject {
    NSArray *_list;
}
@property (strong) NSMutableArray *items;
@property (strong) NSArray *everyone;
@property int sets;
- (NSArray *)list;
- (void)setList:(NSArray *)list;
@end
@implementation Owner
- (NSArray *)list { return _list; }
- (void)setList:(NSArray *)list
{
    _sets++;
    _list = list;
}
@end

/* Makes view-based rows: a cell view with a field bound to objectValue.age, validated. */
@interface Rows : NSObject <NSTableViewDelegate>
@end
@implementation Rows
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
    NSTableCellView *v = [tv makeViewWithIdentifier:@"age" owner:self];
    if (!v) {
        v = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [v setIdentifier:@"age"];
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(2, 2, 90, 16)];
        [v addSubview:f];
        [v setTextField:f];
        [f bind:NSValueBinding toObject:v withKeyPath:@"objectValue.age"
            options:@{NSValidatesImmediatelyBindingOption : @YES}];
    }
    return v;
}
@end

static void conditions(const char *what, NSTextField *f, NSButton *b)
{
    printf("%s: field enabled %d editable %d \"%s\"%s%s, check box enabled %d\n", what, [f isEnabled], [f isEditable],
           [[f stringValue] UTF8String], [f placeholderString] ? " placeholder " : "",
           [f placeholderString] ? [[f placeholderString] UTF8String] : "", [b isEnabled]);
}

int main(void)
{
    @autoreleasepool {
        setenv("FERRY_ALERT_ANSWER", "OK", 1);
        [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500) styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        NSView *content = [win contentView];
        [win makeKeyAndOrderFront:nil];

        /* ---- NSValidatesImmediately through an object controller ---- */
        Person *ann = [Person name:@"Ann" age:34];
        NSObjectController *one = [[NSObjectController alloc] initWithContent:ann];
        NSTextField *age = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 460, 120, 22)];
        NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 460, 120, 22)];
        NSTextField *loose = [[NSTextField alloc] initWithFrame:NSMakeRect(270, 460, 120, 22)];
        [content addSubview:age];
        [content addSubview:name];
        [content addSubview:loose];
        [age bind:NSValueBinding toObject:one withKeyPath:@"selection.age"
            options:@{NSValidatesImmediatelyBindingOption : @YES}];
        [name bind:NSValueBinding toObject:one withKeyPath:@"selection.name"
            options:@{NSValidatesImmediatelyBindingOption : @YES}];
        [loose bind:NSValueBinding toObject:one withKeyPath:@"selection.age" options:nil];
        printf("bound: age \"%s\", name \"%s\"; %d checks so far\n", [[age stringValue] UTF8String],
               [[name stringValue] UTF8String], checks);
        enter(win, age, @"-3");
        printf("typed -3: model %s, field \"%s\", %d checks\n", str(ann), [[age stringValue] UTF8String], checks);
        enter(win, age, @"old");
        printf("typed old: model %s, field \"%s\"\n", str(ann), [[age stringValue] UTF8String]);
        enter(win, age, @"200");
        printf("typed 200: model %s (a number %d), field \"%s\"\n", str(ann), [ann.age isKindOfClass:[NSNumber class]],
               [[age stringValue] UTF8String]);
        enter(win, age, @"41");
        printf("typed 41: model %s, field \"%s\", the unvalidated field \"%s\"\n", str(ann), [[age stringValue] UTF8String],
               [[loose stringValue] UTF8String]);
        enter(win, name, @"  Anne  ");
        printf("typed \"  Anne  \": model \"%s\", field \"%s\"\n", [ann.name UTF8String], [[name stringValue] UTF8String]);
        enter(win, name, @"   ");
        printf("typed spaces: model \"%s\", field \"%s\"\n", [ann.name UTF8String], [[name stringValue] UTF8String]);
        int before = checks;
        enter(win, loose, @"-7");
        printf("without the option: typed -7, model %s, no check %d; the validated field \"%s\"\n", str(ann),
               checks == before, [[age stringValue] UTF8String]);
        ann.age = @41;

        /* the same check, asked of a controller's selection */
        id v = @"12";
        NSError *error = nil;
        BOOL ok = [[one selection] validateValue:&v forKeyPath:@"age" error:&error];
        printf("selection's validateValue: 12 -> %d %s; ", ok, str(v));
        v = @"x";
        ok = [[one selection] validateValue:&v forKeyPath:@"age" error:&error];
        printf("x -> %d (%s)\n", ok, [[error localizedDescription] UTF8String]);

        /* ---- through an array controller's selection, and a table's column ---- */
        Person *bo = [Person name:@"Bo" age:7], *cy = [Person name:@"Cy" age:60];
        Owner *owner = [[Owner alloc] init];
        owner.everyone = @[ ann, bo, cy ];
        NSArrayController *people = [[NSArrayController alloc] init];
        [people bind:NSContentArrayBinding toObject:owner withKeyPath:@"everyone" options:nil];
        NSTextField *ages = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 430, 120, 22)];
        [content addSubview:ages];
        [ages bind:NSValueBinding toObject:people withKeyPath:@"selection.age"
            options:@{NSValidatesImmediatelyBindingOption : @YES}];
        [people setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]];
        printf("Bo and Cy selected: field placeholder %s\n", str([ages placeholderString]));
        enter(win, ages, @"-1");
        printf("typed -1 for both: %s, %s, field placeholder %s\n", str(bo), str(cy), str([ages placeholderString]));
        enter(win, ages, @"500");
        printf("typed 500 for both: %s, %s, field \"%s\"\n", str(bo), str(cy), [[ages stringValue] UTF8String]);

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 300, 280, 120)];
        NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 280, 120)];
        NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        NSTableColumn *ageCol = [[NSTableColumn alloc] initWithIdentifier:@"age"];
        [nameCol setWidth:120];
        [ageCol setWidth:80];
        [tv addTableColumn:nameCol];
        [tv addTableColumn:ageCol];
        [scroll setDocumentView:tv];
        [content addSubview:scroll];
        [nameCol bind:NSValueBinding toObject:people withKeyPath:@"arrangedObjects.name"
              options:@{NSValidatesImmediatelyBindingOption : @YES}];
        [ageCol bind:NSValueBinding toObject:people withKeyPath:@"arrangedObjects.age"
             options:@{NSValidatesImmediatelyBindingOption : @YES}];
        [people setSelectionIndex:1];
        NSRect f = [tv frameOfCellAtColumn:1 row:1];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"ten");
        key(win, '\r');
        printf("table: typed ten in Bo's age: %s, cell \"%s\"\n", str(bo), [[[tv preparedCellAtColumn:1 row:1] stringValue] UTF8String]);
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @"9");
        key(win, '\r');
        printf("table: typed 9: %s (a number %d), cell \"%s\"\n", str(bo), [bo.age isKindOfClass:[NSNumber class]],
               [[[tv preparedCellAtColumn:1 row:1] stringValue] UTF8String]);
        f = [tv frameOfCellAtColumn:0 row:2];
        click(win, tv, NSMakePoint(NSMidX(f), NSMidY(f)), 2, 0);
        type(win, @" Cyd ");
        key(win, '\r');
        printf("table: typed \" Cyd \" in Cy's name: \"%s\"\n", [cy.name UTF8String]);

        /* ---- a control in a view-based table's cell view ---- */
        NSScrollView *scroll2 = [[NSScrollView alloc] initWithFrame:NSMakeRect(300, 300, 200, 120)];
        NSTableView *cards = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
        NSTableColumn *cardCol = [[NSTableColumn alloc] initWithIdentifier:@"card"];
        [cardCol setWidth:180];
        [cards addTableColumn:cardCol];
        Rows *rowsDelegate = [[Rows alloc] init];
        [cards setDelegate:rowsDelegate];
        [scroll2 setDocumentView:cards];
        [content addSubview:scroll2];
        [cards bind:NSContentBinding toObject:people withKeyPath:@"arrangedObjects" options:nil];
        NSTableCellView *cv = [cards viewAtColumn:0 row:0 makeIfNecessary:NO];
        printf("cell views: %s %s %s\n", [[[[cards viewAtColumn:0 row:0 makeIfNecessary:NO] textField] stringValue] UTF8String],
               [[[[cards viewAtColumn:0 row:1 makeIfNecessary:NO] textField] stringValue] UTF8String],
               [[[[cards viewAtColumn:0 row:2 makeIfNecessary:NO] textField] stringValue] UTF8String]);
        enter(win, [cv textField], @"-2");
        printf("cell view: typed -2: %s, field \"%s\"\n", str(ann), [[[cv textField] stringValue] UTF8String]);
        enter(win, [cv textField], @"140");
        printf("cell view: typed 140: %s, field \"%s\", the other field \"%s\"\n", str(ann),
               [[[cv textField] stringValue] UTF8String], [[age stringValue] UTF8String]);
        [cards unbind:NSContentBinding];
        [ageCol unbind:NSValueBinding];
        [nameCol unbind:NSValueBinding];

        /* ---- NSRaisesForNotApplicableKeys ---- */
        NSObjectController *odd = [[NSObjectController alloc] initWithContent:ann];
        NSTextField *colour = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 260, 120, 22)];
        [content addSubview:colour];
        [colour setStringValue:@"as it was"];
        [colour bind:NSValueBinding toObject:odd withKeyPath:@"selection.colour" options:nil];
        printf("selection.colour, no option: field \"%s\", placeholder %s\n", [[colour stringValue] UTF8String],
               str([colour placeholderString]));
        [colour unbind:NSValueBinding];
        [colour bind:NSValueBinding toObject:odd withKeyPath:@"selection.colour"
             options:@{NSRaisesForNotApplicableKeysBindingOption : @NO}];
        printf("option NO: field \"%s\", placeholder %s, enabled %d editable %d\n", [[colour stringValue] UTF8String],
               str([colour placeholderString]), [colour isEnabled], [colour isEditable]);
        [colour unbind:NSValueBinding];
        @try {
            [colour bind:NSValueBinding toObject:odd withKeyPath:@"selection.colour"
                 options:@{NSRaisesForNotApplicableKeysBindingOption : @YES}];
            printf("option YES: no exception\n");
        } @catch (NSException *e) {
            printf("option YES: raised %s\n", [[e name] UTF8String]);
        }
        [colour unbind:NSValueBinding];

        /* ---- conditions ---- */
        bo.member = YES;
        NSArrayController *few = [[NSArrayController alloc] initWithContent:[NSMutableArray arrayWithObjects:ann, bo, nil]];
        [few setAvoidsEmptySelection:NO];
        [few setSelectionIndexes:[NSIndexSet indexSet]];
        NSTextField *who = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 220, 120, 22)];
        NSButton *member = [[NSButton alloc] initWithFrame:NSMakeRect(140, 220, 120, 22)];
        [member setButtonType:NSButtonTypeSwitch];
        [content addSubview:who];
        [content addSubview:member];
        [who bind:NSValueBinding toObject:few withKeyPath:@"selection.name" options:nil];
        [member bind:NSValueBinding toObject:few withKeyPath:@"selection.member" options:nil];
        conditions("no selection", who, member);
        [few setSelectionIndex:0];
        conditions("Ann selected", who, member);
        [few setEditable:NO];
        conditions("controller not editable", who, member);
        [few setEditable:YES];
        conditions("editable again", who, member);
        [few setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
        conditions("two selected", who, member);
        [who unbind:NSValueBinding];
        [who bind:NSValueBinding toObject:few withKeyPath:@"selection.name"
            options:@{NSAllowsEditingMultipleValuesSelectionBindingOption : @NO}];
        [member unbind:NSValueBinding];
        [member bind:NSValueBinding toObject:few withKeyPath:@"selection.member"
             options:@{NSAllowsEditingMultipleValuesSelectionBindingOption : @NO}];
        conditions("two selected, editing multiple values off", who, member);
        [few setSelectionIndex:1];
        conditions("Bo selected", who, member);

        /* an enabled binding, taken together with the conditions */
        NSMutableDictionary *flags = [NSMutableDictionary dictionaryWithObject:@NO forKey:@"on"];
        [member bind:NSEnabledBinding toObject:flags withKeyPath:@"on" options:nil];
        conditions("enabled bound to NO", who, member);
        [flags setValue:@YES forKey:@"on"];
        conditions("enabled bound to YES", who, member);
        [few setSelectionIndexes:[NSIndexSet indexSet]];
        conditions("enabled YES, no selection", who, member);
        [few setSelectionIndex:0];
        [member unbind:NSEnabledBinding];

        /* the options set by hand */
        [few setSelectionIndexes:[NSIndexSet indexSet]];
        [who unbind:NSValueBinding];
        [who bind:NSValueBinding toObject:few withKeyPath:@"selection.name"
            options:@{NSConditionallySetsEnabledBindingOption : @YES, NSConditionallySetsEditableBindingOption : @NO}];
        [member unbind:NSValueBinding];
        [member bind:NSValueBinding toObject:few withKeyPath:@"selection.member"
             options:@{NSConditionallySetsEnabledBindingOption : @NO}];
        conditions("no selection, sets enabled on the field, off on the check box", who, member);
        [who setEditable:NO];
        [who unbind:NSValueBinding];
        [member unbind:NSValueBinding];
        [who bind:NSValueBinding toObject:few withKeyPath:@"selection.name" options:nil];
        [member bind:NSValueBinding toObject:few withKeyPath:@"selection.member" options:nil];
        conditions("bound again, the field set uneditable beforehand", who, member);
        [who unbind:NSValueBinding];
        [member unbind:NSValueBinding];
        conditions("unbound", who, member);
        [who setEditable:YES];
        [few setSelectionIndex:0];

        /* ---- NSDeletesObjectsOnRemove ---- */
        Context *moc = [[Context alloc] init];
        moc.deleted = [NSMutableArray array];
        NSMutableArray *things = [NSMutableArray array];
        for (NSString *n in @[ @"lamp", @"desk", @"rug" ]) {
            Managed *m = [[Managed alloc] init];
            m.name = n;
            m.managedObjectContext = moc;
            [things addObject:m];
        }
        owner.items = things;
        NSArrayController *stuff = [[NSArrayController alloc] init];
        [stuff bind:NSContentArrayBinding toObject:owner withKeyPath:@"items"
            options:@{NSDeletesObjectsOnRemoveBindingsOption : @YES}];
        [stuff setSelectionIndex:1];
        [stuff remove:nil];
        turn();
        [stuff removeObjectAtArrangedObjectIndex:0];
        printf("deletes on remove: %lu items left, deleted %s\n", (unsigned long)[owner.items count],
               [[moc.deleted componentsJoinedByString:@","] UTF8String]);
        NSArrayController *keep = [[NSArrayController alloc] init];
        [keep bind:NSContentArrayBinding toObject:owner withKeyPath:@"items" options:nil];
        [keep removeObjectAtArrangedObjectIndex:0];
        printf("without the option: %lu items left, deleted %s\n", (unsigned long)[owner.items count],
               [[moc.deleted componentsJoinedByString:@","] UTF8String]);
        [stuff unbind:NSContentArrayBinding];
        [keep unbind:NSContentArrayBinding];

        /* ---- NSSelectsAllWhenSettingContent ---- */
        NSArrayController *all = [[NSArrayController alloc] init];
        [all bind:NSContentArrayBinding toObject:owner withKeyPath:@"everyone"
            options:@{NSSelectsAllWhenSettingContentBindingOption : @YES}];
        printf("selects all: bound %s", [rows([all selectionIndexes]) UTF8String]);
        [all setSelectionIndex:0];
        owner.everyone = @[ ann, bo ];
        printf(", content set again %s", [rows([all selectionIndexes]) UTF8String]);
        NSArrayController *plain = [[NSArrayController alloc] init];
        [plain setAvoidsEmptySelection:NO];
        [plain bind:NSContentArrayBinding toObject:owner withKeyPath:@"everyone" options:nil];
        owner.everyone = @[ ann, bo, cy ];
        printf("; without it %s, the other %s\n", [rows([plain selectionIndexes]) UTF8String],
               [rows([all selectionIndexes]) UTF8String]);
        [all unbind:NSContentArrayBinding];
        [plain unbind:NSContentArrayBinding];

        /* ---- NSHandlesContentAsCompoundValue ---- */
        [owner setList:@[ @"a", @"b" ]];
        owner.sets = 0;
        NSArrayController *list = [[NSArrayController alloc] init];
        [list bind:NSContentArrayBinding toObject:owner withKeyPath:@"list"
            options:@{NSHandlesContentAsCompoundValueBindingOption : @YES}];
        [list addObject:@"c"];
        [list insertObject:@"z" atArrangedObjectIndex:0];
        [list removeObjectAtArrangedObjectIndex:1];
        printf("compound value: owner's list %s set %d times, immutable %d; controller %s\n",
               [[[owner list] componentsJoinedByString:@","] UTF8String], owner.sets,
               ![[owner list] isKindOfClass:[NSMutableArray class]],
               [[[list arrangedObjects] componentsJoinedByString:@","] UTF8String]);
        [list unbind:NSContentArrayBinding];

        NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
        [[NSUserDefaults standardUserDefaults] setObject:@[ @"red", @"green" ] forKey:@"FerryColours"];
        NSArrayController *colours = [[NSArrayController alloc] init];
        [colours bind:NSContentArrayBinding toObject:udc withKeyPath:@"values.FerryColours"
              options:@{NSHandlesContentAsCompoundValueBindingOption : @YES}];
        [colours addObject:@"blue"];
        [colours removeObjectAtArrangedObjectIndex:0];
        printf("compound value in the defaults: %s\n",
               [[[[NSUserDefaults standardUserDefaults] arrayForKey:@"FerryColours"] componentsJoinedByString:@","] UTF8String]);
        [colours unbind:NSContentArrayBinding];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"FerryColours"];

        [win orderOut:nil];
    }
    return 0;
}
