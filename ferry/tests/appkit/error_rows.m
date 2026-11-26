/* SPDX-License-Identifier: GPL-3.0-or-later
 * VLC's Errors and Warnings window (freemac 1.NEXT): a cell-based table
 * with 45-point rows, an icon column filled from
 * iconForFileType:NSFileTypeForHFSTypeCode(kAlertStopIcon), and text cells
 * holding "Title\nmessage". A Mac shows the alert icon and the title and
 * message on two lines; Ferry showed a blank document icon and one line
 * with the line break drawn as a glyph. */
#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>

@interface Source : NSObject <NSTableViewDataSource>
@end
@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 1; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return @"Your input can't be opened\nVLC is unable to open the file.";
}
@end

static CGFloat lum(NSBitmapImageRep *rep, NSInteger x, NSInteger y)
{
    NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    CGFloat a = [c alphaComponent];
    return a * (0.3 * [c redComponent] + 0.59 * [c greenComponent] + 0.11 * [c blueComponent]) + (1 - a);
}

static void icons(void)
{
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSImage *stop = [ws iconForFileType:NSFileTypeForHFSTypeCode(kAlertStopIcon)];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[stop TIFFRepresentation]];
    NSColor *edge = [[rep colorAtX:(NSInteger)(rep.pixelsWide * 0.2) y:rep.pixelsHigh / 2]
        colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    NSColor *mid = [[rep colorAtX:rep.pixelsWide / 2 y:rep.pixelsHigh / 2]
        colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    printf("stop icon: %.0fx%.0f, red %d, white bar %d\n", [stop size].width, [stop size].height,
           [edge redComponent] > 0.7 && [edge greenComponent] < 0.3, [mid greenComponent] > 0.9);
    printf("caution icon: %d, note icon: %d\n",
           [ws iconForFileType:NSFileTypeForHFSTypeCode(kAlertCautionIcon)] == [NSImage imageNamed:NSImageNameCaution],
           [ws iconForFileType:NSFileTypeForHFSTypeCode(kAlertNoteIcon)] == [NSImage imageNamed:NSImageNameInfo]);
}

/* the bands of rows with ink in them, in the cell's column */
static void lines(BOOL single)
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 60) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:YES];
    NSTableView *t = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 320, 60)];
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"error_msg"];
    [c setWidth:300];
    NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
    [cell setFont:[NSFont systemFontOfSize:11]];
    [cell setUsesSingleLineMode:single];
    [c setDataCell:cell];
    [t addTableColumn:c];
    [t setHeaderView:nil];
    [t setRowHeight:45];
    Source *src = [Source new];
    [t setDataSource:src];
    [[w contentView] addSubview:t];
    [t reloadData];
    NSBitmapImageRep *rep = [t bitmapImageRepForCachingDisplayInRect:[t bounds]];
    [t cacheDisplayInRect:[t bounds] toBitmapImageRep:rep];
    int bands = 0;
    BOOL was = NO;
    for (NSInteger y = 0; y < 47 && y < rep.pixelsHigh; y++) {
        BOOL ink = NO;
        for (NSInteger x = 4; x < 200 && !ink; x++)
            ink = lum(rep, x, y) < 0.5;
        if (ink && !was)
            bands++;
        was = ink;
    }
    printf("%s: %d line%s\n", single ? "single-line mode" : "text cell", bands, bands == 1 ? "" : "s");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        icons();
        lines(NO);
        lines(YES);
    }
    return 0;
}
