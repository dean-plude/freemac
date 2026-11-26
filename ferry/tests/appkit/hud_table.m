/* SPDX-License-Identifier: GPL-3.0-or-later
 * A table with a header in a scroll view with a border, in a HUD
 * panel (freemac 1.NEXT), as VLC's Bookmarks window has one. A Mac draws
 * the header dark there, its titles light, and the border a faint line;
 * Ferry drew a white header band and a light frame on the dark panel.
 * The same table in an ordinary window keeps its light header. */
#import <Cocoa/Cocoa.h>

/* a pixel's lightness as it shows, over the window's background */
static CGFloat lum(NSBitmapImageRep *rep, NSInteger x, NSInteger y, CGFloat under)
{
    NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    CGFloat a = [c alphaComponent];
    return a * (0.3 * [c redComponent] + 0.59 * [c greenComponent] + 0.11 * [c blueComponent]) + (1 - a) * under;
}

static void check(NSUInteger style, const char *name)
{
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:style
                                              backing:NSBackingStoreBuffered defer:YES];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 260, 160)];
    [sv setBorderType:NSBezelBorder];
    NSTableView *t = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 258, 140)];
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"d"];
    [[c headerCell] setStringValue:@"Description"];
    [c setWidth:240];
    [t addTableColumn:c];
    [sv setDocumentView:t];
    [[p contentView] addSubview:sv];
    NSView *v = [p contentView];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    /* the header band's top rows, right of its title; the panel's own colour beside the scroll view */
    NSRect h = [[t headerView] convertRect:[[t headerView] bounds] toView:v];
    NSInteger hy = (NSInteger)(NSHeight([v bounds]) - NSMaxY(h) + 3);
    if ([v isFlipped])
        hy = (NSInteger)(NSMinY(h) + 3);
    CGFloat under = 1, alpha;
    [[[p backgroundColor] colorUsingColorSpace:[NSColorSpace genericGrayColorSpace]] getWhite:&under alpha:&alpha];
    CGFloat header = lum(rep, 200, hy, under), panel = lum(rep, 8, 100, under), border = lum(rep, 20, 100, under);
    printf("%s: header %s", name, header < 0.5 ? "dark" : "light");
    if (panel < 0.5)   /* on the dark panel a light frame stands out; a faint line doesn't */
        printf(", border %s", fabs(border - panel) < 0.25 ? "faint" : "a light frame");
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        check(NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskHUDWindow, "HUD panel");
        check(NSWindowStyleMaskTitled, "ordinary window");
    }
    return 0;
}
