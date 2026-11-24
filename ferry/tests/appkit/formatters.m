/* SPDX-License-Identifier: GPL-3.0-or-later
 * Formatters on controls and cells (Ferry 0.17.0), with no display: a text
 * field shows its value with stringForObjectValue:, starts editing from
 * editingStringForObjectValue:, refuses a keystroke its formatter's
 * isPartialStringValid: refuses, and reads what was typed with
 * getObjectValue:forString:errorDescription: when the editing ends. When
 * that fails the field beeps, its delegate is asked
 * control:didFailToFormatString:errorDescription:, and the editing goes on
 * unless the delegate takes the string. control:isValidObject: may refuse
 * a value. A cell's formatter shows its value too, and a table's column
 * cell's formatter reads an edited cell, so that the data source gets the
 * value, not the text. */
#import <Cocoa/Cocoa.h>
#import <objc/message.h>

static NSUInteger beeps(void)
{
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(NSApp, sel_registerName("_ferryBeepCount"));
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
static NSString *describe(id v)
{
    if (!v)
        return @"nil";
    if ([v isKindOfClass:[NSNumber class]])
        return [NSString stringWithFormat:@"the number %@", v];
    if ([v isKindOfClass:[NSString class]])
        return [NSString stringWithFormat:@"the string \"%@\"", v];
    return NSStringFromClass([v class]);
}

/* Degrees: "21.5 °C" shown, "21.5" while editing; digits, a point and a
 * minus sign may be typed. */
@interface Degrees : NSFormatter
@end
@implementation Degrees
- (NSString *)stringForObjectValue:(id)obj
{
    return [obj isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%g °C", [obj doubleValue]] : nil;
}
- (NSString *)editingStringForObjectValue:(id)obj
{
    return [obj isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%g", [obj doubleValue]] : nil;
}
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error
{
    NSString *s = [string hasSuffix:@" °C"] ? [string substringToIndex:[string length] - 3] : string;
    const char *start = [s UTF8String];
    char *end;
    double d = strtod(start, &end);
    if ([s length] && end != start && !*end) {
        *obj = @(d);
        return YES;
    }
    if (error)
        *error = [NSString stringWithFormat:@"“%@” isn't a temperature", string];
    return NO;
}
- (BOOL)isPartialStringValid:(NSString *)partial newEditingString:(NSString **)newString
            errorDescription:(NSString **)error
{
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"] invertedSet];
    if ([partial rangeOfCharacterFromSet:bad].location == NSNotFound)
        return YES;
    *newString = nil;
    if (error)
        *error = @"only numbers";
    return NO;
}
@end

@interface Watcher : NSObject <NSTextFieldDelegate>
@property BOOL acceptBadStrings;
@property double limit;
@property (strong) NSMutableArray *log;
@end
@implementation Watcher
- (instancetype)init
{
    if ((self = [super init])) {
        _log = [NSMutableArray array];
        _limit = 1000;
    }
    return self;
}
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    [_log addObject:[NSString stringWithFormat:@"couldn't format \"%@\": %@ (%s)", string, error,
                                               _acceptBadStrings ? "kept" : "editing goes on"]];
    return _acceptBadStrings;
}
- (void)control:(NSControl *)control didFailToValidatePartialString:(NSString *)string
    errorDescription:(NSString *)error
{
    [_log addObject:[NSString stringWithFormat:@"refused the keystroke making \"%@\": %@", string, error]];
}
- (BOOL)control:(NSControl *)control isValidObject:(id)obj
{
    BOOL ok = ![obj isKindOfClass:[NSNumber class]] || [obj doubleValue] <= _limit;
    if (!ok)
        [_log addObject:[NSString stringWithFormat:@"refused %@", describe(obj)]];
    return ok;
}
- (void)changed:(NSTextField *)f
{
    [_log addObject:[NSString stringWithFormat:@"action: value %@", describe([f objectValue])]];
}
- (void)dump
{
    for (NSString *s in _log)
        printf("  %s\n", [s UTF8String]);
    [_log removeAllObjects];
}
@end

@interface Readings : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSMutableArray *values;
@end
@implementation Readings
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)[_values count]; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return _values[(NSUInteger)row];
}
- (void)tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    printf("  the data source gets %s for row %ld\n", [describe(v) UTF8String], (long)row);
    _values[(NSUInteger)row] = v;
}
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    printf("  the table's delegate hears \"%s\" couldn't be read (control is the table: %d)\n", [string UTF8String],
           [control isKindOfClass:[NSTableView class]]);
    return NO;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 300) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];

        /* ---- showing and setting ---- */
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, 150, 22)];
        NSTextField *other = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 40, 150, 22)];
        [[w contentView] addSubview:f];
        [[w contentView] addSubview:other];
        Degrees *degrees = [[Degrees alloc] init];
        [f setFormatter:degrees];
        printf("formatter kept: %d\n", [f formatter] == degrees);
        [f setObjectValue:@21.5];
        printf("shown: %s, value %s, double %g\n", [[f stringValue] UTF8String], [describe([f objectValue]) UTF8String],
               [f doubleValue]);
        [f setStringValue:@"30 °C"];
        printf("setStringValue 30 °C: value %s, shown %s\n", [describe([f objectValue]) UTF8String],
               [[f stringValue] UTF8String]);
        [f setStringValue:@"warm"];
        printf("setStringValue warm: value %s, shown %s\n", [describe([f objectValue]) UTF8String],
               [[f stringValue] UTF8String]);
        [f setObjectValue:@21.5];

        /* ---- editing ---- */
        Watcher *watch = [[Watcher alloc] init];
        [f setDelegate:watch];
        [f setTarget:watch];
        [f setAction:@selector(changed:)];
        [w makeFirstResponder:f];
        printf("editing starts from: %s\n", [[f stringValue] UTF8String]);
        NSUInteger b = beeps();
        type(w, @"2x");
        printf("typed 2x: text %s, beeps %lu\n", [[f stringValue] UTF8String], (unsigned long)(beeps() - b));
        [watch dump];
        key(w, '5', 0);
        key(w, '\r', 0);
        printf("typed 5, Return: value %s, text %s, still editing %d\n", [describe([f objectValue]) UTF8String],
               [[f stringValue] UTF8String], [w firstResponder] == f);
        [watch dump];

        /* text the formatter can type but can't read */
        [f selectText:nil];
        type(w, @"1-2");
        b = beeps();
        BOOL moved = [w makeFirstResponder:other];
        printf("typed 1-2, focus moved away: %s, beeps %lu, value %s\n", moved ? "yes" : "no",
               (unsigned long)(beeps() - b), [describe([f objectValue]) UTF8String]);
        [watch dump];
        key(w, '\r', 0);
        printf("Return on it: value %s, still editing %d\n", [describe([f objectValue]) UTF8String],
               [w firstResponder] == f);
        [watch dump];
        watch.acceptBadStrings = YES;
        moved = [w makeFirstResponder:other];
        printf("the delegate takes it: focus moved %s, value %s, shown %s\n", moved ? "yes" : "no",
               [describe([f objectValue]) UTF8String], [[f stringValue] UTF8String]);
        [watch dump];
        watch.acceptBadStrings = NO;

        /* the delegate refuses a value */
        [f setObjectValue:@20];
        watch.limit = 100;
        [w makeFirstResponder:f];
        type(w, @"500");
        b = beeps();
        moved = [w makeFirstResponder:other];
        printf("typed 500 over a limit of 100: focus moved %s, beeps %lu, value %s\n", moved ? "yes" : "no",
               (unsigned long)(beeps() - b), [describe([f objectValue]) UTF8String]);
        [watch dump];
        [f selectText:nil];
        type(w, @"99");
        moved = [w makeFirstResponder:other];
        printf("typed 99: focus moved %s, value %s, shown %s\n", moved ? "yes" : "no",
               [describe([f objectValue]) UTF8String], [[f stringValue] UTF8String]);
        [watch dump];

        /* focus that comes and goes with nothing typed keeps the value */
        [w makeFirstResponder:f];
        [w makeFirstResponder:other];
        printf("no typing: value %s\n", [describe([f objectValue]) UTF8String]);

        /* Escape-like abort gives up what was typed */
        [w makeFirstResponder:f];
        type(w, @"7");
        [f abortEditing];
        printf("abortEditing: value %s, editing %d\n", [describe([f objectValue]) UTF8String], [w firstResponder] == f);

        /* validateEditing reads the text if it can, and the editing goes on */
        [w makeFirstResponder:f];
        [f selectText:nil];
        type(w, @"12");
        [f validateEditing];
        printf("validateEditing: value %s, editing %d\n", [describe([f objectValue]) UTF8String], [w firstResponder] == f);
        [w makeFirstResponder:other];

        /* ---- a number formatter ---- */
        NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
        [nf setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        [nf setNumberStyle:NSNumberFormatterDecimalStyle];
        NSTextField *n = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 70, 150, 22)];
        [[w contentView] addSubview:n];
        [n setFormatter:nf];
        [n setObjectValue:@1234.5];
        printf("number formatter: shown %s\n", [[n stringValue] UTF8String]);
        [w makeFirstResponder:n];
        [n selectText:nil];
        type(w, @"2,000");
        [w makeFirstResponder:other];
        printf("typed 2,000: value %s, shown %s\n", [describe([n objectValue]) UTF8String], [[n stringValue] UTF8String]);

        /* ---- cells ---- */
        NSTextFieldCell *c = [[NSTextFieldCell alloc] initTextCell:@""];
        [c setFormatter:degrees];
        [c setObjectValue:@-4];
        NSTextFieldCell *copy = [c copy];
        printf("a cell: %s; its copy: %s\n", [[c stringValue] UTF8String], [[copy stringValue] UTF8String]);
        [c setStringValue:@"8"];
        printf("cell setStringValue 8: %s\n", [describe([c objectValue]) UTF8String]);

        /* ---- a table's column cell ---- */
        Readings *readings = [[Readings alloc] init];
        readings.values = [@[ @20, @22.5, @19 ] mutableCopy];
        NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(180, 10, 200, 100)];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"t"];
        [col setWidth:150];
        [col setEditable:YES];
        [[col dataCell] setFormatter:degrees];
        [tv addTableColumn:col];
        [tv setDataSource:readings];
        [tv setDelegate:readings];
        [[w contentView] addSubview:tv];
        [tv reloadData];
        printf("table cell shown: %s\n", [[[tv preparedCellAtColumn:0 row:1] stringValue] UTF8String]);
        [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        [tv editColumn:0 row:1 withEvent:nil select:YES];
        printf("editing the cell starts from: %s\n", [[(NSTextField *)[w firstResponder] stringValue] UTF8String]);
        type(w, @"18");
        key(w, '\r', 0);
        printf("typed 18, Return: edited row %ld, value %s\n", (long)[tv editedRow],
               [describe(readings.values[1]) UTF8String]);
        [tv editColumn:0 row:1 withEvent:nil select:YES];
        type(w, @"1-2");
        b = beeps();
        key(w, '\r', 0);
        printf("typed 1-2, Return: edited row %ld, beeps %lu\n", (long)[tv editedRow], (unsigned long)(beeps() - b));
        key(w, 0x1b, 0);
        printf("Escape: edited row %ld, value %s\n", (long)[tv editedRow], [describe(readings.values[1]) UTF8String]);
    }
    return 0;
}
