/* SPDX-License-Identifier: GPL-3.0-or-later
 * The older AppKit and WebKit names Sequel Pro uses (freemac 1.226, Ferry
 * 0.50.0): the window and bezel style names, colour lists, HFS type codes
 * as file types, base coordinates, the layout manager's glyph queries, the
 * token field cell's delegate, PICT image reps, matrices of cells, the
 * spelling checker, and WebKit's history items and back-forward list; and
 * newer calls Sequel Pro also makes: more of NSCell, the graphics port,
 * background layout, and frame notifications only for a frame that
 * changes. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Receiver : NSObject
@property (retain) id last;
@property NSInteger count;
@end
@implementation Receiver
- (void)chose:(id)sender
{
    self.last = sender;
    self.count++;
}
@end

@interface CellDelegate : NSObject <NSTokenFieldCellDelegate>
@end
@implementation CellDelegate
@end

static void names(void)
{
    printf("names:\n");
    printf("  textured window %lu, thick bezels %lu %lu, folder icon '%c%c%c%c'\n",
           (unsigned long)NSTexturedBackgroundWindowMask, (unsigned long)NSThickSquareBezelStyle,
           (unsigned long)NSThickerSquareBezelStyle, (char)(kGenericFolderIcon >> 24),
           (char)(kGenericFolderIcon >> 16), (char)(kGenericFolderIcon >> 8), (char)kGenericFolderIcon);
    printf("  excluded elements key: %s\n", [NSExcludedElementsDocumentAttribute UTF8String]);
    printf("  summary keys: %s %s\n", [NSPrintPanelAccessorySummaryItemNameKey UTF8String],
           [NSPrintPanelAccessorySummaryItemDescriptionKey UTF8String]);
}

static void hfs_types(void)
{
    printf("HFS type codes:\n");
    NSString *folder = NSFileTypeForHFSTypeCode(kGenericFolderIcon);
    printf("  %s -> 0x%08x\n", [folder UTF8String], (unsigned)NSHFSTypeCodeFromFileType(folder));
    printf("  bare: 0x%08x, wrong: 0x%x\n", (unsigned)NSHFSTypeCodeFromFileType(@"TEXT"),
           (unsigned)NSHFSTypeCodeFromFileType(@"text file"));
    printf("  of /: %s, of nothing: %s\n", [NSHFSTypeOfFile(@"/") UTF8String],
           NSHFSTypeOfFile(@"/no/such/file") ? "something" : "nil");
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:folder];
    printf("  folder icon: %d\n", icon != nil && [icon size].width > 0);
}

static void color_lists(void)
{
    printf("colour lists:\n");
    NSColorList *system = [NSColorList colorListNamed:@"System"];
    printf("  System: %d, editable %d, has controlColor %d\n", system != nil, [system isEditable],
           [[system allKeys] containsObject:@"controlColor"]);
    NSColor *c = [system colorWithKey:@"windowBackgroundColor"];
    printf("  windowBackgroundColor: %d, same as NSColor's %d\n", c != nil,
           [c isEqual:[NSColor windowBackgroundColor]]);
    printf("  no such colour: %s\n", [system colorWithKey:@"noSuchColor"] ? "found" : "nil");
    [system setColor:[NSColor redColor] forKey:@"mine"];
    printf("  System unchanged: %d\n", [system colorWithKey:@"mine"] == nil);

    NSColorList *mine = [[NSColorList alloc] initWithName:@"Mine"];
    [mine setColor:[NSColor redColor] forKey:@"red"];
    [mine setColor:[NSColor blueColor] forKey:@"blue"];
    [mine insertColor:[NSColor greenColor] key:@"green" atIndex:0];
    printf("  Mine: %s\n", [[[mine allKeys] componentsJoinedByString:@" "] UTF8String]);
    printf("  found by name: %d, listed %d\n", [NSColorList colorListNamed:@"Mine"] == mine,
           [[NSColorList availableColorLists] containsObject:mine]);
    [mine removeColorWithKey:@"red"];
    printf("  after removing red: %s\n", [[[mine allKeys] componentsJoinedByString:@" "] UTF8String]);
    NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:mine];
    NSColorList *back = [NSKeyedUnarchiver unarchiveObjectWithData:archived];
    printf("  archived and back: %s, %s\n", [[back name] UTF8String],
           [[[back allKeys] componentsJoinedByString:@" "] UTF8String]);
    [mine removeFile];
    printf("  removed: %s\n", [NSColorList colorListNamed:@"Mine"] == mine ? "still listed" : "gone");
    [mine release];
}

static void base_coordinates(void)
{
    printf("base coordinates:\n");
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:YES];
    NSView *v = [[[NSView alloc] initWithFrame:NSMakeRect(20, 30, 100, 50)] autorelease];
    [[w contentView] addSubview:v];
    NSRect r = [v convertRectToBase:NSMakeRect(5, 5, 10, 10)];
    printf("  to base: %.0f,%.0f %.0fx%.0f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
    r = [v convertRectFromBase:r];
    printf("  and back: %.0f,%.0f\n", r.origin.x, r.origin.y);
    NSPoint p = [v convertPointToBase:NSMakePoint(1, 2)];
    printf("  point: %.0f,%.0f, size %.0f\n", p.x, p.y, [v convertSizeToBase:NSMakeSize(3, 4)].height);
    [w release];
}

static void glyphs(void)
{
    printf("layout manager:\n");
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)] autorelease];
    [tv setString:@"Hello world"];
    NSLayoutManager *lm = [tv layoutManager];
    NSRange all = [lm glyphRangeForBoundingRectWithoutAdditionalLayout:NSMakeRect(0, 0, 400, 100)
                                                       inTextContainer:[tv textContainer]];
    printf("  glyphs in view: %lu+%lu\n", (unsigned long)all.location, (unsigned long)all.length);
    NSRect g = [lm boundingRectForGlyphRange:NSMakeRange(4, 1) inTextContainer:[tv textContainer]];
    CGFloat fraction = -1;
    NSUInteger i = [lm glyphIndexForPoint:NSMakePoint(NSMinX(g) + NSWidth(g) * 0.25, NSMidY(g))
                          inTextContainer:[tv textContainer]
           fractionOfDistanceThroughGlyph:&fraction];
    printf("  a quarter into the fifth glyph: glyph %lu, fraction %.2f\n", (unsigned long)i, fraction);
    i = [lm glyphIndexForPoint:NSMakePoint(NSMinX(g) + NSWidth(g) * 0.75, NSMidY(g))
                     inTextContainer:[tv textContainer]
        fractionOfDistanceThroughGlyph:&fraction];
    printf("  three quarters in: glyph %lu, fraction %.2f\n", (unsigned long)i, fraction);
}

static void cells_and_matrices(void)
{
    printf("token field cell:\n");
    NSTokenFieldCell *cell = [[[NSTokenFieldCell alloc] initTextCell:@""] autorelease];
    CellDelegate *d = [[[CellDelegate alloc] init] autorelease];
    [cell setDelegate:d];
    printf("  delegate kept: %d\n", [cell delegate] == d);

    printf("PICT:\n");
    NSPICTImageRep *pict = [[NSPICTImageRep alloc] initWithData:[NSData dataWithBytes:"PICT" length:4]];
    printf("  from data: %s, can read %d\n", pict ? "a rep" : "nil",
           [NSPICTImageRep canInitWithData:[NSData data]]);

    printf("NSMatrix:\n");
    NSButtonCell *prototype = [[[NSButtonCell alloc] init] autorelease];
    [prototype setButtonType:NSButtonTypeRadio];
    NSMatrix *m = [[[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 100, 41) mode:NSRadioModeMatrix
                                          prototype:prototype numberOfRows:2 numberOfColumns:1] autorelease];
    [m setCellSize:NSMakeSize(100, 20)];
    [[m cellAtRow:0 column:0] setTitle:@"Sheet per table"];
    [[m cellAtRow:0 column:0] setTag:1];
    [[m cellAtRow:1 column:0] setTitle:@"File per table"];
    [[m cellAtRow:1 column:0] setTag:2];
    printf("  %ld x %ld, %lu cells, buttons %lu\n", (long)[m numberOfRows], (long)[m numberOfColumns],
           (unsigned long)[[m cells] count], (unsigned long)[[m subviews] count]);
    [m selectCellWithTag:2];
    printf("  selected tag %ld, row %ld, states %ld %ld\n", (long)[m selectedTag], (long)[m selectedRow],
           (long)[[m cellAtRow:0 column:0] state], (long)[[m cellAtRow:1 column:0] state]);
    Receiver *rx = [[[Receiver alloc] init] autorelease];
    [m setTarget:rx];
    [m setAction:@selector(chose:)];
    NSButton *first = (NSButton *)[[m subviews] objectAtIndex:0];
    [first performClick:nil];
    printf("  clicked the first: sender is the matrix %d, selected tag %ld, states %ld %ld, sent %ld\n",
           rx.last == m, (long)[m selectedTag], (long)[[m cellAtRow:0 column:0] state],
           (long)[[m cellAtRow:1 column:0] state], (long)rx.count);
    NSInteger row = -1, col = -1;
    [m getRow:&row column:&col ofCell:[m cellWithTag:2]];
    printf("  tag 2 at row %ld column %ld; frame of row 1: y %.0f\n", (long)row, (long)col,
           [m cellFrameAtRow:1 column:0].origin.y);
    [m addRow];
    printf("  a row added: %ld rows, %lu buttons\n", (long)[m numberOfRows], (unsigned long)[[m subviews] count]);

    printf("NSSpellChecker:\n");
    NSSpellChecker *s = [NSSpellChecker sharedSpellChecker];
    NSRange wrong = [s checkSpellingOfString:@"Ths is speled wrong" startingAt:0];
    printf("  shared %d, misspelled at %s, completions %lu\n", [NSSpellChecker sharedSpellCheckerExists],
           wrong.location == NSNotFound ? "none" : "some",
           (unsigned long)[[s completionsForPartialWordRange:NSMakeRange(0, 3) inString:@"sel" language:nil
                                      inSpellDocumentWithTag:0] count]);
    [s learnWord:@"MySQL"];
    NSInteger tag = [NSSpellChecker uniqueSpellDocumentTag];
    [s ignoreWord:@"InnoDB" inSpellDocumentWithTag:tag];
    printf("  learned %d, ignored %s, words %ld\n", [s hasLearnedWord:@"MySQL"],
           [[[s ignoredWordsInSpellDocumentWithTag:tag] firstObject] UTF8String],
           (long)[s countWordsInString:@"three little words" language:nil]);
}

static void history(void)
{
    printf("WebKit history:\n");
    WebHistoryItem *a = [[[WebHistoryItem alloc] initWithURLString:@"applewebdata://SHOW" title:@"SHOW"
                                           lastVisitedTimeInterval:5] autorelease];
    printf("  item: %s \"%s\" %.0f\n", [[a URLString] UTF8String], [[a title] UTF8String],
           [a lastVisitedTimeInterval]);
    WebBackForwardList *list = [[[WebBackForwardList alloc] init] autorelease];
    printf("  empty: back %d forward %d, capacity %d\n", [list backListCount], [list forwardListCount],
           [list capacity]);
    for (NSString *word in @[ @"SELECT", @"INSERT", @"UPDATE" ])
        [list addItem:[[[WebHistoryItem alloc] initWithURLString:[@"applewebdata://" stringByAppendingString:word]
                                                            title:word
                                          lastVisitedTimeInterval:0] autorelease]];
    printf("  three added: current %s, back %d forward %d\n", [[[list currentItem] title] UTF8String],
           [list backListCount], [list forwardListCount]);
    [list goBack];
    [list goBack];
    printf("  back twice: current %s, forward %s, back %d forward %d\n", [[[list currentItem] title] UTF8String],
           [[[list forwardItem] title] UTF8String], [list backListCount], [list forwardListCount]);
    [list addItem:a];
    printf("  added after going back: %s, forward %d, list %s\n", [[[list currentItem] title] UTF8String],
           [list forwardListCount],
           [[[[list backListWithLimit:10] valueForKey:@"title"] componentsJoinedByString:@" "] UTF8String]);
    [list setCapacity:1];
    printf("  capacity 1: back %d, contains the first %d\n", [list backListCount], [list containsItem:a]);
}

static int framePosts;
@interface FrameWatcher : NSObject
@end
@implementation FrameWatcher
- (void)changed:(NSNotification *)n { framePosts++; }
@end

static void newer(void)
{
    printf("more of NSCell:\n");
    NSCell *c = [[[NSCell alloc] initTextCell:@"tab"] autorelease];
    [c setRepresentedObject:@"the tab's item"];
    printf("  represented object: %s, type %d\n", [[c representedObject] UTF8String], (int)[c type]);
    [c setIntegerValue:42];
    printf("  integer 42: string %s, float %.1f\n", [[c stringValue] UTF8String], [c floatValue]);
    [c setDoubleValue:2.5];
    printf("  double 2.5: %s\n", [[c stringValue] UTF8String]);
    NSCell *other = [[[NSCell alloc] initTextCell:@"b"] autorelease];
    [other takeStringValueFrom:c];
    printf("  taken: %s, compare %ld\n", [[other stringValue] UTF8String], (long)[c compare:other]);
    printf("  image cell type: %d\n", (int)[[[[NSCell alloc] initImageCell:[NSImage imageNamed:NSImageNameFolder]]
                                                 autorelease] type]);
    [c setState:NSControlStateValueOff];
    [c setAllowsMixedState:YES];
    printf("  states: next of off %ld", (long)[c nextState]);
    [c setNextState];
    printf(", next of on %ld", (long)[c nextState]);
    [c setNextState];
    printf(", then %ld\n", (long)[c nextState]);
    [c setSendsActionOnEndEditing:YES];
    [c setRefusesFirstResponder:YES];
    [c setFocusRingType:NSFocusRingTypeNone];
    printf("  kept: ends editing %d, refuses %d (accepts %d), focus ring %lu, old mask %ld\n",
           [c sendsActionOnEndEditing], [c refusesFirstResponder], [c acceptsFirstResponder],
           (unsigned long)[c focusRingType], (long)[c sendActionOn:4]);
    NSCell *t = [[[NSCell alloc] initTextCell:@"plain"] autorelease];
    [t performClick:nil];
    printf("  a text cell's click leaves its state: %ld\n", (long)[t state]);

    printf("graphics port and layout:\n");
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:4 pixelsHigh:4
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0] autorelease];
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    printf("  port is the CG context: %d\n", g && [g graphicsPort] == (void *)[g CGContext]);
    NSLayoutManager *lm = [[[NSLayoutManager alloc] init] autorelease];
    printf("  background layout: %d", [lm backgroundLayoutEnabled]);
    [lm setBackgroundLayoutEnabled:NO];
    printf(", then %d\n", [lm backgroundLayoutEnabled]);

    printf("frame notifications:\n");
    NSView *v = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
    FrameWatcher *fw = [[[FrameWatcher alloc] init] autorelease];
    [[NSNotificationCenter defaultCenter] addObserver:fw selector:@selector(changed:)
                                                 name:NSViewFrameDidChangeNotification object:v];
    [v setFrame:NSMakeRect(0, 0, 10, 10)];
    printf("  the same frame: %d posted\n", framePosts);
    [v setFrame:NSMakeRect(5, 0, 10, 10)];
    [v setFrame:NSMakeRect(5, 0, 20, 10)];
    printf("  two changes: %d posted\n", framePosts);
    [[NSNotificationCenter defaultCenter] removeObserver:fw];

    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50) styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered defer:NO];
    [w setAlphaValue:0];
    printf("  window alpha: %.1f\n", [w alphaValue]);
    [w release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        names();
        hfs_types();
        color_lists();
        base_coordinates();
        glyphs();
        cells_and_matrices();
        history();
        newer();
    }
    return 0;
}
