/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSRuleEditor (freemac 1.222, Ferry 0.46.0): rows made from a delegate's
 * criteria, compound and simple, as Sequel Pro's filter rules are; their
 * display values shown as pop-ups, labels and the delegate's own text
 * fields; choosing another criterion in a pop-up; the add and remove
 * buttons; the predicate from the delegate's parts; the rows bound to a
 * model's array, and the model changed from outside; removing a row whose
 * subrows are kept; reloading the criteria; and the change notification.
 * Also NSTextView's selection by word and paragraph. Run with no display. */
#import <Cocoa/Cocoa.h>

@interface Delegate : NSObject <NSRuleEditorDelegate>
@property int changes;
@property BOOL noSize;
@property NSMutableDictionary *fields; /* one text field for each row object */
@end

@implementation Delegate
- (NSArray *)children:(id)criterion type:(NSRuleEditorRowType)type
{
    if (type == NSRuleEditorRowTypeCompound) {
        if (!criterion)
            return @[ @"all", @"any" ];
        if ([criterion isEqual:@"all"] || [criterion isEqual:@"any"])
            return @[ @"of these are true" ];
        return @[];
    }
    if (!criterion)
        return self.noSize ? @[ @"name" ] : @[ @"name", @"size" ];
    if ([criterion isEqual:@"name"])
        return @[ @"is", @"contains" ];
    if ([criterion isEqual:@"size"])
        return @[ @"is more than" ];
    if ([criterion isEqual:@"is"] || [criterion isEqual:@"contains"] || [criterion isEqual:@"is more than"])
        return @[ @"field" ];
    return @[];
}
- (NSInteger)ruleEditor:(NSRuleEditor *)editor numberOfChildrenForCriterion:(id)criterion
            withRowType:(NSRuleEditorRowType)rowType
{
    return [[self children:criterion type:rowType] count];
}
- (id)ruleEditor:(NSRuleEditor *)editor child:(NSInteger)index forCriterion:(id)criterion
     withRowType:(NSRuleEditorRowType)rowType
{
    return [self children:criterion type:rowType][index];
}
- (id)ruleEditor:(NSRuleEditor *)editor displayValueForCriterion:(id)criterion inRow:(NSInteger)row
{
    if (![criterion isEqual:@"field"])
        return criterion;
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
    f.stringValue = @"";
    return f;
}
- (NSDictionary *)ruleEditor:(NSRuleEditor *)editor predicatePartsForCriterion:(id)criterion
            withDisplayValue:(id)value inRow:(NSInteger)row
{
    if ([criterion isEqual:@"all"])
        return @{NSRuleEditorPredicateCompoundType : @(NSAndPredicateType)};
    if ([criterion isEqual:@"any"])
        return @{NSRuleEditorPredicateCompoundType : @(NSOrPredicateType)};
    if ([criterion isEqual:@"name"] || [criterion isEqual:@"size"])
        return @{NSRuleEditorPredicateLeftExpression : [NSExpression expressionForKeyPath:criterion]};
    if ([criterion isEqual:@"is"])
        return @{NSRuleEditorPredicateOperatorType : @(NSEqualToPredicateOperatorType)};
    if ([criterion isEqual:@"contains"])
        return @{
            NSRuleEditorPredicateOperatorType : @(NSContainsPredicateOperatorType),
            NSRuleEditorPredicateOptions : @(NSCaseInsensitivePredicateOption)
        };
    if ([criterion isEqual:@"is more than"])
        return @{NSRuleEditorPredicateOperatorType : @(NSGreaterThanPredicateOperatorType)};
    if ([criterion isEqual:@"field"])
        return @{
            NSRuleEditorPredicateRightExpression : [NSExpression expressionForConstantValue:[value stringValue]]
        };
    return nil;
}
- (void)ruleEditorRowsDidChange:(NSNotification *)n { self.changes++; }
@end

@interface Model : NSObject
@property NSMutableArray *rows;
@end
@implementation Model
@end

