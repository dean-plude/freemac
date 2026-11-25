/* SPDX-License-Identifier: GPL-3.0-or-later
 * The classes the seven apps' xibs use that ferry-ibtool used to make as
 * plain views (freemac 1.229, Ferry 0.53.0), compiled from Ferry's own
 * ibtool_classes.xib and loaded with no display: a text view with its
 * attributed text, its flags and colours, and one of the app's own class
 * bound to the user defaults; a web view's preferences; a matrix of check
 * boxes with its mode, sizes and a cell bound to the defaults; a level
 * indicator, a date picker and a path control with their values; number,
 * byte-count, date and custom formatters on text fields; a rule editor; a
 * control of the app's own class; a collection view with its item; a
 * Quartz Composer view; a date-components formatter and a combo box cell at
 * the top level; a table whose columns hold a combo box and an image cell;
 * and a window's initial position. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <Quartz/Quartz.h>

@interface ICTextView : NSTextView
@end
@implementation ICTextView
@end

@interface ICRecorder : NSControl
@end
@implementation ICRecorder
@end

@interface ICItem : NSCollectionViewItem
@end
@implementation ICItem
@end

@interface ICDaysFormatter : NSFormatter
@end
@implementation ICDaysFormatter
- (NSString *)stringForObjectValue:(id)obj { return [NSString stringWithFormat:@"%ld days", (long)[obj integerValue]]; }
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)s errorDescription:(NSString **)err
{
    *obj = @([s integerValue]);
    return YES;
}
@end

@interface ICOwner : NSObject
@property (strong) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextView *textView;
@property (weak) IBOutlet NSTextView *notes;
@property (weak) IBOutlet WebView *webView;
@property (weak) IBOutlet NSMatrix *matrix;
@property (weak) IBOutlet NSButtonCell *firstCheck;
@property (weak) IBOutlet NSLevelIndicator *level;
@property (weak) IBOutlet NSDatePicker *datePicker;
@property (weak) IBOutlet NSPathControl *pathControl;
@property (weak) IBOutlet NSTextField *numberField;
@property (weak) IBOutlet NSTextField *sizeField;
@property (weak) IBOutlet NSTextField *dateField;
@property (weak) IBOutlet NSTextField *customField;
@property (weak) IBOutlet NSRuleEditor *ruleEditor;
@property (weak) IBOutlet NSControl *recorder;
@property (weak) IBOutlet NSCollectionView *collection;
@property (strong) IBOutlet NSDateComponentsFormatter *durations;
@property (strong) IBOutlet NSComboBoxCell *comboCell;
@property (strong) IBOutlet NSCollectionViewItem *item;
@property (weak) IBOutlet NSTableView *table;
@property (weak) IBOutlet QCView *composition;
@end
@implementation ICOwner
- (IBAction)toggle:(id)sender
{
    printf("toggle: from %s, the clicked cell \"%s\" state %ld\n", [[sender className] UTF8String],
           [[[sender selectedCell] title] UTF8String], (long)[[sender selectedCell] state]);
}
@end

static const char *yesno(BOOL b) { return b ? "yes" : "no"; }

static void print_rgb(const char *what, NSColor *c)
{
    NSColor *rgb = [c colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    printf("%s %.2f %.2f %.2f", what, [rgb redComponent], [rgb greenComponent], [rgb blueComponent]);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setObject:@"from the defaults" forKey:@"ICNotes"];
        [d setBool:NO forKey:@"ICShowsMenu"];

        NSString *path = [NSString stringWithFormat:@"%s/Classes.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        ICOwner *owner = [ICOwner new];
        NSArray *top = nil;
        printf("instantiated: %s\n", yesno([nib instantiateWithOwner:owner topLevelObjects:&top]));
        NSMutableArray *kinds = [NSMutableArray array];
        for (id o in top)
            [kinds addObject:[o className]];
        [kinds sortUsingSelector:@selector(compare:)];
        printf("top level: %s\n", [[kinds componentsJoinedByString:@", "] UTF8String]);

        NSTextView *tv = owner.textView;
        printf("text view: %s \"%s\" editable %s selectable %s rich %s graphics %s font panel %s undo %s smart %s\n",
               [[tv className] UTF8String], [[tv string] UTF8String], yesno([tv isEditable]), yesno([tv isSelectable]),
               yesno([tv isRichText]), yesno([tv importsGraphics]), yesno([tv usesFontPanel]), yesno([tv allowsUndo]),
               yesno([tv smartInsertDeleteEnabled]));
        NSTextStorage *ts = [tv textStorage];
        NSRange r;
        NSDictionary *a0 = [ts attributesAtIndex:0 effectiveRange:&r];
        NSDictionary *a1 = [ts attributesAtIndex:8 effectiveRange:NULL];
        printf("  runs: \"%s\" %lu long, then \"%s\" in %s %.0f", [[[ts string] substringWithRange:r] UTF8String],
               (unsigned long)r.length, [[[ts string] substringFromIndex:NSMaxRange(r)] UTF8String],
               [[a1[NSFontAttributeName] fontName] UTF8String], [a1[NSFontAttributeName] pointSize]);
        print_rgb(", colour", a1[NSForegroundColorAttributeName]);
        printf(", centred %s\n", yesno([a0[NSParagraphStyleAttributeName] alignment] == NSTextAlignmentCenter));
        print_rgb("  background", [tv backgroundColor]);
        printf(", in a scroll view %s, resizes vertically %s, max width %.0f\n", yesno([tv enclosingScrollView] != nil),
               yesno([tv isVerticallyResizable]), [tv maxSize].width);

        NSTextView *notes = owner.notes;
        printf("notes: %s \"%s\" editable %s rich %s spelling %s ruler %s quotes %s\n", [[notes className] UTF8String],
               [[notes string] UTF8String], yesno([notes isEditable]), yesno([notes isRichText]),
               yesno([notes isContinuousSpellCheckingEnabled]), yesno([notes usesRuler]),
               yesno([notes isAutomaticQuoteSubstitutionEnabled]));
        print_rgb("  insertion point", [notes insertionPointColor]);
        printf("\n");

        WebView *web = owner.webView;
        WebPreferences *prefs = [web preferences];
        printf("web view: %s back-forward list %s, font size %d fixed %d minimum %d, plug-ins %s, JavaScript %s\n",
               [[web className] UTF8String], yesno([web maintainsBackForwardList]), [prefs defaultFontSize],
               [prefs defaultFixedFontSize], [prefs minimumFontSize], yesno([prefs arePlugInsEnabled]),
               yesno([prefs isJavaScriptEnabled]));

        NSMatrix *mx = owner.matrix;
        printf("matrix: %s %ldx%ld mode %ld empty selection %s cell %.0fx%.0f spacing %.0fx%.0f prototype %s\n",
               [[mx className] UTF8String], (long)[mx numberOfRows], (long)[mx numberOfColumns], (long)[mx mode],
               yesno([mx allowsEmptySelection]), [mx cellSize].width, [mx cellSize].height,
               [mx intercellSpacing].width, [mx intercellSpacing].height, [[[mx prototype] className] UTF8String]);
        for (NSButtonCell *c in [mx cells])
            printf("  \"%s\" state %ld tag %ld action %s\n", [[c title] UTF8String], (long)[c state], (long)[c tag],
                   [c action] ? sel_getName([c action]) : "-");
        NSDictionary *info = [owner.firstCheck infoForBinding:NSValueBinding];
        printf("  first cell is the owner's %s, bound to %s\n", yesno(owner.firstCheck == [mx cellAtRow:0 column:0]),
               [info[NSObservedKeyPathKey] UTF8String]);
        [d setBool:YES forKey:@"ICShowsMenu"];
        printf("  after the default changed: state %ld\n", (long)[owner.firstCheck state]);

        NSLevelIndicator *lvl = owner.level;
        printf("level: %s %.0f in %.0f..%.0f warning %.0f critical %.0f style %ld\n", [[lvl className] UTF8String],
               [lvl doubleValue], [lvl minValue], [lvl maxValue], [lvl warningValue], [lvl criticalValue],
               (long)[lvl levelIndicatorStyle]);

        NSDatePicker *dp = owner.datePicker;
        NSDateFormatter *iso = [NSDateFormatter new];
        [iso setDateFormat:@"yyyy-MM-dd"];
        [iso setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        printf("date picker: %s %s elements %#lx\n", [[dp className] UTF8String],
               [[iso stringFromDate:[dp dateValue]] UTF8String], (unsigned long)[dp datePickerElements]);

        NSPathControl *pc = owner.pathControl;
        printf("path control: %s %s style %ld editable %s\n", [[pc className] UTF8String],
               [[[pc URL] path] UTF8String], (long)[pc pathStyle], yesno([pc isEditable]));

        NSNumberFormatter *nf = [owner.numberField formatter];
        printf("number formatter: %s style %ld grouping %s fraction digits %lu, %s .. %s\n", [[nf className] UTF8String],
               (long)[nf numberStyle], yesno([nf usesGroupingSeparator]), (unsigned long)[nf maximumFractionDigits],
               [[[nf minimum] stringValue] UTF8String], [[[nf maximum] stringValue] UTF8String]);
        [owner.numberField setObjectValue:@(3.14159)];
        printf("  shows \"%s\"\n", [[owner.numberField stringValue] UTF8String]);
        NSByteCountFormatter *bcf = [owner.sizeField formatter];
        printf("byte-count formatter: %s style %ld\n", [[bcf className] UTF8String], (long)[bcf countStyle]);
        NSDateFormatter *df = [owner.dateField formatter];
        printf("date formatter: %s date style %ld time style %ld\n", [[df className] UTF8String], (long)[df dateStyle],
               (long)[df timeStyle]);
        [owner.customField setObjectValue:@(3)];
        printf("custom formatter: %s shows \"%s\"\n", [[[owner.customField formatter] className] UTF8String],
               [[owner.customField stringValue] UTF8String]);

        NSRuleEditor *re = owner.ruleEditor;
        printf("rule editor: %s nesting %ld row height %.0f can remove all %s\n", [[re className] UTF8String],
               (long)[re nestingMode], [re rowHeight], yesno([re canRemoveAllRows]));
        printf("recorder: %s with a %s\n", [[owner.recorder className] UTF8String],
               [[[owner.recorder cell] className] UTF8String]);
        NSCollectionView *cv = owner.collection;
        printf("collection: %s selectable %s prototype %s, the owner's item %s, its view %.0fx%.0f\n",
               [[cv className] UTF8String], yesno([cv isSelectable]), [[[cv itemPrototype] className] UTF8String],
               yesno([cv itemPrototype] == owner.item), [[owner.item view] frame].size.width,
               [[owner.item view] frame].size.height);
        QCView *qc = owner.composition;
        print_rgb([[NSString stringWithFormat:@"composition: %@ starts by itself %s, erase colour",
                   [qc className], yesno([qc autostartsRendering])] UTF8String], [qc eraseColor]);
        printf("\n");

        NSDateComponentsFormatter *dcf = owner.durations;
        printf("durations: %s units style %ld zero behaviour %#lx\n", [[dcf className] UTF8String],
               (long)[dcf unitsStyle], (unsigned long)[dcf zeroFormattingBehavior]);
        NSComboBoxCell *cbc = owner.comboCell;
        printf("combo cell: %s %ld items, completes %s, %ld visible\n", [[cbc className] UTF8String],
               (long)[cbc numberOfItems], yesno([cbc completes]), (long)[cbc numberOfVisibleItems]);
        for (NSTableColumn *col in [owner.table tableColumns]) {
            id cell = [col dataCell];
            printf("column %s: %s", [[col identifier] UTF8String], [[cell className] UTF8String]);
            if ([cell isKindOfClass:[NSComboBoxCell class]])
                printf(" with %ld items, %ld visible", (long)[cell numberOfItems], (long)[cell numberOfVisibleItems]);
            printf("\n");
        }

        NSMatrix *m = owner.matrix;
        NSButtonCell *second = (NSButtonCell *)[m cellAtRow:1 column:0];
        [m selectCellAtRow:1 column:0];
        [m sendAction:[second action] to:[second target]];
    }
    return 0;
}
