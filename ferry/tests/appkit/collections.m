/* SPDX-License-Identifier: GPL-3.0-or-later
 * Collection views of the modern kind, with no display: a data source
 * with two sections, items of a registered class made with
 * makeItemWithIdentifier:forIndexPath: and reused, and header and footer
 * views; the flow layout's item size, spacing, insets and headers and
 * footers, scrolling both ways, a delegate's own sizes, pinned headers and
 * a collapsed section; the grid layout; finding items by point and index
 * path and scrolling to them; selection by code (no delegate calls) and by
 * clicks and keys (with the delegate's should, did and highlight calls,
 * and empty and multiple selection allowed or not); and items and
 * sections inserted, deleted, moved and reloaded, alone and in a batch,
 * the selection and the items in sight going with them. */
#import <Cocoa/Cocoa.h>

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
static NSString *paths(NSSet *set)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSIndexPath *p in [[set allObjects] sortedArrayUsingSelector:@selector(compare:)])
        [a addObject:[NSString stringWithFormat:@"%ld.%ld", (long)[p section], (long)[p item]]];
    return [NSString stringWithFormat:@"{%@}", [a componentsJoinedByString:@","]];
}
static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p, NSEventModifierFlags flags)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:flags timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
}
static void click(NSWindow *w, NSView *v, NSPoint p, NSEventModifierFlags flags)
{
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, p, flags)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, p, flags)];
}
static void key(NSWindow *w, unichar c, NSEventModifierFlags flags)
{
    NSString *s = [NSString stringWithFormat:@"%C", c];
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}
static NSPoint mid(NSRect r) { return NSMakePoint(NSMidX(r), NSMidY(r)); }

/* ---- an item and a header ---- */

static int made, reused;

@interface Tile : NSCollectionViewItem
@property (copy) NSString *name;
@end
@implementation Tile
- (instancetype)initWithNibName:(NSString *)n bundle:(NSBundle *)b
{
    if ((self = [super initWithNibName:n bundle:b]))
        made++;
    return self;
}
- (void)loadView { [self setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]]; }
- (void)prepareForReuse
{
    [super prepareForReuse];
    reused++;
    self.name = nil;
}
@end

@interface Header : NSView <NSCollectionViewElement>
@property (copy) NSString *title;
@end
@implementation Header
@end

/* ---- the data source and delegate ---- */

