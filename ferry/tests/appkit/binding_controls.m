/* SPDX-License-Identifier: GPL-3.0-or-later
 * Bindings that follow and write back (Ferry 0.17.0), with no display:
 * text fields, check boxes, pop-up buttons and sliders bound to a model's
 * key paths (through a to-one relationship too) show its changes, and
 * what the user does in them is written back; the options (value
 * transformers, the null placeholder, continuous updates); several
 * enabled and hidden bindings together; NSObjectController's content and
 * selection.* key paths (with no content: the no-selection placeholder);
 * NSUserDefaultsController's values.* key paths, changed through it or in
 * the defaults; exposedBindings and infoForBinding:; and the same bindings
 * loaded from a nib (Bindings.nib, from make_nibs.py). */
#import <Cocoa/Cocoa.h>

@interface NSWindow (FerryPeek)
- (NSView *)_overlayView;
@end
@interface NSView (FerryMenuPeek)
- (NSRect)rectOfItemAtIndex:(NSInteger)index;
@end

static NSPoint mid(NSRect r) { return NSMakePoint(NSMidX(r), NSMidY(r)); }
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
static const char *str(id v)
{
    if (!v)
        return "nil";
    return [[v description] UTF8String];
}

@interface Pet : NSObject
@property (copy) NSString *name;
@end
@implementation Pet
@end

@interface Person : NSObject
@property (nonatomic, copy) NSString *name, *nickname;
@property (copy) NSString *size;
@property NSInteger sizeIndex;
@property BOOL married, adult, away;
@property double level;
@property (strong) Pet *pet;
@property (strong) NSMutableArray *log;
@end
@implementation Person
- (instancetype)init
{
    if ((self = [super init]))
        _log = [NSMutableArray array];
    return self;
}
- (void)setName:(NSString *)name
{
    [_log addObject:[NSString stringWithFormat:@"setName: %@", name]];
    _name = [name copy];
}
- (void)setNickname:(NSString *)n
{
    [_log addObject:[NSString stringWithFormat:@"setNickname: %@", n ?: @"nil"]];
    _nickname = [n copy];
}
- (void)dump
{
    for (NSString *s in _log)
        printf("  model: %s\n", [s UTF8String]);
    [_log removeAllObjects];
}
@end

