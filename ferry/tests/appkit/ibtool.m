/* SPDX-License-Identifier: GPL-3.0-or-later
 * A nib compiled by ferry-ibtool (freemac 1.223, Ferry 0.47.0) from
 * ibtool.xib, Ferry's own document in the format Interface Builder saves,
 * loaded with NSNib with no display: File's Owner's outlets, a window of
 * the app's own class with its style, title, size and autosave name, a
 * panel that isn't shown at launch, text fields bound to the user
 * defaults, a push button's Return key and action, a check box, radio
 * buttons in a stack view, a pop-up button's items, a box, a stepper, a
 * table in a scroll view with its columns and header, a custom view and an
 * object of the app's own classes given values by the document's runtime
 * attributes, an element ferry-ibtool doesn't know made as a plain view of
 * its class (a browser since 1.229, a class Ferry hasn't got, so a plain
 * NSView), and a menu with key equivalents, a separator and a submenu. */
#import <Cocoa/Cocoa.h>

@interface IBWindow : NSWindow
@end
@implementation IBWindow
@end

@interface IBDrawingView : NSView
@property (strong) NSColor *fill;
@end
@implementation IBDrawingView
@end

@interface IBHelper : NSObject
@property (copy) NSString *label;
@property NSInteger count;
@property BOOL enabled;
@property (weak) id owner;
@end
@implementation IBHelper
@end

@interface IBOwner : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSPanel *panel;
@property (weak) IBOutlet NSTextField *nameField;
@property (weak) IBOutlet NSSecureTextField *passwordField;
@property (weak) IBOutlet NSButton *okButton;
@property (weak) IBOutlet NSButton *check;
@property (weak) IBOutlet NSPopUpButton *sizePopUp;
@property (weak) IBOutlet NSTableView *table;
@property (weak) IBOutlet NSStackView *stack;
@property (weak) IBOutlet IBDrawingView *drawing;
@property (weak) IBOutlet NSBox *box;
@property (weak) IBOutlet NSStepper *stepper;
@property (weak) IBOutlet NSView *level;
@property (strong) IBOutlet NSMenu *statusMenu;
@property (strong) IBOutlet IBHelper *helper;
@end
@implementation IBOwner
- (IBAction)confirm:(id)sender { printf("confirm: from %s \"%s\"\n", [[sender className] UTF8String], [[sender title] UTF8String]); }
- (IBAction)openThing:(id)sender { printf("openThing:\n"); }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return 2; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
    return [NSString stringWithFormat:@"%@ %ld", [col identifier], (long)row];
}
@end

static const char *yesno(BOOL b) { return b ? "yes" : "no"; }