static void show(NSRuleEditor *e, const char *what)
{
    printf("%s: %ld rows\n", what, (long)e.numberOfRows);
    for (NSInteger i = 0; i < e.numberOfRows; i++) {
        NSMutableArray *shown = [NSMutableArray array];
        for (id v in [e displayValuesForRow:i])
            [shown addObject:[v isKindOfClass:[NSString class]] ? v : NSStringFromClass([v class])];
        printf("  %ld: %s, parent %ld, [%s]\n", (long)i,
               [e rowTypeForRow:i] == NSRuleEditorRowTypeCompound ? "compound" : "simple", (long)[e parentRowForRow:i],
               [[shown componentsJoinedByString:@", "] UTF8String]);
    }
}

/* what row i's view holds, left to right */
static void views(NSRuleEditor *e, NSInteger i)
{
    NSView *row = e.subviews[i];
    printf("  row %ld at y %g:", (long)i, NSMinY(row.frame));
    for (NSView *v in row.subviews) {
        if ([v isKindOfClass:[NSPopUpButton class]])
            printf(" pop-up(%s of %s)", [[(NSPopUpButton *)v titleOfSelectedItem] UTF8String],
                   [[[(NSPopUpButton *)v itemTitles] componentsJoinedByString:@"|"] UTF8String]);
        else if ([v isKindOfClass:[NSButton class]])
            printf(" button(%s%s)", [[(NSButton *)v title] UTF8String], [(NSButton *)v isEnabled] ? "" : ", off");
        else if ([v isKindOfClass:[NSTextField class]] && ![(NSTextField *)v isEditable])
            printf(" label(%s)", [[(NSTextField *)v stringValue] UTF8String]);
        else
            printf(" %s", [NSStringFromClass([v class]) UTF8String]);
    }
    printf("\n");
}

static NSButton *button(NSRuleEditor *e, NSInteger row, NSString *title)
{
    for (NSView *v in [e.subviews[row] subviews])
        if ([v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]] &&
            [[(NSButton *)v title] isEqual:title])
            return (NSButton *)v;
    return nil;
}

