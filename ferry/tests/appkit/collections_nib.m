/* SPDX-License-Identifier: GPL-3.0-or-later
 * A collection view of the older kind loaded from a nib (Collections.nib,
 * and CollectionsArchive.nib in the NIBArchive form, both written by
 * make_collection_nibs.py), with no display: its settings from the nib's
 * keys, and its item prototype (of the app's class, by a class swapper)
 * copied for each content object, with a view, field and button of its
 * own, its outlets pointing into its own view, its field's binding to its
 * represented object, and its button's action going to File's Owner. */
#import <Cocoa/Cocoa.h>

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}

@interface PetItem : NSCollectionViewItem
@property (assign) IBOutlet NSTextField *label;
@end
@implementation PetItem
@end

@interface CollectionOwner : NSObject
@property (strong) IBOutlet NSView *view;
@property (assign) IBOutlet NSCollectionView *collection;
@property (strong) NSMutableArray *pressed;
@end
@implementation CollectionOwner
- (IBAction)petPressed:(id)sender
{
    NSView *v = sender;
    while (v && ![[v nextResponder] isKindOfClass:[NSCollectionViewItem class]])
        v = [v superview];
    id item = [v nextResponder];
    [self.pressed addObject:[[item representedObject] objectForKey:@"name"] ?: @"?"];
}
@end

static void load(const char *file)
{
    printf("---- %s\n", file);
    CollectionOwner *owner = [[CollectionOwner alloc] init];
    owner.pressed = [NSMutableArray array];
    NSString *path = [NSString stringWithFormat:@"%s/%s", getenv("FERRY_TEST_DATA"), file];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:path bundle:nil];
    NSArray *top = nil;
    printf("loaded %d\n", [nib instantiateWithOwner:owner topLevelObjects:&top]);
    NSCollectionView *cv = owner.collection;
    printf("collection view %s, in the view %d\n", object_getClassName(cv), [cv superview] == owner.view);
    printf("selectable %d, multiple %d, empty %d, columns %lu, rows %lu\n", cv.selectable, cv.allowsMultipleSelection,
           cv.allowsEmptySelection, (unsigned long)cv.maxNumberOfColumns, (unsigned long)cv.maxNumberOfRows);
    NSSize min = cv.minItemSize;
    CGFloat white = -1;
    [[[cv.backgroundColors firstObject] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] getWhite:&white alpha:NULL];
    printf("smallest item %.0fx%.0f, %lu background colour, white %.1f\n", min.width, min.height,
           (unsigned long)[cv.backgroundColors count], white);
    PetItem *proto = (PetItem *)cv.itemPrototype;
    printf("prototype a %s, view %s, label %s in it, text field the label %d\n", [NSStringFromClass([proto class]) UTF8String],
           [proto view] ? "set" : "missing", [proto.label superview] == [proto view] ? "is" : "isn't",
           proto.textField == proto.label);

    NSArray *pets = @[ [@{ @"name" : @"Rex" } mutableCopy], [@{ @"name" : @"Tib" } mutableCopy],
                       [@{ @"name" : @"Ozzy" } mutableCopy] ];
    cv.content = pets;
    NSMutableSet *views = [NSMutableSet setWithObject:[NSValue valueWithPointer:(__bridge void *)[proto view]]];
    for (NSUInteger i = 0; i < [pets count]; i++) {
        PetItem *item = (PetItem *)[cv itemAtIndex:i];
        NSView *v = [item view];
        [views addObject:[NSValue valueWithPointer:(__bridge void *)v]];
        NSButton *button = nil;
        for (NSView *s in [v subviews])
            if ([s isKindOfClass:[NSButton class]])
                button = (NSButton *)s;
        printf("item %lu: a %s, %s, label \"%s\" %s its view, text field the label %d, button to %s\n", (unsigned long)i,
               [NSStringFromClass([item class]) UTF8String], item == proto ? "the prototype" : "a copy", [[item.label stringValue] UTF8String],
               [item.label superview] == v ? "in" : "not in", item.textField == item.label,
               [button target] == owner ? "File's Owner" : "somewhere else");
        rect("  frame", [v frame]);
        [button performClick:nil];
    }
    printf("views: %lu, all different\n", (unsigned long)[views count]);
    printf("pressed: %s\n", [[owner.pressed componentsJoinedByString:@" "] UTF8String]);
    [pets[1] setValue:@"Tibbles" forKey:@"name"];
    printf("renamed: label \"%s\"; prototype's label \"%s\"\n",
           [[((PetItem *)[cv itemAtIndex:1]).label stringValue] UTF8String], [[proto.label stringValue] UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        load("Collections.nib");
        load("CollectionsArchive.nib");
    }
    return 0;
}