@interface Pets : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>
@property (strong) NSMutableArray *sections;   /* arrays of names */
@property (strong) NSMutableArray *log;
@property (copy) NSString *refuse;             /* a name that may not be selected */
@property BOOL ownSizes;
@end
@implementation Pets
- (instancetype)init
{
    if ((self = [super init])) {
        _sections = [@[ [@[ @"ant", @"bee", @"cat", @"dog", @"eel", @"fox", @"gnu" ] mutableCopy],
                        [@[ @"hen", @"ibis", @"jay" ] mutableCopy] ] mutableCopy];
        _log = [NSMutableArray array];
    }
    return self;
}
- (NSString *)nameAt:(NSIndexPath *)p { return self.sections[(NSUInteger)p.section][(NSUInteger)p.item]; }
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)cv { return (NSInteger)[self.sections count]; }
- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)s
{
    return (NSInteger)[self.sections[(NSUInteger)s] count];
}
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)p
{
    Tile *t = [cv makeItemWithIdentifier:@"tile" forIndexPath:p];
    t.name = [self nameAt:p];
    return t;
}
- (NSView *)collectionView:(NSCollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind
               atIndexPath:(NSIndexPath *)p
{
    BOOL header = [kind isEqualToString:NSCollectionElementKindSectionHeader];
    Header *h = [cv makeSupplementaryViewOfKind:kind withIdentifier:header ? @"head" : @"foot" forIndexPath:p];
    h.title = [NSString stringWithFormat:@"%@ %ld", header ? @"head" : @"foot", (long)p.section];
    return h;
}
- (NSSize)collectionView:(NSCollectionView *)cv layout:(NSCollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p
{
    return self.ownSizes ? NSMakeSize(30 + 10 * (CGFloat)p.item, 30) : [(NSCollectionViewFlowLayout *)l itemSize];
}
- (NSSet *)collectionView:(NSCollectionView *)cv shouldSelectItemsAtIndexPaths:(NSSet *)set
{
    [self.log addObject:[NSString stringWithFormat:@"should select %@", paths(set)]];
    NSMutableSet *ok = [NSMutableSet set];
    for (NSIndexPath *p in set)
        if (![[self nameAt:p] isEqual:self.refuse])
            [ok addObject:p];
    return ok;
}
- (NSSet *)collectionView:(NSCollectionView *)cv shouldDeselectItemsAtIndexPaths:(NSSet *)set
{
    [self.log addObject:[NSString stringWithFormat:@"should deselect %@", paths(set)]];
    return set;
}
- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet *)set
{
    [self.log addObject:[NSString stringWithFormat:@"did select %@", paths(set)]];
}
- (void)collectionView:(NSCollectionView *)cv didDeselectItemsAtIndexPaths:(NSSet *)set
{
    [self.log addObject:[NSString stringWithFormat:@"did deselect %@", paths(set)]];
}
- (NSSet *)collectionView:(NSCollectionView *)cv shouldChangeItemsAtIndexPaths:(NSSet *)set
         toHighlightState:(NSCollectionViewItemHighlightState)state
{
    [self.log addObject:[NSString stringWithFormat:@"should highlight %@ %ld", paths(set), (long)state]];
    return set;
}
- (void)collectionView:(NSCollectionView *)cv didChangeItemsAtIndexPaths:(NSSet *)set
      toHighlightState:(NSCollectionViewItemHighlightState)state
{
    [self.log addObject:[NSString stringWithFormat:@"highlighted %@ %ld", paths(set), (long)state]];
}
- (void)flush:(const char *)what
{
    printf("%s: %s\n", what, [[self.log componentsJoinedByString:@"; "] UTF8String]);
    [self.log removeAllObjects];
}
@end

static void shown(NSCollectionView *cv, const char *what)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSCollectionViewItem *item in [cv visibleItems]) {
        NSIndexPath *p = [cv indexPathForItem:item];
        [a addObject:[NSString stringWithFormat:@"%ld.%ld=%@%s", (long)p.section, (long)p.item, [(Tile *)item name],
                                                [item isSelected] ? "*" : ""]];
    }
    printf("%s: %s\n", what, [[a componentsJoinedByString:@" "] UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];
        Pets *pets = [[Pets alloc] init];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
        NSCollectionView *cv = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
        NSCollectionViewFlowLayout *flow = [[NSCollectionViewFlowLayout alloc] init];
        printf("flow defaults: item %.0fx%.0f, lines %.0f, between %.0f\n", flow.itemSize.width, flow.itemSize.height,
               flow.minimumLineSpacing, flow.minimumInteritemSpacing);
        flow.itemSize = NSMakeSize(40, 30);
        flow.minimumLineSpacing = 5;
        flow.minimumInteritemSpacing = 10;
        flow.sectionInset = NSEdgeInsetsMake(5, 10, 5, 10);
        flow.headerReferenceSize = NSMakeSize(0, 20);
        flow.footerReferenceSize = NSMakeSize(0, 10);
        cv.collectionViewLayout = flow;
        [cv registerClass:[Tile class] forItemWithIdentifier:@"tile"];
        [cv registerClass:[Header class] forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
           withIdentifier:@"head"];
        [cv registerClass:[Header class] forSupplementaryViewOfKind:NSCollectionElementKindSectionFooter
           withIdentifier:@"foot"];
        cv.delegate = pets;
        cv.dataSource = pets;
        [scroll setDocumentView:cv];
        [[w contentView] addSubview:scroll];
        printf("flipped %d, selectable %d, empty %d, multiple %d\n", [cv isFlipped], cv.selectable,
               cv.allowsEmptySelection, cv.allowsMultipleSelection);

        /* ---- the flow layout, vertically ---- */
        printf("sections %ld, items %ld and %ld\n", (long)cv.numberOfSections, (long)[cv numberOfItemsInSection:0],
               (long)[cv numberOfItemsInSection:1]);
        NSSize cs = flow.collectionViewContentSize;
        printf("content %.0fx%.0f\n", cs.width, cs.height);
        /* 200 wide less insets of 10 and 10: three items of 40 with the gaps spread, 20 each */
        for (NSInteger i = 0; i < 7; i++)
            rect([[NSString stringWithFormat:@"item 0.%ld", (long)i] UTF8String],
                 [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame);
        rect("item 1.0", [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]].frame);
        rect("header 0", [cv layoutAttributesForSupplementaryElementOfKind:NSCollectionElementKindSectionHeader
                                                               atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame);
        rect("footer 0", [cv layoutAttributesForSupplementaryElementOfKind:NSCollectionElementKindSectionFooter
                                                               atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame);
        rect("header 1", [cv layoutAttributesForSupplementaryElementOfKind:NSCollectionElementKindSectionHeader
                                                               atIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]].frame);
        shown(cv, "in sight");
        rect("collection view", cv.frame);
        printf("made %d, reused %d\n", made, reused);
        printf("headers in sight %s, footers %s\n",
               [paths([cv indexPathsForVisibleSupplementaryElementsOfKind:NSCollectionElementKindSectionHeader]) UTF8String],
               [paths([cv indexPathsForVisibleSupplementaryElementsOfKind:NSCollectionElementKindSectionFooter]) UTF8String]);
        Header *h0 = (Header *)[cv supplementaryViewForElementKind:NSCollectionElementKindSectionHeader
                                                       atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
        printf("header view %s, %s\n", [h0.title UTF8String], [h0 superview] == cv ? "in the collection view" : "?");
        rect("its frame", h0.frame);
        NSIndexPath *at = [cv indexPathForItemAtPoint:NSMakePoint(75, 40)];
        printf("at 75,40: %ld.%ld; at 65,40 (a gap): %s\n", (long)at.section, (long)at.item,
               [cv indexPathForItemAtPoint:NSMakePoint(65, 40)] ? "an item" : "none");

        /* scrolling to items, and the views in sight following */
        [cv scrollToItemsAtIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:2 inSection:1]]
                       scrollPosition:NSCollectionViewScrollPositionBottom];
        rect("scrolled to 1.2 at the bottom", [[scroll contentView] bounds]);
        shown(cv, "in sight");
        printf("made %d, reused %d\n", made, reused);
        [cv scrollToItemsAtIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:3 inSection:0]]
                       scrollPosition:NSCollectionViewScrollPositionTop];
        rect("scrolled to 0.3 at the top", [[scroll contentView] bounds]);
        shown(cv, "in sight");
        printf("made %d, reused %d\n", made, reused);
        [cv scrollToItemsAtIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:0 inSection:0]]
                       scrollPosition:NSCollectionViewScrollPositionNearestHorizontalEdge];
        rect("scrolled to 0.0, nearest edge", [[scroll contentView] bounds]);

        /* pinned headers */
        flow.sectionHeadersPinToVisibleBounds = YES;
        [[scroll contentView] scrollToPoint:NSMakePoint(0, 60)];
        rect("header 0 pinned at 60",
             [cv layoutAttributesForSupplementaryElementOfKind:NSCollectionElementKindSectionHeader
                                                   atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame);
        [[scroll contentView] scrollToPoint:NSMakePoint(0, 0)];
        flow.sectionHeadersPinToVisibleBounds = NO;

        /* the delegate's own sizes, and a collapsed section */
        pets.ownSizes = YES;
        [flow invalidateLayout];
        for (NSInteger i = 0; i < 5; i++)
            rect([[NSString stringWithFormat:@"own size 0.%ld", (long)i] UTF8String],
                 [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame);
        pets.ownSizes = NO;
        [flow collapseSectionAtIndex:0];
        printf("collapsed 0: %d; ", [flow sectionAtIndexIsCollapsed:0]);
        NSCollectionViewLayoutAttributes *a4 = [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:4 inSection:0]];
        printf("item 0.4 %s; ", a4.hidden ? "hidden" : "shown");
        rect("item 1.0 now", [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]].frame);
        [flow expandSectionAtIndex:0];

        /* ---- the flow layout, horizontally ---- */
        flow.scrollDirection = NSCollectionViewScrollDirectionHorizontal;
        flow.headerReferenceSize = NSMakeSize(15, 0);
        flow.footerReferenceSize = NSZeroSize;
        cs = flow.collectionViewContentSize;
        printf("across: content %.0fx%.0f\n", cs.width, cs.height);
        for (NSInteger i = 0; i < 4; i++)
            rect([[NSString stringWithFormat:@"across 0.%ld", (long)i] UTF8String],
                 [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame);
        rect("across header 1",
             [cv layoutAttributesForSupplementaryElementOfKind:NSCollectionElementKindSectionHeader
                                                   atIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]].frame);
        shown(cv, "in sight");
        rect("collection view", cv.frame);
        flow.scrollDirection = NSCollectionViewScrollDirectionVertical;
        flow.headerReferenceSize = NSMakeSize(0, 20);
        flow.footerReferenceSize = NSMakeSize(0, 10);

        /* ---- the grid layout ---- */
        NSCollectionViewGridLayout *grid = [[NSCollectionViewGridLayout alloc] init];
        grid.minimumItemSize = NSMakeSize(50, 40);
        grid.maximumItemSize = NSMakeSize(80, 40);
        grid.margins = NSEdgeInsetsMake(5, 5, 5, 5);
        grid.minimumInteritemSpacing = 5;
        grid.minimumLineSpacing = 4;
        cv.collectionViewLayout = grid;
        cs = grid.collectionViewContentSize;
        printf("grid: content %.0fx%.0f\n", cs.width, cs.height);
        rect("grid 0.0", [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame);
        rect("grid 0.4", [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:4 inSection:0]].frame);
        rect("grid 1.0", [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]].frame);
        grid.maximumNumberOfColumns = 2;
        rect("two columns, 0.3", [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:3 inSection:0]].frame);
        grid.maximumNumberOfRows = 2;
        printf("two rows: 0.3 %s, 0.4 %s\n",
               [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:3 inSection:0]].hidden ? "hidden" : "shown",
               [cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:4 inSection:0]].hidden ? "hidden" : "shown");
        cv.collectionViewLayout = flow;
        [[scroll contentView] scrollToPoint:NSZeroPoint];

        /* ---- selection ---- */
        NSIndexPath *p00 = [NSIndexPath indexPathForItem:0 inSection:0], *p01 = [NSIndexPath indexPathForItem:1 inSection:0];
        NSIndexPath *p02 = [NSIndexPath indexPathForItem:2 inSection:0], *p03 = [NSIndexPath indexPathForItem:3 inSection:0];
        [cv selectItemsAtIndexPaths:[NSSet setWithObject:p01] scrollPosition:NSCollectionViewScrollPositionNone];
        printf("selected by code %s, item selected %d\n", [paths(cv.selectionIndexPaths) UTF8String],
               [[cv itemAtIndexPath:p01] isSelected]);
        [pets flush:"delegate"];
        cv.selectable = YES;
        NSRect f00 = [cv layoutAttributesForItemAtIndexPath:p00].frame, f02 = [cv layoutAttributesForItemAtIndexPath:p02].frame;
        NSRect f03 = [cv layoutAttributesForItemAtIndexPath:p03].frame;
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, cv, mid(f00), 0)];
        printf("pressed 0.0: highlight %ld, selection %s\n", (long)[[cv itemAtIndexPath:p00] highlightState],
               [paths(cv.selectionIndexPaths) UTF8String]);
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, cv, mid(f00), 0)];
        printf("released: highlight %ld, selection %s, first responder %d\n",
               (long)[[cv itemAtIndexPath:p00] highlightState], [paths(cv.selectionIndexPaths) UTF8String],
               cv.firstResponder);
        [pets flush:"delegate"];
        click(w, cv, mid(f02), NSEventModifierFlagCommand);
        printf("command-click 0.2, single selection: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets.log removeAllObjects];
        cv.allowsMultipleSelection = YES;
        click(w, cv, mid(f00), NSEventModifierFlagCommand);
        printf("command-click 0.0: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets flush:"delegate"];
        click(w, cv, mid(f03), NSEventModifierFlagShift);
        printf("shift-click 0.3: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets.log removeAllObjects];
        pets.refuse = @"eel";
        click(w, cv, mid([cv layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:4 inSection:0]].frame), 0);
        printf("click eel, which may not be selected: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets flush:"delegate"];
        pets.refuse = nil;
        click(w, cv, NSMakePoint(65, 40), 0);
        printf("click a gap: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets.log removeAllObjects];
        cv.allowsEmptySelection = NO;
        click(w, cv, mid(f00), 0);
        click(w, cv, NSMakePoint(65, 40), 0);
        printf("click a gap, empty not allowed: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets flush:"delegate"];
        /* keys: right along a line, then down a line, left at a line's start goes back */
        key(w, NSRightArrowFunctionKey, 0);
        printf("right: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        key(w, NSDownArrowFunctionKey, 0);
        printf("down: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        key(w, NSLeftArrowFunctionKey, 0);
        key(w, NSLeftArrowFunctionKey, 0);
        printf("left twice: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        key(w, NSRightArrowFunctionKey, NSEventModifierFlagShift);
        printf("shift-right: %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        [pets flush:"delegate"];
        [cv selectAll:nil];
        printf("select all: %lu selected\n", (unsigned long)[cv.selectionIndexPaths count]);
        [cv deselectAll:nil];
        printf("deselect all, empty not allowed: %lu selected\n", (unsigned long)[cv.selectionIndexPaths count]);
        cv.allowsEmptySelection = YES;
        [cv deselectAll:nil];
        printf("deselect all: %lu selected\n", (unsigned long)[cv.selectionIndexPaths count]);
        [pets.log removeAllObjects];
        cv.selectionIndexPaths = [NSSet setWithObjects:p01, [NSIndexPath indexPathForItem:9 inSection:0], nil];
        printf("set to 0.1 and 0.9 (not there): %s, indexes %lu\n", [paths(cv.selectionIndexPaths) UTF8String],
               (unsigned long)[cv.selectionIndexes firstIndex]);

        /* ---- updates ---- */
        shown(cv, "before");
        [pets.sections[0] insertObject:@"asp" atIndex:0];
        [cv insertItemsAtIndexPaths:[NSSet setWithObject:p00]];
        printf("inserted asp at 0.0: %ld items, selection %s\n", (long)[cv numberOfItemsInSection:0],
               [paths(cv.selectionIndexPaths) UTF8String]);
        shown(cv, "after");
        [pets.sections[0] removeObjectAtIndex:1];
        [cv deleteItemsAtIndexPaths:[NSSet setWithObject:p01]];
        printf("deleted ant: selection %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        shown(cv, "after");
        id moving = pets.sections[0][1];
        [pets.sections[0] removeObjectAtIndex:1];
        [pets.sections[0] insertObject:moving atIndex:4];
        [cv moveItemAtIndexPath:p01 toIndexPath:[NSIndexPath indexPathForItem:4 inSection:0]];
        printf("moved bee to 0.4: selection %s\n", [paths(cv.selectionIndexPaths) UTF8String]);
        shown(cv, "after");
        pets.sections[0][0] = @"auk";
        int was = reused;
        [cv reloadItemsAtIndexPaths:[NSSet setWithObject:p00]];
        Tile *after = (Tile *)[cv itemAtIndexPath:p00];
        printf("reloaded 0.0: now %s, %d item reused\n", [after.name UTF8String], reused - was);
        __block int ran = 0;
        [cv performBatchUpdates:^{
          /* delete cat (at 0.1 before) and dog (0.2), insert yak at 0.0 and emu at 0.3 (after) */
          [pets.sections[0] removeObjectsInRange:NSMakeRange(1, 2)];
          [pets.sections[0] insertObject:@"yak" atIndex:0];
          [pets.sections[0] insertObject:@"emu" atIndex:3];
          [cv deleteItemsAtIndexPaths:[NSSet setWithObjects:p01, p02, nil]];
          [cv insertItemsAtIndexPaths:[NSSet setWithObjects:p00, p03, nil]];
          ran++;
        }
                      completionHandler:^(BOOL finished) {
                        printf("batch done: finished %d, ran %d\n", finished, ran);
                      }];
        printf("after the batch: %ld items, selection %s\n", (long)[cv numberOfItemsInSection:0],
               [paths(cv.selectionIndexPaths) UTF8String]);
        shown(cv, "after");
        [pets.sections insertObject:[@[ @"koi" ] mutableCopy] atIndex:0];
        [cv insertSections:[NSIndexSet indexSetWithIndex:0]];
        printf("inserted a section: %ld sections, selection %s\n", (long)cv.numberOfSections,
               [paths(cv.selectionIndexPaths) UTF8String]);
        [pets.sections exchangeObjectAtIndex:1 withObjectAtIndex:2];
        [cv moveSection:1 toSection:2];
        printf("moved section 1 to 2: selection %s, 1.0 is %s\n", [paths(cv.selectionIndexPaths) UTF8String],
               [[pets nameAt:[NSIndexPath indexPathForItem:0 inSection:1]] UTF8String]);
        [pets.sections removeObjectAtIndex:0];
        [cv deleteSections:[NSIndexSet indexSetWithIndex:0]];
        printf("deleted section 0: %ld sections, selection %s\n", (long)cv.numberOfSections,
               [paths(cv.selectionIndexPaths) UTF8String]);
        [cv reloadSections:[NSIndexSet indexSetWithIndex:0]];
        [cv reloadData];
        shown(cv, "reloaded");
        printf("made %d, reused %d\n", made, reused);
        printf("sets: %s, enumerated", [paths([NSSet setWithCollectionViewIndexPaths:@[ p02, p00 ]]) UTF8String]);
        [[NSSet setWithCollectionViewIndexPaths:@[ p02, p00, p01 ]]
            enumerateIndexPathsWithOptions:NSEnumerationReverse
                                usingBlock:^(NSIndexPath *p, BOOL *stop) {
                                  printf(" %ld.%ld", (long)p.section, (long)p.item);
                                }];
        printf("\n");
    }
    return 0;
}