static void press(NSControl *c) { [NSApp sendAction:c.action to:c.target from:c]; }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Delegate *d = [Delegate new];
        NSRuleEditor *e = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
        printf("defaults: nesting %lu, row height %g, editable %d, can remove all %d, row class %s\n",
               (unsigned long)e.nestingMode, e.rowHeight, e.editable, e.canRemoveAllRows,
               [NSStringFromClass(e.rowClass) UTF8String]);
        e.delegate = d;
        [e addRow:nil];
        [e addRow:nil];
        show(e, "two rows added");
        views(e, 0);
        views(e, 1);

        /* a value in the field, and the predicate */
        NSTextField *field = [e displayValuesForRow:1][2];
        field.stringValue = @"Ferry";
        printf("the field is in row %ld\n", (long)[e rowForDisplayValue:field]);
        [e reloadPredicate];
        printf("predicate: %s\n", [e.predicate.predicateFormat UTF8String]);

        /* another criterion chosen in the first pop-up */
        NSPopUpButton *pop = (NSPopUpButton *)[e.subviews[1] subviews][0];
        [pop selectItemAtIndex:1];
        press(pop);
        show(e, "size chosen");
        views(e, 1);
        pop = (NSPopUpButton *)[e.subviews[1] subviews][0];
        [pop selectItemAtIndex:0];
        press(pop);
        pop = (NSPopUpButton *)[e.subviews[1] subviews][1];
        [pop selectItemAtIndex:1];
        press(pop);
        ((NSTextField *)[e displayValuesForRow:1][2]).stringValue = @"mac";
        [e reloadPredicate];
        printf("contains: %s, row's own %s\n", [e.predicate.predicateFormat UTF8String],
               [[e predicateForRow:1].predicateFormat UTF8String]);

        /* the buttons */
        press(button(e, 1, @"+"));
        press(button(e, 0, @"+"));
        show(e, "added after row 1, and under row 0");
        press(button(e, 2, @"−"));
        show(e, "row 2 removed");
        printf("subrows of row 0: %lu, changes so far %d\n", (unsigned long)[e subrowIndexesForRow:0].count,
               d.changes);

        /* the first compound row's choice */
        pop = (NSPopUpButton *)[e.subviews[0] subviews][0];
        [pop selectItemAtIndex:1];
        press(pop);
        ((NSTextField *)[e displayValuesForRow:2][2]).stringValue = @"x";
        [e reloadPredicate];
        printf("any: %s\n", [e.predicate.predicateFormat UTF8String]);

        /* a nested compound row */
        [e insertRowAtIndex:3 withType:NSRuleEditorRowTypeCompound asSubrowOfRow:0 animate:NO];
        [e insertRowAtIndex:4 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:3 animate:NO];
        show(e, "a compound row inside");
        views(e, 4);
        @try {
            [e insertRowAtIndex:2 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:1 animate:NO];
        } @catch (NSException *x) {
            printf("a subrow of a simple row: %s\n", [x.name UTF8String]);
        }
        @try {
            [e criteriaForRow:9];
        } @catch (NSException *x) {
            printf("no row 9: %s\n", [x.name UTF8String]);
        }

        /* removing the top row keeps its subrows */
        [e removeRowAtIndex:0];
        show(e, "the top row removed");
        [e removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:2] includeSubrows:YES];
        show(e, "a compound row removed with its subrow");

        /* the criteria reloaded when the delegate offers fewer */
        pop = (NSPopUpButton *)[e.subviews[0] subviews][0];
        [pop selectItemAtIndex:1];
        press(pop);
        d.noSize = YES;
        [e reloadCriteria];
        show(e, "size no longer offered");
        views(e, 0);
        [e selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        [e selectRowIndexes:[NSIndexSet indexSetWithIndex:7] byExtendingSelection:YES];
        printf("selected: %lu rows, first %lu\n", (unsigned long)e.selectedRowIndexes.count,
               (unsigned long)e.selectedRowIndexes.firstIndex);

        /* bound to a model */
        Model *m = [Model new];
        m.rows = [NSMutableArray array];
        NSRuleEditor *b = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
        b.nestingMode = NSRuleEditorNestingModeList;
        b.delegate = d;
        [b bind:@"rows" toObject:m withKeyPath:@"rows" options:nil];
        printf("bound: info %d\n", [[b infoForBinding:@"rows"][NSObservedKeyPathKey] isEqual:@"rows"]);
        [b addRow:nil];
        [b addRow:nil];
        NSDictionary *first = m.rows[0];
        printf("the model has %lu rows; the first's criteria %s, type %s\n", (unsigned long)m.rows.count,
               [[first[@"criteria"] componentsJoinedByString:@" "] UTF8String], [[first[@"rowType"] description] UTF8String]);
        show(b, "a list");
        views(b, 0);
        NSMutableDictionary *outside = [NSMutableDictionary dictionaryWithDictionary:@{
            @"rowType" : @(NSRuleEditorRowTypeSimple),
            @"criteria" : @[ @"name", @"is", @"field" ],
            @"displayValues" : @[ @"name", @"is", [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 22)] ],
            @"subrows" : [NSMutableArray array],
        }];
        m.rows = [NSMutableArray arrayWithObject:outside];
        show(b, "the model set from outside");
        [[m mutableArrayValueForKey:@"rows"] removeAllObjects];
        printf("the model emptied: %ld rows\n", (long)b.numberOfRows);
        [b unbind:@"rows"];
        printf("unbound: info %d\n", [b infoForBinding:@"rows"] != nil);

        b.editable = NO;
        b.nestingMode = NSRuleEditorNestingModeSingle;
        [b addRow:nil];
        [b addRow:nil];
        show(b, "single, not editable");
        views(b, 0);
        printf("changes: %d\n", d.changes);

        /* selection by word and paragraph */
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        tv.string = @"one two-three\nfour five";
        NSRange r = [tv selectionRangeForProposedRange:NSMakeRange(5, 1) granularity:NSSelectByWord];
        NSRange p = [tv selectionRangeForProposedRange:NSMakeRange(5, 1) granularity:NSSelectByParagraph];
        NSRange c = [tv selectionRangeForProposedRange:NSMakeRange(5, 1) granularity:NSSelectByCharacter];
        NSRange s = [tv selectionRangeForProposedRange:NSMakeRange(3, 0) granularity:NSSelectByWord];
        printf("by word %s, by paragraph %s, by character %s, a space %s, %s\n",
               [NSStringFromRange(r) UTF8String], [NSStringFromRange(p) UTF8String], [NSStringFromRange(c) UTF8String],
               [NSStringFromRange(s) UTF8String], NSUnderlinePatternDot == NSUnderlineStylePatternDot ? "dots" : "");
    }
    return 0;
}