static void print_item(NSMenuItem *item, int depth)
{
    if ([item isSeparatorItem]) {
        printf("%*s-----\n", depth * 2, "");
        return;
    }
    printf("%*s\"%s\" key \"%s\" mask %#lx tag %ld state %ld hidden %s action %s target %s\n", depth * 2, "",
           [[item title] UTF8String], [[item keyEquivalent] UTF8String],
           (unsigned long)[item keyEquivalentModifierMask], (long)[item tag], (long)[item state], yesno([item isHidden]),
           [item action] ? sel_getName([item action]) : "-",
           [item target] ? [[[item target] className] UTF8String] : "nil");
    for (NSMenuItem *sub in [[item submenu] itemArray])
        print_item(sub, depth + 1);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setObject:@"Ada" forKey:@"IBToolName"];
        [d setBool:NO forKey:@"IBToolShowsThing"];

        NSString *path = [NSString stringWithFormat:@"%s/IBTool.nib", getenv("FERRY_TEST_DATA")];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        printf("nib read: %s\n", yesno(nib != nil));
        IBOwner *owner = [IBOwner new];
        NSArray *top = nil;
        printf("instantiated: %s\n", yesno([nib instantiateWithOwner:owner topLevelObjects:&top]));
        NSMutableArray *kinds = [NSMutableArray array];
        for (id o in top)
            [kinds addObject:[o className]];
        [kinds sortUsingSelector:@selector(compare:)];
        printf("top level: %s\n", [[kinds componentsJoinedByString:@", "] UTF8String]);

        NSWindow *w = owner.window;
        printf("window: %s \"%s\" style %#lx content %.0fx%.0f autosave \"%s\" min %.0fx%.0f visible %s\n",
               [[w className] UTF8String], [[w title] UTF8String], (unsigned long)[w styleMask],
               [[w contentView] frame].size.width, [[w contentView] frame].size.height,
               [[w frameAutosaveName] UTF8String], [w minSize].width, [w minSize].height, yesno([w isVisible]));
        NSPanel *p = owner.panel;
        printf("panel: %s \"%s\" utility %s visible %s\n", [[p className] UTF8String], [[p title] UTF8String],
               yesno(([p styleMask] & NSWindowStyleMaskUtilityWindow) != 0), yesno([p isVisible]));
        /* a HUD panel (as xibs write it, HUD="YES") is dark; a slider taller
         * than wide is vertical, and keeps its control size and range */
        CGFloat white = 1, alpha = 0;
        [[[p backgroundColor] colorUsingColorSpace:[NSColorSpace genericGrayColorSpace]] getWhite:&white alpha:&alpha];
        NSSlider *band = [[[p contentView] subviews] firstObject];
        printf("panel HUD %s, dark %s; slider vertical %s, small %s, %g to %g\n",
               yesno(([p styleMask] & NSWindowStyleMaskHUDWindow) != 0), yesno(white < 0.5), yesno([band isVertical]),
               yesno([band controlSize] == NSControlSizeSmall), [band minValue], [band maxValue]);
        /* a disclosure triangle opens and closes, as a button that stays on */
        NSButton *tri = [[[p contentView] subviews] lastObject];
        [tri performClick:nil];
        printf("disclosure triangle: bezel %ld, open after a click %s\n", (long)[tri bezelStyle],
               yesno([tri state] == NSControlStateValueOn));
        printf("content subviews: %lu\n", (unsigned long)[[[w contentView] subviews] count]);

        NSTextField *name = owner.nameField;
        printf("name: \"%s\" placeholder \"%s\" editable %s bezeled %s alignment %ld bold %s tip \"%s\" mask %lu in window %s\n",
               [[name stringValue] UTF8String], [[[name cell] placeholderString] UTF8String], yesno([name isEditable]),
               yesno([name isBezeled]), (long)[name alignment],
               yesno(([[NSFontManager sharedFontManager] traitsOfFont:[name font]] & NSBoldFontMask) != 0),
               [[name toolTip] UTF8String], (unsigned long)[name autoresizingMask], yesno([name window] == w));
        NSDictionary *info = [name infoForBinding:NSValueBinding];
        printf("name bound to %s, keyPath %s\n", [[info[NSObservedObjectKey] className] UTF8String],
               [info[NSObservedKeyPathKey] UTF8String]);
        printf("password field: %s font %.0f\n", [[owner.passwordField className] UTF8String],
               [[owner.passwordField font] pointSize]);

        NSButton *ok = owner.okButton;
        printf("ok: \"%s\" key %s tag %ld bezel %ld target %s action %s\n", [[ok title] UTF8String],
               [[ok keyEquivalent] isEqualToString:@"\r"] ? "Return" : [[ok keyEquivalent] UTF8String], (long)[ok tag],
               (long)[ok bezelStyle], [[[ok target] className] UTF8String], sel_getName([ok action]));
        [ok performClick:nil];
        NSButton *check = owner.check;
        printf("check: \"%s\" state %ld (the defaults say no)\n", [[check title] UTF8String], (long)[check state]);
        [d setBool:YES forKey:@"IBToolShowsThing"];
        printf("check after the default changed: state %ld\n", (long)[check state]);

        NSPopUpButton *pop = owner.sizePopUp;
        printf("pop-up: %ld items, selected \"%s\" tag %ld, pulls down %s, bezel drawn %s\n", (long)[pop numberOfItems],
               [[pop titleOfSelectedItem] UTF8String], (long)[[pop selectedItem] tag], yesno([pop pullsDown]),
               yesno([pop isBordered]));
        printf("box: \"%s\" holds %lu views\n", [[owner.box title] UTF8String],
               (unsigned long)[[[owner.box contentView] subviews] count]);
        NSStepper *st = owner.stepper;
        printf("stepper: %.0f in %.0f..%.0f by %.0f, in the box %s\n", [st doubleValue], [st minValue], [st maxValue],
               [st increment], yesno([st isDescendantOf:owner.box]));
        printf("browser, an element the tool does not know: %s\n", [[owner.level className] UTF8String]);

        NSTableView *t = owner.table;
        printf("table: %lu columns, row height %.0f, data source is the owner %s, in a scroll view %s (line border %s), header %s\n",
               (unsigned long)[[t tableColumns] count], [t rowHeight], yesno([t dataSource] == (id)owner),
               yesno([t enclosingScrollView] != nil), yesno([[t enclosingScrollView] borderType] == NSLineBorder),
               yesno([t headerView] != nil));
        for (NSTableColumn *c in [t tableColumns])
            printf("  column %s \"%s\" width %.0f editable %s\n", [[c identifier] UTF8String],
                   [[[c headerCell] stringValue] UTF8String], [c width], yesno([c isEditable]));
        printf("  multiple selection %s, alternating rows %s, source list %s\n", yesno([t allowsMultipleSelection]),
               yesno([t usesAlternatingRowBackgroundColors]),
               yesno([t selectionHighlightStyle] == NSTableViewSelectionHighlightStyleSourceList));
        [t reloadData];
        printf("  rows %ld\n", (long)[t numberOfRows]);

        NSStackView *stack = owner.stack;
        printf("stack: %s orientation %ld, %lu views:", [[stack className] UTF8String], (long)[stack orientation],
               (unsigned long)[[stack arrangedSubviews] count]);
        for (NSButton *b in [stack arrangedSubviews])
            printf(" \"%s\" (%ld)", [[b title] UTF8String], (long)[b state]);
        printf("\n");

        IBDrawingView *draw = owner.drawing;
        printf("drawing: %s fill white %.2f mask %lu\n", [[draw className] UTF8String],
               [draw.fill whiteComponent],
               (unsigned long)[draw autoresizingMask]);
        IBHelper *h = owner.helper;
        printf("helper: \"%s\" count %ld enabled %s owner %s\n", [h.label UTF8String], (long)h.count, yesno(h.enabled),
               yesno(h.owner == owner));

        NSMenu *m = owner.statusMenu;
        printf("menu \"%s\":\n", [[m title] UTF8String]);
        for (NSMenuItem *item in [m itemArray])
            print_item(item, 1);
        NSMenuItem *open = [m itemAtIndex:0];
        [NSApp sendAction:[open action] to:[open target] from:open];
    }
    return 0;
}