@interface BindingsOwner : NSObject
@property (strong) NSWindow *window;
@property (strong) NSTextField *field;
@property (strong) NSSlider *slider;
@property (strong) NSButton *check;
@property (strong) NSObjectController *controller;
@end
@implementation BindingsOwner
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 300) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];
        NSView *cv = [w contentView];
        Person *p = [[Person alloc] init];
        p.name = @"Ada";
        p.adult = YES;
        [p.log removeAllObjects];

        /* ---- a text field's value ---- */
        NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 260, 150, 22)];
        NSTextField *other = [[NSTextField alloc] initWithFrame:NSMakeRect(170, 260, 150, 22)];
        [cv addSubview:name];
        [cv addSubview:other];
        [name bind:NSValueBinding toObject:p withKeyPath:@"name" options:nil];
        printf("bound: %s\n", [[name stringValue] UTF8String]);
        p.name = @"Grace";
        printf("model changed: %s\n", [[name stringValue] UTF8String]);
        [p dump];
        [w makeFirstResponder:name];
        type(w, @"Lise");
        printf("typing Lise: model %s\n", str(p.name));
        [w makeFirstResponder:other];
        printf("editing ended: model %s\n", str(p.name));
        [p dump];
        [w makeFirstResponder:name];
        [w makeFirstResponder:other];
        printf("no typing: nothing written\n");
        [p dump];
        [w makeFirstResponder:name];
        type(w, @"Mary");
        key(w, '\r');
        printf("typed Mary, Return: model %s\n", str(p.name));
        [p dump];
        [w makeFirstResponder:other];
        [p dump];

        /* continuously */
        [name bind:NSValueBinding toObject:p withKeyPath:@"name"
             options:@{NSContinuouslyUpdatesValueBindingOption : @YES}];
        [w makeFirstResponder:name];
        type(w, @"Jo");
        printf("continuously, typed Jo: model %s, field %s\n", str(p.name), [[name stringValue] UTF8String]);
        [w makeFirstResponder:other];
        [p dump];
        [name unbind:NSValueBinding];

        /* a null placeholder */
        NSTextField *nick = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 230, 150, 22)];
        [cv addSubview:nick];
        [nick setPlaceholderString:@"its own"];
        [nick bind:NSValueBinding toObject:p withKeyPath:@"nickname"
             options:@{NSNullPlaceholderBindingOption : @"no nickname"}];
        printf("nil nickname: value \"%s\", placeholder %s\n", [[nick stringValue] UTF8String],
               str([nick placeholderString]));
        p.nickname = @"Addie";
        printf("nickname Addie: value \"%s\", placeholder %s\n", [[nick stringValue] UTF8String],
               str([nick placeholderString]));
        [w makeFirstResponder:nick];
        key(w, 0x7f);   /* delete everything selected */
        [w makeFirstResponder:other];
        printf("emptied: model %s, placeholder %s\n", str(p.nickname), str([nick placeholderString]));
        [p dump];
        [nick unbind:NSValueBinding];
        printf("unbound: placeholder %s\n", str([nick placeholderString]));

        /* ---- a check box, through a transformer ---- */
        NSButton *single = [NSButton checkboxWithTitle:@"Single" target:nil action:NULL];
        [cv addSubview:single];
        [single bind:NSValueBinding toObject:p withKeyPath:@"married"
               options:@{NSValueTransformerNameBindingOption : NSNegateBooleanTransformerName}];
        printf("single (not married): state %ld\n", (long)[single state]);
        [single performClick:nil];
        printf("clicked: state %ld, married %d\n", (long)[single state], p.married);
        p.married = NO;
        printf("model unmarried: state %ld\n", (long)[single state]);

        /* enabled and enabled2 together, hidden and hidden2 together */
        NSButton *go = [NSButton buttonWithTitle:@"Go" target:nil action:NULL];
        [cv addSubview:go];
        [go bind:NSEnabledBinding toObject:p withKeyPath:@"adult" options:nil];
        [go bind:@"enabled2" toObject:p withKeyPath:@"married" options:nil];
        [go bind:NSHiddenBinding toObject:p withKeyPath:@"away" options:nil];
        [go bind:@"hidden2" toObject:p withKeyPath:@"nickname"
             options:@{NSValueTransformerNameBindingOption : NSIsNotNilTransformerName}];
        printf("adult, unmarried, here, no nickname: enabled %d, hidden %d\n", [go isEnabled], [go isHidden]);
        p.married = YES;
        printf("married: enabled %d\n", [go isEnabled]);
        p.adult = NO;
        printf("not adult: enabled %d\n", [go isEnabled]);
        p.nickname = @"Ace";
        printf("a nickname: hidden %d\n", [go isHidden]);
        p.nickname = nil;
        p.away = YES;
        printf("no nickname, away: hidden %d\n", [go isHidden]);
        [p dump];

        /* ---- through a to-one relationship ---- */
        NSTextField *pet = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 200, 150, 22)];
        [cv addSubview:pet];
        [pet bind:NSValueBinding toObject:p withKeyPath:@"pet.name" options:@{NSNullPlaceholderBindingOption : @"no pet"}];
        printf("no pet: \"%s\" (placeholder %s)\n", [[pet stringValue] UTF8String], str([pet placeholderString]));
        Pet *rex = [[Pet alloc] init];
        rex.name = @"Rex";
        p.pet = rex;
        printf("a pet: %s\n", [[pet stringValue] UTF8String]);
        rex.name = @"Rex II";
        printf("renamed: %s\n", [[pet stringValue] UTF8String]);
        Pet *tom = [[Pet alloc] init];
        tom.name = @"Tom";
        p.pet = tom;
        rex.name = @"Rex III";
        printf("another pet: %s (the old one not followed)\n", [[pet stringValue] UTF8String]);
        [w makeFirstResponder:pet];
        type(w, @"Felix");
        [w makeFirstResponder:other];
        printf("typed Felix: the pet is %s\n", str(tom.name));

        /* ---- pop-up buttons ---- */
        NSMutableDictionary *store = [@{@"sizes" : @[ @"Small", @"Medium", @"Large" ]} mutableCopy];
        NSPopUpButton *sizes = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, 160, 120, 25) pullsDown:NO];
        [cv addSubview:sizes];
        p.size = @"Large";
        [sizes bind:NSContentBinding toObject:store withKeyPath:@"sizes" options:nil];
        [sizes bind:NSSelectedObjectBinding toObject:p withKeyPath:@"size" options:nil];
        printf("pop-up: %s, chosen \"%s\"\n", [[[sizes itemTitles] componentsJoinedByString:@","] UTF8String],
               [[sizes titleOfSelectedItem] UTF8String]);
        p.size = @"Small";
        printf("model Small: chosen \"%s\"\n", [[sizes titleOfSelectedItem] UTF8String]);
        click(w, sizes, mid([sizes bounds]));
        NSView *ov = [w _overlayView];
        click(w, ov, mid([ov rectOfItemAtIndex:1]));
        printf("chose the second: model size %s\n", str(p.size));
        [store setValue:@[ @"Tiny", @"Small", @"Medium", @"Large", @"Huge" ] forKey:@"sizes"];
        printf("new content: %s, chosen \"%s\"\n", [[[sizes itemTitles] componentsJoinedByString:@","] UTF8String],
               [[sizes titleOfSelectedItem] UTF8String]);

        NSPopUpButton *byIndex = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 160, 120, 25) pullsDown:NO];
        [cv addSubview:byIndex];
        [byIndex addItemsWithTitles:@[ @"One", @"Two", @"Three" ]];
        p.sizeIndex = 2;
        [byIndex bind:NSSelectedIndexBinding toObject:p withKeyPath:@"sizeIndex" options:nil];
        printf("selectedIndex: chosen \"%s\"\n", [[byIndex titleOfSelectedItem] UTF8String]);
        click(w, byIndex, mid([byIndex bounds]));
        ov = [w _overlayView];
        click(w, ov, mid([ov rectOfItemAtIndex:0]));
        printf("chose the first: model index %ld\n", (long)p.sizeIndex);
        p.size = @"Two";
        [byIndex bind:NSSelectedValueBinding toObject:p withKeyPath:@"size" options:nil];
        printf("selectedValue too: chosen \"%s\"\n", [[byIndex titleOfSelectedItem] UTF8String]);
        click(w, byIndex, mid([byIndex bounds]));
        ov = [w _overlayView];
        click(w, ov, mid([ov rectOfItemAtIndex:2]));
        printf("chose the third: model size %s, index %ld\n", str(p.size), (long)p.sizeIndex);
        [byIndex unbind:NSSelectedValueBinding];

        /* ---- a slider ---- */
        NSSlider *level = [NSSlider sliderWithValue:0 minValue:0 maxValue:10 target:nil action:NULL];
        [level setFrame:NSMakeRect(10, 120, 200, 21)];
        [cv addSubview:level];
        p.level = 2.5;
        [level bind:NSValueBinding toObject:p withKeyPath:@"level" options:nil];
        printf("slider: %g\n", [level doubleValue]);
        p.level = 40;
        printf("model 40: slider %g (kept in its range)\n", [level doubleValue]);
        NSRect b = [level bounds];
        click(w, level, NSMakePoint(NSMidX(b), NSMidY(b)));
        printf("clicked in the middle: model level %g\n", p.level);

        /* ---- an object controller ---- */
        NSObjectController *oc = [[NSObjectController alloc] initWithContent:nil];
        NSTextField *sel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 90, 150, 22)];
        [cv addSubview:sel];
        [sel bind:NSValueBinding toObject:oc withKeyPath:@"selection.name" options:nil];
        printf("no content: \"%s\", placeholder %s\n", [[sel stringValue] UTF8String], str([sel placeholderString]));
        NSTextField *sel2 = [[NSTextField alloc] initWithFrame:NSMakeRect(170, 90, 150, 22)];
        [cv addSubview:sel2];
        [sel2 bind:NSValueBinding toObject:oc withKeyPath:@"selection.name"
              options:@{NSNoSelectionPlaceholderBindingOption : @"(none)"}];
        printf("its own no-selection placeholder: \"%s\" (placeholder %s)\n", [[sel2 stringValue] UTF8String],
               str([sel2 placeholderString]));
        [oc setContent:p];
        printf("content: \"%s\", placeholder %s; selected objects %lu\n", [[sel stringValue] UTF8String],
               str([sel placeholderString]), (unsigned long)[[oc selectedObjects] count]);
        p.name = @"Hedy";
        printf("model changed: %s and %s\n", [[sel stringValue] UTF8String], [[sel2 stringValue] UTF8String]);
        [w makeFirstResponder:sel];
        type(w, @"Emmy");
        [w makeFirstResponder:other];
        printf("typed Emmy: model %s, the other field %s\n", str(p.name), [[sel2 stringValue] UTF8String]);
        [p dump];
        printf("selection.name by key-value coding: %s\n", str([oc valueForKeyPath:@"selection.name"]));
        [oc setValue:@"Kurt" forKeyPath:@"selection.name"];
        printf("set through the selection: %s\n", str(p.name));
        Person *q = [[Person alloc] init];
        q.name = @"Alan";
        [oc setContent:q];
        p.name = @"not followed";
        printf("new content: %s; can remove %d, can add %d\n", [[sel stringValue] UTF8String], [oc canRemove],
               [oc canAdd]);
        [oc remove:nil];
        printf("removed: \"%s\" (placeholder %s)\n", [[sel stringValue] UTF8String], str([sel placeholderString]));
        [oc add:nil];
        printf("added: content is a %s\n", [[oc content] isKindOfClass:[NSMutableDictionary class]] ? "dictionary" : "?");
        [w makeFirstResponder:sel];
        type(w, @"Dict");
        [w makeFirstResponder:other];
        printf("typed Dict: content name %s\n", str([[oc content] objectForKey:@"name"]));
        [sel unbind:NSValueBinding];
        [sel2 unbind:NSValueBinding];

        /* ---- the user's defaults ---- */
        NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:@"FerryBindingFlag"];
        NSButton *flag = [NSButton checkboxWithTitle:@"Flag" target:nil action:NULL];
        [cv addSubview:flag];
        [flag bind:NSValueBinding toObject:udc withKeyPath:@"values.FerryBindingFlag" options:nil];
        printf("defaults: state %ld\n", (long)[flag state]);
        [flag performClick:nil];
        printf("clicked: default %d\n", [defaults boolForKey:@"FerryBindingFlag"]);
        [defaults setBool:NO forKey:@"FerryBindingFlag"];
        printf("default changed in the defaults: state %ld\n", (long)[flag state]);
        [[udc values] setValue:@YES forKey:@"FerryBindingFlag"];
        printf("through the controller: state %ld\n", (long)[flag state]);
        [flag unbind:NSValueBinding];
        [defaults removeObjectForKey:@"FerryBindingFlag"];

        /* ---- what is exposed, and recorded ---- */
        printf("text field exposes: %s\n", [[[name exposedBindings] componentsJoinedByString:@","] UTF8String]);
        printf("pop-up exposes: %s\n", [[[sizes exposedBindings] componentsJoinedByString:@","] UTF8String]);
        printf("slider exposes: %s\n", [[[level exposedBindings] componentsJoinedByString:@","] UTF8String]);
        NSDictionary *info = [go infoForBinding:@"hidden2"];
        printf("info: observed %d, key path %s, transformer %s\n", info[NSObservedObjectKey] == p,
               str(info[NSObservedKeyPathKey]), str(info[NSOptionsKey][NSValueTransformerNameBindingOption]));
        printf("markers: %s %s %s, controller markers %d %d\n", str(NSNoSelectionMarker), str(NSMultipleValuesMarker),
               str(NSNotApplicableMarker), NSIsControllerMarker(NSNoSelectionMarker), NSIsControllerMarker(@"x"));

        /* ---- from a nib ---- */
        NSString *path = [NSString stringWithFormat:@"%s/Bindings.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        BindingsOwner *owner = [[BindingsOwner alloc] init];
        NSArray *top = nil;
        [defaults setBool:YES forKey:@"FerryNibFlag"];
        printf("nib loaded: %d\n", [nib instantiateWithOwner:owner topLevelObjects:&top]);
        NSObjectController *nc = owner.controller;
        printf("controller: %s, field \"%s\" (placeholder %s), slider %g, check %ld\n",
               [NSStringFromClass([nc class]) UTF8String], [[owner.field stringValue] UTF8String],
               str([owner.field placeholderString]), [owner.slider doubleValue], (long)[owner.check state]);
        printf("the field's binding: %s %s\n", str([owner.field infoForBinding:NSValueBinding][NSObservedKeyPathKey]),
               [owner.field infoForBinding:NSValueBinding][NSObservedObjectKey] == nc ? "of the controller" : "?");
        printf("the check box's: %s\n",
               [owner.check infoForBinding:NSValueBinding][NSObservedObjectKey] == udc ? "the shared controller" : "?");
        [nc setContent:[@{@"name" : @"Nib", @"level" : @7} mutableCopy]];
        printf("content: field %s, slider %g\n", [[owner.field stringValue] UTF8String], [owner.slider doubleValue]);
        [[nc content] setValue:@"Changed" forKey:@"name"];
        printf("content changed: field %s\n", [[owner.field stringValue] UTF8String]);
        [owner.slider setDoubleValue:3.4];
        printf("slider snaps to its tick marks: %g\n", [owner.slider doubleValue]);
        [defaults removeObjectForKey:@"FerryNibFlag"];
        printf("default removed: check %ld\n", (long)[owner.check state]);
    }
    return 0;
}
