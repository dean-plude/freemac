/* SPDX-License-Identifier: GPL-3.0-or-later
 * What MacPass and its HNHUi and KeePassKit need from AppKit and Core Image
 * (freemac 1.225, Ferry 0.49.0): a window controller that names its nib by
 * overriding -windowNibName, a table of the app's own class whose columns
 * point back at it, grid views (from a nib and made in code), Core Image's
 * images, filters, contexts and detectors, a text field cell's bezel, an
 * icon for a content type and a bitmap read from a focused view; and a nib
 * from a xib in the older format (an archive of objects with their keys),
 * which MASPreferences in MacDown ships. With no display; MacPassUI.nib and
 * ArchiveFormat.nib are compiled by ferry-ibtool next to the program. */
#import <Cocoa/Cocoa.h>
#import <CoreImage/CoreImage.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface UITable : NSTableView
@end
@implementation UITable
@end

@interface UIController : NSWindowController
@property (assign) IBOutlet NSGridView *grid;
@property (assign) IBOutlet NSTableView *table;
@property (assign) IBOutlet NSTextField *nameLabel, *nameField, *noteField;
@end
@implementation UIController
- (NSString *)windowNibName { return @"MacPassUI"; }
@end

/* File's Owner of ArchiveFormat.nib, compiled from a xib in the older
 * format (MASPreferences, which MacDown uses, ships one) */
@interface OldOwner : NSObject <NSWindowDelegate>
@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSToolbar *toolbar;
@end
@implementation OldOwner
@end

static void frame(const char *what, NSView *v)
{
    NSRect f = v.frame;
    printf("  %s: %g %g %g %g%s\n", what, f.origin.x, f.origin.y, f.size.width, f.size.height, v.hidden ? " hidden" : "");
}

