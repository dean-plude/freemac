/* SPDX-License-Identifier: GPL-3.0-or-later
 * Collection views of the older kind, with no display: an array of content
 * objects and an item prototype copied for each (a prototype made in code
 * whose class makes its own view), the grid made from the prototype's
 * size with the maximum numbers of rows and columns and the minimum and
 * maximum item sizes, frameForItemAtIndex:, items kept for objects that
 * stay when the content changes, content and selectionIndexes bound to an
 * array controller both ways, a click selecting and the selection
 * observed, and the background colours drawn into a bitmap (one colour,
 * and rows of two in turn). */
#import <Cocoa/Cocoa.h>

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
static NSString *indexes(NSIndexSet *set)
{
    NSMutableArray *a = [NSMutableArray array];
    [set enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
      [a addObject:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
    }];
    return [NSString stringWithFormat:@"{%@}", [a componentsJoinedByString:@","]];
}
static void click(NSWindow *w, NSView *v, NSPoint p)
{
    for (NSEventType t = NSEventTypeLeftMouseDown; t <= NSEventTypeLeftMouseUp; t++)
        [w sendEvent:[NSEvent mouseEventWithType:t location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                                    windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1]];
}
static void pixel(const char *what, NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    printf("%s (%d,%d from the top): %.1f %.1f %.1f\n", what, x, y, r, g, b);
}

@interface Person : NSObject
@property (copy) NSString *name;
@end
@implementation Person
+ (instancetype)named:(NSString *)name
{
    Person *p = [[Person alloc] init];
    p.name = name;
    return p;
}
@end

/* A prototype whose class makes its view, with a field showing the name. */
static int views;
@interface Card : NSCollectionViewItem
@property (strong) NSTextField *label;
@end
@implementation Card
- (void)loadView
{
    views++;
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 60, 30)];
    self.label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 60, 20)];
    [self.label setEditable:NO];
    [self.label setSelectable:NO];
    [v addSubview:self.label];
    [self setView:v];
}
- (void)setRepresentedObject:(id)o
{
    [super setRepresentedObject:o];
    [self view];
    [self.label setStringValue:[o name] ?: @""];
}
@end

@interface Watcher : NSObject
@property int changes;
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx
{
    self.changes++;
}
@end