static NSView *box(CGFloat w, CGFloat h)
{
    return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* the nib a subclass names, loaded by -window */
        UIController *wc = [[UIController alloc] initWithWindow:nil];
        NSWindow *w = wc.window;
        printf("window: %s, \"%s\", owner's outlet %s\n", w ? "loaded" : "none", w.title.UTF8String,
               wc.window == w && w.windowController == wc ? "set" : "unset");
        printf("table: %s, %ld columns, each column's table is it: %d\n", [wc.table className].UTF8String,
               (long)wc.table.numberOfColumns,
               wc.table.tableColumns[0].tableView == wc.table && wc.table.tableColumns[1].tableView == wc.table);

        /* the grid from the nib */
        NSGridView *g = wc.grid;
        printf("grid: %ld rows, %ld columns, spacing %g %g, row 3 hidden %d\n", (long)g.numberOfRows,
               (long)g.numberOfColumns, g.rowSpacing, g.columnSpacing, [g rowAtIndex:2].hidden);
        [g layoutSubtreeIfNeeded];
        NSRect lf = wc.nameLabel.frame, ff = wc.nameField.frame, nf = wc.noteField.frame;
        printf("  label at the column's trailing edge, field %g after it, %g wide (its own width, as editable)\n",
               ff.origin.x - NSMaxX(lf), ff.size.width);
        printf("  note: x %g, %g wide, %g below the first row (spacing and padding)\n", nf.origin.x, nf.size.width,
               nf.origin.y - NSMaxY(ff) - (100 - (NSMaxY(ff) + 12 + 22)) / 2);
        printf("  note's cell: row %ld column %ld\n", (long)[g indexOfRow:[g cellForView:wc.noteField].row],
               (long)[g indexOfColumn:[g cellForView:wc.noteField].column]);

        /* a grid made in code */
        NSView *a = box(50, 20), *b = box(100, 30), *c = box(80, 20), *d = box(40, 10);
        NSGridView *gv = [NSGridView gridViewWithViews:@[ @[ a, b ], @[ c, d ] ]];
        gv.frame = NSMakeRect(0, 0, 300, 100);
        gv.rowSpacing = 5;
        gv.columnSpacing = 10;
        [gv layoutSubtreeIfNeeded];
        printf("made grid: %ld x %ld, flipped %d\n", (long)gv.numberOfRows, (long)gv.numberOfColumns, gv.isFlipped);
        frame("a", a);
        frame("b", b);
        frame("c", c);
        frame("d", d);
        [gv columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
        [gv rowAtIndex:0].yPlacement = NSGridCellPlacementCenter;
        [gv columnAtIndex:1].width = 120;
        [gv layoutSubtreeIfNeeded];
        printf("trailing column 0, centred row 0, column 1 120 wide:\n");
        frame("a", a);
        frame("c", c);
        frame("d", d);
        [gv rowAtIndex:1].yPlacement = NSGridCellPlacementTop;
        [gv layoutSubtreeIfNeeded];
        printf("row 1 at its top:\n");
        frame("c", c);
        [gv rowAtIndex:0].hidden = YES;
        [gv layoutSubtreeIfNeeded];
        printf("row 0 hidden:\n");
        frame("a", a);
        frame("c", c);
        NSView *e = box(30, 30);
        [gv addRowWithViews:@[ e ]];
        printf("added row: %ld rows, empty cell's view %s, e's cell in row %ld\n", (long)gv.numberOfRows,
               [gv cellAtColumnIndex:1 rowIndex:2].contentView ? "set" : "none",
               (long)[gv indexOfRow:[gv cellForView:e].row]);
        [gv removeRowAtIndex:0];
        printf("removed row 0: %ld rows, a in grid %d\n", (long)gv.numberOfRows, a.superview == gv);

        /* Core Image */
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:10 pixelsHigh:20
                                                                     bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                          isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:0];
        CIImage *ci = [[CIImage alloc] initWithBitmapImageRep:rep];
        printf("CIImage: %g x %g\n", ci.extent.size.width, ci.extent.size.height);
        CIFilter *scale = [CIFilter filterWithName:@"CIAffineTransform"];
        [scale setValue:ci forKey:kCIInputImageKey];
        [scale setValue:[NSValue valueWithBytes:&(CGAffineTransform){3, 0, 0, 2, 0, 0} objCType:@encode(CGAffineTransform)]
                 forKey:kCIInputTransformKey];
        CIImage *big = scale.outputImage;
        printf("scaled: %g x %g, cropped: %g x %g\n", big.extent.size.width, big.extent.size.height,
               [big imageByCroppingToRect:CGRectMake(0, 0, 5, 5)].extent.size.width,
               [big imageByCroppingToRect:CGRectMake(0, 0, 5, 5)].extent.size.height);
        CGImageRef cg = [[CIContext context] createCGImage:big fromRect:big.extent];
        printf("rendered: %zu x %zu\n", CGImageGetWidth(cg), CGImageGetHeight(cg));
        CGImageRelease(cg);
        printf("filters: unknown %s, QR generator %s\n", [CIFilter filterWithName:@"CINoSuchFilter"] ? "made" : "nil",
               [CIFilter filterWithName:@"CIQRCodeGenerator"] ? "made" : "nil");
        CIDetector *det = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
                                             options:@{ CIDetectorAccuracy: CIDetectorAccuracyHigh }];
        printf("detector: %s, %lu features\n", det ? "made" : "nil", (unsigned long)[det featuresInImage:ci].count);
        NSCIImageRep *ciRep = [NSCIImageRep imageRepWithCIImage:ci];
        printf("NSCIImageRep: %g x %g\n", ciRep.size.width, ciRep.size.height);

        /* a text field's cell keeps its field's bezel */
        NSTextField *tf = wc.nameField;
        tf.bezelStyle = NSTextFieldRoundedBezel;
        printf("bezel: field %ld, cell %ld\n", (long)tf.bezelStyle, (long)((NSTextFieldCell *)tf.cell).bezelStyle);
        ((NSTextFieldCell *)tf.cell).bezelStyle = NSTextFieldSquareBezel;
        printf("bezel set on cell: field %ld\n", (long)tf.bezelStyle);

        /* an icon for a content type */
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForContentType:UTTypePlainText];
        printf("icon: %s\n", icon && icon.size.width > 0 ? "made" : "none");

        /* a bitmap of what was drawn in a focused image */
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
        [img lockFocus];
        [[NSColor redColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 8, 8));
        [[NSColor blueColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 4, 4));
        NSBitmapImageRep *read = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, 8, 8)];
        [img unlockFocus];
        NSColor *top = [[read colorAtX:6 y:1] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor *bottom = [[read colorAtX:1 y:6] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        printf("focused view: %ld x %ld, top right red %d, bottom left blue %d\n", (long)read.pixelsWide,
               (long)read.pixelsHigh, top.redComponent > 0.9 && top.blueComponent < 0.1,
               bottom.blueComponent > 0.9 && bottom.redComponent < 0.1);

        /* a nib from the older xib format: its window, toolbar, content
         * view, outlets and the window's delegate */
        OldOwner *old = [OldOwner new];
        NSArray *tops = nil;
        NSNib *oldNib = [[NSNib alloc] initWithNibNamed:@"ArchiveFormat" bundle:nil];
        BOOL loaded = [oldNib instantiateWithOwner:old topLevelObjects:&tops];
        NSWindow *ow = old.window;
        printf("older format: loaded %d, window \"%s\" %g x %g, visible %d, delegate is owner %d\n", loaded,
               ow.title.UTF8String, ow.contentView.frame.size.width, ow.contentView.frame.size.height,
               ow.isVisible, ow.delegate == old);
        /* the numbers and switches, kept in each object's own keys */
        printf("  style mask %lu; toolbar: outlet %s, \"%s\", window's toolbar is it %d\n",
               (unsigned long)ow.styleMask, [old.toolbar className].UTF8String, old.toolbar.identifier.UTF8String,
               ow.toolbar == old.toolbar);
        printf("  display mode %ld, size mode %ld, shown %d, customizable %d\n", (long)old.toolbar.displayMode,
               (long)old.toolbar.sizeMode, old.toolbar.isVisible, old.toolbar.allowsUserCustomization);
    }
    return 0;
}