static void names(NSCollectionView *cv, const char *what)
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < [cv.content count]; i++) {
        Card *c = (Card *)[cv itemAtIndex:i];
        [a addObject:[NSString stringWithFormat:@"%@%s", [c.label stringValue], c.selected ? "*" : ""]];
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
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSCollectionView *cv = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        [scroll setDocumentView:cv];
        [[w contentView] addSubview:scroll];
        printf("bindings: %s\n", [[[cv exposedBindings] componentsJoinedByString:@" "] UTF8String]);

        Card *prototype = [[Card alloc] init];
        cv.itemPrototype = prototype;
        NSArray *people = @[ [Person named:@"Ada"], [Person named:@"Bo"], [Person named:@"Cy"], [Person named:@"Di"],
                             [Person named:@"Ed"] ];
        cv.content = people;
        printf("sections %ld, items %ld, views made %d\n", (long)cv.numberOfSections,
               (long)[cv numberOfItemsInSection:0], views);
        Card *c0 = (Card *)[cv itemAtIndex:0], *c1 = (Card *)[cv itemAtIndex:1];
        printf("item 0: a %s, %s, for %s, view %s, in the collection view %d, its collection view %d\n",
               object_getClassName(c0), c0 == prototype ? "the prototype" : "a copy", [[c0.representedObject name] UTF8String],
               [c0 view] == [prototype view] ? "the prototype's" : "its own", [[c0 view] superview] == cv,
               c0.collectionView == cv);
        printf("item 1 for %s, field \"%s\"; prototype's field \"%s\"\n", [[c1.representedObject name] UTF8String],
               [[c1.label stringValue] UTF8String], [[prototype.label stringValue] UTF8String]);
        /* the prototype is 60 wide: three columns, each stretched to a third */
        for (NSUInteger i = 0; i < 5; i++)
            rect([[NSString stringWithFormat:@"item %lu", (unsigned long)i] UTF8String], [cv frameForItemAtIndex:i]);
        rect("its view", [[cv itemAtIndex:4] view].frame);
        rect("collection view", cv.frame);
        rect("item 7 of 8", [cv frameForItemAtIndex:7 withNumberOfItems:8]);
        cv.maxNumberOfColumns = 2;
        rect("two columns, item 3", [cv frameForItemAtIndex:3]);
        cv.maxItemSize = NSMakeSize(80, 30);
        rect("at most 80 wide, item 1", [cv frameForItemAtIndex:1]);
        cv.maxNumberOfColumns = 0;
        cv.maxNumberOfRows = 1;
        rect("one row, item 4", [cv frameForItemAtIndex:4]);
        [cv itemAtIndex:0]; /* laid out */
        rect("collection view, laid out", cv.frame);
        cv.maxNumberOfRows = 0;
        cv.minItemSize = NSMakeSize(90, 40);
        rect("at least 90x40, item 1", [cv frameForItemAtIndex:1]);
        cv.minItemSize = NSZeroSize;
        cv.maxItemSize = NSZeroSize;
        NSPoint at = NSMakePoint(NSMidX([cv frameForItemAtIndex:4]), NSMidY([cv frameForItemAtIndex:4]));
        NSIndexPath *p = [cv indexPathForItemAtPoint:at];
        printf("at item 4's middle: %ld.%ld\n", (long)p.section, (long)p.item);

        /* content changing: items for the objects that stay are kept */
        NSCollectionViewItem *c4 = [cv itemAtIndex:4];
        cv.content = @[ people[4], people[0], [Person named:@"Flo"] ];
        printf("new content: Ed's item %s, Ada's %s, views made %d\n", c4 == [cv itemAtIndex:0] ? "kept" : "new",
               c0 == [cv itemAtIndex:1] ? "kept" : "new", views);
        names(cv, "items");
        printf("subviews %lu\n", (unsigned long)[[cv subviews] count]);

        /* ---- bound to an array controller ---- */
        NSArrayController *ac = [[NSArrayController alloc] initWithContent:[people mutableCopy]];
        [ac setSelectsInsertedObjects:NO];
        [cv bind:NSContentBinding toObject:ac withKeyPath:@"arrangedObjects" options:nil];
        [cv bind:NSSelectionIndexesBinding toObject:ac withKeyPath:@"selectionIndexes" options:nil];
        Watcher *watch = [[Watcher alloc] init];
        [cv addObserver:watch forKeyPath:@"selectionIndexes" options:0 context:NULL];
        names(cv, "bound");
        [ac setSelectionIndex:2];
        names(cv, "controller selects 2");
        printf("selection %s, observed %d\n", [indexes(cv.selectionIndexes) UTF8String], watch.changes);
        [ac addObject:[Person named:@"Gus"]];
        names(cv, "controller adds Gus");
        cv.selectable = YES;
        NSRect f3 = [cv frameForItemAtIndex:3];
        click(w, cv, NSMakePoint(NSMidX(f3), NSMinY(f3) + 2)); /* above the item's field */
        printf("clicked item 3: collection view %s, controller %s, observed %d\n", [indexes(cv.selectionIndexes) UTF8String],
               [indexes([ac selectionIndexes]) UTF8String], watch.changes);
        names(cv, "items");
        cv.allowsMultipleSelection = YES;
        NSRect f0 = [cv frameForItemAtIndex:0];
        [w sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                        location:[cv convertPoint:NSMakePoint(NSMidX(f0), NSMinY(f0) + 2) toView:nil]
                                   modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[w windowNumber]
                                         context:nil eventNumber:0 clickCount:1 pressure:1]];
        [w sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                        location:[cv convertPoint:NSMakePoint(NSMidX(f0), NSMinY(f0) + 2) toView:nil]
                                   modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[w windowNumber]
                                         context:nil eventNumber:0 clickCount:1 pressure:1]];
        printf("command-clicked item 0: controller %s\n", [indexes([ac selectionIndexes]) UTF8String]);
        [ac removeObjectAtArrangedObjectIndex:1];
        names(cv, "controller removes Bo");
        [cv removeObserver:watch forKeyPath:@"selectionIndexes"];
        [cv unbind:NSContentBinding];
        [cv unbind:NSSelectionIndexesBinding];

        /* ---- background colours ---- */
        cv.content = @[];
        printf("default colours: %lu\n", (unsigned long)[cv.backgroundColors count]);
        cv.backgroundColors = @[ [NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1] ];
        NSBitmapImageRep *rep = [cv bitmapImageRepForCachingDisplayInRect:[cv bounds]];
        [cv cacheDisplayInRect:[cv bounds] toBitmapImageRep:rep];
        pixel("one colour", rep, 100, 50);
        cv.backgroundColors = @[ [NSColor colorWithDeviceRed:1 green:1 blue:1 alpha:1],
                                 [NSColor colorWithDeviceRed:0 green:0 blue:1 alpha:1] ];
        cv.content = people;
        rep = [cv bitmapImageRepForCachingDisplayInRect:[cv bounds]];
        [cv cacheDisplayInRect:[cv bounds] toBitmapImageRep:rep];
        pixel("first row", rep, 180, 10);
        pixel("second row", rep, 180, 40);
    }
    return 0;
}
